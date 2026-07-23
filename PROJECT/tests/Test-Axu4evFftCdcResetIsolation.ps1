$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$library = Join-Path $root 'Related-Docs\hdl-main\library\axi_ad9364_fft_capture'

function Require-NotMatch([string]$Path, [string]$Pattern, [string]$Description) {
  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -match $Pattern) {
    throw "CDC reset-isolation failure: $Description"
  }
}

function Require-Match([string]$Path, [string]$Pattern, [string]$Description) {
  $content = Get-Content -LiteralPath $Path -Raw
  if ($content -notmatch $Pattern) {
    throw "CDC reset-isolation failure: $Description"
  }
}

$result = Join-Path $library 'fft_result_cdc.v'
$command = Join-Path $library 'fft_command_cdc.v'
$constraints = Join-Path $library 'axi_ad9364_fft_capture_constr.xdc'

Require-NotMatch $result 'assign\s+o_adc_ready\s*=\s*adc_resetn\s*&&\s*cpu_resetn' `
  'ADC-domain result ready depends directly on cpu_resetn.'
Require-NotMatch $result 'else\s+if\s*\(cpu_resetn\s*&&\s*adc_resetn\s*&&' `
  'CPU-domain result acknowledge depends directly on adc_resetn.'
Require-NotMatch $command 'assign\s+o_cpu_ready\s*=\s*cpu_resetn\s*&&\s*adc_resetn' `
  'CPU-domain command ready depends directly on adc_resetn.'
Require-NotMatch $command 'else\s+if\s*\(adc_resetn\s*&&\s*cpu_resetn\s*&&' `
  'ADC-domain command acknowledge depends directly on cpu_resetn.'

foreach ($source in @($command, $result)) {
  Require-NotMatch $source `
    'always\s*@\(\s*posedge\s+cpu_clk\s+or\s+negedge\s+cpu_resetn\s+or\s+negedge\s+adc_resetn\s*\)' `
    'CPU-domain logic releases directly from an asynchronous ADC reset.'
  Require-NotMatch $source `
    'always\s*@\(\s*posedge\s+adc_clk\s+or\s+negedge\s+adc_resetn\s+or\s+negedge\s+cpu_resetn\s*\)' `
    'ADC-domain logic releases directly from an asynchronous CPU reset.'

  foreach ($domain in @('cpu', 'adc')) {
    Require-Match $source `
      "\(\*\s*ASYNC_REG\s*=\s*`"TRUE`"\s*\*\)\s*reg\s+\[1:0\]\s+${domain}_domains_reset_sync\s*;" `
      "Missing ${domain}-clock domains-reset synchronizer."
    Require-Match $source `
      "\(\*\s*ASYNC_REG\s*=\s*`"TRUE`"\s*\*\)\s*reg\s+\[1:0\]\s+${domain}_mailbox_reset_sync\s*;" `
      "Missing ${domain}-clock mailbox-reset synchronizer."
  }
}

Require-Match $constraints `
  'set_false_path\s+-to\s+\[get_pins[\s\S]{0,200}\(cpu\|adc\)_\(mailbox\|domains\)_reset_sync_reg[\s\S]{0,80}/CLR\$' `
  'Missing targeted recovery/removal exception for reset-synchronizer CLR pins.'
Require-NotMatch $constraints `
  'set_false_path[^\r\n]*(get_ports|resetn\b)' `
  'Reset exception is broader than the named synchronizer CLR pins.'

Write-Host 'PASS: FFT CDC ready/acknowledge paths avoid opposite-domain raw resets.'
