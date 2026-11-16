# Reference Study: Implementation Comparison of PIL → DEX Allocation (Liquity v2 BOLD / Nerite / Asymmetry)

> **Positioning**: Reference information. An external-implementation study that forms the design rationale for [`spec/PILAllocator.md`](../../protocol/product/spec/PILAllocator.md). Not the canonical specification.
> **Date**: 2026-06-25 | **Subject**: The DEX-allocation implementation of the PIL portion of borrowing interest (the residual that does not go to the SP = the portion minted to `interestRouter`)
> **Method**: Verbatim verification of actual GitHub code (`mcp__github__*`). Citations give repo / path / contract / function name plus the key blob SHA. A portion of Nerite's current deployed state is measured on-chain (confidence level noted explicitly).

---

## 1. Common Starting Point (the 3 protocols + jpydf in common)

For all 3 protocols, the behavior of Core (`ActivePool`) is identical: **Core does nothing more than "mint the non-SP residual of borrowing interest (PIL) as JPYdf/BOLD to a single address called `interestRouter`."** The allocation logic depends on whatever contract is placed at `interestRouter`.

`ActivePool._mintAggInterest()` (`liquity/bold:contracts/src/ActivePool.sol`, blob `eff5042…`):
```solidity
uint256 spYield = SP_YIELD_SPLIT * mintedAmount / DECIMAL_PRECISION;   // 75%
uint256 remainderToLPs = mintedAmount - spYield;                       // 25% = PIL
boldToken.mint(address(interestRouter), remainderToLPs);              // ← PIL to interestRouter
```
- `SP_YIELD_SPLIT = 75%` (`Constants.sol`). **The `Constants.sol` of bold / Nerite / Asymmetry match exactly at blob SHA `9e0231988039464b070dc5cd325f7e35d35f1e22`** → all 3 keep 75/25 unchanged.
- `interestRouter` is an immutable of `ActivePool`. `IInterestRouter` (`contracts/src/Interfaces/IInterestRouter.sol`, blob `f66a5ab…`) is an **empty interface** ("Currently the Interest Router doesn't need any specific function"). There is no callback on receipt.
- → The difference among the 3 boils down to **what was placed at `interestRouter`**.

---

## 2. Comparison of the 3 Archetypes

| | PIL allocation type | What is placed at interestRouter | DEX-reaching path | Decentralization/automation |
| --- | --- | --- | --- | --- |
| **BOLD (upstream)** | Full on-chain governance | `Governance.sol` (vote-based initiative allocation) | Auto-injected to Curve gauge / Uniswap v4 (Merkl) via initiatives | High (permissionless, automated) |
| **Nerite** | Follows the BOLD model (transitional) | Currently: stays in the Aragon NERI DAO → Future: planned switch to V2-gov `Governance` (DEX = Camelot/Bunni) | Design is the same as BOLD; **currently held by the DAO and not yet automated** | Medium (mid-migration) |
| **Asymmetry (USDaf)** | Minimal, discretionary | Custom `InterestRouter.sol` (`Ownable` + `sweep`) | **No on-chain allocation logic.** The owner multisig sweeps out manually | Low (discretionary, off-chain) |
| **(Reference) jpydf current** | Forwarder shim | `InterestRouterForwarder` (recipient mutable, `route()` permissionless) | On Day-1, only forwards to recipient. Allocation is Day-2 / external | Low (Day-1) → predicated on extension |

---

## 3. Liquity v2 BOLD (upstream) — Full On-chain Governance + DEX Initiatives

In BOLD, `interestRouter = Governance` (separate repo `liquity/V2-gov`). The deploy wiring is `contracts.interestRouter = IInterestRouter(_governance)` (`liquity/bold:contracts/script/DeployGovernance.s.sol`, blob `88ffa47…`). `Governance` reads `boldAccrued = bold.balanceOf(address(this))` as the distributable source funds.

### 3.1 Allocation Engine `Governance.sol` (blob `cf36139…`)
- **Stake**: `depositLQTY()` → stakes LQTY via `UserProxy`. Voting power = `LQTY × elapsed time` (time-weighted).
- **Voting**: `allocateLQTY(reset[], initiatives[], votes[], vetos[])` — assigns voting power to initiatives as vote/veto. After `EPOCH_VOTING_CUTOFF`, votes cannot be increased.
- **Epoch snapshot**: in `_snapshotVotes()`, `boldAccrued = balanceOf(this)` (0 if `< MIN_ACCRUAL`). **The accumulated PIL is this period's source funds.**
- **Share**: `getInitiativeState()` — `claim = votesForInitiative × boldAccrued / totalVotes` (CLAIMABLE when votes exceed the voting threshold ∧ veto is not exceeded).
- **Transfer**: `claimForInitiative(initiative)` (**permissionless**) — `bold.safeTransfer(initiative, claim)` plus the `onClaimForInitiative` hook. **Unclaimed amounts are recycled** (included in the next epoch's `boldAccrued`; = carry-over).
- **Registration**: `registerInitiative()` — **permissionless** via the `REGISTRATION_FEE` (BOLD) plus a voting-power threshold. Anyone can register a new DEX pool as an initiative.

### 3.2 The Initiatives That Execute "PIL → DEX" (the main topic)
- **`CurveV2GaugeRewards.sol`** (blob `dea21ee…`): `onClaimForInitiative` → `gauge.deposit_reward_token(bold, total, duration)`. Injects BOLD as a reward into a Curve gauge → Curve LPs earn it. Small amounts stay in `remainder` (less than `duration×1000`).
- **`UniV4MerklRewards.sol`** (blob `b30028a…`): `claimForInitiative()` (permissionless wrapper) → `_createCampaign` → `merklDistributionCreator.createCampaign({campaignType: 13(UNISWAP_V4), rewardToken: bold, startTimestamp: epochEnd, duration: EPOCH_DURATION, campaignData: poolId/weights/blacklist})`. Merkl allocates to Uniswap v4 LPs via off-chain computation. `onClaimForInitiative` is empty; the Merkl integration is separated into the wrapper (gas mitigation). **The blacklist is a single entry, the company's own Funds Safe `0xF06016…`** (a business-entity Safe, not protocol-owned), with `IS_OUT_OF_RANGE_INCENTIVIZED=false` (in-range only).
- **`BribeInitiative.sol`** (blob `2bbb36c…`): the parent of `CurveV2GaugeRewards`. Not a PIL path but a **vote-incentivization (bribe) layer** in which a third party uses `depositBribe()` to induce voters, and voters reclaim a vote-proportional share via `claimBribes()`. In `onAfterAllocateLQTY` it records per-user/total vote amounts by epoch (the source funds for bribe pro-ration).

### 3.3 Initiative Granularity (important)
`registeredInitiatives` is a `mapping(address => uint256)` = **per-address**. A DEX-allocation initiative fixes **a single allocation target as immutable in the constructor** (`CurveV2GaugeRewards.gauge` / `UniV4MerklRewards.UNIV4_POOL_ID`).
- Evidence: the mainnet initial initiatives (`DeployGovernance.s.sol`) are **separate `CurveV2GaugeRewards` instances for Curve USDC/BOLD and Curve LUSD/BOLD** (`deployCurveV2GaugeRewards` deploys a gauge and an instance per pool) plus `defiCollectiveInitiative` (just a grants Safe address).
- → **The unit is not "Curve" or "Uniswap" but 1 instance = 1 pool.** Curve BOLD/USDC, Curve BOLD/USDT, Uni v4 BOLD/USDC … are all separate initiatives (separate addresses, separate voting/allocation). v3 is not bundled upstream (it requires a separately-built initiative of a different type).
- Exception: since an initiative is any address that satisfies `IInitiative`, a custom implementation that distributes to multiple pools inside a single initiative is also possible (the default is 1:1).

### 3.4 Why "Initiatives Can Be Added Later Even Though It's Immutable"
`registerInitiative()` is a **permissionless function built into the immutable code from the start**; it merely writes one line into `registeredInitiatives` (mutable state). The code does not change (= it is not an upgrade). A new initiative is simply newly deployed to a separate address, with the existing Core/Governance unchanged. After the initial registration, `Governance` also renounces ownership via `_renounceOwnership()` (so arbitrary insertion by an administrator is also impossible). **"The rules (code) are immutable; only the beneficiary list (state) moves through a defined procedure"** = extensibility without upgradeability.

---

## 4. Nerite (USND, Arbitrum) — Follows the BOLD Model, in a Migration Transition

- **Ratio / Core**: the `Constants.sol` blob of `NeriteOrg/liquity2-template` matches bold (`9e0231988…`) → **75/25 unchanged, Core unmodified**. The core files under `contracts/src` also have blobs matching bold.
- **Design (docs)**: allocate the PIL (25% of fees) via **NERI token** governance, directing it toward **USND liquidity incentives on external DEXes such as Camelot and Bunni** (`NeriteOrg/docs`). = Follows BOLD's V2-gov model with only the token swapped.
- **Current state (on-chain measurement, high confidence)**: `AddressesRegistry.interestRouter()` currently points to the **Aragon OSx NERI DAO (`0x108f…B1d`)**, and the PIL (USND) stays there. The real V2-gov `Governance` (`0x528b…892`, epochStart 2026-07-25) is deployed but **has no registered initiatives, a balance of 0, and is not yet operational**. The docs also state it is mid-migration: "Initially, Governance is also set as the InterestRouter. This will be updated in the near future."
- **Confidence**: ratio/Core unmodified, and the current destination of interestRouter = high. **The mechanism for automatic allocation to the final DEX (Camelot/Bunni) = medium-to-low (mid-migration, "Coming Soon")**.
- **Note**: `liquity2-template` is the upstream template, which has no Arbitrum branch. The production source of truth is `api.nerite.org` + docs + on-chain.

---

## 5. Asymmetry (USDaf, Ethereum) — Minimal, Immutable, Discretionary Allocation

- **Ratio / Core**: the `Constants.sol` blob matches (75/25). `ActivePool._mintAggInterest` is the same logic as bold (mint-to-`interestRouter`; the SHA difference `2289ffa…` is only a comment typo).
- **The contents of `interestRouter` = the custom `InterestRouter.sol`** (`asymmetryfinance/USDaf-v2:contracts/src/InterestRouter.sol`, blob `9d1812d…`), in full:
```solidity
contract InterestRouter is IInterestRouter, Ownable {
    address private constant _OWNER = 0xce352181C0f0350F1687e1a44c45BC9D96ee738B;
    constructor() Ownable(_OWNER) {}
    function sweep(address _token, address _to) external onlyOwner {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        require(_balance > 0, "!BALANCE");
        IERC20(_token).safeTransfer(_to, _balance);
        emit Swept(_token, _to, _balance);
    }
}
```
- **Behavior**: the PIL (USDaf) merely accumulates at `interestRouter`. **Only the owner (a hardcoded multisig `0xce35…738B`) can sweep the entire balance to any destination via `sweep(token, to)`.** There is no on-chain DEX-allocation logic, voting, gauge, or Merkl. The use of funds is entirely at the owner's discretion (off-chain).
- **Philosophy**: a minimal implementation with no governance mechanism, in line with "Immutable by design."

---

## 6. Implications for jpydf (→ `spec/PILAllocator.md`)

- **The current jpydf `InterestRouterForwarder`** is closest to the Asymmetry type (minimal), but is operationally superior with `route()` permissionless + a mutable recipient. The Forwarder's `recipient` replacement point is the insertion slot for future DEX automation/voting (`IRTR-GOV-003`/`IRTR-TBD-004`).
- **Adoption policy (`PILAllocator.md`)**: follow BOLD's composition (`Governance` + `IInitiative` + `UniV4MerklRewards`), and **substitute admin weight for voting in Phase-A**. In Phase-B, migrate to upstream-conformant DFT voting (`VotingAllocator`) by replacing the recipient (core/Forwarder/initiative unmodified).
- **Design decisions confirmed by this study**:
  1. **The residual is carry-over (upstream-conformant; no treasury sink needed)**: upstream "recycles unclaimed amounts" (§3.1). To route to a treasury, **register a Safe as an initiative**, as upstream's `defiCollectiveInitiative` does. → `PILA-FR-005/006/007`, `PILA-INV-002`.
  2. **Initiative granularity = 1 instance, 1 pool** (§3.3) → multiple pools/Curve are extended by adding instances (`PILA-GOV-005`). Curve is Day-2, out of scope.
  3. **`onAfterAllocateLQTY` is unused in Phase-A but the IF is retained** (reused in Phase-B, §3.2) → `PILA-FR-102`.
  4. **The Merkl integration is separated into `createCampaign`, in-range only** (§3.2). jpydf's blacklist is **empty on Day-1 (no targets)** → `PILA-FR-202/203`.
  5. **`approve` is hardened from upstream's max → per-call approve** (limiting damage to the campaign amount in question) → `PILA-SEC-003`.
  6. **"Immutable yet extensible"** (§3.4) = the same archetype as jpydf's "Core immutable + external replacement" (ARCH-004). `registerInitiative` is merely a permissionless window into immutable code.

---

## Appendix: Sources (Key blob SHAs)

| repo | path | contract / function | blob SHA |
| --- | --- | --- | --- |
| liquity/bold | contracts/src/ActivePool.sol | `_mintAggInterest` | `eff5042…` |
| liquity/bold | contracts/src/Dependencies/Constants.sol | `SP_YIELD_SPLIT=75%` | `9e0231988039464b070dc5cd325f7e35d35f1e22` |
| liquity/bold | contracts/src/Interfaces/IInterestRouter.sol | empty IF | `f66a5ab…` |
| liquity/bold | contracts/script/DeployGovernance.s.sol | initial initiatives (Curve×2 + defiCollective) | `88ffa47…` |
| liquity/V2-gov | src/Governance.sol | vote-allocation engine | `cf36139…` |
| liquity/V2-gov | src/CurveV2GaugeRewards.sol | Curve gauge injection | `dea21ee…` |
| liquity/V2-gov | src/UniV4MerklRewards.sol | Merkl Uni v4 | `b30028a…` |
| liquity/V2-gov | src/BribeInitiative.sol | bribe layer | `2bbb36c…` |
| liquity/V2-gov | src/interfaces/IInitiative.sol | 4 hooks | `4a415c5…` |
| NeriteOrg/liquity2-template | contracts/src/Dependencies/Constants.sol | matches bold | `9e0231988…` |
| asymmetryfinance/USDaf-v2 | contracts/src/InterestRouter.sol | `Ownable` + `sweep` | `9d1812d…` |
| asymmetryfinance/USDaf-v2 | contracts/src/Dependencies/Constants.sol | matches bold | `9e0231988…` |

> Note: the blob SHAs are measured from each repo's default branch at the time of the study (2026-06-25). When referencing the latest, re-confirm via the GitHub API. Nerite's on-chain destination (Aragon DAO / V2-gov address) is an Arbitrum measured value; the operating volume and latest registration state require a separate inquiry.
