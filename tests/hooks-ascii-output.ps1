# TEST (e2e): no omnilog hook writes a non-ASCII byte, even when fed a Unicode payload.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8   # deliver UTF-8 to child stdin

$U = 'em' + [char]0x2014 + 'dash ' + [char]0x201C + 'q' + [char]0x201D + ' caf' + [char]0xE9 +
     ' ' + [char]0x65E5 + [char]0x672C + [char]0x8A9E + ' ' + [char]::ConvertFromUtf32(0x1F680) + ' end' + [char]0x2026

$log = Join-Path $env:TEMP ("omni-ascii-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
function Fire($s, $j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks $s) }

Fire 'omnilog-tool.ps1' ('{"tool_name":"Bash","tool_input":{"description":"' + $U + '"}}')
Fire 'omnilog-tool.ps1' ('{"tool_name":"Grep","tool_input":{"pattern":"' + $U + '"}}')
Fire 'omnilog-tool.ps1' ('{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","description":"' + $U + '"},"tool_response":"agentId: a4864e002ce7efac2"}')
Fire 'omnilog-subagentstop.ps1' ('{"agent_id":"a4864e002ce7efac2","agent_type":"' + $U + '"}')
Remove-Item Env:\OMNILOG_FILE

if (-not (Test-Path -LiteralPath $log)) { Write-Output 'FAIL  no output produced (hooks wrote nothing)'; exit 1 }
Write-Output '--- hook output (len | line) ---'
Get-Content -LiteralPath $log -Encoding ASCII | ForEach-Object { '{0,3} | {1}' -f $_.Length, $_ }

$bytes = [System.IO.File]::ReadAllBytes($log)
$badBytes = @($bytes | Where-Object { $_ -gt 127 })
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

$ok = $true
if ($badBytes.Count -gt 0) { Write-Output ("FAIL  {0} non-ASCII byte(s)" -f $badBytes.Count); $ok = $false }
if ($ok) { Write-Output ("PASS  hooks-ascii-output ({0} bytes, all ASCII)" -f $bytes.Length); exit 0 }
exit 1
