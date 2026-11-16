# Anvil On-chain Verification Ledger (per-ID real transactions)

> **Purpose**: to verify **every** requirement of jpydf-v2 (functional FR / invariant INV / security SEC / governance GOV / event EVT / failure ERR) **one by one with real transactions / real calls on anvil (a local chain)**, leaving for each ID an "execution method, anvil evidence (tx / revert selector / state / event), and result." This builds up, per requirement, a **third axis = on-chain execution** following code implementation (forge build) and tests (forge test), forming a triple verification.
>
> **Positioning**: this ledger is a **history snapshot of the anvil session performed at the verification fixed point `30d078b` (2026-06-20)**. The forge suite is **1170 passed** at the same fixed point (the test axis is green). For the per-ID forge mapping (`PASS@tip` about 592), refer to the V1 campaign of PR #258, but if PR #258 is unmerged, it may temporarily disagree with the displayed counts of this repo's main ledger / Core ledger. The role of this ledger does not overlap with those; it is a **third axis that confirms with real txs whether the happy and exception paths actually reproduce on the local chain**. As of this PR, **about 191 IDs have been demonstrated on anvil** (covering representatives of all 6 categories and the SYS core flows; incomplete items are in §4). The implementation and ID denominator of current `develop` are re-confirmed at merge / rebase time.

| Item | Value |
| --- | --- |
| Verification fixed point | `deltaforesight/jpydf-v2` `develop` commit `30d078b` (history snapshot as of 2026-06-20) |
| Verification date | 2026-06-20 |
| chain | anvil 31337 (8 branches, 5 active seed) |
| Progress | **about 191 / about 1011 IDs** (PR #258 V1 campaign tally: main ledger 594 + Core 417, approximate) demonstrated on anvil. May not match this repo's displayed counts when PR #258 is unmerged. The remainder is in §4 |
| State | **In progress** (the continuation of this fixed point is reproducible from §1. When carrying it over to current `develop`, re-confirm the implementation state and the ID denominator) |

---

## 0. To whoever views this PR (handover guide)

**This PR is "partway done."** Whoever continues it can rebuild the environment and verify the remaining IDs in the same way by reading in the following order.

1. **What is finished** → §0.1 completion summary + the §3 evidence tables (per ID).
2. **How to reproduce** → the reproduction recipe in §1 (anvil start → deploy → seed, reproduced by copy-paste. Addresses are **deterministically identical** with a fixed salt).
3. **Which vocabulary to record in** → §2 result vocabulary.
4. **Where to continue from** → §4 incomplete map (component × remaining category, at a granularity where one chunk can be taken on at a time).
5. **Pitfalls** → §5 gotchas (the troveId formula, oracle staleness, the empty data of an access-control revert, etc. **If you do not read this, you will get stuck in the same place**).

### 0.1 Completion summary (about 191 IDs, all 6 categories)

| Category | Representatives demonstrated on anvil | Evidence § |
| --- | --- | --- |
| **FR functional** | borrow / in-kind redemption / SP deposit-withdraw / **the full trove-lifecycle** (open/addColl/withdrawColl/borrow/repay/close) / **Redemption** / **3-layer liquidation (SP offset)** / **Zapper 1-tx open** / **interest accrual → IRTR/SP distribution** / branch param / Core view group | §3.5,3.8,3.15,3.17,3.18 |
| **INV invariant** | backingRatio=1e18 / decimals=18 / **SCR<MCR<CCR** / liquidation-penalty ordering / supply-path singularity / ST size↔trove count consistency / interest conservation law | §3.1,3.10,3.11,3.15 |
| **SEC security** | OnlyVault / Ownable / AccessControl / **Core caller restriction on 7 functions** (sendColl/offset/insert etc. unauthorized → revert) / Strategy upgrade unauthorized rejection / transfer protection | §3.2,3.14 |
| **GOV governance** | per-role operations / pause/unpause / **owner-renounce immutable** / timelock ceremony (drill) | §3.2,3.10 |
| **EVT event** | CapUpdated / Deposited / Redeemed / Paused / Transfer(mint) **demonstrated emitted via the receipt's topic0** | §3.13 |
| **ERR failure** | DebtBelowMin / ICRBelowMCR / InterestRateTooHigh / empty-array liquidation / NothingToLiquidate / EmptyManager / WrongETH / ZeroAmount / TokenInfoNotSet and others | §3.16,3.18 |

⇒ **The representative paths of the SYS core flows are demonstrated with real anvil txs**: borrow (SYS-FR-001), in-kind redemption (FR-002), external-management push (FR-003), **autonomous peg correction (FR-004) = both Redemption and Liquidation**, JPY-denominated oracle happy path (FR-005), supply-path singularity (INV-003). Incomplete exception paths such as the cast standalone reproduction of Oracle staleness remain in §4.

---

## 1. Environment / reproduction recipe (rebuild the identical environment by copy-paste)

> anvil state is volatile (lost when the process stops). Because the salt is fixed, **the CREATE2 addresses are identical even on redeploy** (the address table in §1.3 can be used as-is).

### 1.1 Start anvil (resident)
```bash
~/.foundry/bin/anvil --port 8545 --chain-id 31337 --base-fee 0 --gas-limit 60000000
```

### 1.2 Deploy + seed (in a separate shell)
```bash
cd <jpydf-v2 clone>/contracts          # * Do not run forge on Google Drive. Use a disposable clone
DK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil#0
DA=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
NONK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # anvil#1 (for unauthorized tests)
CAP=115792089237316195423570985008687907853269984665640564039457584007913129639935

# deploy (fixed salt = deterministic addresses)
DEPLOYER=$DK SALT=jpydf-drill-1 \
  DF_TREASURY=$DA DF_INTEREST_ROUTER_RECIPIENT=$DA DF_INTEREST_ROUTER_OWNER=$DA \
  DF_STRATEGY_KIND=aave DF_STRATEGY_WEIGHT_BPS=10000 DF_STRATEGY_CAP=$CAP \
  forge script DeployLiquity2Script --chain-id 31337 --rpc-url http://localhost:8545 --broadcast --slow

# seed (create demo troves / SP deposits)
DEPLOYER=$DK forge script SeedLocalDemo --chain-id 31337 --rpc-url http://localhost:8545 --broadcast --slow

# Inject Multicall3 (for frontend / MultiTroveGetter)
cast rpc anvil_setCode 0xcA11bde05977b3631167028862bE2a173976CA11 "$(cat utils/multicall3-runtime.hex)" -r http://localhost:8545
```
After deploy, all addresses are output to `contracts/deployment-manifest.json` (§1.3 is the branch0 excerpt of that). If `ONCHAIN EXECUTION COMPLETE` appears twice, deploy+seed succeeded.

### 1.3 Main addresses (branch0, salt `jpydf-drill-1`, deterministic)
| Role | Address |
| --- | --- |
| collateralRegistry | `0x02b0b4efd909240fcb2eb5fae060dc60d112e3a4` |
| jpydfToken | `0x39b67ed1371cdf78cd0e6d4f0b78fa17a6dea663` |
| dToken(dETH) | `0x9a676e781a523b5d0c0e43731313a708cb607508` |
| collateralVault | `0x959922be3caee4b8cd9a407cc3ac1c251c2007b1` |
| strategy(AaveV3) | `0xe6e340d132b5f46d1e472debcd681b2abc16e57e` |
| WETH(underlying) | `0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0` |
| BorrowerOperations | `0xc9eda9ef65702d8d33b337890ef22e244424cd66` |
| TroveManager | `0xb6faae2bc2d55a9f041f255c8f373f2ff2bf7001` |
| StabilityPool | `0xcbc69577db47a4bf19b702f73a3ffdd1caa617ec` |
| sortedTroves | `0x61d7420ccee5db7680c68f59000320f7dde1d315` |
| priceFeed(branch0) | `0x96f3ce39ad2bfdcf92c0f6e2c2cabf83874660fc` |
| collUsdFeed(ETH/USD) | `0x59b670e9fa9d0a427751af201d676719a970857b` |
| jpyUsdFeed(JPY/USD) | `0x5fc8d32690cc91d4c39d9d3abcbd16989f875707` |
| interestRouter | `0x5b17e9f5ac8dae94731f7d8869d0d64f1a7f05c7` |
| zapper(CollateralYield) | `0x74cf9087ad26d541930bac724b7ab21ba8f00a27` |

> deployer/owner = anvil#0 `0xf39F…2266` (before governance handover, so it holds each owner/role). For unauthorized tests = anvil#1 `0x7099…79C8` (key `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`).

### 1.4 How to produce verifications (minimal cast forms)
```bash
RPC=http://localhost:8545; C=~/.foundry/bin/cast
$C call  <addr> 'fn()(type)'            -r $RPC          # view verification
$C send  <addr> 'fn(args)' <vals> --private-key $DK -r $RPC   # tx verification (happy)
$C send  <addr> 'fn(args)' <vals> --private-key $NONK -r $RPC # unauthorized → revert (exception)
$C rpc evm_snapshot / evm_revert <id>   # isolation of destructive / time-dependent tests
$C receipt <txhash> --json | jq .logs   # EVT: the topic0/data of emitted events
```

---

## 2. Result vocabulary
- `PASS@anvil(tx)` = real tx succeeded + expected state/event confirmed (happy path).
- `PASS@anvil(revert)` / `PASS@anvil(revert:<selector>)` = real tx reverted as expected (exception path).
- `PASS@anvil(view)` = expected value / mutual consistency confirmed via a view call.
- `PASS@anvil(event)` = event emission (topic0 match) confirmed in a real tx receipt's log.
- `PASS@tip` = green in the forge suite (test axis) of the verification fixed point / PR #258 V1 campaign. In this ledger it is used as a supplementary reference for time-dependent systems (the per-ID forge-side reference source is PR #258).
- `BLOCKED(unimplemented)` = no implementation exists at the verification fixed point `30d078b` (SKY / Treasury). / `TODO` = not started.

---

## 3. Verified IDs (evidence)

### 3.1 dToken (branch0 `0x9a676e…7508`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| DTKN-INV-001 | INV | `decimals()` | `=18` | PASS@anvil(view) |
| DTKN-FR-001 | FR | `name()`/`symbol()`/`cap()` | `"DToken dETH"`/`"dETH"`/set | PASS@anvil(view) |
| DTKN-FR-003 / INV-006 | FR/INV | `convertToDToken(1e18)` | `=1e18` (18dec, multiplier 1) | PASS@anvil(view) |
| DTKN-FR-004 happy path | FR | WETH→`vault.deposit(1e18)`→mint | balance `0→1e18` | PASS@anvil(tx) |
| DTKN-FR-004 / SEC-001 / INV-002 exception path | FR/SEC | non-vault `mint` | revert `OnlyVault 0x8d1af8bd` | PASS@anvil(revert) |
| DTKN-FR-005 / SEC-001 exception path | FR/SEC | non-vault `burn` | revert `OnlyVault 0x8d1af8bd` | PASS@anvil(revert) |
| DTKN-FR-006 happy path | FR | owner `setCap` | cap changed, tx succeeded | PASS@anvil(tx) |
| DTKN-FR-006 / SEC exception path | FR/SEC | non-owner `setCap` | revert `Ownable` | PASS@anvil(revert) |
| DTKN-FR-009 / GOV-003 / SEC-006 exception path | FR/GOV/SEC | `renounceOwnership()` | revert `RenounceOwnershipDisabled 0xffc0fd93` | PASS@anvil(revert) |
| DTKN-FR-002 / INV-010 exception path | FR/INV/ERR | `setAllowedUnderlying` after finalization | revert `TokenInfoAlreadySet 0xc60a4ce9` | PASS@anvil(revert) |

### 3.2 CollateralVault (branch0 `0x959922…`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| VAULT-FR-016 / INV-001/012 | INV | `backingRatio()` | `=1e18` (healthy) | PASS@anvil(view) |
| VAULT-FR-013 | FR | `totalUnderlying()`/`bufferBalance()` | `5.7e19` | PASS@anvil(view) |
| VAULT-FR-014 / SEC-006 happy path | FR/GOV | `pauseDeposit`(GUARDIAN)→`unpauseDeposit`(GOV) | paused→unpaused | PASS@anvil(tx) |
| VAULT-FR-001 / ERR-Paused exception path | FR/ERR | `deposit` while paused | revert(Paused) | PASS@anvil(revert) |
| VAULT-FR-014 / GOV-002 exception path | SEC/GOV | non-GUARDIAN `pauseDeposit` | revert (access, data `0x`*) | PASS@anvil(revert) |
| VAULT-FR-004 / SEC-005 exception path | SEC | non-ALLOCATOR `allocate` | revert (access) | PASS@anvil(revert) |
| VAULT-FR-004 happy path | FR | `allocate()`(ALLOCATOR) → strategy push | strategy `estimatedTotalUnderlying=4.56e19` | PASS@anvil(tx) |
| VAULT-FR-012 happy / exception path | FR/GOV/SEC | `setTreasury`(GOV) succeeds, non-GOV reverts | reflected / revert | PASS@anvil(tx/revert) |
| VAULT-FR-002 happy path | FR | `redeem(5e17)` immediate | dToken `1e18→5e17`, WETH `+5e17` | PASS@anvil(tx) |
| VAULT-ERR ZeroAmount | ERR | `deposit(0)`/`redeem(0)` | revert `0x1f2a2005` | PASS@anvil(revert) |

* access-control reverts return with empty data (`0x`) (the selector `AccessControlUnauthorizedAccount 0xe2517d3f` is not present). Control is demonstrated by the difference between an authorized success and an unauthorized revert (see §5 gotcha).

### 3.3 Oracle (PriceFeedProxy branch0 `0x96f3ce…`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| ORCL-FR-001/004 happy path | FR | `fetchPrice()` | `=6e23`, failed=false (JPY-denominated) | PASS@anvil(view) |
| ORCL-FR-002 happy path | FR | `fetchRedemptionPrice()` | `=6e23` | PASS@anvil(view) |
| ORCL-INV lastGoodPrice | INV | `lastGoodPrice()` | `=6e23` | PASS@anvil(view) |
| ORCL-FR-004 / ERR staleness exception path | ERR | `+25h`→`fetchPrice`→failsafe (snapshot isolation) | the staleness failsafe is `PASS@tip` in the forge oracle fork-test (the test axis is green). **The degenerate reproduction with anvil cast standalone is incomplete** and continues as remaining work for §4 Oracle | TODO@anvil / PASS@tip |

### 3.4 Strategy (AaveV3Strategy branch0 `0xe6e340…`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| STGY-INV-008 underlying | INV | `strategy.underlying()==vault.underlying()` | match | PASS@anvil(view) |
| STGY-FR estimatedTotalUnderlying | FR | managed balance after allocate | `4.56e19` (push reflected) | PASS@anvil(tx,view) |
| STGY-GOV owner/upgrader | GOV | `owner()`/`upgrader()` | deployer-held | PASS@anvil(view) |
| STGY-FR-009 / SEC-002/008 exception path | SEC | non-upgrader `setUpgrader` | revert | PASS@anvil(revert) |

### 3.5 Core user flows (borrow / SP / Redemption / JpydfToken, branch0)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| SYS-FR-001 / BO-FR-001 happy path | FR | `openTrove` (borrow with over-collateralization) | troves `4→5`, JPYdf `+400,000` | PASS@anvil(tx) |
| SP-FR provideToSP happy path | FR | `provideToSP(100k,false)` | SP `getCompoundedJpydfDeposit=2.112e24` | PASS@anvil(tx) |
| SP-FR withdrawFromSP happy path | FR | `withdrawFromSP(50k)` | deposit `2.112e24→2.062e24` | PASS@anvil(tx) |
| SYS-FR-004 / CR / TM redemption happy path | FR | `registry.redeemCollateral(10k,0,1e18)` (scans all 8 branches) | JPYdf burn, totalSupply `5.784e25→5.783e25` | PASS@anvil(tx) |
| SYS-INV-003 / supply singularity exception path | INV/SEC | `JpydfToken.mint` from non-Core | revert (Core mint/burn only) | PASS@anvil(revert) |
| BT-FR-008 transfer protection exception path | SEC | `JpydfToken.transfer` to a protocol address | revert | PASS@anvil(revert) |

### 3.6 InterestRouterForwarder (PIL, branch0 `0x5b17e9…`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| IRTR-FR recipient/owner | GOV | `recipient()`/`owner()` | =deployer | PASS@anvil(view) |
| IRTR-FR-001 route happy path | FR | `route()` (PIL 25% to recipient) | recipient JPYdf `7.84e24→7.852e24` | PASS@anvil(tx) |
| IRTR-SEC-001 exception path | SEC | non-owner `setRecipient` | revert | PASS@anvil(revert) |

### 3.7 Zapper wiring (CollateralYieldZapper `0x74cf90…`)
| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| ZAP-INV vault wiring | INV | `collateralVault()==branch0 vault` | match | PASS@anvil(view) |
| ZAP-SEC-007 receive exception path | SEC | sending ETH directly to the zapper | revert `OnlyWETH` | PASS@anvil(revert) |

### 3.8 trove-lifecycle + liquidation (branch0, correct troveId)
> troveId formula = `keccak256(abi.encode(msg.sender, _owner, _ownerIndex))` (**3 arguments**, `BorrowerOperations.sol:325`). §5 gotcha must read.

| ID | Category | Execution content | Evidence | Result |
| --- | --- | --- | --- | --- |
| BO-FR-001 open happy path | FR | `openTrove`(6 dETH, 500k) | status `=1`(active) | PASS@anvil(tx) |
| BO-FR addColl / withdrawColl happy path | FR | `addColl(+2)`/`withdrawColl(-1)` | real tx succeeded | PASS@anvil(tx) |
| BO-FR withdrawJpydf happy path (borrow) | FR | `withdrawJpydf(+100k)` | JPYdf `8e24→8.1e24` | PASS@anvil(tx) |
| BO-FR repayJpydf happy path (repay) | FR | `repayJpydf(-100k)` | real tx succeeded | PASS@anvil(tx) |
| BO-FR closeTrove happy path | FR | `closeTrove` (full repay → collateral returned) | status `=2`(closedByOwner) | PASS@anvil(tx) |
| **TM-FR / SYS-FR-004 liquidation (3-layer SP offset)** | FR | low-CR trove → price drops 18% → `batchLiquidateTroves` (snapshot isolation) | status `=3`(closedByLiquidation), **SP `5e24→2.497e24` (absorbs the debt via SP offset)** | PASS@anvil(tx) |

### 3.9 Per-branch parameters (branches 0–4)
| ID | Verification content | Evidence | Result |
| --- | --- | --- | --- |
| DTKN-INV-001 (all branches) | dToken.decimals | 5/5 `=18` | PASS@anvil(view) |
| DTKN-FR-003 non-18dec wrap | `convertToDToken` | dUSDC/dUSDT/dXAUT(6dec), dETH/dUSDS(18dec) all `→1e18` | PASS@anvil(view) |
| ORCL per-branch price | `fetchPrice()` failed=false | dETH`¥600k`/dUSDC・dUSDT`¥150`/dUSDS`¥160`/dXAUT`¥480k` | PASS@anvil(view) |

### 3.10 PRM value reconciliation (addressesRegistry, per branch) + JpydfToken
| ID | Verification content | Evidence | Result |
| --- | --- | --- | --- |
| PRM-MCR/SCR/BCR/CCR (all branches, absolute values) | `addressesRegistry` fetch | dETH`119.18/110/10/132.61%`, dUSDC・dUSDT`111.58/105/10/124.5%`, dUSDS`114.71/105/10/131.58%`, dXAUT`129/110/10/152.93%` | PASS@anvil(view) |
| PRM-INV-001 SCR<MCR<CCR (all branches) | ordering holds | e.g. dETH`110<119.18<132.61` | PASS@anvil(view) |
| PRM-BCR (mapping GAP resolved) | BCR=`10%` all branches | real values fetched | PASS@anvil(view) |
| VAULT-INV-001 backingRatio (all branches) | `=1e18` | 5/5 healthy | PASS@anvil(view) |
| BT-FR-010 / CORE-MOD-001 (GAP resolved) | `JpydfToken.name/symbol/decimals` | `"JPYdf Stablecoin"`/`"JPYdf"`/`18` | PASS@anvil(view) |
| SYS-GOV-001 owner renounce | `JpydfToken.owner()` | `=0x0` (renounced = immutable) | PASS@anvil(view) |

### 3.11 Core helpers / pools / liquidation penalties
| ID | Verification content | Evidence | Result |
| --- | --- | --- | --- |
| MTG-FR-001 (GAP resolved) | `MultiTroveGetter.getMultipleSortedTroves(0,0,3)` | array returned (view directly wired to frontend) | PASS@anvil(view) |
| HH-FR getApproxHint | `HintHelpers.getApproxHint` | hint returned | PASS@anvil(view) |
| GP-FR-001 (GAP resolved) | GasPool→BO `WETH.allowance` | `=max` (`1.157e77`) | PASS@anvil(view) |
| PRM-INV-003 (all branches) | `LIQUIDATION_PENALTY_SP ≤ REDISTRIBUTION` | SP`5%`≤Redist`10%` (5/5) | PASS@anvil(view) |
| PRM-INV-004 (all branches) | `1+PENALTY_SP ≤ MCR` | `105%`≤MCR (5/5) | PASS@anvil(view) |

### 3.12 inert branches (5–7) placeholder containment
| ID | Verification content | Evidence | Result |
| --- | --- | --- | --- |
| DTKN-FR-001 placeholder (5–7) | `cap()`/`name()` | `cap=0`, `"DToken Placeholder"` (3/3) | PASS@anvil(view) |
| DTKN-INV-008 exception path (5–7) | placeholder `convertToDToken` | TokenInfoNotSet revert (3/3) | PASS@anvil(revert) |
| VAULT-INV-011 containment (5–7) | inert vault `deposit` | revert (3/3, contained before activation) | PASS@anvil(revert) |
| SYS-GOV-001 exception path | `setBranchAddresses` after renounce | revert (immutable finalized) | PASS@anvil(revert) |

### 3.13 Event emission (EVT, real tx receipt logs)
> For EVT where "missing expectEmit" was a GAP in the mapping, it is demonstrated via the receipt that **on-chain it is emitted with the correct topic0/param**.

| ID | Execution content | Evidence | Result |
| --- | --- | --- | --- |
| DTKN-EVT-002 CapUpdated | `setCap` receipt | topic0 `0xd363…` emitted | PASS@anvil(event) |
| VAULT-EVT-001 Deposited | `deposit` receipt | topic0 `0x73a1…` emitted | PASS@anvil(event) |
| VAULT-EVT-012 Paused | `pauseDeposit` receipt | log emitted (`0x35ed…`) | PASS@anvil(event) |
| VAULT-EVT-002 Redeemed | `redeem` receipt | topic0 `0x764a…` emitted | PASS@anvil(event) |
| DTKN-EVT-003 Transfer(mint) | deposit tx | Transfer log with from=0x0 | PASS@anvil(event) |

### 3.14 Core caller restriction (SEC, from unauthorized anvil#1 → revert)
> For the internal-call restrictions that the mapping marked as "unauthorized-call revert delegated to base parity = no proprietary test," on-chain enforcement is demonstrated with real anvil txs.

| ID | Execution content | Result |
| --- | --- | --- |
| AP-SEC-001 ActivePool.sendColl(non-BO/TM/SP) | called from anvil#1 | PASS@anvil(revert) |
| AP-SEC-002 ActivePool.receiveColl | called from anvil#1 | PASS@anvil(revert) |
| DP-SEC-001 DefaultPool.sendCollToActivePool(non-TM) | called from anvil#1 | PASS@anvil(revert) |
| CSP-SEC-001 CollSurplusPool.accountSurplus(non-TM) | called from anvil#1 | PASS@anvil(revert) |
| ST-SEC-001 SortedTroves.insert(non-BO/TM) | called from anvil#1 | PASS@anvil(revert) |
| SP-SEC-001 StabilityPool.offset(non-TM) | called from anvil#1 | PASS@anvil(revert) |
| TM-SEC-001 TroveManager.onRedeemCollateral(non-CR) | called from anvil#1 | PASS@anvil(revert) |

### 3.15 Core view / getter (mutual consistency reconciliation)
| ID | Real call and value | Result |
| --- | --- | --- |
| CR getToken(0) / getTroveManager(0) | **matches** branch0 collToken / TM | PASS@anvil(view) |
| CR getRedemptionRate / WithDecay / baseRate | `1e18` / `9.992e17` / `1e18` | PASS@anvil(view) |
| TM getTroveIdsCount ↔ ST getSize | `4 == 4` (consistent) | PASS@anvil(view) |
| ST isEmpty / getFirst / contains | `false` / value / contains determination correct | PASS@anvil(view) |
| TM getCurrentICR(first) / status / interest rate | `1.686e18`(168.6%) / `1`(active) / `5.2e16` | PASS@anvil(view) |
| **BO MCR/CCR/SCR/BCR** | `1.1918`/`1.326`/`1.1`/`0.1` e18 → **SCR<MCR<CCR holds** | PASS@anvil(view) |
| SP getTotalJpydfDeposits / getCompoundedJpydfDeposit | `5e24` / `2e24` | PASS@anvil(view) |
| AP getCollBalance / getJpydfDebt / calcPendingAggInterest | `56 dETH` / `2.02e25` / `3.38e18` | PASS@anvil(view) |

### 3.16 Exception paths (ERR) — the revert paths of BO/TM/CR
> Error definition identification: `BorrowerOperations.sol:137-146` (ICRBelowMCR / DebtBelowMin / InterestRateTooLow/High and others).

| ID | Invalid input | Result |
| --- | --- | --- |
| BO-ERR DebtBelowMin | open(debt 100k < MIN_DEBT 300k) | PASS@anvil(revert) |
| BO-ERR ICRBelowMCR | open(coll 0.1 dETH, debt 300k → ICR≈20%) | PASS@anvil(revert) |
| BO-ERR InterestRateTooHigh | open(rate 200% > max) → `0xfe4a4370` | PASS@anvil(revert) |
| TM-ERR empty-array liquidation | batchLiquidateTroves(`[]`) | PASS@anvil(revert) |
| TM-ERR NothingToLiquidate | batchLiquidate(`[healthy trove]`) | PASS@anvil(revert) |
| CR-ERR 0 redemption | redeemCollateral(`0`,…) | PASS@anvil(revert) |

### 3.17 Interest accrual / distribution (time-dependent, `evm_increaseTime` isolation)
> Time-dependent systems observable only on anvil. snapshot isolation → `+365 days` → refresh `updatedAt` of both feeds (avoid stale) → distribution fires on a debt-update op.

| ID | Execution content and value | Result |
| --- | --- | --- |
| Interest accumulation (time-dependent) | `+365 days` makes `calcPendingAggInterest` `0→1,662,345 JPYdf` | PASS@anvil(tx) |
| **IRTR-FR InterestRouter receipt** | IR balance **+415,728 JPYdf** after trigger | PASS@anvil(tx) |
| **SP yield split** | SP `getYieldGainsOwed` **+1,247,186 JPYdf** after trigger | PASS@anvil(tx) |
| Distribution ratio / conservation law | IR:SP ≈ **25:75**, total ≈ accumulated interest (match) | PASS@anvil(tx) |

### 3.18 Zapper 1-tx open (DF-proprietary, ETH→dToken→trove)
> "RawETH" = raw ETH for gas compensation only (`msg.value==ETH_GAS_COMPENSATION` fixed, `L405`); the collateral is the underlying (WETH) via `transferFrom`.

| ID | Execution content | Result |
| --- | --- | --- |
| ZAP-FR openTroveWithRawETH | collAmount=6 WETH + msg.value=gas comp, managers=owner → **trove count `5→6`, success** | PASS@anvil(tx) |
| ZAP-ERR EmptyManager | open with managers=`0x0` → revert `0x22359217` | PASS@anvil(revert) |
| ZAP-ERR WrongETH | msg.value≠gas comp → revert | PASS@anvil(revert) |

---

## 4. Incomplete ID map (continue from here)

> The **majority of the remainder is already covered by the forge suite (1170 passed) of the verification fixed point `30d078b`** = the implementation and tests are green. The remaining work of this ledger is "the third axis that also reproduces it with real anvil txs." Priority is **(A) representative exception paths / EVT of each component via real txs → (B) Core detailed functions → (C) branch-specific → (D) frontend**. Counts are approximate (for the per-ID inventory, refer to the main ledger / Core ledger of the PR #258 V1 campaign. In current `develop`, the implementation state and ID denominator may change).

| component / namespace | anvil done | anvil remaining (main content) | forge | startup memo |
| --- | --- | --- | --- | --- |
| dToken `DTKN` | ~10 | permit(EIP-712 signed tx), UUPS upgrade(new impl→upgradeTo), 2-step owner(transfer→accept), remaining EVT(TokenInfoSet/Ownership/AllowedUnderlyingUpdated), ERR(CapExceeded/NotContract/InvalidUnderlyingDecimals) | PASS@tip | using a placeholder dToken can emit ERR for the unfinalized state |
| CollateralVault `VAULT` | ~12 | harvest/skim, remaining role operations (full GOV/GUARDIAN coverage), emergencyDisableStrategy(VAULT-FR-019), remaining EVT/ERR, delayed redemption + claim path | PASS@tip | delayed redemption is triggered by creating a buffer shortage |
| Strategy `STGY`/`AAVE`/`E4626`/`LIDO` | ~4 | deposit/withdraw/harvest real amounts, allocator cooldown (time-dependent), remaining SEC/EVT, LIDO-specific (stETH rebase) | PASS@tip | cooldown is `evm_increaseTime` isolated |
| Oracle `ORCL` | ~4 | cast standalone reproduction of per-branch staleness / failure degeneracy, redemption price branching | PASS@tip(+drill) | for time-dependent, the feed refresh procedure in §5 |
| Zapper `ZAP` | ~5 | close/adjust/addColl WithUnderlying, Sky USDC route, remaining SEC(leftover sweep) | PASS@tip | open is established in §3.18. close requires troveNFT owner authorization |
| Parameters `PRM` | ~10 | remaining INV(full per-branch coverage), bridge-minter-timelock | PASS@tip | view-centric, can be gained by horizontal expansion |
| InterestRouter `IRTR` | ~3 | remaining route branches, owner handover ceremony | PASS@tip | |
| **Core BO** `CORE-BO` | ~10 | adjustZombieTrove, applyPendingDebt, interestIndividualDelegate, batch operations, shutdown path, remaining ERR(~60) | PASS@tip | open/close/adjust established in §3.8. The rest are derived functions |
| **Core TM** `CORE-TM` | ~8 | urgentRedemption, redistribution layer(on SP depletion), batch liquidation, getLatestTroveData family, remaining view(~70) | PASS@tip | redistribution is triggered by emptying the SP |
| **Core SP** `CORE-SP` | ~6 | collGain claim, epoch/scale transition, remaining EVT | PASS@tip | the post-liquidation collGain as a continuation of §3.8 |
| Core CR/AP/DP/CSP/ST/HH/MTG and others | ~12 | full coverage of each getter/branch, CollSurplus claim, SortedTroves re-insertion | PASS@tip | view horizontal expansion + claim of liquidation surplus |
| **SKY Strategy** `SKY` | 0 | **all IDs BLOCKED(unimplemented)** | — | unimplemented at the `30d078b` fixed point. In current `develop` the implementation state may change, so re-confirm when continuing |
| **Treasury** `TRSY` | 0 | **all IDs BLOCKED(unimplemented)** | — | unimplemented at the `30d078b` fixed point. Out of scope until implemented |
| Frontend `FRNT` | 0 | admin operations via console/ops; the app via Playwright for borrow/redeem/earn after subgraph recovery | e2e-local | subgraph(graph-node Docker) needs recovery. See §5 |

---

## 5. Known gotchas / lessons (if you do not read this, you will get stuck in the same place)

1. **The troveId formula takes 3 arguments**: `uint256(keccak256(abi.encode(msg.sender, _owner, _ownerIndex)))` (`BorrowerOperations.sol:325`). `msg.sender` is the **caller** of openTrove. For a direct EOA call it is the EOA; via the Zapper it is the Zapper address. Computing with 2 arguments yields status=0 (does not exist), and the whole lifecycle/liquidation gets stuck.
2. **An access-control revert can return with empty data (`0x`)** (the selector of `AccessControlUnauthorizedAccount 0xe2517d3f` is not present). Demonstrate via the **difference** between "authorized succeeds, unauthorized reverts."
3. **Advancing time staleness the oracle**: after `evm_increaseTime`, `block.timestamp` advances, so the feed `updatedAt` from deploy time becomes old and the `fetchPrice` family degenerates/reverts. Refresh by sending `setUpdatedAt(<new timestamp>)` to **both feeds** (`collUsdFeed`=ETH/USD, `jpyUsdFeed`=JPY/USD) before operating. Changing the price is done with `LocalChainlinkAggregator.setAnswer(int256)` (not `setPrice`/`updateAnswer`).
4. **Destructive / time-dependent tests must always be isolated with `evm_snapshot`→…→`evm_revert`** (liquidation, price manipulation, time advancement). Do not break the shared anvil's seed state.
5. **BOLD→JPYdf rename**: SP is `getTotalJpydfDeposits`/`getCompoundedJpydfDeposit` (`…BoldDeposits` reverts). Borrow/repay are `withdrawJpydf`/`repayJpydf`.
6. **Where getters live**: `MCR/SCR/BCR/LIQUIDATION_PENALTY_*` **revert on TroveManager**; take them from `addressesRegistry` (or BO's `MCR()/CCR()/SCR()/BCR()`). Only `CCR()` is also on TM.
7. **Zapper openTroveWithRawETH**: `msg.value` is **exactly ETH_GAS_COMPENSATION** (`0.0375 ETH`). The collateral is the underlying (WETH), separately `approve`d + `transferFrom`. Setting `addManager`/`removeManager` to `0x0` reverts with `EmptyManager(0x22359217)` (put in the owner).
8. **Deploy by calling `forge script DeployLiquity2Script` directly, not via the CLI `./deploy local`** (the CLI failed due to missing `DF_INTEREST_ROUTER_RECIPIENT`/`DF_STRATEGY_KIND_0`). The env is the recipe in §1.2.
9. **Do not run forge on Google Drive** (path spaces / sync break it). Run in a disposable clone (`/tmp/...`) and return only the ledger to Drive/repo.
10. **The frontend app requires the subgraph**: if the graph-node Docker (port 8020) is down, subgraph deploy is `ECONNREFUSED`. Run app-mediated flows with Playwright after graph-node recovery. Admin-type operations do not need the subgraph, so they can proceed first from console/ops.

---

## 6. Related documents
- [Requirements-Verification-Ledger.md](../../verification-ledgers/Requirements-Verification-Ledger.md) — main ledger (the current display on this repo. When PR #258 is unmerged, it may differ from the V1 campaign tally of 594 IDs).
- [Core-Requirements-Verification-Ledger.md](../../verification-ledgers/Core-Requirements-Verification-Ledger.md) — Core(BO/TM/SP/…) ledger (the current display on this repo. When PR #258 is unmerged, it may differ from the V1 campaign tally of ~417 IDs).
- **PR #258** (`docs/requirements-verification-campaign-v1`) — the V1 mapping campaign (forge baseline **1170 passed**, per-row `PASS@tip` about 592, includes the 2026-06-20 review group). The **forge-side coverage reference source** of this ledger. If unmerged, treat this ledger as a history snapshot of the `30d078b` fixed point.
- Time-dependent systems (staleness/shutdown, etc.) can be confirmed by running a fork-test-style drill on the same anvil deploy (the procedure in §5). The drill test itself is a local work artifact and is not included in this repo.
