# Rationale for non-JPY oracle staleness candidates

| Item | Value |
| --- | --- |
| Scope | stETH/USD and USDC/USD used by Day-1 sources, plus dwstETH redemption-only ETH/USD and stETH/ETH references |
| Canonical values | [Parameters](../../../Parameters.md) `PRM-ORACLE-002` through `PRM-ORACLE-004`, and `PRM-ORACLE-007` |
| Normative behavior | [Oracle](../../product/spec/Oracle.md) |
| Finalization | [Mainnet Deploy Env Freeze Runbook](../gates/Mainnet-Deploy-Env-Freeze-Runbook.md) |

This is the decision record for selecting candidate values, not the canonical source for deployment inputs or current Chainlink metadata. External metadata can change. Before mainnet broadcast, reacquire it under the runbook and retain freeze evidence with the fork block and risk-owner sign-off.

Selecting or freezing a parameter value does not accept that dwstETH redemption may select a policy-fresh but stale-high stETH/ETH value through `max(direct, derived)`, nor does it accept the tradeoff of failing closed instead of falling back to direct-only when an auxiliary feed fails. Evaluate that acceptance and its evidence separately under [`SYS-RISK-010`](../gates/Mainnet-Launch-Risk-Gate.md#sys-risk-010).

## 1. External metadata snapshot

On 2026-07-26, the Ethereum mainnet Chainlink feed pages were checked against the [Reference Data Directory](https://reference-data-directory.vercel.app/feeds-mainnet.json). This snapshot does not replace the freeze-time check.

| Parameter | Feed | Heartbeat | Deviation | Market |
| --- | --- | ---: | ---: | --- |
| `PRM-ORACLE-002` | ETH/USD | 3,600s | 0.5% | Crypto |
| `PRM-ORACLE-003` | stETH/USD | 3,600s | 1% | Crypto |
| `PRM-ORACLE-004` | USDC/USD | 82,800s | 0.25% | Crypto |
| `PRM-ORACLE-007` | stETH/ETH | 86,400s | 0.5% | Crypto / Pegged Asset |

Official pages: [ETH/USD](https://data.chain.link/feeds/ethereum/mainnet/eth-usd), [stETH/USD](https://data.chain.link/feeds/ethereum/mainnet/steth-usd), [USDC/USD](https://data.chain.link/feeds/ethereum/mainnet/usdc-usd), and [stETH/ETH](https://data.chain.link/feeds/ethereum/mainnet/steth-eth). The stETH/ETH proxy is `0x86392dC19c0b719886221c78AB11eb8Cf5c52812`, has 18 decimals, and was rechecked on 2026-08-28 as product `STETH/ETH-RefPrice-DF-Ethereum-001`.

## 2. Decision rationale

`MainnetPriceFeedBase` uses the strict comparison `block.timestamp - updatedAt < stalenessThreshold`. A threshold equal to the heartbeat can classify a normal periodic update as stale at the boundary.

| Parameter | Candidate |
| --- | ---: |
| `PRM-ORACLE-002` | `7200s` (2h) |
| `PRM-ORACLE-003` | `86400s` (24h) |
| `PRM-ORACLE-004` | `172800s` (48h) |
| `PRM-ORACLE-007` | `90000s` (25h) |

- `PRM-ORACLE-002`: 1-hour heartbeat. Branch 0 uses it only for the redemption reference that protects against a stale-low direct stETH/USD price. Two heartbeats avoid routine fail-closed behavior at the strict `<` heartbeat boundary while bounding protection-feed age.
- `PRM-ORACLE-003`: 1-hour heartbeat. Use the same margin for the dwstETH market leg.
- `PRM-ORACLE-004`: approximately 23-hour heartbeat. A 24-hour threshold has too little room under strict `<`, so use approximately two heartbeats.
- `PRM-ORACLE-007`: 24-hour heartbeat. stETH/ETH is the redemption-protection input that distinguishes a genuine depeg, and auxiliary failure does not fall back to direct-only. Add one hour for submission and inclusion at the strict `<` boundary, yielding 25 hours.

If a candidate changes, update Parameters, deploy env, boundary tests, and fork evidence in the same freeze package.

## 3. Out of scope

- USDT/USD, USDS/USD, and XAU/USD are not Day-1 sources in the current branch map and are outside both this decision and `ORCL-TBD-001`.
- `PRM-ORACLE-005` is re-derived in the Branch 5 (dBTC) activation package after its exact Underlying and feed are selected.
- JPY/USD is assessed separately for shared-dependency blast radius and FX market hours; see [JPY/USD staleness threshold determination](jpyusd-staleness-threshold-determination.md).
