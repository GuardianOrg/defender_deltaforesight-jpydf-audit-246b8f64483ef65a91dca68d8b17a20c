# 🟢 Reward Distributor Requirements

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | **Future Draft / outside the current audit scope.** Day-2 or later requirements for converting Treasury purpose budgets into reward assets and distributing them through cumulative Merkle claims. |
| Owner | DeltaForesight |
| Targets | `SPAdditionalRewardDistributor.sol`, `BorrowReferralRewardDistributor.sol`, `SPDepositReferralRewardDistributor.sol` (all new, 🟢 Original, UUPS), plus off-chain root calculation |
| Related documents | [Treasury](Treasury.md), [Protocol Revenue Allocation Policy](../policies/Protocol-Revenue-Allocation-Policy.md), [Referral Program Policy](../../operations/policies/Referral-Program-Policy.md), [Referral Campaign Activation Gate](../../operations/runbooks/Referral-Campaign-Activation-Gate.md), [Oracle](../../product/spec/Oracle.md), [Parameters](../../../Parameters.md) |

This document states shared requirements once and identifies mechanism-specific differences. Existing `SPARD-*`, `BRRD-*`, and `SPDRD-*` IDs are preserved. These are not implementation requirements for an existing contract until a separate specification, implementation, test, audit package, and activation gate are completed.

## 1. Responsibilities and boundaries

Each Distributor is a fixed Treasury purpose destination that:

1. receives the Underlying budget for its purpose;
2. market-buys an approved reward asset (initially JPYdf) through an allowlisted route, without minting JPYdf;
3. escrows funding against an off-chain cumulative Merkle root; and
4. after a challenge window, pays the unclaimed cumulative delta to the beneficiary fixed in the leaf.

Treasury does not execute buybacks, post roots, or process claims. A Distributor does not define collateral-profit allocation, Core or Stability Pool accounting, partner registries, campaign terms, frontend attribution, or DFT tokenomics. If borrow or SP-deposit referral rewards are paid manually from a Foundation operating-asset Safe, the corresponding Distributor bucket is set to zero and routed to the Foundation residual; there is no normal return path from a Distributor to that Safe.

### 1.1 Mechanism-specific differences

| Prefix / contract | Treasury purpose | Beneficiary | Attribution input | Epoch-specific value | Merkle leaf |
| --- | --- | --- | --- | --- | --- |
| `SPARD` / `SPAdditionalRewardDistributor` | `SP_ADDITIONAL_REWARD` | SP depositor `account` | TWAB from public SP deposit, withdrawal, and liquidation events across all branches | none | `keccak256(abi.encode(block.chainid, distributor, SP_ADDITIONAL_REWARD, account, asset, cumulative))` |
| `BRRD` / `BorrowReferralRewardDistributor` | `BORROW_REFERRAL` | `referrer` | `ReferralDeposit` / `SkyUsdcRouteDeposit`, partner registry, and campaign terms; initial rewardable volume is `ReferralDeposit.jpydfAmount` | `campaignHash` | `keccak256(abi.encode(block.chainid, distributor, BORROW_REFERRAL, referrer, asset, cumulative))` |
| `SPDRD` / `SPDepositReferralRewardDistributor` | `SP_DEPOSIT_REFERRAL` | `referrer` | reconciliation of sJPYdf, a wrapper, or signed attribution with SP events; a raw SP deposit alone is insufficient | `sourceHash` | `keccak256(abi.encode(block.chainid, distributor, SP_DEPOSIT_REFERRAL, referrer, asset, cumulative))` |

The SP additional reward is separate from native SP rewards (75% of borrowing interest and liquidation gain) and does not modify Core state.

## 2. Accounting and roles

Funds move only as `Treasury → buybackBudget → rewardBudget → epoch escrow → beneficiary`. Budgets for the three mechanisms never mix.

| State | Meaning |
| --- | --- |
| `underlyingBudget[token]` | cumulative Underlying received from Treasury for this purpose |
| `accountedUnderlying[token]` | Treasury-pulled Underlying that remains accounted; decreases as buyback consumes it |
| `rewardShareBps[asset]` | allocation by reward asset; initially JPYdf = 10,000 |
| `buybackBudget[token][asset]` | unspent buyback budget denominated in `token` |
| `rewardBudget[asset]` | purchased balance available to fund roots |
| `epochs[asset][epochId]` | root, funding, mechanism-specific value, `activatesAt`, and cancellation state |
| `totalFunded[asset]` / `totalClaimed[asset]` | cumulative claim-solvency counters |
| `claimed[beneficiary][asset]` | cumulative amount already paid to a beneficiary |

| Role | Authority |
| --- | --- |
| `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` | common TimelockController; finalize settings, unpause, upgrade |
| `TREASURER_ROLE` | execute and pause buybacks |
| `ROOT_POSTER_ROLE` | post roots |
| `GUARDIAN_ROLE` | disable reward assets, cancel roots, pause buybacks or claims |
| Treasury | fixed sender that only notifies revenue for the matching purpose |

## 3. Functional requirements

### SPARD-FR-001 / BRRD-FR-001 / SPDRD-FR-001: initialize

`initialize(address admin, address treasury, address jpyDf)` rejects zero addresses and repeat initialization; grants `DEFAULT_ADMIN_ROLE` and `GOV_ROLE` to `admin`; fixes Treasury; enables JPYdf with `rewardShareBps[JPYdf] = 10000`; and leaves the implementation contract itself uninitializable. No ordinary setter can change Treasury. SPDRD starts with no `attributionSourceHash` and cannot receive revenue until one is set. Production use additionally requires the buyback, root, and operating gates; a paid BRRD campaign also requires the Referral Campaign Activation Gate.

### SPARD-FR-002 / BRRD-FR-002 / SPDRD-FR-002: receive Treasury revenue

`notifyTreasuryRevenue(token, purpose, amount)` is `onlyTreasury` and requires the matching purpose, non-zero token and amount, and enabled reward shares summing to 10,000. SPDRD also requires a non-zero attribution source. Treasury gives a temporary allowance for exactly `amount`; the Distributor pulls with `safeTransferFrom`.

This is the fixed-purpose notification path defined by `TRSY-FR-002`; a
Distributor must not accept or relabel another Treasury purpose.

The pre/post balance delta must equal `amount`, rejecting fee-on-transfer, rebasing, or otherwise non-exact transfers. Only after exact receipt does it increase `underlyingBudget` and `accountedUnderlying` and allocate to `buybackBudget`; rounding dust goes to JPYdf or the first enabled asset. Direct donations remain unaccounted surplus (`actual balance - accountedUnderlying`) and cannot fund buyback or roots without an explicit governance or incident policy.

### SPDRD-FR-003: attribution source gate

Only `GOV_ROLE` may call `setAttributionSourceHash`. It rejects zero, a source based solely on raw `DFStabilityPool.provideToSP()`, and changes while a root is pending. The hash uniquely identifies chain, contract or signer, period, TWAB, minimum holding, and exclusion/clawback rules. A change is future-only.

### SPARD-FR-003 / BRRD-FR-003 / SPDRD-FR-004: buyback

`executeBuyback(token, targetAsset, amountIn, path)` requires `TREASURER_ROLE`, an unpaused buyback, an enabled non-zero asset, budget and clip bounds, an allowlisted router/pool/hop, the correct terminal asset, and a usable fair price or TWAP within the spot/TWAP deviation limit.

The contract computes `minOut = fairOut * (10000 - maxSlippageBps) / 10000`; callers cannot lower it. It measures `amountOut` from balance deltas, reverts below `minOut`, leaves no excess allowance, and changes budgets only after success.

### SPARD-FR-004 / BRRD-FR-004 / SPDRD-FR-005: post and cancel an epoch root

`notifyEpoch(...)` is restricted to `ROOT_POSTER_ROLE`; `cancelRoot(asset, epochId)` to `GUARDIAN_ROLE`. Posting requires an enabled asset, non-zero root and funding, sufficient `rewardBudget`, monotonically increasing epoch IDs per asset, and no uncancelled pending root. BRRD fixes a non-zero `campaignHash`; SPDRD fixes a non-zero `sourceHash` equal to the current attribution source.

Posting escrows funding, sets `activatesAt = block.timestamp + CHALLENGE_WINDOW`, and increases `totalFunded`. A root cannot be used until the window expires. Cancellation is allowed only before activation, returns funding to `rewardBudget`, and removes it from `totalFunded`.

### SPARD-FR-005 / BRRD-FR-005 / SPDRD-FR-006: cumulative claim

`claim(asset, beneficiary, cumulative, proof)` is permissionless, but payment is fixed to the `account` (SPARD) or `referrer` (BRRD/SPDRD) encoded in the leaf; there is no arbitrary receiver. It requires claims unpaused, an enabled asset, non-zero beneficiary, active root, valid proof, `cumulative > claimed`, and `totalClaimed + payout <= totalFunded`.

The contract updates `claimed` and `totalClaimed` before `safeTransfer(beneficiary, payout)`. A transfer failure reverts all state.

### SPARD-FR-006 / BRRD-FR-006 / SPDRD-FR-007: governance configuration

`setRewardShareBps`, `setBuybackConfig`, and `addRewardAsset` require `GOV_ROLE`. Adding an asset follows propose → delay → confirm and verifies price source, router/path, and claim-token risk. Slippage, TWAP deviation, and clip values remain within [Parameters](../../../Parameters.md). Share changes affect future revenue only. GUARDIAN can disable an asset or buyback immediately without burning existing claim funding.

### SPARD-FR-007 / BRRD-FR-007 / SPDRD-FR-008: pause

TREASURER or GUARDIAN can pause buyback; GUARDIAN can pause claims; only GOV can resume. Buyback and claim pauses are independent. Revenue receipt, views, and cancellation during the challenge window remain available.

### SPARD-FR-008 / BRRD-FR-008 / SPDRD-FR-009: views

Expose budgets, epochs, active/pending roots, claimed amounts, funding counters, assets/shares, buyback config, and pause states. BRRD also exposes `campaignHash`; SPDRD exposes the attribution source and epoch `sourceHash`.

### SPARD-FR-009 / BRRD-FR-009 / SPDRD-FR-010: UUPS

`_authorizeUpgrade` requires `GOV_ROLE`, whose production holder is the common TimelockController. Storage is append-only and an upgrade cannot change the meaning of budgets, claims, funding counters, roots, or SPDRD attribution sources.

## 4. Off-chain root requirements

- Deduplicate events by `chainId`, emitter, tx hash, and log index; signed sources use signer and nonce.
- Record finality depth, extraction time, methodology version, and first applicable epoch.
- Use the domain-separated leaves in §1.1 with cumulative amounts by asset and beneficiary.
- A party independent from the root poster recalculates the root during the challenge window.
- Artifacts include period, inputs and exclusions, manual-review count, beneficiary count, sum of cumulative deltas, funding, and rounding dust.
- SPARD uses TWAB across all branches, reflects withdrawals/liquidations, and never double-counts native liquidation gain.
- BRRD excludes zero codes and applies campaign rules for self-referral, immediate close, repayment, liquidation/redemption/bad debt, holding period, and partner/wallet caps.
- SPDRD uses TWAB and minimum holding, reconciles an approved attribution source, and never treats a raw SP event as sufficient.

## 5. Invariants and security requirements

| IDs | Requirement |
| --- | --- |
| `SPARD-INV-001..008` | `totalClaimed <= totalFunded`; claims are monotonic; buyback stays within budget; caller cannot lower min-out; pending roots cannot be claimed; Core/SP state is untouched; cancelled funding is not double-counted; no arbitrary receiver/call/router outflow exists. |
| `BRRD-INV-001..009` | only `BORROW_REFERRAL`; funded/claimed solvency and monotonic claims; budget-bound buyback; payout fixed to referrer; no normal Foundation-Safe return; no cross-purpose diversion; no double-counted cancellation or arbitrary outflow. |
| `SPDRD-INV-001..010` | only `SP_DEPOSIT_REFERRAL`; no revenue before source registration; funded/claimed solvency and monotonic claims; payout fixed to referrer; no normal Foundation-Safe return; no Core SP accounting/ABI change or cross-purpose diversion; no double-counted cancellation or arbitrary outflow. |

| ID | Requirement |
| --- | --- |
| SPARD-INV-001 | `totalClaimed[asset] <= totalFunded[asset]` |
| SPARD-INV-002 | `claimed[account][asset]` is monotonic |
| SPARD-INV-003 | buyback never exceeds the matching `buybackBudget` |
| SPARD-INV-004 | callers cannot lower the contract-computed minimum output |
| SPARD-INV-005 | roots cannot be claimed before the challenge window ends |
| SPARD-INV-006 | the Distributor never changes Core or Stability Pool state |
| SPARD-INV-007 | cancelled funding returns to `rewardBudget` without remaining in `totalFunded` |
| SPARD-INV-008 | no arbitrary receiver, call, or router outflow exists |
| BRRD-INV-001 | only `BORROW_REFERRAL` revenue is accepted |
| BRRD-INV-002 | `totalClaimed[asset] <= totalFunded[asset]` |
| BRRD-INV-003 | `claimed[referrer][asset]` is monotonic |
| BRRD-INV-004 | buyback never exceeds the matching `buybackBudget` |
| BRRD-INV-005 | payout is fixed to the referrer in the leaf |
| BRRD-INV-006 | there is no ordinary manual-payment return path to the Foundation Safe |
| BRRD-INV-007 | funds cannot be diverted to SP-deposit Referral, SP additional rewards, or PIL |
| BRRD-INV-008 | cancelled funding is not double-counted |
| BRRD-INV-009 | no arbitrary receiver, call, or router outflow exists |
| SPDRD-INV-001 | only `SP_DEPOSIT_REFERRAL` revenue is accepted |
| SPDRD-INV-002 | Treasury revenue is rejected before attribution-source registration |
| SPDRD-INV-003 | `totalClaimed[asset] <= totalFunded[asset]` |
| SPDRD-INV-004 | `claimed[referrer][asset]` is monotonic |
| SPDRD-INV-005 | payout is fixed to the referrer in the leaf |
| SPDRD-INV-006 | there is no ordinary manual-payment return path to the Foundation Safe |
| SPDRD-INV-007 | Core Stability Pool accounting and ABI remain unchanged |
| SPDRD-INV-008 | funds cannot be diverted to Borrow Referral, SP additional rewards, or PIL |
| SPDRD-INV-009 | cancelled funding is not double-counted |
| SPDRD-INV-010 | no arbitrary receiver, call, or router outflow exists |

An incorrect activated root can misdistribute more than that epoch's funding because cumulative claims may reach the whole unclaimed balance. Independent recalculation, claim pause, and unclaimed-balance monitoring are mandatory.

## 6. Events and monitoring

| ID | Event |
| --- | --- |
| SPARD-EVT-001 | `SPAdditionalRevenueReceived(token, amount)` |
| SPARD-EVT-002 | `BuybackExecuted(token, asset, amountIn, amountOut, minOut)` |
| SPARD-EVT-003 | `EpochFunded(asset, epochId, root, amount, activatesAt)` |
| SPARD-EVT-004 | `RootCancelled(asset, epochId)` |
| SPARD-EVT-005 | `Claimed(asset, account, payout, cumulative)` |
| SPARD-EVT-006 | reward-asset, share, and buyback-configuration updates |
| SPARD-EVT-007 | buyback and claim pause/unpause |
| BRRD-EVT-001 | `BorrowReferralRevenueReceived(token, amount)` |
| BRRD-EVT-002 | `BorrowReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` |
| BRRD-EVT-003 | `BorrowReferralEpochFunded(asset, epochId, root, amount, campaignHash, activatesAt)` |
| BRRD-EVT-004 | `BorrowReferralRootCancelled(asset, epochId)` |
| BRRD-EVT-005 | `BorrowReferralClaimed(asset, referrer, payout, cumulative)` |
| BRRD-EVT-006 | reward-asset, share, and buyback-configuration updates |
| BRRD-EVT-007 | buyback and claim pause/unpause |
| SPDRD-EVT-001 | `SPDepositReferralRevenueReceived(token, amount)` |
| SPDRD-EVT-002 | `SPDepositReferralAttributionSourceUpdated(sourceHash)` |
| SPDRD-EVT-003 | `SPDepositReferralBuybackExecuted(token, asset, amountIn, amountOut, minOut)` |
| SPDRD-EVT-004 | `SPDepositReferralEpochFunded(asset, epochId, root, amount, sourceHash, activatesAt)` |
| SPDRD-EVT-005 | `SPDepositReferralRootCancelled(asset, epochId)` |
| SPDRD-EVT-006 | `SPDepositReferralClaimed(asset, referrer, payout, cumulative)` |
| SPDRD-EVT-007 | reward-asset, share, and buyback-configuration updates |
| SPDRD-EVT-008 | buyback and claim pause/unpause |

Monitoring covers budgets by token/asset, active and pending roots, challenge time remaining, mechanism-specific evidence, `totalFunded - totalClaimed`, pause duration, independent recalculation results, and `amountOut / minOut`.

## 7. Failure behavior

| Failure | Behavior |
| --- | --- |
| wrong sender/purpose, missing SPDRD source, invalid shares, or receipt mismatch | revert the revenue notification and the whole Treasury transaction |
| direct donation | retain as unaccounted surplus; do not use for budget, buyback, or root funding |
| invalid buyback price, TWAP, path, or min-out | revert only the buyback; preserve budgets, roots, and claims |
| insufficient root evidence | ROOT_POSTER does not post |
| incorrect pending root | GUARDIAN cancels within the window and makes funding reusable |
| incorrect activated root | GUARDIAN pauses claims; governance/incident policy handles the unclaimed balance |
| reward transfer failure | revert the whole claim without advancing `claimed` |
| switch to manual referral payment | set the matching bucket to zero; do not create a normal Safe-return path |
| request to use raw SP deposit alone for SPDRD | reject until an approved attribution source exists |

## 8. Open items

| ID | Open decision |
| --- | --- |
| SPARD-TBD-001 | epoch length, challenge window, and claim-pause operation |
| SPARD-TBD-002 | JPYdf buyback venue, clip, slippage, and TWAP thresholds |
| SPARD-TBD-003 | conditions for adding DFT or another reward asset |
| SPARD-TBD-004 | controls that cap damage after an incorrect root activates |
| BRRD-TBD-001 | caps, campaign period, minimum holding, and clawback rules |
| BRRD-TBD-002 | epoch length, challenge window, and claim-pause operation |
| BRRD-TBD-003 | payout-asset composition and non-JPYdf price guards |
| BRRD-TBD-004 | carryover, Foundation return, burn, or other unused-budget treatment |
| BRRD-TBD-005 | event/ledger revision if rewardable volume stops using `jpydfAmount` |
| SPDRD-TBD-001 | sJPYdf, wrapper, or signed-attribution source |
| SPDRD-TBD-002 | TWAB, minimum holding, and withdrawal/liquidation/self-referral exclusions |
| SPDRD-TBD-003 | epoch length, challenge window, and claim-pause operation |
| SPDRD-TBD-004 | payout-asset composition and non-JPYdf price guards |
| SPDRD-TBD-005 | carryover, Foundation return, burn, or other unused-budget treatment |
