# Tokenomics ve NFT Rozet Sistemi

## MCRY Token (ERC-20)

### Temel Bilgiler

| Özellik | Değer |
|---------|-------|
| İsim | MonadCarry Token |
| Sembol | MCRY |
| Ondalık | 18 |
| Toplam arz | 100,000,000 MCRY (sabit) |
| Standart | ERC-20 |
| Chain | Monad |

### Dağıtım

| Pay | Yüzde | Miktar | Vesting |
|-----|-------|--------|---------|
| Ekip | 15% | 15M | 4 yıl, 1 yıl cliff |
| Yatırımcılar | 20% | 20M | 3 yıl lineer |
| Hazine (treasury) | 20% | 20M | DAO kontrolü |
| Ödül havuzu | 35% | 35M | 5 yıl lineer, her hafta dağıtım |
| Topluluk airdrop | 5% | 5M | İlk 10k kullanıcıya |
| Likidite | 5% | 5M | DEX likidite sağlayıcısı |

### Kullanım Alanları

1. **Ödeme aracı**: Müşteriler teslimat için MCRY kullanabilir (stablecoin alternatifi)
2. **Teminat/stake**: Kuryeler kayıt için 10 MCRY stake etmeli
3. **Ödül**: Leaderboard kazananlarına haftalık/aylık dağıtım
4. **Governance**: Stake yatıranlar oylama hakkı kazanır
5. **Jüri stake**: Dispute jürileri 100 MCRY stake yatırmalı

## Ödül Havuzu Mekaniği

### Kaynak

| Kaynak | Miktar |
|--------|--------|
| Her teslimat ücretinin %5'i | Ana kaynak |
| Emisyon (haftalık) | Token unlock |
| Gecikme cezaları | Kuryelerden kesilen ceza |
| Haksız dispute stake'leri | Jüri kararlarıyla |

### Dağıtım (Haftalık)

```
Haftalık Havuz = %5 komisyon + haftalık emisyon
```

Bu havuz şu şekilde bölünür:

| Kullanım | Yüzde |
|----------|-------|
| Haftalık kurye ödülleri | 40% |
| Aylık gönderici ödülleri | 30% |
| Sezonluk bölge ödülleri | 20% |
| Jüri ödemeleri | 10% |

## NFT Rozet Sistemi (ERC-721 Soulbound)

### Rozet Tipleri

#### Kurye Rozetleri

| Rozet | Koşul | Prestij |
|-------|-------|---------|
| 🎖 İlk Teslimat | İlk başarılı teslimat | Common |
| 🚀 100 Club | 100 teslimat | Uncommon |
| 💎 1000 Club | 1,000 teslimat | Rare |
| ⚡ Hız Şampiyonu | Hafta en düşük ort. süre | Rare (haftalık 1 kişi) |
| 🏆 Hafta Şampiyonu | Haftalık #1 | Rare |
| 👑 Ay Şampiyonu | Aylık #1 | Epic |
| 🌟 Sezon Şampiyonu | Sezonluk #1 | Legendary |
| 💯 Mükemmel Puan | 50+ teslimat, 5.0 ort. | Epic |
| 🔥 Streak Master | 30 gün kesintisiz aktif | Rare |

#### Gönderici Rozetleri

| Rozet | Koşul |
|-------|-------|
| 📦 İlk Gönderi | İlk sipariş |
| 💝 Sadık Müşteri | 50 sipariş |
| ⭐ Cömert Puanlayıcı | 100+ puanlama, ortalama 4.5+ |
| 🏅 VIP | Aylık harcaması top %5 |

#### Bölgesel Rozetler

| Rozet | Koşul |
|-------|-------|
| 🏰 Bölge Kralı | Kazanan bölgenin top 10 kuryesi |
| 🌆 Şehir Onuru | Bölge sezon şampiyonu oldu, tüm aktif kullanıcılara |

### Soulbound Özelliği

Rozetler **transfer edilemez** — kazanılır, satılamaz. Bu, rozetlerin itibar değerini korur.

```solidity
function _update(address to, uint256 tokenId, address auth)
    internal override returns (address)
{
    address from = _ownerOf(tokenId);
    // Sadece mint (from = 0) veya burn (to = 0) izinli
    require(from == address(0) || to == address(0), "Soulbound: non-transferable");
    return super._update(to, tokenId, auth);
}
```

### Rozet Faydaları

Sadece dekoratif değil, pratik avantajlar:

| Rozet | Fayda |
|-------|-------|
| 100 Club | Teklif önceliği (+5 puan) |
| 1000 Club | Kurye yayın komisyonu %1 indirim |
| Hız Şampiyonu | Profil badge + bonus %2 (1 hafta) |
| Sezon Şampiyonu | 500 MCRY + fiziksel trophy (opt.) |

## Stake ve Teminat Yapısı

### Kurye Stake

```
Minimum stake: 10 MCRY
Her teklifte bloke: 1 MCRY
Teslimat tamamlanınca: iade
```

### Müşteri Stake (Dispute için)

```
Dispute başlatmak: 5 MCRY
Jüri haklı bulursa: iade
Jüri haksız bulursa: yanar (ödül havuzuna)
```

### Jüri Stake

```
Jüri olma koşulu: 100 MCRY
Doğru oy: +2 MCRY
Yanlış oy: -1 MCRY
```

## Governance (v2)

Stake yatıranlar DAO oylamasına katılabilir:

- Platform komisyon oranı değişikliği
- Leaderboard formülü güncellemesi
- Yeni rozet ekleme/çıkarma
- Treasury kullanımı
- Hazine fonlarının kullanımı

Oy ağırlığı: `sqrt(stake)` — Vitalik'in quadratic voting önerisi gibi.

## Sürdürülebilirlik Analizi

### Senaryo: 10,000 günlük teslimat

- Ort. teslimat ücreti: 50 MCRY
- Günlük toplam hacim: 500,000 MCRY
- Ödül havuzuna (%5): 25,000 MCRY/gün
- Haftalık havuz: 175,000 MCRY

Bu havuz **sadece komisyondan** geliyor — emisyon dahil değil. Yani platform kendi kendini finanse edebilir.

### Enflasyon Kontrolü

Emisyon 5 yıl süreyle, sonra token deflasyonist hale gelir:
- Komisyonların bir kısmı **burn** edilebilir (DAO kararıyla)
- Rozet mint'i token yakmaz, sadece emisyon sınırlı

## Geliştirme Checklist

- [ ] `MCRY` ERC-20 kontratı
- [ ] Vesting kontratı (ekip, yatırımcı)
- [ ] Treasury multisig kurulumu
- [ ] `ReputationBadge` ERC-721 soulbound
- [ ] Rozet mint koşulları (otomatik tetikleme)
- [ ] Stake yönetimi (kurye, jüri, dispute)
- [ ] Airdrop mekanizması
- [ ] DEX likiditesi (v2)
- [ ] DAO governance (v2)
