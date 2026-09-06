# MONOSFER Kontratları

Monad Testnet (`chainId 10143`) üzerinde çalışan MONOSFER akıllı kontratları.

Kapsam ve şartname: depo kökündeki
`MONOSFER_Initial_Release_Base_Documentation_v1.0.md`. Bu README'deki `sec. ` atıfları
o dokümana yapılır.

---

## 1) V1 kontratları

Aktif geliştirme `src/v1/` altındadır ve baseline sec. 32'deki mimariyi izler:
sorumluluklar ayrı kontratlara bölünmüş, tüm değer tek bir vault'ta custody
edilir, yetkiler tek bir rol yöneticisinden gelir.

| Kontrat | Sorumluluk | Doküman |
|---|---|---|
| `ProtocolAccessManager` | Roller, acil durum pause, gecikmeli unpause | [governance](docs/governance.md) |
| `ProtocolConfig` | sec. 48 parametreleri, sınırlar, zaman kilidi, sürümleme | [governance](docs/governance.md) |
| `SettlementVault` | Custody, pull-payment uzlaşma, ödeme gücü | [settlement](docs/settlement.md) |
| `CourierRegistry` | Stake, C0/C1/C2, askı, teminat, custody | [courier-registry](docs/courier-registry.md) |
| `DeliveryHub` | Teslimat yaşam döngüsü, teklif, fonlama, uzlaşma | [delivery-lifecycle](docs/delivery-lifecycle.md) |
| `RiskQuoteVerifier` | İmzalı kapsam teklifi, zincirde kapsam bandı | [risk-quote](docs/risk-quote.md) |
| `PickupProofVerifier` | Gönderenin imzalı devir kabulü, nonce, ERC-1271 | [proofs](docs/proofs.md) |

Sıradaki fazlar (PoD attestation, `ReputationRegistry`, `DisputeCourt`, …):
[`docs/implementation-plan-v1.0.md`](docs/implementation-plan-v1.0.md).

---

## 2) Ağ

| | |
|---|---|
| Network | Monad Testnet |
| Chain ID | `10143` |
| RPC | `https://testnet-rpc.monad.xyz` |
| Explorer | `https://testnet.monadexplorer.com` |

`foundry.toml` içinde `monad_testnet` alias'ı tanımlıdır.

**Deploy adresleri:** [`deployments/10143.json`](deployments/10143.json).
Adresleri elle hiçbir yere kopyalamayın — sec. 5'e bakın.

> **Monad'a özgü:** gas, harcanan miktar üzerinden değil
> **`gasLimit × maxFeePerGas`** üzerinden peşin rezerve edilir (sec. 43). Fazla büyük
> gas limiti tamponu, bakiyesi yeterli bir hesabın işlemini bile
> "insufficient balance" ile reddettirir. İşlem gönderirken `--gas-limit` verin.

---

## 3) Kurulum ve komutlar

```bash
cd contracts
forge build
forge test -vvv
```

Bağımlılıklar (`forge-std`, `openzeppelin-contracts`) depoda **vendor** edilmiştir;
submodule kurulumu gerekmez.

| Komut | İş |
|---|---|
| `forge build` | Derle |
| `forge test` | Tüm testler (`FOUNDRY_PROFILE=ci` daha ağır fuzz/invariant koşar) |
| `forge fmt` | Biçimlendir |
| `forge snapshot --no-match-test "testFuzz\|invariant_"` | Gas snapshot'ını yeniden üret |
| `slither .` | Statik analiz (`pip install slither-analyzer==0.11.6`) |

---

## 4) CI ve kalite kapıları

`.github/workflows/contracts.yml` her pull request'te ve `Monosfer-V2` push'unda
çalışır. `deploy.yml` sadece uygulamayı deploy eder; kontratları **build veya
test etmez**.

| Kapı | Komut |
|---|---|
| Build | `forge build` |
| Format | `forge fmt --check` |
| Test | `forge test -vvv` |
| Gas | `forge snapshot --check --no-match-test "testFuzz\|invariant_"` |
| Statik analiz | `slither .` (`fail_on: medium`) |
| Deploy dry-run | Devralınan iki deploy script'i simüle edilir |

**Kapı olmayan iki şey.** `script/v1/DeployCore.s.sol` CI'da simüle edilmiyor ve
`npm run contracts:exports:check` bir kapı değil — ikisi de yerelde koşuluyor.
Yani bozuk bir V1 deploy script'i veya bayat bir `exports/` paketi CI'dan sessizce
geçer. Bilinçli bir boşluk değil, kapatılmayı bekleyen bir eksik.

### Arac surumu (pinlenmistir)

```text
Foundry 1.8.1   ·   OpenZeppelin 5.7.0   ·   Slither 0.11.6
```

CI aynı sürüme pinlidir. **Gas rakamları Foundry sürümüne duyarlıdır**: 1.5.1 →
1.8.1 yükseltmesinde kontrat değişmeden ölçülen gas %25–61 arttı. Bu yüzden
`.gas-snapshot` yalnızca pinlenmiş sürüm içinde anlamlıdır; sürüm yükseltilirse
aynı PR'da yeniden üretilmelidir.

Snapshot **yalnızca deterministik testleri** kapsar. Fuzz ve invariant testlerinin
raporladığı gas, rastgele girdiler üzerinden bir ortalamadır ve fuzz seed'iyle
değişir; snapshot'a dahil edilseler kapı dalgalı olurdu. Kapıya anlamını veren şey
determinizmdir.

Determinizm testin **kendi başına** ölçülebilmesi demektir: bir girdinin gası,
ondan önce hangi testlerin koştuğuna bağlı olmamalı. Test fixture'larında artan
sayaçtan üretilip calldata'ya ulaşan değerler tam olarak bu bağımlılığı yaratır
ve kapıyı kodun değil test filtresinin fonksiyonu haline getirir. Fixture'lar bu
yüzden nonce/salt gibi değerleri argümanlardan türetir.

### Tekrarlanabilir derleme

`foundry.toml` içinde `bytecode_hash = "none"`. Varsayılan davranışta solc,
bytecode'a **mutlak kaynak yollarını** içeren bir metadata hash'i gömer; aynı
kaynak Windows'ta ve Linux CI'da farklı bytecode, farklı CREATE adresi ve —
adres byte'ları calldata'ya girdiğinde — farklı gas üretir. Bu ayar makineler
arasında aynı çıktıyı garanti eder.

### Statik analiz baseline

Kabul edilen baseline ve gerekçeleri
[`docs/static-analysis-baseline.md`](docs/static-analysis-baseline.md)'de kayıtlı,
filtreler `slither.config.json`'da. Filtrelenmiş koşu **0 sonuç** vermelidir;
vermiyorsa bulgu yeni kodadır.

### Solidity satır sonları

Kök `.gitattributes`, `*.sol` dosyalarını `eol=lf` olarak sabitler. Windows'ta
`core.autocrlf=true` ile bu ayar olmadan `forge fmt` her satırı değişmiş gösterir
ve yerelde CI'dan farklı davranır.

---

## 5) Frontend / backend entegrasyonu

Adresler ve ABI'lar **üretilir**, elle yazılmaz:

```bash
npm run contracts:exports          # deployments/ + forge ciktisi -> exports/
npm run contracts:exports:check    # bayatsa hata ver
```

```js
import { getAddress, getChain, ABIS } from '../../contracts/exports/index.js'
const vault = getAddress(10143, 'SettlementVault')
```

Paket ESM + `.d.ts` yayınlar: TypeScript frontend tip denetimi, JavaScript backend
editör tamamlaması alır. Ayrıntı ve gerekçe:
[`docs/integration.md`](docs/integration.md).

> Adresleri `chain.ts`, `.env` veya bu README'ye **kopyalamayın**. Elle tutulan her
> kopya zamanla diğerlerinden ayrışır; bu katman tam olarak onu önlemek için var.

---

## 6) Deploy

```bash
DEFAULT_ADMIN=... CONFIG_ADMIN=... EMERGENCY_ADMIN=... SIGNER_ADMIN=... \
TREASURER=... TREASURY=... RISK_QUOTE_SIGNER=... POD_ATTESTATION_SIGNER=... \
EXPECTED_CHAIN_ID=10143 \
forge script script/v1/DeployCore.s.sol:DeployCoreScript \
  --rpc-url monad_testnet --broadcast
```

Script şu durumlarda **deploy etmeden durur**: eksik rol adresi, kritik rollerin
aynı adresi paylaşması, yanlış ağ, boş olmayan vault/registry.

Roller script tarafından **verilmez** — yalnızca `DEFAULT_ADMIN` atanır; diğer
roller multisig'in kendisi tarafından verilir, böylece deployer anahtarı hiçbir
operasyonel rol taşımaz. Rol matrisi ve runbook:
[`docs/governance.md`](docs/governance.md).

Deploy sonrası manifest ve export'ları güncelleyin (sec. 5).

---

## 7) Test

| Suite | Kapsam |
|---|---|
| `test/v1/` | V1 birim + fuzz testleri |
| `test/v1/invariant/` | Durum-bilgili invariant suiteleri |
| `test/legacy/` | Devralınan kontratların regresyon ağı (bkz. sec. 8) |

Güncel sonuçlar, faz faz özet ve testnet senaryoları:
[`docs/verification-log.md`](docs/verification-log.md).

---

## 8) Devralınan kontratlar

`src/*.sol` altındaki kontratlar (`Delivera`, `DeliveryEscrow`, `Leaderboard`,
`MCRYToken`, `ReputationBadge`, `RewardDistributor`) V1 öncesi MVP'ye aittir.
Karar **D1** gereği **byte-byte dondurulmuşlardır**: mevcut demo çalışmaya devam
etsin diye dururlar, düzeltme almazlar ve P5.3 cut-over'ında kaldırılacaklardır.
`test/legacy/` davranışlarını sabitler, `foundry.toml` ve `slither.config.json`
onları biçimlendirme ve statik analiz kapsamının dışında tutar.

> ⚠️ Bu kontratlarda **kalıcı para kilitlenmesine** yol açan doğrulanmış açıklar
> vardır. Zincir üzerinde kanıtlanmış ayrıntı:
> [`docs/contract-analysis-v1.0.md`](docs/contract-analysis-v1.0.md).
> Yeni geliştirme yalnızca V1 üzerinde yapılır.

---

## 9) Dosya haritası

```text
contracts/
├── src/
│   ├── v1/                     aktif gelistirme
│   │   ├── access/             ProtocolAccessManager
│   │   ├── config/             ProtocolConfig, BaselineParams
│   │   ├── vault/              SettlementVault
│   │   ├── registry/           CourierRegistry
│   │   ├── hub/                DeliveryHub
│   │   ├── risk/               CoverageQuote, RiskQuoteVerifier
│   │   ├── proof/              PickupProof, PickupProofVerifier
│   │   └── interfaces/         ISettlementVault
│   └── *.sol                   devralinan (dondurulmus, bkz. sec. 8)
├── script/
│   ├── v1/DeployCore.s.sol     V1 deploy (rol ayrilik korumalari)
│   └── Deploy*.s.sol           devralinan deploy
├── test/
│   ├── v1/                     V1 testleri + invariant/
│   └── legacy/                 devralinan regresyon agi
├── deployments/10143.json      adres manifesti (tek gercek kaynak)
├── exports/                    URETILEN: frontend/backend paketi
├── tools/build-exports.mjs     export ureticisi
├── docs/                       tasarim dokumanlari ve dogrulama gunlugu
├── .gas-snapshot
├── slither.config.json
└── foundry.toml
```
