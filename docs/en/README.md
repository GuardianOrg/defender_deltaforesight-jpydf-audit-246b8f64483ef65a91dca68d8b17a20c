# JPY DeFi English Support Documents (`documents/en`)

This directory mirrors the domain and lifecycle layout of the Japanese JPY DeFi documentation for English-language review and implementation support.

## Source of Truth Policy

- The Japanese tree under [`documents/jp/`](../jp/) is normative. English documents are support translations and may lag behind it.
- Domain, lifecycle, artifact type, and decision authority follow the Japanese [Document Governance](../jp/Document-Governance.md).
- Historical reviews remain point-in-time records. Current behavior and values must be checked against the Japanese Spec, Policy, Decision, Manifest, and Evidence sources.

## Document List

This directory is organized into the following folders by purpose.

```text
documents/en/
├── README.md
├── Parameters.md
├── Governance.md
├── protocol/
│   ├── product/
│   ├── launch/
│   ├── operations/
│   └── roadmap/
├── contributors/
│   └── deltaforesight/
├── engineering/
│   ├── plans/
│   ├── guides/
│   ├── verification-ledgers/
│   └── historical-reviews/
└── archive/
```

- **Protocol**: product requirements, launch decisions and gates, post-launch operations, and roadmap candidates.
- **Contributor**: DeltaForesight commitments, delivery plans, and company-operated procedures.
- **Engineering**: implementation plans, technical guides, verification ledgers, and historical reviews.
- **Archive**: deprecated material that is outside the active implementation and audit scope.

### Product Specifications

| File                                                                   | Contents                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Product-Overview.md`](protocol/product/Product-Overview.md)                         | Evergreen Protocol Spec for system requirements, constraints, invariants, architecture principles, and trust boundaries                                                                                                                                                                                                                         |
| [`Architecture-Decision-Records.md`](protocol/product/architecture/Architecture-Decision-Records.md) | Decision Record for the rationale behind the major Protocol architecture choices (`ADR-*`) |
| [`Mainnet-Launch-Risk-Gate.md`](protocol/launch/gates/Mainnet-Launch-Risk-Gate.md) | Launch Runbook / Gate for system-wide mainnet risks and acceptance evidence (`SYS-RISK-*`) |
| [`Governance.md`](./Governance.md)                                     | A cross-cutting permissions reference for looking up the holder, target functions, and timing of GOV / Guardian / Allocator / Writeoff / Owner / Upgrader / Timelock. Requirement values refer to each component spec and Parameters                                                                                                                                                                              |
| [`Liquity-v2-Core-Spec.md`](protocol/product/spec/Liquity-v2-Core-Spec.md)            | Liquity v2 core inheritance specification (`CORE-*`). Normatively defines the external/public functions, state variables, and events of **all core contracts in the §5.1 catalog** with IDs (upstream-preserved PriceFeeds/Zappers etc. are outside the normative scope, as stated in §5.1). DF modification ledger (`CORE-MOD-*`) / cross-cutting invariants / parity verification plan for fork-source identity |
| [`Permissionless-User-Operations.md`](protocol/product/spec/Permissionless-User-Operations.md)         | Public frontend operation requirements mapping permissionless state-changing surfaces in Core / JPYdf / dToken / Vault / Zapper / keeper / optional modules to User App routes, adopted entrypoints, conditional visibility, and intentional exclusions |
| [`JpydfToken.md`](protocol/product/spec/JpydfToken.md)                                | JpydfToken requirements (`CORE-BT-*`). Debt token JPYdf: Core `mint`/`burn` authorization boundary, SP internal transfers, recipient-restricted ERC-20/permit, deploy wiring and owner renounce, and the 🟡 bridge-ready dormant surface (`bridgeAdmin` / minter registry / `bridgeMint` / self-burn `bridgeBurn`). The activation gate before bridge minter registration is [`Bridge-Minter-Activation-Gate.md`](protocol/operations/runbooks/Bridge-Minter-Activation-Gate.md). Separated from the Core Spec (namespace preserved) |
| [`dToken.md`](protocol/product/spec/dToken.md)                                        | dToken requirements. dToken token (decimals / conversion / collateral cap / setTokenInfo / EIP-2612 Permit / mint and burn authorization)                                                                                                                                                                                                                                                                         |
| [`CollateralVault.md`](protocol/product/spec/CollateralVault.md)                      | CollateralVault requirements. Underlying custody / mint and redeem / buffer accounting / allocate and push reception / delayed redemption / Treasury transfer / permissions, events, and risks                                                                                                                                                                                                                    |
| [`Strategy.md`](protocol/product/spec/strategies/Strategy.md)                         | Common Strategy architecture. IStrategy / push model / permissions and monitoring                                                                                                                                                                                                                                                                                                                                 |
| [`AaveV3Strategy.md`](protocol/product/spec/strategies/AaveV3Strategy.md)             | Individual Strategy implementation for Aave V3 (child document of `Strategy.md`)                                                                                                                                                                                                                                                                                                                                  |
| [`LidoStrategy.md`](archive/LidoStrategy.md)                 | **Archived / Out of scope**: historical requirements for the retired Lido async Strategy. Source preserved at `contracts/src/Strategies/archive/`. Previously audited under `0c7766e0`; not active implementation or audit scope                                                                                                                                                                                                                                                       |
| [`ERC4626Strategy.md`](protocol/product/spec/strategies/ERC4626Strategy.md)           | Generic Strategy implementation for ERC-4626-compliant vaults (child document of `Strategy.md`)                                                                                                                                                                                                                                                                                                                   |
| [`SkySUsdsStrategy.md`](protocol/product/spec/strategies/SkySUsdsStrategy.md)         | Individual Strategy requirements for dUSDC Sky USDC -> USDS -> sUSDS                                                                                                                                                                                                                                                                                                                                              |
| [`EtherfiWeETHStrategy.md`](archive/EtherfiWeETHStrategy.md) | **Archived / Out of scope**: historical requirements for the retired Ether.fi eETH / weETH async Strategy and its withdraw adapter. Source preserved at `contracts/src/Strategies/archive/`. Previously audited under `0c7766e0`; not active implementation or audit scope                                                                                                                                                                                                                                                                                                                                    |
| [`Zapper.md`](protocol/product/spec/Zapper.md)                                        | Zapper UX Router / EIP-2612 Permit / Sky ingress / Uniswap v4 route gate (Flash Loan close is outside the current ABI)                                                                                                                                                                                                                                                                                      |
| [`Oracle.md`](protocol/product/spec/Oracle.md)                                        | PriceFeedProxy / Chainlink feeds / per-collateral oracle configuration / placeholder branches                                                                                                                                                                                                                                                                                                                     |
| [`Treasury.md`](protocol/roadmap/spec/Treasury.md)                                    | Treasury requirements. Revenue router that sends collateral deployment yield to fixed purpose destinations / registered backstop Vaults. **The current launch package uses Safe retention only, `Treasury.sol` is not implemented, and routing is future activation scope**                                                                         |
| [`Reward-Distributors.md`](protocol/roadmap/spec/Reward-Distributors.md) | Consolidated requirements for SP additional reward, Borrow Referral, and SP-deposit Referral distributors. Covers purpose-isolated buyback, attribution, cumulative Merkle roots, challenge, and claims. **Future draft / outside current audit scope** |
| [`InterestRouter.md`](protocol/product/spec/InterestRouter.md)                        | InterestRouterForwarder requirements (`IRTR-*`). A single forwarder receiving the PIL share of aggregate interest, with permissionless `route()`, mutable `recipient`, disabled renounce, and 2-step owner handover                                                                                                                                                                                               |
| [`PILAllocator.md`](protocol/product/spec/PILAllocator.md)                            | PILAllocator / IInitiative / UniV4MerklInitiative requirements (`PILA-*`). Phase-A liquidity incentive layer that receives PIL from InterestRouter, allocates by admin weights to registered initiatives, and connects Uniswap v4 Merkl campaigns                                                                                                                                                             |
| [`Frontend.md`](protocol/product/spec/Frontend.md)                                    | Frontend requirements (off-chain). Four target surfaces: User App, Admin Control, Private Operations Monitor, and Dune Public Analytics. The legacy public Ops UI is transitional only. Covers configuration synchronization, transaction UX, data freshness, security, and monitoring                                                                                                                                 |
| [`Multichain.md`](./archive/Multichain.md)                             | **Deprecated / Out of Scope**: historical study material for Burn & Mint / bridge extensions. Not the source of truth for current implementation or audit                                                                                                                                                                                                                                                         |
| [`Parameters.md`](./Parameters.md)                                     | Day-1 Parameter Manifest for the values selected for a particular launch environment. Evergreen acceptance criteria remain in Protocol Specs and Policies                                                                                                                                                                                                                                                    |

### Domain and Lifecycle Index

English support documents use the same placement boundaries as the Japanese tree. See the [engineering index](engineering/README.md) for implementation and verification material.

| Category              | Location                                                                                                  | Contents                                                                                                                                                                                                                                                                                                                                          |
| --------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Protocol product | [`protocol/product/`](protocol/product/) | Product overview, component specifications, and evergreen product policies |
| Protocol launch | [`protocol/launch/`](protocol/launch/) | Mainnet decisions and pre-launch gates |
| Protocol operations | [`protocol/operations/`](protocol/operations/) | Post-launch policies and runbooks |
| Protocol roadmap | [`protocol/roadmap/`](protocol/roadmap/) | Future initiatives, policies, and unimplemented specifications |
| DeltaForesight contributor | [`contributors/deltaforesight/`](contributors/deltaforesight/) | Company commitments, delivery plans, and operated procedures |
| Engineering | [`engineering/`](engineering/) | Plans, guides, verification ledgers, and historical reviews |

## Suggested Reading Order

1. [`Product-Overview.md`](protocol/product/Product-Overview.md) — evergreen system requirements, architecture, and terminology
2. [`Architecture-Decision-Records.md`](protocol/product/architecture/Architecture-Decision-Records.md) — rationale for the major architecture decisions
3. [`Mainnet-Launch-Risk-Gate.md`](protocol/launch/gates/Mainnet-Launch-Risk-Gate.md) — mainnet launch acceptance conditions and Evidence
4. [`Contract-Audit-Usage-Map.md`](engineering/guides/Contract-Audit-Usage-Map.md) — auditor-facing actors, entrypoints, keeper/admin paths, and disabled routes
5. [Root `SCOPE.md`](../../SCOPE.md) — sole current additional-audit SOW page; exact paths, current nSLOC, integration/non-scope boundaries, and requested schedule. The retained engineering guide is historical.
6. [`Liquity-v2-Core-Spec.md`](protocol/product/spec/Liquity-v2-Core-Spec.md) — the core inherited without modification, plus [`JpydfToken.md`](protocol/product/spec/JpydfToken.md) (debt token JPYdf; the `CORE-BT-*` separated from the Core Spec)
7. By layer: [`dToken.md`](protocol/product/spec/dToken.md) -> [`CollateralVault.md`](protocol/product/spec/CollateralVault.md) -> [`Strategy.md`](protocol/product/spec/strategies/Strategy.md) / [`AaveV3Strategy.md`](protocol/product/spec/strategies/AaveV3Strategy.md) / [`ERC4626Strategy.md`](protocol/product/spec/strategies/ERC4626Strategy.md) / [`MorphoV2Strategy.md`](protocol/product/spec/strategies/MorphoV2Strategy.md) / [`SkySUsdsStrategy.md`](protocol/product/spec/strategies/SkySUsdsStrategy.md) -> [`Oracle.md`](protocol/product/spec/Oracle.md) -> [`Zapper.md`](protocol/product/spec/Zapper.md) -> [`InterestRouter.md`](protocol/product/spec/InterestRouter.md) -> [`PILAllocator.md`](protocol/product/spec/PILAllocator.md). Read [`Treasury.md`](protocol/roadmap/spec/Treasury.md) -> [`Reward-Distributors.md`](protocol/roadmap/spec/Reward-Distributors.md) only when working on future revenue distribution.
8. [`Parameters.md`](./Parameters.md) — the Day-1 Parameter Manifest
9. [`Governance.md`](./Governance.md) — cross-cutting reference for permission holders, target functions, and Timelock boundaries
10. [`Frontend.md`](protocol/product/spec/Frontend.md) — off-chain requirements for the User App, Admin Control, Private Operations Monitor, and Dune Public Analytics
   - [`Permissionless-User-Operations.md`](protocol/product/spec/Permissionless-User-Operations.md) is the exhaustive public User App operation matrix required by `FRNT-FR-038`.
11. Optional: [`Contract-Business-Catalog.md`](engineering/guides/Contract-Business-Catalog.md) for product / business context. It is not authoritative for audit scope or entrypoint classification
12. Optional: [`Product-Unwind-And-Sunset-Runbook.md`](protocol/operations/runbooks/Product-Unwind-And-Sunset-Runbook.md) for exit/sunset operations, and [`Multichain.md`](./archive/Multichain.md) / [`LidoStrategy.md`](./archive/LidoStrategy.md) / [`EtherfiWeETHStrategy.md`](./archive/EtherfiWeETHStrategy.md) for historical material that has been moved out of scope. Do not use archived documents for implementation decisions

> To understand implementation progress and the rebuild background, first read the specifications above (the source of truth), then see [`engineering/`](./engineering/) for development plans and historical reviews.

---

## Requirements Spec Standard

> This section is the **source of truth for how contract requirement specifications under `documents/jp` are written**. New documents and revisions must follow this standard.
> Purpose: standardize requirements as **verifiable specifications that can be translated directly into implementation, tests, and audits**, rather than as design narratives.

### Scope of Application

- **This standard applies to the current production source / audit-visible requirement specification files**: [`dToken.md`](protocol/product/spec/dToken.md) / [`CollateralVault.md`](protocol/product/spec/CollateralVault.md) / [`Strategy.md`](protocol/product/spec/strategies/Strategy.md) / [`AaveV3Strategy.md`](protocol/product/spec/strategies/AaveV3Strategy.md) / [`ERC4626Strategy.md`](protocol/product/spec/strategies/ERC4626Strategy.md) / [`MorphoV2Strategy.md`](protocol/product/spec/strategies/MorphoV2Strategy.md) / [`SkySUsdsStrategy.md`](protocol/product/spec/strategies/SkySUsdsStrategy.md) / [`Oracle.md`](protocol/product/spec/Oracle.md) / [`Zapper.md`](protocol/product/spec/Zapper.md) / [`InterestRouter.md`](protocol/product/spec/InterestRouter.md) / [`PILAllocator.md`](protocol/product/spec/PILAllocator.md) / [`Frontend.md`](protocol/product/spec/Frontend.md). `SkySUsdsStrategy.md` is an implemented optional Strategy requirement, not an active requirement for the expected launch manifest. `LidoStrategy.md` / `EtherfiWeETHStrategy.md` are archived and no longer covered by this standard.
- **This standard also applies to future draft requirement specifications outside current audit scope**: [`Treasury.md`](protocol/roadmap/spec/Treasury.md) / [`Reward-Distributors.md`](protocol/roadmap/spec/Reward-Distributors.md). These are not implementation requirements for existing contracts until a separate PR / activation gate adds the implementation, tests, and audit package.
- **Adapted application to the core inheritance specification**: [`Liquity-v2-Core-Spec.md`](protocol/product/spec/Liquity-v2-Core-Spec.md) (🔵 normative specification for the full core set). The template, ID rules, and guardrails in this standard apply, but its nature differs: it is not a set of requirements newly designed by DF; it is the descriptive normalization of the `base` (fork-source) implementation behavior (🔵 the base implementation is authoritative for requirements; if there is a conflict, the document is revised). Details of this adaptation are specified in §2.4 of that document. Because one document covers multiple contracts, IDs use a four-part format with contract scope (see ID rules below), and DF differences added to the core are centralized in the modification ledger (`CORE-MOD-*`) in §2.2 of that document.
- **Adapted application to off-chain components**: [`Frontend.md`](protocol/product/spec/Frontend.md) (frontend requirements). Its §0 specifies the translation table for contract-specific sections such as signatures and reverts. The same ID rules, append-only policy, and guardrails apply.
- **Historical material (outside current scope)**: [`Multichain.md`](./archive/Multichain.md), [`LidoStrategy.md`](./archive/LidoStrategy.md), [`EtherfiWeETHStrategy.md`](./archive/EtherfiWeETHStrategy.md). `MCHN-*` / `LIDO-*` / `EFWEETH-*` remain as historical IDs that are not reused, but they are not active requirements for implementation or audit. The archived Strategy sources stay under `contracts/src/Strategies/archive/` because they were covered by the external audit completed 2026-08-05 (`0c7766e0`); that audit result is preserved, but the surfaces are outside the active audit scope.
- **Not applied to**: [`Parameters.md`](./Parameters.md) (Day-1 Parameter Manifest) / [`Product-Overview.md`](protocol/product/Product-Overview.md) (source of truth for higher-level system requirements and architecture) / [`Mainnet-Launch-Risk-Gate.md`](protocol/launch/gates/Mainnet-Launch-Risk-Gate.md) (Launch Runbook / Gate) / [`Architecture-Decision-Records.md`](protocol/product/architecture/Architecture-Decision-Records.md) (Decision Record)
- **🔵 Core behavior must not be respecified in component specs (🟢 layers)**. Normative core behavior is centralized in `Liquity-v2-Core-Spec.md` (`CORE-*`) and is referenced from other documents by ID.

### Standard Template (Chapter Structure)

Each file is standardized in the following order (**scalable**: thin modules may merge sections with no substantive content. Do not leave empty headings; use a one-line "Not applicable (reason)" instead).

```
## 0. Metadata          Status / Owner / Target contracts / Related docs
## 1. Purpose, Scope, and Non-Responsibilities
## 2. Background and Design Policy       Why, rationale, relation to no core modification
## 3. Terms, External Dependencies, and Assumptions    glossary and trusted externals (Chainlink/Aave etc.)
## 4. Actors, Roles, and Trust Boundaries
## 5. Interface Specification    Function signatures / visibility list (terse, non-normative)
## 6. Functional Requirements FR         ID-based verifiable blocks (normative body)
## 7. State Variables and Accounting Model    principal/profit/dust/cap etc. accounting
## 8. Invariants INV        ID-based (specification for invariant tests)
## 9. Security Requirements SEC    ID-based (reentrancy/CEI/oracle validation/least privilege)
## 10. Governance, Operations, and Upgrade Requirements GOV   ID-based
## 11. Event and Monitoring Requirements EVT   ID-based (indexed fields and off-chain uses)
## 12. Failure and Exceptional Behavior ERR   system-level behavior (pause/stale/buffer shortage/strategy failure)
## 13. Acceptance Criteria and Verification Plan   FR/INV/SEC x verification-method ledger
## 14. Open Issues TBD        ID-based
## 15. References
```

### Requirement ID Rules

- Format: `<MODULE>-<CAT>-<NNN>` (example: `DTKN-FR-005`). `NNN` is zero-padded to three digits.
- **Module prefixes**: `DTKN` (dToken) / `VAULT` (CollateralVault) / `STGY` (common Strategy) / `AAVE` (AaveV3Strategy) / `E4626` (ERC4626Strategy) / `MV2` (MorphoV2Strategy) / `SKY` (SkyUsdcSUsdsStrategy) / `ORCL` (Oracle) / `ZAP` (Zapper) / `TRSY` (Treasury) / `SPARD` (SPAdditionalRewardDistributor) / `BRRD` (BorrowReferralRewardDistributor) / `SPDRD` (SPDepositReferralRewardDistributor) / `IRTR` (InterestRouter) / `PILA` (PILAllocator) / `FRNT` (Frontend, off-chain). `MCHN` (Multichain), `LIDO` (LidoStrategy), and `EFWEETH` (EtherfiWeETHStrategy) are frozen as historical IDs and are not used for current requirements.
- **Categories**: `FR` (Functional) / `INV` (Invariant) / `SEC` (Security) / `GOV` (Governance, Operations, and Upgrade) / `EVT` (Events and Monitoring) / `ERR` (Failure Behavior) / `TBD` (Open Issue)
- **Special case for the core inheritance specification (`Liquity-v2-Core-Spec.md`)**: because one document covers many contracts, it uses the four-part format `CORE-<SCOPE>-<CAT>-<NNN>` with contract scope (example: `CORE-BO-FR-001`; `<SCOPE>` is BO/TM/SP/AP/DP/CSP/GP/ST/TN/BT/CR/AR/HH/MTG/DFH/RH/LCG/LIB/SYS; see §5.1 of that document). `NNN` is sequential and append-only per scope. In addition, the DF modification ledger has a dedicated three-part format `CORE-MOD-<NNN>` (§2.2 of that document is authoritative).
- **Append-only and no reuse**: even if a requirement is removed, leave its ID as a gap and do not reassign it to another requirement (preserves traceability across audit cycles). For withdrawal, leave `(Deprecated: reason)` in the text.
- **Cross-references use IDs, not section numbers**: write `DTKN-FR-006` when referencing another document. References do not break when chapters are renumbered.

### Requirement Block Format (§6 FR, §9 SEC, etc.)

Based on readable function specifications (purpose / numbered behavior / design notes), with **ID (heading) + Type/Source/Verification** added. Japanese labels map 1:1 to FR fields (Preconditions / Postconditions / Reverts / Events).

```md
### DTKN-FR-006: Update collateral cap with setCap

- **Type**: Functional | **Source**: Product-Overview "Collateral Cap" / Parameters mintCap # Do not write PR/SHA
- **Signature**: `setCap(uint256 newCap)`
- **Purpose**: <1-2 sentences. What the function does>
- **Permission**: <onlyOwner / onlyVault / permissionless etc.>
- **Preconditions (Checks)**: <call assumptions and input validation>
- **Behavior (Effects)**: <numbered state-change steps in CEI order>
- **revert / early return**: <condition -> error name>
- **Emitted event**: <Event = EVT-ID>
- **Design notes**: <function-specific design rationale (optional)>
- **Verification**: unit / fuzz / invariant=<INV-ID> / fork / integration / manual # Do not write test names
```

- **Type** is Functional / Security / Invariant / Governance / Event / Error. Priority is Must by default; specify `Priority: Should` etc. only when it is not Must.
- Self-evident view getters may simplify Preconditions and Behavior (**Purpose** and **Verification** are mandatory).
- Function-specific design rationale goes in **Design notes**; general background goes in §2 Design Policy.

### Guardrails (DF-Specific)

1. **Do not bring volatile information into the body**: do not write PR numbers, commit SHAs, test names, merge status, or migration history (git and `engineering/historical-reviews/Retrospective.md` carry those). `Verification` goes only as far as the **method category** (`unit/fuzz/invariant/fork/manual`).
2. **ID linkage is one-way**: code (NatSpec `@custom:requirement`), tests, PRs, and audit findings **refer to document IDs**. Documents do not list external artifacts.
3. **🔵 Core normative behavior is centralized**: normative core behavior exists only in `Liquity-v2-Core-Spec.md` (`CORE-*`) and is not respecified in component specs (reference by ID). Any core difference must be recorded in that document's `CORE-MOD-*` ledger in §2.2.
4. **Keep metadata minimal**: Status/Owner/target contracts/related docs. Do not place hand-written update dates (git carries them).
5. **Values live in Parameters.md**: specific values are referenced from `Parameters.md` as the source of truth; do not scatter numbers throughout requirement bodies.

> Applied example: [`dToken.md`](protocol/product/spec/dToken.md) is the first application of this standard.
