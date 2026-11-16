# Admin Console Production Gate

Updated: 2026-08-03

この runbook は `frontend/console` 内の Admin Control と認証済み Private Operations Monitor に固有の mainnet差分gateを定義する。[Frontend-Production-Delivery-Gate.md](./Frontend-Production-Delivery-Gate.md) の共通判定を前提とし、RPC credential、live-data、error redaction、release / rollbackを再掲しない。日本語版をsource of truthとし、Frontend specの `FRNT-TBD-005` / `FRNT-FR-024..035` / `FRNT-SEC-007` / `FRNT-SEC-008` / `FRNT-GOV-001` と連動する。公開分析との責務境界は [Public-Analytics-Private-Monitoring-Architecture.md](../operations/Public-Analytics-Private-Monitoring-Architecture.md) を正とする。
ローンチ後の日常操作は
[`Admin-Console-Operator-Manual`](../../../protocol/operations/runbooks/Admin-Console-Operator-Manual.md)
を使い、本 gate の evidence template や non-mainnet E2E を日次手順として転用しない。

## 1. Scope

認証済み運用面は次の2 viewを持つ。

- Admin Control: GOV_MULTISIG / ALLOCATOR / GUARDIAN / WRITEOFF / oracle owner / token ownerの操作を準備・確認する。秘密鍵を保持せず、calldata、現在値、role / owner、Safe / explorer導線、証跡を提供する。
- Private Operations Monitor: 全branchの即時状態、monitoring degradation、critical alert、ACK / escalationを表示する。特権操作を準備・送信しない。

monitor viewerとprivileged operator / signerは分離可能にし、viewerからAdmin Controlへ到達できない構成を許容する。Admin Controlの操作はAction Registryからauthority、holder、実行経路、効果発現時期、復旧主体を表示し、Timelock workflow roleと対象contract authorityを分ける。実行はSafeまたは当該role holderのwalletで行い、GOV / DEFAULT_ADMIN / DToken owner / Strategy upgrader操作は共通TimelockControllerを経由する。

## 2. Day-1 Minimum Gate

| Gate                          | Admin差分要件                                                                                                                                                                                                                                                                                                                                                 | Evidence                                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Authentication                | 会社管理 IdP または access proxy で保護する。MFA 必須。shared password のみは禁止。break-glass account は社内運用資料にだけ記録し、公開 docs へ書かない。                                                                                                                                                                                                     | IdP / proxy 名、管理 owner、MFA policy、許可 group 名                                                         |
| Monitor / operator separation | monitor viewer、privileged operator、signerの到達権限を分離し、viewerにcalldata生成・Safe proposal・特権操作導線を付与しない。                                                                                                                                                                                                                                | group / route matrix、viewer negative access test、operator positive test                                     |
| Hosting separation            | user app と別 hostname / project / deployment にする。public marketing / user app からリンクしない。                                                                                                                                                                                                                                                          | console domain、hosting project id、user app から到達不可である確認                                           |
| Search index block            | `X-Robots-Tag: noindex`、HTML `noindex`、`robots.txt` のいずれか複数で index を拒否する。auth wall なしで bundle が読める構成は不可。                                                                                                                                                                                                                         | response header、robots、page source の確認                                                                   |
| Role visibility               | role / owner は on-chain read で確認する。role は複数 address が持てる前提で list 表示する。`AccessControlEnumerable` でない role は「declared holders + hasRole 検証」として扱い、未知 holder の不存在は governance handover / [`Mainnet-Safe-Role-Assignment-Gate`](../../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md) の証跡で補完する。 | role snapshot block、declared holder list、hasRole / owner read result、address book hash                     |
| Safe / Timelock boundary      | simulation済みartifactをouter `CALL` 1件のBuilder JSONとして渡し、公式read-only APIから取得したproposalの全署名対象field・EIP-712 hash・実行結果を機械照合する。Timelock操作はwrapperをdecodeしてinner payloadとoperation stateを照合する。lookupはboundedかつkill可能とし、依存障害から自動回復できる。                                                      | §5.1 / §5.2 のartifact、payload diff、Timelock state、lookup health、monitor delivery                         |
| Privileged operation UX       | pause / unpause、cap、allocator、strategy add/update、writeoff、oracle source replacement、upgrade は impact preview と二重確認を必要とする。preview 不可なら「preview unavailable」と明示し、guard 値を operator が入力する。                                                                                                                                | operation evidence、impact preview、guard values                                                              |
| Operator readiness            | `Admin Safe` / `Guardian Safe` / `Allocator Safe` の label と checksum address を単一 build-time 設定へ固定する。日常操作の共通経路、Safe JSON import、署名前機械照合、Timelock Schedule / Execute / Cancel、例外操作、停止条件を Operator Manual に固定し、operator と independent reviewer が本番相当の dry-run を完了する。                                | address book hash、operator config、manual revision、training record、representative T1 / D1 dry-run evidence |

## 3. No-Go Conditions

共通 gate または §2 の差分要件が未達なら No-Go とする。特に次は証跡の
注記だけで許容しない。

- 認証・配信分離・noindex のいずれかがない。
- monitor viewerがAdmin Control、calldata生成、Safe proposal、特権操作導線へ到達できる。
- role snapshot が複数 holder を扱わない、または role assignment package と不一致。
- calldata の手動転記が必要、proposal の全 field / EIP-712 hash / execution outcome
  を公式 read-only API から照合できない、または lookup が bounded でない。
- Timelock target / operation、Pending Queue の chain / Action / target / route /
  freshness を再検証できない。
- console が鍵を保持・送信する、または operator と independent reviewer の
  production-like dry-run が未完了。

## 4. Production Evidence Template

```
Admin console production evidence
Date:
Operator:
Common production evidence ID:
Admin Control URL:
Private Operations Monitor URL:
Monitor viewer group:
Privileged operator group:
Viewer negative access evidence:
Auth provider / group:
Noindex evidence:
Role snapshot block:
Declared role holders:
hasRole / owner verification:
Safe artifact hash / simulation block:
Action ID / required authority / execution route:
Artifact integrity (valid / stale / invalid / superseded):
Safe Transaction Builder filename / checksum:
Generated / imported / proposed payload hash:
Safe transaction URL / ID / Safe tx hash:
Safe version:
Safe proposal verification result / diff:
Safe read-only API / proxy aggregate quota, rate / connection limit, 429 backoff:
Safe lookup timeout / active count / configured limit / oldest outstanding age / circuit / stuck probe:
Safe verification synthetic monitor / escalation / delivery test:
Governance execution path (derived from chainId / Timelock config):
Timelock address / deploy block:
Timelock minDelay / role snapshot:
Timelock operation ID / stage:
Dry-run / import evidence:
Known limitations:
Go / No-Go:
```

## 5. Machine Checks

production promotion 前に、少なくとも次を実行して evidence に残す。

```bash
pnpm -C frontend/console check:hosting-env
pnpm -C frontend/console build
```

`check:hosting-env` は generated binding の chainId / RPC URL、`index.html` の
noindex、`VITE_CONSOLE_ENABLE_LOCAL_EXECUTION=false`、
`VITE_CONSOLE_OPERATOR_ACCOUNTS_JSON`、`VITE_CONSOLE_TIMELOCK_ADDRESS`、
Timelock deployment blockを指定する
`VITE_CONSOLE_TIMELOCK_FROM_BLOCK`（1以上）の設定を確認する。
operator 設定は次の1変数を正本とし、address book の実値へ置き換える。

```bash
VITE_CONSOLE_OPERATOR_ACCOUNTS_JSON='[
  {"label":"Admin Safe","address":"0x..."},
  {"label":"Guardian Safe","address":"0x..."},
  {"label":"Allocator Safe","address":"0x..."}
]'
```

本番 guard は3つの標準 label、全 entry の非空 label と非zero address、address / label の
重複がないことを検査する。旧 `VITE_CONSOLE_OPERATOR_ADDRESSES` との併用は拒否する。
旧変数は Hosted Anvil staging / local の既存 env writer との互換入力に限り、
本番 promotion では使用しない。値は client bundle に入る公開設定であり、秘密鍵、
mnemonic、Safe owner 個人情報を含めない。
mainnet bindingのruntime readで`getMinDelay()`が
[`Parameters.md`](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY` と不一致、または
`EXECUTOR_ROLE(address(0)) == true`を検出した場合、consoleはTimelock artifact生成を停止する。
現在の generated binding が
mainnet 以外を指している場合、この check は失敗する。staging / local 用の失敗は
expected failure として扱い、production evidence では mainnet binding で再実行する。

### 5.1 Hosted Anvil / local Timelock E2E

devnet / local で Timelock 経路を検証するときは、EOA を Timelock holder として代用せず、
実際の `TimelockController` をデプロイする。Console の Timelock 経路は chainId と
`VITE_CONSOLE_TIMELOCK_*` の2変数から導出され、廃止済みの governance mode 切替変数は
使用しない。`DEVNET_*` の2変数は後述の deploy / handover script の入口 guard 専用であり、
Console の経路導出には関与しない。

```bash
DEVNET_EXPECTED_CHAIN_ID=31337
DEVNET_EXPECTED_MANIFEST_HASH=0x...
VITE_CONSOLE_TIMELOCK_ADDRESS=0x...
VITE_CONSOLE_TIMELOCK_FROM_BLOCK=1以上のdeploy block
```

`DEVNET_EXPECTED_MANIFEST_HASH` は `cast keccak < deployment-manifest.json` で取得する。
使用するmanifestが現在のConsole bindingと一致することを確認し、そのhashをreview evidenceへ
先に固定してから、承認済みのliteral値をPrepare / Finalizeの両方へ渡す。broadcast直前に
未レビューのmanifestからhashを算出してそのまま採用してはならない。

この節の機械照合部分は自動化済みで、anvilと`contracts/utils/local-stack.sh`の
bootstrapを済ませたうえで次の1コマンドで実行する。

```bash
RPC_URL=http://127.0.0.1:8545 CHAIN_ID=31337 \
  frontend/console/scripts/e2e-local-anvil-timelock-safe.sh
```

scriptは下記1–3をそのまま実行し、続いてConsole自身のモジュール（action / artifact
builder、Safe export、proposal照合、Timelock read）を使って下記4をassertする。
evidenceは`E2E_EVIDENCE_OUT`（既定`/tmp/jpydf-console-timelock-safe-e2e.json`）へ
JSONで残す。`CHAIN_ID=1`では起動時にfail-closedする。Console UI固有の表示だけが
手動確認として残る（下記5）。

短いdelayでの再現手順は次のとおり。

1. `DeployConsoleDevnetTimelock` で bootstrap delay 0 の実Timelockをデプロイする。
   `DEVNET_EXPECTED_CHAIN_ID` は接続先chain IDと完全一致させ、誤ったdevnetへのbroadcastを
   fail-closedにする。
   operator は proposer / executor / canceller を持ち、open executor と外部
   `TIMELOCK_ADMIN_ROLE` は持たせない。`VITE_CONSOLE_TIMELOCK_FROM_BLOCK` にはscriptの
   preflight blockではなく、CREATE transaction receiptのblockを使う。
2. Console E2Eでは `PrepareConsoleDevnetTimelockHandover` を使い、Vault
   `DEFAULT_ADMIN_ROLE` / `GOV_ROLE`、DToken owner、Strategy upgrader、
   InterestRouterForwarder ownerだけをそのTimelockへ移す。この専用scriptはcap、Vault運用値、
   treasury、PriceFeed owner、Strategy owner、Guardian / Allocator / Writeoff holderを変更しない。
   scriptはbroadcast前にmanifest hash、Timelock runtime、bootstrap delay、operator role、
   self-admin、open executor禁止を確認する。本番Day-1設定を同時に投入する場合だけ
   `PrepareDFGovernanceHandover` を使う。
3. `FinalizeConsoleDevnetTimelockHandover` で DToken / InterestRouterForwarder の
   `acceptOwnership()` をTimelock自身から実行し、最後にTimelock自身の `updateDelay()` で
   1秒以上の検証用delayへ上げる。同じ引数でもう一度実行し、変更なしのpost-handover
   verifierとして全branchのowner / role / upgraderを再読する。schedule transactionだけが
   採掘された途中状態では、同じoperation IDを再scheduleせず、既存operationをexecuteして再開する。
4. 同じpayload / salt / predecessorで以下をassertする（自動script実行分。手動での再確認は不要）。
   - schedule前は `unscheduled`、schedule直後は `waiting`
   - 実行可能時刻以降は `ready` となりexecute後は `done`
   - 別operationをschedule後、cancelすると `unscheduled` へ戻り、post-stateは変化しない
   - schedule artifactの `earliestExecutionAt` は `null`、execute / cancel artifactは
     on-chainで観測したtimestampを持つ
   - artifactのouter targetはTimelockであり、対象コントラクトを直接targetにした
     direct artifactを生成しない
   - schedule / execute / cancelをそれぞれtransaction 1件のSafe Transaction Builder
     互換JSONとして生成し、inner target / calldataがouter transactionへ使われない
   - Builder file checksumが自己整合し、そのfileから再構成したproposalがartifactと
     全項目一致する
   - proposal照合がouterへのinner payload昇格、schedule delayの差し替えで失敗する
     （chainId / Safe / value / operation / 複数transaction / `DELEGATECALL` / 未simulation /
     artifact改変の各拒否は `test:safe-transactions` が網羅する）
   - execute後にinner callのpost-stateが実際に変わっている（対象branchの `withdrawDelay`）
5. Console UIから、上記に含まれない表示のみを確認する。
   - `waiting` の間はexecuteのaffordanceが押せない
   - Pending Queueに保存済みartifactが表示され、browser reload後も再度開ける
   - stage / branch / operation IDがoperatorに識別可能な形で表示される

Hosted Anvil / localの標準chainId `31338` / `31337`には公式Safe Transaction
Serviceがないため、この節ではTimelock state transition、Builder file、pasted JSONの
非authoritativeなpayload比較までを確認する。pasted JSONを
`Safe transaction verified`へ昇格させてはならず、production同等のauthoritative
proposal lookup evidenceは次節のSepoliaで別途閉じる。

chainId 1 にだけ適用する mainnet delay / open executor 禁止 gate は、non-mainnetでは
E2E用の短いdelayを妨げない。ただしこの緩和をproduction evidenceへ流用してはならない。

### 5.2 Sepolia Safe proposal authoritative E2E

Safe互換artifact生成・proposal照合とHosted Anvil / local E2Eを追跡したIssue #1188は、
その受入条件の完了をもってcloseする。Issue #1201はSepolia（chainId `11155111`）へ
current sourceの実JPYdf一式をdeployし、新しいSafe / Timelockへ権限を移した環境で
Admin Consoleの機能E2Eを閉じる。認証済みsynthetic、GitHub OIDC workflow、incident
delivery / recoveryはproduction運用のIssue #694で追跡し、#1201のclose条件に含めない。

1. current sourceのJPYdf一式をSepoliaへdeployし、source commit、manifest、broadcast、
   deploy block、runtime codehashをevidence packageへ固定する。
2. 人間wallet ownerの新しいSepolia Safeと共通Timelockをdeployし、実JPYdfのrole / ownerを
   Safe、Timelock、Guardian、Allocator、Writeoffへ移管する。旧deployerの権限が残らないことを
   fixed blockで検証する。
3. Admin Consoleを実manifestへ直接bindingし、local executionを無効にした専用テストURLへ
   deployする。manifest内の実コントラクトをtest targetへ差し替えてはならない。
4. Consoleが生成したschedule / execute / cancelのBuilder fileをSafe UIへimportし、各proposalを
   outer transaction 1件として作成する。Safe URL / tx hashから公式read-only APIで取得し、
   payload、Safe-info version、
   zero gas / refund方針、current Safe nonce、versionに対応するdomainで再計算した
   EIP-712 Safe tx hashを含む全比較項目が一致して`Safe transaction verified`と
   なることを記録する。
5. Safe-info version欠落・不正形式、response `safeTxHash`欠落・別hash、
   各signed fieldの改変、never-settling lookup、
   通常同時2件超過をfault injectionし、fail-closed、physical work総上限3、
   Worker termination、bounded half-open probeによるhealthy recoveryを確認する。
   half-open probe自体もnever-settlingにし、dependency回復後の次probeで自動的に
   closedへ戻ることを確認する。
6. browser reload後にPending Queueから保存済みartifactを再度開き、同じSafe proposalを
   再照合できること、`isExecuted=true`かつ`isSuccessful=true`の場合だけ
   `実行済み(Safe)`へ遷移することを確認する。`isSuccessful=false`では
   `Safe実行失敗（未適用）`としてPending Queueに残ることを確認する。
7. Timelockのexecute lifecycleで実JPYdfのpost-stateが変わり、cancel lifecycleでは
   operationがunscheduledへ戻って対象stateが変わらないことをtransactionとfixed-block readで
   確認する。

**進捗記録（2026-07-26）**: Issue #1201で、専用Sepolia Safe / Timelock /
無害なtest target、公式Safe UIでのdirect / schedule / execute / cancel import、
公式proposalの全field・payload・EIP-712 hash照合、reload後の再開、fail-closed、
Timelock lifecycleを確認した。Safe APIの疎通、強制異常判定、通知文面・Issue運用も
preflightしたが、Issue #1245は手動起票・手動復旧であり、GitHub Actions自身による
test incident delivery / recoveryの証跡ではない。
結果と再現用の生証跡は
[`2026-07-25-Issue-1201-Sepolia-Evidence`](../../../engineering/historical-reviews/2026-07-25-Issue-1201-Sepolia-Evidence/README.md)
を正本とする。この結果はConsole / Safe / Timelock経路の先行証明だが、actual JPYdf contract、
current sourceからのdeployment、実manifest binding、実role / owner移管を使用していないため、
Issue #1201は **Pending** とする。

任意URLやoperator入力のservice baseをauthoritative sourceへ昇格させない。公式Safe APIの
認証credentialはbrowserへ渡さず、same-origin proxyで付与する。proxyはchainとread-only
endpointをallowlistし、operator session headerをupstreamへ転送しない。server側で
request rateと同時接続数を制限し、capacity拒否は`429`とbackoff guidanceを返す。
syntheticはSafe APIへ直接接続せず、synthetic専用identityでdeployed Admin Console proxyを
通す。URLはAdmin Console stack output、認証情報は固定名のSecrets Manager secretから
最小権限GitHub OIDC roleで実行時に取得し、GitHub variable / secretへ複製しない。
production CDK workflowの非機密設定も同様にGitHub variablesへ複製せず、
`/jpydf/production/config/`配下のSSM String parameterからallowlist付きで展開する。
SecureStringや未知のkeyはworkflowへ注入せず、OIDC deploy roleはこのpathのreadと
標準CDK bootstrap roleのassumeだけを許可する。credential値、Safe API key、
synthetic session cookie / authorizationはSecrets Managerにだけ保持し、SSMには
必要なsecret ARNだけを置く。
never-settling probeを物理的に終了し、次のhealthy probeで自動回復すること、
monitor bootstrap失敗でもescalation issueを作成できること、認証済みaggregate quota、
escalation recipient、workflow自身によるdelivery / recoveryを確認してからhourly scheduleを
有効にする。Safe API key自体をmonitorへ複製しない。これらproduction monitoring gateは
Issue #694で閉じる。

## 6. Day-2 Enhancements

Day-2 として追加してよいが、Day-1 gate の代替にはしない。

- Deep Safe App integration。
- Internal audit-log storage。
- Approval workflow / change request ticket integration。
- Searchable historical operation archive。
- Fine-grained per-operation RBAC beyond the auth gate。
