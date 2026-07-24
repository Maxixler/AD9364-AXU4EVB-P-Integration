[CmdletBinding()]
param(
    [ValidateSet('Golden', 'Workspace', 'Candidate')]
    [string]$Mode = 'Golden',

    [string]$WorkspaceRoot,

    [string]$CandidateRoot,

    [string]$CandidateApplication,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
else {
    $WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
}

$module = Join-Path $PSScriptRoot 'Axu4evRelease.psm1'
$launchTcl = Join-Path $WorkspaceRoot 'PROJECT\tests\Launch-Axu4evAd9364Jtag.tcl'
$xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
foreach ($required in @($module, $launchTcl, $xsct)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing launch dependency: $required"
    }
}

Import-Module $module -Force
$paths = [ordered]@{}

$releaseBase = Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$candidateBase = Join-Path $WorkspaceRoot 'PROJECT\candidates\axu4ev-ad9364'

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Boundary
    )

    $boundaryPath = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    $boundaryPrefix = $boundaryPath + '\'
    $current = Get-Item -LiteralPath $Path
    while ($true) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate path contains a reparse point: $($current.FullName)"
        }
        if ($current.FullName.TrimEnd('\').Equals(
                $boundaryPath,
                [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        if (-not $current.FullName.StartsWith(
                $boundaryPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Candidate path escaped its approved tree: $($current.FullName)"
        }
        if ($current -is [IO.DirectoryInfo]) {
            $current = $current.Parent
        }
        else {
            $current = $current.Directory
        }
        if (-not $current) {
            throw "Candidate path has no approved-tree ancestor: $Path"
        }
    }
}

function Assert-CandidateFftHardwareContract {
    param(
        [Parameter(Mandatory)]
        [string]$Xsa,

        [Parameter(Mandatory)]
        [string]$Bitstream
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Xsa)
    try {
        $hwhEntry = @($archive.Entries |
            Where-Object {
                $_.FullName -notmatch '/' -and
                [IO.Path]::GetExtension($_.FullName) -eq '.hwh'
            }) | Select-Object -First 1
        $bitEntry = @($archive.Entries |
            Where-Object {
                $_.FullName -notmatch '/' -and
                [IO.Path]::GetExtension($_.FullName) -eq '.bit'
            }) | Select-Object -First 1
        if (-not $hwhEntry -or -not $bitEntry) {
            throw 'Candidate XSA does not contain its top-level HWH and embedded bitstream.'
        }

        $reader = New-Object IO.StreamReader($hwhEntry.Open())
        try {
            $hwh = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        foreach ($pattern in @(
            'BASEVALUE="0x9C440000"[^>]+INSTANCE="axi_ad9364_fft_capture"',
            'BASEVALUE="0x9D000000"[^>]+INSTANCE="axi_ad9364_fft_bram0"',
            'BASEVALUE="0x9D010000"[^>]+INSTANCE="axi_ad9364_fft_bram1"'
        )) {
            if ($hwh -notmatch $pattern) {
                throw 'Candidate XSA does not satisfy the locked PL FFT address contract.'
            }
        }

        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bitInput = $bitEntry.Open()
        try {
            $embeddedHash = [BitConverter]::ToString(
                $sha256.ComputeHash($bitInput)).Replace('-', '')
        }
        finally {
            $bitInput.Dispose()
            $sha256.Dispose()
        }
        $standaloneHash = (Get-FileHash -LiteralPath $Bitstream -Algorithm SHA256).Hash
        if ($embeddedHash -ne $standaloneHash) {
            throw 'Candidate XSA embedded bitstream does not match the standalone Candidate bitstream.'
        }
    }
    finally {
        $archive.Dispose()
    }
}

if ($Mode -eq 'Golden') {
    $release = Resolve-Axu4evCurrentRelease $releaseBase
    $manifest = Read-Axu4evReleaseManifest $release.FullName
    $verified = @(Test-Axu4evReleaseArtifacts $release.FullName $manifest)
    foreach ($item in $verified) {
        $paths[$item.Name] = $item.Path
    }
}
elseif ($Mode -eq 'Candidate') {
    if (-not [string]::IsNullOrWhiteSpace($CandidateApplication)) {
        throw 'CandidateApplication-only launch is unsafe. Provide a complete CandidateRoot bundle.'
    }
    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) {
        throw 'Candidate mode requires CandidateRoot.'
    }

    $candidate = Get-Item -LiteralPath (Resolve-Path -LiteralPath $CandidateRoot).Path
    if (-not $candidate.PSIsContainer) {
        throw "CandidateRoot is not a directory: $($candidate.FullName)"
    }

    $golden = Resolve-Axu4evCurrentRelease $releaseBase
    $candidateBasePath = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\')
    $candidateBasePrefix = $candidateBasePath + '\'
    $releaseBasePath = [IO.Path]::GetFullPath($releaseBase).TrimEnd('\')
    $releaseBasePrefix = $releaseBasePath + '\'
    $candidatePrefix = $candidate.FullName.TrimEnd('\') + '\'
    if ($candidate.FullName.Equals($releaseBasePath, [StringComparison]::OrdinalIgnoreCase) -or
        $candidatePrefix.StartsWith($releaseBasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CandidateRoot resolves inside the Golden release tree: $($candidate.FullName)"
    }
    if (-not $candidate.FullName.StartsWith(
            $candidateBasePrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "CandidateRoot must be inside the approved Candidate tree: $($candidate.FullName)"
    }
    Assert-NoReparsePoint -Path $candidate.FullName -Boundary $candidateBasePath

    $manifest = Read-Axu4evReleaseManifest $candidate.FullName
    $verified = @(Test-Axu4evReleaseArtifacts $candidate.FullName $manifest)
    foreach ($item in $verified) {
        $artifactPath = [IO.Path]::GetFullPath($item.Path)
        if ($artifactPath.Equals($golden.FullName, [StringComparison]::OrdinalIgnoreCase) -or
            $artifactPath.StartsWith($releaseBasePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Candidate artifact resolves inside the Golden release tree: $artifactPath"
        }
        Assert-NoReparsePoint -Path $artifactPath -Boundary $candidateBasePath
        $paths[$item.Name] = $artifactPath
    }
    Assert-CandidateFftHardwareContract -Xsa $paths.xsa -Bitstream $paths.bitstream
}
else {
    $handoffTest = Join-Path $WorkspaceRoot 'PROJECT\tests\Test-Axu4evHandoffArtifacts.ps1'
    if (-not (Test-Path -LiteralPath $handoffTest -PathType Leaf)) {
        throw "Missing workspace handoff verifier: $handoffTest"
    }
    $handoffOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $handoffTest -WorkspaceRoot $WorkspaceRoot)
    if ($LASTEXITCODE -ne 0) {
        throw "Workspace handoff verification failed.`r`n$($handoffOutput -join "`r`n")"
    }
    Write-Verbose ($handoffOutput -join [Environment]::NewLine)

    $appRoot = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app'
    $application = @('Release', 'Debug') |
        ForEach-Object { Join-Path $appRoot "$_\ad9364app.elf" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $application) {
        throw 'Missing workspace application ELF under Release or Debug.'
    }

    $paths.bitstream = Join-Path $appRoot '_ide\bitstream\system_top.bit'
    $paths.psu_init = Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl'
    $paths.pmufw = Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf'
    $paths.application = $application
}

$requiredNames = @('bitstream', 'psu_init', 'pmufw', 'application')
if ($Mode -eq 'Candidate') {
    $requiredNames += 'xsa'
}
$artifacts = @(
    foreach ($name in $requiredNames) {
        $path = [string]$paths[$name]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing launch artifact '$name': $path"
        }
        $item = Get-Item -LiteralPath $path
        [pscustomobject][ordered]@{
            name = $name
            path = $item.FullName
            length = $item.Length
            sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }
)

$logDir = Join-Path $WorkspaceRoot 'PROJECT\logs\jtag'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Mode.ToLowerInvariant() + '.log')
$result = [ordered]@{
    mode = $Mode
    xsct = $xsct
    tcl = $launchTcl
    log = $logPath
    artifacts = $artifacts
}
$artifactManifest = ConvertTo-Json -InputObject @($artifacts) -Depth 4 -Compress

if ($DryRun) {
    $result | ConvertTo-Json -Depth 6
    return
}

$environment = [ordered]@{
    AXU4EV_PMUFW_ELF = $paths.pmufw
    AXU4EV_BITSTREAM = $paths.bitstream
    AXU4EV_PSU_INIT_TCL = $paths.psu_init
    AXU4EV_APP_ELF = $paths.application
}
$savedEnvironment = @{}
foreach ($name in $environment.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process')
}

try {
    "Mode=$Mode" | Set-Content -LiteralPath $logPath -Encoding Unicode
    "ARTIFACT_MANIFEST_JSON=$artifactManifest" | Add-Content -LiteralPath $logPath -Encoding Unicode
    & $xsct $launchTcl 2>&1 | Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "XSCT launch failed with exit code $exitCode. Log: $logPath"
    }
    Write-Output "PASS: $Mode launch completed. Check PS_UART in PuTTY. Log: $logPath"
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
