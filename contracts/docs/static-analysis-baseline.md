# Static Analysis Baseline — Legacy Contracts

> Established in **P0.1**. Tool: Slither `0.11.6`, 102 detectors, 8 contracts.
> Toolchain: Foundry `1.8.1`. Re-measured under both `1.5.1` and `1.8.1` — the
> baseline is **identical** (48 findings) on both, so the upgrade introduced no
> analysis regression.
> Scope: the pre-V1 contracts frozen under decision **D1**.

> **Measuring the baseline correctly.** Slither reads `slither.config.json` from the
> working directory automatically, so a plain `slither . --exclude-dependencies` now
> applies the legacy `filter_paths` and reports **0 findings**. That is the CI-gated
> view, not the baseline. To reproduce the numbers below, override the filter:
>
> ```bash
> slither . --filter-paths "lib/" --exclude-dependencies
> ```

## Why a baseline exists

Legacy contracts must remain byte-identical until the approved **P5.3** cut-over, so
their findings cannot be fixed yet. Rather than disabling static analysis (which would
leave V1 code ungated) or failing every build (which would make the gate meaningless),
`slither.config.json` filters the legacy paths and CI fails only on findings in code
added from **P0.2** onward.

`filter_paths` entries are removed one by one as legacy files are deleted in P5.3. When
the last entry goes, the whole codebase is gated with no exceptions.

## Accepted baseline — 48 findings

| Severity | Count |
|---|---:|
| High | **0** |
| Medium | 6 |
| Low | 29 |
| Informational | 7 |
| Optimization | 6 |

### By detector

| Severity | Detector | Count |
|---|---|---:|
| Medium | `incorrect-equality` | 3 |
| Medium | `divide-before-multiply` | 2 |
| Medium | `unused-return` | 1 |
| Low | `timestamp` | 14 |
| Low | `reentrancy-events` | 11 |
| Low | `reentrancy-benign` | 4 |
| Informational | `low-level-calls` | 5 |
| Informational | `missing-inheritance` | 2 |
| Optimization | `immutable-states` | 4 |
| Optimization | `constable-states` | 2 |

## Cross-reference with the gap analysis

Several baseline findings independently corroborate items already raised in
`MONOSFER_Contract_Analysis_vs_Baseline_v1.0.md`. They are recorded here as accepted
legacy debt, not as new work:

| Slither finding | Gap-analysis item |
|---|---|
| `low-level-calls` on `Delivera._releasePayment` (3 raw `.call` sends) | sec. 2.3 push-payment settlement, reproduced as **[PoC-D]** |
| `low-level-calls` on `DeliveryEscrow._safeTransfer` / `_safeTransferFrom` | sec. 3.5 unhardened token calls (`data.length == 0` treated as success) |
| `reentrancy-benign` / `reentrancy-events` | sec. 3.4 no `ReentrancyGuard`, CEI violated in `_releasePayment` |
| `immutable-states` on `Leaderboard.owner`, `ReputationBadge.owner`, `RewardDistributor.owner` | sec. 3.7 single-EOA owners with no transfer path |
| `divide-before-multiply` in score math | sec. 2.7 unbounded, unversioned reputation score |
| `unused-return` | Return value of an external call ignored |

## `forge lint` (built-in)

Foundry's own linter expanded substantially in 1.8: legacy warnings went from **3**
under 1.5.1 to **48** under 1.8.1. The build still exits 0, so this does not gate CI,
but it now overlaps meaningfully with Slither and corroborates the same gap-analysis
items:

| Warning | Count | Gap-analysis item |
|---|---:|---|
| `reentrancy-events` | 13 | sec. 3.4 no `ReentrancyGuard`, CEI violated |
| `unsafe-typecast` | 11 | Unchecked narrowing casts in stats/score math |
| `arbitrary-send-eth` | 8 | sec. 2.3 raw `.call` value sends, **[PoC-D]** |
| `unused-return` | 6 | Ignored external call return values |
| `missing-events-access-control` | 5 | sec. 3.7 privileged setters without events |
| `erc20-unchecked-transfer` | 3 | sec. 3.5 unhardened token calls |
| `divide-before-multiply` | 2 | sec. 2.7 score math precision loss |

## Regenerating

Baseline (overrides the committed filter — see the note at the top):

```bash
cd contracts && slither . --filter-paths "lib/" --exclude-dependencies
```

Run the gated (CI-equivalent) analysis with the committed config:

```bash
cd contracts && slither .
```

The gated run must report **0 results**. If it does not, the finding is in new code and
must be fixed or explicitly justified in the pull request.
