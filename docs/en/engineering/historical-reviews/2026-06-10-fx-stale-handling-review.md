# FX stale handling differential review (2026-06-10)

## Executive summary

| Severity | Count |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

**Overall risk**: Low  
**Recommendation**: Approve this incremental change.

Scope: commit `fe33863` (`Document FX stale handling precedent`) on PR #25. This review covers only the FX weekend/staleness documentation and test additions, not the full PR diff.

## What changed

| File | Risk | Notes |
| --- | --- | --- |
| `contracts/test/DFPriceFeed.t.sol` | Low | Adds JPY/USD weekend-close and exact-boundary tests for standard DF feeds. |
| `contracts/test/sUSDSPriceFeed.t.sol` | Low | Adds the same coverage for the composite sUSDS feed. |
| `contracts/test/sUSDSPriceFeedProxyIntegration.t.sol` | Low | Confirms the proxy path does not shut down when JPY/USD is stale only within threshold. |
| `documents/jp/Oracle.md` | Low | Documents the no-calendar / `updatedAt`-based FX handling and EUR CDP precedent. |
| `documents/jp/Parameters.md` | Low | Aligns oracle staleness parameters with the same precedent. |

No production Solidity logic was modified in this commit.

## Findings

No blocking findings.

The tests are consistent with the implementation in `MainnetPriceFeedBase`: Chainlink responses are valid only when `block.timestamp - updatedAt < stalenessThreshold`. The new boundary tests correctly assert that an age exactly equal to `JPY_STALENESS` is stale.

## Coverage

The incremental tests cover:

- Standard DF feeds: JPY/USD updated 60h ago remains primary, while exactly 72h is stale.
- Composite sUSDS feed: same 60h healthy / 72h stale behavior.
- `PriceFeedProxy` path: JPY/USD weekend-close age within threshold does not trigger branch shutdown.

Verification run:

```text
forge test --offline --match-path 'test/*PriceFeed*.t.sol'
160 passed, 0 failed, 0 skipped
```

`git diff HEAD^..HEAD --check` also passed.

## Residual risk

The production value is still a parameter choice. Because the implementation uses a strict `< stalenessThreshold` comparison, a configured threshold of exactly `72 hours` means an answer aged exactly 72h is invalid. Final mainnet deployment should choose the JPY/USD threshold from observed Chainlink update history, with explicit buffer for normal weekends, holidays, and Monday-open update delay.
