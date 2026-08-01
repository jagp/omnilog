# Shared helpers for the omnilog hooks - the single source of truth for the log's
# invariants. Every hook reads stdin as UTF-8 and writes through Write-OmnilogEntry, which
# guarantees:
#   * ASCII-only  - common Unicode punctuation is transliterated, anything else -> '?',
#                   and the file is written with the ASCII encoder (belt + suspenders),
#                   so the log renders identically in every terminal / editor / git diff.
#   * one line    - whitespace (incl. newlines) collapses to single spaces; entries are
#                   never truncated, the full detail is kept however long.
# Verified by tests/omnilog-ascii.test.ps1.

function Read-HookStdin {
  # Read the hook payload as UTF-8 regardless of the console code page.
  $stdin = [Console]::OpenStandardInput()
  $sr = New-Object System.IO.StreamReader($stdin, [System.Text.Encoding]::UTF8)
  try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}

function ConvertTo-Ascii([string]$s) {
  if (-not $s) { return '' }
  # Whitespace controls (newline/tab/...) become spaces FIRST - the catch-all below
  # would otherwise turn them into '?' before callers can collapse them.
  $s = $s -replace '\s', ' '
  $s = $s.Replace([string][char]0x2026, '...')
  $s = $s.Replace([string][char]0x2014, '-').Replace([string][char]0x2013, '-')
  $s = $s.Replace([string][char]0x2018, "'").Replace([string][char]0x2019, "'")
  $s = $s.Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"')
  $s = $s.Replace([string][char]0x00A0, ' ').Replace([string][char]0x2022, '*')
  return ($s -replace '[^\x20-\x7E]', '?')   # keep printable ASCII only; anything else -> '?'
}

function Get-OmnilogConfig {
  # Reads .claude/omnilog.local.md frontmatter from the project dir.
  # Returns @{ scope = 'per-project'|'global'|'off'; path = <string|$null>;
  #            ado = $null|'on'|'off'; adoPath = <string|$null> }
  #   'ado:'      -- the task board's independent on/off switch.
  #   'ado-path:' -- explicit board location override (parity with omnilog 'path:').
  $scope = 'per-project'; $path = $null; $ado = $null; $adoPath = $null
  if ($env:CLAUDE_PROJECT_DIR) {
    $cfg = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\omnilog.local.md'
    if (Test-Path -LiteralPath $cfg) {
      # Unreadable config (locked/permission) -> defaults; never let config IO throw.
      $all = @(); try { $all = @(Get-Content -LiteralPath $cfg -ErrorAction Stop) } catch { $all = @() }
      # Honor keys ONLY inside the YAML frontmatter fence. Prose in the markdown
      # body (e.g. docs quoting "scope: off") must not flip the config. Files
      # without an opening '---' keep the lenient whole-file scan.
      $lines = $all
      if ($all.Count -gt 0 -and ($all[0] -replace [string][char]0xFEFF, '').Trim() -eq '---') {
        $close = -1
        for ($i = 1; $i -lt $all.Count; $i++) { if ($all[$i].Trim() -eq '---') { $close = $i; break } }
        if ($close -eq 1) { $lines = @() }                            # empty frontmatter
        elseif ($close -gt 1) { $lines = $all[1..($close - 1)] }
        # no closing fence: keep the whole-file scan (still just a frontmatter file)
      }
      foreach ($ln in $lines) {
        if ($ln -match '^\s*scope:\s*(\S+)') { $scope = $Matches[1].Trim('"').ToLower() }
        elseif ($ln -match '^\s*path:\s*(.+?)\s*$') { $path = $Matches[1].Trim().Trim('"') }
        elseif ($ln -match '^\s*ado-path:\s*(.+?)\s*$') { $adoPath = $Matches[1].Trim().Trim('"') }
        elseif ($ln -match '^\s*ado:\s*(\S+)') { $ado = $Matches[1].Trim('"').ToLower() }
      }
    }
  }
  return @{ scope = $scope; path = $path; ado = $ado; adoPath = $adoPath }
}

function Resolve-OmnilogTarget {
  # The log path, or $null meaning "do not log".
  # Highest-priority override (tests + power users). Trimmed: a whitespace-only
  # value leaked by a wrapper/other tool must not become a "path" of spaces.
  $ov = [string]$env:OMNILOG_FILE
  if ($ov -and $ov.Trim()) { return $ov.Trim() }
  $cfg = Get-OmnilogConfig
  switch ($cfg.scope) {
    'off' { return $null }
    'global' {
      if ($cfg.path) { return $cfg.path }
      $base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR }
              elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude' }
              else { $HOME }
      return (Join-Path $base 'omnilog.md')
    }
    default {
      # 'per-project' (and any unrecognized value): log only if the project opted in
      # by having an omnilog.md marker.
      if ($env:CLAUDE_PROJECT_DIR) {
        $marker = Join-Path $env:CLAUDE_PROJECT_DIR 'omnilog.md'
        if (Test-Path -LiteralPath $marker) { return $marker }
        return $null
      }
      # Fallback (no CLAUDE_PROJECT_DIR): the runtime working directory, never the
      # plugin's own dir. Anchoring to $PWD keeps an installed plugin logging into
      # the calling project rather than the plugin cache.
      return (Join-Path (Get-Location).Path 'omnilog.md')
    }
  }
}

function Write-OmnilogEntry([string]$detail, [string]$tag) {
  $target = Resolve-OmnilogTarget
  if (-not $target) { return }   # scope=off, or per-project with no opt-in marker
  # A 'path:'/OMNILOG_FILE aimed into a not-yet-created folder must not silently
  # drop every line forever - create the parent dir (parity with Write-AdoMirror).
  $dir = Split-Path $target -Parent
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $detail = (ConvertTo-Ascii $detail) -replace '\s+', ' '
  $detail = $detail.Trim()
  $tag = ConvertTo-Ascii $tag
  $ts = Get-Date -Format 'yy-MM-dd HH:mm'
  if (-not $detail) { $line = "[$ts] <$tag>" }
  else { $line = "[$ts] $detail <$tag>" }
  Add-Content -LiteralPath $target -Encoding ASCII -Value $line
}
