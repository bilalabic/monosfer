# Risk Teklifi ve Kapsam Matematiği

> Kalıcı referans. Kaynak: `src/v1/risk/CoverageQuote.sol`, `src/v1/risk/RiskQuoteVerifier.sol`
> Baseline: sec. 6, sec. 8.3, sec. 12, sec. 48, invariant sec. 33-8
> Faz: P1.3

---

## 1. Kapatılan açık

P1.1'de `createDelivery(riskTier, requiredCollateral)` **müşterinin ikisini de
seçmesine** izin veriyordu. Yani R3 (yüksek risk) bir teslimat 1 wei teminatla
açılabilirdi. Risk katmanı sadece bir etiketti; hiçbir şeyi zorlamıyordu.

Artık ikisi de **imzalı bir tekliften** geliyor. Teklif zincir dışında üretilir —
girdiler (beyan edilen değer, rota, geçmiş) zaten zincir dışıdır (sec. 34) — ve
imzalanır ki zincir onları görmeden güvenebilsin.

---

## 2. İmza gerekli, ama yeterli değil

Yalnızca imza istemek güveni **taşırdı**, azaltmazdı: imza anahtarını elinde
tutan herkes her teslimatı sıfır teminatla fiyatlayabilirdi.

Bu yüzden her teklif, zincirin **kendi hesapladığı** bir banda karşı da kontrol
edilir:

```text
baseline = beyanEdilenDeger x katmanKapsamBps / 10.000
izinli   = [ baseline x minCarpan , baseline x maxCarpan ]
```

Risk servisi bu bandın **içinde serbestçe** fiyatlar — itibar indirimi tam olarak
burada yaşar (sec. 8.3) — ve dışına çıkamaz.

> Ele geçirilmiş bir imzacı bir teslimatı **yanlış fiyatlayabilir**;
> teminatı **kaldıramaz**.

Varsayılan band `[0.75x, 1.5x]`; `ProtocolConfig` sınırları `[0.5x, 2x]` ile
kapatır, yani zaman kilitli bir config değişikliği bile bandı bu aralığın dışına
taşıyamaz.

**Hassasiyet notu:** her iki sınır da **tek bir bölme** ile hesaplanır. Önce
baseline'ı bölüp sonra çarpanı uygulamak iki kez yuvarlar ve bandı birkaç wei
kaydırırdı — küçük, ama kabul aralığını politikaya değil yuvarlamaya bağlardı.

---

## 3. Tekrar koruması (invariant sec. 33-8)

EIP-712 digest'i tekrar anahtarıdır: her teklif **bir kez** kullanılır.

| Alan | Neyi engeller |
|---|---|
| `customer` | Bir cüzdana kesilen teklifin başkasınca harcanmasını |
| `salt` | Aynı şartlı iki teklifin aynı digest'e düşmesini |
| `issuedAt` / `expiresAt` | Eski bir fiyatın sonradan kullanılmasını |
| EIP-712 domain (chainId + kontrat) | Başka zincire veya başka deploy'a taşınmasını |

Zincir, imzacının belirttiği pencereyi **kabul etmez, sınırlar**:
`expiresAt - issuedAt` en fazla `riskQuoteValidity` (sec. 48: 5 dk) olabilir.
Aksi halde bir yıl geçerli teklif kesilebilir ve sec. 48 kuralı yalnızca
backend'de yaşardı.

İmzalar `SignatureChecker` ile doğrulanır, yani akıllı-hesap (ERC-1271) bir risk
servisi EOA gibi çalışır (sec. 12).

---

## 4. Teminatın ikiye ayrılması (sec. 8.3)

Kurye fonlarken kapsam ikiye bölünür ve olay olarak raporlanır:

```text
reservedBase   = min(mevcutStake, gerekenKapsam)
additionalBond = gerekenKapsam - reservedBase
```

`reservedBase` kuryenin **zaten sahip olduğu** stake'ten karşılanır; teklif
verirken kilitlenen depozito de buna sayılır, serbest bırakılıp yeniden alınmaz.
`additionalBond` bu teslimat için **eklemesi gereken** kısımdır ve aynı işlemde
gönderilebilir.

Eksik bond gönderilirse işlem `InsufficientBond` ile reddedilir.

---

## 5. Backend'in üretmesi gerekenler

```jsonc
// EIP-712 domain
{ "name": "MONOSFER", "version": "1", "chainId": 10143, "verifyingContract": "<DeliveryHub>" }

// Quote(address customer,uint8 riskTier,uint96 declaredValue,uint96 requiredCoverage,
//       uint64 issuedAt,uint64 expiresAt,bytes32 salt)
```

`hub.quoteDomainSeparator()` ve `hub.hashQuote(quote)` zincirden okunabilir;
backend imzasını doğrulamak için bunları kullanabilir. ABI ve adresler
`contracts/exports/` içinde (bkz. [`integration.md`](integration.md)).

**İmzacı rotasyonu anında yapılır** (`SIGNER_ADMIN_ROLE`) ve eski anahtarla
kesilmiş teklifleri **anında geçersizleştirir** — testle doğrulanmıştır.

---

## 6. Test kapsamı

22 birim/fuzz testi. Kapsananlar:

- Her katmanın kendi baseline'ı (sec. 6)
- Sahte imza, bozuk imza, kurcalanmış kapsam, kurcalanmış katman
- Başka müşteriye kesilmiş teklif
- Tekrar kullanım, farklı `salt` ile bağımsızlık
- Süresi dolmuş teklif, son saniyede geçerli teklif, aşırı uzun pencere, ters pencere
- **İmzalı ama bandın altında/üstünde** fiyatlanmış teklif
- Band kenarlarının ikisi de kabul
- R4 ve katman 0 reddi (sec. 49)
- İmzacı rotasyonu eski teklifleri geçersizleştiriyor
- Domain'in bu deploy'a bağlı olması (sec. 12)
- Fuzz: kabul edilen kapsam **her zaman** bandın içinde
- Fuzz: yapılandırılmış imzacı dışında hiçbir anahtar kabul edilmiyor

Invariant suite'ine `invariant_ForgedQuoteNeverAccepted` eklendi: fuzzer sürekli
sahte imzalı teklif denemesi yapar, hiçbiri teslimat açamaz.
