# Proje Durum Raporu — AXU4EVB-P + AD9364

**Son güncelleme:** 27 Temmuz 2026

**Ana hedef:** ALINX AXU4EVB-P üzerinde AD9364/FMCOMMS ailesi ile doğrulanmış FPGA donanım platformu ve bare-metal yazılım zinciri oluşturmak.

**Mevcut aşama:** Vivado/Vitis kapanışı, PMUFW içeren JTAG başlatma ve temel bare-metal kart bring-up'ı tamamlandı. Tek AD9364 RX, dört analog Σ/Δ durumu ve tek 2048-point FFT kullanan monopulse Candidate tasarımı onaylandı. 21 Temmuz inceleme uzlaştırmasıyla tam 2048-bin spektrum, peak diagnostikleri, tek-kare ve ping-pong sürekli frame modları bağlayıcı hale getirildi; sıradaki ana aşama kaynak/Golden regresyonu ile RX/IQ format kapısıdır.

## 21. Bare-metal Python laboratuvar ekranı tasarımı — 27 Temmuz 2026

Durum: **Tasarım onaylandı; uygulama planı hazır, kodlama başlamadı.**

Kartta kabul edilen PL FFT altyapısının sonuçlarını doğrudan gözlemlemek için
PetaLinux/IIO eklemeden bare-metal + Python yaklaşımı seçildi. Yeni teslim ayrı
`monopulse-live-lab-v1` Candidate olacaktır. Mevcut Golden,
`fft-single-shot-v1` ve `fft-periodic-monitor-v1` değişmeden korunacaktır.

Seçilen veri yolu:

```text
AD9364 I0/Q0
  -> non-blocking 2048-sample shadow capture
  -> xFFT v9.1 + magnitude-square + peak
  -> atomik spectrum BRAM
  -> A53 bare-metal UART servisi
  -> CRC-32 korumalı 2048-bin binary paket
  -> Python/NumPy/Matplotlib laboratuvar ekranı
```

İlk ekran; canlı spectrum, son 32 frame waterfall, peak bin/RF frekansı,
relative peak power, LO/Fs/BW, frame ID, RF state, CRC ve donanım sağlık
bayraklarını gösterecektir. Tam frame `.npz`, aynı frame'in özeti `.csv`
olarak kaydedilecektir. UART `115200-8-N-1` kalacak; yaklaşık 16 KiB spectrum
paketi nedeniyle beklenen görüntü yenileme hızı yaklaşık 1,5-2 saniyedir.
Ethernet yalnız gelecekte aynı mesaj codec'ine bağlanabilecek taşıma adaptörü
olarak bırakılmış, bu staj tesliminin kapsamına alınmamıştır.

ZX80-DR230-S+ ve EV1HMC936ALP6 nihai ürün kapsamından çıkarılmamıştır.
Python/FFT tesliminden sonra fiziksel RF kontrol işi şu sırayla devam edecektir:

1. BDC IF, RF1/RF2 kablo takibi, ZX80 VDD, HMC 5 V level-shifter ve sekiz
   FPGA pininin elektriksel sözleşmesini kapatmak.
2. S0-S3 durumlarını fiziksel switch/phase kodlarıyla sürmek.
3. Her FFT frame'ini gerçek RF state etiketiyle atomik eşlemek.
4. Dört spectrumdan ortak CW peak veya configured band-power üretmek.
5. Q1.31 AZ/EL normalize hatalarını hesaplamak.
6. SMW200A ile phase-code, mekanik sıfır ve `-theta/0/+theta` kalibrasyonu
   yapmak.

Bağlayıcı tasarım:

`PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-monopulse-lab-design.md`

Test-first uygulama planı:

`PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-lab-implementation-plan.md`

Bu aşama henüz RF performans, DOA veya açı kalibrasyonu PASS iddiası taşımaz.
Bir sonraki yazılım teslimi UART protocol golden-byte testleriyle başlayacaktır.

## 20. Periodic FFT monitor Candidate status - 27 July 2026

Status: **physical monitor transport/control acceptance passed.** One fresh
AXU4EVB-P + AD9364 run launched from
`b0f53f36f8676b54747d417c4ae44c61ac8a3c99` recorded AD9364 initialization,
the exact START contract, 100 valid ordered FRAME records, and final PASS.
The committed raw PS-UART evidence (`115200-8-N-1`) is
`PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-raw-putty.log`;
the committed JTAG launch evidence is
`PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-jtag-launch.log`.
The strict validator invoked with `-LogPath` returned `PASS: periodic FFT monitor log contains 100 valid frames.`
The committed evidence file binds this run to the Candidate ELF and bitstream
hashes, and `board_verified=true` is now accepted only when that committed
evidence passes the strict parser.

Scope limit: no controlled CW/R&S source was declared and observed peak powers
were low/ambient-noise; antenna/port wiring was not independently reverified.
This accepts monitor transport/control, not RF performance, DOA, calibration,
or antenna wiring.

Historical preflight status: **software-ready; physical-board acceptance was open.** The separately
packaged `fft-periodic-monitor-v1` Candidate targets AXU4EVB-P + AD9364
(`xczu4ev-sfvc784-1-i`, tool version 2020.1; manifest source commit
`65ff6144ee9cf02cacfe8840ad506611c17806ac`). It is built/packaged and the
nine-command host/preflight suite passed fresh, including the package,
launcher, parser, JTAG-order, and release-integrity gates.

The manifest now records `board_verified=true` with committed physical monitor
evidence. The periodic application ELF SHA-256
is `0586E9A18EA4457A622CEE84D33F81A6402C95FB12A64755D2A7C39441964002`; the
bitstream, PMUFW, `psu_init.tcl`, and XSA remain hardware-identical to the
accepted single-shot Candidate with hashes `ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC`,
`9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB`,
`CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B`, and
`672A431A3698DFB841AD0F09A8605CD1D125314FCB6333E49A60727E8B42E574`.

The historical next operator action was to open PuTTY on the PS UART at 115200-8-N-1, run
`PROJECT\tools\Start-Axu4evAd9364PeriodicMonitor.cmd`, save its complete
output, and validate it with
`PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 -LogPath <putty-log-path>`.
The test requires the exact START/PASS contract, 100 ordered valid frame lines,
and no FAIL record. That run has now passed; the resulting evidence remains
subject to the package gate described above.

## 1. Yönetici özeti

Aktif proje, Analog Devices HDL ağacındaki aşağıdaki AXU4EV uyarlamasıdır:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.xpr`

Hedef FPGA `xczu4ev-sfvc784-1-i`, üst modül `system_top`, etkin kısıt dosyası `system_constr.xdc` olarak doğrulandı. AXU4EVB-P ve AD9364 şemaları esas alınarak kritik LVDS pin eşlemeleri düzeltildi; elektriksel özellikler ve RX saat tanımı tamamlandı. Vivado 2020.1 ile temiz bir sentez, implementasyon ve bitstream üretimi gerçekleştirildi. Aynı implementasyondan XSA çıkarıldı, Vitis platformu yenilendi, FSBL ile AD9364 bare-metal uygulaması derlendi ve teslim zincirindeki dosyaların bütünlüğü hash karşılaştırmalarıyla doğrulandı. Uygulama JTAG üzerinden kartta çalıştırıldı; UART kaydı AD9364 Rev 2 başlatmasının, AXI çekirdeklerinin ve ilk DMA aktarımının başarıyla tamamlandığını gösterdi.

Markdown belgeleri yardımcı kayıt niteliğindedir. Çelişki halinde şemalar, etkin Vivado projesi, üretilen raporlar ve derleme çıktıları önceliklidir.

## 2. Tamamlanan adımlar

- [x] AXU4EVB-P + AD9364/FMCOMMS hedef mimarisi doğrulandı.
- [x] Aktif Vivado projesi, FPGA parçası, üst modül ve etkin XDC tespit edildi.
- [x] Kart ve RF modülü şemaları üzerinden kritik FMC/LVDS pinleri çapraz kontrol edildi.
- [x] `RX_FRAME` pinleri L7/L6, `TX_CLK/FB_CLK` pinleri N7/N6 olacak şekilde düzeltildi.
- [x] On altı RX LVDS portuna `DIFF_TERM_ADV TERM_100` eklendi.
- [x] SPI chip-select hattına pull-up özelliği eklendi.
- [x] `rx_clk` için 4,00 ns (250 MHz) saat kısıtı eklendi.
- [x] Kısıt regresyon testi önce hataları gösterdi, düzeltmelerden sonra tamamen geçti.
- [x] Vivado 2020.1 sentez, implementasyon ve bitstream üretimi tamamlandı.
- [x] Zamanlama kapanışı ve DRC sonuçları raporlandı.
- [x] Bitstream içeren güncel XSA dışa aktarıldı.
- [x] Vivado, doğrulama klasörü ve Vitis içindeki XSA kopyalarının aynı olduğu doğrulandı.
- [x] Vitis donanım platformu güncel XSA ile yeniden oluşturuldu.
- [x] `Out-of-date` platform durumu incelendi; PMU firmware hedefi `psu_pmu_0`/`mb-gcc` olarak düzeltildi ve XPFM yeniden üretildi.
- [x] FSBL'nin OCM taşması teşhis edildi; uygulama ve BSP için bölüm bazlı derleme seçenekleriyle çözüldü.
- [x] FSBL ELF üretildi ve dışa aktarılan kopyasıyla hash eşitliği doğrulandı.
- [x] `ad9364app` içindeki eski `sdr_wrapper` platform bağlantıları temizlendi.
- [x] Uygulama `fmcomms2_axu4ev_hw / standalone_domain` hedefine bağlandı.
- [x] Release include/library ayarları düzeltildi; `libm` bağlantısı sağlandı.
- [x] Kaynak yapılandırmasında AD9364 seçimi (`AD9361_DEVICE 0`, `AD9364_DEVICE 1`) doğrulandı.
- [x] AArch64 Release ELF başarıyla üretildi.
- [x] IDE bitstream ve `psu_init` dosyaları güncel platformla eşitlendi.
- [x] Güncel bitstream, FSBL ve `ad9364app.elf` JTAG üzerinden kartta çalıştırıldı.
- [x] PS_UART üzerinde AD936x Rev 2 başlatması ve AXI ADC/DDS initialization mesajları kaydedildi.
- [x] DMA örneği 65.536 örnek, 2 kanal ve 16 bit ile `Done.` sonucuna ulaştı.
- [x] Tekrarlanabilir denetim ve derleme betikleri `PROJECT/tests` altında kalıcı hale getirildi.

## 3. Vivado kapanış sonuçları

| Kontrol | Sonuç |
|---|---:|
| Setup WNS | 0,144 ns |
| Setup TNS | 0,000 ns |
| Hold WHS | 0,010 ns |
| Hold THS | 0,000 ns |
| Yönlendirilmemiş ağ | 0 |
| DRC hata sayısı | 0 |
| `rx_clk` frekansı | 250 MHz |
| `rx_clk` endpoint sayısı | 16.657 |
| `rx_clk` WNS / WHS | 1,098 ns / 0,013 ns |

Kalan Vivado uyarıları iki `REQP-1853` ve bir `RTSTAT-10` uyarısıdır; bitstream üretimini veya zamanlama kapanışını engellememiştir.

### Bilinçli olarak açık bırakılan zamanlama sınırı

Kart üstü harici gecikmeler için ölçülmüş/veri sayfasından türetilmiş güvenilir değer bulunmadığından yapay `set_input_delay` veya `set_output_delay` değerleri eklenmedi. `check_timing` raporundaki kalan kapsam şudur:

- 1 `no_clock`: PS8 `EMIOSPI0SCLKO`
- 1 `unconstrained_internal`: PS8 `EMIOSPI0MI`
- 8 `no_input_delay`: RX veri p[0..5], RX frame p ve `spi_miso`
- 13 `no_output_delay`: enable, SPI çıkışları, TX clock/data/frame ve `txnrx`

Bu maddeler, kart üstü ölçüm veya doğrulanmış arayüz zamanlama bütçesi elde edildiğinde ele alınmalıdır; mevcut durumda gizlenmemiş bir doğrulama sınırı olarak kaydedilmiştir.

## 4. Üretilen ve doğrulanan teslimler

| Teslim | Konum | SHA-256 |
|---|---|---|
| Bitstream | `Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.runs/impl_1/system_top.bit` | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| XSA | `PROJECT/verification/vivado/system_top.xsa` | `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118` |
| FSBL ELF | `Vitis/workspace/fmcomms2_axu4ev_hw/zynqmp_fsbl/executable.elf` | `C8EC16594420C96D0EDC5B64036BA9653C338C33BBD23C59AEC168F09470AC21` |
| PMU firmware ELF | `Vitis/workspace/fmcomms2_axu4ev_hw/zynqmp_pmufw/executable.elf` | `F4D1FC0B82A64555883C79063278863654CEF80167826F2BB3541967B82FEF98` |
| XPFM | `Vitis/workspace/fmcomms2_axu4ev_hw/export/fmcomms2_axu4ev_hw/fmcomms2_axu4ev_hw.xpfm` | `C85BBEBB5C3A76C5AA7D748BCCBF578269C319EE6091D750161039FFC4BA47D5` |
| AD9364 uygulama ELF | `Vitis/workspace/ad9364app/Release/ad9364app.elf` | `A9B5B372C4E79FD263752F0C10B9162D01A32EC1CA114B0B4C98F6F5E293D5F7` |

Vivado SDK, `PROJECT/verification` ve Vitis platformundaki XSA kopyaları bit düzeyinde aynıdır. XSA içine gömülü bitstream de implementasyon çıktısıyla eşleşmektedir. Uygulama ELF'i 64-bit AArch64 çalıştırılabilir dosyasıdır.

## 5. Mevcut riskler ve doğrulama sınırları

- Fiziksel kartta FSBL geçişi, SPI üzerinden AD9364 Rev 2 başlatması, AXI çekirdek initialization ve DMA tamamlanması kanıtlandı; ancak DMA'nın tamamlanması yakalanan I/Q verisinin doğru veya RF performansının yeterli olduğunu tek başına kanıtlamaz.
- PMUFW artık JTAG üzerinden FSBL'den önce yüklenmektedir ve önceki `PMU-FW is not running` uyarısı kaldırılmıştır. Bu akışın sırası kalıcı XSCT betiğiyle korunmaktadır.
- Harici I/O gecikmeleri ölçülmeden zamanlama modeli kart seviyesinde tam kapanmış sayılmamalıdır.
- Anten, attenuator, LO frekansı, örnekleme hızı ve güvenli TX güç seviyesi ilk testten önce kontrollü seçilmelidir.
- PetaLinux/IIO entegrasyonu ve FPGA içinde FFT/spektrum işleme mevcut bare-metal bring-up zincirinden sonraki aşamalardır.
- Çalışma ağacında kullanıcıya ait başka değişiklikler bulunduğundan bunlar korunmuş, bu çalışma kapsamında geri alınmamış veya commit edilmemiştir.

## 6. Sıradaki adımlar

### Aşama 7 — Kart üzerinde ilk çalıştırma — temel smoke-test tamamlandı

- [ ] Kart revizyonu, FMC modülü, güç kaynakları, jumper/switch ve boot modunun fiziksel kontrolü yazılı veya fotoğraflı kayda alınacak.
- [x] JTAG bağlantısı ve 115200-8-N-1 UART terminali doğrulandı.
- [x] Güncel bitstream programlandı.
- [x] Güncel FSBL ve `ad9364app.elf` yüklenerek kontrollü başlatma yapıldı.
- [x] UART logunda FSBL geçişi ve uygulama çıktısı kaydedildi.
- [x] SPI üzerinden AD9364 Rev 2 kimliği ve initialization sonucu doğrulandı.
- [x] AXI ADC/DDS çekirdekleri başlatıldı ve ilk DMA aktarımı tamamlandı.
- [x] JTAG akışına PMU firmware eklendi ve PMUFW uyarısı kaldırıldı.
- [ ] Referans saat/LO kilit durumu ve ayrıntılı kalibrasyon sonuçları ayrıca kaydedilecek.
- [ ] Önce RX-only güvenli test uygulanacak; bilinen RF kaynak veya loopback ile örnek akışı doğrulanacak.
- [ ] DMA tamponu, örnek düzeni, I/Q polaritesi ve veri sürekliliği kontrol edilecek.
- [ ] TX testi gerekiyorsa düşük güç, uygun attenuator ve spektrum analizörüyle ayrı güvenlik kapısından sonra yapılacak.
- [ ] Kart üstü bulgular, UART kayıtları ve ölçümler raporlara eklenecek.

### Aşama 8 — RF işleme ve spektrum

- [x] Hedef mimari AXU4EVB-P + mevcut AD9364 olarak korundu; AD9361/FMCOMMS3'e geçiş reddedildi.
- [x] İlk profil 30,72 MSPS, runtime 10 MHz RX bandwidth readback hedefi ve 2048-point tek FFT olarak seçildi.
- [x] Analog durumlar `Σ+ΔAZ`, `Σ-ΔAZ`, `Σ+ΔEL`, `Σ-ΔEL` olarak tanımlandı.
- [x] CW common-peak, modülasyonlu sinyal configured band-power ve Q1.31 AZ/EL normalize oran sözleşmesi tasarlandı.
- [ ] AD9364 I0/Q0 formatı ve mevcut DMAC izolasyonu ILA/DMA ile doğrulanacak.
- [x] Store-and-forward capture, gerçek xFFT v9.1, magnitude-square, tam 2048-bin spectrum ve ortak peak yolu test-first tamamlandı; block-design/kart entegrasyonu açık.
- [ ] SPDT/0°-180° phase switch pin, gerilim, polarite ve settle değerleri gerçek donanımla doğrulanacak.
- [ ] SMW200A ile yankısız odada mekanik sıfır ve `-θ/0/+θ` kalibrasyonu yapılacak.
- [ ] Timing/DRC, Golden DMA regresyonu ve kart kabulü tamamlanacak.

### Aşama 9 — İsteğe bağlı Linux/PetaLinux

- [ ] Donanım bring-up kararlı hale geldikten sonra güncel XSA ile PetaLinux platformu oluşturulacak.
- [ ] AD936x IIO sürücüsü, device tree, DMA ve clock tanımları doğrulanacak.
- [ ] IIO üzerinden RX/TX veri yolu ve kullanıcı alanı araçları test edilecek.

## 7. Tekrarlanabilir doğrulama araçları

Kalıcı betikler `PROJECT/tests` klasöründedir:

- `Test-Axu4evAd9364Constraints.ps1`
- `Inspect-Axu4evAd9364Project.tcl`
- `Build-Axu4evAd9364Bitstream.tcl`
- `Export-Axu4evAd9364Xsa.tcl`
- `Update-Axu4evVitisPlatform.tcl`
- `Fix-Axu4evFsblBuild.tcl`
- `Build-Axu4evAd9364App.tcl`
- `Sync-Axu4evAd9364IdeHardware.ps1`
- `Test-Axu4evHandoffArtifacts.ps1`
- `Launch-Axu4evAd9364Jtag.tcl`
- `Test-Axu4evJtagLaunchScript.ps1`

Son taze doğrulamada kısıt regresyonu ve teslim bütünlüğü testleri geçti; zamanlama değerleri yukarıdaki sonuçlarla eşleşti ve DRC hata sayısı sıfır kaldı. PMUFW, FPGA, FSBL ve uygulama sırasıyla JTAG üzerinden başlatıldı; önceki PMUFW uyarısı tekrar oluşmadı. Kart smoke-test'inde AD936x Rev 2 başarıyla başlatıldı, AXI ADC/DDS çekirdekleri yaklaşık 61,44 MHz değerleriyle hazırlandı ve 65.536 örneklik iki kanallı 16-bit DMA işlemi `Done.` ile tamamlandı. RF/IQ örnek bütünlüğü doğrulaması açık iş olarak korunmaktadır.

## 8. 16 Temmuz 2026 kart tekrar-doğrulaması ve geçerli başlatma yolu

Bu bölüm, yukarıdaki FSBL tabanlı başlatma ve eski artifact hash kayıtlarını güncel çalışma alanı açısından geçersiz kılar. Mevcut FSBL kartta SerDes/PCIe kalibrasyonunda kalmış, DDR handoff tamamlanmadığı için uygulamanın `0x0` adresine indirilmesi önce başarısız olmuştur. FSBL atlanıp yalnızca `psu_init` çalıştırıldığında DDR testi geçmiş; ancak boş olan `psu_post_config` PS–PL sınırını hazırlamadığı için AD9364 ürün kimliği `0x00` okunmuştur.

Doğrulanmış çözüm; PMUFW → FPGA → A53 reset → `psu_init` → `psu_ps_pl_isolation_removal` → `psu_ps_pl_reset_config` → DDR testi → uygulama sırasıdır. DDR'de `0x00100000` adresine yazılan `A5A5A5A5` doğru okunmuş, ardından Debug uygulama ELF'i başarıyla çalışmıştır. UART sonucu AD9364 Rev 2 başlangıcını, yaklaşık 61,44 MHz AXI ADC/DDS saatlerini ve `address=0x60c00` adresindeki 65.536 örnekli DMA işleminin `Done.` ile tamamlandığını göstermiştir.

Geçerli kart-smoke-test teslimleri:

| Teslim | SHA-256 |
|---|---|
| Bitstream | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| XSA | `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118` |
| PMUFW ELF | `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB` |
| `psu_init.tcl` | `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B` |
| Debug uygulama ELF | `320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC` |

Kalıcı XSCT betiği stale FSBL'yi artık kullanmaz, Release bulunmadığında Debug ELF'e düşer ve kartta doğrulanan iki PS–PL prosedürünü zorunlu sırada çalıştırır.

## 9. Yeniden başlatılabilir proje paketi — 16 Temmuz 2026

Durum: **Golden otomatik başlatma ve kart kabulü tamamlandı.**

Seçili sürüm `2026-07-16-bringup-v1` olarak `PROJECT/releases/axu4ev-ad9364/CURRENT` dosyasına kaydedildi. Sürümdeki beş teslim manifest boyutu ve SHA-256 değeriyle doğrulanmadan JTAG programlama başlamaz. Golden ve Workspace kuru çalışmaları doğru dört çalıştırma girdisini seçmiş; release bütünlüğü, Vitis handoff bütünlüğü, XSCT yol bağımsızlığı, PMUFW/FPGA/PS–PL/DDR/uygulama sırası ve çift tıklama başlatıcı sözleşmeleri otomatik testlerden geçmiştir.

Günlük kullanım:

1. JTAG ve PS_UART bağlanır; PuTTY `115200-8-N-1` açılır.
2. Normal açılış için `PROJECT/tools/Start-Axu4evAd9364Golden.cmd` çift tıklanır.
3. `AD936x Rev 2 successfully initialized`, `DMA_EXAMPLE:` ve `Done.` UART'ta aranır.
4. Yeni derlemeler yalnızca Workspace başlatıcısıyla aday olarak denenir.
5. Başarılı aday değişmez yeni sürüme terfi ettirilir; `CURRENT` daha sonra ayrı komutla seçilir.

Çalışma logları `PROJECT/logs/jtag` altında tutulur ve Git tarafından yok sayılır. Mevcut Golden sürüm gelecekteki RF/anten ölçümleri için bilinen-iyi geri dönüş noktasıdır. PetaLinux geçişinde aynı sürümün doğrulanmış XSA'sı ilk donanım referansı olarak korunacaktır.

### Golden kart kabulü

16 Temmuz 2026 tarihinde `2026-07-16-bringup-v1` sürümü `Start-Axu4evAd9364Golden.cmd` üzerinden, manuel XSCT komutu girilmeden çalıştırıldı. JTAG tarafında PMUFW ve FPGA programlama tamamlandı; doğrudan PS/DDR/PS–PL başlangıcı geçti ve DDR `A5A5A5A5` doğrulaması uygulama indirilmeden önce başarı verdi. Çalışma logu: `PROJECT/logs/jtag/20260716-120323-golden.log`.

UART kabul kanıtı:

```text
cf-ad9361-lpc: Successfully initialized (61439514 Hz)
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized (61439514 Hz)
DMA_EXAMPLE: address=0x60c00 samples=65536 channels=2 bits=16
Done.
```

Kabul edilen değişmez sürümün SHA-256 değerleri:

| Teslim | SHA-256 |
|---|---|
| Bitstream | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| XSA | `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118` |
| PMUFW ELF | `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB` |
| `psu_init.tcl` | `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B` |
| `ad9364app.elf` | `320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC` |

Sonuç olarak bilgisayar/kart yeniden açıldıktan sonra kullanılacak normal yol Golden başlatıcıdır; XSCT komutlarının elle tekrarlanması gerekmemektedir.

## 10. Main entegrasyonu ve GitHub yayını

Durum: **Tamamlandı.**

Golden kart kabulünden sonra `codex/axu4ev-pmufw-bringup` üzerindeki doğrulanmış 14 commit yerel `main` dalına fast-forward edildi. İşlem çatışmasız tamamlandı; `main` ve HEAD `9d2f06a` commitinde eşleşti. Entegrasyon sonrasında beş otomatik test yeniden geçti.

Yerel `main`, `https://github.com/Maxixler/FPGA-Profen.git` deposundaki `origin/main` dalına pushlandı. GitHub doğrulamasında uzak referans şu değeri verdi:

```text
9d2f06acca380778cae29ddaf4bbf327048e15b5 refs/heads/main
```

Push aralığı `6b78d06..9d2f06a` oldu. Çalışma alanındaki kullanıcıya ait 1081 staged dosya, untracked Vitis/Vivado çıktıları ve runtime JTAG logu push kapsamına girmedi. Böylece GitHub `main`, kartta doğrulanmış Golden release, otomatik başlatıcılar, bütünlük testleri ve kabul raporlarını içerirken yerel geliştirme çıktıları korunmuştur.

## 11. 20 Temmuz 2026 monopulse tasarım durumu

Durum: **Tasarım onaylandı; uygulama başlamadı.**

Yeni bağlayıcı tasarım belgesi:

`PROJECT/designs/2026-07-20-axu4ev-ad9364-single-channel-monopulse-design.md`

Kullanıcının paylaştığı şema ana ürün mimarisi, IEEE Access makalesi ise yalnız referans olarak kabul edildi. Şemadaki analog ön uç SPDT ile ΔAZ/ΔEL seçer, seçilen Δ yolunu 0°/180° çevirir ve Σ ile birleştirir. AD9364'e tek birleşik hat geldiği için dört finite-frame zaman bölüşümlü yakalanır; iki eşzamanlı dijital RX veya tam kompleks faz farkı iddiası yapılmaz.

Yankısız oda fotoğrafları SMW200A, döner anten, X-band BDC ve önceki ADI düzenini gösterdi. Yakın çekimde `AD-FMCOMMS3-EBZ`, `RX1A` ve `RX2A` doğrulandı; bunun AD9361 tabanlı 2Rx referans sistem olduğu ve mevcut AD9364 hedefinin yerine geçmediği kayda alındı.

Sıradaki güvenli iş sırası:

1. Aktif Tcl/XDC ve Golden kaynak/artefakt regresyonu.
2. I0/Q0, runtime RF metadata ve TX-safe readback kapısı.
3. Non-blocking 2048-sample capture, tek-kare FFT, tam 2048-bin spectrum ve peak sayısal kapanışı.
4. Tek-kare kabulünden sonra ping-pong bankalı sürekli FFT frame modu.
4. Common peak/band-power motoru.
5. Gerçek harici kontrol elektriksel sözleşmesi.
6. Dört-durum FSM, PL scalar ratio ve yankısız oda kalibrasyonu.

Sayısal açı RMSE limiti henüz ürün sahibi tarafından verilmedi. İlk açı süpürmesi ölçülmüş performans tabanını üretecek; kabul limiti anten HPBW'si ve kalibrasyon verisi görülmeden uydurulmayacaktır.

## 12. Monopulse foundation uygulama hazırlığı

Durum: **Uygulama planı hazır; temiz Candidate branch birleştirmesi sıradaki adımdır.**

Kartta doğrulanmış RX/Wi-Fi kaynaklarının `codex/wifi-rf-detection` branch'inde, yeni monopulse tasarım belgelerinin ise `codex/axu4ev-pmufw-bringup` branch'inde bulunduğu teyit edildi. İki tarih yeni `codex/axu4ev-ad9364-monopulse` branch'inde, bağımsız worktree kullanılarak birleştirilecek; masaüstündeki kirli Vitis/Vivado çalışma ağacına dokunulmayacaktır.

İlk uygulanabilir dilim; Q1.31 scalar AZ/EL aritmetiği, dört durum sırası, 2048-bin ortak peak/CW/band-power referansı ve Cortex-A53 self-test'idir. PL FFT ve switch GPIO bağlantısı bu dilimin dışında tutulmuştur. Bu işler için `docs/superpowers/plans/2026-07-20-axu4ev-ad9364-monopulse-foundation.md` oluşturuldu.

Python doğrulama katmanında NumPy bağımsız oracle olarak kullanılacaktır. `analogdevicesinc/pyadi-iio` AD936X ailesini destekler; ancak mevcut JTAG/bare-metal Candidate IIO context/IIOD sunmadığından bugün karta doğrudan bağlanmayacaktır. Gerçek `adi.ad9361(uri=...).rx()` otomasyonu PetaLinux/IIOD aşamasında etkinleşecektir.

Harici kontrol entegrasyonu için model kapısı kapanmıştır: `ZX80-DR230-S+` ve `EV1HMC936ALP6/HMC936ALP6E`. BDC IF/koherens, RF-port DC seviyesi, 5 V level-shifter, kablo/pin eşlemesi, güvenli açılış durumu ve ölçülmüş switching/settling süreleri doğrulanmadan RTL/XDC pin varsayımı yapılmayacaktır.

## 13. Harici kontrol donanımı durumu — 20 Temmuz 2026

Durum: **Parça modelleri doğrulandı; elektriksel/pin entegrasyonu kısmen açık.**

Fotoğraftaki SPDT `ZX80-DR230-S+`, phase-shifter kartı ise `EV1HMC936ALP6/HMC936ALP6E` olarak okundu ve üretici datasheet'leriyle eşleştirildi. HMC kart etiketi üzerindeki `2017 120557 163` seri/üretim bilgisidir; modeldeki doğru sayı `936`dır.

Uygulanabilirlik sonucu:

- ZX80, hedef 1.2-1.4 GHz IF'yi kapsayan DC-3 GHz SPDT'dir.
- HMC936A yalnız 1.2-1.4 GHz için derecelidir; bu nedenle X-band anten sinyali BDC'den geçmeden HMC'ye uygulanamaz.
- HMC'nin altı kontrol hattı 5 V ve aktif-düşüktür; doğrudan FPGA bağlantısı reddedildi.
- ZX80 için iki, HMC için altı olmak üzere sekiz güvenli kontrol çıkışı gerekir.
- İlk settle başlangıç değeri 10 us olacaktır; datasheet süreleri yalnız tipik olduğundan nihai değer laboratuvarda ölçülecektir.

Sonraki donanım kararı için BDC IF etiketi/datasheet'i, RF1/RF2 kablo takibi, seviye dönüştürücü şeması ve AXU4EVB-P pin listesi gereklidir. Bu sırada board-independent monopulse math/spectrum/sequence foundation geliştirilebilir.

## 14. AXU4EVB-P monopulse foundation fiziksel kabulü — 20 Temmuz 2026

Durum: **TAMAMLANDI — yazılım foundation kabul edildi; monopulse ürün kabulü açık kalır.**

`codex/axu4ev-ad9364-monopulse` branch'inin
`53f74d93da93e77a21e3c5f733c11be330f20e19` launch commit'i ile Candidate iki kez
kartta çalıştırıldı; ikinci koşu cold power cycle sonrası yapıldı. Her iki JTAG
logunda Golden BIT ile DDR `A5A5A5A5` doğrulaması ve PMUFW/FPGA/PS/DDR/PS-PL/
uygulama launch PASS görüldü. Golden BIT SHA-256
`AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`, Candidate
Release ELF SHA-256 ise
`B4BA1BDE40AA4CDE10A6C370C7CFAEDCD0FB9CFED3A510501BA7C015C05CF6B2` olarak
kaydedildi; Candidate yalnız uygulama ELF'ini değiştirdi.

İki UART koşusu da `cf-ad9361-lpc` 61439514 Hz init satırını, AD936x Rev 2
başlatmasını ve aynı `MONOPULSE_RF: PASS fs=30720000 bw=10000000 lo=2400000000
gain=71 tx_att=89750` readback'ini verdi; ardından tam bir
`MONOPULSE_FOUNDATION: PASS` geldi. `DMA_EXAMPLE:`, `WIFI_RF_TEST:`, `Read Error`,
`Write Error` ve `PLATFORM: FAIL` işaretleri görülmedi. Sanitized, iki koşulu
kanıt `PROJECT/tests/evidence/axu4ev-ad9364-monopulse-foundation-pass.txt`
içindedir.

Post-review revalidation status: the historical acceptance above remains scoped
to launch commit `53f74d9` and ELF SHA-256
`B4BA1BDE40AA4CDE10A6C370C7CFAEDCD0FB9CFED3A510501BA7C015C05CF6B2`. The rebuilt
review-fix commit `e0c293544bc45e21b734bb215b39e341acb918b2` is separately
accepted after two fresh physical runs, one following a cold power cycle. Its
Candidate ELF is `860576` bytes with SHA-256
`D6FFF74DEFC1ACE260010D5BF13A93E7373C1633C3C5DC73DB23839FB13C9106`; the Golden
BIT SHA-256 remains `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`.
`20260720-174800-candidate.log` and `20260720-174936-candidate.log` each record
the full artifact manifest, DDR `A5A5A5A5`, and full JTAG launch PASS. The
user-supplied UART records show 61441040 Hz / 61439514 Hz initialization, the
required RF readback, and `MONOPULSE_FOUNDATION: PASS`, with no forbidden
DMA/Wi-Fi/error/platform/foundation FAIL marker.

Bu kabul yalnız A53 C foundation, AD9364 runtime sözleşmesi ve dört-durum
aritmetiğini kapatır; monopulse ürünü tamamlanmış değildir. PL 2048-point FFT ve
timing closure, ZX80/HMC936A GPIO ile FPGA bank/XDC/continuity, 5 V
level-shifter/safe OE, BDC IF/koherens, ölçülmüş settle/discard ve chamber angle
modeli sonraki kapılı teslimlerdir. Fiziksel HMC bağlantısında fotoğrafla
doğrulanan eval-header sırası `5.625..180 -> BIT1..BIT6` olarak korunacak;
süreklilik tablosu kapanmadan fiziksel kod sürülmeyecektir.
## 11. Wi-Fi RF detection feature durumu — 16 Temmuz 2026 kapanışı

Durum: **Task 1-5 tamamlandı ve review CLEAN; Task 6 READY_FOR_HARDWARE.**

Geliştirme, ana kirli çalışma ağacını ve mevcut Golden geri dönüş noktasını etkilememek için `codex/wifi-rf-detection` dalındaki bağımsız worktree'de yapıldı. GitHub'a push, `main` merge veya Golden `CURRENT` değişikliği yapılmadı.

### Tamamlanan fonksiyonlar

- Candidate launcher: doğrulanmış Golden donanım teslimleri + exact Release uygulama ELF'i; Debug fallback yok.
- Saf I/Q metrikleri: mean power, dBFS16, peak, clipping, medyan, delta ve aktivite verdict'i.
- RX-only capture: `B_BALANCED / RXB`, maksimum TX attenuation, ENSM RX readback, finite DMA, 500 ms timeout, cache ownership ve baseline gain reuse.
- UART akışı: hotspot kapalı baseline, 13 kanal active scan, deterministik kanal seçimi, 20 monitor penceresi ve PASS/INCONCLUSIVE sonucu.
- Release entegrasyonu: `WIFI_RF_TEST`, TX DMAC/DAC/DDS dışlama, temiz cleanup ve Release `libm` bağlantısı.
- Tekrarlanabilir Vitis build: kısa izole temp workspace, fresh platform/app üretimi, Windows Job Object ile process containment, gerçek `nm` sembol kapısı ve doğrulanmış cleanup.

### Son doğrulanmış aday

| Teslim | Değer |
|---|---|
| Branch | `codex/wifi-rf-detection` |
| Feature HEAD | `0042e820957442f957d881f207090b3c608be789` |
| Release ELF | `Vitis/workspace/ad9364app/Release/ad9364app.elf` |
| ELF boyutu | `855568` bayt |
| ELF SHA-256 | `C95CD5478275F2CA7911D1984D544AECEE44034BF368FF238221957BA4A500B1` |
| Golden BIT SHA-256 | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| Golden PMUFW SHA-256 | `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB` |
| Golden `psu_init.tcl` SHA-256 | `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B` |

ELF içinde `wifi_rf_test_run`, `wifi_rf_prepare_rx_only`, `wifi_rf_capture_channel` ve `wifi_rf_analyze_block` global text sembolleri doğrulandı. Metrics, source/host, Candidate launcher, JTAG order, release integrity ve handoff testlerinin altısı son preflight'ta PASS verdi. `P:` eşlemesi ve güncel-format geçici build kökü kalmadı.

### Donanım kabulü bekleyen maddeler

- Tek 2.4 GHz anten yalnız RXB'ye bağlanacak. İkinci anten ilk testte kullanılmayacak; AD9364 1x1 olduğu için RXA/RXB eşzamanlı iki kanal değildir.
- Telefon hotspot'u 2.4 GHz'e zorlanacak; baseline sırasında kapalı, active/monitor sırasında bağlı istemci trafiğiyle açık olacak.
- Candidate iki kez başlatılacak ve iki ardışık `WIFI_RF_TEST: PASS` sonucu aranacak.
- Gerçek PASS oluşmadan `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt` oluşturulmayacak ve raporlara RF kabulü tamamlandı yazılmayacak.
- Kart kabulünden sonra FFT/grafik, continuous streaming, PL hızlandırma ve PetaLinux/IIO ayrı fazlar olarak kalacaktır.

Bugünkü kapanışta donanım programlanmadı. Yarın başlangıç noktası `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd` ve Task 6 fiziksel checklist'idir.

## 12. Wi-Fi RF fiziksel kabulü — 17 Temmuz 2026

Durum: **TAMAMLANDI — iki ardışık fiziksel `WIFI_RF_TEST: PASS`.**

İlk kart denemesinde görülen `PLATFORM: FAIL stage=RX_ONLY error=-5`, AD9364 arızası değil FDD ENSM readback sözleşmesindeki yazılım hatasıydı. AD9364 init ve SPI başarılıydı. FDD/independent-FDD durumlarını maksimum TX attenuation sonrasında güvenli kabul eden, FDD dışındaki RX geçişini koruyan düzeltme TDD ile uygulandı.

| Teslim | Değer |
|---|---|
| Branch | `codex/wifi-rf-detection` |
| Release ELF | `Vitis/workspace/ad9364app/Release/ad9364app.elf` |
| ELF boyutu | `855568` bayt |
| ELF SHA-256 | `7E89D1A7D912661FD9843CFDAF48D4A81135EBE632FDF3E93B178CE01D92C2F0` |
| Golden BIT SHA-256 | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| Golden PMUFW SHA-256 | `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB` |
| Golden `psu_init.tcl` SHA-256 | `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B` |

Kart kabul özeti:

- Tek 2.4 GHz anten yalnız RXB'de; RXA/TXA/TXB boş.
- Baseline hotspot kapalı, active/monitor sırasında 2.4 GHz hotspot ve gerçek istemci trafiği aktif.
- Koşu 1: CH6 / 2437 MHz, `DELTA_PWR=+3.14dB`, `DELTA_BURST=+32pp`.
- Koşu 2: CH5 / 2432 MHz, `DELTA_PWR=+4.77dB`, `DELTA_BURST=+49pp`.
- İki koşunun tamamında RX-only güvenlik kapısı PASS, DMA OK, clipping sıfır, platform PASS ve RF activity PASS.

Kabul kanıtı `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt` dosyasındadır. Sistem RF enerji ve burst aktivitesini algılar; Wi-Fi paketlerini veya kullanıcı verisini çözmez. Task 6 kapanmıştır. Mevcut Golden fallback ve `CURRENT` değiştirilmemiştir; FFT/grafik, continuous streaming ve PetaLinux/IIO sonraki fazlardır.

## 16. Tasarım inceleme uzlaştırması ve PL FFT sözleşmesi — 21 Temmuz 2026

Durum: **TAMAMLANDI — iki inceleme raporu teknik kaynaklar ve güncel branch ile uzlaştırıldı.**

Bağlayıcı alt-tasarım:
`docs/superpowers/specs/2026-07-21-axu4ev-ad9364-pl-fft-spectrum-design.md`.

Kesinleşenler:

- `ZX80-DR230-S+` DC-3 GHz, HMC936A 1.2-1.4 GHz ve 0/+5 V kontrollüdür.
- HMC936A BDC sonrası Delta IF yolundadır; monopulse AD9364 LO'su ölçülen IF merkezine göre seçilir.
- İlk PL kabulü PS tetiklemeli tek-kare, 2048-point, rectangular-first FFT'dir.
- Tam 2048-bin magnitude-square spectrum AXI BRAM'de, control/status AXI-Lite'tadır.
- Peak sonucu `BIN/POWER/RE/IM` taşır; Re/Im diagnostiktir, ardışık frame kompleks oranı değildir.
- Tek-kare kabulünden sonra yaklaşık sekiz BRAM36 bütçeli iki spectrum bankasıyla sürekli FFT frame modu açılır.
- Ürün monopulse sonucu dört ardışık gücün normalize AZ/EL oranıdır; tam kompleks `Delta/Sigma` kapsam dışıdır.
- İlk elektriksel RF kontrolü PS/manual olabilir; nihai S0-S3 state-tag/settle/discard çevrimi PL FSM'dedir.
- CDC mailbox, `reset_epoch`, imza+CRC frame eşlemesi ve DMA'yı durdurmayan shadow path korunur.

İkinci inceleme raporu eski `d264bddd`/`codex/wifi-rf-detection` bağlamında hazırlandığından “foundation yok” ve “monopulse yalnız opsiyonel Faz 5B olsun” yorumları güncel durum değildir. Foundation iki soğuk başlangıçta fiziksel kabul edilmiştir; monopulse kullanıcı tarafından bağlayıcı ürün mimarisi olarak seçilmiştir. Risk azaltma, ürünü A/B prototipine geri döndürmek yerine FFT, sürekli mod ve RF kontrolünü ayrı kabul kapılarıyla geliştirmek şeklinde uygulanacaktır.

Sıradaki uygulanabilir işler:

1. Temiz Candidate Vivado kaynak/build güvenini kapatmak.
2. ILA/DMA ile I0/Q0 formatı, valid/enable ve gerçek tap clock'unu ölçmek.
3. 2048-point bit-true model ve non-blocking capture sözleşmesini test-first uygulamak.

## 17. PL FFT uygulama durumu — 21 Temmuz 2026 gün sonu

Yukarıdaki ilk üç iş tamamlandı ve uygulama Task 5 seviyesine ulaştı. Mevcut Candidate kaynak durumu:

- Bit-doğru FFT oracle ve dondurulmuş 2048-sample vektörler hazırdır.
- Non-blocking capture/replay, exact magnitude/peak ve atomik ping-pong spectrum bank RTL'i hazırdır.
- İki spectrum bankası Vivado sentezinde sekiz RAMB36 kullanmakta, LUTRAM kullanmamaktadır.
- CPU↔ADC komut ve sonuçları 16-bit reset epoch içeren bundled-data toggle mailbox'larıyla atomik taşınmaktadır.
- AXI-Lite kontrol/status bloğu sabit `0x00..0x40` haritasını; bağımsız AW/W, WSTRB, backpressure, RO koruması, pulse, W1C ve invalid-config reddini uygulamaktadır.
- Tek-taraflı resetlerde stale, kayıp veya duplicate transfer üretmemek için reset-at-toggle-one, in-flight, remote-ready latency ve post-ack reset testleri iki yönde geçmektedir.

Son Task 5 commit zinciri `95b0c19` → `19d7e65` → `072cdf6` olup bağımsız RTL review sonucu `Approved` durumundadır. Golden artefaktlar korunmuştur. Bir sonraki açık iş FFT v9.1 IP konfigürasyonunun üretilmesi ve ardından üst-seviye Candidate entegrasyonudur.

## 18. FFT IP durumu — 22 Temmuz 2026

FFT v9.1 konfigürasyonu kaynak kontrollü Tcl ile kilitlenmiştir. Gerçek Vivado 2020.1 property inspection gate'i hedef part, IP sürümü ve tüm sayısal ayarları doğrular. AXIS config sözcüğü `16'h0D57` olarak dondurulmuş; forward/scale bit dilimleri ayrı ayrı test edilmiştir.

Paketleme reçetesi Task 7 top-level ve XCI oluşmadan kaynak ağacına artefakt yazmaz. Eksik kaynak/IP/XCI hata yolları geçici fixture'larda çalıştırılmaktadır. Task 6 bağımsız incelemesi açık bulgusuz `Approved` durumundadır; commitler `a0ad12b` ve `25adaf0`'dır. Aktif sıradaki iş Task 7 single-shot üst-seviye RTL entegrasyonudur.

## 19. Task 7 single-shot üst RTL durumu — 22 Temmuz 2026

Durum: **TAMAMLANDI ve bağımsız re-review `Approved`.**

- AD9364 shadow girişi ayrık `valid/enable/I/Q` portlarıyla ve DMAC'a geri basınç üretmeden bağlandı.
- Capture→replay→xFFT→magnitude/peak→atomik spectrum bank veri yolu tamamlandı.
- Gerçek Vivado 2020.1 xFFT modeliyle altı vektörün tüm 2048 FFT ve güç kelimeleri sıfır farkla geçti.
- Abort, soft-reset/epoch recovery, stale epoch, dolu bank, dropped sample, FFT error, overflow, W1C ve sticky IRQ hata yolları bounded actual-IP simülasyonda geçti.
- Komut RF etiketi metadata için otoritatiftir; canlı RF pini bilinçli farklı sürülerek bu bağ doğrulandı.
- Pozitif custom-IP paketleme kaynak ağacı dışında çalışır; iki BRAM arayüzü, AXI-Lite, IRQ, ayrık ADC portları ve xFFT bağımlılığı kontrol edilir.
- Spectrum bank sentezi sekiz RAMB36 kullanır ve LUTRAM kullanmaz.

Commitler `8c03a0f`, `b743312`, `67d5524`'tür. Golden bitstream/XSA/ELF ve çalışan JTAG başlatma zinciri değiştirilmedi. Sıradaki aktif iş Task 8 block-design entegrasyonu, adres/IRQ ataması, synthesis/implementation ve kart üstü DMA-shadow korelasyonudur.
