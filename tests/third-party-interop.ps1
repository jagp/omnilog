# TEST (e2e fuzz): unexpected payloads and cross-plugin interactions. Hooks with a
# '*' matcher see EVERY tool call in the session, including tools from 3rd-party
# plugins and MCP servers with arbitrary names/shapes -- none of that may crash a
# hook, corrupt the log/board, or trick ado into mirroring a lookalike tool.
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

Remove-Item Env:\OMNILOG_FILE, Env:\ADO_FILE, Env:\ADO_SCOPE -ErrorAction SilentlyContinue
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

# --- ado: lookalike tools + hostile subjects + parallel writers --------------------
$ado = Join-Path $env:TEMP ("ado-interop-{0}.ado" -f ([guid]::NewGuid().ToString('N')))
$env:ADO_FILE = $ado

# 11) an MCP tool NAMED like TaskCreate (mcp__todos__TaskCreate) is NOT mirrored --
#     its payload shape is foreign; only the native tools are trusted
$rc = Fire 'ado-tool.ps1' '{"tool_name":"mcp__todos__TaskCreate","tool_input":{"subject":"impostor"},"tool_response":"Task #5 created successfully"}'
Check 'mcp lookalike: exit 0'   ($rc -eq 0)
Check 'mcp lookalike: no board' (-not (Test-Path -LiteralPath $ado))

# 12) tool_response as an OBJECT (schema drift) -> item still lands, just without #id
$rc = Fire 'ado-tool.ps1' '{"tool_name":"TaskCreate","tool_input":{"subject":"drifted"},"tool_response":{"content":[{"type":"text","text":"Task #3 created"}]}}'
Check 'object tool_response: exit 0'     ($rc -eq 0)
Check 'object tool_response: item lands' ((Test-Path -LiteralPath $ado) -and ((Get-Content -Raw -LiteralPath $ado) -match '(?m)^- \[ \] .*drifted'))

# 13) subject mimicking board syntax (### header / checkbox / #id) collapses to one item line
$rc = Fire 'ado-tool.ps1' '{"tool_name":"TaskCreate","tool_input":{"subject":"### sneaky\n- [x] #99 fake done"},"tool_response":"Task #4 created successfully"}'
$content = Get-Content -Raw -LiteralPath $ado
Check 'hostile subject: exit 0'          ($rc -eq 0)
Check 'hostile subject: single item'     ($content -match '(?m)^- \[ \] #4 ### sneaky - \[x\] #99 fake done$')
Check 'hostile subject: no forged block' (-not ($content -match '(?m)^### sneaky'))
# ...and updating #4 doesn't touch the embedded '#99' text
$rc = Fire 'ado-tool.ps1' '{"tool_name":"TaskUpdate","tool_input":{"taskId":"4","status":"completed"}}'
Check 'hostile subject: update by id ok' ((Get-Content -Raw -LiteralPath $ado) -match '(?m)^- \[x\] #4 ### sneaky')

Remove-Item -LiteralPath $ado -ErrorAction SilentlyContinue

# 14) six parallel agents mirroring to ONE board (the real multi-agent scenario):
#     every item lands, title exactly once, zero malformed lines
$payloadDir = Join-Path $env:TEMP ("ado-par-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
$procs = @()
1..6 | ForEach-Object {
  $p = Join-Path $payloadDir "p$_.json"
  ('{"tool_name":"TaskCreate","agent_id":"agent' + $_ + 'aaaaaaaa","agent_type":"worker","tool_input":{"subject":"parallel task ' + $_ + '"},"tool_response":"Task #10' + $_ + ' created successfully"}') |
    Set-Content -LiteralPath $p -Encoding ASCII
  $procs += Start-Process powershell -PassThru -WindowStyle Hidden -RedirectStandardInput $p `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $hooks 'ado-tool.ps1')
}
$procs | ForEach-Object { $_.WaitForExit() }
$content = Get-Content -Raw -LiteralPath $ado
$lines = @(Get-Content -LiteralPath $ado)
$missing = @(1..6 | Where-Object { -not ($content -match ('parallel task ' + $_)) })
Check 'parallel: all 6 items landed' ($missing.Count -eq 0)
Check 'parallel: title exactly once' (([regex]::Matches($content, '(?m)^# ado')).Count -eq 1)
$badLines = @($lines | Where-Object { $_ -and ($_ -notmatch '^(# ado|### |- \[)') })
Check 'parallel: zero malformed lines' ($badLines.Count -eq 0)
if ($missing.Count -gt 0) { Write-Output ("        missing: {0}" -f ($missing -join ',')) }

Remove-Item Env:\ADO_FILE -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ado -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  third-party-interop'; exit 0 }
Write-Output ("FAIL  third-party-interop ({0} case(s))" -f $fail); exit 1
