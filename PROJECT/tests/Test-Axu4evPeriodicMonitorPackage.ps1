$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$releaseModule = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$singleRoot = Join-Path $candidateBase 'fft-single-shot-v1'
$periodicRoot = Join-Path $candidateBase 'fft-periodic-monitor-v1'

if (-not (Test-Path -LiteralPath $releaseModule -PathType Leaf)) {
    throw "Missing release manifest module: $releaseModule"
}

Import-Module $releaseModule -Force
$singleManifest = Read-Axu4evReleaseManifest -ReleaseRoot $singleRoot
$periodicManifest = Read-Axu4evReleaseManifest -ReleaseRoot $periodicRoot
$singleArtifacts = @(Test-Axu4evReleaseArtifacts -ReleaseRoot $singleRoot -Manifest $singleManifest)
$periodicArtifacts = @(Test-Axu4evReleaseArtifacts -ReleaseRoot $periodicRoot -Manifest $periodicManifest)

if ($periodicManifest.release_id -ne 'fft-periodic-monitor-v1') {
    throw "Unexpected periodic Candidate release id: $($periodicManifest.release_id)"
}
if ($periodicManifest.board_verified) {
    throw 'Periodic Candidate must remain board_verified=false until physical acceptance.'
}
if (@($periodicManifest.uart_markers).Count -ne 1 -or
    @($periodicManifest.uart_markers)[0] -ne 'PL_FFT_MONITOR: PASS') {
    throw 'Periodic Candidate manifest must require the PL_FFT_MONITOR: PASS UART marker.'
}

$expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
$actualNames = @($periodicArtifacts.Name | Sort-Object)
if ($actualNames.Count -ne $expectedNames.Count -or
    ($actualNames -join ',') -ne ($expectedNames -join ',')) {
    throw "Periodic Candidate must contain exactly five artifacts: $($actualNames -join ',')"
}

$singleByName = @{}
foreach ($artifact in $singleArtifacts) {
    $singleByName[$artifact.Name] = $artifact
}
$periodicByName = @{}
foreach ($artifact in $periodicArtifacts) {
    $periodicByName[$artifact.Name] = $artifact
}

if ($singleByName['application'].Sha256 -eq $periodicByName['application'].Sha256) {
    throw 'Periodic application ELF must differ from the single-shot application ELF.'
}
foreach ($name in @('bitstream', 'xsa', 'psu_init', 'pmufw')) {
    if ($singleByName[$name].Sha256 -ne $periodicByName[$name].Sha256) {
        throw "Periodic hardware differs from single-shot: $name"
    }
}

Write-Output 'PASS: periodic FFT Candidate package is complete, unverified, and hardware-identical.'
