$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$includeDir = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$testSource = Join-Path $PSScriptRoot 'monopulse_foundation_test.c'
$mathSource = Join-Path $includeDir 'monopulse_math.c'

if ($env:MONOPULSE_GCC) {
    $gcc = $env:MONOPULSE_GCC
} else {
    $command = Get-Command gcc -ErrorAction SilentlyContinue
    if ($command) {
        $gcc = $command.Source
    } elseif (Test-Path 'C:\MinGW\bin\gcc.exe') {
        $gcc = 'C:\MinGW\bin\gcc.exe'
    } else {
        throw 'Unable to find gcc. Set MONOPULSE_GCC or add gcc to PATH.'
    }
}

$executable = Join-Path ([System.IO.Path]::GetTempPath()) (
    'monopulse_foundation_' + [guid]::NewGuid().ToString('N') + '.exe')

try {
    & $gcc -std=c11 -Wall -Wextra -Werror -I $includeDir $testSource $mathSource -o $executable
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE."
    }

    & $executable
    if ($LASTEXITCODE -ne 0) {
        throw "Test executable failed with exit code $LASTEXITCODE."
    }
} finally {
    if (Test-Path $executable) {
        Remove-Item -LiteralPath $executable -Force
    }
}
