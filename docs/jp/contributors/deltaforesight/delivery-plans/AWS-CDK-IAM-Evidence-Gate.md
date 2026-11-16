# AWS CDK / IAM Evidence Gate

Updated: 2026-06-25

この runbook は AWS CDK で JPYdf の frontend / ops / admin / worker hosting を
構築する PR と、本番 deploy 前の IAM / KMS / S3 / CloudFront / ECS evidence を
定義する。設計方針は
[AWS-CDK-Hosting-Plan.md](../../../engineering/plans/AWS-CDK-Hosting-Plan.md) を正とし、この文書は
「どの証跡が無ければ ready / launch できないか」を固定する。

## 1. Scope

対象:

- `infra/cdk` の CDK app、stack、construct、config、test。
- user app / ops / public stats / admin console の hosting IAM。
- stats publisher、ops worker、liquidator、route-interest worker の task role。
- mainnet fork stress CodeBuild gate と GitHub Actions OIDC dispatch role。
- GitHub Actions OIDC deploy role / release evidence upload role。
- KMS key policy、S3 bucket policy、CloudFront OAC、CloudWatch Logs / ECR /
  Secrets Manager encryption。

対象外:

- AWS access key / secret access key の共有。operator credential はこの証跡に
  記録しない。
- production account id、private RPC URL、signer secret、OIDC client secret の
  raw value。
- 手動 console screenshot だけでの IAM 承認。CDK synth / diff / assertion で
  機械的に確認できる証跡を優先する。

## 2. Ready Gate For CDK PRs

CDK / IAM を実装する PR は、ready 化前に以下を満たす。

| Gate | Requirement | Evidence |
| --- | --- | --- |
| CDK synth | staging / production config の synth が成功する。 | `cdk synth` command、template artifact hash |
| CDK diff | expected resource changes だけである。IAM broadening は明示レビューする。 | `cdk diff` output summary |
| Static assertions | S3 public access block、OAC、KMS、IAM resource scope、Secrets attachment を unit test で assert する。 | CDK assertion test logs |
| cdk-nag / policy lint | AwsSolutions 相当の guard を走らせ、suppress は理由付きにする。現行 CDK package では `pnpm -C infra/cdk check:policy-lint` で synthesized template の IAM / S3 / KMS / OIDC boundary を検査する。 | nag report または `check:policy-lint` output、suppress justification |
| No long-lived AWS keys | CI deploy は GitHub Actions OIDC を使う。repository secret に AWS access key を置かない。 | OIDC role trust policy、GitHub environment |
| Least privilege | worker role / deploy role は必要 resource に限定する。`Resource: "*"` は理由と境界を持つ。 | IAM policy summary |
| Redaction | evidence は account id 以外の secret-bearing fields を redact する。 | redaction checklist |

## 3. Required IAM / KMS Assertions

### S3 / CloudFront

- user app / ops / stats bucket は Block Public Access を全有効化する。
- S3 website endpoint は使わず、CloudFront OAC からの regular S3 origin に限定する。
- bucket policy は CloudFront service principal を `AWS:SourceArn` で distribution
  ARN に縛る。
- production static site distributions は official user app / ops / stats hostname
  を CloudFront alias として持ち、同一 AWS account の `us-east-1` ACM certificate
  ARN を viewer certificate に使う。
- production static site distributions は CloudFront scope の WAFv2 WebACL ARN を
  attach する。WebACL は同一 AWS account の `us-east-1` global resource とし、
  WAF managed rules / rate limit / geo policy の中身は別 evidence に残す。
- stats bucket writer role は stable stats key と versioned prefix だけに
  `s3:PutObject` / `s3:GetObject` を持つ。bucket 全体 write は不可。
- stats stable key の CDN TTL は documented stale threshold 以下にする。
- public stats stable object は `Content-Type: application/json`、short
  `Cache-Control`、schema / block metadata を持つ。

### KMS

- production / staging は別 customer managed KMS key を使う。
- S3、Secrets Manager、CloudWatch Logs、ECR、EFS は production で KMS encryption を
  有効化する。
- CloudFront + SSE-KMS の場合、KMS key policy 側にも CloudFront service principal
  と account-scoped SourceArn 条件を入れる。CDK 同一 stack 内で bucket encryption key
  と distribution exact ARN を直接相互参照すると CloudFormation dependency cycle を
  作るため、初期実装では KMS policy を `arn:aws:cloudfront::<account>:distribution/*`
  に縛り、S3 bucket policy 側で distribution exact ARN を
  強制する。post-deploy narrowing を採用する場合は、distribution ID 固定後に KMS
  policy を exact ARN へ狭める変更を別 evidence として残す。
- stats publisher は production mode で `OPS_STATS_S3_SSE=aws:kms` を要求する。
- bucket policy または CDK assertion で non-KMS PUT を拒否する。

### ECS / Workers

- dry-run liquidator task definition には signer secret を attach しない。
- live liquidator と `route-interest` は別 secret、別 task role、別 deploy gate にする。
- task role は対象 Secrets Manager ARN と対象 KMS key だけを decrypt できる。
- private monitor task は RPC secret だけを受け取り、state object の
  `s3:GetObject`、state / status object の `s3:PutObject`、専用 CMK の
  Encrypt / Decrypt / GenerateDataKey 以外の bucket 権限を持たない。
- production では `PrivateMonitorScheduleExpression=rate(1 minute)`、
  schedule / script / source-unavailable / P0 / P1 の各 alarm、SNS action、
  CloudWatch log retention を CDK outputs と AWS 実状態で確認する。
- 正常 cycle、RPC 取得失敗、既存 active alert 保持、並行 state PUT 競合を drill し、
  status object、worker log、alarm state、SNS receipt を同一時刻帯で保存する。
- task role に `iam:*`、broad `secretsmanager:*`、unbounded `s3:*` を持たせない。
- ECS task metadata は `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` を通常経路にし、
  `AWS_CONTAINER_CREDENTIALS_FULL_URI` を使う場合は明示 opt-in と理由を残す。

### Admin Console

- admin console は public S3-only hosting にしない。
- ALB auth / OIDC / Cognito の auth wall と MFA group を証跡化する。
- `/private-monitor/status.json` の listener rule にも default console route と同じ
  OIDC action があり、認証前に Lambda target へ forward されないことを確認する。
- private monitor bucket は public stats bucket と分離し、Block Public Access、
  versioning、専用 CMK、SSL-only、retain が有効であることを確認する。
- reader Lambda の IAM は `private-monitor/status.json` の `s3:GetObject` と専用
  CMK の `kms:Decrypt` だけを持ち、`private-monitor/state.json`、`s3:ListBucket`、
  `s3:PutObject` を持たないことを確認する。
- 認証済み `GET /private-monitor/status.json` が `private, no-store` で 200、
  未認証 request が OIDC redirect、status 未生成・不正 schema が詳細を漏らさず
  503、生成から 120 秒以上で Admin UI が stale 表示になる証跡を残す。
- CloudFront を ALB の前段に置く場合は authenticated response を cache しない。
- direct ALB access の扱いを固定し、必要なら CloudFront-origin-only 制約を入れる。
- static console container / target group は ALB security group からだけ受ける。

### GitHub Actions OIDC

- deploy role trust policy は `token.actions.githubusercontent.com` を principal にし、
  `aud=sts.amazonaws.com` と repository / branch / environment 条件を持つ。
- deploy role の permissions は標準 CDK bootstrap
  `deploy` / `file-publishing` / `image-publishing` / `lookup` role への
  `sts:AssumeRole` だけに限定する。deploy role 自体に direct
  CloudFormation / IAM / S3 / KMS / Lambda / CodeBuild / Secrets Manager 権限を
  持たせない。
- production promotion 前に operator は production AWS credentials で
  `pnpm -C infra/cdk check:cdk-bootstrap` を実行し、caller account、bootstrap
  SSM version parameter、`CDKToolkit` stack status、標準 CDK bootstrap
  deploy / file-publishing / image-publishing / lookup role の存在を確認する。
- release evidence upload role は deploy role と分離し、CloudFormation / IAM /
  Secrets Manager / CodeBuild / Lambda 権限を持たせない。
- release evidence upload role trust policy は `aud=sts.amazonaws.com` と
  `repo:<owner>/<repo>:ref:refs/heads/<branch>` または tag subject に限定する。
  wildcard subject は CDK config で拒否する。
- release evidence upload role の permissions は
  `JPYDF_RELEASE_EVIDENCE_UPLOAD_PREFIX` 配下の `s3:PutObject` /
  `s3:AbortMultipartUpload` / `s3:GetObject`、当該 bucket の prefix-limited
  `s3:ListBucket`、および release evidence CMK の encrypt/decrypt/data key に
  限定する。
- static asset publish role は deploy role と分離し、user app / ops bucket への
  SSE-KMS 付き `s3:PutObject` / `s3:DeleteObject` / `s3:ListBucket`、対応 CMK の
  encrypt/data key、StaticSites stack の `cloudformation:DescribeStacks`、user app /
  ops distribution の `cloudfront:CreateInvalidation` / `GetInvalidation` だけを
  持つ。CloudFormation write / IAM / Secrets Manager 権限は持たせない。
- protected production infra deploy は GitHub `production-infra` Environment subject と
  branch restriction に縛る。この Environment は OIDC subject 分離と branch policy の
  軽い境界であり、required reviewers はチーム運用で必要な場合だけ使う。mainnet
  protocol deploy / Safe / Timelock / signer authority の境界として使わない。
- `.github/workflows/cdk-production-promotion.yml` は GitHub `production-infra`
  Environment 上で実行し、`all` / `static-sites` / `cicd` の固定 target だけを
  受ける。`confirm_deploy=deploy-production` が無い実行は diff-only とする。
- production promotion 前に operator は
  `pnpm -C infra/cdk check:github-production` を `gh` 認証済み shell で実行し、
  GitHub `production-infra` Environment の deployment branch policy、repository
  variables、release evidence upload variables が揃っていることを確認する。この check
  は Environment reviewers を既定では要求せず、variable value を出力しない。GitHub Environment には
  できるだけ値を持たせず、非 secret は repository / organization variables、secret や
  raw RPC / provider endpoint は AWS Secrets Manager または SSM に寄せる。
- production promotion workflow は AWS assume 前に
  `pnpm -C infra/cdk check:production-promotion` を通し、repo variables / OIDC
  provider / CDK deploy role / domain / ACM / WAF / subject / prefix /
  release evidence bucket / KMS key の整合を検査する。
- production promotion workflow は diff / outputs artifact 検査後に
  `pnpm -C infra/cdk generate:promotion-release-evidence` で
  `release-evidence.generated.json` を生成し、
  `pnpm -C infra/cdk check:release-evidence` と
  `pnpm -C infra/cdk check:promotion-artifact` で検査して promotion artifact に残す。
  CDK / static asset の release evidence は `environment=production` と
  `operationScope=production-infra` を持ち、release id / S3 prefix は
  `production-infra/<date>/...` にする。Ethereum mainnet protocol deploy /
  governance evidence と同じ path / scope に置かない。
  `cloudfront-invalidations.json` は CDK promotion では空配列でもよいが、static
  asset release では CloudFront invalidation id / distribution id / paths / status
  を記録して同じ release evidence draft に取り込む。
- `.github/workflows/static-assets-production-publish.yml` は GitHub `production-infra`
  Environment と `confirm_publish=publish-static-assets-production` を要求し、
  frontend hosting env guard、S3 SSE-KMS sync、CloudFront invalidation 完了待ち、
  `cloudfront-invalidations.json` artifact を実行する。publish 後に
  `pnpm -C infra/cdk generate:static-assets-release-evidence` と
  `pnpm -C infra/cdk check:release-evidence` を通し、公開した静的 artifact
  directory hash / StaticSites outputs hash / CloudFront invalidation hash を含む
  `release-evidence.generated.json` draft と
  `static-asset-manifest.generated.json` を同じ artifact に残す。さらに
  `pnpm -C infra/cdk check:static-assets-artifact -- --artifact-dir /tmp` で
  outputs / invalidation / manifest / release evidence の相互整合を replay-check
  する。この draft は raw RPC URL / subgraph URL を含めず、operator review 後に
  `.github/workflows/release-evidence-upload.yml` で final JSON として upload する。
- repository secrets に AWS access key / secret access key を置かない。
- CI が出力する evidence は raw RPC URL、AWS secret、signer key を含まない。

### Mainnet Fork Stress Gate

- fork stress dispatch role は deploy role と分離し、CloudFormation / IAM / S3 bucket
  管理 / Secrets Manager 書き込み権限を持たせない。
- dispatch role trust policy は `aud=sts.amazonaws.com` と
  `repo:<owner>/<repo>:...` subject 条件を持つ。
- dispatch role の permissions は fork stress dispatcher Lambda の
  `lambda:InvokeFunction` と当該 project build の `codebuild:BatchGetBuilds` に限定する。
- `codebuild:StartBuild` は dispatcher Lambda execution role にだけ持たせる。
  dispatcher は `FORK_BLOCK` / scenario id / optional launch config のみを受け、
  source / buildspec / image / artifact / secret env override は受けない。
- CodeBuild project は archive RPC URL を Secrets Manager env
  `MAINNET_RPC_URL` として読む。raw URL を GitHub secret に置かない。
- frozen deploy / handover env は Secrets Manager env `DF_DEPLOY_ENV_FILE` として渡し、
  buildspec は shell として source せず literal `KEY=value` として `DF_*` /
  `DEPLOYER` / `DEPLOYMENT_MODE` / `SALT` / `GAS_ESTIMATE_MULTIPLIER` だけを
  export する。
- CodeBuild artifact は Block Public Access、versioning、SSE-KMS を持つ S3 bucket に
  保存する。
- release evidence bucket は Block Public Access、versioning、SSE-KMS を持ち、
  `s3:PutObject` は stack CMK を明示した `aws:kms` upload だけを許す。
- release evidence JSON は upload 前に
  `pnpm -C infra/cdk check:release-evidence <file>` を通し、必須 metadata /
  hash / KMS ARN / secret-like field が検査されている。
- `.github/workflows/release-evidence-upload.yml` は release evidence JSON を検査し、
  release evidence upload role を OIDC assume して
  `--sse aws:kms --sse-kms-key-id <ReleaseEvidenceKmsKeyArn>` で upload する。
  CDK promotion artifact 由来の final JSON は `artifact_kind=cdk-promotion` と
  `artifact_dir=<downloaded artifact dir>` を指定し、upload 前に
  `check:promotion-artifact -- --release-evidence <file>` で replay-check する。
  static asset publish artifact 由来の final JSON は `artifact_kind=static-assets` と
  `artifact_dir=<downloaded artifact dir>` を指定し、upload 前に
  `check:static-assets-artifact -- --release-evidence <file>` で replay-check する。
  manual override でも KMS key region は `aws_region`、KMS key account は
  assumed role account と一致していることを workflow 入力段階で検査する。
- fork stress build image は `forge` / `anvil` / `cast` / Git / Node / pnpm を含み、
  production は immutable digest image にする。

## 4. Evidence Template

```
AWS CDK / IAM evidence
Date:
Operator:
PR / commit:
Environment:
AWS account label:
Region:
CDK app path:
CDK synth command:
CDK synth artifact hash:
CDK diff summary:
CDK assertion command:
CDK assertion result:
CDK bootstrap readiness command / result:
GitHub production readiness command / result:
Production promotion readiness command / result:
cdk-nag / policy lint command / result:
S3 buckets:
CloudFront distributions:
KMS aliases:
Stats stable key:
Stats versioned prefix:
Stats stale threshold:
Worker task roles:
Secrets attached to dry-run tasks:
Secrets attached to live tasks:
GitHub OIDC role:
OIDC trust policy conditions:
CDK deploy role:
CDK bootstrap role assumptions:
CDK promotion workflow run:
CDK promotion mode:
Generated release evidence draft / check:
Fork stress CodeBuild project:
Fork stress dispatcher Lambda:
Fork stress dispatch role:
Fork stress evidence bucket / KMS key:
Release evidence bucket / KMS key:
Release evidence upload role:
Release evidence check command / result:
Known suppressions:
Redaction check:
Go / No-Go:
```

## 5. No-Go Conditions

以下が残る場合、CDK PR は ready にしない。本番 deploy も行わない。

- AWS access key / secret access key を GitHub secret、docs、PR body、evidence に
  保存している。
- public app / ops / stats bucket が public bucket policy または public ACL で読める。
- CloudFront OAC、S3 bucket policy の distribution exact `SourceArn`、および KMS
  key policy の account-scoped CloudFront `SourceArn` 制約が無い。
- stats writer role が bucket 全体や unrelated prefix に write できる。
- production stats publish が SSE-KMS なしで成功する。
- dry-run liquidator task に live signer secret が attach されている。
- admin console が認証なしで reachable、または authenticated response が CDN cache
  されうる。
- GitHub deploy role trust policy が repository / branch / environment を縛っていない。
- GitHub deploy role が標準 CDK bootstrap role assume 以外の direct deploy 権限を
  持つ。
- release evidence upload role が deploy 権限、bucket 全体 write、`s3:*`、
  `Resource: "*"`、または release evidence CMK 以外の KMS broad write を持つ。
- fork stress dispatch role が deploy 権限、broad `codebuild:*`、unbounded
  Secrets Manager / S3 権限を持つ。
- CDK assertion / `pnpm -C infra/cdk check:policy-lint` が未実行、または suppress
  理由が無い。

## 6. Current Implementation Boundary

`infra/cdk` の現在の実装境界は、static hosting / public stats storage、hosted Anvil
staging RPC、backend workers、mainnet fork stress CodeBuild gate である。以下は
assertion / synth で確認する。

- user app / ops / stats bucket が Block Public Access、SSE-KMS、versioning、
  bucket-owner enforced ownership を持つこと。
- CloudFront OAC が S3 origin に使われ、S3 bucket policy が distribution exact
  `SourceArn` で read access を制限すること。
- KMS key policy が CloudFront service principal を account-scoped SourceArn で
  制限し、CloudFront 側の KMS action は `kms:Decrypt` / `kms:GenerateDataKey*`
  に限定すること。`kms:Encrypt` は stats publisher など write path 側だけに
  付与する。
- stats stable key の CloudFront max TTL が stale threshold 以下であり、
  `versions/*` は長期 cache behavior を持つこと。
- stats publisher role の S3 write が stable key と versioned prefix に限定され、
  `s3:*` / `Resource: "*"` を使わないこと。
- stats bucket が non-KMS または stack CMK 以外の `PutObject` を拒否する bucket policy
  を持つこと。
- production backend は `JPYDF_BACKEND_ALARM_TOPIC_ARN` または
  `JPYDF_BACKEND_ALARM_EMAILS` の少なくとも一方を要求し、alarm action topic が無人の
  default topic だけになる構成を拒否すること。
- dry-run `route-interest` / liquidator task definition に signer secret が attach
  されないこと。
- live `route-interest` / liquidator は別 signer secret を要求すること。
- liquidator state は EFS access point + task role 条件付き mount であること。
- fork stress CodeBuild project が Secrets Manager の archive RPC secret と frozen
  deploy env secret を env として受け、artifact を KMS encrypted S3 bucket に出すこと。
- fork stress GitHub OIDC dispatch role が repo/ref subject に縛られ、
  dispatcher `lambda:InvokeFunction` / `codebuild:BatchGetBuilds` に限定されていること。
- dispatcher Lambda execution role だけが対象 CodeBuild project の
  `codebuild:StartBuild` を持ち、GitHub input から source / buildspec / image /
  artifact / secret env override を受けないこと。
- release evidence bucket が non-KMS または stack CMK 以外の `PutObject` を拒否し、
  GitHub OIDC upload role が repo/ref subject、release evidence prefix、release
  evidence CMK に限定されていること。
- `.github/workflows/release-evidence-upload.yml` が upload 前に
  `pnpm -C infra/cdk check:release-evidence <file>` を実行し、evidence JSON の
  bucket / KMS key / prefix が repo variables と一致し、KMS key region / account
  が upload 実行環境と一致することを確認すること。
- CDK deploy role が GitHub `production-infra` Environment subject に縛られ、標準 CDK
  bootstrap role ARN への `sts:AssumeRole` だけを持つこと。
- `pnpm -C infra/cdk check:cdk-bootstrap` が PASS し、production account の
  `CDKToolkit`、bootstrap version parameter、標準 CDK bootstrap role が揃っていること。
- `.github/workflows/cdk-production-promotion.yml` が GitHub `production-infra`
  Environment subject、OIDC assume、CDK build / assertion / synth /
  `check:policy-lint` / diff、固定 stack target、明示
  `confirm_deploy=deploy-production` gate、deploy 後
  `check:production-postdeploy`、`check:promotion-evidence`、
  `generate:promotion-release-evidence`、`check:promotion-artifact`、
  diff / outputs / generated release evidence / stack-list / CloudFront
  invalidation artifact を持つこと。
- `.github/workflows/static-assets-production-publish.yml` が GitHub `production-infra`
  Environment subject、OIDC assume、hosting-env guard、S3 sync の
  `--sse aws:kms --sse-kms-key-id`、CloudFront invalidation 作成 / 完了待ち、
  invalidation artifact upload を持つこと。
- `pnpm -C infra/cdk check:policy-lint` が PASS し、synthesized template に
  broad identity-policy action、未承認 `Resource: "*"`, wildcard GitHub OIDC
  subject、public S3 bucket policy、S3 SSE-KMS / Block Public Access 欠落、
  unsafe CloudFront KMS principal が無いこと。
- `pnpm -C infra/cdk check:promotion-evidence` が PASS し、promotion diff /
  outputs artifact が空でなく、diff-only outputs が `{}`、deploy outputs が対象
  stack を含み、secret-like text / high-risk IAM wildcard allow / unexpected
  stack output を含まないこと。
- deploy 実行時は `pnpm -C infra/cdk check:production-postdeploy` が PASS し、
  CloudFormation stack status / outputs、CDK deploy role trust / inline policy、
  CloudFront alias / certificate / WebACL / OAC、S3 public access block /
  SSE-KMS / versioning / bucket policy、release evidence bucket CMK binding が
  AWS 実状態で確認されていること。
- `pnpm -C infra/cdk check:github-production` が PASS し、GitHub
  `production-infra` Environment branch restrictions、production
  promotion repo variables、release evidence upload repo variables が揃っていること。
- `pnpm -C infra/cdk check:production-promotion` が PASS し、first-run evidence は
  `infra/cdk/templates/production-promotion-first-run-evidence.md` を使って
  explicit confirmation / diff / outputs / stack list / CloudFront invalidation evidence /
  generated release evidence draft / release evidence object version /
  KMS evidence を記録すること。

以下はまだ未実装 / 未検証であり、production-ready と扱わない。

- Production deploy / production `cdk diff` evidence。Staging static-sites stack の
  bootstrap / deploy / no-diff evidence は
  [2026-06-22-Staging-Frontend-Hosting-Smoke-Review.md](../../../engineering/historical-reviews/2026-06-22-Staging-Frontend-Hosting-Smoke-Review.md)
  に記録済みだが、production-ready の代替ではない。
- 実 production account での GitHub Actions production promotion workflow 実行証跡
  と GitHub `production-infra` Environment subject / branch policy 証跡。
- admin console ALB auth / no-cache / noindex stack。
- Route 53 record creation、ACM certificate issuance / renewal evidence、WAF rule
  evidence、observability。
