# AXU4EVB-P + AD9364 Staj Sunum Özeti

**Sunum tarihi:** 30 Temmuz 2026

**Proje:** AXU4EVB-P üzerinde AD9364 tabanlı RF alıcı, FPGA FFT ve monopulse
anten takip altyapısı

## 1. Projenin amacı

Amaç, AXU4EVB-P kartına bağlı AD9364 RF transceiver'dan alınan kompleks I/Q
örneklerini güvenilir biçimde FPGA tarafında işlemek; 2048 noktalı spektrum,
taşıyıcı peak'i ve daha sonra harici RF switch/phase-shifter üzerinden
azimuth/elevation hata bilgisi üretmektir.

Nihai analog ölçüm sırası:

```text
S0: Σ + ΔAZ
S1: Σ - ΔAZ
S2: Σ + ΔEL
S3: Σ - ΔEL
```

Tek AD9364 RX kullanıldığı için bu dört durum eşzamanlı değil, kontrollü ve
ardışık finite frame'ler olarak ölçülür.

## 2. Kullanılan donanım

- ALINX AXU4EVB-P
- Xilinx Zynq UltraScale+ MPSoC `xczu4ev-sfvc784-1-i`
- Mevcut AD9364 RF kartı
- JTAG
- PS_UART
- Rohde & Schwarz SMW200A vector signal generator
- Yankısız oda ve anten altyapısı
- Mini-Circuits ZX80-DR230-S+ SPDT RF switch
- Analog Devices EV1HMC936ALP6 / HMC936ALP6E 6-bit phase shifter

Önemli donanım sınırı: HMC936A `1.2-1.4 GHz` aralığında çalışır. Bu nedenle
phase shifter X-band anten sinyalinde doğrudan değil, BDC sonrasındaki uygun IF
yolunda kullanılmalıdır.

## 3. Başlangıçta karşılaşılan temel problemler

### 3.1 Yanlış ve eski proje bilgileri

Eski notlarda ADRV9008/ADRV9009, farklı wrapper/XSA ve yeniden proje oluşturma
önerileri bulunuyordu. Şema, aktif Vivado projesi ve üretilen donanım
çıktıları esas alınarak gerçek hedefin:

```text
Related-Docs/hdl-main/projects/fmcomms2/axu4ev
```

altındaki AXU4EVB-P + AD9364/FMCOMMS tasarımı olduğu doğrulandı.

### 3.2 FMC/LVDS pin ve constraint sorunları

- RX frame ve feedback clock pin eşlemeleri düzeltildi.
- On altı RX LVDS portuna `DIFF_TERM_ADV TERM_100` uygulandı.
- SPI chip-select pull-up eklendi.
- 250 MHz RX clock constraint'i tanımlandı.
- Temiz synthesis/implementation ve DRC kontrolü yapıldı.

Son doğrulanmış temel zamanlama:

| Ölçüm | Sonuç |
|---|---:|
| Setup WNS | `+0.144 ns` |
| Setup TNS | `0.000 ns` |
| DRC error | `0` |

### 3.3 Vitis platform ve FSBL problemleri

- `fmcomms2_axu4ev_hw` platformu güncel XSA ile yeniden üretildi.
- PMU firmware hedefi `psu_pmu_0` ve `mb-gcc` olarak düzeltildi.
- FSBL OCM taşması giderildi.
- Uygulama `psu_cortexa53_0 / standalone_domain` hedefine bağlandı.
- AD9364 seçimi `AD9361_DEVICE=0`, `AD9364_DEVICE=1` olarak doğrulandı.

### 3.4 JTAG başlatma problemi

FSBL bazı koşularda SerDes/PCIe kalibrasyonunda kalıyor; yalnız `psu_init`
çalıştırmak ise PS-PL sınırını hazırlamadığı için AD9364 ürün kimliği `0x00`
okunuyordu.

Kartta doğrulanan sıra:

```text
PMUFW
-> FPGA bitstream
-> Cortex-A53 reset
-> psu_init
-> psu_ps_pl_isolation_removal
-> psu_ps_pl_reset_config
-> DDR A5A5A5A5 testi
-> ad9364app.elf
```

Bu sıra kalıcı Golden/Candidate launcher'lara dönüştürüldü; her açılışta XSCT
komutlarının elle girilmesi kaldırıldı.

## 4. Temel kart kabulü

Kart üzerinde:

- PMUFW çalıştırıldı.
- FPGA programlandı.
- DDR erişimi doğrulandı.
- AD9364 SPI üzerinden Rev 2 olarak tanındı.
- AXI ADC/DDS çekirdekleri başlatıldı.
- İlk 65.536 örnekli DMA aktarımı `Done.` ile tamamlandı.

Örnek UART sonucu:

```text
cf-ad9361-lpc: Successfully initialized
ad9361_init : AD936x Rev 2 successfully initialized
DMA_EXAMPLE: samples=65536 channels=2 bits=16
Done.
```

## 5. 2.4 GHz RF aktivite testi

Telefon hotspot'u kontrollü RF aktivite kaynağı olarak kullanıldı.

- RX-only güvenli çalışma sağlandı.
- 2.4 GHz kanalları baseline ve active olarak tarandı.
- DMA, clipping, power ve burst metrikleri çıkarıldı.
- İki ardışık fiziksel `WIFI_RF_TEST: PASS` alındı.

Bu test Wi-Fi paketlerini çözmez; havadaki RF enerji ve burst aktivitesini
algıladığını kanıtlar.

## 6. Monopulse foundation

AD9364'ün tek gerçek RX zinciri nedeniyle ürün mimarisi eşzamanlı iki kanal
yerine ardışık dört analog durum olarak tasarlandı.

Yazılım referansında tamamlananlar:

- S0-S3 deterministik durum sırası
- ortak peak hesabı
- CW için peak `±2` bin güç toplamı
- modülasyonlu sinyal için configured band-power
- `AZ_NUM/AZ_DEN` ve `EL_NUM/EL_DEN`
- signed Q1.31 normalize hata
- küçük payda ve taşma kontrolü

Kartta iki cold-start koşusunda:

```text
MONOPULSE_RF: PASS fs=30720000 bw=10000000 lo=2400000000 gain=71 tx_att=89750
MONOPULSE_FOUNDATION: PASS
```

sonuçları alındı.

Bu kabul matematik/RF profil foundation kabulüdür; fiziksel ZX80/HMC936 veya
açı kalibrasyonu değildir.

## 7. FPGA FFT mimarisi

Geliştirilen PL yol:

```text
AD9364 I0/Q0
-> geri basınçsız shadow capture
-> 2048-sample store-and-forward RAM
-> AXI4-Stream replay
-> Vivado FFT v9.1
-> magnitude-square ve peak
-> çift atomik spectrum BRAM bankası
-> AXI-Lite control/status
```

FFT sözleşmesi:

| Özellik | Değer |
|---|---|
| FFT size | 2048 |
| Giriş | 16-bit I + 16-bit Q |
| Çıkış sırası | Natural order |
| Scaling | `0x6AB`, toplam `2^-12` |
| Güç | 33-bit magnitude-square |
| Spectrum | 2048 adet 64-bit kelime |
| Bank | 2 adet ping-pong |
| BRAM | 8 RAMB36, 0 LUTRAM |

CDC, backpressure, abort, soft reset, stale epoch, busy rejection, bank
overrun, FFT error, overflow, sticky status, W1C ve IRQ davranışları
self-checking testlerde kapatıldı.

Altı deterministik vektörde bütün 2048 kompleks FFT sonucu ve 2048 güç kelimesi
gerçek Vivado FFT modeliyle sıfır LSB farkla geçti.

## 8. Kart üstü FFT kabulü

Tek-frame Candidate kartta:

```text
PL_FFT: PASS frame=1 bank=0 peak_bin=88
```

sonucunu verdi.

Daha sonra 100 frame, 1000 ms aralıklı periyodik Candidate hazırlandı.
Committed PuTTY kaydı strict parser ile doğrulandı:

```text
PL_FFT_MONITOR: START frames=100 interval_ms=1000 bins=2048
...
PL_FFT_MONITOR: PASS frames=100 interval_ms=1000
```

Bu kabul:

- 100 sıralı frame
- exact 2048 sample
- frame ID
- peak metadata
- spectrum CRC
- JTAG artifact hash bağlama

özelliklerini doğrular.

Kontrollü CW bağlı olmadığı için değişen düşük güçlü peak bin'ler ortam
gürültüsüdür. Bu sonuç transport/control kabulüdür; RF performans veya DOA
kabulü değildir.

## 9. Tekrarlanabilirlik ve yazılım kalitesi

- Golden ve Candidate launcher'lar ayrıldı.
- Candidate manifestleri SHA-256 hash taşır.
- Kart kanıtı olmadan `board_verified=true` engellendi.
- Çalışma farklı klasöre taşındığında path bağımsızlığı doğrulandı.
- Ham PuTTY ve JTAG logları Candidate artifactlerine bağlandı.
- Tek-frame ve periodic paketler birbirinden izole tutuldu.
- Geliştirmeler bağımsız worktree ve `codex/` branch'lerinde yapıldı.
- Fiziksel kabulden sonra GitHub pull request main'e birleştirildi.

## 10. Yeni bare-metal Python laboratuvar ekranı

Stajın kalan süresinde PetaLinux yükü eklemeden gerçek FFT spectrumunu görme
kararı alındı.

Yeni mimari:

```text
PL FFT spectrum BRAM
-> A53 bare-metal UART service
-> CRC'li binary 2048-bin paket
-> PySerial
-> NumPy
-> Matplotlib spectrum + waterfall
```

Ekranda:

- canlı FFT
- son 32 frame waterfall
- peak bin ve gerçek RF frekansı
- relative peak power
- LO, sample-rate ve bandwidth
- frame ID, RF state, CRC
- frame/FFT/overflow/CDC/bank sağlık bilgileri

gösterilecek.

Tam frame NPZ, özet CSV olarak kaydedilecek. 115200 baud'da beklenen yenileme
yaklaşık 1,5-2 saniyedir. Ethernet geleceğe açık bırakılmış fakat mevcut
teslime eklenmemiştir.

Tasarım:

`PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-monopulse-lab-design.md`

Uygulama planı:

`PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-lab-implementation-plan.md`

## 11. Kalan işler

### Yazılım/FFT grafik

1. Python ve C byte-exact UART codec.
2. Bare-metal GET_INFO/CAPTURE_ONCE servisi.
3. PySerial/NumPy/Matplotlib ekranı.
4. `monopulse-live-lab-v1` Candidate paketi.
5. SMW200A kontrollü CW ile en az 10 stabil frame kabulü.

### ZX80/HMC936

1. BDC IF'nin `1.2-1.4 GHz` içinde doğrulanması.
2. ΔAZ/ΔEL ile ZX80 RF1/RF2 kablo eşlemesi.
3. ZX80 VDD ve kontrol gerilimleri.
4. HMC936 için 5 V level-shifter/buffer ve güvenli OE.
5. Altı faz biti + iki switch kontrolü için sekiz FPGA pini/XDC.
6. Gerçek settle/discard ölçümü.
7. S0-S3 state-tag ve dört spectrum çevrimi.

### Kalibrasyon

1. HMC936 phase-code karakterizasyonu.
2. PLUS/MINUS kodlarının ölçülmesi.
3. Mekanik sıfır.
4. `-theta/0/+theta` AZ ve EL süpürmesi.
5. Bias, eğim, simetri ve tekrar edilebilirlik.
6. Açı kabul sınırı/RMSE.

## 12. Sunumda vurgulanacak mühendislik kazanımları

- Şema, kaynak kodu ve kart kanıtını eski dokümanlardan daha yüksek öncelikle
  kullanma
- Vivado timing/DRC ve Vitis artifact bütünlüğü
- PMUFW/PS/DDR/PS-PL başlatma sırasını teşhis etme
- Donanımı tekrar açınca çalışan otomatik JTAG launcher
- AD9364 RX güvenliği ve gerçek RF aktivite testi
- Fixed-point FFT ve bit-doğru referans model
- CDC, backpressure, reset recovery ve atomik buffer ownership
- Fiziksel kart kanıtını hash/manifest/log ile yeniden üretilebilir hale getirme
- Tek-RX donanım kısıtına uygun dört durumlu monopulse mimarisi
- Büyük sistemi bağımsız ve ölçülebilir Candidate teslimlerine ayırma

## 13. Kısa sonuç cümlesi

AXU4EVB-P + AD9364 platformu yalnızca bitstream üreten bir tasarımdan;
tekrarlanabilir JTAG başlatması, RF aktivite algılama, bit-doğru 2048 noktalı
FPGA FFT, tam spectrum belleği, 100-frame fiziksel monitor kabulü ve harici
ZX80/HMC936 monopulse entegrasyonuna hazır modüler bir ölçüm platformuna
dönüştürülmüştür.
