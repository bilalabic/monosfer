# İtibar: Puan ve Güven Seviyesi

> Kalıcı referans. Kaynak: `src/v1/reputation/ReputationRegistry.sol`
> Baseline: sec. 13, sec. 19, sec. 20, sec. 22
> Faz: P3.1

---

## 1. Puan ve güven ayrı iki soru

Puan "bu kurye ne kadar iyi iş çıkarıyor" sorusunu, güven seviyesi "bu yargı ne
kadar geçmişe dayanıyor" sorusunu yanıtlar. İkisini ayrı tutmak, **tek mükemmel
teslimatı olan bir kuryenin yüzlercesi olanla aynı okunmasını** engeller
(sec. 19): puanları yakın olabilir, güven seviyeleri olamaz.

Güven bilerek puana çarpan olarak katılmadı — katılsaydı iyi bir yeni kurye ile
vasat bir veteran ayırt edilemez hale gelirdi, oysa ikisi farklı yanıt gerektirir.

| | Aralık | Neyi ölçer |
|---|---|---|
| Puan | 0–1000 | Performans |
| Güven | 0–1000 | Performansın dayandığı hacim |

Güven 100 tamamlanmış teslimatta doyar; ötesi güven eklemez.

---

## 2. sec. 19 ağırlık tablosu

| Sinyal | Ağırlık |
|---|---:|
| Başarılı teslimat | %30 |
| Müşteri puanı | %20 |
| Zamanında performans | %15 |
| İhtilaf performansı | %15 |
| Kurye kaynaklı iptal | %10 |
| Deneyim / güven | %10 |

Ağırlıklar derleme-zamanı sabitidir. Değiştirmek bir yapılandırma ayarı değil,
**bilinçli bir yeni sürümdür**.

---

## 3. Kanıt yoksa nötr, mükemmel değil

Geçmişi olmayan bir kuryenin lehine de aleyhine de kanıt yoktur, bu yüzden oran
biçimli bileşenler tam not değil **orta noktadan** başlar. Tam nottan başlamak,
yeni açılmış bir hesaba maksimum puan vermek olurdu — itibar sisteminin varlık
sebebinin tam tersi.

İki bileşen bunun istisnasıdır ve sebebi açıktır:

- **İhtilafı olmamak** bir boşluk değil, kanıttır — hiç ihtilafa düşmemiş kurye
  tam not alır.
- **Hiç atama almamış** bir kuryenin terk ettiği bir iş de yoktur.

---

## 4. Zamanındalık kuryenin kendi verdiği ETA'ya göre ölçülür

sec. 13 gereği gecikme, protokol çapında bir sabite göre değil, **kuryenin kendi
teklifinde kabul ettiği ETA'ya** göre değerlendirilir. `DeliveryHub` teslim alma
anında `etaDeadline = şimdi + teklifteki etaMinutes` değerini sabitler; böylece
sonradan yapılan bir config değişikliği geçmişe dönük olarak bir teslimatı geç
gösteremez.

600 dakikalık ETA veren kurye 31 dakikada geç kalmaz; 30 dakikalık ETA veren
kalır. Aynı kontrat, aynı süre, farklı taahhüt.

---

## 5. İptal kuryeye yazılmaz

Bir teslimat, devir gerçekleşmediğinde `Cancelled` olur. P2.1 buna **meşru** bir
yol açtı: imzalamayı reddeden bir gönderen teslimatı pencere kapanana kadar
askıda bırakır. Zincir bunu hiç gelmemiş bir kuryeden ayırt edemez ve sec. 13
olumsuz sonucun tek başına kusur olmadığını açıkça söyler.

Bu yüzden iptal, itibar açısından **nötr** kaydedilir. `Outcome.CancelledByCourier`
yalnızca kanıta dayanan bir merci — ihtilaf mahkemesi (P4) — tarafından
raporlanmak üzere durur; başka hiçbir yol onu üretmez.

---

## 6. Zincirde sıralama yok (sec. 22)

Kontratta kurye dizisi, sıralama ve herhangi bir iterasyon **yoktur** — yalnızca
kurye başına sayaçlar. Sıralama, buradaki olaylardan indexer tarafından türetilir.

Depolanan kuryeleri sıralayan bir liderlik tablosu kurye sayısında karesel
büyür ve tam da protokol başarılı olduğunda çalışmayı bırakır.

Her değişiklik `ReputationUpdated(courier, score, confidence, version)` yayar;
indexer'ın ihtiyacı olan her şey olaylardadır.

---

## 7. İtibar parayı bloke edemez

`DeliveryHub` itibar kaydını **hata toleranslı** yapar: çağrı düşük seviyeli
yapılır ve başarısızlığı yayılmaz, `ReputationReportFailed` olayıyla görünür
kılınır. Rolü geri alınmış, değiştirilmiş veya hatalı bir registry bir teslimatı
askıda bırakamaz, bir ödemeyi geciktiremez.

Puanlama (`rateCourier`) ise bilinçli olarak **hata toleranslı değildir**: orada
uzlaşan bir şey yoktur, reddedilen bir puanlama müşteriye sebebini söylemelidir.

Testte kayıtlı: `test_BrokenReputationCannotBlockSettlement` — registry'nin yazma
rolü teslimat sürerken geri alınır, uzlaşma yine de tam ödeme yapar.

---

## 8. Sürümleme

`ALGORITHM_VERSION` her güncellemeyle yayılır. Formül değiştiğinde geçmiş puanlar
yorumlanabilir kalır, çünkü her biri hangi formülün ürettiğini söyler.

| Sürüm | Değişiklik |
|---|---|
| 1 | İlk sürüm: sec. 19 ağırlık tablosu, nötr priorler, 100 teslimatta doyan güven |

---

## 9. Test kapsamı

34 test (21 birim/fuzz + 13 entegrasyon).

Mutasyon testi — her kural tek tek koddan çıkarıldığında test kırılıyor:

| Kaldırılan | Kırılan test |
|---|---|
| Nötr prior (tam nota çevrildi) | 2 |
| İptal cezası | 2 |
| Rating ağırlığı | 2 |
| İhtilaf cezası | 2 |
| Zamanındalık ağırlığı | 2 |
| Deneyime bağlı güven | 4 |

> **Not:** ilk yazımda iki test boş çıktı — "yeni kurye nötr başlar" testi priorler
> tam nota çevrilse bile geçiyordu, "iptal puanı düşürür" testi ise aslında başarı
> oranındaki düşüşü ölçüyordu. İkisi de sıkılaştırıldı; ikincisi artık iptal eden
> ile iade edeni karşılaştırıyor, yani sadece iptal bileşeni farklı.

---

## 10. Backend'in sorumlulukları

- **Liderlik tablosu tamamen backend'e ait** (sec. 22, sec. 51): olaylardan
  deterministik olarak yeniden hesaplanır.
- Frontend puanı **ve güven seviyesini birlikte** göstermeli; tek başına puan
  yanıltıcıdır.
- `ratingWindow` (varsayılan 7 gün) sec. 48'de yok; sec. 20 sınırlı olmasını
  istiyor, değerini vermiyor. Diğer yaşam döngüsü pencereleri gibi zaman kilitli
  ve sınırlı.
