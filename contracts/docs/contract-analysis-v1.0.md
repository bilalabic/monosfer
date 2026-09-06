# MONOSFER — Smart Contract Analysis vs. Initial Release Baseline v1.0

> **Scope:** `contracts/` only (contracts, architecture, business logic, access control, security, events, error handling, gas, tests, deployment). Frontend and backend deliberately excluded.
> **Baseline:** `MONOSFER_Initial_Release_Base_Documentation_v1.0.md`
> **Code analysed:** `main` @ `1139d8f` and `origin/Monosfer-V2` @ `fa8a884`
> **Date:** 5 September 2026

### Branch note — `Monosfer-V2` contains no contract changes

`git diff main origin/Monosfer-V2 -- contracts` is **empty**. The V2 branch is a frontend-only migration (Nuxt 4, PWA, wagmi, homepage/dashboard rework — 93 files, all under `frontend/`). Every finding below therefore applies identically to both branches. **There is currently no contract-side V2.**

### Verification performed

- `forge build` — clean (Solc 0.8.24, `via_ir = true`).
- `forge test` — **5/5 pass** (4 in `Delivera.t.sol`, 1 in `DeliveryEscrow.t.sol`).
- 6 throwaway proof-of-concept tests were run against the real contracts to confirm the critical findings, then deleted. Results are cited inline as **[PoC-A…F]**. No repository code was modified.

---

## 1. Sufficient and correctly implemented parts

These work as written and match the baseline's intent. Keep them.

| Area | What is correct |
|---|---|
| **Toolchain** | Foundry + Solidity `0.8.24` pinned in `foundry.toml`, optimizer + `via_ir` on. Matches §44's baseline choice. |
| **Happy-path lifecycle** | `create → bid → accept → pickup → deliver → rate` is coherent and end-to-end tested in both `Delivera.sol` and `DeliveryEscrow.sol`. This is the §2 core loop in skeleton form. |
| **Bid-deposit accounting** | `courierStake -= BID_DEPOSIT` → `lockedBidDeposits[requestId][courier]`. The same stake cannot back two simultaneous bids. This is the one place the baseline's §8.3 *"same base collateral cannot protect two deliveries"* rule is genuinely honoured. |
| **Losing-bidder refunds** | `_refundNonSelectedBidDeposits` correctly zeroes before crediting, and skips the winner. No double-refund. |
| **Fee arithmetic** | `treasuryFee = platformFee - rewardFee` avoids the rounding leak of two independent divisions. Value is conserved exactly in the success path. |
| **Terminal-state discipline** | Status guards on every transition prevent re-entry into `confirmPickup`/`confirmDelivery`/`submitRating`. Satisfies invariants §33-2 and §33-6 for the paths that exist. |
| **Rating hygiene** | One rating per delivery, customer-only, `1..5` bounded, does not reopen settlement. Matches §20 precisely. |
| **Soulbound intent** | `ReputationBadge.transferFrom` reverts — the *intent* of §24 is right (implementation is incomplete, see §2). |
| **Merkle claim core** | `RewardDistributor` uses a double-hashed leaf (`keccak256(bytes.concat(keccak256(abi.encode(...))))`), which is second-preimage safe and OZ-compatible. Per-period `claimed` mapping blocks the simple double-claim. |
| **Modular wiring** | `Leaderboard.onlyEscrow` + `ReputationBadge.onlyMinter` correctly isolate who may mutate reputation and mint badges. Right shape, wrong governance (see §3). |
| **Off-chain boundary** | Only `pickupHash` / `deliveryHash` are stored — no addresses, no phone numbers, no GPS, no declared value on-chain. §34's privacy boundary is respected. |
| **Deploy scripts run** | `Deploy.s.sol` and `DeploySystem.s.sol` execute and wire dependencies in the correct order (badge → leaderboard → escrow → `setMinter` → `setEscrowContract`). |
| **Chain-id guard in shell** | `TestScenarioSystem.sh` asserts `chain-id == 10143` before sending. Good practice worth keeping and extending. |

---

## 2. Missing or insufficient parts

### 2.1 Contract inventory — 6 of 12 required contracts do not exist

Against §32:

| Baseline contract | Status |
|---|---|
| `ProtocolConfig` | **Missing.** All parameters are `constant`; no bounded, versioned configuration. |
| `SettlementVault` | **Missing as a contract.** Escrow logic is inlined; no `claimable[]`, no pull-payment, no solvency invariant. |
| `CourierRegistry` | **Partial**, inlined as `isRegisteredCourier` + `courierStake`. No verification levels (C0/C1/C2), no suspension, no active-custody counter, no qualified-delivery counters. |
| `DeliveryHub` | **Partial** (`Delivera` / `DeliveryEscrow`). 5-state machine vs. the baseline's 12 states. |
| `ReputationRegistry` | **Partial** (`Leaderboard`). No score version, no confidence level, no 0–1000 scale; performs the on-chain sorting §22 forbids. |
| `DisputeCourt` | **Missing entirely.** No dispute, evidence, juror pool, commit/reveal, quorum, appeal or ruling. |
| `RandomnessAdapter` | **Missing entirely.** No `IRandomnessAdapter`, no Pyth Entropy. |
| `RewardDistributor` | **Partial.** See 2.5. |
| `BadgeSBT` | **Partial.** See 2.6. |
| `Treasury` | **Missing.** Treasury is a raw EOA address (the deployer, in both scripts). |
| `AccessManager` | **Missing.** A single mutable `address public owner` per contract, no roles, no timelock, no multisig. |
| `ISettlementAdapter` | **Missing.** The payment rail is hard-wired. |

Milestones **M2 (economic security), M3 (physical delivery proof/return), M5 (dispute)** are effectively unstarted on the contract side; M4 exists only as a leaderboard stub.

### 2.2 Custody safety — funds can be permanently locked (critical)

- **No cancellation or expiry path exists in either contract.** `Status.Cancelled` is declared in both enums and **never assigned anywhere** (verified by grep). If nobody bids, if the customer never accepts, if the courier never picks up, or if the customer never confirms delivery, the escrowed value is locked forever. **[PoC-A]** confirms 1 MON still trapped in `Delivera` after a simulated 10 years, with no function able to release it. This breaks §10 (*"no party can keep the other party's capital locked indefinitely"*) and §3.4's entire failure-first mandate.
- **`Delivera.sol` has no `withdrawStake` at all.** **[PoC-B]** confirms the selector does not exist. Every MON a courier stakes via `registerCourier` is unrecoverable.
- **`Delivera.registerCourier` reverts on `Already registered`**, so a courier whose stake has been drained by bid deposits can never top up and is permanently unable to bid.
- **`DeliveryEscrow.withdrawStake` has no exit path either**: `isRegisteredCourier` is set once and never cleared, so `stake - amount >= MIN_COURIER_STAKE` is permanent. A courier sitting at exactly the minimum can never withdraw anything.
- **A selected courier who abandons the job is never slashed** and their locked bid deposit is never released — it is simply stranded.

### 2.3 Settlement model contradicts §18.2 (critical)

Both contracts use **push payments** with `require(ok)`. A single reverting receiver — treasury, reward pool, or courier — bricks `confirmDelivery` permanently for that delivery. **[PoC-D]** confirms: with a reverting treasury, `confirmDelivery` reverts `"Treasury transfer failed"` and both the payment and the escrow are frozen with no recovery function.

This directly violates **invariant §33-11** and the §18.2 requirement for `claimable[] + claim()`.

### 2.4 No proof layer — §12 and §15 are entirely absent

- No EIP-712, no `ecrecover`, no `SignatureChecker`, no ERC-1271, no nonce, no expiry, no domain separator anywhere in `src/` (verified by grep).
- `pickupHash` / `deliveryHash` are **stored but never verified against anything**. They are inert bytes.
- `confirmPickup` is an unverified unilateral courier claim; `confirmDelivery` is an unverified unilateral customer claim.
- The walletless recipient OTP/QR → PoD attestation flow (§15) has no on-chain counterpart at all.
- **Invariants §33-7 and §33-8 (proof/quote replay) are untestable because no proofs exist.**

### 2.5 `RewardDistributor` — insufficient against §23

- **No per-epoch budget cap.** `claimReward` transfers against the contract's whole token balance. Any valid proof for any period can drain funds earmarked for another period. **Violates invariant §33-12** ("reward claims cannot exceed funded epoch budget").
- No funding/accounting function — the "budget" is whatever tokens happen to sit in the contract.
- No 90-day claim window, no 7-day reclaim delay, no reclaim function (§23, §48).
- `setMerkleRoot` can **overwrite an already-published root** for a period that has partial claims.
- `owner` cannot be transferred or renounced; no timelock.

### 2.6 `ReputationBadge` — not standards-compliant

- **Not ERC-721.** Missing `safeTransferFrom`, `approve`, `setApprovalForAll`, `getApproved`, `isApprovedForAll`, `supportsInterface`, `tokenURI`. Wallets and explorers will not render these badges.
- **Not ERC-5192** as §24 requires: no `locked(uint256)` view, no `Locked` event. Only `transferFrom` reverts — the other transfer entry points simply do not exist rather than being explicitly locked.
- No duplicate-mint prevention at the badge level; the guard lives in `Leaderboard` (`totalDeliveries == 1`).
- Only `FirstDelivery` is ever minted. `WeeklyChampion`, `MonthlyChampion`, `PerfectRating`, `RegionLord` are dead enum values, and none of §24's milestone/verification badges (10/50/100/500 deliveries, Verified/Trusted Courier, Zero Lost Dispute) exist.

### 2.7 Business-logic gaps vs. baseline

| Baseline requirement | Status in code |
|---|---|
| Risk tiers R1–R4, coverage %, required verification level (§6) | **Absent.** No risk concept at all. |
| `requiredCoverage` / `reservedBase` / `additionalBond` (§8.3) | **Absent.** Only a flat 1 MON / 0.001 MON bid deposit. |
| `MAX_ACTIVE_CUSTODY = 1` (§9) | **Absent.** Invariant §33-10 unenforced. |
| Two-sided `FundingSession` with 15-min deadline (§10) | **Absent.** Funding is a single customer transfer at creation. |
| `RETURN_REQUIRED` / `RETURNED` / `returnAsk` / return reserve (§17) | **Absent.** |
| 24-hour challenge window + permissionless finalizer (§16) | **Absent.** `confirmDelivery` settles instantly. |
| Bid `validUntil`, `returnAsk`, `termsVersion` (§7) | **Absent.** Bid holds only `amount` + `estimatedMinutes`. |
| Courier may update/withdraw an unselected bid (§7) | **Absent.** `require(bids[...].amount == 0, "Already bid")` makes a bid permanent. |
| Customer cannot select own wallet as courier (§33-16) | **Violated. [PoC-C]** confirms a customer can register as courier, bid on their own request, and accept themselves. |
| Accepted ETA vs. Live ETA (§13) | `estimatedMinutes` is **stored and never read**. On-time is judged against a hardcoded urgency constant, not the courier's own promise. |
| Customer reliability signals (§21) | **Absent.** |
| Referral system (§25) | **Absent.** |
| Reputation 0–1000 + confidence + versioning (§19) | **Absent.** Score is unbounded and grows +10 per delivery forever; no confidence, no version. |
| Emergency pause + safe exits (§45) | **Absent.** No pause anywhere. |

### 2.8 Parameters do not match §48

| §48 parameter | Baseline | Code |
|---|---|---|
| Protocol fee | 2% | **1%** (`PLATFORM_FEE_BPS = 100`), both contracts |
| Fee destination | Treasury (§18.1) | **50/50 split** treasury / rewardPool |
| Fee incidence | Customer pays *on top of* courier ask (§8.1) | **Deducted from the courier's ask** — courier bears it |
| Courier base deposit | 10 MON | `Delivera`: **0.01 MON**; `DeliveryEscrow`: 10e18 of a mock token, not MON |
| Coverage R1/R2/R3, max custody, funding window, challenge window, withdrawal cooldown, all juror params, listing cap, quote/PoD validity, reward claim/reclaim | 13 values | **All absent** |

### 2.9 ERC-20 token contradicts §23 and §49

`MCRYToken` is a hand-rolled ERC-20 that the baseline explicitly rules out: §23 — *"The protocol does not create a MONOSFER ERC-20 token"* — and §49 lists it as out of scope. It is also **named `"Delivera Token"` with symbol `"MON"`**, impersonating the native gas token, which is actively dangerous in a wallet UI. And it is hand-written rather than OpenZeppelin (§44).

### 2.10 Testing — far below §46/§47

- **5 tests total.** 3 happy paths, 2 negative access checks.
- **Zero fuzz tests, zero stateful invariant tests, zero adversarial tests** (verified: no `testFuzz`, no `invariant_`, no `StdInvariant`).
- **No `.gas-snapshot`** despite §44 requiring gas snapshots.
- **None of the 18 invariants in §33 are explicitly tested.** Two of them (§33-11, §33-16) are demonstrably violated.
- **None of the 22 failure scenarios in §47 are covered.**
- **CI never touches the contracts.** The only workflow, `.github/workflows/deploy.yml`, SSH-deploys the app on push to `main`. There is no `forge build`, no `forge test`, no `forge fmt --check`, no static analysis.

### 2.11 Deployment gaps

- Both scripts assign **treasury, reward pool, and every `owner` role to the single deployer EOA**, directly contradicting §32.11 (*"No single EOA should control critical production permissions"*) and §45.
- `Deploy.s.sol` passes `deployer` as both treasury *and* reward pool, so the 50/50 fee split is a no-op.
- No post-deploy assertions (e.g. verifying `badge.minter() == leaderboard`), no chain-id guard in the Solidity scripts, no address-artifact JSON emitted for downstream consumers, no `--verify` source verification step (§45).
- `contracts/README.md` §10.1 claims a real deploy record exists at `broadcast/DeploySystem.s.sol/10143/run-latest.json`, but **`broadcast/` is gitignored and absent** — the claim is not verifiable from the repository.

---

## 3. Parts that should be improved

Things that exist and function, but need rework before they satisfy the baseline.

1. **Collapse the two parallel systems.** `Delivera.sol` (native MON monolith) and the modular stack duplicate escrow, bidding, and reputation logic. The baseline specifies one architecture; maintaining both doubles the audit surface and guarantees drift. `Delivera.sol` is the closer starting point for a native-MON V1 (§32.12's `NativeMonSettlementAdapter`), but the *modular decomposition* is the correct target shape.

2. **Remove on-chain sorting.** `Delivera.getLeaderboard` bubble-sorts the unbounded `allCouriers` array in O(n²). **[PoC-F]** measures **28.5M gas at 301 couriers** — already past typical `eth_call` caps, and quadratic beyond that. §22 is explicit: *"The global ranking should not be sorted inside a smart contract."* `Leaderboard.getTopCouriers` is better (caller-supplied candidates) but still sorts on-chain. Both should be deleted in favour of event-driven indexer ranking.

3. **Bound the bidder loop.** `_refundNonSelectedBidDeposits` iterates an unbounded, user-grown array inside `acceptBid`. **[PoC-E]** measures **423k gas at 300 bidders**, growing ~1.1k gas per bidder. Because losing deposits are fully refunded, the only griefing cost is gas. §45 forbids unbounded user-controlled loops. Convert to a pull-based `claimBidDeposit()`.

4. **Add reentrancy protection and tighten CEI.** No `ReentrancyGuard` exists. `Delivera._releasePayment` sends MON to the courier via `.call` *before* clearing `lockedBidDeposits` and updating scores. I found no directly exploitable path today (status is set to `Delivered` first, and stake is credited after the call), but the ordering is fragile and §45 requires both a guard and CEI.

5. **Harden the low-level token calls.** `DeliveryEscrow._safeTransfer` / `_safeTransferFrom` accept `data.length == 0` as success. Since the constructor only checks `tokenAddress != address(0)` and never checks for code, a misconfigured token address makes every "transfer" silently succeed while moving nothing. Add an `extcodesize` check or use OpenZeppelin `SafeERC20`.

6. **Decouple badge minting from settlement.** `Leaderboard.recordDelivery` calls `badge.mint(...)` synchronously. If `setMinter` was never called or is later repointed, the mint reverts and **`confirmDelivery` reverts with it** — a cosmetic subsystem can brick financial settlement. Make the mint failure-tolerant (try/catch) or move it to a pull-claim.

7. **Governance on privileged setters.** `Leaderboard.setEscrowContract` and `ReputationBadge.setMinter` are single-EOA, instant, unbounded, and repeatable. An owner can repoint the escrow at a malicious contract and mint arbitrary reputation. §45 requires multisig plus delayed privileged configuration; §33-15 requires admin actions to stay inside configured bounds. Neither `owner` can even be transferred today.

8. **Replace string `require`s with custom errors.** ~60 string reverts across `src/`. Custom errors cut deploy and revert-path gas and give the frontend typed failures — directly supporting §40's requirement to distinguish stale quote / expired bid / insufficient collateral.

9. **Extend the event set for the indexer.** `Delivera` emits nothing for courier registration or stake changes, so §22/§23's indexer cannot reconstruct courier state from events alone. Also missing: `OwnershipTransferred`, bid update/withdrawal, and any configuration-change events (§34 lists "configuration events" as on-chain). `Delivera.PaymentReleased` omits the fee breakdown that `DeliveryEscrow`'s version includes — align them.

10. **Make timing parameters configurable.** `_expectedDuration` hardcodes 30 min / 1 h / 2 h in two places. These belong in `ProtocolConfig` as bounded, versioned values (§32.1).

11. **Adopt OpenZeppelin.** §44 names OZ as baseline. Replacing the hand-rolled ERC-20, ERC-721, `Ownable`, Merkle proof, and safe-transfer implementations removes five categories of bug from the audit surface at once.

---

## 4. Parts that should remain unchanged

Deliberate "do not touch" list, to avoid churn during the rework.

- **`foundry.toml`** — Solidity 0.8.24, optimizer, `via_ir`, `monad_testnet` alias. Correct; only re-check the Foundry version against §53's `>= 1.8.0` recommendation at implementation time.
- **The bid-deposit lock/release pattern** (`courierStake` → `lockedBidDeposits` → credit back). This is the correct primitive for §8.3's non-reusable collateral; the coverage model should be built *on top of* it, not instead of it.
- **The fee-remainder arithmetic** (`treasuryFee = platformFee - rewardFee`). Keep this rounding-safe form when the fee moves to 2% and to a `claimable[]` model.
- **The `onlyEscrow` / `onlyMinter` isolation pattern** in `Leaderboard` and `ReputationBadge`. The boundary is right; only the governance behind it needs upgrading.
- **The Merkle leaf construction** in `RewardDistributor` (double-hashed, sorted pairs). OZ-compatible and second-preimage safe — keep it when adding budget caps and expiry.
- **Hash-only on-chain storage** of pickup/delivery data. §34's privacy boundary is currently respected and must stay that way as the proof layer is added.
- **The existing 5 tests.** They are correct as happy-path regression anchors — extend the suite around them rather than rewriting them.
- **`TestScenarioSystem.sh`'s chain-id assertion.** Keep and replicate into the Solidity deploy scripts.
- **Existing event names/signatures already consumed by the indexer** (`DeliveryRequested`, `BidSubmitted`, `CourierSelected`, `PickupConfirmed`, `DeliveryConfirmed`, `PaymentReleased`, `RatingSubmitted`, `ScoreUpdated`). Extend with new fields via *new* events rather than silently changing these.

---

## 5. Prioritized contract development tasks

Ordered by the baseline's own §55 priority: correct custody → correct state machine → correct failure paths → reputation → disputes → incentives.

### P0 — Custody safety (nothing else ships until these are closed)

| # | Task | Baseline ref |
|---|---|---|
| 1 | Add cancellation + expiry paths that actually assign `Status.Cancelled`/`Expired` and refund escrow. No delivery may reach a state with no exit. | §10, §11, §3.4 |
| 2 | Convert all settlement to pull payments: `claimable[account] += amount` + `claim()`. Remove every `require(ok)` on an external value transfer. | §18.2, §33-11 |
| 3 | Add stake withdrawal to `Delivera` (or delete `Delivera` per P1-13), and a deregistration path in `DeliveryEscrow` so base stake is recoverable. | §8.2, §48 |
| 4 | Add `ReentrancyGuard` to every value-moving entry point and enforce CEI in `_releasePayment`. | §45 |
| 5 | Reject `selectedCourier == req.customer` in `acceptBid`. | §33-16 |
| 6 | Add emergency pause with safe user exit while paused. | §45 |
| 7 | Convert `_refundNonSelectedBidDeposits` to a pull `claimBidDeposit()`; delete the unbounded loop from `acceptBid`. | §45, §33-11 |

### P1 — Architecture and governance

| # | Task | Baseline ref |
|---|---|---|
| 8 | Introduce `ProtocolConfig` with bounded, versioned parameters; move every constant into it (fee → 2%, base deposit → 10 MON, all §48 windows). | §32.1, §48 |
| 9 | Introduce `AccessManager` + multisig ownership + timelock on `setEscrowContract`, `setMinter`, `setMerkleRoot`, and all config setters. Add `OwnershipTransferred`. | §32.11, §45, §33-15 |
| 10 | Split `SettlementVault` out of the hub; assert `vaultBalance >= totalRecordedLiabilities` as a stateful invariant. | §32.2, §33-1 |
| 11 | Split `CourierRegistry` out: verification levels C0/C1/C2, suspension, `activeCustody` counter enforcing `MAX_ACTIVE_CUSTODY = 1`, qualified-delivery counters. | §32.3, §9, §33-10 |
| 12 | Delete `MCRYToken` and settle in native MON behind `ISettlementAdapter` / `NativeMonSettlementAdapter`. | §23, §32.12, §49 |
| 13 | Retire `Delivera.sol` as a second parallel system; keep exactly one lifecycle contract. | §32.4 |

### P2 — State machine and proofs

| # | Task | Baseline ref |
|---|---|---|
| 14 | Implement the full 12-state machine (`BIDDING → AWAITING_FUNDING → READY_FOR_PICKUP → IN_TRANSIT → DELIVERED_PENDING → COMPLETED`, plus `RETURN_REQUIRED/RETURNED/DISPUTED/RESOLVED/CANCELLED/EXPIRED`). | §11 |
| 15 | Implement `FundingSession`: two independent obligations, 15-min deadline, one-sided release on expiry. | §10 |
| 16 | Implement risk tiers R1–R3 with coverage %, `requiredCoverage` / `reservedBase` / `additionalBond`, and signed, expiring coverage quotes. | §6, §8.3, §33-8, §33-9 |
| 17 | Implement EIP-712 `PickupAcceptance` with nonce, expiry, chainId, verifyingContract, and `SignatureChecker`/ERC-1271 support. | §12, §33-7 |
| 18 | Implement the PoD attestation check (signer-based, 10-min max lifetime) for the walletless recipient flow. | §15 |
| 19 | Implement the 24-hour challenge window plus the permissionless finalizer. | §16 |
| 20 | Implement the return flow: `returnAsk`, pre-funded return reserve, return proof, `RETURNED`. | §17 |
| 21 | Extend `Bid` with `validUntil`, `returnAsk`, `termsVersion`; allow update/withdrawal of unselected bids; evaluate on-time against the courier's own accepted ETA. | §7, §13 |

### P3 — Testing and CI (run in parallel with P0–P2, not after)

| # | Task | Baseline ref |
|---|---|---|
| 22 | Add a CI workflow running `forge build`, `forge test`, `forge fmt --check`, and static analysis on every PR. Contracts are currently never built in CI. | §44, §45 |
| 23 | Write a stateful invariant suite covering all 18 invariants in §33. | §33, §46 |
| 24 | Write the 22 failure tests enumerated in §47. | §47 |
| 25 | Add fuzz tests for fee arithmetic, coverage math, and stake/bond accounting; commit a `.gas-snapshot`. | §44, §46 |

### P4 — Reputation and incentives

| # | Task | Baseline ref |
|---|---|---|
| 26 | Rebuild reputation as a 0–1000 versioned score with a separate confidence level and the §19 weight table. Delete all on-chain sorting. | §19, §22, §32.5 |
| 27 | Add per-epoch funded budget caps, a 90-day claim window, and a 7-day reclaim delay to `RewardDistributor`; block root overwrites on periods with claims. | §23, §33-12 |
| 28 | Make `ReputationBadge` a real ERC-721 + ERC-5192 (`locked()`, `Locked`, `supportsInterface`, `tokenURI`), with duplicate-mint prevention and the §24 badge set. Decouple minting from settlement. | §24 |
| 29 | Implement the referral system with one-referrer-per-wallet, self-referral and cycle rejection, and failure isolation from settlement. | §25 |

### P5 — Dispute system (largest single gap; blocks M5 and §51)

| # | Task | Baseline ref |
|---|---|---|
| 30 | Implement `DisputeCourt`: creation, evidence commitment, juror eligibility/stake, draw, commit/reveal, quorum, appeals (3→5→7), bounded ruling codes, final settlement exactly once. | §26–§30, §32.6 |
| 31 | Implement `IRandomnessAdapter` + `PythEntropyAdapter` with dynamic fee query, pass-through fee, and a callback that only records randomness. No blockhash fallback. | §29, §32.7, §33-18 |
| 32 | Implement the 3-of-5 Safe committee EIP-1271 fallback, restricted to bounded ruling codes. | §31 |
| 33 | Ensure a disputed delivery can never settle through the normal success path. | §33-5 |

### P6 — Deployment hardening

| # | Task | Baseline ref |
|---|---|---|
| 34 | Rewrite deploy scripts: separate treasury/reward/owner addresses, multisig owners, chain-id assertion, post-deploy invariant assertions, emitted address artifact, `--verify` source verification. | §32.11, §45 |
| 35 | Correct `contracts/README.md` §10.1 — either commit the deploy record or drop the unverifiable claim. Update its §12 "Known Limits" to reflect the real gap list. | — |

---

## Summary

The contracts are a **working hackathon MVP of the happy path**, not an implementation of this baseline. The end-to-end flow compiles, deploys and passes its 5 tests, and a handful of primitives (bid-deposit locking, fee arithmetic, privilege isolation, the off-chain data boundary) are genuinely correct and worth keeping.

But measured against the baseline: **6 of 12 required contracts do not exist**, the entire proof/coverage/dispute layer is absent, **2 of the 18 core invariants are demonstrably violated** (§33-11 and §33-16, both reproduced), and **escrowed funds can be permanently locked through at least four ordinary, non-adversarial paths** — no bid, no acceptance, no pickup, no confirmation. Contracts are never built or tested in CI.

The single most urgent item is **P0**: today, a customer who creates a delivery that nobody bids on has permanently lost their MON, and a courier who stakes into `Delivera` can never get it back.
