[CmdletBinding()]
param(
    [string]$WorkspaceRoot,

    [string]$SourceXsa,

    [string]$CandidateRoot,

    [string]$VitisWorkspace,

    [string]$AllowedVitisWorkspaceRoot,

    [ValidateSet('SingleShot', 'PeriodicMonitor', 'LabUart', 'Ethernet')]
    [string]$ApplicationMode = 'SingleShot',

    [switch]$BuildOnly,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($BuildOnly) {
    if ($ApplicationMode -cne 'Ethernet') {
        throw 'BuildOnly is reserved for the isolated Ethernet development workspace.'
    }

    $projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $defaultWorkspace = [IO.Path]::GetFullPath(
        (Join-Path $projectRoot 'vitis_ethernet\workspace'))
    $selectedWorkspace = if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
        $defaultWorkspace
    }
    else {
        [IO.Path]::GetFullPath($WorkspaceRoot)
    }
    if (-not $selectedWorkspace.Equals(
            $defaultWorkspace,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ethernet BuildOnly workspace must be '$defaultWorkspace': $selectedWorkspace"
    }

    $allowedRoot = Split-Path $defaultWorkspace -Parent
    $existingAncestor = $allowedRoot
    while (-not (Test-Path -LiteralPath $existingAncestor)) {
        $existingAncestor = Split-Path $existingAncestor -Parent
    }
    $current = Get-Item -LiteralPath $existingAncestor
    while ($current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Ethernet BuildOnly workspace contains a reparse point: $($current.FullName)"
        }
        if ($current.FullName.TrimEnd('\').Equals(
                [IO.Path]::GetPathRoot($current.FullName).TrimEnd('\'),
                [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $current = $current.Parent
    }

    $referenceRoot = Join-Path $projectRoot `
        'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1'
    $manifestPath = Join-Path $referenceRoot 'manifest.json'
    $releaseModule = Join-Path $projectRoot 'PROJECT\tools\Axu4evRelease.psm1'
    $buildTcl = Join-Path $projectRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
    $xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
    foreach ($required in @($manifestPath, $releaseModule, $buildTcl, $xsct)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing Ethernet BuildOnly dependency: $required"
        }
    }

    $referenceRelative = 'PROJECT/candidates/axu4ev-ad9364/fft-single-shot-v1'
    $referenceStatus = @(
        & git -C $projectRoot status --porcelain=v1 --untracked-files=all -- $referenceRelative
    )
    if ($LASTEXITCODE -ne 0 -or $referenceStatus.Count -ne 0) {
        throw "Ethernet BuildOnly requires a clean board-verified reference.`r`n$($referenceStatus -join "`r`n")"
    }

    Import-Module $releaseModule -Force
    $referenceManifest = Read-Axu4evReleaseManifest -ReleaseRoot $referenceRoot
    if (-not $referenceManifest.board_verified) {
        throw 'Ethernet BuildOnly requires the board-verified fft-single-shot-v1 reference.'
    }
    $referenceArtifacts = @(
        Test-Axu4evReleaseArtifacts `
            -ReleaseRoot $referenceRoot `
            -Manifest $referenceManifest
    )
    $referenceByName = @{}
    foreach ($artifact in $referenceArtifacts) {
        $referenceByName[$artifact.Name] = $artifact
    }
    foreach ($requiredArtifact in @('bitstream', 'pmufw', 'psu_init', 'xsa')) {
        if (-not $referenceByName.ContainsKey($requiredArtifact)) {
            throw "Ethernet BuildOnly reference is missing '$requiredArtifact'."
        }
    }
    $trustedXsa = $referenceByName['xsa'].Path
    if (-not [string]::IsNullOrWhiteSpace($SourceXsa) -and
        -not [IO.Path]::GetFullPath($SourceXsa).Equals(
            [IO.Path]::GetFullPath($trustedXsa),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Ethernet BuildOnly cannot override the board-verified reference XSA.'
    }
    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
        throw 'Ethernet BuildOnly does not create or modify a Candidate bundle.'
    }

    $untrackedInputs = @(
        & git -C $projectRoot ls-files --others --exclude-standard -- `
            'Vitis/workspace/ad9364app/src'
    )
    if ($LASTEXITCODE -ne 0 -or $untrackedInputs.Count -ne 0) {
        throw "Ethernet BuildOnly rejects untracked application sources.`r`n$($untrackedInputs -join "`r`n")"
    }

    $description = [ordered]@{
        source_xsa = $trustedXsa
        source_xsa_sha256 = $referenceByName['xsa'].Sha256
        candidate_root = $null
        vitis_workspace = $selectedWorkspace
        application_mode = $ApplicationMode
        compiler_symbol = 'PL_FFT_ETHERNET'
        pl_fft_single_shot = $false
        pl_fft_periodic_monitor = $false
        pl_fft_lab_uart = $false
        pl_fft_ethernet = $true
        build_only = [bool]$BuildOnly
        trusted_reference = $referenceRoot
    }
    if ($DryRun) {
        $description | ConvertTo-Json -Depth 4
        return
    }

    $free = (Get-PSDrive -Name C).Free
    if ($free -lt 5GB) {
        throw 'At least 5 GiB free space is required for the Ethernet Vitis workspace.'
    }
    New-Item -ItemType Directory -Path $allowedRoot -Force | Out-Null
    $referenceHashes = @{}
    foreach ($artifact in $referenceArtifacts) {
        $referenceHashes[$artifact.Name] = (Get-FileHash `
                -LiteralPath $artifact.Path `
                -Algorithm SHA256).Hash
    }

    $usedDriveLetters = @(
        [IO.DriveInfo]::GetDrives() |
            ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() }
    )
    $substLetter = @('V', 'W', 'X', 'Y', 'Z') |
        Where-Object { $_ -notin $usedDriveLetters } |
        Select-Object -First 1
    if (-not $substLetter) {
        throw 'Ethernet BuildOnly requires one free drive letter from V: through Z: for Vitis 2020.1 path shortening.'
    }
    $substDrive = "$substLetter`:"
    & subst.exe $substDrive $projectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot map $substDrive to the project root for Vitis 2020.1."
    }
    try {
        $mappedProjectRoot = "$substDrive\"
        $mappedBuildTcl = Join-Path $mappedProjectRoot `
            'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
        $mappedTrustedXsa = Join-Path $mappedProjectRoot `
            'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1\hardware\system_top.xsa'
        $mappedAllowedRoot = Join-Path $mappedProjectRoot 'vitis_ethernet'
        $mappedWorkspace = Join-Path $mappedAllowedRoot 'workspace'
        & $xsct $mappedBuildTcl $mappedProjectRoot $mappedTrustedXsa `
            $mappedWorkspace $mappedAllowedRoot PL_FFT_ETHERNET
        $buildExitCode = $LASTEXITCODE
    }
    finally {
        & subst.exe $substDrive /D
    }
    if ($buildExitCode -ne 0) {
        throw "Ethernet BuildOnly Vitis build failed with exit code $buildExitCode."
    }

    $elf = Join-Path $selectedWorkspace 'ad9364app\Release\ad9364app.elf'
    if (-not (Test-Path -LiteralPath $elf -PathType Leaf) -or
        (Get-Item -LiteralPath $elf).Length -le 0) {
        throw "Ethernet BuildOnly did not produce a non-empty ELF: $elf"
    }
    $lwipManifests = @(
        Get-ChildItem -LiteralPath $selectedWorkspace -Recurse -Filter *.mss -File |
            Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'lwip211' -Quiet }
    )
    if ($lwipManifests.Count -eq 0) {
        throw 'Ethernet BuildOnly BSP manifest does not contain lwip211.'
    }
    foreach ($artifact in $referenceArtifacts) {
        $actualHash = (Get-FileHash -LiteralPath $artifact.Path -Algorithm SHA256).Hash
        if ($actualHash -cne $referenceHashes[$artifact.Name]) {
            throw "Ethernet BuildOnly modified trusted Candidate artifact '$($artifact.Name)'."
        }
    }

    Write-Output "PASS: Ethernet development ELF built at $elf"
    $description | ConvertTo-Json -Depth 4
    return
}

foreach ($requiredValue in @{
        SourceXsa = $SourceXsa
        CandidateRoot = $CandidateRoot
    }.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValue.Value)) {
        throw "$($requiredValue.Key) is required unless BuildOnly is selected."
    }
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
else {
    $WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
}
$defaultEthernetWorkspace = Join-Path $WorkspaceRoot 'vitis_ethernet\workspace'
$defaultEthernetWorkspaceRoot = Split-Path $defaultEthernetWorkspace -Parent
if ([string]::IsNullOrWhiteSpace($VitisWorkspace)) {
    if ($ApplicationMode -cne 'Ethernet') {
        throw 'VitisWorkspace is required unless ApplicationMode is Ethernet.'
    }
    $VitisWorkspace = $defaultEthernetWorkspace
}
if ([string]::IsNullOrWhiteSpace($AllowedVitisWorkspaceRoot)) {
    if ($ApplicationMode -cne 'Ethernet') {
        throw 'AllowedVitisWorkspaceRoot is required unless ApplicationMode is Ethernet.'
    }
    $AllowedVitisWorkspaceRoot = $defaultEthernetWorkspaceRoot
}
$SourceXsa = (Resolve-Path -LiteralPath $SourceXsa).Path
$CandidateRoot = [IO.Path]::GetFullPath($CandidateRoot)
$VitisWorkspace = [IO.Path]::GetFullPath($VitisWorkspace)
$AllowedVitisWorkspaceRoot = [IO.Path]::GetFullPath($AllowedVitisWorkspaceRoot)
$defaultEthernetWorkspace = [IO.Path]::GetFullPath($defaultEthernetWorkspace)
$usesDefaultEthernetWorkspace = (
    $ApplicationMode -ceq 'Ethernet' -and
    $VitisWorkspace.Equals(
        $defaultEthernetWorkspace,
        [StringComparison]::OrdinalIgnoreCase)
)
if ($usesDefaultEthernetWorkspace -and
    -not (Test-Path -LiteralPath $AllowedVitisWorkspaceRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $AllowedVitisWorkspaceRoot -Force | Out-Null
}

$goldenBase = Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$candidateBase = Join-Path $WorkspaceRoot 'PROJECT\candidates\axu4ev-ad9364'
$releaseModule = Join-Path $WorkspaceRoot 'PROJECT\tools\Axu4evRelease.psm1'
$buildTcl = Join-Path $WorkspaceRoot 'PROJECT\tools\Build-Axu4evPlFftCandidate.tcl'
$xsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
$compilerSymbol = switch ($ApplicationMode) {
    'SingleShot' { 'PL_FFT_SINGLE_SHOT' }
    'PeriodicMonitor' { 'PL_FFT_PERIODIC_MONITOR' }
    'LabUart' { 'PL_FFT_LAB_UART' }
    'Ethernet' { 'PL_FFT_ETHERNET' }
}
$uartMarkers = switch ($ApplicationMode) {
    'SingleShot' { @('PL_FFT: PASS') }
    'PeriodicMonitor' { @('PL_FFT_MONITOR: PASS') }
    'LabUart' { @('PL_FFT_LAB: READY') }
    'Ethernet' { @('PL_FFT_ETH: READY') }
}
$usesTrustedSingleShotReference = $ApplicationMode -in @(
    'PeriodicMonitor',
    'LabUart',
    'Ethernet'
)

function Assert-NoReparsePointForWrite {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Boundary
    )

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $boundaryPath = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    $boundaryPrefix = $boundaryPath + '\'
    if (-not $fullPath.Equals($boundaryPath, [StringComparison]::OrdinalIgnoreCase) -and
        -not $fullPath.StartsWith($boundaryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Write path is outside its approved boundary '$boundaryPath': $fullPath"
    }
    if (-not (Test-Path -LiteralPath $boundaryPath -PathType Container)) {
        throw "Approved write boundary does not exist: $boundaryPath"
    }

    $existingPath = $fullPath
    while (-not (Test-Path -LiteralPath $existingPath)) {
        $parent = Split-Path $existingPath -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $existingPath) {
            throw "Cannot find an existing approved ancestor for write path: $fullPath"
        }
        $existingPath = $parent
    }

    $current = Get-Item -LiteralPath $existingPath
    while ($true) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Write path contains a reparse point: $($current.FullName)"
        }
        if ($current.FullName.TrimEnd('\').Equals(
                $boundaryPath,
                [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        if (-not $current.FullName.StartsWith(
                $boundaryPrefix,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Write path escaped its approved boundary: $($current.FullName)"
        }
        $current = $current.Parent
        if (-not $current) {
            throw "Write path has no approved-boundary ancestor: $fullPath"
        }
    }
}

function Get-WorkspaceRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = $root + '\'
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the Candidate workspace: $fullPath"
    }
    return $fullPath.Substring($prefix.Length).Replace('\', '/')
}

function Assert-CandidateTrackedSourceCleanliness {
    param([Parameter(Mandatory = $true)][string]$SelectedCandidateRoot)

    $trackedChanges = @(& git -C $WorkspaceRoot status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot inspect the Candidate source tree state.'
    }
    $candidateRelative = Get-WorkspaceRelativePath -Path $SelectedCandidateRoot
    $candidateRelativePrefix = $candidateRelative.TrimEnd('/') + '/'
    $unexpectedTrackedChanges = @($trackedChanges | Where-Object {
        $path = if ($_.Length -gt 3) { $_.Substring(3).Replace('\', '/') } else { '' }
        -not $path.Equals($candidateRelative, [StringComparison]::OrdinalIgnoreCase) -and
        -not $path.StartsWith($candidateRelativePrefix, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($unexpectedTrackedChanges.Count -ne 0) {
        throw "Candidate builds require clean tracked source inputs.`r`n$($unexpectedTrackedChanges -join "`r`n")"
    }
}

function Assert-GitPathMatchesHeadAndIndex {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    & git -C $WorkspaceRoot cat-file -e "HEAD:$RelativePath"
    if ($LASTEXITCODE -ne 0) {
        throw "$Description is not committed at HEAD: $RelativePath"
    }
    $headObject = (& git -C $WorkspaceRoot rev-parse "HEAD:$RelativePath").Trim()
    $indexObject = (& git -C $WorkspaceRoot rev-parse ":$RelativePath").Trim()
    if ($LASTEXITCODE -ne 0 -or $headObject -cne $indexObject) {
        throw "$Description differs between HEAD and the Git index: $RelativePath"
    }
    & git -C $WorkspaceRoot diff --quiet --no-ext-diff -- $RelativePath
    if ($LASTEXITCODE -ne 0) {
        throw "$Description differs between the Git index and working tree: $RelativePath"
    }
}

function Assert-TrustedPeriodicReferenceProvenance {
    param([Parameter(Mandatory = $true)][string]$ReferenceRoot)

    & git -C $WorkspaceRoot rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Periodic Candidate builds require the trusted fft-single-shot-v1 reference to be in a Git worktree.'
    }
    $referenceRelative = Get-WorkspaceRelativePath -Path $ReferenceRoot
    $referenceStatus = @(& git -C $WorkspaceRoot status --porcelain=v1 --untracked-files=all -- $referenceRelative)
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot inspect the trusted fft-single-shot-v1 reference source state.'
    }
    if ($referenceStatus.Count -ne 0) {
        throw "Periodic Candidate builds require a clean trusted fft-single-shot-v1 reference before reading it.`r`n$($referenceStatus -join "`r`n")"
    }

    $manifestRelative = "$referenceRelative/manifest.json"
    Assert-GitPathMatchesHeadAndIndex -RelativePath $manifestRelative -Description 'Trusted fft-single-shot-v1 manifest'
    $referenceManifest = Get-Content -LiteralPath (Join-Path $ReferenceRoot 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($artifact in @($referenceManifest.artifacts)) {
        $artifactPath = [string]$artifact.path
        if ([string]::IsNullOrWhiteSpace($artifactPath) -or
            [IO.Path]::IsPathRooted($artifactPath) -or
            $artifactPath -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Trusted fft-single-shot-v1 manifest has an unsafe artifact path: $artifactPath"
        }
        Assert-GitPathMatchesHeadAndIndex `
            -RelativePath "$referenceRelative/$($artifactPath.Replace('\', '/'))" `
            -Description "Trusted fft-single-shot-v1 artifact '$($artifact.name)'"
    }
}

foreach ($required in @($SourceXsa, $releaseModule, $buildTcl, $xsct)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing Candidate build dependency: $required"
    }
}

$goldenPrefix = [IO.Path]::GetFullPath($goldenBase).TrimEnd('\') + '\'
$candidatePrefix = [IO.Path]::GetFullPath($candidateBase).TrimEnd('\') + '\'
if ($CandidateRoot.StartsWith($goldenPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "CandidateRoot cannot be inside the Golden release tree: $CandidateRoot"
}
if (-not $CandidateRoot.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "CandidateRoot must be inside the project Candidate tree: $CandidateRoot"
}
Assert-NoReparsePointForWrite -Path $CandidateRoot -Boundary $candidateBase
$protectedCandidateRoots = @(
    (Join-Path $candidateBase 'fft-single-shot-v1'),
    (Join-Path $candidateBase 'fft-periodic-monitor-v1')
)
foreach ($protectedCandidateRoot in $protectedCandidateRoots) {
    $protectedRoot = [IO.Path]::GetFullPath($protectedCandidateRoot).TrimEnd('\')
    $protectedPrefix = $protectedRoot + '\'
    $selectedRoot = $CandidateRoot.TrimEnd('\')
    $selectedPrefix = $selectedRoot + '\'
    if ($selectedRoot.Equals($protectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $selectedRoot.StartsWith($protectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $protectedRoot.StartsWith($selectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CandidateRoot cannot overlap an accepted Candidate bundle: $protectedRoot"
    }
}
if (-not $DryRun -and (Test-Path -LiteralPath (Join-Path $CandidateRoot 'manifest.json') -PathType Leaf)) {
    throw "CandidateRoot already contains an immutable manifest: $CandidateRoot"
}
Assert-CandidateTrackedSourceCleanliness -SelectedCandidateRoot $CandidateRoot

Import-Module $releaseModule -Force
$singleShotReferenceArtifacts = @{}
$hardwareContractReferenceXsa = if ($usesTrustedSingleShotReference) {
    $singleShotReference = (Resolve-Path -LiteralPath (Join-Path $candidateBase 'fft-single-shot-v1')).Path
    Assert-TrustedPeriodicReferenceProvenance -ReferenceRoot $singleShotReference
    $singleShotManifest = Read-Axu4evReleaseManifest -ReleaseRoot $singleShotReference
    if (-not $singleShotManifest.board_verified) {
        throw 'The fft-single-shot-v1 Candidate reference must be board verified.'
    }
    foreach ($artifact in @(Test-Axu4evReleaseArtifacts `
            -ReleaseRoot $singleShotReference `
            -Manifest $singleShotManifest)) {
        $singleShotReferenceArtifacts[$artifact.Name] = [pscustomobject]@{
            Path = $artifact.Path
            Sha256 = $artifact.Sha256
        }
    }
    foreach ($requiredArtifact in @('bitstream', 'pmufw', 'psu_init', 'xsa')) {
        if (-not $singleShotReferenceArtifacts.ContainsKey($requiredArtifact)) {
            throw "The fft-single-shot-v1 Candidate reference is missing '$requiredArtifact'."
        }
    }
    $singleShotReferenceArtifacts['xsa'].Path
}
else {
    $referenceRelease = Resolve-Axu4evCurrentRelease -ReleasesRoot $goldenBase
    $referenceManifest = Read-Axu4evReleaseManifest -ReleaseRoot $referenceRelease.FullName
    $referenceArtifacts = @(
        Test-Axu4evReleaseArtifacts `
            -ReleaseRoot $referenceRelease.FullName `
            -Manifest $referenceManifest
    )
    $referenceXsa = @(
        $referenceArtifacts |
            Where-Object Name -eq 'xsa' |
            ForEach-Object Path
    )
    if ($referenceXsa.Count -ne 1) {
        throw 'The current Golden release must contain exactly one XSA artifact.'
    }
    $referencePmufw = @(
        $referenceArtifacts |
            Where-Object Name -eq 'pmufw' |
            ForEach-Object Path
    )
    if ($referencePmufw.Count -ne 1) {
        throw 'The current Golden release must contain exactly one PMUFW artifact.'
    }
    $referenceXsa[0]
}

if ($usesTrustedSingleShotReference) {
    $singleShotReferenceRoot = [IO.Path]::GetFullPath($singleShotReference).TrimEnd('\')
    $singleShotReferencePrefix = $singleShotReferenceRoot + '\'
    $candidateRootPrefix = $CandidateRoot.TrimEnd('\') + '\'
    if ($CandidateRoot.TrimEnd('\').Equals(
            $singleShotReferenceRoot,
            [StringComparison]::OrdinalIgnoreCase) -or
        $CandidateRoot.StartsWith($singleShotReferencePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $singleShotReferenceRoot.StartsWith($candidateRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$ApplicationMode CandidateRoot cannot overlap the board-verified fft-single-shot-v1 reference: $CandidateRoot"
    }
}
$allowedWorkspacePrefix = $AllowedVitisWorkspaceRoot.TrimEnd('\') + '\'
$vitisWorkspacePrefix = $VitisWorkspace.TrimEnd('\') + '\'
$allowedWorkspaceRootTrimmed = $AllowedVitisWorkspaceRoot.TrimEnd('\')
if ([IO.Path]::GetPathRoot($AllowedVitisWorkspaceRoot).TrimEnd('\').Equals(
        $allowedWorkspaceRootTrimmed,
        [StringComparison]::OrdinalIgnoreCase) -or
    -not $VitisWorkspace.StartsWith($allowedWorkspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "VitisWorkspace must be a child of the approved root '$AllowedVitisWorkspaceRoot': $VitisWorkspace"
}
$protectedPaths = @($CandidateRoot, $goldenBase, (Split-Path $SourceXsa -Parent))
if (-not $usesDefaultEthernetWorkspace) {
    $protectedPaths = @($WorkspaceRoot) + $protectedPaths
}
foreach ($protectedPath in $protectedPaths) {
    $protectedPrefix = [IO.Path]::GetFullPath($protectedPath).TrimEnd('\') + '\'
    if ($VitisWorkspace.Equals(
            [IO.Path]::GetFullPath($protectedPath),
            [StringComparison]::OrdinalIgnoreCase) -or
        $VitisWorkspace.StartsWith($protectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFullPath($protectedPath).StartsWith(
            $vitisWorkspacePrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe Candidate Vitis workspace overlaps protected path '$protectedPath': $VitisWorkspace"
    }
}
if ($VitisWorkspace.Equals($AllowedVitisWorkspaceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe Candidate Vitis workspace path: $VitisWorkspace"
}
Assert-NoReparsePointForWrite -Path $VitisWorkspace -Boundary $AllowedVitisWorkspaceRoot

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($SourceXsa)
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
        throw 'Candidate XSA does not contain a top-level HWH and bitstream.'
    }

    $reader = New-Object IO.StreamReader($hwhEntry.Open())
    try {
        $hwh = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    $requiredHwhPatterns = [ordered]@{
        fft_control = 'BASEVALUE="0x9C440000"[^>]+INSTANCE="axi_ad9364_fft_capture"'
        fft_bank0 = 'BASEVALUE="0x9D000000"[^>]+INSTANCE="axi_ad9364_fft_bram0"'
        fft_bank1 = 'BASEVALUE="0x9D010000"[^>]+INSTANCE="axi_ad9364_fft_bram1"'
    }
    foreach ($entry in $requiredHwhPatterns.GetEnumerator()) {
        if ($hwh -notmatch $entry.Value) {
            throw "Candidate XSA is missing the locked PL FFT hardware mapping '$($entry.Key)'."
        }
    }
    Assert-Axu4evPsHardwareContract `
        -Xsa $SourceXsa `
        -ReferenceXsa $hardwareContractReferenceXsa

    $description = [ordered]@{
        source_xsa = $SourceXsa
        source_xsa_sha256 = (Get-FileHash -LiteralPath $SourceXsa -Algorithm SHA256).Hash
        candidate_root = $CandidateRoot
        vitis_workspace = $VitisWorkspace
        fft_control_base = '0x9C440000'
        fft_bank0_base = '0x9D000000'
        fft_bank1_base = '0x9D010000'
        application_mode = $ApplicationMode
        compiler_symbol = $compilerSymbol
        pl_fft_single_shot = ($ApplicationMode -eq 'SingleShot')
        pl_fft_periodic_monitor = ($ApplicationMode -eq 'PeriodicMonitor')
        pl_fft_lab_uart = ($ApplicationMode -eq 'LabUart')
        pl_fft_ethernet = ($ApplicationMode -eq 'Ethernet')
        tracked_source_cleanliness_checked = $true
    }
    if ($DryRun) {
        $description | ConvertTo-Json -Depth 4
        return
    }

    $untrackedInputs = @(
        & git -C $WorkspaceRoot ls-files --others --exclude-standard -- 'Vitis/workspace/ad9364app/src'
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot inspect untracked Candidate application inputs.'
    }
    if ($untrackedInputs.Count -ne 0) {
        throw "Candidate builds reject untracked application source inputs.`r`n$($untrackedInputs -join "`r`n")"
    }
    $legacyVitisDeepSuffix = '\fmcomms2_axu4ev_fft_hw\psu_cortexa53_0\standalone_domain\bsp\psu_cortexa53_0\libsrc\standalone_v7_2\src\arm\ARMv8\64bit\platform\versal\armclang\translation_table.S'
    $legacyVitisDeepPath = $VitisWorkspace.TrimEnd('\') + $legacyVitisDeepSuffix
    if ($legacyVitisDeepPath.Length -ge 260) {
        throw "VitisWorkspace path is too long for Vitis 2020.1 BSP generation ($($legacyVitisDeepPath.Length) characters at the deepest known output): $VitisWorkspace"
    }
    $sourceCommit = (& git -C $WorkspaceRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot determine the Candidate source commit.'
    }

    $hardwareDir = Join-Path $CandidateRoot 'hardware'
    New-Item -ItemType Directory -Path $hardwareDir -Force | Out-Null
    $candidateXsa = Join-Path $hardwareDir 'system_top.xsa'
    $candidateBitstream = Join-Path $hardwareDir 'system_top.bit'
    Copy-Item -LiteralPath $SourceXsa -Destination $candidateXsa -Force

    $bitInput = $bitEntry.Open()
    $bitOutput = [IO.File]::Create($candidateBitstream)
    try {
        $bitInput.CopyTo($bitOutput)
    }
    finally {
        $bitOutput.Dispose()
        $bitInput.Dispose()
    }
}
finally {
    $archive.Dispose()
}

& $xsct $buildTcl $WorkspaceRoot $candidateXsa $VitisWorkspace $AllowedVitisWorkspaceRoot $compilerSymbol
if ($LASTEXITCODE -ne 0) {
    throw "Candidate Vitis build failed with exit code $LASTEXITCODE."
}

$platformName = 'fmcomms2_axu4ev_fft_hw'
$generated = [ordered]@{
    application = Join-Path $VitisWorkspace 'ad9364app\Release\ad9364app.elf'
    bitstream = Join-Path $VitisWorkspace 'ad9364app\_ide\bitstream\system_top.bit'
    pmufw = if ($usesTrustedSingleShotReference) {
        $singleShotReferenceArtifacts['pmufw'].Path
    }
    else {
        $referencePmufw[0]
    }
    psu_init = Join-Path $VitisWorkspace 'ad9364app\_ide\psinit\psu_init.tcl'
    xsa = $candidateXsa
}
foreach ($entry in $generated.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Candidate Vitis build is missing '$($entry.Key)': $($entry.Value)"
    }
}
if ((Get-FileHash -LiteralPath $generated.bitstream -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $candidateBitstream -Algorithm SHA256).Hash) {
    throw 'Candidate Vitis bitstream does not match the bitstream embedded in the Candidate XSA.'
}
if ($usesTrustedSingleShotReference) {
    foreach ($artifactName in @('bitstream', 'pmufw', 'psu_init', 'xsa')) {
        $generatedHash = (Get-FileHash -LiteralPath $generated[$artifactName] -Algorithm SHA256).Hash
        $referenceHash = $singleShotReferenceArtifacts[$artifactName].Sha256
        if ($generatedHash -ne $referenceHash) {
            throw "$ApplicationMode Candidate $artifactName must be byte-identical to the board-verified fft-single-shot-v1 reference."
        }
    }
}

$destinations = [ordered]@{
    application = 'applications/ad9364app.elf'
    bitstream = 'hardware/system_top.bit'
    pmufw = 'firmware/pmufw.elf'
    psu_init = 'hardware/psu_init.tcl'
    xsa = 'hardware/system_top.xsa'
}
foreach ($name in @('application', 'pmufw', 'psu_init')) {
    $destination = Join-Path $CandidateRoot ($destinations[$name] -replace '/', '\')
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath $generated[$name] -Destination $destination -Force
}

$manifest = New-Axu4evReleaseManifest `
    -ReleaseRoot $CandidateRoot `
    -Metadata @{
        release_id = Split-Path $CandidateRoot -Leaf
        created_at = (Get-Date).ToString('o')
        source_commit = $sourceCommit
        board_verified = $false
        uart_markers = $uartMarkers
    } `
    -Artifacts $destinations
$manifest | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $CandidateRoot 'manifest.json') -Encoding UTF8

Write-Output "PASS: Candidate bundle created at $CandidateRoot"
$description | ConvertTo-Json -Depth 4
