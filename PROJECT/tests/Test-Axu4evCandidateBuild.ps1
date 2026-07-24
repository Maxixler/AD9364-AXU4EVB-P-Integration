$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$builder = Join-Path $workspaceRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.ps1'
$applicationMain = Join-Path $workspaceRoot 'Vitis\workspace\ad9364app\src\adc9364_src\main.c'
$candidateXsa = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1\hardware\system_top.xsa'
$wrongXsa = Join-Path $workspaceRoot 'vivado\SDR_Real\sdr_wrapper.xsa'

if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "Missing Candidate build orchestrator: $builder"
}
foreach ($xsa in @($candidateXsa, $wrongXsa)) {
    if (-not (Test-Path -LiteralPath $xsa -PathType Leaf)) {
        throw "Missing Candidate build test XSA: $xsa"
    }
}
if (-not (Select-String -LiteralPath $applicationMain `
        -Pattern 'XPAR_AXI_AD9364_FFT_CAPTURE_BASEADDR' -Quiet)) {
    throw 'Application does not support the FFT control macro emitted by the locked Candidate XSA.'
}
$builderContent = Get-Content -LiteralPath $builder -Raw
if (-not $builderContent.Contains('git -C $WorkspaceRoot status --porcelain --untracked-files=no')) {
    throw 'Candidate build does not reject dirty tracked source trees before recording provenance.'
}
if (-not $builderContent.Contains(
        "git -C `$WorkspaceRoot ls-files --others --exclude-standard -- 'Vitis/workspace/ad9364app/src'")) {
    throw 'Candidate build does not reject untracked application sources before recording provenance.'
}
if (-not $builderContent.Contains('Assert-NoReparsePointForWrite')) {
    throw 'Candidate build does not guard output paths against junction/reparse redirection.'
}

$candidateBase = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$candidateRoot = Join-Path $candidateBase "test-build-$([guid]::NewGuid())"
$allowedWorkspaceRoot = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-candidate-vitis-root-$([guid]::NewGuid())"
$candidateWorkspace = Join-Path $allowedWorkspaceRoot 'workspace'
try {
    New-Item -ItemType Directory -Path $allowedWorkspaceRoot -Force | Out-Null
    $dryRunLines = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
            -WorkspaceRoot $workspaceRoot `
            -SourceXsa $candidateXsa `
            -CandidateRoot $candidateRoot `
            -VitisWorkspace $candidateWorkspace `
            -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
            -DryRun
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Candidate build dry-run failed with exit code $LASTEXITCODE."
    }
    $dryRun = ($dryRunLines -join "`n") | ConvertFrom-Json
    if ($dryRun.fft_control_base -ne '0x9C440000' -or
        $dryRun.fft_bank0_base -ne '0x9D000000' -or
        $dryRun.fft_bank1_base -ne '0x9D010000') {
        throw 'Candidate XSA FFT addresses do not match the locked address contract.'
    }
    if (-not $dryRun.pl_fft_single_shot) {
        throw 'Candidate build does not enable PL_FFT_SINGLE_SHOT.'
    }
    if ([IO.Path]::GetFullPath($dryRun.candidate_root) -ne
        [IO.Path]::GetFullPath($candidateRoot)) {
        throw 'Candidate build reported the wrong Candidate root.'
    }

    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $wrongOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
                -WorkspaceRoot $workspaceRoot `
                -SourceXsa $wrongXsa `
                -CandidateRoot $candidateRoot `
                -VitisWorkspace $candidateWorkspace `
                -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
                -DryRun 2>&1
        )
        $wrongExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($wrongExitCode -eq 0) {
        throw 'Candidate build accepted an XSA without the PL FFT hardware.'
    }
    if (($wrongOutput -join "`n") -notmatch 'FFT') {
        throw "Wrong XSA was rejected for an unrelated reason.`r`n$($wrongOutput -join "`r`n")"
    }

    $unsafeWorkspace = Join-Path $workspaceRoot 'PROJECT'
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $unsafeOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
                -WorkspaceRoot $workspaceRoot `
                -SourceXsa $candidateXsa `
                -CandidateRoot $candidateRoot `
                -VitisWorkspace $unsafeWorkspace `
                -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
                -DryRun 2>&1
        )
        $unsafeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($unsafeExitCode -eq 0 -or ($unsafeOutput -join "`n") -notmatch 'approved root') {
        throw 'Candidate build did not reject an unsafe Vitis workspace deletion target.'
    }

    $untrackedInput = Join-Path $workspaceRoot 'Vitis\workspace\ad9364app\src\candidate_untracked_test.c'
    try {
        Set-Content -LiteralPath $untrackedInput -Value 'int candidate_untracked_test;' -Encoding Ascii
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $untrackedOutput = @(
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
                    -WorkspaceRoot $workspaceRoot `
                    -SourceXsa $candidateXsa `
                    -CandidateRoot $candidateRoot `
                    -VitisWorkspace $candidateWorkspace `
                    -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot 2>&1
            )
            $untrackedExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($untrackedExitCode -eq 0 -or ($untrackedOutput -join "`n") -notmatch 'untracked application source') {
            throw 'Candidate build did not reject an untracked application build input.'
        }
    }
    finally {
        Remove-Item -LiteralPath $untrackedInput -Force -ErrorAction SilentlyContinue
    }

    $junctionTarget = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-candidate-junction-target-$([guid]::NewGuid())"
    $junctionPath = Join-Path $candidateBase "test-junction-$([guid]::NewGuid())"
    try {
        New-Item -ItemType Directory -Path $junctionTarget -Force | Out-Null
        New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $junctionOutput = @(
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
                    -WorkspaceRoot $workspaceRoot `
                    -SourceXsa $candidateXsa `
                    -CandidateRoot (Join-Path $junctionPath 'bundle') `
                    -VitisWorkspace $candidateWorkspace `
                    -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
                    -DryRun 2>&1
            )
            $junctionExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($junctionExitCode -eq 0 -or ($junctionOutput -join "`n") -notmatch 'reparse point') {
            throw 'Candidate build accepted a Candidate output redirected through a junction.'
        }
    }
    finally {
        Remove-Item -LiteralPath $junctionPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $junctionTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    foreach ($path in @($candidateWorkspace, $allowedWorkspaceRoot)) {
        $fullPath = [IO.Path]::GetFullPath($path)
        $tempPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($fullPath.StartsWith($tempPath, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $candidatePath = [IO.Path]::GetFullPath($candidateRoot)
    $candidatePrefix = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\') + '\'
    if ($candidatePath.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $candidatePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: Candidate build accepts only the locked PL FFT XSA contract.'
