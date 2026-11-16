# Product Unwind And Sunset Runbook

## 0. Scope

This runbook defines how to wind down the JPY DeFi product, market, or branch
operations without adding a global shutdown contract or modifying Liquity Core.
It uses the existing cap, pause, Strategy recovery, backstop, and writeoff
surfaces.

Scope:

- Ethereum mainnet JPY DeFi protocol-wide soft wind-down.
- Active-branch soft wind-down.
- Strategy or backing incident handling at product sequencing level.
- Balance-sheet seed exit for bootstrap Troves, SP seed, and LP seed.

Non-goals:

- Arbitrary governance shutdown of Core branches.
- Forced user balance burn or discretionary JPYdf mint.
- Promising fixed exit timing, guaranteed full exit, or borrower protection from
  normal redemption and liquidation mechanics.

Related documents:

- [`Mainnet-Launch-Operation-Gate.md`](../../launch/gates/Mainnet-Launch-Operation-Gate.md)
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](Strategy-Incident-Liquidation-Safety-Runbook.md)
- [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](../../../contributors/deltaforesight/operations/Vault-Buffer-Shortfall-User-Comms-Runbook.md)
- [`Treasury-Safe-Retention-Runbook.md`](Treasury-Safe-Retention-Runbook.md)
- [`Incident-Notification-Policy.md`](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md)
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
- [`../../product/spec/CollateralVault.md`](../../product/spec/CollateralVault.md)
- [`../../product/spec/dToken.md`](../../product/spec/dToken.md)
- [`../../product/spec/Liquity-v2-Core-Spec.md`](../../product/spec/Liquity-v2-Core-Spec.md)

## 1. Principles

1. Do not treat Core branch shutdown as a product off switch. Core shutdown is a
   protocol safety path, not a business-discretion sunset tool.
2. Stop new growth before restricting exits. In ordinary sunset mode, keep close,
   repay, redeem, claim, and SP withdrawal flows available where backing and
   safety allow.
3. Do not overstate what contracts can stop. `DToken.setCap(0)` and
   `CollateralVault.pauseDeposit()` stop new dToken supply, but they do not
   retroactively burn existing supply or close existing Core debt.
4. Separate repair from loss recognition. Use `backstopDeposit` with the
   underlying asset when repair is possible. Use `writeoffStrategyPrincipal`
   only after an unrecoverable amount is confirmed.
5. Keep balance-sheet funds separate from user and protocol funds. LP seed, SP
   seed, bootstrap Troves, Treasury Safe funds, and Vault backstop funds must be
   reconciled as separate buckets.

## 2. Contract Boundary

| Purpose | Contract surface | Holder / owner | Sunset use |
| --- | --- | --- | --- |
| Stop new dToken supply | `DToken.setCap(0)` | dToken owner / Timelock | Standard hard stop for new supply. Existing supply is not burned. |
| Limit net dToken growth | `DToken.setCap(snapshotTotalSupply)` | dToken owner / Timelock | Not a hard stop. Redemptions lower supply and can reopen headroom. |
| Stop Vault deposits | `CollateralVault.pauseDeposit()` | Guardian | Stops new user underlying deposits. |
| Stop new allocations | `CollateralVault.pauseAllocation()` | Guardian | Stops new outbound Strategy allocation and treasury sweep. |
| Prioritize exit liquidity | `setBufferConfig(10000, floor)` | GOV / Timelock | Keeps recovered assets in the Vault buffer for user exits. |
| Stop normal Strategy weight | `updateStrategy(strategy, 0, cap, false)` | GOV / Timelock | Planned wind-down path. |
| Emergency Strategy disable | `emergencyDisableStrategy(strategy)` | Guardian | Incident or external venue risk path. |
| Recover Strategy funds | `sendToVault` or Strategy-specific emergency withdrawal | Allocator / Strategy owner | Return recoverable assets to the Vault. Illiquidity alone is not loss. |
| Repair backing | `backstopDeposit(amount)` | Funding owner / anyone | Underlying asset only. Do not mint dToken for repair. |
| Recognize confirmed loss | `writeoffStrategyPrincipal(strategy, amount, minBackingRatioAfter)` | Writeoff role | Use only after unrecoverable residual is confirmed. |
| Stop user exits | `pauseRedeem()`, `pauseClaim()` | Guardian | Incident-only. Not the ordinary sunset default. |
| Stop Day-2 bridge routes | Adapter route pause, runtime cap 0, optionally `removeBridgeMinter` | Adapter admin / bridge admin | Only relevant after a bridge minter has been activated. Do not reopen routes until remote canonical supply reconciliation is complete. |

### 2.1 Explicit Non-Goals

- Do not add a mechanism for governance to arbitrarily shut down all Core
  branches.
- Do not add a new governance flag to stop Core `openTrove` or debt increase.
- Do not let the operator unilaterally burn or settle user JPYdf, dToken, or
  Trove debt.
- Do not discretionary-mint JPYdf for protocol reward or repair purposes.
- Do not promise a fixed ETA, full immediate exit, redemption avoidance, or
  special borrower protection.

### 2.2 Bridge-Active Caveat

Day-1 launch assumes zero bridge minters, so the ordinary product unwind only
needs to cover Ethereum mainnet Core, dToken, Vault, Strategy, LP, and SP
surfaces. After any Day-2 bridge minter is registered, use the incident path in
[`Bridge-Minter-Activation-Gate.md`](Bridge-Minter-Activation-Gate.md) before
treating a product-wide sunset as complete, and retain evidence for:

1. Route / chain pause state, runtime cap, hourly rate limit, and daily rate
   limit.
2. Public route flag, frontend route flag, and ops route flag closed.
3. Adapter-side route pause and runtime cap 0 execution.
4. `globalCanonicalJpydfSupply`, per-chain `remoteCanonicalJpydfSupply`, and
   in-flight / failed / expired message reconciliation.
5. Adapter drift, remote-chain incident, or accounting mismatch handling. If any
   of these are present, keep the route paused with cap 0 and consider
   `removeBridgeMinter` or adapter-specific revoke.

`JpydfToken` does not have token-level route pause, per-chain cap, or remote
accounting. After bridge activation, do not treat token-local action alone as a
complete sunset.

## 3. Trigger Classification

| Trigger | Example | First decision owner | Standard mode |
| --- | --- | --- | --- |
| Product soft wind-down | Demand shortfall or decision to stop public launch growth | Product / governance | Soft wind-down |
| Branch-specific wind-down | Branch liquidity, oracle, or strategy economics deteriorate | Risk / governance | Branch soft wind-down |
| Strategy / backing incident | External venue loss, withdrawal halt, valuation failure | Ops / guardian / writeoff | Incident recovery |
| Balance-sheet seed exit | Bootstrap Trove, LP seed, or SP seed withdrawal | Finance / ops | B/S bootstrap exit |
| Insolvent / loss case | Unrepaired backing shortfall or confirmed Strategy loss | Governance / writeoff | Loss handling |

## 4. Soft Wind-Down Flow

1. Record the decision scope: branches, frontend surfaces, cap changes, LP / SP
   seed handling, and user communication owner.
2. Use Guardian immediate controls first: `pauseDeposit()` and
   `pauseAllocation()`. Keep redeem and claim open unless an incident requires
   otherwise.
3. Queue and execute `DToken.setCap(0)` for each active dToken through the
   Timelock.
4. Reduce Strategy exposure. Use `updateStrategy(strategy, 0, cap, false)` for
   planned wind-down, or `emergencyDisableStrategy(strategy)` for incident mode.
5. Increase buffer priority with `setBufferConfig(10000, floor)` when user exit
   liquidity needs to dominate new allocation.
6. Shift frontend and ops surfaces from growth to exit: close, repay, redeem,
   SP withdraw, dToken redeem, pending claims, and strategy exposure.
7. Record T+24h, T+72h, and T+7d evidence for branch debt, SP deposits, outside
   debt, redemption volume, pending withdrawals, buffer balance, backing ratio,
   and LP depth.

No-Go:

- Treating `pauseRedeem` or `pauseClaim` as the standard sunset path.
- Describing dToken cap lowering as a full stop of Core borrowing.
- Writing off temporary Strategy illiquidity as confirmed loss.
- Publishing fixed exit ETAs or guaranteed full-exit language.

## 5. Balance-Sheet Bootstrap Exit

Bootstrap Troves, SP seed, and JPYdf/USDC LP seed are balance-sheet operations,
not protocol safety controls. Exiting them should not remove user exit
liquidity or liquidation coverage abruptly.

Required checks:

1. Reconcile LP seed, SP seed, bootstrap Trove collateral and debt, Treasury Safe
   retained funds, and manual backstop funds by token, owner, and branch.
2. Before LP withdrawal, confirm JPYdf/USDC depth, redemption pressure, SP
   coverage, borrower close demand, and the alternative exit route.
3. Before SP seed withdrawal, confirm branch debt, liquidation candidates,
   outside debt, third-party SP deposits, and the JIT or top-up owner.
4. Before bootstrap Trove close, confirm the JPYdf repayment source and avoid
   double-counting JPYdf already allocated to LP or SP exit.
5. Monitor JPYdf price, redemption fee/base rate, branch TCR/SCR, SP coverage,
   and liquidation candidates for at least 72 hours after a material exit.

## 6. Strategy Incident / Loss Handling

The Strategy incident runbook is authoritative for detailed recovery and bot
safety. Product-level sequencing is:

1. Guardian stops affected Vault and Strategy user flows and allocation.
2. Confirm the operational liquidation bot skips the affected branch when
   backing or oracle state is unsafe.
3. Recover what can be recovered into the Vault.
4. If repair is possible, backstop with the affected Vault underlying.
5. Write off only the confirmed unrecoverable residual.
6. Record impact on `backingRatio`, PriceFeed, MCR-near Troves, and pending
   claims.
7. Unpause user flows only after full-backing or accepted-loss conditions are
   explicitly approved.

No-Go:

- Large writeoff before recovery and repair attempts.
- Classifying JPYdf, dToken, or reward tokens as direct backing repair.
- Double-counting loss already reflected in live valuation.
- Letting bots ignore Vault pause or backing-ratio guards.

## 7. User Surface

Product sunset communication should lead with what users can still do, not only
what has been stopped.

| User state | Primary path | Display policy |
| --- | --- | --- |
| Borrower with active Trove | Repay / close / manage rate | Show required JPYdf, redemption risk, and close path. |
| JPYdf holder | Redeem JPYdf / DEX exit | Show redemption fee, route, received dToken or collateral redeem path. |
| dToken holder | Redeem collateral | Show queued claim and `claimableAt` when buffer is short. Do not show fixed ETA. |
| SP depositor | Withdraw from SP / claim collateral gains | Show branch SP coverage, remaining liquidation risk, and dToken gain redemption path. |
| LP or campaign participant | Withdraw LP / end campaign | Separate campaign end, unclaimed rewards, and LP manager actions. |

## 8. Evidence Template

```text
Decision:
Scope: protocol-wide / branch-specific / strategy-specific
Reason:
Decision owner:
Governance proposal / Safe tx:
Public communication owner:

Affected branches:
Affected dTokens:
Affected Vaults:
Affected Strategies:

Cap action:
Cap before:
TotalSupply before:
Cap after:
TotalSupply after:
Deposit paused:
Vault pause action:
Strategy action:
Buffer config action:
Backstop / writeoff action:
Frontend / admin mode:
Bridge route state:
Remote canonical supply reconciliation:

Current branch debt:
Current SP deposits:
Current outside debt:
Current JPYdf/USDC depth:
Current redemption fee / base rate:
Current bufferBalance:
Current pendingWithdrawals:
Current backingRatio:

B/S LP seed state:
B/S SP seed state:
Bootstrap Trove state:
Repayment source:
Backstop source:

Allowed user actions:
Paused user actions:
Known limitations:

T+24h review:
T+72h review:
T+7d review:
```

## 9. Follow-Up Surface

- **Admin console**: show branch wind-down checklist, cap / pause / buffer /
  Strategy exposure, LP / SP / bootstrap Trove state, and Safe calldata evidence
  in one place.
- **User app**: add sunset mode and prioritize Close / Repay / Redeem / SP
  withdraw / Vault redeem over Borrow / Earn growth CTAs.
- **Ops dashboard**: align `product_sunset`, `branch_wind_down`,
  `strategy_incident`, and `loss_handling` alert keys with
  `Incident-Notification-Policy`.
- **Docs**: launch evidence `Unwind plan` should point to this runbook and record
  branch-level repayment source, LP exit, and SP seed exit.
