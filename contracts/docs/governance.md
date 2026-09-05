# Yönetişim: Roller, Zaman Kilitleri ve Pause

> Kalıcı referans (sürümsüz, sistem geliştikçe güncellenir).
> Kaynak kontratlar: `src/v1/access/ProtocolAccessManager.sol`, `src/v1/config/ProtocolConfig.sol`
> Baseline: §32.11, §45, §32.1, §48, invariant §33-15
> Faz: P0.2

---

## 1. Rol matrisi

| Rol | Yapabildiği | Yapamadığı |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Rolleri ver/al. Devri iki adımlı ve gecikmeli (min **1 gün**, deploy'da 3 gün). | Pause edemez, config değiştiremez, imzacı döndüremez. |
| `CONFIG_ADMIN_ROLE` | Parametre önerir/uygular, hazine ve randomness adapter önerir/uygular, unpause planlar ve uygular. | **Pause edemez.** |
| `EMERGENCY_ROLE` | **Anında** pause eder. | **Unpause edemez**, config değiştiremez. |
| `SIGNER_ADMIN_ROLE` | Risk-quote ve PoD attestation imzacılarını **anında** döndürür. | Config veya pause'a dokunamaz. |
| `TREASURER_ROLE` | Hazine operasyonları (tüketici kontratlar P0.3+'ta gelecek). | Config veya pause'a dokunamaz. |

**Ayrılık kuralı:** deploy script'i şu çiftlerin aynı adres olmasını **reddeder** —
`DEFAULT_ADMIN`/`CONFIG_ADMIN`, `CONFIG_ADMIN`/`EMERGENCY`, `CONFIG_ADMIN`/`SIGNER_ADMIN`,
`DEFAULT_ADMIN`/`EMERGENCY`, ve iki imzacı birbirinden. Legacy script'lerde hazine,
ödül havuzu ve tüm sahiplikler tek deployer EOA'sıydı (§32.11 ihlali); burada bu
yapısal olarak imkânsız.

Deploy script'i rolleri **vermez**. Sadece `DEFAULT_ADMIN`'i atar; diğer roller
multisig'in kendisi tarafından verilir, böylece deployer anahtarı hiçbir zaman
operasyonel rol taşımaz.

---

## 2. Neden zamanlama asimetrik?

Tekrar eden tasarım kararı: **koruma sağlayan işlem hızlı, korumayı kaldıran işlem yavaş.**

| İşlem | Zamanlama | Gerekçe |
|---|---|---|
| `pause()` | **Anında** | Saldırı sırasında beklemek zarar demektir. |
| `unpause()` | **6 saat planlama** | Korumayı kaldırır. Ele geçirilmiş tek anahtar, pause'u açıldığı anda kapatamamalı. |
| Parametre değişikliği | **Zaman kilitli** (1 saat–30 gün, deploy'da 2 gün) | Kullanıcı parasını etkiler; önceden gözlemlenebilir olmalı. |
| Hazine / randomness adapter | **Zaman kilitli** | Aynı gerekçe. |
| İmzacı döndürme | **Anında** | Döndürme sebebi genelde anahtarın ele geçirilmiş olmasıdır; beklemek maruziyeti uzatır. **Karşı önlem: `SIGNER_ADMIN_ROLE` multisig olmalı.** |

`pause()` çağrısı bekleyen unpause planını **sıfırlar** — yeni bir pause, eski planı
devralmaz.

---

## 3. Parametre sınırları

Her sayısal parametrenin derleme-zamanı MIN/MAX sabiti vardır. Doğrulama hem öneri
hem de **uygulama** anında çalışır, böylece daha önce yapılmış bir öneri sonradan
sınır dışına kaçamaz.

| Parametre | Sınır | §48 değeri |
|---|---|---|
| `protocolFeeBps` | ≤ 1.000 (%10 tavan) | 200 (%2) |
| `coverageBps` R1/R2/R3 | ≤ 10.000 ve **R1 ≤ R2 ≤ R3** | 2.500 / 6.000 / 10.000 |
| `maxActiveCustody` | 1–10 | 1 |
| `customerMaxActiveListings` | 1–50 | 5 |
| Jüri boyutları | 3–15, **tek sayı**, ve **kesin artan** | 3 / 5 / 7 |
| `fundingWindow` | 5 dk – 24 sa | 15 dk |
| `challengeWindow` | 1 sa – 7 gün | 24 sa |
| `courierWithdrawalCooldown` | ≤ 30 gün | 24 sa |
| `riskQuoteValidity` | 1 dk – 1 sa | 5 dk |
| `podAttestationValidity` | 1 dk – 1 sa | 10 dk |
| `rewardClaimWindow` | 7 – 365 gün | 90 gün |
| `rewardReclaimDelay` | 1 – 90 gün | 7 gün |
| `courierBaseDeposit` | 0.001 – 1.000 MON | 10 MON |
| Jüri ekonomisi | **`nonRevealSlash` ≤ `jurorLockPerCase` ≤ `minJurorStake`** | 1 / 2 / 10 MON |

Çapraz-alan kuralları (kapsam sıralaması, jüri sıralaması, jüri ekonomisi) tek tek
setter'larla garanti edilemeyeceği için parametreler **atomik bir küme** olarak
değişir.

---

## 4. Runbook

### Parametre değiştirme

```bash
# 1) CONFIG_ADMIN multisig'inden öner
cast send $CONFIG "proposeParams(...)" ...
# 2) configTimelock kadar bekle (deploy'da 2 gün)
# 3) uygula — sınırlar yeniden doğrulanır
cast send $CONFIG "executeParams()" ...
```

Yanlış öneri verildiyse: `cancelParamsProposal()`.

### Acil durum

```bash
# EMERGENCY multisig'inden — anında
cast send $ACCESS "pause()" ...
```

Geri açmak **iki adım** ve 6 saat sürer:

```bash
cast send $ACCESS "scheduleUnpause()" ...   # CONFIG_ADMIN
# 6 saat bekle
cast send $ACCESS "unpause()" ...           # CONFIG_ADMIN
```

`unpauseReadyAt()` planlanan zamanı, `paused()` mevcut durumu döner.

### İmzacı ele geçirildiyse

```bash
# SIGNER_ADMIN multisig'inden — anında, bekleme yok
cast send $CONFIG "rotateRiskQuoteSigner(address)" $NEW ...
cast send $CONFIG "rotatePodAttestationSigner(address)" $NEW ...
```

---

## 5. Deploy

```bash
DEFAULT_ADMIN=... CONFIG_ADMIN=... EMERGENCY_ADMIN=... SIGNER_ADMIN=... \
TREASURER=... TREASURY=... RISK_QUOTE_SIGNER=... POD_ATTESTATION_SIGNER=... \
EXPECTED_CHAIN_ID=10143 \
forge script script/v1/DeployCore.s.sol:DeployCoreScript --rpc-url monad_testnet --broadcast
```

Script şu durumlarda **deploy etmeden** durur: eksik rol adresi
(`RoleAddressMissing`), kritik rollerin aynı adresi paylaşması
(`CriticalRolesShareAnAddress`), yanlış ağ (`WrongChain`).

---

## 6. Bilinen açık kararlar

- **Yükseltilebilirlik:** kontratlar şu an **immutable**. Baseline bu konuda sessiz;
  §32 proxy listelemiyor. Testnet'te yeniden deploy ucuz. UUPS isteniyorsa şimdi
  karar verilmeli — sonradan geçmek depolama düzeni kısıtları getirir.
- **Multisig:** roller şu an EOA olabilir. §45 kritik kontrol için multisig şart
  koşuyor; testnet deploy'undan önce Safe kurulmalı (plan kararı **D5**).
- **CI kapsamı:** `contracts.yml` henüz V1 deploy script'inin dry-run'ını
  içermiyor; CI'a dokunulmaması istendiği için eklenmedi.
