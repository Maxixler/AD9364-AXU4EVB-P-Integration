# AXU4EV + AD9364 Periyodik FFT Monitor Tasarımı

**Tarih:** 27 Temmuz 2026
**Durum:** Kullanıcı tarafından onaylandı
**Hedef donanım:** AXU4EVB-P + AD9364
**Temel alınan sürüm:** Kart üzerinde `PL_FFT: PASS` sonucu alınmış
`fft-single-shot-v1` Candidate

## 1. Amaç

Mevcut tek-atımlık FFT kabul testini değiştirmeden, kartı JTAG üzerinden yalnız
bir kez başlatan ve ardından 100 adet FFT frame'i 1000 ms aralıklarla alan ayrı
bir laboratuvar izleme modu oluşturulacaktır.

Bu mod gerçek sürekli streaming veya nihai monopulse tracking modu değildir.
Amaç; anten, RF kaynak ve kazanç/güç değişikliklerinin yaklaşık 100 saniyelik
bir deney boyunca kararlı ve okunabilir peak ölçümleriyle gözlenmesidir.

## 2. Değişmezler ve kapsam sınırı

- `PROJECT/tools/Start-Axu4evAd9364Candidate.cmd` ve
  `fft-single-shot-v1` paketi değiştirilmeyecektir.
- Golden PMUFW, FPGA bitstream, XSA ve `psu_init.tcl` değiştirilmeyecektir.
- FPGA her frame için yeniden programlanmayacaktır.
- AD9364 her frame için yeniden başlatılmayacaktır.
- 2048 spektrum kelimesi her frame'de CPU tarafından okunmaya devam edecek,
  ancak UART'a tam spektrum dökülmeyecektir.
- İlk sürümde frame sayısı ve bekleme süresi çalışma zamanında
  değiştirilmeyecektir: `100 frame`, `1000 ms`.
- Harici RF switch, phase shifter, S0-S3 durum çevrimi, AZ/EL oranı ve
  PetaLinux/IIO bu değişikliğin kapsamı dışındadır.
- Bu mod PL içi kesintisiz/ping-pong üretimin yerine geçmez. Sürekli tracking
  ayrı bir sonraki faz olarak kalır.

## 3. Seçilen yaklaşım

Yeni bir bare-metal uygulama modu ve ona ait ayrı Candidate paketi
oluşturulacaktır. Windows başlatıcısı kartı bir kez programlayacak; periyodik
capture döngüsü Cortex-A53 üzerinde çalışacaktır.

Bu yaklaşım şu alternatiflere tercih edilmiştir:

1. Mevcut CMD'yi Windows'tan 100 kez çalıştırmak, her turda PMUFW/FPGA/PS/DDR
   ve AD9364'ü yeniden başlatacağı için reddedildi.
2. PL içinde gerçek sürekli frame üretimine hemen geçmek, 1 Hz laboratuvar
   gözlemi için gereksiz RTL ve doğrulama kapsamı getirdiği için ertelendi.

## 4. Bileşenler

### 4.1 Mevcut tek-atımlık başlatıcı

`Start-Axu4evAd9364Candidate.cmd` mevcut tek-frame kabul testi olarak aynen
korunacaktır. Yeni modun build veya paketleme adımı bu dosyayı ya da
`fft-single-shot-v1` manifestini değiştiremez.

### 4.2 Yeni periyodik başlatıcı

Yeni kullanıcı giriş noktası:

`PROJECT/tools/Start-Axu4evAd9364PeriodicMonitor.cmd`

Bu dosya mevcut doğrulanmış PowerShell/XSCT başlatma zincirini kullanacak ve
Candidate kökü olarak aşağıdaki ayrı paketi seçecektir:

`PROJECT/candidates/axu4ev-ad9364/fft-periodic-monitor-v1`

### 4.3 Yeni Candidate paketi

Paket kendi `manifest.json`, README ve Release ELF dosyasını taşıyacaktır.
Manifest; ELF, bitstream, PMUFW, XSA ve `psu_init.tcl` hash'lerini birlikte
doğrulayacaktır. Donanım teslimlerinin hash'leri kartta kabul edilen
single-shot Candidate ile aynı olmak zorundadır; yalnız uygulama ELF'i farklı
olacaktır.

### 4.4 Bare-metal periyodik monitor

Uygulama `PL_FFT_PERIODIC_MONITOR` derleme modu ile üretilecektir. Ortak PL FFT
adres çözümleme ve MMIO adaptörleri single-shot moduyla paylaşılacak, fakat
single-shot ve periodic giriş işlevleri ayrı tutulacaktır.

Periyodik döngü küçük, bağımsız ve host testine uygun bir monitor birimi
olacaktır. Birim:

- frame sayısını ve aralık değerini alır,
- mevcut `pl_fft_capture_once()` sürücüsünü çağırır,
- başarılı sonucu raporlayıcıya iletir,
- son frame dışında gecikme işlevini çağırır,
- ilk gerçek hatada döngüyü keser.

Kart adaptörü gecikme için `no_os_mdelay()` ve raporlama için UART `printf`
kullanacaktır.

## 5. Çalışma ve veri akışı

1. Yeni CMD mevcut Candidate JTAG zincirini çağırır.
2. PMUFW yüklenir; doğrulanmış FPGA bitstream programlanır.
3. PS, DDR ve PS-PL sınırı başlatılır; DDR erişim kapısı geçilir.
4. Periodic-monitor ELF'i Cortex-A53 #0'a yüklenir ve çalıştırılır.
5. AD9364 yalnız bir kez başlatılır.
6. PL FFT sürücüsü yalnız bir kez doğrulanır ve hazırlanır.
7. `SEQ=1` için 2048-sample capture, FFT, peak ve spectrum snapshot işlemi
   tamamlanır.
8. Sonuç UART'a tek satırlık özet olarak basılır.
9. `SEQ < 100` ise başarılı capture tamamlandıktan sonra 1000 ms beklenir.
10. Adımlar 7-9 toplam 100 başarılı frame için tekrarlanır.
11. Yüzüncü başarılı frame'den sonra bekleme yapılmaz; genel PASS satırı
    basılır ve uygulama temizleme yoluna girer.

1000 ms değeri kesin bir gerçek-zamanlı frame başlangıç periyodu değildir.
Başarılı bir frame'in okunup raporlanmasından sonraki minimum bekleme
süresidir. Toplam deney süresi bu nedenle en az 99 saniye artı capture ve UART
işleme süreleridir.

## 6. UART çıktı sözleşmesi

Başlangıç satırı:

```text
PL_FFT_MONITOR: START frames=100 interval_ms=1000 bins=2048
```

Her başarılı frame için tek satır:

```text
PL_FFT_MONITOR: FRAME seq=001/100 frame=1 bank=0 samples=2048 peak_bin=88 peak_power=123456 dropped=0 crc=aaa532ad
```

Genel başarı:

```text
PL_FFT_MONITOR: PASS frames=100 interval_ms=1000
```

Hata:

```text
PL_FFT_MONITOR: FAIL seq=017 stage=CAPTURE error=-6
```

`frame` donanım frame kimliğidir; `seq` yazılım deney sayacıdır. `crc`, PL'nin
ürettiği frame CRC metadata'sıdır ve frame korelasyonu için raporlanır. Mevcut
atomik snapshot kontrolleri frame/tag değişimini ve geçersiz bank okumalarını
reddetmeye devam eder.

`dropped` tanı alanı olarak raporlanır. Shadow-path mimarisinde capture
penceresi dışındaki ADC örneklerinin akmaya devam etmesi nedeniyle tek başına
sıfırdan büyük `dropped` değeri genel hata sayılmaz. Sürücünün fatal status,
timeout, geçersiz/torn snapshot veya bank hataları ise gerçek capture hatasıdır.

## 7. Hata yönetimi

- AD9364 başlatılamazsa monitor döngüsü başlamaz.
- PL FFT sürücüsü hazır değilse `stage=INIT` ile genel FAIL üretilir.
- Herhangi bir capture çağrısı hata döndürürse o frame başarılı sayılmaz.
- İlk gerçek capture hatasında döngü hemen durur; sonraki frame'ler denenmez.
- 100'den az başarılı frame ile genel PASS üretilemez.
- Hata sonrasında single-shot veya Golden fallback'in otomatik çalıştırılması
  yoktur; operatör açıkça uygun başlatıcıyı seçer.
- Başlatma/paket hash doğrulaması başarısızsa ELF karta indirilmez.

## 8. Doğrulama planı

### 8.1 Host birim testleri

- Geçerli yapılandırmada tam 100 capture çağrısı yapılır.
- İlk 99 başarılı frame'den sonra tam 99 gecikme çağrısı yapılır.
- Yüzüncü frame'den sonra gecikme çağrılmaz.
- Raporlayıcı 100 başarılı ve sıralı sonuç alır.
- Seçilen herhangi bir sırada enjekte edilen capture hatası döngüyü hemen
  keser.
- Hata sonrasında capture, delay ve başarı raporu üretilmez.
- Sıfır frame veya sıfır aralık gibi geçersiz yapılandırmalar karta erişmeden
  reddedilir.

### 8.2 Build ve paketleme testleri

- Single-shot ve periodic derleme sembolleri aynı ELF'te birlikte
  etkinleştirilemez.
- Periodic Release ELF Debug çıktısına düşmeden üretilir.
- Yeni Candidate manifestindeki tüm hash ve provenance alanları doğrulanır.
- Yeni CMD dry-run'da yalnız periodic Candidate kökünü seçer.
- Mevcut single-shot launcher ve testleri değişmeden PASS verir.
- Golden ve periodic Candidate donanım teslimlerinin hash'leri birebir
  eşleşir.

### 8.3 Kart kabulü

PuTTY `115200-8-N-1` ile açıkken yeni CMD çalıştırılacaktır. Kabul için:

- AD9364 Rev 2 başarıyla başlatılmalıdır.
- Tam olarak 100 `PL_FFT_MONITOR: FRAME` satırı görülmelidir.
- `seq` değeri 1'den 100'e kesintisiz ilerlemelidir.
- Her frame'de `samples=2048` olmalıdır.
- Donanım `frame` kimlikleri ileri yönde ilerlemelidir.
- Arada hiçbir `PL_FFT_MONITOR: FAIL` bulunmamalıdır.
- Son satır `PL_FFT_MONITOR: PASS frames=100 interval_ms=1000` olmalıdır.
- PASS sonrasında yeni frame üretilmemelidir.

İlk fiziksel kabul kanıtı ayrı evidence dosyasına kaydedilecek; bu kanıt
oluşmadan yeni Candidate `CURRENT` veya Golden yapılmayacaktır.

## 9. Başarı ölçütü

Özellik; eski single-shot kabulü bozulmadan, yeni CMD ile kartın yalnız bir kez
başlatılması ve yaklaşık 100 saniyelik deneyde 100 geçerli 2048-bin FFT
snapshot'ının özetlenmesiyle tamamlanmış sayılır. Herhangi bir gerçek capture
hatası tüm koşuyu başarısız yapar.
