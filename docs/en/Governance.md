# 🔑 JPY DeFi Governance Permissions Reference

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Active |
| Owner | DeltaForesight |
| Role of this document | Cross-cutting, role-first index answering **which privileged functions on which contracts each governance actor can call**. Component specs are authoritative for individual gates, [Parameters.md](./Parameters.md) for values, [Governance-Roles-Timelock.md](protocol/product/policies/Governance-Roles-Timelock.md) for rationale, and the relevant runbook for execution procedure. |
| Source-of-truth relationship | This index presents the GOV / FR requirements from component specs by role. It is not a separate source of truth for gates, effects, failure behavior, or values. If a conflict exists, correct the applicable spec and Parameters first, then update this index. |
| Off-chain approval | [Day-1 Governance Proposal & Execution Policy](../jp/protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) defines JIP approval, publication, execution, and readback; [Protocol Governance GitHub Operations](../jp/protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md) defines GitHub procedure. The existence of an on-chain permission does not authorize its use. |
| Code reconciliation target | `contracts/src` on the latest `develop` of `deltaforesight/jpydf-v2`. Canonical role names are the primary key. Re-grep functions and role definitions at the current head before use. |
| Cross-reference convention | Refer to roles by canonical name: GOV / WRITEOFF / GUARDIAN / ALLOCATOR / ORACLE-OWNER / BRIDGE-ADMIN / BRIDGE-MINTER. Avoid section-number references because sections may be renumbered. |

---

## 1. Purpose, Scope, and Non-Responsibilities

### 1.1 Scope and Non-Responsibilities

- **Covered here**: continuing governance actors and privileged entrypoints for the DF layer (CollateralVault / dToken / Strategy / Oracle / InterestRouter / PILAllocator), JpydfToken including its dormant bridge surface, the external GOV Timelock's internal PROPOSER / EXECUTOR / CANCELLER roles, and confirmation that 🔵 Core has no privileged actor.
- **Covered elsewhere**: contract-first interfaces, gates, effects, and failures (`spec/*.md`); permissionless operations ([Permissionless User Operations](protocol/product/spec/Permissionless-User-Operations.md)); timing rationale ([Governance-Roles-Timelock.md](protocol/product/policies/Governance-Roles-Timelock.md)); parameter values ([Parameters.md](./Parameters.md)); and Foundation corporate administration, the Foundation operating multisig, five Members / Exhibit A, and the MINS Category C reporting member ([Foundation docs](../jp/foundation/requirements/Foundation-Entity-Setup-Requirements.md)).

The Foundation operating multisig, Members, and Exhibit A belong to the RMI DAO LLC / Foundation corporate layer. They are distinct from the protocol Admin multisig, Guardian, Treasury, and Timelock holders. Do not treat a protocol Safe or signer address as a Foundation Exhibit A Member address.

### 1.2 Summary

**Core principle**: operations that can move funds out, dilute value, or recognize a write-down require delay or a high threshold; reversible fail-safe actions are immediate, while recovery is delayed. 🔵 Core borrowing, redemption, liquidation, Stability Pool, and redemption mechanics are immutable and permissionless and have no pause actor. GOV controls parameters only (`SYS-NFR-002`). [Governance-Roles-Timelock.md](protocol/product/policies/Governance-Roles-Timelock.md) is authoritative for the rationale.

Governance has three domains: (1) the DF protocol layer, centered on CollateralVault and its five roles plus contract owners and Oracle; (2) the GOV Timelock's internal PROPOSER / EXECUTOR / CANCELLER roles; and (3) JpydfToken's Core mint/burn and dormant bridge surface. Section 2 maps actors to holders; Section 3 is the role-first permission index.

A contract `owner` does not always identify the same holder. The GOV Timelock is external; PriceFeedProxy and bridge-minter delays are built into their respective contracts. Use the `PRM-GOV-*` and `PRM-BRIDGE-*` values in Parameters.

### 1.3 Operational Approval Gate

On-chain capability is not execution approval. [Day-1 Governance Proposal & Execution Policy](../jp/protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md) is authoritative for the JIP, publication, calldata reconciliation, and readback process.

---

## 2. Actor Mapping (canonical name ↔ role ↔ holder ↔ env)

The leftmost canonical name is the vocabulary used throughout this document and the primary key in Section 3.

| Canonical name | Code identity (role / owner) | Holder | Deploy env |
| --- | --- | --- | --- |
| **GOV** | Vault `GOV_ROLE` + `DEFAULT_ADMIN_ROLE`; DToken `owner`; Strategy `upgrader`; InterestRouter `owner`; PILAllocator `owner` | External Timelock | `DF_TIMELOCK` (= `DF_STRATEGY_UPGRADER`); PIL Phase A uses `DF_PILA_OWNER` |
| **WRITEOFF** | Vault `WRITEOFF_ROLE` | Admin multisig | `DF_WRITEOFF` |
| **GUARDIAN** | Vault `GUARDIAN_ROLE`; each Strategy `owner`; PILAllocator `guardian` | Guardian multisig | `DF_GUARDIAN` (= `DF_STRATEGY_OWNER`); PIL Phase A uses `DF_PILA_GUARDIAN` |
| **ALLOCATOR** | Vault `ALLOCATOR_ROLE` | Allocator holder; form and handover conditions are in [Allocator Signer Policy](../jp/protocol/launch/gates/Mainnet-Role-Assignment-Allocator-Signer-Policy.md) | `DF_ALLOCATOR` |
| **ORACLE-OWNER** | PriceFeedProxy `owner` | Admin multisig | `DF_PRICE_FEED_OWNER` |
| **BRIDGE-ADMIN** | JpydfToken `bridgeAdmin` | Admin multisig | `DF_BRIDGE_ADMIN` |
| **BRIDGE-MINTER** | Registered JpydfToken bridge minter (`bridgeMint` / `bridgeBurn`) | Registered address; none on Day-1 | On-chain |

**Internal roles of the external Timelock** (a separate level from the table above):

| Internal role | Holder | Responsibility | Repository env |
| --- | --- | --- | --- |
| **PROPOSER** | Admin multisig | Schedule delayed operations | None; configured on the external Timelock |
| **EXECUTOR** | Admin multisig | Execute after `minDelay` | None; configured on the external Timelock |
| **CANCELLER** | Admin multisig | Cancel a pending proposal | `DF_TIMELOCK_CANCELLER` in launch evidence; no contracts env |

See `PRM-GOV-*` in [Parameters.md](./Parameters.md) for final holder and delay values and [Governance-Roles-Timelock.md](protocol/product/policies/Governance-Roles-Timelock.md) for separation rationale.

**Actors without continuing governance authority**: JpydfToken `owner` self-renounces after deployment wiring. BO / AP / CR / TM / SP call JpydfToken Core `mint` / `burn`; Vault calls DToken `mint` / `burn`; Vault calls Strategy `deposit` / `writeoffPrincipal`; registered Strategies call Vault `receiveFromStrategy`. Concrete price feeds have no owner or setter. 🔵 Core and ordinary user operations are permissionless. The component specs are authoritative for these contract-first authorization conditions, so they are not duplicated in Section 3.

---

## 3. Role-First Permission Index

This section lists only function names and links to the normative requirements. Section 2 identifies holders, Parameters defines delay values, and the linked component spec defines each gate, effect, and failure mode. Disabled functions that always revert, such as `renounceOwnership`, are not listed as capabilities.

[Strategy Selection Policy](protocol/operations/policies/Strategy-Selection-Policy.md#adoption-classification) is authoritative for venue adoption. The LidoStrategy and EtherfiWeETHStrategy entries below are **archived**: those sources moved to `contracts/src/Strategies/archive/` on 2026-08-06 and have no deploy path, so no instance can be created. The entries are retained only to describe the recovery capabilities that would apply to a pre-existing instance if inventory ever finds one.

Each CollateralVault role holder can use OpenZeppelin AccessControl `renounceRole` to renounce only its own role. This is not privilege expansion, but it can leave the role unheld and is therefore covered by [VAULT-GOV-002](protocol/product/spec/CollateralVault.md#vault-gov-002).

### 3.1 GOV + DEFAULT_ADMIN

- **CollateralVault**: `_authorizeUpgrade`, `setUnderlying`, `setBufferConfig`, `setWithdrawDelay`, `setTreasury`, `setAllocatorConfig`, `setStrategyValuationMaxAge`, `addToWhitelist`, `addStrategy`, `updateStrategy`, `releaseBackstopToBuffer`, `invalidateStrategyValuationCache`, `unpauseDeposit`, `unpauseRedeem`, `unpauseClaim`, `unpauseAllocation`, `grantRole`, `revokeRole` — [VAULT-GOV-002](protocol/product/spec/CollateralVault.md#vault-gov-002)
- **DToken**: `setCap`, `setTokenInfo`, `setAllowedUnderlying`, `_authorizeUpgrade`, `transferOwnership`, `acceptOwnership` — [DTKN-GOV-004](protocol/product/spec/dToken.md#dtkn-gov-004-owner-timelock)
- **Strategies** (dedicated `upgrader`): `_authorizeUpgrade`, `setUpgrader` — [STGY-GOV-003](protocol/product/spec/strategies/Strategy.md#stgy-gov-003-upgrader-timelock)
- **InterestRouterForwarder**: `setRecipient`, `transferOwnership`, `acceptOwnership` — [IRTR-GOV-001](protocol/product/spec/InterestRouter.md)
- **PILAllocator**: `registerInitiative`, `unregisterInitiative`, `setWeights`, `unpause`, `setGuardian`, `transferOwnership`, `acceptOwnership` — [PILA-GOV-001](protocol/product/spec/PILAllocator.md)

### 3.2 WRITEOFF

- **CollateralVault**: `writeoffStrategyPrincipal`, `invalidateStrategyValuationCache` — [VAULT-GOV-002](protocol/product/spec/CollateralVault.md#vault-gov-002)
- **AsyncRequestStrategy** (Etherfi; Lido only when recovering an existing instance): `setPendingWithdrawalValuationBps` — [STGY-SEC-004](protocol/product/spec/strategies/Strategy.md#stgy-sec-004-conservative-accounting-against-aum-overstatement)

### 3.3 GUARDIAN

- **CollateralVault**: `pauseDeposit`, `pauseRedeem`, `pauseClaim`, `pauseAllocation`, `emergencyDisableStrategy`, `removeStrategy`, `removeFromWhitelist` — [VAULT-GOV-002](protocol/product/spec/CollateralVault.md#vault-gov-002)
- **All BaseStrategies**: `emergencyWithdraw`, `sweepRewardToken`, `claimMerklRewards`, `transferOwnership`, `acceptOwnership` — [STGY-GOV-002](protocol/product/spec/strategies/Strategy.md#stgy-gov-002-emergency-operations)
- **AaveV3Strategy**: `emergencyWithdrawFromAave`, `claimAaveRewards` — [AAVE-FR-006 / AAVE-FR-007](protocol/product/spec/strategies/AaveV3Strategy.md)
- **LidoStrategy** (archived; recovery of a pre-existing instance only, no deploy path): `emergencyWithdrawFromLido`, `setReferral` — [archived Lido Strategy spec](archive/LidoStrategy.md)
- **ERC4626Strategy**: `emergencyWithdrawFromERC4626` — [ERC-4626 Strategy spec](protocol/product/spec/strategies/ERC4626Strategy.md)
- **EtherfiWeETHStrategy** (archived; no deploy path): `emergencyWithdrawFromEtherfi`, `setReferral` — [archived Etherfi Strategy spec](archive/EtherfiWeETHStrategy.md)
- **SkyUsdcSUsdsStrategy**: `setMaxConversionLossBps`, `emergencyRedeemSUsdsToUsds`, `emergencyConvertIdleUsdsToVault`, `emergencyWithdrawFromSky` — [Sky Strategy spec](protocol/product/spec/strategies/SkySUsdsStrategy.md)
- **PILAllocator**: `pause` — [PILA-FR-008](protocol/product/spec/PILAllocator.md)

### 3.4 ALLOCATOR

- **CollateralVault**: `allocate`, `transferYieldToTreasury` — [VAULT-GOV-002](protocol/product/spec/CollateralVault.md#vault-gov-002)
- **All BaseStrategies**: `sendToVault`, `sendProfitToVault` — [STGY-FR-002 / STGY-FR-003](protocol/product/spec/strategies/Strategy.md)
- **LidoStrategy / EtherfiWeETHStrategy** (both archived; no deploy path, recovery of a pre-existing instance only): `requestLidoWithdrawal`, `requestEtherfiWithdrawal` — [archived Lido Strategy spec](archive/LidoStrategy.md) / [archived Etherfi Strategy spec](archive/EtherfiWeETHStrategy.md)

### 3.5 ORACLE-OWNER

- **PriceFeedProxy**: `proposeSource`, `confirmSource`, `confirmSourceEmergency`, `cancelSourceProposal`, `transferOwnership`, `acceptOwnership` — [ORCL-GOV-001 through ORCL-GOV-004](protocol/product/spec/Oracle.md#orcl-gov-001-owner-is-governance--multisig)

### 3.6 BRIDGE-ADMIN

- **JpydfToken**: `proposeBridgeMinter`, `confirmBridgeMinter`, `cancelBridgeMinterProposal`, `removeBridgeMinter`, `transferBridgeAdmin`, `acceptBridgeAdmin`, `renounceBridgeAdmin` — [CORE-BT-FR-014 / CORE-BT-FR-016](protocol/product/spec/JpydfToken.md)

### 3.7 BRIDGE-MINTER

- **JpydfToken**: `bridgeMint`, `bridgeBurn` — [CORE-BT-FR-015](protocol/product/spec/JpydfToken.md)

### 3.8 Internal Roles of the External Timelock

- **PROPOSER**: `schedule`, `scheduleBatch`
- **EXECUTOR**: `execute`, `executeBatch`
- **CANCELLER**: `cancel`

These are permissions of the external OpenZeppelin `TimelockController`, not DF component roles. [Mainnet Timelock Deploy Policy](../jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Policy.md) is authoritative for configuration; [Mainnet Timelock Deploy Runbook](../jp/protocol/launch/gates/Mainnet-Timelock-Deploy-Runbook.md) is authoritative for execution and readback.

---

## 4. 🟡 Day-2 Treasury / Reward Distributors — Not Implemented

`contracts/src` contains no `Treasury.sol`, `SPAdditionalRewardDistributor.sol`, or referral distributor. They are therefore excluded from the active permission index. [Treasury](protocol/roadmap/spec/Treasury.md) and [Reward Distributors](protocol/roadmap/spec/Reward-Distributors.md) are the Future Draft sources of truth for planned roles, functions, and gates. Add them to Section 3 only after implementation, audit, and activation gates are complete and reconciled against current code.

---

## 5. Sources and Source-of-Truth Relationships

- **Contract-first component requirements**: [CollateralVault](protocol/product/spec/CollateralVault.md), [dToken](protocol/product/spec/dToken.md), [Strategy](protocol/product/spec/strategies/Strategy.md) and each Strategy spec, [Oracle](protocol/product/spec/Oracle.md), [InterestRouter](protocol/product/spec/InterestRouter.md), [JpydfToken](protocol/product/spec/JpydfToken.md), and [PILAllocator](protocol/product/spec/PILAllocator.md).
- **Holder and delay values**: `PRM-GOV-*` / `PRM-BRIDGE-*` in [Parameters](./Parameters.md).
- **Timing-design rationale**: [Governance Roles & Timelock](protocol/product/policies/Governance-Roles-Timelock.md).
- **Off-chain approval and GitHub operations**: [Day-1 Governance Proposal & Execution Policy](../jp/protocol/launch/gates/Day-1-Governance-Proposal-Execution-Policy.md), [Protocol Governance GitHub Operations](../jp/protocol/operations/runbooks/Protocol-Governance-GitHub-Operations.md), and [JIP Template](../jp/protocol/operations/templates/JIP-Template.md).
- **System principles**: `SYS-NFR-002 / 003` in [Product Overview](protocol/product/Product-Overview.md).

This document is a **role → contract → privileged function** index spanning the normative specs and current implementation. Re-grep function names and role definitions at the latest `develop` head before using it; line numbers and surrounding code are fluid.
