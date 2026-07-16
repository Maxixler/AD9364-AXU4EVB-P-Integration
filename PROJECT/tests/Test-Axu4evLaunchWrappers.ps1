$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$orchestrator = Join-Path $workspaceRoot 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'
if (-not (Test-Path -LiteralPath $orchestrator -PathType Leaf)) {
    throw "Missing launch orchestrator: $orchestrator"
}
$orchestratorContent = Get-Content -LiteralPath $orchestrator -Raw
foreach ($fragment in @(
    'Set-Content -LiteralPath $logPath -Encoding Unicode',
    'Add-Content -LiteralPath $logPath -Encoding Unicode'
)) {
    if (-not $orchestratorContent.Contains($fragment)) {
        throw "Launch orchestrator does not keep the XSCT log in one Windows PowerShell encoding: $fragment"
    }
}

function Invoke-DryRun {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Golden', 'Workspace', 'Candidate')]
        [string]$Mode,

        [string]$CandidateApplication
    )

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $orchestrator,
        '-Mode', $Mode, '-WorkspaceRoot', $workspaceRoot, '-DryRun'
    )
    if ($CandidateApplication) {
        $arguments += @('-CandidateApplication', $CandidateApplication)
    }
    $lines = @(& powershell.exe @arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "$Mode dry-run failed with exit code $LASTEXITCODE."
    }
    return (($lines -join "`n") | ConvertFrom-Json)
}

$expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init')
foreach ($mode in @('Golden', 'Workspace')) {
    $result = Invoke-DryRun -Mode $mode
    if ($result.mode -ne $mode) {
        throw "$mode dry-run reported mode '$($result.mode)'."
    }
    if ($result.xsct -ne 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat') {
        throw "$mode dry-run selected the wrong XSCT executable."
    }
    if (-not (Test-Path -LiteralPath $result.tcl -PathType Leaf)) {
        throw "$mode dry-run reported a missing Tcl script."
    }
    if ([IO.Path]::GetFullPath($result.log).IndexOf([IO.Path]::GetFullPath((Join-Path $workspaceRoot 'PROJECT\logs\jtag')), [StringComparison]::OrdinalIgnoreCase) -ne 0) {
        throw "$mode dry-run log is outside PROJECT\logs\jtag."
    }

    $artifacts = @($result.artifacts)
    $actualNames = @($artifacts.name | Sort-Object)
    if (($actualNames -join ',') -ne ($expectedNames -join ',')) {
        throw "$mode dry-run did not resolve the four launch artifacts."
    }
    foreach ($artifact in $artifacts) {
        if (-not (Test-Path -LiteralPath $artifact.path -PathType Leaf)) {
            throw "$mode dry-run reported missing artifact '$($artifact.name)'."
        }
        if ([int64]$artifact.length -le 0 -or [string]$artifact.sha256 -notmatch '^[0-9A-F]{64}$') {
            throw "$mode dry-run reported invalid integrity data for '$($artifact.name)'."
        }
        $actualHash = (Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash
        if ($actualHash -ne $artifact.sha256) {
            throw "$mode dry-run hash mismatch for '$($artifact.name)'."
        }
    }
}

$candidateTemp = Join-Path ([IO.Path]::GetTempPath()) "ad9364app-candidate-$([guid]::NewGuid()).elf"
try {
    Set-Content -LiteralPath $candidateTemp -Value 'candidate-app' -NoNewline
    $golden = Invoke-DryRun -Mode Golden
    $candidate = Invoke-DryRun -Mode Candidate -CandidateApplication $candidateTemp

    foreach ($name in @('bitstream', 'pmufw', 'psu_init')) {
        $goldenArtifact = @($golden.artifacts | Where-Object name -eq $name)[0]
        $candidateArtifact = @($candidate.artifacts | Where-Object name -eq $name)[0]
        if ($candidateArtifact.sha256 -ne $goldenArtifact.sha256) {
            throw "Candidate $name did not come from the current Golden release."
        }
    }
    $candidateApp = @($candidate.artifacts | Where-Object name -eq 'application')[0]
    if ([IO.Path]::GetFullPath($candidateApp.path) -ne [IO.Path]::GetFullPath($candidateTemp)) {
        throw 'Candidate did not use the explicit test application.'
    }
}
finally {
    Remove-Item -LiteralPath $candidateTemp -Force -ErrorAction SilentlyContinue
}

foreach ($mode in @('Golden', 'Workspace', 'Candidate')) {
    $launcher = Join-Path $workspaceRoot "PROJECT\tools\Start-Axu4evAd9364$mode.cmd"
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "Missing $mode launcher: $launcher"
    }
    $content = Get-Content -LiteralPath $launcher -Raw
    foreach ($fragment in @(
        '%~dp0',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass',
        'Invoke-Axu4evAd9364Launch.ps1',
        "-Mode $mode",
        'set "RC=%ERRORLEVEL%"',
        'pause',
        'exit /b %RC%'
    )) {
        if (-not $content.Contains($fragment)) {
            throw "$mode launcher is missing required fragment: $fragment"
        }
    }
}

$logIgnore = Join-Path $workspaceRoot 'PROJECT\logs\jtag\.gitignore'
if (-not (Test-Path -LiteralPath $logIgnore -PathType Leaf)) {
    throw "Missing JTAG log ignore file: $logIgnore"
}
$ignoreContent = Get-Content -LiteralPath $logIgnore -Raw
if (-not $ignoreContent.Contains('*') -or -not $ignoreContent.Contains('!.gitignore')) {
    throw 'JTAG log ignore file does not exclude runtime logs while retaining itself.'
}

Write-Output 'PASS: Golden, Workspace, and Candidate launchers resolve the intended verified artifacts.'
