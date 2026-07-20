# AXU4EVB-P + AD9364 Tek Kanallı Monopulse FFT Tasarımı

**Tarih:** 20 Temmuz 2026

**Durum:** Kullanıcı tarafından mimari, DSP ve kalibrasyon bölümleri onaylandı; ZX80-DR230-S+ ile EV1HMC936ALP6 parça kimlikleri doğrulandı; fiziksel pin/level-shifter/IF sözleşmesi henüz tamamlanmadı ve RTL uygulanmadı.

**Hedef platform:** ALINX AXU4EVB-P + mevcut AD9364 tabanlı RF kartı

**Bağlayıcı şema:** Kullanıcının 20 Temmuz 2026 tarihinde paylaştığı Σ/ΔAZ/ΔEL, SPDT, 0°/180° phase switch, combiner ve tek RX zinciri
**Referans çalışma:** `Related-Docs/Antenna_Tracking_Techniques_for_Long_Range_Air-to- (1).pdf`; yalnız algoritma ve test referansıdır, bağlayıcı donanım şeması değildir.

## 1. Amaç ve kapsam

Bu tasarım, yankısız odada Rohde & Schwarz SMW200A ile üretilen kontrollü RF sinyalini monopulse alıcı anten ve hazır analog ön uç üzerinden alarak aşağıdaki sonuçları AXU4EVB-P üzerinde üretir:

- Tek AD9364 RX kanalından finite-frame I/Q yakalama
- Tek ve zaman paylaşımlı FFT çekirdeği
- Modülasyonsuz taşıyıcı için ortak maksimum peak tespiti
- 5-10 MHz işgal bantlı sinyal için bant gücü ölçümü
- `Σ+ΔAZ`, `Σ-ΔAZ`, `Σ+ΔEL`, `Σ-ΔEL` güçleri
- Normalize `AZ_ERROR` ve `EL_ERROR`
- Kalibre edilmiş tahmini azimuth/elevation hata açısı

İlk ürün kesintisiz streaming yapmaz. Dört analog durumu sırayla yakalayan, doğrulanabilir finite-frame Candidate geliştirir. Mevcut Golden bitstream/XSA/ELF değişmez tutulur; yeni tasarım ayrı Candidate olarak üretilir.

## 2. Donanım gerçekleri ve kapsam sınırı

### 2.1 Hedef transceiver

Mevcut AD9364 1x1 transceiver'dır. RXA/RXB, eşzamanlı iki dijital alıcı kanalı değildir; tek RX zincirine seçilebilen RF girişleridir. Bu nedenle hedef sistemde iki kompleks kanal aynı anda örneklenmeyecek ve ardışık frame'ler faz-koherent iki dijital kanal olarak sunulmayacaktır.

### 2.2 Fotoğraftaki eski/referans düzen

20 Temmuz 2026 tarihli yakın çekimde görülen kart `AD-FMCOMMS3-EBZ` ve bağlı portlar `RX1A` ile `RX2A`dır. Bu kart AD9361 tabanlı gerçek 2Rx referans düzendir. Fotoğraf, yankısız oda, BDC ve ölçüm altyapısının varlığını kanıtlar; hedef RF kartını değiştirmez. AD9361/FMCOMMS3 kaynakları AXU4EVB-P + AD9364 Candidate'a yanlışlıkla taşınmayacaktır.

### 2.3 Phase switch'in rolü

0°/180° bi-phase switch antenin mekanik azimuth açısını doğrudan değiştirmez. Seçilen fark yolunu işaretçe tersler:

```text
0°   : +Δ
180° : -Δ
```

Tek başına bir RF yoluna 180° uygulamak FFT gücünü değiştirmez. Yön bilgisi, Δ'nın Σ ile analog combiner'da toplanması ve çıkarılması sayesinde oluşur.

Bu Candidate tam keyfi kompleks `angle(Σ/Δ)` ölçmez. 0°/180° çiftinden elde edilen fiziksel büyüklük:

```text
P_plus - P_minus = 4 * Re{Σ * conjugate(Δ)}
```

Tam kompleks faz farkı veya quadrature kalibrasyonu istenirse 90°/270° durumları veya gerçek eşzamanlı ikinci RX içeren ayrı mimari gerekir.

### 2.4 Doğrulanan harici kontrol donanımı

Harici yol seçici Mini-Circuits `ZX80-DR230-S+`, phase shifter ise Analog Devices `EV1HMC936ALP6` üzerindeki `HMC936ALP6E`dir. Ayrıntılı elektriksel sözleşme `PROJECT/designs/2026-07-20-rf-control-hardware-contract.md` dosyasındadır.

Kritik sonuçlar:

- ZX80 iki kontrol pinli, absorptive SPDT'dir; `00` iki yolu kapatır, `10` RF1'i, `01` RF2'yi seçer ve `11` yasaktır.
- HMC936A 1.2-1.4 GHz için 6-bit, 5.625° adımlı phase shifter'dır; basit tek-bit 0/180 switch değildir.
- HMC kontrolü aktif-düşüktür: referans faz `111111`, nominal 180° `011111` fiziksel kodudur.
- HMC kontrol HIGH seviyesi yaklaşık 5 V istediği için AXU4EVB-P GPIO doğrudan bağlanmaz; altı bitlik 5 V level-shifter/buffer zorunludur.
- HMC'nin çalışma bandı nedeniyle seçilebilir Delta yolu BDC sonrası 1.2-1.4 GHz IF olmalıdır; gerçek BDC IF frekansı ayrı kabul kapısıdır.

## 3. Bağlayıcı sistem mimarisi

```text
R&S SMW200A
  -> verici anten
  -> yankısız oda
  -> monopulse alıcı anten / comparator
       -> Σ   -> coherent BDC Σ ------------------------------+
       -> ΔAZ -> coherent BDC ΔAZ --+                         |
       -> ΔEL -> coherent BDC ΔEL --+-> SPDT -> HMC936A ------+-> IF combiner -> AD9364 RX
                                                                  |
                                                                  v
                                                     AXU4EVB-P finite-frame DSP
```

Üç BDC ortak LO/referans kullanmalı ve göreli fazları ölçüm çevrimi boyunca kararlı kalmalıdır; aksi halde `Σ±Δ` işareti ve `phase_base` kalibrasyonu fiziksel anlamını kaybeder. Analog ön uç AD9364'e tek bir birleşik IF hattı verir. DSP/FSM iki mantıksal kontrol üretir:

- `delta_select`: `AZ` veya `EL`
- `phase_180`: kalibre edilmiş PLUS veya yaklaşık `+180°` MINUS durumu

Fiziksel adaptör mantıksal `delta_select` değerini ZX80 `Control1/Control2` çiftine, mantıksal faz durumunu ise altı HMC bitine çevirir. `phase_base` kalibrasyon kodu desteklenir; nominal MINUS kodu `phase_base+32 (mod 64)` olur. SPDT RF1/RF2 kablo yönü, sekiz FPGA kontrol pini, I/O bankları ve 5 V level-shifter tamamlanmadan XDC yazılmaz. Mevcut AD9364 `gpio_ctl` hatları serbest FPGA pini sayılmaz.

## 4. Vitis ve PL görev ayrımı

### Vitis / PS

- AD9364 RX-only initialization
- Runtime LO, sample-rate, RF bandwidth, gain ve ENSM readback
- TX attenuation'ı başlangıçtan itibaren 89.750 mdB yapma
- Bütün AXI DAC kanallarını `AXI_DAC_DATA_SEL_ZERO` yapma ve readback
- Ölçüm modu, arama bandı, settle/discard ve eşik register'larını yazma
- Ölçümü başlatma, status/hata okuma
- Kalibrasyon katsayılarını saklama ve raporlama
- Spectrum/ölçüm sonuçlarını UART, dosya veya ileride Linux/IIO'ya aktarma

### Vivado / PL

- ZX80 iki-hat yol seçimi ve HMC936A altı-bit phase-code kontrol FSM'i
- Yerleşme bekleme ve geçiş örneklerini discard etme
- ADI-native I/Q çıkışından 2048 örneklik non-blocking capture
- CDC-safe store-and-forward replay
- Rectangular/Hann pencereleme
- Tek 2048-point FFT
- Magnitude-square, spectrum buffer ve ortak peak araması
- CW peak veya configured band-power toplamı
- Dört durumun güçlerini, pay/payda ve Q1.31 hata oranlarını üretme
- Clip, sample-drop, FFT event, switch timeout ve küçük-payda denetimleri

## 5. Varsayılan DSP profili

| Alan | İlk Candidate |
|---|---|
| AD9364 sample rate | 30.72 MSPS |
| RX analog bandwidth | 10 MHz; runtime readback zorunlu |
| FFT uzunluğu | 2048 |
| Capture süresi | Yaklaşık 66.67 µs/frame |
| FFT IP | Vivado 2020.1 FFT v9.1, tek core |
| FFT ölçekleme | Mevcut bit-true plan sözleşmesi `SCALE_SCH=0x6AB` |
| İlk pencere | Rectangular bit-doğrulama; RF ölçümünde Hann desteği |
| İlk RF uyarımı | SMW200A CW, LO'dan DC guard dışına kontrollü offset |
| TX | Mute; DAC ZERO + 89.750 mdB + readback |

`30.72 MSPS` ile bin aralığı 15 kHz'tir. Daha ince CW frekans kestirimi gerekirse önce üç-bin interpolasyonu veya kontrollü dijital decimation değerlendirilir; FFT uzunluğu gerekçesiz büyütülmez.

## 6. Dört durumlu ölçüm FSM'i

Bir tam ölçüm çevrimi:

| Durum | SPDT | Phase | Analog sonuç | Saklanan güç |
|---|---|---:|---|---|
| S0 | ΔAZ | 0° | Σ + ΔAZ | `P_AZ_PLUS[k]` |
| S1 | ΔAZ | 180° | Σ - ΔAZ | `P_AZ_MINUS[k]` |
| S2 | ΔEL | 0° | Σ + ΔEL | `P_EL_PLUS[k]` |
| S3 | ΔEL | 180° | Σ - ΔEL | `P_EL_MINUS[k]` |

Her durum aynı alt akışı kullanır:

```text
SET_PATH
-> SET_PHASE
-> SETTLE
-> DISCARD
-> CAPTURE_2048
-> FFT_REPLAY
-> MAGNITUDE_SQUARE
-> STORE_SPECTRUM
-> NEXT_STATE
```

`settling_cycles` processing-clock cycle, `discard_samples` ise kabul edilen kompleks ADC örneği cinsindedir. ZX80 tipik switching süresi 2 us, HMC936A tipik switching süresi 250 ns'dir; bunlar garanti edilen maksimum değildir. İlk laboratuvar başlangıcı 10 us settle'dır ve nihai değer SMW200A ile yapılan geçiş-kararlılığı ölçümünden seçilir.

Capture store-and-forward'dır. FFT `TREADY` durumu canlı ADC veya mevcut RX DMAC yoluna backpressure uygulayamaz. Tek buffer Candidate'da capture ve FFT replay aynı anda yapılmaz.

## 7. Ortak peak ve güç hesabı

### 7.1 CW peak modu

Dört spektrum toplandıktan sonra ortak referans oluşturulur:

```text
P_REF[k] = P_AZ_PLUS[k] + P_AZ_MINUS[k]
         + P_EL_PLUS[k] + P_EL_MINUS[k]
```

Peak yalnız Vitis'in yapılandırdığı beklenen taşıyıcı arama penceresinde bulunur:

```text
k_peak = argmax(P_REF[k])
```

DC çevresi ayrı guard band ile arama dışında bırakılır. Bir durumdaki yıkıcı birleşim peak'i zayıflatsa bile ortak toplam yanlış taşıyıcı seçimini azaltır.

Her durumun scalar gücü peak ve iki yan komşu bin üzerinden hesaplanır:

```text
P_X = sum(P_X[k]), k = k_peak-2 ... k_peak+2
```

### 7.2 Band-power modu

5-10 MHz işgal bantlı modülasyonlu sinyalde tek maksimum bin güç ölçütü sayılmaz:

```text
P_X = sum(P_X[k]), k = configured_band_start ... configured_band_stop
```

CW peak modu ilk Candidate kabulüdür. Band-power modu aynı FFT sonucu üzerinde ayrı konfigürasyonla etkinleştirilir.

## 8. Monopulse hata aritmetiği

```text
AZ_NUM = signed(P_AZ_PLUS) - signed(P_AZ_MINUS)
AZ_DEN = P_AZ_PLUS + P_AZ_MINUS
AZ_ERROR = AZ_NUM / AZ_DEN

EL_NUM = signed(P_EL_PLUS) - signed(P_EL_MINUS)
EL_DEN = P_EL_PLUS + P_EL_MINUS
EL_ERROR = EL_NUM / EL_DEN
```

`AZ_ERROR` ve `EL_ERROR` signed Q1.31, nominal `[-1,+1]` aralığındadır. İlk ürün oranı yalnız scalar peak/band gücü üzerinde hesaplar; 2048 binin her biri için divider oluşturmaz. Kaynak bütçesi uygunsa düşük-throughput iteratif PL divider kullanılır. Divider eklenmeden önce pay, payda ve PS/Python referansı bit-doğru doğrulanır.

Payda `denominator_threshold` altında ise sonuç saturate edilmez; frame `denominator_small` ile geçersiz sayılır. Ham dört güç, pay, payda, peak bin ve hata sonucu birlikte okunabilir olmalıdır.

## 9. Kalibrasyon

### 9.1 Test hazırlığı

RF açılmadan önce test kaydı şunları içermelidir:

- SMW200A frekansı, çıkış seviyesi ve modülasyon modu
- Antenler arası mesafe, anten açıklığı, polarizasyon ve mekanik sıfır
- Uzak alan koşulunun anten ölçülerine göre hesabı
- BDC RF/LO/IF frekansları, kazançları ve seri numaraları
- Üç BDC'nin ortak LO/referans bağlantısı, göreli faz drift ölçümü ve kanal kalibrasyonu
- Kablo/combiner kayıpları
- SPDT/phase-switch kontrol polaritesi
- AD9364 runtime LO, bandwidth, sample rate ve sabit MGC değeri

Generator düşük güçten başlatılır. Dört durumda ortak MGC kullanılır; ölçüm çevrimi sırasında AGC veya gain değişimine izin verilmez.

### 9.2 Sıfır ve açı süpürmesi

1. Mekanik `AZ=0°, EL=0°` konumunda tekrarlı dört-durum ölçümleri alınır.
2. `AZ` süpürülürken `EL=0°`, `EL` süpürülürken `AZ=0°` tutulur.
3. HPBW bilinmiyorsa önce kaba güç taramasıyla bulunur.
4. Kalibrasyon, ana lobun yaklaşık doğrusal merkez bölgesinde yapılır.
5. Her açı için en az 20 tam dört-durum çevrimi, ortalama, standart sapma, peak bin/güç ve hata bayrakları kaydedilir.

Sıfır biasları:

```text
AZ_BIAS = mean(AZ_ERROR at mechanical zero)
EL_BIAS = mean(EL_ERROR at mechanical zero)
```

İlk açı modeli:

```text
E_AZ = m_AZ * theta_AZ + b_AZ
theta_AZ_hat = (E_AZ - b_AZ) / m_AZ
```

Elevation ayrı katsayı kullanır. Doğrusal model yetersizse ancak ölçüm kanıtıyla LUT veya düşük dereceli polinom eklenir.

Kalibrasyon sonrasında `E(+theta) ~= -E(-theta)` beklenir. Eğim yoksa veya çok küçükse analog Σ/Δ faz eşleşmesi/yol bağlantısı düzeltilmeden yazılımla güvenilir açı üretilmez.

## 10. Register ve sonuç sözleşmesi

Zorunlu kontrol alanları:

- `start`, `abort`, `soft_reset`
- `measurement_mode`: CW peak veya band power
- `settling_cycles`, `discard_samples`
- `search_bin_start`, `search_bin_stop`, `dc_guard_bins`
- `band_bin_start`, `band_bin_stop`
- `denominator_threshold`
- `window_select`

Zorunlu status/sonuç alanları:

- `busy`, `done`, `state_id`, `frame_id`
- `peak_bin`, `peak_power`, `peak_frequency_metadata`
- `P_AZ_PLUS`, `P_AZ_MINUS`, `P_EL_PLUS`, `P_EL_MINUS`
- `AZ_NUM`, `AZ_DEN`, `AZ_ERROR`
- `EL_NUM`, `EL_DEN`, `EL_ERROR`
- `fifo_overflow`, `dropped_samples`, `frame_error`
- `fft_error`, `arithmetic_overflow`, `denominator_small`
- `clipping_detected`, `switch_timeout`, `rf_metadata_changed`
- `cdc_ready`, `cdc_fault`, `reset_epoch`

## 11. Hata yönetimi

Bir ölçüm aşağıdaki koşullardan herhangi birinde geçersizdir:

- Eksik/fazla sample veya capture sırasında sample drop
- FFT event/overflow
- AD9364 veya dijital magnitude clipping
- Beklenen arama penceresinde peak bulunamaması
- Dört durumda peak bin'in izin verilen ±1 bin sınırını aşması
- Dört durum tamamlanmadan RF metadata/gain değişmesi
- Küçük payda
- SPDT/phase yerleşme süresinin dolmaması
- CDC epoch veya state-tag uyuşmazlığı

Hatalı çevrimde önceki geçerli AZ/EL sonucu yeniymiş gibi yayımlanmaz. Status hata bayrakları sticky olarak tutulur ve açık yazılım resetiyle temizlenir.

## 12. Doğrulama ve kabul

### 12.1 Dijital doğrulama

- Bin-merkezli kompleks ton
- Bin dışı ton ve leakage
- DC guard testi
- İki ton ve eşit peak tie-break
- Sabit seed'li pseudo-random kompleks frame
- FFT `TREADY` stall
- Busy iken start reddi, abort ve reset-epoch recovery
- Bilinçli clipping/overflow/küçük-payda negatif testleri
- Python/C bit-true FFT, magnitude-square, peak ve Q1.31 oran karşılaştırması

### 12.2 Kart kabulü

- Golden AD9364 initialization ve RX DMA regresyonu değişmeden geçer.
- Runtime Fs/BW/LO/gain readback kaydedilir; hardcoded metadata kullanılmaz.
- TX güvenliği `TX_SAFE: PASS` olmadan capture başlamaz.
- SMW200A CW bütün dört durumda beklenen frekans penceresinde bulunur.
- Sample drop, FFT overflow ve clipping sıfırdır.
- Peak bin durumlar arasında en fazla ±1 bin değişir.
- Mekanik `+theta` ve `-theta` hata işaretleri ters olur.
- Aynı açıda sonuçların ortalama ve standart sapması raporlanır.

Açı RMSE için yönetici tarafından sayısal sınır verilmemiştir. İlk yankısız oda süpürmesi ölçülmüş tabanı üretir; ürün kabul limiti bu veri ve anten HPBW'siyle yazılı olarak onaylanır.

### 12.3 Python ve IIO doğrulama katmanı

`analogdevicesinc/pyadi-iio` AD936X ailesini desteklediği için Linux/IIOD aşamasında `adi.ad9361(uri=...)` sınıfı üzerinden AD9364 RX yapılandırması ve kompleks örnek yakalama otomasyonu kullanılacaktır. Bu katman NumPy ile ortak peak, CW/bant gücü ve normalize AZ/EL sonuçlarını bağımsız bir referans olarak hesaplar; C ve ilerideki RTL sonuçları aynı test vektörleriyle karşılaştırılır.

Mevcut JTAG/bare-metal Candidate bir IIO context veya IIOD sunmadığından `pyadi-iio` bugün doğrudan karta bağlanma yöntemi değildir. İlk aşamada NumPy oracle ve taklit edilmiş `adi` nesnesiyle test edilir. Gerçek `adi.ad9361(...).rx()` çağrısı PetaLinux/IIOD veya eşdeğer IIO sunucusu ayağa kalktıktan sonra kabul testine eklenir.

SPDT ve phase-shifter modelleri doğrulanmıştır. Kalan donanım kapısı; BDC IF planı, RF1/RF2 kablo eşlemesi, ZX80 beslemesi, HMC936A 5 V level-shifter/buffer şeması, sekiz FPGA kontrol pininin bank gerilimleri ve ölçülmüş settle/discard değerleridir. Bu bilgiler olmadan FPGA pini XDC/RTL'e yazılmaz.

## 13. Uygulama sırası

1. Golden kaynak/artefakt ve aktif FMCOMMS2 Tcl/XDC güvenini yeniden doğrula.
2. AD9364 I0/Q0 formatı, runtime RF metadata ve TX-safe readback'i kapat.
3. Non-blocking 2048-sample capture + AXI replay adapter'ını test-first geliştir.
4. Tek FFT, magnitude-square ve spectrum BRAM'i bit-doğru doğrula.
5. CW peak ve band-power motorunu ekle.
6. BDC IF/koherensini, ZX80/HMC936A sürücü sözleşmesini ve PL pinlerini doğrula.
7. Dört-durum FSM, ortak peak ve scalar PL oran motorunu ekle.
8. SMW200A ile yankısız oda sıfır/açı kalibrasyonunu yap.
9. Golden DMA regresyonu, timing/DRC ve fiziksel kabulden sonra Candidate release üret.

Hiçbir adım mevcut Golden sürümün üzerine yazmaz. Bir kapı başarısızken sonraki fiziksel özellik uygulanmaz.

## 14. Tasarım dışı kapsam

- AD9361/FMCOMMS3'e geçiş
- Gerçek eşzamanlı iki dijital RX
- Tam kompleks Σ/Δ faz açısı
- 90°/270° quadrature phase state
- Sürekli kesintisiz spectrum streaming
- 61.44 MSPS profilinin kanıtsız etkinleştirilmesi
- 8192/65536 gibi gerekçesiz yüksek FFT uzunluğu
- PetaLinux ürünleştirmesi; Candidate donanım kabulünden sonraki ayrı fazdır
