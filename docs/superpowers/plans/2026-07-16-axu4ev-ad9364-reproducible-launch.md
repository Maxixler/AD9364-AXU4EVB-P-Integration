# AXU4EVB-P + AD9364 Reproducible Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a versioned golden-release package and one-click Windows launcher that restores the verified AXU4EVB-P + AD9364 bare-metal system after every PC/board power cycle without manual XSCT commands.

**Architecture:** A small PowerShell module owns manifest parsing, SHA-256 verification, current-release resolution, and immutable release creation. Two `.cmd` entry points call one PowerShell orchestrator in `Golden` or `Workspace` mode; the orchestrator validates inputs, exports exact artifact paths, creates a dated log, and invokes one shared XSCT Tcl program. Golden artifacts are versioned and immutable, while workspace artifacts remain candidates until an explicit promotion and current-release selection.

**Tech Stack:** Windows PowerShell 5.1, Tcl/XSCT from Xilinx Vitis 2020.1, JSON manifests, SHA-256, Git, existing AXU4EV project scripts.

## Global Constraints

- Target hardware is AXU4EVB-P (`xczu4ev-sfvc784-1-i`) with AD9364 over FMC, JTAG, and PS_UART.
- Tool paths are `C:\Xilinx\Vitis\2020.1\bin\xsct.bat`, `C:\Xilinx\Vitis\2020.1\bin\vitis.bat`, and `C:\Xilinx\Vivado\2020.1\bin\vivado.bat`.
- Golden launch must not use the stale FSBL; the verified order is PMUFW → FPGA → A53 reset → `psu_init` → PS-PL isolation removal → PS-PL reset → DDR test → application.
- Golden artifacts are immutable. Promotion creates a new release directory and never overwrites an existing release.
- `CURRENT` changes only through a separate explicit selection command.
- Release launch stops before JTAG programming if any artifact path, byte length, or SHA-256 differs from the manifest.
- Application download stops if DDR scratch write/read verification fails.
- UART remains owned by PuTTY or another terminal; version 1 does not open or capture the COM port.
- Runtime logs are excluded from Git.
- Existing unrelated user changes and the 1081 pre-existing staged paths must remain untouched. Every commit uses explicit pathspecs.

---

## File Structure

**Create:**

- `PROJECT/tools/Axu4evRelease.psm1` — manifest, hash, release resolution, and immutable copy functions.
- `PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1` — Golden/Workspace preflight, logging, and XSCT invocation.
- `PROJECT/tools/Promote-Axu4evAd9364Release.ps1` — copy verified workspace artifacts into a new release.
- `PROJECT/tools/Set-Axu4evAd9364CurrentRelease.ps1` — explicitly update `CURRENT` after board validation.
- `PROJECT/tools/Start-Axu4evAd9364Golden.cmd` — double-click Golden entry point.
- `PROJECT/tools/Start-Axu4evAd9364Workspace.cmd` — double-click Workspace entry point.
- `PROJECT/tests/Test-Axu4evRelease.ps1` — dependency-free PowerShell release/preflight tests.
- `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1` — wrapper and orchestrator static/dry-run tests.
- `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/**` — verified artifact snapshot, manifest, and README.
- `PROJECT/releases/axu4ev-ad9364/CURRENT` — selected release id.
- `PROJECT/logs/jtag/.gitignore` — retain directory while excluding generated logs.

**Modify:**

- `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl` — consume explicit artifact environment variables and enforce DDR verification.
- `PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1` — assert environment contract and verified ordering.
- `PROJECT/tests/Test-Axu4evHandoffArtifacts.ps1` — keep workspace candidate verification aligned with release inputs.
- `PROJECT/implementation_plan.md` — record golden/workspace operating procedure.
- `PROJECT/project_situation_report.md` — record current release and acceptance result.
- `chat_report.md` — record implementation and reboot validation.

---

### Task 1: Release Manifest and Integrity Module

**Files:**

- Create: `PROJECT/tools/Axu4evRelease.psm1`
- Create: `PROJECT/tests/Test-Axu4evRelease.ps1`

**Interfaces:**

- Produces: `Resolve-Axu4evCurrentRelease([string]$ReleasesRoot) -> DirectoryInfo`
- Produces: `Read-Axu4evReleaseManifest([string]$ReleaseRoot) -> PSCustomObject`
- Produces: `Test-Axu4evReleaseArtifacts([string]$ReleaseRoot, [object]$Manifest) -> PSCustomObject[]`
- Produces: `New-Axu4evReleaseManifest([string]$ReleaseRoot, [hashtable]$Metadata, [hashtable]$Artifacts) -> PSCustomObject`

- [ ] **Step 1: Write the failing integrity test**

Create `PROJECT/tests/Test-Axu4evRelease.ps1` with temporary files, one valid manifest, and one corrupted file assertion:

```powershell
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\tools\Axu4evRelease.psm1'
if (-not (Test-Path -LiteralPath $module)) { throw "Missing module: $module" }
Import-Module $module -Force

$temp = Join-Path ([IO.Path]::GetTempPath()) ("axu4ev-release-" + [guid]::NewGuid())
try {
    $release = Join-Path $temp 'releases\r1'
    New-Item -ItemType Directory -Path (Join-Path $release 'hardware') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $release 'hardware\system_top.bit') -Value 'verified-bit' -NoNewline
    $file = Get-Item -LiteralPath (Join-Path $release 'hardware\system_top.bit')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    @{ release_id='r1'; artifacts=@(@{name='bitstream';path='hardware/system_top.bit';length=$file.Length;sha256=$hash}) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $release 'manifest.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $temp 'releases\CURRENT') -Value 'r1' -NoNewline

    $resolved = Resolve-Axu4evCurrentRelease (Join-Path $temp 'releases')
    if ($resolved.Name -ne 'r1') { throw 'CURRENT did not resolve r1.' }
    $manifest = Read-Axu4evReleaseManifest $release
    $verified = @(Test-Axu4evReleaseArtifacts $release $manifest)
    if ($verified.Count -ne 1 -or $verified[0].Sha256 -ne $hash) { throw 'Valid artifact was not verified.' }

    Set-Content -LiteralPath $file.FullName -Value 'changed--bit' -NoNewline
    try { Test-Axu4evReleaseArtifacts $release $manifest | Out-Null; throw 'Corruption was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw } }
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'PASS: AXU4EV release resolution and integrity checks reject corruption.'
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evRelease.ps1
```

Expected: FAIL with `Missing module: ...Axu4evRelease.psm1`.

- [ ] **Step 3: Implement the minimal module**

Create `PROJECT/tools/Axu4evRelease.psm1` with strict relative-path validation, length/hash checks, and JSON creation:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Axu4evCurrentRelease {
    param([Parameter(Mandatory)][string]$ReleasesRoot)
    $current = Join-Path $ReleasesRoot 'CURRENT'
    if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { throw "Missing CURRENT file: $current" }
    $id = (Get-Content -LiteralPath $current -Raw).Trim()
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') { throw "Invalid release id in CURRENT: $id" }
    $release = Get-Item -LiteralPath (Join-Path $ReleasesRoot $id) -ErrorAction Stop
    if (-not $release.PSIsContainer) { throw "CURRENT is not a release directory: $($release.FullName)" }
    return $release
}

function Read-Axu4evReleaseManifest {
    param([Parameter(Mandatory)][string]$ReleaseRoot)
    $path = Join-Path $ReleaseRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing manifest: $path" }
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $manifest.release_id -or @($manifest.artifacts).Count -eq 0) { throw "Invalid manifest: $path" }
    return $manifest
}

function Test-Axu4evReleaseArtifacts {
    param([Parameter(Mandatory)][string]$ReleaseRoot, [Parameter(Mandatory)]$Manifest)
    $root = (Resolve-Path -LiteralPath $ReleaseRoot).Path
    foreach ($artifact in @($Manifest.artifacts)) {
        $relative = [string]$artifact.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe artifact path: $relative" }
        $path = Join-Path $root ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing artifact '$($artifact.name)': $path" }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [int64]$artifact.length) { throw "Length mismatch for '$($artifact.name)': $($item.Length) != $($artifact.length)" }
        $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($sha -ne ([string]$artifact.sha256).ToUpperInvariant()) { throw "SHA-256 mismatch for '$($artifact.name)': $sha" }
        [pscustomobject]@{ Name=$artifact.name; Path=$item.FullName; Length=$item.Length; Sha256=$sha }
    }
}

function New-Axu4evReleaseManifest {
    param([Parameter(Mandatory)][string]$ReleaseRoot, [Parameter(Mandatory)][hashtable]$Metadata, [Parameter(Mandatory)][hashtable]$Artifacts)
    $entries = foreach ($name in ($Artifacts.Keys | Sort-Object)) {
        $relative = [string]$Artifacts[$name]
        $path = Join-Path $ReleaseRoot ($relative -replace '/', '\')
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        [ordered]@{ name=$name; path=$relative; length=$item.Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    }
    [pscustomobject][ordered]@{
        schema_version = 1
        release_id = $Metadata.release_id
        created_at = $Metadata.created_at
        target_board = 'AXU4EVB-P'
        fpga_part = 'xczu4ev-sfvc784-1-i'
        rf_device = 'AD9364'
        tool_version = '2020.1'
        source_commit = $Metadata.source_commit
        board_verified = [bool]$Metadata.board_verified
        uart_markers = @($Metadata.uart_markers)
        artifacts = @($entries)
    }
}

Export-ModuleMember -Function Resolve-Axu4evCurrentRelease,Read-Axu4evReleaseManifest,Test-Axu4evReleaseArtifacts,New-Axu4evReleaseManifest
```

- [ ] **Step 4: Run the test and verify GREEN**

Run the Step 2 command. Expected: `PASS: AXU4EV release resolution and integrity checks reject corruption.`

- [ ] **Step 5: Commit only the task files**

```powershell
git add -- PROJECT/tools/Axu4evRelease.psm1 PROJECT/tests/Test-Axu4evRelease.ps1
git commit --only -m "feat: verify AXU4EV release artifacts" -- PROJECT/tools/Axu4evRelease.psm1 PROJECT/tests/Test-Axu4evRelease.ps1
```

---

### Task 2: Immutable Promotion and Explicit Current Selection

**Files:**

- Create: `PROJECT/tools/Promote-Axu4evAd9364Release.ps1`
- Create: `PROJECT/tools/Set-Axu4evAd9364CurrentRelease.ps1`
- Modify: `PROJECT/tests/Test-Axu4evRelease.ps1`

**Interfaces:**

- Consumes the four functions exported by `Axu4evRelease.psm1`.
- Produces command `Promote-Axu4evAd9364Release.ps1 -ReleaseId <id> -WorkspaceRoot <root> [-BoardVerified]`.
- Produces command `Set-Axu4evAd9364CurrentRelease.ps1 -ReleaseId <id> -WorkspaceRoot <root>`.

- [ ] **Step 1: Add failing promotion assertions**

Extend `Test-Axu4evRelease.ps1` with a synthetic workspace containing the five required files. Invoke promotion twice with the same id and assert the second call fails with `Release already exists`; assert `CURRENT` remains unchanged until the selector runs.

```powershell
$promote = Join-Path $PSScriptRoot '..\tools\Promote-Axu4evAd9364Release.ps1'
$select = Join-Path $PSScriptRoot '..\tools\Set-Axu4evAd9364CurrentRelease.ps1'
if (-not (Test-Path $promote)) { throw "Missing promotion tool: $promote" }
if (-not (Test-Path $select)) { throw "Missing current-release tool: $select" }

$promotionRoot = Join-Path ([IO.Path]::GetTempPath()) ("axu4ev-promotion-" + [guid]::NewGuid())
try {
    $fakeFiles = @(
        'Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit',
        'Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.sdk\system_top.xsa',
        'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl',
        'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf',
        'Vitis\workspace\ad9364app\Debug\ad9364app.elf'
    )
    foreach ($relative in $fakeFiles) {
        $path = Join-Path $promotionRoot $relative
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $relative -NoNewline
    }
    & $promote -ReleaseId r2 -WorkspaceRoot $promotionRoot -BoardVerified
    if (Test-Path (Join-Path $promotionRoot 'PROJECT\releases\axu4ev-ad9364\CURRENT')) { throw 'Promotion changed CURRENT.' }
    try { & $promote -ReleaseId r2 -WorkspaceRoot $promotionRoot; throw 'Duplicate release was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'Release already exists') { throw } }
    & $select -ReleaseId r2 -WorkspaceRoot $promotionRoot
    $current = (Get-Content (Join-Path $promotionRoot 'PROJECT\releases\axu4ev-ad9364\CURRENT') -Raw).Trim()
    if ($current -ne 'r2') { throw 'Explicit selection did not update CURRENT.' }
}
finally { Remove-Item -LiteralPath $promotionRoot -Recurse -Force -ErrorAction SilentlyContinue }
```

- [ ] **Step 2: Run the test and verify RED**

Run Task 1 Step 2 command. Expected: FAIL with `Missing promotion tool`.

- [ ] **Step 3: Implement promotion with fixed source mapping**

`Promote-Axu4evAd9364Release.ps1` must map these source files:

```powershell
$sources = [ordered]@{
    bitstream = 'Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit'
    xsa = 'Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.sdk\system_top.xsa'
    psu_init = 'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl'
    pmufw = 'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf'
    application = 'Vitis\workspace\ad9364app\Debug\ad9364app.elf'
}
$destinations = [ordered]@{
    bitstream='hardware/system_top.bit'; xsa='hardware/system_top.xsa'; psu_init='hardware/psu_init.tcl'
    pmufw='firmware/pmufw.elf'; application='applications/ad9364app.elf'
}
```

The script must create a temporary sibling directory, copy with `Copy-Item -LiteralPath`, generate `manifest.json` using `New-Axu4evReleaseManifest`, verify it using `Test-Axu4evReleaseArtifacts`, write `README.md`, then atomically rename the temporary directory to the release id. It must throw before copying if the final release directory exists.

`Set-Axu4evAd9364CurrentRelease.ps1` must resolve and verify the selected release before writing its id to `CURRENT` with `Set-Content -NoNewline`.

Use this complete promotion body after its parameter block:

```powershell
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseId,[string]$WorkspaceRoot,[switch]$BoardVerified)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
Import-Module (Join-Path $PSScriptRoot 'Axu4evRelease.psm1') -Force
if ($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') { throw "Invalid release id: $ReleaseId" }
$releaseBase=Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$final=Join-Path $releaseBase $ReleaseId
if (Test-Path -LiteralPath $final) { throw "Release already exists: $final" }
$temp=Join-Path $releaseBase ('.creating-' + [guid]::NewGuid())
$sources=[ordered]@{
 bitstream='Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit'
 xsa='Related-Docs\hdl-main\projects\fmcomms2\axu4ev\fmcomms2_axu4ev.sdk\system_top.xsa'
 psu_init='Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl'
 pmufw='Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf'
 application='Vitis\workspace\ad9364app\Debug\ad9364app.elf'
}
$destinations=[ordered]@{
 bitstream='hardware/system_top.bit'; xsa='hardware/system_top.xsa'; psu_init='hardware/psu_init.tcl'
 pmufw='firmware/pmufw.elf'; application='applications/ad9364app.elf'
}
try {
 New-Item -ItemType Directory -Path $temp -Force | Out-Null
 foreach($name in $sources.Keys){
  $source=Join-Path $WorkspaceRoot $sources[$name]
  if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing source artifact '$name': $source"}
  $destination=Join-Path $temp ($destinations[$name] -replace '/','\')
  New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination
 }
 $commit=(git -c safe.directory=($WorkspaceRoot -replace '\\','/') -C $WorkspaceRoot rev-parse HEAD).Trim()
 $metadata=@{
  release_id=$ReleaseId; created_at=(Get-Date).ToString('o'); source_commit=$commit
  board_verified=[bool]$BoardVerified
  uart_markers=@('AD936x Rev 2 successfully initialized','DMA_EXAMPLE:','Done.')
 }
 $manifest=New-Axu4evReleaseManifest -ReleaseRoot $temp -Metadata $metadata -Artifacts $destinations
 $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temp 'manifest.json') -Encoding UTF8
 Test-Axu4evReleaseArtifacts $temp $manifest | Out-Null
 "# $ReleaseId`r`n`r`nImmutable AXU4EVB-P + AD9364 release. See manifest.json for hashes.`r`n" |
  Set-Content -LiteralPath (Join-Path $temp 'README.md') -Encoding UTF8
 Move-Item -LiteralPath $temp -Destination $final
 Write-Output "PASS: Created immutable release $ReleaseId"
}
catch { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue; throw }
```

Use this complete selector:

```powershell
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseId,[string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
Import-Module (Join-Path $PSScriptRoot 'Axu4evRelease.psm1') -Force
$base=Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364'
$release=Join-Path $base $ReleaseId
$manifest=Read-Axu4evReleaseManifest $release
Test-Axu4evReleaseArtifacts $release $manifest | Out-Null
New-Item -ItemType Directory -Path $base -Force | Out-Null
Set-Content -LiteralPath (Join-Path $base 'CURRENT') -Value $ReleaseId -NoNewline
Write-Output "PASS: CURRENT=$ReleaseId"
```

- [ ] **Step 4: Run the test and verify GREEN**

Expected: the release test passes, duplicate promotion is rejected, and explicit selection updates `CURRENT`.

- [ ] **Step 5: Commit only promotion files and test**

```powershell
git add -- PROJECT/tools/Promote-Axu4evAd9364Release.ps1 PROJECT/tools/Set-Axu4evAd9364CurrentRelease.ps1 PROJECT/tests/Test-Axu4evRelease.ps1
git commit --only -m "feat: promote immutable AXU4EV releases" -- PROJECT/tools/Promote-Axu4evAd9364Release.ps1 PROJECT/tools/Set-Axu4evAd9364CurrentRelease.ps1 PROJECT/tests/Test-Axu4evRelease.ps1
```

---

### Task 3: Create and Verify the First Golden Release

**Files:**

- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/hardware/system_top.bit`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/hardware/system_top.xsa`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/hardware/psu_init.tcl`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/firmware/pmufw.elf`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/applications/ad9364app.elf`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/manifest.json`
- Create: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/README.md`
- Create: `PROJECT/releases/axu4ev-ad9364/CURRENT`

**Interfaces:**

- Consumes promotion and selection commands from Task 2.
- Produces the immutable release selected by Golden mode.

- [ ] **Step 1: Run a pre-promotion source hash gate**

Run `PROJECT/tests/Test-Axu4evHandoffArtifacts.ps1` and assert these exact values:

```text
BIT_SHA256=AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4
XSA_SHA256=AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118
APP_ELF_SHA256=320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC
```

- [ ] **Step 2: Promote the verified workspace artifacts**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tools\Promote-Axu4evAd9364Release.ps1 -ReleaseId 2026-07-16-bringup-v1 -WorkspaceRoot (Get-Location).Path -BoardVerified
```

Expected: `PASS: Created immutable release 2026-07-16-bringup-v1` and no `CURRENT` file yet.

- [ ] **Step 3: Select the verified release explicitly**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tools\Set-Axu4evAd9364CurrentRelease.ps1 -ReleaseId 2026-07-16-bringup-v1 -WorkspaceRoot (Get-Location).Path
```

Expected: `PASS: CURRENT=2026-07-16-bringup-v1`.

- [ ] **Step 4: Verify every release hash**

Run Task 1 test plus a direct module call:

```powershell
Import-Module .\PROJECT\tools\Axu4evRelease.psm1 -Force
$root = Resolve-Axu4evCurrentRelease .\PROJECT\releases\axu4ev-ad9364
$manifest = Read-Axu4evReleaseManifest $root.FullName
Test-Axu4evReleaseArtifacts $root.FullName $manifest | Format-Table Name,Length,Sha256
```

Expected hashes are the five values in the approved design specification.

- [ ] **Step 5: Commit the release as one isolated snapshot**

```powershell
git add -- PROJECT/releases/axu4ev-ad9364
git commit --only -m "release: snapshot verified AXU4EV AD9364 bring-up" -- PROJECT/releases/axu4ev-ad9364
```

---

### Task 4: Make the XSCT Program Artifact-Independent and DDR-Gated

**Files:**

- Modify: `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl`
- Modify: `PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1`

**Interfaces:**

- Consumes environment variables `AXU4EV_PMUFW_ELF`, `AXU4EV_BITSTREAM`, `AXU4EV_PSU_INIT_TCL`, `AXU4EV_APP_ELF`.
- Produces XSCT exit code `0` only after the application is started; throws on DDR mismatch.

- [ ] **Step 1: Add failing environment and DDR-order assertions**

Update `Test-Axu4evJtagLaunchScript.ps1` to require all four environment variables, forbid workspace path construction, and require this order:

```powershell
$orderedPhases = @(
    'mwr 0xffca0038 0x1ff', 'dow $pmufw_elf', 'fpga -file $bitstream',
    'rst -processor -clear-registers', 'source $psu_init_tcl', 'psu_init',
    'psu_ps_pl_isolation_removal', 'psu_ps_pl_reset_config',
    'mwr $ddr_test_address $ddr_test_value', 'mrd $ddr_test_address',
    'dow $app_elf', 'configparams force-mem-accesses 0', 'con'
)
```

- [ ] **Step 2: Run the test and verify RED**

Expected: FAIL because the existing script constructs paths from `FPGA_PROFEN_ROOT` and does not enforce DDR comparison.

- [ ] **Step 3: Implement explicit artifact inputs and DDR comparison**

Replace path discovery with:

```tcl
foreach name {AXU4EV_PMUFW_ELF AXU4EV_BITSTREAM AXU4EV_PSU_INIT_TCL AXU4EV_APP_ELF} {
  if {![info exists ::env($name)] || $::env($name) eq ""} { error "Missing environment variable: $name" }
}
set pmufw_elf [string map {\\ /} $::env(AXU4EV_PMUFW_ELF)]
set bitstream [string map {\\ /} $::env(AXU4EV_BITSTREAM)]
set psu_init_tcl [string map {\\ /} $::env(AXU4EV_PSU_INIT_TCL)]
set app_elf [string map {\\ /} $::env(AXU4EV_APP_ELF)]
set ddr_test_address 0x00100000
set ddr_test_value 0xA5A5A5A5
```

After PS-PL reset, write and read the scratch word. Parse the final eight hex digits from `mrd`, compare case-insensitively to `A5A5A5A5`, and `error` before `dow $app_elf` if different.

```tcl
mwr $ddr_test_address $ddr_test_value
set ddr_readback [mrd $ddr_test_address]
if {![regexp -nocase {([0-9a-f]{8})\s*$} $ddr_readback -> ddr_word]} {
  error "Unable to parse DDR readback: $ddr_readback"
}
if {[string toupper $ddr_word] ne "A5A5A5A5"} {
  error "DDR verification failed at $ddr_test_address: $ddr_word"
}
puts "DDR verification passed: $ddr_word"
```

- [ ] **Step 4: Run launch-order and path tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evJtagLaunchScript.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evXsctScriptPaths.ps1
```

Expected: both PASS.

- [ ] **Step 5: Commit Tcl and tests**

```powershell
git add -- PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1 PROJECT/tests/Test-Axu4evXsctScriptPaths.ps1
git commit --only -m "feat: gate AXU4EV launch on verified artifacts and DDR" -- PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1 PROJECT/tests/Test-Axu4evXsctScriptPaths.ps1
```

---

### Task 5: Build the Golden/Workspace PowerShell Orchestrator

**Files:**

- Create: `PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1`
- Create: `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1`

**Interfaces:**

- Produces command `Invoke-Axu4evAd9364Launch.ps1 -Mode Golden|Workspace [-DryRun] [-WorkspaceRoot <root>]`.
- In `-DryRun`, returns a JSON object containing mode, four artifact paths, four hashes, Tcl path, XSCT path, and log path without starting hardware tools.

- [ ] **Step 1: Write failing Golden and Workspace dry-run tests**

`Test-Axu4evLaunchWrappers.ps1` must invoke both modes with `-DryRun`, parse JSON, assert four existing files, assert the Golden bitstream path contains `PROJECT\releases\axu4ev-ad9364`, and assert the Workspace path contains `Vitis\workspace`.

- [ ] **Step 2: Run the wrapper test and verify RED**

Expected: FAIL with `Missing orchestrator`.

- [ ] **Step 3: Implement orchestrator preflight and launch**

The orchestrator must:

```powershell
[CmdletBinding()]
param(
    [ValidateSet('Golden','Workspace')][string]$Mode='Golden',
    [string]$WorkspaceRoot,
    [switch]$DryRun
)
```

Resolve project root from `$PSScriptRoot\..\..`, unless `-WorkspaceRoot` is supplied. Golden mode resolves `CURRENT`, reads the manifest, verifies every artifact, and maps manifest names to paths. Workspace mode runs `Test-Axu4evHandoffArtifacts.ps1`, prefers Release then Debug application ELF, and calculates hashes for the same four launch inputs. Both modes verify `xsct.bat` and Tcl paths, create `PROJECT\logs\jtag\yyyyMMdd-HHmmss-<mode>.log`, and export the four `AXU4EV_*` environment variables only for the child process.

For real launch, execute:

```powershell
& $xsct $launchTcl 2>&1 | Tee-Object -FilePath $logPath
if ($LASTEXITCODE -ne 0) { throw "XSCT launch failed with exit code $LASTEXITCODE. Log: $logPath" }
```

Use `try/finally` to restore any pre-existing `AXU4EV_*` environment values.

Implement the complete orchestrator as follows:

```powershell
[CmdletBinding()]
param(
 [ValidateSet('Golden','Workspace')][string]$Mode='Golden',
 [string]$WorkspaceRoot,
 [switch]$DryRun
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($WorkspaceRoot)){$WorkspaceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path}
$module=Join-Path $PSScriptRoot 'Axu4evRelease.psm1'
$launchTcl=Join-Path $WorkspaceRoot 'PROJECT\tests\Launch-Axu4evAd9364Jtag.tcl'
$xsct='C:\Xilinx\Vitis\2020.1\bin\xsct.bat'
foreach($required in @($module,$launchTcl,$xsct)){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Missing launch dependency: $required"}}
Import-Module $module -Force

$paths=[ordered]@{}
if($Mode -eq 'Golden'){
 $release=Resolve-Axu4evCurrentRelease (Join-Path $WorkspaceRoot 'PROJECT\releases\axu4ev-ad9364')
 $manifest=Read-Axu4evReleaseManifest $release.FullName
 $verified=@(Test-Axu4evReleaseArtifacts $release.FullName $manifest)
 foreach($item in $verified){$paths[$item.Name]=$item.Path}
}
else{
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $WorkspaceRoot 'PROJECT\tests\Test-Axu4evHandoffArtifacts.ps1') -WorkspaceRoot $WorkspaceRoot
 if($LASTEXITCODE -ne 0){throw 'Workspace handoff verification failed.'}
 $app=@('Release','Debug') | ForEach-Object {Join-Path $WorkspaceRoot "Vitis\workspace\ad9364app\$_\ad9364app.elf"} |
  Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
 if(-not $app){throw 'Missing workspace application ELF.'}
 $paths.bitstream=Join-Path $WorkspaceRoot 'Vitis\workspace\ad9364app\_ide\bitstream\system_top.bit'
 $paths.psu_init=Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\hw\psu_init.tcl'
 $paths.pmufw=Join-Path $WorkspaceRoot 'Vitis\workspace\fmcomms2_axu4ev_hw\zynqmp_pmufw\executable.elf'
 $paths.application=$app
}

$requiredNames=@('bitstream','psu_init','pmufw','application')
$artifacts=@(foreach($name in $requiredNames){
 $path=[string]$paths[$name]
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing launch artifact '$name': $path"}
 $item=Get-Item -LiteralPath $path
 [pscustomobject]@{name=$name;path=$item.FullName;length=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash}
})
$logDir=Join-Path $WorkspaceRoot 'PROJECT\logs\jtag'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath=Join-Path $logDir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Mode.ToLowerInvariant() + '.log')
$result=[ordered]@{mode=$Mode;xsct=$xsct;tcl=$launchTcl;log=$logPath;artifacts=$artifacts}
if($DryRun){$result | ConvertTo-Json -Depth 6; return}

$envMap=[ordered]@{
 AXU4EV_PMUFW_ELF=$paths.pmufw
 AXU4EV_BITSTREAM=$paths.bitstream
 AXU4EV_PSU_INIT_TCL=$paths.psu_init
 AXU4EV_APP_ELF=$paths.application
}
$saved=@{}
foreach($name in $envMap.Keys){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process');[Environment]::SetEnvironmentVariable($name,$envMap[$name],'Process')}
try{
 "Mode=$Mode" | Set-Content -LiteralPath $logPath -Encoding UTF8
 $artifacts | Format-Table -AutoSize | Out-String | Add-Content -LiteralPath $logPath -Encoding UTF8
 & $xsct $launchTcl 2>&1 | Tee-Object -FilePath $logPath -Append
 $exitCode=$LASTEXITCODE
 if($exitCode -ne 0){throw "XSCT launch failed with exit code $exitCode. Log: $logPath"}
 Write-Output "PASS: $Mode launch completed. Check PS_UART in PuTTY. Log: $logPath"
}
finally{
 foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
}
```

- [ ] **Step 4: Run dry-run and existing regression tests**

Expected: Golden and Workspace dry-runs pass; release, handoff, launch-order, and path tests also pass.

- [ ] **Step 5: Commit orchestrator and tests**

```powershell
git add -- PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1 PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
git commit --only -m "feat: orchestrate golden and workspace JTAG launch" -- PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1 PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
```

---

### Task 6: Add Double-Click Launchers and Log Exclusion

**Files:**

- Create: `PROJECT/tools/Start-Axu4evAd9364Golden.cmd`
- Create: `PROJECT/tools/Start-Axu4evAd9364Workspace.cmd`
- Create: `PROJECT/logs/jtag/.gitignore`
- Modify: `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1`

**Interfaces:**

- Golden launcher calls orchestrator with `-Mode Golden`.
- Workspace launcher calls orchestrator with `-Mode Workspace`.

- [ ] **Step 1: Add failing launcher-content assertions**

Require each `.cmd` file to derive the project root from `%~dp0`, call `powershell.exe -NoProfile -ExecutionPolicy Bypass`, propagate `%ERRORLEVEL%`, print the log/error result, and `pause` before closing.

- [ ] **Step 2: Run wrapper test and verify RED**

Expected: FAIL with missing Golden launcher.

- [ ] **Step 3: Create the launchers**

Golden launcher content:

```batch
@echo off
setlocal
set "TOOLS_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Golden
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Launch failed with exit code %RC%.
if "%RC%"=="0" echo Launch completed. Check PS_UART in PuTTY.
pause
exit /b %RC%
```

Workspace launcher is identical except `-Mode Workspace`.

Create `PROJECT/logs/jtag/.gitignore`:

```gitignore
*
!.gitignore
```

- [ ] **Step 4: Run wrapper tests**

Expected: PASS for both launcher contracts and `-DryRun` modes.

- [ ] **Step 5: Commit launcher files**

```powershell
git add -- PROJECT/tools/Start-Axu4evAd9364Golden.cmd PROJECT/tools/Start-Axu4evAd9364Workspace.cmd PROJECT/logs/jtag/.gitignore PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
git commit --only -m "feat: add one-click AXU4EV launchers" -- PROJECT/tools/Start-Axu4evAd9364Golden.cmd PROJECT/tools/Start-Axu4evAd9364Workspace.cmd PROJECT/logs/jtag/.gitignore PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
```

---

### Task 7: Documentation and Full Automated Regression

**Files:**

- Modify: `PROJECT/implementation_plan.md`
- Modify: `PROJECT/project_situation_report.md`
- Modify: `chat_report.md`
- Modify: `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/README.md`

**Interfaces:**

- Produces the operator instructions for power-cycle recovery, Golden launch, Workspace launch, promotion, and PetaLinux extension.

- [ ] **Step 1: Document exact operator procedure**

Record these steps verbatim in the release README and summarize them in the three project reports:

1. Connect JTAG and PS_UART; open PuTTY at 115200-8-N-1.
2. Power-cycle the board if the previous session ended with an instruction-transfer timeout.
3. Double-click `PROJECT\tools\Start-Axu4evAd9364Golden.cmd`.
4. Confirm `AD936x Rev 2 successfully initialized` and `Done.` in PuTTY.
5. Use Workspace launcher only for candidate builds.
6. Promote and select a new release only after the candidate passes the same UART/DMA acceptance.

- [ ] **Step 2: Run all automated tests in one fresh process**

```powershell
$tests=@(
 'PROJECT\tests\Test-Axu4evRelease.ps1',
 'PROJECT\tests\Test-Axu4evLaunchWrappers.ps1',
 'PROJECT\tests\Test-Axu4evJtagLaunchScript.ps1',
 'PROJECT\tests\Test-Axu4evXsctScriptPaths.ps1',
 'PROJECT\tests\Test-Axu4evHandoffArtifacts.ps1'
)
foreach($test in $tests){ & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test; if($LASTEXITCODE -ne 0){throw "$test failed"} }
```

Expected: five PASS results, exact BIT/XSA/application hashes, and zero failures.

- [ ] **Step 3: Run Git whitespace and scope checks**

```powershell
git diff --check
git diff --name-only HEAD
```

Expected: no whitespace errors; only task files differ from the last task commit. Do not alter unrelated staged files.

- [ ] **Step 4: Commit documentation**

```powershell
git add -- PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/README.md
git commit --only -m "docs: add repeatable AXU4EV launch procedure" -- PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/README.md
```

---

### Task 8: Clean Power-Cycle Board Acceptance

**Files:**

- Modify: `PROJECT/project_situation_report.md`
- Modify: `chat_report.md`
- Runtime only: `PROJECT/logs/jtag/<timestamp>-golden.log` (ignored)

**Interfaces:**

- Consumes `Start-Axu4evAd9364Golden.cmd` and the selected release.
- Produces final physical acceptance evidence; no automated test substitutes for this task.

- [ ] **Step 1: Establish the cold-start condition**

Close Vitis/XSCT, turn off the AXU4EVB-P, disconnect main power for 10–15 seconds, reconnect JTAG/PS_UART and power, then open PuTTY at 115200-8-N-1.

- [ ] **Step 2: Run the Golden launcher without manual XSCT commands**

Double-click `PROJECT\tools\Start-Axu4evAd9364Golden.cmd`. Do not open the XSCT console manually and do not enter any Tcl command.

- [ ] **Step 3: Verify acceptance evidence**

Require all of:

```text
cf-ad9361-lpc: Successfully initialized
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized
DMA_EXAMPLE: address=<nonzero> samples=65536 channels=2 bits=16
Done.
```

Also require an XSCT log containing successful PMUFW download, 100% FPGA programming, DDR `A5A5A5A5` readback, application download, and no `Instruction transfer timeout`.

- [ ] **Step 4: Record the acceptance**

Add the date, release id, five hashes, UART markers, and log filename to the situation and chat reports. Do not commit the runtime log.

- [ ] **Step 5: Run the full automated regression again**

Run Task 7 Step 2 command. Expected: all PASS.

- [ ] **Step 6: Commit final acceptance records**

```powershell
git add -- PROJECT/project_situation_report.md chat_report.md
git commit --only -m "test: verify AXU4EV golden cold start" -- PROJECT/project_situation_report.md chat_report.md
```

---

## Final Verification Checklist

- [ ] Golden release exists, is immutable, and matches all five approved SHA-256 values.
- [ ] `CURRENT` resolves and verifies before launch.
- [ ] Workspace mode does not modify any release file.
- [ ] Duplicate promotion is rejected.
- [ ] Stale FSBL is absent from the launch path.
- [ ] DDR comparison gates application download.
- [ ] Golden and Workspace dry-runs return correct paths and hashes.
- [ ] Both `.cmd` launchers use project-relative paths.
- [ ] Runtime logs are ignored by Git.
- [ ] Full automated test suite passes.
- [ ] Cold power-cycle Golden launch passes without manual XSCT input.
- [ ] UART confirms AD9364 Rev 2 and DMA `Done.`.
- [ ] Pre-existing unrelated staged paths remain untouched.
