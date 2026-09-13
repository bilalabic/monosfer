# Faz 7 — Support, audit, reputation ve operasyon sözleşmesi

Bu teslim yalnız backend'i kapsar. Support ve ops yetkileri ayrı tutulur; profil `role` alanı privileged yetki vermez. Nihai test durumu [ilerleme günlüğündedir](backend-v2-progress.md).

## Kurulum ve yetki

`npm.cmd run db:migrate` release-operations ve support-idempotency-response migration'larını uygular. Runtime otomatik migration çalıştırmaz. `SUPPORT_ENABLED=true` için `SUPPORT_WALLETS` veya `ADMIN_WALLETS` en az bir geçerli, sıfır olmayan Ethereum adresi içermeli; virgülle ayrılır ve normalize edilir. Kapalı support endpoint'leri kimlik doğrulamasından sonra 503 döner. İmzasız/oturumsuz istek 401, allowlist dışı kullanıcı 403 alır. Mutation'larda Origin + CSRF şarttır.

Private/evidence okuma bir SQL transaction içinde indexer stream, delivery ve private link'i paylaşım kilidiyle doğrular. Kaynak hazır, güncel, aynı fingerprint ve sıfır lag olmalı. Native quote private link/customer eşleşmesi gerekir. Admin private okumada case zorunluluğunu aşabilir; support wallet aynı stream/delivery için open veya investigating case'e atanmış olmalıdır. Kapalı case yetki sağlamaz. Atama/closure aynı satırlarda transaction kilidiyle seri hale gelir.

## HTTP sözleşmesi

| Endpoint | Yetki ve yanıt |
| --- | --- |
| `GET /v1/support/deliveries/:id` | Support/admin; finalized delivery, salt/signature içermeyen quote özeti, privateRecordId, evidence metadata ve notification sayısı. |
| `GET /v1/support/deliveries/:id/private` | Admin veya aktif case ataması; pickup/dropoff address, coordinates ve sınırlı kişi/iletişim alanları. Delivery code, keyfi notes, live GPS history ve legacy dispute yok. |
| `GET /v1/support/deliveries/:id/evidence` | Support/admin; `data` içinde id/content_type/status/created_at, en fazla 100 öğe ve `hasMore`. |
| `GET /v1/support/deliveries/:id/evidence/:evidenceId/content` | Admin veya aktif atama; yalnız aynı trusted binding'e ait ready evidence. SHA-256 + AES-GCM doğrulanır. Dev/test storage açık olmalı. |
| `POST /v1/support/cases` | Support/admin; `{id,assignee?,note?}`. `id` decimal delivery ID, `assignee` allowlisted wallet, `note` en fazla 2000 karakter. Idempotency-Key zorunlu. 201. |
| `GET /v1/support/cases` | Support/admin; `limit` 1..100 (25), opsiyonel UUID `after`, `{data,nextCursor}`. |
| `GET /v1/support/cases/:caseId` | Support/admin; case metadata + son 100 event metadata; serbest metin note dönmez. |
| `PATCH /v1/support/cases/:caseId` | Support/admin; boş olmayan `{status?,assignee?,note?}`, status open/investigating/closed; null assignee atamayı kaldırır. |
| `GET /v1/admin/audit` | Yalnız admin; `limit` 1..100 ve decimal audit ID `after`, `{data,nextCursor}`. |
| `GET /v1/users/me/reputation` | SIWE; kendi finalized sayaçları, referral/reward pending_policy. |
| `GET /v1/support/wallets/:wallet/reputation` | Support/admin; aynı projection yanıtı ve audit. |
| `GET /v1/ops/status` | `Authorization: Bearer <OPS_METRICS_TOKEN>`; DB/Redis, schema, indexer lag, job/outbox sayıları ve rebuild özeti. |
| `GET /v1/ops/metrics` | Aynı token; Prometheus text exposition 0.0.4. Sayısal label'sız metrikler. |
| `GET /v1/ops/traces/:requestId` | Ops token veya SIWE admin; fixed http_response event, status_code, duration_ms, created_at. En fazla 100. |

Case yanıt alanları: `id`, `stream`, `delivery_id`, `status`, `assignee`, `created_by`, `created_at`, `updated_at`. Create body aynı key ile tekrarlandığında özgün oluşturma yanıtı döner; sonraki PATCH yanıtı değiştirmez. Aynı key/farklı body 409. Scope wallet + deployment stream + operation üzerinden anahtarlı hash'tir. `SUPPORT_CASE_IDEMPOTENCY_TTL_SECONDS` dolunca key yeni case için kullanılabilir; eski case/audit silinmez.

Hatalar `{error:{code,message,requestId}}` sözleşmesini korur. Private erişim yetkisiz/missing link olduğunda 403; indexer güveni veya bağımlılık bozulduğunda 503; yok case/evidence 404; ready olmayan evidence/idempotency çakışması 409; DTO hatası 400. Request/response body, URL query veya secret loglanmaz. Tarayıcıya ops token verilmez; metrics internal scraper/operator içindir.

## Audit ve telemetry

Başarılı privileged iş + audit aynı PostgreSQL transaction'ındadır. Audit yazılamazsa case/event değişikliği rollback olur ve private yanıt teslim edilmez. Auth/allowlist/CSRF ve servis denial'ları ayrı transaction'da sabit reason code ile kaydedilir. Audit requestId, actor wallet, fixed action, target type/id, decision/reason ve timestamp içerir. Notes/evidence içeriği audit'e taşınmaz. SQL trigger UPDATE/DELETE/TRUNCATE'ı reddeder; migration owner/superuser yetkisi ayrıca operasyon kontrolü gerektirir.

`OPS_TRACE_SAMPLE_RATE=0` varsayılanı telemetry depolamasını kapatır. Açıldığında sampled `onResponse` kaydı cevaptan sonra görünür; ilk trace sorgusu henüz boş olabilir. Otomatik retention silmesi uygulanmaz. Process metrikleri restart'ta sıfırlanır, SQL backlog metrikleri tüm backend kuyruklarını sayar. `status=degraded` bağımlılık veya indexer hazır olmadığını belirtir; 200 teşhis yanıtıdır. Sağlık readiness endpoint'i önceki PG/Redis 200/503 sözleşmesini korur.

## Projection ve CLI

Sayaçlar `customerDeliveries`, `courierDeliveries`, `customerCompleted`, `courierCompleted`, `returned`, `cancelled`, `expired` decimal string'leridir. Skor veya ekonomik yorum yoktur. Aynı wallet iki rolü üstlenirse her rol gözlemi sayılır. Legacy veri, serbest kullanıcı beyanı veya canonical olmayan event kullanılmaz; kaynak Phase 4 trusted finalized delivery projection'dır. Kaynak block/hash/fingerprint değişmişse eski sayılar sunulmaz, `rebuild_pending` döner.

```sh
npm run openapi:export
npm run ops:preflight
npm run ops:rebuild-projections -- --dry-run
npm run ops:rebuild-projections -- --apply
npm run ops:restore-drill -- --fixture
npm run ops:testnet-smoke
```

Normal CLI gerçek `.env` konfigürasyonunu gerektirir. `tests/support/release-cli.mjs preflight|restore|smoke` açıkça local fixture doğrulaması için test ayarları üretir; runtime'a yüklenmez, gerçek `.env` değiştirmez. Local preflight indexer kapalıyken altyapı kontrollerini geçebilir; `ops.indexer.status=disabled`, `ops.status=degraded` ve `productionReady=false` ayrıca raporlanır.

Rebuild dry-run domain/projection/drill tablosuna yazmaz. Apply yalnız non-production, localhost ve açık dev/test DB isimleri için çalışır; tek trusted stream'in derived projection'larını atomik yeniler. Audit/case/source event değişmez. Worker scheduling/deploy bu teslimin dışındadır.

Restore fixture backend Compose PostgreSQL (localhost:55432, monosfer kullanıcısı), Redis ve Docker CLI ister. Rastgele yeni `ops_fixture_<uuid>` şeması oluşturur, native `pg_dump -Fc` ile yedekler, kaynak fixture şemasını yeniden adlandırır ve `pg_restore` ile ayrı kopyayı doğrular. Encrypted object kopyası, AAD/key doğrulaması, yanlış key reddi, fixture Redis TTL ve erişilemeyen ayrı PG/Redis istemcilerinin kontrollü hatası sınanır. Bitişte yalnız bu invocation'ın oluşturduğu şema/key/geçici dosyalar temizlenir; özet `ops_drill_runs` içinde kalır. Bu local restore kanıtıdır; production backup/PITR/replica failover testi değildir. Default 60 saniye yalnız fixture hedefidir.

Smoke `TESTNET_SMOKE_RPC_URL` gerektirir. Build export bundle dışında ABI/adres kaynağı kullanmaz. ChainId 10143, taze finalized block, hub/config bytecode, config bağlantısı/signer/validity/coverage bounds, contract `hashQuote` eşitliği, aynı bloktaki indexer block/log okuması ve tekrar block hash kontrolü yapılır. Hiç signer/private key/transaction gerekmez. Çıktı yalnız başarı aşamaları/sabit hata kodu ve public block/fingerprint içerir; RPC credential göstermez. Referanslar: [Monad JSON-RPC](https://docs.monad.xyz/reference/json-rpc/api), [Monad Testnet](https://docs.monad.xyz/developer-essentials/testnet).

## Sonraki iki iş

1. Güvenlik/operasyon: runtime DB least-privilege, KMS/object off-site restore, trace/audit retention ve gerçek provider hesaplarıyla DR kabulü.
2. Ürün/API: support UI/browser SIWE-CSRF senaryoları, destek notlarının okunma kapsamı ve referral/reward ekonomi kararlarının ayrı fazda somutlaştırılması.
