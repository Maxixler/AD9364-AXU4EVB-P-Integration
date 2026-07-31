# Task 8 report: cable-only Ethernet acceptance soak

## Status

**BLOCKED — physical acceptance has not run.** No physical Ethernet evidence
files were created by this task.

## Delivered tooling

- `PROJECT/tests/Test-Axu4evEthernetLabAcceptance.ps1` performs read-only
  adapter/link, ping, and Xilinx/Digilent JTAG preflight; runs an unbounded
  headless capture for the requested duration; and writes factual link/soak
  evidence only after preflight succeeds.
- `PROJECT.ethernet_fft.app` now supports headless finite or duration-bounded
  capture, a versioned JSON capture summary, and the required one-line
  acceptance status for finite captures.
- Offline fixtures cover duration completion, the minimum-frame gate, loss
  percentage calculation (`lost / (completed + lost)`), invalid datagrams,
  frame-ID span, and JSON evidence parsing without hardware.

## Offline verification

- `PROJECT/tests/Test-Axu4evEthernetHost.ps1`: 34 tests passed.
- `PROJECT/tests/Test-Axu4evEthernetLabAcceptanceTool.ps1`: passed.
- Workspace diff check: passed.

## Read-only physical preflight findings

- No Windows adapter currently owns `192.168.1.100`.
- `192.168.1.10` did not answer ping.
- No present Xilinx/Digilent/JTAG PnP device was detected.

## Operator prerequisites to unblock

1. Connect the AXU4EV board directly to the dedicated PC Ethernet adapter and
   configure that adapter as `192.168.1.100/255.255.255.0`, with blank gateway
   and DNS. Keep Wi-Fi off if it routes `192.168.1.0/24`.
2. Connect and power the board's Xilinx/Digilent JTAG USB interface until it is
   visible in Windows, then launch the Ethernet ELF with
   `PROJECT/tools/Start-Axu4evAd9364EthernetDev.cmd` and confirm the UART
   `PL_FFT_ETH: READY` marker.
3. Confirm `ping 192.168.1.10` succeeds.
4. Run the 150-frame headless capture from the task brief, then run:
   `PROJECT/tests/Test-Axu4evEthernetLabAcceptance.ps1 -DurationSeconds 600 -MinimumFrames 2200 -MaximumLossPercent 0.1`.

The second command will create the timestamped link and soak evidence only
from that real run and will enforce duration stop, at least 2200 completed
frames, loss at or below 0.1%, zero invalid datagrams, and a frame-ID span over
100.

## Fix Round 1: headless deadline and frame-ID progression

The duration predicate previously ran only after a complete frame or a socket
idle timeout. A stream of malformed or incomplete datagrams can keep the
receiver inside its datagram loop, so the duration deadline was not guaranteed
to run. `UdpFftReceiver.frames()` now checks the supplied deadline before and
after every received datagram. The deterministic regression test feeds an
unbounded malformed-datagram iterator and confirms that it terminates after one
datagram when the deadline trips.

Finite headless acceptance now also requires non-null, advancing frame IDs, a
last ID at least as large as the requested frame count, and a span of at least
`frames - 1`. A repeated-ID capture is therefore reported as `ETH_FFT: FAIL`.

Commands and output:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evEthernetHost.ps1
36 passed in 9.53s
PASS: Ethernet FFT host receiver and viewer tests.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evEthernetLabAcceptanceTool.ps1
PASS: Ethernet lab acceptance offline thresholds and JSON evidence behavior.

git diff --check
exit 0
```

No physical evidence was generated during this fix round.

## Fix Round 2: full finite-capture frame-ID ordering

Endpoint-only validation could accept an internal frame-ID regression: the
150-response sequence `1..148, 1, 150` has a valid first ID, last ID, and
overall span. The headless capture summary now records
`frame_ids_strictly_increasing`, derived from every adjacent pair. Finite
acceptance requires that value in addition to the existing count, loss,
invalid-datagram, endpoint, and span checks. Continuous mode does not use this
finite-capture PASS gate.

Commands and output:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evEthernetHost.ps1
38 passed in 9.98s
PASS: Ethernet FFT host receiver and viewer tests.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evEthernetLabAcceptanceTool.ps1
PASS: Ethernet lab acceptance offline thresholds and JSON evidence behavior.

git diff --check
exit 0
```

The exact regressed sequence returns nonzero with `ETH_FFT: FAIL`; a strictly
increasing `1..150` sequence returns zero with `ETH_FFT: PASS`. No physical
evidence was generated during this fix round.
