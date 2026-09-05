# MONOSFER — Smart Contract Implementation Plan

> **Target branch:** `Monosfer-V2`
> **Inputs:** `MONOSFER_Initial_Release_Base_Documentation_v1.0.md` (baseline), `MONOSFER_Contract_Analysis_vs_Baseline_v1.0.md` (gap analysis), current `contracts/` source
> **Status:** Plan only — no code written, no branch created, no P0 started. Awaiting approval on §7.
> **Date:** 5 September 2026

---

## 1. Verified branch state

Confirmed after `git fetch origin --prune`:

| Fact | Value |
|---|---|
| Current checkout | `main` @ `1139d8f` — **unchanged, will not be touched** |
| `origin/Monosfer-V2` | `fa8a884` "feat: consolidate dashboard/map duplication, add SSR fetching, PWA, and wagmi wallet" |
| Local `Monosfer-V2` branch | **Does not exist.** Only the remote tracking ref. |
| Divergence `main...origin/Monosfer-V2` | `0  3` — V2 is **3 commits ahead, 0 behind** |
| `git diff main origin/Monosfer-V2 -- contracts` | **Empty** — contracts byte-identical on both branches |

Two consequences that shape this plan:

1. **V2 is a strict superset of `main`.** No rebase-from-main, no back-merge, and no conflict risk from `main` during this work. `main` stays frozen.
2. **All contract work on V2 starts from the same code analysed in the gap report.** Every finding carries over unchanged.

Local setup required before any work (not yet executed):

```bash
git fetch origin --prune && git checkout -b Monosfer-V2 origin/Monosfer-V2
```

---

## 2. Current frontend/backend coupling (measured, not assumed)

This determines how disruptive contract changes actually are:

- **No ABI is imported anywhere.** Grep for `abi` across `frontend/app` and `backend/src` on V2 returns only incidental Turkish text matches. Neither app decodes contract calls today.
- **The backend never touches the chain.** `backend/src` has no `ethers`/`viem`/`web3` usage; it is a plain REST service over its own store, written in **plain JavaScript** (not TypeScript).
- **Addresses already have three conflicting sources of truth:**
  - `frontend/app/config/chain.ts` — hardcoded literals for the 5 modular contracts,
  - `frontend/.env` — `VITE_DELIVERA_ADDRESS`, a **different** address for the `Delivera` monolith,
  - `contracts/README.md` §9 — a third copy.
- **Partial automation already exists:** `scripts/deploy-monad-testnet.mjs` + `scripts/deploy-record.mjs` run `forge script`, parse `broadcast/.../run-latest.json`, write `contracts/deployments/monad-testnet.json`, and patch `frontend/.env`. It is limited to **one contract (`Delivera`), one hardcoded chain (10143), address only** — no ABI, no events, no errors, no types. `contracts/deployments/` is **not committed** to the repo.

**Implication:** the contract rewrite has a very small blast radius on the apps right now, and the artifact-sharing layer (§6) is effectively greenfield. Both are strong arguments for building it correctly before the frontend starts making real contract calls.

---

## 3. Foundational strategy decision

The baseline states in its own preamble: *"V1 / Initial Release means the first version that will be built from scratch. It does not refer to any previous MONOSFER implementation."*

That conflicts with patching `Delivera.sol` in place. Three options:

| Option | Approach | Assessment |
|---|---|---|
| **A. Remediate in place** | Fix `Delivera` + `DeliveryEscrow` custody bugs, then grow them toward §32 | P0 effort on `Delivera` is thrown away at P1-13 ("retire the second parallel system"). Doubles review surface for months. |
| **B. Freeze + build additively** ✅ | Move current contracts to `contracts/src/legacy/` untouched; build the §32 contract set under `contracts/src/v1/`; single cut-over at the end | Doc-aligned. Every merge is additive and non-breaking. Legacy stays deployable for the existing demo. Correct custody is *designed in*, not patched on. |
| **C. Hard greenfield** | Delete legacy immediately, new repo layout | Loses the working demo and the 5 passing regression tests during a months-long build. |

**Recommended: Option B.** It is the only option where every intermediate merge into `Monosfer-V2` leaves the branch working, and it honours the baseline's "from scratch" instruction without discarding the existing demo or its regression value.

**Consequence for P0:** the gap report's P0 list (pull payments, cancellation, stake withdrawal, reentrancy, self-dealing, pause) is **not retrofitted onto `Delivera`**. It becomes the design contract for the new `v1/` code, enforced from day one by invariant tests. The 8 verified-correct primitives listed in the gap report §4 are harvested into `v1/`, not rewritten.

> ⚠️ **Legacy funds are unrecoverable.** The already-deployed testnet `Delivera` is immutable and has no cancel/withdraw path. Funds currently stranded there stay stranded. Option B does not fix this; nothing can. Action required is documentation + pointing the frontend away from it (Decision **D9**).

---

## 4. Branch strategy

### 4.1 Comparison

| | **A. Direct commits on `Monosfer-V2`** | **B. Feature branch per step → PR → `Monosfer-V2`** ✅ | **C. Long-lived `contracts/v1` integration branch** |
|---|---|---|---|
| Review gate | None | One PR per step, CI-gated | Two hops, review at both |
| Blast radius of a bad commit | Whole shared branch; frontend work stalls | Isolated to the feature branch | Isolated, but drift accumulates |
| Bisectability | Poor — mixed contract/frontend history | Good — one squashed commit per step | Good |
| Conflict risk with frontend work | Low (disjoint dirs) but branch instability is shared | None | None |
| Rollback | `revert` on a shared branch | Revert one squash commit | Revert a merge commit |
| Overhead | Lowest | Low | Highest — extra merge hop, periodic sync |

**Why not C:** its main benefit is isolating a breaking rewrite from an active branch. Under Option B (§3) the contract work is **additive** (`src/v1/` alongside `src/legacy/`) and lives in a directory the frontend never touches, so file-level conflict risk with frontend work is already ~zero. The second merge hop buys nothing and adds drift.

**Why not A:** contract work spans many phases and touches custody logic. A shared branch with no review gate is how an unreviewed custody bug reaches the deployed demo.

### 4.2 Recommended workflow

```
main                      ← FROZEN. Never touched during this work.
  └── Monosfer-V2         ← integration branch. Protected. No direct pushes.
        ├── feat/contracts-p0.1-ci-harness      → PR → squash-merge
        ├── feat/contracts-p0.2-access-config   → PR → squash-merge
        ├── feat/contracts-p0.3-settlement-vault→ PR → squash-merge
        └── ...one branch per numbered step
```

Rules:

- **Branch naming:** `feat/contracts-<phase>.<step>-<slug>`, always cut fresh from the latest `Monosfer-V2`.
- **Commits:** conventional commits, logically separated *within* a step — `feat(contracts):` for source, `test(contracts):` for tests, `docs(contracts):` for documentation. Never mix a contract change and its test into one unreviewable commit.
- **Review:** one PR per numbered step. Merge blocked until CI is green (build, test, `forge fmt --check`, gas-snapshot diff, static analysis) **and** the step's acceptance criteria in §5 are checked off in the PR body.
- **Merge:** squash-merge into `Monosfer-V2` so each step is one revertible commit. Delete the feature branch after merge.
- **`main`:** receives nothing until the full V1 contract set is complete, then a single `Monosfer-V2 → main` PR — a separate decision (**D10**), not part of this plan.
- **Cut-over step (P5.3)** is the only step that removes `src/legacy/` and repoints the apps. It merges last, behind its own approval.

### 4.3 Definition of Done — applied to every step

No step is complete, and no next step begins, until all of these pass:

1. **Build** — `forge build` clean, zero new warnings.
2. **Test** — full suite green, including every pre-existing test (regression protection below).
3. **Review** — PR reviewed and approved; acceptance criteria checked off.
4. **Document** — `contracts/README.md` and the affected sections of this plan updated in the *same* PR.

**Regression protection policy:** the 5 existing tests (`Delivera.t.sol`, `DeliveryEscrow.t.sol`) are moved to `test/legacy/` in step P0.1 and **must keep passing unmodified through every subsequent step** until the P5.3 cut-over formally retires them. Any change that requires editing an existing test is a red flag to be justified in the PR, not silently absorbed. Each phase additionally adds its own tests to a growing suite that later phases must not break.

---

## 5. Implementation phases

Dependency graph (a phase may not start until its predecessors merge):

```
P0 foundation ──► P1 lifecycle ──► P2 proofs ──► P5 hardening
      │                │                            ▲
      │                └──────► P3 reputation ──────┤
      └───────────────────────► P4 dispute ─────────┘
                                (needs P1 + P3)
```

---

### **P0 — Safety foundation**
*Goal: a custody substrate that is correct by construction, plus the harness that proves it stays correct.*

---

#### P0.1 — CI, regression harness, and gas baseline

| | |
|---|---|
| **Problem** | Contracts are never built or tested in CI (the only workflow SSH-deploys the app). No gas snapshot. Nothing prevents a future step from silently breaking working behavior. This must exist *before* any code change. |
| **Files** | `.github/workflows/contracts.yml` (new); `contracts/test/legacy/{Delivera,DeliveryEscrow}.t.sol` (moved); `contracts/.gas-snapshot` (new); `contracts/foundry.toml`; `contracts/README.md` |
| **Changes** | Add CI job: `forge build`, `forge test`, `forge fmt --check`, `forge snapshot --check`, static analysis (Slither). Move existing tests to `test/legacy/` **without editing their contents**. Commit the first `.gas-snapshot`. Add `[profile.ci]` with higher fuzz runs. Note: root `contracts:test` script uses `--offline`; CI must not. |
| **Depends / Risks** | None — this is the root. Risk: Slither noise on legacy code; mitigate by baselining legacy findings as accepted, failing only on *new* findings. |
| **Tests** | *Unit:* existing 5 must pass unmodified. *Fuzz/Invariant:* n/a. *Integration:* CI green on a throwaway PR. *Deploy:* `forge script --dry-run` for both legacy scripts. |
| **Acceptance** | ☐ CI runs on every PR touching `contracts/` ☐ 5 legacy tests pass ☐ `.gas-snapshot` committed ☐ CI fails on an intentionally broken test (verified once) |
| **Docs** | `contracts/README.md`: CI section, how to run/update snapshots. |
| **FE/BE impact** | None. |

---

#### P0.2 — `AccessManager` + `ProtocolConfig`

| | |
|---|---|
| **Problem** | Every privileged setter is an instant, unbounded, single-EOA `owner` with no transfer, no timelock, no pause (baseline §32.11, §45; invariant §33-15). Every parameter is a hardcoded `constant` — no bounded, versioned config (§32.1). Everything downstream depends on these. |
| **Files** | `contracts/src/v1/access/AccessManager.sol`, `contracts/src/v1/config/ProtocolConfig.sol`, `contracts/src/v1/base/Pausable*.sol` (new); `contracts/lib/openzeppelin-contracts` (new submodule); `contracts/foundry.toml` (remappings) |
| **Changes** | Add OpenZeppelin as a submodule (§44). Roles: `CONFIG_ADMIN`, `EMERGENCY`, `SIGNER_ADMIN`, `TREASURER`. Timelock on config changes; `EMERGENCY` pause is immediate (pause must be fast, unpause must be delayed). `ProtocolConfig` holds every §48 value with **compile-time enforced min/max bounds** and a monotonic `configVersion`. Every setter emits an event (§34 "configuration events"). |
| **Depends / Risks** | P0.1. Risk: over-engineering governance before a Safe exists — mitigate by shipping the role structure now and deferring Safe wiring to deployment config (**D5**). Risk: a bad bound bricks config; mitigate with fuzz tests over the full parameter space. |
| **Tests** | *Unit:* each role gates the right functions; timelock delay enforced; pause blocks/unblocks. *Fuzz:* no reachable value escapes declared bounds. *Invariant:* `configVersion` strictly monotonic; no role escalates itself. *Integration:* pause propagates to a mock consumer. *Deploy:* script wires roles to distinct addresses and asserts no EOA holds two critical roles. |
| **Acceptance** | ☐ Invariant §33-15 test passes ☐ No single address holds `CONFIG_ADMIN` + `EMERGENCY` in deploy output ☐ All 13 §48 parameters present and bounded ☐ Ownership transfer is two-step |
| **Docs** | New `contracts/docs/governance.md`: role matrix, timelock durations, pause runbook. |
| **FE/BE impact** | Backend: none yet. Frontend: none yet. Both will later read `ProtocolConfig` for §40 fee/lock disclosures — **plan the read path now, build in P1.** |

---

#### P0.3 — `SettlementVault` (pull payments + solvency)

| | |
|---|---|
| **Problem** | Push payments with `require(ok)` let one reverting receiver permanently brick settlement — **reproduced in the gap report [PoC-D]**, violating invariant §33-11 and §18.2. There is no vault, no `claimable[]`, and no solvency accounting (§32.2, §33-1). |
| **Files** | `contracts/src/v1/vault/SettlementVault.sol`, `contracts/src/v1/interfaces/ISettlementAdapter.sol`, `contracts/src/v1/adapters/NativeMonSettlementAdapter.sol` (new) |
| **Changes** | `claimable[account] += amount` + permissionless `claim()`. **Zero `require(ok)` on any outbound value transfer.** Track `totalRecordedLiabilities`; assert `address(this).balance >= totalRecordedLiabilities` on every mutation. `ReentrancyGuard` + strict CEI on all entry points. Route settlement through `ISettlementAdapter` (§32.12) so the rail is swappable. |
| **Depends / Risks** | P0.2. Risk: this is the single most security-critical contract — it gets the heaviest invariant suite and an explicit external review gate before P1 starts (**D6**). |
| **Tests** | *Unit:* claim, double-claim rejection, zero-balance claim. *Fuzz:* random deposit/credit/claim sequences never break solvency. *Invariant:* §33-1 solvency, §33-3 value conservation — **stateful, with a reverting-receiver actor in the handler**. *Integration:* reverting receiver is credited and cannot block any other party's settlement (§33-11). *Deploy:* vault deploys with zero liabilities and zero balance. |
| **Acceptance** | ☐ [PoC-D] scenario now passes instead of reverting ☐ Solvency invariant survives 10k+ stateful runs ☐ No `require` on a value-transfer return value anywhere in `v1/` (grep-enforced in CI) |
| **Docs** | `contracts/docs/settlement.md`: pull-payment model, why receivers cannot block, claim UX contract. |
| **FE/BE impact** | **Frontend: new mandatory `claim()` screen.** Money no longer arrives automatically — this is a user-visible product change and must reach the frontend backlog now. Backend: index `Claimable`/`Claimed` events for balance display. |

---

#### P0.4 — `CourierRegistry`

| | |
|---|---|
| **Problem** | `Delivera` has no `withdrawStake` at all — stake is unrecoverable **[PoC-B]**. `DeliveryEscrow` sets `isRegisteredCourier` permanently, so a courier at the minimum can never exit. No verification levels, no suspension, no custody counter (§32.3, §9, invariant §33-10). |
| **Files** | `contracts/src/v1/registry/CourierRegistry.sol` (new) |
| **Changes** | Deposit / withdraw / **deregister-and-exit** with the §48 24h withdrawal cooldown. Verification levels C0/C1/C2 (§4.3–4.5) with off-chain-attested promotion. Suspension. `activeCustody` counter enforcing `MAX_ACTIVE_CUSTODY = 1`. Qualified-delivery counters. Preserve the one primitive the legacy code got right: stake → locked-reservation accounting so the same collateral can never back two deliveries (§8.3). |
| **Depends / Risks** | P0.2, P0.3. Risk: cooldown interacting with an active delivery could strand a courier; explicitly test withdraw-during-active-delivery. |
| **Tests** | *Unit:* full deposit→lock→release→cooldown→withdraw→deregister cycle. *Fuzz:* stake accounting never goes negative or double-credits. *Invariant:* §33-4 collateral never reused; §33-10 custody limit never exceeded. *Integration:* courier can always fully exit given no active delivery — **the direct fix for [PoC-B]**. *Deploy:* registry wired to config + vault. |
| **Acceptance** | ☐ Every courier has a terminating exit path ☐ §33-4 and §33-10 invariants pass ☐ Cooldown matches `ProtocolConfig`, not a constant |
| **Docs** | `contracts/docs/courier-lifecycle.md`. |
| **FE/BE impact** | Frontend: courier activation screen gains verification level + cooldown countdown + exit flow. Backend: owns C1/C2 verification attestation — **new backend responsibility, needs its own spec.** |

---

### **P1 — Delivery lifecycle**
*Goal: the full state machine with no state lacking an exit.*

---

#### P1.1 — `DeliveryHub` state machine + bidding

| | |
|---|---|
| **Problem** | 5 states vs the baseline's 12 (§11). `Status.Cancelled` is declared and **never assigned anywhere** — no bid, no acceptance, no pickup or no confirmation strands funds forever **[PoC-A]**. Bids are permanent (`"Already bid"`), lack `validUntil`/`returnAsk`/`termsVersion` (§7), and a customer can accept themselves **[PoC-C]**, violating §33-16. |
| **Files** | `contracts/src/v1/hub/DeliveryHub.sol`, `contracts/src/v1/hub/DeliveryTypes.sol` (new) |
| **Changes** | Full 12-state machine with an explicit transition table. **Every non-terminal state gets a timeout exit.** Bid struct gains `validUntil`, `returnAsk`, `termsVersion`; add update/withdraw for unselected bids. Reject `selectedCourier == customer`. Selected terms become immutable. Enforce the §48 customer active-listing cap of 5. Replace the unbounded `_refundNonSelectedBidDeposits` loop with pull-based `claimBidDeposit()` (§45). |
| **Depends / Risks** | P0.2–P0.4. Risk: the transition table is the highest-complexity artifact in the project — build it as data, not nested `if`s, so an invariant test can enumerate every (state, action) pair. |
| **Tests** | *Unit:* every legal transition; every illegal transition reverts. *Fuzz:* random action sequences never reach an undefined state. *Invariant:* §33-2 settles once, §33-6 terminal never reopens, **and a new "no state without an exit" invariant** — the direct fix for [PoC-A]. *Integration:* full happy path mirroring the legacy regression test. *Deploy:* hub wired to vault/registry/config. |
| **Acceptance** | ☐ [PoC-A] and [PoC-C] scenarios both now fail to strand funds / are rejected ☐ Every non-terminal state provably reachable to a terminal state ☐ No unbounded loop in any state-changing function (CI-enforced) |
| **Docs** | `contracts/docs/state-machine.md` with the transition table + diagram. |
| **FE/BE impact** | **Large.** Frontend state model goes 5 → 12 states; every status badge, guard and route changes. Backend projection schema and indexer must be rewritten against the new event set. Both need the transition table as a shared artifact — see §6. |

---

#### P1.2 — `FundingSession` (two-sided funding)

| | |
|---|---|
| **Problem** | §10's two independent funding obligations with a 15-minute deadline do not exist; funding is a single customer transfer at creation. Neither side can currently be released if the other defaults. |
| **Files** | `contracts/src/v1/hub/FundingSession.sol`; `DeliveryHub.sol`; `SettlementVault.sol` |
| **Changes** | On bid selection open a bounded session. Customer locks ask + protocol fee + return reserve; courier locks reserved base + additional bond. `READY_FOR_PICKUP` only when both complete. On deadline expiry the completed side is released via `claimable[]` — never stranded. |
| **Depends / Risks** | P1.1. Risk: the both-sides-fund-simultaneously race; test with adversarial ordering including same-block completion. |
| **Tests** | *Unit:* each side funds/defaults independently. *Fuzz:* random timing around the deadline. *Invariant:* neither party's capital is ever locked past the deadline (§10). *Integration:* customer-funds-courier-doesn't and the reverse — both §47 scenarios. *Deploy:* funding window read from `ProtocolConfig`. |
| **Acceptance** | ☐ Both §47 default scenarios refund correctly ☐ No path reaches `READY_FOR_PICKUP` with one side unfunded ☐ Window is config-driven |
| **Docs** | `contracts/docs/funding.md` with the timing diagram. |
| **FE/BE impact** | Frontend: new dual-progress funding screen with countdown; §40 disclosure of exactly what is locked. Backend: funding-required and funding-expiry notifications (§41). |

---

#### P1.3 — Risk tiers, coverage, and signed quotes

| | |
|---|---|
| **Problem** | No risk concept exists at all — no R1–R3 tiers, no coverage %, no `requiredCoverage`/`reservedBase`/`additionalBond` (§6, §8.3). Invariants §33-8 and §33-9 are currently untestable. |
| **Files** | `contracts/src/v1/risk/CoverageQuote.sol`; `ProtocolConfig.sol`; `DeliveryHub.sol`; `CourierRegistry.sol` |
| **Changes** | R1/R2/R3 tiers with per-tier coverage % and required verification level (R4 stays disabled per §49). Coverage math per §8.3 with a **bounded** reputation multiplier. Backend-signed, expiring coverage quotes (§48: 5-minute validity) with nonce-based replay protection. Enforce required collateral present at pickup. |
| **Depends / Risks** | P1.1, P1.2, P0.4. Risk: introduces a **trusted off-chain signer** into the custody path — key rotation and compromise behavior must be specified (**D7**). Risk: multiplier bounds are economic guesswork on testnet; make them config-bounded and reviewable. |
| **Tests** | *Unit:* each tier's coverage; verification gating. *Fuzz:* coverage math never underflows or exceeds bounds for any declared value. *Invariant:* §33-8 quote replay impossible, §33-9 collateral present at pickup. *Integration:* forged signer and expired quote both rejected (§47). *Deploy:* signer address set via `SIGNER_ADMIN`, rotatable. |
| **Acceptance** | ☐ Forged/expired/replayed quotes all rejected ☐ Coverage matches §6 table exactly ☐ Signer rotation works without redeploy |
| **Docs** | `contracts/docs/risk-coverage.md`; signer key runbook. |
| **FE/BE impact** | **Backend: major new responsibility** — the risk quote service and its signing key. Frontend: must display Declared Value / Protected Amount / Coverage % as three distinct fields (§6 requirement) and handle stale-quote errors (§40). |

---

### **P2 — Proofs and physical delivery**

---

#### P2.1 — EIP-712 pickup proof

| | |
|---|---|
| **Problem** | `pickupHash`/`deliveryHash` are stored but **never verified against anything** — inert bytes. `confirmPickup` is an unverified unilateral claim. No EIP-712, nonce, expiry or ERC-1271 anywhere (§12, invariant §33-7). |
| **Files** | `contracts/src/v1/proof/PickupProof.sol`; `DeliveryHub.sol` |
| **Changes** | EIP-712 `PickupAcceptance` binding deliveryId, courier, action, nonce, expiry, chainId, verifyingContract. Enforce **all** of: nonce uniqueness, expiry, correct delivery/action/courier/signer (§12 is explicit that domain separation alone is insufficient). Use OZ `SignatureChecker` for EOA + ERC-1271 smart accounts. Successful pickup moves straight to `IN_TRANSIT` (§11 — no extra transaction). |
| **Depends / Risks** | P1.1–P1.3. Risk: signature malleability and cross-delivery replay; covered by dedicated adversarial tests. |
| **Tests** | *Unit:* valid signature accepted; each of the 6 required checks rejected independently. *Fuzz:* random signature bytes never validate. *Invariant:* §33-7 nonce never reusable. *Integration:* ERC-1271 smart-account signer; pickup-proof replay across deliveries (§47). *Deploy:* domain separator matches deployed chainId + address. |
| **Acceptance** | ☐ All 6 §12 checks independently enforced ☐ Replay impossible across deliveries, couriers and chains ☐ ERC-1271 accounts work |
| **Docs** | `contracts/docs/proofs.md` with the typed-data schema. |
| **FE/BE impact** | Frontend: EIP-712 signing UX at pickup (§40 plain-language disclosure). Backend: must expose the typed-data payload builder; chainId/verifyingContract must come from the shared manifest (§6). |

---

#### P2.2 — PoD attestation (walletless recipient)

| | |
|---|---|
| **Problem** | §15's walletless OTP/QR → signed attestation → on-chain validation flow has no on-chain counterpart. A recipient without a wallet cannot prove delivery. |
| **Files** | `contracts/src/v1/proof/DeliveryProof.sol`; `DeliveryHub.sol` |
| **Changes** | Validate a backend-signed typed attestation binding deliveryId, courier, proof type, challenge hash, nonce, issue time, expiry. §48 max lifetime 10 minutes. **No plaintext OTP ever on-chain.** Optional recipient-wallet signature path when a wallet exists. |
| **Depends / Risks** | P2.1. Risk: the attestation signer becomes a single point of trust for delivery confirmation — shares the rotation/compromise policy from P1.3 (**D7**). |
| **Tests** | *Unit:* valid attestation; expired; wrong courier; wrong delivery. *Fuzz:* random challenge hashes never validate. *Invariant:* attestation nonce single-use. *Integration:* OTP replay and OTP guessing (§47). *Deploy:* attestation signer distinct from the quote signer. |
| **Acceptance** | ☐ No OTP material on-chain ☐ 10-minute lifetime enforced ☐ Replay rejected ☐ Signer independently rotatable |
| **Docs** | `contracts/docs/proofs.md` (PoD section). |
| **FE/BE impact** | **Backend: PoD attestation service** — new signing key, OTP/QR issuance and validation. Frontend: recipient handoff screen. |

---

#### P2.3 — Challenge window and permissionless finalization

| | |
|---|---|
| **Problem** | `confirmDelivery` settles instantly. §16's `DELIVERED_PENDING` + 24-hour challenge window + permissionless finalizer does not exist, so there is no window in which a dispute can pre-empt settlement. |
| **Files** | `DeliveryHub.sol`; `SettlementVault.sol` |
| **Changes** | Recipient proof → `DELIVERED_PENDING`. Customer may confirm early. After the §48 24h deadline **anyone** may call the finalizer. Courier collateral stays locked until the window closes or explicit irreversible confirmation. Valid dispute before completion → `DISPUTED`. |
| **Depends / Risks** | P2.2. Risk: the dispute-vs-timeout race (§47) — the finalizer and dispute opener must be mutually exclusive under same-block ordering. |
| **Tests** | *Unit:* early confirm; timeout finalize; dispute blocks finalize. *Fuzz:* random timing around the deadline boundary. *Invariant:* §33-5 disputed delivery never settles via the success path. *Integration:* dispute/timeout race with adversarial ordering (§47). *Deploy:* window config-driven. |
| **Acceptance** | ☐ Race resolved deterministically ☐ Anyone can finalize after the deadline ☐ Collateral release timing matches §16 |
| **Docs** | `contracts/docs/state-machine.md` update. |
| **FE/BE impact** | Frontend: challenge-window countdown, "confirm early" action. Backend: finalizer keeper job + §41 challenge-window notification. |

---

#### P2.4 — Return flow

| | |
|---|---|
| **Problem** | §17's failed-delivery return path is entirely absent — `RETURN_REQUIRED`/`RETURNED`, `returnAsk`, the pre-funded return reserve and return proof. Today a recipient-unavailable delivery has nowhere to go. |
| **Files** | `DeliveryHub.sol`; `SettlementVault.sol` |
| **Changes** | `IN_TRANSIT → RETURN_REQUIRED → RETURNED` with return proof. Pay `returnAsk` from the pre-funded reserve **only** on valid return conditions + proof. Release unused reserve to the customer. Post-custody pickup must not use a unilateral cancellation path (§17). |
| **Depends / Risks** | P1.2 (reserve funded there), P2.2 (proof mechanism). Risk: return fee paid on an invalid return; gate strictly on proof. |
| **Tests** | *Unit:* valid return pays; invalid return does not. *Fuzz:* reserve accounting exact for random asks. *Invariant:* value conservation across the return path. *Integration:* recipient-unavailable and failed-return (§47). *Deploy:* n/a. |
| **Acceptance** | ☐ Unused reserve always returns to customer ☐ Return fee impossible without valid proof ☐ No unilateral cancel after custody |
| **Docs** | `contracts/docs/state-machine.md` (return branch). |
| **FE/BE impact** | Frontend: courier return flow + customer return status. Backend: return-required notification. |

---

### **P3 — Reputation and incentives**

---

#### P3.1 — `ReputationRegistry`

| | |
|---|---|
| **Problem** | Score is unbounded (+10/delivery forever), has no confidence level, no version, and is not on the §19 0–1000 scale. Worse, `getLeaderboard` bubble-sorts unbounded storage on-chain — **28.5M gas at 301 couriers, quadratic** — which §22 explicitly forbids. |
| **Files** | `contracts/src/v1/reputation/ReputationRegistry.sol` (new); legacy `Leaderboard.sol` untouched in `legacy/` |
| **Changes** | 0–1000 score with the §19 weight table; separate confidence level so a new courier cannot match a veteran on 100% success. Versioned algorithm. Terminal-outcome counters, rating aggregates, dispute/cancellation history. **No sorting of any kind on-chain** — ranking is indexer-derived (§22). Judge on-time against the courier's own accepted ETA, not a hardcoded constant (§13). |
| **Depends / Risks** | P1.1, P2.3. Risk: score formula churn — version it from day one so history stays interpretable. |
| **Tests** | *Unit:* each §19 component. *Fuzz:* score always within 0–1000 for any input history. *Invariant:* score monotonic w.r.t. identical outcomes; confidence never exceeds bounds. *Integration:* rating → reputation update path. *Deploy:* only the hub may write. |
| **Acceptance** | ☐ Score provably in 0–1000 ☐ Zero sort operations in the contract (CI-enforced) ☐ Version emitted with every update ☐ On-time uses accepted ETA |
| **Docs** | `contracts/docs/reputation.md` with the formula and version history. |
| **FE/BE impact** | **Backend owns leaderboard ranking entirely** — deterministic recomputation from events (§22, §51). Frontend: reputation + confidence display, leaderboard from the backend API not the chain. |

---

#### P3.2 — `BadgeSBT` (ERC-721 + ERC-5192)

| | |
|---|---|
| **Problem** | `ReputationBadge` is not ERC-721 (no `safeTransferFrom`, `approve`, `supportsInterface`, `tokenURI`) and not ERC-5192 (no `locked()`, no `Locked` event) as §24 requires — wallets and explorers cannot render it. Only `FirstDelivery` is ever minted; 4 enum values are dead. Critically, a mint failure **reverts `confirmDelivery`** — a cosmetic subsystem can brick settlement. |
| **Files** | `contracts/src/v1/badge/BadgeSBT.sol` (new) |
| **Changes** | OZ ERC-721 + full ERC-5192 (`locked()`, `Locked`, `supportsInterface`, `tokenURI`). All §24 badge types: milestones 1/10/50/100/500, Zero Lost Dispute, Top 10 Weekly, Verified/Trusted Courier. Duplicate-mint prevention **in the badge contract**. **Decouple minting from settlement** — failure-tolerant or pull-claimed. Badges never reduce required collateral (§24). |
| **Depends / Risks** | P3.1. Risk: verification badges affecting risk eligibility creates a badge→collateral coupling; assert explicitly that they never eliminate collateral. |
| **Tests** | *Unit:* mint, duplicate rejection, every transfer entry point reverts. *Fuzz:* no token ever becomes transferable. *Invariant:* badge count never exceeds qualifying events; badges never reduce required coverage. *Integration:* **a reverting badge mint does not block settlement** — the direct fix. *Deploy:* minter set to the reputation registry, not an EOA. |
| **Acceptance** | ☐ `supportsInterface` returns true for ERC-721 + ERC-5192 ☐ Renders in a wallet ☐ Mint failure cannot revert settlement ☐ No duplicates |
| **Docs** | `contracts/docs/badges.md`. |
| **FE/BE impact** | Frontend: badge gallery. Backend: `tokenURI` metadata hosting — **new backend responsibility**. |

---

#### P3.3 — `RewardDistributor` v2 + referral

| | |
|---|---|
| **Problem** | `claimReward` has **no per-epoch budget cap** — a valid proof for one period can drain another period's funds, violating invariant §33-12. No 90-day claim window, no 7-day reclaim delay, no reclaim function. `setMerkleRoot` can overwrite a root with partial claims. Referral (§25) does not exist. |
| **Files** | `contracts/src/v1/rewards/RewardDistributor.sol`, `contracts/src/v1/rewards/Referral.sol` (new) |
| **Changes** | Per-epoch **funded** budget with an explicit fund step; claims cannot exceed it. §48 90-day claim window + 7-day reclaim delay; reclaim only unclaimed budget. Block root overwrite once a period has claims. **Keep the legacy double-hashed Merkle leaf construction** — it is correct and second-preimage safe. Referral: one referrer per wallet, one monetary reward per wallet, self-referral and cycle rejection, qualification on first completed delivery/jury participation; **referral failure must never block settlement** (§25). |
| **Depends / Risks** | P3.1. Risk: Merkle root generation is off-chain — root correctness is a backend concern with its own test burden. |
| **Tests** | *Unit:* claim, double-claim, expired claim, reclaim. *Fuzz:* sum of claims never exceeds epoch budget for random trees. *Invariant:* §33-12 budget cap; referral graph acyclic. *Integration:* reward double-claim, referral circular graph (§47). *Deploy:* epoch 0 funded and asserted. |
| **Acceptance** | ☐ §33-12 invariant passes ☐ Cross-epoch drain impossible ☐ Root overwrite blocked after first claim ☐ Referral failure cannot revert settlement |
| **Docs** | `contracts/docs/rewards.md`. |
| **FE/BE impact** | **Backend: Merkle tree generation + epoch automation.** Frontend: claim screen + referral status. |

---

### **P4 — Dispute system**
*The largest single gap. Blocks §51 Definition of Done.*

---

#### P4.1 — `IRandomnessAdapter` + `PythEntropyAdapter`

| | |
|---|---|
| **Problem** | No randomness source exists. §29 requires a provider abstraction so the core court never depends on one provider, dynamic fee query, pass-through fees, a callback that **only records** randomness, and explicitly **no blockhash fallback** for jury selection. |
| **Files** | `contracts/src/v1/randomness/IRandomnessAdapter.sol`, `contracts/src/v1/randomness/PythEntropyAdapter.sol` (new) |
| **Changes** | Interface + Pyth Entropy v2 implementation. Query fee dynamically; pass through. Callback records randomness only — never settles. Handle provider-unavailable without stranding a dispute. |
| **Depends / Risks** | P0.2. **Risk: Pyth Entropy v2 availability on Monad testnet is unverified** — must be confirmed before P4 starts (**D8**). If unavailable, the interface still ships and a documented interim adapter is needed; blockhash is explicitly not acceptable. |
| **Tests** | *Unit:* request/callback cycle; fee query. *Fuzz:* random callback payloads. *Invariant:* callback never mutates dispute state. *Integration:* provider unavailable (§47). *Deploy:* adapter address set via config, swappable. |
| **Acceptance** | ☐ Core court has zero Pyth-specific code ☐ Provider swap needs no court redeploy ☐ No blockhash randomness anywhere ☐ Provider outage does not strand a dispute |
| **Docs** | `contracts/docs/randomness.md`. |
| **FE/BE impact** | Frontend: must surface the dynamic randomness fee at dispute time (§40). |

---

#### P4.2 — `DisputeCourt` core

| | |
|---|---|
| **Problem** | No dispute system exists at all — no evidence, juror pool, draw, commit/reveal or quorum (§26–§30, §32.6). |
| **Files** | `contracts/src/v1/dispute/DisputeCourt.sol`, `contracts/src/v1/dispute/JurorPool.sol` (new) |
| **Changes** | Dispute creation + evidence commitment (hashes only). Juror eligibility separate from courier stake (§4.6) with §48 economics: 10 MON min stake, 2 MON lock/case, 1 MON non-reveal slash. Equal-weight random selection — stake above minimum grants no extra weight (§27). Commit/reveal per §30 with the 6 bounded ruling outcomes; **jurors cannot supply arbitrary addresses or percentages**. Quorum handling. |
| **Depends / Risks** | P4.1, P1.1, P3.1. Risk: juror set changing between draw request and fulfilment (invariant §33-18) — snapshot the eligible set at request time. Risk: a valid minority juror must not be slashed merely for dissenting (§33-14). |
| **Tests** | *Unit:* commit, reveal, non-reveal slash, quorum. *Fuzz:* random vote distributions produce a bounded ruling. *Invariant:* §33-13 same juror never occupies two slots; §33-14 minority not slashed; §33-18 membership changes cannot manipulate a pending draw. *Integration:* juror fails to reveal; duplicate juror selection attempt (§47). *Deploy:* juror economics from config. |
| **Acceptance** | ☐ Invariants §33-13, §33-14, §33-18 pass ☐ Rulings strictly bounded to the 6 codes ☐ Deterministic timeouts never become jury cases (§26) |
| **Docs** | `contracts/docs/dispute.md`. |
| **FE/BE impact** | **Frontend: entire juror role UI** (activation, evidence, commit, reveal, appeal, history) — the largest single frontend addition. Backend: encrypted evidence storage + juror notifications. |

---

#### P4.3 — Appeals, fallback committee, ruling settlement

| | |
|---|---|
| **Problem** | §28's 3→5→7 appeal escalation, §31's liveness fallback, and the path from ruling to money do not exist. Without the fallback a stuck jury freezes funds permanently. |
| **Files** | `DisputeCourt.sol`; `contracts/src/v1/dispute/FallbackCommittee.sol` (new); `SettlementVault.sol` |
| **Changes** | Appeal rounds 3→5→7 with the §28 fee/bond schedule. 3-of-5 Safe committee validated via EIP-1271, restricted to **bounded ruling codes only — never arbitrary transfers** (§31). Final ruling settles through the vault exactly once, into `claimable[]`. |
| **Depends / Risks** | P4.2, P0.3. Risk: the fallback committee is a centralization vector — it is last-resort liveness, not routine administration (§31), and must be documented and monitored as such. |
| **Tests** | *Unit:* each appeal round; committee signature validation. *Fuzz:* arbitrary committee payloads never produce an unbounded transfer. *Invariant:* a dispute settles exactly once across all paths. *Integration:* full dispute → jury → appeal → resolve (§46). *Deploy:* committee is a real Safe, not an EOA. |
| **Acceptance** | ☐ Ruling settles exactly once (§51) ☐ Committee cannot define arbitrary transfers ☐ No dispute can freeze funds indefinitely |
| **Docs** | `contracts/docs/dispute.md` (appeals + fallback runbook). |
| **FE/BE impact** | Frontend: appeal status. Backend: committee coordination + monitoring alerts on any fallback use. |

---

### **P5 — Release hardening**

---

#### P5.1 — Full invariant, failure and adversarial suite

| | |
|---|---|
| **Problem** | Today: 5 tests, zero fuzz, zero invariant, zero adversarial; none of the 18 §33 invariants explicitly tested and two demonstrably violated; none of the 22 §47 failure scenarios covered. |
| **Files** | `contracts/test/invariant/**`, `contracts/test/failure/**`, `contracts/test/adversarial/**`, `contracts/.gas-snapshot` |
| **Changes** | One named test per §33 invariant (all 18) and per §47 failure scenario (all 22). Stateful invariant handlers spanning the whole system, including reverting receivers, malicious couriers and failing providers. Adversarial suite. Refresh gas snapshots. |
| **Depends / Risks** | P0–P4. Risk: deferring this to the end — mitigated because each phase already ships its own invariants; P5.1 is consolidation and gap-filling, not first coverage. |
| **Tests** | The deliverable *is* the tests. Add coverage reporting to CI. |
| **Acceptance** | ☐ All 18 §33 invariants have a named passing test ☐ All 22 §47 scenarios covered ☐ Gas snapshot committed ☐ Coverage threshold met (**D4**) |
| **Docs** | `contracts/docs/testing.md` mapping each invariant/scenario to its test. |
| **FE/BE impact** | None directly; failure-mode catalogue feeds frontend §40 error taxonomy. |

---

#### P5.2 — Deployment hardening + artifact export

| | |
|---|---|
| **Problem** | Both deploy scripts assign treasury, reward pool and every owner role to a **single deployer EOA** (§32.11 violation). No post-deploy assertions, no chainId guard in Solidity, no source verification, no address artifact for consumers. `contracts/README.md` §10.1 claims a deploy record that is gitignored and absent. |
| **Files** | `contracts/script/v1/DeployV1.s.sol` (new); `scripts/deploy-*.mjs`; `contracts/deployments/<chainId>.json`; `contracts/README.md` |
| **Changes** | Distinct addresses per role; Safe-owned criticals. Assert chainId in Solidity (not only in the shell script). Post-deploy invariant assertions (roles correct, no EOA holds two criticals, vault solvent, minter wired). `--verify` source verification. Emit the network manifest + ABIs per §6. Correct the README's unverifiable deploy claim. |
| **Depends / Risks** | P0–P4, and the §6 decision (**D3**). Risk: a partially-failed multi-contract deploy — make the script idempotent and resumable. |
| **Tests** | *Unit:* manifest builder (extends the existing `deploy-record.test.mjs`). *Integration:* full local anvil deploy + assertions. *Deploy:* testnet dry-run then broadcast; re-run proves idempotency. |
| **Acceptance** | ☐ No EOA holds two critical roles ☐ Deploy aborts on wrong chainId ☐ All sources verified on the explorer ☐ Manifest generated and committed ☐ README claim corrected |
| **Docs** | `contracts/docs/deployment.md` runbook; README rewrite. |
| **FE/BE impact** | **This is the step that delivers §6.** Both apps switch to the generated package as their single source of truth. |

---

#### P5.3 — Testnet E2E, cut-over, security review

| | |
|---|---|
| **Problem** | §46 requires the three end-to-end Monad testnet flows to pass, and §51's Definition of Done requires the whole loop working. Legacy contracts must be retired in a controlled way. |
| **Files** | `contracts/script/E2E*.sh`; removal of `contracts/src/legacy/**` and `contracts/test/legacy/**`; `frontend/app/config/chain.ts`; `frontend/.env` |
| **Changes** | Run all three §46 E2E flows on Monad testnet: happy path → claim; failed delivery → return; dispute → jury → appeal → resolve. **Only now** remove legacy contracts and repoint the apps. Delete the three conflicting address sources in favour of the generated package. External security review before any mainnet consideration (§45, §52). |
| **Depends / Risks** | Everything. Risk: **this is the only breaking step** — it merges last, behind its own approval, and is independently revertible as one squash commit. |
| **Tests** | *Integration:* all three §46 E2E flows on real testnet. *Deploy:* full clean-network deploy from scratch. *Regression:* legacy tests retired **only after** V1 equivalents demonstrably cover the same behavior. |
| **Acceptance** | ☐ All three §46 flows pass on testnet ☐ Every §51 contract-side checkbox ticked ☐ Zero hardcoded addresses remain ☐ Security review complete |
| **Docs** | Full README rewrite; §12 "Known Limits" replaced with the real state. |
| **FE/BE impact** | **Coordinated cut-over.** Frontend and backend must merge their consuming changes in lockstep with this step. |

---

## 6. Sharing addresses, ABIs, chain IDs, events, errors and types

### 6.1 Current state

Three conflicting address sources (`chain.ts` literals, `frontend/.env`, `README.md` §9) that **have already drifted** — `chain.ts` holds the modular addresses while `.env` holds a different `Delivera` address. No ABI is shared at all. `contracts/deployments/` is generated but never committed.

### 6.2 Options compared

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **1. Status quo (manual)** | Hand-edited constants in each consumer | Zero setup | Already drifted. No ABI, no types, no errors. Unusable once the apps make real calls. |
| **2. Network-keyed manifest** | `contracts/deployments/<chainId>.json` committed to git — address, chainId, deploy tx, block, commit SHA, contract version | Simple; git-reviewable; deployment history in history; multi-network by construction; **extends the existing `deploy-record.mjs`** | No ABI, no types. Consumers hand-write typings. |
| **3. Generated package** | `packages/contracts/` generated via wagmi CLI / abitype — addresses + ABIs + typed events + **custom errors** + viem/wagmi types | One import for both apps; full type safety; decodes custom errors, which §40's error taxonomy needs; catches drift at compile time | Needs a build step and workspace wiring (root `package.json` has **no `workspaces` field** today). Must emit JS + `.d.ts` because **the backend is plain JavaScript**. |
| **4. Automated deploy export** | CI regenerates 2 + 3 on every deploy and opens a PR | Removes the human step where drift originates; deploy and artifacts can never disagree | CI complexity; must open a PR, never auto-push to a protected branch |
| **5. On-chain registry** | A registry contract resolving names → addresses | Fully trustless resolution | Overkill for V1; extra call latency and gas; still doesn't solve ABIs or types |

### 6.3 Recommendation — layered 2 + 3 + 4

These are complementary layers, not alternatives:

1. **Source of truth — the manifest (2).** `contracts/deployments/<chainId>.json`, committed and schema-validated. Extend the existing `buildDeploymentRecord` rather than replacing it: generalize it from one contract to all, and from hardcoded `10143` to a chainId parameter. Include the deploying commit SHA and an ABI hash so a stale artifact is *detectable*.
2. **Consumer surface — the generated package (3).** `packages/contracts/` generated from the manifest plus `forge build` output, exporting addresses by chainId, ABIs, typed events, custom errors and viem/wagmi types. **Must emit ESM JS + `.d.ts`** so the JavaScript backend and TypeScript frontend consume one package.
3. **Automation — CI export (4).** The deploy job regenerates both and opens a PR. CI additionally fails if a committed manifest's ABI hash diverges from a fresh `forge build`, which catches "contract changed, artifacts didn't".
4. **Reject 5** for V1 and **retire 1** entirely at P5.3.

Sequencing note: the manifest layer is needed as soon as P1 deploys anything testable; the generated package is needed when the frontend makes its first real contract call. Both land in **P5.2**, but if frontend integration starts earlier, the manifest layer should be pulled forward — worth flagging now (**D3**).

Custom errors matter here specifically: P0.2 onward replaces string `require`s with custom errors, and §40 requires the UI to distinguish wrong network / stale quote / expired bid / insufficient collateral. Only the generated-package layer makes those decodable in the frontend without hand-maintained selector tables.

---

## 7. Decisions requiring your approval

Nothing proceeds until these are settled. **D1–D3 block P0.**

| # | Decision | Options | Recommendation |
|---|---|---|---|
| **D1** | **Legacy strategy** (§3) | A remediate in place · **B freeze + build additively** · C hard greenfield | **B** — doc-aligned ("from scratch"), every merge non-breaking, no throwaway work |
| **D2** | **Branch strategy** (§4) | A direct commits · **B feature branch per step** · C integration branch | **B** — review gate per step, isolated blast radius, minimal overhead given disjoint directories |
| **D3** | **Artifact sharing** (§6) | 1–5 as compared | **Layered 2+3+4.** Also decide whether to pull the manifest layer forward ahead of P5.2 |
| **D4** | **Coverage / quality gates** | What CI blocks a merge on | Propose: line coverage ≥ 90% on `src/v1/`, zero new Slither high/medium, gas snapshot diff reviewed |
| **D5** | **Multisig timing** | Stand up a Safe now vs. 1-of-1 placeholder until P5.2 | Real Safe from **P0.2** — a placeholder that "will be replaced later" usually isn't |
| **D6** | **External review gate** | Review `SettlementVault` after P0.3, or only at P5.3 | **After P0.3.** Everything else builds on it; finding a vault flaw at P5 invalidates months of work |
| **D7** | **Off-chain signer policy** | Who holds the risk-quote and PoD keys; rotation cadence; compromise runbook | Two **separate** keys, backend-held, rotatable via `SIGNER_ADMIN` without redeploy. Needs your key-custody decision |
| **D8** | **Pyth Entropy on Monad testnet** | Confirmed available? If not, what interim? | **Verify before P4 starts.** Blockhash fallback is explicitly not acceptable (§29) |
| **D9** | **Stranded legacy testnet funds** | Do nothing / document / compensate testers | Document publicly + repoint the frontend. On-chain recovery is impossible — the deployed contract is immutable with no exit path |
| **D10** | **`Monosfer-V2 → main` timing** | When (if ever) the contract work reaches `main` | Out of scope here — decide after P5.3 |

### Economic parameters also needing sign-off (block P0.2)

| Parameter | Baseline §48 | Current code | Needs your call |
|---|---|---|---|
| Protocol fee | 2% | 1% | Adopt 2%? |
| Fee incidence | Customer pays **on top of** ask (§8.1) | Deducted from courier's ask | Adopt baseline (courier receives full ask)? |
| Fee split | → Treasury (§18.1) | 50/50 treasury/rewardPool | Keep the split (not in baseline) or send all to Treasury? |
| Courier base deposit | 10 MON | 0.01 MON native | Adopt 10 MON? Affects testnet faucet burden |
| Settlement asset | Native MON (§23 forbids a project ERC-20) | `MCRYToken`, symbol `"MON"` | Confirm native MON and deletion of `MCRYToken`? |
| Upgradeability | **Baseline is silent** | Immutable | Immutable-with-redeploy, or UUPS proxy? Materially changes every contract |

---

## 8. What happens next

On approval of **D1, D2, D3** (plus the economic parameters for P0.2), the first action is:

```bash
git fetch origin --prune && git checkout -b Monosfer-V2 origin/Monosfer-V2
git checkout -b feat/contracts-p0.1-ci-harness
```

…and P0.1 begins. `main` is not touched at any point. No implementation starts before that approval.
