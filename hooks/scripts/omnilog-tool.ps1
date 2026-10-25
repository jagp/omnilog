# PostToolUse hook: append one line per tool call. Logs the model-authored description
# (shell/agent) or project-relative path/pattern (file/search) - never raw commands or file
# content, so secrets never reach the log. ASCII-only + one-line output are enforced centrally
# in omnilog-lib.ps1. <actionType> = literal tool name. No :cost (only Stop has a real one).
$ErrorActionPreference = 'Stop'

function ConvertTo-ProjectRelative([string]$path) {
  # Show a file the way a reader of this project's log thinks of it: relative to the project.
  #   1. No CLAUDE_PROJECT_DIR -> nothing to be relative to; return the path as given.
  #   2. Compare with '/' folded to '\' and case ignored (Windows paths arrive either way),
  #      against the project dir PLUS a trailing '\' - so a sibling dir like 'proj2' never
  #      counts as being inside 'proj'.
  #   3. Inside the project -> drop that prefix. Outside -> return the path unchanged.
  $project = [string]$env:CLAUDE_PROJECT_DIR
  if (-not $project) { return $path }
  $prefix = $project.Replace('/', '\').TrimEnd('\') + '\'
  if ($path.Replace('/', '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    return $path.Substring($prefix.Length)   # the '/'->'\' fold keeps length, so the index holds
  }
  return $path
}

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
      '^(Edit|Write|Read|NotebookEdit|MultiEdit)$' { if ($ti.file_path) { $detail = ConvertTo-ProjectRelative ([string]$ti.file_path) } }
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
