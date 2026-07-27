$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$orchestrator = Join-Path $workspaceRoot 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'
$launcher = Join-Path $workspaceRoot 'PROJECT\tools\Start-Axu4evAd9364PeriodicMonitor.cmd'
$periodicRoot = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1'

foreach ($required in @($orchestrator, $launcher)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing periodic Candidate launch dependency: $required"
    }
}

$launcherContent = Get-Content -LiteralPath $launcher -Raw
if ($launcherContent -notmatch 'fft-periodic-monitor-v1' -or
    $launcherContent -match 'fft-single-shot-v1') {
    throw 'Periodic CMD must select only fft-periodic-monitor-v1.'
}

$wrapperCommand = 'echo.| call "{0}" -DryRun' -f $launcher
$wrapperOutput = @(& cmd.exe /d /c $wrapperCommand 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Periodic CMD dry-run failed with exit code $LASTEXITCODE."
}
$wrapperText = $wrapperOutput -join "`n"
if ($wrapperText -notmatch 'Periodic monitor launched\. Wait for the final PASS in PuTTY\.') {
    throw "Periodic CMD did not report a successful dry-run launch.`r`n$wrapperText"
}

$output = @(
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
        -Mode Candidate `
        -WorkspaceRoot $workspaceRoot `
        -CandidateRoot $periodicRoot `
        -DryRun
)
if ($LASTEXITCODE -ne 0) {
    throw "Periodic Candidate launch dry-run failed with exit code $LASTEXITCODE."
}
$result = ($output -join "`n") | ConvertFrom-Json
if ($result.mode -ne 'Candidate') {
    throw "Periodic launch selected '$($result.mode)' instead of Candidate mode."
}
$expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
$actualNames = @($result.artifacts.name | Sort-Object)
if ($actualNames.Count -ne $expectedNames.Count -or
    ($actualNames -join ',') -ne ($expectedNames -join ',')) {
    throw "Periodic launch did not resolve exactly five artifacts: $($actualNames -join ',')"
}

$rootPrefix = [IO.Path]::GetFullPath($periodicRoot).TrimEnd('\') + '\'
foreach ($artifact in @($result.artifacts)) {
    $path = [IO.Path]::GetFullPath([string]$artifact.path)
    if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Periodic launch artifact escaped Candidate root: $path"
    }
}

$candidateBase = Split-Path $periodicRoot -Parent
$junctionRoot = Join-Path $candidateBase "test-periodic-launch-junction-$([guid]::NewGuid())"
try {
    New-Item -ItemType Junction -Path $junctionRoot -Target $periodicRoot | Out-Null
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $junctionOutput = @(
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator `
                -Mode Candidate `
                -WorkspaceRoot $workspaceRoot `
                -CandidateRoot $junctionRoot `
                -DryRun 2>&1
        )
        $junctionExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($junctionExitCode -eq 0 -or
        ($junctionOutput -join "`n") -notmatch 'reparse point') {
        throw 'Periodic launch accepted a Candidate path redirected through a junction.'
    }
}
finally {
    if (Test-Path -LiteralPath $junctionRoot) {
        $junctionItem = Get-Item -LiteralPath $junctionRoot
        $candidatePrefix = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\') + '\'
        if (($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
            -not $junctionItem.FullName.StartsWith(
                $candidatePrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an unsafe periodic launch test path: $($junctionItem.FullName)"
        }
        [IO.Directory]::Delete($junctionItem.FullName)
    }
}

Write-Output 'PASS: periodic FFT Candidate launcher resolves only its complete Candidate bundle.'
