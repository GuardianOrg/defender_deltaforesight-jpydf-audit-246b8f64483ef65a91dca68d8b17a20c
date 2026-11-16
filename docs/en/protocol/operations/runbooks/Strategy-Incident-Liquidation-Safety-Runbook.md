# Strategy Incident / Liquidation Safety Runbook

| Item | Details |
| ---- | ------- |
| Scope | Losses not immediately reflected in Strategy accounting, external protocol liquidity stoppage, suspected reserve deficit / bad debt / depeg |
| Purpose | Prevent the operator liquidation bot from advancing liquidation unfairly before unrecoverable amounts are reflected in backing |
| Source of truth | [Strategy spec](../../product/spec/strategies/Strategy.md) / [AaveV3Strategy spec](../../product/spec/strategies/AaveV3Strategy.md) / [CollateralVault spec](../../product/spec/CollateralVault.md) / [Oracle spec](../../product/spec/Oracle.md) |

## 1. Principles

1. **Losses absent from accounting are not automatically marked down**
   Events such as Aave reserve deficit / bad debt / collateral depeg that do not appear in Strategy `estimatedTotalUnderlying()` are not automatically reflected in `backingRatio()`. Until monitoring, recovery, and GOV decision lead to `writeoffStrategyPrincipal`, on-chain prices may continue to look healthy.

2. **Do not liquidate first on unconfirmed losses**
   While unrecoverable amount is not finalized, the operator liquidation bot must fail-closed for the affected branch. Third-party liquidation cannot be stopped, but the operating entity must not advance liquidation based on speculative markdown.

3. **Writeoff is an operation that changes liquidation price**
   Once `writeoffStrategyPrincipal` makes `backingRatio() < 1e18`, the DF PriceFeed reflects that downward into collateral price. Because this affects borrowing, redemption, and liquidation prices, writeoff is a GOV operation that combines loss finalization with liquidation impact.

4. **Recovery should proceed in the order recover, backstop, reflect**
   Return liquid recoverable assets to the Vault first, use `backstopDeposit` if necessary, and write off only the finalized residual amount last. Writing off too much first and backstopping later creates an unnecessary liquidation window even if only briefly.

5. **Backstop assets must be the target Vault's Underlying**
   `backstopDeposit` receives the target `CollateralVault.underlying()` with `safeTransferFrom`. Sending JPYdf, dToken, Aave/Merkl reward tokens, or other assets directly does not repair dToken backing. If the Safe / Treasury holds JPYdf or reward tokens, convert them to the target branch's Underlying before calling `backstopDeposit`.

## 2. Strategy-Specific Classification

Whether an event appears in accounting, is unrecoverable, or is merely a liquidity constraint differs by Strategy implementation. Classify by the registered Strategy kind / external protocol state, not by branch collateral symbol.

| Strategy kind | What `estimatedTotalUnderlying()` represents | Events to distinguish before writeoff | Recovery and liquidation safety |
| ------------- | -------------------------------------------- | ------------------------------------ | ------------------------------- |
| AaveV3Strategy | Strategy-owned scaled balance x Aave normalized income. A decrease in Aave scaled balance is reflected, but reserve deficit / bad debt / market depeg may not directly reduce the Aave accounting value | Temporary `withdraw` shortfall from reserve utilization, reserve pause/freeze, aToken liquidity shortfall, Aave governance deficit processing, market depeg of collateral asset | Do not write off merely because max withdraw is short. `emergencyWithdrawFromAave` returns only liquid amounts to the Vault; examine external accounting, Aave governance state, and realistic recovery for residuals. Bot skips while Vault is paused. Write off only finalized residuals |
| ERC4626Strategy (Morpho Vault / EulerEarn, etc.) | `convertToAssets()` for shares minted by the Strategy itself. Share price decline generally appears in live valuation | Real loss from share price decline, temporary `maxWithdraw` / `maxRedeem` limit, withdrawal queue, vault pause, oracle / loan-market bad debt | `convertToAssets(ownShares) < principal` can be a loss signal, but `maxWithdraw` shortage alone is a liquidity constraint. Emergency redeem recoverable amounts, and write off only amounts finalized by share-price decline and bad debt. Avoid double writeoff by comparing live valuation loss with Strategy `principal` reduction |
| LidoStrategy | Canonical stETH equivalent of owned wstETH + `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` + claimed own idle WETH. stETH DEX market depeg is not by itself a canonical accounting loss. During normal operation pending is valued at 10000 bps; only after incident freeze can the Vault `WRITEOFF_ROLE` lower the bps | Withdrawal queue wait, pending valuation bps, finalization rate, slashing / consensus loss, stETH market depeg, delayed request NFT claim, direct stETH/wstETH/WETH/raw ETH donation | Do not treat queue wait as loss. After `requestLidoWithdrawal`, track finalization / claim; if claim proceeds are uncertain, confirm `pausedAllocation == true` before lowering pending bps as an explicit incident operation. Return actually received WETH to the Vault after claim. Do not write off until slashing or canonical rate / actual claim amount below principal is confirmed. Direct stETH/wstETH/WETH/raw ETH donations are not backing. WETH donations can be returned with generic `emergencyWithdraw` if needed, but are not principal return |
| EtherfiWeETHStrategy | Owned weETH eETH/WETH value + `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` + claimed own idle WETH. During normal operation pending is valued at 10000 bps; only after incident freeze can the Vault `WRITEOFF_ROLE` lower the bps | Ether.fi withdrawal finalization wait, pending valuation bps, NFT claim delay, actual ETH receipt shortfall, weETH/eETH canonical rate decline, LRT market depeg, direct eETH/weETH/WETH/raw ETH donation | Do not treat pending NFT wait as loss. After `requestEtherfiWithdrawal`, track NFT validity / `isFinalized` / actual claim receipt; if claim proceeds are uncertain, confirm `pausedAllocation == true` before lowering pending bps as an explicit incident operation. Return claimed WETH to the Vault. Do not write off until actual claim receipt or canonical-rate decline confirms residual loss. Direct eETH/weETH/WETH/raw ETH donations are not backing |
| SkyUsdcSUsdsStrategy | Normally values owned sUSDS share value in USDS plus own idle USDS at the lower of converter preview and 1:1 USDC conversion. During an explicit reverse-route halt, valuation is `min(1:1 position, principal)` and does not recognize unrealized yield. Direct sUSDS/USDS/USDC donations are not normal valuation | PSM / LitePSM / converter halt, route slippage, USDS depeg, sUSDS share-price decline, sUSDS `maxWithdraw` limit, USDS idle residue | Converter halt or wider slippage is a halted recovery path, not immediate writeoff. `emergencyRedeemSUsdsToUsds` can return to USDS, but backing is repaired only after USDC conversion and successful `receiveFromStrategy`. Do not infer 1:1 value for quote faults other than an explicit halt; write off only finalized residuals based on conservative USDC quote and actual USDC recovery |
| Direct idle / mock / inert | Vault buffer or assets directly held by Strategy | Mistaken transfers, directly held idle assets, unconfigured Strategy | Return to Vault with `emergencyWithdraw` / `receiveFromStrategy`. Normally no writeoff because this is not external protocol loss |

### Classification Aids

- **Temporary liquidity constraint**: Aave reserve utilization, ERC4626 `maxWithdraw` limits, and Lido queue wait are not losses if recovery is merely delayed. Keep Vault pause and bot skip active while recovery / claim / queue progresses.
- **Loss visible in live valuation**: ERC4626 share price decline or lower Lido finalization amount can already appear in `estimatedTotalUnderlying()` and therefore in `backingRatio()`. Compare Strategy `principal`, Vault conservative value, and returned principal before applying additional manual writeoff.
- **Loss absent from live valuation**: Aave reserve deficit may not appear immediately in Strategy accounting; `backingRatio()` may still look healthy. Use official external protocol accounting, reserve status, actual recovery txs, audit/incident reports, and write off only the finalized residual.
- **Market depeg vs canonical accounting**: stETH / wstETH and some yield tokens can trade lower on DEXs without immediate impairment in protocol canonical accounting. Liquidation price reflection belongs to JPYdf oracle / backing policy and is separate from Strategy principal writeoff.
- **Do not classify by branch symbol**: use the rule for the actual venue. Day-1 active venues belong only to dwstETH and dUSDC; inert branches have no Strategy.

### 2.1 Monitoring and Recovery for Allocation Valuation Preflight

- Before and after every allocation keeper call, have an external monitor read `getStrategyStatuses()` and require `estimateAvailable && principalAvailable` for every registered Strategy, regardless of enabled state or weight. If any is false, `allocate` and `transferYieldToTreasury` use neither cache nor a partial sum and produce zero outbound movement. Because `allocate` emits no `Allocated` event and consumes no cooldown on this path, do not treat a successful keeper receipt alone as successful allocation; alert on unavailable status correlated with the missing `Allocated` event as the earliest stable machine signal.
- A later healthy dependency automatically allows the next keeper call to resume. The recovery probe must confirm both views on the affected Strategy, all registry statuses, buffer target, actual `Allocated` / `StrategyAllocated` events, and buffer deltas in the same block. A never-settling or gas-exhausting view can revert the whole transaction, so a caller timeout is not recovery evidence; require a successful receipt on the affected data path and the expected events.
- Page on-call for consecutive failures or a failure lasting longer than one keeper interval. Proceed through `pauseAllocation`, external venue / RPC / Strategy implementation diagnosis, and a recovery probe. Never use a fresh valuation cache as authority to resume outbound movement.
- Before production enablement, connect an external monitor, escalation policy, and real recipient, then run a labeled test incident through valuation unavailable, zero outbound, dependency recovery, automatic resume, receipt, and resolution. Record it without tokens or webhook URLs.

### 2.2 Monitoring and Upgrade for Allocation Deposit Rejection

- Subscribe to `StrategyAllocationSkipped` from an external monitor. When the contemporaneous `getStrategyStatuses()` is live-available with cap headroom, classify it as an external-venue deposit rejection rather than a valuation/cap skip. Warn on the first event and page on-call when the same Strategy rejects consecutively or again within one keeper interval. If `allocate` reverts with `DepositRecoveryFailed`, page on the first occurrence and pause allocation because exact recovery could not be proven.
- Structured logs alone are not alert delivery. Before production enablement, connect an enabled external monitor, escalation policy, and real on-call recipient; run a labeled test incident through creation, receipt, and resolution, and record it in the incident log without tokens or webhook URLs.
- The change from `deposit(uint256)` to `deposit(uint256,uint256)` changes the selector, so pause allocation throughout the upgrade. Upgrade every registered BaseStrategy implementation first, then CollateralVault. Verify the new selector on every Strategy, Vault/Strategy Underlying identity, cap/weight, and bytecode; run an allocate probe on the affected data path and verify event delivery before unpausing. Selector mismatch during the intermediate state fails closed but does not replace the pause.

## 3. Immediate Response Flow

1. **Detection**
   When an external protocol incident, reserve deficit, withdrawal halt, price divergence, audit report, or keeper partial recovery is detected, put the affected branch into incident mode.

2. **Stop Vault / Strategy**
   GUARDIAN executes `emergencyDisableStrategy(strategy)`. This sets Strategy `weightBps = 0` / `enabled = false` and pauses Vault deposit / redeem / claim / allocation. Stop new outbound allocation and user flows so recovery and backstop decisions can be made.

3. **Confirm operator liquidation bot stop**
   The bot reads branch `collateral_vault` config and skips the branch when any of the following is true:
   - `pausedDeposit || pausedRedeem || pausedClaim`
   - `backingRatio() < safety.min_backing_ratio_wei`
   - Vault guard is required but `collateral_vault` is unset

   When lowering Lido / Etherfi pending valuation through `setPendingWithdrawalValuationBps`, first confirm `pausedAllocation == true` and the bot skip condition. Pending bps markdown is not principal writeoff, but it can lower `backingRatio()` and liquidation pricing, so treat it as a temporary incident markdown.

4. **Recovery**
   Execute the Strategy-specific emergency function and return recoverable liquid amounts to the Vault in the same tx. Actual Vault receipt reduces Strategy `principal` as returned principal.

5. **Backstop decision**
   Check `backingShortfall()` / `backstopRequiredForRatio(1e18)` and the target Vault's `underlying()` / symbol / decimals, then decide whether Treasury / Foundation Safe can provide that Underlying. If backstop is possible, call `backstopDeposit` before writeoff to avoid unnecessary `backingRatio` decline. JPYdf, dToken, and non-Underlying reward tokens are not direct backstop assets.

6. **Finalize loss writeoff**
   Execute `writeoffStrategyPrincipal(strategy, amount, minBackingRatioAfter)` only for the finalized unrecoverable amount. Set `minBackingRatioAfter` from the expected backing ratio calculated in dry-run step 3, with margin for rounding and concurrent state changes. If the transaction reverts with `BackingRatioBelowMinimum`, re-check unit mistakes, last-minute state changes, and unreconciled recovery before retrying; do not blindly lower the value. Record post-writeoff `backingRatio()` and PriceFeed display price, and inspect impact on Troves near MCR.

7. **Resume**
   After `backingRatio == 1e18` is restored and Strategy addition / cap / weight / oracle / bot guard are confirmed, GOV unpauses Vault user flows in the required order. If relaxing operator bot `min_backing_ratio_wei`, record the GOV/operator decision and rationale in the incident log.

### 3.1 Operation Policy Ledger

Admin Console and Ops Dashboard should use the same vocabulary below. Do not infer semantics from UI button names alone; record in the incident log what each action changes for backing, buffer, principal, and bot safety.

| Category | Main function / procedure | Purpose | Backing impact | Buffer / claim liquidity impact | Pre-check |
| -------- | ------------------------- | ------- | -------------- | ------------------------------- | --------- |
| Freeze | `emergencyDisableStrategy`, Vault pause | Stop new allocation and user flows | None. Not loss finalization | None | Target Strategy, branch, bot skip condition, third-party liquidation risk |
| Recover | `sendToVault`, Strategy-specific emergency withdraw, `claimLidoWithdrawals` | Return recoverable amounts to Vault | Amount actually received returns to accounting as returned principal | Returns to Vault buffer / idle | Difference between `requested` and `sent`, Aave reserve liquidity, ERC4626 `maxWithdraw` / queue, Lido finalization / claim state |
| Writeoff | `writeoffStrategyPrincipal` | Finalize unrecoverable amount by deducting from principal | Reflected in `backingRatio` and PriceFeed only for the additional conservative-value decline | Does not directly add liquidity | Double-counting against loss already visible in live valuation, Troves near MCR, backstop availability |
| Inject | `backstopDeposit` | Repair missing backing from Treasury / Foundation Safe or equivalent | Increases `totalUnderlying` / backstop reserve and can restore full backing | Protected reserve; not yet claim / redeem liquidity | Target Vault `underlying()`, source Underlying balance / allowance, full repair amount, post-writeoff shortfall. Do not directly inject JPYdf / dToken / reward tokens |
| Release | `releaseBackstopToBuffer` | Move protected reserve into claim / redeem source | Internal Vault classification only. Does not increase `totalUnderlying` | Increases buffer for pending claim / withdraw payment | Full backing restored, pending queue, protected reserve to keep |
| Resume | unpause, strategy weight / cap reset, bot safety relaxation | Return to normal operation | No new direct impact, though reallocation reintroduces future risk | user flows resume | backingRatio, oracle, strategy selector, bot `min_backing_ratio_wei`, incident log approval |

`writeoff` is loss finalization and is distinct from recovery, injection, and release to buffer. In Aave, reserve deficit may not appear immediately in Strategy accounting; in ERC4626 / Lido, share price or canonical finalization amount decline may already be visible in live valuation. Confirm there is no double markdown per Strategy before executing.

### 3.2 Strategy-Kind Execute Checklist

The same `sendToVault` / `writeoffStrategyPrincipal` means different things depending on the external venue. Admin Console / Ops Dashboard should detect kind from Strategy-specific views, and operators should record the checklist below in the incident log.

| Strategy kind | Primary recovery path | First interpretation of `requested != sent` | Residual that may be written off | Extra checks before bot resume |
| ------------- | --------------------- | ------------------------------------------- | -------------------------------- | ------------------------------ |
| Aave V3 | `sendToVault`; in severe cases `emergencyWithdrawFromAave` | reserve utilization / liquid underlying shortage. Not immediate loss while Aave accounting value remains | residual where Aave reserve deficit / bad debt does not appear in accounting and no realistic recovery remains | Aave reserve pause/freeze, normalized income, scaled balance, liquid reserve, external incident report |
| ERC-4626 | `sendToVault`; in severe cases `emergencyWithdrawFromERC4626` | liquidity limit from `maxWithdraw` / `maxRedeem` / queue / vault pause | residual confirmed by `convertToAssets(ownShares) < principal` and bad debt, not duplicated with loss already visible in live valuation | share price, maxWithdraw/maxRedeem, curator/governance action, underlying market bad debt |
| Lido | `requestLidoWithdrawal` -> finalization -> `claimLidoWithdrawals` -> `sendToVault`; in severe cases `emergencyWithdrawFromLido` | claimed own idle WETH is insufficient; staked amount waits in queue. Finalized but unclaimed requests remain at freeze-gated bps-adjusted pending value. Direct WETH/raw ETH donation is not evidence of recovery or backing | residual confirmed by actual claim receipt or canonical rate decline, not by queue wait | requestId, pending amount matching sum by requestId, `pausedAllocation`, pending valuation bps, finalization/claim status, actually received ETH, own idle WETH, donation residue, withdrawDelay and pending user claims |
| Etherfi weETH | `requestEtherfiWithdrawal` -> NFT finalization -> `claimEtherfiWithdrawals` -> `sendToVault`; in severe cases `emergencyWithdrawFromEtherfi` | claimed own idle WETH is insufficient; weETH waits in pending NFT / finalization. Direct WETH/raw ETH donation is not evidence of recovery or backing | residual confirmed by actual claim receipt or weETH/eETH canonical-rate decline, not by NFT wait | requestId, NFT owner / validity, pending amount matching sum by requestId, `pausedAllocation`, pending valuation bps, `isFinalized`, actually received ETH, own idle WETH, donation residue |
| Sky USDC/sUSDS | `sendToVault`; in severe cases `emergencyRedeemSUsdsToUsds` -> `emergencyConvertIdleUsdsToVault` or `emergencyWithdrawFromSky` | converter halt / slippage / USDS idle state. Returning to USDS is not backing repair until USDC reaches the Vault | normal-route converter preview and 1:1 cap; principal-capped 1:1 valuation during an explicit halt; actual USDC recovery; sUSDS share value decline | route-status read, converter preview / halt, `maxConversionLossBps`, USDS idle, sUSDS `maxWithdraw`, actual USDC recovery, branch 1 / USDC-only configuration |

`BaseStrategy.emergencyWithdraw(amount)` is a rescue path for returning Underlying directly held by the Strategy to the Vault; it does not reduce `principal`. To recover external-protocol principal for Aave / ERC4626 / Lido, normally use the specific `emergencyWithdrawFrom...` function or `sendToVault`, so actual Vault receipt is accounted as returned principal. A direct WETH donation to Lido can be returned to Vault with Base emergency, but it is not Lido principal return. After using Base idle rescue, compare remaining `principal` with `estimatedTotalUnderlying()` and apply residual writeoff separately if needed.

## 4. Bot Operation Rules

The Day-1 operator liquidation bot defaults to `safety.require_vault_guard = true`.

```toml
[safety]
require_vault_guard = true
allow_liquidation_during_vault_pause = false
min_backing_ratio_wei = "1000000000000000000"

[[branches]]
symbol = "dUSDC"
collateral_vault = "0x..."
```

With this configuration, the operator bot does not send liquidation transactions for branches where Vault user flow is paused because of a Strategy incident, or where explicit writeoff has made backingRatio less than 1.

`allow_liquidation_during_vault_pause = true` or `min_backing_ratio_wei < 1e18` should be applied only temporarily, paired with an incident log, when loss has been finalized and the operator should intervene on the same conditions as third-party liquidators.

The bot reads Vault guards both at scan time and immediately before submit planning. If Vault pause / writeoff occurs after scan, the pre-submit re-check still skips the branch.

## 5. Checks to Avoid Unfair Liquidation

Before writeoff / bot resume, confirm at least:

| Check | Purpose |
| ----- | ------- |
| Difference between `estimatedTotalUnderlying()` and externally recoverable amount | Separate accounting-invisible loss from temporary illiquidity |
| `backingShortfall()` | Confirm the absolute amount requiring backstop or writeoff |
| `backstopRequiredForRatio(1e18)` | Confirm backstop amount required to restore full backing |
| List of Troves near MCR | Understand which Troves become liquidatable after post-writeoff price |
| `PriceFeed.fetchPrice()` / `fetchRedemptionPrice()` | Confirm backing markdown is consistently reflected in borrowing / redemption / liquidation prices |
| bot safety config | Confirm operator bot skips the incident branch |

## 6. Decision Criteria

- **Temporary liquidity shortage**: do not write off. Wait for recovery queue / protocol liquidity recovery. Bot skips while Vault is paused.
- **Recovered + full backing restorable by backstop**: backstop first and keep writeoff to the minimum necessary.
- **Finalized loss and no backstop available**: write off and reflect `backingRatio < 1` into market price. In that case liquidation reflects protocol solvency rather than being unfair, but operator bot resume remains an explicit decision.
- **Unassessable / data mismatch**: do not write off. Keep Vault paused and bot skipped while investigating further.
