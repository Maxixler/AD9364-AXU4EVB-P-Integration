$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$buildTcl = Join-Path $root 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
$buildPs1 = Join-Path $root 'PROJECT\tools\Build-Axu4evPlFftCandidate.ps1'
$mainPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\main.c'
$transportPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\pl_fft_lwip_transport.c'
$platformPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\pl_fft_lwip_platform.c'
$gitignorePath = Join-Path $root '.gitignore'

function Assert-Match {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing Ethernet Candidate build contract: $Pattern"
    }
}

foreach ($path in @($buildTcl, $buildPs1, $mainPath, $gitignorePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Ethernet Candidate build dependency: $path"
    }
}

$tcl = Get-Content -LiteralPath $buildTcl -Raw
$ps1 = Get-Content -LiteralPath $buildPs1 -Raw
$main = Get-Content -LiteralPath $mainPath -Raw
$gitignore = Get-Content -LiteralPath $gitignorePath -Raw

Assert-Match $tcl 'PL_FFT_ETHERNET'
Assert-Match $tcl 'bsp setlib -name lwip211'
Assert-Match $tcl 'bsp config api_mode RAW_API'
Assert-Match $tcl 'bsp config lwip_dhcp false'
Assert-Match $tcl 'bsp config mem_size 524288'
Assert-Match $tcl 'bsp config pbuf_pool_size 256'
Assert-Match $ps1 "'Ethernet' \{ 'PL_FFT_ETHERNET' \}"
Assert-Match $ps1 "'Ethernet' \{ @\('PL_FFT_ETH: READY'\) \}"
Assert-Match $ps1 "vitis_ethernet[\\/]workspace"
Assert-Match $main '#ifdef PL_FFT_ETHERNET'
Assert-Match $main 'uint32_t rf_state;'
Assert-Match $main 'snapshot->rf_state = \(uint8_t\)rf_state;'
Assert-Match $gitignore '/vitis_ethernet/workspace/'

foreach ($path in @($transportPath, $platformPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Ethernet Candidate lwIP source: $path"
    }
}

$transport = Get-Content -LiteralPath $transportPath -Raw
$platform = Get-Content -LiteralPath $platformPath -Raw

Assert-Match $transport 'pbuf_alloc\(PBUF_TRANSPORT,\s*\(uint16_t\)\(64u \+ bin_count \* 8u\),\s*PBUF_RAM\)'
Assert-Match $transport 'udp_sendto\(transport->pcb,\s*packet,\s*&transport->target,\s*5005u\)'
Assert-Match $transport 'pbuf_free\(packet\)'
Assert-Match $transport 'payload_bytes == 0u'
Assert-Match $transport 'payload_bytes > PL_FFT_UDP_BINS_PER_CHUNK \* sizeof\(uint64_t\)'
Assert-Match $platform 'XPAR_XEMACPS_0_BASEADDR'
Assert-Match $platform 'xemac_add\('
Assert-Match $platform 'netif_set_default\('
Assert-Match $platform 'netif_set_up\('
Assert-Match $platform 'XTtcPs'
Assert-Match $platform 'XScuGic'

Write-Output 'PASS: Ethernet Candidate build and lwIP platform contracts are isolated.'
