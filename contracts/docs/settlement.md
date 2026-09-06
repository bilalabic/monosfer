# Settlement Modeli: Pull-Payment ve Ödeme Güvenliği

> Kalıcı referans (sürümsüz, sistem geliştikçe güncellenir).
> Kaynak: `src/v1/vault/SettlementVault.sol`, `src/v1/interfaces/ISettlementVault.sol`
> Baseline: sec. 32.2, sec. 18.2, sec. 45, invariant sec. 33-1, sec. 33-2, sec. 33-3, sec. 33-11
> Faz: P0.3

---

## 1. Çözülen sorun

Legacy kontratlar ödemeyi **iterek** yapıyor:

```solidity
(bool ok, ) = platformTreasury.call{value: treasuryFee}("");
require(okTreasury, "Treasury transfer failed");   // <-- burası
```

Tek bir alıcı (hazine, ödül havuzu veya kurye) MON kabul etmiyorsa `confirmDelivery`
**kalıcı olarak** revert eder: kuryenin ödemesi de, müşterinin escrow'u da donar.
Bu teorik değil — canlı zincirde yeniden üretildi (`[PoC-D]`) ve deploy edilmiş
legacy Delivera kontratı şu anda hiçbir fonksiyonun serbest bırakamayacağı MON tutuyor.

---

## 2. Çözüm: settlement değer göndermez

`SettlementVault`'ta uzlaşma **sadece defter kaydıdır**.

```text
lock()        -> kontrat parayı alır, "locked" olarak kaydeder
releaseLock() -> locked bakiyeyi claimable'a tasir    (HIC dis cagri yok)
claim()       -> sahibi kendi parasini ceker          (tek deger cikisi)
```

`releaseLock` hiçbir dış çağrı yapmadığı için **üçüncü bir taraf onu
başarısız kılamaz**. Değer kontrattan tek bir yerde çıkar: `_payOut`, ve oraya
yalnızca kişi kendi parasını çekerken gelinir. O transfer başarısız olursa
sadece **o çağıranın kendi işlemi** geri alınır; bakiyesi yerinde kalır ve
başka hiç kimse etkilenmez.

| Legacy | V1 Vault |
|---|---|
| Uzlaşma sırasında 3 dış çağrı | **0 dış çağrı** |
| Bir alıcı reddederse herkes bloke | Sadece o alıcı çekemiyor |
| Bloke olan para kalıcı kilitli | Bakiye duruyor, sonra çekilebilir |

---

## 3. Ödeme gücü (solvency)

```text
address(this).balance  >=  totalLocked + totalClaimable
```

Bu koşul **her durum değiştiren çağrıdan sonra kodda** kontrol edilir (`solvent`
modifier), sadece testlerde değil — ihlali kullanıcı parasının çoktan gitmiş
olması demektir.

Bakiye yükümlülüğü **aşabilir**: `selfdestruct` ile zorla gönderilen değer
kaydedilmez, `surplus()` ile raporlanır ve kimse tarafından talep edilemez.
Bakiye yükümlülüğün **altına düşemez**.

### Değer korunumu

`releaseLock` ödemelerin toplamının kilide **tam eşit** olmasını şart koşar —
"en fazla" değil. Eksik ödeme, sahibi olmayan bir bakiye artığı bırakırdı ki bu
tam da kaldırmaya çalıştığımız legacy davranışı.

---

## 4. Reentrancy ve CEI

- Tüm değer çıkışları `nonReentrant`.
- `_payOut` bakiyeyi **dış çağrıdan önce** sıfırlar (checks-effects-interactions).
- Uzlaşma yolunda hiç dış çağrı olmadığı için orada reentrancy yüzeyi yoktur.

`ReentrantClaimer` testi: alıcı `receive()` içinden `claim()`'i tekrar çağırıyor,
reddediliyor, ve saldırgan tam olarak kendi bakiyesini **bir kez** alıyor.

---

## 5. Pause davranışı

sec. 45 "duraklatma sırasında güvenli kullanıcı çıkışı" şart koşuyor:

| İşlem | Pause'da | Gerekçe |
|---|---|---|
| `lock`, `topUpLock` | **Bloke** | Yeni emanet alınmaz |
| `releaseLock`, `refundLock` | **Açık** | Sadece iç bakiyeyi kullanıcıya doğru taşır |
| `claim`, `claimFor` | **Açık** | Kullanıcı her zaman çıkabilmeli |

---

## 6. Yetkilendirme

`lock` / `releaseLock` / `refundLock` yalnızca `VAULT_CONTROLLER_ROLE` sahibi
çağırabilir. Bu rol **kontratlara** verilir (P1'de `DeliveryHub`, P4'te
`DisputeCourt`), asla bir EOA'ya. `claim` ve `claimFor` izinsizdir.

`claimFor` her zaman **hesabın kendisine** öder, çağırana değil — bir keeper
kullanıcıya parayı itebilir ama yönünü değiştiremez.

---

## 7. sec. 32.12 rail soyutlaması

Teslimat yaşam döngüsü `ISettlementVault` arayüzüne bağımlıdır, somut kontrata
değil. V1 native MON ile uzlaşan tek bir uygulama sunar; ileride farklı bir ödeme
rayı **aynı arayüzün başka bir uygulaması** olur, `DeliveryHub`'da değişiklik
gerektirmez.

Arayüz bilinçli olarak **push-free**: içinde üçüncü tarafa değer gönderen tek bir
fonksiyon yoktur.

---

## 8. Test kapsamı

24 birim/fuzz testi + 4 invariant.

| Invariant | Garanti |
|---|---|
| `invariant_VaultIsSolvent` | sec. 33-1 — bakiye ≥ yükümlülük |
| `invariant_ValueIsConserved` | sec. 33-3 — (yatırılan − çekilen) = yükümlülük |
| `invariant_NeverOwesMoreThanDeposited` | Vault aldığından fazlasını borçlanamaz |
| `invariant_LockedMatchesActiveLocks` | Uzlaşmış kilit tekrar değer tutamaz |

Değer korunumu, vault'un kendi sayaçlarına değil, **dışarıdan gözlenen akışa**
karşı ölçülür; böylece vault kendi yanlış rakamlarıyla tutarlı olarak testi
geçemez.

Boşluk güvencesi: `test_HandlerReachesSettlementAndClaim` fuzzer'ın gerçekten
uzlaşma ve çekim noktasına ulaşabildiğini kanıtlar — yoksa invariant'lar boşuna
yeşil olurdu.

---

## 9. Henüz yapılmayanlar

Bu faz custody **primitifini** kurar. Teslimat-özel muhasebe sonraki fazlarda:

- kurye teminatı ve ek bond → P0.4 `CourierRegistry`
- teslimat escrow'u ve iptal/timeout yolları → P1.1 `DeliveryHub`
- jüri stake'i ve tahkim ücretleri → P4 `DisputeCourt`
