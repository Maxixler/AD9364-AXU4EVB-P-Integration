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

function Assert-UniqueMetadataLine {
    param(
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $matches = @($Lines | Where-Object { $_.StartsWith($Key, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1 -or $matches[0] -cne $Expected) {
        throw "Physical acceptance evidence has invalid or non-unique $Description."
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

function Get-JtagPeriodicArtifactRelativePath {
    param([Parameter(Mandatory = $true)][string]$LoggedPath)

    $releaseRootSuffix = 'PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1'
    $normalizedPath = $LoggedPath.Replace('/', '\')
    if (-not [IO.Path]::IsPathRooted($normalizedPath) -or
        $normalizedPath -match '(^|\\)(?:\.|\.\.)(?:\\|$)') {
        throw "JTAG launch evidence has an unsafe artifact path: $LoggedPath"
    }

    $matches = @()
    $searchOffset = 0
    while ($searchOffset -lt $normalizedPath.Length) {
        $index = $normalizedPath.IndexOf(
            $releaseRootSuffix,
            $searchOffset,
            [StringComparison]::Ordinal)
        if ($index -lt 0) {
            break
        }
        $matches += $index
        $searchOffset = $index + $releaseRootSuffix.Length
    }
    if ($matches.Count -ne 1) {
        throw "JTAG launch evidence artifact path has an ambiguous Candidate release suffix: $LoggedPath"
    }
    $releaseIndex = $matches[0]
    $releaseEnd = $releaseIndex + $releaseRootSuffix.Length
    if ($releaseIndex -eq 0 -or
        $normalizedPath[$releaseIndex - 1] -ne '\' -or
        ($releaseEnd -lt $normalizedPath.Length -and $normalizedPath[$releaseEnd] -ne '\')) {
        throw "JTAG launch evidence artifact path is not inside the historical periodic Candidate root: $LoggedPath"
    }

    $relativePath = $normalizedPath.Substring($releaseEnd).TrimStart('\')
    if ([string]::IsNullOrWhiteSpace($relativePath) -or
        $relativePath -match '(^|\\)(?:\.|\.\.)(?:\\|$)' -or
        $relativePath.Contains('\\')) {
        throw "JTAG launch evidence artifact path has an ambiguous Candidate-relative suffix: $LoggedPath"
    }
    return $relativePath
}

function Assert-JtagArtifactManifestMatchesCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$JtagPath,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $jtagText = Get-Content -LiteralPath $JtagPath -Raw
    $manifestLines = @([regex]::Matches(
        $jtagText,
        '(?m)^ARTIFACT_MANIFEST_JSON=(.+?)\r?$'))
    if ($manifestLines.Count -ne 1) {
        throw 'JTAG launch evidence must contain exactly one ARTIFACT_MANIFEST_JSON line.'
    }
    try {
        $jtagArtifacts = $manifestLines[0].Groups[1].Value | ConvertFrom-Json
    }
    catch {
        throw "JTAG launch evidence has invalid ARTIFACT_MANIFEST_JSON: $($_.Exception.Message)"
    }

    $expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
    $expectedByName = @{}
    foreach ($artifact in @($Manifest.artifacts)) {
        $name = [string]$artifact.name
        if ($name -notin $expectedNames -or $expectedByName.ContainsKey($name)) {
            throw "Periodic Candidate manifest has an unexpected or duplicate JTAG-bound artifact: $name"
        }
        $expectedByName[$name] = [pscustomobject]@{
            Path = ([string]$artifact.path).Replace('/', '\')
            Length = [int64]$artifact.length
            Sha256 = [string]$artifact.sha256
        }
    }
    if ($expectedByName.Count -ne $expectedNames.Count) {
        throw 'Periodic Candidate manifest must expose exactly five JTAG-bound artifacts.'
    }

    $actualByName = @{}
    foreach ($artifact in $jtagArtifacts) {
        $name = [string]$artifact.name
        if ($name -notin $expectedNames -or $actualByName.ContainsKey($name)) {
            throw "JTAG launch evidence has an unexpected or duplicate artifact: $name"
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifact.path)) {
            throw "JTAG launch evidence has no path for artifact: $name"
        }
        $actualByName[$name] = [pscustomobject]@{
            Path = Get-JtagPeriodicArtifactRelativePath -LoggedPath ([string]$artifact.path)
            Length = [int64]$artifact.length
            Sha256 = [string]$artifact.sha256
        }
    }
    if ($actualByName.Count -ne $expectedNames.Count) {
        throw 'JTAG launch evidence must bind exactly five Candidate artifacts.'
    }
    foreach ($name in $expectedNames) {
        $expected = $expectedByName[$name]
        $actual = $actualByName[$name]
        if ($actual.Path -cne $expected.Path -or
            $actual.Length -ne $expected.Length -or
            $actual.Sha256 -cne $expected.Sha256) {
            throw "JTAG launch evidence artifact mismatch: $name"
        }
    }

    foreach ($binding in @(
            [pscustomobject]@{ Pattern = '(?m)^(?:RELEASE_ID|ReleaseId|release_id)=(.+?)\r?$'; Expected = [string]$Manifest.release_id; Description = 'release id' },
            [pscustomobject]@{ Pattern = '(?m)^(?:TARGET_BOARD|TargetBoard|target_board)=(.+?)\r?$'; Expected = [string]$Manifest.target_board; Description = 'target board' }
        )) {
        $matches = @([regex]::Matches($jtagText, $binding.Pattern))
        if ($matches.Count -gt 0 -and
            ($matches.Count -ne 1 -or $matches[0].Groups[1].Value -cne $binding.Expected)) {
            throw "JTAG launch evidence $($binding.Description) does not match the periodic Candidate."
        }
    }
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
    Assert-JtagArtifactManifestMatchesCandidate -JtagPath $JtagPath -Manifest $Manifest
    $applicationHash = (@($Manifest.artifacts | Where-Object name -eq 'application')[0]).sha256
    $bitstreamHash = (@($Manifest.artifacts | Where-Object name -eq 'bitstream')[0]).sha256

    $metadata = @(
        [pscustomobject]@{ Key = 'AXU4EVB-P + AD9364 periodic FFT monitor physical acceptance evidence'; Line = 'AXU4EVB-P + AD9364 periodic FFT monitor physical acceptance evidence'; Description = 'evidence title' },
        [pscustomobject]@{ Key = 'Acceptance date (Europe/Istanbul):'; Line = 'Acceptance date (Europe/Istanbul): 2026-07-27'; Description = 'acceptance date' },
        [pscustomobject]@{ Key = 'Branch at physical run:'; Line = 'Branch at physical run: codex/axu4ev-ad9364-monopulse'; Description = 'physical-run branch' },
        [pscustomobject]@{ Key = 'Launch commit:'; Line = 'Launch commit: b0f53f36f8676b54747d417c4ae44c61ac8a3c99'; Description = 'launch commit' },
        [pscustomobject]@{ Key = 'Candidate manifest source commit:'; Line = "Candidate manifest source commit: $($Manifest.source_commit)"; Description = 'manifest source commit' },
        [pscustomobject]@{ Key = 'Periodic application ELF SHA-256:'; Line = "Periodic application ELF SHA-256: $applicationHash"; Description = 'application hash' },
        [pscustomobject]@{ Key = 'Periodic bitstream SHA-256:'; Line = "Periodic bitstream SHA-256: $bitstreamHash"; Description = 'bitstream hash' },
        [pscustomobject]@{ Key = 'Raw PuTTY log (committed relative path):'; Line = "Raw PuTTY log (committed relative path): $rawRelativePath"; Description = 'raw PuTTY path' },
        [pscustomobject]@{ Key = 'Raw PuTTY log SHA-256:'; Line = "Raw PuTTY log SHA-256: $rawHash"; Description = 'raw PuTTY hash' },
        [pscustomobject]@{ Key = 'JTAG launch log (committed relative path):'; Line = "JTAG launch log (committed relative path): $jtagRelativePath"; Description = 'JTAG path' },
        [pscustomobject]@{ Key = 'JTAG launch log SHA-256:'; Line = "JTAG launch log SHA-256: $jtagHash"; Description = 'JTAG hash' },
        [pscustomobject]@{ Key = 'PuTTY serial settings:'; Line = 'PuTTY serial settings: PS_UART, 115200-8-N-1, all-session output.'; Description = 'PuTTY session settings' },
        [pscustomobject]@{ Key = 'Origin note:'; Line = 'Origin note: the committed raw PuTTY and JTAG paths above are the release evidence locators; capture staging paths are not.'; Description = 'origin note' },
        [pscustomobject]@{ Key = 'Strict validator command:'; Line = "Strict validator command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 -LogPath $rawRelativePath"; Description = 'strict validator command' },
        [pscustomobject]@{ Key = 'Strict validator output:'; Line = 'Strict validator output: PASS: periodic FFT monitor log contains 100 valid frames.'; Description = 'strict validator output' },
        [pscustomobject]@{ Key = 'RF context:'; Line = 'RF context: No controlled CW or R&S source was declared for this infrastructure acceptance. Observed low peak powers were ambient-noise input; this acceptance covers monitor transport/control only, not RF performance or DOA calibration.'; Description = 'RF scope' },
        [pscustomobject]@{ Key = 'Antenna/port wiring:'; Line = 'Antenna/port wiring: Not independently reverified during this run.'; Description = 'antenna/port-wiring scope' }
    )
    if ($lines.Count -lt $metadata.Count + 1) {
        throw 'Physical acceptance evidence metadata is incomplete.'
    }
    for ($index = 0; $index -lt $metadata.Count; $index++) {
        if ($lines[$index] -cne $metadata[$index].Line) {
            throw "Physical acceptance evidence metadata order/value mismatch at index $index."
        }
        Assert-UniqueMetadataLine -Lines $lines -Key $metadata[$index].Key -Expected $metadata[$index].Line -Description $metadata[$index].Description
    }

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
    if ($rawPayload.Count -ne 104 -or $evidencePayload.Count -ne 104) {
        throw "Normalized UART evidence payload must contain exactly 104 lines (raw=$($rawPayload.Count), evidence=$($evidencePayload.Count))."
    }
    for ($index = 0; $index -lt 104; $index++) {
        if ($rawPayload[$index] -cne $evidencePayload[$index]) {
            throw "Normalized UART evidence payload differs from committed raw PuTTY log at index $index."
        }
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

function New-JtagManifestFixture {
    param(
        [Parameter(Mandatory = $true)][string]$JtagText,
        [Parameter(Mandatory = $true)][scriptblock]$Transform
    )

    $match = [regex]::Match($JtagText, '(?m)^ARTIFACT_MANIFEST_JSON=(.+?)\r?$')
    if (-not $match.Success) {
        throw 'JTAG fixture source has no artifact manifest.'
    }
    $artifacts = $match.Groups[1].Value | ConvertFrom-Json
    & $Transform $artifacts
    $replacement = 'ARTIFACT_MANIFEST_JSON=' + ($artifacts | ConvertTo-Json -Compress)
    return $JtagText.Substring(0, $match.Index) + $replacement +
        $JtagText.Substring($match.Index + $match.Length)
}

function Invoke-JtagArtifactBindingPortabilityTests {
    param(
        [Parameter(Mandatory = $true)][string]$JtagPath,
        [Parameter(Mandatory = $true)]$Manifest
    )

    $sourceText = Get-Content -LiteralPath $JtagPath -Raw
    $historicalPrefix = 'C:\\Users\\DELL\\Desktop\\Yazilim\\FPGA-Profen-Worktrees\\axu4ev-ad9364-monopulse'
    $relocatedPrefix = 'D:\\archived-checkouts\\axu4ev-ad9364-monopulse'
    if (([regex]::Matches($sourceText, [regex]::Escape($historicalPrefix))).Count -ne 5) {
        throw 'JTAG portability fixture expected five historical checkout prefixes.'
    }
    $relocatedText = $sourceText.Replace($historicalPrefix, $relocatedPrefix)
    $fixturePath = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-jtag-portability-$([guid]::NewGuid()).log"
    try {
        Set-Content -LiteralPath $fixturePath -Value $relocatedText -Encoding Unicode
        Assert-JtagArtifactManifestMatchesCandidate -JtagPath $fixturePath -Manifest $Manifest

        Assert-Rejected -Description 'JTAG artifact path selects the wrong release' -Action {
            $wrongRelease = New-JtagManifestFixture -JtagText $relocatedText -Transform {
                param($artifacts)
                $artifacts[0].path = $artifacts[0].path.Replace(
                    'fft-periodic-monitor-v1', 'fft-single-shot-v1')
            }
            Set-Content -LiteralPath $fixturePath -Value $wrongRelease -Encoding Unicode
            Assert-JtagArtifactManifestMatchesCandidate -JtagPath $fixturePath -Manifest $Manifest
        }
        Assert-Rejected -Description 'JTAG artifact path traversal' -Action {
            $traversal = New-JtagManifestFixture -JtagText $relocatedText -Transform {
                param($artifacts)
                $artifacts[0].path = $artifacts[0].path.Replace(
                    'hardware\system_top.bit', 'hardware\..\hardware\system_top.bit')
            }
            Set-Content -LiteralPath $fixturePath -Value $traversal -Encoding Unicode
            Assert-JtagArtifactManifestMatchesCandidate -JtagPath $fixturePath -Manifest $Manifest
        }
        Assert-Rejected -Description 'JTAG artifact path contains a duplicate release suffix' -Action {
            $duplicateSuffix = New-JtagManifestFixture -JtagText $relocatedText -Transform {
                param($artifacts)
                $artifacts[0].path = $artifacts[0].path.Replace(
                    'fft-periodic-monitor-v1\hardware',
                    'fft-periodic-monitor-v1\PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1\hardware')
            }
            Set-Content -LiteralPath $fixturePath -Value $duplicateSuffix -Encoding Unicode
            Assert-JtagArtifactManifestMatchesCandidate -JtagPath $fixturePath -Manifest $Manifest
        }
    }
    finally {
        Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BoardVerificationGate {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory = $true)][scriptblock]$EvidenceCheck
    )

    if ([bool]$Manifest.board_verified) {
        & $EvidenceCheck
    }
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

function Assert-DeterministicPsuInitMaterialization {
    param(
        [Parameter(Mandatory = $true)]$SingleManifest,
        [Parameter(Mandatory = $true)]$PeriodicManifest
    )

    $relativePaths = @(
        'PROJECT/candidates/axu4ev-ad9364/fft-single-shot-v1/hardware/psu_init.tcl',
        'PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/hardware/psu_init.tcl'
    )
    $attributeOutput = @(Invoke-Git -Arguments (@('check-attr', 'text', 'eol', '--') + $relativePaths))
    foreach ($relativePath in $relativePaths) {
        if ($attributeOutput -notcontains "${relativePath}: text: set" -or
            $attributeOutput -notcontains "${relativePath}: eol: crlf") {
            throw "psu_init checkout policy is not deterministic CRLF: $relativePath"
        }
    }

    $materializationRoot = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-psu-init-$([guid]::NewGuid())"
    try {
        New-Item -ItemType Directory -Path $materializationRoot -Force | Out-Null
        & git -C $workspaceRoot -c core.autocrlf=false checkout-index `
            --prefix="$materializationRoot\" -- $relativePaths
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot materialize psu_init files with core.autocrlf=false.'
        }

        $manifests = @($SingleManifest, $PeriodicManifest)
        for ($index = 0; $index -lt $relativePaths.Count; $index++) {
            $expected = @($manifests[$index].artifacts |
                Where-Object name -eq 'psu_init')[0].sha256
            $materialized = Join-Path $materializationRoot $relativePaths[$index]
            if ((Get-FileHash -LiteralPath $materialized -Algorithm SHA256).Hash -cne $expected) {
                throw "psu_init materialized hash does not match its manifest: $($relativePaths[$index])"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $materializationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Import-Module $releaseModule -Force
$singleManifest = Read-Axu4evReleaseManifest -ReleaseRoot $singleRoot
$periodicManifest = Read-Axu4evReleaseManifest -ReleaseRoot $periodicRoot
$singleArtifacts = @(Test-Axu4evReleaseArtifacts -ReleaseRoot $singleRoot -Manifest $singleManifest)
$periodicArtifacts = @(Test-Axu4evReleaseArtifacts -ReleaseRoot $periodicRoot -Manifest $periodicManifest)
Assert-DeterministicPsuInitMaterialization -SingleManifest $singleManifest -PeriodicManifest $periodicManifest

if ($periodicManifest.release_id -ne 'fft-periodic-monitor-v1') {
    throw "Unexpected periodic Candidate release id: $($periodicManifest.release_id)"
}
$preAcceptanceManifest = $periodicManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json
$preAcceptanceManifest.board_verified = $false
Invoke-BoardVerificationGate -Manifest $preAcceptanceManifest -EvidenceCheck {
    throw 'board_verified=false must not require physical acceptance evidence.'
}

Invoke-BoardVerificationGate -Manifest $periodicManifest -EvidenceCheck {
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
    Invoke-JtagArtifactBindingPortabilityTests -JtagPath $jtagPath -Manifest $periodicManifest
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
    Assert-Rejected -Description 'swapped initialization lines' -Action {
        $initializationPair = [regex]::Escape('cf-ad9361-lpc: Successfully initialized (61441040 Hz)') +
            '\r?\n' + [regex]::Escape('ad9361_init : AD936x Rev 2 successfully initialized')
        $swapped = [regex]::Replace(
            $evidenceText,
            $initializationPair,
            "ad9361_init : AD936x Rev 2 successfully initialized`ncf-ad9361-lpc: Successfully initialized (61441040 Hz)")
        Assert-AcceptanceEvidence -EvidenceText $swapped -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    Assert-Rejected -Description 'uppercase CRC' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace('crc=1d8b292d', 'crc=1D8B292D')) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    Assert-Rejected -Description 'duplicate blank branch' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace('Branch at physical run: codex/axu4ev-ad9364-monopulse', "Branch at physical run: codex/axu4ev-ad9364-monopulse`r`nBranch at physical run: ")) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    Assert-Rejected -Description 'duplicate contradictory raw path' -Action {
        Assert-AcceptanceEvidence -EvidenceText ($evidenceText.Replace("Raw PuTTY log (committed relative path): $rawRelativePath", "Raw PuTTY log (committed relative path): $rawRelativePath`r`nRaw PuTTY log (committed relative path): PROJECT/tests/evidence/not-the-accepted-log.log")) -RawPath $rawPath -JtagPath $jtagPath -Manifest $periodicManifest
    }
    $staleApplicationManifest = $periodicManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    @($staleApplicationManifest.artifacts | Where-Object name -eq 'application')[0].sha256 =
        'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
    $staleApplicationEvidence = $evidenceText.Replace(
        "Periodic application ELF SHA-256: $(@($periodicManifest.artifacts | Where-Object name -eq 'application')[0].sha256)",
        "Periodic application ELF SHA-256: $(@($staleApplicationManifest.artifacts | Where-Object name -eq 'application')[0].sha256)")
    Assert-Rejected -Description 'stale JTAG application manifest after replacement' -Action {
        Assert-AcceptanceEvidence -EvidenceText $staleApplicationEvidence -RawPath $rawPath -JtagPath $jtagPath -Manifest $staleApplicationManifest
    }
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
