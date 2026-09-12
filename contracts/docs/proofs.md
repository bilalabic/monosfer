# Kanıtlar: Teslim Alma ve Teslim Etme

> Kalıcı referans. Kaynak: `src/v1/proof/` altındaki dört dosya
> Baseline: sec. 11, sec. 12, sec. 15, sec. 47, sec. 48, invariant sec. 33-7
> Faz: P2.1 (teslim alma), P2.2 (teslim etme)

---

## 1. Teslim almayı kim yetkilendirir

Paketi teslim almak sorumluluğu kuryeye geçirir: o andan itibaren paket ondadır,
teminatı ona karşılık verir ve transit saati işlemeye başlar. Bu yüzden teslim
alma **iki tarafın da orada olmasını** gerektirir:

| Taraf | Ne yapar |
|---|---|
| Kurye | İşlemi gönderir — kendi rızası |
| Gönderen | EIP-712 kabul mesajını imzalar — devrin gerçekleştiğinin beyanı |

Tek başına ikisi de yetersizdir. Kuryenin kendi teslim almasını imzalaması,
fonksiyonu imzasız çağırmaktan farklı bir şey kanıtlamaz. Gönderenin tek başına
hareket etmesi ise hiç paket almamış bir kuryeye karşı transit saatini başlatır.

---

## 2. Mesajın bağladıkları

```text
PickupAcceptance(uint256 deliveryId,address courier,bytes32 action,uint256 nonce,uint64 expiresAt)
```

| Alan | Neyi engeller |
|---|---|
| `deliveryId` | Kabulün başka bir teslimata taşınmasını |
| `courier` | Gönderenin *hangi* kuryeye verdiğini belirsiz bırakmayı |
| `action` | Bir adım için toplanan imzanın başka adımda kullanılmasını |
| `nonce` | Aynı kabulün ikinci kez harcanmasını |
| `expiresAt` | İmzalanıp kullanılmayan bir kabulün süresiz beklemesini |

Chain id ve doğrulayan kontrat struct alanı değil, **EIP-712 domain'i** ile
bağlanır — bir kabul başka zincire veya başka deploy'a taşınamaz.

`action` iki değer alıyor: teslim almada `keccak256("MONOSFER.PICKUP")`,
iadede `keccak256("MONOSFER.RETURN")`. Aynı struct, aynı nonce alanı, tek fark bu
— ve fark tam olarak şunu sağlıyor: gönderenin devir için verdiği imza, iade
olmuş gibi tekrar sunulamıyor. Nonce alanı ortak olduğu için ikisi de tek
kullanımlık; bir kabul harcandığında diğer adımda da geçersiz.

---

## 3. Altı kontrol (sec. 12)

sec. 12 domain ayrımının **tek başına yetmediğini** açıkça söyler ve üstüne
zorunlu tutulacakları sayar. Her biri ayrı bir revert:

| Kontrol | Nerede |
|---|---|
| Doğru teslimat | `deliveryId` çağrının teslimatıyla karşılaştırılır |
| Doğru aksiyon | `action` ↔ `PICKUP_ACTION` |
| Doğru kurye | `courier` ↔ seçilmiş kurye |
| Süre | `expiresAt` ↔ `block.timestamp` |
| Nonce tekliği | `pickupNonceUsed[signer][nonce]` |
| Doğru imzacı | `SignatureChecker`, gönderenin adresine karşı |

İmzalar `SignatureChecker` ile doğrulanır: akıllı-hesap (ERC-1271) bir gönderen
EOA gibi çalışır.

### Nonce neden digest'e değil imzacıya bağlı

Digest'i tüketmek, birebir aynı mesajın ikinci kez gönderilmesini zaten
engellerdi. `(imzacı, nonce)` çiftini yakmak daha güçlüdür: o nonce, o imzacı
için **her teslimat, her aksiyon ve her süre boyunca** harcanmıştır, yani imzalı
bir kabulün hiçbir varyasyonu geri gelemez. sec. 12'nin ifadesi de budur — mesaj
tekliği değil, nonce tekliği.

Nonce **yalnızca başarılı gönderimde** yakılır. Kullanılmadan süresi dolan bir
kabul, nonce'unu yeniden imzalanabilir bırakır.

### Kabulün ömrüne neden ayrı bir üst sınır yok

Kapsam teklifinin aksine kabulün kendi maksimum penceresine ihtiyacı yoktur:
adını taşıdığı teslimat zaten `pickupWindow` üzerinde oturur ve o süre dolduğunda
`poke` teslimatı `ReadyForPickup`'tan çıkarır — o noktadan sonra hiçbir kabul
kullanılamaz. Ömrü durum makinesi sınırlar; ikinci bir sınır yalnızca yanlış
ayarlanacak ikinci bir yer olurdu.

---

## 4. Gönderen imzalamazsa

Bu tasarımın bedeli açıktır: imzalamayı reddeden bir gönderen devri askıya alır.
Hiçbir şey kilitlenmez — `pickupWindow` dolar, `poke` teslimatı `Cancelled`'a
alır, müşterinin emaneti geri döner ve kuryenin teminatı **kesilmeden** serbest
kalır. Kurye yolculuğunun karşılığını alamaz.

Bu, P2.1'in bilinçli bir sonucudur, gözden kaçmış bir durum değil; testte de
böyle kayıtlıdır (`test_SenderRefusingToSign_StallsThenCancelsCleanly`).

---

## 5. Backend'in üretmesi gerekenler

```jsonc
// EIP-712 domain — zincirden okunur: hub.eip712Domain()
{ "name": "MONOSFER", "version": "1", "chainId": 10143, "verifyingContract": "<DeliveryHub>" }

// PickupAcceptance(uint256 deliveryId,address courier,bytes32 action,
//                  uint256 nonce,uint64 expiresAt)
```

- `action` değeri `hub.pickupAction()` ile zincirden okunabilir — tahmin edilmez.
- `hub.hashPickupAcceptance(acceptance)` digest'i döndürür; backend imzayı
  göndermeden önce doğrulamak için kullanabilir.
- `hub.pickupNonceUsed(gonderen, nonce)` bir nonce'un harcanıp harcanmadığını
  söyler; nonce tahsisi backend'in sorumluluğundadır.
- Frontend, imzalatmadan önce sec. 40 gereği ne imzalandığını düz dille
  göstermelidir: hangi teslimat, hangi kurye, ne zamana kadar geçerli.

ABI ve adresler `contracts/exports/` içinde (bkz. [`integration.md`](integration.md)).

---

## 6. Test kapsamı

25 birim/fuzz testi. sec. 12'nin altı kontrolünün **her biri**, diğer beşi
sağlamken tek başına bozularak test edilir; böylece hiçbir kontrol komşusunun
arkasına saklanamaz.

Ayrıca:

- Kuryenin **kendi anahtarıyla** imzaladığı kabul reddedilir (sec. 12'nin
  kapattığı tek taraflı iddia)
- Başka gönderenin kabulü ödünç alınamaz
- Süre kenarı: son geçerli saniye kabul, bir sonrası ret
- Başarısız kanıt durumu ve nonce'u **değiştirmeden** bırakır
- Süresi dolmuş kabul nonce'u yeniden kullanılabilir bırakır
- ERC-1271 akıllı hesap gönderen kabul edilir, sahibi imzalamadıysa reddedilir
- Domain bu zincire ve bu deploy'a bağlı
- Digest bağımsız türetimle karşılaştırılır (tip dizgisi kayması yakalanır)
- Fuzz: rastgele imza baytı, gönderen dışındaki anahtar, kurcalanmış nonce

Invariant suite'inde `invariant_PickupAcceptanceNeverReplayed` (sec. 33-7) ve
`invariant_ForgedPickupNeverAccepted`.

> **Not:** birebir aynı kabulü tekrar göndermek nonce kontrolüne hiç varmaz —
> durum makinesi çok önce reddeder. Nonce korumasına gerçekten ulaşan saldırı,
> **harcanmış bir nonce ile yeni ve doğru imzalanmış bir kabul** üretmektir;
> invariant handler'ı bunu yapar. Nonce yakma satırı koddan çıkarıldığında
> invariant kırmızıya döner — doğrulanmıştır.


---

# İade Kanıtı (sec. 17)

## 7. Kurye kendi kendine ödeme yapamaz

`confirmReturn` tek başına bir durum geçişi değil: `returnAsk` müşterinin
escrow'undan kuryeye ödenir ve mala karşılık duran kapsam serbest kalır. Yani
kurye **kendisine** ödeme yaptırıyor.

Bu yüzden kanıt isteniyor. `confirmPickup` gönderenin EIP-712 kabulünü,
`submitDeliveryProof` servis imzalı attestation'ı ve 24 saatlik itiraz penceresini
şart koşarken, paranın kuryeye kendi beyanıyla gittiği tek geçişin hiçbir şey
istememesi tutarsızdı. Şimdi aynı typed data kullanılıyor, tek farkla:

```solidity
acceptance.action == keccak256("MONOSFER.RETURN")
```

## 8. Gönderen imzalamazsa ne olur

Kurye mahsur kalmaz. `ReturnRequired` durumunun kendi son tarihi var; pencere
dolduğunda `poke` teslimatı `Returned`'a taşır. Fark şurada: o yolda müşteri
escrow'un tamamını geri alır ve iade ücreti ödenmez. İadenin gerçekten yapıldığını
düşünen kurye ihtilaf mahkemesine gidebilir (sec. 26).

Kısacası kaybolan şey kuryenin **kimsenin onaylamadığı** bir iade için ücret alma
imkânı; iade ücretinin kendisi değil.

## 9. Test kapsamı

- Gönderen dışında birinin imzaladığı iade reddedilir
- Teslim alma için toplanan imza iadede sunulunca `PickupProofWrongAction`
- Ters yön de doğru: iade kabulü `confirmPickup`'a sunulunca reddedilir
- Kullanılan iade kabulünün nonce'u yanar (sec. 33-7)

Mutasyon kanıtı: kontrol satırı tamamen kaldırıldığında 3 test, beklenen aksiyon
`PICKUP_ACTION` ile değiştirildiğinde 4 test kırmızıya döner.

---

# Teslim Etme Kanıtı (PoD)

## 10. Neden alıcının imzası değil

Bir teslimatta cüzdanı olduğu varsayılamayacak tek kişi alıcıdır. sec. 15 bu
yüzden onun kanıtını sahip olmayabileceği bir anahtardan değil, protokolden
geçirir: alıcı bir challenge'ı (OTP veya okutulan kod) yanıtlar, backend
doğrular, PoD attestation servisi doğrulamanın geçtiğini imzalar.

Zincir sırrı hiç görmez. `challengeHash` ona bir taahhüttür; bir ihtilafta hangi
challenge'ın yanıtlandığı gösterilebilir, düz metin hiç yayımlanmadan.

## 11. Attestation'ın bağladıkları

```text
PodAttestation(uint256 deliveryId,address courier,bytes32 proofType,
               bytes32 challengeHash,uint256 nonce,uint64 issuedAt,uint64 expiresAt)
```

| Kontrol | Nerede |
|---|---|
| Doğru teslimat | `deliveryId` çağrının teslimatıyla karşılaştırılır |
| Doğru kurye | `courier` ↔ zincirdeki kurye |
| Bilinen tip | `POD_OTP` / `POD_QR` / `POD_RECIPIENT_SIGNATURE` |
| Gerçek challenge | `challengeHash` sıfır olamaz |
| Ömür | Pencere tutarlı, süresi dolmamış, **ve zincirce sınırlı** |
| Nonce tekliği | `podNonceUsed[imzacı][nonce]` |
| Doğru imzacı | `SignatureChecker`, `podAttestationSigner`'a karşı |

**Ömrü zincir sınırlar.** İmzacı pencereyi beyan eder ama sec. 48 üst sınırı 10
dakikadır ve bu kural imzacının düzenleyemeyeceği bir yerde durmalıdır. Sınır
olmasa bir yıl geçerli attestation kesilebilir ve kural yalnızca backend'de
yaşardı — yani imzanın gereksiz kılmayı amaçladığı bileşende.

**Bilinmeyen tip reddedilir.** Böylece gelecekteki bir kanıt türü, kod onu
anlamadan kabul edilemez; yeni tip eklemek bilinçli bir değişikliktir, imzacının
tek taraflı sokabileceği bir şey değil.

## 12. Ele geçirilmiş bir attestation imzacısı ne yapabilir

Bu anahtar teslimatı beyan edebilir, yani gerçek bir güven noktasıdır — risk
teklifi imzacısından **bağımsız döner** (`SIGNER_ADMIN_ROLE`) ve deploy script'i
tek adresin ikisini birden tutmasını reddeder.

Yapamadığı şey uzlaşmaktır: attestation yalnızca **itiraz penceresini açar**
(sec. 16), müşteriye değer hareket etmeden önce itiraz etme süresi kalır.

Döndürme, bekleyen attestation'ları anında geçersizleştirir: nonce'lar imzalayan
hesaba göre tutulur ve imza gönderim anında config'in adını verdiği imzacıya
karşı doğrulanır.

## 13. Backend'in üretmesi gerekenler

- Tip değerleri `hub.podProofTypes()` ile zincirden okunur, tahmin edilmez.
- `hub.hashPodAttestation(attestation)` digest'i döndürür.
- `hub.podNonceUsed(imzacı, nonce)` bir nonce'un harcanıp harcanmadığını söyler.
- Düz metin OTP **hiçbir koşulda** zincire gönderilmez; yalnızca hash'i.

## 14. Henüz yapılmayan

sec. 15 cüzdanı olan bir alıcı için isteğe bağlı **doğrudan imza yolundan** da
söz eder. Bugün uygulanmadı: bir teslimat zincirde alıcı adresi taşımıyor, bu
yüzden kontrat böyle bir imzayı kendisi doğrulayamaz. `POD_RECIPIENT_SIGNATURE`
tipi kabul edilir ve anlamı "attestation servisi alıcının imzasını zincir dışında
doğruladı"dır. Doğrudan yol, teslimata alıcı alanı eklenmesini gerektirir.

## 15. Test kapsamı

25 birim/fuzz testi. Altı kontrolün her biri tek tek koddan çıkarılarak ölçüldü:

| Kaldırılan | Kırılan test |
|---|---|
| İmza doğrulama | 14 |
| Nonce yakma | 6 |
| Ömür üst sınırı | 4 |
| Bilinmeyen tip | 2 |
| Boş challenge | 2 |
| Kurye | 2 |

Invariant: `invariant_ForgedPodAttestationNeverAccepted`.
