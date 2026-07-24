[CmdletBinding()]
param(
    [string]$WorkspaceRoot,

    [Parameter(Mandatory)]
    [string]$SourceXsa,

    [Parameter(Mandatory)]
    [string]$CandidateRoot,

    [Parameter(Mandatory)]
    [string]$VitisWorkspace,

    [Parameter(Mandatory)]
    [string]$AllowedVitisWorkspaceRoot,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
else {
    $WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
}
$SourceXsa = (Resolve-Path -LiteralPath $SourceXsa).Path
$CandidateRoot = [IO.Path]::GetFullPath($CandidateRoot)
$VitisWorkspace = [IO.Path]::GetFullPath($VitisWorkspace)
$AllowedVitisWorkspaceRoot = [IO.Path]::GetFullPath($AllowedVitisWorkspaceRoot)

$goldenBase = Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$candidateBase = Join-Path $WorkspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$releaseModule = Join-Path $WorkspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$buildTcl = Join-Path $WorkspaceRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
$xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
foreach ($required in @($SourceXsa, $releaseModule, $buildTcl, $xsct)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing Candidate build dependency: $required"
    }
}

$goldenPrefix = [IO.Path]::GetFullPath($goldenBase).TrimEnd('\') + '\'
$candidatePrefix = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\') + '\'
if ($CandidateRoot.StartsWith($goldenPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "CandidateRoot cannot be inside the Golden release tree: $CandidateRoot"
}
if (-not $CandidateRoot.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase) -and -not $DryRun) {
    throw "CandidateRoot must be inside the project Candidate tree: $CandidateRoot"
}
$allowedWorkspacePrefix = $AllowedVitisWorkspaceRoot.TrimEnd('\') + '\'
$vitisWorkspacePrefix = $VitisWorkspace.TrimEnd('\') + '\'
$allowedWorkspaceRootTrimmed = $AllowedVitisWorkspaceRoot.TrimEnd('\')
if ([IO.Path]::GetPathRoot($AllowedVitisWorkspaceRoot).TrimEnd('\').Equals(
        $allowedWorkspaceRootTrimmed,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $VitisWorkspace.StartsWith($allowedWorkspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "VitisWorkspace must be a child of the approved root '$AllowedVitisWorkspaceRoot': $VitisWorkspace"
}
foreach ($protectedPath in @($WorkspaceRoot, $CandidateRoot, $goldenBase, (Split-Path $SourceXsa -Parent))) {
    $protectedPrefix = [IO.Path]::GetFullPath($protectedPath).TrimEnd('\') + '\'
    if ($VitisWorkspace.Equals(
            [IO.Path]::GetFullPath($protectedPath),
            [StringComparison]::OrdinalIgnoreCase) -or
        $VitisWorkspace.StartsWith($protectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFullPath($protectedPath).StartsWith(
            $vitisWorkspacePrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe Candidate Vitis workspace overlaps protected path '$protectedPath': $VitisWorkspace"
    }
}
if ($VitisWorkspace.Equals($AllowedVitisWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe Candidate Vitis workspace path: $VitisWorkspace"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($SourceXsa)
try {
    $hwhEntry = @($archive.Entries |
        Where-Object {
            $_.FullName -notmatch '/' -and
            [IO.Path]::GetExtension($_.FullName) -eq '.hwh'
        }) | Select-Object -First 1
    $bitEntry = @($archive.Entries |
        Where-Object {
            $_.FullName -notmatch '/' -and
            [IO.Path]::GetExtension($_.FullName) -eq '.bit'
        }) | Select-Object -First 1
    if (-not $hwhEntry -or -not $bitEntry) {
        throw 'Candidate XSA does not contain a top-level HWH and bitstream.'
    }

    $reader = New-Object IO.StreamReader($hwhEntry.Open())
    try {
        $hwh = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    $requiredHwhPatterns = [ordered]@{
        fft_control = 'BASEVALUE="0x9C440000"[^>]+INSTANCE="axi_ad9364_fft_capture"'
        fft_bank0 = 'BASEVALUE="0x9D000000"[^>]+INSTANCE="axi_ad9364_fft_bram0"'
        fft_bank1 = 'BASEVALUE="0x9D010000"[^>]+INSTANCE="axi_ad9364_fft_bram1"'
    }
    foreach ($entry in $requiredHwhPatterns.GetEnumerator()) {
        if ($hwh -notmatch $entry.Value) {
            throw "Candidate XSA is missing the locked PL FFT hardware mapping '$($entry.Key)'."
        }
    }

    $description = [ordered]@{
        source_xsa = $SourceXsa
        source_xsa_sha256 = (Get-FileHash -LiteralPath $SourceXsa -Algorithm SHA256).Hash
        candidate_root = $CandidateRoot
        vitis_workspace = $VitisWorkspace
        fft_control_base = '0x9C440000'
        fft_bank0_base = '0x9D000000'
        fft_bank1_base = '0x9D010000'
        pl_fft_single_shot = $true
    }
    if ($DryRun) {
        $description | ConvertTo-Json -Depth 4
        return
    }

    $trackedChanges = @(& git -C $WorkspaceRoot status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot inspect the Candidate source tree state.'
    }
    if ($trackedChanges.Count -ne 0) {
        throw "Candidate builds require a clean tracked source tree.`r`n$($trackedChanges -join "`r`n")"
    }
    $sourceCommit = (& git -C $WorkspaceRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot determine the Candidate source commit.'
    }

    $hardwareDir = Join-Path $CandidateRoot 'hardware'
    New-Item -ItemType Directory -Path $hardwareDir -Force | Out-Null
    $candidateXsa = Join-Path $hardwareDir 'system_top.xsa'
    $candidateBitstream = Join-Path $hardwareDir 'system_top.bit'
    Copy-Item -LiteralPath $SourceXsa -Destination $candidateXsa -Force

    $bitInput = $bitEntry.Open()
    $bitOutput = [IO.File]::Create($candidateBitstream)
    try {
        $bitInput.CopyTo($bitOutput)
    }
    finally {
        $bitOutput.Dispose()
        $bitInput.Dispose()
    }
}
finally {
    $archive.Dispose()
}

& $xsct $buildTcl $WorkspaceRoot $candidateXsa $VitisWorkspace $AllowedVitisWorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Candidate Vitis build failed with exit code $LASTEXITCODE."
}

$platformName = 'fmcomms2_axu4ev_fft_hw'
$generated = [ordered]@{
    application = Join-Path $VitisWorkspace 'ad9364app\Release\ad9364app.elf'
    bitstream = Join-Path $VitisWorkspace 'ad9364app\_ide\bitstream\system_top.bit'
    pmufw = Join-Path $VitisWorkspace "$platformName\zynqmp_pmufw\executable.elf"
    psu_init = Join-Path $VitisWorkspace 'ad9364app\_ide\psinit\psu_init.tcl'
    xsa = $candidateXsa
}
foreach ($entry in $generated.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Candidate Vitis build is missing '$($entry.Key)': $($entry.Value)"
    }
}
if ((Get-FileHash -LiteralPath $generated.bitstream -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $candidateBitstream -Algorithm SHA256).Hash) {
    throw 'Candidate Vitis bitstream does not match the bitstream embedded in the Candidate XSA.'
}

$destinations = [ordered]@{
    application = 'applications/ad9364app.elf'
    bitstream = 'hardware/system_top.bit'
    pmufw = 'firmware/pmufw.elf'
    psu_init = 'hardware/psu_init.tcl'
    xsa = 'hardware/system_top.xsa'
}
foreach ($name in @('application', 'pmufw', 'psu_init')) {
    $destination = Join-Path $CandidateRoot ($destinations[$name] -replace '/', '\')
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $generated[$name] -Destination $destination -Force
}

Import-Module $releaseModule -Force
$manifest = New-Axu4evReleaseManifest `
    -ReleaseRoot $CandidateRoot `
    -Metadata @{
        release_id = Split-Path $CandidateRoot -Leaf
        created_at = (Get-Date).ToString('o')
        source_commit = $sourceCommit
        board_verified = $false
        uart_markers = @('PL_FFT: PASS')
    } `
    -Artifacts $destinations
$manifest | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $CandidateRoot 'manifest.json') -Encoding UTF8

Write-Output "PASS: Candidate bundle created at $CandidateRoot"
$description | ConvertTo-Json -Depth 4
