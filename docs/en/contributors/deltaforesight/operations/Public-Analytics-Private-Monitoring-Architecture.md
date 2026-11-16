# Public Analytics / Private Monitoring Responsibility Split

## 0. Position

| Item | Value |
| --- | --- |
| Status | Adopted |
| Decision date | 2026-07-25 |
| Scope | Public analytics, real-time monitoring, administrator operations, and user-facing incident communications |
| Requirements source | [Frontend](../../../protocol/product/spec/Frontend.md) `FRNT-FR-031..036` |
| Alert-policy source | [Incident Notification Policy](Incident-Notification-Policy.md) |

This document is the source of truth for replacing the public Ops dashboard with Dune public analytics and moving real-time monitoring into authenticated Admin surfaces and a headless worker. The linked requirements and policy remain authoritative for individual metrics, alert thresholds, and public-announcement conditions.

## 1. Decision

JPYdf separates its off-chain surfaces into four responsibilities:

| Surface | Primary purpose | Freshness | Reachability |
| --- | --- | --- | --- |
| Dune Public Analytics | Public on-chain statistics, history, and Treasury flows | Daily initially; adjust from measured credit usage | Public |
| Private Operations Monitor | Real-time Oracle/RPC/branch/Vault/Strategy monitoring, alert state, ACK, and escalation | Seconds to minutes | Authenticated |
| Admin Control | Safe/Timelock operation preparation, simulation, pending actions, evidence, and configuration checks | Immediately before an operation | Authenticated |
| User App / Status Page | Minimum necessary communication for user-impacting incidents | Per incident policy | Public |

The Private Operations Monitor UI is an independent monitoring view inside `frontend/console`. Alert collection, evaluation, delivery, and persistence run in a worker even when no browser is open. Admin Control may link from an alert to the relevant operation, but an alert never automatically becomes an on-chain action.

After migration, the public Ops static site is decommissioned. Dune is a public analytics surface, not a protocol availability monitor, critical-alert source, or User App runtime API.

## 2. Responsibility Boundaries

### 2.1 Dune Public Analytics

Dune contains statistics and history reproducible from public on-chain data that do not need second-level freshness or an incident SLA: supply, debt, TVL, borrow rates, Stability Pool, liquidation/redemption, dToken mint/redeem, Vault/Strategy flows, protocol revenue, and Treasury flows.

Each metric is governed by a query-registry entry containing:

- query ID, display name, SQL source, and owner;
- decoded events, token transfers, curated prices, and other inputs;
- the state reconstructible from events and its RPC-snapshot reconciliation method;
- measured credits per execution, schedule, and monthly estimate; and
- expected freshness, missing-data behavior, and retirement/replacement destination.

Do not assume Dune can continuously `eth_call` arbitrary view functions. Current state that events cannot reconstruct accurately belongs to the Private Operations Monitor or a DF-managed public-statistics JSON publisher.

### 2.2 Private Operations Monitor

The monitor shows current state across all branches, monitoring degradation, alert status (`active / acknowledged / escalated / resolved`), owner aliases, channels, and ACK deadlines. It is read-only and links an alert requiring remediation to an explicit Admin Control action.

The monitoring worker must:

1. keep polling, ingesting events, and delivering alerts while the Admin browser is closed;
2. distinguish RPC endpoint failures from protocol-state anomalies;
3. never interpret collection failure as “no anomaly”;
4. persist delivery deduplication, ACK deadlines, escalation, and resolution; and
5. exclude private RPC URLs, credentials, and personal data from payloads, receipts, and UI.

`frontend/ops notify-alerts` atomically writes a schema-v2 private-monitor status artifact from the same-cycle snapshot and delivery state when `OPS_PRIVATE_MONITOR_OUTPUT` or `--monitor-output` is configured. The artifact contains active alerts, at most 50 resolved alerts, and current state for every branch. It excludes external-incident actor/reason/private URLs and redacts hosts and credential-shaped key/value data.

On snapshot failure, existing active alerts are retained until a successful cycle can reevaluate them; their last-observed time and block remain the last actual observation. Snapshot and event-history health are recorded separately. When event history is disabled or unavailable, current snapshot state may still be shown, but zero active alerts must not be presented as healthy.

The Admin monitor view reads same-origin `/private-monitor/status.json` every 15 seconds. It fails closed when generated time or source block is 120 seconds stale, time is more than 30 seconds in the future, or artifact chain ID differs from the console deployment chain ID. A recent fetch failure must not turn a cached zero-alert artifact into a healthy state. Alert-to-action links stay disabled unless provenance is valid. The route remains behind the Admin server-side authentication boundary; private endpoints and credentials never enter the browser bundle.

### 2.3 Admin Control

Admin Overview supports pre-operation checks for one selected branch; it does not duplicate the all-branch monitoring list. The monitor answers “what is abnormal,” while Admin Control answers “which authority and path prepares the response.” Shared state uses one retrieval and evaluation implementation rather than separate formulas.

Monitor viewers and privileged operators/signers can have separate authentication roles. Frontend authentication is defense in depth; on-chain roles and Safe/Timelock remain the authorization boundary.

### 2.4 Public Incident Communication

Dune updates and Dune alerts are not incident-notification channels. When a P0/P1 or another user-impacting incident occurs, an approved public payload from the monitoring worker updates the User App banner and Status Page. Internal owners, channels, ACK state, unapproved actions, and private endpoints remain private.

## 3. Dune Free-Plan Budget

Dune content is owned by the DeltaForesight Team, not an individual account, and the extra-credit limit is fixed at `$0`.

| Use | Monthly cap |
| --- | ---: |
| Scheduled execution | 2,000 credits |
| Development and manual-verification reserve | 500 credits |

Monthly estimates use `Σ(query credits/run × monthly runs)`. The initial schedule is daily, with all queries capped at 64 credits per cycle (`64 × 31 = 1,984`). A twelve-hour schedule requires a 32-credit cycle cap (`32 × 62 = 1,984`). Community refreshes are not an operations SLA.

If usage exceeds the budget, reduce SQL scan scope, share base queries, make processing incremental, then lower refresh frequency. Do not move critical monitoring to Dune schedules or alerts to fit the budget.

The plan, credit, and scheduling assumptions were checked against Dune documentation on 2026-07-25 and must be rechecked at Dune MVP acceptance and before schedule changes. Scheduled-query failure notifications do not replace worker health or critical delivery.

External references:

- [How Credits Work](https://docs.dune.com/resources/credits-billing/how-credits-work)
- [Teams and Roles](https://docs.dune.com/web-app/teams)
- [Schedule Queries and Dashboards](https://docs.dune.com/web-app/query-editor/query-scheduler)
- [Set Up Alerts](https://docs.dune.com/web-app/alerts)
- [Data Freshness](https://docs.dune.com/data-catalog/data-freshness)
- [Contract Submission Guide](https://docs.dune.com/web-app/decoding/short-guide-contract-submission)

## 4. Migration Order and Gates

The public Ops surface is reduced in this order and is not removed before prior gates close:

1. Align the Frontend spec, incident policy, and data-source ledger with this decision.
2. Move alert, health, ledger, and keeper logic out of the public React bundle into a headless package/worker/operations CLI.
3. Add the monitoring view and monitor-viewer authorization boundary to the Admin console.
4. Prepare Dune contract decoding, query registry, primary queries, credit gate, and public dashboard.
5. Dual-run current Ops, Private Monitor, and Dune; reconcile primary metrics and alerts at the same block or aggregation period.
6. Change the official public analytics link to Dune and remove the public Ops URL from guidance.
7. Remove the public Ops React build, S3/CloudFront resources, and publishing workflow.

Decommissioning requires:

- registered Dune public metrics with verified freshness and credit budget;
- browser-independent Oracle/RPC/branch/Vault/Strategy alert and resolution;
- a monitor viewer that cannot execute privileged actions and an operator path from alert to action preview;
- User App/Status Page communications independent of Dune;
- a public-statistics publisher independent of the Ops UI if `NEXT_PUBLIC_PROTOCOL_STATS_URL` remains;
- removal of `pnpm -C frontend/ops check:public-bundle` only with the public build/publish workflow; and
- an inventory and passing build/publish verification for every Ops AWS and CI consumer before resource removal.

## 5. Code Ownership Boundaries

| Logical component | Includes | Excludes |
| --- | --- | --- |
| Monitoring core / worker | Snapshots, event ingestion, alert derivation/routing/delivery, health checks, public-comms state | React, wallets, Safe signing |
| Operations CLI | Explicit Treasury/referral-ledger/interest-routing/buffer-refill commands | Public browser bundle |
| Admin monitor UI | Private-monitor state/API display, filters, ACK/escalation state, Admin action links | Polling scheduler, secrets, private endpoints |
| Dune analytics | SQL, query registry, dashboard metadata, credit-budget checks | Critical alerts, private operations metadata |
| Public stats publisher | Current-health JSON required by the User App | Dune dashboard implementation |

Migration does not mean deleting `frontend/ops` as a directory. Move every consumer to its destination first, then remove only the public UI and its delivery assets.
