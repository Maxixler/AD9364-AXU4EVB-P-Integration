param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2020.1\bin\vivado.bat',
    [switch]$KeepWork,
    [switch]$DisableIntegration
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$hdlRoot = Join-Path $root 'Related-Docs\hdl-main'
$sourceProject = Join-Path $hdlRoot 'projects\fmcomms2\axu4ev'
$sourceCommon = Join-Path $hdlRoot 'projects\fmcomms2\common\fmcomms2_bd.tcl'
$inspectTcl = Join-Path $PSScriptRoot 'Inspect-Axu4evFftBlockDesign.tcl'
$packageTcl = Join-Path $PSScriptRoot 'Package-Axu4evFftIp.tcl'

foreach ($required in @($Vivado, $inspectTcl, $packageTcl,
        (Join-Path $sourceProject 'system_project.tcl'),
        (Join-Path $sourceProject 'system_bd.tcl'),
        (Join-Path $sourceProject 'system_top.v'),
        (Join-Path $sourceProject 'system_constr.xdc'),
        $sourceCommon)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing FFT block-design dependency: $required"
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_fft_candidate_' + [guid]::NewGuid().ToString('N'))
$candidateRoot = Join-Path $work 'Candidate'
$candidateHdl = Join-Path $candidateRoot 'hdl-main'
$candidateProject = Join-Path $candidateHdl 'projects\fmcomms2\axu4ev'
$candidateCommon = Join-Path $candidateHdl 'projects\fmcomms2\common'
$candidateScripts = Join-Path $candidateHdl 'scripts'
$candidateRepo = Join-Path $candidateRoot 'custom-ip'
$candidateLibrary = Join-Path $candidateRepo 'library'
$packageOutput = Join-Path $candidateLibrary 'axi_ad9364_fft_capture'
New-Item -ItemType Directory -Path $candidateProject, $candidateCommon,
    $candidateScripts, $candidateLibrary -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceProject 'system_project.tcl') -Destination $candidateProject
Copy-Item -LiteralPath (Join-Path $sourceProject 'system_bd.tcl') -Destination $candidateProject
Copy-Item -LiteralPath (Join-Path $sourceProject 'system_top.v') -Destination $candidateProject
Copy-Item -LiteralPath (Join-Path $sourceProject 'system_constr.xdc') -Destination $candidateProject
Copy-Item -LiteralPath $sourceCommon -Destination $candidateCommon
Copy-Item -LiteralPath (Join-Path $hdlRoot 'scripts\adi_env.tcl') -Destination $candidateScripts
$candidateProjectScript = Join-Path $candidateProject 'system_project.tcl'
$candidateProjectSource = Get-Content -Raw -LiteralPath $candidateProjectScript
$candidateProjectSource = $candidateProjectSource.Replace(
    'source $ad_hdl_dir/library/axi_ad9361/axi_ad9361_delay.tcl',
    '# Structural Candidate gate: post-route delay report is exercised by the bitstream gate.')
Set-Content -LiteralPath $candidateProjectScript -Value $candidateProjectSource -Encoding Ascii

# A linked worktree intentionally omits ignored ADI component.xml products.
# Reuse an existing generated ADI repository read-only by copying only the ten
# dependency packages into Candidate; never generate into either source tree.
$dependencyHdl = @(git -C $root worktree list --porcelain |
    Where-Object { $_ -like 'worktree *' } |
    ForEach-Object { Join-Path $_.Substring(9) 'Related-Docs\hdl-main' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ 'library\axi_sysid\component.xml') } |
    Select-Object -First 1)
if ($dependencyHdl.Count -ne 1) {
    throw 'No generated ADI IP dependency repository with axi_sysid/component.xml was found.'
}
foreach ($dependency in @(
        'scripts', 'axi_ad9361', 'axi_dmac', 'axi_sysid', 'sysid_rom',
        'util_pack\util_cpack2', 'util_pack\util_upack2',
        'util_rfifo', 'util_tdd_sync', 'util_wfifo', 'xilinx\util_clkdiv')) {
    $sourceDependency = Join-Path $dependencyHdl[0] "library\$dependency"
    $destinationDependency = Join-Path $candidateLibrary $dependency
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationDependency) -Force | Out-Null
    Copy-Item -LiteralPath $sourceDependency -Destination $destinationDependency -Recurse -Force
}

$old = @{
    FPGA_PROFEN_ROOT = $env:FPGA_PROFEN_ROOT
    FFT_PACKAGE_OUTPUT_DIR = $env:FFT_PACKAGE_OUTPUT_DIR
    FFT_PACKAGE_IMPORT_FILES = $env:FFT_PACKAGE_IMPORT_FILES
    ADI_GHDL_DIR = $env:ADI_GHDL_DIR
    ADI_HDL_DIR = $env:ADI_HDL_DIR
    ADI_SKIP_SYNTHESIS = $env:ADI_SKIP_SYNTHESIS
    AXU4EV_FFT_SHADOW_PATH = $env:AXU4EV_FFT_SHADOW_PATH
}

try {
    $env:FPGA_PROFEN_ROOT = $root
    $env:FFT_PACKAGE_OUTPUT_DIR = $packageOutput
    $env:FFT_PACKAGE_IMPORT_FILES = '1'
    $env:ADI_GHDL_DIR = $candidateRepo
    # Use the generated dependency tree with its matching source callbacks.
    # The Candidate mirror still supplies this branch's fmcomms2 common Tcl.
    $env:ADI_HDL_DIR = $dependencyHdl[0]
    $env:ADI_SKIP_SYNTHESIS = '1'
    $env:AXU4EV_FFT_SHADOW_PATH = if ($DisableIntegration) { '0' } else { '1' }

    if (-not $DisableIntegration) {
        $packageOutputText = (& $Vivado -mode batch -nolog -nojournal -notrace `
            -source $packageTcl 2>&1 | Out-String)
        Write-Output $packageOutputText
        if ($LASTEXITCODE -ne 0 -or
            $packageOutputText -notmatch 'PASS: positive disposable FFT package inspection') {
            throw "Disposable FFT IP packaging failed with exit code $LASTEXITCODE."
        }
        if ($packageOutputText -match 'CRITICAL WARNING: \[IP_Flow 19-530\]') {
            throw 'Disposable FFT IP package contains a missing or external source reference.'
        }
    }

    Push-Location $candidateProject
    try {
        $inspectOutput = (& $Vivado -mode batch -nolog -nojournal -notrace `
            -source $inspectTcl 2>&1 | Out-String)
    } finally {
        Pop-Location
    }
    Write-Output $inspectOutput
    if ($LASTEXITCODE -ne 0) {
        throw "FFT block-design inspection failed with exit code $LASTEXITCODE."
    }
    if ($inspectOutput -match 'CRITICAL WARNING:.*axi_ad9364_fft') {
        throw 'FFT block-design inspection reported a critical warning attributable to the shadow path.'
    }
    if ($inspectOutput -match 'WARNING: \[BD 41-926\].*axi_ad9364_fft_capture') {
        throw 'FFT block-design inspection reported an unresolved FFT BRAM bus-parameter propagation warning.'
    }
    if ($inspectOutput -notmatch
        'PASS: FFT shadow path is present and the Golden DMA topology is unchanged') {
        throw 'FFT block-design inspection did not print its required PASS marker.'
    }
} finally {
    $env:FPGA_PROFEN_ROOT = $old.FPGA_PROFEN_ROOT
    $env:FFT_PACKAGE_OUTPUT_DIR = $old.FFT_PACKAGE_OUTPUT_DIR
    $env:FFT_PACKAGE_IMPORT_FILES = $old.FFT_PACKAGE_IMPORT_FILES
    $env:ADI_GHDL_DIR = $old.ADI_GHDL_DIR
    $env:ADI_HDL_DIR = $old.ADI_HDL_DIR
    $env:ADI_SKIP_SYNTHESIS = $old.ADI_SKIP_SYNTHESIS
    $env:AXU4EV_FFT_SHADOW_PATH = $old.AXU4EV_FFT_SHADOW_PATH

    if ($KeepWork) {
        Write-Output "INFO: Preserved disposable Candidate work at $work"
    } elseif (Test-Path -LiteralPath $work) {
        $resolved = (Resolve-Path -LiteralPath $work).Path
        $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove non-temporary Candidate path '$resolved'."
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
