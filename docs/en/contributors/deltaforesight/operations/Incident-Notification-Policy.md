# Incident Notification Policy

## 0. Purpose

This runbook defines who is notified, at what severity, and with what
information when an anomaly occurs in JPYdf's oracle, branch health,
Vault / Strategy, or frontend / ops delivery surfaces.

Notifications separate "internal notifications for operators to respond
immediately" from "public announcements for users to understand what operations
are currently permitted." Do not turn an internal watch directly into a
full-screen banner in the user app.

Source-of-truth specifications:

- [`Frontend.md`](../../../protocol/product/spec/Frontend.md): `FRNT-FR-031..035`,
  `FRNT-ERR-005`, `FRNT-ERR-006`
- [`Oracle.md`](../../../protocol/product/spec/Oracle.md): `ORCL-SEC-005`, `ORCL-EVT-*`
- [`Parameters.md`](../../../Parameters.md): oracle staleness, branch risk
  parameters
- [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](Vault-Buffer-Shortfall-User-Comms-Runbook.md):
  user comms for buffer shortfall / queued claim
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](../../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md):
  Strategy incident, writeoff, liquidation bot safety

## 1. Principles

1. **Treat notifications as a state machine**
   They carry `triggered` / `acknowledged` / `escalated` / `resolved`, and
   duplicate notifications for the same cause are bundled by alert key.

2. **Separate user impact from internal risk**
   A source proposal, reduced staleness margin, or operator bot dry-run failure
   is in principle handled by internal notification alone. Branch shutdown, user
   flow pause, claim funding shortfall, and backing incidents warrant
   consideration of a user-facing announcement.

3. **Separate the oracle's shared leg from branch-local legs**
   Branch-local collateral/USD, peg, and canonical rate failures proceed to the
   shutdown of the affected branch. JPY/USD is a dependency shared across all
   branches, treated as a bounded soft-freeze from `JpyRateFrozen` up to
   `MAX_JPY_FREEZE_DURATION`.

4. **Do not conflate buffer shortfall with backing shortfall**
   `pendingWithdrawals > bufferBalance` is a claim liquidity problem, whereas
   `backingRatio < 1e18` is handled as a Strategy / backing incident.

5. **Notifications are not on-chain actions**
   An alert does not execute automatic pause, cap change, source replacement, or
   writeoff. Execution follows each runbook and the explicit judgment of the
   authority holder.

## 2. Severity

| Severity | Meaning | Internal notification | Public announcement |
| --- | --- | --- | --- |
| P0 Critical | Immediate impact on protocol safety or user operation. Branch shutdown, backing incident, writeoff, claim/redeem halt, prolonged JPY/USD freeze | Pager / incident channel / Safe signer channel | Required in principle |
| P1 Incident | A state that can become P0 in a short time. `JpyRateFrozen`, Strategy incident mode, claim funding shortfall, emergency source switch | Pager or incident channel | Only when there is user impact |
| P2 Watch | Threshold approach, pending operation, or operational confirmation needed. Reduced staleness margin, below buffer target, TCR / CCR approach, source proposal pending | ops channel / dashboard | Not required in principle |
| P3 Info | Normal state change or resolution notice. source updated, proposal cancelled, monitor recovered | dashboard / digest | Not required |

ACK targets:

| Severity | ACK target | Escalation |
| --- | --- | --- |
| P0 | Within 10 minutes | If no ACK, re-notify the incident owner and backup owner |
| P1 | Within 30 minutes | Escalate to P0 on ongoing user impact or approach to a P0 condition |
| P2 | Within 4 hours | Escalate only if the same condition persists and approaches a P1 condition |
| P3 | Next digest | No escalation |

## 3. Notification Destinations and Public Surfaces

| Surface | Use | Information that may be included | Information not to include |
| --- | --- | --- | --- |
| Pager / incident channel | Immediate response for P0 / P1 | branch, contract, tx hash, block, threshold, required action, runbook link | private RPC URL, API key, unpublished Safe nonce |
| Private Operations Monitor | Alert history and current state | alert key, status, resolved block, scope of impact, owner alias, ACK / escalation | signer personal information, secret, internal chat permalink, raw private endpoint |
| Admin console | Preparation and confirmation of privileged operations | impact preview of pause/source/writeoff, public banner reflection state | private keys, raw private endpoint |
| User app banner | States that affect user operations | affected branch, halted/available operations, where the next update will appear | internal owner, undetermined compensation availability, fixed ETA |
| Status page / official social | Broad user impact | short state description, scope of impact, next-update policy | root cause speculation, unapproved action, confidential information |

Representative cases that require a public announcement:

- Branch shutdown / activation of the urgent redemption flow
- Pause of borrow / redeem / claim / deposit
- An incident involving `backingRatio < 1e18` or a writeoff
- A state where `pendingWithdrawals > bufferBalance` affects users past the claim delay
- A state where the JPY/USD soft-freeze is prolonged, with source-replacement or shutdown risk
- A state where a full outage of user app / RPC / stats halts the write UI

Representative cases that do not require a public announcement:

- A normal timelock for an oracle source proposal
- A state that is merely approaching the staleness threshold and does not yet affect user operations
- Below buffer target but `pendingWithdrawals <= bufferBalance`
- An operator bot dry-run failure that does not affect third-party keepers or protocol state

## 4. Alert Key and Payload

To bundle re-notifications for the same cause, the alert key uses the following
standard form.

```text
<kind>:<chainId>:<branchOrGlobal>:<contractOrFeed>
```

`ALRT-ORCL-012` uses `chainId + branch + PriceFeedProxy` as its sole incident
identity because it represents branch urgent-settlement availability rather
than an individual auxiliary feed. The failed oracle, transaction hash, and log
index remain diagnostic payload fields. The process-external
`fetchUrgentRedemptionPrice()` synthetic is the current-state truth.

`ALRT-ORCL-016` uses
`chainId + PriceFeedProxy + normal-redemption-jpy-age` as its sole incident
identity. Source/provider addresses, cached timestamp, age, and provenance are
diagnostics and do not split the key. At one safe block, Proxy-only
normal-redemption `failure=true`, with current-source normal-redemption and
Proxy normal/urgent healthy and BO pause false, is the current-state truth. A
fresh round resolves that same key.

Required payload:

| Field | Content |
| --- | --- |
| `severity` | `P0` / `P1` / `P2` / `P3` |
| `status` | `triggered` / `acknowledged` / `escalated` / `resolved` |
| `kind` | `oracle_stale`, `jpy_freeze`, `branch_shutdown`, `buffer_shortfall`, `backing_incident`, `writeoff`, `pause`, `source_change`, `frontend_outage`, etc. |
| `chainId` | Target chain |
| `branch` | For branch-local, the branch id / dToken / underlying. For global such as JPY/USD, `global` |
| `contract` | Related contract address. If undetermined, the manifest key |
| `observedAtBlock` | Observed block |
| `txHash` | For an event origin, the tx hash. For a polling origin, may be empty |
| `currentValue` | Observed value |
| `threshold` | Firing threshold |
| `userImpact` | Halted operations, affected screens |
| `allowedUserActions` | Operations that can continue, such as repayment, claim, urgent redemption |
| `action` | The next action for a human to decide |
| `runbook` | Reference runbook |
| `owner` | Incident owner team alias. Use the duty rotation / team alias, not a personal name |
| `ackDeadline` | ISO timestamp of the ACK deadline |
| `ackDeadlineMinutes` | Minutes from firing time to the ACK deadline |
| `channels` | Delivery channel alias. Do not include actual URL / secret |
| `routeId` | The applied routing rule |
| `publicMessageRequired` | `true` / `false` |

In the current implementation, `buildAlertNotificationPayloads()` in
`frontend/ops/src/lib/alertNotifications.ts` generates the raw notification
payload with `schemaVersion=1`. `frontend/ops/src/lib/alertRouting.ts` applies
the default routing policy in the order of severity / kind / alertId and fills
in `owner` / `ackDeadline` / `channels` / `routeId`. `frontend/ops
export-alerts` outputs the routed payload as JSON. The payload is the
intermediate payload immediately before delivery.

`frontend/ops/src/lib/alertDelivery.ts` uses file-backed state to suppress
continued firing for the same alert key, and generates a `status=resolved`
payload when a previously active alert disappears. `frontend/ops notify-alerts`
uses `OPS_ALERTS_STATE_PATH` (default `outputs/ops-alert-delivery-state.json`)
and updates state only after a webhook success, or when `--write-state` is
specified. Production delivery destinations such as Slack / SNS / PagerDuty and
ACK / escalation state management are the responsibility of the delivery /
incident management layer.
CloudWatch backend alarm Slack delivery uses a Slack-only topic, not the email /
readiness record topic. Slack receives `ALARM` / `OK` on the same CRITICAL
public-stats-health alarm so Chatbot can close the same thread, plus `ALARM`
(and heartbeat / catch-cycle `INSUFFICIENT_DATA`) for heartbeat-missing
(stats / market-data report-check / state-collector / input-publisher /
liquidator receipt-reconciler), liquidator catch-cycle stale, and
private-monitor P0. Other immediate `OK` events do not page Slack.
FailedInvocations, ordinary script-failures, liquidator safety /
receipt-reconciler failure, WARNING health, and P1 / P2 stay on the record
topic for email. FailedInvocations and ordinary script-failures alarm on the
first breaching period. Liquidator safety and receipt-reconciler failure also
alarm after one period and email only.

As an explicit exception, the Aave reserve-deficit monitor routes P1/P2 and zero-recovery `OK` to both the record topic and Amazon Q because they are subject to the pre-cap-increase human-delivery drill.

`frontend/ops/src/lib/alertChannelDelivery.ts` resolves a channel alias to a
webhook destination. `OPS_ALERTS_CHANNEL_WEBHOOKS_JSON` is a JSON object whose
values use either a direct URL string or an env reference of the form
`{ "urlEnv": "...", "bearerTokenEnv": "..." }`. Do not write actual webhook
URLs, tokens, or chat permalinks in runbooks / spec / git-tracked files. Pass
the bearer token via `OPS_ALERTS_WEBHOOK_BEARER_TOKEN` or `bearerTokenEnv`, not
as a CLI argument. When a channel mapping is configured and a channel alias
referenced by the payload has no destination, `notify-alerts` fails closed. When
the mapping is unset and the fallback `OPS_ALERTS_WEBHOOK_URL` is also unset,
`notify-alerts` does not update state and outputs the delivery-candidate payload
to stdout.
On a successful webhook post, the `notify-alerts` summary leaves the channel,
HTTP status, notification count, alert keys, and redacted target in
`webhookReceipts[]`. Actual URL / token are not included in the receipt. On a
failed post as well, if `OPS_ALERTS_RECEIPTS_PATH` is configured, it appends an
`ok=false` redacted failure receipt and then fails closed. A failure receipt is
investigation evidence and is not treated as proof of notification completion in
the delivery state. State is not updated on a failed post.
When `OPS_ALERTS_RECEIPTS_PATH` or `--receipts-path` is set, the same receipt is
appended as JSONL. At handoff / retrospective, reconcile this receipt log with
delivery state / SLA audit.

### Persistence and DB Migration Boundary

For Day-1, the alert delivery state / receipts are authoritative as file-backed
JSON / JSONL, and a DB is not a mandatory dependency. Introduce a
Postgres-compatible DB only when worker restart, multiple workers, long-term
retention, searchability, or centralized management of the audit trail becomes
necessary. The schema baseline when introducing a DB is
`frontend/ops/db/alerting-postgres-schema.sql`. This schema assumes it can run
on either Neon Postgres or RDS Postgres and does not depend on Neon-specific
features. To follow an existing DB, apply `frontend/ops/db/migrations/*.sql` in
filename order after applying the baseline. Migrations record the version in
`ops_alert_schema_migrations` and use only Postgres-compatible SQL.

Even when migrating to a DB, maintain the following.

- Keep the delivery state semantics of `alert_key` / `last_payload_hash` /
  `last_notified_at` / `notification_count` consistent with the file-backed
  state.
- Webhook receipts store both success / failure, but only the `ok=true` success
  receipt satisfies `lastNotifiedAt` in state reconciliation.
- Public comms reflected to the app banner / status page are stored in
  `ops_public_comms_publications` and `ops_public_comms_publication_alerts`, with
  channel, status, source alert key, approved / published / expires timestamps,
  `public_url`, `public_text`, approved payload hash, source alert payload hash,
  and redacted evidence.
  A publication-alert row whose `source_payload_hash` is NULL is treated as
  legacy / unaugmented evidence and is not counted, in public comms coverage, as
  evidence that satisfies the current alert payload.
  Do not include query / fragment URLs, secret-bearing text, or internal routing
  aliases in `public_text` / `evidence`.
  Before the DB insert, inspect the approved publication JSON with
  `frontend/ops check-public-comms-publication`, and generate the approved
  payload hash and `dbRows` (the value set passed to a parameterized insert, not
  an SQL string).
  When `--state` (or `OPS_PUBLIC_COMMS_PUBLICATION_STATE_PATH`) is specified, it
  also checks that the source alert key matches a public comms target alert, and
  that the status is `triggered` for active-class statuses and `resolved` for
  `resolved` / `removed`, and fixes the `lastPayloadHash` at that point into
  `sourceAlertPayloadHashes`.
  `dbRows.opsPublicCommsPublicationAlerts[].sourcePayloadHash` passes this fixed
  value into `ops_public_comms_publication_alerts.source_payload_hash`.
  In Day-1 file-backed operation, the output of
  `check-public-comms-publication` is saved as JSONL in
  `OPS_PUBLIC_COMMS_PUBLICATIONS_PATH`, and `frontend/ops
  check-public-comms-publications` is run at handoff / retrospective. An active
  public comms target alert is covered by an active-class publication, a resolved
  alert by the latest evidence of a `resolved` / `removed` publication, and it
  fails closed unless the publication-side source alert payload hash matches the
  current alert state.
  Before importing into the DB, `frontend/ops
  export-public-comms-db-insert-plan` converts the JSONL into an insert plan in
  table / column / row form. This plan does not contain SQL strings and by
  default rejects a missing `sourcePayloadHash`. Only when moving legacy rows for
  inventory purposes, specify `--allow-missing-source-payload-hash` explicitly.
- Do not store raw webhook URLs, bearer tokens, chat permalinks, or
  secret-bearing errors in the DB. The storage targets are only the redacted
  target and redacted error.
- On either Neon / RDS, leave the same migration, backup, restore drill, and
  network policy / RLS policy in the launch evidence. Even when adding a DB,
  retain the JSONL export at least for rollback / restore drills.

Minimal env example:

```json
{
  "ops-critical": {
    "urlEnv": "OPS_ALERTS_OPS_CRITICAL_WEBHOOK_URL",
    "bearerTokenEnv": "OPS_ALERTS_WEBHOOK_BEARER_TOKEN"
  },
  "ops-watch": {
    "urlEnv": "OPS_ALERTS_OPS_WATCH_WEBHOOK_URL"
  }
}
```

Day-1 default routing:

| Scope | Owner alias | ACK | Channel aliases |
| --- | --- | --- | --- |
| P0 default | `incident-commander` | 10m | `ops-critical`, `incident-command` |
| P1 default | `ops-duty` | 30m | `ops-alerts` |
| P2 default | `ops-duty` | 240m | `ops-watch` |
| P3 / resolved default | `ops-duty` | 1440m | `ops-resolved` |
| oracle / JPY freeze | `oracle-ops` | severity default | `oracle-ops` plus severity channel |
| vault buffer / backstop | `vault-ops` | severity default | `vault-ops` plus severity channel |
| strategy health / writeoff | `strategy-ops` or `incident-commander` | severity default / P0 10m | `strategy-ops` or `strategy-incident` |
| market health | `risk-ops` | severity default | `risk-ops` plus severity channel |
| frontend / data publish | `frontend-ops` | severity default | `frontend-ops` plus severity channel |
| public comms required | route-specific | severity default | include `public-comms` |

### 4.1 Notification Catalog

The following is the Day-1 standard notification catalog. `Alert ID` is the
operational identifier used in the notification platform, Private Operations Monitor, and
incident log; it is not a component spec requirement ID.

| Alert ID | Trigger | Severity | Public | Primary source | Initial action |
| --- | --- | --- | --- | --- | --- |
| `ALRT-ORCL-001` | branch-local feed-age warning boundary: 80% of the staleness threshold by default; for the dwstETH redemption stETH/ETH leg only, age reaches 88,200s (24.5h), set above the feed's own ~24h heartbeat so ordinary updates stay silent, leaving ~30min before expiry | P2 | No | Chainlink `latestRoundData.updatedAt` / Parameters §2-C | Check feed health, the latest round, and time remaining before expiry |
| `ALRT-ORCL-002` | branch-local feed stale / invalid / revert risk | P1 | No, unless user operation is impacted | polling + `fetchPrice` dry-run | Check the on-chain failure path |
| `ALRT-ORCL-003` | `shutdownTime > 0` / irreversible economic shutdown | P0 | Yes | ActivePool / BorrowerOperations state and `ShutDown` event | Check the user-app block for new operations and the urgent-redemption path |
| `ALRT-ORCL-004` | JPY/USD shared feed age >= 80% of staleness threshold | P2 | No | shared JPY/USD `latestRoundData.updatedAt` | Confirm early as a dependency shared across all branches |
| `ALRT-ORCL-005` | shared provider `JpyRateFrozen` / `jpyFrozenSince > 0` | P1 | No initially | `JpyUsdRateProvider` state / event | Record the freeze start block, confirm every active source references the same provider, and determine whether an alternative source is needed |
| `ALRT-ORCL-006` | shared JPY/USD freeze >= 6h and no recovery path | P0 | Prepare | provider `jpyFrozenSince`, source proposal state | Escalate to the oracle owner / GOV |
| `ALRT-ORCL-007` | shared JPY/USD freeze >= 12h or `JpyFreezeExpired` | P0 | Yes | provider state / event | Prepare a public update; on expiry verify each active branch's oracle pause / `priceSource` and user-action block. Provider recovery alone does not clear the pause flag |
| `ALRT-ORCL-008` | JPY/USD provider freeze resolved | P3 / Recovery | No, unless public notice was posted | `JpyRateUnfrozen` / state | Inventory every branch's oracle pause / `priceSource`; if a BO pause is active, lift the public notice only after the owner validates normal / redemption / urgent and calls `resumeFromOracleFailure()`. An age-only gate resolves on a fresh round without owner action |
| `ALRT-ORCL-009` | `SourceProposed` | P2 | No | PriceFeedProxy event/state | Notify the timelock deadline and the smoke-test owner |
| `ALRT-ORCL-010` | `SourceSwitchValidated.priceGuardBypassed == true` | P1 | No, unless user impact exists | PriceFeedProxy event | Audit the emergency bypass and price difference |
| `ALRT-ORCL-011` | dwstETH stETH/ETH divergence `>= 0.5%` | P2 | No | stETH/USD and ETH/USD oracle legs | Review the divergence trend, both feed-health states, and that the redemption quote always uses the higher leg |
| `ALRT-ORCL-012` | `fetchUrgentRedemptionPrice()` synthetic revert, `RedemptionReferenceUnavailable`, or a stale / invalid / reverting redemption auxiliary leg | P0 | Yes | process-external PriceFeedProxy `eth_call`, auxiliary-feed `latestRoundData`, and normal-redemption source event | Group by `chainId + branch + PriceFeedProxy` and treat the synthetic as current-state truth. For a temporary feed outage, verify recovery on the same source; replace the source after 12h only for a source defect. Do not fall back to cache/direct-only pricing or rely on an event that may roll back with the failed transaction |
| `ALRT-ORCL-013` | wstETH canonical rate decreases from the preceding observation | P1 | No initially | wstETH `stEthPerToken()` polling | Investigate slashing/negative rebase and assess collateral-value and liquidation impact |
| `ALRT-ORCL-014` | `SourceFailureHandled` / `isOracleFailureShutdown == true` | P0 | Yes | PriceFeedProxy event and BorrowerOperations state | Check the user-app block, keeper continuity, and recovery of normal / redemption / urgent. Do not advertise urgent redemption while `shutdownTime == 0` |
| `ALRT-ORCL-015` | Active-path Chainlink proxy `decimals()` differs from the current source/provider value, configured/live reads fail, or a new source's auxiliary-getter coverage is incomplete | P0 | Yes | source/provider and Chainlink proxy reads pinned to the RPC safe head | Stop borrow/liquidation/redemption for collateral or JPY legs, but only normal/urgent redemption for auxiliary legs; verify the Chainlink phase and a healthy source/provider replacement |
| `ALRT-ORCL-016` | At one safe block, only Proxy normal-redemption returns `failure=true`; current-source normal-redemption and Proxy normal/urgent are healthy; BO pause is false | P0 | Yes | hash-rechecked PriceFeedProxy / current source / provider / BorrowerOperations reads | Confirm that only normal redemption is halted and diagnose the shared JPY round/provenance. Confirm same-key resolution on a fresh round; do not pause/resume or replace the source absent a real source failure |
| `ALRT-PEG-001` | active wrapper-collateral peg monitor Watch band | P2 | No | off-chain peg monitor | Check source dispersion |
| `ALRT-PEG-002` | active wrapper-collateral peg monitor Incident band | P1 | No, unless pause is executed | off-chain peg monitor | Manually consider Guardian action |
| `ALRT-PEG-003` | active wrapper-collateral peg monitor Critical band | P0 | Yes if exposure/user operation exists | off-chain peg monitor | Evaluate cap freeze / source review / shutdown criteria |
| `ALRT-VAULT-001` | `bufferBalance < bufferTargetAmount` | P2 | No | CollateralVault read | Check allocation and redeem volume |
| `ALRT-VAULT-002` | `pendingWithdrawals > bufferBalance` | P1 | Yes if claim-delay users are affected | CollateralVault read | Restore claim funding and convene the user comms owner |
| `ALRT-VAULT-003` | `pausedRedeem || pausedClaim` | P0 | Yes | CollateralVault pause flags / events | Check the user app banner and resumption conditions |
| `ALRT-VAULT-004` | `pausedDeposit` | P1, P0 if active public branch | Yes if public deposit/borrow path is exposed | CollateralVault pause flag / event | Check the Borrow/Zapper UI block and the reason |
| `ALRT-VAULT-005` | `pausedAllocation` | P2, P1 in active Strategy incident | No by itself | CollateralVault pause flag / event | Record the reason for halting outbound allocation |
| `ALRT-VAULT-006` | oldest claimable WithdrawRequest age reaches configured threshold | P1 | Yes if users are affected | private WithdrawRequest read model | Check count, amount, refill progress, and user communications |
| `ALRT-VAULT-007` | buffer-eligible observed age reaches configured threshold | P1 | No initially | private periodic observation | Check claim processing; do not infer continuous availability or starvation |
| `ALRT-VAULT-008` | confirmed expected outflow reaches 50% of immediate headroom, would leave the buffer below target, exceeds immediate headroom, or the forecast source is unhealthy | P2; P1 when immediate headroom is exceeded | No; actual user impact is determined by `ALRT-VAULT-002` | Vault snapshot + expiring operator input bound to chain and Vault | Check Strategy recoverability, refill owner, deadline, and source freshness |
| `ALRT-BACK-001` | `backingRatio < 1e18` | P0 | Yes | CollateralVault `backingRatio` / PriceFeed effective price | Escalate to the Strategy incident runbook |
| `ALRT-BACK-002` | `backingShortfall > 0` | P0 | Yes | CollateralVault `backingShortfall` | Classify backstop / writeoff / recovery |
| `ALRT-STGY-001` | Strategy `estimatedTotalUnderlying` unavailable | P2 | No | Strategy view reads | Check the bounded cache / external protocol health |
| `ALRT-STGY-002` | Strategy estimated loss > 0 | P1, P0 if backing drops | No initially | Strategy valuation / Vault backing | Check live valuation and double-writeoff risk |
| `ALRT-STGY-003` | async pending valuation bps < 10000 | P1 | No, unless user flow paused | Lido / Etherfi strategy state | Check `pausedAllocation` and bot skip |
| `ALRT-STGY-004` | external venue incident / withdraw halt / bad debt / Aave reserve deficit | P1, P0 if backing/user flow impacted | Case-by-case | external monitor + pinned chain read + ops confirmation | incident mode, pause, bot skip; reserve deficit alone is not realized loss |
| `ALRT-STGY-005` | `writeoffStrategyPrincipal` proposal or execution | P0 | Yes on execution, prepare on proposal | CollateralVault event / Safe queue | Check Troves near MCR and the post-price |
| `ALRT-STGY-006` | `backstopDeposit` / `releaseBackstopToBuffer` | P2, P1 if resolving claim shortfall | No, unless public notice exists | CollateralVault event | Check claim coverage and update the notice |
| `ALRT-STGY-007` | writeoff Safe queue monitor unavailable | P2 | No | Safe queue monitor endpoint | Check the Safe queue monitor endpoint, credential, and scheduler |
| `ALRT-MKT-001` | TCR < CCR | P1 | No initially | TroveManager / ops snapshot | Check the crisis-mode copy and borrow route |
| `ALRT-MKT-002` | TCR < SCR or SCR breach path | P0 | Yes if shutdown/user impact | TroveManager / ops snapshot | Check the shutdown / urgent redemption path |
| `ALRT-MKT-003` | SP coverage below launch gate minimum | P1 | No initially | StabilityPool / launch gate config | Check the SP top-up / JIT owner |
| `ALRT-MKT-004` | large redemption / redemption base rate spike | P2, P1 if user impact large | No initially | CollateralRegistry / event index | Check exit liquidity and borrow APR policy |
| `ALRT-MKT-005` | JPYdf/USDC pool price/depth outside launch envelope | P1 | Yes if user exit materially impacted | Uniswap v4 pool monitor | Check the LP / treasury owner and user copy. For an upward deviation, derive debt capacity from live state and use a manual/Safe-approved company-Trove debt increase and market sale; persistent deviations may accelerate the cap ramp under `SYS-RISK-009` |
| `ALRT-MKT-006` | market liquidity monitor unavailable | P2 | No | Uniswap v4 pool monitor endpoint | Check the market monitor endpoint, credential, and scheduler |
| `ALRT-MKT-007` | active branch dToken cap usage >= 8,000 bps | P2, P1 if >= 9,500 bps | No initially | DToken `totalSupply` / `cap` | Check the cap ramp runbook, SP coverage, and whether a Timelock queue is needed |
| `ALRT-MKT-008` | gas fee spike / blockspace congestion band | P2, P1 if incident/critical | No initially | external gas market monitor | Check the gas fee envelope, keeper/relayer budget, and user tx copy |
| `ALRT-FRNT-001` | user app critical route synthetic failure | P1 | Yes if persistent | synthetic monitor | Check hosting/CDN/RPC |
| `ALRT-FRNT-002` | all RPC fallback down and write UI disabled | P0 | Yes | runtime health / app telemetry | banner, status page, provider escalation |
| `ALRT-FRNT-003` | subgraph stale beyond threshold | P2, P1 if values are visually mixed | No | subgraph sync monitor | Check the display separation from the RPC current value |
| `ALRT-FRNT-004` | public stats JSON stale/unavailable | P2, P1 if user app shows stale as live | No, unless public data is misleading | stats publisher / CDN health | Check the stale display and the publisher |
| `ALRT-FRNT-005` | official domain/link integrity or phishing incident | P0 | Yes | link monitor / security report | official notice and distribution freeze |
| `ALRT-FRNT-006` | frontend monitor / health report unavailable | P2 | No | runtime / link-integrity monitor endpoint | Check the monitor endpoint, credential, and scheduler |
| `ALRT-FRNT-007` | access pressure / traffic surge above capacity envelope | P2, P1/P0 if user flow impacted | Yes only when public impact is confirmed | CDN/WAF/API/RPC access monitor | Check CDN/WAF/rate limit/autoscale/RPC quota and whether public comms is needed |

### 4.2 Day-1 Implementation Priority

The Day-1 minimal implementation prioritizes putting the current-state alerts
already displayed by `frontend/ops` into a form that can be sent to external
notifications.

1. **P0 / P1 current-state alerts**
   `ALRT-ORCL-003`, `ALRT-ORCL-005..007`, `ALRT-ORCL-012..016`, `ALRT-VAULT-002..004`,
   `ALRT-BACK-001..002`, `ALRT-STGY-005`, `ALRT-FRNT-002`.

2. **P2 watch alerts**
   `ALRT-ORCL-001`, `ALRT-ORCL-004`, `ALRT-VAULT-001`,
   `ALRT-MKT-001`, `ALRT-FRNT-003..004`.

3. **Event-indexed alerts**
   To the extent that `frontend/ops` EventData is available, connect
   `StrategyPrincipalWrittenOff`, `BackstopDeposited`, `BackstopReleased`,
   large `Redemption`, and `SourceSwitchValidated.priceGuardBypassed` to
   `deriveAlerts(snapshot, events)`.
   `SourceProposed` is detected by current-state polling of
   `PriceFeedProxy.proposedSource/sourceProposedAt`. A Safe queue proposal is
   detected by the Safe queue monitor, and an external venue incident by the
   external risk health monitor.

4. **External-source alerts**
   The active-wrapper-collateral peg monitor, Aave / Lido / Etherfi / Sky
   external incidents, and official domain / link integrity are enabled as
   health-report inputs only after fixing the owner and evidence format of the
   external monitor in the launch evidence.

### 4.3 Correspondence with the current `frontend/ops`

The current `deriveAlerts()` in `frontend/ops/src/lib/alerts.ts` generates
alerts for Private Operations Monitor and public stats, and attaches auxiliary
metadata that can be passed to the notification platform
(`alertId` / `policySeverity` / `publicMessageRequired` / `action` /
`runbook` / `kind` / `sourceKey` / `currentValue` / `threshold`). The
implementation-level source of truth for the metadata is `ALERT_POLICY` in
`frontend/ops/src/lib/alertCatalog.ts`, kept in sync with the runbook's catalog.
Conversion to the notification payload is handled by
`frontend/ops/src/lib/alertNotifications.ts`, team alias / ACK / channel routing
by `frontend/ops/src/lib/alertRouting.ts`, and manual export by `frontend/ops
export-alerts`. Delivery-candidate dedupe / resolved generation is handled by
`frontend/ops/src/lib/alertDelivery.ts` and `frontend/ops notify-alerts`.
Using `OPS_ALERTS_ROUTING_POLICY_JSON` (or `--routing-policy-json`), the
`owner` / `channels` / `ackDeadlineMinutes` / `routeId` of `defaultRoute`,
`severityRoutes`, `kindRoutes`, and `alertIdRoutes` can be overridden per
production environment. Resolve actual delivery destinations such as Slack / SNS
/ PagerDuty as channel aliases in `OPS_ALERTS_CHANNEL_WEBHOOKS_JSON`, and swap
the duty rotation by substituting the routing policy's `owner` and channel
aliases as environment variables.
Routing resolution starts from the severity route and adds, with deduplication,
the channel aliases of the kind route and the alertId route. Therefore the
default channels for P0 / P1 / P2 / P3 are maintained, and responsible channels
for oracle / vault / frontend, etc. are added on top. `public-comms` is included
only in alerts with `publicMessageRequired=true`.
The external status sync in `frontend/ops/src/lib/alertExternalStatus.ts` and
`frontend/ops/src/lib/alertDelivery.ts` imports the `acknowledged` /
`escalated` state per `alertKey` from an external incident management system via
`OPS_ALERTS_EXTERNAL_STATUS_JSON` or `OPS_ALERTS_EXTERNAL_STATUS_URL`, and
delivers `status=acknowledged` / `status=escalated` of the schema v1 payload only
on state change. The external incident URL drops query / fragment, and a URL
fetch failure does not stop new alert delivery and remains in the summary as
`externalStatusError`.
`alertDelivery` fixes the ACK deadline at the time of first firing as
`ackDeadlineAt` in state, and does not re-extend the deadline even if the same
alert continues. If external `acknowledged` / `escalated` is not synced at the
point `ackDeadlineAt` is reached, it automatically delivers a `status=escalated`
payload once, recorded as `externalStatus.actor=auto-escalation`.
The `notify-alerts` summary outputs `state.active`, `state.unacknowledged`,
`state.ackOverdue`, `state.escalated`, `state.publicMessageRequiredActive`, and
`state.activeBySeverity`, so operators confirm in the same output not only the
delivery result but also the currently remaining unACKed, overdue, and public
comms target alerts.
To check only saved state, `frontend/ops summarize-alert-state` reads
`OPS_ALERTS_STATE_PATH` (or `--state`) and outputs the same state summary to
stdout. At handoff / post-incident review, specify the evaluation time with
`--now` to recompute ACK deadline overruns.
`frontend/ops/src/lib/publicStatsHealth.ts` generates `ALRT-FRNT-004` from the
external check result of `OPS_PUBLIC_STATS_URL`, and uses the URL with query /
fragment dropped as `sourceKey`. A `generatedAt` exceeding
`OPS_PUBLIC_STATS_STALE_THRESHOLD_SEC` (when unset,
`OPS_STATS_STALE_THRESHOLD_SEC`, default 300s) is treated as stale. When
`OPS_PUBLIC_STATS_USER_APP_SHOWS_LIVE=1`, it is raised to P1 on the premise that
the user app is showing it as if live.
`frontend/ops/src/lib/statsPublisherHealth.ts` generates the same
`ALRT-FRNT-004` from the publisher job health report of
`OPS_STATS_PUBLISHER_HEALTH_JSON` or `OPS_STATS_PUBLISHER_HEALTH_URL`. The report
receives `ok` / `success`, `status` / `jobStatus`, `stage` / `failureStage`,
`category` / `errorCategory`, `lastSuccessAt`, and `publicStatsUrl`, and leaves
in the notification the failure stage such as snapshot fetch / stats build / S3
put / stable key conditional write / CDN invalidation before the public stats
JSON becomes stale. When the error contains a URL, the secret-bearing path /
query / fragment is masked.
`frontend/ops/src/lib/frontendSyntheticHealth.ts` generates `ALRT-FRNT-001` from
the external check result of `OPS_FRONTEND_SYNTHETIC_ROUTES_JSON`, and uses the
URL with query / fragment dropped as `sourceKey`. The JSON is an array of URL
strings or `{ label, url, expectedText, publicMessageRequired }` objects.
`OPS_FRONTEND_SYNTHETIC_TIMEOUT_MS` is the fetch timeout per route, default
10,000ms. By default it does not set the public-announcement flag, and via
`OPS_FRONTEND_SYNTHETIC_PUBLIC_MESSAGE_REQUIRED=1` or per-route
`publicMessageRequired: true`, it raises a route already judged a persistent
failure to a public comms candidate.
`frontend/ops/src/lib/frontendRuntimeHealth.ts` generates `ALRT-FRNT-002` from
the runtime health report of `OPS_FRONTEND_RUNTIME_HEALTH_JSON` or
`OPS_FRONTEND_RUNTIME_HEALTH_URL`. The report treats `writeUiDisabled: true`
together with `allRpcFallbacksDown: true` or all `rpcFallbacks[].ok` being
`false` as the P0 condition. When the runtime health report endpoint is
unavailable, it is not treated as a confirmed UI halt but as `ALRT-FRNT-006`,
with a fail-soft notification to the monitor owner.
Even when snapshot RPC fetch fails, `notify-alerts` generates the notification
payload with an `observedAtBlock=0` fallback snapshot if an external health alert
exists.
When `OPS_MIN_SP_COVERAGE_BPS` (or `--min-sp-coverage-bps`) is set,
`ALRT-MKT-003` is generated when the `spCoverage` of an active branch with public
exposure falls below the same bps. Set the threshold to the value approved in the
launch operation config / evidence; when unset, the business target is undetermined
and no firing occurs.
When `OPS_REDEMPTION_RATE_SPIKE_BPS` (or `--redemption-rate-spike-bps`) is set,
`ALRT-MKT-004` is generated when
`CollateralRegistry.getRedemptionRateWithDecay()` exceeds the same bps. It uses
the same ID as the large redemption event and routes to the check of exit
liquidity, borrow APR policy, and the lowest-rate Trove distribution.
`frontend/ops/src/lib/safeQueueAlerts.ts` decodes the `to + data` of the Safe
queue JSON passed by `OPS_WRITEOFF_SAFE_QUEUE_JSON` or
`OPS_WRITEOFF_SAFE_QUEUE_URL` as `CollateralVault.writeoffStrategyPrincipal`
calldata, and generates `ALRT-STGY-005` from an unexecuted proposal. It uses the
same ID as the execution event, but at the proposal stage it overrides
`publicMessageRequired=false` and treats public comms as pre-execution
preparation.
`frontend/ops/src/lib/poolLiquidityHealth.ts` generates `ALRT-MKT-005` from the
JPYdf/USDC liquidity monitor report of `OPS_POOL_LIQUIDITY_HEALTH_JSON` or
`OPS_POOL_LIQUIDITY_HEALTH_URL`. The report receives `poolInitialized`,
`liquidity/minLiquidity`, `priceBps/minPriceBps/maxPriceBps`, and
`quotes.*.slippageBps/maxSlippageBps`, and notifies an envelope breach from the
same perspective as the pool depth / sample sell-buy slippage of the launch
operation evidence.
The MarketData report checker, input publisher, and state collector expose
separate failure-log, missing-success-heartbeat, and EventBridge
`FailedInvocations` alarms through the shared backend SNS topic. These alarms
map to `ALRT-MKT-006`. A state-collector heartbeat counts only after S3 publish
and when read-only protocol state plus configured inventory / pool inputs are
available, so publishing unusable chain state with exit code 0 is not treated as
success. The backend readiness check inspects every enabled alarm. Before
production readiness, exercise each path as a labeled staging incident and
record ALARM / OK history, successful SNS actions, human receipt, and resolution
without recording endpoints or secrets.
`frontend/ops/src/lib/externalRiskHealth.ts` generates `ALRT-PEG-001..003` and
`ALRT-STGY-004` from the external risk report of
`OPS_EXTERNAL_RISK_HEALTH_JSON` or `OPS_EXTERNAL_RISK_HEALTH_URL`. The report
maps the XAUT/XAU `band`, `median1hBps`, `sampleBps`, and `dispersionBps` of
`pegMonitors[]` / `xautPeg` to the Watch / Incident / Critical bands of
[`Oracle.md`](../../../protocol/product/spec/Oracle.md) `ORCL-TBD-003`. Furthermore, it notifies
active incidents, withdraw halts, bad debt, backing impact, and user flow impact
of Aave / Lido / Etherfi / Sky, etc. in `protocolIncidents[]` as Strategy health
incidents. `gasMarkets[]` is mapped to `ALRT-MKT-008` for execution gas /
blockspace congestion, and when there is no explicit `band`, it is classified by
max fee gwei and the monitor-provided threshold (when unspecified, watch 150 /
incident 300 / critical 600 gwei). `accessMonitors[]` / `trafficMonitors[]` map
request rate, error rate, p95 latency, saturation, rate-limit ratio, and queue
depth to `ALRT-FRNT-007`, with watch at 80% capacity, incident on threshold
exceedance, and critical near 2x / saturation. The URL drops query / fragment and
does not leave the secret-bearing report URL of the external source in the
payload.

For the Aave V3 Ethereum USDC reserve deficit, the Private Monitor scheduled task is another process-external machine source for the same `ALRT-STGY-004`. It reads `getReserveDeficit` from the canonical Pool/USDC at a fresh pinned `safe` block and delivers nonzero P1, RPC/read/canonicality/safe-head-freshness-failure P2, fifteen-minute identity-bound execution-heartbeat absence P2, and zero-recovery OK as distinct states through record SNS and Amazon Q. A structured CloudWatch Logs report includes block number/hash/timestamp, asset, base-unit deficit, and fixed config identity, but no private RPC URL. The current CloudWatch alarm body does not embed that dynamic context, so delivery of the same context to the external recipient remains pending before a cap increase. The signal does not replace human confirmation of the external incident report and does not mean realized Strategy loss or automatic pause/writeoff.
`frontend/ops/src/lib/linkIntegrityHealth.ts` generates `ALRT-FRNT-005` from the
official link / domain integrity report of `OPS_LINK_INTEGRITY_HEALTH_JSON` or
`OPS_LINK_INTEGRITY_HEALTH_URL`. The report receives `ok=false` of `checks[]` and
active reports of `incidents[]` / `phishingReports[]`, and treats the official
domain, canonical origin, hosting manifest, official social / docs link, and
phishing report as the same P0 security integrity incident. The payload's
`sourceKey` drops the URL query / fragment and does not leave tokens, wallet
addresses, report queries, etc. in the notification. This is not the production
incident management system itself, but it can be reused as the input and delivery
adapter for Day-1 notifications.

| Current display alert | Corresponding Alert ID | Notes |
| --- | --- | --- |
| JPY/USD shared feed age warning / critical | `ALRT-ORCL-004` | A layer is needed to convert the 80% warning and stale critical into policy P2/P1/P0 |
| branch-local collateral/USD feed age warning / critical | `ALRT-ORCL-001`, `ALRT-ORCL-002` | A recoverable pause is separately `ALRT-ORCL-014` |
| `jpyFrozenSince > 0` | `ALRT-ORCL-005..007` | A conversion that splits P1/P0 by elapsed time is needed |
| `isOracleFailureShutdown == true` | `ALRT-ORCL-014` | Normal operations stop while interest continues; owner resume requires normal / redemption / urgent paths healthy |
| configured / live Chainlink decimals mismatch or unreadable value | `ALRT-ORCL-015` | Compare five active feeds at the RPC safe head and page P0 per stable feed-role key, including incomplete coverage |
| Proxy-local normal-redemption gate | `ALRT-ORCL-016` | Compare Proxy/current-source/BO reads at one safe block and page P0 for normal-redemption-only halt and same-key fresh-round resolution |
| `shutdownTime > 0` | `ALRT-ORCL-003` / `ALRT-MKT-002` | Cause classification is supplemented by the event / failed oracle address |
| `backingRatio < 1e18` | `ALRT-BACK-001` | Public announcement target |
| `pendingWithdrawals > bufferBalance` | `ALRT-VAULT-002` | A public announcement target when there are users past the claim delay |
| `bufferBalance < bufferTargetAmount` | `ALRT-VAULT-001` | Internal watch |
| Vault pause flags | `ALRT-VAULT-003..005` | Determine whether a public announcement is needed by user flow impact |
| Strategy estimate unavailable / estimated loss / async pending bps | `ALRT-STGY-001..003` | Combined with the external incident monitor to become P1/P0 |
| Aave / Lido / Etherfi / Sky external incident / withdraw halt / bad debt | `ALRT-STGY-004` | Imported from `protocolIncidents[]` of `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL |
| `TCR < CCR` / `TCR < SCR` | `ALRT-MKT-001`, `ALRT-MKT-002` | The SCR breach / shutdown path is a public announcement candidate |
| `spCoverage < OPS_MIN_SP_COVERAGE_BPS` | `ALRT-MKT-003` | Make the threshold match the launch operation config / evidence. Disabled when unset |
| Safe queue `writeoffStrategyPrincipal` calldata | `ALRT-STGY-005` | Detect an unexecuted tx from `OPS_WRITEOFF_SAFE_QUEUE_JSON` / URL. The proposal stage is public announcement preparation |
| writeoff Safe queue monitor unavailable | `ALRT-STGY-007` | A Safe queue monitor outage is not treated as a P0 writeoff proposal; notify as P2 without dropping the delivery job |
| `StrategyPrincipalWrittenOff` event | `ALRT-STGY-005` | Treated as a P0 public announcement candidate in the dashboard / verify path |
| `BackstopDeposited` / `BackstopReleased` event | `ALRT-STGY-006` | Check whether the recovery / claim coverage notice needs updating |
| large `Redemption` event | `ALRT-MKT-004` | Watch within the recent block window and at or above 10 million JPYdf or 5% of total debt |
| `redemptionRateWithDecay >= OPS_REDEMPTION_RATE_SPIKE_BPS` | `ALRT-MKT-004` | CollateralRegistry current-state polling. Disabled when unset |
| JPYdf/USDC pool initialized / liquidity / price / slippage envelope breach | `ALRT-MKT-005` | Import external monitor evidence from `OPS_POOL_LIQUIDITY_HEALTH_JSON` / URL |
| market liquidity monitor unavailable | `ALRT-MKT-006` | A pool liquidity monitor outage is not treated as a confirmed market breach; notify as P2 |
| gas fee spike / blockspace congestion band | `ALRT-MKT-008` | Import from `gasMarkets[]` / `gasReports[]` of `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL |
| active wrapper collateral peg monitor Watch / Incident / Critical band | `ALRT-PEG-001..003` | Import from `pegMonitors[]` (including the stETH/ETH series) / `xautPeg` of `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL |
| access pressure / traffic surge / rate-limit envelope breach | `ALRT-FRNT-007` | Import from `accessMonitors[]` / `trafficMonitors[]` of `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL |
| official link / domain integrity failure or active phishing report | `ALRT-FRNT-005` | Import security monitor evidence from `OPS_LINK_INTEGRITY_HEALTH_JSON` / URL |
| frontend synthetic route failure | `ALRT-FRNT-001` | External check of `OPS_FRONTEND_SYNTHETIC_ROUTES_JSON`. query / fragment are excluded from the payload |
| all RPC fallback down and write UI disabled | `ALRT-FRNT-002` | Detect from runtime health JSON / URL. Can notify with a fallback snapshot even when snapshot RPC fails |
| frontend runtime / link-integrity health report unavailable | `ALRT-FRNT-006` | A monitor outage is not made a confirmed P0 incident; notify as P2 without dropping the delivery job |
| public stats JSON stale / unavailable | `ALRT-FRNT-004` | External check of `OPS_PUBLIC_STATS_URL`. query / fragment are excluded from the payload |
| stats publisher job failure / health report unavailable | `ALRT-FRNT-004` | Notify the failure stage / category / last success from `OPS_STATS_PUBLISHER_HEALTH_JSON` / URL |
| `proposedSource != 0 && sourceProposedAt > 0` | `ALRT-ORCL-009` | Notify the timelock confirmable time and smoke-test owner by current-state polling |
| `SourceSwitchValidated.priceGuardBypassed == true` event | `ALRT-ORCL-010` | Notify the emergency bypass and price-difference audit via the PriceFeedProxy event index |
| dwstETH stETH/ETH divergence and wstETH canonical-rate decrease | `ALRT-ORCL-011..013` | Poll both USD legs and `stEthPerToken()` as the `ORCL-FR-015` monitoring source |

Items not covered that require separate implementation:

- ACK / escalation state sync with an external incident management system

## 5. Oracle Notifications

### 5.1 Staleness Approach

| Condition | Severity | Initial response |
| --- | --- | --- |
| Remaining stale time of a branch-local feed is 25% or less of the threshold | P2 | Check feed metadata, latest round, RPC / Chainlink status |
| Remaining stale time of JPY/USD is 25% or less of the threshold | P2 | Notify the incident owner early as a dependency shared across all branches |
| Polling detects an invalid round / future timestamp / `answer <= 0` | P1 | Check whether the on-chain `fetchPrice` path hits the same failure |

The source-of-truth values for staleness are in
[`Parameters.md`](../../../Parameters.md) §2-C. The monitor assumes a strict `<`
comparison and does not treat exactly the threshold as fresh.

### 5.2 JPY/USD soft-freeze

| Condition | Severity | Initial response |
| --- | --- | --- |
| provider `JpyRateFrozen` or `jpyFrozenSince > 0` | P1 | Record the provider address and freeze start block, prove all active sources reference it, and check every branch price-fetch path |
| Only Proxy normal-redemption returns `failure=true`, while current-source normal-redemption and Proxy normal/urgent are healthy and BO pause is false | P0 | `ALRT-ORCL-016`. Save the same-block/hash Proxy/source/provider/BO reads, show only normal redemption as halted, and use cached age only to diagnose the exact 30h boundary |
| 6h elapsed since freeze, with no recovery prospect or source proposal | P0 | Escalate to GOV / oracle owner. Prepare an alternative source and public comms |
| 12h elapsed since freeze | P0 | Raise shutdown risk to a public announcement candidate and decide the next update time |
| `JpyRateUnfrozen` | P3 / Recovery | Record the freeze price, user impact, and each branch's oracle pause / `priceSource`; where a BO pause is active, do not close until the owner validates normal / redemption / urgent and explicitly resumes. An age-only gate closes automatically after the first fresh round |
| provider `JpyFreezeExpired` / `MAX_JPY_FREEZE_DURATION` reached | P0 | Confirm alert delivery, each active branch's oracle pause / `priceSource`, public notice, and user app block. Fresh recovery makes live-source validation possible, but `isOracleFailureShutdown` remains set until owner `resumeFromOracleFailure()` |

A JPY/USD freeze is not an immediate branch shutdown. Once the cached shared
JPY/USD round age reaches 30h, only normal redemption fails closed; borrowing,
liquidation, TCR/SCR, and the urgent-price path remain unchanged. The first call
that observes a fresh round recovers automatically, so do not replace the source
or invoke owner resume absent a real source failure or BO pause. While the other
price paths continue, keep public wording to a state description such as "the
shared FX leg for price conversion is temporarily continuing at the last-good
rate," and do not suggest asset impairment or compensation.

The `ALRT-ORCL-016` synthetic and route exist in code, but production readiness
requires a labeled `ALARM`, receipt by the intended human, and same-key `OK` /
resolution through the existing backend alarm SNS to Amazon Q Developer route.
Bot readback or successful CloudWatch/SNS actions alone are not human
acknowledgement.

### 5.3 Branch-local oracle pause / economic shutdown

| Condition | Severity | Initial response |
| --- | --- | --- |
| `SourceFailureHandled` or `isOracleFailureShutdown == true` | P0 | Check the affected branch's user-app new-operation block, keeper continuity, normal / redemption / urgent paths, and the Private Operations Monitor |
| `failedOracleAddr` is a backing / rate provider / peg leg | P0 | Refer to both the Oracle and Strategy / Vault runbooks and classify the root cause |

An oracle pause is not irreversible economic shutdown: interest keeps accruing and urgent redemption is not enabled. After the current normal price recovers, liquidation, the `TCR < SCR` check, and CCR-constrained close can continue, while BorrowerOperations and normal redemption remain paused until the owner calls Proxy `resumeFromOracleFailure()`. Resume validates all three price paths and clears the BO pause, but aged/invalid JPY provenance is not written to the normal-redemption cache and its age gate remains until a fresh round. Only irreversible economic shutdown with `shutdownTime > 0` enables urgent redemption.

A public announcement must always identify the affected branch, stopped and continuing operations, and whether the state is an oracle pause or economic shutdown.

### 5.4 Source replacement

| Condition | Severity | Initial response |
| --- | --- | --- |
| `SourceProposed` | P2 | Notify the confirmable time, the old/new source, and the smoke-test owner |
| `SourceProposalCancelled` | P3 | Set the pending alert to resolved |
| `SourceUpdated` | P3 | Check the post-switch price and cache update |
| `SourceSwitchValidated.priceGuardBypassed == true` | P1 | Record in the incident log as an emergency bypass and audit the price jump |

## 6. Peg Monitor Notifications

The peg monitor for active wrapper collateral uses the bands of
[`Oracle.md`](../../../protocol/product/spec/Oracle.md) `ORCL-SEC-006` and each asset's activation package.

| Condition | Severity | Initial response |
| --- | --- | --- |
| Watch band | P2 | Check source health and venue dispersion. No on-chain action in principle |
| Incident band | P1 | Guardian manually considers `pauseDeposit` / `pauseAllocation`. redeem / claim maintained in principle |
| Critical band | P0 | Evaluate the preconditions for cap freeze, source replacement review, and branch shutdown |
| Recovery band continues for 24h | P3 / Resolved | Unpause only after explicit Guardian / GOV approval |

The peg monitor does not auto-pause. A human confirms false positives caused by
weekend market-hour differences or venue noise.

## 7. Vault / Strategy Notifications

| Condition | Severity | Initial response |
| --- | --- | --- |
| `bufferBalance < bufferTargetAmount` | P2 | Check allocation and expected redeem volume |
| `pendingWithdrawals > bufferBalance` | P1 | Plan to restore claim funding. Convene the user comms owner if needed |
| confirmed expected outflow reaches 50% of `max(bufferBalance - pendingWithdrawals, 0)`, would leave the buffer below the pending-inclusive target, or the forecast source is unhealthy | P2 | `ALRT-VAULT-008`. Check Strategy recoverability, refill owner / deadline, and source freshness |
| confirmed expected outflow exceeds `max(bufferBalance - pendingWithdrawals, 0)` | P1 | Refill for the forecast queue. Use `ALRT-VAULT-002` for user communications only if an actual queue occurs |
| `pausedRedeem || pausedClaim` | P0 | Check the user app banner and resumption conditions |
| `backingRatio < 1e18` or `backingShortfall > 0` | P0 | Escalate to the Strategy incident runbook |
| `emergencyDisableStrategy` / Vault user flow pause | P1. P0 if user flow is halted | Check liquidation bot skip, public impact, and the recovery owner |
| `writeoffStrategyPrincipal` proposal / execution | P0 | Check Troves near MCR, bot safety, public comms, and the post-price |
| `backstopDeposit` / `releaseBackstopToBuffer` | P2. P1 resolved if it resolves the claim funding shortfall | Check claim coverage and the buffer resumption order |

Because a writeoff involves both "loss finalization" and "reflection into the
liquidation price," it is treated for notification purposes as a P0 event
separate from a freeze or recovery.

## 8. Branch / Market Health Notifications

| Condition | Severity | Initial response |
| --- | --- | --- |
| TCR approaching CCR | P2 | Check the borrow UI / rate policy / SP coverage |
| branch TCR < CCR | P1 | Check the consistency of the new-borrowing restriction and public copy |
| SP coverage below the launch gate minimum | P1 | Check SP top-up / JIT / public risk copy |
| large redemption or redemption base rate spike | P2. P1 if user impact is large | Check exit liquidity, borrow APR policy, and the lowest-rate Trove distribution |
| branch shutdown | P0 | Same as §5.3 |

## 9. Frontend / Data Notifications

| Condition | Severity | Initial response |
| --- | --- | --- |
| A key route of the user app fails in the synthetic monitor | P1 | Check the official origin / CDN / wallet route |
| All RPC fallback down and write UI halted | P0 | user app banner, status page, provider escalation |
| subgraph stale | P2. P1 if confused with the current-value display | Check the display separation from the RPC current value |
| public stats JSON stale / unavailable | P2. P1 if the user app shows it as if live | Check the stats publisher and cache header |
| official link / domain integrity failure | P0 | Public comms as a phishing / delivery incident |

## 10. Discipline for Public Announcement Wording

Public wording observes the following.

- Do not state a fixed ETA. A planned next-update time may be stated.
- Do not describe a buffer shortfall as "loss" or "insolvency."
- For a backing incident, do not assert whether recovery is possible or whether compensation will occur.
- Separate halted operations from operations that can continue.
- Provide tx hash / contract address as needed, but do not provide private endpoints, API keys, Safe nonces, or internal staff names.

Minimal public template:

```text
We have detected <state> on <branch/global>.
Currently halted operations: <operations>
Currently available operations: <operations>
Next update: <time or condition>
Please check the status page for details.
```

The `draftText` of `export-public-comms` satisfies this template but is a
pre-approval draft with `requiresOperatorApproval=true`. Do not post it
automatically; confirm that it does not contain a fixed ETA, a compensation
assertion, an internal owner name, or a secret, then reflect it to the app
banner / status page.
When reflecting to the status page, pass `OPS_STATUS_PAGE_UPDATE_JSON` or
`OPS_STATUS_PAGE_UPDATE_JSON_PATH` to `frontend/ops check-status-page-update`,
inspect the approved update JSON, and then pass it to the external status page
bridge. The raw `export-public-comms` report, an unapproved draft, a URL with
query / fragment, a fixed ETA, a compensation guarantee, an internal owner name,
and secret-bearing text fail closed.
When `--state` (or `OPS_STATUS_PAGE_UPDATE_STATE_PATH`) is specified, it also
checks that `sourceAlertKeys` matches a public comms target alert in the alert
delivery state. A `status=resolved` update is rejected unless the corresponding
alert is also `resolved` in state.
Immediately before lifting a banner or making a status page resolved update, run
`frontend/ops check-public-comms-clearance`. When `--source-alert-key` or
`OPS_PUBLIC_COMMS_SOURCE_ALERT_KEYS_JSON` is specified, it confirms that the
target is both a public comms target in state and `resolved`. When none is
specified, it confirms that there are 0 active public comms target alerts.
`frontend/ops check-alert-sla` audits the ACK / escalation SLA from saved
delivery state. If an active alert is past `ackDeadlineAt` and not ACKed, or if
the terminal timestamp of an `acknowledged` / `escalated` / resolved candidate is
after the deadline, it returns `ok=false` and exits 1. At handoff, daily review,
and incident retrospective, transcribe `breached[]` and `ackLatencySec` into the
incident log.

## 11. Resolved Conditions

Before setting a state to resolved, confirm the following.

| Type | Resolved condition |
| --- | --- |
| Oracle stale / freeze | The feed is fresh, `JpyRateUnfrozen` or normal price fetch, and the dashboard is green |
| Branch shutdown | Because a shutdown itself is irreversible, the alert is closed as `terminal` rather than `resolved`, and confirm that the user app's shutdown state is correct |
| Buffer shortfall | `pendingWithdrawals <= bufferBalance`, the claim UI is normal, and the necessary user comms update is done |
| Backing incident | Cause classified, and the post-state of backing / writeoff / backstop recorded. If not a full recovery, the residual risk is stated explicitly |
| Frontend outage | The synthetic monitor recovered, runtime health pass, and the incident banner lifted or updated |

## 12. Evidence

The incident log retains at minimum the following.

- alert key / severity / status
- detection time, block, tx hash, monitoring source
- branch id / dToken / underlying / contract address
- observed value, threshold, difference
- ACK person, owner, escalation time
- whether public comms occurred, where posted, and the wording
- the on-chain action executed and the tx hash
- the resolved / terminal determination and its basis

The evidence does not include private RPC URLs, API keys, unpublished Safe
nonces, private keys, or personal information.
