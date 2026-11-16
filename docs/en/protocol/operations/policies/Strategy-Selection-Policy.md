# Strategy Selection Policy

## Positioning

This document defines how DeltaForesight selects, approves, monitors, and removes
external Strategy venues for CollateralVault Underlying.

Responsibilities are split as follows.

| Document | Responsibility |
| --- | --- |
| This document | Risk, governance, and monitoring criteria for approving an external venue |
| [`Collateral-Asset-Management-Policy.md`](Collateral-Asset-Management-Policy.md) | Day-1 branch configuration, candidate venues, and current adapter coverage |
| [`Morpho-Operation-Policy.md`](Morpho-Operation-Policy.md) | Morpho adoption gates for vaults, markets, roles, queues, oracle, and emergency operations |
| [`../../product/spec/strategies/Strategy.md`](../../product/spec/strategies/Strategy.md) | Shared Strategy contract requirements, push model, permissions, accounting, and invariants |
| [`../../../archive/LidoStrategy.md`](../../../archive/LidoStrategy.md) | **Archived** historical Lido requirements. Not active implementation or audit scope; retained because the source was covered by the `0c7766e0` audit |
| [`../../../archive/EtherfiWeETHStrategy.md`](../../../archive/EtherfiWeETHStrategy.md) | **Archived** historical Ether.fi weETH requirements. Not active implementation or audit scope; retained because the source was covered by the `0c7766e0` audit |
| [`../../Parameters.md`](../../../Parameters.md) | Final values for branch caps, buffers, withdraw delays, Strategy caps, and weights |

The key boundary is that **being technically expressible through an existing adapter does not mean
the venue is approved for allocation**. For example, even if a Morpho / EulerEarn ERC-4626 vault
has `asset()==underlying`, it must still pass this selection gate, activation evidence,
continuous monitoring, and incident runbook requirements before public exposure or mainnet allocation.

## Day-1 Policy

Day-1 borrowable branches are Branch 0 dwstETH and Branch 1 dUSDC. dwstETH uses the Aave V3 wstETH slot (aEthwstETH) as its only Day-1 Strategy (`DF_STRATEGY_COUNT_0=1` / `DF_STRATEGY_KIND_0_0=aave`); native wstETH staking appreciation remains borrower collateral value, and Day-1 `allocateMaxMove` follows Parameters. dUSDC uses synchronous-recovery Aave V3 as the required baseline plus the Morpho Vault V2 slot (`morpho-v2`).

Branches 2–7 (dETH / dUSD-A / dBTC / dUSD-B / dJPY / dJGB) are inert with no bound Underlying. They start with empty `strategies[]` and zero weight, cap, and `allocateMaxMove`; no Strategy is deployed, registered, or allocated for them.

Morpho allocation opens only after a specific-vault Go decision and the evidence gate in this policy. Adapter support alone does not open mainnet allocation; a cap-0 branch has no allocation surface while its cap stays zero.

The Day-1 manifest fail-closes on the approved Strategy sets (Branch 0 aave only, Branch 1 aave + morpho-v2) and empty `strategies[]` for Branches 2–7.

## Adoption Classes

| Class | Meaning | Required action |
| --- | --- | --- |
| Approved active | Current mainnet launch / production allocation target | Confirm Parameters / deploy env / preflight / runbook / monitoring alignment |
| Conditional approved | Technically supported, but inactive until activation evidence is complete | Prepare an activation package satisfying this policy |
| Candidate | Research candidate. Adapter fit, risk evidence, or ops readiness is still missing | Do not use for adoption decisions; keep in research issues / docs |
| Rejected / backlog | Not a Day-1 or near-term adoption target | Record the reason and keep it out of public exposure / deploy env |
| Archived (previously audited) | Existing implementation is not reused; it is moved to the archive tree and preserved as an audited artifact, out of active scope | Close its remaining surface under component-specific retirement requirements |

Current classification (canonical for adoption status):

| Venue / branch | Class | Reason |
| --- | --- | --- |
| Aave V3 wstETH / dwstETH | Approved active | Synchronous recovery, existing Strategy (aEthwstETH), Day-1 required Branch 0 set |
| Aave V3 USDC / dUSDC | Approved active | Synchronous recovery, existing Strategy, mainnet preflight / launch evidence target |
| Morpho ERC-4626 for dUSDC | Conditional approved | allocation opens only after a specific-vault Go decision and frozen vault/curator/market/oracle/bad-debt evidence |
| Morpho Vault V2 / dUSDC | Conditional approved via dedicated `MorphoV2Strategy` | Not eligible via `ERC4626Strategy` (max\* views are zero by design); the dedicated `MorphoV2Strategy` (kind `morpho-v2`) removes that blocker. Allocation opens only after the activation package (V2 gate rows in `Morpho-Operation-Policy.md`) and external audit complete. Day-1 mapping is branch 1 USDC; branch 0 (wstETH) is deferred until a credible wstETH-denominated V2 vault exists |
| EulerEarn / other ERC-4626 | Conditional approved | Deposit/withdraw adapter fit can be evaluated with the existing `ERC4626Strategy`, but this is outside the expected Day-1 scope. A vault with pull-based native rewards such as Euler Reward Streams is No-Go until evidence proves the reward path is disabled or a venue-specific claim implementation and additional audit are complete |
| Lido for dETH | **Retired, source archived** | The `LidoStrategy` source moved to `contracts/src/Strategies/archive/` on 2026-08-06. Its underlying is structurally WETH; PR #1424 removed the deploy selector entry that bound it (no `lido` strategy kind, venue struct, helper, or env key remains), and branch 0's underlying is now wstETH, so no branch can supply one. Do not deploy, register, or allocate. The archived source was covered by the external audit completed 2026-08-05 (`0c7766e0`) and is retained for that reason, not as a reactivation candidate. Reactivation requires re-entry into the deploy selector plus a fresh activation package and audit-scope change |
| Etherfi for dETH | **Retired, source archived** | `EtherfiWeETHStrategy` and `WeETHWithdrawAdapter` moved to `contracts/src/Strategies/archive/` on 2026-08-06 for the same reason: a WETH underlying is no longer reachable and the deploy surface was removed in PR #1424. Covered by the `0c7766e0` audit; retained as a historical artifact. Any future LRT venue is a new proposal requiring an async request / NFT / LRT risk package |
| Sky USDC -> USDS -> sUSDS | Conditional approved / backlog | Implemented, but not in the expected Day-1 scope. Requires converter / route halt / min-out / partnership / activation evidence |
| Additional dwstETH external Strategy | Candidate / Day-2 | beyond the Day-1 Aave slot, native appreciation remains collateral value. Leveraged-loop or Ride-on designs require separate due diligence, specification, implementation, and audit |
| inert-slot external Strategy | Candidate / activation-specific | evaluate with exact-Underlying approval, binding, and additional-audit decision |

## Adoption Flow

1. **Classify** whether the change is a new venue, a cap / weight / branch change for an approved venue, or a different vault through an existing adapter.
2. **Check adapter fit** under `Strategy.md` and `Collateral-Asset-Management-Policy.md`: existing Strategy kind or new Strategy.
3. **Check hard requirements**. Any failure excludes the venue from production allocation.
4. **Run risk review** with evidence per evaluation dimension and sign-off from risk, contracts, and ops owners.
5. **Prepare activation package** connecting Parameters, deploy env, preflight, runbooks, frontend / ops display, monitoring, and audit scope.
6. **Execute governance** through Safe / Timelock bundle and on-chain readback evidence for mainnet changes.
7. **Enable post-activation monitoring** and reassessment triggers.

## Hard Requirements

| Item | Requirement |
| --- | --- |
| Chain / venue | Direct Ethereum mainnet venue. Day-1 Strategies must not depend on an external bridge or another chain |
| Contract address | Official source, contract address, implementation, proxy admin, and upgrade path can be frozen |
| Underlying accounting | Strategy can conservatively value in Vault underlying terms and push-recover the same underlying |
| Adapter fit | `strategy.underlying() == vault.underlying()`. Asset-transforming routes require a dedicated Strategy spec / tests / audit |
| Withdraw path | Normal and incident withdrawal / redeem / claim / queue paths are explainable. Temporary illiquidity and confirmed loss are separated |
| Valuation | `estimatedTotalUnderlying()` does not overvalue. External share price / exchange rate / oracle / quote trust boundaries are clear |
| Governance risk | Venue admin / upgrader / guardian / pause / blacklist / fee-setter holders and timelock / multisig structure are known |
| Oracle / market risk | Price source, conversion route, bad debt, depeg, slashing, reserve deficit, and related monitors are defined |
| Emergency controls | Owners and runbooks exist for `pauseAllocation`, `sendToVault`, protocol-specific emergency withdraw, writeoff, and backstop |
| Reward path | Claim, forfeit/expiry, Underlying/Treasury settlement, and protected-token rejection are defined for every enabled incentive/reward distributor. If the current adapter cannot invoke a pull claim, allocation remains disabled until evidence proves the path is off or a venue-specific implementation, unit/fork tests, and additional audit are complete |
| Audit scope | New adapters or asset-transforming routes enter Day-1 audit scope. Existing-adapter new vaults still require fork evidence and config review |

## Evaluation Dimensions

| Dimension | Review items |
| --- | --- |
| Protocol maturity | Mainnet age, TVL, usage, incident history, and response history |
| Smart-contract risk | Audits, bug bounty, upgradeability, proxy admin, timelock, dangerous privileged functions |
| Governance / admin risk | Owner / guardian / emergency admin holder, threshold, timelock, pause / freeze / blacklist permissions |
| Asset / counterparty risk | Underlying issuer, redeemability, depeg, slashing, reserve deficit, custody / bridge dependency |
| Oracle / valuation risk | Chainlink / TWAP / share price / exchange rate / converter quote and stale / paused / manipulated quote handling |
| Liquidity / exit risk | `maxWithdraw`, reserve liquidity, queue finalization, withdrawDelay alignment, stress partial recovery |
| Accounting fit | Whether principal / yield / pending / idle / reward token / donation residue fit existing Strategy accounting |
| Operational readiness | Preflight, monitoring, alerts, keeper, explicit emergency actions, Safe calldata / runbook, incident owner |
| User / frontend impact | Borrowable branch gates, public exposure copy, risk disclosure, ops dashboard data sources |

## Evidence Package

An adoption or cap / weight increase PR / issue must include at least:

- venue name, chain, official address source, contract address, proxy / implementation / admin data
- adopted Strategy kind, branch, underlying, cap, weight, and buffer / withdrawDelay impact
- fork readback for `asset()` / `underlying()` / `decimals()` / `convertToAssets` / `maxWithdraw` / reserve status
- normal deposit / withdraw / partial withdraw / emergency withdraw / pause / writeoff dry-runs
- oracle / quote / share price / exchange rate source and stale / failure handling
- incentive/reward distributor type, enabled state, claim/forfeit/expiry, recipient, and Underlying/Treasury settlement dry-run
- privileged holder / timelock / pause / upgrade / fee / blacklist permission inventory
- monitoring metrics, alert thresholds, owner / backup owner, and incident runbook
- frontend / ops / launch gate / deploy manifest / Parameters diffs
- residual risks and rejected alternatives

## Continuous Monitoring and Reassessment

Approved active venues are not permanent. Immediately reassess and consider cap / weight reduction,
allocation pause, emergency withdraw, writeoff, or branch cap-ramp stop when any of the following occur:

- external protocol upgrade, admin holder change, or timelock change
- reserve pause / freeze, withdrawal queue stall, or sharp `maxWithdraw` drop
- oracle stale condition, abnormal share price, abnormal exchange rate, or converter halt
- depeg, slashing, bad debt, reserve deficit, bridge / custody incident
- sharp TVL / liquidity decrease, utilization spike, or withdrawal-cost increase
- divergence between Strategy `estimatedTotalUnderlying` and actual recoverable amount
- suspected stale frontend / ops / bot config

Normal reviews should run at least quarterly, with a full review of the adoption basis once per year.
Major incidents or governance changes trigger reassessment without waiting for the review cycle.

## Governance / Approval

| Role | Responsibility |
| --- | --- |
| proposer | Submit venue candidate, adoption purpose, cap / weight, expected yield, and alternatives |
| risk owner | Review hard requirements, evaluation dimensions, residual risk, and cap / weight sizing |
| contracts owner | Review adapter fit, storage / upgrade risk, preflight / fork evidence, and audit scope |
| ops owner | Review monitoring, keeper, Safe calldata, incident / withdrawal runbook |
| governance owner | Approve Safe / Timelock bundle, role assignment, and on-chain readback evidence |

Even for venues in the Day-1 planned active set, do not open allocation through only a deploy-env
change or Safe transaction. Complete the activation package and on-chain readback evidence. Adding a
venue outside the planned active set before Day-1 is an audit-scope change.

## Morpho / ERC-4626

Morpho / EulerEarn-style venues fit `ERC4626Strategy` if the adopted vault is a standard
ERC-4626 vault with `asset()==underlying`. This is an **adapter-fit** conclusion, not a
venue-selection conclusion. In the expected Day-1 scope, Morpho `erc4626` adoption targets
branch 1 `dUSDC` only; any other ERC-4626 venue / branch adoption is a separate scope change.

If Morpho is adopted, this policy must be supplemented by
[`Morpho-Operation-Policy.md`](Morpho-Operation-Policy.md) for curator, market selection, oracle,
LLTV, bad debt, supply / withdraw queue, role design, and emergency / writeoff linkage. Running a
DeltaForesight-curated vault has a larger governance / ops / monitoring scope than supplying to a
third-party curated vault and must use a separate activation package.

Morpho Vault V2 exposes an ERC-4626 interface, but its official implementation returns zero for
`maxWithdraw` / `maxRedeem`. The current `ERC4626Strategy` uses those functions as recovery limits,
so Vault V2 is **not eligible via `ERC4626Strategy`**. Vault V2 adoption goes through the dedicated
[`MorphoV2Strategy`](../../product/spec/strategies/MorphoV2Strategy.md) (kind `morpho-v2`), which
never consults the max\* views and has its own recovery / emergency model; venue gates and evidence
fields live in [`Morpho-Operation-Policy.md`](Morpho-Operation-Policy.md). Day-1 mapping: branch 1
`dUSDC` only; branch 0 (`dwstETH`) is deferred until a credible wstETH-denominated V2 vault exists.

## Non-Responsibilities

- This document does not redefine Strategy contract functions. Contract requirements live in
  `Strategy.md` and child documents.
- This document does not set branch risk parameter values. Values live in `Parameters.md`.
- This document does not approve a new venue by itself. Adoption requires an issue, PR, evidence,
  and governance execution.
