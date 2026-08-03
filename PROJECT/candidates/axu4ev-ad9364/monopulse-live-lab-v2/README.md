# Monopulse Live Lab Candidate v2

Bu değişmez Candidate, AXU4EVB-P + AD9364 üzerindeki 2048-bin PL FFT
spektrumunu PS_UART üzerinden Python laboratuvar uygulamasına taşır.

V2 ile RX0 kazancı laboratuvar karşılaştırmalarını bozmayacak şekilde
`manual / 50 dB` olarak kilitlenmiştir. INFO ve SPECTRUM yanıtları gerçek
kazanç modu ile değerini taşır; firmware her frame öncesinde bu ayarların
değişmediğini doğrular. Fiziksel CW kabulü henüz yapılmadığı için manifest
doğru biçimde `board_verified=false` durumundadır.

## Bağlantılar

- AXU4EVB-P JTAG ve `PS_UART` bağlantılarını bilgisayara bağlayın.
- Kartı açın ve JTAG zincirinin görünür olmasını bekleyin.
- Bu Candidate `RX channel 0 / A_BALANCED` kullandığı için fiziksel RF girişi
  **RXA**'dır. Önceki Wi-Fi Candidate'ındaki RXB bağlantısını bu testte
  kullanmayın.
- İlk kablolu kabul yolu:
  `SMW200A RF OUT A -> onaylı 20-30 dB attenuator -> 50 ohm SMA -> RXA`.
- RXB, TXA ve TXB kullanılmaz; uygun 50 ohm terminasyonlar varsa kullanılmayan
  RF portlarına takılabilir. `REF_CLK` RF girişi değildir ve değiştirilmez.
- RF kaynağını yalnız laboratuvar sorumlusunun onayladığı güvenli seviye,
  kablolama ve harici zayıflatma ile hazırlayın.
- Bütün RF kablolamasını SMW200A RF çıkışı kapalıyken yapın. İlk kaynak
  seviyesini düşük tutun ve clipping görülmediğini doğrulamadan artırmayın.
- Python uygulamasından önce PuTTY'yi tamamen kapatın. COM portunu aynı anda
  yalnız bir uygulama açabilir.

## Candidate'ı başlatma

Worktree kökünde:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364LabConsole.cmd
```

Beklenen UART açılış satırı:

```text
PL_FFT_LAB: READY protocol=2 bins=2048 baud=115200 gain_mode=manual gain_db=50
```

Bu satır görülmüyorsa Python testine geçmeyin.

## Python ortamı ve 100-frame kayıt

İlk kullanımda:

```powershell
py -m venv .venv-lab
.\.venv-lab\Scripts\python.exe -m pip install -r PROJECT\lab_console\requirements.txt
```

Windows Aygıt Yöneticisi'ndeki gerçek PS_UART portunu `COMx` yerine yazın:

```powershell
.\.venv-lab\Scripts\python.exe -m PROJECT.lab_console.app `
  --port COMx --frames 100 --interval-ms 250 `
  --output-dir PROJECT\tests\evidence `
  --series-name axu4ev-ad9364-live-lab-cw-v2
```

Kayıtta her frame için protokol sürümü, 2048 FFT bin'i, CRC, frame/bank
bilgisi, RF telemetrisi, `gain_mode=manual` ve `gain_db=50` doğrulanır.
Frame'ler arasında kazanç değişirse seri kabul edilmez.

## Kontrollü CW kabulü

- SMW200A sinyalini DC bin'ine değil, bilinen bir frekans ofsetine yerleştirin.
- Varsayılan LO `2.400000 GHz`, sample rate `30.72 MSPS` ve FFT boyutu 2048
  olduğundan bin aralığı `15 kHz`'dir.
- Önerilen ilk kaynak `2.400300 GHz` ve beklenen natural-order peak
  `bin 20`'dir. Alternatif `2.401500 GHz` kaynağı `bin 100` üretir.
- AD9364 girişine yüksek güç uygulamayın; başlangıç seviyesi ve toplam harici
  zayıflatma laboratuvar sorumlusu tarafından onaylanmalıdır.
- 100 frame boyunca CRC hatası, fatal donanım bayrağı, eksik FFT verisi ve
  kazanç kayması olmamalıdır.
- Beklenen peak bin ile ölçülen peak bin farkı kabul toleransı içinde olmalıdır.
- Gösterilen güç, ayrıca kalibre edilene kadar bağıl FFT gücüdür; dBm olarak
  raporlanmamalıdır.

Kanıt üstverisinde aşağıdaki alanlar bulunmalıdır:

```text
Candidate release: monopulse-live-lab-v2
Application SHA-256: E05CA5EB83CC3E94BC05F55E52C1A076979FD2A66D8E19EBBE822DAF4FE7C01F
Bitstream SHA-256: ECDD9378FF9EBB3D0BD6BAD1C8C3FA6DD3E88C578087C51F219D78EAD13C6CCC
AD9364 gain mode: manual
AD9364 gain dB: 50
SMW200A frequency Hz: <tam sayı>
SMW200A level dBm: <değer>
External attenuation dB: <değer>
RF path: <kablo/attenuator/anten ve AD9364 portu>
AD9364 LO Hz: <tam sayı>
AD9364 sample rate Hz: <tam sayı>
AD9364 bandwidth Hz: <tam sayı>
Expected peak bin: <DC olmayan natural-order bin>
Peak tolerance bins: 1
NPZ SHA-256: <capture.npz SHA-256>
CSV SHA-256: <summary.csv SHA-256>
```

Kanıt doğrulayıcısı:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File PROJECT\tests\Test-Axu4evLabCaptureEvidence.ps1
```

ZX80-DR230-S+ ve EV1HMC936ALP6 kontrolü bu Candidate içinde etkin değildir.
Besleme, kontrol seviyeleri, level shifter, FPGA pinleri ve settle/discard
süreleri ölçülmeden bu donanımlara kontrol kodu uygulanmamalıdır.

Paket içeriği ve SHA-256 değerleri `manifest.json` dosyasındadır.
