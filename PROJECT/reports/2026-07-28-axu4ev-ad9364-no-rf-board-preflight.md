# AXU4EVB-P + AD9364 Sinyalsiz Kart Preflight

**Tarih:** 28 Temmuz 2026
**Candidate:** `monopulse-live-lab-v2`
**Test tipi:** JTAG + PS_UART gerçek kart, harici RF kaynağı yok
**Fiziksel CW kabulü:** Hayır

## Amaç

Laboratuvar RF kaynağı kullanılamazken JTAG başlatma, protocol v2, gerçek
PS_UART iletişimi, tam 2048-bin frame aktarımı, CRC, gain-lock ve health
metadata yolunu kart üzerinde sınamak.

## JTAG başlatma

Launcher aşağıdaki kapıları geçti:

```text
PASS: PMUFW, FPGA, direct PS/DDR/PS-PL initialization,
DDR gate and ad9364app were launched over JTAG.
PASS: Candidate launch completed.
```

JTAG log:

```text
PROJECT/logs/jtag/20260728-164424-candidate.log
SHA-256:
3D92D960E2F6635C3F2B25C52B39813341F7361CD588B1D3C5C7B098DD36570F
```

## Protocol-v2 INFO sonucu

```text
release_id=monopulse-live-lab-v2
fft_size=2048
spectrum_word_bytes=8
sample_rate_hz=30720000
rx_bandwidth_hz=10000000
lo_hz=2400000000
gain_mode=manual
gain_db=50
```

## İlk-frame gözlemi

İlk `CAPTURE_ONCE` isteği:

```text
board error code=-6 stage=4
```

olarak döndü. Bu `PL_FFT_ERR_HARDWARE / CAPTURE` eşlemesidir. Hata kalıcı
olmadı; sonraki ham isteklerde frame 6-15 arasında on ardışık frame:

- exact 2048 sample;
- `hardware_flags=0`;
- manual 50 dB gain;
- geçerli protocol CRC;
- artan frame ID

ile döndü. İlk transient fatal bitin alt nedeni bu testte kesinleştirilmedi;
temiz cold-start CW kabulünde tekrar izlenecektir.

## Sinyalsiz spectrum ve host peak sınırı

Harici RF kaynağı yokken bütün 2048 magnitude-square kelimesi mevcut FFT
scaling'i altında sıfır oldu. Donanım `dc_guard=0` durumunda bile bin 0'ı
dışladığı için eşit güçte `peak_bin=1` raporladı. Python modeli ise varsayılan
`search_start=0` ile `np.argmax` sonucu bin 0'ı bekledi ve temiz frame'i
peak-mismatch olarak reddetti.

Kod değiştirilmeden, donanımın mevcut arama sözleşmesine uygun
`--search-start 1` kullanılarak sinyalsiz preflight tamamlandı. Bu davranış
gerçek CW peak kabulünden önce Python/donanım DC-guard tie semantiğinin
birleştirilmesi gereken açık yazılım maddesidir.

## Kaydedilen 10-frame seri

```text
NPZ:
PROJECT/tests/evidence/axu4ev-ad9364-no-rf-preflight-20260728-capture.npz
SHA-256:
C3D8448A404721815A6191E2D42E32ACFF0C7117BBE05BDD646B3AD8C6248D0E

CSV:
PROJECT/tests/evidence/axu4ev-ad9364-no-rf-preflight-20260728-summary.csv
SHA-256:
DA2722AE04195A4F869395B40A97667F260442B666F8DBD0B242EBC1C71392BB
```

Özet:

| Alan | Sonuç |
|---|---|
| Spectrum şekli | `10 x 2048`, `uint64` |
| Frame ID | `19..28`, ardışık |
| FFT size | Her frame `2048` |
| Protocol CRC | Her frame geçerli |
| Hardware flags | Her frame `0` |
| Gain mode | Her frame manual |
| Gain | Her frame `50 dB` |
| LO | Her frame `2.400000 GHz` |
| Sample rate | Her frame `30.72 MSPS` |
| RX bandwidth | Her frame `10 MHz` |
| Peak | Her frame bin 1, power 0 |
| Sıfır olmayan spectrum kelimesi | `0` |

## Sonuç ve sınır

JTAG, PS/DDR/PS-PL init, protocol v2, PS_UART, exact 2048-bin transfer, CRC,
gain-lock ve on ardışık temiz health frame'i gerçek kartta doğrulandı.

Bu testte kontrollü RF tonu olmadığı için:

- RF peak/frekans doğruluğu;
- relatif güç kararlılığı;
- `±1 bin` CW kabulü;
- mutlak dBm;
- ZX80/HMC936 ve monopulse açı performansı

doğrulanmadı. Candidate manifesti doğru biçimde `board_verified=false`
kalacaktır.
