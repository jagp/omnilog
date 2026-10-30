# TEST: the Stop line's token cost is the REAL turn cost. Walking the transcript back to
# the turn's prompt, it sums output_tokens once per requestId (one JSONL line per content
# block repeats the same usage), skips <synthetic> messages, treats tool_result user lines
# as mid-turn, and stops at the real prompt so earlier turns don't leak in. No usage at all
# means no :cost suffix -- never ':0'. Also pins Glob logging its pattern. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}
function Fire($s, $j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks $s); return $LASTEXITCODE }
function FireStop($tp) { Fire 'omnilog-stop.ps1' ('{"transcript_path":"' + $tp.Replace('\', '\\') + '","stop_hook_active":false}') }

Remove-Item Env:\OMNILOG_FILE -ErrorAction SilentlyContinue
$log = Join-Path $env:TEMP ("omni-cost-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$tp  = Join-Path $env:TEMP ("omni-cost-t-{0}.jsonl" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log
function LastLine { @(Get-Content -LiteralPath $log)[-1] }

# 1) dedupe + synthetic + tool_result + turn boundary: expect 50 + 30 = 80, 2 tool calls
@(
  '{"type":"user","message":{"content":"earlier prompt"}}'
  '{"type":"assistant","requestId":"r0","message":{"model":"m","usage":{"output_tokens":1000},"content":[]}}'
  '{"type":"user","message":{"content":"current prompt"}}'
  '{"type":"assistant","requestId":"r1","message":{"model":"m","usage":{"output_tokens":50},"content":[{"type":"tool_use","id":"t1"}]}}'
  '{"type":"assistant","requestId":"r1","message":{"model":"m","usage":{"output_tokens":50},"content":[{"type":"text","text":"same request"}]}}'
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'
  '{"type":"assistant","requestId":"r2","message":{"model":"m","usage":{"output_tokens":30},"content":[{"type":"tool_use","id":"t2"}]}}'
  '{"type":"assistant","requestId":"r3","message":{"model":"<synthetic>","usage":{"output_tokens":999},"content":[]}}'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = FireStop $tp
Check 'cost: exit 0'                   ($rc -eq 0)
Check 'cost: deduped, synthetic out'   ((LastLine) -match '<Stop:80>$')
Check 'cost: tool calls counted'       ((LastLine) -match 'response - 2 tool call\(s\)')

# 2) no usage anywhere in the turn -> bare <Stop>, never <Stop:0>
@(
  '{"type":"user","message":{"content":"prompt"}}'
  '{"type":"assistant","requestId":"r9","message":{"model":"m","content":[]}}'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = FireStop $tp
Check 'no usage: exit 0'       ($rc -eq 0)
Check 'no usage: bare <Stop>'  ((LastLine) -match '<Stop>$')

# 2b) usage present but output_tokens missing (schema drift) -> bare <Stop>, never <Stop:0>
@(
  '{"type":"user","message":{"content":"prompt"}}'
  '{"type":"assistant","requestId":"r9","message":{"model":"m","usage":{"input_tokens":5},"content":[]}}'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = FireStop $tp
Check 'no output_tokens: exit 0'       ($rc -eq 0)
Check 'no output_tokens: bare <Stop>'  ((LastLine) -match '<Stop>$')

# 2c) isMeta user lines injected MID-turn (skill body after a Skill call, with or without
#     sourceToolUseID) must not end the walk: expect 10 + 20 + 40 = 70, 2 tool calls. An
#     isMeta line that opens a turn (peer message after a finished reply) still ends it.
@(
  '{"type":"user","message":{"content":"earlier prompt"}}'
  '{"type":"assistant","requestId":"r0","message":{"model":"m","usage":{"output_tokens":1000},"content":[{"type":"text","text":"done"}]}}'
  '{"type":"user","isMeta":true,"message":{"content":"peer message opens this turn"}}'
  '{"type":"assistant","requestId":"r1","message":{"model":"m","usage":{"output_tokens":10},"content":[{"type":"tool_use","id":"t1"}]}}'
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'
  '{"type":"user","isMeta":true,"sourceToolUseID":"t1","message":{"content":"skill body"}}'
  '{"type":"assistant","requestId":"r2","message":{"model":"m","usage":{"output_tokens":20},"content":[{"type":"tool_use","id":"t2"}]}}'
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2"}]}}'
  '{"type":"system","subtype":"noise"}'
  '{"type":"user","isMeta":true,"message":{"content":[{"type":"text","text":"reminder"}]}}'
  '{"type":"assistant","requestId":"r3","message":{"model":"m","usage":{"output_tokens":40},"content":[{"type":"text","text":"wrap"}]}}'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = FireStop $tp
Check 'mid-turn meta: exit 0'          ($rc -eq 0)
Check 'mid-turn meta: full turn cost'  ((LastLine) -match '<Stop:70>$')
Check 'mid-turn meta: tool calls'      ((LastLine) -match 'response - 2 tool call\(s\)')

# 2d) StopFailure (turn ended on an API error) logs under its own tag, cost still real
@(
  '{"type":"user","message":{"content":"prompt"}}'
  '{"type":"assistant","requestId":"r1","message":{"model":"m","usage":{"output_tokens":7},"content":[]}}'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = Fire 'omnilog-stop.ps1' ('{"hook_event_name":"StopFailure","error":"rate_limit","transcript_path":"' + $tp.Replace('\', '\\') + '"}')
Check 'stop failure: exit 0'      ($rc -eq 0)
Check 'stop failure: own tag'     ((LastLine) -match 'response failed - 0 tool call\(s\) <StopFailure:7>$')

# 3) Glob logs its pattern (Grep is covered in hooks-ascii-output.ps1)
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"Glob","tool_input":{"pattern":"**/*.ps1"}}'
Check 'glob: exit 0'       ($rc -eq 0)
Check 'glob: pattern only' ((LastLine) -match '\] \*\*/\*\.ps1 <Glob>$')

Remove-Item Env:\OMNILOG_FILE
Remove-Item -LiteralPath $log, $tp -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  stop-cost'; exit 0 }
Write-Output ("FAIL  stop-cost ({0} case(s))" -f $fail); exit 1
