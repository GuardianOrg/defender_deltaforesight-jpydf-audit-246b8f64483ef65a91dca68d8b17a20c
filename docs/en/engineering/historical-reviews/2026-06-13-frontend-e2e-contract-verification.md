# Contract Functionality Verification Report via Frontend (Local Real-Machine E2E)

- **Created**: 2026-06-13
- **Verifier**: Claude Code (Opus 4.8 1M context)
- **Verification Target**: `deltaforesight/jpydf-v2` `develop` @ `7741513` (frontend=PR#58, phase4 deploy wiring=PR#38, Aave accounting hardening=PR#65 all merged)
- **Positioning**: This file is a record, **independent** of [2026-06-13-requirements-verification-campaign-V1.md](2026-06-13-requirements-verification-campaign-V1.md) (PR#64 = per-ID `forge` ledger), of **real Tx verification of contract functionality via the frontend on the latest develop tip using a real local environment**.
- **Regarding the basis `e2e-local(PR#58@827e803)` in the V1 ledger `§14 FRNT` (important correction)**: `827e803` is an **intermediate commit on the PR#58 branch (`feat/frontend-local-surfaces`)** (an **ancestor** of PR#58 head `4cb0a68e`), and **the tree pointed to by that commit already has the frontend fully implemented** (`VaultScreen.tsx`/`ops/src/App.tsx`/`console/src/App.tsx`/`df-hooks.ts`, etc. exist). The commit **diff** only deletes `.claude/launch.json`, but because a **commit SHA points to the entire tree, not the diff**, `PR#58@827e803` is a **valid verification-point SHA and the FRNT e2e-local verification is reproducible**. The initial statements in this file that “827e803 is unrelated to frontend and unreproducible” and “it should be corrected to head `4cb0a68e`” were **incorrect (confusing commit diff with tree) and are withdrawn** (rewriting to 4cb0a68e would tamper with the verification provenance).
  - Note that `827e803` is **not an ancestor** of PR#64’s verification target `d4c69d2` (the record is that FRNT was verified on a separate lineage using the SHA of the PR#58 branch that includes the frontend. The ledger header also explicitly separates this as “target develop @ d4c69d2 (FRNT only PR#58 @ 827e803)”). The PR body description “unmerged PR#58” was accurate at the time V1 was created; PR#58 is now merged (freshness difference).

---

## 0. Conclusion Summary

- **The frontend does not start with the standard configuration (`pnpm build-deps && pnpm dev`)** (`build-graphql` fails due to a subgraph dependency → subsequent steps do not run and styled-system/uikit are not generated). Startup succeeded by using committed graphql artifacts, manually running `build-uikit`/`build-panda`, and restarting dev. This is consistent with Codex’s note that “the standard configuration does not pass.”
- **After startup, all 3 surfaces (app / console / ops) worked**, and major contract functionality could be confirmed through real Tx via the frontend: app=**openTrove, Vault deposit, adjustTrove(increase borrowing/decrease collateral), closeTrove**, console=**allocate, proposeSource, cancelSourceProposal** (**8 total**). Many reads (price, TCR, CCR, MCR, SCR, BCR, backingRatio, buffer, strategy, oracle, treasury, permissions) were also displayed correctly across all surfaces. **However, Earn(SP) could not be completed due to the FE-1 bug, and redeem could not be completed from the frontend due to a subgraph dependency** (§4).
- **Two new defects were found through frontend-based verification**: ① **Earn screen (`/earn/[pool]`) cannot be opened due to a Runtime Error** (`generateStaticParams` does not generate pools and violates the `output: export` constraint) / ② **Redemption Fee 95.8%** (observation: local demo baseRate is abnormally high). In addition, Codex’s reported getLiquidationRisk vitest failure and FRNT-FR-014 adjust `#edf` were also corroborated in the actual code.
- (Initial state) SP deposit could not proceed because the Earn screen did not open due to the FE-1 bug, and redeem could not be completed from the frontend due to a subgraph dependency. **→ After fixing FE-1 and starting the subgraph in §8, both SP deposit and redeem succeeded as real Tx via the frontend**. Ultimately, **frontend write operations totaled 10** (§2=8 + §8=2 for SP deposit and redeem).

---

## 1. Environment Setup (Reproduction Steps and Pitfalls)

| Step | Details | Result |
|---|---|---|
| clone | Dedicated clone of `develop` @ `7741513` + `submodule update --recursive` | OK |
| build | `forge build` (contracts) | OK (lint warnings only) |
| install | root workspace `pnpm install` | OK |
| chain | `anvil --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000` | OK |
| stack | `utils/local-stack.sh` (8-branch deploy → **inject Multicall3 with `anvil_setCode`** → SeedLocalDemo → generate `.env.local` / console and ops bindings) | OK (active 5=dETH/dUSDC/dUSDT/dUSDS/dXAUT, inert 3 skipped) |
| frontend deps | `pnpm build-deps` | **✗ `build-graphql` failed with `ECONNREFUSED localhost:8000` (subgraph not running) → `&&` chain broke and `build-uikit`/`build-panda` did not run** |
| workaround | Use committed artifacts in `src/graphql/` (no subgraph required) + run `build-uikit` / `build-panda` individually → **restart dev** | OK (uikit/styled-system resolved, `GET / 200`) |
| app | `pnpm dev` (Next.js, :3000) | OK |
| console | `pnpm dev` (Vite, :3001) | OK |
| ops | `pnpm dev` (Vite, :3002) | OK |

> **Recorded Note**: local-stack.sh has scripted the Multicall3 injection that Codex previously handled manually as a workaround, and SeedLocalDemo also inserts demo troves correctly (Codex’s `DebtBelowMin()` from `--open-demo-troves` does not occur). Meanwhile, **the app’s `build-deps` still assumes the subgraph is running**, so if the subgraph is not started, the workaround steps in this file are required.

---

## 2. Real Tx Verification via Frontend (On-Chain Finalized)

| # | Functionality (Contract Requirement) | Surface / Path | Operation | Result | tx |
|---|---|---|---|---|---|
| 1 | **openTrove** (SYS-FR-001 / ZAP-FR-001 / VAULT-FR-001 / DTKN-FR-004 / CORE BorrowerOperations) | app `/borrow/deth` | Collateral 2 dETH, borrow 600,000 JPYdf, interest 5% → Approve WETH → **Wrap WETH→dETH (Vault.deposit / dToken mint)** → Approve dETH → **Open Position** | ✅ “created successfully”. trove count 4→**5**, dev-wallet dETH balance=**0** (collateral locked), gas 746,682 | `0x246aedb2…`(block 456) |
| 2 | **Vault deposit** (VAULT-FR-001 / DTKN-FR-004 / DTKN-INV-001 18dec 1:1) | app `/vault` Deposit | 1 WETH → Approve → Deposit | ✅ “dETH has been minted successfully”/**1 WETH=1 dETH** | `0x16ec4fda…`(block 458) |
| 3 | **allocate** (VAULT-FR-004 / STGY push / VAULT-INV-006) | console “ALLOCATOR Operations” | Execute allocate (send excess buffer 47.2 WETH to Strategy) | ✅ “Execution succeeded”/buffer **59→11.8 WETH**/Strategy principal **47.2 WETH**/ops event reflected | `0x430c2b34…`(block 459) |
| 4 | **adjustTrove increase borrowing** (CORE BorrowerOperations) | app `/loan` Update Loan→Borrow | Borrow +100,000 JPYdf | ✅ “updated successfully”/600,493→700,575 JPYdf/LTV 50→58%/**1 step “Borrow BOLD” (not via gasCompZapper)** | `0x3db0257b…` |
| 5 | **adjustTrove decrease collateral** (CORE BorrowerOperations) | app `/loan` Update Loan→Withdraw | Collateral −0.3 dETH | ✅ “updated successfully”/2.0→1.7 dETH/LTV 58→68%/1 step “Withdraw Collateral” | `0x8d209a8f…` |
| 6 | **closeTrove** (CORE/full JPYdf repay + collateral receipt) | app `/loan/close` | Repay & close | ✅ SUCCESS/2 steps “Approve BOLD” → “Close loan” | (trove 5→4) |
| 7 | **proposeSource** (ORCL-FR-001/oracle source replacement proposal) | console “Oracle” | Propose new source | ✅ proposedSource set/**timelock 24h**/price deviation guard | (block progress) |
| 8 | **cancelSourceProposal** (ORCL-FR-003) | console “Oracle” | Cancel proposal | ✅ proposal cleared/current source restored | (block progress) |

> ⚠️ **This table = real UI Tx via frontend**: 5 app operations (open / deposit / increase borrowing / decrease collateral / close) + 3 console operations (allocate / proposeSource / cancel). **Earn(SP) deposit and redeem could not be completed through the frontend** (former=FE-1 routing bug, latter=subgraph dependency. §4 FE-1/FE-6). SP cast supplementation (§5) is outside the E2E verification scope and is not included in this table.

---

## 3. Read Verification via Frontend (by Surface)

- **app (dashboard / borrow / vault / redeem)**: Prices for 5 collateral branches (JPY-denominated), Max LTV, TCR, CCR, total debt, SP pool size, JPYdf price (¥1.001), TVL (¥91M), creation fee, liquidation price, LTV, **Refundable gas deposit 0.0375 ETH** (`ETH_GAS_COMPENSATION` reflected), redeem allocation calculation across 5 collaterals.

- **console (JPYdf Admin Console)**: All roles (GOV/ALLOCATOR/GUARDIAN/WRITEOFF/Oracle owner/DToken owner), branches #0-4 active / #5-7 inert (disabled), Vault state (**backingRatio 100%**, buffer target 20%, bufferFloor 0, unlimited dToken cap, totalSupply, withdrawDelay 24h, unlimited allocateMaxMove, allocatorCooldown 0, totalWeightBps 100%), Strategy list, various address wiring, `transferYieldToTreasury` (surplus 0).
- **ops (operations dashboard, read-only / FRNT-FR-031 through 036)**: Total supply, total collateral, aggregate collateral ratio 157.4%, active 5/8, all systems normal, all parameters for all branches + backing 100%, oracle monitoring (shared JPY/USD feed ¥150, freshness 28 minutes / threshold 3 days, fetchPrice/lastGoodPrice/source/proposed source/collateral USD aggregator/freshness for each collateral), Vault and Strategy monitoring (all branches, allocated principal, estimated valuation, P&L), Treasury cumulative revenue, allocation/deposit/redemption event history (including the Tx from this verification).

---

## 4. Issues and Findings Discovered

| ID | Severity | Details | Evidence |
|---|---|---|---|
| FE-1 | 🟡 Medium | **Earn screen `/earn/deth` cannot be opened due to a Runtime Error**: `Page "/earn/[pool]/page" is missing param "/earn/deth" in generateStaticParams(), which is required with "output: export"`. Since `/borrow/[collateral]` opens, this is a missing `generateStaticParams` implementation specific to Earn. SP deposits **cannot be performed from the frontend**. | Playwright on actual machine (dev). The SP function itself works via cast `provideToSP` (§2-4), so this is a frontend issue, not a contract issue |
| FE-2 | 🔵 Low | **Redemption Fee 95.80%** is shown abnormally (redeem screen). The local demo baseRate is in an extremely high state. Actual redeem has no economic value. This is separate from the production baseRate, but should be checked as demo/display behavior. | app `/redeem` (when entering Max 8.1M JPYdf) |
| FE-3 | 🔵 Low | **Standard `build-deps` fails due to subgraph dependency** (§1). The local startup procedure without a subgraph has not been runbooked. | `app-builddeps.log` (ECONNREFUSED:8000) |
| FE-4 | 🟡 Medium | **getLiquidationRisk(ltv=0) returns "not-applicable", but the test expects "low" -> vitest 1 failed** (confirmed Codex report against actual code). | `liquity-math.ts:30` `dn.eq(ltv,0)->"not-applicable"` vs `liquity-math.test.ts:60` |
| FE-5 | 🔵 Low (updated) | **FRNT-FR-014 (borrow increase / collateral reduction `#edf`) is not reproducible on develop tip `7741513`**. In frontend actual Tx, both borrow increase (`0x3db0257b`) and collateral reduction (`0x8d209a8f`) **succeeded** (both are one-step flows not via gasCompZapper: “Borrow BOLD” and “Withdraw Collateral”). Codex’s `#edf` report was from the `d4c69d2` SHA series, and is judged to have been resolved by the develop tip. | Actual Tx in this verification §2-#4/#5 |
| FE-6 | 🟡 Medium | **redeem cannot be completed in the frontend due to subgraph dependency**: The calculation (fee 88-95% / distribution across 5 collaterals) is displayed, but at the Approve BOLD step it fails with “Error while fetching data from the subgraph”. In a local environment without the subgraph running, the redeem actual Tx cannot be completed (fetching data for redemption hints depends on the subgraph). | This verification, redeem Approve failure |

> FE-1 / FE-4 / FE-6 are **frontend-layer constraints/bugs**, not issues with the contracts (Core/dToken/Vault/Strategy/Oracle). Contract functionality has been confirmed to work normally in §2 (8 actual Tx) and §3 (reads). FE-5 is resolved at the develop tip.

---

## 5. cast Supplementation (Frontend-Private Features)

Among the contract functions that the frontend does not expose as screens / that were not reached from the UI in this verification, the following were executed/read with cast in this campaign:

- ✅ `StabilityPool.provideToSP` (**executed via cast, not through the frontend**. This was an alternative because the app Earn screen cannot be opened due to FE-1. status 1, SP 2,000,000->2,013,534 JPYdf, tx `0x19deab3d`, block 460) <- **This is cast supplementation, not E2E verification**
- ✅ `PriceFeedProxy.lastGoodPrice` (dETH=¥600,000.6 read)
- * `PriceFeedProxy.proposeSource` / `cancelSourceProposal` were **executed as actual Tx via the console UI, not cast** (§2-#7/#8, within E2E scope)
- (Not executed via frontend / remaining tasks) `confirmSource` (after 24h timelock elapsed) / `writeoffStrategyPrincipal` / `backstopDeposit` / `releaseBackstopToBuffer` / `transferYieldToTreasury` (no-op with surplus 0) / `emergencyWithdraw` / `sweepRewardToken` / liquidation (`liquidate`) / `redeemCollateral` (not possible via frontend due to subgraph dependency = FE-6)

---

## 6. Verification Limitations (Explicitly Not Executed)

- **This verification was performed on a local actual-machine environment at develop @ `7741513`**, which is a different SHA from the PR#64 verification target `d4c69d2` (the line that does not include PR#58 frontend local-surfaces; `d4c69d2` is not an ancestor of PR#58). Note that the PR#58 frontend exists on the tree at `PR#58@827e803` (an intermediate SHA of the PR#58 branch with the frontend implemented), which is what the V1 ledger FRNT verification refers to.
- **(Initial limitation, resolved in §8)** SP deposits (Earn) could not initially be completed in the frontend due to the FE-1 bug, and redeem could not be completed due to the subgraph dependency. -> **After fixing FE-1 and starting the subgraph in §8, both succeeded as actual Tx through the frontend**.
- Frontend writes are **the 8 in §2** (openTrove / Vault deposit / borrow increase / collateral reduction / close / allocate / proposeSource / cancelSourceProposal) **+ the 2 in §8** (SP deposit / redeem) = **10 actual Tx proven in total**.
- **Not executed via frontend (remaining tasks)**: `confirmSource` (after 24h timelock elapsed) / console proposal builder, pause, writeoff, backstop / urgent redemption / liquidation (because prerequisite conditions such as branch shutdown were not met). These can be executed through the same path in the console (direct RPC, no subgraph required), or once the prerequisite conditions are met.
- **Error paths, revert paths, and invariants** were not verified through the frontend (these are in the scope of `forge` tests = handled by the V1 ledger).
- This file proves that contract functions “work through the frontend”; it **does not claim per-ID satisfaction for all 965 requirement IDs**.

---

## 7. Environment (Evidence)

- Clone: `/private/tmp/jpydf-v2-fe-verify` (develop @ `7741513`)
- chain: anvil 31337 / Multicall3 `0xcA11…CA11` injected
- Surfaces: app `:3000` / console `:3001` / ops `:3002`
- Main addresses (branch0 dETH): Vault `0x3Aa5…443c` / dToken `0x9A9f…63AE` / PriceFeedProxy `0xde2B…5E2c` / Strategy `0x9E54…3042` / BoldToken(JPYdf) `0x1f80…c746`

---

## 8. Additional Verification — After FE-1 Fix & Subgraph Startup (Completed SP Deposit and redeem in Frontend)

With user approval, the 2 items that could not be completed in the frontend in §4 (Earn(SP) = FE-1 / redeem = subgraph dependency) were actually resolved and verified through actual Tx via the frontend.

### 8.1 FE-1 Fix (Missing `generateStaticParams` Update for Earn Screen)
- **Cause**: `generateStaticParams` in `borrow/[collateral]/page.tsx` includes dToken branches (`deth`, etc.), but `earn/[pool]/page.tsx` and `earn/[pool]/layout.tsx` remained at the upstream `eth/reth/wsteth/sbold` and did not include dTokens -> `/earn/deth` returned a `missing param` 500.
- **Fix**: Added dToken branches (`deth/dusdc/dusdt/dusds/dxaut/dbtc/dusd/djpy`) to `generateStaticParams` in both files, and relaxed the params type in `layout.tsx` to `string` (frontend modification on the verification clone. Applying to develop is a separate PR).
- **Result**: `/earn/deth` opened, and **SP deposit (`provideToSP`) succeeded as an actual Tx through the frontend** (SUCCESS after Retry). Cross-checked with cast: `getCompoundedBoldDeposit` increased from 2,013,534 to **2,014,534**, confirming the SP deposit actual Tx was established.
  - Note: `getCompoundedBoldDeposit` is the **compounded balance of principal + SP yield**, not the pure deposited principal amount itself. The frontend input amount and the increase in compounded balance do not match exactly (the difference is SP yield on the existing 2M deposit crystallized at `provideToSP` time), so this evidence only claims that “the SP balance increased = the actual Tx was established” (it does not assert the pure deposit amount).

### 8.2 Subgraph Startup (Prerequisite for redeem)
- **Procedure**: With node 20.18.1 (graph-cli requirement), ran `start-graph --reset` (discarded old postgres) -> started graph-node/postgres/ipfs -> `pnpm codegen` -> `deploy-subgraph local --version v1 --create` -> **`liquity2/liquity2` fully synced to anvil block 469 (hasIndexingErrors: false)**.
- **frontend env fix**: `NEXT_PUBLIC_SUBGRAPH_URL` in `.env.local` was `…/liquity2/version/latest`, causing a **path mismatch** -> fixed to `…/liquity2/liquity2` and restarted app dev.
- **Result**: **redeem (1000 JPYdf) succeeded as an actual Tx through the frontend** (“Redeem JPYdf” -> SUCCESS. The previous “Error while fetching data from the subgraph” was resolved).

### 8.3 Updated Status

- **FE-1 (§4)**: Fixed (must be reflected to develop in a separate PR).
- **FE-6 (redeem subgraph dependency)**: Resolved by starting the subgraph. The fact remains that the subgraph must be running to complete redeem locally (runbook recommended).
- **Actual frontend write Txs: 10 total** (8 in §2 = openTrove / Vault deposit / borrow increase / collateral decrease / close / allocate / proposeSource / cancelSourceProposal + 2 in §8 = **SP deposit / redeem**). **`provideToSP`, which had been completed via cast, was promoted in §8.1 to an actual frontend Tx** (the cast in §5 was the initial provisional step; §8 is correct for the E2E).
- **Still not executed** (frontend): `confirmSource` (after the 24h timelock has elapsed) / urgent redemption and liquidation (preconditions such as branch shutdown not satisfied) / console proposal builder, pause, writeoff, and backstop (same path in console). Internal functions with no UI, error cases, and invariants are in the forge scope (V1 ledger).
