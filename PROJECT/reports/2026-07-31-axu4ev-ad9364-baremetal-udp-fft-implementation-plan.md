# AXU4EV AD9364 Bare-Metal Continuous UDP FFT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AXU4EVB-P üzerindeki AD9364/PL FFT zincirinden alınan 2048-bin spektrumu, peak ve RF metadatasıyla birlikte saniyede 4 kare hızında kesintisiz UDP unicast olarak PC'ye aktarmak ve Python'da canlı göstermek.

**Architecture:** Mevcut doğrulanmış Golden, single-shot, periodic-monitor ve UART Lab projeleri değişmeden kalır. Yeni `PL_FFT_ETHERNET` uygulama modu, PL FFT yakalamasını 64 baytlık sürümlü bir UDP başlığı ve 12 MTU-güvenli parçayla lwIP RAW API üzerinden yollar; PC tarafı paketleri `frame_id` ile yeniden birleştirip mevcut `SpectrumResponse`, model ve kayıt sözleşmesine dönüştürür. Varsayılan çalışma kesintisizdir; `--frames N` yalnız test ve sınırlı kayıt için isteğe bağlı durdurma kapısıdır.

**Tech Stack:** Vivado/Vitis 2020.1, Zynq UltraScale+ MPSoC Cortex-A53 standalone BSP, `lwip211` RAW API, ADI no-OS AD9364 sürücüsü, C11 host testleri, Python 3, `socket`, `struct`, NumPy, Matplotlib, pytest.

## Global Constraints

- Mevcut `vitis2/`, Golden ve `PROJECT/candidates/axu4ev-ad9364-monopulse/` altındaki doğrulanmış Candidate içerikleri değiştirilmez.
- Yeni üretilen Vitis çalışma alanı `vitis_ethernet/workspace/` altında tutulur ve Git'e eklenmez.
- Kart IP adresi `192.168.1.10`, PC IP adresi `192.168.1.100`, ağ maskesi `255.255.255.0`, UDP hedef portu `5005` olur.
- Ethernet hedefi doğrudan kart-PC bağlantısı ve sabit IPv4'tür; DHCP, TCP, WebSocket ve PetaLinux kullanılmaz.
- Gönderim hızı varsayılan 4 FFT kare/saniye, kare periyodu 250 ms'dir.
- Varsayılan yayın süresizdir; firmware veya Python tarafında 100-kare otomatik durdurma bulunmaz.
- FFT boyutu 2048, her bin unsigned 64-bit, payload little-endian olur.
- Ethernet MTU 1500 aşılmaz: 64 bayt uygulama başlığı ve en fazla 1408 bayt/176 bin payload kullanılır.
- Bir FFT karesi 12 UDP datagramına bölünür; son datagram 112 bin taşır.
- Uygulama başlığındaki çok baytlı sayısal alanlar network byte order kullanır.
- Kaynak RF testi SMW200A ile kablosuz CW, 2.400300 GHz; AD9364 LO 2.400000 GHz; beklenen natural-order peak bin `20 ± 1` olur.
- Jeneratör `Level Limit=-20 dBm`, başlangıç `-70 dBm`, artış `5 dB`, normal üst sınır `-30 dBm` ve anten mesafesi en az 1 m olur.
- Yeni Candidate paketi yalnız host testleri, Vitis build, ağ testi ve gerçek kart CW kabul testi geçtikten sonra oluşturulur.

---

## File Map

### New firmware protocol and service files

- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_protocol.h`: Wire-format constants, metadata and chunk definitions.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_protocol.c`: Endian-safe 64-byte header encoding and 2048-bin chunk calculation.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_service.h`: Transport-independent continuous capture service interfaces.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_service.c`: One-frame capture/send transaction and 250 ms continuous scheduling.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_transport.h`: Static IPv4/lwIP transport interface.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_transport.c`: GEM3, lwIP RAW UDP and 12-datagram transmission.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_platform.h`: ZynqMP timer/interrupt functions required by Xilinx lwIP adapter.
- `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_platform.c`: TTC/GIC setup derived from the installed Vitis 2020.1 UDP example.

### Modified firmware/build files

- `Vitis/workspace/ad9364app/src/adc9364_src/main.c`: Add isolated `PL_FFT_ETHERNET` mode and infinite streaming entry point.
- `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl`: Accept `PL_FFT_ETHERNET`, add `lwip211`, and select RAW/static-IP BSP settings.
- `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1`: Add Ethernet application mode and keep generated workspace separate.
- `.gitignore`: Ignore only generated `vitis_ethernet/workspace/`.
- `PROJECT/tools/Start-Axu4evAd9364EthernetDev.cmd`: Launch the new development ELF with verified hardware artifacts.

### New PC files

- `PROJECT/ethernet_fft/__init__.py`: Package boundary.
- `PROJECT/ethernet_fft/protocol.py`: Header decoding and datagram validation.
- `PROJECT/ethernet_fft/reassembly.py`: Out-of-order chunk assembly, timeout eviction and loss counters.
- `PROJECT/ethernet_fft/receiver.py`: UDP socket and continuous frame iterator.
- `PROJECT/ethernet_fft/app.py`: CLI, live spectrum/peak graph, bounded history and optional finite capture.
- `PROJECT/ethernet_fft/requirements.txt`: Python runtime/test dependencies.
- `PROJECT/tools/Start-Axu4evAd9364EthernetViewer.cmd`: PC viewer wrapper.

### Tests and evidence

- `PROJECT/tests/pl_fft_udp_protocol_test.c`
- `PROJECT/tests/pl_fft_udp_service_test.c`
- `PROJECT/tests/Test-Axu4evPlFftUdpProtocol.ps1`
- `PROJECT/tests/Test-Axu4evPlFftUdpService.ps1`
- `PROJECT/tests/Test-Axu4evEthernetCandidateBuild.ps1`
- `PROJECT/tests/test_ethernet_fft_protocol.py`
- `PROJECT/tests/test_ethernet_fft_reassembly.py`
- `PROJECT/tests/test_ethernet_fft_receiver.py`
- `PROJECT/tests/test_ethernet_fft_app.py`
- `PROJECT/tests/Test-Axu4evEthernetHost.ps1`
- `PROJECT/tests/Test-Axu4evEthernetLabAcceptance.ps1`
- `PROJECT/tests/Test-Axu4evEthernetCandidatePackage.ps1`
- `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-*.txt|json|npz|png`: Yalnız gerçek test çıktıları.

---

### Task 1: Freeze the 64-Byte UDP Wire Contract

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_protocol.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_protocol.c`
- Create: `PROJECT/tests/pl_fft_udp_protocol_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftUdpProtocol.ps1`

**Interfaces:**
- Consumes: `PL_FFT_SPECTRUM_WORDS == 2048`, `struct pl_fft_result` metadata.
- Produces:
  - `int32_t pl_fft_udp_chunk_bounds(uint16_t chunk_index, struct pl_fft_udp_chunk_view *view);`
  - `int32_t pl_fft_udp_encode_header(uint8_t out[PL_FFT_UDP_HEADER_BYTES], const struct pl_fft_udp_metadata *metadata, uint16_t chunk_index);`
  - `PL_FFT_UDP_HEADER_BYTES=64`, `PL_FFT_UDP_BINS_PER_CHUNK=176`, `PL_FFT_UDP_CHUNK_COUNT=12`.

- [ ] **Step 1: Write a failing C protocol test**

```c
static void test_header_and_chunk_contract(void)
{
	uint8_t bytes[PL_FFT_UDP_HEADER_BYTES];
	struct pl_fft_udp_chunk_view last;
	struct pl_fft_udp_metadata meta = {
		.frame_id = 0x01020304u,
		.lo_hz = 2400000000ull,
		.sample_rate_hz = 30720000u,
		.bandwidth_hz = 10000000u,
		.gain_db = 50,
		.peak_bin = 20u,
		.peak_power = 0x0102030405060708ull,
		.frame_crc32 = 0xaabbccddu,
		.peak_re = -123,
		.peak_im = 456,
		.reset_epoch = 7u,
		.rf_state = 0u,
		.active_bank = 1u,
	};

	CHECK(pl_fft_udp_chunk_bounds(11u, &last) == PL_FFT_UDP_OK);
	CHECK(last.first_bin == 1936u);
	CHECK(last.bin_count == 112u);
	CHECK(pl_fft_udp_encode_header(bytes, &meta, 11u) == PL_FFT_UDP_OK);
	CHECK(bytes[0] == 'A' && bytes[1] == 'F' &&
	      bytes[2] == 'F' && bytes[3] == 'T');
	CHECK(bytes[4] == 1u && bytes[5] == 1u);
	CHECK(bytes[6] == 0u && bytes[7] == 64u);
	CHECK(bytes[8] == 1u && bytes[9] == 2u &&
	      bytes[10] == 3u && bytes[11] == 4u);
}
```

- [ ] **Step 2: Run the protocol test and verify RED**

Run:

```powershell
& .\PROJECT\tests\Test-Axu4evPlFftUdpProtocol.ps1
```

Expected: compilation fails because `pl_fft_udp_protocol.h` or the declared functions do not exist.

- [ ] **Step 3: Implement the exact wire types and manual big-endian writers**

```c
#define PL_FFT_UDP_MAGIC 0x41464654u
#define PL_FFT_UDP_VERSION 1u
#define PL_FFT_UDP_PACKET_TYPE_FFT 1u
#define PL_FFT_UDP_HEADER_BYTES 64u
#define PL_FFT_UDP_FFT_SIZE 2048u
#define PL_FFT_UDP_BINS_PER_CHUNK 176u
#define PL_FFT_UDP_CHUNK_COUNT 12u

struct pl_fft_udp_chunk_view {
	uint16_t first_bin;
	uint16_t bin_count;
};

struct pl_fft_udp_metadata {
	uint32_t frame_id;
	uint16_t hardware_flags;
	uint64_t lo_hz;
	uint32_t sample_rate_hz;
	uint32_t bandwidth_hz;
	int16_t gain_db;
	uint16_t peak_bin;
	uint64_t peak_power;
	uint32_t frame_crc32;
	int16_t peak_re;
	int16_t peak_im;
	uint16_t reset_epoch;
	uint8_t rf_state;
	uint8_t active_bank;
};

static void put_u64_be(uint8_t *dst, uint64_t value)
{
	uint32_t index;
	for (index = 0u; index < 8u; index++)
		dst[index] = (uint8_t)(value >> (56u - index * 8u));
}
```

Encode the fields at the exact offsets specified in
`PROJECT/reports/2026-07-31-axu4ev-ad9364-baremetal-udp-fft-design.md`;
reject null pointers and `chunk_index >= 12`.

- [ ] **Step 4: Run protocol tests and existing FFT tests**

Run:

```powershell
& .\PROJECT\tests\Test-Axu4evPlFftUdpProtocol.ps1
& .\PROJECT\tests\Test-Axu4evPlFftDriver.ps1
& .\PROJECT\tests\Test-Axu4evPlFftLabProtocol.ps1
```

Expected: all commands print PASS and return exit code 0.

- [ ] **Step 5: Commit the protocol**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_protocol.* PROJECT/tests/pl_fft_udp_protocol_test.c PROJECT/tests/Test-Axu4evPlFftUdpProtocol.ps1
git commit -m "feat: define FFT UDP wire protocol"
```

---

### Task 2: Add a Transport-Independent Continuous FFT Service

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_service.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_service.c`
- Create: `PROJECT/tests/pl_fft_udp_service_test.c`
- Create: `PROJECT/tests/Test-Axu4evPlFftUdpService.ps1`

**Interfaces:**
- Consumes:
  - `pl_fft_capture_once(...)`
  - `pl_fft_udp_encode_header(...)`
  - callback `send_datagram(context, header, 64, payload, payload_bytes)`.
- Produces:
  - `int32_t pl_fft_udp_service_send_frame(struct pl_fft_udp_service *service);`
  - `int32_t pl_fft_udp_service_run(struct pl_fft_udp_service *service);`
  - `run()` returns only on error or when an injected test callback requests stop; production has no frame limit.

- [ ] **Step 1: Write RED tests for 12 chunks, 250 ms cadence and no 100-frame limit**

```c
static void test_continuous_service_passes_frame_150(void)
{
	struct fixture test = fixture_make();
	test.stop_after_frames = 151u;

	CHECK(pl_fft_udp_service_run(&test.service) == PL_FFT_UDP_STOPPED);
	CHECK(test.capture_calls == 151u);
	CHECK(test.sent_datagrams == 151u * 12u);
	CHECK(test.delay_calls == 150u);
	CHECK(test.last_delay_ms == 250u);
	CHECK(test.max_chunk_bytes <= 1472u);
}
```

Also assert that a send failure stops the loop immediately, increments no
successful-frame counter, and returns the exact injected error.

- [ ] **Step 2: Run the service test and verify RED**

```powershell
& .\PROJECT\tests\Test-Axu4evPlFftUdpService.ps1
```

Expected: compilation fails for missing service declarations.

- [ ] **Step 3: Implement one-frame transaction and infinite scheduler**

```c
struct pl_fft_udp_rf_snapshot {
	uint64_t lo_hz;
	uint32_t sample_rate_hz;
	uint32_t bandwidth_hz;
	int16_t gain_db;
	uint8_t rf_state;
};

struct pl_fft_udp_service {
	void *context;
	int32_t (*capture)(void *context, struct pl_fft_result *result,
			   uint64_t spectrum[PL_FFT_UDP_FFT_SIZE]);
	int32_t (*read_rf)(void *context,
			   struct pl_fft_udp_rf_snapshot *snapshot);
	int32_t (*send_datagram)(void *context, const uint8_t *header,
				 uint32_t header_bytes,
				 const uint8_t *payload,
				 uint32_t payload_bytes);
	void (*delay_ms)(void *context, uint32_t delay_ms);
	bool (*should_stop)(void *context);
	uint64_t *spectrum;
	uint32_t completed_frames;
};

int32_t pl_fft_udp_service_run(struct pl_fft_udp_service *service)
{
	int32_t status;

	if (service == NULL || service->delay_ms == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	for (;;) {
		status = pl_fft_udp_service_send_frame(service);
		if (status != PL_FFT_UDP_OK)
			return status;
		if (service->should_stop != NULL &&
		    service->should_stop(service->context))
			return PL_FFT_UDP_STOPPED;
		service->delay_ms(service->context, 250u);
	}
}
```

`send_frame()` captures one coherent bank, reads the RF snapshot once, emits
chunks `0..11` in order, and reports success only after all 12 sends succeed.

- [ ] **Step 4: Run new and existing service regressions**

```powershell
& .\PROJECT\tests\Test-Axu4evPlFftUdpService.ps1
& .\PROJECT\tests\Test-Axu4evPlFftLabService.ps1
& .\PROJECT\tests\Test-Axu4evPlFftMonitor.ps1
```

Expected: PASS, including the 151-frame test proving there is no hidden 100-frame stop.

- [ ] **Step 5: Commit the service**

```powershell
git add Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_udp_service.* PROJECT/tests/pl_fft_udp_service_test.c PROJECT/tests/Test-Axu4evPlFftUdpService.ps1
git commit -m "feat: add continuous FFT UDP service"
```

---

### Task 3: Integrate GEM3 and lwIP211 Without Touching Verified Modes

**Files:**
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_transport.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_transport.c`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_platform.h`
- Create: `Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_platform.c`
- Modify: `Vitis/workspace/ad9364app/src/adc9364_src/main.c`
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl`
- Modify: `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1`
- Modify: `.gitignore`
- Create: `PROJECT/tests/Test-Axu4evEthernetCandidateBuild.ps1`

**Interfaces:**
- Consumes: Task 2 service; `XPAR_XEMACPS_0_BASEADDR == 0xFF0E0000`; Vitis 2020.1 `lwip211`.
- Produces:
  - `int32_t pl_fft_lwip_transport_init(struct pl_fft_lwip_transport *transport);`
  - `int32_t pl_fft_lwip_transport_send(...);`
  - compiler symbol `PL_FFT_ETHERNET`.

- [ ] **Step 1: Add a RED build-contract test**

```powershell
$tcl = Get-Content -LiteralPath $buildTcl -Raw
$ps1 = Get-Content -LiteralPath $buildPs1 -Raw
Assert-Match $tcl 'PL_FFT_ETHERNET'
Assert-Match $tcl 'bsp setlib -name lwip211'
Assert-Match $ps1 "'Ethernet' \{ 'PL_FFT_ETHERNET' \}"
Assert-Match $main '#ifdef PL_FFT_ETHERNET'
Assert-Match $gitignore '/vitis_ethernet/workspace/'
```

- [ ] **Step 2: Run the build-contract test and verify RED**

```powershell
& .\PROJECT\tests\Test-Axu4evEthernetCandidateBuild.ps1
```

Expected: FAIL because the Ethernet application mode is not yet declared.

- [ ] **Step 3: Configure the standalone BSP for lwIP RAW/static IPv4**

Add only when `$compiler_symbol == "PL_FFT_ETHERNET"`:

```tcl
bsp setlib -name lwip211
bsp config api_mode RAW_API
bsp config lwip_dhcp false
bsp config mem_size 524288
bsp config pbuf_pool_size 256
bsp regenerate
```

Extend the PowerShell `ValidateSet` with `Ethernet`, select
`PL_FFT_ETHERNET`, require UART marker `PL_FFT_ETH: READY`, and default the
generated workspace to `vitis_ethernet\workspace`.

- [ ] **Step 4: Implement static network initialization and UDP send**

```c
static const uint8_t board_ip[4] = {192u, 168u, 1u, 10u};
static const uint8_t target_ip[4] = {192u, 168u, 1u, 100u};
static const uint8_t netmask[4] = {255u, 255u, 255u, 0u};
static const uint8_t mac[6] = {0x02u, 0x00u, 0x00u, 0x93u, 0x64u, 0x01u};

err = udp_sendto(transport->pcb, packet, &transport->target, 5005u);
```

Use `pbuf_alloc(PBUF_TRANSPORT, 64 + bin_count * 8, PBUF_RAM)`, copy the
header and payload, call `udp_sendto`, then always `pbuf_free`. Initialize
`lwip_init`, `xemac_add`, `netif_set_default`, `netif_set_up`, TTC/GIC and
the Xilinx adapter. Keep all lwIP includes and calls inside
`#ifdef PL_FFT_ETHERNET`.

- [ ] **Step 5: Add the isolated main-mode entry**

```c
#ifdef PL_FFT_ETHERNET
	status = pl_fft_ethernet_run(phy);
	if (status != PL_FFT_UDP_OK)
		printf("PL_FFT_ETH: FAIL error=%d\n", status);
	return status;
#endif
```

Print:

```text
PL_FFT_ETH: READY board=192.168.1.10 target=192.168.1.100:5005 fps=4 bins=2048
```

before entering the infinite service loop. Preserve all previous preprocessor
branches byte-for-byte except for the new isolated branch and shared include guard.

- [ ] **Step 6: Run static and host regressions**

```powershell
& .\PROJECT\tests\Test-Axu4evEthernetCandidateBuild.ps1
& .\PROJECT\tests\Test-Axu4evPlFftUdpProtocol.ps1
& .\PROJECT\tests\Test-Axu4evPlFftUdpService.ps1
& .\PROJECT\tests\Test-Axu4evPlFftLabProtocol.ps1
& .\PROJECT\tests\Test-Axu4evPlFftLabService.ps1
```

Expected: all PASS.

- [ ] **Step 7: Commit lwIP integration**

```powershell
git add .gitignore Vitis/workspace/ad9364app/src/adc9364_src/main.c Vitis/workspace/ad9364app/src/adc9364_src/pl_fft_lwip_* PROJECT/tools/Build-Axu4evPlFftCandidate.* PROJECT/tests/Test-Axu4evEthernetCandidateBuild.ps1
git commit -m "feat: integrate bare-metal FFT UDP transport"
```

---

### Task 4: Implement and Verify the Python Wire Decoder

**Files:**
- Create: `PROJECT/ethernet_fft/__init__.py`
- Create: `PROJECT/ethernet_fft/protocol.py`
- Create: `PROJECT/tests/test_ethernet_fft_protocol.py`

**Interfaces:**
- Consumes: Task 1 64-byte wire contract.
- Produces:
  - `HEADER = struct.Struct("!IBBHIHHHHHHQIIhHQIhhHBB")`
  - `UdpFftChunk.decode(datagram: bytes) -> UdpFftChunk`
  - `UdpProtocolError`.

- [ ] **Step 1: Write failing exact-byte and rejection tests**

```python
def test_decodes_last_chunk():
    datagram = make_datagram(
        frame_id=0x01020304, chunk_index=11,
        first_bin=1936, bins=np.arange(112, dtype="<u8")
    )
    chunk = UdpFftChunk.decode(datagram)
    assert chunk.frame_id == 0x01020304
    assert chunk.first_bin == 1936
    assert chunk.bin_count == 112
    assert chunk.bins.dtype == np.dtype("<u8")

@pytest.mark.parametrize("mutation", ["magic", "version", "length", "range"])
def test_rejects_invalid_datagram(mutation):
    with pytest.raises(UdpProtocolError):
        UdpFftChunk.decode(corrupt_valid_datagram(mutation))
```

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_protocol.py -q
```

Expected: import failure for `PROJECT.ethernet_fft.protocol`.

- [ ] **Step 3: Implement strict decode**

```python
HEADER = struct.Struct("!IBBHIHHHHHHQIIhHQIhhHBB")

@classmethod
def decode(cls, datagram: bytes) -> "UdpFftChunk":
    if len(datagram) < HEADER.size:
        raise UdpProtocolError("datagram shorter than 64-byte header")
    fields = HEADER.unpack_from(datagram)
    if fields[0] != 0x41464654 or fields[1:4] != (1, 1, 64):
        raise UdpProtocolError("unsupported FFT UDP header")
    payload = datagram[64:]
    if len(payload) != fields[8] * 8:
        raise UdpProtocolError("bin_count does not match payload length")
    return cls.from_fields(fields, np.frombuffer(payload, dtype="<u8").copy())
```

Validate `chunk_count == 12`, `fft_size == 2048`,
`first_bin + bin_count <= 2048`, and the exact canonical bounds for each
chunk index.

- [ ] **Step 4: Run Python protocol tests**

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_protocol.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit the decoder**

```powershell
git add PROJECT/ethernet_fft/__init__.py PROJECT/ethernet_fft/protocol.py PROJECT/tests/test_ethernet_fft_protocol.py
git commit -m "feat: decode FFT UDP datagrams"
```

---

### Task 5: Reassemble Frames With Loss and Reordering Diagnostics

**Files:**
- Create: `PROJECT/ethernet_fft/reassembly.py`
- Create: `PROJECT/tests/test_ethernet_fft_reassembly.py`

**Interfaces:**
- Consumes: `UdpFftChunk.decode`.
- Produces:
  - `FrameReassembler.push(datagram: bytes, received_at: float) -> SpectrumResponse | None`
  - `FrameReassembler.expire(now: float) -> int`
  - counters `completed_frames`, `lost_frames`, `duplicate_chunks`, `invalid_datagrams`, `out_of_order_chunks`.

- [ ] **Step 1: Write RED tests for ordering, loss and metadata consistency**

```python
def test_reassembles_twelve_chunks_in_reverse_order():
    assembler = FrameReassembler(timeout_s=1.0)
    response = None
    for datagram in reversed(make_frame(frame_id=7)):
        response = assembler.push(datagram, received_at=0.1)
    assert response is not None
    assert response.frame_id == 7
    assert response.peak_bin == 20
    np.testing.assert_array_equal(
        response.spectrum, np.arange(2048, dtype=np.uint64)
    )
    assert assembler.completed_frames == 1
    assert assembler.out_of_order_chunks > 0

def test_expires_incomplete_frame_without_plotting_it():
    assembler = FrameReassembler(timeout_s=1.0)
    assembler.push(make_frame(9)[0], received_at=0.0)
    assert assembler.expire(now=1.1) == 1
    assert assembler.lost_frames == 1
```

- [ ] **Step 2: Run and verify RED**

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_reassembly.py -q
```

Expected: import failure for `FrameReassembler`.

- [ ] **Step 3: Implement bounded per-frame assembly**

```python
def push(self, datagram: bytes, received_at: float) -> SpectrumResponse | None:
    try:
        chunk = UdpFftChunk.decode(datagram)
    except UdpProtocolError:
        self.invalid_datagrams += 1
        return None
    pending = self._frames.setdefault(
        chunk.frame_id, PendingFrame.from_chunk(chunk, received_at)
    )
    if not pending.metadata_matches(chunk):
        self.invalid_datagrams += 1
        del self._frames[chunk.frame_id]
        return None
    pending.add(chunk)
    if not pending.complete:
        return None
    del self._frames[chunk.frame_id]
    self.completed_frames += 1
    return pending.to_spectrum_response()
```

Keep at most 8 pending frames; evict the oldest incomplete frame when the
limit is reached. Do not reinterpret the PL `frame_crc32` as the UART
protocol CRC; carry it as telemetry exactly as the current console does.

- [ ] **Step 4: Run reassembly and existing model/storage tests**

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_reassembly.py PROJECT/tests/test_lab_console_model.py PROJECT/tests/test_lab_console_storage.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit reassembly**

```powershell
git add PROJECT/ethernet_fft/reassembly.py PROJECT/tests/test_ethernet_fft_reassembly.py
git commit -m "feat: reassemble FFT UDP frames"
```

---

### Task 6: Add a Truly Continuous UDP Receiver and Live Viewer

**Files:**
- Create: `PROJECT/ethernet_fft/receiver.py`
- Create: `PROJECT/ethernet_fft/app.py`
- Create: `PROJECT/ethernet_fft/requirements.txt`
- Create: `PROJECT/tests/test_ethernet_fft_receiver.py`
- Create: `PROJECT/tests/test_ethernet_fft_app.py`
- Create: `PROJECT/tests/Test-Axu4evEthernetHost.ps1`
- Create: `PROJECT/tools/Start-Axu4evAd9364EthernetViewer.cmd`

**Interfaces:**
- Consumes: `FrameReassembler`, current `PROJECT.lab_console.model.SpectrumHistory`.
- Produces:
  - `UdpFftReceiver.frames(limit: int = 0) -> Iterator[SpectrumResponse]`
  - CLI `python -m PROJECT.ethernet_fft.app --bind 192.168.1.100 --port 5005 --frames 0`.

- [ ] **Step 1: Write RED tests proving frame 101 and frame 150 are displayed**

```python
def test_zero_limit_is_continuous_past_one_hundred_frames():
    receiver = UdpFftReceiver.from_datagrams(
        datagram for frame in range(1, 151)
        for datagram in make_frame(frame)
    )
    observed = list(receiver.frames(limit=0, stop=lambda r: r.frame_id == 150))
    assert len(observed) == 150
    assert observed[-1].frame_id == 150

def test_positive_limit_stops_for_acceptance_capture():
    receiver = fake_receiver(frame_count=150)
    assert len(list(receiver.frames(limit=100))) == 100
```

- [ ] **Step 2: Run and verify RED**

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_receiver.py PROJECT/tests/test_ethernet_fft_app.py -q
```

Expected: import failure for receiver/app modules.

- [ ] **Step 3: Implement continuous socket iteration**

```python
def frames(self, limit: int = 0) -> Iterator[SpectrumResponse]:
    completed = 0
    while limit == 0 or completed < limit:
        datagram, _peer = self.socket.recvfrom(2048)
        response = self.reassembler.push(datagram, time.monotonic())
        self.reassembler.expire(time.monotonic())
        if response is None:
            continue
        completed += 1
        yield response
```

Handle `KeyboardInterrupt` as a clean stop. Set `SO_RCVBUF` to at least
1 MiB and socket timeout to 250 ms so expiry/statistics continue during
packet gaps.

- [ ] **Step 4: Implement bounded live plotting**

Update one Matplotlib line in place; keep at most 32 completed frames in
`SpectrumHistory`. Display frame ID, peak bin/frequency, FPS, lost frames,
invalid datagrams and out-of-order chunks. `--frames` defaults to `0`;
`--frames 100` remains available only for a finite evidence capture.

- [ ] **Step 5: Run all host tests**

```powershell
& .\PROJECT\tests\Test-Axu4evEthernetHost.ps1
```

The wrapper runs:

```powershell
python -m pytest PROJECT/tests/test_ethernet_fft_protocol.py PROJECT/tests/test_ethernet_fft_reassembly.py PROJECT/tests/test_ethernet_fft_receiver.py PROJECT/tests/test_ethernet_fft_app.py -q
```

Expected: PASS and the continuous test reaches frame 150.

- [ ] **Step 6: Commit the PC application**

```powershell
git add PROJECT/ethernet_fft PROJECT/tests/test_ethernet_fft_*.py PROJECT/tests/Test-Axu4evEthernetHost.ps1 PROJECT/tools/Start-Axu4evAd9364EthernetViewer.cmd
git commit -m "feat: add continuous Ethernet FFT viewer"
```

---

### Task 7: Build the Separate Ethernet Workspace and Launch Development ELF

**Files:**
- Create generated directory: `vitis_ethernet/workspace/` (ignored)
- Create: `PROJECT/tools/Start-Axu4evAd9364EthernetDev.cmd`
- Modify if required by observed build only: `PROJECT/tools/Build-Axu4evPlFftCandidate.tcl`
- Modify if required by observed build only: `PROJECT/tools/Build-Axu4evPlFftCandidate.ps1`

**Interfaces:**
- Consumes: verified FFT Candidate XSA/bitstream and new `PL_FFT_ETHERNET` sources.
- Produces: `vitis_ethernet/workspace/ad9364app/Release/ad9364app.elf`.

- [ ] **Step 1: Check disk, tools and immutable references**

```powershell
$free = (Get-PSDrive C).Free
if ($free -lt 5GB) { throw 'At least 5 GiB free space is required.' }
Test-Path C:\Xilinx\Vitis\2020.1\bin\xsct.bat
Test-Path .\PROJECT\candidates\axu4ev-ad9364-monopulse\fft-single-shot-v1\system.xsa
git status --short
```

Expected: Vitis exists, verified reference exists, and at least 5 GiB is free.

- [ ] **Step 2: Run the Ethernet build into the new workspace**

```powershell
& .\PROJECT\tools\Build-Axu4evPlFftCandidate.ps1 `
  -ApplicationMode Ethernet `
  -WorkspaceRoot .\vitis_ethernet\workspace `
  -BuildOnly
```

Expected: Release ELF exists, BSP manifest contains `lwip211`, and old
Candidate hashes remain unchanged.

- [ ] **Step 3: Inspect the ELF and build provenance**

```powershell
Get-Item .\vitis_ethernet\workspace\ad9364app\Release\ad9364app.elf
Select-String -Path .\vitis_ethernet\workspace\**\*.mss -Pattern 'lwip211'
& .\PROJECT\tests\Test-Axu4evEthernetCandidateBuild.ps1
git status --short
```

Expected: the ELF is non-empty, `lwip211` is present, tests pass, and no
generated workspace file appears in Git status.

- [ ] **Step 4: Create and verify the dev launcher**

The wrapper invokes:

```powershell
& .\PROJECT\tools\Invoke-Axu4evAd9364Launch.ps1 `
  -Mode Candidate `
  -CandidateApplication '.\vitis_ethernet\workspace\ad9364app\Release\ad9364app.elf'
```

Expected UART marker after launch:

```text
PL_FFT_ETH: READY board=192.168.1.10 target=192.168.1.100:5005 fps=4 bins=2048
```

- [ ] **Step 5: Commit only reproducible scripts**

```powershell
git add PROJECT/tools/Start-Axu4evAd9364EthernetDev.cmd PROJECT/tools/Build-Axu4evPlFftCandidate.* .gitignore
git commit -m "build: add separate Ethernet FFT workspace"
```

Do not add `vitis_ethernet/workspace/`.

---

### Task 8: Perform Cable-Only Network Soak Test

**Files:**
- Create: `PROJECT/tests/Test-Axu4evEthernetLabAcceptance.ps1`
- Create after execution: `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-link-<timestamp>.txt`
- Create after execution: `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-soak-<timestamp>.json`

**Interfaces:**
- Consumes: running Ethernet ELF, PC static IP `192.168.1.100`, no RF source.
- Produces: evidence that frame streaming remains active beyond 100 frames.

- [ ] **Step 1: Configure the dedicated PC adapter**

Set only the cable-connected adapter to:

```text
IPv4: 192.168.1.100
Mask: 255.255.255.0
Gateway: blank
DNS: blank
```

Keep Wi-Fi enabled only if Windows routing does not assign the same subnet;
otherwise disable Wi-Fi for this test.

- [ ] **Step 2: Launch the board and verify link**

```powershell
& .\PROJECT\tools\Start-Axu4evAd9364EthernetDev.cmd
ping 192.168.1.10
```

Expected: UART READY marker and successful ping replies.

- [ ] **Step 3: Run a 150-frame headless acceptance capture**

```powershell
python -m PROJECT.ethernet_fft.app `
  --bind 192.168.1.100 --port 5005 --frames 150 --headless `
  --evidence-dir PROJECT\tests\evidence
```

Expected:

```text
ETH_FFT: PASS frames=150 last_frame>=150 lost_frames=0 invalid_datagrams=0
```

- [ ] **Step 4: Run a 10-minute continuous soak**

```powershell
& .\PROJECT\tests\Test-Axu4evEthernetLabAcceptance.ps1 `
  -DurationSeconds 600 -MinimumFrames 2200 -MaximumLossPercent 0.1
```

Expected: process is stopped by duration, not by frame count; at least 2200
frames complete, loss is at most 0.1%, and the last frame ID is greater than
the first by more than 100.

- [ ] **Step 5: Commit the acceptance tooling and real evidence**

```powershell
git add PROJECT/tests/Test-Axu4evEthernetLabAcceptance.ps1 PROJECT/tests/evidence/axu4ev-ad9364-ethernet-link-*.txt PROJECT/tests/evidence/axu4ev-ad9364-ethernet-soak-*.json
git commit -m "test: verify continuous FFT Ethernet streaming"
```

---

### Task 9: Perform the Wireless CW Peak Acceptance Test

**Files:**
- Create after execution: `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-<timestamp>.npz`
- Create after execution: `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-<timestamp>.png`
- Create after execution: `PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-<timestamp>.txt`

**Interfaces:**
- Consumes: Task 8 stable Ethernet streaming, SMW200A and separate TX/RX antennas.
- Produces: accepted real-RF peak at bin `20 ± 1`.

- [ ] **Step 1: Apply the RF safety gate before enabling output**

Configure:

```text
SMW200A frequency: 2.400300 GHz
Level Limit: -20 dBm
Starting level: -70 dBm
Modulation: off (CW)
RF output: off while cabling/positioning
Antenna separation: >= 1 m
AD9364 RX input: the project-verified RX port
```

- [ ] **Step 2: Start continuous reception before RF**

```powershell
python -m PROJECT.ethernet_fft.app `
  --bind 192.168.1.100 --port 5005 --frames 0 `
  --expected-peak-bin 20 --peak-tolerance 1
```

Expected: the graph and frame counter continue past frame 100.

- [ ] **Step 3: Raise the generator level conservatively**

Enable RF at `-70 dBm`, then increase by 5 dB only when the spectrum remains
unclipped. Stop increasing when the peak is stable; do not exceed `-30 dBm`
in normal testing.

- [ ] **Step 4: Capture 100 accepted RF frames**

```powershell
python -m PROJECT.ethernet_fft.app `
  --bind 192.168.1.100 --port 5005 --frames 100 `
  --expected-peak-bin 20 --peak-tolerance 1 `
  --save PROJECT\tests\evidence
```

Expected: median peak bin is in `[19, 21]`, completed frame count is 100,
invalid datagrams are zero, and a PNG/NPZ/text summary is written.

- [ ] **Step 5: Turn RF off and commit evidence**

```powershell
git add PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-*.npz PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-*.png PROJECT/tests/evidence/axu4ev-ad9364-ethernet-cw-*.txt
git commit -m "test: validate wireless CW FFT over Ethernet"
```

---

### Task 10: Package the Verified Ethernet Candidate and Update Reports

**Files:**
- Create only after Task 9 passes: `PROJECT/candidates/axu4ev-ad9364-monopulse/monopulse-live-ethernet-v1/`
- Create: `PROJECT/tools/Start-Axu4evAd9364EthernetCandidate.cmd`
- Create: `PROJECT/tests/Test-Axu4evEthernetCandidatePackage.ps1`
- Modify: `PROJECT/reports/implementation_plan.md`
- Modify: `PROJECT/reports/project_situation_report.md`
- Modify: `PROJECT/reports/chat_report.md`
- Modify: `PROJECT/reports/axu4ev_ad9364_fft_rf_switch_nihai_plan.md`
- Modify: `PROJECT/reports/profen_staj_raporu.docx` only if the final report is still the maintained handoff artifact.

**Interfaces:**
- Consumes: board-verified ELF and immutable verified hardware artifacts.
- Produces: self-contained immutable Candidate with manifest, hashes, evidence references and launcher.

- [ ] **Step 1: Run the complete regression gate**

```powershell
& .\PROJECT\tests\Test-Axu4evPlFftUdpProtocol.ps1
& .\PROJECT\tests\Test-Axu4evPlFftUdpService.ps1
& .\PROJECT\tests\Test-Axu4evEthernetHost.ps1
& .\PROJECT\tests\Test-Axu4evEthernetCandidateBuild.ps1
git diff --check
```

Expected: all PASS and no whitespace errors.

- [ ] **Step 2: Package exact verified artifacts**

Copy the verified Ethernet ELF plus the already verified XSA, bitstream,
PMUFW, FSBL and `psu_init.tcl`. Generate SHA-256 values with:

```powershell
Get-FileHash -Algorithm SHA256 $artifactPaths
```

The manifest records:

```json
{
  "candidate_id": "monopulse-live-ethernet-v1",
  "application_mode": "Ethernet",
  "compiler_symbol": "PL_FFT_ETHERNET",
  "board_ip": "192.168.1.10",
  "target_ip": "192.168.1.100",
  "target_port": 5005,
  "fft_size": 2048,
  "frame_period_ms": 250,
  "continuous": true,
  "board_verified": true
}
```

- [ ] **Step 3: Verify immutability and launcher**

```powershell
& .\PROJECT\tests\Test-Axu4evEthernetCandidatePackage.ps1 `
  -CandidateRoot .\PROJECT\candidates\axu4ev-ad9364-monopulse\monopulse-live-ethernet-v1
& .\PROJECT\tools\Start-Axu4evAd9364EthernetCandidate.cmd
```

Expected: manifest/hash PASS and UART Ethernet READY marker.

- [ ] **Step 4: Update handoff reports with measured results**

Record exact commit, Candidate hash, 150-frame gate, 10-minute soak
statistics, CW frequency/level/distance, median peak bin and evidence paths.
State explicitly that default streaming is continuous and `--frames 100`
is only an optional finite evidence mode.

- [ ] **Step 5: Commit the final Candidate and reports**

```powershell
git add PROJECT/candidates/axu4ev-ad9364-monopulse/monopulse-live-ethernet-v1 PROJECT/tools/Start-Axu4evAd9364EthernetCandidate.cmd PROJECT/reports
git commit -m "feat: release continuous Ethernet FFT candidate"
```

- [ ] **Step 6: Push only after final status review**

```powershell
git status --short --branch
git log -5 --oneline
git push origin codex/axu4ev-monopulse-lab-console
```

Expected: push succeeds and local branch is no longer ahead of origin.
