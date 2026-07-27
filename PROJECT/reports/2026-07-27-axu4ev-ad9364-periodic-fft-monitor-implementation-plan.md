# AXU4EV + AD9364 Periodic FFT Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the board-verified single-shot launcher while adding a separate Candidate that captures 100 valid 2048-bin FFT frames, waits 1000 ms after the first 99 frames, prints one UART summary per frame, and fails immediately on the first real capture error.

**Architecture:** A host-testable C monitor loop owns only sequencing, delay, reporting, and fail-fast policy. `main.c` supplies AXU4EV/AD9364 adapters around the existing `pl_fft_capture_once()` driver. The existing Candidate builder gains an explicit application mode, while the launch orchestrator and JTAG Tcl remain unchanged; a new CMD selects a separate manifest-verified periodic Candidate bundle.

**Tech Stack:** C11, Analog Devices no-OS, Xilinx standalone BSP, MinGW/GCC host tests, Windows PowerShell 5.1, CMD, XSCT/Vitis 2020.1, JSON release manifests, Git.

## Global Constraints

- Keep `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd` and `fft-single-shot-v1` unchanged.
- Use exactly 100 successful frames and a 1000 ms post-capture delay after frames 1 through 99.
- Do not delay after frame 100.
- Initialize PMUFW, FPGA, PS/DDR, AD9364, and the PL FFT device only once per run.
- Read all 2048 spectrum words for every frame, but do not print all bins to UART.
- Print `seq`, hardware `frame`, `bank`, `samples`, `peak_bin`, `peak_power`, `dropped`, and `crc` for every successful frame.
- Stop on the first `pl_fft_capture_once()` error; fewer than 100 valid frames can never produce overall PASS.
- Treat `dropped_count` as diagnostics under the accepted shadow-path policy; it is not by itself a fatal monitor error.
- Do not modify Golden artifacts. Require the periodic PMUFW, bitstream, XSA, and `psu_init.tcl` to be byte-identical to the board-verified `fft-single-shot-v1` Candidate.
- Create the new bundle only under `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1`.
- Leave external RF switch control, phase shifter control, S0-S3 sequencing, AZ/EL calculation, continuous PL streaming, and PetaLinux/IIO out of scope.
- Preserve all unrelated untracked build, cache, `Release`, and `vitis2` files.

---

## File Map

### New files

- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.h` — portable monitor callback contract.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.c` — frame-count, delay, reporting, and fail-fast loop.
- `PROJECT/tests/pl_fft_monitor_test.c` — host tests using the real PL FFT driver with fake MMIO.
- `PROJECT/tests/Test-Axu4evPlFftMonitor.ps1` — compiles and runs the monitor/driver host test.
- `PROJECT/tools/Start-Axu4evAd9364PeriodicMonitor.cmd` — operator entry point for the new bundle.
- `PROJECT/tests/Test-Axu4evPeriodicMonitorLog.ps1` — validates a captured PuTTY log.
- `PROJECT/tests/Test-Axu4evPeriodicMonitorLogParser.ps1` — positive and negative parser tests.
- `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/README.md` — lab procedure and PASS contract.
- `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/**` — generated ELF, unchanged hardware/firmware artifacts, and manifest.
- `PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt` — created only after real board PASS.

### Modified files

- `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h` — make periodic mode opt-in and mutually exclusive.
- `Vitis/workspace/ad9364app/src/adc9364_src/main.c` — board adapters and exact UART output.
- `PROJECT/tests/Test-Axu4evPlFftDriver.ps1` — build/run the new C tests and compile all application-mode contracts.
- `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1` — select application mode, marker, and exact hardware reference.
- `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl` — select a validated compiler symbol.
- `PROJECT/tests/Test-Axu4evCandidateBuild.ps1` — test default and periodic build modes.
- `PROJECT/tests/Test-Axu4evPeriodicMonitorPackage.ps1` — validates the periodic manifest and exact single-shot hardware identity.
- `PROJECT/tests/Test-Axu4evPeriodicMonitorLaunch.ps1` — validates the new CMD root and periodic Candidate dry-run.
- `PROJECT/reports/implementation_plan.md` — record software and board gates.
- `PROJECT/reports/project_situation_report.md` — record current Candidate status.
- `PROJECT/reports/chat_report.md` — record this implementation and acceptance session.

### Explicitly unchanged files

- `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd`
- `PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1`
- `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl`
- `PROJECT/candidates/axu4ev-ad9364/fft-single-shot-v1/**`
- `PROJECT/tests/Test-Axu4evCandidateLaunch.ps1`
- `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1`

---

### Task 1: Add the host-tested periodic monitor policy

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.c`
- Create: `PROJECT/tests/pl_fft_monitor_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftMonitor.ps1`

**Interfaces:**
- Consumes: `struct pl_fft_device`, `struct pl_fft_result`,
  `pl_fft_capture_once()`, `PL_FFT_ERR_ARGUMENT`, and `PL_FFT_ERR_CONFIG`
  from `pl_fft_control.h`.
- Produces:

```c
typedef void (*pl_fft_monitor_delay_fn)(
	void *context, uint32_t delay_ms);
typedef void (*pl_fft_monitor_report_fn)(
	void *context, uint32_t sequence, uint32_t total,
	const struct pl_fft_result *result);

struct pl_fft_monitor {
	struct pl_fft_device *device;
	void *callback_context;
	pl_fft_monitor_delay_fn delay_ms;
	pl_fft_monitor_report_fn report_frame;
};

int pl_fft_monitor_run(struct pl_fft_monitor *monitor,
		       uint32_t frame_count, uint32_t interval_ms,
		       uint64_t spectrum[PL_FFT_SPECTRUM_WORDS],
		       uint32_t *completed_frames);
```

- [ ] **Step 1: Write failing monitor tests**

Use fake MMIO so the monitor exercises the real `pl_fft_capture_once()` path.
The fake must re-arm `STATUS_DONE`, bank-valid metadata, and frame ID for every
START. It records delay/report calls and can inject `STATUS_FFT_ERROR` on a
selected START. Include these exact contracts:

```c
static void test_100_frames_and_99_delays(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 0;

	fake_init(&fake);
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_monitor_run(&monitor, 100u, 1000u,
				 spectrum, &completed) == PL_FFT_OK);
	CHECK(completed == 100u);
	CHECK(fake.start_count == 100u);
	CHECK(fake.report_count == 100u);
	CHECK(fake.delay_count == 99u);
	CHECK(fake.last_delay_ms == 1000u);
	CHECK(fake.last_sequence == 100u);
	CHECK(fake.last_total == 100u);
}

static void test_first_capture_error_is_fail_fast(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 99u;

	fake_init(&fake);
	fake.fail_start = 17u;
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_monitor_run(&monitor, 100u, 1000u,
				 spectrum, &completed) == PL_FFT_ERR_HARDWARE);
	CHECK(completed == 16u);
	CHECK(fake.start_count == 17u);
	CHECK(fake.report_count == 16u);
	CHECK(fake.delay_count == 16u);
}
```

Also test null monitor/device/callbacks/spectrum/completed pointer as
`PL_FFT_ERR_ARGUMENT`, and zero frames/interval as `PL_FFT_ERR_CONFIG`.
Invalid inputs must not touch MMIO or invoke callbacks.

- [ ] **Step 2: Create the focused PowerShell runner and prove RED**

Use the GCC discovery and safe temporary cleanup pattern from
`Test-Axu4evPlFftDriver.ps1`, then compile:

```powershell
& $gcc -std=c11 -Wall -Wextra -Werror "-I$sourceRoot" `
    $monitorTestSource $monitorSource $driverSource -o $monitorExecutable
```

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPlFftMonitor.ps1
```

Expected: FAIL because `pl_fft_monitor.h`/`.c` or
`pl_fft_monitor_run()` does not yet exist.

- [ ] **Step 3: Implement the minimum monitor loop**

Implement `pl_fft_monitor_run()` with this control flow:

```c
int pl_fft_monitor_run(struct pl_fft_monitor *monitor,
		       uint32_t frame_count, uint32_t interval_ms,
		       uint64_t spectrum[PL_FFT_SPECTRUM_WORDS],
		       uint32_t *completed_frames)
{
	struct pl_fft_result result;
	uint32_t sequence;
	int status;

	if (monitor == NULL || monitor->device == NULL ||
	    monitor->delay_ms == NULL || monitor->report_frame == NULL ||
	    spectrum == NULL || completed_frames == NULL)
		return PL_FFT_ERR_ARGUMENT;
	if (frame_count == 0u || interval_ms == 0u)
		return PL_FFT_ERR_CONFIG;

	*completed_frames = 0u;
	for (sequence = 1u; sequence <= frame_count; sequence++) {
		status = pl_fft_capture_once(monitor->device, 0u, 2047u,
					     0u, 0u, &result, spectrum);
		if (status != 0)
			return status;
		monitor->report_frame(monitor->callback_context, sequence,
				      frame_count, &result);
		*completed_frames = sequence;
		if (sequence < frame_count)
			monitor->delay_ms(monitor->callback_context, interval_ms);
	}
	return 0;
}
```

- [ ] **Step 4: Run the focused test GREEN**

Run the same PowerShell command. Expected:

```text
PASS: pl_fft_monitor policy
```

- [ ] **Step 5: Commit the monitor unit**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.h `
        Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_monitor.c `
        PROJECT/tests/pl_fft_monitor_test.c `
        PROJECT/tests/Test-Axu4evPlFftMonitor.ps1
git commit -m "feat: add fail-fast periodic FFT monitor"
```

---

### Task 2: Integrate the periodic mode into the AXU4EV application

**Files:**
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
- Modify: `PROJECT/tests/Test-Axu4evPlFftDriver.ps1`

**Interfaces:**
- Consumes: `pl_fft_monitor_run()` from Task 1 and the existing
  `pl_fft_capture_once()` MMIO driver.
- Produces: compiler symbol `PL_FFT_PERIODIC_MONITOR` and the UART markers
  `PL_FFT_MONITOR: START|FRAME|PASS|FAIL`.

- [ ] **Step 1: Add failing application-mode contract tests**

Extend the temporary C snippets in `Test-Axu4evPlFftDriver.ps1` to verify:

```c
#include "app_config.h"
#if !defined(PL_FFT_PERIODIC_MONITOR)
#error PL_FFT_PERIODIC_MONITOR was not selected
#endif
#if defined(PL_FFT_SINGLE_SHOT) || defined(MONOPULSE_FOUNDATION_TEST)
#error periodic mode must be exclusive
#endif
int main(void) { return 0; }
```

Compile it with `-DPL_FFT_PERIODIC_MONITOR`. Add a second compile invocation
with both `-DPL_FFT_SINGLE_SHOT -DPL_FFT_PERIODIC_MONITOR` and require a
non-zero compiler exit code.

Also require these source fragments:

```text
PL_FFT_MONITOR_FRAMES 100u
PL_FFT_MONITOR_INTERVAL_MS 1000u
PL_FFT_MONITOR: START frames=
PL_FFT_MONITOR: FRAME seq=
PL_FFT_MONITOR: PASS frames=
PL_FFT_MONITOR: FAIL seq=
```

- [ ] **Step 2: Run the application contract test RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPlFftDriver.ps1
```

Expected: FAIL because periodic mode is not defined or is not exclusive.

- [ ] **Step 3: Make application modes mutually exclusive**

In `app_config.h`, preserve default foundation behavior and add:

```c
//#define PL_FFT_PERIODIC_MONITOR

#if defined(PL_FFT_SINGLE_SHOT) && defined(PL_FFT_PERIODIC_MONITOR)
#error "Only one PL FFT application mode may be enabled"
#endif

#if !defined(PL_FFT_SINGLE_SHOT) && \
	!defined(PL_FFT_PERIODIC_MONITOR)
#if !defined(WIFI_RF_TEST) && !defined(MONOPULSE_FOUNDATION_TEST)
#define MONOPULSE_FOUNDATION_TEST
#endif
#endif

#if (defined(PL_FFT_SINGLE_SHOT) || \
     defined(PL_FFT_PERIODIC_MONITOR)) && \
	(defined(MONOPULSE_FOUNDATION_TEST) || defined(WIFI_RF_TEST) || \
	 defined(DMA_EXAMPLE))
#error "PL FFT application modes must be enabled by themselves"
#endif
```

- [ ] **Step 4: Add the board adapters and exact UART contract**

In `main.c`, share address/MMIO definitions under:

```c
#if defined(PL_FFT_SINGLE_SHOT) || \
	defined(PL_FFT_PERIODIC_MONITOR)
```

Add:

```c
#define PL_FFT_MONITOR_FRAMES 100u
#define PL_FFT_MONITOR_INTERVAL_MS 1000u
```

The delay adapter must call `no_os_mdelay(delay_ms)`. The report adapter must
print one line:

```c
printf("PL_FFT_MONITOR: FRAME seq=%03"PRIu32"/%03"PRIu32
       " frame=%"PRIu32" bank=%u samples=%"PRIu32
       " peak_bin=%u peak_power=%"PRIu64
       " dropped=%"PRIu32" crc=%08"PRIx32"\n",
       sequence, total, result->frame_id, result->active_bank,
       result->sample_count, result->peak_bin, result->peak_power,
       result->dropped_count, result->frame_crc32);
```

Initialize the PL device once and construct:

```c
struct pl_fft_monitor monitor = {
	.device = &dev,
	.callback_context = NULL,
	.delay_ms = pl_fft_board_delay,
	.report_frame = pl_fft_board_report
};
```

Print START, call `pl_fft_monitor_run(&monitor, 100u, 1000u,
pl_fft_spectrum, &completed)`, and print either:

```c
printf("PL_FFT_MONITOR: PASS frames=100 interval_ms=1000\n");
```

or:

```c
printf("PL_FFT_MONITOR: FAIL seq=%03"PRIu32
       " stage=CAPTURE error=%d\n", completed + 1u, status);
```

An initialization error must use `stage=INIT`. Route
`PL_FFT_PERIODIC_MONITOR` to this function immediately after successful
`ad9361_init()`, then enter the existing cleanup path.

- [ ] **Step 5: Run host tests GREEN and single-shot regression**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPlFftDriver.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPlFftMonitor.ps1
```

Expected: both C executables pass; default foundation, single-shot, and
periodic compile contracts pass; dual-mode compilation is rejected.

- [ ] **Step 6: Commit the board application integration**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/app_config.h `
        Vitis/workspace/ad9364app/src/adc9364_src/main.c `
        PROJECT/tests/Test-Axu4evPlFftDriver.ps1
git commit -m "feat: add AXU4EV periodic FFT application mode"
```

---

### Task 3: Parameterize Candidate build and add the new CMD

**Files:**
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1`
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl`
- Create: `PROJECT/tools/Start-Axu4evAd9364PeriodicMonitor.cmd`
- Modify: `PROJECT/tests/Test-Axu4evCandidateBuild.ps1`

**Interfaces:**
- Consumes: `PL_FFT_SINGLE_SHOT` and `PL_FFT_PERIODIC_MONITOR`.
- Produces: `-ApplicationMode SingleShot|PeriodicMonitor`; periodic manifest
  marker `PL_FFT_MONITOR: PASS`; periodic CMD fixed to the periodic bundle.

- [ ] **Step 1: Write failing build-mode tests**

Keep the existing default dry-run and assert:

```powershell
if ($dryRun.application_mode -ne 'SingleShot' -or
    -not $dryRun.pl_fft_single_shot -or
    $dryRun.pl_fft_periodic_monitor) {
    throw 'Default Candidate build is no longer single-shot.'
}
```

Add an explicit periodic dry-run:

```powershell
$periodic = ((@(
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $builder `
        -WorkspaceRoot $workspaceRoot `
        -ApplicationMode PeriodicMonitor `
        -SourceXsa $candidateXsa `
        -CandidateRoot $candidateRoot `
        -VitisWorkspace $candidateWorkspace `
        -AllowedVitisWorkspaceRoot $allowedWorkspaceRoot `
        -DryRun
) -join "`n") | ConvertFrom-Json)

if ($periodic.application_mode -ne 'PeriodicMonitor' -or
    $periodic.pl_fft_single_shot -or
    -not $periodic.pl_fft_periodic_monitor) {
    throw 'Periodic Candidate build selected the wrong compiler mode.'
}
```

Require the new CMD to contain only
`fft-periodic-monitor-v1`, and prove the old CMD still contains only
`fft-single-shot-v1`.

- [ ] **Step 2: Run build/wrapper tests RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evCandidateBuild.ps1
```

Expected: FAIL because `ApplicationMode` and the periodic CMD do not exist.

- [ ] **Step 3: Add the PowerShell mode mapping**

Add this parameter with the default preserved:

```powershell
[ValidateSet('SingleShot', 'PeriodicMonitor')]
[string]$ApplicationMode = 'SingleShot'
```

Map it once:

```powershell
$compilerSymbol = switch ($ApplicationMode) {
    'SingleShot' { 'PL_FFT_SINGLE_SHOT' }
    'PeriodicMonitor' { 'PL_FFT_PERIODIC_MONITOR' }
}
$uartMarkers = switch ($ApplicationMode) {
    'SingleShot' { @('PL_FFT: PASS') }
    'PeriodicMonitor' { @('PL_FFT_MONITOR: PASS') }
}
```

Pass `$compilerSymbol` as the fifth XSCT argument. Add
`application_mode`, `compiler_symbol`, `pl_fft_single_shot`, and
`pl_fft_periodic_monitor` to dry-run JSON. Use `$uartMarkers` in manifest
metadata.

When `ApplicationMode` is `PeriodicMonitor`, load the accepted
`fft-single-shot-v1` manifest and require byte-identical hashes for
`bitstream`, `xsa`, `psu_init`, and `pmufw` before writing the new manifest.

- [ ] **Step 4: Validate the optional Tcl compiler symbol**

Allow four or five Tcl arguments. Four arguments preserve
`PL_FFT_SINGLE_SHOT`; the optional fifth argument must be exactly one of:

```tcl
set allowed_symbols {
    PL_FFT_SINGLE_SHOT
    PL_FFT_PERIODIC_MONITOR
}
```

Use the selected value here:

```tcl
app config -name $app_name define-compiler-symbols $compiler_symbol
```

The PASS line must report the selected symbol.

- [ ] **Step 5: Add the periodic CMD without touching the old CMD**

Create:

```cmd
@echo off
setlocal
set "TOOLS_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Candidate -CandidateRoot "%TOOLS_DIR%..\..\PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Launch failed with exit code %RC%.
if "%RC%"=="0" echo Periodic monitor launched. Wait for the final PASS in PuTTY.
pause
exit /b %RC%
```

- [ ] **Step 6: Run the build/wrapper tests GREEN**

Run the PowerShell test from Step 2. Expected: exit zero, the default remains
single-shot, periodic mode selects only its symbol, and both CMD roots are
isolated. Also run the unchanged single-shot gate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evCandidateLaunch.ps1
```

- [ ] **Step 7: Commit build and launch support**

```powershell
git add PROJECT/tools/Build-Axu4evPlFftCandidate.ps1 `
        PROJECT/tools/Build-Axu4evPlFftCandidate.tcl `
        PROJECT/tools/Start-Axu4evAd9364PeriodicMonitor.cmd `
        PROJECT/tests/Test-Axu4evCandidateBuild.ps1
git commit -m "build: add periodic FFT Candidate mode"
```

---

### Task 4: Add an automated PuTTY log acceptance gate

**Files:**
- Create: `PROJECT/tests/Test-Axu4evPeriodicMonitorLog.ps1`
- Create: `PROJECT/tests/Test-Axu4evPeriodicMonitorLogParser.ps1`

**Interfaces:**
- Consumes: a text log containing the UART contract from Task 2.
- Produces: exit zero plus
  `PASS: periodic FFT monitor log contains 100 valid frames.`

- [ ] **Step 1: Write failing positive and negative parser tests**

Generate a valid temporary log with START, 100 FRAME lines, and final PASS:

```powershell
$valid = @('PL_FFT_MONITOR: START frames=100 interval_ms=1000 bins=2048')
$valid += 1..100 | ForEach-Object {
    'PL_FFT_MONITOR: FRAME seq={0:D3}/100 frame={1} bank={2} samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc={3:x8}' -f `
        $_, $_, ($_ % 2), $_
}
$valid += 'PL_FFT_MONITOR: PASS frames=100 interval_ms=1000'
```

Require the parser to accept it. Create mutated copies and require rejection
for:

- 99 frame lines,
- duplicate or skipped `seq`,
- non-increasing hardware `frame`,
- `samples` other than 2048,
- any `PL_FFT_MONITOR: FAIL`,
- missing final PASS,
- any FRAME line after final PASS.

- [ ] **Step 2: Run parser test RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
```

Expected: FAIL because the parser does not exist.

- [ ] **Step 3: Implement strict log parsing**

Use an anchored regex:

```powershell
$framePattern = '^PL_FFT_MONITOR: FRAME seq=(\d{3})/100 frame=(\d+) bank=([01]) samples=2048 peak_bin=(\d+) peak_power=(\d+) dropped=(\d+) crc=([0-9a-fA-F]{8})$'
```

Require exactly one START, exactly 100 matching FRAME lines, exactly one
final PASS, continuous `seq=001..100`, and strictly increasing hardware frame
IDs. Reject any FAIL line and any FRAME after PASS.

- [ ] **Step 4: Run parser tests GREEN**

Run the command from Step 2. Expected:

```text
PASS: periodic FFT monitor log parser accepts only the complete contract.
```

- [ ] **Step 5: Commit the acceptance gate**

```powershell
git add PROJECT/tests/Test-Axu4evPeriodicMonitorLog.ps1 `
        PROJECT/tests/Test-Axu4evPeriodicMonitorLogParser.ps1
git commit -m "test: validate periodic FFT UART logs"
```

---

### Task 5: Build, test, and package `fft-periodic-monitor-v1`

**Files:**
- Create: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/README.md`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/applications/ad9364app.elf`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/hardware/system_top.bit`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/hardware/system_top.xsa`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/hardware/psu_init.tcl`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/firmware/pmufw.elf`
- Generate: `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/manifest.json`
- Create: `PROJECT/tests/Test-Axu4evPeriodicMonitorPackage.ps1`
- Create: `PROJECT/tests/Test-Axu4evPeriodicMonitorLaunch.ps1`

**Interfaces:**
- Consumes: clean committed sources from Tasks 1-4 and the accepted
  single-shot Candidate XSA.
- Produces: complete, launchable, initially unverified Candidate bundle.

- [ ] **Step 1: Verify tracked sources are clean before provenance capture**

Run:

```powershell
git status --short
```

Expected: no tracked modifications. Existing unrelated untracked build/cache
paths may remain and must not be deleted or staged.

- [ ] **Step 2: Write package and launch tests, then prove RED**

`Test-Axu4evPeriodicMonitorPackage.ps1` must load both manifests through
`Axu4evRelease.psm1`, require exactly five valid periodic artifacts, require
`board_verified=false`, require marker `PL_FFT_MONITOR: PASS`, require the
application hash to differ, and require these four artifact hashes to match:

```powershell
foreach ($name in @('bitstream', 'xsa', 'psu_init', 'pmufw')) {
    if ($singleByName[$name].Sha256 -ne $periodicByName[$name].Sha256) {
        throw "Periodic hardware differs from single-shot: $name"
    }
}
```

`Test-Axu4evPeriodicMonitorLaunch.ps1` must require the new CMD to contain
`fft-periodic-monitor-v1`, reject `fft-single-shot-v1`, and run the shared
orchestrator with the periodic root and `-DryRun`. It must assert Candidate
mode, five artifacts, and that every path remains under the periodic root.

Run both tests. Expected: FAIL because the periodic Candidate directory is
not yet complete.

- [ ] **Step 3: Run the real Vitis 2020.1 periodic build**

From the worktree root:

```powershell
$allowed = Join-Path $env:TEMP 'axu4ev-periodic-monitor-vitis'
New-Item -ItemType Directory -Path $allowed -Force | Out-Null

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tools\Build-Axu4evPlFftCandidate.ps1 `
  -ApplicationMode PeriodicMonitor `
  -SourceXsa PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1\hardware\system_top.xsa `
  -CandidateRoot PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1 `
  -VitisWorkspace (Join-Path $allowed 'workspace') `
  -AllowedVitisWorkspaceRoot $allowed
```

Expected: Vitis Release build exits zero and prints
`PASS: Candidate bundle created`.

- [ ] **Step 4: Verify the complete bundle without programming the board**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1 `
  -Mode Candidate `
  -CandidateRoot PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1 `
  -DryRun
```

Expected artifacts: `application`, `bitstream`, `pmufw`, `psu_init`, and
`xsa`; every path must be inside the periodic Candidate root.

- [ ] **Step 5: Verify exact hardware identity**

Compare each periodic artifact with the accepted single-shot artifact:

```powershell
$single = 'PROJECT\candidates\axu4ev-ad9364\fft-single-shot-v1'
$periodic = 'PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1'
foreach ($relative in @(
    'hardware\system_top.bit',
    'hardware\system_top.xsa',
    'hardware\psu_init.tcl',
    'firmware\pmufw.elf'
)) {
    $a = (Get-FileHash (Join-Path $single $relative) -Algorithm SHA256).Hash
    $b = (Get-FileHash (Join-Path $periodic $relative) -Algorithm SHA256).Hash
    if ($a -ne $b) { throw "Hardware identity mismatch: $relative" }
}
```

Expected fixed hashes:

```text
bitstream ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC
XSA       672A431A3698DFB841AD0F09A8605CD1D125314FCB6333E49A60727E8B42E574
psu_init  CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B
PMUFW     9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB
```

- [ ] **Step 6: Add the operator README**

Document JTAG + PS_UART setup, new CMD, expected 100 FRAME lines, final PASS,
fail-fast behavior, approximately 100-second duration, and this warning:

```text
The CMD/XSCT "launch completed" message means only that the ELF started.
Board acceptance requires the final PL_FFT_MONITOR: PASS line in PuTTY.
```

State `board_verified=false` until Task 7.

- [ ] **Step 7: Run package/launch tests GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorPackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLaunch.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evCandidateLaunch.ps1
```

Expected: all three exit zero. The last command is the unchanged single-shot
launch regression.

- [ ] **Step 8: Commit the generated Candidate**

```powershell
git add PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1 `
        PROJECT/tests/Test-Axu4evPeriodicMonitorPackage.ps1 `
        PROJECT/tests/Test-Axu4evPeriodicMonitorLaunch.ps1
git commit -m "build: package periodic FFT Candidate"
```

---

### Task 6: Run preflight regression and update project reports

**Files:**
- Modify: `PROJECT/reports/implementation_plan.md`
- Modify: `PROJECT/reports/project_situation_report.md`
- Modify: `PROJECT/reports/chat_report.md`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: software-ready status with physical board acceptance still open.

- [ ] **Step 1: Run the focused software/preflight suite**

Run each command and require exit zero:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftDriver.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftMonitor.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evCandidateBuild.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evCandidateLaunch.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorPackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLaunch.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evJtagLaunchScript.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evRelease.ps1
```

`Test-Axu4evLaunchWrappers.ps1` is not a periodic acceptance gate in this
plan: its pre-feature baseline currently fails because unrelated generated
Workspace Vivado/Vitis/IDE bitstreams are out of sync. Do not change or
silently waive that test; record the known baseline separately.

- [ ] **Step 2: Prove the single-shot launcher was not modified**

Run:

```powershell
git diff df3e052 -- PROJECT/tools/Start-Axu4evAd9364Candidate.cmd `
  PROJECT/candidates/axu4ev-ad9364/fft-single-shot-v1
```

Expected: no diff.

- [ ] **Step 3: Update reports without claiming board PASS**

Record:

- new periodic mode and wrapper,
- host test counts and commands,
- Candidate artifact hashes,
- exact hardware identity,
- `board_verified=false`,
- next action: run the new CMD and capture PuTTY output.

Do not create evidence or mark the periodic Candidate accepted.

- [ ] **Step 4: Commit the software-ready checkpoint**

```powershell
git add PROJECT/reports/implementation_plan.md `
        PROJECT/reports/project_situation_report.md `
        PROJECT/reports/chat_report.md
git commit -m "docs: record periodic FFT preflight"
```

---

### Task 7: Perform physical board acceptance

**Files:**
- Create after PASS only:
  `PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt`
- Modify after PASS only:
  `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/manifest.json`
- Modify after PASS only:
  `PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/README.md`
- Modify after PASS only:
  `PROJECT/reports/implementation_plan.md`
- Modify after PASS only:
  `PROJECT/reports/project_situation_report.md`
- Modify after PASS only:
  `PROJECT/reports/chat_report.md`

**Interfaces:**
- Consumes: real AXU4EVB-P + AD9364, JTAG, PS_UART, and the periodic bundle.
- Produces: board evidence and `board_verified=true`.

- [ ] **Step 1: Prepare the board**

Connect JTAG and PS_UART, power the board, and open PuTTY at `115200-8-N-1`.
Clear or start a fresh PuTTY session log.

- [ ] **Step 2: Launch exactly once**

From the worktree root:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364PeriodicMonitor.cmd
```

Do not re-run the CMD while the 100-frame monitor is active.

- [ ] **Step 3: Wait for UART completion**

The Windows launcher will finish before the monitor. Continue watching PuTTY
until either:

```text
PL_FFT_MONITOR: PASS frames=100 interval_ms=1000
```

or the first `PL_FFT_MONITOR: FAIL`.

- [ ] **Step 4: Validate the saved PuTTY log**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 `
  -LogPath <absolute-path-to-putty-log>
```

Expected:

```text
PASS: periodic FFT monitor log contains 100 valid frames.
```

- [ ] **Step 5: Record evidence only after parser PASS**

Copy the relevant AD9364 initialization, START, all 100 FRAME lines, and final
PASS to the evidence file. Record date, branch, commit, ELF SHA-256,
bitstream SHA-256, antenna/RF source configuration, and PuTTY settings.

Set periodic manifest `board_verified` to `true`; do not change artifact
hashes or the single-shot Candidate.

- [ ] **Step 6: Re-run manifest and release gates**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1 `
  -Mode Candidate `
  -CandidateRoot PROJECT\candidates\axu4ev-ad9364\fft-periodic-monitor-v1 `
  -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evCandidateLaunch.ps1
```

- [ ] **Step 7: Commit physical acceptance**

```powershell
git add PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt `
        PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/manifest.json `
        PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1/README.md `
        PROJECT/reports/implementation_plan.md `
        PROJECT/reports/project_situation_report.md `
        PROJECT/reports/chat_report.md
git commit -m "test: accept periodic FFT monitor on hardware"
```

## Completion Gate

Implementation is complete only when:

1. Host tests prove exactly 100 captures, 99 delays, and fail-fast behavior.
2. Default and existing single-shot modes still pass.
3. Periodic Candidate build selects only `PL_FFT_PERIODIC_MONITOR`.
4. Periodic hardware/firmware artifacts are byte-identical to the accepted
   single-shot Candidate.
5. PuTTY log parser accepts exactly 100 valid frames and the final PASS.
6. Physical evidence is committed and periodic manifest says
   `board_verified=true`.
