# Referral Campaign Activation Gate

> **位置づけ**: 有償 Referral campaign を user-facing にする前の activation gate。Referral の設計方針は [`Referral-Program-Policy.md`](../policies/Referral-Program-Policy.md)、on-chain 計装は [`../../spec/Zapper.md`](../../product/spec/Zapper.md)（§2 / `ZAP-EVT-001`）を正とする。
>
> 本 runbook は campaign accounting / ops / root / claim の gate であり、Core / Vault / Treasury / Stability Pool の会計を変更するものではない。

---

## 0. Activation Policy

有償 Referral campaign は、次の全項目が `PASS` になるまで公開しない。

| Area | Gate |
| --- | --- |
| Product | campaign terms、対象 action、対象期間、停止条件、問い合わせ owner が確定している |
| Budget | reward source、campaign cap、partner cap、per-wallet cap、未使用 budget の扱いが承認されている |
| Frontend | unknown / expired / paused code を referral なしとして表示し、valid code のみ `...AndReferral` に渡す |
| Subgraph / ledger | `txHash:logIndex` idempotency、branchId、referralCode、jpydfAmount、exclusion reason を記録できる |
| Anti-abuse | self-referral、same-cluster、即時 close、全額返済、liquidation、redemption、bad debt の除外方針が確定している |
| Distribution | reward asset、claim recipient mapping、root export、challenge evidence、tax / accounting owner が確定している |
| Legal / comms | reward terms、非保証表現、停止 / 変更権限、地域制限が review 済みである |

Day-1 launch は Referral campaign activation を必要としない。Referral の contract surface が存在していても、本 gate が未達なら frontend / marketing copy では有償 campaign を active と表示しない。

## 1. Campaign State

| State | 意味 | 次へ進める条件 |
| --- | --- | --- |
| `Draft` | 企画中。registry や UI に出さない | campaign packet が作成される |
| `EvidenceReady` | budget / abuse / root / claim evidence が揃った | Product、Ops、Finance / Accounting、Legal が承認する |
| `Approved` | 公開準備済み。まだ user-facing ではない | frontend / backend / subgraph release が production に反映される |
| `Active` | user-facing に表示し、valid code を送信してよい | monitoring が fresh、budget が cap 内、stop condition が未発火 |
| `Paused` | 新規 attribution 停止。既存分の review は継続 | pause reason が解消し、再承認される |
| `Closed` | 期間終了。root / claim / audit evidence のみ残す | final root export と close report が保存される |

`Paused` / `Closed` code は frontend で referral なしとして扱う。on-chain `bytes32` を送信しない。

## 2. Campaign Packet

campaign ごとに次の packet を作る。空欄がある場合は `Active` にできない。

| Field | 必須内容 |
| --- | --- |
| campaignId | off-chain 一意 ID。slug と `bytes32 referralCode` の対応を含む |
| partnerId / owner | partner 名、契約 owner、連絡先、停止連絡経路 |
| target action | 対象 action。初期は borrow open referral のみ。raw SP deposit は対象外 |
| eligible branch | 対象 branch。全 branch の場合も明示する |
| campaign period | start / end timestamp、timezone、早期停止条件 |
| reward formula | rewardable volume、rate、上限、丸め、minimum payout |
| budget source | growth / marketing budget、または Treasury retained revenue の別承認 evidence |
| budget caps | campaign cap、partner cap、per-wallet cap、daily / weekly cap |
| exclusion policy | §4 の除外条件を campaign-specific に上書きする場合の理由 |
| holding / clawback | minimum holding period、clawback window、支払停止条件 |
| reward distribution plan | reward asset、claim recipient mapping、root export schema、承認者 |
| legal / comms | terms URL、非保証表現、地域制限、tax / accounting owner |
| evidence links | registry snapshot hash、subgraph query / export hash、approval memo、close report |

## 3. Budget And Source Of Funds

### 3.1 Default

既定の reward source は protocol accounting 外の growth / marketing budget とする。この場合も、campaign cap と partner cap を明示し、Finance / Accounting owner が承認する。

### 3.2 Treasury / Protocol Revenue を使う場合

担保運用益を Referral に使う場合は、通常の campaign approval とは別に governance / ops evidence を必要とする。

- [Protocol-Revenue-Allocation-Policy](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md) の `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` bucket と budget cap
- SP additional rewards、buyback、backstop、Foundation retention との優先順位
- SPAdditionalRewardDistributor / SP additional rewards と同じ source-of-funds table での二重計上防止
- reward asset、recipient list、Merkle root / challenge evidence
- unused budget の戻し先と campaign stop 条項

### 3.3 No PIL

PIL は JPYdf liquidity incentive 用の InterestRouter / PILAllocator 経路であり、Referral reward source ではない。Referral に PIL を使う変更は本 gate では承認できない。

## 4. Anti-Abuse Policy

最低限、次は rewardable volume から除外する。

| Exclusion | 判定 |
| --- | --- |
| self-referral | borrower と partner / payout owner / controlled wallet が同一または実質同一 |
| same-cluster | 事前定義した wallet cluster、common funding、internal wallet、employee wallet |
| immediate close | minimum holding period 前の close / full repayment |
| full repayment | campaign が定める holding period 中に net debt が基準未満になった position |
| liquidation | liquidation された position。partial liquidation 相当の扱いは campaign packet で定義する |
| redemption | redemption により debt / position が campaign 条件を満たさなくなった場合 |
| bad debt / branch incident | branch shutdown、oracle incident、strategy writeoff、bad debt が関係する attribution |
| duplicate event | 同一 `txHash:logIndex`、reorg 後の重複、registry にない code |
| paused / expired code | registry 上 `Paused` / `Closed` / expired の code |

除外判定は off-chain campaign ledger で行う。contract state を書き換えない。判定結果には `eligibilityStatus` と `exclusionReason` を残し、root export に含める。

## 5. Ledger And Root Export

### 5.1 Ledger Fields

borrow referral ledger は最低限、次を保存する。

| Field | Source |
| --- | --- |
| chainId | deployment config |
| branchId | deployment manifest / Zapper address |
| txHash / logIndex | `ReferralDeposit` / route event |
| user | event |
| troveId | event |
| referralCode | event。`bytes32(0)` は対象外 |
| jpydfAmount | event。初期 rewardable volume の基準 |
| underlyingAmount / dTokenAmount | event |
| campaignId / partnerId | registry join |
| eligibilityStatus / exclusionReason | campaign ledger |
| payoutAmount / payoutAsset | root に入れる claimable amount / reward asset（既存 export field 名） |

### 5.2 Root Export

root export には次を含める。

- export generatedAt、source block range、registry snapshot hash、query hash
- claim recipient address、reward asset、amount、campaignId、partnerId
- eligible volume、cap 適用前後の値、rounding、minimum payout 判定
- exclusion summary、manual override がある場合の approver / reason
- approval memo link、campaignHash / sourceHash、Merkle root、challenge evidence

export は root 投稿前に Product / Ops / Finance or Accounting の 2 名以上で review する。担保運用益を使う場合は budget table / governance evidence を追加する。

## 6. Frontend / Backend / Subgraph Gates

有償 campaign を public enable する前に次を満たす。

| Component | Required |
| --- | --- |
| Frontend | URL / localStorage capture、registry validation、unknown / expired / paused 表示、tx preview、valid code のみ `...AndReferral` |
| Backend registry | slug normalization、canonical `bytes32` 発行、state 管理、campaign period、partner metadata |
| Subgraph | `ReferralDeposit` / Sky route event indexing、branchId 解決、`txHash:logIndex` idempotency、`bytes32(0)` 除外 |
| Analytics ledger | registry join、holding period、exclusion、cap、root export |
| Monitoring | stale subgraph / registry / stats の alert、budget cap approaching alert、pause propagation |

どれかが未達の場合、frontend は referral 付き transaction を送信しない。valid referral function が ABI に存在することは activation evidence にならない。

## 7. Stop Conditions

次のいずれかが発生した場合、campaign を `Paused` にする。

- campaign cap、partner cap、per-wallet cap の超過または near-cap alert の未対応
- registry / subgraph / analytics ledger の stale、欠損、reorg 不整合
- self-referral / same-cluster abuse の疑い
- claim recipient mapping review の失敗、sanctions / legal / tax review の blocker
- branch shutdown、oracle incident、strategy writeoff、bad debt、critical frontend bug
- terms / UI copy が実際の eligibility とずれている

pause 後は新規 attribution を停止し、既存 attribution は close report で支払可否を再判定する。

## 8. Evidence Package

`referral-campaign-activation-{campaignId}` として次を保存する。

| Evidence | 内容 |
| --- | --- |
| Campaign packet | §2 の全項目、承認者、承認日時 |
| Registry snapshot | slug、`bytes32 referralCode`、state、period、cap、hash |
| Frontend evidence | URL capture、invalid code、expired / paused code、tx preview の screenshots / test output |
| Subgraph / ledger evidence | source block、query hash、idempotency、branchId join、sample export |
| Budget evidence | source-of-funds table、cap、Treasury を使う場合の governance / Safe evidence |
| Anti-abuse evidence | exclusion rules、sample exclusions、manual review queue |
| Root / claim evidence | export hash、approval memo、Merkle root、challenge result、claim monitor |
| Close report | final spend、unused budget、exclusions、incidents、follow-up issue |

private key、raw RPC URL、未公開 Safe nonce、個人情報の不要な原本を evidence package に含めない。

## 9. Close Criteria For #658

#658 は次を満たせば Day-2 paid referral policy scope として閉じられる。

1. 本 runbook が `develop` に入り、[`Referral-Program-Policy.md`](../policies/Referral-Program-Policy.md) から参照されている。
2. reward source、Treasury 使用時の別承認、PIL 不使用、budget cap / partner cap / wallet cap、anti-abuse、holding / clawback、root / claim evidence が本 runbook に明文化されている。
3. 具体的な campaign 数値は campaign packet で freeze する運用になっており、未 freeze のまま public enable できない。
4. 未実装の frontend / subgraph / SP-sJPYdf attribution は #656 / #657 / #659 の個別 scope として残っている。

本 issue を閉じても、有償 campaign が active になったことを意味しない。実際の activation は campaign ごとの evidence package と承認で判断する。
