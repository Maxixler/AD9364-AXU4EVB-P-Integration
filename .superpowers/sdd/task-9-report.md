# Task 9 Report: Bare-metal PL FFT single-shot readout

## Outcome

Added a platform-independent callback-based MMIO driver for the AXU4EV PL FFT
control block and its two 2048 x 64-bit spectrum banks. The default application
mode remains `MONOPULSE_FOUNDATION_TEST`; `PL_FFT_SINGLE_SHOT` is explicitly
opt-in and exits before the existing TX DMAC/DDS path.

The Xilinx board adapter is isolated in `main.c` and uses Candidate-generated
`XPAR_*` base-address macros. It prints the required one-line result and can
optionally dump all 2048 words with `PL_FFT_UART_DUMP_BINS`.

## TDD evidence

RED was observed before either production source existed:

```text
Missing PL FFT driver source: .../pl_fft_control.c
```

The fake-MMIO host tests exposed and closed two related implementation defects:
sticky FFT errors were first cleared before capture, and a later review showed
that an error already present when `pl_fft_init()` ran was also silently
discarded. Initialization and capture now both W1C-clear the reported bits and
return `PL_FFT_ERR_HARDWARE`.

Final host coverage includes:

- configuration validation without a start pulse;
- bounded completion timeout followed by abort;
- W1C hardware-error handling during both initialization and capture;
- active-bank/valid-bank agreement;
- complete 2048-word 64-bit bank reads;
- frame/result-tag before/after consistency and bounded retry;
- bank release only after a stable copy;
- CRC extraction/comparison;
- signed peak real/imaginary unpacking;
- default foundation mode and opt-in PL FFT mode selection.

## Verification

```text
Test-Axu4evPlFftDriver.ps1
  PASS: pl_fft_control single-shot driver

Test-Axu4evMonopulseSource.ps1
  PASS

Test-Axu4evMonopulseFoundation.ps1
  PASS: monopulse foundation deterministic vectors passed.

Test-Axu4evWifiRfSource.ps1
  PASS: Wi-Fi RF capture host behavior passed.
  PASS: Wi-Fi RF capture and UART state-machine source/host behavior passed.
```

## Deferred board evidence

The current Golden Vitis platform intentionally has no FFT `XPAR_*` macros.
Task 10 must import the Candidate XSA, confirm the generated control/bank macro
names, build the opt-in ELF, and run the cabled low-power CW comparison. No
board-level PL FFT PASS is claimed by this task.
