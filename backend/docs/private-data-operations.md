# Faz 3 private veri ve aktarım

Tüm komutlar `backend/` dizininden çalıştırılır. Runtime için `.env.example` içindeki `PRIVATE_DATA_MASTER_KEY_B64` (rastgele 32 bayt, base64) ve `PRIVATE_DATA_KEY_ID` zorunludur. Gerçek anahtarı Git'e veya loglara koymayın. Anahtarı kalıcı secret deposunda saklayın; restart'ta yeniden üretmeyin. Key ID bilinmiyorsa, anahtar/AAD/tag uyuşmazsa decrypt kapalı kalır. Bu faz tek aktif key kullanır; çoklu key/key rotation aracı dahil değildir. Yedek ve anahtar birlikte geri yüklenebilmelidir.

Mongo ayarları yalnız CLI içindir; API başlatılırken okunmaz. `LEGACY_MONGODB_URI`, `LEGACY_MONGODB_DATABASE`, `LEGACY_MONGODB_SOURCE_ID` gerekir; read preference varsayılan `secondaryPreferred`, alternatif `primary`. Kaynak etiketi aynı dataset için sabit ve farklı dataset'ler için farklı olmalıdır. URI/credential değişiminde etiketi değiştirmeyin. Import hesabına yalnız belirtilen DB üzerinde `read` rolü verin. `secondaryPreferred` tek başına read-only yetki sağlamaz. Araç native Mongo client ile yalnız find/count kullanır; Mongoose auto-index/auto-create çalıştırmaz. Read concern değiştirilmez; Mongo transaction veya snapshot varsayılmaz.

```sh
npm run db:migrate
npm run private:inventory
npm run private:migrate -- --dry-run
npm run private:migrate -- --apply
# Başlangıç event'inde verilen UUID ile kesilen/hatalı run'ı sürdür:
npm run private:migrate -- --apply --run-id=<UUID>
```

Her iki migration modu da PostgreSQL run/item raporu yazar. Dry-run domain tabloya yazmaz; validation/encrypt/decrypt çalıştırır. Envanter PostgreSQL'e bağlanmaz ve şifreleme key'i gerektirmez. CLI JSON'u stdout'a, sabit hata event'lerini stderr'e yazar. Çıkış kodları: 0 başarılı; 1 config/bağlantı/run hatası; 2 en az bir invalid/failed/pending item. Ham Mongo belge, wallet, connection URI veya hata metni loglanmaz. CLI varsayılanında güvenli hata kodu verilir; ayar adları `.env.example` üzerinden kontrol edilir.

Local yazma guard'ı yalnız localhost/127.0.0.1/::1 ve `monosfer_v2`/`monosfer_v2_test` PostgreSQL hedefini kabul eder. Diğer hedefler veya NODE_ENV=production için `--confirm-production-import` gerekir; dry-run audit yazısı da bu kurala tabidir. Bu bayrak mevcut teslimde kullanılmadı. CLI hiçbir modda şema migration'ını otomatik çalıştırmaz veya MongoDB'ye yazmaz.

Import kimlik eşlemesi run/item tablosunda source collection + legacy Mongo ID → private record UUID biçimindedir. Dispute, legacy delivery ID ile bağlanır; Mongo parent yoksa `MISSING_PARENT` olur. Customer/courier wallet formatı doğrulanıp lowercase tutulur; V2 user veya SIWE sahipliği üretilmez. Inventory wallet eşleşmeleri yalnız legacy users içindeki varlığı gösterir; on-chain/SIWE doğrulaması değildir.

Her item'ın domain insert'i ile imported/skipped raporu aynı PostgreSQL transaction'ındadır. Domain unique constraint eşzamanlı run'larda duplicate'i engeller. Run için PostgreSQL session advisory lock vardır; process bağlantısı kapanınca kilit serbest kalır. Retry pending/failed/invalid item'ları yeniden değerlendirir, başarılı item'ları korur. Tamamlanmış aynı run yeni belgeleri taramaz: değişen kaynak için yeni run ID kullanın. Önceden aktarılmış kaynak kimliği `skipped_existing` olur; değişen kaynak payload'ını overwrite etmez. Kaynak güncellemelerinin delta eşlemesi ayrı iş olarak ele alınmalıdır.

Envanter ve import snapshot değildir. Kaynak tarama sırasında değişirse sayımlar veya parent görünürlüğü farklı olabilir; rapor `best_effort_non_snapshot` olarak etiketlenir. Üretim aktarımından önce ekip salt okunur snapshot veya yazmaların duracağı pencere sağlamalı, invalid/failed ve kayıt sayıları gözden geçirilmelidir. Geçersiz/çok büyük (>1 MiB) payload otomatik düzeltilmez; Mongo belgesi korunur. Kapsam dışı legacy user email/phone ve bilinmeyen kök alanlar import edilmez. Özet rapor ile SQL item eşlemesi birlikte tutarlılık incelemesi sağlar.

Runtime `PrivateDataService` dışarıya HTTP endpoint açmaz. `readDelivery(id, authenticatedWallet)` server'ın doğruladığı wallet ile çağrılır. Faz 4'te confirmed projection provider'ı takılana kadar bütün erişimler reddedilir; body'den lifecycle/assignment alınmaz. Confirmed customer kendi delivery payload'ını; confirmed assigned courier yalnız Accepted/InTransit aşamalarında allowlist alanları alır. Courier teslimat kodu, recipient wallet, serbest timeline/notes, evidence ve kullanıcı live location/push token alamaz. Dispute ve courier_location archive'ları bu servisten okunamaz. Retention/silme ve support yetkileri bu fazda tanımlanmaz.

## Yerel doğrulama

```sh
docker compose --profile private-tests up -d --wait
npm run typecheck
npm run build
npm test
npm run test:integration
npm run test:legacy
npm audit
git diff --check
```

Mongo test servisi localhost:57017 üzerindedir. Compose init script'i `monosfer_legacy_test` DB'sine yalnız read yetkili `legacy_reader` kullanıcısını açar. Entegrasyon yalnız bu fixture DB'sini kullanır; ayrı fixture_admin hesabı ile rastgele ObjectId/wallet belgeleri oluşturup test sonunda yalnız kendi belgelerini kaldırır. Uygulama CLI'si sadece reader hesabını alır. Test PostgreSQL run/record/item kayıtları rastgele source namespace ile izole edilir ve yalnız o namespace temizlenir. MongoDB/Redis/PostgreSQL çalışmıyorsa test skip edilmez, fail eder.

Doğal devam: (1) anahtar yedek/rotation/restore doğrulaması ve retention kararlarının netleşmesi; (2) Faz 4 confirmed projection ve private-record kimlik bağının uygulanması.
