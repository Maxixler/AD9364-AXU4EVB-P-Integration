# Final Release-Hardening Report

## Scope

- Bound physical periodic-monitor acceptance to the exact five artifacts
  recorded by the committed JTAG launch manifest.
- Rejected a stale JTAG application record even when the in-memory Candidate
  manifest and evidence metadata claim a replacement ELF.
- Required the trusted single-shot reference to be clean and to match both
  `HEAD` and the Git index before a periodic build reads it. The selected
  Candidate output root remains the only exempt output path.
- Pinned both hash-bound `psu_init.tcl` files to CRLF materialization without
  changing either accepted artifact blob or manifest hash.

## TDD evidence

RED was observed for the missing deterministic `psu_init` attribute policy and
for stale JTAG application evidence being accepted. A disposable Git fixture
then demonstrated the reference-source defect: it edited the reference PMUFW
and made its manifest self-consistent, and the periodic dry-run accepted it
before the provenance gate was added. The fixture also demonstrates that a
dirty selected output root remains allowed.

## Fresh verification

- `Test-Axu4evCandidateBuild.ps1` — PASS.
- `Test-Axu4evPeriodicMonitorPackage.ps1` — PASS.
- `Test-Axu4evPlFftMonitor.ps1` — PASS, including every report callback
  sequence from 1 through 100.
- `Test-Axu4evPlFftDriver.ps1` — PASS.
- `Test-Axu4evPeriodicMonitorLogParser.ps1` — PASS.
- `Test-Axu4evPeriodicMonitorLog.ps1` — PASS for both committed raw UART log
  and committed acceptance-evidence log.
- `Test-Axu4evPeriodicMonitorLaunch.ps1` and
  `Test-Axu4evCandidateLaunch.ps1` — PASS.
- `git diff --check c263389..HEAD` — PASS. The protected single-shot Candidate
  has no path changes; its `psu_init.tcl` index blob remains
  `50f28ba65ffab223b8ffb12912d5d9ff3c433a35`.

## Remaining environment limitation

`Test-Axu4evLaunchWrappers.ps1` reaches its workspace dry-run and fails because
the pre-existing tracked Vivado bitstream
(`AFC016C6...FCFD4`) differs from the identical tracked Vitis-platform and IDE
bitstreams (`81686190...D4D5`). Those paths are unchanged from `c263389` to this
hardening branch. The separate user-owned untracked outputs were also
preserved; this hardening change neither modifies nor accepts any workspace
handoff artifact.

## Round 2: portability and non-vacuous dry-run closure

The JTAG launch record retains its original absolute historical checkout paths,
but the package gate now accepts only one separator-normalized, ordinal
`PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1` suffix and compares
the resulting exact release-relative path with name, length, and SHA-256. The
regression rewrites only the historical checkout prefix and passes; wrong
release, traversal, and duplicate-release-suffix probes are rejected.

Tracked-source cleanliness now runs before every dry-run return. The Candidate
fixture changes a tracked file in the selected output root and observes the
dry-run JSON gate marker, while a self-consistent modified trusted reference is
rejected by the same tracked-source filter before it can be read.

Fresh validation passed in both the current checkout and a detached, differently
located `core.autocrlf=false` checkout: package, Candidate build/dry-runs,
monitor/driver, parser, both strict evidence logs, and Candidate launch gates.
`git diff --check c263389..HEAD` passed and the protected single-shot Candidate
tree remains unchanged.
