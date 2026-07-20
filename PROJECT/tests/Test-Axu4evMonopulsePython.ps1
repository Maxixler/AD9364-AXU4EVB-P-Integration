param(
    [switch]$InstallDependencies,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$venv = Join-Path $root '.venv-monopulse'

if ($InstallDependencies) {
    if (-not (Test-Path $venv)) {
        & $Python -m venv $venv
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to create virtual environment with $Python."
        }
    }
    $pythonExe = Join-Path $venv 'Scripts\python.exe'
    & $pythonExe -m pip install 'numpy>=1.20' pyadi-iio
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to install Python dependencies.'
    }
} else {
    $pythonExe = $Python
}

Push-Location $root
try {
    & $pythonExe -m unittest PROJECT.tests.test_monopulse_reference -v
    if ($LASTEXITCODE -ne 0) {
        throw "Python monopulse tests failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
