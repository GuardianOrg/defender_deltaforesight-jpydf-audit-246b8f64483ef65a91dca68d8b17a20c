# Incident Notification Policy

## 0. 目的

この runbook は、JPYdf のオラクル、branch health、Vault / Strategy、
frontend / monitoring 配信面で異常が起きたときに、誰へ、どの深刻度で、どの
情報を通知するかを定める。

通知は「運用者が即応するための内部通知」と「ユーザーが現在許される操作を
理解するための公開告知」を分ける。内部 watch をそのまま user app の全画面
banner にしない。

正本となる仕様:

- [`Frontend.md`](../../../protocol/product/spec/Frontend.md): `FRNT-FR-031..035`,
  `FRNT-ERR-005`, `FRNT-ERR-006`
- [`Public-Analytics-Private-Monitoring-Architecture.md`](./Public-Analytics-Private-Monitoring-Architecture.md):
  公開分析 / private monitoring / Admin Control / public comms の責務境界
- [`Oracle.md`](../../../protocol/product/spec/Oracle.md): `ORCL-SEC-005`, `ORCL-EVT-*`
- [`Parameters.md`](../../../Parameters.md): oracle staleness、branch risk
  parameter
- [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](./Vault-Buffer-Shortfall-User-Comms-Runbook.md):
  buffer shortfall / queued claim の user comms
- [`Strategy-Incident-Liquidation-Safety-Runbook.md`](../../../protocol/operations/runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md):
  Strategy incident、writeoff、liquidation bot safety

## 1. 原則

1. **通知は状態機械として扱う**
   `triggered` / `acknowledged` / `escalated` / `resolved` を持ち、
   同じ原因の重複通知は alert key で束ねる。

2. **user impact と internal risk を分ける**
   source proposal、staleness 余裕低下、operator bot の dry-run failure は
   原則内部通知で足りる。branch shutdown、user flow pause、claim 原資不足、
   backing incident は user-facing 告知を検討する。

3. **oracle の共有レッグと branch-local レッグを分ける**
   branch-local collateral/USD・peg・canonical rate 障害は該当 branch の
   shutdown へ進む。JPY/USD は全 branch 共通依存であり、`JpyRateFrozen`
   から `MAX_JPY_FREEZE_DURATION` までの有界 soft-freeze として扱う。

4. **buffer shortfall と backing shortfall を混同しない**
   `pendingWithdrawals > bufferBalance` は claim liquidity の問題であり、
   `backingRatio < 1e18` は Strategy / backing incident として扱う。

5. **通知は on-chain action ではない**
   alert は自動 pause、cap 変更、source 差替、writeoff を実行しない。
   実行は各 runbook と権限 holder の明示判断に従う。

## 2. Severity

| Severity | 意味 | 内部通知 | Public 告知 |
| --- | --- | --- | --- |
| P0 Critical | protocol safety または user operation に即時影響。branch shutdown、backing incident、writeoff、claim/redeem 停止、JPY/USD freeze 長期化 | Pager / incident channel / Safe signer channel | 原則必要 |
| P1 Incident | 短時間で P0 化し得る状態。`JpyRateFrozen`、Strategy incident mode、claim 原資不足、emergency source switch | Pager または incident channel | user impact がある場合のみ |
| P2 Watch | しきい値接近・保留中操作・運用確認が必要。staleness 余裕低下、buffer target 未満、TCR / CCR 接近、source proposal pending | ops channel / dashboard | 原則不要 |
| P3 Info | 通常の状態変化・解消通知。source updated、proposal cancelled、monitor recovered | dashboard / digest | 不要 |

ACK 目安:

| Severity | ACK 目安 | Escalation |
| --- | --- | --- |
| P0 | 10 分以内 | ACK なしなら incident owner と backup owner へ再通知 |
| P1 | 30 分以内 | 進行中の user impact または P0 条件接近で P0 へ昇格 |
| P2 | 4 時間以内 | 同一条件が継続し P1 条件へ近づく場合のみ昇格 |
| P3 | 次回 digest | escalation なし |

## 3. 通知先と公開面

| 面 | 用途 | 含めてよい情報 | 含めない情報 |
| --- | --- | --- | --- |
| Pager / incident channel | P0 / P1 の即応 | branch、contract、tx hash、block、しきい値、必要 action、runbook link | private RPC URL、API key、未公開 Safe nonce |
| Private Operations Monitor | 発報履歴・現在状態 | alert key、status、resolved block、影響範囲、owner alias、ACK / escalation | signer 個人情報、secret、内部 chat permalink、raw private endpoint |
| Admin Control | 特権操作の準備・確認 | pause/source/writeoff の impact preview、public banner 反映状態 | 秘密鍵、raw private endpoint |
| User app banner | ユーザー操作に影響する状態 | 影響 branch、停止中/可能な操作、次の更新場所 | 内部 owner、未確定の補填可否、固定 ETA |
| Status page / official social | 広範な user impact | 短い状態説明、影響範囲、次回更新方針 | root cause の推測、未承認 action、機密情報 |

Dune Public Analytics は通知面ではない。Dune schedule / alert の成功・失敗を
P0 / P1 の発報源、ACK state、Status Page 更新の前提にしない。

Public 告知が必要な代表例:

- branch shutdown / urgent redemption 導線の有効化
- borrow / redeem / claim / deposit の pause
- `backingRatio < 1e18` または writeoff を伴う incident
- `pendingWithdrawals > bufferBalance` が claim delay 経過ユーザーに影響する状態
- JPY/USD soft-freeze が長期化し、source 差替または shutdown リスクがある状態
- user app / RPC / stats の全体障害により write UI を止める状態

Public 告知しない代表例:

- oracle source proposal の通常 timelock
- staleness threshold への接近だけで、まだ user operation へ影響がない状態
- buffer target 未満だが `pendingWithdrawals <= bufferBalance`
- operator bot dry-run failure で、第三者 keeper や protocol state に影響がない状態

## 4. Alert Key と Payload

alert key は同じ原因の再通知を束ねるため、次の形式を標準にする。

```text
<kind>:<chainId>:<branchOrGlobal>:<contractOrFeed>
```

必須 payload:

| Field | 内容 |
| --- | --- |
| `severity` | `P0` / `P1` / `P2` / `P3` |
| `status` | `triggered` / `acknowledged` / `escalated` / `resolved` |
| `kind` | `oracle_stale`, `jpy_freeze`, `branch_shutdown`, `buffer_shortfall`, `backing_incident`, `writeoff`, `pause`, `source_change`, `frontend_outage` など |
| `chainId` | 対象 chain |
| `branch` | branch-local なら branch id / dToken / underlying。JPY/USD など global は `global` |
| `contract` | 関連 contract address。未確定なら manifest key |
| `observedAtBlock` | 観測 block |
| `txHash` | event 起点なら tx hash。polling 起点なら空でよい |
| `currentValue` | 観測値 |
| `threshold` | 発報しきい値 |
| `userImpact` | 停止中の操作、影響を受ける画面 |
| `allowedUserActions` | 返済、claim、urgent redemption など継続可能な操作 |
| `action` | 次に人間が判断する action |
| `runbook` | 参照 runbook |
| `owner` | incident owner team alias。個人名ではなく duty rotation / team alias を使う |
| `ackDeadline` | ACK 期限の ISO timestamp |
| `ackDeadlineMinutes` | 発報時刻から ACK 期限までの分数 |
| `channels` | 配送 channel alias。実 URL / secret は含めない |
| `routeId` | 適用された routing rule |
| `publicMessageRequired` | `true` / `false` |

現行実装では `frontend/ops/src/lib/alertNotifications.ts` の
`buildAlertNotificationPayloads()` が `schemaVersion=1` の raw 通知 payload を
生成する。`frontend/ops/src/lib/alertRouting.ts` は severity / kind / alertId の
順に default routing policy を適用し、`owner` / `ackDeadline` / `channels` /
`routeId` を埋める。`frontend/ops export-alerts` は routed payload を JSON として
出力する。payload は delivery 直前の intermediate payload である。

`frontend/ops/src/lib/alertDelivery.ts` は file-backed state により、同じ
alert key の継続発報を抑制し、前回 active だった alert が消えた場合に
`status=resolved` payload を生成する。`frontend/ops notify-alerts` は
`OPS_ALERTS_STATE_PATH`（既定 `outputs/ops-alert-delivery-state.json`）を使い、
webhook 成功後、または `--write-state` 指定時だけ state を更新する。
Slack / SNS / PagerDuty 等への本番配送先と ACK / escalation 状態管理は
delivery / incident management layer の責務とする。

`frontend/ops/src/lib/alertChannelDelivery.ts` は channel alias を webhook 送信先へ
解決する。`OPS_ALERTS_CHANNEL_WEBHOOKS_JSON` は JSON object とし、値は直接 URL
文字列、または `{ "urlEnv": "...", "bearerTokenEnv": "..." }` の env 参照を
使う。実 webhook URL、token、chat permalink は runbook / spec / git tracked
file に書かない。bearer token は `OPS_ALERTS_WEBHOOK_BEARER_TOKEN` または
`bearerTokenEnv` で渡し、CLI 引数には渡さない。channel mapping が設定されている
場合、payload が参照する channel alias に送信先がないと `notify-alerts` は
fail-closed する。mapping が未設定かつ fallback `OPS_ALERTS_WEBHOOK_URL` も
未設定の場合、`notify-alerts` は state を更新せず配送候補 payload を stdout に
出す。
`frontend/ops check-alert-routing --require-gas-access-monitors` は routing / channel
mapping に加え、`OPS_EXTERNAL_RISK_HEALTH_JSON` または
`OPS_EXTERNAL_RISK_HEALTH_URL` が設定され、`OPS_EXTERNAL_RISK_HEALTH_REQUIRED_SECTIONS`
に `gasMarkets,accessMonitors` が含まれることを静的に確認する。Day-1 の gas fee
spike / access pressure 通知を external risk report に依存する環境では、
production delivery 前の設定確認に含める。
external risk report の freshness も静的に必須化したい環境では、
`frontend/ops check-alert-routing --require-external-risk-health-freshness` と
`OPS_EXTERNAL_RISK_HEALTH_MAX_AGE_SEC`（または
`--external-risk-health-max-age-sec <seconds>`）を併用する。この確認は任意であり、
live incident 対応時の機動性を落とさないため、production workflow 側で一律必須には
しない。
webhook post 成功時、`notify-alerts` summary は `webhookReceipts[]` に channel、
HTTP status、notification count、alert keys、redacted target を残す。実 URL /
token は receipt に含めない。post 失敗時も、`OPS_ALERTS_RECEIPTS_PATH` が設定されて
いれば `ok=false` の redacted failure receipt を append してから fail closed する。
failure receipt は調査証跡であり、delivery state の通知完了証跡としては扱わない。
post 失敗時は state を更新しない。
`OPS_ALERTS_RECEIPTS_PATH` または `--receipts-path` を設定した場合、同じ receipt
を JSONL として append する。handoff / retrospective ではこの receipt log と
delivery state / SLA audit を突合する。

### 永続化と DB 移行境界

Day-1 の alert delivery state / receipt は file-backed JSON / JSONL を正とし、
DB を必須依存にしない。worker の再起動、複数 worker、長期 retention、検索性、
監査証跡の集中管理が必要になった場合だけ Postgres 互換 DB を導入する。
DB 導入時の schema baseline は
`frontend/ops/db/alerting-postgres-schema.sql` とする。この schema は Neon Postgres
/ RDS Postgres のどちらにも載ることを前提に、Neon 固有機能へ依存しない。
既存 DB へ追従する場合は baseline 適用後に
`frontend/ops/db/migrations/*.sql` をファイル名順で適用する。migration は
`ops_alert_schema_migrations` に version を記録し、Postgres 互換 SQL だけを使う。

DB へ移行する場合も、以下を維持する。

- `alert_key` / `last_payload_hash` / `last_notified_at` / `notification_count` の
  delivery state semantics は file-backed state と一致させる。
- webhook receipt は success / failure の両方を保存するが、state 突合で
  `lastNotifiedAt` を満たすのは `ok=true` の success receipt だけとする。
- app banner / status page へ反映した public comms は
  `ops_public_comms_publications` と `ops_public_comms_publication_alerts` に、
  channel、status、source alert key、approved / published / expires timestamp、
  `public_url`、`public_text`、approved payload hash、source alert payload hash、
  redacted evidence を保存する。
  `source_payload_hash` が NULL の publication-alert row は legacy / 未補強証跡として
  扱い、public comms coverage では current alert payload を満たした証跡に数えない。
  `public_text` / `evidence` には query / fragment 付き URL、secret-bearing 文言、
  内部 routing alias を含めない。
  DB insert 前に `frontend/ops check-public-comms-publication` で承認済み publication
  JSON を検査し、approved payload hash と `dbRows`（SQL 文字列ではなく
  parameterized insert に渡す値セット）を生成する。
  `--state`（または `OPS_PUBLIC_COMMS_PUBLICATION_STATE_PATH`）を指定した場合は、
  source alert key が public comms 対象 alert と一致し、active 系 status では
  `triggered`、`resolved` / `removed` では `resolved` であることと、その時点の
  `lastPayloadHash` を `sourceAlertPayloadHashes` に固定することも検査する。
  `dbRows.opsPublicCommsPublicationAlerts[].sourcePayloadHash` はこの固定値を
  `ops_public_comms_publication_alerts.source_payload_hash` へ渡す。
  Day-1 file-backed 運用では `check-public-comms-publication` の出力を
  `OPS_PUBLIC_COMMS_PUBLICATIONS_PATH` の JSONL に保存し、handoff / retrospective
  で `frontend/ops check-public-comms-publications` を実行する。active な public
  comms 対象 alert は active 系 publication、resolved alert は `resolved` /
  `removed` publication の最新証跡で coverage され、かつ publication 側の
  source alert payload hash が現在の alert state と一致していなければ fail closed
  とする。
  DB へ取り込む前には `frontend/ops export-public-comms-db-insert-plan` で JSONL を
  table / column / row 形式の insert plan に変換する。この plan は SQL 文字列を
  含まず、既定では `sourcePayloadHash` 欠落を拒否する。legacy row を棚卸し目的で
  移す場合だけ `--allow-missing-source-payload-hash` を明示する。
- DB には raw webhook URL、bearer token、chat permalink、secret-bearing error を
  保存しない。保存対象は redacted target と redacted error のみとする。
- Neon / RDS のどちらでも同じ migration、backup、restore drill、network policy /
  RLS 方針を launch evidence に残す。DB を追加しても JSONL export は少なくとも
  rollback / restore drill 用に残す。

最小 env 例:

```json
{
  "ops-critical": {
    "urlEnv": "OPS_ALERTS_OPS_CRITICAL_WEBHOOK_URL",
    "bearerTokenEnv": "OPS_ALERTS_WEBHOOK_BEARER_TOKEN"
  },
  "ops-watch": {
    "urlEnv": "OPS_ALERTS_OPS_WATCH_WEBHOOK_URL"
  }
}
```

Day-1 default routing:

| Scope | Owner alias | ACK | Channel aliases |
| --- | --- | --- | --- |
| P0 default | `incident-commander` | 10m | `ops-critical`, `incident-command` |
| P1 default | `ops-duty` | 30m | `ops-alerts` |
| P2 default | `ops-duty` | 240m | `ops-watch` |
| P3 / resolved default | `ops-duty` | 1440m | `ops-resolved` |
| oracle / JPY freeze | `oracle-ops` | severity default | `oracle-ops` plus severity channel |
| vault buffer / backstop | `vault-ops` | severity default | `vault-ops` plus severity channel |
| strategy health / writeoff | `strategy-ops` or `incident-commander` | severity default / P0 10m | `strategy-ops` or `strategy-incident` |
| market health | `risk-ops` | severity default | `risk-ops` plus severity channel |
| frontend / data publish | `frontend-ops` | severity default | `frontend-ops` plus severity channel |
| public comms required | route-specific | severity default | include `public-comms` |

### 4.1 通知カタログ

以下を Day-1 の標準通知カタログとする。`Alert ID` は通知基盤・Ops dashboard・
incident log で使う運用識別子であり、component spec の requirement ID ではない。

| Alert ID | Trigger | Severity | Public | Primary source | Initial action |
| --- | --- | --- | --- | --- | --- |
| `ALRT-ORCL-001` | branch-local feed age >= 80% of staleness threshold | P2 | No | Chainlink `latestRoundData.updatedAt` / Day1 Parameter Manifest `PRM-ORACLE-*` | feed health と RPC を確認 |
| `ALRT-ORCL-002` | branch-local feed stale / invalid / revert risk | P1 | No, unless user operation is impacted | polling + `fetchPrice` dry-run | on-chain failure path を確認 |
| `ALRT-ORCL-003` | `ShutDownFromOracleFailure` / branch shutdown observed | P0 | Yes | TroveManager / PriceFeedProxy event, `shutdownTime` | user app block と urgent redemption 導線を確認 |
| `ALRT-ORCL-004` | JPY/USD shared feed age >= 80% of staleness threshold | P2 | No | shared JPY/USD `latestRoundData.updatedAt` | 全 branch 共通依存として早期確認 |
| `ALRT-ORCL-005` | shared provider `JpyRateFrozen` / `jpyFrozenSince > 0` | P1 | No initially | `JpyUsdRateProvider` state / event | freeze 起点と検知 block、全 active source の provider address 一致、代替 source 要否を記録 |
| `ALRT-ORCL-006` | shared JPY/USD freeze >= 6h and no recovery path | P0 | Prepare | provider `jpyFrozenSince`, source proposal state | oracle owner / GOV に escalation |
| `ALRT-ORCL-007` | shared JPY/USD freeze >= 12h または `JpyFreezeExpired` | P0 | Yes | provider state / event | public update を準備し、expiry 時は各 active branch の shutdown / `priceSource` / user action block を確認。provider 回復だけで既 shutdown branch が再開したと扱わない |
| `ALRT-ORCL-008` | JPY/USD provider freeze resolved | P3 / Recovery | No, unless public notice was posted | `JpyRateUnfrozen` / state | 全 branch の shutdown / `priceSource` を棚卸しし、既 shutdown branch の明示的な処置後にだけ public notice を解除 |
| `ALRT-ORCL-009` | `SourceProposed` | P2 | No | PriceFeedProxy event/state | timelock 期限と smoke-test owner を通知 |
| `ALRT-ORCL-010` | `SourceSwitchValidated.priceGuardBypassed == true` | P1 | No, unless user impact exists | PriceFeedProxy event | emergency bypass と価格差を監査 |
| `ALRT-ORCL-011` | dwstETH stETH/ETH 乖離 watch（`abs(stETH/USD − ETH/USD) / ETH/USD >= 0.5%`） | P2 | No | dwstETH oracle legs（stETH/USD・ETH/USD `latestRoundData`） | 乖離推移と両 feed health を確認（redemption band 1% への接近監視） |
| `ALRT-ORCL-012` | dwstETH stETH/ETH 乖離が redemption band 超過（`> 1%` = ORCL-FR-015 band 外） | P1 | No, unless user operation is impacted | dwstETH oracle legs（stETH/USD・ETH/USD `latestRoundData`） | redemption が market 価格へ切替わる状態。実勢 depeg・清算 / 償還・SP coverage を確認 |
| `ALRT-ORCL-013` | wstETH canonical rate（`stEthPerToken()`）が前回観測値から低下 | P1 | No initially | wstETH contract polling（前回値比較） | Lido slashing / negative rebase を確認し、担保価値の下方反映と清算リスクを評価。ALRT-PEG band / Guardian 対応を検討 |
| `ALRT-PEG-001` | active wrapper collateral peg monitor Watch band | P2 | No | off-chain peg monitor | source dispersion を確認 |
| `ALRT-PEG-002` | active wrapper collateral peg monitor Incident band | P1 | No, unless pause is executed | off-chain peg monitor | Guardian action を手動検討 |
| `ALRT-PEG-003` | active wrapper collateral peg monitor Critical band | P0 | Yes if exposure/user operation exists | off-chain peg monitor | cap freeze / source review / shutdown criteria を評価 |
| `ALRT-VAULT-001` | `bufferBalance < bufferTargetAmount` | P2 | No | CollateralVault read | allocation と redeem volume を確認 |
| `ALRT-VAULT-002` | `pendingWithdrawals > bufferBalance` | P1 | Yes if claim-delay users are affected | CollateralVault read | claim 原資復旧と user comms owner 招集 |
| `ALRT-VAULT-003` | `pausedRedeem || pausedClaim` | P0 | Yes | CollateralVault pause flags / events | user app banner と再開条件を確認 |
| `ALRT-VAULT-004` | `pausedDeposit` | P1, P0 if active public branch | Yes if public deposit/borrow path is exposed | CollateralVault pause flag / event | Borrow/Zapper UI block と reason を確認 |
| `ALRT-VAULT-005` | `pausedAllocation` | P2, P1 in active Strategy incident | No by itself | CollateralVault pause flag / event | outbound allocation 停止理由を記録 |
| `ALRT-BACK-001` | `backingRatio < 1e18` | P0 | Yes | CollateralVault `backingRatio` / PriceFeed effective price | Strategy incident runbook へ escalation |
| `ALRT-BACK-002` | `backingShortfall > 0` | P0 | Yes | CollateralVault `backingShortfall` | backstop / writeoff / recovery 分類 |
| `ALRT-STGY-001` | Strategy `estimatedTotalUnderlying` unavailable | P2 | No | Strategy view reads | bounded cache / external protocol health を確認 |
| `ALRT-STGY-002` | Strategy estimated loss > 0 | P1, P0 if backing drops | No initially | Strategy valuation / Vault backing | live valuation と二重 writeoff risk を確認 |
| `ALRT-STGY-003` | async pending valuation bps < 10000 | P1 | No, unless user flow paused | Lido / Etherfi strategy state | `pausedAllocation` と bot skip を確認 |
| `ALRT-STGY-004` | external venue incident / withdraw halt / bad debt report | P1, P0 if backing/user flow impacted | Case-by-case | external monitor + ops confirmation | incident mode、pause、bot skip |
| `ALRT-STGY-004` | external risk monitor source / coverage / freshness gap | P2 | No | `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL / `checkedAt` / required sections | external risk monitor endpoint、credential、scheduler、freshness を確認 |
| `ALRT-STGY-005` | `writeoffStrategyPrincipal` proposal or execution | P0 | Yes on execution, prepare on proposal | CollateralVault event / Safe queue | MCR 近傍 Trove と post-price を確認 |
| `ALRT-STGY-006` | `backstopDeposit` / `releaseBackstopToBuffer` | P2, P1 if resolving claim shortfall | No, unless public notice exists | CollateralVault event | claim coverage と notice 更新 |
| `ALRT-STGY-007` | writeoff Safe queue monitor unavailable | P2 | No | Safe queue monitor endpoint | Safe queue monitor endpoint、credential、scheduler を確認 |
| `ALRT-MKT-001` | TCR < CCR | P1 | No initially | TroveManager / ops snapshot | crisis-mode copy と borrow route を確認 |
| `ALRT-MKT-002` | TCR < SCR or SCR breach path | P0 | Yes if shutdown/user impact | TroveManager / ops snapshot | shutdown / urgent redemption path を確認 |
| `ALRT-MKT-003` | SP coverage below launch gate minimum | P1 | No initially | StabilityPool / launch gate config | SP top-up / JIT owner を確認 |
| `ALRT-MKT-004` | large redemption / redemption base rate spike | P2, P1 if user impact large | No initially | CollateralRegistry / event index | exit liquidity と borrow APR policy を確認 |
| `ALRT-MKT-005` | JPYdf/USDC pool price/depth outside launch envelope | P1 | Yes if user exit materially impacted | Uniswap v4 pool monitor | LP / treasury owner と user copy を確認。**上方向**（JPYdf > ¥1 相当）は実状態から即時 debt capacity を算出し、追加借入額・max upfront fee・実行後 ICR / LTV・Redemption exposure を manual / Safe 承認後、会社管理 Trove の debt increase と市場売却を実行。APR 変更は別判断とし、継続時は cap ramp 前倒し（`SYS-RISK-009` / ADR-007） |
| `ALRT-MKT-006` | market liquidity collector / report checker / pool monitor unavailable | P2 | No | 0xArchive collector、report checker、Uniswap v4 pool monitor | provider、credential、scheduler、ECS task、S3、最終成功 heartbeat を確認し、read-only liquidity plan を停止 |
| `ALRT-MKT-007` | active branch dToken cap usage >= 8,000 bps | P2, P1 if >= 9,500 bps | No initially | DToken `totalSupply` / `cap` | cap ramp runbook、SP coverage、Timelock queue 要否を確認 |
| `ALRT-MKT-008` | gas fee spike / blockspace congestion band | P2, P1 if incident/critical | No initially | external gas market monitor | gas fee envelope、keeper/relayer budget、user tx copy を確認 |
| `ALRT-MKT-009` | watched Trove redemption risk Watch / unknown read | P2 | No | `check-redemption-risk` / DebtInFrontHelper | debt-in-front、rate、comms owner を確認 |
| `ALRT-MKT-010` | watched Trove redemption risk Action / Incident | P1 | No | `check-redemption-risk` / DebtInFrontHelper | Layer A-D snapshot を添えて risk escalation |
| `ALRT-FRNT-001` | user app critical route synthetic failure | P1 | Yes if persistent | synthetic monitor | hosting/CDN/RPC を確認 |
| `ALRT-FRNT-002` | all RPC fallback down and write UI disabled | P0 | Yes | runtime health / app telemetry | banner、status page、provider escalation |
| `ALRT-FRNT-003` | subgraph stale beyond threshold | P2, P1 if values are visually mixed | No | subgraph sync monitor | RPC current value との表示分離を確認 |
| `ALRT-FRNT-004` | public stats JSON stale/unavailable | P2, P1 if user app shows stale as live | No, unless public data is misleading | stats publisher / CDN health | stale表示と publisher を確認 |
| `ALRT-FRNT-005` | official domain/link integrity or phishing incident | P0 | Yes | link monitor / security report | official notice と distribution freeze |
| `ALRT-FRNT-006` | frontend monitor / health report unavailable | P2 | No | runtime / link-integrity monitor endpoint | monitor endpoint、credential、scheduler を確認 |
| `ALRT-FRNT-007` | access pressure / traffic surge above capacity envelope | P2, P1/P0 if user flow impacted | Yes only when public impact is confirmed | CDN/WAF/API/RPC access monitor | CDN/WAF/rate limit/autoscale/RPC quota と public comms 要否を確認 |

### 4.2 Day-1 実装優先順位

Day-1 の最小実装は、すでに `frontend/ops` が表示している current-state alert を
外部通知へ送れる形にすることを優先する。

1. **P0 / P1 current-state alerts**
   `ALRT-ORCL-003`, `ALRT-ORCL-005..007`, `ALRT-ORCL-012..013`,
   `ALRT-VAULT-002..004`, `ALRT-BACK-001..002`, `ALRT-STGY-005`, `ALRT-FRNT-002`。

2. **P2 watch alerts**
   `ALRT-ORCL-001`, `ALRT-ORCL-004`, `ALRT-ORCL-011`, `ALRT-VAULT-001`,
   `ALRT-MKT-001`, `ALRT-MKT-009`, `ALRT-FRNT-003..004`。

3. **Event-indexed alerts**
   `frontend/ops` の EventData が取得できる範囲では、
   `StrategyPrincipalWrittenOff`, `BackstopDeposited`, `BackstopReleased`,
   large `Redemption`, `SourceSwitchValidated.priceGuardBypassed` を
   `deriveAlerts(snapshot, events)` に接続する。
   `SourceProposed` は `PriceFeedProxy.proposedSource/sourceProposedAt` の
   current-state polling で検知する。Safe queue proposal は Safe queue monitor、
   external venue incident は external risk health monitor で検知する。

4. **External-source alerts**
   active wrapper collateral peg monitor、Aave / Lido / Etherfi / Sky 外部 incident、official
   domain / link integrity は、外部 monitor の owner と evidence format を
   launch evidence で固定してから health report 入力として有効化する。

### 4.3 現行 `frontend/ops` との対応

現行 `frontend/ops/src/lib/alerts.ts` の `deriveAlerts()` は、Ops dashboard と
public stats 用の表示 alert を生成し、通知基盤へ渡せる補助 metadata
（`alertId` / `policySeverity` / `publicMessageRequired` / `action` /
`runbook` / `kind` / `sourceKey` / `currentValue` / `threshold`）を付与する。
metadata の実装上の正本は
`frontend/ops/src/lib/alertCatalog.ts` の `ALERT_POLICY` とし、
runbook の catalog と同期する。通知 payload への変換は
`frontend/ops/src/lib/alertNotifications.ts`、team alias / ACK / channel routing は
`frontend/ops/src/lib/alertRouting.ts`、手動 export は `frontend/ops export-alerts`
が担う。配送候補の dedupe / resolved 生成は `frontend/ops/src/lib/alertDelivery.ts`
と `frontend/ops notify-alerts` が担う。
`OPS_ALERTS_ROUTING_POLICY_JSON`（または `--routing-policy-json`）を使うと、
`defaultRoute`、`severityRoutes`、`kindRoutes`、`alertIdRoutes` の
`owner` / `channels` / `ackDeadlineMinutes` / `routeId` を本番環境ごとに
上書きできる。Slack / SNS / PagerDuty 等の実配送先は channel alias として
`OPS_ALERTS_CHANNEL_WEBHOOKS_JSON` に解決させ、duty rotation は routing policy の
`owner` と channel alias を環境変数として差し替える。
routing 解決は severity route を基点に、kind route と alertId route の channel
alias を重複排除して追加する。したがって P0 / P1 / P2 / P3 の既定 channel は
維持され、oracle / vault / frontend などの担当 channel が上乗せされる。
`public-comms` は `publicMessageRequired=true` の alert だけに含める。
`frontend/ops/src/lib/alertExternalStatus.ts` と
`frontend/ops/src/lib/alertDelivery.ts` の external status sync は
`OPS_ALERTS_EXTERNAL_STATUS_JSON` または `OPS_ALERTS_EXTERNAL_STATUS_URL` で
外部 incident management system から `alertKey` 単位の `acknowledged` /
`escalated` 状態を取り込み、状態変化時だけ schema v1 payload の
`status=acknowledged` / `status=escalated` を配送する。外部 incident URL は
query / fragment を落とし、URL 取得失敗は新規 alert 配送を止めず
`externalStatusError` として summary に残す。
`alertDelivery` は初回発報時の ACK 期限を `ackDeadlineAt` として state に固定し、
同じ alert が継続しても期限を再延長しない。`ackDeadlineAt` 到達時点で外部
`acknowledged` / `escalated` が未同期なら、自動で `status=escalated`
payload を一度だけ配送し、`externalStatus.actor=auto-escalation` として記録する。
`notify-alerts` の summary は `state.active`、`state.unacknowledged`、
`state.ackOverdue`、`state.escalated`、`state.publicMessageRequiredActive`、
`state.activeBySeverity` を出力し、運用者は配送結果だけでなく現在残っている
未ACK・期限超過・public comms 対象 alert を同じ出力で確認する。
保存済み state のみを確認する場合は `frontend/ops summarize-alert-state` が
`OPS_ALERTS_STATE_PATH`（または `--state`）を読み、同じ state summary を stdout
に出す。引き継ぎ・事後確認では `--now` に評価時刻を指定して ACK 期限超過を
再計算する。
`frontend/ops/src/lib/publicStatsHealth.ts` は `OPS_PUBLIC_STATS_URL` の外形チェック
結果から `ALRT-FRNT-004` を生成し、query / fragment を落とした URL を
`sourceKey` とする。`OPS_PUBLIC_STATS_STALE_THRESHOLD_SEC`（未設定時は
`OPS_STATS_STALE_THRESHOLD_SEC`、既定 300s）を超える `generatedAt` は stale と
する。`OPS_PUBLIC_STATS_USER_APP_SHOWS_LIVE=1` の場合、user app が live 値風に
見せている前提で P1 に上げる。
`frontend/ops/src/lib/statsPublisherHealth.ts` は
`OPS_STATS_PUBLISHER_HEALTH_JSON` または `OPS_STATS_PUBLISHER_HEALTH_URL` の
publisher job health report から同じ `ALRT-FRNT-004` を生成する。report は
`ok` / `success`、`status` / `jobStatus`、`stage` / `failureStage`、
`category` / `errorCategory`、`lastSuccessAt`、`publicStatsUrl` を受け取り、
public stats JSON が stale になる前に、snapshot fetch / stats build / S3 put /
stable key conditional write / CDN invalidation 等の failure stage を通知に残す。
error に URL が含まれる場合は secret-bearing path / query / fragment を伏せる。
`frontend/ops/src/lib/frontendSyntheticHealth.ts` は
`OPS_FRONTEND_SYNTHETIC_ROUTES_JSON` の外形チェック結果から `ALRT-FRNT-001`
を生成し、query / fragment を落とした URL を `sourceKey` とする。JSON は URL
文字列または `{ label, url, expectedText, publicMessageRequired }` object の配列
とする。`OPS_FRONTEND_SYNTHETIC_TIMEOUT_MS` は route ごとの取得 timeout で、
既定は 10,000ms とする。既定では public 告知 flag を立てず、
`OPS_FRONTEND_SYNTHETIC_PUBLIC_MESSAGE_REQUIRED=1` または route 単位の
`publicMessageRequired: true` により、persistent failure と判断済みの route を
public comms 候補へ上げる。
staging の private User app は Backend task role に限定した
`cloudfront-keyvaluestore:GetKey` で pinned CloudFront KeyValueStore の
`authorization` key を都度読み、`https://staging.jpydf.com` と完全一致する origin
だけへ Basic Authorization header を付与する。値を task definition、GitHub
variable / secret、CloudWatch log、他 origin へ複製してはならない。
同じ worker は Secrets Manager から `OPS_RPC_URL` を受け取り、
`OPS_FRONTEND_SYNTHETIC_EXPECTED_CHAIN_ID` と一致する `eth_chainId` および
現在の `eth_blockNumber` を 2 回まで probe する。HTML route が 2xx でも、この RPC probe が
連続失敗または chain 不一致なら `ALRT-FRNT-002` を生成する。RPC URL、query、credential は
summary、alert、CloudWatch log へ出力しない。
`frontend/ops/src/lib/frontendRuntimeHealth.ts` は
`OPS_FRONTEND_RUNTIME_HEALTH_JSON` または `OPS_FRONTEND_RUNTIME_HEALTH_URL` の
runtime health report から `ALRT-FRNT-002` を生成する。report は
`writeUiDisabled: true` と、`allRpcFallbacksDown: true` または
`rpcFallbacks[].ok` が全て `false` であることを P0 条件とする。
runtime health report endpoint が取得不能な場合は、UI 停止確定とは扱わず
`ALRT-FRNT-006` として monitor owner に fail-soft 通知する。
`notify-alerts` は snapshot RPC 取得に失敗した場合でも、外部 health alert が
存在すれば `observedAtBlock=0` の fallback snapshot で通知 payload を生成する。
`OPS_MIN_SP_COVERAGE_BPS`（または `--min-sp-coverage-bps`）を設定した場合、
active かつ public exposure のある branch の `spCoverage` が同 bps を下回ると
`ALRT-MKT-003` を生成する。閾値は launch operation config / evidence で
承認された値を入れ、未設定時は business target 未確定として発報しない。
`OPS_REDEMPTION_RATE_SPIKE_BPS`（または `--redemption-rate-spike-bps`）を
設定した場合、`CollateralRegistry.getRedemptionRateWithDecay()` が同 bps を
上回ると `ALRT-MKT-004` を生成する。大口 redemption event と同じ ID を使い、
exit liquidity、borrow APR policy、lowest-rate Trove 分布の確認へ送る。
`frontend/ops/scripts/check-redemption-risk.ts` は watchlist Trove の
debt-in-front / rate / SP coverage / redemption fee snapshot を読み、
Watch / unknown read を `ALRT-MKT-009`、Action / Incident を `ALRT-MKT-010`
に写像する。これは DF internal monitoring の通知であり、A 社への自動配送や
rate tx 実行ではない。
`frontend/ops/src/lib/safeQueueAlerts.ts` は `OPS_WRITEOFF_SAFE_QUEUE_JSON` または
`OPS_WRITEOFF_SAFE_QUEUE_URL` で渡された Safe queue JSON の `to + data` を
`CollateralVault.writeoffStrategyPrincipal` calldata として decode し、
未実行 proposal から `ALRT-STGY-005` を生成する。execution event と同じ ID だが、
proposal 段階では `publicMessageRequired=false` に上書きし、public comms は
実行前準備として扱う。
`frontend/ops/src/lib/poolLiquidityHealth.ts` は
`OPS_POOL_LIQUIDITY_HEALTH_JSON` または `OPS_POOL_LIQUIDITY_HEALTH_URL` の
JPYdf/USDC liquidity monitor report から `ALRT-MKT-005` を生成する。report は
`poolInitialized`、`liquidity/minLiquidity`、`priceBps/minPriceBps/maxPriceBps`、
`quotes.*.slippageBps/maxSlippageBps` を受け取り、launch operation evidence の
pool depth / sample sell-buy slippage と同じ観点で envelope breach を通知する。
MarketData stack の report checker は、共通 failure log、成功 heartbeat 欠落、
EventBridge `FailedInvocations` を別 alarm として同じ backend SNS topic へ配送し、
いずれも `ALRT-MKT-006` に写像する。failure log alarm は credential / SDK / S3 /
report policy を含む checker 全体の失敗を対象とし、heartbeat alarm は 5 分 period
を既定値とし、設定された `rate(N minutes)` period の 3 点中 2 点で成功が無い場合を
missing-data breaching として扱う。readiness check は標準名の MarketData stack を
自動検出し、`JPYDF_MARKET_DATA_ENABLED` が未設定または false でも、stack が存在すれば
3 alarm を検査する。collector の
0xArchive request は実リクエストを abort する 30 秒以下の deadline を持つ。
production-ready とする前に staging で各 alarm path の labeled test incident を作り、
ALARM / OK history、CloudWatch-to-SNS action 成功、意図した human receiver の受領、
resolve 時刻を secret / endpoint 無しで記録する。設定の存在や log 出力だけでは
delivery 検証完了としない。
`frontend/ops/src/lib/externalRiskHealth.ts` は
`OPS_EXTERNAL_RISK_HEALTH_JSON` または `OPS_EXTERNAL_RISK_HEALTH_URL` の external
risk report から `ALRT-PEG-001..003` と `ALRT-STGY-004` を生成する。report は
`pegMonitors[]` / `xautPeg` の XAUT/XAU `band`、`median1hBps`、
`sampleBps`、`dispersionBps` を [`Oracle.md`](../../../protocol/product/spec/Oracle.md)
`ORCL-TBD-003` の Watch / Incident / Critical band に写像する。さらに
`protocolIncidents[]` の Aave / Lido / Etherfi / Sky 等の active incident、
withdraw halt、bad debt、backing impact、user flow impact を Strategy health
incident として通知する。`gasMarkets[]` は execution gas / blockspace congestion
を `ALRT-MKT-008` に写像し、明示 `band` が無い場合は max fee gwei と
monitor-provided threshold（未指定時は watch 150 / incident 300 / critical
600 gwei）で分類する。`accessMonitors[]` / `trafficMonitors[]` は request rate、
error rate、p95 latency、saturation、rate-limit 比、queue depth を `ALRT-FRNT-007`
に写像し、capacity 80% で watch、閾値超過で incident、2x / saturation 近傍で
critical とする。URL は query / fragment を落とし、外部 source の
secret-bearing report URL を payload に残さない。
`OPS_EXTERNAL_RISK_HEALTH_REQUIRED_SECTIONS`（comma 区切りまたは JSON array）または
`notify-alerts --external-risk-health-required-section <section>` で
`pegMonitors` / `protocolIncidents` / `gasMarkets` / `accessMonitors` を必須化できる。
必須化した section が report から欠落した場合は、monitor 全体が HTTP 200 でも
domain 別の P2 alert（gas は `ALRT-MKT-008`、access は `ALRT-FRNT-007` など）を
出す。必須 section を指定したのに `OPS_EXTERNAL_RISK_HEALTH_JSON` /
`OPS_EXTERNAL_RISK_HEALTH_URL` が未設定の場合も、`notify-alerts` は同じ domain 別
P2 alert を出す。`OPS_EXTERNAL_RISK_HEALTH_MAX_AGE_SEC`（または
`notify-alerts --external-risk-health-max-age-sec <seconds>`）を設定すると、
report の `checkedAt` 欠落・不正値・期限切れ・60 秒超の未来時刻も同じ domain 別
P2 alert にする。freshness 上限を設定したのに
`OPS_EXTERNAL_RISK_HEALTH_JSON` / `OPS_EXTERNAL_RISK_HEALTH_URL` が未設定で、
必須 section も未指定の場合は、generic `ALRT-STGY-004` P2 として source 未設定を
通知する。
Day-1 で gas fee spike や access pressure をこの external risk report に依存する
環境では、少なくとも `gasMarkets,accessMonitors` を必須化し、freshness 上限も
設定して、監視 feed の schema drift / partial outage / stale publish を「正常」として
扱わない。
`frontend/ops/src/lib/linkIntegrityHealth.ts` は
`OPS_LINK_INTEGRITY_HEALTH_JSON` または `OPS_LINK_INTEGRITY_HEALTH_URL` の
official link / domain integrity report から `ALRT-FRNT-005` を生成する。
report は `checks[]` の `ok=false`、および `incidents[]` /
`phishingReports[]` の active report を受け取り、公式ドメイン、canonical
origin、hosting manifest、official social / docs link、phishing report を同じ
P0 security integrity incident として扱う。payload の `sourceKey` は URL の
query / fragment を落とし、token・wallet address・report query 等を通知へ残さない。
これは本番 incident management system そのものではないが、Day-1 通知の入力と
delivery adapter として再利用できる。

| 現行表示 alert | 対応 Alert ID | 備考 |
| --- | --- | --- |
| JPY/USD 共有フィードの age warning / critical | `ALRT-ORCL-004` | 80% warning と stale critical を policy P2/P1/P0 へ変換する layer が必要 |
| branch-local collateral/USD feed age warning / critical | `ALRT-ORCL-001`, `ALRT-ORCL-002` | stale 後の shutdown event は別途 `ALRT-ORCL-003` |
| `jpyFrozenSince > 0` | `ALRT-ORCL-005..007` | 経過時間で P1/P0 を分ける変換が必要 |
| `shutdownTime > 0` | `ALRT-ORCL-003` / `ALRT-MKT-002` | 原因分類は event / failed oracle address で補う |
| `backingRatio < 1e18` | `ALRT-BACK-001` | public 告知対象 |
| `pendingWithdrawals > bufferBalance` | `ALRT-VAULT-002` | claim delay 経過ユーザーがいる場合は public 告知対象 |
| `bufferBalance < bufferTargetAmount` | `ALRT-VAULT-001` | 内部 watch |
| Vault pause flags | `ALRT-VAULT-003..005` | user flow 影響で public 告知要否を判定 |
| Strategy estimate unavailable / estimated loss / async pending bps | `ALRT-STGY-001..003` | 外部 incident monitor と組み合わせて P1/P0 化 |
| Aave / Lido / Etherfi / Sky external incident / withdraw halt / bad debt | `ALRT-STGY-004` | `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL の `protocolIncidents[]` から取り込む |
| `TCR < CCR` / `TCR < SCR` | `ALRT-MKT-001`, `ALRT-MKT-002` | SCR breach / shutdown path は public 告知候補 |
| `spCoverage < OPS_MIN_SP_COVERAGE_BPS` | `ALRT-MKT-003` | 閾値は launch operation config / evidence と一致させる。未設定時は無効 |
| Safe queue の `writeoffStrategyPrincipal` calldata | `ALRT-STGY-005` | `OPS_WRITEOFF_SAFE_QUEUE_JSON` / URL から未実行 tx を検知。proposal 段階は public 告知準備 |
| writeoff Safe queue monitor unavailable | `ALRT-STGY-007` | Safe queue monitor 不達は P0 writeoff proposal とは扱わず、配送 job を落とさず P2 として通知 |
| `StrategyPrincipalWrittenOff` event | `ALRT-STGY-005` | dashboard / verify path で P0 public 告知候補として扱う |
| `BackstopDeposited` / `BackstopReleased` event | `ALRT-STGY-006` | recovery / claim coverage の notice 更新要否を確認 |
| large `Redemption` event | `ALRT-MKT-004` | 直近 block window 内、かつ 1,000万 JPYdf または total debt 5% 以上を watch |
| `redemptionRateWithDecay >= OPS_REDEMPTION_RATE_SPIKE_BPS` | `ALRT-MKT-004` | CollateralRegistry current-state polling。未設定時は無効 |
| JPYdf/USDC pool initialized / liquidity / price / slippage envelope breach | `ALRT-MKT-005` | `OPS_POOL_LIQUIDITY_HEALTH_JSON` / URL から外部 monitor evidence を取り込む |
| market liquidity collector / report checker / pool monitor unavailable | `ALRT-MKT-006` | 0xArchive timeout、checker failure、heartbeat 欠落、schedule failed invocation、pool monitor 不達を P2 通知し、market breach 確定とは分離する |
| gas fee spike / blockspace congestion band | `ALRT-MKT-008` | `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL の `gasMarkets[]` / `gasReports[]` から取り込む |
| watched Trove redemption risk Watch / unknown / Action / Incident | `ALRT-MKT-009..010` | `check-redemption-risk` の internal read-only watchlist。A 社自動配送・rate tx ではない |
| active wrapper collateral peg monitor Watch / Incident / Critical band | `ALRT-PEG-001..003` | `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL の `pegMonitors[]`（stETH/ETH 系列を含む）/ `xautPeg` から取り込む |
| dwstETH stETH/ETH 乖離 watch / band 超過・wstETH canonical rate 低下 | `ALRT-ORCL-011..013` | dwstETH oracle legs（stETH/USD・ETH/USD）と wstETH `stEthPerToken()` の current-state polling（ORCL-FR-015 monitoring） |
| access pressure / traffic surge / rate-limit envelope breach | `ALRT-FRNT-007` | `OPS_EXTERNAL_RISK_HEALTH_JSON` / URL の `accessMonitors[]` / `trafficMonitors[]` から取り込む |
| official link / domain integrity failure or active phishing report | `ALRT-FRNT-005` | `OPS_LINK_INTEGRITY_HEALTH_JSON` / URL から security monitor evidence を取り込む |
| frontend synthetic route failure | `ALRT-FRNT-001` | `OPS_FRONTEND_SYNTHETIC_ROUTES_JSON` の外形チェック。query / fragment は payload から除外 |
| all RPC fallback down and write UI disabled | `ALRT-FRNT-002` | runtime health JSON / URL、または read-only RPC の `eth_chainId` / `eth_blockNumber` synthetic probe から検知。snapshot RPC 失敗時も fallback snapshot で通知可能 |
| frontend runtime / link-integrity health report unavailable | `ALRT-FRNT-006` | monitor 不達は P0 確定 incident にせず、配送 job を落とさず P2 として通知 |
| public stats JSON stale / unavailable | `ALRT-FRNT-004` | `OPS_PUBLIC_STATS_URL` の外形チェック。query / fragment は payload から除外 |
| stats publisher job failure / health report unavailable | `ALRT-FRNT-004` | `OPS_STATS_PUBLISHER_HEALTH_JSON` / URL から failure stage / category / last success を通知 |
| `proposedSource != 0 && sourceProposedAt > 0` | `ALRT-ORCL-009` | current-state polling で timelock 確定可能時刻と smoke-test owner を通知 |
| `SourceSwitchValidated.priceGuardBypassed == true` event | `ALRT-ORCL-010` | PriceFeedProxy event index で emergency bypass と価格差監査を通知 |

未カバーで別実装が必要なもの:

- 外部 incident management system との ACK / escalation 状態同期

## 5. オラクル通知

### 5.1 Staleness 接近

| 条件 | Severity | 初動 |
| --- | --- | --- |
| branch-local feed の stale 残り時間が threshold の 25% 以下 | P2 | feed metadata、latest round、RPC / Chainlink status を確認 |
| JPY/USD の stale 残り時間が threshold の 25% 以下 | P2 | 全 branch 共通依存として incident owner へ早期通知 |
| invalid round / future timestamp / `answer <= 0` を polling が検知 | P1 | on-chain `fetchPrice` 経路で同じ障害になるか確認 |

staleness の正本値は [Day1 Parameter Manifest](../../../Parameters.md) の`PRM-ORACLE-*`を参照する。
monitor は strict `<` 判定を前提に、閾値ちょうどを fresh と扱わない。

### 5.2 JPY/USD soft-freeze

| 条件 | Severity | 初動 |
| --- | --- | --- |
| provider `JpyRateFrozen` または `jpyFrozenSince > 0` | P1 | provider address と凍結起点 timestamp を記録し、全 active source が同じ provider を参照する証跡と全 branch の価格取得状況を確認 |
| freeze から 6h 経過、かつ復旧見込みまたは source proposal がない | P0 | GOV / oracle owner へ escalation。代替 source と public comms を準備 |
| freeze から 12h 経過 | P0 | shutdown リスクを public 告知候補に上げ、次回更新時刻を決める |
| `JpyRateUnfrozen` | P3 / Recovery | freeze 中の価格・user impact・各 branch の shutdown / `priceSource` を記録し、既 shutdown branch の処置が決まるまで incident を close しない |
| provider `JpyFreezeExpired` / `MAX_JPY_FREEZE_DURATION` 到達 | P0 | 意図した human recipient への alert delivery、各 active branch の shutdown / `priceSource`、public 告知・user app block を確認。fresh 回復後も既 shutdown branch は pinned、expiry 未観測 branch だけが live rate を再開することを記録 |

JPY/USD freeze は即時 branch shutdown ではない。借入、清算、redemption が継続する
限り、public 文言は「価格換算の共通 FX レッグが last-good rate で一時継続中」
という状態説明に留め、資産毀損や補填を示唆しない。

### 5.3 Branch-local shutdown

| 条件 | Severity | 初動 |
| --- | --- | --- |
| `ShutDownFromOracleFailure` または Proxy shutdown 観測 event | P0 | 該当 branch の user app 新規操作 block、urgent redemption 導線、Ops dashboard 表示を確認 |
| `failedOracleAddr` が backing / rate provider / peg leg | P0 | Oracle と Strategy / Vault の両 runbook を参照し、root cause を分類 |

Public 告知には、該当 branch、停止する操作、継続可能な操作（全額返済、
claim、urgent redemption など）を必ず含める。

### 5.4 Source 差替

| 条件 | Severity | 初動 |
| --- | --- | --- |
| `SourceProposed` | P2 | 確定可能時刻、新旧 source、smoke-test 担当を通知 |
| `SourceProposalCancelled` | P3 | 保留中 alert を resolved にする |
| `SourceUpdated` | P3 | post-switch price と cache 更新を確認 |
| `SourceSwitchValidated.priceGuardBypassed == true` | P1 | emergency bypass として incident log に残し、価格ジャンプを監査 |

## 6. Peg Monitor 通知

active wrapper collateral の peg monitor は [`Oracle.md`](../../../protocol/product/spec/Oracle.md)
`ORCL-SEC-006` と資産別 activation package の band を使う。

| 条件 | Severity | 初動 |
| --- | --- | --- |
| Watch band | P2 | source health と venue dispersion を確認。on-chain action は原則なし |
| Incident band | P1 | Guardian が `pauseDeposit` / `pauseAllocation` を手動検討。redeem / claim は原則維持 |
| Critical band | P0 | cap freeze、source 差替レビュー、branch shutdown の前提条件を評価 |
| Recovery band が 24h 継続 | P3 / Resolved | Guardian / GOV の明示承認後だけ unpause |

peg monitor は自動 pause をしない。週末市場時間差や venue noise による誤検知を
人間が確認する。

## 7. Vault / Strategy 通知

| 条件 | Severity | 初動 |
| --- | --- | --- |
| `bufferBalance < bufferTargetAmount` | P2 | allocation と expected redeem volume を確認 |
| `pendingWithdrawals > bufferBalance` | P1 | claim 原資復旧計画。必要なら user comms owner を招集 |
| `pausedRedeem || pausedClaim` | P0 | user app banner と再開条件を確認 |
| `backingRatio < 1e18` または `backingShortfall > 0` | P0 | Strategy incident runbook へ escalation |
| `emergencyDisableStrategy` / Vault user flow pause | P1。user flow 停止なら P0 | liquidation bot skip、public impact、recovery owner を確認 |
| `writeoffStrategyPrincipal` proposal / execution | P0 | MCR 近傍 Trove、bot safety、public comms、post-price を確認 |
| `backstopDeposit` / `releaseBackstopToBuffer` | P2。claim 原資不足解消なら P1 resolved | claim coverage と buffer 再開順序を確認 |

writeoff は「損失確定」と「清算価格への反映」を伴うため、通知上は freeze や
回収とは別の P0 event として扱う。

## 8. Branch / Market Health 通知

| 条件 | Severity | 初動 |
| --- | --- | --- |
| TCR が CCR に接近 | P2 | borrow UI / rate policy / SP coverage を確認 |
| branch TCR < CCR | P1 | 新規 borrowing 制限・public copy の整合を確認 |
| SP coverage が launch gate の最低値を下回る | P1 | SP top-up / JIT / public risk copy を確認 |
| large redemption または redemption base rate 急上昇 | P2。user impact が大きければ P1 | exit liquidity、borrow APR policy、lowest-rate Trove 分布を確認 |
| branch shutdown | P0 | §5.3 と同じ |

## 9. Frontend / Data 通知

| 条件 | Severity | 初動 |
| --- | --- | --- |
| user app の主要 route が synthetic monitor で失敗 | P1 | official origin / CDN / wallet route を確認 |
| 全 RPC fallback が不通で write UI を停止 | P0 | user app banner、status page、provider escalation |
| subgraph stale | P2。現在値表示と混同する場合は P1 | RPC 現在値との表示分離を確認 |
| public stats JSON stale / unavailable | P2。user app が live 値風に表示する場合は P1 | stats publisher と cache header を確認 |
| official link / domain integrity failure | P0 | phishing / delivery incident として public comms |

## 10. Public 告知文言の規律

Public 文言は次を守る。

- 固定 ETA を出さない。次回更新予定は出してよい。
- buffer shortfall を「損失」「破綻」と表現しない。
- backing incident では回復可否や補填を断定しない。
- 停止中の操作と継続可能な操作を分ける。
- tx hash / contract address は必要に応じて出すが、private endpoint、API key、
  Safe nonce、内部担当者名は出さない。

最小 public template:

```text
<branch/global> で <状態> を検知しました。
現在停止している操作: <operations>
現在利用できる操作: <operations>
次の更新: <time or condition>
詳細は status page を確認してください。
```

`export-public-comms` の `draftText` はこの template を満たすが、`requiresOperatorApproval=true`
の承認前文面である。自動掲出はせず、固定 ETA・補填断定・内部 owner 名・secret を
含まないことを確認してから app banner / status page へ反映する。
status page へ反映する場合は `frontend/ops check-status-page-update` に
`OPS_STATUS_PAGE_UPDATE_JSON` または `OPS_STATUS_PAGE_UPDATE_JSON_PATH` を渡し、
承認済み update JSON を検査してから外部 status page bridge へ渡す。raw
`export-public-comms` report、未承認 draft、query / fragment 付き URL、
固定 ETA、補填保証、内部 owner 名、secret-bearing 文言は fail closed とする。
`--state`（または `OPS_STATUS_PAGE_UPDATE_STATE_PATH`）を指定した場合、
`sourceAlertKeys` が alert delivery state 上の public comms 対象 alert と一致する
ことも検査する。`status=resolved` の update は、対応 alert が state 上でも
`resolved` になっていなければ拒否する。
banner 解除や status page resolved 更新の直前には
`frontend/ops check-public-comms-clearance` を実行する。`--source-alert-key`
または `OPS_PUBLIC_COMMS_SOURCE_ALERT_KEYS_JSON` を指定した場合は、その対象が
state 上で public comms 対象かつ `resolved` になっていることを確認する。指定が
ない場合は、active な public comms 対象 alert が 0 件であることを確認する。
`frontend/ops check-alert-sla` は保存済み delivery state から ACK / escalation SLA
を監査する。active alert が `ackDeadlineAt` を超えて未 ACK の場合、または
`acknowledged` / `escalated` / resolved candidate の terminal timestamp が
deadline 後の場合は `ok=false` で exit 1 とする。handoff、日次レビュー、
incident retrospective では `breached[]` と `ackLatencySec` を incident log に
転記する。

## 11. Resolved 条件

Resolved にする前に、以下を確認する。

| 種別 | Resolved 条件 |
| --- | --- |
| Oracle stale / freeze | feed が fresh、`JpyRateUnfrozen` または正常価格取得、dashboard が green |
| Branch shutdown | shutdown 自体は不可逆なので alert は `resolved` ではなく `terminal` として閉じ、user app の shutdown state が正しいことを確認 |
| Buffer shortfall | `pendingWithdrawals <= bufferBalance`、claim UI が正常、必要な user comms 更新済み |
| Backing incident | 原因分類済み、backing / writeoff / backstop の post-state 記録済み。full recovery しない場合は residual risk を明示 |
| Frontend outage | synthetic monitor 復旧、runtime health pass、incident banner の解除または更新済み |

## 12. 証跡

incident log には最低限以下を残す。

- alert key / severity / status
- 検知時刻、block、tx hash、監視 source
- branch id / dToken / underlying / contract address
- 観測値、しきい値、差分
- ACK 者、owner、escalation 時刻
- public comms の有無、掲載場所、文面
- 実行した on-chain action と tx hash
- resolved / terminal 判定と根拠

証跡には private RPC URL、API key、未公開 Safe nonce、秘密鍵、個人情報を含めない。
