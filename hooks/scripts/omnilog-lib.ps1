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
  #            ado = $null|'on'|'off' } ('ado:' is the task board's independent switch).
  $scope = 'per-project'; $path = $null; $ado = $null
  if ($env:CLAUDE_PROJECT_DIR) {
    $cfg = Join-Path $env:CLAUDE_PROJECT_DIR '.claude\omnilog.local.md'
    if (Test-Path -LiteralPath $cfg) {
      foreach ($ln in (Get-Content -LiteralPath $cfg)) {
        if ($ln -match '^\s*scope:\s*(\S+)') { $scope = $Matches[1].Trim('"').ToLower() }
        elseif ($ln -match '^\s*path:\s*(.+?)\s*$') { $path = $Matches[1].Trim().Trim('"') }
        elseif ($ln -match '^\s*ado:\s*(\S+)') { $ado = $Matches[1].Trim('"').ToLower() }
      }
    }
  }
  return @{ scope = $scope; path = $path; ado = $ado }
}

function Resolve-OmnilogTarget {
  # The log path, or $null meaning "do not log".
  if ($env:OMNILOG_FILE) { return $env:OMNILOG_FILE }   # highest-priority override (tests + power users)
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
      # Dev fallback (no CLAUDE_PROJECT_DIR): repo root two levels up from this lib.
      return (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'omnilog.md')
    }
  }
}

function Write-OmnilogEntry([string]$detail, [string]$tag, [int]$max = 78) {
  $target = Resolve-OmnilogTarget
  if (-not $target) { return }   # scope=off, or per-project with no opt-in marker
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
