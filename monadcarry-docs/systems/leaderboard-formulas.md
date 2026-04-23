# Leaderboard Skor Formülleri

## Kurye Skoru — Detay

```
KuryeSkoru_Hafta = 
    (BaşarılıTeslimat         × 10)
  + (ZamanındaTeslimatOranı% × 50)
  + (OrtalamaMüşteriPuanı     × 20)
  + (MesafeBonusu             × 5)
  − (İptal                    × 15)
  − (GeçTeslimat              × 8)
```

### Değişken Tanımları

| Değişken | Nasıl hesaplanır | Aralık |
|----------|------------------|--------|
| `BaşarılıTeslimat` | Haftalık tamamlanan teslimat sayısı | 0 – ∞ |
| `ZamanındaTeslimatOranı%` | `onTimeCount / totalDeliveries` × 100 | 0 – 100 |
| `OrtalamaMüşteriPuanı` | Haftalık puanların ortalaması | 1.0 – 5.0 |
| `MesafeBonusu` | Toplam km / 10 | 0 – ∞ |
| `İptal` | Kuryenin iptal ettiği sipariş sayısı | 0 – ∞ |
| `GeçTeslimat` | Aciliyet süresini aşan teslimat sayısı | 0 – ∞ |

### Örnek Hesaplama

Ahmet bir haftada:
- 47 teslimat tamamladı
- 46'sı zamanında (%97.8)
- Ortalama puan 4.8
- Toplam 230 km yol gitti
- 1 iptal, 1 geç teslimat

```
Skor = (47 × 10) + (97.8 × 50/100 × 50) + (4.8 × 20) + (23 × 5) − (1 × 15) − (1 × 8)
     = 470 + 489 + 96 + 115 − 15 − 8
     = 1,147
```

### Lig Sistemi (Normalize Etme)

Yeni kurye veteranla yarışmasın:

| Lig | Koşul | Ayrı leaderboard |
|-----|-------|------------------|
| Çırak | 0-49 teslimat | Evet, %20 havuz |
| Usta | 50+ teslimat | Evet, %80 havuz |

## Gönderici Skoru — Detay

```
GöndericiSkoru_Ay = 
    (ToplamGönderi              × 8)
  + (HarcananToplam_USD         × 0.5)
  + (KuryelereVerdiğiOrtPuan    × 15)
  + (ArdışıkAktifHafta          × 25)
```

### Değişken Tanımları

| Değişken | Nasıl hesaplanır |
|----------|------------------|
| `ToplamGönderi` | Aylık oluşturduğu sipariş sayısı |
| `HarcananToplam_USD` | Aylık toplam ödeme (Monad oracle üzerinden USD) |
| `KuryelereVerdiğiOrtPuan` | Müşterinin kuryelere verdiği ort. puan |
| `ArdışıkAktifHafta` | Kesintisiz kaç hafta sipariş verdi |

### Streak Mekanizması

Duolingo mantığı — kullanıcıyı düzenli kullanmaya iter:

- Haftada en az 1 sipariş = streak devam
- 1 hafta boşluk = streak sıfırlanır
- Streak katsayısı üstel: 4 hafta = 100, 8 hafta = 200, 12 hafta = 300

## Bölgesel Skor — Detay

```
BölgeSkoru_Sezon = 
    (Bölgedeki_Toplam_Teslimat    × 3)
  + (Bölge_Ort_Kurye_Puanı × 100)
  + (Bölge_Aktif_Kullanıcı × 5)
```

### Bölge Tanımı

MVP için Türkiye'nin 81 ili. Her ilin kendi leaderboard'u. İller arası sıralama da ayrıca gösterilir.

### Örnek: Kayseri vs Ankara

| Bölge | Teslimat | Ort. Puan | Aktif Kullanıcı | Skor |
|-------|----------|-----------|-----------------|------|
| Kayseri | 2,400 | 4.7 | 340 | 2,400×3 + 4.7×100 + 340×5 = 8,870 |
| Ankara | 8,700 | 4.5 | 1,250 | 8,700×3 + 4.5×100 + 1,250×5 = 32,800 |

Popülasyon farkı nedeniyle Ankara öne çıkar. Bu yüzden **kişi başı skor** da hesaplanır:

```
KişiBaşıSkor = BölgeSkoru / Aktif_Kullanıcı
```

Bu şekilde küçük şehirler de yarışabilir.

## Real-time Güncelleme Stratejisi

### On-chain (Monad'ın hızı sayesinde)

Her teslimat sonrası `recordDelivery()` çağrısı skoru günceller. Monad'ın 10k TPS'i bu yükü kaldırır.

### Off-chain Cache

Leaderboard UI, her saniyede kontrata bakmaz — WebSocket ile event'leri dinler:

```javascript
contract.on('ScoreUpdated', (user, newScore, periodId) => {
    updateLeaderboardUI(user, newScore);
});
```

## Formül Kalibrasyonu

Bu formüller başlangıç halleridir. Platform büyüdükçe:

1. **A/B test**: Farklı ağırlıklar dene
2. **Kullanıcı feedback**: "Adil hissediyor mu?"
3. **Abuse tespiti**: Belirli davranışlar skoru anormal yükseltiyor mu?

Formüller governance ile değiştirilebilir olmalı (v2).

## Test Senaryoları

Bu formüllerin test edilmesi için `leaderboard-simulation.js` script'i yazılabilir:

```javascript
// Simülasyon: 100 kurye, 1000 teslimat, 4 hafta
const couriers = generateCouriers(100);
for (let week = 0; week < 4; week++) {
    for (let i = 0; i < 250; i++) {
        const delivery = simulateDelivery(couriers);
        updateScores(delivery);
    }
    printLeaderboard(week);
}
```

Bu simülasyonla formüldeki dengesizlikler (örn. tek bir metriğin çok baskın olması) fark edilebilir.
