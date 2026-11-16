# Referral Campaign Activation Gate

> **Positioning**: Activation gate before any paid Referral campaign becomes user-facing. The referral design policy lives in [`Referral-Program-Policy.md`](../policies/Referral-Program-Policy.md), and on-chain instrumentation lives in [`../../product/spec/Zapper.md`](../../product/spec/Zapper.md) (section 2 / `ZAP-EVT-001`).
>
> This runbook gates campaign accounting, operations, root export, and claim. It does not change Core, Vault, Treasury, or Stability Pool accounting.

---

## 0. Activation Policy

A paid Referral campaign must not be published until all of the following are `PASS`.

| Area | Gate |
| --- | --- |
| Product | Campaign terms, target action, target period, stop conditions, and inquiry owner are frozen |
| Budget | Reward source, campaign cap, partner cap, per-wallet cap, and unused-budget handling are approved |
| Frontend | Unknown / expired / paused codes are shown as no-referral, and only valid codes are passed to `...AndReferral` |
| Subgraph / ledger | `txHash:logIndex` idempotency, branchId, referralCode, jpydfAmount, and exclusion reason can be recorded |
| Anti-abuse | Exclusion policy covers self-referral, same-cluster, immediate close, full repayment, liquidation, redemption, and bad debt |
| Distribution | Reward asset, claim recipient mapping, root export, challenge evidence, and tax / accounting owner are frozen |
| Legal / comms | Reward terms, non-guarantee language, stop / change rights, and jurisdiction restrictions are reviewed |

Day-1 launch does not require Referral campaign activation. Even when referral contract surfaces exist, the frontend and marketing copy must not show a paid campaign as active until this gate passes.

## 1. Campaign State

| State | Meaning | Condition to proceed |
| --- | --- | --- |
| `Draft` | Planned only. Not exposed in registry or UI | Campaign packet is created |
| `EvidenceReady` | Budget / abuse / root / claim evidence is ready | Product, Ops, Finance / Accounting, and Legal approve |
| `Approved` | Ready to publish, but not user-facing yet | Frontend / backend / subgraph release reaches production |
| `Active` | User-facing display is allowed, and valid codes may be submitted | Monitoring is fresh, budget is within cap, and no stop condition has fired |
| `Paused` | New attribution is stopped. Existing attribution remains under review | Pause reason is resolved and re-approved |
| `Closed` | Campaign period ended. Only root / claim / audit evidence remains | Final root export and close report are saved |

`Paused` / `Closed` codes are handled as no-referral in the frontend. Do not submit their on-chain `bytes32` values.

## 2. Campaign Packet

Create the following packet for each campaign. The campaign cannot move to `Active` if any field is blank.

| Field | Required content |
| --- | --- |
| campaignId | Off-chain unique ID, including the slug to `bytes32 referralCode` mapping |
| partnerId / owner | Partner name, contract owner, contact, and pause contact path |
| target action | Target action. Initially borrow-open referral only. Raw SP deposit is out of scope |
| eligible branch | Target branch. Explicitly state if all branches are eligible |
| campaign period | Start / end timestamp, timezone, early stop conditions |
| reward formula | Rewardable volume, rate, caps, rounding, minimum payout |
| budget source | Growth / marketing budget, or separate approval evidence for Treasury retained revenue |
| budget caps | Campaign cap, partner cap, per-wallet cap, daily / weekly cap |
| exclusion policy | Reason for any campaign-specific override of §4 exclusions |
| holding / clawback | Minimum holding period, clawback window, payment stop conditions |
| reward distribution plan | Reward asset, claim recipient mapping, root export schema, approvers |
| legal / comms | Terms URL, non-guarantee language, jurisdiction restrictions, tax / accounting owner |
| evidence links | Registry snapshot hash, subgraph query / export hash, approval memo, close report |

## 3. Budget And Source Of Funds

### 3.1 Default

The default reward source is growth / marketing budget outside protocol accounting. Even then, the campaign cap and partner cap must be explicit and approved by the Finance / Accounting owner.

### 3.2 If Treasury Is Used

Using Treasury retained revenue for Referral requires governance / ops evidence in addition to normal campaign approval.

- `BORROW_REFERRAL` / `SP_DEPOSIT_REFERRAL` bucket and budget cap in [Protocol-Revenue-Allocation-Policy](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md)
- Priority against SP additional rewards, buyback, backstop, and Foundation retention
- Double-count prevention in the same source-of-funds table used for SPAdditionalRewardDistributor / SP additional rewards
- Reward asset, recipient list, Merkle root / challenge evidence
- Unused-budget destination and campaign stop clauses

If manual Safe payment is chosen for Referral, set the corresponding Referral bucket ratio to 0 and route that amount to Foundation retention. Budget sent to a Referral distributor has no normal path back to the Safe for manual payment.

### 3.3 No PIL

PIL is the InterestRouter / PILAllocator route for JPYdf liquidity incentives. It is not a Referral reward source. This gate cannot approve using PIL for Referral.

## 4. Anti-Abuse Policy

At minimum, exclude the following from rewardable volume.

| Exclusion | Decision rule |
| --- | --- |
| self-referral | Borrower and partner / payout owner / controlled wallet are the same or effectively the same |
| same-cluster | Predefined wallet cluster, common funding, internal wallet, employee wallet |
| immediate close | Close / full repayment before the minimum holding period |
| full repayment | Position net debt falls below the campaign threshold during the holding period |
| liquidation | Liquidated position. Define partial-liquidation treatment in the campaign packet |
| redemption | Redemption causes debt / position to no longer satisfy campaign terms |
| bad debt / branch incident | Attribution involving branch shutdown, oracle incident, strategy writeoff, or bad debt |
| duplicate event | Same `txHash:logIndex`, duplicate after reorg, or code not present in the registry |
| paused / expired code | Registry state is `Paused` / `Closed` / expired |

Exclusion decisions are made in the off-chain campaign ledger. Do not rewrite contract state. Record `eligibilityStatus` and `exclusionReason`, and include them in root exports.

## 5. Ledger And Root Export

### 5.1 Ledger Fields

The borrow referral ledger stores at least:

| Field | Source |
| --- | --- |
| chainId | Deployment config |
| branchId | Deployment manifest / Zapper address |
| txHash / logIndex | `ReferralDeposit` / route event |
| user | Event |
| troveId | Event |
| referralCode | Event. `bytes32(0)` is out of scope |
| jpydfAmount | Event. Initial basis for rewardable volume |
| underlyingAmount / dTokenAmount | Event |
| campaignId / partnerId | Registry join |
| eligibilityStatus / exclusionReason | Campaign ledger |
| payoutAmount / payoutAsset | Claimable amount / reward asset used in the root (existing export field names) |

### 5.2 Root Export

The root export includes:

- export generatedAt, source block range, registry snapshot hash, query hash
- claim recipient address, reward asset, amount, campaignId, partnerId
- eligible volume, values before / after cap application, rounding, minimum payout decision
- exclusion summary, plus approver / reason for any manual override
- approval memo link, campaignHash / sourceHash, Merkle root, challenge evidence

At least two people across Product / Ops / Finance or Accounting review the export before root posting. Add budget table / governance evidence when collateral strategy yield is used.

## 6. Frontend / Backend / Subgraph Gates

Before public-enabling a paid campaign:

| Component | Required |
| --- | --- |
| Frontend | URL / localStorage capture, registry validation, unknown / expired / paused display, tx preview, `...AndReferral` only for valid codes |
| Backend registry | Slug normalization, canonical `bytes32` issuance, state management, campaign period, partner metadata |
| Subgraph | `ReferralDeposit` / Sky route event indexing, branchId resolution, `txHash:logIndex` idempotency, `bytes32(0)` exclusion |
| Analytics ledger | Registry join, holding period, exclusion, cap, root export |
| Monitoring | Alerts for stale subgraph / registry / stats, approaching budget caps, pause propagation |

If any item is missing, the frontend must not submit referral transactions. A referral function existing in the ABI is not activation evidence.

## 7. Stop Conditions

Move the campaign to `Paused` if any of the following occur.

- Campaign cap, partner cap, or per-wallet cap is exceeded, or a near-cap alert is not handled
- Registry / subgraph / analytics ledger is stale, missing data, or inconsistent after a reorg
- Suspected self-referral or same-cluster abuse
- Claim recipient mapping review failure, sanctions / legal / tax blocker
- Branch shutdown, oracle incident, strategy writeoff, bad debt, critical frontend bug
- Terms / UI copy diverges from actual eligibility

After pause, stop new attribution and re-evaluate existing attribution in the close report.

## 8. Evidence Package

Save the following as `referral-campaign-activation-{campaignId}`.

| Evidence | Content |
| --- | --- |
| Campaign packet | All §2 fields, approvers, approval timestamps |
| Registry snapshot | slug, `bytes32 referralCode`, state, period, cap, hash |
| Frontend evidence | screenshots / test output for URL capture, invalid code, expired / paused code, tx preview |
| Subgraph / ledger evidence | source block, query hash, idempotency, branchId join, sample export |
| Budget evidence | source-of-funds table, caps, governance / Safe evidence if Treasury is used |
| Anti-abuse evidence | exclusion rules, sample exclusions, manual review queue |
| Root / claim evidence | export hash, approval memo, Merkle root, challenge result, claim monitor |
| Close report | final spend, unused budget, exclusions, incidents, follow-up issue |

Do not include private keys, raw RPC URLs, unpublished Safe nonces, or unnecessary personal-data source files in the evidence package.

## 9. Close Criteria For #658

#658 can close for the Day-2 paid referral policy scope when:

1. This runbook is merged to `develop` and referenced from [`Referral-Program-Policy.md`](../policies/Referral-Program-Policy.md).
2. Reward source, separate approval when Treasury is used, no PIL use, budget / partner / wallet caps, anti-abuse, holding / clawback, and root / claim evidence are documented here.
3. Concrete campaign values are frozen in campaign packets, and public enablement is impossible before that freeze.
4. Unimplemented frontend / subgraph / SP-sJPYdf attribution remains in the individual scopes #656 / #657 / #659.

Closing the issue does not mean a paid campaign is active. Real activation is decided per campaign by its evidence package and approvals.
