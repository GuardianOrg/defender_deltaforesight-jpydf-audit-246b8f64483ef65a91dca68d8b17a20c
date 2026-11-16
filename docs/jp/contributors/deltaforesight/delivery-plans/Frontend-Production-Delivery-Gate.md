# Frontend Production Delivery Gate

Updated: 2026-07-26

この runbook は User App、Dune Public Analytics、Private Operations Monitor、Admin Control、public stats publisher に共通するmainnet production gateを定義する。日本語版をsource of truthとし、Frontend specの `FRNT-TBD-004` / `FRNT-TBD-007` / `FRNT-SEC-002` / `FRNT-SEC-005` / `FRNT-SEC-007` / `FRNT-SEC-008` / `FRNT-GOV-001` / `FRNT-ERR-001` / `FRNT-ERR-002` / `FRNT-EVT-002` と連動する。

本gateを所有・配信・runtime integrityの共通判定正本とし、UX、agent discovery、restricted operationsは各差分gateを追加適用する。Admin Control / Private Operations Monitorの差分は [Admin-Console-Production-Gate.md](./Admin-Console-Production-Gate.md)、公開分析とprivate monitoringの責務、dual-run、cutover、decommissionは [Public-Analytics-Private-Monitoring-Architecture.md](../operations/Public-Analytics-Private-Monitoring-Architecture.md) を正とする。ミラー配信は [Frontend-Mirror-Delivery-Policy.md](./Frontend-Mirror-Delivery-Policy.md) を正とする。

判定はsurfaceごとに行う。evidence packageの先頭でoperation scope、対象surface、
対象外surfaceを固定し、各gate行は対象surfaceが使用するdata pathとdelivery方式にだけ
適用する。対象外の欄は空欄にせず、`N/A`、理由、状態を追跡する正本を記録する。
未実装surfaceを別surfaceの独立したreleaseのNo-Go理由にはしない。surface別判定と
operation全体の判定を分け、Dune / Private Operations Monitorへのcutoverとpublic Opsの
decommissionは、対象surfaceすべてのevidenceが揃った場合だけGoとする。

## 1. Scope

対象:

- User App: public user application。
- Dune Public Analytics: 公開on-chain統計・履歴。real-time monitorではない。
- Private Operations Monitor: 即時状態、critical alert、ACK / escalationを扱う認証済みview。
- Admin Control: 特権操作を準備・検証するrestricted operations surface。
- DF-managed public stats publisher: User App current health JSONをDuneと独立して提供する。
- 移行中のpublic Ops UI / build / publish workflow: architectureのdecommission完了までだけ対象とする。
- 共通runtime config: chainId、RPC、subgraph、contract manifest、official links。

実domain、provider key、account名等のprivate値はevidence packageで管理する。APR時系列collectorがない場合は該当表示を無効化する。

## 2. Day-1 Minimum Gate

| Gate                       | Day-1 要件                                                                                                                                                                                                                                 | Evidence                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| Company ownership          | domain registrar、DNS、hosting/CDN、RPC/subgraph provider、stats storage、Dune Teamを会社管理accountに置く。個人account依存でlaunchしない。 | asset owner list、admin group、billing owner、break-glass owner |
| Domain registry            | User App、Dune、Private Operations Monitor、Admin Control、public stats、移行中のpublic Opsの正式URLと公開 / restricted境界を一つのevidenceに固定する。preview / staging / localhostをofficial linkに混ぜない。 | official URL table、staging URL table、link ledger check、migration state |
| Hosting separation         | User Appと認証済み運用面を別projectまたは明確なroute / auth boundaryで分ける。移行中のpublic Ops bundleにwallet / signing runtime、secret、admin runtime config、operator-only routing / worker commandを含めず、decommission完了までpublic-bundle guardを通す。 | hosting project id、route / role map、public-bundle boundary check |
| Delivery integrity         | HTTPS、HSTS、CSP、必要に応じた SRI、DNSSEC または registrar lock を適用する。第三者 script / executable tag は台帳化し、不要なら入れない。                                                                                                 | response headers、DNS/registrar evidence、CSP report-only/active state                       |
| Runtime config fail-closed | code-delivered surfaceのproduction build / runtime healthは、そのsurfaceが使用するchainId、deployment manifest hash、RPC URL、subgraph URL、stats URLの必須値が未設定ならfail-closedにする。Duneにはこのbrowser runtime configを転用せず、query registryとexecution evidenceを適用する。viem public defaultなどの迷いRPC pathを残さない。 | env schema output、runtime health JSON/screenshot、negative config drill |
| RPC / API keys             | browser向けread-only RPC / subgraph credentialはUser App、移行中のpublic Ops、Admin Controlで共有可だが公開credentialとして扱う。全利用domain、合算rate / capacity、rotation owner、leak responseを記録し、worker / archive / write / signing credentialは分離する。 | provider label、shared / split、redacted URL、allowed domains、aggregate rate / capacity、rotation owner |
| Contract manifest          | User App、Admin Control / Private Operations Monitor、移行中のpublic Opsが読むchainId、contract address table、generated binding commit、deployment manifest hashをproduction evidenceに固定する。 | manifest hash、build commit、generated binding hash、contract table |
| Subgraph release           | `mainnet-relaunch` / network `mainnet`、current manifest 由来の JPYdf / Zapper address、JPYdf deploy tx block と一致する `startBlock`（より早い block は理由付き）、schema / mapping commit、version / deployment ID を固定し、欠落 event がないことを smoke query で確認する。 | generated network / subgraph manifest hash、startBlock 根拠、release ID、query evidence |
| Public stats freshness     | stats JSON は source block、generatedAt、schema version を含む。stale threshold 超過時、user app は数値を mock で補完せず stale / unavailable 表示にする。                                                                                 | stats JSON sample、stale drill、alert rule                                                   |
| Subgraph degradation       | subgraph が stale / unavailable の場合、RPC 現在値と index 由来値を視覚的に区別する。書き込みに必要な現在値は RPC 由来に限定する。                                                                                                         | degraded screenshot、RPC fallback evidence                                                   |
| Error surface              | RPC / subgraph / stats failure は user-facing copy に丸める。raw stack、provider URL、DataAPIError 詳細、key fragment を表示しない。全 RPC 不通時は write UI を停止する。                                                                  | failure screenshots、redaction check                                                         |
| Agent discovery            | user app は [Frontend-Agent-Readiness-Gate.md](./Frontend-Agent-Readiness-Gate.md) を満たす。admin / ops surface を user app discovery に混ぜず、実体のない MCP / Agent Skills / OAuth / commerce endpoint を available として公開しない。 | `robots.txt` / `sitemap.xml` / `llms.txt` / `auth.md` / `.well-known` output、scanner result |
| Monitoring                 | User App render、RPC read、subgraph / stats freshness、official link、critical routeをsynthetic monitorに入れる。Duneはquery freshnessを監視し、Private Operations Monitorはworker ingestionとalert deliveryを監視する。 | monitor URL/list、Dune query freshness、alert owner、delivery test |
| Release / rollback         | 対象surfaceごとにbuildまたはquery registry revision、config hash、release time、rollback / replacement target、該当する場合はcache purge手順を記録する。 | release evidence、rollback rehearsal or documented target |
| Surface-specific gates     | User Appと移行中のpublic Opsは [UX Gate](./Frontend-UX-Readiness-Gate.md)、User Appは [Agent Gate](./Frontend-Agent-Readiness-Gate.md)、Admin Control / Private Operations Monitorは [Admin Gate](./Admin-Console-Production-Gate.md)、公開分析・private monitoring移行は [監視アーキテクチャ](../operations/Public-Analytics-Private-Monitoring-Architecture.md) のgateを満たす。 | 各差分evidenceのIDと判定 |

## 3. No-Go Conditions

以下が残る場合、mainnet production を公開しない。

- Duneをcritical alert、availability monitor、User App runtime APIとして使用する。
- Duneを公開済みまたはcutover可能と判定する時点で、query registry revision / hash、
  repository SQL / parameter-set hash、Dune query revision / exported SQL hash、
  repositoryとのcontent match、public query / dashboard ID、Dune上のcompile・
  成功execution、同一期間または同一blockのRPC / event照合、freshness、実測creditsの
  証跡がない。
- Private Operations Monitorが未認証、またはmonitor viewerから特権操作へ到達できる。
- dual-run evidenceなしにpublic Ops URLを公式導線から外す、またはdecommission完了前にpublic-bundle guardを削除する。
- public stats publisherがDuneまたはpublic Ops UIの可用性に依存する。

- official domain / hosting / RPC / stats が個人 account 依存。
- production app が `api.liquity.org`、upstream governance endpoint、viem public
  default RPC など JPYdf 非所有 endpoint へ到達できる。
- production env 未設定でも user app が起動し、数値を mock / fixture / stale
  snapshot で埋める。
- `pnpm -C frontend/ops check:public-bundle` が失敗する、または public bundle に
  wallet / signing runtime、admin runtime config / URL、private RPC URL、
  operator-only routing / worker command、key fragment、Safe nonce、private signer
  情報が含まれる。
- stats JSON に `generatedAt` / source block / schema version が無い。
- subgraph の network / address / schema / mapping commit / version が current release と一致しない、`startBlock` が JPYdf deploy tx より後で欠落 event を生む、または deploy tx より前の値にした理由が記録されていない。
- stale stats / stale subgraph が live current value と同じ見た目で表示される。
- RPC 全系統不通でも borrow / deposit / redeem / claim など write flow が開始できる。
- public user app の production env で `NEXT_PUBLIC_SHOW_DATA_SOURCES=true`、
  `NEXT_PUBLIC_ALLOW_DATA_SOURCE_OVERRIDES=true`、または
  `NEXT_PUBLIC_DEV_WALLET=true` が設定され、ユーザーが custom RPC / subgraph
  endpoint や local dev wallet 経路を使える。
- inert branch（Day-1: branch 2–7）または cap 0 branch が borrow dropdown、`/borrow/*` route、または write request 生成対象として有効になっている。
- `NEXT_PUBLIC_REFERRAL_REGISTRY_URL` が設定されているが、有償 Referral campaign activation packet（#668 または後継 issue）が承認されておらず、`NEXT_PUBLIC_REFERRAL_CAMPAIGN_ACTIVATION_APPROVED=true` の evidence もない。Day-1 標準では referral registry URL は未設定にし、URL slug capture は referral なし transaction に落とす。
- raw provider error、stack trace、DataAPIError 詳細、private URL が user-visible。
- rollback 先または cache purge 手順が記録されていない。

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

1. Freeze domain、hosting、endpoint、Dune、restricted surface、public Ops移行状態のinventory。
2. Build code-delivered target surfaces from the pinned commit. Duneを対象に含む場合は、
   query registry revision、repository SQL / parameter-set hash、Dune query revision /
   exported SQL hashを固定し、内容一致を確認する。
3. Verify env schema and runtime health with positive config.
4. `./subgraph/deploy-subgraph mainnet-relaunch --deployment-manifest
   <current-manifest> --start-block <JPYDF_DEPLOY_BLOCK> --version <VERSION>` で generated
   manifest を作り、network / address / `startBlock` を review してから deploy / smoke query
   evidence を残す。
5. Run negative config drill: missing RPC, wrong chainId, missing stats URL, stale
   stats, stale subgraph, and all-RPC-down.
6. public Opsのbuild / publish workflowが残る間は `pnpm -C frontend/ops check:public-bundle` を実行し、official links、upstream endpoint、mock snapshot、private metadataの混入がないことを確認する。
7. Verify agent discovery files and run the UX / Agent / Admin differential gates plus the monitoring architecture dual-run / cutover / decommission gate.
8. Publish code-delivered surfaces to staging and record headers, CSP, HSTS, DNS / registrar evidence. Verify Dune query freshness and public scope.
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
   stack bucket CMKs, deletes local-only stats snapshots from the user app
   artifact before upload, waits for CloudFront invalidation completion,
   generates a checked `release-evidence.generated.json` draft plus
   `static-asset-manifest.generated.json`, replay-checks the artifact set with
   `pnpm -C infra/cdk check:static-assets-artifact`, and records the draft /
   manifest / invalidation evidence in the workflow artifact. Keep the generated
   draft at `goNoGo=no-go` until operator review, then upload the final JSON
   through `.github/workflows/release-evidence-upload.yml`.
10. Confirm synthetic monitors、Dune query freshness、monitoring worker、alert owners and delivery.
11. Record per-surface Go / No-Go、migration state、rollback target.

## 5.1 Machine Checks

production promotion 前に、少なくとも次を実行して evidence に残す。

```bash
pnpm -C frontend/app check:hosting-env
pnpm -C frontend/app check:data-sources
pnpm -C frontend/app build
pnpm -C frontend/ops check:hosting-env
pnpm -C frontend/ops build
```

`frontend/ops` の2コマンドはpublic Ops build / publish workflowが存在する間だけ必須とする。decommission後は、当該workflowと公開配信資産の撤去、公式リンクcutover、public-bundle guardの同一reviewでの削除をarchitecture evidenceとして残す。

`frontend/app check:hosting-env` は production env を読み込んだ状態で
`NEXT_PUBLIC_SITE_URL`（HTTPS origin only）、`NEXT_PUBLIC_CHAIN_ID=1`、
`NEXT_PUBLIC_CHAIN_RPC_URL`、`NEXT_PUBLIC_SUBGRAPH_URL`、
`NEXT_PUBLIC_PROTOCOL_STATS_URL`、`NEXT_PUBLIC_DEPLOYMENT_FLAVOR` に加え、
`NEXT_PUBLIC_SHOW_DATA_SOURCES=false`、
`NEXT_PUBLIC_ALLOW_DATA_SOURCE_OVERRIDES=false`（または未設定）、
`NEXT_PUBLIC_DEV_WALLET=false` を確認する。user app runtime も
`NEXT_PUBLIC_SHOW_DATA_SOURCES=false` の場合は localStorage に残った RPC / subgraph
override を無視し、official config のみを使う。local / CI の空 env で
`site-url-required` が出る状態や、staging Anvil env（例: chainId `31338`）で
`mainnet-chain-required` が出る状態は正常な negative drill であり、production Go
evidence として扱わない。`NEXT_PUBLIC_REFERRAL_REGISTRY_URL` が設定されている場合は、
有償 Referral campaign activation packet が承認済みであることを示す
`NEXT_PUBLIC_REFERRAL_CAMPAIGN_ACTIVATION_APPROVED=true` も必要である。Day-1 標準では
registry URL を未設定にし、paid campaign を user-facing にしない。
`frontend/ops check:hosting-env` は生成済み
binding の chainId が Ethereum mainnet `1` であり、rpcUrl が HTTPS absolute URL かつ
localhost / loopback でないことを確認するため、generated binding hash と合わせて
evidence 化する。staging Anvil binding（例: chainId `31338`）でこの check が fail する
状態も正常であり、production Go evidence として扱わない。

admin console は別 gate のため、
[Admin-Console-Production-Gate.md](./Admin-Console-Production-Gate.md) の
`pnpm -C frontend/console check:hosting-env` / `pnpm -C frontend/console build`
を別 evidence として残す。

## 6. Day-2 Enhancements

Day-2 として追加してよいが、Day-1 gate の代替にはしない。

- Mirror delivery（IPFS / ENS 等）は
  [Frontend-Mirror-Delivery-Policy.md](./Frontend-Mirror-Delivery-Policy.md)
  の gate を満たす場合に限る。
- APR / historical time-series collector。
- CSP report ingestion and automatic regression tickets。
- Public status page。
- Multi-region frontend failover。
