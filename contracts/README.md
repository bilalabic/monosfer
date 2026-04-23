# Delivera Smart Contracts

Monad Testnet (`10143`) uzerinde calisan Delivera kontratlari.
Bu dokuman backend ve frontend ekiplerinin paralel calismasini kolaylastirmak icin handoff formatinda hazirlandi.

## 1) Hedef ve Kapsam

Bu repo icinde iki ayri uygulama yolu vardir:

- `Delivera.sol`:
  - Native MON ile tek-kontrat MVP
  - Demo hizli cikis ve tek dosyada akisin gorulmesi icin ideal
- Moduler sistem:
  - `MCRYToken.sol`
  - `DeliveryEscrow.sol`
  - `Leaderboard.sol`
  - `RewardDistributor.sol`
  - `ReputationBadge.sol`
  - Backend/frontend entegrasyonu ve v2 genisleme icin onerilen yol

Hackathon demosunda hiz gerekiyorsa `Delivera.sol`, urune yaklasan mimari gerekiyorsa moduler sistem kullanilmalidir.

## 2) Ag ve Ortam Bilgileri

- Network: `Monad Testnet`
- RPC: `https://testnet-rpc.monad.xyz`
- Chain ID: `10143`
- Explorer: `https://testnet.monadexplorer.com`

`foundry.toml` icinde `monad_testnet` alias tanimlidir.

## 3) Kurulum ve Komutlar

```bash
cd contracts
forge build
forge test -vv
```

Deploy oncesi:

```bash
echo "PRIVATE_KEY=0x..." > .env
echo ".env" >> .gitignore
source .env
```

Deploy secenekleri:

- Tek kontrat MVP:
```bash
forge script script/Deploy.s.sol \
  --rpc-url monad_testnet \
  --private-key $PRIVATE_KEY \
  --broadcast
```

- Moduler sistem:
```bash
forge script script/DeploySystem.s.sol \
  --rpc-url monad_testnet \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 4) Sistem Akisi (Moduler)

1. Kurye `depositStake()` ile stake yatırır.
2. Musteri `createDeliveryRequest()` ile escrow talebi acar.
3. Kuryeler `submitBid()` ile teklif verir, `BID_DEPOSIT` kilitlenir.
4. Musteri `acceptBid()` ile kazanani secer.
5. Kurye `confirmPickup()` cagirir.
6. Musteri `confirmDelivery()` cagirir, odeme dagitimi otomatik olur.
7. Musteri `submitRating()` ile puanlar.
8. `Leaderboard` skoru gunceller, event emit eder.

## 5) Kontrat Sorumluluklari

### `MCRYToken`

- ERC20-benzeri temel token
- `transfer`, `approve`, `transferFrom`
- Stake ve escrow odemelerinde kullanilir

### `DeliveryEscrow`

- Talep/bid/secim/teslim akisi
- Teminat kilitleme ve iade
- `%1` komisyon kesintisi
- Komisyon dagilimi: `%50 treasury` + `%50 rewardPool`
- Leaderboard entegrasyonu

### `Leaderboard`

- Kurye istatistikleri
- Skor hesaplama
- `ScoreUpdated` eventi
- Ilk teslimatta rozet mint tetigi

### `RewardDistributor`

- Periyot bazli `merkleRoot` saklama
- Proof ile odul claim

### `ReputationBadge`

- Soulbound rozet mint
- Transfer kapali (`revert`)

## 6) Kritik Parametreler

### `Delivera.sol` (native MON MVP)

- `MIN_COURIER_STAKE = 0.01 ether`
- `BID_DEPOSIT = 0.001 ether`
- `PLATFORM_FEE_BPS = 100`

### `DeliveryEscrow.sol` (token tabanli)

- `MIN_COURIER_STAKE = 10 ether`
- `BID_DEPOSIT = 1 ether`
- `PLATFORM_FEE_BPS = 100`

Not: Her iki modelde de toplam platform komisyonu `%1` olarak ayarlidir.

## 7) Backend Handoff

### 7.1 Dinlenecek Eventler

- `DeliveryRequested(requestId, customer, maxBudget, urgency)`
- `BidSubmitted(requestId, courier, amount)`
- `CourierSelected(requestId, courier, amount)`
- `PickupConfirmed(requestId, timestamp)`
- `DeliveryConfirmed(requestId, timestamp)`
- `PaymentReleased(requestId, courier, courierAmount, treasuryFee, rewardFee)`
- `RatingSubmitted(requestId, courier, stars)`
- `ScoreUpdated(courier, newScore, timestamp)` (`Leaderboard`)

### 7.2 Onerilen Veri Modeli

- `requests`
  - `request_id`, `customer`, `status`, `max_budget`, `accepted_amount`, `urgency`
- `bids`
  - `request_id`, `courier`, `amount`, `estimated_minutes`, `is_winner`
- `deliveries`
  - `request_id`, `pickup_at`, `delivered_at`, `is_on_time`
- `ratings`
  - `request_id`, `courier`, `stars`
- `leaderboard_snapshots`
  - `courier`, `score`, `block_number`, `updated_at`

### 7.3 Sync Stratejisi

- Polling veya websocket ile event ingest
- Reorg guvenligi: en az `3` block confirmation
- Her event sonrası gerekirse on-chain read ile state dogrulama:
  - `requests(requestId)`
  - `courierStake(courier)`
  - `courierStats(courier)`

### 7.4 Backend Gorev Listesi

- Event consumer
- Idempotent writer (ayni tx iki kez islenmemeli)
- Retry + dead-letter queue
- Leaderboard cache endpoint (`GET /leaderboard`)
- Request detay endpoint (`GET /requests/:id`)

## 8) Frontend Handoff

### 8.1 Zorunlu Ekranlar

- Talep olusturma
- Teklif listesi
- Kurye secimi
- Pickup onayi
- Delivery onayi
- Rating
- Leaderboard

### 8.2 Gerekli Read Fonksiyonlari

- `DeliveryEscrow.requests(requestId)`
- `DeliveryEscrow.bidderList(requestId, i)` veya toplu getter (MVP: `Delivera.getBidders`)
- `DeliveryEscrow.courierStake(courier)`
- `Leaderboard.courierStats(courier)`
- `Leaderboard.getTopCouriers(candidates, topN)`

### 8.3 Gerekli Write Fonksiyonlari

- `depositStake(amount)`
- `createDeliveryRequest(...)`
- `submitBid(...)`
- `acceptBid(requestId, courier)`
- `confirmPickup(requestId)`
- `confirmDelivery(requestId)`
- `submitRating(requestId, stars)`

### 8.4 UI Durum Makinesi (Oneri)

- `OPEN_FOR_BIDS`
- `ACCEPTED`
- `IN_TRANSIT`
- `DELIVERED`
- `RATED`

UI, durum degisimini event ile dinlemeli; fallback olarak kontrattan durum okumali.

## 9) Frontend Config Ornegi

```ts
export const MONAD_TESTNET = {
  chainId: 10143,
  rpcUrl: "https://testnet-rpc.monad.xyz",
  explorer: "https://testnet.monadexplorer.com",
  contracts: {
    token: "0x...",
    escrow: "0x...",
    leaderboard: "0x...",
    distributor: "0x...",
    badge: "0x..."
  }
};
```

## 10) ABI ve Artifact Lokasyonlari

`forge build` sonrasi ABI dosyalari:

- `out/Delivera.sol/Delivera.json`
- `out/DeliveryEscrow.sol/DeliveryEscrow.json`
- `out/Leaderboard.sol/Leaderboard.json`
- `out/RewardDistributor.sol/RewardDistributor.json`
- `out/ReputationBadge.sol/ReputationBadge.json`
- `out/MCRYToken.sol/MCRYToken.json`

Frontend sadece `abi` alanini import ederek kullanabilir.

## 11) Test Kapsami

- `test/Delivera.t.sol`
  - Native MON full flow
  - Leaderboard basic siralama
- `test/DeliveryEscrow.t.sol`
  - Token bazli full flow
  - Fee dagitimi dogrulamasi
  - Rating -> leaderboard guncellemesi

Calistirma:

```bash
forge test -vv
```

## 12) Bilinen Limitler (Hackathon MVP)

- Reentrancy guard ekli degil (v2'de eklenmeli)
- GPS/Oracle dogrulama sade
- Dispute resolution yok
- Access control minimal
- On-chain sorting gas maliyetli (demo odakli)

## 13) V2 Teknik Yol Haritasi

- OpenZeppelin tabanli ERC20/ERC721
- UUPS veya Transparent proxy upgrade modeli
- Chainlink/Oracle destekli lokasyon dogrulama
- Merkle dagitiminda off-chain signer + period otomasyonu
- Subgraph veya benzeri indexer altyapisi

## 14) Dosya Haritasi

```text
contracts/
├── src/
│   ├── Delivera.sol
│   ├── DeliveryEscrow.sol
│   ├── Leaderboard.sol
│   ├── MCRYToken.sol
│   ├── ReputationBadge.sol
│   └── RewardDistributor.sol
├── script/
│   ├── Deploy.s.sol
│   ├── DeploySystem.s.sol
│   └── TestScenario.sh
├── test/
│   ├── Delivera.t.sol
│   └── DeliveryEscrow.t.sol
├── foundry.toml
└── .env.example
```
