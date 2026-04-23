# 04 — Alış Onayı (Pickup Confirmation)

## Amaç

Kurye, ürünü müşteriden fiziksel olarak teslim alır. QR kod okutma + GPS doğrulama ile "Alış Onaylandı" durumu blockchain'e kaydedilir. Bu aşamadan sonra talep iptal edilemez, sadece anlaşmazlık çözümüne gidilebilir.

## Akış

```
Kurye alış adresine varır
   ↓
Kurye uygulamasında "Alış Yaptım" butonuna basar
   ↓
Müşteri uygulamasında QR kod görünür
   ↓
Kurye QR kodu tarar (veya müşteri 6 haneli kod söyler)
   ↓
GPS doğrulaması (kurye pickup lokasyonuna ± 100m içinde mi?)
   ↓
Akıllı kontrat: confirmPickup()
   ↓
Sözleşme "InTransit" durumuna geçer
```

## İki Aşamalı Onay

### Aşama A: Kurye "Alış Yaptım" Butonuna Basar

Kurye uygulaması şunları toplar:
- Kuryenin o anki GPS koordinatları
- Zaman damgası
- Fotoğraf (opsiyonel — paket görseli)

### Aşama B: Müşteri QR Kod Onayı

Müşteri uygulamasında talep için **benzersiz bir QR kod** oluşturulur. Bu QR kod:
- `requestId`
- Müşteri imzası (EIP-712)
- 60 saniye TTL (süresi dolunca yenilenir)

Kurye QR kodu tarayınca, uygulama bu imzayı alır ve kontrata iletir.

## Akıllı Kontrat Fonksiyonu

```solidity
function confirmPickup(
    uint256 requestId,
    int32 courierLat,
    int32 courierLng,
    bytes calldata customerSignature
) external {
    DeliveryRequest storage req = requests[requestId];
    require(req.status == Status.Accepted, "Invalid state");
    require(req.acceptedCourier == msg.sender, "Not assigned courier");

    // GPS doğrulama (on-chain hash kontrolü, koordinatlar off-chain tutulur)
    bytes32 locationHash = keccak256(abi.encode(courierLat, courierLng));
    require(_isWithinPickupRadius(requestId, locationHash), "Too far from pickup");

    // Müşteri imzasını doğrula (EIP-712)
    bytes32 message = keccak256(abi.encode(
        "CONFIRM_PICKUP",
        requestId,
        msg.sender,
        block.timestamp / 60 // 1 dakikalık slot
    ));
    address signer = _recoverSigner(message, customerSignature);
    require(signer == req.customer, "Invalid signature");

    req.status = Status.InTransit;
    req.pickupAt = block.timestamp;

    emit PickupConfirmed(requestId, msg.sender, block.timestamp);
}
```

## GPS Doğrulama Stratejisi

On-chain tam GPS doğrulaması pahalı olduğu için hybrid yaklaşım:

1. **Off-chain oracle**: Kuryenin GPS verisi bir trusted oracle'a gönderilir.
2. **Oracle imzası**: Oracle, kuryenin pickup lokasyonuna ± 100m içinde olduğunu doğruladığını imzalar.
3. **On-chain kontrol**: Kontrat sadece oracle imzasını doğrular.

Alternatif: **ZK-proof** ile GPS doğrulaması (v2 için, MVP'de overkill).

## QR Kod Yapısı

QR kod içeriği (JSON, base64 encoded):

```json
{
  "requestId": "0x1a2b3c...",
  "customer": "0xabc...",
  "nonce": "1699999999",
  "signature": "0x..."
}
```

**Güvenlik:** 60 saniyelik TTL, replay attack'i önler. Kurye aynı QR'ı iki kere kullanamaz.

## Alternatif: 6 Haneli Kod

QR tarama çalışmazsa (kamera problemi, karanlık vs.), müşteri 6 haneli rakam gösterir:

```
Alış Kodu: 842 937
```

Kurye bu kodu uygulamaya girer, off-chain servis doğrular, kontrat çağrılır.

## Fiziksel Teslim Alma Kontrolü

Uygulamada kurye için checklist (opsiyonel ama önerilir):

```
☐ Paketi teslim aldım
☐ Paket hasarsız
☐ Adres etiketi doğru
☐ Paket fotoğrafı çektim (opsiyonel)

[ Alışı Tamamla ]
```

Fotoğraf IPFS'e yüklenir, hash'i kontrata kaydedilir — anlaşmazlık durumunda kanıt olarak kullanılır.

## Sözleşme Durum Geçişi

```
Accepted → [confirmPickup()] → InTransit
```

Bu noktadan sonra:
- Escrow hâlâ kilitli
- Müşteri tek taraflı iptal edemez
- Kurye zaman içinde teslim etmezse ceza (bkz. 05)

## Emit Edilecek Event'ler

```solidity
event PickupConfirmed(
    uint256 indexed requestId,
    address indexed courier,
    uint256 timestamp
);
event PickupPhotoUploaded(
    uint256 indexed requestId,
    bytes32 ipfsHash
);
```

## Edge Case'ler

- **QR kod süresi doldu**: Yenisi oluşur, kurye tekrar tarar.
- **Müşteri evde yok**: Kurye "Müşteri yok" butonuna basar, 5 dakika bekler, hâlâ yoksa talep `PickupFailed` durumuna geçer ve escrow %70 iade edilir (kurye rezervasyon ücreti olarak %30 alır).
- **GPS kapalı**: Kurye GPS'i açmak zorunda, aksi halde pickup onayı verilemez.
- **Paket yanlış**: Kurye paketi incelemekten sorumlu değil, sadece teslim alır.

## Geliştirme Checklist

- [ ] `confirmPickup()` kontrat fonksiyonu
- [ ] EIP-712 imza doğrulama
- [ ] Oracle imza doğrulama (GPS için)
- [ ] QR kod oluşturma (müşteri uygulaması)
- [ ] QR kod tarayıcı (kurye uygulaması)
- [ ] 6 haneli kod fallback
- [ ] Opsiyonel fotoğraf + IPFS yükleme
- [ ] `PickupFailed` timeout mekanizması (5 dk)
- [ ] Unit test + imza doğrulama testleri

## Sonraki Adım

→ [`05-teslimat-onayi.md`](./05-teslimat-onayi.md) — Kurye alıcıya teslim edecek, alıcı onay verecek.
