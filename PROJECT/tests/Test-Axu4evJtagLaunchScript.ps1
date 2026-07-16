$ErrorActionPreference = 'Stop'

$launchScript = Join-Path $PSScriptRoot 'Launch-Axu4evAd9364Jtag.tcl'
if (-not (Test-Path -LiteralPath $launchScript)) {
    throw "Missing JTAG launch script: $launchScript"
}

$content = Get-Content -LiteralPath $launchScript -Raw
$mappingMatch = [regex]::Match($content, 'set pmufw_elf \[string map (?<mapping>\{[^}\r\n]+\}) ')
if (-not $mappingMatch.Success) {
    throw 'Cannot find the PMUFW Windows-path mapping expression.'
}

$xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
if (-not (Test-Path -LiteralPath $xsct -PathType Leaf)) {
    throw "Missing XSCT executable: $xsct"
}
$probePath = Join-Path ([IO.Path]::GetTempPath()) ("axu4ev-path-map-$([guid]::NewGuid()).tcl")
try {
    $mapping = $mappingMatch.Groups['mapping'].Value
    @(
        'set sample {C:\Temp\file.elf}'
        "set converted [string map $mapping `$sample]"
        'if {$converted ne {C:/Temp/file.elf}} { error "Windows path conversion failed: $converted" }'
        'puts {PASS: XSCT accepts the launch path mapping.}'
        'exit'
    ) | Set-Content -LiteralPath $probePath -Encoding ASCII
    $probeOutput = @(& $xsct $probePath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "XSCT rejected the launch path mapping.`r`n$($probeOutput -join "`r`n")"
    }
}
finally {
    Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
}

$required = @(
    'AXU4EV_PMUFW_ELF'
    'AXU4EV_BITSTREAM'
    'AXU4EV_PSU_INIT_TCL'
    'AXU4EV_APP_ELF'
    'set psu_init_tcl [string map {\\ /} $::env(AXU4EV_PSU_INIT_TCL)]'
    'set ddr_test_address 0x00100000'
    'set ddr_test_value 0xA5A5A5A5'
    'mwr 0xffca0038 0x1ff'
    'dow $pmufw_elf'
    'fpga -file $bitstream'
    'rst -processor -clear-registers'
    'source $psu_init_tcl'
    'configparams force-mem-accesses 1'
    'psu_init'
    'psu_ps_pl_isolation_removal'
    'psu_ps_pl_reset_config'
    'mwr $ddr_test_address $ddr_test_value'
    'mrd $ddr_test_address'
    'DDR verification failed'
    'dow $app_elf'
    'configparams force-mem-accesses 0'
)

foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "JTAG launch script is missing required fragment: $fragment"
    }
}

$orderedPhases = @(
    'mwr 0xffca0038 0x1ff'
    'dow $pmufw_elf'
    'fpga -file $bitstream'
    'rst -processor -clear-registers'
    'source $psu_init_tcl'
    "`npsu_init"
    'psu_ps_pl_isolation_removal'
    'psu_ps_pl_reset_config'
    'mwr $ddr_test_address $ddr_test_value'
    'mrd $ddr_test_address'
    'dow $app_elf'
    'configparams force-mem-accesses 0'
)

$lastIndex = -1
foreach ($phase in $orderedPhases) {
    $index = $content.IndexOf($phase, [System.StringComparison]::Ordinal)
    if ($index -le $lastIndex) {
        throw "JTAG launch phase is missing or out of order: $phase"
    }
    $lastIndex = $index
}

$finalCon = $content.LastIndexOf("`ncon", [System.StringComparison]::Ordinal)
if ($finalCon -le $lastIndex) {
    throw 'The application is not resumed after force-mem-accesses is restored.'
}

if ($content.Contains('dow $fsbl_elf') -or $content.Contains('set fsbl_elf')) {
    throw 'The verified JTAG path must initialize PS/DDR directly and must not launch the stale FSBL.'
}

if ($content.Contains('FPGA_PROFEN_ROOT') -or $content.Contains('set workspace ')) {
    throw 'The launch script must consume verified artifact paths instead of constructing workspace paths.'
}

if ($content -match '(?i)C:/Users|C:\\Users') {
    throw 'JTAG launch script must not contain a user-specific absolute path.'
}

Write-Output 'PASS: verified artifacts, PMUFW, FPGA, PS/DDR/PS-PL, DDR gate, and application launch order are valid.'
