# SPECA Audit Pilot Review (2026-06-19)

## Purpose

As preparation for external JPYdf audit, this pilot extracted SPECA properties from the canonical specs in `documents/jp` and trialed code-location / audit-map generation for DeltaForesight original layers.

## Scope

- Audit freeze commit: `503e46a534b3ce14e1780045314461996209240c`
- Branch label: `codex/extension-boundary-docs`
- Target specs:
  - `documents/jp/spec/dToken.md`
  - `documents/jp/spec/CollateralVault.md`
  - `documents/jp/spec/strategies/Strategy.md`
  - `documents/jp/spec/Oracle.md`

## Results

| Phase | Result | Count / notes |
| --- | --- | --- |
| `doctor` | Pass | Runnable with Claude Code subscription authentication |
| `01b` | Pass | Extracted 68 subgraphs from 4 specs |
| `01e` | Pass | Generated 112 properties |
| `02c` | Pass | Resolved 111 properties to code locations. 109 resolved / 2 not_found |
| `03` High+ subset | Pass | Audit-mapped all 50 items from Critical 5 + High 45. All 50 were `not-a-vulnerability` |
| `04` High+ subset | Pass | All 50 items early-exited because Phase 03 produced no candidate findings. Additional review targets: 0 |
| `03` Medium focused subset | Pass | Audit-mapped 50 resolved Medium items around Oracle / Vault / Strategy loss handling. All 50 were `not-a-vulnerability` |
| `04` Medium focused subset | Pass | All 50 items early-exited because Phase 03 produced no candidate findings. Additional review targets: 0 |
| `03` Remaining resolved tail | Pass | Audit-mapped 10 resolved items from Medium 7 + Low 3. All 10 were `not-a-vulnerability` |
| `04` Remaining resolved tail | Pass | All 10 items early-exited because Phase 03 produced no candidate findings. Additional review targets: 0 |

## 02c not_found

The 2 items came from interpreting abstract Strategy notation as literal function names.

- `PROP-strategy-ist-pre-020`
- `PROP-strategy-ist-post-001`

The cause was SPECA interpreting `emergency*From{Protocol}` / `emergencyFromProtocol`; this is not an implementation gap. The implementation has concrete names per derived Strategy.

- `AaveV3Strategy.emergencyWithdrawFromAave`
- `LidoStrategy.emergencyWithdrawFromLido`
- `ERC4626Strategy.emergencyWithdrawFromERC4626`
- Spec-first: `emergencyWithdrawFromSky`

As a response, `documents/jp/spec/strategies/Strategy.md` now states that `emergencyWithdrawFrom{Protocol}` is abstract notation and not a common `IStrategy` function name.

## 03 High+ subset

SPECA Phase 03 accepts `--min-severity High`, but at present the severity gate does not apply to Phase 03 queue creation. Therefore `outputs-high` was created as a separate output dir, only the 50 Critical / High items were extracted from `02c_PARTIAL_*.json`, and Phase 03 was run on that subset.

The first run saved 47 items as `not-a-vulnerability` and then hit the Claude Code session limit. After session reset, the run resumed, skipped the existing 47 items, and processed the remaining 3 items only.

- `PROP-strategy-ist-inv-028`: collateral-leg failure vs JPY/USD soft-freeze
- `PROP-strategy-ist-inv-029`: WBTC market/canonical min/max pricing
- `PROP-strategy-ist-inv-030`: sUSDS 18-decimal scaling

The remaining 3 items were also classified as `not-a-vulnerability` by SPECA Phase 03. At the initial stop point, manual review and focused Foundry tests were used as temporary coverage, then checked against the resumed SPECA result.

- WBTC / DF standard oracle tests: `forge test --match-contract 'DFPriceFeedTest|DFWBTCPriceFeedTest|DFWBTCPriceFeedProxyIntegrationTest|sUSDSPriceFeedTest|sUSDSPriceFeedProxyIntegrationTest'`
  - Result: 51 tests passed, 0 failed. The regex did not pick up `SUSDS...`, so sUSDS was run separately.
- sUSDS oracle tests: `forge test --match-contract 'SUSDSPriceFeedTest|SUSDSPriceFeedProxyIntegrationTest'`
  - Result: 40 tests passed, 0 failed

Manual review results:

- `PROP-strategy-ist-inv-028`: branch-specific legs such as collateral/USD, USDS/USD, WBTC-BTC, and BTC-USD trigger branch shutdown on stale / answer <= 0 / incomplete round / invalid timestamp. The shared JPY/USD leg enters `lastGoodJpyRate` soft-freeze on the same invalid responses and shuts down after `MAX_JPY_FREEZE_DURATION`. Gas-starved external calls re-revert with `InsufficientGasForExternalCall`.
- `PROP-strategy-ist-inv-029`: WBTC normal path uses `min(WBTC/BTC x BTC/USD, BTC/USD)`, and redemption path uses `max(...)` only inside the 2% band. Depeg outside the 2% band reflects the market leg.
- `PROP-strategy-ist-inv-030`: sUSDS validates in the constructor that the sUSDS token and asset decimals are 18, and composes USDS/USD with canonical rate through `Math.mulDiv(..., 1e18)`.

Additional note: the upstream Liquity v2-derived `MainnetPriceFeedBase` did not sufficiently validate `latestRoundData()` round completeness and timestamp boundaries. Follow-up hardening now treats `roundId == 0`, `answeredInRound < roundId`, `updatedAt == 0`, and `updatedAt > block.timestamp` as invalid responses. This does not bake JPY conversion into the upstream base; it is recorded in the Oracle spec as a minimal modern Chainlink validation diff.

## 03 Medium focused subset

After High+ completed, Medium properties were filtered for Oracle / Vault / Strategy loss handling. The filter matched properties containing `oracle`, `price`, `vault`, `strategy`, `loss`, `writeoff`, `backing`, `buffer`, `redeem`, `withdraw`, `liquid`, `pause`, `allocation`, `allocate`, `yield`, `principal`, or `collateral`. It matched 51 of the 58 Medium properties. Of those, 50 were resolved in `02c`; 1 was the known abstract-function-name `emergencyFromProtocol` not_found case and was excluded.

All 50 targeted items were classified as `not-a-vulnerability` in Phase 03. Phase 04 early-exited all 50 items because there were no candidate findings. Main coverage:

- CollateralVault: redeem dust / pending withdrawal decrement / strategy valuation cache / backingRatio fail-soft / cap-clamped allocate / receiveFromStrategy balance delta / writeoff clamp / yield transfer liquidity reserve / backstop release / pause asymmetry
- Strategy: principal accounting / partial withdrawal / excess sent as yield / writeoff clamp / idle-only emergencyWithdraw / Merkl claim bounds and protected-token rejection / two-step owner / upgrader zero-address checks
- Oracle: source timelock / deviation check / emergency source switch smoke-test / XAUT Day-1 standard path / JPY soft-freeze gas-guard re-revert / backingRatio gas-guard re-revert / placeholder feed behavior

## 03 Remaining resolved tail

The remaining 10 resolved items outside the Medium focused subset (Medium 7 + Low 3) were also run through Phase 03 / Phase 04. They covered dToken cap / decimal conversion / one-shot token info / allowlist + code.length / two-step ownership, Strategy reward sweep balance-delta, Oracle source proposal cancellation, and Merkl zero-address token rejection. All 10 were `not-a-vulnerability`, and Phase 04 early-exited all 10.

This leaves 110 of SPECA `02c`'s 111 properties processed through Phase 03 / 04. The only unprocessed item is `PROP-strategy-ist-pre-020` (`emergencyFromProtocol` abstract-function-name not_found), already triaged as the same abstract-notation mapping issue.

## Triage

- SPECA has not produced any confirmed vulnerability at this point.
- The most useful detection was not a code bug, but that abstract function names in the spec were misread by audit tooling.
- The remaining 3 Oracle high/critical properties completed through resume execution and did not contradict the manual review.
- The Medium focused subset also produced no confirmed vulnerability.
- The remaining resolved Medium / Low tail also produced no confirmed vulnerability.
- The fact that the Phase 03 severity gate does not apply is recorded as an operational note in the SPECA runbook.
- Phase 04 completed by early exit because Phase 03 produced no candidate findings.

## Next Actions

1. Re-map `PROP-strategy-ist-pre-020` after the spec-side abstract notation is corrected, if needed. Do not treat it as an implementation gap in the current state.
2. Do not write SPECA candidate findings directly into the Requirements Verification Ledger. Human triage must first classify them as code / test / spec gaps.
3. `MainnetPriceFeedBase` Chainlink response validation is resolved by follow-up hardening. Future upstream resyncs should preserve this minimal diff.
