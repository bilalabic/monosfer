# MONOSFER Kontratları

Monad Testnet (`chainId 10143`) üzerinde çalışan MONOSFER akıllı kontratları.

Kapsam ve şartname: depo kökündeki
`MONOSFER_Initial_Release_Base_Documentation_v1.0.md`. Bu README'deki `sec. ` atıfları
o dokümana yapılır.

---

## 1) Depoda iki kontrat kümesi var

| | Konum | Durum |
|---|---|---|
| **V1** | `src/v1/` | **Aktif geliştirme.** Baseline sec. 32'deki mimari. |
| **Legacy** | `src/*.sol` | **Dondurulmuş.** Hackathon MVP'si. Değiştirilmez, P5.3 cut-over'ında kaldırılır. |

Legacy kontratlar (`Delivera`, `DeliveryEscrow`, `Leaderboard`, `MCRYToken`,
`ReputationBadge`, `RewardDistributor`) karar **D1** gereği **byte-byte
dondurulmuştur**. Mevcut demo çalışmaya devam etsin diye duruyorlar; üzerlerinde
düzeltme yapılmaz.

> ⚠️ Legacy kontratlarda **kalıcı para kilitlenmesine** yol açan doğrulanmış
> açıklar var (iptal yolu yok, `Delivera`'da stake çekme yok, ödeme iten alıcı
> tüm uzlaşmayı tıkıyor). Ayrıntı ve zincir üzerinde kanıt:
> [`docs/contract-analysis-v1.0.md`](docs/contract-analysis-v1.0.md).
> Yeni geliştirme V1 üzerinde yapılır.

### V1 kontratları

| Kontrat | Sorumluluk | Doküman |
|---|---|---|
| `ProtocolAccessManager` | Roller, acil durum pause, gecikmeli unpause | [governance](docs/governance.md) |
| `ProtocolConfig` | sec. 48 parametreleri, sınırlar, zaman kilidi, sürümleme | [governance](docs/governance.md) |
| `SettlementVault` | Custody, pull-payment uzlaşma, ödeme gücü | [settlement](docs/settlement.md) |
| `CourierRegistry` | Stake, C0/C1/C2, askı, teminat, custody | [courier-registry](docs/courier-registry.md) |

Sıradaki fazlar (`DeliveryHub`, `ReputationRegistry`, `DisputeCourt`, …):
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
| `forge fmt` | Biçimlendir (legacy `foundry.toml` içinde hariç tutulmuştur) |
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
| Deploy dry-run | Her iki legacy script simüle edilir |

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

### Statik analiz baseline

Legacy kontratlar dondurulmuş olduğu için bulguları düzeltilemez. Kabul edilen
baseline (48 bulgu: 0 high, 6 medium) `slither.config.json` ile filtrelenir ve
[`docs/static-analysis-baseline.md`](docs/static-analysis-baseline.md)'de
kayıtlıdır. Filtrelenmiş koşu **0 sonuç** vermelidir; vermiyorsa bulgu yeni kodadır.

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

> Adresleri `chain.ts`, `.env` veya bu README'ye **kopyalamayın**. Daha önce üç
> ayrı kopya vardı ve birbirinden kaymışlardı; bu katman tam olarak onu önlemek
> için var.

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
| `test/legacy/` | Dondurulmuş MVP'nin regresyon ağı. **Değiştirilmeden geçmeye devam etmeli.** |
| `test/v1/` | V1 birim + fuzz testleri |
| `test/v1/invariant/` | Durum-bilgili invariant suiteleri |

Güncel sonuçlar, faz faz özet ve testnet senaryoları:
[`docs/verification-log.md`](docs/verification-log.md).

---

## 8) Dosya haritası

```text
contracts/
├── src/
│   ├── v1/                     aktif gelistirme
│   │   ├── access/             ProtocolAccessManager
│   │   ├── config/             ProtocolConfig, BaselineParams
│   │   ├── vault/              SettlementVault
│   │   ├── registry/           CourierRegistry
│   │   └── interfaces/         ISettlementVault
│   └── *.sol                   legacy (dondurulmus)
├── script/
│   ├── v1/DeployCore.s.sol     V1 deploy (rol ayrilik korumalari)
│   └── Deploy*.s.sol           legacy deploy
├── test/
│   ├── v1/                     V1 testleri + invariant/
│   └── legacy/                 dondurulmus regresyon agi
├── deployments/10143.json      adres manifesti (tek gercek kaynak)
├── exports/                    URETILEN: frontend/backend paketi
├── tools/build-exports.mjs     export ureticisi
├── docs/                       tasarim dokumanlari ve dogrulama gunlugu
├── .gas-snapshot
├── slither.config.json
└── foundry.toml
```
