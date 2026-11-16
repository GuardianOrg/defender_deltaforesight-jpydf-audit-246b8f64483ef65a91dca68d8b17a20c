# Docs / Implementation Spec Sync Checkpoint - 2026-06-17

## 0. Scope

- **Base commit**: `origin/develop` = `23db690` (`fix(zappers): harden token approvals`)
- **Purpose**: compare the current docs source of truth with the implementation surface, without weakening the specs, and separate the conditions required to call production PASS from the current interim implementation.
- **Reviewed surfaces**:
  - contracts: `DeployLiquity2.s.sol`, `CollateralYieldZapper`, `SkyUsdcSUsdsYieldZapper`, upstream-style `WETHZapper` / `GasCompZapper` / `Leverage*Zapper`, exchange modules
  - frontend: `frontend/app` borrow / close / update flows, `frontend/df-shared`
  - docs: `Product-Overview.md`, `Frontend.md`, `Zapper.md`, `Development-Plan.md`, `Frontend-Development-Plan.md`, verification ledger

## 1. Sync Principles

1. Keep **spec as the source of truth, plan as the implementation tracker, and ledger as verification evidence**. "Implemented" in a plan is not the same as production PASS.
2. **Auxiliary Zappers are convenience functionality, but they can still be production UX acceptance criteria**. Direct paths remain available under ARCH-005, but PASS for FRNT-FR-013 / SYS-FR-008 is judged by the 1-tx `CollateralYieldZapper` path.
3. **Do not leave the received asset for dToken branches ambiguous**. User-facing close / withdraw defaults to Underlying; receiving dToken is an explicit fallback / advanced flow.
4. **Existing upstream Zapper names are implementation details, not the product-spec source of truth**. Reusing `LeverageLSTZapper` as a generic router for dToken branches is limited to the interim path before CYZ wiring.

## 2. Confirmed Alignment

| Area | Current state | Spec status |
| --- | --- | --- |
| Strategy kind accounting | Aave / ERC4626 / Lido valuation, recovery, and writeoff differences are reflected in docs / console / ops | aligned |
| InterestRouterForwarder | deploy env / handover / verify are wired around `DF_INTEREST_ROUTER_RECIPIENT` / owner | aligned |
| Treasury Day-1 | Treasury.sol is Day-2; Day-1 retains in Vault treasury Safe | aligned |
| Zapper approval hardening | exchange modules use per-swap `forceApprove(amount)` -> `forceApprove(0)`, and the Sky route resets converter / vault allowance to 0 | `Zapper.md` documents the policy. Ledger still lacks execution evidence |
| Product Overview Zapper flow | 1 tx remains target architecture | active CYZ deploy / manifest / binding is wired. Do not treat it as production PASS until user app flow adoption and swap route review |
| Rust liquidator | implementation exists; backend-like components are `bots/liquidator` plus ops exporter | docs should name the actual component whenever they say "backend" |

## 3. High-Priority Gaps

### G-1: FRNT-FR-013 1 Tx Borrow Is Not Production-Complete

**Observed implementation**

- `frontend/app/src/tx-flows/openBorrowPosition.tsx` deposits the shortfall through `CollateralVault.deposit` on dToken branches, then calls `LeverageLSTZapper.openTroveWithRawETH`.
- `DeployLiquity2.s.sol` deploys `CollateralYieldZapper` for active dToken branches and writes it to `dfYield[].collateralYieldZapper` in the manifest.
- `frontend/df-shared/generate.ts` and the app env / ABI surface generate `CollateralYieldZapper` address / ABI.
- The Day-1 CYZ swap dependency is bound to `DFDisabledExchange`, which fail-fast blocks an unreviewed JPYdf swap route. Concrete `SkyUsdcSUsdsYieldZapper` adapter / manifest binding is not wired yet.

**Spec impact**

- `FRNT-FR-013` ("Underlying -> dToken -> Trove through Zapper in 1 tx") is not satisfied by the user app flow.
- Production UX completion for `SYS-FR-008` / `ZAP-FR-001..005` is also incomplete until CYZ user app adoption and e2e evidence.

**Decision**

- Treat the current multi-step flow as a local fallback / direct-path demonstration.
- Treat active-branch CYZ deploy / manifest / binding as complete.
- Treat production PASS as requiring CYZ-family Zapper adoption in the user app flow, reviewed close paths with swap routes, and e2e verification.

**Required implementation**

1. Complete: wire active-branch `CollateralYieldZapper` in `DeployLiquity2.s.sol`, and deploy-assert `collToken == dToken` / `vault.underlying() == underlyingToken` / CYZ dependencies.
2. Complete: generate `collateralYieldZapper` address and ABI in the deployment manifest and `frontend/df-shared` / app env.
3. Incomplete: optionally wire `SkyUsdcSUsdsYieldZapper` as USDC ingress for the dUSDS branch, while keeping native sUSDS ingress in the parent CYZ or explicitly separating it.
4. Incomplete: default `frontend/app` borrow flow to `openTroveWithRawETH*` (existing allowance) or `openTroveWithUnderlyingPermit*` (permit) where CYZ exists. Branches without CYZ must show an explicit multi-step fallback and must not call it 1 tx.

### G-2: FRNT-FR-014 Underlying-Denominated Close / Withdraw Is Not Proven

**Observed implementation**

- `closeLoanPosition.tsx` / `updateBorrowPosition.tsx` uses upstream-style `LeverageLSTZapper` for non-ETH branches.
- For dToken branches, `CollToken` is dToken, so the user-facing received asset being Underlying does not match the CYZ spec.

**Spec impact**

- `FRNT-FR-014-2` (collateral decrease / close defaults to receiving Underlying) is not satisfied.
- Frontend acceptance for `ZAP-FR-006 / ZAP-FR-010 / ZAP-FR-011` is also incomplete.

**Decision**

- Production UX should use CYZ-family Underlying withdrawal / close routes, or an explicit sequential flow of "receive dToken -> Vault redeem".
- Reusing upstream-style `LeverageLSTZapper` does not count as production completion.

**Required implementation**

1. Add CYZ `withdrawCollToUnderlying` / `closeTroveToUnderlying` / `closeTroveFromCollateral` to app flows.
2. If the dToken receive fallback remains, clearly show that the received asset is dToken and Vault redeem is a separate action.
3. Verify in e2e-local whether borrow -> adjust -> close results in received Underlying or queued redeem.

### G-3: Zapper Verification Ledger Is Still Evidence-Empty

**Observed implementation**

- `CollateralYieldZapper.t.sol` includes tests for CYZ / Sky route / residue / allowance reset.
- Many ZAP / FRNT rows in `Requirements-Verification-Ledger.md` remain `Not run`.

**Spec impact**

This is acceptable only if implementation status and verification status are not conflated; many not-run rows should be closed before audit.

**Decision**

- Do not bulk-mark the ledger PASS. Define an execution campaign and update rows with command, commit, and target evidence.

**Required implementation**

1. Create a ZAP campaign using `forge test --match-contract CollateralYieldZapperTest` as evidence.
2. After deploy wiring, use `DeployLiquity2` / local stack / frontend e2e as evidence for FRNT-FR-013 / 014.
3. Judge `ZAP-SEC-006` by code inspection plus zero-first / partial-spend router tests.

### G-4: Backend Terminology Should Match Repository Reality

**Observed implementation**

- There is no `backend/` package.
- Current backend-like components are `bots/liquidator` (Rust keeper) and `frontend/ops` scripts (public stats / route-interest / treasury ledger).

**Decision**

- When docs say "backend", they should specify whether they mean `bots/liquidator`, `frontend/ops` exporter, or a future API service.
- The initial production stats backend remains static JSON from `frontend/ops export-stats`.

## 4. Next PR Acceptance Criteria

CYZ wiring PR must at least satisfy the following.

| Area | Acceptance |
| --- | --- |
| Deploy | Deploy CYZ for active branches and write addresses to the manifest. Optional Sky CYZ is separate PR |
| Deploy asserts | Check `collToken == dToken`, `vault.underlying == underlying`, and `zapper.borrowerOperations/jpydfToken/exchange` consistency |
| Shared bindings | `frontend/df-shared` generates CYZ ABI and branch address. Sky ABI/address is added when the concrete adapter exists |
| Frontend borrow | When CYZ exists, default to `openTroveWithRawETH*` / `openTroveWithUnderlyingPermit*`. Explicit fallback when not wired |
| Frontend close/withdraw | Default to Underlying-denominated CYZ route. Explicit dToken fallback |
| Tests | `forge test --match-contract CollateralYieldZapperTest`, deploy selector/local parity test, frontend app build, relevant tx-flow unit/e2e |
| Docs | Move FE-A2 in `Frontend-Development-Plan.md` back to complete only after CYZ wiring |

## 5. Current Working Classification

| Requirement | Current classification |
| --- | --- |
| `FRNT-FR-013` | Partial: Underlying-denominated input works; CYZ deploy/binding is ready; 1 tx route is blocked by frontend adoption/e2e |
| `FRNT-FR-014` | Partial: position operations exist; Underlying-denominated dToken branch close/withdraw not production-proven |
| `ZAP-FR-001..014` | Implemented in contracts/tests; active CYZ deploy/binding is wired; frontend adoption and ledger campaign pending |
| `ZAP-SEC-006` | Source aligns with temporary allowance design; needs campaign evidence |
| `SYS-FR-008` | Not complete until CYZ is wired into production user flow |
