$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gcc = 'C:\MinGW\bin\gcc.exe'
$test = Join-Path $root 'PROJECT\tests\wifi_rf_metrics_test.c'
$source = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\wifi_rf_metrics.c'
$include = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$output = Join-Path ([IO.Path]::GetTempPath()) "wifi-rf-metrics-$([guid]::NewGuid()).exe"

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$include" $test $source -lm -o $output
    if ($LASTEXITCODE -ne 0) { throw 'Native metrics compilation failed.' }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Native metrics test failed.' }
}
finally {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}
