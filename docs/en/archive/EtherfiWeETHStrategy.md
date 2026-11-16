# 🟡 EtherfiWeETHStrategy Requirements

> **Status: Archived / Out of Day-1 scope**
>
> `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` is **archived**. Its underlying is
> structurally WETH (`initialize` takes `IWETH _weth`; the deposit path unwraps WETH to
> native ETH), and the deploy selector that rejected any non-WETH underlying -- along with
> the strategy kinds, venue structs, helpers, and env keys -- was removed in PR #1424.
> Branch 0's Vault underlying then moved from WETH to wstETH, so no current branch can
> supply one. The source is preserved unmodified at
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
> [Strategy](../protocol/product/spec/strategies/Strategy.md). `EFWEETH-*` IDs are kept for
> historical traceability and must not be reused or cited as active audit scope.
> Re-activation requires re-entry into the `DeployLiquity2` strategy selector plus a
> fresh activation package (venue evidence, risk sign-off, audit-scope change).

> ⚠️ **Retired from the Day-1 deploy surface.** With the WETH → wstETH branch swap (Branch 0 = dwstETH, aave-only Day-1 Strategy set), the staking-venue Strategy kinds were dropped and `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` are not deployed, registered, or allocated. The source and tests are not deleted: sources move to `contracts/src/Strategies/archive/` and specs to `documents/{en,jp}/archive/`, preserved as previously audited artifacts (audited at identity `0c7766e0`) and out of active scope. The archive move lands in the separate retirement change. Any future adoption is a new proposal with its own activation gate and audit.

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Archived / Out of Day-1 scope (historical material; previously audited under `0c7766e0`) |
| Implementation status | Implemented optional Strategy. A separate activation gate is required before including it in an expected launch manifest. |
| Owner | DeltaForesight |
| Target contract | `contracts/src/Strategies/archive/EtherfiWeETHStrategy.sol` (inherits `AsyncRequestStrategy` / `BaseStrategy`) / `contracts/src/Strategies/archive/WeETHWithdrawAdapter.sol` |
| Related documents | [Strategy](../protocol/product/spec/strategies/Strategy.md) / [LidoStrategy](LidoStrategy.md) / [CollateralVault](../protocol/product/spec/CollateralVault.md) / [Deployment-Configuration](../engineering/guides/Deployment-Configuration-Spec.md) |

This English page is a support translation. The Japanese
[EtherfiWeETHStrategy.md](../../jp/archive/EtherfiWeETHStrategy.md)
remains the normative source of truth.

`EtherfiWeETHStrategy` keeps the WETH underlying branch's Vault underlying as **WETH** while
deploying allocated WETH through Ether.fi eETH / weETH. Exit is asynchronous and
uses Ether.fi `WithdrawRequestNFT`.

## 1. Scope

- `underlying()`: WETH
- position token: weETH
- intermediate token: eETH
- async request: DeltaForesight `WeETHWithdrawAdapter.requestWithdraw` (a first-party adapter that unwraps weETH to eETH, then calls Ether.fi native `LiquidityPool.requestWithdraw`)
- pending position: `WithdrawRequestNFT`
- recovery asset: ETH claim wrapped back to WETH

`sendToVault` and `sendProfitToVault` can return only WETH that has already been
claimed and wrapped by the Strategy. Shared accounting for pending request IDs,
`pendingWithdrawAmount`, `pendingWithdrawalValuationBps`, and claimed self-owned idle WETH lives in
`AsyncRequestStrategy`. They do not synchronously unwind weETH.

## 2. Deployment Configuration

| Item | Env key |
| --- | --- |
| Strategy kind | `DF_STRATEGY_KIND_i=etherfi-weeth` |
| Ether.fi LiquidityPool | `DF_STRATEGY_ETHERFI_LIQUIDITY_POOL_i` |
| eETH token | `DF_STRATEGY_ETHERFI_EETH_i` |
| weETH token | `DF_STRATEGY_ETHERFI_WEETH_i` |
| DeltaForesight WeETHWithdrawAdapter | `DF_STRATEGY_ETHERFI_WITHDRAW_ADAPTER_i` |
| WithdrawRequestNFT | `DF_STRATEGY_ETHERFI_WITHDRAW_REQUEST_NFT_i` |
| referral | `DF_STRATEGY_ETHERFI_REFERRAL_i` (optional) |

The Vault supports multiple registered Strategies per branch. A WETH underlying branch can
therefore use Aave 50% / Etherfi 50% via `weightBps = 5000 / 5000`.
`DeployLiquity2` supports this at initial deployment through the
`DF_STRATEGY_COUNT_i` array form. Example for a hypothetical branch `i`
(this Strategy is archived and is not wired to any Day-1 branch): set
`DF_STRATEGY_COUNT_i=2`, `DF_STRATEGY_KIND_i_0=aave`,
`DF_STRATEGY_WEIGHT_BPS_i_0=5000`, `DF_STRATEGY_KIND_i_1=etherfi-weeth`,
and `DF_STRATEGY_WEIGHT_BPS_i_1=5000`; Etherfi-specific env keys use the
`DF_STRATEGY_ETHERFI_*_0_1` suffix. Governance handover helpers iterate the
live Vault registered Strategy list, so secondary Strategies receive the same
owner / upgrader handover as the primary Strategy.

Venue addresses are fixed at `initialize`. Do not add setters for LiquidityPool,
eETH, weETH, WithdrawAdapter, or WithdrawRequestNFT in normal operation. Venue
changes use Strategy replacement and Vault registration updates, as specified in
[Strategy](../protocol/product/spec/strategies/Strategy.md#22-external-venue-address-update-policy).

Initialization also validates the venue graph exposed by Ether.fi contracts:

- `weETH.eETH() == eETH`
- `weETH.liquidityPool() == liquidityPool`
- `withdrawRequestNFT.eETH() == eETH`
- `withdrawRequestNFT.liquidityPool() == liquidityPool`
- `liquidityPool.withdrawRequestNFT() == withdrawRequestNFT`
- `withdrawAdapter.dfWeETHWithdrawAdapterId() == DF_WEETH_WITHDRAW_ADAPTER_ID`
- `withdrawAdapter.liquidityPool() == liquidityPool`
- `withdrawAdapter.eETH() == eETH`
- `withdrawAdapter.weETH() == weETH`
- `withdrawAdapter.withdrawRequestNFT() == withdrawRequestNFT`

`WeETHWithdrawAdapter` is not an Ether.fi first-party contract. It is a
DeltaForesight first-party adapter fixed by env freeze and deployment review.
Because Ether.fi may expose a same-named helper, the Strategy does not accept a
merely ABI-compatible adapter. Before approval, it requires the DF-specific
`dfWeETHWithdrawAdapterId()` marker to return `DF_WEETH_WITHDRAW_ADAPTER_ID`.
The Strategy request and claim flows validate the actual weETH spent, NFT request
data, and ETH received. The adapter constructor also validates that `weETH`,
`WithdrawRequestNFT`, and `liquidityPool.withdrawRequestNFT()` point to the same
configured `eETH` / `liquidityPool` / `withdrawRequestNFT` graph.

## 3. Behavior

`_doDeposit(amount)` unwraps WETH to ETH, deposits into Ether.fi LiquidityPool,
wraps received eETH into weETH, and tracks only the weETH minted by this
Strategy in `_ownWeETH`.

`requestEtherfiWithdrawal(eETHAmount)` is restricted to the Vault
`ALLOCATOR_ROLE`. It converts the requested eETH amount to weETH, calls the
withdraw adapter, receives a `WithdrawRequestNFT`, stores the request ID, and
tracks the net pending amount from Ether.fi request data.
If a nonzero eETH request floors to 0 weETH, the Strategy rounds up to 1 wei
weETH so that weETH dust is not left permanently stranded. The pending value is
still taken from the NFT request data's net eETH amount.

`WeETHWithdrawAdapter.requestWithdraw(weETHAmount, recipient)` transfers exactly
`weETHAmount` from the caller, unwraps that transfer into eETH, requests native
Ether.fi withdrawal through `LiquidityPool.requestWithdraw(recipient, eETHAmount)`,
verifies that its weETH and eETH balances return to their pre-request baselines,
and verifies that `WithdrawRequestNFT.ownerOf(requestId) == recipient`. The
adapter is immutable, non-upgradeable, and has no owner / rescue / sweep surface.
Directly sent weETH, eETH, or ETH is not part of Strategy valuation and is not
mixed into normal request input. The adapter exposes the read-only
`dfWeETHWithdrawAdapterId()` identity marker, and the Strategy rejects
ABI-compatible adapters that do not expose that marker.

`claimEtherfiWithdrawals(requestIds)` is permissionless. It accepts only pending
request IDs tracked through `AsyncRequestStrategy`, claims ETH from Ether.fi,
wraps received ETH to WETH, and marks it as tracked idle WETH. Each claim batch
is capped at `MAX_ASYNC_REQUESTS_PER_CLAIM` (32) requests per transaction, and
the total unclaimed request count is capped at `MAX_ASYNC_PENDING_REQUESTS`
(128) to prevent storage bloat / UI retrieval failure from ALLOCATOR
misoperation or key compromise. When more than 32 requests are pending, keepers
/ UI must split them across transactions.
If the ETH actually received is below the pending value recorded at request time,
only the actual received amount becomes idle WETH and the shortfall drops out of
valuation. If the actual received ETH is above the pending value, the surplus
appears as `realizedYield()` and can be recovered to the Vault buffer through
`sendProfitToVault()` without reducing principal.

`_doWithdraw(amount)` returns only `min(amount, ownIdleUnderlying, WETH balance)`.
Pending requests and live weETH positions are not treated as synchronous
liquidity.

`estimatedTotalUnderlying()` is:

```text
weETH.getEETHByWeETH(min(_ownWeETH, weETH.balanceOf(this)))
+ pendingWithdrawAmount * pendingWithdrawalValuationBps / 10000
+ min(_ownIdleUnderlying, WETH.balanceOf(this))
```

The pending bps default is 10000. The Vault `WRITEOFF_ROLE` can lower it only after
`pausedAllocation == true`; restoration / upward changes do not require pause.
The bps calculation rounds down, keeping sub-wei dust on the conservative side.

## 4. Security Requirements

| ID | Requirement |
| --- | --- |
| EFWEETH-SEC-001 | Register only on a WETH branch; deploy selector requires WETH underlying |
| EFWEETH-SEC-002 | weETH donations must not inflate valuation or realized yield |
| EFWEETH-SEC-003 | eETH, weETH, and WithdrawRequestNFT are protected assets and cannot be swept |
| EFWEETH-SEC-004 | `onERC721Received` accepts only the configured WithdrawRequestNFT |
| EFWEETH-SEC-005 | Pending requests are tracked by request ID and unknown claims are rejected |
| EFWEETH-SEC-006 | `_doWithdraw` returns only claimed idle WETH |
| EFWEETH-SEC-007 | Initialization validates that `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` point to the configured `eETH` / `liquidityPool` / `weETH` / `withdrawRequestNFT` graph and that `withdrawAdapter` returns the DF-specific identity marker |
| EFWEETH-SEC-008 | The requestId returned by `withdrawAdapter.requestWithdraw` must be owned by the Strategy before it enters pending accounting |
| EFWEETH-SEC-009 | Permissionless claim batches are capped at 32 requestIds per transaction to avoid oversized gas paths / UI mistakes |
| EFWEETH-SEC-010 | Pending request valuation can be conservatively adjusted through Vault `WRITEOFF_ROLE` gated `pendingWithdrawalValuationBps` (0..10000); downward changes require `pausedAllocation == true`, and sub-wei dust rounds down |
| EFWEETH-SEC-011 | Unclaimed async requests are capped at 128 total to bound storage growth and pending-request retrieval |
| EFWEETH-SEC-012 | Raw ETH already present before claim must not enter claim delta / idle WETH / yield / valuation |
| EFWEETH-SEC-013 | Nonzero eETH requests that floor to 0 weETH round up to 1 wei weETH, while pending accounting records the NFT request data's net eETH amount |
| EFWEETH-SEC-014 | `WeETHWithdrawAdapter` is included in audit scope as a DeltaForesight first-party adapter; it exposes a DF-specific identity marker, validates immutable venue graph, LiquidityPool reverse binding, weETH / eETH balance deltas and residual balances, and NFT owner, and has no admin / upgrade / rescue surface |

## 5. Verification

`contracts/test/archive/EtherfiWeETHStrategy.t.sol` covers:

- WETH allocation into eETH / weETH and WETH-denominated valuation
- request, pending tracking, finalized claim, WETH wrap, and `sendToVault`
- tiny eETH requests that would floor to 0 weETH round up to 1 wei weETH while preserving staked + pending valuation consistency
- `WeETHWithdrawAdapter` unwraps weETH to eETH, creates an Ether.fi native withdrawal request, and keeps no weETH / eETH balance
- `WeETHWithdrawAdapter` rejects venue graph / LiquidityPool reverse-binding mismatch, zero requests, and residual weETH / eETH
- zero synchronous withdrawal before claim
- actual received ETH below pending value is reflected as a valuation shortfall
- actual received ETH above pending value can be recovered as yield through `sendProfitToVault`
- pending valuation bps default, floor rounding, 0 bps, and actual-value replacement after claim
- initialization reverts on mismatched `weETH` / `WithdrawRequestNFT` / `liquidityPool.withdrawRequestNFT()` / `withdrawAdapter` venue graph links or an ABI-compatible adapter that does not expose the DF identity marker
- requestId owner mismatch does not create phantom pending accounting
- claim batch cap is enforced before pending accounting is touched
- pending request total cap is enforced before new async requests are issued
- donation-resistant valuation
- raw ETH donation does not inflate claim delta / idle WETH / yield / valuation
- position-token sweep protection
- Aave 50% / Etherfi 50% Vault allocation by strategy weights
