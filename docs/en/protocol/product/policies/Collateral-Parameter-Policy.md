# JPY DeFi Collateral Parameter Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/product/policies/Collateral-Parameter-Policy.md`](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md)
> is authoritative if this file conflicts with it.

| Field | Value |
| --- | --- |
| Domain | Protocol |
| Lifecycle | Evergreen |
| Artifact Type | Policy |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Status | Active |

## 1. Purpose and boundary

This document defines the inputs and criteria by which the risk parameters of a
collateral branch and the operating parameters of the dToken layer are selected
and changed, whether activating a new collateral or changing a parameter after
launch.

The [Parameter Catalog](../../../../jp/protocol/product/parameters/Parameter-Catalog.md) is authoritative for
what each parameter means, its unit, binding, mutability, and invariants. For
the Ethereum mainnet Day-1 values see [`Parameters.md`](../../../Parameters.md);
for the inputs, derivation rules, exceptions, and reasoning adopted at Day 1 see
the [Day1 Parameter Decision](../../../../jp/protocol/launch/decisions/Day1-Parameter-Decision.md).
This document does not duplicate those Day-1 snapshots.

Individual values, the reasons for adopting them, execution procedures, approval
results, and on-chain readbacks belong to the Decision Record, Manifest, Runbook
/ Gate, and Evidence for the release or change in question.

Oracle, Governance, Bridge, and PIL parameters are owned by their own component
policy or activation package. This document covers only the conditions that
cross into the collateral branch.

## 2. Selecting risk parameters

### 2.1 Required inputs

Before approving a new collateral activation or a risk parameter change, gather
at least the following on the same observation period, time window, and currency
basis:

- Downside move of the collateral price
- Depeg between market price and claim value for wrapped assets, stablecoins,
  RWAs, and similar
- Slippage at the liquidation exit, and the stress multiplier applied when
  liquidity deteriorates
- FX downside against JPY-denominated debt
- Non-price risk: issuer, custodian, transfer restrictions, redemption,
  settlement, queue, market hours, and similar
- Executability of the SP, the JIT liquidator, and the redemption route

Input data, sources, observation period, block of measurement, calculation
sheets, and rejected alternatives are stored in the applicable Decision Record
or Evidence, not duplicated here.

### 2.2 MCR / LLTV

For high-volatility collateral, choose a level at which a position at the
liquidation threshold can still cover its debt and the liquidation penalty out
of collateral after the compound stress that applies until liquidation
completes. When applying this to a new asset class or liquidation route, state
in the Decision Record which stress terms are included and over what observation
window.

```text
MCR = (1 + liquidationPenaltySP)
      / ((1 - priceStress)
         (1 - depegStress)
         (1 - slippageStress × multiplier)
         (1 - fxStress))

LLTV = 1 / MCR
```

For USD stable and structured assets, do not treat the level implied by observed
depeg and FX alone as a mechanical ceiling. Compare it against a separate MCR
floor that reflects structural risk — exit, oracle, wrapper, issuer, custody —
and adopt the more conservative of the two. The specific floor value is approved
in the applicable Decision Record.

For JPY-denominated settlement assets, do not layer FX on top; evaluate against
price, NAV, and settlement stress plus the liquidation penalty. Do not treat
depeg, exit, issuer, or settlement risk as zero merely because the collateral is
denominated in JPY.

### 2.3 CCR / SCR / BCR / liquidation penalty

- CCR is derived as the Recovery Mode boundary at which the branch as a whole
  still does not fall below MCR after the selected stress:
  `CCR = MCR / ((1 - priceStress)(1 - depegStress)(1 - fxStress))`.
- SCR is the boundary at which an irreversible shutdown begins. It must satisfy
  `SCR < MCR < CCR` and the payability of the urgent redemption bonus at the same
  time, and must account for the mis-shutdown risk of a branch whose exposure is
  concentrated in a small number of positions.
- BCR is chosen as the buffer that keeps batch fees and interest-rate changes
  from pushing a position straight into liquidation.
- The Stability Pool penalty is at or above the contract floor and at or below
  the redistribution penalty, and both must be payable out of collateral at MCR.
- Verify the parameter combination against
  [Parameter Catalog §4](../../../../jp/protocol/product/parameters/Parameter-Catalog.md#4-parameter-invariants)
  in deploy preflight and in readback.

### 2.4 Branches whose exact Underlying is undecided

A reserved branch whose exact Underlying is unknown receives bootstrap safety
values at construction that satisfy the Core's mathematical invariants. Those
values are not approval values, an upper-bound envelope, or public display
values for the future collateral. While `riskParamsFinalized == false`, opening
a Trove and making a new or top-up Stability Pool deposit are rejected.

After the exact Underlying is selected, derive all six Core risk parameters
afresh from that asset's stress, oracle, liquidity, exit, legal / custody, and SP
/ liquidator capacity. In one atomic activation ceremony, the common Timelock
binds the Underlying, installs the real PriceFeed source, configures the Vault /
Strategy, finalizes the risk parameters, and opens the cap. All six risk values
are finalized together exactly once; no later change, unfreeze, or rollback to
the old values is permitted.

Finalization requires `cap == 0`, `totalSupply == 0`, zero Troves, debt,
collateral, and Stability Pool deposits, agreement between the dToken and Vault
Underlying, no active oracle-failure pause, and no terminal shutdown. Do not
compensate for incorrect values or partial execution with the cap, an oracle
haircut, or a separate transaction.

## 3. Selecting dToken layer parameters

### 3.1 mintCap

Set or change `PRM-mintCap` on the basis of the collateral's exit liquidity, SP
/ liquidator capacity, oracle confidence, operational readiness, and planned
exposure. It is not JPYdf's global issuance cap, nor a Core branch debt ceiling.

When approving in nominal JPY, take the underlying price before the backing
ratio is applied from the same external legs as the production PriceFeed, and
round so that the cap does not exceed the approved nominal amount. Store the
price, round, block, formula, rounding, and encoded value in the freeze Evidence.

After launch, recompute the nominal JPY exposure of a token-quantity cap when
any of the following occurs:

- A cap-increase proposal is being drafted
- The deviation threshold set by the branch's Decision Record or its most recent
  approved proposal is reached
- The risk owner proposes an exposure reduction

Compute the estimated nominal amount from the current cap quantity and the
underlying price from the same external legs as the production PriceFeed,
without applying the backing ratio. The comparison basis is the nominal amount
recorded in the most recent approved Decision Record, proposal, or execution
Evidence. Express the deviation in bps as
`abs(estimatedCapNotionalJpy - approvedNominalJpy) × 10,000 / approvedNominalJpy`.
The recomputation Evidence retains the price, round, block, formula, rounding,
encoded value, comparison basis, and deviation in bps.

Cap increases follow the
[Active Branch Cap Ramp Runbook](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md).
A cap decrease does not burn existing supply and can only stop new minting, so
state the residual risk explicitly in the proposal and in the execution Evidence.

### 3.2 allocatorCooldown / allocateMaxMove

Set `allocatorCooldown` to restrict repeated operations by a compromised
allocator without obstructing normal allocation to permitted Strategies or
emergency recovery. Do not impose the same wait on the recovery path that
returns assets to the Vault.

`allocateMaxMove` limits the quantity of underlying that a single outbound
allocation can move. A branch that adopts no Strategy does not open outbound
allocation at all. When enabling a Strategy on an inert branch, evaluate the
loss envelope, the recovery route, and keeper capacity separately from the cap,
and approve them in the same activation package.

### 3.3 withdrawDelay / bufferTargetBps / bufferFloor

Derive `withdrawDelay` from the worst-case recovery period across underlying and
Strategy withdrawal, settlement, queue, and lock. When an async Strategy is
adopted, do not reuse the value from a synchronous-recovery or no-Strategy
configuration.

Choose `bufferTargetBps` and `bufferFloor` as the combination that secures
`requiredBuffer` under [Parameter Catalog](../../../../jp/protocol/product/parameters/Parameter-Catalog.md)
`PRM-INV-007` against redemption demand and recovery delay.

Set `bufferFloor` only where a proportional buffer is insufficient in absolute
terms at small TVL. Re-evaluation triggers are: a sustained buffer shortfall,
`pendingWithdrawals > bufferBalance`, a change in the recovery period, and any
change that makes redemption the primary peg exit.

## 4. Decision, execution, and verification

A proposal for a new value or a value change records, in the Decision Record,
which parts of this policy applied, the inputs used, the alternatives, the
exceptions, and the re-evaluation triggers. Information boundaries between
artifacts follow
[Document Governance](../../../../jp/Document-Governance.md#4-artifact-type--文書の役割).

A GOV-mutable parameter becomes the current value only once Timelock execution
and a block-stamped readback are both complete. For Day-1 active-branch Core risk
parameters, reconcile the Catalog invariants against the Manifest's encoded
values before broadcast. For a `RESERVED` branch, first verify the deployed
bootstrap-value readback and `riskParamsFinalized == false`. The values become
final only after approval of the collateral-specific activation Manifest,
Timelock execution, confirmation that all six Registry values match the
BorrowerOperations / TroveManager consumer copies, and a block-stamped readback
of `riskParamsFinalized == true`.
