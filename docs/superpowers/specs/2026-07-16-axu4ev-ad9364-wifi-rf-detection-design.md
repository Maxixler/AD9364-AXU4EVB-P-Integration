# AXU4EVB-P + AD9364 2.4 GHz Wi-Fi RF Algılama Tasarımı

**Tarih:** 16 Temmuz 2026
**Durum:** Mimari kullanıcı tarafından onaylandı; uygulama öncesi tasarım
**Hedef ortam:** AXU4EVB-P, AD9364, Vitis/XSCT 2020.1, bare-metal Cortex-A53 #0, JTAG ve PS_UART

## 1. Amaç

İlk aşamada AXU4EVB-P ve AD9364 alıcı yolunun gerçek bir 2.4 GHz Wi-Fi sinyalini havadan algılayabildiğini tekrarlanabilir biçimde doğrulamak amaçlanır. Kontrollü RF kaynağı olarak kullanıcının 2.4 GHz'e zorlanmış telefon hotspot'u kullanılır. Uygulama Wi-Fi paketlerini çözmez ve içerik toplamaz; yalnızca seçili kanaldaki RF enerji değişimini, burst davranışını ve DMA örneklerini ölçer.

Test, mevcut çalışan Golden JTAG başlatma zincirini kullanır ve bütün sonucu PS_UART üzerinden PuTTY'ye verir. İlk sürümde PC tarafında FFT, grafik veya sürekli IQ aktarımı bulunmaz.

## 2. Doğrulanmış donanım sınırları

- AD9364 tek bağımsız RX ve tek bağımsız TX zincirine sahip 1x1 bir RF transceiver'dır.
- Karttaki `RXA` ve `RXB`, iki eşzamanlı alıcı değildir; aynı RX zinciri için seçilebilir iki RF girişidir.
- Kart şemasına göre RXA geniş bant fakat kayıplı eşleşmeye, RXB ise 2.4 GHz eşleşmesine sahiptir. Bu testte anten `RXB` konektörüne bağlanır ve yazılım `B_BALANCED` girişini seçer.
- Mevcut uygulamanın AD9364 için bildirdiği iki ADC kanalı iki anten değil, bir kompleks örneğin `I` ve `Q` bileşenleridir.
- Gerçek eşzamanlı çift anten alımı bu kapsamda yoktur. Bunun için ileride AD9361 2x2 tabanlı donanım veya senkronize ikinci AD9364 gerekir.

## 3. Kapsam

Bu sürüm şunları sağlar:

- RXB üzerinden yalnızca alım yapan güvenli AD9364 yapılandırması.
- 2.4 GHz Wi-Fi kanal 1-13 merkez frekanslarının taranması.
- Hotspot kapalı ve açık ölçümlerinin aynı uygulama çalışması içinde karşılaştırılması.
- Tekrarlanan sonlu AXI DMAC bloklarıyla I/Q örnek yakalama.
- Kanal başına AD9364 RSSI, ortalama kompleks örnek gücü, tepe değer, clipping ve burst doluluk ölçümleri.
- En belirgin değişimin görüldüğü kanalın yaklaşık 10 saniye izlenmesi.
- UART üzerinde ayrı `PLATFORM`, `RF_ACTIVITY` ve genel test sonucu.
- Mevcut Golden release'in değiştirilmeden korunması; Golden donanım artifact'leriyle yalnızca yeni workspace ELF'ini yükleyen Candidate başlatma modu.

Bu sürüm şunları kapsamaz:

- 802.11 senkronizasyonu, demodülasyonu, paket veya payload çözme.
- Spektrum/FFT grafiği veya IQ verisinin PC'ye sürekli aktarılması.
- Kayıpsız sürekli streaming garantisi.
- TX testi veya havadan yayın.
- Eşzamanlı çift anten/MIMO.
- PetaLinux, IIO ağ servisi veya libiio istemcisi.
- Yeni Vivado bitstream'i; ilk uygulama yalnızca mevcut doğrulanmış HDL veri yolunu kullanır.

## 4. Seçilen yaklaşım

İlk donanım kanıtı, bare-metal A53 uygulamasında tekrarlanan one-shot DMA yakalamaları ve CPU üzerinde hafif istatistik hesabıyla yapılır. Bu yaklaşım mevcut Golden sistemle en küçük değişikliği gerektirir, hata durumunda kolay incelenir ve UART ile bağımsız çalışır.

PL içinde sürekli güç ölçer tasarlamak daha kesintisiz veri sağlar fakat yeni HDL, bitstream ve zamanlama doğrulaması gerektirir. PetaLinux/IIO ise ileride grafik ve sürekli veri aktarımı için doğru hedeftir fakat ilk RF doğrulamasını gereksiz yere geciktirir. Bu iki seçenek sonraki aşamalara bırakılır.

## 5. Yazılım mimarisi

Mevcut `main.c`, platform ve AD9364 başlatmasını yürütmeye devam eder. Wi-Fi testine ait davranış odaklı modüllere ayrılır:

```text
main.c
  platform + AD9364 + RX DMAC initialization
                    |
                    v
wifi_rf_test.c/.h
  UART state machine, channel scan, monitor, verdict
                    |
          +---------+---------+
          v                   v
wifi_rf_capture.c/.h   wifi_rf_metrics.c/.h
  LO tune, settle,       pure I/Q calculations,
  one-shot DMA, RSSI     baseline comparison
```

Sorumluluklar:

- `main.c`: mevcut no-OS cihazlarını kurar, TX güvenliğini uygular ve özellik bayrağı açıksa Wi-Fi testini çağırır.
- `wifi_rf_test`: kullanıcı etkileşimini ve `BASELINE_SCAN -> ACTIVE_SCAN -> MONITOR -> RESULT` durum makinesini yönetir.
- `wifi_rf_capture`: RX LO ayarı, yerleşme gecikmesi, RSSI okuma, DMA zaman aşımı ve cache invalidate işlemlerini tek arayüz altında toplar.
- `wifi_rf_metrics`: donanımdan bağımsız signed I/Q bloklarını analiz eder. Bu ayrım deterministik test vektörleriyle bilgisayarda veya hedefte sınanmasını sağlar.

Özellik `WIFI_RF_TEST` derleme bayrağıyla etkinleşir. Bayrak kapalıyken mevcut uygulama davranışı korunur. Golden release içindeki doğrulanmış ELF'in üzerine yazılmaz.

Başlatma aracına üçüncü bir `Candidate` modu eklenir. Bu mod Golden manifestten doğrulanmış `system_top.bit`, PMUFW ve `psu_init.tcl` dosyalarını; workspace'ten ise açıkça `Vitis/workspace/ad9364app/Release/ad9364app.elf` dosyasını alır. Release/Debug arasında sessiz fallback yapılmaz; doğrulanmış otomatik build zincirinin ürettiği Release ELF yoksa başlatma karta erişmeden hata verir. Böylece ilk RF testi için Vivado artifact'leri değişmez, fakat uygulama hızlıca build edilip denenebilir. Mevcut `Golden` ve `Workspace` modlarının anlamı değişmez.

## 6. Sabit RF ve yakalama ayarları

İlk sürümün ayarları özellikle mevcut çalışan yapılandırmaya yakın tutulur:

| Ayar | Değer |
|---|---:|
| RX portu | `B_BALANCED` / RXB |
| Kanal aralığı | 1-13 |
| Kanal merkezleri | `2412 + 5 * (kanal - 1)` MHz |
| RX örnekleme hızı | 30.72 MSPS |
| RX analog bant genişliği | 18 MHz |
| İlk tarama dwell süresi | kanal başına 250 ms |
| DMA biçimi | interleaved signed 16-bit I, Q |
| DMA modu | sonlu, non-cyclic, tekrar başlatılan |
| DMA zaman aşımı | blok başına 500 ms |
| Monitor süresi | 10 s |
| UART monitor özeti | 500 ms'de bir |

18 MHz bant genişliği bir 20 MHz Wi-Fi kanalının kenarlarını tam ölçmek için ideal değildir; ancak ilk amaç paket çözmek değil, kontrollü hotspot açıldığında kanal enerjisindeki değişimi güvenilir biçimde görmektir. Mevcut doğrulanmış saat zincirini koruduğu için ilk testte tercih edilir.

Baseline taramasında her kanal için slow-attack AGC kısa süre yerleştirilir, elde edilen RX gain değeri kaydedilir ve yakalama öncesinde gain manual moda alınarak bu değerde dondurulur. Active tarama ve monitor aynı kanalın kaydedilmiş baseline gain değerini kullanır. Böylece hotspot açıldığında AGC'nin dijital örnek gücünü bastırması önlenir ve iki tarama karşılaştırılabilir kalır. Active ölçümde clipping oluşursa gain otomatik değiştirilmez; ölçüm `INCONCLUSIVE` olur ve test daha uzak hotspot/anten konumuyla yeniden çalıştırılır.

Her kanal ayarından sonra LO'nun yerleşmesi için kısa bir gecikme uygulanır. Kanalın 250 ms ölçüm penceresi içinde mümkün olduğu kadar çok sonlu DMA bloğu yakalanır; UART'a blok başına değil, yalnızca kanal özeti yazılır. Böylece seri port trafiği ölçüm zamanlamasını bozmaz.

## 7. RX-only ve TX güvenliği

Uygulama RF ölçümünden önce aşağıdaki kontrolleri sırasıyla uygular:

1. RX girişini `B_BALANCED` olarak ayarlar ve geri okuyarak doğrular.
2. TX zayıflatmasını desteklenen maksimum değer olan `89750 mdB` yapar.
3. ENSM durumunu `ENSM_MODE_RX` yapar ve geri okuyarak RX durumunu doğrular.
4. AXI DAC, DDS ve TX DMAC veri üretimini Wi-Fi test yolunda başlatmaz.
5. UART'ta `RX_ONLY: PASS` görülmeden kanal taramasına geçmez.

Fiziksel testte yalnızca RXB'ye 2.4 GHz anten bağlanır; TXA ve TXB boş bırakılır. Bir güvenlik adımı başarısız olursa DMA ölçümü başlatılmaz ve uygulama `PLATFORM: FAIL` ile durur.

## 8. Kullanıcı ve veri akışı

Testin tek çalıştırmadaki akışı şöyledir:

1. Candidate başlatıcı, Golden BIT/PMUFW/PS başlatma dosyalarını hash kontrolünden geçirir ve workspace test ELF'ini A53'e yükler.
2. Uygulama AD9364 Rev bilgisini, RX-only durumunu, RXB'yi, örnekleme hızını ve bant genişliğini yazdırır.
3. PuTTY `Hotspot'u kapatın ve Enter'a basın` mesajını gösterir.
4. Kullanıcı Enter'a bastığında kanal 1-13 baseline taraması yapılır.
5. PuTTY `Hotspot'u 2.4 GHz olarak açın, trafik oluşturun ve Enter'a basın` mesajını gösterir.
6. Kullanıcı hotspot'a ikinci bir cihaz bağlar ve indirme, hız testi veya video gibi trafik üretir; ardından Enter'a basar.
7. Aynı kanal ve RF ayarlarıyla active tarama yapılır.
8. Baseline-active farkı en kuvvetli kanal seçilir ve yaklaşık 10 saniye izlenir.
9. UART, platform sağlığını, RF aktivite sonucunu ve genel sonucu yazdırır.

PuTTY'deki beklenen özet biçimi:

```text
RX_ONLY: PASS port=RXB fs=30.72MSPS bw=18MHz
BASELINE_SCAN: START channels=1-13 dwell=250ms
CH=01 FREQ=2412MHz GAIN=44dB RSSI=-61.25dB PWR=-48.30dBFS16 PEAK=-20.10dBFS16 CLIP=0 BURST=3% DMA=OK
...
ACTIVE_SCAN: START
CH=06 FREQ=2437MHz GAIN=41dB RSSI=-43.75dB PWR=-35.10dBFS16 PEAK=-8.20dBFS16 CLIP=0 BURST=48% DMA=OK
SELECTED: CH=06 FREQ=2437MHz DELTA_RSSI=+17.50dB DELTA_PWR=+13.20dB DELTA_BURST=+45pp
MONITOR: CH=06 duration=10s
...
PLATFORM: PASS
RF_ACTIVITY: PASS
WIFI_RF_TEST: PASS
```

`dBFS16`, signed 16-bit I/Q saklama biçimine göre normalize edilen göreli dijital ölçümdür; kalibre edilmiş dBm değildir. UART gösteriminde AD9364 sürücüsünün pozitif RSSI attenuation büyüklüğü negatif işaretle yazılır; daha az negatif değer daha güçlü sinyal demektir. RSSI de ilk sürümde yalnızca göreli karşılaştırma için kullanılır. Mutlak RF güç ölçümü için ileride kalibre edilmiş kaynak ve bilinen kablo/attenuator kayıpları gerekir.

## 9. Ölçümler ve karar kuralları

Her DMA bloğu için aşağıdaki değerler hesaplanır:

- `mean_power`: tüm kompleks örneklerde `I^2 + Q^2` ortalaması; taşmayı önlemek için 64-bit akümülatör kullanılır.
- `power_dbfs16`: `10*log10(mean((I/32768)^2 + (Q/32768)^2)/2)` tanımıyla normalize edilmiş dijital güç.
- `peak_dbfs16`: bloktaki en büyük `abs(I)` veya `abs(Q)` değeri.
- `clip_count`: `abs(I)` veya `abs(Q)` değeri tam ölçeğin %98'ine ulaşan örnek sayısı.
- `burst_occupancy`: kısa alt pencerelerin yüzde kaçının o kanalın baseline medyan gücünü en az 6 dB aştığı.
- `rssi`: `ad9361_get_rx_rssi()` ile okunan göreli alıcı RSSI değeri.
- `gain_db`: baseline AGC yerleşmesinden sonra kaydedilen ve baseline/active çifti boyunca sabit tutulan RX gain.

Hotspot kararı tek bir ölçüme bağlanmaz. Seçilen kanalda aşağıdaki üç göstergeden en az ikisi sağlanırsa `RF_ACTIVITY: PASS` verilir:

- RSSI, baseline'a göre en az 3 dB güçlenmiştir.
- DMA ortalama gücü baseline'a göre en az 3 dB artmıştır.
- Burst doluluğu baseline'a göre en az 20 yüzde puan artmıştır.

Ayrıca 10 saniyelik monitörde en az üç adet 500 ms özet penceresi baseline burst eşiğini aşmalıdır. Tüm DMA ve donanım kontrolleri başarılı olduğu halde bu RF koşulları oluşmazsa sonuç donanım arızası olarak etiketlenmez; `PLATFORM: PASS`, `RF_ACTIVITY: INCONCLUSIVE`, `WIFI_RF_TEST: INCONCLUSIVE` yazdırılır. Kullanıcı hotspot'u antene yaklaştırıp trafik üreterek testi tekrarlar.

Kalıcı clipping oranı toplam örneklerin %0.1'ini aşarsa sonuç `RF_ACTIVITY: INCONCLUSIVE` olur ve UART anten/hotspot mesafesini artırma uyarısı verir. Böylece saturasyon yanlış başarı olarak sayılmaz.

## 10. Hata yönetimi

- AD9364 ürün kimliği veya init başarısızsa: `PLATFORM: FAIL stage=AD9364_INIT`; tarama yapılmaz.
- RXB seçimi, TX attenuation veya ENSM doğrulaması başarısızsa: `PLATFORM: FAIL stage=RX_ONLY`; tarama yapılmaz.
- LO ayarı başarısızsa: ilgili kanal `LO_ERROR` olur. Herhangi bir kanal hatası genel platform sonucunu `FAIL` yapar.
- RSSI okuması başarısızsa kanal DMA ölçümü yine tamamlanır fakat `RSSI=ERROR` yazılır; karar kalan iki DMA göstergesiyle verilemezse sonuç `INCONCLUSIVE` olur.
- DMA başlatma veya 500 ms tamamlama beklemesi başarısızsa kanal `DMA_ERROR` olur ve platform sonucu `FAIL` olur. Sonsuz otomatik tekrar yapılmaz.
- UART Enter beklemesi sırasında alınan CR, LF veya CRLF tek onay olarak ele alınır; diğer karakterler yok sayılır.
- Beklenmeyen örnek sayısı veya I/Q hizası görülürse `SAMPLE_FORMAT_ERROR` verilir ve karar üretilmez.
- Her hata yolu TX'i maksimum attenuation'da ve ENSM'yi RX/ALERT güvenli durumunda bırakır.

## 11. Test stratejisi

### 11.1 Donanımdan bağımsız ölçüm testleri

`wifi_rf_metrics` sabit I/Q test vektörleriyle doğrulanır:

- Tüm sıfırlar için minimum/boş güç ve sıfır clipping.
- Bilinen sabit I/Q genliği için beklenen 64-bit güç ve dBFS16 toleransı.
- Pozitif ve negatif tam ölçek yakınındaki örnekler için tepe ve clipping sayısı.
- Sessiz ve burst içeren sentetik pencereler için burst doluluğu.
- Baseline/active çiftlerinde üç göstergenin iki tanesiyle `PASS`, yetersiz farkla `INCONCLUSIVE`.
- Büyük blokta güç toplamının 32-bit taşmadan 64-bit ile doğru kalması.

### 11.2 Statik entegrasyon kontrolleri

- `WIFI_RF_TEST` açıkken RXB seçimi ve `ENSM_MODE_RX` doğrulamasının taramadan önce bulunması.
- Wi-Fi test yolunda DAC/DDS/TX DMAC başlatılmaması.
- Kanal tablosunun 1-13 ve 2412-2472 MHz olması.
- DMA zaman aşımının sonlu olması.
- Golden release artifact hash'lerinin değişmemesi.

### 11.3 Kart kabul testi

1. Kart ve bilgisayar soğuk başlangıçtan açılır.
2. Candidate modu Golden donanım zincirini ve workspace Wi-Fi test ELF'ini otomatik JTAG başlatıcıyla yükler.
3. 2.4 GHz anten yalnızca RXB'ye bağlıdır; hotspot başlangıçta kapalıdır.
4. Baseline taraması tamamlanır ve 13 kanalın tamamında `DMA=OK` görülür.
5. Hotspot açılır, ikinci cihaz bağlanır ve sürekli trafik üretilir.
6. Active tarama ve 10 saniyelik monitor tamamlanır.
7. `RX_ONLY: PASS`, `PLATFORM: PASS`, `RF_ACTIVITY: PASS` ve `WIFI_RF_TEST: PASS` görülür.
8. Aynı test uygulama yeniden başlatılarak ikinci kez tekrarlanır ve seçilen kanal/aktivite sonucu tutarlı kalır.

## 12. Kabul ölçütleri

Uygulama aşağıdaki şartlarda tamamlanmış sayılır:

1. Mevcut Golden BIT, XSA, PMUFW, `psu_init.tcl` ve uygulama ELF'i değiştirilmez.
2. Test ELF'i, Golden donanım artifact'lerini ve workspace uygulamasını birleştiren tek tık Candidate JTAG akışıyla başlatılabilir.
3. UART, RXB seçimini ve RX-only güvenlik kontrollerini açıkça doğrular.
4. Kanal 1-13 baseline ve active taramaları sonlu sürede tamamlanır.
5. Her kanal için RSSI, güç, tepe, clipping, burst ve DMA durumu tek satırda raporlanır.
6. Platform arızası ile algılanamayan RF aktivitesi birbirinden ayrılır.
7. Telefon hotspot'u açılıp trafik oluşturulduğunda test iki ardışık çalışmada `WIFI_RF_TEST: PASS` üretir.
8. TXA/TXB üzerinden örnek, DDS veya DMA verisi gönderilmez.
9. Saf metrik hesapları deterministik test vektörlerini geçer.
10. Belgelenen UART kabul çıktısı kart test kaydına eklenir; ancak yeni aday yalnızca kullanıcı doğrulamasından sonra yeni Golden release'e yükseltilebilir.

## 13. Sonraki aşamalar

İlk RF aktivite testi geçtikten sonra geliştirme sırası şöyledir:

1. IQ bloklarını PC'ye aktararak FFT ve waterfall grafiği.
2. Daha uzun/kesintisiz akış için cyclic DMA veya PL tabanlı güç/FFT ön işleme değerlendirmesi.
3. PetaLinux + ADI IIO sürücüleri + libiio ile standart kullanıcı alanı veri yolu.
4. Gerekirse AD9361 2x2 veya ikinci senkron AD9364 ile gerçek çift anten mimarisi.

Bare-metal Golden RF testi bu aşamalarda donanım regresyon referansı olarak korunur.
