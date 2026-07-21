AXU4EVB-P + AD9364 + FPGA FFT / RF Switch / Monopulse Teknik Denetim Raporu

21 TEMMUZ 2026 GÜNCEL DAL UZLAŞTIRMA NOTU

Bu rapor `d264bddd` commit'i ve `codex/wifi-rf-detection` dalı üzerinde
hazırlanmış salt-okunur denetimdir. Güncel uygulama dalı
`codex/axu4ev-ad9364-monopulse` üzerinde software monopulse foundation kartta
iki kez kabul edilmiş, harici RF kontrol sözleşmesi ayrıca yazılmıştır. Bu
nedenle aşağıdaki eski-dal gözlemleri tarihsel kanıt olarak korunur; şu
düzeltmeler rapordaki çelişen önerilerin yerine geçer:

- ZX80-DR230-S+ DC-3 GHz'dir; DC-23 GHz değildir.
- HMC936A 1.2-1.4 GHz BDC-sonrası IF yolunda kullanılacaktır. AD9364 LO sabit
  1.3 GHz diye kodlanmayacak, ölçülen BDC IF merkezinden üretilecektir.
- Monopulse dört durumlu S0-S3 mimarisi “opsiyonel A/B sonrasına eklenen ayrı
  ürün” değildir; kullanıcı tarafından onaylanan bağlayıcı ürün mimarisidir.
  Buna rağmen geliştirme riskini azaltmak için önce tek-girişli FFT shadow
  path, sonra harici kontrol ve dört-durum FSM uygulanacaktır.
- AD9364 tek RX olduğu ve S0-S3 ardışık yakalandığı için kompleks frame-to-frame
  `Delta/Sigma` ürün sonucu kabul edilmez. Bağlayıcı sonuç güç tabanlı normalize
  AZ/EL oranıdır. Kompleks peak Re/Im yalnız diagnostik ve koherens araştırma
  verisidir.
- İlk FFT doğrulaması PS tetiklemeli tek-karedir. Kullanıcının istediği sürekli
  mod tasarım sözleşmesindedir; ping-pong BRAM, atomik bank swap ve throughput
  testiyle ikinci alt aşamada açılır. Sürekli host/DDR spectrum streaming ayrı
  performans işidir.
- İlk switch/phase-shifter elektriksel kontrolü PS/manual olabilir; nihai S0-S3
  durum sırası deterministik PL FSM'e aittir.
- Tam 2048-bin spectrum ve peak bilgisi zorunludur. Spectrum AXI BRAM üzerinden,
  control/status AXI-Lite üzerinden taşınır. `PEAK_BIN`, `PEAK_POWER`,
  `PEAK_RE`, `PEAK_IM`, `FRAME_ID`, `RF_STATE`, hata ve CDC epoch alanları
  birlikte tanımlanır.
- 2048 x 64-bit tek spectrum bankası yaklaşık dört BRAM36, ping-pong iki banka
  yaklaşık sekiz BRAM36 gerektirir. Raporun farklı tahminleri yalnız ön tahmindir;
  kabul ölçütü Vivado sentez/implementation utilization raporudur.
- 30.72 MSPS foundation kart kanıtı artık mevcuttur; 61.44 MSPS hâlâ ayrı
  performans kapısıdır. Temiz Candidate build, I/Q format ILA kanıtı ve bit-true
  FFT modeli PL entegrasyonundan önce/entegrasyon sırasında kapanacaktır.

GÜNCEL SONUÇ: Mimari uygulanabilir. Bağlayıcı sıra; Golden/build güveni, I/Q
format kapısı, 2048-point tek-kare FFT, full-spectrum/peak doğrulaması,
ping-pong sürekli mod, RF elektriksel kapı, dört-durum PL FSM ve güç tabanlı
monopulse kalibrasyonudur. PetaLinux/pyadi-iio ancak kart kabulünden sonra gelir.

Denetim tarihi: 2026-07-21
Denetçi: Salt-okunur otomatik denetim
Başlangıç commit: d264bddd5644529099e7516b24c9b4d54d2da47d
Branch: codex/wifi-rf-detection

1. Yönetici Özeti
Proje, çalışan bir AD9364 bare-metal DMA capture sistemine sahiptir. Golden sürüm 2026-07-16-bringup-v1 SHA-256 korumalı ve immutable'dır. Mevcut C tabanlı Wi-Fi RF metrik motoru (wifi_rf_analyze_block, wifi_rf_capture_channel) DMA üzerinden zaman-alanı I/Q örnekleri almakta ve mean power, clip count, RSSI gibi metrikler üretmektedir. PL FFT shadow path için henüz hiçbir RTL kodu yazılmamıştır — tüm FPGA sinyal işleme zinciri yalnızca plan aşamasındadır.

Yeni monopulse mimarisi (kullanıcının son mesajındaki), nihai plandaki basit A/B SPDT switch yaklaşımından önemli ölçüde farklıdır: Σ, ΔAZ, ΔEL yolları, ZX80-DR230-S+ switch, HMC936A 6-bit phase shifter ve RF combiner eklenmiştir. Bu genişleme PL'deki aritmetik gereksinimlerini de kompleks bölme ve Σ/Δ rekonstrüksiyonuna taşımaktadır.

En büyük üç risk:

Critical — RF donanımı belirsizliği: HMC936A phase shifter ~1.2–1.4 GHz ile sınırlıdır. 2.4 GHz Wi-Fi bandında çalışmaz. ZX80-DR230-S+ kontrol gerilimi, pin eşlemesi ve FPGA GPIO voltaj uyumluluğu (FMC bank 1.8V vs 3.3V/5V) henüz belirlenmemiştir. Monopulse anten sistemi fiziksel olarak mevcut değilse tüm kompleks kalibrasyon ve Δ/Σ hesapları test edilemez.

High — I/Q formatı ILA ile doğrulanmadan RTL başlaması: AD9364'ün 12-bit örneklerinin 16-bit alana nasıl yerleştirildiği (sign-extended mi, left-aligned mi, right-aligned mi), I/Q çiftlerinin packed sırası ve ADI-specific valid/enable davranışı henüz ILA ile ölçülmemiştir. Nihai plan bunu Faz 1 kapısı olarak tanımlar. Bu kapı geçilmeden yazılan herhangi bir adc_stream_bridge hatalı olacaktır.

High — Vivado build yeniden üretilebilirliği kanıtlanmamıştır: Paket 1 — Temiz build kapısı henüz yapılmamıştır. Mevcut Golden XPR/bitstream/XSA temiz Vivado 2020.1'de sıfırdan üretilip manifest'teki SHA-256 ile karşılaştırılmamıştır. Yeni IP eklenmeden build zincirinin yeniden üretilebilir olduğu kanıtlanmalıdır.

2. İncelenen Kanıtlar
Dosya	Tür	Kritiklik
fmcomms2_bd.tcl	Block Design Tcl	★★★ RX veri yolu bağlantıları
axu4ev_system_bd.tcl	Block Design Tcl	★★★ PS, clock, reset konfigürasyonu
system_project.tcl	Vivado proje Tcl	★★ Build akışı
system_constr.xdc	XDC constraint	★★★ Pin eşleme, I/O timing
main.c	C kaynak (1255 satır)	★★★ AD9364 init, DMA
wifi_rf_capture.c	C kaynak (192 satır)	★★★ DMA capture, kanal döngüsü
wifi_rf_metrics.c	C kaynak (125 satır)	★★★ Zaman-alanı metrikler
app_config.h	C header	★★ Build flag'leri
manifest.json	JSON	★★★ Golden artefakt SHA-256
axu4ev_ad9364_fft_rf_switch_nihai_plan.md	Markdown plan	★★★ Nihai geliştirme planı
README.md	Markdown	★★ Golden kullanım talimatı
Build-Axu4evAd9364App.tcl	XSCT build	★★ Vitis build akışı
git log --oneline -42	Git geçmişi	★★ 42 commit, linear history
git tag -l	Git tag	★★ Sıfır tag
Commit geçmişi: 42 commit, linear (merge commit yok). Tüm commit'ler conventional-commit formatında (feat:, fix:, docs:, test:, release:). Son 10 commit Wi-Fi RF capture/test altyapısını eklemiş.

Git tag'leri: Mevcut değil. "2026-07-16-bringup-v1" bir Git tag'i değil, PROJECT/releases/ altında SHA-256 korumalı bir dizindir. Bu yaklaşım immutable release için çalışır ancak git describe veya tag-tabanlı CI trigger'ları kullanılamaz.

3. Doğrulanan Doğru Kararlar
3.1 AD9364 RX veri yolu mimarisi
Karar: Tap noktası util_ad9361_adc_fifo çıkışı ile util_ad9361_adc_pack girişi arası olarak seçilmiştir.
Neden doğru: Mevcut util_wfifo CDC'sini yeniden kullanır; ikinci bir asenkron FIFO'yu zorunlu kılmaz. Pack öncesi 4×16-bit paralel kanal formu, bireysel I/Q örneklerine erişimi kolaylaştırır. DMAC yoluna (64-bit packed_fifo_wr) backpressure üretmez.
Kanıt: fmcomms2_bd.tcl:94-133 — FIFO çıkışları dout_valid_0, dout_enable_0..3, dout_data_0..3 olarak pack girişine bağlanır. packed_fifo_wr ayrı bir sinyaldir, tap bu sinyale dokunmaz.
Güven: Yüksek
3.2 Finite-frame mimarisi seçimi
Karar: İlk sürüm sürekli streaming değil, tetiklemeli finite-frame capture kullanacak.
Neden doğru: 2048 örneklik capture süresi 30.72 MSPS'de ~66.7 µs'dir. Bu süre içinde FFT processing latency'si (Pipelined Streaming I/O için yaklaşık 2048+ pipeline delay cycle) capture süresini aşabilir. Finite-frame, buffer dolduktan sonra capture'ı kapatıp FFT'nin yetişmesini bekler — gerçek zamanlı constraint'i kaldırır. DMA yoluna backpressure riskini de elimine eder.
Kanıt: Nihai plan Faz 2 tanımı ve Section 6. PG109'a göre Pipelined Streaming I/O 2048-point FFT latency'si ~4200-4400 cycle'dır; 100 MHz'de bu ~42-44 µs eder — capture süresine yakındır.
Güven: Yüksek
3.3 Ortak MGC gain kullanımı
Karar: A ve B ölçümlerinde aynı MGC gain değeri kullanılacak.
Neden doğru: Farklı gain değerleri A/B genlik oranını bozar. Mevcut C kodu zaten baseline→AGC ölçüp active→MGC+baseline gain pattern'ini uygulamaktadır.
Kanıt: wifi_rf_capture.c:148-154 — baseline'de AGC ile gain ölçülür, active'de gain_db = baseline->gain_db ile MGC uygulanır.
Güven: Yüksek
3.4 FDD/ENSM güvenli kabulü
Karar: FDD ve independent-FDD güvenli durumdur; ENSM değiştirilmez.
Neden doğru: FDD modunda AD9364 sürekli RX'tedir, TX ayrı LO kullanır. ENSM transition'ları sırasında data path kesintisi ve calibration reset riski vardır.
Kanıt: main.c:198 — frequency_division_duplex_mode_enable=1 varsayılan; wifi_rf_capture.c:68-71 — FDD modunda ENSM değiştirilmez.
Güven: Yüksek
3.5 TX güvenlik önlemi
Karar: TX kapalı veya maksimum attenuation'da.
Neden doğru: Harici RF kaynağı bağlıyken TX açık olması PA hasarına veya yasal olmayan yayına neden olabilir.
Kanıt: wifi_rf_capture.c:64 — ad9361_set_tx_attenuation(ctx->phy, 0, 89750) (maksimum ~89.75 dB attenuation).
Güven: Yüksek
3.6 Shadow path backpressure izolasyonu
Karar: FFT yolu DMAC'a asla backpressure uygulamamalıdır.
Neden doğru: Finite-frame'de capture buffer dolduktan sonra ADC örnekleri bilinçli olarak drop edilir — bu DMA kaybı değildir çünkü DMA capture'ı o anda aktif değildir. Pack→DMAC yolu her zaman TREADY=1 görür.
Kanıt: Nihai plan Section 4 shadow yol sözleşmesi — açıkça "FFT tarafındaki TREADY, busy veya buffer-full durumu mevcut pack/DMAC yolunu durduramaz" yazar.
Güven: Yüksek (henüz implementasyon kanıtı yok ancak mimari prensip doğru)
3.7 Bit-doğru FFT doğrulama yaklaşımı
Karar: Python modeliyle aynı scaling schedule, rounding ve saturation kullanılacak; 0 LSB tolerans.
Neden doğru: Kapalı-form integer FFT'de referans modelle bit-doğru eşleşme, yalnızca peak lokasyonu doğrulamasından çok daha güçlü bir kanıttır. Scaling, rounding ve overflow hatalarını anında yakalar.
Kanıt: Nihai plan Section 11 sayısal sözleşme tablosu — 0 LSB fark, tüm aşamalar için format tanımı.
Güven: Yüksek
3.8 Frame korelasyonu (CRC-32 + imza)
Karar: DMA ve PL capture'ı aynı frame üzerinde CRC-32/ISO-HDLC + ilk 8 örnek imzası ile eşleştirilecek.
Neden doğru: Mevcut DMAC akışı frame_id taşımaz. Zaman damgası eşleştirmesi yazılım gecikmesi nedeniyle güvenilir değildir. CRC-32 korelasyonu deterministiktir.
Kanıt: Nihai plan Section 5.1 somut sözleşme — 5 adımlı eşleştirme protokolü.
Güven: Yüksek (CRC-32/ISO-HDLC poly 0x04C11DB7 standart ve güvenilirdir)
4. Yanlış veya Kanıtlanmamış Varsayımlar
4.1 GPIO serbest pin varsayımı
İddia: Mevcut gpio_ctl[3:0] veya başka GPIO pinleri RF switch kontrolü için kullanılabilir.
Gerçek durum: system_constr.xdc:90-93 — gpio_ctl[3:0] AD9364'ün CTRL_IN girişlerine (LA24_P/N, LA25_P/N) bağlıdır. Bunlar AD9364 kontrol sinyalleridir, serbest GPIO değildir. gpio_status[7:0] CTRL_OUT, gpio_en_agc, gpio_sync, gpio_resetb de AD9364 fonksiyonlarına bağlıdır. FMC bank'ları 1.8V'tur (system_constr.xdc:94 — LVCMOS18).
Risk: 3.3V veya 5V RF switch/modül kontrolü doğrudan FPGA pininden yapılamaz. Level shifter zorunludur. Yanlış pin seçimi donanım hasarına yol açabilir.
Önerilen düzeltme: Nihai planın zaten belirttiği gibi Section 10:360 — CAM_GPIO (J23, 3.3V) birincil aday ancak switch datasheet'i ile elektriksel inceleme şart.
Güven: Yüksek (kanıt: XDC dosyası)
4.2 Monopulse mimarisinde phase shifter frekans uyumsuzluğu
İddia: HMC936A değerlendirme kartı (EV1HMC936ALP6) RF testlerinde kullanılabilir.
Gerçek durum: Kullanıcının kendi belirttiği gibi, HMC936A ~1.2–1.4 GHz aralığı içindir. 2.4 GHz Wi-Fi bandında çalışmaz. AD9364 ve ZX80-DR230-S+ daha geniş aralığı desteklese bile ortak çalışma bandını phase shifter sınırlar.
Risk: İlk tam zincir testi için 1.3 GHz civarı seçilmek zorundadır. 2.4 GHz'de monopulse test yapılamaz. Ürün hedefi 2.4 GHz ise farklı bir phase shifter (veya wideband alternatif) gerekecektir.
Önerilen düzeltme: Ürün hedef frekansı netleştirilmeli; phase shifter seçimi buna göre yapılmalı.
Güven: Yüksek (kullanıcının kendi notu)
4.3 "İlk 8 kompleks örnek imzası" ile DMA eşleşmesi
İddia: DMA buffer içinde 8-örnek imza aranarak tek ve tam CRC eşleşmesi bulunabilir.
Gerçek durum: Bu yaklaşım teorik olarak doğrudur ancak DMA buffer'ı PL capture'dan daha uzun olacaktır (örneğin 16384 örnek vs 2048). İmza araması O(n) tarama ve her aday 2048-örnek alt-dizi için CRC hesaplaması gerektirir. C tarafında bu işlem DMA transfer süresine eklenir.
Risk: CRC eşleşmesi bulunamaması veya birden fazla eşleşme çıkması durumunda test tekrarı gerekir. Bu deterministik bir sorun değil ancak test süresini uzatır.
Önerilen düzeltme: İmza uzunluğu 8'den 16 örneğe çıkarılabilir; false-positive olasılığını azaltır. Alternatif: PL tarafında DMA'ya özel bir frame_id register'ı yazılıp AXI-Lite üzerinden okunabilir.
Güven: Orta
4.4 30.72 MSPS örnekleme profilinin doğrulanmış olması
İddia: 30.72 MSPS kart üzerinde doğrulanmış başlangıç profilidir.
Gerçek durum: main.c'de rx_path_clock_frequencies dizisinde {983040000, 245760000, 122880000, 61440000, 30720000, 30720000} tanımlıdır. Bu AD9364'ün 30.72 MSPS'yi desteklediğini gösterir ancak gerçek kart testinde bu hızda DMA capture'ın hatasız ç wake_up =31lmış olduğuna dair raporda kanıt yoktur. DMA_EXAMPLE modunda samples=16384 kullanılır (main.c:719); IRQ modunda samples=2048 (main.c:772).
Risk: 61.44 MSPS profilinde veri yolu throughput'u iki katına çıkar. RX DATA_CLK period'u XDC'de 4.00 ns (250 MHz DDR) olarak tanımlıdır — bu 30.72 MSPS için yeterlidir (61.44 MSPS'de 2× data rate = 491.52 Mbps per lane). Ancak divclk oranı ve FIFO davranışı 61.44 MSPS'de test edilmemiştir.
Önerilen düzeltme: 30.72 MSPS'de DMA capture test kanıtı (UART log, DMA transfer count, sıfır overflow) rapora eklenmeli.
Güven: Orta
4.5 "Mevcut DMA zinciri çalışan Golden davranışıdır" iddiası
İddia: DMA yolu kartta doğrulanmış ve ç wake_up =31lmaktadır.
Gerçek durum: manifest.json uart_markers alanında "DMA_EXAMPLE:" string'i başarılı DMA transferinin kanıtıdır. Ancak DMA'nın sürekli, tekrarlı çalışmada overflow veya data corruption üretmediğine dair stress-test kanıtı yoktur.
Risk: PL FFT eklenince clock fanout ve power supply noise değişebilir; DMA timing'i etkilenebilir.
Önerilen düzeltme: Golden DMA regresyon testi her Candidate öncesi tekrarlanmalıdır (nihai planda Paket 5 bunu kapsar).
Güven: Orta
4.6 Gerçek 12-bit örnek yerleşimi
İddia: AD9364 12-bit ADC örnekleri 16-bit alana sign-extended olarak yerleştirilmiştir.
Gerçek durum: Bu ILA ile doğrulanmamıştır. AD9364 register map'inde data format kontrol bitleri vardır. Default davranış sign-extended'dır ancak pp_rx_swap_enable=1 ve rx_frame_pulse_mode_enable=1 ayarları (main.c:353-354,357) ile gerçek bit hizalaması değişebilir.
Risk: Yanlış bit hizalama varsayımıyla yazılan adc_stream_bridge tüm downstream FFT sonuçlarını geçersiz kılar.
Önerilen düzeltme: Nihai plan Faz 1 ILA kapısı zorunludur — bu kapı geçilmeden RTL başlamamalıdır.
Güven: Yüksek
5. Kritik Teknik Riskler
Risk #1 — Critical: Monopulse RF donanımı mevcut olmadan tasarımın tamamlanamaması
Etkilenen bileşen: Tüm Σ/Δ/EL hesapları, kompleks kalibrasyon, faz ölçümü, açı hesabı
Arıza senaryosu: ZX80-DR230-S+, HMC936A, RF combiner ve monopulse anten sistemi fiziksel olarak mevcut değilse, PL'de yapılan tüm kompleks bölme ve Σ/Δ rekonstrüksiyonu donanımda test edilemez. Sadece simülasyonla doğrulanmış bir sistem sahada çalışmayabilir.
Nasıl tespit edilir: Donanım envanteri kontrolü; Faz 5 başlangıcında fiziksel RF bileşenlerin varlığı teyit edilmeli.
Önerilen çözüm: İlk iki minimum sürüm (tek girişli FFT + basit A/B power ratio) RF switch donanımından bağımsız olarak geliştirilebilir. Monopulse genişletmesi ayrı bir faz olarak, donanım hazır olduğunda başlatılmalıdır.
Uygulanacak faz: Faz 0 (karar kapısı)
Risk #2 — High: Monopulse mimarisi ile nihai plan arasındaki kapsam farkı
Etkilenen bileşen: Proje planlaması, kaynak bütçesi, zaman çizelgesi
Arıza senaryosu: Yeni monopulse tasarımı (kullanıcının son mesajı) nihai plandaki basit A/B switch yaklaşımından çok daha karmaşıktır:
Nihai plan: 2 RF durumu (A/B) → 2 capture → 2 FFT → PA/PB → power ratio
Monopulse tasarımı: 4 RF durumu (Σ+ΔAZ, Σ-ΔAZ, Σ+ΔEL, Σ-ΔEL) → 4 capture → kompleks Σ/Δ rekonstrüksiyonu → kompleks bölme → açı LUT
Phase shifter: 64 kod × karakterizasyon
Kalibrasyon: Her RF durumu için kompleks düzeltme katsayısı Bu genişleme PL aritmetik IP kapsamını, BRAM ihtiyacını ve doğrulama matrisini katlar.
Nasıl tespit edilir: İki tasarım dokümanının yan yana karşılaştırılması
Önerilen çözüm: Monopulse tasarımı "Faz 5 sonrası genişletme" olarak sınıflandırılmalı; nihai planın ilk iki minimum sürümü (tek giriş FFT + A/B güç karşılaştırması) ana geliştirme hattı olarak korunmalıdır.
Uygulanacak faz: Faz 0 (plan güncellemesi)
Risk #3 — High: Vivado build yeniden üretilebilirliği kanıtlanmamış
Etkilenen bileşen: Tüm Vivado projesi, IP konfigürasyonları, timing
Arıza senaryosu: Temiz Vivado 2020.1'de Makefile/Tcl ile sıfırdan build alınamazsa mevcut Golden bitstream'in nasıl üretildiği belirsizdir. Yeni IP eklenince build kırılabilir ve kök neden bulunamaz.
Nasıl tespit edilir: Paket 1 — Temiz build kapısı çalıştırılır; XPR/bitstream/XSA üretilir ve manifest SHA-256 ile karşılaştırılır.
Önerilen çözüm: Paket 1'i hemen yapın. ZCU102 bağımlılığı temizlenmeli, Makefile'daki BOARD_NAME ve kart dosyaları doğrulanmalı.
Uygulanacak faz: Faz -1 (build yeniden üretilebilirliği)
Risk #4 — High: GPIO/voltaj uyumsuzluğu nedeniyle donanım hasarı
Etkilenen bileşen: FPGA I/O bank, RF switch, phase shifter
Arıza senaryosu: FMC bank'ları 1.8V LVCMOS18'dir. HMC936A eval kartı 0/5V aktif-low kontrol kullanır. Doğrudan bağlantı FPGA pin hasarına veya tanımsız lojik seviyeye yol açar. ZX80-DR230-S+ kontrol voltajı henüz datasheet'ten doğrulanmamıştır.
Nasıl tespit edilir: Switch/modül datasheet'i + kart şeması + FPGA bank voltajı yan yana kontrol edilir.
Önerilen çözüm: Nihai plan Section 10 donanım sözleşmesi maddeleri eksiksiz tamamlanmadan tek bir GPIO ataması yapılmamalıdır. Level shifter (3.3V→5V) ve buffer zorunludur.
Uygulanacak faz: Faz 5 öncesi
Risk #5 — Medium: I/Q format ve valid/enable davranışı ILA'sız varsayılamaz
Etkilenen bileşen: adc_stream_bridge, tüm downstream FFT sonuçları
Arıza senaryosu: AD9364 1R1T modunda adc_r1_mode=1 sinyali üretir. Bu sinyal util_ad9361_divclk_sel ile clock divider'ı 2x moduna alır. util_ad9361_adc_fifo 4 kanal sunar ancak AD9364 için I0/Q0 aktif, I1/Q1 sıfır veya duplicate olabilir. I/Q sırası (I önce mi Q önce mi), signed/unsigned formatı ve adc_enable ile adc_valid arasındaki zamansal ilişki bilinmeden bridge yazılamaz.
Nasıl tespit edilir: Faz 1 ILA kapısı — util_ad9361_adc_fifo çıkışındaki tüm sinyaller prob edilir.
Önerilen çözüm: ILA capture'ı 4 kanal × (enable, valid, data[15:0]) + dout_valid_0 sinyallerini içermeli; en az 100 örneklik derinlikte tetiklemeli capture alınmalı.
Uygulanacak faz: Faz 1 (ILA)
Risk #6 — Medium: FFT throughput'un 61.44 MSPS'de yetersiz kalması
Etkilenen bileşen: FFT IP, capture buffer, processing clock
Arıza senaryosu: 61.44 MSPS'de 2048 örneklik capture süresi ~33.3 µs'dir. 100 MHz processing clock'ta FFT latency'si ~42-44 µs ise, FFT capture süresinden daha uzun sürer. Sürekli streaming modunda frame'ler arası boşluk kalmaz ve FIFO overflow kaçınılmazdır.
Nasıl tespit edilir: FFT IP latency'si PG109 veya Vivado IP catalog'dan kesin değer alınır, 100 MHz'de cycle sayısı capture süresiyle karşılaştırılır.
Önerilen çözüm: Profil B (61.44 MSPS) finite-frame için sorun değildir; sürekli streaming için 150 MHz processing clock veya ping-pong buffer gerekir. Bu Faz 6 kapsamındadır.
Uygulanacak faz: Faz 6 (performans)
Risk #7 — Medium: Processing clock olarak 100 MHz yeterliliği
Etkilenen bileşen: Tüm PL processing zinciri
Arıza senaryosu: 100 MHz sys_cpu_clk (PL0) ile FFT + magnitude-square + window multiply + AXI yazma toplam latency'si capture süresini aşarsa backpressure oluşur.
Nasıl tespit edilir: Post-synthesis timing raporu + davranışsal simülasyon
Önerilen çözüm: Nihai plan bunu tanır: "150 MHz ancak 100 MHz'te ölçülen throughput gereksinimi karşılanmazsa... değerlendirilecektir" Section 7.
Uygulanacak faz: Faz 6 (performans)
Risk #8 — Low: Git tag eksikliği
Etkilenen bileşen: CI/CD, sürüm takibi
Arıza senaryosu: git describe veya tag-tabanlı trigger kullanan CI pipeline'ları çalışmaz. "2026-07-16-bringup-v1" tag olmadığı için git show 2026-07-16-bringup-v1 başarısız olur.
Nasıl tespit edilir: git tag -l çıktısı boş
Önerilen çözüm: İstenirse her Golden sürüm için git tag -s ile signed tag oluşturulabilir (mevcut dizin-tabanlı immutable release'e ek olarak).
Uygulanacak faz: İsteğe bağlı
6. Vivado ve PL Denetimi
6.1 Veri Yolu
Gerçek RX veri yolu (kaynak koddan doğrulanmış):


AD9364 LVDS RX → axi_ad9361 (l_clk domain)
  → adc_data_i0/q0/i1/q1 [15:0] (4 kanal)
  → adc_enable_i0/q0/i1/q1
  → adc_valid_i0/q0/i1/q1
  → util_ad9361_adc_fifo (util_wfifo)
    → CDC: l_clk → util_ad9361_divclk/clk_out
    → NUM_OF_CHANNELS=4, DIN_DATA_WIDTH=16, DOUT_DATA_WIDTH=16
    → dout_valid_0 (tek valid sinyali!)
    → dout_enable_0..3, dout_data_0..3
  → util_ad9361_adc_pack (util_cpack2)
    → 4×16-bit → 64-bit packed_fifo_wr
    → packed_sync
  → axi_ad9361_adc_dma
    → DMA_DATA_WIDTH_SRC=64
    → CYCLIC=0, DMA_SG_TRANSFER=1
    → HPC0 → DDR
Kritik bulgular:

Arayüz ADI-specific'tir, standart AXI4-Stream değildir. enable, valid ve data sinyalleri kanal başına ayrıdır. dout_valid_0 tek bir valid sinyali olarak pack'i sürer ancak dout_enable_0..3 hâlâ kanal başınadır. Standart AXI4-Stream TVALID/TREADY/TDATA/TLAST/TKEEP kullanmaz.

Veri genişliği: Kanal başına 16-bit, toplam 4 kanal. DMAC kaynak genişliği 64-bit.

AD9364 1R1T modunda bile 4 kanal IP'si vardır. main.c:599 — rx_adc_init.num_channels = 2 (I0/Q0 aktif). AXU4EV için AXI_ADC_NOT_PRESENT tanımlı değil, axi_adc_core kullanılıyor.

ADC kaynağı durdurulamaz. AD9364 sürekli örnek üretir. axi_ad9361 IP'sinde backpressure mekanizması yoktur. Örnekler ya kabul edilir ya da drop edilir. Finite-frame kapanınca drop bilinçlidir.

Tap noktası doğrulaması: util_ad9361_adc_fifo çıkışındaki sinyaller:

dout_valid_0 — tek valid (4 kanal aynı anda geçerli)
dout_enable_0..3 — kanal başına enable
dout_data_0..3 — 16-bit kanal verisi
dout_ovf — overflow (pack'ten gelen fifo_wr_overflow ile bağlı)
6.2 Clock Domain Crossing
Mevcut clock yapısı (kaynak koddan):

Clock	Kaynak	Frekans	Kullanım
rx_clk	AD9364 LVDS DATA_CLK	250 MHz DDR (XDC: 4.00 ns period)	axi_ad9361 l_clk
util_ad9361_divclk/clk_out	l_clk ÷ (2 veya 4)	~125 MHz (2x) veya ~62.5 MHz (4x)	Pack, DMAC, FIFO çıkışı
sys_cpu_clk (PL0)	IOPLL ÷ 15	100 MHz	CPU, AXI interconnect
PL1	IOPLL ÷ 6	250 MHz	Kullanılmıyor
PL2	IOPLL ÷ 3	500 MHz	Kullanılmıyor
CDC analizi:

Mevcut CDC: util_ad9361_adc_fifo (util_wfifo) — l_clk → divclk/clk_out. Bu bir asenkron FIFO'dur (din_clk ve dout_clk farklı domain'ler).
divclk/clk_out frekansı adc_r1_mode/dac_r1_mode sinyallerine göre değişir. AD9364 1R1T'de 2x bölme, 2R2T'de 4x bölme yapar.
İlk tap noktası divclk/clk_out domain'indedir. Bu domain'den 100 MHz sys_cpu_clk domain'ine geçiş için ikinci bir CDC FIFO'su gerekli değildir — eğer processing chain de divclk/clk_out kullanırsa.
Ancak processing clock olarak 100 MHz kullanılırsa CDC FIFO zorunludur.
Öneri:

İlk Candidate'da processing chain divclk/clk_out domain'inde çalıştırılabilir (FIFO çıkışıyla aynı domain). Bu, ikinci CDC'yi elimine eder.
100 MHz tercih edilirse XPM FIFO Async (XCZU4EV'de built-in FIFO36E2) kullanılmalı.
divclk/clk_out frekansı örnekleme profiline göre değişir: 30.72 MSPS 1R1T'de ~61.44 MHz (l_clk=122.88 MHz / 2), 61.44 MSPS 1R1T'de ~122.88 MHz. Bu değişkenlik CDC tasarımında dikkate alınmalı.
6.3 FFT Yapılandırması
Nihai plan önerisi: Vivado FFT v9.1, 2048-point, Pipelined Streaming I/O, fixed-point scaled, 16-bit I/Q, SCALE_SCH=0x6AB, natural-order.

Değerlendirme:

0x6AB = 12'b01_10_10_10_10_11 schedule'ı PG109'a uygundur. Toplam scaling 2^-12.
Pipelined Streaming I/O, Burst I/O'ya göre:
Avantaj: Sürekli veri akışı kabul eder, frame'ler arası boşluk gerektirmez. Daha düşük latency (ilk çıkış ~100-200 cycle sonra gelir).
Dezavantaj: Daha fazla DSP slice kullanır, daha yüksek dinamik güç.
Burst I/O: Frame'ler arası boşluk gerektirir, daha az kaynak kullanır.
Finite-frame capture için ikisi de uygundur. Pipelined seçimi sürekli moda geçişi kolaylaştırır.
Natural-order output: Bit-reversed sıraya göre ekstra BRAM (reorder buffer) gerektirir. Bit-reversed + yazılımda reorder, kaynak tasarrufu sağlar ancak PS yükünü artırır. Natural-order PS readout'u basitleştirir — doğru seçimdir.
6.4 Buffer Kaynak Kullanımı
Tahmini BRAM bütçesi (ön sentez verisi olmadan):

Bileşen	Veri genişliği	Derinlik	BRAM18K eşdeğeri	BRAM36K eşdeğeri
Capture buffer (2048×32-bit raw)	32	2048	4	2
Hann ROM (2048×16-bit)	16	2048	2	1
Spectrum-A buffer (2048×64-bit)	64	2048	8	4
FFT internal (reorder+phase factor)	IP içinde	—	—	—
CDC FIFO (gerekirse)	32+control	~512	1-2	1
Toplam (tahmini)			~15-18	~8-9
XCZU4EV'de toplam 128 BRAM36K (veya 256 BRAM18K) vardır. Golden routed tasarımda 4/128 kullanımda — ~%3. Tahmini yeni kullanım ~8-9 BRAM36K → %7-8. BRAM riski düşüktür.

URAM: XCZU4EV'de 48 URAM288K vardır. 8192 nokta ve üzeri FFT'lerde URAM kullanımı gerekebilir; ilk sürümde gerekmez.

DSP: XCZU4EV'de 240 DSP48E2 vardır. FFT IP 2048-point Pipelined Streaming için yaklaşık 20-30 DSP kullanır (PG109 tahmini). Window multiply (1 DSP), magnitude-square (2 DSP) — toplam ~25-35 DSP. DSP riski düşüktür (%10-15).

6.5 Timing ve Reset
Mevcut Golden WNS: +0.144 ns, WHS: +0.010 ns (nihai plan Section 7'den alıntı).
Yeni IP eklenince timing kapanışı yeniden kanıtlanmalıdır.
Reset: util_ad9361_divclk_reset (proc_sys_reset) ÷ sys_rstgen/peripheral_aresetn zinciri. Yeni IP aynı reset domain'inde olmalı veya kendi reset synchronizer'ını içermelidir.
sys_cpu_clk ile divclk/clk_out arasındaki CDC'de reset: sys_cpu_resetn ve util_ad9361_divclk_reset/peripheral_aresetn farklı domain'lerdedir. CDC FIFO kullanılırsa her iki domain'in reset'i de bağlanmalıdır.
6.6 AXI ve Backpressure
RX DMA: CYCLIC=0, SYNC_TRANSFER_START=1 (pack'ten packed_sync ile tetiklenir).
DMAC fifo_wr arayüzü: packed_fifo_wr sinyali passthrough'dur. DMAC kendi iç FIFO'suna sahiptir.
Shadow path'in backpressure üretmemesi sözleşmesi: capture buffer dolduğunda TREADY=0 → upstream FIFO'ya backpressure. Ancak bu upstream util_ad9361_adc_fifo değil, shadow path'in kendi bridge'idir. Bridge girişinde örnek drop edilir, DMA yolu etkilenmez.
Kritik kontrol noktası: Bridge girişi dout_valid_0'ı pasif olarak dinlemelidir; bu sinyale hiçbir koşulda backpressure uygulayamaz.
7. AD9364 ve RF Denetimi
7.1 Sample Rate ve RF BW
Tanımlı profiller:
Profil A: 30.72 MSPS, RX BW ≈ 18 MHz (varsayılan: rf_rx_bandwidth_hz = 18000000)
Profil B: 61.44 MSPS, RX BW = yapılandırılabilir
AD9364 yetenekleri: 30.72 MSPS ve 61.44 MSPS, rx_path_clock_frequencies dizisinde tanımlıdır. AD9364 maximum RX sample rate 61.44 MSPS'tir.
Kartta doğrulama durumu: 30.72 MSPS'nin kartta çalıştığı UART marker'larından ("DMA_EXAMPLE:") anlaşılıyor ancak 61.44 MSPS test kanıtı yoktur.
7.2 FDD/TDD/ENSM
Varsayılan mod: frequency_division_duplex_mode_enable = 1 (FDD)
independent-FDD = 0 (varsayılan kapalı)
tdd_use_dual_synth_mode_enable = 0
ENSM readback: ad9361_get_en_state_machine_mode() çağrısı wifi_rf_capture.c:66-68'de yapılır.
FDD kabulü: FDD veya PINCTRL_FDD_INDEP ise ENSM değiştirilmez (doğru davranış).
FDD dışı: ENSM_MODE_RX'e geçilir (SPI kontrol).
7.3 MGC/AGC
Baseline capture: RF_GAIN_SLOWATTACK_AGC → gain readback → MGC'ye geç
Active capture: Baseline gain değeriyle MGC
Gain readback: ad9361_get_rx_rf_gain(ctx->phy, 0, &gain_db)
Doğru politika: A/B karşılaştırmasında ortak gain şarttır. Mevcut C kodu bu pattern'i uygular.
7.4 RF Switch — Nihai Plan vs Monopulse Tasarımı
Özellik	Nihai Plan	Monopulse Tasarımı
Switch tipi	SPDT (A/B)	ZX80-DR230-S+ (AZ/EL) + HMC936A phase shifter
Durum sayısı	2	4
Kontrol sinyali	1 GPIO	1-2 GPIO (switch) + 6 GPIO (phase shifter)
RF frekansı	2.4 GHz hedef	Phase shifter ~1.2-1.4 GHz sınırlı
Kalibrasyon	Yol kaybı	Her durum için kompleks düzeltme + faz kodu tablosu
PL aritmetik	PA/PB power ratio	Σ/Δ kompleks rekonstrüksiyonu + kompleks bölme
Monopulse tasarımının avantajları:

Gerçek açı ölçümüne giden tam zincir
Faz bilgisi korunur → yön bilgisi mevcuttur
Daha kapsamlı RF karakterizasyonu
Monopulse tasarımının riskleri:

Donanım bağımlılığı çok daha yüksek
Phase shifter frekans sınırlaması ürün hedefini kısıtlar
PL kaynak kullanımı artar (kompleks bölme, daha fazla BRAM)
Doğrulama matrisi çok daha geniş
7.5 Settling ve Discard
Settling süresi yalnız switch switching time'a değil, AD9364'ün:
RX filter settling'ine (FIR + analog LPF transient)
DC offset tracking recovery'sine
IQ imbalance düzeltme adaptasyonuna da bağlıdır.
Nihai plan settling_cycles ve discard_samples'ı ayrı register olarak tanımlar — doğru yaklaşım.
settling_cycles processing-clock cycle, discard_samples kompleks ADC örneği cinsindendir. Bu ikisi farklı domain'lerdedir ve register dokümanı bunu açıkça belirtmelidir.
7.6 A/B Ölçümlerinin Fiziksel Anlamı
Ardışık A/B ölçümleri koherent değildir. Faz bilgisi ancak sinyal kaynağı yeterince kararlıysa ve ölçümler arası LO phase continuity varsa anlamlıdır. AD9364 LO her tuning'de faz reset'ler.
Power ratio (PA/PB) her zaman anlamlıdır. Koherent olmayan kaynaklarda bile geçerlidir.
Kompleks oran (A/B) yalnız koherent kaynaklarda faz bilgisi taşır. CW sinyal üreteci ile mümkündür; ortam Wi-Fi sinyalleri ile değildir.
Monopulse tasarımındaki Σ/Δ kompleks rekonstrüksiyonu: (Σ+Δ) ve (Σ-Δ) ardışık ölçüldüğü için Σ aynı değildir. Ancak kaynak kararlıysa (CW) ve LO aynıysa, faz farkı korunur.
8. Vitis ve Yazılım Denetimi
8.1 Mevcut C Altyapısı
Var olan fonksiyonlar (kaynak koddan doğrulanmış):

Fonksiyon	Dosya	Görev
wifi_rf_capture_init()	wifi_rf_capture.c:16	Context, buffer, DMA doğrulama
wifi_rf_prepare_rx_only()	wifi_rf_capture.c:51	RX-only güvenlik kapısı, FDD/ENSM
wifi_rf_capture_channel()	wifi_rf_capture.c:110	LO tuning, gain, DMA capture, metrik
wifi_rf_analyze_block()	wifi_rf_metrics.c:26	Mean power, clip count, peak (zaman alanı)
wifi_rf_median_u64()	wifi_rf_metrics.c:59	Insertion-sort median
wifi_rf_power_cdbfs16()	wifi_rf_metrics.c:75	dBFS dönüşümü (10×log10)
wifi_rf_peak_cdbfs16()	wifi_rf_metrics.c:84	Peak dBFS (20×log10)
wifi_rf_delta()	wifi_rf_metrics.c:92	Baseline-active farkı
wifi_rf_classify()	wifi_rf_metrics.c:109	Aktivite kararı (3 gösterge, ≥2)
wifi_rf_test_run()	wifi_rf_test.c	Wi-Fi kanal tarama testi
Var olmayan fonksiyonlar (planda referans verilen ancak henüz yazılmamış):

pl_fft_control.c / pl_fft_control.h — PL FFT AXI-Lite sürücüsü
Herhangi bir PL register read/write kodu
Python FFT referans modeli (dosya yok)
CRC-32/ISO-HDLC implementasyonu (C tarafında)
8.2 Build Sistemi
Build flag: WIFI_RF_TEST tanımlı → DMA örneği yerine wifi_rf_test_run() çağrılır
Vitis build: Build-Axu4evAd9364App.tcl XSCT script'i ile
Release build: Build-Axu4evAd9364App.ps1 (PowerShell wrapper)
Platform: fmcomms2_axu4ev_hw (Vitis platform)
Domain: standalone_domain (bare-metal)
8.3 DMA Referans Yolu
adc_buffer: uint16_t[ADC_BUFFER_SAMPLES * ADC_CHANNELS] — 1024-byte aligned
DMAC transfer: tek seferde sizeof(adc_buffer) byte, CYCLIC=NO
Tamamlanma: axi_dmac_transfer_wait_completion(rx_dmac, 500) — 500 ms timeout
Cache: Xil_DCacheInvalidateRange transfer öncesi ve sonrası
8.4 Readback ve Metadata
Şu an readback yapılanlar:

ENSM mode: ad9361_get_en_state_machine_mode() ✓
RX RF gain: ad9361_get_rx_rf_gain() ✓
RX RF port: ad9361_get_rx_rf_port_input() ✓
RSSI: ad9361_get_rx_rssi() ✓
Şu an readback yapılmayanlar (plan gerektiriyor):

Sample rate: ad9361_get_rx_sampling_freq() — IIO callback'te var ama test modunda çağrılmıyor
RF bandwidth: API'de ad9361_get_rx_rf_bandwidth() var — test modunda çağrılmıyor
LO frequency: API'de var — test modunda çağrılmıyor
8.5 PL Kontrol Entegrasyonu
Henüz hiçbir PL kontrol kodu yazılmamıştır. Nihai plan pl_fft_control.c/h oluşturulmasını önerir. Gerekli register sürücüsü:

AXI-Lite base address okuma (xparameters.h'ten)
CONTROL, STATUS, FRAME_ID, PEAK_* register'ları
Timeout mekanizması (DONE polling, maksimum bekleme)
Hata yönetimi: overflow, frame_error, fft_error, config_error bit'leri
9. Aritmetik IP Denetimi
9.1 Magnitude-Square
Giriş: Signed 16-bit I + signed 16-bit Q (FFT çıkışı)
İşlem: I² + Q²
16×16 signed çarpım → 32-bit signed
İki 32-bit toplam → 33-bit unsigned (overflow yok; max: 2 × (2^15)² = 2 × 2^30 = 2^31)
Çıkış formatı: 33-bit unsigned integer, binary point yok
PL kaynak: 2 DSP48E2 (MULT18×18) + 1 CARRY8 (toplama)
Risk: Sıfır (33-bit yeterli)
9.2 Power Ratio
Nihai plan kararı: İlk Candidate'da PS/Python tarafında hesaplanacak
Monopulse tasarımı: Kompleks Δ/Σ oranı PL'de olabilir
PA / (PB + epsilon):
Pay ve payda unsigned 33-bit → 64-bit yazılım değişkenine genişletilir
epsilon: Payda sıfır veya çok küçük olduğunda bölme hatasını önler
denominator_threshold: Payda bu değerin altındaysa denominator_small flag'i set edilir, sonuç saturate edilmez
Önerilen epsilon: PB full-scale değerinin ~1/1000'ü. 33-bit için 2^33 / 1000 ≈ 8.6×10^6. Register'da konfigüre edilebilir olmalı.
PS vs PL divider:
PS: 64-bit integer division, μs-level latency, kaynak kullanımı yok
PL Divider Generator IP: Radix-2, ~33 cycle latency, ~500 LUT + ~300 FF
PL Reciprocal + multiplier: 1 DSP + LUT, pipeline'lı
İlk sürüm PS yeterlidir; sürekli streaming'de PL divider gerekebilir
9.3 Kompleks Bölme
A / B = A × conj(B) / (|B|² + epsilon)
Faz sonucu yalnızca koherent kaynaklarda anlamlıdır.
Ardışık A/B ölçümlerinde: RF kaynağı kararlı değilse (örneğin Wi-Fi paketleri), A ve B farklı anlarda alınmıştır → faz farkı rastgeledir. Magnitude/power ratio güvenilirdir; kompleks ratio değildir.
Monopulse Σ/Δ için: CW kaynakla faz anlamlıdır; Wi-Fi/ortam RF ile değildir.
9.4 Fixed-Point Overflow Riskleri
Aşama	Giriş formatı	Çıkış formatı	Overflow riski
Window multiply	16-bit signed × 16-bit unsigned	32-bit → 16-bit (scale+sat)	Saturation'da (clipping)
FFT	16-bit signed I/Q	16-bit signed I/Q (scaled)	FFT event overflow
Magnitude-square	16-bit signed I/Q	33-bit unsigned	Yok
Spectrum store	33-bit unsigned	64-bit word	Yok
ADD/SUB	33-bit unsigned	34-bit unsigned	SUB'da underflow (negatif)
MUL	33-bit unsigned × 33-bit unsigned	66-bit → saturation	64-bit word'e sığdırma
DIV	33-bit / 33-bit	N-bit quotient	Payda sıfır/küçük
10. Kaynak Bütçesi
Uyarı: Tüm değerler tahminidir. Kesin sentez sonucu yoktur.

Bileşen	Tahmini BRAM36K	Tahmini URAM	Tahmini DSP48E	Risk
Capture buffer (2048×32-bit)	2	0	0	Düşük
Hann ROM (2048×16-bit)	1	0	0	Düşük
Window multiplier	0	0	1	Düşük
FFT IP (2048, Pipelined)	8-10	0	20-30	Orta
Spectrum-A buffer (2048×64-bit)	4	0	0	Düşük
Magnitude-square (2×MULT+ADD)	0	0	2	Düşük
AXI BRAM Controller	0	0	0	Düşük
AXI-Lite register bank	0	0	0	Düşük
CDC FIFO (gerekirse)	1	0	0	Düşük
Toplam (tahmini)	16-18	0	23-33	Düşük
XCZU4EV toplam	128	48	240	—
Kullanım yüzdesi	%13-14	%0	%10-14	Düşük
Eklemeler (sonraki fazlar):

Bileşen	BRAM36K	DSP48E
Spectrum-B buffer (ping-pong)	+4	0
Divider Generator (Radix-2, 33-bit)	0	0 (LUT only)
Kompleks divider (Recip+2×MULT)	0-1	+3
Result DMAC (AXI DMA)	0	0
Sürekli streaming (ping-pong capture)	+2	0
8192 nokta FFT'de: BRAM ~30-35, DSP ~40-50. URAM gerekebilir.
65536 nokta FFT: İlk sürüm kapsamı dışı; URAM zorunlu, DSP >100.

11. Plan Üzerindeki Önerilen Değişiklikler
11.1 Eklenmesi Gerekenler
Monopulse tasarımı ayrı bir "Faz 5B — Monopulse Genişletmesi" olarak eklenmeli. Mevcut nihai planın Faz 5'i (A/B switch ve power ratio) tamamlandıktan sonra, monopulse donanımı hazırsa başlatılmalı.

Python FFT referans modeli için dosya yolu ve format spesifikasyonu. PROJECT/verification/fft/model/ altında Python referans modelinin adı, API'si ve vektör formatı tanımlanmalı.

CRC-32 C implementasyonu. wifi_rf_capture.c içinde veya ayrı bir frame_crc.c olarak eklenmeli. Poly: 0x04C11DB7, reflected: 0xEDB88320, init/xorout: 0xFFFFFFFF.

ILA trigger ve capture konfigürasyonu dokümanı. Faz 1'de hangi sinyallerin, hangi derinlikte, hangi trigger koşuluyla prob edileceği yazılmalı.

61.44 MSPS için ayrı kabul kriterleri matrisi. Profil B'nin hangi testleri, hangi limitlerle geçmesi gerektiği netleştirilmeli.

11.2 Çıkarılması Gerekenler
"Hotspot/ortam RF testi" nicel kabul kriterlerinden çıkarılmalı (nihai planda zaten böyle — Kabul kriteri #18). Monopulse tasarımında da aynı politika korunmalı.

"Continuous streaming" Faz 2 kapsamından çıkarılmalı — Faz 6'ya ertelenmeli (nihai planda zaten böyle).

11.3 Ertelenmesi Gerekenler
Kompleks bölme (PL divider + complex ratio): Power ratio PS'de doğrulandıktan ve sürekli streaming ihtiyacı ölçüldükten sonra.
61.44 MSPS profili: Profil A kart kabulünden sonra.
Monopulse açı kalibrasyonu: Anekoik oda erişimi olmadan yapılamaz — Faz 5B sonrası.
Result DMAC: İlk sürüm AXI BRAM yeterlidir; yüksek hızlı sürekli spektrum akışı gerekirse.
11.4 Daha Erken Yapılması Gerekenler
Paket 1 — Temiz build kapısı hemen yapılmalı. Build zincirinin sağlam olduğu kanıtlanmadan yeni IP eklemek risklidir.
GPIO/voltaj elektriksel incelemesi Faz 5'ten önceye çekilmeli; donanım siparişi ve level shifter tasarımı zaman alır.
Python bit-true FFT modeli Paket 3 (deterministik capture) ile paralel yazılmalı, Paket 4'te kullanıma hazır olmalı.
12. Önerilen Uygulama Sırası
Nihai plandaki 8 paket yapısı büyük ölçüde doğrudur. Monopulse genişletmesi için ek faz önerisi:


Faz -1: Temiz build kapısı (Paket 1)
Faz 0:  Gereksinim ve RF donanım kararı (Paket 6'nın ilk yarısı)
Faz 1:  ILA veri yolu denetimi (Paket 2)
Faz 2:  Tek girişli capture + FFT + magnitude-square (Paket 3-4)
Faz 3:  DMA/PL/Python çapraz doğrulama (Paket 5)
Faz 4:  Aritmetik IP (ADD/SUB/MUL) ve PA/PB buffer (Paket 7'nin PL kısmı)
Faz 5A: Harici A/B RF switch + power ratio (Paket 7'nin RF kısmı)
Faz 5B: [YENİ] Monopulse genişletmesi:
        - HMC936A faz kodu karakterizasyonu
        - 4-durum FSM (Σ+ΔAZ, Σ-ΔAZ, Σ+ΔEL, Σ-ΔEL)
        - Kompleks kalibrasyon katsayıları
        - Σ/Δ rekonstrüksiyonu
        - Kompleks bölme
        - Açı LUT ve kalibrasyon
Faz 6:  Performans (ping-pong, 61.44 MSPS, PL divider)
Faz 7:  Release kapanışı (Paket 8)
Her faz için kabul kapısı (gate):

Faz -1: Temiz build SHA-256 match + DRC sıfır Error
Faz 1: ILA verisi + I/Q format dokümanı
Faz 2: Bit-doğru Python karşılaştırması (0 LSB fark)
Faz 3: Tek CRC eşleşmesi + DMA regresyonu
Faz 5A: 10 tekrarda power ratio std ≤0.5 dB
Faz 5B: CW kaynakla faz karakterizasyonu + port swap testi
Faz 7: Tüm Vivado/DMA/RF kabul kriterleri
13. Test Matrisi
#	Test	Faz	Kaynak	Beklenen sonuç	Durum
1	I/Q format testi	1	ILA	I/Q sırası, 12→16 bit mapping, valid/enable timing	Planlandı
2	Bilinen ton testi (bin merkezli)	2	Dijital vektör	Tam bin'de peak, bin index doğru	Planlandı
3	Bilinen ton testi (bin dışı)	2	Dijital vektör	Leakage pattern doğru, en yakın bin'de max	Planlandı
4	FFT scaling testi	2	Dijital vektör	16-bit I/Q output bit-doğru, 0 LSB fark	Planlandı
5	Saturation/clipping testi	2	Dijital vektör (sınır değerleri)	Overflow flag set, saturate değerleri doğru	Planlandı
6	Hann pencere testi	2	Dijital vektör + ROM	Coherent gain düzeltmesi doğru, leakage azalmış	Planlandı
7	FIFO overflow testi	3	Kart + DMA	Sıfır overflow, frame_error=0	Planlandı
8	Backpressure testi	3	Kart + DMA	DMA regresyonu geçer, DMA sample kaybı yok	Planlandı
9	CRC-32 frame eşleşme testi	3	Kart	Tek CRC eşleşmesi, aynı 2048 örnek	Planlandı
10	30.72 MSPS kart testi	3	Kart + CW	Peak beklenen bin'de, DMA/PL eşleşir	Planlandı
11	61.44 MSPS kart testi	6	Kart + CW	Sıfır overflow, FIFO occupancy < %80	Ertelendi
12	FDD modu testi	3	Kart	ENSM readback FDD, capture başarılı	Planlandı
13	MGC A/B testi	5A	Kart + 2 seviye	Aynı gain, power ratio tutarlı	Planlandı
14	Switch settling testi	5A	Kart + CW + scope	Settling sonrası örnekler kararlı	Planlandı
15	Power ratio testi (PA/PB)	5A	Kart + bilinen attenuator	Beklenen dB farkı ±1 dB	Planlandı
16	Port swap testi	5A	Kart	A/B etiketi port'la değişir, ratio terslenir	Planlandı
17	Golden rollback testi	Tüm	Kart	Eski Golden başlatılabilir, DMA çalışır	Planlandı
18	Monopulse Σ/Δ testi	5B	Kart + CW + phase shifter	Σ rekonstrüksiyonu doğru, Δ/Σ oranı tutarlı	Yeni
19	HMC936 faz kodu testi	5B	Kart + CW + VNA	64 kod için faz farkı ölçülür, LUT oluşturulur	Yeni
20	Anekoik oda açı kalibrasyonu	5B+	Kart + monopulse anten	Açı vs Δ/Σ eğrisi, LUT/curve fit	Yeni (donanım bağımlı)
14. Son Karar
Karar: Mimari düzeltme gerekiyor (kapsam netleştirmesi)

Gerekçe:

Nihai plan (2026-07-20) ile monopulse tasarımı (2026-07-21) arasında kapsam uyuşmazlığı vardır. Nihai plan 2-durumlu A/B SPDT switch + power ratio hedeflerken, monopulse tasarımı 4-durumlu Σ/Δ/EL zinciri + kompleks bölme + faz karakterizasyonu + açı kalibrasyonu eklemektedir. Bu genişleme PL kaynak kullanımını, doğrulama matrisini ve donanım bağımlılıklarını önemli ölçüde artırır.

Nihai planın ilk iki minimum sürümü (tek girişli FFT + A/B power ratio) uygulanabilirdir — mevcut kaynak, saat ve DMA altyapısıyla. Bu sürümler monopolse RF donanımından bağımsızdır ve hemen başlatılabilir.

Monopulse genişletmesi ayrı bir faz olarak planlanmalıdır. Faz 5A (A/B switch) tamamlandıktan sonra, monopulse donanımı hazırsa Faz 5B başlatılabilir. Bu, ilerlemeyi monopolse donanım tedarikine bağlamaz.

Üç kritik kapı geçilmeden RTL yazılmamalıdır:

Temiz Vivado build yeniden üretilebilirliği (Paket 1)
I/Q format ILA doğrulaması (Paket 2)
Python FFT bit-true modelinin hazır olması (Paket 4 öncesi)
Phase shifter frekans sınırlaması (1.2-1.4 GHz) ürün hedefini belirler. 2.4 GHz nihai hedefse HMC936A uygun değildir; farklı phase shifter veya wideband alternatif gerekecektir.

Özetle: Proje sağlam bir temele (çalışan DMA, doğrulanmış AD9364 init, immutable Golden) sahiptir. PL FFT shadow path için mimari kararlar büyük ölçüde doğrudur. Monopulse genişletmesi değerli bir ürün vizyonudur ancak ayrı bir faz olarak, kendi donanım ve doğrulama kapılarıyla planlanmalıdır.

15. Salt-Okunur Denetim Doğrulaması
Soru	Cevap
Herhangi bir dosya değiştirildi mi?	Hayır. Hiçbir dosya yazılmadı, düzenlenmedi veya silinmedi.
Herhangi bir dosya oluşturuldu mu?	Hayır. Hiçbir yeni dosya oluşturulmadı.
Herhangi bir build veya generation çalıştırıldı mı?	Hayır. Vivado, Vitis, XSCT veya başka bir build aracı çalıştırılmadı.
İnceleme sırasında repository durumu değişti mi?	Kontrol edilecek.
Başlangıç ve bitiş commit hash'leri aynı mı?	Kontrol edilecek.
