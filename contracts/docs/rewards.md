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

Her cüzdan referans ormanındaki derinliğini saklar: kök 0, referans edilen cüzdan
referans edenin derinliği artı bir. Kayıt, referans edenin derinliğinin
`MAX_DEPTH` (32) altında olmasını ister — bu her zinciri sınırlar. Bu sınır
içinde kontrat, önerilen referans edenden yukarı yürüyerek kayıt olan cüzdanın
zaten bir ata olmadığını doğrular.

Yürüyüş **eksiksizdir**, çünkü bir zincir tavandan uzun olamaz; ve gası **aynı
tavanla sınırlıdır**. Sınırsız yürümek bariz uygulama olurdu ve kayıt maliyetini
başkasının ağacının derinliğine bağlardı.

## 8. Ödüller talep edilir, itilmez

Nitelenme referans edenin bakiyesini alacaklandırır; referans eden kendisi çeker.

sec. 25 bir referans hatasının teslimat uzlaşmasını **asla** bloke etmemesini
istiyor ve bunu garanti etmenin yolu, uzlaşmanın referans parasını hiç
taşımamasıdır. MON kabul etmeyen ya da hiç ortaya çıkmayan bir referans eden
kimseyi bekletmez.

`recordQualification` ödül yolunda **hiç revert etmez**. Bütçe yetmiyorsa
nitelenme yine kaydedilir ve eksik olay olarak yayılır — çağıran bir uzlaşma
kontratıdır ve referans bütçesi boş diye başarısız olmamalıdır.

---

## 9. Test kapsamı

38 test (19 ödül + 19 referans). Mutasyon testi:

| Kaldırılan | Kırılan test |
|---|---|
| Döngü tespiti | 6 |
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

---

## 10. Backend'in sorumlulukları

- **Merkle ağacı üretimi ve epoch otomasyonu backend'e ait** (sec. 23). Root'un
  doğruluğu zincir dışı bir sorumluluktur ve kendi test yükünü taşır.
- Leaf yapısı yukarıdaki gibi olmalı; tek hash'li bir ağaç kabul edilmez.
- Frontend: talep ekranı ve referans durumu.
- Sybil kalıpları sec. 25 gereği **zincir dışı risk kontrollerine** ait; kontrat
  yalnızca yapısal kuralları (tek referans eden, tek ödül, döngüsüzlük) uygular.
