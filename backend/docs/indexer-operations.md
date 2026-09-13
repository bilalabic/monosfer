# Faz 4 indexer ve projection işletimi

Bu teslim yalnız mevcut V2 `DeliveryHub` export'unu tüketir. Build `contracts/exports/index.js` içinden ABI, legacy olmayan deployment adresi/başlangıç bloğu ve fingerprint içeren `backend/dist/indexer/contracts.json` üretir. Elle ABI/adres kopyası tutulmaz; TypeScript kaynağı backend dışına yazmaz. Backend build ortamında repo export paketi bulunmalı; çalışma ortamına backend dist bundle'ı taşınmalıdır. Export değişirse mevcut cursor fingerprint kontrolü durur; yeni deployment veya uyumluluk değişikliği incelenmeden cursor güncellenmez.

## Başlatma ve komutlar

Komutları backend dizininde çalıştırın. `.env.example` runtime ayarlarına ek olarak `INDEXER_ENABLED=true` ve `INDEXER_RPC_URL` gerekir. Chain varsayılan 10143; desteklenen ağlar export bundle'ından gelir. RPC için yanlış chain, boş contract code, desteklenmeyen finalized tag ve malformed log güvenli hata üretir. Bytecode varlığı kontrolü tam bytecode/source attestation değildir; deployment manifest'i kontrat ekibinin doğrulanmış teslimi olmalıdır.

API konfigürasyonunda aktif indexer chain ID ile SIWE chain ID aynı olmak zorundadır; farklı ağlardaki aynı contract-wallet adresi üzerinden yetki aktarımı yapılmaz.

```sh
npm run db:migrate
npm run indexer -- once
npm run indexer -- watch
npm run indexer -- reconcile
npm run indexer -- replay
# Replay sonrasında hazır durumuna dönmek için:
npm run indexer -- reconcile
npm run indexer -- once
```

API process'i zincir polling yapmaz. Worker ayrı process'tir ve SQL cursor'dan devam eder. `once` en fazla bir batch tüketir; backfill için watch çalışır. Varsayılan batch 100 (üst sınır 200), blok fetch eşzamanlılığı 8, polling 2 saniye; her RPC çağrısı 5 saniye timeout ve en fazla 1 retry kullanır. Watch hatalarında bekleme 60 saniyeye kadar artar. SIGTERM/SIGINT RPC fetch/beklemeyi abort eder; aktif SQL işi bitirilir veya rollback olur, pool kapanır. Daemon yönetimi/deploy dosyası bu teslimde eklenmedi.

Komutlar PostgreSQL'e cursor/projection/audit yazdığı için localhost + `monosfer_v2`/`monosfer_v2_test` dışı hedef veya NODE_ENV=production, açık `--confirm-production-indexing` flag'i gerektirir. Bu flag hiçbir testte kullanılmadı. RPC yalnız read metodları kullanır; wallet/private key gerekmez ve tx göndermez. CLI hata event'leri sabittir; URI/raw RPC error/log payload loglanmaz. Exit 0 başarı, 1 operasyon hatası, reconcile için 2 tutarsızlık bulunmasıdır.

## Kaynak ve doğruluk

Yalnız RPC `finalized` seviyesine kadar indekslenir; latest/safe spekülatif sonuçlar projection'a girmez. Bu politika [Monad block states](https://docs.monad.xyz/monad-arch/consensus/block-states) ve monskill/concepts block-states rehberiyle seçildi. Düşük gecikmeli WS yayınları bu fazda kullanılmaz: uygulama bazında filtreli ve sınırlı HTTP backfill/polling uygulanır. Ağın bütün event'lerini indekslemek hedef değildir. Provider büyük tarih aralıklarını/archival eth_call'u karşılamalı; 429/timeout durumunda batch/RPC kapasitesi ayarlanmalıdır.

`chain_event_inbox` raw log + strict ABI decode, block hash/height/tx/log index ve canonical bayrağını tutar. DB'de unique event ve tek canonical height constraint'leri vardır. Sırasız/aynı log tekrarları sıralanıp tekilleştirilir; çelişkili duplicate, yabancı adres, removed/malformed/unknown event reddedilir. Inherited ABI event'leri de inbox'a girer; yalnız ilgili lifecycle event'leri delivery/bid projection değiştirir. Tutarlar/ID'ler JavaScript number'a dönüştürülmez.

Blok, inbox, projection ve ilerleyen cursor aynı transaction'dadır. Bidding→AwaitingFunding state event'i CourierSelected'den önce gelir; projector bu gerçek kontrat sırasını izler. Selected bid funding'e kadar active kalabilir. `active` rezervasyon durumudur, seçilebilirlik garantisi değildir; lifecycle, expiry ve termsVersion ayrıca önemlidir. Terminalde kaybeden bidder'ın rezervasyonu withdraw edilene kadar active kalır. V2 state'leri legacy Accepted/Delivered adlarına çevrilmez.

Her çalıştırmada checkpoint hash kontrol edilir. Uyuşmazlıkta en fazla INDEXER_REORG_DEPTH (varsayılan 64) içinde ortak ata aranır. Sonraki blok/event'ler silinmez, orphan olarak korunur; etkilenen delivery/bid projection'ları canonical inbox'tan yeniden hesaplanır ve cursor geri alınır. Daha derin uyuşmazlık veya gerileyen finalized head hata verir; otomatik geniş reset yapılmaz. Bu, finalized verinin beklenmedik RPC fork/operatör müdahalesine karşı korumadır; normal finalized blokların reorg olması beklenmez.

Replay projection'ları inbox'tan oluşturur; legacy/private/session tablolarını değiştirmez. Kayıtlar event cursor'ıyla 500'lük gruplarda okunur; replay bir bakım transaction'ıdır. Bütün delivery kimlikleri ve tek delivery'nin bid durumu bellekte tutulur; büyük dataset için bellek/bakım süresi ölçülmeden üretim kapasitesi varsayılmamalıdır.

Reconcile checkpoint bloğunda `nextDeliveryId`, `deliveryOf`, bilinen `bidOf` alanlarını karşılaştırır. Ayrıca tüm indekslenmiş aralığı batch'lerle tekrar getLogs üzerinden okuyup canonical inbox ile karşılaştırır ve inbox'tan yeniden hesaplanan projection'ı kontrol eder. Böylece eksik bid projection, event atlama ve projection bozulması raporlanır. Son checkpoint hash tekrar kontrol edilir. Bu işlem tarihçe uzunluğuyla büyür ve archive RPC gerektirir. Tutarsızlıkta `integrity_ok=false` olur; once/watch bunu temizleyemez. Projection sorunu replay + başarılı reconcile ile giderilir. Inbox eksik/bozuksa replay tek başına onarmaz; kaynak/provider düzeltildikten sonra ayrı incelenmiş backfill gerekir. Aynı provider sürekli aynı eksik cevabı verirse bağımsız kriptografik log completeness kanıtı sağlanmış olmaz.

## HTTP sözleşmesi

| Endpoint | Sonuç |
| --- | --- |
| GET /v1/indexer/status | disabled/indexing_pending/syncing/ready/stale/error, chainId, indexedBlock, finalizedBlock, lagBlocks, checkedAt |
| GET /v1/deliveries?limit=25&after=0 | `{indexing,data:[Delivery],nextCursor}`; exclusive decimal ID cursor, max 100 |
| GET /v1/deliveries/:id | `{indexing,data:Delivery}`; bilinmeyen ID ready iken 404, henüz doğrulanamıyorsa 202 ve data:null |
| GET /v1/deliveries/:id/bids?limit=25&after=0x… | `{indexing,data:[Bid],nextCursor}`; exclusive lowercase wallet cursor, max 100 |

Delivery state: Bidding, AwaitingFunding, ReadyForPickup, InTransit, DeliveredPending, ReturnRequired, Disputed, Completed, Returned, Resolved, Cancelled, Expired. IDs, riskTier, termsVersion, deadline/validUntil (Unix saniyesi), ETA ve tutarlar decimal string; funding/active boolean. Courier seçilmediyse zero address. Fiyatlar kontrattaki tam birim miktarlardır; backend token formatlaması/kur dönüşümü yapmaz. OpenAPI alanları tanımlar. Liste/bid sayfaları canlı projection üzerinde cursor pagination'dır, sayfalar arası snapshot garantisi yoktur.

## Contract Sync reindex — 2026-09-13

`1789344000000-contract-sync.sql`, `indexer_blocks.timestamp` alanını ekler. Eski canonical blok timestamp'i NULL olan stream'ler error/integrity=false işaretlenir; timestamp uydurulmaz. Worker böyle bir stream'de once/replay/reconcile ile ilerlemeyi reddeder. `etaMinutes` seçilen bid'den, `etaDeadline=pickupBlockTimestamp+etaMinutes*60`, `completedAt=CompletedBlockTimestamp` alınır. Disputed state 7, Completed 8, Resolved 10'dur.

Build fingerprint artık DeliveryHub ve DisputeCourt ABI/address/deployment block verisini kapsar. Staging prosedürü:

1. İlgili indexer/link/provider worker'larını kontrollü durdurun, mevcut DB/anahtar/object backup'ını koruyun. Production işlemi için ayrıca operasyon yetkilendirmesi gerekir.
2. Backend build, yeni migration ve export adres/bloklarını doğrulayın. Eski fingerprint'i SQL'de yenisiyle değiştirip geçmeyin.
3. Yeni hub adresinde worker doğal olarak yeni `chainId:hubAddress` stream'i açar; eski stream verisi korunur. Aynı hub adresiyle timestamp'siz/eski fingerprint stream'i yeniden kurmak gerekiyorsa PK çakışması nedeniyle aynı DB'de ikinci stream açılamaz: yeni izole staging PostgreSQL hedefi hazırlayın veya ayrıca incelenmiş arşivleme/backfill migration'ı isteyin. Bu teslim otomatik silme/reset aracı içermez.
4. Archive RPC ile `npm run indexer -- watch` çalıştırıp finalized head'e kadar tamamlayın. Sonra `npm run indexer -- reconcile`, sıfır mismatch ardından `npm run indexer -- once`. Event/projection onarımı gerekiyorsa replay → reconcile → once; NULL timestamp için replay yeterli değildir.
5. Ready, integrity_ok, sıfır lag, güncel fingerprint ve timestamp'leri doğrulayın. Private link'ler deployment'a bağlıdır; eski link'ler yeni stream'e kopyalanmaz. Link worker yalnız yeni trusted quoteDigest/customer eşleşmesiyle bağ kurar. Reputation rebuild ve proof read smoke sonrası API/worker geçişini yapın.

DisputeCourt aynı finalized aralıkta ayrı inbox/projection'a alınır; reconcile taze court log taramasını ve yeniden üretilmiş projection'ı kontrol eder. `ResolvedByCommittee` alarm gauge'u reorg'da azalabilir. Reorg sırasında hub ve court verisi tek transaction'da geri alınır. Bu teslimde staging reindex veya production migration çalıştırılmadı.

Yalnız kamuya açık on-chain alanlar döner. Delivery write, bid write, arbitrary event ingestion, private payload veya private-link endpoint'i yoktur. DTO'lar bilinmeyen parametre ve geçersiz/uint256 dışı ID'leri reddeder. DB hatası mevcut standart 503 yanıtını verir. Process/dependency health ayrı kalır; frontend/monitoring indexer durumuna da bakmalıdır. Heartbeat süresi geçerse stale; backlog varsa syncing olur. Var olan projection stale/error iken okunabilir fakat indexing metadata durumunu açıkça taşır; UI son durum olduğunu varsaymamalıdır.

## Private veri bağı ve ekip teslimi

PrivateDeliveryProjection `private_delivery_links` üzerinden quoteDigest, customer, chain/contract ve export fingerprint'i kontrol eder. Sadece ready, sıfır bilinen lag, güncel heartbeat ve integrity_ok durumunda yetki üretir. Kurye ReadyForPickup/InTransit dışında okuyamaz; customer own payload politikası korunur. On-chain deadline'ın geçmesi kendiliğinden yeni state değildir; kontrattaki event esas alınır.

Bu faz link tablosuna uygulama yazıcısı eklemez. Faz 5 server-issued quote kaydı private record → signed quote digest bağını üretmeli; o digest'li DeliveryCreated doğrulandığında ilişki kurulmalıdır. Legacy Mongo ID/wallet/tx hash benzerliği yetki vermez. Testte explicit link yalnız fixture olarak kurulur; gerçek imported kayıtlar halen legacy_unverified'dır.

Sonraki işler: (1) archive RPC, büyük dataset replay/backfill kapasitesi ve export/deployment tutarlılığı için operasyon smoke; (2) Faz 5 signed quote/audit/outbox ve güvenilir private-record bağının oluşturulması.
