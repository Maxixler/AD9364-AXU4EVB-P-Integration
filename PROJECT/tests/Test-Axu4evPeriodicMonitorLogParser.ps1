$ErrorActionPreference = 'Stop'

$validatorPath = Join-Path $PSScriptRoot 'Test-Axu4evPeriodicMonitorLog.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('axu4ev-periodic-monitor-log-parser-' + [Guid]::NewGuid().ToString('N'))

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Write-LogFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )

    $path = Join-Path $tempRoot $Name
    [System.IO.File]::WriteAllLines($path, $Lines, [System.Text.Encoding]::ASCII)
    return $path
}

function Invoke-Validator {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validatorPath -LogPath $LogPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $valid = @('PL_FFT_MONITOR: START frames=100 interval_ms=1000 bins=2048')
    $valid += 1..100 | ForEach-Object {
        'PL_FFT_MONITOR: FRAME seq={0:D3}/100 frame={1} bank={2} samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc={3:x8}' -f `
            $_, $_, ($_ % 2), $_
    }
    $valid += 'PL_FFT_MONITOR: PASS frames=100 interval_ms=1000'

    $positive = Invoke-Validator (Write-LogFixture -Name 'valid.log' -Lines $valid)
    Assert-Condition ($positive.ExitCode -eq 0) "Valid log was rejected: $($positive.Output)"
    Assert-Condition ($positive.Output -match [regex]::Escape('PASS: periodic FFT monitor log contains 100 valid frames.')) 'Valid log did not produce the required PASS message.'

    $cases = @(
        @{ Name = '99-frames'; Lines = @($valid[0]) + $valid[1..99] + @($valid[-1]) },
        @{ Name = 'duplicate-seq'; Lines = ($valid | ForEach-Object { $_ -replace 'seq=050/100', 'seq=049/100' }) },
        @{ Name = 'skipped-seq'; Lines = ($valid | ForEach-Object { $_ -replace 'seq=050/100', 'seq=051/100' }) },
        @{ Name = 'non-increasing-frame'; Lines = ($valid | ForEach-Object { $_ -replace 'seq=050/100 frame=50 ', 'seq=050/100 frame=49 ' }) },
        @{ Name = 'wrong-samples'; Lines = ($valid | ForEach-Object { $_ -replace 'seq=050/100 frame=50 bank=0 samples=2048', 'seq=050/100 frame=50 bank=0 samples=1024' }) },
        @{ Name = 'frame-tab-delimiter'; Lines = @($valid[0]) + @("PL_FFT_MONITOR: FRAME`tseq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065") + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'frame-no-delimiter'; Lines = @($valid[0]) + @('PL_FFT_MONITOR: FRAMEseq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065') + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'framex-marker'; Lines = @($valid[0]) + @('PL_FFT_MONITOR: FRAMEX seq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065') + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'frame-double-space-after-colon'; Lines = @($valid[0]) + @('PL_FFT_MONITOR:  FRAME seq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065') + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'frame-tab-after-colon'; Lines = @($valid[0]) + @("PL_FFT_MONITOR:`tFRAME seq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065") + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'frame-space-before-colon'; Lines = @($valid[0]) + @('PL_FFT_MONITOR : FRAME seq=101/100 frame=101 bank=1 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=00000065') + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'fail-line'; Lines = @($valid[0]) + @('PL_FFT_MONITOR: FAIL seq=050 reason=hardware') + $valid[1..$($valid.Count - 1)] },
        @{ Name = 'extra-malformed-start'; Lines = @('PL_FFT_MONITOR: START frames=99 interval_ms=1000 bins=2048') + $valid },
        @{ Name = 'missing-final-pass'; Lines = $valid[0..($valid.Count - 2)] },
        @{ Name = 'extra-malformed-pass'; Lines = $valid[0..100] + @('PL_FFT_MONITOR: PASS frames=99 interval_ms=1000') + @($valid[-1]) },
        @{ Name = 'frame-after-pass'; Lines = $valid[0..99] + @($valid[-1]) + @($valid[100]) }
    )

    foreach ($case in $cases) {
        $result = Invoke-Validator (Write-LogFixture -Name ($case.Name + '.log') -Lines $case.Lines)
        Assert-Condition ($result.ExitCode -ne 0) "Invalid $($case.Name) log was accepted: $($result.Output)"
    }

    Write-Output 'PASS: periodic FFT monitor log parser accepts only the complete contract.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
