# TEST (unit): Resolve-OmnilogTarget honors scope (off/global/per-project) + the
# opt-in marker (presence of omnilog.md), with $env:OMNILOG_FILE overriding all.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$hooks = Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\scripts'
. (Join-Path $hooks 'omnilog-lib.ps1')

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}

Remove-Item Env:\OMNILOG_FILE -ErrorAction SilentlyContinue
$proj = Join-Path $env:TEMP ("omni-scope-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
$env:CLAUDE_PROJECT_DIR = $proj
$cfg = Join-Path $proj '.claude\omnilog.local.md'
$log = Join-Path $proj 'omnilog.md'

# 1) per-project default, no marker -> $null (project has not opted in)
Check 'per-project/no-marker => null' ($null -eq (Resolve-OmnilogTarget))

# 2) per-project default, marker present -> the project log
Set-Content -LiteralPath $log -Value '' -Encoding ASCII
Check 'per-project/marker => project log' ((Resolve-OmnilogTarget) -eq $log)

# 3) scope: off -> $null even with the marker present
Set-Content -LiteralPath $cfg -Value "---`nscope: off`n---" -Encoding ASCII
Check 'off => null' ($null -eq (Resolve-OmnilogTarget))

# 4) scope: global with explicit path -> that path
$g = Join-Path $env:TEMP ("omni-global-{0}.md" -f ([guid]::NewGuid().ToString('N')))
Set-Content -LiteralPath $cfg -Value "---`nscope: global`npath: $g`n---" -Encoding ASCII
Check 'global/path => that path' ((Resolve-OmnilogTarget) -eq $g)

# 5) $env:OMNILOG_FILE overrides everything
$env:OMNILOG_FILE = 'X:\override.md'
Check 'OMNILOG_FILE overrides' ((Resolve-OmnilogTarget) -eq 'X:\override.md')
Remove-Item Env:\OMNILOG_FILE

Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $g -Force -ErrorAction SilentlyContinue

# 6) no CLAUDE_PROJECT_DIR -> fallback is the runtime working dir, NOT the plugin dir
$cwd = Join-Path $env:TEMP ("omni-cwd-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $cwd -Force | Out-Null
Push-Location $cwd
$rFallback = Resolve-OmnilogTarget
$here = (Get-Location).Path
Pop-Location
Check 'no-project-dir => cwd log' ($rFallback -eq (Join-Path $here 'omnilog.md'))
Check 'no-project-dir !=> plugin dir' ($rFallback -ne (Join-Path (Split-Path (Split-Path $hooks -Parent) -Parent) 'omnilog.md'))
Remove-Item -LiteralPath $cwd -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  omnilog-scope'; exit 0 }
Write-Output ("FAIL  omnilog-scope ({0} case(s))" -f $fail); exit 1
