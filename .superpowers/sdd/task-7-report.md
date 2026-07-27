# Task 7 Report: Complete single-shot PL FFT datapath

## Outcome

Implemented the complete ADC shadow capture path through the actual Vivado
2020.1 xFFT v9.1 IP, exact magnitude/peak calculation, atomic spectrum bank
publication, CPU-visible AXI-Lite registers, and command/result CDC mailboxes.
No generated XCI, simulation product, or Vivado cache is stored in the source
tree; the actual IP is generated in a disposable temporary project for the
top-level regression.

## TDD evidence

The top-level test and `top` runner entry were created before the production
top. The initial command was:

```powershell
powershell -ExecutionPolicy Bypass -File PROJECT/tests/Test-Axu4evFftRtl.ps1 -Test top
```

Expected RED observed:

```text
ERROR: [XSIM 43-4316] Can not find file: .../axi_ad9364_fft_capture.v
xvlog failed for top with exit code 1.
```

After implementation, the same gate generated `ad9364_fft_2048` from
`fft_v9_1_config.tcl`, compiled and elaborated the generated Xilinx VHDL model,
and checked all six manifest vectors.

## Implemented contracts

- Discrete non-backpressured ADC tap: `adc_valid`, `adc_enable`, signed
  `adc_i`, signed `adc_q`, and `rf_state`; no ready path exists toward ADI RX.
- Physical capture word remains `{Q[15:0], I[15:0]}`.
- The xFFT receives raw configuration `16'h0D57` once after ADC reset release.
- Capture, replay, xFFT, magnitude/peak, and bank ownership remain in
  `adc_clk`; AXI-Lite and both independent bank read ports remain in
  `s_axi_aclk`.
- Commands cross through a bundled-data command mailbox and completed metadata
  crosses through a bundled-data result mailbox.
- Publication occurs only after ordered bin 2047 storage and complete metadata.
- A held `frame_ready` from the preceding frame is gated during the next
  capture-start clear cycle, preventing stale-frame replay.

## End-to-end checks

For every case in `PROJECT/verification/fft/vectors/manifest.json` the bench
checks all 2048 xFFT component words, all 2048 64-bit power words, peak bin,
peak power, signed peak components, CRC-32, first sample, sample count, RF tag,
frame ID, active bank, DONE/error/overflow status, and atomic bank validity.
It also injects input gaps, forces internal FFT-output backpressure while ADC
traffic continues, issues a second START while busy, and proves a partial frame
never becomes CPU-visible.

Cases verified with zero mismatch:

- `zeros`
- `impulse`
- `tone_bin_137`
- `tone_bin_1901`
- `two_tone_tie`
- `near_full_scale`

## Final verification

```text
powershell ... Test-Axu4evFftRtl.ps1 -Test all
  PASS: adc_frame_capture
  PASS: adc_frame_replay
  PASS: magnitude_peak
  PASS: spectrum_pingpong
  PASS: fft_cdc
  PASS: fft_regs
  PASS: axi_ad9364_fft_capture single-shot
  exit 0

powershell ... Test-Axu4evFftIp.ps1
  PASS: FFT v9.1 configuration matches the numerical contract
  exit 0

python -m unittest discover -s PROJECT/tests -p "test_*.py" -v
  Ran 22 tests
  OK
```

The final actual-IP simulation published and verified the final
`near_full_scale` bank at simulation times 941.116 us and 986.502 us,
respectively, then printed the required top-level PASS marker.

## Independent-review hardening

The follow-up review was handled with a new strict RED: the testbench changed
the live RF pins after accepting a command and the first actual-IP result
failed at 119.053 us (`RESULT_TAG expected=00000002 actual=0000000c`).  The
command RF tag is now authoritative.

The result mailbox was widened to carry the epoch and all completion/error
flags atomically.  The CPU domain converts those flags into one-cycle events
for the sticky W1C status register, holds IRQ until a relevant W1C, and reports
BUSY while a command is pending as well as while the ADC pipeline is active.
The ADC domain validates the bundled command epoch locally, reserves a bank
before replay, propagates xFFT overflow, and uses the xFFT ARESETN port with a
three-cycle coordinated reset/reconfiguration path after abort, soft reset,
and normal completion.

The actual xFFT regression now covers a process abort and recovery, an
unreleased-bank rejection before replay, W1C/IRQ behavior, dropped-sample W1C,
a soft reset during processing with epoch 0 to 1, and live RF pins deliberately
different from the accepted command tag.  It then verifies all six manifest
frames and every FFT/power bin.  Final marker:

```text
PASS: axi_ad9364_fft_capture single-shot
$finish called at time : 1086748 ns
```

The real IP package script now requires `FFT_PACKAGE_OUTPUT_DIR`.  The positive
gate packages into a disposable directory and inspects AXI-Lite, both 11-bit
address/64-bit data BRAM ports, the discrete ADC ports, IRQ, all production RTL
files, and the generated xFFT XCI.  A before/after source-tree comparison proves
that packaging creates no products beside the RTL sources.

Additional final gates:

```text
PASS: FFT v9.1 configuration matches the numerical contract
PASS: positive disposable FFT package inspection
PASS: spectrum_pingpong infers block RAM
SYNTH_BANK: RAMB36=8 RAMB18=0 LUT_AS_MEMORY=0
Ran 22 tests in 0.649s -- OK
```

## Residual review closure

IRQ ownership now lives in the AXI-Lite register block and is derived from all
remaining sticky causes.  Targeted RED failed because `o_irq` did not exist;
the GREEN register test latches DONE and FFT_ERROR together, clears only DONE,
proves IRQ and FFT_ERROR remain, then clears FFT_ERROR and proves IRQ drops.

The actual-IP bench legally submits a START with a staged epoch that has not
been adopted by SOFT_RESET.  It observes CDC_FAULT with no capture, replay, or
bank publication, clears the fault, adopts the epoch, and completes subsequent
frames.  A controlled one-cycle xFFT event and accepted TUSER overflow bit also
prove atomic result payload bits FFT_ERROR[258] and OVERFLOW[259].  The injected
result exercises the same partial-W1C IRQ sequence at the integrated top.

The package output guard now rejects normalized paths equal to or below the RTL
source directory.  Its RED fixture reached ADI helper loading through a nested
path; the GREEN fixture fails immediately with the containment diagnostic.

Fresh closure evidence:

```text
PASS: fft_regs
PASS: Descendant output packaging path
PASS: positive disposable FFT package inspection
PASS: axi_ad9364_fft_capture single-shot (1087308 ns)
capture,replay,magnitude,bank,cdc,regs: exit 0
SYNTH_BANK: RAMB36=8 RAMB18=0 LUT_AS_MEMORY=0
Ran 22 tests in 0.592s -- OK
```
