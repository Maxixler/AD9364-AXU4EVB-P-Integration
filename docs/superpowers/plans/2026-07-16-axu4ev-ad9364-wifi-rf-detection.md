# AXU4EVB-P + AD9364 Wi-Fi RF Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable bare-metal test that proves the AXU4EVB-P + AD9364 RXB path detects controlled 2.4 GHz phone-hotspot activity and reports RF/DMA health over PS_UART.

**Architecture:** Keep the verified Golden BIT, PMUFW, and PS initialization immutable, and add a Candidate launcher that substitutes only the Release application ELF. Split the application into a pure I/Q metrics module, an AD9364/AXI-DMAC capture module, and a UART-driven scan/monitor state machine called from the existing `main.c` behind `WIFI_RF_TEST`.

**Tech Stack:** Xilinx Vitis/XSCT 2020.1, bare-metal Cortex-A53 C11, ADI no-OS AD9361 API, ADI AXI-DMAC, Xilinx BSP UART/cache APIs, Windows PowerShell tests, MinGW GCC native metric tests, Git.

## Global Constraints

- Target hardware is AXU4EVB-P with AD9364; RX uses `B_BALANCED` through the physically matched RXB connector.
- AD9364 is 1x1. The two enabled ADC streams are I and Q, not two antennas.
- The test scans Wi-Fi channels 1-13 at `2412 + 5 * (channel - 1)` MHz with 30.72 MSPS and 18 MHz RX bandwidth.
- TX attenuation must be `89750 mdB`, ENSM must verify `ENSM_MODE_RX`, and the Wi-Fi test path must not initialize AXI DAC, DDS, or TX DMAC.
- DMA remains finite/non-cyclic with a 500 ms timeout per block; scan dwell is 250 ms per channel and monitor duration is 10 s with 500 ms summaries.
- Candidate mode uses Golden `system_top.bit`, PMUFW, and `psu_init.tcl`, plus exactly `Vitis/workspace/ad9364app/Release/ad9364app.elf`; it must not fall back to Debug.
- Existing Golden release artifacts and hashes must remain unchanged.
- `WIFI_RF_TEST` disabled must preserve the existing no-OS application behavior.
- `PLATFORM: FAIL`, `RF_ACTIVITY: INCONCLUSIVE`, and `WIFI_RF_TEST: PASS` are distinct outcomes; inability to observe hotspot activity is not automatically a platform failure.
- Do not decode 802.11 frames or payloads, transmit RF, add FFT/graphs, implement PetaLinux, or add MIMO in this plan.
- The working tree already contains 1081 unrelated staged paths and three modified Markdown reports. Every commit must use explicit pathspecs with `git commit --only`; never reset, unstage, clean, or broad-add the tree.

**Source specification:** `docs/superpowers/specs/2026-07-16-axu4ev-ad9364-wifi-rf-detection-design.md`

---

## File Map

- `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd`: one-click Candidate entry point.
- `PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1`: resolves verified Golden hardware plus the Release candidate ELF.
- `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1`: deterministic Candidate dry-run and wrapper tests.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.h`: pure metric and verdict types/API.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.c`: I/Q power, peak, clipping, median, burst, and verdict calculations.
- `PROJECT/tests/wifi_rf_metrics_test.c`: native deterministic metric vectors.
- `PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1`: builds/runs the native metric test with MinGW.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.h`: RX/DMA capture context and channel result interface.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.c`: RX-only safety, LO/gain control, RSSI, repeated one-shot DMA, and aggregation.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.h`: top-level test return codes and entry point.
- `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.c`: PuTTY prompts, two scans, channel selection, monitor, UART formatting, and final verdict.
- `PROJECT/tests/Test-Axu4evWifiRfSource.ps1`: static integration/safety invariants.
- `PROJECT/tests/Build-Axu4evAd9364App.ps1`: path-safe XSCT Release build wrapper; currently present but untracked, and made part of the reproducible project in Task 5.
- `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`: enables `WIFI_RF_TEST` and rejects conflicting DMA demo mode.
- `Vitis/workspace/ad9364app/src/adc9364_src/main.c`: checks init errors, skips TX setup, calls the test, and retains cleanup.
- `Vitis/workspace/ad9364app/.cproject`: links `libm` in Release, matching the existing Debug configuration.
- `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt`: accepted UART evidence after the real board test.
- `PROJECT/implementation_plan.md`, `PROJECT/project_situation_report.md`, `chat_report.md`: project status updates after board acceptance.

---

### Task 1: Add the Golden-hardware/Release-application Candidate launcher

**Files:**
- Create: `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd`
- Modify: `PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1`
- Modify: `PROJECT/tests/Test-Axu4evLaunchWrappers.ps1`

**Interfaces:**
- Consumes: `Resolve-Axu4evCurrentRelease`, `Read-Axu4evReleaseManifest`, and `Test-Axu4evReleaseArtifacts` from `PROJECT/tools/Axu4evRelease.psm1`.
- Produces: `Invoke-Axu4evAd9364Launch.ps1 -Mode Candidate [-CandidateApplication <path>] [-DryRun]`; default candidate path is exactly `Vitis/workspace/ad9364app/Release/ad9364app.elf`.

- [ ] **Step 1: Extend the launcher test so Candidate fails before implementation**

In `Test-Axu4evLaunchWrappers.ps1`, change the helper signature and mode loops, create a temporary ELF for the dry-run, and assert the source split:

```powershell
function Invoke-DryRun {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Golden', 'Workspace', 'Candidate')]
        [string]$Mode,

        [string]$CandidateApplication
    )

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $orchestrator,
        '-Mode', $Mode, '-WorkspaceRoot', $workspaceRoot, '-DryRun'
    )
    if ($CandidateApplication) {
        $arguments += @('-CandidateApplication', $CandidateApplication)
    }
    $lines = @(& powershell.exe @arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "$Mode dry-run failed with exit code $LASTEXITCODE."
    }
    return (($lines -join "`n") | ConvertFrom-Json)
}

$candidateTemp = Join-Path ([IO.Path]::GetTempPath()) "ad9364app-candidate-$([guid]::NewGuid()).elf"
try {
    Set-Content -LiteralPath $candidateTemp -Value 'candidate-app' -NoNewline
    $golden = Invoke-DryRun -Mode Golden
    $candidate = Invoke-DryRun -Mode Candidate -CandidateApplication $candidateTemp

    foreach ($name in @('bitstream', 'pmufw', 'psu_init')) {
        $goldenArtifact = @($golden.artifacts | Where-Object name -eq $name)[0]
        $candidateArtifact = @($candidate.artifacts | Where-Object name -eq $name)[0]
        if ($candidateArtifact.sha256 -ne $goldenArtifact.sha256) {
            throw "Candidate $name did not come from the current Golden release."
        }
    }
    $candidateApp = @($candidate.artifacts | Where-Object name -eq 'application')[0]
    if ([IO.Path]::GetFullPath($candidateApp.path) -ne [IO.Path]::GetFullPath($candidateTemp)) {
        throw 'Candidate did not use the explicit test application.'
    }
}
finally {
    Remove-Item -LiteralPath $candidateTemp -Force -ErrorAction SilentlyContinue
}
```

Keep the existing artifact-validation loop for `Golden` and `Workspace`; the separate temporary-ELF block above fully validates Candidate artifact provenance. Change only the `.cmd` wrapper loop to include `Candidate`. Update the final pass line to:

```powershell
Write-Output 'PASS: Golden, Workspace, and Candidate launchers resolve the intended verified artifacts.'
```

- [ ] **Step 2: Run the launcher test and verify the new mode is rejected**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
```

Expected: FAIL because `Invoke-Axu4evAd9364Launch.ps1` does not accept `Candidate` and the Candidate `.cmd` does not exist.

- [ ] **Step 3: Implement Candidate artifact resolution without Debug fallback**

Update the parameter block in `Invoke-Axu4evAd9364Launch.ps1`:

```powershell
param(
    [ValidateSet('Golden', 'Workspace', 'Candidate')]
    [string]$Mode = 'Golden',

    [string]$WorkspaceRoot,

    [string]$CandidateApplication,

    [switch]$DryRun
)
```

Replace the two-way Golden/Workspace artifact branch with this exact three-way structure:

```powershell
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
```

The existing common validation, SHA-256 reporting, environment setup, and XSCT launch remain unchanged.

- [ ] **Step 4: Create the one-click Candidate wrapper**

Create `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd`:

```bat
@echo off
setlocal
set "TOOLS_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%Invoke-Axu4evAd9364Launch.ps1" -Mode Candidate
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Launch failed with exit code %RC%.
if "%RC%"=="0" echo Candidate launch completed. Check PS_UART in PuTTY.
pause
exit /b %RC%
```

- [ ] **Step 5: Run launcher and JTAG-script regressions**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1
```

Expected:

```text
PASS: Golden, Workspace, and Candidate launchers resolve the intended verified artifacts.
PASS: verified artifacts, PMUFW, FPGA, PS/DDR/PS-PL, DDR gate, and application launch order are valid.
```

- [ ] **Step 6: Commit only Candidate launcher files**

```powershell
git add -- PROJECT/tools/Start-Axu4evAd9364Candidate.cmd PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1 PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
git commit --only -m "feat: add AXU4EV RF candidate launcher" -- PROJECT/tools/Start-Axu4evAd9364Candidate.cmd PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1 PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
```

---

### Task 2: Implement and native-test the pure I/Q metrics engine

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.c`
- Create: `PROJECT/tests/wifi_rf_metrics_test.c`
- Create: `PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1`

**Interfaces:**
- Consumes: interleaved signed 16-bit `[I0,Q0,I1,Q1,...]` data and per-channel baseline/active summaries.
- Produces: `wifi_rf_analyze_block`, `wifi_rf_median_u64`, `wifi_rf_power_cdbfs16`, `wifi_rf_peak_cdbfs16`, `wifi_rf_delta`, and `wifi_rf_classify`.

- [ ] **Step 1: Create the public metric contract and failing native test**

Create `wifi_rf_metrics.h`:

```c
#ifndef WIFI_RF_METRICS_H
#define WIFI_RF_METRICS_H

#include <stddef.h>
#include <stdint.h>

#define WIFI_RF_CLIP_ABS 32112U
#define WIFI_RF_RSSI_DELTA_PASS_CDB 300
#define WIFI_RF_POWER_DELTA_PASS_CDB 300
#define WIFI_RF_BURST_DELTA_PASS_PP 20
#define WIFI_RF_REQUIRED_MONITOR_HITS 3U
#define WIFI_RF_ZERO_CDBFS INT32_MIN
#define WIFI_RF_RSSI_INVALID_CDB INT32_MIN

struct wifi_rf_block_metrics {
	uint64_t mean_power;
	uint32_t complex_samples;
	uint32_t clip_count;
	uint16_t peak_abs;
};

struct wifi_rf_channel_metrics {
	int32_t rssi_cdb;
	int32_t power_cdbfs16;
	int32_t peak_cdbfs16;
	int32_t gain_db;
	uint64_t baseline_median_power;
	uint32_t clip_count;
	uint32_t complex_samples;
	uint32_t dma_blocks;
	uint8_t burst_percent;
};

struct wifi_rf_metric_delta {
	int32_t rssi_cdb;
	int32_t power_cdb;
	int32_t burst_pp;
};

enum wifi_rf_activity_verdict {
	WIFI_RF_ACTIVITY_INCONCLUSIVE = 0,
	WIFI_RF_ACTIVITY_PASS = 1
};

int32_t wifi_rf_analyze_block(const int16_t *iq, size_t complex_samples,
			      struct wifi_rf_block_metrics *out);
uint64_t wifi_rf_median_u64(uint64_t *values, size_t count);
int32_t wifi_rf_power_cdbfs16(uint64_t mean_power);
int32_t wifi_rf_peak_cdbfs16(uint16_t peak_abs);
struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *baseline,
	const struct wifi_rf_channel_metrics *active);
enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *delta,
	uint32_t monitor_hits,
	uint32_t clip_count,
	uint32_t complex_samples);

#endif
```

Create `PROJECT/tests/wifi_rf_metrics_test.c` with deterministic checks:

```c
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "wifi_rf_metrics.h"

static void test_zero_and_constant(void)
{
	int16_t zero[8] = {0};
	int16_t quarter_scale[8] = {
		16384, 16384, 16384, 16384,
		16384, 16384, 16384, 16384
	};
	struct wifi_rf_block_metrics m;

	assert(wifi_rf_analyze_block(zero, 4, &m) == 0);
	assert(m.mean_power == 0);
	assert(m.peak_abs == 0);
	assert(m.clip_count == 0);
	assert(wifi_rf_power_cdbfs16(m.mean_power) == WIFI_RF_ZERO_CDBFS);

	assert(wifi_rf_analyze_block(quarter_scale, 4, &m) == 0);
	assert(m.mean_power == 536870912ULL);
	assert(m.peak_abs == 16384);
	assert(m.clip_count == 0);
	assert(wifi_rf_power_cdbfs16(m.mean_power) >= -603);
	assert(wifi_rf_power_cdbfs16(m.mean_power) <= -601);
	assert(wifi_rf_peak_cdbfs16(m.peak_abs) >= -603);
	assert(wifi_rf_peak_cdbfs16(m.peak_abs) <= -601);
}

static void test_clipping_median_and_verdict(void)
{
	int16_t clipped[4] = {32767, -32768, 100, -100};
	uint64_t values[5] = {40, 10, 30, 50, 20};
	struct wifi_rf_block_metrics m;
	struct wifi_rf_channel_metrics baseline = {
		.rssi_cdb = -6000, .power_cdbfs16 = -4800,
		.burst_percent = 3
	};
	struct wifi_rf_channel_metrics active = {
		.rssi_cdb = -5600, .power_cdbfs16 = -4400,
		.burst_percent = 24
	};
	struct wifi_rf_metric_delta delta;

	assert(wifi_rf_analyze_block(clipped, 2, &m) == 0);
	assert(m.peak_abs == 32768U);
	assert(m.clip_count == 1U);
	assert(wifi_rf_median_u64(values, 5) == 30U);

	delta = wifi_rf_delta(&baseline, &active);
	assert(delta.rssi_cdb == 400);
	assert(delta.power_cdb == 400);
	assert(delta.burst_pp == 21);
	assert(wifi_rf_classify(&delta, 3, 0, 10000) == WIFI_RF_ACTIVITY_PASS);
	assert(wifi_rf_classify(&delta, 2, 0, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	assert(wifi_rf_classify(&delta, 3, 11, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	baseline.rssi_cdb = WIFI_RF_RSSI_INVALID_CDB;
	delta = wifi_rf_delta(&baseline, &active);
	assert(delta.rssi_cdb == WIFI_RF_RSSI_INVALID_CDB);
	assert(wifi_rf_classify(&delta, 3, 0, 10000) == WIFI_RF_ACTIVITY_PASS);
}

int main(void)
{
	test_zero_and_constant();
	test_clipping_median_and_verdict();
	puts("PASS: Wi-Fi RF metrics deterministic vectors passed.");
	return 0;
}
```

- [ ] **Step 2: Create the native test runner and verify the missing implementation fails**

Create `PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$gcc = 'C:\MinGW\bin\gcc.exe'
$test = Join-Path $root 'PROJECT\tests\wifi_rf_metrics_test.c'
$source = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src\wifi_rf_metrics.c'
$include = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$output = Join-Path ([IO.Path]::GetTempPath()) "wifi-rf-metrics-$([guid]::NewGuid()).exe"

try {
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$include" $test $source -lm -o $output
    if ($LASTEXITCODE -ne 0) { throw 'Native metrics compilation failed.' }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Native metrics test failed.' }
}
finally {
    Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
}
```

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
```

Expected: FAIL because `wifi_rf_metrics.c` is missing.

- [ ] **Step 3: Implement power, peak, clipping, median, delta, and verdict calculations**

Create `wifi_rf_metrics.c`:

```c
#include "wifi_rf_metrics.h"

#include <errno.h>
#include <limits.h>
#include <math.h>

#define WIFI_RF_COMPLEX_FULL_SCALE_POWER 2147483648.0

static uint16_t abs_i16(int16_t value)
{
	int32_t widened = value;
	return (uint16_t)(widened < 0 ? -widened : widened);
}

int32_t wifi_rf_analyze_block(const int16_t *iq, size_t complex_samples,
			      struct wifi_rf_block_metrics *out)
{
	uint64_t sum = 0;
	uint32_t clips = 0;
	uint16_t peak = 0;
	size_t n;

	if (!iq || !out || complex_samples == 0 || complex_samples > UINT32_MAX)
		return -EINVAL;

	for (n = 0; n < complex_samples; n++) {
		int32_t i = iq[2 * n];
		int32_t q = iq[2 * n + 1];
		uint16_t ai = abs_i16((int16_t)i);
		uint16_t aq = abs_i16((int16_t)q);

		sum += (uint64_t)(i * i) + (uint64_t)(q * q);
		if (ai > peak) peak = ai;
		if (aq > peak) peak = aq;
		if (ai >= WIFI_RF_CLIP_ABS || aq >= WIFI_RF_CLIP_ABS)
			clips++;
	}

	out->mean_power = sum / complex_samples;
	out->complex_samples = (uint32_t)complex_samples;
	out->clip_count = clips;
	out->peak_abs = peak;
	return 0;
}

uint64_t wifi_rf_median_u64(uint64_t *values, size_t count)
{
	size_t i, j;
	if (!values || count == 0) return 0;
	for (i = 1; i < count; i++) {
		uint64_t key = values[i];
		j = i;
		while (j > 0 && values[j - 1] > key) {
			values[j] = values[j - 1];
			j--;
		}
		values[j] = key;
	}
	return values[count / 2];
}

int32_t wifi_rf_power_cdbfs16(uint64_t mean_power)
{
	double cdb;
	if (mean_power == 0) return WIFI_RF_ZERO_CDBFS;
	cdb = 1000.0 * log10((double)mean_power /
				     WIFI_RF_COMPLEX_FULL_SCALE_POWER);
	return (int32_t)lround(cdb);
}

int32_t wifi_rf_peak_cdbfs16(uint16_t peak_abs)
{
	double cdb;
	if (peak_abs == 0) return WIFI_RF_ZERO_CDBFS;
	cdb = 2000.0 * log10((double)peak_abs / 32768.0);
	return (int32_t)lround(cdb);
}

struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *baseline,
	const struct wifi_rf_channel_metrics *active)
{
	struct wifi_rf_metric_delta delta = {0};
	if (!baseline || !active) return delta;
	delta.rssi_cdb = baseline->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB ||
		active->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB ?
		WIFI_RF_RSSI_INVALID_CDB : active->rssi_cdb - baseline->rssi_cdb;
	delta.power_cdb = active->power_cdbfs16 - baseline->power_cdbfs16;
	delta.burst_pp = (int32_t)active->burst_percent -
			 (int32_t)baseline->burst_percent;
	return delta;
}

enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *delta,
	uint32_t monitor_hits,
	uint32_t clip_count,
	uint32_t complex_samples)
{
	uint32_t indicators = 0;
	if (!delta || complex_samples == 0) return WIFI_RF_ACTIVITY_INCONCLUSIVE;
	if ((uint64_t)clip_count * 1000U > complex_samples)
		return WIFI_RF_ACTIVITY_INCONCLUSIVE;
	if (delta->rssi_cdb != WIFI_RF_RSSI_INVALID_CDB &&
	    delta->rssi_cdb >= WIFI_RF_RSSI_DELTA_PASS_CDB) indicators++;
	if (delta->power_cdb >= WIFI_RF_POWER_DELTA_PASS_CDB) indicators++;
	if (delta->burst_pp >= WIFI_RF_BURST_DELTA_PASS_PP) indicators++;
	return indicators >= 2 && monitor_hits >= WIFI_RF_REQUIRED_MONITOR_HITS ?
		WIFI_RF_ACTIVITY_PASS : WIFI_RF_ACTIVITY_INCONCLUSIVE;
}
```

- [ ] **Step 4: Run native metrics tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
```

Expected:

```text
PASS: Wi-Fi RF metrics deterministic vectors passed.
```

- [ ] **Step 5: Commit only the metrics engine and its tests**

```powershell
git add -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.c PROJECT/tests/wifi_rf_metrics_test.c PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
git commit --only -m "feat: add deterministic Wi-Fi RF metrics" -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_metrics.c PROJECT/tests/wifi_rf_metrics_test.c PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
```

---

### Task 3: Implement RX-only AD9364 and repeated one-shot DMA capture

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.c`
- Create: `PROJECT/tests/Test-Axu4evWifiRfSource.ps1`

**Interfaces:**
- Consumes: `struct ad9361_rf_phy *`, `struct axi_dmac *`, an aligned interleaved I/Q buffer, and Task 2 metric functions.
- Produces: `wifi_rf_capture_init`, `wifi_rf_prepare_rx_only`, and `wifi_rf_capture_channel` with fixed baseline gain reuse.

- [ ] **Step 1: Write static safety/source tests before creating capture files**

Create `PROJECT/tests/Test-Axu4evWifiRfSource.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$capture = Join-Path $sourceRoot 'wifi_rf_capture.c'
$header = Join-Path $sourceRoot 'wifi_rf_capture.h'

foreach ($path in @($capture, $header)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Wi-Fi RF capture source: $path"
    }
}

$content = Get-Content -LiteralPath $capture -Raw
$required = @(
    'ad9361_set_rx_rf_port_input(ctx->phy, B_BALANCED)',
    'ad9361_get_rx_rf_port_input(ctx->phy, &port)',
    'ad9361_set_tx_attenuation(ctx->phy, 0, 89750)',
    'ad9361_set_en_state_machine_mode(ctx->phy, ENSM_MODE_RX)',
    'ad9361_get_en_state_machine_mode(ctx->phy, &ensm)',
    '.cyclic = NO',
    'axi_dmac_transfer_wait_completion(ctx->rx_dmac, WIFI_RF_DMA_TIMEOUT_MS)',
    'Xil_DCacheInvalidateRange',
    'RF_GAIN_SLOWATTACK_AGC',
    'RF_GAIN_MGC',
    'ad9361_set_rx_rf_gain',
    'ad9361_get_rx_rssi',
    'wifi_rf_analyze_block',
    'LO_ERROR',
    'GAIN_ERROR',
    'DMA_ERROR'
)
foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "Capture path is missing required safety/measurement fragment: $fragment"
    }
}

if ($content -match 'axi_dmac_transfer_start\s*\(\s*tx_dmac' -or
    $content -match 'axi_dac_' -or $content -match 'AXI_DAC_DATA_SEL_DDS') {
    throw 'Wi-Fi RF capture path contains TX DAC/DDS/DMAC behavior.'
}

Write-Output 'PASS: Wi-Fi RF capture source enforces RX-only finite-DMA behavior.'
```

- [ ] **Step 2: Run the source test and verify it fails on missing capture files**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

Expected: FAIL with `Missing Wi-Fi RF capture source`.

- [ ] **Step 3: Create the capture interface**

Create `wifi_rf_capture.h`:

```c
#ifndef WIFI_RF_CAPTURE_H
#define WIFI_RF_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#include "ad9361_api.h"
#include "axi_dmac.h"
#include "wifi_rf_metrics.h"

#define WIFI_RF_FIRST_CHANNEL 1U
#define WIFI_RF_LAST_CHANNEL 13U
#define WIFI_RF_CHANNEL_COUNT 13U
#define WIFI_RF_SCAN_DWELL_MS 250U
#define WIFI_RF_MONITOR_DWELL_MS 500U
#define WIFI_RF_DMA_TIMEOUT_MS 500U
#define WIFI_RF_LO_SETTLE_MS 20U
#define WIFI_RF_MAX_BLOCKS 512U

enum wifi_rf_capture_mode {
	WIFI_RF_CAPTURE_BASELINE,
	WIFI_RF_CAPTURE_ACTIVE
};

struct wifi_rf_capture_ctx {
	struct ad9361_rf_phy *phy;
	struct axi_dmac *rx_dmac;
	int16_t *iq_buffer;
	size_t complex_samples;
	const char *last_error;
};

int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *ctx,
			     struct ad9361_rf_phy *phy,
			     struct axi_dmac *rx_dmac,
			     int16_t *iq_buffer,
			     size_t complex_samples);
int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *ctx);
uint64_t wifi_rf_channel_frequency_hz(uint8_t channel);
int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *ctx,
				uint8_t channel,
				enum wifi_rf_capture_mode mode,
				uint32_t dwell_ms,
				const struct wifi_rf_channel_metrics *baseline,
				struct wifi_rf_channel_metrics *out);

#endif
```

- [ ] **Step 4: Implement RX-only safety and one DMA block**

Start `wifi_rf_capture.c` with these includes and helpers:

```c
#include "wifi_rf_capture.h"

#include <errno.h>
#include <limits.h>
#include <string.h>

#include "no_os_delay.h"
#include "xil_cache.h"

static uint64_t now_us(void)
{
	struct no_os_time now = no_os_get_time();
	return (uint64_t)now.s * 1000000ULL + now.us;
}

int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *ctx,
			     struct ad9361_rf_phy *phy,
			     struct axi_dmac *rx_dmac,
			     int16_t *iq_buffer,
			     size_t complex_samples)
{
	if (!ctx || !phy || !rx_dmac || !iq_buffer ||
	    ((uintptr_t)iq_buffer & 63U) != 0U || complex_samples == 0 ||
	    complex_samples > UINT32_MAX / (2U * sizeof(int16_t)))
		return -EINVAL;
	ctx->phy = phy;
	ctx->rx_dmac = rx_dmac;
	ctx->iq_buffer = iq_buffer;
	ctx->complex_samples = complex_samples;
	ctx->last_error = "NONE";
	return 0;
}

int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *ctx)
{
	uint32_t port = UINT32_MAX;
	uint32_t ensm = UINT32_MAX;
	int32_t ret;
	if (!ctx) return -EINVAL;
	ret = ad9361_set_rx_rf_port_input(ctx->phy, B_BALANCED);
	if (ret < 0) return ret;
	ret = ad9361_get_rx_rf_port_input(ctx->phy, &port);
	if (ret < 0 || port != B_BALANCED) return ret < 0 ? ret : -EIO;
	ret = ad9361_set_tx_attenuation(ctx->phy, 0, 89750);
	if (ret < 0) return ret;
	ret = ad9361_set_en_state_machine_mode(ctx->phy, ENSM_MODE_RX);
	if (ret < 0) return ret;
	ret = ad9361_get_en_state_machine_mode(ctx->phy, &ensm);
	if (ret < 0 || ensm != ENSM_MODE_RX) return ret < 0 ? ret : -EIO;
	return 0;
}

uint64_t wifi_rf_channel_frequency_hz(uint8_t channel)
{
	if (channel < WIFI_RF_FIRST_CHANNEL || channel > WIFI_RF_LAST_CHANNEL)
		return 0;
	return 2412000000ULL + (uint64_t)(channel - 1U) * 5000000ULL;
}

static int32_t capture_one_block(struct wifi_rf_capture_ctx *ctx,
				 struct wifi_rf_block_metrics *metrics)
{
	struct axi_dma_transfer transfer = {
		.size = (uint32_t)(ctx->complex_samples * 2U * sizeof(int16_t)),
		.transfer_done = 0,
		.cyclic = NO,
		.src_addr = 0,
		.dest_addr = (uint32_t)(uintptr_t)ctx->iq_buffer
	};
	int32_t ret;
	ctx->last_error = "DMA_ERROR";
	ret = axi_dmac_transfer_start(ctx->rx_dmac, &transfer);
	if (ret < 0) return ret;
	ret = axi_dmac_transfer_wait_completion(ctx->rx_dmac,
						 WIFI_RF_DMA_TIMEOUT_MS);
	if (ret < 0) return ret;
	Xil_DCacheInvalidateRange((uintptr_t)ctx->iq_buffer, transfer.size);
	return wifi_rf_analyze_block(ctx->iq_buffer, ctx->complex_samples, metrics);
}
```

- [ ] **Step 5: Implement fixed-gain channel capture and aggregation**

Append `wifi_rf_capture_channel` using the following exact algorithm:

```c
int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *ctx,
				uint8_t channel,
				enum wifi_rf_capture_mode mode,
				uint32_t dwell_ms,
				const struct wifi_rf_channel_metrics *baseline,
				struct wifi_rf_channel_metrics *out)
{
	uint64_t block_power[WIFI_RF_MAX_BLOCKS];
	uint64_t sum_power = 0, start, threshold;
	uint32_t blocks = 0, clips = 0, samples = 0, bursts = 0;
	uint16_t peak = 0;
	struct wifi_rf_block_metrics block;
	struct rf_rssi rssi = {0};
	uint64_t frequency = wifi_rf_channel_frequency_hz(channel);
	int32_t gain_db, ret;

	if (!ctx || !out || !frequency || !dwell_ms) return -EINVAL;
	if (mode == WIFI_RF_CAPTURE_ACTIVE && !baseline) return -EINVAL;
	memset(out, 0, sizeof(*out));

	ctx->last_error = "LO_ERROR";
	ret = ad9361_set_rx_lo_freq(ctx->phy, frequency);
	if (ret < 0) return ret;
	ctx->last_error = "GAIN_ERROR";
	if (mode == WIFI_RF_CAPTURE_BASELINE) {
		ret = ad9361_set_rx_gain_control_mode(ctx->phy, 0,
						      RF_GAIN_SLOWATTACK_AGC);
		if (ret < 0) return ret;
		no_os_mdelay(WIFI_RF_LO_SETTLE_MS);
		ret = ad9361_get_rx_rf_gain(ctx->phy, 0, &gain_db);
		if (ret < 0) return ret;
	} else {
		gain_db = baseline->gain_db;
		no_os_mdelay(WIFI_RF_LO_SETTLE_MS);
	}
	ret = ad9361_set_rx_gain_control_mode(ctx->phy, 0, RF_GAIN_MGC);
	if (ret < 0) return ret;
	ret = ad9361_set_rx_rf_gain(ctx->phy, 0, gain_db);
	if (ret < 0) return ret;

	start = now_us();
	do {
		ret = capture_one_block(ctx, &block);
		if (ret < 0) return ret;
		block_power[blocks] = block.mean_power;
		sum_power += block.mean_power;
		clips += block.clip_count;
		samples += block.complex_samples;
		if (block.peak_abs > peak) peak = block.peak_abs;
		blocks++;
	} while (blocks < WIFI_RF_MAX_BLOCKS &&
		 now_us() - start < (uint64_t)dwell_ms * 1000ULL);

	ret = ad9361_get_rx_rssi(ctx->phy, 0, &rssi);
	if (ret < 0 || rssi.multiplier <= 0) {
		out->rssi_cdb = WIFI_RF_RSSI_INVALID_CDB;
	} else {
		out->rssi_cdb = -(int32_t)(((uint64_t)rssi.symbol * 100U +
					      (uint32_t)rssi.multiplier / 2U) /
					     (uint32_t)rssi.multiplier);
	}
	out->gain_db = gain_db;
	out->dma_blocks = blocks;
	out->complex_samples = samples;
	out->clip_count = clips;
	out->power_cdbfs16 = wifi_rf_power_cdbfs16(sum_power / blocks);
	out->peak_cdbfs16 = wifi_rf_peak_cdbfs16(peak);
	out->baseline_median_power = mode == WIFI_RF_CAPTURE_BASELINE ?
		wifi_rf_median_u64(block_power, blocks) : baseline->baseline_median_power;
	threshold = out->baseline_median_power > UINT64_MAX / 4U ?
		UINT64_MAX : out->baseline_median_power * 4U;
	for (uint32_t n = 0; n < blocks; n++)
		if (block_power[n] > threshold) bursts++;
	out->burst_percent = (uint8_t)((bursts * 100U + blocks / 2U) / blocks);
	ctx->last_error = "NONE";
	return 0;
}
```

- [ ] **Step 6: Run capture static and native metric tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
```

Expected:

```text
PASS: Wi-Fi RF capture source enforces RX-only finite-DMA behavior.
PASS: Wi-Fi RF metrics deterministic vectors passed.
```

- [ ] **Step 7: Commit only capture files and their source test**

```powershell
git add -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.c PROJECT/tests/Test-Axu4evWifiRfSource.ps1
git commit --only -m "feat: add AD9364 RX-only channel capture" -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_capture.c PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

---

### Task 4: Add the UART scan, selection, monitor, and verdict state machine

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.c`
- Modify: `PROJECT/tests/Test-Axu4evWifiRfSource.ps1`

**Interfaces:**
- Consumes: Task 2 verdict API and Task 3 capture API.
- Produces: `int32_t wifi_rf_test_run(struct ad9361_rf_phy *, struct axi_dmac *, int16_t *, size_t)` returning `0` for PASS, `1` for INCONCLUSIVE, and a negative error for platform failure.

- [ ] **Step 1: Extend the source test with UART/state-machine invariants**

Append to `Test-Axu4evWifiRfSource.ps1` before its pass message:

```powershell
$testSource = Join-Path $sourceRoot 'wifi_rf_test.c'
$testHeader = Join-Path $sourceRoot 'wifi_rf_test.h'
foreach ($path in @($testSource, $testHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Wi-Fi RF test state machine: $path"
    }
}
$testContent = Get-Content -LiteralPath $testSource -Raw
foreach ($fragment in @(
    'Hotspot kapali',
    'Hotspot 2.4 GHz',
    'BASELINE_SCAN: START',
    'ACTIVE_SCAN: START',
    'SELECTED:',
    'MONITOR:',
    'PLATFORM: PASS',
    'RF_ACTIVITY: PASS',
    'RF_ACTIVITY: INCONCLUSIVE',
    'WIFI_RF_TEST: PASS',
    'WIFI_RF_TEST: INCONCLUSIVE',
    'XUartPs_IsReceiveData(STDIN_BASEADDRESS)',
    'WIFI_RF_MONITOR_WINDOWS'
)) {
    if (-not $testContent.Contains($fragment)) {
        throw "UART state machine is missing required fragment: $fragment"
    }
}
```

- [ ] **Step 2: Run the source test and verify the state-machine files are missing**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

Expected: FAIL with `Missing Wi-Fi RF test state machine`.

- [ ] **Step 3: Create the top-level test contract**

Create `wifi_rf_test.h`:

```c
#ifndef WIFI_RF_TEST_H
#define WIFI_RF_TEST_H

#include <stddef.h>
#include <stdint.h>

struct ad9361_rf_phy;
struct axi_dmac;

#define WIFI_RF_TEST_PASS 0
#define WIFI_RF_TEST_INCONCLUSIVE 1

int32_t wifi_rf_test_run(struct ad9361_rf_phy *phy,
			 struct axi_dmac *rx_dmac,
			 int16_t *iq_buffer,
			 size_t complex_samples);

#endif
```

- [ ] **Step 4: Implement UART helpers and channel reporting without float printf**

Start `wifi_rf_test.c` with:

```c
#include "wifi_rf_test.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>

#include "wifi_rf_capture.h"
#include "wifi_rf_metrics.h"
#include "no_os_delay.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"

#define WIFI_RF_MONITOR_WINDOWS 20U

static void wait_for_enter(void)
{
	char c;
	do {
		c = inbyte();
	} while (c != '\r' && c != '\n');
	no_os_mdelay(20);
	while (XUartPs_IsReceiveData(STDIN_BASEADDRESS))
		(void)inbyte();
}

static void print_centi_db(int32_t value)
{
	uint32_t magnitude;
	if (value == WIFI_RF_ZERO_CDBFS) {
		printf("-INF");
		return;
	}
	if (value < 0) {
		printf("-");
		magnitude = (uint32_t)(-(int64_t)value);
	} else {
		printf("+");
		magnitude = (uint32_t)value;
	}
	printf("%"PRIu32".%02"PRIu32, magnitude / 100U, magnitude % 100U);
}

static void print_channel(uint8_t channel,
			  const struct wifi_rf_channel_metrics *m)
{
	printf("CH=%02u FREQ=%"PRIu64"MHz GAIN=%"PRIi32"dB RSSI=",
	       channel, wifi_rf_channel_frequency_hz(channel) / 1000000ULL,
	       m->gain_db);
	if (m->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB)
		printf("ERROR");
	else
		print_centi_db(m->rssi_cdb);
	printf("dB PWR=");
	print_centi_db(m->power_cdbfs16);
	printf("dBFS16 PEAK=");
	print_centi_db(m->peak_cdbfs16);
	printf("dBFS16 CLIP=%"PRIu32" BURST=%u%% BLOCKS=%"PRIu32" DMA=OK\n",
	       m->clip_count, m->burst_percent, m->dma_blocks);
}

static int64_t activity_score(const struct wifi_rf_metric_delta *delta)
{
	int64_t rssi = delta->rssi_cdb != WIFI_RF_RSSI_INVALID_CDB &&
			delta->rssi_cdb > 0 ? delta->rssi_cdb : 0;
	int64_t power = delta->power_cdb > 0 ? delta->power_cdb : 0;
	int64_t burst = delta->burst_pp > 0 ? delta->burst_pp * 100LL : 0;
	return rssi + power + burst;
}
```

- [ ] **Step 5: Implement the two scans, channel selection, monitor, and final classification**

Append the top-level function:

```c
int32_t wifi_rf_test_run(struct ad9361_rf_phy *phy,
			 struct axi_dmac *rx_dmac,
			 int16_t *iq_buffer,
			 size_t complex_samples)
{
	struct wifi_rf_capture_ctx ctx;
	struct wifi_rf_channel_metrics baseline[WIFI_RF_CHANNEL_COUNT];
	struct wifi_rf_channel_metrics active[WIFI_RF_CHANNEL_COUNT];
	struct wifi_rf_channel_metrics monitor;
	struct wifi_rf_metric_delta selected_delta = {0};
	int64_t best_score = INT64_MIN;
	uint32_t monitor_hits = 0, selected = 0;
	uint32_t total_clip = 0, total_samples = 0;
	uint8_t current_channel = 0;
	int32_t ret;

	ret = wifi_rf_capture_init(&ctx, phy, rx_dmac, iq_buffer, complex_samples);
	if (ret < 0) goto sample_format_fail;
	ret = wifi_rf_prepare_rx_only(&ctx);
	if (ret < 0) goto rx_only_fail;
	printf("RX_ONLY: PASS port=RXB fs=30.72MSPS bw=18MHz\n");

	printf("Hotspot kapali olmali. Hazir oldugunuzda Enter'a basin.\n");
	wait_for_enter();
	printf("BASELINE_SCAN: START channels=1-13 dwell=250ms\n");
	for (uint32_t n = 0; n < WIFI_RF_CHANNEL_COUNT; n++) {
		uint8_t channel = (uint8_t)(n + WIFI_RF_FIRST_CHANNEL);
		current_channel = channel;
		ret = wifi_rf_capture_channel(&ctx, channel,
			WIFI_RF_CAPTURE_BASELINE, WIFI_RF_SCAN_DWELL_MS,
			NULL, &baseline[n]);
		if (ret < 0) goto channel_fail;
		print_channel(channel, &baseline[n]);
	}

	printf("Hotspot 2.4 GHz modunda acik ve trafik aktif olmali. Enter'a basin.\n");
	wait_for_enter();
	printf("ACTIVE_SCAN: START channels=1-13 dwell=250ms\n");
	for (uint32_t n = 0; n < WIFI_RF_CHANNEL_COUNT; n++) {
		uint8_t channel = (uint8_t)(n + WIFI_RF_FIRST_CHANNEL);
		struct wifi_rf_metric_delta delta;
		int64_t score;
		current_channel = channel;
		ret = wifi_rf_capture_channel(&ctx, channel,
			WIFI_RF_CAPTURE_ACTIVE, WIFI_RF_SCAN_DWELL_MS,
			&baseline[n], &active[n]);
		if (ret < 0) goto channel_fail;
		print_channel(channel, &active[n]);
		delta = wifi_rf_delta(&baseline[n], &active[n]);
		score = activity_score(&delta);
		if (score > best_score) {
			best_score = score;
			selected = n;
			selected_delta = delta;
		}
	}

	printf("SELECTED: CH=%02"PRIu32" FREQ=%"PRIu64"MHz DELTA_RSSI=",
	       selected + 1U, wifi_rf_channel_frequency_hz((uint8_t)(selected + 1U)) /
	       1000000ULL);
	if (selected_delta.rssi_cdb == WIFI_RF_RSSI_INVALID_CDB)
		printf("ERROR");
	else
		print_centi_db(selected_delta.rssi_cdb);
	printf("dB DELTA_PWR=");
	print_centi_db(selected_delta.power_cdb);
	printf("dB DELTA_BURST=%+"PRIi32"pp\n", selected_delta.burst_pp);
	printf("MONITOR: CH=%02"PRIu32" duration=10s\n", selected + 1U);
	total_clip = active[selected].clip_count;
	total_samples = active[selected].complex_samples;

	for (uint32_t n = 0; n < WIFI_RF_MONITOR_WINDOWS; n++) {
		current_channel = (uint8_t)(selected + 1U);
		ret = wifi_rf_capture_channel(&ctx, (uint8_t)(selected + 1U),
			WIFI_RF_CAPTURE_ACTIVE, WIFI_RF_MONITOR_DWELL_MS,
			&baseline[selected], &monitor);
		if (ret < 0) goto channel_fail;
		print_channel((uint8_t)(selected + 1U), &monitor);
		if (monitor.burst_percent > 0U) monitor_hits++;
		total_clip += monitor.clip_count;
		total_samples += monitor.complex_samples;
	}

	printf("PLATFORM: PASS\n");
	if (wifi_rf_classify(&selected_delta, monitor_hits, total_clip,
			     total_samples) == WIFI_RF_ACTIVITY_PASS) {
		printf("RF_ACTIVITY: PASS\nWIFI_RF_TEST: PASS\n");
		return WIFI_RF_TEST_PASS;
	}
	printf("RF_ACTIVITY: INCONCLUSIVE\nWIFI_RF_TEST: INCONCLUSIVE\n");
	if ((uint64_t)total_clip * 1000U > total_samples)
		printf("WARNING: clipping above 0.1%%; move hotspot farther from RXB.\n");
	else
		printf("WARNING: activity delta too small; verify 2.4 GHz client traffic and move hotspot closer.\n");
	return WIFI_RF_TEST_INCONCLUSIVE;

rx_only_fail:
	printf("PLATFORM: FAIL stage=RX_ONLY error=%"PRIi32"\n", ret);
	return ret;
channel_fail:
	printf("CH=%02u %s code=%"PRIi32"\n", current_channel,
	       ctx.last_error, ret);
	printf("PLATFORM: FAIL stage=CHANNEL_CAPTURE error=%"PRIi32"\n", ret);
	return ret;
sample_format_fail:
	printf("PLATFORM: FAIL stage=SAMPLE_FORMAT_ERROR error=%"PRIi32"\n", ret);
	return ret;
}
```

- [ ] **Step 6: Run state-machine source and metric regressions**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
```

Expected: both `PASS` lines.

- [ ] **Step 7: Commit only the state machine and updated source test**

```powershell
git add -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.c PROJECT/tests/Test-Axu4evWifiRfSource.ps1
git commit --only -m "feat: add interactive Wi-Fi RF scan" -- Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.h Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_test.c PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

---

### Task 5: Integrate the feature into the Release Vitis application and verify the ELF

**Files:**
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
- Modify: `Vitis/workspace/ad9364app/.cproject`
- Modify: `PROJECT/tests/Test-Axu4evWifiRfSource.ps1`
- Add to Git: `PROJECT/tests/Build-Axu4evAd9364App.ps1`

**Interfaces:**
- Consumes: `wifi_rf_test_run` from Task 4, existing `ad9361_phy`, `rx_dmac`, and aligned `adc_buffer`.
- Produces: `Vitis/workspace/ad9364app/Release/ad9364app.elf` with the Wi-Fi RF test enabled and no Wi-Fi-path TX initialization.

- [ ] **Step 1: Add failing integration invariants to the source test**

Append these checks to `Test-Axu4evWifiRfSource.ps1` before the final pass:

```powershell
$config = Get-Content -LiteralPath (Join-Path $sourceRoot 'app_config.h') -Raw
$main = Get-Content -LiteralPath (Join-Path $sourceRoot 'main.c') -Raw
$cproject = Get-Content -LiteralPath (Join-Path $root 'Vitis\workspace\ad9364app\.cproject') -Raw

foreach ($fragment in @(
    '#define WIFI_RF_TEST',
    '#if defined(WIFI_RF_TEST) && defined(DMA_EXAMPLE)',
    '#error "WIFI_RF_TEST and DMA_EXAMPLE cannot be enabled together"'
)) {
    if (-not $config.Contains($fragment)) { throw "Missing app config invariant: $fragment" }
}
foreach ($fragment in @(
    '#include "wifi_rf_test.h"',
    'status = ad9361_init(&ad9361_phy, &default_init_param);',
    '#ifndef WIFI_RF_TEST',
    'status = wifi_rf_test_run(ad9361_phy, rx_dmac,',
    'goto cleanup;',
    'cleanup:'
)) {
    if (-not $main.Contains($fragment)) { throw "Missing main integration fragment: $fragment" }
}
if (($cproject | Select-String -Pattern '<listOptionValue builtIn="false" value="m"/>' -AllMatches).Matches.Count -lt 2) {
    throw 'Both Debug and Release configurations must link libm.'
}
```

- [ ] **Step 2: Run the source test and verify integration is absent**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

Expected: FAIL on the missing `WIFI_RF_TEST` config or `main.c` integration fragment.

- [ ] **Step 3: Enable an exclusive Wi-Fi test build**

Add to `app_config.h` immediately below the existing demo feature switches:

```c
#define WIFI_RF_TEST

#if defined(WIFI_RF_TEST) && defined(DMA_EXAMPLE)
#error "WIFI_RF_TEST and DMA_EXAMPLE cannot be enabled together"
#endif
```

Leave `DMA_EXAMPLE` commented and keep `IIO_SUPPORT` disabled.

- [ ] **Step 4: Integrate init checking, RX-only DMAC setup, test execution, and cleanup**

In `main.c`:

1. Add `#include "wifi_rf_test.h"` with the local application includes.
2. Initialize `status` as `int32_t status = 0;`.
3. Replace the ignored AD9364 init call with:

```c
status = ad9361_init(&ad9361_phy, &default_init_param);
if (status < 0) {
	printf("PLATFORM: FAIL stage=AD9364_INIT error=%"PRIi32"\n", status);
	goto cleanup;
}
```

4. Wrap TX DMAC initialization with `#ifndef WIFI_RF_TEST` while leaving RX DMAC initialization unconditional:

```c
#ifndef WIFI_RF_TEST
status = axi_dmac_init(&tx_dmac, &tx_dmac_init);
if (status < 0) {
	printf("axi_dmac_init tx init error: %"PRIi32"\n", status);
	goto cleanup;
}
#endif
status = axi_dmac_init(&rx_dmac, &rx_dmac_init);
if (status < 0) {
	printf("axi_dmac_init rx init error: %"PRIi32"\n", status);
	goto cleanup;
}
```

5. Wrap the whole AXI DAC/DDS initialization block with `#ifndef WIFI_RF_TEST`.
6. Immediately after RX DMAC is ready and before the legacy DMA example, add:

```c
#ifdef WIFI_RF_TEST
status = wifi_rf_test_run(ad9361_phy, rx_dmac,
			  (int16_t *)adc_buffer,
			  NO_OS_ARRAY_SIZE(adc_buffer) / 2U);
goto cleanup;
#endif
```

7. Add `cleanup:` immediately before device removal, guard cleanup against a failed init, and retain cache disable. Use this exact shape and return `status`, not a hard-coded zero:

```c
cleanup:
	if (ad9361_phy)
		ad9361_remove(ad9361_phy);
#ifdef FMCOMMS5
	if (ad9361_phy_b)
		ad9361_remove(ad9361_phy_b);
#endif

#ifdef XILINX_PLATFORM
	Xil_DCacheDisable();
	Xil_ICacheDisable();
#endif
	return status;
```

- [ ] **Step 5: Link libm in the Release configuration**

In the Release C linker tool (`xilinx.gnu.arm.a53.c.toolchain.linker.release.140832304`), add the same library option already present in Debug:

```xml
<option id="xilinx.gnu.c.link.option.libs.wifi.release" name="Libraries (-l)" superClass="xilinx.gnu.c.link.option.libs" valueType="libs">
    <listOptionValue builtIn="false" value="m"/>
</option>
```

Do not alter BSP library ordering or the linker script.

- [ ] **Step 6: Run local source/metrics/launcher regressions**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1
```

Expected: four `PASS` results.

- [ ] **Step 7: Build the Release application through the verified XSCT path**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Build-Axu4evAd9364App.ps1
```

Expected:

```text
PASS: AD9364 application generated: ...\Vitis\workspace\ad9364app\Release\ad9364app.elf
```

The PowerShell wrapper is part of the reproducible build contract: it maps the long workspace to `P:`, temporarily rewrites the three Vitis metadata paths, invokes the tracked Tcl build, restores every metadata path in `finally`, removes `P:`, and requires a non-empty Release ELF. Before staging it, compare its current content to those invariants and run it successfully as above.

- [ ] **Step 8: Verify the Release ELF contains all feature entry points**

Run:

```powershell
$nm='C:\Xilinx\Vitis\2020.1\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-nm.exe'
$elf='Vitis\workspace\ad9364app\Release\ad9364app.elf'
$symbols=& $nm $elf
foreach($name in 'wifi_rf_test_run','wifi_rf_prepare_rx_only','wifi_rf_capture_channel','wifi_rf_analyze_block') {
    if($symbols -notmatch "\b$name$"){ throw "Missing ELF symbol: $name" }
}
'PASS: Release ELF contains Wi-Fi RF test entry points.'
```

Expected: `PASS: Release ELF contains Wi-Fi RF test entry points.`

- [ ] **Step 9: Commit only source integration and project metadata**

```powershell
git add -- Vitis/workspace/ad9364app/src/adc9364_src/app_config.h Vitis/workspace/ad9364app/src/adc9364_src/main.c Vitis/workspace/ad9364app/.cproject PROJECT/tests/Test-Axu4evWifiRfSource.ps1 PROJECT/tests/Build-Axu4evAd9364App.ps1
git commit --only -m "feat: integrate AD9364 Wi-Fi RF test app" -- Vitis/workspace/ad9364app/src/adc9364_src/app_config.h Vitis/workspace/ad9364app/src/adc9364_src/main.c Vitis/workspace/ad9364app/.cproject PROJECT/tests/Test-Axu4evWifiRfSource.ps1 PROJECT/tests/Build-Axu4evAd9364App.ps1
```

---

### Task 6: Run the real hotspot acceptance test and record the result

**Files:**
- Create after PASS: `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt`
- Modify after PASS: `PROJECT/implementation_plan.md`
- Modify after PASS: `PROJECT/project_situation_report.md`
- Modify after PASS: `chat_report.md`

**Interfaces:**
- Consumes: Candidate launcher and Release ELF from Tasks 1-5, the existing Golden release, JTAG, PS_UART, RXB antenna, and a phone hotspot forced to 2.4 GHz.
- Produces: repeatable UART proof with two consecutive `WIFI_RF_TEST: PASS` runs and updated project records; does not promote a new Golden release automatically.

- [ ] **Step 1: Re-run all non-hardware gates and Golden integrity tests**

Run:

```powershell
$tests=@(
 'PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1',
 'PROJECT/tests/Test-Axu4evWifiRfSource.ps1',
 'PROJECT/tests/Test-Axu4evLaunchWrappers.ps1',
 'PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1',
 'PROJECT/tests/Test-Axu4evRelease.ps1',
 'PROJECT/tests/Test-Axu4evHandoffArtifacts.ps1'
)
foreach($test in $tests){
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test
  if($LASTEXITCODE -ne 0){throw "Failed: $test"}
}
```

Expected: every script prints `PASS`; the Golden manifest hashes remain the values recorded in the source specification.

- [ ] **Step 2: Prepare the RF setup safely**

Perform exactly these physical checks:

```text
1. Connect one 2.4 GHz antenna to RXB only.
2. Leave RXA, TXA, and TXB unconnected.
3. Connect PS_UART and JTAG to the PC.
4. Open PuTTY on PS_UART with the previously verified serial settings.
5. Keep the phone hotspot off before launch.
6. Place the phone initially 1-3 metres from RXB; do not place it directly against the antenna.
```

- [ ] **Step 3: Launch Candidate mode and complete the first interactive run**

Double-click:

```text
PROJECT\tools\Start-Axu4evAd9364Candidate.cmd
```

Expected launcher result:

```text
PASS: PMUFW, FPGA, direct PS/DDR/PS-PL initialization, DDR gate and ad9364app were launched over JTAG.
PASS: Candidate launch completed. Check PS_UART in PuTTY.
```

In PuTTY:

1. Confirm `RX_ONLY: PASS` before pressing Enter.
2. Keep the hotspot off and press Enter for baseline.
3. Enable the phone hotspot in 2.4 GHz mode.
4. Connect a second device and create sustained traffic with a download, video, or speed test.
5. Press Enter for active scan and keep traffic running through the 10-second monitor.

Expected final lines:

```text
PLATFORM: PASS
RF_ACTIVITY: PASS
WIFI_RF_TEST: PASS
```

If `PLATFORM: PASS` and `RF_ACTIVITY: INCONCLUSIVE` appear, move the phone closer while avoiding direct contact, ensure real client traffic exists, and restart Candidate mode. If clipping exceeds 0.1%, move the phone farther away. Do not change thresholds to force a pass.

- [ ] **Step 4: Repeat from application launch for reproducibility**

Run Candidate mode again with the same physical setup and repeat baseline-off/active-on prompts. Expected: a second `WIFI_RF_TEST: PASS`, with the same selected channel or an adjacent channel caused by the 18 MHz measurement bandwidth.

- [ ] **Step 5: Save sanitized UART evidence**

Copy the complete first PuTTY run, execute the first prompt below, then copy the complete second PuTTY run and continue. This script extracts only the acceptance lines, verifies each run, and writes the evidence without SSIDs, credentials, payloads, tokens, or unrelated serial output:

```powershell
$evidence='PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt'
New-Item -ItemType Directory -Path (Split-Path $evidence) -Force | Out-Null

Read-Host 'Copy complete PuTTY Run 1 output, then press Enter here'
$run1=Get-Clipboard -Raw
Read-Host 'Copy complete PuTTY Run 2 output, then press Enter here'
$run2=Get-Clipboard -Raw

function Get-AcceptanceLines([string]$text,[string]$label) {
  $lines=@($text -split "`r?`n" | Where-Object {
    $_ -match '^(RX_ONLY:|SELECTED:|PLATFORM:|RF_ACTIVITY:|WIFI_RF_TEST:)'
  })
  foreach($required in 'RX_ONLY: PASS','SELECTED:','PLATFORM: PASS','RF_ACTIVITY: PASS','WIFI_RF_TEST: PASS') {
    if(-not ($lines -match [regex]::Escape($required))){throw "$label missing $required"}
  }
  return $lines
}

$accepted1=Get-AcceptanceLines $run1 'Run 1'
$accepted2=Get-AcceptanceLines $run2 'Run 2'
$header=@(
 'AXU4EVB-P + AD9364 Wi-Fi RF acceptance',
 'Date: 2026-07-16',
 'RF input: RXB / B_BALANCED',
 'Sample rate: 30.72 MSPS',
 'RX bandwidth: 18 MHz',
 'Hotspot: user-controlled 2.4 GHz, active client traffic',
 '', 'Run 1:'
)
@($header + $accepted1 + '' + 'Run 2:' + $accepted2) |
  Set-Content -LiteralPath $evidence -Encoding UTF8
Write-Output "PASS: sanitized RF evidence saved to $evidence"
```

- [ ] **Step 6: Update project reports without overwriting existing local edits**

Merge the accepted facts into the three existing reports:

```text
PROJECT/implementation_plan.md:
- Mark the initial RXB 2.4 GHz over-the-air RF proof complete.
- Record that FFT, continuous streaming, PetaLinux/IIO, and true dual antenna remain future phases.

PROJECT/project_situation_report.md:
- Record Candidate-mode Golden hardware + Release ELF architecture.
- Record two-pass UART acceptance and the evidence path.
- Reiterate AD9364 1x1 and I/Q-not-two-antennas.

chat_report.md:
- Record the design/plan decisions, safety configuration, implementation commits, build evidence, and both UART PASS runs.
```

Review the existing working-tree modifications first and add only compatible paragraphs; do not replace either report wholesale.

- [ ] **Step 7: Verify evidence and documentation contain no placeholders**

Run:

```powershell
$paths=@(
 'PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt',
 'PROJECT/implementation_plan.md',
 'PROJECT/project_situation_report.md',
 'chat_report.md'
)
foreach($path in $paths){
  $text=Get-Content -LiteralPath $path -Raw
  $forbidden=@(([char]60 + 'paste'),('T'+'BD'),('T'+'ODO'))
  foreach($token in $forbidden){if($text.Contains($token)){throw "Incomplete marker remains in $path"}}
}
'PASS: RF evidence and project reports are complete.'
```

Expected: `PASS: RF evidence and project reports are complete.`

- [ ] **Step 8: Commit only accepted evidence and compatible report updates**

```powershell
git add -- PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md
git commit --only -m "test: verify AD9364 2.4 GHz RF reception" -- PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md
```

- [ ] **Step 9: Stop before Golden promotion**

Report the candidate ELF hash, the two UART verdicts, and the commit hash to the user. Promotion to a new Golden release is a separate explicit user decision because the current Golden application remains the known bring-up fallback.

---

## Final Verification Checklist

- [ ] Candidate dry-run proves BIT, PMUFW, and `psu_init.tcl` hashes match current Golden while the application path is Release workspace ELF.
- [ ] Native metric vectors pass with `-Wall -Wextra -Werror`.
- [ ] Static source test proves RXB, maximum TX attenuation, RX ENSM, non-cyclic DMA, 500 ms timeout, fixed baseline gain reuse, and absence of TX DAC/DDS/DMAC behavior.
- [ ] Release Vitis build succeeds and the ELF contains all four RF test entry symbols.
- [ ] Golden release integrity and JTAG ordering regressions pass.
- [ ] Real board shows two consecutive `WIFI_RF_TEST: PASS` runs using controlled 2.4 GHz hotspot traffic.
- [ ] Evidence is sanitized, reports are merged without losing existing edits, and Golden promotion has not occurred implicitly.
