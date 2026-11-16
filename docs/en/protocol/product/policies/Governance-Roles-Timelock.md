# JPY DeFi Governance Roles and Timelock Design Decisions

> **Role**: Records why dToken / Strategy / Oracle / Treasury permissions are
> separated into delayed, immediate fail-safe, operations, and loss-reflection
> classes, together with the accepted risks.
>
> **Source-of-truth relationship**: Each component spec is authoritative for
> its individual gates; [`Parameters.md`](../../../Parameters.md) `PRM-GOV-*` is
> authoritative for delay and holder classes; [`Governance.md`](../../../Governance.md)
> is the cross-component index; and the mainnet gates / runbooks are
> authoritative for actual addresses and procedures. This memo is not the
> source of truth for values, function inventories, or implementation status.
>
> **Status**: Active

---

## 0. One-Line Summary

A five-role system combines **two-party governance (delayed = Timelock,
immediate = Guardian multisig) plus an operations principal (ALLOCATOR)** with
an independent **high-quorum role that immediately reflects losses or
uncertainty into backing (`WRITEOFF_ROLE`)**. The governing principle is:
**operations that can cause fund outflow, dilution, or markdown are delayed (or
high-quorum); reversible fail-safes such as pauses and neutralization are
immediate; recovery is delayed**. Because a role's holder determines timing,
operations that require different timing or quorum must use separate roles.

---

## 1. Problems

| # | Problem | Detail |
| --- | --- | --- |
| **P1** | Upgrades can be immediate | Compromise of a GOV / Owner key can immediately replace an implementation, inject arbitrary logic, and bypass every other protection at once: role separation, caps, whitelist, fixed destinations, and pauses |
| **P2** | Immediate outflow exists without an upgrade | With DEFAULT_ADMIN + GOV, an attacker can call `setBufferConfig(0,0)` → `setAllocatorConfig(max,0)` → `addToWhitelist` → `addStrategy(malicious)` → grant itself ALLOCATOR → `allocate` and drain the buffer. The defaults `allocateMaxMove = type(uint256).max` and cooldown `0` provide no effective initial bound |
| **P3** | Immediate actions can dilute backing and trigger excessive liquidation | An Aave emergency withdrawal can leave assets idle and uncounted until the Vault push; `writeoff` or `invalidateStrategyValuationCache` can reduce principal / valuation |
| **P4** | Writeoff is the primary route for reflecting Strategy loss | Aave V3 bad debt, deficits, or frozen state may not reduce `scaledBalanceOf` / `normalizedIncome`, so the estimate may be overstated. A loss absent from protocol accounting must be reflected explicitly through writeoff (`AAVE-INV-002`); delay therefore prolongs the overvaluation window |

Fixing P1 alone does not address P2. Immediate actions are not unconditionally
safe because of P3, and loss recognition is not automatic because of P4.

---

## 2. Design Principles

1. **The holder determines timing**: same role means same holder and timing.
   Operations needing different timing or quorum must use separate roles. This
   is why `WRITEOFF_ROLE` is independent.
2. **Risk increase, fund movement, or markdown → delayed or high-quorum
   immediate**.
3. **Reversible fail-safe such as pause / neutralization → immediate
   Guardian**.
4. **Recovery such as unpause, re-enable, or limit increase → delayed
   Timelock**. Brakes should be easy to apply and slow to release.
5. **Two governance parties plus operations**: Timelock is the delayed party,
   Guardian multisig the immediate party, and ALLOCATOR daily operations. Holder
   design is the primary defense; code gates provide the framework.
6. **Core remains unmodified (`ARCH-001`)**: solve these concerns in the
   JPY DeFi-specific permission and wiring layer.

---

## 3. Role Model

### 3.1 CollateralVault — Five Roles

| Role | Holder | Timing | Responsibility |
| --- | --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | **Timelock** | Delayed | `grantRole` / `revokeRole` |
| `GOV_ROLE` | Timelock | Delayed | Risk parameters, upgrades, recovery, and role administration |
| `WRITEOFF_ROLE` | High-quorum Admin multisig | Immediate | Reflect losses / uncertainty into backing |
| `GUARDIAN_ROLE` | Guardian multisig | Immediate | Pause, neutralization, and emergency recovery |
| `ALLOCATOR_ROLE` | `DF_ALLOCATOR` | Operations | Allocation, recovery, and yield transfer through fixed routes |

Design consequences:

- **Writeoff is a separate `WRITEOFF_ROLE`**, not part of Guardian. Guardian is
  intentionally fast and can use a lower quorum; writeoff is monetizable through
  improper markdown → liquidation → SP / liquidator gains and therefore needs a
  high quorum. Combining them would make either pauses too slow or writeoffs too
  permissive. A distinct high-quorum Admin multisig holder is the reason to pay
  the cost of a separate role.
- **`invalidateStrategyValuationCache` is not a Guardian operation**. Clearing a
  cache while live valuation fails can set that Strategy's valuation to zero,
  reduce backing, and trigger liquidation. Its normal path is delayed
  `GOV_ROLE`; `WRITEOFF_ROLE` may also call it only when incident-ready
  (Strategy disabled or allocation paused). This keeps immediate markdown under
  the same high-quorum incident boundary and denies markdown power to Guardian.
- Every Guardian action is **backing-neutral or pure flow control**:
  - `emergencyDisableStrategy` sets `enabled=false` and weight zero without
    changing estimate or principal.
  - `removeStrategy` requires `principal==0`, so the contribution is already
    `min(estimated, 0) == 0`.
  - `removeFromWhitelist` does not affect registered Strategies or backing.
  - Pause functions only stop flows.

This makes it safe to combine emergency and pause functions in `GUARDIAN_ROLE`,
while writeoff and valuation-cache invalidation remain outside it.

### 3.2 DToken — Owner = Timelock

- Wire the single two-step Owner to the **Timelock**. `setCap`, `setTokenInfo`,
  `setAllowedUnderlying`, and upgrades are all delayed.
- Emergency mint stoppage is handled by Vault `pauseDeposit` (immediate
  Guardian), so DToken does not need another code path. `setCap` is a durable
  exposure limit, not an emergency brake.

### 3.3 Strategy — Separate Upgrader and Owner

| Permission | Holder | Timing | Functions |
| --- | --- | --- | --- |
| `upgrader` | Timelock | Delayed | Upgrade and upgrader changes |
| `owner` | Guardian multisig | Immediate | Emergency recovery, rewards, and protocol-specific fail-safes |

One Ownable owner cannot make upgrades delayed and emergencies immediate, so the
upgrade permission is separated into `upgrader`.

### 3.4 PriceFeedProxy — Owner = Direct Admin Multisig

Source replacement has a built-in delay that also applies to
`confirmSourceEmergency`. Putting Owner behind the shared Timelock would impose
a double delay. The Admin multisig therefore holds Owner directly and retains
immediate `cancelSourceProposal` for a malicious proposal.

### 3.5 Treasury / Distributor — Separate Immediate Guardian Fail-Safes

Apply the Vault-style delayed / immediate split to
[Treasury](../../roadmap/spec/Treasury.md) and
[Reward Distributors](../../roadmap/spec/Reward-Distributors.md). The shared Timelock
holds `GOV_ROLE` / `DEFAULT_ADMIN_ROLE`; Guardian handles destination disable,
proposal / root cancellation, and pause. Cancellation cannot remain with GOV
because the shared delay may outlast a challenge window. `emergencyBackstopDeposit`
is bounded by registered Vault, matching underlying, and current shortfall, so
it cannot become arbitrary transfer or markdown authority.

---

## 4. Key Decisions and Verified Constraints

### A. Pause Mint, Redeem, and Claim Separately

- `pauseDeposit` and `pauseRedeem` are separate because the required action
  differs by scenario:
  - **XAUT price depeg while A=L**: stop new mint but keep redeem open for a fair
    exit → `pauseDeposit` only.
  - **Strategy loss with A<L**: dToken redemption remains 1:1 without a haircut,
    so open redemption becomes a first-mover run → `pauseRedeem`.
  - The old combined pause unfairly blocked exits in the XAUT scenario.
- **Claim must also be pausable** during a Strategy-loss writeoff:
  - Redeem / claim remain 1:1. With A<L, immediate redeem payments and vested
    claims race for a finite buffer. `pendingWithdrawals` protects funds from
    allocation but does not remove first-mover advantage between redeem and
    claim.
  - The repair path is **freeze → inject backstop with `backstopDeposit` and
    `releaseBackstopToBuffer` until A≥L → resume**. Claims must stop during that
    window or vested claims can drain the buffer and defeat equitable repair.
- **Accepted cost**: governance can freeze a vested claim, weakening
  non-custodial properties. Guardian should do so only with high confidence, and
  the repair window should remain short even though recovery requires the
  shared Timelock. Core Redemption and liquidation continue during the freeze,
  so JPYdf Redemption arbitrage can also weaken temporarily.
- A pro-rata haircut at A<L would structurally remove first-mover advantage, but
  conflicts with the existing 1:1 plus backstop-repair design
  (`ORCL-FR-014`), so it is not adopted.

### B. `setCap` Is a Durable Risk Parameter; `pauseDeposit` Is the Emergency Brake

An acute depeg uses immediate Guardian `pauseDeposit`. `setCap` is the durable
control for not increasing exposure and may remain delayed behind Owner =
Timelock. The two are complementary. The `ORCL-FR-013` response is therefore
acute `pauseDeposit`, followed by delayed `setCap(0)` for durable policy.

### C. Core Branch Shutdown Is Not a Reversible Freeze

Verified constraints in Core:

- **Permanent and irreversible**: no function restores `hasBeenShutDown=false`
  or `shutdownTime=0`. A shutdown branch remains in urgent-redemption mode.
- **Cannot be invoked arbitrarily**: `shutdown()` requires `TCR < SCR`;
  `shutdownFromOracleFailure()` requires the PriceFeed caller.
- **Circular before markdown**: before writeoff, an overstated backing ratio can
  keep TCR above SCR, causing shutdown to revert.
- **dToken pause does not stop Core borrowing**: `pauseDeposit` and
  `emergencyDisableStrategy` stop new dToken supply / allocation, but existing
  collateral can still support Core borrowing until shutdown.

Do not treat Core shutdown as a temporary pause. It is the only way to stop
existing dToken collateral exposure and is permanent and conditional. Normal
exposure must therefore be structurally bounded by `mintCap` (`ORCL-FR-013`,
`SYS-INV-004`).

### D. Writeoff Is Immediate and High-Quorum

Because Core has no arbitrary reversible freeze, a design that freezes
immediately and delays writeoff does not work: borrowing can continue against
overvalued collateral and add bad debt. `WRITEOFF_ROLE` therefore executes
writeoff immediately through the high-quorum Admin multisig. A scalar rate limit
is not adopted because a low limit that blocks abuse also blocks prompt
recognition of a large real loss.

Three layers constrain a malicious writeoff: high quorum; immediate Guardian
`pauseRedeem` to close the attacker's dToken-to-underlying exit; and the fact
that writeoff only reduces principal and does not itself transfer funds.

### E. `emergencyWithdrawFromAave` Uses an Atomic Direct Push

In the former two-step Aave withdrawal then Strategy withdrawal, underlying
could remain idle in the Strategy, excluded from both Strategy estimate and
Vault buffer. The resulting backing-ratio drop could trigger improper,
permissionless, and irreversible mass liquidation. Multisig `multiSend` is an
operational convention and does not enforce atomicity in code.

`emergencyWithdrawFromAave` therefore completes Aave → Vault in one
transaction. An Aave revert reverts the whole operation. The separate
`emergencyWithdraw` remains for idle donations and residual recovery.

---

## 5. Residual Risks and Operational Assumptions

- Full key compromise relies on detection and exit during the shared delay. If
  the Admin multisig / proposer is compromised, there is no separate holder that
  can cancel.
- Guardian compromise can cause availability damage through pause /
  neutralization, but cannot make arbitrary transfers or markdowns.
- `WRITEOFF_ROLE` compromise can execute immediate writeoffs until revocation.
  High quorum, `pauseRedeem`, and the lack of a direct transfer bound
  monetization.
- Immediate writeoff is a consequence of Core lacking a reversible freeze.
- Delays have operational cost: Strategy additions, config changes, dToken
  activation, and unpause cannot be immediate. Guardian pauses buy time during
  an incident.
