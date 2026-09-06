# Teslimat Yaşam Döngüsü

> Kalıcı referans. Kaynak: `src/v1/hub/DeliveryHub.sol`
> Baseline: sec. 7, sec. 10, sec. 11, sec. 16, sec. 17, sec. 18, invariant sec. 33-2, sec. 33-6, sec. 33-16, sec. 33-17
> Faz: P1.1

---

## 1. Oluşturma para almaz

Legacy kontrat bütçeyi **oluşturma anında** escrow'a alıyordu. Teklif gelmezse
paranın çıkış yolu yoktu — canlı zincirde yeniden üretildi ve deploy edilmiş
legacy kontrat hâlâ hiçbir fonksiyonun serbest bırakamayacağı MON tutuyor.

Burada fonlama **yalnızca teklif seçildikten sonra** olur (sec. 10). Kimsenin teklif
vermediği bir teslimat, ortada hiçbir şey yokken süresi dolarak kapanır.
"Oluşturuldu ama terk edildi" sınıfı yamanmadı, **yapısal olarak kaldırıldı**.

Testnet'te doğrulandı: teslimat oluşturulduğunda vault bakiyesi hiç değişmedi.

---

## 2. Durum makinesi

```text
Bidding ──seç──► AwaitingFunding ──iki taraf──► ReadyForPickup
   │                    │                            │
   │                    │                       confirmPickup
   │                    │                            ▼
   │                    │                        InTransit ──kanit──► DeliveredPending
   │                    │                            │                      │
   │                    │                       requestReturn          confirmDelivery
   │                    │                            ▼                      ▼
   │                    │                     ReturnRequired ──onay──►  Completed
   │                    │                            │
   ▼                    ▼                            ▼
Expired / Cancelled  Cancelled                    Returned
```

Terminal durumlar: `Completed`, `Returned`, `Cancelled`, `Expired`.
Terminal bir teslimat **hiçbir zaman** hareket edemez ve deadline taşımaz (sec. 33-6).

---

## 3. Her canlı durumun bir son tarihi var

Her canlı durum `stateDeadline` taşır. Süre geçtiğinde **herkes** `poke`
çağırabilir; teslimat terminal'e doğru ilerler ve tutulan ne varsa serbest kalır.
Hiçbir teslimat sonsuza kadar asılı kalamaz ve **hiç kimse parasını geri almak
için karşı tarafın işbirliğine muhtaç değildir**.

| Durum | Süre dolunca | Sonuç |
|---|---|---|
| `Bidding` | `Expired` | Ortada para yok |
| `AwaitingFunding` | `Cancelled` | Fonlayan taraf iade alır (sec. 10) |
| `ReadyForPickup` | `Cancelled` | Kurye gelmedi; escrow müşteriye |
| `InTransit` | `ReturnRequired` | Kurye pakete sahip; iade etmeli |
| `ReturnRequired` | `Returned` | Deterministik; müşteri tam iade alır |
| `DeliveredPending` | `Completed` | İzinsiz finalize edici (sec. 16) |

Zaman aşımları **deterministik** çözülür ve asla jüri vakası açmaz (sec. 26).
Kayıp/hasar iddiaları ihtilaf konusudur ve P4 ile gelir. Geç teslimat tek başına
teminat kesmez (sec. 13).

Invariant testi bunu doğruluyor: fuzzer'ın ürettiği herhangi bir durumdan
başlayıp yalnızca zaman atlayıp `poke` çağırarak **her teslimat terminal'e
sürülebiliyor**.

---

## 4. Teklifler

Teklif alanları (sec. 7): `courierAsk`, `returnAsk`, `etaMinutes`, `validUntil`,
`termsVersion`.

- Bir kuryenin teslimat başına **tek aktif teklif sürümü** olur; güncelleme
  sürümü artırır ve **ikinci bir rezervasyon yığmaz**.
- Müşteri seçerken gördüğü **tam sürümü** belirtir; kurye, müşteri teklifi
  okuduktan sonra fiyat değiştiremez.
- Süresi geçmiş teklif seçilemez.

### Teklif depozitosu ayrı bir escrow değil

Teklif vermek `CourierRegistry`'de teminat rezerve eder. **Kaybeden kuryeler
kendi rezervasyonlarını `withdrawBid` ile serbest bırakır**; hiçbir yerde teklif
listesi dolaşılmaz. `selectCourier` üç teklifle de üç bin teklifle de aynı gası
harcar (sec. 45).

Legacy'de `acceptBid` sınırsız bir döngü içeriyordu ve teklif sayısıyla
büyüyordu.

---

## 5. Self-dealing engeli

Müşterinin kendi teslimatının kuryesi olması **iki yerde** reddedilir: teklif
verirken ve seçim yaparken (sec. 33-16). İkisi de testnet'te doğrulandı.

---

## 6. Fonlama (sec. 10)

İki bağımsız yükümlülük, tek pencere:

```text
Musteri: courierAsk + protocolFee + returnReserve   (tam eslesme, sec. 33-17)
Kurye  : requiredCollateral
```

İkisi de tamamlanmadan `ReadyForPickup`'a geçilmez. Pencere dolarsa tamamlanan
taraf iade alır — hiçbir taraf diğerinin sermayesini süresiz tutamaz.

Kurye eksikse `fundAsCourier` ile aynı işlemde stake'ini yükseltip teminatını
kilitleyebilir (sec. 8.3 ek bond).

---

## 7. Uzlaşma (sec. 18.1)

| Başarılı teslimat | Nereye |
|---|---|
| `courierAsk` | Kurye `claimable` |
| `protocolFee` | Hazine `claimable` |
| Kullanılmayan `returnReserve` | Müşteri `claimable` |
| Kurye teminatı | Serbest |

Onaylanmış iadede `returnAsk` kuryeye ödenir, kalanı müşteriye. **Zaman aşımına
uğramış** iadede müşteri tam iade alır; kurye teminatı kesilmeden serbest bırakılır.

Uzlaşma değeri **itmez**, yalnızca `claimable` yazar — bkz.
[`settlement.md`](settlement.md).

---

## 8. Sonraki fazların bağlanacağı yerler

- **P1.3:** `requiredCollateral` şu an oluşturulurken veriliyor; imzalı ve süreli
  risk teklifi (sec. 8.3, sec. 33-8) oraya bağlanacak.
- **P2.1/P2.2:** `confirmPickup` ve `submitDeliveryProof` şu an çağıran kontrolü
  yapıyor; EIP-712 pickup imzası ve PoD attestation'ı bunların yerine geçecek.
  Durum geçişleri değişmeyecek.
- **P4:** `Disputed`/`Resolved` durumları ve ihtilaf girişi.
