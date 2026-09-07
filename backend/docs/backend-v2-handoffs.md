# V2 Backend Ekip Bağımlılıkları

## Frontend

### Faz 2 sözleşmesi — 2026-09-07

Tüm isteklerde `credentials: 'include'`; mutasyonlarda tarayıcı `Origin` göndermeli ve origin backend CORS listesinde bulunmalı. SameSite=Lax nedeniyle frontend/API aynı site içinde olmalı; local geliştirmede iki tarafta da aynı hostname'i kullanın (`localhost` ile `127.0.0.1` karıştırmayın). SIWE_DOMAIN, frontend host:port değeridir; SIWE_URI, frontend giriş origin/URI değeridir.

1. `POST /v1/auth/siwe/nonce` JSON `{address}` → 200 `{address, nonce, message, expiresAt}` ve HttpOnly challenge cookie. Dönen message metnini değiştirmeden `personal_sign` ile imzalayın. Yeni nonce aynı tarayıcının önceki challenge cookie'sini değiştirir; aynı anda bir giriş akışı yürütün.
2. `POST /v1/auth/siwe/verify` JSON `{message, signature}` → 200 `{user, session:{expiresAt}, csrfToken}` ve session cookie. Challenge cookie bu istekte zorunlu; başarıda temizlenir. Replay, yanlış cüzdan/context/expiry 401; tekrar nonce alın.
3. `GET /v1/auth/session` → 200 aynı user/session/csrfToken; 401 ise yeniden giriş. Token'ı bellekte tutun, localStorage'a yazmayın. Token/session değerlerini analitik veya hata raporlarına eklemeyin.
4. `GET /v1/users/me` → yalnız oturum sahibinin profili. `PATCH /v1/users/me` → 200 güncel profil; `x-csrf-token` gerekir. Alanlar displayName (1–80), email, E.164 phone, role (`customer/courier`), courierProfile (`{vehicleType: on_foot|bicycle|motorcycle|car}`). displayName/email/phone/courierProfile için null temizler. Email/phone doğrulanmamıştır; role tercih olup courier onayı/operasyon yetkisi değildir. Bilinmeyen alanlar 400.
5. `DELETE /v1/auth/session` mevcut oturumu; `DELETE /v1/auth/sessions` kullanıcının tüm aktif oturumlarını iptal eder. İkisi de `x-csrf-token` gerektirir; başarı 204 ve cookie temizliği. Eksik session 401; eksik/yanlış CSRF veya Origin 403. Redis/DB kesintisi 503. Rate limit 429 + Retry-After saniyesi.

Production/HTTPS cookie: `__Host-monosfer_sid`, HttpOnly, Secure, SameSite=Lax, Path=/, Domain yok. HTTP development/test cookie: `monosfer_sid_dev`, Secure olmadan; JS cookie'yi okumaz. Challenge cookie aynı politikada `__Host-monosfer_challenge` veya `monosfer_challenge_dev`.

Gerekli frontend teslimi: wallet ile gerçek tarayıcı login/refresh/logout/revoke-all; credentials, CORS preflight, CSRF ve çoklu sekme akışını smoke test edin. Backend testleri Fastify inject kullanır, gerçek tarayıcı cookie kabulü bu teslimde test edilmedi. ERC-1271 adapter yerel RPC fixture ile test edilir; canlı testnet contract-wallet smoke ayrıca gerekir. ERC-6492 desteklenmez; contract-wallet yetki değişikliği için zincir event tabanlı oturum iptali ileriki indexer fazına bağlıdır.

OpenAPI export `/v1` auth/user request ve response şemalarını, cookie auth, CSRF/Origin başlıklarını ve standart hataları içerir. Faz 4 indexing-pending sözleşmesi henüz yoktur.

- Yeni sözleşme `/v1`; eski `/api` endpoint'leri yeni runtime'da bulunmaz. Faz 1 yalnız health endpoint'leri sağlar.
- OpenAPI `/v1/openapi.json`; `npm run openapi:export` çıktısı `artifacts/openapi.json`. Tip üretimi frontend ekibinin sorumluluğudur.
- Hata: `{error:{code,message,requestId}}`; `x-request-id` destek taleplerinde korelasyon için kullanılabilir.
- Faz 2 SIWE/session sözleşmesi yukarıda teslim edildi. Faz 4'te confirmed/indexing pending ayrımı gelecek.
- Production CORS origin listesi ve BFF/proxy yerleşimi gerekli. Private/auth/financial cevaplar service-worker cache'ine alınmamalı.

## Contracts

- ABI/deployment kaynağı mevcut `contracts/exports/`; backend kopya adres üretmeyecek.
- V2'ye birleşmiş commit esas alınacak. 2026-09-07 kontrolünde P2.1 pickup proof `98d7e64` (PR #4) ile V2'ye alındı; Faz 4 entegrasyonu güncel imzalı pickup ABI'sini esas almalı.
- Quote policy/price audit alanları off-chain kayıtta tutulacak; EIP-712 mesajına ABI dışı alan eklenmeyecek.

## Altyapı/DevOps

- Faz 2: `.env.example` yeni zorunlu SIWE/session/rate alanları içerir. SESSION_COOKIE_SECRET boş bırakılmıştır; ortam başına kriptografik rastgele üretin (en az 32 karakter). Production SIWE_URI ve RPC HTTPS zorunlu. SIWE_DOMAIN/URI/CORS birlikte ayarlanmalı; proxy cookie ve Origin başlıklarını korumalı.
- Session TTL, ortak IP rate bütçesi (NAT etkisi), user/contact ve revoked session retention politikası ürün/operasyon onayı bekler. Bu teslim otomatik veri silme/retention worker çalıştırmaz. PostgreSQL yetki/revocation kaynağı, Redis ek zorunlu session store'dur; Redis veri kaybı yeniden giriş gerektirir.
- `1788825600000-auth-users.sql` up migration additive; down otomatik veri silmez. Geri alma için ayrı onaylı veri koruma planı gerekir. Api runtime şemayı kendi başına değiştirmez.
- Secret rotasyonu mevcut CSRF token'larını geçersiz kılar; session endpoint yeni token verir. Tüm session'ları iptal etmekle eşdeğer değildir. RPC arızası contract-wallet girişini 401 ile güvenli reddeder; EOA girişinde RPC kullanılmaz. RPC timeout ve retry sınırlıdır.

- Production PostgreSQL, Redis, TLS, secret yönetimi, resource limits ve proxy ağı sağlanmalı.
- Backend Compose yalnız yerel geliştirme içindir; örnek parola production'da kullanılamaz.
- Node 24 process: build ardından start; migration ayrı release job. Eski deploy MongoDB environment'ı tek başına yeterli değildir.
- CI için backend npm ci, typecheck, test, test:legacy, integration ve audit adımları gerekli. Bu dosyada bildirilir; `.github` değiştirilmez.
- Readiness 503 traffic admission'ı durdurur; liveness 200 process'in çalıştığını gösterir. Redis reconnect bütçesi tüketilirse servis yeniden başlatılmalı.
- Indexer/provider seçimi, quote signer/KMS, Route/ETA ve Web Push hesapları sonraki fazlar için gerekli.

## Veri/ürün kararları

- MongoDB salt okunur erişim ve veri envanteri Faz 3 öncesi gerekli; mevcut veri korunacak.
- Exact adres/evidence erişim matrisi, retention ve silme politikası ürün tarafından netleştirilmeli.
- Risk fiyat/policy formülü, referral qualification ve reward kuralları netleştirilmeli.
- Mainnet öncesi RTO/RPO ve restore drill onayı gerekli; belirlenmeden Mainnet-ready etiketi kullanılmaz.
