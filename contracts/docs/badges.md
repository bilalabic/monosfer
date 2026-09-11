# Rozetler: Devredilemez Başarı NFT'leri

> Kalıcı referans. Kaynak: `src/v1/badge/BadgeSBT.sol`, `src/v1/badge/IERC5192.sol`
> Baseline: sec. 22, sec. 24
> Faz: P3.2

---

## 1. Rozetler talep edilir, itilmez

Uzlaşma yolundaki **hiçbir kod bu kontratı çağırmaz**. Kurye (veya onun adına
herhangi biri) hak ettiği rozeti talep eder, talep de itibar kaydını okuyarak
doğrulanır.

Bu bir kolaylık değil, yapısal bir karar. `confirmDelivery` içinden basım yapmak,
buradaki bir hatanın — revert, gas tükenmesi, yanlış kurgulanmış bir duplicate
kontrolü — birinin ödemesini askıya alabilmesi demektir. Dekoratif bir alt
sistemin bunu yapabilmesi kabul edilemez ve bunu garanti etmenin en kesin yolu,
uzlaşmadan bu kontrata giden **hiçbir çağrı bırakmamaktır**.

---

## 2. İki tür rozet, yalnızca biri izinsiz olabilir

| Tür | Nasıl alınır | Neden |
|---|---|---|
| Geçmişe dayalı (8 adet) | `claim()` — izinsiz, kontrat kendisi doğrular | Zincirdeki geçmiş hakkında bir ifade |
| `TopTenWeekly` | `award()` — `BADGE_AWARDER_ROLE` | Zincir sıralama yapamaz (sec. 22) |

sec. 22 sıralamayı bilerek indexer'a koyuyor, çünkü kurye sıralamak zincirde
ölçeklenmiyor. Dolayısıyla zincir kimin ilk ona girdiğini **bilemez**. Bu ayrımı
gizlemek yerine API'de görünür kıldık: haftalık rozet talep edilemez, verilir.

Rol bilerek dar: ödüllendirici geçmişe dayalı rozetleri basamaz. Ele geçirilmiş
bir ödüllendirici sahte teslimat geçmişi uyduramaz.

---

## 3. Kazanma koşulları

| Rozet | Koşul |
|---|---|
| `FirstDelivery` | ≥ 1 tamamlanmış teslimat |
| `TenDeliveries` | ≥ 10 |
| `FiftyDeliveries` | ≥ 50 |
| `HundredDeliveries` | ≥ 100 |
| `FiveHundredDeliveries` | ≥ 500 |
| `ZeroLostDispute` | `disputesLost == 0` **ve** `disputesWon > 0` |
| `VerifiedCourier` | Doğrulama seviyesi ≥ C1 |
| `TrustedCourier` | Doğrulama seviyesi == C2 |
| `TopTenWeekly` | Zincir dışı sıralama (verilir) |

**"Sıfır kayıp" bir şey ifade etmeli.** Hiç ihtilafa düşmemiş bir kurye ihtilaflar
hakkında hiçbir şey kanıtlamamıştır; bu yüzden rozet en az bir kazanılmış ihtilaf
ister.

---

## 4. Devredilemezlik (ERC-5192)

Tek bir kontrol noktası var: OpenZeppelin 5.x'te her ERC-721 hareketi `_update`
üzerinden geçer. Basım (`from == 0`) serbest, **diğer her şey** — transfer,
`safeTransferFrom`, yakma — reddedilir. Tek tek giriş noktalarını değil bu ortak
noktayı override etmek, ileriki bir OZ sürümünün kuralı atlayan yeni bir yol eklemesini
imkânsız kılar.

`approve` ve `setApprovalForAll` de reddedilir: hareket edemeyen bir token için
onay anlamsızdır, cüzdanda canlı bir yetki göstermek yanıltıcı olur.

`supportsInterface` hem ERC-721 hem **ERC-5192** için `true` döner. Cüzdanlar ve
explorer'lar token'ı devredilemez olarak göstermek için buna bakar; kendini
tanıtmadan sadece transfer'de revert eden bir rozet, soulbound değil **bozuk** bir
NFT gibi görünür.

---

## 5. Rozetler teminatı azaltmaz

sec. 24 doğrulama rozetlerinin uygunluğu etkilemesine izin veriyor ama teminatı
**ortadan kaldırmasını yasaklıyor**.

Bu kontratta hiç kapsam mantığı yok ve kapsamı hesaplayan hiçbir şey buraya
referans vermiyor: rozet, registry'nin doğrulama seviyesinin bir **görüntüsü**,
ona bir **girdi** değil. İlişki tek yönlü.

Test bunu tam olarak sabitliyor: `test_HoldingEveryBadgeChangesNoCollateral` —
sec. 24 listesindeki **dokuz rozetin tamamını** taşıyan bir kurye, hiç rozeti
olmayanla birebir aynı teminatı yatırmak zorunda; temel depozito, uygunluk ve
rezerve edilmiş teminat değişmiyor.

---

## 6. Metadata

`tokenURI` = `<baseURI><badgeType>.json` — token başına değil **rozet türü
başına** bir belge. Her `FirstDelivery` rozeti aynı rozettir; binlerce özdeş JSON
üretmek, okuyucusu olmayan bir barındırma faturasıdır.

`baseURI` `CONFIG_ADMIN_ROLE` ile güncellenir. Metadata barındırmak **backend'in
yeni bir sorumluluğudur**.

---

## 7. Test kapsamı

20 birim/fuzz testi. Mutasyon testi:

| Kaldırılan | Kırılan test |
|---|---|
| Soulbound kilidi | 4 |
| `approve` kilidi | 2 |
| ERC-5192 bildirimi | 2 |
| Duplicate kontrolü | 2 |
| Haftalık rozetin claim'e kapalı olması | 2 |
| `ZeroLostDispute`'un ihtilaf şartı | 2 |

Ayrıca: her transfer giriş noktası tek tek denenir, fuzz ile rastgele alıcıya
transfer denenir, olmayan token için `locked` revert eder, talep eden ile alıcının
farklı olabildiği doğrulanır.
