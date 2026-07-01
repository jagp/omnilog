# SubagentStop hook: append one line when a spawned agent finishes, referencing it. No :cost
# (no verifiable subagent cost at this event). ASCII-only + width enforced in omnilog-lib.ps1.
# Field names for this event are undocumented, so read defensively. exit 0 (never blocks).
$ErrorActionPreference = 'Stop'
try {
  . (Join-Path $PSScriptRoot 'omnilog-lib.ps1')
  $raw = Read-HookStdin
  if (-not $raw) { exit 0 }
  $o = $raw | ConvertFrom-Json

  $aid = [string]$o.agent_id
  if (-not $aid) { $aid = [string]$o.agentId }
  $atype = [string]$o.agent_type
  if (-not $atype) { $atype = [string]$o.subagent_type }
  if ($aid -and $aid.Length -gt 8) { $aid = $aid.Substring(0, 8) }

  $detail = 'Subagent finished'
  if ($aid)   { $detail += " (#$aid)" }
  if ($atype) { $detail += " $atype" }

  Write-OmnilogEntry $detail 'SubagentStop'
} catch { }
exit 0
