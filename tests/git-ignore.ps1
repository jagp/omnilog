# TEST (integration): the per-project log never reaches git. Fires the real tool
# hook (no OMNILOG_FILE -- the default per-project path) inside a fresh git repo,
# then asks git itself: the log and its seeded .gitignore must be ignored, and a
# legacy root omnilog.md must keep receiving lines with no .claude log created.
# Skips (exit 0) when git is not on PATH. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$hooks = Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\scripts'

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output 'SKIP  git-ignore (git not on PATH)'; exit 0 }

# Fire omnilog-tool.ps1 in its own process, with the project dir pointed at $repo.
function FireTool($repo, $desc) {
  $env:CLAUDE_PROJECT_DIR = $repo
  ('{"tool_name":"Bash","tool_input":{"description":"' + $desc + '"}}') |
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'omnilog-tool.ps1')
  return $LASTEXITCODE
}
function NewRepo {
  $repo = Join-Path $env:TEMP ("omni-git-{0}" -f ([guid]::NewGuid().ToString('N')))
  New-Item -ItemType Directory -Path $repo -Force | Out-Null
  & git -C $repo init -q
  return $repo
}
Remove-Item Env:\OMNILOG_FILE -ErrorAction SilentlyContinue
Remove-Item Env:\OMNILOG_ENABLED -ErrorAction SilentlyContinue

# 1) fresh repo: the hook seeds .claude\.omnilog\.omnilog.md and git sees nothing
$repo = NewRepo
$log = Join-Path $repo '.claude\.omnilog\.omnilog.md'
Check 'fresh: hook exit 0'           ((FireTool $repo 'git probe') -eq 0)
Check 'fresh: line lands'            ((Test-Path -LiteralPath $log) -and ((Get-Content -Raw -LiteralPath $log) -match 'git probe'))
$status = @(& git -C $repo status --porcelain --untracked-files=all)
Check 'fresh: git status is clean'   ($status.Count -eq 0)
& git -C $repo check-ignore -q '.claude/.omnilog/.omnilog.md'
Check 'fresh: log is git-ignored'    ($LASTEXITCODE -eq 0)
Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue

# 2) repo with a legacy root omnilog.md: lines land there, no .claude log appears
$repo = NewRepo
$legacy = Join-Path $repo 'omnilog.md'
Set-Content -LiteralPath $legacy -Value '[26-01-01 00:00] old line <Bash>' -Encoding ASCII
Check 'legacy: hook exit 0'          ((FireTool $repo 'legacy probe') -eq 0)
Check 'legacy: line lands in root'   ((Get-Content -Raw -LiteralPath $legacy) -match 'legacy probe')
Check 'legacy: no .claude\.omnilog'  (-not (Test-Path -LiteralPath (Join-Path $repo '.claude\.omnilog')))
Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue

Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
if ($fail -eq 0) { Write-Output 'PASS  git-ignore'; exit 0 }
Write-Output ("FAIL  git-ignore ({0} case(s))" -f $fail); exit 1
