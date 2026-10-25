# TEST: every hook line matches the omnilog format  [yy-MM-dd HH:mm] <text> <tag>
# Pins the timestamp shape - including the ':' in HH:mm - and the trailing <tag>.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$log = Join-Path $env:TEMP ("omni-fmt-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
function Fire($s, $j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks $s) }

Fire 'omnilog-tool.ps1' '{"tool_name":"Bash","tool_input":{"description":"do a thing"}}'
Fire 'omnilog-tool.ps1' '{"tool_name":"AskUserQuestion","tool_input":{"questions":[]}}'   # no-detail line
Fire 'omnilog-subagentstop.ps1' '{"agent_id":"a4864e002ce7efac2","agent_type":"Explore"}'
$fx = Join-Path $root 'evals\fixtures\C--Users-jared-Projects-skill-jagp-copy-template-skeleton__d7093b8d.jsonl'
if (Test-Path -LiteralPath $fx) { Fire 'omnilog-stop.ps1' ('{"transcript_path":"' + $fx.Replace('\', '\\') + '","stop_hook_active":false}') }
Remove-Item Env:\OMNILOG_FILE

if (-not (Test-Path -LiteralPath $log)) { Write-Output 'FAIL  no output produced'; exit 1 }
$pattern = '^\[\d{2}-\d{2}-\d{2} \d{2}:\d{2}\] .*<[^<>]+>$'
$lines = Get-Content -LiteralPath $log
$bad = @($lines | Where-Object { $_ -notmatch $pattern })
Write-Output '--- lines ---'
$lines | ForEach-Object { Write-Output ("  {0}" -f $_) }
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

if ($bad.Count -eq 0) { Write-Output ("PASS  line-format ({0} lines match [yy-MM-dd HH:mm] ... <tag>)" -f $lines.Count); exit 0 }
Write-Output ("FAIL  line-format: {0} off-format line(s):" -f $bad.Count)
$bad | ForEach-Object { Write-Output ("  {0}" -f $_) }
exit 1
