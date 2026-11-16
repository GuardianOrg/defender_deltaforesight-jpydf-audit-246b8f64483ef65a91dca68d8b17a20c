# Merkl campaign / launch KPI policy

> Support translation. The Japanese source document
> [`documents/jp/protocol/roadmap/policies/Merkl-Campaign-KPI-Policy.md`](../../../../jp/protocol/roadmap/policies/Merkl-Campaign-KPI-Policy.md)
> is authoritative if this file conflicts with it.

## 0. Position

This document is a design memo defining the candidates, adoption decisions,
budget classification, launch KPIs, and stop conditions for external liquidity
campaigns that use Merkl.

`PILAllocator.md` and `UniV4MerklInitiative` define the **contract requirements
for creating a Merkl campaign**. This document sits above them and covers
**which campaign is enabled, out of which funds, and to achieve what**.

Not defined here:

- Contract specification of the Uniswap v4 pool / route:
  [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)
- Contract requirements of PILAllocator / UniV4MerklInitiative:
  [`../../spec/PILAllocator.md`](../../product/spec/PILAllocator.md)
- LP / SP seed amounts adopted from the company balance sheet:
  [`Day1-Self-BS-Launch-Commitment.md`](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md)
- Day-1 Safe retention of collateral yield, and Day-2 Treasury / SP additional
  rewards: [`Protocol-Revenue-Allocation-Policy.md`](./Protocol-Revenue-Allocation-Policy.md)
- Fixed parameter values: [`../../Parameters.md`](../../../Parameters.md)

## 1. Basic policy

The only candidate for a Day-1 / Phase-A Merkl campaign is the **JPYdf/USDC
Uniswap v4 LP incentive**. It exists to create JPYdf's initial exit liquidity,
price discovery, and depth around the peg. It is not an SP additional reward, and
it is not a distribution of collateral yield.

USDT pools, dToken LP, and external lending markets are not adopted for Day 1.
They become Day-2 candidates only once clear demand, a partner, and the route /
oracle / liquidation / accounting gates are all in place.

Funding buckets are not mixed. At minimum, the following are accounted for
separately.

| Bucket | Use | Treatment here |
| --- | --- | --- |
| PIL | Liquidity incentive derived from 25% of borrowing interest | Primary candidate for JPYdf/USDC Phase-A |
| Merkl campaign budget | Short-term incentives explicitly approved outside PIL | Only where individually approved |
| B/S LP seed | Initial JPYdf/USDC LP from company funds | Not a campaign budget |
| B/S SP seed | Pre-funded SP deposit from company funds | Out of Merkl scope |
| Backstop funds | Protected reserve for Vault backing repair | Out of Merkl scope |
| Safe-retained collateral yield | Day-1 Safe retention of collateral yield | Not used for Merkl / SP rewards until Day-2 Treasury approval |

## 2. Campaign classification

| Campaign | Phase | Policy | Reason / gate |
| --- | --- | --- | --- |
| JPYdf/USDC Uniswap v4 LP | Day-1 / Phase-A candidate | Adoption candidate | The only JPYdf DEX pair on Day 1. Aligned with `PILAllocator` / `UniV4MerklInitiative` / the approved activation package |
| JPYdf/USDT LP | Day-2 candidate | Conditional | The Day-1 route consolidates on USDC. Considered as a separate pool / initiative if USDT demand, a partner, or a liquidity need emerges |
| JPYdf/JPYC LP | Day-2 candidate | Conditional | Requires activation of the dormant route ([Liquidity-Route-Policy](../../product/policies/Liquidity-Route-Policy.md) §7). Even after activation, turning it into a campaign needs separate individual approval; not a Day-1 / Phase-A candidate |
| JPYdf/dToken LP | Backlog | Not adopted for Day 1 | dToken is a collateral beneficiary interest and serves a different purpose from JPYdf exit liquidity. Not a candidate until demand and the risk explanation are settled |
| External lending market | Day-2 candidate | Conditional | Adopted only where real supply / borrow demand, oracle, liquidation, market admin, and claim UX are all in place |
| SP additional reward via Merkl | Not adopted | Not adopted | A standing SP additional reward is handled by the Day-2 protocol-native distributor. Merkl is limited to external LP / lending / bootstrap |

## 3. JPYdf/USDC Phase-A initial policy

Phase A takes the standard approach of enabling a single epoch first and
deciding on continuation from results. It does not become a long-running campaign
automatically.

| Item | Phase-A initial policy |
| --- | --- |
| Target pair | JPYdf/USDC Uniswap v4 only |
| Funding source | PIL only. A Merkl campaign budget outside PIL is used only with individual governance approval |
| Initial funding rule | Under the current contract, the campaign amount is the JPYdf balance held by `UniV4MerklInitiative` at the time of `createCampaign()` |
| Campaign cap | No absolute cap in Phase A. `UniV4MerklInitiative` / `PILAllocator` do not enforce a per-campaign cap |
| Budget control | Controlled by not routing actively, setting weight to 0, allocating weight to a reserve initiative, or delaying campaign creation |
| Reserve / carry-over | Amounts below the threshold, PIL received after campaign creation, and PIL allocated to a reserve initiative all carry over |
| Duration | One epoch initially. From the second epoch onward, continuation is approved after KPI review |
| Review cadence | Every funded epoch |
| User segment | External LP, arbitrageurs, market makers, partner LP. DF-controlled LP seed is excluded from user-acquisition KPIs |
| Day-1 non-goals | SP additional rewards, Referral, dToken LP, and incentivising external lending markets |

```text
campaignAmount = UniV4MerklInitiative.JPYdf.balanceOf(address(this))
```

If the campaign amount is below `CAMPAIGN_JPYDF_AMOUNT_THRESHOLD`, no campaign is
created and the balance carries over. If additional PIL arrives after a campaign
with the same `campaignStart` has been created, the current
`UniV4MerklInitiative` also carries it over to the next `campaignStart`.

No absolute cap is required in Phase A because PIL is the bucket of protocol
revenue designed as a DEX liquidity incentive, and it can be stopped or reduced
through per-epoch KPI review, weight changes, pause, and the reserve initiative.
If a per-campaign absolute cap becomes necessary in future, it is introduced by
deploying a new initiative / allocator and replacing the `InterestRouterForwarder`
recipient or the registered initiative — not by changing how the current
`UniV4MerklInitiative` is operated.

## 4. KPI definitions

KPIs exist to **improve JPYdf's exit liquidity and depth around the peg**, not to
make the APR look high. The B/S LP seed is company funds used to create the
initial market, and is not double-counted as a result of the Merkl campaign.

| KPI | Initial basis / calculation rule | Continuation judgement |
| --- | --- | --- |
| Campaign efficiency | `totalPoolVolume / postFeeRewardAmount`. Deduct known DF self-trading, wash volume, and clearly circular volume as far as it can be detected; record what cannot be deducted as a limitation | Re-approve continuation if below `10x` for 2 consecutive funded epochs |
| External eligible TVL | Merkl eligible TVL less the DF-controlled LP seed. Where exclusion is impossible, retain the address list and the limitation in evidence | Re-approve continuation if there is no growth for 2 consecutive funded epochs, or if it is effectively 0 |
| Spread | Peg deviation of the JPYdf/USDC implied JPY price. Oracle / redemption / pool incidents are noted separately | Review required if outside median ±0.5% under normal conditions, or outside p95 ±1.0% |
| Depth 0.1% | Depth at 0.1% price impact. The beta reference for a Day-1 ¥100M LP seed is roughly ¥1.08M. Recompute proportionally if the LP seed changes | Review required if it stays well below the beta reference |
| Depth 0.5% | Depth at 0.5% price impact. The beta reference for a Day-1 ¥100M LP seed is roughly ¥5.22M | Weighted heavily as the practical proxy for the redemption fee line |
| Depth 1.0% | Depth at 1.0% price impact. The beta reference for a Day-1 ¥100M LP seed is roughly ¥7.57M | Supporting indicator for large swaps and JIT sourcing capacity |
| Campaign execution | `route -> distribute -> createCampaign` succeeds in the scheduled epoch, and the post-fee distribution is reflected in Merkl | On failure, suspend updates until the cause is resolved before the next epoch |

Depth references follow the beta proposal in
[`Liquidity-Management-Policy.md`](../../operations/policies/Liquidity-Management-Policy.md).
If the actual pool's LP notional, range, fee tier, or the choice between IPOR and
manual management changes, use the values recomputed in the activation package.

## 5. Activation gate

Before making the JPYdf/USDC Merkl campaign active, satisfy the following.

1. The JPYdf/USDC Uniswap v4 pool from `Liquidity-Route-Policy.md` has been
   created, and the pool key / poolId / hook policy / fee / tick spacing are
   recorded as evidence.
2. The values corresponding to `PRM-PILA-*` are frozen in the approved activation
   package's `pil-activation-manifest.json`.
3. The retained PIL balance, the expected initiative balance after `distribute()`,
   the campaign amount, and the post-fee expected distribution are recorded as
   evidence.
4. The official Merkl `DistributionCreator` address, fee model, terms / KYC
   requirements, claim UX, and unclaimed rewards policy have been confirmed.
5. `InterestRouterForwarder.setRecipient(PILAllocator)`, initiative registration,
   weight configuration, and campaign creation are each separately verifiable as
   Safe / Timelock actions.
6. The B/S LP seed, SP seed, backstop funds, and Safe-retained collateral yield
   are not double-counted against the campaign budget.
7. A fork / dry run has confirmed the end-to-end
   `route -> distribute -> createCampaign` path and the no-op / carry-over paths.
8. The KPI dashboard / artifact can recompute each metric in §4 per epoch.

## 6. Stop conditions

Stop creating new campaigns or renewing the next epoch on any of the following.

| Condition | Response |
| --- | --- |
| Abnormal price or depth in the JPYdf/USDC pool | Stop campaign renewal and check LP / oracle / redemption state |
| A §4 KPI missed for 2 consecutive funded epochs | Put campaign continuation under re-approval |
| Wash trading, self-dealing, or clear incentive farming | Consider a blacklist approach or a new initiative. No in-place blacklist on Day 1 |
| An incident in the Merkl engine / API / Distributor / dispute process | `PILAllocator.pause()` or stop campaign creation |
| Cost-effectiveness deteriorates, including campaign fees | Reduce, end, or move the budget to another channel |
| Confusion arises with Safe-retained yield or backstop funds | Stop the campaign, correct the accounting classification, then resume |

## 7. Merkl-specific considerations

As of 2026-07-01, the official Merkl docs state a standard campaign fee of 3%,
deducted from the tokens deposited into the campaign. Do not assume additional
tokens are sent to cover the fee. Confirm the current terms for the
scale-dependent degressive fee, the commitment model, and the unclaimed rewards
policy in the activation package.

Merkl computes activity in an off-chain engine, posts a Merkle root on-chain, and
users claim through the Merkl app / API or similar. This is an external trust
boundary, not a JPY DeFi protocol-native claim. UI and ops must not conflate Core
SP rewards, Day-2 SP additional rewards, and Merkl LP rewards.

## 8. References

- Issue #649: organise Merkl campaign candidates and the launch KPI policy
- [`../../spec/PILAllocator.md`](../../product/spec/PILAllocator.md)
- [`Liquidity-Route-Policy.md`](../../product/policies/Liquidity-Route-Policy.md)
- [`Liquidity-Management-Policy.md`](../../operations/policies/Liquidity-Management-Policy.md)
- [`Balance-Sheet-Liquidity-Allocation-Policy.md`](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md)
- [`Protocol-Revenue-Allocation-Policy.md`](./Protocol-Revenue-Allocation-Policy.md)
- Merkl Technical Overview: https://docs.merkl.xyz/merkl-mechanisms/technical-overview
- Merkl Fee Model: https://docs.merkl.xyz/distribute-with-merkl/fee-model
