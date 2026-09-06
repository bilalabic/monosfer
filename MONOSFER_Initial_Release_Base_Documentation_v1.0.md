# MONOSFER — Initial Release Base Documentation

> **Status:** Initial Release Baseline  
> **Version:** 1.0  
> **Date:** 5 September 2026  
> **Target:** Monad Testnet first; Mainnet only after separate readiness gates  
> **Scope:** Product + protocol + smart contracts + backend + frontend + testing  
>
> **Important:** In this document, **V1 / Initial Release** means the first version that will be built from scratch. It does **not** refer to any previous MONOSFER implementation.

---

## 1. Project Summary

**MONOSFER** is a decentralized courier marketplace designed for real-world physical deliveries. Customers create delivery requests, independent couriers compete with their own price and ETA proposals, and the customer selects the courier based on price, reputation, delivery history, risk eligibility, and expected delivery time.

Blockchain is not used for every part of the product. It is used where shared verification or economic custody matters:

- delivery lifecycle,
- courier bidding,
- courier selection,
- escrow,
- courier collateral,
- dispute state,
- reputation outcomes,
- reward claims,
- non-transferable achievements.

Private and operational data such as full addresses, phone numbers, raw GPS locations, OTP secrets, photos, and dispute evidence remain **off-chain**.

The Initial Release should prove one complete lifecycle:

```text
Customer creates delivery
        ↓
Couriers place bids
        ↓
Customer selects courier
        ↓
Customer funds escrow
+
Courier locks required coverage
        ↓
Pickup proof
        ↓
Physical delivery + live tracking
        ↓
Recipient proof
        ↓
Challenge / dispute window
        ↓
Settlement
        ↓
Reputation + leaderboard + rewards
```

---

## 2. Initial Release Goal

The first release should be a **complete Testnet product**, not only a smart-contract demo.

A successful V1 should demonstrate:

1. a real user can connect a wallet;
2. a customer can create a delivery;
3. eligible couriers can submit competing bids;
4. the customer can select one courier;
5. escrow and courier collateral can be locked safely;
6. pickup can be cryptographically confirmed;
7. the courier can perform the delivery with route/ETA and live tracking;
8. a walletless recipient can confirm delivery using OTP/QR;
9. the delivery can complete normally or enter return/dispute flows;
10. money and collateral settle deterministically;
11. courier reputation updates;
12. leaderboard, badges and rewards can be produced;
13. a dispute can be resolved through the decentralized-jury flow;
14. the whole system can recover from provider/indexer/backend failures without duplicating financial effects.

The first release is **Testnet-first**. Production payment, postal-operation and legal constraints are separate Mainnet gates.

---

# 3. Product Principles

## 3.1 Trust-minimized, not blockchain-everywhere

Use blockchain for:

- shared economic state,
- custody,
- objective lifecycle transitions,
- public reputation aggregates,
- dispute rulings,
- immutable reward/achievement records.

Do not put unnecessary private data on-chain.

## 3.2 Courier-defined pricing

A courier defines:

- delivery fee,
- estimated delivery time,
- optional return fee,
- bid validity.

The platform does not force a single delivery price.

## 3.3 Reputation has economic value

Good reputation should provide:

- better marketplace visibility,
- stronger customer trust,
- access to higher-risk deliveries,
- limited collateral advantages,
- leaderboard eligibility,
- achievement badges.

However:

> **Reputation never replaces economic collateral.**

## 3.4 Failure-first product design

The system must explicitly handle:

- customer does not fund,
- courier does not provide coverage,
- courier does not arrive,
- sender is unavailable,
- recipient is unavailable,
- delivery cannot be completed,
- package must be returned,
- customer does not confirm,
- package is lost or damaged,
- one party disputes delivery,
- randomness provider fails,
- indexer/RPC fails,
- payout receiver rejects MON,
- signer/backend provider becomes unavailable.

---

# 4. User Roles

## 4.1 Customer / Sender

The customer:

- connects MetaMask,
- creates the delivery,
- enters private pickup/drop-off details,
- declares approximate package value,
- receives risk/coverage information,
- selects a courier bid,
- funds the delivery,
- confirms pickup,
- monitors delivery,
- confirms receipt or opens a dispute,
- can rate the courier after successful completion.

## 4.2 Recipient

The recipient may be different from the customer.

The recipient:

- does **not** need a wallet,
- receives delivery notifications,
- can verify handoff using OTP/QR,
- may optionally use wallet signature if a wallet is available.

## 4.3 Community Courier — C0

Requirements:

- wallet,
- courier profile,
- minimum base security deposit,
- no suspension.

Initial access:

- R1 / low-risk deliveries.

## 4.4 Verified Courier — C1

Requirements:

- C0 requirements,
- off-chain verification.

Initial access:

- R1 and R2 deliveries.

## 4.5 Trusted Courier — C2

Requirements:

- C1,
- minimum qualified delivery history,
- acceptable dispute/cancellation history,
- sufficient reputation/confidence.

Initial access:

- R1, R2 and R3 deliveries.

## 4.6 Juror

Requirements:

- separate juror eligibility,
- juror stake,
- required platform history / verification policy,
- no conflict with dispute parties.

A courier deposit is **not automatically juror stake**.

## 4.7 Protocol Operator

The protocol operator can manage:

- bounded configuration,
- emergency pause,
- provider/signer rotation,
- operational support.

The operator must **not** have arbitrary access to user escrow.

---

# 5. Initial Release Feature Scope

## 5.1 Wallet and Authentication

Required:

- MetaMask connection,
- Monad network detection/switching,
- SIWE-based backend session,
- session nonce/replay protection,
- wallet reconnect flow,
- insufficient MON error handling,
- rejected signature handling.

The same wallet may hold multiple roles:

- customer,
- courier,
- juror.

---

## 5.2 Delivery Creation

Customer enters:

### Route
- pickup location,
- drop-off location,
- pickup window,
- approximate route distance,
- estimated route duration.

### Recipient
- name,
- contact information,
- optional wallet address.

### Package
- category,
- size class,
- approximate weight,
- declared value,
- handling flags,
- optional instructions.

### Risk
The system returns:

- risk tier,
- required courier verification level,
- protected/covered amount,
- required collateral estimate.

### Privacy
Public marketplace listing must **not** expose:

- exact pickup address,
- exact destination address,
- phone number,
- raw GPS coordinates,
- exact declared value,
- private delivery instructions.

The marketplace may show:

- city/district/zone,
- approximate distance,
- package class,
- risk tier,
- pickup window.

---

# 6. Risk Tiers

Initial policy:

| Tier | Meaning | Courier | Testnet Coverage Baseline |
|---|---|---|---:|
| R1 | Low risk | C0+ | 25% |
| R2 | Medium risk | C1+ | 60% |
| R3 | High risk | C2 | 100% |
| R4 | Restricted | Disabled | N/A |

`Declared Value` is **not insurance**.

The UI must separately display:

- Declared Value
- Protected Amount / Coverage
- Coverage percentage

R4 remains disabled until a separate insurance/special-operations model exists.

---

# 7. Courier Bidding

Each courier may submit:

```text
courierAsk
deliveryEstimate / ETA
returnAsk
validUntil
termsVersion
```

Rules:

- multiple couriers may bid;
- customer does not have to select the cheapest bid;
- the customer may compare price, ETA, reputation, delivery count, disputes and badges;
- one courier has one active bid version per delivery;
- a courier can update or withdraw an unselected bid;
- selected terms become immutable;
- a customer cannot select their own wallet as courier;
- global bid lists are produced by the indexer, not by unbounded contract arrays.

---

# 8. Funding and Economic Security

## 8.1 Customer Funding

After bid selection:

```text
Customer Escrow
=
Courier Ask
+ Protocol Fee
+ Return Reserve
```

The Initial Release Testnet protocol fee baseline is:

```text
2%
```

This value is a Testnet calibration value, not a permanent Mainnet commitment.

## 8.2 Courier Base Security Deposit

Testnet baseline:

```text
Minimum Courier Base Deposit = 10 MON
```

Purpose:

- courier role activation,
- basic economic skin-in-the-game,
- source for delivery-specific collateral reservation.

It is **not** package insurance.

## 8.3 Delivery Coverage

For each selected delivery:

```text
requiredCoverage
=
coverageQuote
× bounded reputation multiplier
```

Then:

```text
reservedBase
=
min(availableBaseDeposit, requiredCoverage)

additionalBond
=
requiredCoverage - reservedBase
```

Therefore:

```text
lockedCoverage
=
reservedBase + additionalBond
```

### Critical rule

The same base collateral cannot protect two deliveries simultaneously.

---

# 9. Courier Physical Concurrency

Initial Release baseline:

```text
MAX_ACTIVE_CUSTODY = 1
```

A courier may:

- browse many listings,
- place multiple bids,

but may only physically hold **one active delivery** after pickup.

This protects:

- ETA quality,
- operational clarity,
- collateral accounting,
- package security.

The limit may be increased in later releases after field data.

---

# 10. Funding Session

After bid selection, a bounded `FundingSession` begins.

Two independent obligations must complete:

### Customer
Locks:

- courier ask,
- protocol fee,
- return reserve.

### Courier
Locks:

- reserved base collateral,
- additional delivery bond if needed.

Only after both are satisfied:

```text
AWAITING_FUNDING
        ↓
READY_FOR_PICKUP
```

If the deadline expires:

- the completed side is released/refunded,
- no party can keep the other party's capital locked indefinitely.

Testnet funding window baseline:

```text
15 minutes
```

---

# 11. Delivery State Machine

Recommended persistent state machine:

```text
BIDDING
   │
   ├── CANCELLED
   ├── EXPIRED
   │
   ▼
AWAITING_FUNDING
   │
   ├── CANCELLED
   ├── EXPIRED
   │
   ▼
READY_FOR_PICKUP
   │
   ├── CANCELLED
   ├── EXPIRED
   │
   ▼
IN_TRANSIT
   │
   ├── RETURN_REQUIRED
   ├── DISPUTED
   │
   ▼
DELIVERED_PENDING
   │
   ├── DISPUTED
   │
   ▼
COMPLETED

RETURN_REQUIRED
   ├── RETURNED
   └── DISPUTED

DISPUTED
   ↓
RESOLVED
```

Pickup is emitted as an explicit checkpoint/event, but successful pickup moves the persistent state directly to `IN_TRANSIT`; an extra transaction only to enter `IN_TRANSIT` is unnecessary.

Terminal states:

- COMPLETED
- RETURNED
- RESOLVED
- CANCELLED
- EXPIRED

Terminal state cannot reopen.

---

# 12. Pickup Proof

Preferred Initial Release method:

**EIP-712 PickupAcceptance signature**

The signed message binds:

- delivery ID,
- selected courier,
- pickup action,
- nonce,
- expiry,
- chain,
- verifying contract.

EIP-712 domain separation alone is not sufficient.

The contract must also enforce:

- nonce uniqueness,
- expiry,
- correct delivery,
- correct action,
- correct courier,
- correct signer.

EOA and smart-account signatures should be supported through `SignatureChecker` / ERC-1271-compatible validation.

---

# 13. Route and ETA

The Initial Release includes **single-delivery route optimization**, not fleet-level multi-stop optimization.

The routing layer should consider:

- pickup,
- drop-off,
- courier transport mode,
- current courier position when available,
- road/travel information from provider,
- current ETA.

The system distinguishes:

### Accepted ETA
The courier's bid-time promise.

### Live ETA
The latest estimated arrival.

Late delivery primarily affects reputation and operational signals. It does not automatically slash collateral unless an explicit dispute/rule applies.

---

# 14. Live Location

Live courier location is off-chain.

Flow:

```text
Courier device
    ↓
Tracking Service
    ↓
Authorized Customer / Recipient
```

Rules:

- starts around active pickup/in-transit lifecycle;
- exact location is not public;
- access is delivery-scoped;
- tracking authorization ends with the delivery;
- location is never written directly to blockchain.

### Initial PWA limitation

The Nuxt/PWA release must not promise guaranteed continuous background GPS.

The Initial Release baseline supports foreground tracking.

A real production requirement for guaranteed background courier tracking must be validated with:

- native mobile app, or
- background-capable mobile shell/runtime.

---

# 15. Recipient Delivery Proof

Walletless recipient flow:

```text
Recipient receives OTP / QR
        ↓
Backend validates secret
        ↓
PoD Attestation Service signs typed attestation
        ↓
Smart contract validates signed attestation
```

Blockchain stores no plaintext OTP.

Attestation binds:

- delivery ID,
- courier,
- proof type,
- challenge hash,
- nonce,
- issue time,
- expiry.

Testnet PoD attestation maximum lifetime:

```text
10 minutes
```

Photos/GPS may support a dispute but are not sufficient alone to prove package condition.

---

# 16. Delivery Challenge Window

After recipient proof:

```text
DELIVERED_PENDING
```

The Initial Release uses a unified:

```text
24-hour challenge window
```

Two possibilities:

### Customer explicitly confirms
The delivery may complete early.

### Customer does nothing
After challenge deadline, anyone may call the permissionless finalizer.

If a valid dispute opens before completion:

```text
DELIVERED_PENDING → DISPUTED
```

Courier collateral remains locked until this window ends or explicit irreversible confirmation occurs.

---

# 17. Failed Delivery and Return

Examples:

- recipient unavailable,
- recipient refuses package,
- OTP verification cannot complete.

Flow:

```text
IN_TRANSIT
    ↓
RETURN_REQUIRED
    ↓
Return to sender
    ↓
Return proof
    ↓
RETURNED
```

A selected bid may contain:

```text
returnAsk
```

The customer pre-funds a return reserve.

A return fee can only be paid if return conditions and return proof are valid.

Pickup after physical custody does **not** use a normal unilateral cancellation path.

---

# 18. Settlement

## 18.1 Successful Delivery

Accounting:

```text
Courier Ask
    → courier

Protocol Fee
    → Treasury

Unused Return Reserve
    → customer

Courier Coverage
    → released
```

## 18.2 Pull-Payment Model

Settlement does not force MON directly to external wallet contracts.

Instead:

```text
claimable[courier] += amount
claimable[customer] += amount
claimable[treasury] += amount
```

Users later call:

```text
claim()
```

Reason:

A receiver reverting must not block the delivery settlement of everyone else.

---

# 19. Reputation

Reputation is not simply star rating.

Initial long-term courier score:

```text
0–1000
```

with a separate confidence level.

Initial components:

| Signal | Baseline Weight |
|---|---:|
| Successful delivery | 30% |
| Customer rating | 20% |
| On-time performance | 15% |
| Dispute performance | 15% |
| Courier-caused cancellation | 10% |
| Experience / confidence | 10% |

The scoring algorithm is versioned.

New couriers must not obtain the same confidence as a courier with hundreds of deliveries merely because both have 100% success.

---

# 20. Customer Rating

After a successful delivery:

- customer may rate courier,
- rating range is 1–5,
- one rating per delivery,
- only delivery customer may rate,
- rating must occur within a bounded rating window,
- rating does not reopen settlement.

Rating is one reputation input, not the entire score.

---

# 21. Customer / Sender Reliability

The system should also maintain objective customer-side reliability signals.

Possible inputs:

- completed deliveries,
- customer-caused cancellations,
- customer/sender no-show,
- finalized fraudulent claims,
- repeated failed handoff responsibility.

This should not become an opaque social score.

Only operationally relevant and explainable reliability signals should affect marketplace risk controls.

---

# 22. Leaderboard

Leaderboard is separate from long-term reputation.

### Reputation
Long-term trust signal.

### Weekly Leaderboard
Short-term competitive performance.

Leaderboard source:

```text
On-chain events
    ↓
Indexer
    ↓
Deterministic ranking
```

The global ranking should **not** be sorted inside a smart contract.

---

# 23. MON Rewards

The protocol does **not** create a MONOSFER ERC-20 token.

MON rewards may be funded by:

- Testnet faucet budget,
- sponsors,
- grants,
- Treasury budget.

Weekly reward process:

```text
Indexer calculates ranking
        ↓
Epoch reward set generated
        ↓
Merkle root published
        ↓
Eligible users claim
```

Initial reward claim policy:

```text
Claim window: 90 days
Reclaim delay: 7 days
```

Only unclaimed budget may be reclaimed after the delay.

---

# 24. Soulbound Badges

Achievement NFTs are non-transferable.

Reference design:

```text
ERC-721 + ERC-5192
```

Possible badges:

- First Delivery
- 10 Deliveries
- 50 Deliveries
- 100 Deliveries
- 500 Deliveries
- Zero Lost Dispute
- Top 10 Weekly
- Verified Courier
- Trusted Courier

Badges are not just cosmetic when appropriate:

- verification badges may affect risk eligibility;
- achievement badges may improve marketplace trust.

Badges must never eliminate required collateral.

---

# 25. Referral System

Referral supports:

- customer,
- courier,
- juror.

A referral does not pay merely because a wallet connects.

Qualification examples:

### Customer
First qualified completed delivery.

### Courier
First qualified delivery completed as courier.

### Juror
First finalized valid jury participation.

Rules:

- one referrer per referred wallet;
- one monetary referral reward per referred wallet;
- self-referral prohibited;
- circular referral detection;
- obvious Sybil patterns handled by off-chain risk controls;
- reward failure must never block delivery settlement.

---

# 26. Decentralized Dispute System

Disputes are used when physical facts require evidence interpretation.

Examples:

- non-delivery,
- loss,
- damage,
- failed return,
- disputed handoff.

Deterministic timeout/cancellation situations should not automatically become jury cases.

---

# 27. Juror Economics

Initial Testnet calibration values:

```text
Minimum Juror Stake:       10 MON
Lock per selected case:     2 MON
Non-reveal slash:           1 MON
```

These are **Testnet economic simulation parameters**, not permanent Mainnet economics.

Stake above the minimum does not give unlimited voting power.

Initial juror selection baseline:

```text
eligible jurors → equal-weight random selection
```

---

# 28. Jury Lifecycle

Initial structure:

```text
Dispute opened
    ↓
Evidence window
    ↓
Random juror draw
    ↓
3 jurors
    ↓
Commit
    ↓
Reveal
    ↓
Provisional ruling
    ↓
Appeal if needed
    ↓
5 jurors
    ↓
Second appeal if needed
    ↓
7 jurors
    ↓
Final ruling / fallback
```

Initial Testnet dispute economics:

| Round | Base Arbitration Fee | Participation / Appeal Bond |
|---|---:|---:|
| First | 0.3 MON | 1 MON |
| Appeal 1 | 0.5 MON | 2 MON |
| Appeal 2 | 0.7 MON | 4 MON |

The dynamic randomness-provider network fee is separate.

---

# 29. Juror Selection Randomness

Initial Testnet provider:

**Pyth Entropy v2**

The core court must use a provider abstraction:

```text
DisputeCourt
    ↓
IRandomnessAdapter
    ↓
PythEntropyAdapter
```

The provider may later be replaced without rewriting the dispute core.

Rules:

- fee is queried dynamically;
- randomness fee is pass-through;
- callback only records randomness;
- callback does not settle dispute;
- pseudorandom blockhash fallback is not used for jury selection.

---

# 30. Jury Voting

Voting uses commit/reveal.

Commit example:

```text
voteHash =
keccak256(
    disputeId,
    round,
    juror,
    ruling,
    salt
)
```

Reveal later supplies:

- ruling,
- salt.

Initial allowed outcomes are bounded:

- CUSTOMER_100
- CUSTOMER_75
- SPLIT_50
- CUSTOMER_25
- COURIER_100
- REFUSE

Jurors cannot provide arbitrary payout addresses or arbitrary percentage values.

---

# 31. Jury Fallback

If 3 / 5 / 7 juror rounds cannot reach usable quorum/ruling, the protocol needs a final liveness mechanism.

Initial fallback design:

```text
3-of-5 Safe committee
+
EIP-1271 signature validation
```

The committee may only sign a bounded ruling code.

It cannot define arbitrary transfers.

The fallback committee is a last-resort liveness mechanism, not normal dispute administration.

---

# 32. Smart Contracts Required in V1

## 32.1 `ProtocolConfig`

Responsibilities:

- protocol fee,
- timing windows,
- risk policy,
- coverage ratios,
- signer addresses,
- randomness adapter,
- Treasury address,
- listing/custody limits,
- jury economic parameters,
- reward windows.

Configuration must be bounded and versioned.

---

## 32.2 `SettlementVault`

The most security-critical contract.

Responsibilities:

- customer escrow,
- courier base deposit,
- reserved courier collateral,
- additional delivery bond,
- juror stake,
- arbitration fee accounting,
- appeal/participation bond accounting,
- claimable balances,
- payout/refund accounting.

Critical property:

```text
Vault Balance >= Total Recorded Liabilities
```

---

## 32.3 `CourierRegistry`

Responsibilities:

- courier activation,
- verification level,
- suspension,
- delivery eligibility,
- active custody count,
- qualified delivery counters.

---

## 32.4 `DeliveryHub`

Core marketplace/lifecycle contract.

Responsibilities:

- create delivery,
- publish delivery,
- bid hash/status,
- select courier,
- coordinate funding,
- delivery state machine,
- pickup proof,
- delivery proof,
- return flow,
- challenge timeout,
- dispute entry,
- courier rating entry.

---

## 32.5 `ReputationRegistry`

Responsibilities:

- terminal outcome counters,
- customer rating aggregates,
- dispute/cancellation history,
- reputation score version,
- confidence level.

It does not perform global leaderboard sorting.

---

## 32.6 `DisputeCourt`

Responsibilities:

- dispute creation,
- evidence commitment,
- juror eligibility/pool state,
- juror draw,
- commit/reveal,
- quorum,
- appeals,
- final ruling.

---

## 32.7 `RandomnessAdapter`

Provider abstraction for decentralized randomness.

V1 Testnet implementation:

```text
PythEntropyAdapter
```

---

## 32.8 `RewardDistributor`

Responsibilities:

- weekly reward epoch root,
- funded reward budget,
- Merkle proof validation,
- double-claim prevention,
- reward expiry,
- unclaimed-budget reclaim.

---

## 32.9 `BadgeSBT`

Responsibilities:

- non-transferable achievement badges,
- verified/trusted badges,
- milestone badges.

---

## 32.10 `Treasury`

Responsibilities:

- protocol-owned funds,
- sponsor/grant funding,
- reward budget funding,
- dispute reserve where applicable.

Treasury does not hold delivery escrow.

---

## 32.11 `AccessManager`

OpenZeppelin-based permission layer for:

- config roles,
- emergency roles,
- signer/provider rotation,
- delayed privileged operations.

No single EOA should control critical production permissions.

---

## 32.12 `ISettlementAdapter`

The delivery lifecycle should not permanently depend on a single production payment rail.

Testnet:

```text
NativeMonSettlementAdapter
```

Production implementation remains a separate Mainnet decision.

---

# 33. Core Smart Contract Invariants

The Initial Release must test at least the following:

1. Vault is solvent.
2. A delivery settles only once.
3. Accounting conserves value.
4. Courier collateral cannot be reused.
5. Disputed delivery cannot settle through normal success path.
6. Terminal states cannot reopen.
7. Proof nonces cannot be replayed.
8. Coverage quotes cannot be replayed.
9. Required collateral is present at pickup.
10. Courier active custody limit cannot be exceeded.
11. A reverting payout receiver cannot block settlement.
12. Reward claims cannot exceed funded epoch budget.
13. The same juror cannot occupy two slots in one round.
14. A valid minority juror is not slashed only for being in the minority.
15. Admin actions remain inside configured bounds.
16. Customer cannot select their own wallet as courier.
17. Customer escrow amount must exactly match selected terms.
18. Juror membership changes cannot manipulate a previously requested random draw.

---

# 34. On-chain vs Off-chain Boundary

## On-chain

- delivery ID,
- public terms commitment,
- risk tier,
- lifecycle state,
- bid hash/status,
- selected courier,
- escrow accounting,
- fee accounting,
- collateral/bond,
- proof nonce/hash/result,
- dispute ID,
- evidence commitment,
- votes/ruling,
- reputation aggregates,
- badge ownership,
- reward roots/claims,
- configuration events.

## Off-chain

- exact address,
- phone number,
- recipient identity/contact,
- raw declared package value,
- GPS stream,
- route cache,
- OTP secret,
- QR secret,
- photos/videos,
- dispute evidence files,
- notification tokens,
- support notes,
- search/filter indexes,
- user analytics.

---

# 35. Backend Architecture

Initial backend stack:

```text
Node.js LTS
TypeScript
NestJS
Fastify
PostgreSQL
Redis
Encrypted S3-compatible object storage
```

Main backend modules:

- Auth / SIWE
- User Profile
- Courier Profile
- Delivery Private Data
- Risk Quote
- Price Reference
- Indexer Projection
- Tracking Realtime
- Route / ETA
- Evidence
- Notifications
- Referral
- Rewards Projection
- Operations / Support

---

# 36. Backend Responsibilities

The backend may manage:

- private data,
- sessions,
- signed short-lived attestations,
- route provider calls,
- notification delivery,
- live GPS,
- encrypted evidence,
- search/index projection,
- anomaly/risk signals.

The backend must **not** override blockchain-authoritative financial state.

Critical APIs must be:

- versioned (`/v1`),
- documented with OpenAPI,
- idempotent where financial/retry effects exist.

Use `Idempotency-Key` where appropriate.

Blockchain event processing must also be idempotent.

---

# 37. Database and Realtime

## PostgreSQL

Example entities:

- UserProfile
- DeliveryPrivate
- DeliveryProjection
- BidProjection
- CoverageQuote
- EvidencePackage
- ReputationProjection
- Referral
- IndexerCursor

## Redis

Used for:

- realtime tracking,
- short-lived OTP/challenges,
- rate limiting,
- queues,
- ephemeral session state.

Redis is not the authoritative long-term financial database.

---

# 38. Frontend Architecture

Initial frontend:

```text
Nuxt 4
Vue 3
TypeScript
Wagmi Vue / Nuxt
Viem
MetaMask Connect
PWA
```

Nuxt Nitro must **not** become a second domain backend.

Use Nuxt server functionality for:

- SSR,
- presentation,
- same-origin proxy/BFF where useful.

Core business and financial backend logic remains in the dedicated Node/Nest backend and smart contracts.

---

# 39. Main Frontend Screens

## Customer

- Landing / marketplace
- Connect wallet
- Create delivery
- Delivery review
- Delivery detail
- Bid comparison
- Funding
- Active tracking
- Delivery confirmation
- Return status
- Dispute creation
- Profile / history
- Referral

## Courier

- Courier activation
- Deposit/collateral
- Available jobs
- Delivery detail
- Place/edit bid
- Selected job
- Pickup
- Active route/tracking
- Delivery handoff
- Return flow
- Earnings dashboard
- Reputation/badges
- Leaderboard

## Juror

- Juror activation/stake
- Assigned dispute
- Evidence
- Commit vote
- Reveal vote
- Appeal status
- Participation history

---

# 40. Transaction UX

Every transaction must show in plain language:

- what the user is signing,
- how much MON is being locked,
- how much is a fee,
- how much can be slashed,
- when the funds become available again.

UI transaction states:

```text
Awaiting Signature
Submitted
Proposed
Finalized
Verified / indexed when required
```

Errors must distinguish:

- wrong network,
- rejected signature,
- insufficient MON,
- stale quote,
- expired bid,
- insufficient collateral,
- indexer delay,
- RPC failure.

---

# 41. Notifications

Initial push events:

- new bid,
- bid selected,
- funding required,
- funding complete,
- ready for pickup,
- pickup confirmed,
- approaching recipient,
- delivery proof submitted,
- challenge window,
- return required,
- dispute opened,
- jury action required,
- settlement complete,
- reward available.

Push notification failure never changes the blockchain state.

---

# 42. PWA Data Safety

Service worker must not cache:

- authenticated financial API responses,
- wallet sessions,
- OTP,
- evidence,
- transaction payloads,
- private address data.

Offline caching is limited to safe public/static content.

---

# 43. Monad-Specific Technical Rules

Current Monad developer documentation should be treated as deployment-time source of truth.

Important current behavior:

- EVM-compatible smart contracts,
- 300 ms block frequency,
- approximately 600 ms finality,
- gas charging based on transaction **gas limit**,
- asynchronous execution with a later `Verified` state,
- standard Ethereum tooling support.

For significant off-chain financial side effects, backend services should use a conservative confirmation policy and consider the `Verified` stage.

`block.timestamp` has second-level granularity and must not be used as a unique ID.

Do not send unnecessarily large gas-limit buffers.

---

# 44. Smart Contract Tooling

Initial baseline:

```text
Solidity
Foundry with Monad execution network support
OpenZeppelin Contracts
```

Use:

- unit tests,
- fuzz tests,
- stateful invariant tests,
- adversarial tests,
- gas snapshots,
- Testnet integration tests.

Tool versions must be pinned by repository configuration / lock strategy rather than silently following a development branch.

---

# 45. Security Requirements

Required before a public economic release:

- no arbitrary admin custody,
- multisig for critical control,
- delayed privileged configuration,
- emergency pause,
- safe user exits during pause,
- EIP-712 replay protection,
- ERC-1271-compatible signature checks,
- Reentrancy protection,
- CEI pattern,
- no `tx.origin`,
- no arbitrary delegatecall in custody path,
- no unbounded user-controlled loops,
- stale quote handling,
- signer rotation,
- provider-failure behavior,
- source verification,
- dependency review,
- static analysis,
- contract audit/review before Mainnet.

---

# 46. Test Strategy

## Contracts

- Unit
- Fuzz
- Stateful invariant
- Adversarial
- Gas

## Backend

- Unit
- Integration
- Auth/SIWE
- Idempotency
- WebSocket/realtime
- worker/job tests

## Frontend

- Component tests
- wallet tests
- SSR/hydration
- E2E
- PWA cache-policy tests
- mobile viewport tests

## System

Monad Testnet E2E:

```text
Create
→ Bid
→ Select
→ Fund
→ Pickup
→ Track
→ Deliver
→ Challenge
→ Complete
→ Claim
```

And:

```text
Failed Delivery
→ Return
```

And:

```text
Dispute
→ Jury
→ Appeal
→ Resolve
```

---

# 47. Required Failure Tests

At minimum:

- customer selects but never funds;
- courier never provides required coverage;
- same collateral is reserved twice;
- quote expires;
- quote signer is forged;
- pickup proof replay;
- OTP replay/guess;
- receiver cannot accept MON;
- recipient unavailable;
- failed return;
- customer does not confirm;
- dispute/timeout race;
- courier loses package;
- juror fails to reveal;
- duplicate juror selection attempt;
- randomness provider unavailable;
- reward double claim;
- referral circular graph;
- indexer outage/replay;
- RPC provider failure;
- backend retry causes duplicate request;
- admin key compromise drill.

---

# 48. Initial Testnet Parameters

These values exist to make V1 testable. They are not permanent production economics.

| Parameter | Initial Testnet Value |
|---|---:|
| Protocol fee | 2% |
| Courier base deposit | 10 MON |
| R1 coverage | 25% |
| R2 coverage | 60% |
| R3 coverage | 100% |
| R4 | Disabled |
| Max active physical custody | 1 |
| Funding window | 15 min |
| Delivery challenge window | 24 h |
| Courier withdrawal cooldown | 24 h |
| Min juror stake | 10 MON |
| Juror lock / case | 2 MON |
| Non-reveal slash | 1 MON |
| First jury | 3 |
| Appeal 1 | 5 |
| Appeal 2 | 7 |
| Customer active listings | 5 |
| Risk quote validity | 5 min |
| PoD attestation validity | 10 min |
| Reward claim | 90 days |
| Reward reclaim delay | 7 days |

---

# 49. Explicitly Out of Scope for V1

Do **not** add these to the Initial Release unless the baseline is deliberately revised:

- MONOSFER ERC-20 token,
- guaranteed insurance product,
- R4 high-restriction delivery,
- international/customs delivery,
- enterprise WMS,
- fleet dispatch,
- multi-stop courier route optimization,
- arbitrary batch deliveries,
- embedded wallet onboarding,
- gas sponsorship,
- native mobile app unless background GPS becomes necessary for the field pilot,
- fully autonomous AI dispute resolution,
- production crypto-payment architecture for Türkiye before the payment/legal gate is closed.

---

# 50. V1 Technical Milestones

## M0 — Foundation

- repository structure,
- Solidity / Foundry,
- Nuxt frontend skeleton,
- Node/Nest backend skeleton,
- PostgreSQL / Redis,
- CI,
- environments,
- shared types.

## M1 — Marketplace

- wallet/SIWE,
- courier activation,
- delivery creation,
- listing,
- bidding,
- bid selection.

## M2 — Economic Security

- SettlementVault,
- base deposit,
- collateral reservation,
- additional bond,
- risk quote,
- funding session,
- cancellation/expiry accounting.

## M3 — Physical Delivery

- pickup proof,
- route/ETA,
- tracking,
- recipient OTP/QR,
- delivery proof,
- challenge window,
- return flow.

## M4 — Reputation and Incentives

- reputation,
- customer rating,
- leaderboard,
- badges,
- rewards,
- referral,
- earnings dashboard.

## M5 — Dispute

- juror pool,
- Pyth randomness adapter,
- evidence,
- commit/reveal,
- appeal,
- fallback,
- ruling settlement.

## M6 — Testnet Release Candidate

- provider failover,
- load testing,
- full invariant suite,
- observability,
- security review,
- UAT,
- runbooks.

---

# 51. V1 Definition of Done

The Initial Release is complete only when all of the following work end-to-end:

- [ ] MetaMask + SIWE authentication
- [ ] Customer creates private delivery draft
- [ ] Public delivery listing contains no sensitive exact data
- [ ] Multiple eligible couriers can bid
- [ ] Customer selects courier
- [ ] Exact funding is enforced
- [ ] Courier collateral cannot be double-used
- [ ] Required additional bond is enforced
- [ ] Delivery reaches READY_FOR_PICKUP only after both funding obligations
- [ ] Pickup proof is replay-safe
- [ ] Courier custody concurrency limit works
- [ ] Route/ETA works
- [ ] Foreground live tracking works
- [ ] Walletless recipient OTP/QR proof works
- [ ] Delivery challenge window works
- [ ] Normal delivery settles correctly
- [ ] Pull-payment claim works
- [ ] Recipient-unavailable return works
- [ ] Dispute freezes normal settlement
- [ ] Random juror selection works
- [ ] Commit/reveal works
- [ ] Appeal works
- [ ] Final ruling settles exactly once
- [ ] Reputation updates
- [ ] Customer rating updates reputation inputs
- [ ] Weekly leaderboard can be recomputed deterministically
- [ ] Reward Merkle claim works
- [ ] Reward cannot be double-claimed
- [ ] Badge minting works
- [ ] Referral qualification works
- [ ] Earnings dashboard reflects on-chain outcomes
- [ ] Indexer can replay/recover
- [ ] RPC failure does not create duplicate financial effects
- [ ] Smart-contract invariants pass
- [ ] End-to-end Monad Testnet test passes

---

# 52. Mainnet Is Not V1 Done

A successful Testnet V1 does **not** automatically mean Mainnet-ready.

Before a real economic deployment, separately close:

- smart-contract security review/audit,
- production key management,
- production economic calibration,
- final package/value limits,
- routing/provider SLAs,
- background tracking runtime if required,
- operational return/loss processes,
- production settlement/payment architecture,
- postal/courier operating model,
- user-data/compliance review,
- production monitoring and incident response.

These are **Mainnet readiness gates**, not reasons to block building the Initial Testnet Release.

---

# 53. Verified Technical References

The following should be re-checked at deployment time because infrastructure and recommended versions can change.

- [Monad — Deployment Summary for Developers](https://docs.monad.xyz/developer-essentials/summary)
- [Monad — Foundry deployment guide](https://docs.monad.xyz/guides/deploy-smart-contract/foundry)
- [Monad — Oracles](https://docs.monad.xyz/tooling-and-infra/oracles)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Foundry](https://getfoundry.sh/)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271)
- [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192)
- [SIWE / ERC-4361](https://eips.ethereum.org/EIPS/eip-4361)

### Current Monad tooling note

As of this document revision, Monad's official developer summary recommends:

```text
Foundry >= 1.8.0
viem >= 2.40.0
```

with the Monad execution network enabled for the relevant Foundry behavior.

The repository should follow the current official recommendation when implementation begins rather than relying on an older pinned value from an earlier planning draft.

---

# 54. Base Architecture Summary

```text
                        MONOSFER V1
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
      Nuxt                                        Node/Nest
   Frontend/PWA                                   Backend
        │                                           │
 Wallet / UX                               Private Data / API
        │                                    Tracking / Evidence
        │                                           │
        └───────────────────┬───────────────────────┘
                            │
                       Monad / Web3
                            │
        ┌───────────────────┼───────────────────────────┐
        │                   │                           │
    DeliveryHub       SettlementVault             DisputeCourt
        │                   │                           │
 CourierRegistry         Treasury              RandomnessAdapter
        │                   │                           │
 ReputationRegistry  RewardDistributor            Pyth Entropy
        │
     BadgeSBT
```

---

# 55. Final Baseline

For the first version, MONOSFER is:

> A Monad Testnet-first decentralized courier marketplace where customers publish delivery requests, couriers compete through open bids, selected deliveries are economically secured with escrow and delivery-specific collateral, physical pickup/drop-off are verifiable, private location and recipient data remain off-chain, failed deliveries can return safely, disputes can escalate to a decentralized jury, and successful work creates transparent courier reputation, leaderboard status and achievements.

The Initial Release should prioritize:

```text
1. Correct custody
2. Correct state machine
3. Correct failure paths
4. Real delivery UX
5. Reputation
6. Disputes
7. Incentives
8. Polish
```

The project should not be considered successful merely because smart contracts deploy. The first release is successful only when the **entire customer → courier → physical delivery → settlement → reputation** loop works as one coherent product.
