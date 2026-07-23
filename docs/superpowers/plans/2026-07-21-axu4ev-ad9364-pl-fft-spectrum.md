# AXU4EVB-P + AD9364 PL FFT Spectrum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a non-blocking 2048-point PL FFT shadow path to the verified AXU4EVB-P + AD9364 design, publish an atomic full-power spectrum and deterministic peak metadata, and validate single-shot then continuous ping-pong operation without regressing the existing DMA path.

**Architecture:** Tap only the validated `I0/Q0` output of `util_ad9361_adc_fifo` in the ADC clock domain. Capture complete 2048-sample frames into local RAM, replay them through FFT v9.1, calculate 33-bit power and peak data, and publish completed frames through dual-clock spectrum BRAM banks. AXI-Lite carries commands and metadata; AXI BRAM controllers carry the 2048-bin payload. The CPU and ADC clock domains exchange atomic command and result mailboxes with reset epochs. No signal from the new path may drive `ready`, `enable`, or backpressure into the existing ADI pack/DMAC chain.

**Tech Stack:** Vivado/Vitis 2020.1, Xilinx FFT v9.1 and its installed bit-accurate C model, Verilog-2001/SystemVerilog testbenches, XSIM, Python 3 with `ctypes`, `numpy`, and `unittest`, ADI HDL Tcl/IP conventions, and the existing bare-metal no-OS application.

**Global Constraints:** Preserve the Golden bitstream/XSA/ELF; build Candidate artifacts only. Preserve physical sample order `{Q[15:0], I[15:0]}` and signed Q1.15 interpretation. Use `NFFT=2048`, natural-order forward FFT, fixed 16-bit complex data, 24-bit twiddles, convergent rounding, and `SCALE_SCH=0x6AB`. Use rectangular windowing for closure; reserve but do not enable Hann. Store `Re^2+Im^2` in bits `[32:0]` of each 64-bit spectrum word. A frame becomes visible only after all 2048 bins and metadata are complete. Do not implement external RF control or S0-S3 sequencing in this plan.

## Fixed interfaces and register contract

The RTL library root is `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/`. Module names and signal directions below are binding for this implementation.

ADC-domain capture input:

```text
adc_clk, adc_resetn
adc_valid                 one-cycle source-valid indication
adc_enable                I0/Q0 sample-enable indication
adc_i[15:0], adc_q[15:0]  signed sample components
rf_state[2:0]             tag captured at command acceptance
```

AXI-Stream FFT boundary:

```text
s_axis_data_tdata[31:0] = {Q[15:0], I[15:0]}
s_axis_data_tvalid/tready/tlast
m_axis_data_tdata[31:0] = {Im[15:0], Re[15:0]}
m_axis_data_tvalid/tready/tlast
```

Control address map, byte offsets from the control AXI-Lite base:

| Offset | Name | Access | Contract |
|---:|---|---|---|
| `0x00` | `VERSION` | RO | `0x0001_0000` |
| `0x04` | `CONTROL` | RW/pulse | bit 0 `START`, 1 `ABORT`, 2 `SOFT_RESET`, 3 `MODE_CONTINUOUS`, 4 `BANK0_RELEASE`, 5 `BANK1_RELEASE` |
| `0x08` | `STATUS` | RO/W1C | bit 0 `BUSY`, 1 `DONE`, 2 `CDC_READY`, 3 `CDC_FAULT`, 4 `ABORTED`, 5 `FRAME_ERROR`, 6 `FFT_ERROR`, 7 `OVERFLOW`, 8 `DROPPED_SAMPLES`, 9 `BANK_OVERRUN`, 10 `CONFIG_ERROR` |
| `0x0C` | `SEARCH_RANGE` | RW | `[10:0] SEARCH_START`, `[26:16] SEARCH_STOP`, inclusive |
| `0x10` | `DC_GUARD_WINDOW` | RW | `[10:0] DC_GUARD`, `[17:16] WINDOW_SELECT`; only value 0 is accepted in this plan |
| `0x14` | `COMMAND_TAG` | RW | `[2:0] RF_STATE`, `[31:16] RESET_EPOCH` |
| `0x18` | `FRAME_ID` | RO | completed frame sequence number |
| `0x1C` | `RESULT_TAG` | RO | `[0] ACTIVE_BANK`, `[3:1] RF_STATE`, `[31:16] RESET_EPOCH` |
| `0x20` | `SAMPLE_COUNT` | RO | must equal 2048 for a valid frame |
| `0x24` | `PEAK_BIN` | RO | natural-order bin index |
| `0x28` | `PEAK_POWER_LO` | RO | peak power bits `[31:0]` |
| `0x2C` | `PEAK_POWER_HI` | RO | peak power bit 32 in bit 0 |
| `0x30` | `PEAK_RE_IM` | RO | `{PEAK_IM[15:0], PEAK_RE[15:0]}` |
| `0x34` | `FIRST_SAMPLE` | RO | `{Q0[15:0], I0[15:0]}` |
| `0x38` | `FRAME_CRC32` | RO | CRC-32/ISO-HDLC over 2048 input words in capture order |
| `0x3C` | `DROPPED_COUNT` | RO | saturating count of input samples rejected while unavailable |
| `0x40` | `BANK_VALID` | RO | bit 0 bank 0 valid, bit 1 bank 1 valid |

Configuration validity is `0 <= SEARCH_START <= SEARCH_STOP < 2048`, `DC_GUARD <= 1024`, and `WINDOW_SELECT=0`. A bad start request sets `CONFIG_ERROR` and does not start capture. DC exclusion applies to the natural-order bins `[0, DC_GUARD]` and `[2048-DC_GUARD, 2047]`; `DC_GUARD=0` excludes only bin 0.

The two AXI BRAM Controller segments each expose 2048 64-bit read-only spectrum words to software. Tcl assigns their addresses and Vitis consumes the generated `XPAR_*` macros; software must not hard-code physical base addresses.

## Task 1: Lock the official Xilinx FFT bit-accurate oracle

**Files:**

- Create: `PROJECT/verification/fft/model/__init__.py`
- Create: `PROJECT/verification/fft/model/xilinx_fft_cmodel.py`
- Create: `PROJECT/tests/test_xilinx_fft_cmodel.py`
- Modify: `PROJECT/tests/Test-Axu4evMonopulsePython.ps1`

- [x] **Step 1: Write failing discovery and schedule tests**

Add `unittest` cases that require:

```python
self.assertEqual(decode_scale_schedule(0x6AB, nfft=11), (3, 2, 2, 2, 2, 1))
self.assertEqual(sum(decode_scale_schedule(0x6AB, nfft=11)), 12)
self.assertTrue(discover_xfft_library().name.endswith("libIp_xfft_v9_1_bitacc_cmodel.dll"))
```

Run:

```powershell
python -m unittest PROJECT.tests.test_xilinx_fft_cmodel -v
```

Expected: `ImportError` or missing-module failure because the wrapper does not exist.

- [x] **Step 2: Implement DLL discovery and typed API binding**

Implement `discover_xfft_library()` using, in order, `XILINX_VIVADO`, `XILINX_VITIS`, then `C:\Xilinx\Vivado\2020.1`. Define local `ctypes.Structure` declarations for the documented generics, input, and output structures. Bind:

```python
xilinx_ip_xfft_v9_1_get_default_generics
xilinx_ip_xfft_v9_1_create_state
xilinx_ip_xfft_v9_1_destroy_state
xilinx_ip_xfft_v9_1_bitacc_simulate
```

Use generics `C_NFFT_MAX=11`, `C_ARCH=3`, `C_HAS_NFFT=0`, `C_USE_FLT_PT=0`, `C_INPUT_WIDTH=16`, `C_TWIDDLE_WIDTH=24`, `C_HAS_SCALING=1`, `C_HAS_BFP=0`, and `C_HAS_ROUNDING=1`. Always destroy state in `finally` or a context manager.

- [x] **Step 3: Add Q1.15 conversion and deterministic simulation API**

Expose:

```python
@dataclass(frozen=True)
class FftResult:
    real: np.ndarray
    imag: np.ndarray
    overflow: bool

def simulate_fft(i: np.ndarray, q: np.ndarray, scale_schedule: int = 0x6AB) -> FftResult:
    """Return 2048 natural-order signed int16 FFT components."""
```

Reject arrays not exactly 2048 long or values outside signed 16-bit range. Convert integers to the normalized doubles expected by the C model, call forward transform, and require every returned value to quantize exactly onto the signed 16-bit grid.

- [x] **Step 4: Test numerical invariants**

Add impulse, DC, positive-bin complex tone, negative-bin complex tone, near-full-scale, and zero tests. Check natural-order peak index, output type/range, overflow propagation, and repeated-call identity. The test suite may skip only when the official DLL is absent; on the project machine its absence is a hard failure in the PowerShell gate.

- [x] **Step 5: Add the oracle to the existing Python gate**

Update the PowerShell test to reject a skipped C-model suite on the project machine, then run:

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulsePython.ps1
```

Expected: existing 10 tests plus all FFT oracle tests pass.

- [x] **Step 6: Commit Task 1**

```powershell
git add PROJECT/verification/fft/model PROJECT/tests/test_xilinx_fft_cmodel.py PROJECT/tests/Test-Axu4evMonopulsePython.ps1
git commit -m "test: add Xilinx FFT bit-accurate oracle"
```

## Task 2: Freeze deterministic FFT vector and metadata formats

**Files:**

- Create: `PROJECT/verification/fft/model/generate_vectors.py`
- Create: `PROJECT/verification/fft/vectors/manifest.json`
- Create: `PROJECT/verification/fft/vectors/*.input.hex`
- Create: `PROJECT/verification/fft/vectors/*.fft.hex`
- Create: `PROJECT/verification/fft/vectors/*.power.hex`
- Create: `PROJECT/tests/test_fft_vectors.py`

- [x] **Step 1: Write failing manifest tests**

Require six named cases: `zeros`, `impulse`, `tone_bin_137`, `tone_bin_1901`, `two_tone_tie`, and `near_full_scale`. Verify each case records `nfft`, scaling, input CRC, expected overflow, search range, DC guard, peak bin, peak complex value, and peak power.

- [x] **Step 2: Implement reproducible generation**

Use fixed integer samples and the Task 1 oracle. Store input words as 8-hex-digit `{Q,I}`, FFT words as `{Im,Re}`, and power words as 16-hex-digit zero-extended unsigned values. Use uppercase hex, one word per line, LF endings, and deterministic JSON ordering.

- [x] **Step 3: Validate tie and guard behavior**

For equal peak power choose the lower eligible bin. Verify the DC guard removes both wrapped natural-order DC neighborhoods defined in the register contract.

- [x] **Step 4: Run and commit**

```powershell
python PROJECT/verification/fft/model/generate_vectors.py --check
python -m unittest PROJECT.tests.test_fft_vectors -v
git add PROJECT/verification/fft PROJECT/tests/test_fft_vectors.py
git commit -m "test: freeze FFT golden vectors"
```

Expected: generator reports `PASS: 6 FFT vector sets are reproducible` and tests pass.

## Task 3: Build the non-blocking 2048-sample capture and replay path

**Files:**

- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/adc_frame_capture.v`
- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/adc_frame_replay.v`
- Create: `PROJECT/verification/fft/rtl/tb_adc_frame_capture.sv`
- Create: `PROJECT/verification/fft/rtl/tb_adc_frame_replay.sv`
- Create: `PROJECT/tests/Test-Axu4evFftRtl.ps1`

- [x] **Step 1: Write capture tests before RTL**

The capture testbench must inject valid/enable gaps, try starts while busy, issue aborts at samples 1 and 2047, and prove that `frame_ready` asserts only after 2048 accepted samples. It must check first sample, sample count, dropped count, and CRC-32/ISO-HDLC against testbench values.

- [x] **Step 2: Prove the test fails**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test capture
```

Expected: compilation fails because `adc_frame_capture.v` is absent.

- [x] **Step 3: Implement capture as a passive sink**

Capture only on `adc_valid && adc_enable && armed`. Never expose a ready signal. Store exactly 2048 `{Q,I}` words in inferred true dual-port RAM, saturate the dropped counter, and freeze frame metadata at completion. `ABORT` invalidates the partial frame without publishing it.

- [x] **Step 4: Write replay stall tests before RTL**

Randomize `m_axis_tready`, verify all words remain stable under stall, verify exactly one `tlast` at word 2047, and ensure a new replay cannot begin before the previous handshake completes.

- [x] **Step 5: Implement replay and run both tests**

Replay stored data with AXI4-Stream-valid semantics. Run:

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test capture,replay
```

Expected: `PASS: adc_frame_capture` and `PASS: adc_frame_replay`.

- [x] **Step 6: Commit Task 3**

```powershell
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture PROJECT/verification/fft/rtl PROJECT/tests/Test-Axu4evFftRtl.ps1
git commit -m "feat: add non-blocking ADC frame capture"
```

## Task 4: Implement magnitude, peak, and spectrum bank primitives

**Files:**

- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/magnitude_peak.v`
- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/spectrum_pingpong.v`
- Create: `PROJECT/verification/fft/rtl/tb_magnitude_peak.sv`
- Create: `PROJECT/verification/fft/rtl/tb_spectrum_pingpong.sv`

- [x] **Step 1: Write failing magnitude/peak tests**

Drive FFT words from the checked-in vectors and check every 33-bit power word, `PEAK_BIN`, `PEAK_POWER`, `PEAK_RE`, and `PEAK_IM`. Exercise search boundaries, DC guard, lower-bin tie resolution, signed `-32768`, and output stalls.

- [x] **Step 2: Implement exact arithmetic**

Sign-extend both 16-bit components, calculate two unsigned 32-bit squares, add into 33 bits, and compare only eligible bins. Register candidate complex values with the winning power. Do not truncate power before comparison or storage.

- [x] **Step 3: Write failing bank ownership tests**

Cover single mode, alternating continuous frames, independent PS read clock, bank release, unread-bank collision, sticky overrun, aborted frames, and reset-epoch invalidation. Assert that bank-valid never changes before bin 2047 is written.

- [x] **Step 4: Implement atomic ping-pong publication**

Use two 2048x64 true dual-port inferred memories. PL owns the write port; CPU owns the read port. Publish metadata and valid toggle after the last write. In continuous mode choose a released bank; if neither is free, drop the new frame, preserve both completed banks, and set overrun.

- [x] **Step 5: Run and commit**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test magnitude,bank
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture PROJECT/verification/fft/rtl
git commit -m "feat: add exact FFT power and spectrum banks"
```

Expected: both testbenches print their `PASS` markers.

## Task 5: Implement atomic control/status CDC and AXI-Lite registers

**Files:**

- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/fft_command_cdc.v`
- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/fft_result_cdc.v`
- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/axi_ad9364_fft_regs.v`
- Create: `PROJECT/verification/fft/rtl/tb_fft_cdc.sv`
- Create: `PROJECT/verification/fft/rtl/tb_fft_regs.sv`

- [x] **Step 1: Write asynchronous-clock and reset tests**

Run CPU and ADC clocks at non-integer-related periods. Randomize start timing, assert one-sided resets, wrap mailbox toggles, and prove every accepted command/result transfers exactly once with an intact payload. Old epochs must be discarded.

- [x] **Step 2: Implement bundled-data mailboxes**

Hold command payload stable from request toggle until synchronized acknowledgement. Mirror the pattern for results. Synchronize only toggles/status bits individually; do not synchronize a changing multi-bit bus bit-by-bit. Mark synchronizer registers `ASYNC_REG`.

- [x] **Step 3: Write AXI-Lite protocol/register tests**

Test independent AW/W arrival, byte strobes, held B/R responses under backpressure, read-only protection, pulse generation, W1C status, invalid configuration rejection, and the exact fixed register map.

- [x] **Step 4: Implement AXI-Lite slave and run tests**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test cdc,regs
```

Expected: `PASS: fft_cdc` and `PASS: fft_regs`.

- [x] **Step 5: Commit Task 5**

```powershell
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture PROJECT/verification/fft/rtl
git commit -m "feat: add FFT control and result mailboxes"
```

## Task 6: Generate and lock the FFT v9.1 IP configuration

**Files:**

- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/axi_ad9364_fft_capture_ip.tcl`
- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/fft_v9_1_config.tcl`
- Create: `PROJECT/tests/Inspect-Axu4evFftIp.tcl`
- Create: `PROJECT/tests/Test-Axu4evFftIp.ps1`

- [x] **Step 1: Write a failing property inspection gate**

Create an in-memory Vivado project, source the IP Tcl, and assert transform length 2048, pipelined streaming architecture, fixed point, 16-bit data, 24-bit phase factor, natural order, convergent rounding, scaled arithmetic, and runtime config disabled.

- [x] **Step 2: Generate the IP through Tcl only**

Use `create_ip -name xfft -vendor xilinx.com -library ip -version 9.1` and explicit `set_property -dict`. Encode `0x6AB` on the configuration stream once after reset and before the first frame; fix forward direction. No GUI-generated project path may enter source control.

- [x] **Step 3: Package the custom RTL sources**

The library Tcl must enumerate source files explicitly and expose CPU AXI-Lite, dual bank BRAM read ports, ADC tap, and interrupts. It must fail immediately if an expected source or FFT IP is missing.

- [x] **Step 4: Run and commit**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftIp.ps1
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture PROJECT/tests/Inspect-Axu4evFftIp.tcl PROJECT/tests/Test-Axu4evFftIp.ps1
git commit -m "build: lock FFT v9.1 configuration"
```

Expected: `PASS: FFT v9.1 configuration matches the numerical contract`.

## Task 7: Integrate the complete single-shot RTL datapath

**Files:**

- Create: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/axi_ad9364_fft_capture.v`
- Create: `PROJECT/verification/fft/rtl/tb_axi_ad9364_fft_capture.sv`
- Modify: `PROJECT/tests/Test-Axu4evFftRtl.ps1`

- [x] **Step 1: Write end-to-end failing tests**

Feed each checked-in input vector through the ADC interface with gaps, stall the FFT output path, then read the published bank and result registers. Check all 2048 spectrum words, peak fields, CRC, first sample, sample count, RF tag, frame ID, active bank, overflow, done, and atomic valid timing.

- [x] **Step 2: Connect the modules and FFT instance**

Keep capture/replay/FFT/magnitude/bank in `adc_clk`. Keep AXI-Lite and bank read ports in `s_axi_aclk`. Use the command/result mailboxes at the boundary. Connect `m_axis_tready` so only internal storage can stall FFT; no reverse path may reach the ADI tap.

- [x] **Step 3: Add assertions for the shadow-path invariant**

Testbench assertions must prove input traffic continues while the FFT is stalled, starts while busy are rejected without corrupting the active frame, and a partial frame never changes the CPU-visible bank.

- [x] **Step 4: Run bit-exact cross-check and commit**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test top
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture PROJECT/verification/fft/rtl PROJECT/tests/Test-Axu4evFftRtl.ps1
git commit -m "feat: complete single-shot PL FFT datapath"
```

Expected: all six vector cases match with zero LSB difference and print `PASS: axi_ad9364_fft_capture single-shot`.

## Task 8: Integrate the shadow path into the FMCOMMS2 AXU4EV block design

**Files:**

- Modify: `Related-Docs/hdl-main/projects/fmcomms2/common/fmcomms2_bd.tcl`
- Modify: `Related-Docs/hdl-main/projects/fmcomms2/axu4ev/system_project.tcl`
- Create: `PROJECT/tests/Inspect-Axu4evFftBlockDesign.tcl`
- Create: `PROJECT/tests/Test-Axu4evFftBlockDesign.ps1`
- Modify: `PROJECT/tests/Build-Axu4evAd9364Bitstream.tcl`

- [x] **Step 1: Write a failing structural gate**

Require one FFT capture instance, two AXI BRAM Controllers, control and bank address segments, CPU reset/clock connections, ADC clock/reset connections, and only I0/Q0 tap nets. Snapshot all existing `util_ad9361_adc_fifo -> util_ad9361_adc_pack` and pack-to-DMAC connections and assert they are unchanged.

- [x] **Step 2: Add the RTL/IP instances without editing generated BD files**

Source only checked-in Tcl. Connect the tap to `util_ad9361_adc_fifo/dout_valid_0`, `/dout_enable_0`, `/dout_data_0`, and `/dout_data_1`; validate in the generated BD that these are I0 and Q0 before accepting the build. Connect CPU AXI through the existing interconnect and let `assign_bd_address` allocate segments.

- [x] **Step 3: Generate a clean Candidate design**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftBlockDesign.ps1
```

Expected: `PASS: FFT shadow path is present and the Golden DMA topology is unchanged`.

- [x] **Step 4: Build Candidate bitstream and inspect closure**

```powershell
C:\Xilinx\Vivado\2020.1\bin\vivado.bat -mode batch -source PROJECT/tests/Build-Axu4evAd9364Bitstream.tcl -tclargs candidate_fft
```

Require zero critical warnings attributable to the new CDC or BRAM interfaces, zero DRC errors, non-negative worst setup/hold slack, and a utilization report recording FFT DSP/BRAM/LUT/FF use. Do not overwrite the Golden bitstream/XSA.

- [x] **Step 5: Commit Task 8**

```powershell
git add Related-Docs/hdl-main/projects/fmcomms2 PROJECT/tests
git commit -m "feat: integrate FFT shadow path into AXU4EV design"
```

## Task 9: Add the bare-metal single-shot driver and UART evidence

**Files:**

- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.c`
- Create: `PROJECT/tests/pl_fft_control_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftDriver.ps1`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`

- [x] **Step 1: Write host-side failing register-driver tests**

Use a fake MMIO array to test configuration validation, start pulse, timeout, W1C error handling, bank-valid selection, 2048-word reads, metadata-before/after consistency, bank release, CRC comparison, and signed peak unpacking.

- [x] **Step 2: Implement a platform-independent MMIO core**

Use generated `XPAR_*` base macros only in the board adapter. Provide:

```c
int pl_fft_init(struct pl_fft_device *dev);
int pl_fft_capture_once(struct pl_fft_device *dev,
                        uint16_t search_start,
                        uint16_t search_stop,
                        uint16_t dc_guard,
                        uint8_t rf_state,
                        struct pl_fft_result *result,
                        uint64_t spectrum[2048]);
```

Reject torn reads by reading `FRAME_ID` and `RESULT_TAG` before and after the bank copy and retrying only within a bounded timeout.

- [x] **Step 3: Add explicit application mode**

Preserve `MONOPULSE_FOUNDATION` behavior. Add compile-time `PL_FFT_SINGLE_SHOT` mode that captures one frame and prints one summary line plus optional full-bin UART dump. The default remains the already verified foundation mode until Candidate hardware is loaded.

- [x] **Step 4: Run source/host tests and commit**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evPlFftDriver.ps1
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evMonopulseSource.ps1
git add Vitis/workspace/ad9364app/src/adc9364_src PROJECT/tests
git commit -m "feat: add bare-metal PL FFT readout"
```

Expected: host tests pass and existing monopulse source gate remains green.

## Task 10: Validate single-shot behavior on the board

**Files:**

- Create: `PROJECT/tests/Validate-Axu4evPlFftJtag.tcl`
- Create: `PROJECT/tests/Invoke-Axu4evPlFftValidation.ps1`
- Create: `PROJECT/verification/fft/model/compare_uart_spectrum.py`
- Create: `PROJECT/verification/fft/reports/.gitignore`

- [ ] **Step 1: Add Candidate-only JTAG launch**

Reuse the proven PMUFW, PS initialization, DDR verification, FPGA programming, and A53 launch ordering, but require Candidate bitstream/XSA/ELF paths. Abort if any path resolves to a Golden artifact.

- [ ] **Step 2: Run a cabled low-power CW test**

Use the Rohde & Schwarz generator at the measured AD9364 receive frequency, begin at a safe low level with attenuation, and verify no clipping. Capture the same observation interval through the existing DMA diagnostic and the PL FFT path.

- [ ] **Step 3: Cross-check identity and numerical results**

Require matching first-sample imprint and CRC between DMA-derived input and PL metadata. Re-run the official C model over DMA input and require all 2048 power bins and peak fields to match the PL output exactly.

- [ ] **Step 4: Save evidence and commit automation**

The script writes timestamped logs and JSON summaries under ignored `PROJECT/verification/fft/reports/`. Commit only scripts and report schema:

```powershell
git add PROJECT/tests PROJECT/verification/fft/model PROJECT/verification/fft/reports/.gitignore
git commit -m "test: automate board-level PL FFT validation"
```

Expected UART summary: `PL_FFT: PASS frame=<n> bank=<0|1> peak_bin=<n> crc=<hex>`.

## Task 11: Enable and close continuous ping-pong mode

**Files:**

- Modify: `Related-Docs/hdl-main/library/axi_ad9364_fft_capture/axi_ad9364_fft_capture.v`
- Modify: `PROJECT/verification/fft/rtl/tb_axi_ad9364_fft_capture.sv`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.c`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.h`
- Modify: `PROJECT/tests/pl_fft_control_test.c`

- [ ] **Step 1: Add failing continuous-mode tests**

Run at least 100 frames with randomized CPU service latency. Verify monotonic frame IDs, strict bank ownership, correct release, no torn data, intentional overrun behavior, recovery after overrun clear, and single-shot compatibility.

- [ ] **Step 2: Implement continuous re-arm**

After publishing a frame, automatically arm capture only when an output bank can eventually accept the next completed spectrum. Never block ADC input; count/drop complete capture opportunities when resources are unavailable and expose sticky status.

- [ ] **Step 3: Add a bounded software consumer**

Provide polling APIs that return `NO_FRAME`, `FRAME_READY`, or a typed error without unbounded waits. Release a bank only after copying all 2048 words and rechecking its metadata.

- [ ] **Step 4: Run regressions and commit**

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test all
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evPlFftDriver.ps1
python -m unittest discover -s PROJECT/tests -p "test_*.py" -v
git add Related-Docs/hdl-main/library/axi_ad9364_fft_capture Vitis/workspace/ad9364app/src/adc9364_src PROJECT/verification/fft/rtl PROJECT/tests
git commit -m "feat: enable continuous FFT spectrum capture"
```

Expected: all single-shot tests still pass and continuous test prints `PASS: 100 atomic FFT frames`.

## Task 12: Final verification, documentation, and handoff

**Files:**

- Modify: `PROJECT/implementation_plan.md`
- Modify: `PROJECT/project_situation_report.md`
- Modify: `PROJECT/axu4ev_ad9364_fft_rf_switch_nihai_plan.md`
- Modify: `chat_report.md`
- Create: `PROJECT/verification/fft/README.md`

- [ ] **Step 1: Run the complete non-hardware regression**

```powershell
python -m unittest discover -s PROJECT/tests -p "test_*.py" -v
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test all
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftIp.ps1
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftBlockDesign.ps1
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evPlFftDriver.ps1
```

Expected: every gate prints `PASS` and no test is skipped on the project machine.

- [ ] **Step 2: Run Candidate implementation and board acceptance**

Require DRC/timing closure, exact DMA topology preservation, successful Golden launch regression, successful Candidate single-shot test, and successful Candidate continuous test. Record tool versions, Git commit, bitstream SHA-256, XSA SHA-256, ELF SHA-256, RF settings, and UART/log paths.

- [ ] **Step 3: Update project records with evidence, not intent**

Mark only demonstrated requirements complete. Record exact resource utilization, timing slack, tested sample rate/bandwidth, peak-bin error, power-bin equality, dropped/overrun counts, and the remaining RF-control prerequisites.

- [ ] **Step 4: Check documentation and repository hygiene**

```powershell
rg -n "TODO|TBD|PLACEHOLDER|FIXME" docs/superpowers PROJECT Related-Docs/hdl-main/library/axi_ad9364_fft_capture Vitis/workspace/ad9364app/src/adc9364_src
git diff --check
git status --short
```

Expected: no unresolved placeholder in the implemented scope, no whitespace errors, and only intentional files are modified.

- [ ] **Step 5: Commit the handoff**

```powershell
git add PROJECT/implementation_plan.md PROJECT/project_situation_report.md PROJECT/axu4ev_ad9364_fft_rf_switch_nihai_plan.md PROJECT/verification/fft/README.md chat_report.md
git commit -m "docs: close PL FFT spectrum milestone"
```

## Exit criteria for this plan

This plan is complete only when:

1. The existing Golden DMA application still produces its verified AD9364/DMA output.
2. Candidate hardware publishes all 2048 spectrum bins atomically with exact metadata.
3. Official Xilinx C-model comparison shows zero LSB difference for FFT components, power bins, and peak fields on deterministic vectors and a board-captured frame.
4. Single-shot and 100-frame continuous ping-pong tests pass without torn reads.
5. DRC and timing pass, CDC assumptions are structurally tested, and actual utilization is recorded.
6. No external RF-control behavior is claimed; the next plan begins only after the BDC IF, level shifting, pins, settle time, and phase-shifter truth table are electrically confirmed.
