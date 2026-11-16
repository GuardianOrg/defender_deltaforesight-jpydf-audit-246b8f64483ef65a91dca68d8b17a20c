# Liquidity Management Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/operations/policies/Liquidity-Management-Policy.md`](../../../../jp/protocol/operations/policies/Liquidity-Management-Policy.md)
> is authoritative if this file conflicts with it.

## 0. Positioning

This document defines the post-launch self balance-sheet management policy for the
JPYdf/USDC Uniswap v4 LP: selected management infrastructure, range design,
rebalance logic, and bot implementation policy.

The source documents for launch amounts and route boundaries are:

- [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md)
  for the committed Day-1 company balance-sheet amounts
- [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)
  for their calculation basis
- [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)

This document is not the source of truth for launch broadcast, Safe role
assignment, or fork evidence. Running IPOR Fusion / the ALPHA bot on Day 1
requires the activation gate below and the evidence packages in
[`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md),
[`Mainnet-Initial-Configuration-Checklist.md`](../../launch/gates/Mainnet-Initial-Configuration-Checklist.md),
and [`Mainnet-Safe-Role-Assignment-Gate.md`](../../launch/gates/Mainnet-Safe-Role-Assignment-Gate.md).

## 1. Design Policy

The LP strategy must protect the user swap experience while limiting IL on the
company balance sheet.

| Constraint | Value |
| --- | --- |
| LP structure | Multiple positions separating user depth, inventory, and unwind needs |
| Annual IL ceiling | 10% |
| Swap-depth metrics | Price move at 0.1% / 0.5% / 1.0% |

The 0.1% depth represents normal user UX and micro peg defense. The 0.5% depth
maps to the Liquity v2 base redemption-fee line, so keeping depth around that
level helps reduce economically rational third-party redemptions.

## 2. Infrastructure Direction: IPOR Fusion

The preferred LP management infrastructure is IPOR Fusion, with the rebalance
logic implemented by an in-house ALPHA bot.

This is a conditional adoption direction. Until the Uniswap v4 LP fuse, Plasma
Vault deployment, role assignment, bot configuration, and fork evidence are all
ready, IPOR Fusion / ALPHA bot operation is not a Day-1 launch PASS condition.
If the gate is not met, Day 1 starts with the existing Safe-controlled,
manual/static JPYdf/USDC Uniswap v4 LP managed by `LP_OWNER`; IPOR Fusion is then
a post-launch activation.

| Item | IPOR Fusion | Arrakis Pro |
| --- | --- | --- |
| Management fee at JPY 100m LP | 0.3% = JPY 300k/year | Retainer about USD 5,000/month |
| Performance fee | 2% | Separate |
| Range logic | In-house via ALPHA role | Delegated to Arrakis |
| Uniswap v4 fuse | Request-based implementation; activation-gated until public evidence / fork evidence exists | Existing |

An AWS-only bot / signer that directly manages LP positions is a different
design, not a drop-in substitute for IPOR Fusion. AWS is appropriate for KMS /
HSM signing, scheduling, monitoring, private relays, and alerts, but AWS by
itself does not provide on-chain custody boundaries, allowed-action constraints,
asset / venue allowlists, share accounting, role revocation, or pause controls.

| Dimension | IPOR Fusion + AWS bot | AWS-only direct LP manager |
| --- | --- | --- |
| Custody / execution boundary | Plasma Vault, fuses, and roles constrain allowed actions on-chain and keep the ALPHA key scoped to LP management | Depends on bot key, Safe module, or custom executor design; hot-key authority can become too broad if misconfigured |
| Asset / venue limits | Substrate / asset list / fuse allowlist can restrict funds to JPYdf / USDC and the frozen pool key | Depends on off-chain config and signer operations unless a separate on-chain allowlist is built |
| Accounting / auditability | Vault, position, and fuse-call evidence are easier to reconcile on-chain | Relies on custom ledgers, bot logs, and Safe transaction reconciliation; custom audit surface increases |
| Emergency control | OWNER / ATOMIST / GUARDIAN / ALPHA revoke / pause role model is available | Equivalent controls must be built through Safe modules, custom contracts, and runbooks |
| Implementation risk | Uniswap v4 fuse readiness and IPOR dependency are activation-gated | Custom executor / custody / accounting must be audited in-house, expanding Day-1 scope |

The reason to use IPOR is therefore not to avoid AWS. AWS remains the execution
platform for the ALPHA bot; IPOR narrows what the bot can do with funds on-chain.
If the IPOR Uniswap v4 fuse, roles, and fork evidence are not ready, the fallback
is Safe-controlled manual/static LP, not an unreviewed AWS-only automated LP
manager.

## 2.1 Day-1 Activation Gate And Fallback

IPOR Fusion / ALPHA bot can run on Day 1 only if the following evidence is ready:

1. **Uniswap v4 fuse readiness**: The fuse set supports new position, modify,
   collect, withdraw, and required swap operations for the JPYdf/USDC v4 LP; the
   commit, bytecode, deployed addresses, internal review, and fork-run evidence
   are retained.
2. **Vault readiness**: The Plasma Vault accepts only JPYdf / USDC as assets and
   cannot move funds to unexpected tokens, venues, or hooks in fork testing.
3. **Role readiness**: OWNER, ATOMIST, GUARDIAN, FUSE_MANAGER, ALPHA, and
   WHITELIST holders, Safe thresholds, pause / cancel / revoke flows, and
   on-chain readbacks are included in the Safe role assignment package.
4. **Bot readiness**: The ALPHA key is managed through AWS KMS or HSM; bot config
   hash, tx relay, max recenter, max withdraw, cooldown, emergency stop, and
   alert path are evidenced.
5. **Route readiness**: The JPYdf/USDC Uniswap v4 pool uses `fee = 500`,
   `tickSpacing = 10`, and no hook, with pool key, route config, and allowance
   cleanup frozen.
6. **Operational readiness**: Fair FX anchor / pool price / TWAP / protocol
   oracle sources and cross-divergence guards, per-position reconciliation,
   recenter / swap / redemption / borrow action selection, short-horizon
   order-flow / inventory modeling, rebalance / redemption / liquidation
   monitoring priority, manual intervention, and incident owners are included
   in runbooks.

If any item is missing, Day 1 does not run IPOR Fusion / ALPHA. The launch scope
is limited to JPYdf/USDC v4 liquidity evidence and `LP_OWNER` management. The beta
parameters below remain the first post-launch activation candidate.

## 3. Initial Parameters

Backtesting on five years of daily USD/JPY data selected the beta candidate as
the initial parameter set after the activation gate passes. The fee assumption is
the Day-1 route standard: `fee = 500`, `tickSpacing = 10`, and no hook.

| Item | Value |
| --- | --- |
| Tier 1 range | +/-0.5% |
| Tier 2 range | +/-9% |
| Tier 1 allocation | 15% of JPY 100m LP (= JPY 15m equivalent) |
| Recenter trigger | 70% of range edge (= +/-0.35% / +/-6.3%) |
| Recenter cooldown | Tier 1: 1 hour; Tier 2: 24 hours |
| Emergency stop | Pause bot + alert if price moves 1% within 1 hour |

Tier 1 / Tier 2 are backtest liquidity-shape parameters, not constraints on the
number of production LP positions. The actual MM bot position count is set from
user-depth, inventory, unwind, and operational evidence as described below.

Backtest results:

| Metric | Value |
| --- | --- |
| Annual IL | -6.94% |
| Swap size to move price 0.1% | About JPY 1.08m |
| Swap size to move price 0.5% | About JPY 5.22m |
| Swap size to move price 1.0% | About JPY 7.57m |
| Recenter frequency | About 131/year |

## 4. Candidate Comparison

The search process used a grid across Tier 1 range, Tier 2 range, Tier 1
allocation, and threshold, then filtered by the 10% IL ceiling, walk-forward
robustness, and Pareto efficiency across IL and depth. The beta candidate is the
balanced activation candidate.

| Candidate | Tier 1 | Tier 2 | T1 allocation | Threshold | Annual IL | 0.1% depth | 0.5% depth | Recenter/year | Policy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| alpha | +/-2.0% | +/-10% | 5% | 60% | -4.18% | JPY 0.49m | JPY 2.45m | 36 | Low ops load |
| beta | +/-0.5% | +/-9% | 15% | 70% | -6.94% | JPY 1.08m | JPY 5.22m | 131 | Balanced |
| gamma | +/-0.2% | +/-8% | 20% | 80% | -8.94% | JPY 2.27m | JPY 5.88m | 194 | Depth-heavy active |

## 5. Rebalance And Reconciliation Logic

The ALPHA bot must not blindly chase pool price. JPYdf/USDC pool price can be
distorted by flow, redemption pressure, thin liquidity, or a single large swap.
Re-centering around that distorted price can ratify a depeg. The range center is
the fair FX anchor (JPY/USD or USD/JPY reference); pool spot / TWAP is used to
measure deviation and execution slippage.

The LP manager is a market maker with JPYdf / USDC inventory, not only a range
bot following a chart. If the AMM hedges or rebalances mechanically in the same
pool immediately after receiving user flow, it can lock in adverse selection. For
example, the AMM may buy USDC from a user and then see the fair value of USDC
fall in the next block, leaving the manager with bad inventory. Production
operation must therefore compare natural offset, Liquity-native redemption /
borrow / self-mint, manual top-up, and bounded pool swaps instead of assuming
that every inventory problem is solved by a swap.

Price inputs are separated as follows:

| Input | Role | Activation treatment |
| --- | --- | --- |
| Fair FX anchor | Center price for LP ranges, derived from JPY/USD or USD/JPY reference together with the USDC/USD reference | Source, freshness, fallback, and operator sign-off are frozen in activation evidence. Do not recenter when stale or inconsistent |
| USDC/USD reference / stablecoin health | Determines whether USDC can be treated as 1 USD or whether USDC depeg must be reflected in fair price and inventory risk | USDC/USD source, depeg threshold, stale threshold, and fallback are frozen. Stop recentering and bounded swaps when stale or depegged |
| Pool spot / TWAP | Market deviation, swap slippage, MEV / manipulation signal | If materially away from fair anchor, do not recenter; pause or send to manual review |
| Core oracle / protocol state | Redemption / liquidation / branch health input | Not the LP center price; used for action selection. Divergence from the fair anchor is monitored as a risk limit; on breach, recentering and bounded swaps stop pending manual review |

The fair FX anchor and the protocol oracle prices (`fetchPrice` /
`fetchRedemptionPrice`) can diverge by design. As specified by
[`SYS-RISK-001`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-001),
the protocol oracle soft-freezes on `lastGoodJpyRate` for up to 24 hours during a JPY/USD
feed failure. Redemption proceeds are valued at the protocol oracle price, so
while the divergence exceeds its limit the bot must not treat JPYdf as cheap
against the fair anchor alone, and must stop recenter / bounded-swap /
redemption comparisons pending manual review.

The MM bot is expected to hold multiple LP positions. A single position cannot
cleanly handle user slippage, peg defense, inventory skew, and unwind at the same
time; moving all liquidity for every range change can worsen slippage, MEV,
realized IL, and accounting opacity.

Tier 1 / Tier 2 in this document describe the liquidity shape used for
backtesting; they do not impose a fixed production position count. The
actual number of positions is set in activation evidence based on user-facing
depth, inventory skew, natural-offset waiting, hedging, unwind needs, and gas /
accounting load. Splitting passive wide, active narrow, intervention-only, and
unwind buckets is natural, but each additional position must have an explicit
purpose, limit, and stop condition.

The operator constraint is not only minimizing company-balance-sheet IL. The
JPYdf/USDC pool is the main user swap route, so position design must protect user
slippage and route integrity. Removing active narrow liquidity, creating
inventory skew, or hedging through pool swaps must not break effective user
depth, 0.1% / 0.5% depth, fair-anchor deviation limits, or route best execution.
A position update that breaches user slippage guards is not ALPHA-automatable
even if it is favorable for the company balance sheet.

Each position tracks at least:

- position id / owner / vault / tick range / liquidity / token0-token1
  composition
- intended role (micro peg defense, wide passive depth, intervention, unwind,
  etc.)
- initial notional, current notional, uncollected fees, realized fee, realized
  IL
- expected user depth contribution (0.1% / 0.5%), slippage guard, withdraw /
  resize limit
- last recenter, last collect, last rebalance tx, and absence of unexpected
  tokens / allowances / hooks

Before any action, the bot reconciles Vault balances, LP positions, pending fees,
allowances, pool key, fair FX anchor, and pool spot / TWAP. If expected inventory
or position state differs from on-chain readback beyond configured thresholds,
ALPHA stops and alerts the operator.

Minimum reconciliation checks:

- The Vault holds nothing other than JPYdf / USDC, or any exception is
  evidenced.
- Per-position token composition, uncollected fees, and liquidity are
  continuous with the previous report.
- User-facing 0.1% / 0.5% depth and slippage guards stay above their floors
  after the position update.
- The JPYdf / USDC inventory required for the recenter matches idle balances
  and expected post-withdraw amounts.
- The pool key matches `fee = 500` / `tickSpacing = 10` / no hook.
- The fair FX anchor and USDC/USD reference are not stale, outliers, or
  depegged.
- Max amounts, max slippage, and operator approvals for swaps / redemptions /
  borrows used in LP operations are within configured bounds.

Inventory adjustment is not assumed to be a pool swap. The JPYdf/USDC pool is
the only external execution venue, but DeltaForesight also has dUSDC / dwstETH
branches, bootstrap Troves, redemption paths, and SP operations. When dUSDC is
available, sourcing JPYdf through a healthy dUSDC Trove can be cheaper than
buying JPYdf from the pool. When JPYdf trades below fair value, redemption can
also be cheaper than swapping after accounting for redemption fee, received
collateral, dToken unwrap, disposal route, and timing risk.

Redemption is not a way to choose arbitrary dUSDC collateral. It depends on
branch allocation, unbacked portions, `minColl`, oracle freshness, shutdown
state, and dToken / underlying disposal. Borrow / self-mint also worsens debt,
ICR / LTV, rate, upfront fee, redemption ordering, and cap headroom. These are
inventory sourcing alternatives that may beat pool swap; they are not automatic
bot actions without separate evidence.

The operator / bot compares all-in cost and risk:

| Action | Use case | Main cost / risk | Day-1 permission boundary |
| --- | --- | --- | --- |
| Natural offset / wait | Inventory is within risk limits and near-term opposite flow is likely | Fair FX / pool movement while unhedged, inventory-limit breach | ALPHA may only wait; not allowed after risk-limit breach |
| LP modify only | Fair anchor remains within range and inventory is sufficient | Gas and accounting | ALPHA may execute |
| Pool swap | Small inventory imbalance while pool price is close to fair anchor | Pool fee, slippage, MEV, depeg ratification | ALPHA may execute only with max swap, slippage, and fair-deviation guards |
| Redemption | JPYdf trades below fair value and redemption is cheaper than swapping after fees and collateral disposal | Redemption fee, branch allocation, dToken / underlying disposal, oracle / shutdown, collateral price risk, timing | Safe / manual on Day 1. ALPHA automation requires a separate audit / runbook |
| Additional borrow / self-mint | Sourcing JPYdf from a healthy dUSDC / dwstETH Trove is cheaper than buying it from the pool | More debt, lower ICR / LTV, upfront fee, redemption ordering, cap / collateral availability | Safe / manual on Day 1. ALPHA cannot execute |
| Manual top-up / withdraw | Large flow, Company A handling (= the Japanese DAT company in [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)), emergency peg defense, bot pause | Signer availability, accounting owner, repayment / unwind plan | Safe / manual |

Standard flow:

1. **Stop / stale check**: pause when the fair FX anchor is stale, USDC/USD is
   stale or depegged, pool spot is materially away from fair anchor, the fair
   anchor and protocol oracle prices diverge beyond the configured limit, price
   moves 1% or more within one hour, or oracle / route / role readback is
   abnormal.
2. **Reconcile**: verify Vault balances, LP positions, idle balances, pending
   fees, allowances, and expected inventory.
3. **Classify need**: range recenter, inventory imbalance, peg defense, or large
   flow handling.
4. **Check order flow**: decide whether recent flow is toxic, whether near-term
   natural offset is likely, and whether inventory limits have room.
5. **Compare actions**: wait, LP modify, pool swap, redemption, additional borrow
   / self-mint, and manual top-up. ALPHA is limited to wait, LP modify
   (including fee collect), and bounded pool swap.
6. **Execute and report**: record LP state, realized IL, fees, borrow /
   redemption / swap cost, inventory delta, and adverse-selection cost.

The beta range / threshold is only an initial liquidity shape, not sufficient
evidence for a production market-making bot. A live bot must estimate at least:

| Forecast target | Purpose | Action usage |
| --- | --- | --- |
| Probability of opposite flow in the next block (about 12 seconds) | Decide whether to hedge in the next block or wait for natural offset | Wait if probability is high and inventory is within limits; hedge or escalate if low or fair FX is moving the same way |
| Expected natural offset over the next few blocks (within about a minute) | Avoid over-hedging consecutive small flows through pool swaps | Delay LP modification / hedge if expected offset absorbs enough imbalance |
| Net customer flow over the next tens of blocks (a few minutes) | Decide target JPYdf / USDC inventory and liquidity skew | Compare range, inventory, borrow, and redemption actions when flow is one-sided |

Horizons are defined in blocks, not seconds. On-chain swap events are only
observable at block granularity (about 12 seconds) and the bot executes per
block through the private relay, so sub-block prediction and hedging are not
assumed. Concrete block counts are calibrated in Phase 1 replay at block
granularity.

Candidate inputs:

- JPYdf/USDC pool swaps: direction, size, execution price, fee, wallet / route
  aggregates
- Fair FX anchor and short-term changes
- USDC/USD reference and stablecoin depeg / liquidity signal
- Pool spot / TWAP deviation from fair anchor
- Per-position token composition and idle inventory
- Redemption activity, base rate, branch unbacked, dUSDC / dwstETH borrow capacity,
  and SP coverage
- Gas, mempool / private relay state, recent failed transactions / reverted
  quotes

Minimum risk limits:

- JPYdf / USDC inventory delta
- Expected loss over 1-block / few-block / tens-of-blocks horizons
- Pool deviation from fair anchor
- Fair-anchor / protocol-oracle price divergence limit
- USDC/USD depeg / stale guard
- Single-action max notional, max slippage, max borrow, and max redemption
- Kill switch for repeated same-direction flow

Before production activation, trade-level replay must measure `natural offset
rate`, `adverse selection cost`, `hedge cost`, `inventory limit breach`, and
`realized IL + fee`. A daily USD/JPY LP-range backtest is not enough evidence for
the hedge / rebalance policy of a production market-making bot.

Beta thresholds apply to the fair FX anchor, not raw pool price:

1. Recenter Tier 1 when the fair FX anchor moves at least +/-0.35% from Tier 1
   center, at least one hour has elapsed, and pool spot / TWAP is within allowed
   deviation from fair anchor.
2. Recenter Tier 2 when the fair FX anchor moves at least +/-6.3% from Tier 2
   center, at least 24 hours have elapsed, and pool spot / TWAP is within allowed
   deviation from fair anchor.
3. If pool spot / TWAP deviates materially from fair anchor, do not recenter; send
   the state to peg-defense / redemption / borrow / manual top-up action
   selection.
4. Run a daily health inspection for per-position state, recenter history,
   cumulative IL, fee income, pool deviation, fair-anchor freshness, inventory
   delta, and alert conditions.

## 6. Cost Structure

Annual cost estimate for the beta candidate:

| Item | Amount |
| --- | --- |
| IL | About JPY 6.94m (= 6.94%) |
| Gas | About JPY 0.34m (= 0.34%) |
| DEX swap fee | About JPY 0.66m (= 0.66%) if bounded swaps are used, based on `fee = 500` / PR #643 |
| IPOR Fusion management fee | About JPY 0.30m (= 0.3%) |
| IPOR Fusion performance fee | Variable, 2% of gains |
| Reference total under beta / IPOR / bounded-swap assumptions | About JPY 8.24m (= 8.24%) |

The reference total assumes IPOR activation and bounded swaps. It is not a normal
expected cost, not a fixed operating cost, and not the cost of every inventory
adjustment path.

LP fee income is not included in this estimate. An existing Uniswap pool's fee
tier cannot be changed after creation. If a third party creates another
JPYdf/USDC pool at a different fee tier such as 0.3%, that is a separate pool
with a separate pool key, and the risk is route fragmentation or routing
migration rather than an in-place fee change. The operations bot must target only
the pool key frozen in activation evidence; using another pool requires a
separate route-policy, pool-key, depth, fee, MEV, and LP-accounting review. Pool
swap fee is a cost of the swap action, not a fixed inventory-management route;
production operation compares swap, redemption, additional borrow / self-mint,
and manual top-up.

## 7. Known Limitations

- USD/JPY daily data is a proxy. Actual JPYdf/USDC price also reflects supply,
  redemption pressure, and user behavior.
- The five-year period is a strong yen-depreciation period; yen-appreciation and
  major depeg regimes are not fully covered.
- LP fee revenue, redemption interaction, multi-path Monte Carlo, and MEV /
  sandwich costs are not modeled.
- Fair FX anchor versus pool-price separation is not modeled. The backtest uses
  the USD/JPY path as the center and does not cover depegged pool states,
  pause/review behavior, redemption, borrow, or manual top-up action selection.
- USDC depeg is not modeled. The backtest treats USDC as 1 USD and does not cover
  fair-anchor changes, bad inventory, or manual unwind when USDC/USD departs from
  1.
- Inventory sourcing alternatives are not modeled. In production, additional
  borrow / self-mint, redemption, or manual top-up can be cheaper than a pool
  swap, but they add debt, redemption, accounting, and signer risk and are not
  ALPHA-automated until separate evidence exists.
- Market-making order flow is not modeled. The backtest does not estimate
  adverse selection, probability of opposite flow in the next block, natural
  offset over the next few blocks, or net customer flow over tens of blocks.
  The daily FX path backtest evaluates liquidity shape, not a production hedge
  / rebalance policy.
- Production behavior must be validated after launch or post-launch activation.

## 8. IPOR Fusion Vault And Bot Policy

When the activation gate passes, IPOR Fusion Plasma Vault is used with role-based
access control. Main roles follow the IPOR Fusion `Roles.sol` definitions:

| Role | Main power | Expected holder at activation |
| --- | --- | --- |
| OWNER | Highest-level owner / role management | Company multisig |
| ATOMIST | Vault configuration, fuse manager appointment, whitelist management | Company multisig |
| GUARDIAN | Emergency pause and timelocked operation cancel | Company multisig |
| FUSE_MANAGER | Add / remove / balance / reward fuses | Under ATOMIST control |
| ALPHA | Execute rebalance fuse calls through `PlasmaVault.execute(...)` | Bot EOA signed by AWS KMS or HSM |
| WHITELIST | Private vault deposit / withdraw control | Company-only during private phase |

OWNER / ATOMIST / GUARDIAN are multisig-held. ALPHA is a bot key but is bounded
by ATOMIST-configured daily withdraw / rebalance limits and must have a documented
revoke path.

Bot implementation is TypeScript / Node.js, aligned with existing backend
tooling. Execution uses AWS Lambda or ECS Fargate, Flashbots Protect or an
equivalent private relay, monitoring dashboards, and Slack / PagerDuty alerts.
The bot observes fair FX anchor, USDC/USD reference, pool spot / TWAP, Vault
balances, LP positions, idle inventory, customer flow, and redemption / borrow
state before building fuse calls. Redemption, additional borrow, and self-mint
are manual Safe actions on Day 1, not ALPHA actions, even when they are cheaper
than a pool swap. The production bot is not considered ready until config hash,
key holder, limits, reconciliation, order-flow model, action-selection, and
revoke procedures are evidenced.

At activation, the vault starts as private. WHITELIST allows only company wallets.
Public vault migration is a separate business decision and requires a separate PR
or issue covering third-party deposit terms, fee recipients, and redemption-window
transparency.

## 9. Implementation Plan And Roadmap

The beta parameters define the initial LP liquidity shape; they are not, by
themselves, the production bot implementation specification. Production
activation must make position count, user slippage guards, redemption / borrow /
self-mint permission boundaries, and the IPOR + AWS responsibility split explicit
in activation evidence.

| Phase | Active scope | Main artifacts | PASS condition |
| --- | --- | --- | --- |
| 0. Manual / static launch | Safe-controlled static LP managed by `LP_OWNER`; no ALPHA bot | Pool key / route / allowance cleanup, fair FX anchor, USDC/USD health source, initial LP position evidence | `fee = 500`, `tickSpacing = 10`, no hook, route config, and Safe owner are recorded in launch gates |
| 1. Read-only shadow | Bot only observes and reports; no transactions | State service, dashboard, daily report, alert dry-run | Fair anchor, USDC health, pool spot/TWAP, pool token composition, swap flow, LP positions, `baseRate`, redemption volume, branch unbacked, SP coverage, and borrow capacity can be reconciled at the same timestamp |
| 2. IPOR LP-only canary | Private Plasma Vault + ALPHA; automated actions are limited to wait / LP modify / collect / bounded pool swap | Uniswap v4 fuse evidence, role readbacks, KMS/HSM signer, private relay, position registry, reconciliation tests | After each action, user-facing 0.1% / 0.5% depth, route integrity, max slippage, and fair-anchor deviation guards remain satisfied. Redemption / borrow / self-mint are not executed |
| 3. Manual inventory / peg-defense integration | Comparator evaluates redemption / borrow / self-mint / manual top-up, but execution remains Safe / manual | Runbook, Safe calldata templates, all-in cost report, incident owner | Redemption cost includes `baseRate + 0.5% floor`, baseRate spikes, branch-unbacked proportional routing, mixed received collateral, and dToken unwrap / disposal cost |
| 4. Post-evidence automation candidate | Consider partial automation for redemption / borrow / self-mint | Separate issue / PR, fork evidence, audit / runbook, kill switch | Phase 1-3 live data shows the path is safer and cheaper than pool swap, with audited permission boundaries and loss caps |

From Phase 1 onward, the state service is shared by the LP bot, Peg Defense
Orchestrator, and redemption / borrow runbooks. BOLD empirical data (#854) shows
that redemption uses `baseRate + 0.5% floor`, baseRate can rise exactly when the
path is most attractive, and received collateral is mixed by branch-unbacked
routing. Therefore the LP bot must not automatically redeem simply because JPYdf
is cheap during Day 1 / canary; it may only use that as a manual-escalation
reason.

Pool token composition is an alert signal. BOLD data showed pool composition
moving materially before large price deviations, so JPYdf/USDC should monitor
`JPYdf share` / `USDC share`. However, composition depends on the fair FX anchor,
USDC/USD health, and LP range placement, so it is not a recentering center. The
thresholds are recalibrated from live launch data.

Implementation work is split as follows:

1. **State / data**: collect fair FX anchor, USDC/USD, pool spot/TWAP, pool token
   composition, swap flow, LP positions, redemption activity, `baseRate`, branch
   unbacked, SP coverage, and borrow capacity under one schema.
2. **Policy engine**: implement stop / stale checks, position guards, user-depth
   guards, action comparator, and manual-escalation reasons as pure functions and
   validate them with trade-level replay.
3. **Executor**: implement IPOR fuse-call builder, bounded pool swap, private
   relay, KMS/HSM signing, config hash, role readbacks, emergency pause, and
   revoke. AWS-only direct LP management is not the fallback.
4. **Evidence / runbook**: attach fork runs, dry runs, dashboard, daily reports,
   Safe calldata templates, and incident logs to launch / activation gates.

- **Day 1 to Day 7**: If the gate is missing, remain in Phase 0. If the gate
  passes, run Phase 2 canary with small notional and strict limits.
- **Day 7 to Day 30**: Use Phase 1 / 2 live data to measure `natural offset rate`,
  `adverse selection cost`, `hedge cost`, `inventory limit breach`, and
  `realized IL + fee`; adjust beta parameters, guards, and position count.
- **After Day 30**: Evaluate dynamic range adjustment, market-making order-flow
  modeling, partial redemption / borrow automation, LP fee revenue modeling,
  Monte Carlo follow-up work, and the other limitations in §7 through separate
  PRs / issues.

## 10. Related Issues / PRs

- Issue #318: liquidity management policy
- Issue #396: annual IL ceiling
- Issue #630 / PR #643: JPYdf/USDC Uniswap v4 fee tier (`fee = 500` /
  `tickSpacing = 10` / no hook)
- Issue #617: self-mint WETH / USDC hedge strategy
- Issue #558: large-borrower redemption avoidance
- PR #854: BOLD depeg / redemption empirical review
- PR #266: original B/S allocation policy
