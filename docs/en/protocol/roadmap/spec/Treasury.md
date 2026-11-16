# 🟢 Treasury Requirements

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Draft. **Day-1 (MVP) does not implement `Treasury.sol`**. Each Vault's `treasury` points to the Foundation/GOV Safe and only accumulates collateral deployment yield there. **Day-2 introduces `Treasury.sol`**, and `setTreasury` switches Safe -> Treasury. Day-1 / Day-2 operation is governed by the [Treasury Safe Retention Runbook](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md). |
| Owner | DeltaForesight |
| Target contract | `contracts/src/Treasury.sol` (new, 🟢 Original, UUPS) |
| Related documents | [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md) (collateral-yield purpose allocation) / [Reward Distributors](Reward-Distributors.md) (SP additional, Borrow Referral, and SP-deposit Referral rewards) / [CollateralVault](../../product/spec/CollateralVault.md) (VAULT-FR-007 / VAULT-FR-012 / VAULT-FR-017) / [Strategy](../../product/spec/strategies/Strategy.md) (STGY-FR-003 / STGY-FR-010) / [Parameters](../../../Parameters.md) |

> This English document is a support translation. The Japanese source under `documents/jp` is authoritative.
> This document follows the [Requirements Spec Standard](../../../README.md#requirements-spec-standard). Requirement IDs use `TRSY-*`.

---

## 1. Overview and Responsibilities

`Treasury.sol` is a revenue router that receives collateral deployment yield (Underlying) from CollateralVault and sends it to fixed purpose destinations according to the single budget table in [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md).

Treasury itself does not perform DEX buyback, SP depositor TWAB calculation, Merkle claim, Referral partner / wallet calculation, or Foundation internal accounting. Processing required by each purpose is the responsibility of the receiving contract or the Foundation Safe side. For backstop funding, Treasury only calls the registered CollateralVault `backstopDeposit`; `releaseBackstopToBuffer` and the recovery waterfall remain the responsibility of the Vault / incident policy side.

| Purpose | Destination | Destination-side source of truth |
| --- | --- | --- |
| `SP_ADDITIONAL_REWARD` | `SPAdditionalRewardDistributor` | [Reward-Distributors.md](Reward-Distributors.md) |
| `BORROW_REFERRAL` | `BorrowReferralRewardDistributor` | [Reward-Distributors.md](Reward-Distributors.md) |
| `SP_DEPOSIT_REFERRAL` | `SPDepositReferralRewardDistributor` | [Reward-Distributors.md](Reward-Distributors.md) |
| `BACKSTOP_DEPOSIT` | registered `CollateralVault.backstopDeposit` | [CollateralVault.md](../../product/spec/CollateralVault.md) VAULT-FR-017 |
| Foundation remainder | `foundationSafe` | Foundation / DF protocol-external accounting |

**Treasury has only four responsibilities**:

1. Receive collateral deployment yield and expose unsplit balances.
2. Run `splitYield` according to `purposeShareBps[purpose]` and send funds to fixed purpose destinations.
3. During incidents, fund registered Vault `backstopDeposit` paths within the shortfall cap.
4. Control destination / ratio changes through timelock, roles, and events.

---

## 2. Scope and Non-Responsibilities

**Specified by this document**:

- Purpose routing, fixed destinations, ratio changes, route-change timelock, backstopDeposit funding, pause, and UUPS for `Treasury.sol`.
- Assumptions for the Day-1 Safe-retention -> Day-2 Treasury introduction switch.
- Simple forwarding of reward tokens (Aave incentives / Merkl, etc.) to the Foundation Safe.

**Not specified by this document**:

- SP additional reward, Borrow Referral, and SP-deposit Referral buyback / attribution / root / claim -> [Reward Distributors](Reward-Distributors.md) and [Referral-Program-Policy](../../operations/policies/Referral-Program-Policy.md)
- Collateral-yield purpose allocation ratios themselves -> [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md) and [Parameters](../../../Parameters.md)
- `releaseBackstopToBuffer`, post-funding redeem / claim restart order, and the repair waterfall. These are handled by [CollateralVault](../../product/spec/CollateralVault.md) and incident policy / governance decisions.

---

## 3. Terms and Accounting

| Term | Meaning |
| --- | --- |
| Underlying yield | Collateral deployment yield sent by a Vault through `transferYieldToTreasury` |
| purpose | Fixed purpose: `SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` / `BACKSTOP_DEPOSIT` |
| Foundation remainder | `10000 - sum(purposeShareBps[purpose])`; sent to `foundationSafe` at split time |
| `purposeShareBps[purpose]` | Ratio sent to that purpose destination at split time. Initial values are sourced from [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md) / [Parameters](../../../Parameters.md) |
| `purposeDestination[purpose]` | Fixed destination contract for `SP_ADDITIONAL_REWARD` / `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` |
| `backstopVault[token]` | Destination for `BACKSTOP_DEPOSIT` and emergency backstop. It must satisfy `CollateralVault.underlying() == token` |
| `unsplitBalance(token)` | Treasury token balance that has not yet been processed by `splitYield`. Treasury has no receive hook; the value is finalized at processing time |

Treasury exposes cumulative routed totals by purpose through events / views, but asset accounting after routing moves to the destination-side source of truth. Therefore Treasury does not keep `rewardShareBps`, `buybackBudget`, `assetBudget`, `epoch`, or `claimed`. SP / Referral purpose destinations implement the common interface `notifyTreasuryRevenue(address token, bytes32 purpose, uint256 amount)` and record the received amount when Treasury notifies them. `BACKSTOP_DEPOSIT` is not a notification path; Treasury deposits Underlying into the registered Vault `backstopDeposit` and reconciles with `BackstopDeposited` events.

---

## 4. Actors and Roles

| Actor | Operation | Trust boundary |
| --- | --- | --- |
| `GOV_ROLE` | `setPurposeShareBps` / propose and confirm destination and backstopVault changes / `unpauseRouting` / UUPS authorization | Expected holder is the shared TimelockController (`minDelay` 24h). Cannot cause immediate outflow |
| `TREASURER_ROLE` | `splitYield` / `forwardRewardToken` / `pauseRouting` / `emergencyBackstopDeposit` | Operations role. Cannot change ratios or destinations through function arguments. Emergency backstop is limited to registered Vault and shortfall cap |
| `GUARDIAN_ROLE` | Cancel destination proposals / disable destinations / `pauseRouting` / `emergencyBackstopDeposit` | Fail-safe only. Cannot add fund destinations or change ratios. Backstop funding is limited to registered Vault and shortfall cap |
| Purpose destination / backstop Vault | Receives purpose funds from Treasury | Processing is governed by each destination spec |
| Foundation Safe | Receives Foundation remainder and reward tokens | Protocol-external |

---

## 5. Interface Specification

| Function | Visibility | Summary | Requirement |
| --- | --- | --- | --- |
| `initialize(address admin, address foundationSafe, PurposeConfig[] initialPurposes, BackstopConfig[] initialBackstops)` | external initializer | Set roles, Foundation Safe, initial purpose destinations / ratios, and backstop Vaults | TRSY-FR-001 |
| `splitYield(address token, uint256 amount)` | external `TREASURER_ROLE` | Send unsplit Underlying to purpose destinations and Foundation Safe | TRSY-FR-002 |
| `forwardRewardToken(address token, uint256 amount)` | external `TREASURER_ROLE` | Forward non-Underlying reward token to Foundation Safe | TRSY-FR-003 |
| `setPurposeShareBps(bytes32 purpose, uint256 bps)` | external `GOV_ROLE` | Update future purpose ratio within bounds | TRSY-FR-004 |
| `proposePurposeDestination(bytes32 purpose, address destination)` / `confirmPurposeDestination(bytes32 purpose)` / `cancelPurposeDestination(bytes32 purpose)` | external | Two-step control for destination changes | TRSY-FR-005 |
| `proposeBackstopVault(address token, address vault)` / `confirmBackstopVault(address token)` / `cancelBackstopVault(address token)` | external | Two-step control for backstop Vault changes | TRSY-FR-005 |
| `disablePurposeDestination(bytes32 purpose)` | external `GUARDIAN_ROLE` | Stop new routing to that purpose on compromise / failure | TRSY-FR-005 |
| `pauseRouting()` / `unpauseRouting()` | external | Asymmetric pause for routing | TRSY-FR-006 |
| `emergencyBackstopDeposit(address vault, uint256 amount)` | external `TREASURER_ROLE` or `GUARDIAN_ROLE` | Fund a registered Vault within the shortfall cap even while routing is paused | TRSY-FR-007 |
| `unsplitBalance(address token)` / `purposeDestination(bytes32 purpose)` / `purposeShareBps(bytes32 purpose)` / `backstopVault(address token)` / `routedTotal(address token, bytes32 purpose)` | external view | Monitoring and reconciliation views | TRSY-FR-008 |
| `_authorizeUpgrade(address)` | internal | UUPS authorization | TRSY-FR-009 |

---

## 6. Functional Requirements

### TRSY-FR-001: initialize

- `admin` and `foundationSafe` must be nonzero.
- Initialization is one-time.
- Initial `sum(purposeShareBps) <= PURPOSE_SHARE_TOTAL_MAX_BPS`.
- SP / Referral purposes with positive initial share require a nonzero destination.
- Positive initial `BACKSTOP_DEPOSIT` share requires `backstopVault[token] != address(0)` and `CollateralVault(vault).underlying() == token`.
- Initial destinations and backstop Vaults are deployment wiring and are not subject to timelock. Later changes follow TRSY-FR-005.
- Emits initial `PurposeShareBpsUpdated`, `PurposeDestinationChanged`, and `BackstopVaultChanged` evidence.

### TRSY-FR-002: splitYield

- `token` must be the Underlying of a registered Vault.
- `amount != 0` and `amount <= unsplitBalance(token)`.
- `sum(purposeShareBps) <= PURPOSE_SHARE_TOTAL_MAX_BPS`.
- SP / Referral purposes with positive share require a set, non-disabled destination.
- A positive `BACKSTOP_DEPOSIT` share requires a set, non-disabled `backstopVault[token]` whose underlying matches `token`.
- Purpose shares of 0 do not require a destination / backstop Vault and do not block `splitYield`.
- For SP / Referral purposes with `purposeAmount[p] > 0`, Treasury transfers to `purposeDestination[p]` and calls `notifyTreasuryRevenue(token, p, purposeAmount[p])`. If notification reverts, the whole `splitYield` reverts.
- For `BACKSTOP_DEPOSIT`, Treasury approves the registered Vault and calls `backstopDeposit(purposeAmount)`. The received amount is reconciled through both Vault and Treasury events.
- `foundationAmount = amount - sum(purposeAmount[p])` is sent to `foundationSafe`. Dust is assigned to the Foundation side.
- Ratio changes apply only to future `splitYield`; past routed amounts are not redistributed.
- Emits `YieldRouted(...)` and, when applicable, `BackstopDepositedFromTreasury(token, vault, amount, received, false)`.

### TRSY-FR-003: forwardRewardToken

- Forwards non-Underlying reward tokens from Strategies directly to `foundationSafe`.
- `token != address(0)` and `amount != 0`.
- Underlying tokens are handled by `splitYield` and must be rejected.
- Tokens protected as destination reward assets under escrow / claim must be rejected.
- Does not automatically repurpose reward tokens into buyback, backstop, or Referral budgets.

### TRSY-FR-004: purpose share setter

- Only `GOV_ROLE`.
- `purpose` must be known.
- Always maintains `sum(purposeShareBps) <= PURPOSE_SHARE_TOTAL_MAX_BPS`.
- `PURPOSE_SHARE_TOTAL_MAX_BPS` structurally guarantees the minimum Foundation remainder; the value is sourced from [Parameters](../../../Parameters.md).
- Setter is reusable, not one-shot. It is future-effective only.
- Emits `PurposeShareBpsUpdated(purpose, oldBps, newBps)`.

### TRSY-FR-005: purpose destination / backstop Vault changes

- Destination and backstop Vault changes use `propose -> TRSY_TIMELOCK_DELAY -> confirm`.
- `propose` / `confirm` require `GOV_ROLE`; `cancel` and `disable` require `GUARDIAN_ROLE`.
- New destinations / backstop Vaults must be nonzero.
- Before confirmation, the old destination / backstop Vault remains active.
- Backstop Vaults must satisfy `CollateralVault(vault).underlying() == token`.
- A disabled purpose cannot receive new positive-share `splitYield` routing.
- Emits `PurposeDestinationChangeProposed` / `PurposeDestinationChanged` / `PurposeDestinationChangeCancelled` / `PurposeDestinationDisabled` / `BackstopVaultChangeProposed` / `BackstopVaultChanged` / `BackstopVaultChangeCancelled`.

### TRSY-FR-006: pauseRouting / unpauseRouting

- `TREASURER_ROLE` or `GUARDIAN_ROLE` can call `pauseRouting`.
- Only `GOV_ROLE` can unpause.
- While paused, `splitYield` stops.
- `forwardRewardToken` can continue as a Foundation evacuation path.
- `emergencyBackstopDeposit` can continue only under TRSY-FR-007 conditions.

### TRSY-FR-007: emergencyBackstopDeposit

- Callable only by `TREASURER_ROLE` or `GUARDIAN_ROLE`.
- Requires `routingPaused == true`; normal backstop funding uses the `BACKSTOP_DEPOSIT` bucket in `splitYield`.
- `BACKSTOP_DEPOSIT` purpose must not be disabled.
- `vault` must match the registered `backstopVault[token]`, and `token == CollateralVault(vault).underlying()`.
- `amount != 0` and `amount <= unsplitBalance(token)`.
- `amount <= CollateralVault(vault).backstopRequiredForRatio(1e18)`. A Vault with zero shortfall cannot receive emergency backstop funding.
- Treasury approves exactly the required token amount, calls `CollateralVault(vault).backstopDeposit(amount)`, records received amount, updates `routedTotal[token][BACKSTOP_DEPOSIT]`, and leaves no approval residue.
- Emits `BackstopDepositedFromTreasury(token, vault, amount, received, true)`.
- Emergency backstop cannot reclaim already routed / finalized SP additional reward, Referral, or Foundation budgets.

### TRSY-FR-008: views

- Views expose `unsplitBalance`, purpose share, destination, backstop Vault, disabled state, cumulative routed totals by token / purpose, pending proposals, and routing pause state.

### TRSY-FR-009: UUPS upgrade

- `_authorizeUpgrade` is restricted to `GOV_ROLE`.
- On mainnet, `GOV_ROLE` / `DEFAULT_ADMIN_ROLE` holders are only the shared TimelockController.
- Before upgrade execution, review storage layout diff, role holders, routing pause, unsplit balances, and destination / backstop proposals.
- Storage is append-only. Existing meanings of `purposeShareBps`, destination, backstop Vault, `routedTotal`, and unsplit balances must not change.

---

## 7. Invariants and Security

| ID | Invariant / Requirement | Verification |
| --- | --- | --- |
| TRSY-INV-001 | Fund outflows from Treasury are limited to `{purposeDestination[p], backstopVault[token], foundationSafe}`. Treasury has no transfer function with arbitrary `to` | unit / manual |
| TRSY-INV-002 | `sum(purposeShareBps) <= PURPOSE_SHARE_TOTAL_MAX_BPS` | unit |
| TRSY-INV-003 | `splitYield` never silently reallocates an unset / disabled purpose to another purpose | unit |
| TRSY-INV-004 | Treasury does not directly transfer or call DEX routers, SP, or Referral participants. The only direct Vault call is the registered `backstopDeposit` path | static review |
| TRSY-INV-005 | Destination / backstop Vault changes cannot take effect before the timelock elapses | unit |
| TRSY-INV-006 | `emergencyBackstopDeposit` can execute only while routing is paused, `BACKSTOP_DEPOSIT` is active, Vault is registered, underlying matches, and amount is within the shortfall cap | unit / invariant |

**TREASURER key compromise boundary**: TREASURER can only route according to preset ratios and fixed destinations, or pause routing. Emergency backstop is also capped by registered Vault shortfall. There is no path to send funds to an attacker address, arbitrary router, or arbitrary referral payout address.

**GOV key compromise boundary**: destination replacement passes through timelock and event monitoring. GUARDIAN can cancel during the delay. UUPS upgrade bypass is delayed by making TimelockController the GOV holder.

---

## 8. Events and Monitoring

| ID | Event | Use |
| --- | --- | --- |
| TRSY-EVT-001 | `YieldRouted(token, amount, foundationAmount, purposes[], destinations[], purposeAmounts[])` | Reconcile purpose allocation results |
| TRSY-EVT-002 | `RewardTokenForwarded(token, amount)` | Track reward token evacuation |
| TRSY-EVT-003 | `PurposeShareBpsUpdated(purpose, oldBps, newBps)` | Monitor budget table changes |
| TRSY-EVT-004 | `PurposeDestinationChangeProposed/Changed/Cancelled(purpose, destination, readyAt)` | Monitor route changes |
| TRSY-EVT-005 | `PurposeDestinationDisabled(purpose, destination)` | Monitor fail-safe action |
| TRSY-EVT-006 | `RoutingPaused(account)` / `RoutingUnpaused(account)` | Incident monitoring |
| TRSY-EVT-007 | `BackstopVaultChangeProposed/Changed/Cancelled(token, vault, readyAt)` | Monitor backstop Vault changes |
| TRSY-EVT-008 | `BackstopDepositedFromTreasury(token, vault, amount, received, emergency)` | Reconcile normal / emergency backstop funding |

Monitoring metrics: `unsplitBalance` by token, cumulative routed amount by purpose, Foundation remainder, destination / backstop proposal, disabled purpose, routing pause duration, and Vault-level `backingShortfall` / `backstopRequiredForRatio(1e18)`.

---

## 9. Failure and Exceptional Behavior

| Event | Behavior |
| --- | --- |
| Destination contract failure / revert | Entire `splitYield` reverts. Funds remain in Treasury and are not reallocated to another purpose |
| Positive-share purpose destination unset / disabled | `splitYield` reverts. Funds remain unsplit until GOV repairs the destination or sets the share to 0 |
| Positive-share backstop Vault unset / underlying mismatch | `splitYield` / `emergencyBackstopDeposit` reverts. Funds remain unsplit until GOV repairs registration or sets `BACKSTOP_DEPOSIT` share to 0 |
| Ratio misconfiguration | Bounds violations revert. Wrong settings within bounds are detected by governance / monitoring and fixed for future splits |
| Before Day-2 cutover | Vault treasury remains the Safe. Treasury routing does not occur |
| Backing impairment | `pauseRouting` stops normal C/D/Foundation payments. `emergencyBackstopDeposit` can fund registered Vaults within the shortfall cap. Release / restart order is handled by incident policy / governance decision |

---

## 10. Acceptance Criteria

| ID | Summary | Verification |
| --- | --- | --- |
| TRSY-FR-001 | initialize | unit |
| TRSY-FR-002 | purpose routing | unit / invariant |
| TRSY-FR-003 | reward token forwarding | unit |
| TRSY-FR-004 | purpose share setter | unit |
| TRSY-FR-005 | destination timelock / disable | unit |
| TRSY-FR-006 | pause / unpause | unit |
| TRSY-FR-007 | emergency backstop | unit / invariant |
| TRSY-FR-008 | views | unit |
| TRSY-FR-009 | UUPS | unit / manual |
| TRSY-INV-001..006 | fixed destinations, ratios, route controls, and emergency backstop cap | unit / invariant / static review |

---

## 11. Open Issues

| ID | Open item |
| --- | --- |
| TRSY-TBD-001 | Finalize `PURPOSE_SHARE_TOTAL_MAX_BPS`, initial `purposeShareBps`, and `TRSY_TIMELOCK_DELAY` values |
| TRSY-TBD-002 | Decide whether Day-1 Safe-retained funds are routed in one batch after Treasury introduction or gradually over a period |
| TRSY-TBD-003 | Post-emergency-backstop order for `releaseBackstopToBuffer`, redeem / claim restart, and routing restart (separate incident policy) |
| TRSY-TBD-004 | `BORROWER_REBATE` is frozen because it is inactive on Day-1. Keep share 0 and destination unset until a new explicit decision, a `BorrowerRebateDistributor` specification/destination, and an initial share all pass their activation gate |

---

## 12. References

- [Protocol-Revenue-Allocation-Policy](../policies/Protocol-Revenue-Allocation-Policy.md)
- [Reward Distributors](Reward-Distributors.md)
- [Treasury Safe Retention Runbook](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md)
