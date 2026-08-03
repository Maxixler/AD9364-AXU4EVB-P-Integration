$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$testSource = Join-Path $PSScriptRoot 'pl_fft_lab_protocol_test.c'
$protocolSource = Join-Path $sourceRoot 'pl_fft_lab_protocol.c'
$protocolHeader = Join-Path $sourceRoot 'pl_fft_lab_protocol.h'

foreach ($path in @($testSource, $protocolSource, $protocolHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PL FFT lab protocol source: $path"
    }
}

$gcc = $env:MONOPULSE_GCC
if (-not $gcc) {
    $command = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue
    if ($command) {
        $gcc = $command.Source
    } elseif (Test-Path -LiteralPath 'C:\MinGW\bin\gcc.exe') {
        $gcc = 'C:\MinGW\bin\gcc.exe'
    } else {
        throw 'Unable to find gcc. Set MONOPULSE_GCC or add gcc to PATH.'
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_pl_fft_lab_protocol_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$executable = Join-Path $work 'pl_fft_lab_protocol_test.exe'

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        $testSource $protocolSource -o $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT lab protocol compilation failed with: $gcc"
    }
    & $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT lab protocol test failed with exit code $LASTEXITCODE"
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
