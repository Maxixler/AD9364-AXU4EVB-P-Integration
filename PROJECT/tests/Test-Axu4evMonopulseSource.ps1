$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$config = Join-Path $sourceRoot 'app_config.h'
$main = Join-Path $sourceRoot 'main.c'
$selftest = Join-Path $sourceRoot 'monopulse_selftest.c'
$selftestHeader = Join-Path $sourceRoot 'monopulse_selftest.h'

foreach ($path in @($config, $main, $selftest, $selftestHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing monopulse foundation source: $path"
    }
}

$content = (Get-Content -LiteralPath $config -Raw) +
    (Get-Content -LiteralPath $main -Raw) +
    (Get-Content -LiteralPath $selftest -Raw)
$required = @(
    '#define MONOPULSE_FOUNDATION_TEST',
    '#if defined(MONOPULSE_FOUNDATION_TEST) && defined(WIFI_RF_TEST)',
    'monopulse_selftest_run(ad9361_phy)',
    'MONOPULSE_RF: PASS',
    'MONOPULSE_FOUNDATION: PASS',
    'MONOPULSE_FOUNDATION: FAIL'
)

foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "Monopulse foundation integration is missing required fragment: $fragment"
    }
}

$selftestContent = Get-Content -LiteralPath $selftest -Raw
if ($selftestContent -match 'axi_dac_set_datasel' -or
    $selftestContent -match 'axi_dmac_transfer_start' -or
    $selftestContent -match 'no_os_gpio_(direction_output|set_value)') {
    throw 'Monopulse self-test contains prohibited TX DAC/DMAC or external switch GPIO writes.'
}
