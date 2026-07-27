# AXU4EVB-P + AD9364 Bare-Metal Python Monopulse Laboratuvar Tasarımı

**Tarih:** 27 Temmuz 2026

**Durum:** Kullanıcı tarafından onaylandı

**Hedef platform:** AXU4EVB-P + mevcut AD9364

**Araç zinciri:** Vivado/Vitis 2020.1, bare-metal A53, Python 3

## 1. Amaç

Bu teslim, kartta kabul edilmiş 2048 noktalı PL FFT veri yolunu bilgisayarda
çalışan hafif bir Python laboratuvar ekranına bağlar. İlk kabul tek RF girişi ve
kontrollü CW ile yapılır. Aynı arayüz sonraki teslimlerde ZX80-DR230-S+,
EV1HMC936ALP6 ve dört durumlu monopulse çevrimini taşıyacaktır.

Uçtan uca ürün sırası şöyledir:

1. Tek girişli canlı FFT ve kayıt.
2. ZX80/HMC936 elektriksel kontrol kapısının kapanması.
3. S0-S3 durumlarının FFT frame'leriyle senkronize edilmesi.
4. Normalize AZ/EL hata hesabı.
5. SMW200A ve yankısız oda kalibrasyonu.

PetaLinux, IIO ve Ethernet bu teslimin çalışma zamanı bağımlılığı değildir.

## 2. Değişmezler

- Mevcut Golden release ve kartta kabul edilmiş `fft-periodic-monitor-v1`
  paketi değiştirilmeyecektir.
- Yeni çalışma ayrı `monopulse-live-lab-v1` Candidate olarak üretilecektir.
- PL FFT boyutu 2048, doğal çıkış sırası ve mevcut `0x6AB` scaling sözleşmesi
  korunacaktır.
- Spectrum verisi 2048 adet unsigned 64-bit magnitude-square kelimesidir.
- Mevcut RX DMAC yolu durdurulmayacak ve FFT shadow capture geri basınç
  üretmeyecektir.
- UART başlangıç hızı `115200-8-N-1` olacaktır.
- İlk sürüm mutlak dBm iddia etmeyecektir. Grafik güç ekseni
  `relative dB, uncalibrated` olarak etiketlenecektir.
- AD9364 tek RX olduğu için eşzamanlı iki dijital RX veya frame'ler arası
  kompleks kanal oranı üretilmeyecektir.

## 3. Kapsam

### 3.1 Bu teslimde

- Bare-metal UART istek/yanıt protokolü
- Tek istekle bir tam 2048-bin spectrum alma
- Frame metadata ve CRC-32 bütünlüğü
- Python seri-port istemcisi
- Canlı FFT çizgisi
- Son 32 geçerli frame için waterfall
- Peak bin, RF frekansı, peak güç ve frame bilgisi
- Donanım sağlık göstergeleri
- Tam ölçümü `.npz`, ölçüm özetini `.csv` olarak kaydetme
- Kontrollü CW ile kart kabulü
- ZX80/HMC936 ve S0-S3 için geriye uyumlu protokol alanları

### 3.2 Sonraki kapılı teslimlerde

- ZX80 `Control1/Control2` sürücüsü
- HMC936A altı-bit phase-code sürücüsü
- 5 V level-shifter/buffer, güvenli `OE` ve FPGA XDC pinleri
- S0-S3 finite-frame monopulse çevrimi
- Ortak peak, CW/band-power ve Q1.31 AZ/EL sonuçlarının canlı karta bağlanması
- Phase-code ve açı kalibrasyonu

### 3.3 Kapsam dışında

- PetaLinux veya IIOD
- `pyadi-iio` ile canlı kart erişimi
- Ethernet üzerinden canlı veri
- Web dashboard
- Wi-Fi paket veya kullanıcı verisi çözme
- Mutlak güç kalibrasyonu tamamlanmadan dBm gösterimi
- Sürekli host/DDR spectrum streaming

Ethernet gelecekte aynı mesaj codec'ini kullanan ayrı bir taşıma adaptörü
olarak eklenebilir. UART protokolü içinde Ethernet'e özgü adres, MTU veya
socket davranışı bulunmayacaktır.

## 4. Sistem mimarisi

```text
AD9364 I0/Q0
    |
    v
geri basınçsız shadow capture
    |
    v
2048 sample RAM -> xFFT v9.1 -> magnitude-square/peak
                                      |
                                      v
                          atomik spectrum BRAM bankası
                                      |
                                      v
                         bare-metal A53 UART servisi
                                      |
                                      v
                         CRC'li little-endian paket
                                      |
                                      v
                  Python serial codec -> NumPy -> Matplotlib
                                      |
                    +-----------------+------------------+
                    |                 |                  |
                 spectrum         waterfall          NPZ/CSV
```

Python uygulaması producer hızını kontrol eder. Her `CAPTURE_ONCE` isteği en
fazla bir spectrum yanıtı üretir. Bu sayede 115200 baud UART, PL capture veya
çift spectrum bankasında birikme oluşturmaz. Canlı görünüm, önceki yanıt
tamamen doğrulandıktan sonra yeni istek göndererek çalışır.

## 5. Candidate çalışma modu

Yeni compile-time uygulama modu `PL_FFT_LAB_UART` olacaktır ve aşağıdaki
modlarla karşılıklı dışlayıcıdır:

- `PL_FFT_SINGLE_SHOT`
- `PL_FFT_PERIODIC_MONITOR`
- `MONOPULSE_FOUNDATION_TEST`
- `WIFI_RF_TEST`
- `DMA_EXAMPLE`

AD9364 başarıyla başlatıldıktan ve PL FFT sürücüsü hazırlandıktan sonra
uygulama:

```text
PL_FFT_LAB: READY protocol=1 bins=2048 baud=115200
```

satırını üretir ve komut bekler. Başlatma veya PL FFT hazırlığı başarısızsa
binary servis açılmaz ve:

```text
PL_FFT_LAB: FAIL stage=<stage> error=<code>
```

satırıyla durur.

## 6. UART protokolü

### 6.1 Byte düzeni ve CRC

- Çok byte'lı tüm tamsayılar little-endian'dır.
- Mesaj sürümü `1`dir.
- CRC `CRC-32/ISO-HDLC` kullanır:
  - reflected polynomial `0xEDB88320`
  - init `0xFFFFFFFF`
  - xorout `0xFFFFFFFF`
- CRC, `magic` ile başlayıp payload'ın son byte'ıyla biten bütün mesaj
  üzerinde hesaplanır; CRC alanının kendisi hesaba katılmaz.
- Mesajlar alan alan kodlanır; C `struct` padding'i veya derleyici ABI düzeni
  seri hatta kopyalanmaz.
- Host bilinmeyen sürümü veya mesaj tipini reddeder.
- `payload_length` izin verilen üst sınırı aşarsa host magic aramasına geri
  döner ve bellek ayırmaz.

### 6.2 Ortak mesaj zarfı

| Alan | Tip | Değer |
|---|---:|---|
| `magic` | 4 byte | Komut için `MPLQ`, yanıt için `MPLR` |
| `version` | `uint8` | `1` |
| `message_type` | `uint8` | Bölüm 6.3 |
| `flags` | `uint16` | Mesaj tipine özgü |
| `payload_length` | `uint32` | Payload byte sayısı |
| `sequence` | `uint32` | Host tarafından artırılan sıra |
| `payload` | byte dizisi | Mesaj tipine özgü |
| `crc32` | `uint32` | Bölüm 6.1 |

Host yanıtı yalnız magic, version, message type, sequence, exact payload
uzunluğu ve CRC birlikte geçerse kabul eder.

### 6.3 Mesaj tipleri

| Değer | Ad | Yön | İşlev |
|---:|---|---|---|
| `0x01` | `GET_INFO` | Host -> kart | Platform/protokol bilgisini ister |
| `0x02` | `INFO` | Kart -> host | Sabit platform ve RF snapshot bilgisini verir |
| `0x03` | `CAPTURE_ONCE` | Host -> kart | Tek FFT frame ister |
| `0x04` | `SPECTRUM` | Kart -> host | Metadata ve 2048-bin spectrum taşır |
| `0x7e` | `ERROR` | Kart -> host | Komut veya donanım hatası taşır |

İlk sürümde kart kendiliğinden spectrum göndermeyecektir. Sürekli görünüm
Python'ın ardışık `CAPTURE_ONCE` komutlarıdır.

### 6.4 `INFO` payload

| Alan | Tip | Değer |
|---|---:|---|
| `board_code` | `uint16` | `1` = AXU4EVB-P |
| `rf_device_code` | `uint16` | `1` = AD9364 |
| `firmware_version` | `uint32` | `0x00010000` |
| `feature_bits` | `uint32` | Bit 0 spectrum, bit 1 peak, bit 2 RF-state metadata |
| `fft_size` | `uint16` | `2048` |
| `spectrum_word_bytes` | `uint8` | `8` |
| `rf_state_count` | `uint8` | İlk sürümde `1`, S0-S3 sürümünde `4` |
| `sample_rate_hz` | `uint32` | AD9364 runtime readback |
| `rx_bandwidth_hz` | `uint32` | AD9364 runtime readback |
| `lo_hz` | `uint64` | AD9364 runtime readback |
| `release_id` | `char[32]` | NUL ile doldurulmuş ASCII Candidate kimliği |

`release_id`, `monopulse-live-lab-v1` değerini taşır. Ayrılmış feature bitleri
ve ayrılmış byte'lar sıfır gönderilir.

### 6.5 `CAPTURE_ONCE` payload

| Alan | Tip | İlk sürüm |
|---|---:|---:|
| `search_start` | `uint16` | `0` |
| `search_stop` | `uint16` | `2047` |
| `dc_guard` | `uint16` | `0` veya kullanıcı ayarı |
| `rf_state` | `uint8` | Tek giriş için `0` |
| `reserved` | `uint8` | `0` |

Geçersiz aralık veya `rf_state > 7` için spectrum üretilmez; aynı sequence ile
`ERROR` yanıtı verilir.

### 6.6 `SPECTRUM` payload

| Alan | Tip |
|---|---:|
| `frame_id` | `uint32` |
| `sample_count` | `uint16` |
| `fft_size` | `uint16` |
| `sample_rate_hz` | `uint32` |
| `rx_bandwidth_hz` | `uint32` |
| `lo_hz` | `uint64` |
| `frame_crc32` | `uint32` |
| `skipped_sample_count` | `uint32` |
| `peak_power` | `uint64` |
| `peak_bin` | `uint16` |
| `peak_re` | `int16` |
| `peak_im` | `int16` |
| `reset_epoch` | `uint16` |
| `rf_state` | `uint8` |
| `active_bank` | `uint8` |
| `hardware_flags` | `uint16` |
| `reserved` | `uint16` |
| `spectrum` | `uint64[2048]` |

`skipped_sample_count`, finite shadow-capture dışında geçen örneklerin
kümülatif sayacıdır; tek başına capture kaybı veya kırmızı hata olarak
yorumlanmayacaktır. `hardware_flags` içindeki frame, FFT, overflow, CDC,
bank-overrun veya capture-sırasında-drop bayrağı ayrı sağlık durumudur.

`hardware_flags` bit eşlemesi:

| Bit | Anlam |
|---:|---|
| 0 | `frame_error` |
| 1 | `fft_error` |
| 2 | `fft_overflow` |
| 3 | `cdc_fault` |
| 4 | `bank_overrun` |
| 5 | `dropped_during_capture` |
| 6-15 | Ayrılmış, sıfır |

### 6.7 `ERROR` payload

| Alan | Tip | Anlam |
|---|---:|---|
| `error_code` | `int32` | Mevcut `PL_FFT_ERR_*` değeri |
| `stage` | `uint16` | 1 parse, 2 config, 3 busy, 4 capture, 5 UART |
| `detail` | `uint16` | Protokol v1'de ayrılmış ve daima sıfır |

Bir `ERROR` mesajı hataya neden olan komutun sequence değerini taşır.

## 7. Python laboratuvar uygulaması

### 7.1 Bağımlılıklar

- `pyserial`
- `numpy`
- `matplotlib`

Web framework, Qt/PySide, notebook sunucusu veya IIO bağımlılığı
eklenmeyecektir.

### 7.2 Komut satırı

```powershell
python PROJECT\tools\axu4ev_fft_lab.py --port COM5
```

Opsiyonlar:

- `--port`: zorunlu COM portu
- `--baud`: varsayılan `115200`
- `--interval-ms`: başarılı yanıtlar arasındaki host beklemesi, varsayılan `250`
- `--history`: waterfall derinliği, varsayılan ve maksimum `32`
- `--output-dir`: kayıt dizini, varsayılan `PROJECT/lab-captures`
- `--single`: tek frame al, kaydet ve çık

PuTTY ve Python aynı COM portunu eşzamanlı açmayacaktır. Grafik kullanılacağı
zaman PuTTY kapalı tutulur.

Tam 2048-bin yanıtın 115200 baud aktarım süresi nedeniyle bir komut için host
timeout'u `5 saniye` olacaktır. Yeni istek önceki mesajın CRC kontrolü ve
işlenmesi tamamlanmadan gönderilmez.

### 7.3 Görünüm

Ekran iki ana panel ve küçük bir sağlık alanı kullanır:

1. Üst panel: merkezlenmiş RF frekans ekseninde canlı spectrum.
2. Alt panel: son 32 geçerli frame'in waterfall görünümü.
3. Sağlık alanı:
   - frame ID ve protocol sequence
   - LO, sample-rate, bandwidth
   - RF state
   - peak bin, peak RF frekansı ve relative peak dB
   - CRC durumu
   - hardware flag özeti
   - skipped sample sayacı

Doğal FFT bin sırası ekranda merkezlenecektir:

```text
offset(k) = k * Fs / N,           k < N/2
offset(k) = (k - N) * Fs / N,     k >= N/2
rf_frequency(k) = LO + offset(k)
```

Güç gösterimi:

```text
relative_db(k) = 10 * log10(max(power(k), 1))
```

Mutlak ADC/FFT scaling ve RF path kalibrasyonu tamamlanmadan eksen `dBm`
etiketi kullanmayacaktır.

### 7.4 Kayıt

Kullanıcı `Save` düğmesine bastığında veya `--single` kullandığında:

- `.npz`:
  - tam `uint64[2048]` spectrum
  - merkezlenmiş RF frekans ekseni
  - bütün frame metadata'sı
  - ham mesaj CRC'si
- `.csv`:
  - zaman
  - Candidate release kimliği
  - frame ID
  - LO/Fs/BW
  - RF state
  - peak bin/frekans/güç
  - hardware flags
  - NPZ dosya adı

Kaydedilen dosya adları UTC zaman ve frame ID içerir. Aynı isimli dosyanın
üzerine yazılmaz.

## 8. Hata yönetimi

- UART timeout: mevcut grafik korunur, durum `TIMEOUT` olur ve kontrollü retry
  yapılır.
- CRC hatası: frame çizilmez veya kaydedilmez; magic aramasıyla resync yapılır.
- Sequence uyuşmazlığı: yanıt reddedilir.
- Eksik/uzun payload: yanıt reddedilir ve sabit üst sınırın üzerinde bellek
  ayrılmaz.
- `sample_count != 2048` veya `fft_size != 2048`: frame reddedilir.
- Fatal hardware flag: frame diagnostik olarak listelenir fakat waterfall ve
  kabul kaydına alınmaz.
- Python kapanışı: seri port her durumda serbest bırakılır.
- Kart komut alırken meşgulse aynı sequence ile `ERROR/BUSY` döner; gizli retry
  yapmaz.

## 9. ZX80/HMC936 entegrasyon sınırı

Nihai monopulse ürünü bu laboratuvar ekranının devamıdır. Ancak fiziksel
kontrol aşağıdaki kapılar kapanmadan XDC veya GPIO RTL'ine bağlanmayacaktır:

- BDC IF merkezi ve işgal bandı HMC936A'nın `1.2-1.4 GHz` aralığında olmalı.
- ΔAZ/ΔEL ile ZX80 RF1/RF2 eşlemesi süreklilik testiyle kaydedilmeli.
- ZX80 VDD ve kontrol lojik seviyeleri doğrulanmalı.
- HMC936A için altı kanallı 5 V level-shifter/buffer ve güvenli `OE`
  belirlenmeli.
- Altı phase bit ve iki ZX80 kontrolü için sekiz FPGA pini, bank voltajı ve XDC
  tablosu onaylanmalı.
- Settle ve discard değerleri SMW200A ile ölçülmeli.

Bu kapılardan sonra protocol version değiştirilmeden `rf_state=0..3`
kullanılacaktır:

| RF state | ZX80 | HMC936 | Ölçüm |
|---:|---|---|---|
| `0` | ΔAZ | PLUS | `P_AZ_PLUS` |
| `1` | ΔAZ | MINUS | `P_AZ_MINUS` |
| `2` | ΔEL | PLUS | `P_EL_PLUS` |
| `3` | ΔEL | MINUS | `P_EL_MINUS` |

Python aynı dört spectrum paketini state etiketiyle gruplayacak; ortak peak,
CW/band-power ve Q1.31 AZ/EL sonuçları sonraki monopulse-cycle mesajında
gösterilecektir.

## 10. Doğrulama

### 10.1 Host

- Zarf encode/decode golden byte testleri
- CRC bozulması, truncation, yanlış version/type ve aşırı payload testleri
- Gürültülü byte akışında magic resync testi
- 2048-bin exact round-trip
- Doğal bin -> merkezlenmiş frekans ekseni testi
- Peak metadata ile NumPy argmax tutarlılığı
- NPZ/CSV aynı-frame kimliği ve üzerine yazmama testi

### 10.2 Bare-metal

- C encoder'ın Python golden mesajıyla byte-exact eşleşmesi
- Geçerli/geçersiz `CAPTURE_ONCE` komutları
- Busy ve PL FFT hata yanıtları
- UART partial-write davranışı
- Mevcut single-shot ve periodic Candidate regresyonu

### 10.3 Kart

İlk fiziksel kabul:

1. Yeni Candidate JTAG üzerinden başlar.
2. Python `GET_INFO` ve en az 10 ardışık `CAPTURE_ONCE` çalıştırır.
3. Bütün yanıtlar CRC ve exact 2048-bin kontrolden geçer.
4. Kontrollü CW, yapılandırılmış arama penceresinde bulunur.
5. Peak bin ardışık geçerli frame'lerde en fazla `±1` bin değişir.
6. Frame, FFT, overflow, CDC ve bank-overrun fatal flag'leri sıfırdır.
7. Kaydedilen NPZ spectrum ile ekrandaki peak aynıdır.
8. Kabul kaydı Candidate/ELF/bitstream hash'lerini ve SMW200A ayarlarını
   içerir.

Bu kabul FFT grafik ve taşıma kapanışıdır; monopulse açı kabulü değildir.

### 10.4 Nihai monopulse kabulü

ZX80/HMC936 entegrasyonundan sonra:

- S0-S3 state etiketi fiziksel kontrolle birebir eşleşir.
- Dört durumda ortak CW peak farkı en fazla `±1` bindir.
- PLUS/MINUS güçleri beklenen işaret değişimini üretir.
- Mekanik `+theta` ve `-theta` için düzeltilmiş AZ/EL hata işaretleri terstir.
- Sıfır bias, AZ/EL eğimleri ve phase-code kalibrasyonu kayıt altındadır.
- Kabul sınırları ilk oda ölçümü ve anten HPBW verisiyle sayısallaştırılır.

## 11. Teslim ayrımı

Bu tasarım üç bağımsız uygulama planına bölünecektir:

1. **Lab transport ve Python ekranı:** UART codec, Candidate, grafik ve
   kontrollü CW kabulü.
2. **RF kontrol ve S0-S3:** Elektriksel kapı, ZX80/HMC936 sürücüsü, settle,
   state-tag ve dört spectrum çevrimi.
3. **Kalibrasyon ve nihai kabul:** phase-code, mekanik sıfır, AZ/EL eğimi,
   tekrarlanabilirlik ve sonuç raporu.

Birinci teslim ikinci teslimin fiziksel bilgilerini beklemeden tamamlanabilir.
İkinci ve üçüncü teslimler, mevcut
`PROJECT/designs/2026-07-20-rf-control-hardware-contract.md` ile
`PROJECT/designs/2026-07-20-axu4ev-ad9364-single-channel-monopulse-design.md`
sözleşmelerini değiştirmez; onları canlı ölçüm arayüzüne bağlar.
