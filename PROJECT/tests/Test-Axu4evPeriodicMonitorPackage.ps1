$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$releaseModule = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$singleRoot = Join-Path $candidateBase 'fft-single-shot-v1'
$periodicRoot = Join-Path $candidateBase 'fft-periodic-monitor-v1'
$evidenceRelativePath = 'PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt'
$rawRelativePath = 'PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-raw-putty.log'
$jtagRelativePath = 'PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-jtag-launch.log'
$validatorPath = Join-Path $workspaceRoot 'PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1'

if (-not (Test-Path -LiteralPath $releaseModule -PathType Leaf)) {
    throw "Missing release manifest module: $releaseModule"
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $workspaceRoot @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
    return $output
}

function Assert-HeadMatchesWorktree {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    Invoke-Git -Arguments @('cat-file', '-e', "HEAD:$RelativePath") | Out-Null
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $workspaceRoot diff --quiet --no-ext-diff HEAD -- $RelativePath 2>$null
        $matchesHead = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $matchesHead) {
        throw "Committed source differs from working tree: $RelativePath"
    }
}

function Assert-ExactLine {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([array]::IndexOf($Lines, $Expected) -lt 0) {
        throw "Physical acceptance evidence has invalid $Description."
    }
}

function Get-NormalizedUartPayload {
    param([Parameter(Mandatory = $true)][string]$RawPath)

    $rawText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($RawPath))
    $normalizedText = $rawText.Replace([string][char]0, '')
    return @($normalizedText -split "`r?`n" | Where-Object {
        $_ -ceq 'cf-ad9361-lpc: Successfully initialized (61441040 Hz)' -or
        $_ -ceq 'ad9361_init : AD936x Rev 2 successfully initialized' -or
        $_ -like 'PL_FFT_MONITOR:*'
    })
}

function Assert-AcceptanceEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceText,
        [Parameter(Mandatory = $true)][string]$RawPath,
        [Parameter(Mandatory = $true)][string]$JtagPath,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $lines = @($EvidenceText -split "`r?`n" | Where-Object { $_ -ne '' })
    $rawHash = (Get-FileHash -LiteralPath $RawPath -Algorithm SHA256).Hash
    $jtagHash = (Get-FileHash -LiteralPath $JtagPath -Algorithm SHA256).Hash
    $applicationHash = (@($Manifest.artifacts | Where-Object name -eq 'application')[0]).sha256
    $bitstreamHash = (@($Manifest.artifacts | Where-Object name -eq 'bitstream')[0]).sha256

    Assert-ExactLine -Lines $lines -Expected 'Acceptance date (Europe/Istanbul): 2026-07-27' -Description 'acceptance date'
    Assert-ExactLine -Lines $lines -Expected 'Branch at physical run: codex/axu4ev-ad9364-monopulse' -Description 'physical-run branch'
    Assert-ExactLine -Lines $lines -Expected "Candidate manifest source commit: $($Manifest.source_commit)" -Description 'manifest source commit'
    Assert-ExactLine -Lines $lines -Expected "Periodic application ELF SHA-256: $applicationHash" -Description 'application hash'
    Assert-ExactLine -Lines $lines -Expected "Periodic bitstream SHA-256: $bitstreamHash" -Description 'bitstream hash'
    Assert-ExactLine -Lines $lines -Expected "Raw PuTTY log (committed relative path): $rawRelativePath" -Description 'raw PuTTY path'
    Assert-ExactLine -Lines $lines -Expected "Raw PuTTY log SHA-256: $rawHash" -Description 'raw PuTTY hash'
    Assert-ExactLine -Lines $lines -Expected "JTAG launch log (committed relative path): $jtagRelativePath" -Description 'JTAG path'
    Assert-ExactLine -Lines $lines -Expected "JTAG launch log SHA-256: $jtagHash" -Description 'JTAG hash'
    Assert-ExactLine -Lines $lines -Expected 'PuTTY serial settings: PS_UART, 115200-8-N-1, all-session output.' -Description 'PuTTY session settings'
    Assert-ExactLine -Lines $lines -Expected "Strict validator command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 -LogPath $rawRelativePath" -Description 'strict validator command'
    Assert-ExactLine -Lines $lines -Expected 'Strict validator output: PASS: periodic FFT monitor log contains 100 valid frames.' -Description 'strict validator output'
    Assert-ExactLine -Lines $lines -Expected 'RF context: No controlled CW or R&S source was declared for this infrastructure acceptance. Observed low peak powers were ambient-noise input; this acceptance covers monitor transport/control only, not RF performance or DOA calibration.' -Description 'RF scope'
    Assert-ExactLine -Lines $lines -Expected 'Antenna/port wiring: Not independently reverified during this run.' -Description 'antenna/port-wiring scope'

    $launchCommitMatch = [regex]::Match($EvidenceText, '(?m)^Launch commit: ([0-9a-f]{40})\r?$')
    if (-not $launchCommitMatch.Success) {
        throw 'Physical acceptance evidence must contain one full launch commit.'
    }
    $launchCommit = $launchCommitMatch.Groups[1].Value
    Invoke-Git -Arguments @('cat-file', '-e', "$launchCommit^{commit}") | Out-Null
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $workspaceRoot merge-base --is-ancestor $launchCommit HEAD 2>$null
        $launchCommitIsAncestor = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if (-not $launchCommitIsAncestor) {
        throw 'Physical acceptance launch commit is not an ancestor of this acceptance commit.'
    }

    $marker = 'Selected UART payload normalized from committed raw PuTTY log (PuTTY framing and NUL removed):'
    $markerIndexes = @(for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq $marker) { $index }
    })
    if ($markerIndexes.Count -ne 1) {
        throw 'Physical acceptance evidence must contain one normalized-payload marker.'
    }
    $evidencePayload = @($lines[($markerIndexes[0] + 1)..($lines.Count - 1)] | Where-Object { $_ -ne '' })
    $rawPayload = Get-NormalizedUartPayload -RawPath $RawPath
    if ($rawPayload.Count -ne 104 -or $evidencePayload.Count -ne 104 -or
        (Compare-Object -ReferenceObject $rawPayload -DifferenceObject $evidencePayload)) {
        throw 'Normalized UART evidence payload does not exactly match the committed raw PuTTY log.'
    }
}

function Assert-Rejected {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Description)

    try {
        & $Action
    }
    catch {
        return
    }
    throw "Acceptance evidence negative probe was incorrectly accepted: $Description"
}

function Assert-PeriodicArtifactPaths {
    param([Parameter(Mandatory)]$Manifest)

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
        if (-not $actualByName.ContainsKey($name) -or $actualByName[$name] -cne $expectedPaths[$name]) {
            throw "Periodic Candidate artifact path mismatch for '$name': $($actualByName[$name])"
        }
    }
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
    $evidencePath = Join-Path $workspaceRoot $evidenceRelativePath
    $rawPath = Join-Path $workspaceRoot $rawRelativePath
    $jtagPath = Join-Path $workspaceRoot $jtagRelativePath
    foreach ($sourcePath in @($evidencePath, $rawPath, $jtagPath)) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "board_verified=true requires physical acceptance source: $sourcePath"
        }
    }
    foreach ($relativePath in @($evidenceRelativePath, $rawRelativePath, $jtagRelativePath)) {
        Assert-HeadMatchesWorktree -RelativePath $relativePath
    }

    $evidenceText = Get-Content -LiteralPath $evidencePath -Raw
    Assert-AcceptanceEvidence -EvidenceText $evidenceText -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    foreach ($logPath in @($rawPath, $evidencePath)) {
        $validatorOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatorPath -LogPath $logPath 2>&1)
        if ($LASTEXITCODE -ne 0 -or ($validatorOutput -join "`n") -cne 'PASS: periodic FFT monitor log contains 100 valid frames.') {
            throw "Strict periodic monitor log parser rejected: $logPath"
        }
    }

    Assert-Rejected -Description 'CRC substitution' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace('crc=1d8b292d', 'crc=00000000')) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    Assert-Rejected -Description 'blank branch' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace('Branch at physical run: codex/axu4ev-ad9364-monopulse', 'Branch at physical run: ')) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    Assert-Rejected -Description 'wrong raw hash' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace('Raw PuTTY log SHA-256: B3BCA7747B6130DDF39731C39DE28FEA1E31DEC210FD8E2009B43DB751CF8129', 'Raw PuTTY log SHA-256: 0000000000000000000000000000000000000000000000000000000000000000')) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
}
else {
    # Pre-acceptance manifests are valid without physical evidence.
    $preAcceptanceManifest = $periodicManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $preAcceptanceManifest.board_verified = $false
}
if (@($periodicManifest.uart_markers).Count -ne 1 -or @($periodicManifest.uart_markers)[0] -ne 'PL_FFT_MONITOR: PASS') {
    throw 'Periodic Candidate manifest must require the PL_FFT_MONITOR: PASS UART marker.'
}
Assert-PeriodicArtifactPaths -Manifest $periodicManifest

$readmeSubstitution = $periodicManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json
@($readmeSubstitution.artifacts | Where-Object name -eq 'application')[0].path = 'README.md'
Assert-Rejected -Description 'README application substitution' -Action { Assert-PeriodicArtifactPaths -Manifest $readmeSubstitution }

$expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
$actualNames = @($periodicArtifacts.Name | Sort-Object)
if ($actualNames.Count -ne $expectedNames.Count -or ($actualNames -join ',') -ne ($expectedNames -join ',')) {
    throw "Periodic Candidate must contain exactly five artifacts: $($actualNames -join ',')"
}
$singleByName = @{}
foreach ($artifact in $singleArtifacts) { $singleByName[$artifact.Name] = $artifact }
$periodicByName = @{}
foreach ($artifact in $periodicArtifacts) { $periodicByName[$artifact.Name] = $artifact }
if ($singleByName['application'].Sha256 -eq $periodicByName['application'].Sha256) {
    throw 'Periodic application ELF must differ from the single-shot application ELF.'
}
foreach ($name in @('bitstream', 'xsa', 'psu_init', 'pmufw')) {
    if ($singleByName[$name].Sha256 -ne $periodicByName[$name].Sha256) { throw "Periodic hardware differs from single-shot: $name" }
}
$applicationPath = [string]$periodicByName['application'].Path
$applicationStream = [IO.File]::OpenRead($applicationPath)
try {
    $header = New-Object byte[] 4
    if ($applicationStream.Length -lt 4 -or $applicationStream.Read($header, 0, $header.Length) -ne 4 -or $header[0] -ne 0x7F -or $header[1] -ne 0x45 -or $header[2] -ne 0x4C -or $header[3] -ne 0x46) {
        throw "Periodic application is not an ELF payload: $applicationPath"
    }
}
finally { $applicationStream.Dispose() }

if ($periodicManifest.board_verified) {
    Write-Output 'PASS: periodic FFT Candidate package is complete, physically accepted, and hardware-identical.'
}
else {
    Write-Output 'PASS: periodic FFT Candidate package is complete, unverified, and hardware-identical.'
}
