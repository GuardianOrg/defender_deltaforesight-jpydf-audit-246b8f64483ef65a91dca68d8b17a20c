# 🟡 LidoStrategy Requirements Definition

> **Status: Archived / Out of Day-1 scope**
>
> `LidoStrategy` is **archived**. Its underlying is structurally WETH (`initialize` takes
> `IWETH _weth`; the deposit path unwraps WETH to native ETH before `lido.submit`), and the
> deploy selector that rejected any non-WETH underlying -- along with the strategy kinds,
> venue structs, helpers, and env keys -- was removed in PR #1424. Branch 0's Vault
> underlying then moved from WETH to wstETH, so no current branch can supply one. The source is preserved unmodified at
> `contracts/src/Strategies/archive/` and its test suite at
> `contracts/test/archive/`; both still compile and run.
>
> This surface **was covered by the external audit completed 2026-08-05** against
> audited identity `0c7766e0`. It is retained so that audit result is not discarded,
> but it is **out of the ACTIVE audit scope** from this commit onward. See
> [Contract-Audit-Scope-And-nSLOC](../engineering/guides/Contract-Audit-Scope-And-nSLOC.md)
> section 3.5.
>
> This document is historical material, not the source of truth for implementation,
> audit, or acceptance criteria. Current venue adoption is canonical in
> [Strategy-Selection-Policy](../protocol/operations/policies/Strategy-Selection-Policy.md);
> shared Strategy architecture is canonical in
> [Strategy](../protocol/product/spec/strategies/Strategy.md). `LIDO-*` IDs are kept for
> historical traceability and must not be reused or cited as active audit scope.
> Re-activation requires re-entry into the `DeployLiquity2` strategy selector plus a
> fresh activation package (venue evidence, risk sign-off, audit-scope change).

> ⚠️ **Retired from the Day-1 deploy surface.** With the WETH → wstETH branch swap (Branch 0 = dwstETH, aave-only Day-1 Strategy set), `LidoStrategy` is not deployed, registered, or allocated. The source and tests are not deleted: sources move to `contracts/src/Strategies/archive/` and specs to `documents/{en,jp}/archive/`, preserved as previously audited artifacts (audited at identity `0c7766e0`) and out of active scope. The archive move lands in the separate retirement change. This document describes the remaining implementation and its retirement / non-activation requirements (`LIDO-GOV-001`) and is not approval to reactivate.

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Archived / Out of Day-1 scope (historical material; previously audited under `0c7766e0`) |
| Implementation status | Implemented / retirement requirements active ([`LIDO-GOV-001`](#lido-gov-001-retirement--non-activation-gate)) |
| Owner | DeltaForesight |
| Target contract | `contracts/src/Strategies/archive/LidoStrategy.sol` (dedicated Lido wstETH Strategy; inherits `AsyncRequestStrategy` / `BaseStrategy`; UUPS; **asynchronous withdrawals**) |
| Related documents | [Strategy](../protocol/product/spec/strategies/Strategy.md) (authoritative source for `IStrategy` / `BaseStrategy` / `AsyncRequestStrategy` / push model / common permissions / common risks / **STGY-ERR-002 asynchronous handling**) / [CollateralVault](../protocol/product/spec/CollateralVault.md) (caller side for whitelist / addStrategy / receiveFromStrategy / delayed redemption claim / writeoff) / [Product-Overview](../protocol/product/Product-Overview.md) (architecture and separation of responsibilities) / [Mainnet Launch Risk Gate](../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-004) / [Parameters](../Parameters.md) (WETH underlying branch cap / weightBps / `withdrawDelay`) / [Oracle](../protocol/product/spec/Oracle.md) (a WETH underlying branch's assumed oracle is ETH/USD Standard and is not affected by this selection. This Strategy's AUM valuation uses the canonical wstETH rate [`getStETHByWstETH` / `stEthPerToken`] and is in the same family as Liquity v2 wstETH/rETH canonical-rate valuation. Production `CompositePriceFeed` is pruned for sUSDS) |

> This document follows the [requirements definition document standard](../README.md#requirements-spec-standard). Persistent IDs (`LIDO-…`) are assigned to requirements, invariants, and security requirements, and cross-references are made by ID.
> **Scope of this document**: This document covers only the **Lido-specific requirements** of `LidoStrategy`. Common Strategy matters (`IStrategy` / `BaseStrategy` / `AsyncRequestStrategy` rules, integration with Vault, common permissions, common risks, common events, and the **handling policy for asynchronous protocols STGY-ERR-002**) are defined authoritatively in the parent page [Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md) and are referenced by name in this document.
>
> **Adoption status and role of this document**: [Strategy Selection Policy](../protocol/operations/policies/Strategy-Selection-Policy.md) is canonical for current venue adoption. This document accurately describes the remaining implementation and defines component-specific retirement, recovery, and removal requirements in `LIDO-GOV-001`.

---

## 1. Purpose, Scope, and Non-Responsibilities

`LidoStrategy` is the remaining implementation that **stakes WETH allocated by CollateralVault into Lido (`submit` → `wrap` into wstETH) to earn ETH staking yield**. It inherits `AsyncRequestStrategy` / `BaseStrategy`, uses the push model, and encapsulates asynchronous Withdrawal Queue finalization inside the Strategy. This describes remaining code behavior; it is not approval to deploy or activate it.

- **Target Underlying / external protocol**: WETH (WETH underlying branch) / Lido stETH (`submit`) + wstETH (`wrap`) + Lido Withdrawal Queue (`requestWithdrawalsWstETH` / `claimWithdrawal` / `claimWithdrawals`). See §3 for details.
- **Specified by this document**: Lido-specific additional storage (`lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth` / `referral` / `_ownWstETH`) and how this Strategy uses async accounting shared by `AsyncRequestStrategy` (`_ownIdleUnderlying` / `pendingWithdrawAmount` / management of unclaimed requestIds) / `initialize` (new signature including the `upgrader` argument; max approvals from stETH to wstETH and from wstETH to Withdrawal Queue) / three hooks mapped to Lido I/F (`_doDeposit` = WETH→ETH→`lido.submit`→`wstETH.wrap` / `_doWithdraw` = **returns only already-claimed self-owned idle WETH** / `_estimatedTotalUnderlying` = own wstETH converted at the canonical rate + pending + own idle WETH) / **keeper functions for the asynchronous lifecycle** (`requestLidoWithdrawal` / `claimLidoWithdrawals`, withdrawals use `requestWithdrawalsWstETH`) / Lido-specific emergency recovery function `emergencyWithdrawFromLido` (**explicitly states the limits of non-atomicity**) / `referral` configuration / Lido-specific risks such as wstETH (non-rebasing), WETH/raw ETH donation, finalization delays, and slashing.
- **Not specified by this document (non-responsibilities / other documents)**:
  - Common `IStrategy` interface and the `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` (fixed destination Vault) / `sweepRewardToken` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` body provided by `BaseStrategy`; push-model accounting and `principal` management; requestId / pending / idle Underlying accounting provided by `AsyncRequestStrategy`; **STGY-ERR-002 (policy that asynchronicity is encapsulated inside Strategy)** → [Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md)
  - Integration with Vault (whitelist / weights / cap / `addStrategy` / `receiveFromStrategy` / **delayed redemption `claim` (VAULT-FR-006)** / fault tolerance) → [CollateralVault Requirements Definition](../protocol/product/spec/CollateralVault.md)
  - Final values for dToken / Underlying allocation, cap, weightBps, and **`withdrawDelay` (currently 3 days)** in the WETH underlying branch → [Parameters](../Parameters.md)
  - 🔵 Liquity core collateral, liquidation, and Redemption behavior → [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md)
  - Method for distributing operating profits to SP / DF Corp (`SYS-RISK-003` and Treasury design gate) → separate document ([Development-Plan](../engineering/plans/Development-Plan.md) §4)
- **Responsibility boundary (intentionally unaware of)**: `LidoStrategy` does not assume "whose collateral the allocation is for" or "how the Vault buffer / weights / `withdrawDelay` are determined." It is responsible purely for the external protocol I/F translation layer: "how to stake received WETH into the single external protocol Lido, how to recover it (asynchronously), and how much value it has." The central responsibility of this Strategy is to **avoid leaking** Lido's asynchronous withdrawals into the Vault's synchronous accounting.

---

## 2. Background and Design Policy

`LidoStrategy` is the concrete implementation of the **first asynchronous Strategy**, following the push model and the "1 Strategy = 1 Underlying = 1 external deployment destination" principle in the [Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md). Lido is a representative ETH staking destination, but because withdrawals require waiting for finalization in the Withdrawal Queue (generally about 1 to 5 days, longer under congestion), its recovery path is fundamentally different from Aave V3 ([AaveV3Strategy Requirements Definition](../protocol/product/spec/strategies/AaveV3Strategy.md)), which assumes immediate withdrawals.

### 2.1 Remaining async implementation boundary

`LidoStrategy` is a remaining implementation that demonstrates async support. Its functional and accounting requirements preserve the behavior and historical IDs of that code; they do not form an activation package.

### 2.2 Push Model and Encapsulation of Asynchronicity (Recast for STGY-ERR-002 Compliance)

The core of this Strategy's design is to **avoid leaking Lido's asynchronous withdrawals to the `IStrategy` surface and encapsulate them inside the Strategy implementation** ([Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002).

- **The `IStrategy` surface remains the push model**: `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / views inherit `BaseStrategy` / `AsyncRequestStrategy` from the [Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md) as-is. The Vault side does not hold `requestKey`, and does not have an `isAsyncWithdraw` branch or asynchronous settlement paths equivalent to `claimWithdraw` / `claimHarvest` (`StrategyConfig = {enabled, weightBps, cap}` remains unchanged).
- **`_doWithdraw` returns "only the amount immediately withdrawable at that point"**: This Strategy's `_doWithdraw` does not touch stETH directly, and returns only **self-owned idle WETH already claimed from the Withdrawal Queue and held by the Strategy**, as `min(requested amount, min(_ownIdleUnderlying, WETH.balanceOf(this)))`. Third-party WETH donations and raw ETH are not returnable and are not included in AUM. If there is no self-owned idle WETH, it returns `0`. Returning less than the requested amount (including `0`) is treated as a **normal path** ([Strategy Requirements Definition](../protocol/product/spec/strategies/Strategy.md) STGY-SEC-005). This allows `sendToVault` / `sendProfitToVault` to operate through the same push path as synchronous Strategies.
- **The asynchronous lifecycle is encapsulated in Strategy-internal keeper functions**: The multi-step flow of issuing an unstake request (`requestLidoWithdrawal`, LIDO-FR-006) → waiting for finalization → receiving funds (`claimLidoWithdrawals`, LIDO-FR-007) is implemented not on the `IStrategy` surface but as functions specific to this Strategy, and is managed through Strategy internal state (`pendingWithdrawAmount` / unclaimed requestIds / `_ownIdleUnderlying`). This follows the same "child Strategy-specific functions" pattern as Aave V3 having its own `emergencyWithdrawFromAave` outside the `IStrategy` surface.

- **Current Vault values do not assume Lido recovery**: User dToken redeems still use the Vault delayed-redemption mechanism when buffer is insufficient. However, the current WETH-underlying-branch baseline `withdrawDelay = 3 days` and `bufferTargetBps = 3.33%` assume synchronously recoverable Strategies and do not absorb Lido finalization. Therefore the current implementation must not receive allocation, and the former 17-day setting or a Lido-specific Vault/Core branch must not be restored.

> **Differences from the old `deltaforesight/jpydf` Lido implementation (key points of the recast)**: The prototype Lido Strategy in the old repository assumed the old pull-leaning `IStrategy` (`requestWithdraw` returned a `bytes32 key`, `claimWithdraw(key)` and `supportsImmediateWithdraw()` were exposed at the surface, and Vault registration used the 4-argument `addStrategy` with `isAsyncWithdraw = true`). The current jpydf-v2 **structurally does not adopt** this design (STGY-ERR-002). This document recasts it as follows: ① remove the asynchronous I/F from the surface and move it to keeper functions inside the Strategy, ② align with the 3-argument `addStrategy(IStrategy, weightBps, cap)` and do not pass an async flag to the Vault, ③ add an `upgrader` argument to the derived `initialize` and align it with the push model's Vault max approval. These are requirements, and volatile PR/commit information is not brought into this document (it belongs in git and the [Retrospective](../engineering/historical-reviews/Retrospective.md)).

### 2.3 Separation of Principal and Yield, and Conservative Valuation

- **`principal` is self-managed by `BaseStrategy`**: `deposit` adds the "amount of WETH sent by the Vault", and `sendToVault` subtracts `min(sent, principal)` for the "actual `sent` received by the Vault" (principal-first). Appreciation from increases in the wstETH canonical rate (`getStETHByWstETH` monotonically increases = staking yield) appears as `realizedYield() = max(estimatedTotalUnderlying() − principal, 0)`. **Not confusing yield (canonical rate increments) with principal** is ensured by the two paths: `sendProfitToVault`, which does not move `principal`, and `sendToVault`, which reduces `principal` based on `sent` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-002 / STGY-FR-003).
- **Include pending principal in AUM, with incident-time discounting**: Principal already submitted to the Withdrawal Queue but not yet claimed (`pendingWithdrawAmount`) remains in `principal` and is included in `estimatedTotalUnderlying()` through `pendingWithdrawalValuationBps` (effective default 10000). Normal unstaking does not make pending principal disappear from AUM. During incidents where claim proceeds are uncertain, after `pausedAllocation == true`, the Vault `WRITEOFF_ROLE` can lower the bps to conservatively value only the pending component before claim (LIDO-FR-005 / LIDO-INV-005).
- **Donation resistance (two-layer tracking for own position / own idle)**: stETH / wstETH / WETH can be transferred to this Strategy by anyone, and raw ETH can be sent directly to `receive()`. If external donations were included directly in AUM, they could inflate `realizedYield()` and make arbitrary value look like protocol yield. To prevent this, the staked portion tracks only **wstETH (`_ownWstETH`) obtained through this Strategy's own `submit`→`wrap` flow**, and the claimed portion tracks only **self-owned idle WETH (`_ownIdleUnderlying`) received through Withdrawal Queue claims and wrapped by this Strategy**. Valuation is `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`; direct stETH / wstETH / WETH / raw ETH donations are excluded from AUM (same idea as `_ownScaledBalance` in the [AaveV3Strategy Requirements](../protocol/product/spec/strategies/AaveV3Strategy.md). LIDO-SEC-002).
- **Honestly state the limits of emergency recovery**: Unlike Aave, Lido cannot convert staked principal to ETH **immediately**. `emergencyWithdrawFromLido` can only perform an atomic push of claimed self-owned idle funds plus issue unstake requests for the remaining wstETH; full recovery of staked principal is inherently delayed until finalization. This document does not exaggerate this point and explicitly states that immediate full recovery is not guaranteed even in emergencies (LIDO-FR-008 / LIDO-ERR-004 / LIDO-SEC-003).

> The overall policy for the push model and `IStrategy` / `BaseStrategy` is governed by [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md). The overall policy of no core changes is governed by [Product-Overview](../protocol/product/Product-Overview.md) §5.

---

## 3. Terms, External Dependencies, and Assumptions

**Terms**

| Term | Meaning |
| --- | --- |
| Underlying | The real collateral asset managed by this Strategy. In this Strategy, it is fixed to **WETH** (WETH underlying branch) |
| stETH | Lido's liquid staking token. Obtained by depositing ETH via `submit`. **Rebasing** (the balance increases with yield). In this Strategy, it is converted to wstETH via `wrap` immediately after submit, and stETH is treated only as an **intermediate token** in the wrap / withdraw paths (normal holding balance is ~0) |
| wstETH | A **non-rebasing** wrapper for stETH (Lido `WstETH`). Interchangeable with stETH via `wrap` / `unwrap`. The **balance is unchanged**, and value increases as `stEthPerToken` / `getStETHByWstETH` (canonical rate) monotonically increases. **1 wstETH corresponds to its own stETH shares**. The **holding form and basis for AUM valuation** of this Strategy |
| canonical rate | The conversion rate from wstETH to stETH (≈ETH) (`getStETHByWstETH(wstETH)` / `stEthPerToken()`). It is unaffected by rebases and monotonically increases with staking yield. It is the same family of valuation axis as Liquity v2 wstETH/rETH canonical-rate valuation |
| `_ownWstETH` | wstETH obtained by this Strategy itself through `submit`→`wrap` (= its own stETH shares). Does not include third-party donations. The basis for AUM valuation (LIDO-FR-005) |
| `_ownIdleUnderlying` | Idle Underlying received and wrapped by this Strategy itself through Lido Withdrawal Queue claims. Does not include third-party WETH/raw ETH donations. It is the upper bound for `_doWithdraw`, `emergencyWithdrawFromLido`, and the idle component of AUM |
| Withdrawal Queue | Lido's withdrawal queue (`WithdrawalQueueERC721`, unstETH NFT). Deposit stETH to obtain a requestId, then claim ETH after finalization |
| unstETH NFT | An ERC-721 representing a withdrawal request. Minted by `requestWithdrawalsWstETH`, burned by `claimWithdrawal` / `claimWithdrawals`, and ETH is received |
| finalization | The process by which the Lido oracle finalizes withdrawal requests. Generally 1-5 days (longer during congestion) |
| `pendingWithdrawAmount` | The total amount of stETH submitted to the Withdrawal Queue and not yet claimed (management of pending principal) |
| `referral` | The referral address passed to `lido.submit` (zero allowed). The destination for Lido incentives |
| vault | The corresponding CollateralVault that registers this Strategy (fixed by `BaseStrategy` in `initialize`) |
| Owner / Guardian multisig | The Owner of this Strategy (the actor for emergency recovery, `setReferral`, and ownership operations) |
| STRATEGY_UPGRADER | The `upgrader` of this Strategy (the actor that authorizes UUPS upgrades) |
| ALLOCATOR | The Vault's `ALLOCATOR_ROLE`. The operational role that starts `sendToVault` / `sendProfitToVault` and this Strategy's async request keeper (`requestLidoWithdrawal`) |

**External Dependencies (Trusted Externals)**

- **Lido stETH (`ILido` / `IStETH`)** — The call target for `submit(referral)` (ETH→stETH), and the input token for `wstETH.wrap` (approval target for stETH→wstETH). The minimal interface also exposes `sharesOf(account)` / `getPooledEthByShares(sharesAmount)`, but current AUM valuation uses the wstETH canonical helpers as the source of truth. We trust that stETH's core accounting is sound. Lido consensus-layer slashing or compromise of the stETH contract may affect principal (LIDO-ERR-003 / LIDO-ERR-004).
- **Lido wstETH (`IWstETH`)** — The call target for `wrap(stETH)` / `unwrap(wstETH)` / `getStETHByWstETH(wstETH)` / `getWstETHByStETH(stETH)` / `stEthPerToken()` / `balanceOf`. It is the **non-rebasing holding form** and is used for AUM valuation (canonical rate) and for submitting wstETH to the Withdrawal Queue. Managed by Lido, like stETH.
- **Lido Withdrawal Queue (`IWithdrawalQueueERC721`)** — The call target for `requestWithdrawalsWstETH(amounts, owner)` (**directly submits wstETH**, and the Queue unwraps it internally) / `claimWithdrawal(requestId)` / `claimWithdrawals(requestIds, hints)` / `MIN_STETH_WITHDRAWAL_AMOUNT()` / `MAX_STETH_WITHDRAWAL_AMOUNT()` / `getWithdrawalStatus(requestIds)` (checking finalization / claimed state). MIN/MAX checks for wstETH requests are performed against each request amount's `getStETHByWstETH(amount)` (= stETH equivalent). Finalization timing depends on the Lido oracle and cannot be controlled by this Strategy.
- **WETH (`IWETH`)** — `deposit()` (ETH→WETH) / `withdraw(amount)` (WETH→ETH). The same token as the Underlying.
- **`BaseStrategy` (parent [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md))** — Inherits and trusts the implementations of `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` and the push-model accounting.
- **OpenZeppelin Contracts (upgradeable)** — `OwnableUpgradeable` / UUPS (via `BaseStrategy`).

**Assumptions**

- This Strategy's Underlying is **fixed to WETH** and matches the Underlying of the corresponding Vault (WETH underlying branch) (the Vault's `addStrategy` verifies on-chain that `strategy.underlying() == vault.underlying()`. [CollateralVault Requirements](../protocol/product/spec/CollateralVault.md) `addStrategy`).
- `lido.submit{value: x}` generally mints stETH equivalent to ETH at 1:1, and the subsequent `wstETH.wrap(stETH)` mints wstETH at the canonical rate at that point and returns the minted amount as the return value (rounding of fractional amounts by -1 wei and floor rounding in wrap may occur. LIDO-SEC-006).
- wstETH is **non-rebasing** (balance does not change; value increases with the canonical rate), but as an ERC-20 it can be transferred by anyone (a donation path exists. LIDO-SEC-002).
- The Withdrawal Queue accepts only requests whose stETH-denominated amount is at least `MIN_STETH_WITHDRAWAL_AMOUNT` and at most `MAX_STETH_WITHDRAWAL_AMOUNT` per request (mainnet defaults are minimum 100 wei and maximum 1000 stETH). When supplying wstETH, each requested amount's `getStETHByWstETH(amount)` must fall within this range, and large withdrawals are split into multiple requests (LIDO-FR-006).
- `claimWithdrawal` before finalization reverts in the Withdrawal Queue (early claim is not possible. LIDO-FR-007 / LIDO-ERR-001).
- The ETH received from withdrawal is based on the **Lido protocol rate** and is independent of the secondary-market price of stETH (DEX depeg) (LIDO-ERR-005).

---

## 4. Actors, Roles, and Trust Boundaries

The common permission design (operation-by-operation matrix for Owner / Upgrader / ALLOCATOR / permissionless, and damage boundaries in the event of key compromise) is defined canonically in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md). Only Lido-specific operations are shown below.

| Actor | Lido-specific operations | Trust boundary |
| --- | --- | --- |
| **Owner (Guardian multisig)** | `initialize` (fix investment destinations; one time only) / `emergencyWithdrawFromLido` (atomic push of claimed self-owned idle funds to Vault + issuance of unstake requests for remaining wstETH) / `setReferral` | Immediate emergency operator. Must be multisig. `emergencyWithdrawFromLido` pushes only the self-owned idle portion to the fixed Vault destination and has no arbitrary destination (LIDO-SEC-003). However, staked principal cannot be recovered immediately, and direct WETH/raw ETH donations are not treated as Lido principal (LIDO-FR-008) |
| **Upgrader (STRATEGY_UPGRADER)** | Approval of UUPS upgrades / `setUpgrader` | Powerful permission to replace logic. Separated from Owner. The common policy is defined canonically in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) |
| **ALLOCATOR (Vault role)** | `sendToVault` / `sendProfitToVault` (internal `_doWithdraw` moves only self-owned idle WETH) / **`requestLidoWithdrawal` (issue unstake requests)** | Funds are only pushed to the Vault; arbitrary destinations are not allowed. `requestLidoWithdrawal` only performs MIN/MAX validation and pending accounting, and does not send funds externally (the owner of unstETH is the Strategy itself) |
| **WRITEOFF (Vault role)** | `setPendingWithdrawalValuationBps` | Price-moving operation that can lower pending request valuation. Downward changes require `pausedAllocation == true`. It does not move funds, but affects backing and is limited to the high-quorum immediate GOV multisig |
| **Anyone (permissionless)** | views (`estimatedTotalUnderlying`, etc.) / `claimLidoWithdrawals` (receive finalized requests) / stETH, wstETH, WETH, or raw ETH donation | Views require no trust. Claims only recover finalized requests to the Strategy itself and wrap them into WETH; there is no arbitrary destination. Finalized loss realization does not depend on a specific keeper key. Donations are not mixed into AUM, profit push, or Lido-specific emergency principal return (LIDO-SEC-002) |

- **Permission separation**: `emergencyWithdrawFromLido` and `setReferral` are `onlyOwner` and cannot be invoked by the operational role (ALLOCATOR). `requestLidoWithdrawal` is routinely triggered by an operations bot (ALLOCATOR), does not move funds externally, and has no destination address, limiting the damage from compromise of the operations key to "disruption of unstake timing." Pending valuation markdown is gated by Vault `WRITEOFF_ROLE`, not Owner or ALLOCATOR, and downward markdown requires Vault `pausedAllocation`. `claimLidoWithdrawals` is permissionless, so finalized request receipt and loss realization do not depend on a keeper key (LIDO-SEC-003 / LIDO-SEC-004).

---

## 5. Interface Specification

The functions provided by `BaseStrategy` (`IStrategy`) (`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `principal` / `realizedYield` / `estimatedTotalUnderlying` / `underlying` / `emergencyWithdraw` / `sweepRewardToken` / UUPS / 2-step Owner) are defined canonically in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md). The visibility of Lido-specific functions and hooks specified by this document is summarized below only as non-normative reference.

| Function | Visibility | Summary | Specified requirement |
| --- | --- | --- | --- |
| `initialize(address _vault, IWETH _weth, address _owner, address _upgrader, ILido _lido, IWstETH _wstETH, IWithdrawalQueueERC721 _withdrawalQueue, address _referral)` | external (initializer) | Initialize BaseStrategy (including `upgrader`) + fix investment destinations + max approve stETH→wstETH and wstETH→Withdrawal Queue | LIDO-FR-001 |
| `_doDeposit(uint256 _amount)` | internal (`deposit` hook) | WETH→ETH unwrap → `lido.submit{value}` → stETH → `wstETH.wrap` → wstETH. Add the wrap return value to `_ownWstETH` | LIDO-FR-003 |
| `_doWithdraw(uint256 _amount) → uint256 actual` | internal (`sendToVault` / `sendProfitToVault` hook) | Returns **claimed self-owned idle WETH only** as `min(_amount, min(_ownIdleUnderlying, WETH.balanceOf(this)))`, and decreases `_ownIdleUnderlying` by the returned amount. Does not directly touch wstETH / stETH | LIDO-FR-004 |
| `_estimatedTotalUnderlying() → uint256` | internal view (`estimatedTotalUnderlying` hook) | `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this)))` + `pendingWithdrawAmount` + `min(_ownIdleUnderlying, WETH.balanceOf(this))` | LIDO-FR-005 |
| `requestLidoWithdrawal(uint256 _stETHAmount) → uint256[] requestIds` | external (ALLOCATOR) | Convert the requested value (stETH-denominated) to wstETH and submit it to the Withdrawal Queue via `requestWithdrawalsWstETH` (MIN/MAX splitting). Add to `pendingWithdrawAmount`, record requestId, and subtract from `_ownWstETH` | LIDO-FR-006 |
| `claimLidoWithdrawals(uint256[] _requestIds)` / `claimLidoWithdrawals(uint256[] _requestIds, uint256[] _hints)` | external (permissionless) | Claim finalized requests → ETH → WETH wrap (make self-owned idle). A single request uses the no-hint path, multiple requests use a hinted batch. Subtract from `pendingWithdrawAmount` and increase `_ownIdleUnderlying` by the actual WETH delta | LIDO-FR-007 |
| `emergencyWithdrawFromLido()` / `emergencyWithdrawFromLido(uint256 maxStETHToRequest)` | external (onlyOwner) | Atomic push of claimed self-owned idle funds to Vault + returned-principal accounting + issuance of unstake requests for remaining wstETH (**staked funds cannot be recovered immediately**). The overload with an argument caps the stETH amount requested in that tx | LIDO-FR-008 |
| `setReferral(address _referral)` | external (onlyOwner) | Update the referral for `lido.submit` | LIDO-FR-009 |
| `ownWstETH() → uint256` | external view | Returns the self-tracked wstETH amount (`_ownWstETH`) excluding donations | LIDO-FR-005 |
| `pendingRequestCount() → uint256` | external view | Returns the number of unclaimed requestIds | LIDO-FR-006 / LIDO-FR-007 |
| `getPendingRequestIds() → uint256[]` | external view | Returns a snapshot of unclaimed requestIds | LIDO-FR-006 / LIDO-FR-007 |
| `receive() external payable` | external | Required for WETH unwrap and receiving ETH from the Withdrawal Queue | LIDO-FR-003 / LIDO-FR-007 |
| `_isSweepProtectedToken(address) → bool` | internal view (override) | In addition to Underlying (WETH), add stETH / wstETH / unstETH to sweep-prohibited tokens | LIDO-SEC-007 |

### 5.1 Funds and Lifecycle Diagram (Reference)

```text
[allocation] allocate (Vault → Strategy)        [stake]
  CollateralVault ──safeTransfer(WETH)──▶ LidoStrategy
                  ──deposit(amount)──────▶   _doDeposit: WETH→ETH→lido.submit→wstETH.wrap → wstETH (_ownWstETH += wrap return value)

[async recovery trigger] (ALLOCATOR / keeper)
  requestLidoWithdrawal(stETHAmount) ──▶ WithdrawalQueue.requestWithdrawalsWstETH → unstETH NFT
                                          (pendingWithdrawAmount += amount; _ownWstETH -= supplied wstETH)
        … wait for finalization (~1-5 days or longer; current Vault settings do not absorb this queue) …
  claimLidoWithdrawals(requestIds) ───▶ WithdrawalQueue.claimWithdrawal → ETH → WETH (made self-owned idle; pendingWithdrawAmount -= amount; _ownIdleUnderlying += WETH delta)

[push] (ALLOCATOR)
  sendToVault(amount) / sendProfitToVault()
        └ _doWithdraw: returns only min(requested, min(_ownIdleUnderlying, WETH balance)) from self-owned idle WETH (0 allowed)
        └ vault.receiveFromStrategy(actual) → Vault buffer (principal is decreased on a sent basis)

[user redeem] (Vault side; outside this Strategy's responsibility)
  redeem → buffer shortage → WithdrawRequest (claimableAt = now + current withdrawDelay 3 days) → later claim (VAULT-FR-006)
```

---

## 6. Functional Requirements (FR)

> The bodies of `deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` (fixed recipient Vault) / `sweepRewardToken` are provided by `BaseStrategy` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)). `LidoStrategy` implements only `initialize`, 3 hooks (`_doDeposit` / `_doWithdraw` / `_estimatedTotalUnderlying`) + **asynchronous keeper functions** (`requestLidoWithdrawal` / `claimLidoWithdrawals`) + its own emergency recovery function + `setReferral`.

### LIDO-FR-001: initialize (fixed investment destination and proxy initialization)

- **Type**: Functional | **Source**: Derived-class `initialize` convention in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) / Lido submit
- **Signature**: `initialize(address _vault, IWETH _weth, address _owner, address _upgrader, ILido _lido, IWstETH _wstETH, IWithdrawalQueueERC721 _withdrawalQueue, address _referral) external initializer`
- **Purpose**: Initialize exactly once through the UUPS proxy; in addition to the standard `BaseStrategy` initialization (including the `upgrader` argument), fix the Lido investment destinations (`lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth`), and max-approve stETH→wstETH (for `wrap`) and wstETH→Withdrawal Queue (for `requestWithdrawalsWstETH`).
- **Permissions**: Part of the deployment procedure (proxy initialization). Bind Owner (Guardian multisig) to `_owner` and STRATEGY_UPGRADER (shared TimelockController) to `_upgrader`.
- **Preconditions (Checks)**:
  - One-time only via `initializer` (multiple initialization reverts). The logic contract itself must not be initializable; initialization is limited to execution through the proxy.
  - `_lido != address(0)` / `_wstETH != address(0)` / `_withdrawalQueue != address(0)` (revert with `ZeroAddress` if zero)
  - Zero checks for `_vault` / `_weth` (= Underlying) / `_owner` / `_upgrader` are performed by the standard `BaseStrategy` initialization
  - `_wstETH.stETH() == address(_lido)`; otherwise revert with `InvalidWstETHStETH`
  - `_withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT() != 0` and `MAX_STETH_WITHDRAWAL_AMOUNT() >= MIN_STETH_WITHDRAWAL_AMOUNT()`; invalid queue bounds revert with `InvalidWithdrawalQueueBounds`
- **Behavior (Effects)**:
  1. `__BaseStrategy_init(_vault, IERC20(address(_weth)), _owner, _upgrader)` — standard `BaseStrategy` initialization (Ownable / UUPS, storage persistence, ownership transfer, `upgrader` persistence, **`underlying.safeApprove(vault, max)` to the Vault**). For details, see `BaseStrategy` in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)
  2. `lido = _lido` / `stETH = IStETH(address(_lido))` / `wstETH = _wstETH` / `withdrawalQueue = _withdrawalQueue` / `weth = _weth` (immutable thereafter)
  3. `referral = _referral` (updatable via `setReferral`; LIDO-FR-009)
  4. `IERC20(address(_lido)).safeApprove(address(_wstETH), type(uint256).max)` — allow `wstETH.wrap` to pull stETH / `IERC20(address(_wstETH)).safeApprove(address(_withdrawalQueue), type(uint256).max)` — allow the Withdrawal Queue to pull wstETH in `requestWithdrawalsWstETH` (both only once during initialize)
- **Reverts / Early Returns**: Multiple initialization → revert; `_lido == 0` / `_wstETH == 0` / `_withdrawalQueue == 0` → `ZeroAddress`; `wstETH.stETH() != lido` → `InvalidWstETHStETH`; invalid Withdrawal Queue min/max bounds → `InvalidWithdrawalQueueBounds`; failure of standard `BaseStrategy` zero checks → revert.
- **Emitted Events**: None (follows `BaseStrategy` initialization. No dedicated event is provided for finalizing investment destinations).
- **Design Notes**:
  - **Addition of the `upgrader` argument**: The old prototype implementation used `(vault, weth, owner, lido, withdrawalQueue, referral)` and had no `upgrader`. The current `BaseStrategy` separates Owner and Upgrader, so `_upgrader` is added as an argument to align with the standard initialization for the push model ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-007).
  - **Finalize investment destinations in `initialize`**: No `setLido` / `setWithdrawalQueue`-style functions are provided. If the investment destination needs to change, recreate the entire Strategy and replace the Vault registration (same policy as [AaveV3Strategy Requirements](../protocol/product/spec/strategies/AaveV3Strategy.md) AAVE-GOV-001. LIDO-SEC-001).
  - **Verify Underlying = WETH on-chain**: When registered with the Vault, `strategy.underlying() == vault.underlying()` is verified (LIDO-FR-002). The deployment script also asserts that the target is the WETH underlying branch.
- **Verification**: unit (multiple initialization revert, each `ZeroAddress` revert, successful max approval for stETH→wstETH / wstETH→Withdrawal Queue, fixed investment destinations, `upgrader` persistence).

### LIDO-FR-002: addStrategy prerequisite (Vault registration contract)

- **Type**: Functional | **Source**: `underlying()` contract in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) / `addStrategy` in [CollateralVault Requirements](../protocol/product/spec/CollateralVault.md)
- **Signature**: `underlying() → address` (provided by `BaseStrategy`)
- **Purpose**: After deployment, satisfy the prerequisites for the corresponding CollateralVault (WETH underlying branch) to put this Strategy into operation. `underlying()` returns WETH, and the Vault's `addStrategy` verifies this on-chain.
- **Permissions**: None (`underlying()` is view). Registration operations (whitelist / `addStrategy`) are performed by the Vault `GOV_ROLE` holder (shared TimelockController; [CollateralVault Requirements](../protocol/product/spec/CollateralVault.md)).
- **Preconditions (Checks)**: This Strategy has already been registered in the corresponding CollateralVault whitelist (`addToWhitelist`).
- **Behavior (Effects)**:
  1. GOV calls `addToWhitelist(strategy)` on the corresponding CollateralVault
  2. GOV puts it into actual operation with **`addStrategy(strategy, weightBps, cap)` (3 arguments)**. The Vault verifies on-chain that `strategy.underlying() == vault.underlying()` ([CollateralVault Requirements](../protocol/product/spec/CollateralVault.md) `addStrategy`)
- **Reverts / Early Returns**: If `strategy.underlying()` does not match the Vault's Underlying → reverts on the Vault side with `UnderlyingMismatch`. Registration of a placeholder (`underlying == address(0)`) → `UnderlyingNotSet`.
- **Emitted Events**: Follows Vault-side events (no Strategy-specific event).
- **Design Notes**:
  - **Do not pass an `isAsyncWithdraw` flag to the Vault**: The old prototype notified the Vault of asynchronicity using the 4-argument form `addStrategy(strategy, weight, cap, true /*isAsyncWithdraw*/)`. The current `StrategyConfig = {enabled, weightBps, cap}` has no async field, and `addStrategy` also takes 3 arguments ([CollateralVault Requirements](../protocol/product/spec/CollateralVault.md)). Because asynchronicity is contained inside this Strategy, the Vault registers and operates this Strategy **through the same interface as a synchronous Strategy** (STGY-ERR-002).
  - **Production applicability**: follow `LIDO-GOV-001`; do not deploy, register, or allocate the current implementation. [Parameters](../Parameters.md) is canonical for the current WETH underlying branch cap, allocation, buffer, and three-day `withdrawDelay`. A future async design must re-derive those values from its worst recovery period.
- **Verification**: integration (successful `addStrategy` (3 arguments) after whitelisting, Underlying mismatch revert), manual (deployment procedure).

### LIDO-FR-003: _doDeposit (convert WETH to ETH and submit to Lido)

- **Type**: Functional | **Source**: `_doDeposit` hook in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) / Lido submit
- **Signature**: `_doDeposit(uint256 _amount)` (internal; `deposit` hook)
- **Purpose**: Unwrap the WETH already received by `BaseStrategy.deposit` into ETH, convert it to stETH via `lido.submit`, then convert it to wstETH via `wstETH.wrap`. Only the wstETH obtained from that submit→wrap sequence is self-accounted into `_ownWstETH`.
- **Permissions**: Internal hook. The caller `deposit` is `onlyVault` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)). The Vault has already sent WETH immediately before `deposit` via `safeTransfer(strategy, _amount)`.
- **Preconditions (Checks)**: WETH has been transferred from the Vault to the Strategy before the call (push-model deposit).
- **Behavior (Effects)**:
  1. `stBefore = stETH.balanceOf(address(this))` — baseline for excluding existing stETH balance (donations, etc.)
  2. `weth.withdraw(_amount)` — unwrap WETH into ETH (receive ETH via `receive()`)
  3. `lido.submit{value: _amount}(referral)` — deposit ETH into Lido and mint stETH. Crediting recipient = this Strategy itself

  4. `stReceived = stETH.balanceOf(address(this)) - stBefore` — only the stETH received by this submit (no donation contamination)
  5. `wstBefore = wstETH.balanceOf(address(this))` -> `reportedWstMinted = wstETH.wrap(stReceived)` -> `wstAfter = wstETH.balanceOf(address(this))`. `wstMinted = wstAfter - wstBefore`; if the balance delta differs from `reportedWstMinted`, revert with `LidoShareBalanceMismatch`. `_ownWstETH += wstMinted`
  6. Firing `Deposited` (`principal += _amount`) is handled by `BaseStrategy.deposit`. Fire `OwnWstETHUpdated(_ownWstETH)` (LIDO-EVT-004)
- **revert / early return**: Failures of `weth.withdraw` / `lido.submit` / `wstETH.wrap`, unexpected wstETH decreases, or wrap-return mismatches revert the inner `_doDeposit` frame. `BaseStrategy.deposit` rolls it back and skips this allocation after exact WETH recovery, or reverts the full allocation when recovery mismatches. The zero-receipt no-op is handled by BaseStrategy ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-001).
- **Emitted events**: `OwnWstETHUpdated(uint256 ownWstETH)` (LIDO-EVT-004). `Deposited(_amount, newPrincipal)` is emitted by `BaseStrategy`.
- **Design points**:
  - **Self-accounting of wstETH**: Only the stETH received by this `submit` (`stReceived` after subtracting `stBefore`) is `wrap`ped, and the actual wstETH balance delta is added to `_ownWstETH` after checking it against the `wrap` return value. Third-party stETH / wstETH donations increase `balanceOf`, but they do not contaminate the `stReceived` calculation or the actual share delta within the same tx (LIDO-SEC-002).
  - **`principal` is increased by the ETH amount (= `_amount`)**: Appreciation from increases in the canonical rate of wstETH appears later in `realizedYield()` as yield, not principal (LIDO-FR-005). The -1 wei rounding in `submit` and floor rounding in `wrap` are absorbed on the `_ownWstETH` (wstETH quantity) side, while `principal` is exactly the amount sent by the Vault ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-001).
  - **`referral`**: Pass the current `referral` to `lido.submit` (updatable via LIDO-FR-009).
- **Verification**: unit (WETH unwrap, submit, accounting of `wrap` return value, no donation contamination), fork (submit to real Lido → wrap), invariant=LIDO-INV-001.

### LIDO-FR-004: _doWithdraw (return only self-owned idle WETH that is immediately withdrawable)

- **Type**: Functional | **Source**: [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) `_doWithdraw` hook / **STGY-ERR-002**
- **Signature**: `_doWithdraw(uint256 _amount) → uint256 actual` (internal hook for `sendToVault` / `sendProfitToVault`)
- **Purpose**: For normal principal/yield recovery, return the requested amount from **self-owned idle WETH that has already been claimed from the Withdrawal Queue and wrapped by the Strategy**. `BaseStrategy` then routes principal/cache-reducing returns through `receiveFromStrategy` and yield-only returns through direct transfer to the Vault buffer. It does not directly touch stETH / wstETH (because Lido cannot be withdrawn synchronously), and it does not treat third-party WETH/raw ETH donations as returnable protocol funds.
- **Permissions**: Internal hook. The callers `sendToVault` / `sendProfitToVault` reference the Vault's `ALLOCATOR_ROLE` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)).
- **Preconditions (Checks)**: None (clamped according to self-owned idle WETH and actual WETH balance).
- **Behavior (Effects)**:
  1. `ownIdle = min(_ownIdleUnderlying, IERC20(address(weth)).balanceOf(address(this)))`
  2. `actual = Math.min(_amount, ownIdle)`
  3. Decrease `_ownIdleUnderlying` by `actual` (lower-clamped to 0) and emit `OwnIdleUnderlyingUpdated` if `actual != 0`
  4. `return actual` (self-owned idle WETH is already in the Strategy balance, and `BaseStrategy` collects it via `vault.receiveFromStrategy(actual)`)
- **revert / early return**: Does not revert. If there is no self-owned idle WETH, returns `actual = 0` (`sendToVault` / `sendProfitToVault` treat `actual == 0` as a normal path. [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-SEC-005).
- **Emitted events**: `OwnIdleUnderlyingUpdated(uint256 ownIdleUnderlying)` if a nonzero amount is returned; `SentToVault` / `ProfitSentToVault` are emitted by `BaseStrategy`.
- **Design points**:
  - **Core abstraction of asynchronicity**: `_doWithdraw` does not unstake wstETH. Since wstETH→ETH can proceed only through `requestLidoWithdrawal` (LIDO-FR-006) → `claimLidoWithdrawals` (LIDO-FR-007), which waits for finalization, `_doWithdraw` returns only the "amount immediately withdrawable at that point" = claimed self-owned idle WETH (STGY-ERR-002). This allows the Vault side to avoid having an asynchronous liquidation path.
  - **`sent < requested` is normal**: Self-owned idle WETH being less than the requested amount (including `0`) is a normal liquidity case, and `sendToVault` / `sendProfitToVault` do not revert. For any shortfall in Buffer replenishment, the ALLOCATOR is expected to first increase self-owned idle WETH via `requestLidoWithdrawal` → wait → `claimLidoWithdrawals`, then call `sendToVault` again (LIDO-ERR-001).
  - **Relationship to yield recovery**: `sendProfitToVault` calls `_doWithdraw(yield)` capped by `realizedYield()`, but in this Strategy, converting the "yield portion into self-owned idle WETH" also goes through `requestLidoWithdrawal` / `claimLidoWithdrawals`. If there is no self-owned idle WETH, the yield push is also `0` (normal path).
  - **Do not turn donations into profit/principal**: Direct WETH donations increase `WETH.balanceOf(this)` but do not increase `_ownIdleUnderlying`, so they are not returned by normal `sendToVault` / `sendProfitToVault`. Raw ETH donations are not treated as Underlying unless a separate recovery policy wraps them.
- **Verification**: unit (self-owned idle WETH clamp, returns 0 when `ownIdle==0`, decreases `_ownIdleUnderlying`, does not touch stETH), integration (request → claim → self-owned idle → sendToVault coordination).

### LIDO-FR-005: _estimatedTotalUnderlying (valuation calculation)

- **Type**: Functional | **Source**: [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) `_estimatedTotalUnderlying` hook (assumes conservative valuation)
- **Signature**: `_estimatedTotalUnderlying() → uint256` (internal view hook for `estimatedTotalUnderlying`)
- **Purpose**: Return the value of the Underlying (ETH/WETH-denominated) managed by this Strategy in Lido, based on the canonical rate of wstETH (`getStETHByWstETH`) while excluding third-party donations. This is the basis for `BaseStrategy`'s `estimatedTotalUnderlying` / `realizedYield`.
- **Permissions**: None (internal view).
- **Preconditions (Checks)**: None (view).
- **Behavior (Effects)**:
  1. `ownWst = Math.min(_ownWstETH, wstETH.balanceOf(address(this)))` — excludes donations while reflecting decreases in the Lido-accounted balance (for example, if self-owned wstETH shrinks due to slashing)
  2. `stakedValue = ownWst == 0 ? 0 : wstETH.getStETHByWstETH(ownWst)` — converts wstETH to stETH(≈ETH) at the canonical rate
  3. `ownIdleWeth = min(_ownIdleUnderlying, IERC20(address(weth)).balanceOf(address(this)))`
  4. `return stakedValue + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + ownIdleWeth`
- **revert / early return**: When `ownWst == 0`, the staked portion is `0`.
- **Emitted events**: None (view).
- **Design points**:
  - **Including and discounting pending principal**: `pendingWithdrawAmount` (submitted to the Withdrawal Queue but not yet claimed, LIDO-FR-006 / LIDO-FR-007) is valued through `pendingWithdrawalValuationBps`. The effective default 10000 bps prevents principal in the middle of normal unstaking from temporarily disappearing from AUM. During incidents, after `pausedAllocation == true`, Vault `WRITEOFF_ROLE` can lower the bps so the Strategy reflects a conservative pending-value haircut in `estimatedTotalUnderlying()` and the Vault's conservative valuation before claim. Floor rounding keeps sub-wei dust on the conservative side (the "pending principal" requirement in SYS-RISK-004. LIDO-INV-005).
  - **Donation resistance**: Do not use `wstETH.balanceOf(this)` or `WETH.balanceOf(this)` directly; instead cap them by the self-derived trackers `_ownWstETH` and `_ownIdleUnderlying`. Third-party stETH / wstETH / WETH donations increase only actual balances, so they are not included in AUM. Raw ETH balance is never included. Because wstETH is non-rebasing, there is no normal valuation drift; if the canonical rate (`getStETHByWstETH`) shrinks due to slashing or similar events, the decrease is reflected (LIDO-SEC-002 / LIDO-INV-002 / LIDO-INV-010).
  - **Limits of conservatism**: Around the time Lido consensus-layer slashing is reflected in `wstETH.balanceOf` / `getStETHByWstETH` (canonical rate), valuation may diverge from the amount actually recoverable. Losses that do not appear in accounting are explicitly reflected downward into backing through the Vault's `writeoffStrategyPrincipal` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-004 / [CollateralVault Requirements](../protocol/product/spec/CollateralVault.md)) (LIDO-ERR-003).
- **Verification**: unit (`min` selection, pending bps inclusion, dust floor rounding, stETH/wstETH/WETH/raw ETH donation exclusion), fork (valuation using real `getStETHByWstETH`, canonical rate reflection), invariant=LIDO-INV-002 / LIDO-INV-005 / LIDO-INV-010.

### LIDO-FR-006: requestLidoWithdrawal (issue unstake request / async recovery trigger)

- **Type**: Functional | **Source**: [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002 (keep asynchronous recovery internal to the Strategy) / SYS-RISK-004 "async recovery trigger"
- **Signature**: `requestLidoWithdrawal(uint256 _stETHAmount) external returns (uint256[] memory requestIds)`
- **Purpose**: The **starting point for asynchronous recovery**, which submits stETH to the Lido Withdrawal Queue and obtains unstETH NFTs (requestIds). Splits the request into multiple requests according to MIN/MAX constraints and records them as pending.
- **Permissions**: Vault `ALLOCATOR_ROLE` (operations keeper). Funds do not leave externally, and the owner of unstETH is the Strategy itself.
- **Preconditions (Checks)**:
  - The caller must hold the Vault `ALLOCATOR_ROLE` (if not held, `Unauthorized`)
  - `_stETHAmount != 0` (zero is a no-op that returns `0` `requestIds`)
  - `_stETHAmount <= getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this)))` (do not request more than self-held amount. Excess is `AmountExceedsStaked`)
  - The post-split request count must be at or below `MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL` (implementation constant 32; excess is `LidoWithdrawalRequestTooLarge`)
  - Existing pending request count + post-split request count must be at or below `MAX_ASYNC_PENDING_REQUESTS` (128; excess is `AsyncPendingRequestLimitExceeded`)
- **Behavior (Effects)**:
  1. **Role validation** — if not ALLOCATOR, `Unauthorized`
  2. **stETH-denominated splitting** — Split the requested value (stETH-denominated) into chunks at or below `MAX_STETH_WITHDRAWAL_AMOUNT()`, adjusting so that the remainder does not fall below `MIN_STETH_WITHDRAWAL_AMOUNT()`
  3. **wstETH conversion** — Convert each chunk to a wstETH amount with `wstETH.getWstETHByStETH` and confirm that each chunk's stETH conversion `getStETHByWstETH(chunk)` falls within MIN/MAX. If the total submitted wstETH exceeds `min(_ownWstETH, wstETH.balanceOf(address(this)))`, `AmountExceedsStaked`
  4. **pending capacity check** — Confirm the total unclaimed request count after adding the new requests does not exceed `MAX_ASYNC_PENDING_REQUESTS` (128)
  5. `requestIds = withdrawalQueue.requestWithdrawalsWstETH(amounts, address(this))` — the Queue takes the wstETH (internally unwraps it) and mints unstETH NFTs to the Strategy itself
  6. Confirm that the before/after wstETH balance difference matches the total submitted wstETH, then `_ownWstETH -= totalWstETH` (clamp to 0 lower bound)
  7. `pendingWithdrawAmount += totalRequested`; record each `requestId` in the unclaimed set (store requestId→amount so the amount can be deducted at claim time)
  8. Emit `WithdrawRequested(requestIds, totalRequested)` (LIDO-EVT-002) / `OwnWstETHUpdated(_ownWstETH)` (LIDO-EVT-004)
- **revert / early return**: non-ALLOCATOR → `Unauthorized`; split satisfying MIN/MAX is impossible (extremely small amount) → `AmountOutOfRange`; exceeds self-held amount → `AmountExceedsStaked`; request count cap exceeded → `LidoWithdrawalRequestTooLarge`; pending request total cap exceeded → `AsyncPendingRequestLimitExceeded`.
- **Emitted events**: `WithdrawRequested(uint256[] requestIds, uint256 stETHAmount)` (LIDO-EVT-002) / `OwnWstETHUpdated` (LIDO-EVT-004).
- **Design notes**:
  - **pending principal does not reduce `principal`**: At the time the request is issued, the principal has not yet returned to the Vault. Do not subtract from `principal`; keep it in AUM via `pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000` (subtraction occurs only when self-owned idle WETH is actually pushed to the Vault through `sendToVault` / `emergencyWithdrawFromLido`). This is the "pending principal" requirement in SYS-RISK-004 (LIDO-INV-005 / LIDO-INV-006).
  - **How much to request is determined operationally from Vault conditions**: The ALLOCATOR decides the request amount so that it satisfies "remaining `WithdrawRequest` amounts due to buffer shortfall ([CollateralVault Requirements](../protocol/product/spec/CollateralVault.md) `pendingWithdrawals`) + rebalance target". The Strategy only validates the requested amount (self-held upper bound and MIN/MAX).
  - **Griefing resistance**: Restrict to ALLOCATOR to prevent attacks where third parties stop yield through meaningless unstaking (LIDO-SEC-004). Since funds do not leave externally, damage from compromise of the operations key is limited to "disruption of unstake timing".
- **Verification**: unit (ALLOCATOR-only, MIN/MAX splitting, request count cap, self-held upper bound, pending accounting, wstETH subtraction), fork (requestWithdrawalsWstETH to the real Withdrawal Queue), invariant=LIDO-INV-005.

### LIDO-FR-007: claimLidoWithdrawals (receive finalized requests and make them claimable)

- **Type**: Functional | **Source**: [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-002 / SYS-RISK-004 "making claimable"
- **Signature**: `claimLidoWithdrawals(uint256[] calldata _requestIds) external` / `claimLidoWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external`
- **Purpose**: Claim finalized unstETH requests to receive ETH, wrap the received ETH into WETH, and make it **self-owned idle**. The self-owned idle WETH can then be pushed to the Vault buffer via `sendToVault` (LIDO-FR-004).
- **Permissions**: permissionless. Received ETH enters the Strategy itself and is wrapped into WETH; it does not leave externally, and there is no arbitrary destination. Finalized request settlement does not depend on a keeper role.
- **Preconditions (Checks)**:
  - Each `requestId` must belong to this Strategy's unclaimed set (unknown IDs are `UnknownRequest`)
  - Each `requestId` must be finalized (if not finalized, the Withdrawal Queue reverts. Operationally checked in advance with `getWithdrawalStatus`)
  - The no-hint overload is for a single request only. Multiple requests must use the hinted overload (multiple requests without hints is `ClaimHintsRequired`; a hint-length mismatch is `WithdrawalQueueRequestMismatch`)
  - Each claim batch is capped at `MAX_ASYNC_REQUESTS_PER_CLAIM` (32) requests per transaction (excess is `AsyncRequestClaimTooLarge`)
- **Behavior (Effects)**:
  1. First remove each `requestId` from the unclaimed set and `pendingWithdrawAmount -= recorded requested amount` (clamp to 0 lower bound)
  2. Record `address(this).balance` before the claim. The no-hint overload calls `withdrawalQueue.claimWithdrawal(requestId)`, while the hinted overload calls `withdrawalQueue.claimWithdrawals(requestIds, hints)`, sending ETH to the Strategy (received via `receive()`)
  3. Wrap only the ETH balance delta received by the claim into WETH with `weth.deposit{value: ethReceived}()`; pre-existing raw ETH donation is not wrapped
  4. Add the actual WETH balance delta to `_ownIdleUnderlying` and emit `OwnIdleUnderlyingUpdated` (LIDO-EVT-005) if nonzero
  5. Emit `WithdrawClaimed(_requestIds, ethReceived)` (LIDO-EVT-003)
- **revert / early return**: unknown ID → `UnknownRequest`; multiple requests without hints → `ClaimHintsRequired`; claim batch cap exceeded → `AsyncRequestClaimTooLarge`; hint-length mismatch → `WithdrawalQueueRequestMismatch`; not finalized → Withdrawal Queue reverts (early claim not possible. LIDO-ERR-001).
- **Emitted events**: `WithdrawClaimed(uint256[] requestIds, uint256 ethReceived)` (LIDO-EVT-003) / `OwnIdleUnderlyingUpdated(uint256 ownIdleUnderlying)` (LIDO-EVT-005, omitted when `ethReceived == 0`).
- **Design notes**:
  - **pending subtraction is based on recorded amount**: `pendingWithdrawAmount` is subtracted by the stETH amount recorded at request time, stabilizing in-flight estimates. Even if the actual ETH received differs slightly from the requested stETH amount due to the finalization rate, that difference naturally appears in `_estimatedTotalUnderlying()` (including self-owned idle WETH) and `realizedYield()`.
  - **Finalization alone does not settle profit/loss**: Even after Lido finalizes a request, this Strategy's AUM still uses `pendingWithdrawAmount` until `claimLidoWithdrawals` executes. Haircut / surplus from the finalization amount enters accounting only after the claim creates self-owned idle WETH, so incident writeoff / liquidation decisions should compare `ethReceived`, `estimatedTotalUnderlying()`, and `principal` after claim execution.
  - **After claim, it becomes self-owned idle WETH and is eligible for return by `_doWithdraw`**: This is the first point where the "immediately withdrawable amount" increases. The actual push to the Vault and `principal` subtraction are handled by `sendToVault` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-002) (claim itself does not move `principal`).
  - **Do not mix raw ETH donations**: Only the claim-time ETH balance delta is wrapped, so raw ETH sent earlier is not counted as self-owned idle.
  - **claim hint optimization**: The no-hint overload uses Lido's single-request claim, while multiple requests are batch-claimed by an off-chain keeper that obtains hints via `findCheckpointHints` or similar. How hints are obtained is left to the off-chain operational procedure. If pending requests exceed 32, split them across multiple transactions.
- **Verification**: unit (permissionless claim, unknown ID revert, multiple-without-hints revert, hint-length mismatch revert, pending subtraction, ETH→WETH wrap, self-owned idle accounting, raw ETH donation exclusion), fork (claim after finalization, revert before finalization), invariant=LIDO-INV-005 / LIDO-INV-010.

### LIDO-FR-008: emergencyWithdrawFromLido (emergency recovery and explicit non-atomic limitation)

- **Type**: Functional | **Source**: [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) protocol-specific emergency recovery function (`emergency*From{Protocol}()`) / async limitation
- **Signature**: `emergencyWithdrawFromLido() external onlyOwner returns (uint256 sent)` / `emergencyWithdrawFromLido(uint256 _maxStETHToRequest) external onlyOwner returns (uint256 sent)`
- **Purpose**: An emergency function for cases where a serious incident is suspected in Lido / stETH / wstETH, allowing the Owner (Guardian multisig) to **(a) push already-claimed self-owned idle WETH to the Vault within the same tx, and (b) issue unstake requests for remaining wstETH**. Staked principal cannot be recovered immediately because it must wait for finalization. Direct WETH/raw ETH donations are not treated as Lido principal.
- **Permissions**: `onlyOwner` (Guardian multisig). Separated from the operations role (ALLOCATOR) (LIDO-SEC-003).
- **Preconditions (Checks)**: `caller == Owner`.
- **Behavior (Effects)**:
  1. **Determine self-owned idle** — `idle = min(_ownIdleUnderlying, WETH.balanceOf(this))`. Raw ETH is not wrapped, and direct WETH donations are not included because they do not increase `_ownIdleUnderlying`
  2. **Atomic push to Vault** — if `idle != 0`, `sent = CollateralVault.receiveFromStrategy(idle)` (immediately accounted to the Vault buffer and valuation cache is also reduced), `_ownIdleUnderlying -= idle`, and `principal -= min(sent, principal)` as returned-principal accounting
  3. **Unstake request for remaining wstETH** — If `remaining = min(_ownWstETH, wstETH.balanceOf(this))` exists, the no-arg overload uses the implementation per-tx ceiling (`MAX_STETH_WITHDRAWAL_AMOUNT * MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL`), while the overload with `_maxStETHToRequest` caps the request amount at `min(_maxStETHToRequest, implementation ceiling)`. Split the resulting stETH request amount so each chunk falls within MIN/MAX, issue `withdrawalQueue.requestWithdrawalsWstETH(amounts, this)`, add `pendingWithdrawAmount += requestAmount`, subtract `_ownWstETH -= queuedWstETH`, and record requestIds (same bookkeeping as LIDO-FR-006). **ETH recovery for this portion completes only through `claimLidoWithdrawals` + `sendToVault` after finalization**
  4. Emit `EmergencyWithdrawn(sent)` (`BaseStrategy` common event) / if remaining wstETH was requested, emit `WithdrawRequested` (LIDO-EVT-002), and return `sent`
- **revert / early return**: Non-Owner → revert; both idle and stETH are 0, or `_maxStETHToRequest` is below MIN so no requestable amount exists → exit normally without doing anything (`sent = 0`).
- **Emitted events**: `EmergencyWithdrawn(uint256 amount)` (common) / `WithdrawRequested(...)` (if remaining wstETH was requested).
- **Design points**:
  - **Immediate full recovery is not guaranteed (honest limitation)**: Aave’s `emergencyWithdrawFromAave` can return the full amount to the Vault in one tx, but Lido cannot immediately convert staked principal into ETH. This function only performs an “atomic push of self-owned idle WETH that can be sent immediately” + “issuance of an unstake request for the remainder”; return of staked principal to the Vault is rate-limited by finalization (~1-5 days, longer during congestion). As a requirement, it **does not promise immediate redemption** (consistent with LIDO-ERR-004 / [Product-Overview](../protocol/product/Product-Overview.md) SYS-NFR-004).
  - **Third-party donations are not recovery targets**: `emergencyWithdrawFromLido` uses only `min(_ownWstETH, wstETH.balanceOf(this))` for unstake requests and only `min(_ownIdleUnderlying, WETH.balanceOf(this))` for the immediate push. Direct stETH / wstETH / WETH / raw ETH donations are excluded from AUM and are not treated as protocol backing by this Lido-specific emergency path. If mis-sent asset recovery is introduced, it must be a separate governance / upgrade procedure that does not break the boundary between donations and protocol-owned positions.
  - **Fixed destination**: The push destination for self-owned idle funds is fixed to the Vault and has no arbitrary `_to` (LIDO-SEC-003). The owner of unstETH for the remaining wstETH is also the Strategy itself and is not transferred to a third party.
  - **Temporary window for `backingRatio()`**: Idle funds are atomically pushed, and remaining wstETH stays in AUM as bps-adjusted `pendingWithdrawAmount`, avoiding an improper temporary decrease in `backingRatio()` during normal emergency recovery. If incident evidence suggests a pending haircut, after `pausedAllocation == true`, the Vault `WRITEOFF_ROLE` can lower `pendingWithdrawalValuationBps` explicitly instead of treating the request flow itself as a loss.
  - **Difference from `BaseStrategy.emergencyWithdraw`**: The common `emergencyWithdraw(uint256)` is a generic rescue mechanism that sends Underlying directly held by the Strategy to the Vault and does not decrease `principal`. It can recover direct WETH donations if needed, but that is not a Lido principal return. `emergencyWithdrawFromLido()` is a Lido-specific function that unwinds the Lido position as much as possible (push claimed self-owned idle funds + request unstake for the remainder) and accounts Vault-received amounts as returned principal. Neither has an arbitrary destination.
- **Verification**: unit (onlyOwner, self-owned idle atomic push, direct WETH/raw ETH donation exclusion, issuance of requestWithdrawalsWstETH for remaining wstETH, overload request amount cap, fixed Vault destination, does not promise immediate full recovery), fork (push claimed self-owned idle funds + request unstake for the remainder).

### LIDO-FR-009: setReferral (referral update)

- **Type**: Functional | **Source**: `setReferral` in the old prototype implementation / Lido referral program
- **Signature**: `setReferral(address _referral) external onlyOwner`
- **Purpose**: Updates the `referral` passed to `lido.submit`. The destination if Lido grants referral incentives.
- **Permission**: `onlyOwner` (Guardian multisig).
- **Behavior (Effects)**: `referral = _referral` (zero allowed); emits `ReferralUpdated(_referral)` (LIDO-EVT-001).
- **revert / early return**: Non-Owner → revert.
- **Emitted events**: `ReferralUpdated(address indexed referral)` (LIDO-EVT-001).
- **Design points**: Reflected in `_doDeposit` `submit` calls from the next time onward. Does not apply retroactively to past submits. If referral incentives are received in another token, handle them according to `sweepRewardToken` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-010), and do not sweep stETH / unstETH as protected tokens (LIDO-SEC-007). The finalized referral value is LIDO-TBD-002.
- **Verification**: unit (onlyOwner, referral reflection, application to next submit).

---

## 7. State Variables and Accounting Model

In addition to common storage held by `BaseStrategy` (`vault` / `underlyingToken` / `_principal` / `_pendingOwner` / `upgrader`) and async shared storage held by `AsyncRequestStrategy` (`_ownIdleUnderlying` / `pendingWithdrawAmount` / requestId management), `LidoStrategy`-specific storage is as follows. `lido` / `stETH` / `withdrawalQueue` / `weth` are fixed in `initialize` and cannot be changed thereafter.

| Variable | Type | Role | Finalization |
| --- | --- | --- | --- |
| `lido` | `ILido` | Lido stETH (`submit` call target) | Fixed and immutable in `initialize` |
| `stETH` | `IStETH` | ERC-20 view of stETH (= same address as `lido`). Input to `wstETH.wrap` and intermediate token | Fixed and immutable in `initialize` |
| `wstETH` | `IWstETH` | Lido wstETH (`wrap` / `unwrap` / `getStETHByWstETH` / `getWstETHByStETH` / `balanceOf` call target). The **holding form and basis for AUM valuation** of this Strategy | Fixed and immutable in `initialize` |
| `withdrawalQueue` | `IWithdrawalQueueERC721` | Lido Withdrawal Queue (requestWithdrawalsWstETH / claimWithdrawal / MIN and MAX) | Fixed and immutable in `initialize` |
| `weth` | `IWETH` | Holds the Underlying (= `underlyingToken`) typed for ETH operations | Fixed and immutable in `initialize` |
| `referral` | `address` | Referral for `lido.submit` | Default in `initialize` / `setReferral` |
| `_ownWstETH` | `uint256` | wstETH obtained by this Strategy itself through submit→wrap (= its own stETH shares). Does not include third-party donations. Basis for AUM valuation (LIDO-FR-005) | Increased in `_doDeposit` / decreased in `requestLidoWithdrawal` and `emergencyWithdrawFromLido` |
| `_ownIdleUnderlying` | `uint256` | Idle Underlying received and wrapped by this Strategy itself through Lido Withdrawal Queue claims. Does not include third-party WETH/raw ETH donations. Upper bound for the idle AUM component, normal push, and Lido emergency push | Increased in `claimLidoWithdrawals` / decreased through `_doWithdraw`, `emergencyWithdrawFromLido`, and the common `emergencyWithdraw` hook |
| `pendingWithdrawAmount` | `uint256` | Total stETH amount submitted to the Withdrawal Queue and not yet claimed (pending principal) | Increased in `requestLidoWithdrawal` / decreased in `claimLidoWithdrawals` |
| `pendingWithdrawalValuationBps` | `uint256` | Effective valuation bps for pending principal. Fresh default is 10000; unset storage is treated as 10000; Vault `WRITEOFF_ROLE` can lower to 0..10000 after incident freeze; restoration / upward changes do not require pause | Set to 10000 in `initialize` / updated by `setPendingWithdrawalValuationBps` |
| Unclaimed requestId management | `mapping`/array | Unclaimed requestIds and requested amounts (used for pending subtraction at claim time and to prevent missed claims) | Added in `requestLidoWithdrawal` / removed in `claimLidoWithdrawals` |

**Accounting model**: Accounting such as self-management of deployed principal `principal` and `realizedYield = max(estimatedTotalUnderlying − principal, 0)` belongs to `BaseStrategy` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)). `LidoStrategy` is responsible for valuation of Lido-side positions (`_estimatedTotalUnderlying`) and the asynchronous lifecycle (pending / requestId).

- **AUM composition**: `estimatedTotalUnderlying = getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`. It aggregates three components denominated in ETH/WETH: staked funds (including canonical rate), bps-adjusted pending unstake funds, and claimed self-owned idle funds. Pending bps math rounds down. Direct stETH / wstETH / WETH / raw ETH donations are not included in AUM.
- **Increase/decrease of `principal`**: `deposit` adds the “WETH amount sent by the Vault.” `sendToVault` and `emergencyWithdrawFromLido` subtract `min(sent, principal)` for the “`sent` amount actually received by the Vault” (principal-first). `writeoffPrincipal` subtracts `min(_amount, principal)`. It is unchanged by `sendProfitToVault` / `requestLidoWithdrawal` / `claimLidoWithdrawals` / `setReferral`.
- **Separation of principal and yield (SYS-RISK-004 “prevent mixing of yield and principal”)**: Appreciation from increases in the canonical rate of wstETH appears in `realizedYield()` and is pushed via `sendProfitToVault` (`principal` unchanged). Principal is pushed via `sendToVault` or the self-owned idle push in `emergencyWithdrawFromLido` (both decrease `principal` based on `sent`). Pending funds (during unstake) remain in AUM without reducing `principal`, and principal returns to the Vault and reduces `principal` only through the route claim → self-owned idle WETH → `sendToVault` / `emergencyWithdrawFromLido`.
- **Pending principal does not temporarily make `principal` fall below it**: Even if stake moves to pending when a request is issued, `principal` is left unchanged and pending is normally included at `pendingWithdrawalValuationBps = 10000`, so `realizedYield()` does not appear to swing negative during ordinary unstake. If incident evidence requires a lower bps after freeze, that markdown is explicitly reflected in `estimatedTotalUnderlying()` and the Vault's conservative value (LIDO-INV-005 / LIDO-INV-006).
- **Accounting boundary for reward tokens**: stETH itself is a position token representing staking principal + interest, not a reward token. stETH / unstETH NFTs are rejected as protected tokens in `sweepRewardToken` (LIDO-SEC-007). Only if Lido referral or similar rewards are received in another token are they sent to the Treasury through the common `BaseStrategy.sweepRewardToken` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-010).

---

## 8. Invariants (INV)

| ID | Invariant | Verification |
| --- | --- | --- |
| LIDO-INV-001 | `_ownWstETH` increases or decreases only through this Strategy’s own `_doDeposit` (adding the `wrap` return value) / `requestLidoWithdrawal` and `emergencyWithdrawFromLido` (subtracting the deposited wstETH amount with a lower clamp at 0), and does not increase due to third-party stETH / wstETH donations | invariant |

| LIDO-INV-002 | `_estimatedTotalUnderlying()` is `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`. Pending bps math rounds down. Third-party donations are not included in AUM, while canonical rate decreases (slashing) are reflected. Raw ETH balance is not included | invariant / fork |
| LIDO-INV-003 | `lido` / `stETH` / `wstETH` / `withdrawalQueue` / `weth` are immutable after `initialize` (no setters) | invariant |
| LIDO-INV-004 | `_doWithdraw` does not return more than self-owned idle WETH (`actual <= min(_ownIdleUnderlyingBefore, weth.balanceOf(this))`). It decreases `_ownIdleUnderlying` by the returned amount and does not synchronously unstake stETH | unit |
| LIDO-INV-005 | `pendingWithdrawAmount` matches the sum of recorded requested amounts for unclaimed requestIds, increases in `requestLidoWithdrawal`, decreases in `claimLidoWithdrawals`, and does not double-claim already claimed IDs | invariant |
| LIDO-INV-006 | `requestLidoWithdrawal` / `claimLidoWithdrawals` do not change `principal` (movement to pending and claims do not affect principal accounting. `principal` is decreased only based on Vault-received `sent` in `sendToVault` and `emergencyWithdrawFromLido`) | invariant |
| LIDO-INV-007 | `sweepRewardToken` rejects Underlying(WETH), stETH, wstETH, and unstETH, and cannot move them to the Treasury (position token protection) | unit |
| LIDO-INV-008 | `underlying()` remains WETH and matches the Underlying of the corresponding Vault (WETH underlying branch) | invariant |
| LIDO-INV-009 | `wstETH.stETH()` matches `lido`, and Withdrawal Queue bounds must be an initialized venue with `MIN != 0` and `MAX >= MIN` | unit / manual |
| LIDO-INV-010 | `_ownIdleUnderlying` increases only by the self-received WETH amount actually wrapped from Lido claims, and decreases through `_doWithdraw` / `emergencyWithdrawFromLido` / the common `emergencyWithdraw` hook. Direct WETH or raw ETH donations do not increase it, and stale self-owned idle capacity cannot be refilled by later donations | unit / invariant |

> Common invariants (`principal` non-negative, `sendProfitToVault`/`emergencyWithdraw` keeping `principal` unchanged, `realizedYield` identity, 2-step Owner, UUPS upgrader restriction, etc. STGY-INV-001..010) are canonicalized in the [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) and are not repeated in this document.

---

## 9. Security Requirements (SEC)

### LIDO-SEC-001: Investment destination addresses fixed at initialize time

- Type: Security
- Statement: `lido` / `stETH` / `withdrawalQueue` / `weth` and approval to the Withdrawal Queue must be fixed in `initialize`, and there must be no post-change setters such as `setLido` / `setWithdrawalQueue` (eliminating the attack surface where “the Strategy side can move the investment destination” and storage migration risk). To change the investment destination, recreate the entire Strategy and replace the Vault registration (same policy as AAVE-GOV-001 in the [AaveV3Strategy Requirements](../protocol/product/spec/strategies/AaveV3Strategy.md)).
- Verification: invariant=LIDO-INV-003, manual (code review confirming absence of setters)

### LIDO-SEC-002: Exclusion of AUM inflation via third-party donations and rebases

- Type: Security
- Statement: stETH / wstETH / WETH can be transferred to this Strategy by anyone, and raw ETH can be sent directly to `receive()` (donation paths exist). If these `balanceOf` / ETH balances are used directly for AUM, third-party donations can inflate `realizedYield()`, enabling an attack that routes arbitrary value into the Treasury through `sendProfitToVault` plus the Vault revenue-to-Treasury path. To prevent this, `_estimatedTotalUnderlying()` must value the staked portion through `_ownWstETH`, the claimed idle portion through `_ownIdleUnderlying`, and use `getStETHByWstETH(min(_ownWstETH, wstETH.balanceOf(this))) + pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000 + min(_ownIdleUnderlying, WETH.balanceOf(this))`. The canonical rate reflects legitimate staking appreciation while excluding donations that only increase raw balances. Raw ETH is not included in valuation or the Lido-specific emergency push.
- Verification: invariant=LIDO-INV-001/002/010, fork (injecting stETH / wstETH / WETH / raw ETH donations does not increase `realizedYield`, while an increase in the canonical rate is reflected)

### LIDO-SEC-003: Fixed emergency recovery destination and permission separation

- Type: Security
- Statement: `emergencyWithdrawFromLido` must be `onlyOwner` and must not be executable by an operational role (ALLOCATOR). The withdrawal destination / push destination for self-owned idle funds must be fixed to the Vault (no arbitrary `_to`), and the unstETH owner for remaining wstETH must also be fixed to the Strategy itself, so that funds cannot be withdrawn to an arbitrary destination even if the Owner key is compromised. The fact that staked principal cannot be immediately converted to ETH must be explicitly stated as a design limitation (LIDO-FR-008), and immediate full recovery must not be promised. Direct WETH/raw ETH donations must not be processed as Lido principal returns.
- Verification: unit (call from ALLOCATOR reverts, self-owned idle push is fixed to the Vault, direct donation is excluded, remaining wstETH has self owner, no arbitrary destination)

### LIDO-SEC-004: Permissions and griefing resistance for asynchronous keeper (request/claim)

- Type: Security
- Statement: `requestLidoWithdrawal` must be restricted to ALLOCATOR to prevent griefing where a third party issues meaningless unstake requests and stops yield generation. `requestLidoWithdrawal` must not request more than self-owned holdings (stETH equivalent of `min(_ownWstETH, wstETH.balanceOf)`) and must split requests according to MIN/MAX constraints. `claimLidoWithdrawals` is permissionless so finalized request settlement does not depend on a keeper key, but it must reject unknown requestIds, double-claiming, and no-hint claims of multiple requests.
- Verification: unit (request restricted to ALLOCATOR, self-owned upper bound, MIN/MAX splitting, permissionless claim, claim rejects unknown IDs / double claims)

### LIDO-SEC-005: Rejection of claims before finalization

- Type: Security
- Statement: `claimWithdrawal` for a requestId that has not been finalized reverts in the Lido Withdrawal Queue. This Strategy relies on that behavior and must not attempt to claim by independently falsifying finalization state. Operations should check finalization with `getWithdrawalStatus` before calling `claimLidoWithdrawals`. Early claim unavailability is treated as the normal path (retry), not as unrecoverability (LIDO-ERR-001).
- Verification: unit (revert propagates before finalization), fork (claim succeeds only after finalization)

### LIDO-SEC-006: Safe-side handling of 1-wei rounding and accounting for stETH / wstETH

- Type: Security
- Statement: ±1 wei / floor rounding can occur in conversions for `submit` (ETH→stETH) and `wrap` (stETH→wstETH). `principal` is increased by the amount sent from the Vault (`_doDeposit` argument), and rounding differences are absorbed by `_ownWstETH` (wstETH quantity) and `realizedYield()`, so `principal` must not be over-accounted. `pendingWithdrawAmount` is decreased based on the recorded requested amount, and small deviations from the finalization rate are naturally corrected by inclusion in self-owned idle WETH. `_ownWstETH` / `_ownIdleUnderlying` decreases and pending decrease must be clamped at a lower bound of 0. Because wstETH is non-rebasing, there is no accumulation of rounding on each rebase, and rounding exposure is smaller than when directly holding and tracking stETH.
- Verification: unit (1-wei boundary, no principal over-accounting, pending clamped at lower bound of 0)

### LIDO-SEC-007: Prohibition on reward sweep of stETH / unstETH

- Type: Security
- Statement: stETH / wstETH are position tokens representing staking principal plus interest, and the unstETH NFT is a withdrawal claim right; none of them are reward tokens. If `sweepRewardToken` can move them to the Treasury, it bypasses the Lido withdrawal path, `_ownWstETH`, and Vault backing accounting, so `LidoStrategy` must override `BaseStrategy._isSweepProtectedToken` and include Underlying(WETH), stETH, wstETH, and unstETH as protected tokens. Sweeping true reward tokens such as Lido referrals remains possible.
- Verification: unit (`sweepRewardToken(stETH/unstETH/WETH)` reverts, normal reward token sweep succeeds)

### LIDO-SEC-008: fail-fast on Lido venue miswiring and inconsistent wstETH return value

- Type: Security
- Statement: `initialize` must verify `wstETH.stETH() == lido` and Withdrawal Queue bounds (`MIN != 0` / `MAX >= MIN`) to reject miswired Lido address triples. `_doDeposit` must not increase `_ownWstETH` by trusting only the return value from `wstETH.wrap`; it must treat the before/after delta of `wstETH.balanceOf(this)` as truth and cross-check it against the return value. Mismatch reverts with `LidoShareBalanceMismatch`, so the external protocol adapter accounting does not depend on a false return value.
- Verification: unit (reject wstETH/stETH mismatch, reject invalid Queue bounds, reject wrap return / balance delta mismatch), manual (deploy address review)

> **reentrancy / CEI**: Permission and accounting defenses for push paths are the responsibility of `BaseStrategy` / CollateralVault ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) / [CollateralVault Requirements](../protocol/product/spec/CollateralVault.md)), and this document does not respecify them. This Strategy receives ETH through `weth.withdraw` / `lido.submit` / `withdrawalQueue.claimWithdrawal` (`receive()`). Before and after these external calls, wstETH balance, received stETH, and pending are accounted for using before/after measurement or recorded amounts, and claims follow the order of confirming existence in the unclaimed set → state update → external call. If a path with strong callback behavior is added, introducing a reentrancy guard on the `BaseStrategy` side should be reconsidered according to the [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md).

---

## 10. Governance, Operations, and Upgrade Requirements (GOV)

Common permission and upgrade policies (`STGY-GOV-001..005`) are canonical in [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md). The following requirements cover retirement and recovery only; they do not start a new instance.

### <a id="lido-gov-001-retirement--non-activation-gate"></a>LIDO-GOV-001: Retirement / non-activation gate

- Statement: Do not deploy, whitelist, or register the current `LidoStrategy`; remove it from manifest, preflight, and generated-config selection. Audit-critical removal occurs only after the external auditor confirms the scope reduction, post-removal file list, fresh nSLOC, review boundary, and remaining async-base test coverage. If inventory finds an existing instance, first stop allocation; recover pending, idle, and principal; verify `principal == 0` and live AUM 0; and remove it from the Vault. A future stETH Strategy is a new proposal requiring governance approval, implementation review, and external audit—not a reactivation of this code.
- Verification: manual (auditor scope sign-off, instance inventory, negative deploy/register check, post-removal file list and nSLOC, remaining async test coverage)

### LIDO-GOV-002: Operational Runbook for asynchronous keeper

- Statement: Do not start a new keeper. Only if inventory finds an existing instance with recoverable balances may ALLOCATOR use `requestLidoWithdrawal` for retirement recovery, while any caller may trigger finalized `claimLidoWithdrawals`. The recovery procedure records remaining positions and pending requests after allocation is stopped, finalization status, `sendToVault` of claimed self-owned WETH, principal/AUM/Vault-receipt readback, and separation of donation residue. Do not remove required readers or runbooks until evidence is complete.
- Verification: manual (operational Runbook and degradation review during keeper failure)

### LIDO-GOV-003: Stop new allocations and emergency recovery during incidents

- Statement: If inventory finds an existing instance, GUARDIAN disables it (`weightBps = 0`, `enabled = false`) regardless of whether a Lido incident is present. Owner returns idle funds and requests unstaking of remaining wstETH through `emergencyWithdrawFromLido`; confirmed unrecoverable principal is written off. If no instance exists, do not create this recovery route; proceed to remove source and runtime surfaces.
- Verification: manual (monitoring and emergency Runbook), integration (`emergencyDisableStrategy` → `emergencyWithdrawFromLido` → writeoff)

---

## 11. Event and Monitoring Requirements (EVT)

Common events (`Deposited` / `SentToVault` / `ProfitSentToVault` / `PrincipalWrittenOff` / `EmergencyWithdrawn` / `RewardTokenSwept` / Owner and Upgrader related) are emitted by `BaseStrategy` ([Strategy Requirements](../protocol/product/spec/strategies/Strategy.md)). Lido-specific events and monitoring are below.

| ID | Event | Purpose (off-chain) |
| --- | --- | --- |
| LIDO-EVT-001 | `ReferralUpdated(address indexed referral)` | Track `setReferral` |
| LIDO-EVT-002 | `WithdrawRequested(uint256[] requestIds, uint256 stETHAmount)` | Issuance of unstake requests by `requestLidoWithdrawal` / `emergencyWithdrawFromLido`. Track pending deployed amount and unstETH |
| LIDO-EVT-003 | `WithdrawClaimed(uint256[] requestIds, uint256 ethReceived)` | Track receipts from `claimLidoWithdrawals` (finalization completion and self-owned idle WETH increase) |
| LIDO-EVT-004 | `OwnWstETHUpdated(uint256 ownWstETH)` | Own wstETH balance after `_doDeposit` / `requestLidoWithdrawal` / `emergencyWithdrawFromLido`. Monitor changes in the AUM basis |
| LIDO-EVT-005 | `OwnIdleUnderlyingUpdated(uint256 ownIdleUnderlying)` | Self-owned idle WETH balance after `claimLidoWithdrawals` / `_doWithdraw` / `emergencyWithdrawFromLido` / common `emergencyWithdraw`. Distinguish direct WETH donations from protocol-owned idle |

**Monitoring metrics (Lido-specific)**:

- **Pending withdraw backlog**: Time-series changes in `pendingWithdrawAmount` and unclaimed requestIds. Monitor whether finalization delays are becoming prolonged relative to `withdrawDelay` ([Parameters](../Parameters.md) §4-4).
- **Finalization status**: `isFinalized` / `isClaimed` from `getWithdrawalStatus(requestIds)`. Detect missed claims for finalized requests (not converted into self-owned idle WETH, delaying Vault buffer replenishment). Even if a request is finalized, it is valued by the amount recorded at request time until claim execution, so haircut / surplus should be confirmed from `WithdrawClaimed.ethReceived`.
- **Divergence between AUM and actually recoverable amount**: During slashing or stETH depeg, `_estimatedTotalUnderlying` (wstETH × `getStETHByWstETH`) can diverge from the actually recoverable amount, so visualize it with a subgraph. Track yield/impairment through changes in `OwnWstETHUpdated` and `getStETHByWstETH`.
- **Donation residue**: Monitor `WETH.balanceOf(strategy) - min(_ownIdleUnderlying, WETH.balanceOf(strategy))` and `address(strategy).balance`. These are not backing / yield. If needed, direct WETH can be returned through the common `emergencyWithdraw`; raw ETH requires a separate recovery policy. Do not mix these residues into Lido-specific emergency or liquidation decisions.
- **Lido protocol health**: Continuously monitor consensus-layer slashing, Withdrawal Queue congestion (time required for finalization), and stETH secondary-market depeg on the Lido dashboard / Governance forum.

---

## 12. Failure and Incident Behavior (ERR)

For common incident cases (handling push under insufficient liquidity as a normal path, **absorption of asynchronous protocols STGY-ERR-002**, and damage boundaries during key compromise), see [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md). This section describes only Lido-specific events and mitigations.

### LIDO-ERR-001: Finalization delay and inability to claim early

- Trigger: Lido Withdrawal Queue finalization depends on Lido oracle reports and generally takes about 1-5 days, or longer during congestion. `claimWithdrawal` before finalization reverts.
- Behavior: during recovery of any inventoried legacy instance, `claimLidoWithdrawals` reverts for unfinalized requests (LIDO-SEC-005). Without self-owned idle WETH, `_doWithdraw` returns `0` and `sendToVault` reports `sent = 0`. The current 3-day baseline `withdrawDelay` is not sized to absorb this async queue.
- Mitigation: follow `LIDO-GOV-001`. If inventory finds recoverable balances, stop new allocation, retain the reader/runbook, monitor finalization, then claim and `sendToVault` before unregistering (LIDO-GOV-002). Do not restore the legacy 17-day setting to the Day-1 configuration.

### LIDO-ERR-002: Request constraints from MIN/MAX_STETH_WITHDRAWAL_AMOUNT

- Trigger: The Withdrawal Queue only accepts at least `MIN_STETH_WITHDRAWAL_AMOUNT` (mainnet default 100 wei) and at most `MAX_STETH_WITHDRAWAL_AMOUNT` (same, 1000 stETH) per request.
- Behavior: `requestLidoWithdrawal` splits the requested amount into multiple chunks at or below MAX and structures each chunk to be at or above MIN (LIDO-FR-006). Tiny requests below MIN are `AmountOutOfRange`.
- Mitigation: Expand large requests into multiple unstETH requests using split logic. Operationally combine tiny remainders into the next request.

### LIDO-ERR-003: stETH slashing and principal impairment

- Trigger: Large-scale slashing occurs in Lido's consensus layer, lowering the wstETH-to-stETH conversion rate (`getStETHByWstETH` / `stEthPerToken` = canonical rate).
- Behavior: `_estimatedTotalUnderlying()` decreases to reflect the lower canonical rate, and if `estimatedTotalUnderlying < principal`, `realizedYield()` becomes 0; the Vault's conservative valuation `min(estimatedTotalUnderlying, principal)` decreases and is reflected downward in `backingRatio()`.
- Mitigation: Impairment that appears in accounting automatically propagates to backing. For unrecoverable amounts that do not appear in accounting / are definitive, after returning the recoverable portion with `sendToVault`, GOV finalizes a downward adjustment of `principal` using `writeoffStrategyPrincipal` ([CollateralVault Requirements](../protocol/product/spec/CollateralVault.md) / [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-FR-004) (SYS-RISK-004 "loss-writeoff linkage"). Avoid concentrated deployment with the Vault-side `cap` (LIDO-GOV-003).

### LIDO-ERR-004: Emergency recovery limits when Lido / Withdrawal Queue is halted

- Trigger: The Lido protocol / Withdrawal Queue is halted and `requestWithdrawalsWstETH` / `claimWithdrawal` / `claimWithdrawals` reverts.
- Behavior: Staked principal cannot be converted into ETH, and `emergencyWithdrawFromLido` can only push the idle portion (staked amounts cannot be recovered immediately. LIDO-FR-008).
- Mitigation: Unlike Aave, clearly state in the runbook and user-facing disclosures that Lido has a structure where immediate full recovery cannot be guaranteed even during emergencies (consistent with [Product-Overview](../protocol/product/Product-Overview.md) SYS-NFR-004 and "does not promise immediate redemption"). Retry after recovery. Suppress concentrated deployment with `cap` / weight, and set the allocation ratio to Lido itself conservatively ([Parameters](../Parameters.md)).

### LIDO-ERR-005: stETH secondary-market depeg (independent of withdraw rate)

- Trigger: stETH depegs against ETH on secondary markets such as DEXs.
- Behavior: This Strategy's recovery depends on the Withdrawal Queue (receiving ETH at the protocol rate), and it does not sell at secondary-market prices, so **secondary-market depeg does not directly affect this Strategy's recovered amount** (it holds until finalization and receives the equivalent of 1:1). However, there is time-value risk during finalization delays, and if the depeg is caused by consensus-layer issues, it may appear as LIDO-ERR-003.

- Mitigation: Recovery must always go through the Withdrawal Queue; no forced selling on secondary markets. Root causes of depegging (such as slashing concerns) are monitored under LIDO-GOV-003.

**Error Catalog (Lido-specific)**

| Error | Trigger |
| --- | --- |
| `ZeroAddress` | `_lido` / `_wstETH` / `_withdrawalQueue` in `initialize` is zero |
| `InvalidWstETHStETH` | `initialize` sees `wstETH.stETH()` not matching `_lido` |
| `InvalidWithdrawalQueueBounds` | `initialize` sees invalid Withdrawal Queue `MIN_STETH_WITHDRAWAL_AMOUNT` / `MAX_STETH_WITHDRAWAL_AMOUNT` bounds |
| `Unauthorized` | `requestLidoWithdrawal` by anyone other than ALLOCATOR |
| `AmountOutOfRange` | `requestLidoWithdrawal` cannot split the amount in a way that satisfies MIN/MAX |
| `LidoWithdrawalRequestTooLarge` | The split request count for `requestLidoWithdrawal` / `emergencyWithdrawFromLido` exceeds `MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL` (32) |
| `AmountExceedsStaked` | The `requestLidoWithdrawal` request exceeds self-held funds (stETH equivalent of `min(_ownWstETH, wstETH.balanceOf)`) |
| `UnknownRequest` | `claimLidoWithdrawals` specifies a requestId that is not in this Strategy's unclaimed set |
| `AsyncRequestClaimTooLarge` | `claimLidoWithdrawals` requestId count exceeds `MAX_ASYNC_REQUESTS_PER_CLAIM` (32) |
| `AsyncPendingRequestLimitExceeded` | `requestLidoWithdrawal` / `emergencyWithdrawFromLido` would exceed `MAX_ASYNC_PENDING_REQUESTS` (128) unclaimed requests |
| `LidoZeroShares` | Detects the anomaly where no wstETH is minted after `lido.submit` → `wstETH.wrap` in `_doDeposit`, so only the principal increases |
| `LidoShareBalanceMismatch` | `_doDeposit` detects mismatch between wstETH `wrap` return value and actual balance delta, or an unexpected wstETH balance decrease |
| `ClaimHintsRequired` | Multiple requestIds are specified to the no-hint overload |
| `WithdrawalQueueRequestMismatch` | Detects an inconsistency that prevents safely tracking pending requests, such as the Withdrawal Queue returning a number of requestIds different from the number of requested chunks, or the number of hints differing from the number of requestIds |
| `UnexpectedWithdrawalRequestOwner` | The Withdrawal Queue returned a requestId not owned by the Strategy |
| (Withdrawal Queue-derived revert) | Claims before finalization, Queue pause, etc. are reverted by the Lido contract and propagated (LIDO-ERR-001 / LIDO-ERR-004) |

> For common errors (`OnlyVault` / `CannotSweepProtectedToken` / `RenounceOwnershipDisabled` / common `ZeroAddress` / `Unauthorized`), see [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) STGY-ERR-001.

---

## 13. Acceptance Criteria and Verification Plan

The pass condition for each requirement is satisfying the verification method in the table below (test names and execution results are not written in this document; only the type of method is specified). For verification of common functions (`deposit` / `sendToVault` / `sendProfitToVault` / `writeoffPrincipal` / `emergencyWithdraw` / `sweepRewardToken` / 2-step Owner / UUPS), see [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md).

| ID | Requirement (Summary) | Verification Method |
| --- | --- | --- |
| LIDO-FR-001 | initialize (fixed investment target, `upgrader` argument, stETH→wstETH / wstETH→WQ approvals, zero/multiple initialization revert) | unit |
| LIDO-FR-002 | addStrategy prerequisites (whitelist→`addStrategy`(3 arguments), Underlying=WETH match, no isAsync notification) | integration, manual |
| LIDO-FR-003 | _doDeposit (WETH→ETH→submit→wrap, wstETH accounting, no donation mixing) | unit, fork, invariant=LIDO-INV-001 |
| LIDO-FR-004 | _doWithdraw (self-owned idle WETH only, returns 0 when `ownIdle==0`, direct WETH donation excluded, does not touch stETH) | unit, integration |
| LIDO-FR-005 | _estimatedTotalUnderlying (min, include pending, exclude stETH/wstETH/WETH/raw ETH donations) | unit, fork, invariant=LIDO-INV-002/005/010 |
| LIDO-FR-006 | requestLidoWithdrawal (ALLOCATOR, requestWithdrawalsWstETH, MIN/MAX splitting, request count cap, self-held upper bound, pending bookkeeping, wstETH subtraction) | unit, fork, invariant=LIDO-INV-005 |
| LIDO-FR-007 | claimLidoWithdrawals (permissionless finalized claim, subtract pending, convert claim-time ETH delta→WETH into self-owned idle, raw ETH donation exclusion, reject unknown/double claims, hinted batch claim) | unit, fork, invariant=LIDO-INV-005/010 |
| LIDO-FR-008 | emergencyWithdrawFromLido (onlyOwner, self-owned idle atomic push, direct WETH/raw ETH donation exclusion, returned-principal accounting, request remaining wstETH, overload request amount cap, does not promise immediate full recovery, fixed destination) | unit, fork |
| LIDO-FR-009 | setReferral (onlyOwner, reflected in next submit) | unit |
| LIDO-INV-001..010 | Each invariant in §8 | invariant / fork / unit (as described in §8) |
| LIDO-SEC-001..007 | Each security requirement in §9 | invariant / unit / fork / manual |
| LIDO-EVT-001..005 | Each event emission in §11 | unit |
| LIDO-ERR-001..005 | Lido-specific abnormal cases in §12 | unit, fork, manual |

**Trace to the 5 mandatory items of SYS-RISK-004** (satisfaction assuming Day-1 launch):

| SYS-RISK-004 Request | Satisfying Requirement |
| --- | --- |
| async recovery trigger | LIDO-FR-006 (`requestLidoWithdrawal`) |
| pending principal | LIDO-FR-005 / LIDO-INV-005 / LIDO-INV-006 (include pendingWithdrawAmount at 10000 bps in normal AUM, allow post-freeze incident-time bps discounting, keep principal unchanged) |
| prevention of revenue/principal commingling | §7 Accounting Model / LIDO-FR-004 / LIDO-INV-006 / LIDO-INV-010 (`sendToVault` / emergency self-owned idle push = principal, `sendProfitToVault` = revenue, pending leaves principal unchanged, donations are not mixed into yield/principal) |
| becoming claimable | LIDO-FR-007 (`claimLidoWithdrawals`) + Vault VAULT-FR-006 (user claim) |
| loss/writeoff linkage | LIDO-FR-005 / LIDO-ERR-003 (reflect slashing → writeoffStrategyPrincipal) |

---

## 14. Open Items (TBD)

### LIDO-TBD-001

Resolved (2026-06-16 update): `requestLidoWithdrawal` is restricted to ALLOCATOR, and `claimLidoWithdrawals` is permissionless. Finalized claims only receive ETH into the Strategy itself and wrap it into WETH, with no arbitrary destination, so loss realization does not depend on a keeper key. `_stETHAmount == 0` is a no-op that returns an empty array. Related: LIDO-FR-006 / LIDO-FR-007.

### LIDO-TBD-002

Final value of `referral` — leave as zero / Lido referral registration / own identifier. Related: LIDO-FR-009 / LIDO-FR-003.

### LIDO-TBD-003

Resolved (2026-06-17 implementation): `_ownIdleUnderlying` was introduced. `claimLidoWithdrawals` wraps only the ETH balance delta received by the claim, and tracks only the actual WETH delta as self-owned idle. `_estimatedTotalUnderlying` / `_doWithdraw` / `emergencyWithdrawFromLido` use only `min(_ownIdleUnderlying, WETH.balanceOf(this))` as protocol-owned idle, so third-party WETH donations and raw ETH donations are not mixed into AUM, normal push, or Lido-specific emergency principal return. Direct WETH donations can be returned through the common `BaseStrategy.emergencyWithdraw` if needed, but that does not decrease `principal`. Raw ETH is not valued; if mis-sent recovery is introduced, it must be a separate recovery policy that preserves the boundary between donations and protocol-owned positions.

stETH / wstETH donations also remain excluded from protocol-owned position valuation and recovery. This conservative boundary avoids donation-driven AUM inflation; any future mis-sent recovery must preserve `_ownWstETH` / `_ownIdleUnderlying` / pending request invariants.

### LIDO-TBD-004

Resolved (2026-06-14 implementation): The no-hint overload is for a single request only; multiple requests are batch-claimed with the hinted `claimLidoWithdrawals(requestIds, hints)`. Unclaimed requestIds are held with an array + index mapping + amount mapping. The number of requests per tx and the retrieval range of `findCheckpointHints` are kept within the gas limit by the off-chain keeper runbook. Related: LIDO-FR-007 / §7.

### LIDO-TBD-005 (Resolved — wstETH Adopted)

**Decision: adopt wstETH (non-rebasing)**. The proposal to directly hold stETH (rebasing) is rejected. This document §1-§13 already reflects this decision (IDs are retained for traceability).
- **Rationale**: ① wstETH is non-rebasing, so `balanceOf` is stable, making it more robust than direct stETH holding for accounting, donation exclusion, and 1-wei rounding (LIDO-SEC-002 / LIDO-SEC-006). ② AUM valuation uses the canonical wstETH rate (`getStETHByWstETH` / `stEthPerToken`), belongs to the same family as Liquity v2 wstETH/rETH canonical-rate valuation, and is auditor-friendly. Production `CompositePriceFeed` is pruned for sUSDS in [Oracle](../protocol/product/spec/Oracle.md) ORCL-FR-012 and does not retain the WSTETH/RETH LST secondary fallback. ③ Major protocols such as Aave / Sky / Morpho / Liquity v2 uniformly adopt wstETH as the industry standard. ④ Withdrawals are symmetric with stETH because the Withdrawal Queue natively supports `requestWithdrawalsWstETH`.
- **Accepted cost**: Add one `wrap` after `submit` on deposit (slightly higher gas and one stETH→wstETH approval).
- **Scope of impact (contained within the Strategy)**: No impact on the branch dToken (Underlying = WETH), branch oracle (ETH/USD Standard), 🔵 Core, Vault `IStrategy` IF, or `withdrawDelay`. Reflected in §2.3 / §3 / §5 / §6 (LIDO-FR-001/003/005/006/008) / §7 / §8 (LIDO-INV-001/002/003/007) / §9 (LIDO-SEC-002/006/007). Related: LIDO-TBD-006.

### LIDO-TBD-006

Resolved (2026-06-18): [Product-Overview](../protocol/product/Product-Overview.md) now uses wording aligned with the implementation entity, **Lido stETH/wstETH + Withdrawal Queue**. Parent [Strategy](../protocol/product/spec/strategies/Strategy.md) already says `Lido stETH + Withdrawal Queue`. If a future Lido V3 vault product is adopted, its interface and risk profile are different enough that it should be specified as a separate Strategy rather than as an edit to this one. Related: §1 / §2.1 / LIDO-TBD-005.

### LIDO-TBD-007

Resolved: current branch values are canonical in [Parameters](../Parameters.md), and current venue adoption is canonical in the [Strategy Selection Policy](../protocol/operations/policies/Strategy-Selection-Policy.md). A future asynchronous Strategy proposal must re-derive buffer and `withdrawDelay` from its own worst-case recovery behavior. Related: LIDO-GOV-001 / LIDO-ERR-001.

---

## 15. References

### Implementation

- `contracts/src/Strategies/archive/LidoStrategy.sol` (main Lido wstETH individual Strategy)

### Related Pages

- [Strategy Requirements](../protocol/product/spec/strategies/Strategy.md) — `IStrategy` / `BaseStrategy` / push model, common permissions, common risks, common events, and **STGY-ERR-002 async handling** (parent page / canonical source)

- [CollateralVault Requirements Definition](../protocol/product/spec/CollateralVault.md) — whitelist / `addStrategy` (3 arguments) / `receiveFromStrategy` / **delayed redemption `claim` (VAULT-FR-006)** / `writeoffStrategyPrincipal` / buffer, cap, and weights
- [AaveV3Strategy Requirements Definition](../protocol/product/spec/strategies/AaveV3Strategy.md) — concrete child-document example of a synchronous Strategy (donation resistance `_ownScaledBalance` [the same idea as this document's `_ownWstETH`: self-tracking in non-rebasing units] and atomic push for strategy-specific emergency recovery)
- [Product-Overview](../protocol/product/Product-Overview.md) — architecture, separation of responsibilities, and SYS-NFR-004 (availability and fault tolerance)
- [Mainnet Launch Risk Gate](../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-004) — async Strategy activation gate
- [Parameters.md](../Parameters.md) — current branch cap, allocation, `withdrawDelay`, and buffer values
- [Strategy Selection Policy](../protocol/operations/policies/Strategy-Selection-Policy.md) — current venue adoption status
- [Oracle Requirements Definition](../protocol/product/spec/Oracle.md) — a WETH underlying branch is ETH/USD Standard (not affected by this selection). The wstETH canonical rate (`getStETHByWstETH` / `stEthPerToken`) used for this Strategy's AUM valuation is of the same family as Liquity v2 wstETH/rETH canonical-rate valuation. Production `CompositePriceFeed` is pruned for sUSDS
- [Requirements Specification Document Standard](../README.md#requirements-spec-standard) — the standard followed by this document

### External Resources

- [Lido documentation](https://docs.lido.fi/)
- [Lido stETH (Lido.sol)](https://docs.lido.fi/contracts/lido)
- [Lido Withdrawal Queue (WithdrawalQueueERC721)](https://docs.lido.fi/contracts/withdrawal-queue-erc721)
- [Lido deployed contracts](https://docs.lido.fi/deployed-contracts/)
