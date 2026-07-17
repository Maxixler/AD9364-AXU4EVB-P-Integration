# AXU4EVB-P + AD9364 SDR Uygulama Planı

## 1. Proje hedefi

Bu projenin ana hedefi, ALINX AXU4EVB-P (`xczu4ev-sfvc784-1-i`) kartı üzerinde FMC LPC üzerinden bağlı AD9364 tabanlı RF kartını çalıştırmak; RX/TX örneklerini ADI `axi_ad9361` ve AXI DMAC veri yollarıyla DDR belleğe aktarmak ve önce bare-metal/no-OS, daha sonra gerekirse Linux/IIO katmanında işlemek ve gözlemlemektir.

Aktif Vivado projesi:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.xpr`

Bu proje yeniden oluşturulmayacaktır. Doğrulanmış ADI FMCOMMS2 blok tasarımı, AXU4EVB-P kartına uyarlanmış mevcut çalışma tabanı olarak kullanılacaktır.

## 2. Kesinleşen mimari kararlar

- Ana geliştirme kartı: **ALINX AXU4EVB-P**.
- RF transceiver: **AD9364**.
- Fiziksel dijital arayüz: FMC LPC üzerinden LVDS + LVCMOS18 kontrol sinyalleri.
- JESD204B tabanlı ADRV9008/ADRV9009 mimarisi bu kart için aktif hedef değildir; FMC LPC üzerinde gerekli GTH bağlantıları bulunmadığından önceki ADRV9009 yaklaşımı terk edilmiştir.
- FPGA veri yolu: ADI `axi_ad9361`, RX/TX `axi_dmac`, mevcut PS–PL AXI altyapısı.
- İlk yazılım hedefi: Vitis 2020.1 üzerinde AArch64 bare-metal/no-OS AD9364 uygulaması.
- Linux/PetaLinux desteği daha sonraki ve ayrı bir aşamadır; mevcut donanım kapanışının kabul kriteri değildir.

## 3. Doğrulama kaynaklarının öncelik sırası

Markdown raporları tek başına teknik doğruluk kaynağı olarak kullanılmayacaktır. Karar sırası şöyledir:

1. AXU4EVB-P/AXU4EV-P kart şemaları ve kullanıcı kılavuzları.
2. AD9364/FMCOMMS kart şeması.
3. Aktif Vivado kaynak grafiği, XDC dosyası ve implementasyon raporları.
4. Vivado tarafından üretilen bitstream/XSA içeriği ve Vitis platform çıktıları.
5. ADI resmi FMCOMMS2 referans tasarımları.
6. Proje içindeki Markdown talimat ve durum belgeleri.

## 4. Aşama 1 — Donanım tabanının doğrulanması

Durum: **Tamamlandı**

- [x] Aktif Vivado projesinin hedef parçası `xczu4ev-sfvc784-1-i` olarak doğrulandı.
- [x] Üst modülün `system_top` olduğu doğrulandı.
- [x] Aktif constraint dosyasının `system_constr.xdc` olduğu ve hem synthesis hem implementation için kullanıldığı doğrulandı.
- [x] Mevcut ADI blok tasarımının `axi_ad9361`, RX/TX AXI DMAC ve gerekli PS–PL altyapısını içerdiği doğrulandı.
- [x] PS DDR yapılandırmasının 4 GB AXU4EVB-P donanımına uygun olduğu kontrol edildi.
- [x] Bu kapanış sırasında PS DDR, MIO veya blok tasarım adresleri değiştirilmedi.

## 5. Aşama 2 — AD9364 FMC pin ve elektriksel constraint kapanışı

Durum: **Tamamlandı**

Aktif dosya:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/system_constr.xdc`

Uygulanan ve doğrulanan düzeltmeler:

- [x] AD9364 `RX_FRAME` / FPGA `rx_frame_in_p/n`, FMC `LA01_CC` karşılığı olan `L7/L6` pinlerine atandı.
- [x] AD9364 `FB_CLK` / FPGA `tx_clk_out_p/n`, FMC `LA08` karşılığı olan `N7/N6` pinlerine atandı.
- [x] `rx_clk_in_p/n`, `rx_frame_in_p/n` ve altı RX veri çiftinin tamamına `DIFF_TERM_ADV TERM_100` uygulandı.
- [x] Aktif-düşük `spi_csn` sinyaline `PULLTYPE PULLUP` eklendi.
- [x] `rx_clk_in_p` üzerine 4.00 ns, yani 250 MHz `rx_clk` constraint'i eklendi.
- [x] LVDS ve LVCMOS18 I/O standartlarının aktif portlara uygulandığı kontrol edildi.

Kalıcı regresyon testi:

`PROJECT/tests/Test-Axu4evAd9364Constraints.ps1`

Sonuç: `PASS: All`

## 6. Aşama 3 — Vivado synthesis, implementation ve bitstream kapanışı

Durum: **Tamamlandı**

- [x] Vivado 2020.1 ile synthesis ve implementation sıfırdan çalıştırıldı.
- [x] `write_bitstream` yüzde 100 tamamlandı.
- [x] Unrouted net sayısı sıfır olarak doğrulandı.
- [x] DRC error sayısı sıfır olarak doğrulandı.
- [x] Implement edilmiş pinler, terminasyonlar, SPI pull-up ve RX clock doğrudan Vivado veritabanından tekrar okundu.

Son timing sonucu:

| Metrik | Sonuç |
|---|---:|
| WNS | 0.144 ns |
| TNS | 0.000 ns |
| Setup failing endpoint | 0 |
| WHS | 0.010 ns |
| THS | 0.000 ns |
| Hold failing endpoint | 0 |
| RX clock periyodu | 4.000 ns |
| RX clock endpoint sayısı | 16.657 |

Vivado raporu açıkça `All user specified timing constraints are met.` sonucunu vermektedir.

Kalan DRC warning'leri:

- `REQP-1853`: 2 adet cascaded clock buffer warning'i.
- `RTSTAT-10`: 1 adet routable load bulunmayan net warning'i.

Bu üç kayıt error değildir; donanım testi öncesi raporda görünür tutulacaktır.

Bitstream:

`Related-Docs/hdl-main/projects/fmcomms2/axu4ev/fmcomms2_axu4ev.runs/impl_1/system_top.bit`

SHA-256:

`AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`

## 7. Timing modelinin bilinçli sınırları

Durum: **Açık fakat donanım kapanışını engellemiyor**

`check_timing` raporunda kalan kayıtlar:

- 1 adet `no_clock`: PS8 `EMIOSPI0SCLKO` hard-macro noktası.
- 1 adet `unconstrained_internal_endpoints`: PS8 `EMIOSPI0MI` hard-macro noktası.
- 8 adet `no_input_delay`: AD9364 RX paralel girişleri ve `spi_miso`.
- 13 adet `no_output_delay`: AD9364 TX paralel çıkışları, SPI çıkışları ve kontrol sinyalleri.

ADI FMCOMMS2 referans XDC dosyalarında da AD936x paralel portları için dış I/O delay değerleri verilmemektedir. AD9364 datasheet zamanlaması, kart üzerindeki iz gecikmeleri ve gerçek çalışma modu birlikte hesaplanmadan keyfi `set_input_delay`/`set_output_delay` değeri eklenmeyecektir. Bu konu laboratuvar ölçümü ve kart-zamanlama analiziyle kapatılacaktır.

## 8. Aşama 4 — Vivado'dan Vitis'e doğrulanmış handoff

Durum: **Tamamlandı**

- [x] Timing ve DRC kapıları geçmeden Vitis platformunun üzerine yazılmadı.
- [x] Bitstream'i içeren yeni `system_top.xsa` üretildi.
- [x] XSA içindeki `system_top.bit` dosyasının implement edilmiş bitstream ile birebir aynı olduğu doğrulandı.
- [x] Doğrulanmış XSA, canonical Vivado SDK ve Vitis platform konumlarına aktarıldı.
- [x] Vitis platformundaki `system_top.xsa`, `system_top.bit`, `psu_init.tcl`, BSP ve boot bileşenleri yeni donanıma göre yenilendi.

XSA SHA-256:

`AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118`

## 9. Aşama 5 — FSBL ve Vitis platform kapanışı

Durum: **Tamamlandı**

Yeni XSA ile platform üretimi sırasında FSBL'nin OCM alanını aşması tespit edildi. Uygulama kaynaklarına eklenen bölüm bazlı garbage collection tek başına yeterli olmadı; BSP sürücü kütüphaneleri de aynı bölümleme seçenekleriyle derlendi.

Vitis'te görülen `fmcomms2_axu4ev_hw (Out-of-date)` durumu ayrıca incelendi. Platformdaki PMU firmware tanımının yanlışlıkla A53 işlemcisine yöneldiği ve eksik/eski XPFM tesliminin platform durumunu bozduğu doğrulandı. PMU domain'i `psu_pmu_0` ve `mb-gcc` araç zinciriyle yeniden oluşturuldu; XPFM, domain metadatası ve boot teslimleri güncel XSA ile eşitlendi.

Kalıcı ayarlar:

- FSBL uygulama derleme seçenekleri: `-ffunction-sections -fdata-sections`.
- FSBL BSP işlemci derleme seçenekleri: `-ffunction-sections -fdata-sections`.
- Linker'ın mevcut `--gc-sections` seçeneği kullanılmaya devam edildi.

Sonuç:

- [x] FSBL OCM taşması giderildi.
- [x] `zynqmp_fsbl/executable.elf` üretildi.
- [x] Export edilen `boot/fsbl.elf` ile build çıktısının hash'leri eşleşti.
- [x] PMU firmware ve standalone BSP yeni XSA ile güncellendi.
- [x] PMU firmware hedefi `psu_pmu_0` ve derleyicisi `mb-gcc` olarak düzeltildi.
- [x] `fmcomms2_axu4ev_hw.xpfm` yeniden üretildi ve kalıcı handoff yollarında geçici sürücü harfi bırakılmadı.
- [x] Platform domain metadatası ve teslim hash'leri son doğrulamada eşleşti.

Son teslim SHA-256 değerleri:

- FSBL ELF: `C8EC16594420C96D0EDC5B64036BA9653C338C33BBD23C59AEC168F09470AC21`
- PMU firmware ELF: `F4D1FC0B82A64555883C79063278863654CEF80167826F2BB3541967B82FEF98`
- XPFM: `C85BBEBB5C3A76C5AA7D748BCCBF578269C319EE6091D750161039FFC4BA47D5`

## 10. Aşama 6 — AD9364 no-OS uygulaması

Durum: **Derleme ve ilk kart smoke-test'i tamamlandı**

Tespit edilen eski durum:

- `ad9364app` dizini çalışma alanında bulunmasına rağmen Vitis metadata'sına kayıtlı değildi.
- Proje eski `C:/Users/DELL/workspace/sdr_wrapper` platformuna ve `domain_psu_cortexa53_0` alanına bağlıydı.
- Release yapılandırmasında no-OS başlık dizinleri ve `libm` eksikti.
- `_ide` altındaki bitstream ve `psu_init.tcl`, yeni Vivado handoff'undan farklı ve eskiydi.

Uygulanan düzeltmeler:

- [x] Uygulama ve sistem projesi Vitis çalışma alanına kaydedildi.
- [x] Platform `fmcomms2_axu4ev_hw` olarak güncellendi.
- [x] Domain `standalone_domain`, işlemci `psu_cortexa53_0` olarak güncellendi.
- [x] Release include path'leri kalıcı workspace değişkenleriyle düzeltildi.
- [x] Matematik kütüphanesi `m` Release link ayarına eklendi.
- [x] `AD9361_DEVICE=0` ve `AD9364_DEVICE=1` doğrulandı.
- [x] AArch64 Release ELF üretildi.
- [x] Uygulamanın `_ide` bitstream ve PS-init kopyaları doğrulanmış platform çıktısıyla eşitlendi.
- [x] Uygulama JTAG üzerinden A53-0 üzerinde çalıştırıldı ve PS_UART çıktısı kaydedildi.
- [x] AD936x Rev 2 başlatması, AXI ADC/DDS çekirdekleri ve ilk DMA örnek aktarımı başarıyla tamamlandı.

ELF:

`Vitis/workspace/ad9364app/Release/ad9364app.elf`

ELF doğrulaması:

- Format: ELF64.
- Makine: AArch64.
- Tür: Executable.
- Linker girişi: `_vector_table`; DDR başlangıcı `0x0`.
- Text/Data/BSS toplamı: 463.468 bayt.

ELF SHA-256:

`A9B5B372C4E79FD263752F0C10B9162D01A32EC1CA114B0B4C98F6F5E293D5F7`

## 11. Aşama 7 — Kart üzerinde bring-up

Durum: **Temel bring-up tamamlandı; RF/IQ veri doğrulaması sürüyor**

Ön koşullar:

- AXU4EVB-P kapalıyken AD9364/FMCOMMS kartının FMC konektörüne doğru yönde takılması.
- Bank 65'in FMC çalışma modu için 1.8 V konumunda olduğunun kart kılavuzundan fiziksel olarak doğrulanması.
- UART0 seri portunun 115200-8-N-1 olarak hazırlanması.
- JTAG bağlantısı ve kart boot-mode anahtarlarının seçilen akışa göre kontrol edilmesi.

İzlenecek sıra:

1. [ ] Kart revizyonu, FMC yönü ve Bank 65/jumper konumlarının fotoğraflı veya yazılı fiziksel kaydı tamamlanacak.
2. [x] JTAG ile PS initialization çalıştırıldı.
3. [x] Doğrulanmış `system_top.bit` dosyası FPGA'ya programlandı.
4. [x] `ad9364app.elf` dosyası A53-0'a yüklendi.
5. [x] UART logunda `AD936x Rev 2 successfully initialized` sonucu kaydedildi.
6. [x] AD9364 initialization akışı hata vermeden tamamlandı.
7. [x] AXI ADC ve DDS çekirdekleri sırasıyla 61.441.040 Hz ve 61.439.514 Hz ile başlatıldı.
8. [x] İlk DMA aktarımı 65.536 örnek, 2 kanal ve 16 bit formatıyla `Done.` sonucuna ulaştı.
9. [ ] Yakalanan örneklerin DC, saturasyon, veri tekrarı ve kanal sıralaması açısından incelenmesi.
10. [ ] Gerekirse AD9364 dijital arayüz delay tuning/calibration çalıştırılması.
11. [x] PMU firmware JTAG ile `MicroBlaze PMU` hedefine FSBL'den önce yüklenip çalıştırıldı; `PMU-FW is not running` uyarısı kaldırıldı.

## 12. Aşama 8 — RF veri işleme ve spektrum

Durum: **Başlamaya hazır; ilk öncelik RX örnek bütünlüğü**

1. [ ] Güvenilir RX capture boyutunun ve örnek formatının sabitlenmesi.
2. [ ] IQ örneklerinin DDR'den alınması ve ölçeklendirilmesi.
3. [ ] Pencereleme ve FFT yönteminin seçilmesi.
4. [ ] CPU tabanlı FFT ile ilk spektrum doğrulaması.
5. [ ] Performans ihtiyacına göre PL tabanlı FFT veya streaming mimarisinin değerlendirilmesi.
6. [ ] TX test tonu ve RX loopback testlerinin eklenmesi.
7. [ ] Otomatik RF smoke-test ve veri bütünlüğü testlerinin oluşturulması.

## 13. Opsiyonel Linux/PetaLinux aşaması

Durum: **Başlatılmadı**

Bare-metal bring-up başarıyla tamamlandıktan sonra:

1. [ ] PetaLinux 2020.1 projesi oluşturulacak veya mevcut proje yeni XSA ile güncellenecek.
2. [ ] AD9361/AD9364 IIO, AXI ADC, AXI DMAC ve gerekli clock/device-tree düğümleri eklenecek.
3. [ ] Kernel ve rootfs seçenekleri doğrulanacak.
4. [ ] `iio_info` ile cihaz keşfi yapılacak.
5. [ ] `libiio`/IIO Oscilloscope ile RX/TX testi gerçekleştirilecek.

## 14. Kalıcı doğrulama araçları

- `PROJECT/tests/Test-Axu4evAd9364Constraints.ps1`
- `PROJECT/tests/Inspect-Axu4evAd9364Project.tcl`
- `PROJECT/tests/Build-Axu4evAd9364Bitstream.tcl`
- `PROJECT/tests/Export-Axu4evAd9364Xsa.tcl`
- `PROJECT/tests/Update-Axu4evVitisPlatform.tcl`
- `PROJECT/tests/Fix-Axu4evFsblBuild.tcl`
- `PROJECT/tests/Build-Axu4evAd9364App.tcl`
- `PROJECT/tests/Sync-Axu4evAd9364IdeHardware.ps1`
- `PROJECT/tests/Test-Axu4evHandoffArtifacts.ps1`
- `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl`
- `PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1`

Son otomatik doğrulama sonuçları:

- Constraint testi: PASS.
- Vivado implementasyon assertion'ları: PASS.
- Timing kapanışı: PASS.
- DRC error kontrolü: PASS.
- XSA/bitstream/Vitis/IDE hash bütünlüğü: PASS.
- FSBL build/export bütünlüğü: PASS.
- AD9364 Release ELF build: PASS.
- Vitis XPFM, PMU hedefi ve domain metadata bütünlüğü: PASS.
- Kart üstü FSBL, AD9364 başlatma, AXI çekirdek ve DMA smoke-test'i: PASS.
- PMUFW → FPGA → FSBL → AD9364 uygulaması JTAG başlatma sırası: PASS.
- PMUFW etkin kart smoke-test'i; AD9364 initialization ve DMA: PASS.

## 15. Değişiklik güvenliği

- Mevcut checkout başlangıçta kullanıcı değişiklikleri içeriyordu.
- İlgisiz değişiklikler geri alınmadı, stage edilmedi veya commit edilmedi.
- Bu aşamada PS DDR, MIO, block design adresleri, Linux kaynakları ve AD9364 uygulama C kaynakları değiştirilmedi.
- İlk kart smoke-test'i SPI/AD9364 başlatmasını ve DMA tamamlanmasını kanıtlamıştır; yakalanan I/Q örneklerinin doğruluğu ve RF performansı henüz kanıtlanmış sayılmayacaktır.
- Sonraki donanım adımlarında her programlama/boot işlemi kullanılan bitstream, XSA ve ELF hash'leri kaydedilerek yapılacaktır.

## 16. 16 Temmuz 2026 — doğrulanmış JTAG başlatma düzeltmesi

Önceki FSBL tabanlı JTAG kaydı güncel çalışma alanı için geçerli değildir. Çalışma alanındaki mevcut FSBL (`B65950BA...`) A53 üzerinde SerDes/PCIe kalibrasyonunda kaldığı için DDR handoff'unu tamamlamamaktadır. Ayrıca yalnızca `psu_init` ve `psu_post_config` çağrılarından oluşan doğrudan akış yetersizdir; bu XSA'nın `psu_post_config` prosedürü boştur. PS–PL izolasyonu kaldırılmadan ve fabric reset sırası çalıştırılmadan uygulama AD9364 ürün kimliğini `0x00` okumuş ve `-22` SPI hataları üretmiştir.

Kart üzerinde doğrulanan kalıcı sıra şöyledir:

1. PSU JTAG güvenlik kapılarını `0xffca0038 = 0x1ff` ile aç.
2. PMUFW'yi `MicroBlaze PMU` hedefine indir ve çalıştır.
3. Doğrulanmış bitstream'i programla.
4. Cortex-A53 #0'ı temiz register resetine al.
5. `psu_init.tcl` dosyasını yükle ve `force-mem-accesses 1` ile `psu_init` çalıştır.
6. Sırayla `psu_ps_pl_isolation_removal` ve `psu_ps_pl_reset_config` çalıştır.
7. DDR yaz/oku testi yap.
8. Mevcut uygulama ELF'ini A53-0'a indir, zorlanmış bellek erişimini kapat ve çalıştır.

Bu sıra `PROJECT/tests/Launch-Axu4evAd9364Jtag.tcl` içine aktarıldı; betik Release ELF varsa onu, yoksa Debug ELF'i seçer ve stale FSBL'yi çalıştırmaz. Statik sıra testi `PROJECT/tests/Test-Axu4evJtagLaunchScript.ps1` ile korunur.

16 Temmuz 2026 kart kanıtı:

- `cf-ad9361-lpc: Successfully initialized (61439514 Hz)`
- `ad9361_init : AD936x Rev 2 successfully initialized`
- `cf-ad9361-dds-core-lpc: Successfully initialized (61441040 Hz)`
- `DMA_EXAMPLE: address=0x60c00 samples=65536 channels=2 bits=16`
- `Done.`

Bu doğrulamada kullanılan güncel SHA-256 değerleri:

- Bitstream: `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4`
- XSA: `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118`
- PMUFW: `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB`
- `psu_init.tcl`: `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B`
- Debug `ad9364app.elf`: `320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC`

Önceki bölümlerdeki FSBL/Release ELF hash'leri tarihsel kayıt olarak değerlendirilmelidir; güncel JTAG smoke-test'i yukarıdaki doğrudan PS/DDR/PS–PL akışı ve Debug ELF ile yapılmıştır.

## 17. 16 Temmuz 2026 — yeniden açılışa dayanıklı Golden/Workspace düzeni

Manuel XSCT komutlarını her bilgisayar veya kart açılışında tekrarlamamak için iki ayrı çalışma yolu oluşturuldu:

- **Golden:** `PROJECT/tools/Start-Axu4evAd9364Golden.cmd`, `CURRENT` ile seçilen değişmez sürümü manifest boyutları ve SHA-256 değerleriyle doğrulayıp çalıştırır.
- **Workspace:** `PROJECT/tools/Start-Axu4evAd9364Workspace.cmd`, güncel Vivado/Vitis teslim zincirini çapraz doğrular ve yalnızca aday çıktıları çalıştırır.

Seçili Golden sürüm `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1` dizinidir. BIT, XSA, PMUFW, `psu_init.tcl` ve Debug uygulama ELF'i burada sabitlenmiş; `CURRENT` ayrı seçim dosyasında tutulmuştur. `Promote-Axu4evAd9364Release.ps1` mevcut sürümün üzerine yazmayı reddeder ve `CURRENT` değerini kendiliğinden değiştirmez. Yeni sürüm ancak Workspace kart testi geçtikten sonra `Set-Axu4evAd9364CurrentRelease.ps1` ile açıkça seçilecektir.

Ortak orkestratör `Invoke-Axu4evAd9364Launch.ps1` dört çalıştırma artefaktını seçer, bütünlük kontrollerini tamamlar, XSCT ortamını hazırlar ve tarihli log üretir. Ortak Tcl akışı uygulama indirmesini DDR `0x00100000 = 0xA5A5A5A5` yaz/oku karşılaştırmasının arkasına alır. FSBL bu akışta kullanılmaz.

Operatör sırası:

1. JTAG ve PS_UART'ı bağla; PuTTY'yi `115200-8-N-1` aç.
2. Önceki oturum instruction-transfer timeout ile bittiyse kartı 10–15 saniye kapalı tutarak güç döngüsü yap.
3. Normal kullanımda Golden `.cmd` dosyasına çift tıkla.
4. UART'ta `AD936x Rev 2 successfully initialized`, `DMA_EXAMPLE:` ve `Done.` işaretlerini doğrula.
5. Yalnızca yeni derleme testi için Workspace `.cmd` dosyasını kullan.
6. Aday aynı UART/DMA kabulünü geçmeden terfi/seçim yapma.

Otomatik bütünlük, kuru çalışma ve sıralama testleri geçmiştir. Golden `.cmd` dosyası hiçbir manuel XSCT komutu olmadan çalıştırılmış; PMUFW, FPGA, doğrudan PS/DDR/PS–PL hazırlığı, DDR `A5A5A5A5` kapısı, AD9364 Rev 2 başlatması ve DMA `Done.` sonucu 16 Temmuz 2026 tarihinde doğrulanmıştır. Kabul logu `20260716-120323-golden.log` dosyasıdır. PetaLinux aşamasında Golden XSA sabit donanım referansı, yeni Workspace XSA'ları ise aday olarak kullanılacaktır.

## 18. Git kapanışı ve ana dal durumu

Doğrulanmış AXU4EVB-P + AD9364 çalışması yerel `main` dalına çatışmasız fast-forward ile alındı. Merge sonrasında release, Golden/Workspace wrapper, XSCT sıra/yol ve Vitis handoff testlerinin beşi yeniden çalıştırılarak geçti. Yerel `main` ile doğrulanmış HEAD aynı `9d2f06a` commitine işaret etti.

`main`, GitHub üzerindeki `origin/main` dalına başarıyla pushlandı:

- Repo: `Maxixler/FPGA-Profen`
- Uzak dal: `main`
- Push aralığı: `6b78d06..9d2f06a`
- Uzak HEAD: `9d2f06acca380778cae29ddaf4bbf327048e15b5`

Çalışma alanındaki kullanıcıya ait 1081 staged dosya ile Vitis/Vivado üretim çıktıları merge veya push kapsamına alınmadı. Kirli çalışma ağacını taşımamak için checkout zorlanmadı; `codex/axu4ev-pmufw-bringup` dalı çalışma alanında korunurken yerel ve uzak `main` doğrulanmış committe sabitlendi.

## 19. 16 Temmuz 2026 — AD9364 2.4 GHz Wi-Fi RF algılama adayı

İlk gerçek RF doğrulaması için çalışma `codex/wifi-rf-detection` dalındaki bağımsız worktree'de sürdürüldü. Amaç Wi-Fi paketlerini çözmek değil; AXU4EVB-P + AD9364 alıcı yolunun kontrollü telefon hotspot'u ile oluşan 2.4 GHz RF enerji ve burst değişimini güvenilir biçimde ölçtüğünü kanıtlamaktır.

Donanım kararı:

- AD9364 `1x1` transceiver'dır; RXA ve RXB iki eşzamanlı anten kanalı değildir.
- İlk kabul testinde yalnızca 2.4 GHz, 50 ohm anten RXB'ye bağlanacaktır.
- Yazılım `B_BALANCED / RXB` girişini seçer; RXA, TXA ve TXB boş bırakılır.
- `REF_CLK` anten girişi değildir.
- TX DMAC, DAC ve DDS Wi-Fi RF test yolunda devre dışıdır; TX maksimum attenuation ve RX ENSM readback kontrolleri zorunludur.

Tamamlanan geliştirme kapıları:

1. Golden BIT/PMUFW/`psu_init.tcl` ile yalnız Release uygulama ELF'ini birleştiren `Candidate` başlatıcı eklendi. Candidate modu Debug ELF'e düşmez.
2. Host üzerinde test edilen saf I/Q metrik motoru eklendi: güç, peak, clipping, medyan, delta ve PASS/INCONCLUSIVE sınıflandırması.
3. RXB-only, finite ve non-cyclic DMA capture katmanı eklendi. Tekrarlı DMA completion, 32-bit adres sınırı, cache ownership, sabit gain reuse ve sayaç taşmaları davranış testleriyle korundu.
4. UART baseline/active kanal taraması, kanal seçimi, 20 monitor penceresi ve final verdict state machine'i eklendi.
5. `WIFI_RF_TEST` Release uygulamasına entegre edildi. Wi-Fi yolu TX başlatmaz; hata yolları cleanup üzerinden gerçek status döndürür.
6. Vitis 2020.1 Release build wrapper'ı izole kısa temp workspace ve Windows Job Object ile güvenli hâle getirildi. Launcher askıda kalsa veya child process detach olsa bile timeout/cleanup yalnız wrapper'ın job ağacını etkiler.

Son Release adayı:

- Yol: `Vitis/workspace/ad9364app/Release/ad9364app.elf`
- Boyut: `855568` bayt
- SHA-256: `C95CD5478275F2CA7911D1984D544AECEE44034BF368FF238221957BA4A500B1`
- Doğrulanan semboller: `wifi_rf_test_run`, `wifi_rf_prepare_rx_only`, `wifi_rf_capture_channel`, `wifi_rf_analyze_block`

Task 6 kart öncesi kapıları iki kez geçmiştir: metrics, source/host, Candidate launcher, JTAG sırası, Golden release bütünlüğü ve handoff artifact bütünlüğü PASS. Candidate kuru çalışması Golden BIT, PMUFW ve `psu_init.tcl` hash'lerini aynen korurken uygulama olarak yukarıdaki Release ELF'i seçmiştir.

### Yarın devam edilecek fiziksel kabul

- JTAG ve PS_UART bağlanacak; PuTTY `115200-8-N-1` açılacak.
- Tek 2.4 GHz anten RXB'ye bağlanacak; hotspot başlangıçta kapalı ve telefondan RXB'ye mesafe 1-3 metre olacak.
- `Start-Axu4evAd9364Candidate.cmd` ile ilk koşu yapılacak.
- Baseline hotspot kapalı, active scan ve 10 saniyelik monitor süresince hotspot açık ve gerçek istemci trafiği var olacak.
- İki ardışık koşuda `RX_ONLY: PASS`, `PLATFORM: PASS`, `RF_ACTIVITY: PASS` ve `WIFI_RF_TEST: PASS` aranacak.
- İki gerçek PASS görülmeden evidence dosyası oluşturulmayacak, eşikler değiştirilmeyecek ve yeni Golden terfisi yapılmayacak.

Bu oturumun sonunda Task 1-5 tamamlanmış ve bağımsız review'ları CLEAN durumundadır. Task 6 `READY_FOR_HARDWARE` durumunda bırakılmıştır. Feature dalı yereldir; `main`, `origin/main`, mevcut Golden release ve `CURRENT` değiştirilmemiştir. Push/merge yarınki kart kabulünden sonra ayrıca kararlaştırılacaktır.

## 20. 17 Temmuz 2026 — FDD düzeltmesi ve fiziksel RF kabulü

İlk Candidate kart koşusunda AD9364 başarıyla başlatıldıktan sonra `PLATFORM: FAIL stage=RX_ONLY error=-5` görüldü. Kök neden donanım veya SPI değildi: uygulama FDD modunda yapılandırılmışken RX güvenlik kapısı ENSM readback'inin yalnızca `ENSM_MODE_RX` olmasını bekliyordu. Hata önce host regresyonunda `FDD prepare (actual=-5 expected=0)` olarak yeniden üretildi.

Düzeltmede RXB seçimi ve 89.75 dB TX attenuation korunarak mevcut ENSM durumu önce okunur hâle getirildi. `ENSM_MODE_FDD` ve `ENSM_MODE_PINCTRL_FDD_INDEP` güvenli FDD durumları olarak kabul edildi; FDD dışındaki çalışma için `ENSM_MODE_RX` geçişi ve ikinci readback doğrulaması aynen korundu. Sürücünün özel `pdata` alanına bağımlılık eklenmedi.

Yeni Release uygulaması:

- Yol: `Vitis/workspace/ad9364app/Release/ad9364app.elf`
- Boyut: `855568` bayt
- SHA-256: `7E89D1A7D912661FD9843CFDAF48D4A81135EBE632FDF3E93B178CE01D92C2F0`
- Global text sembolleri: `wifi_rf_test_run`, `wifi_rf_prepare_rx_only`, `wifi_rf_capture_channel`, `wifi_rf_analyze_block`

Yeni ELF ile altı yazılım/preflight kapısı yeniden PASS verdi ve Candidate kuru çalışması doğrulanmış Golden BIT, PMUFW ve `psu_init.tcl` ile tam olarak bu Release ELF'i seçti.

Fiziksel kabul, tek 2.4 GHz anten RXB'ye bağlıyken ve telefon hotspot'u gerçek istemci trafiği üretirken iki ardışık Candidate koşusuyla tamamlandı:

1. Koşu: CH6 / 2437 MHz seçildi; delta power `+3.14 dB`, delta burst `+32 pp`.
2. Koşu: CH5 / 2432 MHz seçildi; delta power `+4.77 dB`, delta burst `+49 pp`.

Her iki koşuda `RX_ONLY: PASS`, tüm bloklarda `DMA=OK` ve `CLIP=0`, ardından `PLATFORM: PASS`, `RF_ACTIVITY: PASS` ve `WIFI_RF_TEST: PASS` elde edildi. CH5/CH6 komşuluğu, 20 MHz Wi-Fi enerjisinin 5 MHz aralıklı ölçüm noktalarına yayılmasıyla uyumludur; bu aşamada paket veya payload çözümü iddia edilmez.

Task 6 fiziksel kabulü tamamlanmıştır. Kanıt: `PROJECT/tests/evidence/axu4ev-ad9364-wifi-rf-pass.txt`. Sonraki geliştirme fazları FFT/grafik, sürekli I/Q streaming ve PetaLinux/IIO entegrasyonudur. Golden `CURRENT` bu kabul sırasında değiştirilmemiştir.
