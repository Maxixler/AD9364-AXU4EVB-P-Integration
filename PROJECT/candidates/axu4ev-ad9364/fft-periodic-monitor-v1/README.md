# AXU4EV AD9364 periodic FFT monitor Candidate

This is the `fft-periodic-monitor-v1` Candidate bundle for the AXU4EVB-P
with AD9364. It contains the periodic-monitor ELF and the byte-identical
hardware handoff used by the accepted `fft-single-shot-v1` Candidate.

`board_verified=true`: this bundle passed the 27 July 2026 physical monitor
transport/control acceptance. The committed evidence is
`PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt`.
This is not RF-performance, antenna/port-wiring, or DOA-calibration
acceptance: no controlled CW/R&S source was declared and the antenna/port
wiring was not independently reverified during this run.

## Run on the board

1. Connect JTAG and the PS UART, power the board, and open PuTTY at
   **115200-8-N-1** on the PS UART.
2. From the project root, run:

   ```powershell
   .\PROJECT\tools\Start-Axu4evAd9364PeriodicMonitor.cmd
   ```

3. Watch PuTTY. The monitor prints `PL_FFT_MONITOR: START`, then 100
   `PL_FFT_MONITOR: FRAME` lines at roughly one-second intervals, followed
   by `PL_FFT_MONITOR: PASS frames=100 interval_ms=1000`.

The run takes approximately 100 seconds. It fails fast: the first capture,
validation, or reporting error ends the monitor with a `PL_FFT_MONITOR: FAIL`
line; do not restart the CMD while a 100-frame run is active.

> The CMD/XSCT "launch completed" message means only that the ELF started.
> Board acceptance requires the final PL_FFT_MONITOR: PASS line in PuTTY.

The acceptance evidence is checked by the strict parser and by
`PROJECT\tests\Test-Axu4evPeriodicMonitorPackage.ps1`; a true
`board_verified` manifest requires that committed evidence and its matching
artifact metadata.
