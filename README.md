# FPGA-Profen — AXU4EVB-P + AD9364 FFT ve Monopulse Platformu

Bu depo, AXU4EVB-P üzerinde AD9364/FMCOMMS uyumlu RF kartı kullanılarak
geliştirilen bare-metal FPGA FFT, monopulse ölçüm ve host görüntüleme
çalışmasının teslim deposudur.

## İlk okunacak belgeler

1. `PROJECT/reports/profen_staj_raporu.docx` — genel staj ve proje raporu.
2. `PROJECT/reports/profen_teknik_detay_raporu.docx` — yalnız teknik tasarım,
   uygulama, doğrulama ve devir adımları.
3. `PROJECT/reports/project_situation_report.md` — tamamlanan ve açık işler.
4. `PROJECT/reports/implementation_plan.md` — kronolojik uygulama planı.
5. `PROJECT/reports/axu4ev_ad9364_fft_rf_switch_nihai_plan.md` — nihai RF/FFT yol haritası.
6. `PROJECT/reports/TESLIM_NOTLARI_2026-08-03.md` — devir özeti ve teslim kontrol listesi.

Sunum dosyaları `PROJECT/reports/profen_staj_sunumu.pptx` ve
`PROJECT/reports/profen_staj_sunumu.pdf` altındadır.

## Ana klasörler

| Yol | İçerik |
|---|---|
| `Related-Docs/hdl-main/` | AXU4EV için kullanılan ADI HDL tabanı ve özel FFT IP kaynakları |
| `Vitis/workspace/` | Kartta doğrulanan bare-metal kaynak/BSP çalışma alanı |
| `PROJECT/releases/` | Değişmez Golden bring-up paketi |
| `PROJECT/candidates/` | Tek-frame, periyodik ve live-lab Candidate paketleri |
| `PROJECT/tools/` | Build, JTAG launcher, Ethernet ve paketleme araçları |
| `PROJECT/tests/` | C/Python/PowerShell doğrulama testleri |
| `PROJECT/lab_console/` | UART tabanlı Python FFT laboratuvar ekranı |
| `PROJECT/ethernet_fft/` | Sürekli UDP FFT alıcı ve görüntüleyici |
| `PROJECT/reports/` | Plan, durum, doğrulama, sunum ve nihai raporlar |

## Doğrulanmış çalışma yolları

Golden kart bring-up:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364Golden.cmd
```

Güncel UART live-lab Candidate:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364Candidate.cmd
```

Ethernet geliştirme Candidate'i:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364EthernetDev.cmd
```

Ethernet viewer:

```powershell
.\PROJECT\tools\Start-Axu4evAd9364EthernetViewer.cmd
```

Ethernet kart IP'si `192.168.1.10`, PC IP'si `192.168.1.100/24`, UDP portu
`5005`'tir. Fiziksel Ethernet kabulü için USB-Ethernet adaptörü gereklidir.

## Güncel teslim durumu

- Vivado/Vitis 2020.1 kart bring-up ve AD9364 Rev 2 başlatma doğrulandı.
- 2048 noktalı PL FFT tek-frame ve 100-frame periyodik akış kartta doğrulandı.
- UART/Python live-lab yolu, CRC ve 2048-bin frame sözleşmesi doğrulandı.
- Bare-metal sürekli UDP FFT yazılımı, ayrı Vitis Ethernet build'i ve host testleri tamamlandı.
- ZX80-DR230-S+ ve EV1HMC936ALP6 fiziksel S0–S3 kontrolü gelecekteki entegrasyondur.
- USB-Ethernet adaptörü bulunmadığı için fiziksel UDP soak ve kablosuz CW Ethernet kabulü açık bırakılmıştır.
- PetaLinux bu teslimin zorunlu parçası değildir.

## Araç sürümleri

- Xilinx Vivado/Vitis 2020.1
- PowerShell 5.1 veya üzeri
- Python 3 + NumPy/Matplotlib/PySerial/Pytest
- PuTTY veya eşdeğer terminal: `115200-8-N-1`
- JTAG ve PS_UART bağlantısı

## Temiz klon ve tarihçe

Teslim RAR'ında kaynak snapshotının yanında `GIT_GECMISI/FPGA-Profen.git.bundle`
bulunur. Tam tarihçe şu şekilde geri yüklenebilir:

```powershell
git clone .\GIT_GECMISI\FPGA-Profen.git.bundle FPGA-Profen
cd FPGA-Profen
git switch codex/axu4ev-monopulse-lab-console
```

`Related-Docs/no-OS` geçmişten kalan bir gitlink'tir ve bağımsız checkout bu
teslimde boş olabilir. Kullanılan AD9361/AD9364 sürücü kaynakları
`Vitis/workspace/ad9364app/src/` ve `vitis2/workspace/ad9364app/src/` içinde
teslim edilmiştir; yeniden üretim bu vendored kaynaklara dayanır.

## Güvenlik

RF testinde jeneratör çıkışını düşük seviyede başlatın, seviye limitini açık
tutun ve AD9364 RX maksimum güvenli giriş sınırını aşmayın. Golden veya mevcut
Candidate paketlerini yerinde değiştirmeyin; yeni çalışma için yeni Candidate
adı ve ayrı kanıt klasörü kullanın.
