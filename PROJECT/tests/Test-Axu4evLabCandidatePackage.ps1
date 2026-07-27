$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$releaseModule = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$referenceRoot = Join-Path $candidateBase 'fft-single-shot-v1'
$labRoot = Join-Path $candidateBase 'monopulse-live-lab-v1'

foreach ($path in @($releaseModule, $referenceRoot, $labRoot)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing Lab Candidate package dependency: $path"
    }
}

Import-Module $releaseModule -Force
$referenceManifest = Read-Axu4evReleaseManifest -ReleaseRoot $referenceRoot
$labManifest = Read-Axu4evReleaseManifest -ReleaseRoot $labRoot
$referenceArtifacts = @(Test-Axu4evReleaseArtifacts `
        -ReleaseRoot $referenceRoot -Manifest $referenceManifest)
$labArtifacts = @(Test-Axu4evReleaseArtifacts `
        -ReleaseRoot $labRoot -Manifest $labManifest)

if ($labManifest.release_id -cne 'monopulse-live-lab-v1') {
    throw "Unexpected Lab Candidate release id: $($labManifest.release_id)"
}
if ([bool]$labManifest.board_verified) {
    throw 'New Lab Candidate must remain board_verified=false until controlled-CW acceptance.'
}
$markers = @($labManifest.uart_markers)
if ($markers.Count -ne 1 -or $markers[0] -cne 'PL_FFT_LAB: READY') {
    throw 'Lab Candidate manifest must require only PL_FFT_LAB: READY.'
}

$expectedPaths = [ordered]@{
    application = 'applications/ad9364app.elf'
    bitstream = 'hardware/system_top.bit'
    pmufw = 'firmware/pmufw.elf'
    psu_init = 'hardware/psu_init.tcl'
    xsa = 'hardware/system_top.xsa'
}
$labByName = @{}
foreach ($artifact in $labArtifacts) {
    if (-not $expectedPaths.Contains($artifact.Name) -or
        $labByName.ContainsKey($artifact.Name)) {
        throw "Unexpected or duplicate Lab Candidate artifact: $($artifact.Name)"
    }
    $manifestArtifact = @($labManifest.artifacts |
            Where-Object name -ceq $artifact.Name)
    if ($manifestArtifact.Count -ne 1 -or
        [string]$manifestArtifact[0].path -cne $expectedPaths[$artifact.Name]) {
        throw "Lab Candidate artifact path mismatch: $($artifact.Name)"
    }
    $labByName[$artifact.Name] = $artifact
}
if ($labByName.Count -ne $expectedPaths.Count) {
    throw "Lab Candidate must contain exactly five artifacts; found $($labByName.Count)."
}

$referenceByName = @{}
foreach ($artifact in $referenceArtifacts) {
    $referenceByName[$artifact.Name] = $artifact
}
foreach ($name in @('bitstream', 'pmufw', 'psu_init', 'xsa')) {
    if ($labByName[$name].Sha256 -cne $referenceByName[$name].Sha256) {
        throw "Lab Candidate hardware differs from board-verified single-shot: $name"
    }
}
if ($labByName['application'].Sha256 -ceq $referenceByName['application'].Sha256) {
    throw 'Lab UART application ELF must differ from the single-shot application ELF.'
}

$applicationStream = [IO.File]::OpenRead([string]$labByName['application'].Path)
try {
    $header = New-Object byte[] 4
    if ($applicationStream.Length -lt 4 -or
        $applicationStream.Read($header, 0, $header.Length) -ne 4 -or
        $header[0] -ne 0x7F -or $header[1] -ne 0x45 -or
        $header[2] -ne 0x4C -or $header[3] -ne 0x46) {
        throw 'Lab Candidate application is not an ELF payload.'
    }
}
finally {
    $applicationStream.Dispose()
}

Write-Output 'PASS: Lab UART Candidate package is complete, immutable and hardware-identical.'
