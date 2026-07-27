$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceBuilder = Join-Path $workspaceRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.ps1'
$sourceBuildTcl = Join-Path $workspaceRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
$sourceReleaseModule = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$referenceRoot = Join-Path $candidateBase 'fft-single-shot-v1'
$sourceXsa = Join-Path $referenceRoot 'hardware\system_top.xsa'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-lab-build-$([guid]::NewGuid())"
$fixtureTools = Join-Path $fixtureRoot 'PROJECT\tools'
$fixtureCandidateBase = Join-Path $fixtureRoot 'PROJECT\candidates\axu4ev-ad9364'
$fixtureReferenceRoot = Join-Path $fixtureCandidateBase 'fft-single-shot-v1'
$builder = Join-Path $fixtureTools 'Build-Axu4evPlFftCandidate.ps1'
$buildTcl = Join-Path $fixtureTools 'Build-Axu4evPlFftCandidate.tcl'
$fixtureXsa = Join-Path $fixtureReferenceRoot 'hardware\system_top.xsa'
$candidateRoot = Join-Path $fixtureCandidateBase "test-lab-build-$([guid]::NewGuid())"
$allowedWorkspaceRoot = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-lab-vitis-$([guid]::NewGuid())"
$vitisWorkspace = Join-Path $allowedWorkspaceRoot 'workspace'
$launcher = Join-Path $workspaceRoot 'PROJECT\tools\Start-Axu4evAd9364LabConsole.cmd'

foreach ($path in @($sourceBuilder, $sourceBuildTcl, $sourceReleaseModule, $sourceXsa)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Lab Candidate build dependency: $path"
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureTools, $allowedWorkspaceRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourceBuilder -Destination $builder -Force
    Copy-Item -LiteralPath $sourceBuildTcl -Destination $buildTcl -Force
    Copy-Item -LiteralPath $sourceReleaseModule `
        -Destination (Join-Path $fixtureTools 'Axu4evRelease.psm1') -Force
    Copy-Item -LiteralPath $referenceRoot -Destination $fixtureReferenceRoot -Recurse -Force
    & git -C $fixtureRoot init -q
    & git -C $fixtureRoot config user.email 'lab-candidate-test@example.invalid'
    & git -C $fixtureRoot config user.name 'Lab Candidate Build Test'
    & git -C $fixtureRoot add .
    & git -C $fixtureRoot commit -q -m 'lab Candidate build fixture'
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot commit Lab Candidate build fixture.'
    }

    $output = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
            -WorkspaceRoot $fixtureRoot `
            -ApplicationMode LabUart `
            -SourceXsa $fixtureXsa `
            -CandidateRoot $candidateRoot `
            -VitisWorkspace $vitisWorkspace `
            -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
            -DryRun
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Lab Candidate dry-run failed with exit code $LASTEXITCODE."
    }
    $description = ($output -join "`n") | ConvertFrom-Json
    if ($description.application_mode -cne 'LabUart' -or
        $description.compiler_symbol -cne 'PL_FFT_LAB_UART' -or
        -not [bool]$description.pl_fft_lab_uart -or
        [bool]$description.pl_fft_single_shot -or
        [bool]$description.pl_fft_periodic_monitor) {
        throw 'Lab Candidate dry-run selected the wrong compiler contract.'
    }

    foreach ($protectedId in @('fft-single-shot-v1', 'fft-periodic-monitor-v1')) {
        $protectedRoot = Join-Path $fixtureCandidateBase $protectedId
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $protectedOutput = @(
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
                    -WorkspaceRoot $fixtureRoot `
                    -ApplicationMode LabUart `
                    -SourceXsa $fixtureXsa `
                    -CandidateRoot $protectedRoot `
                    -VitisWorkspace $vitisWorkspace `
                    -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
                    -DryRun 2>&1
            )
            $protectedExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($protectedExitCode -eq 0 -or
            ($protectedOutput -join "`n") -notmatch 'accepted Candidate bundle') {
            throw "Lab Candidate build accepted protected bundle overlap: $protectedId"
        }
    }

    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "Missing Lab Candidate launcher: $launcher"
    }
    $launcherText = Get-Content -LiteralPath $launcher -Raw
    foreach ($fragment in @(
            'monopulse-live-lab-v1',
            'Invoke-Axu4evAd9364Launch.ps1',
            '-Mode Candidate',
            '%*',
            'exit /b %RC%'
        )) {
        if (-not $launcherText.Contains($fragment)) {
            throw "Lab Candidate launcher is missing required fragment: $fragment"
        }
    }
    if ($launcherText.Contains('fft-single-shot-v1') -or
        $launcherText.Contains('fft-periodic-monitor-v1')) {
        throw 'Lab Candidate launcher can select a historical Candidate bundle.'
    }
}
finally {
    Remove-Item -LiteralPath $allowedWorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: Lab UART Candidate build mode and launcher are isolated.'
