param(
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$venvPython = Join-Path $root '.venv-monopulse-lab\Scripts\python.exe'
if ($Python -eq 'python' -and (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    $Python = $venvPython
}

Push-Location $root
try {
    & $Python -m pytest `
        PROJECT/tests/test_ethernet_fft_protocol.py `
        PROJECT/tests/test_ethernet_fft_reassembly.py `
        PROJECT/tests/test_ethernet_fft_receiver.py `
        PROJECT/tests/test_ethernet_fft_app.py `
        -q
    if ($LASTEXITCODE -ne 0) {
        throw "Ethernet FFT host tests failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

Write-Host 'PASS: Ethernet FFT host receiver and viewer tests.'
