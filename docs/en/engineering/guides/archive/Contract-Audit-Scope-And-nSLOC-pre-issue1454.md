# Contract Audit Scope and nSLOC

## 0. Auditor Quick Read

This document is the auditor-facing scope and nSLOC handoff for the current
mainnet contract review. It explains what should be reviewed as new or modified
Solidity logic, what should be treated as fork-parity review, and what should
stay outside Solidity nSLOC pricing.

Normative product and architecture policy lives in
[Product-Overview](../../../protocol/product/Product-Overview.md) section 12.1. The canonical
Liquity v2 fork-diff ledger lives in
[Liquity-v2-Core-Spec](../../../protocol/product/spec/Liquity-v2-Core-Spec.md) section 2.2
(`CORE-MOD-*`).

### 0.1 Recommended Scope Decision

| Scope item | Recommended treatment | nSLOC |
| --- | --- | ---: |
| A. Economic/security full-review body | Main SOW number. Covers DF-modified economic/security surfaces and JPY DeFi-specific implementation code. | 5,472 |
| TroveNFT / NFT metadata | Light diff/rendering review. Deployed public surface, but no fund movement, debt accounting, liquidation, redemption, or authorization change. | +330 |
| Interfaces / external ABI shims | ABI/interface consistency review only. Exclude from the main nSLOC because they contain no implementation logic. | +1,253 if priced |
| Large base-derived core files | Diff-boundary / fork-parity review. Count whole files only if the auditor requires whole-file pricing for any changed base-derived file. | +2,890 |
| Archived, previously audited Strategy sources | **Out of the active review body from this commit.** Preserved unmodified under `contracts/src/Strategies/archive/` because they were in scope for, and covered by, the external audit completed 2026-08-05 (audited identity `0c7766e0`). Re-price only on re-activation. See section 3.5. | 810 excluded |
| Deploy / handover / runbooks / ops console | Reference material for launch-final evidence. Not Solidity audit scope and not Solidity nSLOC; review only if deployment ceremony / launch execution is separately scoped. | 0 Solidity nSLOC |

Use **5,472 nSLOC** as the primary full-review estimate. If the deployed
TroveNFT / metadata surface is included as a light review package, use
**5,802 nSLOC** as the practical total. If an auditor also prices interfaces,
the corresponding numbers are **6,725 nSLOC** without NFT metadata and
**7,055 nSLOC** with NFT metadata.
The full `contracts/src` Solidity population is **13,106 nSLOC**; that total is a
reconciliation number, not the recommended economic full-review price, because it
includes interface-only files, rendering utilities, base-derived support/reference
files, and the **810 nSLOC archived, previously audited Strategy sources** under
`contracts/src/Strategies/archive/` (section 3.5).

**Scope delta vs the previously audited identity `0c7766e0`.** The A body moved
from 5,836 to 5,472 nSLOC. That is not a single subtraction; it is three effects:

Reproduce it by running the section 1 command against `git archive 0c7766e0`
and against this commit; every step below is a cloc result, not an estimate.

| Step | nSLOC | Running |
| --- | ---: | ---: |
| Previous edition's stated A body | | 5,836 |
| Correction: rows already stale at `0c7766e0`, inside the old A set | +5 | 5,841 |
| Correction: `JpyUsdRateProvider` existed at `0c7766e0` but was never listed; now in section 3.3 | +93 | 5,934 |
| **Archived out of the A body (this PR)** | **-810** | **5,124** |
| `DFWETHPriceFeed` deleted (branch 0 moved WETH -> wstETH) | -19 | 5,105 |
| New files since `0c7766e0`: `MorphoV2Strategy` 149, `DFWstETHPriceFeed` 88, `JpyFreezeLib` 50 | +287 | 5,392 |
| Edits to existing A files since `0c7766e0`: `CollateralYieldZapper` +107, `DFPriceFeedBase` -14, `sUSDSPriceFeed` -13 | +80 | **5,472** |

Grouped: **-810 archival**, **+348 genuine post-audit source change**
(-19 + 287 + 80), **+98 correction of rows that were already stale at `0c7766e0`**
(+5 + 93). Net -364.

The +5 correction row is a *net* of offsetting errors, most of them negative, so
do not read it as "the old numbers were low": `BaseStrategy` +40,
`MainnetPriceFeedBase` +7, `InterestRouterForwarder` +3, `PriceFeedProxy` +2,
against `sUSDSPriceFeed` -16, `DFPriceFeedBase` -14, `CollateralVault` -7, and
five concrete price feeds at -2 each.

`IJpyUsdRateProvider` (+4) is deliberately absent from this table: it lands in
the interfaces bucket (section 4, 1,249 -> 1,253), not the A body.

An auditor comparing only the headline numbers should read this table before
concluding that 364 nSLOC of review disappeared.

### 0.2 Solidity Review Objectives

The review should produce yes/no answers for these concrete objectives:

- **Core fork boundary**: every behavior change in the Liquity v2-derived core
  is either listed in `CORE-MOD-*` or is rename / wiring parity. Unlisted core
  accounting, liquidation, redemption, and SP behavior should remain
  fork-parity.
- **JPYdf implementation layer**: `DToken`, `CollateralVault`, Strategies,
  PriceFeeds, Zappers, `InterestRouterForwarder`, `PILAllocator`, and
  `UniV4MerklInitiative` preserve their intended accounting, access control,
  external-call, oracle, and upgrade boundaries.
- **Callable surface**: each external/public function has the expected actor and
  production path described in
  [`Contract-Audit-Usage-Map.md`](../Contract-Audit-Usage-Map.md). Protocol-only
  handlers should not be callable as arbitrary user routes.
- **Gated or dormant surface**: bridge minters, optional Strategies, inert
  branches, PIL / UniV4 incentives, and route adapters cannot move funds, mint
  supply, receive production routing, or become frontend-facing without their
  documented configuration / activation gates.
- **Absent routes**: Curve, Balancer, Uniswap v3 route adapters, flash-close,
  collateral-funded repay, Multiply, active bridge adapters, and future
  `Treasury.sol` / reward distributors are absent from production `contracts/src`
  and ABI.
- **Reference artifacts**: deploy scripts, manifests, runbooks, and ops-console
  boundaries are useful for launch-evidence sanity, but they are not Solidity
  review scope unless a separate launch-execution review is explicitly scoped.

### 0.3 Suggested SOW Text

> Full Solidity review scope: approximately 5.5k nSLOC, covering DF-modified
> economic/security surfaces and JPY DeFi-specific contracts. Interfaces are listed
> for ABI/interface consistency review but are not counted in the main nSLOC.
> TroveNFT / NFT metadata changes are included as light diff/rendering review,
> not as economic full-review scope; including them gives a practical total of
> approximately 5.8k nSLOC. Archived, previously audited Strategy sources under
> `contracts/src/Strategies/archive/` (810 nSLOC) are excluded from this figure;
> they were covered by the external audit completed 2026-08-05 (`0c7766e0`) and are
> retained as historical artifacts, not as current review scope. Liquity v2 base core is treated as upstream audited
> and reviewed for fork parity, integration assumptions, and DF diff boundaries.
> Deploy and handover scripts are supplied as reference material for
> launch-final evidence, not as Solidity audit scope or Solidity review nSLOC.
> If the auditor prices all changed base-derived files as
> whole-file full review, the conservative upper bound is approximately 8.4k
> nSLOC without interfaces, or 9.6k nSLOC with interfaces.

### 0.4 How to Read This Document

| Need | Read |
| --- | --- |
| Confirm counting method | Section 1 |
| Estimate SOW size | Section 2 |
| Review main economic/security implementation files | Section 3 |
| Map expected callers and production entrypoints | [`Contract-Audit-Usage-Map.md`](../Contract-Audit-Usage-Map.md) |
| Review archived, previously audited sources | Section 3.5 |
| Check interfaces separately | Section 4 |
| Review deployed NFT metadata surface | Section 5 |
| Understand optional NFT utility expansion | Section 6 |
| Discuss conservative whole-file core counting | Section 7 |
| Confirm explicit out-of-scope items | Section 8 |
| Separate audit scope from launch activation | Section 0.6 |

### 0.5 Launch-Active Strategy Manifest Policy

The launch-active manifest is intentionally narrower than the full set of
implemented Strategy contracts listed in Section 3.2. For launch readiness and
audit handoff, treat the production Strategy set as follows:

| Branch | Required baseline | Launch-active additions | Outside current launch-active scope |
| ---: | --- | --- | --- |
| 0 `dwstETH` | Aave V3 (`aave`) — exactly this set | none on Day 1 | Any non-`aave` kind. `DeployLiquity2._requireMainnetDay1StrategyPolicy` rejects everything else; the archived Lido / Etherfi surfaces have no strategy kind at all |
| 1 `dUSDC` | Aave V3 (`aave`) + Morpho Vault V2 (`morpho-v2`) | Morpho via ERC-4626 (`erc4626`) additionally permitted | Sky USDC -> USDS -> sUSDS unless separately scoped |
| 2 `dUSDT`, 3 `dUSDS`, 4 `dXAUT` | none — actively wired (Underlying, feed, zapper bound) but Strategy registration is disabled and cap freezes at 0 | none | Any Strategy registration (`DF: Day-1 branch strategies disabled`) |
| 5-7 (`dBTC` / `dUSD` / `dJPY`) | none — inert, no Underlying bound | none | Any Strategy registration |

`contracts/utils/mainnet-preflight.ts`,
`contracts/utils/deployment-manifest-to-app-env.ts`, and
`frontend/df-shared/generate.ts` enforce this policy fail-closed. The generic
`ERC4626Strategy.sol` review should therefore focus on the adapter's rounding,
share/asset, loss, and recovery properties, while the Morpho-specific curator,
market, oracle, bad-debt, and withdrawal-liquidity decisions remain required
venue evidence before production allocation. The implemented optional Strategy
contract `SkyUsdcSUsdsStrategy.sol` remains visible in the codebase and may be
reviewed for future readiness, but it is not a valid launch-active manifest entry
without a separate audit-scope change. `LidoStrategy.sol`,
`EtherfiWeETHStrategy.sol`, `WeETHWithdrawAdapter.sol`, and
`AsyncRequestStrategy.sol` are **archived** under
`contracts/src/Strategies/archive/`: they are neither launch-active nor active
review scope, and they have no reachable deploy path (section 3.5).

### 0.6 Scope vs Activation Matrix

Do not infer launch activation from "included in the audit SOW", and do
not infer "out of audit" from "not launch-active". Use this matrix when
deciding whether a surface should be added to or removed from the auditor
package.

| Category | Solidity audit treatment | Activation treatment | Examples |
| --- | --- | --- | --- |
| Launch-active / planned active | Included in the A full-review body when the contract is JPY DeFi-specific or DF-modified. | May be configured after the corresponding freeze / evidence / Safe approval gate. | Core DF diffs, `JpydfToken`, `DToken`, `CollateralVault`, `PriceFeedProxy`, active price feeds, `CollateralYieldZapper`, `InterestRouterForwarder`, Aave, Morpho via `ERC4626Strategy`. |
| Archived, previously audited source | **Out of the active A body and out of the current nSLOC** from this commit. Retained under `contracts/src/Strategies/archive/` so the completed external audit result (`0c7766e0`, 2026-08-05) is not discarded. Listed in section 3.5 with its audited nSLOC. | Must not be deployed, registered, funded, or routed. Re-activation requires re-entry into the `DeployLiquity2` strategy selector plus a fresh activation and audit-scope package. | `LidoStrategy`, `EtherfiWeETHStrategy`, `WeETHWithdrawAdapter`, `AsyncRequestStrategy`. |
| Audited but gated production code | Included in the A full-review body because it is production source that can affect funds, routing, incentives, or authorization once configured. | Not user-facing, not funded, or not routed until route / PIL / branch / manifest gates are approved. | `UniV4Exchange`, `PILAllocator`, `UniV4MerklInitiative`, dormant bridge-ready `JpydfToken` minter surface, cap-0 branch dTokens / feeds / zappers where applicable. |
| Implemented optional Strategy code outside the expected launch manifest | Included in the A full-review body while it remains in production `contracts/src`, but it is not launch-approved by default. | Separate strategy activation package and audit-scope confirmation are required before registration, cap allocation, or frontend exposure. | `SkyUsdcSUsdsStrategy`, non-Morpho `ERC4626Strategy` venues, any Strategy registration for branch 2+. |
| Base-derived support files with no DF economic redesign | B parity / reference review. Do not add to the A nSLOC unless the auditor prices the whole production source population. | Deployed or linked as core support, but the review question is fork parity and integration, not new protocol design. | `AddressesRegistry`, `CollateralRegistry`, `StabilityPool`, `SortedTroves`, `CollSurplusPool`, `DebtInFrontHelper`, `HintHelpers`, `MultiTroveGetter`, `AddRemoveManagers`, `BatchId`, `LatestBatchData`, `LatestTroveData`, `TroveChange`, `LiquityMath`, `LiquityBase`, `Ownable`. |
| Future draft specs without current implementation | Outside current Solidity nSLOC. | New PR, tests, deploy plan, and audit package before production use. | `Treasury.sol`, `SPAdditionalRewardDistributor.sol`, `BorrowReferralRewardDistributor.sol`, `SPDepositReferralRewardDistributor.sol`. |
| Removed / absent route code | Outside current scope because the code and ABI are not present in production `src`. | Reintroduce only as a new audited entrypoint; do not keep compatibility shims for fresh deploy. | Curve, Balancer, Uniswap v3 route adapters, flash-close, collateral-funded repay, Multiply, fail-fast exchange placeholder, direct non-USDC JPYdf pools, active bridge adapter. |
| Operational artifacts | Reference material, 0 Solidity nSLOC. | Required for launch evidence and handover correctness, but not Solidity audit scope. | Deploy scripts, manifests, preflight checks, freeze packages, runbooks, ops-console write boundaries. |

## 1. Counting Method

| Item | Value |
| --- | --- |
| Tool | [AlDanial/cloc](https://github.com/AlDanial/cloc) |
| Local version used for this draft | `cloc --version` = `2.06` |
| Command | `cloc --by-file --csv --quiet --include-lang=Solidity contracts/src` |
| Counted source | `contracts/src/**/*.sol` |
| Archive carve-out | `contracts/src/Strategies/archive/**` is inside the counted population but excluded from the A full-review body. To reproduce the active-source population directly, use `cloc --by-file --csv --quiet --include-lang=Solidity --not-match-d='(^\|/)archive$' contracts/src`. |
| Excluded source | `contracts/test/**`, deploy / handover scripts, `contracts/lib/**`, generated artifacts, Markdown |

Every nSLOC figure in this edition was regenerated with the command above at the
head of this PR; the previous edition's figures had drifted from the source tree
(see the scope-delta table in section 0.1).

`cloc`'s `code` column is treated as nSLOC. Blank lines and comment lines are
not included. The first CSV header row includes `cloc` runtime metadata, so do
not use that header row for deterministic evidence hashing. At audit freeze,
rerun the command above, record the freeze commit SHA and `cloc --version`, and
hash the normalized CSV body (`tail -n +2` output) in the audit handoff package.

Counting rules:

- Count implementation files that can affect funds, accounting, authorization,
  oracle values, or swap routing in the A full-review body.
- Exclude interface-only files from the main nSLOC. List them for ABI/interface
  consistency review instead.
- Treat TroveNFT / NFT metadata as light diff/rendering review unless the
  auditor explicitly wants all deployed view/rendering code in full-review
  pricing.
- Treat large Liquity v2-derived core files as diff-boundary / parity review,
  not fresh protocol design review, unless the auditor requires whole-file
  counting for every changed file.

## 2. SOW Summary

| Counting policy | nSLOC | Intended use |
| --- | ---: | --- |
| A economic full-review body, excluding interfaces and NFT rendering | 5,472 | Recommended main full-review estimate |
| A + TroveNFT / metadata light diff review | 5,802 | Practical total when deployed NFT surface is included as light review |
| A + listed interfaces / ABI files | 6,725 | Use only if the auditor prices interfaces as nSLOC |
| A + interfaces + TroveNFT / metadata light diff review | 7,055 | Use only if both interfaces and deployed NFT surface are priced |
| A + interfaces + TroveNFT / metadata + full NFT support utilities | 7,712 | Use only if the auditor prices deployed metadata and support utilities as full-review scope |
| A + large base-derived core files counted as whole-file full review | 8,362 without interfaces / 9,615 with interfaces | Conservative upper bound if changed base-derived files are priced whole-file |
| Base-derived support / reference files not otherwise priced | +1,694 | Reconciliation bucket only; use for whole-`contracts/src` pricing, not recommended economic full-review pricing |
| Archived, previously audited Strategy sources (section 3.5) | +810 | **Not priced.** Covered by the completed `0c7766e0` audit; retained as historical artifacts, excluded from the active body |
| `contracts/src` Solidity total | 13,106 | Whole Solidity source population including the archive, not the recommended full-review scope |

### 2.1 Recommended SOW Scope = 5,472 nSLOC

The recommended main SOW number is **5,472 nSLOC**.

| Bucket | nSLOC | Included | Excluded |
| --- | ---: | --- | --- |
| Section 3.1 DF-modified economic/security core surfaces | 849 | `ActivePool` event / approval hardening, `DFStabilityPool` same-block guard, `JpydfToken` bridge-ready dormant extension and recipient helper, `Constants` value changes | TroveNFT / NFT metadata rendering, whole-file counting of large base-derived files |
| Section 3.2 JPY DeFi-specific implementation layer | 2,724 | `DToken`, `CollateralVault`, `InterestRouterForwarder`, `PILAllocator`, `UniV4MerklInitiative`, `LiquidationCandidateGetter`, active strategy implementations | Deploy scripts, tests, archived Strategy sources (section 3.5) |
| Section 3.3 Oracle / PriceFeed surface | 848 | DF price feeds, `PriceFeedProxy`, JPY freeze / rate-provider helpers used by active branches | Off-chain oracle monitoring scripts |
| Section 3.4 Zapper / Route implementation surface | 1,051 | `CollateralYieldZapper` including the native-ETH -> stETH -> wstETH route, Sky ingress zapper, Uniswap v4 adapter / codec | Route interfaces, removed Curve / Balancer / Uniswap v3 routes, flash-close, Multiply |
| **Recommended SOW total** | **5,472** | Full economic/security review baseline | Interfaces are separate ABI review; NFT rendering is separate light review; archived sources are section 3.5 |

Formula: `849 + 2,724 + 848 + 1,051 = 5,472`.

### 2.2 Why Interfaces Are Separate

Interfaces have no implementation logic, no storage, no external calls, and no
accounting behavior. They should be checked for ABI compatibility and semantic
alignment with the implementation, but they should not inflate the main
economic/security nSLOC. If the auditor prices them anyway, add `+1,253 nSLOC`.

### 2.3 Why NFT Metadata Is Light Review

TroveNFT / NFT metadata files are deployed or directly used by deployed NFT
metadata, so they should not disappear from the audit package. However, the
review objective is display correctness and fork-diff sanity. These files do
not move protocol funds, update debt accounting, perform liquidations, perform
redemptions, or alter the Trove ownership authorization model beyond the
base/OZ ERC-721 surface. Adding the light review package gives
`5,472 + 330 = 5,802`.

## 3. A Economic Full-Review Body

This is the recommended full economic/security review package.

### 3.1 DF-Modified Economic/Security Core Surfaces

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/ActivePool.sol` | 245 | Pool that holds active collateral and aggregate debt / interest accounting for each branch. DF adds aggregate accounting events and hardens collateral approvals with `forceApprove`. | Events emit correct post-update values; observability changes do not change accounting, authorization, or external-call ordering; approval hardening has no integration side effects. |
| `contracts/src/DFStabilityPool.sol` | 306 | Deployed Stability Pool variant. Adds a same-block withdrawal guard to the base `StabilityPool` behavior. | Same-block `provideToSP` -> `withdrawFromSP` is blocked; next-block withdrawals remain valid; non-guard SP accounting remains base-parity. |
| `contracts/src/JpydfToken.sol` | 224 | Protocol debt token. Equivalent to base `BoldToken` with JPYdf naming, bridge-ready dormant extension, core address registration hardening, and recipient validation helpers. | Core mint/burn authority remains separate from `bridgeMint`/`bridgeBurn`; bridge minter count is zero for the current launch-active package; owner renounce and registry binding are irreversible as intended; transfer recipient restrictions and helper parity are correct; permit / EIP-712 domain is correct. |
| `contracts/src/Dependencies/Constants.sol` | 74 | Liquity core constants. DF defines `MIN_DEBT`, `COLL_GAS_COMPENSATION_CAP`, and branch constants. Production-unreferenced fixture constants are removed from `src`. | Values match `Parameters.md`; liquidation compensation cap and minimum debt boundaries are correct; inert branch constants cannot activate unintended risk; old WETH/SETH fixture constants do not remain in production source. |

Subtotal: 849 nSLOC.

### 3.2 JPY DeFi-Specific Implementation Layer

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/DToken.sol` | 153 | Wraps underlying assets into 18-decimal core collateral tokens. Only the bound Vault can mint/burn. | Mint/burn authority, cap enforcement, token info / allowed underlying, permit behavior, one-time Vault binding. |
| `contracts/src/CollateralVault.sol` | 818 | Core custody and accounting contract for underlying deposits, dToken mint/redeem, liquid buffer, delayed withdrawals, strategy allocation, and backstop. | 1:1 claim accounting, buffer and delayed claim behavior, strategy loss / writeoff / backstop flows, pause / role / UUPS upgrade boundaries, reentrancy. |
| `contracts/src/InterestRouterForwarder.sol` | 60 | Receives the core interest-router share and forwards it to the launch recipient. | Recipient change authority, route transfer behavior, 2-step ownership / Timelock handover, stuck-funds risk. |
| `contracts/src/PILAllocator.sol` | 235 | Admin-weighted Phase-A allocator for PIL JPYdf liquidity incentives. | Initiative registration and JPYdf recipient validation, bounded initiative count / distribution loop, weight sum and carry-over accounting, hook isolation + hook status observability, pause / guardian / 2-step ownership, permissionless distribution behavior. |
| `contracts/src/Initiatives/UniV4MerklInitiative.sol` | 174 | Keeper-prioritized Merkl campaign creator with public fallback for JPYdf/USDC Uniswap v4 liquidity incentives. | Merkl trust boundary, campaign threshold and epoch alignment, campaign creation window, allowance hygiene, poolId / weight immutability, no-op hook reuse across Phase-A / Phase-B. |
| `contracts/src/LiquidationCandidateGetter.sol` | 99 | Read-only helper for liquidator bot and frontend liquidation candidate pagination. | Bounded scan behavior, zombie / inactive Trove exclusion, read-only non-interference with core state. |
| `contracts/src/Strategies/BaseStrategy.sol` | 348 | Shared strategy base with Vault binding, principal accounting, reward settlement, and UUPS upgrade plumbing. | `onlyVault` / manager boundaries, principal tracking, emergency flows, storage layout and upgrade safety. |
| `contracts/src/Strategies/AaveV3Strategy.sol` | 151 | Strategy implementation that supplies underlying assets to Aave V3. | aToken accounting, withdraw / send-to-vault behavior, external protocol failure handling, reward / donation handling. |
| `contracts/src/Strategies/ERC4626Strategy.sol` | 91 | Generic ERC-4626 vault adapter strategy. | Share/asset conversion, rounding, deposit/withdraw failure handling, vault compatibility assumptions. |
| `contracts/src/Strategies/MorphoV2Strategy.sol` | 149 | Morpho Vaults V2 adapter strategy. Fully synchronous, so it derives from `BaseStrategy` directly rather than from an async request base. | Share/asset conversion and rounding, fail-soft venue isolation, forced-deallocation penalty bound (`maxPenaltyBps` <= 200), donation resistance, backing-ratio accounting. |
| `contracts/src/Strategies/SkyUsdcSUsdsStrategy.sol` | 290 | Asset-transforming dUSDC strategy for USDC -> USDS -> sUSDS and USDC-denominated recovery. | Converter identity, min-out / preview accounting, actual USDS spend / idle tracking, sUSDS donation resistance, emergency redeem / convert boundaries. |
| `contracts/src/Strategies/SkyUsdcSUsdsConverter.sol` | 156 | Immutable adapter for Sky LitePSMWrapper-USDS-USDC. | Wrapper/token identity, `tin/tout` halt and fee math, 6/18-decimal rounding, min-out, reverse-route refund, balance/allowance residue, reentrancy. |

Subtotal: 2,724 nSLOC.

`SkyUsdcSUsdsStrategy.sol` and `MorphoV2Strategy.sol` are counted here because
they are active production Strategy implementations under `contracts/src`. That
does **not** make them launch-active manifest entries; their activation status is
governed by Section 0.5 / 0.6 and by the strategy selection evidence package.

`LidoStrategy.sol`, `EtherfiWeETHStrategy.sol`, `WeETHWithdrawAdapter.sol`, and
`AsyncRequestStrategy.sol` are **no longer counted here**. They moved to
`contracts/src/Strategies/archive/` and are listed with their audited nSLOC in
Section 3.5. That move is the whole scope reduction in this edition: -810 nSLOC
from this subtotal.

### 3.3 Oracle / PriceFeed Surface

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/PriceFeeds/DFPriceFeedBase.sol` | 69 | Shared DF price feed base. Combines Chainlink collateral/USD and USD/JPY feeds into JPY-denominated prices. | Stale / invalid price handling, JPY freeze behavior, `lastGoodPrice`, shutdown signaling. |
| `contracts/src/PriceFeeds/DFUSDCPriceFeed.sol` | 19 | Concrete dUSDC branch price feed. | Feed address, decimals, stale threshold configuration. |
| `contracts/src/PriceFeeds/DFUSDTPriceFeed.sol` | 19 | Concrete dUSDT branch price feed. | Feed address, decimals, stale threshold configuration, USDT depeg assumptions. |
| `contracts/src/PriceFeeds/DFWstETHPriceFeed.sol` | 88 | Concrete branch-0 dwstETH price feed. Replaced `DFWETHPriceFeed.sol` when branch 0's underlying moved WETH -> wstETH. | wstETH canonical-rate composition with ETH/USD and USD/JPY, JPY freeze behavior, branch wiring. |
| `contracts/src/PriceFeeds/DFWBTCPriceFeed.sol` | 82 | WBTC branch price feed. | BTC/USD and JPY composition, token-specific fallback behavior. |
| `contracts/src/PriceFeeds/DFXAUTPriceFeed.sol` | 19 | dXAUT branch price feed. | XAU/XAUT peg assumptions, monitoring / mintCap gate assumptions. |
| `contracts/src/PriceFeeds/sUSDSPriceFeed.sol` | 94 | sUSDS / USDS route price feed. | Savings-rate / wrapper conversion, Sky dependency, JPY composition. |
| `contracts/src/PriceFeeds/PriceFeedProxy.sol` | 186 | Proxy address fixed by core; source can be changed by 24h timelock. | `proposeSource` / `confirmSource`, smoke test, ownership / no-renounce policy, source failure isolation. |
| `contracts/src/PriceFeeds/PriceFeedPlaceholder.sol` | 14 | Feed for inert / placeholder branches. | Cannot be wired to active branches accidentally; expected failure behavior. |
| `contracts/src/PriceFeeds/CompositePriceFeed.sol` | 27 | sUSDS-only composite base. Keeps primary -> `lastGoodPrice`; unused WSTETH/RETH LST secondary fallback is removed. | Canonical-rate composition, shutdown fallback, no reintroduction of unused secondary pricing modes. |
| `contracts/src/PriceFeeds/MainnetPriceFeedBase.sol` | 88 | Upstream-derived mainnet price feed base. | Base parity, failure path, Chainlink interface handling. |
| `contracts/src/PriceFeeds/JpyFreezeLib.sol` | 50 | Shared JPY soft-freeze library extracted from the DF feed base. | Freeze entry / exit conditions, maximum freeze duration, `lastGoodPrice` interaction, no divergence between feeds. |
| `contracts/src/PriceFeeds/JpyUsdRateProvider.sol` | 93 | JPY/USD rate provider consumed by the DF feed base. | Staleness threshold, decimals, invalid / zero answer handling, freeze signalling. |

Subtotal: 848 nSLOC.

Some concrete price feed implementations, including `DFWBTCPriceFeed.sol`, may
be compiled but not launch-wired. Treat them as audit-visible,
non-launch-active production source: they must not appear in the launch manifest
unless the corresponding branch activation package is approved.

### 3.4 Zapper / Route Implementation Surface

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/Zappers/CollateralYieldZapper.sol` | 575 | Stateless UX router that bundles underlying deposit -> Vault -> core open/add/withdraw/close-with-JPYdf flows into one transaction. Also carries the branch-gated native-ETH -> stETH -> wstETH zap route, which calls Lido `submit` directly and defines its own minimal `IStETHSubmit` / `IWstETHWrap` interfaces. | Allowance handling, leftovers, receiver handling, manager delegation, Vault/Core call ordering, reentrancy, slippage-free paths, native-ETH route enablement gate and submit revert bubbling. |
| `contracts/src/Zappers/SkyUsdcSUsdsYieldZapper.sol` | 187 | USDC -> USDS -> sUSDS -> dUSDS ingress zapper variant. | Sky route/token identity, asset conversion, allowance cleanup, failure rollback. |
| `contracts/src/Zappers/BaseZapper.sol` | 46 | Shared Zapper base. | Shared access / manager handling, statelessness. |
| `contracts/src/Zappers/LeftoversSweep.sol` | 47 | Helper for sweeping leftover tokens after Zapper execution. | Leftover token receiver correctness, unnecessary allowance / stuck-fund prevention. |
| `contracts/src/Zappers/Modules/Exchanges/UniV4Exchange.sol` | 188 | `IExchange` adapter for the JPYdf/USDC Uniswap v4 final leg. | Universal Router / Permit2 allowance, pool key / hook policy, exact-output refund, route config gate. |
| `contracts/src/Zappers/Modules/Exchanges/UniswapV4/V4RouterCodec.sol` | 8 | v4 router command encoding helper. | Command byte correctness. |

Subtotal: 1,051 nSLOC.

### 3.5 Archived, Previously Audited Strategy Sources

These files were in scope for, and covered by, the external audit completed
**2026-08-05** against audited identity **`0c7766e0`**
(`0c7766e0a935b3dd99111349ef84e69c1a07da38`, jpydf-v2 `develop`, sync PR #1418).

They are **not deleted**. Deleting them would discard a completed audit result and
force a from-scratch review if either venue is ever reconsidered. They are moved
to `contracts/src/Strategies/archive/`, and their test suites to
`contracts/test/archive/`, with an `ARCHIVED` NatSpec banner on each source file.

They are **out of the active A full-review body and out of the active nSLOC** and
must not be priced in a new SOW.

| File | nSLOC | Audited under | Why archived |
| --- | ---: | --- | --- |
| `contracts/src/Strategies/archive/LidoStrategy.sol` | 327 | `0c7766e0` | Underlying is structurally WETH (`initialize(..., IWETH _weth, ...)`; deposit unwraps WETH to native ETH before `lido.submit`). The non-WETH rejection lived in the deploy selector, removed in PR #1424 along with the kind, venue struct, helpers, and env keys; branch 0's underlying then moved WETH -> wstETH, so no branch can supply one. |
| `contracts/src/Strategies/archive/EtherfiWeETHStrategy.sol` | 261 | `0c7766e0` | Same structural WETH underlying and same removed deploy surface. |
| `contracts/src/Strategies/archive/AsyncRequestStrategy.sol` | 114 | `0c7766e0` | Shared async request base with no remaining consumer. Its only subclasses were the two archived Strategies; every active Strategy derives from `BaseStrategy` directly, and Morpho Vaults V2 is fully synchronous. |
| `contracts/src/Strategies/archive/WeETHWithdrawAdapter.sol` | 108 | `0c7766e0` | First-party withdrawal adapter for the archived `EtherfiWeETHStrategy`; no other consumer. |

Subtotal: **810 nSLOC, excluded from the A body.**

**Compile and test posture.** The archive stays inside the `src` and `test` roots,
so `forge build` still compiles it and `forge test` still runs its 84 tests
(`LidoStrategyTest` 50, `EtherfiWeETHStrategyTest` 34). No build-profile exclusion
was introduced. Passing tests are the evidence that the preserved audit artifacts
have not rotted. They are excluded from the Foundry coverage shards, because
coverage targets active scope.

**Negative assurance for the auditor.**

- No `contracts/src` file outside `contracts/src/Strategies/archive/` imports an
  archived file. Verify with
  `git grep -n "Strategies/archive" -- contracts/src contracts/script contracts/test`.
- `contracts/script/DeployLiquity2.s.sol` has no `lido` or `etherfi` strategy kind,
  venue struct, helper, or env key (removed in PR #1424), so no reachable deploy or
  register path exists.
- Re-activation is a new proposal: re-entry into the `DeployLiquity2` strategy
  selector, a fresh strategy activation package, and an explicit audit-scope change.
  The `0c7766e0` result may be cited as prior coverage of the unmodified source, but
  it does not by itself authorize activation.

## 4. Interface / ABI Files

Interfaces and external ABI shims are small and have no implementation logic. Do
not count them in the main economic/security nSLOC. Keep them listed for
ABI/interface consistency review and add `+1,253 nSLOC` only if the auditor
explicitly prices interfaces.

| File | nSLOC | Purpose |
| --- | ---: | --- |
| `contracts/src/Dependencies/AggregatorV3Interface.sol` | 8 | Chainlink AggregatorV3 ABI |
| `contracts/src/Interfaces/IActivePool.sol` | 37 | ActivePool ABI |
| `contracts/src/Interfaces/IAddressesRegistry.sol` | 65 | AddressesRegistry ABI |
| `contracts/src/Interfaces/IAddRemoveManagers.sol` | 8 | Add / remove manager delegation ABI |
| `contracts/src/Interfaces/IBorrowerOperations.sol` | 141 | BorrowerOperations user-facing ABI |
| `contracts/src/Interfaces/ICollateralRegistry.sol` | 18 | CollateralRegistry ABI |
| `contracts/src/Interfaces/ICollSurplusPool.sol` | 7 | CollSurplusPool ABI |
| `contracts/src/Interfaces/IDebtInFrontHelper.sol` | 23 | Debt-in-front helper ABI |
| `contracts/src/Interfaces/IDefaultPool.sol` | 11 | DefaultPool ABI |
| `contracts/src/Interfaces/IHintHelpers.sol` | 32 | Hint helper ABI |
| `contracts/src/Interfaces/IJpydfRewardsReceiver.sol` | 4 | JPYdf rewards receiver ABI |
| `contracts/src/Interfaces/IJpyUsdRateProvider.sol` | 4 | JPY/USD rate provider ABI |
| `contracts/src/Interfaces/IJpydfToken.sol` | 68 | JpydfToken / bridge-ready surface ABI |
| `contracts/src/Interfaces/ILiquityBase.sol` | 7 | Liquity base ABI |
| `contracts/src/Interfaces/ITroveEvents.sol` | 83 | Trove event ABI |
| `contracts/src/Interfaces/ITroveManager.sol` | 136 | TroveManager ABI |
| `contracts/src/Interfaces/ITroveNFT.sol` | 6 | Trove NFT ABI |
| `contracts/src/Interfaces/IMetadataNFT.sol` | 15 | Trove NFT metadata ABI |
| `contracts/src/Interfaces/IRedemptionHelper.sol` | 29 | Redemption helper ABI |
| `contracts/src/Interfaces/ILiquidationCandidateGetter.sol` | 30 | Liquidation candidate helper ABI |
| `contracts/src/Interfaces/IDToken.sol` | 18 | dToken ABI |
| `contracts/src/Interfaces/ICollateralVault.sol` | 156 | CollateralVault ABI |
| `contracts/src/Interfaces/IMultiTroveGetter.sol` | 34 | MultiTroveGetter ABI |
| `contracts/src/Interfaces/IStrategy.sol` | 13 | Strategy common ABI |
| `contracts/src/Interfaces/ISkyUsdcSUsdsConverter.sol` | 22 | Sky LitePSMWrapper and DF converter ABI |
| `contracts/src/Interfaces/IPriceFeedProxy.sol` | 38 | PriceFeedProxy ABI |
| `contracts/src/Interfaces/IMainnetPriceFeed.sol` | 12 | Mainnet price feed ABI |
| `contracts/src/Interfaces/IPriceFeed.sol` | 6 | Core price feed ABI |
| `contracts/src/Interfaces/ISortedTroves.sol` | 39 | SortedTroves ABI |
| `contracts/src/Interfaces/IStabilityPool.sol` | 29 | StabilityPool ABI |
| `contracts/src/Interfaces/IStabilityPoolEvents.sol` | 33 | StabilityPool event ABI |
| `contracts/src/Interfaces/IWETH.sol` | 6 | WETH minimal ABI |
| `contracts/src/Interfaces/IInterestRouter.sol` | 3 | Liquity interestRouter marker ABI |
| `contracts/src/Interfaces/IInitiative.sol` | 33 | Liquity V2-gov-compatible initiative hook ABI |
| `contracts/src/Interfaces/IDistributionCreator.sol` | 16 | Merkl DistributionCreator campaign ABI |
| `contracts/src/Zappers/Modules/Exchanges/UniswapV4/IPermit2.sol` | 8 | Permit2 minimal ABI |
| `contracts/src/Zappers/Modules/Exchanges/UniswapV4/IUniversalRouter.sol` | 4 | Universal Router minimal ABI |
| `contracts/src/Zappers/Modules/Exchanges/UniswapV4/IV4Router.sol` | 28 | Uniswap v4 router minimal ABI / structs |
| `contracts/src/Zappers/Interfaces/IExchange.sol` | 5 | Exchange adapter ABI |
| `contracts/src/Zappers/Interfaces/IZapper.sol` | 18 | Zapper user-facing ABI |

Subtotal: 1,253 nSLOC.

## 5. TroveNFT / NFT Metadata Light Diff Review

These files are deployed or directly used by deployed TroveNFT metadata, but the
reviewed diff is display-oriented. They should not be priced as full
economic/security audit scope unless the auditor requires every deployed
view/rendering contract to be full-review counted.

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/JPYdfTroveNFT.sol` | 53 | Deployed Trove ownership NFT variant. Returns JPYdf-branded collection name and symbol. | Mint/burn remains TroveManager-only and base/OZ ERC-721-equivalent; diff is limited to collection name/symbol and custom error. |
| `contracts/src/NFTMetadata/JPYdfMetadataNFT.sol` | 74 | Deployed NFT metadata renderer variant. Returns JPYdf-branded tokenURI JSON / SVG. | `uri`, `attributes`, and `dynamicTextComponents` are view-only; diff is limited to display text and input data shape. |
| `contracts/src/NFTMetadata/utils/JPYdfBaseSVG.sol` | 203 | JPYdf-branded SVG rendering helper. | Fixed card layout, JPYdf logo / text rendering, and collateral-logo omission behavior; no protocol state, external mutation, or authorization behavior. |

Subtotal: 330 nSLOC.

## 6. Optional NFT Metadata Support Utilities

These files support NFT rendering. They are not economic accounting code, but
include them in conservative full-review scope if the deployed NFT metadata
surface is priced as full scope.

| File | nSLOC | Purpose | Primary review focus |
| --- | ---: | --- | --- |
| `contracts/src/NFTMetadata/utils/FixedAssets.sol` | 21 | SVG / metadata fixed asset constants. | No external effects, rendering correctness. |
| `contracts/src/NFTMetadata/utils/JSON.sol` | 71 | JSON string encoding helper. | Escaping / tokenURI formatting. |
| `contracts/src/NFTMetadata/utils/SVG.sol` | 35 | SVG helper library. | Rendering correctness. |
| `contracts/src/NFTMetadata/utils/Utils.sol` | 60 | String / numeric utility helpers. | Numeric formatting / bounds. |
| `contracts/src/NFTMetadata/utils/bauhaus.sol` | 470 | SVG art helper / assets. | Rendering only, no protocol state. |

Subtotal: 657 nSLOC.

## 7. B Scope: Core Diff-Boundary / Parity Review

The following files are base-derived core files with small non-rename changes or
SafeERC20 hardening call sites. The recommended treatment is not full re-audit by
whole-file nSLOC, but normalized diff review plus behavior parity. If an auditor
prices any changed file as whole-file full review, add this subtotal to the A
baseline.

| File | nSLOC | Purpose | Review treatment |
| --- | ---: | --- | --- |
| `contracts/src/BorrowerOperations.sol` | 1,208 | User entrypoint for Trove open / adjust / close / repay / borrow flows. | BOLD-to-JPYdf rename plus WETH / collateral transfer hardening call sites. Review changed hunks and parity tests; whole-file count only for conservative upper bound. |
| `contracts/src/TroveManager.sol` | 1,476 | Trove state machine: liquidation, redemption application, redistribution. | WETH gas compensation transfer hardening plus rename. Core accounting should remain base-parity. |
| `contracts/src/RedemptionHelper.sol` | 126 | Redemption wrapper and off-chain simulation helper. | JPYdf pull / refund `safeTransfer` hardening plus rename. |
| `contracts/src/DefaultPool.sol` | 64 | Redistribution debt / collateral pool. | Approval hardening and collateral transfer compatibility. |
| `contracts/src/GasPool.sol` | 16 | WETH gas compensation pool. | WETH approval hardening. |

Subtotal: 2,890 nSLOC.

Other base-derived support files such as `AddressesRegistry.sol`,
`CollateralRegistry.sol`, `StabilityPool.sol`, `SortedTroves.sol`,
`CollSurplusPool.sol`, `DebtInFrontHelper.sol`, `HintHelpers.sol`,
`MultiTroveGetter.sol`, `Dependencies/AddRemoveManagers.sol`,
`Types/BatchId.sol`, `Types/LatestBatchData.sol`, `Types/LatestTroveData.sol`,
`Types/TroveChange.sol`,
`LiquityMath.sol`, `LiquityBase.sol`, and `Ownable.sol` remain in the production
source population. They are covered by fork-parity / integration review and by
the source map, but they are not added to the A full-review nSLOC unless the
auditor chooses to price the whole production source population.

`StabilityPool.sol` is intentionally kept as the base-parity reference beside
the deployed `DFStabilityPool.sol`. The current launch wiring uses `DFStabilityPool`,
which adds the same-block withdrawal guard; deleting the base file during audit
freeze would make fork-parity review harder without reducing deployed attack
surface.

### 7.1 Base-Derived Support / Reference Files

These files are part of the production Solidity source population and must stay
visible in the audit package. They are not included in the A full-review nSLOC
because the review question is fork parity, source-map completeness, and
integration assumptions rather than new JPYdf economic design.

| File | nSLOC | Review treatment |
| --- | ---: | --- |
| `contracts/src/AddressesRegistry.sol` | 118 | Branch address registry parity / wiring reference. |
| `contracts/src/CollateralRegistry.sol` | 224 | Branch registry / redemption routing parity and integration reference. |
| `contracts/src/StabilityPool.sol` | 300 | Base SP parity reference beside deployed `DFStabilityPool`. |
| `contracts/src/SortedTroves.sol` | 322 | Sorted list parity / integration reference. |
| `contracts/src/CollSurplusPool.sol` | 53 | Collateral surplus pool parity / integration reference. |
| `contracts/src/DebtInFrontHelper.sol` | 95 | Read-only helper parity / integration reference. |
| `contracts/src/HintHelpers.sol` | 202 | Read-only hint helper parity / integration reference. |
| `contracts/src/MultiTroveGetter.sol` | 122 | Read-only getter parity / integration reference. |
| `contracts/src/Dependencies/AddRemoveManagers.sol` | 85 | Trove manager delegation parity / authorization support. |
| `contracts/src/Types/BatchId.sol` | 16 | Shared type definition. |
| `contracts/src/Types/LatestBatchData.sol` | 15 | Shared type definition. |
| `contracts/src/Types/LatestTroveData.sol` | 13 | Shared type definition. |
| `contracts/src/Types/TroveChange.sol` | 15 | Shared type definition. |
| `contracts/src/Dependencies/LiquityMath.sol` | 44 | Base math parity / reference. |
| `contracts/src/Dependencies/LiquityBase.sol` | 47 | Base shared references / integration parity. |
| `contracts/src/Dependencies/Ownable.sol` | 23 | Base ownership helper parity / reference. |

Subtotal: 1,694 nSLOC.

## 8. Scope Boundaries

| Boundary | Treatment |
| --- | --- |
| A full-review body | DF-modified core surfaces and JPY DeFi-specific implementation contracts. |
| B core parity review | Base-derived core files where the review goal is parity / diff-boundary, not fresh protocol design review. |
| NFT metadata | Light diff/rendering review. Deployed/public surface, but not economic full-review scope by default. |
| Interfaces | ABI/interface consistency review. Not counted in main nSLOC by default. |
| Launch-final reference material | Deploy scripts, handover scripts, manifest generation, runbooks, ops console boundaries. Useful for launch evidence and deployment sanity checks, but outside Solidity audit scope and nSLOC unless explicitly scoped as a separate launch-execution review. |
| Explicitly out of scope for the current contract audit | `contracts/lib/**`, removed Curve / Balancer / Uniswap v3 routes, Flash Loan close, collateral-funded repay, Multiply, active bridge protocol, other-chain deployment, direct non-USDC JPYdf pools, future `Treasury.sol` / `SPAdditionalRewardDistributor.sol` / `BorrowReferralRewardDistributor.sol` / `SPDepositReferralRewardDistributor.sol` and their interfaces, tests, and cutover execution until a separate activation audit package is opened. |

Deploy and handover scripts are excluded from A/B implementation nSLOC and from
the Solidity audit scope. They are kept in the handoff package as reference
scripts because wrong addresses, roles, manifest fields, or handover calls can
create launch risk. If deployment ceremony / launch execution is included in a
separate operational SOW, the minimum sanity-check list is:

- `contracts/script/DeployLiquity2.s.sol`
- `contracts/script/PrepareDFGovernanceHandover.s.sol`
- `contracts/script/VerifyDFGovernanceHandover.s.sol`
- `contracts/script/AcceptDFGovernanceHandover.s.sol`
- `contracts/script/DeployPILAllocatorPhaseA.s.sol`

## 9. Audit Freeze Handoff Checklist

This document is a live scope map, not the final freeze evidence by itself. The
audit handoff package should include the following artifacts at the freeze
commit.

| Artifact | Required evidence |
| --- | --- |
| Freeze identity | Freeze branch or tag, exact commit SHA, auditor package owner, and whether the package is pre-audit final or dry-run only. |
| Fresh nSLOC evidence | `cloc --version`, the `cloc --by-file --csv --quiet --include-lang=Solidity contracts/src` output, normalized CSV-body sha256 (`tail -n +2`), and confirmation that Section 2 totals were refreshed in the same PR if the output differs. The CSV includes `contracts/src/Strategies/archive/**`; subtract the Section 3.5 subtotal (810) to reconcile against the active A body. |
| Source map | This scope document, `Contract-Business-Catalog.md`, `contracts/README.md`, `contracts/src/README.md`, `Product-Overview.md`, `Parameters.md`, `Governance.md`, and the component specs for every A-scope file. |
| Core diff ledger | `Liquity-v2-Core-Spec.md` section 2.2 (`CORE-MOD-*`) plus the B-scope file list in Section 7. |
| Activation gates | Mainnet deploy env freeze, Safe role assignment, governance handover, strategy selection / Morpho vault freeze package, liquidity route policy, bridge minter activation gate, and fork stress evidence package. |
| Negative scope proof | Evidence that `contracts/src` contains no Curve, Balancer, Uniswap v3 route adapter, flash-close, collateral-funded repay, Multiply, active bridge adapter, `Treasury.sol`, or future reward distributor implementation. |
| Manifest proof | Expected launch-active manifest has exactly `aave` on branch 0 (dwstETH), `aave` + `morpho-v2` on branch 1 (dUSDC) with `erc4626` optionally permitted, no Sky active entry, and **no Strategy registration on branches 2–7** (2 dUSDT / 3 dUSDS / 4 dXAUT are wired but Strategy-disabled at cap 0; 5–7 are inert). Archived Lido / Etherfi surfaces have no strategy kind in `DeployLiquity2.s.sol` and therefore cannot appear in any manifest. |
| Dormant authority proof | `bridgeMinterCount == 0`, no pending bridge minter proposal, inert/dormant branch dToken caps are zero, and PIL / UniV4 / Merkl routing is not funded or user-facing until its activation package is approved. |
| Verification commands | At minimum, `git diff --check`, the fast Foundry gate used by PR CI, focused tests for any files changed after this handoff, and any fork / stress evidence referenced by the launch gate. |

### 9.1 Solidity File-Level Audit Checklist

Before sending the freeze package, fill this checklist against the exact freeze
commit. Each row should have an owner, evidence link, and explicit PASS / BLOCKED
status in the issue or handoff sheet. This checklist is intentionally
Solidity-file focused; operational artifacts remain evidence inputs, not
Solidity nSLOC.

| ID | Solidity surface | Audit class | Required check before handoff |
| --- | --- | --- | --- |
| SOL-A-001 | `ActivePool.sol`, `DFStabilityPool.sol`, `JpydfToken.sol`, `Dependencies/Constants.sol` | A full-review | Confirm DF changes are mapped to `CORE-MOD-*`, `Parameters.md` values match constants, same-block SP guard and bridge-ready dormant token surface have focused tests, and bridge minter launch state is zero. |
| SOL-A-002 | `DToken.sol`, `CollateralVault.sol` | A full-review | Confirm cap / decimal conversion / one-time binding / buffer / delayed redeem / allocation / writeoff / backstop / upgrade-role behavior is covered by component specs, tests, and launch env gates. |
| SOL-A-003 | `InterestRouterForwarder.sol`, `PILAllocator.sol`, `Initiatives/UniV4MerklInitiative.sol` | A full-review / gated activation | Confirm the recipient is the approved holding Safe/address unless PIL activation is separately approved; check owner / guardian split, bounded distribution loop, Merkl trust boundary, and no user-facing funding before activation. |
| SOL-A-004 | `Strategies/BaseStrategy.sol`, `AaveV3Strategy.sol`, `ERC4626Strategy.sol`, `MorphoV2Strategy.sol` | A full-review / launch-active | Confirm Vault-only accounting, principal / profit separation, reward sweep boundaries, reentrancy guard, emergency recovery, Aave/Morpho venue assumptions, Morpho vault freeze evidence, and the `MorphoV2Strategy` forced-deallocation penalty bound. Confirm `BaseStrategy` has no remaining async-request surface now that `AsyncRequestStrategy` is archived. |
| SOL-A-005 | `Strategies/SkyUsdcSUsdsStrategy.sol`, `Strategies/SkyUsdcSUsdsConverter.sol` | A full-review / optional not launch-active | Confirm the implementations are reviewed as production code but are absent from the expected launch-active manifest, not registered, not allocated to, and require a separate activation package before use. |
| SOL-X-001 | `Strategies/archive/LidoStrategy.sol`, `Strategies/archive/EtherfiWeETHStrategy.sol`, `Strategies/archive/WeETHWithdrawAdapter.sol`, `Strategies/archive/AsyncRequestStrategy.sol` | Archived / previously audited, out of active scope | Do **not** price or re-review. Confirm instead: the four files live only under `contracts/src/Strategies/archive/`; no active `contracts/src` file imports them; `DeployLiquity2.s.sol` exposes no `lido` / `etherfi` strategy kind, venue struct, helper, or env key; the sources are byte-identical to the `0c7766e0` audited versions apart from the added `ARCHIVED` NatSpec banner and the relocated import paths; and their 84 tests still pass. Section 3.5. |
| SOL-A-006 | `PriceFeeds/DF*.sol`, `PriceFeeds/sUSDSPriceFeed.sol`, `PriceFeeds/PriceFeedProxy.sol`, `PriceFeeds/CompositePriceFeed.sol`, `PriceFeeds/PriceFeedPlaceholder.sol`, `PriceFeeds/MainnetPriceFeedBase.sol` | A full-review | Confirm feed addresses / decimals / staleness are frozen, `PriceFeedProxy` source switch smoke tests are documented, JPY freeze behavior is covered, placeholder feeds cannot activate live branches accidentally, and removed WSTETH/RETH fallback behavior is not present. |
| SOL-A-007 | `Zappers/CollateralYieldZapper.sol`, `Zappers/SkyUsdcSUsdsYieldZapper.sol`, `Zappers/BaseZapper.sol`, `Zappers/LeftoversSweep.sol`, `Zappers/Modules/Exchanges/UniV4Exchange.sol`, `Zappers/Modules/Exchanges/UniswapV4/V4RouterCodec.sol` | A full-review / route gated | Confirm open/add/withdraw/close-with-JPYdf do not depend on swaps, `UniV4Exchange` is reviewed but not user-facing until route config / fork evidence / manifest gates pass, and no flash-close / collateral-funded repay / Multiply entrypoint exists. |
| SOL-A-008 | `LiquidationCandidateGetter.sol` | A full-review / read-only helper | Confirm bounded scan behavior, zombie / inactive Trove exclusion, invalid branch handling, read-only non-interference with core state, and liquidator bot / frontend integration evidence. |
| SOL-B-001 | `BorrowerOperations.sol`, `TroveManager.sol`, `RedemptionHelper.sol`, `DefaultPool.sol`, `GasPool.sol` | B parity / diff-boundary | Confirm normalized diff review covers transfer / approval hardening and rename-only regions, while inherited core accounting remains fork-parity. |
| SOL-B-002 | Other base-derived support files listed in Section 7 | B parity / reference | Confirm source-map inclusion and parity/integration treatment; do not include in A nSLOC unless the auditor prices whole production source. |
| SOL-B-003 | `Dependencies/AddRemoveManagers.sol` | B parity / authorization support | Confirm upstream parity, Trove owner / add-manager / remove-manager authorization semantics, receiver handling, wipe-on-close behavior, and BorrowerOperations / Zapper integration tests. |
| SOL-L-001 | `JPYdfTroveNFT.sol`, `NFTMetadata/JPYdfMetadataNFT.sol`, `NFTMetadata/utils/JPYdfBaseSVG.sol` | Light diff/rendering | Confirm display-only diff, NFT authorization parity, and no fund / debt / liquidation / redemption behavior. |
| SOL-L-002 | `NFTMetadata/utils/FixedAssets.sol`, `NFTMetadata/utils/JSON.sol`, `NFTMetadata/utils/SVG.sol`, `NFTMetadata/utils/Utils.sol`, `NFTMetadata/utils/bauhaus.sol` | Optional NFT support utilities | Confirm rendering-only / encoding-only behavior, JSON escaping and numeric formatting sanity, and no protocol state, external mutation, authorization, or fund movement. |
| SOL-I-001 | `Interfaces/**`, `Dependencies/AggregatorV3Interface.sol`, `Zappers/Interfaces/**`, Uniswap v4 minimal interfaces | Interface consistency | Confirm ABI matches implementations and external integrations; do not count as implementation nSLOC unless the auditor requests it. |
| SOL-O-001 | Curve / Balancer / Uniswap v3 adapters, flash-close, collateral-funded repay, Multiply, fail-fast exchange placeholder | Removed / absent | Attach a negative source-tree proof that these files and ABI entrypoints are absent from production `contracts/src`. |
| SOL-O-002 | `Treasury.sol`, `SPAdditionalRewardDistributor.sol`, `BorrowReferralRewardDistributor.sol`, `SPDepositReferralRewardDistributor.sol`, active bridge adapter | Future / not implemented | Attach a negative source-tree proof and link the activation gate; do not describe these as current implementation requirements. |

### 9.2 Per-File Evidence Packet

For every A full-review Solidity file, attach or link a small packet with:

- file path, scope class, nSLOC, and deployed / linked / dormant / optional status;
- primary requirement IDs or source docs;
- privileged roles and upgradeability / ownership model;
- external protocol dependencies and trust assumptions;
- focused unit / integration / fork / invariant evidence, or the explicit reason
  a test class is not applicable;
- known accepted risks and the issue / runbook that owns the risk;
- activation gate status if the file is audited but not launch user-facing.

If any production Solidity file is added, removed, or materially changed after
freeze, rerun the checklist and explicitly classify the changed file as A
full-review, B parity, light review, interface-only, operational, or out of
scope before sending an updated package to auditors.
