# JPYdf Protocol — Additional Assessment Review

## PR #107 (Solidity Remediation) + PR #109 (Production Companion)

**Final Consolidated Report**
**Date:** 2026-09-03
**Engagement:** PR #107 (`audit/additional-remediation-candidate`, merged 2026-08-31) — 25 files / 171 hunks / +745/−185 lines; PR #109 (supporting materials)

---

## About This Document

This report consolidates the joint independent review of two pull requests:

- **PR #107** — materializes the current post-`d412` production Solidity differential: 25 files, `+745/−185` physical lines across oracle validation, JPY/USD provenance, three price paths, recoverable oracle shutdown, reserved-branch risk finalization, vault solvency gating, and `MIN_DEBT` boundaries.
- **PR #109** — authoritative scope, complete final tests, pinned build inputs, English specifications, prior Chain Defenders reports, provenance, and reproducibility evidence. It does **not** change the production Solidity shown in #107.

The client is expected to ship a September 2026 mainnet release and requested review by **18 September 2026**. This report is the consolidated review of the requested boundary: **22 of 25 paths / 164 of 171 hunks / +713/−181 lines / 510 final-side changed nSLOC**.

---

## 1. Context and Scope

### 1.1 Source identity

| Boundary | Source tree | Audit commit |
|---|---|---|
| Chain Defenders remediation base | `417fe3b995f3dec84fd611fcc2f5c3ebd62d5c7a` | `b5265f311abc524683561b79792eab2900823fa9` |
| **Final production candidate** | **`84476d9086e89580c58918b203f4142ecd839765`** | **`2725216e0407a0ef4599e359a04094ae5f322624`** |

### 1.2 In-scope review areas

Oracle and JPY/USD validation, three price paths (normal, redemption, urgent), recovery/resume and freeze episodes, proxy source replacement, wstETH redemption and urgent pricing composition, failed-branch redemption accounting, CollateralVault full-backing checks, one-shot reserved-risk finalization, `MIN_DEBT = 100_000e18` boundaries, and the active CollateralYieldZapper referral behavior. Reuters source: **12 Solidity production paths across oracle, vault, redemption, and finalization surfaces**.

### 1.3 Explicit exclusions

Deployment scripts, deployment execution, frontend/backend/bots/subgraph code, production on-chain readbacks, Safe operations, and alert delivery are outside this Solidity review. They are flagged only where they gate launch readiness (Section 6).

---

## 2. Executive Summary

The additional-remediation candidate is a **materially improved, well-engineered set of changes** suitable for mainnet pending resolution of **one actionable code defect** and **completion of the launch evidence checklist**.

**Key strengths**
- **Recoverable (non-terminal) oracle shutdown** is the most significant architectural improvement. Transient single-source failures no longer irreversibly kill a branch; `PriceFeedProxy.resumeFromOracleFailure()` provides a validated, owner-gated recovery path.
- **Three-path price architecture** cleanly separates normal, redemption, and urgent redemption quotations, preventing cache contamination and cross-path arbitrage.
- **Vault solvency gating** (`_requireConfirmedFullyBacked`) fails closed — unavailable Strategy live valuations contribute zero rather than cached value — correctly prioritizing integrity over availability.
- **JPY provenance gating** (30-hour normal-redemption age gate) meaningfully bounds weekend/holiday FX staleness without introducing an on-chain market-hours calendar.
- **Reserved-branch risk finalization** is a one-shot, permissioned activation gate with correct state-machine guards and parameter invariants.
- The **companion package** (SCOPE, tests, build reproducibility, hunk provenance, risk register) is thorough and reproducible (1,789 tests pass, 0 fail).

**Primary concerns requiring action before launch**

| # | Finding | Severity | Action |
|---|---|---|---|
| **H-01** | Urgent redemption discards oracle-failure boolean; miswire enables stale-price wind-down settlement | **High** | Apply 2-line defensive fix **or** produce deployment evidence for every PriceFeed binding |
| **M-01** | Stale-but-newer JPY rounding can re-anchor an in-progress freeze episode | **Medium** | Apply targeted freeze-preserving fix **or** explicit project-risk retention with loss budget |
| **M-02** | Vault backing guard halts all user flows during a Strategy outage | **Medium** | Demonstrate funded backstop + end-to-end incident drill |

**Secondary items:** resume path does not independently validate JPY provenance freshness (see L-02); `MIN_DEBT` single constant conflates three policy axes (L-07); emergency source confirmation bypasses all three deviation guards by design (L-05).

**Recommendation:** Approve for mainnet **conditional on** the launch-blocking evidence below.

---

## 3. Findings

### 3.1 Findings with resolution required before launch

#### H-01 — Urgent redemption discards the oracle-failure boolean (High)

**File:** `TroveManager.sol` (urgent redemption path)

```solidity
(uint256 price,) = priceFeed.fetchUrgentRedemptionPrice();  // failure bool discarded
```

The failure boolean returned by `fetchUrgentRedemptionPrice()` is discarded. Under **correct wiring** (the registered source is the reviewed `PriceFeedProxy`), this is safe: the proxy reverts with `UrgentRedemptionPriceUnavailable` on failure rather than returning a failure flag. Under **miswiring** (a direct source registered as `AddressesRegistry.priceFeed`), the feed returns `(lastGoodPrice, true)`, and TroveManager silently settles wind-down redemptions at a potentially stale price.

A direct-source miswire is **permanent**: `AddressesRegistry.setAddresses()` renounces registry ownership after wiring, so it cannot be repaired by later Proxy source rotation.

**Recommended fix (two lines, safe-by-construction):**

```solidity
(uint256 price, bool urgentFailure) = priceFeed.fetchUrgentRedemptionPrice();
if (urgentFailure || price == 0) revert UrgentRedemptionPriceUnavailable();
```

**Required:** Engineering applies the fix, **or** produces deployment evidence that every `AddressesRegistry.priceFeed` is the reviewed `PriceFeedProxy` (runtime codehash readback, D-1/D-2). Direct-source registration is unacceptable for production.

---

#### M-01 — Stale-but-newer JPY rounds can re-anchor an in-progress freeze episode (Medium)

**File:** `JpyUsdRateProvider.sol` (fresh/successful-round adoption path)

`fetchJpyUsdRate()` accepts any otherwise-valid Chainlink round whose `updatedAt` is newer than the cached timestamp, even when that round is already older than the staleness threshold. On adoption it updates the cached rate/timestamp and clears the freeze onset (`jpyFrozenSince = 0`). The newly released Japan market-hours analysis explicitly confirms that a *same-value heartbeat* can refresh `updatedAt` without fresh price discovery.

**Impact**
The normal-to-urgent window is designed to be `[30h, 96h)` from the original fresh observation. If the feed surfaces **progressively newer but already-stale rounds before each episode expires**, each adopted round re-anchors the freeze onset and can extend the window beyond 96 hours. Adversarial control over Chainlink publication is not required; a governance-halved second feed or the re-anchoring calibration assumption are the realistic drivers. This is not attacker-controllable FX direction, but it does defeat the claimed time bound.

**Note on the earlier "delete one line" suggestion:** the `jpyFrozenSince = 0` line sits in the **fresh-round** path and is required for correct recovery. The defect is the stale-but-newer path updating `lastGoodJpyUpdatedAt` (and thus the freeze anchor) without verifying freshness. The fix must **preserve an already-active freeze episode** while still allowing a genuinely fresh round to start a new healthy episode.

```solidity
// Preserve an already-active freeze episode when adopting a stale-but-newer round.
// Only a genuinely fresh round may clear the freeze.
// (jpyFrozenSince = 0;  // ← move this so it fires ONLY on a validated fresh round)
```

**Required:** Product/Protocol Risk owner makes an explicit retain-or-remediate decision including the **repeated stale-but-newer sequence** (not just the single-round case), with loss budget and an independent FX monitoring plan. If retained, a named re-evaluation owner is required.

---

#### M-02 — Vault backing check can halt all user flows during a Strategy outage (Medium)

**File:** `CollateralVault._requireConfirmedFullyBacked()`

`_requireConfirmedFullyBacked()` counts **unavailable** Strategy live valuations as **zero** (never cached). If raw underlying < liabilities and any Strategy is unavailable, `redeem()`, `redeemWithPermit()`, and `claim()` all revert.

**Assessment:** This is the **correct trade-off**. Accepting cached values would enable first-mover extraction against stale data. Do **not** weaken this check. The residual exposure is an availability risk bounded by monitoring and an operational repair path.

**Required:**
- **Operations** demonstrate a funded repair/backstop: named holders of recovery funds, maximum response time, and a completed end-to-end drill with a human at the end of the alert chain.
- **Monitoring** for `liveAvailable == false`, backing deficit, queued-claim age, and blocked user paths.

---

### 3.2 Findings retained with formal disposition

#### L-01 — Semantic forwarding cycle passes the PriceFeedProxy marker check (Low)

**File:** `PriceFeedProxy._isPriceFeedProxy()`

`_isPriceFeedProxy()` is a one-level type marker (does the candidate expose a `source()` getter returning 32 bytes?). A `ForwardingAdapter` without that getter, that forwards all three price calls back to the existing healthy proxy, passes the marker check and the smoke tests, then produces a Proxy → Adapter → Proxy forwarding cycle after acceptance. A fresh 12h proposal can recover.

**Residual:** requires the Proxy **owner** to propose and confirm the adapter. Retained under the 12h lifecycle and human review.

**Required:** Guardian independently challenges severity; Product/Protocol Risk makes a formal treatment decision. Operational mitigation: recursively audit every source dependency, implementation, mutable router, and administrator before any source change.

---

#### L-02 — Oracle recovery can trigger irreversible shutdown before Owner resume (Low)

**File:** `BorrowerOperations` / `PriceFeedProxy`

During `isOracleFailureShutdown = true`, once the oracle recovers a valid live price, `BorrowerOperations.shutdown()` is permissionless. If `TCR < SCR` at that moment, any caller can permanently shut down the branch before the Proxy owner calls `resumeFromOracleFailure()`.

**Assessment:** This is intentional Liquity design — a genuinely unsafe branch should shut down permissionlessly. Owner resume is an explicit human approval boundary for re-enabling risk-increasing operations, not a continuity/provenance proof.

**Residual:** resume validates three quote paths but does not enforce price-continuity/deviation bounds. Aged or invalid JPY provenance may pass `healthy=true` while withholding the redemption-cache update. Normal redemption may remain independently unavailable after resume.

**Required:** Operations monitor TCR in real time during pause with an emergency plan near SCR; Guardian verifies no failure-bearing price is used and risk-increasing operations remain latched.

---

#### L-03 — Fail-closed urgent redemption can delay exits during joint oracle/governance outage (Low)

**File:** `PriceFeedProxy.fetchUrgentRedemptionPrice()`

Urgent redemption has no cache and no direct-only fallback. Every required leg must succeed. A joint failure of the oracle source AND an unavailable owner/Safe can block source replacement, trove closure, progression to irreversible shutdown, and urgent redemption for an extended period. If Governance is available, a new source can be proposed/confirmed after 12h.

**Assessment:** stale/cache settlement transfers value at an invalid price; a timeout cannot manufacture a valid quote. The design correctly chooses price integrity over guaranteed exit availability.

---

#### L-04 — `max(direct, derived)` redemption reference can underpay redeemers (Low)

**File:** `DFWstETHPriceFeed`

Redemption/urgent pricing uses `max(stETH/USD_direct, ETH/USD × stETH/ETH)`. If the ETH/USD reference is stale-high, redeemers receive fewer wstETH than the true market rate. This is intentional — it prevents undervaluing collateral during a genuine stETH depeg and protects remaining borrowers.

**Deployment dependency:** `redemptionStEthEthOracle.stalenessThreshold` is a constructor parameter (not hardcoded) that **must equal 90,000 seconds (25h)**.

**Required:** deployment evidence readback (D-6); Guardian confirms the formula, polarity, staleness semantics, and failure behavior.

---

#### L-05 — Emergency source confirmation bypasses all three deviation guards (Low)

**File:** `PriceFeedProxy.confirmSourceEmergency()`

Normal `confirmSource()` checks three price-continuity deviation guards. `confirmSourceEmergency()` keeps the same 12h delay and validates three quote methods on the proposed source, but deliberately does not call the broken old source — bypassing all three deviation guards together. Aged-but-valid JPY provenance can be accepted while the redemption-cache update is withheld.

**Assessment:** a per-leg emergency bypass requires another state machine and audit surface. Retain the current recovery path under role-controlled execution.

---

#### L-06 — Zapper referral safety assumes canonical Lido contracts (Launch evidence)

**File:** `CollateralYieldZapper._submitStEth()`

`_submitStEth()` calls `stETH.submit(lidoReferral)` and credits the received balance delta. The conclusion that referral changes cannot redirect funds depends on deployed contracts having canonical Lido stETH/wstETH identity and `submit(address)` semantics. A look-alike contract satisfying only the getter/ABI is not sufficient.

**Required:** deployment evidence binding configured addresses, runtime hashes, immutable relation, and called semantics (D-7).

---

#### L-07 — MIN_DEBT 300,000 → 100,000 JPYdf without full use-site review (Low-Medium)

**File:** `Constants.sol`

`MIN_DEBT` applies to more than the entry floor:

| Use site | Effect of lower MIN_DEBT |
|---|---|
| Zombie threshold | Troves with 100k–300k debt are now zombies — liquidatable regardless of ICR |
| Max partial repayment | Lower floor; more repayment space near minimum |
| Open/adjust gate | More small troves → SortedTroves fragmentation → keeper gas pressure |

**Required:** Engineering audits every `MIN_DEBT` call site (BO 612, 814, 1501; TM 721); Economics confirms keeper gas assumptions at 100k JPYdf minimum; Risk confirms the zombie-state boundary change creates no mass-liquidation exposure at launch.

---

### 3.3 Informational / acknowledged items

- **I-01 (partial Strategy recovery does not renew cache timestamp)** — Acknowledged (Chain Defenders L-03: `Acknowledged`, not `Fixed`). Confirm PR #107 does not weaken this boundary.
- **I-02 (Strategy loss invisible to backing guard)** — Systemic exposure managed via approved exposure caps, backstop capacity, loss scenarios, monitoring, and production-topology evidence.
- **I-03 (dToken mintCap is not a hard branch debt ceiling)** — Known architecture boundary; a hard ceiling requires separate design/audit.
- **I-04 (contract size constraints)** — TroveManager 24,570 bytes (6-byte headroom) / BorrowerOperations 24,531 bytes (45-byte headroom). This constrains *how* a fix is made, never *whether* a finding is valid.
- **I-05 (two generic default price-feed behaviors are topology-dependent)** — Future-change constraint; re-audit before activating another Composite source relying on the default urgent getter, or adding a source with divergent redemption/urgent formulas.

---

## 4. Change-by-Change Verification

The following were independently verified against the final source tree:

| File | Change | Verified |
|---|---|---|
| `AddressesRegistry` | Reserved-branch `finalizeRiskParams` (one-shot, 6 params, atomic BO/TM sync, DToken/Vault identity, empty-state guards) | ✅ |
| `BorrowerOperations` | Recoverable `isOracleFailureShutdown` + `resumeFromOracleFailure`; risk-reducing ops allowed during pause; finalization gate on openTrove | ✅ |
| `TroveManager` | `syncRiskParams` (5 params, registry-only); oracle-aware liquidation/redemption paths; urgent path uses dedicated quote | ✅ |
| `StabilityPool` × 2 | `RiskParamsNotFinalized` gate on `provideToSP` | ✅ |
| `PriceFeedProxy` | 12h timelock; 30h JPY normal-redemption age gate; urgent path (no cache, hard revert on failure); recoverable pause; source marker + cache-on-fresh-provenance | ✅ |
| `DFWstETHPriceFeed` | Dual-oracle redemption reference; `PriceUse` enum; normal cache uncorrupted by redemption quotes | ✅ |
| `DFPriceFeedBase` / `JpyFreezeLib` | Recoverable JPY freeze; sources stay on primary so recovery observable | ✅ |
| `RedemptionHelper` | Per-branch redemption-price availability; excludes stale-price branches; `availableProportions==0` early return | ✅ |
| `CollateralVault` | `_requireConfirmedFullyBacked` on redeem/redeemWithPermit/claim; unavailable strategies contribute zero | ✅ |
| `Constants` | `MIN_DEBT` 300,000 → 100,000; semantic comment corrected | ✅ |
| `CollateralYieldZapper` | Lido referral (immutable manager, revert/Event); `submit(lidoReferral)` | ✅ |
| `CompositePriceFeed` / `MainnetPriceFeedBase` | Default urgent impl; recoverable vs terminal shutdown split; legacy wrapper retained | ✅ |
| `PriceFeedPlaceholder` | Urgent path + synthetic JPY provenance (keeps inert branches non-blocking) | ✅ |
| Interfaces (7) | Surface `syncRiskParams`, `resume`, `fetchUrgentRedemptionPrice`, finalization, `RiskParamsNotFinalized`; compile-time enforcement | ✅ |
| `SkyUsdcSUsdsYieldZapper` (archive) | Mechanical constructor propagation; not on active deployment path | ✅ |

**Architecture note on `_isPriceFeedProxy`:** the marker is a shallow direct-proxy screen confirmed in code. It does not traverse semantic forwarding or prove dependency-graph acyclicity (see L-01). This is a defense-in-depth improvement, not a substitute for timelock owner diligence.

---

## 5. Launch-Blocking Deployment Evidence

Confirm all items via on-chain readbacks before raising any `mintCap` above zero:

| # | Item | Closes |
|---|---|---|
| **D-1** | Every `AddressesRegistry.priceFeed` is the reviewed `PriceFeedProxy`; confirm runtime codehash | H-01 |
| **D-2** | Every `PriceFeedProxy.source` is the reviewed live source; confirm codehash + all three price paths | H-01 |
| **D-3** | Recursively reviewed source dependency graph (addresses, hashes, mutable routers, admins) | L-01 |
| **D-4** | `finalizeRiskParams` preflight: Vault liabilities = 0, queued claims = 0, Strategies reviewed, backing confirmed, exact 6 param values recorded | |
| **D-5** | Post-finalization readback: all 6 params match in `AddressesRegistry`, `BorrowerOperations`, `TroveManager` | |
| **D-6** | `DFWstETHPriceFeed.redemptionStEthEthOracle.stalenessThreshold` = 90,000 seconds | L-04 |
| **D-7** | Lido stETH/wstETH addresses confirmed canonical; `submit(address)` semantics verified | L-06 |
| **D-8** | Timelock: 43,200-second delay, complete role/event/pending-op history, separation from canary | |
| **D-9** | `mintCap` raised **last**, after all readbacks pass | |

---

## 6. Required Decisions Before Launch

| Decision | Owner | Closes |
|---|---|---|
| Apply the 2-line urgent-redemption fix OR produce deployment evidence for every PriceFeed binding | Engineering | H-01 |
| Retain or remediate stale-but-newer JPY re-anchoring (repeated sequence) with loss budget | Product / Protocol Risk | M-01 |
| Operational repair/backstop path + end-to-end incident drill | Operations | M-02 |
| Signed activation preflight + post-finalization readback ceremony | Deployment / Ops | |
| Independent severity and operational graph assessment of the forwarding-cycle boundary | Guardian | L-01 |
| MIN_DEBT use-site review and economic capacity sign-off | Engineering / Risk | L-07 |

---

## 7. Future Changes That Reopen Review

Re-audit before making to production:

- Activating the legacy StabilityPool or archived Sky Zapper excluded by the current SOW
- Activating another Composite source that relies on the default `fetchUrgentRedemptionPrice()` getter (I-05)
- Adding a source whose normal, redemption, and urgent formulas diverge (I-05)
- Adding a wrapper collateral without an on-chain market/depeg leg
- Activating an asynchronous Strategy without approved pending-principal, withdrawal, pricing, and incident behavior
- Changing JPY/USD age/freeze policy, wstETH polarity or staleness thresholds, emergency confirmation, or branch debt-cap architecture
- Any production Solidity change after source tree `84476d9086e89580c58918b203f4142ecd839765`

---

## 8. Conclusion

The additional-remediation candidate significantly hardens the protocol: transient oracle failure no longer terminally escalates, three distinct price paths prevent arbitrage and cache contamination, vault solvency fails closed, and reserved branches activate through a one-shot, invariants-checked finalization gate. The companion evidence package is complete, reproducible, and honestly tracks residual risk.

The code is **conditionally approved for mainnet** pending:
1. **H-01** — the two-line urgent-redemption fix or definitive PriceFeed binding evidence (High, actionable now),
2. **M-01** — an explicit product-risk decision on the repeated stale-but-newer sequence (Medium),
3. **M-02** — a demonstrated funded repair/backstop path (Medium),
4. Completion of the Section 5 deployment evidence checklist.

No other issues in this review are launch-blocking. Residual retained items are documented, role-assigned, and gated by identified operational controls and named owners.
