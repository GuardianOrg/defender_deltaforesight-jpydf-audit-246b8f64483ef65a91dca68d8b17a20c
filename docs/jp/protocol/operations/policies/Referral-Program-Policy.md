# Referral Program Policy

## 0. 位置づけ

本書は Referral（紹介）機能を、contract 計装、frontend / indexer、報酬原資、SP / sJPYdf 連携に分けて整理する設計方針である。

関連する正本:

- Zapper の on-chain 計装: [`../../spec/Zapper.md`](../../product/spec/Zapper.md) `ZAP-FR-002` / `ZAP-FR-004` / `ZAP-FR-014` / `ZAP-EVT-001`
- 計装（型・payload・indexing）の設計根拠: [`../../spec/Zapper.md`](../../product/spec/Zapper.md) §2
- 有償 campaign activation gate: [`../runbooks/Referral-Campaign-Activation-Gate.md`](../runbooks/Referral-Campaign-Activation-Gate.md)
- ledger / root export: [`Referral-Ledger-Export-Runbook.md`](../../../contributors/deltaforesight/operations/Referral-Ledger-Export-Runbook.md)
- 原資配分（担保運用益の用途配分・正本）: [`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md)
- Referral / SP 追加報酬の配布: [`Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md)
- Treasury routing: [`../../spec/Treasury.md`](../../roadmap/spec/Treasury.md)
- frontend gate: [`../../spec/Frontend.md`](../../product/spec/Frontend.md)

本書は #564 の結論を集約する。結論として、Referral は **Day-1 contract ABI には計測 surface だけを入れ、報酬 program は off-chain / Day-2+ gate に分離**する。Referral の不具合やキャンペーン判断が、Core / Vault / Treasury / SP accounting へ波及してはならない。

## 1. 決定

| 項目 | 方針 |
| --- | --- |
| Day-1 contract surface | Zapper open 時の `ReferralDeposit` / Sky route event のみ。storage 保存・Core / Vault 伝播・資金移動なし |
| Day-1 frontend | referral code の公開入力 / URL capture / paid campaign 表示は未有効。実装する場合も feature gate と registry / abuse policy を必須にする |
| 借入 attribution | `ReferralDeposit.referralCode` と `jpydfAmount`（ユーザー受領借入額）を基準にする。`entireDebt` / upfront fee 込み debt は使わない |
| SP 預入 attribution | 現行 `DFStabilityPool.provideToSP()` には referral surface がないため、raw SP deposit は on-chain referral 対象外 |
| sJPYdf / SP referral | sJPYdf or wrapper 設計が固まった後に別 issue / PR で追加。Core SP に referral 引数を足さない |
| 報酬原資 | [`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md) の Referral bucket。詳細は §7 |
| PIL との関係 | PIL（借入金利 25% の liquidity incentive）は Referral 原資に流用しない。PILAllocator / Merkl campaign とは別会計 |
| SP 追加報酬との関係 | SP 追加報酬と**同一原資（担保運用益）**。同じ budget table（Protocol-Revenue-Allocation-Policy §2）で bucket を分け、同じ yen/token を二重計上しない |

## 2. Contract 境界

### 2.1 Borrow referral

借入側 referral は Zapper で確定済みである。

| 項目 | 値 |
| --- | --- |
| 型 | `bytes32 referralCode` |
| referral なし | `bytes32(0)` |
| 対象 | `openTroveWithRawETHAndReferral` / `openTroveWithUnderlyingPermitAndReferral` / `openTroveWithUsdcAndReferral` |
| event | `ReferralDeposit(address indexed user, uint256 indexed troveId, uint256 underlyingAmount, uint256 dTokenAmount, uint256 jpydfAmount, bytes32 indexed referralCode)` |
| Sky route | `SkyUsdcRouteDeposit(..., bytes32 indexed referralCode)` |
| amount | `jpydfAmount` = user が受領する借入額 |

`referralCode` は accounting input ではなく measurement metadata である。Zapper 以外の production contract は referral を知らない。この境界により、referral registry / campaign / reward logic の bug は担保保管、債務、清算、償還に影響しない。

### 2.2 SP deposit referral

SP deposit は現時点では referral 対象にしない。

- `DFStabilityPool.provideToSP()` は Core SP 経路であり、referral 引数も event も持たない。
- Zapper は borrow open の UX router であり、SP deposit wrapper ではない。
- raw SP deposit へ referral を足すために Core SP ABI を変更しない。

SP deposit を Referral program に含める場合は、sJPYdf / wrapper / off-chain signed attribution のいずれかを別設計する。推奨は **sJPYdf or dedicated wrapper 側の event** とし、Core SP は変更しない。

## 3. Program Phase

| Phase | 内容 | Launch 判定 |
| --- | --- | --- |
| Phase 0: Measurement ready | Zapper event が存在し、ABI / spec / tests が固定されている | Day-1 contract ready |
| Phase 1: Private borrow campaign ledger | partner registry、URL capture、subgraph / analytics ledger、root input export を用意（台帳・tooling 整備）。実 payout は行わない | Day-1+ |
| Phase 2: Paid referral program | campaign terms、budget cap、anti-abuse、KPI、tax / legal review、ops dashboard、Referral distributor の root / claim gate を揃えて公開 | Day-2+ |
| Phase 3: SP / sJPYdf referral | sJPYdf / wrapper / SP additional reward policy と連携して SP deposit attribution を追加 | Day-2+ / depends on sJPYdf |
| Phase 4: Root automation | root 計算・検証・投稿を自動化し、手動 review 依存を下げる | 各 Referral distributor / legal / audit gate 後 |

Day-1 mainnet launch は Phase 0 で十分である。Phase 1 以降は growth 施策であり、protocol launch gate ではない。

## 4. Attribution 仕様

### 4.1 Borrow attribution

borrow referral ledger は次を key にする。

| Field | Source | 用途 |
| --- | --- | --- |
| chainId | deployment config | chain 分離 |
| branchId | emitting Zapper address -> deployment manifest | collateral branch 分離 |
| txHash / logIndex | event | idempotency |
| user | `ReferralDeposit.user` | borrower wallet |
| troveId | `ReferralDeposit.troveId` | open position |
| referralCode | `ReferralDeposit.referralCode` | channel / partner |
| jpydfAmount | `ReferralDeposit.jpydfAmount` | borrow volume |
| underlyingAmount / dTokenAmount | event | campaign analysis / branch mix |

同一 tx / logIndex は 1 回だけ集計する。`referralCode == bytes32(0)` は referral なしとして集計対象外にする。

### 4.2 Rewardable volume

初期の rewardable volume は `jpydfAmount` とする。理由は次の通り。

- ユーザーが実際に受け取る借入額であり、UI / campaign copy と一致しやすい。
- upfront fee 込みの `entireDebt` は event に含まれず、Zapper deploy 後に追加するには ABI / event 変更が必要。
- referral は acquisition measurement であり、debt accounting の正本ではない。

将来 `entireDebt`、残存 debt、期間加重 debt、net interest paid などへ変更する場合は、program ledger 側の policy update と、必要であれば Zapper event 改訂を別 PR にする。既存 event の意味を上書きしない。

### 4.3 Duration / clawback

paid campaign では、単純な open volume だけで即時支払いしない。最低限、off-chain ledger で以下を policy として持つ。

- minimum holding period
- immediate close / full repayment / self-referral の除外
- liquidation / redemption / bad debt event での支払い停止または clawback
- campaign budget cap / partner cap / per-wallet cap
- manual review queue

これらは protocol accounting ではなく campaign accounting であり、contract state に反映しない。

## 5. Referral Code Registry

frontend / backend で扱う人間向け code と on-chain `bytes32` は分ける。

| 表現 | 役割 |
| --- | --- |
| slug | URL / UI に出す短い code。例: partner name、campaign name |
| bytes32 referralCode | Zapper に渡す canonical ID |
| partnerId | off-chain registry の内部 ID |

推奨変換:

1. registry が slug を正規化する（lowercase、trim、許可文字セット、長さ上限）。
2. canonical `bytes32` は registry が発行し、frontend は registry から受け取った値だけを送信する。
3. frontend が任意 slug をその場で hash して paid campaign に使うことは禁止する。
4. unknown code は `bytes32(0)` として送信するか、transaction 前に referral なしとして明示する。

paid campaign で使う code は、campaign terms、partner owner、budget cap、有効期間、停止状態を registry に持つ。

## 6. Frontend / Subgraph / Backend Gate

Referral を user-facing にする前に以下を満たす。

| Area | Gate |
| --- | --- |
| Frontend | URL param / local storage / input の capture、sanitization、registry validation、unknown / expired code の表示、transaction preview での referral 表示 |
| Transaction | valid code がある場合だけ `...AndReferral` entrypoint を呼ぶ。ない場合は現行 no-referral entrypoint を維持 |
| Subgraph | `ReferralDeposit` / `SkyUsdcRouteDeposit` を index し、branchId と Zapper address を manifest から解決する |
| Backend / ledger | event idempotency、registry join、campaign period、budget cap、exclusion / clawback、root input export |
| Ops | campaign dashboard、partner report、fraud review queue、root approval / challenge evidence |
| Security | referral 文字列の XSS / homograph / address spoofing 対策、self-referral / same-cluster abuse 対策 |
| Legal / comms | reward terms、非保証表現、tax / accounting owner、campaign stop 条項 |

上記が未達の場合、frontend は referral 付き transaction を送信しない。ABI に関数が存在しても、program として active とは表示しない。

実装上の Day-1+ evidence package は `frontend/ops export-referral-ledger` が担当する。入力は subgraph 由来の `ReferralDeposit` / `SkyUsdcRouteDeposit` event JSON と partner / campaign registry JSON であり、rewardable volume は `ReferralDeposit.jpydfAmount` を正本にする。`SkyUsdcRouteDeposit` は route metadata evidence として取り込めるが、単体では `jpydfAmount` を持たないため rewardable から除外する。出力は `manual_review` / `excluded` row、partner / campaign summary、cap partial、holding-period 未検証、self-referral 未検証、liquidation / redemption clawback 未検証などの review flag を含む。これは Safe queue への支払指示ではなく、Referral distributor に投稿する root の検証 evidence である。

## 7. 報酬原資と会計

### 7.1 原資

Referral reward の原資は**担保運用益（Strategy yield）**とする。用途配分は [`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md) の単一 budget table が正本で、Referral は借入 / SP-deposit の 2 bucket として SP 追加報酬・Foundation と排他配分する（同じ yen / token を二重計上しない）。配布機構は [`Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md) が規定する。会社 marketing 予算は protocol 外の資金（[`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md) 所管）であり、本書の原資ではない。

### 7.2 承認・会計

担保運用益を Referral 原資に充てるには、別途 governance / ops evidence を要する（配分比率は budget table、payout 原資管理は [`Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md) が正本）。

- budget cap・partner cap・per-wallet cap・campaign period・stop 条項（[`../runbooks/Referral-Campaign-Activation-Gate.md`](../runbooks/Referral-Campaign-Activation-Gate.md)）
- reward asset・claim recipient mapping・root export / challenge evidence・税務 / 会計オーナー
- SP 配布 / Referral claim budget / backstop / Foundation retention との優先順位（Protocol Revenue / incident policy の TBD）

配布手段は **各 Referral distributor → root posting → challenge window → on-chain claim** とする。

### 7.3 PIL を使わない

PIL は borrowing interest の 25% を JPYdf liquidity incentive に向ける経路であり、Referral reward とは別目的である。Referral に PIL を流す変更は本書の範囲外であり、InterestRouter / PILAllocator の別 governance decision を必要とする。

## 8. SP / sJPYdf referral の方針

SP deposit を Referral に含める場合、raw `provideToSP()` に直接 referral を足すのではなく、sJPYdf / wrapper / distributor の設計で扱う。

推奨方針:

1. sJPYdf が ERC-4626 型になる場合、`depositWithReferral` または wrapper event を追加する。
2. SP deposit の rewardable amount は raw deposit amount ではなく、TWAB / minimum holding period を基準にする。
3. Referral bonus は SP 追加報酬と同一原資（担保運用益）だが、base SP reward とは別 bucket にする（budget table 上で分離）。
4. liquidation により SP deposit が担保化した場合の扱い（継続 / 停止 / clawback）を campaign terms に明記する。
5. raw SP direct deposit は referral なしでも常に利用可能にする。

この設計は統一トークン zJPYdf（[Roadmap](../../roadmap/Roadmap.md) `ROADMAP-CAND-006` / 設計調査 [zJPYdf](../../roadmap/initiatives/zjpydf/zJPYdf.md)。旧 sJPYdf 構想を統合）および SP reward policy の確定後に実装する。

## 9. Close Criteria for #564

#564 は Epic として、以下を満たせば閉じられる。

- Borrow referral の contract surface が `ZAP-EVT-001` と実装で固定されている。
- Program 方針として、Day-1 / Day-2 境界、報酬原資、SP / sJPYdf 境界、abuse gate が本書に整理されている。
- 未実装の作業が frontend / subgraph / ledger / SP-sJPYdf / reward-budget の個別 issue に分解されている。

#564 を閉じても Referral program が本番 active になったことを意味しない。本番 active は各 follow-up issue / PR の gate に従う。

## 10. Follow-up Work

| Issue | Area | 内容 |
| --- | --- | --- |
| #656 | Frontend | referral URL capture、registry validation、transaction preview、`...AndReferral` 送信 |
| #657 | Subgraph / analytics | `ReferralDeposit` indexing、branch 解決、campaign ledger |
| #658 | Backend / ops / reward budget | 有償 campaign の activation gate は [`../runbooks/Referral-Campaign-Activation-Gate.md`](../runbooks/Referral-Campaign-Activation-Gate.md) に分離。具体 campaign の registry / ledger / dashboard は #656 / #657 と campaign packet で管理 |
| #659 | SP / sJPYdf | sJPYdf or wrapper 側の referral event、TWAB / holding-period attribution |
