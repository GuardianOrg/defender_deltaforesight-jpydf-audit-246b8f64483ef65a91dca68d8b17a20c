# Collateral Parameter Derivation Rationale (Historical Analysis Record / Rationale / Raw Data / Rejected Candidates)

> ⚠️ **This document is a "record of the analysis process at a past point in time (as of the derivation work through January 2026)."**
> The **source of truth for the finalized values / latest derivation formulas of the collateral parameters is [Parameters.md](../../Parameters.md)** (the Single Source of Truth for Day-1 deployment input values). This document archives the analysis process at that time (variable models, raw volatility data, rejected alternatives, per-collateral adoption/rejection decisions), and **the figures in this document are "values as of the analysis time," some of which have since been superseded by finalized values** (in particular, among the stable assets, sUSDS has been updated by the introduction of the Day-1 immutable policy floor; see §0). When citing values, always treat Parameters.md as canonical.

> 📘 **Positioning**
> An archive that consolidates and replaces the parameter-related pages of the old Notion (parent "Collateral Assets and Parameter Configuration" / children "Liquidation LTV", "Parameter Analysis Memo" / grandchildren "JGB Token Branch LLTV Configuration", "Minimum Interest Rate Discussion Memo_20260610"). The Notion side has been retired, and from now on the reference for analysis records is this page.

> 📘 **Meta information**
> - **Type**: analysis record (archive). Not the source of truth for finalized values.
> - **Source-of-truth relationship**: finalized values / latest derivation formulas = [Parameters.md](../../Parameters.md) / analysis history, rejected candidates, raw data = this page. **In case of conflict, Parameters.md is canonical.**
> - **Derivation spreadsheet**: `LLTV_DeltaForesight_20260111` (internal Google Sheets). ⚠️ The general-formula rows for the stable assets in that sheet have been replaced by the finalized formulas in §E and are stale; the only rows that still match are WBTC / WETH.
> - **Upstream constraint**: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)

---

## §0. Differences from Current Finalized Values (Important)

After this document was written, the stable-asset branches were once approached with a uniform tightening via a **Day-1 immutable risk policy floor**, but the final policy separated plain stable from structured / RWA stable. For USDC / USDT, which are structurally simple plain stables, the stress-implied values were restored as the current finalized values. sUSDS, which carries USDS depeg plus ERC-4626 share / PSM / withdrawal / oracle composition risk, and dUSD, which is an RWA-style branch, apply a structural-risk MCR 120% floor. The derivation formulas were reorganized as follows:

`USDC / USDT LLTV = (1 − max DD)(1 − FX)`

`sUSDS / dUSD LLTV = min((1 − max DD)(1 − FX), 1 / 1.20)`

| Collateral | Value at this document's analysis time (LLTV / MCR / CCR) | **Current finalized value in Parameters.md** | Reason for the difference |
| --- | --- | --- | --- |
| USDC (Br1) | 89.62% / 111.58% / 124.50% | **89.62% / 111.58% / 124.50%** | adopted stress-implied value as a plain stable |
| USDT (Br2) | 89.62% / 111.58% / 124.50% | **89.62% / 111.58% / 124.50%** | = USDC |
| sUSDS (Br3) | 87.18% / 114.71% / 131.58% | **83.33% / 120.00% / 137.65%** | policy floor MCR 120% (USDS depeg + ERC-4626/PSM/withdrawal/oracle compound risk) |
| WETH (Br0) | 83.91% / 119.18% / 132.61% | 83.91% / 119.18% / 132.61% (unchanged) | — |
| XAUT (Br4) | 77.52% / 129.00% / 152.93% | 77.52% / 129.00% / 152.93% (unchanged) | — |
| dBTC (Br5) | 83.65% / 119.55% / 130.82% | 83.65% / 119.55% / 130.82% (unchanged) | — |
| dUSD (Br6, USDe provisional) | 86.30% / 115.87% / 134.26% | **83.33% / 120.00% / 137.65%** | policy floor MCR 120% (RWA structured stable; CCR recalculated on the same 11.79% max-DD basis as sUSDS) |
| dJPY (Br7) | 94.97% / 105.30% / 107.30% | 94.97% / 105.30% / 107.30% (unchanged) | — |

> The USDC / USDT values that appear in §D / §E below match the current finalized values. The sUSDS / dUSD values are **stress-implied / USDe-proxy values as of the analysis time**, not the current finalized values. For the sUSDS / dUSD policy floor and the rationale for treating their MCR as a structured-risk premium, treat [Parameters.md §3-1 / §8-3](../../Parameters.md) as canonical.

---

## §A. Design Philosophy (Common Principles)

### §A-1. Problem Statement

The LLTV / MCR configuration problem is defined as "**finding a value at which liquidation is performed safely (the protocol does not incur Bad Debt) within a range that does not impair capital efficiency**."

- A liquidator executes a liquidation when profit is expected, but in situations where the expected profit is low — as below — it is not executed, and the protocol risks incurring Bad Debt.
  - The collateral asset price falls at an extremely fast rate.
  - The LTV has breached the liquidation threshold but the oracle is not updated.
  - The post-liquidation sale route is unprofitable due to slippage and gas-cost spikes.
- Approach to LLTV configuration: find the line at which, from the profit obtained as the liquidation penalty, after subtracting gas costs, slippage, etc., the remaining profit still keeps the liquidation executable even if the collateral asset price falls against the Loan Asset (JPY) within a specific period.

### §A-2. The Absolute Condition of Producing No Bad Debt

Here, **Bad Debt = a state in which, even after liquidation, the collateral cannot fully recover the debt (collateral value < debt)**. Not producing this is the absolute condition of the design.

Liquidation does not necessarily settle immediately; it can be delayed or fail to occur due to (a) a sharp price drop, (b) an unupdated oracle, or (c) becoming unprofitable from slippage and gas spikes. Therefore, MCR is set at a level such that a position exactly at the liquidation threshold (collateral value = MCR × debt at the oracle price) **still maintains over-collateralization (collateral value ≥ debt) even after eroding under composite stress over the assumed time to liquidation completion (assumed to be 2h as a baseline, taking the oracle update interval into account)**.

The erosion cannot be captured by a single price drop alone; it takes effect as the product of **price movement, depeg, DEX slippage (under stress, several times the normal level due to liquidity drying up), and FX in the yen-appreciation direction** (a product of survival ratios).

### §A-3. Premise of the Liquidation Method (ICR > 105% floor)

- Liquity v2's liquidation method prioritizes the Stability Pool first, and if it is empty, JIT liquidation. The liquidation executor is paid 0.5% of the collateral (up to a cap of 1,000 units) as collateral compensation (`COLL_GAS_COMPENSATION`; for the implemented value see [Parameters.md §3-7](../../Parameters.md)).
- If ICR > 105%, liquidation is reliably executed in both SP and JIT, so the design conservatively aims for an MCR / LLTV above this line.
- The USD stable assets do not include this 105% in their safety condition and aim for the very edge of over-collateralization, but as a result the MCR of every branch exceeds this line and stays within the range where the liquidation mechanism functions (the minimum is the JPY branch at 105.30%).

### §A-4. Two Formula Families by Collateral Type (+ a JGB special form)

| Family | Targets | Level maintained after stress | Finalized formula (as of analysis time) |
| --- | --- | --- | --- |
| High-volatility | WETH / WBTC / XAUT | collateral ≥ debt + liquidation penalty (+ slippage) | `MCR = (1 + SP) / [(1 − Price)(1 − Depeg)(1 − Slip × Mult)(1 − FX)]` |
| USD stable | USDC / USDT / sUSDS / dUSD | collateral ≥ debt (maintain over-collateralization) | USDC / USDT: `LLTV = (1 − max DD)(1 − FX)`; sUSDS / dUSD: `min((1 − max DD)(1 − FX), 1 / 1.20)` (SP and slippage not included) |
| JGB | dJPY | collateral ≥ debt + liquidation penalty | `MCR = (1 + SP) / (1 − Price)` (§E-9) |

- The **high-volatility family** involves DEX sale, so the formula includes the liquidation penalty (SP = 5%) and slippage, and satisfies a level at which no Bad Debt arises even if a 1-in-1000-grade price plunge over 2h and yen appreciation occur simultaneously.
- The **USD stable family** does not include the liquidation penalty or slippage in the buffer, and raises LLTV high enough to maintain over-collateralization even if a historically-largest-grade depeg occurs (reasons: low volatility in normal times / liquidation settles mainly through SP spot absorption and does not bear DEX sale slippage). In the current Day-1, USDC / USDT adopt this stress-implied value, while sUSDS (yield-stable) and dUSD (RWA) apply the MCR 120% policy floor as a non-price / exit / oracle structural-risk premium (§0).
- The three families can be unified into a single formula, with the high-volatility family as the root; the USD stable family (`SP = Price = Slip×Mult = 0`) and the JGB family (`Depeg = Slip×Mult = FX = 0`) are both special forms of it.

---

## §B. Stress Variables and Data Sources

### §B-1. Definition of Stress Variables

| Variable | Meaning |
| --- | --- |
| `Oracle_Update_Frequency` | Oracle update frequency (daily or on threshold exceedance). Delay assumed in 3 patterns: 30m / 1h / 2h |
| `Liquidation_Penalty_Percent` | Assumed 5%, same as Liquity v2. The lower it is, the easier it is for borrowers to apply leverage, but safety decreases (a tradeoff between capital efficiency and security) |
| `Stress_Price_Shock_D_Percent` | Assumed drop within a specific period for a constantly USD-denominated fluctuating token such as WBTC / WETH |
| `Stress_Depeg_Shock_D_Percent` | Assumed drop of a token that is normally pegged but diverges on a specific event, such as USDC |
| `Stress_FX_Shock_USDJPY_Percent` | Assumed move of JPY/USD in the yen-appreciation / dollar-depreciation direction within a specific period |
| `Stress_Slippage_S_Percent` | Assumed slippage when selling collateral on an external DEX under stress. Normal-time average slippage obtained via a dex aggregator (ParaSwap) API |
| `Stress_Liquidity_Stress_Multiplier` | Multiplier derived from the decrease in major DEX TVL under stress (industry convention 2–3×) |

- Derived values: `MCR_Proposed` (assumed collateral ratio) → `LTVmax_Proposed = 1 / MCR_Proposed`.
- The slippage placeholder assumes "handling a $5m liquidation in normal times" and adopts the Aave level at the time of the UST collapse — a fairly conservative value. When computing `MCR_Proposed`, `Stress_Slippage` is multiplied by `Stress_Liquidity_Stress_Multiplier`.

### §B-2. Data Source List (provenance)

| Target | Data source | Granularity / period / count / notes |
| --- | --- | --- |
| JPY/USD | Twelve Data API | 5-minute / 2021-01-18–2026-01-16 (about 5 years) / **360,781 records** / **270 outliers excluded** |
| WBTC (BTC/USD) | Binance API | 5-minute / 2017-08– |
| WBTC/BTC (depeg) | Binance API | 5-minute / 2020-08– |
| WETH (ETH/USD) | Binance API | 5-minute / 2017-08– (custody depeg risk not considered) |
| USDC (USD-denominated) | — | 5-minute. Distribution is non-normal (with jumps), so depeg adopts max DD |
| USDT (reference / rejected candidate) | Binance API | TUSDUSDT 5-minute (2h max DD 13.6%). Rejected as a crude source (§D-4) |
| USDS | Binance API | DAI/USDT 5-minute / 2020-08-11– (USDS has a short history, substituted with DAI-era data) |
| USDe | Curve | 5-minute interval price / 2024-01– (one-off single-5-minute outliers excluded) |
| XAU/USD | Twelve Data API | 5-minute / 2020-09-01 00:00 UTC–2026-05-13 00:55 UTC |
| XAUt/XAU (depeg) | Bitfinex API (XAUt/USD) reconciled against XAU/USD | 5-minute / 2020-09-01–2026-05-13 |
| JGB | Ministry of Finance "JGB Interest Rate Information" | 52 years. Since 3M data is hard to obtain, **1Y JGB is used as a substitute for 3M** |

---

## §C. Volatility Raw Data (Full Distributions)

### §C-1. JPY/USD (Twelve Data, 5-minute, 2021-01-18–2026-01-16, 360,781 records, 270 outliers excluded)

| Window | Max drop rate | 99.9th | 99th |
| --- | --- | --- | --- |
| 30 min | 1.79% | 0.51% | 0.23% |
| 1 hour | 2.02% | 0.78% | 0.36% |
| 2 hours | 2.29% | 1.17% | 0.52% |

- Finalized value used for the FX adjustment of each collateral = **JPY/USD 2h 99.9th = 1.17%**.

### §C-2. WBTC

**BTC/USD (Binance 2017-08– 5-minute)**

| Window | Max drop rate | 99.9th | 99th | 95th |
| --- | --- | --- | --- | --- |
| 30 min | 17.38% | 3.78% | 1.66% | 0.78% |
| 1 hour | 22.29% | 5.53% | 2.53% | 1.22% |
| 2 hours | 23.62% | 7.54% | 3.66% | 1.84% |

**WBTC/BTC (depeg, 2020-08–)**

| Window | Max drop rate | 99.9th | 99th |
| --- | --- | --- | --- |
| 30 min | 2.49% | 0.32% | 0.14% |
| 1 hour | 2.91% | 0.43% | 0.17% |
| 2 hours | 2.91% | 0.53% | 0.20% |

### §C-3. WETH (ETH/USD, Binance 5-minute)

| Window | Max drop rate | 99.9th | 99th | 95th |
| --- | --- | --- | --- | --- |
| 30 min | 24.21% | 4.41% | 2.00% | 0.99% |
| 1 hour | 29.38% | 6.55% | 3.05% | 1.53% |
| 2 hours | 31.17% | 9.07% | 4.44% | 2.29% |

### §C-4. USDC

| Window | Max drop rate | 99.9th | 99th | 95th | CVaR 99.9th |
| --- | --- | --- | --- | --- | --- |
| 30 min | 9.31% | 0.34% | 0.14% | 0.05% | 0.66% |
| 1 hour | 9.32% | 0.51% | 0.19% | 0.08% | 1.04% |
| 2 hours | 9.32% | 0.77% | 0.26% | 0.11% | 1.60% |

- Since the USD-denominated price distribution of USD stables is non-normal (it has jumps), depeg adopts the **2h max DD 9.32% (SVB incident)**.

### §C-5. XAU/USD · XAUt/XAU (Gold)

**XAU/USD (Twelve Data 2020-09-01–2026-05-13 5-minute)**

| Window | MAX DD | 99.9th | 99th |
| --- | --- | --- | --- |
| 30 min | 7.27% | 1.11% | 0.49% |
| 1 hour | 7.27% | 1.60% | 0.71% |
| 2 hours | 7.62% | 2.19% | 1.04% |

**XAUt/XAU (Bitfinex XAUt/USD reconciled against XAU/USD)**

| Window | MAX DD | 99.9th | 99th |
| --- | --- | --- | --- |
| 30 min | 7.616% | 1.764% | 1.022% |
| 1 hour | 7.616% | 2.015% | 1.274% |
| 2 hours | 7.616% | 2.355% | 1.575% |

- The XAUt/XAU max DD occurred at 2025-10-10 21:40 UTC, while the XAU/USD max DD was at 2026-01-29 14:25 UTC; **the figures are close but are separate events**. Since drawdowns near the max DD have occurred multiple times, both price movement and depeg **adopt the max DD**.

### §C-6. JGB (Ministry of Finance JGB Interest Rate Information · 52 years · 1Y as a substitute for 3M)

- For the 2h window, **p99.9 = 0.248% / max = 0.279% → adopted 0.28%**.
- Source: [Ministry of Finance JGB Interest Rate Information CSV](https://www.mof.go.jp/jgbs/reference/interest_rate/data/jgbcm_all.csv)

---

## §D. LLTV / MCR — Per-Collateral Adoption Rationale and Rejected Candidates (as of analysis time)

> ⚠️ Among the stable assets, the "adopted" values for USDC / USDT match the current finalized values. The "adopted" values for sUSDS / dUSD are **stress-implied / USDe-proxy values as of the analysis time**; the current finalized values are after applying the §0 policy floor (both LLTV 83.33% / MCR 120.00%). The high-volatility and JGB families match the current values.

### §D-1. WBTC (→ provisional value for Branch 5 dBTC)

- LLTV is in the 83.87–89.35% range. The variables that matter are "which window to use" and "what to put in `Stress_FX_Shock`."
- ~~**Candidate A (ultra-conservative, rejected)**~~: both JPY/USD and BTC/USD use the 2h **max drop rate**. **LLTV 69.09%**. Rejected because, with Aave at 78%, its competitive capital efficiency is low.
- **Candidate B (adopted)**: both JPY/USD and BTC/USD use the **2h 99.9th**. The line at which no Bad Debt arises even with a 1-in-1000-grade simultaneous occurrence under a 2h liquidation delay. **LLTV 83.65%**. Close to Morpho/Euler 86% · Compound 85%.
- ~~**Candidate C (slightly aggressive, rejected)**~~: 1h 99.9th. **LLTV 85.47%**. The more conservative Candidate B is adopted.

### §D-2. WETH (Branch 0 · adopted 83.91%)

- The approach is the same as WBTC but does not consider custody depeg risk. Adopted = the same "2h 99.9th" method as WBTC Candidate B. **LLTV 83.91%** (matches the current finalized value).

### §D-3. USDC (Branch 1 · current 89.62%)

- ~~**Candidate A (rejected)**~~: assumes SVB and uses max DD. **LLTV 85.01%**. Rejected because capital efficiency is poor.
- ~~**Candidate B (rejected)**~~: 99.9th, prioritizing capital efficiency. **LLTV 93.03%**. Rejected because it ignores JPY/USD movement.
- ~~**Candidate C (rejected)**~~: CVaR of 2h 99.9th. **LLTV 92.24%**. Rejected for the same reason.
- **Candidate D (adopted as of analysis time)**: adopts the e-mode-derived `1 − LLTV > max divergence` and adjusts for FX. `LLTV = (1 − 0.0932)(1 − 0.0117) = 89.62%`.
- ~~**Candidate E (rejected)**~~: max drop rate for FX as well. **LLTV 88.60%**. Rejected as excessively conservative.
- **Current finalized value**: as a plain stable, the above stress-implied value is adopted, giving **LLTV 89.62% / MCR 111.58% / CCR 124.50%** (§0).

### §D-4. USDT (Branch 2 · current 89.62%)

- **Candidate A (adopted)**: same value as USDC. Over 7 years have passed since USDT's idiosyncratic depeg, and during the SVB crisis USDT had positives such as a premium. As partnership talks progress, setting it below USDC would give a poor impression.
- ~~**Candidate B (rejected)**~~: substitutes Binance TUSDUSDT 2h max DD 13.6%. **LLTV 85.389%**. Rejected as a forced computation from a crude source.
- **Current finalized value**: same as USDC, as a plain stable, **89.62% / 111.58% / 124.50%** (§0).

### §D-5. USDS / sUSDS (Branch 3 · analysis time 87.18% -> current 83.33%)

- Since USDS has a short history, DAI-era data (Binance DAI/USDT 2020-08-11–) is referenced. 2h max drop rate **11.79%**.
- As of analysis time: `LLTV = (1 − 0.1179)(1 − 0.0117) = 0.8821 × 0.9883 = 87.18%`.
- ⚠️ **Current finalized value**: since sUSDS, in addition to USDS depeg, carries ERC-4626 share / PSM / withdrawal / oracle composition risk, the Day-1 immutable policy floor (MCR 120%) is applied, giving **LLTV 83.33% / MCR 120.00% / CCR 137.65%** (§0, [Parameters.md §8-3](../../Parameters.md)).
- **Relationship to WETH / dBTC**: sUSDS's MCR 120.00% being slightly higher than WETH 119.18% / dBTC 119.55% is not in price-volatility order but an exception as a non-price / exit / oracle structural-risk premium. dUSDS is Day-1 cap-0 dormant, so it does not affect borrowable capacity, and before Sky activation / cap increase, the route / oracle / liquidity / withdrawal evidence and whether MCR 120% can be maintained are re-approved.

### §D-6. GHO (analysis candidate · not deployed)

> ⚠️ GHO is **not included in the Day-1 collateral branches**. This item is an analysis record.

- No SVB depeg data (launched 2023-07). Its track record showing a higher LLTV than USDS is unnatural.
- **Candidate A**: same value as USDS's old stress-implied benchmark, **87.18%** (reinforced by the reliability of the Aave CDP).
- ~~**Candidate B (rejected)**~~: applying a safety factor. Arbitrary and not recommended.

### §D-7. USDe (old provisional value for Branch 6 dUSD · adopted 86.30% at analysis time, current 83.33%)

- Curve 5-minute interval price (2024-01–). 2h max drop rate 5.94%. Being delta-neutral rather than a CDP, it is hard to decide it should equal USDS.
- **Old provisional value (USDe proxy)**: apply a safety factor of **1.36** to the USDC formula (within the 2-year 95% confidence interval of the data-period comparison and extreme-value statistics GEV). `(1 − 0.0932 × 1.36)(1 − 0.0117) = 0.8732 × 0.9883 = 86.30%`.
- ⚠️ The old Notion child "Liquidation LTV" recorded "86.03%", but this was a transposition (typo); the formula yields **86.30%** (USDe-proxy value).
- ⚠️ **Current finalized value**: Branch 6 (dUSD) does not adopt the USDe-proxy provisional value (86.30% / MCR 115.87% / CCR 134.26%). It is treated like sUSDS as a structured / RWA stable and applies the Day-1 immutable policy floor (MCR 120%), giving **LLTV 83.33% / MCR 120.00% / CCR 137.65%**. The CCR is calculated on the same DAI-era 2h max-DD 11.79% basis as sUSDS. When the underlying asset (BUIDL / USYC / USDY assumed) is finalized, the §8-1 gate rechecks whether the MCR 120% floor remains appropriate for that asset (§0, [Parameters.md §8-3](../../Parameters.md)).

### §D-8. XAUT / Gold (Branch 4 · adopted 77.52%)

- Inputs (§C-5): Price 7.62% (XAU/USD 2h max DD) / Depeg 7.616% (XAUt/XAU 2h max DD) / Slippage 0.35% ($500k swap) × Multiplier 10 / FX 1.17% / SP 5%.
- `MCR = 1.05 / [(1 − 0.0762)(1 − 0.07616)(1 − 0.0035 × 10)(1 − 0.0117)] = 129.00%`, `LLTV = 77.52%` (matches the current value).
- **Note on stress inputs**: another source records depeg 10.53% / slippage 4.52% / 99.9th 2.403%, but the finalized formula that derives MCR 129.00% uses depeg 7.616% / slippage 0.35%×10 / price max DD 7.62%. Because slippage is large, the premise is to keep mintCap low ([Parameters.md §8-4](../../Parameters.md) gate).

### §D-9. Distinction Between dJPY (JGB Branch · adopted 94.97%) and JPYC (100%)

> ⚠️ The old Notion recommendation summary said "JPYC: 100%", but **Day-1 Branch 7 (dJPY) is a JGB-family design with JGB-token collateral, at LLTV 94.97% / MCR 105.30%** (§E-9 · matches the current value). The "100%" is a theoretical value premised on JPYC as collateral with a hardcoded oracle of 1 yen, not a deployment value.

- **JPYC (theoretical analysis)**: 100% premised on a hardcoded oracle of 1 yen (price fixed). Concerns = the possibility of a super-SVB depeg from a surge in the yield of the backing JGBs, and the asset-management risk of JPYC's backing assets at the company. Requires re-examination upon a future oracle change.
- **JGB token (Branch 7 finalized design) = see §E-9.**

### §D-10. Recommended LLTV Summary (as of analysis time. The current finalized values are canonical via §0 / Parameters.md)

| Collateral | LLTV as of analysis time | Derivation key point |
| --- | --- | --- |
| WETH | 83.91% | both ETH/USD and JPY/USD at 2h 99.9th (matches current) |
| WBTC | 83.65% | both BTC/USD and JPY/USD at 2h 99.9th (matches current) |
| USDC | 89.62% | `(1 − max DD 9.32%)(1 − FX 1.17%)`. plain stable stress-implied value |
| USDT | 89.62% | same value as USDC. plain stable stress-implied value |
| USDS | 87.18% ⚠️->current 83.33% | DAI-era 2h max DD 11.79%. current is policy floor MCR 120% |
| GHO | 87.18% | same value as the old USDS benchmark due to insufficient data (**not deployed**) |
| USDe | 86.30% ⚠️->current dUSD 83.33% | safety factor 1.36 applied to the USDC formula (old USDe-proxy value). Branch 6 (dUSD) current uses the USDS basis + MCR 120% floor (§D-7) |
| XAUT | 77.52% | §D-8 (high-volatility family · Gold, matches current) |
| dJPY (JGB) | 94.97% | §E-9 (JGB family · MCR 105.30%, matches current) |
| JPYC | 100% | theoretical value premised on a hardcoded oracle of 1 yen (**not the dJPY deployment value**) |

---

## §E. CCR / SCR / BCR / Liquidation Penalty — Adoption Rationale

> The finalized values are canonical in [Parameters.md §2-A / §3](../../Parameters.md). This section is the decision rationale, peer comparison, and rejected analysis (among the stable assets, the sUSDS / dUSD CCR differs in the current version as per §0).

### §E-1. CCR (Critical Collateral Ratio)

- **Role**: when TCR falls below CCR, new borrowing and collateral withdrawal are prohibited. A "breakwater" for the case where liquidation does not work as intended and TCR keeps falling.
- **Design formula**: `CCR = MCR / [(1 − Price)(1 − Depeg)(1 − FX)]`. The design goal is "when TCR_before = CCR, even after the worst stress, TCR_after only falls to MCR."
- Stress inputs and results (USDC / USDT match the current value. sUSDS / dUSD differ in the current version as per §0):

  | Collateral | MCR | collateral/USD DD 2h (Price) | depeg DD 2h (Depeg) | JPY/USD DD 2h 99.9th | CCR |
  | --- | --- | --- | --- | --- | --- |
  | WBTC | 119.55% | 7.54% (BTC 2h 99.9th) | — | 1.17% | 130.82% |
  | WETH | 119.18% | 9.07% (ETH 2h 99.9th) | — | 1.17% | 132.61% |
  | USDC | 111.58% | — | 9.32% (max DD) | 1.17% | 124.50% |
  | USDT | 111.58% | — | 9.32% (=USDC) | 1.17% | 124.50% |
  | sUSDS ⚠️ | 114.71%->current 120.00% | — | 11.79% (USDS max DD) | 1.17% | 131.58%->current 137.65% |
  | dUSD (dUSD/TBD) ⚠️ | 115.87%->current 120.00% | — | 11.79% (USDS basis, same as sUSDS; old USDe-proxy used Price 12.6752%) | 1.17% | 134.26%->current 137.65% |
  | Gold (XAUT) | 129.00% | 7.62% | 7.616% | 1.17% | 152.93% |
  | JGB token | 105.30% | — | — | — | 107.30% (separate logic. §E-9) |

- **Policy**: since MCR is set conservatively, CCR need not be made excessively conservative. AsymmetryFi uses `CCR = MCR + 10%` for stables.

### §E-2. SCR (Shutdown Collateral Ratio)

- **Role**: when TCR reaches SCR, the branch is shut down and emergency redemption begins (irreversible). The "last line of defense" for the case where TCR keeps falling even after SP/JIT, Redistribution, and CCR.
- **Adopted values**: USD stables 105% / WETH · WBTC · Gold 110%.
- **Design philosophy**: upstream uses `SCR = MCR`, but in an oligopolistic branch there is a risk of an erroneous shutdown from entering a large liquidation threshold → `SCR < MCR` is preferable. To follow `URGENT_REDEMPTION_BONUS = 2%`, it must be at least 102%. The 105% that includes the Liquidation Penalty 5% is set as the last-resort line for USD stables, and for WETH/WBTC a buffer is provided up to the full-Redistribution-bonus line of 110% (matching AsymmetryFi).

### §E-3. BCR (Batch CR buffer)

- **Adopted value**: unified 10% across all branches (only the JPY branch is 5%).
- **Rationale**: upstream, AsymmetryFi, and Nerite have a track record of a unified 10%. Under the premises (`MAX_ANNUAL_INTEREST_RATE 250%`, `MAX_ANNUAL_BATCH_MANAGEMENT_FEE 10%`, `UPFRONT_INTEREST_PERIOD = INTEREST_RATE_ADJ_COOLDOWN 7 days`), even in an extreme case, paying a total of **4.98%** for 7 days of management fees + one interest-rate-change upfront fee still protects up to two interest-rate changes.
- **JPY branch**: since a 250% interest rate is too extreme, **5% (≈4.22%)** assuming it withstands 2 cycles at 50%.

### §E-4. Liquidation Penalty (SP liquidation penalty)

- **Adopted value**: unified 5% across all branches (JPY is also 5%).
- **Rationale**: upstream and the fork group also have a track record of 5%. If the penalty differs across SPs, SP liquidity becomes skewed. Lowering or differentiating it has no clear benefit.
- ⚠️ **JPY branch (history)**: the old "Parameter Analysis Memo" stated that at MCR 102.04% "`(1 + 5%) ≤ MCR` could not be satisfied, so 2% was adopted", but the final design raised MCR to 105.30%, satisfying `1.05 ≤ 1.0530`, thereby **securing 5%** ([Parameters.md §8-2](../../Parameters.md)).

### §E-5. Redistribution Penalty

- **Adopted value**: unified 10% across all branches (only JPY is 5%).
- **Rationale**: upstream WETH 10% (wstETH/rETH 20%), AsymmetryFi has a track record of a unified 10% across all. Setting it too high raises the attack incentive to induce Redistribution. Since JPY has a permissioned liquidation design, there is no need to differentiate it from the Liquidation Penalty, so 5%.

### §E-6. Constraint Conditions (upstream Whitepaper / BOLD README)

```
LIQUIDATION_PENALTY_SP  ≤  LIQUIDATION_PENALTY_REDISTRIBUTION  ≤  10%  ≤  MCR
```

- The maximum collateral that can be seized in a liquidation is `(1 + penalty) × debt`. Unless `(1 + penalty) × debt ≤ MCR × debt` holds, the collateral surplus becomes negative.
- Making the penalty higher at Redistribution time is because TCR does not decrease through liquidation (upstream Whitepaper).
- Source: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)

### §E-7. Peer LLTV / MCR / CCR / SCR Designs (reference)

**Peer LLTV examples**

| Collateral | Aave | Morpho | Euler | Fluid | Compound |
| --- | --- | --- | --- | --- | --- |
| WETH | 83% | 86% | 85% | 92% | 88% |
| WBTC | 78% | 86% | 86% | 90% | 85% |
| USDC | 78% (e-mode 90–91%) | — | — | — | — |
| USDT | 78% (e-mode 90–91%) | — | — | — | — |
| USDS | 78% | — | 94% | — | — |
| USDe | 75% (e-mode 90–94%) | 91.5% | 92% | 94% | — |
| XAUt | 75% (isolated) | 77% | 75% | 80% | — |
| stETH | 81% | 86% | 83% | 88% | 86% |

**Peer MCR / CCR / SCR**

- **Liquity v2 upstream**: WETH `110 / 150 / 110`, wstETH · rETH `120 / 160 / 120`. `SCR = MCR`, CCR is MCR+40%.
- **AsymmetryFi**: stable example `110 / 120 / 105`, tBTC · WBTC `120 / 150 / 110`. `SCR < MCR`, for stables the CCR−MCR buffer is 10%.
- **Nerite**: WETH `110/150/110`, LST `130/160/115`, ARB · COMP `140/165/115`, tBTC `115/150/110`.

### §E-8. Liquidation Executor Collateral Compensation

- **Adopted value**: `min(0.5% × collateral, 1,000 units)` (`COLL_GAS_COMPENSATION_DIVISOR = 200` / `COLL_GAS_COMPENSATION_CAP = 1_000e18`). For details see [Parameters.md §3-7](../../Parameters.md).

### §E-9. Special Design of the dJPY (JGB token) Branch

Since both the collateral currency and the issued currency are JPY, the general formula's Depeg, Slip, and FX are 0, and only Stress_Price takes effect.

- **Liquidation flow (permissioned)**: tokenized JGB has transfer restrictions and no DEX sale. `Trove liquidatable → operations liquidate with JPYdf → receive JGB token → redeem from issuer → receive JPY → return to JPYdf`. The oracle is assumed to ingest the NAV published by the issuer / partner via Chainlink Proof of Reserves, etc.
- **Duration premise**: **3M or less**, on par with BUIDL / OUSG. BUIDL is $1 stable + USDC par redemption; OUSG is NAV-based redemption. The OUSG mechanism is conservatively assumed.
- **Liquidation-to-redemption period**: oracle lag of several hours + update interval 24h + liquidator reaction of several minutes + redemption worst case (spanning a holiday block) ≈ about 2 weeks.
- **LLTV / MCR**: from §C-6, Stress_Price = 2h max 0.279% / p99.9 0.248% → adopted 0.28%. `MCR = 1.05 / (1 − 0.0028) = 105.30%`, `LLTV = 94.97%`.
- **CCR**: with the other formulas, `MCR = CCR` results, which does not function, so it is designed by a gap. `CCR = MCR + 2% = 107.30%`.

  | gap (CCR−MCR) | APR 1% | APR 5% | APR 10% | APR 50% | APR 250% |
  | --- | --- | --- | --- | --- | --- |
  | 1% | 358 days | 73 days | 37 days | 8.8 days | 2.8 days |
  | 2% | 712 days | 145 days | 74 days | **17 days** | 5.7 days |
  | 3% | 1063 days | 217 days | 111 days | 26 days | 8.4 days |

  APR 250% is an outlier. Even assuming APR 50%, with 2 weeks the branch can be kept healthy in preparation for liquidation → CCR 107.30%.
- **SCR**: if it falls to a level where the `URGENT_REDEMPTION_BONUS` (2%) cannot be paid, the urgent redemption reverts and Bad Debt remains. With a gap symmetric to CCR, `SCR = MCR − 2% = 103.30%` (satisfies ≥102%).
- **Oracle**: in the case of JPYC-family collateral, initially the oracle is hardcoded at 1 yen (with possibility of a future upgrade).

---

## §F. dToken Layer Operational Parameters — Adoption Rationale

> Operational parameters held by DeltaForesight's own dToken / CollateralVault, not Liquity v2 core. Implementation specs are in [CollateralVault](../../protocol/product/spec/CollateralVault.md) / [dToken](../../protocol/product/spec/dToken.md) / [Strategy](../../protocol/product/spec/strategies/Strategy.md). The finalized values are in [Parameters.md §2-B / §4](../../Parameters.md).

### §F-1. mintCap

- **Policy**: from a Biz perspective, setting a cap that fills on the launch day and showing "cap reached on day one" is more effective for user acquisition. Day-1 open branches are wstETH / USDC. Reserved Branches 3–7 with no finalized Underlying start at 0. A future XAUT candidate may be raised only after on-chain depeg reflection is operational.
- ⚠️ **Background on cap-size analysis**: the old memo also considered "self-B/S mint $250k floor · USDT deal cap $3m" and "each branch $1m", but a 2026-06-18 re-examination found that, taking into account the maximum liquidation size of 22% relative to debt for Liquity v2's wstETH branch over the past year, a $1m cap cannot fully absorb a 50%-scale liquidation, whereas **a 100-million-JPYdf scale has ample headroom**. The current Day-1 open-branch caps are dwstETH = 35 million yen and dUSDC = 100 million yen (Parameters.md is canonical).
- **Day-1 branch debt ceiling decision (#301)**: for Day-1, no new on-chain branch debt ceiling is added to Core (the Core diff / test / audit complexity is high, and the initial exposure can be managed via dToken mintCap · MCR/CCR/SCR · SP coverage · ops gate). `mintCap` must not be denoted as "JPYdf issuance cap" or "branch debt ceiling".

### §F-2. allocatorCooldown

- **Adopted value**: 30m for all branches. Not applied to `Strategy.sendToVault` (buffer replenishment).
- **Policy**: the purpose is to reduce risk when the ALLOCATOR key is leaked. Since it is whitelist-limited, conservatively extending it does not greatly increase safety, so it may be possible to prioritize convenience. The point that funds could be indirectly drained if an allocator key leak overlaps with a whitelisted-destination exploit is a residual risk.

### §F-3. allocateMaxMove

- **Adopted value (Day-1)**: dUSDC = 100 million yen; all others (dETH, dwstETH, and inert branches) are 0 (`0` = allocation halted, `type(uint256).max` = effectively no upper limit). dwstETH has no Day-1 Strategy.
- **Positioning**: a safety device that limits the amount movable at once in case of a key compromise. The design-philosophy description is thin, and the value rationale at activation is to be detailed later ([Parameters.md §8-1](../../Parameters.md)).

### §F-4. withdrawDelay

| Collateral | withdrawDelay | Rationale |
| --- | --- | --- |
| WETH | 3 days | Current dETH has cap 0 and assumes only synchronously recoverable Strategies. The former 17-day Lido assumption is not adopted; see [Strategy Selection Policy](../../protocol/operations/policies/Strategy-Selection-Policy.md) |
| WBTC | 12 days | 9 days when using Lombard + 3 days buffer |
| USDC / USDT | 3 days | basically a sync strategy |
| USD stable (sUSDS, etc.) | 10 days | assuming sUSDe's 7 days |
| Gold (XAUT) | 3 days | no particular destination for management |
| JPY stable | 3 days | basically a sync strategy |

- **Policy**: being conservative enough to add a buffer on top of the withdrawal period of an async-type Strategy is acceptable. "Saying you can withdraw but being unable to" carries a larger reputation risk.
- ⚠️ The old Notion parent table had a swap: WETH = 12 days / dBTC = 17 days. The finalized values are **WETH = 17 days / dBTC = 12 days**.

### §F-5. bufferTargetBps

- The target ratio held inside the Vault as immediately withdrawable liquidity. Redemption uses this buffer.
- **Derivation rationale**: the redemption-to-TVL ratio of Liquity v2 from 2025-05-15–2026-05-04 is aggregated as a rolling-max over each withdrawDelay period, and the largest **WETH branch** value is conservatively adopted.

  | Branch | TVL | 3d | 10d | 12d | 17d |
  | --- | --- | --- | --- | --- | --- |
  | WETH | $23m | 3.33% | 9.38% | 10.16% | 12.00% |
  | wstETH | $118m | 0.62% | 1.66% | 1.90% | 2.52% |
  | rETH | $22m | 1.24% | 2.12% | 2.44% | 3.42% |

  → per withdrawDelay period: 3 days = 3.33% / 10 days = 9.38% / 12 days = 10.16% / 17 days = 12.00%.
- The largest single redemption (1 tx) is 1.34% of TVL (WETH branch).
- **Policy**: since in DeltaForesight's early days a single redemption can be relatively large, there is room for a 1.5–3× multiplier. Combination with peg monitoring + flash-loan arbitrage bots is under consideration.

### §F-6. bufferFloor

- **Adopted value**: 0 for all branches. The understanding is that it is unnecessary if it can be controlled via `bufferTargetBps`.

---

## §G. Minimum Interest Rate (MIN_ANNUAL_INTEREST_RATE) — Adoption Rationale

> **Finalized value**: common across all branches at **0.5% (`_1pct / 2`), finalized 2026-06-10**. The Liquity v2 standard value is maintained with no DF-specific change. Since it is a Core inherited constant, **the source of truth for the value is [Liquity-v2-Core-Spec.md §7](../../protocol/product/spec/Liquity-v2-Core-Spec.md)** (as a base-unmodified inheritance, the policy is not to list it in [Parameters.md](../../Parameters.md)). This section is the rationale for deciding the value (migrated from the old Notion child "Minimum Interest Rate Discussion Memo_20260610").

### §G-1. Conclusion

`MIN_ANNUAL_INTEREST_RATE = 0.5%` is adopted for all branches (standard value maintained, no reduction). Borrowers can freely set the annual rate within the range `[MIN, MAX]`, and its lower bound is not changed from base.

### §G-2. Origin of the Discussion

For the tokenized JGB branch, a reduction (0.5% → 0.3%) was considered, from the hypothesis that lowering the borrowing cost would increase JPYdf issuance.

### §G-3. Attacks / Risks Considered (0.5% → 0.3%)

| Perspective | Impact |
| --- | --- |
| Direct attack | No new attack vector |
| Secondary vulnerability | A 0.2% lower borrowing cost slightly increases the profitability of existing attacks (JPYdf dump chains, arbitrage) |
| Redemption avoidance | The cost of temporary interest-rate manipulation decreases slightly |
| SP yield | Lower interest-derived yield → SP depositor exit → SP weakening → weakening of the liquidation mechanism |

No immediately critical vulnerability arises, but all of these shave safety slightly.

### §G-4. Rationale for Maintaining 0.5%

- **Market interest-rate environment**: Japan has little room for rate cuts amid rising prices and yen weakness, and even at the 2026-06 meeting the policy rate rises toward 1%. A 0.5% yen-denominated borrowing rate is sufficiently attractive. With JGB yields structurally continuing to rise due to fiscal strain, there is little necessity to lower the borrowing cost further.
- **Attack resistance and fork policy**: the benefit of a reduction (increased issuance) does not justify the risk. As a Liquity v2 fork, **base parameters are changed as little as possible** (inheriting audits / track record, avoiding unexpected behavior).

### §G-5. Implementation / References

- Source of truth for the value: [Liquity-v2-Core-Spec.md §7](../../protocol/product/spec/Liquity-v2-Core-Spec.md) — `MIN_ANNUAL_INTEREST_RATE = _1pct / 2` (0.5%).
- Code: `contracts/src/Dependencies/Constants.sol` / `contracts/src/BorrowerOperations.sol` (`_requireValidAnnualInterestRate`).

---

## §H. Difference Memo from Old Notion Values (stale caution)

Stale values that remained mid-analysis on each old Notion page (in all cases, **the finalized records in Parameters.md / this document are canonical**). **※ This is a separate axis from the §0 sUSDS policy floor / USDC · USDT stress-derived restoration** (these here are transpositions / old versions within Notion).

| Item | Old Notion record | This document's record | Notes |
| --- | --- | --- | --- |
| USDe / dUSD LLTV | 86.03% | 86.30% (old USDe-proxy value) | transposition of the formula `0.8732×0.9883≈0.8630`. Current dUSD is USDS basis + MCR 120% floor, **83.33%** (§D-7 / §0) |
| dJPY LLTV / MCR | 98% / 102.04% (early memo) | 94.97% / 105.30% | JGB-family finalized design (§E-9) |
| JPY Liquidation Penalty | 2% (premised on MCR 102.04%) | 5% (secured at MCR 105.30%) | §E-4 |
| WETH withdrawDelay | 12 days (parent table) | 17 days | §F-4 swap |
| dBTC(WBTC) withdrawDelay | 17 days (parent table) | 12 days | §F-4 swap |
| mintCap | 100 million JPYdf (WETH, parent table) / $1m proposal | dwstETH = 35 million yen · dUSDC = 100 million yen | §F-1 (2026-06-18 re-examination; current value is Parameters.md) |
| rebalanceCooldown / rebalanceMaxMove | old names | allocatorCooldown / allocateMaxMove | renamed ([CollateralVault](../../protocol/product/spec/CollateralVault.md)) |

---

## §I. References

- **Source of truth for finalized values / latest derivation formulas**: [Parameters.md](../../Parameters.md)
- **Mechanism specs**: [Liquity v2 core spec](../../protocol/product/spec/Liquity-v2-Core-Spec.md) / [CollateralVault](../../protocol/product/spec/CollateralVault.md) / [dToken](../../protocol/product/spec/dToken.md) / [Strategy](../../protocol/product/spec/strategies/Strategy.md) / [Oracle](../../protocol/product/spec/Oracle.md)
- **Derivation spreadsheet**: `LLTV_DeltaForesight_20260111` (internal Google Sheets)
- **Upstream**: [liquity/bold README](https://github.com/liquity/bold/blob/main/README.md#liquidation-penalties-and-borrowers-collateral-surplus)
- **Data sources**: each API in §B-2 / Ministry of Finance JGB Interest Rate Information

> This page is the consolidated / replacement version of the old Notion parameter-related pages (a record of past-time analysis). The Notion side has been retired, and from now on the reference for analysis records is this page. The finalized values are always canonical in Parameters.md.
