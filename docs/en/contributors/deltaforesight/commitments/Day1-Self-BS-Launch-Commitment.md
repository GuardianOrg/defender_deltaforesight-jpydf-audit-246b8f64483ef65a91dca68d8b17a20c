# DeltaForesight Day-1 Self-B/S Launch Commitment

| Item | Value |
| --- | --- |
| Status | Active |
| Role | Canonical company record for Day-1 bootstrap Troves, SP seed, JPYdf/USDC LP, and manual top-up amounts and owner classes funded from DeltaForesight's own balance sheet |
| Decision owner | DeltaForesight Inc.; approved and executed solely as a corporate-funds decision |
| Product requirement | [Mainnet Launch Product Decision Record](../../../protocol/launch/decisions/Mainnet-Launch-Product-Decision-Record.md) |
| Calculation basis | [Day-1 Self-B/S Initial Liquidity Plan](Day1-Self-BS-Initial-Liquidity-Plan.md) |
| Out of scope | protocol parameters, Foundation assets, product requirements, gate procedures, real addresses/signers/nonces/secrets, and transaction evidence |

Real addresses, signers, nonces, secrets, balances, and transactions belong in the launch evidence package and `mainnet-launch-operation.config.json`.

## 0. Corporate-asset boundary

Corporate B/S funds cover the bootstrap Troves, SP seed, JPYdf/USDC LP, and any manually approved inventory top-up or JIT action. Foundation treasury, Treasury-retained Strategy yield, and protocol revenue are not corporate assets and require separate Foundation approval before use. A corporate approval does not execute a protocol-governance action such as cap reduction, pause, or Vault-buffer change.

## 1. Budget reconciliation

Cash outlay, deployed-market notional, and self-minted JPYdf are different quantities.

| View | Reconciliation | Total |
| --- | --- | ---: |
| corporate B/S cash outlay | JPY 92.77m bootstrap collateral + JPY 7.23m + JPY 50m USDC side of LP | JPY 150m budget ceiling |
| self-mint and uses | JPYdf 69.58m + 4.70m = 50m LP side + 8.33m SP + 15.95m SP | 74.28m JPYdf |
| company-deployed market notional | JPY 100m LP + JPY 8.33m SP + JPY 15.95m SP | JPY 124.28m |

Self-minted JPYdf is collateralized by the bootstrap assets and is not counted again as a cash outlay.

## 2. Bootstrap Troves

| Item | Company-adopted value / owner |
| --- | --- |
| borrower owner | `BOOTSTRAP_BORROWER_OWNER` |
| accounting owner | `financeOwner` |
| dUSDC bootstrap | mint 69.58m JPYdf; JPY 92.77m equivalent USDC collateral; 75% LTV; 2.0% borrow APR anchor |
| dwstETH bootstrap | mint 4.70m JPYdf; JPY 7.23m equivalent wstETH collateral; 65% LTV; 2.0% borrow APR main path |
| company rate policy | 2.0% normal anchor for both branches; managed range 1.5%–2.5%; use risk mode only after checking branch state, SP coverage, redemption pressure, peg, and LP depth; no automated rate transaction |
| Trove structure | one Trove per branch by default; dUSDC may use at most two after accounting, repayment-plan, and per-Trove evidence approval; never split into three or more |
| unwind | no automatic unwind; `financeOwner` and `riskOwner` approve repayment source and order and retain the decision log |

The dwstETH bootstrap Trove is not excluded from third-party redemption.

## 3. Company SP seed

| Branch | `companySpContributionJpydf` | Source | Owner class |
| ---: | ---: | --- | --- |
| 0 dwstETH | 15,950,000 JPYdf | bootstrap-Trove self-mint | `SP_SEED_SOURCE_OWNER` |
| 1 dUSDC | 8,330,000 JPYdf | bootstrap-Trove self-mint | `SP_SEED_SOURCE_OWNER` |

`SP_SEED_SOURCE_OWNER` is the company Launch/Ops finance Safe in the [DeltaForesight Launch Operations Holder Manifest](../../../../jp/contributors/deltaforesight/manifests/Mainnet-Launch-Operations-Holder-Manifest.md). The [Safe Role Assignment Gate](../../../protocol/launch/gates/Mainnet-Safe-Role-Assignment-Gate.md) freezes the real address and signer evidence. LP seed, SP seed, Treasury retention, and backstop funding are never double-counted.

## 4. Company JPYdf/USDC LP commitment

| Item | Company-adopted value / owner |
| --- | --- |
| LP owner | `LP_OWNER` |
| JPYdf contribution | 50,000,000 JPYdf from bootstrap self-mint |
| USDC contribution | JPY 50,000,000 equivalent from the company B/S |
| allowance-cleanup owner | `LP_OWNER` |

Venue, pair, fee, tick spacing, and hook policy are canonical in the [Liquidity Route Policy](../../../protocol/product/policies/Liquidity-Route-Policy.md).

## 5. Company launch owners

| Config field | Corporate responsibility |
| --- | --- |
| `launchOwner` | reconcile product requirements with corporate funding readiness |
| `riskOwner` | approve corporate exposure and SP/redemption/liquidation risk |
| `financeOwner` | approve self-mint, SP seed, LP, repayment, and accounting |
| `opsOwner` | execute launch, monitor, run bot dry-runs, and retain evidence |
| `incidentOwner` | initial response to depeg, liquidation, oracle, or ops incidents |

These are corporate-operation roles, not Foundation or protocol-governance owners.

## 6. Manual inventory top-up / JIT

Automatic JIT or top-up is not a Day-1 company commitment. If the company chooses a manual action:

| Config field | Adopted value |
| --- | --- |
| `manualJitTopUpOwner` | `SP_SEED_SOURCE_OWNER` |
| `jitFundingSource` | JPYdf inventory in the company Launch/Ops finance Safe; excludes Foundation-owned Treasury-retained yield |
| `spShortfallDecisionOwner` | `riskOwner` |
| `redistributionDecisionOwner` | `riskOwner` |
| `collateralDisposalOwner` | `financeOwner` |
| `failedReceiptEscalationOwner` | `opsOwner` |

This does not guarantee additional funding or successful liquidation. If no top-up is made, cap reduction, pause, or acceptance of redistribution follows the Product Decision Record and protocol governance.

## 7. Initiating a protocol change

The company `riskOwner` may propose re-evaluating Vault buffer, `withdrawDelay`, or exposure; `financeOwner` and `opsOwner` assess corporate and execution impact. Corporate review is not protocol approval. Any change remains a separate GOV/Timelock action.
