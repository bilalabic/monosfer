# 06 — Ödeme Aktarımı

## Amaç

Teslimat onaylandığı anda escrow'daki ücret kuryeye otomatik olarak aktarılır. Platform komisyonu düşülür, ödül havuzuna pay ayrılır.

## Akış

```
Teslimat onaylandı (05'ten)
   ↓
Akıllı kontrat: _releasePayment() (internal)
   ↓
Escrow'dan ücret çekilir
   ↓
Platform komisyonu düşülür (%3)
   ↓
Ödül havuzu payı ayrılır (%5)
   ↓
Kuryenin cüzdanına kalan aktarılır
   ↓
Teminat (BID_DEPOSIT) iade edilir
   ↓
Event emit edilir
```

## Ödeme Dağılımı

Teslimat ücreti **100 MCRY** örneği üzerinden:

| Alıcı | % | Miktar | Açıklama |
|-------|---|--------|----------|
| Kurye | 92% | 92 MCRY | Net kazanç |
| Platform | 3% | 3 MCRY | İşletim masrafları |
| Ödül havuzu | 5% | 5 MCRY | Leaderboard ödülleri (08) |

## Akıllı Kontrat Fonksiyonu

```solidity
function _releasePayment(uint256 requestId) internal {
    DeliveryRequest storage req = requests[requestId];
    require(req.status == Status.Delivered, "Not delivered");
    require(!req.paymentReleased, "Already paid");

    uint256 totalAmount = req.acceptedAmount;
    uint256 platformFee = (totalAmount * PLATFORM_FEE_BPS) / 10000; // 300 = 3%
    uint256 rewardPoolFee = (totalAmount * REWARD_POOL_BPS) / 10000; // 500 = 5%
    uint256 courierNet = totalAmount - platformFee - rewardPoolFee;

    // Transferler
    token.transfer(req.acceptedCourier, courierNet);
    token.transfer(platformTreasury, platformFee);
    token.transfer(rewardPool, rewardPoolFee);

    // Kurye teminatını iade et
    uint256 deposit = lockedBidDeposits[requestId][req.acceptedCourier];
    if (deposit > 0) {
        courierStake[req.acceptedCourier] += deposit;
        lockedBidDeposits[requestId][req.acceptedCourier] = 0;
    }

    req.paymentReleased = true;
    req.status = Status.Completed;

    emit PaymentReleased(
        requestId,
        req.acceptedCourier,
        courierNet,
        platformFee,
        rewardPoolFee
    );

    // Leaderboard güncelle (08'de detay)
    leaderboard.recordDelivery(
        req.acceptedCourier,
        req.customer,
        totalAmount,
        req.deliveredAt - req.pickupAt,
        req.urgency
    );
}
```

## Gecikme Cezası

Kurye zamanında teslim etmediyse `courierNet` azaltılır:

```solidity
function _calculateCourierNet(
    uint256 baseAmount,
    uint256 expectedDuration,
    uint256 actualDuration
) internal pure returns (uint256) {
    if (actualDuration <= expectedDuration) {
        return baseAmount;
    }

    uint256 delay = actualDuration - expectedDuration;
    uint256 penaltyBps;

    if (delay <= 15 minutes) penaltyBps = 500;      // %5 ceza
    else if (delay <= 30 minutes) penaltyBps = 1000; // %10 ceza
    else if (delay <= 1 hours) penaltyBps = 2000;    // %20 ceza
    else penaltyBps = 3000;                           // %30 ceza

    uint256 penalty = (baseAmount * penaltyBps) / 10000;
    return baseAmount - penalty;
}
```

Kesilen ceza miktarı:
- %50'si müşteriye iade
- %50'si ödül havuzuna

## Stablecoin Desteği (İleride)

MVP'de MCRY token kullanılır. v2'de USDC ile ödeme opsiyonu:

```solidity
enum PaymentToken { MCRY, USDC }

struct DeliveryRequest {
    // ...
    PaymentToken paymentToken;
}
```

USDC ile ödeme yapanlara cashback olarak MCRY token verilir (işlem başına küçük bir miktar).

## Kurye Bakiyesi

Kurye, cüzdanındaki token'ları:
- Başka bir teslimat için teminat olarak kullanabilir
- Stablecoin'e çevirebilir (DEX entegrasyonu)
- Platform üzerinden withdraw edebilir (fiyat oracle ile TL/USD dönüşümü)

## Emit Edilecek Event'ler

```solidity
event PaymentReleased(
    uint256 indexed requestId,
    address indexed courier,
    uint256 courierAmount,
    uint256 platformFee,
    uint256 rewardPoolFee
);
event LatePenaltyApplied(
    uint256 indexed requestId,
    uint256 penaltyAmount,
    uint256 delaySeconds
);
```

## Frontend — Kurye Ekranı (Ödeme Alındı)

```
┌─────────────────────────────────┐
│  💰 Ödeme Alındı!                │
├─────────────────────────────────┤
│  Brüt ücret:     100 MCRY        │
│  Platform fee:     -3 MCRY       │
│  Ödül havuzu:      -5 MCRY       │
│  ────────────────────────        │
│  Net kazanç:       92 MCRY       │
│                                  │
│  Toplam bakiye: 1,247 MCRY      │
│                                  │
│  [ Yeni Görev Ara ]              │
└─────────────────────────────────┘
```

## Edge Case'ler

- **Çifte ödeme riski**: `paymentReleased` bayrağı + reentrancy guard.
- **Token transferi başarısız olursa**: `try/catch` ile güvenli transfer, hata durumunda manual `withdraw()` fonksiyonu.
- **Platform treasury veya reward pool adresi değişirse**: Sadece owner/governance ile değiştirilebilir, timelock ile.
- **Kurye cüzdanı blacklist'te**: Token sözleşmesi reddedebilir; bu durumda ödeme escrow'da kalır, admin müdahalesi gerekir.

## Güvenlik

- `ReentrancyGuard` modifier kullan
- `SafeERC20` wrapper ile transfer
- Ödeme dağılımı toplamı = 100% kontrolü (test'te)
- Formal verification (ileride, v2)

## Geliştirme Checklist

- [ ] `_releasePayment()` internal fonksiyon
- [ ] Gecikme cezası hesaplama
- [ ] `SafeERC20` transferleri
- [ ] `ReentrancyGuard` uygulaması
- [ ] Platform treasury + reward pool adresleri (değiştirilebilir)
- [ ] Event emisyonu
- [ ] Leaderboard tetiklemesi (08'e bağlan)
- [ ] Kurye bakiye UI
- [ ] Unit test — ödeme dağılımı matematiği
- [ ] Fork test — Monad testnet üzerinde gerçek gas ölçümü

## Sonraki Adım

→ [`07-puanlama.md`](./07-puanlama.md) — Müşteri puan verecek, rating sistemi güncellenecek.
