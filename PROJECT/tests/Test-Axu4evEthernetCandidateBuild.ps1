$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$buildTcl = Join-Path $root 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
$buildPs1 = Join-Path $root 'PROJECT\tools\Build-Axu4evPlFftCandidate.ps1'
$mainPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\main.c'
$transportPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\pl_fft_lwip_transport.c'
$platformPath = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\pl_fft_lwip_platform.c'
$gitignorePath = Join-Path $root '.gitignore'
$launcherPath = Join-Path $root 'PROJECT\tools\Start-Axu4evAd9364EthernetDev.cmd'
$orchestratorPath = Join-Path $root 'PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1'

function Assert-Match {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing Ethernet Candidate build contract: $Pattern"
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "Forbidden Ethernet Candidate build contract: $Pattern"
    }
}

function Remove-TestOwnedDevelopmentArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactPath,

        [Parameter(Mandatory)]
        [bool]$ArtifactCreated,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$CreatedDirectories,

        [Parameter(Mandatory)]
        [string]$Boundary
    )

    $boundaryPath = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    $boundaryPrefix = $boundaryPath + '\'
    if ($ArtifactCreated -and (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
        Remove-Item -LiteralPath $ArtifactPath -Force
    }
    foreach ($directory in @($CreatedDirectories | Sort-Object Length -Descending)) {
        $directoryPath = [IO.Path]::GetFullPath($directory).TrimEnd('\')
        if (-not $directoryPath.StartsWith(
                $boundaryPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a test-created directory outside '$boundaryPath': $directoryPath"
        }
        if ((Test-Path -LiteralPath $directoryPath -PathType Container) -and
            @(Get-ChildItem -LiteralPath $directoryPath -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directoryPath -Force
        }
    }
    if ($ArtifactCreated -and (Test-Path -LiteralPath $ArtifactPath)) {
        throw "Test-created development ELF remains after cleanup: $ArtifactPath"
    }
}

foreach ($path in @(
        $buildTcl,
        $buildPs1,
        $mainPath,
        $gitignorePath,
        $launcherPath,
        $orchestratorPath
    )) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Ethernet Candidate build dependency: $path"
    }
}

$tcl = Get-Content -LiteralPath $buildTcl -Raw
$ps1 = Get-Content -LiteralPath $buildPs1 -Raw
$main = Get-Content -LiteralPath $mainPath -Raw
$gitignore = Get-Content -LiteralPath $gitignorePath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$orchestrator = Get-Content -LiteralPath $orchestratorPath -Raw

Assert-Match $tcl 'PL_FFT_ETHERNET'
Assert-Match $tcl 'default_ethernet_workspace'
Assert-Match $tcl 'is_default_ethernet_workspace'
Assert-Match $tcl 'bsp setlib -name lwip211'
Assert-Match $tcl 'bsp config api_mode RAW_API'
Assert-Match $tcl 'bsp config no_sys_no_timers true'
Assert-Match $tcl 'bsp config lwip_dhcp false'
Assert-Match $tcl 'bsp config mem_size 524288'
Assert-Match $tcl 'bsp config pbuf_pool_size 256'
Assert-Match $ps1 "'Ethernet' \{ 'PL_FFT_ETHERNET' \}"
Assert-Match $ps1 "'Ethernet' \{ @\('PL_FFT_ETH: READY'\) \}"
Assert-Match $ps1 "vitis_ethernet[\\/]workspace"
Assert-Match $ps1 '\[switch\]\$BuildOnly'
Assert-Match $ps1 'build_only = \[bool\]\$BuildOnly'
Assert-Match $ps1 'subst\.exe'
Assert-Match $ps1 'mappedProjectRoot'
Assert-Match $ps1 'finally'
Assert-Match $main '#ifdef PL_FFT_ETHERNET'
Assert-Match $main 'uint32_t rf_state;'
Assert-Match $main 'snapshot->rf_state = \(uint8_t\)rf_state;'
Assert-Match $gitignore '/vitis_ethernet/workspace/'
Assert-Match $launcher 'Invoke-Axu4evAd9364Launch\.ps1'
Assert-Match $launcher '-Mode Candidate'
Assert-Match $launcher '-CandidateApplication'
Assert-Match $launcher 'vitis_ethernet[\\/]workspace[\\/]ad9364app[\\/]Release[\\/]ad9364app\.elf'
Assert-Match $launcher 'exit /b %RC%'
Assert-NotMatch $orchestrator 'CandidateApplication-only launch is unsafe'
Assert-Match $orchestrator 'fft-single-shot-v1'
Assert-Match $orchestrator 'vitis_ethernet[\\/]workspace'

$buildOnlyOutput = @(
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $buildPs1 `
        -ApplicationMode Ethernet `
        -WorkspaceRoot (Join-Path $root 'vitis_ethernet\workspace') `
        -BuildOnly `
        -DryRun
)
if ($LASTEXITCODE -ne 0) {
    throw "Ethernet BuildOnly dry-run failed with exit code $LASTEXITCODE."
}
$buildOnly = ($buildOnlyOutput -join "`n") | ConvertFrom-Json
if (-not [bool]$buildOnly.build_only -or
    $buildOnly.application_mode -cne 'Ethernet' -or
    $buildOnly.compiler_symbol -cne 'PL_FFT_ETHERNET' -or
    [IO.Path]::GetFullPath($buildOnly.vitis_workspace) -cne
        [IO.Path]::GetFullPath((Join-Path $root 'vitis_ethernet\workspace'))) {
    throw 'Ethernet BuildOnly dry-run did not select the isolated workspace contract.'
}

. $buildPs1 `
    -ApplicationMode Ethernet `
    -WorkspaceRoot (Join-Path $root 'vitis_ethernet\workspace') `
    -BuildOnly `
    -DryRun | Out-Null
if (-not (Get-Command Invoke-WithVerifiedSubstMapping -ErrorAction SilentlyContinue)) {
    throw 'Ethernet BuildOnly does not expose its verified SUBST lifecycle helper.'
}

$substFixture = Join-Path ([IO.Path]::GetTempPath()) `
    "axu4ev-ethernet-subst-$([guid]::NewGuid())"
$fakeSubst = Join-Path $substFixture 'subst-fixture.cmd'
$substState = Join-Path $substFixture 'mapped.txt'
$savedDeleteExit = $env:AXU4EV_TEST_SUBST_DELETE_EXIT
$savedKeepMapping = $env:AXU4EV_TEST_SUBST_KEEP_MAPPING
try {
    New-Item -ItemType Directory -Path $substFixture | Out-Null
    @"
@echo off
setlocal
set "STATE=$substState"
if "%~1"=="" (
  if exist "%STATE%" echo V:\: =^> C:\fixture
  exit /b 0
)
if /I "%~2"=="/D" (
  if not "%AXU4EV_TEST_SUBST_KEEP_MAPPING%"=="1" del /q "%STATE%" >nul 2>&1
  if "%AXU4EV_TEST_SUBST_DELETE_EXIT%"=="" exit /b 0
  exit /b %AXU4EV_TEST_SUBST_DELETE_EXIT%
)
type nul > "%STATE%"
exit /b 0
"@ | Set-Content -LiteralPath $fakeSubst -Encoding Ascii

    $env:AXU4EV_TEST_SUBST_DELETE_EXIT = '0'
    $env:AXU4EV_TEST_SUBST_KEEP_MAPPING = '0'
    Invoke-WithVerifiedSubstMapping `
        -SubstDrive 'V:' `
        -TargetRoot $substFixture `
        -SubstExecutable $fakeSubst `
        -Operation {
            param($mappedRoot)
            if ($mappedRoot -cne 'V:\') {
                throw "SUBST operation received the wrong mapped root: $mappedRoot"
            }
        }
    if (Test-Path -LiteralPath $substState) {
        throw 'Successful SUBST cleanup left the mapping fixture present.'
    }

    $env:AXU4EV_TEST_SUBST_DELETE_EXIT = '23'
    $env:AXU4EV_TEST_SUBST_KEEP_MAPPING = '0'
    $combinedFailure = $null
    try {
        Invoke-WithVerifiedSubstMapping `
            -SubstDrive 'V:' `
            -TargetRoot $substFixture `
            -SubstExecutable $fakeSubst `
            -Operation { throw 'forced original build failure' }
    }
    catch {
        $combinedFailure = $_.Exception.Message
    }
    if ($combinedFailure -notmatch 'forced original build failure' -or
        $combinedFailure -notmatch 'exit code 23') {
        throw "SUBST cleanup did not preserve both failures: $combinedFailure"
    }

    $env:AXU4EV_TEST_SUBST_DELETE_EXIT = '0'
    $env:AXU4EV_TEST_SUBST_KEEP_MAPPING = '1'
    $remainingMappingFailure = $null
    try {
        Invoke-WithVerifiedSubstMapping `
            -SubstDrive 'V:' `
            -TargetRoot $substFixture `
            -SubstExecutable $fakeSubst `
            -Operation { }
    }
    catch {
        $remainingMappingFailure = $_.Exception.Message
    }
    if ($remainingMappingFailure -notmatch 'remains mapped') {
        throw "SUBST cleanup did not reject a remaining mapping: $remainingMappingFailure"
    }
}
finally {
    $env:AXU4EV_TEST_SUBST_DELETE_EXIT = $savedDeleteExit
    $env:AXU4EV_TEST_SUBST_KEEP_MAPPING = $savedKeepMapping
    $resolvedSubstFixture = [IO.Path]::GetFullPath($substFixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedSubstFixture.StartsWith(
            $tempPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedSubstFixture -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

$cleanupFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) `
    "axu4ev-ethernet-workspace-$([guid]::NewGuid())"
try {
    $cleanupFixtureWorkspace = Join-Path $cleanupFixtureRoot 'workspace'
    $cleanupFixtureRelease = Join-Path $cleanupFixtureWorkspace 'ad9364app\Release'
    $cleanupFixtureElf = Join-Path $cleanupFixtureRelease 'ad9364app.elf'
    $cleanupFixtureSentinel = Join-Path $cleanupFixtureWorkspace 'preexisting-sentinel.txt'
    New-Item -ItemType Directory -Path $cleanupFixtureWorkspace | Out-Null
    Set-Content -LiteralPath $cleanupFixtureSentinel -Value 'preserve-me' -Encoding Ascii
    New-Item -ItemType Directory -Path $cleanupFixtureRelease -Force | Out-Null
    [IO.File]::WriteAllBytes(
        $cleanupFixtureElf,
        [byte[]](0x7F, 0x45, 0x4C, 0x46))
    Remove-TestOwnedDevelopmentArtifact `
        -ArtifactPath $cleanupFixtureElf `
        -ArtifactCreated $true `
        -CreatedDirectories @(
            $cleanupFixtureRelease,
            (Split-Path $cleanupFixtureRelease -Parent)
        ) `
        -Boundary $cleanupFixtureRoot
    if ((Get-Content -LiteralPath $cleanupFixtureSentinel -Raw).Trim() -cne
        'preserve-me') {
        throw 'Development ELF cleanup erased or changed preexisting workspace content.'
    }
}
finally {
    $resolvedCleanupFixture = [IO.Path]::GetFullPath($cleanupFixtureRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedCleanupFixture.StartsWith(
            $tempPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedCleanupFixture -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

$developmentWorkspace = Join-Path $root 'vitis_ethernet\workspace'
$developmentElf = Join-Path $developmentWorkspace 'ad9364app\Release\ad9364app.elf'
$createdDevelopmentElf = $false
$createdDevelopmentDirectories = New-Object System.Collections.Generic.List[string]
try {
    if (-not (Test-Path -LiteralPath $developmentElf -PathType Leaf)) {
        $currentDirectory = Split-Path $developmentElf -Parent
        while (-not (Test-Path -LiteralPath $currentDirectory)) {
            $createdDevelopmentDirectories.Add($currentDirectory)
            $parentDirectory = Split-Path $currentDirectory -Parent
            if ([string]::IsNullOrWhiteSpace($parentDirectory) -or
                $parentDirectory -eq $currentDirectory) {
                throw "Cannot find an existing ancestor for test development ELF: $developmentElf"
            }
            $currentDirectory = $parentDirectory
        }
        New-Item -ItemType Directory -Path (Split-Path $developmentElf -Parent) -Force |
            Out-Null
        [IO.File]::WriteAllBytes(
            $developmentElf,
            [byte[]](0x7F, 0x45, 0x4C, 0x46))
        $createdDevelopmentElf = $true
    }

    $launchOutput = @(
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $orchestratorPath `
            -Mode Candidate `
            -CandidateApplication $developmentElf `
            -DryRun
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Ethernet development launch dry-run failed with exit code $LASTEXITCODE."
    }
    $launch = ($launchOutput -join "`n") | ConvertFrom-Json
    $launchApplication = @($launch.artifacts | Where-Object name -eq 'application')
    if ($launch.mode -cne 'Candidate' -or
        $launchApplication.Count -ne 1 -or
        [IO.Path]::GetFullPath($launchApplication[0].path) -cne
            [IO.Path]::GetFullPath($developmentElf)) {
        throw 'Ethernet development launch did not pair the isolated ELF with Candidate mode.'
    }
    $trustedReference = [IO.Path]::GetFullPath(
        (Join-Path $root 'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1')) +
        [IO.Path]::DirectorySeparatorChar
    foreach ($artifact in @($launch.artifacts | Where-Object name -ne 'application')) {
        if (-not [IO.Path]::GetFullPath($artifact.path).StartsWith(
                $trustedReference,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Ethernet development launch hardware escaped the trusted reference: $($artifact.path)"
        }
    }
}
finally {
    Remove-TestOwnedDevelopmentArtifact `
        -ArtifactPath $developmentElf `
        -ArtifactCreated $createdDevelopmentElf `
        -CreatedDirectories @($createdDevelopmentDirectories) `
        -Boundary $root
}

foreach ($path in @($transportPath, $platformPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Ethernet Candidate lwIP source: $path"
    }
}

$transport = Get-Content -LiteralPath $transportPath -Raw
$platform = Get-Content -LiteralPath $platformPath -Raw

Assert-Match $transport 'pbuf_alloc\(PBUF_TRANSPORT,\s*\(uint16_t\)\(64u \+ bin_count \* 8u\),\s*PBUF_RAM\)'
Assert-Match $transport 'udp_sendto\(transport->pcb,\s*packet,\s*&transport->target,\s*5005u\)'
Assert-Match $transport 'pbuf_free\(packet\)'
Assert-Match $transport 'payload_bytes == 0u'
Assert-Match $transport 'payload_bytes > PL_FFT_UDP_BINS_PER_CHUNK \* sizeof\(uint64_t\)'
Assert-Match $platform 'XPAR_XEMACPS_0_BASEADDR'
Assert-Match $platform 'xemac_add\('
Assert-Match $platform 'netif_set_default\('
Assert-Match $platform 'netif_set_up\('
Assert-Match $platform 'XTtcPs'
Assert-Match $platform 'XScuGic'
Assert-NotMatch $platform 'lwip/timeouts\.h'
Assert-NotMatch $platform 'sys_check_timeouts'
Assert-Match $platform 'pl_fft_lwip_timer_pending = 0u;\s*xemacif_input\(&platform->netif\);'

Write-Output 'PASS: Ethernet Candidate build and lwIP platform contracts are isolated.'
