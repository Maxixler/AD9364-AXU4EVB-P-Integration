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
