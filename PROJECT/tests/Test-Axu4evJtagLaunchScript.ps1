$ErrorActionPreference = 'Stop'

$launchScript = Join-Path $PSScriptRoot 'Launch-Axu4evAd9364Jtag.tcl'
if (-not (Test-Path -LiteralPath $launchScript)) {
    throw "Missing JTAG launch script: $launchScript"
}

$content = Get-Content -LiteralPath $launchScript -Raw
$required = @(
    'set script_dir [file dirname [file normalize [info script]]]'
    'set project_root [file dirname [file dirname $script_dir]]'
    'mwr 0xffca0038 0x1ff'
    'dow $pmufw_elf'
    'fpga -file $bitstream'
    'rst -processor -clear-registers'
    'dow $fsbl_elf'
    'stop'
    'dow $app_elf'
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
    'dow $fsbl_elf'
    'stop'
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

if ($content -match '(?i)C:/Users|C:\\Users') {
    throw 'JTAG launch script must not contain a user-specific absolute path.'
}

Write-Output 'PASS: PMUFW, FPGA, FSBL and application JTAG launch order is valid.'
