# Inert Branch Activation Runbook

## 0. Scope

This defines the procedure for opening Branches 2–7 (`dETH` / `dUSD-A` / `dBTC` / `dUSD-B` / `dJPY` / `dJGB`), which were reserved on Day-1 with no Underlying binding and `mintCap = 0`, as active collateral. For every slot, the exact Underlying, immutable-risk conformity evidence, Owner approval, Oracle, Strategy / Zapper, and audit scope are finalized as one activation package.

Out of scope: the Day-1 active Branch 0 `dwstETH` / Branch 1 `dUSDC` (product scope is [Mainnet Launch Product Decision Record](../../launch/decisions/Mainnet-Launch-Product-Decision-Record.md) §1; the risk gate is the Japanese [Day-1 Parameter Decision](../../../../jp/protocol/launch/decisions/Day1-Parameter-Decision.md) §4; post-launch cap changes are handled by the [Active Branch Cap Ramp Runbook](Active-Branch-Cap-Ramp-Runbook.md)).

This runbook turns the Japanese [Collateral Parameter Policy](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) §2.4, `Oracle.md` ORCL-FR-009, `dToken.md` DTKN-FR-002 / DTKN-FR-010, and `CollateralVault.md` VAULT-FR-011 into an operational procedure.

Key premises:

- You must not open an inert branch with `setCap` alone.
- Branch immutable parameters (MCR / CCR / SCR / BCR / liquidation penalty, etc.) are immutable values fixed on Day-1. If the **go/no-go verification** result against stress data for the confirmed Underlying does not fit within the [Parameters.md](../../../Parameters.md) values, do not activate; per the Japanese [Collateral Parameter Policy](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) §2.4, **consider a redeploy = migration** (a permanent inert hold is also possible; a branch-level swap is not possible).
- The Underlying binding of the dToken / Vault is one-shot. If the wrong token is set, it cannot be corrected within the same branch.
- Keep `mintCap = 0` until activation is complete, and make the final `setCap(N)` the only deposit-release operation.

## 1. Activation Candidate Gates

If any of the following cannot be met, stop the activation.

| Gate | Required evidence |
| --- | --- |
| Underlying decision | token address, symbol, decimals, implementation/proxy, admin / pause / blacklist authority, custody / redemption terms |
| Risk parameter go/no-go verification | Verified and approved that the stress for the confirmed Underlying fits within the Day-1 immutable values (LLTV / MCR / CCR / SCR / BCR / liquidation penalties) (verification, not re-derivation; if it does not fit, activation is not allowed) |
| Oracle design | Which of Standard / Peg-monitored / Composite rate / Composite peg / fixed price to use, feed address, staleness, weekend / market-hours handling |
| Liquidity / liquidation route | That SP / JIT / liquidator can process the collateral, and that the liquidation reward holds up in real operation |
| dToken / Vault readiness | `dToken.totalSupply() == 0`, `dToken.cap() == 0`, `dToken.underlying() == 0`, `vault.underlying() == 0` |
| PriceFeedProxy readiness | Current source is `PriceFeedPlaceholder`, owner / pending owner is the expected holder |
| Frontend / ops readiness | The user app shows a non-operable display before activation; admin/ops can read branch state / cap / source / Underlying |
| Governance readiness | The Timelock proposal bundle, Guardian pause path, rollback criteria, and execution window are approved |

Branch-specific minimum review:

| Branch | Extra review |
| --- | --- |
| 2 `dETH` | ETH-type candidates (WETH / LSTs, etc.). For an LST, verify secondary-market depeg, slashing / negative rebase, withdrawal queue / exit, and the canonical rate provider. The envelope equals Branch 0 (conservative side including LST-specific depeg risk, [Parameters.md](../../../Parameters.md) §2-A) |
| 3 `dUSD-A` / 5 `dUSD-B` | Do not pre-fix the category (permissionless / yield-bearing / RWA, etc.); per candidate, verify issuer / protocol dependency, transfer restriction, freeze / blacklist, redemption, canonical rate / NAV, and secondary liquidity |
| 4 `dBTC` | BTC wrapper peg / custody / withdrawal delay / staking slash or finality risk. Presence of a WBTC/BTC-type peg monitor |
| 6 `dJPY` | Candidates are JPY-denominated assets (regulated JPY assets, etc.); verify settlement delay, freeze / allowlist, issuer / custodian credit, reserve attestation, legal transferability, exit, and SP / redemption / settlement capacity |
| 7 `dJGB` | Candidates are tokenized JGBs; verify the 3-month duration cap, NAV / oracle, interest-rate stress, redemption calendar, and transfer restrictions, in addition to settlement delay, issuer / custodian credit, and SP / redemption / settlement capacity |

## 2. Preflight Evidence

Attach at least the following to the activation PR / governance proposal.

1. A go/no-go verification memo per the Japanese [Collateral Parameter Policy](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) §2.4 (confirmation that the confirmed asset's stress fits within the Day-1 immutable values in [Parameters.md](../../../Parameters.md); if it does not fit, activation is not allowed).
2. RPC evidence of the confirmed token's `decimals()` / `symbol()` / `name()` / implementation / proxy admin.
3. The feed's `latestRoundData()`, decimals, heartbeat / staleness basis, and `secondsToStale`.
4. `dToken.totalSupply == 0`, `cap == 0`, `underlying == 0`.
5. `vault.underlying == 0`, `bufferBalance == 0`, `backstopBalance == 0`, strategy count / config.
6. The `PriceFeedProxy` current source is the placeholder, and the owner is the expected holder.
7. A log of executing the activation calls in order against the same fork state in a fork dry-run.
8. A screenshot or component/e2e evidence showing that the user app / admin / ops branch display changes as intended before and after activation.

## 3. Execution Order

For each branch, do not break the following order.

1. Keep cap closed:
   - Confirm `dToken.cap() == 0`.
   - If not zero, queue `dToken.setCap(0)` first and wait until confirmed.
2. Allowlist intended Underlying:
   - `dToken.setAllowedUnderlying(underlying, true)`.
   - Do not allowlist multiple alternatives in the same proposal unless one will be removed before binding.
3. Bind dToken first:
   - `dToken.setTokenInfo(name, symbol, underlying)`.
   - Requires `totalSupply() == 0` and `allowedUnderlying[underlying] == true`.
4. Bind Vault second:
   - `vault.setUnderlying(underlying)`.
   - This must observe `dToken.underlying() == underlying`; otherwise it reverts with `UnderlyingMismatch`.
5. Deploy and smoke-test real price feed:
   - Verify feed code, constructor args, source addresses, staleness, decimals, and sample price.
6. Queue source replacement:
   - `priceFeedProxy.proposeSource(realFeed)`.
   - Wait the required timelock.
7. Confirm source replacement:
   - Placeholder `(1e18, false)` to real feed normally exceeds the price-difference guard, so use the emergency confirmation path only with pre-approved evidence and private submission policy.
   - Keep cap at 0 during and after this step until post-confirm smoke tests pass.
8. Configure Vault operations:
   - Set buffer target/floor, withdraw delay, allocator cooldown/max move, strategy whitelist/config if applicable.
   - If no Strategy is approved, leave strategy count/config empty and `allocateMaxMove = 0`.
9. Frontend / ops release:
   - Update generated deployment/app env and branch metadata.
   - User app can show the branch only after Underlying, source, and cap release are all confirmed.
   - When multiple branches of the same asset class become active, display them side by side without recommending or pre-selecting one.
10. Open cap:
    - Convert the approved USD nominal exposure to dToken 18-dec token units using the final launch price and decimals.
    - Execute `dToken.setCap(N)`.
    - Record tx hash, cap units, nominal reference price, and reviewer sign-off.

## 4. Post-Activation Checks

After `setCap(N)`, verify:

| Check | Expected |
| --- | --- |
| `dToken.underlying()` | exact intended token |
| `vault.underlying()` | same token |
| `dToken.cap()` | approved nonzero token-unit cap |
| `PriceFeedProxy.fetchPrice()` | non-placeholder price and `oracleFailure == false` |
| `backingRatio()` | `1e18` before deposits |
| user app branch state | active and uses real token copy, not TBD / placeholder |
| admin/ops branch state | source, cap, roles, strategy config visible |
| liquidation tooling | branch included only after price and Trove reads are healthy |

## 5. Failure Handling

| Failure point | Handling |
| --- | --- |
| Confirmed-asset stress does not fit Day-1 immutable values | Stop activation. Params cannot be edited in place; the only path is a full system redeploy (a migration) or keeping the branch inert (no branch-level swap; see the Japanese Collateral Parameter Policy §2.4). Do not compensate with dToken cap only |
| Wrong Underlying allowlisted before binding | Remove allowlist entry if possible, re-run preflight, and restart proposal |
| Wrong `setTokenInfo` executed | Stop. The branch is not safely recoverable in-place because Underlying binding is one-shot |
| `vault.setUnderlying` reverts | Do not retry blindly. Confirm dToken-first state and token address equality |
| Price feed smoke test fails | Keep cap at 0, do not confirm source or open deposits |
| Source confirmed but post-confirm checks fail | Keep cap at 0, pause user/app activation, queue source remediation |
| Cap opened with wrong units | Immediately Guardian-pause deposits where available, queue corrected cap / incident response, and assess whether any deposits occurred |

## 6. Non-Goals

- This runbook does not add new core branches or change immutable Liquity branch parameters.
- This runbook does not approve a specific Branch 2–7 Underlying, Strategy, PriceFeed, cap, or SP seed.
- This runbook does not define new frontend copy beyond the rule that activation must not expose TBD / placeholder branches as usable collateral.
