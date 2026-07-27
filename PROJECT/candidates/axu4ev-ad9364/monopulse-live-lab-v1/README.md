# Monopulse Live Lab Candidate v1

Bu değişmez Candidate, AXU4EVB-P + AD9364 üzerinde üretilen 2048-bin PL FFT
spektrumunu PS_UART üzerinden Python laboratuvar ekranına taşır. Paket henüz
kontrollü CW ile fiziksel kabul edilmediği için `board_verified=false` olarak
işaretlidir.

## 1. Bağlantılar

- AXU4EVB-P JTAG bağlantısını bilgisayara bağlayın.
- Kartın `PS_UART` bağlantısını bilgisayara bağlayın.
- RF kaynağını, attenuator ve kablolamayı onaylanmış güvenli seviyelerde
  hazırlayın.
- Python uygulamasını başlatmadan önce PuTTY'yi kapatın. Aynı COM portunu aynı
  anda yalnız bir program açabilir.
- Kart kapalıysa açın ve JTAG zincirinin görünür olmasını bekleyin.

## 2. Python ortamı

PowerShell'i bu worktree kökünde açın:

```powershell
py -m venv .venv-lab
.\.venv-lab\Scripts\python.exe -m pip install -r PROJECT\lab_console\requirements.txt
```

## 3. Candidate'ı JTAG üzerinden başlatma

```powershell
.\PROJECT\tools\Start-Axu4evAd9364LabConsole.cmd
```

Başlatıcı PMUFW'yi yükler, doğrulanmış bitstream'i programlar, PS/DDR/PS-PL
başlatmasını yapar ve bu paketteki `ad9364app.elf` dosyasını çalıştırır.
Başarılı UART açılış işareti:

```text
PL_FFT_LAB: READY
```

Bu işareti kontrol etmek için PuTTY kullanılabilir; ancak Python uygulamasından
önce PuTTY tamamen kapatılmalıdır.

## 4. Canlı spektrum ve waterfall

Windows Aygıt Yöneticisi'nde PS_UART COM numarasını bulun ve `COMx` yerine
yazın:

```powershell
.\.venv-lab\Scripts\python.exe -m PROJECT.lab_console.app --port COMx
```

Uygulama önce `GET_INFO`, sonra tekrar eden `CAPTURE_ONCE` istekleri gönderir.
INFO yanıtında kart/RF kodları, firmware ve özellik bitleri, FFT boyutu,
spektrum sözcük boyutu, RF durum sayısı, sample rate, RX bandwidth, LO ve
`monopulse-live-lab-v1` release kimliği doğrulanır.

Ekranda 2048-bin spektrum, son 32 frame waterfall, peak bin/frekans/güç,
frame ID, RF state, aktif bank, CRC ve donanım sağlık bayrakları gösterilir.
`s` tuşu geçerli frame'i `PROJECT/lab-captures` altında NPZ ve CSV olarak
kaydeder.

Tek ölçüm alıp otomatik kaydetmek için:

```powershell
.\.venv-lab\Scripts\python.exe -m PROJECT.lab_console.app --port COMx --single
```

İsteğe bağlı temel ayarlar:

```powershell
.\.venv-lab\Scripts\python.exe -m PROJECT.lab_console.app `
  --port COMx --interval-ms 250 --history 32 `
  --search-start 0 --search-stop 2047 --dc-guard 0 --rf-state 0
```

## 5. Kabul ve güvenlik notları

- Uygulamanın gösterdiği güç, kalibrasyon tamamlanana kadar **kalibre edilmemiş
  bağıl güçtür**; dBm veya mutlak saha şiddeti olarak raporlanmamalıdır.
- İlk kabul, SMW200A ile DC dışındaki bilinen bir offsette kontrollü ve düşük
  seviyeli CW kullanır.
- En az 10 ardışık frame için CRC geçerli, FFT boyutu tam 2048, fatal donanım
  bayrağı sıfır ve peak bin kararlılığı beklenen değerin `±1` bin içinde
  olmalıdır.
- RF çıkışını doğrudan AD9364 girişine yüksek güçle bağlamayın. Anten/kablo
  kurulumu, attenuator ve jeneratör seviyesi laboratuvar sorumlusu tarafından
  onaylanmadan RF ON yapılmamalıdır.
- ZX80-DR230-S+ ve EV1HMC936ALP6 elektriksel sürüşü bu Candidate kapsamında
  henüz etkin değildir. Besleme, kontrol seviyeleri, level shifter, FPGA pinleri
  ve settle/discard süreleri ölçülmeden bu donanımlara kontrol kodu
  uygulanmamalıdır.

Paket içeriği ve SHA-256 değerleri `manifest.json` dosyasında kayıtlıdır.
