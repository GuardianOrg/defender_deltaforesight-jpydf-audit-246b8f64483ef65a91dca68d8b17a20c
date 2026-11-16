All evidence is gathered. Here is the review.

## Verdicts

I could not execute Foundry or the size gate in this environment, so every test count and byte figure below is treated as a claim, and I verified behavior by tracing code at the integration head `1036a99f`.

| PR | Finding | Head SHA | Verdict |
| --- | --- | --- | --- |
| 114 | Disposition report | `487d154a874c646369840b9ed2ab75b5ec028a27` | APPROVE, docs only |
| 115 | I-02..I-05 | `e50a51bbc19cd08ce3263a6d4e100c055e995e7c` | APPROVE |
| 116 | L-08 | `de3accd7cace6fc18e6c1dd54efb759c275b2275` | APPROVE, no blocking finding |
| 117 | L-10 | `7e673095b0d167e61c4564042987f263f8dbf696` | CONDITIONAL |
| 118 | I-01 | `521f5e39672527a968a90f4956cc48c2e2b2359d` | APPROVE, no blocking finding |
| 119 | L-07 | `215c904e3a63e909e3f8252f348a21164d5d8daa` | APPROVE, no blocking finding |
| 120 | L-09 | `7164010ca21793cdce6d9826f2951bd83d677f33` | APPROVE, no blocking finding |
| 121 | L-03 | `aae5cf7e2451ac7530e806aa010573ad17234119` | CONDITIONAL |

No confirmed exploitable bug was found in any PR. The two CONDITIONAL verdicts are about remediation completeness and disclosure, not about broken code.

## Per-PR findings

**PR 121, L-03 branch caps.** The mechanics are correct. The constructor stores the cap at slot 30, and I counted the 30 preceding fields by inspection: 3 in LiquityBase and 27 in TroveManager, ending with `shutdownTime` at slot 29. CREATE2 prediction and deployment both derive the cap from the same branch index, and the constructor-arg encoding in `DeployLiquity2.s.sol` matches the `new TroveManager{salt}` call. TroveManager is not upgradeable and has no setter, so storage is equivalent to an immutable for safety, at the cost of one cold SLOAD per liquidation and the loss of a bytecode-visible value for verifiers.

- **Medium, confirmed design gap: reserved high-value slots inherit the 1,000-unit cap permanently.** `_collGasCompensationCap` in the deploy script returns 2 ether only for index 0. Slots 2 and 4 are labeled dETH and dBTC in `_dfDTokenSlot`. Their TroveManagers are deployed on Day 1, the cap is not part of `finalizeRiskParams` or `TroveManager.syncRiskParams`, and CollateralRegistry stores every TroveManager as an immutable. So the exact L-03 defect recurs for any ETH or BTC-like reserved branch, and "a different cap requires redeployment" in practice means the slot cannot be fixed without redeploying the registry set. Guardian asked for a cap calibrated per collateral. Minimal fix: choose per-slot bootstrap caps now in the pure helper, for example 2 ether for the dwstETH, dETH and dBTC slots and 1,000 ether for stable slots, and add a deploy-invariant test asserting the mapping for all 8 indices. Moving the cap into the synced risk params would be cleaner but cannot fit in the 13-byte margin.
- **Low, docs:** `Parameter-Catalog.md` now labels the cap "deploy input / Protocol Governance". Governance cannot change it. Say "deploy input, fixed for the branch lifetime".
- **Low, tests:** the partial-offset case in `GuardianL03GasCap.t.sol` lands exactly on the cap boundary rather than below it, so the SP-portion scaling below the cap is only covered by the pure-function fuzz. `test_RejectsZeroOrExcessiveCap` uses a generic `expectRevert` with no positive control that a valid cap deploys. The "deployed cap remains fixed" assertion compares deployer storage, not the TroveManager, and proves nothing.
- **Untested claims:** 24,563 bytes and the 13-byte margin come from the PR's own size gate. I could not rerun it. The report's statement that the baseline had 6 bytes of headroom implies the storage version freed only 7 bytes, which is plausible but unverified. Either way I-06 will not fit in TroveManager.
- **Aside:** the JP core spec context lines show MIN_DEBT as 300,000e18 while Constants.sol and the EN spec say 100,000e18. Pre-existing, not introduced here.

**PR 120, L-09 close to dToken.** `closeTroveToDToken` reuses `_closeTrove`, which enforces the zapper-local owner-or-manager check and the core receiver check, pulls the exact `entireDebt` from the caller, and closes via Core. Collateral is measured from `getLatestTroveData` in the same block Core uses, so the transferred amount equals what ActivePool sends. Gas compensation follows the existing WETH-to-ETH path. Reentrancy guard is present. Donated dToken is untouched because the transfer uses the measured trove collateral, not the balance. No blocking finding.

- **Residual, accurately disclosed:** Core `closeTrove` still fetches a price when the branch is not permanently shut down and reverts on oracle failure. So this path rescues Vault redemption pauses and illiquidity, not incidents that also pause the oracle. The Zapper.md note "Core close restrictions still apply" covers this, but the Guardian response should say it explicitly.
- **Low:** `closeTroveToDToken` is not declared in `IZapper`, so interface-typed integrators cannot reach it. The test covers manager-with-receiver only. Add an owner-call case and a manager-with-zero-receiver case to pin that the owner receives in both.

**PR 119, L-07 excess harvest.** I confirmed the root cause: the production converter's `convertUsdsToUsdc` buys the maximum USDC for the supplied budget, and `_usdsTargetForUsdc` inflates that budget by the loss allowance, so the mock's full-input conversion is a faithful proxy. The fix routes `withdrawn - realizedProfit` through `receiveFromStrategy` and decrements principal by the measured receipt. Because the yield estimate already nets the actual fee, the post-harvest position value equals the reduced principal within one atom, so no phantom principal remains. The strategy holds the USDC when the Vault pulls, the Vault-side guard is free because the allocator calls the strategy directly, and no Vault function calls `sendProfitToVault`. Other adapters return at most the requested amount, so the branch only triggers for Sky. The regression test would fail on the old code because the old `sent` exceeded the measured yield.

- **Residual, should be disclosed:** Guardian's first recommendation, converting only enough USDS for the requested USDC, is not implemented. Each harvest with a positive fee below the allowance still over-converts by up to the allowance fraction of the yield and de-allocates that sliver to the buffer until the next `allocate`. Economically negligible, but say so in the response.
- **Ops note:** the excess receipt reduces or, under PR 117, invalidates the valuation cache without refreshing it. Allocators should follow a harvest with the permissionless `refreshStrategyValuation` so a later outage has a fresh cache.

**PR 118, I-01 fee reduction during pause.** The only change is replacing the combined check with a permanent-shutdown check. The downstream path touches TroveManager batch storage and ActivePool aggregate accounting, neither of which reads a price or checks the oracle flag. The test uses a real oracle-failure pause, shows accrual, settles at the old rate, waives, and confirms the branch stays paused. The retained permanent-shutdown test uses the TCR-below-SCR path, so it still exercises the kept guard. No blocking finding. The 24,559-byte figure is unverified here.

**PR 117, L-10 exhausted cache.** The helper now invalidates when the amount reaches or exceeds the cached value and still preserves the timestamp on partial reductions. All three callers were checked. Only privileged strategy entry points reach `receiveFromStrategy`, so no permissionless actor can force an invalidation. The Sky regression reproduces Guardian's sequence and would fail on the old code, and the fuzz covers the zero-cache edge. Verdict is CONDITIONAL on two disclosures, not on code changes:

- **Declined recommendation:** Guardian asked to refresh valuation on receipt before reducing. The PR states no callback was added but does not say why. The reason is sound: `sendToVault` decrements principal after the receipt returns, so an in-receipt refresh would store a stale principal and renew the TTL against the spec's intent. Record this in the response.
- **Behavior change on writeoff, low:** a full writeoff while valuation is unreadable now yields unavailable pricing immediately instead of an available zero for the remaining cache TTL. Because `removeStrategy` also needs live reads, a strategy whose upstream is permanently dead leaves the branch oracle paused until PR 116's coverage rule applies. This is the L-02 residual and should be cross-referenced there.

**PR 116, L-08 coverage short-circuit.** The reordered check returns full backing only when raw custody plus valued strategies already cover liabilities, with unvalued strategies contributing zero. That total is a true lower bound, so no loss can be hidden and the feed's clamp to 1e18 makes the numeric result identical. The test sits exactly on the boundary because the buffer is zero after allocation and the donation equals liabilities, and the one-atom burn correctly flips availability. No blocking finding.

- **Low, docs:** the `ICollateralVault` NatSpec still says a false flag means some strategy was unvalued, which remains true, but it no longer implies the converse. Add one sentence that availability can be true despite an unvalued strategy when known assets cover liabilities.
- **Note:** the protected backstop reserve counts toward known assets. This matches the existing `totalUnderlying` definition and is by design, but it should be stated in the response since it is not user-redeemable liquidity.

**PR 115, I-02..I-05.** All comments are accurate against code. The 30-hour wording matches the `>=` comparison in `_normalRedemptionJpyStatus`, and the invalid-provenance case correctly notes the healthy flag stays true. The `removeStrategy` NatSpec matches the two live-read checks. No issues.

**PR 114.** The tracking document does not overstate closure: every PR is labeled Draft, unfinished items are marked pending, and the final-handoff rule forbids labeling anything Fixed. The unverified byte counts are repeated there and should be regenerated in the integration run.

## Validation claims and cross-PR interactions

The interactions among PRs 116, 117 and 119 are consistent. An L-07 excess receipt uses the L-10 reduce-or-invalidate path, and the L-10 tests fail closed under L-08 only because their raw balance is below liabilities, which I checked for both the Sky test and the fuzz. The integration patch contains all three Guardian tests in the Sky suite and every code hunk from the seven code PRs.

What is not proven:

- No combined test run exists. The per-PR counts are self-reported and were run on isolated branches.
- No size, storage-layout or CREATE2 manifest run exists for the integration head. Both byte margins are small enough that this must be the gate before merge.
- PR 121 changes the TroveManager constructor ABI and creation bytecode, so all Day-1 address manifests are invalid until regenerated.

Recommended order: resolve the reserved-slot cap decision for PR 121, add the two PR 117 disclosures, then rerun the full suite plus size and storage gates on the integration commit and record the new identities before requesting Guardian's remediation review.