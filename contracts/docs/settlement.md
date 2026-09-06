# Uzlaşma Modeli: Pull-Payment ve Ödeme Gücü

> Kalıcı referans. Kaynak: `src/v1/vault/SettlementVault.sol`, `src/v1/interfaces/ISettlementVault.sol`
> Baseline: sec. 32.2, sec. 18.2, sec. 45, invariant sec. 33-1, sec. 33-2, sec. 33-3, sec. 33-11

---

## 1. Uzlaşma defter kaydıdır; değeri yalnızca sahibi taşır

```text
lock()        -> kontrat parayı alır, "locked" olarak kaydeder
releaseLock() -> locked bakiyeyi claimable'a taşır      (hiç dış çağrı yok)
claim()       -> sahibi kendi parasını çeker            (tek değer çıkışı)
```

`releaseLock` ve `refundLock` hiçbir dış çağrı yapmaz. Değer kontrattan tek bir
yerden çıkar — `_payOut` — ve oraya yalnızca kişi **kendi** parasını çekerken
gelinir.

Bunun kazandırdığı özellik:

> **Hiçbir alacaklı, başka bir alacaklıyı etkileyemez.**

MON kabul etmeyen, tüm gazı yakan veya hiç `claim` çağırmayan bir cüzdan yine de
alacaklandırılır; diğer herkes normal şekilde uzlaşır ve parasını çeker.
Başarısız bir çekim yalnızca o çağıranın işlemini geri alır, bakiyesi yerinde
kalır ve sonra tekrar denenebilir.

Bu, uzlaşmanın üçüncü bir tarafın davranışına bağımlı olmamasını sağlar
(sec. 18.2, invariant sec. 33-11).

---

## 2. Ödeme gücü

Durum değiştiren her çağrıdan sonra:

```text
address(this).balance  >=  totalLocked + totalClaimable
```

Bu koşul **kodda** kontrol edilir (`solvent` modifier), sadece testlerde değil —
ihlali, kullanıcı parasının çoktan gitmiş olması demektir.

Bakiye yükümlülüğü **aşabilir**: `selfdestruct` ile zorla gönderilen değer
kaydedilmez, `surplus()` ile raporlanır ve kimse talep edemez. Bakiye
yükümlülüğün **altına düşemez**.

### Değer korunumu

`releaseLock`, ödemelerin toplamının kilide **tam eşit** olmasını şart koşar —
"en fazla" değil. Eksik ödeme, sahibi olmayan bir bakiye artığı bırakırdı: gürültülü
bir hata değil, sessiz bir sızıntı (invariant sec. 33-3).

---

## 3. Reentrancy ve CEI

- Tüm değer çıkışları `nonReentrant`.
- `_payOut` bakiyeyi **dış çağrıdan önce** sıfırlar.
- Uzlaşma yolunda hiç dış çağrı olmadığı için orada reentrancy yüzeyi yoktur.

`ReentrantClaimer` testi bunu doğrular: alıcı `receive()` içinden `claim()`'i
tekrar çağırır, reddedilir ve tam olarak kendi bakiyesini **bir kez** alır.

---

## 4. Pause davranışı

sec. 45 duraklatma sırasında güvenli kullanıcı çıkışı şart koşar:

| İşlem | Pause'da | Gerekçe |
|---|---|---|
| `lock`, `topUpLock` | **Bloke** | Yeni emanet alınmaz |
| `releaseLock`, `refundLock` | **Açık** | Yalnızca iç bakiyeyi kullanıcıya doğru taşır |
| `claim`, `claimFor` | **Açık** | Duraklatılmış bir protokolden çıkılabilmeli |

---

## 5. Yetkilendirme

`lock` / `releaseLock` / `releasePartial` / `refundLock` yalnızca
`VAULT_CONTROLLER_ROLE` ile çağrılır. Bu rol **kontratlara** verilir
(`DeliveryHub`, `CourierRegistry`, ileride `DisputeCourt`), asla bir EOA'ya.

`claim` ve `claimFor` izinsizdir. `claimFor` her zaman **hesabın kendisine** öder,
çağırana değil — bir keeper kullanıcıya parayı itebilir ama yönünü değiştiremez.

### Tam ve kısmi serbest bırakma

| Fonksiyon | Kural | Kullanım |
|---|---|---|
| `releaseLock` | Toplam kilide **tam eşit**, kilit kapanır | Teslimat uzlaşması |
| `releasePartial` | Toplam kilitten **küçük olabilir**, kalan kilitli kalır | Stake çekimi, slash |

Katı eşitlik kuralı teslimat yolunda korunur; kısmi çekim yalnızca bakiyenin bir
kısmının serbest kalması gereken yerlerde kullanılır.

---

## 6. Rail soyutlaması (sec. 32.12)

Teslimat yaşam döngüsü `ISettlementVault` arayüzüne bağımlıdır, somut kontrata
değil. V1 native MON ile uzlaşan tek bir uygulama sunar; farklı bir ödeme rayı
**aynı arayüzün başka bir uygulaması** olur ve `DeliveryHub`'da değişiklik
gerektirmez.

Arayüz bilinçli olarak **push-free**: içinde üçüncü tarafa değer gönderen tek bir
fonksiyon yoktur.

---

## 7. Test kapsamı

24 birim/fuzz testi + 4 invariant.

| Invariant | Garanti |
|---|---|
| `invariant_VaultIsSolvent` | sec. 33-1 — bakiye ≥ yükümlülük |
| `invariant_ValueIsConserved` | sec. 33-3 — (yatırılan − çekilen) = yükümlülük |
| `invariant_NeverOwesMoreThanDeposited` | Vault aldığından fazlasını borçlanamaz |
| `invariant_LockedMatchesActiveLocks` | Uzlaşmış kilit tekrar değer tutamaz |

Değer korunumu, vault'un kendi sayaçlarına değil **dışarıdan gözlenen akışa**
karşı ölçülür; böylece vault kendi yanlış rakamlarıyla tutarlı olarak testi
geçemez. Fuzzer sürekli olarak MON kabul etmeyen bir alıcıya kredi verir.

`test_HandlerReachesSettlementAndClaim`, fuzzer'ın gerçekten uzlaşma ve çekim
noktasına ulaşabildiğini kanıtlar — yoksa invariant'lar boşuna yeşil olurdu.
