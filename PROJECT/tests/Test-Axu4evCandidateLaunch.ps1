$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$orchestrator = Join-Path $workspaceRoot 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'
$releaseModule = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$candidateLauncher = Join-Path $workspaceRoot 'PROJECT\tools\Start-Axu4evAd9364Candidate.cmd'
$goldenRoot = Join-Path $workspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$sourceCandidate = Join-Path $candidateBase 'fft-single-shot-v1'

foreach ($required in @($orchestrator, $releaseModule, $candidateLauncher)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing Candidate launch dependency: $required"
    }
}

Import-Module $releaseModule -Force
$tempRoot = Join-Path $candidateBase "test-$([guid]::NewGuid())"
$candidateRoot = Join-Path $tempRoot 'fft-single-shot-test'
$nonCurrentGolden = Join-Path $goldenRoot "test-non-current-$([guid]::NewGuid())"

try {
    Copy-Item -LiteralPath $sourceCandidate -Destination $candidateRoot -Recurse
    $relativeArtifacts = [ordered]@{
        application = 'applications/ad9364app.elf'
        bitstream = 'hardware/system_top.bit'
        pmufw = 'firmware/pmufw.elf'
        psu_init = 'hardware/psu_init.tcl'
        xsa = 'hardware/system_top.xsa'
    }
    $output = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
            -Mode Candidate `
            -WorkspaceRoot $workspaceRoot `
            -CandidateRoot $candidateRoot `
            -DryRun
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Candidate-only dry-run failed with exit code $LASTEXITCODE."
    }
    $result = ($output -join "`n") | ConvertFrom-Json
    $actualNames = @($result.artifacts.name | Sort-Object)
    $expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
    if (($actualNames -join ',') -ne ($expectedNames -join ',')) {
        throw "Candidate dry-run did not resolve all five Candidate artifacts: $($actualNames -join ',')"
    }
    foreach ($artifact in @($result.artifacts)) {
        $fullPath = [IO.Path]::GetFullPath($artifact.path)
        if (-not $fullPath.StartsWith(
                [IO.Path]::GetFullPath($candidateRoot) + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Candidate artifact escaped Candidate root: $fullPath"
        }
    }

    $currentGolden = Resolve-Axu4evCurrentRelease $goldenRoot
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $goldenOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
                -Mode Candidate `
                -WorkspaceRoot $workspaceRoot `
                -CandidateRoot $currentGolden.FullName `
                -DryRun 2>&1
        )
        $goldenExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($goldenExitCode -eq 0) {
        throw 'Candidate mode accepted the current Golden release directory.'
    }
    if (($goldenOutput -join "`n") -notmatch 'Golden') {
        throw "Golden rejection failed for the wrong reason.`r`n$($goldenOutput -join "`r`n")"
    }

    Copy-Item -LiteralPath $sourceCandidate -Destination $nonCurrentGolden -Recurse
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nonCurrentOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
                -Mode Candidate `
                -WorkspaceRoot $workspaceRoot `
                -CandidateRoot $nonCurrentGolden `
                -DryRun 2>&1
        )
        $nonCurrentExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($nonCurrentExitCode -eq 0 -or ($nonCurrentOutput -join "`n") -notmatch 'Golden release tree') {
        throw 'Candidate mode accepted a non-current release under the Golden tree.'
    }

    $goldenManifest = Read-Axu4evReleaseManifest $currentGolden.FullName
    $goldenArtifacts = @(Test-Axu4evReleaseArtifacts $currentGolden.FullName $goldenManifest)
    $goldenBitstream = @($goldenArtifacts | Where-Object Name -eq 'bitstream')[0].Path
    Copy-Item -LiteralPath $goldenBitstream `
        -Destination (Join-Path $candidateRoot 'hardware\system_top.bit') -Force
    $mismatchManifest = New-Axu4evReleaseManifest `
        -ReleaseRoot $candidateRoot `
        -Metadata @{
            release_id = 'fft-single-shot-mismatch'
            created_at = '2026-07-24T00:00:00+03:00'
            source_commit = 'test'
            board_verified = $false
            uart_markers = @('PL_FFT: PASS')
        } `
        -Artifacts $relativeArtifacts
    $mismatchManifest | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $candidateRoot 'manifest.json') -Encoding UTF8
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $mismatchOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
                -Mode Candidate `
                -WorkspaceRoot $workspaceRoot `
                -CandidateRoot $candidateRoot `
                -DryRun 2>&1
        )
        $mismatchExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($mismatchExitCode -eq 0 -or ($mismatchOutput -join "`n") -notmatch 'embedded bitstream') {
        throw 'Candidate mode accepted an XSA/bitstream mismatch with a self-consistent manifest.'
    }

    $launcherContent = Get-Content -LiteralPath $candidateLauncher -Raw
    foreach ($fragment in @('-CandidateRoot', 'PROJECT\candidates\axu4ev-ad9364')) {
        if (-not $launcherContent.Contains($fragment)) {
            throw "Candidate CMD launcher is missing required fragment: $fragment"
        }
    }
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $candidatePrefix = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\') + '\'
    if ($resolvedTemp.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
    $resolvedGolden = [IO.Path]::GetFullPath($nonCurrentGolden)
    $goldenPrefix = [IO.Path]::GetFullPath($goldenRoot).TrimEnd('\') + '\'
    if ($resolvedGolden.StartsWith($goldenPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedGolden -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: Candidate launch requires a complete non-Golden artifact bundle.'
