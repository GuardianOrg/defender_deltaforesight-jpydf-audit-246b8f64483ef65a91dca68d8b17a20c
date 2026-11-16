# ChainDefenders Audit Prep - Contracts / Backend

Date: 2026-06-17
Baseline: `6f77b1aa8f212f415981c5ce256523a04016433e` (`[codex] Improve liquidator priority and observability`)
Branch checked: `develop`

## Scope

- Contracts: `contracts/src` (132 Solidity files), excluding `contracts/lib`, tests, scripts, generated artifacts.
- Backend-like services: `bots/liquidator` (6 Rust source files).
- Ops backend scripts: `frontend/ops/src` and `frontend/ops/scripts` (27 TypeScript files).
- Out of scope for this pass: user frontend UX, admin console UI, generated `dist`, dependency source under `lib` / `node_modules`.

## Changes Made During Prep

- Moved `MockStrategy` out of production contracts:
  - from `contracts/src/Strategies/MockStrategy.sol`
  - to `contracts/test/TestContracts/MockStrategy.sol`
  - updated test imports in `CollateralVaultStrategy.t.sol` and `InvariantPushModel.t.sol`.
- Replaced unchecked ERC20-style transfer paths with `SafeERC20`:
  - WETH gas compensation movement in `BorrowerOperations` and `TroveManager`.
  - JPYdf pull/send paths in `RedemptionHelper`.
  - JPYdf/WETH paths in `BaseZapper`, `WETHZapper`, `GasCompZapper`, `LeverageWETHZapper`.
  - JPYdf transfer paths in the legacy exchange modules, including `UniV3Exchange`.

## Checks Run

### Contracts

- `forge build`
  - Result: pass.
  - Remaining compiler warnings are test-only unused-variable / mutability warnings.

- `forge test`
  - Result: 1202 passed, 3 failed, 4 skipped, 1209 total.
  - Failures are external/fork setup issues:
    - `ExchangeHelpersMainnetTest`: deployment JSON missing `.jpydfToken`.
    - `OracleMainnet`: RPC HTTP 408 free-tier timeout.
    - `ZapperLeverageMainnet`: RPC HTTP 500 temporary provider error.
  - This should be fixed before audit CI is treated as green.

- Targeted post-change tests:
  - `forge test --match-path test/borrowerOperations.t.sol`: 11 passed.
  - `forge test --match-path test/troveManager.t.sol`: 20 passed.
  - `forge test --match-path test/RedemptionHelper.t.sol`: 5 passed.
  - `forge test --match-path test/CollateralVaultStrategy.t.sol`: 103 passed.
  - `forge test --match-path test/CollateralYieldZapper.t.sol`: 19 passed.
  - `forge test --match-path test/InvariantPushModel.t.sol`: 4 invariant tests passed.

- Slither:
  - Initial production-style run: 249 findings.
  - Final run after cleanup: 221 findings.
  - High findings reduced from 33 to 5.

Final Slither breakdown:

| Impact | Count |
| --- | ---: |
| High | 5 |
| Medium | 60 |
| Low | 55 |
| Informational | 84 |
| Optimization | 17 |

Top detector groups:

| Detector | Impact | Count |
| --- | --- | ---: |
| `unused-return` | Medium | 54 |
| `calls-loop` | Low | 43 |
| `dead-code` | Informational | 42 |
| `immutable-states` | Optimization | 17 |
| `unused-import` | Informational | 14 |
| `unused-state` | Informational | 10 |
| `missing-zero-check` | Low | 9 |
| `divide-before-multiply` | Medium | 6 |
| `low-level-calls` | Informational | 6 |
| `arbitrary-send-eth` | High | 3 |
| `arbitrary-send-erc20` | High | 2 |

### Backend / Ops

- `cargo fmt --check` in `bots/liquidator`: pass.
- `cargo test` in `bots/liquidator`: 35 passed.
- `cargo clippy --all-targets -- -D warnings` in `bots/liquidator`: pass.
- `pnpm -C frontend/ops build`: pass, with Vite chunk-size warning only.
- `pnpm -C frontend/ops test:public-stats`: pass.
- `pnpm -C frontend/ops test:treasury-ledger`: pass.
- `pnpm -C frontend/ops test:interest-router`: pass.

## Remaining Audit Prep Items

### P0 - CI / RPC Determinism

Mainnet/fork tests currently fail because they depend on unstable external RPC and deployment JSON shape. This is audit-blocking because it makes a red test suite indistinguishable from a protocol regression.

Required:

- Use a paid/pinned archive RPC for fork tests, not a free-tier endpoint.
- Split fork tests into a separate CI job with explicit env requirements.
- Add a preflight check that fails early with a clear message when deployment JSON lacks required keys such as `.jpydfToken`.
- Store fork block numbers and expected deployment file path in one documented place.

### P1 - Remaining High Slither Findings

Remaining High findings:

- `BorrowerOperations.closeTrove`: WETH gas compensation is transferred from `gasPoolAddress` to the close receiver.
- `TroveManager._sendGasCompensation`: WETH gas compensation is transferred from `gasPoolAddress` to the liquidator.
- `WETHZapper._adjustTrovePost`: raw ETH is sent to the configured receiver.
- `LidoStrategy._claimLidoWithdrawals`: ETH received from Lido is immediately wrapped to WETH.
- `LidoStrategy._doDeposit`: ETH is submitted to Lido with a referral address.

Current assessment:

- The two WETH `transferFrom(gasPoolAddress, ...)` findings are intended gas compensation flows, but should be documented with the GasPool approval invariant.
- The zapper raw ETH send is intended receiver routing, but should remain covered by manager/receiver authorization tests.
- Lido findings are expected protocol integration calls, but the audit package should explain why destination/referral are controlled and why reentrancy risk is bounded.

### P1 - Medium Findings Worth Triage

- `unused-return` still flags approvals, oracle tuple returns, external protocol return values, and router/exchange calls.
  - Approval return values should either use `SafeERC20` or be explicitly documented as known token/protocol behavior.
  - Exchange/router ignored return values should be checked where the return value represents amount received.
- `divide-before-multiply` includes TroveManager redemption and redistribution math.
  - These may be deliberate Liquity-style rounding-error accounting patterns, but should be documented with rounding direction and invariant tests.
- `calls-loop` covers redemption, hint helper, vault strategy reads, and helper view loops.
  - Need document boundedness and gas expectations, especially strategy list size and `_maxIterationsPerCollateral`.

### P2 - Hygiene

- Unused imports in production interfaces/contracts should be removed in a follow-up cleanup PR.
- Metadata SVG/JSON helpers create `dead-code` noise. If retained for composability, suppress or document; otherwise remove unused helpers.
- `contracts/lib/V2-gov` shows as dirty with 0-line diff. Normalize submodule state before opening the audit PR.

## Mock / Placeholder Sweep

Production `contracts/src` no longer contains `MockStrategy`.

Remaining production hits are placeholder-branch terminology, not mock behavior:

- deferred-underlying placeholder branches in `CollateralVault`, `DToken`, price feed placeholder contracts, and constants.
- these are protocol features and should be documented as inert branches with cap/debt disabled until activation.

Only ops-side test fixture hit:

- `frontend/ops/scripts/verify-reads.ts` describes seeded fixture assertions.

## Secret / RPC Surface

File-name scan for RPC/API/private-key style strings found only config templates, docs, scripts, tests, and frontend env wiring. No raw secret value was printed in this report.

Before audit handoff:

- ensure `.env` is not committed;
- confirm fork RPC values are CI secrets;
- document allowed public RPC fallback behavior separately from production RPC requirements.

## Recommended Next Steps

1. Make fork/mainnet tests deterministic and green.
2. Add a short audit-facing note for gas compensation and raw ETH receiver flows.
3. Triage remaining `unused-return` findings into real fixes vs documented false positives.
4. Remove low-risk unused imports from production contracts.
5. Run a full `forge test` again after RPC/deployment JSON cleanup.
6. Package this report plus Slither JSON artifact paths for ChainDefenders.
