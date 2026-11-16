# Mainnet Fork Stress Scenario Package

> **位置づけ**: [`Mainnet-Fork-Stress-Gate.md`](./Mainnet-Fork-Stress-Gate.md) を実行する時に、どの scenario を回し、どの artifact を evidence bucket に残し、business / risk reviewer が何を見れば Go / No-Go を判断できるかを固定する package template。Issue #405 の作業成果はこの形式で残す。
>
> 本書は scenario package の型を定義する。actual `FORK_BLOCK`、CodeBuild build id、manifest hash、launch config hash、owner sign-off は launch freeze 時の evidence package に記入し、repo には private key、raw `MAINNET_RPC_URL`、AWS secret、unpublished Safe nonce を残さない。

## 1. Package Layout

evidence bucket には scenario id ごとの raw artifact と、review 用 summary を分けて置く。

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

`scenario-matrix.*` は business / risk review の一次入口にする。step log や raw command output は internal artifact として残してよいが、review summary には secret、raw calldata、private endpoint、未公開 Safe nonce を含めない。

## 2. Scaffold Command

scenario package の starter files は contracts package から生成する。これは実行証跡ではなく、
launch freeze 時に actual `FORK_BLOCK`、CodeBuild build id、manifest hash、launch config
hash、owner sign-off を埋めるための雛形である。

```bash
cd contracts
pnpm mainnet-fork-stress-package:init \
  --out /path/to/evidence-dir/mainnet-fork-stress-evidence
```

既存 package を意図的に更新する場合だけ `--force` を使う。生成された public summary には
private key、raw `MAINNET_RPC_URL`、AWS secret、raw privileged calldata、未公開 Safe nonce
を追記しない。

生成直後の draft package は placeholder を許可して構造だけ確認する。

```bash
cd contracts
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence \
  --allow-placeholders
```

実行済み scenario artifact を package に取り込む時は、raw log を手動で summary に貼らず、
hash / build id / artifact label だけを import command で反映する。

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

`--run` は `mainnet-fork-evidence` / CodeBuild が出す `evidence-summary.txt`、
`deployment-manifest.sha256`、任意の `launch-operation-config.sha256` /
`launch-operation/launch-operation-evidence.json` を読む。`--actual-result=warn|fail`
では `--exception-owner` と `--exception-reason` が必須。`full_deploy_eligible=false`
の non-smoke scenario は `--exclusion-reason` で、なぜ full deploy PASS に数えないかを
明記する。`--risk-owner-signoff` は execution import 時点で未確定でもよいが、sign-off
前の strict check では全 scenario で必須。`--artifact-path` は S3 prefix または
`codebuild://...` / `internal://...` label とし、raw HTTP(S) URL は使わない。

launch sign-off 前は placeholder を許可しない strict check を通す。strict check は
`actual_result`、`fork_block`、manifest / launch config hash、`Remaining No-Go: no`、
CodeBuild run list、secret hygiene の yes/no、public summary の raw URL / long calldata /
private-key-like value を確認し、No-Go が残る場合は non-zero で終了する。実行済み
scenario では `import-summary.json` も provenance として必須になり、`scenario-matrix.json`
と `scenario-matrix.csv`、CodeBuild run row、import summary の hash / build id /
artifact label が矛盾している場合や、`actual_result=pass` なのに CodeBuild status が
`FAILED` の場合も fail する。実行済み scenario の `risk_owner_signoff` が空欄の
場合、また non-smoke scenario で `full_deploy_eligible=false` なのに `exclusion_reason`
が空欄の場合も fail する。required scenario の `family` / `phase` /
`expected_result` / required flag が tooling の canonical scenario catalog とズレた
場合、また `scenario-matrix.*` / `codebuild-runs.csv` の field schema が canonical
schema とズレた場合も fail する。

```bash
cd contracts
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence
```

repo 内の required scenario docs と tooling catalog の同期は、PR 前に次で確認する。

```bash
cd contracts
pnpm mainnet-fork-stress-package:check-docs
```

## 3. Scenario Matrix Schema

| Field                  | Required       | Meaning                                                                                                                                        |
| ---------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `scenario_id`          | yes            | path-safe id。例 `baseline-freeze-full`                                                                                                        |
| `family`               | yes            | `baseline` / `launch-operation` / `branch-config` / `vault` / `stablecoin` / `oracle` / `dex` / `aave` / `liquidation` / `frontend-admin` など |
| `phase`                | yes            | `phase0-local-smoke` / `phase1-dispatch-smoke` / `phase2-pinned-full` / `phase3-stress-matrix` / `phase4-final-rerun`                          |
| `fork_block`           | yes            | decimal mainnet block。smoke 以外で `latest` は不可                                                                                            |
| `block_source`         | yes            | freeze runbook、historical event、current synthetic など                                                                                       |
| `full_deploy_eligible` | yes            | Day-1 依存がその block に存在し、full deploy / handover rehearsal として扱えるか                                                               |
| `scope`                | yes            | deploy、handover、launch operation、targeted observation、frontend/admin hash matching など                                                    |
| `expected_result`      | yes            | `pass` / `warn` / `fail-expected`                                                                                                              |
| `actual_result`        | after run      | `pass` / `warn` / `fail`                                                                                                                       |
| `exception_owner`      | if warn/fail   | risk owner / launch owner。generic owner は不可                                                                                                |
| `exception_reason`     | if warn/fail   | launch Go に使う場合の明示理由                                                                                                                 |
| `exclusion_reason`     | if excluded    | `full_deploy_eligible=false` の non-smoke scenario が full launch rehearsal PASS に数えられない理由                                            |
| `risk_owner_signoff`   | before signoff | risk owner の承認 label / ticket / signer reference。実行済み scenario の strict check では必須                                                |
| `artifact_path`        | after run      | S3 prefix or internal artifact label                                                                                                           |
| `manifest_sha256`      | after run      | deployment manifest hash                                                                                                                       |
| `launch_config_sha256` | if applicable  | launch operation config hash                                                                                                                   |
| `codebuild_build_id`   | if CodeBuild   | AWS CodeBuild build id                                                                                                                         |

`full_deploy_eligible=false` の historical block は、targeted observation としては使えるが、mainnet full rehearsal の PASS に数えない。

## 4. Required Scenario Set v0

| Scenario id                            | Family           | Phase                 | Block rule                                            | Full deploy eligible                 | Required checks                                                                                                                                                                                                                                                                     | Notes                                                                                                 |
| -------------------------------------- | ---------------- | --------------------- | ----------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `local-current-smoke`                  | baseline         | phase0-local-smoke    | current block allowed                                 | no                                   | `mainnet-fork-evidence --skip-handover` が env / deploy / manifest preflight まで通る                                                                                                                                                                                               | 個人 PC output は production evidence にしない                                                        |
| `dispatch-smoke`                       | baseline         | phase1-dispatch-smoke | current block allowed                                 | no                                   | GitHub OIDC が CodeBuild を起動し、build id / status が返る                                                                                                                                                                                                                         | GitHub に RPC / deploy env secret が無いこと                                                          |
| `baseline-freeze-full`                 | baseline         | phase2-pinned-full    | deploy env freeze block                               | yes                                  | full deploy、manifest preflight、handover prepare / pending verify、app env generation                                                                                                                                                                                              | `--skip-handover=false`                                                                               |
| `launch-operation-freeze`              | launch-operation | phase2-pinned-full    | same as `baseline-freeze-full`                        | yes                                  | SP seed、JPYdf/USDC Uniswap v4 liquidity、bootstrap Trove、redemption / liquidation readiness、strategy operation                                                                                                                                                                   | [`Mainnet-Launch-Operation-Gate.md`](./Mainnet-Launch-Operation-Gate.md) config hash 必須             |
| `dtoken-cap-inert-branch-synthetic`    | branch-config    | phase3-stress-matrix  | current freeze fork                                   | yes                                  | borrowable branch 0–1のdToken capがfreeze envと一致し、branch 2–7がUnderlying未binding・placeholder PriceFeed・cap=0 / allocateMaxMove=0 / Strategy / Zapperなし・liquidity / UI exposureなし | dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGBをDay-1 inertとして証跡化 |
| `vault-buffer-strategy-synthetic`      | vault            | phase3-stress-matrix  | current freeze fork                                   | yes                                  | withdrawDelay、bufferTargetBps / floor、allocateMaxMove / cooldown、strategy weight / cap、none-strategy branch、paused/frozen upstream の deposit/withdraw failure mode、backingRatio 表示                                                                                         | Aave reserve 個別ストレスとは別に CollateralVault 全体の運用制御を確認                                |
| `stablecoin-usdc-depeg-observation`    | stablecoin       | phase3-stress-matrix  | USDC depeg / market stress block chosen by risk owner | only if all Day-1 dependencies exist | USDC oracle, Aave reserve, liquidity, branch params (MCR 111.58% / LLTV 89.62% / CCR 124.50% / SCR 105%), frontend warning assumptions                                                                                                                                         | Day-1 direct JPYdf/USDC LP check は dependency existence と branch risk parameter floor（Constants.sol）を確認                         |
| `wsteth-vol-liquidation-synthetic`     | liquidation      | phase3-stress-matrix  | current freeze fork                                   | yes                                  | wstETH price shock, TCR/SCR/CCR proximity, liquidation candidate scan, SP deposits / offset capacity / SP-covered candidate count, planned-batch gas / gasCost / stressedGasCost / decision, high-gas caps, SP coverage threshold, JIT/top-up owner, redistribution acceptance owner  | Black Thursday 型 drill。shock input、gas 前提、thin-SP 挙動、liquidation / redistribution 判断を記録 |
| `jpyusd-staleness-synthetic`           | oracle           | phase3-stress-matrix  | current freeze fork                                   | yes                                  | JPY/USD stale threshold, `jpyFrozenSince`, shutdown / frontend stale-state behavior                                                                                                                                                                                                 | `PRM-ORACLE-001` と矛盾しない                                                                         |
| `aave-reserve-liquidity-synthetic`     | aave             | phase3-stress-matrix  | current freeze fork                                   | yes                                  | Aave reserve paused/frozen/supply-cap/liquidity shortage, strategy deposit/withdraw failure mode                                                                                                                                                                                    | active Aave strategy branch は必須                                                                    |
| `dex-usdc-v4-depth-synthetic`          | dex              | phase3-stress-matrix  | current freeze fork                                   | yes                                  | JPYdf/USDC v4 pool initialization, sample sell/buy slippage, LP owner, allowance cleanup                                                                                                                                                                                            | Curve / Balancer / v3 / USDT direct route が残っていないこと                                          |
| `redemption-liquidation-ops-synthetic` | liquidation      | phase3-stress-matrix  | current freeze fork                                   | yes                                  | redemption routing / base rate / outside debt / lowest-rate Troves / liquidator config hash / dry-run hash / gas-loss caps / gas stress multiplier / SP offset threshold / SP shortfall decision / JIT funding source / collateral disposal owner / failed receipt escalation owner | bot canonical evidence と Mainnet-Launch-Operation-Gate liquidator config を参照                      |
| `frontend-admin-payload-match`         | frontend-admin   | phase3-stress-matrix  | same commit and manifest as full rehearsal            | yes                                  | user app write-flow sample、ops action、admin console Safe calldata hash matching                                                                                                                                                                                                   | raw calldata は internal artifact、summary は hash only                                               |
| `final-freeze-rerun`                   | baseline         | phase4-final-rerun    | launch final freeze block                             | yes                                  | phase2 + selected phase3 no-go rechecks                                                                                                                                                                                                                                             | No-Go が残らないこと                                                                                  |

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

For every CodeBuild run, record:

- `FORK_BLOCK`
- `DF_STRESS_SCENARIO_ID`
- `DF_STRESS_SKIP_HANDOVER`
- `DF_LAUNCH_OPERATION_CONFIG` hash, if used
- `deployment-manifest.sha256`
- CodeBuild build id and project name
- artifact bucket label, not a public URL

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

Before sharing the package summary or linking it in a PR / issue:

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

Any `no` is No-Go until fixed or moved to internal-only evidence with risk owner exception.

## 9. Historical Block Rules

Historical stress blocks are useful for market observation, but they are often older than Day-1 dependencies.

- If Aave reserve, Uniswap v4 pool, or current deploy dependency did not exist at the block, set `full_deploy_eligible=false`.
- Do not use `full_deploy_eligible=false` as evidence that the full launch path passes.
- Use historical block output for target observation only, then cover missing dependencies with current-fork synthetic tests.
- Record the dependency existence check in `External dependency coverage`.

## 10. Relation To Other Gates

- #302 remains the source issue for the USD-stable MCR / LLTV review (originally USDC / USDT / sUSDS; the current branch mapping is Parameters.md). This package records scenario execution and must not contradict #302 outcomes.
- USDT / XAUt branchを前提とした旧scenario（`stablecoin-usdt-stress-observation` / `xaut-vol-oracle-synthetic`）は、候補資産のarchive化（#1454 / #1459）に伴いtooling catalogから削除済みで、required setに含めない。
- 現行値は[Parameters.md](../../../Parameters.md)とOwner Manifestを正本とし、branch 2 dETHはbranch 0 dwstETHと同じMCR 123.18% / LLTV 81.18% / CCR 141.67% / SCR 110%である。stress packageはこれを下回る前提でPASSにしてはならない。
- [`Mainnet-Launch-Operation-Gate.md`](./Mainnet-Launch-Operation-Gate.md) owns SP seed, JPYdf/USDC liquidity, bootstrap Trove, redemption / liquidation readiness targets.
- [`Frontend-Production-Delivery-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md) and [`Admin-Console-Production-Gate.md`](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) own production frontend / console delivery gates; this package only records fork-state write-flow and payload hash evidence.
- [`AWS-CDK-IAM-Evidence-Gate.md`](../../../contributors/deltaforesight/delivery-plans/AWS-CDK-IAM-Evidence-Gate.md) owns IAM / KMS / S3 / CodeBuild permission evidence.
