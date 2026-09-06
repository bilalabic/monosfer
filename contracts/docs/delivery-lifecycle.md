# Teslimat Yaşam Döngüsü

> Kalıcı referans. Kaynak: `src/v1/hub/DeliveryHub.sol`
> Baseline: sec. 7, sec. 10, sec. 11, sec. 16, sec. 17, sec. 18,
> invariant sec. 33-2, sec. 33-6, sec. 33-16, sec. 33-17

---

## 1. Durum makinesi

```text
Bidding ──seç──► AwaitingFunding ──iki taraf──► ReadyForPickup
   │                    │                            │
   │                    │                       confirmPickup
   │                    │                            ▼
   │                    │                        InTransit ──kanıt──► DeliveredPending
   │                    │                            │                      │
   │                    │                       requestReturn          confirmDelivery
   │                    │                            ▼                      ▼
   │                    │                     ReturnRequired ──onay──►  Completed
   │                    │                            │
   ▼                    ▼                            ▼
Expired / Cancelled  Cancelled                    Returned
```

Terminal durumlar: `Completed`, `Returned`, `Cancelled`, `Expired`. Terminal bir
teslimat hiçbir zaman hareket edemez ve deadline taşımaz (invariant sec. 33-6).

---

## 2. İki taraf da taahhüt edene kadar hiçbir şey emanete girmez

Teslimat oluşturmak **ücretsizdir ve hiçbir şey kilitlemez**. Para, ancak bir
teklif seçildikten ve iki taraf da fonlama oturumunu tamamladıktan sonra girer
(sec. 10).

Sonuç: teklif almamış veya terk edilmiş bir ilanın kilitleyecek değeri yoktur —
süresi dolar ve kapanır.

---

## 3. Her canlı durumun bir son tarihi var

Her canlı durum `stateDeadline` taşır. Süre geçtiğinde **herkes** `poke`
çağırabilir; teslimat terminal duruma doğru ilerler ve tutulan ne varsa serbest
kalır.

| Durum | Süre dolunca | Sonuç |
|---|---|---|
| `Bidding` | `Expired` | Ortada değer yok |
| `AwaitingFunding` | `Cancelled` | Fonlayan taraf iade alır (sec. 10) |
| `ReadyForPickup` | `Cancelled` | Kurye gelmedi; escrow müşteriye |
| `InTransit` | `ReturnRequired` | Kurye pakete sahip; iade etmeli |
| `ReturnRequired` | `Returned` | Deterministik; müşteri tam iade alır |
| `DeliveredPending` | `Completed` | İzinsiz finalize edici (sec. 16) |

Garanti şudur: **hiçbir katılımcı parasını geri almak için karşı tarafın
işbirliğine muhtaç değildir** ve hiçbir teslimat süresiz olarak değer tutamaz.

Zaman aşımları deterministik çözülür ve asla jüri vakası açmaz (sec. 26).
Kusura dayalı sonuçlar kanıt gerektirir ve ihtilaf mahkemesine aittir; geç
teslimat tek başına teminat kesmez (sec. 13).

Bir invariant bunu doğrular: fuzzer'ın ürettiği herhangi bir durumdan başlayıp
yalnızca zaman atlayarak `poke` çağırmak, **her** teslimatı terminal duruma
ulaştırır.

---

## 4. Teklifler

Teklif alanları (sec. 7): `courierAsk`, `returnAsk`, `etaMinutes`, `validUntil`,
`termsVersion`.

- Bir kuryenin teslimat başına **tek aktif teklif sürümü** olur; güncelleme
  sürümü artırır ve ikinci bir rezervasyon yığmaz.
- Müşteri seçerken gördüğü **tam sürümü** belirtir, böylece kurye teklifi
  okunduktan sonra fiyat değiştiremez.
- Süresi geçmiş teklif seçilemez.
- Müşteri kendi teslimatının kuryesi olamaz; bu hem teklif hem seçim adımında
  reddedilir (invariant sec. 33-16).

### Seçim maliyeti teklif sayısıyla büyümez

Teklif vermek `CourierRegistry`'de teminat rezerve eder. **Seçilmeyen kuryeler
kendi rezervasyonlarını `withdrawBid` ile serbest bırakır.** Hiçbir yerde teklif
listesi dolaşılmadığı için `selectCourier`, üç teklifle de üç bin teklifle de
aynı gası harcar (sec. 45).

---

## 5. Fonlama oturumu (sec. 10)

İki bağımsız yükümlülük, tek pencere:

```text
Müşteri: courierAsk + protocolFee + returnReserve   (tam eşleşme, sec. 33-17)
Kurye  : requiredCoverage
```

İkisi de tamamlanmadan `ReadyForPickup`'a geçilmez. Pencere dolarsa tamamlanan
taraf iade alır; hiçbir taraf diğerinin sermayesini süresiz tutamaz.

Kapsam ikiye ayrılır ve olayla raporlanır (sec. 8.3):

```text
reservedBase   = min(mevcutStake, gerekenKapsam)
additionalBond = gerekenKapsam - reservedBase
```

`additionalBond` aynı işlemde gönderilebilir; eksikse `InsufficientBond` ile
reddedilir. Teklif verirken kilitlenen depozito `reservedBase`'e sayılır,
serbest bırakılıp yeniden alınmaz.

---

## 6. Uzlaşma (sec. 18.1)

| Başarılı teslimat | Nereye |
|---|---|
| `courierAsk` | Kurye `claimable` |
| `protocolFee` | Hazine `claimable` |
| Kullanılmayan `returnReserve` | Müşteri `claimable` |
| Kurye teminatı | Serbest |

Onaylanmış iadede `returnAsk` kuryeye ödenir, kalanı müşteriye. Zaman aşımına
uğramış iadede müşteri tam iade alır ve kurye teminatı kesilmeden serbest kalır.

Uzlaşma değeri itmez, yalnızca `claimable` yazar — bkz.
[`settlement.md`](settlement.md).

---

## 7. Risk katmanı ve kapsam

Risk katmanı ve gereken teminat, risk servisinin imzaladığı bir kapsam
teklifinden gelir ve zincirde yeniden sınırlandırılır — bkz.
[`risk-quote.md`](risk-quote.md).

---

## 8. Sonraki fazların bağlanacağı yerler

- **P2.1 / P2.2:** `confirmPickup` ve `submitDeliveryProof` şu an çağıran
  kontrolü yapar; yerlerine EIP-712 pickup imzası ve PoD attestation'ı gelecek.
  Durum geçişleri değişmeyecek.
- **P4:** `Disputed` / `Resolved` durumları ve ihtilaf girişi.
