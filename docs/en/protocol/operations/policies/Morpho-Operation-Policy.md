# Morpho Operation Policy

## Positioning

This document defines how JPY DeFi operates Morpho when Morpho is adopted as a collateral
Strategy venue: operating model, vault / market selection, allocation, roles, oracle / LLTV / IRM,
monitoring, and emergency response.

Responsibilities are split as follows.

| Document | Responsibility |
| --- | --- |
| This document | Morpho-specific operation gates, role design, market / vault selection, monitoring, and incident handling |
| [`Strategy-Selection-Policy.md`](Strategy-Selection-Policy.md) | Cross-venue gate for approving external Strategy venues |
| [`Collateral-Asset-Management-Policy.md`](Collateral-Asset-Management-Policy.md) | Day-1 branch configuration, candidate venues, and current adapter coverage |
| [`../../product/spec/strategies/ERC4626Strategy.md`](../../product/spec/strategies/ERC4626Strategy.md) | `ERC4626Strategy` contract requirements, `asset()==underlying`, and the recovery model that uses `maxWithdraw` / `maxRedeem` |
| [`../../product/spec/strategies/MorphoV2Strategy.md`](../../product/spec/strategies/MorphoV2Strategy.md) | `MorphoV2Strategy` contract requirements for Morpho Vaults V2: no reliance on max\* views, fail-soft recovery, `forceDeallocate` wrapper, penalty bound |
| [`../../product/spec/strategies/Strategy.md`](../../product/spec/strategies/Strategy.md) | Common Strategy requirements, push model, permissions, accounting, and invariants |
| [`../../Parameters.md`](../../../Parameters.md) | Final values for branch caps, buffers, withdraw delays, Strategy caps, and weights |
| [`../runbooks/Morpho-Day1-Vault-Freeze-Package.md`](../../launch/gates/Morpho-Day1-Vault-Freeze-Package.md) | Freeze package for Day-1 adopted vaults, curator, oracle, queue, bad debt, and withdrawability |
| [`Strategy-Incident-Liquidation-Safety-Runbook.md`](../runbooks/Strategy-Incident-Liquidation-Safety-Runbook.md) | Strategy incident allocation stop, recovery, and liquidation-safety decisions |
| [`Vault-Buffer-Shortfall-User-Comms-Runbook.md`](../../../contributors/deltaforesight/operations/Vault-Buffer-Shortfall-User-Comms-Runbook.md) | User communication for Vault buffer shortfalls and delayed claims |

Morpho is a **conditional Day-1 planned-active venue for `dUSDC`**. Branches 2–7 have no Day-1 allocation, so a Morpho path for any of them is reconsidered only with that branch's cap or activation decision. However,
this document does not by itself approve a specific vault address / cap / weight. Actual allocation
requires an activation package covering this policy, `Parameters.md`, deploy env, preflight, fork
evidence, ops / frontend gates, and Safe / Timelock evidence. Incomplete evidence keeps Morpho
allocation closed; the dUSDC Aave baseline remains the approved Day-1 path.

## Decisions

1. **Morpho adoption is limited to vault-share adapters with `asset()==branch underlying`**. To use
   Morpho from Day-1, it is limited to vaults expressible by `ERC4626Strategy` (V1 / MetaMorpho) or
   the dedicated `MorphoV2Strategy` (Vaults V2). Routes that convert USDC into another asset or
   adapters that directly operate Morpho markets are not approved here.
2. **Day-1 adoption should prefer supplying to third-party curated vaults**. A DeltaForesight
   curated vault has a larger operational scope around roles, allocators, caps, queues, market
   selection, and incident response, so it is Day-2 or a separate activation package.
3. **Morpho Vault V2 rejection is superseded (2026-08-05): V2 is conditional via the dedicated
   `MorphoV2Strategy`, and remains No-Go via `ERC4626Strategy`**. Vault V2 exposes an ERC-4626
   interface, but its official implementation returns zero for `maxDeposit`, `maxMint`,
   `maxWithdraw`, and `maxRedeem`, so `ERC4626Strategy` — which uses `maxWithdraw(this)` /
   `maxRedeem(this)` as recovery limits — cannot satisfy the normal or emergency recovery evidence;
   that part of the original decision still stands. The blocker was adapter-specific: the merged
   [`MorphoV2Strategy`](../../product/spec/strategies/MorphoV2Strategy.md) (kind `morpho-v2`) never
   consults the max\* views, clamps to its own tracked shares, fail-softs liquidity-short
   withdrawals, and wraps `forceDeallocate` under an init-frozen penalty bound. V2 adoption is
   therefore conditional on the V2 gate rows below, the activation package, and external audit —
   no longer rejected outright.
4. **Conventional MetaMorpho / Morpho Vault V1 style ERC-4626 vaults are the Day-1 compatible family**.
   Adoption still requires freezing `asset()==underlying`, `convertToAssets`, `maxWithdraw` /
   `maxRedeem`, roles, timelocks, caps, queues, fees, and underlying market exposure.
5. **Public Allocator dependency is default-off**. Public reallocation can help exits, but it is not
   adoption evidence until max flows, fees, admins, queue changes, and abuse impact are frozen.
6. **Vault / market adoption evaluations are recorded with the six-axis evaluation framework**. Each
   axis is classified as `PASS / REVIEW / BLOCKER`; a single `BLOCKER` keeps the Day-1 allocation
   closed, and each `REVIEW` remains unapproved until the risk owner explicitly accepts, caps down,
   or rejects it on the issue. The axes and classification rules are defined in the six-axis
   evaluation framework under "Market / Collateral Criteria".

## Operating Models

| Model | Day-1 policy | Main responsibility / risk |
| --- | --- | --- |
| Supply to a third-party curated MetaMorpho / Morpho Vault V1 | Conditional Day-1 path for dUSDC only; other branches wait for their cap or activation decision. Requires `asset()==underlying` and complete activation evidence | External curator / owner / allocator / guardian are a trust boundary. DF manages Strategy cap / weight / buffer / monitoring / emergency withdrawal |
| DeltaForesight curated vault | Day-2 or separate activation package | DF directly owns market selection, caps, queues, allocator, guardian, and incident response. Requires role mapping, an ops bot, Safe calldata, market scoring, and monitoring |
| Morpho Vault V2 | Conditional via the dedicated `MorphoV2Strategy` (kind `morpho-v2`); still No-Go via `ERC4626Strategy` | `maxWithdraw` / `maxRedeem` are zero by design, so `ERC4626Strategy` recovery gates are not met. `MorphoV2Strategy` does not rely on the max\* views; adoption requires the V2 gate rows below, activation package, and external audit. Day-1 mapping: branch 1 dUSDC; branch 0 (wstETH) waits for a credible wstETH V2 vault |
| Direct Morpho Blue market operation | Out of scope | This is not ERC-4626 share accounting and would require a dedicated Strategy and audit |

Even when using a third-party curated vault, DF indirectly takes exposure to the markets selected by
the external curator. Adoption therefore monitors not only the vault address but also markets with
non-zero caps / exposure, supply queue, withdraw queue, owner / curator / guardian / allocator, and
timelock pending actions.

## Adapter / Preflight Gate

Before registering a Morpho vault through `ERC4626Strategy`, the activation package must include at
least the following evidence.

| Gate | Required evidence |
| --- | --- |
| Chain / source | Freeze the Ethereum mainnet official-source address, proxy / implementation, code hash, and deployment source |
| Asset match | `IERC4626.asset() == branch underlying`; branch 1 is USDC, and every other branch must match exactly the Underlying already bound to that branch |
| Decimals / token behavior | Underlying decimals, share decimals, fee-on-transfer / rebasing / blacklist / transfer restrictions |
| Share price | Readbacks for `convertToAssets(10 ** decimals)` and `convertToShares`, plus the bad-debt / loss reflection model |
| Withdrawability | `maxWithdraw(strategy)` / `maxRedeem(strategy)` are non-zero in normal conditions, with partial and full withdraw fork dry-runs |
| Emergency path | Dry-runs for `sendToVault`, `emergencyWithdrawFromERC4626`, partial recovery, and residual principal writeoff |
| Governance / roles | Owner, curator, guardian / sentinel, allocator, fee recipient, timelock, pending actions, upgrade / registry / gate permissions |
| Market exposure | loanToken, collateralToken, oracle, IRM, LLTV, supply cap, current exposure, and queue position for the markets the vault can supply |
| Monitoring | Alert owner for share price, maxWithdraw, market utilization, oracle, role changes, cap / queue changes, bad debt, and withdrawal failure |

If `maxWithdraw` / `maxRedeem` are zero, distinguish temporary illiquidity from a design that always
returns zero. A Vault V2-style design is not adopted through `ERC4626Strategy`; it must go through
`MorphoV2Strategy` and the V2 gate rows below. Temporary illiquidity is handled as exit / allocation
operational risk, not immediate loss.

Before registering a Morpho Vaults V2 vault through `MorphoV2Strategy` (kind `morpho-v2`), the
activation package must additionally include at least the following evidence.

| V2 Gate | Required evidence |
| --- | --- |
| Adapter registry | Registered adapter set (IDs, addresses, target protocols) is read back and each adapter is explained; unexplained adapters are a blocker |
| Gates unset | All four gates (receive-shares / send-shares / receive-assets / send-assets) are unset. Installation is curator-timelocked, but an installed gate's allowlist can freeze an address instantly, so unset is the freeze criterion |
| Sentinel | Sentinel is set and its holder / escalation path is explained |
| maxRate | `maxRate` is nonzero and monitored — the deployment default is 0, which withholds all yield. Accepting a zero-`maxRate` venue requires explicit risk-owner approval |
| Per-selector timelocks | Timelock values per selector are read back per vault. They **default to zero**; nonzero values are a freeze checklist item, not a protocol guarantee |
| forceDeallocate penalty | Every adapter's `forceDeallocatePenalty` is ≤ the Strategy's init-frozen `maxForceDeallocatePenaltyBps` (protocol max 2%) |
| Adapter liquidity | Per-adapter deallocatable liquidity readback plus vault idle balance; idle + `forceDeallocate` dry-run replaces the max\*-based withdrawability evidence used for ERC-4626 vaults |

## Market / Collateral Criteria

In a third-party curated vault, DF does not directly set markets. Even so, markets with live exposure
or non-zero caps are indirect JPYdf risk and must satisfy these checks.

| Item | Adoption criterion |
| --- | --- |
| loan asset | Same as branch underlying: WETH for the WETH branch and USDC for the USDC branch |
| collateral asset | Mainnet liquidity, issuer / custody, oracle coverage, depeg / slashing / bridge risk can be explained |
| oracle | Source, scaling, staleness, upgrade / admin, fallback, and liveness under abnormal values are understood |
| LLTV | Conservative relative to collateral volatility and liquidation liquidity |
| IRM | Enabled IRM with explainable liveness risk under reverts, extreme rates, or admin changes |
| market health | Utilization, available liquidity, bad-debt history, liquidation path, and supplier exit depth are known |
| cap / queue | Supply cap, withdraw queue, and supply queue match the adoption purpose; unsafe markets are not placed ahead of safer exits |

For a DeltaForesight curated vault, markets are classified as follows.

| Class | Policy |
| --- | --- |
| Base market | Markets such as ETH / BTC / major stable collateral where liquidity, oracle, liquidation history, and counterparty risk are explainable. Can be an initial candidate |
| Case-by-case market | LSTs, yield-bearing shares, stable assets with stronger issuer / custody risk, or concentrated-liquidity assets. Requires a specific risk memo and low cap |
| Rejected market | Long-tail collateral, unverified oracle, bridge-only asset, illiquid collateral, or share-token collateral without oracle review |

Recursive structures where vault shares are collateral in another market, or structures depending on
vault-share AUM oracles, are not adopted until oracle manipulation and bad-debt propagation are
explained.

### Six-Axis Evaluation Framework

Candidate vaults and markets are evaluated on the following six axes, recording
`PASS / REVIEW / BLOCKER` per axis.

| Axis | Target | PASS | REVIEW | BLOCKER |
| --- | --- | --- | --- | --- |
| A Monitoring risk / cost | Monitoring load of the curator / queue / role / market structure | Simple and coverable by dashboards / alerts | Composite structure, Public Allocator, or frequent queue / cap changes that need an explicit owner | Black box; role / queue / cap changes cannot be tracked |
| B Issuer / curator credibility | Track record of the vault owner / curator / guardian / market collateral | Established protocol / curator whose holders and timelocks can be explained | Newer or strongly externally dependent, but audits and operating history can be explained | Unknown holders, unaudited, unresolved major incidents, or unexplainable admin-takeover risk |
| C Price stability / liquidation ease | Collateral price, liquidation depth, loan-asset match | ETH / BTC / major stables with explainable oracle and liquidation liquidity | LSTs, yield-bearing shares, RWAs, or governance tokens that need haircuts / low caps | Long-tail / bridge-only / illiquid collateral, or an unexplainable liquidation path |
| D Structural soundness | Recursive exposure, share collateral, oracle / AUM dependency | Simple overcollateralized market | Composite strategies, non-recursive share / structured exposure, or non-RED Morpho API warnings | Recursive vault shares, AUM-oracle dependency, unsupported collateral, RED Morpho API warnings, or serious structural defects |
| E Time constraints / exit | Maturity, withdraw queue, utilization, `maxWithdraw` | Immediate exit path, or one consistent with withdrawDelay | High utilization, queue degradation, or maturity / locks absorbable with dry-runs and buffer | Exit blocked, expired / near maturity, or `maxWithdraw` / `maxRedeem` evidence unavailable |
| F Verifiability | On-chain / API / official source / fork dry-run | Fully verifiable via official sources and fork readbacks | Partially relies on off-chain / API / curator explanations but can be evidenced | Current sources unavailable, fork dry-run impossible, or unverifiable |

Classification is per axis, and `REVIEW` / `BLOCKER` counts are the number of axes classified as such.

- `PASS` only, or up to one `REVIEW`: base candidate. Proceed to the normal cap / weight discussion.
- Two or more `REVIEW`: capped candidate. Adoption requires cap-down, weight-down, additional
  monitoring, withdraw dry-runs, and Safe calldata.
- One or more `BLOCKER`: No-Go. Allocation stays closed unless explicitly approved as a scope change.

This classification is applied at both the market level and the vault level. In a third-party curated
vault, even if the vault itself is PASS, any supplied market classified as REVIEW / BLOCKER is
recorded on its own row with its exposure, cap, queue position, and withdraw path. BLOCKER / REVIEW
findings from `morpho-vault-freeze-evidence.ts` are recorded against the corresponding axis.

**Axis E carve-out for Morpho Vaults V2 (`morpho-v2`)**: `maxWithdraw` / `maxRedeem` returning zero
is the V2 design, not missing evidence, so it is not by itself an axis-E BLOCKER for a
`MorphoV2Strategy` candidate. Axis-E evidence for V2 is instead: vault idle balance, per-adapter
deallocatable liquidity readback, and a `forceDeallocate` dry-run. For `erc4626` candidates the
original rule stands: unavailable max\* evidence remains a BLOCKER.

## Allocation Policy

Morpho allocation is not controlled only by Morpho-side caps. JPYdf must freeze at least:

- branch mintCap, CollateralVault buffer, withdrawDelay, Strategy cap, and Strategy weight
- `DF_STRATEGY_KIND_i=erc4626` with `DF_STRATEGY_ERC4626_VAULT_i`, or `DF_STRATEGY_KIND_i=morpho-v2`
  with `DF_STRATEGY_MORPHOV2_VAULT_i` / `DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_i`, plus
  `DF_STRATEGY_CAP_i` and `DF_STRATEGY_WEIGHT_BPS_i`
- activation block / fork block, normal-withdraw dry-run amount, and stress-withdraw dry-run amount
- immediate user-claimable amount from the Vault buffer and expected recoverable amount from Morpho

Initial allocation prioritizes the Aave baseline and Vault buffer, then sizes Morpho conservatively
against observed liquidity and withdrawal dry-runs. Cap / weight increases require the same style of
evidence as the active branch cap-ramp runbook: SP coverage, DEX liquidity, liquidation bot, fork
stress, and ops monitoring.

Morpho share-price appreciation follows `ERC4626Strategy` accounting. External incentives / Merkl
rewards are pushed to the Vault buffer when they are Underlying, swept to Treasury when they are
ordinary non-Underlying / non-share reward tokens, and rejected before claim when they are share
tokens.

## Role Mapping

In third-party curated vaults, Morpho roles are external trust boundaries that DF cannot change.
The adoption package still readbacks holders, thresholds, timelocks, pending actions, fee recipient,
and queue / cap permissions.

For a DeltaForesight curated vault, the default role mapping is:

| Morpho role | DF holder principle | Policy |
| --- | --- | --- |
| Owner | `GOV_MULTISIG` + `TimelockController` | Top-level configuration such as curator / guardian / allocator / fee / timelock. Not held by a hot key |
| Curator | `GOV_MULTISIG` + `TimelockController` or Risk Safe | Supply caps, market removal, allocator permissions. Cap increases / market additions are timelocked |
| Guardian / Sentinel | Guardian Safe | Revokes unsafe pending actions and handles emergency deallocation |
| Allocator | Allocator Safe or hardened allocator bot | Supply / withdraw queues and reallocation. Bots require caps, allowlists, kill-switches, monitoring, and manual fallback |
| Fee recipient | Treasury Safe | Recipient if performance / management fees are set. Fees require explicit activation approval |

For Vault V2 adoption through `MorphoV2Strategy`, the activation package MUST freeze all of the
following (normative; mirrors the V2 Gate table in "Adapter / Preflight Gate"):

- owner / curator / sentinel / allocator holders and the Sentinel escalation path
- the adapter registry entries (IDs, addresses, target protocols)
- all four gates (receive-shares / send-shares / receive-assets / send-assets) confirmed unset —
  an installed gate's allowlist can freeze an address instantly even though installation is
  curator-timelocked
- per-selector timelock values per vault (they default to zero; nonzero is a checklist item, not a
  protocol guarantee)
- `maxRate` (deployment default 0 withholds yield; a monitored knob)
- per-adapter `forceDeallocatePenalty` ≤ the Strategy's init-frozen `maxForceDeallocatePenaltyBps`
- the liquidity adapter and its deallocatable-liquidity readback

Vault V2 is never registered through `ERC4626Strategy`.

## Oracle / LLTV / IRM

Morpho market risk is determined at least by `loanToken`, `collateralToken`, `oracle`, `irm`, and
`lltv`. Per-market evidence must include:

- oracle address, source, scaling, admin / upgrade, and behavior on stale / paused / reverting feeds
- how a collateral price drop, oracle delay, or liquidation latency propagates into supplier loss
- whether LLTV and liquidation incentive are conservative against collateral volatility / DEX depth / oracle cadence
- whether the IRM is enabled and preserves supply / withdraw liveness under extreme utilization
- whether there is existing bad debt, a liquidation bottleneck, oracle controversy, or admin incident

Collateral depeg or oracle issues may not immediately appear in `convertToAssets`. JPYdf separates
confirmed loss from unconfirmed market-health risk. Before confirmed loss, use cap / weight
reduction, allocation pause, withdrawal dry-runs, and Safe calldata preparation.

## Monitoring

At Morpho adoption, ops dashboards / alerts / runbooks must monitor at least:

| Target | Metrics | Action trigger |
| --- | --- | --- |
| ERC-4626 vault | totalAssets, totalSupply, share price, `convertToAssets`, `maxWithdraw`, `maxRedeem` | share-price drop, sharp maxWithdraw drop, redeem revert, totalAssets drop |
| Vault roles | owner, curator, guardian / sentinel, allocator, fee recipient, timelock, pending actions | holder change, timelock decrease, fee increase, cap increase, unsafe market addition |
| Queue / cap | supply queue, withdraw queue, market cap, current exposure, idle market | unsafe market remains behind exits, exposure remains in cap-0 market, queue change |
| Market | utilization, available liquidity, bad debt, collateral price, liquidation volume | high utilization, liquidity drain, bad debt, liquidation stall |
| Oracle / IRM / LLTV | oracle price, staleness, revert, IRM rate, enabled status, LLTV | oracle stale / revert, LLTV change, IRM change, abnormal rate |
| JPYdf side | Strategy principal, estimatedTotalUnderlying, buffer, queued claims, cap / weight | divergence between estimate and recoverable amount, buffer shortfall, delayed claims |

## Emergency / Writeoff Linkage

Morpho incidents use three levels.

| Level | Situation | First response |
| --- | --- | --- |
| Watch | High utilization, maxWithdraw drop, queue / cap change, oracle warning, role pending action | Prepare allocation stop, withdrawal dry-run, cap / weight reduction proposal, Safe calldata |
| Action | Unsafe market exposure, degraded withdraw queue, suspected curator / allocator compromise, oracle stale / revert | `pauseAllocation`, `sendToVault`, confirm Morpho V2 bounded-partial actual receipt, dry-run or execute Strategy-specific emergency recovery, frontend / ops warning |
| Incident | Confirmed bad debt, share-price drop, impossible withdraw, gate-blocked exit, oracle exploit, curator takeover | Stop allocation, recover funds, when necessary use WRITEOFF_ROLE `forceDeallocateMorphoV2` (atomic pause + penalty/backing guards), decide backstop, `writeoffStrategyPrincipal`, buffer shortfall comms, post-mortem |

Confirmed loss that lowers `convertToAssets` is reflected downward in `estimatedTotalUnderlying()`;
unrecoverable residual principal then becomes a `writeoffStrategyPrincipal` candidate. In contrast,
a maxWithdraw drop or market liquidity shortage may be temporary and should not be immediately
written off.

The standard emergency sequence is:

1. Stop new allocation / cap ramp.
2. Read back Morpho role / queue / cap / market / oracle state.
3. Check `maxWithdraw` / `maxRedeem` and `convertToAssets` through fork / read-only calls.
4. If recoverable amount exists, execute `sendToVault` or Strategy-specific emergency recovery through Safe. Morpho V2 `sendToVault` performs bounded partial retries after a full-size failure, so read `SentToVault.actual` and re-plan the remainder.
5. If Morpho V2 needs penalty-bearing deallocation, high-quorum `WRITEOFF_ROLE` calls `CollateralVault.forceDeallocateMorphoV2`. Do not call the Strategy wrapper directly; freeze positive `_minReceived` and `_minBackingRatioAfter` from a dry-run. The same transaction pauses allocation / deposit / redeem / claim and recovers funds to the Vault. Insufficient actual receipt or backing reverts the penalty and recovery together.

   For an existing deployment, upgrade Vault and MorphoV2Strategy together in one shared-Timelock batch, without executing recovery between upgrades. An old Vault paired with the new Strategy may retain recovered assets in a fallback cache when live valuation fails. Receipt monitoring must include `ReceivedFromStrategy` emitted by this incident path.
6. After recovery, check Vault buffer, queued claims, SP / DEX liquidity, and liquidation safety.
7. Only confirmed residual loss goes through governance for writeoff and backstop release.
8. Update frontend / ops / public comms; reallocation requires post-mortem and a new activation package.

## Activation Evidence Package

A PR / issue that freezes Day-1 Morpho allocation must include at least:

- `morpho-vault-freeze.json` generated according to
  [`../runbooks/Morpho-Day1-Vault-Freeze-Package.md`](../../launch/gates/Morpho-Day1-Vault-Freeze-Package.md).
  Remaining `BLOCKER` findings are launch blockers
- adopted vault, chain, official source, code hash, proxy / implementation, version, audits / bug bounty
- Strategy kind, branch, underlying, cap, weight, and buffer / withdrawDelay impact
- `asset()`, `decimals()`, `convertToAssets`, `maxWithdraw`, `maxRedeem`, and normal / partial / emergency withdraw dry-runs
- vault roles, timelock, fee, pending actions, supply / withdraw queue, market cap, current exposure
- per-market loanToken, collateralToken, oracle, IRM, LLTV, utilization, available liquidity, bad debt
- residual risk for oracle / LLTV / IRM / curator / allocator / Public Allocator
- monitoring dashboard / alert / owner / backup owner / escalation path
- Safe / Timelock calldata, on-chain readback plan, rollback / pause / writeoff plan
- frontend / ops / deploy manifest / `mainnet-preflight` / Parameters diffs

## No-Go Conditions

Morpho allocation must not open if any of the following apply:

- `asset()!=branch underlying`
- official address source, code, implementation, role holder, or timelock cannot be frozen
- a vault registered through `ERC4626Strategy` cannot satisfy `maxWithdraw` / `maxRedeem` evidence
  (always-zero Vault V2-style designs must instead use the dedicated `MorphoV2Strategy` and satisfy
  the V2 Gate rows above)
- normal / partial / emergency withdraw dry-runs are missing
- curator / allocator / guardian / sentinel holders or pending actions are unknown
- fee, gate, registry, queue, or cap changes can unilaterally break Strategy exit
- markets depend on unsupported collateral, unverified oracle, bridge-only asset, illiquid collateral, or recursive share collateral
- there is no owner, Safe calldata, writeoff / backstop / comms process for depeg / exploit / bad debt

## Handling Unfinalized Values

This document sets the Morpho operation policy. Concrete vault address, market cap, Strategy cap,
weight, accepted fee, role holder addresses, and alert thresholds are finalized in the activation
package once the target vault and fork block are known, then reflected into `Parameters.md`, deploy
env, and preflight. Missing values must not be treated as Day-1 Morpho allocation being freeze-complete.

## References

- Morpho MetaMorpho repository: https://github.com/morpho-org/metamorpho
- Morpho Vault V2 repository: https://github.com/morpho-org/vault-v2
- Morpho Blue repository: https://github.com/morpho-org/morpho-blue
- Morpho Public Allocator repository: https://github.com/morpho-org/public-allocator
