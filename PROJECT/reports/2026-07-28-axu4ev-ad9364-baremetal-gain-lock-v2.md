# AXU4EVB-P + AD9364 Bare-Metal Gain-Lock v2

Date: 2026-07-28

## Scope

This revision remains bare-metal. PetaLinux, IIOD and the experimental
`capture_monopulse_iio.py` path are outside this delivery.

The immutable `monopulse-live-lab-v1` Candidate is retained as historical
evidence. The corrected lab Candidate is `monopulse-live-lab-v2`.

## Corrected RF contract

- Physical RF device: AD9364.
- Active receive channel: RX channel 0 only.
- FFT length: exactly 2048 complex samples.
- Sample rate: 30.72 MSPS.
- Default RX bandwidth: 10 MHz.
- Gain control mode: manual (`RF_GAIN_MGC`).
- Fixed RX gain: 50 dB.

After AD9364 initialization the application changes RX0 to manual gain, writes
50 dB, then reads back both gain mode and gain. Failure to read back exactly
manual/50 dB prevents the UART lab service from starting.

Before every `GET_INFO` or `CAPTURE_ONCE` response, the board reads the RF
configuration again. A mode or gain change is reported as a hardware failure,
so frames captured under an unbound gain state cannot enter the evidence set.

## Protocol v2

Protocol v2 adds signed `gain_db` and `gain_mode` to both INFO and SPECTRUM
responses. The release identifier is `monopulse-live-lab-v2`.

The Python console:

1. accepts only protocol v2;
2. accepts only manual gain telemetry;
3. rejects a gain change within a capture series;
4. stores gain mode and gain dB in NPZ and CSV;
5. requires the evidence metadata to bind `AD9364 gain mode: manual` and
   `AD9364 gain dB: 50`;
6. rejects controlled-CW evidence if any frame has a different gain.

## Expected UART marker

```text
PL_FFT_LAB: READY protocol=2 bins=2048 baud=115200 gain_mode=manual gain_db=50
```

## Controlled-CW test point

Use a non-DC, bin-aligned offset. At 30.72 MSPS and 2048 bins, one bin is
15 kHz. Recommended initial choices are:

- LO + 300 kHz: natural-order bin 20.
- LO + 1.5 MHz: natural-order bin 100.

Do not use LO + 7 kHz for acceptance because it falls within the DC-bin region.
Start the SMW200A at a safe low level with the approved attenuation. Confirm
there is no clipping before increasing source level or receiver gain.

## Verification gates

- C protocol golden vectors.
- C bare-metal lab service tests.
- A53 `PL_FFT_LAB_UART` source compilation.
- Python protocol/model/storage/serial/UI/evidence tests.
- Candidate build isolation dry-run.
- Immutable Candidate artifact/hash verification after real Vitis build.
- Physical JTAG/UART and controlled-CW acceptance in the laboratory.

## Built Candidate

The application was compiled with the Vitis 2020.1 AArch64 compiler/linker
against the existing verified AXU4EV standalone BSP. Two clean short-workspace
`platform generate` attempts hit the same Vitis 2020.1 Windows BSP self-lock;
the failing operation was not repeated a third time.

The application-only build used the real address contract from the Candidate
XSA, not the dummy addresses used by host syntax tests:

- control: `0x9C440000`;
- spectrum bank 0: `0x9D000000`;
- spectrum bank 1: `0x9D010000`.

Binary gates confirmed the protocol-v2 READY format, release identifier and
lab-service symbols. The package is:

```text
release_id: monopulse-live-lab-v2
source_commit: 3f88ccc7e85eaab34f197dd9dda4a3e136285c32
application_length: 865952
application_sha256:
  E05CA5EB83CC3E94BC05F55E52C1A076979FD2A66D8E19EBBE822DAF4FE7C01F
bitstream_sha256:
  ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC
board_verified: false
```

The bitstream, PMUFW, `psu_init.tcl` and XSA remain byte-identical to the
board-verified `fft-single-shot-v1` hardware package. Physical JTAG/UART and
controlled-CW acceptance remain intentionally open.
