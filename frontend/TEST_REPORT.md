# Proje inceleme ve test raporu — 1 Ekim 2026

Ön yüz kuralları `frontend/AGENTS.md`, backend kuralları `backend/AGENTS.md` ve entegrasyon notları okundu. Uygulama kodu değiştirilmedi; bu rapor ve test kanıtları eklendi. Önceden bulunan `.claude/launch.json`, `backend/package-lock.json`, `backend/TODO.md` ve `contracts/deployments/local.json` değişikliklerine dokunulmadı.

## Çalışan ortam

- Ön yüz: Nuxt 4.5.2 / Vue 3.5.42, `http://localhost:3000`.
- Backend: NestJS 11 / Fastify, `http://127.0.0.1:3001`.
- Node: kurulu `v24.20.0` kullanıldı. Terminalin varsayılan `v20.19.4` sürümü paketlerin engine şartını karşılamıyor.
- PostgreSQL: yerel `5432`, `monosfer_v2`; Redis: yerel `6379`. Backend launch konfigürasyonunun yerel geliştirme ayarları kullanıldı.
- Production ön yüz ayrıca `3100` portunda çalıştırılıp kontrol edildi.
- Indexer, operations ve support mevcut geliştirme konfigürasyonunda kapalı. Liste API'si `indexing.status=disabled` ve boş veri döndürüyor.

## Kontrol sonuçları

| Kontrol | Sonuç |
| --- | --- |
| Ön yüz `npm run typecheck` | Geçti |
| Ön yüz kaynak ESLint: `eslint app server nuxt.config.ts` | Geçti |
| Ön yüz `oxlint .` | 0 hata, 0 uyarı |
| Ön yüz genel ESLint: `eslint .` | **96 hata**; üretilmiş `.nuxt`/`.output` dosyaları taranıyor |
| Ön yüz `npm run build` | Geçti |
| Backend `npm run typecheck` | Geçti |
| Backend `npm test` | **87/87 geçti** |
| Backend `npm run test:legacy` | **13/13 geçti** |
| Backend integration suite | **39/40 geçti**; MongoDB fixture servisi eksik |
| Kök `npm run test:deploy` | **2/2 geçti** |
| `forge test --offline` | **493/493 geçti**, 26 suite |
| Kontrat `forge fmt --check` | Geçti |
| Kontrat test haritası | 65 referans, 0 çözülemeyen test |
| Kontrat `node tools/build-exports.mjs --check` | Başarısız; mevcut yerel deployment kaydı export şemasına uymuyor |
| npm bağımlılık güvenlik taraması | Otomatik onay incelemesi veri paylaşımı nedeniyle reddetti; kullanıcı onayı bekliyor |

Lint'in `--fix` seçenekleri çalıştırılmadı; inceleme sırasında kaynak veya üretilmiş dosyalar otomatik değiştirilmedi. İlk sandbox çalıştırmasında yerel port açma izni olmayan testler, localhost erişimiyle yeniden çalıştırıldı; yukarıdaki sonuçlar yeniden çalıştırmanın sonuçlarıdır.

## Tarayıcı ve canlı API doğrulaması

- Ana sayfa, teslimat listesi, kurye dizini, harita, giriş ve kayıt sayfaları açıldı. MetaMask bulunmadığında bağlantı butonu devre dışı ve açıklama görünür.
- Mobil menü açma/kapatma, Escape ile kapatma, menüden sayfa geçişi, teslimat araması/filtreleri, teslimat demosunda adım değiştirme ve animasyonu duraklatma çalıştı. Liste araması/filtreleri boş veri üzerinde kontrol edildi; sonuçların dolu veri üzerinde doğruluğu ayrıca test edilmeli.
- `1440×1000` ana sayfa ve `390×844` ana sayfa/liste/kurye dizini/giriş/harita kontrollerinde yatay taşma görülmedi.
- `/dashboard`, `/create`, `/payment/999999`, `/courier/receive/999999`, `/delivery/999999/confirm`, `/kuryem-nerede`, `/support`, `/support/new`, `/support/test-case`, `/support/test-case/delivery` oturumsuzken girişe yönlendirildi.
- Nuxt'un `/v1` proxy'si üzerinden live/ready 200; oturumsuz session/profile/support 401; geçersiz teslimat ID'si ve geçersiz nonce adresi 400 döndü. API yanıtlarında `Cache-Control: no-store` doğrulandı. OpenAPI 36 yol içeriyor.
- Gerçek HTTP üzerinden rastgele, yalnız test için oluşturulan EOA ile **nonce → imza doğrulama → cookie oturumu → CSRF olmadan profil güncelleme reddi (403) → CSRF ile profil güncelleme (200) → çıkış (204) → oturumun reddi (401)** geçti. Yalnız bu rastgele test cüzdanının SQL kayıtları temizlendi; gerçek kullanıcı cüzdanı veya zincir işlemi kullanılmadı.
- İlk Nuxt açılışında bağımlılık optimizasyonu sırasında tek bir dinamik modül yükleme hatası görüldü; yeniden yükleme sonrasında etkileşimler çalıştı. Kalıcı uygulama hatası olarak sınıflandırılmadı.

## Doğrulanmış hatalar

1. **P2 — Teslimat onay sayfasında hydration hatası.** `app/pages/delivery/[id]/confirm.vue:2` oturum gerektiriyor, ancak `nuxt.config.ts` içindeki `ssr:false` kuralları bu rotayı kapsamıyor. Oturumsuz doğrudan `/delivery/999999/confirm` açılışı server'da onay ekranını, client'ta giriş ekranını render ediyor. Development'ta node/class/children mismatch, production'ta `Hydration completed but contains mismatches.` tekrarlandı. Çözüm: bu rotayı client render kurallarına ekleyip hem doğrudan açılışı hem oturumlu açılışı doğrulamak.

2. **P2 — Genel lint komutu derleme sonrasında kırılıyor.** `eslint.config.ts:17` `.nuxt` ve `.output` dizinlerini ignore etmiyor. `eslint .` 96 hata verdi; kaynak dosyalara sınırlı tarama temiz. `package.json` içindeki lint script'i de `eslint . --fix` kullanıyor. Çözüm: üretilmiş Nuxt/Nitro dizinlerini global ignore listesine eklemek ve build sonrası genel lint'i çalıştırmak.

3. **Yerel tooling sorunu — Contract export kontrolü/generator hatası.** Oturumdan önce mevcut, untracked `contracts/deployments/local.json` Counter deployment kaydı içeriyor (`contractName,address,transactionHash,chainId,rpcUrl`); generator tüm JSON dosyalarını V1 manifest sanıyor (`tools/build-exports.mjs:71`). `--check`, `index.js` için stale sonucu verdi. Generator'ın `/tmp` içindeki izole kopyasında gerçek çıktı üretimi, yazma işleminden sonra `Object.keys(d.contracts)` satırında TypeError verdi. Repo export dosyaları değiştirilmedi. Çözüm: legacy/local kayıtları ayrı dizinde tutmak veya manifest şemasını dosyaları yazmadan önce doğrulamak.

## Kod incelemesiyle tespit edilen işlev boşlukları

Bu bölümdeki veri senaryoları gerçek zincir verisiyle tarayıcıda tekrar edilmedi; bulgular mevcut kaynak kodunun davranışına dayanıyor.

- **Detay sayfası kaydı ID ile yüklemiyor:** `app/pages/delivery/[id]/index.vue:22` yalnız store boşsa `loadDeliveries()` çağırıyor; `fetchDelivery(id)` kullanmıyor. Store doluyken eksik bir ID açılırsa veya kayıt ilk 100 sonucun dışında kalırsa mevcut teslimat için de “bulunamadı” gösterilir. `loadDeliveries()` ve `api/couriers.ts:list()` `nextCursor` değerini işlemiyor; liste/dizin de ilk sayfayla sınırlı.
- **Puanlama durumu kalıcı olarak okunmuyor, yorum gönderilmiyor:** `app/stores/useDeliveryStore.ts:402` `_comment` parametresini kullanmıyor; `rating/isRated` yalnız mevcut nesneye yazılıyor. `mapDelivery()` bu alanları yeniden oluşturmuyor. Yenileme sonrası puanlanmış teslimat yeniden puan bekliyor gibi görünebilir; yorum alanı kayıt yapılmış izlenimi veriyor. Zincire gönderilen puanın saklanması ayrı bir konudur; burada eksik olan UI'ın bunu yeniden okumasıdır.
- **Oluşturulma tarihleri yanlış:** Aynı store'da `mapBid():159` `validUntil` değerini, `mapDelivery():186` `stateDeadline` değerini `createdAt` olarak kullanıyor. Son geçerlilik/durum süreleri oluşturulma zamanı değildir; tarih ve “önce” metinleri yanıltıcı olabilir.
- **Harita kurye verisi hiçbir zaman gelmiyor:** `app/api/couriers.ts:54` `locations()` her zaman `[]` döndürüyor. Bu, V2'nin canlı konumu yalnız scoped tracking oturumunda sunma kararıyla tutarlı; ancak `app/pages/map.vue` “Canlı Konum Takibi” ve “Kuryeler kayıt olduğunda haritada görünecek” diyor. Kayıt olunsa da mevcut fonksiyon marker üretmez; ürün metni veya harita akışı güncellenmeli.
- **Ana sayfa istatistikleri sabit demo verisi:** `app/components/StatsSection.vue:11` 1247 teslimat, 342 kurye, %98,4 başarı ve 24680 MON sabitlerini gerçek metrik gibi gösteriyor. Çalışan API boşken animasyon sonunda bu rakamlar tarayıcıda da görüldü. Demo etiketi veya gerçek metrik kaynağı gerekli.
- **Kurallara uyum eksikleri:** `AGENTS.md` şablonda kebab-case istiyor; bazı bileşen çağrıları hâlâ PascalCase. Kök README de güncel Nuxt/NestJS mimarisini anlatmıyor. Bunlar çalışan testleri kıran hatalar değil, tutarlılık/dokümantasyon işleri.

## Kalan doğrulama ve devam notu

- `backend/tests/integration/private-data.test.mjs` için `127.0.0.1:57017` MongoDB fixture servisi gerekli. Makinede Docker veya mongod bulunamadı. Bu testin başarısızlığı uygulama assertion hatası değil, eksik servis (`ECONNREFUSED`).
- Gerçek MetaMask bağlantısı/imza reddi/hesap değişimi/çoklu sekme; dolu finalized projection ile teslimat oluşturma, teklif, escrow, pickup/return QR, OTP, canlı SSE ve support allowlist akışları henüz uçtan uca doğrulanmadı. Mevcut kapalı indexer/operations/support ve signer ayarlarıyla bunlara “geçti” denilemez. Backend bu alanların önemli bölümünü integration fixture'larıyla doğruluyor; bu, gerçek cüzdanlı browser E2E'nin yerine geçmez.
- Kamera, gerçek cihaz GPS izinleri, iOS Safari/Firefox QR fallback ve offline/service-worker davranışı ayrıca kontrol edilmeli.
- `npm audit` paket adlarını/sürümlerini public npm registry'ye göndereceğinden otomatik inceleme açık izin olmadan reddetti. Onay gelmeden bu veri paylaşımı yapılmadı.

## Sonraki iki görev

1. **Teknik doğrulama:** Hydration, lint ve ID/pagination yükleme hatalarını düzeltip dolu veriyle çalışan kalıcı frontend regression/E2E testleri eklemek; Mongo fixture'ıyla kalan integration testini tamamlamak. Böylece yalnız derleme başarısına güvenilmez.
2. **Ürün:** Ana sayfa metriklerini, harita mesajlarını ve puanlama/yorum ekranlarını V2'nin gerçekten sunduğu verilerle eşleştirmek. Böylece kullanıcıya henüz uygulanmamış davranışlar vaat edilmez.

## Kanıt dosyaları

- [Ana sayfa ekran görüntüsü](test-artifacts/home-desktop.jpg)
- [Production onay rotasından girişe yönlendirme](test-artifacts/production-confirm-redirect.jpg)
- `test-artifacts/` altında test logları ve browser hata kayıtları bulunur; `.log` dosyaları mevcut gitignore kuralıyla dışarıda kalır.
