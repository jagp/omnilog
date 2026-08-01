# PostToolUse hook: append one line per tool call. Logs the model-authored description
# (shell/agent) or filename/pattern (file/search) - never raw commands or file content, so
# secrets never reach the log. ASCII-only + one-line output are enforced centrally in
# omnilog-lib.ps1. <actionType> = literal tool name. No :cost (only Stop has a real one).
$ErrorActionPreference = 'Stop'
try {
  . (Join-Path $PSScriptRoot 'omnilog-lib.ps1')
  $raw = Read-HookStdin
  if (-not $raw) { exit 0 }
  $o = $raw | ConvertFrom-Json
  $tool = [string]$o.tool_name
  $ti = $o.tool_input
  $detail = ''

  if ($tool -match '^(Agent|Task)$') {
    $id = ''
    $tr = $o.tool_response
    if ($tr) {
      $trs = if ($tr -is [string]) { $tr } else { $tr | ConvertTo-Json -Depth 6 -Compress }
      $m = [regex]::Match($trs, 'agent[_]?[Ii]d["'':\s]+([0-9a-fA-F]{6,})')
      if ($m.Success) { $id = $m.Groups[1].Value; if ($id.Length -gt 8) { $id = $id.Substring(0, 8) } }
    }
    $detail = 'Spun off new subagent'
    if ($id) { $detail += " (#$id)" }
    $purpose = [string]$ti.description
    if ($purpose) { $detail += " for $purpose" }
  }
  else {
    switch -Regex ($tool) {
      '^(Bash|PowerShell)$'                        { $detail = [string]$ti.description }
      '^(Edit|Write|Read|NotebookEdit|MultiEdit)$' { if ($ti.file_path) { $detail = Split-Path ([string]$ti.file_path) -Leaf } }
      '^(Grep|Glob)$'                              { $detail = [string]$ti.pattern }
      '^Skill$'                                    { $detail = [string]$ti.skill }
      '^ToolSearch$'                               { $detail = [string]$ti.query }
      '^WebFetch$'                                 { $detail = [string]$ti.url }
      '^WebSearch$'                                { $detail = [string]$ti.query }
      default                                      { $detail = [string]$ti.description }
    }
  }

  Write-OmnilogEntry $detail $tool
} catch { }
exit 0
