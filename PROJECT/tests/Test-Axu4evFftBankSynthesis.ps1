param(
    [string]$Vivado = 'C:\Xilinx\Vivado\2020.1\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Vivado -PathType Leaf)) {
    throw "Missing Vivado executable: $Vivado"
}

$tcl = Join-Path $PSScriptRoot 'Synthesize-Axu4evFftBank.tcl'
$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_fft_bank_synth_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    Push-Location $work
    try {
        $output = (& $Vivado -mode batch -nolog -nojournal -notrace -source $tcl 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        Write-Output $output
        if ($exitCode -ne 0) {
            throw "Vivado bank synthesis gate failed with exit code $exitCode."
        }
        if ($output.Contains('ERROR:')) {
            throw 'Vivado bank synthesis gate reported ERROR.'
        }
        if (-not $output.Contains('PASS: spectrum_pingpong infers block RAM')) {
            throw 'Vivado bank synthesis PASS marker is missing.'
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
