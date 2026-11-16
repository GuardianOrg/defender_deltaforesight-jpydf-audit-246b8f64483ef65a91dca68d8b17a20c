# 🟡 Multichain Requirements Definition

> **Status: Deprecated / Out of Scope**
>
> Current jpydf-v2 requirements do not support multichain. The target is Ethereum mainnet as a single chain only; bridge mint/burn, `bridgeAdmin`, bridge minter, issuance on other chains, and full protocol deployment on other chains are not implemented. This document is historical material from prior analysis and is not the source of truth for implementation, audit, or acceptance criteria. For current sources of truth, see [Product-Overview](../protocol/product/Product-Overview.md) and each component spec.

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Deprecated / Out of Scope (historical material; not implemented in current jpydf-v2) |
| Owner | DeltaForesight |
| Target contracts | none (the old analysis assumed an additive extension to `contracts/src/BoldToken.sol`, but current requirements do not adopt it) |
| Related documents | [Product-Overview](../protocol/product/Product-Overview.md) (source of truth for current scope) / [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md) (🔵 Core mint/burn and owner renounce behavior) / [Parameters](../Parameters.md) (source of truth for collateral and risk parameters) |

> `MCHN-*` IDs are retained for historical preservation, but must not be reused. Current PRs must not reference `MCHN-*` as implementation or audit targets.
> **Markers**: 🔵/🟡/🟢 in this document are classifications from the old analysis and do not indicate current scope.

---

## 1. Purpose, Scope, and Non-Responsibilities

This document defines requirements for a **Burn & Mint** model to circulate JPYdf (`BoldToken`) across multiple chains, and for a **bridge-agnostic extension** to `BoldToken` (mint/burn extension point independent of any specific bridge protocol) that supports it. Deployment proceeds in three stages: Day1 / Day2 / Day3.

- **Defined by this document**: bridge-agnostic extension to `BoldToken` (persistent `bridgeAdmin` role / bridge minter registry with propose-confirm 48h timelock / immediate remove / extended mint and burn permissions / 2-step admin transfer and renounce / `getCCIPAdmin()` shim / constructor invariants), plus its trust boundaries, staged transition (Day1→Day2→Day3, no migration), and pre-merge gates.
- **Not defined by this document (non-responsibilities / other documents / staged decisions)**:
  - 🔵 Liquity core mint/burn permissions, liquidation, owner renounce behavior → [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md)
  - Concrete specs of the adopted bridge protocol (CCIP / LayerZero, etc.), both-end wiring, and rate-limit implementation on bridge minter (pool) side → **finalized on Day2** ([MCHN-TBD-001](#mchn-tbd-001-bridge-protocol-selection-day2) / [MCHN-TBD-002](#mchn-tbd-002-rate-limit-details-day2))
  - Full protocol wiring method on other chains and procedure for connecting core to the Day2 token-only `BoldToken` → **finalized on Day3** ([MCHN-TBD-003](#mchn-tbd-003-other-chain-full-protocol-wiring-method-day3))
  - Final timelock and other parameter values → [Parameters](../Parameters.md)
- **Responsibility boundary (intentionally ignorant)**: `BoldToken` does not assume "which bridge is used" or "how much can be minted/burned per unit time"; it purely manages "**who is a trusted bridge minter**" and allows that minter to mint/burn. Rate limits and bridge-specific logic belong to the minter side ([MCHN-SEC-003](#mchn-sec-003-rate-limits-live-on-minter-side)).

---

## 2. Background and Design Policy

### 2.1 Liquity v2 / BOLD Assumes a Single Chain

Liquity v2's stablecoin BOLD (**JPYdf** for DeltaForesight) is designed for issuance on a single chain. In 🔵 Core, `BoldToken` mint / burn permissions are limited to Liquity v2 core contracts (mint ← BorrowerOperations / ActivePool, burn ← CollateralRegistry / BorrowerOperations / TroveManager / StabilityPool). This design has no concept of "mint / burn by a bridge," so JPYdf cannot be deployed to other chains as-is. Details of core mint/burn permissions are sourced from [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md).

### 2.2 "Same Token" Requirement for Multichain

The most important requirement when circulating JPYdf across multiple chains is **supply unity (being the same token)**. If separate "wrapped versions" proliferate on each chain, peg, accounting, and user experience are fragmented. The standard method to preserve supply unity is **Burn & Mint** (§3): burn JPYdf on one chain and mint the same amount on another chain, keeping total supply across all chains consistent without creating wrapped tokens.

What is needed is an extension point in `BoldToken` that lets a bridge mint / burn, **without depending on any specific bridge protocol (CCIP / LayerZero, etc.)**. That is the bridge-agnostic extension defined in this document (§6).

### 2.3 Design Policy (Why This Shape?)

- **Preserve core unmodified**: DeltaForesight's major principle is "Liquity v2 core logic remains unmodified in principle" ([Product-Overview](../protocol/product/Product-Overview.md) §5). Production modification for this extension is limited to **one file, `BoldToken.sol`** (additive state variables and functions), `BoldToken` remains **non-upgradeable**, and `CollateralRegistry` and all other 🔵 Core contracts remain unchanged ([MCHN-SEC-001](#mchn-sec-001-limit-modifications-to-additive-extension-of-one-file-boldtokensol)).
- **Avoid bridge lock-in**: baking CCIP / LayerZero-specific code into the token makes policy changes difficult. Making it bridge-agnostic allows changing adopted bridges or using multiple bridges only by replacing minters ([MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start) / [MCHN-FR-005](#mchn-fr-005-removebridgeminter-immediate-removal)).
- **Make `bridgeAdmin` a persistent role independent of owner**: Liquity v2 renounces owner after wiring is complete. If bridge admin were the same role as owner, minter registration/blocking would become impossible after renounce. Therefore `bridgeAdmin` is a persistent role in separate storage and separate from owner, allowing bridge operations after core wiring completes (MCHN-INV-001).
- **Finalize token on Day1 while deferring bridge selection to Day2**: Selecting CCIP / LayerZero, etc. takes time, while the Day1 token should be finalized and deployed early. The bridge-agnostic extension lets the **token design be finalized on Day1 while bridge selection remains deferred until Day2**. This is the central value of the design; no token redeploy is needed ([MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration)).
- **Oracle Layer-like timelock**: bridge minter addition uses the same propose/confirm pattern (48h) as Oracle Layer `PriceFeedProxy` source replacement (24h timelock) ([Oracle](../protocol/product/spec/Oracle.md)).

### 2.4 Overall Architecture (Day1 / Day2 / Day3)

Multichain deployment proceeds in three stages: Day1 / Day2 / Day3. The table and architecture diagrams below show each stage's configuration, market, and bridge-extension active state. Day2 is an intermediate phase where "**the protocol exists only on Ethereum; only the JPYdf token is bridged to other chains**." See [MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration) for staged transition procedure (no migration), and §12 for a quick view of active states.

| Item | **Day1** | **Day2** | **Day3** |
| --- | --- | --- | --- |
| Supported chains | Ethereum only | Ethereum + other chains | Ethereum + other chains |
| Protocol deployment | full protocol on Ethereum | **Ethereum only** (not deployed on other chains) | **full protocol also deployed on other chains** |
| Other-chain configuration | — | **`BoldToken` only (token-only)**. No Core / dToken / Oracle / Zapper | full protocol set (independent markets) |
| Markets on each chain | Ethereum only | **Ethereum only** (no borrowing, liquidation, or SP market on other chains) | each chain has an **independent borrowing, liquidation, and SP market** |
| JPYdf issuance (collateral) | Ethereum | **Ethereum only** | each chain |
| JPYdf circulation | Ethereum only | **to other chains by Burn & Mint** (other chains have bridge mint only) | cross-chain (same token) |
| bridge extension point | **installed** (dormant, §6) | **activated** (bridge minter registered) | active (all chains) |
| bridge minter | **unregistered (dormant)** | registered on Ethereum + other-chain `BoldToken` | registered on every chain's `BoldToken` |
| Bridge selection (CCIP / LZ, etc.) | **unselected** | **selected on Day2** (required to start operation) | continue using Day2 selection |
| Token redeploy | — | **not needed** (added to Day1 token on Ethereum) | **not needed** (reuse Day2 token on other chains) |

**Day1 (Ethereum only; bridge extension point dormant)**

```plain text
┌──────────────────────── Ethereum ────────────────────────┐
│ 🔵 Liquity v2 Core (IMMUTABLE)                            │
│   BorrowerOperations │ TroveManager │ StabilityPool        │
│   CollateralRegistry │ ActivePool   │ Redemption           │
│        │ mint/burn                                         │
│        ▼                                                   │
│ 🟡 BoldToken (JPYdf)                                       │
│   ├─ core mint/burn (BO/AP/CR/TM/SP)          ← active      │
│   └─ bridgeAdmin role + bridge minter registry ← dormant    │
│        (no bridge minter registered = mint/burn extension inactive) │
│                                                            │
│ 🟢 dToken Layer / 🟢 Oracle Layer / 🟢 Zapper             │
└────────────────────────────────────────────────────────────┘
```

On Day1, no bridge minter is registered, so the `BoldToken` mint/burn extension is effectively inactive and behavior is the same as single-chain Liquity v2.

**Day2 (Ethereum-only issuance; other chains are token-only; token-only bridge)**

```plain text
┌──────────── Ethereum ────────────┐     ┌─── Other chain (L2, etc.): token-only ───┐
│ 🔵 Liquity v2 full set            │     │ (No Core / dToken / Oracle / Zapper)     │
│ 🟢 dToken / Oracle / Zapper       │     │                                          │
│ 🟡 BoldToken_ETH                  │     │ 🟡 BoldToken_L2 (token-only)             │
│    └─ bridge minter registered ●  │     │    └─ bridge minter registered ●         │
└───────────────┬───────────────────┘     └──────────────┬───────────────────────────┘
                │  burn / mint                            │  mint / burn
                └─────────▶ Bridge (CCIP / LZ, etc.; selected on Day2) ─┘
                      (issued on Ethereum → Burn & Mint to other chains)

  Issuance (collateral): Ethereum only (no borrowing/liquidation/SP market on other chains)
  JPYdf:                 circulates to other chains by Burn & Mint (same token, bridge-derived only)
```

On Day2, only `BoldToken` is placed on other chains, making them "**bridge-receive-only**" for JPYdf from Ethereum. All JPYdf supply on other chains is bridge-derived from Ethereum, and all trove debt is concentrated on Ethereum ([MCHN-FR-012](#mchn-fr-012-supply-consistency-local-divergence-global-invariant)). Other-chain `BoldToken` also has the same bridge-agnostic extension (§6) as Ethereum, and has its own chain-local `bridgeAdmin` and bridge minter registry.

**Day3 (full protocol on multiple chains; independent issuance on each chain)**

```plain text
┌──────────── Ethereum ────────────┐        ┌──────────── Other chain (L2, etc.) ────────────┐
│ 🔵 Liquity v2 full set            │        │ 🔵 Liquity v2 full set                          │
│ 🟢 dToken / Oracle / Zapper       │        │ 🟢 dToken / Oracle / Zapper                     │
│ 🟡 BoldToken_ETH                  │        │ 🟡 BoldToken_L2                                 │
│    └─ bridge minter registered ●  │        │    └─ bridge minter registered ●                │
└───────────────┬───────────────────┘        └───────────────┬───────────────────────────────┘
                │  burn(user, N)                              │  mint(user, N)
                └──────────────▶  Bridge (CCIP / LZ, etc.; selected on Day2) ─┘
                          (burn on source → mint on destination)

  Each chain: independent borrowing, liquidation, and SP market (collateral is local)
  JPYdf:      single token across all chains through Burn & Mint
```

On Day3, the Day2 token-only `BoldToken` is reused and the full protocol is wired around it ([MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration)). Each chain's `BoldToken` is independently deployed (Ethereum on Day1, other chains on Day2), each with its own `bridgeAdmin` and bridge minter registry. Every chain has the same bridge-agnostic extension (§6).

---

## 3. Terminology, External Dependencies, and Assumptions

**Terminology**

| Term | Meaning |
| --- | --- |
| JPYdf | DeltaForesight stablecoin. The implementation token contract is `BoldToken` (fork of Liquity v2 BOLD) |
| Burn & Mint | Method that burns on source and mints the same amount on destination, circulating a single token cross-chain without creating wrapped versions (comparison table in §3 body) |
| Lock & Mint | Method that locks on source and mints a wrapped version on destination (comparison target; not adopted) |
| bridge minter | Bridge-side contract (pool) registered on each chain's `BoldToken` and executing burn/mint |
| `bridgeAdmin` | Persistent role that registers/removes bridge minters. Independent of Ownable. Must be a Safe multisig |
| token-only | Configuration with only `BoldToken` on another chain, without Core / dToken / Oracle / Zapper (Day2) |
| full protocol | Full deployment of Liquity v2 set (Core) + 🟢 original layers (dToken / Oracle / Zapper) |
| canonical token | Original token, not a wrapped version. Under Burn & Mint, every chain can issue the same canonical token as an equal peer |
| supply unity | Total JPYdf supply across all chains is consistent, and JPYdf on each chain is the same token |

**External dependencies (trusted externals)**

- **Adopted bridge protocol (selected on Day2, not decided)** — Chainlink CCIP / LayerZero, etc. `BoldToken` does not import or reference it at all; on Day2 it connects the minter through `proposeBridgeMinter` ([MCHN-SEC-002](#mchn-sec-002-bridge-independent-do-not-import-specific-protocols)).
- **Registered bridge minter (pool)** — fully trusted bridge contract. It has strong authority to mint arbitrary amounts to arbitrary addresses / burn arbitrary amounts from arbitrary addresses (§4 and [MCHN-SEC-004](#mchn-sec-004-registered-minters-are-limited-to-fully-trusted-bridges)).
- **`bridgeAdmin` (Safe multisig)** — operator that registers/removes minters and transfers admin. Constructor enforces that it is a contract ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)).
- **OpenZeppelin `Ownable` / `Ownable2Step` (type)** — `bridgeAdmin` 2-step transfer follows the same procedure as `Ownable2Step` (independent implementation).

**Assumptions**

- 🔵 Core `setCollateralRegistry()` internally calls `_renounceOwnership()` after wiring completes and sets `owner` to `address(0)` (Liquity v2-derived behavior; [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md)). `bridgeAdmin` is separate storage, so it survives this renounce.
- Burn & Mint is **token movement**, not **debt (trove debt) movement** (§3 body "supply consistency").
- Collateral remains chain-local; only JPYdf crosses chains (§3 body "collateral is chain-local").

---

## 4. Actors, Roles, and Trust Boundaries

| Actor | Operations | Trust boundary |
| --- | --- | --- |
| **owner (GOV_MULTISIG)** | core wiring (`setCollateralRegistry`, etc.). Renounced when wiring completes | Strong authority from 🔵 Core. **Separate role** from `bridgeAdmin`. On Day2 token-only chains, owner is kept (Safe multisig) for Day3 core wiring and not renounced |
| **`bridgeAdmin` (Safe multisig)** | `proposeBridgeMinter` / `confirmBridgeMinter` / `cancelBridgeMinterProposal` / `removeBridgeMinter` / `transferBridgeAdmin` / `renounceBridgeAdmin` | Persistent role for bridge governance. Independent of owner and survives owner renounce. Constructor enforces "is a contract" and "different from owner" |
| **bridge minter (pool)** | `mint(account, amount)` / `burn(account, amount)` | **Fully trusted**. Can mint arbitrary amounts to arbitrary addresses / burn arbitrary amounts from arbitrary addresses. Same trust level as core (TroveManager / StabilityPool during liquidation). Rate limits are implemented on minter side |
| **pendingBridgeAdmin** | `acceptBridgeAdmin` | Candidate transferee. Transfer is incomplete until it calls accept |
| **Anyone (permissionless)** | `getCCIPAdmin()` (view) | No trust required (read-only shim) |

- **Authorization separation**: owner cannot register/remove bridge minters; `bridgeAdmin` cannot perform core wiring (mint/burn permission granting). Constructor enforces that the two are distinct addresses ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)).
- **Trust-boundary key point**: a registered bridge minter has strong authority (arbitrary mint/burn). Burn from arbitrary accounts is already an authority that core (TroveManager / StabilityPool during liquidation) has in Liquity v2, and bridge minter is placed at the same trust level. This is secured by careful registration with 48h timelock by Safe-multisig `bridgeAdmin` ([MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start) / [MCHN-FR-003](#mchn-fr-003-confirmbridgeminter-confirm-registration)).

---

## 5. Interface Specification

Normative interface (bridge-agnostic extension portion of `BoldToken`). Production modification is limited to additive additions to `BoldToken.sol`. Behavior is in §6 Functional Requirements; only visibility and summary are shown below (non-normative).

| Function / state | Visibility | Summary | Normative requirement |
| --- | --- | --- | --- |
| `constructor(address _owner, address _bridgeAdmin)` | — | bind owner + bridgeAdmin and enforce 3 invariants | MCHN-FR-009 |
| `bridgeAdmin` / `pendingBridgeAdmin` | public (state) | persistent admin role / 2-step transfer candidate | MCHN-FR-001 |
| `proposeBridgeMinter(address _minter)` | external (onlyBridgeAdmin) | minter proposal; start 48h timelock | MCHN-FR-002 |
| `confirmBridgeMinter()` | external (onlyBridgeAdmin) | confirm registration after timelock | MCHN-FR-003 |
| `cancelBridgeMinterProposal()` | external (onlyBridgeAdmin) | cancel proposal at any time | MCHN-FR-004 |
| `removeBridgeMinter(address _minter)` | external (onlyBridgeAdmin) | immediately remove registered minter (no timelock) | MCHN-FR-005 |
| `mint(address account, uint256 amount)` | external | core permission `||` registered minter | MCHN-FR-006 |
| `burn(address account, uint256 amount)` | external | core permission `||` registered minter | MCHN-FR-007 |
| `transferBridgeAdmin(address _newAdmin)` | external (onlyBridgeAdmin) | 2-step transfer Step 1 | MCHN-FR-008 |
| `acceptBridgeAdmin()` | external (pending only) | 2-step transfer Step 2 | MCHN-FR-008 |
| `renounceBridgeAdmin()` | external (onlyBridgeAdmin) | permanently renounce admin role | MCHN-FR-008 |
| `getCCIPAdmin() → address` | external view | self-registration shim returning `bridgeAdmin` | MCHN-FR-010 |
| `BRIDGE_MINTER_TIMELOCK` | public constant | 48 hours | MCHN-FR-002 |
| `bridgeMinterAddresses` / `proposedBridgeMinter` / `bridgeMinterProposedAt` | public (state) | registered minters / proposed minter / proposed timestamp | §7 |

---

## 6. Functional Requirements (FR)

### MCHN-FR-001: Persistent `bridgeAdmin` Role (Independent of Ownable)

- **Type**: Functional | **Source**: Product-Overview "bridge-agnostic extension" / continued bridge operations after core owner renounce
- **Signature**: `address public bridgeAdmin;` / `address public pendingBridgeAdmin;` (state variables; modifier `onlyBridgeAdmin`)
- **Purpose**: maintain a persistent role for bridge governance (minter registration/removal/admin transfer), **independent** of Ownable.
- **Authorization**: set in constructor ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)); transfer is 2-step ([MCHN-FR-008](#mchn-fr-008-2-step-admin-transfer--renounce)).
- **Preconditions (Checks)**: `onlyBridgeAdmin` functions require `msg.sender == bridgeAdmin`.
- **Behavior (Effects)**:
  1. `bridgeAdmin` is held as **separate storage and a separate role** from `owner`
  2. Even when 🔵 Core-derived `setCollateralRegistry()` calls `_renounceOwnership()` after wiring completion and sets `owner` to `address(0)`, `bridgeAdmin` **survives this renounce**
- **revert / early return**: non-admin calls to `onlyBridgeAdmin` functions → revert.
- **Emitted event**: on setting/transfer, MCHN-EVT-005 (`BridgeAdminTransferred`).
- **Design notes**: making it independent from owner allows continued bridge operations (minter registration/removal) after core wiring completes and owner is renounced. Tests must ensure `bridgeAdmin` survives owner renounce (MCHN-INV-001 and §13).
- **Verification**: unit (`bridgeAdmin` survives owner renounce), invariant=MCHN-INV-001.

### MCHN-FR-002: `proposeBridgeMinter` (Proposal → Timelock Start)

- **Type**: Functional | **Source**: Oracle PriceFeedProxy-like propose/confirm (48h)
- **Signature**: `proposeBridgeMinter(address _minter)` / `uint256 public constant BRIDGE_MINTER_TIMELOCK = 48 hours;`
- **Purpose**: start registration of a bridge minter (bridge-side contract executing burn/mint) as **Step 1** of a propose/confirm flow with a 48-hour timelock.
- **Authorization**: `onlyBridgeAdmin`.
- **Preconditions (Checks)**: `msg.sender == bridgeAdmin`. One proposal, one minter (same shape as `PriceFeedProxy` single `source` slot).
- **Behavior (Effects)**:
  1. Set `proposedBridgeMinter = _minter`, `bridgeMinterProposedAt = block.timestamp` (timelock start)
  2. If overwriting an existing proposal, emit cancellation event for the old proposal (MCHN-EVT-002), then set the new proposal
  3. Emit proposal event (MCHN-EVT-001)
- **revert / early return**: non-admin → revert.
- **Emitted event**: MCHN-EVT-001 (proposal) / MCHN-EVT-002 (old proposal cancellation) on overwrite.
- **Design notes**: value (timelock = 48h) is sourced from [Parameters](../Parameters.md). Same shape as Oracle 24h timelock, but bridge minter has even stronger arbitrary mint/burn authority, so the value is 48h.
- **Verification**: unit (proposal and overwrite), integration (timelock boundary with MCHN-FR-003).

### MCHN-FR-003: `confirmBridgeMinter` (Confirm Registration)

- **Type**: Functional | **Source**: Oracle PriceFeedProxy-like propose/confirm (48h)
- **Signature**: `confirmBridgeMinter()`
- **Purpose**: confirm-register the proposed bridge minter after timelock as **Step 2** of propose/confirm.
- **Authorization**: `onlyBridgeAdmin`.
- **Preconditions (Checks)**: `msg.sender == bridgeAdmin`; `block.timestamp >= bridgeMinterProposedAt + BRIDGE_MINTER_TIMELOCK`. Cannot confirm if proposal was canceled ([MCHN-FR-004](#mchn-fr-004-cancelbridgeminterproposal-cancel-proposal)).
- **Behavior (Effects)**:
  1. `bridgeMinterAddresses[proposedBridgeMinter] = true` (add to registered minters)
  2. Emit confirmation event (MCHN-EVT-003)
- **revert / early return**: non-admin → revert; `TIMELOCK` not elapsed → revert; confirm after cancellation → revert (no proposal).
- **Emitted event**: MCHN-EVT-003 (confirm registration).
- **Design notes**: timelock boundary must revert at `TIMELOCK - 1` and succeed exactly at `TIMELOCK` (§13 acceptance criteria). After confirmation, that minter can mint/burn ([MCHN-FR-006](#mchn-fr-006-mint-permission-extension) / [MCHN-FR-007](#mchn-fr-007-burn-permission-extension)).
- **Verification**: unit (timelock boundary and cannot confirm after cancellation), integration.

### MCHN-FR-004: `cancelBridgeMinterProposal` (Cancel Proposal)

- **Type**: Functional | **Source**: escape hatch for mistaken proposal or admin-key compromise
- **Signature**: `cancelBridgeMinterProposal()`
- **Purpose**: **cancel at any time** a proposed bridge minter (escape hatch before confirm).
- **Authorization**: `onlyBridgeAdmin`.
- **Preconditions (Checks)**: `msg.sender == bridgeAdmin`.
- **Behavior (Effects)**:
  1. Discard proposal (clear `proposedBridgeMinter`; cannot confirm afterward)
  2. Emit cancellation event (MCHN-EVT-002)
- **revert / early return**: non-admin → revert.
- **Emitted event**: MCHN-EVT-002 (proposal cancellation).
- **Design notes**: in a mistaken proposal or suspected admin-key compromise, the proposal can be invalidated without waiting for timelock expiry. After cancellation, [MCHN-FR-003](#mchn-fr-003-confirmbridgeminter-confirm-registration) cannot succeed.
- **Verification**: unit (cancel; cannot confirm after cancellation).

### MCHN-FR-005: `removeBridgeMinter` (Immediate Removal)

- **Type**: Functional | **Source**: asymmetric design (addition=delayed / removal=immediate) / incident response
- **Signature**: `removeBridgeMinter(address _minter) external onlyBridgeAdmin`
- **Purpose**: immediately block a registered bridge minter with **no timelock**. First incident-response tool for compromised minters.
- **Authorization**: `onlyBridgeAdmin`.
- **Preconditions (Checks)**: `msg.sender == bridgeAdmin`; `bridgeMinterAddresses[_minter] == true` (unregistered reverts).
- **Behavior (Effects)**:
  1. `bridgeMinterAddresses[_minter] = false` (unregister)
  2. Emit `BridgeMinterRemoved(_minter)` (MCHN-EVT-004)
- **revert / early return**: non-admin → revert; unregistered minter (`!bridgeMinterAddresses[_minter]`) → `"BoldToken: not a bridge minter"`.
- **Emitted event**: MCHN-EVT-004 (`BridgeMinterRemoved`).
- **Design notes**: **the asymmetric design is intentional**. Granting new authority waits 48h for caution ([MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start)), while compromised minters can be blocked immediately as emergency response ([MCHN-SEC-005](#mchn-sec-005-emergency-stop-immediate-blocking)).
- **Verification**: unit (immediacy, unregistered revert, removed minter mint/burn revert).

### MCHN-FR-006: mint Permission Extension

- **Type**: Functional | **Source**: §2 Burn & Mint (mint same token on destination)
- **Signature**: `mint(address account, uint256 amount)` (additively extend permission check `_requireCallerIsBOorAP()`)
- **Purpose**: add minter to existing core permission checks so a registered bridge minter can mint JPYdf on destination chain (mint side of Burn & Mint).
- **Authorization**: existing core authority (BorrowerOperations / ActivePool) **`||` registered bridge minter**.
- **Preconditions (Checks)**: `borrowerOperationsAddresses[msg.sender] || activePoolAddresses[msg.sender] || bridgeMinterAddresses[msg.sender]`.
- **Behavior (Effects)**:
  1. Existing core authority remains unchanged. **OR-add** `bridgeMinterAddresses[msg.sender]` to allowed condition
  2. Authorized caller mints `amount` to `account` (issue source-A JPYdf on destination)
- **revert / early return**: caller has none of the permissions above → `"BoldToken: Caller is not BO or AP or Bridge"`.
- **Emitted event**: ERC20 `Transfer` (mint, from=0).
- **Design notes**: **existing core permissions are unchanged**. Addition is only one OR term (additive, core no-modification policy). See §4 and [MCHN-SEC-004](#mchn-sec-004-registered-minters-are-limited-to-fully-trusted-bridges) for strength and boundary of this authority.
- **Verification**: unit (registered minter can mint; unregistered/removed reverts), invariant=MCHN-INV-003.

### MCHN-FR-007: burn Permission Extension

- **Type**: Functional | **Source**: §2 Burn & Mint (burn on source)
- **Signature**: `burn(address account, uint256 amount)` (additively extend permission check `_requireCallerIsCRorBOorTMorSP()`)
- **Purpose**: add minter to existing core permission checks so a registered bridge minter can burn JPYdf on source chain (burn side of Burn & Mint).
- **Authorization**: existing core authority (CollateralRegistry / BorrowerOperations / TroveManager / StabilityPool) **`||` registered bridge minter**.
- **Preconditions (Checks)**: `msg.sender == collateralRegistryAddress || borrowerOperationsAddresses[msg.sender] || troveManagerAddresses[msg.sender] || stabilityPoolAddresses[msg.sender] || bridgeMinterAddresses[msg.sender]`.
- **Behavior (Effects)**:
  1. Existing core authority remains unchanged. **OR-add** `bridgeMinterAddresses[msg.sender]` to allowed condition
  2. Authorized caller burns `amount` from `account` (destroy JPYdf on source)
- **revert / early return**: caller has none of the permissions above → `"BoldToken: Caller is neither CR nor BorrowerOperations nor TroveManager nor StabilityPool nor Bridge"`.
- **Emitted event**: ERC20 `Transfer` (burn, to=0).
- **Design notes**: burn from arbitrary accounts is an authority core already has in Liquity v2 (TroveManager / StabilityPool during liquidation). bridge minter is placed at the same trust level ([MCHN-SEC-004](#mchn-sec-004-registered-minters-are-limited-to-fully-trusted-bridges)).
- **Verification**: unit (registered minter can burn; unregistered/removed reverts), invariant=MCHN-INV-003.

### MCHN-FR-008: 2-Step Admin Transfer / Renounce

- **Type**: Functional | **Source**: `Ownable2Step`-like / Day N exit
- **Signature**: `transferBridgeAdmin(address _newAdmin)` / `acceptBridgeAdmin()` / `renounceBridgeAdmin()`
- **Purpose**: transfer `bridgeAdmin` role with 2-step flow (`Ownable2Step`-like), preventing authority loss from 1-step transfer to a wrong address. Also provide permanent role renounce (Day N exit).
- **Authorization**: `transferBridgeAdmin` / `renounceBridgeAdmin` are `onlyBridgeAdmin`. `acceptBridgeAdmin` requires `msg.sender == pendingBridgeAdmin`.
- **Preconditions (Checks)**:
  - `transferBridgeAdmin`: `msg.sender == bridgeAdmin`; `_newAdmin != address(0)` (**only these 2 checks. Contract-ness and "different from owner" invariants are not rechecked**)
  - `acceptBridgeAdmin`: `msg.sender == pendingBridgeAdmin`
  - `renounceBridgeAdmin`: `msg.sender == bridgeAdmin`
- **Behavior (Effects)**:
  1. `transferBridgeAdmin`: set `pendingBridgeAdmin = _newAdmin` (transfer incomplete)
  2. `acceptBridgeAdmin`: complete transfer (`bridgeAdmin = pendingBridgeAdmin`, clear pending)
  3. `renounceBridgeAdmin`: cancel pending proposal and set `bridgeAdmin = address(0)`. Afterward, all `onlyBridgeAdmin` functions are permanently disabled, and `getCCIPAdmin()` returns `address(0)`
- **revert / early return**: non-admin (transfer/renounce) → revert; `_newAdmin == address(0)` (transfer) → revert; `msg.sender != pendingBridgeAdmin` (accept) → revert.
- **Emitted event**: MCHN-EVT-005 (`BridgeAdminTransferred`).
- **Design notes**:
  - **Remove all minters before renounce**: `renounceBridgeAdmin()` cancels pending proposal but **does not clear confirmed `bridgeMinterAddresses`**. After renounce, existing registered minters can continue mint/burn, while the ability to block them with `removeBridgeMinter()` is **permanently lost**. → Day N exit must always execute "**remove all bridge minters → then renounce**" ([MCHN-GOV-002](#mchn-gov-002-day-n-exit-renounce-after-removing-all-minters)).
  - **Operationally ensure transferee is also Safe multisig**: constructor enforces `bridgeAdmin` is a contract and different from owner, but `transferBridgeAdmin` / `acceptBridgeAdmin` **do not recheck these invariants** (only `_newAdmin != address(0)`). Operational procedures and governance approval ensure transferee is a Safe multisig ([MCHN-GOV-003](#mchn-gov-003-operationally-ensure-admin-transferee-is-also-safe-multisig)).
- **Verification**: unit (only pending can accept, overwrite allowed, renounce disables all admin functions and cancels pending), manual (multisig assurance for transferee).

### MCHN-FR-009: Constructor Invariants

- **Type**: Functional | **Source**: admin key management / authorization separation
- **Signature**: `constructor(address _owner, address _bridgeAdmin) Ownable(_owner) ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME)`
- **Purpose**: bind owner and `bridgeAdmin` at deploy time, and enforce 3 invariants on `bridgeAdmin` (prevent misdeploy, EOA single-control, and non-separated authority).
- **Authorization**: deployment procedure (constructor). Deploy script `contracts/script/DeployLiquity2.s.sol` passes it through `BRIDGE_ADMIN` environment variable.
- **Preconditions (Checks)** (3 invariants; all required):
  - `_bridgeAdmin != address(0)` (nonzero)
  - `_bridgeAdmin.code.length > 0` (contract)
  - `_bridgeAdmin != _owner` (different from owner)
- **Behavior (Effects)**:
  1. Set `bridgeAdmin = _bridgeAdmin`
  2. Emit `BridgeAdminTransferred(address(0), _bridgeAdmin)` (MCHN-EVT-005)
- **revert / early return**: zero → `"BoldToken: zero bridgeAdmin"`; non-contract → `"BoldToken: bridgeAdmin must be a contract"`; same as owner → `"BoldToken: bridgeAdmin must differ from owner"`.
- **Emitted event**: MCHN-EVT-005 (`BridgeAdminTransferred`, from=0).

| Condition | Intent |
| --- | --- |
| nonzero | prevent misdeploy with no admin |
| contract (`code.length > 0`) | forbid EOA single-control and enforce **Safe multisig** or similar contract control |
| different from `owner` | separate core owner from bridge admin |

- **Design notes**: `bridgeAdmin` must be a **Safe multisig (or Safe + Timelock), not an EOA or deployer** (a contract controlled by a single EOA is insufficient). Constructor enforces only "is a contract"; Safe multisig configuration is guaranteed by pre-merge gates ([MCHN-GOV-001](#mchn-gov-001-bridgeadmin--owner-are-safe-multisigs) / [MCHN-GOV-004](#mchn-gov-004-pre-merge-gates-day2day3-operation-gates)).
- **Verification**: unit (zero / EOA / `owner==bridgeAdmin` revert), manual (deploy configuration review).

### MCHN-FR-010: `getCCIPAdmin()` Self-Registration Shim

- **Type**: Functional | **Source**: conventional interface name for external registry self-registration
- **Signature**: `getCCIPAdmin() external view returns (address)`
- **Purpose**: read-only shim that self-declares the token administrator. Returns `bridgeAdmin` as-is. Matches a **conventional interface name** for external registries to automatically detect "who administers this token."
- **Authorization**: none (external view, permissionless).
- **Preconditions (Checks)**: none.
- **Behavior (Effects)**:
  1. `return bridgeAdmin` (after renounce, returns `address(0)`)
- **revert / early return**: none.
- **Emitted event**: none (view).
- **Design notes**: this function name **does not imply adoption of a specific bridge protocol**. Some bridge methods may not reference this function. Whatever bridge is adopted on Day2, the token side only needs to provide this one view. After transfer, it follows `bridgeAdmin` (§13 acceptance criteria).
- **Verification**: unit (returns `bridgeAdmin`, follows after transfer, returns `address(0)` after renounce).

### MCHN-FR-011: Burn & Mint Cross-Chain Transfer Flow

- **Type**: Functional | **Source**: §2.2 supply unity / §3 Burn & Mint
- **Signature**: protocol-level flow combining `BoldToken_A.burn` / `BoldToken_B.mint` ([MCHN-FR-006](#mchn-fr-006-mint-permission-extension) / [MCHN-FR-007](#mchn-fr-007-burn-permission-extension) are components)
- **Purpose**: when moving JPYdf amount `N` from chain A to chain B, burn on source and mint the same amount on destination, circulating a single canonical token cross-chain without creating a wrapped version.
- **Authorization**: only bridge minters registered on each chain's `BoldToken` can execute burn / mint on source / destination ([MCHN-FR-006](#mchn-fr-006-mint-permission-extension) / [MCHN-FR-007](#mchn-fr-007-burn-permission-extension)).
- **Preconditions (Checks)**: executing minter is registered on each chain.
- **Behavior (Effects)**:
  1. source (A): registered bridge minter executes `BoldToken_A.burn(user, N)` → JPYdf supply on A −N
  2. Bridge transmits message
  3. destination (B): registered bridge minter executes `BoldToken_B.mint(user, N)` → JPYdf supply on B +N (user receives JPYdf N on B)

```plain text
   Chain A                          Bridge                     Chain B
─────────────────              ───────────────            ─────────────────
 user: JPYdf N
   │
   │ (1) transfer request to bridge
   ▼
 BoldToken_A.burn(user, N)  ──▶  detect burn                BoldToken_B.mint(user, N)
   │   * bridge minter executes                                ▲
   │     burn                                                   │
   ▼                            (2) message transmission ───────┘
 JPYdf supply on A −N                                      JPYdf supply on B +N
                                                           user: JPYdf N (on B)
```

- **revert / early return**: burn/mint by unregistered minter → permission revert in [MCHN-FR-006](#mchn-fr-006-mint-permission-extension) / [MCHN-FR-007](#mchn-fr-007-burn-permission-extension).
- **Emitted event**: ERC20 `Transfer` (A: burn to=0 / B: mint from=0).
- **Design notes**: because this is Burn & Mint, JPYdf on destination is **not a wrapped version, but the same canonical token** (§2.2, MCHN-INV-002). Collateral remains chain-local; only JPYdf crosses chains (MCHN-INV-004).

```plain text
Chain A: [dETH/dBTC... collateral] → [Liquity v2 full set] → JPYdf_A ┐
                                                                     ├─ cross-chain by Burn & Mint
Chain B: [dETH/dBTC... collateral] → [Liquity v2 full set] → JPYdf_B ┘
              ▲                                             ▲
        collateral is local                         JPYdf circulates as one token across all chains
```

- **Verification**: integration (bidirectional Burn & Mint), fork/testnet (testnet proof = §13 / [MCHN-GOV-004](#mchn-gov-004-pre-merge-gates-day2day3-operation-gates) G7).

### MCHN-FR-012: Supply Consistency (Local Divergence, Global Invariant)

- **Type**: Functional | **Source**: §3 supply consistency / cross-chain supply monitor
- **Signature**: accounting invariant verified by off-chain monitor; paired with MCHN-INV-005
- **Purpose**: guarantee the relationship of local divergence and global invariant that follows from Burn & Mint being **token movement**, not **debt (trove debt) movement**.
- **Authorization**: none (accounting property; monitored off-chain).
- **Preconditions (Checks)**: can aggregate `BoldToken.totalSupply()` and total trove debt across all chains.
- **Behavior (Effects)**:
  1. On each local chain, "JPYdf supply" and "trove debt" may diverge
  2. **Across all chains globally, `total JPYdf supply = total trove debt` is always maintained**

```javascript
Chain A:  trove debt = N,  JPYdf supply = 0   (borrowed amount moved to B)
Chain B:  trove debt = 0,  JPYdf supply = N   (JPYdf from A circulates)
────────────────────────────────────────────
Global: total trove debt = N  =  total JPYdf supply = N   ✅ matches
```

- **revert / early return**: none (invariant; violation detection is off-chain monitor → incident response).
- **Emitted event**: none (tracked by aggregating ERC20 `Transfer`).
- **Design notes**:
  - **Day2 is a special case of this general rule**: all trove debt is concentrated on Ethereum (no Troves on other chains), while JPYdf is distributed across Ethereum + other chains. In the formula above, A = Ethereum (only debt-holding chain), B = other chain (always debt 0, bridge-derived JPYdf only). On **Day3**, other chains can also hold debt, so each chain can be both A and B in the general form.
  - To close a trove on A, JPYdf must return to A (burn on B, mint on A). This is how Burn & Mint preserves peg and accounting soundness.
- **Verification**: integration (A↔B debt/supply divergence and global match), manual (cross-chain supply monitor design = MCHN-EVT-006 / [MCHN-GOV-004](#mchn-gov-004-pre-merge-gates-day2day3-operation-gates) G5).

### MCHN-FR-013: Staged Transition (No Migration)

- **Type**: Functional | **Source**: §2 three-stage rollout / no token redeploy
- **Signature**: deployment/wiring procedure. Add no new setter; only activate existing extension points
- **Purpose**: complete Day1 / Day2 / Day3 activation by only adding functionality to existing `BoldToken`, without token redeploy or user-balance migration.
- **Authorization**: Day2/Day3 activation uses `bridgeAdmin` (minter registration) / owner (Day3 core wiring).
- **Preconditions (Checks)**: bridge-agnostic extension (§6) is fully built into Day1. Day3 wiring assumes "Day2 token-only `BoldToken` still holds owner without renounce" ([MCHN-GOV-005](#mchn-gov-005-day2-token-only-chain-owner-is-kept-until-day3-wiring)).
- **Behavior (Effects)**:
  1. **Day1**: deploy `BoldToken`. All bridge-agnostic extensions are built in, but bridge minter unregistered = **inactive**. Behavior is identical to single-chain Liquity v2
  2. **Day2 (Ethereum)**: add bridge minter to the same Day1 `BoldToken` afterward (propose --48h--> confirm). No redeploy
  3. **Day2 (other chains)**: newly deploy token-only `BoldToken` (no Core / dToken / Oracle / Zapper). Owner is not renounced and remains Safe multisig. Register local bridge minter. After adopted bridge selection ([MCHN-TBD-001](#mchn-tbd-001-bridge-protocol-selection-day2)), wire both ends and prove on testnet → operate
  4. **Day3 (other chains)**: **reuse** Day2 token-only `BoldToken`, and wire Liquity v2 Core + 🟢 original layers around it. When wiring completes, `setCollateralRegistry()` renounces owner ([MCHN-FR-001](#mchn-fr-001-persistent-bridgeadmin-role-independent-of-ownable)). From then on, collateral can be deposited and JPYdf issued on that chain too
- **revert / early return**: none (procedure).
- **Emitted event**: events from corresponding FRs for each activation (minter registration = MCHN-EVT-003, etc.).
- **Design notes**:
  - **No token redeploy required**: Day2 (Ethereum) adds bridge minter to Day1 token; Day3 (other chains) wires core around Day2 token-only token. JPYdf balances already received by bridge, token addresses, and token identity are preserved. `bridgeAdmin` and bridge minter registry survive owner renounce ([MCHN-FR-001](#mchn-fr-001-persistent-bridgeadmin-role-independent-of-ownable)), so bridge operations are uninterrupted.
  - This is the maximum value of the design: "**place the extension point and token first, then activate later**."
- **Verification**: integration (Day1 inactive, Day2 activation, Day3 reuse wiring), fork/testnet.

---

## 7. State Variables and Accounting Model

| Variable | Type | Description | Finalized by |
| --- | --- | --- | --- |
| `bridgeAdmin` | `address` | persistent role for bridge governance. Independent of Ownable. Survives owner renounce | constructor / 2-step transfer |
| `pendingBridgeAdmin` | `address` | candidate for 2-step admin transfer | `transferBridgeAdmin` / cleared by `acceptBridgeAdmin` |
| `bridgeMinterAddresses` | `mapping(address => bool)` | registered bridge minters | `true` by `confirmBridgeMinter` / `false` by `removeBridgeMinter` |
| `proposedBridgeMinter` | `address` | proposed minter (only one) | `proposeBridgeMinter` / `cancel` / `confirm` |
| `bridgeMinterProposedAt` | `uint256` | proposal time (timelock start) | `proposeBridgeMinter` |
| `BRIDGE_MINTER_TIMELOCK` | `uint256 constant` | timelock for bridge minter addition (48 hours) | compile-time constant (value from [Parameters](../Parameters.md)) |

**Accounting model**: `BoldToken` itself has **no rate limit and no supply cap**. It only manages "**who is a trusted bridge minter**" (`bridgeMinterAddresses`) and "proposed minter + timelock." Supply accounting (global invariant `total JPYdf supply = total trove debt`) is preserved by the nature of Burn & Mint ([MCHN-FR-012](#mchn-fr-012-supply-consistency-local-divergence-global-invariant)), and an off-chain cross-chain monitor handles observation (MCHN-EVT-006). Rate limits (issuance/burn limits per unit time) belong to the bridge minter (pool) side and are not put into `BoldToken` ([MCHN-SEC-003](#mchn-sec-003-rate-limits-live-on-minter-side)).

```plain text
┌────────────────────────────────────────────────────────┐
│ BoldToken                                              │
│   - manages "who is a minter" (bridgeMinterAddresses)   │
│   - has no rate limit                                  │
└───────────────────────┬────────────────────────────────┘
                        │ mint/burn
                        ▼
┌────────────────────────────────────────────────────────┐
│ Bridge minter (pool)                                  │
│   - implement rate limits here (example: token bucket) │
│   - supply guards configured for adopted bridge         │
└────────────────────────────────────────────────────────┘
```

---

## 8. Invariants (INV)

| ID | Invariant | Verification |
| --- | --- | --- |
| MCHN-INV-001 | Even after 🔵 Core `setCollateralRegistry()` (owner renounce, `owner = address(0)`), `bridgeAdmin` survives and `onlyBridgeAdmin` functions remain executable (separate storage and role from owner) | invariant / unit |
| MCHN-INV-002 | JPYdf issued on destination by Burn & Mint is the same canonical token and does not create a wrapped version (same token across all chains) | manual / integration |
| MCHN-INV-003 | `mint` / `burn` can be executed only by "existing core authority `||` registered bridge minter"; all others permission-revert (existing core authority unchanged; addition is one OR term only) | invariant / unit |
| MCHN-INV-004 | Collateral remains chain-local; only JPYdf can cross chains (Day2 has no collateral market on other chains at all) | manual |
| MCHN-INV-005 | Globally, `total JPYdf supply = total trove debt` is always preserved (local chains may diverge). Day2 is a special case where "all trove debt = concentrated on Ethereum, JPYdf = distributed" | manual / integration |
| MCHN-INV-006 | Adding bridge minter requires 48h timelock (`TIMELOCK - 1` reverts, exactly `TIMELOCK` succeeds); removal is immediate (asymmetric design) | unit |
| MCHN-INV-007 | Production modification to `BoldToken` is limited to additive state/functions; `BoldToken` remains non-upgradeable, and 🔵 Core and other contracts remain unchanged | manual (diff review) |
| MCHN-INV-008 | `getCCIPAdmin()` always returns current `bridgeAdmin` (new admin after transfer, `address(0)` after renounce) and does not imply adoption of a specific bridge | unit |

---

## 9. Security Requirements (SEC)

### MCHN-SEC-001: Limit Modifications to Additive Extension of One File, `BoldToken.sol`

- Type: Security
- Statement: production modification for this extension must be confined to additive state variables and functions in `contracts/src/BoldToken.sol`; `BoldToken` must remain **non-upgradeable**, and `CollateralRegistry` and other 🔵 Core contracts must remain unchanged (core no-modification and minimum-change policy). Do not modify 🔵 Core except wiring (`DeployLiquity2.s.sol`) and test harnesses.
- Verification: manual (diff review and scope requirement), invariant=MCHN-INV-007

### MCHN-SEC-002: Bridge-Independent (Do Not Import Specific Protocols)

- Type: Security
- Statement: `BoldToken` must not import or reference code for specific bridge protocols such as CCIP / LayerZero. On Day2, a bridge plugs in as minter through `proposeBridgeMinter`. The function name `getCCIPAdmin()` is a shim matching an external registry self-registration convention, and does not imply adoption of a specific bridge ([MCHN-FR-010](#mchn-fr-010-getccipadmin-self-registration-shim)).
- Verification: manual (dependency/import review), invariant=MCHN-INV-008

### MCHN-SEC-003: Rate Limits Live on Minter Side

- Type: Security
- Statement: `BoldToken` itself must have no rate limits. The token side manages only "who is a trusted minter"; rate limits for "how much can be issued/burned per unit time" are **implemented on the bridge minter (pool) side**. This responsibility separation keeps the token bridge-agnostic while allowing rate limits appropriate to the adopted bridge to be configured on the minter side. Concrete specification is finalized together with Day2 bridge selection ([MCHN-TBD-001](#mchn-tbd-001-bridge-protocol-selection-day2)) ([MCHN-TBD-002](#mchn-tbd-002-rate-limit-details-day2)).
- Verification: manual (responsibility-separation review), integration (minter-side rate limits)

### MCHN-SEC-004: Registered Minters Are Limited to Fully Trusted Bridges

- Type: Security
- Statement: A registered bridge minter has strong authority to execute `mint(account, amount)` (arbitrary amount to arbitrary address) and `burn(account, amount)` (arbitrary amount from arbitrary address), so it must be a **fully trusted bridge contract**. Burn from arbitrary accounts is already an authority core has in Liquity v2 (TroveManager / StabilityPool during liquidation), and bridge minter is placed at the same trust level. This is secured by careful registration with a 48h timelock by Safe-multisig `bridgeAdmin` ([MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start) / [MCHN-FR-003](#mchn-fr-003-confirmbridgeminter-confirm-registration)).
- Verification: manual (trust-boundary review), unit (registered minter can mint/burn; unregistered reverts)

### MCHN-SEC-005: Emergency Stop (Immediate Blocking)

- Type: Security
- Statement: if a bridge minter is compromised, `bridgeAdmin` must be able to immediately block that minter with `removeBridgeMinter()` **without timelock** (first incident-response tool). The asymmetry of 48h delay for addition and immediate removal is intentional.
- Verification: unit (immediate blocking; removed minter mint/burn reverts), manual (runbook = [MCHN-GOV-004](#mchn-gov-004-pre-merge-gates-day2day3-operation-gates) G6)

### MCHN-SEC-006: Admin Key Management (Safe Multisig Enforced)

- Type: Security
- Statement: constructor enforces that `bridgeAdmin` is a contract ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)), and operationally it must be **Safe multisig** (or Safe + Timelock). A contract owned by only an EOA is insufficient. Because `transferBridgeAdmin` does not recheck invariants, operational procedures and governance approval must ensure the admin transferee is also a Safe multisig ([MCHN-GOV-003](#mchn-gov-003-operationally-ensure-admin-transferee-is-also-safe-multisig)).
- Verification: manual (multisig configuration review)

---

## 10. Governance, Operations, and Upgrade Requirements (GOV)

### MCHN-GOV-001: `bridgeAdmin` / owner Are Safe Multisigs

- Statement: `bridgeAdmin` must be a Safe multisig configuration (example: 3-of-5). Because Day2 other-chain token-only `BoldToken` keeps owner unrenounced for Day3 core wiring ([MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration)), that owner must also be Safe multisig.
- Verification: manual (deploy configuration review)

### MCHN-GOV-002: Day N Exit Renounces After Removing All Minters

- Statement: when bridge operations end, always execute "**remove all bridge minters with `removeBridgeMinter()` → then `renounceBridgeAdmin()`**" in that order. `renounceBridgeAdmin()` does not clear confirmed `bridgeMinterAddresses`; reversing the order leaves surviving minters permanently unstoppable (all `onlyBridgeAdmin` functions disabled). Put this in a runbook ([MCHN-GOV-004](#mchn-gov-004-pre-merge-gates-day2day3-operation-gates) G6).
- Verification: manual (runbook and procedure review), unit (minter survives after renounce and cannot be removed)

### MCHN-GOV-003: Operationally Ensure Admin Transferee Is Also Safe Multisig

- Statement: `transferBridgeAdmin()` / `acceptBridgeAdmin()` do **not recheck** constructor invariants (contract-ness and different from owner); they only check `_newAdmin != address(0)`. When transferring admin, operational procedures and governance approval must ensure the transferee is a Safe multisig. Code does not enforce the transferee form.
- Verification: manual (governance approval and transferee review)

### MCHN-GOV-004: Pre-Merge Gates (Day2/Day3 Operation Gates)

- Statement: code implementing these requirements, and production operation for Day2 (token-only bridge), must satisfy the following. Day3 (other-chain full protocol) applies the same gates to each chain.

| Gate | Requirement |
| --- | --- |
| **G1 Audit** | complete external audit of `BoldToken` including bridge extension |
| **G2 admin = multisig** | configure `bridgeAdmin` as Safe multisig (example: 3-of-5) ([MCHN-GOV-001](#mchn-gov-001-bridgeadmin--owner-are-safe-multisigs)) |
| **G3 other-chain owner = multisig** | since Day2 other-chain token-only `BoldToken` keeps owner unrenounced, that owner is also Safe multisig ([MCHN-GOV-005](#mchn-gov-005-day2-token-only-chain-owner-is-kept-until-day3-wiring)) |
| **G4 rate limits** | implement rate limits on bridge minter (pool) side ([MCHN-SEC-003](#mchn-sec-003-rate-limits-live-on-minter-side)) |
| **G5 supply monitor** | prepare cross-chain monitor for total JPYdf supply across all chains = total trove debt ([MCHN-FR-012](#mchn-fr-012-supply-consistency-local-divergence-global-invariant)) |
| **G6 emergency runbook** | create runbook for immediate `removeBridgeMinter()` blocking on minter compromise ([MCHN-SEC-005](#mchn-sec-005-emergency-stop-immediate-blocking)) and Day N exit procedure ([MCHN-GOV-002](#mchn-gov-002-day-n-exit-renounces-after-removing-all-minters)) |
| **G7 testnet proof** | prove bidirectional Burn & Mint on testnet ([MCHN-FR-011](#mchn-fr-011-burn--mint-cross-chain-transfer-flow)) |

- Verification: manual (gate satisfaction review)

### MCHN-GOV-005: Day2 Token-Only Chain Owner Is Kept Until Day3 Wiring

- Statement: Day2 token-only `BoldToken` has no CollateralRegistry and does not call `setCollateralRegistry()`, so owner naturally survives. This owner is a powerful key capable of core wiring (effectively mint/burn permission granting), and must be kept without renounce as **Safe multisig** until Day3 core wiring. When core is wired on Day3 and `setCollateralRegistry()` is called, owner is renounced ([MCHN-FR-001](#mchn-fr-001-persistent-bridgeadmin-role-independent-of-ownable) / [MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration)).
- Verification: manual (Day2 deploy configuration and owner-retention review)

---

## 11. Event and Monitoring Requirements (EVT)

| ID | Event | Emitted by (FR) | Purpose (off-chain) |
| --- | --- | --- | --- |
| MCHN-EVT-001 | BridgeMinterProposed (proposal: minter / proposed timestamp, index recommended) | [MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start) | detect bridge minter proposal and timelock start (start 48h count) |
| MCHN-EVT-002 | BridgeMinterProposalCancelled (cancellation / old proposal cancellation on overwrite) | [MCHN-FR-002](#mchn-fr-002-proposebridgeminter-proposal--timelock-start) / [MCHN-FR-004](#mchn-fr-004-cancelbridgeminterproposal-cancel-proposal) | detect proposal cancellation (mistake / compromise escape) |
| MCHN-EVT-003 | BridgeMinterConfirmed (confirmed registration: minter) | [MCHN-FR-003](#mchn-fr-003-confirmbridgeminter-confirm-registration) | detect minter activation (mint/burn allowed) |
| MCHN-EVT-004 | `BridgeMinterRemoved(_minter)` | [MCHN-FR-005](#mchn-fr-005-removebridgeminter-immediate-removal) | detect immediate minter blocking (incident response) |
| MCHN-EVT-005 | `BridgeAdminTransferred(previous, current)` | [MCHN-FR-009](#mchn-fr-009-constructor-invariants) (from=0) / [MCHN-FR-008](#mchn-fr-008-2-step-admin-transfer--renounce) | track admin setting, transfer, and renounce (current=0) |
| MCHN-EVT-006 | cross-chain supply monitor (not an event; off-chain monitoring requirement aggregating ERC20 `Transfer`) | [MCHN-FR-012](#mchn-fr-012-supply-consistency-local-divergence-global-invariant) | monitor all-chain total `total JPYdf supply = total trove debt` (MCHN-INV-005) |

- The minter lifecycle (proposal → confirm / cancel → remove) and admin transfer must all be traceable off-chain through the above events. `BridgeMinterRemoved` / `BridgeAdminTransferred` signatures are normative in implementation (§6 and [MCHN-FR-005](#mchn-fr-005-removebridgeminter-immediate-removal) / [MCHN-FR-009](#mchn-fr-009-constructor-invariants)).

---

## 12. Failure and Exception Behavior (ERR)

**Bridge extension active state by phase**

| Phase | bridge minter | mint/burn extension | collateral issuance | JPYdf circulation |
| --- | --- | --- | --- | --- |
| Day1 | unregistered (dormant) | inactive (behavior same as single-chain Liquity v2) | Ethereum only | Ethereum only |
| Day2 | registered on Ethereum + other chains | active | **Ethereum only** (no borrowing/liquidation/SP market on other chains) | to other chains by Burn & Mint (bridge-derived only) |
| Day3 | registered on all chains | active | each chain (independent markets) | cross-chain (same token) |

**Error catalog (require strings)**

| Error (require string) | Trigger |
| --- | --- |
| `"BoldToken: Caller is not BO or AP or Bridge"` | `mint` by non-core and non-registered minter ([MCHN-FR-006](#mchn-fr-006-mint-permission-extension)) |
| `"BoldToken: Caller is neither CR nor BorrowerOperations nor TroveManager nor StabilityPool nor Bridge"` | `burn` by non-core and non-registered minter ([MCHN-FR-007](#mchn-fr-007-burn-permission-extension)) |
| `"BoldToken: not a bridge minter"` | `removeBridgeMinter` for unregistered minter ([MCHN-FR-005](#mchn-fr-005-removebridgeminter-immediate-removal)) |
| `"BoldToken: zero bridgeAdmin"` | constructor `_bridgeAdmin == address(0)` ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)) |
| `"BoldToken: bridgeAdmin must be a contract"` | constructor `_bridgeAdmin.code.length == 0` ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)) |
| `"BoldToken: bridgeAdmin must differ from owner"` | constructor `_bridgeAdmin == _owner` ([MCHN-FR-009](#mchn-fr-009-constructor-invariants)) |
| revert (`onlyBridgeAdmin`) | propose/confirm/cancel/remove/transfer/renounce by non-admin |
| revert (timelock not elapsed) | `confirmBridgeMinter` at `TIMELOCK - 1` ([MCHN-FR-003](#mchn-fr-003-confirmbridgeminter-confirm-registration)) |
| revert (no proposal) | `confirmBridgeMinter` after cancellation ([MCHN-FR-004](#mchn-fr-004-cancelbridgeminterproposal-cancel-proposal)) |

**Operational exception cases (known review findings; not preventable by code and guaranteed operationally)**

| Event | Control |
| --- | --- |
| cannot stop surviving minter after renounce | Day N exit order is remove all minters → then renounce ([MCHN-GOV-002](#mchn-gov-002-day-n-exit-renounces-after-removing-all-minters)) |
| admin transferee becomes EOA / same as owner | `transferBridgeAdmin` does not recheck invariants, so operations ensure Safe multisig ([MCHN-GOV-003](#mchn-gov-003-operationally-ensure-admin-transferee-is-also-safe-multisig)) |
| minter compromise | immediately block with `removeBridgeMinter()` ([MCHN-SEC-005](#mchn-sec-005-emergency-stop-immediate-blocking)) |

---

## 13. Acceptance Criteria and Verification Plan

Passing condition for each requirement = satisfy the verification methods in the table below (test names and execution results are not written here; only method types). Production modification is limited to additive extension of 🟡 `BoldToken.sol`; do not modify 🔵 Core except wiring (`DeployLiquity2.s.sol`) and test harnesses.

**Scope requirement**: production modification is limited to additive extension of `contracts/src/BoldToken.sol` (other 🔵 Core contracts unchanged; [MCHN-SEC-001](#mchn-sec-001-limit-modifications-to-additive-extension-of-one-file-boldtokensol) / MCHN-INV-007).

| ID | Requirement (summary) | Verification method |
| --- | --- | --- |
| MCHN-FR-001 | persistent `bridgeAdmin` role (survives owner renounce) | unit, invariant=MCHN-INV-001 |
| MCHN-FR-002 | `proposeBridgeMinter` (proposal, overwrite, timelock start) | unit, integration |
| MCHN-FR-003 | `confirmBridgeMinter` (timelock boundary and cannot confirm after cancellation) | unit, integration |
| MCHN-FR-004 | `cancelBridgeMinterProposal` (cancel and cannot confirm after cancellation) | unit |
| MCHN-FR-005 | `removeBridgeMinter` (immediacy, unregistered revert, cannot mint/burn after removal) | unit |
| MCHN-FR-006 | mint permission extension (registered minter allowed; unregistered/removed reverts) | unit, invariant=MCHN-INV-003 |
| MCHN-FR-007 | burn permission extension (registered minter allowed; unregistered/removed reverts) | unit, invariant=MCHN-INV-003 |
| MCHN-FR-008 | 2-step transfer / renounce (only pending can accept, overwrite allowed, renounce disables all admin functions and cancels pending) | unit, manual |
| MCHN-FR-009 | constructor invariants (zero / EOA / `owner==bridgeAdmin` revert) | unit, manual |
| MCHN-FR-010 | `getCCIPAdmin()` (returns `bridgeAdmin`, follows transfer, returns `address(0)` after renounce) | unit, invariant=MCHN-INV-008 |
| MCHN-FR-011 | Burn & Mint transfer flow (bidirectional) | integration, fork/testnet |
| MCHN-FR-012 | supply consistency (local divergence, global match) | integration, manual=MCHN-EVT-006 |
| MCHN-FR-013 | staged transition (Day1 inactive, Day2 activation, Day3 reuse wiring, no redeploy) | integration, fork/testnet |
| MCHN-INV-001..008 | each invariant in §8 | unit / invariant / manual (as listed in §8) |
| MCHN-SEC-001..006 | each security requirement in §9 | unit / manual / integration (as listed in §9) |
| MCHN-GOV-001..005 | governance and operational requirements in §10 (including G1-G7 gates) | manual |

**Test coverage requirements** (`BoldToken` bridge extension):

- constructor invariants (zero / EOA / `owner==bridgeAdmin` revert)
- propose / confirm timelock boundary (`TIMELOCK - 1` reverts, exactly `TIMELOCK` succeeds)
- proposal overwrite, cancellation, and cannot confirm after cancellation
- immediacy of `removeBridgeMinter`
- 2-step transfer (only pending can accept, overwrite allowed)
- `renounceBridgeAdmin` disables all admin functions and cancels pending proposal
- registered minter can mint/burn; unregistered/removed reverts
- **`bridgeAdmin` survives after `setCollateralRegistry()` (owner renounce)**
- `getCCIPAdmin()` returns `bridgeAdmin` and follows after transfer

---

## 14. Open Items (TBD)

> **Distinction between finalized requirements and staged decisions**: §5, §6, §9, and §13 are requirements for the `BoldToken` side that should be **finalized on Day1** (interfaces, invariants, acceptance criteria, operational controls). The following are decisions finalized in later stages.

### MCHN-TBD-001: Bridge Protocol Selection (Day2)

The bridge protocol to adopt (Chainlink CCIP / LayerZero, etc.) is undecided and is a **Day2 decision**. These requirements do not assume a specific bridge, and `BoldToken` contains no CCIP / LayerZero-specific code ([MCHN-SEC-002](#mchn-sec-002-bridge-independent-do-not-import-specific-protocols)). The bridge-agnostic design allows Day1 token design to be finalized while deferring selection to Day2. Both-end wiring (burn/mint endpoints on Ethereum side and other-chain side) is also finalized here. Related: [MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration).

### MCHN-TBD-002: Rate Limit Details (Day2)

Concrete specification for rate limits placed on the bridge minter (pool) side (example: token bucket) is finalized together with Day2 bridge selection ([MCHN-TBD-001](#mchn-tbd-001-bridge-protocol-selection-day2)). `BoldToken` side has no rate limits ([MCHN-SEC-003](#mchn-sec-003-rate-limits-live-on-minter-side)).

### MCHN-TBD-003: Other-Chain Full Protocol Wiring Method (Day3)

**Full protocol wiring** on other chains and the method for connecting core to the Day2 token-only `BoldToken` (owner retained → Day3 renounce) are **Day3 decisions**. Reuse Day2 token-only `BoldToken` and wire Liquity v2 Core + 🟢 original layers around it ([MCHN-FR-013](#mchn-fr-013-staged-transition-no-migration) / [MCHN-GOV-005](#mchn-gov-005-day2-token-only-chain-owner-is-kept-until-day3-wiring)).

---

## 15. References

- [Product Overview](../protocol/product/Product-Overview.md) — overall product / 🔵🟡🟢 markers / principle of core unmodified (§5)
- [Liquity-v2-Core-Spec](../protocol/product/spec/Liquity-v2-Core-Spec.md) — 🔵 Core mint/burn permissions and `setCollateralRegistry()` owner renounce behavior
- [Oracle requirements](../protocol/product/spec/Oracle.md) — `PriceFeedProxy` 24h timelock (replacement pattern same shape as this document's bridge minter 48h propose/confirm)
- [Parameters.md](../Parameters.md) — source of truth for finalized values such as `BRIDGE_MINTER_TIMELOCK` (48h)
- [Requirements Specification Document Standard](../README.md#requirements-spec-standard) — standard followed by this document
