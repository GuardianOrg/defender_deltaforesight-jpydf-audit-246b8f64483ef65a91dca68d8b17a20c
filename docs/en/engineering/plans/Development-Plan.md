# jpydf-v2 Development Plan

| Item | Value |
| --- | --- |
| Status | Active |
| Role | Cross-workstream progress tracker for incomplete development, launch, and audit work |
| Source-of-truth boundary | `protocol/product/spec/` owns requirements, `Parameters.md` owns values, `protocol/**/policies/` owns decision policies, gates/runbooks own execution procedures, and `engineering/verification-ledgers/` plus `engineering/historical-reviews/` own verification status/evidence |
| Excluded | histories of completed PRs/commits, resolved decisions, and duplicated specifications or values |

Completed work remains in Git history and [`historical-reviews/`](../historical-reviews/). This plan contains only current work, dependencies, and completion criteria.

## 1. Development Guardrails

1. **Specifications are normative.** Implementation, testing, and audit trace to requirement IDs under `documents/jp`. A code mismatch is an audit finding; do not rewrite an approved specification merely to mirror current code.
2. **Do not duplicate values.** Refer to [Parameters](../../Parameters.md) for final collateral, risk, governance, and oracle values.
3. **Constrain Core deltas.** The JPYdf canonical surface is guarded in CI; accepted deltas are tracked by `CORE-MOD-*` in [Liquity v2 Core Spec](../../protocol/product/spec/Liquity-v2-Core-Spec.md) and parity tests.
4. **Keep change and verification together.** Run affected build, test, fork, E2E, and guards for every change. Do not add unexplained skips or carve-outs.
5. **Verify the production configuration in stages.** Preserve production contracts and role separation through local Anvil, mainnet fork, Sepolia, and mainnet.
6. **Decide launch through evidence.** A Go/No-Go requires the applicable readback, negative drills, and artifacts—not a statement that implementation exists.

## 2. Current Work

| Workstream | Status | Remaining work | Completion source |
| --- | --- | --- | --- |
| Eight-branch implementation sync | In progress | Align `Parameters.md`, Core constants, deploy/manifest, frontend/ops metadata, active/inert wiring, dry-run, and mechanical CI checks for branches 0–7 | [Parameters](../../Parameters.md), [Deployment Configuration](../guides/Deployment-Configuration-Spec.md), [Requirements Ledger](../verification-ledgers/Requirements-Verification-Ledger.md) |
| Phase 4 — Deploy / Wiring | In progress | Freeze mainnet dependencies and holders/Timelock, rehearse Sepolia, and complete final active-branch manifest/readback | [Mainnet Initial Configuration Checklist](../../protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md) |
| Phase 5 — Zapper / user flow | In progress | Review adopted Zapper deployment/binding/User App flow and JPYdf/USDC route | [Zapper](../../protocol/product/spec/Zapper.md), [Frontend Production Gate](../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) |
| LidoStrategy retirement | Blocked | Agree auditor scope reduction, post-removal file list/nSLOC, and review boundary; then remove current implementation and deploy/runtime surfaces | [LidoStrategy](../../archive/LidoStrategy.md), [Audit Scope and nSLOC](../guides/Contract-Audit-Scope-And-nSLOC.md) |
| Phase 7 — Audit readiness | In progress | Complete requirement coverage, invariants, threat model, Core parity, eight-branch delta classification, and external audit package | [Formal Verification / Audit Plan](formal-verification-audit-plan.md), [Requirements Ledger](../verification-ledgers/Requirements-Verification-Ledger.md) |
| Launch operations / peg response | In progress | Complete Vault buffer refill planner, bounded downward-deviation execution, upward-deviation Safe exception, privileged signer, monitoring, stop, and drills | [Mainnet Launch Operation Gate](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md), [Liquidity Management Policy](../../protocol/operations/policies/Liquidity-Management-Policy.md) |
| Liquidation operations | In progress | Freeze mainnet/Sepolia config, key custody, monitoring, ABI alignment, and operations procedure | [Liquidation Bot Plan](Liquidation-Bot-Plan.md), [Mainnet Launch Operation Gate](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md) |
| Foundation readiness | In progress | Member/signer acceptance, RMI and Japanese legal/tax review, OA final values, and closing-package/private-evidence alignment | [Foundation Entity Setup Requirements](../../../jp/foundation/requirements/Foundation-Entity-Setup-Requirements.en.md) |
| Day-2 revenue distribution | Future draft | Implement, test, audit, and approve Treasury/Distributors | [Treasury](../../protocol/roadmap/spec/Treasury.md), [Revenue Allocation Policy](../../protocol/roadmap/policies/Protocol-Revenue-Allocation-Policy.md) |

### 2.1 Phase 4 — Deploy / Wiring

- Freeze feeds, external protocols, fork block, and artifacts through [Mainnet Deploy Env Freeze Runbook](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md).
- Freeze Safe/Timelock/deployer/bot holders, thresholds, and consumer readback through [Mainnet Safe Role Assignment Gate](../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md).
- Enable dUSDC Morpho only through [Morpho Vault Freeze Package](../../protocol/launch/gates/Morpho-Day1-Vault-Freeze-Package.md).
- Take active/inert state, Strategies, and withdraw delay from [Parameters](../../Parameters.md) and [Strategy Selection Policy](../../protocol/operations/policies/Strategy-Selection-Policy.md).
- Gate dwstETH through `PRM-LAUNCH-DWSTETH-*` and the Oracle requirements.
- Keep symbols, immutable parameters, dToken/Vault/PriceFeed, manifest, and frontend/ops metadata for branches 0–7 mechanically aligned.

Phase 4 is complete only when eight-branch sync and deploy dry-run pass; final manifest equals on-chain readback; no temporary holder, unresolved value, or unexplained route remains; and every required checklist gate is closed.

### 2.2 Phase 5 — Zapper / User Flow

- Connect each adopted active-branch Zapper consistently to manifest, generated bindings, and User App flow.
- Review the JPYdf/USDC route under [Liquidity Route Policy](../../protocol/product/policies/Liquidity-Route-Policy.md).
- For any retained direct route, verify display, quote, approval, signing, receipt, and failure recovery through the production gate.

Do not mix unadopted or future routes into Day-1 completion.

### 2.3 Phase 7 — Audit Readiness

Audit readiness requires all of:

- every FR/INV/SEC/GOV/EVT/ERR in current scope maps uniquely to the verification ledger;
- required invariant, fork, integration, and negative tests have actually run;
- actor, role, dependency, upgrade, and emergency-path threat models match current code;
- the diff from `base` matches `CORE-MOD-*` and the Core JPYdf surface guard passes;
- every final eight-branch code delta is classified as external audit, auditor delta review, internal parity review, operational review, or future activation;
- LidoStrategy retirement criteria are met while preserving remaining async-base coverage and historical requirement IDs;
- scope, target commit, known issues, and exclusions are ready to hand to the external auditor.

`TRSY`, `SPARD`, `BRRD`, and `SPDRD` are Day-2; `MCHN` is historical. They are outside current audit coverage.

### 2.4 Cross-Cutting Backlog

- Remove unnecessary BOLD compatibility names from owned frontend surfaces while distinguishing upstream identifiers.
- Align RPC, indexer, hosting, and repository ownership/secrets with production policy.
- Finalize required CI checks and flaky-test handling before audit.
- Complete the verification campaign in [Requirements Ledger](../verification-ledgers/Requirements-Verification-Ledger.md) against the current commit.

## 3. Dependency Order

1. Synchronize eight-branch specification into Core constants, deploy, manifest, and frontend/ops; complete mechanical checks and dry-run.
2. Freeze mainnet dependencies, holders, and Strategy venue evidence.
3. Complete deploy/wiring and verify the same manifest on mainnet fork and Sepolia.
4. Complete User App/ops/admin bindings, Day-1 routes, buffer refill, peg response, privileged signer, and production gates.
5. Complete current-scope coverage, eight-branch delta classification, LidoStrategy retirement audit boundary, and external audit package.
6. Reconcile Foundation closing package and private evidence.
7. Make the final Go/No-Go decision through [Mainnet Initial Configuration Checklist](../../protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md).

Day-2 Treasury/Distributors, Strategies for cap-zero branches, and future routes remain outside this sequence and follow their own activation gates.

## 4. Unresolved Design Decisions

None are managed in this plan. Resolve new decisions in the owning spec, Parameters, design document, or Decision Record; track only the blocker and completion condition here.

## 5. PR Completion Criteria

- Requirement IDs map to implementation and tests.
- Affected build, test, fork, E2E, and CI guards are green.
- `git diff --check` passes with no unintended scope.
- Required security, failure, rollback, and readback evidence exists in its gate or ledger.
- Do not append completed-PR lists or resolved decision history to this active plan.

## References

- [Retrospective](../historical-reviews/Retrospective.md)
- [Product Overview](../../protocol/product/Product-Overview.md)
- [Development document index](../README.md)
