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

## 2.1) MetaMask Kurulumu ve Kontrol Listesi

MetaMask tarafi calismiyorsa genelde 3 sebep var: yanlis ag, yanlis adres, yetersiz bakiye.

### A) Monad Testnet agini manuel ekle

MetaMask -> `Settings` -> `Networks` -> `Add network manually`:

- Network Name: `Monad Testnet`
- RPC URL: `https://testnet-rpc.monad.xyz`
- Chain ID: `10143`
- Currency Symbol: `MON`
- Block Explorer URL: `https://testnet.monadexplorer.com`

Alternatif: [chainlist.org](https://chainlist.org) uzerinden Monad Testnet eklenebilir.

### B) Deployer adresi ve `.env` adresini eslestir

Terminalde:

```bash
source .env
cast wallet address --private-key $PRIVATE_KEY
cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url monad_testnet
cast chain-id --rpc-url monad_testnet
```

Beklenen sonuc:

- `cast chain-id` -> `10143`
- `cast wallet address` ile MetaMask aktif adresi ayni
- bakiye > `1 MON` (guvenli deploy icin)

### C) "Signer had insufficient balance" hatasi icin net kontrol

Bu hata bakiye varken bile gorunebilir, eger MetaMask'te gordugun adres ile script'in imzaladigi adres farkliysa.

Mutlaka su ikisini karsilastir:

1. MetaMask aktif hesap adresi
2. `cast wallet address --private-key $PRIVATE_KEY` ciktisi

Farkliysa `.env` icindeki key yanlis hesaba ait demektir.

### D) Frontend tarafinda zorunlu network kontrolu

Frontend baglandiginda:

- Chain ID `10143` degilse kullaniciya network switch istegi gonder.
- Yanlis chain'de write islemlerini blokla.
- Tx olustuktan sonra explorer linkini goster:
  - `https://testnet.monadexplorer.com/tx/<TX_HASH>`

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
- `DeliveryEscrow.getBidderCount(requestId)`
- `DeliveryEscrow.getBidders(requestId)`
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
    token: "0xda4f523b0d55fb6ce61515c4d003a70ca55948cd",
    escrow: "0x91023fb41c5a308c12ab68c037207f832426d067",
    leaderboard: "0x5a887f8c32e3299309212686acaad9b108aa883c",
    distributor: "0x6e7ed62ab956f79e16d870d0b3796dffca6903f2",
    badge: "0x8b44b40e24c16174eb0df623212f341e230ae83c"
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

### 10.1 Testnet Deploy Kaydi

Gercek deploy kaydi:

- `broadcast/DeploySystem.s.sol/10143/run-latest.json`

Bu dosyada `transactions[].hash` ve `receipts[]` dolu oldugu icin deploy on-chain basarili tamamlanmistir.
Backend ve frontend adresleri bu dosyadan alinmistir; mock adres kullanilmamistir.

## 11) Test Kapsami

Legacy (V1 oncesi) testler `test/legacy/` altinda toplanmistir. Bu testler
**degistirilmeden** gecmeye devam etmelidir; P5.3 cut-over onaylanana kadar
regresyon koruma agi olarak kullanilirlar (bkz. D1 karari).

- `test/legacy/Delivera.t.sol`
  - Native MON full flow
  - Leaderboard basic siralama
- `test/legacy/DeliveryEscrow.t.sol`
  - Token bazli full flow
  - Fee dagitimi dogrulamasi
  - Rating -> leaderboard guncellemesi

Calistirma:

```bash
forge test -vv
```

## 11.1) CI ve Kalite Kapilari

Kontratlar `.github/workflows/contracts.yml` ile her pull request'te ve
`Monosfer-V2` push'unda dogrulanir. `deploy.yml` sadece uygulamayi deploy eder;
kontratlari **build veya test etmez**.

| Kapi | Komut | Notlar |
|---|---|---|
| Build | `forge build` | `--offline` kullanilmaz |
| Format | `forge fmt --check` | Legacy dosyalar `foundry.toml` icindeki `[fmt].ignore` ile haric tutulur |
| Test | `forge test -vvv` | `FOUNDRY_PROFILE=ci` (fuzz 1024, invariant 256/128) |
| Gas | `forge snapshot --check` | Commit'li `.gas-snapshot` ile karsilastirir |
| Statik analiz | `slither .` | `slither.config.json`, `fail_on: medium` |
| Deploy dry-run | `forge script ...` | Her iki legacy script simule edilir (broadcast yok) |

Yerelde ayni kapilari calistirmak icin:

```bash
cd contracts
forge build
forge fmt --check
forge test -vvv
forge snapshot --check
slither .            # pip install slither-analyzer==0.11.6
```

### Arac surumu (pinlenmistir)

```text
Foundry 1.8.1
```

CI ayni surume pinlidir (`.github/workflows/contracts.yml`). Baseline §53, Monad
icin `Foundry >= 1.8.0` onerir; 1.8.1 bu kosulu saglar.

**Onemli:** gas rakamlari Foundry surumune duyarlidir. 1.5.1 -> 1.8.1 yukseltmesinde
kontrat kodu hic degismedigi halde olculen gas %25-61 artti (orn. `test_FullDeliveryFlow`
666.734 -> 1.076.982). Bu bir gas regresyonu degil, Foundry'nin test gas olcum
yonteminin degismesidir. Bu yuzden `.gas-snapshot` sadece **pinlenmis surum icinde**
anlamlidir; surum yukseltilirse snapshot ayni PR'da yeniden uretilmelidir.

### Gas snapshot guncelleme

`.gas-snapshot` commit'lidir. Gas degeri bilerek degistiyse ayni pull request
icinde yeniden uretilmeli ki fark incelenebilir olsun:

```bash
cd contracts && forge snapshot
```

`forge snapshot --check` kirmizi ise ya beklenmeyen bir gas regresyonu vardir, ya
snapshot guncellenmemistir, ya da arac surumu pinden farklidir.

### Statik analiz baseline

Legacy kontratlar D1 geregi dondurulmus oldugu icin bulgular su an duzeltilemez.
Kabul edilen baseline (48 bulgu: 0 high, 6 medium, 29 low, 7 informational,
6 optimization) `docs/static-analysis-baseline.md` icinde kayitlidir. Filtrelenmis
calistirma **0 sonuc** vermelidir; vermiyorsa bulgu yeni kodadir.

### Solidity satir sonlari

Kok dizindeki `.gitattributes`, `*.sol` dosyalarini `eol=lf` olarak sabitler.
Windows'ta `core.autocrlf=true` ile bu ayar olmadan `forge fmt` her satiri
degismis gosterir ve `forge fmt --check` yerelde CI'dan farkli davranir.

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
│   ├── TestScenario.sh
│   └── TestScenarioSystem.sh
├── test/
│   └── legacy/
│       ├── Delivera.t.sol
│       └── DeliveryEscrow.t.sol
├── docs/
│   └── static-analysis-baseline.md
├── .gas-snapshot
├── slither.config.json
├── foundry.toml
└── .env.example
```

V1 kontratlari P0.2'den itibaren `src/v1/` altina eklenecektir; legacy kaynaklar
P5.3 cut-over onaylanana kadar yerinde ve degistirilmeden kalir.

