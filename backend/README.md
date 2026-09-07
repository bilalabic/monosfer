# Monosfer V2 Backend

Node.js 24 + NestJS 11/Fastify + TypeScript. Faz 2 API: health, SIWE cookie oturumu, minimal profil ve OpenAPI.

Faz 3: private veri şifreleme/erişim sınırı ve MongoDB salt okunur inventory/dry-run/import araçları eklendi. Runtime artık `PRIVATE_DATA_MASTER_KEY_B64` ve `PRIVATE_DATA_KEY_ID` gerektirir. Yeni delivery endpoint'i yoktur; confirmed projection bağlantısı Faz 4'e aittir. Yerel Mongo testi, import komutları ve key/resume kuralları: [private-data-operations.md](docs/private-data-operations.md).

## Yerel çalışma

Backend dizininde:

```sh
npm ci
docker compose up -d --wait
# .env.example içeriğini yerel .env dosyanıza aktarın.
# SESSION_COOKIE_SECRET için rastgele değer üretip .env içine ekleyin:
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
npm run db:migrate
npm run dev
```

`.env` yerine process environment da kullanılabilir. Eksik/yanlış config başlangıcı reddeder.
Compose PostgreSQL'i `127.0.0.1:55432`, Redis'i `127.0.0.1:56379` üzerinden sunar. Örnek parolalar yalnız localhost geliştirme içindir.
PostgreSQL named volume kalıcıdır. MongoDB erişimi veya otomatik aktarım yoktur.

Production: `npm run build`, ayrı migration job, ardından `npm start`. Migrasyon komutu devDependencies içeren build/release ortamında çalıştırılmalıdır; API startup şemayı değiştirmez.
`TRUST_PROXY=false` varsayılandır; yalnız güvenilen reverse proxy arkasında ve doğrudan erişim sınırlandırılmışsa açın.

## API

| Endpoint | Davranış |
| --- | --- |
| GET /v1/health/live | 200 `{status:"ok"}` |
| GET /v1/health/ready | PostgreSQL/Redis sağlıklıysa 200; değilse standart 503 |
| GET /v1/openapi.json | OpenAPI JSON |
| GET /v1/docs | Yalnız development Swagger UI |
| POST /v1/auth/siwe/nonce | 200 SIWE mesajı + browser challenge cookie |
| POST /v1/auth/siwe/verify | 200 user/session/csrfToken + HttpOnly session cookie |
| GET /v1/auth/session | 200 oturum veya 401 |
| DELETE /v1/auth/session | CSRF ile mevcut oturumu kapatır; 204 |
| DELETE /v1/auth/sessions | CSRF ile kendi tüm oturumlarını iptal eder; 204 |
| GET/PATCH /v1/users/me | Kendi minimal profili; PATCH için CSRF gerekir |

Frontend akışı ve cookie/Origin gereksinimleri [handoffs](docs/backend-v2-handoffs.md) içinde. `.env.example` auth ayarları zorunludur; development HTTP cookie `monosfer_sid_dev`, production/HTTPS cookie `__Host-monosfer_sid` olarak üretilir. Production yalnız HTTPS SIWE URI/RPC kabul eder.

Hatalar: `{error:{code,message,requestId}}`. Her request için sunucu UUID üretir; istemci request ID'sine güvenmez.
Body, URL/query ve credential loglanmaz; request/status korelasyonu tutulur. Yanıtlarda `Cache-Control: no-store` bulunur.
Redis bağlantısı sınırlı retry sonrasında başarısız kalırsa process yeniden başlatılmalıdır. Liveness bağımlılıkları ölçmez.

## Doğrulama

```sh
npm run typecheck
npm test
npm run test:integration
npm run test:legacy
npm run openapi:export
npm audit
```

Integration suite localhost Compose servisine ihtiyaç duyar, yoksa fail eder. `DATABASE_URL` verilmişse yerel `monosfer_v2` veya `monosfer_v2_test` veritabanı kullanın; suite migration uygular, yalnız kendi rastgele test cüzdanlarının fixture kayıtlarını temizler. Test dosyaları migration kilidi için sırayla çalışır. Unit testler dış servislere bağlanmaz; ERC-1271 testi yerel HTTP RPC fixture kullanır.
OpenAPI export offline çalışır ve yalnız yok sayılan `artifacts/` dizinine yazar.
Legacy testler ayrı tutulur; eski Express uygulaması V2 runtime'a dahil değildir.

Windows üzerinde shutdown testleri Nest'in signal handler dispatch'ini çalıştırır. Gerçek POSIX sinyalleri için aynı `tests/integration/shutdown.test.mjs` dosyası Linux Node 24 ortamında çalıştırılır. Windows bind mount soğuk modül yüklemesi yavaş olduğundan bootstrap test bütçesi 90 saniyedir; uygulama hazır olduktan sonraki kapanış sınırı 5 saniyedir.

Plan: [backend-v2-plan.md](docs/backend-v2-plan.md). İlerleme: [backend-v2-progress.md](docs/backend-v2-progress.md). Ekip ihtiyaçları: [backend-v2-handoffs.md](docs/backend-v2-handoffs.md).
