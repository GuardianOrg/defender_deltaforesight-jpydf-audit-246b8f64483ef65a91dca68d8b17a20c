# Solidity Remediation and Residual Risk — Business Summary (2026-08-29)

> Domain: Contributor
>
> Lifecycle: Historical
>
> Artifact Type: Evidence
>
> Maintainer: DeltaForesight
>
> Visibility: Repository
>
> Status: Historical
>
> Snapshot: 2026-08-29
>
> Normative Source: Current specifications, Parameter Manifest, Launch Gates, and Activation Gates referenced in this document
>
> Translation Status: English support translation of the original Japanese historical snapshot. This document is non-normative; the current, self-contained English requirements for the additional audit are in [`GUARDIAN_ADDITIONAL_AUDIT_HANDOFF.md`](../../../audit/GUARDIAN_ADDITIONAL_AUDIT_HANDOFF.md).

> Audit repository intake: copied from source PR head
> `e0587edc4eb9a9cf78a06196ecf3c1ad469b738a`, source blob
> `dd489f511b9dcd8a4c9b8dc4a1ee48b531116e74`. The snapshot stops at source
> merge `c9206af5` and does not include later runtime-decimals, oracle-recovery,
> normal-redemption 30-hour provenance, or final production-cleanup work. Four
> inaccessible source-repository links were removed or redirected locally; no
> security claim depends on them.

This document is a dated snapshot for Business, Product, Protocol Governance, and Operations. It summarizes issues identified during the recent Solidity remediation work. It is not the source of truth for current specifications, risk acceptance, Go / No-Go decisions, or execution procedures. Any decision or procedure change must be made in the linked specifications, gates, or governance records.

### Snapshot identity

| Item | Value |
| --- | --- |
| frozen baseline contracts tree | `ad2445667fe5a72f287c210b34a0e464cf44b4e9` |
| materialized audit candidate (`source-snapshot/contracts/`) tree | `b3615d075f41028367f2f44557e48e08e4903171` |
| frozen-baseline differential | 113 files / +10,558 / -650. The primary economic and security review scope contains 24 source / interface paths |
| source merge provenance | `c9206af57890cc57c5c901f969a04986dff64c5a` (for historical identification; not a source of truth) |
| Day-1 manifest SHA-256 | `b50e9e48bbd9e0776106744ddd74527178a3057cfde59cd2eddbc3dfc71823a4` |

The verification results and remaining work below apply to this candidate identity. They do not automatically carry over to a different tree.

## 1. Conclusion

**The code differential is ready for review, but production transition remains conditional and mainnet execution is not yet approved.**

| Area | Conclusion as of 2026-08-29 |
| --- | --- |
| Immediate direct loss of funds caused by the recent diff | None identified in the current differential review. The conditional economic-transfer risk from `F-1` remains, and this is not a guarantee that no vulnerability exists |
| Solidity and regression tests | Multiple bugs and configuration-failure risks have been remediated |
| Unresolved risks and design boundaries | Two Medium and three Low risks remain undecided in §4, together with three Info constraints. A separate pause-time permissionless-shutdown observation reported as High is a non-defect: it retains Liquity's inherited safety mechanism alongside the mitigation in §3. It still requires a Governance design disposition and public explanation. Two High production-governance evidence items remain in §5 |
| Production execution | Real-chain evidence for the Timelock, backstop, roles, caps, receipts, and alert delivery is incomplete |
| Recommendation | **CONDITIONAL**. Do not proceed with protocol deployment, handover, allocation, or public activation without approval for each phase. Treat deployment of the fresh production Timelock as a separate approval ceremony |

“Implemented and verified” means that the root cause was addressed in Solidity or a deployment script and regression evidence was obtained from tests. It does not mean that the change has been deployed to mainnet or accepted by the external auditor.

## 2. Four statuses that the business side must distinguish

| Status | Meaning |
| --- | --- |
| **Implemented and verified** | The root cause was addressed in Solidity or a deployment script and regression-tested. A test alone does not count as remediation of the cause |
| **Execution evidence pending** | A procedure or checker exists, but the production transaction, receipt, and block-pinned readback do not yet exist |
| **Intentionally unchanged** | The issue cannot be changed safely in one direction only; Product / Protocol Risk must make the trade-off decision |
| **Design constraint** | The audit treats it as a non-defect or known trade-off. The constraint remains and still requires monitoring, explanation, and acceptance |

### Glossary

| Term | Meaning in this document |
| --- | --- |
| round | An update unit published by an oracle |
| stale | A value older than its allowed age |
| cache | The last value stored by the contract; this is distinct from a stale oracle round |
| leg | An individual feed that forms part of a composite price |
| redeemer | A party that returns JPYdf and receives collateral from Troves |
| base unit | A token's smallest unit; for USDC, 100,000 base units equal 0.1 USDC |
| branch | A collateral-specific independent market |
| backstop | A protected Vault deposit that absorbs small shortfalls such as external-venue rounding |
| canary | A low-value, limited configuration separate from production, used to prove execution and monitoring first |
| wind-down | A terminal phase that ends new normal activity and resolves existing debt and collateral |
| fail-closed | A policy that rejects processing after a required validation fails instead of continuing with an old value |
| DoS | Denial of service. Here it means giving the Owner power to prevent a legitimate shutdown |
| `TCR` / `SCR` | The collateral ratio of the whole system / the threshold used to decide shutdown |
| headroom | Confirmed assets in excess of the recorded liability |
| receipt-pinned | Evidence tied to a transaction receipt, its block hash, and readback at that block |
| Trove / zombie | A borrowing position / a state below minimum debt after redemption that is handled differently from a normal position |
| recoverable oracle pause / irreversible shutdown | The former can return to normal after a healthy price or source replacement. The latter is a terminal transition into branch wind-down and cannot be reversed |
| normal / redemption / urgent price | Three price consumers: normal covers borrowing, liquidation, and shutdown evaluation; redemption covers normal redemption; urgent covers redemption after irreversible shutdown |

## 3. Issues identified and remediated

| Theme | Issue identified | Remediation implemented | What remains |
| --- | --- | --- | --- |
| wstETH redemption price (`ORACLE-COLLATERAL-01` / High incident class) | Treating stETH and ETH as always equal can produce an incorrect redemption price during an stETH depeg | Compare direct `stETH/USD` with derived `ETH/USD × stETH/ETH`; the urgent path does not fall back to cache | Pinned mainnet-fork evidence using the final manifest and live feeds; external-auditor acceptance |
| Oracle pause / economic shutdown boundary (`PAUSE-SHUTDOWN-01`) | Liquity upstream makes oracle failure itself an irreversible shutdown. Simply auto-recovering could reopen normal operations before every price path is validated | Separate oracle failure into a recoverable pause and prevent a `failure=true` price from reaching the `TCR < SCR` check. While paused, block normal redemption and BorrowerOperations until the Owner validates normal, redemption, and urgent paths in one transaction and resumes. After the live normal price recovers, continue to permit liquidation, Liquity's inherited permissionless `TCR < SCR` shutdown, and CCR-constrained closure | Production evidence for human alert receipt and the resume receipt. Permissionless irreversible shutdown on a live `TCR < SCR` price before Owner resume is the inherited safety boundary retained to avoid an Owner veto; it is not an additional remediation target |
| JPY freeze episode (`JPY-EPISODE-01` / Medium) | If a newly observed round became stale again, it could inherit the previous episode's clock and expire immediately | Re-anchor each stale round's freeze start to `round.updatedAt + 72 hours`, then expire it 24 hours later | Fork evidence using actual rounds. A round already older than 96 hours when first observed may expire immediately |
| PriceFeed source configuration (`PROXY-INIT-01` / `F-4`, `PROXY-CYCLE-01`) | A broken urgent getter, self-reference, proxy nesting / cycles, or gas spent calling a broken old source could prevent recovery | Add validation of all three price paths at initialization and source change; reject self-reference, nesting, and repository-observable PriceFeedProxy A↔B cycles; check normal-price continuity; avoid calling the old source during emergency replacement | This does not prove the absence of every cycle through arbitrary wrappers or callbacks. Emergency replacement still bypasses the deviation guard for healthy legs; that risk remains separately |
| Initial Vault allocation (`VAULT-BACKSTOP-01` / `LB-1`) | External venue rounding can reduce confirmed assets by a few base units and make a first allocation with zero surplus revert. Because the failed transaction rolls back in full, this event alone does not cause a direct loss of funds | Enforce confirmed backing, atomic rollback, and a protected-backstop condition only immediately before the first nonzero allocation | The current canary minimum is 1 USDC through `backstopDeposit`, not a plain transfer. For production, measure approved venues, actual share prices, and `allocateMaxMove` on a fork, then approve an asset-specific seed and minimum headroom. Do not reuse 1 USDC as a fixed production value or for another collateral |
| Canary recovery guard | Applying the 1 USDC condition to every phase would also block legitimate recovery after the backstop had decreased | Limit the condition to immediately before the first nonzero allocation | Receipt-pinned post-check after broadcast. This pending evidence is recorded as `CANARY-EVIDENCE-01` in §5 |
| Pilot / Production Timelock | The pilot's five-minute delay or pilot-only 1,000 JPYdf setting could accidentally be reused in production | Keep the pilot at 300 seconds and 1,000 JPYdf; deploy a separate production Timelock with 43,200 seconds (12 hours) from creation and minimum debt of 100,000 JPYdf; add identity verification | Real-chain evidence covering roles, events, pending operations, and runtime from creation through handover. Do not present the pilot on chain 1 as production |
| Minimum debt (`MIN-DEBT-100K-01`) | The final production threshold could diverge across code, manifest, and tests | Fix entire debt, including the upfront fee, at 100,000 JPYdf. Exactly 100,000 succeeds; even 1 wei below 100,000 fails; repayment-crossing and zombie boundaries are fixed | Either add and execute the 100M JPYdf / approximately 1,000 minimum-Trove scenario in total across both active branches in the authoritative gate, or add and execute a Governance-approved alternative gate. This additional gate is recorded in the auditor-facing handoff and awaits external-auditor acceptance. Binding to broadcast receipts also remains |
| Token identity (`CORE-BT-FR-010` / `CORE-BT-FR-011`) | The ERC-20 display identity and permit-signature domain could retain the old token identity | Fix name to `JPYdf Stablecoin` and symbol to `JPYdf`; bind the EIP-712 / EIP-2612 domain to the same name | Evidence that final candidate bytecode, manifest, wallet display, and signature verification agree |
| Day-1 Strategy topology | Canary / test evidence using the Aave + Gauntlet configuration could be reused incorrectly as production evidence | Fix production Day 1 as branch 0 `dwstETH` = no Strategy, and branch 1 `dUSDC` = Aave V3 + Morpho Vault V2 required. An additional `erc4626` slot is permitted only when separately approved | Canary Aave + Gauntlet evidence alone does not prove approval of an optional production `erc4626`. Produce same-safe-block fork evidence using the final manifest |
| Reserved branch (`INERT-RISK-FINALIZATION-01`) | A branch not selected for Day 1 could have its underlying asset and risk values finalized accidentally, or lack a safe path for later finalization | Deploy it unusable with cap 0; the shared Timelock atomically finalizes six values exactly once. Trove opening and Stability Pool deposits are rejected before finalization | Approved values, atomic package, empty-state check, and receipt for each future activation |
| Role / cap handover | Checks covered only active branches, and a cap could be opened before authority was verified | Normalize and read back roles on both active and inert Vaults; keep cap 0 during Prepare; make positive-cap activation the final independent step | Evidence that no unknown role holder or unapproved pending operation exists; cap-last receipt |
| Lido attribution (`LIDO-REFERRAL-01` / Low operational) | Confusing the authority to update a referral with the recipient of funds could make it appear that principal could be redirected | Restrict updates to an immutable manager and set the production manager to the Timelock. The referral is used only as Lido attribution metadata | Verify the manager in the production manifest and receipt |

### Why these remediation methods were chosen and how they relate to Liquity

This document says that an item was “explicitly documented by Liquity” only when the same mechanism or trade-off appears in code, comments, or Known Issues in the frozen [Liquity v2 upstream baseline](https://github.com/liquity/bold/tree/3fcaf602eb36541dd298c73710e067dcad42d8ae). Inheriting a base mechanism does not mean that Liquity reviewed or accepted a JPYdf-specific composition layered on top of it, such as JPY conversion, a recoverable oracle pause, or the third urgent-price path.

| Theme | Origin / relationship to Liquity | Why this remediation was chosen |
| --- | --- | --- |
| wstETH redemption price | **Liquity inheritance plus a JPYdf-specific change.** Liquity explicitly uses the higher market / canonical value for normal WSTETH redemption, describing it as the redeemer's “worst price” against oracle-lag arbitrage and recording the trade-off. The JPY-denominated formula, unconditional direct / derived comparison, and third urgent consumer are JPYdf's `CORE-MOD-012` | `ETH/USD × stETH/ETH` incorporates the ETH/USD update while preserving an stETH depeg in the price. Selecting the higher of that path and the direct path protects remaining borrowers and solvency; no cache on the urgent path prevents irreversible shutdown from reopening settlement against an old extractable price |
| Oracle pause / economic shutdown boundary | **Permissionless `TCR < SCR` shutdown is inherited from Liquity; the recoverable pause is a JPYdf change.** Liquity allows anyone to move an economically unsafe branch into wind-down, while JPYdf separated oracle failure into a recoverable state | Avoid permanent wind-down from a feed outage without giving the Owner a veto over legitimate economic shutdown. A `failure=true` price cannot reach the TCR check, while live-price recovery still leaves risk-increasing normal redemption and borrowing operations latched until a three-path validated resume. This avoids both a false terminal transition and an Owner veto |
| JPY freeze episode | **JPYdf-specific.** Liquity upstream has no shared JPY/USD denominator or soft freeze | Anchor freeze start to each round's `updatedAt + 72 hours`, not to observation time, and allow 24 hours from that point. This neither inherits an old episode nor permits indefinite extension by resetting on each read. A round already older than 96 hours may therefore expire when first observed |
| PriceFeed source configuration | **JPYdf-specific.** Liquity upstream has no `PriceFeedProxy`, three price consumers, or source-replacement lifecycle | Validate all three paths at the common initialization and replacement boundary, before a broken source is accepted or activated behind the Proxy fixed in branch wiring. Emergency replacement avoids calling a broken old source to preserve recoverability, while failing closed only on statically observable self-reference, nesting, and A↔B cycles |
| Initial Vault allocation | **JPYdf-specific.** Liquity has no counterpart to the CollateralVault / Strategy accounting layer | A plain transfer can be removed by the yield sweep, so the seed uses `backstopDeposit`; accepting dust would hide a real shortfall. The preflight checks headroom immediately before the first nonzero allocation. `allocate()` itself rechecks confirmed full backing after allocation in the same transaction and rolls the operation back on failure. Receipt-pinned post-check evidence remains separate |
| Canary recovery guard | **JPYdf operational behavior.** It is not part of the Liquity protocol lifecycle | Guard only the first nonzero allocation, where rounding risk first appears. A 1-USDC condition in every phase would block fund recovery after a legitimate backstop release or consumption |
| Pilot / Production Timelock | **JPYdf governance and deployment policy.** It is not inherited Liquity core behavior | Keep the pilot as a 300-second test identity and deploy production fresh with 43,200 seconds. A separate identity does not carry pilot roles, pending operations, or history into production, and avoids treating a self-call delay update as the production migration ceremony |
| Minimum debt | **A parameter change to a Liquity mechanism.** Liquity says each fork should choose `MIN_DEBT` based on redemption gas and list griefing by minimum Troves. JPYdf also considered liquidation economics in approving 100,000 through `CORE-MOD-002`; it is not claimed to be economically equivalent to 2,000 BOLD | Apply the approved JPY production threshold to entire debt including the upfront fee, using the existing Liquity semantics, and make code, manifest, and tests agree. Fixing the exact value, one-wei edge, repayment crossing, and zombie boundary removes interpretation differences among users, bots, and auditors |
| Token identity | **Liquity token logic with a JPYdf rename.** Core mint / burn / permit logic remains structurally equivalent; naming is `CORE-MOD-001` | Changing only the ERC-20 display identity would split wallet display from the EIP-712 / EIP-2612 signing domain. Bind name, symbol, and signature domain to one canonical identity |
| Day-1 Strategy topology | **JPYdf Vault integration.** It has no Liquity core counterpart | Canary Aave + Gauntlet evidence does not prove production Aave + Morpho V2. State required venues per active branch and require separate approval for an optional slot so evidence for different risk owners, vaults, and share prices cannot be reused |
| Reserved branch | **Liquity inheritance plus a JPYdf-specific change.** Liquity fixes six risk values in the constructor and does not permit later changes. Only JPYdf's `CORE-MOD-013` adds one-shot finalization for reserved branches | Do not permanently choose collateral-dependent values on Day 1 for an unknown asset. While economic state is empty, synchronize the underlying and all six values in one Timelock transaction. A one-shot lifecycle change prevents both use before finalization and partial configuration without creating a repeatable setter |
| Role / cap handover | **JPYdf deployment and Vault behavior.** It has no Liquity counterpart | Apply the same role checks to active and inert branches and make the positive cap that opens capital exposure the last independent receipt. If an authority or pending-operation anomaly appears, the process can stop while cap remains zero |
| Lido attribution | **JPYdf native-ETH route.** Liquity core has no Lido referral manager | A referral is Lido attribution metadata, not a funds recipient, so only that address is mutable. Bind its immutable manager to the production Timelock without creating any surface that can change principal, collateral, debt, or receiver |

## 4. Issues identified but not remediated

This section is not a risk-acceptance record. Open Medium / Low items require an explicit decision from Protocol Governance or the designated risk owner. `PAUSE-SHUTDOWN-01` was reported as High, but after the §3 mitigation it remains an intentional Liquity-inherited design boundary, not an open code fix. Info items also require recorded and confirmed audit dispositions, but no code change. “Explicitly documented by Liquity” identifies an upstream risk class or base mechanism only; it does not mean that Liquity accepted JPYdf-specific formulas, parameters, or dependencies.

**Origin and relationship to Liquity**

| ID | Origin / relationship to Liquity |
| --- | --- |
| `JPY-DENOM-01` (`F-1`) | **JPYdf-specific composition; the general class is explicitly documented by Liquity.** Liquity Known Issues record over- and underpayment in redemptions from push-oracle lag, a frozen last-good price, and stale prices before shutdown. The shared JPY/USD denominator and 72-hour plus 24-hour window are JPYdf-specific |
| `PAUSE-SHUTDOWN-01` | **Permissionless, irreversible `TCR < SCR` shutdown is inherited from Liquity.** JPYdf adds a mitigation layer that separates oracle failure into a recoverable pause and keeps normal redemption and BorrowerOperations stopped until explicit resume. Preserving Liquity's shutdown authority after live normal-price recovery is the intended boundary of that mitigation |
| `URGENT-LIVENESS-01` (`F-3`) | **The urgent mechanism is inherited; the current fail-closed dependency is JPYdf-specific.** Liquity prioritizes urgent-redemption availability through shutdown fallback pricing that can include available live legs and `lastGoodPrice`, and publishes the possible over- and underpayment as a Known Issue. JPYdf's `CORE-MOD-012` makes a third price path no-cache and fail-closed |
| `ORACLE-FAILURE-TO-URGENT-01` (`A2-1`) | **JPYdf-specific.** Liquity makes oracle failure itself irreversible; JPYdf changed it into a recoverable pause |
| `REDEMPTION-POLARITY-01` (`F-5`) | **The polarity is explicit in Liquity; its scope is JPYdf-specific.** Liquity applies `max` to normal WSTETH redemption inside a 1% gate. Unconditional direct / derived comparison and urgent-path use are JPYdf changes |
| `EMERGENCY-GUARD-01` (`B1-01`) | **JPYdf-specific.** Liquity upstream has no `PriceFeedProxy`, source proposal, or emergency confirmation |
| `URGENT-CACHE-ASYMMETRY-01` (`F-6`) | **JPYdf-specific.** Liquity upstream has no third urgent getter. Liquity's Known Issue about mixed provenance in shared `lastGoodPrice` is related but is not this finding. The only feed that currently uses the default `CompositePriceFeed` urgent getter without an override is the archived `sUSDSPriceFeed`; the production dwstETH feed inherits the same base but overrides this getter |
| `SOURCE-CONTINUITY-01` (`F-7`) | **JPYdf-specific.** Liquity has no counterpart to a replaceable source proxy with a third urgent getter |
| `PILOT-CLEANUP-OVERLAY-01` | **JPYdf-specific.** It is source compatibility for a retired pilot cleanup, not a Liquity feature |

**Business decisions**

| ID / Severity | Residual risk and business meaning | Why it was not changed / reconsideration trigger |
| --- | --- | --- |
| `JPY-DENOM-01` (`F-1`) / **Medium (conditional oracle-outage risk)** | If a readable shared JPY/USD round stops updating, its stored value may remain usable for up to 96 hours. A redeemer can receive excess collateral if JPY is sufficiently weaker at execution. In ordinary operation, the 0.15% deviation update listed for the [Chainlink JPY/USD feed](https://data.chain.link/feeds/ethereum/mainnet/jpy-usd) is below the 0.5% plus dynamic normal-redemption fee, so routine lag is generally uneconomic. The approximately 6.67% pre-fee excess in a 150-to-160 example is a tail illustration requiring a feed-delivery outage, a large favorable FX move, low fees, JPYdf acquisition, redeemable debt, and exit liquidity; it is not guaranteed profit. Scale depends on debt actually redeemed and reachable Trove collateral | The 72-hour policy prioritizes avoiding false stops across all branches; shortening maximum age or stopping immediately changes liveness. Do not make a one-directional Solidity change until Product / Protocol Risk chooses an independent reference, a redemption-specific age, or an explicit exposure envelope covering conditions and scale. A dToken `mintCap` alone is not a JPYdf branch debt ceiling |
| `PAUSE-SHUTDOWN-01` / **High audit observation; design non-defect** | If the live normal price recovers during an oracle pause and that price puts `TCR < SCR`, anyone can trigger irreversible shutdown before Owner resume. This is not direct theft; it moves an economically unsafe branch into permanent wind-down as Liquity specifies | The §3 mitigation prevents a `failure=true` price from reaching the TCR check and keeps normal redemption plus BorrowerOperations stopped until the Owner validates all three paths. Making shutdown Owner-dependent beyond that point would permit denial of legitimate wind-down, so no additional code change was made. Redesign only if Governance changes Liquity's permissionless wind-down model. Keeping it still requires an explicit Governance design disposition, monitoring, user disclosure, and external-auditor disposition |
| `URGENT-LIVENESS-01` (`F-3`) / **Medium** | After irreversible shutdown, urgent redemption depends on every policy-required price input and dependency read succeeding. If governance and the oracles fail at the same time, the emergency exit can stop. A failed transaction reverts in full and does not corrupt state | Cache fallback would reintroduce the closed price-transfer risk, and a timeout alone cannot create a valid quote. If governance remains live, it can propose a new source and replace it after 12 hours. Reconsider after degraded settlement, maximum tolerated downtime, and the source-replacement drill are approved as one policy |
| `ORACLE-FAILURE-TO-URGENT-01` (`A2-1`) / **Low** | While the normal path returns `failure=true`, irreversible shutdown is not evaluated and urgent redemption is not enabled. A healthy round normally restores the `TCR < SCR` path without Owner action. However, if the source fails permanently and the Safe acting as PriceFeed Owner cannot replace it, neither a healthy quote nor source replacement is possible, so the branch cannot move into irreversible shutdown and urgent redemption. Trove closure also depends on a price, so collateral may remain locked for an extended period | Allowing irreversible shutdown on a failed price could create a false terminal transition. Keep code unchanged and address maximum tolerated downtime, alerts, source-replacement SLO, governance availability, and this joint-failure condition in operational gates and Public Known Risks |
| `REDEMPTION-POLARITY-01` (`F-5`) / **Low** | `max(direct, derived)` may underpay a redeemer when one path is stale-high. It protects protocol solvency and remaining borrowers, but leaves a fairness and disclosure risk | `min` or a simple freshest-only rule can reopen collateral extraction when a path is stale-low. Retain the solvency-protective polarity for now, require public disclosure and explicit Product / Protocol Risk acceptance, and redesign only if a fairness-prioritizing formula is approved |
| `EMERGENCY-GUARD-01` (`B1-01`) / **Low** | Even if only a redemption leg is unhealthy, emergency source confirmation skips the normal, redemption, and urgent deviation checks together. It is not directly permissionless, but operator error or compromise of the PriceFeed Owner could accept a large price discontinuity | Avoiding the broken old source is necessary for recovery; a per-leg bypass requires a new state machine and tests. Keep the 12-hour Timelock, new source's three-path smoke test, private execution, cap stop, role evidence, and monitoring. Reconsider after a per-leg policy is designed and audited. Cache refresh prepares normal confirmation; it is not a post-emergency price guarantee |
| `URGENT-CACHE-ASYMMETRY-01` (`F-6`) / Info | The Standard urgent getter and the default `CompositePriceFeed` urgent getter—currently used without an override only by the archived `sUSDSPriceFeed`—update the source's normal `lastGoodPrice`; the production dwstETH override does not. Urgent settlement has no cache fallback. In the current Standard source, urgent and normal prices are equal, so the write is harmless; for dwstETH, a settlement quote must not enter the normal borrow / liquidation cache | **Intentional asymmetry.** Symmetrizing writes or adding a third cache changes cache semantics without improving current safety. Redesign and re-audit when another Composite source with different normal and urgent formulas is introduced into production |
| `SOURCE-CONTINUITY-01` (`F-7`) / Info | During normal confirmation when the old source is unhealthy, urgent continuity aliases `_lastGoodRedemptionPrice` as its baseline. Current production sources use the same formula for normal and urgent redemption, so this is not a present pricing error; future formula divergence could make the baseline inappropriate | **Known current constraint.** Tests pin present formula equality, and no independent urgent cache is added because it would introduce stale state without a current need. Add a dedicated continuity baseline and audit when a source with divergent formulas is introduced |
| `PILOT-CLEANUP-OVERLAY-01` / Info | A pilot-cleanup helper and dust bound remain in source. In production, `MAINNET_PILOT_CLEANUP_OVERLAY = false` disables it even on chain 1, `effectiveSPYieldSplit()` returns the canonical 75%, and there is no runtime toggle or token-side pilot call / dust burn | It does not change production behavior, and the current rollback gate permits the inactive helper. If removed, treat it as source cleanup rather than a functional fix and refresh candidate bytecode plus the audit differential |

### How to interpret the “up to 96 hours” and 150-to-160 example

- The 96 hours is the policy maximum round age. It does not mean that the same price gap persists for 96 hours or that the full period is profitable.
- The market does not have to move continuously in one direction. A redeemer can execute only when the gap exceeds fees and costs in the favorable direction, while abstaining when it is unfavorable. Direction uncertainty therefore does not invalidate the path, but the oracle outage and favorable FX move must overlap, reducing likelihood.
- 6.25% is the reduction in the collateral's JPY quote relative to the fresh value of 160; approximately 6.67% is the additional collateral a redeemer receives before fees because of the inverse relationship. Neither is a contractual upper bound on loss.
- The protocol's `JPY/USD` feed is USD per JPY. The 150→160 notation follows the market convention for USD/JPY, meaning JPY per 1 USD.
- Normal-redemption break-even requires an approximately 0.503% favorable gap even at the fee floor. Actual profit also depends on the dynamic base rate, execution costs, JPYdf acquisition, debt that can actually be redeemed, reachable Trove collateral, and exit liquidity for the received dToken. Urgent redemption has no normal fee but requires an irreversibly shut branch.
- Monitoring can detect the condition sooner, but does not remove the on-chain behavior that permits an old rate to be used before its deadline.

## 5. Items outside Solidity or awaiting production execution

| ID / Classification | Source-level status | Business meaning / evidence required for completion |
| --- | --- | --- |
| Oracle alert identity (`ORACLE-ALERT-01` / `F-2`) / **Medium** | The off-chain monitor identity now uses a stable key based on chain / branch / `PriceFeedProxy`. Human delivery is outside the code | Labelled trigger → intended human receipt → resolution using the same key. Do not leave a state in which only one synthetic is resolved |
| Chainlink decimals migration (`DECIMALS-MIGRATION-01` / `B2-L1`) / **Low tail risk** | Safe-head monitor logic has been reviewed. No on-chain band has been selected | A decimals change can move the price scale by `10^N`, causing widespread wrongful liquidation or excessive borrowing. Trigger probability is low, but tail impact is large. P0 notification to every role, human receipt, and resolution using the same key are required. If a band is introduced, policy approval is also required for both scale directions and fresh / stale-newer cases |
| Public Known Risks / Documentation | JP / EN Risk Disclosure pages already exist, but do not yet include these specific Known Risks, acceptance conditions, risk owners, or reconsideration criteria. The public Oracle explanation also needs synchronization with the current `max(stETH/USD, ETH/USD × stETH/ETH)` formula | Before Public Activation, update the existing Risk Disclosure, Oracle, and Redemption pages. Publish F-1, pause → shutdown, urgent fail-closed behavior including collateral lock when permanent source failure coincides with an unavailable PriceFeed Owner / Safe, “worst price,” and emergency source recovery in structurally matched JP / EN content with conditions, user impact, mitigations, risk owner, and reconsideration trigger. Exclude exploit playbooks, private endpoints, signers, and unpublished ceremony details; keep this separate from the Governance acceptance record |
| Vault backstop (`VAULT-BACKSTOP-01` / `LB-1`) / Launch procedure | Code and tests are remediated | For canary: prior receipt for `backstopDeposit(1_000_000)` and readback of at least 100,000 base units of confirmed headroom immediately before the first allocation. For production: measure the final Strategy set on a fork and use an approved asset-specific seed / headroom |
| Day-1 production seed / Gate gap | `VAULT-FR-004` defines the fork-measurement rule, but at the Snapshot date the Day-1 launch gate quantified only the canary's 1 USDC / 0.1 USDC and did not define the exact quantity or approval owner for production Aave + Morpho V2 | Before the first production nonzero allocation, add the asset-specific seed, minimum headroom, approval owner, and immediate pre-allocation readback to the Mainnet Initial Configuration Checklist or Launch Operation Gate. Do not substitute the canary value or the future inert-branch gate |
| Canary post-check (`CANARY-EVIDENCE-01`) / **Medium operations** | Foundry preflight exists | Post-transaction verification pinned to transaction, receipt, and block hash. Simulation alone is not production evidence |
| Timelock unknown holder / **High** | `AccessControl` can check required holders but is not enumerable | Review role events, receipt by receipt, from creation through the pre-handover block and prove that no unknown admin / proposer / executor / canceller exists |
| Timelock aged operation / **High** | An operation can be scheduled and its waiting period advanced before ownership handover | Review operation events from creation through the pre-handover block and allowlist every pending operation |
| Production Timelock identity / Gate | The 12-hour deployment script, tests, and runbook exist | Block-pinned current-state readback for the Safe, runtime hash, constructor, and `getMinDelay() == 43,200`, plus the complete role / operation event history since creation |
| Final candidate binding / **Medium** | A source-level checker exists | Bind the candidate tree, manifest, release / code hash, 100,000 JPYdf value, and every broadcast receipt into one package |
| 100M JPYdf stress / Auditor-handoff gate | This additional gate is recorded in the auditor-facing handoff and awaits external-auditor acceptance. It is not yet included in the current [Mainnet Fork Stress Gate](../../protocol/launch/gates/Mainnet-Fork-Stress-Gate.md) | Either add and execute the 100M JPYdf / approximately 1,000 minimum-Trove scenario in total across both active branches in the authoritative gate, or add and execute a Governance-approved alternative gate |
| Cap activation / **Medium** | Prepare keeps cap at 0 | The final independent receipt-pinned step, performed only after ownership and role verification succeeds |

## 6. Proposed fixes not adopted

The following are not merely “unresolved.” They were rejected because implementing them would create a different failure mode.

| Proposal | Why it was not adopted |
| --- | --- |
| Set the strategy price to `min(value, withdrawable)` | A normal withdrawal pause on Aave or a similar venue could appear as insolvency and trigger mass liquidation of otherwise sound books |
| Apply the confirmed-backing gate to `receiveFromStrategy` | It would close the fund-recovery path needed to repair a shortfall |
| Add a dust epsilon to the Vault solvency gate | It could defer a shortfall and later price the asset below par. A protected backstop addresses the cause more clearly |

## 7. Phase-specific gates for Solidity remediation

This section summarizes **only the necessary conditions related to Solidity remediation**. It does not state sufficient conditions for mainnet as a whole. The [Mainnet Initial Configuration Checklist](../../protocol/launch/gates/Mainnet-Initial-Configuration-Checklist.md) and [Mainnet Launch Operation Gate](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md) are authoritative for the full sequence and Go / No-Go decision.

| Owner | Required action |
| --- | --- |
| Product / Protocol Risk | Explicitly classify `F-1`, urgent-feed conjunction, `F-5`, and emergency bypass as remediated, accepted, or launch-blocking. Confirm the design disposition for the inherited pause → shutdown boundary and approve the user-facing Public Known Risks wording |
| Protocol Governance | Approve the production Timelock, Safe, role / event history, pending operations, ownership handover, cap-last sequence, and reserved-branch activation |
| Engineering | Complete the final static analysis, pinned mainnet fork, and receipt-pinned checker. Either add and execute the 100M JPYdf scenario in the authoritative gate, or add and execute a Governance-approved alternative gate. `BorrowerOperations` has only 76 bytes of EIP-170 runtime headroom, so rerun the size gate after any further change to that contract |
| Operations | Prove the canary 1 USDC minimum and 100,000-base-unit minimum headroom. For production, add the approval owner and asset-specific seed / headroom to the Day-1 gate before proving first allocation / recovery. Also complete human delivery of Oracle / Vault P0 alerts |
| External auditor | Accept the final Solidity differential from the frozen baseline and confirm the disposition of open items |

| Phase | Solidity-remediation conditions before proceeding | Status |
| --- | --- | --- |
| 0. Production Timelock creation | Separately approve the fresh Timelock bytecode, constructor, 12-hour delay, and Safe. Its address must differ from the pilot | Do not execute without approval of the independent ceremony |
| 1. Protocol deploy | External-auditor acceptance of the 113-file differential from frozen baseline `ad2445667fe5a72f287c210b34a0e464cf44b4e9` to materialized audit candidate `b3615d075f41028367f2f44557e48e08e4903171` (primary review scope: 24 source / interface paths); explicit dispositions for High / Medium risks and risks involving user fairness; final static analysis; either addition and execution of the 100M JPYdf scenario in the authoritative gate or addition and execution of a Governance-approved alternative gate; pinned mainnet fork using the final manifest | Protocol deploy is No-Go until the conditions are complete |
| 2A. Pilot / canary evidence | On a canary with a different address and topology from production, complete `backstopDeposit(1_000_000)`, the first allocation, and the receipt-pinned post-check | Do not reuse canary evidence as production proof |
| 2B. Production handover / pre-allocation | Complete review of role / operation events since Timelock creation, ownership acceptance, and continued cap 0. Add the approval owner, fork-measured production seed / headroom, and immediate pre-allocation checker to the Day-1 gate. Immediately before the first production nonzero allocation, obtain the asset-specific `backstopDeposit` receipt and headroom readback | Gate updates and transaction-specific approval and evidence are required |
| 3. Public activation / positive cap | Complete all role readbacks; prove that no unknown holder exists and that only approved pending operations remain; prove P0 alert trigger → human receipt → resolution using the same key; publish structurally matched JP / EN Known Risks; retain the final cap-last receipt | Public Activation is No-Go until complete |

## 8. Verified scope and wording constraints

For the candidate fixed by the Snapshot identity, the Foundry CI profile reported 1,832 pass / 0 fail / 2 skips; the production Timelock profile reported 5 pass / 0 fail / 2 expected skips; and the production contract-size gate passed. The minimum runtime headroom is 76 bytes in `BorrowerOperations`; rerun the size gate after every subsequent Solidity change.

However, the final static-analysis refresh, mainnet fork, 100M JPYdf stress test, broadcast, receipt-pinned post-check, and end-to-end alert delivery have not been completed. Do not use the following statements:

- “All vulnerabilities have been fixed.”
- “The current version has external-auditor approval.”
- “The tests passed, so it can be deployed to mainnet.”
- “Oracle risk or governance risk has been eliminated.”

The accurate statement is:

> Some source-level remediation and regression verification are complete. Intentionally retained design risks and pending production-chain and operational evidence remain. There is currently no general approval to broadcast to mainnet; Protocol deploy and Public Activation remain No-Go until their respective phase gates are complete.

## 9. Current sources of truth

| Subject | Current source of truth |
| --- | --- |
| Day 1 values, 100,000 JPYdf, 96-hour boundary, 12-hour delay | [Day 1 Parameter Manifest](../../Parameters.md) |
| JPYdf name / symbol, permit, EIP-712 domain | [JpydfToken Specification](../../protocol/product/spec/JpydfToken.md) — `CORE-BT-FR-010`, `CORE-BT-FR-011` |
| Oracle prices, freeze, sources, urgent path, and safety requirements | [Oracle Specification](../../protocol/product/spec/Oracle.md) — `ORCL-FR-016`, `ORCL-SEC-003`, `ORCL-SEC-005`, `ORCL-SEC-008`, `ORCL-INV-004`, `ORCL-INV-013`, `ORCL-INV-014` |
| Vault backing, allocation, and backstop | [CollateralVault Specification](../../protocol/product/spec/CollateralVault.md) — `VAULT-FR-004`, `VAULT-FR-017`, `VAULT-SEC-010` |
| Day-1 Strategy topology | [Mainnet Deploy Env Freeze Runbook](../../protocol/launch/gates/Mainnet-Deploy-Env-Freeze-Runbook.md) — branch 0 has no Strategy; branch 1 requires Aave V3 + Morpho Vault V2; an additional `erc4626` is permitted only when separately approved |
| MIN_DEBT, urgent consumer, and reserved-risk finalization | [Liquity v2 Core Specification](../../protocol/product/spec/Liquity-v2-Core-Spec.md) — `CORE-MOD-002`, `CORE-MOD-012`, `CORE-MOD-013`, `CORE-LIB-FR-002`, `CORE-AR-FR-005` |
| Lido attribution | [Zapper Specification](../../protocol/product/spec/Zapper.md) — `ZAP-GOV-004` |
| System-level launch risk | [Mainnet Launch Risk Gate](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md) |
| Canary 1 USDC / 0.1 USDC headroom and cap-last sequence | [Mainnet Launch Operation Gate](../../protocol/launch/gates/Mainnet-Launch-Operation-Gate.md) |
| Production Timelock execution | [Mainnet Timelock Deploy Runbook](../../protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md) |
| Future inert-branch activation / seed | [Inert Branch Activation Runbook (English context)](../../protocol/operations/runbooks/Inert-Branch-Activation-Runbook.md). It does not cover Day-1 active branches |
| Day-1 production seed / headroom | [CollateralVault Specification](../../protocol/product/spec/CollateralVault.md) `VAULT-FR-004` defines the measurement principle, but at the Snapshot date the exact quantity and approval owner were not included in an authoritative launch gate |
| Fork / stress completion criteria | [Mainnet Fork Stress Gate](../../protocol/launch/gates/Mainnet-Fork-Stress-Gate.md). The 100M JPYdf / approximately 1,000-Trove scenario in total across both active branches is an additional gate recorded in the auditor-facing handoff and awaiting external-auditor acceptance; at the Snapshot date, either that scenario still had to be added and executed in this gate, or a Governance-approved alternative gate had to be added and executed |

Finding IDs from the audit handoff are for historical traceability and do not replace the canonical `SYS-RISK-*` IDs. Record Governance dispositions in the [Mainnet Launch Risk Gate](../../protocol/launch/gates/Mainnet-Launch-Risk-Gate.md), linking handoff IDs as Evidence references. Do not create an independent acceptance state in this Historical snapshot.
