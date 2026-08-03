# Staj Sunumu FFT Bölümü Sadeleştirme Tasarımı

## Amaç

FFT bölümünü teknik tasarım incelemesi ayrıntısından çıkarıp 30 dakikalık staj
sunumunda tek okumada anlaşılabilecek bir sonuç hikâyesine dönüştürmek.

## Değerlendirilen Yaklaşımlar

1. Mevcut altı FFT/Python slaydını koruyup yalnız metni kısaltmak: Teknik akış
   parçalı kalacağı için elendi.
2. Bölümü dört slayta indirmek: Mimari ve doğrulamayı ayırır ancak kart kabulü
   ile Python sonucu arasında tekrar üretir.
3. Bölümü üç slayta indirmek: Neden/nasıl, doğrulama ve kullanıcı çıktısı
   ekseninde en kısa tamamlanmış hikâyeyi verir. Bu yaklaşım seçildi.

## Onaylanan Ana Akış

### Slayt A - FPGA'da FFT neden ve nasıl yapıldı?

- AD9364'ten kompleks I/Q örnekleri alınır.
- FPGA içinde 2048 noktalı FFT uygulanır.
- Tam spektrum ve maksimum peak noktası çıkarılır.
- Görsel yalnız `AD9364 I/Q -> PL FFT -> Spektrum + Peak` akışını gösterir.

### Slayt B - FFT nasıl doğrulandı?

- Python/NumPy referans modeli ile FPGA sonucu karşılaştırıldı.
- Deterministik testlerde bit-doğru sonuç alındı.
- Kartta tek-frame `PL_FFT: PASS` ve 100-frame izleme testi geçti.
- Görsel, bir doğrulama özeti ile kısa UART PASS kanıtını birleştirir.

### Slayt C - Sonuç nasıl görüntülendi?

- Bare-metal uygulama spektrumu PS_UART üzerinden bilgisayara taşır.
- Python uygulaması spektrum ve waterfall grafiğini gösterir.
- CRC ve frame kontrolleri veri bütünlüğünü korur.
- Görsel, gerçek Python FFT/waterfall ekran görüntüsüdür.

## Ana Sunumdan Çıkarılacak Ayrıntılar

- CDC mailbox uygulama ayrıntıları
- Ping-pong bank sahipliği ve stale epoch
- `0x6AB` scaling schedule
- Q1.15/Q1.31 iç format ayrıntıları
- 33-bit magnitude-square genişliği
- CRC polinomu ve little-endian paketleme ayrıntıları
- DC-guard/`argmax` köşe durumu
- Abort, W1C, overflow ve soft-reset alt yolları

Bu maddeler yalnız teknik soru gelirse kullanılmak üzere yedek slaytlarda veya
raporda korunur.

## Korunacak Dürüstlük Sınırı

Sinyalsiz kart preflight sonucu RF performans kanıtı olarak sunulmayacak.
Kontrollü CW ile frekans/peak doğruluğu henüz sıradaki fiziksel kabul adımı
olarak açıkça belirtilecek.

## Başarı Ölçütleri

- Ana FFT anlatımı üç slaytı geçmez.
- Her slaytta en fazla dört kısa madde ve tek ana görsel bulunur.
- Ana akış iki-üç dakikada anlatılabilir.
- Dinleyici veri yolunu `AD9364 -> FPGA FFT -> UART -> Python` olarak tek
  bakışta anlayabilir.
- Teknik doğruluk korunurken uygulama içi register/format ayrıntıları ana
  anlatımı bölmez.
