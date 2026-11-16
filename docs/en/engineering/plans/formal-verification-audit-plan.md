# Formal Verification Audit Plan

## 0. Purpose

This document is a plan that defines, taking the current code on the `develop` branch as the premise, in what order the formal verification audit of JPYdf v2 will proceed. In formal verification, instead of running the program to look for errors, the code and external dependencies are treated as a mathematical model, and the properties that must hold for any input and any reachable state are proven. This plan separates dToken / CollateralVault / Strategy / Oracle / JpydfToken / Core integration, and progressively organizes the invariants and proof targets of each layer.

## 1. Scope

### 1.1 In scope

The targets of formal verification are the following areas that affect fund movement, supply, collateral value, and authority boundaries.

| Area | Main targets | Audit focus |
| --- | --- | --- |
| dToken | `DToken` | mint / burn authority, Underlying conversion, cap, token info binding |
| Vault | `CollateralVault` | deposit / redeem / claim, pending withdrawals, backstop reserve, backing ratio |
| Strategy | `BaseStrategy`, `AsyncRequestStrategy`, each Strategy implementation | principal accounting, push model, async request, valuation, emergency recovery |
| Oracle | `PriceFeedProxy`, `DFPriceFeedBase`, each PriceFeed | source switching, invalid price, JPY freeze, dToken backing multiplication |
| JPYdf token | `JpydfToken` | separation of the Core supply path and the dormant bridge-ready supply path |
| Core integration | The connection boundary with Liquity v2 Core | Core parity, dToken collateral, PriceFeedProxy, JPYdf supply path |

### 1.2 Out of scope

The following are not made direct proof targets of this plan.

- Full proof of external protocols themselves such as Aave / Lido / Sky / Etherfi
- Correctness of Chainlink or external rate providers themselves
- Completeness of UI / subgraph / off-chain bots
- Re-proving Liquity v2 Core in its entirety

External protocols and ERC20 are treated as abstract models limited to the interfaces and failure modes that Strategy / Vault depend on.

## 2. Source-of-truth materials

The source of truth for the specification and model boundaries is the following materials.

- `documents/jp/protocol/product/Product-Overview.md`
- `documents/jp/protocol/product/spec/*.md`
- `documents/jp/protocol/product/spec/strategies/*.md`
- `documents/jp/protocol/product/spec/Liquity-v2-Core-Spec.md`
- `contracts/src/Dependencies/Constants.sol`

In implementation PRs, the requirement IDs and invariants of the proof targets are cited from these materials and translated into specifications such as CVL.

The audit estimates under `documents/jp/engineering/guides/` and the collateral rationale in `documents/jp/engineering/historical-reviews/2026-07-27-Collateral-Parameter-Rationale.md` are read as reference materials as needed. However, they are not included in the source of truth that directly defines the formal-verification proof obligations.

## 3. Approach

### Phase 0: Model Boundary

First, fix the code under verification, the external dependencies, and the environment assumptions.

- External protocols are not fully proven; the return values, reverts, balance changes, and claimable states that Strategy depends on are abstracted.
- ERC20 is handled by separating the boundaries that Vault / Strategy assume: standard token, fee-on-transfer, transfer revert, no-return token, and so on.
- Core is not re-proven in its entirety; the connection boundaries with dToken collateral, PriceFeedProxy, and the JpydfToken supply path are handled.
- Proof specifications are added only after confirming that the implementation, the specification document, and the responsibility boundaries of the audit target are consistent.

### Phase 1: Supply / Authority

First, prove supply and authority, which have a small state space and large impact.

| ID | Target | Proof proposition |
| --- | --- | --- |
| FV-DTKN-001 | `DToken.mint` / `DToken.burn` | Anything other than `vault` cannot mint / burn |
| FV-DTKN-002 | `DToken.setTokenInfo` | token info can be set only once, and minting is impossible while it is unset |
| FV-DTKN-003 | `DToken.convertTo*` | round-trip conversion against the Underlying base unit is correct and does not cause silent rounding loss |
| FV-DTKN-004 | `DToken.mint` | minting in excess of the cap always reverts |
| FV-JPYDF-001 | `JpydfToken.mint` / `burn` / `bridgeMint` / `bridgeBurn` | the caller sets of the Core supply path and the bridge supply path do not intersect |
| FV-JPYDF-002 | bridge minter registry | bridge minters are only permitted contract addresses, and cannot also hold admin-type roles |
| FV-JPYDF-003 | bridge minter timelock | a minter addition cannot be finalized before the timelock elapses, and on removal the count decreases correctly |

The purpose of this phase is to enumerate all paths that can increase or decrease supply, and to prove first that the authority boundaries do not intersect.

### Phase 2: Vault Accounting

Next, prove the accounting of CollateralVault's assets, liabilities, and claims.

| ID | Target | Proof proposition |
| --- | --- | --- |
| FV-VAULT-001 | `deposit` | does not mint dToken in excess of the actually received amount `received` |
| FV-VAULT-002 | `redeem` / `redeemWithPermit` | does not silently burn dToken fractions. If exact conversion is impossible, it reverts before the burn |
| FV-VAULT-003 | `redeem` / `claim` | creating a request increases `pendingWithdrawals`, and a successful claim decreases it exactly once. A double claim is impossible |
| FV-VAULT-004 | `backstopDeposit` / `releaseBackstopToBuffer` | the protected backstop reserve does not become a source for redeem / claim / allocate / treasury until an explicit release |
| FV-VAULT-005 | `totalUnderlying` / `backingRatio` | Strategy value is evaluated conservatively, and `backingRatio <= 1e18` is maintained |
| FV-VAULT-006 | `addStrategy` | cannot be registered unless `strategy.underlying() == vault.underlying()` |
| FV-VAULT-007 | `allocate` | cannot send to a Strategy by eroding pending withdrawals, the buffer target, or the backstop reserve |
| FV-VAULT-008 | `writeoffStrategyPrincipal` | only a registered Strategy can be written off, and it does not succeed unless the backing ratio guard is satisfied after execution |

In this phase, beyond simple token balances, the liquid buffer, pending withdrawals, the protected backstop reserve, and the Strategy conservative value are handled separately.

### Phase 3: Strategy Family

Strategy is proven by separating the common base and the individual adapters.

| ID | Target | Proof proposition |
| --- | --- | --- |
| FV-STGY-001 | `BaseStrategy.deposit` | `onlyVault`. On a successful deposit, principal increases by exactly `_amount` |
| FV-STGY-002 | `BaseStrategy.sendToVault` | does not decrease principal beyond the amount actually received by the Vault, and does not underflow |
| FV-STGY-003 | `BaseStrategy.sendProfitToVault` | a yield-only push does not decrease principal |
| FV-STGY-004 | `BaseStrategy.emergencyWithdraw` | the destination is always the Vault, and it cannot send to an arbitrary address |
| FV-STGY-005 | `AsyncRequestStrategy` | the pending request amount and the set of request ids are not double-counted or double-claimed |
| FV-STGY-006 | `AaveV3Strategy` / `ERC4626Strategy` | even if the observed values of the external protocol move adversely, it does not over-value beyond its own tracked amount |
| FV-STGY-007 | `LidoStrategy` / `EtherfiWeETHStrategy` | the pending before async claim and the claimed idle underlying are not double-valued at the same time |
| FV-STGY-008 | `SkyUsdcSUsdsStrategy` | in the USDC -> USDS -> sUSDS conversion, state is not advanced if it falls below the min-out / max-loss guard |

In this phase, the correctness of external protocols is not over-assumed. Even in states where an external protocol is illiquid, reverts, returns a low recovery amount, or becomes claim-pending, it is proven that the Strategy-side principal / valuation / push accounting does not break down.

### Phase 4: Oracle / PriceFeed

For the Oracle, the focus is less on "returning a normal price" and more on "a broken source cannot cache / serve an invalid price."

| ID | Target | Proof proposition |
| --- | --- | --- |
| FV-ORCL-001 | `PriceFeedProxy.fetchPrice` / `fetchRedemptionPrice` | even if a source returns an invalid price / failure flag / revert, the invalid price is not stored to `_lastGoodPrice` |
| FV-ORCL-002 | `PriceFeedProxy.confirmSource` | the source cannot be changed before the timelock elapses. If the new source smoke test fails, the source does not change |
| FV-ORCL-003 | `PriceFeedProxy.confirmSourceEmergency` | emergency bypasses only the price-difference guard, and does not bypass the timelock or the smoke test |
| FV-ORCL-004 | `PriceFeedProxy` | on a successful source change, the normal cache is reinitialized from the new source; the normal-redemption cache is updated only with fresh JPY provenance, while an aged switch retains the prior cache but can return it only with `failure=true` |
| FV-ORCL-005 | `DFPriceFeedBase` | the freeze on a JPY/USD failure is bounded, and after the deadline is exceeded it is treated as a failure |
| FV-ORCL-006 | `DFPriceFeedBase._applyBackingRatio` | when `backingRatio <= 1e18`, the dToken price does not exceed the market price |

In this phase, the source's ABI mismatches, reverts, invalid sentinels, failure flags, and stale states are explicitly modeled.

### Phase 5: Core Integration

Finally, prove the connection boundary between Liquity v2 Core and the JPYdf-proprietary layer.

| ID | Target | Proof proposition |
| --- | --- | --- |
| FV-CORE-001 | `Liquity-v2-Core-Spec.md` `CORE-MOD-*` | do not mix anything beyond the documented modified surface into the proof scope |
| FV-CORE-002 | dToken collateral integration | Core treats dToken as an ordinary 18dec ERC20 collateral, and does not depend on the Vault's internal accounting |
| FV-CORE-003 | Oracle integration | Core's price source is fixed to `PriceFeedProxy`, and source swapping is closed within the Proxy |
| FV-CORE-004 | JpydfToken integration | the totalSupply changes of the Core supply path and the bridge supply path are separated per entrypoint |

In this phase, rather than re-proving all of Core's functionality, it is handled that Core parity and responsibility separation do not break down even when the outer layers are connected.

## 4. PR prioritization

The formal-verification implementation PRs are split small, in the following order.

1. Add the supply / authority specifications for dToken + JpydfToken
2. Add the source switching / invalid price specifications for PriceFeedProxy
3. Add the deposit / redeem / claim / backstop specifications for CollateralVault
4. Add the principal / request accounting specifications for BaseStrategy + AsyncRequestStrategy
5. Add the protocol models for the individual Strategies
6. Add the connection specifications for the Core integration / parity boundary

The reason for this order is to start the initial PRs from targets that have a small state space and few specification reinterpretations, and to split and handle targets with a large state space such as Vault / Strategy.

## 5. Not yet done

This document is a plan; the CVL specifications, harness, external-protocol models, and actual proof runs are not yet added.

In the next actual work, specifications and a harness will be added starting from Phase 1's `DToken` / `JpydfToken`.
