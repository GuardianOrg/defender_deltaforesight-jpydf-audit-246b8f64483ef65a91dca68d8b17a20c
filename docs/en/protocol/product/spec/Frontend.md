# 🖥 Frontend Requirements Definition

## 0. Metadata

| Item | Value |
| --- | --- |
| Status | Draft (the public User App, Admin Control, Private Operations Monitor, and Dune Public Analytics boundaries are defined; production evidence remains gated by the corresponding launch runbooks) |
| Owner | DeltaForesight |
| Target | Public User App (`frontend/app`) / Admin Control (`frontend/console`) / Private Operations Monitor (`frontend/ops`) / Dune Public Analytics / shared monitoring and statistics foundation |
| Related docs | [Product-Overview](../Product-Overview.md) (SYS-FR/ARCH) / [Permissionless User Operations](Permissionless-User-Operations.md) (FRNT-FR-038) / [dToken](dToken.md) / [CollateralVault](CollateralVault.md) / [Strategy](strategies/Strategy.md) / [Oracle](Oracle.md) / [Zapper](Zapper.md) / [Treasury](../../roadmap/spec/Treasury.md) / [Parameters](../../../Parameters.md) (source of truth for values) / [Public Analytics / Private Monitoring Architecture](../../../contributors/deltaforesight/operations/Public-Analytics-Private-Monitoring-Architecture.md) / [Mainnet-Participant-Readiness-Gate](../../launch/gates/Mainnet-Participant-Readiness-Gate.md) |

> This document **adapts the [Requirements Specification Document Standard](../../../README.md#requirements-spec-standard) to off-chain components**. Mapping table:
>
> | Standard (contract) | This document (frontend) |
> | --- | --- |
> | Signature | Target (surface, screen, function) |
> | Authorization | Target user and access control |
> | Preconditions (Checks) / Behavior (Effects) | Requirements (numbered, verifiable behavior) |
> | revert / early return | Exception behavior (degradation, blocking, display) |
> | Emitted event | Measurement (telemetry and monitoring) |
> | INV (on-chain invariant) | Display and configuration consistency invariants |
>
> `Verification` method types are defined in §13 (`unit / component / e2e-local / build / ci-guard / visual / manual / monitor`).

---

## 1. Purpose, Scope, and Non-Responsibilities

**Purpose**: define requirements for the **off-chain operation and visualization layer** for the JPY DeFi protocol (🔵 Liquity v2 Core + 🟢 dToken / Strategy / Oracle / Zapper / Treasury). Manage it with the same ID discipline as smart-contract requirements (`FRNT-*`) and maintain traceability from frontend implementation changes to requirement IDs. This document is the source of truth for `FRNT-*`; FRNT-FR-038 and the exhaustive [Permissionless User Operations](Permissionless-User-Operations.md) matrix govern coverage and execution paths for permissionless entrypoints.

- **In scope (four surfaces + shared foundation)**:
- **(A) 🟡 User app** — borrowing, repayment, dToken mint/redeem, Earn (SP), Redemption, and position management. Inherits the upstream Liquity v2 app and adds DF differences (JPY-denominated, 8 branches, dToken layer, JPY DeFi / JPYdf branding).
  - **(B) 🟢 Administrator console** — **preparation and visualization** of GOV_MULTISIG / ALLOCATOR operations (parameter changes, whitelist, oracle source replacement, pause, allocate). It holds no keys.
  - **(C) 🟢 Private Operations Monitor** — authenticated monitoring for branches, oracle, Vault/Strategy, Treasury, alerts, owners, and incident state. Read-only in principle.
  - **(D) Dune Public Analytics** — delayed public history and transparency derived from on-chain data. It is not a real-time monitor or an alert source.
  - **Shared foundation** — configuration, constants sync, wallet, transaction UX, data fetching, display conventions, security, telemetry.
- **Out of scope**: contract behavior itself (the component specs are the source of truth) / parameter value decisions ([Parameters.md](../../../Parameters.md)) / final legal/regulatory wording (only the display framework is defined here) / marketing site (static site without protocol operations).
- **Non-responsibility**: the frontend is **not the protocol trust root**. Core and each 🟢 layer operate fully without the frontend (same shape as ARCH-005), and users can call contracts directly to get the same results. Preserve a structure where frontend outage or tampering does not directly impair asset safety (potential impairment paths are controlled in §9 SEC).

---

## 2. Background and Design Principles

For the same reason the core uses an "unmodified fork" approach (ARCH-001/ADR-001), the frontend should also **operate with minimal differences on top of the battle-tested upstream Liquity v2 app**. Upstream UI logic (interest rate, LTV, hint calculation, etc.) has been validated through production usage by the original project, and a full rewrite would discard that value.

- **FE Principle 1 | Minimal upstream modification** — Keep the user app as a fork of the upstream app, but normalize JPYdf-owned frontend surfaces (display copy, types, request schemas, local storage keys, query keys, flow IDs, etc.) to JPYdf naming. Upstream package names, vendor component names, and base protocol spec references are outside this replacement scope. Maintain an update-friendly shape for pulling upstream changes.
- **FE Principle 2 | On-chain is truth** — The trust root for displayed balances, prices, and positions is contract reads through RPC. subgraph and statistics APIs are auxiliary indexes; detect freshness degradation and show degraded display (do not mix them with truth).
- **FE Principle 3 | No keys** — The frontend never holds any private key or privilege. User operations are signed by the user's wallet; privileged operations (GOV/ALLOCATOR) are executed through Safe or similar multisigs, while the administrator console only handles **preparation, verification, and visualization**.
- **FE Principle 4 | Configuration generated from artifacts** — Contract addresses, ABIs, and constants are machine-generated from deploy artifacts / contract sources. Do not keep handwritten duplicates (hardcoded addresses, mirrored constants). Where duplication is unavoidable, CI reconciles against the original source.
- **FE Principle 5 | Disciplined representation** — Do not make definitive claims about yield or safety (state market dependency and non-guarantee). Do not imply that dToken redemption is immediately guaranteed (when Buffer is insufficient, redemption is delayed = VAULT-FR-006). Show Redemption fees as borne by the redeemer.
- **FE Principle 6 | Surface separation** — Separate the User App (public), Admin Control (restricted), Private Operations Monitor (authenticated and read-only in principle), and Dune Public Analytics so trust boundaries, reachability, and deployment are not mixed.

---

## 3. Terminology, External Dependencies, and Assumptions

| Term | Meaning |
| --- | --- |
| Surface | Independently delivered unit (User App / Admin Control / Private Operations Monitor / Dune Public Analytics) |
| Binding | Bundle of chain ID, contract addresses, and ABIs referenced by the frontend |
| Constant mirror | Frontend-side duplicate of contract constants (MIN_DEBT, etc.). Sources of truth are `Constants.sol` / [Parameters.md](../../../Parameters.md) |
| Delayed redemption queue | Unclaimed list of WithdrawRequests when Buffer is insufficient (VAULT-FR-006) |
| Read-only mode | Viewing state with no wallet connected or by watching an arbitrary address |

**Trusted externals (frontend-specific)**: RPC providers (only trusted for read availability; multiple systems) / The Graph (subgraph index with freshness verification) / wallets (EIP-1193 / EIP-6963 detection, WalletConnect, hardware wallets) / Safe (privileged tx execution foundation) / static hosting, CDN, DNS (controlled as tamper surface = §9).

**Assumptions**: deliverables are static builds (no secrets on the server side). Target chain is Ethereum mainnet only (SYS-CON-005). Signature standards are EIP-712 / EIP-2612 (permit = DTKN-FR-007 / ZAP-FR-003,004 / VAULT-FR-003).

---

## 4. Actors, Roles, and Trust Boundaries

| Actor | Main surfaces | Trust |
| --- | --- | --- |
| Borrower / dToken holder / Earner / Redeemer | (A) User app | adversarial assumption (can sign only with their own wallet) |
| GOV_MULTISIG signer | (B) administrator console → Safe | trusted (but console holds no keys; final approval is in Safe) |
| ALLOCATOR | (B) administrator console | limited trust (only permitted operational actions; authority enforced on-chain) |
| GUARDIAN | (B) administrator console | trusted only for immediate incident stops; recovery belongs to GOV / Timelock |
| WRITEOFF | (B) administrator console | high-quorum limited trust for irreversible principal write-off |
| Oracle / Strategy owner or upgrader | (B) administrator console → Safe | contract-scoped trust; shared-Timelock and direct routes are distinguished per action |
| Operations / monitoring staff | (C) Private Operations Monitor | authenticated, read-only |
| Public viewer (not connected) | (A)(D) | read-only |
| RPC / subgraph / statistics API | all surfaces | semi-trusted (availability only; values displayed only after freshness and consistency checks) |
| Hosting / CDN / DNS / dependency packages | all surfaces | **tamper surface** (controlled by §9 SEC) |

**Trust-boundary key point**: all authorization is enforced on-chain (contract `onlyOwner` / role). Frontend access control (SEC-007) is only an **additional defense-in-depth layer**. If the frontend is compromised, the maximum attacker gain is "inducing users to sign malicious txs"; §9 reduces that through explicit approvals, simulation, and address verification.

---

## 5. Screens and Route Structure (Terse, Non-Normative)

Implementation routes may change, so this table is non-normative. Normative requirements are in §6 FR.

| Surface | Screen (route example) | Main corresponding FR |
| --- | --- | --- |
| (A) User app | Dashboard `/` | FRNT-FR-012,019,020 |
| (A) | Borrow `/borrow` / `/borrow/:coll` and position `/loan` | FRNT-FR-013,014 |
| (A) | Vault withdrawal (dToken redeem, claim) `/vault` | FRNT-FR-015,016 |
| (A) | Earn `/earn/:pool` | FRNT-FR-017 |
| (A) | Redemption `/redeem` and shutdown redemption `/redeem/shutdown` | FRNT-FR-018 |
| (A) | History `/transactions` and account `/account` | FRNT-FR-020 |
| (A) | Upstream Stake / Multiply surface removal | FRNT-FR-022,023 |
| (B) Administrator console | Proposal builder / timelock queue / allocate / pause | FRNT-FR-024..030 |
| (C) Private Operations Monitor | Branch / oracle / Vault and Strategy / Treasury / alert state | FRNT-FR-031..035 |
| (D) Dune Public Analytics | Public on-chain history and transparency | FRNT-FR-033,034,036 |

---

## 6. Functional Requirements FR

### 6.1 Shared Foundation

### FRNT-FR-001: Machine-Generated Chain and Contract Bindings
- **Type**: Functional | **Source**: FE Principle 4 / SYS-CON-005
- **Target**: all surfaces (build and configuration)
- **Purpose**: derive referenced addresses and chain configuration uniquely from deploy artifacts, eliminating handwritten misconnection.
- **Requirements**:
  1. Contract address sets are machine-generated from deployment artifacts (manifest) and imported into environment configuration. Do not place handwritten address definitions in source.
  2. Declare target chain ID in environment configuration and reconcile with the actual wallet/RPC chain ID (FRNT-ERR-003 on mismatch).
  3. Do not mix bindings for multiple environments (mainnet / test environment) inside one build. The environment is uniquely fixed at build time.
- **Failure behavior**: missing required binding causes build failure (FRNT-FR-004).
- **Verification**: build / ci-guard / e2e-local

### FRNT-FR-002: Single Source for On-Chain Constants
- **Type**: Functional | **Source**: FE Principle 4 / Parameters.md §0-2
- **Target**: all surfaces (constant layer)
- **Purpose**: structurally prevent divergence between frontend-side mirrors and sources of truth (`Constants.sol` / on-chain values / [Parameters.md](../../../Parameters.md)) for contract constants and branch parameters such as MIN_DEBT, MCR/CCR/SCR, decimals, etc.
- **Requirements**:
  1. Branch-specific parameters (MCR, etc.) are read **from on-chain** in principle (not fixed at build time).
  2. Unavoidable constant mirrors (MIN_DEBT for input validation, etc.) are subject to automatic generation from sources of truth or CI reconciliation (FRNT-INV-002).
  3. Display text that references constant mirrors (minimum borrow warnings, etc.) is dynamically rendered from the mirror value (forbid hardcoded numeric text).
- **Failure behavior**: CI reconciliation mismatch blocks merge.
- **Design notes**: Permanently eliminates by CI the class of issue proven in local verification: frontend constants/text not following contract-side MIN_DEBT changes.
- **Verification**: ci-guard / unit

### FRNT-FR-003: Machine-Generated ABI and Types
- **Type**: Functional | **Source**: FE Principle 4
- **Target**: all surfaces (build)
- **Requirement**: referenced ABIs are generated from contract build artifacts; no handwritten ABIs. Types derived from subgraph schema are obtained by code generation, and CI verifies freshness (schema-change follow-through) of generated artifacts.
- **Verification**: build / ci-guard

### FRNT-FR-004: Fail-Fast Environment Schema Validation
- **Type**: Functional | **Source**: FE Principle 4
- **Target**: all surfaces (build and startup)
- **Requirements**:
  1. Declare every environment variable in a schema with required/optional status, type, and format (address / URL / flag), verify at build time, and fail build on missing/invalid values.
  2. Treat missing optional items as explicit per-feature disablement (hide screen/banner, etc.), not runtime exceptions.
  3. Do not place secrets (writable API keys, etc.) in client-public environment variables.
- **Verification**: build / unit

### FRNT-FR-005: Wallet Connection
- **Type**: Functional | **Source**: FE Principle 3
- **Target**: (A)(B)
- **Requirements**:
  1. Support at least one path each for injected-wallet detection via EIP-1193 / EIP-6963, WalletConnect, and hardware wallets.
  2. Provide no input field for private keys or mnemonics.
  3. Provide **read-only watch** for arbitrary addresses (support, audit, self-check; no signing actions).
  4. Fully display read-only screens (dashboard and statistics) even when not connected.
  5. On a resettable devnet, the TopBar may expose a test ETH / USDC funding action for the connected wallet between the operations navigation and language switcher. Gate it by both devnet chain ID and deployment flavor, and never render or execute it in a mainnet build. ETH funding must not reduce an existing balance, and USDC minting must wait for a successful receipt before showing completion.
  6. On disconnected write surfaces, do not pair a disabled transaction CTA with an inline connection link. Present wallet connection as the single full-width primary CTA, with a label that makes clear the operation can continue after connecting.
  7. On arbitrary-address watch surfaces, compare the viewed address with the connected wallet. When disconnected or mismatched, identify the view as read-only near the address and do not imply that write actions use the viewed address rather than the connected wallet.
  8. When an arbitrary-address watch has no positions, show an empty state for that address rather than replacing it with new borrowing or earning actions intended for the connected wallet owner.
  9. Show Account collateral-claim guidance only when a positive claim balance exists. While watching an arbitrary address, keep the balance read-only and replace collateral-redemption links with an explanation that the address owner wallet must be connected.
- **Verification**: e2e-local / manual

### FRNT-FR-006: Transaction Lifecycle
- **Type**: Functional | **Source**: FE Principle 2,3
- **Target**: (A)(B)
- **Purpose**: detect failure before sending and let users track state after sending.
- **Requirements**:
  1. Always simulate (`eth_call` / gas estimation) before signature requests; disable sending UI and show reason for txs expected to fail (FRNT-INV-003).
  2. Explicitly show pending / confirmed / failed transitions, and preserve tracking of submitted txs across navigation and reload until confirmation.
  3. Decode custom errors on failure and display human-readable reasons (FRNT-ERR-004).
  4. Visualize multi-step flows (approve → main operation, etc.) as progress steps and support resuming after interruption.
- **Verification**: e2e-local / component / unit

### FRNT-FR-007: Minimal and Explicit Approvals (approve / permit)
- **Type**: Functional | **Source**: DTKN-FR-007 / ZAP-FR-003,004 / VAULT-FR-003
- **Target**: (A)
- **Requirements**:
  1. Offer permit only in flows where the permit signature through the target entrypoint is implemented and verified end-to-end. Unimplemented Day-1 flows use exact-amount approve; legacy localStorage approve-method preferences (including `permit` and unlimited approval) are discarded while stored loan IDs are kept.
  2. Approvals newly issued by this app are always limited to **the amount required for that operation** (for close, capped at the required amount plus the 0.1% execution buffer); unlimited approvals are not offered and no approve-method selector is shown.
  3. Approval UI always shows spender address, amount, and target asset.
  4. Approvals involving dToken/Underlying decimals conversion or rounding pin the converted raw amount in the request so the approval UI, allowance check, approve argument, and main tx use the same value.
  5. After a main operation that uses an exact-amount approval newly issued by this app, any allowance that can remain with a known spender is bounded to the rounding/execution-buffer portion (for close, at most 0.1% of the debt). Pre-existing allowances separately configured through a wallet, explorer, or other client are outside this guarantee. Approvals that include a buffer explain its rationale in the approval step, and the UI never claims unused allowances disappear automatically.
- **Verification**: e2e-local / component

### FRNT-FR-008: Data Source Role Separation and Freshness Management
- **Type**: Functional | **Source**: FE Principle 2
- **Target**: all surfaces
- **Requirements**:
  1. Fix the authoritative source for each data type according to the matrix in §7 (balances, prices, parameters = RPC / histories and lists = subgraph / market auxiliary data = statistics API).
  2. Measure divergence between subgraph synced block and chain head, and show a freshness warning when threshold is exceeded (FRNT-ERR-002).
  3. Statistics API references only DF-managed endpoints (do not reference upstream vendor URLs in production). For Day-1 public health metrics, the initial backend is the static JSON generated by `frontend/ops export-stats`; displays that require missing time-series aggregation such as observed APR remain disabled (FRNT-TBD-004).
  4. Advanced users may be allowed to override RPC / subgraph endpoints (default is official configuration).
  5. A public-stats or subgraph failure must not gate queries for RPC-authoritative prices, branch debt, SP deposits, or ActivePool aggregates. Indicators backed by successful direct RPC reads remain available while only metrics that require the auxiliary endpoint, such as historical windows, degrade to unavailable.
- **Verification**: e2e-local / unit / monitor

### FRNT-FR-009: JPY-Denominated Display and Numeric Conventions
- **Type**: Functional | **Source**: SYS-FR-005 (JPY-denominated) / FE Principle 5
- **Target**: all surfaces
- **Requirements**:
  1. Amounts and prices default to JPY denomination, with currency symbol, grouping, and decimal digits unified by locale (ja-JP baseline). Eliminate reuse of USD symbols.
  2. Perform calculations on 18dec values with a fixed-point decimal library; do not use floating point for amount calculations.
  3. Round displays against the user's benefit (expected receipts round down; required amounts/payments round up). Note that finalized values are sourced from on-chain calculation.
  4. Show source and acquisition time for conversion rates (Underlying ↔ dToken = DTKN-FR-003, collateral ↔ JPY) where applicable.
  5. Do not present a price-query acquisition time as the oracle update time. Primary collateral-price flows distinguish live, frozen, and unavailable by reading the active PriceFeedProxy source directly. The new-borrow screen shows that source state and the price-read time immediately below the collateral price so they are visible while entering amounts.
- **Verification**: unit / visual / component

### FRNT-FR-010: Internationalization (i18n)
- **Type**: Functional | Priority: Should | **Source**: market characteristics (Japan-first market)
- **Target**: (A)(C)
- **Requirement**: externalize display text into a text catalog and support a structure capable of providing Japanese and English locales (delivery order is FRNT-TBD-008). Suppress newly added hardcoded strings with lint.
- **Verification**: build / component

### FRNT-FR-011: JPY DeFi / JPYdf Brand Wording
- **Type**: Functional | **Source**: Development-Plan cross-cutting backlog (decided) / Product-Overview §12
- **Target**: (A)(C)
- **Requirements**:
  1. Use **JPY DeFi** for display names that refer to the service, protocol, app, documentation, or admin / operations surfaces. This includes headers, page titles, frontend metadata, wallet connection names, network labels, and agent discovery.
  2. Use **JPYdf** for the stablecoin, token symbol, amount unit, the asset used by Borrow / Repay / Redeem / Earn, and currency pairs.
  3. Replace display-layer "BOLD" with "JPYdf" in token contexts. Normalize token/data model names in owned frontend code (for example request schemas, local storage keys, query keys, flow IDs, and reward fields) to JPYdf naming, and do not retain unnecessary BOLD compatibility names.
  4. Technical identifiers such as upstream package names (for example `@liquity2/*`), repositories, packages, environment variables, contract artifacts / classes, and base protocol references are outside the display-name replacement scope. The audit-submitted `contracts/` tree and its current runtime metadata are also outside this change and require separate post-audit approval.
  5. Replace upstream brand assets (Liquity logo, external links) with DF official assets (link ledger in FRNT-SEC-005). Confirm completion with a full grep of the target surfaces and review.
- **Verification**: visual / manual

### 6.2 (A) User App

### FRNT-FR-012: Dynamic Support for 8 Branches
- **Type**: Functional | **Source**: SYS-CON-005 / Parameters.md §1
- **Target**: all (A) screens
- **Purpose**: remove hardcoding based on upstream's 3-collateral assumption (ETH/wstETH/rETH) and handle the Day-1 8 branches in [Parameters.md](../../../Parameters.md) §1 (and future added/placeholder branches) through configuration.
- **Requirements**:
  1. Branch count, token identifiers, icons, and display names are derived from bindings (FRNT-FR-001) and token registry; do not rely on hardcoded collateral symbol enumerations (union types / branches) in code.
  2. Screens can interpret per-collateral differences (Underlying decimals, peg type, placeholder/inert state).
  3. inert (inactive) branches are hidden from lists or shown non-operable as "preparing" (consistent with Day-2 enablement in ORCL-FR-008,009).
- **Verification**: e2e-local / component / unit

### FRNT-FR-013: Borrowing Flow (1 Tx Aggregation)
- **Type**: Functional | **Source**: SYS-FR-001 / ZAP-FR-001..004 / VAULT-FR-001 / DTKN-FR-004
- **Target**: (A) borrow screen
- **Implementation sync note**: Production PASS requires `DeployLiquity2` to wire `CollateralYieldZapper` into the two active dToken branches (dwstETH / dUSDC) and the user app to execute `Underlying -> dToken -> Trove` through that Zapper. There is no WETH branch; native ETH is accepted only through the dwstETH branch's native-ETH on-ramp (ETH -> Lido stETH -> wstETH, [Zapper](Zapper.md) ZAP-FR-015) when it was enabled at deployment, with an ETH input mode that converts inside the same open transaction. Branches 2–7 are inert and must have no borrow route or public slug. `/borrow` directly renders the Open Borrow screen with the first public collateral of the release definition selected, and the in-form collateral selector switches among public collaterals; `/borrow/:collateral` remains the per-collateral canonical deep link. Unknown slugs and multi-value params fail as 404 instead of being coerced to the first branch.
- **Requirements**:
  1. User input is fundamentally **Underlying-denominated**, and internal dToken wrapping (deposit → openTrove) is aggregated into 1 Tx through Zapper (direct path remains permitted by ARCH-005).
  2. The Borrow entrypoint, collateral selector, and Open Borrow screen use Underlying for the primary dToken-branch display (label / icon / canonical URL slug; for example the internal `dwstETH` branch is linked as `/borrow/wsteth` and shown as `wstETH`). The internal `symbol` / branch key / contract lookup / oracle lookup / subgraph lookup remains the dToken symbol, and Vault / Admin / Ops / direct dToken management screens keep dToken display.
  3. The Borrow screen's available collateral displays `Underlying wallet balance` in Underlying units even for dToken branches. On the dwstETH branch, when the native-ETH on-ramp (ZAP-FR-015) is enabled, an ETH input mode is offered separately from the Underlying input, and the ETH mode is blocked while the route is unavailable (staking pause, stake limit, etc.). On send, the Zapper wraps any required Underlying shortfall into dToken. Direct use of an existing dToken balance is not part of the Day-1 Borrow open UI path.
  4. The Borrow screen's collateral price display is the **effective collateral value** after dToken backing ratio, not the raw Underlying spot price. When backing ratio is below 100%, warn that borrowing remains possible but the Core dToken claim is against remaining backing.
  5. Input validation checks MIN_DEBT (mirror from FRNT-FR-002), MCR/CCR, balance, approval state, and dToken cap before sending, and blocks sending with reasons on violations. A `mintCap = 0` branch must not generate an open request even through a direct route.
  6. Provide user-set interest rate (manual/delegated), and display effective APR, policy anchor, and Redemption risk indicators for the selected setting (debt in front / ahead ratio against branch debt / rate distribution). The initial policy anchor is sourced from public stats `borrowRatePolicies` and launch-evidence business input; do not present it as guaranteed yield or fixed cost.
  7. Disclose in details (collapsible) that deposited collateral is dToken on Core (transparency under FE Principle 5).
  8. Referral may capture slugs from URL query (`ref` / `referral` / `referralCode`) and persist them under the JPYdf localStorage namespace. The frontend must not convert arbitrary slugs into bytes32 codes. If `NEXT_PUBLIC_REFERRAL_REGISTRY_URL` is unset, unavailable, or does not return an active entry, the frontend must not pass a referral code to `openTroveWithRawETHAndReferral` and must keep the normal no-referral entrypoint. After registry enablement, only a canonical bytes32 returned by an active registry entry may appear in the transaction preview; unknown / expired / paused / not-started / cleared states are treated as no-referral.
- **Failure behavior**: block new borrowing in the UI during branch shutdown / oracle failure (FRNT-ERR-005).
- **Verification**: e2e-local / component

### FRNT-FR-014: Position Management (Adjust, Repay, Close, Change Interest)
- **Type**: Functional | **Source**: ZAP-FR-005..010 / 🔵 Core (Liquity-v2-Core-Spec)
- **Target**: (A) position screen
- **Implementation sync note**: Production PASS requires collateral decrease and close-with-held-JPYdf through `CollateralYieldZapper` or an explicit dToken receipt + Vault redeem sequence. `repayWithCollateral` / flash-close / collateral-funded repay / Multiply are absent from the Day-1 ABI. Any future asset-specific pre-leg requires a separately audited entrypoint and activation package.
- **Requirements**:
  1. Provide collateral increase/decrease, debt increase/decrease, simultaneous adjustment, and close when holding JPYdf. Flash Loan close without holding JPYdf / collateral-funded repay / Multiply are not provided in the Day-1 UX.
  2. Default proceeds for collateral decrease / close to Underlying denomination (ZAP-FR-006,010). Because insufficient Vault Buffer creates a delayed `WithdrawRequest`, do not use wording that guarantees immediate receipt.
  3. Show interest adjustment, delegation, and batch participation state; render zombie-state (below MIN_DEBT) restriction text from the FRNT-FR-002 mirror value.
  4. Show preview of post-adjustment ICR, liquidation price, and Redemption risk before sending.
- **Verification**: e2e-local / component

### FRNT-FR-015: dToken Vault Withdrawal (redeem / claim)
- **Type**: Functional | **Source**: SYS-FR-002 / VAULT-FR-001 / `VAULT-FR-002` / VAULT-FR-003 / DTKN-FR-003
- **Target**: (A) Vault withdrawal screen
- **Purpose**: provide the operation surface for converting dToken holdings independent of Troves back to Underlying, and for tracking / claiming delayed WithdrawRequests when the Buffer is insufficient.
- **Implementation sync note (2026-06-23)**: the Day-1 user app does not expose a standalone `CollateralVault.deposit` mint UI. Underlying ingress into Core collateral is consolidated into the Borrow/Zapper flow (FRNT-FR-013), and `/vault` is scoped to dToken -> Underlying redeem / queued claim. Direct deposit remains possible through the contract path under ARCH-005, but is not the user app's primary surface.
- **Requirements**:
  1. Provide dToken → Underlying (redeem / redeemWithPermit), and show that a redeem can split into immediate payout and a delayed WithdrawRequest.
  2. On redeem, show an **estimate** before sending of either "immediate receipt" or "enters delayed redemption queue" depending on Buffer sufficiency. Do not use wording that guarantees immediate receipt (FE Principle 5).
  3. Show Buffer balance, Backing ratio, per-branch withdrawDelay ([Parameters.md](../../../Parameters.md) §2-B), and unclaimed queue state.
- **Verification**: e2e-local / component

### FRNT-FR-016: Delayed Redemption Queue and claim
- **Type**: Functional | **Source**: VAULT-FR-006 / SYS-NFR-004
- **Target**: (A) Vault withdrawal screen
- **Requirements**:
  1. Show the user's WithdrawRequest list (amount, creation time, expected claim availability, status).
  2. Provide claim action for requests that are claimable, and represent as state that claim can still fail due to insufficient funds, etc. (wording must assume indefinite delay is possible).
  3. Show queue-wide size (total unclaimed amount) so users can estimate delay severity.
  4. When a request is waiting for buffer refill, clearly state that it remains on-chain and does not need to be resubmitted. A positive `withdrawDelay` is an on-chain hard lock from queue creation until `claimableAt`; early strategy-fund or buffer recovery does not shorten it. For synchronous-recovery configurations with `withdrawDelay == 0`, show that there is no time lock and the request becomes claimable as soon as the buffer refills. Buffer recovery timing is not guaranteed in either case, so do not present it as an expected payout time.
  5. Do not conflate buffer shortfall and backing shortfall. Temporary liquidity shortage with `backingRatio() == 1e18` and incidents with `backingRatio() < 1e18` must use separate warnings / copy.
- **Verification**: e2e-local / component

### FRNT-FR-017: Earn (Stability Pool)
- **Type**: Functional | **Source**: SYS-FR-004 / 🔵 Core SP
- **Target**: (A) Earn screen
- **Implementation sync note (2026-06-25)**: `/earn` is a pool-selection list, and pool screens render only when `/earn/:pool` or `/earn/:pool/:action` matches a public slug / action. Missing pool slugs, unknown slugs, unknown actions, and multi-value params must not be filled from the first pool or deposit tab; they fail as 404.
- **Requirements**:
  1. Provide deposit, withdrawal, and reward (JPYdf yield + liquidation collateral) claim / compound for branch-specific SPs.
  2. Deposit is capped only by the user's JPYdf balance; do not imply linkage to a borrowing position.
  3. APR display states source (observed period), and does not guarantee future yield. Do not display SP additional rewards (Treasury-derived) until finalized (FRNT-TBD-003).
  4. Show SP coverage, outside debt, branch debt, and covered / thin-SP state per branch so depositors can judge which debt range the SP may absorb.
  5. For dToken branches, show backing ratio, Vault buffer, withdraw delay, strategy exposure, JPYdf/USDC exit liquidity, and redemption fee / base rate in the same decision context.
  6. Do not describe SP as the repair fund for dToken / Strategy impairment. Impairment is reflected through backing ratio and collateral value; repair belongs to strategy recovery / writeoff / backstop.
  7. Current interest-derived APR may be calculated from ActivePool aggregate debt / weighted debt and SP deposits through RPC. APR windows that require history, such as seven-day actuals, follow public-stats freshness and must not be silently backfilled with the current APR under the same period label.
  8. For dToken branches, state beside the pool reward display that liquidation collateral is received as a collateral claim rather than as Underlying, and that conversion to Underlying follows the Vault's instant buffer and delayed-claim queue conditions. Display the live contract `withdrawDelay`; do not imply immediate receipt or guaranteed liquidation profit.
- **Verification**: e2e-local / component

### FRNT-FR-018: Redemption
- **Type**: Functional | **Source**: SYS-FR-004 / 🔵 Core Redemption / ORCL-FR-005
- **Target**: (A) Redemption screen
- **Implementation sync note (2026-06-23 / 2026-06-25)**: normal redemption is provided at `/redeem`, and branch-shutdown urgent/shutdown redemption is provided at `/redeem/shutdown`. No legacy compatibility route is kept; agent discovery, sitemap, and public docs expose only the canonical route.
- **Requirements**:
  1. Provide redemption into "collateral worth 1 JPYdf = ¥1 equivalent" with expected receipt, current redemption fee, and target branch allocation.
  2. Display fees as **borne by the redeemer** (do not describe them as borrower cost). State that the fee is not an additional JPYdf payment but a deduction from the collateral returned by each branch. For an aggregate normal redemption routed across multiple collateral types, show the current fee rate and a face-value JPY equivalent; do not use a JPYdf token icon or unit that implies payment in JPYdf. Round the estimated equivalent against the user.
  3. Put borrower-facing impact explanation (for receiving Redemption) near the interest-setting UI (FRNT-FR-013 requirement 3).
  4. For dToken branches, expected receipt and branch-allocation displays are user-facing collateral claims (for example `wstETH claim`), and conversion to Underlying is shown as a separate `/vault` Vault withdrawal path.
- **Verification**: e2e-local / component

### FRNT-FR-019: Branch Health and Backing Ratio Display
- **Type**: Functional | **Source**: ORCL-FR-014 / VAULT-FR-016,018 / SYS-INV-002
- **Target**: (A) dashboard and branch screens
- **Requirements**:
  1. Show per-branch TCR, total debt, SP balance, Shield (redemption shielding) state, and shutdown state.
  2. Show dToken backing ratio, and warn on operation screens for branches below 1 (principal impairment being reflected). The value definition is sourced from VAULT-FR-016 / ORCL-FR-014 and is not redefined here.
  3. Warnings show facts (ratio, source, reference block) and do not predict recoverability.
  4. Compare the collateral value of current claim-token supply with deposit capacity and label it "Collateral value / app limit" or "Collateral value / on-chain limit". Show live branch debt as "JPYdf borrowed" without a redundant explanatory line beneath it. Collateral value and debt are not expected to match because loans are overcollateralized; explain their relationship through TCR. Do not expose internal Day-1 debt-plan comparisons or describe a dToken deposit limit as an on-chain JPYdf debt ceiling.
  5. Show the Vault instant-withdrawal buffer and queued claims as separate values with units. When `withdrawDelay` is a whole number of 24-hour days, display days (for example, 3 days) instead of accumulated hours (for example, 72 hours).
  6. Explain Shield state in terms of SP coverage and normal-redemption ordering. User-facing banners must avoid relying on "debt outside SP coverage" jargon; state plainly that other collateral branches are prioritized because Stability Pool deposits exceed the shielded branch's debt. `MIN_ANNUAL_INTEREST_RATE` (0.5%) is the always-available global lower bound for every Trove; do not present it as a rate unlocked by SP coverage.
- **Verification**: e2e-local / component / visual

### FRNT-FR-020: Position and History Listability
- **Type**: Functional | **Source**: SYS-NFR-005
- **Target**: (A) dashboard and history screen
- **Requirements**:
  1. Cross-list Troves, SP deposits, dToken balances, and delayed redemption queue for the connected (or watched) address.
  2. Show operation history (borrow, adjustment, liquidation, redemption hit, claim) chronologically from subgraph, following freshness warning rules (FRNT-FR-008).
  3. Maintain display consistency after ownership transfer, assuming individual Troves are transferable NFTs.
  4. For dToken branches, balance, collateral-surplus, and history displays are collateral claims, and they show that conversion to Underlying is a separate Vault withdrawal operation.
  5. Use the subgraph `updatedAt` changed by a redemption hit for the individual Trove redemption timestamp; do not substitute the borrower's `lastUserActionAt`.
  6. Provide a primary-navigation account screen that crosses balances, loans, SP deposits, collateral claims, and delayed redemption queues. `/transactions` prioritizes active or saved transaction-flow recovery; account activity is secondary when no flow exists.
  7. Loan and Stability Pool empty states link to their corresponding new actions. A data-source failure is not an empty state and retains retry and support-ID controls.
  8. The new-borrow screen presents the user's collateral input, collateral valuation, projected debt, LTV, and liquidation price before branch-wide operational metrics. Projected debt and risk metrics are not shown as final until the upfront fee is available.
  9. When the subgraph is unconfigured or unavailable, discover candidate Trove IDs from TroveNFT `Transfer` logs addressed to the watched account across every configured branch, then revalidate the current `ownerOf`, Trove status, and latest Trove data through RPC. Browser-stored Trove IDs are hints only and must not determine completeness for watched addresses or another browser. A log-discovery or revalidation failure is not reported as zero positions and exposes retry and a support ID.
  10. A loan detail opened from an account card returns to the account screen for the current owner from the latest loan data. When the whole card is a link, it does not contain another interactive button or link.
  11. When an active loan detail is viewed while disconnected or with a wallet other than the owner, identify the owner and state that the loan is read-only. Collateral, debt, rate, and close write actions remain disabled until the connected wallet matches the owner.
  12. An active loan detail identifies when the on-chain JPY/USD source is frozen, stale, invalid, or when its freshness/freeze state cannot be read. It does not add an oracle banner while the source is healthy or during the initial status read.
  13. When auxiliary redemption-ranking data cannot be read, show it as unavailable; while it is loading, show it as checking. Do not present either state as not applicable or low risk. Keep this distinction consistent across Account, loan details, borrowing, rate changes, delegate selection, and transaction previews.
  14. Home and Account each have exactly one page-level `h1`, use `h2` for major regions such as position lists and comparison tables, and use `h3` for position and action cards within those regions. Heading levels are not skipped merely to obtain a visual size.
  15. A Stability Pool detail uses the displayed pool name as its page-level `h1`; the pool list uses each pool name as an `h2` under the list page `h1`. Reuse of the same summary inside a transaction preview does not promote it to an independent page heading.
  16. A modal is exposed to assistive technology as a named modal dialog, with its title as `h1`, major dialog sections as `h2`, and nested table groups or equivalent subsections as `h3`. Read-only environment value fields also use their displayed key as the accessible name. Reopening a closed modal resets its scroll position to the start so that its title and close action are immediately available.
  17. Narrow-screen primary navigation opens as a named modal dialog and places initial focus on an explicit close action. The backdrop is not focusable; after Escape or the close action, focus returns to the trigger. The current page is identified with `aria-current="page"` on its link.
  18. History queries recover owner-close and liquidation records from `previousOwner` after an NFT burn changes `borrower` to the zero address. Subgraph `status=redeemed` only identifies the latest operation as a redemption; it is not treated as proof that a Trove ended or was fully redeemed, and only the redemption-hit history is shown.
  19. An amount shown on a history row is backed by an event value or historical snapshot for that timestamp. The latest Trove entity debt or collateral is not presented as the value at an earlier opening or adjustment; when the historical value cannot be reconstructed, the UI identifies it as unavailable.
  20. The RPC Trove status is authoritative for a current position's lifecycle (open, owner-closed, or liquidated). Subgraph `status=redeemed` does not override that current state; redemption hits are presented from history fields such as `redemptionCount`. A Trove that remains active or zombie on-chain after a partial redemption remains in open-loan counts, lists, and action paths.
  21. If refreshing account balances, loans, Stability Pool positions, or liquidation surplus fails after the last successful query result was cached, retain the value but label it as last-known and expose a warning, retry, and support ID. A cached empty array must not become a successful empty state or expose new-borrow/deposit CTAs. If liquidation surplus cannot be read, do not classify it as zero or claimed; keep the liquidated loan visible with an unresolved claim status.
  22. On loan details, do not treat a refresh failure as success merely because query cache still contains collateral price, oracle freshness, branch shutdown, branch debt/TCR, upfront fee, latest Trove data, or a wallet balance required by the action. Retained values are reference-only and the UI exposes retry and a support ID. Do not create collateral/debt update, interest-rate update, or close write requests until every required read succeeds. Failure of a reference price that is not used in close calldata does not block closing.
- **Verification**: e2e-local / component

### FRNT-FR-021: Risk and Disclaimer Display
- **Type**: Functional | **Source**: FE Principle 5 / SYS-NFR-002
- **Target**: all (A) operation screens
- **Requirements**:
  1. Display liquidation risk (liquidation price, ICR), Redemption risk, delayed redemption possibility, and smart-contract risk in the context of each applicable operation.
  2. Forbid definitive wording about yield or "risk-free"; state assumptions (market-dependent, not guaranteed) in the body.
  3. Keep a configuration framework for geoblocking / blocklists in case jurisdiction-specific restrictions become necessary (default disabled; triggering decision is outside this document).
- **Verification**: visual / manual / component

### FRNT-FR-022: Remove Upstream Governance UI (Stake)
- **Type**: Functional | **Source**: FE Principle 1 / Product-Overview §4.1 (DFT)
- **Target**: (A)
- **Requirement**: Remove upstream LQTY staking / V1 integration / upstream governance screens and banners from the JPYdf user app surface. DFT staking and governance UI will be added as separate requirements after design finalization (FRNT-TBD-001). Reintroduction requires a separate spec for JPYdf-owned governance sources, contract address policy, user-facing copy, and admin/runbook handling.
- **Verification**: visual / build

### FRNT-FR-023: Multiply (Leverage) Gate
- **Type**: Functional | **Source**: FE Principle 1 / ZAP-TBD-004 (dToken leverage not designed)
- **Target**: (A)
- **Requirement**: Hide leverage UI through a configuration flag until JPYdf DEX liquidity and leverage route configuration are established (FRNT-TBD-002). When disabled, hide not only navigation and cards but also guard direct `/multiply` access at the route level with a 404-equivalent outcome. When enabled, price impact and slippage tolerance display are mandatory. On dToken branches, Multiply open / update remains unsendable until ZAP-TBD-004 dToken leverage design and ZAP-TBD-010 swap route production enablement are resolved and a dedicated router is added.
- **Verification**: build / visual

### FRNT-FR-038: Public User Operation Coverage and Execution Paths
- **Type**: Functional | **Source**: ARCH-005 / production permissionless surface / FRNT-FR-006,007
- **Target**: all write operations and internal read helpers in (A)
- **Requirements**:
  1. Enumerate every state-changing production entrypoint that does not require a privileged caller, based on production ABIs and source-level caller checks, and map it to public-app treatment in [Permissionless User Operations](Permissionless-User-Operations.md). Use component plus function name (and an identifiable signature for overloads) as the stable row key, and reference the applicable `FRNT-*` requirements.
  2. For every operation offered by the public app, the user goal, route, selected entrypoint, conditional visibility, spender, asset, and receiver must match that matrix. When an Underlying-denominated Zapper or protected Helper fulfills the same goal as a direct Core call, do not add a duplicate direct-operation UI.
  3. When a non-view helper is used only to quote, truncate, or fetch a price, call it through `eth_call`; do not create a user signature or transaction request.
  4. Do not add standalone public-app UI for standard token/NFT management, third-party managers, batch-manager administration, keepers/bots, Strategy maintenance, incentive distribution, or optional utilities without complete requirements. Lack of UI is not on-chain access control.
  5. Any addition, removal, caller restriction, or standard-path change to a permissionless entrypoint must update the matrix, related `FRNT-*`, transaction-flow tests, and required E2E fixtures in the same change.
- **Verification**: ci-guard / unit / component / e2e-local

### 6.3 (B) Administrator Console

### FRNT-FR-024: "Preparation and Visualization" Model for Privileged Operations
- **Type**: Functional | **Source**: FE Principle 3 / SYS-FR-007
- **Target**: all (B) functions
- **Purpose**: safely prepare and verify GOV_MULTISIG / GUARDIAN / ALLOCATOR / WRITEOFF / owner and upgrader operations in a console that holds no keys.
- **Requirements**:
  1. The console constructs calldata, simulates, and displays diffs; execution is delegated to Safe (or the wallet holding the role).
  2. Show current values and on-chain permissions (Owner / role holder) for the target. Warn during preparation for actions that cannot be executed by addresses without authorization.
  3. Even for a placeholder / inert branch, Activation and Oracle operations are available once the admin contracts (dToken / CollateralVault / PriceFeedProxy) are deployed. Screens that presuppose underlying, such as Vault state / ALLOCATOR, are not shown for an inactive branch. An active branch with no Strategy (empty manifest `dfYield[i].strategies`) shows Vault state and treats the Strategy list as empty.
  4. Do not place renounce or permission-abandonment operations in the UI (consistent with DTKN-FR-009 / ORCL-FR-007 disablement policy).
  5. Preserve the selected branch and operation screen in URL query parameters so reviewers and operators can reopen the same context. Normalize invalid query values, disable unavailable screens for inert branches, and fall back to Activation.
  6. Do not infer an "active" operating state from manifest Underlying / Vault configuration alone. For configured branches, read on-chain `dToken.cap()` and Core `shutdownTime()`; display cap zero as dormant, a completed shutdown as stopped, and read failures as unavailable without failing open. Keep applicable administration and activation inspection available for dormant branches while distinguishing borrowable/live state from configured admin contracts. Within Vault state, present effective operation availability rather than pause flags alone: deposit also depends on dToken cap, and allocation also depends on `allocateMaxMove`.
  7. Every write action displays its required authority, authority holder, execution route, effect timing, and recovery actor in the same operation card. Timelock workflow roles (PROPOSER / EXECUTOR / CANCELLER) are not presented as the controlled contract's authority. Header, filters, and pending queue use the same Action Registry.
  8. Present the execution-principal selector as a caller used for role / owner reads and simulation `from`, not as a connected signing wallet. Production candidates are fixed in one structured build-time configuration as label + checksum-compatible address pairs that distinguish `Admin Safe`, `Guardian Safe`, and `Allocator Safe`. The production guard rejects missing labels, invalid / zero / duplicate addresses, duplicate labels, and simultaneous use of the legacy address-only config. The UI exposes the label and full checksum address for verification.
- **Verification**: e2e-local / component / unit / build / manual

### FRNT-FR-025: Parameter Change Proposal Builder
- **Type**: Functional | **Source**: DTKN-FR-006 / VAULT-FR-008,009,012 / STGY-FR-011
- **Target**: (B)
- **Requirements**:
  1. For each target (setCap / setBufferConfig / setAllocatorConfig / setWithdrawDelay / setTreasury / whitelist add/remove / addStrategy / updateStrategy / writeoffStrategyPrincipal, etc.), provide **current value → proposed value diff** and input validation.
  2. Validate [Parameters.md](../../../Parameters.md) and on-chain constraints at input time, including total Strategy weight, disabled weight, caps, and minimum post-writeoff backing ratio. If preview is unavailable, require explicit operator-supplied guard values.
  3. Only after successful simulation, generate a versioned artifact containing chain, target, value, calldata, decoded result, simulation block, creation metadata, and hash, plus Safe Transaction Builder-compatible JSON. Each artifact is one outer `CALL`; Timelock operations use Timelock as the outer target. Manual calldata transcription is not the routine path.
  4. Retrieve a Safe proposal through the read-only API and mechanically compare it with the artifact, Safe version, every signed field, nonce, and version-specific EIP-712 hash. Decode Timelock stage, inner payload, operation ID, salt, predecessor, and delay. Mark it verified only on a full match. Do not distribute secret credentials to the browser; attach them through a same-origin proxy limited to read-only endpoints. The [Admin Console Production Gate](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) governs deadlines, concurrency limits, killability, recovery, proxy flow limits, and external monitoring.
  5. For one-shot activation, show the dToken allowlist → metadata bind → Vault underlying bind order and its failure conditions. For upgrades, distinguish Owner from upgrader and generate only `upgradeTo`, subject to external storage-layout, bytecode, and codehash review.
  6. Do not generate a `revokeRole` that removes the last holder, a mainnet `updateDelay` inconsistent with `PRM-GOV-COMMON-TIMELOCK-DELAY`, renounce, or an unaudited `upgradeToAndCall`.
  7. The current LidoStrategy is retirement-only. Do not add it to the Action Registry; show an old snapshot only as read-only `retired` / `unknown`.
- **Verification**: unit / component / e2e-local

### FRNT-FR-026: Oracle Source Replacement Flow
- **Type**: Functional | **Source**: ORCL-FR-001,002,003 / ORCL-GOV-004
- **Target**: (B)
- **Requirements**:
  1. Visualize the sequence proposeSource → (timelock passes) → confirmSource → cancelSourceProposal when needed, with proposed source, remaining wait time, and confirm deadline.
  2. Provide pre-confirm validation (new source response and price reasonableness range) as simulation.
  3. Provide a cross-branch list of "current source / proposed source."
- **Verification**: e2e-local / component

### FRNT-FR-027: Emergency Operations (pause / unpause)
- **Type**: Functional | **Source**: VAULT-FR-014 / STGY ERR series
- **Target**: (B)
- **Requirement**: Prepare pause operations with explanation of impact scope (functions stopped, functions continuing) and double confirmation. After execution, show whether it is reflected in the user app announcement banner (FRNT-ERR-006).
- **Verification**: e2e-local / manual

### FRNT-FR-028: ALLOCATOR Operations Screen
- **Type**: Functional | **Source**: VAULT-FR-004,005 / STGY-FR-001..005
- **Target**: (B)
- **Requirements**:
  1. Show per-branch current buffer state (target ratio, surplus) and per-Strategy allocation state, and for allocate amount input show **estimated post-execution impact on buffer and backing ratio**.
  2. Allow viewing Strategy push (receiveFromStrategy) history and yield performance.
  3. Only whitelisted Strategies appear as allocation destinations.
  4. Display Strategy kind distinctly as `aave-v3` / `erc4626` / `morpho-v2` / `sky-susds` / `etherfi-weeth` / `retired` / `unknown`. `lido` is not an active kind: historical Lido snapshots are converted to a read-only `retired` / `unknown` display. For `retired` / `etherfi-weeth`, show pending request and claimed idle underlying state; for `sky-susds`, show own sUSDS shares, idle USDS, and max conversion loss on the same Strategy row.
- **Verification**: e2e-local / component

### FRNT-FR-029: Timelock and Pending Operation Queue
- **Type**: Functional | **Source**: SYS-NFR-003 / DTKN-GOV-004 / ORCL-FR-002
- **Target**: (B)
- **Requirement**: List cross-module pending operations (dToken / Vault / Strategy / Oracle / Treasury): waiting for timelock, waiting for confirm, waiting for Safe signatures, and failed Safe execution. Display deadline, required action, required authority, execution route, outer / inner target, and owner. On reload, revalidate each artifact's chainId, Action ID, function, deployment target, current execution route, and shared Timelock address. A legacy direct artifact that now requires the shared Timelock, a wrong-chain / target / Timelock artifact, or a simulation older than one hour is not presented as waiting for signatures and must be regenerated. Group older copies of the same semantic operation as superseded.
- **Verification**: component / e2e-local / manual

### FRNT-FR-030: Operation Audit Trail
- **Type**: Functional | **Source**: SYS-NFR-005
- **Target**: (B)
- **Requirement**: Store and view privileged operations prepared/executed through the console (Action ID, required authority, route, outer / inner target, proposal contents, calldata, execution tx, executor, and integrity state) as a chronological audit trail. Decode known AccessControl role identifiers to role names. Where on-chain event indexing is sufficient, treat it as source of truth; the console-specific ledger is auxiliary.
- **Verification**: e2e-local / manual

### 6.4 (B) Private Operations Monitor / (C) Dune Public Analytics

This section defines target requirements; it does not imply implementation or
production readiness. Current surface status is authoritative in the
[Frontend Data Source Ledger](../../../engineering/verification-ledgers/Frontend-Data-Source-Ledger.md),
and implementation / verification status per requirement is authoritative in
the [Requirements Verification Ledger](../../../engineering/verification-ledgers/Requirements-Verification-Ledger.md).
Treat Dune as unimplemented until its query registry, live queries / dashboard,
Dune compilation and successful execution, RPC / event reconciliation,
freshness, and measured-credit evidence are complete.

### FRNT-FR-031: Branch Overview Monitoring
- **Type**: Functional | **Source**: SYS-NFR-005 / SYS-INV-001,004
- **Target**: (C)
- **Requirement**: Provide one-screen overview of every branch's TCR, SCR, CCR, MCR, total debt, SP balance, SP coverage, outside debt, liquidation/redemption occurrences, and shutdown / shield state. Show the TCR-to-CCR margin explicitly, and visually emphasize SP coverage below 100% and positive outside debt as thin-SP state.
- **Verification**: e2e-local / visual / monitor

### FRNT-FR-032: Oracle Monitoring
- **Type**: Functional | **Source**: ORCL-SEC-005 / SYS-RISK-001 / Parameters.md §2-C
- **Target**: (C)
- **Requirements**:
  1. Per branch, show current price, elapsed time since last update, margin against staleness threshold ([Parameters.md](../../../Parameters.md) §2-C is source of truth), lastGoodPrice fallback / shutdown state.
  2. Explicitly show **feeds shared by all branches**, such as JPY/USD, as independent monitoring targets.
  3. Display source replacement state (proposed and confirmed) from the same data source as (B).
- **Verification**: e2e-local / monitor / visual

### FRNT-FR-033: Vault and Strategy Monitoring
- **Type**: Functional | **Source**: VAULT-FR-016,017,018 / STGY-FR-006..009
- **Target**: (C) Private Operations Monitor (current state and incidents) + (D) Dune Public Analytics (public history)
- **Requirement**: The Private Operations Monitor shows per-branch buffer balance and target, allocated principal, Strategy valuation, valuation failures, backstop reserve, backing ratio, and pending withdrawals, emphasizing movement toward `A < L_effective`. Strategy emergency stops and valuation/cache failures are alertable, and authenticated operations can compare configuration transactions with immediate post-change state. Dune reconstructs, where events permit, public history for Strategy additions/updates/emergency stops/removals, yield/principal pushes, writeoffs, and backing ratio. Strategy-kind summaries distinguish `aave-v3` / `erc4626` / `morpho-v2` / `sky-susds` / `etherfi-weeth` / `retired` / `unknown`; Sky and Etherfi must not collapse into `unknown`, and historical Lido snapshots must not reappear as active.
- **Verification**: e2e-local / monitor / visual

### FRNT-FR-034: Treasury and Revenue Flow Monitoring
- **Type**: Functional | **Source**: VAULT-FR-007 / TRSY-FR series
- **Target**: (D) Dune Public Analytics + operations evidence
- **Requirement**: For Day 1, publish `transferYieldToTreasury`, Strategy `RewardTokenSwept`, and `InterestRouterForwarder.Routed` by branch, token, and transaction hash in Dune. Reconciliation against Safe external exports stays outside the browser bundle as operations evidence. Extend to distribution results after Day-2 Treasury adoption; do not present an unapproved SP additional-reward path as live.
- **Verification**: e2e-local / visual

### FRNT-FR-035: Alert Integration
- **Type**: Functional | **Source**: SYS-NFR-005 / EVT requirements in each component
- **Target**: (C) Private Operations Monitor (display) + browser-independent notification foundation
- **Requirements**:
  1. Deduplicate FRNT-FR-031..034 anomalies by alert key and transform them into notifications with severity, owner, destination, ACK deadline, and status (`triggered / acknowledged / escalated / resolved`).
  2. [Incident Notification Policy](../../../contributors/deltaforesight/operations/Incident-Notification-Policy.md) is the source of truth for thresholds, routing, public-announcement boundaries, payloads, state transitions, persistence, and delivery evidence. Notifications never execute on-chain actions automatically.
  3. When event history is unavailable, distinguish monitoring degradation from an absence of current-state anomalies; do not report “all systems normal.”
  4. Public surfaces expose only approved impact, status, and still-available operations. Keep internal owners, channels, ACK/escalation data, and secrets in authenticated operations surfaces.
  5. Dune schedules and alerts are not a source for critical alerts, ACK state, or public communications.
- **Verification**: monitor / manual

### FRNT-FR-036: Dune Public Transparency
- **Type**: Functional | Priority: Should | **Source**: SYS-NFR-002,005
- **Target**: (D) Dune Public Analytics
- **Requirement**: Publish on-chain metrics—supply, collateral composition, debt, rates, SP, liquidation/redemption, dToken, Vault/Strategy flows, and Revenue/Treasury—in Dune. Each metric has a query-registry entry with data source, SQL, owner, freshness, credit cost, and reconciliation method. The dashboard states that it is not a real-time monitor and shows its latest execution time; it excludes internal alerts, owners, channels, ACK/escalation, procedures, and private endpoints. User App current-health behavior must not depend on the Dune API.
- **Verification**: visual / manual

### FRNT-FR-037: Interaction Feedback and Motion Reduction
- **Type**: Functional | Priority: Should | **Source**: SYS-NFR-002
- **Target**: shared UI foundation for (A)(B)
- **Requirements**:
  1. Primary command controls provide immediate press feedback without layout shift; disabled controls do not show a pressed state.
  2. Do not add decorative motion to financial values, prices, balances, or risk charts. Reserve motion for command feedback, navigation, waiting, and errors where it improves state comprehension.
  3. Under `prefers-reduced-motion: reduce`, suppress CSS transitions/animations and JavaScript springs while retaining non-motion state cues such as color, text, progress, and errors.
  4. Use shared UI-kit easing tokens rather than adding arbitrary per-screen curves.
- **Verification**: UI-kit gallery build / compiled CSS artifact check / visual

---

## 7. State and Data Source Model

| Data type | Authoritative source | Auxiliary | Notes |
| --- | --- | --- | --- |
| Balance, allowance, current position value | RPC (contract reads) | — | Keep display block height |
| Price and backing ratio | RPC (PriceFeedProxy / Vault) | — | ORCL-FR-004,005,014 |
| Branch parameters (MCR, etc.) | RPC (on-chain values) | Parameters.md (reconciliation) | FRNT-FR-002 |
| Input-validation constants (MIN_DEBT, etc.) | generated constant mirror | CI reconciliation | FRNT-INV-002 |
| Lists and history (Trove list, operation history, interest distribution) | subgraph | — | with freshness verification (FRNT-FR-008) |
| Market and statistics (APR observed performance, etc.) | DF statistics API | public JSON from `frontend/ops export-stats` | Public health metrics are implemented. Time-series aggregation such as observed APR remains hidden until ready (FRNT-TBD-004) |
| Pending operations and timelock state | RPC + event index | subgraph | shared by (B)(C) |
| UI state (in-progress inputs, settings) | client local | — | do not persist asset information |

---

## 8. Consistency Invariants INV

- **FRNT-INV-001 (display matches on-chain)**: amounts, rates, and fees shown on operation confirmation screens are derived from RPC reads at the same reference block and have no differences except display rounding (FRNT-FR-009 requirement 3).
- **FRNT-INV-002 (constant mirror match)**: all constant mirrors held by the frontend are mechanically reconciled in CI against sources of truth (`Constants.sol` / [Parameters.md](../../../Parameters.md)) and are not released while mismatched.
- **FRNT-INV-003 (no signature request without simulation)**: every write operation must not proceed to wallet signature request without immediately preceding successful simulation.
- **FRNT-INV-004 (absence of secrets)**: frontend distributables, repository, and client-public environment variables contain no private keys, privileged API keys, or personal information.

---

## 9. Security Requirements SEC

- **FRNT-SEC-001 (supply chain)**: dependency packages are pinned by lockfile, and dependency additions/updates go through review and vulnerability audit. Do not load scripts from third-party domains at runtime (external communication by wallet-connection libraries, etc. is limited to known endpoints). Builds are reproducible, and distributables can be verified against source.
- **FRNT-SEC-002 (delivery integrity)**: apply DNSSEC to official domains, and place hosting/DNS/CDN administration under company-managed authority (FRNT-GOV-001). Reduce tampered-script execution surface with CSP, SRI, etc. The Day-1 policy and Day-2 adoption gate for mirror delivery such as IPFS / ENS are governed by FRNT-TBD-006 / [Frontend-Mirror-Delivery-Policy.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md).
- **FRNT-SEC-003 (display integrity)**: sanitize external strings (ENS names, referrals, etc.) before display. Always provide full-address verification means (copy, explorer link); do not rely only on ambiguous abbreviated display for approvals.
- **FRNT-SEC-004 (approval safety)**: spender is limited to known protocol contracts derived from bindings; do not provide arbitrary-address approval as a flow. Unlimited approvals are not offered (FRNT-FR-007).
- **FRNT-SEC-005 (phishing resistance)**: official links (domain, SNS, documentation) are rendered from a single repository-managed ledger. Public documentation links in the user app use the page registry in `frontend/app/src/docs-url.ts` as their sole generator and link directly to the page that explains the current UI. Public hosting requires the JP / EN publication-root environment variables as a pair and rejects an unset pair. Only local and test builds may fall back to the private repository's `documents/public-docs/{jp,en}` authoring trees for developer preview; that fallback is not a public user route. Public product surfaces must not link directly to the internal `documents/{jp,en}` specifications. An operator-only link such as a devnet-state guide may reference an internal runbook only when the UI clearly distinguishes it from public product documentation. Enforce `rel="noopener noreferrer"` on external links. Maintain an operational runbook for incident announcements when fake sites appear (official-domain banner, SNS).
- **FRNT-SEC-006 (privacy)**: analytics/measurement is opt-in (or with consent banner), and does not collect mappings between addresses and personal information. Telemetry (§11) contains no PII.
- **FRNT-SEC-007 (administrator surface separation)**: Admin Control and Private Operations Monitor are unreachable from public surfaces and require authentication even to view. Monitor viewer and privileged operator / signer may be separate roles; viewers receive no privileged operation. Preparation revalidates on-chain authority, which remains the actual enforcement boundary. Dune, User App, and the transitional public Ops bundle exclude private endpoints, admin runtime config, operator routing, worker commands, source maps, and key material. The public Ops public-bundle guard remains fail-closed until build / publish decommission and is removed in the same review as that workflow.
- **FRNT-SEC-008 (endpoint keys)**: Browser-facing read-only RPC / subgraph credentials may be shared by the User App, transitional public Ops, and Admin Control, but are treated as public with every consuming domain allowlisted, aggregate rate / capacity limits, and rotation / revocation ownership. A read-only API key that the provider contract treats as secret must not enter the browser bundle; inject it from the company secret store into a same-origin proxy restricted to read-only endpoints and bounded traffic. Authenticated operations must not depend on RPC URL / key secrecy. Worker-only / archive / write / signing credentials remain separate from browser credentials (FRNT-GOV-001).

---

## 10. Governance, Operations, and Upgrade Requirements GOV

- **FRNT-GOV-001 (company ownership of assets)**: domains, hosting, RPC / subgraph accounts, analytics foundation, and statistics API are owned by company accounts and access is role-managed (eliminate individual-account dependency; consistent with Development-Plan cross-cutting backlog).
- **FRNT-GOV-002 (release management)**: production releases have versioning and mapping to source commit (origin display in footer, etc.), with rollback procedures. Production environment-variable changes undergo the same review as normal code changes.
- **FRNT-GOV-003 (change management and requirement traceability)**: frontend specification changes first update this document (FRNT-ID), and implementation PRs, code, and tests reference the relevant ID (frontend application of the standard guardrail "ID linkage is one-way"; code comments equivalent to `@requirement FRNT-FR-NNN`, PR body cites IDs). Do not write PR/SHA into docs.
- **FRNT-GOV-004 (upstream follow-through)**: periodically incorporate updates from the upstream Liquity v2 app after checking conflicts with DF diffs (FRNT-FR-011, etc.). Maintain operating records for incorporation decisions and diff ledger (avoid uncontrolled fork drift).
- **FRNT-GOV-005 (audit acceptance)**: include FRNT FR / INV / SEC in a coverage ledger of "implementation × verification method" (same shape as Development-Plan audit acceptance), and release only after uncovered = 0.

---

## 11. Telemetry and Monitoring Requirements EVT

- **FRNT-EVT-001 (client exceptions)**: collect uncaught exceptions and render errors without PII, and detect regressions by release.
- **FRNT-EVT-002 (synthetic monitoring)**: externally monitor liveness of public surfaces, RPC / subgraph responses, and render success of main screens, and notify operations on failures. Probe RPC independently from static HTML availability by sending `eth_chainId` and `eth_blockNumber` to a configured read-only endpoint and validating both the expected chain and a current block. The shared browser credential under FRNT-SEC-008 may be used, but endpoint URLs, queries, and credentials are not emitted in alerts or logs.
- **FRNT-EVT-003 (tx success/failure measurement)**: aggregate submitted frontend tx count, failure rate, and main revert reasons, and detect UX-caused failures (missed validation, constant divergence). Do not perform per-address behavior tracking (FRNT-SEC-006).

---

## 12. Failure and Exception Behavior ERR

- **FRNT-ERR-001 (RPC failure)**: reads switch to fallback systems; if all systems are unreachable, show degraded display with "last fetched at." Disable write operations during outage. The user app does not start writes until a runtime `eth_chainId` plus current-block probe has succeeded, and repeats the same probe immediately before each tx step. While it fails, new flows, the next step of an existing flow, and the devnet faucet all fail closed. The outage UI includes the last successful check and a retry action. Ops marks retained data as previous values, Admin blocks simulation and local execution while RPC health is unconfirmed, and the AWS synthetic worker probes the expected-chain read-only RPC with retries and routes total outage through `ALRT-FRNT-002`.
- **FRNT-ERR-002 (subgraph degradation)**: when sync delay exceeds threshold, show freshness warning on history/list screens and visually distinguish them from current-value views (RPC-derived). On full outage, only list views degrade; operation flows (RPC-based) remain available.
- **FRNT-ERR-003 (chain mismatch)**: if wallet connected chain differs from target chain, block all write UI and show chain-switch path.
- **FRNT-ERR-004 (tx failure)**: failed txs show decoded reason (custom error name mapped to human-readable description) plus retry/support path. Unknown failures show error id / tx hash / redacted details, and raw stacks, private RPC URLs, API key fragments, or DataAPIError details must not be user-visible ([Frontend-UX-Readiness-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md)).
- **FRNT-ERR-005 (branch abnormality)**: when detecting oracle failure, branch shutdown, or pause (VAULT-FR-014), block new operations for the branch in UI (borrow, mint, etc.) and present only allowed operations (repay, claim [claim also stopped during `pauseClaim`], urgent redemption, etc.). Inspect `newOracleFailureDetected` returned by `PriceFeed.fetchPrice()` together with the price; a positive last-good price must not be treated as healthy by itself. Keep new borrowing fail-closed while required RPC reads for price, TCR/CCR, branch debt, Vault state, or shutdown state are failed or unresolved. Contract-side defense is authoritative; frontend blocking is only UX preemption.
- **FRNT-ERR-006 (incident announcement)**: operations can display a whole-app banner (warning, maintenance, read-only mode) through configuration change without code change.

---

## 13. Acceptance Criteria and Verification Plan

**Verification method types**: `unit` (pure functions, utilities) / `component` (UI component or screen unit) / `e2e-local` (local chain + subgraph + app end to end) / `build` (build, types, environment schema) / `ci-guard` (automatic gates such as source reconciliation and text lint) / `visual` (display check) / `manual` (operational procedure) / `monitor` (production synthetic monitoring).

| Area | ID | Main verification |
| --- | --- | --- |
| Bindings, constants, ABI | FRNT-FR-001..004, FRNT-INV-002 | build / ci-guard |
| Wallet, tx, approvals | FRNT-FR-005..007, FRNT-INV-003 | e2e-local / component |
| Data sources and display conventions | FRNT-FR-008..011, FRNT-INV-001 | unit / component / monitor |
| User app functions | FRNT-FR-012..023 | e2e-local / component / visual |
| Administrator console | FRNT-FR-024..030 | e2e-local / component / manual |
| Operations dashboard | FRNT-FR-031..036 | e2e-local / visual / monitor |
| Security | FRNT-SEC-001..008, FRNT-INV-004 | ci-guard / build / manual |
| Failure behavior | FRNT-ERR-001..006 | e2e-local / component / manual |

**Acceptance principles**:
1. **docs ↔ code parity** — implementation, tests, and PRs reference FRNT-ID, and every FR / INV / SEC has uncovered = 0 in the "implementation status × verification method" ledger (FRNT-GOV-005).
2. **Treat e2e-local as first-class acceptance** — main user flows (borrow → adjust → Earn → redeem → claim) can be reproduced in an end-to-end environment with deploy to local chain + subgraph + app.
3. **Release gates** — FRNT-INV-002 (constant reconciliation), FRNT-FR-004 (environment schema), and FRNT-SEC-001 (dependency audit) are required CI gates.

---

## 14. Open Items TBD

- **FRNT-TBD-001**: DFT staking and governance UI (after tokenomics and PIL voting design are finalized; replacement for FRNT-FR-022).
- **FRNT-TBD-002**: Multiply (leverage) enablement conditions (JPYdf DEX liquidity, JPYdf/USDC Uniswap v4 final leg, asset-specific pre-legs, and dToken leverage design; linked to ZAP-TBD-004 / ZAP-TBD-010 / Liquidity-Route-Policy). Day-1 keeps `NEXT_PUBLIC_MULTIPLY_SCREEN=false`; Curve and direct USDT/USDS/WETH/XAUT JPYdf pools are not gate conditions. The frontend / manifest must explicitly constrain the sendable v4 route and hook range.
- **FRNT-TBD-003**: Display of SP additional rewards and Treasury distribution (waiting for SYS-RISK-003 / TRSY design finalization; hide until finalized).
- **FRNT-TBD-004**: DF statistics API (replacement for upstream `api.liquity.org` series) readiness and ownership (under FRNT-GOV-001). The initial backend for public health JSON is implemented through `frontend/ops export-stats`, and the user app reads it through `NEXT_PUBLIC_PROTOCOL_STATS_URL` and `frontend/app/src/protocol-stats.ts`. **Required before mainnet**: close production hosting / company-owned domain / publishing procedure / stale JSON alert / runtime health evidence under [Frontend-Production-Delivery-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md), and fail closed at production build or runtime health when the endpoint is unset. **Day-2**: APR-style time-series aggregation; keep hidden until ready.
- **FRNT-TBD-005**: The administrator console production gate is defined by [Admin-Console-Production-Gate.md](../../../contributors/deltaforesight/delivery-plans/Admin-Console-Production-Gate.md) (`frontend/console` local implementation is adopted in the monorepo). **Required before mainnet**: authentication, hosting separation, publication scope, search-index blocking, browser read-only RPC/API credential evidence under FRNT-SEC-008 (sharing is allowed), current contract manifest, role snapshots that support multiple holders, and Safe calldata export / decoded evidence. Concrete domain / IdP / key values are recorded in deploy freeze evidence; this spec must not contain secrets. Deep Safe App integration is Day-2.
- **FRNT-TBD-006**: The Day-1 policy for mirror delivery (IPFS / ENS) for censorship and outage resistance is governed by [Frontend-Mirror-Delivery-Policy.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Mirror-Delivery-Policy.md). Day-1 mainnet launch uses the official HTTPS origin as canonical, and the mirror is not a launch-gate replacement; it is Day-2 optional. If adopted on Day-2, evidence must cover a static bundle built from the same commit / config / deployment manifest, canonical-origin display, RPC / wallet domain allowlist, stale-data display, error redaction, incident announcement, and CID / ENS rollback. The admin console, operator-only information, and private endpoints are out of scope for mirroring.
- **FRNT-TBD-007**: The production domain / hosting gate is defined by [Frontend-Production-Delivery-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-Production-Delivery-Gate.md). **Required before mainnet**: official URLs for user app / ops dashboard / public stats JSON, company-account ownership, DNS / CDN / hosting evidence, CSP / HSTS / official link ledger, fail-closed runtime health for RPC/subgraph/stats endpoints, monitoring, and rollback evidence. Concrete domain / account / key values are recorded in launch evidence; this spec must not contain secrets.
- **FRNT-TBD-008**: The mainnet gate for i18n delivery order and scope is [Frontend-UX-Readiness-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md). Before mainnet, freeze the primary locale in launch evidence and align all reachable-screen copy to JPYdf terminology, JPY display, and error copy. If another locale is incomplete, do not expose a locale switch. Complete multi-locale delivery is Day-2.
- **FRNT-TBD-009**: The mainnet gate for mobile / in-wallet browser support is [Frontend-UX-Readiness-Gate.md](../../../contributors/deltaforesight/delivery-plans/Frontend-UX-Readiness-Gate.md). Before mainnet, responsive layout, wallet modal, tx confirmation, and error states must not break at major phone widths. Wallet-specific in-app browser polish is Day-2, but signing return paths and long error display must be closed before mainnet.
- **FRNT-TBD-010**: Participant readiness gate is governed by [Mainnet-Participant-Readiness-Gate.md](../../launch/gates/Mainnet-Participant-Readiness-Gate.md). Before mainnet, evidence must show that borrowers / SP depositors / liquidators can inspect effective APR, redemption risk, liquidation risk, SP coverage, outside debt, JPYdf/USDC exit liquidity, and liquidation-operator evidence. Day-2 items such as SPAdditionalRewardDistributor, profit-seeking liquidator, auto-compound, and APR time-series aggregation remain unimplemented and must not be displayed as implemented.
- **FRNT-TBD-011**: Referral URL capture / transaction submission is enabled only after the registry / abuse / ledger gate in [Referral-Program-Policy.md](../../operations/policies/Referral-Program-Policy.md) and [Referral-Ledger-Export-Runbook.md](../../../contributors/deltaforesight/operations/Referral-Ledger-Export-Runbook.md). The current implementation treats `NEXT_PUBLIC_REFERRAL_REGISTRY_URL` as an optional source and validates URL/localStorage slugs against that registry. Only a canonical `bytes32` returned by an active registry entry can appear in tx preview / submit; unknown / expired / paused / not-started / registry unavailable states are shown to the user and continue as no-referral txs. Before any concrete campaign is announced as production-active, close a separate activation packet covering partner registry, campaign terms, budget approval, fraud review owner, and root / claim evidence.

---

## 15. References

- Higher-level requirements and architecture: [Product-Overview.md](../Product-Overview.md) (SYS-FR-001..008 / ARCH-001..005)
- Launch risk gate: [Mainnet-Launch-Risk-Gate.md](../../launch/gates/Mainnet-Launch-Risk-Gate.md) (SYS-RISK-001..009)
- Normative specs for operation targets: [dToken.md](dToken.md) / [CollateralVault.md](CollateralVault.md) / [Strategy.md](strategies/Strategy.md) / [Oracle.md](Oracle.md) / [Zapper.md](Zapper.md) / [Treasury.md](../../roadmap/spec/Treasury.md)
- Source of truth for values: [Parameters.md](../../../Parameters.md)
- 🔵 Core behavior: [Liquity-v2-Core-Spec.md](Liquity-v2-Core-Spec.md)
- Internal plan and finalized decisions: [development/Development-Plan.md](../../../engineering/plans/Development-Plan.md) (cross-cutting backlog: JPYdf-owned display/data-model normalization / infra company-account unification)
- Participant launch readiness: [Mainnet-Participant-Readiness-Gate.md](../../launch/gates/Mainnet-Participant-Readiness-Gate.md)
- Formatting standard: [README.md — Requirements Specification Document Standard](../../../README.md#requirements-spec-standard)
