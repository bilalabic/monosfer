# Puanlama Sistemi (Rating & Reputation)

## Amaç

Platformda güven oluşturmanın merkezinde puanlama var. Bu doküman, 07-puanlama akışının detaylı teknik spesifikasyonu ve itibar sisteminin matematiğidir.

## Ortalama Puan Hesaplama

### Ağırlıklı Ortalama (Weighted Average)

Yeni gelen puanlar son puanlardan daha fazla ağırlık taşır:

```
Ağırlıklı Ortalama = Σ(puan_i × ağırlık_i) / Σ(ağırlık_i)

ağırlık_i = 1 / (1 + (günTeknikEskiligi / 90))
```

Yani 90 gün önceki puan, bugünkünün yarısı kadar etkili.

### Neden Zaman Ağırlıklı?

Bir kurye 6 ay önce çok iyiydi ama son 1 aydır kötü performans gösteriyorsa, müşteri bunu görmeli. Basit ortalama bunu gizler.

## Wilson Lower Bound Score

Reddit/Amazon gibi platformların kullandığı yöntem. Az puana sahip kuryelerin yanıltıcı "5.0 puan" göstermesini engeller:

```
WilsonScore = (p + z²/2n − z·√((p(1-p) + z²/4n) / n)) / (1 + z²/n)

p = pozitif puan oranı (4-5 yıldız)
n = toplam puan sayısı
z = 1.96 (%95 güven aralığı)
```

### Örnek

- Kurye A: 2 puan, ikisi de 5 yıldız → basit ort. 5.0
- Kurye B: 100 puan, ortalaması 4.8

Wilson score:
- A: ~0.35 (güvensiz)
- B: ~0.82 (güvenilir)

Wilson score sıralamada kullanılır, ama UI'da basit ortalama gösterilir.

## Puan Eşikleri

| Puan | Anlam | Sonuç |
|------|-------|-------|
| 4.5+ | Mükemmel | Teklif önceliği, bonus rozetler |
| 4.0 – 4.5 | İyi | Normal işlem |
| 3.5 – 4.0 | Ortalama | Uyarı, eğitim önerisi |
| 3.0 – 3.5 | Zayıf | Teklif kısıtlaması (maksimum 3/gün) |
| 3.0 altı | Risk | Hesap askıya, manuel inceleme |

## İlk 5 Teslimat Politikası

Yeni kuryelerin ortalaması henüz anlamlı değil. İlk 5 teslimat:

- "Yeni kurye" etiketi gösterilir
- Puan düşüklüğü kısıtlama yaratmaz
- 5. teslimat sonunda normal sisteme geçer

## Düşük Puan Flow

Müşteri 2 veya daha düşük puan verirse:

```
Müşteri 1-2 yıldız seçer
   ↓
Zorunlu kategori seçimi:
  ☐ Geç geldi
  ☐ Kaba davrandı
  ☐ Paketi hor kullandı
  ☐ Adres değişikliği istedi
  ☐ Ek ücret istedi
  ☐ Diğer
   ↓
Zorunlu yorum (min 20 karakter)
   ↓
Platform tarafına bildirim gider
   ↓
Kurye de kendi tarafını anlatabilir (24s içinde)
   ↓
Sistematik sorun varsa platform müdahale eder
```

## Puan Geri Alma (Contestable Ratings)

Kurye, haksız bulduğu puanı 48 saat içinde itiraz edebilir:

```solidity
function contestRating(
    uint256 requestId,
    bytes32 evidenceIpfsHash,
    string calldata explanation
) external {
    require(msg.sender == requests[requestId].acceptedCourier);
    require(block.timestamp <= requests[requestId].ratedAt + 48 hours);
    
    contestedRatings[requestId] = Contest({
        evidence: evidenceIpfsHash,
        timestamp: block.timestamp,
        status: ContestStatus.Open
    });
    emit RatingContested(requestId);
}
```

Eğer platform moderasyon (veya v2'de jüri) haklı bulursa:
- Puan kuryenin ortalamasından çıkarılır
- Müşteriye uyarı

## Gizli Puanlama

Müşteri kuryenin kim olduğunu görmeden genel puan verir (isteğe bağlı):

- Ad, fotoğraf gizli
- Sadece "Kurye A" olarak gösterilir
- Önyargıyı azaltır

v2 için feature.

## İtibar Skoru (Composite Reputation)

Sadece ortalama puan değil, multi-factor:

```
İtibar = (
    OrtalamaPuan      × 0.40
  + ZamanındaOranı   × 0.25
  + TamamlamaOranı   × 0.15
  + TecrubeSkoru      × 0.10
  + ÇeşitlilikSkoru  × 0.10
)

TecrubeSkoru = min(log2(toplamTeslimat) / 10, 1.0)
ÇeşitlilikSkoru = farklıMüşteriSayısı / toplamTeslimat
```

ÇeşitlilikSkoru fake rating'i engeller — aynı müşteriden sürekli 5 alan kurye düşük çeşitlilik alır.

## Anti-Fraud Pattern Tespiti

Off-chain ML modeli şunları izler:

| Pattern | Eylem |
|---------|-------|
| Aynı IP'den birden çok hesap aynı kuryeye puan | Flag |
| Kuryeyle sosyal medya bağlantısı | Flag |
| Kısa süre içinde çok fazla 5 yıldız | İnceleme |
| Anomalik puan dağılımı | İnceleme |

## Kurye Profil Sayfası

```
┌──────────────────────────────────┐
│  👤 Ahmet K.                      │
│  Üye: 8 ay                        │
├──────────────────────────────────┤
│  ⭐ 4.87 (127 puan)               │
│  📦 143 başarılı teslimat         │
│  ⏱  %96 zamanında                │
│  🎯 %98 tamamlama oranı           │
├──────────────────────────────────┤
│  🏅 Rozetler                      │
│  [100 Club] [Hız Şampiyonu]      │
│  [Hafta #3 - 47. Hafta]          │
├──────────────────────────────────┤
│  📊 Kategori detayı               │
│  Hız:           ⭐⭐⭐⭐⭐ 4.9     │
│  Davranış:      ⭐⭐⭐⭐⭐ 4.8     │
│  Paket durumu:  ⭐⭐⭐⭐⭐ 4.9     │
│  İletişim:      ⭐⭐⭐⭐  4.7      │
├──────────────────────────────────┤
│  💬 Son yorumlar                  │
│  "Çok hızlı ve nazikti"  ⭐⭐⭐⭐⭐ │
│  "Paketi özenle taşıdı"  ⭐⭐⭐⭐⭐ │
│  "İletişimde biraz eksikti" ⭐⭐⭐⭐│
└──────────────────────────────────┘
```

## Geliştirme Checklist

- [ ] Ağırlıklı ortalama hesaplama (off-chain)
- [ ] Wilson score hesaplama (leaderboard sıralama için)
- [ ] Zorunlu yorum flow (düşük puanda)
- [ ] Puan itiraz mekanizması
- [ ] Anti-fraud ML service (v2)
- [ ] Kurye profil sayfası
- [ ] IPFS yorum yükleme + gösterimi
- [ ] Kategori alt puanları (off-chain)
