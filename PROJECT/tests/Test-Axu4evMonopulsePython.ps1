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
    $expectedCrosscheck = 'CROSSCHECK powers=300,100,100,300 q31=1073741824,-1073741824'
    $modules = @(
        'PROJECT.tests.test_fft_vectors',
        'PROJECT.tests.test_lab_console_protocol',
        'PROJECT.tests.test_lab_console_model',
        'PROJECT.tests.test_lab_console_storage',
        'PROJECT.tests.test_lab_console_serial_client',
        'PROJECT.tests.test_lab_console_app',
        'PROJECT.tests.test_lab_console_evidence',
        'PROJECT.tests.test_monopulse_reference',
        'PROJECT.tests.test_xilinx_fft_cmodel'
    )
    $pythonStdout = [System.IO.Path]::GetTempFileName()
    $pythonStderr = [System.IO.Path]::GetTempFileName()
    try {
        $pythonArguments = @('-B', '-m', 'unittest') + $modules + @('-v')
        $pythonProcess = Start-Process -FilePath $pythonExe -ArgumentList $pythonArguments `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput $pythonStdout `
            -RedirectStandardError $pythonStderr
        $pythonExitCode = $pythonProcess.ExitCode
        $pythonOutput = (Get-Content -LiteralPath $pythonStderr -Raw) + (Get-Content -LiteralPath $pythonStdout -Raw)
    } finally {
        Remove-Item -LiteralPath $pythonStdout, $pythonStderr -Force -ErrorAction SilentlyContinue
    }
    Write-Output $pythonOutput
    if ($pythonExitCode -ne 0) {
        throw "Python monopulse tests failed with exit code $pythonExitCode."
    }
    if ($pythonOutput -match '(?im)\bskipped\b') {
        throw 'Python verification must not skip the installed Xilinx FFT C-model tests.'
    }
    $foundationScript = Join-Path $PSScriptRoot 'Test-Axu4evMonopulseFoundation.ps1'
    $foundationOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -File $foundationScript 2>&1 | Out-String)
    $foundationExitCode = $LASTEXITCODE
    Write-Output $foundationOutput
    if ($foundationExitCode -ne 0) {
        throw "C monopulse foundation tests failed with exit code $foundationExitCode."
    }
    $pythonMarkers = @($pythonOutput -split "`r?`n" | Where-Object { $_ -eq $expectedCrosscheck })
    $foundationMarkers = @($foundationOutput -split "`r?`n" | Where-Object { $_ -eq $expectedCrosscheck })
    if ($pythonMarkers.Count -ne 1 -or $foundationMarkers.Count -ne 1) {
        throw 'Python and C test runners must each emit exactly one matching CROSSCHECK marker.'
    }
} finally {
    Pop-Location
}
