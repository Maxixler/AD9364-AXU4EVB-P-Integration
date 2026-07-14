[CmdletBinding()]
param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

$vivadoBit = Join-Path $WorkspaceRoot 'Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.runs\impl_1\system_top.bit'
$platformRoot = Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\hw'
$platformBit = Join-Path $platformRoot 'system_top.bit'
$platformPsuInit = Join-Path $platformRoot 'psu_init.tcl'
$ideRoot = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\_ide'
$ideBit = Join-Path $ideRoot 'bitstream\system_top.bit'
$idePsuInit = Join-Path $ideRoot 'psinit\psu_init.tcl'

foreach ($path in @($vivadoBit, $platformBit, $platformPsuInit)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required verified hardware artifact is missing: $path"
    }
}

$vivadoHash = (Get-FileHash -LiteralPath $vivadoBit -Algorithm SHA256).Hash
$platformHash = (Get-FileHash -LiteralPath $platformBit -Algorithm SHA256).Hash
if ($vivadoHash -ne $platformHash) {
    throw "Refusing IDE sync: Vivado and Vitis platform bitstreams differ."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ideBit) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $idePsuInit) | Out-Null
Copy-Item -LiteralPath $platformBit -Destination $ideBit -Force
Copy-Item -LiteralPath $platformPsuInit -Destination $idePsuInit -Force

$ideBitHash = (Get-FileHash -LiteralPath $ideBit -Algorithm SHA256).Hash
$platformPsuHash = (Get-FileHash -LiteralPath $platformPsuInit -Algorithm SHA256).Hash
$idePsuHash = (Get-FileHash -LiteralPath $idePsuInit -Algorithm SHA256).Hash
if ($ideBitHash -ne $platformHash) {
    throw "IDE bitstream verification failed after copy."
}
if ($idePsuHash -ne $platformPsuHash) {
    throw "IDE PSU initialization verification failed after copy."
}

Write-Output "PASS: IDE hardware synchronized; bitstream SHA256=$ideBitHash"
