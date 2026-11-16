# JPY DeFi Architecture Decision Records

> Support translation. The Japanese source document
> [`documents/jp/protocol/product/architecture/Architecture-Decision-Records.md`](../../../../jp/protocol/product/architecture/Architecture-Decision-Records.md)
> is authoritative if this file conflicts with it.

| Field | Value |
| --- | --- |
| Domain | Protocol |
| Lifecycle | Evergreen |
| Artifact Type | Decision Record |
| Decision Authority | Protocol Governance |
| Maintainer | DeltaForesight |
| Visibility | Repository |
| Status | Active |
| Normative Source | This document for the choice and rationale recorded by `ADR-*`. Product and component Specs define current requirements |

## 1. Purpose

Record why the current JPYdf architecture was selected, the alternatives considered, and the consequences. This document does not redefine current functions, invariants, or constraints. The [Product Overview](../Product-Overview.md) and component Specs remain authoritative for requirements after a decision is adopted.

<a id="adr-001"></a>
## `ADR-001` Fork Liquity v2 with base parity

- **Context**: The value of a fork is inheriting an audited, production-tested Core. Modification resets that assurance and may break remote invariants.
- **Decision**: Treat Core base parity as the baseline and explicitly retain only the JPYdf canonical surface and cataloged `CORE-MOD-*` differences. Implement extensions as independent layers outside Core.
- **Alternatives**: Build a CDP from scratch or modify Core directly.
- **Consequences**: Extensions remain outside Core (`ARCH-001` / `ARCH-004`). Bridge minters are not added to existing Core `mint` / `burn` authorization; the bridge supply path uses the separate functions in `ADR-004`.

<a id="adr-002"></a>
## `ADR-002` Implement external collateral deployment through dToken and Strategy layers

- **Context**: Core assumes collateral remains inside the Protocol and uses 18 decimals.
- **Decision**: Place a dToken layer between Underlying and Core so that Core handles a claim token rather than the Underlying.
- **Alternatives**: Add an external-deployment hook to Core or handle a non-18-decimal asset directly.
- **Consequences**: dToken is the Core collateral, while custody, deployment, and monetization of Underlying stay outside Core.

<a id="adr-003"></a>
## `ADR-003` Use a push model for Strategies

- **Context**: A design in which the Vault pulls from a Strategy can become blocked precisely when an external venue has constrained liquidity or asynchronous withdrawal.
- **Decision**: A Strategy pushes funds to the Vault through `sendToVault` / `sendProfitToVault`; the Vault never pulls and receives through `receiveFromStrategy`.
- **Alternatives**: A Vault-initiated pull model.
- **Consequences**: Synchronous and asynchronous behavior stays inside the Strategy, and self-scaled balances separate donations.

<a id="adr-004"></a>
## `ADR-004` Separate bridge supply from Core and keep the token bridge-ready

- **Context**: Bridge minting and burning add new JpydfToken supply authority and widen the trust boundary. Conversely, freezing a token with no bridge capability would make a future expansion depend on token migration or an adapter lockbox.
- **Decision**:
  - Add a bridge-protocol-independent dormant extension to `JpydfToken`: a separate `bridgeAdmin`, delayed bridge-minter registry, `bridgeMint`, and self-burn `bridgeBurn`.
  - Restrict `bridgeAdmin` and bridge minters to contract addresses and prohibit the same address from holding both roles.
  - Do not add bridge-minter authorization to existing Core `mint` / `burn`.
- **Alternatives**: Freeze a bridge-incompatible token, bind the initial release to a particular bridge protocol, or let a minter burn from any address.
- **Consequences**: A canonical bridge can be considered without redeploying the token. This record does not fix the dormant or active state for a release. The [Bridge Minter Activation Gate](../../operations/runbooks/Bridge-Minter-Activation-Gate.md) separately approves registration, route opening, and cap ramp, while the Manifest and Evidence record actual state.

<a id="adr-005"></a>
## `ADR-005` Make the Oracle replaceable through PriceFeedProxy

- **Context**: Upstream directly references an immutable Oracle address, so a deprecated or failed feed and a changed collateral configuration cannot be handled by replacement.
- **Decision**: Place the fixed `PriceFeedProxy` reference in front of the source and make that source replaceable after a contract-enforced delay.
- **Alternatives**: Modify Core to replace the Oracle.
- **Consequences**: Source replacement completes without touching Core; price retrieval and JPY composition remain inside the proxy and PriceFeed.

<a id="adr-006"></a>
## `ADR-006` Behavior when dToken backing is impaired below 1

- **Context**: If a Strategy impairment makes dToken backing (`A` actually held divided by effective liability `L`) fall below 1, immediate downward collateral repricing raises liquidation risk. In addition, allowing 1:1 mint / redeem / claim during impairment lets an attacker buy impaired dToken cheaply, convert it first into finite buffer liquidity or a future full-value queue claim, and shift existing losses onto new deposit or backstop liquidity. A manual Guardian pause alone does not close the same-block race through detection, signing, and transaction inclusion. Under `ARCH-001`, the response must remain in the Vault extension layer without changing Core.
- **Decision**:
  - Reflect a confirmed loss in collateral value immediately; do not smooth or rate-limit the price.
  - Do not treat a temporary liquidity shortage as a loss.
  - Preserve nominal 1:1 mint / redeem / claim semantics, but allow Vault user flows **only when full backing is provable before execution**. `deposit` / `redeem` / `redeemWithPermit` / unsettled `claim` revert before changing token, permit, queue, or request state when cache-free confirmed assets `A_confirmed` are below effective liabilities `L_effective`.
  - `A_confirmed` includes the Vault raw balance and only available live `min(estimatedTotalUnderlying, principal)` values. An unreadable Strategy contributes zero; fresh cache cannot open a user flow. If other confirmed assets alone cover all `L_effective`, however, the flow safely remains open so a valuation outage does not become a permanent stop.
  - On an actual loss, use "automatic guard stops the bleed -> Strategy recovery / writeoff / backstop reserve restores backing -> automatic restart at 1:1." This automatic restart applies only to the guard; a pause flag explicitly set by Guardian remains set and still requires the existing GOV unpause. Keep Guardian pause as defense-in-depth for incident coordination and losses not yet visible to valuation.
  - For an incident whose loss is not yet visible in live valuation, submit `emergencyDisableStrategy(strategy)` as the first transaction, separate from loss realization. After inclusion, read back `enabled == false`, `weightBps == 0`, and all four deposit / redeem / claim / allocation pauses before recovery, force-deallocation, or writeoff. Use a private relay where available, but do not treat it as a cryptographic guarantee against queue preemption before pause inclusion. Pauses inside a loss-realization transaction roll back if that transaction reverts and do not replace the separately included pause.
  - Do not automate pro-rata allocation of a permanent loss; reserve it for Protocol Governance judgment.
  - Because the automatic guard cannot detect external loss absent from a Strategy's live valuation, retain conservative Strategy-specific guards, caps, monitoring, and manual incident rails.
- **Alternatives**: Price smoothing, always-on automatic pro-rata redemption, manual pause alone, or allowing fresh valuation cache in the user-flow guard.
- **Consequences**:
  - Add `VAULT-SEC-010` and combine it with `ORCL-FR-014`, `VAULT-FR-014` / `VAULT-FR-017`, and `writeoffStrategyPrincipal`.
  - Component Specs define Strategy-specific behavior, and [`SYS-RISK-002`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-002) checks it at launch.
  - The nominal redeem / queue race before pause inclusion and private relay non-guarantee remain residual risks requiring explicit risk-owner acceptance. Incident rehearsal must verify separate pause inclusion and readback, and that a later reverted loss transaction leaves the prior pause committed.
  - Mainnet activation remains No-Go until the Vault upgrade and integration/monitoring evidence are complete. Do not introduce a pro-rata/epoch queue.

<a id="adr-007"></a>
## `ADR-007` Do not prevent an upward peg deviation with a new automatic supply mechanism

- **Context**: Redemption creates nominal downward price pressure but does not guarantee a market-price floor, and no symmetric mechanism corrects an upward deviation (JPYdf > ¥1). A PSM-like supply mechanism would create a minting path outside Core and conflict with base parity and the supply-path trust boundary.
- **Decision**: The fast lever is additional borrowing and market supply through the existing Core path by any eligible borrower; the slower lever is a Protocol Governance cap ramp for additional dToken supply headroom. Calculate borrowing capacity from live collateral, debt, risk limits, and dToken `totalSupply / cap`, not from a plan value. Treat an APR change as a separate decision affecting borrowing cost and redemption priority, not as a supply action.
- **Alternatives**: Add a reserve-backed PSM outside Core or preemptively raise the cap by a large amount.
- **Consequences**: Accept a short-term premium as [`SYS-RISK-009`](../../launch/gates/Mainnet-Launch-Risk-Gate.md#sys-risk-009). Additional supply is constrained by borrower willingness, collateral, risk limits, and market liquidity; neither the Protocol nor a particular Contributor guarantees execution. If a Contributor elects to use its own balance sheet, its commitment, approval, and execution belong in Contributor-domain artifacts.
