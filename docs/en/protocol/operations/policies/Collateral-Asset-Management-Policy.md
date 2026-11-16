# Collateral Asset Management Policy

## Positioning

This document classifies Day-1 collateral branches as active or inert and describes which external venues may receive each Underlying.

Canonical values for collateral, risk parameters, buffers, and withdrawal delays are in [Parameters](../../../Parameters.md). Shared Strategy requirements are in [Strategy](../../product/spec/strategies/Strategy.md), with adapter-specific requirements in its child documents. Venue risk, governance, monitoring, and adoption status are canonical in the [Strategy Selection Policy](Strategy-Selection-Policy.md); Morpho-specific gates are in the [Morpho Operation Policy](Morpho-Operation-Policy.md).

“Supported” means technically expressible through an existing adapter, not approved for mainnet allocation. Adoption, cap/weight increase, and public exposure still require the Strategy Selection gate and activation evidence.

## Day-1 implementation

Borrowable branches are Branch 0 dwstETH and Branch 1 dUSDC. Branches 2–7 are inert: no bound Underlying, cap 0, allocation 0, and no deployed or registered Strategy.

| Branch | Underlying | Day-1 baseline | Possible additions | Rationale |
| ---: | --- | --- | --- | --- |
| 0 dwstETH | wstETH | Aave V3 (aEthwstETH) | Day-2 decision; leveraged loop / Ride-on only after DD and additional audit | active prioritized ETH branch; native appreciation remains borrower collateral value |
| 1 dUSDC | USDC | Aave V3 + Morpho Vault V2 (`MorphoV2Strategy`) | additional ERC-4626 venues only after evidence | synchronous recovery baseline plus the audited V2 adapter |
| 2 dETH | TBD | none | decide at activation | conservative-LST-envelope ETH reserve slot |
| 3 dUSD-A | TBD | none | decide at activation | generic USD reserve slot A |
| 4 dBTC | TBD | none | decide at activation | BTC reserve slot |
| 5 dUSD-B | TBD | none | decide at activation | generic USD reserve slot B |
| 6 dJPY | TBD | none | decide at activation | JPY reserve slot |
| 7 dJGB | TBD | none | decide at activation | JGB reserve slot |

Native-ETH entry into Branch 0 is provided by the `CollateralYieldZapper` staking route (ETH → Lido stETH → wstETH, gated by the frozen expected-stETH address); protocol-level WETH remains gas compensation only.

An inert-branch activation first verifies exact Underlying compatibility with immutable parameters, then approves one package covering the [Deploy Env Freeze Runbook](../../launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md), `mainnet-preflight.ts`, frontend branch gates, and Strategy-specific specifications/tests.

## Adapter sufficiency

Only the adapter required by asset flow and recovery behavior should be used. Day-1 live allocation is Branch 0 dwstETH's Aave V3 slot and Branch 1 dUSDC's Aave V3 + Morpho Vault V2 set.

| Decision | Policy |
| --- | --- |
| ERC-4626 vault with `asset() == underlying` | existing `ERC4626Strategy` can suffice; still require venue and recovery evidence |
| operate WETH as Lido wstETH | **retired**; `LidoStrategy` is archived under `contracts/src/Strategies/archive/` and has no deploy path. Any future stETH venue is a new proposal |
| operate wstETH externally | Day-1 baseline is `AaveV3Strategy` (aEthwstETH); native canonical-rate appreciation stays borrower collateral value, and only Underlying quantity growth is Strategy yield |
| operate WETH as Etherfi weETH | **retired**; `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` are archived under `contracts/src/Strategies/archive/` and have no deploy path. Any future LRT venue is a new proposal |
| operate USDC through Sky sUSDS | `SkyUsdcSUsdsStrategy`; requires converter, min-out, and idle-USDS monitoring |
| convert another Underlying into a different asset | requires an asset-transforming Strategy if none exists; configuration alone is insufficient |
| no external venue | use `strategyKind=none`; never deploy a dummy Strategy |
| venue differs only by name | do not create a dedicated Strategy if an existing adapter's conditions are met |

## Venue policy

| Venue / asset | Current support | Adoption condition |
| --- | --- | --- |
| Aave V3 | `AaveV3Strategy` | freeze reserve/aToken from a primary source and verify active, unpaused, unfrozen state at the fork block |
| Morpho ERC-4626 | conditional candidate through `ERC4626Strategy` | target `asset()` exactly equals branch Underlying and both Strategy Selection and Morpho Operation gates pass |
| EulerEarn / other ERC-4626 | conditionally supported | `asset()==underlying`; outside expected Day-1 scope, so adoption updates runbook, audit scope, and preflight |
| USDC → USDS → sUSDS | implemented candidate through `SkyUsdcSUsdsStrategy` | dUSDC only; freeze token/converter/max-loss values, fork dry-run and route-halt monitoring before promotion |
| Etherfi / weETH | **retired, source archived** | `EtherfiWeETHStrategy` / `WeETHWithdrawAdapter` moved to `contracts/src/Strategies/archive/` on 2026-08-06; a WETH underlying is no longer reachable and the deploy surface was removed in PR #1424. Retained because they were covered by the `0c7766e0` audit. A future LRT venue is a new proposal |

## Morpho

A Morpho vault needs no dedicated adapter merely because it is Morpho. If it behaves as standard ERC-4626 and `asset()` equals the branch Underlying, it can fit `ERC4626Strategy`. Adoption additionally:

- freezes `DF_STRATEGY_KIND_i=erc4626`, vault, weight, and cap;
- adds fork observations for code, `asset()`, `convertToAssets`, `maxWithdraw`, and `maxRedeem`;
- manages curator, market selection, oracle, bad debt, and queue behavior in the Morpho Operation Policy;
- separates temporary liquidity limitation from confirmed loss; and
- rejects, through `ERC4626Strategy`, vaults such as Morpho Vault V2 whose `maxWithdraw`/`maxRedeem` are always zero. Morpho Vault V2 is instead covered by the dedicated, audited `MorphoV2Strategy` (kind `morpho-v2`; Day-1 Branch 1 dUSDC) under the gates in the [Morpho Operation Policy](Morpho-Operation-Policy.md).

## Etherfi / LRT (retired, source archived)

> `EtherfiWeETHStrategy` and `WeETHWithdrawAdapter` are **archived** under
> `contracts/src/Strategies/archive/` (2026-08-06). They have no deploy path and are
> not adoption candidates. The requirements below are retained as the design record a
> future LRT proposal would have to re-derive and re-audit.

Etherfi/weETH used `EtherfiWeETHStrategy`, not generic `ERC4626Strategy`, because dETH's Underlying is WETH while eETH/weETH is another asset; deposit and recovery traverse unwrap, LRT mint, request, claim, and wrap states; valuation must separate WETH quote, exchange rate, depeg/slashing, and queue risk; and donation resistance requires tracking self-originated shares, requests, and idle WETH.

Any adoption keeps `underlying() == WETH`, values only self-originated positions conservatively in WETH, returns only claimed idle WETH from `sendToVault`, treats unfinalized amounts as pending rather than loss, and includes request/claim/emergency functions plus donation/residue/share/NFT behavior in audit scope.

## Self-appreciating Underlying boundary

For dwstETH and any future yield-bearing USD Underlying, canonical-rate appreciation remains borrower collateral value. Only growth in the quantity of Underlying produced by an external Strategy is Strategy yield. Venue, accounting, recovery, and monitoring require their own activation package.
