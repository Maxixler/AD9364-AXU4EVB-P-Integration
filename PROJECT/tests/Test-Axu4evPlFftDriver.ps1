$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$testSource = Join-Path $PSScriptRoot 'pl_fft_control_test.c'
$driverSource = Join-Path $sourceRoot 'pl_fft_control.c'
$driverHeader = Join-Path $sourceRoot 'pl_fft_control.h'
$mainSource = Join-Path $sourceRoot 'main.c'
$configSource = Join-Path $sourceRoot 'app_config.h'
$applicationSourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src'
$bspInclude = Join-Path $root (
    'Vitis\workspace\fmcomms2_axu4ev_hw\export\fmcomms2_axu4ev_hw\sw\' +
    'fmcomms2_axu4ev_hw\standalone_domain\bspinclude\include')

foreach ($path in @($testSource, $driverSource, $driverHeader,
        $mainSource, $configSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PL FFT driver source: $path"
    }
}
if (-not (Test-Path -LiteralPath $bspInclude -PathType Container)) {
    throw "Missing AXU4EV BSP include directory: $bspInclude"
}

$targetGcc = $env:AXU4EV_AARCH64_GCC
if (-not $targetGcc) {
    $targetGcc = 'C:\Xilinx\Vitis\2020.1\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-gcc.exe'
}
if (-not (Test-Path -LiteralPath $targetGcc -PathType Leaf)) {
    throw "Unable to find AXU4EV A53 compiler. Set AXU4EV_AARCH64_GCC: $targetGcc"
}

$targetMainArguments = @(
    '-std=c11',
    '-fsyntax-only',
    '-mcpu=cortex-a53',
    '-Wformat=2',
    '-Werror=format',
    "-I$bspInclude",
    "-I$applicationSourceRoot\adc",
    "-I$applicationSourceRoot\include",
    "-I$applicationSourceRoot\adc9364_src",
    "-I$applicationSourceRoot\api",
    "-I$applicationSourceRoot\dac",
    "-I$applicationSourceRoot\dmac",
    "-I$applicationSourceRoot\drivers_rf_transceiver",
    "-I$applicationSourceRoot\iio",
    "-I$applicationSourceRoot\xilinx",
    '-DXPAR_AXI_AD9364_FFT_CAPTURE_0_S_AXI_BASEADDR=0xA0000000u',
    '-DXPAR_AXI_AD9364_FFT_BRAM0_S_AXI_BASEADDR=0xA0010000u',
    '-DXPAR_AXI_AD9364_FFT_BRAM1_S_AXI_BASEADDR=0xA0020000u'
)

function Invoke-NativeCompiler {
    param(
        [string]$Compiler,
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Compiler @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Test-Axu4evMainCompilation {
    param(
        [string]$Mode,
        [string[]]$Defines
    )

    $result = Invoke-NativeCompiler -Compiler $targetGcc `
        -Arguments ($targetMainArguments + $Defines + @($mainSource))
    if ($result.ExitCode -ne 0) {
        throw "AXU4EV main.c $Mode mode compilation failed:`n$($result.Output -join "`n")"
    }
}

function Get-Axu4evMainPreprocessed {
    param([string[]]$Defines)

    $result = Invoke-NativeCompiler -Compiler $targetGcc `
        -Arguments ($targetMainArguments + $Defines + @('-E', $mainSource))
    if ($result.ExitCode -ne 0) {
        throw "AXU4EV main.c periodic mode preprocessing failed:`n$($result.Output -join "`n")"
    }
    return $result.Output -join "`n"
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
            'PL_FFT_MONITOR_FRAMES 100u',
            'PL_FFT_MONITOR_INTERVAL_MS 1000u',
            'PL_FFT_MONITOR: START frames=',
            'PL_FFT_MONITOR: FRAME seq=',
            'PL_FFT_MONITOR: PASS frames=',
            'PL_FFT_MONITOR: FAIL seq=',
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
    $periodicMode = @'
#include "app_config.h"
#if !defined(PL_FFT_PERIODIC_MONITOR)
#error PL_FFT_PERIODIC_MONITOR was not selected
#endif
#if defined(PL_FFT_SINGLE_SHOT) || defined(MONOPULSE_FOUNDATION_TEST)
#error periodic mode must be exclusive
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
    $periodicSource = Join-Path $work 'periodic_mode.c'
    Set-Content -LiteralPath $defaultSource -Value $defaultMode -Encoding Ascii
    Set-Content -LiteralPath $singleSource -Value $singleMode -Encoding Ascii
    Set-Content -LiteralPath $periodicSource -Value $periodicMode -Encoding Ascii
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
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        -DPL_FFT_PERIODIC_MONITOR $periodicSource -o (Join-Path $work 'periodic_mode.exe')
    if ($LASTEXITCODE -ne 0) {
        throw 'PL_FFT_PERIODIC_MONITOR application-mode contract failed.'
    }
    $dualMode = Invoke-NativeCompiler -Compiler $gcc -Arguments @(
        '-std=c11', '-Wall', '-Wextra', '-Werror', "-I$sourceRoot",
        '-DPL_FFT_SINGLE_SHOT', '-DPL_FFT_PERIODIC_MONITOR', $periodicSource,
        '-o', (Join-Path $work 'dual_mode.exe'))
    if ($dualMode.ExitCode -eq 0) {
        throw 'PL FFT dual-mode application-mode contract was accepted.'
    }
    foreach ($invalidMode in @(
            @('-DPL_FFT_PERIODIC_MONITOR', '-DMONOPULSE_FOUNDATION_TEST'),
            @('-DPL_FFT_PERIODIC_MONITOR', '-DWIFI_RF_TEST'),
            @('-DPL_FFT_PERIODIC_MONITOR', '-DDMA_EXAMPLE'))) {
        $invalidModeResult = Invoke-NativeCompiler -Compiler $gcc -Arguments (
            @('-std=c11', '-Wall', '-Wextra', '-Werror', "-I$sourceRoot") +
            $invalidMode + @($periodicSource, '-o', (Join-Path $work 'invalid_mode.exe')))
        if ($invalidModeResult.ExitCode -eq 0) {
            throw "PL FFT periodic mode was accepted with $($invalidMode -join ' ')."
        }
    }

    Test-Axu4evMainCompilation -Mode 'default' -Defines @()
    Test-Axu4evMainCompilation -Mode 'single-shot' -Defines @('-DPL_FFT_SINGLE_SHOT')
    Test-Axu4evMainCompilation -Mode 'periodic' -Defines @('-DPL_FFT_PERIODIC_MONITOR')
    $periodicMain = Get-Axu4evMainPreprocessed -Defines @('-DPL_FFT_PERIODIC_MONITOR')
    if ($periodicMain.Contains('static int pl_fft_single_shot_run(void)')) {
        throw 'Single-shot runner is compiled into the periodic application mode.'
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
