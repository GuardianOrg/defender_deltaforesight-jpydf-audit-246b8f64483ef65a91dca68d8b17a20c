# Liquidation Backstop / JIT Policy

## Positioning

This document is a design memo that defines the boundaries of Stability Pool (SP)
liquidation, operator backstop, and JIT (just-in-time) liquidation support at the JPYdf
launch.

For the on-chain spec of liquidation itself, take
[`../../product/spec/Liquity-v2-Core-Spec.md`](../../product/spec/Liquity-v2-Core-Spec.md) as authoritative;
for the implementation plan of the liquidation bot, take
[`../plans/Liquidation-Bot-Plan.md`](../../../engineering/plans/Liquidation-Bot-Plan.md) as authoritative; and
for the Day-1 DEX liquidity / route, take
[`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md) as authoritative. This document
fixes the operational backstop terminology that cuts across them.

## Terminology

| Term | Meaning |
| --- | --- |
| SP offset | The Liquity core path that, when `TroveManager.batchLiquidateTroves` runs, uses the branch-local Stability Pool's JPYdf deposit to offset the target Trove debt |
| redistribution | The Liquity core path where debt/collateral that cannot be fully offset by the SP deposit is redistributed to the remaining Troves |
| Backstop | The operator or a third party operationally supplementing JPYdf / DEX liquidity / liquidation execution / collateral disposal so that liquidation does not stall |
| JIT | The operation of sourcing JPYdf and depositing it into the SP to increase SP offset capacity, then liquidating, within a short time window after — or just before — a liquidation candidate arises |
| Atomic JIT | An executor that performs JPYdf sourcing, SP deposit, liquidation, and if necessary collateral disposal within 1 tx / bundle. Not a Day-1 implementation |

## Day-1 Decision

What is implemented and operationally targeted on Day-1 is the following two layers only.

1. **Pre-funded SP**: At launch, the operator deposits self-minted JPYdf into the Stability
   Pool of each branch.
2. **Non-atomic JIT top-up**: The liquidation bot / ops dashboard observes the SP offset
   capacity and candidate debt, and as needed the operator additionally deposits held JPYdf or
   JPYdf sourced on the DEX via `StabilityPool.provideToSP`.

On Day-1, **the Atomic JIT executor is not implemented**. Therefore, the "SP + JIT capacity"
used in the allocation table is not capacity guaranteed by the contract, but
**operational planning capacity** premised on the operator being able to complete sourcing, SP
deposit, and liquidation execution.

## What the Current Implementation Can Do

| Area | Current support |
| --- | --- |
| Liquidation candidate detection | `bots/liquidator` patrols each branch using `LiquidationCandidateGetter` and `lastZombieTroveId` |
| Re-verification just before liquidation | The bot re-verifies candidates with `TroveManager.getCurrentICR` |
| SP capacity observation | The bot logs the offset capacity after deducting `MIN_JPYDF_IN_SP` from `StabilityPool.getTotalJpydfDeposits()` |
| Liquidation execution | The bot can send the branch-local `TroveManager.batchLiquidateTroves` according to dry-run / live configuration |
| Vault incident guard | The bot reconfirms Vault pause / backing ratio safety at scan time and before submit |

## What the Current Implementation Does Not Do

| Area | Not supported on Day-1 |
| --- | --- |
| JPYdf sourcing | The bot does not buy JPYdf on Uniswap v4. The DEX LP supports the sourcing environment but is not the bot's route |
| SP top-up | The bot does not auto-execute `provideToSP`. SP deposit is the responsibility of the operator runbook / Safe / a separate executor |
| atomic bundle | It does not bundle JPYdf sourcing -> SP deposit -> liquidation into 1 tx / bundle |
| Collateral disposal | Sale / evacuation / accounting of collateral obtained from liquidation is not handled in the bot itself |
| capacity guarantee | It does not reserve / guarantee SP + JIT capacity on the contract |

## Standard Procedure for Non-atomic JIT Top-up

1. The bot / ops detects a liquidatable candidate, the candidate debt, and the branch SP offset
   capacity.
2. The operator confirms the branch's Vault safety, oracle failure, and shutdown state.
3. If SP capacity is insufficient, the operator prepares held JPYdf, self-minted JPYdf, or JPYdf
   sourced from the JPYdf/USDC Uniswap v4 liquidity.
4. The operator tops up the SP via the target branch's `StabilityPool.provideToSP(amount, false)`.
5. The liquidator bot executes `batchLiquidateTroves(troveIds)`.
6. After liquidation, account for the SP depositor's collateral gain, the remaining JPYdf deposit,
   and any necessary collateral disposal in a separate runbook.

Because this procedure is affected by mempool / timing / price movement, large liquidations require
a private relay, an explicit loss cap, and a post-hoc accounting trail.

## Gates for Introducing Atomic JIT in the Future

If an Atomic JIT executor is added, treat it not as a configuration addition to the existing bot
but as a new audited entrypoint / executor. At a minimum, do not put it into production until the
following are satisfied.

- Make the funding source explicit. Do not conflate operator inventory / flash liquidity / DEX swap
  / self-mint.
- For the JPYdf/USDC Uniswap v4 route, freeze the pool key, hook policy, Universal Router / Permit2
  address, min-out, and allowance cleanup.
- The executor does not accept an arbitrary route and uses only allowlisted routes.
- Verify on-chain / via typed config that the SP deposit and the liquidation target branch match.
- Make loss cap / max gas / min collateral gain / max slippage mandatory.
- Make a runbook for private relay / resend, cancellation, and nonce management on bundle failure.
- Because the internal price in `batchLiquidateTroves` follows core's `priceFeed.fetchPrice()`, do
  not treat the executor's swap quote as the oracle for liquidation eligibility.
- Include in fork tests SP-sufficient, SP-insufficient, route slippage, oracle failure, Vault pause,
  shutdown branch, and zombie Trove.

## Documentation Notation Rules

- Do not use notation that evokes flashloan / atomic bundle, such as "JIT flash liquidation max,"
  as long as there is no implementation.
- In allocation tables, write **JIT backstop capacity** or **operator JIT capacity**, and note in a
  footnote that it is "operational planning capacity, not a contract guarantee."
- DEX liquidity and JIT capacity are not the same. The JPYdf/USDC LP helps with JPYdf sourcing / peg
  defense but does not automate SP deposit or liquidation execution.
