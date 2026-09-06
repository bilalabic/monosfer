# V1 Çekirdek — Monad Testnet Doğrulama Raporu (P0.1–P0.3)

> **Ağ:** Monad Testnet (`chain-id 10143`) · **Toolchain:** Foundry `1.8.1`, OZ `5.7.0`
> **Kapsam:** `ProtocolAccessManager` + `ProtocolConfig` + `SettlementVault`
> **Tarih:** 6 Eylül 2026

---

## 1. Yeniden test ve tutarsızlık taraması

P0.3 ve öncesi temiz build'den yeniden koşuldu: **86/86 test, 7/7 gate**.

Ardından sistematik tutarsızlık taraması yapıldı ve **üç gerçek sorun** bulunup düzeltildi:

| # | Bulgu | Neden önemliydi | Düzeltme |
|---|---|---|---|
| 1 | **§48 tablosu iki yerde yazılıydı** (`test/v1/helpers/BaselineParams.sol` ve `script/v1/DeployCore.s.sol`) | Testler kendi kopyasını doğrularken deploy farklı değer gönderebilirdi — sessiz kayma riski | Tek kaynak: `src/v1/config/BaselineParams.sol`. Hem test hem deploy oradan okuyor. |
| 2 | `SettlementVault.NotController` tanımlı ama hiç kullanılmıyor | Ölü kod; okuyucuya var olmayan bir hata yolu düşündürür | Kaldırıldı (rol kontrolü OZ hatasıyla revert ediyor) |
| 3 | `MIN_PROTOCOL_FEE_BPS`, `MIN_COVERAGE_BPS`, `MIN_WITHDRAWAL_COOLDOWN` tanımlı ama hiçbir kontrol okumuyor | Hepsi 0; tip zaten garanti ediyor. Okunmayan bir `MIN_` sabiti **var olmayan bir doğrulama varmış izlenimi** verir | Kaldırıldı, gerekçe yorumda |

Düzeltme sonrası yeniden: **86/86 test, 7/7 gate.** `grep "protocolFeeBps: 200"` artık **tek dosya** döndürüyor.

---

## 2. Testnet deploy

| Kontrat | Adres |
|---|---|
| `ProtocolAccessManager` | [`0x8bC4c4786053A6b5C8b137595B6C642DF6aB58CB`](https://testnet.monadexplorer.com/address/0x8bC4c4786053A6b5C8b137595B6C642DF6aB58CB) |
| `ProtocolConfig` | [`0xA086F1443A0b0406f4C6238e8C7Da9F75F86Ba18`](https://testnet.monadexplorer.com/address/0xA086F1443A0b0406f4C6238e8C7Da9F75F86Ba18) |
| `SettlementVault` | [`0xDB9CaC561cd83b0312A75416C652303A83161173`](https://testnet.monadexplorer.com/address/0xDB9CaC561cd83b0312A75416C652303A83161173) |

**Rol ayrılığı gerçek adreslerle:** deploy script'i beş ayrı hesap talep etti ve
aldı — `DEFAULT_ADMIN`, `CONFIG_ADMIN`, `EMERGENCY`, `SIGNER_ADMIN`,
`VAULT_CONTROLLER`. Legacy'deki "hepsi deployer EOA'sı" durumu artık yapısal
olarak imkânsız (§32.11).

`ADMIN_TRANSFER_DELAY=1 gün`, `CONFIG_TIMELOCK=1 saat` (ikisi de sözleşmenin
izin verdiği minimum; testnet iterasyonu için).

### Zincirde doğrulanan bağlantı ve parametreler

`config.accessManager == AM` ✔ · `vault.accessManager == AM` ✔ · vault boş (yükümlülük 0) ✔

| Parametre | Zincirdeki değer | §48 |
|---|---|---|
| `protocolFeeBps` | 200 | %2 ✔ |
| `courierBaseDeposit` | 10 MON | 10 MON ✔ |
| `maxActiveCustody` | 1 | 1 ✔ |
| `fundingWindow` | 900 sn | 15 dk ✔ |
| `challengeWindow` | 86.400 sn | 24 sa ✔ |
| Coverage R1/R2/R3 | 2500 / 6000 / 10000 | %25/%60/%100 ✔ |
| `configVersion` | 1 | — |
| R4 | **revert** | devre dışı ✔ |

---

## 3. Koşulan senaryolar — 10/10

### S1–S3 · Roller
- `DEFAULT_ADMIN` dört rolü de verdi ✔
- `CONFIG_ADMIN`'in başkasına `EMERGENCY` vermesi **reddedildi** ✔
- Zincirde: `configAdmin` `CONFIG_ADMIN`'e sahip, `EMERGENCY`'ye **sahip değil** ✔

### S4 · Vault tam akışı
`lock 0.05 MON` → `release (%98 kurye / %2 hazine)` → `claim`

**Kritik gözlem:** release sırasında vault bakiyesi **hiç değişmedi** — uzlaşma
gerçekten sadece defter kaydı. `claimable` 0.049 / 0.001 olarak tam bölündü,
`totalLocked` sıfırlandı.

### S5 · `claimFor` yönü
Çağıran controller'dı, para **kuryeye** gitti (0 → 0.049 MON), çağırana değil ✔
Çift claim **reddedildi** ✔ Ödeme gücü korundu ✔

### S6 · [PoC-D] — legacy'yi kilitleyen senaryo
Ödemenin yarısı, MON kabul etmeyen bir kontrata yönlendirildi.

| | Legacy | V1 (testnet, ölçüldü) |
|---|---|---|
| `release` | Kalıcı revert, herkes bloke | **Başarılı** |
| Sağlam alıcı | Parasını alamaz | **Tam aldı** (0 → 0.02 MON) |
| Kötü alıcı | Herkesi kilitler | Sadece kendi claim'i reddedildi |
| Kötü alıcının parası | Kalıcı kayıp | **Bakiyesi duruyor** (0.02 MON) |
| Ödeme gücü | — | Korundu |

### S7 · Config zaman kilidi
Yetkisiz öneri reddedildi ✔ · `CONFIG_ADMIN` öneri verdi ✔ ·
**Anında uygulama reddedildi** ✔ · fee 200'de, sürüm 1'de kaldı ✔ · iptal çalıştı ✔

### S8 · Parametre sınırları
%50 komisyon önerisi (tavan %10) **reddedildi** ✔

### S9 · İmzacı döndürme
`SIGNER_ADMIN` anında döndürdü ✔ · `CONFIG_ADMIN` **döndüremedi** ✔

### S10 · Pause
- `CONFIG_ADMIN` pause **edemedi** (rol ayrımı) ✔
- `EMERGENCY` anında pause etti ✔
- Yeni `lock` **bloke** ✔
- **`claim` çalışmaya devam etti** — kullanıcı 0.02 MON'unu çekti (§45 güvenli çıkış) ✔
- `EMERGENCY` unpause **planlayamadı** ✔
- `CONFIG_ADMIN` planladı; `unpauseReadyAt − şimdi = 21.599 sn ≈ 6 saat` ✔
- **Erken unpause reddedildi** ✔

---

## 4. Testnet'te doğrulanamayanlar (dürüst sınır)

Zaman kilitlerinin **başarılı** yolu tek oturumda test edilemez:

| Senaryo | Neden | Nerede doğrulandı |
|---|---|---|
| `executeParams` zaman kilidi dolduktan sonra | 1 saat beklemek gerek | Yerel testte `vm.warp` ile (`test_Execute_RequiresTimelockToElapse`) |
| `unpause` 6 saat sonra | 6 saat beklemek gerek | Yerel testte (`test_Unpause_RequiresDelayToElapse`) |

Testnet'te **reddedilme** yolları doğrulandı; bu zaten kilidin gerçekten
uygulandığını kanıtlıyor.

**Not:** protokol şu an testnet'te **paused** durumda. `CONFIG_ADMIN`
6 saat sonra `unpause()` çağırarak açabilir; test dağıtımı olduğu için
bırakıldı.

---

## 5. Bitiş durumu

- Vault: bakiye = yükümlülük = 0.021 MON, surplus 0, **ödeme gücü korunuyor**.
- Yerel: **86/86 test, 7/7 gate**.
- Legacy kaynaklar 8/8 byte-byte değişmedi.
- `main` ve `Monosfer-V2` dokunulmadı; branch zinciri P0.1 → P0.2 → P0.3.
- Deployer bakiye 84.49 → 80.90 MON (tüm testnet doğrulaması ~3.6 MON).

**Sırada:** P0.4 `CourierRegistry` — stake yatırma/çekme/çıkış (24 sa cooldown),
C0/C1/C2 seviyeleri, askıya alma, `MAX_ACTIVE_CUSTODY` sayacı. `[PoC-B]`'yi
(kurye stake'i kalıcı kilitli) kapatır.
