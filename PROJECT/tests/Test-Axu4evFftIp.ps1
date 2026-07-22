param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2020.1\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$libraryDir = Join-Path $root 'Related-Docs\hdl-main\library\axi_ad9364_fft_capture'
$configTcl = Join-Path $libraryDir 'fft_v9_1_config.tcl'
$packageTcl = Join-Path $libraryDir 'axi_ad9364_fft_capture_ip.tcl'
$inspectTcl = Join-Path $PSScriptRoot 'Inspect-Axu4evFftIp.tcl'

foreach ($requiredFile in @($configTcl, $packageTcl, $inspectTcl, $Vivado)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Missing Task 6 dependency: $requiredFile"
    }
}

$packageSource = Get-Content -Raw -LiteralPath $packageTcl
$expectedSources = @(
    'axi_ad9364_fft_capture.v',
    'adc_frame_capture.v',
    'adc_frame_replay.v',
    'magnitude_peak.v',
    'spectrum_pingpong.v',
    'fft_command_cdc.v',
    'fft_result_cdc.v',
    'axi_ad9364_fft_regs.v'
)
foreach ($sourceName in $expectedSources) {
    if (-not $packageSource.Contains($sourceName)) {
        throw "Package Tcl does not enumerate required RTL source '$sourceName'."
    }
}

$requiredPackagingTokens = @(
    'ipx::add_bus_interface s_axi',
    'xilinx.com:interface:aximm_rtl:1.0',
    'ipx::add_bus_interface spectrum_bank0',
    'ipx::add_bus_interface spectrum_bank1',
    'xilinx.com:interface:bram_rtl:1.0',
    'ipx::add_bus_interface adc_tap',
    'xilinx.com:interface:axis_rtl:1.0',
    'ipx::add_bus_interface irq',
    'xilinx.com:signal:interrupt_rtl:1.0',
    'Missing required RTL source',
    'Missing required FFT IP'
)
foreach ($token in $requiredPackagingTokens) {
    if (-not $packageSource.Contains($token)) {
        throw "Package Tcl is missing required packaging contract token '$token'."
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_fft_ip_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$oldRoot = $env:FPGA_PROFEN_ROOT
try {
    $env:FPGA_PROFEN_ROOT = $root
    Push-Location $work
    try {
        $output = (& $Vivado -mode batch -nolog -nojournal -notrace -source $inspectTcl 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        Write-Output $output
        if ($exitCode -ne 0) {
            throw "Vivado FFT IP inspection failed with exit code $exitCode."
        }
        if ($output.Contains('ERROR:')) {
            throw 'Vivado FFT IP inspection reported ERROR.'
        }
        $marker = 'PASS: FFT v9.1 configuration matches the numerical contract'
        if (-not $output.Contains($marker)) {
            throw "Vivado FFT IP inspection did not emit '$marker'."
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:FPGA_PROFEN_ROOT = $oldRoot
    $resolvedWork = (Resolve-Path -LiteralPath $work).Path
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedWork.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected work directory '$resolvedWork'."
    }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
}
