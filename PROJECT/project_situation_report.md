# Proje Durum Raporu — AXU4EVB-P + AD9364

**Son güncelleme:** 16 Temmuz 2026

**Ana hedef:** ALINX AXU4EVB-P üzerinde AD9364/FMCOMMS ailesi ile doğrulanmış FPGA donanım platformu ve bare-metal yazılım zinciri oluşturmak.

**Mevcut aşama:** Vivado/Vitis kapanışı, PMUFW içeren JTAG başlatma ve temel bare-metal kart bring-up'ı tamamlandı; sıradaki ana aşama RF/IQ örnek doğrulamasıdır.

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

- [ ] Hedef örnekleme hızı, bant genişliği ve FFT boyutu netleştirilecek.
- [ ] Önce yazılım tabanlı referans FFT/spektrum çıktısı oluşturulacak.
- [ ] Gerekirse PL tarafında pencereleme/FFT/ortalama mimarisi tasarlanacak.
- [ ] Gerçek zamanlı veri yolu ve DDR bant genişliği ölçülecek.

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

Durum: **Otomatik yazılım doğrulaması tamamlandı; soğuk güç döngüsü kabulü bekleniyor.**

Seçili sürüm `2026-07-16-bringup-v1` olarak `PROJECT/releases/axu4ev-ad9364/CURRENT` dosyasına kaydedildi. Sürümdeki beş teslim manifest boyutu ve SHA-256 değeriyle doğrulanmadan JTAG programlama başlamaz. Golden ve Workspace kuru çalışmaları doğru dört çalıştırma girdisini seçmiş; release bütünlüğü, Vitis handoff bütünlüğü, XSCT yol bağımsızlığı, PMUFW/FPGA/PS–PL/DDR/uygulama sırası ve çift tıklama başlatıcı sözleşmeleri otomatik testlerden geçmiştir.

Günlük kullanım:

1. JTAG ve PS_UART bağlanır; PuTTY `115200-8-N-1` açılır.
2. Normal açılış için `PROJECT/tools/Start-Axu4evAd9364Golden.cmd` çift tıklanır.
3. `AD936x Rev 2 successfully initialized`, `DMA_EXAMPLE:` ve `Done.` UART'ta aranır.
4. Yeni derlemeler yalnızca Workspace başlatıcısıyla aday olarak denenir.
5. Başarılı aday değişmez yeni sürüme terfi ettirilir; `CURRENT` daha sonra ayrı komutla seçilir.

Çalışma logları `PROJECT/logs/jtag` altında tutulur ve Git tarafından yok sayılır. Mevcut Golden sürüm gelecekteki RF/anten ölçümleri için bilinen-iyi geri dönüş noktasıdır. PetaLinux geçişinde aynı sürümün doğrulanmış XSA'sı ilk donanım referansı olarak korunacaktır.

Henüz tamamlanmayan fiziksel kabul: bilgisayar/Vitis/XSCT kapalı ve kart 10–15 saniye enerjisiz bırakılmış durumdan Golden başlatıcının manuel komut olmadan çalıştırılması; UART ve XSCT logundaki başarı işaretlerinin kaydedilmesi. Bu yapılmadan “soğuk başlangıç tamamen kapandı” kabul edilmeyecektir.
