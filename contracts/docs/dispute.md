# İhtilaf Sistemi: Jüri, İtiraz ve Yedek Komite

> Kapsam: sec. 26 (ihtilaf ne içindir), sec. 27 (juror ekonomisi), sec. 28
> (yaşam döngüsü ve 3→5→7 tırmanması), sec. 29 (rastgelelik), sec. 30
> (commit/reveal ve altı sonuç), sec. 31 (yedek komite), sec. 32.6.
>
> Kontratlar: `DisputeCourt.sol`, `JurorPool.sol`, `FallbackCommittee.sol`,
> `PythEntropyAdapter.sol`. Para tarafı `DeliveryHub.settleByRuling` üzerinden
> `SettlementVault`'a gider.

---

## 1. Neyin ihtilaf olduğu, neyin olmadığı

sec. 26 net: ihtilaf **fiziksel bir olgunun yorumlanması** gerektiğinde açılır —
teslim edilmeme, kayıp, hasar, başarısız iade, tartışmalı devir. Zaman aşımı ve
iptal deterministik olarak çözülür ve **jüri önüne hiç gelmez**.

Bu ayrım kod tarafında `DeliveryHub.openDispute`'ta duruyor: yalnızca üç durum
ihtilafa açık.

| Durum | Neden tartışılabilir |
|---|---|
| `InTransit` | Mal kuryede; kayıp veya hasar iddiası burada doğar |
| `DeliveredPending` | Teslim iddia edildi, müşteri itiraz ediyor (sec. 16) |
| `ReturnRequired` | İade istendi; yapılıp yapılmadığı bir olgu sorusu |

Teklif toplayan ya da fonlanmayı bekleyen bir teslimatın jüriye soracağı bir şey
yoktur; `NotDisputable` ile reddedilir.

---

## 2. Mahkeme parayı değil, cevabı tutar

İhtilaf açıldığında escrow yerinde kalır — vault'ta, teslimatın kilidinde.
Değişen tek şey teslimatın `Disputed` durumuna geçmesi ve **deterministik
çıkışların askıya alınması**.

Bunun sebebi tek cümlelik: eğer `poke` ihtilaf sırasında da çalışsaydı, saat
jürinin altından escrow'u kapatır ve hüküm geldiğinde ortada para kalmazdı.

`Disputed` yine de bir son tarih taşıyor. `disputeWindow` (baseline: 30 gün) bir
faz değil, **son çıkış süresi**: mahkeme tamamen susarsa bile "çıkışı olmayan durum
yok" kuralı ayakta kalsın diye var. Üç tam turun ve itiraz pencerelerinin
toplamından (yaklaşık 21,75 gün) uzun olması `ProtocolConfig`'te doğrulanıyor —
yoksa ihtilaf duruşmanın ortasında sona erebilirdi.

---

## 3. Bir turun şekli

```text
open  ──►  Evidence  ──►  AwaitingDraw  ──►  Commit  ──►  Reveal  ──►  Ruled
                                │                            │          │
                          (sağlayıcı sustu)            (kimse açmadı)    │
                                ▼                            ▼          ▼
                             Failed ◄───────────────────── Failed    itiraz?
                                │                                       │
                        komite (sec. 31)                         finalise ──► Settled
```

- **Evidence:** yalnızca hash'ler zincire yazılır (sec. 34). Malzemenin kendisi
  zincir dışında; bir kapı fotoğrafını kalıcı kamusal depoya koymanın bedeli
  koli ihtilafından büyüktür.
- **AwaitingDraw:** aday kümesi **talep anında** donar (invariant sec. 33-18).
  Rastgelelik adaptörden okunur, adaptör mahkemeyi hiç çağırmaz (sec. 29).
- **Commit / Reveal:** oy `keccak256(disputeId, round, juror, ruling, salt)`
  olarak taahhüt edilir (sec. 30).
- **Ruled:** hüküm durur, itiraz penceresi işler.

### Yalnızca açmamak cezalandırılır

Invariant sec. 33-14: kaybeden tarafa oy verdiğini **açan** juror'ın stake'ine
dokunulmaz. Kesme yolu tek bir yerden çağrılıyor ve adı ne için var olduğunu
söylüyor: `slashForNonReveal`. Oy sayımından erişilebilir değil.

---

## 4. Her tur kendi davasıdır

İtiraz edilen bir ihtilaf ikinci bir panel çeker ve ikinci bir oylama yapar.
İkisi birbirinin deposunu **görmemeli**. Bu yüzden panel, koltuklar,
taahhütler ve sayım `keccak256(disputeId, round)` altında tutuluyor.

Aynı anahtar juror havuzunun draw id'si. Sonucu şu: birinci turda oturan bir
juror koltuğunu bırakır ve ikinci tur için **herkesle eşit şartlarda** yeniden
çekilebilir. sec. 27'nin eşit ağırlık kuralı turlar arasında da geçerli.

---

## 5. Altı sonuç, tek bir bölüşüm

sec. 30 sonuçları sınırlıyor ve juror'ın adres veya yüzde veremeyeceğini açıkça
söylüyor. Kodda bu bir enum; settlement onu okur.

| Hüküm | Müşterinin escrow payı |
|---|---:|
| `Customer100` | %100 |
| `Customer75` | %75 |
| `Split50` | %50 |
| `Customer25` | %25 |
| `Courier100` | %0 |
| `Refuse` | %100 |

`Refuse` panelin **karar vermeyi reddetmesi**. Protokolün kuryenin ifa ettiğini
saptayamadığı her durumdaki cevabı escrow'u iade etmektir — zaman aşımına uğramış
iade de, duran ihtilaf da aynı cevabı alır. Kurye lehine okumak, karar vermemeyi
ödüllendirmek olurdu.

İki not:

- **Protokol ücreti alınmaz.** İhtilaflı teslimat protokolün temiz taşıyamadığı
  teslimattır; işler kötüleştikçe daha çok kazanmak yanlış bir teşviktir.
- **Teminat kesilmez.** Hüküm escrow'u bölüştürür; kuryenin sec. 8.3 kapsamı
  kesilmeden serbest bırakılır. Bunun sebebi kapsamın gereksiz olması değil,
  P4.3'ün kapsamının escrow settlement'ı olması — bkz. bölüm 9.

---

## 6. İtiraz ve bond (sec. 28)

| Tur | Arbitration Fee | Bond | Panel |
|---|---:|---:|---:|
| İlk | 0.3 MON | 1 MON | 3 |
| İtiraz 1 | 0.5 MON | 2 MON | 5 |
| İtiraz 2 | 0.7 MON | 4 MON | 7 |

Cetvel turlar boyunca **yükselmek zorunda**; `ProtocolConfig` bunu doğruluyor.
Sonraki turun daha ucuz olması, yargılanmaktan çok itiraz etmeyi ucuzlatırdı ki
bu bond'un varlık sebebini tersine çevirir.

sec. 28 üç satır veriyor, dördüncüsünü vermiyor: **üçüncü tur yapı gereği
kesindir**, bir son tarihle değil.

### Bond kime döner — bu bir yorum

Baseline bond'un akıbetini söylemiyor. Uyguladığımız kural:

- **Birinci turun bond'u her hâlükârda iade edilir.** sec. 28 ona "participation
  bond" diyor; katılım bedeli haklı çıkma bahsi değildir. İşlevi spam'e karşı
  sermaye bağlamak.
- **Her itiraz bond'u**, büyük panel küçüğünden **farklı** karar verirse iade
  edilir; aynı kararı tekrarlarsa hazineye yazılır. Dinlenmek için ödemekle
  geciktirmek için ödemek arasındaki fark budur.
- **Arbitration fee** her zaman hazineye gider; hiç yargılanmamış bir dava
  (bölüm 8) bunun tek istisnası.

Bu bir okuma tercihi, baseline'dan çıkarılmış bir zorunluluk değil. Değiştirmek
isteyen `_settle` içindeki tek bloğa bakmalı.

---

## 7. Yedek komite (sec. 31)

Jüri cevapsız kalabilir: sağlayıcı susar, kimse oyunu açmaz, ya da panel hiç
kurulamaz. Para her hâlükârda escrow'da olduğu için bu duruma cevabı olmayan bir
protokol, parayı mahsur bırakabilen bir protokoldür.

sec. 31'in cevabı 3-of-5 Safe. Kodda bu şuna indirgeniyor:

> **Komite, jürinin seçebileceği altı sonuç arasından seçebilir. Başka hiçbir şey
> yapamaz.**

- Alıcı adresi belirleyemez.
- Tutar belirleyemez.
- Vault'a erişemez.
- **Hâlâ yürüyen** bir ihtilafa dokunamaz — yalnızca `Failed` fazından çağrılır.
  Bir canlılık mekanizmasını veto hâline getirmeyen şey budur.

3-of-5 eşiği bu kontratta değil, Safe'in içinde — Safe zaten bunun için var.
`FallbackCommittee` tek bir adres ve tek bir ERC-1271 imzası görür. Yani
"3-of-5" governance'ın işaret ettiği hesabın bir özelliği; komiteyi döndürmek
başka bir Safe'i göstermek demek.

İmza EIP-712 typed data: komite üyesinin cüzdanı ihtilafı, turu ve hükmü gösterir.
Ham hash imzalamak, okunamayan bir şeyi onaylamaktır. `expiresAt` bir anlık için
toplanmış imzanın aylar sonra kullanılmasını engeller, ve her digest tek
kullanımlıktır.

`setSafe` zaman kilitsiz ve `SIGNER_ADMIN_ROLE` altında — risk teklifi ve
attestation imzacılarıyla aynı gerekçe: anahtarları ele geçirilmiş bir komite
**şimdi** değiştirilebilmeli, iki gün beklemek iki gün düşman imzacı demektir.

---

## 8. Hiçbir ihtilaf parayı donduramaz

Kabul kriteri buydu. İki mekanizma birlikte karşılıyor:

1. **Hub'ın son çıkış süresi.** `disputeWindow` dolduğunda `poke` teslimatı
   `Resolved`'a taşır, escrow müşteriye döner, teminat **kesilmeden** serbest
   kalır — kesme bir tespit gerektirir ve ortada tespit yoktur (sec. 13, sec. 26).
2. **Mahkemenin `abandon`'ı.** Hub teslimatı başka bir yoldan kapattıysa ortada
   hükmedilecek bir şey kalmamıştır. Toplanan her şey ödeyene geri yazılır: hiç
   sonuçlanmamış bir duruşmanın ücreti hak edilmiş değildir. Çağrısı izinsiz —
   aksi hâlde komitesiz kalmış bir `Failed` dava bond'ları sonsuza dek tutardı.

Ters yön de doğru: son çıkış süresi **erken dolmuş sayılmaz**. Çalışan bir jürinin altından
teslimatı kapatmaya çalışan `poke`, `DeadlineNotReached` ile reddedilir.

---

## 9. Henüz yapılmayan

Dürüst sınırlar:

- **Teminat kesme.** Hüküm escrow'u bölüştürüyor; sec. 8.3 kapsamına
  ulaşmıyor. Kaybettiği tespit edilen bir kuryenin kapsamı bugün kesilmeden
  serbest kalıyor. P4.3'ün kapsamı planda "final ruling settles through the vault
  exactly once, into `claimable[]`" olarak tanımlı ve kapsam kesme bunun dışında;
  ekonomik olarak eksik olduğu için burada açıkça yazılıyor.
- **Kanıt teşviki yok.** Kanıt sunmak ücretsiz ve sunmamanın doğrudan bir bedeli
  yok; jüri elindekiyle karar verir.
- **Juror ücreti yok.** Arbitration fee hazineye gidiyor, panele dağıtılmıyor.
  sec. 27 juror ekonomisini stake/lock/slash üzerinden tanımlıyor ve ücret
  paylaşımı vermiyor.

---

## 10. Test kapsamı

`DisputeCourt` suite'inde 57, `FallbackCommittee` suite'inde 16 test, ayrıca
`DisputeCourtInvariant`'ta beş invariant. Mutasyon kanıtları
`verification-log.md`'de; her iddia kodu bozup testin kırmızıya döndüğü
görülerek doğrulandı.

Özellikle kanıtlananlar:

- Escrow her altı hüküm için de **tam olarak** bölüşülür — ne yaratılır ne kaybolur
- Hüküm **bir kez** paraya dönüşür; ikinci `finalise` reddedilir
- İtiraz penceresi kapanmadan para kıpırdamaz
- Dördüncü tur yoktur
- Komite yürüyen bir ihtilafa dokunamaz, sınır dışı kod imzalayamaz, imzasını
  ikinci kez kullanamaz
- Mahkeme tamamen sussa bile escrow sahibine ulaşır
- İtiraz eden de, ihtilafı açan da teslimatın tarafı olmak zorunda

Invariant suite'i dört bitiş yolunu (jüri hükmü, itiraz sonrası hüküm, komite
kararı, hub'ın son çıkış süresi) rastgele sırayla ve aynı ihtilaf üzerinde
çakıştırarak sürüyor — "tam olarak bir kez" ancak bir şey iki kez kapatmaya
çalışırken anlamlı.

---

## 11. Komite imzası nasıl toplanır

Safe'in ERC-1271'i **ham digest'i değil**, kendi sarmalayıcısını doğrular:

```text
safeMessageHash = Safe.getMessageHash(abi.encode(committee.hashDecision(decision)))
```

Komite üyeleri **bunu** imzalar, ve imzalar sahip adresine göre **artan sırada**
birleştirilir. Ham digest'i imzalayan bir backend, Safe'in `GS026` ile
reddedeceği bir imza üretir. Monad testnet'te üçü de doğrulandı: üç imza kabul,
iki imza `GS020`, başka mesaja imza `GS026`.

---

## 12. Backend ve frontend

- **Backend:** komite koordinasyonu ve **yedek kullanıldığında alarm**. sec. 31
  son çare canlılık mekanizması; rutin yönetim değil. Kullanımı istisna olarak
  izlenmeli, normal operasyon olarak değil.
- **Backend:** kanıt malzemesinin saklanması ve hash'e karşı doğrulanabilir
  sunulması (sec. 34).
- **Frontend:** itiraz durumu, kalan pencere, ve bond'un akıbetinin açıkça
  gösterilmesi — kullanıcı bond'unu neyin geri getirdiğini bilmeli.
