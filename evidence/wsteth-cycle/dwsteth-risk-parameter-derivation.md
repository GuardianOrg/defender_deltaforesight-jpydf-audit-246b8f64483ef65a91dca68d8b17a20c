# dwstETH (Branch 0) Risk-Parameter Derivation and Rationale

| Item | Content |
| --- | --- |
| Subject | LLTV / MCR / CCR for Branch 0 `dwstETH` (Underlying: wstETH) |
| Candidate values and rationale | This document |
| Approved values | [Day-1 Parameter Manifest](../../../Parameters.md) §2-A |
| Calculation rules | Collateral Parameter Policy §2.2 / §2.3 (JP) |
| Upstream decision | Day-1 Parameter Decision §2.1–§2.3 (JP) |
| Normative behavior | [Oracle](../../product/spec/Oracle.md) / `DFWstETHPriceFeed` |
| Issues | #1325 (re-derivation) / #1428 (three judgment calls) |

This document is the verification that Day-1 Parameter Decision §2.3 deferred to "a separate launch Evidence": whether wstETH's own market / canonical-rate, depeg and liquidation-exit risks fit inside the WETH envelope. They do not — a depeg leg had to be added and the branch re-derived.

Decision date: 2026-08-06. Approved by the risk owner (the three judgment calls are recorded in §6).

## 1. What is being replaced

After Branch 0's Underlying moved WETH → wstETH, `Constants.sol` still carried the WETH-derived interim values (explicitly marked as pending `#1325`).

| Param | Old (WETH-derived interim) | Final |
| --- | ---: | ---: |
| LLTV | 83.91% | **81.18%** |
| MCR | 119.18% | **123.18%** |
| CCR | 132.61% | **141.67%** |
| SCR | 110% | 110% (keep) |
| BCR | 10% | 10% (keep) |
| Liquidation penalty (SP) | 5% | 5% (keep) |
| Redistribution penalty | 10% | 10% (keep, §6 call 3) |

## 2. The calculation pipeline

The high-volatility model of Collateral Parameter Policy §2.2 / §2.3 is used unchanged.

```
MCR  = (1 + SP) / [(1 − Price)(1 − Depeg)(1 − Slip × Mult)(1 − FX)]
LLTV = 1 / MCR
CCR  = MCR / [(1 − Price)(1 − Depeg)(1 − FX)]        (no SP, no slippage)
```

The WETH (Branch-0 interim) inputs were first verified to reproduce the shipped numbers.

| Input | Value | Provenance |
| --- | ---: | --- |
| SP penalty | 5% | Liquity v2 standard |
| Price | 9.07% | ETH/USD 2h 99.9th, Binance 5-min, 2017-08→ |
| Depeg | 0% | WETH has none |
| Slip × Mult | 0.98% × 2 = 1.96% | ParaSwap historical quote × liquidity-stress multiplier |
| FX | 1.17% | JPY/USD 2h 99.9th, Twelve Data 5-min, 2021→2026 |

Check: `1.05 / (0.9093 × 0.9804 × 0.9883) = 1.19176 → 119.18%` and
`CCR = 1.19176 / (0.9093 × 0.9883) = 1.32616 → 132.61%`, both matching the shipped values.

The percentile convention is the one already used by the other legs: a 2h window (the liquidation-latency assumption), 99.9th for continuously traded price legs and **2h max drawdown for jumpy depeg legs** (USDC already uses a 2h max DD of 9.32%, XAUt/XAU a max DD of 7.616%). Display values are rounded to 2 decimals.

## 3. What the oracle sees, and which leg each risk belongs to

`DFWstETHPriceFeed` computes
`wstETH/USD = stETH/USD (Chainlink market feed, 1h heartbeat / 1% deviation) × stEthPerToken (canonical, no staleness)`,
then converts to JPY. The protocol price therefore carries:

- **ETH market risk** — through stETH/USD (stETH tracks ETH) → Price leg, kept at 9.07%.
- **stETH/ETH market depeg** — through stETH/USD (a discount shows up directly in the price) → the **new Depeg leg**, measured in §4.
- **Slashing (canonical-rate decline)** — through `stEthPerToken`, not through the market ratio (a socialized negative rebase shrinks stETH balances while the stETH/ETH market price stays ≈1). Not added as a numeric leg; treated qualitatively in §7.

## 4. The depeg leg, measured

Dataset: DefiLlama `coins.llama.fi` hourly stETH and WETH USD prices, 2022-01-01 → 2026-08-05 (hourly coverage starts in Jan 2022 and covers both 2022 depeg episodes), 27,694 joint points; ratio = stETH / WETH.

Cleaning mirrors the existing pipeline's anomaly exclusion (JPY/USD dropped 270 outliers): a plausibility clip of `[0.85, 1.05]` plus an iterative despike that drops any point deviating more than 1.5% from its 5-point neighborhood median (this removes single-point API glitches such as a fictitious 78% "drop" on 2025-09-02). 486 points dropped.

stETH/ETH ratio decline statistics (cleaned):

| Window | max DD | p99.9 | p99 |
| --- | ---: | ---: | ---: |
| 1h | 3.03% | 1.91% | 1.16% |
| **2h** | **3.25%** (2022-06-01, Celsius run) | 2.08% | 1.37% |
| 24h | 5.38% | 3.12% | 2.18% |
| 7d | 6.16% | 4.99% | 3.35% |

Context: the all-time minimum ratio is 0.9234 (2022-06-18) — a full-episode depeg of 7.7% from parity, the widely cited "~0.93–0.935 floor" of the Celsius/3AC crisis. Post-Shapella (withdrawals live, 2023-04-12→) the minimum ratio is 0.9796 (2026-06-24) and the worst 2h move is 2.64% (2023-12-22). The 2025 Aave-unwind episode depegged stETH only ~0.3–0.6% despite a record exit queue.

**Adopted Depeg = 3.25% (2h max DD)**, following the convention that jumpy depeg legs use max DD, measured over the whole history including the pre-withdrawals era.

Slippage stays at 1.96% (WETH's 0.98% × 2). wstETH liquidations exit through the deep stETH/ETH Curve pool and the withdrawal queue, and the market discount under stress is already what the Depeg leg measures — a larger slip term would double-count it. The Day-1 mintCap is JPY 35M, far below the $5M liquidation size behind the 0.98% quote.

## 5. Derivation

```
Denominator = (1 − 0.0907)(1 − 0.0325)(1 − 0.0196)(1 − 0.0117)
            = 0.9093 × 0.9675 × 0.9804 × 0.9883 = 0.852413
MCR  = 1.05 / 0.852413 = 1.231797  →  123.18%
LLTV = 0.852413 / 1.05 = 0.811822  →  81.18%
CCR  = 1.231797 / (0.9093 × 0.9675 × 0.9883)
     = 1.231797 / 0.869455 = 1.416742  →  141.67%
```

Because every other term is shared with the WETH derivation, this is equivalently `MCR_wstETH = MCR_WETH / (1 − depeg)`.

Invariants: `SCR(110) < MCR(123.18) < CCR(141.67)`, `SP ≤ redist ≤ 20% cap`, `1 + SP ≤ MCR`, `SCR ≥ 102%` (urgent-redemption bound). Machine-reconciled by `forge test --match-path test/DFBranchRiskParams.t.sol` and the constant-mirror guard.

## 6. The three judgment calls (settled 2026-08-06)

### Call 1: depeg window → **2h window, 3.25%**

Using the full episode (7.7%) would give MCR ≈ 129.4% / LLTV ≈ 77.3%, putting wstETH in the same tier as XAUt. Rejected because:

- The oracle marks the market discount into ICR continuously, so a multi-day depeg triggers ordinary liquidations along the way. Only the move inside the 2h liquidation-latency window is unhedgeable — the identical logic already applied to the ETH price leg. The full 7.7% episode is covered by CCR / SCR, the branch-level defenses.
- The 2022-06 depeg beyond 7% is real, but **the Chainlink price feed kept updating throughout that episode** — liquidations were able to proceed against a moving price rather than being blocked by a stalled feed. Since Shapella made withdrawals live the arbitrage path exists, and the record exit queue of 2025 produced only a 0.3–0.6% depeg. That is thin ground for adopting the ultra-conservative 129%.
- LLTV 81.18% sits at Aave v3's stETH LT (≈81%), consistent with peers (§8).

### Call 2: measurement granularity → **hourly accepted**

The depeg leg alone is measured on hourly data while the other legs use 5-min data; hourly is the finest granularity available back to 2022 through DefiLlama. Re-measuring at 5-min resolution is expected to move the answer by 3–4% (MCR 123–124.5%, i.e. ≤1.3pp), and the adopted 3.25% is already 23% above the worst post-Shapella 2h move (2.64%). The granularity gap is recorded as residual uncertainty in §9; a paid re-measurement (Kaiko / CryptoCompare) is a future re-evaluation item, not a Day-1 blocker.

### Call 3: redistribution penalty → **10%, unchanged**

Upstream Liquity v2 ships 20% for wstETH / rETH, compensating redistributees for LST depeg exposure. DF deliberately uses a uniform 10% across all branches (concern about the attack incentive of inducing redistribution, plus the AsymmetryFi precedent). 10% still exceeds the full 2022 episode depeg of 7.7%, so a redistributee stays whole even at the worst historical discount. There is no affirmative reason to break the uniform policy for Branch 0 alone.

## 7. Risks not in the formula

- **Slashing / canonical rate**: `stEthPerToken` has **never decreased** — Lido has had no negative daily rebase in its history — and LIP-23 negative-rebase protection plus a ~6.6k stETH insurance fund sit behind it. A severe correlated-slashing event would flow through the canonical leg, but published assessments bound realistic severe scenarios well below the ≈18.8% overcollateralization that exists at MCR after the 5% penalty. No numeric leg is added.
- **Thinness of the 10% redistribution penalty**: kept per §6 call 3. Re-evaluate together with any Strategy activation or cap increase.

## 8. Precedent comparison

| Venue | wstETH / stETH parameters | Comment |
| --- | --- | --- |
| Liquity v2 upstream (`liquity/bold` `Constants.sol`, verified from source) | MCR 120 / CCR 160 / SCR 120 / BCR 10 / SP 5% / redist 20% | The 83.33% that appears in some search summaries is an LTV restatement, not an MCR |
| Aave v3 mainnet | stETH / wstETH LT ≈81% (LTV 78–79%) | Our LLTV 81.18% is at the same level |
| Spark (SparkLend) | wstETH max LTV 79% | |
| Morpho / Euler / Fluid / Compound | 86% / 83% / 88% / 86% | Peer table (Collateral Parameter Rationale §E-7) |
| Nerite (bold fork) | LST 130 / 160 / 115 | |
| DF WETH (same model, comparison basis) | MCR 119.18 / CCR 132.61 / SCR 110 | |

The divergence from upstream is explainable. MCR 123.18 > 120 because DF adds the JPY FX leg and uses 99.9th / max-DD stress — the same divergence pattern as DF WETH 119.18 > upstream 110. CCR 141.67 < 160 because DF derives CCR from measured stress instead of upstream's flat `MCR + 40` — the same relation as WETH 132.61 < 150. SCR 110 < 120 follows DF's deliberate `SCR < MCR` anti-false-shutdown design.

## 9. Residual uncertainty (re-evaluation triggers)

1. **Measurement granularity**: hourly (§6 call 2). A 5-min re-measurement could move MCR within 123–124.5%.
2. **Despike filter**: dropping single points that deviate 1.5% from the neighborhood median would also drop a genuine sub-hour V-shaped crash; hourly data cannot distinguish the two. The adopted number is a 2h *window* statistic rather than a single point, which limits the impact.
3. **Pre- vs post-Shapella**: the adopted 3.25% comes from the pre-withdrawals era (June 2022). Post-Shapella data alone gives a worst 2h of 2.64% → MCR ≈ 122.4%, not materially different; the shipped value is on the conservative side.
4. **Branch values are immutable**: these values cannot be changed after deployment. If wstETH's structure changes materially (withdrawal queue, Lido governance, feed composition), the response is migration to a new branch, not a parameter change.

## 10. Adjacent items (out of scope here, confirmed)

- **`withdrawDelay`**: the old §2-B value of 17d assumed a Lido asynchronous exit and no longer holds — the 2025 exit-queue episodes (post-Pectra churn changes, large unwinds) pushed waits to multi-week. No Day-1 change is needed because **Day-1 dwstETH has no live Strategy allocation** (the Aave V3 wstETH Strategy is registered as the aave-only set, but `allocateMaxMove = 0`; canonical-rate accrual is not Strategy yield), so recovery stays synchronous and the current §3-B values of 3d / bufferTarget 333 bps stand. When a Lido asynchronous Strategy is activated, re-derive from the then-current worst-case queue (Policy §3.3 forbids reusing synchronous values).
- **`PRM-ORACLE-003` (stETH/USD staleness)**: the 86400s (24h) candidate stands. Upstream bold ships 24h for the same feed configuration. Staleness is a Chainlink-outage circuit breaker, not the liquidation-latency bound — the 2h latency is already priced into MCR, and the 1% deviation trigger is what actually keeps the feed fresh. See [Non-JPY Oracle staleness threshold rationale](./non-jpy-oracle-staleness-threshold-rationale.md).

## 11. Sources

- This repository: Collateral Parameter Policy §2, Day-1 Parameter Decision §2, `2026-07-27-Collateral-Parameter-Rationale.md`, Parameters.md, `DFWstETHPriceFeed.sol`, Non-JPY Oracle staleness threshold rationale.
- Upstream: `github.com/liquity/bold`, `contracts/src/Dependencies/Constants.sol` (MCR / CCR / SCR / penalties) and `script/DeployLiquity2.s.sol` (24h stETH/USD staleness).
- Data: `coins.llama.fi` hourly stETH (`0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`) and WETH (`0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`), 2022-01→2026-08. The fetch and statistics scripts are archived under `documents/jp/protocol/launch/decisions/evidence/dwsteth-depeg/`.
- Depeg history: post-mortems of the May–June 2022 stETH discount (floor ~0.93–0.935, recovery after the Merge); reporting on the 2025 unwind episode (0.3–0.6% depeg, 9+ day queue) and the record validator exit queue (multi-week waits).
- Lido: integration guide (daily rebases have never been negative), LIP-23 negative-rebase protection, withdrawals documentation (1–5 days normal, bunker-mode caveat).
- Aave / Spark: risk parameters in the stETH LT 81% lineage; Spark wstETH LTV 79%.
