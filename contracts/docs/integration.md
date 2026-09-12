# Frontend / Backend Entegrasyonu: Adresler, ABI'lar, Tipler

> Kalıcı referans. Kaynak: `contracts/deployments/`, `contracts/tools/build-exports.mjs`, `contracts/exports/`
> Baseline: sec. 34 (on-chain/off-chain sınırı), sec. 40 (işlem UX ve hata ayrımı), plan kararı **D3**

---

## 1. Tek yetkili kaynak

Adresler ve ABI'lar **üretilir**, elle yazılmaz. Elle tutulan her kopya zamanla
diğerlerinden ayrışır; bu katman kopyayı ortadan kaldırarak sorunu kaynağında
çözer.

---

## 2. Yaklaşım (D3: katmanlı)

```text
contracts/deployments/<chainId>.json     tek yetkili kaynak (commit'li, incelenebilir)
            +
forge build ciktisi (out/)               ABI'lar
            ↓
contracts/tools/build-exports.mjs        uretici
            ↓
contracts/exports/                       tuketilen paket (commit'li)
   package.json   ESM + tip bildirimi
   index.js       CHAINS, ABIS, getAddress, getChain, explorer yardimcilari
   index.d.ts     TypeScript tipleri
   abis/*.json    ham ABI dosyalari
```

**Neden üretilen dosyalar commit'li:** depoda henüz paket derleme hattı yok.
Commit'lemek hem tüketicilerin ek kurulum adımı olmadan çalışmasını sağlar hem de
her adres değişikliğini **incelenebilir bir diff** haline getirir.

**Neden event topic'leri ve error selector'ları üretilmiyor:** viem, wagmi ve
ethers bunları zaten ABI'dan türetiyor. Bir build script'inde elle yazılmış
keccak, karşılığı olmayan bir risktir.

---

## 3. Kullanım

### Yeniden üretme

```bash
npm run contracts:exports          # forge build + uret
npm run contracts:exports:check    # bayatsa hata ver (CI icin)
```

`--check` modu, `exports/` ile mevcut `deployments/` + ABI çıktısının
uyuşmadığı durumda hata verir. "Kontrat değişti ama artefakt güncellenmedi"
durumunu yakalar.

### Frontend (TypeScript)

```ts
import { getAddress, getChain, ABIS } from '../../contracts/exports/index.js'

const chainId = 10143
const vault = getAddress(chainId, 'SettlementVault')
const { rpcUrl, explorer } = getChain(chainId)

// wagmi / viem
const { data } = useReadContract({
  address: vault,
  abi: ABIS.SettlementVault,
  functionName: 'claimableOf',
  args: [account],
})
```

### Backend (JavaScript)

```js
import { getAddress, ABIS, explorerTxUrl } from '../../contracts/exports/index.js'
```

Paket ESM + `.d.ts` yayınlar: TypeScript frontend tip denetimi alır, JavaScript
backend editör tamamlaması alır.

### Hata ayrımı (sec. 40)

`ABIS.<Kontrat>` custom error tanımlarını içerir, böylece viem'in
`decodeErrorResult`'ı revert'i isimlendirebilir:

```js
// ornek: SettlementVault.NothingToClaim, CourierRegistry.CooldownNotElapsed,
//        ProtocolConfig.ProposalNotReady, ProtocolAccessManager.EnforcedPause
```

Bu, sec. 40'ın "yanlış ağ / bayat teklif / yetersiz teminat" ayrımını yapabilmesi
için gereken temeldir.

---

## 4. Manifest formatı

`contracts/deployments/10143.json`:

```jsonc
{
  "chainId": 10143,
  "name": "monad-testnet",
  "rpcUrl": "https://testnet-rpc.monad.xyz",
  "explorer": "https://testnet.monadexplorer.com",
  "commit": "<deploy anindaki git SHA>",
  "contracts": {
    "SettlementVault": { "address": "0x...", "txHash": "0x...", "block": 60099842 },
    "Delivera":        { "address": "0x...", "legacy": true }
  }
}
```

`legacy: true` olan kontratlar D1 kararıyla dondurulmuştur ve P5.3 cut-over'ında
kaldırılacaktır. Geçiş süresince mevcut uygulamanın çalışmaya devam etmesi için
export ediliyorlar.

## P4 ile eklenenler

`DisputeCourt`, `JurorPool` ve `FallbackCommittee` artık `exports/`'te. Frontend
itiraz durumunu `DisputeCourt.disputeOf` ve `panelOf` ile okur; backend
`ResolvedByCommittee` ve `DisputeSettled` olaylarını dinler.

> **Uyarı:** sec. 31 yedek komitesinin **her kullanımı alarm üretmeli.** Son çare
> canlılık mekanizması rutin yönetim değildir; `ResolvedByCommittee` olayı
> operasyon ekibine bildirim olarak gitmeli.

Henüz `exports/`'te olmayanlar: `ReputationRegistry`, `BadgeSBT`, `Referral`,
`RewardDistributor` (V1 sürümü). P3 kontratları; entegrasyon ihtiyacı doğduğunda
`tools/build-exports.mjs` içindeki `EXPORTED` listesine eklenmeleri yeterli.

### `commit` alanı neden önemli

Kaynak doğrulaması **o commit'ten** build edilerek yapılır, `main`'in ucundan
değil. Derleyici ayarları zamanla değişir — örneğin `bytecode_hash` ayarı
sonradan `none` yapıldı — ve farklı bir commit'ten build almak zincirdeki kodla
eşleşmez. Manifest'teki commit'ten build alındığında bytecode birebir eşleşir.

Yeni bir ağ eklemek: o `chainId` için bir manifest dosyası koy, üreticiyi çalıştır.

---

## 5. Henüz yapılmayanlar

- **Frontend/backend bağlama.** `frontend/app/config/chain.ts` ve `frontend/.env`
  hâlâ eski sabit adresleri taşıyor. Bunları export paketine bağlamak
  `contracts/` dışına çıkar; **onayınız bekleniyor**.
- **CI otomasyonu.** `contracts:exports:check` henüz `contracts.yml`'de değil;
  CI'a dokunulmaması istendiği için eklenmedi.
- **Deploy sonrası otomatik güncelleme.** Manifest şu an deploy sonrası
  `broadcast/` kayıtlarından üretiliyor; bunu deploy script'ine bağlamak P5.2'de.
