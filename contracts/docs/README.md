# MONOSFER Kontrat Dokümantasyonu

İsimlendirme: `YYYY-AA-GG-konu-vX.Y.md` — tarih dokümanın **oluşturulduğu/güncellendiği**
gün, sürüm ise içeriğin revizyonu. Kronolojik sıralanır, en yenisi en altta.

## Kalıcı referanslar (sürümsüz, sürekli güncellenir)

| Doküman | İçerik |
|---|---|
| [`static-analysis-baseline.md`](static-analysis-baseline.md) | Kabul edilen legacy Slither bulguları (48) ve `forge lint` dağılımı |
| [`governance.md`](governance.md) | Rol matrisi, zaman kilitleri, pause runbook, parametre sınırları (P0.2) |

## Analiz ve plan

| Doküman | İçerik |
|---|---|
| [`2026-09-05-contract-analysis-v1.0.md`](2026-09-05-contract-analysis-v1.0.md) | Kontratların v1.0 baseline'a karşı boşluk analizi. Doğru olanlar, eksikler, iyileştirilecekler, dokunulmayacaklar |
| [`2026-09-05-implementation-plan-v1.0.md`](2026-09-05-implementation-plan-v1.0.md) | P0–P5 fazlı uygulama planı, branch stratejisi, artefakt paylaşımı, onay gereken kararlar |

## Doğrulama raporları

| Doküman | İçerik |
|---|---|
| [`2026-09-06-p0.1-verification-report-v1.1.md`](2026-09-06-p0.1-verification-report-v1.1.md) | P0.1 (CI, regresyon ağı, gas baseline) doğrulaması. v1.1 = Foundry 1.8.1 yükseltmesi sonrası |
| [`2026-09-06-testnet-verification-report-v1.0.md`](2026-09-06-testnet-verification-report-v1.0.md) | Monad testnet canlı doğrulaması: 2 sistem deploy, tam yaşam döngüsü, 4 kritik bulgunun zincirde kanıtı |
| [`2026-09-06-p0.2-verification-report-v1.0.md`](2026-09-06-p0.2-verification-report-v1.0.md) | P0.2 (ProtocolAccessManager + ProtocolConfig) doğrulaması, 59/59 test, kapatılan bulgular |

## Depo kökündeki ilgili doküman

`MONOSFER_Initial_Release_Base_Documentation_v1.0.md` — ürünün tamamını (kontrat +
backend + frontend) kapsayan baseline şartname. Kapsamı yalnızca kontratlar olmadığı
için kökte bırakıldı; buradaki tüm dokümanlar ona referans verir.

## Faz durumu

| Faz | Konu | Durum |
|---|---|---|
| P0.1 | CI, regresyon ağı, gas baseline | **Tamamlandı** — yerelde ve testnet'te doğrulandı |
| P0.2 | `ProtocolAccessManager` + `ProtocolConfig` | **Tamamlandı** — 54 yeni test, 5 invariant |
| P0.3 | `SettlementVault` (pull-payment, ödeme tıkanmasını çözer) | Bekliyor |
| P0.4 | `CourierRegistry` (stake çekme, custody limiti) | Bekliyor |
| P1.x | Yaşam döngüsü, iptal/timeout, self-dealing engeli, kapsam/teminat | Bekliyor |
| P2–P5 | Kanıtlar, itibar, ödül, ihtilaf, sertleştirme | Bekliyor |
