# Contract Audit Usage Map

## 0. Purpose

This is the auditor-facing map for how the Solidity contracts are expected to be
called in production. It is intentionally about contract behavior, actors,
entrypoints, and disabled routes. It is not a market plan.

Read this together with
[`Contract-Audit-Scope-And-nSLOC.md`](./Contract-Audit-Scope-And-nSLOC.md).
That document defines what is in the review scope and how nSLOC is counted.
This document defines how the scoped contracts are expected to be used.

Key reading rule: **audit inclusion does not imply that a contract is funded,
registered, routed, or shown in the frontend**. If a production source file is
compiled and can affect funds once configured, it may be in scope even when its
current configuration is inert.

## 1. Actor Classes

| Actor | Expected access pattern | Examples |
| --- | --- | --- |
| End user wallet | Calls Core directly, or calls a Zapper / Vault helper that composes Core and Vault operations. | Borrow, repay, adjust, redeem, SP deposit, Vault deposit/redeem. |
| Approved Trove manager / delegate | Calls selected `BorrowerOperations` paths only after the owner has delegated interest-rate authority or batch management. | Interest manager, batch manager. |
| Permissionless keeper / searcher | Calls state-changing functions where the destination and amount are constrained by contract state. | Liquidations, redemptions, `InterestRouterForwarder.route()`, `PILAllocator.distribute()`, `UniV4MerklInitiative.createCampaign()`, strategy valuation refresh. |
| Allocator / operations key | Moves Vault liquidity between buffer and registered Strategies, or pulls principal/yield back from Strategies. | `CollateralVault.allocate()`, `CollateralVault.transferYieldToTreasury()`, `Strategy.sendToVault()`, `Strategy.sendProfitToVault()`. |
| Guardian multisig | Immediate defensive pause or disable actions. It should not be able to resume flows or reprice collateral by itself. | Vault pause functions, strategy disable / whitelist removal, `PILAllocator.pause()`. |
| Timelock / Admin multisig | Parameter, owner, upgrader, oracle-source, bridge-admin, and writeoff actions according to the role map. | Vault config, Strategy registration, source switching, bridge-minter admin surface, UUPS upgrades. |
| Protocol contracts | Internal protocol-only calls. External callers must not be able to impersonate these routes. | JPYdf mint/burn, SP pool transfers, dToken mint/burn, Vault strategy reception. |

## 2. Primary User-Facing Paths

### 2.1 Borrow / Repay / Manage Trove

The Core collateral token is the branch dToken, not the underlying asset.

Raw path:

1. User obtains dToken by calling `CollateralVault.deposit(underlyingAmount)`.
2. User supplies dToken collateral to Core through `BorrowerOperations`.
3. Core opens or adjusts a Trove and mints / burns JPYdf through `JpydfToken`.

Relevant Core entrypoints:

- `BorrowerOperations.openTrove()`
- `BorrowerOperations.openTroveAndJoinInterestBatchManager()`
- `BorrowerOperations.addColl()`
- `BorrowerOperations.withdrawColl()`
- `BorrowerOperations.withdrawJpydf()`
- `BorrowerOperations.repayJpydf()`
- `BorrowerOperations.adjustTrove()`
- `BorrowerOperations.adjustZombieTrove()`
- `BorrowerOperations.closeTrove()`
- `BorrowerOperations.applyPendingDebt()`
- `BorrowerOperations.claimCollateral()`
- `BorrowerOperations.adjustTroveInterestRate()`
- Batch-manager functions such as `registerBatchManager()`,
  `setBatchManagerAnnualInterestRate()`, `setInterestBatchManager()`,
  `switchBatchManager()`, `removeFromBatch()`, and `kickFromBatch()`.

Zapper-composed path:

- `CollateralYieldZapper.openTroveWithRawETH()`
- `CollateralYieldZapper.openTroveWithRawETHAndReferral()`
- `CollateralYieldZapper.openTroveWithUnderlyingPermit()`
- `CollateralYieldZapper.openTroveWithUnderlyingPermitAndReferral()`
- `CollateralYieldZapper.addCollWithUnderlying()`
- `CollateralYieldZapper.withdrawCollToUnderlying()`
- `CollateralYieldZapper.withdrawCollToUnderlyingWithMin()`
- `CollateralYieldZapper.withdrawJpydf()`
- `CollateralYieldZapper.repayJpydf()`
- `CollateralYieldZapper.adjustTroveWithUnderlying()`
- `CollateralYieldZapper.adjustTroveWithUnderlyingWithMin()`
- `CollateralYieldZapper.adjustZombieTroveWithUnderlying()`
- `CollateralYieldZapper.adjustZombieTroveWithUnderlyingWithMin()`
- `CollateralYieldZapper.closeTroveToUnderlying()`
- `CollateralYieldZapper.closeTroveToUnderlyingWithMin()`

The candidate Sky ingress zapper (`SkyUsdcSUsdsYieldZapper`) is archived under
`contracts/src/**/archive/` and is not an expected production path; re-adopting
it requires a new activation package and Owner approval.

Negative assertion: there is no expected user path for flash-close,
collateral-funded repay, Multiply, Balancer, Curve, or Uniswap v3 adapter flows.
If an off-chain client tries to use those routes, the expected result is that no
production ABI / deployed contract route exists.

### 2.2 Stability Pool

Users deposit JPYdf into the branch-local Stability Pool. Liquidations offset
branch debt against that branch's SP only.

Expected user entrypoints:

- `StabilityPool.provideToSP(topUp, doClaim)`
- `StabilityPool.withdrawFromSP(amount, doClaim)`
- `StabilityPool.claimAllCollGains()`

Expected protocol-only entrypoints:

- `StabilityPool.offset()` is called by `TroveManager` during liquidation.
- `StabilityPool.triggerJpydfRewards()` is called by `ActivePool` interest
  accounting.

Review focus: branch-local accounting, product-sum math, same-block withdrawal
guard in `DFStabilityPool`, minimum JPYdf left in SP, and gain payout ordering.

### 2.3 Redemption

Normal redemption is a JPYdf-holder flow. The user can call the registry route
directly or use `RedemptionHelper` to add per-branch min-output checks.

Expected entrypoints:

- `CollateralRegistry.redeemCollateral(jpydfAmount, maxIterationsPerCollateral, maxFeePercentage)`
- `RedemptionHelper.redeemCollateral(jpydf, maxIterationsPerCollateral, maxFeePct, minCollRedeemed)`
- `RedemptionHelper.simulateRedemption()`
- `RedemptionHelper.truncateRedemption()`
- `TroveManager.urgentRedemption()` only after branch shutdown.

Important distinction: Core redemption returns the branch collateral token
(dToken). Converting dToken back into the underlying asset is a separate Vault
redeem flow.

### 2.4 Vault Deposit / Redeem

The Vault is the only minter and burner for a branch dToken.

Expected user entrypoints:

- `CollateralVault.deposit(underlyingAmount)`
- `CollateralVault.redeem(dTokenAmount, receiver)`
- `CollateralVault.redeemWithPermit(dTokenAmount, deadline, v, r, s, receiver)`
- `CollateralVault.claim(requestId)`
- `CollateralVault.backstopDeposit(underlyingAmount)`

Expected token entrypoints:

- `DToken.mint(to, amount)` is Vault-only.
- `DToken.burn(from, amount)` is Vault-only.
- `DToken.setCap()` and `DToken.setAllowedUnderlying()` are owner/governance
  operations, not user flows.

If the Vault liquid buffer is sufficient, `redeem` burns dToken and transfers
underlying immediately. If the buffer is insufficient, redemption creates a
queued withdrawal request and the user later calls `claim()`. `backstopDeposit`
does not mint dToken; it is a repair/donation path that becomes liquid buffer
only after governance calls `releaseBackstopToBuffer()`.

## 3. Strategy And Vault Operations

The Strategy model is push-based. The Vault allocates underlying to registered
Strategies, and Strategies push principal or yield back to the Vault. Core
Liquity contracts do not call Strategies.

Expected allocator / operator entrypoints:

- `CollateralVault.allocate()`
- `CollateralVault.transferYieldToTreasury()`
- `Strategy.sendToVault(amount)`
- `Strategy.sendProfitToVault()`
- `CollateralVault.refreshStrategyValuation(strategy)`
- `CollateralVault.invalidateStrategyValuationCache(strategy)`

Expected governance / incident entrypoints:

- `CollateralVault.addToWhitelist(strategy)`
- `CollateralVault.removeFromWhitelist(strategy)`
- `CollateralVault.addStrategy(strategy, weightBps, cap)`
- `CollateralVault.updateStrategy(strategy, weightBps, cap, enabled)`
- `CollateralVault.emergencyDisableStrategy(strategy)`
- `CollateralVault.removeStrategy(strategy)`
- `CollateralVault.writeoffStrategyPrincipal(strategy, amount, minBackingRatioAfter)`
- `CollateralVault.setAllocatorConfig(maxMove, cooldown)`
- `CollateralVault.setStrategyValuationMaxAge(maxAge)`
- `CollateralVault.pauseAllocation()` / `unpauseAllocation()`
- `Strategy.emergencyWithdraw(amount)`
- `Strategy.sweepRewardToken(token, amount)`
- `Strategy.claimMerklRewards(distributor, tokens, amounts, proofs)`
- `Strategy.setUpgrader(newUpgrader)`

Expected strategy-specific entrypoints:

- Async base: `AsyncRequestStrategy.setPendingWithdrawalValuationBps()`,
  `pendingRequestCount()`, and `getPendingRequestIds()`.
- Aave: `AaveV3Strategy.claimAaveRewards()` and
  `AaveV3Strategy.emergencyWithdrawFromAave()`.
- Lido: `LidoStrategy.requestLidoWithdrawal()`,
  `LidoStrategy.claimLidoWithdrawals()`, and
  `LidoStrategy.emergencyWithdrawFromLido()`.
- ERC-4626: `ERC4626Strategy.emergencyWithdrawFromERC4626()`.
- Sky: `SkyUsdcSUsdsStrategy.setMaxConversionLossBps()`,
  `emergencyRedeemSUsdsToUsds()`, `emergencyConvertIdleUsdsToVault()`, and
  `emergencyWithdrawFromSky()`.
- Etherfi: `EtherfiWeETHStrategy.requestEtherfiWithdrawal()`,
  `claimEtherfiWithdrawals()`, `emergencyWithdrawFromEtherfi()`, and
  `setReferral()`.

Review focus: strategy registration gates, underlying-token matching,
principal/yield separation, delayed or async withdrawal accounting, valuation
cache fallback, writeoff sequencing, and whether emergency functions can move
funds anywhere other than the Vault or configured treasury.

## 4. Oracle And Shutdown Operations

Normal price reads are made by Core through branch `PriceFeedProxy` instances.
Operators and bots may also read these functions for monitoring.

Expected entrypoints:

- `PriceFeedProxy.fetchPrice()`
- `PriceFeedProxy.fetchRedemptionPrice()`
- `PriceFeedProxy.lastGoodPrice()`
- `PriceFeedProxy.proposeSource(newSource)`
- `PriceFeedProxy.confirmSource()`
- `PriceFeedProxy.confirmSourceEmergency()`
- `PriceFeedProxy.cancelSourceProposal()`
- Underlying feed implementations such as `DFPriceFeedBase.fetchPrice()`,
  `DFPriceFeedBase.fetchRedemptionPrice()`, and composite/feed-specific
  variants.

Expected shutdown entrypoints:

- `BorrowerOperations.shutdown()` is permissionless but only succeeds when the
  branch is below SCR.
- `BorrowerOperations.shutdownFromOracleFailure()` is PriceFeed-only.
- `TroveManager.shutdown()` is BorrowerOperations-only.

Review focus: stale oracle handling, last-good-price usage, source-switch
timelock/deviation guards, emergency switch authority, and whether shutdown
changes only the intended branch behavior.

## 5. Liquidation And Keeper Reads

Liquidation is permissionless and branch-local.

Expected state-changing entrypoints:

- `TroveManager.batchLiquidateTroves(troveIds)`

Expected read helpers:

- `LiquidationCandidateGetter.getLiquidationCandidates()`
- `LiquidationCandidateGetter.getLiquidationCandidatesWithLastZombie()`
- `LiquidationCandidateGetter.getLastZombieLiquidationCandidate()`
- `DebtInFrontHelper`, `HintHelpers`, `MultiTroveGetter`, and SortedTroves
  reads used by bots and frontend transactions.

Review focus: bounded iteration, zombie handling, SP offset vs redistribution,
gas compensation, and read-helper assumptions used by the liquidator bot.

## 6. Interest Routing, PIL, And Uniswap v4 Incentives

These contracts are incentive and routing plumbing. They are not borrow, repay,
or redemption routes.

Expected entrypoints:

- `InterestRouterForwarder.route()`
- `InterestRouterForwarder.setRecipient(newRecipient)`
- `PILAllocator.registerInitiative(initiative)`
- `PILAllocator.unregisterInitiative(initiative)`
- `PILAllocator.setWeights(initiatives, weights)`
- `PILAllocator.distribute()`
- `PILAllocator.pause()` / `unpause()`
- `UniV4MerklInitiative.createCampaign()`
- `UniV4Exchange.swapFromJpydf(jpydfAmount, minCollAmount)`
- `UniV4Exchange.swapToJpydf(collAmount, minJpydfAmount)`

Review focus: recipient validation, permissionless distribution constraints,
bounded initiative loops, hook failure isolation, campaign creation threshold
and epoch alignment, allowance cleanup, Uniswap v4 PoolKey correctness, and
whether v4 swap routes are explicit and not silently substituted by v3/Curve/
Balancer compatibility code.

## 7. Bridge-Ready Token Surface

`JpydfToken` has two separate supply routes:

- Core route: `mint()`, `burn()`, `sendToPool()`, and `returnFromPool()` are
  restricted to the configured Core contracts.
- Bridge route: `bridgeMint()` is restricted to registered bridge minters, and
  `bridgeBurn()` is a self-burn function.

Expected current configuration:

- `bridgeMinterCount == 0`
- `proposedBridgeMinter == address(0)`
- no active bridge adapter or other-chain issuance route

Expected admin entrypoints, only if the bridge surface is later configured
through governance:

- `proposeBridgeMinter()`
- `confirmBridgeMinter()`
- `cancelBridgeMinterProposal()`
- `removeBridgeMinter()`
- `transferBridgeAdmin()`
- `acceptBridgeAdmin()`
- `renounceBridgeAdmin()`

Review focus: core mint authority must not overlap with bridge mint authority,
bridge minter registration must remain contract-only and delayed, and the
dormant bridge route must not expand live supply while no minter is registered.

## 8. Negative Usage Assertions

The following paths should not be treated as expected production usage:

- Curve routes.
- Balancer routes.
- Uniswap v3 route adapters.
- Flash-close.
- Collateral-funded repay.
- Multiply / leveraged route composition.
- Fail-fast exchange placeholder compatibility.
- Active bridge adapter or cross-chain mint route.
- Direct non-USDC JPYdf liquidity pools in the current Uniswap route surface.
- `Treasury.sol` or reward distributor implementations that are not present in
  `contracts/src`.
- Deployment scripts as on-chain protocol entrypoints.
- Direct calls to protocol-only handlers such as `TroveManager.on*`,
  `TroveManager.redeemCollateral()`, `StabilityPool.offset()`, or
  `StabilityPool.triggerJpydfRewards()` from arbitrary users.

If any of those paths appears reachable from production ABI, frontend config,
or deployment manifest wiring, treat it as a scope/configuration mismatch.

## 9. Auditor Checklist

- For every public/external function in scope, identify the expected actor:
  user, keeper, allocator, guardian, governance, protocol contract, or unused.
- For every permissionless function, verify that recipient, amount, and loop
  bounds are constrained by contract state.
- For every operator function, verify the role holder, pause behavior,
  timelock/owner handover, and whether a compromised low-threshold role can move
  funds or only stop flows.
- For every Vault/Strategy path, trace the underlying token movement and the
  principal/yield/backstop accounting effect separately.
- For every Core path, trace dToken collateral movement separately from
  underlying Vault redemption.
- For every route adapter, verify the concrete venue and pool configuration.
  Do not assume that a generic `IExchange` interface implies multiple venues.
- For every dormant or configured-inert surface, verify that the current
  configuration prevents funding, registration, routing, or supply expansion.
