# SubagentStop hook: append one line when a spawned agent finishes, referencing it. No :cost
# (subagent cost is not computed yet). ASCII-only + one-line output enforced in omnilog-lib.ps1.
# agent_id / agent_type are documented; the camelCase spellings are read as a fallback.
# exit 0 (never blocks).
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
