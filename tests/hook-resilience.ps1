# TEST (unit + e2e): file-creation edge cases. The hooks are silent observers, so
# "didn't crash" is table stakes -- these cases pin the useful half: the write
# SUCCEEDS when it reasonably can (missing parent dir gets created), and when it
# truly cannot (read-only file, locked file, target-is-a-directory) the hook still
# exits 0 and corrupts nothing. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'
. (Join-Path $hooks 'ado-lib.ps1')   # also dot-sources omnilog-lib.ps1

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}
function FireTool($j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'omnilog-tool.ps1'); return $LASTEXITCODE }
function FireAdo($j)  { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'ado-tool.ps1');     return $LASTEXITCODE }

$sandbox = Join-Path $env:TEMP ("omni-resil-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
Remove-Item Env:\OMNILOG_FILE, Env:\ADO_FILE, Env:\ADO_SCOPE -ErrorAction SilentlyContinue

# 1) omnilog target in a directory that does not exist yet -> dir is created, line lands.
#    (A 'path:' config or OMNILOG_FILE pointing into a fresh folder must not silently
#    drop every line forever.)
$deep = Join-Path $sandbox 'not\yet\made\omnilog.md'
$env:OMNILOG_FILE = $deep
$rc = FireTool '{"tool_name":"Bash","tool_input":{"description":"deep write"}}'
Check 'missing parent dir: exit 0'      ($rc -eq 0)
Check 'missing parent dir: dir created' (Test-Path -LiteralPath (Split-Path $deep -Parent))
Check 'missing parent dir: line lands'  ((Test-Path -LiteralPath $deep) -and ((Get-Content -Raw -LiteralPath $deep) -match 'deep write'))

# 2) read-only target file -> exit 0, file content untouched (not truncated/corrupted)
$ro = Join-Path $sandbox 'readonly.md'
Set-Content -LiteralPath $ro -Value '[26-01-01 00:00] existing line <Bash>' -Encoding ASCII
Set-ItemProperty -LiteralPath $ro -Name IsReadOnly -Value $true
$env:OMNILOG_FILE = $ro
$rc = FireTool '{"tool_name":"Bash","tool_input":{"description":"should not land"}}'
Set-ItemProperty -LiteralPath $ro -Name IsReadOnly -Value $false
Check 'read-only: exit 0'            ($rc -eq 0)
Check 'read-only: content untouched' ((Get-Content -Raw -LiteralPath $ro) -match 'existing line')
Check 'read-only: nothing appended'  (-not ((Get-Content -Raw -LiteralPath $ro) -match 'should not land'))

# 3) target path is an existing DIRECTORY named omnilog.md -> exit 0, no crash
$dirTarget = Join-Path $sandbox 'omnilog.md'
New-Item -ItemType Directory -Path $dirTarget -Force | Out-Null
$env:OMNILOG_FILE = $dirTarget
$rc = FireTool '{"tool_name":"Bash","tool_input":{"description":"into a dir"}}'
Check 'dir-as-target: exit 0'        ($rc -eq 0)
Check 'dir-as-target: still a dir'   ((Get-Item -LiteralPath $dirTarget) -is [System.IO.DirectoryInfo])

# 4) exclusively locked target -> exit 0, lock holder unaffected
$locked = Join-Path $sandbox 'locked.md'
Set-Content -LiteralPath $locked -Value 'held' -Encoding ASCII
$fs = [System.IO.File]::Open($locked, 'Open', 'ReadWrite', [System.IO.FileShare]::None)
try {
  $env:OMNILOG_FILE = $locked
  $rc = FireTool '{"tool_name":"Bash","tool_input":{"description":"blocked"}}'
} finally { $fs.Dispose() }
Check 'locked file: exit 0' ($rc -eq 0)

# 5) ado target in a missing directory -> dir created, board written (pins existing behavior)
$adoDeep = Join-Path $sandbox 'fresh\.claude\task.ado'
$env:ADO_FILE = $adoDeep
$rc = FireAdo '{"tool_name":"TaskCreate","tool_input":{"subject":"deep board"},"tool_response":"Task #1 created successfully"}'
Check 'ado missing dir: exit 0'       ($rc -eq 0)
Check 'ado missing dir: board lands'  ((Test-Path -LiteralPath $adoDeep) -and ((Get-Content -Raw -LiteralPath $adoDeep) -match 'deep board'))

# 6) ado target is a directory -> exit 0, no crash, dir intact
$adoDir = Join-Path $sandbox 'task.ado'
New-Item -ItemType Directory -Path $adoDir -Force | Out-Null
$env:ADO_FILE = $adoDir
$rc = FireAdo '{"tool_name":"TaskCreate","tool_input":{"subject":"nope"},"tool_response":"Task #2 created successfully"}'
Check 'ado dir-as-target: exit 0'      ($rc -eq 0)
Check 'ado dir-as-target: still a dir' ((Get-Item -LiteralPath $adoDir) -is [System.IO.DirectoryInfo])

Remove-Item Env:\OMNILOG_FILE, Env:\ADO_FILE -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  hook-resilience'; exit 0 }
Write-Output ("FAIL  hook-resilience ({0} case(s))" -f $fail); exit 1
