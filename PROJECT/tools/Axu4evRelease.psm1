Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Axu4evCurrentRelease {
    param(
        [Parameter(Mandatory)]
        [string]$ReleasesRoot
    )

    $current = Join-Path $ReleasesRoot 'CURRENT'
    if (-not (Test-Path -LiteralPath $current -PathType Leaf)) {
        throw "Missing CURRENT file: $current"
    }

    $id = (Get-Content -LiteralPath $current -Raw).Trim()
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') {
        throw "Invalid release id in CURRENT: $id"
    }

    $release = Get-Item -LiteralPath (Join-Path $ReleasesRoot $id) -ErrorAction Stop
    if (-not $release.PSIsContainer) {
        throw "CURRENT is not a release directory: $($release.FullName)"
    }

    return $release
}

function Read-Axu4evReleaseManifest {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseRoot
    )

    $path = Join-Path $ReleaseRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing manifest: $path"
    }

    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $manifest.release_id -or @($manifest.artifacts).Count -eq 0) {
        throw "Invalid manifest: $path"
    }

    return $manifest
}

function Test-Axu4evReleaseArtifacts {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseRoot,

        [Parameter(Mandatory)]
        $Manifest
    )

    $root = (Resolve-Path -LiteralPath $ReleaseRoot).Path
    foreach ($artifact in @($Manifest.artifacts)) {
        $relative = [string]$artifact.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe artifact path: $relative"
        }

        $path = Join-Path $root ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing artifact '$($artifact.name)': $path"
        }

        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [int64]$artifact.length) {
            throw "Length mismatch for '$($artifact.name)': $($item.Length) != $($artifact.length)"
        }

        $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($sha -ne ([string]$artifact.sha256).ToUpperInvariant()) {
            throw "SHA-256 mismatch for '$($artifact.name)': $sha"
        }

        [pscustomobject]@{
            Name = $artifact.name
            Path = $item.FullName
            Length = $item.Length
            Sha256 = $sha
        }
    }
}

function New-Axu4evReleaseManifest {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseRoot,

        [Parameter(Mandatory)]
        [hashtable]$Metadata,

        [Parameter(Mandatory)]
        [hashtable]$Artifacts
    )

    $entries = foreach ($name in ($Artifacts.Keys | Sort-Object)) {
        $relative = [string]$Artifacts[$name]
        $path = Join-Path $ReleaseRoot ($relative -replace '/', '\')
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        [ordered]@{
            name = $name
            path = $relative
            length = $item.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }

    [pscustomobject][ordered]@{
        schema_version = 1
        release_id = $Metadata.release_id
        created_at = $Metadata.created_at
        target_board = 'AXU4EVB-P'
        fpga_part = 'xczu4ev-sfvc784-1-i'
        rf_device = 'AD9364'
        tool_version = '2020.1'
        source_commit = $Metadata.source_commit
        board_verified = [bool]$Metadata.board_verified
        uart_markers = @($Metadata.uart_markers)
        artifacts = @($entries)
    }
}

Export-ModuleMember -Function Resolve-Axu4evCurrentRelease, Read-Axu4evReleaseManifest, Test-Axu4evReleaseArtifacts, New-Axu4evReleaseManifest
