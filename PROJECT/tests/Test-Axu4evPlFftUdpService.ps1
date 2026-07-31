$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$testSource = Join-Path $PSScriptRoot 'pl_fft_udp_service_test.c'
$serviceSource = Join-Path $sourceRoot 'pl_fft_udp_service.c'
$protocolSource = Join-Path $sourceRoot 'pl_fft_udp_protocol.c'

foreach ($path in @($testSource, $protocolSource)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PL FFT UDP service test dependency: $path"
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
    'axu4ev_pl_fft_udp_service_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$executable = Join-Path $work 'pl_fft_udp_service_test.exe'
$sources = @($testSource, $protocolSource)
if (Test-Path -LiteralPath $serviceSource -PathType Leaf) {
    $sources += $serviceSource
}

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
        $sources -o $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT UDP service compilation failed with: $gcc"
    }
    & $executable
    if ($LASTEXITCODE -ne 0) {
        throw "PL FFT UDP service test failed with exit code $LASTEXITCODE"
    }
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
