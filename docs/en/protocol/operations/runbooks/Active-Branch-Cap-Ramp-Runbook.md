# Active Branch Cap Ramp Runbook

## 0. Scope

This defines the operational procedure for raising the `mintCap` of an active branch (dwstETH / dUSDC on Day-1) in stages post-launch.

This runbook turns the Japanese [Parameter Catalog](../../../../jp/protocol/product/parameters/Parameter-Catalog.md) `PRM-mintCap`, the Japanese [Collateral Parameter Policy](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) §3.1, the Japanese [Day-1 Parameter Decision](../../../../jp/protocol/launch/decisions/Day1-Parameter-Decision.md) §3.1, `Mainnet-Launch-Operation-Gate.md`, `Liquidation-Management-Policy.md`, and `Governance-Roles-Timelock.md` into an operational procedure. `mintCap` is a dToken supply / collateral exposure cap, not a JPYdf debt ceiling. A Day-1 hard branch debt ceiling is not added to Core (the #301 policy).

In scope:

- Branches that already have public exposure open as borrowable collateral.
- On Day-1, dwstETH / dUSDC.
- Branches that have been activated in the future go through that activation runbook / risk review in addition to this runbook.

Out of scope:

- Opening an inert branch with `mintCap = 0` (Branches 2–7 on Day-1) from 0. Use the [Inert Branch Activation Runbook](Inert-Branch-Activation-Runbook.md) for that.
- The first cap raise of an inert branch; complete the Inert Branch Activation Runbook first.
- Implementation of a Core hard branch debt ceiling.

## 1. Principles

1. Do not raise via `setCap` alone. Confirm SP coverage, the liquidation bot, JPYdf/USDC liquidity, ops monitoring, and frontend display at the same time.
2. `dToken.setCap` goes through the 24h Timelock; it is not an immediate raise. Begin preparing the proposal at 80% utilization, not after demand is already clogged.
3. Review `mintCap` and `allocateMaxMove` in the same proposal bundle. The standard for Day-1 active branches is to update both to the same notional exposure. For exceptions (suppressing Strategy allocation, or stopping outbound allocation), leave the reason in the decision log.
4. The post-ramp planned debt is not an on-chain cap; it is a conservative operational denominator for inspecting SP coverage / bot / liquidity.
5. A cap reduction / `pauseDeposit` only stops new dToken mints; it does not stop the Core debt increase against existing dToken collateral. State this residual risk explicitly when approving a cap ramp.

## 2. Quantitative Gates

### 2.1 Trigger

Begin preparing a cap ramp proposal on any of the following.

| Trigger | Gate |
| --- | --- |
| cap utilization watch | `dToken.totalSupply / dToken.cap >= 8,000 bps` sustained for 24h, or the ops alert `ALRT-MKT-007` fires |
| demand forecast | The launch owner / sales owner forecasts exceeding 80% of the current cap within the next 48h |
| public campaign | Expected inflow before a campaign start exceeds 50% of the current cap |

If there is no Timelock-executable cap ramp at `>= 9,500 bps`, pause the campaign / UI exposure / sales push, or have the risk owner record an exception. At `>= 10,000 bps`, new dToken mints are clogged, so make the user copy and the cap ramp / campaign pause decision immediately.

> **Upward peg deviation (`JPYdf > ¥1`)**: a cap increase intended to add supply follows this same runbook and cannot shorten the 24h Timelock on `setCap`. Existing borrowing room within the current dToken supply and cap is not subject to that delay. The faster supply response is additional borrowing and market supply through the existing Core path by any eligible borrower; neither the Protocol nor a specific Contributor guarantees execution. A Contributor that adopts a self-balance-sheet response needs its own Policy, Commitment, approval, and Evidence. A cap ramp is the slower follow-up lever ([`SYS-RISK-009`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-009) / [`ADR-007`](../../product/architecture/Architecture-Decision-Records.md#adr-007)). Record existing-Trove debt headroom and new-collateral capacity separately, and do not treat `plannedDebtJpydf` or a nominal cap as immediately executable debt room.

### 2.2 Step and Cooldown

The normal step for Day-1 active branches is capped at the following. Exceeding it requires a fresh risk-owner review and stress evidence.

| Branch | Initial cap | Normal step max | Unreviewed ramp ceiling | Cooldown |
| --- | ---: | ---: | ---: | --- |
| dwstETH | JPY 35 million | `min(JPY 12.5 million, current cap × 25%)` | JPY 50 million | 72h after execution |
| dUSDC | JPY 100 million | `min(JPY 25 million, current cap × 50%)` | JPY 200 million | 24h after execution |

You may queue the next proposal during a Cooldown, but do not execute it until the previous ramp's T+24h / T+72h watch is green.

### 2.3 SP Coverage

Compute the SP coverage for a cap ramp with the following conservative denominator.

```text
coverageDebtJpydf = max(currentBranchDebtJpydf, proposedMintCapJpyNotional)
requiredSpJpydf = coverageDebtJpydf * minSpCoverageBps / 10_000
```

`proposedMintCapJpyNotional` is not a JPYdf hard cap. It is the dToken collateral exposure cap converted to a JPY notional operational denominator; if actual debt exceeds it, use actual debt.

Minimum:

| Branch | minSpCoverageBps | Target note |
| --- | ---: | --- |
| dwstETH | 5,000 bps | High-volatility wstETH branch. Confirm the SP seed / JIT concentration owner before a cap ramp |
| dUSDC | 1,250 bps | Absolute minimum. For bootstrap economics / public APR policy, separately reference the 3,750 bps target |

No-Go:

- `spDeposits < requiredSpJpydf`.
- The SP top-up source is double-counted with the LP seed / Treasury reserve / backstop.
- `minSpCoverageBps` is satisfied, but the bot dry-run's planned batch cannot meet 100% offset coverage.

### 2.4 JPYdf/USDC Liquidity and JIT

Before a cap ramp, make the following into evidence at the current block.

| Gate | Required evidence |
| --- | --- |
| JPYdf/USDC pool | Sample sell / buy slippage via StateView / Quoter direct RPC is within the launch envelope |
| JIT capacity | Operator JPYdf inventory, USDC inventory, self-mint availability, or the SP top-up tx owner |
| 25% event | Assume a liquidation cluster of `coverageDebtJpydf * 25%`, and SP + confirmed JIT capacity is not short in the decision log |
| liquidator dry-run | Enabled branches, SP offset capacity, candidate count, planned batch gas, stressed gas cost, and skipReason match current policy |

DEX liquidity helps with JIT sourcing but does not guarantee SP top-up or liquidation execution. An atomic JIT executor is out of Day-1 scope.

## 3. Governance Procedure

### 3.1 Proposal Bundle

Review the cap ramp as one bundle of the following.

1. `dToken.setCap(newCap)`.
2. `CollateralVault.setAllocatorConfig(newAllocateMaxMove, allocatorCooldown)`.
3. If needed, `CollateralVault.setBufferConfig(...)` / Strategy cap update.
4. Update evidence for the frontend / ops config, public stats, and campaign copy.

The standard is for `newAllocateMaxMove` to be the same notional exposure as `newCap`. However, if it is made smaller for reasons of Strategy capacity, buffer, or market condition, write the reason for `newAllocateMaxMove < newCap` in the decision log. `newAllocateMaxMove > newCap` is not allowed.

### 3.2 Timeline

| Timing | Action |
| --- | --- |
| T-48h to T-24h | The risk owner approves the step, coverageDebt, SP/JIT, liquidity, and bot dry-run |
| T-24h | Queue the Timelock proposal. Record the Safe tx / calldata hash / expected new values |
| T-0 | Before execute, re-confirm that `ALRT-MKT-001..007`, oracle, backing, SP coverage, and liquidity monitor are green |
| T+1h | Confirm the dToken cap, allocateMaxMove, frontend/ops display, and public stats JSON via direct RPC / artifact |
| T+24h / T+72h | Per-branch cooldown watch. Record SP coverage, liquidation candidates, redemption activity, JPYdf/USDC slippage, and cap utilization in the decision log |

## 4. Evidence Template

```text
Active branch cap ramp evidence

Branch:
Current cap (token units / JPY notional):
Proposed cap (token units / JPY notional):
Current dToken supply:
Cap utilization bps:
Current branch debt:
Coverage debt denominator:
minSpCoverageBps:
Current SP deposits:
Required SP deposits:
SP top-up source / owner:

Current allocateMaxMove:
Proposed allocateMaxMove:
Allocator cooldown:
Strategy cap / weight impact:
Buffer target / floor impact:

JPYdf/USDC sample sell size / slippage:
JPYdf/USDC sample buy size / slippage:
Operator JIT inventory:
25% event size:
SP + JIT capacity:

Liquidator dry-run artifact:
Stress evidence artifact / fork block:
Alerts reviewed:
Frontend/app cap warning reviewed:
Ops alert ALRT-MKT-007 status:
Public stats artifact:

Timelock proposal tx:
Safe tx hash:
Queued at:
Executable at:
Executed at:
T+watch owner:
Decision log:
```

## 5. No-Go

Do not execute a cap ramp if any of the following is true.

- Docs / UI / ops copy remain that mislabel `mintCap` as a JPYdf issuance cap / branch debt ceiling.
- SP coverage does not satisfy §2.3.
- The JPYdf/USDC liquidity monitor or the liquidator dry-run is stale / unavailable.
- `ALRT-BACK-*`, `ALRT-ORCL-002/003/005/006/007`, or `ALRT-MKT-001/002/003/005` are unresolved.
- Despite cap utilization at 95% or above, none of the Timelock proposal, campaign pause, or user copy is prepared.
- The `setCap` and `allocateMaxMove` proposal bundle is split, and the reason for the execution order / mismatch is not in the decision log.
- The cap change would be used as an automatic response to upward JPYdf deviation without the manual approval and live debt-capacity checks required by [`SYS-RISK-009`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-009).
- You are trying to open a cap-0 branch (2–4) or an inert branch (5–7) with this runbook alone.

## 6. Frontend / Ops Expectations

- The user app does not surface a cap=0 branch as a borrowable route.
- The user app shows a claim capacity / conversion capacity warning for a branch whose dToken cap is near-full.
- Ops detects `dToken.totalSupply / dToken.cap >= 8,000 bps` for an active public branch as `ALRT-MKT-007`, and the risk owner decides on cap ramp / campaign pause / SP top-up.
- The ops dashboard / public stats read `dTokenSupply`, `dTokenCap`, SP coverage, branch debt, and JPYdf/USDC liquidity from the same current manifest.
- The admin console / Safe proposal displays the current value -> proposed value diff, token unit, JPY notional, and calldata hash.

## 7. References

- [`../../Parameters.md`](../../../Parameters.md) §4-1 — `PRM-mintCap`
- [`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md)
- [`Liquidation-Management-Policy.md`](../policies/Liquidation-Management-Policy.md)
- [`Day1-Self-BS-Initial-Liquidity-Plan.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md)
- [`Governance-Roles-Timelock.md`](../../product/policies/Governance-Roles-Timelock.md)
- [`Inert-Branch-Activation-Runbook.md`](Inert-Branch-Activation-Runbook.md)
