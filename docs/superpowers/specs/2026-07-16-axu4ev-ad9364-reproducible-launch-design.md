# AXU4EVB-P + AD9364 Tekrarlanabilir Başlatma Tasarımı

**Tarih:** 16 Temmuz 2026  
**Durum:** Kullanıcı tarafından yaklaşım onaylandı; uygulama öncesi tasarım  
**Hedef ortam:** Windows, Xilinx Vitis/XSCT 2020.1, AXU4EVB-P, AD9364, JTAG ve PS_UART

## 1. Amaç

Bilgisayar veya kart kapatılıp yeniden açıldıktan sonra, daha önce kart üzerinde doğrulanmış AXU4EVB-P + AD9364 sisteminin XSCT komutları elle girilmeden tek tıklamayla tekrar çalıştırılması amaçlanır. Çözüm aynı zamanda yeni Vitis/Vivado çıktılarının denenmesine izin vermeli, ancak yeni aday doğrulanmadan çalışan referans sürümün üzerine yazmamalıdır.

FPGA yapılandırması, PMU firmware ve DDR durumu güç kesildiğinde kaybolduğu için disk üzerindeki projenin korunması tek başına yeterli değildir. Her güç açılışında karta kontrollü yükleme yapılması zorunludur.

## 2. Kapsam

Çözüm şunları sağlar:

- Bugün kartta doğrulanmış dosyaları değişmez bir **golden release** olarak paketleme.
- Golden release ile tek tık otomatik JTAG başlatma.
- Vitis workspace içindeki güncel aday çıktılarla ayrı bir geliştirme başlatması.
- Başlatmadan önce dosya varlığı ve SHA-256 bütünlük kontrolü.
- XSCT ve UART incelemesi için tarihli çalışma logları.
- Kartta başarıyla doğrulanan adayın açık bir komutla yeni golden release'e dönüştürülmesi.
- Gelecekte PetaLinux boot dosyalarının aynı release modeline eklenebilmesi.

Çözüm şu aşamada şunları kapsamaz:

- RF ölçümünün otomatik değerlendirilmesi veya spektrum analizi.
- Anten, attenuator veya TX güç güvenliğinin otomatik denetlenmesi.
- PetaLinux image üretimi.
- Vitis/Vivado cache klasörlerinin Git'e eklenmesi.
- Mevcut 1081 adet önceden stage edilmiş bağımsız dosyanın temizlenmesi veya yeniden sınıflandırılması.

## 3. Seçilen yaklaşım: hibrit release modeli

İki bağımsız çalışma yolu bulunur:

### 3.1 Golden modu

Referans ölçüm, demo, hata kurtarma ve bilinen çalışan sistemin tekrar başlatılması için kullanılır. Tüm dosyalar release klasöründen alınır ve manifest hash'leri uyuşmadan karta hiçbir şey yüklenmez.

### 3.2 Workspace modu

Yeni HDL, RF uygulaması veya platform değişikliklerini denemek için kullanılır. Dosyalar mevcut Vivado/Vitis çalışma alanından alınır. Workspace modu golden paketi değiştirmez. Kullanıcı çıktıyı kartta ve UART'ta doğruladıktan sonra ayrı promotion işlemini çalıştırır.

Bu ayrım, geliştirme kolaylığını korurken çalışan referansın yanlış build, `Out-of-date` platform veya IDE tarafından üzerine yazılan artifact nedeniyle kaybolmasını önler.

## 4. Dosya yerleşimi

Önerilen kalıcı yapı:

```text
PROJECT/
  releases/
    axu4ev-ad9364/
      2026-07-16-bringup-v1/
        hardware/
          system_top.bit
          system_top.xsa
          psu_init.tcl
        firmware/
          pmufw.elf
        applications/
          ad9364app.elf
        manifest.json
        README.md
      CURRENT
  tools/
    Start-Axu4evAd9364Golden.cmd
    Start-Axu4evAd9364Workspace.cmd
    Invoke-Axu4evAd9364Launch.ps1
    Promote-Axu4evAd9364Release.ps1
  logs/
    jtag/
  tests/
    Launch-Axu4evAd9364Jtag.tcl
    Test-Axu4evRelease.ps1
```

`CURRENT`, varsayılan golden release klasör adını içeren küçük bir metin dosyasıdır. Release klasörleri değişmez kabul edilir; promotion mevcut klasörün üzerine yazmak yerine yeni bir sürüm klasörü oluşturur.

`PROJECT/logs/jtag` çalışma sırasında oluşturulur ve `.gitignore` ile Git dışında tutulur.

## 5. Golden manifest

`manifest.json` aşağıdaki bilgileri taşır:

- Release kimliği ve oluşturma zamanı.
- Hedef kart, FPGA parçası, RF cihazı ve araç sürümü.
- Her artifact için release-relative yol, byte uzunluğu ve SHA-256.
- Kartta doğrulama durumu.
- Doğrulanan UART işaretleri.
- Kaynak Git commit'i ve kaynak workspace yolları.
- Başlatma sırası sürümü.

İlk golden release aşağıdaki doğrulanmış artifact kimliklerini kullanır:

| Artifact | SHA-256 |
|---|---|
| `system_top.bit` | `AFC016C6594F2103B854A4EA3B13FFF023452F1D6340CC0E7D8225515EFCFCD4` |
| `system_top.xsa` | `AE0F23D2D87A403528870858F78F73D76DD2C2B4B224B0E0A78D2FCE1EB0B118` |
| `pmufw.elf` | `9AABFD07EA03CBEE81A27E1B22BF9ADF86AACB919A865F8D6AA5A09AF360D3AB` |
| `psu_init.tcl` | `CDC1A5C457B0A77B8A2BB43AEF4D046889A1B4F3E60992819379F31D28C1539B` |
| `ad9364app.elf` | `320F89C78E932125F5A198DFED96F5101D93D42C95B026216C5F844C5E676FDC` |

## 6. Otomatik başlatma akışı

Kullanıcı `Start-Axu4evAd9364Golden.cmd` dosyasına çift tıklar. Başlatıcı:

1. Proje kökünü kendi konumundan belirler; kullanıcı adına bağlı mutlak proje yolu içermez.
2. `C:\Xilinx\Vitis\2020.1\bin\xsct.bat` varlığını kontrol eder.
3. `CURRENT` ile seçilen release'i ve manifesti okur.
4. Tüm artifact yollarını, boyutlarını ve SHA-256 değerlerini doğrular.
5. Tarihli log dosyasını hazırlar.
6. XSCT'yi release kökü ve log yolu ile başlatır.
7. XSCT doğrulanmış sırayı uygular:
   - local hardware server'a bağlanır;
   - PSU JTAG güvenlik kapılarını açar;
   - PMUFW'yi `MicroBlaze PMU` hedefine indirip çalıştırır;
   - bitstream'i programlar;
   - Cortex-A53 #0'ı temiz register resetine alır;
   - `force-mem-accesses 1` ile `psu_init` çalıştırır;
   - `psu_ps_pl_isolation_removal` çalıştırır;
   - `psu_ps_pl_reset_config` çalıştırır;
   - DDR scratch adresinde yaz/oku testi yapar;
   - uygulama ELF'ini A53-0'a indirir;
   - zorlanmış bellek erişimini kapatır ve uygulamayı çalıştırır.
8. XSCT işlemi başarısızsa pencereyi açık tutar ve hata/log yolunu gösterir.

UART çıktısı PS_UART üzerinden PuTTY gibi ayrı bir terminalde izlenir. Otomatik başarı ölçütü XSCT yükleme zincirinin tamamlanmasıdır; AD9364 ve DMA'nın gerçek kart başarı sonucu UART işaretleriyle kullanıcı tarafından doğrulanır. Daha sonra seri port yakalama otomasyonu eklenebilir, ancak ilk sürümde COM port sahipliği ve PuTTY çakışması yaratılmaz.

## 7. Workspace modu ve promotion

`Start-Axu4evAd9364Workspace.cmd`, aynı doğrulama ve XSCT motorunu kullanır; artifact kaynağı release yerine mevcut Vivado/Vitis yollarıdır. Başlatmadan önce workspace artifact hash'leri loga yazılır.

`Promote-Axu4evAd9364Release.ps1` yalnızca kullanıcı tarafından açıkça çalıştırılır. İşlem:

1. Workspace artifact'lerini ve gerekli test sonuçlarını kontrol eder.
2. Yeni ve benzersiz bir release kimliği ister veya üretir.
3. Artifact'leri yeni release klasörüne kopyalar.
4. Kopya sonrası SHA-256 ve boyutları yeniden hesaplar.
5. Manifest ve README üretir.
6. Yeni release'i doğrudan `CURRENT` yapmaz; kart doğrulaması kaydedildikten sonra ayrı onayla `CURRENT` güncellenir.

Bu iki aşamalı promotion, yanlış adayın bilinen çalışan varsayılan sürüm haline gelmesini önler.

## 8. Hata yönetimi ve güvenlik

- Eksik veya hash'i farklı artifact varsa programlama başlamadan işlem durur.
- JTAG hedefi bulunamazsa kullanıcıya kart gücü, JTAG kablosu ve hardware server kontrolü gösterilir.
- `Instruction transfer timeout` sonrasında otomatik tekrar veya sonsuz reset uygulanmaz; gerçek güç döngüsü istenir.
- DDR yaz/oku testi başarısızsa uygulama indirilmez.
- Golden release dosyalarının üzerine yazılmaz.
- TX otomatik olarak etkinleştirilmez; RF davranışı mevcut uygulama ELF'inin yapılandırmasıyla sınırlıdır.
- Loglar artifact veya gizli bilgi içermez; yalnızca yollar, hash'ler ve araç çıktıları kaydedilir.

## 9. Anten/RF geliştirmeleri ve PetaLinux uyumu

Anten, LO, bant genişliği, örnekleme hızı veya gain ayarı değiştikçe uygulama ELF'i yeni bir aday olarak değerlendirilir. Donanım değişmediyse aynı BIT/XSA farklı uygulama sürümleriyle yeniden paketlenebilir; manifest hangi bileşenin değiştiğini görünür tutar.

PetaLinux aşamasında release yapısı genişletilir:

```text
linux/
  BOOT.BIN
  image.ub
  boot.scr
  system.dtb
```

Bare-metal golden release korunur. PetaLinux release'i aynı BIT/XSA kökenini ve kendi boot artifact hash'lerini kaydeder. Böylece Linux çalışması başarısız olduğunda bare-metal referans testi hızlıca geri çağrılabilir.

## 10. Test stratejisi

Uygulama testleri şu kapıları içerir:

- Release manifest şeması, dosya varlığı, boyut ve SHA-256 testi.
- Golden ve workspace launcher'larının kullanıcıya özel mutlak proje yolu içermediğinin testi.
- XSCT komut sırası testi; stale FSBL kullanımının yasaklanması.
- DDR testinin uygulama indirmesinden önce olduğunun statik testi.
- Eksik/bozuk artifact ile preflight'ın programlamadan önce kırmızıya düşmesi.
- Promotion işleminin mevcut release'in üzerine yazmadığının testi.
- Mevcut handoff bütünlük ve XSCT yol testlerinin regresyon çalıştırması.
- İlk golden release için gerçek kart smoke-test'i ve UART kanıtı.

## 11. Kabul ölçütleri

Çalışma aşağıdaki koşullarda tamamlanmış sayılır:

1. Bilgisayar ve kart tamamen kapatılıp yeniden açıldıktan sonra golden launcher tek tıkla çalışır.
2. Kullanıcı XSCT komutlarını elle girmez.
3. Hash doğrulaması geçmeden JTAG programlama başlamaz.
4. DDR testi geçmeden uygulama yüklenmez.
5. PuTTY'de AD9364 Rev 2, AXI çekirdek başlangıcı, DMA parametreleri ve `Done.` görülür.
6. Workspace launcher golden dosyaları değiştirmez.
7. Yeni release promotion işlemi mevcut golden release'in üzerine yazmaz.
8. Tüm otomatik testler geçer ve çalışma logu üretilir.

## 12. Uygulama sırası

Uygulama; önce testler, ardından preflight/manifest, golden paket, ortak XSCT motoru, launcher'lar, workspace modu ve son olarak promotion aracı sırasıyla geliştirilecektir. İlk gerçek kart testi golden launcher ile temiz güç döngüsünden sonra yapılacaktır.
