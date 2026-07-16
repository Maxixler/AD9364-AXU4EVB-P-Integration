$ErrorActionPreference = 'Stop'

$launchScript = Join-Path $PSScriptRoot 'Launch-Axu4evAd9364Jtag.tcl'
if (-not (Test-Path -LiteralPath $launchScript)) {
    throw "Missing JTAG launch script: $launchScript"
}

$content = Get-Content -LiteralPath $launchScript -Raw
$required = @(
    'if {![info exists ::env(FPGA_PROFEN_ROOT)]}'
    'set workspace_root [string map {\\ /} $::env(FPGA_PROFEN_ROOT)]'
    'foreach configuration {Release Debug}'
    'set candidate [file join $workspace "ad9364app" $configuration "ad9364app.elf"]'
    'mwr 0xffca0038 0x1ff'
    'dow $pmufw_elf'
    'fpga -file $bitstream'
    'set psuInitTcl [file join $workspace "fmcomms2_axu4ev_hw" "hw" "psu_init.tcl"]'
    'source $psuInitTcl'
    'configparams force-mem-accesses 1'
    'psu_init'
    'psu_ps_pl_isolation_removal'
    'psu_ps_pl_reset_config'
    'rst -processor -clear-registers'
    'dow $app_elf'
)

foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "JTAG launch script is missing required fragment: $fragment"
    }
}

$releaseIndex = $content.IndexOf('foreach configuration {Release Debug}', [System.StringComparison]::Ordinal)
if ($releaseIndex -lt 0) {
    throw 'JTAG launch script must prefer Release and fall back to Debug.'
}

$orderedPhases = @(
    'mwr 0xffca0038 0x1ff'
    'dow $pmufw_elf'
    'fpga -file $bitstream'
    'rst -processor -clear-registers'
    'source $psuInitTcl'
    "`npsu_init"
    'psu_ps_pl_isolation_removal'
    'psu_ps_pl_reset_config'
    'dow $app_elf'
)

$lastIndex = -1
foreach ($phase in $orderedPhases) {
    $index = $content.IndexOf($phase, [System.StringComparison]::Ordinal)
    if ($index -le $lastIndex) {
        throw "JTAG launch phase is missing or out of order: $phase"
    }
    $lastIndex = $index
}

if ($content.Contains('dow $fsbl_elf') -or $content.Contains('set fsbl_elf')) {
    throw 'The verified JTAG path must initialize PS/DDR directly and must not launch the stale FSBL.'
}

if ($content -match '(?i)C:/Users|C:\\Users') {
    throw 'JTAG launch script must not contain a user-specific absolute path.'
}

Write-Output 'PASS: PMUFW, FPGA, direct PS/DDR/PS-PL initialization and application JTAG launch order is valid.'
