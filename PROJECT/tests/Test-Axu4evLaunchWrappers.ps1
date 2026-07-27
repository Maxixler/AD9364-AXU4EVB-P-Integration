$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$orchestrator = Join-Path $workspaceRoot 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'
if (-not (Test-Path -LiteralPath $orchestrator -PathType Leaf)) {
    throw "Missing launch orchestrator: $orchestrator"
}
$orchestratorContent = Get-Content -LiteralPath $orchestrator -Raw
foreach ($fragment in @(
    'Set-Content -LiteralPath $logPath -Encoding Unicode',
    'Add-Content -LiteralPath $logPath -Encoding Unicode',
    'ConvertTo-Json -InputObject @($artifacts) -Depth 4 -Compress',
    'ARTIFACT_MANIFEST_JSON=$artifactManifest'
)) {
    if (-not $orchestratorContent.Contains($fragment)) {
        throw "Launch orchestrator does not keep the XSCT log in one Windows PowerShell encoding: $fragment"
    }
}
if ($orchestratorContent.Contains('Format-Table')) {
    throw 'Launch orchestrator still writes a truncating artifact table to real launch logs.'
}

function Invoke-DryRun {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Golden', 'Workspace', 'Candidate')]
        [string]$Mode,

        [string]$CandidateRoot,

        [string]$TestWorkspaceRoot = $workspaceRoot
    )

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $orchestrator,
        '-Mode', $Mode, '-WorkspaceRoot', $TestWorkspaceRoot, '-DryRun'
    )
    if ($CandidateRoot) {
        $arguments += @('-CandidateRoot', $CandidateRoot)
    }
    $lines = @(& powershell.exe @arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "$Mode dry-run failed with exit code $LASTEXITCODE."
    }
    return (($lines -join "`n") | ConvertFrom-Json)
}

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

    $expectedNames = @('application', 'bitstream', 'pmufw', 'psu_init')
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

$candidateRoot = Join-Path $workspaceRoot 'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1'
$candidate = Invoke-DryRun -Mode Candidate -CandidateRoot $candidateRoot
$candidateNames = @($candidate.artifacts.name | Sort-Object)
$expectedCandidateNames = @('application', 'bitstream', 'pmufw', 'psu_init', 'xsa')
if (($candidateNames -join ',') -ne ($expectedCandidateNames -join ',')) {
    throw 'Candidate dry-run did not resolve the complete five-artifact bundle.'
}
foreach ($artifact in @($candidate.artifacts)) {
    $fullPath = [IO.Path]::GetFullPath($artifact.path)
    if (-not $fullPath.StartsWith(
            [IO.Path]::GetFullPath($candidateRoot) + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Candidate artifact escaped the Candidate bundle: $fullPath"
    }
}

if (-not $orchestratorContent.Contains('Write-Verbose ($handoffOutput -join [Environment]::NewLine)')) {
    throw 'Workspace launch no longer reports successful handoff verification in verbose mode.'
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
