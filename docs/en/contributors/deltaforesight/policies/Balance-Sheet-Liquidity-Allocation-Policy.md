# B/S Liquidity Allocation, Deployment Venue, and Buffer Policy

## 0. Positioning

This document is a design memo that handles the policy governing B/S liquidity allocation by **splitting it across two management surfaces**. The two are managed separately because **the deciding party and the granularity differ** ((A) is the company's own funds, hence at the **sole discretion of DeltaForesight Inc.** [off-chain, management decision]; (B) is a public protocol parameter, hence governed by the **Foundation / governance (later by vote)** [decentralized governance]).

- **(A) Company B/S actions (off-chain, deployment of own funds)** — The part where the company (the corporation) "creates" Day-1 initial liquidity with its own funds (DEX LP supply, initial JPYdf mint, pre-funded SP deposit, backstop deposit). The decider is **DeltaForesight Inc. (decided unilaterally as discretion over its own funds)**, and it is reflected via tx. **The authoritative source for concrete allocation amounts and rationale is [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)**.
- **(B) Protocol parameters (on-chain, configuration for Day-1 liquidity)** — The per-branch params the protocol sets for Day-1 liquidity (mintCap, buffer, Strategy cap/weight, allocateMaxMove, withdrawDelay). The decider is the **Foundation / governance (GOV multisig / Timelock, later governance vote)**, and they are frozen at deploy / handover. **The authoritative source for the values is [`../../Parameters.md`](../../../Parameters.md)** (this document does not restate the values).

Cross-cutting references: for the DEX route see [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md); for liquidation backstop / JIT terminology and boundaries see [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md); for whether a Strategy may be adopted see [`Collateral-Asset-Management-Policy.md`](../../../protocol/operations/policies/Collateral-Asset-Management-Policy.md); for Safe retention accounting see [`Treasury-Safe-Retention-Runbook.md`](../../../protocol/operations/runbooks/Treasury-Safe-Retention-Runbook.md).

---

## A. Company B/S Actions (off-chain, deployment of own funds)

The part where the company creates Day-1 initial liquidity with its own funds (B/S). **The decision on amounts and allocation is made unilaterally by DeltaForesight Inc. (as discretion over its own funds) and executed via tx (mint, LP, SP deposit, backstop deposit).** The authoritative source for the finalized amounts and rationale is [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../commitments/Day1-Self-BS-Initial-Liquidity-Plan.md).

### A-1. Buckets (deployment destinations for company funds)

| Bucket | Funding source | Execution means | Notes / authoritative source |
| --- | --- | --- | --- |
| JPYdf/USDC LP seed | USDC from the B/S + self-minted JPYdf | Uniswap v4 position | Not dToken backing / Vault buffer. route = [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md), amount = [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) |
| Initial JPYdf mint (operator self-mint) | Mint at Core using USDC / wstETH from the B/S as collateral | `openTrove` (dToken collateral) | Source of JPYdf for the LP seed / pre-funded SP. amount = [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) |
| Pre-funded SP deposit | Self-minted JPYdf | `StabilityPool.provideToSP` | Deposited into each branch SP at launch. terminology / boundaries = [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) |
| Backstop deposit | Deposit the target Underlying from the B/S | `backstopDeposit()` | Protected reserve. Turning it into ordinary redeem / claim funding normally requires GOV's `releaseBackstopToBuffer()` (mechanism is B-2) |
| JIT / SP top-up capacity | JPYdf / USDC from the B/S or an MM | Non-atomic `provideToSP` (manual / bot-assisted) | **This is operational planning capacity, not a contract guarantee.** JPYdf/USDC LP helps with sourcing but does not guarantee liquidation execution or SP replenishment. authoritative source = [`Liquidation-Backstop-And-JIT-Policy.md`](../../../protocol/operations/policies/Liquidation-Backstop-And-JIT-Policy.md) |

### A-2. Execution discipline (off-chain)

1. Make the **JPYdf/USDC Uniswap v4 LP** the first external liquidity. Consolidate direct pools into USDC only, and do not create JPYdf direct pools for USDT / USDS / WETH / XAUT ([`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md)).
2. **Keep the backstop separate as an insurance bucket.** Backing improves the moment it is deposited, but converting it into ordinary redeem / claim liquidity requires GOV to explicitly execute `releaseBackstopToBuffer()`.
3. **Do not conflate LP and backstop.** The JPYdf/USDC v4 LP is market funding for price discovery and entry/exit liquidity; it does not directly repair the Vault's 1:1 dToken claim. Repair is done via the target Underlying's `backstopDeposit()`.
4. **Do not put B/S funds directly into a Strategy** (do not mix with backing). When repairing from the B/S, convert into the target Underlying and use `backstopDeposit()`.

---

## B. Protocol Parameters (on-chain, configuration for Day-1 liquidity)

The per-branch params the protocol sets for Day-1 liquidity. **The authoritative source for the values is [`../../Parameters.md`](../../../Parameters.md)** (this document does not restate the values). The decision rests with the **Foundation / governance (GOV multisig / Timelock, later governance vote)**, and setting / freezing is done via the handover runbooks (`PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover`).

> **The Vault liquid buffer and Strategy allocation are funded by user deposits** and are the part the protocol controls via params; they are not the company's free B/S funds (A) (they are the funding for the dToken holder's claim; not treated as free B/S funds).

### B-1. Target parameters (values are in Parameters.md)

| Parameter | Role | env / setter | Authoritative source |
| --- | --- | --- | --- |
| `DF_DTOKEN_CAP_i` (mintCap) | dToken supply / collateral exposure cap | `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` | [`../../Parameters.md`](../../../Parameters.md) |
| `DF_BUFFER_TARGET_BPS_i` / `DF_BUFFER_FLOOR_i` | Vault liquid buffer (claim reserve) | `CollateralVault.setBufferConfig()` | [`../../Parameters.md`](../../../Parameters.md) |
| `DF_STRATEGY_CAP_i` (/ `_i_j`) / `DF_STRATEGY_WEIGHT_BPS_i` (/ `_i_j`, total ≤ 10000) | Strategy allocation cap / ratio | `DeployLiquity2` / `CollateralVault.addStrategy()` | [`../../Parameters.md`](../../../Parameters.md) / [`Collateral-Asset-Management-Policy.md`](../../../protocol/operations/policies/Collateral-Asset-Management-Policy.md) |
| `DF_ALLOCATE_MAX_MOVE_i` | Per-allocate cap | `CollateralVault.setAllocatorConfig()` | [`../../Parameters.md`](../../../Parameters.md) |
| `DF_WITHDRAW_DELAY_i` | Wait for delayed redemption | `CollateralVault.setWithdrawDelay()` | [`../../Parameters.md`](../../../Parameters.md) |
| `DF_ALLOCATOR_COOLDOWN_i` | Allocate cooldown | `CollateralVault.setAllocatorConfig()` | [`../../Parameters.md`](../../../Parameters.md) |

### B-2. Scope the contract enforces

What it can do (the minimal functionality the current contract / script has):

- `DeployLiquity2` makes the Strategy kind / weight / cap of active branches env-required, and forces `none` branches to 0 Strategies, weight 0, and cap 0.
- `CollateralVault.allocate()` retains `B_target = max(M * bufferTargetBps / 10000, bufferFloor) + pendingWithdrawals` and sends only the excess to the Strategy.
- A multi-Strategy branch can allocate by `weightBps`, with each Strategy's `cap` and `allocateMaxMove` as upper bounds. Any remainder cut off by a cap is not reallocated to other Strategies but stays in the buffer.
- `transferYieldToTreasury()` retains the same required buffer as `allocate()`, and does not transfer using the protected backstop reserve or the cached Strategy valuation.
- `backstopDeposit()` / `releaseBackstopToBuffer()` separate the repair reserve from the ordinary buffer.
- `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` make the `DF_*` from B-1 required per active branch, preventing going to production with the initial defaults.

What it does not do (the contract does not do automatically):

- It does not auto-compute the JPYdf/USDC LP amount from the B/S balance.
- It does not count the JPYdf/USDC LP position as dToken backing, Vault buffer, or backstop.
- It does not auto-pull from a Strategy at redemption. On buffer shortfall it becomes a delayed withdraw request, and the ALLOCATOR replenishes via `Strategy.sendToVault()`.
- It does not count a B/S repair toward backing while it is still an arbitrary token. Only the portion for which the target Vault's Underlying actually lands and `backstopDeposit()` succeeds is treated as repair.
- It does not auto-update Strategy cap / weight according to market liquidity. Changes are the subject of governance / deploy env / the handover runbook.

### B-3. Freeze checklist (parameter portion)

| Item | Value to freeze | Implementation / runbook |
| --- | --- | --- |
| dToken cap | `DF_DTOKEN_CAP_i` per branch | `PrepareDFGovernanceHandover` / `VerifyDFGovernanceHandover` |
| Strategy cap | `DF_STRATEGY_CAP_i` or `_i_j` per branch / strategy | `DeployLiquity2` |
| Strategy weight | `DF_STRATEGY_WEIGHT_BPS_i` or `_i_j`, total ≤ 10000 | `CollateralVault.addStrategy()` |
| Allocate cap | `DF_ALLOCATE_MAX_MOVE_i` | `CollateralVault.setAllocatorConfig()` |
| buffer | `DF_BUFFER_TARGET_BPS_i`, `DF_BUFFER_FLOOR_i` | `CollateralVault.setBufferConfig()` |
| delayed redeem | `DF_WITHDRAW_DELAY_i` | `CollateralVault.setWithdrawDelay()` |

> The values frozen on the A side (the LP seed USDC / JPYdf amount, position owner, and funding source are [`Liquidity-Route-Policy.md`](../../../protocol/product/policies/Liquidity-Route-Policy.md) §5; the backstop reserve's target Vault, Underlying, deposit amount, and release conditions are A-1; Safe retained yield is [`Treasury-Safe-Retention-Runbook.md`](../../../protocol/operations/runbooks/Treasury-Safe-Retention-Runbook.md)) take the A-side docs as authoritative.

---

## C. Common Decisions

- **No code addition needed**: The functionality to classify B/S funds into LP / backstop / Treasury retention and to control the Vault-side buffer / Strategy allocation is sufficient in the current implementation.
- **What is needed are freeze values**: `DF_DTOKEN_CAP_i` / `DF_ALLOCATE_MAX_MOVE_i` cannot take USD notation as-is. Determine the token unit reflecting the final price, decimal places, and B/S launch envelope separately (values in [`../../Parameters.md`](../../../Parameters.md)).
- **Separate implementation availability from adoption**: Do not infer launch adoption from the presence of Strategy code. Approve each venue together with B/S withdrawal resilience, keeper operations, audit scope, and LP seed amount; the current classification is governed by [Strategy Selection Policy](../../../protocol/operations/policies/Strategy-Selection-Policy.md#adoption-classification). Lido is retirement-pending and is not an activation candidate.
- **Treasury / PIL retention is accumulation-only on Day-1**: Incentives to the JPYdf/USDC LP, additional SP rewards, and buyback are the subject of the Day-2 Treasury implementation or individual approval, not a Day-1 contract guarantee ([`Treasury-Safe-Retention-Runbook.md`](../../../protocol/operations/runbooks/Treasury-Safe-Retention-Runbook.md)).
