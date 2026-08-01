# TEST (e2e): installed-plugin portability. When Claude Code installs the plugin,
# the scripts run from a cache directory (NOT this repo) whose path contains
# spaces. Copy the shipped scripts to such a path and prove the hooks still work
# end-to-end -- catching any accidental dependency on the repo layout or on
# space-free paths. Also runs the lib under pwsh (PowerShell 7) when available,
# since users may swap the hook command to pwsh. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}

Remove-Item Env:\OMNILOG_FILE, Env:\ADO_FILE, Env:\ADO_SCOPE -ErrorAction SilentlyContinue

# --- relocate the scripts to a path with spaces (simulated plugin cache) ----------
$fake = Join-Path $env:TEMP ("dev strap cache {0}\hooks\scripts" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
New-Item -ItemType Directory -Path $fake -Force | Out-Null
Copy-Item -Path (Join-Path $hooks '*.ps1') -Destination $fake

$log = Join-Path $env:TEMP ("omni-port-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log
'{"tool_name":"Bash","tool_input":{"description":"from spaced path"}}' |
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fake 'omnilog-tool.ps1')
Check 'spaced path: omnilog hook exit 0' ($LASTEXITCODE -eq 0)
Check 'spaced path: line written'        ((Test-Path -LiteralPath $log) -and ((Get-Content -Raw -LiteralPath $log) -match 'from spaced path'))
Remove-Item Env:\OMNILOG_FILE

$ado = Join-Path $env:TEMP ("ado-port-{0}.ado" -f ([guid]::NewGuid().ToString('N')))
$env:ADO_FILE = $ado
'{"tool_name":"TaskCreate","tool_input":{"subject":"spaced board"},"tool_response":"Task #1 created successfully"}' |
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fake 'ado-tool.ps1')
Check 'spaced path: ado hook exit 0' ($LASTEXITCODE -eq 0)
Check 'spaced path: board written'   ((Test-Path -LiteralPath $ado) -and ((Get-Content -Raw -LiteralPath $ado) -match 'spaced board'))
Remove-Item Env:\ADO_FILE

# --- scripts must not silently depend on the caller's working directory -----------
# (hooks run with an arbitrary cwd; only CLAUDE_PROJECT_DIR / env overrides count)
$cwd = Join-Path $env:TEMP ("omni-port-cwd-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $cwd -Force | Out-Null
Push-Location $cwd
try {
  $log2 = Join-Path $env:TEMP ("omni-port2-{0}.md" -f ([guid]::NewGuid().ToString('N')))
  $env:OMNILOG_FILE = $log2
  '{"tool_name":"Bash","tool_input":{"description":"cwd independent"}}' |
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fake 'omnilog-tool.ps1')
  Check 'foreign cwd: line written' ((Test-Path -LiteralPath $log2) -and ((Get-Content -Raw -LiteralPath $log2) -match 'cwd independent'))
  Remove-Item Env:\OMNILOG_FILE
  Remove-Item -LiteralPath $log2 -ErrorAction SilentlyContinue
} finally { Pop-Location }

# --- optional: same lib behavior under pwsh (PowerShell 7+) -----------------------
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) {
  $probe = '. ''' + (Join-Path $hooks 'omnilog-lib.ps1') + '''; ConvertTo-Ascii ("caf" + [char]0xE9 + [char]0x2014 + "x")'
  $out = & pwsh -NoProfile -Command $probe
  Check 'pwsh: ConvertTo-Ascii parity' ($out -eq 'caf?-x')
} else {
  Write-Output '  skip pwsh parity (pwsh not installed)'
}

Remove-Item -LiteralPath (Split-Path (Split-Path $fake -Parent) -Parent) -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $log, $ado -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  portability'; exit 0 }
Write-Output ("FAIL  portability ({0} case(s))" -f $fail); exit 1
