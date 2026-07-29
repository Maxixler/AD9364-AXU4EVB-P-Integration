# Tasarım İsterleri Teknik Değerlendirmesi

> [!IMPORTANT]
> **21 Temmuz 2026 teknik uzlaştırması — bu not aşağıdaki incelemede çelişen
> yorumların yerine geçer.** Üretici dokümanları ve güncel
> `codex/axu4ev-ad9364-monopulse` tasarımıyla yapılan yeniden kontrolde şu
> kararlar bağlayıcıdır:
>
> - `ZX80-DR230-S+` çalışma bandı **DC-3 GHz**'dir; rapordaki “DC-23 GHz”
>   ifadesi yanlıştır.
> - `HMC936A` 1.2-1.4 GHz, altı bit ve 0/+5 V pozitif kontrol mantığı
>   kullanır. Bir faz ağırlığı LOW yapıldığında seçilir. Altı kontrol hattı
>   için güvenli 5 V buffer/level-shifter ve tanımlı power-up/OE durumu
>   zorunludur.
> - HMC936A BDC sonrasındaki seçilebilir Delta IF yolundadır. Bu yüzden
>   AD9364 LO değeri koşulsuz “1.3 GHz” yapılmaz; gerçek BDC IF ölçülür,
>   1.2-1.4 GHz içinde olduğu kanıtlanır ve AD9364 LO bu IF merkezine göre
>   ayarlanır. 2.4 GHz foundation kaydı tarihsel kart smoke-test'idir,
>   monopulse RF zinciri kabulü değildir.
> - AD9364 tek RX zincirli 1x1 cihazdır. Ardışık S0-S3 frame'leri faz-koherent
>   iki kanal gibi kullanılamaz. İlk ürünün bağlayıcı monopulse sonucu
>   kompleks `Delta/Sigma` değil, güç tabanlı `(P_plus-P_minus) /
>   (P_plus+P_minus)` oranıdır.
> - `PEAK_RE` ve `PEAK_IM` tek-frame FFT doğrulaması, diagnostik ve ilerideki
>   açık koherens deneyi için saklanacaktır; ardışık frame'lerden ürün
>   seviyesinde kompleks Sigma/Delta rekonstrüksiyonu yapmak için
>   kullanılmayacaktır.
> - İlk uygulama tek-kare moduyla doğrulanır. Sürekli mod aynı register
>   sözleşmesinde desteklenir, ancak ping-pong spectrum buffer, overwrite
>   koruması ve throughput testi geçmeden etkinleştirilmez.
> - İlk RF elektriksel bring-up PS/manual kontrolle yapılabilir; nihai dört
>   durumlu ölçüm çevrimi state tagging ve deterministik settle/discard için
>   PL FSM tarafından yürütülür.
> - 2048 x 64-bit spectrum bankası 16 KiB'dir ve primitive yerleşimine bağlı
>   olarak en az dört BRAM36 eşdeğeri gerektirir; iki bankalı ping-pong için
>   yaklaşık sekiz BRAM36 bütçelenir. Kesin sayı sentez raporudur.
>
> CDC mailbox, `reset_epoch`, CRC-32 frame korelasyonu, doğal FFT sırası,
> `SCALE_SCH=0x6AB`, 33-bit magnitude-square, rectangular-first ve DMA'yı
> durdurmayan shadow path kararları korunur.

**Tarih:** 2026-07-21
**Konu:** 19 bölümlük monopulse sistem tasarım isterlerinin incelemesi
**Karşılaştırma temeli:** Nihai plan, monopulse design belgesi, implementation plan ve önceki audit raporu

---

# 1. Genel Değerlendirme

## 🟢 Olgunluk Kararı: Uygulanabilir ve iyi düşünülmüş

Bu tasarım isterleri, önceki üç belgenizdeki kararları **somut donanım parça numaralarıyla** birleştiren ilk belgedir. Artık soyut "SPDT switch" ve "phase shifter" yerine gerçek bileşenler var:

| Bileşen | Parça | Kritik Özellik |
|---------|-------|---------------|
| RF Switch | **ZX80-DR230-S+** (Mini-Circuits) | DC–23 GHz, SPDT, TTL kontrol |
| Phase Shifter | **HMC936A** (Analog Devices, EV1HMC936ALP6) | 6-bit, **1.2–1.4 GHz** ⚠️ |
| Signal Generator | R&S SMW200A | Lab-grade, CW + modülasyon |
| Transceiver | AD9364 | 1R1T, 70 MHz–6 GHz |

## En Kritik Yeni Bulgu

> [!CAUTION]
> **HMC936A frekans kısıtı tüm test planını etkiliyor.** Bu phase shifter yalnız 1.2–1.4 GHz bandında çalışır. Önceki tüm belgelerde hedef 2.4 GHz bandıydı. Bu, **LO frekansının ~1.3 GHz'e değişmesi** anlamına gelir. AD9364 ve ZX80 buna uyumludur, ama tüm RF parametreleri (anten, kablo, filtre, combiner) bu banda göre yeniden değerlendirilmeli.

---

# 2. Kritik Yeni Karar: HMC936A ve Frekans Kısıtı

## 2.1 HMC936A Özellikleri (Datasheet'ten)

| Parametre | Değer |
|-----------|-------|
| Frekans aralığı | **1.2–1.4 GHz** |
| Phase kontrol | 6-bit (64 kod) |
| LSB çözünürlüğü | 5.625° (nominal) |
| Insertion loss | ~5 dB tipik |
| Kontrol arayüzü | Paralel 6-bit, aktif-low (?), 0/5V veya 0/3.3V ⚠️ |
| Evaluation board | EV1HMC936ALP6 |

## 2.2 Frekans Etkisi

| Önceki Plan | Yeni İster |
|-------------|-----------|
| LO = 2400 MHz (2.4 GHz Wi-Fi bandı) | LO ≈ 1300 MHz (L-band) |
| AD9364 `rx_synthesizer_frequency_hz = 2400000000UL` | **Değiştirilmeli: `1300000000UL`** |
| Anten: 2.4 GHz monopulse | Anten: **L-band monopulse gerekli** |
| Kablolar/combiner: 2.4 GHz | Kablolar/combiner: L-band uyumlu |

**Bu bir sorun mu?** Hayır — AD9364 70 MHz–6 GHz destekler. ZX80-DR230-S+ DC–23 GHz destekler. Tek kısıt HMC936A'dır ve ister bunu doğru tespit etmiş.

## 2.3 Phase Shifter Kontrol Arayüzü — Kritik Belirsizlik

İsterler bunu doğru tanımlamış (Bölüm 4):

> "HMC936A değerlendirme kartının kontrol girişleri aktif-low 0/5V mantığı kullanabileceği için 3.3V FPGA GPIO ile doğrudan bağlantı risklidir."

**Önerim:** HMC936A datasheet'inde kontrol bitlerinin eşik voltajları kesin belirtilmeli. Evaluation board üzerinde pull-up/pull-down resistor'ler olabilir. Level shifter zorunluluğu bu bilgiye bağlı.

---

# 3. Bölüm Bölüm Teknik Yorum

## Bölüm 1 — RF Sinyal Kaynağı ✅

**Yorum:** Mükemmel. CW taşıyıcının DC'den birkaç bin uzakta tutulması doğru. 30.72 MSPS'de DC guard = ±3 bin ≈ ±45 kHz yeterli.

**Ek not:** CW frekansı seçimi için pratik formül:
$$f_{CW} = f_{LO} + k_{target} \cdot \Delta f_{bin}$$
$$\Delta f_{bin} = \frac{f_s}{N} = \frac{30.72 \times 10^6}{2048} = 15 \text{ kHz}$$

Örneğin DC'den 10 bin uzakta: $f_{CW} = f_{LO} + 150 \text{ kHz}$

## Bölüm 2 — Anten Düzeni ✅

**Yorum:** Doğru tanımlanmış. Phase shifter'ın mekanik açı değil RF fazı değiştirdiği notu önemli.

**Dikkat:** L-band (1.3 GHz) monopulse anten boyutu 2.4 GHz'e göre ~1.85x daha büyük ($\lambda \propto 1/f$). Yankısız oda ve anten mevcudiyeti doğrulanmalı.

## Bölüm 3 — Dış RF Durumları ✅

**Yorum:** Dört durumlu yapı önceki monopulse design belgesiyle **tam tutarlı**. Settle → discard → capture sırası doğru.

**Önemli fark:** Önceki belgede "Σ ve Δ combiner'da toplanıyor" şeklindeydi. Burada şema daha net:

```
ΔAZ veya ΔEL → ZX80 switch → HMC936A (0°/180°) → combiner ← Σ → AD9364
```

Bu, combiner çıkışının zaten $\Sigma \pm \Delta$ olduğunu doğrular.

## Bölüm 4 — Elektriksel Kontrol Arayüzü ✅ (Dikkat gerekli)

**Yorum:** Level shifter zorunluluğu doğru tespit edilmiş.

**Kritik detay — HMC936A 6-bit kontrol:**

| Bit | Faz Ağırlığı (nominal) |
|-----|----------------------|
| B0 (LSB) | 5.625° |
| B1 | 11.25° |
| B2 | 22.5° |
| B3 | 45° |
| B4 | 90° |
| B5 (MSB) | 180° |

İsterde belirtilen 0°/180° tersleme = B5 toggle. Kalan 5 bit kalibrasyon fine-tuning için.

**GPIO Sayısı:**
- ZX80-DR230-S+: 2 kontrol pini (Cont1, Cont2) → AZ/EL seçimi
- HMC936A: 6 kontrol biti
- **Toplam: 8 GPIO hattı** + level shifter

**PS vs PL kararı:** İster, ilk sürümde PS kontrolünü öneriyor — bu doğru. 4 durumluk çevrimde her durum ~67 µs capture + FFT süresi + settling süresi içerir. PS software loop latency'si (µs mertebesinde) toplam çevrim süresine göre ihmal edilebilir.

## Bölüm 5 — AD9364 Yapılandırması ✅

**Yorum:** Önceki belgelerle tutarlı. Yeni önemli değişiklik:

| Parametre | Önceki | Yeni |
|-----------|--------|------|
| LO | 2400 MHz | **~1300 MHz** |
| BW | 18 MHz (nihai plan) / 10 MHz (monopulse) | **10 MHz** → netleşti |
| Gain | MGC | MGC ✅ |
| RX port | RXB | **Fiziksel bağlantıya göre belirlenecek** |

> [!IMPORTANT]
> **RF bandwidth artık 10 MHz olarak netleşti.** Nihai plandaki 18 MHz değeri artık geçersiz. AD9364 API çağrısı: `ad9361_set_rx_rf_bandwidth(phy, 10000000)`.

## Bölüm 6 — RX Veri Yolu Dallandırması ✅

**Yorum:** Önceki tüm belgelerle tam tutarlı. Shadow path yaklaşımı doğru.

## Bölüm 7 — FFT Kare Oluşturucu ✅

**Yorum:** Nihai plandaki `adc_stream_bridge` sözleşmesiyle uyumlu.

**Yeni önemli özellik — Sürekli mod:**

İster, sürekli (continuous) modu da tanımlıyor. Nihai plan bu modu "sonraki faz" olarak ertelemişti. İsterin yaklaşımı daha pragmatik: ilk sürümde tek-kare, ama mimariyi sürekli moda hazır tut.

**Tavsiye:** İlk Candidate'da yalnız tek-kare modu implement et, ama AXI-Lite register'da `continuous` bitini ayır. Sürekli mod, ping-pong buffer olmadan güvenilir çalışmaz.

## Bölüm 8 — Pencereleme ✅

**Yorum:** Rectangular-first yaklaşımı nihai planla tam tutarlı. Hann desteği için mimari giriş noktası bırakılması doğru.

## Bölüm 9 — 2048 FFT ✅

**Yorum:** Nihai plandaki `SCALE_SCH=0x6AB`, 24-bit phase factor, convergent rounding sözleşmesiyle uyumlu. İster bunu tekrar etmiyor ama çelişmiyor.

## Bölüm 10 — Güç Spektrumu ✅

**Yorum:** $P[k] = \text{Re}^2 + \text{Im}^2$ — doğru. Log dönüşümün PS'de yapılması doğru karar.

## Bölüm 11 — 2048-bin Spektrum Belleği ✅ (Yeni detay)

**Yorum:** Ping-pong/double-buffer yaklaşımı ilk kez burada detaylandırılmış.

**Kaynak etkisi:**
- 2048 bin × 64-bit/bin = 16 KiB per bank
- Ping-pong: 2 × 16 KiB = 32 KiB = ~2 BRAM36
- Monopulse 4 durum: 4 × 16 KiB = 64 KiB = ~4 BRAM36 (ek spectrum buffer)
- **Toplam BRAM etkisi:** ~6 BRAM36 sadece spectrum storage için. XCZU4EV'de 128 BRAM36 → %5

## Bölüm 12 — Peak Detector ✅✅ (Kritik yeni gereksinim)

**Bu bölüm önceki belgelerde eksikti ve çok önemli.**

> [!IMPORTANT]
> **Kompleks peak değeri saklanmalı.** Önceki belgeler yalnız magnitude-square peak tutuyordu. İster, `PEAK_RE` ve `PEAK_IM` gereksinimini ekliyor. Bu, monopulse Σ/Δ hesabı için **zorunlu**.

**Neden zorunlu?** Çünkü:

$$\hat{\Sigma}_{AZ} = \frac{Y_{AZ+} + Y_{AZ-}}{2}$$

Bu formüldeki $Y$ değerleri **kompleks FFT çıkışlarıdır**, magnitude değil. Yalnız güç saklanırsa faz bilgisi kaybolur ve toplama/çıkarma anlamını yitirir.

**PL implementasyonu:**
- FFT çıkışı zaten kompleks (Re + Im)
- Peak search sırasında magnitude-square hesapla (karşılaştırma için)
- Ama peak bin'in **hem Re hem Im değerini** ayrı register'lara yaz
- Kaynak etkisi: 2 ek 32-bit register → ihmal edilebilir

**Bu, nihai planın güncellenmesi gereken bir noktasıdır.** Mevcut plan yalnız 33-bit magnitude-square saklıyor.

## Bölüm 13 — AXI-Lite Register'ları ✅

**Yorum:** Nihai planla büyük ölçüde uyumlu. Bazı farklar:

| Register | Nihai Plan | Yeni İster | Yorum |
|----------|-----------|-----------|-------|
| `PEAK_RE` / `PEAK_IM` | ❌ Yok | ✅ Var | **Eklenmeli** |
| `PEAK_PHASE` | ❌ Yok | PS'de `atan2` | Doğru — PL'de CORDIC gereksiz |
| CDC register'ları | ✅ Detaylı | ❌ Bahsedilmemiş | Nihai plandaki CDC sözleşmesi korunmalı |
| `reset_epoch` | ✅ Var | ❌ Yok | Nihai plandaki epoch mekanizması eklenmeli |
| `frame_error` | ✅ Var | `stream_error` olarak | Aynı kavram |

**Tavsiye:** Nihai plandaki CDC register'ları (`cdc_ready`, `cdc_fault`, `reset_epoch`, `aborted`) bu ister listesine de eklenmeli. Yoksa iki belge arasında register adresleri çakışabilir.

## Bölüm 14 — PS Yazılım Akışı ✅

**Yorum:** Doğru ve nihai planla tutarlı. Önemli doğru karar: PS, her RF durumu arasında switch kontrolü yapıyor, PL'de FSM değil.

**Basitleştirme avantajı:** İlk sürümde PL yalnız "tek frame al" görevi yapar. Dört durumlu çevrim tamamen PS software'de:

```c
for (int state = 0; state < 4; state++) {
    set_rf_switch(state);      // GPIO
    set_phase_shifter(state);  // GPIO
    usleep(settling_us);       // Bekle
    pl_start_capture();        // AXI-Lite write
    pl_wait_done();            // AXI-Lite poll
    read_peak(state);          // AXI-Lite read
    read_spectrum(state);      // BRAM read
}
compute_monopulse();           // PS hesaplama
```

Bu, PL karmaşıklığını dramatik olarak azaltır. PL FSM yalnız ilerde deterministik zamanlama gerekirse eklenir.

## Bölüm 15 — Kompleks RF Kalibrasyonu ✅✅ (Çok önemli)

**Yorum:** Bu bölüm, önceki belgelerde yüzeysel olan kalibrasyon konusunu somutlaştırıyor.

$Y_{corr,s} = C_s \cdot Y_{meas,s}$ — burada $C_s$ kompleks katsayıdır:

$$C_s = A_s \cdot e^{j\phi_s}$$

- $A_s$: Genlik düzeltme (insertion loss farkları)
- $\phi_s$: Faz düzeltme (kablo/switch/combiner faz farkları)

**Kalibrasyon prosedürü:**
1. SMW200A'dan sabit CW → bilinen referans sinyal
2. Her durum (S0–S3) için FFT peak'in kompleks değerini ölç
3. İdeal durumda 0° ve 180° faz farkı beklenir
4. Gerçek ölçümden sapma → $C_s$ katsayısı

**HMC936A 64-kod karakterizasyonu:**
Her faz kodu (0–63) için gerçek faz ve genlik ölçümü — bu **çok değerli** bir kalibrasyon tablosu oluşturur. 5.625° nominal adımlara güvenmemek doğru.

## Bölüm 16 — Σ ve Δ Yeniden Oluşturma ✅✅

**Matematik doğrulaması:**

Analog combiner çıkışları:
$$Y_{AZ+} = \Sigma + \Delta_{AZ} \quad (\text{0° durumu})$$
$$Y_{AZ-} = \Sigma - \Delta_{AZ} \quad (\text{180° durumu})$$

Toplama ve çıkarma:
$$\hat{\Sigma}_{AZ} = \frac{Y_{AZ+} + Y_{AZ-}}{2} = \Sigma$$
$$\hat{\Delta}_{AZ} = \frac{Y_{AZ+} - Y_{AZ-}}{2} = \Delta_{AZ}$$

✅ **Matematiksel olarak doğru.** Bu, klasik amplitude-comparison monopulse tekniğinin zaman-bölüşümlü versiyonudur.

**Kritik varsayım:** Bu formüller, Σ sinyalinin iki ölçüm arasında **değişmediğini** varsayar. Hareketli hedef veya kararsız kaynak durumunda bu varsayım bozulur. CW kaynağıyla (SMW200A) lab ortamında bu sorun yoktur.

> [!WARNING]
> **Önceki belgelerle önemli fark:** Nihai plan ve monopulse design belgesi, yalnız **güç** üzerinden oran hesaplıyordu:
> $$AZ\_ERROR = \frac{P_{AZ+} - P_{AZ-}}{P_{AZ+} + P_{AZ-}}$$
>
> Bu ister ise **kompleks** oran hesaplıyor:
> $$E_{AZ} = \frac{\hat{\Delta}_{AZ}}{\hat{\Sigma}_{AZ}} = \frac{Y_{AZ+} - Y_{AZ-}}{Y_{AZ+} + Y_{AZ-}}$$
>
> **İkisi eşdeğer DEĞİLDİR.** Kompleks oran hem genlik hem faz bilgisi taşır. Güç oranı yalnız genlik (ve işaret) bilgisi taşır. Kompleks oran daha zengin — faz bilgisinden yön belirlenebilir.
>
> **Bu bir çelişki değil, bir yükseltmedir.** Ama PL'de peak'in `Re` ve `Im` değerlerinin saklanması artık zorunludur. Nihai planın güncellenmesi gerekir.

## Bölüm 17 — Açı Hesabı ✅

**Yorum:** Doğru yaklaşım. Açı $= f(E)$ ilişkisi anten pattern'ine bağlıdır ve ölçülmelidir. LUT veya curve fitting — standard monopulse prosedürü.

**Pratik not:** İlk ürünün kalibre edilmemiş $\Delta/\Sigma$ error çıktısı vermesi makul. Bu "açı" değildir ama monopulse yanıtının doğruluğunu kanıtlar.

## Bölüm 18 — Python Doğrulama ✅

**Yorum:** `pyadi-iio`'nun bare-metal'de kullanılamayacağı doğru. UART/CSV yaklaşımı ilk aşama için uygun.

**Önemli not:** Python FFT modelinin **aynı scaling schedule** (`0x6AB`) ve **aynı fixed-point aritmetiği** kullanması zorunlu. `numpy.fft` floating-point kullanır — bu, bit-true karşılaştırma için yeterli değildir. Nihai planın Python modeli `round-to-nearest-even` ve 16-bit saturasyonu uygulamalıdır.

## Bölüm 19 — Doğrulama Sırası ✅

**Yorum:** 15 adımlık sıralama mantıksal ve tutarlı. İlk paketin 1–6 olması (PL FFT shadow path) doğru karar.

---

# 4. Önceki Belgelerle Delta Analizi

## Yeni Kararlar

| # | Yeni Karar | Etkisi |
|---|-----------|--------|
| 1 | **HMC936A → LO ≈ 1.3 GHz** | Tüm RF parametreleri değişir |
| 2 | **Kompleks peak (`PEAK_RE/IM`)** | PL register güncellemesi gerekli |
| 3 | **Kompleks Σ/Δ hesabı** (güç yerine) | PS yazılımda kompleks aritmetik |
| 4 | **PS kontrollü RF switch** (PL FSM yerine) | PL basitleşiyor, PS karmaşıklaşıyor |
| 5 | **HMC936A 6-bit paralel kontrol** | 8 GPIO + level shifter gerekli |
| 6 | **64-kod faz karakterizasyonu** | Kalibrasyon süresi artıyor ama doğruluk artıyor |
| 7 | **Sürekli mod tanımı** | Ping-pong buffer gereksinimi netleşti |
| 8 | **BW = 10 MHz kesinleşti** | Nihai plandaki 18 MHz artık geçersiz |

## Tutarlılık Kontrolü

| Kontrol | Nihai Plan | Bu İster | Uyumlu? |
|---------|-----------|----------|:-------:|
| FFT = 2048, fixed-point | ✅ | ✅ | ✅ |
| Rectangular-first | ✅ | ✅ | ✅ |
| Store-and-forward | ✅ | ✅ (implicit) | ✅ |
| Shadow DMA path | ✅ | ✅ | ✅ |
| MGC gain | ✅ | ✅ | ✅ |
| TX kapalı | ✅ | ✅ | ✅ |
| CDC mailbox | ✅ | ❌ bahsedilmemiş | ⚠️ |
| CRC-32 frame korelasyonu | ✅ | ❌ bahsedilmemiş | ⚠️ |
| `SCALE_SCH=0x6AB` | ✅ | ❌ bahsedilmemiş | ⚠️ |
| 33-bit magnitude-square | ✅ | ❌ bahsedilmemiş | ⚠️ |
| Güç oranı vs Kompleks oran | Güç oranı | **Kompleks oran** | 🔄 Yükseltme |
| Peak: sadece power | ✅ | **Re + Im** | 🔄 Yükseltme |
| LO = 2.4 GHz | ✅ | **1.3 GHz** | 🔄 Değişiklik |
| BW = 18 MHz | ✅ | **10 MHz** | 🔄 Değişiklik |

> [!NOTE]
> ⚠️ işaretli maddeler "eksik" değil, "bu belgede tekrar edilmemiş" anlamında. Nihai plandaki detaylar (CDC, CRC, scaling) hâlâ geçerli ve uygulanacak.

---

# 5. Yeni Riskler ve Dikkat Noktaları

## 🟠 Risk 1: HMC936A Level Shifter Gereksinimi

**Sorun:** HMC936A evaluation board kontrol girişleri 0/5V TTL olabilir. AXU4EVB-P GPIO'ları 3.3V (LVCMOS33) veya 1.8V (LVCMOS18).

**Etki:** Level shifter tasarımı ve PCB/breakout gerekebilir.

**Çözüm:**
1. HMC936A EV board şemasını incele → gerçek logic level eşiklerini bul
2. 3.3V ile çalışabilirliği kontrol et (çoğu TTL 2.0V threshold kullanır → 3.3V yeterli olabilir)
3. Gerekirse TXS0108E veya SN74LVC8T245 gibi bi-directional level shifter kullan

## 🟠 Risk 2: 8 GPIO Hattı Kaynağı

**Sorun:** ZX80 (2 hat) + HMC936A (6 hat) = 8 GPIO gerekli. Bu hatlar nereye bağlanacak?

**Seçenekler:**

| Kaynak | Pin Sayısı | Avantaj | Dezavantaj |
|--------|:----------:|---------|------------|
| PS MIO | 26 adet boş (MIO 26-51) | Software kontrolü kolay | PL FSM'e taşımak zor |
| PS EMIO | 96 adet | PL üzerinden PS'e bağlı | Routing karmaşıklığı |
| PL GPIO (AXI GPIO) | Konfigüre edilebilir | PL FSM'e geçiş kolay | AXI bus bağlantısı gerekli |
| J23 CAM_GPIO (3.3V) | ~4 pin | Doğrudan erişilebilir | Sayı yetersiz olabilir |

**Tavsiye:** İlk aşamada **PS MIO** veya **AXI GPIO IP** kullanılması en kolay. PL FSM'e geçiş gerekirse AXI GPIO output'larını PL internal sinyal olarak yönlendirmek mümkün.

## 🟡 Risk 3: Kompleks Oran Doğruluğu ve Faz Koherensı

**Sorun:** Dört durum ardışık ölçülüyor. Σ sinyali iki ölçüm arasında faz/genlikte değişebilir.

**Lab ortamında (CW + SMW200A):** Kaynak çok kararlı → risk düşük.

**Sahada:** Hareketli hedef → Σ değişebilir → kompleks oran hatalı olabilir.

**Çözüm:** Lab kalibrasyonunda sorun yok. Saha kullanımı için frame süresi + settling süresi toplamının hedef hareketi boyunca Σ değişimini ihmal edilebilir kılması gerekir. Toplam çevrim süresi:

$$T_{cycle} = 4 \times (T_{settle} + T_{discard} + T_{capture} + T_{FFT})$$

30.72 MSPS'de: $T_{capture} = \frac{2048}{30.72 \times 10^6} \approx 67 \text{ µs}$

$T_{settle} \approx 50 \text{ µs}$ (tahmini), $T_{FFT} \approx 20 \text{ µs}$ (2048-pt pipelined)

$$T_{cycle} \approx 4 \times (50 + 10 + 67 + 20) \approx 588 \text{ µs} \approx 0.6 \text{ ms}$$

Bu, düşük hızlı tracking için yeterlidir.

## 🟡 Risk 4: Combiner ve Kablo Faz Kararlılığı

Faz kalibrasyonu sıcaklık ve mekanik titreşime duyarlıdır. L-band'da $\lambda = 23 \text{ cm}$. 1° faz hatası ≈ 0.64 mm kablo boyu değişimi. Bu, lab ortamında genellikle sorun değildir.

---

# 6. Matematik Doğrulaması

## 6.1 Combiner Çıkışı

Phase shifter $\phi = 0°$ durumunda:
$$Y_{+} = \Sigma + \Delta \cdot e^{j \cdot 0} = \Sigma + \Delta$$

Phase shifter $\phi = 180°$ durumunda:
$$Y_{-} = \Sigma + \Delta \cdot e^{j\pi} = \Sigma - \Delta$$

✅ **Doğru.** Combiner toplayıcı (power combiner) ise çıkış $\Sigma + \Delta \cdot e^{j\phi}$ olur.

## 6.2 Σ ve Δ Yeniden Oluşturma

$$\hat{\Sigma} = \frac{Y_{+} + Y_{-}}{2} = \frac{(\Sigma + \Delta) + (\Sigma - \Delta)}{2} = \Sigma \quad ✅$$

$$\hat{\Delta} = \frac{Y_{+} - Y_{-}}{2} = \frac{(\Sigma + \Delta) - (\Sigma - \Delta)}{2} = \Delta \quad ✅$$

## 6.3 Normalize Hata

$$E = \frac{\hat{\Delta}}{\hat{\Sigma}} = \frac{\Delta}{\Sigma}$$

Bu, klasik monopulse hata sinyalidir. $\text{Re}(E)$ yön bilgisini taşır:
- $\text{Re}(E) > 0$: Hedef boresight'ın bir tarafında
- $\text{Re}(E) < 0$: Hedef boresight'ın diğer tarafında
- $|E|$: Açısal sapma büyüklüğü
- $\text{Im}(E)$: Cross-coupling veya kalibrasyon hatası (ideal durumda sıfıra yakın)

✅ **Tüm matematik doğru ve fiziksel olarak anlamlı.**

## 6.4 Önceki Güç Oranıyla İlişki

Monopulse design belgesindeki güç oranı:

$$\frac{P_{+} - P_{-}}{P_{+} + P_{-}} = \frac{|Y_{+}|^2 - |Y_{-}|^2}{|Y_{+}|^2 + |Y_{-}|^2} = \frac{4 \cdot \text{Re}\{\Sigma \cdot \Delta^*\}}{2(|\Sigma|^2 + |\Delta|^2)}$$

Bu, $\Delta/\Sigma$ kompleks oranının **yalnız Re kısmıyla ilgili** basitleştirilmiş bir versiyondur. Kompleks oran daha genel ve doğrudur.

**Sonuç:** Yeni ister, önceki güç oranını **daha genel ve doğru bir formülle** değiştiriyor. Bu bir ilerleme.

---

# 7. Uygulama Öncelik Sırası Değerlendirmesi

İsterin önerdiği 1–6 ilk paket sırası ile nihai planın M0–M3 paketleri uyumlu. Tablo:

| İster Adımı | Nihai Plan Karşılığı | Yorum |
|:-----------:|:-------------------:|-------|
| 1. Python/C FFT modeli | M3 (kısmen) | Nihai plan daha erken bekliyordu |
| 2. PL FFT IP + frame | M2 + M3 | Uyumlu |
| 3. Sim CW testi | M3 | Uyumlu |
| 4. Bit-true karşılaştırma | M3 | Uyumlu |
| 5. Tek-kare kart testi | M3 (kart kabulü) | Uyumlu |
| 6. Sürekli mod | M8 (performans fazı) | İster daha erken istiyor ⚠️ |
| 7. DMA regresyon | M1 | Uyumlu |
| 8. RF switch GPIO | M5 | Uyumlu |
| 9. HMC936 karakterizasyon | M5 + M7 | Uyumlu |
| 10–13. Monopulse | M6 + M7 | Uyumlu |
| 14. Yankısız oda | M7 | Uyumlu |
| 15. PetaLinux | Opsiyonel | Uyumlu |

> [!TIP]
> **Tavsiye:** Sürekli modu (adım 6) ilk Candidate'dan çıkarıp adım 10'dan sonraya ertelemek daha güvenli. Tek-kare mod monopulse için yeterli; sürekli mod tracking için gerekli ama daha sonra eklenebilir.

---

# 8. Sonuç ve Öneriler

## Genel Karar: 🟢 Uygulanabilir

Bu ister belgesi, **proje tarihindeki en somut ve donanım-bağlantılı tasarım dokümanıdır.** Gerçek parça numaraları, frekans kısıtları ve kontrol arayüzleri tanımlanmış.

## Hemen Yapılması Gerekenler

1. **HMC936A EV board şeması ve datasheet'ini incele** → kontrol voltaj seviyeleri, aktif-low/high, pull resistor'ler
2. **ZX80-DR230-S+ datasheet'ini incele** → Cont1/Cont2 doğruluk tablosu, switching time
3. **L-band monopulse anten mevcudiyetini doğrula** → 1.3 GHz'de çalışacak anten var mı?
4. **Nihai planı güncelle:**
   - `PEAK_RE` / `PEAK_IM` register'ları ekle
   - LO = 1.3 GHz olarak güncelle
   - BW = 10 MHz olarak güncelle
   - Kompleks Σ/Δ hesabı ekle (güç oranına ek olarak)

## Nihai Planla Birleştirme İçin Minimum Güncellemeler

| Dosya | Güncelleme |
|-------|-----------|
| `nihai_plan.md` Bölüm 8 | LO ve BW değerlerini 1.3 GHz / 10 MHz olarak güncelle |
| `nihai_plan.md` Bölüm 10 | `PEAK_RE`, `PEAK_IM` register'larını ekle |
| `nihai_plan.md` Bölüm 12 | Kompleks Σ/Δ hesabını güç oranına alternatif olarak ekle |
| `monopulse_design.md` Bölüm 5 | LO = 1.3 GHz olarak güncelle |
| `monopulse_design.md` Bölüm 8 | Kompleks aritmetik seçeneğini ekle |
| `monopulse_design.md` Bölüm 10 | `PEAK_RE` / `PEAK_IM` register'larını ekle |

## Güçlü Yönler

- ✅ Gerçek donanım parçaları ile somutlaştırılmış mimari
- ✅ HMC936A frekans kısıtının erken tespit edilmesi
- ✅ PS kontrolü ile başlayıp PL FSM'e geçiş opsiyonu
- ✅ Kompleks FFT peak saklanması → zengin kalibrasyon
- ✅ 64-kod faz karakterizasyonu → gerçekçi kalibrasyon
- ✅ Matematiksel tutarlılık: $\Sigma/\Delta$ formülleri doğru
- ✅ DMA shadow path korunması
- ✅ İnkremental doğrulama sırası (1→15)

## 28 Temmuz 2026 Uygulama Sonrası Uzlaştırma Notu

Bu bölüm ilk incelemenin tarihsel bulgularını silmez; daha sonra uygulanan
kararların güncel durumunu kaydeder.

| İnceleme konusu | Güncel karar / durum |
|---|---|
| Tek girişli PL FFT | 2048 nokta, natural order, tam spectrum ve peak olarak uygulandı |
| Bit-doğru model | NumPy oracle ve gerçek Vivado FFT v9.1 ile altı vektörde sıfır LSB fark |
| DMA etkisi | AD9364 shadow tap geri basınçsız tutuldu; Golden DMA yolu korundu |
| Kart entegrasyonu | Tek-frame ve 100-frame transport/control kabulü tamamlandı |
| Laboratuvar LO'su | Güncel v2 kontrollü-CW ara kabulü için `2.400000 GHz` |
| Güncel RF girişi | `RXA / A_BALANCED`; eski Wi-Fi testi RXB'ye özgüdür |
| Gain | `manual / 50 dB`, her frame öncesi readback |
| Kompleks peak I/Q | Mevcut v2 teslimde yok; magnitude-square spectrum/peak kullanılır |
| HMC936A yolu | Güncel 2.4 GHz FFT kabul yoluna dahil değildir; BDC sonrası 1.2-1.4 GHz IF sözleşmesi kapanmalıdır |
| Fiziksel CW | Henüz açık; manifest `board_verified=false` |
| S0-S3 ve açı | M5-M8 gelecek aşaması; tamamlanmış sayılmaz |

Bu nedenle ilk incelemedeki “LO'yu doğrudan 1.3 GHz yap” önerisi güncel ara
teslime uygulanmamıştır. HMC936A'nın kullanılacağı nihai RF yolu ancak BDC IF
frekansı ve kablo eşlemesi fiziksel olarak doğrulandıktan sonra ayrı bir
Candidate'da kilitlenecektir.
