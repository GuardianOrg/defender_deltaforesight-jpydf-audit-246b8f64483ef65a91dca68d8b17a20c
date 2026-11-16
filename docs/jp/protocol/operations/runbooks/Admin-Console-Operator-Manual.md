# Admin Console Operator Manual

Updated: 2026-07-26

このマニュアルは、mainnet 稼働後に `frontend/console` で特権操作を準備し、
Safe または承認済み role holder へ引き渡すときの共通手順を定める。
操作ごとの判断条件は各運用 runbook / 承認済み change request を正とし、
この文書は画面操作・照合・停止条件を正とする。

> 掲載画像は実 TimelockController を使う Hosted Anvil staging（chainId 31338）で撮影した。
> 画面構成は本番と同じだが、アドレス、block、時刻、30秒 delay、Safe proposal 未照合状態は例示である。
> mainnet では画面上の chainId 1、承認済み address book、[Parameters](../../../Parameters.md) `PRM-GOV-COMMON-TIMELOCK-DELAY` の on-chain delay を使う。
> 画像の一部はタブ再編（概況 / 操作 / 保留 / 証跡 / 構成）前の旧タブ構成で撮影しているが、
> 操作カード内の入力・simulation・照合手順は同一である。staging 再撮影時に差し替える。

Admin の画面は「概況（操作前チェック）→ 操作（特権操作カタログ）→ 保留（横断キュー）→
証跡 → 構成（参照）」の 5 タブである。操作カタログは検索とカテゴリ（有効化 / Vault 設定 /
資金移動 / 停止・再開 / Strategy 構成 / 損失処理 / オラクル / 清算・Shutdown / 権限・Upgrade）で
対象 action を選び、右側に 1 操作カードだけを表示する。保留・証跡・構成は branch 選択に
かかわらず常に到達できる。

## 1. 絶対ルール

1. 本番画面の `3. <stage> ローカル実行` は無効でなければならない。Admin は秘密鍵を持たず、
   送信は Safe または承認済み role holder wallet で行う。
2. Safe へ calldata を手入力・転記しない。simulation 成功後に Admin が生成する
   **Safe Transaction Builder 互換 JSON**を import する。画面上の calldata は独立照合用であり、
   Safe transaction 作成への手動転記には使わない。
3. Safe proposal を作成しただけでは署名しない。Admin が公式 read-only API から proposal を取得し、
   `Safe transaction verified` になってから署名する。不一致・取得失敗・照合不能なら停止する。
4. `GOV` / `DEFAULT_ADMIN` / DToken owner / InterestRouter owner / Strategy upgrader の操作は、
   Safe から対象コントラクトを直接呼ばない。共通 Timelock の
   `schedule` → 待機 → `execute` を使う。
5. Timelock の `operation ID` は inner target / value / calldata / predecessor / salt から決まる。
   Execute / Cancel では Schedule と同じ値を再現する。operation ID が一致しなければ停止する。
6. 画面の短縮アドレスだけで判断しない。Admin artifact、Safe proposal、承認済み address book の
   checksum address を別担当者が照合する。
7. RPC、chainId、manifest、role / owner、simulation のいずれかが未確認なら transaction を準備しない。

## 2. 実行経路を選ぶ

個別 action ごとの手順書は作らず、次の3経路と §7 の例外チェックを組み合わせる。

| 経路 | 対象 authority / 代表操作 | 実行経路 | 使う手順 |
| --- | --- | --- | --- |
| T1: 共通 Timelock | Vault `GOV` / `DEFAULT_ADMIN`、DToken owner、InterestRouter owner、Strategy upgrader。`setCap`、設定変更、unpause、upgrade、role変更等 | Admin Safe → Timelock `schedule` → on-chain delay 待機 → Admin Safe → Timelock `execute` → 対象 | §4 |
| D1: 直接 holder | Guardian、Allocator、Writeoff、PriceFeed owner、Strategy owner 等 | 当該 Safe または承認済み role holder → 対象を直接 `CALL` | §5 |
| P1: permissionless / keeper | `refreshStrategyValuation`、`backstopDeposit` 等 | 承認済み funding wallet / keeper → 対象を直接 `CALL` | §5 と対象 runbook |

### 2.1 右上の「実行主体」

「実行主体」は wallet 接続ではない。選択した address を role / owner read と simulation の
`from` に使い、Admin 自身は署名・送信しない。本番 build には承認済み address book と同じ
checksum address を label 付きで固定し、selector には label と全アドレスを表示する。

Day-1 の標準対応は次のとおり。Safe Transaction Builder JSON は、選択した実行主体と同じ
Safe へ import する。

| 表示 label | 選択する操作 | 標準経路 |
| --- | --- | --- |
| `Admin Safe` | T1 の Schedule / Execute / Cancel、D1 の Writeoff / PriceFeed owner 操作 | T1 または D1 |
| `Guardian Safe` | Guardian / Strategy owner の pause、unpause、Strategy maintenance | D1 |
| `Allocator Safe` | Vault / Strategy の allocate、deallocate | D1 |

label は権限を付与しない。選択後に現在 block の badge と操作カードが必要 authority を
保有していることを確認する。`Admin Safe` で Allocator 操作を準備する等、予定 caller が
必要 authority を持たない場合は、別 Safe の署名で補うのではなく selector を正しい実行主体へ
切り替えて simulation と artifact 生成をやり直す。artifact 生成後に実行主体を変更した場合も
旧 artifact は使わない。

画面の role 表示を経路判断の根拠にしてよいのは、chainId と manifest が一致し、
現在 block の on-chain read が成功している場合だけである。holder が Safe か専用 wallet かは
mainnet address book を正とする。

Admin の操作カードは、同じ分類を Action Registry から `共通Timelock`（T1）、`直接Safe`（D1）、
`Proxy内蔵待機`（D1 のうち Oracle 通常 source 差替）、`権限不要`（P1）として表示する。
カードの経路表示と本表が食い違う場合は進めず、Registry / manifest の不整合として扱う。

## 3. 操作前の共通確認

change request / incident ticket を開き、最低限次を確定する。

- 対象 environment、chainId、branch、contract、関数、現在値、提案値、単位 / decimals。
- 実行理由、承認者、実行期限、rollback / cancel 条件、実行後に確認する view と event。
- 使用する Safe / wallet の checksum address と必要 threshold。
- Timelock 操作では Timelock address、`minDelay`、PROPOSER / EXECUTOR / CANCELLER holder。
- upgrade、writeoff、activation、oracle、pause は §7 の追加証跡。

Admin を restricted domain から開き、次を順に見る。

1. 右上の environment、実 chainId、現在 block。
2. 選択中の実行主体 label / checksum address、branch、role / owner badge。
3. 対象 branch の状態。`状態取得失敗`、想定外の `休止中` / `停止` は先に解消する。
4. 対象カードの現在値 → 提案値。入力後に別 branch へ移動しない。
5. T1 では execution が `Safe → Timelock`、D1 / P1 では承認済みの direct path であり、
   ローカル実行が無効であること。
6. 対象カードの権限表示。必要 authority と holder、実行経路、反映タイミング、復旧特性を
   change request と突合する。Timelock の PROPOSER / EXECUTOR / CANCELLER は workflow role
   であり、対象コントラクトの authority と読み替えない。
7. 保存済み artifact を再利用する場合は、`保留` の integrity が `artifact整合`（または
   `旧形式・経路整合`）であること。`simulation期限切れ`・`新しい同一操作あり`・
   `署名禁止・再生成` の artifact は署名対象にせず、現在 state で再生成する。

## 4. T1: 共通 Timelock 操作

以下は `dToken.setCap(100e18)` を代表例にする。他の T1 操作も同じ
Schedule / Execute / Cancel runner を使う。

### 4.1 Schedule artifact を作る

1. branch を選び、`操作` タブで対象 action を検索またはカテゴリから選択する。
2. `Schedule` を選び、承認済みの提案値を入力する。`setCap` の入力は表示単位であり、
   dToken の decimals を画面ラベルで確認する。
3. 次の preflight を確認する。
   - `Safe signer` が予定した Safe。
   - `PROPOSER_ROLE = held`。
   - `execution = Safe → Timelock`。
   - operation は `unscheduled`。既に `waiting` / `ready` / `done` なら、既存 operation と
     change request を突合するまで進めない。
4. salt は Admin が生成した値を使い、change request に保存する。依存 operation がなければ
   predecessor は `0x00…00`。手動変更した場合は理由を記録する。

![setCap の入力と Timelock preflight](./assets/admin-console-operator-manual/01-setcap-input-and-preflight.jpg)

5. `1. Timelock payload` を開き、次を記録・照合する。
   - `chainId = 1`、`value = 0`。
   - `Safe target = 共通 Timelock`。
   - wrapper は `schedule(address,uint256,bytes,bytes32,bytes32,uint256)`。
   - inner target、inner function、args、delay。
   - operation ID、salt、predecessor。
6. `2. Dual simulation` を実行する。次の2件が両方成功しなければ停止する。
   - inner call: sender = Timelock。
   - schedule wrapper: sender = Safe。

![Schedule wrapper、Safe互換JSON、二段階 simulation 証跡](./assets/admin-console-operator-manual/02-timelock-payload-and-simulation.jpg)

7. `Schedule Safe互換JSONをdownload` を押す。生成した artifact は同一 browser profile の
   補助台帳へ直ちに登録され、route 移動や reload 後も `保留` から照合を再開できる。
   別 browser / profile へ補助台帳を持ち出せないため、Safe proposal 照合までは同じ profile を使う。

### 4.2 Safe Transaction Builder へ import する

1. Safe で対象 network と承認済み Admin Safe のフルアドレスを確認する。
2. `New transaction` → `Transaction Builder` を開く。
3. JSON import を選び、Admin からダウンロードしたファイルを指定する。
   Safe の画面名が変更された場合は
   [Safe 公式 Transaction Builder](https://help.safe.global/articles/4180673514-transaction-builder)
   を確認し、手入力への切替で回避しない。
4. import 後、transaction が**1件だけ**であることを確認する。追加、並べ替え、編集をしない。
5. Safe 上で次を Admin artifact と照合する。

| Safe field | T1 Schedule の期待値 |
| --- | --- |
| Network / Safe | chainId 1 / 承認済み Admin Safe |
| Operation | `CALL (0)`。`DELEGATECALL` / MultiSend なら停止 |
| To | 共通 Timelock |
| Value | `0` |
| Data | Admin の `schedule(...)` wrapper calldata と完全一致 |
| Decoded call | inner target / value / calldata、predecessor、salt、delay が一致 |

6. proposal を作成するが、まだ署名しない。Safe transaction URL または Safe tx hash を取得する。

### 4.3 Safe proposal を署名前に機械照合する

1. 同じ browser profile で `保留` を開き、対象 card の `Safe proposalを照合` を押す。
   integrity が `artifact整合` / `旧形式・経路整合` 以外の card には照合・署名導線が
   表示されない。その場合は §4.1 から現在 state で artifact を再生成する。
2. file、artifact hash、generated payload hash、Builder checksum、operation ID、inner target を
   change request と照合する。
3. Safe transaction URL / Safe tx hash を入力し、`提案を取得・照合` を押す。
4. 次の全項目が一致し、`Safe transaction verified` になることを確認する。
   - chainId、Safe address / version、transaction count = 1、`CALL`、To / Value / Data。
   - canonical payload hash、zero gas / refund policy、current Safe nonce。
   - Safe version に対応する EIP-712 domain で再計算した完全な Safe tx hash。
   - Timelock stage、inner target / value / calldata、operation ID、predecessor、salt、schedule delay。

![生成済みartifactとSafe proposal照合入口](./assets/admin-console-operator-manual/03-safe-artifact-and-proposal-verifier.jpg)

![Safe proposal lookupの入力とhealth表示](./assets/admin-console-operator-manual/04-safe-proposal-lookup-health.jpg)

画像は proposal 作成前の `verification required` 状態である。本番では
`Safe transaction verified` の表示と比較結果を evidence に残す。貼り付けた
Transaction Builder JSON の一致は非 authoritative な補助確認であり、公式 proposal lookup の
代替として verified に昇格させない。

1項目でも mismatch、Safe Transaction Service の取得失敗、期待外の nonce / gas field が出た場合は
署名しない。artifact 自体が不正なら生成からやり直し、Safe proposal だけが不正なら破棄して
同じ未改変 artifact から作り直す。

lookup が失敗した場合は次を守る。

- 12秒 timeout 後に自動 retry しない。画面の physical / regular、oldest、circuit、
  stuck probe、deadline を evidence に残す。
- capacity 拒否は表示された retry-after まで待ち、bounded recovery probe を1回だけ行う。
- probe 自体が timeout しても次の cooldown 後に再試行可能であることを確認する。
- 同じ障害が続く場合は read-only 経路の monitor / escalation を確認し、標準操作を停止する。

### 4.4 Schedule を署名・実行する

1. 独立 reviewer が change request、Admin artifact、機械照合結果、Safe proposal を確認する。
2. Safe の必要署名数を集め、schedule transaction を実行する。
3. receipt 成功後に `保留` を更新し、同じ operation ID が `Timelock waiting` になることを確認する。
4. schedule tx hash、block、observed executable time、operation ID を記録する。

### 4.5 待機・Cancel 判断

- mainnet の on-chain delay を満たすまで、PC 時計や予定時刻だけで Execute 可能と判断しない。
  Admin の on-chain queue が同じ operation ID を `ready` と表示するまで待つ。
- 待機中に前提、承認、相場、incident 状態が変わった場合は Execute しない。
- 中止する場合は同じ inner payload / predecessor / salt で `Cancel` artifact を生成し、
  operation ID の一致、CANCELLER_ROLE、simulation、Safe proposal の機械照合を経て実行する。
  cancel 後は `unscheduled` を確認する。

### 4.6 Execute artifact を作成・実行する

1. 対象カードへ戻り、`Execute` を選ぶ。
2. Schedule と同じ提案値、inner target / calldata、predecessor、salt を復元する。
3. `operation = ready`、`EXECUTOR_ROLE = held`、表示された operation ID が Schedule evidence と
   完全一致することを確認する。
4. `1. Timelock payload` と `2. Dual simulation` を実行する。
   wrapper は `execute(address,uint256,bytes,bytes32,bytes32)` でなければならない。
5. `Execute Safe互換JSONをdownload` し、§4.2–4.3 を繰り返す。To は Timelock、
   Operation は単一 `CALL`、Data は execute wrapper である。

6. 独立 reviewer の確認後に署名・実行する。
7. receipt 後、次を確認して operation を完了する。
   - Timelock operation が `done`。
   - 対象 view が提案値。`setCap` なら `cap()` の raw value と表示単位を両方確認。
   - 期待 event と引数。`setCap` なら `CapUpdated(oldCap,newCap)`。
   - 予期しない event、別 branch の変更、user app / Ops 表示の不整合がない。

## 5. D1 / P1: Timelock を使わない操作

1. §3 の共通確認後、対象カードで現在値 → 提案値、role / owner、影響 preview を確認する。
2. `1. Calldata` を開き、chainId、target、value、function、args を記録する。
3. `2. Simulation` を実行する。sender は実行予定の Safe / wallet でなければならない。
4. `Safe互換JSONをdownload` する。holder が Safe でない場合も artifact を照合証跡として保存し、
   承認済み wallet UI で同じ To / Value / Data を使用する。
5. Safe を使う場合は §4.2–4.3 と同じく JSON import → proposal 作成 → Admin 機械照合 →
   署名の順に進む。direct operation の To は対象コントラクトであり、Timelockではない。
6. receipt 後に対象 view と event を確認する。

Admin の role badge が `missing` でも artifact を生成できる場合があるが、その signer では実行できない。
別 signer へ安易に切り替えず、承認済み holder と address book を確認する。

## 6. 操作カタログ

操作はすべて `操作` タブのカタログにあり、カテゴリと検索で到達する。

必要権限フィルターの初期値は `自分の権限` とし、選択中の実行主体が保有する直接 role / owner、
Timelock workflow role、権限不要操作を表示する。owner / pending owner を対象選択後に判定する操作、
または権限 read が未完了・失敗した操作は誤って除外せず、その状態を一覧に表示する。
一覧の権限表示は到達支援であり、対象状態・simulation を含む最終判定は操作カードで行う。

| 操作カタログのカテゴリ | 主な action | 経路 | 追加確認 |
| --- | --- | --- | --- |
| Vault 設定 | `setCap` | T1 / DToken owner | decimals、`totalSupply` / current cap、引上げ・供給制限の意図、cap ramp 承認 |
| Vault 設定 | `setBufferConfig`、`setWithdrawDelay`、`setTreasury`、`setAllocatorConfig` | T1 / GOV | Parameters、buffer / claim、宛先、cooldown |
| 停止・再開 | `pauseDeposit/Redeem/Claim/Allocation` | D1 / Guardian | incident 範囲、継続する user flow、告知 |
| 停止・再開 | `unpauseDeposit/Redeem/Claim/Allocation` | T1 / GOV | 回収・補填・claim 原資・再開順序 |
| Strategy 構成 | `addToWhitelist`、Strategy add / update、valuation max age / invalidate | T1 / GOV | weight 合計、cap、enabled、valuation、incident runbook |
| Strategy 構成 | `invalidateStrategyValuationCache`（WRITEOFF 直接経路） | D1 / Writeoff | incident-ready（対象 strategy disabled または allocation pause 中）のみ。GOV 経路と証跡を区別 |
| Strategy 構成 | `removeFromWhitelist`、`emergencyDisableStrategy`、`removeStrategy` | D1 / Guardian | pause 範囲、回収は別操作、remove 前の principal / assets |
| 権限・Upgrade | Strategy / DToken / PriceFeedProxy / InterestRouterForwarder ownership 操作 | T1 または D1 / 表示された owner・pending owner | current / pending owner、accept 順序、holder separation。§7 R1 |
| 権限・Upgrade | Timelock `grantRole` / `revokeRole` / `updateDelay` | T1（inner target = Timelock 自身） | revoke 前に同じ role の別 holder を on-chain 確認。minDelay は 0 秒禁止・mainnet は承認済み値と一致。PROPOSER / EXECUTOR / CANCELLER 構成、§9 即時停止条件との整合 |
| 金利ルーティング | `setRecipient` | T1 / InterestRouter owner | 現 recipient・pending owner・保有 JPYdf 残高。recipient 変更は PIL activation package の明示承認後（`route()` は permissionless） |
| 損失処理 | `writeoffStrategyPrincipal` | D1 / Writeoff | 回収不能額、`minBackingRatioAfter`、追加 markdown |
| 資金移動 | `sendToVault` | D1 / Allocator | venue別回収状態、pending request、requested / 受取額 |
| 資金移動 | `sendProfitToVault` | D1 / Allocator | 実現利益のみ push・principal 不変。対象 strategy の realizedYield と実受取額 |
| 資金移動 | Strategy owner 緊急回収（`emergencyWithdraw`、`emergencyWithdrawFromAave`、`emergencyWithdrawFromERC4626`） | D1 / Strategy owner (Guardian) | 宛先 Vault 固定。Base の idle 回収は principal 不変、venue 直送は原子実行。incident runbook の kind 別判定 |
| 資金移動 | `sweepRewardToken` / `claimAaveRewards` | D1 / Strategy owner (Guardian) | 非 position トークンのみ・treasury 固定宛先。underlying / position トークンは対象外 |
| 資金移動 | `allocate`、`transferYieldToTreasury` | D1 / Allocator | post-buffer、cap remaining、宛先、運用 runbook |
| 資金移動 | `releaseBackstopToBuffer` | T1 / GOV | 解放額、claim 原資、backing への影響 |
| オラクル | `proposeSource` → 待機 → `confirmSource` / `cancelSourceProposal` | D1 / PriceFeedOwner | §7 O1 |
| 有効化 | allowlist → metadata bind → Vault underlying bind | T1 | §7 A1 |
| 権限・Upgrade | Vault / dToken / Strategy upgrade、`setUpgrader`、role grant / revoke | T1 または表示された owner path | §7 U1 / R1 |
| 清算・Shutdown | `batchLiquidateTroves`（スキャン内蔵）、`shutdown` | P1 / permissionless | §7 H1、simulation、SP offset / redistribution 影響 |
| Strategy 構成 | `refreshStrategyValuation` | P1 / permissionless | 対象 strategy、読取結果、event |
| 資金移動 | underlying `approve` → `backstopDeposit` | P1 / permissionless（funding wallet） | token、amount、allowance、補填判断 |

表は経路選択用であり、risk / incident / activation の承認条件を置き換えない。

## 7. 例外チェック

| ID | 対象 | 共通手順への追加 |
| --- | --- | --- |
| O1 | Oracle source 差替 | PriceFeedProxy 内蔵 delay を使う。提案 source、応答・価格、実行可能時刻を確認する。`confirmSourceEmergency` は価格乖離 guard だけを bypass し、delay と smoke test を省略しない。共通 Timelockとの二重化を前提にしない。 |
| A1 | inert branch activation | allowlist → dToken metadata bind → Vault underlying bind の one-shot 順序を守る。既存 supply、既存 binding、oracle、risk gate を確認し、`setCap` 単独で稼働扱いにしない。 |
| U1 | upgrade | storage layout diff、implementation bytecode / codehash、検証済み source、rollback を別 reviewer が承認する。汎用画面で `upgradeToAndCall` を作らない。 |
| R1 | role / owner change | 新旧 holder、acceptOwnership、threshold、last admin / GOV lockout を確認する。renounce は Admin 画面から行わない。 |
| H1 | pause / emergency disable / writeoff / shutdown | incident commander、影響範囲、guard、ユーザー告知、回収・補填・再開順序を記録する。緊急性を理由に simulation と署名前照合を省略しない。 |

## 8. 完了証跡

change request / evidence package に次を残す。raw RPC URL、API key、Safe signer の秘密情報は残さない。

```text
Environment / chainId:
Admin build commit / manifest hash:
Operator / independent reviewer:
Branch / target contract / function:
Execution route (T1 / D1 / P1):
Current value / proposed value / raw args:
Simulation block / result:
Artifact hash / Safe batch checksum:
Generated / proposed payload hash:
Safe URL / Safe version / Safe tx hash / nonce:
Safe proposal verification result / diff:
Safe lookup physical / regular / oldest / circuit / stuck probe:
Safe isExecuted / isSuccessful / on-chain tx hash:
Timelock operation ID / predecessor / salt / delay:
Schedule tx / block / observed executable time:
Execute or Cancel tx / block:
Post-state block / view result:
Expected event / decoded args:
User app / Ops readback:
Incident or change request:
Known deviation:
```

## 9. 即時停止条件

- chainId、branch、manifest、Safe / wallet、Timelock、target の不一致。
- RPC health、role / owner、現在値、simulation の取得失敗。
- Safe import が1 transactionの単一 `CALL` にならない。
- Admin が公式 read-only API から proposal を取得できない、または
  `Safe transaction verified` にならない。貼り付け JSON の一致だけでは進めない。
- Safe version、署名対象 gas / refund fields、nonce、再計算 EIP-712 hash が期待と一致しない。
- Safe lookup が timeout / capacity 拒否 / circuit open / stuck probe となり、所定の recovery と
  escalation で健全性を回復できない。
- operation ID、salt、predecessor、inner calldata が Schedule evidence と一致しない。
- mainnet Timelock が承認済み delay、closed executor、承認済み role holder の想定と異なる。
- `isExecuted=true` かつ `isSuccessful=true` でない proposal を実行済みとして扱おうとしている。
- proposal 作成後に change request の前提、risk、incident 状態が変わった。
- post-state / event が期待と一致しない。

停止後は artifact を編集しない。artifact 自体または操作の前提が不正なら新しい artifact と
evidence を作る。Safe proposal だけが不正で artifact が未改変・有効なら、proposal を破棄し、
同じ artifact から作り直す。既に Schedule 済みなら必要に応じて Timelock を cancel する。
