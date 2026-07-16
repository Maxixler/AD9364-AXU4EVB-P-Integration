[CmdletBinding()]
param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

function ConvertTo-TclListElement {
    param([Parameter(Mandatory = $true)][string]$Value)

    $encoded = New-Object System.Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        $text = [string]$character
        switch ($text) {
            ' '  { [void]$encoded.Append('\ '); continue }
            "`t" { [void]$encoded.Append('\t'); continue }
            "`r" { [void]$encoded.Append('\r'); continue }
            "`n" { [void]$encoded.Append('\n'); continue }
            '\'  { [void]$encoded.Append('\\'); continue }
            '{'  { [void]$encoded.Append('\{'); continue }
            '}'  { [void]$encoded.Append('\}'); continue }
            '['  { [void]$encoded.Append('\['); continue }
            ']'  { [void]$encoded.Append('\]'); continue }
            '$'  { [void]$encoded.Append('\$'); continue }
            ';'  { [void]$encoded.Append('\;'); continue }
            '"'  { [void]$encoded.Append('\"'); continue }
            '#'  { [void]$encoded.Append('\#'); continue }
            default { [void]$encoded.Append($text) }
        }
    }
    return $encoded.ToString()
}

$testMode = $env:TASK5_WRAPPER_TEST_MODE -eq '1'
if ($testMode -and $null -ne $env:TASK5_TCL_ENCODE_ONLY) {
    Write-Output (ConvertTo-TclListElement -Value $env:TASK5_TCL_ENCODE_ONLY)
    exit 0
}

if (-not ('Task5ProcessSnapshot' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class Task5ProcessRecord
{
    public int ProcessId { get; set; }
    public int ParentProcessId { get; set; }
    public string Name { get; set; }
    public DateTime CreationDate { get; set; }
}

public static class Task5ProcessSnapshot
{
    private const uint TH32CS_SNAPPROCESS = 0x00000002;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private static readonly IntPtr InvalidHandle = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32
    {
        public uint dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExeFile;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32FirstW(IntPtr snapshot, ref PROCESSENTRY32 entry);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32NextW(IntPtr snapshot, ref PROCESSENTRY32 entry);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(IntPtr process, out long creation,
        out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private static DateTime GetCreationUtc(uint processId)
    {
        IntPtr process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
        if (process == IntPtr.Zero) return DateTime.MinValue;
        try
        {
            long creation, exit, kernel, user;
            if (!GetProcessTimes(process, out creation, out exit, out kernel, out user))
                return DateTime.MinValue;
            return DateTime.FromFileTimeUtc(creation);
        }
        finally { CloseHandle(process); }
    }

    public static Task5ProcessRecord[] GetProcesses()
    {
        var records = new List<Task5ProcessRecord>();
        IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == InvalidHandle)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            var entry = new PROCESSENTRY32();
            entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
            if (!Process32FirstW(snapshot, ref entry))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            do
            {
                DateTime creation = GetCreationUtc(entry.th32ProcessID);
                if (creation != DateTime.MinValue)
                {
                    records.Add(new Task5ProcessRecord {
                        ProcessId = (int)entry.th32ProcessID,
                        ParentProcessId = (int)entry.th32ParentProcessID,
                        Name = entry.szExeFile,
                        CreationDate = creation
                    });
                }
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
            } while (Process32NextW(snapshot, ref entry));
        }
        finally { CloseHandle(snapshot); }
        return records.ToArray();
    }
}
'@
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')

$drive = 'P:'
$tempBaseInput = if ($testMode -and $env:TASK5_TEMP_ROOT) {
    $env:TASK5_TEMP_ROOT
}
else {
    [IO.Path]::GetTempPath()
}
$tempRoot = [IO.Path]::GetFullPath($tempBaseInput).TrimEnd('\')
$buildLeaf = "t5-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$buildRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot $buildLeaf))
if ([IO.Path]::GetDirectoryName($buildRoot) -ne $tempRoot -or
    [IO.Path]::GetFileName($buildRoot) -ne $buildLeaf -or
    -not $buildLeaf.StartsWith('t5-', [StringComparison]::Ordinal)) {
    throw "Unsafe temporary build path: $buildRoot"
}
if ($buildRoot.Length -gt 80) {
    throw "Vitis temporary build path exceeds the verified 80-character bound: $buildRoot"
}

$platformXpfm = Join-Path $WorkspaceRoot `
    'Vitis\workspace\fmcomms2_axu4ev_hw\export\fmcomms2_axu4ev_hw\fmcomms2_axu4ev_hw.xpfm'
$sourceDirectory = Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\src'
$trackedBuildScript = Join-Path $WorkspaceRoot 'PROJECT\tests\Build-Axu4evAd9364App.tcl'
$defaultXsct = 'C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
$xsct = if ($testMode -and $env:TASK5_XSCT_PATH) { $env:TASK5_XSCT_PATH } else { $defaultXsct }
$nmCandidates = @(
    'C:\Xilinx\Vitis\2020.1\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-nm.exe',
    'C:\Xilinx\Vitis\2020.1\gnu\aarch64\nt64\aarch64-none\bin\aarch64-none-elf-nm.exe'
)
$nm = if ($testMode -and $env:TASK5_NM_PATH) {
    $env:TASK5_NM_PATH
}
else {
    @($nmCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }) | Select-Object -First 1
}
$timeoutSeconds = if ($testMode -and $env:TASK5_TIMEOUT_SECONDS) {
    [int]$env:TASK5_TIMEOUT_SECONDS
}
else {
    900
}
if ($timeoutSeconds -lt 1 -or $timeoutSeconds -gt 3600) {
    throw "Invalid build timeout: $timeoutSeconds seconds"
}

$buildScript = Join-Path $buildRoot 'bootstrap.tcl'
$launcherScript = Join-Path $buildRoot 'launch-xsct.cmd'
$temporaryElf = Join-Path $buildRoot 'Vitis\workspace\ad9364app\Release\ad9364app.elf'
$elf = if ($testMode -and $env:TASK5_OUTPUT_ELF) {
    [IO.Path]::GetFullPath($env:TASK5_OUTPUT_ELF)
}
else {
    Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\Release\ad9364app.elf'
}
$auditPath = if ($testMode -and $env:TASK5_AUDIT_PATH) {
    [IO.Path]::GetFullPath($env:TASK5_AUDIT_PATH)
}
else {
    $null
}
$cleanupFailureStages = @()
if ($testMode -and $env:TASK5_CLEANUP_FAILURES) {
    $cleanupFailureStages = @($env:TASK5_CLEANUP_FAILURES -split ',' |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$requiredSymbols = @(
    'wifi_rf_test_run',
    'wifi_rf_prepare_rx_only',
    'wifi_rf_capture_channel',
    'wifi_rf_analyze_block'
)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ascii = [Text.Encoding]::ASCII
$driveMapped = $false
$launcher = $null
$ownedProcessIds = New-Object 'System.Collections.Generic.HashSet[int]'
$ownedProcessBirth = New-Object 'System.Collections.Generic.Dictionary[int,datetime]'
$processesStopped = $false
$operationError = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]
$originalTestElfEnvironment = $env:TASK5_WRAPPER_TEMP_ELF

function Write-Audit {
    param([string]$Message)
    if ($auditPath) {
        [IO.File]::AppendAllText($auditPath, "$Message`r`n", $utf8)
    }
}

function Get-BuildProcessRecords {
    return @([Task5ProcessSnapshot]::GetProcesses())
}

function Get-RecordCreationUtc {
    param([Parameter(Mandatory = $true)]$Record)
    return ([DateTime]$Record.CreationDate).ToUniversalTime()
}

function Test-OwnedProcessRecord {
    param([Parameter(Mandatory = $true)]$Record)

    $processId = [int]$Record.ProcessId
    if (-not $ownedProcessIds.Contains($processId) -or
        -not $ownedProcessBirth.ContainsKey($processId)) {
        return $false
    }
    $actualBirth = Get-RecordCreationUtc -Record $Record
    return [Math]::Abs(($actualBirth - $ownedProcessBirth[$processId]).TotalSeconds) -lt 1.0
}

function Update-OwnedBuildProcesses {
    param([object[]]$Records)

    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($record in $Records) {
            $processId = [int]$record.ProcessId
            $parentId = [int]$record.ParentProcessId
            $currentParent = @($Records | Where-Object {
                [int]$_.ProcessId -eq $parentId
            })
            if ($currentParent.Count -eq 0 -or
                -not (Test-OwnedProcessRecord -Record $currentParent[0])) {
                continue
            }
            if (-not $ownedProcessIds.Contains($processId) -and
                $ownedProcessIds.Contains($parentId)) {
                [void]$ownedProcessIds.Add($processId)
                $ownedProcessBirth[$processId] = Get-RecordCreationUtc -Record $record
                $changed = $true
            }
        }
    }
}

function Stop-OwnedBuildProcesses {
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $records = @(Get-BuildProcessRecords)
        Update-OwnedBuildProcesses -Records $records
        $liveOwned = @($records | Where-Object { Test-OwnedProcessRecord -Record $_ })
        if ($liveOwned.Count -eq 0) { break }
        foreach ($record in @($liveOwned | Sort-Object ProcessId -Descending)) {
            Stop-Process -Id ([int]$record.ProcessId) -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 250
    }

    $remaining = @(Get-BuildProcessRecords | Where-Object { Test-OwnedProcessRecord -Record $_ })
    if ($remaining.Count -ne 0) {
        throw "Owned Vitis processes did not terminate: $($remaining.ProcessId -join ', ')"
    }
    $script:processesStopped = $true
    Write-Audit 'VERIFY_OWNED_STOPPED'
}

function Invoke-NmSymbolGate {
    param([Parameter(Mandatory = $true)][string]$Path)

    $nmOutput = @(& $nm --defined-only --extern-only $Path 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "AArch64 nm failed for '$Path': $($nmOutput -join [Environment]::NewLine)"
    }
    $joinedOutput = $nmOutput -join "`n"
    foreach ($symbol in $requiredSymbols) {
        if ($joinedOutput -notmatch "(?m)^[0-9A-Fa-f]+\s+T\s+$([regex]::Escape($symbol))\s*$") {
            throw "Release ELF is missing required global text symbol: $symbol"
        }
    }
    Write-Audit "NM_PASS:$Path"
}

function Invoke-CleanupStage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Audit "CLEANUP_BEGIN:$Name"
    try {
        & $Action
        if ($cleanupFailureStages -contains $Name) {
            throw "Injected cleanup failure for $Name"
        }
        Write-Audit "CLEANUP_PASS:$Name"
    }
    catch {
        $cleanupErrors.Add("$Name`: $($_.Exception.Message)")
        Write-Audit "CLEANUP_FAIL:$Name"
    }
}

$bootstrapTemplate = @'
set build_root [lindex [list __BUILD_ROOT_LIST__] 0]
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
    foreach ($path in @($platformXpfm, $trackedBuildScript, $xsct, $nm)) {
        if ([string]::IsNullOrWhiteSpace($path) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing AD9364 build tool/input: $path"
        }
    }
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Missing AD9364 source directory: $sourceDirectory"
    }

    New-Item -ItemType Directory -Path $buildRoot | Out-Null
    if ($auditPath) {
        $auditDirectory = Split-Path -Parent $auditPath
        if ($auditDirectory -and -not (Test-Path -LiteralPath $auditDirectory)) {
            New-Item -ItemType Directory -Path $auditDirectory | Out-Null
        }
        [IO.File]::WriteAllText($auditPath, '', $utf8)
    }

    & subst $drive $WorkspaceRoot
    if ($LASTEXITCODE -ne 0) { throw "Could not map $drive to the workspace." }
    $driveMapped = $true

    $buildRootTcl = ConvertTo-TclListElement -Value $buildRoot.Replace('\', '/')
    $bootstrapText = $bootstrapTemplate.Replace('__BUILD_ROOT_LIST__', $buildRootTcl)
    [IO.File]::WriteAllText($buildScript, $bootstrapText, $utf8)
    $launcherText = "@echo off`r`ncall `"$xsct`" `"$buildScript`"`r`nexit /b %errorlevel%`r`n"
    [IO.File]::WriteAllText($launcherScript, $launcherText, $ascii)

    $env:TASK5_WRAPPER_TEMP_ELF = $temporaryElf
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)
    Write-Audit "DEADLINE_TICKS:$($deadline.Ticks)"
    $launchStartedUtc = [DateTime]::UtcNow
    $launcher = Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/d', '/c', "`"$launcherScript`"") `
        -WindowStyle Hidden -PassThru
    [void]$ownedProcessIds.Add([int]$launcher.Id)
    $ownedProcessBirth[[int]$launcher.Id] = $launcher.StartTime.ToUniversalTime()
    Write-Audit "LAUNCHER_TICKS:$($launchStartedUtc.Ticks):PID=$($launcher.Id)"

    $stableElfSignature = $null
    $stableElfSince = $null
    while ($true) {
        $records = @(Get-BuildProcessRecords)
        Update-OwnedBuildProcesses -Records $records
        $liveDescendants = @($records | Where-Object {
            (Test-OwnedProcessRecord -Record $_) -and
            [int]$_.ProcessId -ne [int]$launcher.Id
        })
        $launcherAlive = @($records | Where-Object {
            [int]$_.ProcessId -eq [int]$launcher.Id -and
            (Test-OwnedProcessRecord -Record $_)
        }).Count -gt 0
        if (-not $launcherAlive -and $liveDescendants.Count -eq 0) { break }
        $loopCandidate = Get-Item -LiteralPath $temporaryElf -ErrorAction SilentlyContinue
        $freshLoopElf = $null -ne $loopCandidate -and
            $loopCandidate.Length -gt 0 -and
            $loopCandidate.LastWriteTimeUtc -ge $launchStartedUtc.AddSeconds(-1)
        if ($freshLoopElf) {
            $signature = "$($loopCandidate.Length):$($loopCandidate.LastWriteTimeUtc.Ticks)"
            if ($signature -ne $stableElfSignature) {
                $stableElfSignature = $signature
                $stableElfSince = [DateTime]::UtcNow
            }
            elseif ([DateTime]::UtcNow -ge $stableElfSince.AddSeconds(5)) {
                Write-Audit 'ELF_STABLE_BEFORE_PROCESS_CLEANUP'
                break
            }
        }
        else {
            $stableElfSignature = $null
            $stableElfSince = $null
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            $liveDescription = @($records | Where-Object {
                Test-OwnedProcessRecord -Record $_
            } | ForEach-Object { "$($_.ProcessId):$($_.Name)" }) -join ', '
            throw "Timed out after $timeoutSeconds seconds waiting for the owned Vitis process tree: $liveDescription"
        }
        Start-Sleep -Milliseconds 200
    }
    $candidate = Get-Item -LiteralPath $temporaryElf -ErrorAction SilentlyContinue
    if ($null -eq $candidate -or $candidate.Length -le 0) {
        throw 'Owned XSCT build did not produce the exact isolated Release ELF.'
    }
    if ($candidate.LastWriteTimeUtc -lt $launchStartedUtc.AddSeconds(-1)) {
        throw 'Owned XSCT build produced a stale isolated Release ELF.'
    }
    Invoke-NmSymbolGate -Path $temporaryElf

    $releaseDirectory = Split-Path -Parent $elf
    if (-not (Test-Path -LiteralPath $releaseDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $releaseDirectory | Out-Null
    }
    Copy-Item -LiteralPath $temporaryElf -Destination $elf -Force
    if ((Get-FileHash -LiteralPath $temporaryElf -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $elf -Algorithm SHA256).Hash) {
        throw 'Copied Release ELF does not match the verified isolated ELF.'
    }
}
catch {
    $operationError = $_
}
finally {
    Invoke-CleanupStage -Name 'ProcessShutdown' -Action {
        Stop-OwnedBuildProcesses
    }
    Invoke-CleanupStage -Name 'SubstUnmap' -Action {
        if (-not $processesStopped) { throw 'Owned processes were not verified stopped.' }
        if ($driveMapped) {
            & subst $drive /D 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Could not unmap $drive." }
            $script:driveMapped = $false
        }
        $mapping = @(& subst 2>$null | Where-Object { $_ -match '^P:\\:' })
        if ($mapping.Count -ne 0) { throw "$drive remains mapped." }
        Write-Audit 'UNMAP_VERIFIED'
    }
    Invoke-CleanupStage -Name 'TempDelete' -Action {
        if (-not $processesStopped) { throw 'Owned processes were not verified stopped.' }
        $resolvedBuildRoot = [IO.Path]::GetFullPath($buildRoot)
        if ([IO.Path]::GetDirectoryName($resolvedBuildRoot) -ne $tempRoot -or
            [IO.Path]::GetFileName($resolvedBuildRoot) -ne $buildLeaf) {
            throw "Refusing to delete unsafe temporary path: $resolvedBuildRoot"
        }
        if (Test-Path -LiteralPath $resolvedBuildRoot) {
            Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $resolvedBuildRoot) {
            throw "Temporary build path still exists: $resolvedBuildRoot"
        }
        Write-Audit 'DELETE_VERIFIED'
    }
    if ($null -eq $originalTestElfEnvironment) {
        Remove-Item Env:TASK5_WRAPPER_TEMP_ELF -ErrorAction SilentlyContinue
    }
    else {
        $env:TASK5_WRAPPER_TEMP_ELF = $originalTestElfEnvironment
    }
    if ($launcher) { $launcher.Dispose() }
}

$failures = New-Object System.Collections.Generic.List[string]
if ($operationError) { $failures.Add("Build: $($operationError.Exception.Message)") }
foreach ($cleanupError in $cleanupErrors) { $failures.Add("Cleanup: $cleanupError") }
if ($failures.Count -ne 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Output "PASS: AD9364 application generated: $elf"
