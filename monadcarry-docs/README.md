# MonadCarry — Crowdsourced Kurye Pazaryeri

Monad blockchain üzerinde çalışan, merkezi olmayan bir kurye pazaryeri. Kuryeler ve göndericiler akıllı sözleşmeler aracılığıyla güvenli bir şekilde eşleşir; leaderboard ile rekabet, token + NFT rozet ile ödüllendirme yapılır.

## Ana Akış Özeti

```
[Müşteri] → Talep oluştur → Escrow'a para yatır
   ↓
[Kuryeler] → Teklif ver (token miktarı + puan göster)
   ↓
[Müşteri] → Kuryeyi seç (token fiyatı ve puana göre)
   ↓
[Kurye] → Ürünü alır → Müşteri onayı (Alındı)
   ↓
[Kurye] → Teslim eder → Alıcı onayı (Teslim)
   ↓
[Akıllı Kontrat] → Ödemeyi kuryeye aktar
   ↓
[Müşteri] → Puan ver → RatingSystem güncellenir
   ↓
[Leaderboard] → Hesaplama yap → Haftalık/aylık token ödülleri dağıt
```

## Dosya Yapısı

### Akış Dokümanları (`/flows`)

Her dosya, akışın bir adımını tanımlar. Claude Code ile geliştirirken sırayla işlenmelidir.

| Sıra | Dosya | Açıklama |
|------|-------|----------|
| 01 | [`01-talep-olusturma.md`](./flows/01-talep-olusturma.md) | Müşteri talep oluşturur, escrow'a ödeme kilitlenir |
| 02 | [`02-kurye-teklif.md`](./flows/02-kurye-teklif.md) | Kuryeler teklif verir, teminat bloke edilir |
| 03 | [`03-kurye-secimi.md`](./flows/03-kurye-secimi.md) | Müşteri kuryeyi seçer, diğerlerinin teminatı iade edilir |
| 04 | [`04-alis-onayi.md`](./flows/04-alis-onayi.md) | Kurye ürünü alır, QR kod ile pickup onayı |
| 05 | [`05-teslimat-onayi.md`](./flows/05-teslimat-onayi.md) | Alıcı teslim alır, onay verir |
| 06 | [`06-odeme-aktarimi.md`](./flows/06-odeme-aktarimi.md) | Escrow serbest bırakılır, kurye ödenir |
| 07 | [`07-puanlama.md`](./flows/07-puanlama.md) | Müşteri puan verir, rating sistemi güncellenir |
| 08 | [`08-leaderboard-odul.md`](./flows/08-leaderboard-odul.md) | Leaderboard hesaplanır, ödüller dağıtılır |

### Destekleyici Sistemler (`/systems`)

| Dosya | Açıklama |
|-------|----------|
| [`dispute-resolution.md`](./systems/dispute-resolution.md) | Anlaşmazlık çözüm mekanizması |
| [`rating-system.md`](./systems/rating-system.md) | Puanlama ve itibar sistemi detayları |
| [`leaderboard-formulas.md`](./systems/leaderboard-formulas.md) | Leaderboard skor formülleri |
| [`tokenomics.md`](./systems/tokenomics.md) | Token ekonomisi ve NFT rozet sistemi |

### Akıllı Sözleşmeler (`/contracts`)

| Dosya | Açıklama |
|-------|----------|
| [`DeliveryEscrow.md`](./contracts/DeliveryEscrow.md) | Escrow ve teslimat kontratı spesifikasyonu |
| [`Leaderboard.md`](./contracts/Leaderboard.md) | Leaderboard kontratı spesifikasyonu |
| [`RewardDistributor.md`](./contracts/RewardDistributor.md) | Ödül dağıtım kontratı spesifikasyonu |
| [`ReputationBadge.md`](./contracts/ReputationBadge.md) | NFT rozet (soulbound) kontratı |

## Geliştirme Sırası (Claude Code için)

1. **Faz 1 — Çekirdek**: `01` → `02` → `03` → `04` → `05` → `06` (teslimat döngüsü)
2. **Faz 2 — Güven**: `07` + `rating-system.md` + `dispute-resolution.md`
3. **Faz 3 — Rekabet**: `08` + `leaderboard-formulas.md` + `tokenomics.md`
4. **Faz 4 — Kontratlar**: `/contracts` altındaki tüm Solidity implementasyonları

## Teknoloji Stack

- **Blockchain**: Monad (yüksek TPS, EVM uyumlu)
- **Akıllı sözleşmeler**: Solidity 0.8.x
- **Ödeme**: USDC (stablecoin) + platform token (MCRY)
- **NFT**: ERC721 soulbound rozet
- **Backend**: Node.js/Go oracle servisi
- **Frontend**: React Native (mobil) + Next.js (web panel)
