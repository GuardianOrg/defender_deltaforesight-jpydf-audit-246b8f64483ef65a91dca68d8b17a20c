# JPY DeFi Permissionless User-Operation Requirements

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Draft |
| Owner | DeltaForesight |
| Target | Public User App (`frontend/app`) and the permissionless state-changing surface in `contracts/src` |
| Parent requirement | [Frontend](Frontend.md) `FRNT-FR-038` |
| Related docs | [Parameters](../../../Parameters.md) (value source of truth) and each component specification (contract-behavior source of truth) |

## 1. Purpose, Scope, and Source-of-Truth Boundary

This document exhaustively maps permissionless state-changing entrypoints implemented in `contracts/src` to their public User App treatment. For each catalog operation, it defines the public-app route, selected entrypoint, conditional visibility, and intentional exclusions.

The scope includes entrypoints through which users manage their own assets, Loans, or deposits; entrypoints usable by managers/delegates appointed by a Loan owner; and keeper operations executable by anyone when their preconditions hold. It excludes calls requiring GOV, GUARDIAN, ALLOCATOR, WRITEOFF, an owner, bridge admin/minter, or a registered protocol contract.

“Permissionless” does not mean that every direct entrypoint needs a separate screen or can succeed unconditionally. Balance, allowance, permit, ownership, Loan state, price, pause, cap, shutdown, and epoch preconditions remain governed by the component specifications.

The sources of truth are divided as follows:

- [Frontend](Frontend.md) owns `FRNT-*`; this document is the exhaustive matrix required by FRNT-FR-038.
- This document normatively defines permissionless-operation coverage and public-app execution paths.
- Component specifications own caller constraints, accounting, reverts, events, and state transitions.
- [Parameters](../../../Parameters.md) owns parameter values.

The stable key for each catalog row is component plus function name, with an identifiable signature for overloads. Environment-specific addresses, public branches, and optional deployments come from deployment manifests, generated bindings, the public route catalog, and activation gates rather than duplicated fixed values here.

## 2. Public-App Mapping Principles

1. Aggregate by user goal: when an Underlying-denominated Zapper or protected Helper fulfills a direct Core goal, use it as the standard route and do not duplicate the direct operation.
2. Preserve conditional operations: zombie Loans, liquidation surplus, queued redemption, stashed collateral gains, batch participation, and branch shutdown must become reachable from the same asset/position context when applicable.
3. Use quote-only helpers through `eth_call`, never as signed transactions.
4. Put approvals inside their purpose flow and show the actual spender, token, and amount.
5. Delegate standard ERC-20/ERC-721 transfers and approvals to wallets and explorers.
6. Keep user and operator surfaces separate: batch-manager administration, keepers/bots, Strategy maintenance, and incentive distribution do not belong in the public app.
7. Fail closed for optional modules until deployment, wiring, bindings, requirements, and verification are all complete.
8. Update every affected row when a permissionless entrypoint or standard path changes.

## 3. Borrower Operations — BorrowerOperations / TroveNFT

The public standard path is an Underlying-denominated Zapper used by the Loan owner. There is no third-party manager operations UI.

| Catalog operation | Public-app treatment |
| --- | --- |
| `BorrowerOperations.openTrove(...)` | `/borrow/:coll` uses Zapper `openTroveWithRawETH`; confirm collateral, debt, rate, fee limit, and connected-wallet ownership (FRNT-FR-006,013,038) |
| `openTroveAndJoinInterestBatchManager(...)` | Pass a valid registered manager from `Custom delegate` mode into the Zapper open request; invalid, missing, or unavailable selection blocks submission while `Manual` remains available (FRNT-FR-013,038) |
| `addColl(...)` / `withdrawColl(...)` | `/loan/colldebt` uses Zapper `addCollWithUnderlying` / `withdrawCollToUnderlying`; display received assets in Underlying units (FRNT-FR-014,038) |
| `withdrawJpydf(...)` / `repayJpydf(...)` | `/loan/colldebt` uses the equivalent Zapper calls (FRNT-FR-006,007,014,038) |
| `adjustTrove(...)` / `adjustZombieTrove(...)` | `/loan/colldebt` uses `adjustTroveWithUnderlying` or, only for a zombie Loan, `adjustZombieTroveWithUnderlying`; verify hints, approval, and calldata with a zombie fixture (FRNT-FR-014,038) |
| `adjustTroveInterestRate(...)` | `/loan/rate` `Manual` changes the owner's rate; no UI for acting as another Loan's individual delegate (FRNT-FR-014,038) |
| `closeTrove(...)` | `/loan/close` uses `closeTroveToUnderlying`; show latest debt, required balance, returned Underlying and gas compensation; the JPYdf approval is bounded to the required amount plus the 0.1% execution buffer, with spender, cap, and buffer rationale shown in the approval step (FRNT-FR-007,014,038) |
| `claimCollateral()` | Show `Claim remaining collateral` only for a positive liquidation surplus; distinguish fetch failure from zero/claimed, then link the collateral claim to `/vault` for Underlying redemption (FRNT-FR-015,020,038) |
| `setAddManager(...)` / `setRemoveManager(...)` / `setRemoveManagerWithReceiver(...)` | No public manager-configuration UI (FRNT-FR-014,038) |
| `setInterestIndividualDelegate(...)` / `removeInterestIndividualDelegate(...)` | `Custom delegate` targets registered batch managers; no individual-delegate configuration UI (FRNT-FR-014,038) |
| `TroveNFT.approve(...)` / `setApprovalForAll(...)` | Delegate standard ERC-721 approval to wallets/explorers (FRNT-FR-020,038) |
| `TroveNFT.transferFrom(...)` / `safeTransferFrom(...)` overloads | Delegate transfer to wallets/explorers; after transfer, follow on-chain ownership and surface surviving manager/delegate/batch state to the new owner (FRNT-FR-014,020,038) |

## 4. Interest Batches — BorrowerOperations

The public app lets a borrower select a registered batch; it does not administer batch managers. Loading, zero registrations, and fetch failure are distinct states.

| Catalog operation | Public-app treatment |
| --- | --- |
| `registerBatchManager(...)` / `setBatchManagerAnnualInterestRate(...)` / `lowerBatchManagementFee(...)` | No batch-manager administration UI (FRNT-FR-014,038) |
| `setInterestBatchManager(...)` | `/loan/rate` `Custom delegate` selects a registered manager and previews rate, fee, and redemption risk (FRNT-FR-014,038) |
| `removeFromBatch(...)` | `/loan/rate` `Manual` leaves a batch after the user enters an individual rate (FRNT-FR-014,038) |
| `switchBatchManager(...)` | `/loan/rate` `Custom delegate` switches to another registered manager (FRNT-FR-014,038) |

## 5. Stability Pool Depositors — DFStabilityPool

The "recorded deposit" used for entrypoint selection is `deposits[account].initialValue` — the value `withdrawFromSP` / `claimAllCollGains` verify for the caller. Liquidations can zero the displayed compounded deposit while it stays positive, so the displayed value must not substitute for it.

| Catalog operation | Public-app treatment |
| --- | --- |
| `provideToSP(...)` | `/earn/:pool/deposit` `Deposit`; preview treatment of existing gains and identify collateral gains as collateral claims (FRNT-FR-017,038) |
| `withdrawFromSP(...)` | Used by deposit withdrawal, claims with a positive recorded deposit, and compound. Detect same-block/minimum-balance constraints in pre-send simulation (FRNT-FR-006,017,038) |
| `claimAllCollGains()` | When the recorded deposit is zero and stashed collateral gain is positive, `/earn/:pool/claim` must use this selector, including fee estimation; do not create `withdrawFromSP(0, true)` (FRNT-FR-017,038) |

## 6. JPYdf Holders — CollateralRegistry / RedemptionHelper / JpydfToken

| Catalog operation | Public-app treatment |
| --- | --- |
| `CollateralRegistry.redeemCollateral(...)` | Do not expose the direct call; use the protected RedemptionHelper path (FRNT-FR-018,038) |
| `RedemptionHelper.redeemCollateral(...)` | `/redeem` previews the redemption/max fee, per-branch minimum receipts, returned collateral claims, and next `/vault` step (FRNT-FR-018,038) |
| `RedemptionHelper.simulateRedemption(...)` | Not a standard quote path or signed operation (FRNT-FR-018,038) |
| `RedemptionHelper.truncateRedemption(...)` | Use through `eth_call` for quote/executable-amount calculation (FRNT-FR-018,038) |
| `JpydfToken.transfer(...)` / `transferFrom(...)` | Delegate standalone transfers to wallets (FRNT-FR-020,038) |
| `approve(...)` / `increaseAllowance(...)` / `decreaseAllowance(...)` | Offer only inside redemption, repayment, SP, close, and other purpose flows (FRNT-FR-007,038) |
| `permit(...)` | Expose only in an end-to-end implemented and verified permit flow; otherwise use an explicit exact-amount approve (no unlimited approvals) (FRNT-FR-007,038) |

## 7. dToken Layer — CollateralVault / DToken

Borrow/Zapper is the Underlying-to-Loan entry. `/vault` is the collateral-claim-to-Underlying exit and queued-redemption surface.

| Catalog operation | Public-app treatment |
| --- | --- |
| `CollateralVault.deposit(...)` | No standalone deposit UI; aggregate into Borrow/Zapper Underlying input (FRNT-FR-013,015,038) |
| `redeem(...)` | Branch-specific `/vault` `Redeem`; distinguish immediate-receipt estimate from queue estimate and never guarantee immediacy (FRNT-FR-015,016,038) |
| `redeemWithPermit(...)` | Not standard; add end-to-end permit requirements and verification before future adoption (FRNT-FR-007,015,038) |
| `claim(...)` | Show request owner, amount, claimable time, and funding state in `Queued claims`; enable only when claimable and do not create duplicate requests during shortage (FRNT-FR-016,038) |
| `backstopDeposit(...)` | No public UI because the contribution carries no withdrawal right and must not be represented as user investment (`FRNT-FR-015`, `FRNT-FR-021`, `FRNT-FR-038`) |
| `DToken.transfer(...)` / `transferFrom(...)` | Delegate standalone transfers to wallets (FRNT-FR-020,038) |
| `DToken.approve(...)` / `increaseAllowance(...)` / `decreaseAllowance(...)` | No standalone allowance UI (FRNT-FR-007,038) |
| `DToken.permit(...)` | No public direct-Core flow; public borrowing uses Underlying/Zapper (FRNT-FR-007,013,038) |

## 8. Zapper — CollateralYieldZapper / SkyUsdcSUsdsYieldZapper

Collateral input is ERC-20 Underlying. `msg.value` is used only to wrap fixed gas compensation into WETH. The public app uses owner-only standard paths and offers no manager UI.

| Catalog operation | Public-app treatment |
| --- | --- |
| `openTroveWithRawETH(...)` | Standard open entrypoint for a borrowable branch in the public route catalog that passes its activation gate (FRNT-FR-012,013,038) |
| `openTroveWithRawETHAndReferral(...)` | Use only with a canonical code returned by an active referral registry; otherwise retain the normal entrypoint (FRNT-FR-013,038) |
| `openTroveWithUnderlyingPermit(...)` / `openTroveWithUnderlyingPermitAndReferral(...)` | No permit-open UI until end-to-end requirements and verification are added (FRNT-FR-007,013,038) |
| `addCollWithUnderlying(...)` / `withdrawCollToUnderlying(...)` | `/loan/colldebt` deposit/withdraw standard paths (FRNT-FR-014,038) |
| `withdrawCollToUnderlyingWithMin(...)` | Not standard; adoption must explain that the protected minimum excludes a delayed request (FRNT-FR-014,038) |
| `withdrawJpydf(...)` / `repayJpydf(...)` | `/loan/colldebt` borrow/repay standard paths (FRNT-FR-007,014,038) |
| `adjustTroveWithUnderlying(...)` / `adjustZombieTroveWithUnderlying(...)` | Normal/zombie combined collateral-and-debt adjustment paths (FRNT-FR-014,038) |
| `adjustTroveWithUnderlyingWithMin(...)` / `adjustZombieTroveWithUnderlyingWithMin(...)` | Not standard entrypoints (FRNT-FR-014,038) |
| `closeTroveToUnderlying(...)` | `/loan/close` standard path (FRNT-FR-014,038) |
| `closeTroveToUnderlyingWithMin(...)` | Not a standard entrypoint (FRNT-FR-014,038) |
| `setAddManager(...)` / `setRemoveManager(...)` / `setRemoveManagerWithReceiver(...)` | No public manager UI (FRNT-FR-014,038) |
| `SkyUsdcSUsdsYieldZapper.openTroveWithUsdc(...)` / `openTroveWithUsdcAndReferral(...)` | Deployment alone does not expose the route. Require binding, public route, activation gate, asset/price/slippage/referral requirements, and E2E (FRNT-FR-004,012,013,038) |
| `SkyUsdcSUsdsYieldZapper.addCollWithUsdc(...)` | Do not expose until the Sky-open activation conditions are complete (FRNT-FR-004,012,014,038) |

Upstream leverage, Multiply, and flash-close entrypoints are absent from production source and the public app (`FRNT-FR-014`, `FRNT-FR-023`).

## 9. Swap and Conversion Utilities

These optional utilities have no standard public UI. Future exposure requires asset, price, slippage, receiver, failure, and route requirements in [Frontend](Frontend.md), updated together with this matrix.

| Catalog operation | Public-app treatment |
| --- | --- |
| `UniV4Exchange.swapToJpydf(...)` / `swapFromJpydf(...)` | No standalone swap UI (FRNT-FR-004,038) |
| `SkyUsdcSUsdsConverter.convertUsdcToUsds(...)` / `convertUsdsToUsdc(...)` | No public optional-Sky utility UI (FRNT-FR-004,038) |
| `WeETHWithdrawAdapter.requestWithdraw(...)` | No public optional-weETH utility UI (FRNT-FR-004,038) |

## 10. Liquidation and Maintenance Operations

Permissionless maintenance that is not a user's own asset operation belongs to keepers/bots. Shutdown urgent redemption is the exception because it spends the user's JPYdf.

| Catalog operation | Public-app treatment |
| --- | --- |
| `TroveManager.batchLiquidateTroves(...)` / `BorrowerOperations.applyPendingDebt(...)` / `kickFromBatch(...)` | Keeper/liquidator responsibility; no public UI (FRNT-FR-038) |
| `BorrowerOperations.shutdown()` | Permissionless safety operation, but no manual public UI (FRNT-FR-038) |
| `TroveManager.urgentRedemption(...)` | `/redeem/shutdown`; enable only when a branch is shut down (FRNT-FR-018,038) |
| `TroveManager.getUnbackedPortionPriceAndRedeemability()` | Not a public quote/sign/send operation; an operations monitor may use `eth_call` (FRNT-FR-008,038) |
| `PriceFeedProxy.fetchPrice()` / `fetchRedemptionPrice()` | May be used internally through `eth_call`; no user transaction UI (FRNT-FR-008,038) |
| Concrete price-feed `fetchPrice()` / `fetchRedemptionPrice()` functions | Do not call concrete sources as public operations; use the Proxy. [Oracle](Oracle.md) owns source composition (`FRNT-FR-008`, `FRNT-FR-032`, `FRNT-FR-038`) |
| `CollateralVault.refreshStrategyValuation(...)` | Keeper/operations responsibility (FRNT-FR-033,038) |
| `InterestRouterForwarder.route()` / `PILAllocator.distribute()` | Keeper/operations responsibility (FRNT-FR-034,038) |
| `UniV4MerklInitiative.createCampaign()` | Incentive-keeper responsibility (FRNT-FR-034,038) |
| `LidoStrategy.claimLidoWithdrawals(...)` / `EtherfiWeETHStrategy.claimEtherfiWithdrawals(...)` | Strategy-keeper responsibility (FRNT-FR-033,038) |

## 11. Scope Boundary and Update Rules

- Technical `receive()` functions are excluded when they are not product operations or do not add received ETH to Strategy valuation automatically.
- `CollateralYieldZapper.receive()` accepts only WETH unwraps and rejects general senders, so it is not permissionless.
- Pure placeholder feeds and no-op hooks are excluded.
- View/pure getters, initializers, upgrades, pause/cap/allocation/source-replacement/mint/burn/ownership calls, and privileged protocol-only entrypoints are excluded.
- External Merkl Distributor claims are outside `contracts/src`.
- Future-only Treasury, reward distributors, and JPYdf wrappers absent from production source are excluded.
- Lack of public UI does not restrict direct permissionless contract access.
- Changes to the permissionless production surface must update this matrix, FRNT-FR-038, related requirements, transaction-flow tests, and conditional E2E fixtures in the same change.

## 12. Acceptance Criteria and Verification

| Subject | Acceptance criterion | Primary verification |
| --- | --- | --- |
| Catalog completeness | Every permissionless state-changing production ABI entrypoint maps to a row or explicit §11 exclusion | Mechanical ABI/source caller-check reconciliation |
| FRNT trace | Every row references FRNT-FR-038 and applicable existing `FRNT-*` | Non-empty and valid-ID check |
| Public operations | Each offered operation is reachable from its user-goal route with matching entrypoint, spender, asset, and receiver | Transaction-flow unit/component/E2E |
| Conditional operations | Zombie, liquidation surplus, queued claim, zero SP deposit plus stashed gain, batch manager, and shutdown fixtures choose the correct CTA, selector, calldata, and degraded state | Fixture-driven E2E |
| Read helpers | `eth_call` helpers never appear as sign/send steps | Transaction-flow unit/E2E |
| Excluded operations | Operations marked “no UI” do not enter public navigation or transaction builders | Route/build/catalog guard |
| Cross-cutting safety | Approval, simulation, errors, freshness, presentation, and accessibility satisfy [Frontend](Frontend.md) | Frontend §13 verification ledger |

## 13. Related Specifications

[Frontend](Frontend.md) / [Liquity v2 Core](Liquity-v2-Core-Spec.md) / [JpydfToken](JpydfToken.md) / [dToken](dToken.md) / [CollateralVault](CollateralVault.md) / [Zapper](Zapper.md) / [Oracle](Oracle.md) / [InterestRouter](InterestRouter.md) / [PILAllocator](PILAllocator.md) / [Strategy](strategies/Strategy.md)
