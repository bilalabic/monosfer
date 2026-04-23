# 02 — Kurye Teklifleri

## Amaç

Aktif ve coğrafi olarak yakın kuryeler, müşterinin talebini görür ve her biri kendi ücretini belirleyerek teklif verir. Her teklif için kuryeden küçük bir teminat bloke edilir — bu, sahte teklifleri ve "ben yokum" senaryolarını önler.

## Akış

```
Yeni talep broadcast edilir
   ↓
Coğrafi filtre: 5 km çevredeki aktif kuryeler bildirim alır
   ↓
Kurye talebi inceler (mesafe, paket tipi, aciliyet)
   ↓
Kurye teklif ücretini belirler (örn. 7 MCRY token)
   ↓
Akıllı kontrat: submitBid()
   ↓
Kurye cüzdanından 1 MCRY teminat bloke edilir
   ↓
Teklif listeye eklenir, müşteri anlık görür
```

## Teklif Girdileri

| Alan | Tip | Açıklama |
|------|-----|----------|
| `requestId` | uint256 | Teklif verilen talebin ID'si |
| `bidAmount` | uint256 | Kuryenin istediği ücret (token) |
| `estimatedMinutes` | uint16 | Tahmini teslimat süresi |
| `courierLat`, `courierLng` | int32 | Kuryenin o anki konumu (× 1e6 encoded) |

## Akıllı Kontrat Fonksiyonu

```solidity
function submitBid(
    uint256 requestId,
    uint256 bidAmount,
    uint16 estimatedMinutes,
    int32 courierLat,
    int32 courierLng
) external {
    require(bids[requestId][msg.sender].amount == 0, "Already bid");
    require(bidAmount <= requests[requestId].maxBudget, "Over budget");
    require(courierStake[msg.sender] >= BID_DEPOSIT, "Insufficient stake");

    // Teminat bloke et
    courierStake[msg.sender] -= BID_DEPOSIT;
    lockedBidDeposits[requestId][msg.sender] = BID_DEPOSIT;

    bids[requestId][msg.sender] = Bid({
        amount: bidAmount,
        estimatedMinutes: estimatedMinutes,
        timestamp: block.timestamp
    });

    bidderList[requestId].push(msg.sender);
    emit BidSubmitted(requestId, msg.sender, bidAmount);
}
```

## Teminat (Bid Deposit) Mantığı

- Sabit miktar: `BID_DEPOSIT = 1 MCRY` (veya token'ın %10'u, hangisi büyükse).
- Kurye sistemde ilk kayıt olurken genel bir stake (örn. 10 MCRY) yatırır.
- Her teklifte bu stake'ten bir miktar bloke edilir.
- Seçilmeyen kuryelerin teminatı talep kapandığında iade edilir.
- Seçilen kuryenin teminatı da iade edilir (ödemeyi escrow'dan alacağı için).

## Uygun Kurye Filtreleme Kriterleri

Bir kuryenin teklif verebilmesi için:

1. **Minimum stake**: 10 MCRY bloke etmiş olmalı.
2. **Aktif durum**: Uygulamada `online` olmalı.
3. **Coğrafi yakınlık**: Pickup noktasına 5 km içinde olmalı.
4. **Puan eşiği**: Minimum 3.0/5.0 ortalama puana sahip olmalı (ilk 5 teslimat dışında).
5. **Aktif teklif limiti**: Aynı anda maksimum 3 aktif teklifi olabilir.

## Frontend — Kurye Ekranı

```
┌─────────────────────────────────┐
│  Yeni Talep! (2.3 km uzaklıkta) │
├─────────────────────────────────┤
│  📦 Küçük paket                  │
│  📍 Ulus → Çankaya (4.1 km)     │
│  ⚡ Express (1 saat)             │
│  💰 Üst limit: 15 MCRY          │
├─────────────────────────────────┤
│  Teklif Ver:                     │
│  [ 8 MCRY ]  [ ~25 dk ]          │
│                                  │
│  [ Teklifi Gönder ] (1 MCRY bloke) │
└─────────────────────────────────┘
```

## Frontend — Müşteri Ekranı (Canlı)

```
┌─────────────────────────────────┐
│  Teklifler (3)                   │
├─────────────────────────────────┤
│  👤 Ahmet K.  ⭐ 4.8 (127 teslimat) │
│     7 MCRY · ~22 dk              │
│     [ Seç ]                      │
├─────────────────────────────────┤
│  👤 Mehmet Y. ⭐ 4.5 (43 teslimat)  │
│     5 MCRY · ~30 dk              │
│     [ Seç ]                      │
├─────────────────────────────────┤
│  👤 Elif S.   ⭐ 4.9 (250 teslimat) │
│     9 MCRY · ~20 dk              │
│     [ Seç ]                      │
└─────────────────────────────────┘
```

## Süre Limiti

- Teklif toplama süresi: **5 dakika** (aciliyet `instant` ise **2 dakika**).
- Süre dolunca müşteri mevcut tekliflerden birini seçmek zorunda, aksi halde talep iptal olur.

## Emit Edilecek Event'ler

```solidity
event BidSubmitted(uint256 indexed requestId, address indexed courier, uint256 amount);
event BidWithdrawn(uint256 indexed requestId, address indexed courier);
```

## Edge Case'ler

- **Kurye teklif verip kaybolursa**: 30 saniye içinde kurye heartbeat göndermezse teklifi otomatik çekilir, teminat iade edilir ama küçük bir itibar cezası uygulanır.
- **Aynı kuryeden birden fazla teklif**: Engellenmeli, sadece en son teklif geçerli.
- **Bid amount == 0**: Reddedilmeli.

## Geliştirme Checklist

- [ ] `Bid` struct ve mapping'ler
- [ ] `submitBid()` + validasyon
- [ ] `withdrawBid()` (teklifi geri çekme)
- [ ] Stake yönetimi (`depositStake()`, `withdrawStake()`)
- [ ] Event emisyonu
- [ ] Coğrafi filtreleme (off-chain service)
- [ ] Push notification sistemi
- [ ] Kurye uygulamasında teklif ekranı
- [ ] Müşteri uygulamasında canlı teklif listesi (WebSocket / polling)

## Sonraki Adım

→ [`03-kurye-secimi.md`](./03-kurye-secimi.md) — Müşteri kuryeyi seçecek.
