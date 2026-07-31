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
