[CmdletBinding()]
param(
    [ValidateSet('All', 'PinMap', 'RxTermination', 'Timing', 'SpiChipSelect')]
    [string]$Check = 'All',

    [string]$XdcPath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($XdcPath)) {
    $XdcPath = Join-Path $PSScriptRoot '..\..\Related-Docs\hdl-main\projects\fmcomms2\axu4ev\system_constr.xdc'
}
$resolvedXdcPath = (Resolve-Path -LiteralPath $XdcPath).Path
$lines = Get-Content -LiteralPath $resolvedXdcPath
$content = $lines -join "`n"
$failures = [System.Collections.Generic.List[string]]::new()

function Get-PortConstraintLine {
    param([Parameter(Mandatory)][string]$Port)

    $escapedPort = [regex]::Escape($Port)
    $matchingLines = @($lines | Where-Object {
        $_ -match '^\s*set_property\b' -and
        $_ -match "\[get_ports\s+\{?$escapedPort\}?\]"
    })

    if ($matchingLines.Count -eq 0) {
        $failures.Add("Missing constraint for port '$Port'.")
        return $null
    }

    if ($matchingLines.Count -gt 1) {
        $failures.Add("Port '$Port' has $($matchingLines.Count) constraint lines; expected one.")
        return $null
    }

    return $matchingLines[0]
}

function Test-PinMap {
    $expectedPins = [ordered]@{
        'rx_frame_in_p' = 'L7'
        'rx_frame_in_n' = 'L6'
        'tx_clk_out_p'  = 'N7'
        'tx_clk_out_n'  = 'N6'
    }

    foreach ($entry in $expectedPins.GetEnumerator()) {
        $line = Get-PortConstraintLine -Port $entry.Key
        if ($null -ne $line -and $line -notmatch "\bPACKAGE_PIN\s+$([regex]::Escape($entry.Value))\b") {
            $failures.Add("Port '$($entry.Key)' must use PACKAGE_PIN $($entry.Value): $line")
        }
    }
}

function Test-RxTermination {
    $rxPorts = @('rx_clk_in_p', 'rx_clk_in_n', 'rx_frame_in_p', 'rx_frame_in_n')
    foreach ($index in 0..5) {
        $rxPorts += "rx_data_in_p[$index]"
        $rxPorts += "rx_data_in_n[$index]"
    }

    foreach ($port in $rxPorts) {
        $line = Get-PortConstraintLine -Port $port
        if ($null -ne $line -and $line -notmatch '\bDIFF_TERM_ADV\s+TERM_100\b') {
            $failures.Add("Port '$port' must use DIFF_TERM_ADV TERM_100: $line")
        }
    }
}

function Test-Timing {
    $clockPattern = '(?im)^\s*create_clock\s+(?=[^\r\n]*-name\s+rx_clk\b)(?=[^\r\n]*-period\s+4(?:\.0+)?\b)(?=[^\r\n]*\[get_ports\s+\{?rx_clk_in_p\}?\])'
    if ($content -notmatch $clockPattern) {
        $failures.Add("Missing 4.00 ns 'rx_clk' create_clock constraint on rx_clk_in_p.")
    }
}

function Test-SpiChipSelect {
    $line = Get-PortConstraintLine -Port 'spi_csn'
    if ($null -ne $line -and $line -notmatch '\bPULLTYPE\s+PULLUP\b') {
        $failures.Add("Port 'spi_csn' must use PULLTYPE PULLUP: $line")
    }
}

switch ($Check) {
    'PinMap'       { Test-PinMap }
    'RxTermination'{ Test-RxTermination }
    'Timing'       { Test-Timing }
    'SpiChipSelect'{ Test-SpiChipSelect }
    'All' {
        Test-PinMap
        Test-RxTermination
        Test-Timing
        Test-SpiChipSelect
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $Check ($($failures.Count) issue(s))" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "PASS: $Check" -ForegroundColor Green
