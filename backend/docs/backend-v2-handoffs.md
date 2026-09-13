# V2 Backend Ekip Bağımlılıkları

## Contract Sync — 2026-09-13

### Frontend ekibine iletilecek işler

Bu liste backend'in beklediği entegrasyonları belirtir; frontend kodu bu çalışmada incelenip tamamlandı olarak işaretlenmedi.

| Kimlik | Eksik entegrasyon / beklenen davranış | Kabul koşulu |
| --- | --- | --- |
| FE-CS-1 | V2 `/v1` API, SIWE cookie oturumu, `credentials: include`, mutating isteklerde Origin/CSRF ve gerekli yerlerde Idempotency-Key kullanımı. | Wallet değişiminde eski oturum/kullanıcı verisi temizlenir; 401 tekrar girişe, 403 yetki hatasına yönlendirilir. `/api` fallback yapılmaz. |
| FE-CS-2 | Customer pickup/return endpoint'inden typed-data alır, teslimat/kurye/aksiyon/süreyi gösterip wallet ile imzalar; seçilmiş courier ilgili contract çağrısını yapar. | Yanlış wallet/chain, imza reddi, expiry, kullanılmış nonce ve state değişimi senaryoları browser kabul testinden geçer. |
| FE-CS-3 | Customer imzasını courier cihazına iletme kanalı kararlaştırılmalı. Mevcut backend acceptance üretir; imzalı acceptance relay/inbox endpoint'i içermez. | İki farklı cihazda aktarım ve yeniden deneme akışı belirlenir. Relay API isteniyorsa kapsam ayrıca backend'e bildirilir; imza URL/analytics/log'a yazılmaz. |
| FE-CS-4 | Atanmış courier PoD için `{proofType:"otp",code}` gönderir; dönen attestation + backend signature ile `submitDeliveryProof` çağırır. | OTP yalnız form/request body'de kullanılır; kontrata raw kod taşınmaz. 429 durumunda otomatik yeni key ile sınırsız retry yapılmaz. QR/recipient-signature yolu henüz sunulmaz. |
| FE-CS-5 | Receipt ile backend finalized projection senkronizasyonu ayrılır. `indexing_pending`, stale/error, `Disputed`, `Resolved`, yeni ETA alanları UI'da işlenir. | Tx receipt alınınca private link oluşmuş kabul edilmez; ready projection/link beklenir. Stale veriyle proof butonu başarılı işlem vaadi vermez. |
| FE-CS-6 | `source=backend_delivery_projection` sayaçları on-chain puan/badge olarak etiketlenmez; `export_missing`, `rebuild_pending`, `pending_policy` durumları gösterilir. | Kullanıcıya hak edilmiş/ödenebilir reward veya on-chain reputation iddiası yapılmaz. |
| FE-CS-7 | Support ekranı yeni dispute özeti/committee alarmını gösterebilir; private/evidence content mevcut case/admin politikasından geçer. Backend support case ile on-chain dispute farklı kaynaklardır. | Local support case açılması zincirde dispute açmaz. Evidence upload otomatik on-chain commitment submission yapmaz. |

Frontend teslim kaynağı: [proof sözleşmesi](backend-v2-contract-sync.md) ve `npm run openapi:export` ile üretilen `backend/artifacts/openapi.json`. Artifact git-ignored olduğu için checkout sonrası yeniden üretilebilir. Gerçek browser/courier transaction E2E bu backend tesliminde çalıştırılmadı.

### Contract ekibine iletilecek işler

| Kimlik | Eksik / gerekli teslim | Backend etkisi ve kabul koşulu |
| --- | --- | --- |
| CT-CS-1 — blocker | `ReputationRegistry`, `BadgeSBT`, `Referral`, `RewardDistributorV1` için `contracts/tools/build-exports.mjs` EXPORTED listesi ve generated ABIS/ContractName/getAddress yüzeyi tamamlanmalı. | Dört isim consumer import/type kontrolünden geçmeli; ABI ve deployment adresi/bloku aynı release'e ait olmalı. Şu an backend on-chain projection'ı `export_missing` bildirir. |
| CT-CS-2 | Bu dört kontratın event/read sözleşmesi, rol/authorization gereksinimi, rating/confidence/badge ve referral/reward lifecycle anlamları consumer dokümanına eklenmeli. | Backend rebuild tasarımı için event kimliği, başlangıç bloğu, tekrar hesaplama kuralları ve örnek fixture sağlanır. Export teslimi tek başına backend projection'ını otomatik etkinleştirmez; ayrıca backend işi gerekir. |
| CT-CS-3 | Staging release için DeliveryHub/DisputeCourt/ProtocolConfig adresleri, deployment blokları, chainId ve signer konfigürasyonu birlikte doğrulanmalı. | Backend generated bundle ile aynı deployment kullanır. Adres/ABI değişikliği yeni fingerprint ve reindex gerektirir; eski stream fingerprint'i elle güncellenmez. |
| CT-CS-4 | PoD signer provisioning/rotation sahipliği altyapı ekibiyle netleşmeli; risk signer'dan ayrı anahtar/adres kullanılmalı. | `podAttestationSigner` backend signer'ıyla eşleşir, TTL `podAttestationValidity` sınırındadır. Rotasyon sonrası eski imzaların geçersizleştiği staging kabulü yapılır. Secret/private key doküman veya chat üzerinden paylaşılmaz. |
| CT-CS-5 | Proof fonksiyonları için şu an tespit edilmiş ek kontrat düzeltmesi yok; customer acceptance ile servis PoD yolu ayrımı korunmalı. | Canlı read-only smoke üç proof digest'ini gerçek hash fonksiyonlarıyla eşleştirdi. Transaction/state-transition E2E ve imzalı acceptance'ın iki cihazlı akışı ayrı kabul testidir. |

Contract dosyalarında değişiklik yapılmadı. CT-CS-1/2 teslim edilene kadar gerçek on-chain reputation/referral/reward backend entegrasyonu tamamlandı sayılmamalı.

### Ortak kararlar ve sonraki sıra

1. Teknik güvenlik/operasyon: CT-CS-1 export teslimi; ardından staging migration + yeni stream backfill/reconcile ve ayrı PoD signer rotation kabulü. Production KMS/retention/OTP kilit açma kararları ayrıca gereklidir.
2. Ürün/API: FE-CS-2/3/4 iki cihazlı pickup → delivery proof → return senaryoları. Customer imzasını taşıma ve recipient kodunu güvenli ulaştırma kanalı seçildikten sonra eksik backend relay/kod yönetimi ihtiyacı netleştirilir.

- **Contract blocker:** `ReputationRegistry`, `BadgeSBT`, `Referral`, `RewardDistributorV1` deployment kaydında var fakat `contracts/exports` ABIS / ContractName / getAddress tüketici yüzeyi eksik. Contract ekibi export generator ve çıktısını teslim etmeli. Backend mevcut delivery sayaçlarını on-chain score/confidence diye sunmaz: `source=backend_delivery_projection`, `onChainReputation.status=export_missing`. `pending_policy` reward/referral devam eder.
- **Frontend:** [proof API sözleşmesi](backend-v2-contract-sync.md). Customer pickup/return acceptance typed-data'sını wallet ile imzalar; kurye `confirmPickup` / `confirmReturn` transaction'ını gönderir. PoD endpoint'ini atanan kurye çağırır; backend imzası ve attestation `submitDeliveryProof` içindir. İmzalar ve kodlar analytics/log/URL içine konmaz. 409 expiry/state/idempotency çakışması; 503 trusted snapshot/signer/RPC yokluğu; 429 OTP deneme sınırı. Yeniden imza alınmadan önce lifecycle ve expiry gösterilmeli.
- **Staging/altyapı:** timestamp ve DisputeCourt ABI/address/block bilgisi fingerprint'i değiştirir. Eski stream üzerinde fingerprint'i elle değiştirerek devam edilmez; [reindex prosedürü](indexer-operations.md) uygulanır. Production signer secret/KMS, ayrı risk/PoD signer rotasyonu ve RPC kapasitesi ekibin kabulünü gerektirir. Bu teslimde staging/production migrate/deploy yapılmadı.
- **OTP/ürün:** ilk yol yalnız private payload `dropoff.deliveryCode` eşitliğini doğrular; QR/recipient wallet direct-sign yok. Saatlik 5 yeni deneme delivery bazında backend güvenlik sınırıdır. Üretimde kod oluşturma/teslim kanalı, yeniden üretim ve kilit açma politikası, recipient doğrulaması ve operasyon SLA'sı belirlenmeli. Runtime PoD anahtarı yoksa API 503 verir.
- **Ops:** `monosfer_committee_resolutions` canonical projection gauge'udur, reorg'da azalabilir; ops status/indexer readiness ile birlikte alarm kuralı kurulmalı. Reputation projection rebuild yeni state'leri kapsar ama gerçek rating/reward event'leri export gelene kadar tüketilmez.

## Faz 7 — Support/operasyon sözleşmesi / 2026-09-11

- Frontend/support aracı: [Faz 7 API ve örnekler](backend-v2-release.md), `artifacts/openapi.json`. Support/admin yetkisi profil role alanından gelmez; SIWE session + env allowlist gerekir. Case create `{id,assignee?,note?}`, Idempotency-Key, Origin/CSRF; private/evidence content için aktif atama gerekir. Case notes şifreli yazılır, genel case list/detail içinde döndürülmez. Legacy dispute evidence bu yüzeye aktarılmaz. Browser/mobile kabulü ayrıca yapılmalı.
- Ürün/güvenlik: env allowlist geçici privileged kimlik yönetimi; kalıcı RBAC/IdP, atama yetki matrisi, destek notlarını okuma/paylaşma kapsamı ve SLA kararı bekler. Bu fazda allowlisted support case açıp allowlisted kişiye atayabilir; admin private erişiminde case zorunluluğunu aşabilir. Her gerçek privileged işlem auditlenir. Retention, yasal saklama/silme ve bağımsız değiştirilemez audit hedefi belirlenmeli.
- Reputation/referral/reward: sayaçlar finalized projection'a bağlı, skor/ödül hesaplama veya ödeme yok. `pending_policy` referral qualification ve reward economics kararı beklediğini gösterir. Projection kaynak bloğu ilerlediğinde `rebuild_pending` görülebilir; production worker/scheduler ve SLA backend dışı operasyon teslimidir.
- Altyapı: ayrı OPS_METRICS_TOKEN üretimi/rotation, TLS/private ağ, metrics scrape ve alarm, trace retention/sampling, runtime DB rolü ile migration owner ayrımı gerekir. DB owner/superuser trigger'ları değiştirebilir; append-only trigger bağımsız WORM depolama iddiası değildir. Trace body, URL, header, cookie veya credential saklamaz. Varsayılan sampling 0.
- DR: local fixture PostgreSQL dump/restore, Redis TTL ve encrypted object/key kontrolleri production backup/PITR/replica failover veya KMS disaster-recovery kanıtı değildir. RTO/RPO, off-host object backup, anahtar escrow/rotation ve gerçek restore prosedürü kararlaştırılmalı. Redis gerçek session'larının geri yüklenmesi bu fazda yapılmaz.
- Provider: Route/S3/WebPush hesapları/KMS hâlâ bekler. Dev/test adapter contract testleri, timeout/retry/dead-letter testleri mevcut; gerçek provider/region/multi-host davranışı için production kabulü ayrıca gerekir. Mevcut `OPERATIONS_ENABLED` production fail-closed kuralı sürer.
- Contract: ABI/deployment bundle mevcut V2 export'larından okunur. Testnet smoke zincire transaction göndermez, signer gerektirmez. Canlı smoke başarısız veya deployment uyuşmazsa contract/RPC ekibine test aşaması ve sabit hata kodu ile iletilir; backend adres uydurmaz.

Sonraki iki iş: (1) güvenlik/operasyon için production provider/KMS, runtime DB izinleri ve gerçek DR tatbikatı; (2) ürün/API için support ekranı, referral/reward politikası ve tarayıcı SIWE/CSRF/support kabul senaryoları.

## Faz 6 yerel/test teslimi — 2026-09-10

- Frontend: [tracking/provider sözleşmesi](backend-v2-operations.md) ve iki OpenAPI export'u hazır. SIWE cookie + Origin/CSRF, tracking için bellekte/header'da kısa token, evidence için Idempotency-Key kullanın. Realtime ayrı Node process; fetch streaming + Last-Event-ID, reset/expiry/closed ve backoff gerekir. Native EventSource'a token URL'si eklemeyin. Gerçek browser/mobil arka plan/reconnect smoke bu teslimde yapılmadı; GPS izni ve çoklu sekme davranışı frontend sorumluluğunda.
- Ürün: tracking/route/evidence-create yalnız ReadyForPickup/InTransit; ReturnRequired tracking ayrı erişim onayı bekler. Yeni evidence yalnız yükleyene görünür; legacy dispute veya support/admin yetkisi açılmaz. GPS consent, retention/silme, upload boyutu/antivirus/EXIF, katılımcılar arası delil paylaşımı ve push tercihleri kararlaştırılmalı. Dev TTL ve kuş uçuşu ETA production politikasına eşit değildir.
- Provider/altyapı: gerçek Route/ETA hesabı, S3-compatible private bucket/region/credentials/KMS ve WebPush VAPID/abonelik/izin tercihleri bekleniyor. Bu teslimde adapter arayüzleri + yerel encrypted storage + in-app notification inbox vardır; harici provider entegrasyonu, push subscription API ve production storage hazır değildir. `OPERATIONS_ENABLED` varsayılan false; production true startup'ı reddeder.
- Proxy/DevOps: realtime için aynı-site cookie, TLS, CORS ve buffering kapalı streaming upstream gerekir; API ve worker aynı yerel evidence diski/anahtarını kullanır. Process/distributed bağlantı sınırları, ortak auth IP rate bütçesinin GPS publish yüküne göre ayarı, sticky olmayan reconnect, object/disk kota, dead-letter alarmı, SQL+object+key restore ve retention prosedürü gerekli. Backend dışı proxy/deploy/CI dosyaları değiştirilmedi.
- Kontrat: Faz 4/5 trusted finalized private-link tüketildi; backend chain state/contract/ABI yazmadı, işlem göndermedi. Native evidence hash off-chain içerik bütünlüğüdür, zincire dispute/evidence işlemi gönderildiği anlamına gelmez. Bildirim worker'ı current projection snapshot'ı bildirir, her ara zincir event'inin eksiksiz push kaydı değildir.


## Faz 5 teslimi — 2026-09-08

- Frontend: üç yeni `/v1/quotes` endpoint'i OpenAPI ve [quote sözleşmesinde](backend-v2-quotes.md) tanımlandı. SIWE cookie + Origin/CSRF + Idempotency-Key kullanın. Aynı ağ retry'ında aynı key/body; ayrı eylem/refresh için yeni key. Response quote/signature ile createDelivery çağrısını wallet yapar. Ardından indexer pending/confirmed akışını izleyin; privateRecordId veya tx hash tek başına confirmed değildir. Signature/private alanlar browser log/analytics/cache'e gitmemeli. Gas/fee gösterimi frontend sorumluluğundadır.
- Kontrat: mevcut V2 export Hub + ProtocolConfig ABI/adresleri kullanıldı. Her issuance'da finalized riskQuoteSigner/riskQuoteValidity/coverage bandı ve hashQuote okunur. Production imzacı değişikliği mevcut quote'ları geçersiz kılabilir; rotation/quote retry ürün davranışı belirlenmeli. Backend kontrat dosyalarını değiştirmedi.
- Ürün/risk: deterministic adapter yalnız dev/test tier 1 minimum contract bandıdır. Gerçek risk sınıflandırması, fiyat feed/provider, freshness ve retention süreleri belirlenmedi. declaredValue contract birimindedir, token/fiat dönüşümü yoktur. Production quote API ve worker fail-closed kalır.
- Altyapı/güvenlik: signer KMS/HSM, provider hesabı, key rotation ve ciphertext/idempotency key lifecycle kararı gerekir. Retention/cleanup, worker alert/backlog hedefi ve reorg sonrası completed outbox recovery henüz production politikasına bağlanmadı. Quote worker ayrı process; varsayılan false, yerel once/watch CLI. Root/CI/deploy değişmedi.
- Private link: Faz 4'te bekleyen yazıcı tamamlandı; yalnız native server issuance + trusted finalized quoteDigest/customer/projection eşleşmesi bağ kurar. Legacy imported kayıtlar otomatik bağlanmaz. ReturnRequired ve support/admin erişim politikaları hâlâ ayrı karardır.

## Faz 4 teslimi — 2026-09-07

- Frontend: `/v1/indexer/status`, `/v1/deliveries`, `/v1/deliveries/:id` ve bids alt kaynağı hazır. `indexing` metadata zorunlu değerlendirilmelidir; missing delivery 202 iken yeniden sorgulanır, ready iken 404 gerçek yokluk anlamına gelir. Lifecycle adları gerçek DeliveryHub enum'udur; legacy Accepted/Delivered kullanılmaz. UI write işlemleri kontrata gider, backend projection'ını değiştiren endpoint yoktur. [Sözleşme/örnekler](indexer-operations.md) ve OpenAPI kullanın.
- Kontrat: backend build doğrudan mevcut exports paketini tüketir ve fingerprint üretir. Manifest başlangıç bloğu ve deployed code/ABI uyumluluğu ekip sorumluluğunda; backend yalnız chain ID ve code varlığı kontrolü yapar. Export güncellemesi mevcut cursor'ı durdurur; migration/backfill değerlendirilmelidir. Bu teslimde kontrat/root dosyası değiştirilmedi.
- Altyapı: ayrı worker process, archive RPC ve gözlenen finalized/indexer lag için izleme gerekir. Default worker kapalıdır. `/health/ready` PostgreSQL/Redis sağlığını ölçer, indexer için ayrı status kullanın. Production worker/deploy/CI ve canlı Testnet smoke bu teslimde yapılmadı.
- Ürün/Faz 5: private record ID'yi imzalı quote issuance kaydına bağlamak gerekir. Link okuyucusu hazır, uygulama yazıcısı henüz yoktur. Imported legacy kayıtlar otomatik olarak confirmed sayılmaz. Courier erişimi ReadyForPickup/InTransit ile sınırlıdır; ReturnRequired erişimi ürün/güvenlik kararı bekler.
- Operasyon: deep-reorg/fingerprint uyuşmazlığı veya bozuk inbox otomatik geniş reset yapmaz. Projection için replay + reconcile vardır; veri boyutuna göre bakım süresi ve inbox backfill prosedürü ayrıca ölçülmelidir. Gözlenen RPC'nin tutarlılığı test edildi; bağımsız provider/chain proof doğrulaması eklenmedi.

## Faz 3 teslimi — 2026-09-07

- Frontend: yeni endpoint veya zorunlu akış yok. `/v1` SIWE/profil sözleşmesi sürer. Address/evidence/GPS için yeni API teslim edilmedi.
- Indexer/kontrat ekibi: Faz 4'te private record UUID ↔ doğrulanmış chain delivery kimliği bağlanmalı; `PrivateDeliveryProjection.findConfirmed` customer, assigned courier, lifecycle ve confirmed bilgisini güvenilir projection'dan okumalı. Legacy status/tx hash bu bağ için kanıt değildir. Provider şu anda null döndürür; private erişim kapalıdır.
- Ürün/güvenlik: customer saklama süresi, Accepted/InTransit dışındaki courier erişim ihtiyacı, dispute/evidence erişim matrisi, support/admin yetkileri, kişisel veri silme ve retention kararları bekleniyor. Mevcut kurye allowlist teslimat kodunu ve recipient wallet'ı içermez. Faz 2 user email/phone alanları mevcut saklama biçiminde kalır; bunların şifreleme/retention kapsamı ayrıca kararlaştırılmalı.
- Altyapı: runtime için `PRIVATE_DATA_MASTER_KEY_B64` ve `PRIVATE_DATA_KEY_ID` kalıcı secret yönetimiyle sağlanmalı. Backup/key restore ve rotation prosedürü gerekli; tek key desteği varken eski key'i yerinde değiştirmeyin. DB backup tek başına decrypt için yeterli değildir.
- Veri ekibi: production Mongo read rolü, sabit source ID, kaynak snapshot/yazma dondurma penceresi ve kayıt sayımı kabulü sağlanmalı. Envanter yalnız Mongo wallet varlığını raporlar; SIWE ya da chain doğrulaması üretmez. Import lokalde read-only kullanıcıyla test edildi; gerçek kullanıcı dataset'i envanterlenmedi/aktarılmadı. Hatalı ve kapsam dışı alanların ürün eşlemesi ayrı inceleme gerektirir.
- Operasyon: `--confirm-production-import` iki modda uzak hedef audit yazısını da kapsar. Production import bu teslimde yapılmadı. Evidence storage provider, erişim URL politikası, retention ve RTO/RPO kararları bekliyor.

Çalıştırma, resume, exit code ve kaynak tutarlılığı sınırları: [private-data-operations.md](private-data-operations.md).

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
