# AXU4EV AD9364 Monopulse Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic, bit-true software foundation that converts four sequential monopulse spectra into a common carrier selection, four scalar powers, and signed Q1.31 AZ/EL errors without changing the verified Golden release.

**Architecture:** Consolidate the board-verified RX Candidate branch with the approved single-channel monopulse design in an isolated Candidate branch. Add three portable C units—spectrum selection, scalar error arithmetic, and four-state sequencing—then exercise the same units on the Windows host and Cortex-A53. The PL FFT, external switch GPIO binding, and chamber calibration remain separate follow-on plans because their electrical inputs are not yet available.

**Tech Stack:** Git worktrees, C11, MinGW GCC, PowerShell 5.1, Python 3.8+, NumPy, pyadi-iio/libIIO, Xilinx Vitis 2020.1, ADI no-OS AD9361/AD9364 drivers.

## Global Constraints

- Target hardware remains ALINX AXU4EVB-P plus the existing AD9364 1x1 RF card.
- Golden release `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1` is immutable.
- The board-verified `codex/wifi-rf-detection` RX capture path is the Candidate baseline and must retain its tests.
- Default sample rate is 30.72 MSPS; default RX bandwidth is 10 MHz and must later be confirmed by runtime readback.
- FFT length is exactly 2048 and a single FFT result path is time-shared across four analog states.
- State order is exactly `AZ_PLUS`, `AZ_MINUS`, `EL_PLUS`, `EL_MINUS`.
- CW mode uses one common peak derived from the sum of all four spectra and integrates bins `k_peak-2..k_peak+2`.
- Band-power mode integrates one configured inclusive bin interval for every state.
- AZ and EL outputs are signed Q1.31; a denominator below the configured threshold invalidates the corresponding axis.
- No per-bin divider, simultaneous digital dual RX, 90°/270° phase state, or full complex phase estimator is added.
- No external switch pin is assigned until the SPDT and bi-phase-switch part numbers, logic levels, active polarities, and settle times are verified.
- Every source change is test-first and committed independently; generated Vitis metadata, logs, binaries, and Golden artifacts are excluded.

---

## File Map

- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.h`: public scalar power and Q1.31 result contract.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.c`: saturating power sum, signed numerator, denominator gate, and Q1.31 division.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.h`: public spectrum configuration and result structures.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.c`: common peak, DC/search guards, CW integration, and band-power integration.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.h`: four-state identifiers and transition contract.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.c`: deterministic state ordering and switch-output mapping.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_selftest.h`: Cortex-A53 self-test entry point.
- `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_selftest.c`: deterministic on-target vectors and UART pass/fail markers.
- `PROJECT/tests/monopulse_foundation_test.c`: host unit tests for all portable C units.
- `PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1`: strict host compiler/test wrapper.
- `PROJECT/tests/Test-Axu4evMonopulseSource.ps1`: static Candidate safety and source-integration checks.
- `PROJECT/reference/monopulse_reference.py`: NumPy floating-point FFT/power/error oracle.
- `PROJECT/tools/capture_monopulse_iio.py`: pyadi-iio AD936X capture adapter for the later Linux/IIOD target.
- `PROJECT/tests/test_monopulse_reference.py`: Python oracle and mocked pyadi-iio configuration tests.
- `PROJECT/tests/Test-Axu4evMonopulsePython.ps1`: isolated Python test runner.
- `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`: mutually exclusive Candidate feature selection.
- `Vitis/workspace/ad9364app/src/adc9364_src/main.c`: invokes the monopulse self-test only when explicitly enabled.

## Task 1: Consolidate the Verified RX Baseline and Approved Design

**Files:**
- Preserve: `PROJECT/designs/2026-07-20-axu4ev-ad9364-single-channel-monopulse-design.md`
- Preserve: `PROJECT/axu4ev_ad9364_fft_rf_switch_nihai_plan.md`
- Import from `codex/wifi-rf-detection`: `Vitis/workspace/ad9364app/src/adc9364_src/wifi_rf_*.{c,h}`
- Import from `codex/wifi-rf-detection`: `PROJECT/tests/Test-Axu4evWifiRf*.ps1`
- Import from `codex/wifi-rf-detection`: `PROJECT/tests/wifi_rf_metrics_test.c`

**Interfaces:**
- Consumes: the current `codex/axu4ev-pmufw-bringup` HEAD containing design commit `96db472` plus this implementation plan, and branch `codex/wifi-rf-detection` at `d264bdd`.
- Produces: branch `codex/axu4ev-ad9364-monopulse` containing both histories and all passing RX tests.

- [ ] **Step 1: Create an isolated worktree from the approved design commit**

```powershell
git worktree add -b codex/axu4ev-ad9364-monopulse `
  C:\Users\DELL\.codex\worktrees\FPGA-Profen\axu4ev-ad9364-monopulse `
  codex/axu4ev-pmufw-bringup
```

Expected: a new worktree on `codex/axu4ev-ad9364-monopulse`; the dirty desktop checkout is unchanged.

- [ ] **Step 2: Merge the board-verified RX branch without committing**

```powershell
git merge --no-commit --no-ff codex/wifi-rf-detection
```

Expected: source/tool files merge automatically; conflicts are limited to project reports and launch-wrapper evolution.

- [ ] **Step 3: Resolve documentation conflicts using the approved design as authoritative**

Keep the complete content from commit `96db472` for the two binding design documents. In `implementation_plan.md`, `project_situation_report.md`, and `chat_report.md`, retain both the verified Wi-Fi RF evidence and the newer monopulse sections; do not remove either history.

```powershell
git diff --check
git diff --name-only --diff-filter=U
```

Expected: `git diff --check` prints nothing and the unresolved-file command prints nothing.

- [ ] **Step 4: Run the imported host regression**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evLaunchWrappers.ps1
```

Expected: each script exits `0`; the metrics test prints `PASS: Wi-Fi RF metrics deterministic vectors passed.`

- [ ] **Step 5: Commit the consolidated Candidate baseline**

```powershell
git add PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md `
  PROJECT/tests/Build-Axu4evAd9364App.ps1 `
  PROJECT/tests/Test-Axu4evLaunchWrappers.ps1 `
  PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1 `
  PROJECT/tests/Test-Axu4evWifiRfSource.ps1 `
  PROJECT/tests/wifi_rf_metrics_test.c `
  PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt `
  PROJECT/tools/Invoke-Axu4evAd9364Launch.ps1 `
  PROJECT/tools/Start-Axu4evAd9364Candidate.cmd `
  Vitis/workspace/ad9364app/.cproject `
  Vitis/workspace/ad9364app/src/adc9364_src
git commit -m "merge: consolidate verified RX and monopulse design"
```

Expected: the merge commit contains no generated `.metadata`, `Debug`, `Release`, `.log`, `.jou`, BIT, XSA, or ELF files.

## Task 2: Implement Saturating Scalar Monopulse Arithmetic

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.c`
- Create: `PROJECT/tests/monopulse_foundation_test.c`
- Create: `PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1`

**Interfaces:**
- Consumes: four unsigned 64-bit scalar powers and a nonzero unsigned 64-bit denominator threshold.
- Produces: `monopulse_compute_axis(uint64_t plus, uint64_t minus, uint64_t threshold, struct monopulse_axis_result *out)` and `monopulse_compute_result(const struct monopulse_power_set *powers, uint64_t threshold, struct monopulse_result *out)`.

- [ ] **Step 1: Write the failing public-contract test**

Create `PROJECT/tests/monopulse_foundation_test.c` with these exact arithmetic vectors:

```c
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "monopulse_math.h"

static void test_axis_vectors(void)
{
	struct monopulse_axis_result r;
	assert(monopulse_compute_axis(300, 100, 1, &r) == 0);
	assert(r.numerator == 200);
	assert(r.denominator == 400);
	assert(r.error_q31 == INT32_C(1073741824));
	assert(r.valid == 1U);

	assert(monopulse_compute_axis(100, 300, 1, &r) == 0);
	assert(r.numerator == -200);
	assert(r.error_q31 == -INT32_C(1073741824));

	assert(monopulse_compute_axis(200, 200, 1, &r) == 0);
	assert(r.error_q31 == 0);

	assert(monopulse_compute_axis(1, 0, 1, &r) == 0);
	assert(r.error_q31 == INT32_MAX);
	assert(monopulse_compute_axis(0, 1, 1, &r) == 0);
	assert(r.error_q31 == INT32_MIN);

	assert(monopulse_compute_axis(2, 1, 4, &r) == 0);
	assert(r.valid == 0U);
	assert((r.flags & MONOPULSE_AXIS_DENOMINATOR_SMALL) != 0U);
}

int main(void)
{
	test_axis_vectors();
	puts("PASS: monopulse foundation deterministic vectors passed.");
	return 0;
}
```

- [ ] **Step 2: Add the strict host wrapper and verify RED**

Create `PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1` so it finds `$env:MONOPULSE_GCC`, `gcc` on `PATH`, or `C:\MinGW\bin\gcc.exe`; compiles with `-std=c11 -Wall -Wextra -Werror`; runs the temporary executable; and removes it in `finally`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
```

Expected: FAIL because `monopulse_math.h` and `monopulse_math.c` do not exist.

- [ ] **Step 3: Add the minimal arithmetic interface**

Create `monopulse_math.h` with:

```c
#ifndef MONOPULSE_MATH_H
#define MONOPULSE_MATH_H

#include <stdint.h>

#define MONOPULSE_AXIS_DENOMINATOR_SMALL (UINT32_C(1) << 0)
#define MONOPULSE_AXIS_POWER_OVERFLOW    (UINT32_C(1) << 1)

struct monopulse_axis_result {
	int64_t numerator;
	uint64_t denominator;
	int32_t error_q31;
	uint32_t flags;
	uint8_t valid;
};

struct monopulse_power_set {
	uint64_t az_plus;
	uint64_t az_minus;
	uint64_t el_plus;
	uint64_t el_minus;
};

struct monopulse_result {
	struct monopulse_power_set powers;
	struct monopulse_axis_result az;
	struct monopulse_axis_result el;
};

int32_t monopulse_compute_axis(uint64_t plus, uint64_t minus,
			       uint64_t threshold,
			       struct monopulse_axis_result *out);
int32_t monopulse_compute_result(const struct monopulse_power_set *powers,
				 uint64_t threshold,
				 struct monopulse_result *out);

#endif
```

Implement `monopulse_math.c` with `-EINVAL` for null output or zero threshold, a saturating unsigned sum, a signed saturating difference, and a Q1.31 divide that maps `+1` to `INT32_MAX` and `-1` to `INT32_MIN`. Use quotient/remainder arithmetic or compiler-supported 128-bit temporaries without floating point.

- [ ] **Step 4: Run the test and add boundary vectors**

Add vectors for null arguments, zero threshold, `UINT64_MAX` sum overflow, full positive and negative scale, and independent AZ/EL computation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
```

Expected: PASS with the deterministic-vector marker and no compiler warnings.

- [ ] **Step 5: Commit scalar arithmetic**

```powershell
git add PROJECT/tests/monopulse_foundation_test.c PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1 Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.c Vitis/workspace/ad9364app/src/adc9364_src/monopulse_math.h
git commit -m "feat: add bit-true monopulse scalar arithmetic"
```

## Task 3: Implement the Four-State Sequence Contract

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.c`
- Modify: `PROJECT/tests/monopulse_foundation_test.c`
- Modify: `PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1`

**Interfaces:**
- Consumes: `enum monopulse_state_id`.
- Produces: `monopulse_state_outputs(enum monopulse_state_id state, struct monopulse_switch_outputs *out)` and `monopulse_next_state(enum monopulse_state_id state)`.

- [ ] **Step 1: Write failing state-map tests**

```c
static void test_state_sequence(void)
{
	static const struct monopulse_switch_outputs expected[4] = {
		{0U, 0U}, {0U, 1U}, {1U, 0U}, {1U, 1U}
	};
	struct monopulse_switch_outputs actual;
	enum monopulse_state_id state = MONOPULSE_AZ_PLUS;

	for (uint32_t n = 0; n < 4U; n++) {
		assert(monopulse_state_outputs(state, &actual) == 0);
		assert(actual.delta_select == expected[n].delta_select);
		assert(actual.phase_180 == expected[n].phase_180);
		state = monopulse_next_state(state);
	}
	assert(state == MONOPULSE_AZ_PLUS);
}
```

Expected after running the wrapper: FAIL because the sequence API is absent.

- [ ] **Step 2: Add the sequence interface and implementation**

Use this public contract:

```c
enum monopulse_state_id {
	MONOPULSE_AZ_PLUS = 0,
	MONOPULSE_AZ_MINUS = 1,
	MONOPULSE_EL_PLUS = 2,
	MONOPULSE_EL_MINUS = 3,
	MONOPULSE_STATE_COUNT = 4
};

struct monopulse_switch_outputs {
	uint8_t delta_select;
	uint8_t phase_180;
};

int32_t monopulse_state_outputs(enum monopulse_state_id state,
				struct monopulse_switch_outputs *out);
enum monopulse_state_id monopulse_next_state(enum monopulse_state_id state);
```

Invalid state/output arguments return `-EINVAL`; invalid input to `monopulse_next_state` returns `MONOPULSE_AZ_PLUS`.

- [ ] **Step 3: Run all host tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
```

Expected: PASS; all four state/output pairs and wrap-around are exact.

- [ ] **Step 4: Commit the state contract**

```powershell
git add PROJECT/tests Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.c Vitis/workspace/ad9364app/src/adc9364_src/monopulse_sequence.h
git commit -m "feat: define sequential monopulse state contract"
```

## Task 4: Implement Common-Peak and Band-Power Reference Processing

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.c`
- Modify: `PROJECT/tests/monopulse_foundation_test.c`
- Modify: `PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1`

**Interfaces:**
- Consumes: four `uint64_t[2048]` magnitude-square spectra and validated bin configuration.
- Produces: `monopulse_find_common_peak(...)`, `monopulse_integrate_cw(...)`, and `monopulse_integrate_band(...)`.

- [ ] **Step 1: Write failing common-peak tests**

Create four zeroed 2048-bin arrays, put unequal state contributions at bin 100, a larger single-state spur inside the DC guard, and equal common totals at bins 100 and 101. Assert that the lower-bin tie-break selects bin 100, the DC-guard spur is ignored, and CW integration returns each state's sum over bins 98 through 102.

```c
struct monopulse_spectrum_config cfg = {
	.fft_size = 2048U,
	.search_bin_start = 8U,
	.search_bin_stop = 1023U,
	.dc_guard_bins = 4U,
	.cw_half_width = 2U,
	.band_bin_start = 64U,
	.band_bin_stop = 511U
};
```

Expected: FAIL because the spectrum API is absent.

- [ ] **Step 2: Add the exact spectrum contract**

`monopulse_spectrum.h` defines:

```c
#define MONOPULSE_FFT_SIZE 2048U

struct monopulse_spectra {
	const uint64_t *state[MONOPULSE_STATE_COUNT];
};

struct monopulse_spectrum_config {
	uint32_t fft_size;
	uint32_t search_bin_start;
	uint32_t search_bin_stop;
	uint32_t dc_guard_bins;
	uint32_t cw_half_width;
	uint32_t band_bin_start;
	uint32_t band_bin_stop;
};

int32_t monopulse_find_common_peak(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t *peak_bin,
	uint64_t *peak_power);
int32_t monopulse_integrate_cw(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t peak_bin,
	struct monopulse_power_set *powers);
int32_t monopulse_integrate_band(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg,
	struct monopulse_power_set *powers);
```

All sums saturate at `UINT64_MAX`. Configuration is rejected with `-EINVAL` unless `fft_size == 2048`, intervals are inclusive and ordered, and CW integration remains inside the FFT array.

- [ ] **Step 3: Add band-power and negative tests**

Test exact inclusive band sums, all-zero spectra, null state pointers, reversed intervals, out-of-range bins, CW window underflow/overflow, and saturating accumulation.

- [ ] **Step 4: Run all host tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
```

Expected: PASS; common peak, CW integration, band power, sequence, and Q1.31 vectors all pass in one executable.

- [ ] **Step 5: Commit the spectrum reference**

```powershell
git add PROJECT/tests Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.c Vitis/workspace/ad9364app/src/adc9364_src/monopulse_spectrum.h
git commit -m "feat: add common-peak monopulse spectrum model"
```

## Task 5: Add the NumPy Oracle and pyadi-iio Capture Adapter

**Files:**
- Create: `PROJECT/reference/monopulse_reference.py`
- Create: `PROJECT/tools/capture_monopulse_iio.py`
- Create: `PROJECT/tests/test_monopulse_reference.py`
- Create: `PROJECT/tests/Test-Axu4evMonopulsePython.ps1`

**Interfaces:**
- Consumes: four complex NumPy frames or four power spectra; later consumes an IIO URI exposed by Linux/IIOD.
- Produces: floating-point common-peak/CW/band-power/AZ/EL reference values and `capture_ad936x(uri, sample_rate, bandwidth, lo_hz, gain_db, samples)`.

- [ ] **Step 1: Write failing Python reference tests**

Use `unittest` with deterministic NumPy arrays. Generate four 2048-sample complex exponentials at bin 100 with amplitudes whose powers are proportional to `300`, `100`, `100`, and `300`; assert the common peak is 100 and normalized AZ/EL values are `+0.5` and `-0.5` within `1e-12`. Add DC-guard, equal-peak lower-bin tie-break, off-bin tone, band-power, and denominator-threshold cases.

```powershell
python -m unittest PROJECT.tests.test_monopulse_reference -v
```

Expected: FAIL because `PROJECT.reference.monopulse_reference` does not exist.

- [ ] **Step 2: Implement the NumPy oracle**

Expose these exact functions:

```python
def spectra_from_frames(frames: np.ndarray, window: str = "rectangular") -> np.ndarray: ...
def find_common_peak(spectra: np.ndarray, search: tuple[int, int], dc_guard: int) -> tuple[int, float]: ...
def integrate_cw(spectra: np.ndarray, peak_bin: int, half_width: int = 2) -> np.ndarray: ...
def integrate_band(spectra: np.ndarray, band: tuple[int, int]) -> np.ndarray: ...
def normalized_errors(powers: np.ndarray, denominator_threshold: float) -> tuple[float, float]: ...
```

Require shapes `(4, 2048)`; use state order AZ+, AZ−, EL+, EL−; use inclusive bin intervals; reject non-finite input and invalid ranges with `ValueError`; select the lower index on a common-peak tie.

- [ ] **Step 3: Write a mocked pyadi-iio adapter test**

Inject a fake `adi` module whose `ad9361(uri=...)` object records assignments. Assert that `capture_ad936x` selects one RX channel, writes `sample_rate=30720000`, `rx_rf_bandwidth=10000000`, `rx_lo=<requested>`, `gain_control_mode_chan0="manual"`, `rx_hardwaregain_chan0=<requested>`, `rx_buffer_size=2048`, and returns one complex NumPy vector of length 2048.

- [ ] **Step 4: Implement the pyadi-iio adapter with a hard IIO gate**

Import `adi` only inside `capture_ad936x`. If the package or IIO context is unavailable, raise `RuntimeError("pyadi-iio requires a reachable Linux/IIOD IIO context")`. Construct the device with `adi.ad9361(uri=uri)` because official pyadi-iio support groups AD9364 under AD936X, configure RX only, and call `sdr.rx()` once. This adapter is not invoked by the current JTAG/bare-metal tests.

- [ ] **Step 5: Add the isolated Python runner**

`Test-Axu4evMonopulsePython.ps1` creates `.venv-monopulse` only when absent, installs `numpy>=1.20` and `pyadi-iio` when `-InstallDependencies` is supplied, otherwise uses the selected interpreter, then runs:

```powershell
python -m unittest PROJECT.tests.test_monopulse_reference -v
```

Expected: all pure NumPy and mocked pyadi-iio tests pass without requiring the board or a network connection.

- [ ] **Step 6: Cross-check Python and C vectors**

Write the four scalar powers and expected Q1.31 values to stdout in both test runners and assert identical integer results after applying `round(error * 2**31)` with saturation to `[INT32_MIN, INT32_MAX]`.

- [ ] **Step 7: Commit the Python verification layer**

```powershell
git add PROJECT/reference PROJECT/tools/capture_monopulse_iio.py PROJECT/tests/test_monopulse_reference.py PROJECT/tests/Test-Axu4evMonopulsePython.ps1
git commit -m "test: add NumPy and pyadi-iio monopulse oracle"
```

## Task 6: Integrate a Safe Cortex-A53 Candidate Self-Test

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_selftest.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/monopulse_selftest.c`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
- Modify: `Vitis/workspace/ad9364app/.cproject`
- Create: `PROJECT/tests/Test-Axu4evMonopulseSource.ps1`

**Interfaces:**
- Consumes: the three portable C units and the already initialized AD9364 application.
- Produces: `int32_t monopulse_selftest_run(struct ad9361_rf_phy *phy)`, runtime RF readback, and UART marker `MONOPULSE_FOUNDATION: PASS`.

- [ ] **Step 1: Write the failing static integration test**

`Test-Axu4evMonopulseSource.ps1` must assert:

```powershell
$required = @(
  '#define MONOPULSE_FOUNDATION_TEST',
  '#if defined(MONOPULSE_FOUNDATION_TEST) && defined(WIFI_RF_TEST)',
  'monopulse_selftest_run(ad9361_phy)',
  'MONOPULSE_RF: PASS',
  'MONOPULSE_FOUNDATION: PASS',
  'MONOPULSE_FOUNDATION: FAIL'
)
```

It must also reject any `axi_dac_set_datasel`, TX DMAC start, or external switch GPIO write inside `monopulse_selftest.c`.

Expected: FAIL before source integration.

- [ ] **Step 2: Add mutually exclusive Candidate flags**

In `app_config.h`, keep `WIFI_RF_TEST` available but enable only one mode:

```c
//#define WIFI_RF_TEST
#define MONOPULSE_FOUNDATION_TEST

#if defined(MONOPULSE_FOUNDATION_TEST) && defined(WIFI_RF_TEST)
#error "MONOPULSE_FOUNDATION_TEST and WIFI_RF_TEST cannot be enabled together"
#endif
#if defined(MONOPULSE_FOUNDATION_TEST) && defined(DMA_EXAMPLE)
#error "MONOPULSE_FOUNDATION_TEST and DMA_EXAMPLE cannot be enabled together"
#endif
```

- [ ] **Step 3: Add the on-target deterministic self-test**

`monopulse_selftest_run(struct ad9361_rf_phy *phy)` first reads sample rate, RX bandwidth, RX LO, RX gain, and TX attenuation with `ad9361_get_rx_sampling_freq`, `ad9361_get_rx_rf_bandwidth`, `ad9361_get_rx_lo_freq`, `ad9361_get_rx_rf_gain`, and `ad9361_get_tx_attenuation`. It requires `fs=30720000`, `bw=10000000`, and `tx_attenuation_mdB=89750`, then prints `MONOPULSE_RF: PASS fs=30720000 bw=10000000 lo=<readback> gain=<readback> tx_att=89750`. It feeds `AZ=(300,100)` and `EL=(100,300)` into `monopulse_compute_result`, verifies `AZ=+0.5` and `EL=-0.5` in Q1.31, verifies the four-state wrap-around, and prints exactly one foundation PASS marker on success. Each failure prints `MONOPULSE_FOUNDATION: FAIL stage=<name>` and returns `-EIO`.

- [ ] **Step 4: Invoke self-test after successful AD9364 initialization**

Before `ad9361_init`, set `default_init_param.rf_rx_bandwidth_hz = 10000000` and `default_init_param.tx_attenuation_mdB = 89750`; retain the existing verified RX clock vector whose final sampling entry is 30720000. In `main.c`, call `monopulse_selftest_run(ad9361_phy)` only inside `#ifdef MONOPULSE_FOUNDATION_TEST`, after `ad9361_init` succeeds and before any TX DAC/DDS initialization. Route the result through the existing cleanup path.

- [ ] **Step 5: Run host and static tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseSource.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
```

Expected: all scripts exit `0`; Wi-Fi source remains present but inactive while the monopulse foundation flag is selected.

- [ ] **Step 6: Build the Vitis Release application**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Build-Axu4evAd9364App.ps1
```

Expected: Release build exits `0` and creates `Vitis/workspace/ad9364app/Release/ad9364app.elf` without modifying Golden artifacts.

- [ ] **Step 7: Commit the A53 self-test integration**

```powershell
git add PROJECT/tests Vitis/workspace/ad9364app/.cproject Vitis/workspace/ad9364app/src/adc9364_src
git commit -m "feat: integrate monopulse foundation self-test"
```

## Task 7: Run the Candidate on the Board and Freeze the Foundation Contract

**Files:**
- Create: `PROJECT/tests/evidence/axu4ev-ad9364-monopulse-foundation-pass.txt`
- Modify: `PROJECT/project_situation_report.md`
- Modify: `PROJECT/implementation_plan.md`
- Modify: `chat_report.md`

**Interfaces:**
- Consumes: Candidate ELF from Task 5 and the existing verified JTAG launcher.
- Produces: repeatable UART evidence proving AD9364 initialization plus identical A53 arithmetic behavior.

- [ ] **Step 1: Launch Candidate mode with the Golden hardware artifacts**

```powershell
PROJECT\tools\Start-Axu4evAd9364Candidate.cmd
```

Expected launcher markers: DDR verification passes and the Candidate ELF is downloaded without replacing the Golden ELF.

- [ ] **Step 2: Capture UART evidence**

The UART log must include:

```text
ad9361_init : AD936x Rev 2 successfully initialized
MONOPULSE_RF: PASS fs=30720000 bw=10000000 lo=<readback> gain=<readback> tx_att=89750
MONOPULSE_FOUNDATION: PASS
```

It must not include `DMA_EXAMPLE:`, `WIFI_RF_TEST:`, `Read Error`, `Write Error`, or `PLATFORM: FAIL`.

- [ ] **Step 3: Repeat after a cold power cycle**

Power-cycle the board, reconnect PS_UART/JTAG, launch Candidate again, and require the same two success markers. Store both runs in the evidence file with date, branch, commit, BIT SHA-256, ELF SHA-256, and runtime Fs/BW/LO/gain readbacks.

- [ ] **Step 4: Update project records**

Record that the software foundation is accepted but the PL FFT, switch pins, settle/discard values, and chamber angle model remain later gated deliverables. Do not mark the complete monopulse product finished.

- [ ] **Step 5: Run the final regression**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseFoundation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseSource.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulsePython.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfMetrics.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evWifiRfSource.ps1
git diff --check
```

Expected: all tests pass and `git diff --check` prints nothing.

- [ ] **Step 6: Commit the accepted foundation evidence**

```powershell
git add PROJECT/tests/evidence/axu4ev-ad9364-monopulse-foundation-pass.txt PROJECT/implementation_plan.md PROJECT/project_situation_report.md chat_report.md
git commit -m "test: validate monopulse foundation on AXU4EV"
```

## Follow-On Plan Gates

This foundation plan intentionally ends before PL or external-control implementation. The next plan starts only after the following signed electrical contract is available:

- SPDT manufacturer and exact part number
- 0°/180° phase-switch manufacturer and exact part number
- Control voltage, VIH/VIL limits, active polarities, and safe power-up states
- Switching/settling time at the actual RF/IF frequency
- AXU4EVB-P connector/pin allocation and I/O-bank voltage confirmation
- BDC RF/LO/IF frequency plan and gain values

With those inputs, the next plan will instantiate the 2048-point FFT Candidate, map the two switch controls, implement settle/discard/capture/replay, compare RTL against the C oracle from this plan, and run chamber calibration.
