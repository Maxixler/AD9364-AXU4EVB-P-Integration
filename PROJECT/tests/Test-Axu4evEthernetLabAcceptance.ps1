[CmdletBinding()]
param(
    [string]$Python = 'python',
    [string]$Bind = '192.168.1.100',
    [int]$Port = 5005,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$DurationSeconds = 600,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MinimumFrames = 2200,
    [ValidateRange(0.0, 100.0)]
    [double]$MaximumLossPercent = 0.1,
    [string]$BoardAddress = '192.168.1.10',
    [string]$EvidenceDirectory,
    [string]$OfflineEvidencePath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $root 'PROJECT\tests\evidence'
}

function Get-RequiredEvidenceValue {
    param(
        [Parameter(Mandatory)]$Evidence,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Evidence.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        throw "Capture evidence is missing required '$Name'."
    }
    return $property.Value
}

function Test-Axu4evEthernetCapture {
    param(
        [Parameter(Mandatory)]$Capture,
        [Parameter(Mandatory)][int]$RequiredDurationSeconds,
        [Parameter(Mandatory)][int]$RequiredMinimumFrames,
        [Parameter(Mandatory)][double]$RequiredMaximumLossPercent
    )

    $stopReason = [string](Get-RequiredEvidenceValue $Capture 'stop_reason')
    $captureDuration = [int](Get-RequiredEvidenceValue $Capture 'duration_seconds')
    $elapsedSeconds = [double](Get-RequiredEvidenceValue $Capture 'elapsed_seconds')
    $completedFrames = [int](Get-RequiredEvidenceValue $Capture 'completed_frames')
    $lostFrames = [int](Get-RequiredEvidenceValue $Capture 'lost_frames')
    $invalidDatagrams = [int](Get-RequiredEvidenceValue $Capture 'invalid_datagrams')
    $firstFrameId = [long](Get-RequiredEvidenceValue $Capture 'first_frame_id')
    $lastFrameId = [long](Get-RequiredEvidenceValue $Capture 'last_frame_id')
    $frameIdSpan = [long](Get-RequiredEvidenceValue $Capture 'frame_id_span')
    if ($completedFrames -lt 0 -or $lostFrames -lt 0 -or $invalidDatagrams -lt 0) {
        throw 'Capture evidence counters must be non-negative.'
    }

    $observedFrames = $completedFrames + $lostFrames
    $lossPercent = if ($observedFrames -eq 0) { [double]::PositiveInfinity } else {
        100.0 * $lostFrames / $observedFrames
    }
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($stopReason -ne 'duration' -or
        $captureDuration -ne $RequiredDurationSeconds -or
        $elapsedSeconds -lt $RequiredDurationSeconds) {
        $reasons.Add('duration_not_reached')
    }
    if ($completedFrames -lt $RequiredMinimumFrames) {
        $reasons.Add('minimum_frames_not_met')
    }
    if ($lossPercent -gt $RequiredMaximumLossPercent) {
        $reasons.Add('loss_percent_exceeded')
    }
    if ($invalidDatagrams -ne 0) {
        $reasons.Add('invalid_datagrams_detected')
    }
    if ($lastFrameId -le $firstFrameId -or $frameIdSpan -le 100 -or
        $frameIdSpan -ne ($lastFrameId - $firstFrameId)) {
        $reasons.Add('frame_id_span_not_met')
    }

    return [pscustomobject][ordered]@{
        passed = ($reasons.Count -eq 0)
        duration_seconds = $RequiredDurationSeconds
        minimum_frames = $RequiredMinimumFrames
        maximum_loss_percent = $RequiredMaximumLossPercent
        completed_frames = $completedFrames
        lost_frames = $lostFrames
        loss_percent = $lossPercent
        invalid_datagrams = $invalidDatagrams
        first_frame_id = $firstFrameId
        last_frame_id = $lastFrameId
        frame_id_span = $frameIdSpan
        stop_reason = $stopReason
        failure_reasons = @($reasons)
    }
}

function Get-EthernetPreflight {
    param(
        [Parameter(Mandatory)][string]$HostAddress,
        [Parameter(Mandatory)][string]$TargetAddress
    )

    $ip = @(
        Get-NetIPAddress -AddressFamily IPv4 -IPAddress $HostAddress -ErrorAction SilentlyContinue |
            Select-Object -First 1
    )[0]
    if ($null -eq $ip) {
        throw "No PC adapter is configured with IPv4 address $HostAddress."
    }
    $adapter = Get-NetAdapter -InterfaceIndex $ip.InterfaceIndex -ErrorAction Stop
    if ($adapter.Status -ne 'Up') {
        throw "Adapter '$($adapter.Name)' for $HostAddress is not link-up (status=$($adapter.Status))."
    }
    $pingSucceeded = Test-Connection -ComputerName $TargetAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $pingSucceeded) {
        throw "No ping reply from $TargetAddress over the configured Ethernet link."
    }
    $jtagDevices = @()
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        $jtagDevices = @(
            Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
                Where-Object { $_.FriendlyName -match 'Xilinx|Digilent|JTAG' } |
                Select-Object Status, Class, FriendlyName, InstanceId
        )
    }
    if ($jtagDevices.Count -eq 0) {
        throw 'No present Xilinx/Digilent JTAG device was detected; launch the board before the Ethernet soak.'
    }
    return [pscustomobject][ordered]@{
        adapter_name = $adapter.Name
        adapter_interface_index = $adapter.ifIndex
        adapter_status = [string]$adapter.Status
        adapter_mac_address = $adapter.MacAddress
        host_ipv4 = $HostAddress
        board_ipv4 = $TargetAddress
        ping_succeeded = [bool]$pingSucceeded
        jtag_devices = $jtagDevices
    }
}

if (-not [string]::IsNullOrWhiteSpace($OfflineEvidencePath)) {
    $offlinePath = Resolve-Path -LiteralPath $OfflineEvidencePath -ErrorAction Stop
    $capture = Get-Content -LiteralPath $offlinePath -Raw | ConvertFrom-Json
    $result = Test-Axu4evEthernetCapture -Capture $capture `
        -RequiredDurationSeconds $DurationSeconds `
        -RequiredMinimumFrames $MinimumFrames `
        -RequiredMaximumLossPercent $MaximumLossPercent
    $result | ConvertTo-Json -Depth 4 -Compress
    if (-not $result.passed) {
        exit 1
    }
    exit 0
}

$preflight = Get-EthernetPreflight -HostAddress $Bind -TargetAddress $BoardAddress
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$linkEvidencePath = Join-Path $EvidenceDirectory "axu4ev-ad9364-ethernet-link-$timestamp.txt"
$linkText = @(
    'AXU4EV AD9364 Ethernet link preflight evidence'
    "captured_at_utc=$((Get-Date).ToUniversalTime().ToString('o'))"
    "adapter_name=$($preflight.adapter_name)"
    "adapter_interface_index=$($preflight.adapter_interface_index)"
    "adapter_status=$($preflight.adapter_status)"
    "adapter_mac_address=$($preflight.adapter_mac_address)"
    "host_ipv4=$($preflight.host_ipv4)"
    "board_ipv4=$($preflight.board_ipv4)"
    "ping_succeeded=$($preflight.ping_succeeded)"
    'jtag_devices_json='
    ($preflight.jtag_devices | ConvertTo-Json -Depth 4 -Compress)
) -join [Environment]::NewLine
[IO.File]::WriteAllText($linkEvidencePath, $linkText + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$scratch = Join-Path ([IO.Path]::GetTempPath()) "axu4ev-ethernet-soak-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    & $Python -m PROJECT.ethernet_fft.app `
        --bind $Bind --port $Port --headless --duration-seconds $DurationSeconds `
        --evidence-dir $scratch
    if ($LASTEXITCODE -ne 0) {
        throw "Headless Ethernet capture failed with exit code $LASTEXITCODE."
    }
    $capturePaths = @(Get-ChildItem -LiteralPath $scratch -Filter 'axu4ev-ad9364-ethernet-capture-*.json')
    if ($capturePaths.Count -ne 1) {
        throw "Expected one headless capture JSON artifact, found $($capturePaths.Count)."
    }
    $capture = Get-Content -LiteralPath $capturePaths[0].FullName -Raw | ConvertFrom-Json
    $result = Test-Axu4evEthernetCapture -Capture $capture `
        -RequiredDurationSeconds $DurationSeconds `
        -RequiredMinimumFrames $MinimumFrames `
        -RequiredMaximumLossPercent $MaximumLossPercent
    $soakEvidence = [ordered]@{
        schema_version = 1
        evidence_kind = 'axu4ev-ad9364-ethernet-soak'
        captured_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        link_evidence_path = $linkEvidencePath
        preflight = $preflight
        capture = $capture
        acceptance = $result
    }
    $soakEvidencePath = Join-Path $EvidenceDirectory "axu4ev-ad9364-ethernet-soak-$timestamp.json"
    [IO.File]::WriteAllText(
        $soakEvidencePath,
        ($soakEvidence | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    if (-not $result.passed) {
        throw "Ethernet soak acceptance failed: $($result.failure_reasons -join ', '). Evidence: $soakEvidencePath"
    }
    Write-Host "PASS: Ethernet soak accepted. Evidence: $soakEvidencePath"
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
