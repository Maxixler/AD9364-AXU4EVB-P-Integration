# Çalışma Günlüğü — AXU4EVB-P + AD9364 Doğrulama ve Teslim Zinciri

**Tarih:** 14 Temmuz 2026

**Kapsam:** `fmcomms2/axu4ev` Vivado projesinin şemalara göre doğrulanması, bitstream/XSA üretimi, Vitis platformu, FSBL ve AD9364 bare-metal uygulamasının tamamlanması.

## 1. Çalışma yaklaşımı

Projede daha önce oluşturulmuş Markdown notlarının yanıltıcı veya güncelliğini yitirmiş olabileceği kabul edildi. Bu nedenle kararlar aşağıdaki kanıt sırasına göre verildi:

1. AXU4EVB-P ve AD9364/FMCOMMS şemaları ile kart kullanıcı kılavuzları
2. Etkin Vivado projesi, block design, HDL ve XDC
3. Vivado/Vitis tarafından üretilen raporlar, loglar ve ikili çıktılar
4. Markdown raporları ve instruction belgeleri

İlk incelemede eski raporlardaki ADRV9008/9, yeni proje oluşturma, `SDR_Real/sdr_wrapper.xsa` kullanma ve “bitstream üretimi bekleniyor” ifadelerinin mevcut projeyi yansıtmadığı görüldü. Ana çalışma doğrudan şu etkin proje üzerinde sürdürüldü:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.xpr`

## 2. Donanım ve Vivado doğrulaması

Etkin FPGA parçası `xczu4ev-sfvc784-1-i`, üst modül `system_top`, aktif kısıt dosyası `system_constr.xdc` olarak doğrulandı. Şema, top-level portlar ve XDC çapraz karşılaştırıldığında şu sorunlar bulundu:

- `RX_FRAME` diferansiyel çiftinin pinleri hatalıydı.
- `TX_CLK/FB_CLK` diferansiyel çiftinin pinleri hatalıydı.
- RX LVDS girişlerinde hedeflenen diferansiyel terminasyon eksikti.
- SPI chip-select için güvenli pull-up tanımı eksikti.
- RX veri alanını süren açık bir `rx_clk` zamanlama kısıtı yoktu.

Uygulanan düzeltmeler:

- `RX_FRAME`: L7/L6
- `TX_CLK/FB_CLK`: N7/N6
- 16 RX LVDS portu: `DIFF_TERM_ADV TERM_100`
- SPI chip-select: pull-up
- `rx_clk`: 4,00 ns, yani 250 MHz

Bu kontroller kalıcı bir kısıt regresyon testine dönüştürüldü. Test önce mevcut hataları görünür biçimde yakaladı; XDC düzeltmelerinden sonra tüm kontroller geçti.

## 3. Tam Vivado derlemesi

Vivado 2020.1 ile sentez, implementasyon ve bitstream üretimi baştan sona çalıştırıldı. Sonuçlar:

- Setup WNS: 0,144 ns
- Setup TNS: 0,000 ns
- Hold WHS: 0,010 ns
- Hold THS: 0,000 ns
- Yönlendirilmemiş ağ: 0
- DRC hatası: 0
- `rx_clk`: 250 MHz, 16.657 endpoint
- `rx_clk` özel WNS/WHS: 1,098 ns / 0,013 ns

Kalan iki `REQP-1853` ve bir `RTSTAT-10` uyarısı kayda geçirildi. Bunlar derlemeyi veya zamanlama kapanışını engellemedi.

`check_timing` çıktısında 1 `no_clock`, 1 `unconstrained_internal`, 8 `no_input_delay` ve 13 `no_output_delay` maddesi kaldı. ADI referans tasarımında da harici gecikme bütçeleri verilmediği ve kart üstü ölçülmüş değer bulunmadığı için rastgele I/O delay değerleri eklenmedi; bu alan bilinçli bir doğrulama sınırı olarak raporlandı.

## 4. Bitstream ve XSA teslimi

Üretilen bitstream:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.runs/impl_1/system_top.bit`

- Boyut: 7.797.806 bayt
- SHA-256: `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`

Bitstream dahil edilerek güncel XSA dışa aktarıldı. Şu üç kopyanın bit düzeyinde aynı olduğu doğrulandı:

- `PROJECT/verification/vivado/system_top.xsa`
- `Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.sdk/system_top.xsa`
- `Vitis/workspace/fmcomms2_axu4ev_hw/hw/system_top.xsa`

XSA SHA-256 değeri:

`AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118`

XSA içine gömülü bitstream ile implementasyon bitstream'i de eşleşti.

## 5. Vitis platformunun güncellenmesi

Vitis donanım platformu eski/stale handoff yerine güncel `system_top.xsa` ile yeniden oluşturuldu. Platformun PS yapılandırması ve çevre birimi görünümü yeni XSA ile eşitlendi; eski donanım tanımları kaldırıldı, güncel donanım öğeleri yansıtıldı.

Windows araç zincirindeki uzun yol/boşluk sorunlarını aşmak için geçici bir sürücü harfi eşlemesi kullanıldı. İşlem sonunda proje metadatasında kalıcı `P:` yolu bırakılmadığı kontrol edildi.

## 6. FSBL OCM taşmasının çözülmesi

FSBL ilk derlemede OCM alanındaki `.dup_data` taşması nedeniyle link aşamasında başarısız oldu. Yalnızca FSBL uygulamasına bölüm bazlı derleme bayrakları eklemek yeterli olmadı; aynı seçeneklerin BSP kütüphanelerine de uygulanması gerektiği tespit edildi.

Uygulama ve BSP için `-ffunction-sections -fdata-sections` etkinleştirildikten sonra FSBL başarıyla derlendi. Üretilen dosya:

`Vitis/workspace/fmcomms2_axu4ev_hw/zynqmp_fsbl/executable.elf`

SHA-256:

`58E9464EA159616839573139B6DB5755FA397EF7D482248507A5C769DD620367`

FSBL'nin çalışma alanı ve dışa aktarılan kopyalarının hash eşitliği doğrulandı.

## 7. AD9364 bare-metal uygulamasının onarılması ve derlenmesi

`ad9364app` çalışma alanında kayıtlı değildi ve metadata içinde eski `C:/Users/DELL/workspace/sdr_wrapper` platformuna işaret ediyordu. Uygulama ve system metadata'sı şu güncel hedefe bağlandı:

- Platform: `fmcomms2_axu4ev_hw`
- Domain: `standalone_domain`

Release include yolları ve kütüphane bağlantıları düzeltildi, matematik kütüphanesi eklendi. Kaynak kodda cihaz seçimi ayrıca doğrulandı:

- `AD9361_DEVICE 0`
- `AD9364_DEVICE 1`

Release derlemesi başarıyla tamamlandı:

`Vitis/workspace/ad9364app/Release/ad9364app.elf`

- Boyut: 844.880 bayt
- Biçim: ELF64, AArch64, çalıştırılabilir
- `text/data/bss`: 292.856 / 12.724 / 157.888 bayt
- SHA-256: `A9B5B372C4E79FD263752F0C10B9162D01A32EC1CA114B0B4C98F6F5E293D5F7`

ELF giriş adresinin 0 görünmesi linker script'teki `ENTRY(_vector_table)` ve DDR başlangıç adresi 0 yapılandırmasıyla uyumludur; tek başına hata değildir.

## 8. IDE donanım dosyalarının eşitlenmesi

IDE tarafından kullanılacak bitstream ve `psu_init` çıktıları güncel Vitis platformuyla eşitlendi. Bitstream/XSA/ELF zinciri için kalıcı bütünlük testi yazıldı ve son çalıştırmada tüm kontroller geçti.

## 9. Oluşturulan kalıcı test ve otomasyon dosyaları

`PROJECT/tests` altında şu araçlar oluşturuldu:

- `Test-Axu4evAd9364Constraints.ps1`
- `Inspect-Axu4evAd9364Project.tcl`
- `Build-Axu4evAd9364Bitstream.tcl`
- `Export-Axu4evAd9364Xsa.tcl`
- `Update-Axu4evVitisPlatform.tcl`
- `Fix-Axu4evFsblBuild.tcl`
- `Build-Axu4evAd9364App.tcl`
- `Sync-Axu4evAd9364IdeHardware.ps1`
- `Test-Axu4evHandoffArtifacts.ps1`

Bu dosyalar aktif projenin incelenmesini, kısıt regresyonunu, bitstream/XSA üretimini, Vitis platform yenilemesini, FSBL ve uygulama derlemesini, IDE eşitlemesini ve teslim hash kontrollerini tekrarlanabilir hale getirir.

## 10. Bilinçli olarak değiştirilmemiş alanlar

- PS DDR/MIO ve block design ayarları, doğrulanmış mevcut platform temelini gereksiz yere değiştirmemek için bu aşamada yeniden tasarlanmadı.
- AD9364 uygulama kaynaklarının RF davranışı kapsam dışı biçimde yeniden yazılmadı; yalnızca doğru hedefe bağlanması ve derlenmesi sağlandı.
- PetaLinux, device tree ve Linux IIO entegrasyonu başlatılmadı.
- FPGA içi FFT/spektrum işleme eklenmedi.
- Çalışma ağacındaki kullanıcıya ait ilgisiz değişiklikler geri alınmadı, stage edilmedi veya commit edilmedi.

## 11. Güncel sonuç ve sıradaki iş

Masaüstü geliştirme zinciri Vivado kısıtlarından AD9364 uygulama ELF'ine kadar tutarlı ve yeniden üretilebilir durumdadır. Son taze kontrolde:

- Kısıt regresyonu: geçti
- Vivado zamanlama kapanışı: geçti
- Vivado DRC: 0 hata
- Bitstream/XSA bütünlüğü: geçti
- FSBL ELF: üretildi ve doğrulandı
- AD9364 uygulama ELF: üretildi ve doğrulandı

Sıradaki ana iş kart üzerinde kontrollü bring-up'tır: güç/jumper/boot kontrolü, JTAG ve UART, bitstream + FSBL + uygulama yükleme, SPI ürün kimliği, saat/LO kilidi, kalibrasyon ve önce RX-only veri akışı doğrulaması. TX testi ancak düşük güç ve uygun RF ölçüm güvenliği sağlandıktan sonra yapılmalıdır.

Bu güncellemede eski, karakter kodlaması bozuk `chat_report.md` içerikleri temiz UTF-8 Türkçe ile değiştirilmiş ve yalnızca doğrulanabilen güncel sonuçlar aktarılmıştır.
