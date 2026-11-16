# Referral Ledger Export Runbook

> Support translation. The Japanese source document
> [`documents/jp/contributors/deltaforesight/operations/Referral-Ledger-Export-Runbook.md`](../../../../jp/contributors/deltaforesight/operations/Referral-Ledger-Export-Runbook.md)
> is authoritative if this file conflicts with it.

## 0. Purpose

This runbook defines how to join subgraph referral events with the partner /
campaign registry and produce a root / claim review evidence package before any
paid referral campaign is treated as production-active.

It covers the #657 backend / analytics ledger scope. It does not automate
claims; it prepares evidence for root posting, tax/accounting review, and fraud
checks.

## 1. Inputs

### 1.1 Event Input

`frontend/ops export-referral-ledger` takes event JSON through `--events`.

The file may be an array or `{ "events": [...] }`.

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

`transactionHash:logIndex` is the idempotency key. Duplicates are excluded from
rewardable volume. Rewardable volume uses `ReferralDeposit.jpydfAmount`.
`SkyUsdcRouteDeposit` may be imported as route metadata evidence, but it has no
standalone `jpydfAmount`, so it is excluded from rewardable volume. The paired
`ReferralDeposit` in the same tx is the borrow-volume source of truth.

### 1.2 Registry Input

The registry is the source of truth that prevents the frontend from converting
slugs into bytes32 codes. It also carries campaign terms and caps.

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

`rewardBps` is optional. If omitted, the output includes rewardable borrow volume
but no suggested reward amount.

## 2. Command

```bash
pnpm -C frontend/ops export-referral-ledger \
  --events ./evidence/referral-events.json \
  --registry ./evidence/referral-registry.json \
  --out ./evidence/referral-ledger.json \
  --pretty
```

Environment variables are also supported.

| Variable | Purpose |
| --- | --- |
| `REFERRAL_LEDGER_EVENTS` | event JSON path |
| `REFERRAL_LEDGER_REGISTRY` | registry JSON path |
| `REFERRAL_LEDGER_OUTPUT` | output JSON path |
| `REFERRAL_LEDGER_PRETTY=1` | pretty JSON |

## 3. Output Review

Rows have `eligibility`.

| Value | Meaning |
| --- | --- |
| `excluded` | Not rewardable; inspect `exclusionReasons` |
| `manual_review` | Candidate rewardable volume; not a payout instruction |

Common exclusion reasons:

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

Common review flags:

- `manual_payout_review_required`
- `holding_period_unverified`
- `self_referral_unchecked`
- `liquidation_redemption_clawback_unchecked`
- `campaign_cap_partial`
- `partner_cap_partial`
- `wallet_cap_partial`

## 4. Pre-Root Checks

`manual_review` rows are not claim instructions. Before root posting, verify:

1. partner owner / claim recipient address evidence
2. self-referral / same-cluster / sybil review
3. close / repayment / liquidation / redemption / bad debt after the minimum holding period
4. partial campaign / partner / wallet cap application
5. campaign terms and tax/accounting owner approval
6. campaignHash / sourceHash, Merkle root, and challenge evidence against the ledger output hash

## 5. Boundaries

- Rewardable volume uses `jpydfAmount` only; `entireDebt` is not inferred.
- `bytes32(0)` is excluded as no-referral.
- Referral evidence is growth / marketing budget evidence or Protocol Revenue
  budget evidence and must not be mixed with PIL / SPAdditionalRewardDistributor.
- If Treasury funds are used, require a separate budget table and governance /
  ops evidence before root posting.
