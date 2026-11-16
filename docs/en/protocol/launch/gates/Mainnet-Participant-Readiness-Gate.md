# Mainnet Participant Readiness Gate

> **Positioning**: do not publicly launch unless borrowers, SP depositors, and liquidators can understand why to use JPYdf and what risks they are accepting. The launch operation procedure is governed by the Japanese source-of-truth [`Mainnet-Launch-Operation-Gate.md`](Mainnet-Launch-Operation-Gate.md), frontend delivery by [`Frontend-Production-Delivery-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md), UX quality by [`Frontend-UX-Readiness-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md), and the liquidation bot boundary by [`bots/liquidator/README.md`](../../../../../bots/liquidator/README.md).
>
> This document translates the broad participant-readiness checklist into Day-1 / Day-2 / not-yet-implemented gates. It is not a source of wording that guarantees yield or safety.

---

## 0. Day-1 Policy

| Participant | Day-1 value | Day-1 explicit limitation |
| --- | --- | --- |
| Borrower | JPY-denominated borrowing, user-set borrow rate, 1Tx borrow for dUSDC / dwstETH, JPYdf/USDC Uniswap v4 exit liquidity | JPYdf liquidity depends on launch seeding. Lower borrow rates are more exposed to redemption. dToken backing / buffer / strategy risk affects collateral value; native staking appreciation of wstETH remains in dwstETH collateral value |
| SP depositor | Core Stability Pool yield from 75% of borrower interest, liquidation collateral claims, transparent branch coverage / outside debt | No Day-1 SP additional rewards or Treasury distribution are claimable. SP is not the repair fund for dToken / Strategy impairment |
| Liquidator | Permissionless liquidation and operator-maintenance bot evidence | Disposal routes, JIT inventory, private relay, and profit model for external profit seekers are Day-2 hardening. Day-1 assumes operator maintenance |
| Operator | Branch health, SP coverage, oracle, backing, liquidity, and liquidator execution in one evidence package | Stale ops values, snapshots, or local fixtures cannot pass the public launch gate |

Day-1 direct JPYdf DEX liquidity is JPYdf/USDC Uniswap v4 only. Curve, Balancer, Uniswap v3, and direct USDT / USDS / WETH / XAUT JPYdf pools are not launch assumptions.

---

## 1. Borrower Readiness

Borrowers must be able to decide borrowing cost, liquidation / redemption risk, and JPYdf exit path.

| Item | Required content | Source of truth |
| --- | --- | --- |
| Effective APR / borrow rate | user-set rate, operator / policy anchor, rationale for borrowRate policy, rate review cadence, and any additional frontend cost if introduced | RPC / subgraph / public stats `borrowRatePolicies` / launch evidence |
| Redemption risk | debt in front, ahead ratio against branch debt, rate distribution, redemption fee / base rate, and lowest-rate-position explanation | SortedTroves / subgraph / public stats / direct RPC |
| Liquidation risk | current ICR, liquidation price, MCR, TCR, CCR / SCR proximity, branch shutdown / safety mode | TroveManager / PriceFeedProxy / branch params |
| dToken risk | backing ratio, Vault buffer, withdraw delay, strategy exposure, pending withdraw, paused flags | CollateralVault / Strategy reads / public stats |
| 1Tx route | Underlying -> dToken -> Trove Zapper route, cap, allowance, and failure fallback display | generated bindings / manifest / Zapper config |
| JPYdf exit | JPYdf/USDC v4 pool, sample slippage, pool freshness, LP seed owner / allowance cleanup evidence | Uniswap v4 reads / launch operation evidence |

No-Go:

- Borrow UI misses effective APR, redemption risk, liquidation price / ICR, or dToken backing / buffer.
- `mintCap = 0` or inert branches appear as borrowable.
- Borrow UI displays raw Underlying spot value without reflecting dToken backing ratio.
- UI implies easy JPYdf exit without JPYdf/USDC route / slippage evidence.
- Curve, Balancer, Uniswap v3, or non-Day-1 direct pools are assumed as routes.
- stale stats / subgraph data appears the same as fresh current values.

---

## 2. SP Depositor Readiness

SP depositors must be able to decide which branch to deposit into and what risk / coverage they receive.

| Item | Required content | Source of truth |
| --- | --- | --- |
| Core SP yield | JPYdf yield from borrower interest, `SP_YIELD_SPLIT`, observed period or policy anchor, and no guarantee wording | StabilityPool / public stats / launch evidence |
| Liquidation reward | claimable collateral, liquidation history, unclaimed rewards, and difference between dToken claim and Underlying redeem | StabilityPool / subgraph / Vault |
| Coverage | branch debt, SP deposits, SP coverage bps, outside debt, covered / thin-SP state | ActivePool / StabilityPool / public stats |
| Branch risk | MCR / TCR / CCR / SCR, oracle freshness, shutdown risk, dToken backing ratio, Vault buffer, strategy exposure | RPC / public stats / ops exporter |
| Exit liquidity | JPYdf/USDC v4 pool price / depth / sample slippage, redemption fee / base rate | Uniswap v4 / CollateralRegistry / RedemptionHelper |
| Additional rewards | Day-1 shows "not implemented / undecided"; claimable only after SPAdditionalRewardDistributor evidence exists | Treasury spec / future SPAdditionalRewardDistributor evidence |

No-Go:

- SP additional rewards, Treasury distribution, or campaign rewards are mixed into claimable APR without contract / distribution evidence.
- SP is described as the repair fund for dToken / Strategy impairment.
- branch debt / SP deposits / outside debt / coverage bps cannot be displayed.
- thin-SP branches lack launch evidence for redistribution / JIT / operator top-up decision owners.
- SP depositors cannot inspect JPYdf exit liquidity and redemption route.
- claim / compound UX appears available for reward types that are not implemented.

---

## 3. Liquidator Readiness

Day-1 liquidation assumes operator maintenance. External profit-seeker readiness requires collateral disposal and inventory-aware profit modeling, which is Day-2 hardening. The source of truth for profit-seeking activation is the Japanese
[`Liquidation-Management-Policy.md`](../../operations/policies/Liquidation-Management-Policy.md#day-2-profit-seeking-hardening-gate)
hardening gate.

### 3.1 Day-1 Required

| Item | Required content | Source of truth |
| --- | --- | --- |
| Bot mode | whether launch uses `dry-run` or `protocol-maintenance`; Day-1 default is `protocol-maintenance`. `profit-seeking` remains Day-2 until collateral disposal and inventory-aware profit modeling are implemented | bot config / launch evidence |
| Candidate scan | top candidate, min ICR, candidate count, branch priority, zombie append path, scanned branches | `bots/liquidator` JSON evidence |
| SP offset | branch SP deposit, SP offset capacity, SP-covered candidate count, minimum SP offset coverage bps | StabilityPool / bot evidence |
| Gas / loss caps | max gas cost, max loss per tx, gas stress multiplier, max submissions per cycle, high-gas escalation owner | bot config / launch evidence |
| Execution evidence | config hash, generatedAtBlock freshness, planned batch, stressed gas cost, decision / skipReason, receipt policy | bot JSON / launch checker |
| Manual JIT / top-up | JPYdf funding source, SP deposit account, decision owner, thin-SP / redistribution decision log | launch operation evidence |
| Collateral disposal | owner for valuation, custody, and disposal of received dToken / Underlying; the bot does not auto-dispose | launch operation evidence |

### 3.2 Day-2 / Profit-Seeker Conditions

- Satisfy the profit model, evidence schema, and P0->P1->P2 activation conditions in the Japanese
  [`Liquidation-Management-Policy.md`](../../operations/policies/Liquidation-Management-Policy.md#day-2-profit-seeking-hardening-gate).
- Profit model including post-liquidation disposal route, slippage, and inventory cost.
- gas / priority fee / base fee forecasting.
- private relay / MEV protection.
- RPC quorum / fallback RPC.
- fast candidate discovery through event subscription or indexer cache.
- policy for detecting multiple zombie Troves.
- JPYdf inventory management or permissionless JIT executor.
- branch priority policy using `ICR deficit`, `SP coverage`, `collateral liquidity`, `branch TCR`, and `gas/tip`.
- Prometheus metrics / alerts / receipt tracking / failed tx classification.

No-Go:

- Current bot is marketed as external-profit-seeker ready.
- `profit-seeking` mode is enabled in the Day-1 launch config.
- dry-run evidence does not match current-manifest config.
- dry-run evidence is stale or misses active branches.
- SP offset capacity, gas / loss caps, stressed gas cost, or skipReason is absent.
- JIT top-up / collateral disposal appears as already automated by the bot.
- failed tx / on-chain revert / receipt timeout classification and escalation owner are absent.

---

## 4. Product Health Transparency

Borrower / SP depositor / liquidator decision inputs must be visible from consistent sources across the user app, ops dashboard, and public transparency surface.

| Area | Required metrics |
| --- | --- |
| Branch health | TCR, SCR, CCR, MCR, shutdownTime, branch debt, SP deposits, outside debt, coverage bps |
| Oracle | current price, updatedAt, staleness margin, lastGoodPrice fallback, source proposal, JPY soft-freeze |
| dToken / Strategy | backing ratio, Vault buffer, pending withdraw, strategy exposure, writeoff, backstop reserve, paused flags |
| Liquidity | JPYdf/USDC v4 pool price / depth, sample sell / buy slippage, LP owner, allowance cleanup |
| Redemption | redemption fee, base rate, routing sample, lowest-rate distribution, urgent redemption state |
| Liquidation | top candidate, min ICR, candidate count, SP offset capacity, bot block lag, receipt status |
| Incidents | pause / cap-freeze owner, liquidator stop / restart condition, public comms owner, status page / app banner state |

No-Go:

- User app and ops dashboard read different stale sources, local fixtures, or legacy snapshots.
- public stats lacks source block / generatedAt / schema version.
- branch health, SP coverage, oracle freshness, backing ratio, liquidity depth, or liquidator scan is unreadable during launch window.
- incident banner / status page / liquidation bot stop-restart runbook are not synchronized.

---

## 5. Evidence Package

Before launch, keep a `mainnet-launch-participant-readiness` evidence package.

| Evidence | Content |
| --- | --- |
| Borrower screenshots / JSON | Borrow UI effective APR, redemption risk, liquidation price, dToken backing / buffer, Zapper route, JPYdf exit liquidity |
| Earn screenshots / JSON | SP APY source, SP coverage, outside debt, branch risk, exit liquidity, and display that SP additional rewards are not implemented |
| Ops dashboard evidence | branch health, oracle, Vault / Strategy, liquidity, redemption, liquidation, incident owner display |
| Public stats JSON | schema version, source block, generatedAt, healthStatus, borrowRatePolicies, branch coverage / backing fields |
| Liquidator evidence | bot config hash, dry-run JSON, gas / loss caps, max submissions per cycle, SP offset capacity, planned batch, receipt policy |
| Route evidence | JPYdf/USDC v4 pool key, sample slippage, LP seed, allowance cleanup |
| Exception log | risk owner, launch owner, expiry, and follow-up issue for any approved exception |

Evidence must not include private keys, raw RPC URLs, unpublished Safe nonces, API keys, or secret personal-account details. Provider information is limited to a label and redacted URL.

---

## 6. Day-2 Backlog Boundary

| Area | Day-2 candidates |
| --- | --- |
| SP incentive | Treasury / SPAdditionalRewardDistributor, campaign budget, Merkl-style combination, auto-compound / claim UX |
| Borrower UX | APR time series, detailed rate-distribution visual, delegation marketplace, advanced redemption simulator |
| Liquidation | profit-seeking model, private relay, RPC quorum, JIT inventory, collateral disposal router, Prometheus / alerts |
| Public transparency | external branch-risk dashboard, historical APY / liquidation PnL, status page integration |
| Liquidity | JPYdf/USDC v4 depth ramp; additional routes require separate audited route policy. Curve / Balancer / direct USDT・USDS・WETH・XAUT pools are not defaults |

---

## 7. Close / Continue Criteria

Participant readiness can be treated as solved for Day-1 once:

1. this runbook is merged and referenced from the Frontend spec, data-source ledger, and launch operation gate;
2. Borrow / Earn / Ops / liquidator evidence can be collected before launch;
3. Day-1 missing items such as SP additional rewards, profit-seeking liquidation, and auto-compound are treated as unimplemented in UI and docs;
4. Day-2 backlog is split into individual issues and not confused with Day-1 launch blockers.

Unfinished Day-2 backlog is not itself a Day-1 close blocker. It becomes No-Go only if UI, runbooks, or marketing copy present an unimplemented item as implemented.
