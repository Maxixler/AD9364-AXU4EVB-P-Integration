# fft-single-shot-v1

AXU4EVB-P + AD9364 için PL FFT tek-atımlık okuma aday paketidir. Paket henüz
kart kabul testinden geçmediği için `manifest.json` içindeki `board_verified`
alanı `false` değerindedir ve Golden sürüm değildir.

## JTAG ile deneme

1. Kartın JTAG ve PS_UART bağlantılarını yapın; PuTTY'yi `115200-8-N-1`
   ayarıyla açın.
2. `PROJECT\tools\Start-Axu4evAd9364Candidate.cmd` dosyasını çalıştırın.
3. PuTTY'de AD9364 başlatma satırlarından sonra
   `PL_FFT: PASS frame=... bank=... peak_bin=... crc=...` sonucunu arayın.
4. Başarısızlıkta Golden başlatıcıyla doğrulanmış sisteme geri dönün; bu
   Candidate paketini `CURRENT` yapmayın.

Başlatıcı, uygulama ELF'i, bitstream, PMUFW, `psu_init.tcl` ve XSA dosyalarının
tamamını aynı manifestten doğrular. Candidate modunda Golden dosyalarıyla
karışık bir başlatma kabul edilmez.
