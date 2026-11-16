# Vault Buffer Shortfall / User Communication Runbook

## 0. 目的

この runbook は、CollateralVault の liquid buffer が redeem / claim 需要に対して不足したときに、ユーザーが「資金が消えた」「操作を何度もやり直す必要がある」と誤解しないようにするための事前準備と、発生時の運用・告知手順を定める。

正本となる仕様:

- [`CollateralVault.md`](../../../protocol/product/spec/CollateralVault.md): `redeem` / `WithdrawRequest` / `claim` / `bufferBalance` / `pendingWithdrawals`
- [`Frontend.md`](../../../protocol/product/spec/Frontend.md): `FRNT-FR-015` / `FRNT-FR-016` / `FRNT-ERR-005`
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](../../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md): Strategy 回収・writeoff・backstop の判断
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md): B/S 資金、backstop、Vault buffer の責務分離

## 1. ユーザー向けの基本説明

buffer shortfall は、必ずしも backing shortfall ではない。多くの場合は「Vault 内の即時支払用 buffer が一時的に薄く、資産が Strategy 側または protected backstop reserve 側にある」状態である。

ユーザー向け表現は次の 4 点を必ず満たす。

1. **即時受取とキュー入りを分ける**
   redeem の見込みは「今受け取れる額」と「queued claim になる額」に分けて表示する。

2. **queued claim はオンチェーンに残ると説明する**
   buffer 不足で支払われなかった額は `WithdrawRequest` として残る。ユーザーは同じ claim を再送する必要はなく、delay と buffer 回復を待つ。

3. **固定 ETA を言わない**
   `withdrawDelay` は最短待機時間であり、buffer 回復時刻ではない。Strategy 回収、backstop release、追加 deposit の状況に依存する。

4. **backing shortfall と混同しない**
   `backingRatio() == 1e18` なら full backing のまま一時流動性不足である。`backingRatio() < 1e18` の場合は別 incident として扱い、回復可否を断定しない。

避ける表現:

- 「すぐ受け取れます」「保証されています」「必ず X 時間後に受け取れます」
- 「失敗しました」だけで理由を出さない表示
- buffer shortfall を「損失」「破綻」と表現すること

## 2. 事前準備

### 2.1 UI / 公開情報

- user app の `/vault` は、redeem preview で `estimated instant payout` と `estimated queued amount` を分ける。
- queued claim 行は、`Waiting for delay` / `Buffer refill pending` / `Claim paused` / `Claim` を明確に表示する。
- buffer wait の説明には「request remains queued on-chain」「no resubmission is needed」を含める。
- Ops Dashboard は branch ごとに `bufferBalance`, `pendingWithdrawals`, `bufferTargetAmount`, `backingRatio`, paused flags を表示し、`pendingWithdrawals > bufferBalance` を critical alert にする。
- stats publisher は Ops Dashboard と同じ alert 判定を public stats に入れ、`source="publish-stats-s3"`, `ok=false`, `severity="critical" | "warning"` を持つ構造化 JSON log を CloudWatch metric filter / backend alarm SNS topic へ流す。`pendingWithdrawals > bufferBalance` は critical、`bufferBalance < bufferTargetAmount` は warning として外部通知対象にする。
- Admin Console は `claimShortfall = max(pendingWithdrawals - bufferBalance, 0)` と restart gate を表示する。

### 2.2 運用体制

launch 前に次を決めておく。

| 項目 | 準備 |
| --- | --- |
| Incident owner | buffer / claim shortfall の一次判断者 |
| User comms owner | status page / X / Discord / app banner 等の文面承認者 |
| ALLOCATOR executor | `sendToVault` / Strategy 固有回収 / `transferYieldToTreasury` 停止判断 |
| GUARDIAN executor | 必要時の `pauseRedeem` / `pauseClaim` / `pauseAllocation` |
| GOV / Timelock executor | `releaseBackstopToBuffer` / config 変更 |
| Treasury / Protocol retention Safe / Foundation operating-asset Safe | backstop 用 Underlying を用意できる wallet と allowance 手順。Foundation operating-asset Safe を使う場合は Foundation の個別承認・会計/税務証跡を含める |

### 2.3 alert 配送確認

- direct SNS test は topic から receiver までの配送だけを確認する。stats health log、metric filter、CloudWatch alarm を通った証跡として扱わない。
- production-ready 判定前に、`AWS_PROFILE=jpydf-staging JPYDF_STAGE=staging JPYDF_BACKEND_STATS_HEALTH_TEST_ACCOUNT_ID=<staging-account-id> JPYDF_BACKEND_STATS_HEALTH_TEST_CONFIRM=send JPYDF_BACKEND_STATS_HEALTH_TEST_RECEIVER=<confirmed-email> pnpm -C infra/cdk test:backend-stats-health-alert` を実行する。この staging 専用 command は明示した staging account 以外の caller を拒否し、stats publisher log group へ明確に test incident と識別できる critical health JSON log を送り、critical alarm の `ALARM`、warning alarm が `OK` のままであること、その後の critical alarm `OK` 復帰、および両遷移の SNS action history が `Succeeded` であることまで確認する。
- command が PASS しても human receipt は自動確認できない。指定 receiver が ALARM / OK 通知を実際に受信したことを別途確認する。
- subject の `CRITICAL-public-stats-health` / `WARNING-public-stats-health` と、本文先頭の environment・`ALARM` / `OK`・最初の operator action を確認する。後続の CloudWatch metric detail だけで incident 内容を判断しない。
- evidence には log stream、alarm history、受信者、受信時刻、resolve 時刻を残す。email address、webhook URL、token などの secret は残さない。

### 2.4 監視しきい値

| レベル | 条件 | 初動 |
| --- | --- | --- |
| Watch | `bufferBalance < bufferTargetAmount` | Ops alert。allocation / expected redeem volume を確認 |
| User-visible queue | redeem preview または tx 結果で queued amount > 0 | user app copy で通常の queue path として説明 |
| Claim shortfall | `pendingWithdrawals > bufferBalance` | critical alert。claim 原資の復旧計画を立てる |
| Backing incident | `backingRatio < 1e18` または `backingShortfall > 0` | Strategy incident runbook へ escalation |
| User flow pause | `pausedRedeem || pausedClaim` | public notice と再開条件を明示 |

## 3. 発生時の判断

### 3.1 まず分ける

1. `backingRatio() == 1e18` か。
2. `pendingWithdrawals > bufferBalance()` か。
3. `pausedRedeem` / `pausedClaim` / `pausedAllocation` は有効か。
4. Strategy から即時に戻せる idle / liquid amount はあるか。
5. protected `backstopBalance()` はあるか。claim / redeem 原資に使うには `releaseBackstopToBuffer` が必要か。

### 3.2 normal queue と incident の違い

| 状態 | ユーザーへの意味 | 運用 |
| --- | --- | --- |
| buffer は target 未満だが `pendingWithdrawals <= bufferBalance` | queue はあるが claim 原資は足りている | monitor。必要なら `sendToVault` |
| `pendingWithdrawals > bufferBalance` かつ backing は 100% | claim 待ちがある。資産消失ではなく liquidity refill 待ち | Strategy 回収 / backstop release / 追加 deposit を検討 |
| backing < 100% | valuation / loss / writeoff を伴う可能性 | Strategy incident runbook に従う。回復可否を断定しない |
| claim paused | claim は一時停止中。request は残る | public notice。再開条件を明示 |

## 4. 復旧手順

1. **状態を固定して観測する**
   `bufferBalance`, `pendingWithdrawals`, `backingRatio`, `backingShortfall`, `backstopBalance`, Strategy statuses を保存する。

2. **必要なら outbound を止める**
   buffer 回復まで `pauseAllocation` を使い、新たな Strategy 配分を止める。claim 原資が危険なら `pauseClaim`、ユーザーが誤解するほど queue が拡大する場合は `pauseRedeem` を検討する。

3. **Strategy から回収する**
   ALLOCATOR が `sendToVault` または Strategy 固有 emergency / claim 経路で、claim 済み・回収可能な Underlying を Vault へ戻す。非同期 Strategy は finalization / claim が必要で、queue 待ちだけで writeoff しない。

4. **backstop を使う場合は順序を守る**
   `backstopDeposit` は backing を補填する protected reserve であり、そのままでは claim / redeem 原資ではない。claim 原資に使う分だけ GOV が `releaseBackstopToBuffer` を実行する。

5. **claim coverage を確認する**
   `bufferBalance >= pendingWithdrawals` になったことを確認する。全額を即時 redeem に使い切らないよう、redeem 再開前に `bufferTargetAmount` も確認する。

6. **再開順序**
   原則として `Claim` → `Redeem` → `Deposit` → `Allocation` の順に再開する。claim 待ちユーザーを先に処理できる状態にしてから新規 redeem を増やす。

7. **事後確認**
   `WithdrawClaimed` events、pending queue の減少、Ops alert の解消、user app の `/vault` 表示を確認し、incident log に残す。

## 5. ユーザー告知テンプレート

### 5.1 通常の queue 発生

> 一部の redeem は即時支払用 buffer を超えたため、queued claim としてオンチェーンに記録されました。これは通常の Vault withdrawal 経路です。即時に支払われなかった分は `/vault` の Queued claims に表示され、claim delay 経過後、buffer が補充され次第 claim できます。同じ request を作り直す必要はありません。

### 5.2 claim delay 経過後も buffer 待ち

> claim delay は経過していますが、現在の branch buffer が queued claim 全額をまだカバーしていません。request はオンチェーンに残っています。運用側は Strategy 回収または backstop release により buffer を補充します。固定 ETA は出せませんが、進捗は Ops Dashboard と `/vault` の claim 状態で更新します。

### 5.3 claim / redeem pause

> Guardian により Vault の一部操作を一時停止しています。既存の queued claim は削除されず、オンチェーンに残ります。再開条件は、claim 原資、backing ratio、Strategy 回収状況の確認です。再開後、claim 可能な request から順に処理できます。

### 5.4 backing shortfall を伴う場合

> 現在、該当 branch の backing ratio が 100% 未満です。これは単なる buffer 待ちとは異なり、Strategy 回収・補填・writeoff 判断を伴う incident として扱っています。回復可能性や受取時刻は断定せず、確定したオンチェーン状態と対応方針のみ更新します。

## 6. 監査・事後レビューに残す証跡

- branch id / dToken / underlying / Vault address
- incident 開始 block / tx / 検知 source
- `bufferBalance`, `pendingWithdrawals`, `bufferTargetAmount`, `backingRatio`, `backingShortfall`, `backstopBalance`
- pause / unpause tx hash
- Strategy 回収 tx hash と requested / sent
- `backstopDeposit` / `releaseBackstopToBuffer` tx hash
- user comms の時刻・文面・掲載場所
- 解消条件を満たした block / tx

## 7. No-Go

次の状態では通常運用へ戻さない。

- `pendingWithdrawals > bufferBalance`
- `backingRatio < 1e18` の原因が未分類
- claim / redeem pause を解除する前に user comms が未更新
- Strategy 回収額と Vault 受領額が突合できない
- backstop reserve を claim 原資に使う判断が GOV / Timelock 手順なしに行われている
