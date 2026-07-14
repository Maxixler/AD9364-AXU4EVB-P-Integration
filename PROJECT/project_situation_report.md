# Proje Durum Raporu — AXU4EVB-P + AD9364

**Son güncelleme:** 14 Temmuz 2026

**Ana hedef:** ALINX AXU4EVB-P üzerinde AD9364/FMCOMMS ailesi ile doğrulanmış FPGA donanım platformu ve bare-metal yazılım zinciri oluşturmak.

**Mevcut aşama:** Vivado ve Vitis derlemeleri tamamlandı; sıradaki ana aşama kart üzerinde kontrollü ilk çalıştırma ve RF doğrulaması.

## 1. Yönetici özeti

Aktif proje, Analog Devices HDL ağacındaki aşağıdaki AXU4EV uyarlamasıdır:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.xpr`

Hedef FPGA `xczu4ev-sfvc784-1-i`, üst modül `system_top`, etkin kısıt dosyası `system_constr.xdc` olarak doğrulandı. AXU4EVB-P ve AD9364 şemaları esas alınarak kritik LVDS pin eşlemeleri düzeltildi; elektriksel özellikler ve RX saat tanımı tamamlandı. Vivado 2020.1 ile temiz bir sentez, implementasyon ve bitstream üretimi gerçekleştirildi. Aynı implementasyondan XSA çıkarıldı, Vitis platformu yenilendi, FSBL ile AD9364 bare-metal uygulaması derlendi ve teslim zincirindeki dosyaların bütünlüğü hash karşılaştırmalarıyla doğrulandı.

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
- [x] FSBL'nin OCM taşması teşhis edildi; uygulama ve BSP için bölüm bazlı derleme seçenekleriyle çözüldü.
- [x] FSBL ELF üretildi ve dışa aktarılan kopyasıyla hash eşitliği doğrulandı.
- [x] `ad9364app` içindeki eski `sdr_wrapper` platform bağlantıları temizlendi.
- [x] Uygulama `fmcomms2_axu4ev_hw / standalone_domain` hedefine bağlandı.
- [x] Release include/library ayarları düzeltildi; `libm` bağlantısı sağlandı.
- [x] Kaynak yapılandırmasında AD9364 seçimi (`AD9361_DEVICE 0`, `AD9364_DEVICE 1`) doğrulandı.
- [x] AArch64 Release ELF başarıyla üretildi.
- [x] IDE bitstream ve `psu_init` dosyaları güncel platformla eşitlendi.
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
| FSBL ELF | `Vitis/workspace/fmcomms2_axu4ev_hw/zynqmp_fsbl/executable.elf` | `58E9464EA159616839573139B6DB5755FA397EF7D482248507A5C769DD620367` |
| AD9364 uygulama ELF | `Vitis/workspace/ad9364app/Release/ad9364app.elf` | `A9B5B372C4E79FD263752F0C10B9162D01A32EC1CA114B0B4C98F6F5E293D5F7` |

Vivado SDK, `PROJECT/verification` ve Vitis platformundaki XSA kopyaları bit düzeyinde aynıdır. XSA içine gömülü bitstream de implementasyon çıktısıyla eşleşmektedir. Uygulama ELF'i 64-bit AArch64 çalıştırılabilir dosyasıdır.

## 5. Mevcut riskler ve doğrulama sınırları

- Fiziksel kart üzerinde güç, saat, SPI erişimi, AD9364 kimliği ve RF veri akışı henüz bu rapor kapsamındaki masaüstü doğrulamalarla kanıtlanmış değildir.
- Harici I/O gecikmeleri ölçülmeden zamanlama modeli kart seviyesinde tam kapanmış sayılmamalıdır.
- Anten, attenuator, LO frekansı, örnekleme hızı ve güvenli TX güç seviyesi ilk testten önce kontrollü seçilmelidir.
- PetaLinux/IIO entegrasyonu ve FPGA içinde FFT/spektrum işleme mevcut bare-metal bring-up zincirinden sonraki aşamalardır.
- Çalışma ağacında kullanıcıya ait başka değişiklikler bulunduğundan bunlar korunmuş, bu çalışma kapsamında geri alınmamış veya commit edilmemiştir.

## 6. Sıradaki adımlar

### Aşama 7 — Kart üzerinde ilk çalıştırma

- [ ] Kart revizyonu, FMC modülü, güç kaynakları, jumper/switch ve boot modu fiziksel olarak kontrol edilecek.
- [ ] JTAG bağlantısı ve UART terminali doğrulanacak.
- [ ] Güncel bitstream programlanacak.
- [ ] Güncel FSBL ve `ad9364app.elf` yüklenerek kontrollü başlatma yapılacak.
- [ ] UART logunda FSBL geçişi ve uygulama başlangıcı kaydedilecek.
- [ ] SPI üzerinden AD9364 ürün kimliği ve temel register erişimi doğrulanacak.
- [ ] Referans saat/LO kilit durumu ve kalibrasyon sonucu kontrol edilecek.
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

Son taze doğrulamada kısıt regresyonu ve teslim bütünlüğü testleri geçti; zamanlama değerleri yukarıdaki sonuçlarla eşleşti ve DRC hata sayısı sıfır kaldı.
