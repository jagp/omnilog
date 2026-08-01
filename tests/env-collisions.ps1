# TEST (unit): environment-variable and config-file edge cases. Other tools,
# wrappers, and 3rd-party plugins share the process environment -- a stray or
# malformed value must never redirect the log somewhere surprising, and the
# .claude/omnilog.local.md parser must only honor keys inside the YAML
# frontmatter, not lookalike prose in the markdown body. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$hooks = Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\scripts'
. (Join-Path $hooks 'ado-lib.ps1')   # also dot-sources omnilog-lib.ps1

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}

Remove-Item Env:\OMNILOG_FILE, Env:\ADO_FILE, Env:\ADO_SCOPE -ErrorAction SilentlyContinue
$proj = Join-Path $env:TEMP ("omni-env-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
$env:CLAUDE_PROJECT_DIR = $proj
$cfg = Join-Path $proj '.claude\omnilog.local.md'
$log = Join-Path $proj 'omnilog.md'
Set-Content -LiteralPath $log -Value '' -Encoding ASCII   # opt-in marker for the whole file

# 1) whitespace-only OMNILOG_FILE (leaked by a wrapper) -> treated as unset, falls
#    through to normal resolution instead of "logging" to a path of spaces
$env:OMNILOG_FILE = '   '
Check 'whitespace OMNILOG_FILE ignored' ((Resolve-OmnilogTarget) -eq $log)
Remove-Item Env:\OMNILOG_FILE

# 2) whitespace-only ADO_FILE -> same
$env:ADO_FILE = "`t "
Check 'whitespace ADO_FILE ignored' ((Resolve-AdoTarget) -eq (Join-Path $proj '.claude\task.ado'))
Remove-Item Env:\ADO_FILE

# 3) ADO_SCOPE is case-insensitive (another tool may export 'OFF')
$env:ADO_SCOPE = 'OFF'
Check 'ADO_SCOPE=OFF (upper) => off' ($null -eq (Resolve-AdoTarget))
Remove-Item Env:\ADO_SCOPE

# 4) CLAUDE_PROJECT_DIR with a trailing backslash still finds marker + config
$env:CLAUDE_PROJECT_DIR = $proj + '\'
Check 'trailing backslash project dir' ((Resolve-OmnilogTarget) -eq (Join-Path ($proj + '\') 'omnilog.md'))
$env:CLAUDE_PROJECT_DIR = $proj

# 5) CLAUDE_PROJECT_DIR pointing at a directory that does not exist -> null, no throw
$env:CLAUDE_PROJECT_DIR = Join-Path $env:TEMP 'omni-env-definitely-missing-dir'
$r = Resolve-OmnilogTarget
Check 'missing project dir => null' ($null -eq $r)
$env:CLAUDE_PROJECT_DIR = $proj

# 6) config with UTF-8 BOM + CRLF (VS Code defaults) parses fine
[System.IO.File]::WriteAllText($cfg, "---`r`nscope: off`r`n---`r`n", (New-Object System.Text.UTF8Encoding($true)))
Check 'BOM+CRLF config: scope honored' ($null -eq (Resolve-OmnilogTarget))

# 7) 'scope: off' as PROSE in the markdown body (outside frontmatter) is ignored
Set-Content -LiteralPath $cfg -Encoding ASCII -Value @"
---
scope: per-project
---

To disable logging entirely, set the frontmatter to:

    scope: off
    ado: off
"@
Check 'prose scope: off ignored'  ((Resolve-OmnilogTarget) -eq $log)
Check 'prose ado: off ignored'    ((Resolve-AdoTarget) -eq (Join-Path $proj '.claude\task.ado'))

# 8) duplicate key inside frontmatter: last one wins (pinned so edits are predictable)
Set-Content -LiteralPath $cfg -Encoding ASCII -Value "---`nscope: off`nscope: per-project`n---"
Check 'duplicate key: last wins' ((Resolve-OmnilogTarget) -eq $log)

# 9) config that is just prose with NO frontmatter fence: keys still honored
#    (lenient fallback -- hand-written files without --- fences keep working)
Set-Content -LiteralPath $cfg -Encoding ASCII -Value "scope: off"
Check 'fenceless config still parsed' ($null -eq (Resolve-OmnilogTarget))

# 10) unreadable config (exclusively locked by another process) -> defaults, no throw
Set-Content -LiteralPath $cfg -Encoding ASCII -Value "---`nscope: off`n---"
$fs = [System.IO.File]::Open($cfg, 'Open', 'ReadWrite', [System.IO.FileShare]::None)
try {
  $r = $null; $threw = $false
  try { $r = Resolve-OmnilogTarget } catch { $threw = $true }
  Check 'locked config: no throw'        (-not $threw)
  Check 'locked config: default resolve' ($r -eq $log)
} finally { $fs.Dispose() }

# 11) forward-slash 'path:' in config is honored as-is (Windows APIs accept both)
$fwd = ($env:TEMP -replace '\\', '/') + '/omni-env-fwd.md'
Set-Content -LiteralPath $cfg -Encoding ASCII -Value "---`nscope: global`npath: $fwd`n---"
Check 'forward-slash path honored' ((Resolve-OmnilogTarget) -eq $fwd)

Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  env-collisions'; exit 0 }
Write-Output ("FAIL  env-collisions ({0} case(s))" -f $fail); exit 1
