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
    $evidenceRelativePath = 'PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt'
    $evidencePath = Join-Path $workspaceRoot $evidenceRelativePath
    $validatorPath = Join-Path $workspaceRoot 'PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1'

    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        throw "board_verified=true requires physical acceptance evidence: $evidenceRelativePath"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $workspaceRoot cat-file -e "HEAD:$evidenceRelativePath" 2>$null
        $evidenceCommitted = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $evidenceCommitted) {
        throw "board_verified=true requires committed physical acceptance evidence: $evidenceRelativePath"
    }

    $evidenceLines = @(Get-Content -LiteralPath $evidencePath)
    $evidenceText = $evidenceLines -join "`n"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $committedEvidenceLines = @(& git -C $workspaceRoot show "HEAD:$evidenceRelativePath" 2>$null)
        $committedEvidenceRead = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $committedEvidenceRead -or
        (Compare-Object -ReferenceObject $committedEvidenceLines -DifferenceObject $evidenceLines)) {
        throw 'Physical acceptance evidence differs from its committed revision.'
    }
    foreach ($requiredLine in @(
        'Acceptance date (Europe/Istanbul): 2026-07-27',
        'Branch at physical run:',
        'Launch commit:',
        "Candidate manifest source commit: $($periodicManifest.source_commit)",
        "Periodic application ELF SHA-256: $((@($periodicManifest.artifacts | Where-Object name -eq 'application')[0]).sha256)",
        "Periodic bitstream SHA-256: $((@($periodicManifest.artifacts | Where-Object name -eq 'bitstream')[0]).sha256)",
        'Strict validator output: PASS: periodic FFT monitor log contains 100 valid frames.'
    )) {
        if (-not $evidenceText.Contains($requiredLine)) {
            throw "Physical acceptance evidence is missing required metadata: $requiredLine"
        }
    }

    $launchCommitMatch = [regex]::Match($evidenceText, '(?m)^Launch commit: ([0-9a-f]{40})$')
    if (-not $launchCommitMatch.Success) {
        throw 'Physical acceptance evidence must link to a full launch commit.'
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $workspaceRoot cat-file -e "$($launchCommitMatch.Groups[1].Value)^{commit}" 2>$null
        $launchCommitPresent = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $launchCommitPresent) {
        throw 'Physical acceptance evidence launch commit is not present in this repository.'
    }

    $validatorOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatorPath -LogPath $evidencePath 2>&1)
    if ($LASTEXITCODE -ne 0 -or
        ($validatorOutput -join "`n") -notmatch [regex]::Escape('PASS: periodic FFT monitor log contains 100 valid frames.')) {
        throw 'Physical acceptance evidence does not pass the strict periodic monitor log parser.'
    }
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

if ($periodicManifest.board_verified) {
    Write-Output 'PASS: periodic FFT Candidate package is complete, physically accepted, and hardware-identical.'
}
else {
    Write-Output 'PASS: periodic FFT Candidate package is complete, unverified, and hardware-identical.'
}
