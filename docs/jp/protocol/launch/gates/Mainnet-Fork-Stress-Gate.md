# Mainnet Fork Stress Gate

この runbook は mainnet launch 前に、archive RPC、Foundry / Anvil fork、
AWS CodeBuild、KMS encrypted S3 artifact を使って、実行予定の deploy /
handover / launch operation と過去 stress scenario を自前で証跡化する gate を定義する。

日本語版を source of truth とする。本書は
[Mainnet-Initial-Configuration-Checklist.md](./Mainnet-Initial-Configuration-Checklist.md)、
[Mainnet-Deploy-Env-Freeze-Runbook.md](./Mainnet-Deploy-Env-Freeze-Runbook.md)、
[Mainnet-Governance-Handover-Runbook.md](./Mainnet-Governance-Handover-Runbook.md)、
[Mainnet-Launch-Operation-Gate.md](./Mainnet-Launch-Operation-Gate.md)、
[Mainnet-Fork-Stress-Scenario-Package.md](./Mainnet-Fork-Stress-Scenario-Package.md)、
[Frontend-Production-Delivery-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md)、
[Admin-Console-Production-Gate.md](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) の補助 gate であり、
それらの direct RPC read、handover verification、frontend evidence を置き換えない。

## 1. Scope

対象:

- Ethereum mainnet の pinned block を使った `mainnet-fork-evidence` 実行。
- Safe / role holder が実行する Day-1 governance / ops tx の fork rehearsal。
- admin console が生成する privileged operation calldata の payload hash 照合。
- mainnet launch window の SP seed、JPYdf/USDC Uniswap v4 liquidity、bootstrap Trove、
  redemption / liquidation readiness、strategy operation の rehearsal。
- 過去または近似 stress block を使った oracle、DEX liquidity、Aave reserve、
  liquidation / redemption、gas congestion、external protocol availability の検証。
- AWS CodeBuild / S3 artifact による再現可能な証跡保存。

対象外:

- 外部 simulation SaaS を launch gate の必須依存にすること。
- private key、raw `MAINNET_RPC_URL`、AWS secret、unpublished Safe nonce を evidence に
  残すこと。
- 本番 tx の自動送信。fork stress gate は「実行前の証跡」であり、送信は Safe /
  role holder wallet の明示操作で行う。
- 古すぎる block で、Day-1 に使う外部依存がまだ存在しない状態を full deploy
  rehearsal として扱うこと。

## 2. Gate Positioning

mainnet launch evidence package の中で、この gate は次の役割を持つ。

| Layer               | 一次 gate                                           | Fork stress gate で追加する確認                                                   |
| ------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------- |
| deploy env freeze   | mainnet external address freeze / manifest freeze   | same commit / same env / pinned block で deploy と manifest preflight が通る      |
| governance handover | handover dry-run / accept / verify                  | fork 上で prepare / pending owner verify が通る                                   |
| launch operation    | SP seed / LP / redemption / liquidator direct reads | launch operation config と fork state が矛盾しない                                |
| frontend app / ops  | hosting env / data source / stale-state gate        | public write flow や ops action が参照する calldata / route を fork state で読む  |
| admin console       | auth / noindex / Safe boundary / calldata export    | exported calldata hash と fork rehearsal input hash を照合する                    |
| risk parameters     | `Parameters.md` と risk owner sign-off              | historical / synthetic stress で MCR / LLTV / cap / route gate の前提を再確認する |

Business / risk review では、細かい trace 全体ではなく、次を確認できればよい。

- 対象 scenario がどの launch stage / risk family のものか。
- `commit`、`FORK_BLOCK`、manifest hash、launch config hash が固定されているか。
- expected status と実 status が一致するか。
- deploy / handover / launch operation / frontend route のうち、どこまで実行したか。
- stress block が Day-1 外部依存の存在後か。古い block の場合は対象範囲を限定しているか。
- 証跡が AWS 管理 artifact として残り、secret を含まないか。

## 3. Required Scenario Set

mainnet public launch 前に、最低限以下を fork evidence に含める。

| Scenario                                      | 必須度                            | 備考                                                                                                                                                                                                    |
| --------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Current freeze block baseline                 | Must                              | `Mainnet-Deploy-Env-Freeze-Runbook` で freeze した current block。full deploy / handover / manifest preflight を実行                                                                                    |
| Launch operation rehearsal                    | Must                              | SP seed、JPYdf/USDC liquidity、bootstrap Trove、redemption / liquidation readiness を config hash 付きで確認                                                                                            |
| Governance / owner handover                   | Must                              | pending owner / role holder / Timelock delay の verify。`--skip-handover` なしで実行                                                                                                                    |
| Stablecoin depeg family                       | Must                              | USDC の価格・流動性・Aave reserve 前提を確認。古い depeg event は外部依存存在後でなければ full deploy ではなく対象限定 test にする                                                |
| High-volatility collateral family             | Must                              | wstETH の価格下落、oracle update、liquidation candidate scan、SP capacity を確認                                                                                                               |
| JPY / USD and oracle staleness family         | Must                              | JPY/USD stale threshold、fallback / shutdown behavior、frontend stale-state gate と整合させる                                                                                                           |
| Branch lifecycle / recovery-vs-death          | Must                              | backing 低下・Strategy 回収・backstop で live 復旧する branch と、branch-local oracle / backing read failure で不可逆 shutdown する branch を分けて確認                                                 |
| dToken cap / inert branch readiness | Must | active branch 0–1のcapと、branch 2–7のUnderlying未binding・placeholder PriceFeed・cap=0 / allocateMaxMove=0・Strategy / Zapperなし・no liquidity / UI exposureを確認 |
| Vault buffer / allocator / strategy controls  | Must                              | withdrawDelay、bufferTargetBps / floor、allocateMaxMove / cooldown、strategy weight / cap、paused/frozen upstream failure mode、backingRatio 表示を確認                                                 |
| DEX liquidity stress                          | Must                              | Day-1 は JPYdf/USDC Uniswap v4 のみ。Curve / Balancer / Uniswap v3 / USDT direct route は scenario から除外                                                                                             |
| Aave reserve stress                           | Must when Aave strategy is active | frozen / paused / supply cap / liquidity shortage を fork or targeted test で確認                                                                                                                       |
| Liquidator dry-run                            | Separate gate                     | canonical evidence は `Mainnet-Launch-Operation-Gate` と bot runbook。ここでは artifact hash を参照                                                                                                     |
| User app public write-flow sample             | Should                            | borrow / adjust / redeem / SP deposit / vault redeem など主要 flow の代表 calldata を確認                                                                                                               |

Scenario block は本文へ固定値として埋め込まない。各 rehearsal で risk owner が
`DF_STRESS_SCENARIO_ID`、`FORK_BLOCK`、対象範囲、除外理由、artifact id を evidence に残す。
scenario id、matrix、business summary、secret hygiene の package 形式は
[`Mainnet-Fork-Stress-Scenario-Package.md`](./Mainnet-Fork-Stress-Scenario-Package.md)
を使う。sign-off 前の strict check では、実行済み scenario の `risk_owner_signoff` と、
full deploy rehearsal に数えない non-smoke scenario の `exclusion_reason` を必須とする。

古い危機イベントを使う場合のルール:

- full deploy rehearsal は、Day-1 外部依存がその block に存在する時だけ使う。
- 依存が存在しない場合、古い block は「対象資産 / 対象 external protocol の観測」
  に限定し、current fork 上の synthetic stress test、unit / invariant、または
  targeted fork test で補う。
- `latest` block は smoke には使ってよいが、mainnet launch evidence では pinned block
  を必須にする。

## 4. AWS Execution Policy

production evidence は operator local machine だけで作らない。AWS 側に
少なくとも次の boundary を置く。

- GitHub Actions は OIDC で AWS role を assume し、CodeBuild を起動して完了 status を
  待つだけにする。
- CodeBuild / GitHub Actions OIDC / deployment role は会社管理 AWS account に置く。
- `MAINNET_RPC_URL` は archive-capable RPC とし、AWS Secrets Manager または
  SSM Parameter Store から読む。GitHub repository / environment secrets には置かない。
- `DEPLOYER` / `DF_*` の freeze 済み deploy env は Secrets Manager の env file
  secret に置き、CodeBuild で literal `KEY=value` として export する。private key、
  raw RPC URL、未公開 Safe nonce はこの secret に入れない。
- `DEPLOYER` は anvil impersonation 用の公開 address であり、private key ではない。
- CodeBuild image は `forge` / `anvil` / `cast` / Git / Node / pnpm を持つ。version は
  evidence summary に残す。
- CodeBuild log と artifact には raw secret、raw RPC URL、private key、Safe nonce を
  出さない。
- `mainnet-fork-stress-evidence/**` は KMS encrypted S3 bucket に保存し、public / PR body
  には redacted summary だけを貼る。
- evidence は build id、commit、scenario id、fork block、manifest hash、launch config hash、
  operator label、artifact bucket label を持つ。
- scheduled rehearsal を入れる場合、失敗は CloudWatch / SNS / Slack などで launch owner
  と risk owner に通知する。

CDK 標準構成では `JPYDF_FORK_STRESS_ENABLED=true` の backend stack が次を作る。

| Resource                          | 役割                                                 | Boundary                                                                                                                             |
| --------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `ForkStressGateProjectName`       | `mainnet-fork-evidence` を実行する CodeBuild project | buildspec は `infra/cdk/buildspecs/mainnet-fork-stress-gate.yml`。`MAINNET_RPC_URL` と freeze deploy env file は Secrets Manager env |
| `ForkStressEvidenceBucketName`    | evidence artifact 保存先                             | Block Public Access、versioning、SSE-KMS                                                                                             |
| `ForkStressGithubDispatchRoleArn` | GitHub Actions が assume する OIDC role              | `aud=sts.amazonaws.com` と repo/ref subject に限定。権限は `codebuild:StartBuild` / `codebuild:BatchGetBuilds` のみ                  |

CDK deploy role と fork stress dispatch role は別物にする。dispatch role に
CloudFormation / IAM / S3 bucket 管理 / Secrets Manager 書き込み権限を持たせない。

## 5. Experiment Ladder

本番 calldata を扱う前に、次の順で実験する。

| Phase                                  | 目的                                                                    | Go 条件                                                           |
| -------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Phase 0: local current-block smoke     | env と `mainnet-fork-evidence` の基本動作確認                           | `--skip-handover` で deploy / manifest preflight が通る           |
| Phase 1: GitHub OIDC dispatch smoke    | GitHub Actions が AWS OIDC role だけで CodeBuild を起動できることを確認 | GitHub に RPC secret を置かず、CodeBuild build id / status が返る |
| Phase 2: single pinned block rehearsal | freeze block で full deploy / handover / launch operation を確認        | `--skip-handover` なしで pass し、artifact が S3 に残る           |
| Phase 3: historical / synthetic matrix | risk family ごとの stress scenario を横断確認                           | 各 scenario に pass / fail / accepted exception と owner が残る   |
| Phase 4: pre-launch final rerun        | launch 直前の freeze commit / config / block で再実行                   | No-Go が残らず、他 runbook の evidence hash と一致する            |

Phase 2 以降の production rehearsal config は repo に commit しない。Safe / console
artifact、deployment manifest hash、launch operation config hash、AWS build id と一緒に
evidence bucket に保存する。保存時の package layout と scenario matrix は
[`Mainnet-Fork-Stress-Scenario-Package.md`](./Mainnet-Fork-Stress-Scenario-Package.md)
に従う。

## 6. Standard Commands

標準コマンドは `contracts` package の `mainnet-fork-evidence` を使う。

Scenario package scaffold:

```bash
cd contracts
pnpm mainnet-fork-stress-package:init \
  --out /path/to/evidence-dir/mainnet-fork-stress-evidence
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence \
  --allow-placeholders
```

Local smoke:

```bash
cd contracts
pnpm mainnet-fork-evidence \
  --out /tmp/jpydf-mainnet-fork-stress-baseline \
  --skip-handover
```

Full rehearsal:

```bash
cd contracts
DF_LAUNCH_OPERATION_CONFIG=/path/to/mainnet-launch-operation.config.json \
pnpm mainnet-fork-evidence \
  --out /path/to/evidence-dir/mainnet-fork-stress
```

Run artifact import:

```bash
cd contracts
pnpm mainnet-fork-stress-package:import-run \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence \
  --run /path/to/evidence-dir/mainnet-fork-stress \
  --scenario baseline-freeze-full \
  --actual-result pass \
  --full-deploy-eligible true \
  --codebuild-status SUCCEEDED
```

import は `scenario-matrix.*`、`codebuild-runs.csv`、scenario README の safe metadata
だけを更新する。raw log、raw RPC URL、raw privileged calldata は public summary に貼らない。

手動 GitHub Actions 入口:

```bash
gh workflow run mainnet-fork-stress-gate.yml \
  --repo deltaforesight/jpydf-v2 \
  -f fork_block=<pinned-mainnet-block> \
  -f scenario_id=baseline-current \
  -f skip_handover=false \
  -f aws_region=ap-northeast-1 \
  -f aws_role_to_assume=arn:aws:iam::<account-id>:role/<github-oidc-codebuild-dispatch-role> \
  -f codebuild_project=<jpydf-mainnet-fork-stress-project>
```

`aws_role_to_assume` と `codebuild_project` は CDK output の
`ForkStressGithubDispatchRoleArn` / `ForkStressGateProjectName` を使う。

Sign-off 前 package check:

```bash
cd contracts
pnpm mainnet-fork-stress-package:check \
  --package /path/to/evidence-dir/mainnet-fork-stress-evidence
```

AWS CodeBuild 入口:

- `.github/workflows/mainnet-fork-stress-gate.yml`
- `infra/cdk/buildspecs/mainnet-fork-stress-gate.yml`
- `FORK_BLOCK` は decimal mainnet block number。
- `DF_STRESS_SCENARIO_ID` は path-safe id。
- `DF_STRESS_SKIP_HANDOVER` は production final rehearsal では `false`。
- `DF_LAUNCH_OPERATION_CONFIG` は任意。指定する場合は `contracts/` からの相対 path、
  または CodeBuild workspace 上の private config path とする。
- CodeBuild project は GitHub OIDC dispatch role から `codebuild:StartBuild` /
  `codebuild:BatchGetBuilds` だけを許可する。

CDK synth に必要な主な設定:

| 設定                                         | 必須条件               | 備考                                                                                                                                                                                                                 |
| -------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `JPYDF_FORK_STRESS_ENABLED=true`             | gate を AWS に作る時   | `JPYDF_BACKEND_ENABLED=true` も必要                                                                                                                                                                                  |
| `JPYDF_FORK_STRESS_BUILD_IMAGE`              | fork stress enabled 時 | `forge` / `anvil` / `cast` / Git / Node / pnpm 入り。production は digest 必須                                                                                                                                       |
| `JPYDF_FORK_STRESS_MAINNET_RPC_SECRET_ARN`   | fork stress enabled 時 | archive-capable RPC URL を格納した Secrets Manager ARN                                                                                                                                                               |
| `JPYDF_FORK_STRESS_DEPLOY_ENV_SECRET_ARN`    | fork stress enabled 時 | `DEPLOYER` / `DF_*` / `DEPLOYMENT_MODE` / `SALT` / `GAS_ESTIMATE_MULTIPLIER` の freeze 済み env file を literal `KEY=value` で格納した Secrets Manager ARN。`export` 行、private key、raw RPC URL、Safe nonce は不可 |
| `JPYDF_FORK_STRESS_GITHUB_OIDC_PROVIDER_ARN` | fork stress enabled 時 | `token.actions.githubusercontent.com` provider ARN                                                                                                                                                                   |
| `JPYDF_FORK_STRESS_GITHUB_REPOSITORY`        | 任意                   | default `deltaforesight/jpydf-v2`                                                                                                                                                                                    |
| `JPYDF_FORK_STRESS_GITHUB_REF_PATTERN`       | 任意                   | default `repo:deltaforesight/jpydf-v2:ref:refs/heads/develop`。repository prefix 不一致、branch / tag 以外の subject は CDK config が拒否                                                                            |

`JPYDF_FORK_STRESS_DEPLOY_ENV_SECRET_ARN` の secret value は shell script として
source しない。`Mainnet-Deploy-Env-Freeze-Runbook.md` の `export KEY=value`
skeleton から `export` を外し、`DF_*`、`DEPLOYER`、`DEPLOYMENT_MODE`、`SALT`、
`GAS_ESTIMATE_MULTIPLIER` の literal `KEY=value` だけを格納する。buildspec は
`*PRIVATE*` / `*SECRET*` / `*MNEMONIC*` / `*RPC*` を含む key 名を拒否する。
private key、raw RPC URL、未公開 Safe nonce は入れない。

必要な secret / env:

| 変数                               | 用途                                                                                                          | 証跡への扱い                                                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `MAINNET_RPC_URL`                  | archive-capable fork source                                                                                   | raw URL は出力禁止                                                                                                |
| `DF_DEPLOY_ENV_FILE`               | Secrets Manager から渡される freeze 済み deploy env file。CodeBuild が literal `KEY=value` として export する | raw 内容は出力禁止。許可 key は `DF_*` / `DEPLOYER` / `DEPLOYMENT_MODE` / `SALT` / `GAS_ESTIMATE_MULTIPLIER` のみ |
| `FORK_BLOCK` / `FORK_BLOCK_NUMBER` | pinned block                                                                                                  | 出力必須                                                                                                          |
| `DEPLOYER`                         | anvil impersonation 用公開 address                                                                            | 出力可                                                                                                            |
| `DF_*` deploy env                  | deploy / handover / strategy / launch operation config                                                        | secret 値は出力禁止。address / hash は出力可                                                                      |
| `DF_LAUNCH_OPERATION_CONFIG`       | launch operation check config                                                                                 | path / config hash は出力可                                                                                       |
| `DF_STRESS_SCENARIO_ID`            | stress scenario id                                                                                            | 出力必須                                                                                                          |

出力:

- `evidence-summary.txt`
- step ごとの `*.cmd` / `*.log`
- `deployment-manifest.json`
- `deployment-manifest.sha256`
- optional `deployment-context-latest.json`
- optional `launch-operation/launch-operation-evidence.{json,md}`

公開 summary は raw calldata、secret、private endpoint を含めない。payload は admin console /
Safe artifact 側で別途保持し、hash を照合する。

## 7. No-Go Conditions

以下が 1 つでも残る場合、mainnet public launch / privileged tx 実行に進まない。

- full rehearsal が pinned block で再現できない。
- deploy / manifest preflight / handover verify / launch operation check のいずれかが
  unexplained fail になる。
- simulation target の `to` / value / calldata hash が Safe artifact / console export と
  一致しない。
- evidence が `latest` block または古い generated binding / 古い launch config に基づく。
- AWS artifact ではなく、個人 PC の一時出力しか存在しない。
- evidence または PR body に raw RPC URL、AWS secret、private key、unpublished Safe nonce
  が含まれる。
- Day-1 方針外の Curve / Balancer / Uniswap v3 / USDT direct route を前提にした
  scenario が残る。
- historical stress block が Day-1 外部依存の存在前なのに、full deploy rehearsal の
  PASS として扱われている。
- fail / warn を risk owner の明示 exception なしに Go 扱いしている。

## 8. Evidence Template

scenario package 全体の standard template は
[`Mainnet-Fork-Stress-Scenario-Package.md`](./Mainnet-Fork-Stress-Scenario-Package.md)
を正とする。以下は単一 scenario の最小 summary として使う。

```text
Mainnet fork stress evidence
Date:
Operator:
AWS account label:
AWS region:
CodeBuild project:
Build id:
Artifact bucket label:
Commit:
Scenario id:
FORK_BLOCK:
Deployment manifest sha256:
Launch operation config sha256:
External dependency existence checked:

Execution set:
| ID | Stage | Scope | Expected | Actual | Artifact path | Notes |
| --- | --- | --- | --- | --- | --- | --- |

Stress scenario set:
| Scenario id | Family | Fork block | Full deploy eligible | Result | Exception owner / reason |
| --- | --- | ---: | --- | --- | --- |

Admin console / Safe artifact matching:
Decoded calldata artifact:
Payload hash match:
Safe target / value match:

Secret hygiene:
Raw RPC URL absent:
AWS secret absent:
Private key absent:
Safe nonce absent:

Go / No-Go:
Exception owner and reason:
```

## 9. How To Read The Result

| Status | 意味                                                                               | Launch 判断                                            |
| ------ | ---------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `pass` | deploy / handover / launch operation / stress checks が期待通り通った              | 他 gate も pass なら Go 可能                           |
| `warn` | 対象限定の historical block、外部依存未存在、gas 未取得など、追加判断が必要        | mainnet evidence では原則 No-Go。明示 exception が必要 |
| `fail` | expected status mismatch、secret leak、Safe nonce 混入、required evidence 不足など | No-Go                                                  |

詳細 log は internal artifact として残してよいが、business / public summary には raw calldata、
secret、private endpoint を含めない。
