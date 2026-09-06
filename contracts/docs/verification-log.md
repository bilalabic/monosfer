# Doğrulama Günlüğü

> Kalıcı kayıt. Her faz tamamlandığında bir bölüm eklenir.
> Faz başına ayrı rapor tutulmuyordu; altı ayrı dosya süreç gürültüsü yarattığı
> için tek bir günlükte birleştirildi.

**Ortak yöntem —** her faz aynı döngüden geçer:
yaz → yerelde test et → tutarsızlık tara → gate'leri koş → Monad testnet'e deploy
et → senaryoları koş → dokümante et.

**Kapı seti (7):** `forge build` · `forge fmt --check` · `forge test` ·
`forge snapshot --check` · `slither` · 2× legacy deploy dry-run.

---

## Kümülatif durum

| | |
|---|---|
| Test | **154/154** |
| Gate | **7/7** |
| Invariant | **21** (4 suite) |
| Legacy kaynaklar | **8/8 byte-byte değişmedi** |
| Toolchain | Foundry `1.8.1`, OpenZeppelin `5.7.0`, Slither `0.11.6` |

| Faz | Konu | Durum |
|---|---|---|
| P0.1 | CI, regresyon ağı, gas baseline | Tamamlandı |
| P0.2 | `ProtocolAccessManager` + `ProtocolConfig` | Tamamlandı |
| P0.3 | `SettlementVault` | Tamamlandı |
| P0.4 | `CourierRegistry` | Tamamlandı |
| P1.1 | `DeliveryHub` | Tamamlandı |
| P1.3 | İmzalı risk teklifi, kapsam | Tamamlandı |
| P2 | Pickup/PoD kanıtları | Sırada |

---

## P0.1 — CI, regresyon ağı, gas baseline

Kontratlar hiç CI'da derlenmiyordu; tek workflow uygulamayı SSH ile deploy
ediyordu. `.github/workflows/contracts.yml` eklendi, legacy testler
`test/legacy/`'ye taşındı (sadece 6 import satırı değişti — gas birebir aynı
kaldı, taşımanın davranışsal olarak nötr olduğunun kanıtı).

**Gate etkinliği ölçüldü:** her kapı kasten bozulup geri alındı — bozuk test,
formatsız dosya, reentrancy'li kontrat, kurcalanmış gas değeri. Dördü de kırmızı
yandı. Hiç kırmızıya dönmeyen kapı, kapı değildir.

**Toolchain yükseltmesi:** Foundry 1.5.1 → 1.8.1 (baseline sec. 53 `>= 1.8.0` öneriyor).
Gas ölçümleri kontrat değişmeden %25–61 arttı — bu regresyon değil, Foundry'nin
ölçüm yöntemi değişikliği; canlı zincirde davranış birebir aynı kaldı. Sonuç:
`.gas-snapshot` yalnızca **pinlenmiş sürüm içinde** anlamlıdır.

**Legacy Slither baseline:** 48 bulgu (0 high / 6 medium / 29 low / 7 info /
6 opt). D1 gereği düzeltilemedikleri için filtreleniyor ve
[`static-analysis-baseline.md`](static-analysis-baseline.md)'de kayıtlı.

---

## P0.2 — ProtocolAccessManager + ProtocolConfig

Dört ayrık rol, **anında pause / 6 saat gecikmeli unpause**, sec. 48'in 20
parametresi derleme-zamanı MIN/MAX sınırlarıyla, zaman kilidi ve monotonik
sürümleme. Doğrulama hem öneri hem **uygulama** anında çalışır, böylece daha önce
verilmiş bir öneri sonradan sınır dışına kaçamaz.

**Tasarımdaki tekrar eden karar:** koruma sağlayan işlem hızlı, korumayı kaldıran
işlem yavaş. Ayrıntı: [`governance.md`](governance.md).

**Yakalanan iki test hatası (kontrat değil):**
1. Eklediğim boşluk güvencesi kırmızı yandı: fuzzer'ın rastgele parametreleri hep
   sınır dışı olduğu için hiçbir öneri kabul edilmiyor, config hiç değişmiyor ve
   diğer 5 invariant **hiçbir şey kanıtlamadan** yeşil görünüyordu. Handler'da
   değerler yasal aralığa çekildi; reddedilme yolu ayrı tutuldu.
2. Dört test `vm.prank`/`vm.expectRevert` sonrası ilk çağrının bir view olması
   yüzünden yanlış sonuç veriyordu.

---

## P0.3 — SettlementVault

**Legacy'nin en ciddi açığı burada kapandı.** Legacy uzlaşma değeri **iterek**
ödüyor ve `require(ok)` ile koruyordu: tek bir alıcı MON kabul etmezse
`confirmDelivery` kalıcı revert eder, kuryenin ödemesi ve müşterinin escrow'u
donardı.

V1'de uzlaşma **sadece defter kaydıdır** — `releaseLock` hiçbir dış çağrı yapmaz.
Değer tek bir yerden çıkar (`_payOut`), oraya da yalnızca kişi kendi parasını
çekerken gelinir. Ayrıntı: [`settlement.md`](settlement.md).

| | Legacy | V1 |
|---|---|---|
| Uzlaşmada dış çağrı | 3 | **0** |
| Bir alıcı reddederse | Herkes bloke, para kalıcı kilitli | Sadece o alıcı çekemiyor, bakiyesi durur |

**Ödeme gücü invariant'ı 65.536 çağrıda hiç kırılmadı** (planın istediği 10k'nın
6 katı). Değer korunumu vault'un kendi sayaçlarına değil, dışarıdan gözlenen akışa
karşı ölçülüyor — böylece vault kendi yanlış rakamlarıyla tutarlı olarak testi
geçemez.

Ayrıca doğrulandı: reentrancy reddediliyor, gas yakan alıcı krediyi engelleyemiyor,
pause'da `claim` her zaman açık (sec. 45 güvenli çıkış), zorla gönderilen değer
muhasebeyi bozmuyor.

---

## P0.4 — CourierRegistry

Stake, C0/C1/C2 doğrulama seviyeleri, askıya alma, teminat rezervasyonu ve
fiziksel custody. Registry **hiç değer tutmaz**; stake vault'ta, kurye başına bir
kilitte durur — protokolün tamamı için tek ödeme gücü invariant'ı.

`stake = available + reserved + pendingWithdrawal`. Çekim talebinin ayrı kalem
olması, kuryenin çıkış talebi verip aynı MON'u bekleme süresince teminat olarak
kullanmasını engeller (sec. 8.3).

**`[PoC-B]` kapandı:** legacy `Delivera`'da `withdrawStake` hiç yoktu ve
`DeliveryEscrow`'da `isRegisteredCourier` tek yönlü bayraktı. Artık teminatı ve
elinde paketi olmayan kurye tüm stake'ini geri alabiliyor; kayıt durumu bayraktan
değil **stake'ten türetiliyor**.

**Yakalanan iki tasarım hatası:**
1. `stakeLockId` registry adresini içermiyordu. K-1'de immutable + yeniden-deploy
   dendiği için yeni bir registry eski vault'la aynı kilit id'sini türetir ve o
   kurye için hiç kilit açamazdı. `address(this)` eklendi + regresyon testi.
2. Vault'ta kısmi çekim yoktu. `releaseLock`'un "toplam kilide tam eşit olmalı"
   kuralı teslimat için doğru bir güvenlik özelliği ama stake çekimi için uygun
   değil. `releasePartial` eklendi; katı kural teslimat yolunda korundu.

---

## P1.1 — DeliveryHub

11 durumlu yaşam döngüsü, teklif yönetimi, iki taraflı fonlama ve uzlaşma.
Ayrıntı: [`delivery-lifecycle.md`](delivery-lifecycle.md).

**`[PoC-A]` yapısal olarak kapandı.** Legacy bütçeyi oluşturma anında escrow'a
alıyordu; teklif gelmezse çıkış yoktu. Burada oluşturma **para almaz** — fonlama
seçimden sonra başlar (sec. 10), yani "oluşturuldu ama terk edildi" sınıfı yamanmadı,
ortadan kalktı. Testnet'te doğrulandı: oluşturmada vault bakiyesi hiç değişmedi.

**`[PoC-C]` kapandı.** Self-dealing hem teklif hem seçim adımında reddediliyor.

**Sınırsız döngü kaldırıldı.** Legacy `acceptBid` teklif listesini dolaşıyordu.
Burada kaybeden kuryeler kendi rezervasyonlarını serbest bırakır; seçim üç
teklifle de üç bin teklifle de aynı gası harcar (sec. 45).

**Yakalanan üç test hatası (kontrat değil):**
1. `vm.prank` sonrası view çağrısı prank'i yutuyordu — bu tuzak dört kez tekrarladı;
   ardından tüm test dosyaları sistematik olarak tarandı, başka örnek çıkmadı.
2. Boşluk güvencesi kırmızı yandı: kuryeler stake'siz kaldığı için teslimatlar
   `Bidding`'i geçemiyor, diğer invariant'lar **boşuna** geçiyordu. Düzeltince
   `invariant_AllDeliveriesCanBeDrivenTerminal` gerçekten çalışmaya başladı.
3. Invariant fonksiyonu içinde `vm.warp(block.timestamp + delta)` ilk turdan sonra
   ilerlemiyordu; mutlak zaman damgasıyla düzeltildi.

## P1.3 — İmzalı risk teklifi

P1.1'de müşteri hem risk katmanını hem teminatı kendisi seçebiliyordu; R3 bir
teslimat 1 wei teminatla açılabilirdi. Artık ikisi de imzalı bir tekliften geliyor.

**Asıl tasarım kararı:** imza gerekli ama yeterli değil. Yalnızca imza istemek
güveni taşırdı, azaltmazdı — anahtarı tutan herkes sıfır teminat fiyatlayabilirdi.
Bu yüzden her teklif zincirin kendi hesapladığı bir banda karşı da kontrol edilir.
Ele geçirilmiş bir imzacı yanlış fiyatlayabilir, **teminatı kaldıramaz**.
Ayrıntı: [`risk-quote.md`](risk-quote.md).

**Slither üç bulgu çıkardı, üçü de düzeltildi:**
1. `divide-before-multiply` — band sınırları önce baseline'ı bölüp sonra çarpanı
   uyguluyordu, yani iki kez yuvarlıyordu. Tek bölmeye indirildi; kabul aralığı
   artık yuvarlamaya değil politikaya bağlı.
2. `shadowing-state` — hub, miras aldığı sabiti gölgeliyordu.
3. `reentrancy-benign` — iptal yolunda durum, dış çağrılardan sonra yazılıyordu;
   sıralama CEI'ye çekildi.

**Cheatcode tuzağının beşinci varyantı:** bu kez view çağrısı `_create(q, signQuote(...))`
içinde **argüman** olarak `vm.expectRevert`'i yutuyordu. Tarama deseni bu biçimi de
yakalayacak şekilde genişletildi; tüm test dosyaları yeniden tarandı, başka örnek yok.

## P2.1 — Teslim alma kanıtı

`confirmPickup` tek taraflı bir iddiaydı: kurye kendi teslim almasını beyan
ediyordu. Artık kurye işlemi gönderiyor, **gönderen imzalıyor** (sec. 12).

sec. 12'nin altı kontrolü ayrı ayrı zorunlu: teslimat, aksiyon, kurye, süre,
nonce, imzacı. `SignatureChecker` ile ERC-1271 gönderen EOA gibi çalışıyor.

**Testlerin gerçekten ısırdığı mutasyonla ölçüldü.** Altı kontrolün her biri tek
tek koddan çıkarıldı:

| Kaldırılan kontrol | Kırılan unit test |
|---|---|
| Nonce yakma | 6 |
| İmza doğrulama | 16 |
| Aksiyon | 2 |
| Teslimat kimliği | 4 |

### Bu sırada yakalanan iki boş invariant

1. **Fuzzer hiçbir teslimatı `Bidding`'den ileri götüremiyormuş.** Handler
   kuryeleri yalnızca C1'di; tier-2 ve tier-3 teslimatlara teklif veremiyorlardı,
   dolayısıyla seçim hiç gerçekleşmiyordu. Seçim sonrasındaki tüm invariant'lar
   **boş yere yeşildi**. Kurulumda kuryeler C2'ye yükseltildi.

2. **Rastgele diziler tam yaşam döngüsünü kurmuyor.** create → bid → select →
   fund → fund zincirinin aynı teslimatta hizalanma olasılığı pratikte sıfır.
   Handler'a `bootstrapReadyForPickup` eklendi; her adım gerçek giriş
   noktalarından ve gerçek yetkiyle geçiyor, hiçbir kontrol atlanmıyor.

3. **Tekrar saldırısı yanlış kurgulanmıştı.** Aynı kabulü ikinci kez göndermek
   durum makinesinde takılır, nonce kontrolüne hiç varmaz. Nonce korumasına
   gerçekten ulaşan saldırı, **harcanmış bir nonce ile yeni ve doğru imzalanmış**
   bir kabul üretmektir. Düzeltildikten sonra nonce yakma satırı kaldırıldığında
   invariant kırmızıya dönüyor — öncesinde dönmüyordu.

### Gas kapısında yakalanan gerçek hata

PR CI'da gas kapısı iki testte düştü (+87 ve −36), yerelde geçiyordu. Sebep
platform değil **çalıştırma bağlamıydı**: `PickupFixture` nonce'u artan bir
sayaçtan üretiyordu, nonce calldata'ya ulaşıyordu, dolayısıyla bir testin ölçülen
gası ondan önce kaç kabul üretildiğine — yani hangi testlerin koştuğuna —
bağlıydı. Snapshot tam suite ile üretilmiş, kapı ise `--no-match-test` filtresiyle
kontrol ediyordu; iki farklı küme, iki farklı sayaç değeri.

Nonce artık argümanlardan türetiliyor. Sonuç, snapshot'taki **181 girdinin
tamamı** için doğrulandı: her test kontratı tek başına koşturulduğunda ölçülen gas
tam suite'tekiyle birebir aynı, ve kapı hem `default` hem `ci` profilinde geçiyor.

Ders: gas kapısı yalnızca kodun fonksiyonu olan ölçümleri içermeli. Fuzz ve
invariant testlerini dışarıda bırakmak yetmiyor; kalan testlerin de birbirinden
bağımsız olması gerekiyor.

---

### Doğrulama araçlarında yakalanan hata

İlk zincir-üstü koşuda geçerli kabul de reddedildi. Sebep kontrat değil, benim
doğrulama script'imdi: **Solidity'de `memory` struct ataması referans kopyalar**,
dolayısıyla `variant = good; variant.x = y;` yazmak `good`'un kendisini bozuyordu.
Her varyant sıfırdan kurulacak şekilde düzeltildi.

Ayrıca `forge script` bu iş için uygun değil: senaryoların çoğu kasten revert
eder, forge ise revert eden bir işlem içeren yığını ne simüle eder ne yayınlar
(`--skip-simulation` ile bile gas tahmininde patlar). Kurulum script'e, negatif
senaryolar açık `--gas-limit` ile `cast send`'e ayrıldı; tek güvenilir sinyal
receipt'teki `status` alanı.

---

## Testnet doğrulaması

Adresler: [`../deployments/10143.json`](../deployments/10143.json)

Koşulan senaryolar (hepsi geçti):

| # | Senaryo | Sonuç |
|---|---|---|
| S1–S3 | Rol verme ve ayrılığı | `DEFAULT_ADMIN` verdi; `CONFIG_ADMIN`'in başkasına `EMERGENCY` vermesi reddedildi |
| S4 | Vault `lock → release → claim` | **Uzlaşmada bakiye hiç değişmedi** — sadece defter kaydı |
| S5 | `claimFor` yönü | Para hesaba gitti, çağırana değil; çift claim reddedildi |
| S6 | **[PoC-D]** reverting alıcı | Uzlaşma başarılı, sağlam alıcı tam ödendi, kötü alıcının bakiyesi korundu |
| S7 | Config zaman kilidi | Anında uygulama reddedildi; fee ve sürüm değişmedi; iptal çalıştı |
| S8 | Parametre sınırları | %50 komisyon önerisi (tavan %10) reddedildi |
| S9 | İmzacı döndürme | `SIGNER_ADMIN` anında döndürdü; `CONFIG_ADMIN` döndüremedi |
| S10 | Pause | `CONFIG_ADMIN` pause edemedi; `EMERGENCY` etti; `lock` bloke, **`claim` açık**; erken unpause reddedildi (6 saat ölçüldü) |
| S11 | Stake ve C0 | 10.1 MON → C0; **registry bakiyesi 0**, vault 10.1 MON |
| S12 | sec. 33-4 teminat | Fazla rezerve reddedildi; rezerveli stake çekilemedi |
| S13 | sec. 33-10 custody | 2. paket reddedildi; paket varken `deregister` reddedildi |
| S14 | Seviyeler / askı | C2 → R3 uygun; R4 devre dışı; askıdayken rezervasyon reddedildi |
| S15 | Çekim cooldown | Beklemeden çekim reddedildi; **bekleyen çekim teminat olarak kullanılamadı** |
| S16 | **[PoC-A]** oluşturma | Vault bakiyesi hiç değişmedi; escrow kilidi 0 |
| S17 | **[PoC-C]** self-dealing | Kendi teslimatına teklif ve kendini seçme, ikisi de reddedildi |
| S18 | Tam yaşam döngüsü | 7 adım; sec. 18.1 uzlaşması birebir: kurye 5 MON, hazine 0.1 MON (%2), müşteri 1 MON |
| S19 | Terminal değişmezliği | Tamamlanmış teslimatta `confirmDelivery`, `poke`, `confirmPickup` — üçü de reddedildi |
| S20 | Poke koruması | Süresi gelmeden `poke` reddedildi; müşteri iptali çalıştı |

**Son durum:** vault bakiye = yükümlülük, surplus 0, **fark 0**.

### P2.1 senaryoları (yeni deploy, 12/12 geçti)

| # | Senaryo | Sonuç |
|---|---|---|
| T1 | Bozuk imza baytı | Reddedildi |
| T2 | **Kuryenin kendi imzası** | Reddedildi — sec. 12'nin kapattığı tek taraflı iddia |
| T3 | Doğru imzalı, yanlış aksiyon | Reddedildi |
| T4 | Doğru imzalı, yanlış kurye | Reddedildi |
| T5 | Doğru imzalı, süresi dolmuş | Reddedildi |
| — | Beş retten sonra durum ve nonce | **Değişmedi**, nonce yanmadı |
| T6 | Gönderenin geçerli kabulü | Kabul edildi; `InTransit`, nonce yandı, custody açıldı |
| T7 | Aynı kabulün tekrarı | Reddedildi |

Kapanış: vault bakiye 32.44 MON = yükümlülük 32.44 MON, surplus 0, **fark 0**.

### Testnet'te doğrulanamayanlar (dürüst sınır)

Zaman kilitlerinin **başarılı** yolu tek oturumda beklenemez: config zaman kilidi
(1 sa), unpause gecikmesi (6 sa), kurye çekim cooldown'ı (24 sa). Testnet'te
**reddedilme** doğrulandı — bu kilidin gerçekten uygulandığını kanıtlar; başarı
yolları yerelde `vm.warp` ile test edildi.

### Monad'a özgü operasyonel bulgu

`depositStake` önce "Signer had insufficient balance" ile reddedildi: kuryede
32 MON, işlem 10 MON. Sebep baseline **sec. 43** — Monad gası harcanan değil,
**`gasLimit × maxFeePerGas`** üzerinden peşin rezerve ediyor ve aracın otomatik
tamponu fazla büyüktü. Açık `--gas-limit` ile çözüldü. Aynı kök sebep rol
hesaplarını da işlem gönderemez hale getirmişti.

**Deploy runbook'una girmesi gereken madde:** Monad'da gas limiti tampon değil,
peşin ödenen bir rezervasyondur.
