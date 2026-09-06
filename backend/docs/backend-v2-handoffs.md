# V2 Backend Ekip Bağımlılıkları

## Frontend

- Yeni sözleşme `/v1`; eski `/api` endpoint'leri yeni runtime'da bulunmaz. Faz 1 yalnız health endpoint'leri sağlar.
- OpenAPI `/v1/openapi.json`; `npm run openapi:export` çıktısı `artifacts/openapi.json`. Tip üretimi frontend ekibinin sorumluluğudur.
- Hata: `{error:{code,message,requestId}}`; `x-request-id` destek taleplerinde korelasyon için kullanılabilir.
- Faz 2'de SIWE/session sözleşmesi ayrıca teslim edilecek. Faz 4'te confirmed/indexing pending ayrımı gelecek.
- Production CORS origin listesi ve BFF/proxy yerleşimi gerekli. Private/auth/financial cevaplar service-worker cache'ine alınmamalı.

## Contracts

- ABI/deployment kaynağı mevcut `contracts/exports/`; backend kopya adres üretmeyecek.
- V2'ye birleşmiş commit esas alınacak. 2026-09-07 kontrolünde P2.1 pickup proof `98d7e64` (PR #4) ile V2'ye alındı; Faz 4 entegrasyonu güncel imzalı pickup ABI'sini esas almalı.
- Quote policy/price audit alanları off-chain kayıtta tutulacak; EIP-712 mesajına ABI dışı alan eklenmeyecek.

## Altyapı/DevOps

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
