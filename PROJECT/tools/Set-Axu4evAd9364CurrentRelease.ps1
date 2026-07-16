[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleaseId,

    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

Import-Module (Join-Path $PSScriptRoot 'Axu4evRelease.psm1') -Force

$base = Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$release = Join-Path $base $ReleaseId
$manifest = Read-Axu4evReleaseManifest $release
if ([string]$manifest.release_id -ne $ReleaseId) {
    throw "Manifest release id '$($manifest.release_id)' does not match '$ReleaseId'."
}

Test-Axu4evReleaseArtifacts $release $manifest | Out-Null
New-Item -ItemType Directory -Path $base -Force | Out-Null
Set-Content -LiteralPath (Join-Path $base 'CURRENT') -Value $ReleaseId -NoNewline
Write-Output "PASS: CURRENT=$ReleaseId"
