# Task 8 Report: Integrate the FFT shadow path into FMCOMMS2 AXU4EV

## Outcome

Integrated the complete single-shot FFT datapath into the AXU4EV FMCOMMS2
block design as a passive I0/Q0 shadow path. The checked-in Tcl remains shared
with the other FMCOMMS2 carriers, so every new cell, address, and interrupt is
gated by the AXU4EV Candidate-only `AXU4EV_FFT_SHADOW_PATH` contract.

The build wrapper packages the custom IP and generates the Vivado project,
bitstream, XSA, and reports under a drive-root disposable Candidate directory.
It never opens or overwrites the existing Golden project, bitstream, XSA, or
Vitis platform.

## TDD and structural evidence

The structural gate was written before enabling the integration. Its disabled
Candidate run failed on the required FFT instance, establishing RED. After the
Tcl integration, the same generated-BD inspection proved:

- the only ADC additions are passive taps on `dout_valid_0`,
  `dout_enable_0`, `dout_data_0` (I0), and `dout_data_1` (Q0);
- all four Golden FIFO-to-packer connections and the packer-to-DMAC interface
  remain unchanged;
- CPU and ADC clock/reset domains are connected to their intended sources;
- two independent 64-bit AXI BRAM Controllers expose the spectrum banks;
- ADC DMA IRQ slot 13 and DAC DMA IRQ slot 12 are unchanged, while FFT uses
  previously unused slot 11.

The final structural marker is:

```text
PASS: FFT shadow path is present and the Golden DMA topology is unchanged
```

## Hardware contract

| Resource | PS-visible address | Range |
|---|---:|---:|
| FFT AXI-Lite control | `0x9C440000` | `0x1000` |
| Spectrum bank 0 | `0x9D000000` | `0x4000` |
| Spectrum bank 1 | `0x9D010000` | `0x4000` |

Each spectrum aperture is 2048 words by 64 bits. The custom BRAM ports use
14-bit byte addresses and map bits `[13:3]` to the 11-bit spectrum index.
Temporary `rf_state[2:0]` metadata is tied to constant zero until the RF-control
task owns it.

## CDC timing closure

The first routed Candidate exposed a real implementation issue: WNS was
`-3.207 ns` while WHS was `+0.004 ns`. The failing endpoints were functional
command/result mailbox registers whose asynchronous CLR depended directly on
the opposite clock domain's reset.

A strict reset-isolation gate was added before the fix. Both mailbox modules
now use per-domain two-stage `ASYNC_REG` reset synchronizers with asynchronous
assertion and synchronous release. The XDC exception is limited to the CLR
pins of those named reset synchronizers; there is no blanket reset or clock
group exception. Bundled-data CDC paths retain their explicit 8 ns max-delay
and hold-only exceptions.

Fresh CDC and actual-xFFT regressions passed, including one-sided reset,
in-flight request, epoch, and recovery scenarios.

## Final verification

```text
Test-Axu4evFftCdcResetIsolation.ps1
  PASS: FFT CDC ready/acknowledge paths avoid opposite-domain raw resets.

Test-Axu4evFftRtl.ps1 -Test cdc
  PASS: fft_cdc

Test-Axu4evFftIp.ps1
  PASS: positive disposable FFT package inspection
  PASS: FFT v9.1 configuration matches the numerical contract

Test-Axu4evFftBlockDesign.ps1
  PASS: FFT shadow path is present and the Golden DMA topology is unchanged

Test-Axu4evFftRtl.ps1 -Test top
  PASS: axi_ad9364_fft_capture single-shot
```

The routed Candidate generated `system_top.bit`, reported zero DRC errors, and
met all user timing constraints:

| Metric | Result |
|---|---:|
| WNS | `+0.044 ns` |
| TNS | `0.000 ns` |
| WHS | `+0.010 ns` |
| THS | `0.000 ns` |

FFT hierarchy utilization from the routed design:

| Resource | Used |
|---|---:|
| CLB LUT | 3,942 |
| CLB registers | 6,834 |
| Block RAM tiles | 16.5 |
| DSP | 22 |

The complete report set contains DRC, min/max timing, CDC, whole-design
utilization, and FFT-hierarchy utilization reports. No generated Vivado/IP
product is intended for source control.
