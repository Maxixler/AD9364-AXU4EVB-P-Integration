# 2026-07-16-bringup-v1

AXU4EVB-P + AD9364 için kartta doğrulanmış, değişmez Golden sürümdür. Kesin dosya boyutları ve SHA-256 değerleri `manifest.json` içindedir.

## Her açılışta çalıştırma

1. JTAG ve PS_UART bağlantılarını yapın; PuTTY'yi `115200-8-N-1` ile açın.
2. Önceki oturum `Instruction transfer timeout` ile bittiyse kartın gücünü kapatıp 10–15 saniye sonra yeniden açın.
3. `PROJECT\tools\Start-Axu4evAd9364Golden.cmd` dosyasına çift tıklayın.
4. PuTTY'de `AD936x Rev 2 successfully initialized` ve `Done.` satırlarını doğrulayın.
5. Yeni derlemeleri denemek için yalnızca `Start-Axu4evAd9364Workspace.cmd` kullanın.
6. Yeni çalışma alanı çıktısını ancak aynı UART/DMA kabul testi geçtikten sonra yeni bir sürüme terfi ettirin ve `CURRENT` olarak seçin.

Golden başlatıcı manifestteki tüm artefaktların boyutunu ve SHA-256 değerini programlamadan önce kontrol eder. PMUFW → FPGA → PS/DDR → PS–PL izolasyon/reset → DDR yaz/oku testi → uygulama sırasını otomatik uygular; eski FSBL'yi kullanmaz. Çalışma kaydı `PROJECT\logs\jtag` altında oluşur ve Git'e eklenmez.

## Yeni aday sürüm

Önce Workspace başlatıcısıyla kart testini tamamlayın. Başarılı aday için:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tools\Promote-Axu4evAd9364Release.ps1 -ReleaseId <yeni-surum> -BoardVerified
powershell.exe -NoProfile -ExecutionPolicy Bypass -File PROJECT\tools\Set-Axu4evAd9364CurrentRelease.ps1 -ReleaseId <yeni-surum>
```

Terfi işlemi mevcut bir sürümün üzerine yazmaz; `CURRENT` yalnızca ikinci, açık seçim komutuyla değişir. İleride PetaLinux çalışmasına geçildiğinde bu sürümdeki doğrulanmış `hardware/system_top.xsa` donanım başlangıç noktası olarak kullanılabilir; bare-metal Golden sürüm geriye dönüş referansı olarak korunur.
