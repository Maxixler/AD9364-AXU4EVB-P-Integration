param(
    [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'

function Assert-LogCondition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

try {
    Assert-LogCondition (Test-Path -LiteralPath $LogPath -PathType Leaf) "Log file does not exist: $LogPath"

    $lines = @(Get-Content -LiteralPath $LogPath)
    $startLine = 'PL_FFT_MONITOR: START frames=100 interval_ms=1000 bins=2048'
    $passLine = 'PL_FFT_MONITOR: PASS frames=100 interval_ms=1000'
    $framePattern = '^PL_FFT_MONITOR: FRAME seq=(\d{3})/100 frame=(\d+) bank=([01]) samples=2048 peak_bin=(\d+) peak_power=(\d+) dropped=(\d+) crc=([0-9a-fA-F]{8})$'
    $failPattern = '^PL_FFT_MONITOR: FAIL\b'

    $startIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $currentIndex = $index
        $index++
        if ($_ -ceq $startLine) { $currentIndex }
    })
    $startMarkerIndexes = @($lines | Where-Object { $_ -like 'PL_FFT_MONITOR: START*' })
    $passIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $currentIndex = $index
        $index++
        if ($_ -ceq $passLine) { $currentIndex }
    })
    $passMarkerIndexes = @($lines | Where-Object { $_ -like 'PL_FFT_MONITOR: PASS*' })
    $protocolIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $currentIndex = $index
        $index++
        if ([regex]::IsMatch($_, '^PL_FFT_MONITOR\s*:', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { $currentIndex }
    })
    foreach ($protocolIndex in $protocolIndexes) {
        $protocolLine = $lines[$protocolIndex]
        $isKnownRecord = ($protocolLine -ceq $startLine) -or
            ($protocolLine -ceq $passLine) -or
            [regex]::IsMatch($protocolLine, $framePattern) -or
            [regex]::IsMatch($protocolLine, $failPattern)
        Assert-LogCondition $isKnownRecord 'PL_FFT_MONITOR protocol line does not match a known record grammar.'
    }
    $frameIndexes = @($lines | ForEach-Object -Begin { $index = 0 } -Process {
        $currentIndex = $index
        $index++
        if ([regex]::IsMatch($_, $framePattern)) { $currentIndex }
    })

    Assert-LogCondition ($startMarkerIndexes.Count -eq 1) 'Log must contain exactly one START line.'
    Assert-LogCondition ($startIndexes.Count -eq 1) 'START line does not match the required contract.'
    Assert-LogCondition ($passMarkerIndexes.Count -eq 1) 'Log must contain exactly one PASS line.'
    Assert-LogCondition ($passIndexes.Count -eq 1) 'PASS line does not match the required contract.'
    Assert-LogCondition ($frameIndexes.Count -eq 100) 'Log must contain exactly 100 FRAME lines.'
    Assert-LogCondition (-not ($lines | Where-Object { [regex]::IsMatch($_, $failPattern) })) 'Log must not contain a FAIL line.'
    Assert-LogCondition ($startIndexes[0] -lt $frameIndexes[0]) 'START must precede all FRAME lines.'
    Assert-LogCondition ($passIndexes[0] -gt $frameIndexes[-1]) 'PASS must follow all FRAME lines.'
    Assert-LogCondition ($passIndexes[0] -eq ($lines.Count - 1)) 'PASS must be the final log line.'
    Assert-LogCondition (-not ($frameIndexes | Where-Object { $_ -gt $passIndexes[0] })) 'No FRAME line may follow PASS.'

    $previousFrame = -1L
    for ($expectedSequence = 1; $expectedSequence -le 100; $expectedSequence++) {
        $frameLine = $lines[$frameIndexes[$expectedSequence - 1]]
        $match = [regex]::Match($frameLine, $framePattern)
        Assert-LogCondition $match.Success "FRAME line $expectedSequence does not match the required contract."

        $sequence = [Int32]::Parse($match.Groups[1].Value)
        $hardwareFrame = [Int64]::Parse($match.Groups[2].Value)
        $sequenceMessage = 'FRAME sequence must be {0:D3}/100.' -f $expectedSequence
        Assert-LogCondition ($sequence -eq $expectedSequence) $sequenceMessage
        Assert-LogCondition ($hardwareFrame -gt $previousFrame) 'Hardware frame IDs must be strictly increasing.'
        $previousFrame = $hardwareFrame
    }

    Write-Output 'PASS: periodic FFT monitor log contains 100 valid frames.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
