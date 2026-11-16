# Mainnet Launch Product Decision Record

| Item | Value |
| --- | --- |
| Status | Active |
| Role | Canonical product record for Day-1 public-launch scope, business targets, and launch requirements |
| Decision owner | JPY DeFi Product. On-chain parameter changes still require protocol-governance approval and Timelock execution. |
| Company funds | [Day-1 Self-B/S Launch Commitment](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md) |
| Calculation basis | [Day-1 Self-B/S Initial Liquidity Plan](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Initial-Liquidity-Plan.md) |
| Out of scope | DeltaForesight corporate funding commitments, Foundation assets, real addresses, execution steps, Go/No-Go, and transaction evidence |

## 0. Decision and asset boundaries

This document specifies the conditions under which JPY DeFi launches publicly on Day 1. It does not mean the JPY DeFi protocol owns or commits assets belonging to DeltaForesight Inc. or the Foundation.

| Category | Canonical record / approval |
| --- | --- |
| protocol or deploy parameter | [Parameters](../../../Parameters.md); changes require protocol governance and Timelock execution |
| product launch requirement | this document; the launch gate checks it as a minimum market-open condition |
| DeltaForesight corporate B/S | [Day-1 Self-B/S Launch Commitment](../../../contributors/deltaforesight/commitments/Day1-Self-BS-Launch-Commitment.md); approved and executed solely by the company |
| Foundation assets | separate Foundation approval; never aggregated with the company B/S |
| execution values and results | the config and evidence package under the [Mainnet Launch Operation Gate](../gates/Mainnet-Launch-Operation-Gate.md) |

Product requirement, company commitment, and execution evidence are distinct facts even when they use the same amount.

## 1. Public branch exposure

Day-1 public exposure is limited to dUSDC and dwstETH.

| Branch | dToken | Day-1 status | Public exposure |
| ---: | --- | --- | --- |
| 0 | dwstETH | active; prioritized ETH branch | yes |
| 1 | dUSDC | active | yes |
| 2 | dETH | inert | none |
| 3 | dUSD-A | inert | none |
| 4 | dBTC | inert | none |
| 5 | dUSD-B | inert | none |
| 6 | dJPY | inert | none |
| 7 | dJGB | inert | none |

Inert Branches 2–7 are outside frontend, ops dashboard, campaign, SP requirement, liquidity, and liquidator launch scope. Opening any of them requires a separate activation package. `mainnet-launch-operation.config.json` uses `activeBranches: [0, 1]`.

## 2. SP readiness and planned exposure

The Day-1 gate uses absolute SP targets, not a coverage ratio, as the minimum launch requirement.

| Branch | `targetSpJpydf` | `plannedDebtJpydf` |
| ---: | ---: | ---: |
| 0 dwstETH | 15,950,000 JPYdf | 35,000,000 JPYdf |
| 1 dUSDC | 8,330,000 JPYdf | 100,000,000 JPYdf |

`plannedDebtJpydf` is the Day-1 product exposure envelope used as the readiness denominator while branch debt is zero. It is not a dToken cap, debt ceiling, corporate self-mint amount, or executable external borrowing room. Executable capacity must be calculated separately at the freeze block from dToken supply, collateral price, target LTV, existing debt, and upfront fee.

## 3. JPYdf/USDC exit-liquidity requirement

Day 1 uses only the JPYdf/USDC Uniswap v4 route in the [Liquidity Route Policy](../../product/policies/Liquidity-Route-Policy.md).

| Item | Product requirement |
| --- | ---: |
| initial notional | JPY 100,000,000 |
| initial JPYdf | 50,000,000 JPYdf |
| initial USDC value | JPY 50,000,000 equivalent |

LP owner, funding source, company contribution, and allowance-cleanup owner belong to the funding commitment and launch evidence, not this product requirement.

## 4. General-borrower rate targets

These are business targets and operator-managed ranges, not fixed or guaranteed protocol rates and not an automated rate transaction.

| Branch | Normal target | Risk/emergency range | Evidence trigger |
| --- | ---: | ---: | --- |
| dUSDC | ≤2.0% | 2.0%–3.5% | weaker SP coverage, redemption pressure, or JPYdf/USDC peg |
| dwstETH | ≤2.0% | 4.0%–5.5% | the above, wstETH shock, more liquidation candidates, or insufficient LP depth |

## 5. Shortfall and parameter response

Additional corporate or Foundation funding is not a protocol guarantee. If SP requirements are missed or coverage falls after launch, operations choose among a funding-owner-approved top-up, cap reduction, pause, or acceptance of redistribution.

Cap reduction, Vault buffer changes, and `withdrawDelay` changes are protocol-governance operations. Re-evaluate after persistent buffer shortfall, `pendingWithdrawals > bufferBalance`, a Strategy withdrawal-delay change, dToken redemption becoming the peg exit, or a decision to reduce exposure.
