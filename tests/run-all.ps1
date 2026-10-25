# Runs every atomic test in tests\ (each is its own *.ps1 that exits 0=pass / 1=fail)
# and prints a summary. Exit 0 only if all pass.
$ErrorActionPreference = 'Continue'
$tests = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | Where-Object { $_.Name -ne 'run-all.ps1' } | Sort-Object Name
$fail = 0
foreach ($t in $tests) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t.FullName 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Output ("PASS  {0}" -f $t.Name)
  } else {
    Write-Output ("FAIL  {0} (exit {1})" -f $t.Name, $LASTEXITCODE)
    $out | ForEach-Object { Write-Output ("        {0}" -f $_) }
    $fail++
  }
}
Write-Output ''
if ($fail -eq 0) { Write-Output ("ALL PASS ({0} tests)" -f $tests.Count); exit 0 }
Write-Output ("{0} FAILED of {1}" -f $fail, $tests.Count)
exit 1
