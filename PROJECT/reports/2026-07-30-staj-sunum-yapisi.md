# AXU4EVB-P + AD9364 Staj Sunumu Yapısı

**Sunum tarihi:** 30 Temmuz 2026  
**Toplam oturum:** Yaklaşık 30 dakika  
**Ana anlatım:** 22–24 dakika  
**Soru-cevap:** 6–8 dakika  
**Yapı:** 24 ana slayt + gerektiğinde açılacak 5 yedek teknik slayt  
**Hedef kitle:** FPGA konusunda deneyimli mühendis ve gömülü sistem ekip lideri

## Sunumun ana amacı

Bu sunum bir faaliyet günlüğü değildir. Anlatımın temel düzeni her teknik
bölümde aşağıdaki gibi olmalıdır:

```text
Problem
-> doğrulanan teknik bilgi
-> alınan mühendislik kararı
-> yapılan uygulama
-> ölçülebilir sonuç veya açık kabul kapısı
```

Sunum sonunda dinleyici şu dört sonucu net biçimde görmelidir:

1. AXU4EVB-P ve AD9364 için tekrar üretilebilir bir Vivado/Vitis/JTAG altyapısı
   oluşturuldu.
2. AD9364 üzerinden alınan kompleks örnekler FPGA içinde gerçek 2048 noktalı
   FFT işleminden geçirilip tam spektrum olarak erişilebilir hale getirildi.
3. Bare-metal UART servisi ve Python laboratuvar uygulaması gerçek kartla
   çalıştırıldı; protokol, CRC, spektrum ve kayıt katmanları doğrulandı.
4. Kontrollü CW kabulü ile ZX80/HMC936 tabanlı fiziksel monopulse kalibrasyonu
   tamamlanmış işlerden açıkça ayrıldı.

## Sunum tasarım ilkeleri

- Slaytta uzun paragraf kullanılmamalı; ayrıntı konuşma notunda kalmalıdır.
- Her teknik iddia mümkünse şema, blok diyagram, terminal çıktısı, test sonucu
  veya ölçüm tablosuyla desteklenmelidir.
- Yeşil etiket **tamamlandı**, sarı etiket **fiziksel kabul açık**, mavi etiket
  **gelecek geliştirme** anlamına gelmelidir.
- Aynı terminal çıktısı birden fazla slaytta tekrar kullanılmamalıdır.
- Kod ekranı yerine veri akışı, register sözleşmesi veya kısa pseudocode
  gösterilmelidir.
- Sunum boyunca “çalışıyor” ifadesi yerine hangi katmanın hangi kanıtla
  doğrulandığı söylenmelidir.

---

# Ana sunum

## Bölüm 1 — Problem, hedef ve sistem sınırı

### Slayt 1 — Kapak

**Süre:** 20–30 saniye

**Amaç:** Projenin donanım, FPGA işleme ve laboratuvar yazılımını kapsayan
uçtan uca niteliğini tek cümlede göstermek.

**Slaytta bulunacaklar:**

- `AXU4EVB-P + AD9364 Gerçek Zamanlı FPGA FFT ve Monopulse Altyapısı`
- İsim, okul/bölüm, kurum ve staj dönemi
- AXU4EVB-P ile AD9364 kartının net bir fotoğrafı

**Kısa kanıt:**

> Staj boyunca AXU4EVB-P ve AD9364 platformu; doğrulanmış kart başlatmasından
> gerçek zamanlı FPGA FFT üretimine ve Python laboratuvar görünümüne uzanan,
> monopulse entegrasyonuna açık bir ölçüm altyapısına dönüştürüldü.

**Görsel:** Kart ve RF modülünün tek, temiz fotoğrafı.

---

### Slayt 2 — Başlangıç problemi ve proje hedefi

**Süre:** 50–60 saniye

**Amaç:** Neden yalnız hazır ADI projesini derlemenin yeterli olmadığını
açıklamak.

**Slaytta bulunacaklar:**

- Mevcut ADI projesinin AXU4EVB-P uyumluluğu ve pinleri kesin değildi.
- Vivado bitstream üretimi fiziksel kart kabulü anlamına gelmiyordu.
- Vitis platformu, PMUFW, PS/DDR ve PS–PL başlatma sırası tekrarlanabilir değildi.
- Nihai ister; RF alımı, 2048 noktalı FFT, peak tespiti, tam spektrum aktarımı ve
  gelecekte zaman bölüşümlü monopulse ölçümüydü.

**Ana konuşma mesajı:**

> İlk problem bir FFT yazmak değil, güvenilir ve ölçülebilir bir donanım-yazılım
> zinciri kurmaktı.

**Görsel:** Solda başlangıç problemleri, sağda hedef veri yolu.

**Olası soru:** “ADI referans tasarımı neden doğrudan kullanılamadı?”

**Kısa cevap:** Kart pinleri, clock/constraint yapısı, Vitis handoff’u ve fiziksel
başlatma zinciri hedef platformda ayrıca teyit edilmek zorundaydı.

---

### Slayt 3 — Sonuçların tek bakışta özeti

**Süre:** 50–60 saniye

**Amaç:** Sunumun devamında kanıtlanacak sonuçları baştan vermek.

**Slaytta bulunacaklar:**

| Katman | Güncel durum | Temel kanıt |
|---|---|---|
| Vivado ve kart constraint’leri | Tamamlandı | Bitstream, `WNS +0.144 ns`, DRC `0` |
| Vitis/JTAG başlatma | Tamamlandı | PMUFW, DDR kapısı ve Golden/Candidate launcher |
| AD9364 ve DMA bring-up | Tamamlandı | Rev 2 init ve 65.536 örnek DMA `Done` |
| RF aktivite algılama | Tamamlandı | İki 2.4 GHz Wi-Fi karşılaştırma koşusu |
| 2048 noktalı PL FFT | Tamamlandı | Bit-doğru model, tek-frame ve 100-frame kart testi |
| Bare-metal + Python | Kartta preflight tamamlandı | Protocol v2, CRC, 2048 bin ve 61 Python testi |
| Kontrollü CW | Fiziksel kabul açık | SMW200A ile bin 20/bin 100 testi bekleniyor |
| ZX80/HMC936 monopulse | Gelecek entegrasyon | Kontrol, settling ve açı kalibrasyonu açık |

**Ana konuşma mesajı:**

> Projenin çalışan kısmı ile henüz fiziksel kabul bekleyen kısmı baştan
> ayrılmıştır.

**Görsel:** Yeşil/sarı/mavi durum tablosu.

---

### Slayt 4 — Donanım sistemi ve fiziksel veri yolu

**Süre:** 60–75 saniye

**Amaç:** Donanımın hangi parçalardan oluştuğunu ve verinin nereden nereye
aktığını göstermek.

**Slaytta bulunacaklar:**

```text
RF kaynak / anten
-> AD9364 RXA
-> kompleks I/Q örnekleri
-> FMC / LVDS
-> Zynq UltraScale+ PL
-> 2048-point FFT ve spectrum BRAM
-> Cortex-A53 bare-metal servis
-> PS_UART
-> Python spectrum / waterfall / NPZ / CSV
```

- FPGA kartı: ALINX AXU4EVB-P, `xczu4ev-sfvc784-1-i`
- RF kartı: mevcut AD9364
- Geliştirme bağlantıları: JTAG ve PS_UART
- Kontrollü RF kaynağı: Rohde & Schwarz SMW200A

**Ana konuşma mesajı:**

> JTAG sistemi başlatır; PS_UART ise çalışma zamanında FFT spektrumu ve sağlık
> bilgisini bilgisayara taşır.

**Görsel:** Fotoğraflar üzerine etiketlenmiş bağlantı diyagramı.

**Olası soru:** “Ethernet veya PetaLinux neden kullanılmadı?”

**Kısa cevap:** Mevcut hedef için bare-metal + UART yeterli, daha az bağımlı ve
daha kolay doğrulanabilir bir yol sundu. Ethernet geliştirmeye açık bırakıldı.

---

### Slayt 5 — AD9364 kısıtı ve mimari karar

**Süre:** 60–75 saniye

**Amaç:** AD9364’ün 1×1 yapısının iki eşzamanlı RX yerine neden zaman bölüşümlü
monopulse gerektirdiğini açıklamak.

**Slaytta bulunacaklar:**

- AD9364 tek gerçek RX zincirine sahip 1×1 RF transceiver’dır.
- RXA/RXB/RXC seçilebilir fakat iki bağımsız RX aynı anda örneklenemez.
- İki antenin eşzamanlı dijital faz farkını AD9364 içinde ölçme iddiası
  yapılmamıştır.
- Harici analog ağ, `Σ ± ΔAZ` ve `Σ ± ΔEL` durumlarını ardışık olarak üretir.
- Tek ortak FFT donanımı dört finite-frame üzerinde tekrar kullanılır.

**Durum denklemleri:**

```text
S0 = Σ + ΔAZ
S1 = Σ - ΔAZ
S2 = Σ + ΔEL
S3 = Σ - ΔEL
```

**Ana konuşma mesajı:**

> Donanım kısıtı saklanmadı; mimari bu kısıta uygun olarak dört ardışık RF
> durumuna dönüştürüldü.

**Görsel:** `S0–S3 -> RXA -> tek FFT` blok diyagramı.

**Olası soru:** “Neden AD9361 veya iki kanallı başka bir cihaz kullanılmadı?”

**Kısa cevap:** Projenin bağlayıcı hedef donanımı mevcut AD9364’tür; çözüm bu
donanım üzerinde uygulanabilir olacak şekilde tasarlandı.

---

### Slayt 6 — Gereksinimler ve kabul kapıları

**Süre:** 50–60 saniye

**Amaç:** Projenin tek seferde değil, bağımsız doğrulanabilir teslimlere
bölündüğünü göstermek.

**Slaytta bulunacaklar:**

1. Kart, PS/PL, DDR ve AD9364 bring-up
2. Gerçek RF aktivitesinin DMA üzerinden görülmesi
3. Monopulse matematik ve fixed-point referans modeli
4. 2048 noktalı PL FFT, magnitude-square ve peak
5. Tek-frame ve 100-frame kart kabulü
6. CRC’li tam spektrum protokolü ve Python görünümü
7. Kontrollü CW peak-bin kabulü
8. ZX80/HMC936 kontrolü, S0–S3 ve açı kalibrasyonu

**Ana konuşma mesajı:**

> Her sonraki aşama, bir önceki aşamanın ölçülebilir kanıtını giriş koşulu olarak
> kullandı.

**Görsel:** Sekiz kapılı yatay ilerleme diyagramı; tamamlanan ve açık kapılar
renklendirilmeli.

---

### Slayt 7 — Geliştirme ve tekrar üretilebilirlik yöntemi

**Süre:** 50–60 saniye

**Amaç:** Teknik sonucun yanında güvenilir geliştirme sürecini göstermek.

**Slaytta bulunacaklar:**

- Golden: kartta doğrulanmış geri dönüş noktası
- Candidate: yeni bitstream/ELF’in ayrı ve değişmez paketi
- Kaynak, XSA, bitstream ve ELF için SHA-256 manifestleri
- Otomatik JTAG launcher ve DDR yaz/oku kapısı
- C/Python referans testleri, RTL testleri ve fiziksel UART/JTAG kanıtları
- Ayrı Git worktree ve kontrollü branch akışı

**Ana konuşma mesajı:**

> “Benim bilgisayarımda çalışıyor” yerine, aynı artifact’in yeniden seçilip
> doğrulanabildiği bir teslim zinciri oluşturuldu.

**Görsel:** `source -> build -> Candidate -> hash gate -> JTAG -> UART evidence`
akışı.

**Olası soru:** “Golden ile Candidate arasındaki fark nedir?”

**Kısa cevap:** Golden fiziksel olarak doğrulanmış geri dönüş paketidir;
Candidate yeni değişiklikleri test eder ve Golden’ı değiştirmez.

---

## Bölüm 2 — Vivado ve donanım tasarımı

### Slayt 8 — Başlangıç Vivado mimarisi

**Süre:** 50–60 saniye

**Amaç:** Yeni FFT yolunun hangi ADI altyapısına eklendiğini göstermek.

**Slaytta bulunacaklar:**

- Zynq UltraScale+ Processing System
- AD9364 LVDS interface ve ADC/DAC veri yolları
- AXI ADC/DDS ve DMA altyapısı
- A53 bare-metal kontrol alanı
- FFT’nin ADC akışını durdurmayan paralel tap olarak konumu

**Ana konuşma mesajı:**

> Referans tasarım tamamen atılmadı; doğrulanan ADI veri yolu korunup FFT ayrı ve
> geri basınç üretmeyen bir gözlem bloğu olarak eklendi.

**Görsel:** Block design’in sadeleştirilmiş, renkli bir görünümü.

---

### Slayt 9 — Şema teyidi, pinler ve XDC düzeltmeleri

**Süre:** 70–80 saniye

**Amaç:** Kart bring-up öncesinde fiziksel kart ile proje arasındaki kritik
uyumsuzlukların nasıl kapatıldığını açıklamak.

**Slaytta bulunacaklar:**

- AXU4EVB-P ve AD9364 şemaları aktif kaynaklarla karşılaştırıldı.
- RX frame ve feedback clock eşlemeleri doğrulandı.
- On altı RX LVDS portunda uygun `DIFF_TERM_ADV TERM_100` ayarı kullanıldı.
- SPI chip-select pull-up ve I/O standardları kontrol edildi.
- RX clock constraint ve top-level port sözleşmesi tek kaynağa bağlandı.

**Ana konuşma mesajı:**

> Markdown notları doğrudan doğru kabul edilmedi; şema, aktif HDL ve fiziksel
> kart öncelik sırasıyla teyit edildi.

**Görsel:** Şemadaki ilgili net, XDC satırı ve top-level port arasında üçlü
eşleme örneği.

**Olası soru:** “Harici input/output delay neden eklenmedi?”

**Kısa cevap:** Ölçülmüş veya güvenilir veri sayfası değeri olmadan yapay delay
eklenmedi; bu sınır timing raporunda açıkça korundu.

---

### Slayt 10 — Synthesis, timing, DRC ve donanım devri

**Süre:** 45–55 saniye

**Amaç:** Vivado sonucunun yalnız bitstream üretimi olmadığını göstermek.

**Slaytta bulunacaklar:**

| Kontrol | Sonuç |
|---|---:|
| FPGA | `xczu4ev-sfvc784-1-i` |
| Setup WNS | `+0.144 ns` |
| Setup TNS | `0.000 ns` |
| DRC error | `0` |
| Çıktı | Bitstream ve aynı implementasyondan XSA |

- Güncel bitstream XSA içine alınarak Vitis donanım devri yenilendi.
- Eski wrapper/XSA seçme riski artifact kapılarıyla azaltıldı.

**Ana konuşma mesajı:**

> Tasarım implementasyon, timing ve DRC kapılarından geçtikten sonra Vitis’e
> devredildi.

**Görsel:** Timing summary’nin kırpılmış ekran görüntüsü ve küçük sonuç tablosu.

---

## Bölüm 3 — Vitis, JTAG ve kart bring-up

### Slayt 11 — Vitis ve bare-metal yazılım katmanları

**Süre:** 50–60 saniye

**Amaç:** FPGA bitstream’inden çalışan AD9364 uygulamasına kadar olan yazılım
katmanlarını açıklamak.

**Slaytta bulunacaklar:**

```text
XSA / hardware platform
-> psu_cortexa53_0 standalone domain
-> PMU firmware
-> FSBL / PS initialization
-> no-OS AD9364 driver
-> ad9364app
-> PL FFT service ve UART protocol v2
```

- Vitis 2020.1
- Cortex-A53 bare-metal uygulaması
- ADI no-OS sürücüleri

**Ana konuşma mesajı:**

> Vitis yalnız uygulamayı derlemedi; PMU, PS/DDR, sürücü ve PL register erişimi
> aynı donanım tanımıyla bağlandı.

**Görsel:** Vitis platform/application katman diyagramı.

---

### Slayt 12 — Bring-up sırasında görülen hatalar

**Süre:** 60–70 saniye

**Amaç:** Hataları listelemek yerine belirtilerin hangi sistem katmanını işaret
ettiğini göstermek.

**Slaytta bulunacaklar:**

| Belirti | İşaret ettiği katman |
|---|---|
| Platform `Out-of-date` | XSA/platform bağımlılığı |
| PMUFW header index hataları | Vitis index/BSP görünümü |
| `PMU-FW is not running` | Güç yönetimi başlatma sırası |
| Instruction transfer timeout | A53/PS erişimi ve reset durumu |
| DDR `Memory write error` | PS/DDR init eksikliği |
| AD9364 `PRODUCT_ID 0x00` | SPI/peripheral erişimi hazır değil |

**Ana konuşma mesajı:**

> Aynı anda görülen hataların bağımsız olmadığı, eksik sistem başlatma zincirinin
> farklı belirtileri olduğu anlaşıldı.

**Görsel:** Hata mesajlarını katmanlara bağlayan sade teşhis ağacı.

---

### Slayt 13 — Kök neden analizi

**Süre:** 50–60 saniye

**Amaç:** Deneme-yanılma yerine bulunan gerçek sistem problemini açıklamak.

**Slaytta bulunacaklar:**

- PMU, PL, Cortex-A53, PS/DDR ve PS–PL sınırı doğru sırada hazırlanmıyordu.
- Yalnız FPGA programlamak veya yalnız uygulama ELF’i indirmek yeterli değildi.
- Bazı FSBL koşullarında SerDes/PCIe kalibrasyonu başlangıcı geciktiriyordu.
- PS–PL isolation ve reset adımları tamamlanmadan peripheral erişimi güvenilir
  değildi.

**Ana konuşma mesajı:**

> Kök neden uygulama kodundan önceki sistem durumuydu; bu nedenle çözüm debug
> ayarı değil, deterministik başlatma sırası oldu.

**Görsel:** Hatalı ve doğru başlangıç sırasının yan yana karşılaştırması.

**Olası soru:** “FSBL neden tek başına kullanılmadı?”

**Kısa cevap:** Hedef kartta ihtiyaç duyulan deterministik PS/DDR/PS–PL akışı
doğrudan `psu_init` ve ilgili isolation/reset adımlarıyla güvenilir biçimde
kuruldu; FSBL artifact’i yine paket içinde korunmaktadır.

---

### Slayt 14 — Doğrulanan JTAG başlatma sırası

**Süre:** 50–60 saniye

**Amaç:** Kartı güvenilir biçimde çalıştıran sıralı sözleşmeyi göstermek.

**Slaytta bulunacaklar:**

```text
1. PMU güvenlik kapılarını aç
2. PMUFW yükle ve çalıştır
3. FPGA bitstream programla
4. Cortex-A53 #0 reset
5. psu_init
6. psu_ps_pl_isolation_removal
7. psu_ps_pl_reset_config
8. DDR: 0x00100000 <- A5A5A5A5 ve readback
9. ad9364app.elf yükle ve çalıştır
```

**Ana konuşma mesajı:**

> Uygulama indirilmeden önce DDR erişimi ölçülür; başarısız bir başlangıç,
> uygulamaya geçmeden durdurulur.

**Görsel:** Dokuz adımlı dikey sequence diagram.

---

### Slayt 15 — Golden/Candidate otomatik başlatıcı

**Süre:** 40–50 saniye

**Amaç:** Elle girilen XSCT komutlarının neden kalıcı araca dönüştürüldüğünü
göstermek.

**Slaytta bulunacaklar:**

- Tek komut veya çift tıklanabilir `.cmd`
- Xilinx 2020.1 ve artifact yollarını otomatik bulma
- Bitstream/ELF/PMUFW bütünlük kontrolü
- DDR kapısı ve açık hata mesajları
- Tarihli JTAG logu
- Candidate başarısızlığında Golden geri dönüşü

**Ana konuşma mesajı:**

> Aynı kart başlatma sırasını her gün elle tekrar etmek yerine proje içinde
> sürümlü ve doğrulanabilir hale getirdim.

**Görsel:** Launcher PASS çıktısının yalnız önemli 8–10 satırı.

---

### Slayt 16 — Temel kart ve AD9364 kabulü

**Süre:** 50–60 saniye

**Amaç:** Hangi donanım katmanlarının gerçek kartta doğrulandığını göstermek.

**Slaytta bulunacaklar:**

```text
cf-ad9361-lpc: Successfully initialized
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized
DMA_EXAMPLE: samples=65536 channels=2 bits=16
Done.
```

- PMUFW, PL, PS/DDR ve PS–PL yolu
- SPI üzerinden AD9364 Rev 2 okuması
- AXI ADC/DDS çekirdekleri
- DDR üzerinde DMA aktarımı

**Ana konuşma mesajı:**

> Bu test RF doğruluğunu tek başına kanıtlamaz; fakat FPGA, DDR, SPI, AD9364 ve
> DMA zincirinin birlikte çalıştığını kanıtlar.

**Görsel:** PuTTY çıktısı ve yanında doğrulanan katmanların küçük şeması.

---

## Bölüm 4 — RF, FPGA FFT ve Python laboratuvar sistemi

### Slayt 17 — Gerçek RF aktivite testi

**Süre:** 55–65 saniye

**Amaç:** DMA’nın yalnız tamamlanmadığını, gerçek RF değişimine tepki verdiğini
göstermek.

**Slaytta bulunacaklar:**

- İlk test özel olarak RXB üzerinde, tek antenle ve RX-only yapıldı.
- 2.4 GHz kanalları hotspot kapalıyken baseline olarak tarandı.
- Hotspot ve trafik açıldıktan sonra active scan tekrarlandı.
- Kanal 6 için güç ve burst aktivitesinde ölçülebilir artış görüldü.
- İki ardışık çalışma `WIFI_RF_TEST: PASS` ile tamamlandı.

**Sınır:** Wi-Fi paketleri veya kullanıcı verisi çözülmedi; yalnız RF enerji ve
burst aktivitesi algılandı.

**Ana konuşma mesajı:**

> Bu aşama kontrollü FFT peak testi değil, analog RF girişinden DMA metriklerine
> kadar gerçek sinyal duyarlılığı testidir.

**Görsel:** Baseline/active kanal 6 satırlarının yan yana karşılaştırması.

**Olası soru:** “Neden güncel CW testi RXA iken Wi-Fi testi RXB?”

**Kısa cevap:** Wi-Fi Candidate’ı teste özgü RXB konfigürasyonuydu; güncel
`monopulse-live-lab-v2` kabul sözleşmesi RXA/channel 0 kullanır.

---

### Slayt 18 — FPGA'da FFT: sinyalden spektruma

**Süre:** 40–50 saniye

**Slaytta bulunacaklar:**

- AD9364'ten kompleks I/Q örnekleri alınır.
- FPGA içinde 2048 noktalı FFT uygulanır.
- Tam spektrum korunur ve maksimum peak noktası bulunur.
- 30,72 MSPS örnekleme hızında çözünürlük 15 kHz/bin'dir.

**Görsel akış:**

```text
AD9364 I/Q -> 2048 noktalı PL FFT -> Spektrum -> Peak
```

**Ana konuşma mesajı:**

> FFT, A53 yerine deterministik PL yolunda çalışır. Tam spektrum debug ve Python
> görünümü için korunur.

---

### Slayt 19 — FFT nasıl doğrulandı?

**Süre:** 55–65 saniye

**Slaytta bulunacaklar:**

- FPGA sonucu bağımsız Python/NumPy modeliyle karşılaştırıldı.
- Deterministik testlerde bit-doğru sonuç elde edildi.
- Kartta tek-frame `PL_FFT: PASS` sonucu alındı.
- 100 ardışık frame boyunca aktarım ve sağlık kontrolleri geçti.

**Kısa kanıt:**

```text
PL_FFT: PASS frame=1 bank=0 peak_bin=88
PL_FFT_MONITOR: PASS frames=100 interval_ms=1000
```

Kontrollü RF uyarımı bulunmadığı için peak kararlılığı bu testin kabul ölçütü değildir.

---

### Slayt 20 — Bare-metal veriden Python FFT ekranına

**Süre:** 60–70 saniye

**Slaytta bulunacaklar:**

- Bare-metal uygulama FFT sonucunu PS_UART üzerinden bilgisayara taşır.
- Python uygulaması spektrum ve waterfall grafiğini oluşturur.
- CRC ve frame kontrolleri veri bütünlüğünü doğrular.
- 61/61 yazılım testi ve gerçek karttan 10-frame preflight geçti.

**Görsel:** `PROJECT/reports/assets/screenshots/2026-07-28-live-fft-no-rf-board.png`

Harici RF uygulanmadığı için boş spektrum iletişim hatası değildir; bu, sinyalsiz preflight'tır.

---

### Slayt 21 — Kontrollü CW, monopulse yol haritası ve sonuç

**Süre:** 80–90 saniye

**Amaç:** Tamamlanan işi, sıradaki fiziksel kabulü ve nihai ürün yolunu tek ve
net kapanış slaydında ayırmak.

**Slaytta bulunacaklar:**

#### Tamamlanan

- AXU4EVB-P/AD9364 Vivado ve Vitis zinciri
- PMUFW/PS/DDR/PS–PL içeren otomatik JTAG launcher
- AD9364, DMA ve gerçek RF aktivitesi
- Bit-doğru 2048 noktalı PL FFT
- Tek-frame ve 100-frame kart kabulü
- CRC’li bare-metal/Python laboratuvar yolu

#### Sıradaki fiziksel kabul

- SMW200A ile RXA’ya düşük seviyeli, DC dışı CW
- `2.400300 GHz -> bin 20`
- `2.401500 GHz -> bin 100`
- 100 frame boyunca CRC/health/gain sabit ve peak `±1 bin`
- Bu kanıt alınana kadar `board_verified=false`

#### Gelecek monopulse entegrasyonu

- ZX80 RF1/RF2 ve HMC936 kontrol eşlemesi
- HMC936 için güvenli 5 V aktif-düşük level-shifter/OE
- S0–S3 finite-frame durumu ve settling/discard
- Ortak peak/band-power ile normalize AZ/EL
- `-θ / 0 / +θ` yankısız oda kalibrasyonu

**Kapanış cümlesi:**

> Staj sonunda yalnız çalışan bir bitstream değil; kart başlatması, RF alımı,
> bit-doğru FPGA FFT’si, tam spektrum aktarımı ve fiziksel monopulse
> entegrasyonuna genişleyebilen tekrar üretilebilir bir ölçüm altyapısı ortaya
> çıkarıldı.

**Görsel:** Üç sütunlu `tamamlandı / kabul açık / gelecek` tablosu ve en altta
“Sorular” alanı.

---

# Yedek slaytlar

Bu slaytlar ana akışta anlatılmamalı; soru gelirse açılmalıdır.

## Yedek 1 — Ayrıntılı pin ve XDC sözleşmesi

**Kullanım amacı:** FPGA pinleri, LVDS termination veya clock constraint
hakkında soru gelirse.

**İçerik:**

- FMC/AD9364 kritik RX netlerinin pin tablosu
- I/O standard ve termination özeti
- RX frame ve feedback clock eşlemeleri
- SPI chip-select pull-up
- Harici input/output delay’in neden açık sınır olduğu

---

## Yedek 2 — Timing, DRC ve artifact bütünlüğü

**Kullanım amacı:** Tasarım kapanışı veya yeniden üretilebilirlik sorulursa.

**İçerik:**

- Setup WNS/TNS
- DRC error sayısı
- Kullanılan FPGA part ve top-level
- Bitstream/XSA/ELF/PMUFW SHA-256 örnekleri
- Candidate manifest doğrulama sırası

---

## Yedek 3 — FFT sayısal sözleşmesi

**Kullanım amacı:** Fixed-point, ölçekleme veya peak hesabı sorulursa.

**İçerik:**

- Q1.15 giriş ve doğal sıralı FFT çıkışı
- Scaling schedule `0x6AB`
- 33-bit magnitude-square
- DC guard ve eşit peak tie-break kuralı
- CRC’de serialize edilen I/Q kelime sırası
- Altı doğrulama vektörü

---

## Yedek 4 — UART protocol v2 paket yapısı

**Kullanım amacı:** Gömülü sistem, veri bütünlüğü veya hata toparlama sorulursa.

**İçerik:**

- Header, version, type, sequence ve payload length
- INFO, SPECTRUM ve ERROR mesajları
- CRC-32/ISO-HDLC
- 2048-bin payload boyutu
- Timeout, retry ve resynchronization
- Release ID, LO/Fs/BW/gain/flags metadata

---

## Yedek 5 — ZX80/HMC936 elektriksel entegrasyon

**Kullanım amacı:** Monopulse donanımı veya FPGA kontrol pinleri sorulursa.

**İçerik:**

- ZX80-DR230-S+: DC–3 GHz SPDT
- EV1HMC936ALP6: 1.2–1.4 GHz, altı kontrol biti
- HMC936 kontrolü: 5 V ve aktif-düşük
- FPGA’ya doğrudan bağlantının reddedilme nedeni
- Level-shifter, output-enable ve güvenli açılış durumu
- İki ZX80 + altı HMC kontrolü için sekiz güvenli çıkış
- Ölçülmesi gereken switching/settling ve discard süreleri

---

# Süre yönetimi

| Bölüm | Slaytlar | Hedef süre |
|---|---:|---:|
| Problem, hedef ve sistem sınırı | 1–7 | 6–7 dakika |
| Vivado ve donanım tasarımı | 8–10 | 3 dakika |
| Vitis, JTAG ve bring-up | 11–16 | 6 dakika |
| RF, FFT ve Python | 17–23 | 7–8 dakika |
| Sonuç ve yol haritası | 24 | 1–1,5 dakika |
| Toplam ana anlatım | 24 slayt | 22–24 dakika |
| Soru-cevap | Yedek 1–5 | 6–8 dakika |

## Süre aşılırsa atlanabilecek ayrıntılar

- Slayt 7’de Git worktree ayrıntısı yalnız tek cümleyle geçilir.
- Slayt 12’de tüm hata satırları okunmaz; üç temsilî belirti anlatılır.
- Slayt 17’de yalnız kanal 6 baseline/active farkı gösterilir.
- Slayt 20’de scaling schedule açıklanmaz; yedek slayta bırakılır.
- Slayt 23’te test isimleri okunmaz; yalnız 61/61 ve kart metadata’sı açıklanır.

# Sunum öncesi hazırlanacak görsel ve kanıt listesi

## Hazır olanlar

- AXU4EVB-P ve AD9364 fotoğrafları
- SMW200A ve yankısız oda fotoğrafları
- Golden/Candidate JTAG launcher PASS logları
- AD9364 Rev 2 ve DMA UART kabulü
- Wi-Fi baseline/active RF aktivite kanıtı
- `PL_FFT: PASS` ve 100-frame monitor kaydı
- Python 61 test ekran görüntüsü
- Sinyalsiz gerçek kart FFT/waterfall ekran görüntüsü
- ZX80 ve EV1HMC936ALP6 fotoğrafı

## Sunumdan önce alınması hedeflenen

- Vivado block design’in okunabilir kırpılmış görüntüsü
- Timing summary ve DRC ekran görüntüsü
- FFT mimarisinin temiz vektörel blok diyagramı
- Kontrollü SMW200A CW uygulanabilirse bin 20 veya bin 100 ekran görüntüsü
- CW koşusuna ait NPZ/CSV özet grafiği

## Sunumda kullanılmaması gerekenler

- Başka ADI kartına ait eski ekran görüntülerinin mevcut AD9364 sonucu gibi
  gösterilmesi
- Kontrollü RF uyarımı olmadan alınmış peak bin’in frekans doğruluğu kanıtı
  olarak sunulması
- Wi-Fi RF aktivite testinin paket çözme testi gibi anlatılması
- `board_verified=false` Candidate’ın nihai RF kabulü almış gibi gösterilmesi
- Kalibre edilmemiş FFT gücünün dBm olarak etiketlenmesi

# Beklenen teknik sorular için kısa cevaplar

## “2048 FFT neden seçildi?”

30.72 MSPS örnekleme hızında 15 kHz/bin çözünürlük sağlar; kaynak kullanımı,
frame süresi ve debug edilebilirlik arasında uygun bir dengedir.

## “Peak neden sinyal yokken değişiyor?”

Kontrollü tone yokken belirgin bir RF maksimumu bulunmaz. Gürültü, leakage ve
eşit güç tie-break davranışı peak seçimini etkiler. Frekans doğruluğu kontrollü
CW ile sınanmalıdır.

## “AD9364 ile iki anten aynı anda okunuyor mu?”

Hayır. AD9364 1×1’dir. Nihai mimari harici analog ağın ürettiği dört S0–S3
durumunu ardışık finite-frame olarak aynı RXA ve tek FFT üzerinden işler.

## “FFT neden A53 üzerinde yapılmadı?”

PL FFT deterministik, sürekli ve gelecekte S0–S3 durumlarıyla ölçeklenebilir bir
işleme yolu sağlar. A53 kontrol, protokol, metadata ve laboratuvar servisini
yürütür.

## “Python uygulaması kartı hangi yolla okuyor?”

Mevcut sürüm PS_UART üzerinden CRC korumalı protocol v2 kullanır. PetaLinux/
IIOD bulunmadığı için gerçek kart yolu `pyadi-iio` değildir.

## “Monopulse ürünü tamamlandı mı?”

Matematik foundation, FFT ve laboratuvar altyapısı tamamlandı. ZX80/HMC936
elektriksel kontrolü, S0–S3 fiziksel yakalama, settling ve açı kalibrasyonu açık
ürün kabul adımlarıdır.

# Genel rapora dönüşüm

Sunumdaki 24 ana slayt daha sonra hazırlanacak genel Word raporunda şu
bölümlere dönüşebilir:

1. Özet ve proje amacı
2. Donanım araştırması ve gereksinimler
3. Sistem mimarisi ve AD9364 kısıtları
4. Vivado tasarımı ve timing kapanışı
5. Vitis/bare-metal yazılım
6. JTAG bring-up ve hata analizi
7. RF aktivite testleri
8. PL FFT mimarisi ve bit-doğru doğrulama
9. Kart üstü FFT kabulü
10. UART protocol v2 ve Python laboratuvar uygulaması
11. Kontrollü CW kabul planı
12. Monopulse RF kontrolü ve kalibrasyon yol haritası
13. Sonuçlar, sınırlamalar ve gelecek çalışmalar
14. Ekler: pin tablosu, register/protokol sözleşmesi, loglar ve hashler
