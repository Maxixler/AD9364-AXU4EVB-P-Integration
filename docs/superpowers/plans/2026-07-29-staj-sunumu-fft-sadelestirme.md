# Staj Sunumu FFT Sadeleştirme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Staj sunumundaki ayrıntılı FFT anlatımını mimari, doğrulama ve Python çıktısından oluşan üç anlaşılır ana slayta indirmek.

**Architecture:** Mevcut Slayt 17 RF aktivite kanıtı olarak korunacak; Slayt 18-23 tek hikâye kuran üç slaytla değiştirilecek. Eski kapanış slaytı 21 olarak yeniden numaralandırılacak; fixed-point, CDC ve protokol uygulama ayrıntıları yalnız yedek teknik bölümlerde kalacak.

**Tech Stack:** Markdown, Mermaid/metin tabanlı blok diyagramlar, PowerPoint için PNG/SVG kanıt görselleri.

## Global Constraints

- Ana FFT anlatımı üç slaytı geçmeyecek.
- Her ana FFT slaydında en fazla dört kısa madde ve tek ana görsel bulunacak.
- Ana veri yolu `AD9364 -> FPGA FFT -> UART -> Python` olarak tek bakışta anlaşılacak.
- Sinyalsiz preflight RF performans veya frekans doğruluğu kanıtı olarak sunulmayacak.
- Kontrollü CW testi tamamlanmamış fiziksel kabul adımı olarak açıkça korunacak.
- CDC, `0x6AB`, Q-format, CRC polinomu ve register ayrıntıları ana anlatımda bulunmayacak.

---

### Task 1: FFT Bölümünü Üç Ana Slayta İndir

**Files:**
- Modify: `PROJECT/reports/2026-07-30-staj-sunum-yapisi.md:527-798`

**Interfaces:**
- Consumes: Slayt 17'deki gerçek RF aktivite kanıtı ve mevcut FFT/Python doğrulama sonuçları.
- Produces: Slayt 18-20 arasında mimari, doğrulama ve Python çıktısı; Slayt 21'de sonuç/yol haritası.

- [ ] **Step 1: Mevcut ayrıntılı bölüm sınırını kaydet**

Run:

```powershell
rg -n "^### Slayt (17|18|19|20|21|22|23|24)" PROJECT/reports/2026-07-30-staj-sunum-yapisi.md
```

Expected: Slayt 17-24 başlıklarının tamamı görünür.

- [ ] **Step 2: Slayt 18'i sade mimari slaydı olarak yaz**

Slayt başlığı:

```markdown
### Slayt 18 — FPGA'da FFT: sinyalden spektruma
```

Slaytta yalnız şu dört madde bulunacak:

```markdown
- AD9364'ten kompleks I/Q örnekleri alınır.
- FPGA içinde 2048 noktalı FFT uygulanır.
- Tam spektrum korunur ve maksimum peak noktası bulunur.
- 30,72 MSPS örnekleme hızında çözünürlük 15 kHz/bin'dir.
```

Görsel akışı:

```text
AD9364 I/Q -> 2048 noktalı PL FFT -> Spektrum -> Peak
```

Ana konuşma mesajı, FFT'nin A53 yerine deterministik PL yolunda çalıştığını ve tam spektrumun debug/Python görünümü için korunduğunu iki cümleyi aşmadan açıklayacak.

- [ ] **Step 3: Slayt 19'u doğrulama ve kart kanıtı olarak yaz**

Slayt başlığı:

```markdown
### Slayt 19 — FFT nasıl doğrulandı?
```

Slaytta yalnız şu dört madde bulunacak:

```markdown
- FPGA sonucu bağımsız Python/NumPy modeliyle karşılaştırıldı.
- Deterministik testlerde bit-doğru sonuç elde edildi.
- Kartta tek-frame `PL_FFT: PASS` sonucu alındı.
- 100 ardışık frame boyunca aktarım ve sağlık kontrolleri geçti.
```

Kullanılacak kısa kanıt:

```text
PL_FFT: PASS frame=1 bank=0 peak_bin=88
PL_FFT_MONITOR: PASS frames=100 interval_ms=1000
```

Kontrollü RF uyarımı bulunmadığı için peak kararlılığının bu testin kabul ölçütü olmadığı tek cümleyle belirtilecek.

- [ ] **Step 4: Slayt 20'yi Python laboratuvar sonucu olarak yaz**

Slayt başlığı:

```markdown
### Slayt 20 — Bare-metal veriden Python FFT ekranına
```

Slaytta yalnız şu dört madde bulunacak:

```markdown
- Bare-metal uygulama FFT sonucunu PS_UART üzerinden bilgisayara taşır.
- Python uygulaması spektrum ve waterfall grafiğini oluşturur.
- CRC ve frame kontrolleri veri bütünlüğünü doğrular.
- 61/61 yazılım testi ve gerçek karttan 10-frame preflight geçti.
```

Görsel olarak `PROJECT/reports/assets/screenshots/2026-07-28-live-fft-no-rf-board.png` kullanılacak. Harici RF uygulanmadığı için boş spektrumun iletişim hatası olmadığı, bunun sinyalsiz preflight olduğu açıkça yazılacak.

- [ ] **Step 5: Sonuç slaydını 21 olarak yeniden numaralandır**

Eski `Slayt 24 — Kontrollü CW, monopulse yol haritası ve sonuç` başlığı `Slayt 21` yapılacak. Tamamlananlar, sıradaki kontrollü CW kabulü ve gelecekteki monopulse entegrasyonu korunacak; FFT iç uygulama ayrıntısı eklenmeyecek.

- [ ] **Step 6: Ana FFT bölümünde ayrıntı sızıntısı olmadığını doğrula**

Run:

```powershell
$text = Get-Content PROJECT/reports/2026-07-30-staj-sunum-yapisi.md -Raw
$main = ($text -split '# Yedek slaytlar')[0]
$main | Select-String -Pattern '0x6AB|Q1\.15|Q1\.31|stale epoch|W1C|33-bit|ISO-HDLC|little-endian'
```

Expected: Eşleşme üretmez.

- [ ] **Step 7: Task 1 değişikliğini kaydet**

```powershell
git add PROJECT/reports/2026-07-30-staj-sunum-yapisi.md
git commit -m "docs: simplify FFT presentation section"
```

---

### Task 2: Slayt Numaraları ve Süre Tablosunu Tutarlı Hale Getir

**Files:**
- Modify: `PROJECT/reports/2026-07-30-staj-sunum-yapisi.md:880-1000`

**Interfaces:**
- Consumes: Task 1'in ürettiği 21 slaytlık ana akış.
- Produces: Güncel süre tablosu, atlanabilecek ayrıntılar listesi ve Word raporu eşlemesi.

- [ ] **Step 1: Süre tablosunu 21 slayta göre güncelle**

Tablo şu aralıkları kullanacak:

```markdown
| Problem, hedef ve sistem sınırı | 1–7 | 6–7 dakika |
| Vivado ve donanım tasarımı | 8–10 | 3 dakika |
| Vitis, JTAG ve bring-up | 11–16 | 6 dakika |
| RF, FFT ve Python | 17–20 | 4–5 dakika |
| Sonuç ve yol haritası | 21 | 1–1,5 dakika |
| Toplam ana anlatım | 21 slayt | 19–22 dakika |
```

- [ ] **Step 2: Eski slayt numarası referanslarını düzelt**

`Süre aşılırsa` bölümünde:

- Slayt 20 scaling schedule maddesini kaldır.
- Yeni Slayt 19 için yalnız iki PASS satırının anlatılacağını belirt.
- Yeni Slayt 20 için test isimlerinin tek tek okunmayacağını belirt.

- [ ] **Step 3: Ana slayt numaralarının kesintisiz olduğunu doğrula**

Run:

```powershell
$heads = Select-String -Path PROJECT/reports/2026-07-30-staj-sunum-yapisi.md -Pattern '^### Slayt ([0-9]+)' |
    ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
$expected = 1..21
Compare-Object $expected $heads
```

Expected: Çıktı üretmez.

- [ ] **Step 4: Görsel varlığını doğrula**

Run:

```powershell
Test-Path PROJECT/reports/assets/screenshots/2026-07-28-python-verification-61-tests.png
Test-Path PROJECT/reports/assets/screenshots/2026-07-28-live-fft-no-rf-board.png
```

Expected:

```text
True
True
```

- [ ] **Step 5: Markdown değişikliğini gözden geçir**

Run:

```powershell
git diff --check
git diff -- PROJECT/reports/2026-07-30-staj-sunum-yapisi.md
```

Expected: `git diff --check` sessiz tamamlanır; diff yalnız FFT slaytları, sonraki slayt numarası ve süre/referans alanlarını değiştirir.

- [ ] **Step 6: Task 2 değişikliğini kaydet**

```powershell
git add PROJECT/reports/2026-07-30-staj-sunum-yapisi.md
git commit -m "docs: align presentation timing with simplified FFT flow"
```
