# Deploy Runbook

> Kapsam: sec. 32.11 (tek bir EOA kritik izinleri kontrol edemez), sec. 45
> (kritik kontrol multisig'de), sec. 31 (yedek komite bir Safe), sec. 6
> (adres/ABI paylaşımı), invariant sec. 33-1.

---

## 1. Sıra neden bu

Deploy üç adım, ve **ikisi farklı anahtarla yapılır**:

```text
1. deployer anahtari  ->  kontratlari deploy eder
2. admin multisig     ->  rolleri verir
3. herkes             ->  VerifyDeployment ile denetler
```

Deployer hiçbir operasyonel rol taşımaz. `DeployCore` yalnızca `DEFAULT_ADMIN`
atar; geri kalan rolleri multisig kendisi verir. sec. 32.11'in kapattığı şey tam
olarak budur: deploy eden anahtar, deploy ettiği sistemi çalıştıramaz.

Bunun bir bedeli var — **adım 1 ile 2 arasında sistem yarım.** Kontratlar var,
kablolama yok. `DeployCore` bu aralığı göremez, çünkü o noktada henüz hiçbir rol
verilmemiştir. Adım 3 tam olarak bu boşluğu kapatır.

---

## 2. Adım 1 — çekirdek

```bash
DEFAULT_ADMIN=... CONFIG_ADMIN=... EMERGENCY_ADMIN=... SIGNER_ADMIN=... \
TREASURER=... TREASURY=... RISK_QUOTE_SIGNER=... POD_ATTESTATION_SIGNER=... \
EXPECTED_CHAIN_ID=10143 \
forge script script/v1/DeployCore.s.sol:DeployCoreScript \
  --rpc-url monad_testnet --broadcast --slow
```

Script şu durumlarda **deploy etmeden durur**: eksik rol adresi, kritik rollerin
aynı adresi paylaşması, yanlış ağ, boş olmayan vault/registry.

## 3. Adım 1b — ihtilaf katmanı

```bash
ACCESS_MANAGER=... PROTOCOL_CONFIG=... DELIVERY_HUB=... REFERRAL=... \
PYTH_ENTROPY=... FALLBACK_SAFE=... EXPECTED_CHAIN_ID=10143 \
forge script script/v1/DeployDispute.s.sol:DeployDisputeScript \
  --rpc-url monad_testnet --broadcast --slow
```

`FALLBACK_SAFE` **bir kontrat olmak zorunda**. EOA verilirse script reddeder:
sec. 31 3-of-5 Safe istiyor ve tek anahtar, her başarısız ihtilafı sonlandırma
gücünü tek elde toplar. Bu kontrol runbook'ta değil kodda, çünkü runbook revert
edemez.

### Safe nasıl kurulur

Safe v1.4.1'in kanonik kontratları Monad testnet'te kurulu. Proxy factory ile
3-of-5 kurulur; `fallbackHandler` **`CompatibilityFallbackHandler` olmalı**,
yoksa ERC-1271 yolu hiç çalışmaz.

| Kontrat | Adres |
|---|---|
| SafeProxyFactory | `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` |
| Safe (L2 singleton) | `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762` |
| CompatibilityFallbackHandler | `0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99` |

---

## 4. Adım 2 — roller

Multisig şunları verir. Hiçbiri deploy script'i tarafından verilmez.

| Rol | Kime |
|---|---|
| `VAULT_CONTROLLER_ROLE` | `CourierRegistry`, `DeliveryHub` |
| `REGISTRY_CONTROLLER_ROLE` | `DeliveryHub` |
| `REPUTATION_REPORTER_ROLE` | `DeliveryHub` |
| `REFERRAL_REPORTER_ROLE` | `DeliveryHub`, `DisputeCourt` |
| `DISPUTE_COURT_ROLE` | `DisputeCourt` |
| `CONFIG_ADMIN_ROLE` | config operatörü |
| `EMERGENCY_ROLE` | acil durum anahtarı |
| `SIGNER_ADMIN_ROLE` | imzacı rotasyonu |
| `TREASURER_ROLE` | hazine operatörü |

`DISPUTE_COURT_ROLE` **yalnızca mahkeme adresine**, asla bir EOA'ya.

---

## 5. Adım 3 — canlı denetim

```bash
ACCESS_MANAGER=... PROTOCOL_CONFIG=... SETTLEMENT_VAULT=... COURIER_REGISTRY=... \
DELIVERY_HUB=... JUROR_POOL=... DISPUTE_COURT=... FALLBACK_COMMITTEE=... \
DEPLOYER=... CONFIG_ADMIN=... EMERGENCY_ADMIN=... SIGNER_ADMIN=... TREASURER=... \
forge script script/v1/VerifyDeployment.s.sol:VerifyDeploymentScript \
  --rpc-url monad_testnet
```

Hiçbir şey broadcast etmez, her zaman koşulabilir. Ne kontrol ettiği:

| Kontrol | Yakaladığı hata |
|---|---|
| Her adreste kod var mı | Yazım hatası; sistem sanılan boş adres |
| İşaretçiler tutarlı mı (11 tane) | Geçen haftanın registry'sine bakan hub |
| Makine rolleri verilmiş mi | Unutulmuş `grantRole` |
| Deployer operasyonel rol taşımıyor mu | sec. 32.11 ihlali |
| Mahkeme vault/registry'ye doğrudan erişemiyor mu | Fazla verilmiş yetki |
| Kritik roller ayrı anahtarlarda mı | Tek anahtarda toplanmış kontrol |
| İki imzacı ayrı mı | Tek sızıntıyla hem fiyat hem teslim kanıtı sahtelenir |
| Vault ve mahkeme ödeme gücünde mi | Invariant sec. 33-1 |
| Komite bir kontrat mı | EOA'ya bağlanmış yedek |

### Ayrışma kontrolü adreslere değil **zincire** sorar

Operatörün verdiği listeyi karşılaştırmak yetmez: listede farklı görünen iki
adresten biri sonradan ikinci bir kritik rol almış olabilir. Kontrol, bilinen her
adayın zincirdeki rollerini okuyup ikisini birden taşıyanı arar.

> Bu kontrolün gerçekten bir şey yakaladığı testnet'te kanıtlandı: `CONFIG_ADMIN`'e geçici
> olarak `EMERGENCY_ROLE` verildi, denetleyici
> `CriticalRolesShared("CONFIG_ADMIN_ROLE", "EMERGENCY_ROLE", 0x88aB…)` ile
> düştü, rol geri alınınca temiz geçti.

---

## 6. Adım 4 — kaynak doğrulama ve manifest

```bash
bash tools/verify-sources.sh              # gonder ve sonucu geri oku
bash tools/verify-sources.sh --check-only # yalnizca durumu raporla
```

Adresler `deployments/<chainId>.json`'dan okunur; manifest tek yetkili kaynak
(sec. 6). Script **gönderim makbuzuna güvenmez**: her adres API'den geri okunur.

> İlk sürümü tek bir `sleep 3` ile sonucu okuyordu ve on üç kontratın sekizini
> "başarısız" diye raporladı — hepsi aslında doğrulanmıştı. Şimdi sınırlı
> yoklama yapıyor. Bir işi bitmeden sonucunu okumak, bu depoda defalarca
> yakalanan aynı hata.

Sonra manifest ve export'lar:

```bash
node tools/build-exports.mjs            # exports/ uret
node tools/build-exports.mjs --check    # surukleme var mi
```

---

## 7. Monad'a özgü: gas limiti bir rezervasyondur

sec. 43 — Monad gası **harcanan** üzerinden değil, `gasLimit × maxFeePerGas`
üzerinden peşin rezerve eder. Aracın otomatik tamponu fazla büyük olduğunda,
bakiyesi yeten bir hesap "insufficient balance" ile reddedilir.

Çözüm: değer gönderen işlemlerde açık `--gas-limit`. Bu, P0.4'te kurye
`depositStake`'ini ve rol hesaplarını işlem gönderemez hâle getiren asıl nedendi.

---

## 8. Ağ manifesti

`deployments/<chainId>.json` her kontrat için adres, deploy işlemi, blok ve
**deploy anındaki commit SHA**'sını tutar. Kaynak doğrulaması `main`'in ucundan
değil **o commit'ten** yapılır: derleyici ayarları zamanla değişir
(`bytecode_hash` sonradan `none` yapıldı) ve farklı bir commit'ten alınan build
zincirdeki kodla eşleşmez.

`legacy: true` taşıyan kontratlar D1 kararıyla dondurulmuştur ve P5.3
cut-over'ında kaldırılacaktır.
