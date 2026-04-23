# 03 — Kurye Seçimi

## Amaç

Müşteri, gelen teklifler arasından birini seçer. Seçilen kuryenin ücreti escrow'da kilitli kalır, diğer kuryelerin teminatı iade edilir. Sözleşme artık değiştirilemez duruma geçer.

## Akış

```
Müşteri teklifleri inceler
   ↓
Puan, ücret, tahmini süreyi karşılaştırır
   ↓
Bir kuryeyi seçer → acceptBid()
   ↓
Seçilen kuryenin ücreti escrow'dan onaylanır
   ↓
Diğer kuryelerin teminatı iade edilir
   ↓
Sözleşme "Accepted" durumuna geçer
   ↓
Kurye alış adresine yönelir
```

## Seçim Kriterleri (UI'da gösterilir)

| Kriter | Ağırlık | Açıklama |
|--------|---------|----------|
| Ortalama puan | Yüksek | 5 yıldız üzerinden geçmiş teslimat puanı |
| Teslimat sayısı | Orta | Deneyim göstergesi |
| Teklif ücreti | Yüksek | Düşük fiyat cazip ama kalite riski |
| Tahmini süre | Orta | Kuryenin geçmiş ortalamasıyla karşılaştır |
| Mesafe | Düşük | Kurye ne kadar yakın |
| Aktiflik | Düşük | Son 7 günde aktif mi |

## Akıllı Kontrat Fonksiyonu

```solidity
function acceptBid(uint256 requestId, address selectedCourier) external {
    require(requests[requestId].customer == msg.sender, "Not your request");
    require(requests[requestId].status == Status.OpenForBids, "Invalid state");

    Bid memory bid = bids[requestId][selectedCourier];
    require(bid.amount > 0, "Bid not found");

    uint256 maxBudget = requests[requestId].maxBudget;
    uint256 refund = maxBudget - bid.amount;

    // Fazla tutarı müşteriye iade et
    if (refund > 0) {
        escrowBalance[requestId] -= refund;
        token.transfer(msg.sender, refund);
    }

    // Sözleşmeyi güncelle
    requests[requestId].acceptedCourier = selectedCourier;
    requests[requestId].acceptedAmount = bid.amount;
    requests[requestId].status = Status.Accepted;
    requests[requestId].acceptedAt = block.timestamp;

    // Diğer kuryelerin teminatını iade et
    _refundOtherBidders(requestId, selectedCourier);

    emit CourierSelected(requestId, selectedCourier, bid.amount);
}
```

## Teminat İadesi

```solidity
function _refundOtherBidders(uint256 requestId, address winner) internal {
    address[] memory bidders = bidderList[requestId];
    for (uint256 i = 0; i < bidders.length; i++) {
        if (bidders[i] != winner) {
            uint256 deposit = lockedBidDeposits[requestId][bidders[i]];
            if (deposit > 0) {
                courierStake[bidders[i]] += deposit;
                lockedBidDeposits[requestId][bidders[i]] = 0;
            }
        }
    }
}
```

**Gas optimizasyonu:** Eğer kurye listesi uzunsa (>50), iade işlemi iki fazlı yapılır:
1. `acceptBid()` sadece seçilen kuryeyi işaretler.
2. `claimRefund()` — her kurye kendi teminatını geri çeker (pull pattern).

## Sözleşme Durum Geçişleri

```
OpenForBids → Accepted → InTransit → Delivered → Completed
                  ↓                       ↓
               Cancelled              Disputed
```

Bu noktada `Accepted` durumuna geçilir ve sözleşme **değiştirilemez** olur. İptal sadece jüri / anlaşmazlık süreci ile mümkündür.

## UI — Seçim Ekranı

Müşteri her kuryeye tıkladığında detaylı kart açılmalı:

```
┌──────────────────────────────────────┐
│  Ahmet K.                      ⭐ 4.8 │
├──────────────────────────────────────┤
│  📊 İstatistikler                     │
│     • 127 başarılı teslimat          │
│     • %96 zamanında teslimat         │
│     • Ort. teslim süresi: 24 dk      │
│     • Üyelik: 6 ay                   │
│                                       │
│  🏅 Rozetler                          │
│     [100 Club] [Hız Şampiyonu]       │
│                                       │
│  💬 Son yorumlar                      │
│     "Çok hızlı ve nazikti" (5★)      │
│     "Paketi özenle taşıdı" (5★)      │
│                                       │
│  💰 Bu teklif: 7 MCRY                │
│  ⏱  Tahmini: ~22 dk                  │
├──────────────────────────────────────┤
│  [ Bu Kuryeyi Seç ]                  │
└──────────────────────────────────────┘
```

## Emit Edilecek Event'ler

```solidity
event CourierSelected(
    uint256 indexed requestId,
    address indexed courier,
    uint256 amount
);
event BidDepositRefunded(
    uint256 indexed requestId,
    address indexed courier,
    uint256 amount
);
```

## Edge Case'ler

- **Seçim yapmadan süre dolarsa**: Otomatik olarak en yüksek puanlı kurye seçilir (opt-out edilebilir).
- **Müşteri seçilen kuryeyi iptal etmek isterse**: Anlaşmazlık mekanizması devreye girer, direkt iptal yok.
- **Kurye bu arada offline olursa**: Seçim yapıldığı anda kurye hala aktif olmalı; değilse sıradaki yüksek puanlı kuryeye geçer.

## Geliştirme Checklist

- [ ] `acceptBid()` implementasyonu
- [ ] Teminat iadesi (push veya pull pattern)
- [ ] Fazla tutarı iade etme
- [ ] Sözleşme durum geçişi
- [ ] Event emisyonu
- [ ] Seçim UI — filtreler, sıralama
- [ ] Kurye detay kartı
- [ ] Seçilmeyen kuryelere bildirim
- [ ] Auto-select fallback (süre dolduğunda)
- [ ] Unit test — farklı kurye sayılarıyla gas ölçümü

## Sonraki Adım

→ [`04-alis-onayi.md`](./04-alis-onayi.md) — Kurye ürünü alacak ve QR ile pickup onayı yapılacak.
