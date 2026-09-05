# MONOSFER — Monad Testnet Doğrulama Raporu

> **Ağ:** Monad Testnet (`chain-id 10143`) · **Toolchain:** Foundry `1.8.1`
> **Branch:** `feat/contracts-p0.1-ci-harness` · Kod değişmedi, sadece test edildi
> **Tarih:** 6 Eylül 2026

---

## 1. Deploy edilen kontratlar (YENİ)

| Kontrat | Adres |
|---|---|
| `Delivera` | [`0x70042757830398af367c989d9bc8bab244c871d9`](https://testnet.monadexplorer.com/address/0x70042757830398af367c989d9bc8bab244c871d9) |
| `MCRYToken` | [`0x4CD3d3e5F738Eb78FF8B41Bd261a45044692c049`](https://testnet.monadexplorer.com/address/0x4CD3d3e5F738Eb78FF8B41Bd261a45044692c049) |
| `ReputationBadge` | [`0x81e480F6B54FAfDf4de404321F2991a051b8D931`](https://testnet.monadexplorer.com/address/0x81e480F6B54FAfDf4de404321F2991a051b8D931) |
| `Leaderboard` | [`0xe19C2e7CD1579Fb8Ba4b1CA2e1E6066d07B7FF97`](https://testnet.monadexplorer.com/address/0xe19C2e7CD1579Fb8Ba4b1CA2e1E6066d07B7FF97) |
| `RewardDistributor` | [`0x2CD2158dd751930EACa0ff24D4D3D9106d3Aa1a7`](https://testnet.monadexplorer.com/address/0x2CD2158dd751930EACa0ff24D4D3D9106d3Aa1a7) |
| `DeliveryEscrow` | [`0x0b0AfB512a50Ed98e58f8c3922fC89e9332a4C89`](https://testnet.monadexplorer.com/address/0x0b0AfB512a50Ed98e58f8c3922fC89e9332a4C89) |

**Bunlar test amaçlı yeni deploy'lardır.** `frontend/app/config/chain.ts` ve
`frontend/.env` hâlâ eski adresleri gösteriyor — frontend'e dokunulmadı (kapsam dışı).
Bu zaten boşluk analizi §2'deki "üç ayrı adres kaynağı" sorununun canlı örneği.

**Maliyet:** toplam ~1.50 MON (2 deploy + ~25 işlem). Bakiye 84.49 → 82.99 MON.

---

## 2. Test 1 — Delivera tam yaşam döngüsü (2 gerçek taraf)

Müşteri `0x10562C78…BA73`, kurye `0xdfae6C94…ABE1` (tek kullanımlık, fonlanmış).

| Adım | Sonuç |
|---|---|
| `registerCourier` (0.01 MON) | OK |
| `createDeliveryRequest` (0.05 MON) | OK |
| `submitBid` (0.03 MON, 22 dk) | OK |
| `acceptBid` | OK |
| `confirmPickup` | OK |
| `confirmDelivery` | OK |
| `submitRating` (5) | OK |

**Zincirdeki son durum:** kurye stake `0.01 MON` (teklif depozitosu iade edildi) ·
istatistik `1 teslimat / 5 puan / 1 zamanında / 0 geç / skor 160` · ortalama puan `5.00` ·
leaderboard doğru sıraladı.

Bu sonuçlar yerel anvil koşusuyla **birebir aynı** — yani davranış ağdan bağımsız tutarlı.

---

## 3. Test 2 — Modüler sistem tam yaşam döngüsü

Önce bağlantı doğrulaması: `badge.minter == Leaderboard` ✔ ·
`leaderboard.escrowContract == DeliveryEscrow` ✔ · dağıtıcı `1.000.000` token ile fonlu ✔

11 adımın tamamı OK (`transfer → approve → depositStake → approve → createRequest →
submitBid → acceptBid → confirmPickup → confirmDelivery → submitRating`).

**Sonuç:** kurye token bakiyesi `100 → 124.65`
(= 100 − 10 stake + 35 − %1 komisyon). Komisyon matematiği zincirde **kuruşu kuruşuna doğru**.
Leaderboard `1/1/0/5, skor 160`. **SBT rozet basıldı** (bakiye 1, sahibi kurye).

---

## 4. Kritik bulguların gerçek testnet'te doğrulanması

| # | Bulgu | Testnet sonucu |
|---|---|---|
| **A** | Teklif gelmeyen talep | Kontrat bakiyesi 0.010 → **0.015 MON**. `cancelDelivery()`, `refund()`, `withdraw()` — **hiçbiri yok**. 0.005 MON kalıcı kayıp. |
| **B** | `withdrawStake()` | Selector **yok** → kurye stake'i kalıcı kilitli |
| **C** | Müşteri kendi kuryesi (§33-16) | `acceptBid` **geçti**, seçilen kurye = müşteri → **ihlal doğrulandı** |
| **D** | Tek EOA yetkisi (§32.11) | `platformTreasury == rewardPool == deployer` → %50/%50 komisyon bölüşümü fiilen anlamsız |

**Delivera kontratında şu an kalıcı kilitli: `0.025 MON`.** Bu kontrat immutable ve
tahliye yolu olmadığı için bu bakiye **asla geri alınamaz**. Bu, P0'ın neden ilk sırada
olduğunun canlı kanıtı.

---

## 5. Diğer doğrulamalar

- **Proje deploy aracı:** `npm run test:deploy` → **2/2 geçti**
  (`scripts/deploy-record.mjs` broadcast JSON'ı doğru ayrıştırıyor).
- **Anahtar güvenliği:** `contracts/.env` gitignore'da ve **takipsiz**; anahtar hiçbir
  log'a, commit'e veya çıktıya yazılmadı. Kurye test cüzdanının anahtarı depo dışında,
  scratchpad'de tutuldu.
- **Depo durumu:** `contracts/` içinde hiçbir kaynak değişmedi; sadece 4 takipsiz kök
  `.md` dosyası var.

---

## 6. Sonuç

Her iki kontrat sistemi de Monad testnet'te **mutlu yol boyunca eksiksiz çalışıyor** —
para akışı, komisyon, itibar, leaderboard ve SBT rozet dahil. Aynı zamanda boşluk
analizinin **dört kritik bulgusu gerçek ağda kanıtlandı**, ve bunlardan biri şu anda
testnet'te 0.025 MON'u geri alınamaz şekilde kilitli tutuyor.

Yani mevcut kod "çalışıyor ama güvenli değil": P0'ın (pull-payment, iptal/timeout
yolları, stake çekme, self-dealing engeli) neden her şeyden önce gelmesi gerektiği
artık teorik değil, zincirde ölçülmüş durumda.
