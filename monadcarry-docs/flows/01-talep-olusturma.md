# 01 — Talep Oluşturma ve Escrow

## Amaç

Müşteri, gönderi detaylarını girer ve ödemeyi akıllı sözleşmeye (escrow) kilitler. Bu aşamadan sonra teklif toplama başlar.

## Akış

```
Müşteri uygulamayı açar
   ↓
Gönderi detaylarını doldurur
   ↓
Tahmini ücret hesaplanır (mesafe + aciliyet)
   ↓
Müşteri "Talebi Oluştur" butonuna basar
   ↓
Akıllı kontrat: createDeliveryRequest()
   ↓
Müşterinin cüzdanından token escrow'a transfer edilir
   ↓
Talep, aktif kuryelere broadcast edilir
```

## Kullanıcı Girdileri

| Alan | Tip | Zorunlu | Açıklama |
|------|-----|---------|----------|
| `pickupAddress` | string | Evet | Alış adresi (geocode edilecek) |
| `deliveryAddress` | string | Evet | Teslimat adresi |
| `pickupLat`, `pickupLng` | float | Evet | Alış koordinatları |
| `deliveryLat`, `deliveryLng` | float | Evet | Teslimat koordinatları |
| `packageType` | enum | Evet | `document`, `food`, `small`, `medium`, `large` |
| `urgency` | enum | Evet | `standard` (2 saat), `express` (1 saat), `instant` (30 dk) |
| `maxBudget` | uint256 | Evet | Müşterinin ödemeye hazır olduğu üst limit (token) |
| `recipientPhone` | string | Evet | Alıcı telefonu (SMS doğrulama için) |
| `recipientWallet` | address | Hayır | Alıcı cüzdanı (varsa on-chain onay için) |
| `notes` | string | Hayır | Kurye için özel notlar |

## Akıllı Kontrat Fonksiyonu

```solidity
function createDeliveryRequest(
    bytes32 pickupHash,
    bytes32 deliveryHash,
    PackageType packageType,
    Urgency urgency,
    uint256 maxBudget,
    bytes32 recipientCommitment
) external returns (uint256 requestId);
```

**Önemli:** Adresler privacy için off-chain tutulur, sadece hash'leri on-chain'e yazılır.

## Escrow Mantığı

- Müşteri `maxBudget` kadar token'ı kontrata transfer eder (approve + transferFrom).
- Token'lar `escrowBalance[requestId]` altında kilitlenir.
- Talep 15 dakika içinde kurye eşleşmesi bulamazsa otomatik iade.
- Talep iptal edilirse %95 iade edilir (%5 platform ağı kullanım ücreti).

## Emit Edilecek Event

```solidity
event DeliveryRequested(
    uint256 indexed requestId,
    address indexed customer,
    uint256 maxBudget,
    Urgency urgency,
    uint256 timestamp
);
```

## Frontend Gereksinimleri

1. Harita üzerinde pickup + delivery noktalarını seçme (Google Maps / Mapbox).
2. Mesafe ve tahmini ücret hesaplama (off-chain, yaklaşık).
3. Cüzdan bağlantısı (MetaMask / WalletConnect).
4. Transaction onayı ve loading state.
5. Talep oluşturulduktan sonra "Teklif Bekleniyor" ekranına yönlendirme.

## Edge Case'ler

- **Yetersiz bakiye**: Kullanıcı `maxBudget` + gas kadar token'a sahip değilse UI'da uyarı.
- **Aynı anda birden fazla talep**: Bir müşteri maksimum 3 aktif talep tutabilir.
- **Aciliyet-mesafe uyumsuzluğu**: 30 km mesafe için `instant` seçilemez (backend validasyon).

## Geliştirme Checklist

- [ ] `DeliveryRequest` struct tanımlandı
- [ ] `createDeliveryRequest()` implementasyonu
- [ ] Token transferi (ERC20 approve pattern)
- [ ] Event emisyonu
- [ ] 15 dakikalık timeout mekanizması
- [ ] İptal fonksiyonu (`cancelRequest()`)
- [ ] Frontend form + validasyon
- [ ] Harita entegrasyonu
- [ ] Unit test (Hardhat/Foundry)

## Sonraki Adım

→ [`02-kurye-teklif.md`](./02-kurye-teklif.md) — Kuryeler bu talebi görecek ve teklif verecek.
