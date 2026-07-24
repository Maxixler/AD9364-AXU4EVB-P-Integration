$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$module = Join-Path $workspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$goldenXsa = Join-Path $workspaceRoot `
    'PROJECT\releases\axu4ev-ad9364\2026-07-16-bringup-v1\hardware\system_top.xsa'
$candidateXsa = Join-Path $workspaceRoot `
    'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1\hardware\system_top.xsa'

Import-Module $module -Force

Assert-Axu4evPsHardwareContract -Xsa $goldenXsa -ReferenceXsa $goldenXsa
Assert-Axu4evPsHardwareContract -Xsa $candidateXsa -ReferenceXsa $goldenXsa

Add-Type -AssemblyName System.IO.Compression.FileSystem
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) `
    "axu4ev-ps-contract-$([guid]::NewGuid().ToString('N'))"
$expanded = Join-Path $tempRoot 'expanded'
$tamperedXsa = Join-Path $tempRoot 'tampered.xsa'
try {
    New-Item -ItemType Directory -Path $expanded -Force | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($goldenXsa, $expanded)
    $hwh = Get-ChildItem -LiteralPath $expanded -Filter '*.hwh' |
        Select-Object -First 1
    if (-not $hwh) {
        throw 'Golden test fixture contains no top-level HWH.'
    }

    $content = [IO.File]::ReadAllText($hwh.FullName)
    $tampered = $content.Replace(
        '<PARAMETER NAME="PSU__SATA__PERIPHERAL__ENABLE" VALUE="0"/>',
        '<PARAMETER NAME="PSU__SATA__PERIPHERAL__ENABLE" VALUE="1"/>')
    if ($tampered -ceq $content) {
        throw 'Could not tamper the PS contract test fixture.'
    }
    [IO.File]::WriteAllText(
        $hwh.FullName,
        $tampered,
        [Text.UTF8Encoding]::new($false))
    [IO.Compression.ZipFile]::CreateFromDirectory($expanded, $tamperedXsa)

    $rejected = $false
    try {
        Assert-Axu4evPsHardwareContract `
            -Xsa $tamperedXsa `
            -ReferenceXsa $goldenXsa
    }
    catch {
        $rejected = $true
        if ($_.Exception.Message -notmatch 'PS hardware contract mismatch') {
            throw
        }
    }
    if (-not $rejected) {
        throw 'A tampered SATA PS configuration unexpectedly passed the contract.'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

'PASS: Golden and Candidate PS contracts match; tampered PS configuration was rejected.'
