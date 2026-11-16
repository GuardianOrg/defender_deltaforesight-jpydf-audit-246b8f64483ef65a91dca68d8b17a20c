# Mainnet Fork Stress Scenario Package

> **Positioning**: template for the evidence package produced when running
> [`Mainnet-Fork-Stress-Gate.md`](Mainnet-Fork-Stress-Gate.md). It fixes the
> scenario matrix, artifact layout, business summary, and secret-hygiene checks
> used to satisfy Issue #405.
>
> The Japanese version is the source of truth. Actual `FORK_BLOCK`, CodeBuild
> build ids, manifest hashes, launch config hashes, and owner sign-off are filled
> in the launch-freeze evidence package. Do not commit private keys, raw
> `MAINNET_RPC_URL`, AWS secrets, or unpublished Safe nonces.

## 1. Package Layout

Store raw scenario artifacts separately from review summaries.

```text
mainnet-fork-stress-evidence/
  package-summary.md
  scenario-matrix.csv
  scenario-matrix.json
  codebuild-runs.csv
  no-go-summary.md
  secret-hygiene.md
  frontend-admin-payload-matching.md
  launch-operation/
    launch-operation-evidence.json
    launch-operation-evidence.md
  scenarios/
    <scenario_id>/
      evidence-summary.txt
      deployment-manifest.sha256
      launch-operation-config.sha256
      import-summary.json
      import-summary.md
      codebuild-build.json
      logs/
```

`scenario-matrix.*` is the first review surface for business / risk sign-off.
Raw logs may remain internal, but summaries must not include secrets, raw
calldata, private endpoints, or unpublished Safe nonces.

## 2. Scaffold Command

Generate starter package files from the contracts package. This is not execution
evidence. It only creates the scaffold that launch freeze fills with actual
`FORK_BLOCK`, CodeBuild build ids, manifest hashes, launch config hashes, and
owner sign-off.

```bash
cd contracts
pnpm mainnet-fork-stress-package:init \
  --out /path/to/evidence-dir/mainnet-fork-stress-evidence
```

Use `--force` only when intentionally updating an existing package. Do not add
private keys, raw `MAINNET_RPC_URL`, AWS secrets, raw privileged calldata, or
unpublished Safe nonces to generated public summaries.

For a freshly generated draft package, allow placeholders and check only the
package structure.

```bash
cd contracts
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence \
  --allow-placeholders
```

Import completed scenario artifacts with the import command instead of pasting
raw logs into public summaries. The command copies only hash / build id /
artifact label metadata into the scenario matrix and CodeBuild run list.

```bash
cd contracts
pnpm mainnet-fork-stress-package:import-run \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence \
  --run /path/to/codebuild-or-local-run-artifact \
  --scenario baseline-freeze-full \
  --actual-result pass \
  --full-deploy-eligible true \
  --risk-owner-signoff risk-YYYYMMDD \
  --codebuild-status SUCCEEDED \
  --operator ops-YYYYMMDD
```

`--run` reads `evidence-summary.txt`, `deployment-manifest.sha256`, and optional
`launch-operation-config.sha256` / `launch-operation/launch-operation-evidence.json`
from `mainnet-fork-evidence` or CodeBuild output. `--actual-result=warn|fail`
requires `--exception-owner` and `--exception-reason`. Non-smoke scenarios with
`full_deploy_eligible=false` must record `--exclusion-reason` so reviewers know
why the run does not count as full deployment PASS evidence.
`--risk-owner-signoff` can be filled after import, but strict pre-sign-off
validation requires it for every executed scenario. `--artifact-path` must be an
S3 prefix or a `codebuild://...` / `internal://...` label, not a raw HTTP(S) URL.

Before launch sign-off, run strict check without placeholders. Strict check
verifies `actual_result`, `fork_block`, manifest / launch config hashes,
`Remaining No-Go: no`, CodeBuild run list, secret-hygiene yes/no values, and raw
URL / long calldata / private-key-like values in public summaries. It exits
non-zero while No-Go items remain. For executed scenarios,
`import-summary.json` is also required as provenance. The check fails when
`scenario-matrix.json`, `scenario-matrix.csv`, CodeBuild rows, or import
summary hashes / build ids / artifact labels disagree, and when
`actual_result=pass` is paired with CodeBuild status `FAILED`. It also fails
when an executed scenario has empty `risk_owner_signoff`, or when a non-smoke
scenario has `full_deploy_eligible=false` with empty `exclusion_reason`. It also
fails when a required scenario's `family`, `phase`, `expected_result`, or required
flags drift from the tooling's canonical scenario catalog, or when
`scenario-matrix.*` / `codebuild-runs.csv` field schema drifts from the
canonical schema.

```bash
cd contracts
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence
```

Before PRs, verify that the repository required-scenario docs still match the
tooling catalog.

```bash
cd contracts
pnpm mainnet-fork-stress-package:check-docs
```

## 3. Scenario Matrix Schema

| Field                  | Required       | Meaning                                                                                                                                |
| ---------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `scenario_id`          | yes            | path-safe id, for example `baseline-freeze-full`                                                                                       |
| `family`               | yes            | `baseline`, `launch-operation`, `branch-config`, `vault`, `stablecoin`, `oracle`, `dex`, `aave`, `liquidation`, `frontend-admin`, etc. |
| `phase`                | yes            | `phase0-local-smoke`, `phase1-dispatch-smoke`, `phase2-pinned-full`, `phase3-stress-matrix`, or `phase4-final-rerun`                   |
| `fork_block`           | yes            | decimal mainnet block. `latest` is not allowed outside smoke                                                                           |
| `block_source`         | yes            | freeze runbook, historical event, current synthetic, etc.                                                                              |
| `full_deploy_eligible` | yes            | whether Day-1 dependencies exist at the block and the run can count as full deploy / handover rehearsal                                |
| `scope`                | yes            | deploy, handover, launch operation, targeted observation, frontend/admin hash matching, etc.                                           |
| `expected_result`      | yes            | `pass`, `warn`, or `fail-expected`                                                                                                     |
| `actual_result`        | after run      | `pass`, `warn`, or `fail`                                                                                                              |
| `exception_owner`      | if warn/fail   | concrete risk / launch owner. Generic owner labels are not enough                                                                      |
| `exception_reason`     | if warn/fail   | explicit reason if launch Go is still requested                                                                                        |
| `exclusion_reason`     | if excluded    | why a non-smoke `full_deploy_eligible=false` scenario does not count as full launch rehearsal PASS evidence                            |
| `risk_owner_signoff`   | before signoff | risk owner approval label, ticket, or signer reference. Required by strict check for executed scenarios                                |
| `artifact_path`        | after run      | S3 prefix or internal artifact label                                                                                                   |
| `manifest_sha256`      | after run      | deployment manifest hash                                                                                                               |
| `launch_config_sha256` | if applicable  | launch operation config hash                                                                                                           |
| `codebuild_build_id`   | if CodeBuild   | AWS CodeBuild build id                                                                                                                 |

Historical blocks with `full_deploy_eligible=false` can be used for targeted
observation, but they do not count as mainnet full rehearsal PASS evidence.

## 4. Required Scenario Set v0

| Scenario id                            | Family           | Phase                 | Block rule                                              | Full deploy eligible                 | Required checks                                                                                                                                                                                                                       | Notes                                                                                             |
| -------------------------------------- | ---------------- | --------------------- | ------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `local-current-smoke`                  | baseline         | phase0-local-smoke    | current block allowed                                   | no                                   | `mainnet-fork-evidence --skip-handover` passes env / deploy / manifest preflight                                                                                                                                                      | Local output is not production evidence                                                           |
| `dispatch-smoke`                       | baseline         | phase1-dispatch-smoke | current block allowed                                   | no                                   | GitHub OIDC starts CodeBuild and returns build id / status                                                                                                                                                                            | GitHub must not store RPC or deploy env secrets                                                   |
| `baseline-freeze-full`                 | baseline         | phase2-pinned-full    | deploy env freeze block                                 | yes                                  | full deploy, manifest preflight, handover prepare / pending verify, app env generation                                                                                                                                                | `--skip-handover=false`                                                                           |
| `launch-operation-freeze`              | launch-operation | phase2-pinned-full    | same as `baseline-freeze-full`                          | yes                                  | SP seed, JPYdf/USDC Uniswap v4 liquidity, bootstrap Trove, redemption / liquidation readiness, strategy operation                                                                                                                     | Requires launch operation config hash                                                             |
| `dtoken-cap-inert-branch-synthetic`    | branch-config    | phase3-stress-matrix  | current freeze fork                                     | yes                                  | Borrowable Branches 0–1 match frozen caps; Branches 2–7 have no Underlying binding, placeholder feeds, cap=0 / allocateMaxMove=0 / no Strategy or Zapper / no liquidity or UI exposure | Evidence dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB as Day-1 inert |
| `vault-buffer-strategy-synthetic`      | vault            | phase3-stress-matrix  | current freeze fork                                     | yes                                  | withdrawDelay, bufferTargetBps / floor, allocateMaxMove / cooldown, strategy weight / cap, none-strategy branch behavior, paused/frozen upstream deposit/withdraw failure mode, backingRatio visibility                               | Checks CollateralVault-level controls separately from Aave reserve stress                         |
| `stablecoin-usdc-depeg-observation`    | stablecoin       | phase3-stress-matrix  | USDC depeg / market stress block selected by risk owner | only if all Day-1 dependencies exist | USDC oracle, Aave reserve, liquidity, branch params (MCR 111.58% / LLTV 89.62% / CCR 124.50% / SCR 105%), frontend assumptions                                                                                                   | Day-1 direct JPYdf/USDC LP check needs dependency existence and branch risk parameter floor (Constants.sol) confirmation           |
| `wsteth-vol-liquidation-synthetic`     | liquidation      | phase3-stress-matrix  | current freeze fork                                     | yes                                  | wstETH price shock, TCR/SCR/CCR proximity, liquidation candidate scan, SP deposits / offset capacity / SP-covered candidate count, planned-batch gas / gasCost / stressedGasCost / decision, high-gas caps, SP coverage threshold, JIT/top-up owner, redistribution acceptance owner | Black Thursday-style drill: record shock input, gas assumptions, thin-SP behavior, and the liquidation / redistribution decision |
| `jpyusd-staleness-synthetic`           | oracle           | phase3-stress-matrix  | current freeze fork                                     | yes                                  | JPY/USD stale threshold, `jpyFrozenSince`, shutdown / frontend stale-state behavior                                                                                                                                                   | Must match `PRM-ORACLE-001`                                                                       |
| `aave-reserve-liquidity-synthetic`     | aave             | phase3-stress-matrix  | current freeze fork                                     | yes                                  | Aave reserve paused/frozen/supply-cap/liquidity shortage, strategy deposit/withdraw failure mode                                                                                                                                      | Required for active Aave strategy branches                                                        |
| `dex-usdc-v4-depth-synthetic`          | dex              | phase3-stress-matrix  | current freeze fork                                     | yes                                  | JPYdf/USDC v4 pool initialization, sample sell/buy slippage, LP owner, allowance cleanup                                                                                                                                              | Curve / Balancer / v3 / USDT direct route must be absent                                          |
| `redemption-liquidation-ops-synthetic` | liquidation      | phase3-stress-matrix  | current freeze fork                                     | yes                                  | redemption routing / base rate / outside debt / lowest-rate Troves / liquidator dry-run hash                                                                                                                                          | References canonical bot evidence                                                                 |
| `frontend-admin-payload-match`         | frontend-admin   | phase3-stress-matrix  | same commit and manifest as full rehearsal              | yes                                  | user app write-flow sample, ops action, admin console Safe calldata hash matching                                                                                                                                                     | Public summary is hash-only                                                                       |
| `final-freeze-rerun`                   | baseline         | phase4-final-rerun    | launch final freeze block                               | yes                                  | phase2 plus selected phase3 No-Go rechecks                                                                                                                                                                                            | No-Go must be clear                                                                               |

## 5. Scenario Matrix Template

```csv
scenario_id,family,phase,fork_block,block_source,full_deploy_eligible,scope,expected_result,actual_result,exception_owner,exception_reason,exclusion_reason,risk_owner_signoff,artifact_path,manifest_sha256,launch_config_sha256,codebuild_build_id
baseline-freeze-full,baseline,phase2-pinned-full,<FORK_BLOCK>,deploy-env-freeze,true,full deploy + handover + manifest preflight,pass,,,,,,s3://<bucket>/mainnet-fork-stress/<build>/baseline-freeze-full,<sha256>,<sha256>,<build-id>
stablecoin-usdc-depeg-observation,stablecoin,phase3-stress-matrix,<FORK_BLOCK>,risk-owner-historical-selection,<true|false>,USDC oracle + Aave reserve + liquidity observation,warn,,,,,,s3://<bucket>/mainnet-fork-stress/<build>/stablecoin-usdc-depeg-observation,<sha256>,,<build-id>
```

## 6. CodeBuild Run List Template

```csv
scenario_id,github_run_id,github_sha,codebuild_project,codebuild_build_id,status,started_at,ended_at,artifact_path,operator_label
baseline-freeze-full,<run-id>,<commit>,<project>,<build-id>,<SUCCEEDED|FAILED>,<utc>,<utc>,s3://<bucket>/mainnet-fork-stress/<build>/baseline-freeze-full,<operator>
```

Record `FORK_BLOCK`, `DF_STRESS_SCENARIO_ID`, handover mode, launch config hash,
manifest hash, CodeBuild ids, and artifact bucket label for every run.

## 7. Business Summary Template

```text
Mainnet fork stress scenario package

Package date:
Launch owner:
Risk owner:
Ops owner:
Finance/accounting owner:
Commit:
Deploy env freeze evidence:
Launch operation config hash:
Scenario matrix artifact:
CodeBuild run list:

Overall status: pass / warn / fail
Remaining No-Go: yes / no

Scenario summary:
| Scenario id | Family | Result | Full deploy eligible | Exclusion reason | Risk sign-off | Launch decision | Owner / exception |
| --- | --- | --- | --- | --- | --- | --- | --- |

External dependency coverage:
| Dependency | Covered by | Historical block eligible | Synthetic fallback | Notes |
| --- | --- | --- | --- | --- |

Day-1 route exclusions:
Curve route absent:
Balancer route absent:
Uniswap v3 JPYdf route absent:
USDT / USDS / WETH / XAUt direct JPYdf pool absent:

Go / No-Go:
Decision:
Sign-off:
```

## 8. Secret Hygiene Checklist

| Check                                                             | Required result |
| ----------------------------------------------------------------- | --------------- |
| raw `MAINNET_RPC_URL` absent                                      | yes             |
| AWS secret ARN values are label-only or redacted when public      | yes             |
| private key / mnemonic absent                                     | yes             |
| unpublished Safe nonce absent                                     | yes             |
| raw privileged calldata absent from public summary                | yes             |
| Safe / admin payload hash present                                 | yes             |
| `DF_DEPLOY_ENV_FILE` raw value absent                             | yes             |
| artifact bucket is not public                                     | yes             |
| CodeBuild project uses Secrets Manager env for RPC and deploy env | yes             |

Any `no` is No-Go until fixed or moved to internal-only evidence with explicit
risk-owner exception.

## 9. Historical Block Rules

- If Aave reserve, Uniswap v4 pool, or another current
  deploy dependency did not exist at the block, set `full_deploy_eligible=false`.
- Do not use `full_deploy_eligible=false` as evidence that the full launch path passes.
- Use historical block output for targeted observation, then cover missing
  dependencies with current-fork synthetic tests.
- Record the dependency existence check in `External dependency coverage`.

## 10. Relation To Other Gates

- The source of truth is `Constants.sol` / [Parameters.md §2-A](../../../Parameters.md).
  Branch 2 dETH uses the same MCR 123.18% / LLTV 81.18% / CCR 141.67% / SCR 110%
  envelope as Branch 0 dwstETH; all other values come from the Owner Manifest.
  (stress-implied restoration).
  The stress package must not PASS under assumptions below these floors.
- The former scenarios that presupposed USDT / XAUt branches
  (`stablecoin-usdt-stress-observation` / `xaut-vol-oracle-synthetic`) were removed
  from the tooling catalog with the candidate-asset archival (#1454 / #1459) and are
  not part of the required set.
- [`Mainnet-Launch-Operation-Gate.md`](Mainnet-Launch-Operation-Gate.md)
  is the Japanese source of truth for SP seed, JPYdf/USDC liquidity, bootstrap
  Trove, redemption / liquidation readiness targets.
- Frontend and admin production gates own delivery readiness; this package only
  records fork-state write-flow and payload-hash evidence.
- [`AWS-CDK-IAM-Evidence-Gate.md`](../../../contributors/deltaforesight/delivery-plans/AWS-CDK-IAM-Evidence-Gate.md)
  is the Japanese source of truth for IAM / KMS / S3 / CodeBuild permission
  evidence.
