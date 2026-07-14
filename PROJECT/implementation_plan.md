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

Kalıcı ayarlar:

- FSBL uygulama derleme seçenekleri: `-ffunction-sections -fdata-sections`.
- FSBL BSP işlemci derleme seçenekleri: `-ffunction-sections -fdata-sections`.
- Linker'ın mevcut `--gc-sections` seçeneği kullanılmaya devam edildi.

Sonuç:

- [x] FSBL OCM taşması giderildi.
- [x] `zynqmp_fsbl/executable.elf` üretildi.
- [x] Export edilen `boot/fsbl.elf` ile build çıktısının hash'leri eşleşti.
- [x] PMU firmware ve standalone BSP yeni XSA ile güncellendi.

## 10. Aşama 6 — AD9364 no-OS uygulaması

Durum: **Derleme tamamlandı; kart üzerinde çalıştırma bekliyor**

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

Durum: **Sıradaki ana aşama**

Ön koşullar:

- AXU4EVB-P kapalıyken AD9364/FMCOMMS kartının FMC konektörüne doğru yönde takılması.
- Bank 65'in FMC çalışma modu için 1.8 V konumunda olduğunun kart kılavuzundan fiziksel olarak doğrulanması.
- UART0 seri portunun 115200-8-N-1 olarak hazırlanması.
- JTAG bağlantısı ve kart boot-mode anahtarlarının seçilen akışa göre kontrol edilmesi.

İzlenecek sıra:

1. [ ] Kart enerjisizken FMC bağlantısı ve jumper/gerilim kontrolü.
2. [ ] JTAG ile PS initialization çalıştırılması.
3. [ ] Doğrulanmış `system_top.bit` dosyasının FPGA'ya programlanması.
4. [ ] `ad9364app.elf` dosyasının A53-0'a yüklenmesi.
5. [ ] UART logunda AD9364 SPI kimlik/başlatma sonucunun kaydedilmesi.
6. [ ] AD9364 initialization ve calibration adımlarının başarı durumunun doğrulanması.
7. [ ] AXI ADC/DAC core ve DMAC durum register'larının kontrol edilmesi.
8. [ ] İlk RX buffer capture işleminin gerçekleştirilmesi.
9. [ ] Yakalanan örneklerin DC, saturasyon, veri tekrarı ve kanal sıralaması açısından incelenmesi.
10. [ ] Gerekirse AD9364 dijital arayüz delay tuning/calibration çalıştırılması.

## 12. Aşama 8 — RF veri işleme ve spektrum

Durum: **Bring-up sonrasına ertelendi**

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

Son otomatik doğrulama sonuçları:

- Constraint testi: PASS.
- Vivado implementasyon assertion'ları: PASS.
- Timing kapanışı: PASS.
- DRC error kontrolü: PASS.
- XSA/bitstream/Vitis/IDE hash bütünlüğü: PASS.
- FSBL build/export bütünlüğü: PASS.
- AD9364 Release ELF build: PASS.

## 15. Değişiklik güvenliği

- Mevcut checkout başlangıçta kullanıcı değişiklikleri içeriyordu.
- İlgisiz değişiklikler geri alınmadı, stage edilmedi veya commit edilmedi.
- Bu aşamada PS DDR, MIO, block design adresleri, Linux kaynakları ve AD9364 uygulama C kaynakları değiştirilmedi.
- Sonraki donanım adımlarında her programlama/boot işlemi kullanılan bitstream, XSA ve ELF hash'leri kaydedilerek yapılacaktır.
