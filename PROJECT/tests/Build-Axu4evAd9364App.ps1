[CmdletBinding()]
param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')

$drive = 'P:'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$buildRoot = [IO.Path]::GetFullPath(
    (Join-Path $tempRoot "t5-$PID-$([guid]::NewGuid().ToString('N'))")
)
if ([IO.Path]::GetDirectoryName($buildRoot) -ne $tempRoot) {
    throw "Unsafe temporary build path: $buildRoot"
}

$metadataFiles = @(
    (Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\ad9364app.prj'),
    (Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app_system\ad9364app_system.sprj'),
    (Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\platform.spr')
)
$platformXpfm = Join-Path $WorkspaceRoot `
    'Vitis\workspace\fmcomms2_axu4ev_hw\export\fmcomms2_axu4ev_hw\fmcomms2_axu4ev_hw.xpfm'
$sourceDirectory = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\src'
$trackedBuildScript = Join-Path $WorkspaceRoot 'PROJECT\tests\Build-Axu4evAd9364App.tcl'
$xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
$buildScript = Join-Path $buildRoot 'bootstrap.tcl'
$temporaryElf = Join-Path $buildRoot 'Vitis\workspace\ad9364app\Release\ad9364app.elf'
$elf = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\Release\ad9364app.elf'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$metadataOriginal = @{}
$driveMapped = $false

foreach ($path in @($platformXpfm, $trackedBuildScript, $xsct)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing AD9364 build input: $path"
    }
}
if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
    throw "Missing AD9364 source directory: $sourceDirectory"
}
foreach ($path in $metadataFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Vitis metadata: $path"
    }
}

$bootstrapTemplate = @'
set build_root __BUILD_ROOT__
set build_workspace [file join $build_root Vitis workspace]
file mkdir $build_workspace

setws $build_workspace
platform create -xpfm [file join P: Vitis workspace fmcomms2_axu4ev_hw export fmcomms2_axu4ev_hw fmcomms2_axu4ev_hw.xpfm]
platform active fmcomms2_axu4ev_hw
platform generate
app create -name ad9364app -platform fmcomms2_axu4ev_hw -domain standalone_domain -sysproj ad9364app_system -template "Empty Application" -lang c
importsources -name ad9364app -path [file join P: Vitis workspace ad9364app src] -linker-script
if {[string first ad9364app [app list]] < 0} {
  error "Isolated application creation did not register 'ad9364app'."
}

set ::env(FPGA_PROFEN_ROOT) $build_root
source P:/PROJECT/tests/Build-Axu4evAd9364App.tcl
'@

try {
    New-Item -ItemType Directory -Path $buildRoot | Out-Null

    & subst $drive $WorkspaceRoot
    if ($LASTEXITCODE -ne 0) { throw "Could not map $drive to the workspace." }
    $driveMapped = $true

    foreach ($path in $metadataFiles) {
        $text = [IO.File]::ReadAllText($path)
        $metadataOriginal[$path] = $text
        $text = [regex]::Replace(
            $text,
            '(?i)[A-Z]:/.*?(?=/(?:Vitis/workspace|Related-Docs)/)',
            $drive
        )
        [IO.File]::WriteAllText($path, $text, $utf8)
    }

    $buildRootTcl = $buildRoot.Replace('\', '/')
    $bootstrapText = $bootstrapTemplate.Replace('__BUILD_ROOT__', $buildRootTcl)
    [IO.File]::WriteAllText($buildScript, $bootstrapText, $utf8)

    $existingXsctIds = @(Get-Process -Name 'rdi_xsct' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Id })
    $buildStartedUtc = [DateTime]::UtcNow
    & $xsct $buildScript
    if ($LASTEXITCODE -ne 0) { throw 'XSCT application build failed.' }

    # Vitis 2020.1 may detach rdi_xsct from its batch launcher. Keep P:
    # mapped until the client exits and this invocation's isolated ELF exists.
    $deadline = [DateTime]::UtcNow.AddMinutes(15)
    $launchGraceDeadline = [DateTime]::UtcNow.AddSeconds(20)
    $sawDetachedXsct = $false
    while ($true) {
        $detachedXsct = @(Get-Process -Name 'rdi_xsct' -ErrorAction SilentlyContinue |
            Where-Object { $existingXsctIds -notcontains $_.Id })
        if ($detachedXsct.Count -gt 0) { $sawDetachedXsct = $true }

        $candidate = Get-Item -LiteralPath $temporaryElf -ErrorAction SilentlyContinue
        $freshElf = $null -ne $candidate -and
            $candidate.Length -gt 0 -and
            $candidate.LastWriteTimeUtc -ge $buildStartedUtc

        if ($freshElf -and $detachedXsct.Count -eq 0) { break }
        if ($sawDetachedXsct -and $detachedXsct.Count -eq 0) {
            throw 'XSCT exited without producing a fresh isolated Release ELF.'
        }
        if (-not $sawDetachedXsct -and $detachedXsct.Count -eq 0 -and
            [DateTime]::UtcNow -ge $launchGraceDeadline) {
            throw 'XSCT returned without a client or a fresh isolated Release ELF.'
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw 'Timed out waiting for the isolated Vitis Release build.'
        }
        Start-Sleep -Seconds 1
    }

    $releaseDirectory = Split-Path -Parent $elf
    if (-not (Test-Path -LiteralPath $releaseDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $releaseDirectory | Out-Null
    }
    Copy-Item -LiteralPath $temporaryElf -Destination $elf -Force
}
finally {
    foreach ($path in $metadataFiles) {
        if ($metadataOriginal.ContainsKey($path)) {
            [IO.File]::WriteAllText($path, $metadataOriginal[$path], $utf8)
        }
    }
    if ($driveMapped) { & subst $drive /D 2>$null }
    if ((Test-Path -LiteralPath $buildRoot) -and
        [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($buildRoot)) -eq $tempRoot) {
        Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "PASS: AD9364 application generated: $elf"
