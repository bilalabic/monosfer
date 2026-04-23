# 07 — Puanlama (Rating & Review)

## Amaç

Teslimat tamamlandıktan sonra müşteri kuryeyi 1-5 yıldız arasında puanlar. Bu puan on-chain kaydedilir ve kuryenin itibarını belirler. İtibar; leaderboard skorunu, gelecekte tercih edilmesini ve belirli rozetleri etkiler.

## Akış

```
Ödeme aktarıldı (06'dan)
   ↓
Müşteri uygulamasında puanlama ekranı açılır
   ↓
Müşteri 1-5 yıldız seçer (+ opsiyonel yorum)
   ↓
Akıllı kontrat: submitRating()
   ↓
Kuryenin ortalama puanı güncellenir
   ↓
Toplam değerlendirme sayısı artar
   ↓
Event emit edilir
   ↓
08-leaderboard tetiklenir
```

## Puanlama Zorunluluğu

- Müşteri **24 saat içinde** puan vermezse: otomatik 5 yıldız (varsayılan).
- Sürekli otomatik puan veren müşteriler tespit edilip rozetsel indirime açılabilir.
- İlk 5 teslimatında puan zorunlu; yoksa yeni talep oluşturamaz.

## Puanlama Kriterleri

Müşteri tek bir genel yıldız verir, ama uygulama alt kategoriler sorar (opsiyonel):

| Kategori | Ağırlık |
|----------|---------|
| Hız | Otomatik — `pickup` ve `delivery` zamanına göre |
| Davranış | Müşteri kendisi verir |
| Paket durumu | Müşteri kendisi verir |
| İletişim | Müşteri kendisi verir |

Alt kategoriler off-chain detay için; on-chain sadece genel yıldız kaydedilir.

## Akıllı Kontrat Fonksiyonu

```solidity
function submitRating(
    uint256 requestId,
    uint8 stars,
    bytes32 reviewIpfsHash // Opsiyonel yorum metni
) external {
    DeliveryRequest storage req = requests[requestId];
    require(req.status == Status.Completed, "Not completed");
    require(msg.sender == req.customer, "Not customer");
    require(!req.rated, "Already rated");
    require(stars >= 1 && stars <= 5, "Invalid stars");

    req.rated = true;
    req.rating = stars;

    // Kurye istatistiklerini güncelle
    CourierStats storage stats = courierStats[req.acceptedCourier];
    stats.totalDeliveries += 1;
    stats.totalRatingSum += stars;
    stats.lastRatingAt = block.timestamp;

    if (stars == 5) stats.fiveStarCount += 1;
    if (stars <= 2) stats.lowRatingCount += 1;

    if (reviewIpfsHash != bytes32(0)) {
        reviewHashes[requestId] = reviewIpfsHash;
    }

    emit RatingSubmitted(requestId, req.acceptedCourier, stars);

    // Leaderboard güncellemesi (08'de detay)
    leaderboard.updateCourierScore(req.acceptedCourier);
}
```

## Kurye İstatistik Struct'ı

```solidity
struct CourierStats {
    uint32 totalDeliveries;
    uint32 totalRatingSum;       // Ortalama: totalRatingSum / totalDeliveries
    uint32 fiveStarCount;
    uint32 lowRatingCount;       // 1-2 yıldız
    uint32 onTimeCount;
    uint32 lateCount;
    uint32 cancelCount;
    uint64 lastRatingAt;
    uint64 joinedAt;
}
```

## Ortalama Puan Hesaplama

```solidity
function getAverageRating(address courier) public view returns (uint256) {
    CourierStats memory stats = courierStats[courier];
    if (stats.totalDeliveries == 0) return 0;
    return (stats.totalRatingSum * 100) / stats.totalDeliveries; // 2 ondalık
}
```

Sonuç `485` gibi — yani **4.85 yıldız** (100 ile çarpım, ondalık için).

## Yorum Sistemi (IPFS)

Yorumlar on-chain'de büyük yer kaplar — bu yüzden IPFS'te tutulur:

```json
{
  "requestId": "0x1a2b3c...",
  "customer": "0xabc...",
  "courier": "0xdef...",
  "rating": 5,
  "text": "Çok hızlı ve nazikti, teşekkürler!",
  "timestamp": 1699999999,
  "categories": {
    "speed": 5,
    "behavior": 5,
    "packageCondition": 5,
    "communication": 4
  }
}
```

On-chain sadece IPFS hash'i kaydedilir. Frontend, IPFS'ten çeker ve gösterir.

## Abuse Koruması

- **Tek seferlik puanlama**: Her talep için sadece bir kere puan verilebilir (`rated` flag).
- **Müşteri-kurye eşleşmesi**: Sadece teslimatın müşterisi puan verebilir.
- **Puan manipülasyonu**: Aynı müşterinin aynı kuryeden aşırı fazla talep oluşturması tespit edilir (fraud detection off-chain).
- **Otomatik düşük puan**: Müşteri belirli bir eşiğin altında puan verirse (örn. 2 ve altı), zorunlu yorum istenir.

## Frontend — Puanlama Ekranı

```
┌─────────────────────────────────┐
│  Ahmet K.'yı puanlayın           │
├─────────────────────────────────┤
│                                  │
│    ⭐ ⭐ ⭐ ⭐ ⭐                 │
│    (puan seçmek için dokunun)    │
│                                  │
│  Detaylar (opsiyonel):           │
│  ☐ Hızlıydı                     │
│  ☐ Kibar davrandı                │
│  ☐ Paket sağlam geldi            │
│  ☐ İyi iletişim kurdu            │
│                                  │
│  Yorum:                          │
│  ┌────────────────────────┐     │
│  │                         │     │
│  └────────────────────────┘     │
│                                  │
│  [ Puanı Gönder ]                │
└─────────────────────────────────┘
```

## Kuryenin Müşteriyi Puanlaması (İleride)

v2'de çift taraflı puanlama:
- Kurye de müşteriyi 1-5 arası puanlar
- Kötü müşteriler (örn. yanlış adres veren, kaba davranan) filtrelenebilir
- Müşteri puanı düşükse kurye uyarı alır, teklif vermeden önce düşünür

## Emit Edilecek Event'ler

```solidity
event RatingSubmitted(
    uint256 indexed requestId,
    address indexed courier,
    uint8 stars
);
event ReviewAdded(
    uint256 indexed requestId,
    bytes32 ipfsHash
);
event AutomaticRating(uint256 indexed requestId, uint8 defaultStars);
```

## Edge Case'ler

- **Müşteri 24 saat içinde puan vermezse**: Cron job / keeper, varsayılan 5 yıldız uygular.
- **Anlaşmazlık sürüyorsa**: Puan verme donar, dispute çözülene kadar.
- **Müşteri çifte puan verirse**: `rated` flag ile engellenir.
- **Yeni kurye (hiç puanı yok)**: Ortalama gösterimi "Yeni kurye" olarak yapılır, teklif kısıtlaması uygulanmaz (ilk 5 teslimat için).

## Geliştirme Checklist

- [ ] `submitRating()` kontrat fonksiyonu
- [ ] `CourierStats` struct + güncellemeler
- [ ] `getAverageRating()` view fonksiyonu
- [ ] 24 saat otomatik 5-yıldız keeper (off-chain)
- [ ] IPFS yorum yükleme
- [ ] Puanlama UI (yıldız animasyonu)
- [ ] Kategori alt seçimleri
- [ ] Kurye profil sayfasında yorum listesi
- [ ] Abuse detection (off-chain service)
- [ ] Unit test — ortalama hesaplama

## Sonraki Adım

→ [`08-leaderboard-odul.md`](./08-leaderboard-odul.md) — Leaderboard hesaplanıp ödüller dağıtılacak.
