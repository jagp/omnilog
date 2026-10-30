# Stop / StopFailure hook: append one line per assistant response with the REAL turn token
# cost computed from the transcript (algorithm in docs/autologging.md#2). ASCII-only and
# one-line output are enforced in omnilog-lib.ps1. A :cost is written only when it is real
# and verifiable. StopFailure (turn ended on an API error) logs the same way under its own
# tag; its `error` field is never logged. exit 0 (no block).
$ErrorActionPreference = 'Stop'

function Get-Entry([string]$line) {
  # One transcript line -> parsed object, or $null for blank/malformed lines (skipped).
  if ([string]::IsNullOrWhiteSpace($line)) { return $null }
  try { return $line | ConvertFrom-Json } catch { return $null }
}

function Test-ToolResult($entry) {
  # A user line that carries a tool's output back to the model - mid-turn, never a prompt.
  $c = $entry.message.content
  return ($c -is [System.Array] -and $c.Count -gt 0 -and ([string]$c[0].type) -eq 'tool_result')
}

function Test-TurnOpen($lines, [int]$index) {
  # Was a tool call still in flight just before line $index? Used to tell an isMeta user line
  # injected MID-turn (skill body, reminder) from one that OPENS a turn (peer message):
  #   1. Scan backward from the previous line, ignoring non-message lines and other meta lines.
  #   2. The first real message decides: a tool_result, or an assistant line holding a
  #      tool_use, means the turn was still open. Anything else (a finished reply, a human
  #      prompt, start of file) means the meta line starts a new turn.
  for ($j = $index - 1; $j -ge 0; $j--) {
    $prev = Get-Entry $lines[$j]
    if (-not $prev) { continue }
    $pt = [string]$prev.type
    if ($pt -eq 'assistant') {
      foreach ($seg in @($prev.message.content)) { if (([string]$seg.type) -eq 'tool_use') { return $true } }
      return $false
    }
    if ($pt -eq 'user') {
      if (Test-ToolResult $prev) { return $true }
      if ($prev.isMeta -eq $true) { continue }
      return $false
    }
  }
  return $false
}

try {
  . (Join-Path $PSScriptRoot 'omnilog-lib.ps1')
  $raw = Read-HookStdin
  if (-not $raw) { exit 0 }
  $o = $raw | ConvertFrom-Json
  if ($o.stop_hook_active) { exit 0 }
  $eventName = if (([string]$o.hook_event_name) -eq 'StopFailure') { 'StopFailure' } else { 'Stop' }

  $tpath = [string]$o.transcript_path
  $cost = $null
  $toolIds = New-Object System.Collections.Generic.HashSet[string]
  $seenReq = New-Object System.Collections.Generic.HashSet[string]

  # Walk the transcript backward from the end to the prompt that opened this turn.
  if ($tpath -and (Test-Path -LiteralPath $tpath)) {
    $lines = Get-Content -LiteralPath $tpath -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $e = Get-Entry $lines[$i]
      if (-not $e) { continue }
      $t = [string]$e.type
      if ($t -eq 'user') {
        if (Test-ToolResult $e) { continue }                                   # tool output: mid-turn
        if ($e.isMeta -eq $true -and (Test-TurnOpen $lines $i)) { continue }   # injected mid-turn
        break                                                                  # the turn's prompt
      }
      elseif ($t -eq 'assistant') {
        if (([string]$e.message.model) -eq '<synthetic>') { continue }         # local, not billed
        $rid = [string]$e.requestId
        $out = $e.message.usage.output_tokens
        # Count each API request once (its content-block lines repeat one usage). The Add goes
        # last so a line with no output_tokens never claims the requestId.
        if ($rid -and $null -ne $out -and $seenReq.Add($rid)) {
          if ($null -eq $cost) { $cost = 0 }
          $cost += [int]$out
        }
        foreach ($seg in @($e.message.content)) {
          if (([string]$seg.type) -eq 'tool_use' -and $seg.id) { [void]$toolIds.Add([string]$seg.id) }
        }
      }
    }
  }

  $n = $toolIds.Count
  $tag = if ($null -ne $cost) { "${eventName}:$cost" } else { $eventName }
  $detail = if ($eventName -eq 'StopFailure') { "response failed - $n tool call(s)" } else { "response - $n tool call(s)" }
  Write-OmnilogEntry $detail $tag
} catch { }
exit 0
