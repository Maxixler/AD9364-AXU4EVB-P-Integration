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
$vivado = Join-Path $VivadoBin 'vivado.bat'

foreach ($tool in @($xvlog, $xelab, $xsim, $vivado)) {
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
    magnitude = @{
        Top = 'tb_magnitude_peak'
        Sources = @(
            (Join-Path $tbRoot 'tb_magnitude_peak.sv'),
            (Join-Path $rtlRoot 'magnitude_peak.v')
        )
        DataFiles = @(
            (Join-Path $root 'PROJECT\verification\fft\vectors\tone_bin_137.fft.hex'),
            (Join-Path $root 'PROJECT\verification\fft\vectors\tone_bin_137.power.hex')
        )
        Marker = 'PASS: magnitude_peak'
    }
    bank = @{
        Top = 'tb_spectrum_pingpong'
        Sources = @(
            (Join-Path $tbRoot 'tb_spectrum_pingpong.sv'),
            (Join-Path $rtlRoot 'spectrum_pingpong.v')
        )
        Marker = 'PASS: spectrum_pingpong'
    }
    cdc = @{
        Top = 'tb_fft_cdc'
        Sources = @(
            (Join-Path $tbRoot 'tb_fft_cdc.sv'),
            (Join-Path $rtlRoot 'fft_command_cdc.v'),
            (Join-Path $rtlRoot 'fft_result_cdc.v')
        )
        Marker = 'PASS: fft_cdc'
    }
    regs = @{
        Top = 'tb_fft_regs'
        Sources = @(
            (Join-Path $tbRoot 'tb_fft_regs.sv'),
            (Join-Path $rtlRoot 'axi_ad9364_fft_regs.v')
        )
        Marker = 'PASS: fft_regs'
    }
    top = @{
        Top = 'tb_axi_ad9364_fft_capture'
        Sources = @(
            (Join-Path $tbRoot 'tb_axi_ad9364_fft_capture.sv'),
            (Join-Path $rtlRoot 'axi_ad9364_fft_capture.v'),
            (Join-Path $rtlRoot 'adc_frame_capture.v'),
            (Join-Path $rtlRoot 'adc_frame_replay.v'),
            (Join-Path $rtlRoot 'magnitude_peak.v'),
            (Join-Path $rtlRoot 'spectrum_pingpong.v'),
            (Join-Path $rtlRoot 'fft_command_cdc.v'),
            (Join-Path $rtlRoot 'fft_result_cdc.v'),
            (Join-Path $rtlRoot 'axi_ad9364_fft_regs.v')
        )
        Marker = 'PASS: axi_ad9364_fft_capture single-shot'
        VivadoProject = $true
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
        if ($case.ContainsKey('DataFiles')) {
            foreach ($dataFile in $case.DataFiles) {
                Copy-Item -LiteralPath $dataFile -Destination $caseWork
            }
        }
        Push-Location $caseWork
        try {
            if ($case.ContainsKey('VivadoProject')) {
                $topScript = Join-Path $PSScriptRoot 'Run-Axu4evFftTopSim.tcl'
                $prepareLog = Join-Path $caseWork 'prepare.log'
                $output = (& $vivado -mode batch -nojournal -notrace `
                    -log $prepareLog -source $topScript -tclargs $root $caseWork `
                    2>&1 | Tee-Object -FilePath (Join-Path $caseWork 'prepare.stdout.log') |
                    Out-String)
                $exitCode = $LASTEXITCODE
                Write-Output $output
                if ($exitCode -ne 0) {
                    throw "Vivado xFFT/script generation failed for $name with exit code $exitCode. See $prepareLog"
                }

                $simDir = Join-Path $caseWork 'project\fft_top_sim.sim\sim_1\behav\xsim'
                $compileScript = Join-Path $simDir 'compile.bat'
                $elaborateScript = Join-Path $simDir 'elaborate.bat'
                $simulateScript = Join-Path $simDir 'simulate.bat'
                foreach ($script in @($compileScript, $elaborateScript, $simulateScript)) {
                    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
                        throw "Vivado did not generate expected XSIM script: $script"
                    }
                }

                Push-Location $simDir
                $savedPath = $env:Path
                try {
                    $env:Path = $VivadoBin + ';' + $env:Path
                    $compileOutput = (& $compileScript 2>&1 |
                        Tee-Object -FilePath (Join-Path $caseWork 'compile.log') | Out-String)
                    Write-Output $compileOutput
                    if ($LASTEXITCODE -ne 0) {
                        throw "XSIM compile failed for $name with exit code $LASTEXITCODE."
                    }
                    $elaborateOutput = (& $elaborateScript 2>&1 |
                        Tee-Object -FilePath (Join-Path $caseWork 'elaborate.log') | Out-String)
                    Write-Output $elaborateOutput
                    if ($LASTEXITCODE -ne 0) {
                        throw "XSIM elaboration failed for $name with exit code $LASTEXITCODE."
                    }

                    $xsimBatch = Join-Path $PSScriptRoot 'Run-Axu4evFftTopXsim.tcl'
                    Copy-Item -LiteralPath $xsimBatch -Destination `
                        (Join-Path $simDir 'run_top.tcl') -Force
                    $simulateOutput = (& $xsim tb_axi_ad9364_fft_capture_behav `
                        -tclbatch run_top.tcl -log (Join-Path $caseWork 'xsim.log') 2>&1 |
                        Tee-Object -FilePath (Join-Path $caseWork 'simulate.log') | Out-String)
                    Write-Output $simulateOutput
                    if ($LASTEXITCODE -ne 0) {
                        throw "XSIM simulation failed for $name with exit code $LASTEXITCODE."
                    }
                } finally {
                    $env:Path = $savedPath
                    Pop-Location
                }
                if ($simulateOutput.Contains('FAIL:')) {
                    throw "Vivado project simulation reported a testbench failure for $name."
                }
                if (-not $simulateOutput.Contains($case.Marker)) {
                    throw "Vivado project simulation output for $name did not contain '$($case.Marker)'."
                }
                continue
            }

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
