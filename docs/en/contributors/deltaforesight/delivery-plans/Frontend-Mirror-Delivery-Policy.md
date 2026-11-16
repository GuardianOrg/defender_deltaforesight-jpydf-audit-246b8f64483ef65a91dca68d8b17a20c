# Frontend Mirror Delivery Policy

Updated: 2026-06-21

This runbook defines the Day-1 policy and Day-2 adoption gate for
`FRNT-TBD-006` (mirror delivery such as IPFS / ENS). The Japanese version is the
source of truth. This document supports Frontend spec `FRNT-SEC-002`,
`FRNT-SEC-005`, `FRNT-SEC-008`, `FRNT-GOV-001`, `FRNT-GOV-002`,
`FRNT-ERR-001`, `FRNT-ERR-002`, and `FRNT-ERR-006`.

The canonical Day-1 mainnet delivery path is the company-owned official HTTPS
origin defined by
[Frontend-Production-Delivery-Gate.md](Frontend-Production-Delivery-Gate.md).
Mirror delivery is not a replacement for that launch gate. It is only an
optional Day-2 resilience path.

## 1. Decision

Do not adopt mirror delivery on Day-1. Reasons:

- The official domain / hosting / RPC / stats ownership, monitoring, and
  rollback evidence must be frozen first.
- IPFS CIDs are immutable, making mistaken releases, stale bundles, and missed
  incident-banner updates hard to recover.
- ENS / gateway URLs complicate phishing response, domain allowlists, wallet
  connection, and RPC key restrictions.
- Mirrored stats JSON / subgraph / RPC state can make stale data look like live
  current values.
- If admin console, operator-only information, or private endpoints enter a
  public bundle, the blast radius is large.

If adopted on Day-2, the official HTTPS origin remains primary and canonical.
The mirror is a read-only fallback during official-origin outages or a
censorship/outage-resilience aid, not the normal product entrypoint.

## 2. Scope

May be mirrored:

- The `frontend/app` public user app static bundle.
- Public ops / transparency views that contain no operator-only information.
- Public stats JSON, only if `generatedAt`, source block, schema version,
  official-origin metadata, and freshness indicators are retained.
- Public copies of the official link ledger and build manifest.

Out of scope:

- The `frontend/console` admin console.
- Safe calldata drafts, private role snapshots, operator-only runbooks, and
  incident-only dashboards.
- Private RPC URLs, API key fragments, private subgraph endpoints, and
  secret-bearing environments.
- Write-enabled admin/ops surfaces.
- Preview / staging / localhost builds that have not passed the production
  delivery gate.

## 3. Adoption Gate

Before enabling a Day-2 mirror, all gates below must pass.

| Gate | Requirement | Evidence |
| --- | --- | --- |
| Canonical origin | Official HTTPS origin remains primary; mirror is explicitly labeled fallback. | Official URL table, mirror URL table, link ledger |
| Same commit | Mirror bundle is built from the same commit / config / deployment manifest as official production. | Build commit, config hash, deployment manifest hash, bundle hash |
| Public metadata | Mirror UI exposes a way to verify canonical origin, build commit or hash, chainId, and contract manifest hash. | Screenshot, runtime health JSON |
| Static-only boundary | Public bundle contains no admin console, private endpoint, or operator-only route. | Bundle/env redaction check, route map |
| RPC and wallet safety | chainId, RPC provider, domain allowlist, and wallet connection are verified for the mirror origin. If not verified, write UI is read-only. | RPC health, wallet connect drill, domain allowlist evidence |
| Freshness semantics | Stale stats / subgraph data must not look identical to live current values. Do not fill with mock / fixture values. | Stale stats drill, subgraph degraded screenshot |
| Error redaction | Gateway / RPC / subgraph failures do not expose raw provider URLs, DataAPIError details, stacks, or key fragments. | Failure screenshot, redaction check |
| Incident workflow | Define which official channel announces the mirror URL during an official-origin outage and who approves it. | Announcement template, approver list |
| Rollback model | Record CID / ENS contenthash update, old-CID handling, and announcement path when cache / gateway purge is impossible. | Rollback target, new CID, ENS update tx, announcement copy |

## 4. No-Go Conditions

Do not publish a mirror if any item remains true.

- The mirror is the first or only Day-1 launch URL.
- Official production gate evidence for domain / hosting / RPC / stats is
  incomplete.
- Mirror build commit, config hash, deployment manifest hash, or CID is unknown.
- Admin console, private RPC URLs, operator-only routes, or Safe drafts are in
  the public bundle.
- RPC provider domain allowlists do not account for the mirror origin.
- Write UI can start during all-RPC-down, stale stats, or stale subgraph states.
- Stale data looks identical to live current values.
- Gateway / RPC / subgraph failures expose raw URLs, key fragments,
  DataAPIError details, or stacks.
- There is no rollback / announcement procedure for CID or ENS contenthash
  changes.

## 5. Evidence Template

```
Frontend mirror delivery evidence
Date:
Operator:
Canonical user app URL:
Mirror type: IPFS / ENS / other
Mirror URL:
ENS name:
IPFS CID:
Build commit:
Config hash:
Bundle hash:
Chain ID:
Deployment manifest hash:
Generated binding hash:
Official link ledger evidence:
Runtime health evidence:
Canonical origin display evidence:
RPC provider labels:
Allowed mirror domains:
Wallet connection drill:
Stats schema version:
Stats source block:
Stats generatedAt:
Stale stats drill:
Subgraph degraded drill:
RPC all-down drill:
Bundle/env redaction check:
Incident announcement channel:
Approver:
Rollback target:
ENS contenthash update tx:
Go / No-Go:
```

## 6. Operator Workflow

1. Confirm that the canonical production delivery gate is complete.
2. Build the mirror bundle from the exact production commit and config.
3. Record deployment manifest hash, generated binding hash, bundle hash, and CID.
4. Run runtime health on the mirror origin: chainId, RPC, subgraph, stats URL,
   contract manifest, and official link ledger.
5. Run negative drills: all-RPC-down, stale stats, stale subgraph, wrong chainId,
   gateway failure, and missing stats URL.
6. Verify that the public bundle has no admin console URL, private RPC URL,
   operator-only route, Safe draft, key fragment, or private signer information.
7. Verify wallet connection and domain allowlist. Keep write UI disabled if not
   fully verified.
8. Record official announcement copy and rollback/new-CID procedure.
9. Publish the mirror link only through official channels after approval.

## 7. Relationship To Other Gates

- Production domain / hosting / RPC / stats ownership:
  [Frontend-Production-Delivery-Gate.md](Frontend-Production-Delivery-Gate.md).
- i18n / mobile / error redaction:
  [Frontend-UX-Readiness-Gate.md](Frontend-UX-Readiness-Gate.md).
- Admin console:
  [Admin-Console-Production-Gate.md](Admin-Console-Production-Gate.md).
