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

## Review round 1 fix — malformed FRAME markers and PASS ordering

### RED evidence

1. Added fixtures with a TAB after `FRAME`, no delimiter after `FRAME`, and
   a `FRAMEX` marker.  Before the fix, the TAB case was accepted because the
   validator only collected the literal `FRAME ` spelling and treated the
   malformed protocol line as unrelated noise.
2. Replaced the old frame-after-PASS fixture, which had 101 frames, with a
   100-frame log containing frames 001..099 before PASS and frame 100 after
   PASS.  This isolates the ordering rejection from the frame-count check.

### Fix and GREEN evidence

- A line beginning `PL_FFT_MONITOR: FRAME` is now always considered a frame
  protocol marker.  Each such marker must match the anchored required frame
  syntax before the count/order checks run.  Non-protocol UART noise remains
  allowed.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
# PASS: periodic FFT monitor log parser accepts only the complete contract.
```

No board, serial-port, build, packaging, or deployment action was run.

## Review round 3 fix — trimmed protocol-token classification

### RED evidence

Added fixtures with a missing colon (`PL_FFT_MONITOR FRAME`), semicolon
delimiter, and leading whitespace before a FRAME record.  The missing-colon
fixture was accepted by the prior delimiter-based namespace detector.

### Fix and GREEN evidence

- Protocol-like detection now checks whether `TrimStart()` begins with the
  `PL_FFT_MONITOR` token (case-insensitively).  It validates the original,
  untrimmed line against exact case-sensitive START, FRAME, and PASS forms;
  any FAIL line rejects immediately.  Thus a leading space, missing/replaced
  delimiter, or appended namespace form cannot become harmless noise.
- Added a positive fixture with `UART noise: PL_FFT_MONITOR: ...`; because the
  namespace token occurs after other text, it remains unrelated UART noise and
  is accepted.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
# PASS: periodic FFT monitor log parser accepts only the complete contract.

# Targeted missing-delimiter and leading-whitespace records
# PASS: targeted missing-delimiter and leading-whitespace records were rejected.
```

No board, serial-port, build, packaging, or deployment action was run.

## Review round 2 fix — namespace-level protocol validation

### RED evidence

Added a valid log plus `PL_FFT_MONITOR:  FRAME ...` (two spaces after the
colon).  The pre-fix validator exited zero because it only recognized the
exact single-space FRAME header and ignored this malformed namespace record.

### Fix and GREEN evidence

- Lines in the `PL_FFT_MONITOR` namespace are now detected with
  whitespace-tolerant, case-insensitive namespace recognition.  Acceptance is
  still case-sensitive: each detected protocol line must be an exact START,
  PASS, anchored FRAME, or FAIL record; FAIL is subsequently rejected.
- Added TAB-after-colon and space-before-colon FRAME fixtures in addition to
  the double-space case.  Unrelated lines outside the protocol namespace are
  still permitted.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evPeriodicMonitorLogParser.ps1
# PASS: periodic FFT monitor log parser accepts only the complete contract.

# Targeted valid log plus "PL_FFT_MONITOR:  FRAME ..."
# PASS: targeted malformed namespace record was rejected.
```

No board, serial-port, build, packaging, or deployment action was run.
