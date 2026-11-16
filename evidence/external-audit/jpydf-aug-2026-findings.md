# Findings

# High

# High 01 PSM Fee (`tout > 0`) Bricks All `SkyUsdcSUsdsStrategy` Withdrawal Paths

## Location
SkyUsdcSUsdsStrategy.sol

SkyUsdcSUsdsStrategyConvertor.sol

## Description
`SkyUsdcSUsdsStrategy._convertUsdsToUsdc` passes `_usdsAmount` to the converter as a USDS budget, then asserts the strategy's USDS balance dropped by exactly that full amount:

```solidity
// SkyUsdcSUsdsStrategy.sol:322–328
uint256 usdsBalanceBefore = usds.balanceOf(address(this));
usds.forceApprove(address(converterCached), _usdsAmount);
converterCached.convertUsdsToUsdc(_usdsAmount, enforcedMinUsdcOut, address(this));
usds.forceApprove(address(converterCached), 0);
_requireTokenBalance(usds, usdsBalanceBefore - _usdsAmount);  // strict == check
```

The converter is output-denominated: it pulls the full `_maxUsdsIn` budget from the strategy (L182), calls the Sky PSM `buyGem` with a pre-computed USDC output amount, then refunds any unspent USDS back to the strategy:

```solidity
// SkyUsdcSUsdsStrategyConvertor.sol:200-201
uint256 refund = _maxUsdsIn - actualUsdsIn;
if (refund != 0) usds.safeTransfer(msg.sender, refund);  // refund lands back in strategy
```

When `tout > 0`, the PSM charges a fee so `actualUsdsIn < _maxUsdsIn` — the refund is nonzero. After the converter returns, the strategy's USDS balance is `usdsBalanceBefore - actualUsdsIn`, which is **higher** than `usdsBalanceBefore - _usdsAmount`. The strict `!=` check in `_requireTokenBalance` reverts with `SkyUsdcSUsdsStrategy__UnexpectedTokenBalance`.

All three exit paths call `_convertUsdsToUsdc` with no try/catch and fail simultaneously:

- `_doWithdraw` — normal user redemption path

- `emergencyConvertIdleUsdsToVault` — admin emergency conversion

- `emergencyWithdrawFromSky` — admin emergency full withdrawal

There is no bypass. The only escape is a UUPS proxy upgrade.

## Proof of Concept
`test/SkyConverterRefund.t.sol` — run with `forge test --match-test "test_converterRefund" -vvv`:

```solidity
// Mock converter that correctly simulates Sky LitePSM buyGem refund behaviour:
// 1. Pulls maxUsdsIn from strategy
// 2. Consumes only usdsRequired (= usdcOut * 1e12 * (WAD + tout) / WAD)
// 3. Refunds (maxUsdsIn - usdsRequired) back to msg.sender
contract MockConverterWithRefund is ISkyUsdcSUsdsStrategyConverter {
    uint256 public tout; // e.g. 5e15 = 0.5%

    function convertUsdsToUsdc(uint256 maxUsdsIn, uint256 minUsdcOut, address receiver)
        external returns (uint256 usdcOut)
    {
        uint256 usdsRequired = usdcOut * 1e12 + (usdcOut * 1e12 * tout) / 1e18;
        // Pull full budget from strategy
        IERC20(address(usds)).safeTransferFrom(msg.sender, address(this), maxUsdsIn);
        usds.burn(address(this), usdsRequired);
        uint256 refund = maxUsdsIn - usdsRequired;
        if (refund > 0) {
            IERC20(address(usds)).safeTransfer(msg.sender, refund); // ← this refund breaks strategy
        }
        usdc.mint(receiver, usdcOut);
    }
}

// Test 1: tout=0 -> no refund -> succeeds
function test_converterRefund_noFee_succeeds() public {
    converter.setTout(0);
    _depositAndAllocate(vault, usdc, 1_000e6);
    uint256 sent = strategy.sendToVault(500e6);
    assertEq(sent, 500e6, "should succeed with zero tout");
}

// Test 2: tout=0.5% -> refund fires -> _requireTokenBalance reverts
function test_converterRefundRevert() public {
    converter.setTout(5e15); // 0.5%
    _depositAndAllocate(vault, usdc, 1_000e6);

    (bool ok, bytes memory returndata) = address(strategy).call(
        abi.encodeWithSelector(strategy.sendToVault.selector, uint256(500e6))
    );
    assertFalse(ok, "sendToVault must revert when tout > 0");
    bytes4 gotSelector;
    assembly { gotSelector := mload(add(returndata, 32)) }
    assertEq(gotSelector,
        SkyUsdcSUsdsStrategy.SkyUsdcSUsdsStrategy__UnexpectedTokenBalance.selector
    );
}

// Test 3: emergency path also reverts
function test_converterRefundRevert_emergencyPath() public {
    converter.setTout(5e15);
    _depositAndAllocate(vault, usdc, 1_000e6);
    strategy.emergencyRedeemSUsdsToUsds(type(uint256).max); // works (no converter)
    assertGt(strategy.ownIdleUsds(), 0);

    (bool ok2,) = address(strategy).call(
        abi.encodeWithSelector(
            strategy.emergencyConvertIdleUsdsToVault.selector,
            type(uint256).max, uint256(0)
        )
    );
    assertFalse(ok2, "emergencyConvert must revert when tout > 0");
}
```

Results:
```
[PASS] test_converterRefund_noFee_succeeds()
[PASS] test_converterRefundRevert()
[PASS] test_converterRefundRevert_emergencyPath()
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

`tout = 0` today — the bug is dormant. `tout > 0` is a routine Sky governance action with historical precedent.

## Recommendation
Replace the strict balance check with an under-spend guard, and track actual USDS consumed:

```solidity
uint256 usdsBalanceBefore = usds.balanceOf(address(this));
usds.forceApprove(address(converterCached), _usdsAmount);
converterCached.convertUsdsToUsdc(_usdsAmount, enforcedMinUsdcOut, address(this));
usds.forceApprove(address(converterCached), 0);

uint256 usdsBalanceAfter = usds.balanceOf(address(this));
// Guard: converter must not take MORE than the approved budget
if (usdsBalanceAfter < usdsBalanceBefore - _usdsAmount) {
    revert SkyUsdcSUsdsStrategy__UnexpectedTokenBalance(...);
}
uint256 actualUsdsSpent = usdsBalanceBefore - usdsBalanceAfter;
_decreaseOwnIdleUsds(actualUsdsSpent);  // use actual, not _usdsAmount
```

## Status
New

# Medium

# Mid 01 AAVE Pool Address Staleness

## Location
AaveV3Strategy.sol (initializer, approval, all pool calls)

## Description
`AaveV3Strategy` stores the Aave V3 Pool address in a mutable state variable `aavePool` that is set once at initialization and has no update function. All interactions — `supply`, `withdraw`, `getReserveNormalizedIncome` — are hard-coded to this single address. The `max` underlying approval is also given exclusively to this address at initialization:

```solidity
// AaveV3Strategy.sol
aavePool = _aavePool;
_underlying.forceApprove(address(_aavePool), type(uint256).max);
```

Aave V3 uses an upgradeable proxy architecture where the **Pool proxy address is fixed**, but Aave governance can deploy a new Pool implementation and, in extreme cases (such as the Aave V3.1 migration on Ethereum mainnet), can change which address is canonical. More practically, Aave has deployed separate Pool instances for different markets (core market, prime market, Lido market) and has migrated liquidity between them. If the protocol deploys `AaveV3Strategy` pointing at one Pool instance and Aave governance migrates the underlying reserve to a new Pool contract, the strategy can no longer interact with the live reserve — `supply` and `withdraw` calls revert or operate on a deprecated pool with no liquidity.

There is no `setAavePool(address)` function, no `setAToken(address)` function, and no way to update the approval to a new pool address without upgrading the strategy implementation via the `upgrader` key. Because the approval is also address-specific, even a simple pool address update would require revoking the old approval and granting a new one — which is not possible without an upgrade.

Note: The `aToken` address is similarly fixed at initialization (`aToken = _aToken`). If Aave migrates to a new aToken for the same underlying (as it has done in V2 -> V3 migrations), both addresses become stale simultaneously.

## Proof of Concept
Let's have the following situation:

1. Protocol deploys `AaveV3Strategy` pointing at `aavePool = 0xAaveV3Core` with `forceApprove(0xAaveV3Core, max)`.

2. Aave governance deploys a new Pool implementation at `0xAaveV3Prime` for the USDC prime market, or migrates the USDC reserve.

3. `aavePool.supply` on the old address reverts or deposits into a deprecated pool with no yield.

4. `aavePool.withdraw` on the old address has no liquidity — strategy funds are stranded in the old pool.

5. If the new pool uses a different aToken address, `aavePool.getReserveNormalizedIncome` also returns data for the wrong reserve, silently mispricing the strategy's position in vault accounting.

## Recommendation
Instead of storing the pool address at all, derive it dynamically from the Aave `PoolAddressesProvider`, which is the canonical source of truth for the current Pool address and always reflects upgrades:

```solidity
IPoolAddressesProvider public immutable aaveAddressesProvider;

function _pool() internal view returns (IAaveV3Pool) {
    return IAaveV3Pool(aaveAddressesProvider.getPool());
}
```

This approach is recommended by Aave, and this is how other protocol integrations avoid staleness.

## Status
New

# Mid 02 `PriceFeedProxy::confirmSource` Skips 1% Price Deviation Guard When Old Source Is Unhealthy

## Location
PriceFeedProxy.sol (`confirmSource`)

PriceFeedProxy.sol (`_readSourceIfHealthy`)

## Description
`confirmSource` is designed to verify the new price feed source is within 1% of the current price before accepting it. The guard condition is `!_bypassPriceGuard && oldRead.healthy`. When the old source is unhealthy (returns stale data or reverts), `_readSourceIfHealthy` returns a zero-initialized struct with `healthy = false`. This causes the 1% deviation check to be skipped entirely on the normal `confirmSource` path.

```solidity
// The guard short-circuits when old source is unhealthy
if (!_bypassPriceGuard && oldRead.healthy) {
    // 1% check — only runs if old source is healthy
}
// If old source is down: guard never runs, new source accepted at any price
```

This is triggered by an oracle outage — not by governance. An operator runs a scheduled source rotation after the 24h timelock. If the old source happened to go down in the intervening period, the new source is accepted at an arbitrary price with no continuity check. A large price jump in the new source at the switch block is MEV-exploitable for liquidation arbitrage.

## Proof of Concept
Let's have the following situation:

1. `PriceFeedProxy` source rotation proposed, 24h timelock starts
 
2. Old Chainlink feed becomes stale/unhealthy during the 24h window
 
3. Operator calls `confirmSource` after 24h
 
4. `_readSourceIfHealthy(oldSource)` returns `healthy = false`
 
5. 1% deviation guard skipped
 
6. New source accepted regardless of price delta
 
7. If new source reports 10% lower price: all Troves near MCR instantly liquidatable

## Recommendation
Use `lastGoodPrice` as the reference when the old source is unhealthy, rather than skipping the guard:

```solidity
uint256 referencePrice = oldRead.healthy ? oldRead.price : _lastGoodPrice;
if (!_bypassPriceGuard) {
    require(priceDelta(newRead.price, referencePrice) <= MAX_DEVIATION, "PriceContinuityBroken");
}
```

## Status
New

# Mid 03 JPY Freeze Clock Starts At First Call, Not Oracle Failure — Zero-Traffic Branch Never Shuts Down

## Location
DFPriceFeedBase.sol

## Description
`DFPriceFeedBase._convertUsdPriceToJpyWithFreeze` starts the 24-hour shutdown countdown by setting `jpyFrozenSince = block.timestamp` on the **first call** that encounters a JPY oracle failure — not at the oracle's actual failure time:

```solidity
// DFPriceFeedBase.sol
if (jpyUsdOracleDown) {
    jpyUsdRate = lastGoodJpyRate;
    if (jpyFrozenSince == 0) {
        jpyFrozenSince = block.timestamp;  // set on first CALL, not oracle failure
    } else if (block.timestamp - jpyFrozenSince >= MAX_JPY_FREEZE_DURATION) {
        return (0, true);                  // shutdown only after 24h from first call
    }
}
```

If no one calls `fetchPrice` on a branch during an outage, `jpyFrozenSince` remains `0` indefinitely. A call made weeks later sets `jpyFrozenSince` to that later timestamp, restarting the 24-hour window regardless of how long the oracle has been stale.

- Active (frequent calls): 72h staleness threshold + 24h freeze = 96 hours

- Dormant (gap D hours): 72h + D + 24h

- Zero-traffic / never called: Indefinite — shutdown never triggers

The same logic is duplicated verbatim in `sUSDSPriceFeed.sol`.

A stale JPY/USD rate affects every collateral ratio calculation on the branch. During the BoJ intervention of July 2024, JPY strengthened ~13% against USD in four days — a 96-hour stale rate during such an event corresponds to a 3–13% collateral mispricing, delaying liquidations and allowing undercollateralized debt to persist. For zero-traffic branches the mispricing is unbounded.

## Recommendation
Anchor `jpyFrozenSince` to the oracle's `updatedAt` timestamp from the last healthy read:

```solidity
// On healthy read: store updatedAt
lastGoodJpyUpdatedAt = chainlinkUpdatedAt;

// On first failure, freeze clock from oracle's own stale point:
if (jpyFrozenSince == 0) {
    jpyFrozenSince = lastGoodJpyUpdatedAt + jpyUsdStalenessThreshold;
}
```

Apply the same fix to `sUSDSPriceFeed.sol`.

## Status
New

# Low

# Low 01 AAVE v3 Supply Cap Revert

## Location
CollateralVault.sol (`strategy.deposit`)

AaveV3Strategy.sol (`aavePool.supply`)

## Description
`_allocateToStrategies` loops over all registered strategies and calls `strategy.deposit` for each. There is no `try/catch` around the deposit call. If any single strategy's `deposit` reverts, the **entire `allocate` transaction reverts**, preventing all other strategies in the loop from receiving their allocation that round.

```solidity
// CollateralVault.sol
if (targetAllocation > 0) {
    underlying.safeTransfer(address(strategy), targetAllocation);       // sent first
    uint256 strategyUnderlyingReceived = underlying.balanceOf(address(strategy)) - strategyUnderlyingBeforeTransfer;
    strategy.deposit(strategyUnderlyingReceived);                        // no try/catch
    // if deposit reverts, entire tx reverts including L1240 transfer
}
```

The concrete trigger is Aave V3's per-reserve **supply cap**. Aave governance sets a `supplyCap` for each asset (e.g. 1 billion USDC). Once the total Aave V3 supply of USDC reaches that cap, any call to `aavePool.supply` reverts with `SupplyCapExceeded`. When this happens:

1. `AaveV3Strategy._doDeposit` calls `aavePool.supply` -> reverts
 
2. `strategy.deposit` reverts
 
3. The entire `allocate()` call reverts
 
4. All other strategies (Lido, ERC4626, Sky) **also receive no allocation**
 
5. `transferYieldToTreasury` also fails because it calls the same allocation path

The GUARDIAN can call `emergencyDisableStrategy(aaveStrategy)` to remove it from the loop — but this requires a separate transaction and human intervention. Until that happens, no capital can be deployed to any strategy. If Aave supply caps are hit during a period of high market activity and GUARDIAN response is delayed, the vault sits with 100% of capital in the buffer earning no yield.

## Proof of Concept
Let's have the following situation:

1. Aave V3 USDC `supplyCap` is reached (currently set at ~1.8B USDC on mainnet).

2. ALLOCATOR calls `allocate` on the JPYdf vault.

3. `_allocateToStrategies` reaches `AaveV3Strategy` in the loop.

4. `strategy.deposit(amount)` -> `_doDeposit` -> `aavePool.supply` -> reverts `SupplyCapExceeded`.

5. Entire `allocate` tx reverts. `LidoStrategy`, `ERC4626Strategy`, `SkyStrategy` all skipped.

6. Buffer accumulates; strategies receive no new capital; yield generation drops to zero across all strategies until GUARDIAN disables `AaveV3Strategy`.

## Recommendation
Wrap `strategy.deposit` in a `try/catch` so that a single strategy failure is isolated and other strategies can still receive their allocation:

```solidity
// CollateralVault.sol
if (targetAllocation > 0) {
    uint256 strategyUnderlyingBeforeTransfer = underlying.balanceOf(address(strategy));
    underlying.safeTransfer(address(strategy), targetAllocation);
    uint256 strategyUnderlyingReceived =
        underlying.balanceOf(address(strategy)) - strategyUnderlyingBeforeTransfer;

    try strategy.deposit(strategyUnderlyingReceived) {
        if (!_refreshStrategyValuation(strategy)) {
            _setStrategyValuationCache(strategy, currentConservativeValue + strategyUnderlyingReceived);
        }
        remainingAllocation -= targetAllocation;
        emit StrategyAllocated(address(strategy), strategyUnderlyingReceived);
    } catch {
        // Deposit failed — idle underlying remains in strategy, skip this strategy
        emit StrategyAllocationSkipped(address(strategy));
        // Note: underlying is now idle in strategy; owner should call emergencyWithdraw
    }
}
```

This ensures one failing strategy does not cascade into a vault-wide allocation freeze. The idle underlying left in the failing strategy is recoverable via `BaseStrategy.emergencyWithdraw`.

Separately, consider checking whether the Aave supply cap has remaining capacity before attempting the deposit:

```solidity
// Pre-check: skip if Aave supply cap is full
IPool.ReserveData memory data = aavePool.getReserveData(address(underlyingToken));
uint256 supplyCap = data.configuration.getSupplyCap() * 10 ** decimals;
uint256 currentSupply = aToken.totalSupply();
if (currentSupply >= supplyCap) revert AaveSupplyCapReached();
```

## Status
New

# Low 02 Allocate Mis-Sizes Buffer Target When Strategy View Is Unavailable

## Location
CollateralVault.sol

## Description
Two internal view functions serve different purposes but use different fallback strategies for unavailable Strategy valuations:

- `totalUnderlying` (solvency math) uses `_strategyConservativeValue` which falls back to the cached value on live read failure

- `_managedUnderlying` (buffer sizing for allocation) uses `_strategyConservativeValueLiveOrZero` which returns 0 on live read failure — no cache fallback

When any registered, enabled Strategy's `estimatedTotalUnderlying` or `principal` view reverts (paused upstream market, stale oracle, transient gas issue), `_managedUnderlying` understates total system assets. This feeds `_requiredBuffer` which computes the target buffer as `bufferTargetBps%` of the understated number.

Since `_managedUnderlying` is too low, the target buffer is too low, making the actual buffer appear excessive. `allocate` then pushes this "excess" to other strategies — the exact moment a Strategy's health is uncertain, the system moves liquidity away from the buffer.

Concrete trace with buffer = 100, Strategy A = 800 (view reverting), Strategy B = 200 (healthy):

- Correct (A live): `_managedUnderlying` = 1,100, `_requiredBuffer` (20%) = 220, buffer 100 < 220 -> no excess

- Computed (A reverting): `_managedUnderlying` = 300, `_requiredBuffer` (20%) = 60, buffer 100 > 60 -> excess 40

Result: 40 is pushed from buffer to Strategy B. Buffer drops from 100 to 60. A redemption of 80 that would have been served instantly now requires a 1-day delayed claim for 20.

Impact is strictly operational: no fund loss (the 40 lands in Strategy B and is recoverable via `sendToVault`), and the effect is transient — once the Strategy's view recovers, the next `allocate` computes the correct picture.

## Recommendation
Have `_managedUnderlying` fall back to the cached conservative value (same pattern as `totalUnderlying`) rather than defaulting to 0 on live read failure:

```solidity
function _managedUnderlying() internal view returns (uint256 total) {
    total = bufferBalance();
    uint256 strategyCount = strategies.length;
    for (uint256 strategyIndex; strategyIndex < strategyCount; strategyIndex++) {
        total += _strategyConservativeValue(strategies[strategyIndex]);
    }
}
```

This ensures a transient view failure does not cause the buffer target to be understated. The cached conservative value (`min(estimated, principal)`) is always <= the true value, so the buffer target cannot be inflated — it can only be slightly understated (by at most the unrealized yield captured in the cache), which is the safe direction.

## Status
New

# Low 03 Contract Receiver In `redeem` Creates Permanently Unclaimable `WithdrawRequest`

## Location
CollateralVault.sol (`redeem`)

CollateralVault.sol (`claim`)

## Description
`redeem(amount, _receiver)` sets `WithdrawRequest.owner = _receiver`. Only the owner can call `claim(requestId)`. If `_receiver` is a smart contract — such as a Zapper, a multisig with no claim function, or an automated protocol — that has no `claim` integration or whose interface does not expose it, the queued underlying is permanently unclaimable. The dTokens are burned at redeem time.

```solidity
// redeem() — receiver becomes the owner
withdrawRequests[requestId] = WithdrawRequest({
    owner: _receiver,     // ← must implement claim() to retrieve funds
    underlyingAmount: _remaining,
    ...
});

// claim() — only owner can call
require(msg.sender == req.owner, "NotOwner");
```

This is a common integration mistake when routing through Zappers or automated protocols that do not anticipate a two-step withdrawal pattern. The dTokens are burned and the underlying is permanently locked.

## Recommendation
Add a `onBehalfOf` parameter to `claim` that allows the original depositor (or a pre-authorized address) to claim on behalf of a contract receiver, or add a `transferWithdrawRequest` function that allows the request owner to reassign ownership before claiming.

## Status
New

# Low 04 Independent JPY Freeze Timers Create Cross-Branch Price Divergence

## Location
DFPriceFeedBase.sol (`lastGoodJpyRate`, `jpyFrozenSince`)

sUSDSPriceFeed.sol (duplicated state)

## Description
`DFPriceFeedBase` and `sUSDSPriceFeed` each maintain independent copies of `lastGoodJpyRate` and `jpyFrozenSince`. The JPY/USD oracle is shared across all branches, but the freeze logic is per-instance. During a JPY oracle outage, different branches freeze at slightly different rates depending on when each branch's `fetchPrice()` was last called.

This creates cross-branch pricing inconsistency: dETH and dUSDS branches may report different JPY collateral prices during the freeze window, creating arbitrage between branches. Each instance also has its own 24h freeze clock, so branches may shut down at different times.

## Recommendation
Extract the JPY freeze mechanism into a shared `JPYFreezeBase` contract that both price feeds inherit from. This ensures a single shared `lastGoodJpyRate` and `jpyFrozenSince` across all branches, eliminating divergence.

## Status
New

# Low 05 `InterestRouterForwarder::setRecipient` Missing `requireValidRecipient` — `route` Permanently Bricked By Misconfiguration

## Location
InterestRouterForwarder.sol

## Description
`setRecipient` validates only that the new recipient is not `address(0)`. It does not call `IJpydfToken::requireValidRecipient`, which blocks transfers to core Liquity protocol contracts: `TroveManager`, `StabilityPool`, `BorrowerOperations`, `ActivePool`, `CollateralRegistry`, and the `JPYDF` token itself.

If the owner sets `recipient` to any address in this blocked set, `route` will call `jpydfToken.safeTransfer(recipient, amount)`, which calls `_requireValidRecipient` inside JpydfToken's `transfer` and reverts with `JpydfToken__CannotTransferToProtocolContract`. Since `route` is the only exit path and `InterestRouterForwarder` has no emergency drain, all `JPYDF` accumulated in the forwarder is trapped until the owner re-points `recipient` to a valid address (subject to the 24-hour Timelock delay).

The sibling contract `PILAllocator` correctly calls `_requireValidJpydfRecipient` at `registerInitiative` — this guard is absent from `InterestRouterForwarder`.

```solidity
// InterestRouterForwarder.sol:L59-L65
function setRecipient(address _newRecipient) external onlyOwner {
    if (_newRecipient == address(0)) revert ZeroAddress();
    // MISSING: IJpydfToken(address(jpydfToken)).requireValidRecipient(_newRecipient)
    recipient = _newRecipient;
    emit RecipientUpdated(oldRecipient, _newRecipient);
}

// PILAllocator.sol:L112 — correct guard for comparison
_requireValidJpydfRecipient(_initiative);
```

## Recommendation
Add a recipient validity check before updating state:

```solidity
function setRecipient(address _newRecipient) external onlyOwner {
    if (_newRecipient == address(0)) revert ZeroAddress();
    IJpydfToken(address(jpydfToken)).requireValidRecipient(_newRecipient);
    address oldRecipient = recipient;
    recipient = _newRecipient;
    emit RecipientUpdated(oldRecipient, _newRecipient);
}
```

## Status
New

# Low 06 Deployer And Handover Holder Private Keys Are Directly Loaded From Environment Variables

## Location
DeployLiquity2.s.sol:287

DeployPILAllocatorPhaseA.s.sol:123

PrepareDFGovernanceHandover.s.sol:360, 374

VerifyDFGovernanceHandover.s.sol:320

DeployLiquidationCandidateGetter.s.sol:29

AcceptDFGovernanceHandover.s.sol:158-160

## Description
Multiple deployment and governance-handover scripts load private keys directly from environment variables:

```solidity
// DeployLiquity2.s.sol:287, DeployPILAllocatorPhaseA.s.sol:123, DeployLiquidationCandidateGetter.s.sol:29
uint256 privateKey = vm.envUint("DEPLOYER");
vm.startBroadcast(privateKey);

// PrepareDFGovernanceHandover.s.sol:374 / VerifyDFGovernanceHandover.s.sol:320
uint256 privateKey = vm.envUint("DEPLOYER");
vm.startBroadcast(privateKey);

// AcceptDFGovernanceHandover.s.sol:158-160
handoverConfig.timelockPrivateKey = vm.envUint("DF_TIMELOCK_PRIVATE_KEY");
handoverConfig.priceFeedOwnerPrivateKey = vm.envUint("DF_PRICE_FEED_OWNER_PRIVATE_KEY");
handoverConfig.strategyOwnerPrivateKey = vm.envUint("DF_STRATEGY_OWNER_PRIVATE_KEY");
```

This is a security anti-pattern because environment variables can be exposed through multiple vectors:

- **Process inspection**: `/proc/[pid]/environ` and `ps aux e` reveal environment variables to other users / processes on the same host

- **Child-process inheritance**: the key is inherited by every child process and any tool that dumps the environment

- **CI/CD logs**: build logs, GitHub Actions logs, or similar pipeline outputs often capture environment variables, especially when debugging is enabled

- **Shell history**: commands like `DEPLOYER=0x... forge script ...` are saved to `.bash_history` / `.zsh_history`, which may be world-readable or backed up

- **Log aggregation / APM**: container logs, system logs, and monitoring agents may capture environment data

- **Container image / orchestrator inspection**: Docker images and Kubernetes pod descriptions can expose env values

The `AcceptDFGovernanceHandover` case is the most sensitive: it loads the private keys of the **post-handover governance holders** (`DF_TIMELOCK_PRIVATE_KEY`, `DF_PRICE_FEED_OWNER_PRIVATE_KEY`, `DF_STRATEGY_OWNER_PRIVATE_KEY`). Those addresses hold the highest privilege in the system after handover, so an env leak exposes exactly the keys that activate and control the Timelock / PriceFeed / Strategy ownership transfer.

These scripts are launch reference material outside the Solidity audit scope (Contract-Audit-Scope-And-nSLOC.md §8), but they are the actual mechanism for deployment ceremony and governance handover execution, so the key-handling risk is operational rather than contractual. An attacker gaining access to any exposure vector obtains a private key that can deploy contracts, drain assets, or take over governance handover steps.

## Proof of Concept
**Scenario 1: CI/CD Pipeline Exposure**

1. CI/CD runs `DEPLOYER=0x... forge script DeployLiquity2 --broadcast`

2. Build log is archived or briefly visible with verbose/debug output

3. Attacker extracts the key from logs and signs arbitrary transactions with the deployer identity

**Scenario 2: Shell History**

1. Operator runs the handover manually: `DF_TIMELOCK_PRIVATE_KEY=0x... forge script AcceptDFGovernanceHandover --broadcast`

2. Shell saves the command to `.zsh_history`

3. Attacker with shell access (shared machine, compromised account) reads the history and extracts the key

**Scenario 3: Process Inspection**

1. `AcceptDFGovernanceHandover` is executing on a remote/CI host

2. Attacker inspects `/proc/[pid]/environ` of the forge process

3. `DF_TIMELOCK_PRIVATE_KEY` / `DF_STRATEGY_OWNER_PRIVATE_KEY` are visible

## Recommendation
Use a secure signing mechanism and never place a live private key in the environment:

- **Local / fork evidence**: the existing 20-byte-address branch is correct — pass `DEPLOYER` (and the holder addresses) as public addresses and use Anvil impersonation for fork runs. The repo's own runbooks already mandate this for fork stress (Mainnet-Fork-Stress-Gate: `DEPLOYER` is a public address, not a private key).

- **Mainnet broadcasts**: use Foundry's keystore (`cast wallet import`, then `--account`), a hardware signer (`--ledger`, `--trezor`), or a KMS-backed signer. Mainnet-Timelock-Deploy-Runbook requires hardware / KMS / managed signing and no plaintext private key.

- **Governance handover**: execute the accept/prepare steps from each holder's Safe / control plane rather than with holder private keys in env vars (Mainnet-Initial-Configuration-Checklist: production accept is executed from each holder control plane, not by helper scripts with private keys).

- If the env-var path must stay for dev repeatability, gate it to test chains (revert on `block.chainid == 1`) and rotate burner keys frequently.

## Status
New

# Low 07 `SCALE_SPAN = 2` Permanently Loses Depositor Gains After 3+ Scale Changes

## Location
DFStabilityPool.sol

## Description
The Stability Pool's scale mechanism tracks the collateral-to-debt ratio `P` as it decreases through successive liquidations. When `P * remainingDeposits / totalDeposits < 1e27`, the current scale increments, P resets to 1e36, and cumulative gain sums continue under the new scale.

Depositor gain calculations iterate only `SCALE_SPAN = 2` scales ahead of the deposit's snapshot scale:

```solidity
for (uint256 i = 1; i <= SCALE_SPAN; ++i) {
    normalizedGains += scaleToS[snapshots.scale + i] / SCALE_FACTOR ** i;
}
```

If `currentScale - snapshots.scale > 2`, gains from scales `snapshotScale + 3` through `currentScale` are permanently lost. The maximum possible scale distance is `MAX_SCALE_FACTOR_EXPONENT = 8`, so the span covers at most 25% of the possible range.

Scale changes occur when `newP = P * remaining / total < 1e27`. With `P = 1e36` (post-scale-change) and `MIN_JPYDF_IN_SP = 1e18`, the first scale change requires total deposits exceeding `1e27` (~1 billion JPYDF). Subsequent scale changes become progressively easier as P degrades through offsets. Triggering 3+ scale changes against a single deposit requires the depositor to not call `provideToSP`/`withdrawFromSP` while repeated near-total-drain liquidations occur.

The impact is loss of yield and collateral gains for SP depositors who do not periodically refresh their position during extreme liquidation events. Trigger conditions require SP deposits exceeding ~1 billion JPYDF with repeated near-total-drain liquidations, making this unlikely on mainnet but somewhat destructive if triggered.

**Why this issue needs attention:** This issue's mechanism — `SCALE_SPAN = 2` truncating gains after 3+ scale changes — is inherited unchanged from the forked core. `DFStabilityPool.sol` is a full copy of the base `StabilityPool.sol` from **liquity/bold v1.11.0**, with only the same-block withdrawal guard added (CORE-MOD-004, Liquity-v2-Core-Spec.md §2.2 / §8-2). The latent defect therefore exists upstream.

However, the trigger threshold is denominated in **JPY, not USD**, which materially raises the likelihood here relative to BOLD/Liquity:

- The first scale change requires total SP deposits exceeding `1e27` (~1 billion JPYdf).

- At the current rate (~157 JPY/USD), 1 billion JPY ≈ **~6.4 million USD** — roughly **150x smaller** in dollar terms than the same threshold in a USD-pegged stablecoin.

- Reaching ~$6.4M in Stability Pool deposits is far more probable for a JPY-denominated stablecoin than reaching ~$1B in BOLD SP deposits would be for Liquity.

So the same code that is unlikely to trigger in upstream's USD-denominated setting has a meaningfully higher chance of manifesting (permanent loss of depositor yield/collateral gains after 3+ scale changes) in JPYdf.

## Proof of Concept
Paste the following into `test/PoC_SCALE_SPAN.t.sol` and run with:

```bash
forge test --match-contract PoC_SCALE_SPAN -vv
```

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

// Faithful mock of the real DFStabilityPool scale/gain logic (source-snapshot
// contracts/src/DFStabilityPool.sol:396-420, 463-478):
//   - scaleToS[currentScale] += P * collToAdd / totalDeposits       (offset, :396)
//   - while (newP < P_PRECISION / SCALE_FACTOR) { newP *= SCALE_FACTOR; currentScale++; }  (:416-420)
//   - gains loop iterates only SCALE_SPAN scales ahead of the snapshot (:473-475)
contract MockStabilityPool {
    uint256 public constant P_PRECISION = 1e36;
    uint256 public constant SCALE_FACTOR = 1e9;
    uint256 public constant SCALE_SPAN = 2;
    uint256 public constant MAX_SCALE_FACTOR_EXPONENT = 8;
    uint256 public constant MIN_JPYDF_IN_SP = 1e18;

    uint256 public P = P_PRECISION;
    uint256 public currentScale;
    mapping(uint256 => uint256) public scaleToS;
    uint256 public totalDeposits;

    struct Snapshots {
        uint256 scale;
        uint256 P;
        uint256 S;
        uint256 initialValue;
    }
    mapping(address => Snapshots) public snapshots;

    function deposit(address user, uint256 amount) external {
        snapshots[user].initialValue += amount;
        totalDeposits += amount;
        snapshots[user].scale = currentScale;
        snapshots[user].P = P;
        snapshots[user].S = scaleToS[currentScale];
    }

    function liquidate(uint256 debtToOffset, uint256 collToAdd) external returns (uint256 scalesChanged) {
        require(totalDeposits >= MIN_JPYDF_IN_SP, "SP too small");
        scaleToS[currentScale] += P * collToAdd / totalDeposits;
        uint256 remaining = totalDeposits - debtToOffset;
        require(remaining >= MIN_JPYDF_IN_SP, "Would empty SP");
        uint256 newP = P * remaining / totalDeposits;
        while (newP < P_PRECISION / SCALE_FACTOR) {
            newP *= SCALE_FACTOR;
            currentScale += 1;
            scalesChanged++;
        }
        P = newP;
        totalDeposits = remaining;
    }

    function restock(uint256 amount) external { totalDeposits += amount; }

    function getCollGain_SCALESPAN2(address user) external view returns (uint256) {
        uint256 initial = snapshots[user].initialValue;
        if (initial == 0) return 0;
        Snapshots memory s = snapshots[user];
        uint256 g = scaleToS[s.scale] - s.S;
        for (uint256 i = 1; i <= SCALE_SPAN; ++i) {
            g += scaleToS[s.scale + i] / SCALE_FACTOR ** i;
        }
        return initial * g / s.P;
    }

    function getCollGain_SCALESPAN8(address user) external view returns (uint256) {
        uint256 initial = snapshots[user].initialValue;
        if (initial == 0) return 0;
        Snapshots memory s = snapshots[user];
        uint256 g = scaleToS[s.scale] - s.S;
        for (uint256 i = 1; i <= MAX_SCALE_FACTOR_EXPONENT; ++i) {
            if (s.scale + i > currentScale) break;
            g += scaleToS[s.scale + i] / SCALE_FACTOR ** i;
        }
        return initial * g / s.P;
    }
}

contract PoC_SCALE_SPAN is Test {
    MockStabilityPool pool;

    function setUp() public {
        pool = new MockStabilityPool();
    }

    /// Scenario 1 — near-total drains with modest depositor.
    /// Result: gain2 == gain8, i.e. no measurable loss
    /// is reproduced at these magnitudes.
    function test_realisticParams_NoMeasurableLoss() public {
        address alice = address(0xABCD);
        pool.restock(2e27);
        pool.deposit(alice, 10_000e18);

        for (uint256 round = 0; round < 4; round++) {
            pool.restock(2e27);
            pool.liquidate(pool.totalDeposits() - pool.MIN_JPYDF_IN_SP(), 100_000e18 * (4 - round));
        }

        uint256 gain2 = pool.getCollGain_SCALESPAN2(alice);
        uint256 gain8 = pool.getCollGain_SCALESPAN8(alice);

        emit log_named_uint("currentScale", pool.currentScale());
        emit log_named_uint("SCALE_SPAN=2 gain", gain2);
        emit log_named_uint("SCALE_SPAN=8 gain", gain8);
        emit log_named_uint("gap (wei)", gain8 - gain2);

        assertEq(gain2, gain8, "at realistic magnitudes the truncated tail is sub-wei");
    }

    /// Scenario 2 — extreme stress (10^14 JPYdf whale deposit, 10^14 JPYdf
    /// collateral per drain) so the truncated tail crosses 1 wei. Proves the
    /// mechanism exists, while showing the gap is astronomically small relative
    /// to total accrued gains (~1e-28).
    function test_extremeStress_GapIsBoundedDust() public {
        address alice = address(0xABCD);
        uint256 whale = 1e32; // 10^14 JPYdf
        pool.restock(2e27);
        pool.deposit(alice, whale);

        for (uint256 round = 0; round < 4; round++) {
            pool.restock(2e27);
            pool.liquidate(pool.totalDeposits() - pool.MIN_JPYDF_IN_SP(), whale);
        }

        uint256 gain2 = pool.getCollGain_SCALESPAN2(alice);
        uint256 gain8 = pool.getCollGain_SCALESPAN8(alice);
        uint256 gap = gain8 - gain2;

        emit log_named_uint("currentScale", pool.currentScale());
        emit log_named_uint("SCALE_SPAN=2 gain", gain2);
        emit log_named_uint("SCALE_SPAN=8 gain", gain8);
        emit log_named_uint("gap (wei)", gap);

        assertGt(gap, 0, "mechanism: truncated tail must be nonzero at extreme scale");
        assertLt(gap, gain2 / 1e20, "gap is < 1e-20 of accrued gains even in the extreme case");
    }
}
```

## Recommendation
Set `SCALE_SPAN` to `MAX_SCALE_FACTOR_EXPONENT` (= 8):

```solidity
uint256 public constant SCALE_SPAN = 8; // was 2
```

This ensures all 8 possible scale-change distances are covered. The iteration is bounded by a compile-time constant and does not introduce unbounded gas costs.

## Status
New

# Informational

# Info 01 Euler Rewards Streams Are Not Compatible With Current `ERC4626Strategy`

## Location

ERC4626Strategy.sol (no reward claim function)

BaseStrategy.sol (`claimMerklRewards`)

## Description
Euler v2 (`EVault`) has a native reward distribution mechanism called **Euler Reward Streams** (`EulerEarnVault` / `RewardStreams`), separate from Merkl. Euler vaults can have rewards streamed directly to depositors via the `IRewardStreams` interface — rewards accrue automatically to vault share holders and are claimable by calling `claimReward(vault, reward, recipient)` on the Euler RewardStreams contract.

`ERC4626Strategy` has no function to claim Euler's native reward streams. The strategy inherits `claimMerklRewards` and `sweepRewardToken` from `BaseStrategy`, but neither covers Euler's reward distribution mechanism:

- `claimMerklRewards` requires a Merkl distributor contract and Merkle proofs. Euler RewardStreams is a completely different interface — it is not Merkl-compatible.

- `sweepRewardToken` can only sweep tokens **already in the strategy contract**. Euler reward streams accrue to the share holder but rewards sit in the `RewardStreams` contract until explicitly claimed. There is nothing in the strategy to call `rewardStreams.claimReward(address(erc4626Vault), rewardToken, address(this))` to pull them into the strategy first.

```solidity
// Euler RewardStreams interface (not implemented in ERC4626Strategy)
interface IRewardStreams {
    function claimReward(
        address rewarded,   // the EVault address
        address reward,     // the reward token
        address recipient,  // where to send rewards
        bool forfeit        // forfeit unclaimed if true
    ) external returns (uint256 claimed);

    function earnedReward(
        address account,    // the strategy address
        address rewarded,   // the EVault address
        address reward,     // the reward token
        bool forfeit
    ) external view returns (uint256 earned);
}
```

The result is that any Euler-distributed reward tokens accumulate indefinitely in the `RewardStreams` contract, inaccessible to the strategy with no function to claim them. They are not visible to `sweepRewardToken()` (nothing arrived in the strategy), not claimable via `claimMerklRewards()` (wrong interface), and not returned by `estimatedTotalUnderlying()` (only tracks principal value).

Note: this is a latent issue that only materialises if `ERC4626Strategy` is pointed at an Euler `EVault` that has reward streams configured. For Morpho `MetaMorpho` vaults (the Day-1 planned target per SCOPE.md), this does not apply as Morpho uses Merkl for its reward distribution, which is already handled. It becomes relevant if Euler vaults are added as targets in future.

## Recommendation
If Euler `EVaults` are used as targets for `ERC4626Strategy`, add an Euler-specific reward claim function to the strategy:

```solidity
interface IEulerRewardStreams {
    function claimReward(
        address rewarded,
        address reward,
        address recipient,
        bool forfeit
    ) external returns (uint256 claimed);
}

function claimEulerRewards(
    IEulerRewardStreams _rewardStreams,
    address _rewardToken,
    bool _forfeit
) external onlyOwner nonReentrantStrategy returns (uint256 settled) {
    if (address(_rewardStreams) == address(0)) revert ZeroAddress();
    if (_rewardToken == address(0)) revert ZeroAddress();
    if (_isSweepProtectedToken(_rewardToken)) revert CannotSweepProtectedToken();

    // Claim rewards from Euler RewardStreams into this strategy
    uint256 claimed = _rewardStreams.claimReward(
        address(erc4626Vault),
        _rewardToken,
        address(this),
        _forfeit
    );

    if (claimed == 0) return 0;

    // Route to vault: underlying rewards as yield, other tokens to treasury
    if (_rewardToken == address(underlyingToken)) {
        settled = _sendUnderlyingYieldToVault(claimed);
    } else {
        settled = _sweepRewardToken(IERC20(_rewardToken), type(uint256).max);
    }
}
```

## Status
New

# Info 02 `DToken::setCap`: No Lower-bound Check Against `totalSupply`

## Location
DToken.sol

## Description
`setCap` accepts any value without checking it against the current `totalSupply()`. If the owner sets `cap < totalSupply()`, then any `mint` call to bring the supply above `cap` will revert. Since new total supply is computed as `totalSupply() + _amount` and checked against `cap`, this would permanently brick minting (though the cap can be raised again via another `setCap` call).

### Practical context
- The `onlyOwner` role is held by the **timelock** (24h delay), proposed and executed by the **Admin multisig** (3-of-5 Safe).

- `renounceOwnership` is explicitly disabled.

- Ownership transfer uses a two-step pattern (`transferOwnership` -> `acceptOwnership`), preventing single-step mistakes.

- Default cap is `type(uint256).max` (unlimited), so any finite cap set after deployment is an intentional narrowing.

- The cap is only checked on `mint`, which is `onlyVault` — the vault mints dTokens when users deposit underlying. Setting a cap too low would prevent new deposits but not affect existing holders.

Setting a cap below current total supply would require:

1. A proposal through the timelock (24h delay)

2. Approval by 3-of-5 Admin multisig signers

3. Execution after the delay elapses

If the Timelock-governed owner sets `cap < totalSupply()`, new dToken minting (deposits) is blocked until the cap is raised via another governance action. Existing holders are unaffected. The scenario requires coordinated governance action through a 24h timelock and 3-of-5 multisig.

## Recommendation
Add a check in `setCap` to ensure the new cap is not below the current total supply:

```solidity
function setCap(uint256 _newCap) external override onlyOwner {
    if (_newCap < totalSupply()) revert CapBelowTotalSupply(_newCap, totalSupply());
    uint256 oldCap = cap;
    cap = _newCap;
    emit CapUpdated(oldCap, _newCap);
}
```

This prevents accidental misconfiguration without restricting legitimate governance actions.

## Status
New

# Info 03 `setAllocatorConfig` Accepts Unvalidated `cooldown` And `maxMove` Values

## Location
CollateralVault.sol

## Description
`setAllocatorConfig` stores `_maxMove` and `_cooldown` without any validation. Setting `_cooldown` to a very high number makes `block.timestamp < lastAllocatorTime + _cooldown` almost always true, bricking `allocate` until governance corrects it. Setting `_maxMove` to zero makes allocation a silent no-op (excess is capped to zero).

If governance sets a cooldown that is too high, strategy allocation is frozen until `GOV_ROLE` calls `setAllocatorConfig` again with a valid value. A zero `maxMove` causes silent allocation no-ops that may go undetected until strategy balances are inspected.

## Recommendation
Add bounds for both parameters:

```solidity
function setAllocatorConfig(uint256 _maxMove, uint256 _cooldown) external override onlyRole(GOV_ROLE) {
    if (_cooldown > 30 days) revert InvalidAllocatorCooldown();
    if (_maxMove == 0) revert InvalidAllocatorMaxMove();
    uint256 oldMaxMove = allocateMaxMove;
    uint256 oldCooldown = allocatorCooldown;
    allocateMaxMove = _maxMove;
    allocatorCooldown = _cooldown;
    emit AllocatorConfigUpdated(oldMaxMove, _maxMove, oldCooldown, _cooldown);
}
```

## Status
New

# Info 04 `setStrategyValuationMaxAge` Accepts Unvalidated `maxAge` Value

## Location
CollateralVault.sol

## Description
`setStrategyValuationMaxAge` accepts any `uint256` without bounds. Setting to zero makes the cache at line 1072 (`if (maxAge == 0 || ...)`) always return `(0, false, true)` — stale — forcing live reads on every solvency call. If the live valuation is unavailable (strategy view reverts, price feed down), solvency checks may fail and block redemptions or liquidations. Setting it extremely high lets stale valuations persist indefinitely, potentially masking actual insolvency. The default is 1 day.

A governance misconfiguration setting maxAge to 0 removes the cache fallback, making solvency checks dependent on live reads that may fail during temporary outages. Setting it to `type(uint256).max` prevents the system from detecting stale valuations, which could conceal insolvency until it is too late to liquidate.

## Recommendation
Add reasonable bounds:

```solidity
function setStrategyValuationMaxAge(uint256 _maxAge) external override onlyRole(GOV_ROLE) {
    if (_maxAge < 1 hours || _maxAge > 7 days) revert InvalidMaxAge();
    uint256 oldMaxAge = strategyValuationMaxAge;
    strategyValuationMaxAge = _maxAge;
    emit StrategyValuationMaxAgeUpdated(oldMaxAge, _maxAge);
}
```

## Status
New

# Info 05 `setBufferConfig` Does Not Check Consistency Between `bufferFloor` And `bufferTargetBps`

## Location
CollateralVault.sol

## Description
`setBufferConfig` validates only that `_targetBps <= 10000`. There is no check that `_floor` is consistent with `_targetBps`. The required buffer is `max(managedAssets * targetBps / 10000, floor) + pendingWithdrawals`. A floor set disproportionately high relative to the target percentage causes the floor to dominate the buffer computation, making `targetBps` irrelevant and locking idle capital away from strategy allocation. Setting `_floor = type(uint256).max` makes `allocate()` a perpetual no-op because the buffer can never exceed the required floor.

A floor set disproportionately high causes the vault to hold more idle capital than intended, reducing capital efficiency. In extreme cases (e.g., `_floor = type(uint256).max`), strategy allocation is permanently blocked until governance corrects the config.

## Recommendation
Add a consistency check:

```solidity
function setBufferConfig(uint256 _targetBps, uint256 _floor) external override onlyRole(GOV_ROLE) {
    if (_targetBps > BPS_DENOMINATOR) revert InvalidBufferConfig();
    if (_floor > 0 && _targetBps == 0) revert InvalidBufferConfig();
    if (_floor > 1_000_000e18) revert InvalidBufferConfig();
    uint256 oldTargetBps = bufferTargetBps;
    uint256 oldFloor = bufferFloor;
    bufferTargetBps = _targetBps;
    bufferFloor = _floor;
    emit BufferConfigUpdated(oldTargetBps, _targetBps, oldFloor, _floor);
}
```

## Status
New

# Info 06 `setAddresses` Does Not Validate 18 Core Contract Addresses

## Location
AddressesRegistry.sol

## Description
`setAddresses` accepts 18 core contract addresses via an `AddressVars` struct and stores them all with no validation — no zero-address checks, no code-existence checks, no uniqueness checks. After storing, `_renounceOwnership()` is called, making the contract immutable. A calldata construction error (copy-paste mistake, typo) during deployment registration produces a permanent misconfiguration with no recovery path. The function is called once per branch during the deployment ceremony. Compare with the constructor which validates every immutable parameter with explicit range checks, and with `PILAllocator.setWeights` which uses `_requireNoDuplicates` for the same class of issue.

A mistake in any of the 18 addresses is permanent and unfixable. Affected contract references would point to the wrong address or zero, causing downstream calls to either interact with the wrong contract or revert. The risk is partially mitigated by the deployment ceremony (calldata review, testnet dry-run, event verification), but the contract itself provides no defense-in-depth against a simple copy-paste error.

## Recommendation
Add per-address validation:

```solidity
function setAddresses(AddressVars memory _vars) external onlyOwner {
    _requireNonZeroAndContract(address(_vars.collToken));
    _requireNonZeroAndContract(address(_vars.borrowerOperations));
    _requireNonZeroAndContract(address(_vars.troveManager));
    _requireNonZeroAndContract(address(_vars.troveNFT));
    _requireNonZeroAndContract(address(_vars.metadataNFT));
    _requireNonZeroAndContract(address(_vars.stabilityPool));
    _requireNonZeroAndContract(address(_vars.priceFeed));
    _requireNonZeroAndContract(address(_vars.activePool));
    _requireNonZeroAndContract(address(_vars.defaultPool));
    if (_vars.gasPoolAddress == address(0)) revert ZeroAddress();
    _requireNonZeroAndContract(address(_vars.collSurplusPool));
    _requireNonZeroAndContract(address(_vars.sortedTroves));
    _requireNonZeroAndContract(address(_vars.interestRouter));
    _requireNonZeroAndContract(address(_vars.hintHelpers));
    _requireNonZeroAndContract(address(_vars.multiTroveGetter));
    _requireNonZeroAndContract(address(_vars.collateralRegistry));
    _requireNonZeroAndContract(address(_vars.jpydfToken));
    _requireNonZeroAndContract(address(_vars.WETH));
    // ... store, emit, renounce ...
}

function _requireNonZeroAndContract(address _addr) internal view {
    if (_addr == address(0)) revert ZeroAddress();
    if (_addr.code.length == 0) revert NotContract();
}
```

## Status
New

# Info 07 Strategy Contracts Store External Protocol Addresses Without Update Functions

## Location
ERC4626Strategy.sol

LidoStrategy.sol

EtherfiWeETHStrategy.sol

SkyUsdcSUsdsStrategy.sol

## Description
All strategy contracts store external protocol addresses as regular storage variables at initialization time with no setter function to update them.

- **ERC4626Strategy** — locked: `erc4626Vault`

- **LidoStrategy** — locked: `lido`, `stETH`, `wstETH`, `withdrawalQueue`, `weth`

- **EtherfiWeETHStrategy** — locked: `liquidityPool`, `eETH`, `weETH`, `withdrawAdapter`, `withdrawRequestNFT`, `weth`

- **SkyUsdcSUsdsStrategy** — locked: `usdsToken`, `susdsVault`, `converter`

None of the strategies read protocol addresses from `AddressesRegistry`. All external protocol addresses are hardcoded at initialization time. If an upstream protocol contract is upgraded, deprecated, or exploited (e.g., Lido withdrawal queue redeployment, Sky converter replacement), the strategy cannot point to the new contract without a full implementation upgrade via governance.

All strategies are UUPS upgradeable, so the system is not stuck — a governance proposal can deploy a new implementation with a migration setter. However, this requires a code change per incident, not a simple governance admin call.

## Recommendation
For each set-once address, add a governance-only setter with zero-address and code-existence validation. Alternatively, store external protocol addresses in `AddressesRegistry` and have strategies read from there, providing a single update point for governance.

## Status
New

# Info 08 `lastDepositBlock` Comment Overstates Guard Guarantee: No Guaranteed Capital Exposure Across Block Boundary

## Location
DFStabilityPool.sol

## Description
The same-block withdrawal guard requires withdrawal in a strictly later block:

```solidity
// DFStabilityPool.sol:616
require(lastDepositBlock[msg.sender] < block.number, "StabilityPool: Withdrawal must wait after deposit");
```

The code comment describes the guard as follows:

> "Prevent same-block flash deposits from capturing liquidation gains and immediately withdrawing in the same atomic bundle. This does not remove all timing/MEV risk, but forces **at least one block of capital exposure** before a fresh SP deposit can exit with liquidation proceeds."

The multi-block MEV itself is explicitly accepted as residual risk by the spec (CORE-SP-SEC-004: "Withdrawals are unrestricted from the next block onward, so multi-block MEV (cases with highly accurate liquidation prediction) remains in a threshold sense"). This issue is therefore not about that residual risk. It is about a mismatch between the comment's stated guarantee and what the guard actually enforces:

- The guard enforces that the deposit **persists across a block boundary** (`lastDepositBlock < block.number`), not that it bears any liquidation **exposure**.

- With transaction-ordering control (priority fee on tip-sorted blocks, or private relay / builder bundle), a deposit placed as the last transaction of block N and withdrawn as the first transaction of block N+1 passes the check while being touched by zero intervening SP offsets. The deposit "exposure" is reduced to zero, so the comment's "at least one block of capital exposure" claim is stronger than the code delivers.

- The spec's acceptance of the residual risk is premised on a *threshold* of exposure; block-boundary ordering can nullify even that threshold.

## Recommendation
Align the code comment with the actual guarantee. Either:

1. Reword the comment to state the guard enforces *persistence across at least one block boundary* and *blocks same-block / same-tx capture*, without claiming "capital exposure" (matching CORE-SP-SEC-004's residual-risk framing), or

2. If the stronger "at least one full block of exposure" guarantee is desired, require a full intervening block so the deposit must survive every SP offset in an entire block:

```solidity
// DFStabilityPool.sol:616
require(lastDepositBlock[msg.sender] + 1 < block.number, "StabilityPool: Withdrawal must wait after deposit");
```

If option 2 is adopted, update CORE-SP-FR-004 / CORE-SP-SEC-004 and the same-block guard unit tests accordingly.

## Status
New

# Gas

# Gas 01 Gas Exhaustion In Strategy Valuation Loop Can Revert All Redemptions

## Location
DFPriceFeedBase.sol (`_applyBackingRatio`)

CollateralVault.sol (`backingRatio`)

## Description
`backingRatio` iterates over all registered strategies (up to 32) calling `estimatedTotalUnderlying` on each, which in turn makes external calls to Aave, Lido, ERC4626 vaults, etc. This call chain is invoked inside `CollateralRegistry::redeemCollateral` for every branch with no try/catch on the gas budget.

As strategy count grows, the gas cost of `backingRatio` increases proportionally. If the cumulative cost exhausts the transaction gas limit, the entire redemption reverts. This affects all JPYDF redemptions across all branches simultaneously.

Currently at launch scale (3-5 strategies) the impact is ~75,000 extra gas — not a practical threat. The risk grows with each new strategy registration.

## Recommendation
Cap the strategy iteration in `backingRatio` or cache the result within a block. Document a maximum strategy count per vault that keeps `backingRatio` within safe gas bounds.

## Status
New

# Gas 02 `getNewApproxAvgInterestRateFromTroveChange` Runs The `upfrontFee` Assert Even When The Branch Is Shut Down

## Location
ActivePool.sol

## Description
`getNewApproxAvgInterestRateFromTroveChange` executes the `upfrontFee` assertion before the shutdown short-circuit:

```solidity
assert(_troveChange.upfrontFee == 0);

if (shutdownTime != 0) return 0;
```

Once a branch is shut down the function returns `0` unconditionally (CORE-AP-FR-005 step 1; pinned by `testApproxAvgInterestRateIs0AfterShutdown` in `test/shutdown.t.sol`). On that path the `assert` is pure dead work — it performs a calldata read + comparison that can never affect the result.

Hoisting the shutdown check above the `assert` skips it on the shutdown path:

```solidity
if (shutdownTime != 0) return 0;

assert(_troveChange.upfrontFee == 0);
```

The reorder is behavior-preserving for every legitimate caller:

- The `assert` is a calling-convention check, not a security boundary — all producers (`BorrowerOperations`, `HintHelpers`) pass `_troveChange.upfrontFee == 0` by construction (the average-rate calculation intentionally ignores the upfront fee to break the fee <-> rate circularity, CORE-AP-FR-005 / Liquity-v2-Core-Spec.md §CORE-AP-FR-005).

- In the shut-down state the return value is `0` regardless of the assert.

- The only observable difference is a caller passing `upfrontFee != 0` to an already-shut-down branch would receive `0` instead of Panic 0x01 — no code path consumes that revert, and the function is a `view`.

Gas impact is small and limited to the shutdown path, hence Gas severity.

## Proof of Concept
Isolated measurement of the two orderings on the shutdown path (mock reproduction of the function body, solc 0.8.24):

```
currentOrder gas (shutdown): 2724
proposedOrder gas (shutdown): 2575
delta: 149
```

~149 gas saved per call on the shutdown path; identical gas on the live (non-shutdown) path.

## Recommendation
Hoist the shutdown short-circuit above the assert:

```solidity
if (shutdownTime != 0) return 0;

// We are ignoring the upfront fee when calculating the approx. avg. interest rate.
// This is a simple way to resolve the circularity in:
//   fee depends on avg. interest rate -> avg. interest rate is weighted by debt -> debt includes fee -> ...
assert(_troveChange.upfrontFee == 0);
```

## Status
New
