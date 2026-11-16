# Issue #1201 Sepolia Safe authoritative E2E evidence

実施日: 2026-07-25–26
対象: [Issue #1201](https://github.com/deltaforesight/jpydf-v2/issues/1201) /
[Issue #1188](https://github.com/deltaforesight/jpydf-v2/issues/1188)
結果: **PARTIAL PASS — Safe / Timelock E2EはPASS、production gateはPending**
binding commit: `8d2e95b3831395a821fe1cb5c9b73fb0b408cecc`

## 1. 判定と検証条件

専用Sepolia環境で、Safe Transaction Builder import、公式Safe Transaction
Serviceのproposal照合、Safe実行、Timelockのexecute / cancel lifecycle、Consoleの
fail-closed・reload再開・`executed-safe`反映を確認した。外部syntheticのAPI疎通と
通知文面・Issue運用は確認したが、GitHub Actions自身によるtest incidentの起票・復旧は
未実施である。production contract、mainnet Safe、production roleは使用していない。

Issue本文はSafe ownerを人間walletとするが、ユーザーから「エージェントが操作できる
テスト用アカウントを作成し、UIを含め自力検証する」と明示指示があったため、今回だけ
1/1のagent-operated test EOAへ置き換えた。これはIssueの機能的な署名・proposal・実行経路を
短縮しておらず、Safe公式UIと公式APIを通している。一方、人間walletによる署名証跡とは
扱わない。秘密鍵は`/private/tmp`配下のmode `0600`ファイルにだけ置き、repository、
Console、証跡へ保存していない。
全transactionと最終read-only検証の完了後にこの一時秘密鍵を破棄したため、test Safeは
以後署名不能である。monitorはread-onlyのため継続できる。

## 2. 固定testbed

| 対象 | 値 | 検証 |
| --- | --- | --- |
| chain | Ethereum Sepolia `11155111` | PASS |
| test EOA / Safe owner担当 | `0x07665e328618766f3ad96511D8bB6BF3cfE6c5d3` / agent-operated one-time EOA | PASS |
| Safe | `0x782059E410150161489F7b2f36Ac4de54734e583`, v1.4.1+L2, 1/1 | PASS |
| Timelock | `0x99142e847c94E35D74c2a24125Ba88183606d3F1`, delay 60秒 | PASS |
| target | `0xF0b3b80b2024F2E794195B16ecDd1f75A64deD3C` | PASS |
| role | Safe=PROPOSER / EXECUTOR / CANCELLER、open executorなし、外部adminなし | PASS |
| target authority | Safe=GUARDIAN、Timelock=GOV、target=self-admin | PASS |

deploymentとruntime codehashの正本は
[`safe/safe-deployment.json`](./safe/safe-deployment.json)、
[`testbed/testbed-plan.json`](./testbed/testbed-plan.json)、
[`testbed/state-verification.json`](./testbed/state-verification.json)。

| 対象 | deploy tx / block | runtime codehash |
| --- | --- | --- |
| Safe | [`0xd564…92e`](https://sepolia.etherscan.io/tx/0xd5643983b7e20af6098628079f9017d581c334a8bcbc029bb571e6f76479d92e) / `11348225` | `0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c` |
| Timelock | [`0x4e29…cc2`](https://sepolia.etherscan.io/tx/0x4e2993cb76fc12e31f0545f1da5b638d9c7fb94336d3397f19acbcea34094cc2) / `11348253` | `0xf67e476b6ac5b0259c2360d930ef86a12cc0b801ea38272f9a8769310e270d32` |
| target | [`0x38c6…8f1`](https://sepolia.etherscan.io/tx/0x38c671a7d05718e30a4fc9c5f80adbb10596ef4f70e9014699084bb1c891c8f1) / `11348258` | `0x495e7add2286b89e8969c4997331832e9a2e2a10c10fa752e6216b67148b2c58` |

Consoleはopt-inの
`VITE_CONSOLE_ISSUE_1201_SEPOLIA_TESTBED=true`でこのbindingを使用し、
Timelock deploy blockを`11348253`、local executionを無効にした。

## 3. Safe proposal / Timelock E2E

[`safe/proposal-verification.json`](./safe/proposal-verification.json)は、保存済みartifactと
Builder JSONを再検証し、公式Safe APIからproposal / Safe-infoを再取得して次をすべて
照合した結果である。

- Builder checksumとartifact integrity
- chainId / Safe / transaction count 1 / `CALL` / to / value / data
- Safe version、nonce、zero gas / gas token / refund receiver
- 全署名fieldから再計算したEIP-712 Safe tx hash
- Timelock stage / inner target / value / calldata / predecessor / salt / delay / operation ID
- generated / proposed canonical payload hash
- `isExecuted=true`、`isSuccessful=true`、on-chain transaction hash

| stage | Builder checksum | payload hash（generated = proposed） | Safe tx / on-chain tx |
| --- | --- | --- | --- |
| direct pause | `0xa3ba…16c9` | `0xce19…156d` | `0xcd2b…d238` / [`0x21a1…204`](https://sepolia.etherscan.io/tx/0x21a1b5ecfe4107edc810b94cdf147e4129b43187fa4a0e88f8a4c75c9549a204) |
| schedule set delay | `0x5fbf…e0b9` | `0x2e05…97f7` | `0xbac1…358d` / [`0x6dd0…cbc`](https://sepolia.etherscan.io/tx/0x6dd06b46610283417ad014bacf737c62f20f21566bddc499e940cd6390645cbc) |
| execute set delay | `0x6745…d75` | `0xce42…fc8f` | `0xbb64…8018` / [`0x232b…6e7`](https://sepolia.etherscan.io/tx/0x232beaed968e3647fc1cf8f2b3e406907e675aad783f56c71a4937c8b5dbe6e7) |
| schedule unpause | `0x8a8e…9df1` | `0x2f59…834c` | `0x2071…c2ec` / [`0x08ec…4e71`](https://sepolia.etherscan.io/tx/0x08ec5d63a36458e2bd6c9b60b3d6d4aa1ed4aa27ef82f42ff36b089bbbe84e71) |
| cancel unpause | `0xc5e3…0cae` | `0xcebc…cea9` | `0xb60f…93e3` / [`0x1aea…a4ad`](https://sepolia.etherscan.io/tx/0x1aea4c7ed2178d0f12aef369db888084ec8a003c2ca5a119fb88dc4601c8a4ad) |

最新のread-only再検証ではon-chain stateをblock `11352763`で再読した。execute operation
`0x117fe9a13d6712e4039cc0cea1a38d172dc4cb839272a8d19fbd7e93e641748a`
はtimestamp `1` / `done`、cancel operation
`0x02af6978bbe208761e3548b0c04ac5f0730351267c7f3764101fed84f75def4c`
はtimestamp `0` / `unscheduled`。targetは`pausedDeposit=true`、
`withdrawDelay=7200`、`lastUpdater=Timelock`、`updateCount=2`でPASS。

## 4. UI evidence

UIごとのassertionは[`ui/evidence.json`](./ui/evidence.json)を正本とする。

- Safe公式Transaction Builderでdirect / schedule / execute / cancelをそれぞれ1件の
  transactionとしてimportし、directはtarget、3 stageはTimelockへの`CALL`であることを確認。
- Safe公式transaction画面でexecute proposalのSuccess、wrapper引数、作成・署名・実行actor、
  on-chain txを確認し、reload後と390×844 viewportでも再確認。
- Consoleで誤proposal、誤chain URL、BuilderのSafe / operation / value / data /
  predecessor / salt / delay / operation ID / checksum改変をfail-closedとして確認。
- route移動・reload・RPC read failure後もPending Queueから保存済みartifactの再照合を再開。
- authoritative proposalが完全一致し、かつ実行成功した場合だけon-chain tx hashを
  `executed-safe`へ反映し、Audit Logに残ることを確認。

## 5. Safe API monitoringと未完了のdelivery gate

設定正本は
[`frontend/console/config/safe-api-synthetic-sepolia.json`](../../../../../frontend/console/config/safe-api-synthetic-sepolia.json)。
2026-07-25のpreflightではunauthenticated endpointからresponse header上
5,000 requests/monthを観測した。保存済みの[`monitor/healthy.json`](./monitor/healthy.json)、
[`monitor/test-incident.json`](./monitor/test-incident.json)、
[`monitor/recovered.json`](./monitor/recovered.json)は、この疎通・異常判定・復旧判定の
記録であり、認証済みproduction monitorまたはActions配送の証跡ではない。

本PRで追加するmonitorは、Admin Consoleのsynthetic用OIDC sessionまたは専用authorizationを
必須とし、deployed Admin Consoleのsame-origin proxyを通してSafe owner / threshold、
保存済みartifact、全signed field、EIP-712 Safe tx hash、実行成功、on-chain tx hash、
認証済みquotaを照合する。`api.safe.global`へのdirect monitor URLは設定検証で拒否する。
2 requests/runのhourly運用は最大1,488 requests/monthであるが、これはsynthetic分だけであり、
operator trafficを含むaggregate consumptionは別途provider側で監視する。proxyはclientごと
10 requests/minute、全体30 requests/minute、clientごと同時2接続に制限し、capacity拒否は
`429`と`Retry-After: 60`を返す。運用owner / human recipientは
`Admin Console operations / yusuke-j0728`、1 endpointのdeadlineは20秒、2 endpointを実行する
子processの物理deadlineは45秒とする。子processがabortを無視してもTERM/KILL後にfallback
reportを生成する。workflowは、default branchでのdeployed path・認証済みquota確認と
test incident delivery / recoveryが完了するまでmanual-onlyとする。

Issue
[#1245](https://github.com/deltaforesight/jpydf-v2/issues/1245)を
`safe-api-monitor` / `test-incident` label付きで`yusuke-j0728`へassignし、
healthy recovery後にコメントしてresolvedした操作は手動リハーサルであり、Actions
workflow自身の配送ではない。分類は
[`monitor/test-incident-delivery.json`](./monitor/test-incident-delivery.json)を正本とする。

production gateを閉じるには、default branchへmergeしてAdmin Console stackをdeployする。
workflowは既存のGitHub OIDC / `JPYDF_AWS_ACCOUNT`だけを使用し、CDKが作る固定名の
`Jpydf-production-AdminConsoleSyntheticGithubRole`をassumeする。Admin Console URLは
CloudFormation output、synthetic専用identityの認証情報はSecrets Managerの
`jpydf-production/admin-console-safe-api-synthetic-auth`から実行時に取得する。
secret JSONは`sessionCookie`または`authorization`を持つ。GitHub variable / secretへ
base URLや認証情報を複製せず、Safe API key自体もworkflowへコピーしてはならない。

1. `test_incident=true`で起動し、workflow自身がlabel・assignee・Actions run URL付きの
   test incidentを作成する。
2. `test_incident=false`で再実行し、workflow自身が復旧コメントとActions run URLを残して
   test incidentをcloseする。
3. 両run artifactでdeployed proxy URL、認証済みcapacity、完全なproposal検証、
   秘密値非出力を確認する。
4. 証跡を本directoryへ固定してからhourly scheduleを有効にする。

## 6. 要件対応とGate判定

| Issue #1201要件 | Evidence | 結果 |
| --- | --- | --- |
| 専用Safe / Timelock / target、role分離、binding / codehash | §2、`safe/`、`testbed/` | PASS |
| direct / schedule / execute / cancelの公式Safe UI import・proposal・実行 | §3–4、`transactions/`、`ui/` | PASS |
| 全field一致だけverified、不一致fail-closed、reload再開、executed-safe | §3–4、proposal verification、UI evidence | PASS |
| waiting→ready→execute→done、schedule→cancel→unscheduled、post-state | §3、state verification | PASS |
| 認証済みquota / external synthetic | 本PRの実装・unit test、default branch実行は§5に記載 | PENDING |
| workflowによるtest incident delivery / recovery | §5。#1245は手動リハーサルのみ | PENDING |
| 人間wallet / independent reviewerによる署名・dry-run | §1。agent-operated one-time EOAへ明示的に置換 | PENDING |
| secret非公開 | staged差分と秘密鍵値の一致検査0件、credential file 0件 | PASS |
| #1188残存gateへのリンク | 本reportとPRを#1188へリンク | PASS |

以上により、SepoliaでのSafe / Timelock機能E2EはPASSとする。一方、認証済みmonitorの
default-branch実行、workflow自身による通知delivery / recovery、人間operator要件が
未完了のため、Issue #1201のproduction gateは **Pending** とし、Issueをcloseしない。

## 7. 再現コマンド

```bash
pnpm -C frontend/console test:ci
pnpm -C frontend/console typecheck
pnpm -C frontend/console build
pnpm -C frontend/console verify:sepolia-proposals
pnpm -C frontend/console verify:sepolia-testbed
SAFE_API_SYNTHETIC_BASE_URL=https://admin.example.com/api/safe/tx-service/sep/api/v1 \
SAFE_API_SYNTHETIC_SESSION_COOKIE='<value read from Secrets Manager>' \
  pnpm -C frontend/console check:safe-api-synthetic -- \
  --config config/safe-api-synthetic-sepolia.json \
  --out /private/tmp/console-safe-api-synthetic.json
forge test --match-path test/ConsoleSepoliaTestTarget.t.sol -vv
```

2026-07-26の修正後結果はConsole `test:ci` 26系統、typecheck、通常buildがPASS。
Foundryはbuild、対象test、全76 suitesで1,415 testsがPASS、failure 0、skip 1。
2026-07-26のread-only再検証でも公式Safe proposal 5件がPASS、block `11352763`で
on-chain stateがPASS、unauthenticated synthetic preflightがHTTP 200 /
executed / successfulでPASSした。
workflow YAML parse、`git diff --check`、秘密鍵値のstaged diff一致検査もPASS。

認証proxy、完全なauthenticated synthetic、delivery workflowについては、本PRの最新commitと
CI結果、および§5のpost-merge Actions runを新しい証跡とする。

全ファイルのSHA-256は[`SHA256SUMS`](./SHA256SUMS)に固定する。
