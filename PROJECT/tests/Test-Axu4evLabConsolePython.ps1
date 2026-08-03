param(
    [switch]$InstallDependencies,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$requirements = Join-Path $root 'PROJECT\lab_console\requirements.txt'
$venv = Join-Path $root '.venv-monopulse-lab'

if (-not (Test-Path -LiteralPath $requirements -PathType Leaf)) {
    throw "Missing lab console requirements: $requirements"
}
$expected = @('numpy>=1.20', 'matplotlib>=3.5', 'pyserial>=3.5')
$actual = @(Get-Content -LiteralPath $requirements)
if (($actual -join "`n") -ne ($expected -join "`n")) {
    throw 'Lab console requirements must contain the three approved minimums.'
}

if ($InstallDependencies) {
    if (-not (Test-Path -LiteralPath $venv -PathType Container)) {
        & $Python -m venv $venv
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create virtual environment with $Python."
        }
    }
    $pythonExe = Join-Path $venv 'Scripts\python.exe'
    & $pythonExe -m pip install -r $requirements
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to install lab console Python dependencies.'
    }
} else {
    $pythonExe = $Python
}

Push-Location $root
try {
    $modules = @(
        'PROJECT.tests.test_lab_console_protocol',
        'PROJECT.tests.test_lab_console_model',
        'PROJECT.tests.test_lab_console_storage',
        'PROJECT.tests.test_lab_console_serial_client',
        'PROJECT.tests.test_lab_console_app',
        'PROJECT.tests.test_lab_console_evidence'
    )
    & $pythonExe -B -m unittest @modules -v
    if ($LASTEXITCODE -ne 0) {
        throw "Lab console Python tests failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

Write-Host 'PASS: bare-metal FFT lab console Python tests.'
