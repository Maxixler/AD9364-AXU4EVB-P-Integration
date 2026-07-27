# Task 7 report — periodic FFT monitor physical acceptance

Date: 2026-07-27 (Europe/Istanbul)

Physical run: AXU4EVB-P + AD9364, branch
`codex/axu4ev-ad9364-monopulse`, launch commit
`b0f53f36f8676b54747d417c4ae44c61ac8a3c99`.

Evidence sources:

- PuTTY PS_UART session: `C:\Users\DELL\Desktop\putty-periodic.log`
  (115200-8-N-1, all session output).
- JTAG launch: `PROJECT/logs/jtag/20260727-132857-candidate.log`.
- Committed evidence: `PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-pass.txt`.

Fresh strict validation command and result:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 -LogPath C:\Users\DELL\Desktop\putty-periodic.log
# PASS: periodic FFT monitor log contains 100 valid frames.
```

The evidence record includes AD9364 initialization, the exact START line, all
100 raw FRAME records, and final PASS. `board_verified=true` is protected by
`Test-Axu4evPeriodicMonitorPackage.ps1`: it requires the committed evidence,
expected metadata/hash linkage, and a fresh strict-parser PASS. False remains
the valid pre-acceptance manifest state and does not require evidence.

Accepted hashes (unchanged):

- application ELF: `0586E9A18EA4457A622CEE84D33F81A6402C95FB12A64755D2A7C39441964002`
- bitstream: `ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC`

Post-commit verification includes strict validation of the committed evidence,
periodic package and launch gates, unchanged single-shot Candidate launch,
Candidate dry-run, release gate, and focused preflight tests.

Commit: `test: accept periodic FFT monitor on hardware`.

Concerns and scope: no controlled CW/R&S source was declared. Observed low
peak powers are treated as ambient-noise input. Antenna/port wiring was not
independently reverified during this run. This accepts monitor
transport/control only; it does not accept RF performance, antenna wiring,
DOA, or calibration.
