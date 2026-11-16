# Oracle Validation And Mainnet Config Differential Review

Date: 2026-06-19

## Verdict

**APPROVE**. No blocker / high / medium finding was found in this diff.

The review targets are the additional Chainlink response validation hardening, the related tests, the Oracle spec sync, and the addition of the mainnet fresh-deploy initial-configuration checklist. No behavior change to Liquity core or reintroduction of the Curve / legacy route was observed.

## Scope

| Area | Files | Review focus |
| --- | --- | --- |
| Oracle validation | `contracts/src/PriceFeeds/MainnetPriceFeedBase.sol` | Whether `roundId == 0`, future `updatedAt`, and zero timestamp are treated as invalid responses |
| DF / WBTC / sUSDS feeds | `contracts/src/PriceFeeds/DFPriceFeedBase.sol`, `DFWBTCPriceFeed.sol`, `sUSDSPriceFeed.sol` | Whether the boundary between branch-local failure and shared JPY leg soft-freeze remains intact |
| Tests | `contracts/test/DFPriceFeed.t.sol`, `DFWBTCPriceFeed.t.sol`, `sUSDSPriceFeed.t.sol`, `ChainlinkOracleMock.sol` | Regression coverage for invalid responses |
| Docs | `documents/jp/development/runbooks/Mainnet-Initial-Configuration-Checklist.md`, Oracle specs, indexes | Completeness of the Day-1 mainnet config freeze and the liquidity policy |

## Findings

None.

## Reviewed Behavior

- `MainnetPriceFeedBase._isValidChainlinkPrice()` treats any response that does not satisfy `roundId != 0`, `answeredInRound >= roundId`, `updatedAt != 0`, and `updatedAt <= block.timestamp` as invalid. As a result, a future timestamp enters the existing oracle failure path before it can revert via a Solidity 0.8 subtraction underflow.
- A branch-local leg failure of collateral/USD, WBTC/BTC, BTC/USD, or USDS/USD transitions to shutdown + `lastGoodPrice`.
- Because JPY/USD is a shared systemic leg, a zero round / stale / future timestamp / bad answer does not trigger a branch shutdown but instead stays in a soft-freeze of the last-good JPY rate.
- `ChainlinkOracleMock` now has a healthy default round, so it returns a production-like healthy response even when existing tests do not explicitly set round fields each time.
- The mainnet checklist limits Day-1 liquidity to **USDC/JPYdf Uniswap v4 only**, putting Curve / Uniswap v3 / non-USDC direct pools / legacy Zapper out of scope.
- The candidate values for Oracle staleness use `Parameters.md` §2-C as the source of truth, and as audit grounds they are accompanied by Chainlink official metadata (ETH/USD heartbeat 1h, JPY/USD heartbeat 24h / Forex, XAU/USD heartbeat 24h / Precious_Metals) and the 2026-06-10 mainnet update-history measurements. The candidate values are 24h for ETH, 48h for 24h-heartbeat branch-local feeds, and 72h for the JPY common leg.

## Residual Risk

- The exact mainnet addresses of Uniswap v4, Chainlink, Aave, and the underlying tokens, as well as the oracle staleness, must be frozen against official sources and a fork dry-run before broadcast. This checklist is a document that enumerates the items to be frozen; it is not evidence of the final address values themselves.
- Heavy invariant / mainnet fork / full-ci are out of scope for this local check. They are handled in the PR CI or the protected branch workflow.
- `forge build` succeeded, but the existing Foundry lint notes / warnings remain. They are not a blocker for this diff, but can be organized as separate audit-prep work.

## Verification

Executed:

```text
forge test --match-path test/DFPriceFeed.t.sol --no-auto-detect
forge test --match-path test/DFWBTCPriceFeed.t.sol --no-auto-detect
forge test --match-path test/sUSDSPriceFeed.t.sol --no-auto-detect
forge test --match-path 'test/*PriceFeedProxyIntegration.t.sol' --no-auto-detect
forge test --match-path test/PriceFeedProxyRealFeedIntegration.t.sol --no-auto-detect
forge build --no-auto-detect
git diff --check --ignore-submodules=all
```

Results:

- `DFPriceFeed.t.sol`: 42 passed
- `DFWBTCPriceFeed.t.sol`: 11 passed
- `sUSDSPriceFeed.t.sol`: 32 passed
- WBTC / sUSDS proxy integration: 16 passed
- real-feed proxy integration: 7 passed
- `forge build`: successful with existing warnings
- `git diff --check`: clean

## Recommendation

This diff can be turned into a PR. Before merge, confirm the normal CI passes, and before mainnet broadcast, fill in the checklist's `Freeze checks` / `Go / No-Go` as separate evidence.
