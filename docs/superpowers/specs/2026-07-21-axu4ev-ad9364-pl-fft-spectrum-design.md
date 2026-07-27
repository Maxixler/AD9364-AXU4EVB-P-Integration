# AXU4EVB-P + AD9364 PL FFT ve Tam Spektrum Tasarımı

**Tarih:** 21 Temmuz 2026

**Durum:** Kullanıcı tarafından onaylanan mimarinin iki teknik inceleme raporuyla uzlaştırılmış sürümü

**Hedef:** Mevcut AD9364 DMA yolunu bozmadan 2048 noktalı FFT, tam spektrum ve peak çıktısı üretmek

## 1. Kapsam ve bağlayıcı kararlar

İlk PL teslimi tek gerçek AD9364 RX kanalındaki doğrulanmış `I0/Q0` örneklerini
işleyen non-blocking shadow path'tir. Mevcut `util_ad9361_adc_pack -> DMAC` yolu
aynı kalır; FFT yolu hiçbir koşulda bu yola backpressure uygulayamaz.

Teslim iki çalışma biçimini destekler:

1. **Tek-kare:** PS `START` verir, tam 2048 kompleks örnek yakalanır, tek FFT
   tamamlanır ve sonuç bankası atomik olarak yayınlanır.
2. **Sürekli:** Kabul edilmiş her 2048 örneklik frame işlenir. İki spectrum
   bankası ping-pong çalışır; PS yalnız tamamlanmış ve `FRAME_ID` ile etiketli
   bankayı okur. Okunmamış banka üzerine yazma yapılırsa sticky overrun oluşur.

Uygulama sırası tek-kare doğrulaması, ardından aynı arayüz üzerinde sürekli moddur.
Sürekli host/DDR spectrum streaming bu teslimin parçası değildir.

## 2. Veri yolu

```text
AD9364 LVDS
  -> axi_ad9361
  -> util_ad9361_adc_fifo
       +-> mevcut adc_pack -> DMAC -> DDR        (değişmez Golden yol)
       +-> pasif I0/Q0 tap -> 2048-word capture  (yeni shadow yol)
                              -> AXIS replay
                              -> rectangular window bypass
                              -> FFT v9.1, N=2048
                              -> magnitude-square
                                  +-> peak detector
                                  +-> spectrum ping-pong BRAM
```

Tap noktası ve gerçek `I0/Q0`, signed hizalama, valid/enable ilişkisi ILA ve DMA
ile kanıtlanmadan bridge port sözleşmesi dondurulmaz. Mantıksal örnek `(I,Q)`,
fiziksel 32-bit word `{Q[15:0], I[15:0]}` olarak korunur.

Capture tarafı ADI-native valid/enable boşluklarını kabul eder. Tam 2048 kabul
edilmiş kompleks örnek olmadan replay başlamaz. FFT `TREADY` stall olduğunda
frame capture RAM'de korunur; upstream ADI/DMA yolu durdurulmaz.

## 3. Sayısal sözleşme

- FFT uzunluğu: 2048
- İlk sample rate: runtime readback ile 30.72 MSPS
- İlk RF bandwidth hedefi: runtime readback ile 10 MHz
- Pencere: ilk bit-doğru teslimde rectangular/bypass
- Hann: ayrı doğrulama alt aşaması; datapath ekleme noktası korunur
- FFT: Vivado 2020.1 FFT v9.1, forward, natural order
- Giriş/çıkış: signed 16-bit I ve signed 16-bit Q
- Scaling schedule: `SCALE_SCH=0x6AB`
- Rounding/saturation: bit-true model ve IP konfigürasyonunda aynı
- Güç: unsigned 33-bit `Re^2 + Im^2`
- Spectrum storage word: 64-bit; alt 33 bit güç, üst bitler sıfır
- Bit-doğru dijital kabul: tanımlı vektörlerde 0 LSB fark

`numpy.fft` yalnız floating-point oracle olabilir. Bağlayıcı karşılaştırma,
IP ile aynı scaling, rounding ve saturation kurallarını uygulayan integer
bit-true modeldir.

## 4. Peak ve spektrum çıktısı

Her tamamlanmış frame için tüm 2048 güç bin'i BRAM'de saklanır. Donanım doğal
sırayı korur; görsel `fftshift` PS/Python tarafındadır.

Peak araması yapılandırılmış `[SEARCH_START, SEARCH_STOP]` aralığındadır ve DC
guard bin'lerini dışlar. Eşit güçte deterministik olarak en küçük bin seçilir.

Sonuçlar:

- `PEAK_BIN`
- `PEAK_POWER`
- `PEAK_RE`, `PEAK_IM`
- `FRAME_ID`, `RF_STATE`, `SPECTRUM_BANK`
- sample count, ilk-örnek imzası ve CRC-32/ISO-HDLC

`PEAK_RE/IM` tek-frame doğrulama ve diagnostik veridir. AD9364 tek RX olduğu ve
monopulse S0-S3 frame'leri ardışık yakalandığı için bu değerlerden ürün seviyesinde
kompleks `Delta/Sigma` oluşturulmaz. Bağlayıcı monopulse sonucu güç tabanlıdır.

## 5. Bellek ve bankalama

Bir 2048 x 64-bit spectrum bankası 131072 bit, yani 16 KiB'dir. Primitive
yerleşimine bağlı minimum yaklaşık dört BRAM36'dır. Sürekli mod için iki bankaya
yaklaşık sekiz BRAM36 bütçelenir. Capture RAM, Hann ROM ve FFT iç belleği ayrıca
bütçelenir; kesin kaynak kabulü sentez/implementation utilization raporudur.

PL tamamlanan bankaya metadata yazar, sonra bank-valid toggle/handshake yayınlar.
PS metadata'yı okuyup bankayı tüketir ve release verir. Bank ownership atomik
olmalıdır; kısmi frame görünür yapılmaz.

## 6. Kontrol, CDC ve hata sözleşmesi

AXI-Lite yalnız control/status içindir; 2048-bin payload AXI BRAM üzerinden okunur.

Temel kontrol alanları:

- `START`, `ABORT`, `SOFT_RESET`
- `MODE_SINGLE`, `MODE_CONTINUOUS`
- `SEARCH_START`, `SEARCH_STOP`, `DC_GUARD`
- `WINDOW_SELECT`
- `RESET_EPOCH`

Temel status/sonuç alanları:

- `BUSY`, `DONE`, `SPECTRUM_VALID`, `ACTIVE_BANK`
- `FRAME_ID`, `RF_STATE`, `SAMPLE_COUNT`
- `PEAK_BIN`, `PEAK_POWER`, `PEAK_RE`, `PEAK_IM`
- `CDC_READY`, `CDC_FAULT`, `ABORTED`
- `FRAME_ERROR`, `FFT_ERROR`, `OVERFLOW`, `DROPPED_SAMPLES`
- `BANK_OVERRUN`, `CONFIG_ERROR`

Control/config bir bundled command mailbox ile, frame metadata ters yönlü ikinci
handshake ile domainler arasında atomik taşınır. `reset_epoch` tek taraflı reset
sonrası eski command veya metadata'nın kabul edilmesini engeller.

## 7. RF ve monopulse ile sınır

ZX80-DR230-S+ DC-3 GHz SPDT'dir. HMC936A yalnız 1.2-1.4 GHz'de dereceli, altı
bitli ve 0/+5 V kontrollüdür. HMC BDC sonrası Delta IF yolunda kullanılacaktır.
Gerçek BDC IF 1.2-1.4 GHz içinde ölçülmeden AD9364 monopulse LO'su sabitlenmez.

İlk elektriksel bring-up PS/manual kontrolle yapılabilir. Nihai S0-S3 çevrimi
PL FSM tarafından state-tag, settle ve discard ile yürütülür:

```text
S0 = Sigma + Delta_AZ
S1 = Sigma - Delta_AZ
S2 = Sigma + Delta_EL
S3 = Sigma - Delta_EL
```

Ürün sonucu:

```text
AZ_ERROR = (P_AZ_PLUS - P_AZ_MINUS) / (P_AZ_PLUS + P_AZ_MINUS)
EL_ERROR = (P_EL_PLUS - P_EL_MINUS) / (P_EL_PLUS + P_EL_MINUS)
```

Kompleks frame-to-frame oran ancak ortak referans, BDC göreli faz drift'i ve LO
phase continuity ayrı deneyle kanıtlanırsa yeni bir tasarım olarak ele alınır.

## 8. Geliştirme ve kabul sırası

1. Temiz Vivado 2020.1 Candidate build ve aktif Tcl/XDC kaynak kimliği.
2. ILA/DMA ile I0/Q0 formatı, valid/enable ve gerçek `clk_out` ölçümü.
3. Bit-true Python/C vektör modeli.
4. Non-blocking 2048-word capture ve AXIS replay testleri.
5. Tek-kare FFT, full spectrum, peak ve metadata kapanışı.
6. Kartta CW ile DMA/PL/CRC çapraz doğrulama.
7. Ping-pong bankalama ve sürekli mod throughput/overrun testleri.
8. RF level-shifter, pin, BDC IF ve settle/discard elektriksel kapısı.
9. Dört-durum PL FSM ve güç tabanlı AZ/EL oranı.
10. Yankısız oda kalibrasyonu; daha sonra gerekirse PetaLinux/IIOD/pyadi-iio.

Golden bitstream/XSA/ELF değiştirilmez. Her kapı bağımsız Candidate artefaktı,
test kaydı ve timing/DRC veya yazılım regresyonu üretir.

## 9. Açık donanım girdileri

PL FFT'nin dijital geliştirmesini engellemeyen, fakat RF kontrol RTL/XDC'sinden
önce kapanması gereken girdiler:

- BDC RF/LO/IF planı ve ortak referans bağlantısı
- ZX80 RF1/RF2 kablo eşlemesi ve regüle VDD seçimi
- HMC936A altı-bit 5 V buffer/level-shifter şeması ve güvenli `OE`
- Sekiz FPGA çıkışının kesin connector/pin/bank gerilimleri
- Ölçülmüş switch/phase-shifter settle ve discard süreleri
- Anten HPBW ve açı kabul/RMSE sınırı
