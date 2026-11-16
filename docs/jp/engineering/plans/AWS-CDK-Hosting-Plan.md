# AWS CDK Hosting Plan

この計画は、JPY DeFi の user app、ops dashboard、admin console、public stats
JSON、liquidator / keeper 系 backend を AWS CDK で hosting するための実装方針を
定義する。仕様の正本は各 component spec / runbook に置き、この文書は AWS 上の
配置・責務分離・deploy 順序をまとめる。

関連 source of truth:

- [Frontend.md](../../protocol/product/spec/Frontend.md)
- [Frontend-Production-Delivery-Gate.md](../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md)
- [Admin-Console-Production-Gate.md](../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md)
- [AWS-CDK-IAM-Evidence-Gate.md](../../contributors/deltaforesight/delivery-plans/AWS-CDK-IAM-Evidence-Gate.md)
- [Mainnet-Fork-Stress-Gate.md](../../protocol/launch/gates/Mainnet-Fork-Stress-Gate.md)
- [Frontend-UX-Readiness-Gate.md](../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md)
- [Liquidation-Bot-Plan.md](./Liquidation-Bot-Plan.md)
- [Liquidation-Management-Policy.md](../../protocol/operations/policies/Liquidation-Management-Policy.md)
- [InterestRouterForwarder-Route-Runbook.md](../../protocol/operations/runbooks/InterestRouterForwarder-Route-Runbook.md)

## 1. Scope

Day-1 hosting 対象:

- `frontend/app`: public user app。Next.js static export (`next build` -> `out/`)。
- `frontend/ops`: read-only ops / transparency dashboard。Vite static build
  (`vite build` -> `dist/`)。
- Public stats JSON: `frontend/ops` の `export-stats` が生成する公開健全性 JSON。
- `frontend/console`: restricted admin console。Vite static build だが、public
  static site として直接公開しない。
- Hosted Anvil staging RPC: frontend / ops / deploy script の staging 動作確認用
  chain。testnet ではなく resettable な dev chain として扱い、production と誤認
  させない UI 表示を必須にする。
- `bots/liquidator`: Rust liquidator / keeper。Day-1 は dry-run / read-only
  evidence を先に動かし、live submission は別 gate。
- Future ops workers: `export-treasury-ledger`、`route-interest` などの
  scheduled / manual worker。
- Mainnet fork stress rehearsal: GitHub Actions は OIDC で dispatcher Lambda を
  invoke するだけにし、archive RPC を使った `contracts/utils/mainnet-fork-evidence.sh`
  の実行は CodeBuild 側に閉じる。Safe / role holder calldata、frontend write-flow、
  admin console payload hash、historical / synthetic stress scenario の evidence を
  S3 に保存する。

Day-1 hosting 対象外:

- subgraph self-hosting の本番化。Day-1 は managed / hosted endpoint を優先し、
  AWS Graph Node は Day-2 以降の独立計画にする。
- admin console 内での秘密鍵保持、privileged transaction 送信。
- user app 内の mock / fixture / stale 補完。

## 2. Current Repo Facts

| Surface | Build / runtime | Hosting implication |
| --- | --- | --- |
| `frontend/app` | `pnpm --filter @jpydf/app build`。`next.config.js` は `output: "export"`。runtime 値は `NEXT_PUBLIC_*` / generated env から bundle へ入る。 | S3 + CloudFront の private origin で配信できる。secret は置けない。 |
| `frontend/ops` | `pnpm --filter @jpydf/ops build`。read-only dashboard。`export-stats` は RPC から snapshot を読み JSON を出力する。`frontend/df-shared/generated/addresses.ts` の `DEPLOYMENT.rpcUrl` は browser bundle に入る。 | dashboard は static hosting。stats JSON は scheduled worker で生成して S3 へ配置する。browser RPC は秘匿値ではなく制限付き read endpoint として扱う。 |
| `frontend/console` | `pnpm --filter @jpydf/console build`。calldata 作成、contract / role 確認、Safe 手動 import の支援。`DEPLOYMENT.rpcUrl` は authenticated user の browser から見える。 | static asset でも restricted surface。認証なし CloudFront/S3 直公開は禁止。admin browser RPC は user app / Ops と同じ公開 read credential を利用できる。真に秘匿すべき key は backend / worker にだけ置く。 |
| `bots/liquidator` | Rust binary。`scan-once` と `run`。read-only / dry-run は signing key 不要、live は explicit config と key env が必要。 | ECS Fargate worker / service が自然。state.path を永続化する。 |
| `contracts/utils/mainnet-fork-evidence.sh` | pinned mainnet block の Anvil fork 上で deploy / preflight / handover / optional launch-operation evidence を出力する。 | CodeBuild の rehearsal job で実行する。GitHub Actions は OIDC で dispatcher Lambda を invoke するだけにする。archive RPC URL は Secrets Manager / SSM から読む。 |
| `subgraph` | local graph node / deploy scripts。 | self-host は Graph Node / Postgres / IPFS の運用範囲が大きい。Day-1 から抱えない。 |
| `infra/cdk` Hosted Anvil | `Jpydf-staging-HostedAnvil` は explicit opt-in。Anvil container を ECS Fargate で起動し、ALB + CloudFront HTTPS RPC を出す。 | staging のみ。production synth は `JPYDF_HOSTED_ANVIL_ENABLED=true` を拒否する。 |

## 3. Architecture Decision

CDK は Day-1 の標準実装として採用するが、hosting provider そのものを protocol
仕様にしない。build artifact、deployment manifest、stats JSON schema、admin auth
boundary、worker entrypoint を provider-neutral に保ち、将来 Vercel / CloudFront
間の移行、Neon / RDS、Render / ECS、Better Stack / CloudWatch の併用や移行が
できるようにする。

### Public user app

- Route 53 + ACM + CloudFront + private S3 bucket で配信する。
- S3 website endpoint は使わない。CloudFront Origin Access Control (OAC) を使い、
  regular S3 bucket origin を private に保つ。
- CloudFront viewer protocol policy は HTTPS redirect / HTTPS only とする。
- CloudFront response headers policy で HSTS、CSP、`X-Content-Type-Options`、
  `Referrer-Policy` などを管理する。
- WAF web ACL を attach し、managed rules、rate limit、geo / bot policy を
  staging で調整してから production に適用する。
- `NEXT_PUBLIC_*` は公開情報として扱う。RPC URL は secret ではなく、domain
  allowlist / rate cap / rotation owner 付きの public read key として扱う。

### Hosted Anvil staging RPC

- `Jpydf-staging-HostedAnvil` は AWS 上の resettable dev chain として扱う。default
  chainId は `31338` とし、local Anvil (`31337`) や production / testnet と混同
  しない。
- stack は staging で `JPYDF_HOSTED_ANVIL_ENABLED=true` の明示 opt-in がある時だけ作成する。
  production synth は hosted Anvil opt-in を拒否する。
  default synth は static hosting のみを出し、production でも暗黙に Anvil を作らない。
- runtime は ECS Fargate の Anvil container、public browser endpoint は CloudFront
  HTTPS の `AnvilRpcUrl` CloudFormation output とする。frontend / ops はこの URL を
  staging env に固定し、画面上では staging / dev chain であることを常時表示する。
- ALB DNS は supported endpoint として公開しない。ALB listener は default `403`、
  CloudFront origin verification header がある request だけ Anvil target group に
  forward する。これは routing guard であり auth boundary ではないため、value-bearing
  asset や production secret を置かない。
- faucet / test accounts / reset / redeploy は自由に行える前提にする。reset 後は
  contract manifest、generated frontend env、subgraph / stats evidence を作り直す。
- hosted Anvil は testnet の代替ではなく、mainnet 前 staging UX / deploy / rollback
  drill を高速化するための環境である。external integrator / audit evidence には
  testnet または mainnet fork evidence を別途添付する。

### Ops dashboard / public stats

- ops dashboard は user app と別 hostname / bucket / distribution に分離する。
- public stats JSON は dashboard bundle と分けた S3 prefix または専用 bucket に
  置く。JSON は `generatedAt`、source block、schema version を含める。
- `publish-stats-s3` は EventBridge scheduled ECS Fargate task で実行する。初期 CDK
  実装は `AWS::Events::Rule` を使い、worker entrypoint / env contract は将来
  EventBridge Scheduler へ移しても変えない。
- `export-stats` は stdout / file へ JSON を出す script なので、S3 publish は
  `publish-stats-s3` worker で行う。stable key へ直接 partial write しない。
  versioned key へ生成し、`Content-Type: application/json`、stale threshold 未満の
  `Cache-Control`、schema/version metadata を付ける。stable key は既存 stats の
  `blockNumber` と ETag を読み、`If-Match` / `If-None-Match` 条件付き PUT で
  monotonic に更新する。条件衝突時は再読込し、既存 block が新しい場合は
  `skipped-stale-publish` として終了する。
- 生成 worker は RPC / deployment manifest / generated bindings の hash をログへ
  出し、失敗時は既存 JSON を mock で上書きしない。
- stats publish は `--sse aws:kms` だけでなく CDK stats bucket CMK の
  `--kms-key-id` を明示する。AWS managed `aws/s3` key で書かれた object は
  CloudFront OAC + stack CMK policy では復号できず、user app から 403 になる。
- user app は stats stale / unavailable を live value と同じ見た目で表示しない。
- public ops UI は `VITE_OPS_RPC_PROVIDER_LABEL` などの provider label を表示し、
  production では RPC host / full URL / key fragment / raw provider error /
  stack trace を表示しない。localhost 等の host 表示は dev build に限定する。

### Admin console

- admin console は user app / ops と別 hostname、別 CloudFront / ALB、別 auth / cache
  boundary に分離する。browser 向け read-only RPC は共有してよく、その場合は
  public app / Ops から観測可能な公開 credential として全 domain・合算 quota・rotation
  を管理する。RPC key の秘匿性を admin boundary にしない。
- Day-1 は ALB authentication (Cognito または社内 OIDC IdP) + ECS Fargate
  nginx static container を標準構成にする。CloudFront を前段に置く場合でも、
  ALB auth を迂回できる origin path を作らない。
- admin console の CloudFront 前段は Day-1 optional とし、採用する場合は
  admin 用 distribution / behavior を public app と分離し、authenticated response を
  public cache しない構成に固定する。標準は cache policy を `CachingDisabled`、
  origin request policy を all viewer headers / all cookies / all query strings の
  forward に分けて定義し、ALB auth behavior（少なくとも `/*` と `/oauth2/*`）
  に適用する。ALB auth cookie は shard されうるため cookie 名を限定しない。
  `Cache-Control: private, no-store`、HTTPS 443 end-to-end、unauthenticated /
  expired-session / cross-user cache drill を必須にする。
- CloudFront を admin console 前段に置く場合は、direct ALB access の扱いを
  launch gate で固定する。CloudFront 側の WAF / response headers / logging /
  rate limit / noindex を security boundary として使うなら、ALB は CloudFront
  経由だけを受ける構成にする。実装候補は CloudFront 由来 request のみを許す
  network policy、ALB listener / backend で検証する shared origin header、WAF /
  host header 制約のいずれか、または組み合わせとし、ALB DNS direct hit drill を
  必須にする。
- MFA 必須の IdP group で許可し、shared password のみの gate は不可。
- `X-Robots-Tag: noindex`、HTML noindex、`robots.txt` を併用する。
- console は秘密鍵を保持しない。Safe calldata export、target / value / function /
  args decode、role / owner / manifest / chainId 確認までを担当する。
- ALB が付与する OIDC claims を backend authorization に使う場合は、target 側で
  signer / issuer / audience を検証する。static asset gate としてだけ使う場合も、
  target security group は ALB からの traffic のみに制限する。

### Liquidator / keeper backend

- `bots/liquidator run` は ECS Fargate service として動かす。最初は read-only /
  dry-run config で block polling と evidence emission だけを有効化する。
- `state.path` は EFS に置く。将来、DynamoDB / S3 object lock へ移す場合は state
  schema と restart semantics を別 PR で固定する。
- CDK `BackendStack` は liquidator が出す `starting liquidation catch cycle` log を
  CloudWatch Logs metric filter で `JPYdf/Backend` metric に変換し、2 連続 5分間
  catch cycle が無い場合に `liquidator-catch-cycle-stale` alarm を出す。これは
  ECS task、RPC、chain progress、bot loop の P0 liveness 検知である。alarm の
  `ALARM` / `OK` / `INSUFFICIENT_DATA` action は backend alarm SNS topic へ publish
  する。`JPYDF_BACKEND_ALARM_TOPIC_ARN` がある場合は同一 region の既存 incident
  topic を使い、無い場合は `BackendStack` が topic を作って `BackendAlarmTopicArn`
  として出力する。
- `BackendStack` は scheduled worker の初期 failure alarm も同じ backend alarm SNS
  topic に集約する。stats publisher は EventBridge `FailedInvocations` と
  `publish-stats-s3 failed:` log metric filter / alarm を常に持つ。加えて
  public stats の `healthStatus` が `critical` / `warning` になった場合、
  stats publisher が `source="publish-stats-s3"`, `ok=false`,
  `severity="critical" | "warning"` を持つ構造化 JSON log を CloudWatch Logs
  に出し、JSON metric filter から同じ SNS topic へ alarm する。これにより Ops
  Dashboard の buffer shortfall / buffer target warning などを、画面常時監視なし
  でもメール・ChatOps 側へ届けられる。
  `route-interest` 有効時は EventBridge `FailedInvocations` と
  `route-interest failed:` log metric filter / alarm も作る。これらは `ALARM` / `OK`
  action を backend alarm SNS topic に publish し、missing data は non-breaching と
  して扱う。
  `JPYDF_BACKEND_ALARM_EMAILS` に comma-separated email list を設定した場合、
  `BackendStack` が SNS email subscription も作成する。Email subscription は
  `JPYDF_BACKEND_ENABLED=true` を必須とする。SNS email は受信者が AWS の confirmation
  email を承認するまで通知されない。`pnpm -C infra/cdk check:backend-alerts` は
  CloudFormation output、SNS confirmed subscription、CloudWatch alarm action、
  SNS topic policy の HTTPS-only publish deny、同一 account かつ当該 Backend
  stack の alarm name prefix に限定した CloudWatch publish allow、scheduled
  worker alarm state、liquidator 有効時の ECS steady state をまとめて確認し、
  受信者 confirmation 未完了なら失敗する。少なくとも 1 receiver が confirmed になった
  後は、`JPYDF_BACKEND_ALERT_TEST_CONFIRM=send pnpm -C infra/cdk publish:backend-alert-test`
  で backend alarm SNS topic へ one-off test message を publish し、実際に通知を受け取れる
  ことを evidence に残す。この delivery test は明示 confirm env と confirmed subscription
  が無い限り送信しない。ただし、この direct SNS test が証明するのは topic から receiver
  までの配送だけであり、log metric filter / CloudWatch alarm 経路の証跡にはならない。
  production-ready 判定前に、明確に test incident と識別できる stats health JSON log を使い、
  metric filter 一致、alarm の `ALARM` / `OK` 遷移、同じ receiver での受信までを staging
  で確認し、log stream、alarm history、受信者、受信時刻、resolve 時刻を非 secret evidence
  として残す。
  ChatOps / PagerDuty subscription、escalation policy、dashboard は ObservabilityStack
  または外部 incident tooling 側で別途固定する。
- live submission は Secrets Manager の signing key、KMS、task role、positive
  gas/loss caps、chainId check、receipt timeout alert を満たす時だけ有効にする。
- automatic SP top-up / atomic JIT bundle / collateral disposal は現行 bot scope
  外なので、hosting 計画にも混ぜない。
- `route-interest` は liquidator とは別 worker / 別 secret として扱う。live mode は
  `IRTR_ROUTE_PRIVATE_KEY` を Secrets Manager から live task definition にだけ
  mount し、chainId、全 branch の `interestRouter` 一致、Forwarder `jpydfToken()`、
  expected recipient、正の minimum route amount、pre-send simulation を満たす時だけ
  有効化する。dry-run task definition には signer secret を attach しない。

### Mainnet fork stress rehearsal

- `mainnet-fork-evidence` は CodeBuild project で実行する。GitHub Actions は
  OIDC 経由の AWS role で dispatcher Lambda を invoke するだけにする。operator
  local output だけを production evidence にしない。
- CDK backend stack は `JPYDF_FORK_STRESS_ENABLED=true` の時だけ
  `ForkStressGateProjectName`、`ForkStressDispatcherFunctionName`、
  `ForkStressGithubDispatchRoleArn`、`ForkStressEvidenceBucketName` を作る。
  default synth / deploy では作らない。
- GitHub Actions は CodeBuild `source-version` を渡さない。dispatcher Lambda が
  `FORK_BLOCK` / scenario id / optional launch config だけを検証し、固定 source ref
  の CodeBuild project を source / buildspec / image / artifact / secret env override
  なしで起動する。manual input で任意 ref / branch / commit を secret 付き CodeBuild
  に実行させない。
- CodeBuild の標準 buildspec は `infra/cdk/buildspecs/mainnet-fork-stress-gate.yml`
  とし、GitHub Actions の手動入口は `.github/workflows/mainnet-fork-stress-gate.yml`
  とする。
- `MAINNET_RPC_URL` は archive-capable RPC とし、Secrets Manager / SSM Parameter Store
  に置く。GitHub repository / environment secrets には置かない。
- frozen deploy / handover env は Secrets Manager の `DF_DEPLOY_ENV_FILE` として
  CodeBuild に渡す。buildspec はこれを shell として source せず、literal `KEY=value`
  として `DF_*` / `DEPLOYER` / `DEPLOYMENT_MODE` / `SALT` /
  `GAS_ESTIMATE_MULTIPLIER` だけを export し、private key、raw RPC URL、未公開 Safe
  nonce を持ちうる key 名を拒否する。
- `DEPLOYER` は anvil impersonation 用の公開 address とし、private key を渡さない。
- GitHub OIDC dispatch role は dispatcher `lambda:InvokeFunction` /
  `codebuild:BatchGetBuilds` に限定し、trust policy は production evidence を許可する
  branch / tag pattern に絞る。`codebuild:StartBuild` は dispatcher Lambda execution
  role だけに持たせる。
- evidence artifact は KMS encrypted S3 bucket に保存する。public PR / docs には
  scenario id、fork block、status、payload hash、AWS build id、artifact label、
  secret hygiene summary だけを貼る。
- `JPYDF_FORK_STRESS_BUILD_IMAGE` は `forge` / `anvil` / `cast` / Node / pnpm を
  含む image とする。production は digest image を必須にし、mutable tag を拒否する。
- launch window で実行する Safe / role holder tx は、admin console / Safe artifact の
  decoded calldata と fork rehearsal input hash を照合する。
- historical stress block が Day-1 外部依存の存在前である場合、full deploy rehearsal
  の PASS として扱わない。対象資産 / external protocol の観測、current fork の
  synthetic stress、unit / invariant / targeted fork test で補う。

### Subgraph

- Day-1 は managed / hosted subgraph endpoint を使い、AWS CDK は endpoint URL と
  freshness monitor だけを扱う。
- self-host が必要になった場合は別 stack として Graph Node、RDS Postgres、IPFS /
  EFS、indexer snapshot backup、schema migration、replay plan を設計する。

## 4. Provider Portability

CDK 実装は AWS 上の実体を作るが、以下の境界は provider を跨いで維持する。

| Boundary | AWS Day-1 | Portable alternative | Rule |
| --- | --- | --- | --- |
| User app hosting | S3 private bucket + CloudFront OAC | Vercel, another CloudFront distribution, static hosting with private origin | `frontend/app/out` を immutable artifact とし、hosting 固有 env を build evidence に固定する。 |
| Ops dashboard hosting | S3 + CloudFront | Vercel / Render static / separate CDN | user app と hostname / project / key を分離するルールは provider 変更後も維持する。 |
| Admin console hosting | ALB auth + ECS nginx | Cloudflare Access / Vercel Enterprise auth / Render private service | auth wall、MFA、noindex、user app から非リンク、secret 非保持を hosting provider より優先する。 |
| Public stats storage | S3 + CloudFront | R2 / Vercel Blob / managed object storage | JSON schema、freshness fields、stale behavior を固定し、URL だけ差し替える。 |
| Staging dev RPC | ECS Fargate Anvil + ALB + CloudFront | Render private service / Fly / local tunnel for short drills | production と明確に表示分離し、chainId / manifest / reset evidence を release ごとに固定する。 |
| Worker runtime | ECS Fargate scheduled task/service | Render worker / Fly / Kubernetes / GitHub Actions for low-frequency jobs | entrypoint と env contract を stable にし、stateful keeper は restart / state semantics を別途証跡化する。 |
| Worker state | EFS, later DynamoDB/S3 | Neon / Postgres / Redis / managed durable storage | liquidator cursor / idempotency key / replay behavior を schema として固定する。 |
| Fork stress rehearsal | GitHub OIDC dispatch + CodeBuild + archive RPC + Foundry / Anvil + S3 evidence | Self-hosted runner / ECS task / another CI with archive RPC | output schema と payload hash matching を stable にし、RPC secret を evidence に出さない。 |
| Relational DB | RDS only if needed | Neon Postgres | Day-1 に DB を増やさない。必要になったら schema migration、backup、restore drill、RLS / network policy を先に定義する。 |
| Observability | CloudWatch, Synthetics, SNS | Better Stack, Datadog, Grafana Cloud | alert names、SLO、runbook links、redaction policy を tool-neutral に保つ。 |
| DNS / TLS | Route 53 + ACM | Cloudflare / external registrar | official URL table、registrar lock、owner、break-glass は provider と独立に記録する。 |

Migration-ready requirements:

- Build outputは provider 固有 API に依存しない immutable artifact として保存する。
- Runtime config は generated env / manifest hash / URL table で表現し、CDK construct
  内に protocol address を直書きしない。
- Public stats JSON は consumer contract を schema version で管理し、storage provider
  変更時も user app の stale / unavailable behavior を変えない。
- Worker は `command + env + secret refs + state backend` の contract を文書化し、
  ECS 固有イベントに business logic を置かない。
- Observability は CloudWatch metrics 名だけに閉じず、Better Stack など外部 monitor
  にも同じ synthetic checks を再現できる名前と expected result を持つ。

## 5. CDK Stack Layout

Proposed tree:

```text
infra/cdk/
├── bin/jpydf-hosting.ts
├── config/
│   ├── staging.ts
│   └── production.ts
├── lib/
│   ├── foundation-stack.ts
│   ├── static-sites-stack.ts
│   ├── hosted-anvil-stack.ts
│   ├── admin-console-stack.ts
│   ├── backend-stack.ts
│   ├── observability-stack.ts
│   └── constructs/
│       ├── static-site.ts
│       ├── fargate-static-console.ts
│       └── fargate-worker.ts
└── package.json
```

| Stack | Owns | Notes |
| --- | --- | --- |
| `FoundationStack` | Route 53 hosted zone lookup, ACM certs, KMS keys, log buckets, common tags. | CloudFront certificates are in `us-east-1`; app resources can stay in the chosen production region. Current CDK can consume existing certificate / WAF ARNs until this stack owns provisioning. |
| `StaticSitesStack` | user app bucket/distribution, ops bucket/distribution, stats bucket/distribution, OAC, headers policy, official hostname aliases, viewer certificate binding, WAF association, release evidence bucket, release evidence GitHub OIDC upload role, static asset GitHub OIDC publish role. | User app and ops must not share bucket or distribution behavior that can leak admin routes. Production synth must fail without official hostnames, a same-account `us-east-1` ACM certificate ARN, a same-account CloudFront-scope WAFv2 WebACL ARN, and same-account GitHub Actions OIDC provider ARNs for release evidence uploads and static asset publishing. |
| `CicdStack` | GitHub Actions OIDC CDK deploy role. | The deploy role assumes only same-account standard CDK bootstrap deploy / file-publishing / image-publishing / lookup roles. It has no direct CloudFormation / IAM / S3 / KMS permissions. Production synth must fail without a same-account GitHub Actions OIDC provider ARN. |
| `HostedAnvilStack` | staging Anvil Fargate task/service, VPC, ALB, CloudFront RPC distribution. | Explicit opt-in only. Output the CloudFront RPC URL, not the ALB DNS. |
| `AdminConsoleStack` | VPC, ECS cluster, console image, Fargate service, ALB HTTPS listener, Cognito/OIDC auth, noindex headers, WAF. | Public S3-only hosting is intentionally not the default. |
| `BackendStack` | scheduled ECS tasks for stats / `route-interest`, scheduled-worker failure alarms, liquidator Fargate service, EFS state, backend alarm SNS topic or imported topic action, liquidator catch-cycle metric filter / stale alarm, mainnet fork stress CodeBuild project, KMS-encrypted evidence bucket, GitHub OIDC dispatch role, task / build roles, Secrets Manager refs, CloudWatch logs. | Initial implementation keeps ops workers, liquidator, and fork stress gate in one opt-in stack to share backend IAM / secret boundaries. Split into separate stacks later only if ownership or blast-radius boundaries require it. |
| `ObservabilityStack` | CloudWatch dashboards, Synthetics canaries, alarms, SNS / ChatOps targets. | Monitors render, RPC, subgraph freshness, stats freshness, admin auth denial. |

## 6. Environment And Secret Model

KMS は production hosting の標準前提にする。AWS managed encryption だけで済ませず、
production / staging ごとに customer managed KMS key を分け、CDK で key policy、
rotation、alias、scheduled deletion guardrail、principal を明示する。

| Resource | KMS policy |
| --- | --- |
| user app / ops / stats S3 buckets | SSE-KMS を有効化する。CloudFront OAC から読む bucket は、CloudFront service principal に `AWS:SourceArn` で distribution ARN を縛った decrypt / data key 権限を付与する。 |
| release evidence / log buckets | SSE-KMS。release evidence bucket は CDK が作成し、明示 `aws:kms` + stack CMK upload だけを許す。release evidence upload role は repo/ref subject、release evidence prefix、release evidence CMK に限定する。CI deploy role、break-glass admin、audit reader だけに復号権限を付与する。 |
| Secrets Manager | admin OIDC secret、RPC key、liquidator live signing key を customer managed KMS key で暗号化する。dry-run task definition には signing key secret を attach しない。 |
| Mainnet fork stress RPC secret | archive-capable `MAINNET_RPC_URL` は fork stress job role だけが読める。CodeBuild log と artifact へ raw URL を出さない。 |
| EFS liquidator state | EFS encryption at rest を有効化し、liquidator task role と break-glass admin だけに access point / mount 権限を付与する。 |
| CloudWatch Logs | production log groups は KMS encryption を有効化し、retention と export 権限を明示する。 |
| ECR images | production worker / console images は KMS encryption を有効化する。 |

KMS key policy は least privilege に寄せる。特に CloudFront + S3 + SSE-KMS は、
OAC の bucket policy だけでは足りないため、KMS key policy 側にも CloudFront
distribution ARN 条件を入れる。

| Data | Storage | Exposure rule |
| --- | --- | --- |
| public contract addresses / chainId / manifest hash | generated env artifact + static bundle | Public, pinned per release. |
| user app RPC URL | build env / public bundle | Treat as public read endpoint. Use domain allowlist, rate cap, rotation owner. |
| browser RPC URL（user app / ops / admin） | shared generated `DEPLOYMENT.rpcUrl` or surface-specific runtime config | Browser bundle / authenticated browser から見える公開 read credential として扱う。共有可で、全利用 domain の allowlist、合算 traffic の rate / capacity 上限、rotation owner を持つ。公開 UI は provider label のみ表示し、evidence では redact する。 |
| worker RPC URL | Secrets Manager or task env rendered only into ECS / worker runtime | `export-stats`、`route-interest`、liquidator など server-side worker 用。browser bundle に入れない。 |
| WalletConnect project id | build env / public bundle | Public-ish client id; restrict domains where provider supports it. |
| liquidator private key | Secrets Manager + KMS | Only mounted in live task definition. Not present in dry-run task. |
| InterestRouter route private key | Secrets Manager + KMS | Separate from liquidator key. Only mounted in live `route-interest` task definition after route runbook gates pass. |
| archive mainnet RPC URL | Secrets Manager or SSM + KMS | Fork stress rehearsal job only. Not available to frontend bundles or public stats workers. |
| OIDC / Cognito client secret | Secrets Manager | Admin stack only. |
| deployment manifest | versioned artifact in CI and S3 evidence bucket | Hash must match frontend build evidence. |

Stats publish worker env:

| Env | Purpose |
| --- | --- |
| `OPS_STATS_S3_BUCKET` / `OPS_STATS_S3_KEY` / `OPS_STATS_S3_REGION` | Stable public stats object destination. |
| `OPS_STATS_S3_VERSIONED_PREFIX` | Immutable versioned stats prefix. |
| `OPS_STATS_S3_CACHE_CONTROL` | Stable object cache policy. Must be <= `OPS_STATS_STALE_THRESHOLD_SEC`. |
| `OPS_STATS_STALE_THRESHOLD_SEC` | Upper bound for stable stats cache age. |
| `OPS_STATS_STATE_PROFILE` | Optional public stats state profile (`hosted-demo`, `day1-review`, `local-demo`, `none`). Staging CDK defaults to public frontend 用の `day1-review`; production defaults to unset. |
| `OPS_STATS_S3_SSE=aws:kms` / `OPS_STATS_S3_KMS_KEY_ID` | Explicit SSE-KMS publish headers. Required in production mode. |
| `OPS_STATS_REQUIRE_KMS` | Force or disable script-level KMS guard. Production defaults to required. |
| `JPYDF_STATS_STATE_PROFILE` | CDK input that renders `OPS_STATS_STATE_PROFILE` into the stats publisher task definition. Use `day1-review` only after reset/reseed evidence is prepared. |
| `VITE_OPS_RPC_PROVIDER_LABEL` | Public ops UI RPC label; prevents host / key disclosure. |
| `JPYDF_BACKEND_ALARM_TOPIC_ARN` | Optional same-region existing SNS topic ARN for backend alarm actions. If omitted, `BackendStack` creates a backend alarm topic and outputs its ARN. |
| `JPYDF_BACKEND_ALARM_EMAILS` | Optional comma-separated email receivers for backend alarm SNS subscriptions. Requires `JPYDF_BACKEND_ENABLED=true`. Each receiver must confirm the AWS SNS email before notifications are delivered. |

Production builds must fail closed when required chainId, RPC, subgraph, stats URL,
or deployment manifest values are missing. Missing production values must not
fall back to local defaults, upstream Liquity endpoints, or fixture snapshots.
Local development snapshots such as `frontend/app/public/jpydf-stats-local.json`
must be deleted or excluded before publishing `frontend/app/out` to AWS.

## 7. CI/CD Flow

1. Freeze deployment manifest and generated app env from current contract deploy.
2. Regenerate `frontend/df-shared` and frontend env artifacts.
3. Pin the GraphQL schema source for `frontend/app` build. Use a managed /
   hosted subgraph endpoint with recorded freshness, or a committed schema
   artifact. Production CI must not silently depend on a local Graph Node.
4. Run focused checks:
   - `pnpm --filter @jpydf/app check:data-sources`
   - `pnpm --filter @jpydf/app build`
   - `pnpm --filter @jpydf/ops build`
   - `pnpm --filter @jpydf/console build`
   - `cargo test --manifest-path bots/liquidator/Cargo.toml`
5. Build Docker images for `frontend/console` static nginx, `ops-worker`, and
   `liquidator`. Day-1 ops worker は `frontend/ops/Dockerfile.worker` を root
   context で `linux/amd64` build し、ECS が pull 可能な ECR image を
   `JPYDF_OPS_WORKER_IMAGE` に指定する。Dockerfile は `frontend/ops` と
   `frontend/df-shared` を含める。staging は `:staging` のような mutable tag
   を許容するが、production の `JPYDF_OPS_WORKER_IMAGE` /
   `JPYDF_LIQUIDATOR_IMAGE` は `repo@sha256:<digest>` 形式の immutable image
   参照に固定する。staging で同じ mutable tag を repush しただけでは
   CloudFormation の image 文字列が変わらないため ECS service は自動置換されない。
   `aws ecs update-service --force-new-deployment` で task を置換し、新 task の
   `imageDigest` と CloudWatch startup log を evidence として残す。GHCR
   placeholder を default として扱わない。
6. Publish artifacts with immutable build identifiers.
   - For user app static uploads, exclude local-only stats snapshots such as
     `jpydf-stats-local.json`.
   - For public stats uploads, require `OPS_STATS_S3_KMS_KEY_ID` to point to the
     stats bucket CMK, not the AWS-managed `aws/s3` key.
   - Store release evidence in `ReleaseEvidenceBucketName` with
     `--sse aws:kms --sse-kms-key-id <ReleaseEvidenceKmsKeyArn>` through
     `.github/workflows/release-evidence-upload.yml` and the
     `ReleaseEvidenceGithubUploadRoleArn` role.
   - Run `pnpm -C infra/cdk check:release-evidence <file>` before uploading
     release evidence; the workflow runs the same check before `aws s3 cp`.
   - Publish user app / ops static assets through
     `.github/workflows/static-assets-production-publish.yml`, which uses the
     static asset publish role, stack output bucket / KMS / distribution ids,
     SSE-KMS S3 sync, CloudFront invalidation evidence, and a checked
     `release-evidence.generated.json` draft plus replayable
     `static-asset-manifest.generated.json` generated from the published static
     artifact directories.
7. Run [AWS-CDK-IAM-Evidence-Gate.md](../../contributors/deltaforesight/delivery-plans/AWS-CDK-IAM-Evidence-Gate.md)
   checks for synth / diff / assertions / CDK bootstrap readiness /
   GitHub production readiness / production promotion readiness /
   `check:policy-lint` / `check:promotion-evidence` /
   `generate:promotion-release-evidence` / `check:promotion-artifact` /
   `check:production-postdeploy`.
8. Deploy CDK staging.
9. Run negative drills:
   - missing / wrong chainId config
   - RPC all-down
   - stale stats
   - stats CDN cache TTL / `Cache-Control` が stale threshold 未満であること
   - stale subgraph
   - public ops raw endpoint / raw error redaction
   - admin unauthenticated access
   - admin CloudFront cache / auth-bypass attempt, if CloudFront fronts ALB
   - hosted Anvil CloudFront `eth_chainId` success and direct ALB `403`
   - stats exporter failure
   - liquidator dry-run restart with persisted state
10. Run `pnpm -C infra/cdk check:cdk-bootstrap` and
    `pnpm -C infra/cdk check:github-production`, then promote to production
    through `.github/workflows/cdk-production-promotion.yml`
    using the GitHub Actions OIDC deploy role and `production-infra` Environment
    subject / branch policy plus explicit deploy confirmation. Deploy runs must
    check AWS live postdeploy state, and the workflow
    must check the promotion diff / outputs / stack-list artifacts, write
    CloudFront invalidation evidence, generate a checked
    `release-evidence.generated.json` draft, replay-check the artifact set, and
    upload those artifacts.
11. Invalidate CloudFront caches when static assets change and record the
    invalidation artifact plus generated static artifact hashes in release
    evidence; replay-check the static publish artifact set with
    `pnpm -C infra/cdk check:static-assets-artifact`.
12. Confirm monitors, alert owners, rollback target, and Go / No-Go.

## 8. Monitoring And Alerts

Minimum monitors:

- user app home / borrow / earn / redeem route renders without raw provider error.
- ops dashboard renders and displays source block / generatedAt.
- public stats JSON freshness stays within threshold.
- subgraph endpoint freshness and GraphQL availability.
- RPC read health per configured browser endpoint / allowed domain。共有 key の場合は
  合算 quota / saturation も監視する。
- admin console returns unauthenticated denial before login and successful render
  after IdP auth.
- liquidator dry-run service advances blocks and writes state without live tx key.
  CDK P0 は CloudWatch Logs metric filter で `starting liquidation catch cycle`
  を数え、10分間出ない場合に stale alarm を発火させる。Alarm actions は backend
  alarm SNS topic に publish する。ALARM 時は ECS service desired/running count、
  latest task reason、CloudWatch log stream、RPC/chain progress、EFS state load log
  を順に確認する。`JPYDF_BACKEND_ALARM_EMAILS` で管理される email receiver は
  SNS confirmation 完了後に通知を受ける。T-0 readiness では
  `pnpm -C infra/cdk check:backend-alerts` が PASS し、
  `pnpm -C infra/cdk publish:backend-alert-test` の test message を operator が受信した
  ことを evidence に残す。
- `route-interest` / `publish-stats-s3` scheduled tasks have EventBridge
  `FailedInvocations` alarms and script-failure log metric alarms. ALARM 時は
  EventBridge target permission、ECS task stop reason、worker CloudWatch log、
  RPC / Secrets Manager availability を順に確認する。
- CloudFront 4xx / 5xx, ALB auth failures, WAF blocks, ECS task restarts.
- Better Stack など外部 synthetic monitor を併用する場合も、同じ route / expected
  status / stale threshold / redaction rule を使う。

Alerts must route to a named operator and link to the relevant runbook. User-facing
failure copy must not expose raw RPC URLs, key fragments, stack traces, or
`DataAPIError` internals.

## 9. No-Go Conditions

Do not launch production hosting if any of these remain:

- user app / ops / admin console が同じ public bundle または hostname を共有する、
  または共有 browser RPC credential に全 domain allowlist、合算 rate / capacity、
  rotation / revocation がない。
- admin console is reachable without company-controlled auth and MFA.
- admin console is fronted by CloudFront with cacheable authenticated responses,
  missing auth cookie / authorization forwarding, or no auth-bypass cache drill.
- admin console can hold a private key or send privileged transactions directly.
- S3 buckets serving public app / ops are public instead of private behind OAC.
- production frontend starts with missing env and fills values from mock / fixture /
  upstream Liquity endpoints.
- `frontend/app` production build depends on an unpinned local Graph Node or
  mutable schema source without recorded subgraph/schema evidence.
- stale stats / stale subgraph is rendered as current live data.
- public stats CDN cache TTL can exceed the documented stale threshold or serve
  stats without `generatedAt`, source block, and schema version.
- public ops UI renders a full RPC URL, key fragment, raw provider error, or
  stack trace.
- RPC all-down still allows borrow / deposit / redeem / claim write flows to start.
- public evidence contains full private RPC URL, key fragment, signer key, Safe
  nonce, or incident-only operator detail.
- rollback target and cache purge procedure are not recorded.
- liquidator live mode is enabled before dry-run evidence, chainId guard,
  gas/loss caps, and key handling are reviewed.
- `route-interest` live mode shares the liquidator signer secret or is enabled
  before route runbook simulation, recipient, threshold, and chainId gates are
  evidenced.

## 10. Implementation Order

1. Add `infra/cdk` scaffold, environment config, and reusable `StaticSiteConstruct`.
2. Deploy staging user app / ops / public stats with private S3 + CloudFront OAC.
3. Add optional hosted Anvil staging RPC and deploy / reset evidence.
4. Run `pnpm -C infra/cdk check:cdk-bootstrap` and
   `pnpm -C infra/cdk check:github-production`, then run GitHub Actions
   production promotion workflow against the real production account and record
   explicit confirmation / diff / outputs / stack list / generated release evidence draft using
   `infra/cdk/templates/production-promotion-first-run-evidence.md`.
5. Add `publish-stats-s3` scheduled ECS Fargate task and stats freshness canary.
6. Add authenticated admin console hosting behind ALB + Cognito/OIDC.
7. Add liquidator dry-run Fargate service with EFS state and catch-cycle stale
   alarm.
8. Run release evidence upload workflow for the first production promotion and
   record object version / KMS evidence in the same first-run evidence package.
9. Gate live liquidator / route-interest workers after operational drills.
10. Decide whether subgraph self-hosting is necessary; if yes, design it as a
   separate Day-2 stack.

## 11. Open Decisions

| Decision | Default | Owner / evidence |
| --- | --- | --- |
| Production AWS account / org layout | Separate company-owned production and staging accounts. | Asset owner list and billing owner. |
| Domain names | user app, ops, admin, stats JSON are distinct. | Official URL table in frontend production evidence. |
| Admin IdP | Cognito or company OIDC; MFA required. | Admin console production evidence. |
| RPC provider key policy | Day-1 は browser read-only credential を user app / Ops / Admin で共有可。surface 別 key は quota / fault isolation が必要な場合だけ使い、security boundary にはしない。 | Redacted provider label、shared / split、all-domain allowlist、aggregate rate / capacity、rotation / revocation. |
| Hosted Anvil reset cadence | Manual reset / redeploy while staging UX is still moving. | Reset evidence, manifest hash, frontend staging warning check. |
| Public stats cadence | Start with short recurring schedule; tune after RPC/provider limits are known. | stats freshness monitor and cost evidence. |
| Liquidator live mode | Off by default. | dry-run evidence, policy caps, signer custody approval. |
| Subgraph hosting | Managed/hosted endpoint for Day-1. | freshness monitor and incident runbook. |
| Vercel / CloudFront posture | AWS CloudFront is Day-1 baseline; Vercel remains viable for user app if the same env, artifact, headers, and rollback evidence are satisfied. | provider comparison and delivery gate evidence. |
| Neon / RDS posture | No DB for Day-1 frontend hosting unless a worker feature requires it. If DB is introduced, Neon and RDS must share migration / backup / restore drills. | schema migration plan and restore evidence. |
| Render / ECS posture | ECS is Day-1 baseline for workers; Render can host non-custodial workers if restart, secret, state, and alert semantics match. | worker runbook and dry-run evidence. |
| Better Stack / CloudWatch posture | CloudWatch is infrastructure source; Better Stack may be external synthetic / incident UX layer. | monitor parity checklist. |

## 12. AWS References

- [CloudFront: Restrict access to an Amazon S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront: Response headers policies](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/understanding-response-headers-policies.html)
- [ECS: Use EventBridge Scheduler to schedule ECS tasks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/tasks-scheduled-eventbridge-scheduler.html)
- [Elastic Load Balancing: Authenticate users using an Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-authenticate-users.html)
- [S3: PutObject API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html)
- [AWS WAF with CloudFront](https://docs.aws.amazon.com/waf/latest/developerguide/cloudfront-features.html)
