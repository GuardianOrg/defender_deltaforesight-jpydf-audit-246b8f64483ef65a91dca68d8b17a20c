I've finished tracing the diff, all BorrowerOperations callers, the proxy gate, the provider timing, the fixtures and the log. No further reads are needed; here is the review.

**Verdict for pinned head 2baa67e: conditional approve.** I found no blocking regression and no missed agreed requirement. The conditions are the BorrowerOperations size gate passing under the fixed compiler settings (the diff removes struct fields and one call site, so it should shrink, but I did not measure it) and the in-progress docs alignment. Everything below is policy commentary or optional polish.

**Evidence I relied on.** The integrated log ends with 1824 passed, 0 failed, 1 skipped. The skip is a setUp skip in DeployProductionTimelockTest, unrelated to this change. GuardianOraclePolicyTest shows 9 passes including both 256-run fuzz cases over ages 30h to 54h minus one second, with the wrongful and missed liquidation directions both logged.

**Requirements check against the agreed points**

- **Pure repay and add are price-free.** `_adjustTrove` only calls the oracle when the change has a collateral decrease or debt increase, or after permanent shutdown. See `source-snapshot/contracts/src/BorrowerOperations.sol:576-581` and `:672`. The mode check and the ICR test are skipped for pure improvements, matching the updated criticalThreshold and batch tests.
- **Risk increases stop at 30h.** The proxy returns failure to any BorrowerOperations caller once JPY provenance is 30h old, at `source-snapshot/contracts/src/PriceFeeds/PriceFeedProxy.sol:217`. This covers open, risk-increasing adjust, and every upfront-fee path that goes through `_requireOraclesLive`. Normal redemption was already gated at line 241. The gate is the proxy constant, so it binds at 30h regardless of provider configuration.
- **Liquidation keeps the bounded grace.** TroveManager is not the gated caller, so liquidation uses the frozen-JPY, live-collateral price until the provider expiry. With the production 30h threshold plus the 24h freeze, expiry is exactly the round timestamp plus 54h. Boundaries agree: provider freshness uses strict less-than and the proxy uses greater-or-equal, so 30h exactly is aged on both sides.
- **No new permanent shutdown at 30h or later.** `shutdown()` calls the proxy as BorrowerOperations and returns silently on failure at `BorrowerOperations.sol:1238-1240`. The reassessment after fresh FX is covered by the two shutdown tests.
- **Deployment enforcement.** Mainnet reads the env value and requires it to equal 30h at `source-snapshot/contracts/script/DeployLiquity2.s.sol:651`. Non-mainnet uses the constant directly. The canary fixed environment now carries 108000 seconds. No other production path constructs the provider.

**Checklist items I verified with no finding**

- Mixed operations: any change with a decrease or debt increase is treated as risk-increasing, including withdraw plus repay. Zero adjustments still revert. The repay cap to MIN_DEBT cannot flip the risk classification because it only edits debtDecrease.
- Authorization is unchanged: risk increases need owner or remove manager, improvements need owner or add manager.
- Batch accounting: pure repay inside a batch skips only the MCR plus BCR check. Share and weighted-debt updates are unchanged.
- Call ordering: for risk increases the shutdown check runs before the oracle call, so no external call happens while paused. Pure improvements make no oracle call at all. No new reentrancy surface.
- First fresh recovery: the source call runs before the provenance read, so the round that refreshes the provider reopens borrowing in the same transaction. Test covers it.
- Pause latch: at expiry the proxy latches the pause. After fresh FX, liquidation and close work before owner resume, risk increases stay blocked, and pure improvements never needed the oracle. Test covers it.
- Provenance failure: an invalid provenance read fails closed for BorrowerOperations without latching a pause. Constructor and both confirm paths reject sources with missing or malformed provenance.
- Absolute cache age: the provider anchors the freeze at the earlier of first observation and round timestamp plus threshold, so the cached rate is never served beyond 54h absolute age. A newer-but-stale round re-anchors to its own timestamp.
- Other inputs: a collateral-USD or backing failure inside the grace window still shuts liquidation down through the existing path. Test covers it.
- No storage, ABI, or compiler setting changes. The removed struct fields are memory-only.

**Findings, none blocking**

1. **Low, policy scope.** `closeTrove` is now blocked once FX is 30h old, at `BorrowerOperations.sol:732-735`, because it needs a price for the CCR check and the proxy gate applies. The agreed list named borrowing, debt increase, collateral withdrawal and normal redemption. Close is a full repayment plus full withdrawal, so the conservative reading is defensible, and the borrower can still add collateral or repay down to MIN_DEBT price-free to protect against a wrongful liquidation. State this explicitly in the decision record so it is a choice, not a surprise.
2. **Low, invariant change.** `adjustZombieTrove` with a pure add or repay now reactivates a zombie without any ICR check, at `BorrowerOperations.sol:487-520` with the skip at `:672`. A zombie whose accrued debt has crossed MIN_DEBT can be reinserted into the sorted list while below MCR. Redemption already skips troves under 100 percent and the trove is liquidatable either way, so I see no economic loss path. Worth a one-line note in the spec.
3. **Informational.** `shutdown()` returns silently on aged FX with no event, so a monitor cannot distinguish "not below SCR" from "FX too old". Adding an event would change the ABI, which is out of scope. Off-chain monitoring should read provider age directly.
4. **Informational, pre-existing.** The 24h grace is measured from the first observed unhealthy response. If the feed publishes invalid data early, liquidation can halt when the cached round is younger than 54h. See `source-snapshot/contracts/src/PriceFeeds/JpyUsdRateProvider.sol:106-119`. This diff does not change it.

**Optional polish**

- The mainnet staleness require at `DeployLiquity2.s.sol:651` has no test. No test sets that env var, and the selector harness bypasses the env read with 72h. A small test that sets 259200 and expects the revert would close that.
- The comment at `DeployLiquity2.s.sol:184-185` still says the values below are testnet values pending a decision gate. The JPY constant is now the enforced mainnet value.
- `test_30hBlocksAllRiskIncreasesButFreshRoundReopens` does not exercise `closeTrove` or an upfront-fee path such as `setInterestBatchManager` at 30h. Both are gated by the same proxy line, but a direct assertion would document finding 1.
- The shortfall comparison the Guardian asked for is present as a logged value under a synthetic 15 percent move, not as an assertion against the suspend-at-30h alternative. It demonstrates the residual risk as intended, so I consider the request met, but the decision record should say the number is illustrative.