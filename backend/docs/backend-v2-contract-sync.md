# Backend Contract Sync — 2026-09-13

Kaynak `Monosfer-V2@9a15adc`, `contracts/src/v1/hub/DeliveryHub.sol`, proof verifier'ları ve build sırasında tüketilen `contracts/exports`. Değişiklikler yalnız backend altındadır. Her proof issuance SQL transaction'ı commit olmadan cevap dönmez. Backend transaction göndermez.

## Proof API

Üç POST isteği de SIWE session cookie, izinli `Origin`, `x-csrf-token` ve 16–128 karakterlik `Idempotency-Key` ister. Path `id`, decimal uint256'dır. Bilinmeyen body alanları reddedilir. Başarılı cevap 201; tüm hatalar `{error:{code,message,requestId}}` formatındadır.

| Yol | Aktör / finalized state | Body | Sonuç |
| --- | --- | --- | --- |
| `/v1/deliveries/:id/pickup-acceptances` | customer / ReadyForPickup | `{}` | `{acceptance,typedData,digest,expiresAt,status}` |
| `/v1/deliveries/:id/return-acceptances` | customer / ReturnRequired | `{}` | Aynı format, return action |
| `/v1/deliveries/:id/pod-attestations` | courier / InTransit | `{proofType:"otp",code:string}` | `{attestation,typedData,digest,signature,expiresAt,status}` |

`status="issued"`; outer `expiresAt` ISO-8601. Struct integer alanları decimal string'dir. `typedData={domain,types,primaryType,message}`. Domain `{name:"MONOSFER",version:"1",chainId,verifyingContract}` zincirdeki `eip712Domain()` ile doğrulanır; hub/config adresleri generated export bundle'dan gelir.

Pickup/return struct sırası: `PickupAcceptance(uint256 deliveryId,address courier,bytes32 action,uint256 nonce,uint64 expiresAt)`. Backend customer adına imzalamaz. Customer `typedData`'yı imzalar; atanmış courier acceptance + imzayı hub `confirmPickup` veya `confirmReturn` çağrısına geçirir. Aksiyon `pickupAction()` / `returnAction()`, harcanmış nonce kontrolü `pickupNonceUsed(customer,nonce)` üzerinden yapılır.

PoD struct sırası: `PodAttestation(uint256 deliveryId,address courier,bytes32 proofType,bytes32 challengeHash,uint256 nonce,uint64 issuedAt,uint64 expiresAt)`. Backend yalnız `podProofTypes()` OTP tipini kullanır. Private link, quote digest, customer, stream ve fingerprint doğrulanmadan kod okunmaz. `dropoff.deliveryCode` sabit uzunluklu hash'ler üzerinden timing-safe karşılaştırılır. `challengeHash` server-keyed HMAC ile deployment, delivery, random nonce ve kodu bağlar; kısa OTP'nin zincirden sözlük saldırısıyla çıkarılmasını önler. Alıcı imzası veya QR doğrulandığı iddia edilmez.

Zincirden `podAttestationSigner` ve `podAttestationValidity` okunur; configured signer ve TTL uyuşmazsa 503. Sonuç backend'in `hashTypedData` çıktısı ile `hashPickupAcceptance` / `hashPodAttestation` eth_call sonucu eşleştirildikten sonra döner. Seçilen finalized snapshot hash'i tekrar kontrol edilir. Nonce 256-bit CSPRNG değeridir; harcanmış nonce yanıtı fail-closed olur. Sonraki bir zincir işlemi bu kontrolün ardından state/nonce'u değiştirebilir; nihai otorite kontrat doğrulamasıdır.

## Retry, süre ve gizlilik

Aynı actor/route/delivery/deployment/key ve body, geçerli süre boyunca aynı şifreli kayıtlı response'u döndürür; farklı body veya expiry 409. Retry sırasında trusted lifecycle, RPC hash/nonce, current signer tekrar doğrulanır. Süresi dolan key yeniden kullanılmaz; yeni key alınır. Success cached retry OTP deneme bütçesini artırmaz. Yeni PoD isteği delivery başına Redis'te saatte 5 denemeyle sınırlıdır; rollback deneme sayacını geri almaz. Redis arızasında PoD yeni issuance 503 olur.

Varsayılan acceptance ve PoD TTL 300 saniye; expiry ayrıca delivery stateDeadline ile sınırlı. PoD config üst sınırı 600 saniye ve zincir validity'sidir. `PROOF_IDEMPOTENCY_TTL_SECONDS=86400` replay cache üst süresidir; proof expiry daha erkense yine 409. Süre dolumu otomatik SQL silme işi değildir; retention kararı handoff'tadır.

Config: `POD_ATTESTATION_SIGNER_PRIVATE_KEY` (isteğe bağlı, yoksa PoD 503), `POD_ATTESTATION_TTL_SECONDS`, `PROOF_ACCEPTANCE_TTL_SECONDS`, `PROOF_IDEMPOTENCY_TTL_SECONDS`. PoD anahtarı quote anahtarıyla aynı olamaz. Runtime env, raw code, nonce, signature, typedData ve response payload loglanmaz; SQL response AES-256-GCM ile ayrı proof AAD'sine bağlı saklanır. Ops trace yalnız request/status/duration bilgisi taşır.

## Projection ve ops

Yeni delivery state sırası 0–12: None, Bidding, AwaitingFunding, ReadyForPickup, InTransit, DeliveredPending, ReturnRequired, Disputed, Completed, Returned, Resolved, Cancelled, Expired. `Completed` terminal başlangıcıdır. ETA/completedAt event bloğunun timestamp'inden türetilir; yerel sunucu zamanı kullanılmaz.

DisputeCourt eventi hub event'iyle aynı checkpoint transaction'ında ayrı inbox'a alınır. Panel/evidence sayacı, appeal, settlement, abandonment ve committee bilgisi yalnız canonical finalized event'lerden türetilir; private evidence content eklenmez. Reorg orphan event'leri saklar ve projection'ı yeniden kurar. Support summary `dispute` ve `committeeResolutionAlert`; ops status `committeeResolutions` ve text metrics `monosfer_committee_resolutions` döndürür. Bu gauge bir lifetime counter değildir.

Reputation sayaçları backend delivery projection'ından gelir. Dört eksik ABI export'u gelmeden on-chain reputation/referral/reward API'si varmış gibi davranılmaz. Source metadata bu ayrımı açıkça gösterir.

Monad rehberinin uzak block-states dosyası alınamadığından finalized eşlemesi resmi [block states](https://docs.monad.xyz/monad-arch/consensus/block-states) belgesinden kontrol edildi; mevcut finalized-only politika korundu.
