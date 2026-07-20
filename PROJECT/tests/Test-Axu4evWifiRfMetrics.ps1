param(
    [string]$CompilerPath = $env:WIFI_RF_GCC
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$fallbackGcc = 'C:\MinGW\bin\gcc.exe'

if ($CompilerPath) {
    if (-not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) {
        throw "Configured GCC executable does not exist: $CompilerPath"
    }
    $gcc = (Resolve-Path -LiteralPath $CompilerPath).Path
}
else {
    $gccCommand = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue
    if ($gccCommand) {
        $gcc = $gccCommand.Source
    }
    elseif (Test-Path -LiteralPath $fallbackGcc -PathType Leaf) {
        $gcc = $fallbackGcc
    }
    else {
        throw "GCC was not found. Pass -CompilerPath or set WIFI_RF_GCC."
    }
}

$test = Join-Path $root 'PROJECT\tests\wifi_rf_metrics_test.c'
$source = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\wifi_rf_metrics.c'
$include = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$output = Join-Path ([IO.Path]::GetTempPath()) "wifi-rf-metrics-$([guid]::NewGuid()).exe"

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$include" $test $source -lm -o $output
    if ($LASTEXITCODE -ne 0) { throw "Native metrics compilation failed with: $gcc" }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Native metrics test failed.' }
}
finally {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}
