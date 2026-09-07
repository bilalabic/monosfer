# Faz 5 quote sözleşmesi ve operasyon

Bu teslim development/test içindir. Gerçek fiyat sağlayıcısı veya üretim risk politikası içermez. `NODE_ENV=production` altında quote API ve link worker 503/kapalı davranır; sadece ortam adını değiştirerek production'a açılmamalıdır. Yeni npm paketi eklenmedi; mevcut viem kullanılır.

## API

SIWE oturumu cookie ile taşınır. Tüm quote endpoint'leri auth rate bütçesini paylaşır. POST isteklerinde izinli `Origin`, session response'tan alınan `x-csrf-token` ve 16–128 karakter `[A-Za-z0-9._:-]` `Idempotency-Key` gerekir. Önerilen key her kullanıcı eylemi için yeni UUID'dir; ağ retry'ında aynı key/body kullanılır. HTTP response cache edilmez.

`POST /v1/quotes/delivery` → 201:

```json
{
  "declaredValue": "10000",
  "metadata": { "packageType": "document", "urgency": "standard" },
  "privatePayload": {
    "pickup": { "address": "Pickup address", "lat": 41, "lng": 29, "contactPhone": "+905551234567" },
    "dropoff": { "address": "Dropoff address", "lat": 40, "lng": 28, "recipientName": "Recipient" },
    "notes": "Optional private note"
  }
}
```

Tüm adres/konum/iletişim alanları `privatePayload` altındadır ve AES-256-GCM ile saklanır. Pickup ve dropoff için address/lat/lng zorunludur. Dropoff opsiyonları OpenAPI'de listelenir; bilinmeyen alanlar ve null reddedilir. Package enum: document/food/small/medium/large; urgency: standard/express/instant. GPS/evidence takibi bu endpoint'e eklenmez. Wallet/customer, chain state, tx hash, risk tier ve coverage istemciden alınmaz.

Response: `{ privateRecordId, quoteDigest, quote, signature, typedData, expiresAt, status: "issued" }`. Quote tam olarak customer/riskTier/declaredValue/requiredCoverage/issuedAt/expiresAt/salt içerir. Domain `MONOSFER`, version `1`, chain `10143`, export DeliveryHub adresidir. Tutarlar ve quote timestamp'leri decimal string; riskTier ve domain chainId number. Dış response `expiresAt` ISO 8601'dir. Bu değerler contract birimindedir; fiat/token dönüşümü yoktur.

Frontend `DeliveryHub.createDelivery(quote, signature)` çağırır; uint alanlarını kayıpsız BigInt'e çevirebilir. Backend zincire işlem göndermez. Signature/quote/private payload analytics, tarayıcı logu veya service-worker cache'ine yazılmamalıdır. Backend gas/fee hesaplamaz.

`GET /v1/quotes/:quoteDigest` → 200: `{ quoteDigest, privateRecordId, expiresAt, status, deliveryId }`. Yalnız owner erişir; başka wallet 403, bilinmeyen digest 404. Signature/typedData/private payload dönmez. Durumlar issued/expired/refreshed/redeemed/linked; `deliveryId` yalnız fresh ve integrity-checked finalized projection varsa döner. `issued` tek başına zincirde kullanılmadığının kanıtı değildir. Indexer stale iken linked/confirmed veri gösterilmez; frontend ayrıca `/v1/indexer/status` izlemelidir.

`POST /v1/quotes/:quoteDigest/refresh` → 201, body `{}` veya boş. Yeni idempotency key ile aynı private kayıt için yeni quote üretilir; private içerik değiştirilemez. Eski quote'un expiry saniyesi contract tarafından hâlâ geçerli kabul edildiğinden finalized blok zamanı **strictly greater** olmalıdır. Aynı record'un tüm quote geçmişi `quoteRedeemed` üzerinden kontrol edilir; linked/redeemed, aktif quote veya zaten refresh edilmiş parent 409 döner. Her parent için tek child vardır. Refresh'in ağ retry'ı aynı key ile aynı geçerli yanıtı alır.

Hatalar `{ error: { code, message, requestId } }`: 400 body/key, 401 auth, 403 owner/CSRF/Origin, 404 digest, 409 conflict/expiry, 429 rate, 503 provider/signer/DB/Redis/disabled. Retry sırasında policy/signer/export değişmiş veya quote süresi geçmişse eski signature yeniden verilmez. Süresi dolan idempotency key tombstone olarak korunur; farklı body veya expired key yeni kayıt üretmez. TTL yalnız replay süresidir; retention/silme işi değildir.

## Veri ve güven sınırı

Native kayıt provenance `source=quote_api`, `verification_status=pending_chain`, legacy id/import run null. Migration eski Mongo kayıtlarının `legacy_mongo/legacy_unverified` sınırını korur. Private record/AAD kaynak bağlamı `quote-api-v1`, delivery schema 1'dir. Kalıcı doğrulama izni yalnız Phase 4 projection join'iyle hesaplanır; API private kayıtları confirmed diye işaretlemez.

Private kayıt, quote audit, risk input/snapshot, encrypted idempotency response ve outbox tek transaction'da commit edilir. HMAC request hash private alanların offline sözlük saldırısına açık düz SHA hash'ini saklamaz; yanıtın signature ve salt dahil tamamı şifrelenir. Audit quote'u public struct ve snapshot metadata içerir. Private payload, salt, signature veya signer key loglanmaz. Key rotasyonu, HMAC/replay anahtarları ve eski ciphertext okuma planı production öncesi birlikte tasarlanmalıdır.

Her issuance finalized blokta chain ID, Hub bytecode varlığı, export ProtocolConfig adresi, configured signer, validity ve coverage bandını okur; RPC timeout/retry sınırlıdır. Contract `hashQuote` ile backend hash'i eşit olmalı ve snapshot block hash değişmemelidir. ABI tuple alanları startup'ta doğrulanır. Full deployed-bytecode attestation bu kontrolden ayrı bir operasyon işidir.

Adapter arayüzü input + policy snapshot → riskTier/requiredCoverage/policyVersion biçimindedir. Deterministic dev policy tier 1 ve contract'ın minimum coverage bandını kullanır; sıfıra yuvarlanan coverage reddedilir. İleride farklı tier/policy sağlayıcısı eklendiğinde ilgili tier'in contract bandını okuyan snapshot adapter'ı da değiştirilmelidir. Bu davranış production fiyatlama kararı değildir.

## Yerel worker

`.env.example` quote değişkenlerini içerir. Varsayılan signer boş ve worker false'tur. API issuance için testnet deployment ile eşleşen `INDEXER_ENABLED=true`, RPC ve test signer gerekir; signer contract `riskQuoteSigner` ile eşleşmelidir. Mevcut `.env` değiştirilmez. Gerçek anahtar commit edilmez.

```sh
npm run db:migrate
npm run quote:worker -- once
npm run quote:worker -- watch
```

Worker için `QUOTE_LINK_WORKER_ENABLED=true` gereklidir. CLI sadece localhost `monosfer_v2` / `monosfer_v2_test` veritabanına yazar. Production/uzak DB açma flag'i bu teslimde yoktur. Worker imza üretmez ve signer anahtarına ihtiyaç duymaz. HTTP process'inde otomatik worker başlatılmaz. SIGINT/SIGTERM devam eden sınırlı transaction'ı bitirir, polling'i iptal eder ve pool'u kapatır.

Worker en fazla 20 due outbox kaydını transaction başına tek item olarak işler; `FOR UPDATE SKIP LOCKED` concurrent worker çakışmasını önler. Private record kilidi refresh ile koordinasyon sağlar. Stream satır kilidi ve digest/customer/export-fingerprint, ready/integrity, head eşitliği, heartbeat kontrolleri uygulanır. Link + completed outbox atomiktir. No projection/mismatch durumunda 1–60 saniye backoff; worker hatasında watch process'i de en fazla 60 saniye backoff uygular. Outbox expiry'de silinmez: gecikmiş finalized redemption link oluşturabilir.

İzleme için pending sayısı, attempts ve oldest pending yaşı SQL'den incelenebilir. Payload loglanmaz. Stale/fingerprint/integrity sorunu önce indexer reconciliation ile giderilir. Reorg sonrası mevcut link reader digest/customer kontrolünü kaybederse private erişim kapanır; completed outbox'ın farklı delivery ID'ye yeniden bağlanması için ayrı recovery/projection-rebuild prosedürü gereklidir. Bu faz otomatik yeniden bağlama veya veri silme yapmaz.

## Doğrulama ve sonraki işler

Unit/inject, gerçek PostgreSQL migration/concurrency/rollback, gerçek Redis rate/outage ve yerel salt okunur JSON-RPC fixture testleri bulunur. Hash fixture, Solidity `abi.encode` + keccak formülünü bağımsız uygular; viem `hashTypedData` sonucunu kendisiyle karşılaştırmaz. Yerel RPC bir EVM değildir; canlı deployed contract/EVM smoke bu testlerin yerine geçmiş sayılmaz. Gerçek Testnet transaction Faz 7'dedir.

1. Güvenlik/operasyon: production policy/provider, signer KMS/HSM/rotation, encryption key lifecycle ve recovery prosedürlerini kararlaştırmak; ardından deployed contract read-only hash smoke.
2. Ürün/API: frontend quote → wallet createDelivery → indexing pending/confirmed akışını entegre etmek; Faz 6 tracking/provider sözleşmesini planlamak.

Kaynaklar: [viem local signing](https://viem.sh/docs/accounts/local/signTypedData), [EIP-712](https://eips.ethereum.org/EIPS/eip-712), repo `contracts/src/v1/risk/CoverageQuote.sol`, `RiskQuoteVerifier.sol` ve `contracts/docs/risk-quote.md`.
