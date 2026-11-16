# Vault Buffer Shortfall / User Communication Runbook

## 0. Purpose

This runbook defines the advance preparation, plus the operational and notification procedure when it occurs, so that when the CollateralVault's liquid buffer falls short of redeem / claim demand, users do not misunderstand it as "my funds disappeared" or "I need to redo the operation many times."

Source-of-truth specs:

- [`CollateralVault.md`](../../../protocol/product/spec/CollateralVault.md): `redeem` / `WithdrawRequest` / `claim` / `bufferBalance` / `pendingWithdrawals`
- [`Frontend.md`](../../../protocol/product/spec/Frontend.md): `FRNT-FR-015` / `FRNT-FR-016` / `FRNT-ERR-005`
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](../../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md): decisions on Strategy recovery / writeoff / backstop
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../policies/Balance-Sheet-Liquidity-Allocation-Policy.md): responsibility separation of B/S funds, backstop, and Vault buffer

## 1. Basic Explanation for Users

A buffer shortfall is not necessarily a backing shortfall. In many cases it is a state where "the immediate-payout buffer inside the Vault is temporarily thin, and the assets are on the Strategy side or in the protected backstop reserve."

User-facing wording must always satisfy the following 4 points.

1. **Separate immediate receipt from entering the queue**
   Split the redeem outlook into "the amount you can receive now" and "the amount that becomes a queued claim" for display.

2. **Explain that the queued claim remains on-chain**
   The amount not paid out due to insufficient buffer remains as a `WithdrawRequest`. The user does not need to resend the same claim; they wait for the delay and buffer recovery.

3. **Do not state a fixed ETA**
   `withdrawDelay` is a minimum wait time, not the buffer recovery time. It depends on the status of Strategy recovery, backstop release, and additional deposits.

4. **Do not confuse it with a backing shortfall**
   If `backingRatio() == 1e18`, it is a temporary liquidity shortage while still fully backed. If `backingRatio() < 1e18`, treat it as a separate incident and do not assert whether recovery is possible.

Expressions to avoid:

- "You can receive it right away," "It is guaranteed," "You will definitely be able to receive it after X hours."
- A display that only says "Failed" without giving a reason.
- Describing a buffer shortfall as a "loss" or "insolvency."

## 2. Advance Preparation

### 2.1 UI / Public Information

- The user app `/vault` separates `estimated instant payout` and `estimated queued amount` in the redeem preview.
- The queued claim row clearly displays `Waiting for delay` / `Buffer refill pending` / `Claim paused` / `Claim`.
- The buffer wait explanation includes "request remains queued on-chain" and "no resubmission is needed."
- The Ops Dashboard displays `bufferBalance`, `pendingWithdrawals`, `bufferTargetAmount`, `backingRatio`, and paused flags per branch, and makes `pendingWithdrawals > bufferBalance` a critical alert.
- The stats publisher puts the same alert determination as the Ops Dashboard into the public stats, and routes structured JSON logs with `source="publish-stats-s3"`, `ok=false`, and `severity="critical" | "warning"` through CloudWatch metric filters to the backend alarm SNS topic. `pendingWithdrawals > bufferBalance` is critical and `bufferBalance < bufferTargetAmount` is warning, as external notification targets.
- The Admin Console displays `claimShortfall = max(pendingWithdrawals - bufferBalance, 0)` and the restart gate.

### 2.2 Operational Setup

Decide the following before launch.

| Item | Preparation |
| --- | --- |
| Incident owner | Primary decision-maker for buffer / claim shortfall |
| User comms owner | Approver of the copy for status page / X / Discord / app banner, etc. |
| ALLOCATOR executor | Decision to stop `sendToVault` / Strategy-specific recovery / `transferYieldToTreasury` |
| GUARDIAN executor | `pauseRedeem` / `pauseClaim` / `pauseAllocation` when needed |
| GOV / Timelock executor | `releaseBackstopToBuffer` / config changes |
| Foundation / Treasury Safe | The wallet that can supply backstop Underlying and the allowance procedure |

### 2.3 Alert Delivery Verification

- A direct SNS test verifies only topic-to-receiver delivery. Do not treat it as evidence that the stats health log, metric filter, and CloudWatch alarm path works.
- Before production readiness, run `AWS_PROFILE=jpydf-staging JPYDF_STAGE=staging JPYDF_BACKEND_STATS_HEALTH_TEST_ACCOUNT_ID=<staging-account-id> JPYDF_BACKEND_STATS_HEALTH_TEST_CONFIRM=send JPYDF_BACKEND_STATS_HEALTH_TEST_RECEIVER=<confirmed-email> pnpm -C infra/cdk test:backend-stats-health-alert`. This staging-only command rejects a caller outside the explicit staging account, sends a clearly labeled critical health JSON test incident to the stats publisher log group, verifies the critical alarm enters `ALARM`, verifies the warning alarm remains `OK`, waits for the critical alarm to return to `OK`, and requires successful SNS action history for both transitions.
- A passing command cannot confirm human receipt. Separately confirm that the intended receiver actually received the ALARM and OK notifications.
- Check `CRITICAL-public-stats-health` / `WARNING-public-stats-health` in the subject and the environment, `ALARM` / `OK` meaning, and first operator action at the start of the body. Do not infer the incident solely from the trailing CloudWatch metric detail.
- Record the log stream, alarm history, receiver, receipt time, and resolution time. Do not record email addresses, webhook URLs, tokens, or other secrets.

### 2.4 Monitoring Thresholds

| Level | Condition | Initial response |
| --- | --- | --- |
| Watch | `bufferBalance < bufferTargetAmount` | Ops alert. Check allocation / expected redeem volume |
| User-visible queue | queued amount > 0 in the redeem preview or tx result | Explain as a normal queue path in the user app copy |
| Claim shortfall | `pendingWithdrawals > bufferBalance` | Critical alert. Make a recovery plan for the claim funding |
| Backing incident | `backingRatio < 1e18` or `backingShortfall > 0` | Escalate to the Strategy incident runbook |
| User flow pause | `pausedRedeem || pausedClaim` | Public notice and explicit restart conditions |

## 3. Decisions When It Occurs

### 3.1 First, Separate

1. Is `backingRatio() == 1e18`?
2. Is `pendingWithdrawals > bufferBalance()`?
3. Are `pausedRedeem` / `pausedClaim` / `pausedAllocation` in effect?
4. Is there an idle / liquid amount that can be returned immediately from the Strategy?
5. Is there a protected `backstopBalance()`? Is `releaseBackstopToBuffer` needed to use it as claim / redeem funding?

### 3.2 Difference Between a Normal Queue and an Incident

| State | Meaning to the user | Operations |
| --- | --- | --- |
| Buffer is below target but `pendingWithdrawals <= bufferBalance` | There is a queue but the claim funding is sufficient | Monitor. Use `sendToVault` if needed |
| `pendingWithdrawals > bufferBalance` and backing is 100% | There is a claim wait. Not asset loss but a wait for liquidity refill | Consider Strategy recovery / backstop release / additional deposits |
| backing < 100% | May involve valuation / loss / writeoff | Follow the Strategy incident runbook. Do not assert whether recovery is possible |
| claim paused | Claim is temporarily paused. The request remains | Public notice. State restart conditions explicitly |

## 4. Recovery Procedure

1. **Fix the state and observe**
   Save `bufferBalance`, `pendingWithdrawals`, `backingRatio`, `backingShortfall`, `backstopBalance`, and Strategy statuses.

2. **Stop outbound if needed**
   Use `pauseAllocation` until the buffer recovers, to stop new Strategy allocation. If the claim funding is at risk use `pauseClaim`, and if the queue grows enough to confuse users consider `pauseRedeem`.

3. **Recover from the Strategy**
   The ALLOCATOR returns claimed / recoverable Underlying to the Vault via `sendToVault` or a Strategy-specific emergency / claim path. An asynchronous Strategy needs finalization / claim; do not writeoff just because of a queue wait.

4. **If using the backstop, keep the order**
   `backstopDeposit` is a protected reserve that replenishes backing; it is not claim / redeem funding as-is. GOV executes `releaseBackstopToBuffer` only for the portion used as claim funding.

5. **Confirm claim coverage**
   Confirm that `bufferBalance >= pendingWithdrawals`. So as not to use up the entire amount on immediate redeems, also confirm `bufferTargetAmount` before resuming redeem.

6. **Restart order**
   As a rule, restart in the order `Claim` → `Redeem` → `Deposit` → `Allocation`. Reach a state where waiting-claim users can be processed first before increasing new redeems.

7. **Post-event confirmation**
   Confirm the `WithdrawClaimed` events, the decrease in the pending queue, the resolution of the Ops alert, and the user app `/vault` display, and leave them in the incident log.

## 5. User Notification Templates

### 5.1 Normal Queue Occurrence

> Some redeems exceeded the immediate-payout buffer and were recorded on-chain as queued claims. This is the normal Vault withdrawal path. The portion not paid out immediately is shown under Queued claims on `/vault`, and once the claim delay has elapsed, it can be claimed as soon as the buffer is replenished. There is no need to recreate the same request.

### 5.2 Still Waiting on Buffer After the Claim Delay Has Elapsed

> The claim delay has elapsed, but the current branch buffer does not yet cover the full queued claim amount. The request remains on-chain. The operations side will replenish the buffer via Strategy recovery or backstop release. We cannot give a fixed ETA, but progress is updated in the Ops Dashboard and the claim state on `/vault`.

### 5.3 Claim / Redeem Pause

> The Guardian has temporarily paused some Vault operations. Existing queued claims are not deleted and remain on-chain. The restart conditions are confirmation of claim funding, backing ratio, and Strategy recovery status. After restart, requests can be processed in order starting from claimable ones.

### 5.4 When a Backing Shortfall Is Involved

> The backing ratio of the affected branch is currently below 100%. This is different from a simple buffer wait and is treated as an incident involving Strategy recovery / replenishment / writeoff decisions. We do not assert recoverability or receipt time, and update only the confirmed on-chain state and response policy.

## 6. Evidence to Retain for Audit / Post-Event Review

- branch id / dToken / underlying / Vault address
- incident start block / tx / detection source
- `bufferBalance`, `pendingWithdrawals`, `bufferTargetAmount`, `backingRatio`, `backingShortfall`, `backstopBalance`
- pause / unpause tx hash
- Strategy recovery tx hash and requested / sent
- `backstopDeposit` / `releaseBackstopToBuffer` tx hash
- the time, copy, and posting location of the user comms
- the block / tx at which the resolution condition was met

## 7. No-Go

Do not return to normal operation in the following states.

- `pendingWithdrawals > bufferBalance`
- The cause of `backingRatio < 1e18` is unclassified
- The user comms is not updated before releasing the claim / redeem pause
- The Strategy recovery amount and the Vault receipt amount cannot be reconciled
- The decision to use the backstop reserve as claim funding is made without the GOV / Timelock procedure
