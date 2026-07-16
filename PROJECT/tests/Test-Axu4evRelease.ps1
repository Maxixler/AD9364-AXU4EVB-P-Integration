$ErrorActionPreference = 'Stop'

$module = Join-Path $PSScriptRoot '..\tools\Axu4evRelease.psm1'
if (-not (Test-Path -LiteralPath $module)) {
    throw "Missing module: $module"
}
Import-Module $module -Force

$temp = Join-Path ([IO.Path]::GetTempPath()) ("axu4ev-release-" + [guid]::NewGuid())
try {
    $release = Join-Path $temp 'releases\r1'
    New-Item -ItemType Directory -Path (Join-Path $release 'hardware') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $release 'hardware\system_top.bit') -Value 'verified-bit' -NoNewline
    $file = Get-Item -LiteralPath (Join-Path $release 'hardware\system_top.bit')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    @{
        release_id = 'r1'
        artifacts = @(
            @{
                name = 'bitstream'
                path = 'hardware/system_top.bit'
                length = $file.Length
                sha256 = $hash
            }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $release 'manifest.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $temp 'releases\CURRENT') -Value 'r1' -NoNewline

    $resolved = Resolve-Axu4evCurrentRelease (Join-Path $temp 'releases')
    if ($resolved.Name -ne 'r1') {
        throw 'CURRENT did not resolve r1.'
    }

    $manifest = Read-Axu4evReleaseManifest $release
    $verified = @(Test-Axu4evReleaseArtifacts $release $manifest)
    if ($verified.Count -ne 1 -or $verified[0].Sha256 -ne $hash) {
        throw 'Valid artifact was not verified.'
    }

    Set-Content -LiteralPath $file.FullName -Value 'changed--bit' -NoNewline
    try {
        Test-Axu4evReleaseArtifacts $release $manifest | Out-Null
        throw 'Corruption was accepted.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'SHA-256 mismatch') {
            throw
        }
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$promote = Join-Path $PSScriptRoot '..\tools\Promote-Axu4evAd9364Release.ps1'
$select = Join-Path $PSScriptRoot '..\tools\Set-Axu4evAd9364CurrentRelease.ps1'
if (-not (Test-Path -LiteralPath $promote)) {
    throw "Missing promotion tool: $promote"
}
if (-not (Test-Path -LiteralPath $select)) {
    throw "Missing current-release tool: $select"
}

$promotionRoot = Join-Path ([IO.Path]::GetTempPath()) ("axu4ev-promotion-" + [guid]::NewGuid())
try {
    $fakeFiles = @(
        'Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit',
        'Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.sdk\system_top.xsa',
        'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl',
        'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf',
        'Vitis\workspace\ad9364app\Debug\ad9364app.elf'
    )
    foreach ($relative in $fakeFiles) {
        $path = Join-Path $promotionRoot $relative
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $relative -NoNewline
    }

    & $promote -ReleaseId r2 -WorkspaceRoot $promotionRoot -BoardVerified
    $currentPath = Join-Path $promotionRoot 'PROJECT\releases\axu4ev-ad9364\CURRENT'
    if (Test-Path -LiteralPath $currentPath) {
        throw 'Promotion changed CURRENT.'
    }

    try {
        & $promote -ReleaseId r2 -WorkspaceRoot $promotionRoot
        throw 'Duplicate release was accepted.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Release already exists') {
            throw
        }
    }

    & $select -ReleaseId r2 -WorkspaceRoot $promotionRoot
    $current = (Get-Content -LiteralPath $currentPath -Raw).Trim()
    if ($current -ne 'r2') {
        throw 'Explicit selection did not update CURRENT.'
    }
}
finally {
    Remove-Item -LiteralPath $promotionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: AXU4EV release integrity, immutable promotion, and explicit selection checks passed.'
