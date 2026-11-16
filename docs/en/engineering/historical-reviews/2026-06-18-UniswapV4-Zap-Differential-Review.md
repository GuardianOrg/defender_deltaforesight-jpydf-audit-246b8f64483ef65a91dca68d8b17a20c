# Uniswap v4 Zap Differential Review (2026-06-18)

## Executive Summary

| Severity | Count | Status |
| --- | ---: | --- |
| Critical | 0 | - |
| High | 0 | - |
| Medium | 0 | - |
| Low | 1 | Fixed in this session |

**Overall Risk:** Medium for production activation, Low for the adapter-only checked-in scope.

**Recommendation:** Conditional. `UniV4Exchange` / `DFUniV4Exchange` can remain as an unconnected adapter foundation. Do not wire it into production zappers until `ZAP-TBD-010` closes: branch route config, hook policy, route selector, deploy manifest, frontend route selection, and fork/integration validation against canonical Universal Router + Permit2.

**Key Metrics:**
- Files analyzed: 8 changed/new files plus `IExchange` callers and prior DF exchange hardening history.
- Test coverage added: v4 exact-input, exact-output, Permit2 allowance reset, ERC20-to-Permit2 allowance reset, uint128 bounds, constructor guards, and v4 calldata action encoding.
- Blast radius: currently isolated because the adapter is not deploy-wired; high once used by `IExchange` zappers.
- Security regressions detected: none after the hardening fix below.

## What Changed

| File | Risk | Notes |
| --- | --- | --- |
| `contracts/src/Zappers/Modules/Exchanges/UniV4Exchange.sol` | High | New value-transfer adapter using Universal Router `V4_SWAP` and Permit2. |
| `contracts/src/Zappers/Modules/Exchanges/DFUniV4Exchange.sol` | Medium | Deploy wrapper matching existing DF exchange wrapper pattern. |
| `contracts/src/Zappers/Modules/Exchanges/UniswapV4/*` | Medium | Minimal ABI/constant surface for v4 router, Universal Router, and Permit2. |
| `contracts/test/ExchangeApprovalHygiene.t.sol` | Low | v4 mocks and focused approval/calldata/bounds tests. |
| `documents/jp/spec/Zapper.md` | Low | `ZAP-TBD-010` and v4 route notes. |
| `documents/jp/development/ledgers/Requirements-Verification-Ledger.md` | Low | `ZAP-TBD-010` registry row. |

## Fixed During Review

### Low: Output Delta Calculation Could Panic Instead of Returning the Adapter Error

**File:** `contracts/src/Zappers/Modules/Exchanges/UniV4Exchange.sol:91`

**Issue:** The first implementation computed output deltas with direct subtraction. If a bad router/hook path ever reduced an existing adapter balance before the minimum-output check, Solidity underflow would emit a panic instead of the adapter's `UniV4Exchange__InsufficientOutput` error. This was not a fund-loss path because the transaction would revert, but it made the failure mode less deterministic.

**Fix:** `swapFromJpydf` and `swapToJpydf` now use `_balanceIncrease(...)`, returning zero when the current balance is not above the initial balance, then applying the existing minimum-output check.

**Coverage:** Existing exact-input/exact-output tests still pass after the change.

## External Call Safety Review

| Area | Result |
| --- | --- |
| ERC20 transfers | Direct adapter transfers use `SafeERC20`; missing-return tokens are handled at this boundary. |
| Allowance pattern | ERC20 allowance to Permit2 is set per swap with `forceApprove(amount)` and cleared to zero. Permit2 allowance to Universal Router is also cleared to zero. |
| Exact-output leftovers | Partial spend returns unused input through `LeftoversSweep`; tests cover repeated swaps with zero-first tokens. |
| Router trust boundary | Universal Router and Permit2 are immutable constructor inputs and must be canonical deployment addresses in production config. |
| Hook trust boundary | Hook address is part of a v4 pool key, so production routes that allow hooks must constrain them by deploy config or allowlist before wiring. |
| Fee-on-transfer/rebasing tokens | Not supported as generic collateral behavior. Production route should remain limited to reviewed listed tokens/pools. |

## Test Coverage Analysis

Covered by `forge test --match-path test/ExchangeApprovalHygiene.t.sol`:

- `test_UniV4SwapFromBoldClearsResidualPermit2AndTokenAllowancesForZeroFirstTokens`
- `test_UniV4SwapToBoldReturnsActualOutputAndClearsPermit2AndTokenAllowances`
- `test_UniV4SwapToBoldRevertsWhenAmountExceedsV4Uint128`
- `test_UniV4SwapFromBoldRevertsWhenAmountExceedsV4Uint128`
- `test_UniV4ConstructorRejectsInvalidAddressesAndIdenticalTokens`

Remaining gaps before production:

| Gap | Risk | Required Before Wiring |
| --- | --- | --- |
| No fork test against canonical Ethereum Universal Router + Permit2 | High | Add a fork or integration test once concrete route config is selected. |
| No deploy/manifest/frontend selector wiring | Medium | Implement only after route policy is finalized. |
| No hook policy enforcement in deploy layer | High | Add deploy-time assertions or config validation. |
| No route decision for XAUT / USDT / WETH / Sky dUSDS reverse path | Medium | Close `ZAP-TBD-010`. |

## Blast Radius Analysis

The new adapter is not currently referenced by deploy scripts. If wired as an `IExchange`, affected paths include:

| Entry Area | Call Pattern | Impact |
| --- | --- | --- |
| `CollateralYieldZapper.closeTroveFromCollateral` | `exchange.swapToJpydf(...)` | Underlying to JPYdf close path. |
| `LeverageLSTZapper` / `LeverageWETHZapper` | `swapFromJpydf` and `swapToJpydf` | Leverage open/adjust paths. |
| `GasCompZapper` / `WETHZapper` | `swapToJpydf` | Close/repay helper flows. |

Production activation therefore remains a high-blast-radius config change even though the current code addition is isolated.

## Source Cross-Check

The adapter ABI and constants were checked against current Uniswap sources:

- v4 single-hop params include `minHopPriceX36`: https://raw.githubusercontent.com/Uniswap/v4-periphery/main/src/interfaces/IV4Router.sol
- v4 actions: `SWAP_EXACT_IN_SINGLE`, `SWAP_EXACT_OUT_SINGLE`, `SETTLE_ALL`, `TAKE_ALL`: https://raw.githubusercontent.com/Uniswap/v4-periphery/main/src/libraries/Actions.sol
- Universal Router `V4_SWAP = 0x10`: https://raw.githubusercontent.com/Uniswap/universal-router/main/contracts/libraries/Commands.sol
- Permit2 allowance API: https://raw.githubusercontent.com/Uniswap/permit2/main/src/interfaces/IAllowanceTransfer.sol

## Verification

Commands run from `contracts/`:

```bash
forge fmt --check src/Zappers/Modules/Exchanges/UniV4Exchange.sol test/ExchangeApprovalHygiene.t.sol
forge test --match-path test/ExchangeApprovalHygiene.t.sol
forge build
```

Results:

- Focused test: 12 passed, 0 failed.
- Build: successful. Foundry emitted existing lint notes across the repo; no compile errors.

## Recommendation

Keep this as the v4 adapter foundation. The next implementation step should be production wiring behind explicit config, not implicit replacement of v3:

1. Define branch-level route config for `USDC/JPYdf` and each underlying asset.
2. Add hook policy and canonical Universal Router / Permit2 address assertions.
3. Add fork/integration tests for the selected pools.
4. Wire deploy manifest and frontend route selector only after those checks pass.
