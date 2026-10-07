# Yerel kurye ve teslimat testleri

Bu veri seti gerçek kişiler veya müşteri siparişleri değildir. Kayseri semtlerini
kullanan gerçekçi örneklerdir. Profiller PostgreSQL'de, ilan ve tekliflerin yaşam
döngüsü gerçek DeliveryHub sözleşmesinde, özel teslimat bilgileri şifreli kayıtlarda
tutulur. Zincir 31337'dir; test MON'un parasal değeri yoktur.

Node 24, Foundry, yerel PostgreSQL ve Redis gerekir. Backend bağlantı ayarları
`.claude/launch.json` içindeki geliştirme profiline dayanır; farklı bir veya uzak
veritabanında seed çalışmaz. Var olan kullanıcı ve kayıtlar silinmez.

İlk kurulumda proje kökünden:

```sh
npm run local:chain   # ayrı terminalde açık bırak
npm run local:deploy
npm run local:migrate
npm run local:seed
```

Servisleri ayrı terminallerde açık bırak:

```sh
npm run local:backend
npm run local:frontend
npm run local:indexer
npm run local:quotes
npm run local:realtime
```

Ön yüz: http://localhost:3000. API: http://127.0.0.1:3001/v1.
Realtime: http://127.0.0.1:3002/v1. Yerel RPC: http://127.0.0.1:8545.
Finalized indeksleme ve quote bağlantıları hazır olunca `npm run local:verify`
ile ilan/kurye SSR çıktısı, teklifler, şifreli veri bağlantıları ve özel veri
erişim kuralları doğrulanabilir.
MetaMask bağlantısı sırasında uygulama 31337 ağına geçiş ister. Ağ bilgileri:
Monosfer Yerel Test, RPC http://127.0.0.1:8545, chain ID 31337, sembol MON.
Yerel ağ için explorer yoktur.

Seed, mevcut gerçek kullanıcı cüzdanını bulursa dört gönderici senaryosunu ona
atar ve yalnız Anvil'de test bakiyesi verir. `LOCAL_TEST_CUSTOMER` ile belirli bir
cüzdan seçilebilir. Bu yerel impersonation işlemi test sonunda kapatılır;
kullanıcı anahtarına ihtiyaç yoktur ve uzaktaki ağa işlem gönderilmez.
Diğer müşteriler ve altı kurye Anvil'in herkese açık test hesaplarıdır.
Kurye hesabıyla işlem denemek için yalnız test cüzdanında Anvil hesabı kullanılabilir.

## Senaryolar

12 ilan, altı kurye ve birbirinden farklı fiyat/ETA teklifleri vardır:
4 teklif bekleyen, 1 ödeme bekleyen, 1 teslim alma bekleyen, 1 yolda,
1 teslim onayı bekleyen, 1 tamamlanan, 1 iade edilen, 1 iade bekleyen, 1 iptal.
Başlıklar, semtler, ağırlık ve rota mesafeleri örnek senaryo etiketleridir;
bir harita sağlayıcısının ölçümü değildir. Fon ve durum değerleri zincirden gelir.
Örnek etiketler `/v1/development/dataset` üzerinden sadece yerel geliştirmede
sunulur; diğer ortamlarda bu endpoint 404 döner.

Anvil'in varsayılan finalized gecikmesi yaklaşık 64 bloktur. UI ve şifreli veri
bağlantısı bu aşamadan sonra güncellenir. Yerel freshness eşiği bu nedenle
120 saniyedir. Yeniden çalıştırılan seed ilerleme günlüğünü kullanır ve aynı
ilanları çoğaltmaz. Tamamlanan senaryoların beklenen sözleşme durumlarını doğrular.

Anvil durumu `/tmp/monosfer-anvil-state.json` içinde, seed ilerlemesi
`backend/.local-seed-progress.local` içinde saklanır. Yerel zincir ve bu günlük
birlikte korunmalıdır; zincir temizlenirse yeni deployment ve yeni seed gerekir.
Ana sözleşme boyutu için Anvil 131072 bayt sınırıyla çalıştırılır.
Testnet kullanmak için yerel süreçleri kapatıp normal geliştirme profilini aç:
varsayılan frontend chain ID 10143 olarak kalır.

## Devam işleri

- `backend/scripts/local-seed.mjs`: teklif seçme, fonlama ve teslim onayı için
  otomatik API + cüzdan tarayıcı testi ekle; iki rolün akışını birlikte doğrula.
- `frontend/app/pages/couriers/index.vue`: doğrulanmış itibar projeksiyonlarını
  kurye profillerine bağla; müşterinin performansa göre seçim yapmasını sağla.

Jüri sözleşmesi ve canlı GPS bu veri setinde oluşturulmaz; bunlar ayrı test
senaryoları gerektirir.
