# ZX80-DR230-S+ ve EV1HMC936ALP6 RF Kontrol Sözleşmesi

**Tarih:** 20 Temmuz 2026
**Durum:** Parça kimliği ve üretici elektriksel verileri doğrulandı; BDC IF frekansı, RF1/RF2 kablo eşlemesi, FPGA konnektör/pinleri ve seviye dönüştürücü devresi henüz kapatılmadı.

## 1. Doğrulanan parçalar

Kullanıcı fotoğrafı ve üretici dokümanları aşağıdaki iki parçayı doğrular:

- Mini-Circuits `ZX80-DR230-S+`: absorptive SPDT, 50 ohm, DC-3000 MHz, SMA.
- Analog Devices `EV1HMC936ALP6`: üzerinde `HMC936ALP6E` bulunan 6-bit dijital phase-shifter değerlendirme kartı. Kart etiketi `2017 120557 163` parça modeli değildir.

Bağlayıcı üretici kaynakları:

- Mini-Circuits ürün/datasheet: `https://www.minicircuits.com/WebStore/dashboard.html?model=ZX80-DR230-S%2B`
- Analog Devices HMC936A ürün sayfası: `https://www.analog.com/en/products/HMC936A.html`
- Analog Devices HMC936A datasheet: `https://www.analog.com/media/en/technical-documentation/data-sheets/hmc936a.pdf`

## 2. Frekans-planı kapısı

`ZX80-DR230-S+` DC-3 GHz aralığını kapsar. `HMC936A` ise yalnız 1.2-1.4 GHz için derecelendirilmiştir. Bu nedenle SPDT ve phase shifter'ın bulunduğu seçilebilir Delta yolu X-band RF'de değil, BDC sonrasındaki **1.2-1.4 GHz IF** üzerinde çalışmalıdır.

Aşağıdaki bilgi ölçülmeden veya BDC etiketi/datasheet'iyle doğrulanmadan RF entegrasyonu başlatılmaz:

- BDC RF giriş frekansı
- BDC LO frekansı
- BDC IF merkez frekansı ve işgal bandı
- BDC conversion gain ve maksimum çıkış seviyesi
- Σ, ΔAZ ve ΔEL BDC'lerinin ortak LO/referans kaynağı
- Üç downconverter yolunun göreli faz drift'i ve kalibrasyon kararlılığı

Hedef IF 1.2-1.4 GHz dışında ise HMC936A bu mimaride kabul edilemez; yazılımla düzeltilemez.

## 3. ZX80-DR230-S+ sözleşmesi

### 3.1 Elektriksel sınırlar

- `VDD`: 2.7-5.0 V
- Kontrol LOW: 0-0.4 V
- Kontrol HIGH: 2.4 V ile `VDD` arası
- Kontrol akımı: pin başına en fazla 1 mA
- Tipik switching time: 2 us; datasheet maksimum süre garanti etmez
- RF common: `J2`; RF2: `J1`; RF1: `J3`
- `J1/J2/J3` RF portlarının DC seviyesi 0 V olmalıdır; zincirde DC bias varsa uygun DC block zorunludur
- Kontrol pinleri: `P1=Control1`, `P3=Control2`, `P5=VDD`; `P2/P4=GND`

Kullanıcı fotoğrafında, etiket yüzüne bakıldığında RF SMA portları soldan sağa `RF2`, `RF COM`, `RF1`; sol taraftaki kontrol uçları yukarıdan aşağı `Control2`, `GND`, `Control1`; sağ taraftaki uçlar yukarıdan aşağı `GND`, `VDD` olarak okunur. Bu görsel yön bilgisi elektriksel süreklilik kontrolünün yerine geçmez, fakat kablo etiketleme formunun başlangıç referansıdır.

3.3 V GPIO, switch `VDD` değeri 3.3 V veya 5 V seçildiğinde datasheet HIGH eşiğini karşılar. Buna rağmen switch beslemesi FPGA pininden sağlanmaz; harici regüle besleme ve ortak ground kullanılır.

### 3.2 Doğruluk tablosu

| Control1 | Control2 | RF1 | RF2 | Kullanım |
|---:|---:|---|---|---|
| 0 | 0 | OFF | OFF | Güvenli başlangıç/abort |
| 0 | 1 | OFF | ON | İkinci Delta yolu |
| 1 | 0 | ON | OFF | Birinci Delta yolu |
| 1 | 1 | Geçersiz | Geçersiz | RTL ve yazılım tarafından yasaklanır |

`Delta AZ -> RF1/RF2` ve `Delta EL -> RF2/RF1` eşlemesi kablo takibiyle belirlenir. FSM doğrudan AZ=RF1 varsaymaz; iki yönlü yapılandırma biti veya sabit bir board mapping paketi kullanır.

## 4. EV1HMC936ALP6 sözleşmesi

### 4.1 RF ve besleme

- Derecelendirilmiş RF aralığı: 1.2-1.4 GHz
- Phase coverage: 360 derece
- Altı ağırlık: 5.625, 11.25, 22.5, 45, 90 ve 180 derece
- `VDD`: nominal +5 V; tipik akım 3 mA
- Kontrol: 0/+5 V pozitif kontrol gerilimi
- LOW: 0-0.2 V
- HIGH: `VDD +/- 0.2 V`
- Tipik phase settling: 175 ns; amplitude settling: 225 ns; switching: 250 ns

AXU4EVB-P'nin 3.3 V veya 1.8 V GPIO'su HMC936A HIGH şartını karşılamaz. Altı kontrol hattı için 5 V çıkışlı, giriş eşiği seçilen FPGA bankıyla uyumlu tek yönlü level-shifter/buffer zorunludur. Buffer `OE` ve pull-up/down ağı, FPGA konfigüre değilken RF sistemini tanımlı durumda tutmalıdır.

### 4.2 Aktif-düşük faz kodu

HMC936A truth table'ında bir faz ağırlığı kontrol biti LOW yapıldığında seçilir. Yeni yakın plan fotoğraf, komponent yüzünden ve `RF1` solda/`RF2` sağda olacak yönde bakıldığında kullanılan sekiz başlık konumunun soldan sağa `VDD`, `5.625`, `11.25`, `22.5`, `VSS`, `45`, `90`, `180` olarak etiketlendiğini gösterir. Üretici datasheet'i bunları sırasıyla `BIT1..BIT6` faz ağırlıklarıyla doğrular; J3 ise fiziksel olarak 2 mm, 16 pin başlıktır. Fotoğraf kablo renklerinin uçtan uca net elektriksel eşlemesini kanıtlamaz. Fiziksel bağlantıdan önce süreklilik testiyle eval-header etiketi -> HMC `BIT1..BIT6` -> kablo rengi -> level-shifter kanalı -> FPGA pini tablosu oluşturulur; tablo kapanmadan `011111` fiziksel pine uygulanmaz.

RTL içinde doğal bir `phase_index[5:0]` kullanılır:

```text
istenen nominal faz = phase_index * 5.625 derece
phase_gpio_raw[5:0] = bitwise_not(phase_index[5:0])
```

Nominal örnekler:

| İstenen faz | `phase_index[5:0]` | Fiziksel `phase_gpio_raw[5:0]` |
|---:|---:|---:|
| 0 derece | `000000` | `111111` |
| 180 derece | `100000` | `011111` |
| 354.375 derece | `111111` | `000000` |

Monopulse kalibrasyonu yalnız sabit 0/180 koduna kilitlenmez. Her eksen için ölçülmüş bir `phase_base` kodu tutulabilir. Nominal eksi durum kodu `(phase_base + 32) mod 64` olur; gerçek oda kalibrasyonu gerekirse PLUS ve MINUS kodlarını ayrı LUT girişleri olarak düzeltir.

## 5. Birleşik güvenli kontrol sırası

1. Power-up/abort sırasında ZX80 `Control1=0`, `Control2=0` ile iki yolu da kapat.
2. HMC936A level-shifter çıkışlarını tanımlı kalibrasyon koduna getir.
3. ZX80 üzerinde yalnız bir Delta yolunu etkinleştir; `11` durumunu donanımsal ve RTL assertion ile yasakla.
4. En az yapılandırılmış `settle_time` kadar bekle.
5. Yapılandırılmış sayıda ADC örneğini discard et.
6. 2048 geçerli kompleks örneği yakala.

İlk laboratuvar değeri olarak 10 us settle kullanılabilir; bu, iki parçanın tipik sürelerinden daha büyüktür ancak üretici maksimumu değildir. Nihai değer SMW200A tonu ile geçiş sonrası güç/faz kararlılığı ölçülerek ve sıcaklık marjı eklenerek kapatılır.

## 6. Kapatılması gereken fiziksel isterler

- BDC'nin gerçek IF merkez frekansı 1.2-1.4 GHz içinde mi?
- Üç BDC aynı LO/referansı paylaşıyor mu ve göreli faz drift'i kabul edilen ölçüm süresinde ne kadar?
- ZX80 `J1/J2/J3` portlarının her biri 0 VDC mi; değilse DC block nerede?
- Delta AZ ve Delta EL kablolarından hangisi ZX80 `RF1`, hangisi `RF2` olacak?
- ZX80 `VDD` 3.3 V mu 5 V mu olacak ve hangi regüle kaynaktan beslenecek?
- HMC936A için kullanılacak 5 V level-shifter/buffer şeması ve güvenli `OE` durumu nedir?
- Sekiz kontrol çıkışı için AXU4EVB-P konnektör/pin/bank voltajı nedir?
- Eval-header `5.625..180` -> HMC `BIT1..BIT6` -> kablo rengi -> level-shifter kanalı -> FPGA pini süreklilik tablosu nedir?
- HMC `RF1 -> RF2` yönü ile analog zincirdeki giriş/çıkış yönü nasıl bağlanacak?
- SPDT ve HMC sonrası gerçek settle/discard değerleri kaçtır?

Bu maddeler kapanmadan XDC pinleri, fiziksel GPIO modülü veya RF ile kart kabul testi tamamlanmış sayılmaz.
