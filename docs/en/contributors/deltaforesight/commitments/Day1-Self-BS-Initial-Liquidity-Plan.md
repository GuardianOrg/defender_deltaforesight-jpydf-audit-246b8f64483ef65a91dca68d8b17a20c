# Rationale for Day-1 Initial Liquidity from the Self Balance Sheet

## Positioning

| Item | Value |
| --- | --- |
| Status | Active |
| Role | Calculation basis, comparisons, and rejected alternatives for self-B/S allocation, SP seed, and bootstrap-Trove rates |
| Company-adopted values | [Day-1 Self-B/S Launch Commitment](Day1-Self-BS-Launch-Commitment.md) |
| Product requirements | [Mainnet Launch Product Decision Record](../../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md) |
| Out of scope | gates, execution procedure/evidence, and current implementation status |

This document is analytical support. Current adopted company amounts and product requirements are stated only in the records above. Its scope is self-funded DEX LP seed and pre-funded Stability Pool deposits, not user-funded Vault buffers or Strategy operation.

Japanese docs are the source of truth. This English document is a support translation.

## Purpose

Define how to allocate up to JPY 150 million of launch liquidity from DeltaForesight's B/S between SP / DEX, and how to manage it after launch.

## Decisions

### Allocation Policy

Use a DEX-weighted allocation. Do not make SP excessively thick; prioritize peg defense.

### Finalized Allocation Breakdown

The actual cash outlay from the self B/S is about JPY 150 million, while the market-deployed positions are about JPY 124.28 million in notional. They are different because self-minted JPYdf funds part of the market-deployed position.

A Japanese DAT Company A is expected to use the dwstETH branch from Day 1. To reduce the probability and impact of its Trove being reached by redemption, the company also self-mints a small amount on dwstETH. This adopts Pattern D below while preserving JPY 100 million DEX liquidity, the SP floor, and the JPY 150 million B/S budget.

**(1) B/S actual contribution: cash budget ceiling JPY 150 million**

| Contribution | Cash | Details |
| --- | ---: | --- |
| dUSDC self-mint collateral | JPY 92.77 million | Open a dUSDC Trove with USDC collateral and mint JPY 69.58 million JPYdf at 75% LTV, rounded to JPY 10k units |
| dwstETH self-mint collateral | JPY 7.23 million | Open a dwstETH Trove with wstETH collateral and mint JPY 4.70 million JPYdf at 65% LTV |
| USDC side of DEX LP | JPY 50.00 million | USDC contribution assuming a half-and-half JPYdf/USDC pool |
| **Total B/S cash contribution** | **JPY 150.00 million** | Budget ceiling; no spare room |

**(2) Market-deployed positions: notional JPY 124.28 million**

| Position | Notional | Source of JPYdf |
| --- | ---: | --- |
| DEX LP (JPYdf / USDC, Uniswap v4) | JPY 100.00 million | JPYdf 50.00 million from self-mint + USDC 50.00 million from (1) |
| Pre-funded SP dwstETH | JPY 15.95 million | JPYdf 15.95 million from self-mint |
| Pre-funded SP dUSDC | JPY 8.33 million | JPYdf 8.33 million from self-mint |
| **Market-deployed total** | **JPY 124.28 million** | - |

Self-minted JPYdf totals JPY 74.28 million = DEX JPYdf side JPY 50.00 million + SP deposits JPY 24.28 million. It is backed by JPY 100 million of self-mint collateral and is not an additional cash outlay.

### Other Finalized Items

| Item | Value | Source |
| --- | --- | --- |
| Operations budget ceiling | JPY 150 million | - |
| Day-1 mintCap>0 branches | dwstETH (JPY 35 million) / dUSDC (JPY 100 million) | Source of truth: [Parameters](../../../Parameters.md) and [Product Decision Record](../../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md) |
| mintCap round-up rule | Round up below JPY 1 million | Round "company self-mint + expected external borrow" to JPY 1 million units |
| Day-1 inert branches | dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB (Branches 2–7) | No bound Underlying, placeholder feed, cap 0, non-public |
| DEX pair | JPYdf / USDC only | Liquidity-Route-Policy.md |
| DEX venue | Uniswap v4 | Liquidity-Route-Policy.md |
| Self-mint LTV | dUSDC 75%, dwstETH 65% | wstETH branch uses the lower LTV |
| mintCap per branch | dwstETH = JPY 35 million, dUSDC = JPY 100 million | Branches 2–7 remain cap 0 |
| Liquidation assumption | A 25% lump-sum liquidation of each branch's external borrowing room is absorbed by SP | See the analysis below |

### Borrow APR / Bootstrap Trove Policy

Day-1 borrow APR should not be presented as a protocol-promised fixed recommended rate in the public UI. The default UX should be Automatic / Operator-managed. The company bootstrap Trove initial rate, management range, and change conditions are frozen in launch operation evidence.

The Day-1 business target prioritizes letting ETH borrowers / DATs borrow JPYdf below the cost of directly borrowing USD stablecoins. The core hypothesis is an on-chain JPY-funded carry trade through wstETH collateral → JPYdf borrow → USDC swap. The normal dwstETH target APR therefore starts from borrower competitiveness, with a **2.0% upper-bound target**.

The company bootstrap dUSDC / dwstETH rate is back-calculated from low-cost borrower acquisition and a competitive JPY-denominated SP yield rather than external USD DeFi yields.

Formula:

`borrow APR = target SP APR x target SP coverage / SP_YIELD_SPLIT`

where `SP_YIELD_SPLIT = 75%` and `target SP coverage = SP deposits / branch debt`. For the USDC branch Day-1 assumption, branch debt is JPY 100 million (self-mint 69.58 million + cap headroom 30.42 million). If target SP coverage is 37.5% (company SP 8.33 million + external / campaign SP about 29.17 million), and target SP APR is 4.0% (short-term JPY 1.0% + DeFi risk premium 3.0%), the bootstrap borrow APR is `4.0% x 37.5% / 75% = 2.0%`.

For dwstETH, `plannedDebtJpydf = JPY 35 million` and `targetSpJpydf = JPY 15.95 million`, so coverage is about 45.6%. A 2.0% borrow APR gives an interest-only SP gross APR of about 3.3%. This lower rate is intentional because the SP is sized as a safety buffer for expected borrow, wstETH drawdowns, and 25% events; the UI must not present actual SP APR as guaranteed.

| Target | Normal business target | Risk-mode / emergency range | Policy |
| --- | ---: | ---: | --- |
| Company bootstrap dUSDC Trove | 2.0% | 1.5%-2.5% | Anchor from SP target APR 4.0%, target SP coverage 37.5%, and SP share 75%. The core LP / SP seed uses 2.0% as the main line |
| Company bootstrap dwstETH Trove | 2.0% main line | 1.5%-2.5% | execution order and rate remain explicit launch evidence |
| General dUSDC borrower / operator managed | <=2.0% | 2.0%-3.5% | Prioritize the low-cost JPY borrow thesis. Raise into risk-mode only when SP coverage is thin, redemption pressure is high, or the JPYdf/USDC peg is weak |
| General dwstETH / wstETH borrower / operator managed | <=2.0% | 4.0%-5.5% | risk mode only after SP, redemption, peg, wstETH, liquidation, and LP-depth evidence |

Borrow APR also determines redemption priority. In Liquity v2, lower-rate Troves are redeemed first; for equal rates, the later Trove is redeemed first. Therefore the bootstrap Trove rate is also an accounting decision about placing company self-mint ahead of user Troves in the redemption order. Day-1 policy places the company bootstrap Troves at low rates so general borrowers who want cheap borrowing still have a DF-side buffer in front of them.

Day 1 uses a dUSDC bootstrap Trove (69.58m JPYdf) and a dwstETH bootstrap Trove (4.70m JPYdf), both with a 2.0% anchor. The small dwstETH self-mint is a redemption-risk buffer; per-Trove rate, insertion order, and accounting approval remain launch evidence.

Multiple Troves are not mandatory on Day-1. Splitting the dUSDC bootstrap into at most 2 Troves is allowed only if the company explicitly wants to separate the DF-side redemption risk buffer ceiling.

| Use | Debt | Rate | Conditions |
| --- | ---: | ---: | --- |
| DF-side redemption risk buffer | JPY 25 million JPYdf | 1.5%-2.0% | Only when the company approves placing the bootstrap Trove where it is more likely to be consumed first and launch evidence can record the per-Trove split |
| Core bootstrap | JPY 50 million JPYdf | 2.0%-2.5% | Core LP / SP seed. Normally treat this as a single Trove |

If the per-Trove split cannot be evidenced, do not create multiple Troves. Do not split into 3 or more Troves on Day-1 because the operational load of rate adjustment, upfront fee, accounting, and redemption response outweighs the benefit.

APR raise triggers: sustained JPYdf/USDC downward deviation, redemption fee / base rate increase, reduced managed Trove debt-in-front, lower SP coverage, sharp WETH drop or more liquidation candidates, and insufficient LP depth. Do not jump from the 2.0% normal target to 4.0%+ without evidence; first record borrower demand, peg state, redemption state, and SP coverage, then use the 4.0%-5.5% range only when risk-mode conditions are met. APR lower triggers: weak borrow demand, JPYdf upward deviation, quiet redemptions, sufficient SP coverage, and improved LP depth.

### Mapping Into Launch Config

The Day-1 targets for `Mainnet-Launch-Operation-Gate.md` / `mainnet-launch-operation.config.example.json` are:

| Branch | targetSpJpydf | plannedDebtJpydf | Rationale |
| ---: | ---: | ---: | --- |
| 0 dwstETH | JPY 15.95 million JPYdf | JPY 35 million JPYdf | product exposure envelope and SP requirement |
| 1 dUSDC | JPY 8.33 million JPYdf | JPY 100 million JPYdf | mintCap 100M = company self-mint 69.58M + headroom 30.42M. The SP uses the original PR #266 floor |

Branches 2–7 are not included in `activeBranches`. Any future public exposure requires the relevant activation package before changing launch config.

## Items Under Consideration / To Be Decided

- How to manage own-capital liquidity, including whether to use Arrakis Pro, alternative tooling / infrastructure, range-management method, and the relationship between redemption bot and in-house liquidity-management bot.

## Analysis Process

### Four SP / DEX Allocation Plans

The adopted historical comparison is **C. DEX-weighted**. The table below is a past comparison assuming three active branches and JPY 100 million per branch; it is not current launch config. Current product and company values are canonical only in the Product Decision Record and Self-B/S Commitment.

| | A. SP-weighted | B. Balanced | **C. DEX-weighted** | D. 100% DEX |
| --- | ---: | ---: | ---: | ---: |
| DEX LP (JPYdf / USDC) | JPY 60M | JPY 80M | **JPY 100M** | JPY 128.6M |
| SP per branch | JPY 20M | JPY 14.2M | **JPY 8.33M** | 0 |
| SP total | JPY 60M | JPY 42.5M | **JPY 25M** | 0 |
| Operator self-mint total | JPY 90M | JPY 82.5M | **JPY 75M** | JPY 64.3M |
| Operator self-mint / stable branch | JPY 45M | JPY 41.25M | **JPY 37.5M** | JPY 32.15M |
| Upper bound of SP-only liquidation | <= JPY 20M | <= JPY 14.2M | **<= JPY 8.33M** | 0 |
| SP-only liquidation ratio | ~95% | ~90% | **~80%** | 0% |
| Operator JIT capacity | JPY 28.6M | JPY 38M | **JPY 47.6M** | JPY 61.2M |
| SP + JIT capacity / branch | JPY 48.6M | JPY 52.2M | **JPY 55.9M** | JPY 61.2M |
| 25% event (JPY 25M) absorption headroom | 1.94x | 2.09x | **2.24x** | 2.45x |
| Swap size to move peg +/-0.5% | JPY 3M ($19k) | JPY 4M ($25k) | **JPY 5M ($31k)** | JPY 6.4M ($40k) |
| Swap size to move peg +/-1% | JPY 6M ($38k) | JPY 8M ($50k) | **JPY 10M ($63k)** | JPY 12.8M ($80k) |

### Liquity v2 Mainnet Observations

Liquity v2 BOLD 1-year operation record as of 2026-06:

| Branch | TVL | SP balance | Estimated debt | SP / debt | Single max trove / debt | Single max trove |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| WETH | $23M | $6.0M | ~$9M | 67% | 3.2% | $285k |
| wstETH | $118M | $8.7M | ~$13M | 67% | 22.8% | $2.97M |
| rETH | $22M | $5.2M | ~$8M | 65% | 0.4% | $30k |

However, Liquity v2 has many organic SP depositors and maintains about 67% SP/debt. It cannot be compared directly with DeltaForesight immediately after launch.

### Liquidation Size Distribution

Liquity v2 WETH branch, 1-year record:

| Percentile | Liquidation size | Branch debt ratio |
| --- | ---: | ---: |
| p50 | $7.6k | 0.085% |
| p75 | $34k | 0.4% |
| p90 | $91k | 1.0% |
| p95 | $130k | 1.45% |
| max | $285k | 3.2% |

Applied to the comparison scenario for dwstETH and dUSDC, 90% of liquidations are around JPY 300k and the maximum event is under JPY 1m. Using the whole dUSDC JPY 100m envelope as a conservative denominator gives about JPY 1m at p90 and JPY 3.2m at maximum.

### 25% Event Assumption

The comparison scenario assumes one Trove or cluster occupies 25% of assumed external debt. This is an analytical input, not executable current borrowing capacity.

- Liquity v2 wstETH single max is 22.8% of branch debt, so 25% is one conservative step.
- dUSDC: 25% of launch planning room is about JPY 6.25M. Even against full cap headroom it is about JPY 7.61M, covered by the JPY 8.33M pre-funded SP.
- dwstETH: 25% of the assumed external debt is about JPY 7.58m, covered by the JPY 15.95m pre-funded SP.

### Additional Company A Analysis: Patterns A-E

Company A's expected Day-1 dwstETH use led to an additional allocation analysis to reduce the probability and impact of redemption.

Assumption: N-day cumulative worst redemption ratio from Liquity v2 BOLD mainnet 13-month data (2025-05 to 2026-06). Conservative Scenario A assumes the JPY 25M dUSDC launch planning room is 100% deposited to SP, so dUSDC SP state = 8.33M + 25M = JPY 33.33M. The remaining dUSDC cap headroom JPY 5.42M is not included as campaign demand unless launch evidence is updated.

Boundary from Issue #558: this section is a B/S allocation for `redemption risk reduction / exposure preservation support`; it is not an absolute third-party-redemption avoidance guarantee. DF does not exclude a specific user from the Core redemption path and does not stop permissionless redemption. Monitoring / alert / runbooks are best-effort and may be delayed, missing, false-positive, or false-negative. Day-1 standard scope is manual / best-effort explanation from existing ops metrics and launch evidence. If a dedicated dashboard / alert / report is promised as a Day-1 commitment, implementation, dry-run, alert delivery path, and runbook completion become launch blockers. After a redemption, whether to repay JPYdf or restore ETH delta through spot, derivatives, or Trove reconstruction, and which venue / signer / funding source to use, remains Allied-side treasury execution. Any DF guarantee or execution of timed ETH exposure restoration, rehedge, buyback, or Trove reconstruction is outside Day-1 scope and requires a separate managed-service, legal, and audit gate.

| Item | A (1 day) | B (3 days) | C (7 days) | **D (10 days, adopted)** | E (14 days) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Assumed redemption ratio | 4% | 8% | 14% | **15.3%** | 19% |
| Assumed redemption amount | JPY 5.24M | JPY 10.58M | JPY 18.76M | **JPY 20.61M** | JPY 25.94M |
| Company dwstETH self-mint | JPY 0.95M | JPY 2.20M | JPY 4.00M | **JPY 4.70M** | JPY 6.50M |
| Company ETH collateral | JPY 1.46M | JPY 3.38M | JPY 6.15M | **JPY 7.23M** | JPY 10.00M |
| Company dUSDC self-mint | JPY 73.91M | JPY 72.47M | JPY 70.39M | **JPY 69.58M** | JPY 67.50M |
| Company USDC collateral | JPY 98.54M | JPY 96.62M | JPY 93.85M | **JPY 92.77M** | JPY 90.00M |
| DEX LP | JPY 100.00M | JPY 100.00M | JPY 100.00M | **JPY 100.00M** | JPY 100.00M |
| dwstETH SP | JPY 16.53M | JPY 16.34M | JPY 16.06M | **JPY 15.95M** | JPY 15.67M |
| dUSDC SP floor | JPY 8.33M | JPY 8.33M | JPY 8.33M | **JPY 8.33M** | JPY 8.33M |
| Modeled redemption size before Company A is reached | JPY 5.34M | JPY 11.46M | JPY 18.87M | **JPY 21.46M** | JPY 27.27M |
| B/S total | JPY 150.00M | JPY 150.00M | JPY 150.00M | **JPY 150.00M** | JPY 150.00M |
| dwstETH mintCap | JPY 31.00M | JPY 33.00M | JPY 34.00M | **JPY 35.00M** | JPY 37.00M |

Pattern D was adopted because the company-side dwstETH bootstrap Trove is expected to absorb the modeled 10-day redemption window before Company A, while limiting company ETH-price exposure and preserving JPY 100m DEX liquidity, the SP floor, and the JPY 150m B/S limit.

## References

- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../policies/Balance-Sheet-Liquidity-Allocation-Policy.md) - B/S liquidity allocation framework
- [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) - SP / backstop / JIT terminology and boundaries
- [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md) - DEX route policy (JPYdf/USDC, Uniswap v4)
- [`../../Parameters.md`](../../../Parameters.md) - collateral and parameters
- Liquity v2 BOLD mainnet measured data (Dune Analytics, retrieved 2026-06)
- [Liquity v2 Redemptions and Delegation](https://docs.liquity.org/v2-faq/redemptions-and-delegation)
- [Liquity v2 Borrowing and Multiply](https://docs.liquity.org/v2-faq/borrowing-and-liquidations)
- [DeFiLlama yields API](https://yields.llama.fi/pools)
