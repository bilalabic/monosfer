# MONOSFER Kontrat Dokümantasyonu

Şartname depo kökündedir: `MONOSFER_Initial_Release_Base_Documentation_v1.0.md`
(kontrat + backend + frontend kapsar). Buradaki tüm dokümanlar ona referans verir.

## Tasarım referansları

Sistem geliştikçe güncellenir; sürüm/tarih taşımazlar.

| Doküman | İçerik |
|---|---|
| [`governance.md`](governance.md) | Rol matrisi, zaman kilitleri, pause runbook, parametre sınırları |
| [`settlement.md`](settlement.md) | Pull-payment modeli, ödeme gücü, reentrancy, pause davranışı |
| [`courier-registry.md`](courier-registry.md) | Stake bölünmesi, çıkış yolu, C0/C1/C2, custody limiti |
| [`delivery-lifecycle.md`](delivery-lifecycle.md) | 13 durumlu makine, her durumun çıkışı, teklifler, fonlama, uzlaşma |
| [`risk-quote.md`](risk-quote.md) | İmzalı kapsam teklifi, kapsam bandı, tekrar koruması, teminat bölünmesi |
| [`reputation.md`](reputation.md) | 0-1000 puan, ayrı güven seviyesi, sec. 19 ağırlıkları, sürümleme |
| [`badges.md`](badges.md) | Devredilemez rozetler, ERC-5192, talep/verme ayrımı |
| [`rewards.md`](rewards.md) | Epoch bütçesi, Merkle talep, geri alma, referans kuralları |
| [`proofs.md`](proofs.md) | Teslim alma kabulü, iade kanıtı ve PoD attestation: altı kontrol, nonce, ERC-1271 |
| [`dispute.md`](dispute.md) | Jüri yaşam döngüsü, 3→5→7 itiraz, hüküm settlement'ı, yedek komite |
| [`integration.md`](integration.md) | Frontend/backend için adres + ABI + tip paylaşımı |
| [`testing.md`](testing.md) | sec. 33 invariant'ları ve sec. 47 arıza senaryolarının test haritası |
| [`static-analysis-baseline.md`](static-analysis-baseline.md) | Devralınan kontratların kabul edilen Slither bulguları ve `forge lint` dağılımı |

## Analiz ve plan

Sürümlü belgeler; içerik revize edilirse sürüm numarası artar.

| Doküman | İçerik |
|---|---|
| [`contract-analysis-v1.0.md`](contract-analysis-v1.0.md) | Kontratların baseline'a karşı boşluk analizi: doğru olanlar, eksikler, iyileştirilecekler, dokunulmayacaklar |
| [`implementation-plan-v1.0.md`](implementation-plan-v1.0.md) | P0–P5 fazlı uygulama planı, branch stratejisi, artefakt paylaşımı, onay gerektiren kararlar |

## Kayıt

| Doküman | İçerik |
|---|---|
| [`verification-log.md`](verification-log.md) | Faz faz doğrulama sonuçları, testnet senaryoları, yakalanan hatalar |

## Faz durumu

| Faz | Konu | Durum |
|---|---|---|
| P0.1 | CI, regresyon ağı, gas baseline | **Tamamlandı** |
| P0.2 | `ProtocolAccessManager` + `ProtocolConfig` | **Tamamlandı** |
| P0.3 | `SettlementVault` | **Tamamlandı** |
| P0.4 | `CourierRegistry` | **Tamamlandı** |
| P1.1 | `DeliveryHub` — yaşam döngüsü, iptal/timeout, self-dealing engeli | **Tamamlandı** |
| P1.2 | İki taraflı fonlama oturumu | **Tamamlandı** (P1.1 içinde) |
| P1.3 | İmzalı risk teklifi ve kapsam matematiği | **Tamamlandı** |
| P2.1 | Teslim alma kanıtı (EIP-712 / ERC-1271) | **Tamamlandı** |
| P2.2 | PoD attestation (cüzdansız alıcı) | **Tamamlandı** |
| P2.3 | İtiraz penceresi ve izinsiz finalize | **Tamamlandı**; ihtilaf girişi P4.3 ile bağlandı |
| P2.4 | İade akışı | **Tamamlandı**; iade kanıtı `MONOSFER.RETURN` aksiyonuyla eklendi |
| P3.1 | `ReputationRegistry` — puan, güven, sürümleme | **Tamamlandı** |
| P3.2 | `BadgeSBT` (ERC-721 + ERC-5192) | **Tamamlandı** |
| P3.3 | Ödül dağıtımı v2 + referans | **Tamamlandı** |
| P4.1 | `IRandomnessAdapter` + `PythEntropyAdapter` | **Tamamlandı** |
| P4.2 | `DisputeCourt` çekirdeği — kanıt, çekiliş, commit/reveal | **Tamamlandı** |
| P4.3 | İtirazlar, yedek komite, hüküm settlement'ı | **Tamamlandı** |
| P5.1 | Invariant / arıza / adversarial suite | **Tamamlandı** |
| P5.2 | Deploy sertleştirme + artefakt export | Sırada |
| P5.3 | Testnet E2E, cut-over, güvenlik incelemesi | Bekliyor |
