$ErrorActionPreference = 'Stop'

$rootBasedScripts = @(
    'Update-Axu4evVitisPlatform.tcl'
    'Fix-Axu4evFsblBuild.tcl'
)

foreach ($name in $rootBasedScripts) {
    $path = Join-Path $PSScriptRoot $name
    $content = Get-Content -LiteralPath $path -Raw

    if (-not $content.Contains('if {![info exists ::env(FPGA_PROFEN_ROOT)]}')) {
        throw "$name does not require an explicit FPGA_PROFEN_ROOT for Vitis 2020.1."
    }
    if (-not $content.Contains('set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]')) {
        throw "$name does not preserve the explicit Windows workspace path."
    }
    if ($content.Contains('[info script]')) {
        throw "$name derives its root from info script; Vitis 2020.1 removes the Desktop path component."
    }
}

$launchPath = Join-Path $PSScriptRoot 'Launch-Axu4evAd9364Jtag.tcl'
$launchContent = Get-Content -LiteralPath $launchPath -Raw
foreach ($name in @('AXU4EV_PMUFW_ELF','AXU4EV_BITSTREAM','AXU4EV_PSU_INIT_TCL','AXU4EV_APP_ELF')) {
    if (-not $launchContent.Contains($name)) {
        throw "Launch-Axu4evAd9364Jtag.tcl does not consume $name."
    }
}
if ($launchContent.Contains('FPGA_PROFEN_ROOT') -or $launchContent.Contains('[info script]')) {
    throw 'Launch-Axu4evAd9364Jtag.tcl must not derive artifact paths from a workspace root.'
}

Write-Output 'PASS: XSCT scripts use explicit Windows roots or verified artifact inputs.'
