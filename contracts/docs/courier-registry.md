# Kurye Kaydı: Stake, Seviyeler, Custody

> Kalıcı referans. Kaynak: `src/v1/registry/CourierRegistry.sol`
> Baseline: sec. 32.3, sec. 4.3–4.5, sec. 8.2, sec. 8.3, sec. 9, sec. 48, invariant sec. 33-4 ve sec. 33-10
> Faz: P0.4

---

## 1. Stake üçe bölünür

```text
stake = available + reserved + pendingWithdrawal
```

| Kalem | Anlamı |
|---|---|
| `available` | Yeni bir teslimatı veya yeni bir çekim talebini karşılayabilir |
| `reserved` | Devam eden teslimatlara bağlanmış teminat |
| `pendingWithdrawal` | Çekim için ayrılmış, cooldown'da bekliyor |

Çekim talebinin **ayrı bir kalem** olması kritik: aksi halde kurye çıkış talebi
verip aynı MON'u bekleme süresince teminat olarak kullanabilirdi (sec. 8.3).
Rezervasyonlar toplamalı ve `available` ile sınırlıdır — aynı MON iki teslimatı
aynı anda koruyamaz (invariant sec. 33-4).

---

## 2. Para registry'de değil, vault'ta

`CourierRegistry` **hiçbir zaman değer tutmaz**. Stake `SettlementVault`'ta,
kurye başına bir kilitte durur. Böylece protokolün tamamı için **tek bir ödeme
gücü invariant'ı** olur, kontrat başına bir tane değil (sec. 32.2).

Kilit id'si registry adresini içerir. K-1 kararıyla kontratlar immutable ve göç
yolu "yeniden deploy" olduğu için, yeni bir registry eski vault'u paylaşır;
adres olmasaydı kilit id'leri çakışır ve yeni registry hiç kilit açamazdı.

---

## 3. Her kurye çıkabilir

Legacy'de `Delivera.withdrawStake` **hiç yoktu** ve `DeliveryEscrow`'da
`isRegisteredCourier` tek yönlü bir bayraktı — minimumdaki bir kurye hiçbir şey
çekemiyordu. İkisi de canlı zincirde yeniden üretildi.

Burada çıkış yolu her zaman açıktır:

```bash
# 1) talep (veya tam cikis icin deregister)
cast send $REGISTRY "requestWithdrawal(uint256)" $AMOUNT ...
cast send $REGISTRY "deregister()" ...          # tum stake + kurye rolunden cik

# 2) cooldown (sec.48: 24 saat, ProtocolConfig'den okunur)

# 3) uygula -> vault'ta claimable'a yazilir
cast send $REGISTRY "executeWithdrawal()" ...

# 4) cek
cast send $VAULT "claim()" ...
```

`deregister` yalnızca **teminat ve elde paket yokken** çalışır — paketi taşıyan
ya da bir teslimatı garanti eden kurye çekip gidemez.

Kayıt durumu bayrak değil, **stake'ten türetilir**: minimumun altına düşünce
seviye otomatik olarak `None` olur (çekim ve slash sonrası).

`executeWithdrawal` doğrudan MON göndermez, vault'ta `claimable`'a yazar — cüzdanı
MON kabul etmeyen bir kurye hiçbir şeyi tıkayamaz.

Talep ve uygulama **pause sırasında da** çalışır: kullanıcı duraklatılmış bir
protokolden çıkabilmelidir (sec. 45).

---

## 4. Seviyeler ve risk katmanı kapısı

| Seviye | Nasıl alınır | Erişim |
|---|---|---|
| `None` | Stake minimumun altında | Yok |
| `C0` | Base deposit yatırınca **otomatik** | R1 |
| `C1` | `VERIFIER_ROLE` atar (zincir dışı doğrulama, sec. 4.4) | R1, R2 |
| `C2` | `VERIFIER_ROLE` atar (sec. 4.5) | R1, R2, R3 |

R4 devre dışıdır (sec. 49). `isEligibleFor` ayrıca askıya alınmış kuryeyi ve custody
limitindeki kuryeyi eler.

**Rozet teminatın yerine geçmez:** C0 üzerindeki her seviye base deposit'in yerinde
olmasını şart koşar (sec. 3.3, sec. 24).

---

## 5. Fiziksel custody

`MAX_ACTIVE_CUSTODY` (sec. 48: **1**) `ProtocolConfig`'den okunur ve `openCustody`
tarafından uygulanır (invariant sec. 33-10). Limitteki kurye yeni işe uygun değildir.

`openCustody` / `closeCustody` / `reserveCollateral` / `releaseCollateral` /
`slashCollateral` yalnızca `REGISTRY_CONTROLLER_ROLE` ile çağrılır. Bu rol
**kontratlara** verilir (P1'de `DeliveryHub`, P4'te `DisputeCourt`), asla bir
EOA'ya.

---

## 6. Slash

`slashCollateral` rezerveli teminatı bir alıcının vault'taki `claimable`
bakiyesine taşır; hem `reserved` hem `stake` azalır. Stake minimumun altına
düşerse kurye otomatik olarak devre dışı kalır.
