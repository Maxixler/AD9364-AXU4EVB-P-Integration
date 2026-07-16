[CmdletBinding()]
param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Sha256 {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing artifact: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$vivadoRoot = Join-Path $WorkspaceRoot 'Related-Docs\hdl-main\projects\fmcomms2\axu4ev'
$verificationRoot = Join-Path $WorkspaceRoot 'PROJECT\verification\vivado'
$platformRoot = Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw'
$appRoot = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app'

$bitFiles = @(
    (Join-Path $vivadoRoot 'fmcomms2_axu4ev.runs\impl_1\system_top.bit'),
    (Join-Path $platformRoot 'hw\system_top.bit'),
    (Join-Path $appRoot '_ide\bitstream\system_top.bit')
)
$bitHashes = @($bitFiles | ForEach-Object { Get-Sha256 $_ } | Select-Object -Unique)
Assert-True ($bitHashes.Count -eq 1) 'Vivado, Vitis platform, and IDE bitstreams do not match.'

$xsaFiles = @(
    (Join-Path $verificationRoot 'system_top.xsa'),
    (Join-Path $vivadoRoot 'fmcomms2_axu4ev.sdk\system_top.xsa'),
    (Join-Path $platformRoot 'hw\system_top.xsa')
)
$xsaHashes = @($xsaFiles | ForEach-Object { Get-Sha256 $_ } | Select-Object -Unique)
Assert-True ($xsaHashes.Count -eq 1) 'Verified, canonical, and Vitis platform XSA files do not match.'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($xsaFiles[0])
try {
    $bitEntry = $archive.Entries | Where-Object { $_.Name -eq 'system_top.bit' } | Select-Object -First 1
    Assert-True ($null -ne $bitEntry) 'The XSA does not contain system_top.bit.'
    $stream = $bitEntry.Open()
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $embeddedHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
        }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}
finally { $archive.Dispose() }
Assert-True ($embeddedHash -eq $bitHashes[0]) 'The bitstream embedded in the XSA differs from the implemented bitstream.'

$psuHashes = @(
    (Get-Sha256 (Join-Path $platformRoot 'hw\psu_init.tcl')),
    (Get-Sha256 (Join-Path $appRoot '_ide\psinit\psu_init.tcl'))
) | Select-Object -Unique
Assert-True ($psuHashes.Count -eq 1) 'Platform and IDE PSU initialization files do not match.'

$fsblHashes = @(
    (Get-Sha256 (Join-Path $platformRoot 'zynqmp_fsbl\executable.elf')),
    (Get-Sha256 (Join-Path $platformRoot 'export\fmcomms2_axu4ev_hw\sw\fmcomms2_axu4ev_hw\boot\fsbl.elf'))
) | Select-Object -Unique
Assert-True ($fsblHashes.Count -eq 1) 'Built and exported FSBL files do not match.'

$appElf = @(
    (Join-Path $appRoot 'Release\ad9364app.elf'),
    (Join-Path $appRoot 'Debug\ad9364app.elf')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
Assert-True (-not [string]::IsNullOrWhiteSpace($appElf)) 'Missing AD9364 application ELF under the Release and Debug configurations.'
$appElfHash = Get-Sha256 $appElf
Assert-True ((Get-Item -LiteralPath $appElf).Length -gt 0) 'AD9364 application ELF is empty.'

$appConfig = Get-Content -LiteralPath (Join-Path $appRoot 'src\adc9364_src\app_config.h') -Raw
Assert-True ($appConfig -match '#define\s+AD9361_DEVICE\s+0') 'AD9361_DEVICE is not disabled.'
Assert-True ($appConfig -match '#define\s+AD9364_DEVICE\s+1') 'AD9364_DEVICE is not enabled.'

$metadataFiles = @(
    (Join-Path $appRoot 'ad9364app.prj'),
    (Join-Path $appRoot '.cproject'),
    (Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app_system\ad9364app_system.sprj'),
    (Join-Path $platformRoot 'platform.spr')
)
$metadata = ($metadataFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
Assert-True ($metadata -match 'fmcomms2_axu4ev_hw') 'Application metadata does not reference the AXU4EV platform.'
Assert-True ($metadata -match 'standalone_domain') 'Application metadata does not reference standalone_domain.'
Assert-True ($metadata -notmatch 'C:/Users/DELL/workspace|sdr_wrapper|(?:value|location|platform|platHandOff)="P:/') 'Stale or temporary paths remain in Vitis metadata.'

Write-Output "PASS: Handoff artifacts are coherent."
Write-Output "BIT_SHA256=$($bitHashes[0])"
Write-Output "XSA_SHA256=$($xsaHashes[0])"
Write-Output "APP_ELF=$appElf"
Write-Output "APP_ELF_SHA256=$appElfHash"
