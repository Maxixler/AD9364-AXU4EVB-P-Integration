$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$monitorTestSource = Join-Path $PSScriptRoot 'pl_fft_monitor_test.c'
$monitorSource = Join-Path $sourceRoot 'pl_fft_monitor.c'
$monitorHeader = Join-Path $sourceRoot 'pl_fft_monitor.h'
$driverSource = Join-Path $sourceRoot 'pl_fft_control.c'
$driverHeader = Join-Path $sourceRoot 'pl_fft_control.h'

foreach ($path in @($monitorTestSource, $monitorSource, $monitorHeader,
        $driverSource, $driverHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PL FFT monitor source: $path"
    }
}

$gcc = $env:MONOPULSE_GCC
if (-not $gcc) {
    $command = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue
    if ($command) {
        $gcc = $command.Source
    } elseif (Test-Path -LiteralPath 'C:\MinGW\bin\gcc.exe') {
        $gcc = 'C:\MinGW\bin\gcc.exe'
    } else {
        throw 'Unable to find gcc. Set MONOPULSE_GCC or add gcc to PATH.'
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_pl_fft_monitor_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$monitorExecutable = Join-Path $work 'pl_fft_monitor_test.exe'

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        $monitorTestSource $monitorSource $driverSource -o $monitorExecutable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT monitor compilation failed with: $gcc"
    }
    & $monitorExecutable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT monitor test failed with exit code $LASTEXITCODE"
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
