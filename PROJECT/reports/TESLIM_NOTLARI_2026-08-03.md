# AXU4EVB-P + AD9364 Proje Teslim Notları

Tarih: 3 Ağustos 2026

Teslim dalı: `codex/axu4ev-monopulse-lab-console`

## 1. Teslim kapsamı

Bu teslim; doğrulanmış Golden bring-up paketini, PL FFT/monopulse RTL ve
bare-metal kaynaklarını, UART tabanlı Python laboratuvar konsolunu, sürekli UDP
FFT geliştirmesini, otomatik testleri, teknik raporları ve sunumu içerir.

Raporlar iki ayrı amaçla düzenlenmiştir:

- `profen_staj_raporu.docx`: staj süreci, araştırma, planlama ve sonuçların
  genel/profesyonel anlatımı.
- `profen_teknik_detay_raporu.docx`: Vivado/Vitis, JTAG, PL FFT, protokoller,
  testler, arıza teşhisi ve devir prosedürlerini içeren 16 sayfalık teknik
  uygulama raporu.

Teslim paketi kaynak snapshotı ile birlikte tam Git geçmişini taşıyan bir
`git bundle` içerir. Yerel `.Xil`, `.pytest_cache`, Python sanal ortamı, geçici
Vitis/Vivado build klasörleri ve çalışma logları RAR'a alınmaz.

## 2. Kabul edilmiş sonuçlar

| Katman | Sonuç | Kanıt/konum |
|---|---|---|
| Kart bring-up | PASS | `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/` |
| AD9364 başlatma | PASS | UART'ta `AD936x Rev 2 successfully initialized` |
| PL FFT tek-frame | PASS | `fft-single-shot-v1` Candidate |
| PL FFT 100-frame | PASS | `fft-periodic-monitor-v1` Candidate |
| Monopulse foundation | PASS | `MONOPULSE_FOUNDATION: PASS` |
| UART live-lab | PASS | `monopulse-live-lab-v2` ve Python testleri |
| Ethernet yazılım/build | PASS | 38 host testi ve ayrı Vitis Release ELF build'i |
| Fiziksel Ethernet/UDP soak | AÇIK | USB-Ethernet adaptörü bekleniyor |
| Kablosuz CW Ethernet kabulü | AÇIK | Fiziksel ağ kapısından sonra yapılacak |
| ZX80/HMC936 S0–S3 kontrolü | GELECEK | Elektriksel sözleşme ve pin entegrasyonu gerekli |

## 3. Devralacak kişi için ilk gün sırası

1. Genel staj raporunu, teknik detay raporunu ve `project_situation_report.md`
   dosyasını okuyun.
2. Vivado/Vitis 2020.1, JTAG ve PS_UART bağlantısını doğrulayın.
3. Golden launcher ile temel kart/DDR/AD9364 regresyonunu çalıştırın.
4. Güncel live-lab Candidate ile UART FFT yolunu tekrar doğrulayın.
5. USB-Ethernet adaptörünü `192.168.1.100/24` yapın; gateway/DNS boş kalsın.
6. `Start-Axu4evAd9364EthernetDev.cmd` ile Ethernet ELF'ini başlatın.
7. UART READY ve `ping 192.168.1.10` sonrasında 150-frame kabulü çalıştırın.
8. En az 600 saniyelik UDP soak testini tamamlayın.
9. Yalnız ağ kabulü geçerse düşük seviyeli ve sınırlı SMW200A kablosuz CW testi yapın.
10. Tüm kanıtlar PASS ise yeni `monopulse-live-ethernet-v1` Candidate oluşturun.

## 4. Değiştirilmemesi gerekenler

- `PROJECT/releases/axu4ev-ad9364/2026-07-16-bringup-v1/`
- Mevcut `PROJECT/candidates/axu4ev-ad9364/*` paketleri
- Golden manifest, hash ve CURRENT işaretçisi
- Kartta doğrulanmış XSA/bitstream/PMUFW eşleşmeleri

Yeni geliştirme yeni branch, yeni Candidate adı ve ayrı kanıt/log klasörüyle
yürütülmelidir.

## 5. Bilinen sınırlar

- Fiziksel Ethernet kabul kanıtı henüz yoktur; yazılım/build PASS sonucu bunun yerine geçmez.
- Mutlak RF güç kalibrasyonu yapılmamıştır; FFT güçleri bağıl ölçümdür.
- ZX80 ve HMC936 kontrol pinleri mevcut live-lab Candidate tarafından sürülmez.
- PetaLinux ve pyadi-iio bu teslim kapsamında kullanılmamıştır.
- `Related-Docs/no-OS` gitlink'i bağımsız kaynak checkout'u sağlamaz; kullanılan
  sürücüler Vitis uygulama kaynaklarında vendored olarak bulunur.
- `Test-Axu4evHandoffArtifacts.ps1` ve bunun `Workspace` launcher kapısı, 14 ve
  20 Temmuz'dan kalan farklı Vivado/Vitis çalışma alanlarının birebir hash
  eşitliğini aradığı için güncel paralel Candidate tesliminde PASS değildir.
  Artefakt bütünlüğü `Test-Axu4evRelease.ps1`,
  `Test-Axu4evLabCandidatePackage.ps1` ve
  `Test-Axu4evPeriodicMonitorPackage.ps1` ile doğrulanır; günlük kullanımda
  immutable Golden/Candidate launcher'ları esas alınır.

## 6. Teslim arşivi doğrulama

RAR ile aynı klasördeki `.sha256` dosyasını kullanın:

```powershell
(Get-FileHash .\FPGA-Profen_AXU4EV_AD9364_Teslim_2026-08-03.rar -Algorithm SHA256).Hash
```

Çıktı, `.sha256` içindeki değerle aynı olmalıdır. RAR içindeki
`TESLIM_MANIFESTI.txt` kaynak branch/commit bilgisini; `SHA256SUMS.txt` ise paket
içindeki dosyaların hash'lerini verir.
