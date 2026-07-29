# Nihai Geliştirme Planı
## AXU4EVB-P + AD9364 + RF Switch + FPGA FFT ve Aritmetik IP

> **Uygulayıcı notu:** Bu plan paket paket yürütülmelidir; her paket için test-first çalışma, bağımsız doğrulama ve commit zorunludur.

> **Uygulama sözleşmesi:** Bu belge karar kapıları tamamlandıkça uygulanacaktır. Golden sürüm değiştirilmeyecek; her faz ayrı Candidate çıktısı, otomatik doğrulama ve kart kabul kaydı üretmeden sonraki faza geçmeyecektir.

**Güncel uygulanabilirlik kararı (2026-07-20):** 30,72 MSPS, tek AD9364 RX girişi ve tek zaman-paylaşımlı 2048 nokta finite-frame FFT Candidate mevcut kaynak ve saat bütçesiyle uygulanabilirdir. Bağlayıcı ürün mimarisi, analog ön uçta sırayla üretilen `Σ+ΔAZ`, `Σ-ΔAZ`, `Σ+ΔEL`, `Σ-ΔEL` durumlarıdır. İki dijital RX kanalının eşzamanlı okunması AD9364 ile mümkün değildir. 61,44 MSPS profili ayrı kanıt kapısına bağlıdır; telefon hotspot'u zorunlu test kaynağı değildir.

> **2026-07-20 bağlayıcı mimari düzeltmesi:** `PROJECT/designs/2026-07-20-axu4ev-ad9364-single-channel-monopulse-design.md` bu planın RF switch, frame sıralaması, peak/band-power, oran ve kalibrasyon ayrıntıları için güncel kaynak-doğrusudur. Bu belgenin eski bölümlerindeki “RF kaynağı/anten A-B seçimi”, `PA/PB` ve “Spectrum-A/B” ifadeleri geçmiş tasarım aşamasını gösterir; uygulamada sırasıyla `ΔAZ/ΔEL + 0°/180°`, dört `P_*` spektrumu ve ortak peak sözleşmesi kullanılacaktır. Eski A/B ifadeleri yeni tasarımla çeliştiğinde uygulanmayacaktır.

> **2026-07-21 inceleme uzlaştırması:** İki teknik inceleme raporu güncel dala göre değerlendirildi. Bağlayıcı PL FFT alt-tasarımı `docs/superpowers/specs/2026-07-21-axu4ev-ad9364-pl-fft-spectrum-design.md` dosyasındadır. İlk doğrulama tek-kare, ikinci alt aşama atomik ping-pong bankalı sürekli FFT frame modudur. Tam 2048-bin güç spektrumu AXI BRAM'den; peak bin/power ve diagnostik Re/Im AXI-Lite status'tan okunur. Ardışık S0-S3 frame'lerinden kompleks `Δ/Σ` ürün sonucu çıkarılmaz; ilk ürün güç tabanlı normalize AZ/EL oranıdır. `ZX80-DR230-S+` DC-3 GHz'dir. HMC936A BDC sonrası 1.2-1.4 GHz IF yolundadır; AD9364 LO, sabit 1.3 GHz varsayımıyla değil ölçülen IF merkezine göre ayarlanır.

## 1. Projenin hedefi

Projenin hedefi, AXU4EVB-P ve AD9364 tabanlı RF platformuna FPGA içinde çalışan aşağıdaki işleme zincirini eklemektir:

- Tek AD9364 RX'e analog olarak yönlendirilmiş Σ/Δ durumlarından kontrollü örnek alma
- I/Q frame yakalama
- Pencereleme
- FFT
- Güç spektrumu hesaplama
- Tam 2048-bin güç spektrumu, peak ve dört-durum ortak taşıyıcı karşılaştırması
- Güç tabanlı normalize AZ/EL hata oranı; kompleks frame-to-frame oran kapsam dışıdır
- Spektrum sonuçlarının AXI BRAM veya ileride Result DMAC ile aktarılması; AXI-Lite'ın yalnız kontrol/status için kullanılması

Gerçek zamanlı örnek işleme PL içinde yapılacak; PS/Vitis yalnız initialization, konfigürasyon, test ve sonuç okuma görevlerini üstlenecektir.

Mevcut `fmcomms2_axu4ev.xpr` projesi referans alınacak ancak doğrudan Golden sürümün üzerinde çalışılmayacaktır. Yeni PL tasarımı ayrı bir Vivado Candidate dalında geliştirilecektir.

İlk doğrulama hedefi tetiklemeli **finite-frame** işleme ve aynı frame üzerinde tekrarlanabilir sonuçtur. Kullanıcının istediği sürekli FFT frame modu aynı arayüzde desteklenecek, ancak yalnız tek-kare kabulünden sonra ping-pong spectrum bankası, atomik ownership ve throughput/overrun testleriyle etkinleştirilecektir. Sürekli host/DDR spectrum streaming ayrı performans fazıdır.

---

## 2. Ana mimari karar

Birincil hedef mimari:

```text
RF Kaynağı A ─┐
              ├── Harici SPDT RF Switch ── RXB ── AD9364
RF Kaynağı B ─┘
                    ▲
                    │
             FPGA PL switch_ctrl
```

AD9364'ün RXB girişi sabit kullanılacaktır. Harici RF switch doğrudan PL tarafından kontrol edilecektir.

Bu seçim şu nedenlerle önerilir:

- Switch zamanlaması yazılımdan bağımsız olur.
- Settling ve discard süreleri clock-cycle seviyesinde kontrol edilir.
- AD9364 ENSM durumu A/B geçişlerinde değiştirilmez.
- RXA/RXB register değiştirme gecikmesi veri yolundan ayrılır.
- Birim sorumlusunun harici RF switch gereksinimini karşılar.

AD9364'ün dahili RXA/RXB seçimi, harici switch hazır olmadan önce fonksiyonel prototip veya yedek yöntem olarak kullanılabilir. Dahili seçim SPI üzerinden PS/Vitis tarafından yapılır ve PL FSM'in doğrudan bir parçası sayılmaz.

Her iki yöntemde de A ve B eşzamanlı alınmaz.

---

## 3. Vitis ve Vivado görev ayrımı

### Vitis / PS görevleri

- AD9364 initialization
- LO frekansı
- Örnekleme hızı
- RF bant genişliği
- MGC/AGC seçimi
- Sabit RX gain ayarı
- FDD/TDD/ENSM readback kontrolü
- TX'in devre dışı veya maksimum attenuation'da tutulması
- PL IP register konfigürasyonu
- Test başlatma
- Sonuç ve status okuma
- Mevcut DMA/C metrikleriyle karşılaştırma

### Vivado / PL görevleri

- Harici RF switch kontrolü
- Settling ve discard sayaçları
- I/Q frame capture
- Clock-domain crossing
- Pencereleme
- FFT
- Magnitude-square
- A/B spectrum buffer
- Magnitude-square, güç spektrumu toplamı/farkı ve PA/PB sonuç üretimi
- Overflow ve clipping takibi
- Spektrum için AXI BRAM/ileride Result DMAC; scalar sonuç ve status için AXI-Lite
- İşlem tamamlandı interrupt'ı

PS hiçbir örnek üzerinde gerçek zamanlı olarak çalışmayacaktır. PS yalnız kontrol ve doğrulama düzlemidir.

---

## 4. Gerçek veri yolunun önce doğrulanması

Kaynak ve routed rapor incelemesinde aşağıdaki mevcut yapı doğrulanmıştır:

- `axi_ad9361` çıkışında dört adet 16-bit `I0/Q0/I1/Q1` kanalı ile ayrı `enable/valid` sinyalleri bulunur.
- `util_ad9361_adc_fifo` AD9364 `l_clk` alanından `util_ad9361_divclk/clk_out` alanına mevcut CDC'yi yapar.
- `util_ad9361_adc_pack` dört kanalı paketler; RX DMAC kaynak genişliği 64 bittir.
- Mevcut `axi_ad9361_adc_dma` non-cyclic ve scatter-gather etkin yapıdadır.
- Mevcut DMA zinciri çalışan Golden davranışıdır ve Candidate tarafından backpressure'a maruz bırakılamaz.

**Seçilen ilk tap noktası:** `util_ad9361_adc_fifo` çıkışı ile `util_ad9361_adc_pack` girişi arasındaki bölünmüş-clock alanıdır. Böylece ADI'nin mevcut CDC bloğu yeniden kullanılır. Ham `axi_ad9361` çıkışından tap ancak ILA ölçümü bu tercihi zorunlu kılarsa ve ayrı CDC tasarımı onaylanırsa kullanılabilir.

FFT eklenmeden önce aktif Block Design üzerinde şu bilgiler ILA ve DMA örneğiyle tamamlanacaktır:

1. `axi_ad9361` RX çıkış pinleri
2. Paketleme/cpack bloğu
3. RX DMAC giriş arayüzü
4. Saat sinyalleri
5. Veri genişlikleri
6. I/Q sırası
7. Valid/enable davranışı
8. 12-bit örneklerin 16-bit alana nasıl yerleştirildiği
9. Mevcut DMA'ya giden örnek sıralaması

ILA öncelikle aşağıdaki seçilen noktaya yerleştirilecektir:

```text
util_ad9361_adc_fifo çıkışı / util_ad9361_adc_pack girişi
```

Gerekirse yalnız teşhis amacıyla `axi_ad9361` çıkışı veya DMAC kaynak arayüzü de prob edilir.

Bu inceleme tamamlanmadan `[31:16]=Q, [15:0]=I` gibi sabit bir format kabul edilmeyecektir.

Doğrulanan arayüze göre `adc_stream_bridge` geliştirilecektir.

Görevleri:

- ADI veri formatını standart iç formata çevirmek
- Signed I/Q standardizasyonu
- `sample_valid`
- Frame sample counter
- A/B source tag
- Frame başlangıcı ve sonu
- Overflow/drop işareti
- Gerekirse AXI4-Stream `TVALID`, `TREADY`, `TLAST` üretimi

MVP `adc_stream_bridge` port ve davranış sözleşmesi:

```text
ADI-native input (util_ad9361_divclk domain)
  dout_data_0[15:0]   = I0 adayı
  dout_data_1[15:0]   = Q0 adayı
  dout_valid_0
  dout_enable_0
  dout_enable_1

AXI4-Stream output (100 MHz sys_cpu_clk domain)
  M_AXIS_TDATA[15:0]  = I0
  M_AXIS_TDATA[31:16] = Q0
  M_AXIS_TVALID
  M_AXIS_TREADY
  M_AXIS_TLAST         = sample index 2047 transferinde 1
```

`dout_data_2/3` (`I1/Q1` adayı) AD9364 MVP FFT yolunda kullanılmayacaktır. AD9364 yazılım override'ı iki ADC channel bildirse de fiziksel packed sıra ve kullanılmayan kanal davranışı ILA + DMA dump ile doğrulanmadan kanal isimleri kesin kabul edilmeyecektir. Ölçüm beklenen sırayı doğrulamazsa yukarıdaki TDATA eşlemesi belge ve RTL birlikte değiştirilmeden Paket 3 başlamaz.

Tek ve değişmez bit-seviye convention:

- Mantıksal kompleks sample tuple'ı `(I0,Q0)` sırasındadır.
- 32-bit RAM/AXIS word Verilog concat olarak `{Q0[15:0], I0[15:0]}` biçimindedir.
- Dolayısıyla `word[15:0]=I0`, `word[31:16]=Q0` olur.
- FFT `XN_RE` girişi düşük 16 bitten I0, `XN_IM` girişi yüksek 16 bitten Q0 alır.
- CRC byte sırası `I_lo, I_hi, Q_lo, Q_hi`; DMA/Python unpack aynı sırayı kullanır.
- Bu convention frame RAM, AXIS, CRC, FFT wrapper, Vitis ve Python için ortaktır; ayrı modülde byte swap yasaktır.

Bridge iki ayrı işi ayıracaktır:

1. **Capture:** İlk geçerli ve iki kanal da enabled örnekten başlayarak yalnız `dout_valid_0 && dout_enable_0 && dout_enable_1` olduğunda 2048 adet `{Q0,I0}` word'ünü dual-clock frame RAM'e yazar. Capture sırasında FFT hazır olma durumu örnek kabulünü etkileyemez.
2. **Replay:** Frame tamamlandıktan ve CDC handshake geçtikten sonra RAM'i AXI4-Stream olarak FFT'ye oynatır. Read pointer yalnız `TVALID && TREADY` olduğunda ilerler; `TREADY=0` iken `TDATA`, `TVALID` ve `TLAST` sabit tutulur.

Bu store-and-forward sözleşmesi nedeniyle FFT backpressure'ı canlı ADC veya mevcut DMAC yoluna yayılmaz. Tek-buffer MVP'de capture ve replay aynı anda yapılmaz; yeni capture isteği buffer serbest değilken `busy/config_error` ile reddedilir.

Shadow yol sözleşmesi:

- FFT tarafındaki `TREADY`, busy veya buffer-full durumu mevcut pack/DMAC yolunu durduramaz.
- Finite-frame capture kapalıyken gelen örnekler bilinçli olarak yok sayılır; bu durum DMA sample drop değildir.
- Capture açıkken kabul edilmesi gereken bir örneğin kaybı `dropped_samples` ve `frame_error` ile raporlanır.
- Her PL capture monoton artan `frame_id`, ilk örnek işareti, kesin 2048 kompleks örnek sayısı, ilk 8 kompleks örnek imzası ve bütün ham frame üzerinde CRC-32 taşır.

---

## 5. Önerilen ilk PL veri yolu

İlk sürüm sürekli streaming yerine finite-frame mimarisi kullanacaktır:

```text
AD9364
  │
  ▼
axi_ad9361
  │
  ▼
Mevcut util_ad9361_adc_fifo (CDC)
  │
  ├──────────── Mevcut pack + RX DMAC → DDR
  │                                      │
  │                                      ▼
  │                              C referans/metrik motoru
  ▼
adc_stream_bridge
  │
  ▼
2048-sample Capture Buffer
  │
  ▼
Window
  │
  ▼
Vivado FFT IP
  │
  ▼
Magnitude² / Complex Output
  │
  ▼
A Spectrum Buffer
  │
  ▼
Arithmetic / Comparison
  │
  ▼
AXI BRAM Result Buffer
```

Mevcut DDR/DMA yolu başlangıçta kaldırılmayacaktır. PL FFT yolu mevcut yolun yanında bir **shadow processing path** olarak çalışacaktır.

Bu sayede aynı `frame_id` ve aynı 2048 kompleks örnek üzerinde:

- DMA örnekleri
- C metrikleri
- PL FFT sonucu
- Python golden FFT sonucu

karşılaştırılabilecektir.

Yalnız “aynı RF koşulu” altında farklı zamanlarda alınmış iki frame bit-doğru FFT kabulü için kullanılmayacaktır. Mevcut DMAC akışı `frame_id` taşımadığı için canlı korelasyon şu somut sözleşmeyle yapılacaktır:

1. Vitis önce en az PL frame'inden daha uzun RX DMA transferini başlatır ve DMA'nın aktif olduğunu readback ile doğrular.
2. Vitis PL capture'ı arm/start eder; PL ilk geçerli örnekten itibaren tam 2048 kompleks örnek alır.
3. PL `frame_id`, ilk 8 kompleks örnek imzası, `sample_count=2048` ve ham I/Q sırası üzerinde CRC-32 yayınlar.
4. Host/Vitis DMA buffer içinde 8-örnek imzayı arar; aday 2048-örnek alt dizinin CRC-32 değerini PL CRC-32 ile karşılaştırır.
5. Tek ve tam CRC eşleşmesi bulunursa aynı örnek kimliği kanıtlanır ve FFT bin karşılaştırması yapılır. Sıfır veya birden fazla eşleşme test hatasıdır; yeni capture alınır.

Deterministik replay yalnız FFT aritmetiğinin bit-true kabulüdür; canlı DMA-shadow eşzamanlılık kabulü sayılmaz. Canlı test yukarıdaki imza+CRC korelasyonunu geçmelidir.

---

## 6. Frame ve bellek mimarisi

İlk sürüm:

- FFT uzunluğu: 2048
- Ham örnek: signed 16-bit I + signed 16-bit Q
- Window: rectangular ve Hann
- Tek FFT core
- Tek yeniden kullanılabilir capture buffer
- Bir adet Spectrum-A buffer
- Spectrum-B streaming karşılaştırması
- Her frame için `frame_id`, source tag, sample count, clipping, overflow ve timestamp/cycle metadata'sı

Ölçüm sırası:

```text
A seç
→ settle
→ discard
→ A frame capture
→ FFT-A
→ Spectrum-A belleğe yaz

B seç
→ settle
→ discard
→ B frame capture
→ FFT-B
→ FFT-B çıktıkça Spectrum-A ile işlem yap
→ sonucu yaz
```

Bu tasarımda aynı anda iki ham frame ve iki FFT frame saklanmaz.

2048 noktalı, 16-bit I + 16-bit Q ham kompleks frame payload'u tam olarak 65.536 bit, yani 8 KiB'dir; ek metadata ve RAM primitive yuvarlaması ayrıca bütçelenir. Bir spectrum bankası bin başına 64-bit word ile 16 KiB logical payload kullanır; bunun 33 biti magnitude-square, üst bitleri sıfırdır. Bu genişlik/derinlik yaklaşık dört BRAM36 gerektirir; sürekli modun iki bankalı ping-pong spectrum belleği yaklaşık sekiz BRAM36 olarak bütçelenir. Capture RAM, Hann ROM ve FFT iç belleği buna dahil değildir. Mevcut routed tasarımın BRAM kullanımı 4/128 olduğundan başlangıç marjı vardır; bağlayıcı sayı sentez/implementation utilization raporudur.

8192 veya daha uzun FFT'lerde sentez sonrası BRAM/URAM bütçesi değerlendirilir. 65.536 nokta ilk sürüm kapsamına alınmaz. Kesintisiz frame işleme istenirse tek buffer yeterli sayılmayacak; ping-pong capture buffer ve ölçülmüş throughput ayrı kabul kapısı olacaktır.

---

## 7. Clock-domain crossing

AD9364 veri saatinin örnekleme profiline göre değişebilmesi nedeniyle RF capture alanı ve processing alanı mantıksal olarak ayrılacaktır. İlk tap mevcut `util_ad9361_adc_fifo` çıkışından alınacağı için AD9364 saatinden bölünmüş veri alanına geçişte ikinci bir asenkron FIFO otomatik olarak eklenmeyecektir.

```text
AD9364/ADC clock domain
→ mevcut util_ad9361_adc_fifo
→ util_ad9361_divclk veri alanı
→ gerekirse XPM FIFO Async veya dual-clock BRAM
→ 100 MHz processing clock domain
```

İlk Candidate mevcut 100 MHz `sys_cpu_clk` processing clock'unu kullanacaktır. 150 MHz ancak 100 MHz'te ölçülen throughput gereksinimi karşılanmazsa ve yeni clock için CDC/timing raporu temizse değerlendirilecektir. Mevcut routed Golden WNS `+0,144 ns`, WHS `+0,010 ns` olduğundan yeni IP sonrası timing kapanışı yeniden kanıtlanacaktır.

MVP CDC uygulaması:

- Frame RAM write portu ve capture counter `util_ad9361_divclk/clk_out` domain'inde çalışır.
- Frame RAM read portu, AXI4-Stream replay ve FFT 100 MHz `sys_cpu_clk` domain'inde çalışır.
- AXI-Lite control domain'indeki `start`, `abort`, `soft_reset`, `frame_length`, `source_tag`, `discard_samples`, `sample_rate_id` ve `reset_epoch` alanları tek bir bundled command mailbox oluşturur. Mailbox `XPM_CDC_HANDSHAKE` ile capture domain'ine atomik taşınır ve kaynak payload destination ack gelene kadar sabit kalır.
- Command decoder opcode'a göre kabul uygular ve sonucu aynı command sequence numarasıyla ack/status olarak geri döner:
  - `START_CONFIG`: yalnız `IDLE && cdc_ready && epoch_valid && command.reset_epoch==local_epoch` iken kabul edilir; config payload bu anda atomik latch edilir. Busy iken reddedilir.
  - `ABORT`: matching current epoch ile `CAPTURE/FRAME_READY/REPLAY` aktifken kabul edilir; capture ve processing tarafı aktif işi durdurur, frame'i `aborted` işaretler ve RAM valid durumunu temizler. Epoch geçersizse ABORT yerine `SOFT_RESET` gerekir.
  - `SOFT_RESET`: herhangi bir FSM durumunda ve eski epoch eşleşmesi aranmadan kabul edilir; iki domain aktif işi/buffer/mailbox durumunu temizler ve command payload'daki yeni `reset_epoch` değerini kurar.
- `frame_ready/frame_id/source_tag/sample_count/signature/CRC/error` metadata'sı ters yönde ikinci bundled-data request/ack handshake ile taşınır; kaynak metadata ack gelene kadar sabit tutulur.
- Processing tamamlandığında `buffer_release` aynı handshake ilkesiyle capture domain'ine döner.
- Capture logic aktif-high `util_ad9361_divclk_reset/peripheral_reset` ile; processing/AXI logic aktif-low `sys_cpu_resetn` ile resetlenir. FIFO çıkış arayüzünün `util_ad9361_divclk_reset/peripheral_aresetn` reset durumu da capture enable kapısına dahil edilir.
- Her donanım resetinde ilgili domain `epoch_valid=0`, buffer valid=0 ve handshake mailbox empty durumuna döner. Software artan 8-bit `reset_epoch` içeren `soft_reset` komutunu iki domain de ack etmeden `cdc_ready` set edilmez ve `start` reddedilir.
- Domainlerden biri reset veya epoch mismatch görürse `cdc_fault` sticky olur, iki tarafta frame/buffer validity temizlenir ve yeni `soft_reset` epoch handshake zorunlu hale gelir. Böylece tek taraflı reset eski frame'i replay edemez.
- `clk_out` gerçek frekansı ve reset polaritesi ILA/clock report ile ölçülüp metadata'ya yazılır; 1R1T bölme oranı ezberden kabul edilmez.

FIFO derinliği FFT uzunluğundan doğrudan türetilmeyecektir. Derinlik şu verilere göre hesaplanacaktır:

- Maksimum ADC veri hızı
- Capture burst uzunluğu
- Clock-domain oranı
- FFT'ye veri besleme gecikmesi
- En uzun downstream stall
- Güvenlik payı

İlk finite-frame tasarımda buffer dolduktan sonra capture kapanacak ve gelen diğer ADC örnekleri bilinçli olarak yok sayılacaktır. Bu durum bir hata değildir; finite capture sözleşmesidir.

Sürekli streaming daha sonraki fazdır.

---

## 8. Örnekleme profilleri

PL tasarımı tek örnekleme hızına sabitlenmeyecektir.

Profil A ilk Candidate'ın zorunlu profilidir. Profil B ilk Candidate kapsamına dahil değildir; Profil A kabulünden sonra ayrı bir deneysel kapı olarak test edilecektir:

```text
Profil A:
Fs = 30.72 MSPS
RF BW = 10 MHz hedefi; runtime readback bağlayıcıdır
FFT N = 2048
Bin = 15 kHz
Durum = mevcut Vitis/AD9364 akışında kart üzerinde doğrulanmış başlangıç profili

Profil B:
Fs = 61.44 MSPS
RF BW = yapılandırılabilir
FFT N = 2048
Bin = 30 kHz
Durum = AD9364 yeteneği dahilinde, ancak AXU4EV veri yolu/clock/timing/overflow açısından henüz doğrulanmamış deneysel profil
```

Vitis her ölçüm öncesinde gerçek:

- RX sample rate
- RF bandwidth
- LO
- gain
- ENSM mode

değerlerini readback ile okuyacak ve test metadata'sına yazacaktır.

Terminalde veya raporda `30.72MSPS`, `10MHz` ve LO değeri hardcoded başarılı ölçüm gibi basılmayacaktır. Vitis sırasıyla `ad9361_get_rx_sampling_freq()`, `ad9361_get_rx_rf_bandwidth()` ve `ad9361_get_rx_lo_freq()` dönüşlerini kontrol edecek; herhangi bir readback başarısızsa capture başlatılmayacaktır. Yazdırılan değerler ile PL'ye gönderilen `sample_rate_id/Fs` aynı readback snapshot'ından üretilecektir. Monopulse LO değeri gerçek BDC IF merkezine göre seçilir; HMC936A bandından doğrudan sabit değer türetilmez.

PL'ye `sample_rate_id` veya gerçek `Fs` register değeri gönderilecektir. FFT matematiğinin kendisi Fs'den bağımsızdır; ancak bin-frekans dönüşümü ve test raporu gerçek Fs'ye göre yapılacaktır.

2048 örneklik capture süresi Profil A'da yaklaşık 66,67 µs, Profil B'de yaklaşık 33,33 µs'dir. Sürekli çalışma talep edilirse capture, FFT ve sonuç yazma toplam throughput'u bu sürelerle karşılaştırılacaktır.

---

## 9. Gain ve AD9364 çalışma modu

Karşılaştırmalı ölçümlerde MGC kullanılacaktır.

Ölçüm politikası:

1. A ve B için kısa bir ön seviye ölçümü yap.
2. En güçlü girişin clip olmayacağı ortak gain değerini belirle.
3. MGC'ye geç.
4. A ve B ölçümlerinde aynı gain değerini kullan.
5. Her frame için peak ve clipping bilgisini kaydet.

FDD/TDD kontrolü:

- FDD ve independent-FDD güvenli durum olarak kabul edilir.
- FDD dışı kullanımda gerekirse RX durumuna geçilir.
- Her A/B switch değişiminde ENSM değiştirilmez.
- TX path açılmaz.
- TX attenuation her mevcut TX channel için 89.750 mdB'ye ayarlanır ve `ad9361_get_tx_attenuation()` ile doğrulanır.
- AXI DAC source tüm kanallarda `AXI_DAC_DATA_SEL_ZERO` yapılır; mevcut örnek uygulamadaki DDS seçimi RX-only Candidate için kabul edilmez.
- TX DDS tone scale/frequency ayarları sıfır kaynak seçiminin yerine güvenlik kanıtı sayılmaz.
- ENSM readback ve gain readback test kaydına eklenir.

Bu üç TX güvenlik kontrolünden herhangi biri başarısızsa RF capture başlatılmaz ve UART `TX_SAFE: FAIL` raporlar.

Fail-safe initialization sırası:

1. `ad9361_init()` çağrısından önce `default_init_param.tx_attenuation_mdB = 89750` ayarlanır; böylece FDD başlatılırken TX maksimum attenuation ile doğar.
2. AXI DAC init tamamlanır tamamlanmaz ve herhangi bir DDS/DMA source seçilmeden önce `axi_dac_set_datasel(tx_dac, -1, AXI_DAC_DATA_SEL_ZERO)` çağrılır.
3. Mevcut generic örnekteki sonraki `AXI_DAC_DATA_SEL_DDS` veya DMA source seçim yolları RX-only build flag'inde derlenmez/çalıştırılmaz.
4. Her mevcut TX channel için 89.750 mdB attenuation readback ve DAC source ZERO register readback doğrulanır.
5. Yalnız tüm adımlar geçerse `TX_SAFE: PASS` yazılır ve RX capture kontrolü açılır.

Bir adım hata verirse yazılım sonraki RF/DMA/PL capture adımlarına geçmez. Attenuation init değeri maksimumda kalır; mümkünse DAC ZERO tekrar denenir ve hata koduyla çıkılır.

---

## 10. RF switch controller

RF switch parçaları `ZX80-DR230-S+` ve `EV1HMC936ALP6/HMC936ALP6E` olarak doğrulanmıştır. Fiziksel faz aşağıdaki kalan donanım sözleşmesi sağlanmadan başlatılmayacaktır:

- BDC sonrası hedef IF'nin 1.2-1.4 GHz içinde olduğunun doğrulanması; HMC936A bu bant dışında kullanılmayacaktır
- 50 Ω RF portları, insertion loss, isolation, return loss, P1dB/IP3 ve maksimum RF giriş gücü
- ZX80 için `VDD=2.7-5.0 V`, LOW `0-0.4 V`, HIGH `2.4 V..VDD`, `00=OFF`, `10=RF1`, `01=RF2`, `11=yasak` sözleşmesi
- HMC936A için +5 V besleme/kontrol, altı aktif-düşük faz biti ve zorunlu 5 V level-shifter/buffer
- ZX80 tipik 2 us ile HMC936A tipik 250 ns switching değerlerinden başlayıp ölçümle kapatılan settle/discard süresi
- Ortak ground, RF kablo/konnektör planı ve switch'in FPGA pininden beslenmediğinin teyidi
- FPGA konfigürasyonu öncesi güvenli varsayılan A/B seçimi için harici pull-up/pull-down veya eşdeğer donanım
- Seçilen FPGA pininin konnektör, I/O bank voltage ve XDC eşlemesi

Mevcut `gpio_ctl[3:0]` switch kontrolü için serbest pin kabul edilmeyecektir; bu sinyaller PS GPIO üzerinden AD9364 kontrol girişlerine bağlıdır. Toplam sekiz fiziksel çıkış gerekir: ZX80 için iki, HMC936A için altı. MIPI kullanılmıyorsa J23 üzerindeki 3,3 V `CAM_GPIO` adaydır, fakat pin sayısı/bank/XDC ve 5 V level-shifter şeması tamamlanmadan kilitlenmeyecektir. FMC bankları 1,8 V olduğundan doğrudan kontrol varsayılmayacaktır.

FSM:

```text
IDLE
→ SELECT_A
→ SETTLE_A
→ DISCARD_A
→ CAPTURE_A
→ PROCESS_A
→ SELECT_B
→ SETTLE_B
→ DISCARD_B
→ CAPTURE_B
→ PROCESS_B_AND_COMPARE
→ DONE
```

AXI-Lite register'ları:

```text
CONTROL
  start
  abort
  mode_single
  mode_continuous
  soft_reset

RF_SWITCH
  selected_input
  switch_polarity
  settling_cycles
  discard_samples

CAPTURE
  frame_length
  frame_count
  sample_rate_id

FFT
  fft_length
  window_select
  scaling_schedule
  output_mode

GAIN_METADATA
  expected_gain
  gain_readback

ARITHMETIC
  operation
  epsilon
  denominator_threshold

STATUS
  busy
  done
  spectrum_valid
  active_bank
  frame_id
  rf_state
  peak_bin
  peak_power
  peak_re
  peak_im
  config_error
  cdc_ready
  cdc_fault
  reset_epoch
  aborted
  fifo_overflow
  frame_error
  fft_error
  arithmetic_overflow
  denominator_small
  clipping_detected
  dropped_samples
  bank_overrun
```

`peak_re/peak_im` tek tamamlanmış frame'in FFT peak katsayısını taşır; bit-doğru
doğrulama ve diagnostik içindir. Ardışık RF durumları arasında kompleks koherens
kanıtı olmadığı sürece monopulse ürün hesabında kullanılmaz.

MVP'de `fft_length=2048`, forward transform ve `scaling_schedule=0x6AB` sabittir. Register alanı varsa readback/gelecek sürüm uyumluluğu içindir; farklı değer yazımı `config_error` üretmeli ve capture başlatmamalıdır.

`settling_cycles` processing-clock cycle cinsinden, `discard_samples` ise kabul edilen kompleks ADC örneği cinsinden tanımlanacaktır. Register dokümanı her iki alanın clock domain'ini açıkça yazacaktır. İlk değerler switch datasheet'inden türetilir; nihai değerler kontrollü RF kaynağıyla laboratuvar ölçümünden elde edilir.

---

## 11. FFT yapılandırması

İlk FFT IP ayarı:

- Maksimum uzunluk: 2048
- Forward FFT
- Fixed-point
- İlk Candidate için Pipelined Streaming I/O
- Natural-order output tercih edilecek
- Kontrollü scaling schedule
- Event/status sinyalleri bağlı olacak

Pencereleme:

- Rectangular: bit-doğrulama
- Hann: spektrum ölçümü

Bit genişliği her aşamada açıkça dokümante edilecektir:

```text
ADC örneği
→ window multiply sonucu
→ FFT internal/output
→ magnitude-square
→ arithmetic output
```

Her daraltmada rounding ve saturation politikası tanımlanacaktır. Sessiz bit truncation yapılmayacaktır.

RTL başlamadan kilitlenecek sayısal sözleşme:

| Aşama | MVP sayısal sözleşmesi |
|---|---|
| ADI örnek kabı | Signed two's-complement 16-bit integer I ve Q; binary point varsayılmaz. Aktif 12 bitin yerleşimi Faz 1 ILA kapısında ölçülür; beklenen sign-extended yerleşim görülmezse RTL başlamaz ve bu tablo ölçülen formata göre revize edilir. |
| İç kompleks sıra | Mantıksal tuple `(I,Q)`; fiziksel 32-bit RAM/AXIS word `{Q[15:0],I[15:0]}`. Düşük 16 bit FFT real/I, yüksek 16 bit FFT imaginary/Q; CRC/DMA/Python byte sırası `I_lo,I_hi,Q_lo,Q_hi`. |
| Rectangular | Katsayı uygulanmaz; 16-bit I/Q değişmeden FFT girişine gider. |
| Hann ROM | 2048 adet unsigned Q1.15 katsayı, `round(0.5*(1-cos(2*pi*n/2047))*32767)` ve endpoint 0. |
| Window multiply | Signed 16×unsigned 16 → signed 32-bit ara sonuç; 15 bit sağa kaydırma, round-to-nearest-even ve signed 16-bit saturation. |
| FFT | Vivado 2020.1 FFT v9.1, 2048-point forward, Pipelined Streaming I/O, fixed-point scaled arithmetic, 16-bit I/Q input, 16-bit I/Q output, 24-bit phase factor, natural-order output ve convergent rounding. `SCALE_SCH[11:0] = 12'b01_10_10_10_10_11` (`0x6AB`): LSB group 0 için 3 bit, sonraki dört iki-stage group için 2'şer bit ve tek-stage son group için 1 bit kayma; toplam 12 bit, yani `2^-12`. FFT overflow/event kabulde hatadır. |
| Magnitude-square | İki signed 16×16 çarpım 32-bit; toplam unsigned 33-bit, truncation yok. |
| Spectrum BRAM | Bin başına 64-bit word; `[32:0]=magnitude_sq`, `[63:33]=0`. 2048 bin için 16 KiB logical payload. |
| PA/PB ve ratio | PA/PB unsigned 33-bit kaynak olarak 64-bit yazılım değişkenine genişletilir; ratio ilk Candidate'da double/64-bit referansla PS/Python'da hesaplanır. |
| Frame korelasyonu | CRC-32/ISO-HDLC: poly `0x04C11DB7`, reflected poly `0xEDB88320`, init/xorout `0xFFFFFFFF`; byte sırası her sample için little-endian `I_lo,I_hi,Q_lo,Q_hi`. |
| Bit-true tolerans | Deterministik vektörlerde tüm 16-bit FFT I/Q ve 33-bit magnitude-square sonuçları modelle tam eşit olmalıdır (`0 LSB` fark). Analog RF kabulü ayrıca ölçüm belirsizliğiyle değerlendirilir. |

Bu schedule, PG109'un Pipelined Streaming için “group 0 iki LSB'dir”, iki-stage group başına en çok 2 bit, ilk group için korumalı 3 bit ve tek-stage son group için en çok 1 bit kuralından türetilmiştir. Vivado 2020.1 tarafından üretilen XCI/config ve FFT v9.1 C modeli `0x6AB`, 24-bit phase-factor ve `2^-12` toplam ölçeği aynen göstermeden Paket 4 geçmez. Kaynak: [AMD/Xilinx Fast Fourier Transform v9.1 Product Guide PG109](https://www.xilinx.com/support/documents/ip_documentation/xfft/v9_1/pg109-xfft.pdf).

- 16-bit signed I/Q'nun gerçek AD9364 12-bit örneğini hangi bitlerde taşıdığı ve sign-extension davranışı
- I/Q sırası, complex işareti ve frame içindeki sample sırası
- Rectangular ve Hann katsayı genişliği, Q formatı, normalizasyonu ve coherent-gain düzeltmesi
- FFT input/output genişliği, scaling schedule, rounding, saturation ve overflow davranışı
- Natural-order çıkış ve bin 0/DC tanımı
- Magnitude-square ara genişliği; 16×16 çarpım ve iki kare toplamında taşmanın önlenmesi
- Python modelinde aynı integer işlemleri ve aynı saturate/round kuralları
- Kontrollü vektörler için bin başına izin verilen mutlak LSB farkı ve toplam güç farkı

Zorunlu doğrulama vektörleri:

- Sıfır frame
- Kompleks impulse
- Bin merkezli kompleks ton
- Bin merkezinde olmayan kompleks ton
- Pozitif/negatif sınır örnekleri
- Sabit seed'li pseudo-random kompleks örnekler
- Saturation/overflow'u bilinçli tetikleyen negatif test

FFT kabulü yalnız “tepe ±1 bin” ölçütüne dayanmayacak; bin index, genlik/güç hatası, leakage, status/event sinyalleri ve bit-doğru Python karşılaştırması birlikte raporlanacaktır.

---

## 12. Aritmetik IP kapsamı

Ardışık A/B capture'lar faz-koherent değildir. Bu nedenle ilk ürün kapsamı yalnız gerçek, unsigned güç spektrumları üzerindeki işlemlerdir. Kompleks FFT binleri üzerinde A/B `ADD`, `SUB`, `MUL` veya `DIV` uygulanmayacaktır.

```text
POWER_A:
PA[k] = ReA² + ImA²

POWER_B:
PB[k] = ReB² + ImB²

POWER_SUM:
S[k] = PA[k] + PB[k]

POWER_DIFF:
D[k] = signed(PA[k]) - signed(PB[k])

POWER_RATIO:
R[k] = PA[k] / (PB[k] + epsilon)
```

İlk A/B kabul hedefi `PA[k]` ve `PB[k]` güç dizilerinin PL'de doğru üretilmesi ve saklanmasıdır. İlk Candidate'da `POWER_RATIO`, finite-frame sonuçları PS/Python tarafında 64-bit veya floating-point referansla hesaplanacaktır. Bu işlem PS'nin gerçek zamanlı sample yoluna girmesi anlamına gelmez. PL divider yalnız ölçülen throughput/latency gereksinimi PS hesaplamasının yetersiz olduğunu gösterirse eklenecektir.

Kompleks işlemler yalnız yeni ve açık bir **koherent ölçüm** gereksinimi doğarsa ayrı tasarım olarak ele alınacaktır. Böyle bir fazda ortak referans saat, eşzamanlı örnekleme, faz kalibrasyonu ve aşağıdaki matematik yeniden kabul kapısına girer:

```text
A / B = A × conjugate(B) / (|B|² + epsilon)
```

Mevcut tek-RX AD9364 ve ardışık harici switch mimarisinde kompleks A/B oranı ürün fonksiyonu sayılmayacak ve mevcut faz listesine dahil edilmeyecektir.

PL divider kapısında seçenekler:

- Divider Generator IP
- Reciprocal + multiplier
- PS üzerinde scalar division
- Yalnız güçleri PL'de hesaplayıp oranı PS'de üretme

arasında sentez ve latency karşılaştırması yapılacaktır.

`epsilon` ve `denominator_threshold` aynı birimde tanımlanacak; küçük payda durumunda sonuç saturate edilmek yerine `denominator_small` ile işaretlenecek ve politika register sözleşmesinde belirtilecektir.

---

## 13. Referans C altyapısı ve RF/test kaynaklarının rolü

Auditin incelediği `wifi_rf_capture.*`, `wifi_rf_metrics.*` ve `wifi_rf_test.*` dosyaları `d264bddd5644529099e7516b24c9b4d54d2da47d` commit'li `codex/wifi-rf-detection` branch'inde mevcuttur; güncel `codex/axu4ev-pmufw-bringup` çalışma ağacında bulunmamaktadır. Dolayısıyla bu altyapı mevcut branch'te varmış gibi kabul edilmeyecektir.

Paket 2 başlamadan önce ilgili dosyalar ve `PROJECT/tests/wifi_rf_metrics_test.c` kaynak commit'ten kontrollü olarak alınacak, mevcut `main.c`/BSP ile diff-review yapılacak, Release build ve kart Golden regresyonu geçecektir. Tüm branch'i körlemesine merge/cherry-pick etmek yerine yalnız gerekli dosya ve bağımlılıklar taşınacaktır. Kaynak commit, portlanan dosya hash'leri ve uyarlama diff'i evidence kaydına yazılacaktır.

Portlanan C altyapısı kaldırılmayacak ve aşağıdaki alanlarda kullanılacaktır.

Kullanılacağı alanlar:

- RX-only güvenlik kapısı
- DMA capture
- Gain reuse
- Peak ve clipping
- Mean power
- Baseline/active karşılaştırması
- PL sonucu sanity-check
- Hata ve timeout yönetimi

Port ve uyarlama tamamlandıktan sonra yeni Vitis uygulaması şu modları destekleyecektir:

```text
MODE_DMA_REFERENCE
MODE_PL_FFT
MODE_DUAL_COMPARE
MODE_RF_SWITCH_AB
```

`MODE_DUAL_COMPARE` sırasında DMA ve PL yolu aynı RF koşulunda çalıştırılacak; C metrikleriyle PL sonuçları birlikte raporlanacaktır.

Bit-doğru `MODE_DUAL_COMPARE` kabulünde yalnız aynı koşul yeterli değildir; DMA ve PL tarafı aynı `frame_id` içindeki aynı 2048 örneği kullanacaktır.

FFT doğrulaması için DMA tamponu host'a aktarılacak ve bit-doğru Python modeliyle karşılaştırılacaktır.

Telefon hotspot'u yalnız erişilebilir bir **ortam RF aktivitesi** kaynağıdır; proje gereksinimi veya nicel kabul kaynağı değildir. Test kaynakları amaçlarına göre seçilecektir:

1. **Dijital deterministik vektör:** FFT, scaling, rounding ve overflow'un bit-doğru RTL/Python doğrulaması. RF zincirini test etmez.
2. **RF sinyal üreteci/CW:** LO, beklenen bin, genlik doğruluğu, leakage ve A/B attenuation farkı için birincil nicel kabul kaynağı.
3. **Sabit attenuator veya iki bilinen seviye:** Power ratio doğruluğu ve switch yol kalibrasyonu.
4. **Kalibre veya kararlı noise source:** Bant gücü ve istatistiksel tekrarlanabilirlik.
5. **Kablolu ve uygun attenuator'lı loopback:** Laboratuvar ekipmanı kısıtlıysa işlevsel RF zinciri testi; AD9364 RX maksimum giriş seviyesi hiçbir koşulda aşılmayacaktır.
6. **Telefon hotspot'u, erişim noktası veya ortam RF'si:** Aktivite algılama ve saha gösterimi; kararlı A/B ratio veya bit-doğru kabul için kullanılmayacaktır.

Harici RF kaynağı bağlanmadan önce frekans, beklenen güç, toplam kablo/attenuator kaybı ve AD9364 giriş güvenlik marjı test kaydına yazılacaktır. Anten üzerinden yalnız alım yapılan testlerde yasal yayınlar pasif olarak gözlenecek; TX kapalı ve maksimum attenuation'da tutulacaktır.

---

## 14. Geliştirme aşamaları

### Faz -1 — Kaynak ve build yeniden üretilebilirliği

- `projects/fmcomms2/axu4ev/Makefile` proje adı `fmcomms2_axu4ev` olarak düzeltilmiştir.
- Makefile kart bağımlılıkları `common/axu4ev/axu4ev_system_constr.xdc` ve `common/axu4ev/axu4ev_system_bd.tcl` olarak düzeltilmiştir.
- Tüm Makefile bağımlılıklarının dosya varlığı otomatik kontrolden geçmiştir.
- Aktif tasarım kaynakları `projects/fmcomms2/axu4ev/system_project.tcl`, `system_bd.tcl`, `system_top.v`, `system_constr.xdc` ve `projects/common/axu4ev/*` dosyalarıdır.
- `PROJECT/sdr_bd_export.tcl` ADRV9009/JESD204 tasarımına aittir; FMCOMMS2/AD9364 analizinde veya build'de kullanılması yasaktır.
- `PROJECT/axu4ev_fmcomms.xdc` aktif `system_project.tcl` tarafından yüklenmez ve legacy kanıt dosyasıdır. Aktif pin/termination kaynağı `projects/fmcomms2/axu4ev/system_constr.xdc` içindeki UltraScale+ `DIFF_TERM_ADV TERM_100` ayarlarıdır.
- Temiz build sonrasında aktif `system.bd` için `write_bd_tcl -force PROJECT/verification/vivado/fmcomms2_axu4ev_bd_export.tcl` kanıt export'u alınacak; export içinde `axi_ad9361`, `util_ad9361_adc_fifo`, `util_ad9361_adc_pack` ve `axi_ad9361_adc_dma` aranacak, JESD204/ADRV9009 blokları bulunmayacaktır.
- Release manifestindeki `source_commit=0cc0cf8f046e0c4e5d1f0378365d97e8492c3edb` commit'i mevcuttur fakat `2026-07-16-bringup-v1` Git tag'ı mevcut değildir. Manifest artifact SHA-256 değerleri yeniden doğrulandıktan sonra `git tag -a 2026-07-16-bringup-v1 0cc0cf8f046e0c4e5d1f0378365d97e8492c3edb -m "AXU4EV AD9364 verified bringup v1"` ile annotated tag oluşturulacaktır; hash doğrulanmadan tag oluşturulmayacaktır.
- Temiz Vivado 2020.1 ortamında Makefile/Tcl zinciriyle XPR, bitstream ve XSA yeniden üretilecektir.
- Temiz üretimin part, top, clock, address map, timing ve DRC sonuçları mevcut Golden manifestiyle karşılaştırılacaktır.

**Geçiş kapısı:** Temiz AXU4EV build tamamlanmalı; ZCU102 bağımlılığı bulunmamalı; routed timing kapanmalı ve severity `Error` DRC sayısı sıfır olmalıdır. `check_timing` envanteri Golden ile karşılaştırılmalı; yeni `no_clock`, `unconstrained_internal`, `no_input_delay` veya `no_output_delay` bulgusu bulunmamalıdır. Mevcut Golden'daki gözden geçirilmiş warning/advisory mesajlarının sıfır olması şart değildir, fakat Candidate yeni kritik warning ekleyemez. Bilinçli istisnalar sinyal ve gerekçesiyle waiver listesine yazılmalıdır.

### Faz 0 — Gereksinim ve switch kararı

- İlk ürün işlemi frekans alanında magnitude-square ve PA/PB üretimi olarak sabitlenmiştir.
- İlk A/B oranı PS/Python tarafında power ratio olarak hesaplanacaktır; kompleks ratio ilk ürün kapsamı dışındadır.
- Seçilen `ZX80-DR230-S+` ve `EV1HMC936ALP6` için BDC IF/koherens, DC-port, 5 V level-shifter ve FPGA pin sözleşmesi kapatılacak.
- 30,72 MSPS zorunlu başlangıç profili olarak doğrulanacak; 61,44 MSPS ayrı deneysel kapıdır.
- Ortak MGC gain politikası belirlenecek.
- Kabul test kaynağı ve bilinen giriş seviyeleri seçilecek; hotspot zorunlu olmayacaktır.
- FFT sabit nokta sözleşmesi ve aynı-frame kimliği onaylanacak.

**Çıkış:** Onaylı sayısal arayüz sözleşmesi, test-kaynağı matrisi ve RF switch kullanılacaksa seçilmiş datasheet/pin/gerilim belgesi.

### Faz 1 — Vivado veri yolu denetimi

- Block Design pinleri çıkarılacak.
- Gerçek RX veri yolu dokümante edilecek.
- ILA eklenecek.
- I/Q sırası ve sample-valid davranışı doğrulanacak.
- I0/Q0 ile I1/Q1 adayları DMA dump ve ILA'da ayrı incelenecek; MVP yalnız doğrulanmış I0/Q0 çiftini işleyecek.
- `util_ad9361_divclk/clk_out` gerçek frekansı ve reset davranışı ölçülecek.
- Mevcut `util_ad9361_adc_fifo` çıkışından, DMAC'a backpressure üretmeyen data tap eklenecek.
- ADI-native → 2048-word store-and-forward → AXI4-Stream adapter RTL simülasyonda `TREADY` stall ile doğrulanacak.
- `frame_id` ve aynı 2048 örneğin DMA/PL tarafından eşleştirildiği kanıtlanacak.

**Çıkış:** I/Q interface specification, ILA evidence ve non-blocking shadow-path testi.

### Faz 2 — Tek girişli capture ve FFT

- `adc_stream_bridge`
- Dual-clock frame buffer
- Hann/rectangular window
- 2048 FFT
- Magnitude-square
- Result buffer
- AXI-Lite kontrol

Önce deterministik dijital vektörlerle, ardından mevcutsa bilinen RF tonu veya güvenli attenuator'lı loopback ile test edilecek. Hotspot bu fazın kabul koşulu değildir.

**Çıkış:** Single-input PL FFT Candidate.

### Faz 3 — Yazılım/PL çapraz doğrulama

- Aynı `frame_id` ve aynı 2048 örnekle DMA capture
- C power/clipping sonucu
- Python FFT sonucu
- PL FFT sonucu

karşılaştırılacak.

**Çıkış:** Bit-doğrulanmış FFT ve scaling raporu.

### Faz 4 — Aritmetik IP

Sırayla:

1. Magnitude-square
2. PA/PB spectrum saklama
3. Unsigned power sum
4. Signed power difference
5. PS/Python üzerinde epsilon korumalı power ratio
6. Ölçülmüş gerekçe varsa PL reciprocal/divider

uygulanacak.

Kompleks A/B aritmetiği bu planın fazlarından çıkarılmıştır; koherent donanım gereksinimi oluşursa ayrı bir tasarım belgesi gerektirir.

**Çıkış:** RTL testbench ve golden-model karşılaştırması.

### Faz 5 — RF switch entegrasyonu

- Switch GPIO kontrolü
- FSM
- Settling/discard register'ları
- MGC ortak gain
- A ve B capture
- Spectrum-A buffer
- B streaming compare
- Switch A/B yol kaybı ve frekans cevabı kalibrasyonu
- Portları fiziksel olarak değiştirerek yapılan swap testi

eklenecek.

**Çıkış:** İki girişli ardışık RF güç karşılaştırma sistemi, switch kalibrasyon kaydı ve tekrarlanabilirlik raporu. Ardışık A/B yapısı koherent kompleks faz ölçümü olarak sunulmayacaktır.

### Faz 6 — Performans optimizasyonu

- FFT throughput
- FIFO occupancy
- BRAM/URAM
- DSP
- Latency
- Continuous streaming
- Ping-pong buffering
- Uzun FFT
- Result DMAC

ölçülecek.

### Faz 7 — Release kapanışı

Yeni PL tasarımı için birlikte üretilecek:

- BIT
- XSA
- PMUFW
- `psu_init.tcl`
- Vitis platform
- Release ELF
- Manifest
- SHA-256 değerleri
- UART kabul logu
- RF evidence
- Vivado timing/DRC raporu

Eski `2026-07-16-bringup-v1` değiştirilmeden korunacaktır. Yeni sürüm kart kabulünden sonra örneğin:

```text
YYYY-MM-DD-fft-switch-v1
```

adıyla ayrı Golden sürüm olacaktır.

---

## 15. Kabul kriterleri

1. Eski Golden sistem hâlâ başlatılabilir olmalıdır.
2. Yeni Candidate kendi BIT/XSA/ELF setiyle çalışmalıdır.
3. AD9364 init ile runtime sample-rate, RF bandwidth, LO, gain ve ENSM readback geçmeli; UART/metadata hardcoded RF değer kullanmamalıdır.
4. Mevcut DMA capture yolu çalışmaya devam etmelidir.
5. I/Q formatı ILA ve DMA verisiyle doğrulanmalı; MVP'nin yalnız fiziksel AD9364 I0/Q0 çiftini işlediği ve I1/Q1'i yok saydığı kanıtlanmalıdır.
6. Shadow FFT yolu mevcut pack/DMAC yoluna backpressure uygulamamalı; simülasyonda FFT `TREADY=0` iken replay verisi sabit kalmalı ve DMA regresyonu geçmelidir.
7. DMA, PL ve Python karşılaştırması PL ilk-8-sample imzası ve 2048-sample CRC-32 ile DMA içindeki tek alt-diziye eşlenmelidir.
8. Deterministik rectangular-window testlerinde PL FFT ve bit-true model tüm çıkış bitlerinde aynı sonucu üretmelidir; farklı rounding kullanılması kabul edilmez.
9. Hann testinde kullanılan ROM katsayıları Python modeline aynen aktarılmalı; scaling ve coherent-gain düzeltmesi raporda belirtilmelidir.
10. Kontrollü bin-merkezli ton beklenen bin'de görülmeli; analog LO/source belirsizliği varsa en fazla ±1 bin arama penceresi kullanılmalıdır.
11. C ve PL mean-power sonuçları aynı frame ve aynı tanımlı scaling üzerinde karşılaştırılmalıdır.
12. A/B ölçümleri aynı LO, bandwidth, sample rate ve MGC gain ile yapılmalıdır.
13. Kontrollü kabul frame'lerinde clipping sıfır olmalıdır.
14. Capture açıkken FIFO overflow, sample drop, eksik/fazla sample ve FFT event error sıfır olmalıdır.
15. Switch sonrası settling/discard değeri datasheet başlangıç değeriyle kurulmalı ve kontrollü kaynakla ölçülerek artırma marjı kaydedilmelidir.
16. Switch A/B yol farkı kalibre edilmeli; port-swap testi aynı fiziksel yolun sonuca yanlış A/B etiketi vermediğini göstermelidir.
17. Kararlı kontrollü RF kaynağında aynı koşulda en az 10 A/B tekrarının power-ratio standart sapması hedef olarak ≤0,5 dB olmalıdır; kaynak kararlılığı bu sınırdan kötüyse kaynak kabul için kullanılamaz.
18. Hotspot/ortam RF testi yalnız aktivite ve saha demonstrasyonu sayılır; bin doğruluğu, absolute power veya A/B ratio kabulü sayılmaz.
19. Vivado DRC severity `Error` sayısı sıfır olmalı; mevcut Golden warning/advisory listesine göre yeni kritik warning bulunmamalıdır.
20. Setup ve hold timing kapanışı geçmeli; WNS ve WHS negatif olmamalıdır.
21. `check_timing` raporunda Golden'a göre yeni `no_clock`, `unconstrained_internal`, `no_input_delay` veya `no_output_delay` bulgusu bulunmamalı; bilinçli istisna waiver listesinde gerekçelendirilmelidir.
22. Sentez/implementation raporunda hiçbir kaynak yüzde 100'e yaklaşmamalı; sonraki geliştirmeler için LUT, BRAM ve DSP kaynaklarının her birinde en az %20 boşluk korunmalıdır.
23. Profil B 61,44 MSPS ancak Profil A'daki tüm veri-bütünlüğü kriterlerini ayrıca sağlarsa desteklenmiş sayılmalıdır.
24. Yeni Golden yalnız fiziksel RF kabulünden ve manifest/SHA-256 üretiminden sonra seçilmelidir.
25. Build kaynak listesinde `PROJECT/sdr_bd_export.tcl` ve `PROJECT/axu4ev_fmcomms.xdc` bulunmamalıdır; aktif BD export'u FMCOMMS2 blok kimlik kontrolünden geçmelidir.
26. Aktif RX constraint'lerinde `DIFF_TERM_ADV TERM_100` korunmalı; legacy `DIFF_TERM TRUE` dosyası Candidate'a eklenmemelidir.
27. Mevcut Golden manifestindeki tüm artifact SHA-256 değerleri doğrulandıktan sonra `2026-07-16-bringup-v1` annotated Git tag'ı manifestteki source commit'e bağlanmalıdır.
28. RX-only başlatmada init parametresi baştan 89.750 mdB olmalı; AXI DAC init'ten hemen sonra ve DDS/DMA seçilmeden önce tüm kanallar `AXI_DAC_DATA_SEL_ZERO` yapılmalı; attenuation/source readback sonrası UART `TX_SAFE: PASS` göstermelidir.
29. `util_ad9361_divclk/clk_out` frekansı ve reset domain'i ölçülmüş clock/ILA kanıtıyla raporlanmalıdır.
30. `d264bddd` kaynak commit'inden taşınan Wi-Fi/RF C dosyaları current-branch diff review, unit test, Release build ve kart Golden regresyonundan geçmeden PL doğrulama oracle'ı sayılmamalıdır.
31. Start/abort/config ve frame metadata CDC mailbox testleri; command ack, `TREADY` stall, unilateral reset, epoch mismatch ve recovery senaryolarında stale frame üretmeden geçmelidir.

---

## 16. İlk uygulanacak minimum sürüm

İlk gerçek implementasyonun kapsamı bilinçli olarak küçük tutulacaktır:

```text
Tek RF girişi
+ mevcut RX DMAC yolu
+ util_ad9361_adc_fifo çıkışından non-blocking data tap
+ 2048 sample frame buffer
+ frame_id ve exact-sample eşlemesi
+ önce rectangular, ardından Hann window
+ 2048 FFT
+ magnitude-square
+ AXI BRAM Controller üzerinden sonuç buffer
+ yalnız kontrol/status için AXI-Lite
+ Vitis readout
+ bit-true Python karşılaştırma
```

Bu sürüm geçmeden RF switch veya PL power divider eklenmeyecektir.

İkinci minimum sürüm:

```text
Harici SPDT RF switch
+ MGC ortak gain
+ A capture
+ FFT-A buffer
+ B capture
+ FFT-B
+ PA/PB spectrum
+ PS/Python power ratio
+ switch yol kalibrasyonu
```

Continuous streaming ve 65.536 noktalı FFT daha sonraki optimizasyon fazlarıdır. Tam kompleks A/B bölme mevcut ardışık tek-RX mimarisinin kapsamı dışındadır.

---

## 17. Stratejik geliştirme ilkesi

Mevcut çalışan DMA/Vitis yolu kaldırılmadan PL FFT paralel bir shadow path olarak eklenecektir.

Bu yaklaşım:

- Eski Golden sürüme geri dönüşü korur.
- Mevcut C kodunu doğrulama referansı olarak kullanır.
- PL FFT'nin aşamalı ve ölçülebilir şekilde doğrulanmasını sağlar.
- Vitis'i gerçek zamanlı veri yolundan çıkarırken kontrol ve test katmanı olarak korur.
- Yeni Vivado IP'lerinin mevcut projeye kademeli olarak eklenmesine izin verir.

---

## 18. Zorunlu isterler, varsayılanlar ve karar kapıları

Aşağıdaki tablo eksik bilgi yüzünden yanlış donanım geliştirilmesini engeller. Bir ister sağlanmadığında tabloda yazan güvenli varsayılan uygulanır veya ilgili faz durur; sessiz varsayım yapılmaz.

| İster | Güvenli başlangıç kararı | Hangi fazdan önce kanıtlanmalı? | Kanıt |
|---|---|---|---|
| Çalışma biçimi | Önce tetiklemeli finite-frame; sonra ping-pong bankalı sürekli FFT frame. Sürekli host/DDR streaming değil | Faz 2/4 | Register sözleşmesi, bank ownership ve throughput testi |
| Zorunlu sample rate | 30,72 MSPS | Faz 2 | AD9364 readback + ILA/DMA |
| Deneysel sample rate | 61,44 MSPS yalnız ayrı kapıyla | Faz 6 | Overflow, throughput ve timing raporu |
| FFT uzunluğu | 2048 | Faz 2 | IP config ve test vektörü |
| Processing clock | Mevcut 100 MHz `sys_cpu_clk` | Faz 2 | Clock ve timing raporu |
| Tap noktası | `util_ad9361_adc_fifo` çıkışı | Faz 1 | BD bağlantısı + ILA |
| İşlenen kanal | Yalnız doğrulanmış AD9364 I0/Q0; I1/Q1 yok sayılır | Faz 1 | ILA + DMA dump |
| Adapter | ADI-native capture + 2048-word store-and-forward + AXI4-Stream replay | Faz 2 | Self-checking RTL stall testi |
| Control/metadata CDC | Bundled command/ack + frame metadata handshake + 8-bit reset epoch | Faz 2 | Stall/reset/epoch recovery RTL testi |
| DMA izolasyonu | FFT yolundan DMAC'a backpressure yasak | Faz 1 | Non-blocking test ve DMA regresyonu |
| Frame eşliği | PL `frame_id` + ilk 8 örnek imzası + 2048-örnek CRC-32 ile DMA alt-dizi eşleşmesi | Faz 3 | DMA dump + PL metadata + tek CRC eşleşmesi |
| İlk pencere | Rectangular bit-doğrulama, sonra Hann | Faz 2 | Bit-true model |
| İlk çıktı | Tam 2048-bin magnitude-square spectrum + peak bin/power + diagnostik peak Re/Im | Faz 4 | BRAM dump + Python karşılaştırma |
| İlk oran hesabı | PS/Python | Faz 4 | 64-bit/floating referans raporu |
| PL divider | Ölçülmüş performans ihtiyacı olmadan eklenmez | Faz 6 | Latency/throughput gerekçesi |
| A/B karşılaştırma | Ardışık power/magnitude; koherent faz değil | Faz 5 | Sistem test raporu |
| RF switch | ZX80/HMC936A modelleri doğrulandı; BDC IF/koherens, RF-port 0 VDC, level-shifter, kablo/pin eşlemesi ve ölçülmüş settle kapanmadan RTL kontrolü eklenmez | Faz 5 | İki datasheet + kontrol şeması + XDC incelemesi |
| İlk nicel RF kaynağı | CW generator; yoksa güvenli attenuator'lı loopback | Faz 2/5 | Frekans ve güç bütçesi kaydı |
| Hotspot/ortam RF | İsteğe bağlı aktivite demonstrasyonu | Herhangi | UART/evidence; nicel kabul sayılmaz |
| Gain | A/B için ortak MGC | Faz 5 | Gain readback |
| Runtime RF metadata | Sample rate, bandwidth ve LO API readback; hardcoded metin yasak | Faz 2 | UART + metadata snapshot |
| TX güvenliği | AXI DAC `ZERO` + 89.750 mdB attenuation + readback | Tüm RF testleri | `TX_SAFE: PASS` UART/log |
| Result taşıma | Spectrum için AXI BRAM; AXI-Lite yalnız control/status | Faz 2 | Address map ve readout testi |
| Kaynak doğruluğu | Aktif FMCOMMS2 Tcl/XDC; JESD204 export ve legacy XDC yasak | Faz -1 | Source list + BD export kimlik testi |
| Golden koruması | Mevcut Golden immutable ve source commit annotated tag ile işaretli | Her faz | Manifest/SHA-256 + Git tag |

Projeyi ürün seviyesinde genişletmeden önce proje sahibinin ayrıca belirlemesi gereken üst-seviye isterler:

- Hedef RF frekans aralığı yalnız 2,4 GHz mi, yoksa AD9364'ün daha geniş bandı mı?
- Kabul edilen maksimum tek-frame latency ve saniyedeki istenen frame sayısı nedir?
- Sonucun tam spektrum mu, seçilmiş bin/bant gücü mü, yoksa yalnız scalar oran mı olması gerekir?
- Absolute power doğruluğu gerekiyor mu; gerekiyorsa izin verilen dB hatası ve kalibrasyon standardı nedir?
- A/B ratio dinamik aralığı ve izin verilen minimum payda seviyesi nedir?
- HMC936A için altı kanallı 5 V level-shifter/buffer hangi devre olacak ve güvenli `OE` durumu nedir?
- Üç BDC ortak LO/referans kullanıyor mu; gerçek IF ve göreli faz drift'i nedir?
- Harici switch kartı hazır mı; değilse satın alma, level-shifter/buffer, breakout/PCB ve konektör sorumluluğu kimdedir?
- Nihai çalışma bare-metal Vitis mi, PetaLinux sürücüsü/IIO mu olacaktır?

Bu sorular ilk tek-girişli FFT Candidate'ı engellemez. İlgili ürün özelliğine geçilmeden önce cevapları ölçülebilir gereksinim olarak bu belgeye işlenecektir.

---

## 19. Dosya sınırları ve uygulanacak iş paketleri

Yeni iş Golden kaynaklarıyla karışmaması için bağımsız ve sorumluluğu tek olan klasörlerde tutulacaktır:

```text
Related-Docs/hdl-main/library/axi_ad9364_fft_capture/
  axi_ad9364_fft_capture.v
  adc_stream_bridge.v
  frame_capture.v
  window_mul.v
  magnitude_sq.v
  axi_ad9364_fft_capture_ip.tcl

PROJECT/verification/fft/
  model/
  vectors/
  rtl/
  reports/

Vitis/workspace/ad9364app/src/adc9364_src/
  pl_fft_control.c
  pl_fft_control.h
```

İlk uygulama paketi sırası:

- [x] **Paket 0 — Makefile kimliği:** AXU4EV proje adı ve kart bağımlılıkları düzeltildi; dosya-varlık testi geçti.
- [ ] **Paket 1 — Kaynak güveni + temiz build:** Aktif Tcl/XDC listesini doğrula; JESD204 export/legacy XDC'yi dışla; temiz Vivado 2020.1 XPR/bitstream/XSA üret; FMCOMMS2 BD export kimlik testini, Golden part/address/timing/DRC regresyonunu ve manifest hash kontrolünden sonra annotated bringup tag'ını tamamla.
- [ ] **Paket 2 — Referans C portu, arayüz ve RX-only güvenlik kanıtı:** `d264bddd` commit'indeki Wi-Fi/RF kaynaklarını dosya bazında taşı ve test/build/kart regresyonunu geçir; ILA ile FIFO çıkışında I0/Q0/I1/Q1, valid/enable/sample sırasını ve `clk_out` frekansını ölç; runtime Fs/BW/LO readback ile TX DAC ZERO/89.750 mdB readback testini geçir; `frame_id`, ilk-8-sample imzası ve CRC-32 sözleşmesini dondur.
- [ ] **Paket 3 — Adapter + deterministik capture:** Önce başarısız self-checking RTL testinde ADI-native valid boşlukları, AXI `TREADY` stall, command/metadata handshake, busy-start rejection, abort, tek-taraflı reset ve epoch recovery uygula; sonra 2048-word dual-clock store-and-forward bridge, AXI4-Stream replay ve AXI BRAM readout'u geçir.
- [ ] **Paket 4 — FFT sayısal kapanış:** NumPy bit-true vektörlerini üret; rectangular, Hann, FFT ve magnitude-square bloklarını test-first ekle. Linux/IIOD aşamasında AD936X desteği bulunan `analogdevicesinc/pyadi-iio` ile `adi.ad9361(uri=...)` RX yakalama adaptörünü aynı vektör sözleşmesine bağla.
- [ ] **Paket 5 — Kart çapraz doğrulama:** DMA buffer içindeki tek imza+CRC eşleşmesiyle aynı 2048 örneği bul; PL ve Python ile karşılaştır; DMA regresyonu ile AD9364 Golden testini yeniden çalıştır.
- [ ] **Paket 6 — A/B gereksinim kapısı:** Switch datasheet/pin/güç ve kontrollü RF kaynağı kanıtlarını tamamla.
- [ ] **Paket 7 — A/B güç ölçümü:** FSM, settle/discard, PA/PB buffer, kalibrasyon ve PS power-ratio readout'unu ekle.
- [ ] **Paket 8 — Performans/release:** Yalnız ölçümle gerekçelenen ping-pong, 61,44 MSPS veya PL divider özelliklerini ekle; Candidate'ı fiziksel kabulden sonra yeni Golden olarak paketle.

Her pakette sırasıyla başarısız test, en küçük uygulama, geçen test, timing/DRC veya yazılım regresyonu ve ayrı commit bulunacaktır. Bir paketin geçiş kapısı başarısızsa sonraki paket başlatılmayacaktır.

---

## 20. 2026-07-20 teknik audit uzlaştırması

`C:/Users/DELL/Downloads/audit_report.md` farklı bir worktree/commit (`codex/wifi-rf-detection`, `d264bddd`) üzerinde hazırlanmıştır. Bu nedenle satır numaraları ve bazı Vitis kaynakları mevcut `codex/axu4ev-pmufw-bringup` çalışma ağacına doğrudan taşınmamıştır. Bulgular güncel kaynakta yeniden doğrulanarak aşağıdaki şekilde ele alınmıştır.

| Audit maddesi | Karar | Ana plana etkisi |
|---|---|---|
| ADI-native → AXI4-Stream adapter eksikliği | Kabul | Bölüm 4'e kesin port, I0/Q0, TLAST ve handshake sözleşmesi eklendi. |
| Backpressure/store-and-forward | Kabul | 2048-word capture tamamlanmadan FFT replay başlamaz; `TREADY` stall RAM'de tutulur. |
| I1/Q1'in AD9364 için kullanılmaması | Kabul | MVP yalnız ILA/DMA ile doğrulanan I0/Q0 çiftini işler. |
| CDC ve `clk_out` ölçümü | Kabul | Dual-clock RAM request/ack handshake ve gerçek clock ölçümü zorunlu oldu. |
| Control/config/reset CDC atomikliği | Review sonrası genişletildi | Start/abort/config bundled mailbox, reverse metadata handshake, sticky `cdc_fault` ve software `reset_epoch` recovery sözleşmesi eklendi. |
| `sdr_bd_export.tcl` yanlış JESD204 tasarımı | Doğrulandı | Dosya source-of-truth listesinden yasaklandı; temiz FMCOMMS2 BD export kimlik testi eklendi. |
| `axu4ev_fmcomms.xdc` termination çelişkisi | Doğrulandı | Aktif kaynak `system_constr.xdc` ve `DIFF_TERM_ADV TERM_100`; legacy XDC Candidate'a alınmayacak. |
| 61,44 MSPS kanıtlanmamış | Zaten çözülmüş | Yalnız ayrı Faz 6 kapısıyla desteklenecek. |
| Kompleks ardışık A/B işlemleri fiziksel olarak anlamsız | Kabul | Kompleks ADD/SUB/MUL/DIV mevcut fazlardan çıkarıldı; yalnız PA/PB sum/diff/ratio tutuldu. |
| Runtime Fs/BW/LO metni hardcoded olabilir | Kabul | API readback başarısızsa capture başlamaz; aynı snapshot PL metadata'ya gider. |
| TX DDS güvenliği | Güncel kaynakta doğrulandı | Mevcut `main.c` DDS seçebiliyor ve default attenuation 10.000 mdB; Candidate için DAC ZERO + 89.750 mdB + readback bloklayıcı kapı oldu. |
| Auditin kullandığı Wi-Fi/RF C dosyaları current branch'te yok | Doğrulandı | Dosyalar `d264bdd` commit'indeki `codex/wifi-rf-detection` branch'inden kontrollü merge + diff review + test/build/kart regresyonuyla alınacak; mevcutmuş gibi varsayılmayacak. |
| Bringup Git tag'ı yok | Doğrulandı | Manifest hash doğrulamasından sonra `0cc0cf8f...` commit'inde annotated tag zorunlu. |
| Hotspot zorunluluğu | Zaten çözülmüş | Hotspot yalnız demonstrasyon; dijital vektör/CW/attenuator/noise/loopback seçenekleri korunuyor. |
| `gpio_ctl` veya PS MIO'yu switch için kullanma | Reddedildi | `gpio_ctl` AD9364 CTRL_IN'e bağlıdır; PS MIO doğrudan PL FSM kontrolü sağlamaz. CAM_GPIO/ayrı uygun PL pin kararı korunuyor. |
| Audit fixed-point tablosu (27/32/48 bit) | Reddedildi | MVP, PG109 ile doğrulanan 16-bit scaled FFT, 24-bit twiddle, `0x6AB`, 33-bit magnitude-square ve 64-bit BRAM sözleşmesini kullanır. İki format karıştırılmayacak. |
| İlk sonuç yolu olarak Result DMA | Ertelendi | Finite-frame MVP AXI BRAM kullanır; Result DMAC yalnız ölçülmüş performans ihtiyacında Faz 6'da değerlendirilir. |
| PL power divider'ı erken ekleme | Reddedildi | İlk ratio PS/Python'da; PL divider yalnız ölçümle gerekçelenirse eklenir. |

Audit raporundaki süre, tipik switch izolasyonu ve kesin FFT latency gibi datasheet/IP konfigürasyonuna bağlı sayılar kabul kriteri yapılmamıştır. Bunlar seçilen switch datasheet'i ve üretilen FFT IP latency raporuyla ölçülmeden plan girdisi sayılmaz.

---

## 21. 2026-07-20 Σ/Δ monopulse mimari kapanışı

### 21.1 Kesinleşen platform ve laboratuvar düzeni

- Hedef kart değişmemiştir: AXU4EVB-P + mevcut AD9364.
- RF uyarımı yankısız odada Rohde & Schwarz SMW200A ve karşı verici antenle üretilecektir.
- Alıcı anten, BDC ve analog monopulse ön uç donanımının hazır sağlanacağı bildirilmiştir.
- Fotoğraftaki `AD-FMCOMMS3-EBZ`, `RX1A` ve `RX2A` bağlantıları AD9361 tabanlı eski/referans düzendir; hedef transceiver değildir.
- AD9364 tek gerçek RX içerdiği için eşzamanlı iki dijital kanal, kompleks kanal oranı veya doğrudan iki-kanal faz farkı mevcut kapsamda yoktur.
- Harici yol seçici `ZX80-DR230-S+`, phase shifter `EV1HMC936ALP6/HMC936ALP6E` olarak fotoğraf ve üretici datasheet'leriyle doğrulanmıştır.
- HMC936A yalnız 1.2-1.4 GHz'de derecelidir. BDC IF bu aralıkta doğrulanmadan harici RF zinciri uygun sayılmaz.

### 21.2 Bağlayıcı analog durumlar

```text
S0: ΔAZ seç + 0°   -> Σ + ΔAZ -> AD9364 -> FFT -> P_AZ_PLUS
S1: ΔAZ seç + 180° -> Σ - ΔAZ -> AD9364 -> FFT -> P_AZ_MINUS
S2: ΔEL seç + 0°   -> Σ + ΔEL -> AD9364 -> FFT -> P_EL_PLUS
S3: ΔEL seç + 180° -> Σ - ΔEL -> AD9364 -> FFT -> P_EL_MINUS
```

0°/180° phase switch anten açısı komutu değildir; seçilen Δ yolunun işaretini tersler. Tam kompleks faz açısı ölçülmez. Monopulse hata bilgisi `P_plus-P_minus = 4*Re{Σ*conj(Δ)}` çapraz teriminden çıkarılır.

### 21.3 Tek FFT ve ortak peak

İlk Candidate `Fs=30,72 MSPS`, runtime readback ile `BW=10 MHz` hedefi ve `N=2048` kullanır. Tek FFT dört finite-frame için sırayla kullanılır. CW modunda:

```text
P_REF[k] = P_AZ_PLUS[k] + P_AZ_MINUS[k]
         + P_EL_PLUS[k] + P_EL_MINUS[k]

k_peak = argmax(P_REF[k])
P_X = sum(P_X[k_peak-2 ... k_peak+2])
```

Peak yalnız yapılandırılmış RF penceresinde aranır ve DC guard bin'leri dışlanır. 5-10 MHz modülasyonlu sinyalde tek peak yerine yapılandırılmış FFT bandı boyunca güç toplanır.

### 21.4 PL scalar oran sonucu

```text
AZ_NUM = P_AZ_PLUS - P_AZ_MINUS
AZ_DEN = P_AZ_PLUS + P_AZ_MINUS
AZ_ERROR = AZ_NUM / AZ_DEN

EL_NUM = P_EL_PLUS - P_EL_MINUS
EL_DEN = P_EL_PLUS + P_EL_MINUS
EL_ERROR = EL_NUM / EL_DEN
```

Sonuçlar signed Q1.31'dir. Divider yalnız dört scalar güç üzerinde düşük throughput ile çalışır; bin-başına divider yoktur. `denominator_threshold` altında sonuç geçersizdir ve `denominator_small` raporlanır. Ham dört güç, pay/payda ve error sonuçları birlikte okunabilir olacaktır.

Bu karar, önceki “PL divider yalnız Faz 6'da” varsayımını ürün isterine göre dar kapsamda değiştirir: spectrum-bin oranı hâlâ kapsam dışıdır, ancak peak/band-power tabanlı scalar AZ/EL normalize divider dört-durum Candidate'ın parçasıdır. Divider uygulanmadan önce aynı aritmetik PS/Python referansıyla bit-doğru doğrulanacaktır.

### 21.5 Güncel iş paketleri

Python doğrulama iki katmanlıdır. Bare-metal/JTAG aşamasında NumPy oracle C/RTL ile aynı 2048-bin vektörleri işler; `pyadi-iio` gerçek donanım erişimi için kullanılmaz çünkü mevcut Candidate IIO context/IIOD sunmaz. PetaLinux veya eşdeğer IIOD ayağa kalktığında `adi.ad9361(uri=...)` üzerinden AD9364 RX parametreleri ve kompleks örnek yakalama otomatikleştirilir.

- [ ] **Paket M0 — Kaynak ve Golden regresyonu:** Paket 1'deki aktif Tcl/XDC, clean build, manifest/tag ve Golden doğrulamalarını tamamla.
- [ ] **Paket M1 — RX/TX güvenlik ve format kapısı:** Paket 2'deki I0/Q0, runtime Fs/BW/LO/gain, TX DAC ZERO/89.750 mdB ve DMA regresyon kanıtlarını tamamla.
- [x] **Paket M2 — Non-blocking finite capture:** CDC mailbox, store-and-forward capture, AXI replay, abort/reset/epoch recovery ve backpressure testleri RTL'de tamamlandı; fiziksel DMA-shadow korelasyonu M3 kart kapısında yapılacak.
- [x] **Paket M3 — Tek-kare FFT sayısal kapanışı:** Rectangular-first FFT `0x6AB`, magnitude-square, tam 2048-bin spectrum BRAM, `PEAK_BIN/POWER/RE/IM` ve metadata gerçek xFFT modeliyle bit-doğru kapatıldı; kart üstü aynı-frame kabulü açık.
- [ ] **Paket M4 — Peak/band-power ve sürekli mod:** Beklenen pencere, DC guard, ortak `P_REF`, ±2 bin CW integrasyonu ve configured band-power testlerini ekle; ardından atomik ping-pong bank ownership, continuous frame ve overrun/throughput testlerini kapat.
- [ ] **Paket M5 — Harici kontrol elektriksel kapısı:** ZX80 ve HMC936A model doğrulaması tamamlandı. BDC IF, RF1/RF2 kablo eşlemesi, ZX80 beslemesi, HMC altı-bit 5 V level-shifter, sekiz FPGA pini ve ölçülmüş settle/discard değerlerini kapat.
- [ ] **Paket M6 — Dört durumlu FSM ve scalar oran:** S0-S3 kontrolü, settle/discard, dört spectrum/güç sonucu, Q1.31 AZ/EL divider ve hata status'larını ekle.
- [ ] **Paket M7 — Yankısız oda kalibrasyonu:** SMW200A CW ile güç doğruluğu, mekanik sıfır, `-θ/0/+θ`, simetri, eğim ve tekrar edilebilirlik raporunu üret.
- [ ] **Paket M8 — Candidate release:** Timing/DRC, Golden DMA regresyonu ve fiziksel kabul geçince yeni değişmez release üret; eski Golden üzerine yazma.

### 21.6 Ölçüm kabul özeti

- Dört durumda sample drop, FFT overflow ve clipping sıfır olmalıdır.
- Ortak taşıyıcı dört durumda bulunmalı; peak bin farkı en fazla ±1 bin olmalıdır.
- Ölçüm çevriminde LO, sample-rate, bandwidth ve MGC değişmemelidir.
- Mekanik `+θ` ile `-θ` düzeltilmiş hata işaretleri ters olmalıdır.
- Sıfır biası ve AZ/EL eğimleri yankısız oda kalibrasyon artefaktında saklanmalıdır.
- Sayısal açı RMSE limiti ilk kalibrasyon verisi ve anten HPBW'si görülmeden uydurulmayacaktır; proje sahibi ölçülebilir kabul sınırını ayrıca onaylayacaktır.

## 22. PL FFT uygulama ilerlemesi — 21 Temmuz 2026

Bağlayıcı PL FFT alt-planında Tasks 1-5 tamamlanmıştır. Artık Candidate kaynak ağacında bit-doğru oracle, dondurulmuş vektörler, non-blocking 2048-sample capture/replay, exact magnitude/peak, sekiz RAMB36 kullanan çift spectrum bankası, reset-epoch korumalı command/result CDC mailbox'ları ve sabit AXI-Lite control/status bloğu bulunmaktadır.

CDC kabulü yalnız nominal transferle sınırlı değildir. Her iki yönde toggle wrap, epoch mismatch/recovery, reset-at-toggle-one, reset sırasında in-flight transfer, uzak resetin ready'ye yansıma gecikmesi ve hedef tesliminden sonra source ack öncesi reset senaryoları exactly-once davranışıyla geçmektedir. AXI-Lite kabulü bağımsız AW/W, byte strobe, B/R backpressure, RO koruması, one-shot pulse, persistent mode, W1C ve coincident event-wins-clear davranışlarını kapsar.

Bu kapanış analog S0-S3 kontrolünü veya harici ZX80/HMC936A sürüşünü uygulamaz; onlar mevcut nihai plandaki sonraki iş paketlerinde kalır. Bir sonraki dijital adım FFT v9.1 IP ayarlarını kaynak kontrollü Candidate üretimine bağlamak, ardından üst seviye shadow-path entegrasyonu ve bit-doğru uçtan uca regresyondur.

## 23. FFT v9.1 kaynak sözleşmesi — 22 Temmuz 2026

Task 6 ile FFT v9.1 üretimi GUI'den ayrılmış ve Tcl-only Candidate sözleşmesine bağlanmıştır. IP ayarları gerçek Vivado property readback ile doğrulanır. Runtime transform length kapalı, transform direction forward ve scaled schedule `0x6AB`'dır. Tek kanallı AXIS config taşıması `16'h0D57` packed sözcüğünü reset sonrası/ilk frame öncesi bir kez gönderecektir.

Custom-IP paket manifesti top-level dahil sekiz RTL kaynağını, AXI-Lite kontrolü, çift BRAM readout'u, ADC tap'i ve interrupt'ı açıkça tanımlar. Clock/reset associations eklenmiştir. Task 7 tamamlanana kadar eksik top/XCI durumunda kaynak dizinde proje üretmeden fail-fast kalır. Sonraki dijital kapı Task 7 üst-seviye single-shot veri yoludur; analog RF state kontrolü bu Task 6 kapsamına alınmamıştır.

## 24. Task 7 tek-kare FFT uygulama kapanışı — 22 Temmuz 2026

Tek-kare Candidate veri yolu tamamlandı: geri basınçsız AD9364 I0/Q0 shadow capture, 2048-word replay, gerçek FFT v9.1, 33-bit magnitude-square ve peak, çift 2048×64 spectrum bankası, sabit AXI-Lite status ve atomik command/result CDC aynı custom IP altında çalışmaktadır. Komut RF etiketi sonuç metadata'sı için otoritatiftir.

Kabul yalnız nominal spektruma dayanmaz. Abort ve soft-reset xFFT/replay/magnitude yolunu deterministik recovery state'ine alır; core en az üç ADC clock resetlenir ve `16'h0D57` yeniden handshaking yapılmadan yeni START kabul edilmez. Dolu single-shot bank yeni replay başlamadan reddedilir. FFT error, overflow, dropped sample, stale epoch, frame error ve bank overrun CPU'ya atomik result flags ile taşınır; STATUS W1C ve IRQ kalan sticky nedenleri korur.

Altı deterministik vektörün tüm 2048 kompleks FFT bileşeni ve 2048 güç kelimesi gerçek Vivado xFFT modeliyle sıfır LSB farkla geçmiştir. BRAM kabulü `RAMB36=8`, `RAMB18=0`, `LUT_AS_MEMORY=0`'dır. Bu kapanış RTL/simülasyon ve paket sözleşmesidir; AXU4EV block-design bağlantısı, timing/DRC, DMA ile aynı-frame CRC korelasyonu ve fiziksel RF kabulü sonraki paketlerde açık kalır.

## 25. Bare-metal Python laboratuvar görünümü — 27 Temmuz 2026

Periyodik Candidate'ın 100-frame kart kabulünden sonra tam spectrumun kullanıcı
tarafından görülebilir ve kaydedilebilir olması yeni ara teslim olarak
seçilmiştir. Ürün mimarisi değiştirilmemiştir: AXU4EVB-P + AD9364, tek 2048
noktalı FFT ve sonraki S0-S3 monopulse zinciri korunur.

Yeni `monopulse-live-lab-v1` Candidate:

- `PL_FFT_LAB_UART` compile-time modu kullanır.
- `GET_INFO` ve `CAPTURE_ONCE` komutlarını kabul eder.
- `INFO`, `SPECTRUM` veya `ERROR` yanıtı üretir.
- Tam 2048 adet `uint64` güç binini frame/peak/RF metadata ile taşır.
- Mesajı CRC-32/ISO-HDLC ve protocol sequence ile korur.
- UART'ta `115200-8-N-1` kullanır.
- Python tarafında spectrum, waterfall, peak ve sağlık görünümü üretir.
- Tam frame'i NPZ, özetini CSV olarak saklar.

İlk kontrollü CW kabulü, en az 10 ardışık CRC-valid frame, exact 2048 bin,
`±1` peak-bin kararlılığı ve sıfır fatal donanım bayrağı ister. Bu kabul
monopulse açı kabulü değildir.

M4 güncel alt ayrımı:

- [x] Tek-frame exact peak ve tam spectrum altyapısı.
- [x] 100 kez host-tetiklemeli periodic monitor transport/control kart kabulü.
- [x] CRC korumalı UART lab protocol, bare-metal `GET_INFO`/`CAPTURE_ONCE`
  servisi ve Python spectrum/waterfall görünümü.
- [x] NPZ tam-frame ve CSV özet kayıt yolu.
- [x] Değişmez `monopulse-live-lab-v1` Candidate paketi ve ayrı JTAG
  başlatıcısı.
- [ ] Kontrollü CW peak/power kart kabulü.
- [ ] Dört gerçek RF state üzerinde ortak `P_REF` ve CW/band-power çevrimi.

M5-M8 değişmez:

- M5 fiziksel ZX80/HMC936 elektriksel/pin sözleşmesi.
- M6 S0-S3 FSM, state-tag, dört güç ve Q1.31 AZ/EL.
- M7 SMW200A/yankısız oda kalibrasyonu.
- M8 Candidate release kapanışı.

Bağlayıcı ayrıntılar:

- `PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-monopulse-lab-design.md`
- `PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-lab-implementation-plan.md`

### 25.1 27 Temmuz yazılım teslim durumu

M4 laboratuvar yazılımı ve paketleme adımları tamamlanmıştır. Candidate
uygulaması 2048 adet `uint64` güç binini frame/peak/RF metadata ile birlikte
CRC-32/ISO-HDLC korumalı mesajda taşır. Python istemcisi wire sözleşmesini
byte-exact doğrular; spectrum, waterfall ve sağlık görünümünü üretir; geçerli
frame'i NPZ/CSV olarak saklar. Windows/Vitis 2020.1 üretimi kısa workspace,
kaynak temizliği ve tek sınırlı platform-generate retry kapılarıyla
sertleştirilmiştir.

Değişmez Candidate:

- Release: `monopulse-live-lab-v1`
- Uygulama SHA-256:
  `9DFC2355F5A4262AFFD1455EA3D0972A80F279E8804BD371DBCFDF38452FDC14`
- Bitstream SHA-256:
  `ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC`
- `board_verified=false`

`board_verified=false` bilinçlidir. Bu alan ancak SMW200A ile DC dışı kontrollü
CW testinde en az 10 ardışık CRC-valid, exact 2048-bin, sıfır fatal bayraklı ve
beklenen peak'in ±1 bin içinde kaldığı fiziksel kanıt üretildikten sonra yeni
bir release manifestinde `true` yapılacaktır.

ZX80-DR230-S+ ile EV1HMC936ALP6 bu yazılım Candidate'ına fiziksel olarak
entegre edilmiş sayılmaz. M5'te BDC IF, RF1/RF2 eşlemesi, ZX80 besleme/kontrol
seviyesi, HMC936 için 5 V level-shifter ve güvenli OE, sekiz FPGA pini/XDC ile
ölçülmüş settle/discard değerleri kapanmadan S0-S3 sürülmeyecektir.

M4 kontrollü CW kapısının yazılım önkoşulu hazırdır: `--frames 10` bounded
capture tek bir 10-frame NPZ/CSV serisi üretir; kanıt validator'u Candidate
hash'i, jeneratör/RF/AD9364 çalışma noktası, 2048-bin/CRC/flag/peak ve
NPZ-CSV kimliğini birlikte zorunlu tutar. Bu araçların fixture regresyonu
PASS'tir; gerçek SMW200A verisi bulunmadığı için M4 fiziksel checkbox'ı açık
kalmaya devam eder.

Yazılım handoff'u `3f0bcec`, CW kanıt preflight aracı `c920edc` commit'inde
kayıtlıdır.

## 26. Gain-lock v2 ve sunum öncesi bağlayıcı durum — 28 Temmuz 2026

M4 laboratuvar tesliminin güncel Candidate'ı `monopulse-live-lab-v2`'dir.
Tarihsel v1 değiştirilmemiştir.

### 26.1 Güncel RF/FFT sözleşmesi

| Alan | Değer |
|---|---|
| RF cihazı | AD9364 |
| Aktif fiziksel giriş | RXA / RX channel 0 / `A_BALANCED` |
| LO | `2.400000 GHz` |
| Sample rate | `30.72 MSPS` |
| RX bandwidth | `10 MHz` |
| Gain control | manual |
| RX gain | `50 dB` |
| FFT | 2048 nokta, natural order |
| Bin aralığı | `15 kHz` |
| Protokol | v2, CRC-32/ISO-HDLC |
| Candidate durumu | `board_verified=false` |

Firmware başlangıçta ve her frame öncesinde gain modunu/değerini geri okur.
Python, NPZ/CSV ve evidence validator aynı frame serisinde gain değişimini
reddeder.

### 26.2 M4'ün açık fiziksel kapısı

- [x] Protocol v2 ve gain telemetrisi.
- [x] Vitis 2020.1 A53 Release ELF.
- [x] Immutable Candidate ve SHA-256 paket kapısı.
- [x] RXA laboratuvar bağlantı sözleşmesi.
- [ ] Kartta protocol-v2 READY satırı.
- [ ] SMW200A ile bin-hizalı kontrollü CW.
- [ ] 100 ardışık frame evidence kabulü.
- [ ] Yalnız yeni fiziksel kanıtlı release için `board_verified=true`.

İlk test noktası `2.400300 GHz` (`LO + 300 kHz`, bin 20), alternatif test
noktası `2.401500 GHz` (`LO + 1.5 MHz`, bin 100)'dür. Fiziksel yol onaylı
attenuator ve 50 ohm kablo üzerinden RXA'ya bağlanır. Ölçülen güç kalibre
edilene kadar bağıl FFT gücüdür.

### 26.3 M5-M8 sınırı

ZX80-DR230-S+ ve EV1HMC936ALP6 nihai mimaride kalır; ancak güncel v2
Candidate tarafından sürülmez. BDC IF, besleme/kontrol seviyeleri, 5 V
level-shifter/OE, sekiz FPGA pini/XDC, RF1/RF2 kablo eşlemesi ve ölçülmüş
settle/discard değerleri kapanmadan S0-S3 fiziksel kontrolü başlatılmaz.

Sunumda M1-M4'ün tamamlanan dijital/bring-up bölümü ile M4'ün açık CW kapısı ve
M5-M8'in gelecek işleri ayrı renk/durum etiketiyle gösterilecektir.
