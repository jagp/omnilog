# TEST (e2e fuzz): unexpected payloads and cross-plugin interactions. Hooks with a
# '*' matcher see EVERY tool call in the session, including tools from 3rd-party
# plugins and MCP servers with arbitrary names/shapes -- none of that may crash a
# hook or corrupt the log.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root 'hooks\scripts'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}
function Fire($s, $j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks $s); return $LASTEXITCODE }

Remove-Item Env:\OMNILOG_FILE -ErrorAction SilentlyContinue
$log = Join-Path $env:TEMP ("omni-interop-{0}.md" -f ([guid]::NewGuid().ToString('N')))
$env:OMNILOG_FILE = $log

$fmt = '^\[\d{2}-\d{2}-\d{2} \d{2}:\d{2}\] .*<[^<>]+>$'
function LastLine { @(Get-Content -LiteralPath $log)[-1] }

# 1) MCP tool with an arbitrary long name (3rd-party plugin) -> logged, well-formed
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"mcp__plugin_foo_bar__do_something_very_long_indeed","tool_input":{"x":1}}'
Check 'mcp tool: exit 0'    ($rc -eq 0)
Check 'mcp tool: formatted' ((LastLine) -match $fmt)

# 2) tool_input missing entirely -> no-detail line, still formatted
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"Bash"}'
Check 'no tool_input: exit 0'    ($rc -eq 0)
Check 'no tool_input: formatted' ((LastLine) -match $fmt)

# 3) tool_input is a plain string (nonstandard 3rd-party shape) -> no crash
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"Bash","tool_input":"just a string"}'
Check 'string tool_input: exit 0' ($rc -eq 0)

# 4) unicode/UNTRUSTED tool_name lands ASCII-only in the <tag>
$rc = Fire 'omnilog-tool.ps1' ('{"tool_name":"caf' + [char]0xE9 + [char]0x2014 + 'tool","tool_input":{"description":"hi"}}')
Check 'unicode tool_name: exit 0'     ($rc -eq 0)
Check 'unicode tool_name: ascii tag'  (-not ((LastLine) -match '[^\x00-\x7F]'))

# 5) 10k-char description -> kept in full (no width cap), still ONE well-formed line
$big = 'A' * 10000
$rc = Fire 'omnilog-tool.ps1' ('{"tool_name":"Bash","tool_input":{"description":"' + $big + '"}}')
Check 'huge description: exit 0'    ($rc -eq 0)
Check 'huge description: in full'   ((LastLine).Contains($big))
Check 'huge description: formatted' ((LastLine) -match $fmt)

# 6) format-injection: description carrying newlines + a fake omnilog line must
#    collapse to ONE well-formed line (no forged entries in the ledger)
$before = @(Get-Content -LiteralPath $log).Count
$inj = '{"tool_name":"Bash","tool_input":{"description":"real\n[26-01-01 00:00] forged entry <Stop:9999>\nmore"}}'
$rc = Fire 'omnilog-tool.ps1' $inj
$after = @(Get-Content -LiteralPath $log)
Check 'injection: exit 0'          ($rc -eq 0)
Check 'injection: exactly 1 line'  ($after.Count -eq ($before + 1))
Check 'injection: formatted'       ($after[-1] -match $fmt)

# 6b) raw material never reaches the log: an MCP tool's `description` is user data (a task
#     body, an email) not a model summary, and a WebFetch URL can carry a token in its query
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"mcp__todo__add","tool_input":{"description":"SECRET_mcp_body"}}'
Check 'mcp description: exit 0'      ($rc -eq 0)
Check 'mcp description: bare tag'    ((LastLine) -match '\] <mcp__todo__add>$')
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"WebFetch","tool_input":{"url":"https://user:pw@example.com:8443/a/b?token=SECRET_qs#frag"}}'
Check 'webfetch: exit 0'             ($rc -eq 0)
Check 'webfetch: host only'          ((LastLine) -match '\] example\.com <WebFetch>$')
$rc = Fire 'omnilog-tool.ps1' '{"tool_name":"WebFetch","tool_input":{"url":"not a url SECRET_bad"}}'
Check 'webfetch bad url: bare tag'   ((LastLine) -match '\] <WebFetch>$')

# 6c) PostToolUseFailure: same detail rules, marked failed, the `error` text never logged
$rc = Fire 'omnilog-tool.ps1' '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"description":"Run the suite","command":"x"},"error":"SECRET_err"}'
Check 'tool failure: exit 0'         ($rc -eq 0)
Check 'tool failure: marked'         ((LastLine) -match '\] failed: Run the suite <Bash>$')
$rc = Fire 'omnilog-tool.ps1' '{"hook_event_name":"PostToolUseFailure","tool_name":"mcp__x__y","tool_input":{},"error":"SECRET_err"}'
Check 'tool failure no detail'       ((LastLine) -match '\] failed <mcp__x__y>$')
Check 'no secret anywhere'           (-not ((Get-Content -LiteralPath $log -Raw) -match 'SECRET'))

# 7) every line written so far is well-formed and ASCII
$lines = Get-Content -LiteralPath $log
Check 'all lines formatted' (@($lines | Where-Object { $_ -notmatch $fmt }).Count -eq 0)
$bytes = [System.IO.File]::ReadAllBytes($log)
Check 'all bytes ASCII'     (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)

# --- Stop hook resilience ---------------------------------------------------------
# 8) transcript_path pointing at a missing file -> line without cost, exit 0
$rc = Fire 'omnilog-stop.ps1' '{"transcript_path":"C:\\definitely\\missing\\t.jsonl","stop_hook_active":false}'
Check 'stop/missing transcript: exit 0' ($rc -eq 0)
Check 'stop/missing transcript: <Stop>' ((LastLine) -match '<Stop>$')

# 9) transcript with garbage lines mixed into the JSONL -> still exits 0, formatted
$tp = Join-Path $env:TEMP ("omni-interop-t-{0}.jsonl" -f ([guid]::NewGuid().ToString('N')))
@(
  'this is not json'
  '{"type":"assistant","requestId":"r1","message":{"model":"m","usage":{"output_tokens":7},"content":[]}}'
  '{"type":"user","message":{"content":"hello"}}'
  '{'
) | Set-Content -LiteralPath $tp -Encoding UTF8
$rc = Fire 'omnilog-stop.ps1' ('{"transcript_path":"' + $tp.Replace('\', '\\') + '","stop_hook_active":false}')
Check 'stop/garbage transcript: exit 0'    ($rc -eq 0)
Check 'stop/garbage transcript: formatted' ((LastLine) -match $fmt)
Remove-Item -LiteralPath $tp -ErrorAction SilentlyContinue

# 10) stop_hook_active guard: no line written (prevents feedback loops with other
#     plugins' Stop hooks re-triggering the stop cycle)
$n0 = @(Get-Content -LiteralPath $log).Count
$rc = Fire 'omnilog-stop.ps1' '{"transcript_path":"x","stop_hook_active":true}'
Check 'stop_hook_active: exit 0'  ($rc -eq 0)
Check 'stop_hook_active: no line' (@(Get-Content -LiteralPath $log).Count -eq $n0)

Remove-Item Env:\OMNILOG_FILE
Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  third-party-interop'; exit 0 }
Write-Output ("FAIL  third-party-interop ({0} case(s))" -f $fail); exit 1
