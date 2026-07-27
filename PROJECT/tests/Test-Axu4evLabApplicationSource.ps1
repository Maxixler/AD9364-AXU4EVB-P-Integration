$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src'
$appRoot = Join-Path $sourceRoot 'adc9364_src'
$mainSource = Join-Path $appRoot 'main.c'
$configSource = Join-Path $appRoot 'app_config.h'
$serviceSource = Join-Path $appRoot 'pl_fft_lab_service.c'
$protocolSource = Join-Path $appRoot 'pl_fft_lab_protocol.c'
$bspInclude = Join-Path $root (
    'Vitis\workspace\fmcomms2_axu4ev_hw\export\fmcomms2_axu4ev_hw\sw\' +
    'fmcomms2_axu4ev_hw\standalone_domain\bspinclude\include')

foreach ($path in @($mainSource, $configSource, $serviceSource,
        $protocolSource, $bspInclude)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing lab application dependency: $path"
    }
}

$gcc = $env:AXU4EV_AARCH64_GCC
if (-not $gcc) {
    $gcc = 'C:\Xilinx\Vitis\2020.1\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-gcc.exe'
}
if (-not (Test-Path -LiteralPath $gcc -PathType Leaf)) {
    throw "Unable to find AXU4EV A53 compiler. Set AXU4EV_AARCH64_GCC: $gcc"
}
$hostGcc = $env:MONOPULSE_GCC
if (-not $hostGcc) {
    $hostCommand = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue
    if ($hostCommand) {
        $hostGcc = $hostCommand.Source
    } elseif (Test-Path -LiteralPath 'C:\MinGW\bin\gcc.exe') {
        $hostGcc = 'C:\MinGW\bin\gcc.exe'
    } else {
        throw 'Unable to find host gcc. Set MONOPULSE_GCC or add gcc to PATH.'
    }
}

$common = @(
    '-std=c11',
    '-mcpu=cortex-a53',
    '-Wall',
    '-Wextra',
    '-Werror',
    "-I$bspInclude",
    "-I$sourceRoot\adc",
    "-I$sourceRoot\include",
    "-I$sourceRoot\adc9364_src",
    "-I$sourceRoot\api",
    "-I$sourceRoot\dac",
    "-I$sourceRoot\dmac",
    "-I$sourceRoot\drivers_rf_transceiver",
    "-I$sourceRoot\iio",
    "-I$sourceRoot\xilinx",
    '-DXPAR_AXI_AD9364_FFT_CAPTURE_0_S_AXI_BASEADDR=0xA0000000u',
    '-DXPAR_AXI_AD9364_FFT_BRAM0_S_AXI_BASEADDR=0xA0010000u',
    '-DXPAR_AXI_AD9364_FFT_BRAM1_S_AXI_BASEADDR=0xA0020000u'
)

function Invoke-Compiler {
    param(
        [string]$Compiler,
        [string[]]$Arguments
    )

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Compiler @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_lab_application_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    $modeSource = Join-Path $work 'lab_mode.c'
    @'
#include "app_config.h"
#if !defined(PL_FFT_LAB_UART)
#error PL_FFT_LAB_UART was not selected
#endif
#if defined(PL_FFT_SINGLE_SHOT) || defined(PL_FFT_PERIODIC_MONITOR) || \
    defined(MONOPULSE_FOUNDATION_TEST) || defined(WIFI_RF_TEST) || \
    defined(DMA_EXAMPLE)
#error PL_FFT_LAB_UART must be exclusive
#endif
int main(void) { return 0; }
'@ | Set-Content -LiteralPath $modeSource -Encoding Ascii

    $labMode = Invoke-Compiler -Compiler $hostGcc -Arguments @(
        '-std=c11', '-Wall', '-Wextra', '-Werror', "-I$appRoot",
        '-DPL_FFT_LAB_UART', $modeSource, '-o',
        (Join-Path $work 'lab_mode.exe'))
    if ($labMode.ExitCode -ne 0) {
        throw "PL_FFT_LAB_UART mode contract failed:`n$($labMode.Output -join "`n")"
    }

    foreach ($other in @(
            'PL_FFT_SINGLE_SHOT',
            'PL_FFT_PERIODIC_MONITOR',
            'MONOPULSE_FOUNDATION_TEST',
            'WIFI_RF_TEST',
            'DMA_EXAMPLE')) {
        $invalid = Invoke-Compiler -Compiler $hostGcc -Arguments @(
            '-std=c11', '-Wall', '-Wextra', '-Werror', "-I$appRoot",
            '-DPL_FFT_LAB_UART', "-D$other", $modeSource, '-o',
            (Join-Path $work "invalid_$other.exe"))
        if ($invalid.ExitCode -eq 0) {
            throw "PL_FFT_LAB_UART was accepted with $other."
        }
    }

    $mainCompile = Invoke-Compiler -Compiler $gcc -Arguments (
        $common + @('-DPL_FFT_LAB_UART', '-fsyntax-only', $mainSource))
    if ($mainCompile.ExitCode -ne 0) {
        throw "AXU4EV main.c lab mode compilation failed:`n$($mainCompile.Output -join "`n")"
    }

    $preprocess = Invoke-Compiler -Compiler $gcc -Arguments (
        $common + @('-DPL_FFT_LAB_UART', '-E', $mainSource))
    if ($preprocess.ExitCode -ne 0) {
        throw "AXU4EV main.c lab preprocessing failed:`n$($preprocess.Output -join "`n")"
    }
    $expanded = $preprocess.Output -join "`n"
    foreach ($fragment in @(
            'PL_FFT_LAB: READY protocol=1 bins=2048 baud=115200',
            'PL_FFT_LAB: FAIL stage=%s error=%',
            'ad9361_get_rx_sampling_freq',
            'ad9361_get_rx_rf_bandwidth',
            'ad9361_get_rx_lo_freq',
            'static uint64_t pl_fft_spectrum',
            '__attribute__((aligned(64)))',
            'pl_fft_lab_parser_push',
            'inbyte()',
            'outbyte(')) {
        if (-not $expanded.Contains($fragment)) {
            throw "Lab application behavior is missing after preprocessing: $fragment"
        }
    }
    $readyCount = [regex]::Matches(
        $expanded,
        [regex]::Escape('PL_FFT_LAB: READY protocol=1 bins=2048 baud=115200')
    ).Count
    if ($readyCount -ne 1) {
        throw "Lab READY marker must exist exactly once, found $readyCount."
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}

Write-Host 'PASS: PL_FFT_LAB_UART application source contract.'
