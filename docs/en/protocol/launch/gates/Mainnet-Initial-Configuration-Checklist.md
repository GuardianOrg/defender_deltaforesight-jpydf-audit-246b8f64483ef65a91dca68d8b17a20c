# Mainnet Initial Configuration Checklist

> Support translation. The [Japanese source document](../../../../jp/protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md)
> is authoritative if this file conflicts with it.

| Item | Value |
| --- | --- |
| Status | Active |
| Domain | Protocol |
| Lifecycle | Launch |
| Artifact Type | Gate |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight (Contributor) |
| Visibility | Public |
| Normative Source | [Japanese Mainnet Initial Configuration Checklist](../../../../jp/protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md) |
| Role | Stage-specific Go/No-Go based on completion of child gates for Deploy Broadcast and Public Activation |
| Canonical relationship | Child documents own values, procedures, gate-specific No-Go rules, and evidence schemas. The Japanese source document owns the parent Status, Evidence references, sign-offs, and final result; this file is a read-only support translation |
| Scope | Ethereum mainnet fresh deploy, handover, and Day-1 public activation |

Do not record secrets, unpublished Safe nonces, raw RPC URLs, or personal signer data. Evidence retains only provider labels and redacted URLs.

## 1. How to use

1. Complete every §2 `Deploy` row before the first mainnet broadcast. Complete every `Activation` row after real deployment and handover but before public activation.
2. Do not re-adjudicate a child gate's No-Go here. One unresolved item makes the parent No-Go.
3. Under §3 and §4, confirm that evidence for a stage refers to the same candidate, manifest, and state, and that Activation evidence connects the approved broadcast to the real deployment.
4. Advance only when §5 has no applicable No-Go and every required approval in §6 is Go.

Completion does not approve a Day-2 bridge minter, inert-branch activation, active PIL routing, or an additional liquidity route.

## 2. Gate completion matrix

`Status` is `Pending`, `Go`, `No-Go`, or `N/A`. `N/A` is permitted only for a row explicitly marked conditional and must identify the inapplicable surface and reason. Every Evidence cell contains one re-verifiable file, hash, ticket, or equivalent identifier.

Record the one-time Day-1 parent decision only in sections 2 and 6 of the Japanese source document. Do not write statuses, Evidence references, sign-offs, or final results into this support translation.

| Status | Stage | Area | Canonical source / gate | Parent completion condition | Evidence |
| --- | --- | --- | --- | --- | --- |
| Pending | Deploy | adopted values and branch map | [Parameters](../../../Parameters.md), [Launch Product Decision Record](../decisions/Mainnet-Launch-Product-Decision-Record.md) | immutable/mutable parameters and Day-1 launch values approved | |
| Pending | Deploy | deploy mode and manifest schema | [Deployment Configuration](../../../engineering/guides/Deployment-Configuration-Spec.md) | fresh `complete` deploy shape and generated manifest finalized | |
| Pending | Deploy | external addresses, env, toolchain | [Deploy Env Freeze](Mainnet-Deploy-Env-Freeze-Runbook.md) | addresses, env, salts, artifacts, scripts, and toolchain frozen; preflight complete | |
| Pending | Deploy | Strategy adoption | [Strategy Selection Policy](../../operations/policies/Strategy-Selection-Policy.md) | branch × venue, none branches, cap/weight, and activation boundaries approved | |
| Pending | Deploy | fork stress | [Mainnet Fork Stress Gate](Mainnet-Fork-Stress-Gate.md) | mandatory scenarios Go on the same candidate and frozen env | |
| Pending | Deploy | Safe, roles, Timelock | [Safe Role Assignment Gate](Mainnet-Safe-Role-Assignment-Gate.md), [Timelock Deploy Runbook](../../../../jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md) | holders, thresholds, roles, delay, admin renounce, and consumer addresses match | |
| Pending | Activation | governance handover | [Governance Handover Runbook](Mainnet-Governance-Handover-Runbook.md) | prepare, accept, and final verification complete; no deployer privilege or pending owner | |
| Pending | Activation | Proxy / UUPS | [Deployment Configuration](../../../engineering/guides/Deployment-Configuration-Spec.md) | §4.1 proxy evidence complete for every target | |
| Pending | Activation | launch operation | [Mainnet Launch Operation Gate](Mainnet-Launch-Operation-Gate.md) | SP, bootstrap, LP, redemption, liquidation, monitoring, and T+24h plan Go | |
| Pending | Activation | system and residual risk | [Mainnet Launch Risk Gate](Mainnet-Launch-Risk-Gate.md), [Requirements Verification Ledger](../../../engineering/verification-ledgers/Requirements-Verification-Ledger.md) §4.5, [Incident Notification Policy](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md), [Active Branch Cap Ramp](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md) | launch evidence for `SYS-RISK-001..010`, including 008/009 cap display, executable capacity, additional borrowing/sale and APR decisions, cap-ramp handoff, explicit Product-owner and Protocol-Risk-owner approval of 010's stale-high / fail-closed tradeoff, and residual-risk approval | |
| Pending | Activation | participant readiness | [Participant Readiness Gate](Mainnet-Participant-Readiness-Gate.md) | borrower, SP depositor, and liquidator surfaces/operations Go | |
| Pending | Activation | frontend production | [Frontend Production Delivery Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) | production data, security, rollback, and monitoring Go | |
| Pending | Activation | surface-specific frontend (conditional) | [Frontend UX Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md), [Agent Gate](../../../contributors/deltaforesight/delivery-plans/Frontend-Agent-Readiness-Gate.md), [Admin Console Gate](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) | every enabled surface gate Go; disabled surfaces identify name and reason | |
| Pending | Activation | treasury and accounting | [Treasury Safe Retention Reconciliation](../../../../jp/protocol/operations/runbooks/Treasury-Safe-Retention-Reconciliation-Runbook.md) | Day-1 Safe-retention/read-only ledger mode, accounting owner, scan start, alert readiness or periodic fallback cadence, and disabled distribution frozen | |
| Pending | Deploy | audit scope and blockers | [Contract Audit Scope and nSLOC](../../../engineering/guides/Contract-Audit-Scope-And-nSLOC.md) | candidate diff matches audit scope; no unresolved launch blocker | |
| Pending | Activation | dormant surfaces | [Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md), the PIL activation package | no bridge minter/pending proposal/active adapter and no active PIL routing/campaign | |

## 3. Common completion record

Every child-gate evidence package contains at least:

| Field | Requirement |
| --- | --- |
| `candidateCommit` | complete reviewed Git SHA |
| `stage` | `Deploy` or `Activation` |
| `chainId` | `1` for mainnet |
| `forkBlock` | required for Deploy; fixed block for stateful dry-run comparison |
| `deployTxHash` / `deployBlock` | required for Activation; real deploy matching the approved broadcast |
| `manifestSha256` | hash of current `deployment-manifest.json` |
| `artifactHash` | hash or reference for deployed artifacts |
| `applicableScope` | active/borrowable branches and enabled frontend surfaces |
| `gateStatus` | `Go`, `No-Go`, or `N/A` |
| `evidenceRef` | package, log, snapshot, or ticket |
| `reviewers` / `reviewedAt` | reviewer classes and UTC time |

Within a stage, mismatched candidate commit, state block, or manifest requires reconciliation and re-running affected gates. Activation must preserve the approved candidate and artifact and connect its deploy transaction, block, and current manifest to the same real deployment.

## 4. Parent-specific reconciliation

### 4.1 Proxy / UUPS

For every dToken, CollateralVault, and non-zero Strategy:

- proxy, ERC1967 implementation, implementation codehash, and slot match the candidate artifact;
- no Transparent-Proxy admin state contradicts UUPS;
- direct initialization of the implementation is rejected;
- final owner/upgrader/role holders match handover evidence and `pendingOwner == address(0)`; and
- no unapproved Strategy proxy exists for inert or `none` branches.

### 4.2 Cross-gate checks

- Handover, frontend, ops, and bots reference the same current manifest and real deployment.
- Branch counts and active/cap-0/inert states match Parameters and the Product Decision Record.
- Activation candidate and artifacts are unchanged from the approved Deploy result.
- Enabled surfaces match `applicableScope` and each conditional Go/N/A result.
- Token-unit env values equal on-chain readback.
- Holder addresses and launch-operation owners match the Safe/role package.
- Every exception has an owner, reason, expiry, and closure condition.

## 5. Stage-specific No-Go

Both stages are No-Go if any child No-Go remains, evidence is not retrievable, or shared evidence cannot remove secrets, raw RPC URLs, or unpublished signer data.

### 5.1 Deploy Broadcast

Do not broadcast when a required Deploy row is Pending, No-Go, or N/A; when candidate/fork block/manifest/artifact do not reconcile; or when any Deploy approval in §6 is not Go.

### 5.2 Public Activation

Do not activate when the final Deploy result is not Go or its candidate/artifact differs from the real deploy; a required Activation row is Pending, No-Go, or N/A; a conditional N/A lacks its surface and reason; on-chain readback disagrees with env/manifest/holders/consumers; deployer privileges, unexpected pending owners, unapproved proxies/Strategies, active bridge, or active PIL route remain; or any Activation approval in §6 is not Go.

## 6. Final sign-off

| Role | Deploy Broadcast | Public Activation | Evidence / comment |
| --- | --- | --- | --- |
| Product | Pending | Pending | |
| Risk | Pending | Pending | |
| Finance | Pending | Pending | |
| Security / Audit | Pending | Pending | |
| Engineering | Pending | Pending | |
| Operations | Pending | Pending | |
| Launch owner | Pending | Pending | |

| Stage | Final result | Candidate commit | Manifest sha256 | Reference block | Approved at |
| --- | --- | --- | --- | --- | --- |
| Deploy Broadcast | Pending | | | `forkBlock`: | |
| Public Activation | Pending | | | `deployBlock`: | |
