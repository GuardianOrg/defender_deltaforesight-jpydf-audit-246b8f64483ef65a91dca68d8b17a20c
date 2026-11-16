# Contract Doc Drift / Audit Readiness Review - 2026-06-19

> Target: the `contracts/src` production surface, deploy/config wiring, JP source-of-truth docs, and the main ledgers / runbooks.
> Policy: do not touch Liquity core accounting; check the legacy / out-of-Day-1-scope surface unnecessary for a fresh deploy, and doc drift.

## Executive Summary

| Item | Verdict | Notes |
| --- | --- | --- |
| Doc / implementation drift | No blocker after fixes | Synced the descriptions and implementation for Day-1 liquidity, non-adoption of Curve/Balancer/v3, bridge dormant, and no DFT staking |
| Contract audit readiness | Conditional | build / focused tests are green. `UniV4Exchange` is included in Day-1 audit scope. Slither findings and final deploy evidence need triage before audit handoff |
| Dead / legacy contract surface | Mostly clean | Curve / Balancer / Uniswap v3 / flash-close / fail-fast exchange placeholders are absent from the production contract ABI |
| Day-1 audit scope | Includes `UniV4Exchange` | `UniV4Exchange` and the dormant bridge surface are not "unused" but audit scope. v4 route production enablement is judged separately via route config / fork evidence / manifest gate |

## Fixes Applied In This Pass

- Hardened `JpydfToken.setBranchAddresses` / `setCollateralRegistry` to nonzero + contract-only.
- Added `CORE-MOD-009` and the Core verification ledger, documenting prevention of token one-shot wiring misconfiguration.
- Added `JpydfTokenTest::test_CoreAddressRegistrationRequiresContracts`.
- Removed the old `Bold` notation from the v4 adapter test names / variables in `ExchangeApprovalHygieneTest` and unified them to `Jpydf`.
- Updated the stale result of the bridge readiness review to reflect the event payload / deploy resolver / core address hardening.
- Added `launchEvidence` to the deploy manifest, making machine-readable: no bridge adapter, no Curve / Balancer / Uniswap v3 direct JPYdf pool, no non-USDC direct JPYdf pool, and the JPYdf/USDC v4 route status.
- In `deployment-manifest-to-app-env.ts` and `mainnet-preflight.ts`, validated the Day-1 `launchEvidence` so that consumer env / handover evidence is not produced from a dangerous manifest.
- Added `envFreeze` and per-branch `dfYield` freeze fields to the deploy manifest, making bridge admin, treasury, InterestRouter recipient / owner, oracle feed / staleness, and strategy weight / cap verifiable with `mainnet-preflight --manifest`.
- Added a `mainnet-fork-evidence` helper so that external preflight, deploy, manifest preflight, app env generation, handover prepare, and pending verify can be run in the same fork state on a pinned anvil fork.
- Hardened the `FixedAssetReader` constructor to reject a zero SSTORE2 pointer.
- Added aggregate debt / weighted debt / batch management fee update events to `ActivePool`, promoting the Slither `events-maths` finding to a monitoring requirement.
- As audit grounds for Oracle staleness, recorded the Chainlink official metadata (heartbeat / deviation / marketHours) and the measured 2026-06-10 mainnet update history together in `Parameters.md` §2-C / `Oracle.md` ORCL-TBD-001 / the deploy runbook.

## Drift Check Matrix

| Area | Result | Evidence / Notes |
| --- | --- | --- |
| Day-1 DEX liquidity | PASS | The source of truth is only the **JPYdf/USDC Uniswap v4** after JPYdf deploy / issuance. Curve, Balancer, Uniswap v3, and USDT/USDS/WETH/XAUT direct JPYdf pools are not created |
| Curve / Balancer / v3 / flash loan close | PASS(contract) | No active adapter / callback / provider in `contracts/src` / deploy wiring. Places in dated reviews where old terms remain are point-in-time evidence, not the source of truth |
| `stake` / DFT staking | PASS(contract) | The contract's `stake` is Trove redistribution accounting or Lido staking. The Day-1 DFT token / staking contract / UI are out of active scope |
| Bridge | CONDITIONAL | `JpydfToken` has a dormant bridge-ready surface. The manifest `launchEvidence` / `envFreeze` schema gate is already added. For the final mainnet deploy, `bridgeMinterCount == 0` / no pending proposal / no adapter connection / frozen bridge admin must be attached with the actual manifest |
| Oracle staleness evidence | CONDITIONAL | Per Chainlink official metadata: ETH/USD heartbeat 1h, JPY/USD heartbeat 24h / Forex, XAU/USD heartbeat 24h / Precious_Metals. Day-1 candidates are ETH 24h, daily-heartbeat branch-local feeds 48h, JPY common leg 72h. The manifest `envFreeze` / `dfYield` gate is already added. For the final deploy, attach the `mainnet-preflight` output at the pinned fork block |
| `UniV4Exchange` / `IExchange` | IN SCOPE | Not a current CYZ constructor dependency, and there is no swap-backed entrypoint, but it is included in audit scope as the Day-1 standard JPYdf/USDC v4 route adapter. Production route enablement is after route config / fork evidence / manifest gate |
| Frontend Multiply | CONDITIONAL(frontend) | route is gated / tx flows fail-fast, but frontend modules remain. The contract ABI is already removed. For strict dead-code reduction, remove it in a separate frontend cleanup |

## Slither Snapshot

Command:

```bash
slither . --exclude-dependencies
```

Latest local rerun after this triage reached detector output:

```bash
slither . --exclude-dependencies --json /private/tmp/jpydf-slither-after-triage-20260619.json
```

Result: exit 255 with **108 findings**. Exit 255 is expected when Slither emits findings. Aderyn was not available in the local toolchain (`aderyn not found`), so this pass treats Slither + manual code/spec cross-check as the P1 triage input.

This pass removed 2 findings from the 110-finding baseline: `events-maths` on ActivePool aggregate accounting and `missing-zero-check` on `FixedAssetReader.pointer`.

Detector breakdown:

| Detector | Impact | Count | Triage |
| --- | --- | ---: | --- |
| `arbitrary-send-erc20` | High | 2 | GasPool WETH compensation, accepted with invariant note |
| `arbitrary-send-eth` | High | 2 | Lido ETH unwrap/submit/claim wrap path, accepted with Lido-specific spec evidence |
| `divide-before-multiply` | Medium | 6 | Metadata sizing / display formatting / Liquity-style redemption and redistribution rounding, accepted/documented |
| `unused-return` | Medium | 14 | Intentional tuple-field discard, no unchecked external call return |
| `missing-zero-check` | Low | 5 | Ownership cancellation and Lido referral zero remain intentional |
| `calls-loop` | Low | 42 | Bounded/read-helper/Liquity redemption loops, accepted/documented |
| `assembly` / `pragma` / `costly-loop` / `cyclomatic-complexity` / `dead-code` / `unused-state` / `immutable-states` | Info/Optimization | 37 | Informational or deliberate storage/core compatibility choices |

Current triage:

| Detector group | Status |
| --- | --- |
| `arbitrary-from-in-transferfrom` / `arbitrary-send-erc20` on GasPool WETH compensation | Accepted design. GasPool is a functionless WETH vault that grants allowance only to branch BorrowerOperations / TroveManager at construction. BO/TM are the sole outflow logic and can only refund/pay the fixed `ETH_GAS_COMPENSATION` as part of close/liquidation flows. Spec evidence: GasPool section in `Liquity-v2-Core-Spec.md` |
| `arbitrary-send-eth` on Lido deposit / WETH wrapping | Accepted design. ETH is sent only to fixed WETH/Lido/WithdrawalQueue integrations; `referral` may be zero and is not a transfer recipient. `claimLidoWithdrawals` updates pending request state before external claim and wraps the measured ETH delta into protocol-owned idle WETH. Spec evidence: `LidoStrategy.md` LIDO-FR-003/007, LIDO-SEC-002/004/006, reentrancy note |
| `missing-zero-check` | Partially fixed. `FixedAssetReader.pointer` now rejects zero. `transferOwnership(0)` remains intentional cancellation of pending owner in DToken / Strategy / InterestRouter. Lido `referral` remains intentionally zero-allowed |
| `events-maths` on ActivePool aggregate accounting | Fixed. Added `ActivePoolAggRecordedDebtUpdated`, `ActivePoolAggWeightedDebtSumUpdated`, `ActivePoolAggBatchManagementFeesUpdated`, `ActivePoolAggWeightedBatchManagementFeeSumUpdated`; added CORE-AP-EVT-008..011 |
| `unused-return` | Accepted. Findings are tuple destructuring discards (`(price,)`, `(roundId, answer, updatedAt, answeredInRound)`, etc.), not ignored bool-returning token transfers. Token transfers use `SafeERC20` where applicable |
| `dead-code` on `Types/TroveId.sol` helpers | Accepted. Liquity core type utilities; touching core for cosmetic removal is not worth audit churn |
| `unused-state` on `__gap` variables | False positive. Keep storage gaps for upgradeable storage layout |
| `divide-before-multiply` / `calls-loop` in core redemption / redistribution | Accepted. Redemption/redistribution rounding and bounded iteration are Liquity-style accounting design; user-facing redemption also takes `_maxIterationsPerCollateral`. Read helpers and Strategy status loops are bounded by branch/strategy arrays |

## Verification Run

```bash
forge test -vv --match-contract JpydfTokenTest
forge test -vv --match-contract CollateralYieldZapperTest
forge test -vv --match-contract DeployLiquity2StrategySelectorTest
forge test -vv --match-contract ExchangeApprovalHygieneTest
forge test --match-contract SlitherTriageHardeningTest
forge test --match-contract InterestRateAggregate
forge test -vv --no-match-contract 'Mainnet|Invariant|Anchored|E2E|Initiative'
pnpm -C contracts exec tsc --noEmit --pretty false
pnpm -C contracts exec tsx utils/deployment-manifest-to-app-env.ts <manifest-with-launchEvidence>
pnpm -C contracts exec tsx utils/mainnet-preflight.ts --manifest <manifest-with-launchEvidence-and-envFreeze> --manifest-only
pnpm -C contracts --silent mainnet-fork-evidence --help
forge build
git diff --check
slither . --exclude-dependencies
```

Results:

- `JpydfTokenTest`: 11 passed
- `CollateralYieldZapperTest`: 16 passed
- `DeployLiquity2StrategySelectorTest`: 16 passed
- `ExchangeApprovalHygieneTest`: 5 passed
- fast Foundry PR suite: 1180 passed, 0 failed, 1 skipped
- contracts TypeScript check: passed
- deployment manifest app env conversion: passed for Day-1 `launchEvidence`; rejected nonzero bridge minter evidence
- `mainnet-preflight --manifest-only`: passed for mainnet-shaped Day-1 `launchEvidence`; rejected nonzero Uniswap v3 direct JPYdf pool evidence
- `mainnet-preflight --manifest-only`: passed for mainnet-shaped `envFreeze` / `dfYield` freeze evidence; rejected JPY/USD staleness mismatch
- `mainnet-fork-evidence --help`: passed. Full fork evidence requires production holder env and pinned mainnet RPC.
- `SlitherTriageHardeningTest`: 2 passed
- `InterestRateAggregate`: 91 passed
- `slither` after triage: 108 findings; `events-maths` absent; `FixedAssetReader.pointer` missing-zero absent
- `forge build`: passed with existing test-only warnings / lint notes
- `git diff --check`: passed
- `slither`: accepted-risk groups remain as listed above; final audit handoff should attach the JSON artifact / CI rerun output

## Remaining Audit-Ready Gates

| Priority | Gate | Required action |
| --- | --- | --- |
| P0 | Final deploy evidence | Schema / consumer gate implemented via manifest `launchEvidence` plus `envFreeze`. Final mainnet manifest must still be attached proving bridge minter count 0, no pending bridge proposal, no bridge adapter, no Curve/v3/Balancer/non-USDC direct pool, JPYdf/USDC v4 route status, and frozen bridge admin / treasury / InterestRouter |
| P0 | Mainnet env freeze | Manifest `envFreeze` / `dfYield` gate implemented for `DF_BRIDGE_ADMIN`, treasury, InterestRouter, oracle staleness, and strategy config. Final mainnet package must still attach actual manifest sha256, Chainlink metadata snapshot, and pinned `mainnet-preflight` output for ETH 24h / JPY 72h / XAU 48h rationale |
| P1 | Slither triage | Code/docs triage applied. Remaining gate is CI/container rerun of Slither on this branch and reviewer signoff on accepted-risk groups |
| P1 | Full CI / fork determinism | Stateful fork evidence runner implemented. Remaining gate is running `mainnet-fork-evidence` with production holder env + pinned mainnet RPC and attaching the evidence directory; do not treat external RPC failures as green audit evidence |
| P2 | Frontend dead-code cleanup | If strict "no dormant frontend modules" is desired, remove Multiply modules instead of relying only on route gate / fail-fast tx flows |
