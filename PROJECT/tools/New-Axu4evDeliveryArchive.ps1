[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'FPGA-Profen-Teslim'),
    [string]$ArchiveName = 'FPGA-Profen_AXU4EV_AD9364_Teslim_2026-08-03.rar'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$rar = 'C:\Program Files\WinRAR\Rar.exe'

if (-not (Test-Path -LiteralPath $rar)) {
    throw "WinRAR command-line tool not found: $rar"
}

$status = & git -C $repoRoot status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read Git status.'
}
if ($status) {
    throw 'Delivery archive requires a clean Git worktree. Commit or stash changes first.'
}

$branch = (& git -C $repoRoot branch --show-current).Trim()
$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$remote = (& git -C $repoRoot remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve Git branch, commit, or origin.'
}

$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$packageName = [System.IO.Path]::GetFileNameWithoutExtension($ArchiveName)
$stageRoot = Join-Path $outputRoot $packageName
$archivePath = Join-Path $outputRoot $ArchiveName
$archiveHashPath = "$archivePath.sha256"

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
foreach ($path in @($stageRoot, $archivePath, $archiveHashPath)) {
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite existing delivery output: $path"
    }
}

New-Item -ItemType Directory -Path $stageRoot | Out-Null
$sourceRoot = Join-Path $stageRoot 'KAYNAK'
$historyRoot = Join-Path $stageRoot 'GIT_GECMISI'
New-Item -ItemType Directory -Path $sourceRoot, $historyRoot | Out-Null

$snapshotTar = Join-Path $outputRoot "$packageName.snapshot.tar"
try {
    & git -C $repoRoot archive --format=tar --output=$snapshotTar HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }

    & tar -xf $snapshotTar -C $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Snapshot extraction failed.' }

    $bundlePath = Join-Path $historyRoot 'FPGA-Profen.git.bundle'
    & git -C $repoRoot bundle create $bundlePath --all
    if ($LASTEXITCODE -ne 0) { throw 'Git bundle creation failed.' }

    $manifest = @(
        'FPGA-Profen AXU4EVB-P + AD9364 teslim paketi'
        'Tarih: 2026-08-03'
        "Branch: $branch"
        "Commit: $commit"
        "Origin: $remote"
        'Kaynak: KAYNAK/'
        'Tam Git geçmişi: GIT_GECMISI/FPGA-Profen.git.bundle'
        'Not: Geçici build/cache/log dosyaları teslim paketine dahil edilmemiştir.'
    )
    Set-Content -LiteralPath (Join-Path $stageRoot 'TESLIM_MANIFESTI.txt') -Value $manifest -Encoding UTF8

    $hashLines = Get-ChildItem -LiteralPath $stageRoot -Recurse -File |
        Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash  $relative"
        }
    Set-Content -LiteralPath (Join-Path $stageRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding ASCII

    Push-Location $outputRoot
    try {
        & $rar a -r -m5 -rr3 -idq $archivePath $packageName
        if ($LASTEXITCODE -ne 0) { throw "RAR creation failed with exit code $LASTEXITCODE." }
    }
    finally {
        Pop-Location
    }

    & $rar t -idq $archivePath
    if ($LASTEXITCODE -ne 0) { throw "RAR integrity test failed with exit code $LASTEXITCODE." }

    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $archiveHashPath -Value "$archiveHash  $ArchiveName" -Encoding ASCII

    [pscustomobject]@{
        Archive = $archivePath
        Sha256 = $archiveHash
        Branch = $branch
        Commit = $commit
        SizeBytes = (Get-Item -LiteralPath $archivePath).Length
    }
}
finally {
    if (Test-Path -LiteralPath $snapshotTar) {
        Remove-Item -LiteralPath $snapshotTar -Force
    }
}
