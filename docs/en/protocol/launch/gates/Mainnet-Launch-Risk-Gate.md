# Mainnet Launch Risk Gate

> Support translation. The Japanese source document
> [`documents/jp/protocol/launch/gates/Mainnet-Launch-Risk-Gate.md`](../../../../jp/protocol/launch/gates/Mainnet-Launch-Risk-Gate.md)
> is authoritative if this file conflicts with it.

| Field | Value |
| --- | --- |
| Domain | Protocol |
| Lifecycle | Launch |
| Artifact Type | Runbook / Gate |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight |
| Visibility | Repository |
| Status | Active |
| Normative Source | This document for the `SYS-RISK-*` launch gates. Product and component Specs define Protocol requirements; Architecture Decision Records explain the design rationale |

## 1. Purpose

Before the Ethereum mainnet Day-1 launch, verify that each cross-system structural risk is closed by controls in the applicable Spec or Policy and by execution Evidence. The gate checks the extension layers, deployment gates, and Operations artifacts without adding ad hoc try/catch handling or backing accounting to Core.

This document does not define Protocol behavior, parameter values, or a Contributor balance-sheet commitment. The Day-1 Manifest is authoritative for concrete values, and Evidence is authoritative for execution results.

## 2. Gate

<a id="sys-risk-001"></a>
### `SYS-RISK-001` Shared JPY/USD dependency

- **Risk**: Because pricing uses `collateral/USD ÷ (JPY/USD)` where JPY/USD means USD per JPY, a stale, deprecated, or incorrect JPY/USD feed affects every branch.
- **Protocol control**: On a JPY/USD failure, every active feed (the `DFPriceFeedBase` family and the composite feeds) soft-freezes on the shared `JpyUsdRateProvider` `lastGoodJpyRate`; after the approved staleness threshold has elapsed, it falls back to a recoverable oracle-failure pause plus `lastGoodPrice`. In addition, when the stored shared-JPY/USD round reaches `PRM-ORACLE-008` (108,000 seconds / 30h), or when source-bound provider provenance is missing or invalid, `PriceFeedProxy` returns `failure=true` for normal redemption alone without a cache write, `_handleFailedFetch`, `SourceFailureHandled`, or a BO pause. `fetchPrice` and urgent redemption are unchanged, and the first normal-redemption call that observes a fresh round reopens the path automatically. Irreversible terminal shutdown remains a separate transition that occurs only when a price with `failure=false` produces `TCR < SCR`, including a frozen rate still inside the soft-freeze window or a fresh rate after recovery. The `failure=true` result at exact freeze expiry is not itself a terminal trigger.
- **Pass condition**: Confirm the `PRM-ORACLE-001` / `PRM-ORACLE-008` inputs, boundary tests immediately before and exactly at 30h, invalid-provenance and fresh-round recovery tests, `ORCL-SEC-005` monitoring, the source-replacement runbook, and disabled `PriceFeedProxy.renounceOwnership()`. Because the 30h gate emits no event, a hash-rechecked safe-head synthetic must compare Proxy/source normal redemption, normal price, urgent price, provider age, and BO pause at one block and route the result through `ALRT-ORCL-016`.
- **Current evidence (2026-08-30)**: `PriceFeedProxy*.t.sol` passed 140 tests, `PriceFeedPlaceholder.t.sol` 11, `RedemptionHelper.t.sol` 8, and `RedemptionHelperOracleFailure.t.sol` 2, all with zero failures and zero skips. Ops `snapshot.test.ts` and `alerts.test.ts` exercised exact 30h, 30h−1s, invalid provenance, one-safe-head-block reads, `ALRT-ORCL-016` firing, and fresh-state non-firing; Ops typecheck also passed ([`ORCL-JPY-AGE-20260830`](../../../engineering/verification-ledgers/Requirements-Verification-Ledger.md)). The labeled test incident, escalation-target delivery, human receipt, and same-key resolution are **not run**. This gate remains No-Go until that evidence exists.

<a id="sys-risk-002"></a>
### `SYS-RISK-002` dToken backing impairment

- **Risk**: If Strategy loss, slashing, or a hack causes `A < L_effective`, Core may treat nominal dToken as fully backed collateral.
- **Protocol control**: Do not add backing accounting to Core. The Vault calculates `backingRatio()`, and the Oracle applies it downward to the price (`ORCL-FR-014` / `VAULT-FR-016`). In addition, `VAULT-SEC-010` permits `deposit` / `redeem` / `redeemWithPermit` / unsettled `claim` only when the pre-state proves cache-free confirmed assets `A_confirmed >= L_effective`. Repair/recovery rails stay open, and only the automatic guard clears after confirmed assets recover. A pause flag explicitly set by Guardian still requires the existing GOV unpause. [`ADR-006`](../../product/architecture/Architecture-Decision-Records.md#adr-006) explains the design.
- **Pass condition**: Integration tests and external monitoring show that (1) every active feed refers to the correct Vault and loss / writeoff / backstop deposit / release move price down and back up; (2) all four user paths stop before token / permit / queue / request-state changes while underbacked; (3) fresh valuation cache cannot bypass the stop; (4) backstop and Strategy recovery remain executable and the automatic guard clears once `A_confirmed` recovers, while an explicit pause remains in force; and (5) ordinary redemption does not consume the reserve first. Treat external losses not reflected by live Strategy valuation as residual risk covered by caps, monitoring, and incident rails. Mainnet remains No-Go until the Vault upgrade and this evidence are complete.
- **Additional pass condition for unobserved loss**: Calculate separately for each Vault / Underlying `u` in that Underlying's base units. For every Strategy define `E_i,u = max(configured cap_i, current principal_i)` and a primary-evidence-backed, risk-owner-approved `f_i_bps in [0, 10000]`; round every term upward and calculate `U_s,u = sum(ceil(E_i,u * f_i_bps / 10000))` and `U_max,u = max_s(U_s,u)`. If no defensible loss fraction exists, use `f_i_bps = 10000`. Include a same-`u` simultaneous-loss scenario for every active Strategy; excluding one requires primary evidence that rules out co-occurrence and explicit risk-owner approval. Represent correlated scenarios spanning multiple Underlyings as a vector whose per-Underlying inequalities must all hold; never sum raw amounts across tokens or decimal domains.
- **Available remediation capacity**: In plain terms, `U_max,u` is the largest unobserved loss that could surface at once for that Underlying, while `C_available,u` is unused and uncommitted funding that can be delivered immediately (within the approved SLO) in the same Underlying without consuming assets that already back user liabilities. If `U_max,u` is 100,000 USDC, at least 100,000 USDC must be available without double-counting another use. Do not count JPY-converted value, another token, reserve already covering an existing shortfall, or funding whose delivery is uncertain. At the same pinned block, reconstruct cache-free `A_confirmed,u` and `L_effective,u` with the Solidity guard's semantics, treating an unreadable Strategy as zero. Existing reserve contributes only unused capital `C_protected_free,u = min(backstopBalance_u, max(A_confirmed,u - L_effective,u, 0))`; do not count reserve already absorbing rounding loss or an existing shortfall again. Add only real same-Underlying assets `C_external,u` that can reach `backstopDeposit` within the approved time, without double-counting SP seed, LP funds, or another commitment, and set `C_available,u = C_protected_free,u + C_external,u`. If any affected `u` fails `C_available,u >= U_max,u`, risk acceptance alone cannot pass the gate: reduce Strategy caps, keep the affected Strategy inactive, or supply an audited loss-allocation mechanism. `bufferTargetBps` is not a hard upper bound on liquid buffer and must not be used as the bound on pre-pause immediate-redemption exposure.
- **K-01 evidence**: The risk owner explicitly accepts loss reallocation through nominal redeem / queue reservation before pause inclusion, `minBackingRatioAfter` grief caused by live-buffer outflow, and the above funding requirement for keeping queue claims nominal. One launch-rehearsal timeline must bind an external-monitor test incident and delivery to a real recipient, the approved offline signing path for the Guardian threshold specified by the [Safe Threshold Policy](./Mainnet-Role-Assignment-Safe-Threshold-Policy.md), no submission of the unexecuted transaction or signatures to the Safe Transaction Service, unresolved-lineage reconciliation at the current Safe nonce across every approved submission path, self-hosted-node / local-fork restriction for payload-bearing calls, private submission only to explicitly approved builders, immediate re-signing if an existing same-nonce transaction lands first, public fallback after an approved block timeout, immediate receipt-block readback, repeat readback at a canonical `safe` block, the queue delta across the pause block, and persistence of the standalone pause after a later `BackingRatioBelowMinimum` revert. Mainnet is No-Go without measured detection-to-inclusion time, the fallback timeout, an owner, and evidence references. Any post-launch increase of mintCap or a Strategy cap, addition of a Strategy/venue, `current principal_i,u` exceeding the approved `E_i,u`, reduction/double-commitment of `C_available,u`, or consumption of `C_protected_free,u` by rounding or an observed loss requires recalculation and risk-owner re-approval of `U_max,u` / `C_available,u` before execution or the next allocation; keep the affected Strategy inactive or allocation paused while the condition is unmet.

<a id="sys-risk-003"></a>
### `SYS-RISK-003` Additional SP rewards from collateral yield

- **Risk**: No route is connected that converts branch-specific underlying yield into JPYdf and delivers it to base-parity SP depositors.
- **Protocol control**: Strategy yield accumulates in the Protocol retention Safe specified by the Manifest and is not presented as an additional SP reward. The current destination and reconciliation procedure live in the [`Treasury-Safe-Retention-Runbook`](../../operations/runbooks/Treasury-Safe-Retention-Runbook.md).
- **Pass condition**: Do not display an unconnected additional distribution as a user-facing reward. Treat only Core-native 75% borrowing interest and liquidation gains as SP rewards.

<a id="sys-risk-004"></a>
### `SYS-RISK-004` Asynchronous Strategy principal recovery

- **Risk**: Unstake queues and similar mechanisms may prevent immediate recovery and conflict with the Vault's synchronous accounting and separation of yield from principal.
- **Activation boundary**: Do not activate a Strategy with asynchronous recovery until it satisfies the conditions below. The applicable Launch Decision, Manifest, or activation record owns release-specific adoption and weight / cap values.
- **Pass condition**: Before assigning a nonzero allocation, approve asynchronous recovery, pending principal, yield/principal separation, borrower disclosure, redemption/refill behavior, loss/writeoff handling, keeper/incident handling, and the revised withdraw delay and buffer.

<a id="sys-risk-005"></a>
### `SYS-RISK-005` Risk parameters immutable after one-shot finalization

- **Risk**: Active-branch risk parameters are finalized at deployment, while a reserved branch may finalize them only once before activation. Finalizing the wrong Underlying, values, or execution order cannot be corrected or cancelled afterward.
- **Protocol control**: Only while a reserved branch has `riskParamsFinalized == false` and zero cap, supply, Troves, debt, collateral, and Stability Pool deposits may the common Timelock finalize all six values together. Trove opening and SP deposits are rejected while the values are unfinalized, and there is no post-finalization setter or unfreeze path.
- **Pass condition**: Verify `PRM-INV-*` in the Japanese [Parameter Catalog §4](../../../../jp/protocol/product/parameters/Parameter-Catalog.md#4-parameter-invariants) through the forge and deployment scripts. Active branches follow the [Day-1 Parameter Decision](../../../../jp/protocol/launch/decisions/Day1-Parameter-Decision.md); reserved branches follow the Japanese [Collateral Parameter Policy](../../../../jp/protocol/product/policies/Collateral-Parameter-Policy.md) and [Inert Branch Activation Gate](../../../../jp/protocol/operations/activation-gates/Inert-Branch-Activation-Gate.md). Confirm the exact Underlying, Timelock caller, unfinalized / empty / non-shutdown state, synchronization among Registry / BorrowerOperations / TroveManager, and an atomic execution that opens the cap last. Do not duplicate branch values or state here.

<a id="sys-risk-006"></a>
### `SYS-RISK-006` Redemption dependency on non-reverting feeds

- **Risk**: Redemption scans every branch, so one reverting feed can stop all redemption.
- **Protocol control**: Do not add try/catch to Core. The `PriceFeedProxy` constructor and `confirmSource` validate all three price paths plus the source-bound `jpyUsdRateProvider()` / `lastGoodJpyUpdatedAt()` provenance, failing closed on a missing or malformed getter and a zero or future timestamp. At runtime a real source revert, invalid price, or `failure=true` still enters the recoverable oracle-failure pause plus path-specific fallback. Reaching `PRM-ORACLE-008` or losing runtime provenance instead produces a zero fill only in the affected normal-redemption branch and does not spread to other branches, borrowing, liquidation, or urgent redemption. Emergency confirmation avoids the broken old source and validates only the new source. `RedemptionHelper` preserves the redemption failure flag in simulation and truncation and returns unused JPYdf to the caller after execution.
- **Pass condition**: Deployment-tail configuration checks and integration tests confirm that every active and inert source is non-reverting, ABI-valid, nonzero and nonmax, with `failure=false` and valid provenance. Tests cover missing/malformed/aged provenance, source switch/emergency/resume, real source failure, gas guards, repeated placeholder scans, zero spend through direct Registry and Helper calls, full Helper refund, multi-branch denominator preservation, and failure on the truncation re-read.
- **Current evidence (2026-08-30)**: The Proxy, Placeholder, and Helper suites above passed 161 tests in total with zero failures and zero skips, and the safe-head synthetic and alert-classification code tests passed. Mainnet deployment-tail readback for every source and human delivery/resolution evidence for `ALRT-ORCL-016` are **not run**, so this gate remains PARTIAL / No-Go.

<a id="sys-risk-007"></a>
### `SYS-RISK-007` Market depeg of a centralized wrapper

- **Risk**: An underlying-only price cannot reflect wrapper-specific market depeg, redemption halt, or transfer restriction.
- **Protocol control**: A wrapper candidate must incorporate a market / peg leg into the on-chain PriceFeed. Off-chain monitoring is not a substitute.
- **Pass condition**: Approve the wrapper's depeg, issuer/custodian, redemption, freeze/blacklist, and liquidity risks together ([Oracle](../../product/spec/Oracle.md) `ORCL-FR-013` / `ORCL-SEC-006`).

<a id="sys-risk-008"></a>
### `SYS-RISK-008` mintCap is not a branch debt ceiling

- **Risk**: dToken `mintCap`, `pauseDeposit`, and cap reduction stop new dToken supply, but they do not stop JPYdf debt increases through Core `openTrove`, `withdrawJpydf`, or `adjustTrove` against existing dToken collateral.
- **Protocol control**: Do not add a new hard branch debt ceiling to Liquity v2 Core. Manage exposure through dToken `mintCap`, MCR / CCR / SCR, SP coverage, frontend and ops borrowable-branch gates, approved cap ramps, and redemption / liquidation monitoring.
- **Pass condition**: Docs, UI, and ops do not describe `mintCap` as a "JPYdf issuance cap" or "branch debt ceiling." State and plan schemas record `cap - totalSupply` as `dTokenCapHeadroom` (nominal dToken supply-cap headroom), never as `borrowCapacity`. Because actual collateral intake also requires deposits to be unpaused, record `dTokenDepositPaused` separately. Do not treat `plannedDebtJpydf` as an on-chain cap or executable borrowing capacity. Confirm that debt can still increase against existing dToken collateral after a cap reduction.

<a id="sys-risk-009"></a>
### `SYS-RISK-009` Upward JPYdf deviation and asymmetric supply response

- **Risk**: Redemption creates downward pressure toward nominal ¥1 but does not guarantee a market-price floor. No symmetric mechanism corrects an upward deviation (JPYdf > ¥1), so the supply response depends on new borrowing against existing dToken collateral or current cap headroom. The premium may persist if demand exceeds available collateral, willingness to borrow, and the acceptable APR range.
- **Protocol boundary**: The fast response is limited to an eligible borrower using the ordinary Core borrowing path within existing collateral and cap headroom, then supplying JPYdf to the market. The Protocol does not require a particular Contributor to borrow more, commit its own capital, or sell into the market. dToken supply headroom beyond the current cap requires a Protocol Governance cap ramp under the [Active Branch Cap Ramp Runbook](../../operations/runbooks/Active-Branch-Cap-Ramp-Runbook.md).
- **Pass condition**: Calculate executable supply capacity from live state, separately showing additional borrowing room against existing collateral, new collateral accepted within `cap - totalSupply` while deposits are unpaused, and debt available from that collateral after upfront fees. Until borrower-specific, fee-inclusive `executableBorrowCapacity` is collected, mark it explicitly as `not-collected` and fail closed to review or pause for borrow / self-mint approval during an upward deviation. Detection conditions, approval, execution procedure, and Evidence live in the applicable Operations artifacts. If DeltaForesight elects to use its own balance sheet, its [B/S Policy](../../../contributors/deltaforesight/policies/Balance-Sheet-Liquidity-Allocation-Policy.md) and Commitment are authoritative.
- **Residual risk**: JPYdf has no PSM or automatic supply-elasticity mechanism. A cap expansion cannot bypass the Timelock delay, so a short-term upward deviation is accepted. Confirm that adopting another arbitrage route does not itself create new supply capacity.

<a id="sys-risk-010"></a>
### `SYS-RISK-010` Stale-high dwstETH redemption reference

- **Risk**: The dwstETH redemption reference takes the `max` of direct and derived values. If the derived leg's ETH/USD (`PRM-ORACLE-002`) or stETH/ETH (`PRM-ORACLE-007`) round is still policy-fresh but above the current market, the stale-high derived value can be selected and reduce the collateral delivered to the redeemer.
- **Protocol control**: Evaluate the redemption-only ETH/USD feed under `PRM-ORACLE-002` (7,200 seconds) and stETH/ETH under `PRM-ORACLE-007` (90,000 seconds). If either feed is stale or invalid, both normal and urgent paths fail closed with `failure=true`; there is no direct-only fail-open fallback. Operations sends an external pre-expiry warning when stETH/ETH age is at least `88,200` seconds, a P0 `ALRT-ORCL-012` at or above `90,000` seconds, and resolves the incident after a fresh round.
- **Pass condition**: At the same pinned fork block as the actual candidate, verify both feed addresses, runtime codehashes, rounds, `updatedAt`, thresholds, and Proxy / source bindings. The Product owner and Protocol Risk owner explicitly approve both the stale-high window and the redemption outage caused by fail-closed behavior. Deliver labeled warning and P0 test incidents to the approved escalation target, then record receipt by the intended human recipient and resolution after a fresh round.
- **Current evidence (2026-08-31)**: The explicit approvals and end-to-end alert-delivery, human-receipt, and resolution evidence above do not exist. This gate is **No-Go** until they are complete.

## 3. Completion Conditions

1. Each `SYS-RISK-001..010` pass condition refers to executed tests, a Manifest, or Evidence.
2. Every unmet item is explicitly No-Go or isolated in an approved non-public, non-activation scope.
3. Passing this gate does not authorize Contributor funding, use of Foundation assets, or an unapproved parameter change.
