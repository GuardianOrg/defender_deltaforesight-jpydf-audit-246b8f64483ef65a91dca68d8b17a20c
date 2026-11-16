# AWS CDK / IAM Evidence Gate

Updated: 2026-06-25

This runbook defines the PRs that build the JPY DeFi frontend / ops / admin / worker hosting
with AWS CDK, and the IAM / KMS / S3 / CloudFront / ECS evidence required before
a production deploy. The design policy takes
[AWS-CDK-Hosting-Plan.md](../../../engineering/plans/AWS-CDK-Hosting-Plan.md) as authoritative, and this document
fixes "which evidence, if missing, blocks ready / launch."

## 1. Scope

In scope:

- The CDK app, stack, construct, config, and test under `infra/cdk`.
- Hosting IAM for the user app / ops / public stats / admin console.
- The task roles of the stats publisher, ops worker, liquidator, and route-interest worker.
- The mainnet fork stress CodeBuild gate and the GitHub Actions OIDC dispatch role.
- The GitHub Actions OIDC deploy role / release evidence upload role.
- KMS key policy, S3 bucket policy, CloudFront OAC, CloudWatch Logs / ECR /
  Secrets Manager encryption.

Out of scope:

- Sharing of the AWS access key / secret access key. Operator credentials are not
  recorded in this evidence.
- The raw values of the production account id, private RPC URL, signer secret, and
  OIDC client secret.
- IAM approval based on manual console screenshots alone. Prefer evidence that can be
  confirmed mechanically with CDK synth / diff / assertion.

## 2. Ready Gate For CDK PRs

A PR that implements CDK / IAM satisfies the following before being made ready.

| Gate | Requirement | Evidence |
| --- | --- | --- |
| CDK synth | The synth of the staging / production config succeeds. | `cdk synth` command, template artifact hash |
| CDK diff | Only the expected resource changes. IAM broadening is explicitly reviewed. | `cdk diff` output summary |
| Static assertions | Assert the S3 public access block, OAC, KMS, IAM resource scope, and Secrets attachment in unit tests. | CDK assertion test logs |
| cdk-nag / policy lint | Run guards equivalent to AwsSolutions, and make suppressions justified. In the current CDK package, `pnpm -C infra/cdk check:policy-lint` inspects the IAM / S3 / KMS / OIDC boundary of the synthesized template. | nag report or `check:policy-lint` output, suppress justification |
| No long-lived AWS keys | CI deploy uses GitHub Actions OIDC. Do not place an AWS access key in repository secrets. | OIDC role trust policy, GitHub environment |
| Least privilege | The worker role / deploy role is limited to the necessary resources. `Resource: "*"` has a reason and a boundary. | IAM policy summary |
| Redaction | Evidence redacts secret-bearing fields other than the account id. | redaction checklist |

## 3. Required IAM / KMS Assertions

### S3 / CloudFront

- The user app / ops / stats bucket fully enables Block Public Access.
- Do not use the S3 website endpoint; limit to a regular S3 origin from CloudFront OAC.
- The bucket policy binds the CloudFront service principal to the distribution
  ARN via `AWS:SourceArn`.
- Production static site distributions hold the official user app / ops / stats hostname
  as a CloudFront alias, and use the `us-east-1` ACM certificate ARN of the same AWS
  account as the viewer certificate.
- Production static site distributions attach a CloudFront-scoped WAFv2 WebACL ARN.
  The WebACL is a `us-east-1` global resource of the same AWS account, and the
  content of the WAF managed rules / rate limit / geo policy is left in separate evidence.
- The stats bucket writer role has `s3:PutObject` / `s3:GetObject` only for the stable
  stats key and the versioned prefix. Whole-bucket write is not allowed.
- The CDN TTL of the stats stable key is at or below the documented stale threshold.
- The public stats stable object has `Content-Type: application/json`, a short
  `Cache-Control`, and schema / block metadata.

### KMS

- Production / staging use separate customer managed KMS keys.
- S3, Secrets Manager, CloudWatch Logs, ECR, and EFS enable KMS encryption in production.
- For CloudFront + SSE-KMS, the KMS key policy side also includes the CloudFront service
  principal and an account-scoped SourceArn condition. Directly cross-referencing the bucket
  encryption key and the distribution exact ARN within the same CDK stack creates a
  CloudFormation dependency cycle, so in the initial implementation the KMS policy is bound to
  `arn:aws:cloudfront::<account>:distribution/*` and the S3 bucket policy side enforces the
  distribution exact ARN. When adopting post-deploy narrowing, leave the change that narrows the
  KMS policy to the exact ARN after fixing the distribution ID as separate evidence.
- The stats publisher requires `OPS_STATS_S3_SSE=aws:kms` in production mode.
- The bucket policy or a CDK assertion rejects a non-KMS PUT.

### ECS / Workers

- Do not attach a signer secret to the dry-run liquidator task definition.
- Make the live liquidator and `route-interest` use separate secrets, separate task roles, and separate deploy gates.
- The task role can decrypt only the target Secrets Manager ARN and the target KMS key.
- Do not give the task role `iam:*`, broad `secretsmanager:*`, or unbounded `s3:*`.
- Make the ECS task metadata use `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` as the normal path,
  and when using `AWS_CONTAINER_CREDENTIALS_FULL_URI`, leave an explicit opt-in and reason.

### Admin Console

- Do not make the admin console public S3-only hosting.
- Evidence the ALB auth / OIDC / Cognito auth wall and MFA group.
- When placing CloudFront in front of the ALB, do not cache the authenticated response.
- Fix the handling of direct ALB access, and add a CloudFront-origin-only constraint if necessary.
- The static console container / target group receives only from the ALB security group.

### GitHub Actions OIDC

- The deploy role trust policy makes `token.actions.githubusercontent.com` the principal, and
  has the `aud=sts.amazonaws.com` and repository / branch / environment conditions.
- The deploy role's permissions are limited to `sts:AssumeRole` only to the standard CDK bootstrap
  `deploy` / `file-publishing` / `image-publishing` / `lookup` roles. Do not give the deploy role
  itself direct CloudFormation / IAM / S3 / KMS / Lambda / CodeBuild / Secrets Manager permissions.
- Before production promotion, the operator runs `pnpm -C infra/cdk check:cdk-bootstrap`
  with production AWS credentials and confirms the caller account, the bootstrap
  SSM version parameter, the `CDKToolkit` stack status, and the existence of the standard CDK bootstrap
  deploy / file-publishing / image-publishing / lookup roles.
- Separate the release evidence upload role from the deploy role, and do not give it
  CloudFormation / IAM / Secrets Manager / CodeBuild / Lambda permissions.
- The release evidence upload role trust policy is limited to `aud=sts.amazonaws.com` and
  the `repo:<owner>/<repo>:ref:refs/heads/<branch>` or tag subject.
  A wildcard subject is rejected in the CDK config.
- The release evidence upload role's permissions are limited to `s3:PutObject` /
  `s3:AbortMultipartUpload` / `s3:GetObject` under `JPYDF_RELEASE_EVIDENCE_UPLOAD_PREFIX`,
  the prefix-limited `s3:ListBucket` of that bucket, and the encrypt/decrypt/data key of the
  release evidence CMK.
- Separate the static asset publish role from the deploy role, and give it only SSE-KMS
  `s3:PutObject` / `s3:DeleteObject` / `s3:ListBucket` to the user app / ops bucket, the
  encrypt/data key of the corresponding CMK, the `cloudformation:DescribeStacks` of the
  StaticSites stack, and the `cloudfront:CreateInvalidation` / `GetInvalidation` of the user app /
  ops distribution. Do not give it CloudFormation write / IAM / Secrets Manager permissions.
- Bind the protected production infra deploy to the GitHub `production-infra` Environment subject and
  branch restriction. This Environment is a light boundary of OIDC subject separation and branch policy,
  and required reviewers are used only when needed in team operations. Do not use it as the boundary of
  the mainnet protocol deploy / Safe / Timelock / signer authority.
- `.github/workflows/cdk-production-promotion.yml` runs on the GitHub `production-infra`
  Environment and accepts only the fixed targets `all` / `static-sites` / `cicd`. A run without
  `confirm_deploy=deploy-production` is diff-only.
- Before production promotion, the operator runs
  `pnpm -C infra/cdk check:github-production` in a `gh`-authenticated shell and confirms that the
  deployment branch policy, repository variables, and release evidence upload variables of the
  GitHub `production-infra` Environment are in place. This check
  does not require Environment reviewers by default, and does not output variable values. Keep values
  on the GitHub Environment to a minimum: non-secrets go to repository / organization variables, and
  secrets and the raw RPC / provider endpoint go to AWS Secrets Manager or SSM.
- The production promotion workflow passes
  `pnpm -C infra/cdk check:production-promotion` before AWS assume, inspecting the consistency of
  repo variables / OIDC provider / CDK deploy role / domain / ACM / WAF / subject / prefix /
  release evidence bucket / KMS key.
- After inspecting the diff / outputs artifact, the production promotion workflow generates
  `release-evidence.generated.json` with
  `pnpm -C infra/cdk generate:promotion-release-evidence`, inspects it with
  `pnpm -C infra/cdk check:release-evidence` and
  `pnpm -C infra/cdk check:promotion-artifact`, and leaves it in the promotion artifact.
  The CDK / static asset release evidence has `environment=production` and
  `operationScope=production-infra`, and the release id / S3 prefix is
  `production-infra/<date>/...`. Do not place it on the same path / scope as the
  Ethereum mainnet protocol deploy / governance evidence.
  `cloudfront-invalidations.json` may be an empty array in a CDK promotion, but for a static
  asset release it records the CloudFront invalidation id / distribution id / paths / status
  and incorporates them into the same release evidence draft.
- `.github/workflows/static-assets-production-publish.yml` requires the GitHub `production-infra`
  Environment and `confirm_publish=publish-static-assets-production`, and runs the
  frontend hosting env guard, S3 SSE-KMS sync, CloudFront invalidation completion wait, and the
  `cloudfront-invalidations.json` artifact. After publish, it passes
  `pnpm -C infra/cdk generate:static-assets-release-evidence` and
  `pnpm -C infra/cdk check:release-evidence`, and leaves the
  `release-evidence.generated.json` draft including the published static artifact
  directory hash / StaticSites outputs hash / CloudFront invalidation hash and the
  `static-asset-manifest.generated.json` in the same artifact. It also
  replay-checks the mutual consistency of outputs / invalidation / manifest / release evidence with
  `pnpm -C infra/cdk check:static-assets-artifact -- --artifact-dir /tmp`.
  This draft does not include the raw RPC URL / subgraph URL, and after operator review it is
  uploaded as the final JSON by `.github/workflows/release-evidence-upload.yml`.
- Do not place an AWS access key / secret access key in repository secrets.
- The evidence that CI outputs does not include the raw RPC URL, AWS secret, or signer key.

### Mainnet Fork Stress Gate

- Separate the fork stress dispatch role from the deploy role, and do not give it CloudFormation / IAM / S3 bucket
  management / Secrets Manager write permissions.
- The dispatch role trust policy has the `aud=sts.amazonaws.com` and
  `repo:<owner>/<repo>:...` subject conditions.
- The dispatch role's permissions are limited to the `lambda:InvokeFunction` of the fork stress dispatcher Lambda
  and the `codebuild:BatchGetBuilds` of that project build.
- Give `codebuild:StartBuild` only to the dispatcher Lambda execution role.
  The dispatcher receives only `FORK_BLOCK` / scenario id / an optional launch config, and does not receive
  source / buildspec / image / artifact / secret env overrides.
- The CodeBuild project reads the archive RPC URL as the Secrets Manager env
  `MAINNET_RPC_URL`. Do not place the raw URL in a GitHub secret.
- The frozen deploy / handover env is passed as the Secrets Manager env `DF_DEPLOY_ENV_FILE`, and
  the buildspec does not source it as a shell but exports only `DF_*` /
  `DEPLOYER` / `DEPLOYMENT_MODE` / `SALT` / `GAS_ESTIMATE_MULTIPLIER` as literal `KEY=value`.
- CodeBuild artifacts are stored in an S3 bucket that has Block Public Access, versioning, and SSE-KMS.
- The release evidence bucket has Block Public Access, versioning, and SSE-KMS, and
  `s3:PutObject` allows only an `aws:kms` upload that explicitly specifies the stack CMK.
- Before upload, the release evidence JSON passes
  `pnpm -C infra/cdk check:release-evidence <file>`, where the required metadata /
  hash / KMS ARN / secret-like fields are inspected.
- `.github/workflows/release-evidence-upload.yml` inspects the release evidence JSON,
  OIDC-assumes the release evidence upload role, and uploads it with
  `--sse aws:kms --sse-kms-key-id <ReleaseEvidenceKmsKeyArn>`.
  The final JSON derived from the CDK promotion artifact specifies `artifact_kind=cdk-promotion` and
  `artifact_dir=<downloaded artifact dir>`, and before upload it
  replay-checks with `check:promotion-artifact -- --release-evidence <file>`.
  The final JSON derived from the static asset publish artifact specifies `artifact_kind=static-assets` and
  `artifact_dir=<downloaded artifact dir>`, and before upload it
  replay-checks with `check:static-assets-artifact -- --release-evidence <file>`.
  Even on a manual override, the workflow input stage confirms that the KMS key region matches
  `aws_region` and that the KMS key account matches the assumed role account.
- The fork stress build image includes `forge` / `anvil` / `cast` / Git / Node / pnpm, and
  production uses an immutable digest image.

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

If the following remain, do not make the CDK PR ready. Do not perform the production deploy either.

- The AWS access key / secret access key is stored in a GitHub secret, docs, PR body, or evidence.
- The public app / ops / stats bucket is readable via a public bucket policy or public ACL.
- The CloudFront OAC, the distribution exact `SourceArn` of the S3 bucket policy, and the
  account-scoped CloudFront `SourceArn` constraint of the KMS key policy are missing.
- The stats writer role can write to the whole bucket or an unrelated prefix.
- The production stats publish succeeds without SSE-KMS.
- A live signer secret is attached to the dry-run liquidator task.
- The admin console is reachable without authentication, or the authenticated response can be CDN-cached.
- The GitHub deploy role trust policy does not bind the repository / branch / environment.
- The GitHub deploy role has direct deploy permissions other than the standard CDK bootstrap role assume.
- The release evidence upload role has deploy permissions, whole-bucket write, `s3:*`,
  `Resource: "*"`, or broad KMS write to a KMS other than the release evidence CMK.
- The fork stress dispatch role has deploy permissions, broad `codebuild:*`, or unbounded
  Secrets Manager / S3 permissions.
- The CDK assertion / `pnpm -C infra/cdk check:policy-lint` was not run, or a suppression
  has no reason.

## 6. Current Implementation Boundary

The current implementation boundary of `infra/cdk` is static hosting / public stats storage, hosted Anvil
staging RPC, backend workers, and the mainnet fork stress CodeBuild gate. The following are confirmed
with assertion / synth.

- That the user app / ops / stats bucket has Block Public Access, SSE-KMS, versioning, and
  bucket-owner enforced ownership.
- That CloudFront OAC is used for the S3 origin, and the S3 bucket policy limits read access
  with the distribution exact `SourceArn`.
- That the KMS key policy limits the CloudFront service principal with an account-scoped SourceArn,
  and the CloudFront-side KMS action is limited to `kms:Decrypt` / `kms:GenerateDataKey*`.
  `kms:Encrypt` is granted only to the write-path side such as the stats publisher.
- That the CloudFront max TTL of the stats stable key is at or below the stale threshold, and
  `versions/*` has long-term cache behavior.
- That the S3 write of the stats publisher role is limited to the stable key and the versioned prefix, and
  does not use `s3:*` / `Resource: "*"`.
- That the stats bucket has a bucket policy that rejects non-KMS or non-stack-CMK `PutObject`.
- That the production backend requires at least one of `JPYDF_BACKEND_ALARM_TOPIC_ARN` or
  `JPYDF_BACKEND_ALARM_EMAILS`, and rejects a configuration in which the alarm action topic is
  only an unattended default topic.
- That no signer secret is attached to the dry-run `route-interest` / liquidator task definition.
- That the live `route-interest` / liquidator requires a separate signer secret.
- That the liquidator state is an EFS access point + a task-role-conditioned mount.
- That the fork stress CodeBuild project receives the Secrets Manager archive RPC secret and the frozen
  deploy env secret as env, and outputs the artifact to a KMS encrypted S3 bucket.
- That the fork stress GitHub OIDC dispatch role is bound to a repo/ref subject, and is
  limited to the dispatcher `lambda:InvokeFunction` / `codebuild:BatchGetBuilds`.
- That only the dispatcher Lambda execution role has the `codebuild:StartBuild` of the target CodeBuild
  project, and does not receive source / buildspec / image / artifact / secret env overrides from
  GitHub input.
- That the release evidence bucket rejects non-KMS or non-stack-CMK `PutObject`, and the
  GitHub OIDC upload role is limited to a repo/ref subject, the release evidence prefix, and the release
  evidence CMK.
- That `.github/workflows/release-evidence-upload.yml` runs
  `pnpm -C infra/cdk check:release-evidence <file>` before upload, confirming that the
  bucket / KMS key / prefix of the evidence JSON match the repo variables, and that the KMS key region / account
  match the upload execution environment.
- That the CDK deploy role is bound to the GitHub `production-infra` Environment subject, and has only
  `sts:AssumeRole` to the standard CDK bootstrap role ARN.
- That `pnpm -C infra/cdk check:cdk-bootstrap` PASSes, and the production account's
  `CDKToolkit`, bootstrap version parameter, and standard CDK bootstrap roles are in place.
- That `.github/workflows/cdk-production-promotion.yml` has the GitHub `production-infra`
  Environment subject, OIDC assume, CDK build / assertion / synth /
  `check:policy-lint` / diff, fixed stack targets, the explicit
  `confirm_deploy=deploy-production` gate, the post-deploy
  `check:production-postdeploy`, `check:promotion-evidence`,
  `generate:promotion-release-evidence`, `check:promotion-artifact`, and the
  diff / outputs / generated release evidence / stack-list / CloudFront
  invalidation artifact.
- That `.github/workflows/static-assets-production-publish.yml` has the GitHub `production-infra`
  Environment subject, OIDC assume, hosting-env guard, the S3 sync
  `--sse aws:kms --sse-kms-key-id`, CloudFront invalidation creation / completion wait, and the
  invalidation artifact upload.
- That `pnpm -C infra/cdk check:policy-lint` PASSes, and the synthesized template has no
  broad identity-policy action, no unapproved `Resource: "*"`, no wildcard GitHub OIDC
  subject, no public S3 bucket policy, no missing S3 SSE-KMS / Block Public Access, and
  no unsafe CloudFront KMS principal.
- That `pnpm -C infra/cdk check:promotion-evidence` PASSes, and the promotion diff /
  outputs artifact is non-empty, the diff-only outputs are `{}`, the deploy outputs include the target
  stack, and they do not include secret-like text / a high-risk IAM wildcard allow / an unexpected
  stack output.
- That at deploy execution, `pnpm -C infra/cdk check:production-postdeploy` PASSes, and the
  CloudFormation stack status / outputs, CDK deploy role trust / inline policy,
  CloudFront alias / certificate / WebACL / OAC, S3 public access block /
  SSE-KMS / versioning / bucket policy, and release evidence bucket CMK binding are
  confirmed in the actual AWS state.
- That `pnpm -C infra/cdk check:github-production` PASSes, and the GitHub
  `production-infra` Environment branch restrictions, production
  promotion repo variables, and release evidence upload repo variables are in place.
- That `pnpm -C infra/cdk check:production-promotion` PASSes, and the first-run evidence
  uses `infra/cdk/templates/production-promotion-first-run-evidence.md` to record the
  explicit confirmation / diff / outputs / stack list / CloudFront invalidation evidence /
  generated release evidence draft / release evidence object version /
  KMS evidence.

The following are not yet implemented / not yet verified, and are not treated as production-ready.

- Production deploy / production `cdk diff` evidence. The
  bootstrap / deploy / no-diff evidence of the staging static-sites stack is
  recorded in [2026-06-22-Staging-Frontend-Hosting-Smoke-Review.md](../../../engineering/historical-reviews/2026-06-22-Staging-Frontend-Hosting-Smoke-Review.md),
  but it is not a substitute for production-ready.
- GitHub Actions production promotion workflow execution evidence on the actual production account
  and the GitHub `production-infra` Environment subject / branch policy evidence.
- The admin console ALB auth / no-cache / noindex stack.
- Route 53 record creation, ACM certificate issuance / renewal evidence, WAF rule
  evidence, and observability.
