# Çalışma Günlüğü — AXU4EVB-P + AD9364 Doğrulama ve Teslim Zinciri

**Tarih:** 14 Temmuz 2026

**Kapsam:** `fmcomms2/axu4ev` Vivado projesinin şemalara göre doğrulanması, bitstream/XSA üretimi, Vitis platformu, FSBL ve AD9364 bare-metal uygulamasının tamamlanması.

## 29. Bare-metal Python FFT laboratuvar ekranı kararı — 27 Temmuz 2026

Projenin kalan isterleri kart kanıtları ve güncel kaynakla yeniden
karşılaştırıldı. PL FFT transport/control temelinin tamamlandığı; gerçek
ZX80/HMC936 S0-S3 kontrolü, kontrollü CW RF kabulü ve açı kalibrasyonunun açık
kaldığı doğrulandı.

Stajın kalan süresinde gereksiz platform yükü oluşturmamak için kullanıcıyla
birlikte şu karar alındı:

- PetaLinux ve `pyadi-iio` şimdilik kullanılmayacak.
- Kart mevcut bare-metal/JTAG başlatma zincirinde kalacak.
- Tam 2048-bin spectrum UART üzerinden CRC'li binary paketle taşınacak.
- Python tarafı PySerial + NumPy + Matplotlib kullanacak.
- Ekran spectrum, 32-frame waterfall, peak/frekans ve sağlık bilgilerini
  gösterecek.
- Tam ölçüm NPZ, özet CSV olarak kaydedilecek.
- Ethernet yalnız geleceğe açık taşıma adaptörü olacak; şimdi uygulanmayacak.

UART 115200 baud'da yaklaşık 16 KiB spectrum paketinin 1,5-2 saniyede
aktarılması kabul edildi. Host her geçerli yanıt sonrasında yeni frame
isteyecektir; kart kendiliğinden sınırsız stream üretmeyecektir.

ZX80-DR230-S+ ile EV1HMC936ALP6 nihai plana dahildir. İlk grafik tesliminden
sonra BDC IF, RF1/RF2 eşlemesi, ZX80 beslemesi, HMC 5 V level-shifter,
sekiz FPGA pini ve settle/discard ölçümleri kapatılacak; ardından
`Σ±ΔAZ/Σ±ΔEL` S0-S3 çevrimi ve Q1.31 AZ/EL hesabı canlı sisteme bağlanacaktır.

Yeni çalışma dalı:

`codex/axu4ev-monopulse-lab-console`

Tasarım commit'i:

`1ce8220 docs: define bare-metal monopulse lab console`

Tasarım ve ayrıntılı test-first plan:

- `PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-monopulse-lab-design.md`
- `PROJECT/reports/2026-07-27-axu4ev-ad9364-baremetal-python-lab-implementation-plan.md`

## 28. Periodic FFT monitor physical acceptance - 27 July 2026

The periodic Candidate ran once on AXU4EVB-P + AD9364 from launch commit
`b0f53f36f8676b54747d417c4ae44c61ac8a3c99`. The committed PS-UART evidence
at `PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-raw-putty.log`
includes AD9364 initialization, one START, all 100 FRAME records, and the
final PASS. The strict parser command used `-LogPath` and returned `PASS:
periodic FFT monitor log contains 100 valid frames.` The committed JTAG launch
evidence is `PROJECT/tests/evidence/axu4ev-ad9364-pl-fft-periodic-monitor-jtag-launch.log`.

The periodic manifest is now `board_verified=true`; its package test requires
the committed evidence, matching metadata/hashes, and a strict parser PASS.
No artifact hash changed. This is monitor transport/control acceptance only:
no controlled CW/R&S source was declared, observed powers were low/ambient
noise, and antenna/port wiring was not independently reverified. It does not
claim RF-performance, DOA, calibration, or antenna-wiring acceptance.

## 27. Periodic FFT monitor preflight checkpoint - 27 July 2026

Tasks 1-5 produced a separate `fft-periodic-monitor-v1` Candidate for the
AXU4EVB-P + AD9364. This checkpoint freshly ran the complete nine-command
software/preflight regression: PL FFT driver, periodic monitor policy,
Candidate build, unchanged single-shot Candidate launch, periodic package,
periodic launch, periodic log-parser, JTAG launch ordering, and release
integrity. Every command exited 0. The expected PASS evidence included
`pl_fft_control single-shot driver`, `pl_fft_monitor policy`, complete and
hardware-identical periodic packaging, isolated periodic launcher resolution,
strict complete-log parsing, valid JTAG ordering, and immutable release `r2`
with `CURRENT=r2`.

The periodic manifest identifies AXU4EVB-P, AD9364, `xczu4ev-sfvc784-1-i`, and
Vitis 2020.1. The Candidate is built/packaged and host/preflight verified, but
it remains `board_verified=false`; no physical board PASS or periodic-board
evidence has been created. Its artifact SHA-256 values are application
`0586E9A18EA4457A622CEE84D33F81A6402C95FB12A64755D2A7C39441964002`, bitstream
`ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC`, PMUFW
`9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB`, `psu_init`
`CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B`, and XSA
`672A431A3698DFB841AD0F09A8605CD1D125314FCB6333E49A60727E8B42E574`.

The protected single-shot launcher and `fft-single-shot-v1` bundle were
separately checked against `df3e052` with no diff. The unrelated known baseline
failure in `Test-Axu4evLaunchWrappers.ps1` remains out of scope because its
generated Workspace Vivado/Vitis/IDE bitstreams are not in sync; this work did
not alter it or waive it. The next physical action is
`PROJECT\tools\Start-Axu4evAd9364PeriodicMonitor.cmd` with PuTTY PS-UART
capture, followed by
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tests\Test-Axu4evPeriodicMonitorLog.ps1 -LogPath <putty-log-path>`.
Only its successful validation may supply physical acceptance evidence; the
manifest must remain unmodified beforehand.

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

`C8EC16594420C96D0EDC5B64036BA9653C338C33BBD23C59AEC168F09470AC21`

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

Bu bölümde öngörülen kart bring-up'ının temel smoke-test kısmı daha sonra başarıyla tamamlandı; ayrıntıları aşağıdaki güncel kayıtlardadır.

Bu güncellemede eski, karakter kodlaması bozuk `chat_report.md` içerikleri temiz UTF-8 Türkçe ile değiştirilmiş ve yalnızca doğrulanabilen güncel sonuçlar aktarılmıştır.

## 12. Vitis platformundaki `Out-of-date` durumunun onarılması

Vitis'te `fmcomms2_axu4ev_hw` platformunun `Out-of-date` görünmesi yalnızca IDE görüntü yenileme sorunu olarak kabul edilmedi. Platform teslimleri ve metadata çapraz kontrol edildiğinde eksik/eski XPFM ile PMU firmware domain'inin yanlış işlemci hedefine bağlanması birlikte tespit edildi. PMU firmware hedefi `psu_pmu_0`, araç zinciri `mb-gcc` olacak şekilde düzeltildi ve platform güncel XSA'dan yeniden üretildi.

FSBL tarafında Vitis 2020.1'in bazı üst seviye işlemlerde başarısız alt derlemeye rağmen yanıltıcı biçimde başarılı çıkış kodu verebildiği görüldü. Bu nedenle yalnızca IDE durumuna veya süreç çıkış koduna güvenilmedi; gerekli ELF dosyalarının varlığı, mimarisi ve hash eşitliği ayrıca denetlendi. OCM taşması için uygulama ve BSP bayrakları kalıcılaştırıldı. XPFM, domain metadatası, FSBL, PMU firmware ve uygulama handoff dosyaları son kontrolde tutarlı hale geldi. Geçici `P:` sürücü eşlemesinin kalıcı proje yollarına sızmadığı da doğrulandı.

Son platform teslimlerinden bazıları:

- FSBL ELF SHA-256: `C8EC16594420C96D0EDC5B64036BA9653C338C33BBD23C59AEC168F09470AC21`
- PMU firmware ELF SHA-256: `F4D1FC0B82A64555883C79063278863654CEF80167826F2BB3541967B82FEF98`
- XPFM SHA-256: `C85BBEBB5C3A76C5AA7D748BCCBF578269C319EE6091D750161039FFC4BA47D5`

## 13. Kart üzerinde ilk başarılı bare-metal bring-up

Kart PS_UART ve JTAG üzerinden bilgisayara bağlıyken güncel bitstream, FSBL ve `ad9364app.elf` çalıştırıldı. PuTTY kaydı şu kritik kanıtları verdi:

```text
Xilinx Zynq MP First Stage Boot Loader
Release 2020.1   Jul 14 2026  -  17:00:57
PMU-FW is not running, certain applications may not be supported.
cf-ad9361-lpc: Successfully initialized (61441040 Hz)
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized (61439514 Hz)
DMA_EXAMPLE: address=0x4dc00 samples=65536 channels=2 bits=16
Done.
```

Bu çıktı FSBL'nin çalıştığını, AD9364'ün ortak AD936x sürücü katmanı üzerinden SPI ile tanınıp başlatıldığını, AXI ADC/DDS çekirdeklerinin hazırlandığını ve ilk DMA örnek aktarımının tamamlandığını kanıtlar. Logdaki `ad9361` ve `cf-ad9361` adları hata değildir; AD9361 ve AD9364 aynı AD936x no-OS/HDL sürücü ailesini paylaşır.

`PMU-FW is not running` uyarısı bu ilk JTAG launch akışında PMU firmware'in ayrıca başlatılmadığını gösterdi. Smoke-test bu uyarıya rağmen tamamlandı. Sonraki doğrulamada PMUFW, FSBL'den önce yüklenip çalıştırılarak uyarı kaldırıldı; kapanış kaydı Bölüm 15'tedir.

## 14. Güncel sonuç ve sonraki iş

Masaüstü teslim zinciri ile kart üstü temel smoke-test birlikte geçmiştir. Kanıtlanan kapsam; bitstream/FSBL/application handoff bütünlüğü, AD9364 SPI initialization, AXI çekirdek initialization ve DMA işleminin tamamlanmasıdır. Henüz kanıtlanmayan kapsam ise DMA tamponundaki gerçek I/Q örneklerinin doğruluğu, kanal/polarite düzeni, DC ve saturasyon durumu, bilinen RF sinyaline karşı frekans/genlik doğruluğu ve TX güvenliğidir.

Sıradaki kontrollü sıra şudur:

1. Bilinen düşük seviyeli RF kaynak veya güvenli loopback ile RX capture almak.
2. DMA tamponunu kanal sırası, I/Q polaritesi, tekrarlanan veri, DC ve saturasyon açısından incelemek.
3. CPU tabanlı referans FFT ile beklenen tonu/frekansı doğrulamak.
4. TX testini yalnızca uygun attenuator ve ölçüm güvenliği sağlandıktan sonra açmak.

## 15. PMUFW içeren JTAG başlatma kapanışı

Vitis'in tek uygulamalı GDB yapılandırması A53 uygulaması ile PMUFW'yi aynı anda indirmeyi kabul etmedi. Sistem proje debug yapılandırması da mevcut `ad9364app_system` için uygun olmadığından resmî ZynqMP XSCT sırası kullanıldı:

1. PSU JTAG güvenlik kapıları açıldı.
2. PMUFW, `MicroBlaze PMU` hedefine indirildi ve çalıştırıldı.
3. Doğrulanmış bitstream FPGA'ya programlandı.
4. Cortex-A53 #0 resetlenerek FSBL çalıştırıldı.
5. `ad9364app.elf` A53-0'a indirilip çalıştırıldı.

İkinci UART kaydında `PMU-FW is not running` uyarısı bulunmadı. AD9364 tekrar `AD936x Rev 2 successfully initialized` sonucuna ulaştı; AXI çekirdekleri yaklaşık 61,44 MHz ile başladı ve 65.536 örnekli, iki kanallı, 16-bit DMA işlemi yine `Done.` ile tamamlandı.

Manuel olarak doğrulanan sıra `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl` betiğine aktarıldı. Betik kullanıcıya özel mutlak yol içermez ve PMUFW → FPGA → FSBL → uygulama sırası `PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1` ile kontrol edilir.

## 16. 16 Temmuz 2026 — tekrar başlatma arızası ve kalıcı düzeltme

Yeni oturumda Vitis platformu düzeltildikten sonra GUI Run işlemi `Memory write error at 0x0 / Instruction transfer timeout` ile başarısız oldu. İncelemede Release uygulama ELF'inin mevcut olmadığı, güncel çıktının `Debug/ad9364app.elf` olduğu ve çalışma alanındaki mevcut FSBL'nin SerDes/PCIe kalibrasyonunda kaldığı görüldü. DDR kurulmadığından uygulama yüklemesi başarısız oldu.

FSBL yerine XSA'daki `psu_init.tcl` doğrudan çalıştırıldı. DDR yaz/oku testi geçti; fakat ilk denemede yalnızca boş olan `psu_post_config` çağrıldığı için PS–PL izolasyonu ve fabric reset sırası uygulanmadı. Bunun sonucu AD9364 SPI ürün kimliği `0x00`, sürücü sonucu `Unsupported PRODUCT_ID` ve devamında `-22` okuma/yazma hataları oldu.

Gerçek güç döngüsünden sonra şu sıra kartta tek tek doğrulandı:

1. JTAG güvenlik kapıları açıldı.
2. PMUFW yüklendi ve çalıştırıldı.
3. Doğrulanmış bitstream programlandı.
4. A53-0 resetlendi; `force-mem-accesses 1` etkinleştirildi.
5. `psu_init` ile PS/DDR hazırlandı.
6. `psu_ps_pl_isolation_removal` ve `psu_ps_pl_reset_config` çalıştırıldı.
7. DDR `A5A5A5A5` yaz/oku testi geçti.
8. Debug `ad9364app.elf` yüklendi ve çalıştırıldı.

PuTTY kapanış kanıtı:

```text
cf-ad9361-lpc: Successfully initialized (61439514 Hz)
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized (61441040 Hz)
DMA_EXAMPLE: address=0x60c00 samples=65536 channels=2 bits=16
Done.
```

`Launch-Axu4evAd9364Jtag.tcl` bu doğrulanmış sıraya güncellendi: stale FSBL yolu kaldırıldı, `psu_init.tcl` ve iki zorunlu PS–PL prosedürü eklendi, uygulama seçimi Release → Debug fallback olarak korundu. `Test-Axu4evJtagLaunchScript.ps1` önce eski betikte beklenen nedenle başarısız oldu; düzeltme sonrasında yeni sırayı ve FSBL'nin kullanılmadığını doğrulayarak geçti. Bölüm 15'teki FSBL tabanlı sıra tarihsel kayıttır; güncel geçerli sıra bu bölümdedir.

## 17. Golden sürüm ve tek tıklamalı yeniden açılış düzeni

Kullanıcının bilgisayarı/kartı kapatıp açtıktan sonra XSCT komutlarını tek tek girmemesi için doğrulanmış bring-up kalıcı bir pakete dönüştürüldü.

Yapılanlar:

- `Axu4evRelease.psm1` ile manifest okuma, güvenli bağıl yol, dosya boyutu ve SHA-256 doğrulaması eklendi.
- Mevcut sürüm üzerine yazmayı reddeden terfi aracı ile `CURRENT` değerini yalnızca açıkça değiştiren ayrı seçim aracı eklendi.
- Kartta başarı vermiş BIT, XSA, PMUFW, `psu_init.tcl` ve Debug uygulama ELF'i `2026-07-16-bringup-v1` değişmez sürümünde sabitlendi.
- Tcl betiği çalışma alanı yolu üretmek yerine doğrulanmış dört dosya yolunu ortamdan alacak şekilde düzenlendi.
- DDR yaz/oku eşleşmesi başarısızsa uygulama ELF'inin indirilmesini durduran kapı eklendi.
- Golden ve Workspace modlarını yöneten ortak PowerShell orkestratörü oluşturuldu.
- `Start-Axu4evAd9364Golden.cmd` ve `Start-Axu4evAd9364Workspace.cmd` tek tıklama girişleri oluşturuldu.
- Her gerçek çalıştırma için Git dışında kalan tarihli JTAG log dizini eklendi.

Golden modu yalnızca manifesti tam eşleşen sürümü çalıştırır. Workspace modu yeni Vivado/Vitis adayını önce handoff testinden geçirir. Yeni aday, UART'ta AD9364 Rev 2 ve DMA `Done.` sonucunu vermeden Golden sürüme terfi ettirilmeyecektir. PetaLinux'a geçildiğinde mevcut Golden XSA, bilinen-iyi donanım tabanı olarak korunacaktır.

Bu oturumda release/promotion, Golden ve Workspace kuru çalışma, handoff hash'leri, Tcl sırası/yol bağımsızlığı ve `.cmd` sözleşmeleri geçti.

## 18. Golden otomatik kart kabulü

16 Temmuz 2026 tarihinde kullanıcı `Start-Axu4evAd9364Golden.cmd` dosyasını çalıştırdı. İlk denemede Tcl Windows yol eşlemesindeki eksik ters eğik çizgi nedeniyle `char map list unbalanced` hatası alındı. Yol eşlemesi çalışan XSCT biçimi olan `{\\ /}` şeklinde düzeltildi ve gerçek XSCT yorumlayıcısını kullanan regresyon testi eklendi.

Düzeltilen Golden çalışma hiçbir manuel XSCT komutu istemeden şu aşamaları tamamladı:

- yerel hardware server bağlantısı;
- PMU JTAG güvenlik kapılarının açılması;
- PMUFW yükleme/başlatma;
- doğrulanmış FPGA bitstream programlama;
- Cortex-A53 #0 reset;
- doğrudan PS, DDR ve PS–PL sınırı başlangıcı;
- DDR `A5A5A5A5` yaz/oku kapısı;
- `ad9364app.elf` yükleme ve başlatma.

XSCT logu `PROJECT/logs/jtag/20260716-120323-golden.log` olarak üretildi. PuTTY kabul çıktısı:

```text
cf-ad9361-lpc: Successfully initialized (61439514 Hz)
ad9361_init : AD936x Rev 2 successfully initialized
cf-ad9361-dds-core-lpc: Successfully initialized (61439514 Hz)
DMA_EXAMPLE: address=0x60c00 samples=65536 channels=2 bits=16
Done.
```

Kabul edilen `2026-07-16-bringup-v1` sürümünün beş SHA-256 değeri:

- Bitstream: `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`
- XSA: `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118`
- PMUFW: `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB`
- `psu_init.tcl`: `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B`
- `ad9364app.elf`: `320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC`

Logun ilk kısmı UTF-8, XSCT çıktısı UTF-16 olarak birleştiği için okunabilirlik sorunu ayrıca tespit edildi. Orkestratör tek `Unicode` kodlama kullanacak şekilde düzeltildi ve wrapper testi bu sözleşmeyi koruyacak biçimde genişletildi. Mevcut log Git dışında bırakılmıştır; sonraki loglar tek kodlamayla oluşacaktır.

## 19. Main fast-forward ve GitHub push

Kullanıcının onayıyla doğrulanmış çalışma yerel `main` dalına alındı. Ön kontrolde `main`in feature dalının doğrudan atası olduğu ve 14 commit geride bulunduğu doğrulandı; bu nedenle çatışmalı merge yerine güvenli fast-forward uygulandı. Mevcut çalışma ağacında kullanıcıya ait 1081 staged dosya ve çok sayıda Vitis/Vivado çıktısı bulunduğundan branch checkout yapılmadı ve bu dosyalara dokunulmadı.

Fast-forward sonrasında:

- yerel `main`: `9d2f06a`
- doğrulanmış HEAD: `9d2f06a`
- `main` ile HEAD farkı: yok
- beş otomatik AXU4EV testi: PASS

GitHub CLI oturumu yenilendikten sonra yalnızca `refs/heads/main:refs/heads/main` pushlandı. Push sonucu:

```text
To https://github.com/Maxixler/FPGA-Profen.git
   6b78d06..9d2f06a  main -> main
```

Uzak referans ayrıca `9d2f06acca380778cae29ddaf4bbf327048e15b5` olarak doğrulandı. Feature checkout ve kullanıcıya ait staged dosyalar yerelde korunmuş; GitHub `main` yalnızca daha önce kapsamı belirlenerek commitlenmiş proje değişiklikleriyle güncellenmiştir.

## 20. Monopulse ister analizi ve onaylanan tasarım — 20 Temmuz 2026

Kullanıcı, yöneticiden aldığı yeni isterleri karışık sırayla aktardı. İstenen ana fonksiyonlar; FFT çıktısı, maximum peak tespiti, genlik oranı, 0°/180° phase switching, SUM/ERROR yaklaşımı ve azimuth/elevation hata üretimiydi. Kullanıcının paylaştığı RF blok şeması bağlayıcı ürün mimarisi, `Antenna_Tracking_Techniques_for_Long_Range_Air-to- (1).pdf` ise yalnız referans kabul edildi.

Referans makale görsel ve metinsel olarak incelendi. Makalenin tek IF zincirinde Σ+Δ ve Σ-Δ güçlerini zaman bölüşümlü ölçtüğü, tam eşzamanlı iki dijital kanal veya doğrudan kompleks faz bölmesi yapmadığı belirlendi.

AD9364 ürün yeteneği, güncel no-OS kaynakları ve fotoğraflar birlikte incelendi:

- Hedef AD9364 1x1'dir; RXA/RXB eşzamanlı iki ADC kanalı değildir.
- Mevcut `AD9364_DEVICE=1` yazılımı `rx2tx2=false` zorlamaktadır.
- Fotoğraftaki eski düzenin kartı `AD-FMCOMMS3-EBZ` olarak okundu.
- İki mavi IF kablosunun `RX1A` ve `RX2A` portlarına bağlı olduğu görüldü.
- Bu kart AD9361 tabanlı gerçek 2Rx referans sistemdir; AXU4EVB-P + AD9364 hedefini değiştirmez.

Kullanıcı hedef kartın değiştirilmemesini onayladı. Bunun sonucunda eşzamanlı iki dijital RX yaklaşımı elendi ve şu analog tek-kanallı pseudo-monopulse akışı kabul edildi:

```text
S0: Σ + ΔAZ
S1: Σ - ΔAZ
S2: Σ + ΔEL
S3: Σ - ΔEL
```

SPDT ΔAZ/ΔEL seçer; 0°/180° bi-phase switch seçilen Δ'nın işaretini tersler; combiner tek hattı AD9364'e verir. Phase switch'in anten azimuth açısını doğrudan değiştirmediği ve tek RF yolunda yalnız 180° çevirmenin FFT gücünü değiştirmeyeceği açıklığa kavuşturuldu.

Onaylanan ilk sayısal profil ve DSP sözleşmesi:

- 30,72 MSPS sample rate
- Runtime readback ile 10 MHz RX bandwidth hedefi
- 2048-point tek ve zaman paylaşımlı FFT
- CW için dört spektrum toplamından ortak peak
- Peak çevresinde ±2 bin güç integrasyonu
- 5-10 MHz modülasyonlu sinyal için configured band-power
- Dört scalar güçten Q1.31 `AZ_ERROR` ve `EL_ERROR`
- Küçük payda, clipping, sample drop, FFT error ve switch timeout denetimi

R&S SMW200A, yankısız oda, verici/alıcı anten, döner mekanizma ve X-band BDC altyapısının hazır olduğu fotoğraflarla görüldü. Kalibrasyon akışı; düşük güçten başlama, ortak MGC, mekanik sıfır biası, tek eksenli `-θ/0/+θ` taraması, simetri/eğim ve tekrar edilebilirlik raporu olarak tasarlandı. Açı RMSE için kanıtsız limit konmadı.

Bağımsız bağlayıcı tasarım belgesi oluşturuldu:

`PROJECT/designs/2026-07-20-axu4ev-ad9364-single-channel-monopulse-design.md`

Mevcut nihai planın eski anten A/B terminolojisi yeni Σ/Δ mimarisiyle çeliştiği için bağlayıcı düzeltme ve güncel iş paketleri eklendi. Bu aşamada RTL, Vivado BD veya Vitis uygulama kaynakları değiştirilmedi.

## 21. Foundation planı, pyadi-iio ve RF switch bilgi kapısı — 20 Temmuz 2026

Kullanıcı tasarımı onaylayıp geliştirmeye devam edilmesini istedi. Repo incelemesinde kartta doğrulanmış RX/Wi-Fi uygulamasının `codex/wifi-rf-detection`, yeni monopulse belgelerinin ise `codex/axu4ev-pmufw-bringup` branch'inde olduğu bulundu. Çalışan RX kaynağını kaybetmemek için iki geçmişin temiz `codex/axu4ev-ad9364-monopulse` Candidate branch'inde birleştirilmesi ilk uygulama kapısı yapıldı.

Detaylı foundation planı şu dosyada hazırlandı:

`docs/superpowers/plans/2026-07-20-axu4ev-ad9364-monopulse-foundation.md`

Plan; portable C11 Q1.31 monopulse matematiği, dört durum sırası, ortak peak/CW/band-power referansı, NumPy oracle, Cortex-A53 self-test ve kart kabul kanıtını kapsar. PL FFT ile harici switch pin bağlantısı, elektriksel sözleşme gelene kadar ayrı follow-on faz olarak bırakıldı.

Kullanıcının önerdiği `analogdevicesinc/pyadi-iio` incelendi. Resmî proje AD936X ailesini desteklemekte ve örnek kullanımda `adi.ad9361(uri=...).rx()` sağlamaktadır. Buna karşılık `pyadi-iio`, libIIO ve erişilebilir IIO context ister. Mevcut bare-metal/JTAG Candidate IIOD sunmadığından ilk testlerde NumPy oracle ve mock `adi` nesnesi kullanılacak; gerçek kart yakalama PetaLinux/IIOD aşamasında açılacaktır.

RF switch için yalnız “SPDT” veya “phase switch” adı yeterli değildir. SPDT ve 0°/180° phase-switch'in tam üretici/model numarası; kontrol gerilimi, VIH/VIL, aktif polarite, power-up durumu, switching/settling süresi, frekans aralığı ve level-shifter ihtiyacını belirlemek için zorunlu bilgi olarak kaydedildi. Ayrı bir sürücü/kontrol kartı kullanılacaksa onun doğrulanmış dijital giriş sözleşmesi model bilgisinin FPGA tarafındaki karşılığı olabilir.

## 22. ZX80 ve HMC936A model kapanışı — 20 Temmuz 2026

Kullanıcı harici SPDT'yi `ZX80-DR230-S+`, phase-shifter'ı önce `EV1HMC946ALP6` olarak bildirdi. Paylaşılan yakın fotoğraf incelendiğinde kart etiketi `EV1HMC936ALP6`, entegre baskısı `H936A` olarak net okundu. Resmî Analog Devices datasheet'i de eval kart malzeme listesini `EV1HMC936ALP6` olarak doğruladı.

Üretici verilerinden çıkarılan bağlayıcı sonuçlar:

- ZX80: DC-3 GHz, 2.7-5 V besleme, iki kontrol pini, `00=OFF`, `10=RF1`, `01=RF2`, `11=N/A`, tipik 2 us switching.
- HMC936A: 1.2-1.4 GHz, 6-bit/5.625°, nominal +5 V, aktif-düşük faz bitleri, tipik 250 ns switching.
- HMC referans fazı bütün kontrol bitleri HIGH iken oluşur; 180° ağırlığı ilgili en yüksek bit LOW yapılarak seçilir.
- FPGA 3.3 V/1.8 V çıkışları HMC'nin `VDD±0.2 V` HIGH koşuluna doğrudan bağlanmayacaktır; 5 V level-shifter/buffer zorunludur.
- HMC bandı nedeniyle BDC sonrası gerçek IF 1.2-1.4 GHz içinde kanıtlanmalıdır.

Bu bilgiler `PROJECT/designs/2026-07-20-rf-control-hardware-contract.md` dosyasına, ana tasarıma, nihai plana ve foundation uygulama planına işlendi. Fiziksel GPIO/XDC için hâlâ BDC IF, RF1/RF2 kablo eşlemesi, sekiz pin ve sürücü şeması gereklidir.

## 23. AXU4EVB-P üzerinde monopulse foundation kabulü — 20 Temmuz 2026

Foundation Candidate kart üzerinde iki kez kabul edildi; ikinci çalışma cold power
cycle sonrasındadır. `codex/axu4ev-ad9364-monopulse` branch'inde launch commit
`53f74d93da93e77a21e3c5f733c11be330f20e19` kullanıldı. Golden BIT SHA-256
`AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` korunurken
Candidate Release ELF SHA-256
`B4BA1BDE40AA4CDE10A6C370C7CFAEDCD0FB9CFED3A510501BA7C015C05CF6B2` yüklendi.
İki JTAG launch kaydında da DDR `A5A5A5A5` doğrulaması ve full JTAG launch PASS
vardır.

İki UART koşusu da aynen AD9364 init, `MONOPULSE_RF: PASS fs=30720000
bw=10000000 lo=2400000000 gain=71 tx_att=89750` ve
`MONOPULSE_FOUNDATION: PASS` ile bitti. `DMA_EXAMPLE:`, `WIFI_RF_TEST:`,
`Read Error`, `Write Error` veya `PLATFORM: FAIL` görünmedi. Kalıcı sanitize
kanıt: `PROJECT/tests/evidence/axu4ev-ad9364-monopulse-foundation-pass.txt`.

Post-review revalidation: those historical runs remain scoped to launch commit
`53f74d9` and ELF SHA-256
`B4BA1BDE40AA4CDE10A6C370C7CFAEDCD0FB9CFED3A510501BA7C015C05CF6B2`. The rebuilt
review-fix commit `e0c293544bc45e21b734bb215b39e341acb918b2` is separately
accepted by two new physical Candidate runs, including a cold power cycle. The
`860576`-byte Release ELF SHA-256 is
`D6FFF74DEFC1ACE260010D5BF13A93E7373C1633C3C5DC73DB23839FB13C9106`; the Golden
BIT SHA-256 remains `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`.
The `20260720-174800-candidate.log` and `20260720-174936-candidate.log` files
each contain the full artifact manifest, DDR `A5A5A5A5`, and full JTAG launch
PASS. User UART records show 61441040 Hz / 61439514 Hz initialization, the
required RF readback and `MONOPULSE_FOUNDATION: PASS`, with no forbidden
DMA/Wi-Fi/error/platform/foundation FAIL marker.

Bu, A53 software foundation kabulüdür; tamamlanmış monopulse ürünü iddiası
değildir. PL FFT/timing closure, dış ZX80/HMC GPIO ile FPGA bank/XDC/continuity,
HMC için 5 V buffer/safe OE, BDC IF/koherens, ölçülmüş settle/discard ve chamber
angle modeli sonraki kapılı işlerdir. Devam eden fiziksel bağlantı sözleşmesinde
fotoğrafla düzeltilen eşleme `5.625..180 -> BIT1..BIT6` olarak esas alınır;
kablo/level-shifter/FPGA süreklilik tablosu kapanmadan HMC fiziksel kodu
sürülmeyecektir.
## 20. AD9364 2.4 GHz Wi-Fi RF algılama geliştirmesi — gün sonu kaydı

Kullanıcı, kartın gerçek RF sinyali alabildiğini önce kontrollü ve güvenli biçimde kanıtlamak; daha sonra FFT/grafik, continuous streaming ve PetaLinux/IIO fazlarına geçmek istedi. İlk RF kaynağı olarak 2.4 GHz'e zorlanan telefon hotspot'u seçildi. Bu aşamada Wi-Fi paketleri veya kullanıcı verisi çözülmeyecek; yalnız RF enerji, burst, RSSI ve DMA örnek istatistikleri ölçülecektir.

Donanım teyidi:

- AD9364 RF `1x1` transceiver'dır.
- RXA ve RXB iki eşzamanlı alıcı kanal değil, tek RX zincirinin seçilebilir girişleridir.
- Kart eşleşmesine göre ilk 2.4 GHz testinde `RXB / B_BALANCED` kullanılacaktır.
- Kullanıcının iki Wi-Fi anteninden yalnız biri RXB'ye bağlanacak; ikinci anten ilk testte boşta kalacaktır.
- TXA/TXB boş, `REF_CLK` anten bağlantısından bağımsız kalacaktır.

Bu konuşma kapsamında tamamlanan teknik işler:

1. RF kabul tasarımı ve altı görevli implementasyon planı yazıldı.
2. Kirli ana çalışma ağacından bağımsız `codex/wifi-rf-detection` worktree'si oluşturuldu.
3. Candidate launcher eklendi; Golden donanım hash'leri korunurken yalnız Release ELF seçildi ve Debug fallback yasaklandı.
4. Saf C I/Q metrik motoru TDD ile geliştirildi. Signed overflow, `INT16_MIN`, 32-bit size sınırı, exact clipping/eşik sınırları ve compiler discovery sorunları review turlarında giderildi.
5. RX-only capture katmanı geliştirildi. Tekrarlı IRQ DMA flag'i, 64-bit pointer'ın 32-bit DMA adresine kesilmesi, aggregate sayaç taşması, cache ownership ve invalid mode/error yolları host harness ile düzeltildi.
6. UART baseline/active scan ve verdict state machine'i geliştirildi. Kanal-baseline ilişkisi, CRLF/drain davranışı, exact çıktı sırası ve clipping warning'i davranış testleriyle korundu.
7. Feature Release uygulamasına bağlandı. Wi-Fi yolunda TX DMAC ve DAC/DDS başlatılmıyor; RX DMAC ve cleanup akışı doğrulandı.
8. Vitis 2020.1'in stale metadata, asenkron import, uzun Windows yolu ve detached process sorunları sistematik olarak ayrıştırıldı. Son wrapper izole kısa temp platform/app oluşturuyor ve `CreateProcessW` ile suspended başlattığı launcher'ı çalışmadan önce Windows Job Object'a atıyor. Başarı için root exit code sıfır, job process sayısı sıfır, fresh Release ELF ve dört gerçek `nm` sembolü zorunlu.
9. Job Object fake suite success, nonzero root, detached child, timeout, unrelated process, stale ELF, Debug-only, missing symbol, cleanup aggregation ve Tcl escaping senaryolarında art arda PASS verdi.
10. Tek final gerçek Vitis build PASS verdi; hiçbir generated artifact commit kapsamına alınmadı.

Son Release ELF:

```text
Path: Vitis/workspace/ad9364app/Release/ad9364app.elf
Size: 855568 bytes
SHA256: C95CD5478275F2CA7911D1984D544AECEE44034BF368FF238221957BA4A500B1
Symbols: wifi_rf_test_run, wifi_rf_prepare_rx_only,
         wifi_rf_capture_channel, wifi_rf_analyze_block
```

Task 6 preflight'ta şu altı test iki kez PASS verdi: metrics, source/host, launcher provenance, JTAG ordering, Golden release integrity ve Vitis handoff integrity. Candidate kuru çalışması Golden BIT/PMUFW/`psu_init.tcl` ile exact Release ELF'i birleştirdi. Donanım programlanmadı ve gerçek RF evidence dosyası oluşturulmadı.

Yarın devam planı:

1. Tek 2.4 GHz anteni RXB'ye bağla; RXA/TXA/TXB boş kalsın.
2. JTAG + PS_UART bağlantısını ve PuTTY `115200-8-N-1` ayarını hazırla.
3. Hotspot kapalıyken Candidate'ı başlat ve baseline prompt'unu tamamla.
4. Hotspot'u 2.4 GHz aç; ikinci cihazla sürekli trafik oluştur ve active/monitor prompt'unu tamamla.
5. `RX_ONLY: PASS`, `PLATFORM: PASS`, `RF_ACTIVITY: PASS`, `WIFI_RF_TEST: PASS` satırlarını kaydet.
6. Aynı kabulü ikinci kez tekrarla. İki PASS sonrası sanitize evidence ve rapor kapanışı yapılacak.

Gün sonu durumu: Task 1-5 tamamlandı ve bağımsız review'ları CLEAN; Task 6 `READY_FOR_HARDWARE`. Feature branch yerel tutuldu. `main`, `origin/main`, Golden `CURRENT` ve mevcut bring-up fallback değiştirilmedi; push/merge yarınki kart testi sonrasına bırakıldı.

## 21. 17 Temmuz 2026 — FDD hata düzeltmesi ve iki koşulu kart kabulü

İlk fiziksel Candidate çalıştırmasında AD9364 Rev 2 init başarılı olmasına rağmen `PLATFORM: FAIL stage=RX_ONLY error=-5` alındı. Kod geriye doğru izlendiğinde `-5` değerinin `-EIO` olduğu ve FDD yapılandırılmış AD9364'ün ENSM readback'ini `FDD` döndürmesine karşın uygulamanın yalnız `RX` beklediği doğrulandı. Aynı anda kaynakta bulunan tamamlanmamış `pdata->fdd` denemesi host stub'ıyla derlenmediği için kullanılmadı.

TDD akışında önce FDD senaryosu eklendi ve eski kodun `FDD prepare (actual=-5 expected=0)` ile düştüğü görüldü. Üretim kodu mevcut ENSM'yi önce okuyacak şekilde değiştirildi: FDD ve independent-FDD kabul edilirken FDD dışındaki yol RX'e geçirilip tekrar okunuyor. RXB seçimi, 89.75 dB TX attenuation ve hata kapıları korundu.

Kaynak/host testleri, altı preflight kapısı ve gerçek Vitis Release build PASS verdi. Yeni ELF `855568` bayt ve SHA-256 değeri `7E89D1A7D912661FD9843CFDAF48D4A81135EBE632FDF3E93B178CE01D92C2F0` oldu. Candidate dry-run tam olarak bu ELF'i, mevcut Golden BIT/PMUFW/`psu_init.tcl` ile eşledi.

Kullanıcı tek 2.4 GHz anteni RXB'ye bağlayıp hotspot kapalı baseline ve gerçek istemci trafiğiyle active/monitor aşamalarını iki kez tamamladı:

- İlk koşu CH6 / 2437 MHz'i seçti; delta power `+3.14 dB`, delta burst `+32 pp`.
- İkinci koşu CH5 / 2432 MHz'i seçti; delta power `+4.77 dB`, delta burst `+49 pp`.
- Her iki koşu `RX_ONLY: PASS`, `DMA=OK`, `CLIP=0`, `PLATFORM: PASS`, `RF_ACTIVITY: PASS` ve `WIFI_RF_TEST: PASS` ile bitti.

İki ardışık gerçek kart PASS sonucu `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt` içine sanitize edilerek kaydedildi. Bu kabul RF enerji/aktivite algılamasını doğrular; paket veya payload decode edildiği anlamına gelmez. Task 6 fiziksel kabulü tamamlandı, Golden `CURRENT` değiştirilmedi.

## 24. 21 Temmuz 2026 — PL FFT magnitude/bank ve CDC/register kapanışı

Bugünkü geliştirmede PL FFT planının Task 4 ve Task 5 adımları tamamlandı. Task 4 ile exact 33-bit FFT gücü, lower-bin tie-break kullanan peak seçimi ve iki adet 2048×64 ping-pong spectrum bankası eklendi. Vivado sentezi iki bankayı tam sekiz RAMB36'ya eşledi; RAMB18 ve LUTRAM kullanımı sıfırdır.

Task 5 ile CPU↔ADC command/result mailbox'ları ve sabit AXI-Lite register haritası test-first geliştirildi. İlk sürüm altı RTL testini geçmesine rağmen bağımsız inceleme reset sınırında kayıp, stale/phantom ve duplicate transfer pencereleri buldu. Her bulgu önce iki yönlü başarısız testle yeniden üretildi; mailbox request/ack paritesi, payload retention, async ready gating ve recovery kararı düzeltilerek kapatıldı. Son bağımsız re-review Critical/Important/Minor bulgusuz `Approved` verdi.

Kalıcı doğrulama artık şu altı PASS hedefini kapsar: `adc_frame_capture`, `adc_frame_replay`, `magnitude_peak`, `spectrum_pingpong`, `fft_cdc`, `fft_regs`. Task 5 commitleri `95b0c19`, `19d7e65` ve `072cdf6`'dır. Kullanıcının raporları `PROJECT/reports/` altında toplama kararı uygulandı; bundan sonraki proje raporu güncellemeleri bu klasörden yapılacaktır.

## 25. 22 Temmuz 2026 — FFT v9.1 Tcl ve paketleme sözleşmesi

Task 6 test-first tamamlandı. İlk RED, eksik `fft_v9_1_config.tcl` nedeniyle alındı; Vivado property dump ile 2020.1'deki gerçek lowercase `CONFIG.*` anahtarları keşfedildi. Üretim Tcl'i xFFT v9.1'i 2048-point, pipelined streaming, fixed-point scaled, 16/24-bit, natural-order ve convergent-rounding ayarlarıyla üretmektedir.

İlk review packed config word, clock/reset association ve Task 7 sonrası test güvenliği eksiklerini buldu. Bunlar yeni RED gate'lerle kapatıldı: packed `TDATA=16'h0D57`, AXI/ADC bus association metadata'sı, gerçek Vivado version assertion'ı ve temp fixture tabanlı missing-source/IP/XCI testleri eklendi. Son re-review Critical/Important/Minor bulgusuz `Approved` verdi. Commitler `a0ad12b` ve `25adaf0`'dır.

## 26. 22 Temmuz 2026 — Task 7 gerçek xFFT üst RTL ve hardening kapanışı

Kullanıcının “projeye devam edelim” isteğiyle PL FFT planının Task 7 adımı test-first uygulandı. İlk RED, üst modül bulunmadığı için alındı. Daha sonra ayrık ve non-backpressured AD9364 tap, capture/replay, gerçek xFFT v9.1, magnitude/peak, çift spectrum bankası, CDC ve AXI-Lite register alanı `axi_ad9364_fft_capture` üstünde birleştirildi.

Nominal altı-vektör testi ilk GREEN'i aldıktan sonra bağımsız review; hard-wire status bitleri, unsafe pulse CDC, yırtılabilir epoch bus'ı, abort/soft-reset recovery, dolu-bank deadlock'u, RF-tag kaynağı, IRQ/W1C ve paketleme hijyeni açıklarını buldu. Her bulgu negatif testle yeniden üretildi ve kapatıldı. xFFT ARESETn/overflow çıkışları açıldı; result mailbox 264-bit atomik metadata/flag taşıyacak şekilde genişletildi; bank rezervasyonu replay'den önce yapıldı; xFFT finite frame'ler arasında resetlenip `16'h0D57` ile yeniden configure edildi.

Final gerçek-IP suite; abort recovery, stale epoch, soft-reset epoch adoption, dolu-bank rejection, farklı live/command RF etiketi, FFT_ERROR/OVERFLOW enjeksiyonu, partial W1C ve sticky IRQ ile birlikte altı vektörün 2048'er FFT/power sonucunu geçti. Taze root koşusu exit 0 ve `PASS: axi_ad9364_fft_capture single-shot` verdi. Pozitif paketleme gate'i ve bank sentezi de PASS; kaynak ağacına üretilmiş XCI/proje eklenmedi.

Commitler: `8c03a0f`, `b743312`, `67d5524`. Final bağımsız kapanış incelemesi `Approved`. Sıradaki geliştirme adımı Task 8 block-design entegrasyonudur; henüz yeni bitstream üretilmedi veya kart programlanmadı.

## 27. 24-27 Temmuz 2026 — kart FFT'den canlı laboratuvar ekranına

Block-design entegrasyonu ve Candidate bitstream sonrasında kartta ilk
tek-kare koşusu `PL_FFT: FAIL stage=CAPTURE error=-6` verdi. Kart/JTAG
bağlantısı temizlenip yeniden başlatıldığında aynı tasarım
`PL_FFT: PASS frame=1 bank=0 peak_bin=88 crc=aaa532ad` üretti. Ardından
100-frame periyodik monitor kartta tamamlandı. Peak bin'in uyarımsız laboratuvar
ortamında frame'den frame'e değişmesinin normal olduğu, asıl deterministik
kabulün kontrollü CW ile yapılacağı netleştirildi.

Kullanıcı bare-metal + Python yaklaşımını, 2048-bin tam spektrum ve iki çalışma
modunu seçti. Bunun üzerine:

1. Sürümlü request/response protokolü, CRC-32/ISO-HDLC ve sequence koruması C
   ve Python'da byte-exact uygulandı.
2. Bare-metal `GET_INFO`/`CAPTURE_ONCE` servisi PL control/status ve iki
   spectrum bankından atomik frame okudu.
3. Python istemcisi paket uzunluğu, CRC, sıra numarası, metadata, exact 2048
   bin ve fatal donanım bayraklarını doğruladı.
4. Matplotlib canlı spectrum, 32-frame waterfall, peak ve sağlık ekranı
   eklendi.
5. `s` tuşuyla veya `--single` moduyla tam NPZ ve özet CSV kayıt yolu eklendi.
6. `LabUart` Vitis modu, `Start-Axu4evAd9364LabConsole.cmd` başlatıcısı ve
   `monopulse-live-lab-v1` değişmez Candidate'ı oluşturuldu.

Gerçek Vitis 2020.1 build sırasında iki çevresel sorun ayrıştırıldı. Uzun
Windows temp yolu BSP hedefini 260 karakter sınırının ötesine taşıyordu; build
kısa workspace'e alındı ve erken yol kapısı eklendi. Eclipse/platform üretimi
bazen geçici dosya kilidiyle ilk denemede düşüyordu; yalnız bu aşama için bir
kez ve 3 saniye sonra sınırlı retry eklendi. Ardından gerçek Release build ve
paketleme PASS verdi.

Candidate:

```text
release_id: monopulse-live-lab-v1
application: 865360 bytes
application_sha256:
  9DFC2355F5A4262AFFD1455EA3D0972A80F279E8804BD371DBCFDF38452FDC14
bitstream_sha256:
  ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC
board_verified: false
```

Protokol, bare-metal servis, 31 Python testi, Candidate build/package,
periyodik monitor paketi ve Golden release regresyonları PASS verdi. Eski
Workspace launcher testi, ignored Vivado implementation bitstream'i ile
tracked Vitis handoff bitstream'inin farklı olduğunu raporladı. Bu uyuşmazlık
Lab Candidate'tan bağımsız olduğundan kullanıcı üretimi ignored çıktıların
üzerine yazılmadı; immutable Candidate akışı doğrulandı.

Sıradaki gerçek kabul SMW200A ile DC dışı kontrollü CW'de en az 10 ardışık
frame'dir. Exact 2048 bin, CRC-valid mesaj, sıfır fatal flag ve beklenen
peak'in ±1 bin içinde kalması gerekir. Bu kanıt alınana kadar
`board_verified=false` ve güç değerleri “kalibre edilmemiş bağıl güç” olarak
korunur.

ZX80-DR230-S+ ve EV1HMC936ALP6 planda vardır fakat bu Candidate'a fiziksel
olarak entegre edilmiş sayılmaz. BDC IF, RF1/RF2 kablo eşlemesi, ZX80 VDD ve
kontrol gerilimleri, HMC936 5 V level-shifter/OE, sekiz FPGA pini/XDC ile
settle/discard ölçümleri kapanmadan S0-S3 kontrolü etkinleştirilmeyecektir.

Rapor kapanışından sonra Task 9'un fiziksel test öncesi araçları da eklendi.
`--frames 10` modu GUI açmadan on ardışık geçerli frame'i
`axu4ev-ad9364-live-lab-cw-capture.npz` ve
`axu4ev-ad9364-live-lab-cw-summary.csv` olarak atomik kaydeder.
`Test-Axu4evLabCaptureEvidence.ps1`; immutable Candidate hash bağını, SMW200A
frekans/seviye ve RF yolunu, AD9364 LO/Fs/BW değerlerini, ardışık frame
kimliğini, exact 2048 bin, CRC, peak ±1 ve sıfır fatal flag şartlarını birlikte
denetler. Sentetik pozitif/negatif testler PASS, gerçek kanıt eksikliği ise
tasarlandığı gibi RED'dir.
