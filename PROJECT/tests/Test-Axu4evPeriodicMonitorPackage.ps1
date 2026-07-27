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

function Assert-PeriodicArtifactPaths {
    param(
        [Parameter(Mandatory)]
        $Manifest
    )

    $expectedPaths = [ordered]@{
        application = 'applications/ad9364app.elf'
        bitstream = 'hardware/system_top.bit'
        pmufw = 'firmware/pmufw.elf'
        psu_init = 'hardware/psu_init.tcl'
        xsa = 'hardware/system_top.xsa'
    }
    $actualByName = @{}
    foreach ($artifact in @($Manifest.artifacts)) {
        $name = [string]$artifact.name
        if (-not $expectedPaths.Contains($name) -or $actualByName.ContainsKey($name)) {
            throw "Unexpected or duplicate periodic Candidate artifact name: $name"
        }
        $actualByName[$name] = [string]$artifact.path
    }
    if ($actualByName.Count -ne $expectedPaths.Count) {
        throw "Periodic Candidate manifest must map exactly $($expectedPaths.Count) artifacts."
    }
    foreach ($name in $expectedPaths.Keys) {
        if (-not $actualByName.ContainsKey($name) -or
            $actualByName[$name] -cne $expectedPaths[$name]) {
            throw "Periodic Candidate artifact path mismatch for '$name': $($actualByName[$name])"
        }
    }
}

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
Assert-PeriodicArtifactPaths -Manifest $periodicManifest

$readmeSubstitution = $periodicManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json
@($readmeSubstitution.artifacts | Where-Object name -eq 'application')[0].path = 'README.md'
$substitutionRejected = $false
try {
    Assert-PeriodicArtifactPaths -Manifest $readmeSubstitution
}
catch {
    if ($_.Exception.Message -notmatch "path mismatch for 'application'") {
        throw
    }
    $substitutionRejected = $true
}
if (-not $substitutionRejected) {
    throw 'Periodic Candidate path validation accepted a README substitution for the application artifact.'
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

$applicationPath = [string]$periodicByName['application'].Path
$applicationStream = [IO.File]::OpenRead($applicationPath)
try {
    if ($applicationStream.Length -lt 4) {
        throw "Periodic application ELF is too short: $applicationPath"
    }
    $header = New-Object byte[] 4
    if ($applicationStream.Read($header, 0, $header.Length) -ne 4 -or
        $header[0] -ne 0x7F -or $header[1] -ne 0x45 -or
        $header[2] -ne 0x4C -or $header[3] -ne 0x46) {
        throw "Periodic application is not an ELF payload: $applicationPath"
    }
}
finally {
    $applicationStream.Dispose()
}

Write-Output 'PASS: periodic FFT Candidate package is complete, unverified, and hardware-identical.'
