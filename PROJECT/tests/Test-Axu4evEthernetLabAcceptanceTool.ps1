$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$tool = Join-Path $root 'PROJECT\tests\Test-Axu4evEthernetLabAcceptance.ps1'
$fixture = Join-Path $root 'PROJECT\tests\fixtures\axu4ev-ethernet-soak-pass.json'

function Invoke-OfflineAcceptance {
    param(
        [Parameter(Mandatory)]
        [string]$EvidencePath,

        [double]$MaximumLossPercent = 0.1
    )

    $output = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool `
            -OfflineEvidencePath $EvidencePath `
            -DurationSeconds 600 `
            -MinimumFrames 2200 `
            -MaximumLossPercent $MaximumLossPercent
    )
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Result = ($output -join "`n") | ConvertFrom-Json
    }
}

if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    throw "Missing Ethernet lab acceptance tool: $tool"
}

$pass = Invoke-OfflineAcceptance -EvidencePath $fixture
if ($pass.ExitCode -ne 0 -or -not [bool]$pass.Result.passed -or
    [Math]::Abs([double]$pass.Result.loss_percent - 0.090785) -gt 0.000001 -or
    $pass.Result.failure_reasons.Count -ne 0) {
    throw 'A duration-complete fixture at the frame and loss thresholds must pass.'
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-ethernet-acceptance-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $fixtureData = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json

    $fixtureData.lost_frames = 3
    $lossPath = Join-Path $temporaryDirectory 'loss.json'
    $fixtureData | ConvertTo-Json | Set-Content -LiteralPath $lossPath -Encoding utf8
    $loss = Invoke-OfflineAcceptance -EvidencePath $lossPath
    if ($loss.ExitCode -eq 0 -or [bool]$loss.Result.passed -or
        $loss.Result.failure_reasons -notcontains 'loss_percent_exceeded') {
        throw 'A fixture over the loss threshold must fail with the loss reason.'
    }

    $fixtureData = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json
    $fixtureData.completed_frames = 2199
    $minimumPath = Join-Path $temporaryDirectory 'minimum.json'
    $fixtureData | ConvertTo-Json | Set-Content -LiteralPath $minimumPath -Encoding utf8
    $minimum = Invoke-OfflineAcceptance -EvidencePath $minimumPath
    if ($minimum.ExitCode -eq 0 -or [bool]$minimum.Result.passed -or
        $minimum.Result.failure_reasons -notcontains 'minimum_frames_not_met') {
        throw 'A fixture below the minimum frame count must fail with the frame reason.'
    }

    $fixtureData = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json
    $fixtureData.stop_reason = 'source_exhausted'
    $durationPath = Join-Path $temporaryDirectory 'duration.json'
    $fixtureData | ConvertTo-Json | Set-Content -LiteralPath $durationPath -Encoding utf8
    $duration = Invoke-OfflineAcceptance -EvidencePath $durationPath
    if ($duration.ExitCode -eq 0 -or [bool]$duration.Result.passed -or
        $duration.Result.failure_reasons -notcontains 'duration_not_reached') {
        throw 'A capture that did not stop at duration must fail with the duration reason.'
    }
} finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Host 'PASS: Ethernet lab acceptance offline thresholds and JSON evidence behavior.'
