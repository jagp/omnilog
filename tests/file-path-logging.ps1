# TEST: file tools log the file's path relative to CLAUDE_PROJECT_DIR, not just its leaf
# name. Paths outside the project - including a sibling dir that merely shares its name
# prefix - are logged unchanged. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$log = Join-Path $env:TEMP ("omni-path-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log                      # log target (beats the project dir below)
$env:CLAUDE_PROJECT_DIR = 'C:\fake\proj'      # only used as the anchor for relative paths
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

# Each case: the tool, file_path as the model sent it, and the detail expected in the log.
$cases = @(
  @{ tool = 'Read';  path = 'C:\fake\proj\hooks\scripts\omnilog-tool.ps1'; want = 'hooks\scripts\omnilog-tool.ps1' }
  @{ tool = 'Edit';  path = 'c:/Fake/Proj/src/app.ts';                     want = 'src/app.ts' }            # case + slash insensitive
  @{ tool = 'Write'; path = 'D:\elsewhere\notes.md';                       want = 'D:\elsewhere\notes.md' } # outside project: unchanged
  @{ tool = 'Write'; path = 'C:\fake\proj2\x.md';                          want = 'C:\fake\proj2\x.md' }    # prefix-sharing sibling: unchanged
)
foreach ($c in $cases) {
  @{ tool_name = $c.tool; tool_input = @{ file_path = $c.path } } | ConvertTo-Json -Compress |
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'omnilog-tool.ps1')
}
Remove-Item Env:\OMNILOG_FILE, Env:\CLAUDE_PROJECT_DIR

$lines = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log })
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
$fail = 0
for ($i = 0; $i -lt $cases.Count; $i++) {
  $want = '] {0} <{1}>' -f $cases[$i].want, $cases[$i].tool   # line tail after the timestamp
  $got = if ($i -lt $lines.Count) { $lines[$i] } else { '<missing>' }
  if ($got.EndsWith($want)) { Write-Output ("  ok    {0}" -f $got) }
  else { Write-Output ("  FAIL  expected ...{0}  got: {1}" -f $want, $got); $fail++ }
}
if ($fail -eq 0) { Write-Output ("PASS  file-path-logging ({0} cases)" -f $cases.Count); exit 0 }
Write-Output ("FAIL  file-path-logging: {0} of {1} case(s)" -f $fail, $cases.Count)
exit 1
