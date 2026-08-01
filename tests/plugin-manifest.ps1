# TEST (install): the plugin is actually installable/activatable as shipped.
# Validates the three manifests (plugin.json, marketplace.json, hooks.json), that
# every hook command points at a script that exists, is quoted (plugin cache paths
# contain spaces), runs with -NoProfile (user profiles must not leak into hooks),
# and that every shipped .ps1 parses cleanly under Windows PowerShell 5.1.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}

# --- manifests parse -------------------------------------------------------------
$plugin = $null; $market = $null; $hooksCfg = $null
try { $plugin = Get-Content -Raw -LiteralPath (Join-Path $root '.claude-plugin\plugin.json') | ConvertFrom-Json } catch { }
try { $market = Get-Content -Raw -LiteralPath (Join-Path $root '.claude-plugin\marketplace.json') | ConvertFrom-Json } catch { }
try { $hooksCfg = Get-Content -Raw -LiteralPath (Join-Path $root 'hooks\hooks.json') | ConvertFrom-Json } catch { }
Check 'plugin.json parses'      ($null -ne $plugin)
Check 'marketplace.json parses' ($null -ne $market)
Check 'hooks.json parses'       ($null -ne $hooksCfg)
if ($fail -gt 0) { Write-Output ("FAIL  plugin-manifest ({0} case(s))" -f $fail); exit 1 }

# --- identity + version parity (a drifted version breaks marketplace updates) ----
Check 'plugin name present'        ([string]$plugin.name)
$entry = $market.plugins | Where-Object { $_.name -eq $plugin.name } | Select-Object -First 1
Check 'marketplace lists plugin'   ($null -ne $entry)
Check 'versions in sync'           ($entry -and ([string]$entry.version -eq [string]$plugin.version))

# --- every hook command: quoted ${CLAUDE_PLUGIN_ROOT} path, -NoProfile, real file -
$cmds = @()
foreach ($evt in $hooksCfg.hooks.PSObject.Properties) {
  foreach ($m in $evt.Value) { foreach ($h in $m.hooks) { $cmds += [string]$h.command } }
}
Check 'has hook commands' ($cmds.Count -gt 0)
foreach ($cmd in $cmds) {
  $label = (($cmd -replace '.*[\\/]', '') -replace '"', '')  # trailing script name for readable output
  Check "uses -NoProfile           ($label)" ($cmd -match '-NoProfile')
  Check "bypasses execution policy ($label)" ($cmd -match '-ExecutionPolicy\s+Bypass')
  # The script path MUST be wrapped in quotes: installed plugin roots live under
  # paths with spaces (e.g. ...\plugins\cache\...). Unquoted = broken activation.
  Check "quoted plugin-root path   ($label)" ($cmd -match '"\$\{CLAUDE_PLUGIN_ROOT\}[^"]+"')
  $m = [regex]::Match($cmd, '\$\{CLAUDE_PLUGIN_ROOT\}[/\\]([^"]+)')
  $rel = if ($m.Success) { $m.Groups[1].Value -replace '/', '\' } else { $null }
  Check "script exists             ($label)" ($rel -and (Test-Path -LiteralPath (Join-Path $root $rel)))
}

# --- every shipped script parses under 5.1, and is pure ASCII --------------------
# (a BOM-less non-ASCII .ps1 is decoded as ANSI by 5.1 -> silently wrong literals)
$scripts = Get-ChildItem -LiteralPath (Join-Path $root 'hooks\scripts') -Filter '*.ps1'
Check 'has hook scripts' ($scripts.Count -gt 0)
foreach ($s in $scripts) {
  $errs = $null
  [void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -LiteralPath $s.FullName), [ref]$errs)
  Check ("parses cleanly ({0})" -f $s.Name) ($errs.Count -eq 0)
  $bytes = [System.IO.File]::ReadAllBytes($s.FullName)
  Check ("pure ASCII source ({0})" -f $s.Name) (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
}

# --- commands ship with frontmatter (activation surfaces them as slash commands) --
$mds = Get-ChildItem -LiteralPath (Join-Path $root 'commands') -Filter '*.md'
Check 'has command files' ($mds.Count -gt 0)
foreach ($md in $mds) {
  $first = (Get-Content -LiteralPath $md.FullName -TotalCount 1)
  Check ("frontmatter opens ({0})" -f $md.Name) ($first -eq '---')
}

if ($fail -eq 0) { Write-Output 'PASS  plugin-manifest'; exit 0 }
Write-Output ("FAIL  plugin-manifest ({0} case(s))" -f $fail); exit 1
