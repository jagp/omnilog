# Shared helpers for the omnilog hooks - the single source of truth for the log's
# invariants. Every hook reads stdin as UTF-8 and writes through Write-OmnilogEntry, which
# guarantees:
#   * ASCII-only  - common Unicode punctuation is transliterated, anything else -> '?',
#                   and the file is written with the ASCII encoder (belt + suspenders),
#                   so the log renders identically in every terminal / editor / git diff.
#   * <= 78 chars - the whole line fits a standard terminal, ellipsed with ASCII '...'.
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

function ConvertTo-OmnilogBool([string]$v) {
  # Accepts the usual spellings from config files and env vars.
  # Returns $true/$false, or $null when the value is unrecognized (treat as unset).
  if ($null -eq $v) { return $null }
  switch ($v.Trim().Trim('"').ToLower()) {
    { $_ -in @('false', 'off', 'no', '0', 'disabled') } { return $false }
    { $_ -in @('true', 'on', 'yes', '1', 'enabled') } { return $true }
    default { return $null }
  }
}

function Get-OmnilogConfig {
  # Reads .claude/omnilog.local.md frontmatter from the project dir.
  # Returns @{ scope = 'per-project'|'global'|'off'; path = <string|$null>;
  #            ado = $null|'on'|'off'; adoPath = <string|$null>;
  #            enabled = $null|$true|$false }
  #   'enabled:'  -- explicit master on/off switch ($null = unset = on).
  #   'ado:'      -- the task board's independent on/off switch.
  #   'ado-path:' -- explicit board location override (parity with omnilog 'path:').
  $scope = 'per-project'; $path = $null; $ado = $null; $adoPath = $null; $enabled = $null
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
        elseif ($ln -match '^\s*enabled:\s*(\S+)') { $enabled = (ConvertTo-OmnilogBool $Matches[1]) }
      }
    }
  }
  return @{ scope = $scope; path = $path; ado = $ado; adoPath = $adoPath; enabled = $enabled }
}

function Resolve-OmnilogTarget {
  # The log path, or $null meaning "do not log".
  # Order: OMNILOG_ENABLED=off (master kill switch, beats everything) > OMNILOG_FILE
  # > config 'enabled: false' > scope.
  if ((ConvertTo-OmnilogBool $env:OMNILOG_ENABLED) -eq $false) { return $null }
  if ($env:OMNILOG_FILE) { return $env:OMNILOG_FILE }   # explicit path override (tests + power users)
  # Highest-priority override (tests + power users). Trimmed: a whitespace-only
  # value leaked by a wrapper/other tool must not become a "path" of spaces.
  $ov = [string]$env:OMNILOG_FILE
  if ($ov -and $ov.Trim()) { return $ov.Trim() }
  $cfg = Get-OmnilogConfig
  if ($cfg.enabled -eq $false) { return $null }         # explicit opt-out, any scope
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
      # 'per-project' (and any unrecognized value): the calling project's own log.
      # No marker gate -- the file is seeded on first write (see Write-OmnilogEntry).
      # Turn logging off with 'enabled: false', 'scope: off', or OMNILOG_ENABLED=off.
      if ($env:CLAUDE_PROJECT_DIR) {
        return (Join-Path $env:CLAUDE_PROJECT_DIR 'omnilog.md')
      }
      # Fallback (no CLAUDE_PROJECT_DIR): the runtime working directory, never the
      # plugin's own dir. Anchoring to $PWD keeps an installed plugin logging into
      # the calling project rather than the plugin cache.
      return (Join-Path (Get-Location).Path 'omnilog.md')
    }
  }
}

function Initialize-OmnilogFile([string]$target) {
  # Seed a fresh, empty log in the calling project if one does not exist yet.
  # Best-effort: a hook must never break a session, so failures are swallowed.
  if (-not $target) { return }
  try {
    if (-not (Test-Path -LiteralPath $target)) {
      $dir = Split-Path -Parent $target
      if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
      }
      New-Item -ItemType File -Force -Path $target | Out-Null
    }
  }
  catch { }
}

function Write-OmnilogEntry([string]$detail, [string]$tag, [int]$max = 78) {
  $target = Resolve-OmnilogTarget
  if (-not $target) { return }   # scope=off, or per-project with no opt-in marker
  Initialize-OmnilogFile $target


  $dir = Split-Path $target -Parent
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  # Sanitize BEFORE measuring so the width budget is computed on the final ASCII text.
  $detail = (ConvertTo-Ascii $detail) -replace '\s+', ' '
  $detail = $detail.Trim()
  $tag = ConvertTo-Ascii $tag
  $ts = Get-Date -Format 'yy-MM-dd HH:mm'
  $budget = $max - "[$ts] ".Length - " <$tag>".Length
  if ($budget -lt 5 -or -not $detail) {
    $line = "[$ts] <$tag>"
  }
  elseif ($detail.Length -gt $budget) {
    $line = "[$ts] " + $detail.Substring(0, $budget - 3) + '...' + " <$tag>"
  }
  else {
    $line = "[$ts] $detail <$tag>"
  }
  Add-Content -LiteralPath $target -Encoding ASCII -Value $line
}
