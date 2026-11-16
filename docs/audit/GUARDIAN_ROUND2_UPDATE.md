# Guardian remediation review — September 24 update

Guardian reported two additional Low findings after Sentry triage, categorized as out of scope. The authenticated board was read on September 24: both remain Pending in **Remediation Review / Round 2**. These IDs are distinct from Main Review L-01 and L-02. Out-of-scope classification does not mean that the project considers either issue safe or resolved. Client comments linking audit PR #129 were posted to both findings and verified after reload. Both statuses remain Pending; no report approval or resolution was submitted.

| Finding | Engineering status | Guardian status |
| --- | --- | --- |
| R2 L-01 — Nested strategy OOG can permissionlessly relatch a healthy branch's oracle-failure pause | Upstream implementation merged; remaining verification items below | Re-review requested; no resolution claimed |
| R2 L-02 — Merkl Campaign Collisions Can Strand Pre-Funded Incentives | Upstream implementation merged as `937a43b5d5ea54dd9ab206516fa28168b4a4fa44` | Review requested; no resolution claimed |

## R2 L-01: implementation and exact identity

The upstream correction merged as `18bedbf68905705e3c8a4b01a39096fd7881a1bb`. Each CollateralVault Strategy valuation probe receives a fixed 500,000-gas budget. The Vault checks the available gas immediately before **each** probe, including after the first probe has consumed gas. JpyFreezeLib rethrows the exact four-byte `InsufficientGasForExternalCall` error so caller gas starvation is not converted into an oracle-failure pause. A probe that fails despite receiving the full budget retains the existing cache/unavailable-value behavior.

The two production files changed by this fix are `CollateralVault.sol` and `PriceFeeds/JpyFreezeLib.sol`. A catch-time `gasleft() <= gasBefore / 64` check alone misses nested out-of-gas because nested callers can retain gas. The implementation therefore reserves and forwards the budget rather than relying solely on that heuristic. Registered Strategies must complete both valuation views within the budget. Transaction gas limits must cover the reserve even when actual consumption is lower; local deployment and seed broadcasts now use per-transaction RPC estimates.

Review artifacts are included here so access to the private implementation repository is not required:

- [Exact L-01 implementation, regression tests, and local deployment adjustment](../../evidence/guardian-remediation/2026-09-24/r2-l01-implementation.patch), relative to the upstream merge's first parent.
- [Coverage-compatible gas assertion follow-up](../../evidence/guardian-remediation/2026-09-24/r2-l01-coverage-followup.patch), test-only, merge `aaa400e97c20b37ae15ff7d4bbf6c3676b4ba76f`.
- [Complete upstream production delta](../../evidence/guardian-remediation/2026-09-24/upstream-production-delta.patch), from audited tree `4d461638a27fccd2f749f7086ec955985d04c2a0` to current upstream tree `375f41640a8e12396d8b379ef48755cb23320714`.
- [Machine-readable identities, checksums, and validation summary](../../evidence/guardian-remediation/2026-09-24/upstream-validation.json).

The complete production delta includes earlier changes beyond L-01: dwstETH redistribution penalty configuration and operation-specific role separation in `CollateralVault.sol`, `Dependencies/Constants.sol`, `Interfaces/ICollateralVault.sol`, `Interfaces/IStrategy.sol`, and `Strategies/BaseStrategy.sol`. Those changes are disclosed separately from the L-01 fix; none is represented as already covered by Guardian's September 23 report. The audit snapshot and historical identity manifests remain pinned to their existing candidates. These patches are a new review handoff, not a rewrite of the original audit scope.

To reconstruct the current upstream production tree in a disposable checkout of audit commit `5723a6d76279ec13c7cd57e081faf8493db34f15`, apply `upstream-production-delta.patch` with `git apply --directory=source-snapshot/contracts/src`. This reconstructs production source only, not the complete upstream test/build environment. The L-01 implementation patch is a separate review view and must not be applied on top of the complete production delta.

## Verification and remaining work

The upstream L-01 work recorded a calibrated nested-call reproducer at 571,000 caller gas before correction; the corrected sweep permits only a revert or a healthy price. The focused L-01 and DFPriceFeed suites passed 54 tests. The affected regression run passed 933 tests with one separately executed CCIP handoff skip. Local deployment/seed completed 250 transactions; Console Timelock/Safe and Liquidator Anvil E2E passed. CollateralVault runtime measured 23,956 bytes, leaving 620 bytes below EIP-170. These are upstream engineering results, not tests rerun against this documentation package.

Two independent CI failures were then corrected:

- Merge `2f777834b338ef5726772b8a39f226b523f53e11` aligned the invariant handler with the already implemented price/ratio-free collateral-addition and debt-repayment behavior. [Exact test-only patch](../../evidence/guardian-remediation/2026-09-24/invariant-harness-followup.patch).
- Merge `09076b0c6e4b0df706b6779c54742f4e044b1860` set `PRESTO_BLOCK=25995374` in the mainnet full CI step, matching the September 17 Presto evidence. No test assertions changed.

At upstream commit `a0347215390145b4c195e13510114ce67e5f1946`, full CI passed: local full **1,861 passed, 0 failed**, mainnet full **27 passed, 0 failed**, including all four Presto tests and 256 fuzz runs. Canonical Timelock (5 tests), CCIP entrypoint (1), and CCIP mainnet (1) passed in dedicated invocations; their repeats account for the two local and one mainnet skips. DF deploy wiring, contract utility, mainnet launch operation, CDK assertions, and source-tree checks passed. Coverage was intentionally not selected for that run. [CI log excerpt](../../evidence/guardian-remediation/2026-09-24/upstream-ci-summary.txt).

### Remaining verification matrix

The [verification test](../../evidence/guardian-remediation/2026-09-24/r2-l01-verification/GuardianR2L01RemainingVerification.t.sol) wires the real CollateralVault, ERC4626Strategy, DFUSDCPriceFeed, JpyUsdRateProvider and PriceFeedProxy. BorrowerOperations is a stub that keeps the real caller check: only the registered feed can pause or resume. For each case it sweeps caller gas from 150,000 to 1,600,000 on the normal, redemption and urgent price paths. Every attempt must either revert without state change or return a non-failure price no higher than the measured value, and no attempt may leave the branch paused. The same file was run on the pre-fix source and on the fixed source.

| Case | Pre-fix `e95fa3350` | Fixed `937a43b5d` |
| --- | --- | --- |
| Attack after owner recovery, all three paths | Fails: pause re-latched | Passes |
| Measured loss with a fresh valuation cache | Fails: price about 43% above the measured value | Passes |
| Measured loss with a stale cache | Fails: pause latched | Passes |
| Urgent path alone | Passes | Passes |

The fresh-cache case shows a consequence beyond the reported pause. Before the fix, starving a probe made the Vault fall back to the pre-loss cached value, so collateral was over-valued (quoted 149.99 against a measured 104.99 after a 30% venue loss). The fix reverts before probing, so the cache cannot be reached by starvation. The urgent path never pauses and never uses the cache, so it passes on both sources. Run logs: [fixed](../../evidence/guardian-remediation/2026-09-24/r2-l01-verification/run-fixed.txt), [pre-fix](../../evidence/guardian-remediation/2026-09-24/r2-l01-verification/run-prefix.txt).

### Build artifacts and storage layout

[Comparison](../../evidence/guardian-remediation/2026-09-24/r2-l01-verification/artifact-comparison.txt) of production sources built at the L-01 merge's first parent `e95fa3350e2d2c3b6e00b1dea76d00a19d17653c` and the merge `18bedbf68905705e3c8a4b01a39096fd7881a1bb`, with CBOR metadata stripped:

- Runtime bytecode changed in seven of 129 contracts: CollateralVault and six price feeds that inline JpyFreezeLib. Two of the feeds are deployed (DFUSDCPriceFeed, DFWstETHPriceFeed); four are archived.
- Storage layout is identical for every contract.
- The only ABI change is the added `InsufficientGasForExternalCall` error on CollateralVault.

The Vault and both deployed feeds must be deployed from the fixed source. The feeds are not upgradeable, so JpyFreezeLib's change reaches production only through new feed instances.

### GOV-settable probe budget (follow-up to Guardian's note)

Guardian noted that `estimatedTotalUnderlying` gets more expensive as a venue adds adapters or markets, so a fixed 500,000-gas budget can be outgrown. Once that happens, the Vault prices off the last-good cache while it is fresh and then latches the oracle pause. Guardian recommended a GOV-settable budget and per-Strategy gas monitoring.

The upstream change is commit `1bb408d7b41d3b6cb7ad8257ecb96476a5392c4e` on top of `d59d0059d1c07e647a374ff426cb75e64edcaedc`. It merged upstream as `df2984d83f2afa9815913e648356f5d39578b1bc`; the merge adds only specification text beyond that commit, and the production tree is unchanged. [Exact production and test patch](../../evidence/guardian-remediation/2026-09-24/r2-l01-gov-budget/implementation.patch).

- The per-probe budget is now a storage variable. `setStrategyValuationGasBudget(uint256)` is restricted to GOV_ROLE and bounded to 100,000–2,000,000, and the initializer sets the 500,000 default. The bounds only guard against gross misconfiguration: within them, a budget below a registered Strategy's real cost still fails its valuation, and a budget near the top raises the gas limit that priced transactions such as liquidations must carry.
- Each change emits `StrategyValuationGasBudgetUpdated(oldBudget, newBudget)`; out-of-range values revert with `InvalidStrategyValuationGasBudget(budget)`.
- An unset slot reads as the default, so an upgraded proxy never probes with zero gas.
- The variable takes one slot from the storage gap directly after `strategyValuationMaxAge`; the end of the layout is unchanged.
- The specification now requires measuring each Strategy's `estimatedTotalUnderlying()` and `principal()` gas before registration and in operation, and raising the budget before a Strategy approaches it.
- Before **raising** the budget, the liquidation-path estimate multiplied by the liquidator's estimate buffer must stay within its signer gas-limit policy; a 2,000,000 budget alone needs about 2,051,746 gas at the probe. The bot limit is raised first if needed.
- Before **lowering** the budget, every registered Strategy is measured against the new value. Lowering does not invalidate a fresh valuation cache, so a probe that now fails would be valued from the pre-change cache until it expires; after expiry the branch can pause, and restoring the budget does not clear the pause without an owner resume.

These are governance-side risks: the budget is changed only through the GOV timelock. No path lets an ordinary caller change it.

The new tests cover the default, GOV-only and bounded updates with the event, the unset-slot default (including the slot position), a raised budget restoring valuation of a Strategy that had outgrown the default while keeping the no-latch guarantee, and a budget below a Strategy's cost behaving as a genuine valuation failure. [Run log](../../evidence/guardian-remediation/2026-09-24/r2-l01-gov-budget/run.txt): 13 passed in the L-01 suite. Upstream, the related 17 tests and 948 regression tests passed. CollateralVault runtime is 24,216 bytes, 360 bytes below EIP-170. The production source tree with this change is `dc3963480ee152dcb8d58f5c780862551cfd53f3`.

### Still open

- Guardian's re-review and disposition of the exact correction.

No production deployment or upgrade is claimed.

## R2 L-02: implementation

The upstream correction is commit `11828df54c9ab5508db2fd0500b02d6b87bbfe32` on top of `09076b0c6e4b0df706b6779c54742f4e044b1860`. It merged upstream as `937a43b5d5ea54dd9ab206516fa28168b4a4fa44` without further production-source changes; the merged production tree is `3f7ab10db30e6dc237bb9f4cbf8447393a69dca6`. The complete production delta above stops before this change. [Exact L-02 production and test patch](../../evidence/guardian-remediation/2026-09-24/r2-l02-implementation.patch), relative to that parent. It changes `PILAllocator.sol` and `Initiatives/UniV4MerklInitiative.sol`.

Funds for a Merkl initiative now stay in `PILAllocator` until campaign creation:

- On registration the initiative opts into deferred funding (`enableDeferredFunding`). Registration reverts if that hook fails, so an initiative cannot receive a weight without it.
- `distribute()` records the initiative's share as `pendingFunding` and `totalPendingFunding` instead of transferring it. Distributable balance and `pendingDistributable()` exclude reserved funding.
- `createCampaign()` claims the reserved amount through `claimDeferredFunding()` inside the same transaction that calls Merkl. A colliding campaign ID or any other Merkl revert rolls back the claim, and the funds remain reserved in the allocator.
- Unregistering an initiative releases its reserved amount back to the distributable balance. Campaign creation is refused while the initiative is unregistered or the allocator is paused.
- Tokens transferred directly to a retired initiative can be returned to the fixed allocator with the permissionless `returnFundsToAllocator()`.
- The constructor checks that the allocator is a contract and uses the same JPYdf token.

A squatted ID still delays that epoch's campaign; the correction removes the stranding and retirement-loss consequences, not the ability to collide. The next epoch can use the reserved funds unless the attacker squats again at their own cost.

Upstream tests for the allocator and initiative passed (48 tests across three suites at the implementation commit), including collision rollback, next-epoch recovery, release on unregistration, return of direct transfers and isolation of other initiatives. These are upstream results, not tests rerun against this documentation package.

Merged production tree: `3f7ab10db30e6dc237bb9f4cbf8447393a69dca6`. To reconstruct it in a disposable checkout of audit commit `5723a6d76279ec13c7cd57e081faf8493db34f15`, apply the complete production delta as described above, then `r2-l02-implementation.patch` with `git apply --directory=source-snapshot`. The resulting production tree and all four source/test blobs match the candidate. This does not reconstruct the entire upstream build environment; the historical snapshot remains unchanged.

The [differential review](../../evidence/guardian-remediation/2026-09-24/r2-l02-differential-review.md) covers collision/rollback, receiver isolation, registration failure, pause/recovery, retirement and reentrancy. It was performed by the implementing agent, not an independent reviewer. The [candidate validation record](../../evidence/guardian-remediation/2026-09-24/r2-l02-validation.json) includes the exact identities and artifact checksums. The baseline reproducer confirmed 100 JPYdf stranded after collision and retirement. The corrected collision test ran 256 fuzz cases across three squatted epochs followed by recovery; the existing `df-ops` coverage shard passed 67 tests without failures/skips. Production sizes passed (allocator 7,788 bytes; initiative 6,713 bytes). Eight scoped Slither reports were reviewed with individual dispositions in the linked report. Full CI at the implementation commit passed: **1,873 local tests** (including all 11 `Invariants.t.sol` tests) and **27 mainnet tests**, zero failures. The two local and one mainnet skips duplicate separately passed canonical Timelock and CCIP invocations. DF deploy wiring, frontend build, five local-parity failure drills, bot tests and source/surface guards also passed. [CI excerpt](../../evidence/guardian-remediation/2026-09-24/r2-l02-ci-summary.txt). A documentation-only follow-up, `432e7015358dc060dc7bee2c2d6664e3c3fc6fc3`, corrects specification tables and pause wording; its complete contracts and workflow trees are identical to the tested implementation commit. The follow-up's ordinary CI also passed: 1,802 fast tests, DF deploy wiring, bot tests and source/surface guards. Utility/mainnet-operation checks were outside changed-input scope; CI coverage was unselected, with the local owning shard result provided above.

Deploy the updated allocator and initiative together. Already-deployed immutable instances do not gain a recovery function; identify old addresses/balances and establish settlement before migration. Registration now rejects contracts/Safes that reject the registration hook. Zero weight alone does not revoke a reservation; pause or atomically zero-weight and unregister when stopping consumption. Actual production Forwarder recipients, initiative weights and balances have not been verified at a pinned block. Day2 timing or non-use is not a remediation or risk acceptance. No production deployment or Guardian approval is claimed.
