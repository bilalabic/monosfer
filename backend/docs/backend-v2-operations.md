# Faz 6 — Tracking ve provider sözleşmesi

Teslim kapsamı: yerel/test, `Monosfer-V2`, yalnız `backend/`. Gerçek harita, S3 ve WebPush hesapları/adapter'ları yoktur. Production açılması desteklenmez: `NODE_ENV=production` ile `OPERATIONS_ENABLED=true` startup'ı reddeder. Varsayılan kapalıyken mevcut Faz 1–5 çalışması korunur; yeni domain servisleri 503 verir.

## Yetki ve güven sınırı

Tüm endpoint'ler SIWE cookie ve ortak Redis IP rate limit kullanır. Mutasyonlar ayrıca allowlist Origin + `x-csrf-token` ister. Kullanıcının `role` tercihi yetki vermez; müşteri/kurye kimliği finalized delivery projection'ından alınır. `private_delivery_links` bağı, quoteDigest/customer, export fingerprint, indexer ready/integrity, güncel heartbeat ve cursor/head eşitliği zorunludur. Legacy Mongo benzer ID/wallet ile bağlanmaz.

Tracking, route ve yeni evidence oluşturma yalnız `ReadyForPickup` / `InTransit` sırasında yapılır. Customer ve mevcut atanmış courier izleyebilir; yalnız atanmış courier konum yayınlar. Binding deployment + delivery + private record + quoteDigest + customer + courier + fingerprint içerir. Atama/deployment değişince önceki token, cache ve evidence erişim bağlamı geçersizleşir. Bilinmeyen/terminal durumlarda tracking/route kapalıdır. Evidence metadata/content ve inbox, bilinen terminal durumlarda da güncel katılımcı/binding kontrolünden geçer; evidence ayrıca yalnız yükleyene aittir. Customer, courier'ın evidence içeriğini okuyamaz. Support/admin veya legacy dispute okuma endpoint'i eklenmedi.

## HTTP sözleşmesi

Aşağıdaki yolların önünde `/v1` vardır. ID contract uint256 decimal string, evidenceId UUID'dir. JSON bilinmeyen alanları reddeder. HTTP hatası `{error:{code,message,requestId}}`; session yoksa 401, token/yetki/lifecycle/indexer güveni yoksa 403, malformed input 400, çakışma 409, rate/capacity 429, bağımlılık/kapalı özellik 503.

| Metot / yol | Girdi | Sonuç |
| --- | --- | --- |
| POST `/deliveries/:id/tracking/sessions` | `{}` | 201 `{trackingSession,expiresAt,mode:"publish" veya "view"}` |
| DELETE `/deliveries/:id/tracking/sessions` | `x-tracking-session` | 204; mevcut delivery token'ını iptal eder |
| POST `/deliveries/:id/tracking/location` | Token header + `{lat,lng,sequence,capturedAt,accuracyMeters?}` | 201 `{eventId}` |
| GET `/deliveries/:id/tracking/location` | Token header | 200 `{eventId,location}`; TTL sonrasında iki alan da null |
| GET `/deliveries/:id/tracking/events` | Token header, opsiyonel `Last-Event-ID` | Ayrı realtime process: SSE |
| GET `/deliveries/:id/route` | — | 200 `{provider,distanceMeters,durationSeconds,estimatedAt,expiresAt}` |
| POST `/deliveries/:id/evidence` | `Idempotency-Key` + evidence JSON | 201 `{evidenceId,status,contentType}` |
| GET `/deliveries/:id/evidence/:evidenceId` | — | 200 aynı metadata |
| GET `/deliveries/:id/evidence/:evidenceId/content` | — | 200 içerik JSON + `evidenceHash`; pending/failed ise 409 |
| GET `/notifications?limit=25&before=<UUID>` | Limit 1–50; opsiyonel cursor | 200 `{data:[{id,deliveryId,template,arguments,createdAt}],nextCursor}` |

Tracking token'ı 32 random byte hex'dir, yalnız `x-tracking-session` header'ında ve bellekte tutulur. Cookie session hash'ine bağlıdır; başka oturuma/cüzdana/delivery'ye taşınamaz. Aynı SIWE oturumu/delivery için yeni token öncekinin yetkisini kaldırır. Token TTL, SIWE session'ın kalan süresini aşamaz; logout/revoke-all sonraki istek/poll'da erişimi kapatır. Token URL, localStorage, analytics veya loglara yazılmaz.

`sequence` pozitif artan integer, en fazla 2147483647; aynı token'da aynı seq/body retry'ı aynı eventId verir. Aynı seq farklı body, azalan seq veya ilerlemeyen capturedAt 409. Geçmiş örnek location TTL'den eski, gelecek örnek 5 saniyeden ileri olamaz. Konumun `receivedAt` ve `expiresAt` değerlerini sunucu ekler; TTL alımdan itibaren işler, polling süreyi uzatmaz. Redis latest ve bounded stream payload'ı AES-256-GCM şifrelidir; anahtarlar binding/token hash kullanır. Stream en fazla 128 kayıt, poll en fazla 32 kayıt okur; history TTL sonunda silinir. Session/seq ve slot anahtarları da TTL'lidir.

## Ayrı realtime process ve reconnect

`npm run realtime` build edip ayrı Nest/Fastify process'ini `REALTIME_PORT` üzerinde başlatır. Bu process health, paylaşılan auth ve SSE endpoint'lerini içerir; quote/provider/domain write API barındırmaz. İki servis aynı PostgreSQL, Redis, private key, SIWE cookie/CSRF secret ve indexer deployment config'ini kullanmalıdır. `/v1/openapi.json` her process'in kendi sözleşmesidir; `npm run openapi:export`, offline olarak `artifacts/openapi.json` ve `artifacts/realtime-openapi.json` üretir.

Tarayıcı `fetch(url,{credentials:'include',headers:{'x-tracking-session':token,'Last-Event-ID':cursor},signal})` + streaming reader kullanmalı. Native EventSource özel token header'ı gönderemediği için doğrudan uygun değildir. Proxy aynı-site cookie/Origin ve streaming header'larını korumalı; SSE buffering/cache kapatılmalıdır. API ve SSE aynı host altında farklı upstream'e route edilebilir; bu repository'de frontend/proxy değişikliği yapılmadı.

SSE `location` olayında `id` ve `{eventId,location}`, `reset` olayında güncel location veya null, `closed` olayında yalnız `{reason:"access_unavailable"}` gönderir. Heartbeat comment'leri vardır. Her poll cookie auth + finalized binding yeniden doğrulanır. Eski/trimmed veya gelecekteki cursor latest'e reset olur; TTL dolmuş GPS replay edilmez. İstemci reset'te eski konumu temizlemeli, location olaylarının id'sini saklamalıdır. Network kopması sonrası exponential backoff/jitter ile cursor'dan bağlanın; 401'de giriş, 403'te erişim/expiry kontrolü; 429'da bekleme. Her stream sınırlı ömürlüdür, normal kapanışta da yeniden bağlanılır. Aynı tracking token için Redis lease ile tek eşzamanlı bağlantı, process başına bağlantı limiti vardır. Çoklu sekme/mobil cihaz davranışını frontend koordine etmelidir.

Readable backpressure ve her poll'da revalidation uygulanır. İstemci disconnect, stream deadline veya Nest shutdown aktif stream'leri kapatır ve lease'i bırakır; process crash durumunda lease TTL ile düşer. Redis kesintisinde açık stream hassas hata aktarmadan kapanır. Kontrol aralığındaki ve zaten istemciye gönderilmiş verinin geri alınamayacağı dikkate alınmalıdır.

## Route, evidence ve notification adapter'ları

`RouteProvider` koordinatları kullanıcı request'inden değil erişimi doğrulanmış şifreli private kayıttan alır. Dev adapter `straight-line-dev`: küresel kuş uçuşu mesafe ve sabit 5 m/s süresi; yol navigasyonu, trafik veya gerçek teslim ETA'sı değildir. Şifreli Redis cache süresi dolunca eski tahmin fallback olarak sunulmaz; timeout/geçersiz/stale provider sonucu 503. Harici sağlayıcıya koordinat gönderilmez.

Evidence JSON: `{contentType:"text/plain",text,gps?}` veya `{contentType:"image/png"|"image/jpeg",contentBase64,gps?}`. GPS `{lat,lng,capturedAt}`. UTF-8 metin en fazla 8192 byte, decoded fotoğraf en fazla 24576 byte; canonical base64 ve PNG/JPEG başlangıç imzası doğrulanır. Fotoğraf decode/antivirus/EXIF temizleme uygulanmadı; production upload kabulü sayılmaz. Hash orijinal metin/fotoğraf byte'larının SHA-256'sıdır; hash doğruluk/delil güvenilirliği kanıtı değildir. Teslimat kodu veya on-chain dispute submission bu akışta yoktur.

Evidence metadata ve encrypted storage job tek PostgreSQL transaction'ındadır. HMAC scoped idempotency, aynı key/body için aynı evidenceId, farklı body için 409 üretir; retry güncel pending/ready/failed durumunu döndürebilir. Key kayıtları otomatik silinmez. İçerik AES-256-GCM, evidenceId+binding AAD; job payload ayrıca şifrelidir. `EvidenceStorage` mevcut adapter'ı `backend/.local/evidence/` altında immutable/atomic encrypted JSON saklar; public/static URL yoktur. Retry aynı object key/ciphertext ile çalışır, farklı içerik üzerine yazılmaz. Symlink/path kontrolleri vardır; Windows ACL ve dosya sistemi güvenliği ayrıca işletim sorumluluğudur. API ile worker yerel diski paylaşmalıdır; çok-host production storage değildir.

`NotificationProvider` mevcut adapter'ı kalıcı PostgreSQL in-app inbox'tır; dışarı push/e-posta/SMS göndermez. Worker finalized projection'ın güncel lifecycle snapshot'ını ve evidence-ready geçişini üretir; tüm ara event'lerin eksiksiz bildirim günlüğü değildir. Template'ler `delivery_state` (`{state}`) ve `evidence_ready` (`{evidenceId}`). Adres/GPS/evidence metni içermez. Inbox yalnız ilgili wallet + güncel trusted binding'e görünür. Filtrelenen sayfa boş ama nextCursor dolu olabilir. Stale indexer'da eski yetkiyle bildirim sunulmaz.

## Yerel çalıştırma ve hata kurtarma

Önce mevcut Faz 1–5 env ayarları, PostgreSQL/Redis ve `npm run db:migrate`; indexer ve quote-link worker ile trusted private link oluşmuş olmalı. Bu teslim yalnız izole test fixture'larını kullandı, gerçek zincir işlemi göndermedi. Migration additive; down otomatik veri silmeyi reddeder.

`.env.example` değerlerini yerel ortam için ayarlayın: `OPERATIONS_ENABLED=true`, `INDEXER_ENABLED=true`, `PROVIDER_WORKER_ENABLED=true`. Mevcut API'yi `npm start`, ayrı process'leri `npm run realtime`, `npm run provider:worker -- watch` ile çalıştırın. Tek batch `npm run provider:worker -- once`; failed job retry `npm run provider:worker -- retry <jobUUID>`. CLI yalnız yerel/test PostgreSQL hedefini kabul eder ve yalnız configured deployment stream'indeki işleri işler/yeniden kuyruğa alır. HTTP job retry endpoint'i yoktur.

| Dev/test ayarı | Varsayılan |
| --- | --- |
| TRACKING_SESSION_TTL_SECONDS / TRACKING_LOCATION_TTL_SECONDS / TRACKING_EVENT_TTL_SECONDS | 300 / 60 / 180 |
| TRACKING_POLL_MS / TRACKING_STREAM_SECONDS / TRACKING_MAX_CONNECTIONS | 1000 / 60 / 100 |
| REALTIME_PORT / ROUTE_CACHE_TTL_SECONDS | 3002 / 30 |
| PROVIDER_WORKER_POLL_MS / PROVIDER_TIMEOUT_MS / PROVIDER_MAX_ATTEMPTS | 2000 / 1000 / 3 |

Bu sayılar production retention/SLA kararı değildir. Worker batch en fazla 20 iş, SQL SKIP LOCKED, bounded exponential retry kullanır. Provider adapter AbortSignal'e uymalıdır; timeout sonrası dış sistemde tamamlanan side-effect mümkündür. Yeni adapter `send` idempotencyKey/job UUID ve immutable storage key ile tekrar çalıştırılabilir olmalıdır; exactly-once dış teslim garantisi yoktur. Kalıcı hata `failed`, fixed `PROVIDER_UNAVAILABLE`; credential/raw hata saklanmaz. `provider_jobs` status/attempts/next_attempt_at ve `evidence_packages.status` ile lokal teşhis edin. Önce provider/indexer erişimini düzeltin, sonra tek job UUID ile retry yapın; tüm kuyruğu keyfi resetlemeyin.

Evidence object, tamamlanmış job ve inbox için otomatik retention/silme eklenmedi. DB + encrypted object + master key birlikte yedeklenmeli; key kaybında veri kurtarılamaz. Crash sonrası orphan object/temporary dosya temizliği ve disk kota politikası production önkoşuludur; bu teslim veri silmez.

## Devam notu

1. Güvenlik/operasyon: S3-compatible private bucket, gerçek RouteProvider/WebPush adapter'ları, abort/idempotency contract testleri, upload tarama/kota, TTL/retention ve key/object restore onaylarını tamamlamak. Hesap/ürün kararları gelmeden production kapalı kalır.
2. Ürün/API: Faz 7 support/dispute yetki matrisi, audit ve metrics/traces API'lerini ayrıntılandırmak; frontend cookie/SSE reconnect akışını gerçek tarayıcıda smoke test etmek.

Teknik kaynaklar: [Nest SSE yaşam döngüsü](https://docs.nestjs.com/techniques/server-sent-events), [Redis XADD ve bounded stream](https://redis.io/docs/latest/commands/xadd/). SSE uygulaması header öncesi yetki kontrolü ve Fastify shutdown/backpressure için Node Readable kullanır; ek npm paketi eklenmedi.
