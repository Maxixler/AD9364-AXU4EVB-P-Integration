param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2020.1\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$libraryDir = Join-Path $root 'Related-Docs\hdl-main\library\axi_ad9364_fft_capture'
$configTcl = Join-Path $libraryDir 'fft_v9_1_config.tcl'
$packageTcl = Join-Path $libraryDir 'axi_ad9364_fft_capture_ip.tcl'
$inspectTcl = Join-Path $PSScriptRoot 'Inspect-Axu4evFftIp.tcl'
$positivePackageTcl = Join-Path $PSScriptRoot 'Package-Axu4evFftIp.tcl'

foreach ($requiredFile in @($configTcl, $packageTcl, $inspectTcl, $positivePackageTcl, $Vivado)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Missing Task 6 dependency: $requiredFile"
    }
}

$packageSource = Get-Content -Raw -LiteralPath $packageTcl
$inspectSource = Get-Content -Raw -LiteralPath $inspectTcl
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
    'adc_enable {I0/Q0 sample-enable indication}',
    'adc_i      {Signed I0 sample component in Q1.15 format}',
    'adc_q      {Signed Q0 sample component in Q1.15 format}',
    'rf_state   {Three-bit RF-state tag sampled at command acceptance}',
    'ipx::add_bus_interface irq',
    'xilinx.com:signal:interrupt_rtl:1.0',
    'ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk',
    'ipx::associate_bus_interfaces -clock s_axi_aclk -reset s_axi_aresetn',
    'ipx::associate_bus_interfaces -busif spectrum_bank0 -clock s_axi_aclk',
    'ipx::associate_bus_interfaces -busif spectrum_bank1 -clock s_axi_aclk',
    'ipx::associate_bus_interfaces -clock adc_clk -reset adc_resetn',
    'Missing required RTL source',
    'Missing required FFT IP'
)
foreach ($token in $requiredPackagingTokens) {
    if (-not $packageSource.Contains($token)) {
        throw "Package Tcl is missing required packaging contract token '$token'."
    }
}
if ($packageSource.Contains('xilinx.com:interface:axis_rtl:1.0') -or
    $packageSource.Contains('physical_name adc_data')) {
    throw 'Package Tcl must expose the AD9364 tap as discrete non-backpressured ports.'
}

foreach ($fixtureToken in @('FFT_PACKAGE_MISSING_SOURCE_TCL', 'FFT_PACKAGE_COMPLETE_TCL')) {
    if (-not $inspectSource.Contains($fixtureToken)) {
        throw "Inspection Tcl does not require isolated fixture '$fixtureToken'."
    }
}
if ($inspectSource.Contains('set package_tcl [file join $library_dir')) {
    throw 'Inspection Tcl must not resolve the real package script for execution.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_fft_ip_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$oldRoot = $env:FPGA_PROFEN_ROOT
$oldMissingSourceTcl = $env:FFT_PACKAGE_MISSING_SOURCE_TCL
$oldCompleteTcl = $env:FFT_PACKAGE_COMPLETE_TCL
$oldPackageOutput = $env:FFT_PACKAGE_OUTPUT_DIR
$sourceTreeBefore = @(Get-ChildItem -LiteralPath $libraryDir -Recurse -Force |
    ForEach-Object { $_.FullName.Substring($libraryDir.Length) })
try {
    $missingSourceDir = Join-Path $work 'missing_source_fixture'
    $completeDir = Join-Path $work 'complete_source_fixture'
    New-Item -ItemType Directory -Path $missingSourceDir, $completeDir | Out-Null
    $missingSourcePackage = Join-Path $missingSourceDir 'axi_ad9364_fft_capture_ip.tcl'
    $completePackage = Join-Path $completeDir 'axi_ad9364_fft_capture_ip.tcl'
    Copy-Item -LiteralPath $packageTcl -Destination $missingSourcePackage
    Copy-Item -LiteralPath $packageTcl -Destination $completePackage
    foreach ($sourceName in $expectedSources) {
        New-Item -ItemType File -Path (Join-Path $completeDir $sourceName) | Out-Null
        if ($sourceName -ne 'axi_ad9364_fft_capture.v') {
            New-Item -ItemType File -Path (Join-Path $missingSourceDir $sourceName) | Out-Null
        }
    }

    $env:FPGA_PROFEN_ROOT = $root
    $env:FFT_PACKAGE_MISSING_SOURCE_TCL = $missingSourcePackage
    $env:FFT_PACKAGE_COMPLETE_TCL = $completePackage
    $env:FFT_PACKAGE_OUTPUT_DIR = Join-Path $work 'positive_package'
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

        $packageOutput = (& $Vivado -mode batch -nolog -nojournal -notrace `
            -source $positivePackageTcl 2>&1 | Out-String)
        $packageExitCode = $LASTEXITCODE
        Write-Output $packageOutput
        if ($packageExitCode -ne 0 -or $packageOutput.Contains('ERROR:')) {
            throw "Positive disposable FFT packaging failed with exit code $packageExitCode."
        }
        $packageMarker = 'PASS: positive disposable FFT package inspection'
        if (-not $packageOutput.Contains($packageMarker)) {
            throw "Positive packaging did not emit '$packageMarker'."
        }
    } finally {
        Pop-Location
    }
} finally {
    $env:FPGA_PROFEN_ROOT = $oldRoot
    $env:FFT_PACKAGE_MISSING_SOURCE_TCL = $oldMissingSourceTcl
    $env:FFT_PACKAGE_COMPLETE_TCL = $oldCompleteTcl
    $env:FFT_PACKAGE_OUTPUT_DIR = $oldPackageOutput
    $resolvedWork = (Resolve-Path -LiteralPath $work).Path
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedWork.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected work directory '$resolvedWork'."
    }
    Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
    $sourceTreeAfter = @(Get-ChildItem -LiteralPath $libraryDir -Recurse -Force |
        ForEach-Object { $_.FullName.Substring($libraryDir.Length) })
    $sourceTreeDelta = @(Compare-Object $sourceTreeBefore $sourceTreeAfter)
    if ($sourceTreeDelta.Count -ne 0) {
        throw "FFT IP inspection modified the source library: $($sourceTreeDelta | Out-String)"
    }
}
