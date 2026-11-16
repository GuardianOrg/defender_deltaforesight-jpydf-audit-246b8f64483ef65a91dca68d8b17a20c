# Referral Program Policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/operations/policies/Referral-Program-Policy.md`](../../../../jp/protocol/operations/policies/Referral-Program-Policy.md)
> is authoritative if this file conflicts with it.

## 0. Positioning

This document separates the referral program into contract instrumentation,
frontend / indexer handling, reward funding, and SP / sJPYdf integration.

Related source documents:

- Zapper on-chain instrumentation: [`../../product/spec/Zapper.md`](../../product/spec/Zapper.md)
  `ZAP-FR-002` / `ZAP-FR-004` / `ZAP-FR-014` / `ZAP-EVT-001`
- Instrumentation rationale (type / payload / indexing):
  [`../../product/spec/Zapper.md`](../../product/spec/Zapper.md) section 2
- Paid campaign activation gate:
  [`Referral-Campaign-Activation-Gate.md`](../runbooks/Referral-Campaign-Activation-Gate.md)
- Manual ledger export:
  [`Referral-Ledger-Export-Runbook.md`](../../../contributors/deltaforesight/operations/Referral-Ledger-Export-Runbook.md)
- Source-of-funds allocation:
  [`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md)
- Referral / SP additional-reward distribution:
  [`../../roadmap/spec/Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md)
- Treasury routing: [`../../roadmap/spec/Treasury.md`](../../roadmap/spec/Treasury.md)
- Frontend gate: [`../../product/spec/Frontend.md`](../../product/spec/Frontend.md)

The conclusion is that Referral has only measurement instrumentation in the Day-1
contract ABI. The paid reward program is separated into off-chain / Day-2+ gates.
Referral bugs or campaign decisions must not affect Core, Vault, Treasury, or SP
accounting.

## 1. Decisions

| Item | Policy |
| --- | --- |
| Day-1 contract surface | Zapper open-time `ReferralDeposit` / Sky route event only; no storage, no Core / Vault propagation, no fund movement |
| Day-1 frontend | Public referral input / URL capture / paid campaign display is disabled until registry and abuse policy are ready |
| Borrow attribution | Use `ReferralDeposit.referralCode` and `jpydfAmount` (user-received borrow amount), not `entireDebt` |
| SP deposit attribution | Raw `DFStabilityPool.provideToSP()` has no referral surface, so raw SP deposits are not on-chain referral eligible |
| sJPYdf / SP referral | Add later through sJPYdf or a wrapper; do not add referral args to Core SP |
| Reward funding | Source is **collateral strategy yield retained through Treasury**. Allocation follows the single budget table in [`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md), with separate borrow-referral and SP-deposit-referral buckets routed to the corresponding contracts in [`Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md) after Treasury operation starts (Day-2). Company marketing budget is protocol-external and outside this policy |
| PIL relation | PIL is not a referral budget source. It remains a borrowing-interest liquidity incentive path |
| SP reward relation | SP additional rewards and Referral rewards use the **same source of funds: collateral strategy yield**. They are separated by the same budget table so the same yen/token is not double counted |

## 2. Contract Boundary

### 2.1 Borrow referral

Borrow-side referral is fixed in the Zapper.

| Item | Value |
| --- | --- |
| Type | `bytes32 referralCode` |
| No referral | `bytes32(0)` |
| Target functions | `openTroveWithRawETHAndReferral` / `openTroveWithUnderlyingPermitAndReferral` / `openTroveWithUsdcAndReferral` |
| Event | `ReferralDeposit(address indexed user, uint256 indexed troveId, uint256 underlyingAmount, uint256 dTokenAmount, uint256 jpydfAmount, bytes32 indexed referralCode)` |
| Sky route | `SkyUsdcRouteDeposit(..., bytes32 indexed referralCode)` |
| Amount | `jpydfAmount` = borrow amount received by the user |

`referralCode` is measurement metadata, not an accounting input. Production
contracts other than the Zapper do not know referral. This boundary keeps
referral registry / campaign / reward bugs away from collateral custody, debt,
liquidation, and redemption.

### 2.2 SP deposit referral

SP deposits are not currently included in referral attribution.

- `DFStabilityPool.provideToSP()` is the Core SP path and has no referral arg or event.
- Zapper is a borrow-open UX router, not an SP deposit wrapper.
- Do not change the Core SP ABI just to add referral.

If SP deposit attribution is included later, design it through sJPYdf, a wrapper,
or off-chain signed attribution. The preferred route is an event at the sJPYdf or
dedicated wrapper layer; Core SP remains unchanged.

## 3. Program Phases

| Phase | Content | Launch treatment |
| --- | --- | --- |
| Phase 0: Measurement ready | Zapper event exists and ABI / spec / tests are fixed | Day-1 contract ready |
| Phase 1: Private campaign ledger | Partner registry, URL capture, subgraph / analytics ledger, and root export tooling. Actual claim waits until Day-2 collateral-yield allocation | Day-1+ |
| Phase 2: Paid referral program | Campaign terms, budget cap, anti-abuse, KPI, tax / legal review, ops dashboard | Day-2+ |
| Phase 3: SP / sJPYdf referral | Add SP deposit attribution through sJPYdf / wrapper / SP additional reward policy | Day-2+ / depends on sJPYdf |
| Phase 4: On-chain reward distribution | Merkle distributor or equivalent claimable rewards | After Treasury / legal / audit gates |

Day-1 mainnet launch is satisfied by Phase 0. Later phases are growth work, not
protocol launch gates.

## 4. Attribution

### 4.1 Borrow attribution

The borrow referral ledger keys by:

| Field | Source | Use |
| --- | --- | --- |
| chainId | deployment config | chain separation |
| branchId | emitting Zapper address -> deployment manifest | collateral branch separation |
| txHash / logIndex | event | idempotency |
| user | `ReferralDeposit.user` | borrower wallet |
| troveId | `ReferralDeposit.troveId` | opened position |
| referralCode | `ReferralDeposit.referralCode` | channel / partner |
| jpydfAmount | `ReferralDeposit.jpydfAmount` | borrow volume |
| underlyingAmount / dTokenAmount | event | campaign analysis / branch mix |

The same tx / logIndex is counted once. `bytes32(0)` is treated as no referral
and excluded from referral reward calculations.

### 4.2 Rewardable volume

The initial rewardable volume is `jpydfAmount`.

Reasons:

- It is the borrow amount the user receives and is easy to align with UI and
  campaign copy.
- `entireDebt` is not emitted; adding it after deploy would require ABI / event
  changes.
- Referral is acquisition measurement, not the debt-accounting source of truth.

Changing to `entireDebt`, outstanding debt, time-weighted debt, or net interest
paid requires a separate program-ledger policy update and, if needed, a Zapper
event revision. Do not reinterpret the existing event.

### 4.3 Duration / clawback

Paid campaigns should not pay immediately on raw open volume. The off-chain
ledger should define:

- minimum holding period
- immediate close / full repayment / self-referral exclusion
- payment stop or clawback for liquidation / redemption / bad debt events
- campaign budget cap / partner cap / per-wallet cap
- manual review queue

These are campaign-accounting rules and are not reflected in contract state.

## 5. Referral Code Registry

Human-readable codes and on-chain `bytes32` IDs are separate.

| Representation | Role |
| --- | --- |
| slug | Short code shown in URL / UI |
| bytes32 referralCode | Canonical ID sent to the Zapper |
| partnerId | Internal off-chain registry ID |

Recommended flow:

1. Registry normalizes slug (lowercase, trim, allowlist chars, max length).
2. Registry issues the canonical `bytes32`; frontend sends only registry-returned values.
3. Frontend must not hash arbitrary slugs locally for paid campaigns.
4. Unknown codes are sent as `bytes32(0)` or clearly shown as no-referral before tx.

Paid campaign codes include terms, partner owner, budget cap, active period, and
paused status in the registry.

## 6. Frontend / Subgraph / Backend Gate

Before referral becomes user-facing:

| Area | Gate |
| --- | --- |
| Frontend | URL param / local storage / input capture, sanitization, registry validation, unknown / expired display, referral preview |
| Transaction | Call `...AndReferral` only when a valid code exists; otherwise keep current no-referral entrypoint |
| Subgraph | Index `ReferralDeposit` / `SkyUsdcRouteDeposit` and resolve branchId from manifest / Zapper address |
| Backend / ledger | Event idempotency, registry join, campaign period, budget cap, exclusion / clawback, root export |
| Ops | Campaign dashboard, partner report, fraud review queue, root / claim approval evidence |
| Security | XSS / homograph / address spoofing protection, self-referral / same-cluster abuse controls |
| Legal / comms | Reward terms, non-guarantee copy, tax / accounting owner, campaign stop clauses |

If these gates are not met, the frontend must not submit referral transactions or
display the program as active even though the ABI has referral functions.

The Day-1+ evidence package is implemented by `frontend/ops export-referral-ledger`.
It takes subgraph-derived `ReferralDeposit` / `SkyUsdcRouteDeposit` event JSON
and partner / campaign registry JSON. Rewardable volume is sourced from
`ReferralDeposit.jpydfAmount`. `SkyUsdcRouteDeposit` can be imported as route
metadata evidence, but it has no standalone `jpydfAmount` and is excluded from
rewardable volume. The output includes `manual_review` / `excluded` rows,
partner / campaign summaries, cap partial flags, holding-period unverified
flags, self-referral-unchecked flags, and liquidation / redemption
clawback-unchecked flags. This is review evidence for the root posted to the
Referral distributor, not a payout instruction.

## 7. Reward Funding And Accounting

### 7.1 Source

Referral rewards are funded from **collateral strategy yield retained through
Treasury**. The single budget table in
[`Protocol-Revenue-Allocation-Policy.md`](../../roadmap/policies/Protocol-Revenue-Allocation-Policy.md)
is authoritative. Referral uses separate borrow-referral and SP-deposit-referral
buckets that are mutually exclusive with SP additional rewards and Foundation
retention, so the same yen/token cannot be double counted.

Collateral strategy yield is only retained in the Safe on Day-1, so Referral
payout starts after Treasury operation (Day-2). Company marketing budget is
protocol-external funding and is not the source covered by this policy.

### 7.2 Approval and accounting

Using collateral strategy yield for Referral rewards requires separate
governance / operations evidence. The budget table finalizes allocation ratios
and priority; [`Reward-Distributors.md`](../../roadmap/spec/Reward-Distributors.md) is
authoritative for payout-fund management.

- budget cap, partner cap, per-wallet cap, campaign period, and stop clauses
- reward asset, claim recipient mapping, root export / challenge evidence, and
  tax / accounting owner
- priority against SP distribution, buyback, backstop repair, and Foundation
  retention

Distribution uses **Referral distributor -> root posting -> challenge window ->
on-chain claim**. If the Foundation chooses manual Safe payment instead, the
corresponding Referral bucket ratio must be set to 0 and redirected to
Foundation retention in the Protocol Revenue budget table.

### 7.3 PIL is not used

PIL is the 25% borrowing-interest route for JPYdf liquidity incentives. It is not
a referral reward source. Sending PIL to Referral is outside this policy and
requires a separate InterestRouter / PILAllocator governance decision.

## 8. SP / sJPYdf Referral

If SP deposits are included, handle them through sJPYdf / wrapper / distributor
design rather than raw `provideToSP()`.

Recommended policy:

1. If sJPYdf is ERC-4626-style, add `depositWithReferral` or wrapper events.
2. Rewardable SP amount uses TWAB / minimum holding period, not raw deposit only.
3. Referral bonus and SP additional rewards use the same source of funds
   (collateral strategy yield), but Referral bonus remains a separate bucket from
   base SP reward in the budget table.
4. Campaign terms specify what happens after liquidation converts SP deposits into collateral.
5. Raw direct SP deposits stay usable with no referral.

This depends on the unified zJPYdf token (tracked as `ROADMAP-CAND-006` in `documents/jp/protocol/roadmap/Roadmap.md`, design memo `documents/jp/protocol/roadmap/initiatives/zjpydf/zJPYdf.md`; absorbs the former sJPYdf concept) and SP reward policy finalization.

## 9. Close Criteria For #564

#564 can close when:

- Borrow referral contract surface is fixed in `ZAP-EVT-001` and implementation.
- Day-1 / Day-2 boundary, reward funding, SP / sJPYdf boundary, and abuse gates
  are documented here.
- Remaining work is decomposed into frontend / subgraph / ledger / SP-sJPYdf /
  reward-budget issues.

Closing #564 does not make Referral production-active. Production activation
follows the gates in each follow-up issue / PR.

## 10. Follow-up Work

| Issue | Area | Work |
| --- | --- | --- |
| #656 | Frontend | referral URL capture, registry validation, transaction preview, `...AndReferral` submission |
| #657 | Subgraph / analytics | `ReferralDeposit` indexing, branch resolution, campaign ledger |
| #658 | Backend / ops / reward budget | Paid campaign activation gate is separated into [`Referral-Campaign-Activation-Gate.md`](../runbooks/Referral-Campaign-Activation-Gate.md). Concrete campaign registry / ledger / dashboard work is managed through #656 / #657 and the campaign packet |
| #659 | SP / sJPYdf | sJPYdf or wrapper referral event, TWAB / holding-period attribution |
