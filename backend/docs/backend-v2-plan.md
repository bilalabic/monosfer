# Monosfer V2 Backend — Fazlı Uygulama Planı

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

1. Faz 2 SIWE: wallet sahipliğini doğrulayıp güvenli session temeli kurmak.
2. Faz 3 private veri/aktarım: mevcut veriyi korurken PostgreSQL veri sahipliği sınırını oluşturmak.
