# Anlaşmazlık Çözüm Sistemi (Dispute Resolution)

## Amaç

Teslimat sırasında veya sonrasında ortaya çıkan anlaşmazlıkları merkezi otorite olmadan, şeffaf ve adil bir şekilde çözmek.

## Anlaşmazlık Senaryoları

| Senaryo | Kim başlatır | Tipik çözüm |
|---------|-------------|-------------|
| Kurye teslim ettim diyor, alıcı almadım diyor | Alıcı | Kanıt analizi, jüri |
| Paket hasarlı geldi | Alıcı | Kısmi iade |
| Kurye adrese gitmedi | Müşteri | Tam iade + ceza |
| Müşteri yanlış adres verdi | Kurye | Kurye lehine ödeme |
| Paket yanlış teslim edildi | Alıcı veya müşteri | Detaylı inceleme |
| Kurye ekstra ücret istedi | Müşteri | Kurye cezası |

## İki Aşamalı Çözüm

### Aşama 1: Otomatik Zaman Aşımı (Çoğu Durumda Yeterli)

```
Kurye "teslim ettim" diye bildirir
   ↓
Alıcı/müşteriye bildirim gider (push + SMS)
   ↓
24 saat içinde itiraz yoksa → Otomatik onay, ödeme kuryeye
   ↓
24 saat içinde itiraz varsa → Aşama 2'ye geçilir
```

### Aşama 2: Merkeziyetsiz Jüri (Kleros Benzeri)

Rastgele seçilen 5 jüri üyesi (stake yatırmış MCRY token sahipleri) olayı inceler:

```
Taraflar kanıt sunar (fotoğraf, GPS log, mesaj)
   ↓
IPFS'e yüklenir, jüri okur
   ↓
Her jüri oy verir (müşteri/kurye/split)
   ↓
Çoğunluk kararı uygulanır
   ↓
Doğru oy veren jüriler ödül alır
   ↓
Yanlış oy verenler stake'ten kaybeder
```

## Akıllı Kontrat Fonksiyonları

```solidity
function raiseDispute(
    uint256 requestId,
    DisputeReason reason,
    bytes32 evidenceIpfsHash
) external {
    DeliveryRequest storage req = requests[requestId];
    require(
        msg.sender == req.customer
        || msg.sender == req.acceptedCourier
        || msg.sender == req.recipientWallet,
        "Not a party"
    );
    require(req.status == Status.InTransit || req.status == Status.Delivered, "Invalid state");
    require(!req.disputed, "Already disputed");

    req.disputed = true;
    req.disputeRaisedAt = block.timestamp;
    disputes[requestId] = Dispute({
        initiator: msg.sender,
        reason: reason,
        initiatorEvidence: evidenceIpfsHash,
        status: DisputeStatus.Open
    });

    emit DisputeRaised(requestId, msg.sender, reason);
}

function submitEvidence(
    uint256 requestId,
    bytes32 evidenceIpfsHash
) external {
    // Karşı taraf kanıt sunabilir
    // 48 saat içinde kanıt sunulmalı
}

function selectJurors(uint256 requestId) external {
    // 5 rastgele jüri seçer (VRF ile)
    // Jüriler stake yatırmış adresler arasından
}

function juryVote(
    uint256 requestId,
    VoteChoice choice,
    bytes32 reasonHash
) external {
    require(isJuror[requestId][msg.sender], "Not juror");
    require(votes[requestId][msg.sender] == VoteChoice.None, "Already voted");

    votes[requestId][msg.sender] = choice;
    voteCounts[requestId][choice] += 1;

    if (_allJurorsVoted(requestId)) {
        _finalizeDispute(requestId);
    }
}
```

## Kanıt Tipleri

| Kanıt | Kim sunar | Format |
|-------|-----------|--------|
| GPS log | Oracle (otomatik) | Zaman + koordinat dizisi |
| Pickup fotoğrafı | Kurye | IPFS görsel hash |
| Delivery fotoğrafı | Kurye | IPFS görsel hash |
| QR kod doğrulama logu | Kontrat | On-chain event |
| Mesajlaşma ekran görüntüsü | Her iki taraf | IPFS görsel hash |
| Hasarlı paket fotoğrafı | Alıcı | IPFS görsel hash |
| Zaman damgaları | Kontrat | On-chain |

## Jüri Ekonomisi

### Jüri Olma Koşulları

- Minimum 100 MCRY stake
- Minimum 30 gün platformda aktif
- Geçmişte dispute manipülasyonu tespit edilmemiş

### Jüri Kazançları

- Her doğru karar: 2 MCRY
- Doğru oy oranı %90+ ise bonus rozet: `Adil Jüri`
- Yanlış oy: Stake'ten 1 MCRY düşülür
- Oy vermeme: Sıradaki dispute'tan men edilir

### Rastgele Seçim

Chainlink VRF (veya Monad alternatifi) ile adil seçim:

```solidity
function requestJurors(uint256 requestId) internal {
    uint256 vrfRequestId = VRF.requestRandomness(...);
    pendingJurorSelection[vrfRequestId] = requestId;
}

function fulfillRandomness(uint256 vrfRequestId, uint256[] memory randomness) internal {
    uint256 requestId = pendingJurorSelection[vrfRequestId];
    for (uint256 i = 0; i < 5; i++) {
        address juror = _pickJurorFromPool(randomness[i]);
        isJuror[requestId][juror] = true;
    }
}
```

## Karar Sonuçları

| Çoğunluk oyu | Sonuç |
|--------------|-------|
| Müşteri lehine | Tam iade + kurye itibarı düşer |
| Kurye lehine | Ödeme serbest + şikayet kuryenin sicili temiz |
| Split (3-2 veya karışık) | %50 iade, itibar etkilenmez |

## Frontend — Dispute Ekranı

```
┌─────────────────────────────────┐
│  Anlaşmazlık Oluştur             │
├─────────────────────────────────┤
│  Sebep:                          │
│  ◉ Paket ulaşmadı                │
│  ○ Paket hasarlı geldi           │
│  ○ Yanlış paket                  │
│  ○ Geç teslim                    │
│  ○ Kurye davranışı               │
│                                  │
│  Açıklama:                       │
│  ┌─────────────────────────┐    │
│  │                          │    │
│  └─────────────────────────┘    │
│                                  │
│  Kanıt (fotoğraf, ekran resmi):  │
│  [ + Dosya Ekle ]                │
│                                  │
│  ⚠ Haksız anlaşmazlık 10 MCRY   │
│     ceza getirebilir             │
│                                  │
│  [ Anlaşmazlığı Başlat ]         │
└─────────────────────────────────┘
```

## Kötü Niyetli Dispute Koruması

- Her dispute başlatmak 5 MCRY stake gerektirir
- Jüri haksız buldiysa stake yanar
- Tekrarlayan haksız dispute'lar → hesap askıya alınabilir

## MVP'de Basitleştirme

İlk sürümde jüri sistemi karmaşık gelebilir. MVP için:

1. **Otomatik timeout** (24s) — çoğu durumu çözer
2. **Platform moderasyonu** — acil durumlarda operasyon ekibi karar verir
3. **v2'de merkeziyetsiz jüri** — tam Kleros modeli

## Geliştirme Checklist

- [ ] `raiseDispute()` fonksiyonu
- [ ] `submitEvidence()` fonksiyonu
- [ ] Timeout mekanizması (24s)
- [ ] IPFS entegrasyonu
- [ ] Dispute UI (başlatma + kanıt)
- [ ] [v2] Jüri seçim (VRF)
- [ ] [v2] Jüri oy verme
- [ ] [v2] Jüri ödül/ceza mekanizması
