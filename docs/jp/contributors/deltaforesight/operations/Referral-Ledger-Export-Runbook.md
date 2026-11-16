# Referral Ledger Export Runbook

## 0. 目的

Referral paid campaign を production-active にする前に、subgraph event と partner / campaign registry を突合し、Referral distributor の root 投稿前 review 用 evidence package を作る手順を定義する。

本 runbook は #657 の backend / analytics ledger scope に対応する。claimable amount を確定するものではなく、root 投稿・challenge・税務/会計・不正確認の前段 evidence を作る。

## 1. 入力

### 1.1 Event input

`frontend/ops export-referral-ledger` は subgraph 等から取得した JSON を `--events` で受け取る。

形式は配列、または `{ "events": [...] }`。

```json
{
  "events": [
    {
      "source": "ReferralDeposit",
      "chainId": 1,
      "branchId": 1,
      "collSymbol": "dUSDC",
      "blockNumber": "12345678",
      "timestamp": "1800000000",
      "transactionHash": "0x...",
      "logIndex": 12,
      "user": "0x...",
      "troveId": "42",
      "referralCode": "0x...",
      "jpydfAmount": "75000000000000000000000000",
      "underlyingAmount": "50000000000",
      "dTokenAmount": "50000000000000000000000000"
    }
  ]
}
```

`transactionHash:logIndex` を idempotency key とし、重複は rewardable から除外する。rewardable volume は `ReferralDeposit.jpydfAmount` を使う。`SkyUsdcRouteDeposit` は route metadata evidence として取り込めるが、単体では `jpydfAmount` を持たないため rewardable から除外される。同じ tx で発火する `ReferralDeposit` が borrow volume の正本になる。

### 1.2 Registry input

Registry は frontend が slug を bytes32 化しないための正本であり、campaign 条件と cap を持つ。

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-06-30T00:00:00.000Z",
  "partners": [
    {
      "partnerId": "partner-a",
      "displayName": "Partner A",
      "status": "active",
      "payoutAddress": "0x..."
    }
  ],
  "campaigns": [
    {
      "campaignId": "partner-a-launch",
      "partnerId": "partner-a",
      "slug": "partner-a",
      "referralCode": "0x...",
      "status": "active",
      "startsAt": "1800000000",
      "endsAt": "1802592000",
      "rewardBps": 100,
      "budgetCapJpydfRaw": "10000000000000000000000000",
      "partnerCapJpydfRaw": "10000000000000000000000000",
      "perWalletCapJpydfRaw": "1000000000000000000000000",
      "minimumHoldingSeconds": 604800
    }
  ]
}
```

`payoutAddress` は既存 export schema 名であり、Referral distributor の Merkle leaf に入れる claim recipient を意味する。`rewardBps` は任意であり、未設定なら suggested reward は出さず rewardable borrow volume のみを出す。

## 2. 実行

```bash
pnpm -C frontend/ops export-referral-ledger \
  --events ./evidence/referral-events.json \
  --registry ./evidence/referral-registry.json \
  --out ./evidence/referral-ledger.json \
  --pretty
```

環境変数でも指定できる。

| Variable | 用途 |
| --- | --- |
| `REFERRAL_LEDGER_EVENTS` | event JSON path |
| `REFERRAL_LEDGER_REGISTRY` | registry JSON path |
| `REFERRAL_LEDGER_OUTPUT` | output JSON path |
| `REFERRAL_LEDGER_PRETTY=1` | pretty JSON |

## 3. 出力の読み方

出力 row は `eligibility` を持つ。

| 値 | 意味 |
| --- | --- |
| `excluded` | rewardable ではない。`exclusionReasons` を確認する |
| `manual_review` | rewardable volume 候補。ただし claim 指示ではなく、root 投稿前レビューが必要 |

主な除外理由:

- `zero_referral_code`
- `duplicate_event`
- `unknown_campaign`
- `unknown_partner`
- `partner_paused`
- `campaign_paused`
- `campaign_expired`
- `campaign_not_started`
- `campaign_ended`
- `missing_jpydf_amount`
- `campaign_cap_exhausted`
- `partner_cap_exhausted`
- `wallet_cap_exhausted`

主な review flag:

- `manual_payout_review_required`
- `holding_period_unverified`
- `self_referral_unchecked`
- `liquidation_redemption_clawback_unchecked`
- `campaign_cap_partial`
- `partner_cap_partial`
- `wallet_cap_partial`

## 4. Root 投稿前チェック

`manual_review` row は claim 指示ではない。root 投稿前に最低限、次を確認する。

1. partner owner / claim recipient address の承認証跡
2. self-referral / same-cluster / sybil の確認
3. `minimumHoldingSeconds` 到達後の close / repayment / liquidation / redemption / bad debt 確認
4. campaign / partner / wallet cap の partial 適用確認
5. campaign terms と tax / accounting owner の承認
6. Merkle root / campaignHash と ledger output hash の突合

## 5. 境界

- rewardable volume は `jpydfAmount` のみを使い、`entireDebt` は推定しない。
- `bytes32(0)` は referral なしとして除外する。
- Referral は growth / marketing budget または Protocol Revenue budget table の evidence であり、PIL / SPAdditionalRewardDistributor / Foundation 留保と混ぜない。
- Treasury 原資を使う場合は、別途 budget table と governance / ops evidence を要求する。
- 本 export を Safe queue payload として扱わない。
