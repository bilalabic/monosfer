# 05 — Teslimat Onayı (Delivery Confirmation)

## Amaç

Kurye paketi alıcıya ulaştırır. Alıcı, teslim aldığını onaylar. Bu onay sonrası escrow'daki ücret kuryeye serbest bırakılır.

## Akış

```
Kurye teslimat adresine varır
   ↓
Alıcıyı bulur (telefon / kapı zili)
   ↓
Alıcıya paketi teslim eder
   ↓
Alıcı teslim onayı verir (3 yöntemden biri)
   ↓
Akıllı kontrat: confirmDelivery()
   ↓
Sözleşme "Delivered" durumuna geçer
   ↓
06-odeme-aktarimi.md tetiklenir
```

## Üç Onay Yöntemi

Alıcının cüzdanı olup olmamasına göre üç yol:

### Yöntem 1: Alıcı Cüzdanı Var (On-chain Onay)

En güvenli yol. Alıcı kendi cüzdanıyla imzalar:

```solidity
function confirmDeliveryByRecipient(
    uint256 requestId,
    int32 recipientLat,
    int32 recipientLng
) external {
    DeliveryRequest storage req = requests[requestId];
    require(req.status == Status.InTransit, "Invalid state");
    require(msg.sender == req.recipientWallet, "Not recipient");

    req.status = Status.Delivered;
    req.deliveredAt = block.timestamp;

    emit DeliveryConfirmed(requestId, msg.sender, block.timestamp);

    // Ödemeyi tetikle (06'da detay)
    _releasePayment(requestId);
}
```

### Yöntem 2: SMS Kodu (Cüzdansız Alıcı)

Alıcının cüzdanı yoksa, sisteme kayıtlı telefonuna **6 haneli kod** SMS ile gönderilir. Kurye bu kodu uygulamaya girer:

```solidity
function confirmDeliveryByCourier(
    uint256 requestId,
    bytes calldata oracleSignedProof
) external {
    DeliveryRequest storage req = requests[requestId];
    require(msg.sender == req.acceptedCourier, "Not courier");

    // Oracle, alıcının SMS kodunu doğru girdiğini imzalar
    require(_verifyOracleSignature(requestId, oracleSignedProof), "Invalid proof");

    req.status = Status.Delivered;
    req.deliveredAt = block.timestamp;
    emit DeliveryConfirmed(requestId, req.recipientWallet, block.timestamp);
    _releasePayment(requestId);
}
```

### Yöntem 3: Zaman Aşımı (Itiraz Edilmezse)

Kurye "Teslim ettim" der, alıcı 24 saat içinde itiraz etmezse otomatik onay:

```solidity
function claimDeliveryByTimeout(uint256 requestId) external {
    DeliveryRequest storage req = requests[requestId];
    require(msg.sender == req.acceptedCourier, "Not courier");
    require(req.courierClaimedDelivery, "Not claimed yet");
    require(
        block.timestamp >= req.courierClaimTime + 24 hours,
        "Wait 24h"
    );
    require(!req.disputed, "Under dispute");

    req.status = Status.Delivered;
    _releasePayment(requestId);
    emit DeliveryConfirmedByTimeout(requestId);
}
```

Bu yöntem sadece **son çare** olmalı. Müşteri app'te uyarı alır ("Kurye teslim ettiğini söyledi, 24 saat içinde onay veya itiraz et").

## Kurye "Teslim Ettim" Bildirimi

Kurye teslim ettiğini önce off-chain bildirir, sonra onay yöntemine göre akış ilerler:

```solidity
function courierClaimsDelivery(
    uint256 requestId,
    int32 courierLat,
    int32 courierLng,
    bytes32 photoHash // Opsiyonel kapı fotoğrafı
) external {
    DeliveryRequest storage req = requests[requestId];
    require(msg.sender == req.acceptedCourier, "Not courier");
    require(req.status == Status.InTransit, "Invalid state");

    // GPS doğrulama (teslimat adresine ± 100m)
    require(_isWithinDeliveryRadius(requestId, courierLat, courierLng), "Too far");

    req.courierClaimedDelivery = true;
    req.courierClaimTime = block.timestamp;
    if (photoHash != bytes32(0)) {
        req.deliveryProofHash = photoHash;
    }

    emit CourierClaimedDelivery(requestId, block.timestamp);
}
```

## Frontend — Kurye Ekranı

```
┌─────────────────────────────────┐
│  Teslimat Adresindesin           │
├─────────────────────────────────┤
│  📍 Çankaya, Ankara              │
│  👤 Alıcı: Ayşe Y. (0555...47)  │
│                                  │
│  ☐ Paketi alıcıya verdim        │
│  ☐ Paket fotoğrafı çektim       │
│                                  │
│  Onay yöntemi:                   │
│  ◉ Alıcı uygulamasından onay    │
│  ○ SMS kodu ile onay             │
│  ○ Teslim ettiğimi bildir (24s) │
│                                  │
│  [ Teslimi Tamamla ]             │
└─────────────────────────────────┘
```

## Frontend — Alıcı Ekranı (Cüzdan Var)

```
┌─────────────────────────────────┐
│  📦 Paketiniz geldi!             │
├─────────────────────────────────┤
│  Kurye: Ahmet K. (⭐ 4.8)        │
│  Varış: 14:23                    │
│                                  │
│  Paket elinize ulaştı mı?        │
│                                  │
│  [ ✅ Teslim Aldım ]             │
│  [ ❌ Sorun Var ]                │
└─────────────────────────────────┘
```

## Paket Fotoğrafı (Kanıt)

Kurye opsiyonel olarak teslimat anında fotoğraf çekebilir:
- Kapı önündeki paket
- Alıcıyla paket (alıcı izin verirse)

Fotoğraf IPFS'e yüklenir, hash kontrata kaydedilir. Anlaşmazlık durumunda kanıt olarak kullanılır.

## Emit Edilecek Event'ler

```solidity
event CourierClaimedDelivery(uint256 indexed requestId, uint256 timestamp);
event DeliveryConfirmed(
    uint256 indexed requestId,
    address indexed confirmer,
    uint256 timestamp
);
event DeliveryConfirmedByTimeout(uint256 indexed requestId);
event DeliveryDisputed(uint256 indexed requestId, address indexed disputer);
```

## Süre Takibi

| Olay | Süre |
|------|------|
| Kurye pickup'tan sonra teslim etmeli | Aciliyete göre: `standard` 2s, `express` 1s, `instant` 30dk |
| Alıcı onay verme süresi | 24 saat (sonrasında otomatik onay) |
| İtiraz için süre | Kurye claim'den sonra 24 saat |

Kurye süreyi geçerse:
- %10-30 ücret kesintisi (gecikmeye göre)
- İtibar puanı düşer
- Çok geç kalırsa teslim başarısız sayılır

## Edge Case'ler

- **Alıcı paketi reddederse**: `rejectDelivery()` fonksiyonu, paket müşteriye geri gönderilir, ücret %50 müşteriye iade, %50 kuryeye kalır.
- **Alıcı adreste yok**: Kurye 3 kez deneme hakkı, her deneme arası 15 dk, sonunda başarısız teslim.
- **Paket hasarlı**: Alıcı "Sorun Var" der, `07-puanlama` ve `dispute-resolution` devreye girer.
- **Yanlış adres**: Kurye yeni adresi öneremez, müşteri talebi günceller veya iptal eder (cezalı).

## Geliştirme Checklist

- [ ] `courierClaimsDelivery()` fonksiyonu
- [ ] `confirmDeliveryByRecipient()` fonksiyonu
- [ ] `confirmDeliveryByCourier()` + oracle imzası
- [ ] `claimDeliveryByTimeout()` 24s bekleme
- [ ] `rejectDelivery()` red senaryosu
- [ ] SMS servisi entegrasyonu (Twilio veya benzeri)
- [ ] IPFS fotoğraf yükleme
- [ ] Frontend — kurye teslim ekranı
- [ ] Frontend — alıcı onay ekranı (cüzdanlı)
- [ ] Push/SMS bildirim
- [ ] 24 saat timer mekanizması

## Sonraki Adım

→ [`06-odeme-aktarimi.md`](./06-odeme-aktarimi.md) — Escrow serbest bırakılacak, kurye ödenecek.
