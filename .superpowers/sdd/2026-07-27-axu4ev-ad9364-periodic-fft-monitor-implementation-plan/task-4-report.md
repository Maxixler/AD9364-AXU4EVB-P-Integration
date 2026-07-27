# Task 4 report — PuTTY log acceptance gate

## Scope

Implemented Task 4 only: a Windows PowerShell 5.1-compatible validator for
the periodic FFT monitor UART contract and a self-contained parser test with
one valid fixture and required negative fixtures.

## RED evidence

1. Added `Test-Axu4evPeriodicMonitorLogParser.ps1` before the validator.
   Running it failed as expected because
   `Test-Axu4evPeriodicMonitorLog.ps1` did not yet exist.
2. Added malformed extra START/PASS fixtures after the initial green result.
   The extra START case failed as expected because the first implementation
   ignored malformed additional START markers.  The validator was tightened
   to count all START/PASS markers as well as validate their exact contracts.

## GREEN evidence

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
# PASS: periodic FFT monitor log parser accepts only the complete contract.
```

The self-test accepts the complete 100-frame fixture and rejects 99 frames,
duplicate/skipped sequence values, non-increasing hardware frames, wrong
sample count, FAIL output, malformed extra START/PASS markers, missing final
PASS, and a frame after PASS.

## Commit and files

Commit: `test: validate periodic FFT UART logs`

- `PROJECT/tests/Test-Axu4evPeriodicMonitorLog.ps1`
- `PROJECT/tests/Test-Axu4evPeriodicMonitorLogParser.ps1`
- `.superpowers/sdd/2026-07-27-axu4ev-ad9364-periodic-fft-monitor-implementation-plan/task-4-report.md`

## Concerns / limits

- The validator operates on captured text logs only; no board, serial port,
  build, packaging, or deployment action was run.
- Pre-existing unrelated untracked workspace outputs were left untouched.
