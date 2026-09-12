# Test Haritası: sec. 33 Invariant'ları ve sec. 47 Arıza Senaryoları

> Bu doküman bir iddia listesi değil, bir **eşleme**. Her satır baseline'daki bir
> zorunluluğu, onu tutan somut bir test adına bağlıyor. Test adı verilemiyorsa
> satır **boşluk** diye işaretlenir — "yeşil suite" bir kanıt değildir.

**Güncel durum:** 468 test, 26 suite, 30 invariant fonksiyonu (5 stateful suite).

---

## Bir testin gerçekten çalıştığı nasıl gösteriliyor

Bir testin geçmesi, test ettiği şeyi gerçekten tuttuğu anlamına gelmiyor. Bu
depoda standart şu: **iddiayı taşıyan kodu boz, testin kırmızıya döndüğünü gör.**

`verification-log.md` her faz için mutasyon tablosu tutuyor. Bu yöntem şimdiye
kadar altı ayrı yerde, geçen ama hiçbir şey kanıtlamayan test yakaladı —
en son P4.3'te üç tane.

---

## sec. 33 — Çekirdek invariant'lar (18/18)

| # | Invariant | Onu tutan test |
|---|---|---|
| 1 | Vault ödeme gücünde | `invariant_VaultIsSolvent`, `invariant_VaultStaysSolvent`, `invariant_CourierCommitmentsWithinStake` |
| 2 | Bir teslimat yalnızca bir kez settle olur | `invariant_SettledEscrowNeverHoldsValue`, `test_Release_CannotSettleTwice`, `invariant_ADisputedDeliveryEndsInExactlyOneTerminalState` |
| 3 | Muhasebe değeri korur | `invariant_ValueIsConserved`, `test_Release_RejectsPayoutMismatch`, `test_EveryRulingSplitsTheWholeEscrow` |
| 4 | Kurye teminatı yeniden kullanılamaz | `invariant_CommitmentsNeverExceedStake`, `test_Collateral_CannotBeReservedTwice` |
| 5 | İhtilaflı teslimat normal başarı yolundan settle olamaz | `test_Invariant33_5_ADisputedDeliveryCannotSettleThroughSuccess` |
| 6 | Terminal durumlar yeniden açılamaz | `test_TerminalStateCannotReopen`, `invariant_LockedMatchesActiveLocks` |
| 7 | Kanıt nonce'ları tekrar edilemez | `invariant_PickupAcceptanceNeverReplayed`, `test_Rejects_ReplayOnSameDelivery`, `test_ReturnAcceptanceNonceIsBurnedOnUse` |
| 8 | Kapsam teklifleri tekrar edilemez | `invariant_ForgedQuoteNeverAccepted`, `test_QuoteCannotBeReplayed` |
| 9 | Teslim alma anında gerekli teminat yerinde | `test_Invariant33_9_PickupIsImpossibleBeforeCollateralIsLocked` |
| 10 | Kurye eşzamanlı custody limiti aşılamaz | `invariant_CustodyLimitNeverExceeded`, `test_Custody_LimitEnforced` |
| 11 | Revert eden alıcı settlement'ı bloke edemez | `test_invariant_RejectorCreditIsHeldNotLost`, `test_Failure_ARejectingCustomerCannotBlockAnybodysSettlement` |
| 12 | Ödül talepleri epoch bütçesini aşamaz | `testFuzz_ClaimsNeverExceedTheEpochBudget`, `test_ProofFromOneEpochCannotDrainAnother` |
| 13 | Aynı juror bir turda iki koltuk alamaz | `testFuzz_NoJurorTakesTwoSeats`, `test_AJurorCannotBeSeatedTwiceOnTheSameDraw`, `testFuzz_AWalkOverACompositeCandidateSetStillReachesEveryone` |
| 14 | Azınlıkta kalan juror sırf bu yüzden kesilmez | `test_TheOnlySlashingPathIsFailureToReveal`, `test_RevealedMinorityKeepsItsStake` |
| 15 | Admin eylemleri yapılandırılmış sınırlar içinde | `invariant_ParamsAlwaysWithinBounds`, `testFuzz_FeeNeverExceedsCeiling`, `test_RoleHolderCannotGrantThemselvesAnotherRole` |
| 16 | Müşteri kendi cüzdanını kurye seçemez | `invariant_CustomerIsNeverTheCourier`, `test_CustomerCannotBidOnOwnDelivery` |
| 17 | Escrow tutarı seçilen şartlarla birebir eşleşir | `test_Funding_RejectsWrongAmount`, `testFuzz_FundingMustMatchExactly` |
| 18 | Juror üyelik değişimi açılmış çekilişi etkileyemez | `test_ReplacingTheWholePoolAfterTheRequestChangesNothing`, `testFuzz_SnapshotIsImmutable`, `test_WithdrawingCannotEscapeAPendingDraw` |

**5, 9 ve 11 P5.1'de eklendi.** 11'in davranışı vault seviyesinde zaten test
ediliyordu ama teslimat seviyesinde karşılığı yoktu; 5 ve 9 için hiçbir test
yoktu. 5, P4.3 ile ortaya çıkan ve en çok önem taşıyan invariant: mahkeme
teslimatı tutarken müşterinin `confirmDelivery` ile jürinin arkasından kuryeye
ödeme yaptırabilmesi mümkün olmamalı.

---

## sec. 47 — Zorunlu arıza testleri (19 zincirde + 3 zincir dışı)

| Senaryo | Onu tutan test |
|---|---|
| Müşteri seçer ama hiç fonlamaz | `test_Failure_CustomerSelectsButNeverFunds` |
| Kurye gerekli kapsamı hiç sağlamaz | `test_Failure_CourierNeverProvidesCoverage` |
| Aynı teminat iki kez rezerve edilir | `test_Collateral_CannotBeReservedTwice`, `invariant_CommitmentsNeverExceedStake` |
| Teklifin süresi dolar | `test_ExpiredQuoteRejected` |
| Teklif imzacısı taklit edilir | `invariant_ForgedQuoteNeverAccepted`, `testFuzz_OnlyConfiguredSignerIsAccepted` |
| Pickup kanıtı tekrar edilir | `invariant_PickupAcceptanceNeverReplayed`, `test_Rejects_ReplayOnSameDelivery` |
| OTP tekrarı / tahmini | `test_Rejects_EmptyChallengeHash`, `test_ValidAttestation_EmitsChallengeCommitmentOnly`, `test_SignerRotation_InvalidatesOutstandingAttestations` |
| Alıcı MON kabul edemez | `test_Failure_ARejectingCustomerCannotBlockAnybodysSettlement`, `test_invariant_RejectorCreditIsHeldNotLost` |
| Alıcı bulunamaz | `test_Failure_NobodyConfirmsSoTheWindowFinalisesIt` |
| Başarısız iade | `test_Failure_ReturnIsAskedForAndNeverConfirmed` |
| Müşteri onaylamaz | `test_ChallengeWindow_PermissionlessFinalizer` |
| İhtilaf / timeout yarışı | `test_TheLongStopCannotSettleUnderALiveJury`, `test_ASilentCourtCannotFreezeAnybodysMoney` |
| Kurye paketi kaybeder | `test_ARulingSettlesTheEscrowAndOnlyOnce`, `test_EveryRulingSplitsTheWholeEscrow` |
| Juror oyunu açmaz | `test_SilenceIsSlashed`, `test_NoRevealsFailsRatherThanInventingARuling` |
| Aynı juror iki kez seçilmeye çalışılır | `test_AJurorCannotBeSeatedTwiceOnTheSameDraw`, `testFuzz_NoJurorTakesTwoSeats` |
| Rastgelelik sağlayıcısı cevap vermez | `test_SilentProviderLetsTheDrawBeAbandoned`, `test_SilentProviderStrandsNothing` |
| Ödül iki kez talep edilir | `test_DoubleClaimRejected`, `test_ClaimPaysExactlyOnce` |
| Referans grafiğinde döngü | `test_DirectCycleRejected`, `test_IndirectCycleRejected`, `test_TwoLawfulChainsCannotBeJoinedIntoAnUnlawfulOne` |
| Admin anahtarı ele geçirme tatbikatı | `testFuzz_OnlyEmergencyCanPause`, `test_RoleHolderCannotGrantThemselvesAnotherRole`, `test_Integration_PausePropagatesToConsumer` |

### Zincirde test edilmeyen üçü — ve neden

| Senaryo | Nerede test edilmeli |
|---|---|
| Indexer kesintisi / replay | **Backend.** Kontrat olay yayar; olayın kaç kez okunduğu okuyanın sorunu. |
| RPC sağlayıcı arızası | **Backend / frontend.** Kontratın RPC'den haberi yok. |
| Backend retry mükerrer istek üretir | **Backend.** Zincir tarafında karşılığı nonce ve durum makinesi; ikisi de test edilmiş durumda (33-7, 33-6). |

Bunlar için Solidity testi yazmak göstermelik olurdu: kontrat bu üç arızanın hiçbirini
gözlemleyemez. Sorumluluk backend'e yazıldı, buraya değil.

---

## Stateful invariant suite'leri

| Suite | Neyi sürüyor |
|---|---|
| `SettlementVaultInvariant` | Rastgele custody/settlement/claim dizileri, revert eden alıcı dahil |
| `CourierRegistryInvariant` | Stake, rezervasyon, custody, çıkış |
| `ProtocolConfigInvariant` | Parametre önerileri ve zaman kilidi |
| `DeliveryHubInvariant` | Teslimat yaşam döngüsünün tamamı, sahte kanıtlar dahil |
| `DisputeCourtInvariant` | İhtilafın dört bitiş yolu çakıştırılarak |

### Vacuity guard'ları

Her stateful suite, fuzzer'ın iddia ettiği yolları **gerçekten** kat ettiğini
ayrıca test ediyor. Bu gereksiz bir özen değil: `DisputeCourtInvariant` ilk
koşusunda beş invariant'ın hepsini geçti ve hiçbirini kanıtlamadı — fuzzer
bütçesini handler'ın getter'larına harcamış, tek bir ihtilaf açmamıştı.

---

## Boşluklar

Bu haritada **boşluk yok**: sec. 33'ün 18 maddesinin ve sec. 47'nin zincirde
karşılığı olan 19 senaryosunun her biri adlandırılmış bir teste bağlı.

Kapsam dışı bırakılanlar yukarıda açıkça listelendi. Ayrıca `dispute.md`
bölüm 9, hükümle ulaşılmayan teminat kesmeyi bilinen bir ekonomik eksik olarak
kaydediyor — bu bir test boşluğu değil, kapsam kararı.
