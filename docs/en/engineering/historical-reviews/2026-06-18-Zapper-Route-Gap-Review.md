# Zapper Route Gap Review

## Executive Summary

| Severity | Count |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 1 |

**Overall Risk:** Medium

**Recommendation:** Conditional approve for base dToken / dUSDS UX. Keep swap-backed dToken flows disabled until route-specific production gates are closed.

**Key Metrics:**
- Files reviewed: Zapper spec / verification ledger / `CollateralYieldZapper` / `SkyUsdcSUsdsYieldZapper` / `UniV4Exchange` / frontend close and multiply gates.
- Security regressions detected: 0 in reviewed scope.
- Main remaining blockers: production Sky USDC adapter if USDC ingress is enabled; production Uniswap v4 route if collateral-funded close / Multiply is enabled.

## Scope

This review classifies open Zapper TBD items by whether they are required for the next production path:

- Base dToken path: open / add / withdraw / close-with-JPYdf through `CollateralYieldZapper`.
- dUSDS ingress path: `USDC -> USDS -> sUSDS -> dUSDS` through `SkyUsdcSUsdsYieldZapper`.
- Swap-backed path: collateral-funded close / repay-with-collateral / Multiply through `IExchange`.

## Findings

### Medium: Uniswap v4 route is not a production route yet

`UniV4Exchange` adds a v4-compatible `IExchange` adapter with Permit2 allowance cleanup and single-pool Universal Router actions. The focused adapter tests cover the local hygiene surface, but production enablement still depends on branch-specific route config, hook policy, route selector wiring, manifest/deploy configuration, and fork tests against the selected router/pool setup.

Impact: enabling `closeTroveFromCollateral` / collateral-funded repay / Multiply before those gates are closed can route users through the wrong pool, an unreviewed hook, or a route with insufficient final-leg JPYdf liquidity.

Decision: conditionally required only for swap-backed dToken flows. It is not required for open / add / withdraw / close-with-JPYdf. Keep `DFDisabledExchange` and frontend dToken flow gates until route selection is explicit.

### Medium: dUSDS reverse route is absent, but only needed for disabled flows

The implemented Sky route is ingress only: `USDC -> USDS -> sUSDS -> dUSDS`. Parent Zapper withdraw / close-with-JPYdf returns the branch Underlying, which is sUSDS. There is no implemented `sUSDS -> USDS -> USDC -> JPYdf` reverse route.

Impact: dUSDS cannot safely support collateral-funded close / repay-with-collateral / Multiply unless that reverse route is designed and tested.

Decision: not an MVP blocker because dToken branch repay-with-collateral and Multiply are already blocked in the frontend. Direct sUSDS entry plus USDC ingress are enough for base borrow/add/withdraw/close-with-JPYdf.

### Low: Several TBD rows were stale rather than unimplemented

`ZAP-TBD-001`, `ZAP-TBD-002`, `ZAP-TBD-006`, and `ZAP-TBD-007` were still marked as open, but current implementation/spec policy already resolves them:

- `requestId` is returned and Vault events remain the canonical delayed-redeem source.
- adjust collateral increase already uses the `deposit` return value.
- permit-incompatible tokens use the non-permit approve path.
- zombie Trove adjust entrypoints are implemented under `ZAP-FR-009`.

Decision: update the spec and ledger so the remaining open items reflect actual product / route decisions, not stale uncertainty.

## Production Gates

Required before enabling USDC ingress for dUSDS:

- Implement and audit the concrete `IUsdcUsdsConverter` against the selected Sky PSM / LitePSM / alternative route.
- Verify pause / halt / rate-limit / fee behavior and USDC 6-decimal to USDS 18-decimal accounting.
- Add fork coverage for the real route.

Required before enabling swap-backed dToken flows:

- Choose v3 / v4 / hybrid route per asset and branch.
- Fix the `USDC/JPYdf` final leg and pool/hook policy. A pool key does not need to be globally fixed, but any runtime route must be constrained by config or allowlist.
- Add fork tests for selected routes.
- Wire deploy script, manifest, frontend route selector, and ops monitoring.

Not required for the base path:

- sUSDS reverse route.
- dToken Multiply.
- WETH native ETH collateral input.
- Zapper-specific `requestId` event.

## Verification

Evidence already available in this worktree:

- `forge test --match-path test/ExchangeApprovalHygiene.t.sol` passed for v4 adapter hygiene and existing exchange approval cleanup.
- `forge test --match-path test/CollateralYieldZapper.t.sol --match-test 'test_SkyRoute'` passed for Sky ingress route unit coverage.
- `forge build` passed.

## Limitations

This review does not choose mainnet pool addresses or a Sky production adapter. Those decisions require current protocol addresses, liquidity checks, and fork tests against the selected mainnet route.
