[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleaseId,

    [string]$WorkspaceRoot,

    [switch]$BoardVerified
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

Import-Module (Join-Path $PSScriptRoot 'Axu4evRelease.psm1') -Force

if ($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') {
    throw "Invalid release id: $ReleaseId"
}

$releaseBase = Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$final = Join-Path $releaseBase $ReleaseId
if (Test-Path -LiteralPath $final) {
    throw "Release already exists: $final"
}

New-Item -ItemType Directory -Path $releaseBase -Force | Out-Null
$temp = Join-Path $releaseBase ('.creating-' + [guid]::NewGuid())

$sources = @{
    bitstream = 'Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit'
    xsa = 'Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.sdk\system_top.xsa'
    psu_init = 'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl'
    pmufw = 'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf'
    application = 'Vitis\workspace\ad9364app\Debug\ad9364app.elf'
}

$destinations = @{
    bitstream = 'hardware/system_top.bit'
    xsa = 'hardware/system_top.xsa'
    psu_init = 'hardware/psu_init.tcl'
    pmufw = 'firmware/pmufw.elf'
    application = 'applications/ad9364app.elf'
}

try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    foreach ($name in $sources.Keys) {
        $source = Join-Path $WorkspaceRoot $sources[$name]
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Missing source artifact '$name': $source"
        }

        $destination = Join-Path $temp ($destinations[$name] -replace '/', '\')
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }

    $sourceCommit = 'unknown'
    if (Test-Path -LiteralPath (Join-Path $WorkspaceRoot '.git')) {
        $gitSafeRoot = $WorkspaceRoot -replace '\\', '/'
        $gitOutput = & git -c "safe.directory=$gitSafeRoot" -C $WorkspaceRoot rev-parse HEAD
        if ($LASTEXITCODE -eq 0 -and $gitOutput) {
            $sourceCommit = ([string]$gitOutput).Trim()
        }
    }

    $metadata = @{
        release_id = $ReleaseId
        created_at = (Get-Date).ToString('o')
        source_commit = $sourceCommit
        board_verified = [bool]$BoardVerified
        uart_markers = @(
            'AD936x Rev 2 successfully initialized',
            'DMA_EXAMPLE:',
            'Done.'
        )
    }

    $manifest = New-Axu4evReleaseManifest -ReleaseRoot $temp -Metadata $metadata -Artifacts $destinations
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temp 'manifest.json') -Encoding UTF8
    Test-Axu4evReleaseArtifacts $temp $manifest | Out-Null

    @"
# $ReleaseId

Immutable AXU4EVB-P + AD9364 release. See `manifest.json` for exact artifact hashes.
"@ | Set-Content -LiteralPath (Join-Path $temp 'README.md') -Encoding UTF8

    Move-Item -LiteralPath $temp -Destination $final
    Write-Output "PASS: Created immutable release $ReleaseId"
}
catch {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    throw
}
