[CmdletBinding()]
param(
    [ValidateSet('Golden', 'Workspace', 'Candidate')]
    [string]$Mode = 'Golden',

    [string]$WorkspaceRoot,

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

if ($Mode -in @('Golden', 'Candidate')) {
    $release = Resolve-Axu4evCurrentRelease $releaseBase
    $manifest = Read-Axu4evReleaseManifest $release.FullName
    $verified = @(Test-Axu4evReleaseArtifacts $release.FullName $manifest)
    foreach ($item in $verified) {
        $paths[$item.Name] = $item.Path
    }

    if ($Mode -eq 'Candidate') {
        if ([string]::IsNullOrWhiteSpace($CandidateApplication)) {
            $CandidateApplication = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\Release\ad9364app.elf'
        }
        if (-not (Test-Path -LiteralPath $CandidateApplication -PathType Leaf)) {
            throw "Missing Release candidate application ELF: $CandidateApplication"
        }
        $paths.application = (Resolve-Path -LiteralPath $CandidateApplication).Path
    }
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
    $artifacts | Format-Table -AutoSize | Out-String | Add-Content -LiteralPath $logPath -Encoding Unicode
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
