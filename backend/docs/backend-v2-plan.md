# Monosfer V2 Backend — Fazlı Uygulama Planı

## Contract Sync — 2026-09-13

Başlangıç `9a15adc`, `Monosfer-V2`; yalnız backend kapsamı. Kullanıcının Contract Sync planı uygulandı. Görevler CS.1 state/struct/timestamp, CS.2 RPC/reconcile, CS.3 proof API, CS.4 dispute projection, CS.5 reputation kaynak bildirimi, CS.6 dokümantasyon/doğrulama olarak izlendi: bekliyor → devam ediyor → doğrulanıyor → tamamlandı (yerel test ve read-only Testnet kapsamı).

[Sözleşme ve işletim notları](backend-v2-contract-sync.md), [gerçek test sonuçları](backend-v2-progress.md), [ekip bağımlılıkları](backend-v2-handoffs.md). Production signer/KMS, staging reindex ve eksik contract ABI export'ları dış bağımlılık olarak sürer.

## Faz 7 — Support, audit ve yayın hazırlığı / 2026-09-11

Başlangıç `282c570`, `Monosfer-V2`, yalnız `backend/`. Kullanıcının Faz 7 planı uygulandı. Durum: **bekliyor → devam ediyor → doğrulanıyor → tamamlandı (2026-09-11)**; planın local/test adapter ve read-only Testnet kapsamı için. [Gerçek test günlüğü](backend-v2-progress.md): 81 unit/inject, 38 integration, 13 legacy; preflight, gerçek pg_dump/restore fixture ve canlı salt-okunur Testnet başarılı. API/CLI ayrıntıları [Faz 7 sözleşmesi](backend-v2-release.md) içindedir. Production/provider/gerçek DR kabulü handoff'ta bekler.

| Görev | Uygulama ve kabul koşulu |
| --- | --- |
| F7.1 Support | SIWE cookie + ayrı SUPPORT_WALLETS/ADMIN_WALLETS allowlist. Case oluşturma idempotent; değişiklik Origin/CSRF ister. Atanmış açık case veya admin dışında private/evidence content açılmaz. Indexer stale/integrity/fingerprint/lag ve private link doğrulanır. |
| F7.2 Audit | Privileged sonuç audit ile aynı SQL transaction içinde tutulur; audit commit olmadan private yanıt gönderilmez. Denial ayrı append-only kayıttır. Case notları AES-GCM; audit serbest metin/credential içermez. |
| F7.3 Projection | Finalized delivery projection'dan müşteri/kurye sayaçları; legacy kayıtlar kullanılmaz. Dry-run yazmaz; local-only apply atomik/idempotent rebuild yapar. Reward/referral pending_policy; payout/claim yok. |
| F7.4 Telemetry | Token korumalı status ve Prometheus text metrics; token veya admin ile sampled trace okuma. Body/URL/header saklanmaz. Trace örnekleme varsayılan 0, retention kararı bekler. |
| F7.5 Drills | Ayrı rastgele fixture şemasının gerçek pg_dump/pg_restore turu, encrypted object+key kontrolü, Redis TTL ve erişilemeyen bağımlılık/recovery kontrolleri. Production RTO/RPO ve cluster failover kanıtı değildir. |
| F7.6 Testnet ve teslim | Export bundle adres/ABI kaynağı; chain 10143, finalized block, code/config/hashQuote/indexer RPC salt okunur kontrolü. Tam regresyon, OpenAPI, audit, backend-only diff ve yerel commit; push yok. |

Kararlar: support kapalıyken boş allowlist geçerlidir; açılırken en az bir support/admin wallet zorunludur. Ops token boşsa ops bearer erişimi kapanır. Mevcut production provider kısıtı korunur. Ürün risk/reward/referral politikası, retention/silme, provider hesapları, destek SLA ve production RTO/RPO değerleri uydurulmaz; handoff kaydında bekler.

Doğrulama sırası: strict typecheck/build → unit/inject → gerçek SQL/Redis integration → legacy → OpenAPI → local preflight/restore → canlı salt-okunur Testnet → npm audit → diff kapsamı/yerel commit. Her eksik veya başarısız kontrol ilerleme kaydına yazılır; koşulsuz production-ready ifadesi kullanılmaz.

## Faz 6 — Tracking, realtime ve provider servisleri / 2026-09-08

Başlangıç `555473b`, Monosfer-V2; backend-only. F6.1–F6.6 yerel/test kapsamı: bekliyor → devam ediyor → doğrulanıyor → tamamlandı (2026-09-10). Gerçek sonuçlar ilerleme günlüğünde, çalıştırma/API ayrıntıları [Faz 6 sözleşmesinde](backend-v2-operations.md). Canlı provider hesabı/retention politikası bulunmadığı için yerel/test adapter teslimi yapıldı; production açılmaz. Harici Route/S3/WebPush adapter entegrasyonu ve production kabulü dış bağımlılık olarak bekliyor; bu durum Faz 6'nın production-ready olduğu anlamına gelmez.

| Görev | Davranış / kabul |
| --- | --- |
| F6.1 | Delivery-scoped kısa tracking token; cookie oturumuna ve trusted finalized binding'e bağlı; atanmış courier yayınlar, customer/courier izler. ReadyForPickup/InTransit dışı ve stale indexer deny. |
| F6.2 | Redis TTL + AES-GCM latest/event stream, atomik seq/retry ve bounded history. Ayrı Node SSE process; reconnect cursor/reset, her poll'da auth/binding/expiry revalidation, disconnect/shutdown cleanup. |
| F6.3 | RouteProvider interface, deterministic dev straight-line estimate; private endpoints server-side okunur, şifreli kısa cache, timeout/provider outage fail-closed. |
| F6.4 | Owner-only native evidence metadata/content API; metin/küçük fotoğraf ve opsiyonel GPS, şifreli local object adapter, hash integrity, idempotent SQL outbox + worker. Legacy dispute/evidence veya support erişimi açılmaz. |
| F6.5 | NotificationProvider interface + in-app dev inbox, internal lifecycle/evidence notification üretimi, idempotent bounded retry/dead-letter jobs. Dış Web Push/S3/provider hesabı ve retention handoff. |
| F6.6 | Unit/inject, gerçek SQL/Redis/storage, SSE multi-instance/reconnect/revoke, TTL/seq/yetki, provider retry/kesinti; build/typecheck/legacy/audit/OpenAPI/diff ve yerel commit. |

API: POST/DELETE `/v1/deliveries/:id/tracking/sessions`; POST/GET `.../tracking/location`; SSE GET `.../tracking/events` ayrı realtime process; GET `.../route`; POST `.../evidence`, GET `.../evidence/:evidenceId` ve `/content`; GET `/v1/notifications`. Mutasyonlar SIWE cookie + Origin + CSRF; evidence ayrıca Idempotency-Key. Tracking token yalnız `x-tracking-session` header'ında taşınır; URL/log/cache'e yazılmaz. TTL rakamları yalnız dev/test varsayımlarıdır. Production retention, external providers ve support/dispute yetki matrisi uydurulmaz.

## Faz 5 — Quote, audit ve güvenilir private link / 2026-09-08

Başlangıç `82cf5c9`, `Monosfer-V2`. F5.1–F5.6: bekliyor → devam ediyor → doğrulanıyor → tamamlandı. Sonuçlar `backend-v2-progress.md`, API/operasyon ayrıntıları `backend-v2-quotes.md` içindedir. Yalnız backend; otomatik push yok.

| Görev | Uygulama ve kabul |
| --- | --- |
| F5.1 | Native `quote_api/pending_chain` private kayıt; legacy provenance korunur. `risk_quote_issuances`, `risk_quote_inputs`, `idempotency_keys`, `transactional_outbox` migration ve tekrar çalıştırma. |
| F5.2 | Auth + CSRF + Origin + rate limit ile POST `/v1/quotes/delivery`; `{ declaredValue, metadata: { packageType, urgency }, privatePayload: { pickup, dropoff, notes? } }`. İç içe DTO allowlist, şifreleme, contract biriminde decimal uint96. |
| F5.3 | EIP-712 `MONOSFER/1`, export chain/hub ve tam yedi Quote alanı. Finalized RPC'den signer, riskQuoteValidity ve coverage bandı; imza öncesi RPC `hashQuote` eşitliği. Deterministic dev/test tier 1 adapter; production API/worker kapalı. |
| F5.4 | Wallet + route + deployment + Idempotency-Key kapsamı; HMAC request hash, canonical JSON, SQL advisory lock; private/audit/encrypted response/outbox tek transaction. Aynı body aynı geçerli response; değişen body veya süresi geçmiş key/quote 409. Expired key tombstone korunur, sessiz duplicate üretilmez. |
| F5.5 | Owner-only GET `/v1/quotes/:quoteDigest`; signature/private veri dönmez. POST refresh yalnız finalized timestamp tüm önceki quote expiry'lerinden büyük ve hiçbiri redeemed/linked değilse; aynı record satır kilidi, tek refresh child. Yeni key şarttır. |
| F5.6 | Ayrı `quote:worker -- once/watch`; SKIP LOCKED outbox, transaction, bounded batch/backoff, stale/error/integrity/fingerprint/customer kontrolleri. Sadece trusted finalized projection link yaratır; expired quote'un gecikmiş event'i işlenir. |

Kabul: hash/signature/domain/tamper; gerçek SQL transaction rollback/concurrent idempotency/outbox retry; owner/CSRF/validation; refresh expiry/redeem; stale/projection drift; şifreleme ve redaction; tüm typecheck/build/unit/integration/legacy/audit/OpenAPI/diff kontrolleri. Canlı Testnet transaction, production signer/provider/KMS ve fiyat politikası handoff'tur. Monad concepts yönergesi gereği private erişim ve refresh kararları finalized veri kullanır.

## Faz 4 — Indexer ve projection / 2026-09-07

Başlangıç `cd8d593`, `Monosfer-V2`. Backend-only teslim. Mevcut `contracts/exports` içindeki legacy olmayan DeliveryHub ABI/adres/deployment başlangıç bloğu build sırasında backend dist içine üretilmiş bundle olarak alınır; export fingerprint cursor'a bağlanır. Kontrat dosyaları değiştirilmez. `finalized` bloklar RPC üzerinden salt okunur tüketilir; zincire işlem gönderilmez.

F4.1: SQL event inbox, canonical bloklar, cursor, Delivery/Bid projection ve private link sınırı. F4.2: strict ABI decode, chain/code kontrolü, sıralama/dedup, blok ve cursor atomik commit, bounded batch/retry. F4.3: canonical hash uyuşmazlığında bounded ancestor arama, orphan event koruma ve etkilenen projection rebuild; derin uyuşmazlıkta fail closed. F4.4: aynı inbox'tan replay ve aynı blokta deliveryOf/bidOf/nextDeliveryId reconciliation; fark varsa servis stale/error verir. F4.5: salt okunur `/v1/indexer/status`, `/v1/deliveries`, `/v1/deliveries/:id`, `/v1/deliveries/:id/bids`; bounded pagination, decimal string ID/tutarlar, indexing-pending/stale ayrımı ve OpenAPI. Chain-state yazan HTTP endpoint yoktur.

Worker API process'inden ayrı CLI'dır: once/watch/replay/reconcile. Varsayılan kapalı; açıkken zorunlu RPC/config doğrulanır. Restart DB cursor'dan sürer. Worker hatası, geride kalma veya eski heartbeat confirmed private erişimini kapatır. Faz 3 private service gerçek V2 lifecycle adlarına geçirilir; kurye yalnız ReadyForPickup/InTransit erişir. Legacy source ile projection ID/wallet benzerliği otomatik bağ oluşturmaz. Güvenilir quote digest → private record bağı Faz 5 issuance kaydını gerektirir; bu faz link okuyucusu hazırlar, keyfi link HTTP endpoint'i açmaz.

Kabul: gerçek PostgreSQL ve yerel JSON-RPC fixture üzerinde duplicate/sırasız event, atomic rollback, restart, reorg/deep-reorg, lag/outage, replay eşitliği, reconciliation farkı ve read-only HTTP testleri. Typecheck/build/unit/integration/legacy/audit/OpenAPI/diff çalıştırılır; sonuç ve yerel commit progress'e kaydedilir. Canlı Testnet smoke Faz 7'ye aittir; gerçek dataset indexleme/deploy bu teslimde yapılmaz.

## Faz 3 — Model + import / 2026-09-07

Onaylanan kapsam yalnız backend altında private PostgreSQL modeli, AES-256-GCM, internal erişim sınırı ve salt okunur Mongo envanter/dry-run/import araçlarıdır. Yeni delivery endpoint'i yoktur. Çalışma tabanı `0a6d76c`, dal `Monosfer-V2`.

| Görev | Teslim ve kabul koşulu |
| --- | --- |
| F3.1 | `private-data/crypto.ts`: 32 bayt canonical base64 key, key ID, 12 bayt rastgele IV, 16 bayt tag; AAD kayıt UUID + schema version + domain + kaynak kimliği. Roundtrip ve key/AAD/ciphertext müdahale testleri geçer. |
| F3.2 | SQL: `private_delivery_records`, `private_data_import_runs`, `private_data_import_items`; migration/re-run, kaynak unique constraint ve şifreli saklama gerçek PostgreSQL ile doğrulanır. |
| F3.3 | `PrivateDataService` yalnız confirmed projection üzerinden customer/accepted courier erişimini çözer. Legacy metadata yetki vermez. Kurye yalnız Accepted/InTransit durumlarında pickup/dropoff/contact allowlist'ini alır; kod ve evidence alamaz. |
| F3.4 | Envanter PostgreSQL'e bağlanmaz. Private alan dolulukları, collection sayıları, Mongo user-wallet eşleşme sayıları ve geçersiz kayıt nedenleri değer sızdırmadan raporlanır. |
| F3.5 | CLI dry-run yalnız run/item raporu yazar. Apply item başına transaction, eşzamanlı duplicate koruması, run kilidi ve kesinti sonrası devam sağlar. Gerçek read-only Mongo hesabı ve PostgreSQL ile doğrulanır. |
| F3.6 | Typecheck/build/unit/inject/integration/legacy/audit/diff; gerçek sonuçlar progress dosyasına; yalnız backend içeren yerel commit, otomatik push yok. |

Payload pickup/dropoff dahil alıcı/kod/konum bilgileri, serbest metinler, dispute evidence ve courier location/push token içerir. Şifresiz metadata yalnız doğrulanan network, chain referansları, tx hash'leri, lifecycle status, tutarlar, zamanlar, package/urgency ve rating alanlarıdır. User email/phone aktarılmaz; mevcut Faz 2 alanları değişmez. Bilinmeyen kök alanlar aktarılmaz, kaynak korunur.

Üç record kind aynı şifreli kayıt tablosundadır: `delivery`, `dispute`, `courier_location`. Dispute `parent_legacy_id` ile teslimata bağlıdır; kullanıcı konumu teslimat başına kopyalanmaz. `(source_namespace, source_collection, legacy_mongo_id)` unique'dir. Kaynaklar `legacy_mongo` / `legacy_unverified` kalır; schema bu aktarımın confirmed yazmasını kabul etmez. V2 kullanıcı kaydı veya zincir projection'ı oluşturulmaz.

Ek çalışma kararları: `LEGACY_MONGODB_SOURCE_ID` sabit bir kaynak etiketi olarak zorunludur. Run kimliği `--run-id=<UUID>` ile sürdürülebilir. Başarılı dry-run item'ı `validated`, private alan içermeyen user `skipped_no_private` olur; diğer durumlar pending/imported/skipped_existing/invalid/failed'dır. Dry-run da audit yazdığı için uzak/production PostgreSQL hedefi her iki modda `--confirm-production-import` ister. Bu teslimde production import yapılmaz.

Faz 4 confirmed projection provider'ı gelene kadar runtime erişim varsayılanı deny'dır. Retention, key rotation operasyonu, silme, support/admin ve evidence provider kararları handoffs içindedir. Anahtar kaybı şifreli veriyi okunamaz yapar; mevcut key ID yerinde farklı anahtarla değiştirilmez.

Kaynaklar: [Node 24 crypto — GCM/AAD](https://nodejs.org/docs/latest-v24.x/api/crypto.html), [MongoDB Node cursor — batch/async iteration](https://www.mongodb.com/docs/drivers/node/current/crud/query/cursor/). Yeni npm bağımlılığı eklenmez; Node crypto ve mevcut MongoDB/pg paketleri kullanılır.

Operatör adımları ve sınırlar: [private-data-operations.md](private-data-operations.md).

Tarih: 2026-09-06. Kullanıcının onayladığı kapsam: ilk teslim Faz 1.

## Kararlar

- Çalışma dalı `Monosfer-V2`; başlangıç referansı `4df5d5c`, Faz 1 teslim tabanı `98d7e64` (çalışma sırasında gelen P2.1 merge'ine fast-forward).
- Tüm kod, test, Compose ve doküman değişiklikleri yalnızca `backend/` altında.
- Node.js 24 LTS, strict TypeScript/ESM, NestJS 11, Fastify, PostgreSQL ve Redis.
- Yeni `/v1` sözleşmesi; legacy `/api` uyumluluk katmanı yok.
- Legacy kaynaklar ve testler korunur, V2 runtime bunları yüklemez.
- MongoDB verileri korunur; aktarım Faz 3'te. Legacy kayıtlar on-chain doğrulanmış sayılmaz.
- Frontend, contracts, root scripts ve CI/deploy dosyaları değiştirilmez; ihtiyaçlar handoffs dosyasında tutulur.
- Production deploy, gerçek zincir işlemi, otomatik push ve veri silme kapsam dışı.

## Kayıt ve teslim disiplini

Durumlar: bekliyor → devam ediyor → doğrulanıyor → tamamlandı.
İlerleme: `backend-v2-progress.md`; ekip bağımlılıkları: `backend-v2-handoffs.md`.
Her kayıt tarih, görev kimliği, davranış değişikliği, gerçek test sonucu ve devam notu içerir.
Çalışmayan/çalıştırılmayan kontrol tamamlandı sayılmaz. Her doğrulanmış faz yalnızca backend değişiklikleriyle yerel commit edilir; hash sonraki kayda yazılır.

## Faz 1 — Altyapı

- F1.1: `src/v2/` altında NestJS/Fastify; varsayılan dev/build/start V2; legacy test komutu ayrı.
- F1.2: Config validation; `pg` pool ve parametreli SQL; node-pg-migrate SQL migration; resmi Redis istemcisi; localhost Compose.
- F1.3: `/v1/health/live` 200; `/v1/health/ready` PostgreSQL ve Redis sağlıklıyken 200, değilse 503.
- F1.4: Global DTO validation; bilinmeyen alanları reddetme; standart `{error:{code,message,requestId}}`; JSON log/redaction; CORS allowlist; security headers; body limit; explicit trustProxy.
- F1.5: SIGINT/SIGTERM kapanışı, bağlantı temizliği; OpenAPI JSON, yalnız development Swagger UI.
- F1.6: Temiz npm ci, typecheck, build, unit/inject, gerçek DB/Redis migration/readiness, log redaction, shutdown ve legacy testleri; yalnız backend diff kontrolü.

Veritabanı startup sırasında migrate edilmez. İlk migration sadece `monosfer` şemasını oluşturur. Domain tabloları sonraki fazlarda eklenir.
Redis en fazla üç yeniden bağlantı denemesi yapar; tüketildiğinde readiness 503 kalır ve process yeniden başlatılır. PostgreSQL probe her istekte yeniden denenebilir.
Config ve private connection error metinleri HTTP/loglara aktarılmaz.

## Faz 2 — SIWE, oturum ve minimal profil (2026-09-07)

Gerçek doğrulama sonuçları ve faz durumu `backend-v2-progress.md` içinde izlenir.

- F2.1: Exact SIWE 4.2.1, viem 2.56.3, Fastify cookie 11.1.2; zorunlu auth config ve PostgreSQL migration.
- F2.2: `POST /v1/auth/siwe/nonce`, `POST /v1/auth/siwe/verify`; server tarafından üretilmiş EIP-4361 mesajı, 300 saniyeye kadar nonce TTL, browser challenge cookie bağlamı ve atomik compare/delete.
- F2.3: `GET/DELETE /v1/auth/session`, `DELETE /v1/auth/sessions`; opaque cookie, yalnız hash anahtarları, Redis TTL ve her istekte PostgreSQL expiry/revocation kontrolü. Login ve revoke-all user row lock ile sıralanır.
- F2.4: `GET/PATCH /v1/users/me`; yalnız kendi profilini güncelleme. `customer/courier` kullanıcı tercihidir; yönetici/operasyon yetkisi sağlamaz. Courier profili yalnız `vehicleType` (`on_foot/bicycle/motorcycle/car`), onay belgesi içermez. Email/phone doğrulanmış sayılmaz.
- F2.5: Origin allowlist, cookie mutasyonlarında session'a bağlı HMAC CSRF, Redis üzerinde ortak IP rate limit, hassas alan redaction, OpenAPI ve ekip sözleşmesi.
- F2.6: Unit/inject, gerçek PostgreSQL/Redis migration/replay/TTL/revoke/kesinti, legacy ve shutdown regresyonları; typecheck/build/audit/diff kontrolü. Yalnız backend dosyalarıyla yerel commit; otomatik push yok.

Cookie uygulama düzeltmesi: `__Host-` adı tarayıcıda `Secure` gerektirir. HTTPS ve production için `__Host-monosfer_sid`; development/test HTTP için `monosfer_sid_dev`. İkisi de HttpOnly, SameSite=Lax, Path=/; Domain verilmez. Login CSRF için ayrıca kısa ömürlü challenge cookie gerekir. `SESSION_COOKIE_SECRET` cookie değerini değiştirmeden session'a bağlı CSRF üretiminde kullanılır; en az 32 karakter, ortam başına rastgele üretilir.

Zorunlu env: SIWE_DOMAIN, SIWE_URI, SIWE_CHAIN_ID, SIWE_STATEMENT, SIWE_RPC_URL, SESSION_COOKIE_SECRET, SESSION_TTL_SECONDS, NONCE_TTL_SECONDS, AUTH_RATE_LIMIT_WINDOW_SECONDS, AUTH_RATE_LIMIT_MAX. Örnek geliştirme TTL 86400 saniye, nonce 300, rate 60/60 saniye; bunlar production ürün politikası onayı değildir. SIWE URI origin'i CORS listesinde ve host'u SIWE_DOMAIN ile aynı olmalı. Production SIWE URI/RPC HTTPS olmalı.

EOA imzaları yerel kriptografik doğrulanır; deployed ERC-1271 için RPC chain ID ve read-only signature çağrısı kullanılır. ERC-6492/counterfactual cüzdanlar bu teslimde desteklenmez. Gerçek zincire işlem gönderilmez.

Kabul: impersonation/replay/domain-chain-URI/expiry, login CSRF ve protected CSRF reddi, logout/revoke-all sonrası 401, role escalation reddi, gerçek Redis rate/TTL ve hata 503 redaction, OpenAPI sözleşmesi, backend-only diff ve gerçek test kayıtları. Wallet/browser uyumu frontend smoke test devrine yazılır.

Resmi kaynaklar: [SIWE kaynak ve adapter](https://github.com/signinwithethereum/siwe), [EIP-4361](https://eips.ethereum.org/EIPS/eip-4361), [Fastify cookie uyumluluğu](https://github.com/fastify/fastify-cookie), [Nest cookie](https://docs.nestjs.com/techniques/cookies), [viem](https://viem.sh/docs/getting-started).

## Sonraki fazlar

| Faz | Kapsam | Kabul koşulları |
| --- | --- | --- |
| 2 | SIWE nonce/signature, session/revoke, User/Courier, authorization, rate limit | Replay, wallet impersonation, yanlış domain/chain ve expiry testleri |
| 3 | Private data, şifreleme, lifecycle erişimi, MongoDB aktarımı | Salt okunur envanter, dry-run, tekrar çalıştırılabilir aktarım, kimlik eşleme ve tutarlılık raporu |
| 4 | Indexer inbox/cursor, V2 event projection, replay, reconciliation | Duplicate/sırasız event, reorg/restart, lag; API chain state'i keyfi değiştiremez |
| 5 | Risk/price adapter, EIP-712 quote/audit, idempotency, outbox/workers | Contract hash eşitliği, expiry/rotation, duplicate side-effect olmaması |
| 6 | Scoped tracking/realtime/TTL, Route/ETA, evidence, notification | Yetkisiz erişim, reconnect, retention ve provider kesintileri |
| 7 | Reputation/referral/reward, support API, telemetry, DR | Restore drill, failover, projection rebuild, Testnet smoke ve audit |

Her faz başlamadan API ve test senaryoları bu dosyada detaylandırılır.
Risk policy, retention, provider hesapları, RTO/RPO uydurulmaz; ilgili ekip kararları kayıt altına alınır.
Kontratların yalnız V2'ye birleşmiş ABI/deployment export'ları tüketilir. P2.1 ayrı daldaysa tamamlanmış varsayılmaz.

## Kaynaklar ve sürüm kararı

- Kullanıcının teknoloji baseline dokümanı, bölümler 18.1–18.6 ve Şekil 4.
- [Nest Fastify](https://docs.nestjs.com/techniques/performance)
- [Nest OpenAPI](https://docs.nestjs.com/openapi/introduction)
- [node-postgres pooling](https://node-postgres.com/features/pooling)
- [node-pg-migrate](https://github.com/salsita/node-pg-migrate)
- [Redis Node istemcisi](https://github.com/redis/node-redis)

Yeni bağımlılıklar exact sürümlü ve npm lockfile ile sabittir. NestJS 11.2.3, Swagger 11.4.7 ve Fastify 5.12.3 kullanılır.
Nest adaptörünün sabitlediği eski Fastify kopyasında güvenlik bulgusu çıktığı için Fastify 5.12.3 override uygulanır; tip kontrolü ve HTTP testleriyle doğrulanır. NestJS 12'ye major upgrade yapılmaz.
Legacy bağımlılıkların mevcut semver aralıklarındaki güvenlik düzeltmeleri lockfile'a alınır.

## Doğal devam görevleri

1. SIWE tarayıcı entegrasyonu: frontend ekibi cookie/CSRF ve gerçek wallet akışını smoke test etsin; production origin/TTL/rate kararları kesinleşsin.
2. Faz 3 private veri/aktarım: şifreleme ve veri sahipliği sınırını kurup mevcut MongoDB için salt okunur envanter/dry-run hazırlamak.
