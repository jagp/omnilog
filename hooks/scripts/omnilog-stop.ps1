# Stop hook: append one line per assistant response with the REAL turn token cost computed
# from the transcript (algorithm in docs/autologging.md). ASCII-only + width enforced in
# omnilog-lib.ps1. A :cost is written only when it is real and verifiable. exit 0 (no block).
$ErrorActionPreference = 'Stop'
try {
  . (Join-Path $PSScriptRoot 'omnilog-lib.ps1')
  $raw = Read-HookStdin
  if (-not $raw) { exit 0 }
  $o = $raw | ConvertFrom-Json
  if ($o.stop_hook_active) { exit 0 }

  $tpath = [string]$o.transcript_path
  $cost = $null
  $toolIds = New-Object System.Collections.Generic.HashSet[string]
  $seenReq = New-Object System.Collections.Generic.HashSet[string]

  if ($tpath -and (Test-Path -LiteralPath $tpath)) {
    $lines = Get-Content -LiteralPath $tpath -Encoding UTF8
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
      $ln = $lines[$i]
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      try { $e = $ln | ConvertFrom-Json } catch { continue }
      $t = [string]$e.type
      if ($t -eq 'user') {
        $c = $e.message.content
        $isToolResult = ($c -is [System.Array] -and $c.Count -gt 0 -and ([string]$c[0].type) -eq 'tool_result')
        if (-not $isToolResult) { break }
      }
      elseif ($t -eq 'assistant') {
        if (([string]$e.message.model) -eq '<synthetic>') { continue }
        $rid = [string]$e.requestId
        $u = $e.message.usage
        if ($u -and $rid -and $seenReq.Add($rid)) {
          if ($null -eq $cost) { $cost = 0 }
          $cost += [int]$u.output_tokens
        }
        $cc = $e.message.content
        if ($cc -is [System.Array]) {
          foreach ($seg in $cc) { if (([string]$seg.type) -eq 'tool_use' -and $seg.id) { [void]$toolIds.Add([string]$seg.id) } }
        }
      }
    }
  }

  $n = $toolIds.Count
  $tag = if ($null -ne $cost) { "Stop:$cost" } else { 'Stop' }
  Write-OmnilogEntry "response - $n tool call(s)" $tag
} catch { }
exit 0
