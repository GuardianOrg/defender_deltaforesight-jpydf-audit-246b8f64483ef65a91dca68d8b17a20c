# Contract Audit Scope and nSLOC

> **SUPERSEDED FOR THE CURRENT ADDITIONAL AUDIT.** The figures and future-tense
> finalization steps below describe an earlier scope checkpoint. Do not use them
> to price or define the final production differential. Root
> [`SCOPE.md`](../../../../SCOPE.md) is the sole current SOW page and contains the
> exact 164-hunk review boundary, 510 final-side changed-code nSLOC, non-scope
> treatment, and requested date. Its 6,124 final whole-file nSLOC is context,
> not scope. The remainder of this file is retained as historical context only.

## 1. Auditor quick read

This document defines the mainnet contract-review boundary after Issue #1454. [`config/day1-branch-manifest.json`](../../../../config/day1-branch-manifest.json) is authoritative: only Branches 0–1 are active and Branches 2–7 are reserved and inert.

| Scope | nSLOC | Treatment |
| --- | ---: | --- |
| Economic/security full-review body | 5,225 | Recommended SOW body; 5,472 less the 401 candidate-specific nSLOC removed by #1454, plus the +154 of §4 |
| TroveNFT / metadata light review | +330 | Display surface with no fund-moving logic |
| Interfaces / ABI shims | +1,264 | ABI consistency only; excluded from implementation nSLOC |
| Base-derived core whole-file upper bound | +2,890 | Normally diff/parity review |
| Active `contracts/src` population | 12,060 | Reconciliation count for all non-archive Solidity source |
| Archive population | 1,212 | 810 Strategy archive + 402 candidate-specific archive |
| Whole `contracts/src` population | 13,272 | Active + archive; not the recommended SOW body |

Counts use the cloc `code` column. The numeric counts above predate the final reserved-branch risk-finalization changes and remain unchanged here; exact-count finalization is pending the final source SHA. At that freeze SHA, preserve the cloc version, by-file CSV, and hash from the full, non-archive, and archive source populations.

## 2. Day-1 deploy boundary

| Branch | State | Required launch surface |
| ---: | --- | --- |
| 0 `dwstETH` | active | wstETH, DFWstETHPriceFeed, CollateralYieldZapper (no Strategy) |
| 1 `dUSDC` | active | USDC, DFUSDCPriceFeed, CollateralYieldZapper, Aave + Morpho V2 Strategies |
| 2–7 | reserved / inert | no Underlying, PriceFeedPlaceholder, cap 0, no Strategy or Zapper, `riskParamsFinalized == false` |

Exact Underlyings, final risk values, and asset-specific Oracles, Strategies, and Zappers for reserved slots are outside the current audit scope. The shared `AddressesRegistry.finalizeRiskParams` path, rejection of opening an unfinalized branch by BorrowerOperations, rejection of deposits into an unfinalized branch by StabilityPool / DFStabilityPool, synchronization among Registry / BorrowerOperations / TroveManager, and the active / reserved deployment-lifecycle split remain in scope. At activation, re-derive the exact Underlying and all six values, then package common-Timelock one-shot finalization, empty-state and non-shutdown checks, atomic cap opening, Owner approval, asset-specific implementation review, and the additional-audit decision together. Risk values cannot change after finalization.

## 3. Archived source

### 3.1 Candidate-specific archive — 402 nSLOC

| File | nSLOC | Status |
| --- | ---: | --- |
| `contracts/src/PriceFeeds/archive/DFUSDTPriceFeed.sol` | 19 | Removed from the Day-1 map and official deploy imports |
| `contracts/src/PriceFeeds/archive/sUSDSPriceFeed.sol` | 95 | Removed from the Day-1 map and official deploy imports |
| `contracts/src/PriceFeeds/archive/DFXAUTPriceFeed.sol` | 19 | Cannot return until an oracle reflects XAUT downside depeg |
| `contracts/src/PriceFeeds/archive/DFWBTCPriceFeed.sol` | 82 | Exact BTC Underlying not approved |
| `contracts/src/Zappers/archive/SkyUsdcSUsdsYieldZapper.sol` | 187 | Candidate-collateral ingress, separate from the dUSDC operating Strategy |
| **Subtotal** | **402** | Excluded from the active 5,472 body |

Archive tests continue compiling and running under `contracts/test/archive/`. Reactivation requires an activation package, Owner approval, implementation review, and an additional-audit decision.

### 3.2 Previously archived Strategy sources — 810 nSLOC

`LidoStrategy`, `EtherfiWeETHStrategy`, `WeETHWithdrawAdapter`, and `AsyncRequestStrategy` under `contracts/src/Strategies/archive/` remain outside active scope. Keep this 810 nSLOC distinct from the candidate-specific 402 nSLOC.

## 4. Active full-review body reconciliation

| Bucket | Before #1454 | #1454 delta | After #1454 | Since | Current |
| --- | ---: | ---: | ---: | ---: | ---: |
| DF-modified core | 849 | 0 | 849 | +6 | 855 |
| JPY DeFi implementation | 2,724 | 0 | 2,724 | +132 | 2,856 |
| Oracle / PriceFeed | 848 | -214 | 634 | +15 | 649 |
| Zapper / route | 1,051 | -187 | 864 | +1 | 865 |
| **Total** | **5,472** | **-401** | **5,071** | **+154** | **5,225** |

The `Since` column covers the oracle-path fixes, the `CollateralVaultLens`
extraction, and the pre-audit pricing / Morpho incident-rail fixes after #1454.
Every line is shown so the total is checkable against `cloc` rather than taken
on trust:

| File | Before | After | Δ | Bucket |
| --- | ---: | ---: | ---: | --- |
| `DFStabilityPool.sol` | 306 | 312 | **+6** | DF-modified core |
| `CollateralVault.sol` | 818 | 782 | **−36** | JPY DeFi |
| `CollateralVaultLens.sol` | — | 159 | **+159** | JPY DeFi |
| `Strategies/MorphoV2Strategy.sol` | 149 | 158 | +9 | JPY DeFi |
| `Strategies/SkyUsdcSUsdsConverter.sol` | 156 | 157 | +1 | Zapper / route |
| `PriceFeeds/JpyUsdRateProvider.sol` | 93 | 101 | +8 | Oracle |
| `PriceFeeds/JpyFreezeLib.sol` | 50 | 55 | +5 | Oracle |
| `PriceFeeds/DFPriceFeedBase.sol` | 69 | 70 | +1 | Oracle |
| `PriceFeeds/DFWstETHPriceFeed.sol` | 88 | 89 | +1 | Oracle |
| **Total** | | | **+154** | |

The one-shot risk-finalization changes to `AddressesRegistry`,
`BorrowerOperations`, `TroveManager`, `StabilityPool`, `DFStabilityPool`, and
their related interfaces, together with the `PriceFeedProxy` emergency-source
recovery delta, remain in audit scope even while Branches 2–7 are inert. At the
audit freeze SHA, rerun the commands in §1, add those deltas to the existing
reconciliation above, and only then finalize the SOW values.

Two changes in the same window do **not** appear above, deliberately.
`Interfaces/ICollateralVault.sol` moved 156 → 167 but interfaces are excluded
from implementation nSLOC by the row in §1, and `archive/sUSDSPriceFeed.sol`
moved 94 → 95 inside the archive, which is why the archive population is 1,212
rather than 1,211. The +154 implementation, +11 interface, and +1 archive
deltas account for the whole 13,106 → 13,272 population move; there is no
unexplained remainder. The final ERC-4626 correction changes a state transition
but keeps the file at 91 `cloc` code lines; only its comments grew.

The original `CollateralVault` → `CollateralVaultLens` split was a relocation,
not new logic: the Vault was within ~50 bytes of the EIP-170 runtime limit, so
its reporting views moved out. The +69 across the pair at that point was
reconstruction glue. The later `CollateralVault` delta is new behaviour for
pricing availability, the Vault-mediated Morpho incident rail, and receiver-delta
redemption. Final Vault runtime is 23,047 / 24,576 bytes, leaving 1,529 bytes.

Shared price-feed bases, CompositePriceFeed, proxies/placeholders, and generic CollateralYieldZapper remain active. SkyUsdcSUsdsStrategy, its converter, and interface remain because they are a separate dUSDC Vault investment candidate; Day-1 deploy policy still rejects Sky Strategy registration.

## 5. Freeze evidence

The auditor handoff must bind an exact commit SHA to active/archive source manifests, cloc CSV/hash, repo-wide legacy-hit classification, full Forge/archive tests, mainnet fork, and deploy→handover→verify evidence. For reserved branches, it must also cover one-shot behavior, caller restriction, empty state, Underlying agreement, child synchronization, rollback, rejection of unfinalized opening and SP deposits, and the boundary between oracle pause and terminal shutdown. Do not finalize #1450 SOW before these artifacts identify the same SHA.

The former five-active edition is retained at [archive/Contract-Audit-Scope-And-nSLOC-pre-issue1454.md](archive/Contract-Audit-Scope-And-nSLOC-pre-issue1454.md) and is not a current SOW input.
