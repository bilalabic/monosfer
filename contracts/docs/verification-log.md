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
| Test | **414/414** (23 suite) |
| Gate | **7/7** |
| Invariant | **25** (4 suite) |
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
| P2.1 | Teslim alma kanıtı | Tamamlandı |
| P2.2 | Teslim etme kanıtı (PoD) | Tamamlandı |
| P3 | İtibar, rozetler, ödüller, referans | Tamamlandı |
| P4.1 | `JurorPool` + rastgelelik adaptörü | Yerelde tamam, testnet sırada |
| P4.2 | `DisputeCourt` (commit/reveal) | Yerelde tamam, testnet sırada |
| P4.3 | İtirazlar, yedek komite, hüküm settlement | Sırada |

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

**Testlerin bu kuralları gerçekten yakaladığı mutasyon testiyle ölçüldü.** Altı kontrolün her biri tek
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

Bu düzeltmeden sonra CI'da **tek bir** girdi kaldı: fuzz handler'ının
erişilebilirlik probu, platformlar arasında 36 gas oynuyordu. Aynı forge sürümü,
aynı commit SHA, farklı platform binary'si; diğer 180 girdi CI ile birebir
aynıydı, yani sapma protokol kodunda değil test iskelesindeydi.

Problar artık kapının dışında. Ölçtükleri şey handler'ın defter tutması, protokol
değil; ve zaten var oluş sebepleri gasları değil, fuzzer'ın yetkili yolu
katedebildiğini kanıtlamaları. `test_invariant_` önekini taşıyorlar, böylece
kapının mevcut `testFuzz|invariant_` filtresine takılıyorlar ve test olarak
koşmaya devam ediyorlar.

Ders: gas kapısı yalnızca **kodun fonksiyonu olan** ölçümleri içermeli. Fuzz ve
invariant testlerini dışarıda bırakmak yetmiyor — kalan testlerin birbirinden
bağımsız olması, ve test iskelesini ölçen girdilerin hiç bulunmaması gerekiyor.

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

## P2.2 — Teslim etme kanıtı

`submitDeliveryProof` kuryenin beyanıydı. Artık alıcının challenge'ını zincir
dışında doğrulayan **PoD attestation servisinin imzasını** taşıyor (sec. 15).
Zincire sırrın kendisi değil, `challengeHash` taahhüdü düşer.

Yedi kontrolün her biri tek tek koddan çıkarılarak ölçüldü:

| Kaldırılan kontrol | Kırılan birim testi |
|---|---|
| İmza doğrulama | 14 |
| Nonce yakma | 6 |
| Ömür üst sınırı (sec. 48) | 4 |
| Bilinmeyen kanıt tipi | 2 |
| Boş challenge | 2 |
| Kurye | 2 |

`invariant_ForgedPodAttestationNeverAccepted` da imza kontrolü kaldırılınca
kırmızıya döner.

### Yazarken yakalanan iki test hatası

1. **Cheatcode tuzağı, yine.** İmza üretimi `hub`'a bir view çağrısı yapıyor;
   `vm.expectRevert` / `vm.prank` armed iken argüman pozisyonunda değerlendirilince
   cheatcode'u tüketiyor. Beş test "revert etmedi" diye patladı — yani hiçbir şey
   doğrulamıyorlardı. İki fuzz testi ise **geçiyordu**, ama yanlış sebeple: prank
   tükendiği için çağrı kuryeden değil test kontratından gidiyor, `NotCourier` ile
   dönüyordu. Tüm test dosyaları tarandı, kalan yok.

2. **sec. 9 custody limiti.** Üç test aynı kuryeye aynı anda iki paket taşıtmaya
   çalışıyordu. Kontrat haklıydı; testler yeniden kurgulandı — biri artık ikinci
   teslimatı ilan aşamasında bırakıyor, ikisi kanıt sonrası custody'nin kapanmasını
   kullanıyor.

### Doğrulama aracında yakalanan hata

Zincir senaryosu ilk koşuda 12/14 düştü: `cast` çağrısında attestation tuple'ını
**altı alanla** yazmışım, struct yedi alanlı (`challengeHash` düşmüş). Kontratla
ilgisi yoktu; imza düzeltilince geçti. Kalan iki hata ise RPC bağlantısının
kopmasıydı, ayrıca okunup doğrulandı.

---

## P3.1 — İtibar

sec. 19'un ağırlık tablosuyla 0–1000 puan ve **ondan ayrı** bir güven seviyesi.
Ayrı tutulması, tek mükemmel teslimatı olan kuryenin yüzlercesi olanla aynı
okunmasını engelliyor.

**Mutasyon testiyle ölçüldü** — her kural koddan çıkarıldığında test kırılıyor: her kural tek tek koddan çıkarıldı —
deneyime bağlı güven 4, nötr prior 2, iptal cezası 2, rating ağırlığı 2, ihtilaf
cezası 2, zamanındalık ağırlığı 2 test kırdı.

### Yakalanan üç sorun

1. **Hub itibarı hiç yazmıyormuş.** `REPUTATION_REPORTER_ROLE` hiçbir kurulumda
   verilmemişti. Raporlama hata toleranslı olduğu için 249 test yeşil kalıyor ve
   entegrasyonun hiç çalışmadığı görünmüyordu. Teşhis: happy-path testinde
   `ReputationReportFailed` olayı iki kez yayılıyordu. Rol bağlandıktan sonra 0.

2. **İki test boş çıktı.** "Yeni kurye nötr başlar", priorler tam nota çevrilse
   bile geçiyordu. "İptal puanı düşürür" ise aslında başarı oranındaki düşüşü
   ölçüyordu — iptal cezası koddan çıkarılınca hâlâ geçiyordu. İkincisi artık
   iptal edeni iade edenle karşılaştırıyor: aynı başarı oranı, farklı tek bileşen.

3. **Cheatcode tuzağı, altıncı kez.** Bu sefer `{value:}` ifadesinde:
   `registry.depositStake{value: config.courierBaseDeposit() + 20 ether}()`
   satırındaki view çağrısı `vm.prank`'i tüketiyor ve stake kuryeye değil test
   kontratına yatıyordu.

   `tools/cheatcode-scan.py` yazıldı. **İlk hali boş çıktı** — pattern'i yamalarken
   `` gerçek bir backspace karakterine dönüşmüştü, hiçbir şey eşleşmiyordu.
   Bilerek bozulmuş örneklerle test edilip düzeltildi; artık hem argüman hem
   `{value:}` biçimini yakalıyor. Kod tabanında kalan yok.

### CI'ın yakaladığı iki kapı

- **Slither `uninitialized-local`** medium seviye, `fail_on: medium` eşiğini
  tetikliyordu. `_reportOutcome`'daki iki yerel her yolda atanır hale getirildi.
- **Gas kapısı** iki sahte-imza testinde CI ile ayrıştı. Ölçüm, cheatcode'un
  ürettiği imza baytlarına biniyordu — yani protokolün fonksiyonu değildi. Sahte
  imza testinin gerçek imzaya ihtiyacı yok; sabit bir blob aynı şeyi söylüyor ve
  bayt olarak kararlı.

---

## P3 — İtibar, rozetler, ödüller, referans

Üç alt faz: `ReputationRegistry`, `BadgeSBT`, `RewardDistributor` + `Referral`.

**Mutasyonla ölçüldü** — her kural tek tek koddan çıkarıldığında test kırılıyor:
referans döngü tespiti 6, soulbound kilidi ve deneyime bağlı güven 4'er, kalan
on üç kural 2'şer test.

### Gas kapısı: üçüncü kez aynı sebeple kırıldı, bu sefer kökünden çözüldü

CI üç fazda üst üste gas kapısında düştü. Bu turda tek tek yamamak yerine **tüm**
testlerin CI değerlerini çekip yerel snapshot'la karşılaştırdım:

```text
276 ortak test  ->  273 birebir ayni,  3 tanesi 55-64 gas (%0,003-0,006) sapiyor
```

Aynı forge sürümü, aynı commit SHA, farklı platform binary'si; fark yerelde
tekrarlanamıyor. Önceki iki turda tek tek testleri değiştirerek geçtim — ve o
düzeltmelerden biri **aracı memnun etmek için gerçek test kodunu değiştirmekti**
(sahte imzayı sabit bloba çevirmek); yani aracı düzeltmek yerine koda uydurmuşum.

`forge snapshot --check --tolerance 1` CI'a eklendi. Tolerans bir kod farkını
değil platform farkını soğuruyor ve kapının işini görmeye devam ediyor: 40 bin
gaslık bir birim testinde %1 = 400 gas, yani istenmeden eklenen bir cold SLOAD
(2100) kaçmıyor. `foundry.toml`'da karşılığı olmadığı için CI dosyasına dokunmak
gerekti; onay alındı.

### Slither: bu turda iki bulgu

- **`uninitialized-local`** (medium) iki kez: `_reportOutcome` ve `badgesOf`.
  Yereller her yolda açıkça atanır hale getirildi.
- **`arbitrary-send-eth`** (high): `RewardDistributor._payOut`. Hedef
  saldırganın seçebildiği bir adres değil — ya Merkle kanıtıyla **az önce
  doğrulanmış** bir leaf'teki hesap, ya da config'deki hazine. Tasarımı bozmak
  (yalnızca `msg.sender`'a ödemek) keeper'ın talep edenin gasını ödeyebilmesini
  kaldırırdı; bunun yerine tam o satırda gerekçesiyle bastırıldı ve
  [`static-analysis-baseline.md`](static-analysis-baseline.md)'ye kaydedildi.

### Config'de üç eksik getter

`podAttestationValidity`, `rewardClaimWindow`, `rewardReclaimDelay` P0.2'den beri
parametre olarak duruyordu ama dışarıdan okunamıyordu. Üçü de eklendi.

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

### P3 senaryoları (yeni deploy, dokuz kontrat)

**P3.1 — itibar** (önceki deploy, 10/10): geçmişsiz kurye **575**, temiz teslimat
+ 5 yıldız sonrası **901**, güven 10; ikinci puanlama reddedildi.

**P3.2 — rozetler** (13 kontrol, zincirde):

| Kontrol | Sonuç |
|---|---|
| Gerçek teslimat tamamlandı ve kaydedildi | ✓ |
| `FirstDelivery` hak edilmiş, `TenDeliveries` edilmemiş | ✓ |
| Rozet basıldı, **kuryeye** — talep edene değil | ✓ |
| `locked()` true (ERC-5192) | ✓ |

Rozet, uydurulmuş bir itibar kaydına değil **gerçekten yürünen bir teslimata**
dayanıyor.

**P3.3 — ödül ve referans** (15/15, zincirde):

| # | Senaryo | Sonuç |
|---|---|---|
| 1 | Epoch fonlandı, bütçe zincirde göründü | ✓ |
| 2 | Root yayımlandı | ✓ |
| 3 | Talep leaf'teki hesaba ödendi (0.1 MON) | ✓ |
| 4 | Bütçeden yalnızca o kadarı düştü | ✓ |
| 5 | **Çift talep** | `AlreadyClaimed` ile reddedildi |
| 6 | Bütçe içindeki ikinci talep | Geçerli |
| 7–12 | Referans: ödül ayarı, fonlama, kayıt, derinlik 1, kayıt tek başına ödeme yapmıyor | ✓ |
| 13 | **Kendini referans** | `SelfReferral` ile reddedildi |
| 14 | **Döngüsel referans** | `CircularReferral` ile reddedildi |

> `CircularReferral` o günkü koddaki hatanın adı. Denetim geçişinde ata yürüyüşü
> kaldırıldı; döngü artık `RefereesAlreadyAttached` ile, bir adım önce reddediliyor.
> Gerekçesi: `rewards.md`, bölüm 7.

### Doğrulama sırasında çıkan iki şey

- **`forge script` bir işlemi zincirde düşürdü ama `cast run` ile yeniden
  oynatınca "başarılı" dedi** (zincirdeki gasUsed 104 917, replay'de 79 806).
  Zincirdeki durum okumaları üç kez üst üste "inmemiş" dedi ve doğru olan oydu.
  Monad'da gas peşin rezerve edildiği için (sec. 43) büyük `--gas-limit` ile
  gönderilen işlemler bu şekilde davranabiliyor; senaryolar daha küçük limitle
  `cast send`'e taşınınca hepsi geçti.
- **İlk koşuda üç senaryo "FAIL" göründü, üçü de hatalı okumaydı.** `cast call`
  custom error'ları ham selector olarak döndürüyor; ben hata **adını**
  grep'liyordum. Selector karşılaştırmasına çevrilince üçü de doğru hatayla
  reddedildiği görüldü (`0xa9214540`, `0x55e8f70e`, `0x7acaadee`). Aynı sınıf hata
  P2.2'de de çıkmıştı — zincir doğrulamasında **okuma yönteminin kendisi** de
  doğrulanmalı.

### P3.1 senaryoları (yeni deploy, 10/10 + 3 bağımsız okuma)

| # | Senaryo | Sonuç |
|---|---|---|
| R1 | Geçmişsiz kurye | Puan **575** — nötr priorlerin tam beklenen değeri, tam not değil |
| R2 | Güven | 0 — geçmiş yoksa güven yok |
| R3 | Seçim | Atama olarak kaydedildi |
| R4 | Tamamlama | `completed=1`, `onTime=1` (kabul edilen ETA içinde) |
| R5 | Güven arttı | 1/100 teslimat → 10 |
| R6 | Temiz teslimat puanı yükseltti | 575 → 901 |
| R7 | Müşteri puanı | `ratingCount=1`, ortalama 5.0 |
| R8 | Ölçek | Puan 0–1000 aralığında kaldı |
| — | İkinci puanlama | `DeliveryAlreadyRated(0)` ile reddedildi |
| — | Vault | Bakiye = yükümlülük, **fark 0** |

Zincirdeki kayıt birebir: `completed=1, onTime=1, assignments=1, ratingCount=1,
ratingSum=5`, diğer tüm sayaçlar 0.

### Doğrulama sırasında çıkan iki operasyonel not

- **Monad testnet RPC'si kesikli çalışıyor.** Okumalar yeniden deneme sarmalıyla
  yapılmalı; tek seferlik `cast call` sessizce boş dönebiliyor ve bir kontrolü
  yanlışlıkla "başarısız" gösterebiliyor (P2.2'de tam olarak bu oldu).
- **`forge script --gas-limit` hem işlem başına rezervi hem script gövdesinin
  toplam bütçesini belirliyor.** 3M ile tam yaşam döngüsü `ReentrancySentryOOG`
  veriyor; 9M yetiyor. Monad'da bu limit peşin rezerve edildiği için (sec. 43)
  gereğinden büyük seçmek de hesapları işlem gönderemez hale getiriyor.

### P2.2 senaryoları (yeni deploy, 14/14 geçti)

| # | Senaryo | Sonuç |
|---|---|---|
| T1 | Bozuk imza baytı | Reddedildi |
| T2 | Kuryenin kendi imzası | Reddedildi |
| T3 | **Risk-teklifi imzacısının** imzası | Reddedildi — iki güven noktası ayrı |
| T4 | Bilinmeyen kanıt tipi | Reddedildi |
| T5 | Boş `challengeHash` | Reddedildi |
| T6 | sec. 48 ömrünü (600 sn) aşan pencere | Reddedildi |
| T7 | Süresi dolmuş attestation | Reddedildi |
| — | Yedi retten sonra durum ve nonce | **Değişmedi** |
| T8 | Geçerli attestation | Kabul; `DeliveredPending`, nonce yandı, custody kapandı |
| T9 | İkinci kanıt denemesi | Reddedildi |

Kapanış: vault bakiye 13.22 MON = yükümlülük 13.22 MON, surplus 0, **fark 0**.

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

---

## Denetim geçişi — P4 öncesi

P4 kodu yazıldıktan sonra, faza devam etmeden önce V1 yüzeyinin tamamı bağımsız
bir denetimden geçirildi. Altı bulgu ve iki ek not çıktı. Hepsi bu bölümde
kapatıldı; **her düzeltme, düzeltmeyi geri alıp testin kırmızıya döndüğü
görülerek** kanıtlandı.

| # | Ağırlık | Bulgu | Durum |
|---|---|---|---|
| 1 | Critical | Sıfır tutarlı payout bacağı settlement'ı kalıcı olarak kilitliyordu | Kapatıldı |
| 2 | High | `confirmReturn` kanıtsız ödüyordu | Kapatıldı |
| 3 | High | Kapsam < bid depozitosu olduğunda teminat serbest kalmıyordu | Kapatıldı |
| 4 | Medium | Tam çıkıştan sonra kurye geri dönemiyordu (`LockAlreadyExists`) | Kapatıldı |
| 5 | Medium | `Referral` deploy ediliyordu ama `recordQualification`'ı kimse çağırmıyordu | Kapatıldı |
| 6 | Low | Referans döngü koruması eksikti | Kapatıldı |
| — | — | `JurorPool`: koltuk muhasebesi config'i serbest bırakma anında okuyordu | Kapatıldı |
| — | — | `seatPanel`: tek adaylı snapshot'ta sıfıra bölme paniği | Kapatıldı |

### Mutasyon kanıtları

Bir düzeltmenin gerçekten test edildiğini, testin yeşil olması değil; kodu
bozduğunda **kırmızıya dönmesi** gösterir. Her satır çalıştırıldı:

| Mutasyon | Kırılan test |
|---|---|
| Sıfır bacak filtresi kaldırıldı + teminat serbest bırakma daraltıldı | 5/6 (`SettlementEdges`) |
| Stake generation sayacı kaldırıldı | `test_CourierCanReturnAfterAFullExit` |
| `confirmReturn` kanıt kontrolü kaldırıldı | 3 |
| İade beklenen aksiyonu `PICKUP_ACTION` yapıldı | 4 |
| Koltuk tutarı serbest bırakma anında config'den okundu | 3 (`JurorPool`) |
| Draw başına tek koltuk koruması kaldırıldı | 1 |
| `DeliveryHub` nitelenme bildirimini bıraktı | 3 (`ReputationWiring`) |
| Referans 2. kuralı kaldırıldı | 5 — biri fuzz ile gerçek bir döngü kurdu |
| Stride aramadan sabit 3 yapıldı (aralarında asal değil) | 4 (`DisputeCourt`) |
| `size > 1` koruması kaldırıldı | 1 — panik yerine `PanelTooSmall` |
| Snapshot yerine canlı havuz okundu | 1 (`DisputeCourt`) + 4 (`JurorPool`) |

### Testleri güçlendiren düzeltmeler

Denetim üç testi **vacuous** olarak işaretledi; hiçbiri kendi iddiasını
kanıtlamıyordu:

- `test_TerminalStateCannotReopen` üç kez çıplak `vm.expectRevert()` kullanıyordu
  — herhangi bir revert'i, hatta ilgisiz bir sebeple durum kontrolünden önce
  atılanı bile kabul eder. Üçü de adlandırılmış `WrongState` seçicisine bağlandı.
- sec. 33-13 mutasyonları hiçbir testi kırmıyordu. Sebep: stride'ın taşıdığı iddia
  tekrarsızlık değil **kapsama**; tekrarı zaten `isSeated` reddediyor. Kapsama ise
  ancak aday sayısı **bileşik** olduğunda gözlemlenebilir hale geliyor — 3 ve 5
  adayla her stride asallık tesadüfüyle aralarında asal çıkıyor. Dokuz aday /
  dokuz koltuk, sec. 28'in izin verdiği en küçük tek ve bileşik durum.
- sec. 33-18 için tek bir geç gelen yeterli değildi; canlı havuzdan çekilse bile
  o tek kişi seçilmeyebilirdi. Yeni test, draw talep edildikten sonra **aday
  kümesinin tamamını** değiştiriyor.

### Tasarım kararı: yürüyüş yerine değişmez

Bulgu 6'nın düzeltmesi ata yürüyüşünü **kaldırdı**. Yeni kural (alt ağacı olan
cüzdan referans eden atayamaz) döngüyü önerilemez hale getiriyor; yürüyüş bunun
üzerine ulaşılamaz kod olarak kalıyordu. Aynı gerekçeyle `seatPanel`'deki
`size < wanted` erken çıkışı da kaldırıldı: mutasyon testi onu kaldırmanın hiçbir
testi kırmadığını gösterdi, çünkü asıl işi yapan `size > 1` koruması.

### Statik analiz

Slither `0.11.6`, `fail_on: medium` — **medium ve üstü bulgu yok**. Bu geçişte
düzeltilenler: `_successPayouts` ve `_winner` içindeki başlatılmamış yereller
(açık başlangıç değeri verildi), `_panel` ve `_snapshots` mapping'leri için
`uninitialized-state` yanlış pozitifi (gerekçeli tek satırlık bastırma).
`seatPanel` ayrıca `nonReentrant` oldu — döngü içinde dış çağrı yapan bir
fonksiyonun korunmaması için sebep yok.
