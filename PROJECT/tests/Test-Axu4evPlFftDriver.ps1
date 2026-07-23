$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$testSource = Join-Path $PSScriptRoot 'pl_fft_control_test.c'
$driverSource = Join-Path $sourceRoot 'pl_fft_control.c'
$driverHeader = Join-Path $sourceRoot 'pl_fft_control.h'
$mainSource = Join-Path $sourceRoot 'main.c'
$configSource = Join-Path $sourceRoot 'app_config.h'

foreach ($path in @($testSource, $driverSource, $driverHeader,
        $mainSource, $configSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PL FFT driver source: $path"
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
    'axu4ev_pl_fft_driver_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$executable = Join-Path $work 'pl_fft_control_test.exe'

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        $testSource $driverSource -o $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT driver compilation failed with: $gcc"
    }
    & $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT driver test failed with exit code $LASTEXITCODE"
    }

    $combined = (Get-Content -LiteralPath $driverHeader -Raw) +
        (Get-Content -LiteralPath $driverSource -Raw) +
        (Get-Content -LiteralPath $mainSource -Raw) +
        (Get-Content -LiteralPath $configSource -Raw)
    foreach ($fragment in @(
            'PL_FFT_SINGLE_SHOT',
            'pl_fft_capture_once(',
            'PL_FFT: PASS frame=',
            'MONOPULSE_FOUNDATION_TEST')) {
        if (-not $combined.Contains($fragment)) {
            throw "PL FFT application integration is missing: $fragment"
        }
    }

    $defaultMode = @'
#include "app_config.h"
#if !defined(MONOPULSE_FOUNDATION_TEST)
#error default mode must remain MONOPULSE_FOUNDATION_TEST
#endif
#if defined(PL_FFT_SINGLE_SHOT)
#error PL_FFT_SINGLE_SHOT must be opt-in
#endif
int main(void) { return 0; }
'@
    $singleMode = @'
#include "app_config.h"
#if !defined(PL_FFT_SINGLE_SHOT)
#error PL_FFT_SINGLE_SHOT was not selected
#endif
#if defined(MONOPULSE_FOUNDATION_TEST)
#error PL_FFT_SINGLE_SHOT must exclude MONOPULSE_FOUNDATION_TEST
#endif
int main(void) { return 0; }
'@
    $defaultSource = Join-Path $work 'default_mode.c'
    $singleSource = Join-Path $work 'single_mode.c'
    Set-Content -LiteralPath $defaultSource -Value $defaultMode -Encoding Ascii
    Set-Content -LiteralPath $singleSource -Value $singleMode -Encoding Ascii
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        $defaultSource -o (Join-Path $work 'default_mode.exe')
    if ($LASTEXITCODE -ne 0) {
        throw 'Default application-mode contract failed.'
    }
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        -DPL_FFT_SINGLE_SHOT $singleSource -o (Join-Path $work 'single_mode.exe')
    if ($LASTEXITCODE -ne 0) {
        throw 'PL_FFT_SINGLE_SHOT application-mode contract failed.'
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
