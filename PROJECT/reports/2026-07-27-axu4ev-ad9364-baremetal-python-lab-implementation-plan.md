# AXU4EVB-P + AD9364 Bare-Metal Python Lab Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kartta kabul edilmiş 2048 noktalı PL FFT spectrumunu CRC korumalı UART mesajlarıyla bilgisayara taşıyan ve Python üzerinde canlı spectrum, waterfall, peak/sağlık bilgisi ile NPZ/CSV kayıt üreten ayrı bir Candidate oluşturmak.

**Architecture:** Mevcut `pl_fft_control` sürücüsü tek ve atomik spectrum snapshot üretir. Yeni saf C protocol/service katmanı bu snapshotı sabit little-endian mesajlara kodlar; Python codec aynı mesajı doğrulayıp NumPy/Matplotlib görünümüne ve kayıt katmanına verir. Host her geçerli yanıttan sonra yeni `CAPTURE_ONCE` gönderdiği için 115200 baud taşıma PL veya spectrum bankalarında kuyruk oluşturmaz.

**Tech Stack:** Vitis 2020.1 bare-metal A53 C11, mevcut AD9364 no-OS uygulaması, PL FFT AXI-Lite/BRAM sürücüsü, PowerShell test/build kapıları, Python 3 `unittest`, `pyserial`, `numpy`, `matplotlib`.

## Global Constraints

- Mevcut Golden release, `fft-single-shot-v1` ve `fft-periodic-monitor-v1` değiştirilmez.
- Yeni Candidate kimliği `monopulse-live-lab-v1`, compile symbol değeri `PL_FFT_LAB_UART` olur.
- UART `115200-8-N-1`, protocol version `1`, FFT boyutu `2048`, spectrum kelimesi little-endian `uint64` olur.
- Mesaj CRC'si CRC-32/ISO-HDLC (`0xEDB88320`, init/xorout `0xFFFFFFFF`) olur.
- C `struct` belleği seri hatta doğrudan kopyalanmaz; bütün alanlar açık little-endian helper'larla kodlanır.
- Python geçersiz CRC, sequence, version, length, FFT size veya fatal hardware flag içeren frame'i çizmez ve kaydetmez.
- Güç ekseni kalibrasyon tamamlanana kadar `relative dB, uncalibrated` olarak gösterilir; dBm iddia edilmez.
- PuTTY ve Python aynı COM portunu eşzamanlı açmaz.
- Ethernet, PetaLinux, IIO ve ZX80/HMC936 fiziksel GPIO entegrasyonu bu planın uygulama kapsamı değildir.
- Her davranış değişikliği test-first yapılır; testin beklenen nedenle RED olduğu görülmeden production kodu yazılmaz.

---

## File Structure

### Bare-metal

- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_protocol.h`
  - Wire sabitleri, metadata tipleri, parser ve encoder arayüzleri.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_protocol.c`
  - Little-endian codec, CRC, sınırlı komut parser'ı ve streaming response encoder.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_service.h`
  - FFT/RF/UART bağımlılıklarının enjekte edildiği servis arayüzü.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_service.c`
  - `GET_INFO`, `CAPTURE_ONCE`, `INFO`, `SPECTRUM` ve `ERROR` davranışı.
- `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`
  - `PL_FFT_LAB_UART` dışlayıcılığı.
- `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
  - Kart adapter'ları, runtime RF readback, READY/FAIL ve servis döngüsü.

### Python

- `PROJECT/lab_console/__init__.py`
  - Paket sürümü.
- `PROJECT/lab_console/protocol.py`
  - Byte-exact host codec ve streaming decoder.
- `PROJECT/lab_console/model.py`
  - Frekans ekseni, relative dB, peak kontrolü ve waterfall state.
- `PROJECT/lab_console/serial_client.py`
  - Sequence, timeout, request/response ve kontrollü retry.
- `PROJECT/lab_console/storage.py`
  - Atomik NPZ/CSV kayıt.
- `PROJECT/lab_console/app.py`
  - Matplotlib laboratuvar ekranı ve CLI.
- `PROJECT/lab_console/requirements.txt`
  - `pyserial`, `numpy`, `matplotlib`.

### Test/build/release

- `PROJECT/tests/pl_fft_lab_protocol_test.c`
- `PROJECT/tests/pl_fft_lab_service_test.c`
- `PROJECT/tests/Test-Axu4evPlFftLabProtocol.ps1`
- `PROJECT/tests/Test-Axu4evPlFftLabService.ps1`
- `PROJECT/tests/test_lab_console_protocol.py`
- `PROJECT/tests/test_lab_console_model.py`
- `PROJECT/tests/test_lab_console_serial_client.py`
- `PROJECT/tests/test_lab_console_storage.py`
- `PROJECT/tests/Test-Axu4evLabConsolePython.ps1`
- `PROJECT/tests/Test-Axu4evLabCandidateBuild.ps1`
- `PROJECT/tests/Test-Axu4evLabCandidatePackage.ps1`
- `PROJECT/tests/Test-Axu4evLabCaptureEvidence.ps1`
- `PROJECT/tools/Start-Axu4evAd9364LabConsole.cmd`
- `PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/`

---

### Task 1: Python protocol contract

**Files:**
- Create: `PROJECT/lab_console/__init__.py`
- Create: `PROJECT/lab_console/protocol.py`
- Create: `PROJECT/tests/test_lab_console_protocol.py`

**Interfaces:**
- Produces:
  - `encode_get_info(sequence: int) -> bytes`
  - `encode_capture_once(sequence: int, search_start: int, search_stop: int, dc_guard: int, rf_state: int) -> bytes`
  - `MessageDecoder.feed(data: bytes) -> list[Envelope]`
  - `decode_info(envelope: Envelope) -> InfoResponse`
  - `decode_spectrum(envelope: Envelope) -> SpectrumResponse`
  - `decode_error(envelope: Envelope) -> ErrorResponse`

- [x] **Step 1: Write the failing golden-envelope test**

```python
def test_get_info_has_exact_v1_wire_image(self) -> None:
    expected_without_crc = bytes.fromhex(
        "4d504c51010100000000000001000000"
    )
    expected = expected_without_crc + struct.pack(
        "<I", zlib.crc32(expected_without_crc) & 0xFFFFFFFF
    )
    self.assertEqual(encode_get_info(1), expected)
```

- [x] **Step 2: Run the protocol test RED**

Run:

```powershell
python -B -m unittest PROJECT.tests.test_lab_console_protocol -v
```

Expected: import failure because `PROJECT.lab_console.protocol` does not exist.

- [x] **Step 3: Implement constants, envelope dataclasses and command encoders**

```python
REQUEST_MAGIC = b"MPLQ"
RESPONSE_MAGIC = b"MPLR"
PROTOCOL_VERSION = 1
HEADER = struct.Struct("<4sBBHII")

def _encode(magic: bytes, message_type: int, flags: int,
            sequence: int, payload: bytes) -> bytes:
    prefix = HEADER.pack(
        magic, PROTOCOL_VERSION, message_type, flags,
        len(payload), sequence
    ) + payload
    return prefix + struct.pack("<I", zlib.crc32(prefix) & 0xFFFFFFFF)
```

- [x] **Step 4: Add failing decoder rejection/resync tests**

Cover separately:

- one-byte fragmentation,
- text/noise before `MPLR`,
- corrupted CRC,
- version `2`,
- payload over `MAX_PAYLOAD = 16448`,
- truncated message,
- mismatched SPECTRUM payload length,
- sequence retained exactly.

- [x] **Step 5: Implement bounded `MessageDecoder`**

The decoder keeps at most `HEADER.size + MAX_PAYLOAD + 4` bytes after locating
the newest possible `MPLR` prefix. It never allocates the declared payload
before checking `payload_length <= MAX_PAYLOAD`.

- [x] **Step 6: Add failing INFO/SPECTRUM/ERROR payload tests**

Build an exact 2048-element `np.arange(2048, dtype=np.uint64)` payload and
assert every metadata field, the last bin, signed peak Re/Im and hardware flag
mapping.

- [x] **Step 7: Implement payload decoders**

Use explicit `struct.Struct` layouts matching the approved design:

```python
INFO_PREFIX = struct.Struct("<HHIIHBBIIQ32s")
CAPTURE = struct.Struct("<HHHBB")
SPECTRUM_PREFIX = struct.Struct("<IHHIIQIIQHhhHBBHH")
ERROR_PAYLOAD = struct.Struct("<iHH")
```

Reject nonzero reserved fields in protocol v1.

- [x] **Step 8: Run GREEN and full Python regression**

```powershell
python -B -m unittest PROJECT.tests.test_lab_console_protocol -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evMonopulsePython.ps1
```

Expected: all tests PASS with no skip.

- [x] **Step 9: Commit**

```powershell
git add PROJECT/lab_console/__init__.py PROJECT/lab_console/protocol.py PROJECT/tests/test_lab_console_protocol.py
git commit -m "feat: define monopulse lab UART protocol"
```

---

### Task 2: Bare-metal wire codec

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_protocol.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_protocol.c`
- Create: `PROJECT/tests/pl_fft_lab_protocol_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftLabProtocol.ps1`

**Interfaces:**
- Produces:
  - `pl_fft_lab_crc32_update(uint32_t crc, const uint8_t *data, uint32_t length)`
  - `pl_fft_lab_parser_push(struct pl_fft_lab_parser *, uint8_t byte, struct pl_fft_lab_command *)`
  - `pl_fft_lab_write_info(const struct pl_fft_lab_writer *, uint32_t sequence, const struct pl_fft_lab_info *)`
  - `pl_fft_lab_write_spectrum(const struct pl_fft_lab_writer *, uint32_t sequence, const struct pl_fft_lab_spectrum *, const uint64_t bins[2048])`
  - `pl_fft_lab_write_error(const struct pl_fft_lab_writer *, uint32_t sequence, int32_t error_code, uint16_t stage)`

- [x] **Step 1: Write the failing C golden-vector test**

The test feeds the exact Python Task 1 GET_INFO bytes one at a time and asserts:

```c
CHECK(event == PL_FFT_LAB_COMMAND_READY);
CHECK(command.type == PL_FFT_LAB_GET_INFO);
CHECK(command.sequence == 1U);
CHECK(command.payload_length == 0U);
```

It also captures a C INFO response into a fake writer and compares every byte
with the Python golden vector committed in the test.

- [x] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabProtocol.ps1
```

Expected: missing protocol source/header.

- [x] **Step 3: Implement little-endian helpers and CRC**

Production helpers are private:

```c
static void put_u16_le(uint8_t out[2], uint16_t value);
static void put_u32_le(uint8_t out[4], uint32_t value);
static void put_u64_le(uint8_t out[8], uint64_t value);
```

The writer interface must support partial writes:

```c
typedef int32_t (*pl_fft_lab_write_fn)(
    void *context, const uint8_t *data, uint32_t length,
    uint32_t *written);
```

`write_all()` repeats until the exact length is sent or the writer returns an
error/zero progress.

- [x] **Step 4: Implement bounded command parser**

The parser stores only the 16-byte envelope header, at most 8-byte command
payload and 4-byte CRC. It resynchronizes on `MPLQ`, rejects version/type/length
violations and never allocates memory.

- [x] **Step 5: Implement streaming INFO/SPECTRUM/ERROR writers**

The 2048 bins are emitted one little-endian 8-byte word at a time while CRC is
updated. A 16 KiB response buffer is not placed on the A53 stack.

- [x] **Step 6: Add and pass negative tests**

Cover CRC corruption, noise resync, zero-progress writer, partial writer,
invalid command payload, nonzero reserved byte and 2048-bin exact last word.

- [x] **Step 7: Run GREEN and C warnings gate**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabProtocol.ps1
```

Expected: GCC C11 `-Wall -Wextra -Werror` PASS.

- [x] **Step 8: Commit**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_protocol.* PROJECT/tests/pl_fft_lab_protocol_test.c PROJECT/tests/Test-Axu4evPlFftLabProtocol.ps1
git commit -m "feat: add bare-metal lab wire codec"
```

---

### Task 3: Bare-metal lab service

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_service.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_service.c`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.h`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.c`
- Create: `PROJECT/tests/pl_fft_lab_service_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftLabService.ps1`

**Interfaces:**
- Consumes Task 2 codec and existing:
  - `pl_fft_init(struct pl_fft_device *)`
  - `pl_fft_capture_once(...)`
- Produces:

```c
struct pl_fft_lab_rf_snapshot {
    uint32_t sample_rate_hz;
    uint32_t rx_bandwidth_hz;
    uint64_t lo_hz;
};

struct pl_fft_lab_service {
    struct pl_fft_device *fft;
    struct pl_fft_lab_writer writer;
    void *rf_context;
    int32_t (*read_rf)(void *, struct pl_fft_lab_rf_snapshot *);
    uint64_t *spectrum;
};

int32_t pl_fft_lab_service_command(
    struct pl_fft_lab_service *service,
    const struct pl_fft_lab_command *command);
```

- [x] **Step 1: Write failing GET_INFO service test**

Use fake RF readback `30_720_000 / 10_000_000 / 2_400_000_000`, send GET_INFO
sequence 7 and assert one byte-exact INFO response containing
`monopulse-live-lab-v1`.

- [x] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabService.ps1
```

- [x] **Step 3: Implement GET_INFO and RF readback failure**

RF readback failure produces:

```c
pl_fft_lab_write_error(&service->writer, command->sequence,
                       PL_FFT_ERR_HARDWARE, PL_FFT_LAB_STAGE_CONFIG);
```

- [x] **Step 4: Write failing CAPTURE_ONCE tests**

Cover:

- exact search/DC/rf-state forwarded to `pl_fft_capture_once`,
- exact 2048-bin response,
- frame/peak/CRC/bank/RF tag metadata,
- invalid config -> `ERROR stage=CONFIG`,
- busy -> `ERROR stage=BUSY`,
- FFT fatal -> `ERROR stage=CAPTURE`,
- no SPECTRUM emitted after error.

- [x] **Step 5: Add `hardware_flags` to driver result**

Extend `struct pl_fft_result` with `uint16_t hardware_flags`. Map the captured
status snapshot to the v1 flag contract. Existing callers remain source
compatible because the field is appended.

- [x] **Step 6: Implement CAPTURE_ONCE service**

Use the service-owned aligned 2048-word buffer. Validate the command before
touching hardware. Do not retry hidden hardware errors.

- [x] **Step 7: Run service, driver and monitor regression**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabService.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftDriver.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftMonitor.ps1
```

- [x] **Step 8: Commit**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_control.* Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lab_service.* PROJECT/tests/pl_fft_lab_service_test.c PROJECT/tests/Test-Axu4evPlFftLabService.ps1
git commit -m "feat: serve FFT snapshots over lab protocol"
```

---

### Task 4: Board application mode

**Files:**
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/app_config.h`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
- Create: `PROJECT/tests/Test-Axu4evLabApplicationSource.ps1`

**Interfaces:**
- Consumes Task 3 service.
- Produces compile symbol `PL_FFT_LAB_UART` and UART marker:
  - `PL_FFT_LAB: READY protocol=1 bins=2048 baud=115200`
  - `PL_FFT_LAB: FAIL stage=<stage> error=<code>`

- [x] **Step 1: Write failing application-source contract test**

Assert `PL_FFT_LAB_UART` is mutually exclusive with all existing feature modes,
the exact READY/FAIL strings exist once, RF values come from
`ad9361_get_rx_sampling_freq`, `ad9361_get_rx_rf_bandwidth` and
`ad9361_get_rx_lo_freq`, and the spectrum buffer is file-scope aligned storage.

- [x] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabApplicationSource.ps1
```

- [x] **Step 3: Make feature modes exactly-one**

Add `PL_FFT_LAB_UART` to the existing compile-time exclusivity expression.
When no explicit mode is selected, preserve the current
`MONOPULSE_FOUNDATION_TEST` default.

- [x] **Step 4: Add board adapters**

Use:

- existing `Xil_In32/Xil_In64/Xil_Out32` FFT adapters,
- BSP `inbyte()` for blocking command bytes,
- BSP `outbyte()` in a writer that reports exact progress,
- AD9364 API runtime readback for INFO.

After READY, feed each received byte to the bounded parser and dispatch only
complete valid commands.

- [x] **Step 5: Run source and existing mode regressions**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabApplicationSource.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evMonopulseSource.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLaunch.ps1
```

- [x] **Step 6: Commit**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/app_config.h Vitis/workspace/ad9364app/src/adc9364_src/main.c PROJECT/tests/Test-Axu4evLabApplicationSource.ps1
git commit -m "feat: add bare-metal FFT lab UART mode"
```

---

### Task 5: Python spectrum model and persistence

**Files:**
- Create: `PROJECT/lab_console/model.py`
- Create: `PROJECT/lab_console/storage.py`
- Create: `PROJECT/tests/test_lab_console_model.py`
- Create: `PROJECT/tests/test_lab_console_storage.py`

**Interfaces:**
- Consumes Task 1 `SpectrumResponse`.
- Produces:
  - `centered_frequency_axis(lo_hz: int, sample_rate_hz: int, fft_size: int) -> np.ndarray`
  - `relative_db(power: np.ndarray) -> np.ndarray`
  - `SpectrumHistory.append(response: SpectrumResponse) -> PlotFrame`
  - `save_capture(output_dir: Path, frame: PlotFrame, release_id: str) -> CapturePaths`

- [x] **Step 1: Write failing frequency-axis tests**

For `N=8`, `Fs=8 MHz`, `LO=100 MHz`, assert the centered axis is:

```python
np.array([96, 97, 98, 99, 100, 101, 102, 103]) * 1_000_000
```

and that natural bins are reordered `[4,5,6,7,0,1,2,3]`.

- [x] **Step 2: Run RED**

```powershell
python -B -m unittest PROJECT.tests.test_lab_console_model -v
```

- [x] **Step 3: Implement model with immutable accepted frames**

`SpectrumHistory` retains at most 32 valid frames. It verifies the reported
peak bin equals the lower-index NumPy argmax inside the requested search range.
Peak mismatches raise `ValueError` rather than silently changing metadata.

- [x] **Step 4: Write failing NPZ/CSV tests**

Assert:

- NPZ spectrum remains exact `uint64[2048]`,
- RF frequency axis and metadata belong to the same frame ID,
- CSV contains one summary row and the NPZ filename,
- a collision creates a suffixed filename and never overwrites,
- temporary files do not remain after success.

- [x] **Step 5: Implement atomic storage**

Write temporary files in the destination directory, flush/close, then rename.
The host supplies UTC timestamp; the board does not claim wall-clock time.

- [x] **Step 6: Run GREEN**

```powershell
python -B -m unittest PROJECT.tests.test_lab_console_model PROJECT.tests.test_lab_console_storage -v
```

- [x] **Step 7: Commit**

```powershell
git add PROJECT/lab_console/model.py PROJECT/lab_console/storage.py PROJECT/tests/test_lab_console_model.py PROJECT/tests/test_lab_console_storage.py
git commit -m "feat: model and save FFT lab captures"
```

---

### Task 6: Serial client and Matplotlib application

**Files:**
- Create: `PROJECT/lab_console/serial_client.py`
- Create: `PROJECT/lab_console/app.py`
- Create: `PROJECT/lab_console/requirements.txt`
- Create: `PROJECT/tests/test_lab_console_serial_client.py`
- Create: `PROJECT/tests/Test-Axu4evLabConsolePython.ps1`

**Interfaces:**
- Consumes Tasks 1 and 5.
- Produces:
  - `LabSerialClient.get_info() -> InfoResponse`
  - `LabSerialClient.capture_once(config: CaptureConfig) -> SpectrumResponse`
  - `python -m PROJECT.lab_console.app --port COMx`

- [x] **Step 1: Write failing serial-client tests**

Use a deterministic fake serial object. Cover:

- sequence increments,
- text/noise before first binary response,
- fragmented response,
- unrelated older sequence ignored,
- bad CRC discarded and one explicit retry,
- 5 second deadline,
- ERROR response raised with code/stage,
- port closed in context-manager exit.

- [x] **Step 2: Run RED**

```powershell
python -B -m unittest PROJECT.tests.test_lab_console_serial_client -v
```

- [x] **Step 3: Implement `LabSerialClient`**

The client sends one request at a time. Retry count defaults to one and applies
only to transport timeout/CRC, not board ERROR responses.

- [x] **Step 4: Write failing headless UI tests**

Use Matplotlib `Agg`. Assert:

- upper spectrum and lower waterfall axes exist,
- peak marker frequency equals model output,
- title says `relative dB, uncalibrated`,
- health text shows CRC OK and RF state,
- fatal frame does not enter waterfall,
- Save callback invokes storage with current frame.

- [x] **Step 5: Implement CLI and view**

CLI:

```powershell
python -m PROJECT.lab_console.app --port COM5 --baud 115200 --history 32
```

The animation callback requests a new frame only after the previous response
completes. `--single` saves one valid capture and exits without opening an
interactive window.

- [x] **Step 6: Add dependency runner**

`Test-Axu4evLabConsolePython.ps1 -InstallDependencies` creates
`.venv-monopulse-lab` and installs exact minimums:

```text
numpy>=1.20
matplotlib>=3.5
pyserial>=3.5
```

Normal test mode uses the selected Python without modifying the environment.

- [x] **Step 7: Run GREEN and all Python regression**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabConsolePython.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evMonopulsePython.ps1
```

- [x] **Step 8: Commit**

```powershell
git add PROJECT/lab_console PROJECT/tests/test_lab_console_serial_client.py PROJECT/tests/Test-Axu4evLabConsolePython.ps1
git commit -m "feat: add live FFT laboratory display"
```

---

### Task 7: Candidate build, launcher and immutable package

**Files:**
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1`
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl`
- Modify: `PROJECT/tests/Test-Axu4evCandidateBuild.ps1`
- Create: `PROJECT/tests/Test-Axu4evLabCandidateBuild.ps1`
- Create: `PROJECT/tests/Test-Axu4evLabCandidatePackage.ps1`
- Create: `PROJECT/tools/Start-Axu4evAd9364LabConsole.cmd`
- Create after real build: `PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/`

**Interfaces:**
- Produces:
  - `-ApplicationMode LabUart`
  - compiler symbol `PL_FFT_LAB_UART`
  - UART marker `PL_FFT_LAB: READY`
  - Candidate ID `monopulse-live-lab-v1`

- [x] **Step 1: Write failing build-mode tests**

Dry-run must report:

```json
{
  "application_mode": "LabUart",
  "compiler_symbol": "PL_FFT_LAB_UART",
  "pl_fft_lab_uart": true
}
```

It must use the board-verified single-shot hardware reference just like the
periodic Candidate, while refusing to overwrite either accepted Candidate.

- [x] **Step 2: Run RED**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCandidateBuild.ps1
```

- [x] **Step 3: Add LabUart build mapping**

Extend PowerShell `ValidateSet` and Tcl `allowed_symbols`. Do not loosen dirty
tracked-source, reparse-point, manifest or hardware-identity gates.

- [x] **Step 4: Add launcher and package tests**

Launcher must resolve only:

```text
PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1
```

The initial manifest uses `board_verified=false` and contains marker
`PL_FFT_LAB: READY`.

- [x] **Step 5: Run build/launcher tests GREEN**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evCandidateBuild.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCandidateBuild.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCandidatePackage.ps1
```

- [x] **Step 6: Commit build support before generated Candidate**

```powershell
git add PROJECT/tools/Build-Axu4evPlFftCandidate.* PROJECT/tools/Start-Axu4evAd9364LabConsole.cmd PROJECT/tests/Test-Axu4evCandidateBuild.ps1 PROJECT/tests/Test-Axu4evLabCandidateBuild.ps1 PROJECT/tests/Test-Axu4evLabCandidatePackage.ps1
git commit -m "build: add monopulse lab Candidate mode"
```

- [x] **Step 7: Run real Vitis 2020.1 build**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tools\Build-Axu4evPlFftCandidate.ps1 `
  -ApplicationMode LabUart `
  -CandidateRoot PROJECT\candidates\axu4ev-ad9364\monopulse-live-lab-v1
```

Expected: exact application ELF plus hardware-identical BIT/XSA/PMUFW/PSU-init
package, manifest `board_verified=false`.

- [x] **Step 8: Run package and release gates**

Run Lab package, Candidate launch dry-run, JTAG order, release integrity,
single-shot and periodic package regressions.

- [x] **Step 9: Commit generated Candidate**

```powershell
git add PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1
git commit -m "build: package monopulse live lab Candidate"
```

---

### Task 8: Preflight documentation and operator handoff

**Files:**
- Modify: `PROJECT/reports/project_situation_report.md`
- Modify: `PROJECT/reports/implementation_plan.md`
- Modify: `PROJECT/reports/chat_report.md`
- Modify: `PROJECT/reports/axu4ev_ad9364_fft_rf_switch_nihai_plan.md`
- Modify: `PROJECT/reports/2026-07-30-staj-sunum-ozeti.md`
- Create: `PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/README.md`

**Interfaces:**
- Produces exact operator sequence and prevents preflight from being reported as
  physical RF acceptance.

- [x] **Step 1: Run complete preflight**

At minimum:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabProtocol.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPlFftLabService.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabConsolePython.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCandidateBuild.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCandidatePackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorPackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evRelease.ps1
```

- [x] **Step 2: Write README**

Document:

1. JTAG and PS_UART wiring.
2. PuTTY must be closed before Python opens COM.
3. Candidate launch command.
4. `python -m PROJECT.lab_console.app --port COMx`.
5. Expected READY and INFO fields.
6. `--single` capture.
7. RF safety and uncalibrated-relative-power label.

- [x] **Step 3: Update reports as software-ready only**

Record exact commit, Candidate hashes, tests and remaining controlled-CW board
gate. Do not set `board_verified=true`.

- [x] **Step 4: Commit handoff**

```powershell
git add PROJECT/reports PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/README.md
git commit -m "docs: hand off monopulse lab Candidate"
```

---

### Task 9: Controlled-CW physical acceptance

**Files:**
- Create after PASS: `PROJECT/tests/evidence/axu4ev-ad9364-live-lab-cw-pass.md`
- Create after PASS: `PROJECT/tests/evidence/axu4ev-ad9364-live-lab-cw-capture.npz`
- Create after PASS: `PROJECT/tests/evidence/axu4ev-ad9364-live-lab-cw-summary.csv`
- Create: `PROJECT/tests/Test-Axu4evLabCaptureEvidence.ps1`
- Modify after PASS: `PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/manifest.json`
- Modify after PASS: relevant `PROJECT/reports/*.md`

**Interfaces:**
- Converts Lab Candidate from software-ready to controlled-CW board-verified.

- [x] **Step 1: Write failing evidence validator**

Require:

- exact Candidate application/bitstream hashes,
- SMW200A frequency and level,
- AD9364 LO/Fs/BW,
- at least 10 valid consecutive frames,
- exact 2048 bins each,
- CRC valid,
- peak bins within `±1`,
- fatal hardware flags zero,
- NPZ/CSV same frame identity.

- [x] **Step 2: Run validator RED**

Expected: missing physical evidence.

- [ ] **Step 3: Prepare RF safely**

- Use a direct cabled/attenuated path or approved antenna/chamber setup.
- Confirm AD9364 input power remains within the approved lab limit.
- Put CW at a known non-DC FFT offset within the configured RX bandwidth.
- Record SMW200A frequency, output level, attenuator/path and antenna/port.

- [ ] **Step 4: Launch Candidate and Python**

```powershell
PROJECT\tools\Start-Axu4evAd9364LabConsole.cmd
python -m PROJECT.lab_console.app --port COMx
python -m PROJECT.lab_console.app --port COMx --frames 10 `
  --output-dir PROJECT/tests/evidence `
  --series-name axu4ev-ad9364-live-lab-cw
```

Save one accepted series with at least 10 frames.

- [ ] **Step 5: Validate physical evidence**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evLabCaptureEvidence.ps1
```

Expected: PASS with exact peak stability and hash binding.

- [ ] **Step 6: Mark only this Candidate board verified**

Set `board_verified=true` only after Step 5. Do not promote Golden and do not
alter `CURRENT`.

- [ ] **Step 7: Re-run package/release gates and commit**

```powershell
git add PROJECT/tests/evidence PROJECT/candidates/axu4ev-ad9364/monopulse-live-lab-v1/manifest.json PROJECT/reports
git commit -m "test: accept live FFT lab console on hardware"
```

---

## Completion Gate

This plan is complete only when:

1. Python and C golden bytes are identical.
2. Parser/encoder negative tests prove CRC, bounds, resync and partial writes.
3. Existing single-shot and periodic Candidate regressions remain green.
4. `monopulse-live-lab-v1` is reproducibly built and package hashes are bound.
5. Python displays live spectrum, 32-frame waterfall, peak and health state.
6. NPZ/CSV save the exact displayed frame without overwrite.
7. Controlled CW produces at least 10 stable, CRC-valid, 2048-bin frames.
8. Evidence validator passes before `board_verified=true`.
9. Reports distinguish FFT graph acceptance from ZX80/HMC936 monopulse product
   acceptance.

## Following Plans

After this plan passes:

1. Write and execute `ZX80/HMC936 electrical control + S0-S3` plan using the
   measured BDC IF, continuity, level-shifter and FPGA pin table.
2. Write and execute `SMW200A/chamber monopulse calibration` plan using the
   accepted four-state hardware cycle.
