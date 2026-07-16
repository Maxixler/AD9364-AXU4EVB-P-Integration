$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$orchestrator = Join-Path $workspaceRoot 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'
if (-not (Test-Path -LiteralPath $orchestrator -PathType Leaf)) {
    throw "Missing launch orchestrator: $orchestrator"
}

function Invoke-DryRun {
    param([Parameter(Mandatory)][ValidateSet('Golden', 'Workspace')][string]$Mode)

    $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestrator -Mode $Mode -WorkspaceRoot $workspaceRoot -DryRun)
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

Write-Output 'PASS: Golden and Workspace launch orchestration dry-runs resolve verified artifacts.'
