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

function Resolve-OmnilogPath {
  if ($env:OMNILOG_FILE) { return $env:OMNILOG_FILE }
  if ($env:CLAUDE_PROJECT_DIR) { return (Join-Path $env:CLAUDE_PROJECT_DIR 'omnilog.md') }
  return (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'omnilog.md')
}

function Write-OmnilogEntry([string]$detail, [string]$tag, [int]$max = 78) {
  # Sanitize BEFORE measuring so the width budget is computed on the final ASCII text.
  $detail = (ConvertTo-Ascii $detail) -replace '\s+', ' '
  $detail = $detail.Trim()
  $tag = ConvertTo-Ascii $tag
  $ts = Get-Date -Format 'yy-MM-dd HHmm'
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
  Add-Content -LiteralPath (Resolve-OmnilogPath) -Encoding ASCII -Value $line
}
