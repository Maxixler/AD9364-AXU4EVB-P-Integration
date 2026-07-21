param(
    [string]$Test = 'all',
    [string]$VivadoBin = 'C:\Xilinx\Vivado\2020.1\bin'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$rtlRoot = Join-Path $root 'Related-Docs\hdl-main\library\axi_ad9364_fft_capture'
$tbRoot = Join-Path $root 'PROJECT\verification\fft\rtl'
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim = Join-Path $VivadoBin 'xsim.bat'

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing Vivado simulator tool: $tool"
    }
}

$tests = [ordered]@{
    capture = @{
        Top = 'tb_adc_frame_capture'
        Sources = @(
            (Join-Path $tbRoot 'tb_adc_frame_capture.sv'),
            (Join-Path $rtlRoot 'adc_frame_capture.v')
        )
        Marker = 'PASS: adc_frame_capture'
    }
    replay = @{
        Top = 'tb_adc_frame_replay'
        Sources = @(
            (Join-Path $tbRoot 'tb_adc_frame_replay.sv'),
            (Join-Path $rtlRoot 'adc_frame_replay.v')
        )
        Marker = 'PASS: adc_frame_replay'
    }
}

$requested = @($Test -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ })
if ($requested.Count -eq 0 -or $requested -contains 'all') {
    $requested = @($tests.Keys)
}

foreach ($name in $requested) {
    if (-not $tests.Contains($name)) {
        throw "Unknown RTL test '$name'. Available tests: $($tests.Keys -join ', '), all"
    }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) (
    'axu4ev_fft_xsim_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    foreach ($name in $requested) {
        $case = $tests[$name]
        $caseWork = Join-Path $work $name
        New-Item -ItemType Directory -Path $caseWork | Out-Null
        Push-Location $caseWork
        try {
            & $xvlog --sv @($case.Sources)
            if ($LASTEXITCODE -ne 0) {
                throw "xvlog failed for $name with exit code $LASTEXITCODE."
            }

            $snapshot = $case.Top + '_snapshot'
            & $xelab $case.Top -s $snapshot -debug typical
            if ($LASTEXITCODE -ne 0) {
                throw "xelab failed for $name with exit code $LASTEXITCODE."
            }

            $output = (& $xsim $snapshot -runall 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
            Write-Output $output
            if ($exitCode -ne 0) {
                throw "xsim failed for $name with exit code $exitCode."
            }
            if ($output.Contains('FAIL:')) {
                throw "xsim reported a testbench failure for $name."
            }
            if (-not $output.Contains($case.Marker)) {
                throw "xsim output for $name did not contain '$($case.Marker)'."
            }
        } finally {
            Pop-Location
        }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
