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

Write-Output 'PASS: AXU4EV release resolution and integrity checks reject corruption.'
