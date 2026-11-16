# Frontend Production Delivery Gate

Updated: 2026-07-26

This runbook defines the common mainnet production gate for the User App, Dune
Public Analytics, Private Operations Monitor, Admin Control, and the public
stats publisher. The Japanese version is the source of truth. This document
supports Frontend spec `FRNT-TBD-004`, `FRNT-TBD-007`,
`FRNT-SEC-002`, `FRNT-SEC-005`, `FRNT-SEC-007`, `FRNT-SEC-008`, `FRNT-GOV-001`,
`FRNT-ERR-001`, `FRNT-ERR-002`, and `FRNT-EVT-002`.

This gate is authoritative for ownership, delivery, and runtime integrity. Apply
the surface-specific UX, agent-discovery, and restricted-operations gates in
addition. Admin Control / Private Operations Monitor differences are governed
by [Admin-Console-Production-Gate.md](Admin-Console-Production-Gate.md).
Responsibilities, dual-run, cutover, and decommission for public analytics and
private monitoring are governed by
[Public-Analytics-Private-Monitoring-Architecture.md](../operations/Public-Analytics-Private-Monitoring-Architecture.md).
Mirror delivery is governed by
[Frontend-Mirror-Delivery-Policy.md](Frontend-Mirror-Delivery-Policy.md).

Decide each surface independently. At the beginning of the evidence package,
freeze the operation scope, applicable surfaces, and excluded surfaces. Apply
each gate row only to the data path and delivery method used by that surface.
For every excluded item, record `N/A`, its reason, and the source that tracks its
status. An unimplemented surface is not by itself No-Go for an independent
release of another surface. Keep per-surface decisions separate from the overall
operation decision. Dune / Private Operations Monitor cutover and public Ops
decommission are Go only when evidence is complete for every affected surface.

## 1. Scope

In scope:

- User App: public user application.
- Dune Public Analytics: public on-chain statistics and history, not a real-time
  monitor.
- Private Operations Monitor: authenticated view for immediate state, critical
  alerts, ACK, and escalation.
- Admin Control: restricted operations surface for preparing and verifying
  privileged actions.
- DF-managed public stats publisher: current-health JSON for the User App,
  independent of Dune.
- Public Ops UI / build / publish workflow during migration, only until the
  architecture decommission gate completes.
- Shared runtime config: chainId, RPC, subgraph, contract manifest, and official
  links.

Manage private values such as concrete domains, provider keys, and account names
in the evidence package. Hide APR history if no time-series collector is ready.

## 2. Day-1 Minimum Gate

| Gate                       | Day-1 requirement                                                                                                                                                                                                                                                                | Evidence                                                                                     |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Company ownership          | Domain registrar, DNS, hosting/CDN, RPC/subgraph provider, stats storage, and Dune Team are held by company-managed accounts. Do not launch with individual-account dependency.                                                                                                  | Asset owner list, admin group, billing owner, break-glass owner                              |
| Domain registry            | Freeze the User App, Dune, Private Operations Monitor, Admin Control, public stats, and transitional public Ops official URLs and their public / restricted boundaries in one evidence artifact. Do not mix preview / staging / localhost into official links.                    | Official URL table, staging URL table, link ledger check, migration state                    |
| Hosting separation         | Separate the User App and authenticated operations surfaces by project or a clear route / auth boundary. Until decommission, keep wallet / signing runtime, secrets, admin runtime config, and operator-only routing / worker commands out of the public Ops bundle and pass the public-bundle guard. | Hosting project ids, route / role map, public-bundle boundary check                          |
| Delivery integrity         | Apply HTTPS, HSTS, CSP, SRI where needed, and DNSSEC or registrar lock. Ledger any third-party script / executable tag and remove it if unnecessary.                                                                                                                             | Response headers, DNS/registrar evidence, CSP report-only/active state                       |
| Runtime config fail-closed | For a code-delivered surface, production build / runtime health fails closed when a required chainId, deployment manifest hash, RPC URL, subgraph URL, or stats URL used by that surface is missing. Do not reuse this browser runtime config for Dune; apply query-registry and execution evidence instead. Do not leave stray RPC paths such as viem public defaults. | Env schema output, runtime health JSON/screenshot, negative config drill |
| RPC / API keys             | Browser-facing read-only RPC / subgraph credentials may be shared by the User App, transitional public Ops, and Admin Control, but must be treated as public. Record every consuming domain, aggregate rate / capacity, rotation owner, and leak response. Separate worker / archive / write / signing credentials. | Provider label, shared / split, redacted URL, allowed domains, aggregate rate / capacity, rotation owner |
| Contract manifest          | Freeze the chainId, contract address table, generated binding commit, and deployment manifest hash read by the User App, Admin Control / Private Operations Monitor, and transitional public Ops.                                                                                 | Manifest hash, build commit, generated binding hash, contract table                          |
| Subgraph release           | Freeze `mainnet-relaunch` / network `mainnet`, JPYdf / Zapper addresses derived from the current manifest, `startBlock` matching the JPYdf deployment transaction block (or document why an earlier block is used), schema / mapping commit, version, and deployment ID; smoke-query for missing events. | Generated network / subgraph manifest hash, `startBlock` basis, release ID, query evidence |
| Public stats freshness     | Stats JSON includes source block, generatedAt, and schema version. When stale threshold is exceeded, the user app shows stale / unavailable state rather than filling with mock numbers.                                                                                         | Stats JSON sample, stale drill, alert rule                                                   |
| Subgraph degradation       | If the subgraph is stale / unavailable, visually distinguish indexed values from RPC current values. Current values required for writes must come from RPC.                                                                                                                      | Degraded screenshot, RPC fallback evidence                                                   |
| Error surface              | Round RPC / subgraph / stats failures into user-facing copy. Do not display raw stacks, provider URLs, DataAPIError details, or key fragments. Stop write UI when all RPC paths are down.                                                                                        | Failure screenshots, redaction check                                                         |
| Agent discovery            | The user app satisfies [Frontend-Agent-Readiness-Gate.md](Frontend-Agent-Readiness-Gate.md). Do not mix admin / ops surfaces into user app discovery, and do not advertise MCP / Agent Skills / OAuth / commerce endpoints as available when they have no real implementation. | `robots.txt` / `sitemap.xml` / `llms.txt` / `auth.md` / `.well-known` output, scanner result |
| Monitoring                 | Synthetic monitoring covers User App render, RPC reads, subgraph / stats freshness, official links, and critical routes. Monitor Dune query freshness and Private Operations Monitor worker ingestion / alert delivery separately.                                                | Monitor URL/list, Dune query freshness, alert owner, delivery test                           |
| Release / rollback         | For each target surface, record the build or query-registry revision, config hash, release time, rollback / replacement target, and cache-purge procedure where applicable.                                                                                                     | Release evidence, rollback rehearsal or documented target                                    |
| Surface-specific gates     | Apply the [UX Gate](Frontend-UX-Readiness-Gate.md) to the User App and transitional public Ops, the [Agent Gate](Frontend-Agent-Readiness-Gate.md) to the User App, the [Admin Gate](Admin-Console-Production-Gate.md) to Admin Control / Private Operations Monitor, and the [monitoring architecture](../operations/Public-Analytics-Private-Monitoring-Architecture.md) gate to the analytics / monitoring migration. | IDs and results for every applicable differential gate |

## 3. No-Go Conditions

Do not publish mainnet production if any of the following remain true.

- Dune is used as a critical alert, availability monitor, or User App runtime
  API.
- Dune is judged published or ready for cutover without evidence for the
  query-registry revision / hash, repository SQL / parameter-set hash, Dune
  query revision / exported SQL hash, repository-to-published content match,
  public query / dashboard IDs, Dune compile and successful execution,
  same-period or same-block RPC / event reconciliation, freshness, and measured
  credits.
- Private Operations Monitor is unauthenticated, or a monitor viewer can reach
  privileged operations.
- The public Ops URL is removed from official navigation without dual-run
  evidence, or the public-bundle guard is removed before decommission completes.
- The public stats publisher depends on Dune or public Ops availability.
- Official domain / hosting / RPC / stats depend on individual accounts.
- The production app can reach `api.liquity.org`, upstream governance endpoints,
  viem public default RPCs, or other non-JPYdf-owned endpoints.
- The user app starts with missing production env and fills numbers with mock /
  fixture / stale snapshots.
- `pnpm -C frontend/ops check:public-bundle` fails, or a public bundle includes
  wallet / signing runtime, admin runtime config / URLs, a private RPC URL,
  operator-only routing / worker commands, a key fragment, Safe nonce, or private
  signer information.
- The subgraph network, address, schema / mapping commit, or version differs
  from the current release; `startBlock` is later than the JPYdf deployment
  transaction and misses events; or an earlier `startBlock` lacks a documented
  reason.
- Stats JSON lacks `generatedAt`, source block, or schema version.
- Stale stats or stale subgraph values look identical to live current values.
- Borrow / deposit / redeem / claim write flows can start when all RPC paths are
  down.
- The public user app production env sets `NEXT_PUBLIC_SHOW_DATA_SOURCES=true`,
  `NEXT_PUBLIC_ALLOW_DATA_SOURCE_OVERRIDES=true`, or `NEXT_PUBLIC_DEV_WALLET=true`,
  allowing users to use custom RPC / subgraph endpoints or the local dev-wallet
  path.
- An inert branch (Day-1: branches 2–7) is enabled in the
  borrow dropdown, the `/borrow/*` route, or as a write-request generation target.
- `NEXT_PUBLIC_REFERRAL_REGISTRY_URL` is set while the paid Referral campaign
  activation packet (#668 or its successor) is not approved and there is no
  `NEXT_PUBLIC_REFERRAL_CAMPAIGN_ACTIVATION_APPROVED=true` evidence. Standard
  Day-1 leaves the referral registry URL unset, so captured URL slugs fall back
  to no-referral transactions.
- Raw provider errors, stack traces, DataAPIError details, or private URLs are
  user-visible.
- Rollback target or cache purge procedure is not recorded.

## 4. Production Evidence Template

```
Frontend production delivery evidence
Date:
Operator:
Operation scope:
Applicable surfaces:
Excluded surfaces / N/A reasons / tracking source:
User app URL:
Dune dashboard URL:
Dune Team / owner:
Dune query registry revision / hash:
Dune repository SQL / parameter-set hash:
Dune query revision / exported SQL hash:
Dune repository / published content match result:
Dune public query / dashboard IDs:
Dune compile / successful execution evidence:
Dune RPC / event reconciliation evidence:
Dune measured credits / freshness evidence:
Private Operations Monitor URL:
Admin Control URL:
Public Ops transition state / URL:
Public stats URL:
Build commit:
User app config hash:
Public Ops config hash:
Admin / Private Monitor config hash:
Public stats publisher config hash:
Chain ID:
Deployment manifest hash:
Generated binding hash:
Hosting project ids:
DNS / registrar owner:
CDN / cache owner:
RPC provider labels:
RPC URL redaction:
Browser RPC credential policy (shared/split):
Allowed frontend domains:
Aggregate RPC rate / capacity:
RPC rotation / revocation owner:
Data-source override flags:
Dev wallet flag:
Subgraph endpoint label:
Subgraph network:
Subgraph version / deployment ID:
Subgraph schema / mapping commit:
Subgraph generated manifest hash:
Subgraph startBlock:
Subgraph startBlock evidence:
Subgraph smoke query:
Stats schema version:
Stats source block:
Stats generatedAt:
UX readiness evidence:
Agent readiness evidence:
Admin gate evidence / result:
Analytics / private monitoring architecture evidence / result:
Dual-run / cutover / decommission state:
CSP / HSTS / DNS evidence:
Official link ledger evidence:
Runtime health evidence:
Release evidence bucket:
Release evidence prefix:
Release evidence KMS key:
Negative config drill:
Stale stats drill:
Subgraph degraded drill:
RPC all-down drill:
Monitoring links:
Rollback target:
Per-surface Go / No-Go:
Overall operation Go / No-Go:
```

## 5. Operator Workflow

1. Freeze domain, hosting, endpoint, Dune, restricted-surface, and public Ops
   migration inventory.
2. Build code-delivered target surfaces from the pinned commit. When Dune is in
   scope, pin the query-registry revision, repository SQL / parameter-set hash,
   Dune query revision / exported SQL hash, and verify content equality.
3. Verify env schema and runtime health with positive config.
4. Generate the subgraph manifest with
   `./subgraph/deploy-subgraph mainnet-relaunch --deployment-manifest
   <current-manifest> --start-block <JPYDF_DEPLOY_BLOCK> --version <VERSION>`.
   Review network, addresses, and `startBlock`, then deploy and retain smoke-query
   evidence.
5. Run negative config drill: missing RPC, wrong chainId, missing stats URL, stale
   stats, stale subgraph, and all-RPC-down.
6. While the public Ops build / publish workflow remains, run
   `pnpm -C frontend/ops check:public-bundle`, then verify official links and
   the absence of upstream endpoints, mock snapshots, and private metadata.
7. Verify agent-discovery files and run the UX / Agent / Admin differential
   gates plus the monitoring architecture dual-run / cutover / decommission
   gate.
8. Publish code-delivered surfaces to staging and record headers, CSP, HSTS,
   DNS / registrar evidence. Verify Dune query freshness and public scope.
9. Run `pnpm -C infra/cdk check:cdk-bootstrap` and
   `pnpm -C infra/cdk check:github-production`, then promote to production
   through `.github/workflows/cdk-production-promotion.yml` with GitHub
   `production-infra` Environment subject / branch policy and explicit
   `confirm_deploy=deploy-production`. The workflow runs synthesized template
   policy lint before diff / deploy, checks AWS live postdeploy state after
   deploy, checks the promotion diff / outputs / stack-list artifacts before
   upload, records CloudFront invalidation evidence, generates a checked
   `release-evidence.generated.json` draft, and replay-checks the artifact set
   with `pnpm -C infra/cdk check:promotion-artifact`.
   Purge cache and record
   build/config/manifest hashes in the CDK `ReleaseEvidenceBucketName` bucket
   using the `ReleaseEvidenceKmsKeyArn` CMK. Use
   `infra/cdk/templates/production-promotion-first-run-evidence.md` for the
   first production promotion evidence package. Start CDK promotion release
   evidence from the generated `release-evidence.generated.json` artifact; use
   `infra/cdk/templates/release-evidence.example.json` for non-promotion
   releases. For AWS hosting / static asset delivery, keep
   `operationScope=production-infra` and `releaseEvidencePrefix` under
   `release-evidence/production-infra/...`; do not reuse this evidence as
   Ethereum mainnet protocol deploy / governance evidence. Run
   `pnpm -C infra/cdk check:release-evidence <file>` before upload, then use
   `.github/workflows/release-evidence-upload.yml` with
   `ReleaseEvidenceGithubUploadRoleArn` so the object is written with
   `--sse aws:kms --sse-kms-key-id <ReleaseEvidenceKmsKeyArn>`.
   Publish user app / ops static assets only through
   `.github/workflows/static-assets-production-publish.yml`; it uses the
   separate static asset publish role, reads StaticSites outputs, syncs with
   stack bucket CMKs, waits for CloudFront invalidation completion, generates a
   checked `release-evidence.generated.json` draft plus
   `static-asset-manifest.generated.json`, replay-checks the artifact set with
   `pnpm -C infra/cdk check:static-assets-artifact`, and records the draft /
   manifest / invalidation evidence in the workflow artifact. Keep the generated
   draft at `goNoGo=no-go` until operator review, then upload the final JSON
   through `.github/workflows/release-evidence-upload.yml`.
10. Confirm synthetic monitors, Dune query freshness, monitoring workers, alert
    owners, and delivery.
11. Record per-surface Go / No-Go, migration state, and rollback target.

## 5.1 Machine Checks

Before production promotion, run at least the following and keep them in evidence.

```bash
pnpm -C frontend/app check:hosting-env
pnpm -C frontend/app check:data-sources
pnpm -C frontend/app build
pnpm -C frontend/ops check:hosting-env
pnpm -C frontend/ops build
```

The two `frontend/ops` commands are required only while the public Ops build /
publish workflow exists. After decommission, record removal of that workflow and
its public delivery assets, the official-link cutover, and removal of the
public-bundle guard in the same architecture evidence.

`frontend/app check:hosting-env` reads the production env and verifies
`NEXT_PUBLIC_SITE_URL` (HTTPS origin only), `NEXT_PUBLIC_CHAIN_ID=1`,
`NEXT_PUBLIC_CHAIN_RPC_URL`, `NEXT_PUBLIC_SUBGRAPH_URL`,
`NEXT_PUBLIC_PROTOCOL_STATS_URL`, and `NEXT_PUBLIC_DEPLOYMENT_FLAVOR`, plus
`NEXT_PUBLIC_SHOW_DATA_SOURCES=false`,
`NEXT_PUBLIC_ALLOW_DATA_SOURCE_OVERRIDES=false` (or unset), and
`NEXT_PUBLIC_DEV_WALLET=false`. The user app runtime also ignores any RPC /
subgraph override left in localStorage when `NEXT_PUBLIC_SHOW_DATA_SOURCES=false`,
so production uses only the official config. A state where `site-url-required`
appears under an empty local / CI env, or where `mainnet-chain-required` appears
under a staging Anvil env (e.g. chainId `31338`), is a normal negative drill and
is not treated as production Go evidence. If `NEXT_PUBLIC_REFERRAL_REGISTRY_URL`
is set, `NEXT_PUBLIC_REFERRAL_CAMPAIGN_ACTIVATION_APPROVED=true` is also required
as evidence that the paid Referral campaign activation packet has been approved.
Standard Day-1 leaves the registry URL unset and does not make a paid campaign
user-facing. `frontend/ops check:hosting-env`
verifies that the generated binding's chainId is Ethereum mainnet `1` and that
the rpcUrl is an HTTPS absolute URL that is not localhost / loopback, and is kept
as evidence together with the generated binding hash. A state where this check
fails for a staging Anvil binding (e.g. chainId `31338`) is also normal and is
not treated as production Go evidence.

The admin console is a separate gate, so keep
`pnpm -C frontend/console check:hosting-env` / `pnpm -C frontend/console build`
from [Admin-Console-Production-Gate.md](Admin-Console-Production-Gate.md) as
separate evidence.

## 6. Day-2 Enhancements

These may be added on Day-2, but they do not replace the Day-1 gate.

- Mirror delivery such as IPFS / ENS, only after satisfying
  [Frontend-Mirror-Delivery-Policy.md](Frontend-Mirror-Delivery-Policy.md).
- APR / historical time-series collector.
- CSP report ingestion and automatic regression tickets.
- Public status page.
- Multi-region frontend failover.
