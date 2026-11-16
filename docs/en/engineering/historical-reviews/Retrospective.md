# Retrospective and Lessons from the Old jpydf (Rebuild Background / Post-Mortem)

> **This document explains why jpydf was rebuilt from scratch, and analyzes which assets were carried forward or avoided from the old `deltaforesight/jpydf` repository (frozen, reference-only).** Current work is tracked in [`Development-Plan.md`](../plans/Development-Plan.md).
>
> **PR notation**: every `jpydf#N` in this document refers to a PR in the **old `deltaforesight/jpydf` repository** (frozen, reference-only). PRs in the new `deltaforesight/jpydf-v2` repository (current) are written as `v2#N` and rarely appear here.
> **"→ Phase" notation** is a historical label for the migration phase used during the rebuild. See [`Development-Plan.md`](../plans/Development-Plan.md) for current work.

## 0. Executive Summary — Why Rebuild?

1. **The violation of the minimum-core-modification principle is empirically confirmed**: old `develop` (`848c6b8`) modified **15 core (Liquity v2) files** (+257/-57 lines) relative to clean upstream `base` (`d2e75c3`). Most changes were unnecessary, meaningless, or wrong, and even touched the most sensitive `BorrowerOperations`/`TroveManager` files (§1).
2. **The original layer is real reusable material** (18 new files, about 2,400 lines, plus some tests). `CollateralVault` / `CollateralYieldZapper` / `DToken` / `PriceFeedProxy` / `Strategies` can be migrated once reorganized against the specs (§2, §4).
3. **CI never went green (missing verification foundation)**: old `develop` was left with every CI run red for months, and each PR inherited that red state from `develop` rather than from PR-specific changes. There are also signs that required tests were bypassed with `skip` / carve-outs to force green, but even that did not succeed. The verification premise that "the tests BOLD expects always pass" was never established. → Based on this lesson, jpydf-v2 keeps CI green at every commit and every PR ([`Development-Plan.md`](../plans/Development-Plan.md) §1; full text in this document §6, "keep all tests green at every step; no skips").
4. **Policy**: do not patch over `develop`; rebuild from the latest upstream BOLD (v1.11.0), enforce core no-modification in CI from commit 1, and migrate the verified layers + tests to the current specs **while keeping CI (build + test + core no-modification guard) green at every commit and every PR** (no false green via skips). → Plan: [`Development-Plan.md`](../plans/Development-Plan.md).

---

## 1. Actual Core Modifications in Old `develop` (@ `848c6b8`)

**Evidence**: `git diff base develop -- contracts/src` = 15 modified / 18 added

| File | +/- | Assessment |
|---|---|---|
| `Dependencies/Constants.sol` | +58/-2 | Parameters (allowable), but fixed to the old 8-collateral design |
| `PriceFeeds/MainnetPriceFeedBase.sol` | +44/-8 | JPY conversion **directly edited into upstream** (constructor changed from 3 to 5 args and affected all feeds) → rebuild avoids this with a **new DF base class that inherits without modification** |
| `PriceFeeds/{WETH,WSTETH,RETH,Composite}PriceFeed.sol` | each +24 to +30 | ❌ WSTETH/RETH/Composite are **LSTs not adopted by DF. Wasteful modification** |
| `AddressesRegistry.sol` (+I/F) | +20/+11 | ❌ Injected `collateralVault/dToken/underlyingToken` into core = **responsibility-separation violation** |
| `BorrowerOperations.sol` | +6/-2 | ❌ Two `if(ETH_GAS_COMPENSATION>0)` guards = **unnecessary** (zero transfer is harmless with standard WETH) |
| `TroveManager.sol` | +3/-1 | ❌ Wrapped `+=0` with `if>0` = **entirely meaningless** |
| `BoldToken.sol` | +3/-3 | name/symbol is ✓; changing error messages is unnecessary pollution |
| `GasPool.sol` / `Zappers/*` / `Interfaces/IMainnetPriceFeed.sol` | minor | ❌ unnecessary pollution through comments / direct upstream edits |

**Conclusion**: The "gas=0" change should have been expressible through `Constants.sol` parameters, but was implemented by modifying core logic. The `+=0` guard in `TroveManager` has no functional meaning. Even LST feeds DF does not use were edited. The "minimum core modification" principle was not respected. The history also shows a repeated pattern of **core pollution → revert**: `jpydf#24` (Revert to bold), `jpydf#38` (core modifications), then `jpydf#54` (revert).

---

## 2. Reusable Assets (About 2,400 Lines) and Gaps

**Migratable**: `CollateralVault.sol` / `CollateralYieldZapper.sol` (509) / `DToken.sol` (271) / `PriceFeedProxy.sol` (208) / `Strategies/{BaseStrategy,AaveV3Strategy,MockStrategy}`. Tests: `DToken.t` / `CollateralVault.t` / `CollateralYieldZapper.t` / `PriceFeedProxy.t` / `CollateralYieldManagement.t` (integration).

> ⚠️ During the rebuild, the migration source was not the pull-model version in `develop` (893 lines), but the **push-model version (`jpydf#61` branch, `CollateralVault.sol`@blob `5e019a7`) integrated with deferred-underlying from `jpydf#57`**. Current requirements are canonical in [`CollateralVault.md`](../../protocol/product/spec/CollateralVault.md) and [`Strategy.md`](../../protocol/product/spec/strategies/Strategy.md). `CollateralVault.t` / `CollateralYieldManagement.t` were also rewritten from the `jpydf#61` push-model version.

**Gaps requiring new work**:
- ❌ `Treasury.sol` missing (requirements: harvest recipient, **80% SP / 20% DF Corp** distribution, buyback)
- ❌ no Strategy tests / ❌ `PriceFeedPlaceholder.sol` missing
- ❌ deferred init (`setUnderlying` / Vault↔dToken consistency) not merged into `develop` (`jpydf#57`)
- ❌ principal recovery path for asynchronous Strategy liquidation (Strategy requirement STGY-ERR-002)

---

## 3. Design Drift (Old `develop` → Current Specs)

| Topic | `develop` (old) | Current specs (new) | Reference PR |
|---|---|---|---|
| Collateral branches | 8 collaterals hardcoded with concrete feeds | **finalized 5 + inert 3** (Parameters.md §1) | `jpydf#59`, `#60` |
| Underlying finalization | fixed at deploy time | one-time post-deploy (`setTokenInfo→setUnderlying` order) | `jpydf#57` |
| Core coupling | injected vault/dToken into AddressesRegistry | **no core coupling** (register dToken as collateral at deploy layer, getToken==collToken) | `jpydf#54` |
| Oracle source validation | weak | reject non-contract source and assert branch feed | `jpydf#58` |
| Vault yield path | pull harvest (`claimHarvest`→treasury) | **push model** (Strategy→`receiveFromStrategy`→`transferYieldToTreasury`). `jpydf#52` pull path is not adopted. | `jpydf#61` |
| Tests | pull-based and red CI | **push-model migration + invariant fuzz** | `jpydf#61` |

---

## 4. PR Asset Map (All 61 Old jpydf PRs = `jpydf#1`-`#62` [`#19` is an issue gap]: merged 35 / open 12 / closed-unmerged 14. Measured 2026-06-06)

> All PRs are from the old `deltaforesight/jpydf` repository. The "→ Phase" column records the rebuild-era migration phase.

### 4.1 REUSE (Proven Assets to Migrate)
| PR | Status | Contents | → Phase |
|---|---|---|---|
| `jpydf#54` | merged | **Correct wiring that makes dToken collateral without modifying core** (register dToken in CollateralRegistry, getToken==collToken, deploy-tail require) | P4 |
| `jpydf#35` | merged | `AddressVars.collToken = dToken` (one line, minimum correct solution) | P4 |
| `jpydf#33` | merged | fix deploy owner to `deployer` | P4 |
| `jpydf#17` | merged | dToken-layer foundation (fixed 1:1 DToken rate / Vault skeleton / IStrategy, BaseStrategy, AaveV3 / CYZ) | P3a(DToken/Vault)/P3b(Strategy)/P5(CYZ) |
| `jpydf#31` | merged | `setTokenInfo` deferred init + `__gap[50]` | P3a |
| `jpydf#42` | merged | `Allocated` event changed to 3 args | P3b |
| `jpydf#52` | open | Design reference only for per-strategy allocation and bulk removal. ⚠️ weightBps async harvest / `claimHarvest` / `failedRemovalList` are **replaced by the push model (`jpydf#61`) and not adopted** (only the STGY-ERR-002 async principal-recovery topic goes to the Phase 3b design gate) | P3b(reference) |
| `jpydf#53` | open | LidoStrategy (only real async implementation; needs audit) | P3b-2 (inside MVP; implemented as an individual Strategy) |
| `jpydf#57` | open | **deferred-underlying + Vault↔dToken consistency** (`whenUnderlyingReady` / `setUnderlying` eager check, 148 passed) | P3a |
| `jpydf#59` | open | **placeholder inerting + PriceFeedPlaceholder + Zapper vault-source + Day2 activation order** | P2/P3a/P4 |
| `jpydf#26` | merged | PriceFeedProxy (source replacement / 24h TL / try-catch shutdown / lastGoodPrice) | P2 |
| `jpydf#37` | merged | PriceFeedProxy `Ownable2Step` (avoid conflict via OZOwnable alias) | P2 |
| `jpydf#22` | merged | WBTC peg-monitored 3-step | P2 |
| `jpydf#55` | open | PriceFeedProxy gas-error re-revert (strict bubble when `err.length==4`) | P2 |
| `jpydf#58` | open | PriceFeedProxy rejects non-contract source + branch feed assert | P2/P4 |
| `jpydf#45` | merged | Zapper multicall boundary 3 invariants (reject nested / replay / refund) | P5 |
| `jpydf#61` | open | **Primary reference for push-model Vault/Strategy architecture** (branch `feat/push-model-migration` head `9acb750`. `1312baa` push-model migration + complete test rewrite: 57 unit + 3 invariant + PushModelMocks). `CollateralVault.sol`@blob `5e019a7` = `receiveFromStrategy` / `transferYieldToTreasury` | **P3b** |
| `jpydf#25` | merged | CI trigger (`develop` push + PR opened/synchronize) | P0 |
| `jpydf#49` | open | **bridge-agnostic** mint/burn (persistent bridgeAdmin / 48h timelock / getCCIPAdmin shim) | Historical reference. In the current source of truth, the active bridge is cut on Day-1 and the token exposes only a dormant bridge-ready surface |

### 4.2 REFERENCE (Use the Design, Rebuild the Code)
`jpydf#24` (restore BOLD identifiers) / `jpydf#20` (collUsd naming) / `jpydf#27` (Proxy ABI) / `jpydf#36` (Proxy integration wiring) / `jpydf#56` (demo via CYZ + debt>MIN_DEBT) / `jpydf#62` (faucet sizing + rerun salt) / `jpydf#51` (lesson from Path B split) / `jpydf#40` (text replacement and internal key unchanged) / `jpydf#43` (docs spec) / `jpydf#30` (JPYC depeg) / `jpydf#2` (WBTC conversion formula) / `jpydf#16` (fixed-feed concept → RWA/JGB).

### 4.3 AVOID (Do Not Reproduce; Negative Examples)
| PR | Essence of the failure | Reflected in |
|---|---|---|
| `jpydf#1` | Baked JPY conversion into `MainnetPriceFeedBase` constructor by **direct edit** → changed all feed signatures | keep upstream unmodified and add **JPY in a new DF base** → P2 |
| `jpydf#13`/`#14` | added `if(gas>0)` to BorrowerOps/TroveManager as a gas=0 "optimization" | zero transfers / +=0 are harmless → do not touch core → P1 guard |
| `jpydf#9` | renamed BoldToken→JPYdfToken across all core files | keep core names unchanged; visible name only through deploy args → P1 |
| `jpydf#38` | treated redemption mismatch symptoms by **modifying core** → fully reverted by `jpydf#54` | do not hide symptoms in core; root cause is deploy registration → P4 |
| `jpydf#39`/`#44` | Pyth dual-oracle (invasive core feed changes, payable/refund/VAA complexity) | single Chainlink; no payable feed → P2 |
| `jpydf#47` | physically deleted LSTs (core no-modification violation + collateral test fallout + stale count literals causing OOB) | preserve pristine upstream; grep count constants fully → P2/P4 |
| `jpydf#50` | hard-shrank NUM_BRANCHES 8→4 | branch count immutable → Day-1 deploy with final count → P4 |
| `jpydf#51` | deferred-underlying as two independent setters without cross-checking | enforce cross-invariants in code (`jpydf#57` style) → P3a |
| `jpydf#28` | CCIP setBridgeMinter could not be called after renounce and locked out | persistent admin model (`jpydf#49`) → P6 (🚫 Cut) |
| `jpydf#3`/`#5` | repo created by code-copy, losing clean history | proper import (resolved in jpydf-v2) |
| `jpydf#7` | React/Next.js RCE CVE | new frontend starts from patched version → P5 |

### 4.4 Pure DEAD-END (Irrelevant to the Rebuild)
`jpydf#6` (relay merge) / `jpydf#10` (config) / `jpydf#23` (AI explanation md) / `jpydf#11` (huge unmerged) / `jpydf#18` (WIP doc) / `jpydf#21` (artifact contamination) / `jpydf#41` and `#48` (not adopted standalone → integrated into `jpydf#52`) / `jpydf#46` (discarded revert → evidence for Proxy finalization).

---

## 5. Asset Handling Cheat Sheet
| Category | Targets |
|---|---|
| **Revert / discard** | 15 core modifications (`if>0` in BorrowerOps/TroveManager, GasPool/Bold text, AddressesRegistry coupling, WSTETH/RETH/Composite edits) |
| **Inherit as-is** | Clean upstream BOLD core set (unmodified) |
| **Apply parameters only** | BoldToken name/symbol, Constants (gas=0/MIN_DEBT/branch-specific CR) |
| **Migrate** | DToken / **CollateralVault (push-model `jpydf#61` + deferred-underlying `jpydf#57`)** / PriceFeedProxy / Strategies (push) / CollateralYieldZapper / tests (push-model version from `jpydf#61`). Feeds are new files (below). |
| **Build new** | Treasury (80/20 and design gate) / `DFPriceFeedBase` + DF feeds (WETH/USDC/USDT/sUSDS/XAUT, Day-1) / PriceFeedPlaceholder / RWA, JGB, WBTC feeds (Day-2) / Strategy tests / async principal recovery (inside MVP = implemented in P3b-2 as LidoStrategy.md; compatibility design = STGY-ERR-002) / core no-modification CI guard |
| **Primary references (unmerged PRs)** | `jpydf#55-62` stack / **`jpydf#61` (push-model Vault/Strategy foundation + tests)** / `jpydf#52` (strategy design reference only; pull not adopted) / `jpydf#53` (Lido async; **inside MVP = implemented in P3b-2**) / `jpydf#57` (deferred-underlying) / `jpydf#49` (bridge is historical reference; current = Day-1 active bridge cut + dormant token readiness) |

---

## 6. Lessons for Managing Core Deltas (13 Rebuild-Era Rules with PR Evidence)

> This section preserves the rebuild-era lessons and evidence derived from old jpydf (§1 and §4.3 AVOID). Current normative controls are [`Development-Plan.md`](../plans/Development-Plan.md) §1, the `CORE-MOD-*` ledger in [`Liquity-v2-Core-Spec.md`](../../protocol/product/spec/Liquity-v2-Core-Spec.md), canonical-surface guards, diff review, and parity tests.

1. **Do not add `if(gas>0)` to core transferFrom / additions** (gas=0 is constants-only; zero transfers are harmless). ← `jpydf#13/#14`.
2. **Do not bake JPY conversion into upstream feeds (`MainnetPriceFeedBase` included) constructors or logic**. Leave upstream unmodified and add JPY conversion through **new DF base subclasses** (extension, not edit). ← `jpydf#1`.
3. **Keep BoldToken contract name, filename, and identifiers as upstream**. Visible names only through `_NAME`/`_SYMBOL`. ← `jpydf#9`.
4. **Do not fix redemption/token mismatch by modifying CollateralRegistry/RedemptionHelper/IActivePool**. The root cause is token registration during deploy. ← `jpydf#38`→`jpydf#54`.
5. **Do not inject vault/dToken/underlying into AddressesRegistry** (existing `collToken` + deploy-local data is enough). ← old `develop` M violation.
6. **NUM_BRANCHES is fixed at the final count (8). Shrunk deploys are forbidden**. ← `jpydf#50`.
7. **When changing count/array constants, grep all old literals (`i<3`, `[2]`)**. catch-all else must `revert` (fail-closed). ← `jpydf#47`/`jpydf#60`.
8. **Approval is not correctness** (`jpydf#38` was merged with member approval). The rebuild initially enforced a `base` byte-identical frozen list. Current accepted deltas are controlled by the JPYdf canonical-surface guard, the `CORE-MOD-*` ledger, diff review, and parity tests.
9. **Do not create Pyth/payable feeds** (single Chainlink). ← `jpydf#39`/`jpydf#44`.
10. **Measure procedures and ordering in enforcing code as well as documentation**. Specifications remain normative; treat a docs/code mismatch as an audit finding to resolve rather than rewriting an approved specification merely to mirror implementation.
11. **Specification source of truth = `documents/jp/*.md` in the `deltaforesight/jpydf-v2` repository** (`../*.md` in [`Development-Plan.md`](../plans/Development-Plan.md) refers to these). The canonical copy is the team's shared `develop`; each local folder is a git working tree. Edits should directly update the relevant `.md`, commit, and push to `develop`. Implementation, review, and audit use these specs as primary information; inconsistencies in Oracle/Parameters/etc. are fixed in `documents/jp/*.md`. Directory guide/list is `[../../README.md](../../README.md)`.
12. **Confirm CI (`forge build` + `forge test` + Core JPYdf surface guard) is green at every commit and every PR**. Do not merge red. The new `jpydf-v2` repo is clean from commit 1, so CI green can be maintained (do not reproduce old `develop` inheriting red for months). Run fork tests that depend on `MAINNET_RPC_URL` in CI and confirm green. Do not consider "passed locally" sufficient ([`Development-Plan.md`](../plans/Development-Plan.md) §5 completion definition). **Adapt affected existing tests in the same PR according to rule 13**.
13. **Keep tests "current and all green" (do not defer to later phases and do not escape with skips)**: every time a parameter or feature is implemented in a phase, fix **all affected upstream BOLD tests across forkless, Mainnet fork, and E2E** in the **same PR**: trove debt/collateral amounts, expected values, revert conditions, boundary asserts, invariant handler bounds (example: `BORROWED_MAX`), anchored fuzz counterexample replay, etc. Keep `forge test` green at all times. Maintain the state where "the test cases BOLD expected always pass" **at every step**. **Deferring test adaptation to a later phase, and adding new `vm.skip` escapes, are forbidden without exception**. Run fork tests against `MAINNET_RPC_URL` / public archive RPC (pinned block on blastapi, latest on publicnode). When real-pool swaps exist, scale collateral and pool seeding proportionally to preserve slippage; scale only size-dependent absolute tolerances (keep ratios, rates, and seeds unchanged). Lesson: do not leave fork tests red with carve-outs. ← This policy was confirmed by the user on 2026-06-06. `v2#6` demonstrated it by adapting Mainnet fork 147 + E2E + 11 anchored fuzz replays for `MIN_DEBT=100_000e18`, **removing skips and reaching all CI green** with no carve-outs.

---

## Appendix. Measurement Commands (Reproduction)
```bash
# Measure core modifications in old develop (analysis basis)
git clone --quiet https://github.com/deltaforesight/jpydf.git <dir> && cd <dir>
git diff origin/base origin/develop --name-status -- contracts/src   # A18 / M15
# Confirm new repo baseline
gh repo view deltaforesight/jpydf-v2
```
> Measurements are fixed to the heads at the time (old develop=`848c6b8` / base=`d2e75c3`, new baseline=`d62e2ea3`). Repository state can change, so re-fetch and re-run before starting work.

---

> How this background and these lessons affect the forward-looking plan (guardrails and Phase ToDos) → [`Development-Plan.md`](../plans/Development-Plan.md)
