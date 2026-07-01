# TEST (unit): ConvertTo-Ascii turns arbitrary Unicode into pure printable ASCII.
# This file is itself pure ASCII - the torture string is built from code points at runtime.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$hooks = Join-Path (Split-Path $PSScriptRoot -Parent) '.claude\hooks'
. (Join-Path $hooks 'omnilog-lib.ps1')

$U = 'em' + [char]0x2014 + 'dash ' + [char]0x201C + 'smart' + [char]0x201D + ' caf' + [char]0xE9 +
     ' ' + [char]0x65E5 + [char]0x672C + [char]0x8A9E + ' ' + [char]::ConvertFromUtf32(0x1F680) +
     ' end' + [char]0x2026
$out = ConvertTo-Ascii $U
$bad = @($out.ToCharArray() | Where-Object { [int]$_ -lt 32 -or [int]$_ -gt 126 })

Write-Output ("in : {0}" -f $U)
Write-Output ("out: {0}" -f $out)
if ($bad.Count -eq 0) { Write-Output 'PASS  ascii-sanitizer'; exit 0 }
Write-Output ("FAIL  ascii-sanitizer: {0} non-ASCII char(s)" -f $bad.Count)
exit 1
