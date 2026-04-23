# 08 — Leaderboard ve Ödül Dağıtımı

## Amaç

Her teslimat sonrası kurye (ve gönderici) skoru on-chain güncellenir. Haftalık, aylık ve sezonluk olarak en iyiler platform token'ı ve NFT rozet ile ödüllendirilir. Bu mekanizma rekabeti canlı tutar ve platformun en büyük farklılaşma noktasıdır.

## Üç Ayrı Leaderboard

1. **Kurye leaderboard'u** — performans odaklı (haftalık döngü)
2. **Gönderici leaderboard'u** — hacim + sadakat (aylık döngü)
3. **Bölgesel leaderboard** — şehir/ilçe rekabeti (sezonluk, 3 ay)

## Skor Formülleri

### Kurye Skoru

```
KuryeSkoru = (BaşarılıTeslimat × 10)
           + (ZamanındaTeslimatOranı × 50)
           + (OrtalamaMüşteriPuanı × 20)
           + (MesafeBonusu × 5)
           − (İptal × 15)
           − (GeçTeslimat × 8)
```

### Gönderici Skoru

```
GöndericiSkoru = (ToplamGönderi × 8)
               + (HarcananToplamTutar_USD × 0.5)
               + (KuryelereVerdiğiOrtPuan × 15)
               + (ArdışıkAktifHafta × 25)
```

### Bölge Skoru

```
BölgeSkoru = (Bölgedeki_Toplam_Teslimat × 3)
           + (Bölge_Ort_Kurye_Puanı × 100)
           + (Bölge_Aktif_Kullanıcı × 5)
```

Detaylı formüller için: [`/systems/leaderboard-formulas.md`](../systems/leaderboard-formulas.md)

## Akıllı Kontrat — Leaderboard

```solidity
contract Leaderboard {
    struct CourierScore {
        uint256 score;
        uint32 deliveriesThisPeriod;
        uint32 onTimeThisPeriod;
        uint32 lateThisPeriod;
        uint32 totalRatingSum;
        uint256 lastUpdate;
    }

    mapping(address => CourierScore) public courierScores;
    mapping(uint256 => address[]) public topCouriersByPeriod; // periodId => sıralı liste

    uint256 public currentPeriodId;
    uint256 public periodStartTime;
    uint256 public constant PERIOD_DURATION = 7 days;

    function recordDelivery(
        address courier,
        address customer,
        uint256 amount,
        uint256 deliveryDurationSec,
        Urgency urgency
    ) external onlyEscrowContract {
        _rolloverPeriodIfNeeded();

        CourierScore storage c = courierScores[courier];
        c.deliveriesThisPeriod += 1;

        bool onTime = deliveryDurationSec <= _expectedDuration(urgency);
        if (onTime) c.onTimeThisPeriod += 1;
        else c.lateThisPeriod += 1;

        // Ortalama puan rating fonksiyonu çağrıldığında eklenir
        _recalculateScore(courier);

        emit ScoreUpdated(courier, c.score, currentPeriodId);
    }

    function _recalculateScore(address courier) internal {
        CourierScore storage c = courierScores[courier];

        uint256 deliveryPoints = c.deliveriesThisPeriod * 10;
        uint256 onTimeRatio = c.deliveriesThisPeriod == 0
            ? 0
            : (c.onTimeThisPeriod * 100) / c.deliveriesThisPeriod;
        uint256 onTimePoints = (onTimeRatio * 50) / 100;

        uint256 ratingPoints = c.deliveriesThisPeriod == 0
            ? 0
            : (c.totalRatingSum * 20) / c.deliveriesThisPeriod;

        uint256 penalty = c.lateThisPeriod * 8;

        c.score = deliveryPoints + onTimePoints + ratingPoints;
        if (c.score > penalty) c.score -= penalty;
        else c.score = 0;
    }
}
```

## Periyodik Rollover

Her hafta/ay/sezon sonunda yeni periyot başlar:

```solidity
function _rolloverPeriodIfNeeded() internal {
    if (block.timestamp >= periodStartTime + PERIOD_DURATION) {
        _finalizePeriod(currentPeriodId);
        currentPeriodId += 1;
        periodStartTime = block.timestamp;
        emit NewPeriodStarted(currentPeriodId, periodStartTime);
    }
}

function _finalizePeriod(uint256 periodId) internal {
    // Top 50 kuryeyi sırala ve kaydet
    address[] memory topCouriers = _computeTopCouriers(50);
    topCouriersByPeriod[periodId] = topCouriers;

    // Ödül dağıtım kontratını tetikle
    rewardDistributor.distributeWeeklyRewards(periodId, topCouriers);

    emit PeriodFinalized(periodId, topCouriers.length);
}
```

**Gas optimizasyonu:** On-chain top-50 sıralaması pahalıdır. İki yaklaşım:

1. **Merkle tree snapshot**: Off-chain hesapla, Merkle kökünü on-chain kaydet. Kurye kendisi ödülü claim eder (Merkle proof ile).
2. **Lazy ranking**: Kurye ödül talep ederken kendi sırasını proof ile gösterir.

MVP için **opsiyon 1** önerilir.

## Ödül Dağıtımı

### Haftalık Kurye Ödülleri (Ödül havuzunun %40'ı)

| Sıra | Ödül |
|------|------|
| 1. | Havuzun %25'i + `Hafta Şampiyonu` NFT |
| 2-3. | Havuzun %10'u |
| 4-10. | Havuzun %3'ü |
| 11-50. | Havuzun %0.25'i |

### Aylık Gönderici Ödülleri (Ödül havuzunun %30'u)

| Sıra | Ödül |
|------|------|
| 1-3. | %10 indirim kuponu (sonraki 10 gönderi) + `Sadık Müşteri` NFT |
| 4-20. | %5 indirim kuponu (sonraki 5 gönderi) |

### Sezonluk Bölge Ödülü (Ödül havuzunun %30'u)

- Kazanan bölgedeki tüm aktif kullanıcılara eşit dağıtım
- `Bölge Kralı` NFT, bölgedeki top 10 kuryeye
- 3 ayda bir döngü

## Ödül Dağıtım Kontratı (Merkle Proof Pattern)

```solidity
contract RewardDistributor {
    mapping(uint256 => bytes32) public merkleRoots; // periodId => root
    mapping(uint256 => mapping(address => bool)) public claimed;

    function setMerkleRoot(uint256 periodId, bytes32 root)
        external
        onlyOracle
    {
        merkleRoots[periodId] = root;
        emit MerkleRootSet(periodId, root);
    }

    function claimReward(
        uint256 periodId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external {
        require(!claimed[periodId][msg.sender], "Already claimed");
        require(merkleRoots[periodId] != bytes32(0), "Root not set");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.verify(merkleProof, merkleRoots[periodId], leaf),
            "Invalid proof"
        );

        claimed[periodId][msg.sender] = true;
        rewardToken.transfer(msg.sender, amount);

        emit RewardClaimed(periodId, msg.sender, amount);
    }
}
```

## NFT Rozet (Soulbound)

Rozetler transfer edilemez (soulbound), sadece kazanılır:

```solidity
contract ReputationBadge is ERC721 {
    enum BadgeType {
        FirstDelivery,
        Club100,
        Club1000,
        WeeklyChampion,
        MonthlyChampion,
        SpeedKing,
        RegionLord,
        PerfectRating
    }

    function mint(address to, BadgeType badgeType) external onlyLeaderboard {
        uint256 tokenId = _nextTokenId();
        _safeMint(to, tokenId);
        badgeTypes[tokenId] = badgeType;
        emit BadgeMinted(to, tokenId, badgeType);
    }

    // Transfer engelle
    function _update(address to, uint256 tokenId, address auth)
        internal override returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0) || to == address(0), "Soulbound");
        return super._update(to, tokenId, auth);
    }
}
```

## Leaderboard UI

```
┌───────────────────────────────────────┐
│  🏆 Haftalık Kurye Liderlik Tablosu   │
│  (Son güncelleme: 2 dk önce)           │
├───────────────────────────────────────┤
│  #1  🥇 Ahmet K.     2,847 puan ⭐4.9 │
│      47 teslimat · %98 zamanında       │
│      [Hız Şampiyonu] [100 Club]        │
├───────────────────────────────────────┤
│  #2  🥈 Elif S.      2,634 puan ⭐4.8 │
│      52 teslimat · %94 zamanında       │
├───────────────────────────────────────┤
│  #3  🥉 Mehmet Y.    2,401 puan ⭐4.7 │
│  ...                                   │
│  #47 Sen              342 puan ⭐4.5  │
│      8 teslimat · %88 zamanında        │
├───────────────────────────────────────┤
│  Hafta bitimine: 2 gün 14 saat         │
│  Potansiyel ödül (#47): 12 MCRY       │
└───────────────────────────────────────┘
```

## Emit Edilecek Event'ler

```solidity
event ScoreUpdated(address indexed user, uint256 newScore, uint256 periodId);
event PeriodFinalized(uint256 periodId, uint256 topCount);
event NewPeriodStarted(uint256 periodId, uint256 startTime);
event MerkleRootSet(uint256 periodId, bytes32 root);
event RewardClaimed(uint256 periodId, address indexed user, uint256 amount);
event BadgeMinted(address indexed user, uint256 tokenId, BadgeType badgeType);
```

## Anti-Sybil Koruması

Aynı kişinin birden fazla hesap açıp ödülleri sömürmesini önlemek için:

- **Minimum stake zorunluluğu**: Kurye kayıt olurken 10 MCRY bloke eder
- **KYC opsiyonel**: v2'de telefon numarası + ID doğrulama
- **Graf analizi**: Off-chain, cüzdanlar arası şüpheli pattern'ler
- **Device fingerprint**: Aynı cihazdan birden fazla hesap engellenir

## Edge Case'ler

- **Bir kurye haftanın ortasında başlarsa**: Tam hafta tamamlamadan da skoru işlenir, ama top 50'ye girmek için minimum 10 teslimat şart.
- **Beraberlik**: Aynı skor olursa, daha fazla teslimat yapan önde; o da eşitse daha erken başlayan.
- **Ödül claim süresi**: Bir periyodun ödülleri 30 gün içinde claim edilmezse, havuza geri döner.
- **Kontrat upgrade**: Leaderboard verisi güncel periyot sonunda finalize edildiği için, upgrade periyot sonunda yapılmalı.

## Geliştirme Checklist

- [ ] `Leaderboard` kontratı
- [ ] `recordDelivery()` ve `updateCourierScore()` 
- [ ] Periyot rollover mekanizması
- [ ] Merkle tree hesaplaması (off-chain service)
- [ ] `RewardDistributor` kontratı
- [ ] `claimReward()` + Merkle proof verifikasyonu
- [ ] `ReputationBadge` ERC721 soulbound NFT
- [ ] Rozet mint koşulları (otomatik tetikleme)
- [ ] Leaderboard UI (canlı güncelleme)
- [ ] Ödül talep ekranı
- [ ] Anti-sybil off-chain service
- [ ] Unit test — skor hesaplama
- [ ] Integration test — full döngü (01'den 08'e)

## Bu Dosyayla Biten Akış

8 adım tamamlandı. Sonraki adım: `/systems` altındaki destekleyici dokümanları incelemek ve Claude Code ile implementasyona başlamak.

**Önerilen geliştirme sırası:**
1. `DeliveryEscrow.sol` — flow 01-06 birleşik kontrat
2. `Leaderboard.sol` — flow 07-08 skor sistemi
3. `RewardDistributor.sol` + `ReputationBadge.sol`
4. Frontend — React Native mobil uygulama
5. Backend oracle — GPS, SMS, Merkle root servisi
