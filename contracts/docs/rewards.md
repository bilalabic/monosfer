# Ödüller ve Referans

> Kalıcı referans. Kaynak: `src/v1/rewards/RewardDistributor.sol`, `src/v1/rewards/Referral.sol`
> Baseline: sec. 23, sec. 25, sec. 48, invariant sec. 33-12
> Faz: P3.3

---

## 1. Her epoch kendi parasından öder

Bir epoch'tan talep yapılabilmesi için önce **fonlanmış** olması gerekir ve
talepler kontratın toplam bakiyesine değil, **o epoch'un** bakiyesine karşı
kontrol edilir.

Bu ayrım olmadan bir haftanın geçerli kanıtı başka bir haftanın bütçesini
boşaltır: talep eden meşru görünür, aritmetik doğrudur, para yalnızca başka
yerden gitmiştir. Invariant sec. 33-12 tam olarak bunun için var.

Testte sabit: `test_ProofFromOneEpochCannotDrainAnother` — epoch 2'nin ağacı
yanlış üretilmiş ve tuttuğundan fazlasını vaat ediyor. Kanıt doğrulanıyor; onu
durduran şey bütçe kontrolü ve epoch 1'in parasına hiç dokunulmuyor.

---

## 2. Bir root, birisi ona güvendiği anda sabitlenir

İlk talepten önce hazine root'u düzeltebilir — erken yakalanan bozuk bir ağaç
düzeltilebilmeli. İlk talepten sonra dondurulur. O noktadan sonra değiştirmek,
bir kısım insanın bir kurala, geri kalanın başka bir kurala göre ödendiği ve
sonradan hangisinin hangisi olduğunu ayırt etmenin mümkün olmadığı anlamına
gelirdi.

---

## 3. Leaf iki kez hash'lenir

```text
keccak256(keccak256(abi.encode(account, amount)))
```

Standart, ikinci ön-görüntüye kapalı yapı. Önceki uygulamadan **korundu** çünkü
zaten doğruydu. Tek hash, ağacın bir iç düğümünün leaf gibi sunulmasına izin
verir.

---

## 4. Pencereler (sec. 23, sec. 48)

| | Süre |
|---|---|
| Talep penceresi | 90 gün (root yayımından itibaren) |
| Geri alma gecikmesi | +7 gün |

Geri alma **yalnızca talep edilmemiş kalanı** döndürür. Gecikme, henüz işlenmekte olan bir
talebin altından bütçenin çekilmemesi için var.

---

## 5. Fonlamak izinsiz, harcamak rollü

sec. 23 sponsorları ve hibeleri hazinenin yanında sayıyor. Para **vermek** için
rol istemek her sponsoru bir yönetişim kararına çevirirdi. Yetkilendirme, parayı
kimin **çıkarabileceği** tarafında duruyor.

Ödeme gücü vault ile aynı disiplinde: `bakiye >= totalOutstanding`, her durum
değişikliğinden sonra. Ödüller teslimat custody'sinden ayrı bir bütçe ve bilerek
vault'u paylaşmıyor — bir sponsorun hibesiyle bir müşterinin emanetini aynı yere
koymak, vault'a para tutması için ikinci bir sebep ve yanlış olması için bir yol
daha verirdi.

---

# Referans (sec. 25)

## 6. Cüzdan bağlamak ödeme yapmaz

sec. 25 açık: ödül bir şey **yapmakla** kazanılır — müşteri veya kurye olarak ilk
tamamlanmış teslimat, ilk sonuçlanmış jüri katılımı. Kayıt bedava ve hiçbir şey
kanıtlamaz; nitelenme, o eylemi gören protokol kontratı tarafından raporlanır.

**Referred cüzdan başına tek ödül**, hangi rolde önce nitelendiyse. sec. 25 bir
katılımcı kazandırmanın karşılığını ödüyor, o kişinin üstlendiği her rol için
ayrı ayrı değil.

## 7. Döngüler aramayla değil, yapıyla imkânsız

İki kural yeterli, ikisi de gezinme gerektirmiyor:

1. Bir cüzdan referans edenini **en fazla bir kez** yazar (`referrerOf` tek
   yazımlık).
2. Bir cüzdan yalnızca **kendisini henüz kimse referans etmemişken** referans
   eden atayabilir.

İkisi birlikte şunu söylüyor: bir cüzdana **giren** kenar, ondan **çıkan** ilk
kenardan önce sabitlenir. Döngü için W'den W'nin kendi alt ağacındaki birine
kenar gerekir; ama W'nin alt ağacı varsa W'nin bir referansı var demektir ve
2. kural kaydı baştan reddeder. Döngü **önerilemez**, dolayısıyla aranacak bir şey
de yoktur.

Aynı ikili `depthOf` değerini de kesin tutuyor. Derinlik bir kez, referans edenin
o andaki derinliğinden yazılır; referans edenin derinliği ise 2. kural sayesinde
çoktan donmuştur.

### Neden yalnızca ata yürüyüşü yetmiyordu

Önceki uygulama önerilen referans edenden yukarı yürüyüp kayıt olanın zaten ata
olmadığına bakıyordu. Yürüyüş `MAX_DEPTH` (32) ile sınırlıydı ve bu sınırın
yeterli olması **her derinliğin gerçek olmasına** dayanıyordu — ki değildi:
derinlik bir kez yazılıp bir daha güncellenmediği için, alt ağacı olan bir cüzdan
sonradan referans eden alırsa o alt ağaç derinliğini artık kök olmayan bir kökten
saymaya devam ediyordu. Her biri yirmilik iki zincir, kayıtlı en büyük derinlik
hâlâ yirmi bir görünürken kırk birlik tek zincire bağlanabiliyordu — hem
`MAX_DEPTH`'in, hem de yürüyüşün bakacağı yerin ötesinde.

Kullanıcıya düşen kural basit: **referans etmeden önce kendi referans edenini
yaz.** sec. 25 zaten bu sırayı anlatıyor; kayıt bir onboarding adımı.

## 8. Nitelenmeyi kim bildirir

`recordQualification` yalnızca eylemi **gören** kontrat tarafından çağrılır ve
`REFERRAL_REPORTER_ROLE` ister. Bu rol `REPUTATION_REPORTER_ROLE`'den ayrı: biri
puan yazar, diğeri referans kesesinden para taahhüt eder; tek rol olsaydı birini
geri almak diğerini de geri alırdı.

| Eylem | Bildiren | Nerede |
|---|---|---|
| İlk tamamlanan teslimat (müşteri) | `DeliveryHub` | `_complete` |
| İlk tamamlanan teslimat (kurye) | `DeliveryHub` | `_complete` |
| İlk sonuçlanan jüri turu | `DisputeCourt` | `closeReveal` |

Jüri tarafında bildirim `closeReveal`'de; commit ya da reveal anında değil.
sec. 25 **sonuçlanan** turu istiyor, ve commit edip susan bir juror hizmet
vermemiştir — ödüllendirilmez, kesilir.

### Çağrı neden low-level

`recordQualification` daha önce nitelenmiş bir cüzdanda `AlreadyQualified` ile
revert eder — yani ilk teslimattan sonraki **her** teslimatta. Bu revert yukarı
taşınsaydı bir cüzdanın ikinci teslimatı hiç settle olamazdı. sec. 25 kuralı
doğrudan koyuyor: referans hatası settlement'ı bloke etmemeli. Bu yüzden çağrı
low-level yapılıyor, başarısızlık `ReferralReportFailed` olayıyla kayda geçiyor ve
settlement devam ediyor.

Aynı gerekçe jüri tarafında daha da bağlayıcı: panel süpürmesi tek bir tekrar
juror yüzünden revert etseydi, ihtilaf `Reveal` fazında asılı kalır ve **diğer
bütün jurorların** teminatı kilitli kalırdı.

## 9. Ödüller talep edilir, itilmez

Nitelenme referans edenin bakiyesini alacaklandırır; referans eden kendisi çeker.

sec. 25 bir referans hatasının teslimat uzlaşmasını **asla** bloke etmemesini
istiyor ve bunu garanti etmenin yolu, uzlaşmanın referans parasını hiç
taşımamasıdır. MON kabul etmeyen ya da hiç ortaya çıkmayan bir referans eden
kimseyi bekletmez.

`recordQualification` ödül yolunda **hiç revert etmez**. Bütçe yetmiyorsa
nitelenme yine kaydedilir ve eksik olay olarak yayılır — çağıran bir uzlaşma
kontratıdır ve referans bütçesi boş diye başarısız olmamalıdır.

---

## 10. Test kapsamı

41 test (19 ödül + 22 referans). Mutasyon testi:

| Kaldırılan | Kırılan test |
|---|---|
| Döngü koruması (2. kural) | 5, biri gerçek bir döngü kurarak |
| Epoch bütçe tavanı (sec. 33-12) | 2 |
| Root dondurma | 2 |
| Talep penceresi | 2 |
| Geri alma gecikmesi | 2 |
| Kendini referans yasağı | 2 |
| Tek ödül kuralı | 2 |
| Bütçe kontrolü (reporter'ı revert ettiren) | 2 |

Ayrıca: MON kabul etmeyen hazine yalnızca kendi geri almasını bloke eder, MON
kabul etmeyen referans eden kimseyi bekletmez, zorla gönderilen değer kimsenin
bütçesi olmaz, fuzz ile talepler hiçbir girdi kombinasyonunda epoch bütçesini
aşmaz.

Nitelenme kablolaması ayrıca `ReputationWiring` suite'inde kanıtlanıyor: tamamlanan
bir teslimat iki tarafı da niteler, ikinci teslimat aynı referans edene ikinci kez
ödemez, ve hub'ın reporter rolü geri alındığında settlement yine tamamlanır —
`ReferralReportFailed` olayı sayılarak. Hub bildirimi koddan çıkarıldığında bu
üç testten üçü de kırmızıya döner.

---

## 11. Backend'in sorumlulukları

- **Merkle ağacı üretimi ve epoch otomasyonu backend'e ait** (sec. 23). Root'un
  doğruluğu zincir dışı bir sorumluluktur ve kendi test yükünü taşır.
- Leaf yapısı yukarıdaki gibi olmalı; tek hash'li bir ağaç kabul edilmez.
- Frontend: talep ekranı ve referans durumu.
- Sybil kalıpları sec. 25 gereği **zincir dışı risk kontrollerine** ait; kontrat
  yalnızca yapısal kuralları (tek referans eden, tek ödül, döngüsüzlük) uygular.
