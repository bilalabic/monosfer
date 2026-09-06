# Frontend / Backend Entegrasyonu: Adresler, ABI'lar, Tipler

> Kalıcı referans. Kaynak: `contracts/deployments/`, `contracts/tools/build-exports.mjs`, `contracts/exports/`
> Baseline: §34 (on-chain/off-chain sınırı), §40 (işlem UX ve hata ayrımı), plan kararı **D3**

---

## 1. Çözülen sorun

Adresler üç ayrı yerde elle tutuluyordu ve **birbirinden kaymıştı**:

| Yer | Ne tutuyordu |
|---|---|
| `frontend/app/config/chain.ts` | Modüler sistemin 5 adresi (sabit kodlanmış) |
| `frontend/.env` | `VITE_DELIVERA_ADDRESS` — **farklı** bir kontratın adresi |
| `contracts/README.md` §9 | Üçüncü bir kopya |

Üstelik hiçbir yerde ABI yoktu; frontend ve backend hiçbir kontrat çağrısını
çözemiyordu.

---

## 2. Yaklaşım (D3: katmanlı)

```text
contracts/deployments/<chainId>.json     tek gerçek kaynak (commit'li, incelenebilir)
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
Commit'lemek, tüketicilerin ek bir kurulum adımı olmadan çalışmasını sağlar ve
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

### Hata ayrımı (§40)

`ABIS.<Kontrat>` custom error tanımlarını içerir, böylece viem'in
`decodeErrorResult`'ı revert'i isimlendirebilir:

```js
// ornek: SettlementVault.NothingToClaim, CourierRegistry.CooldownNotElapsed,
//        ProtocolConfig.ProposalNotReady, ProtocolAccessManager.EnforcedPause
```

Bu, §40'ın "yanlış ağ / bayat teklif / yetersiz teminat" ayrımını yapabilmesi
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
