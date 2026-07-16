$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$capture = Join-Path $sourceRoot 'wifi_rf_capture.c'
$header = Join-Path $sourceRoot 'wifi_rf_capture.h'

foreach ($path in @($capture, $header)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Wi-Fi RF capture source: $path"
    }
}

$content = Get-Content -LiteralPath $capture -Raw
$required = @(
    'ad9361_set_rx_rf_port_input(ctx->phy, B_BALANCED)',
    'ad9361_get_rx_rf_port_input(ctx->phy, &port)',
    'ad9361_set_tx_attenuation(ctx->phy, 0, 89750)',
    'ad9361_set_en_state_machine_mode(ctx->phy, ENSM_MODE_RX)',
    'ad9361_get_en_state_machine_mode(ctx->phy, &ensm)',
    '.cyclic = NO',
    'axi_dmac_transfer_wait_completion(ctx->rx_dmac, WIFI_RF_DMA_TIMEOUT_MS)',
    'Xil_DCacheInvalidateRange',
    'RF_GAIN_SLOWATTACK_AGC',
    'RF_GAIN_MGC',
    'ad9361_set_rx_rf_gain',
    'ad9361_get_rx_rssi',
    'wifi_rf_analyze_block',
    'LO_ERROR',
    'GAIN_ERROR',
    'DMA_ERROR'
)
foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "Capture path is missing required safety/measurement fragment: $fragment"
    }
}

if ($content -match 'axi_dmac_transfer_start\s*\(\s*tx_dmac' -or
    $content -match 'axi_dac_' -or $content -match 'AXI_DAC_DATA_SEL_DDS') {
    throw 'Wi-Fi RF capture path contains TX DAC/DDS/DMAC behavior.'
}

Write-Output 'PASS: Wi-Fi RF capture source enforces RX-only finite-DMA behavior.'
