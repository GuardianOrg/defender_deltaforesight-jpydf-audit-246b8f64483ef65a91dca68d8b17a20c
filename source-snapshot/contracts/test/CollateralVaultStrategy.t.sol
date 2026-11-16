// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "./TestContracts/MockStrategy.sol";
import "../src/Interfaces/ICollateralVault.sol";
import "../src/Interfaces/IStrategy.sol";
import "./PushModelMocks.sol";
import "./mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ConfigurableValuationStrategy is IStrategy {
    address private immutable underlyingToken;
    bool public revertEstimated;
    bool public revertPrincipal;
    uint256 public estimatedValue;
    uint256 public principalValue;
    uint256 public forcePenaltyShares;
    uint256 public forcePenaltyAssets;
    uint256 public forceValuationLossAssets;
    uint256 public forceReceipt = 10e8;

    constructor(address _underlying) {
        underlyingToken = _underlying;
    }

    function underlying() external view override returns (address) {
        return underlyingToken;
    }

    function setEstimatedValue(uint256 _estimatedValue) external {
        estimatedValue = _estimatedValue;
    }

    function setPrincipalValue(uint256 _principalValue) external {
        principalValue = _principalValue;
    }

    function setRevertEstimated(bool _revertEstimated) external {
        revertEstimated = _revertEstimated;
    }

    function setRevertPrincipal(bool _revertPrincipal) external {
        revertPrincipal = _revertPrincipal;
    }

    function setForceDeallocateResult(uint256 _penaltyShares, uint256 _penaltyAssets, uint256 _valuationLossAssets)
        external
    {
        forcePenaltyShares = _penaltyShares;
        forcePenaltyAssets = _penaltyAssets;
        forceValuationLossAssets = _valuationLossAssets;
    }

    function forceDeallocate(address, bytes calldata, uint256)
        external
        returns (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets, uint256 withdrawnAssets)
    {
        IERC20(underlyingToken).transfer(msg.sender, forceReceipt);
        revertEstimated = true;
        revertPrincipal = true;
        return (forcePenaltyShares, forcePenaltyAssets, forceValuationLossAssets, 10e8);
    }

    function setForceReceipt(uint256 amount) external {
        forceReceipt = amount;
    }

    function deposit(uint256, uint256 _receivedAmount) external pure override returns (uint256 deposited) {
        return _receivedAmount;
    }

    function principal() external view override returns (uint256) {
        if (revertPrincipal) revert("principal failed");
        return principalValue;
    }

    function realizedYield() external pure override returns (uint256) {
        return 0;
    }

    function estimatedTotalUnderlying() external view override returns (uint256) {
        if (revertEstimated) revert("estimate failed");
        return estimatedValue;
    }

    function sendToVault(uint256) external pure override returns (uint256 sent) {
        return 0;
    }

    function sendProfitToVault() external pure override returns (uint256 sent) {
        return 0;
    }

    function writeoffPrincipal(uint256) external pure override returns (uint256 writtenOff) {
        return 0;
    }

    function sweepRewardToken(IERC20, uint256) external pure override returns (uint256 swept) {
        return 0;
    }
}

contract RevertingAfterDepositStrategy is IStrategy {
    address private immutable underlyingToken;
    bool public revertValuation;
    bool public revertAfterDeposit;
    uint256 public estimatedValue;
    uint256 public principalValue;

    constructor(address _underlying) {
        underlyingToken = _underlying;
    }

    function underlying() external view override returns (address) {
        return underlyingToken;
    }

    function setRevertAfterDeposit(bool _revertAfterDeposit) external {
        revertAfterDeposit = _revertAfterDeposit;
    }

    function setValues(uint256 _estimatedValue, uint256 _principalValue) external {
        estimatedValue = _estimatedValue;
        principalValue = _principalValue;
    }

    function deposit(uint256, uint256 _receivedAmount) external override returns (uint256 deposited) {
        estimatedValue += _receivedAmount;
        principalValue += _receivedAmount;
        if (revertAfterDeposit) {
            revertValuation = true;
        }
        return _receivedAmount;
    }

    function principal() external view override returns (uint256) {
        if (revertValuation) revert("principal failed");
        return principalValue;
    }

    function realizedYield() external view override returns (uint256) {
        if (revertValuation) revert("yield failed");
        return estimatedValue > principalValue ? estimatedValue - principalValue : 0;
    }

    function estimatedTotalUnderlying() external view override returns (uint256) {
        if (revertValuation) revert("estimate failed");
        return estimatedValue;
    }

    function sendToVault(uint256) external pure override returns (uint256 sent) {
        return 0;
    }

    function sendProfitToVault() external pure override returns (uint256 sent) {
        return 0;
    }

    function writeoffPrincipal(uint256) external pure override returns (uint256 writtenOff) {
        return 0;
    }

    function sweepRewardToken(IERC20, uint256) external pure override returns (uint256 swept) {
        return 0;
    }
}

contract ReentrantWriteoffStrategy is IStrategy {
    address private immutable underlyingToken;
    ICollateralVault private immutable vault;
    uint256 private principalValue;
    bool public reenterOnWriteoff;

    constructor(address _underlying, ICollateralVault _vault, uint256 _principal) {
        underlyingToken = _underlying;
        vault = _vault;
        principalValue = _principal;
    }

    function setReenterOnWriteoff(bool _reenterOnWriteoff) external {
        reenterOnWriteoff = _reenterOnWriteoff;
    }

    function underlying() external view override returns (address) {
        return underlyingToken;
    }

    function deposit(uint256, uint256 _receivedAmount) external override returns (uint256 deposited) {
        principalValue += _receivedAmount;
        return _receivedAmount;
    }

    function principal() external view override returns (uint256) {
        return principalValue;
    }

    function realizedYield() external pure override returns (uint256) {
        return 0;
    }

    function estimatedTotalUnderlying() external view override returns (uint256) {
        return principalValue;
    }

    function sendToVault(uint256) external pure override returns (uint256 sent) {
        return 0;
    }

    function sendProfitToVault() external pure override returns (uint256 sent) {
        return 0;
    }

    function writeoffPrincipal(uint256 _amount) external override returns (uint256 writtenOff) {
        if (reenterOnWriteoff) {
            vault.receiveFromStrategy(0);
        }

        writtenOff = _amount > principalValue ? principalValue : _amount;
        principalValue -= writtenOff;
    }

    function sweepRewardToken(IERC20, uint256) external pure override returns (uint256 swept) {
        return 0;
    }
}

contract ReadOnlyReentrantAllocateStrategy is IStrategy {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    address private immutable underlyingToken;
    ICollateralVault private immutable vault;
    uint256 private principalValue;
    uint256 private estimatedValue;

    bool public attemptMutatingReentry;
    bool public mutatingReentrySucceeded;
    bool public mutatingReentryReverted;
    uint256 public observedTotalUnderlying;
    uint256 public observedBackingRatio;
    uint256 public observedStrategyCount;

    constructor(address _underlying, ICollateralVault _vault) {
        underlyingToken = _underlying;
        vault = _vault;
    }

    function setAttemptMutatingReentry(bool _attemptMutatingReentry) external {
        attemptMutatingReentry = _attemptMutatingReentry;
    }

    function underlying() external view override returns (address) {
        return underlyingToken;
    }

    function deposit(uint256, uint256 _receivedAmount) external override returns (uint256 deposited) {
        observedTotalUnderlying = vault.totalUnderlying();
        observedBackingRatio = vault.backingRatio();
        observedStrategyCount = _lens().getStrategyStatuses(ICollateralVault(address(vault))).length;

        if (attemptMutatingReentry) {
            try vault.receiveFromStrategy(0) returns (uint256) {
                mutatingReentrySucceeded = true;
            } catch {
                mutatingReentryReverted = true;
            }
        }

        principalValue += _receivedAmount;
        estimatedValue += _receivedAmount;
        return _receivedAmount;
    }

    function principal() external view override returns (uint256) {
        return principalValue;
    }

    function realizedYield() external view override returns (uint256) {
        return estimatedValue > principalValue ? estimatedValue - principalValue : 0;
    }

    function estimatedTotalUnderlying() external view override returns (uint256) {
        return estimatedValue;
    }

    function sendToVault(uint256) external pure override returns (uint256 sent) {
        return 0;
    }

    function sendProfitToVault() external pure override returns (uint256 sent) {
        return 0;
    }

    function writeoffPrincipal(uint256) external pure override returns (uint256 writtenOff) {
        return 0;
    }

    function sweepRewardToken(IERC20, uint256) external pure override returns (uint256 swept) {
        return 0;
    }
}

contract StrategyReentrancyGuardHarness is MockStrategy {
    function enterTwice() external nonReentrantStrategy {
        this.guardedNoop();
    }

    function guardedNoop() external nonReentrantStrategy {}
}

contract MockMerklDistributor {
    using SafeERC20 for IERC20;

    address public lastCaller;
    address public lastUser;
    address public lastToken;
    uint256 public lastAmount;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        require(
            users.length == tokens.length && users.length == amounts.length && users.length == proofs.length,
            "BAD_LENGTH"
        );

        lastCaller = msg.sender;
        for (uint256 i = 0; i < users.length; i++) {
            lastUser = users[i];
            lastToken = tokens[i];
            lastAmount = amounts[i];
            IERC20(tokens[i]).safeTransfer(users[i], amounts[i]);
        }
    }
}

/// @title CollateralVaultStrategyTest - Phase 3b BUCKET B (push-model Strategy layer) coverage.
/// @notice Ports the non-Aave push-model unit tests from jpydf #61
///         (`feat/push-model-migration` head `9acb750`) onto jpydf-v2: allocate,
///         receiveFromStrategy, sendToVault / sendProfitToVault, transferYield-
///         ToTreasury, strategy whitelist + CRUD, writeoff, allocation pause,
///         roles, BaseStrategy edge cases, and fee-on-transfer principal
///         accounting — driven by real `MockStrategy` instances (not `deal`
///         simulation). The dToken-portion (BUCKET A) tests live in
///         `CollateralVault.t.sol`; the Aave-V3 tests live in `AaveV3Strategy.t.sol`.
///
///         Adds three jpydf-v2-specific tests for the deferred-underlying
///         `addStrategy` guard (mismatch / placeholder) that #61 does not have,
///         plus a failing-withdraw propagation test.
contract CollateralVaultStrategyTest is Test {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant WRITEOFF_ROLE = keccak256("WRITEOFF_ROLE");
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    // --- Re-declared events from ICollateralVault for vm.expectEmit ---
    event WithdrawRequested(
        address indexed user, address indexed receiver, uint256 requestId, uint256 amount, uint256 claimableAt
    );
    event WithdrawClaimed(address indexed user, uint256 requestId, uint256 amount);
    event StrategyWhitelisted(address indexed strategy);
    event StrategyRemovedFromWhitelist(address indexed strategy);
    event StrategyAdded(address indexed strategy, uint256 weightBps, uint256 cap);
    event StrategyUpdated(address indexed strategy, uint256 weightBps, uint256 cap, bool enabled);
    event StrategyEmergencyDisabled(address indexed strategy, uint256 oldWeightBps);
    event StrategyRemoved(address indexed strategy);
    event StrategyPrincipalWrittenOff(address indexed strategy, uint256 amount);
    event Allocated(uint256 bufferBefore, uint256 targetBuffer, uint256 bufferAfter);
    event StrategyAllocated(address indexed strategy, uint256 amount);
    event StrategyAllocationSkipped(address indexed strategy);
    event ReceivedFromStrategy(address indexed strategy, uint256 declaredAmount, uint256 received);
    event StrategyValuationCacheReduced(address indexed strategy, uint256 oldValue, uint256 newValue, uint256 amount);
    event StrategyValuationCacheInvalidated(address indexed strategy, uint256 oldValue, uint256 updatedAt);
    event YieldTransferredToTreasury(uint256 amount, address indexed treasury);
    event DepositPaused();
    event RedeemPaused();
    event ClaimPaused();
    event AllocationPaused();
    event AllocatorConfigUpdated(uint256 oldMaxMove, uint256 newMaxMove, uint256 oldCooldown, uint256 newCooldown);
    event StrategyValuationMaxAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event WithdrawDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event RewardTokenSwept(address indexed token, address indexed treasury, uint256 requested, uint256 received);
    event MerklRewardsClaimed(
        address indexed distributor, address indexed token, uint256 cumulativeAmount, uint256 swept
    );
    event MerklUnderlyingRewardsClaimed(
        address indexed distributor, address indexed token, uint256 cumulativeAmount, uint256 sentToVault
    );
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event UpgraderUpdated(address indexed oldUpgrader, address indexed newUpgrader);

    DToken public dToken;
    CollateralVault public vault;
    MockERC20 public underlying;
    MockStrategy public stratA;
    MockStrategy public stratB;

    address public admin;
    address public treasury;
    address public alice;
    address public bob;

    // --- Setup ---

    /// @dev DToken + CollateralVault proxies + 2 MockStrategy proxies, with both
    ///      strategies whitelisted and registered at 5000 bps each.
    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        underlying = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        DToken dTokenImpl = new DToken();
        CollateralVault vaultImpl = new CollateralVault();

        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        dToken = DToken(address(new ERC1967Proxy(address(dTokenImpl), dInit)));
        dToken.setAllowedUnderlying(address(underlying), true);

        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(underlying)), IDToken(address(dToken)), treasury, admin
        );
        vault = CollateralVault(address(new ERC1967Proxy(address(vaultImpl), vInit)));
        assertEq(address(vault), predictedVault, "vault address mismatch");

        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(dToken);

        stratA = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        stratB = _deployMockStrategyFor(vault, IERC20(address(underlying)));

        vault.addToWhitelist(address(stratA));
        vault.addToWhitelist(address(stratB));
        vault.addStrategy(IStrategy(address(stratA)), 5000, type(uint256).max);
        vault.addStrategy(IStrategy(address(stratB)), 5000, type(uint256).max);
    }

    // --- Helpers ---

    function _deposit(address user, uint256 amount) internal returns (uint256 dTokenAmount) {
        underlying.mint(user, amount);
        vm.startPrank(user);
        underlying.approve(address(vault), amount);
        dTokenAmount = vault.deposit(amount);
        vm.stopPrank();
    }

    function _warpPast(uint256 delay) internal {
        vm.warp(block.timestamp + delay + 1);
    }

    function _deployMockStrategyFor(CollateralVault _vault, IERC20 _underlying) internal returns (MockStrategy s) {
        MockStrategy impl = new MockStrategy();
        bytes memory data =
            abi.encodeWithSelector(MockStrategy.initialize.selector, address(_vault), _underlying, admin);
        s = MockStrategy(address(new ERC1967Proxy(address(impl), data)));
    }

    function _deployFailingDepositStrategyFor(CollateralVault _vault, IERC20 _underlying)
        internal
        returns (FailingDepositMockStrategy s)
    {
        FailingDepositMockStrategy impl = new FailingDepositMockStrategy();
        bytes memory data =
            abi.encodeWithSelector(FailingDepositMockStrategy.initialize.selector, address(_vault), _underlying, admin);
        s = FailingDepositMockStrategy(address(new ERC1967Proxy(address(impl), data)));
    }

    // =================================================================
    //                       Allocate
    // =================================================================

    function test_Allocate_DistributesByWeightBps() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);

        uint256 bufferBefore = vault.bufferBalance();
        uint256 expectedTarget = (vault.totalUnderlying() * vault.bufferTargetBps()) / BPS_DENOMINATOR;

        vm.expectEmit(false, false, false, false, address(vault));
        emit Allocated(0, 0, 0); // only assert the event fires
        vault.allocate();

        uint256 movedTotal = bufferBefore - expectedTarget;
        assertApproxEqAbs(stratA.principal(), movedTotal / 2, 1, "stratA principal half");
        assertApproxEqAbs(stratB.principal(), movedTotal / 2, 1, "stratB principal half");
        assertEq(stratA.principal(), stratB.principal(), "equal weights -> equal principal");
    }

    function test_Allocate_EmitsPerStrategyAmounts() public {
        uint256 amount = 10e8;
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyAllocated(address(stratA), amount / 2);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyAllocated(address(stratB), amount / 2);
        vault.allocate();
    }

    function test_AllocateMaxMoveZero_DisablesOutboundAllocation() public {
        uint256 amount = 10e8;
        vault.setBufferConfig(0, 0);
        vault.setAllocatorConfig(0, 0);
        _deposit(alice, amount);

        vm.expectEmit(false, false, false, true, address(vault));
        emit Allocated(amount, 0, amount);
        vault.allocate();

        assertEq(vault.bufferBalance(), amount, "buffer unchanged");
        assertEq(stratA.principal(), 0, "stratA not funded");
        assertEq(stratB.principal(), 0, "stratB not funded");
        assertEq(vault.lastAllocatorTime(), block.timestamp, "zero move is observable and consumes cooldown");
    }

    function test_AllocateMaxMoveZero_UnderbackedStateRemainsObservable() public {
        uint256 amount = 10e8;
        vault.setBufferConfig(0, 0);
        vault.setAllocatorConfig(0, 0);
        _deposit(alice, amount);
        deal(address(underlying), address(vault), amount / 2);

        vm.expectEmit(false, false, false, true, address(vault));
        emit Allocated(amount / 2, 0, amount / 2);
        vault.allocate();

        assertEq(vault.backingRatio(), 5e17, "fixture remains underbacked");
        assertEq(stratA.principal(), 0, "stratA not funded");
        assertEq(stratB.principal(), 0, "stratB not funded");
        assertEq(vault.lastAllocatorTime(), block.timestamp, "zero move still consumes cooldown");
    }

    function test_Allocate_ZeroTargetBpsUsesAbsoluteFloorAndConfigCorrectionRecovers() public {
        uint256 amount = 10e8;
        uint256 floor = 4e8;
        vault.setBufferConfig(0, floor);
        _deposit(alice, amount);

        vm.expectEmit(false, false, false, true, address(vault));
        emit Allocated(amount, floor, floor);
        vault.allocate();

        assertEq(vault.bufferBalance(), floor, "absolute floor is reserved independently of percentage");
        assertEq(stratA.principal() + stratB.principal(), amount - floor, "only value above floor is allocated");

        vault.setBufferConfig(0, 0);
        vault.allocate();

        assertEq(vault.bufferBalance(), 0, "corrected floor releases the remaining buffer");
        assertEq(stratA.principal() + stratB.principal(), amount, "allocation resumes without migration");
    }

    function test_Allocate_IgnoresProtectedBackstopReserveForTarget() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);

        underlying.mint(bob, amount);
        vm.startPrank(bob);
        underlying.approve(address(vault), amount);
        vault.backstopDeposit(amount);
        vm.stopPrank();

        uint256 expectedTarget = (amount * vault.bufferTargetBps()) / BPS_DENOMINATOR;

        vault.allocate();

        assertEq(vault.backstopBalance(), amount, "reserve not allocated");
        assertEq(vault.bufferBalance(), expectedTarget, "target based on managed assets only");
        assertEq(
            stratA.principal() + stratB.principal(), amount - expectedTarget, "only liquid buffer excess allocated"
        );
    }

    function test_Allocate_DepositRevertRecoversAndContinuesToHealthyStrategy() public {
        uint256 amount = 10e8;
        FailingDepositMockStrategy failing = _deployFailingDepositStrategyFor(vault, IERC20(address(underlying)));
        MockStrategy healthy = _deployMockStrategyFor(vault, IERC20(address(underlying)));

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(failing));
        vault.addStrategy(IStrategy(address(failing)), 5000, type(uint256).max);
        vault.addToWhitelist(address(healthy));
        vault.addStrategy(IStrategy(address(healthy)), 5000, type(uint256).max);
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        vm.expectEmit(true, false, false, false, address(vault));
        emit StrategyAllocationSkipped(address(failing));
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyAllocated(address(healthy), amount / 2);
        vault.allocate();

        assertEq(vault.bufferBalance(), amount / 2, "recovered failed share remains in the buffer");
        assertEq(underlying.balanceOf(address(failing)), 0, "failed strategy retains no idle underlying");
        assertEq(failing.principal(), 0, "failing strategy principal stays zero");
        assertEq(failing.depositAttempts(), 0, "isolated upstream call effects are rolled back");
        assertEq(healthy.principal(), amount / 2, "later healthy strategy is still allocated");
        assertEq(vault.totalUnderlying(), amount, "allocation isolation preserves total backing");
    }

    function test_Allocate_DepositRevertFailsClosedWhenTransferFeesPreventExactRecovery() public {
        uint256 amount = 10e8;
        (CollateralVault fotVault, MockStrategy existing, FeeOnTransferToken fot) = _deployFeeOnTransferSetup();
        FailingDepositMockStrategy failing = _deployFailingDepositStrategyFor(fotVault, IERC20(address(fot)));

        fotVault.updateStrategy(IStrategy(address(existing)), 0, type(uint256).max, false);
        fotVault.addToWhitelist(address(failing));
        fotVault.addStrategy(IStrategy(address(failing)), 10_000, type(uint256).max);
        fotVault.setBufferConfig(0, 0);

        fot.mint(alice, amount);
        vm.startPrank(alice);
        fot.approve(address(fotVault), amount);
        fotVault.deposit(amount);
        vm.stopPrank();
        uint256 bufferBefore = fotVault.bufferBalance();

        vm.expectRevert(BaseStrategy.DepositRecoveryFailed.selector);
        fotVault.allocate();

        assertEq(fotVault.bufferBalance(), bufferBefore, "failed recovery rolls the full allocation back");
        assertEq(fot.balanceOf(address(failing)), 0, "failed strategy transfer is rolled back");
        assertEq(failing.principal(), 0, "failed strategy principal remains zero");
    }

    function test_Allocate_DepositRevertFailsClosedWhenReturnTransferFails() public {
        uint256 amount = 10e8;
        FalseReturnToken token = new FalseReturnToken("False Return", "FALSE", 8);
        (CollateralVault falseReturnVault, MockStrategy existing) =
            _deployMockStrategySetupFor(IERC20MetadataUpgradeable(address(token)));
        FailingDepositMockStrategy failing = _deployFailingDepositStrategyFor(falseReturnVault, IERC20(address(token)));

        falseReturnVault.updateStrategy(IStrategy(address(existing)), 0, type(uint256).max, false);
        falseReturnVault.addToWhitelist(address(failing));
        falseReturnVault.addStrategy(IStrategy(address(failing)), 10_000, type(uint256).max);
        falseReturnVault.setBufferConfig(0, 0);

        token.mint(alice, amount);
        vm.startPrank(alice);
        token.approve(address(falseReturnVault), amount);
        falseReturnVault.deposit(amount);
        vm.stopPrank();
        token.setFalseReturnRecipient(address(falseReturnVault));

        vm.expectRevert(BaseStrategy.DepositRecoveryFailed.selector);
        falseReturnVault.allocate();

        assertEq(falseReturnVault.bufferBalance(), amount, "failed recovery rolls the full allocation back");
        assertEq(token.balanceOf(address(failing)), 0, "failed strategy transfer is rolled back");
        assertEq(failing.principal(), 0, "failed strategy principal remains zero");
    }

    function test_Allocate_StopsAllOutboundOnEstimateFailureAndRecoversAutomatically() public {
        uint256 bufferAmount = 100e8;
        ConfigurableValuationStrategy unavailable = new ConfigurableValuationStrategy(address(underlying));
        ConfigurableValuationStrategy healthy = new ConfigurableValuationStrategy(address(underlying));
        unavailable.setEstimatedValue(800e8);
        unavailable.setPrincipalValue(800e8);
        healthy.setEstimatedValue(200e8);
        healthy.setPrincipalValue(200e8);
        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(unavailable));
        vault.addStrategy(IStrategy(address(unavailable)), 0, type(uint256).max);
        vault.addToWhitelist(address(healthy));
        vault.addStrategy(IStrategy(address(healthy)), 10_000, type(uint256).max);
        vault.setBufferConfig(2000, 0);
        underlying.mint(address(vault), bufferAmount);

        unavailable.setRevertEstimated(true);
        vault.allocate();

        assertEq(vault.bufferBalance(), bufferAmount, "partial valuation cannot reduce the liquid buffer");
        assertEq(underlying.balanceOf(address(unavailable)), 0, "unavailable strategy receives nothing");
        assertEq(underlying.balanceOf(address(healthy)), 0, "healthy strategy receives nothing from a partial view");
        assertEq(vault.lastAllocatorTime(), 0, "failed preflight does not consume the recovery cooldown");

        unavailable.setRevertEstimated(false);
        underlying.mint(address(vault), 200e8);
        vault.allocate();

        assertEq(underlying.balanceOf(address(unavailable)), 0, "zero-weight strategy remains unfunded");
        assertEq(underlying.balanceOf(address(healthy)), 40e8, "healthy strategy resumes without manual reset");
        assertEq(vault.bufferBalance(), 260e8, "only live-view excess leaves the buffer");
    }

    function test_Allocate_StopsAllOutboundWhenPrincipalValuationReverts() public {
        uint256 amount = 10e8;
        ConfigurableValuationStrategy bad = new ConfigurableValuationStrategy(address(underlying));
        bad.setRevertPrincipal(true);

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(bad));
        vault.addStrategy(IStrategy(address(bad)), 5000, type(uint256).max);
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        vault.allocate();

        assertEq(stratB.principal(), 0, "healthy strategy is not funded from a partial system view");
        assertEq(vault.bufferBalance(), amount, "all outbound allocation stops on principal failure");
    }

    function test_Allocate_CapCheckDoesNotOverflowOnHugeEstimate() public {
        uint256 amount = 10e8;
        ConfigurableValuationStrategy capped = new ConfigurableValuationStrategy(address(underlying));
        capped.setEstimatedValue(type(uint256).max);

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(capped));
        vault.addStrategy(IStrategy(address(capped)), 5000, type(uint256).max);
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyAllocated(address(stratB), amount / 2);
        vm.expectEmit(true, false, false, false, address(vault));
        emit StrategyAllocationSkipped(address(capped));
        vault.allocate();

        assertEq(stratB.principal(), amount / 2, "healthy strategy still allocated");
        assertEq(vault.bufferBalance(), amount / 2, "capped strategy share remains in buffer");
    }

    function test_Allocate_PostDepositRefreshFailureRevertsAndRecoversAutomatically() public {
        uint256 amount = 10e8;
        RevertingAfterDepositStrategy flaky = new RevertingAfterDepositStrategy(address(underlying));

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(flaky));
        vault.addStrategy(IStrategy(address(flaky)), 10_000, type(uint256).max);
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        flaky.setRevertAfterDeposit(true);
        uint256 allocatorTimeBefore = vault.lastAllocatorTime();

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(0), uint256(1e18))
        );
        vault.allocate();

        (uint256 cached,, bool initialized) = vault.strategyValuationCaches(IStrategy(address(flaky)));
        assertTrue(initialized, "pre-allocation cache remains initialized");
        assertEq(cached, 0, "failed allocation cannot replace live proof with cache");
        assertEq(vault.bufferBalance(), amount, "failed allocation restores buffer");
        assertEq(flaky.principal(), 0, "failed allocation restores principal");
        assertEq(vault.lastAllocatorTime(), allocatorTimeBefore, "failed allocation does not consume cooldown");

        flaky.setRevertAfterDeposit(false);
        vault.allocate();

        assertEq(vault.bufferBalance(), 0, "healthy valuation restores allocation liveness");
        assertEq(flaky.principal(), amount, "healthy retry allocates principal");
        assertEq(vault.backingRatio(), 1e18, "healthy retry preserves full backing");
    }

    function test_Allocate_PostDepositRefreshFailureDoesNotCommitStaleHighCache() public {
        uint256 initialAmount = 100e8;
        uint256 liveAfterLoss = 20e8;
        uint256 newAmount = 10e8;
        RevertingAfterDepositStrategy flaky = new RevertingAfterDepositStrategy(address(underlying));

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(flaky));
        vault.addStrategy(IStrategy(address(flaky)), 10_000, type(uint256).max);
        vault.setBufferConfig(0, 0);

        _deposit(alice, initialAmount);
        vault.allocate();

        (uint256 staleHighCache,, bool cacheInitializedBeforeLoss) =
            vault.strategyValuationCaches(IStrategy(address(flaky)));
        assertTrue(cacheInitializedBeforeLoss, "cache initialized by first allocation");
        assertEq(staleHighCache, initialAmount, "cache starts high");

        flaky.setValues(liveAfterLoss, liveAfterLoss);
        _warpPast(vault.strategyValuationMaxAge());
        assertEq(vault.totalUnderlying(), liveAfterLoss, "live low valuation wins before the next allocation");

        uint256 repairAmount = initialAmount - liveAfterLoss + newAmount;
        underlying.mint(bob, repairAmount);
        vm.startPrank(bob);
        underlying.approve(address(vault), repairAmount);
        vault.backstopDeposit(repairAmount);
        vm.stopPrank();
        vault.releaseBackstopToBuffer(newAmount);
        flaky.setRevertAfterDeposit(true);
        uint256 allocatorTimeBefore = vault.lastAllocatorTime();

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(8e17), uint256(1e18))
        );
        vault.allocate();

        (uint256 cachedAfter,, bool cacheInitializedAfter) = vault.strategyValuationCaches(IStrategy(address(flaky)));
        assertTrue(cacheInitializedAfter, "pre-allocation cache remains initialized");
        assertEq(cachedAfter, staleHighCache, "failed allocation leaves stale cache unchanged");
        assertEq(vault.bufferBalance(), newAmount, "failed allocation restores released buffer");
        assertEq(flaky.principal(), liveAfterLoss, "failed allocation restores principal");
        assertEq(vault.lastAllocatorTime(), allocatorTimeBefore, "failed allocation preserves allocator timestamp");
    }

    function test_Allocate_ReadOnlyReentryDuringDepositCannotInflateVaultViews() public {
        uint256 amount = 10e8;
        ReadOnlyReentrantAllocateStrategy observer =
            new ReadOnlyReentrantAllocateStrategy(address(underlying), ICollateralVault(address(vault)));

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);
        vault.addToWhitelist(address(observer));
        vault.addStrategy(IStrategy(address(observer)), 10_000, type(uint256).max);
        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);

        observer.setAttemptMutatingReentry(true);
        vault.allocate();

        assertTrue(observer.mutatingReentryReverted(), "mutating reentry blocked by Vault guard");
        assertFalse(observer.mutatingReentrySucceeded(), "mutating reentry must not succeed");
        assertEq(observer.observedStrategyCount(), 3, "read-only status view was reachable");
        assertEq(observer.observedTotalUnderlying(), 0, "in-flight allocation view cannot overstate backing");
        assertEq(observer.observedBackingRatio(), 0, "in-flight backing ratio is conservative");
        assertEq(vault.totalUnderlying(), amount, "post-allocation backing restored");
        assertEq(vault.backingRatio(), 1e18, "post-allocation branch fully backed");
    }

    function test_AllocatorCooldown_Enforced() public {
        _deposit(alice, 10e8);

        vault.allocate(); // cooldown 0 sets lastAllocatorTime

        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocatorConfigUpdated(type(uint256).max, type(uint256).max, 0, 1 hours);
        vault.setAllocatorConfig(type(uint256).max, 1 hours);

        vm.expectRevert(CollateralVault.CooldownNotMet.selector);
        vault.allocate();

        _warpPast(1 hours);
        vault.allocate(); // no revert
    }

    function test_AllocatorCooldown_HighValueBlocksButConfigCorrectionRecovers() public {
        _deposit(alice, 10e8);
        vault.allocate();

        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocatorConfigUpdated(type(uint256).max, type(uint256).max, 0, 365 days);
        vault.setAllocatorConfig(type(uint256).max, 365 days);

        _warpPast(30 days);
        vm.expectRevert(CollateralVault.CooldownNotMet.selector);
        vault.allocate();

        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocatorConfigUpdated(type(uint256).max, type(uint256).max, 365 days, 0);
        vault.setAllocatorConfig(type(uint256).max, 0);

        vault.allocate();
        assertEq(vault.lastAllocatorTime(), block.timestamp, "corrected cooldown restores allocation liveness");
    }

    // =================================================================
    //                  deferred-underlying addStrategy guard (jpydf-v2)
    // =================================================================

    /// @dev jpydf-v2 specific: addStrategy must reject a Strategy whose underlying
    ///      differs from the Vault's (dToken.md §2.2.10 / §2.2.11).
    function test_AddStrategy_RevertsOnUnderlyingMismatch() public {
        MockERC20 otherU = new MockERC20("Other", "OTH", 8);
        MockStrategy bad = _deployMockStrategyFor(vault, IERC20(address(otherU)));
        vault.addToWhitelist(address(bad));

        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        vault.addStrategy(IStrategy(address(bad)), 0, type(uint256).max);
    }

    /// @dev jpydf-v2 specific: addStrategy must reject registration on a
    ///      not-yet-bound placeholder Vault (`underlying == address(0)`), which
    ///      restores the activation-order guard the push model would otherwise drop.
    function test_AddStrategy_RevertsOnPlaceholderVault_UnderlyingNotSet() public {
        DToken dImpl = new DToken();
        CollateralVault impl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        DToken placeholderDToken = DToken(
            address(
                new ERC1967Proxy(address(dImpl), abi.encodeWithSelector(DToken.initialize.selector, predicted, admin))
            )
        );
        bytes memory init = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(0)), // placeholder underlying
            IDToken(address(placeholderDToken)),
            treasury,
            admin
        );
        CollateralVault placeholder = CollateralVault(address(new ERC1967Proxy(address(impl), init)));
        assertEq(address(placeholder), predicted, "vault address prediction mismatch");
        assertEq(address(placeholder.underlying()), address(0), "vault is a placeholder");

        MockStrategy s = _deployMockStrategyFor(placeholder, IERC20(address(underlying)));
        placeholder.addToWhitelist(address(s));

        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        placeholder.addStrategy(IStrategy(address(s)), 5000, type(uint256).max);
    }

    // =================================================================
    //                  sendToVault / sendProfitToVault
    // =================================================================

    function test_SendToVault_DecrementsPrincipalBySent() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 principalBefore = stratA.principal();
        uint256 bufferBefore = vault.bufferBalance();
        (uint256 cachedBefore, uint256 cachedAt, bool cacheInitializedBefore) =
            vault.strategyValuationCaches(IStrategy(address(stratA)));
        assertTrue(cacheInitializedBefore, "valuation cache initialized");
        assertEq(cachedBefore, principalBefore, "cache starts at principal");

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationCacheInvalidated(address(stratA), cachedBefore, cachedAt);
        vm.prank(admin); // ALLOCATOR_ROLE
        uint256 sent = stratA.sendToVault(principalBefore);

        assertEq(sent, principalBefore, "sent equals requested (no fee token)");
        assertEq(stratA.principal(), 0, "principal decremented by sent");
        assertEq(vault.bufferBalance(), bufferBefore + sent, "buffer increased by sent");
        (uint256 cachedAfter,, bool cacheInitializedAfter) = vault.strategyValuationCaches(IStrategy(address(stratA)));
        assertFalse(cacheInitializedAfter, "exhausted historical estimate is invalidated");
        assertEq(cachedAfter, 0, "cache reduced to avoid double count");
    }

    function testFuzz_GuardianL10_ExhaustedCacheDuringFailedValuationIsUnavailable(uint256 cached) public {
        cached = bound(cached, 0, 60e8);
        (CollateralVault fVault, FailingMockStrategy fStrat) = _deployFailingSetup();
        underlying.mint(alice, 100e8);
        vm.startPrank(alice);
        underlying.approve(address(fVault), 100e8);
        fVault.deposit(100e8);
        vm.stopPrank();
        fVault.setBufferConfig(0, 0);
        fVault.allocate();
        deal(address(underlying), address(fStrat), cached);
        assertTrue(fVault.refreshStrategyValuation(IStrategy(address(fStrat))));
        deal(address(underlying), address(fStrat), 100e8);
        fStrat.setValuationShouldFail(true);
        fStrat.setWithdrawShouldFail(false);
        assertEq(fStrat.sendToVault(60e8), 60e8);
        (,, bool initialized) = fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertFalse(initialized, "receipt cannot prove a zero residual valuation");
        (, bool available) = fVault.backingRatioForPricing();
        assertFalse(available, "known assets alone do not cover liabilities");
        fStrat.setValuationShouldFail(false);
        (uint256 ratio, bool recovered) = fVault.backingRatioForPricing();
        assertTrue(recovered);
        assertEq(ratio, 1e18);
    }

    function test_SendToVault_PartialRecoveryDoesNotRenewValuationCache() public {
        (CollateralVault fVault, FailingMockStrategy fStrat) = _deployFailingSetup();

        uint256 amount = 100e8;
        uint256 recovered = 10e8;
        underlying.mint(alice, amount);
        vm.startPrank(alice);
        underlying.approve(address(fVault), amount);
        fVault.deposit(amount);
        vm.stopPrank();
        fVault.setBufferConfig(0, 0);
        fVault.allocate();

        (uint256 cachedBefore, uint256 updatedBefore, bool initializedBefore) =
            fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertTrue(initializedBefore, "allocation initializes cache");
        assertEq(cachedBefore, amount, "cache starts at principal");

        fStrat.setValuationShouldFail(true);
        fStrat.setWithdrawShouldFail(false);

        uint256 maxAge = fVault.strategyValuationMaxAge();
        vm.warp(updatedBefore + maxAge - 1);
        vm.prank(admin);
        uint256 sent = fStrat.sendToVault(recovered);
        assertEq(sent, recovered, "partial recovery reaches vault");

        (uint256 cachedAfter, uint256 updatedAfter, bool initializedAfter) =
            fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertTrue(initializedAfter, "cache remains initialized");
        assertEq(cachedAfter, cachedBefore - recovered, "receipt reduces cached value");
        assertEq(updatedAfter, updatedBefore, "partial receipt is not a full valuation refresh");

        vm.warp(updatedBefore + maxAge + 1);
        (uint256 unavailableRatio, bool availableBeforeRecovery) = fVault.backingRatioForPricing();
        assertEq(unavailableRatio, 0, "pricing returns the unavailable sentinel");
        assertFalse(availableBeforeRecovery, "partial receipt cannot extend the original valuation TTL");

        fStrat.setValuationShouldFail(false);
        vm.prank(bob);
        assertTrue(
            fVault.refreshStrategyValuation(IStrategy(address(fStrat))), "permissionless full refresh restores liveness"
        );
        (uint256 recoveredRatio, bool availableAfterRecovery) = fVault.backingRatioForPricing();
        assertEq(recoveredRatio, 1e18, "recovered valuation preserves full backing");
        assertTrue(availableAfterRecovery, "fresh full valuation restores pricing availability");
    }

    function test_WriteoffStrategyPrincipal_DoesNotRestoreUnavailablePricing() public {
        (CollateralVault fVault, FailingMockStrategy fStrat) = _deployFailingSetup();

        uint256 amount = 100e8;
        underlying.mint(alice, amount);
        vm.startPrank(alice);
        underlying.approve(address(fVault), amount);
        fVault.deposit(amount);
        vm.stopPrank();
        fVault.setBufferConfig(0, 0);
        fVault.allocate();

        (uint256 cachedBefore, uint256 updatedBefore, bool initializedBefore) =
            fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertTrue(initializedBefore, "allocation initializes cache");
        assertEq(cachedBefore, amount, "cache starts at principal");

        deal(address(underlying), address(fStrat), 0);
        fStrat.setValuationShouldFail(true);
        fVault.pauseAllocation();
        vm.warp(updatedBefore + fVault.strategyValuationMaxAge() + 1);

        fVault.writeoffStrategyPrincipal(IStrategy(address(fStrat)), amount, 0);

        assertEq(fStrat.principal(), 0, "confirmed loss is written off");
        (uint256 cachedAfter, uint256 updatedAfter, bool initializedAfter) =
            fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertFalse(initializedAfter, "exhausted historical estimate is invalidated");
        assertEq(cachedAfter, 0, "writeoff removes cached value");
        assertEq(updatedAfter, 0, "invalidated cache has no observation timestamp");

        (uint256 unavailableRatio, bool availableAfterWriteoff) = fVault.backingRatioForPricing();
        assertEq(unavailableRatio, 0, "pricing returns the unavailable sentinel");
        assertFalse(availableAfterWriteoff, "accounting writeoff alone cannot restore valuation availability");
    }

    function test_SendProfitToVault_PrincipalUnchanged() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 yieldAmt = 1e7; // 0.1 WBTC yield on stratA
        underlying.mint(address(stratA), yieldAmt);
        stratA.setMockYield(yieldAmt);

        uint256 principalBefore = stratA.principal();
        uint256 bufferBefore = vault.bufferBalance();
        (uint256 cachedBefore,, bool cacheInitializedBefore) = vault.strategyValuationCaches(IStrategy(address(stratA)));
        assertTrue(cacheInitializedBefore, "valuation cache initialized");

        vm.prank(admin); // ALLOCATOR_ROLE
        uint256 sent = stratA.sendProfitToVault();

        assertEq(sent, yieldAmt, "all realized yield sent");
        assertEq(stratA.principal(), principalBefore, "principal unchanged");
        assertEq(vault.bufferBalance(), bufferBefore + yieldAmt, "buffer increased by yield");
        (uint256 cachedAfter,, bool cacheInitializedAfter) = vault.strategyValuationCaches(IStrategy(address(stratA)));
        assertTrue(cacheInitializedAfter, "yield-only transfer leaves principal cache initialized");
        assertEq(cachedAfter, cachedBefore, "yield receipt does not reduce strategy cache");
    }

    function test_SendToVault_RequiresAllocatorRole() public {
        _deposit(alice, 10e8);
        vault.allocate();

        address noRole = makeAddr("noRole");
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        vm.prank(noRole);
        stratA.sendToVault(1);
    }

    function test_SendProfitToVault_RequiresAllocatorRole() public {
        address noRole = makeAddr("noRole");
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        vm.prank(noRole);
        stratA.sendProfitToVault();
    }

    /// @dev jpydf-v2 negative path: a reverting upstream `_doWithdraw` propagates
    ///      out of `sendToVault` (uses FailingMockStrategy in a dedicated vault).
    function test_SendToVault_WithdrawReverts_Propagates() public {
        (CollateralVault fVault, FailingMockStrategy fStrat) = _deployFailingSetup();

        underlying.mint(address(fVault), 10e8);
        fVault.setBufferConfig(0, 0);
        fVault.allocate(); // _doDeposit is a no-op, so underlying sits in the strategy; principal tracked

        // Precompute principal BEFORE expectRevert: evaluating an external call
        // inside the revert-asserted call args would otherwise consume the
        // expectRevert / prank (Foundry gotcha).
        uint256 principalAmt = fStrat.principal();
        assertGt(principalAmt, 0, "failing strat holds principal");

        vm.prank(admin); // ALLOCATOR_ROLE
        vm.expectRevert(bytes("WithdrawFailed"));
        fStrat.sendToVault(principalAmt);
    }

    // =================================================================
    //                  BaseStrategy ownership controls
    // =================================================================

    function test_BaseStrategy_InitializeRevertsOnZeroOwner() public {
        MockStrategy impl = new MockStrategy();
        bytes memory data = abi.encodeWithSelector(
            MockStrategy.initialize.selector, address(vault), IERC20(address(underlying)), address(0)
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function test_BaseStrategy_InitializeRevertsOnNonContractVault() public {
        address vaultEoa = makeAddr("vaultEoa");
        MockStrategy impl = new MockStrategy();
        bytes memory data =
            abi.encodeWithSelector(MockStrategy.initialize.selector, vaultEoa, IERC20(address(underlying)), admin);

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, vaultEoa));
        new ERC1967Proxy(address(impl), data);
    }

    function test_BaseStrategy_InitializeRevertsOnNonContractUnderlying() public {
        address underlyingEoa = makeAddr("underlyingEoa");
        MockStrategy impl = new MockStrategy();
        bytes memory data =
            abi.encodeWithSelector(MockStrategy.initialize.selector, address(vault), IERC20(underlyingEoa), admin);

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, underlyingEoa));
        new ERC1967Proxy(address(impl), data);
    }

    function test_BaseStrategy_ReentrancyGuardBlocksNestedEntry() public {
        StrategyReentrancyGuardHarness harness = new StrategyReentrancyGuardHarness();

        vm.expectRevert(BaseStrategy.ReentrantCall.selector);
        harness.enterTwice();

        harness.guardedNoop();
    }

    function test_BaseStrategy_TransferOwnershipIsTwoStep() public {
        address newOwner = makeAddr("strategyNewOwner");

        vm.expectEmit(true, true, false, true, address(stratA));
        emit OwnershipTransferStarted(admin, newOwner);
        stratA.transferOwnership(newOwner);

        assertEq(stratA.owner(), admin, "owner unchanged until accept");
        assertEq(stratA.pendingOwner(), newOwner, "pending owner set");

        vm.prank(newOwner);
        stratA.acceptOwnership();

        assertEq(stratA.owner(), newOwner, "ownership accepted");
        assertEq(stratA.pendingOwner(), address(0), "pending owner cleared");
    }

    function test_BaseStrategy_AcceptOwnershipRevertsForNonPendingOwner() public {
        address newOwner = makeAddr("strategyNewOwner");
        address notPending = makeAddr("notPending");

        stratA.transferOwnership(newOwner);

        vm.prank(notPending);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        stratA.acceptOwnership();
    }

    function test_BaseStrategy_TransferOwnershipZeroAddressCancelsPendingTransfer() public {
        address newOwner = makeAddr("strategyNewOwner");

        stratA.transferOwnership(newOwner);
        assertEq(stratA.pendingOwner(), newOwner, "pending owner set");

        stratA.transferOwnership(address(0));
        assertEq(stratA.owner(), admin, "owner unchanged");
        assertEq(stratA.pendingOwner(), address(0), "pending owner cleared");

        vm.prank(newOwner);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        stratA.acceptOwnership();
    }

    function test_BaseStrategy_RenounceOwnershipDisabled() public {
        vm.expectRevert(BaseStrategy.RenounceOwnershipDisabled.selector);
        stratA.renounceOwnership();

        assertEq(stratA.owner(), admin, "owner preserved");
    }

    function test_BaseStrategy_SetUpgraderRequiresCurrentUpgrader() public {
        address newUpgrader = makeAddr("strategyUpgrader");
        address noRole = makeAddr("strategyNoRole");

        vm.expectEmit(true, true, false, true, address(stratA));
        emit UpgraderUpdated(admin, newUpgrader);
        stratA.setUpgrader(newUpgrader);

        assertEq(stratA.upgrader(), newUpgrader, "upgrader changed");

        vm.prank(admin); // owner, but no longer upgrader
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        stratA.setUpgrader(noRole);

        vm.prank(noRole);
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        stratA.setUpgrader(admin);
    }

    function test_BaseStrategy_SetUpgraderRejectsZeroAddress() public {
        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        stratA.setUpgrader(address(0));
    }

    function test_BaseStrategy_UpgradeAuthorizationRequiresUpgrader() public {
        address newUpgrader = makeAddr("strategyUpgrader");
        address noRole = makeAddr("strategyNoRole");
        MockStrategy newImpl = new MockStrategy();

        stratA.setUpgrader(newUpgrader);

        vm.prank(admin); // owner, but no longer upgrader
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        UUPSUpgradeable(address(stratA)).upgradeTo(address(newImpl));

        vm.prank(address(vault));
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        UUPSUpgradeable(address(stratA)).upgradeTo(address(newImpl));

        vm.prank(noRole);
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        UUPSUpgradeable(address(stratA)).upgradeTo(address(newImpl));

        vm.prank(newUpgrader);
        UUPSUpgradeable(address(stratA)).upgradeTo(address(newImpl));
    }

    // =================================================================
    //                  transferYieldToTreasury
    // =================================================================

    function test_TransferYieldToTreasury_OnlySurplus() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 yieldAmt = 1e7;
        underlying.mint(address(stratA), yieldAmt);
        stratA.setMockYield(yieldAmt);

        vm.prank(admin);
        stratA.sendProfitToVault();

        vm.expectEmit(false, true, false, true, address(vault));
        emit YieldTransferredToTreasury(yieldAmt, treasury);
        vm.prank(admin);
        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, yieldAmt, "treasury received yield");
        assertEq(underlying.balanceOf(treasury), yieldAmt, "treasury balance");
    }

    function test_TransferYieldToTreasury_UnderwaterReturnsZero() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.expectEmit(false, true, false, true, address(vault));
        emit YieldTransferredToTreasury(0, treasury);
        vm.prank(admin);
        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, 0, "no surplus -> zero transferred");
        assertEq(underlying.balanceOf(treasury), 0, "treasury untouched");
    }

    function test_TransferYieldToTreasury_StopsOnPartialValuationAndRecoversAutomatically() public {
        _deposit(alice, 100e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 yieldAmount = 20e8;
        underlying.mint(address(stratA), yieldAmount);
        stratA.setMockYield(yieldAmount);
        vm.prank(admin);
        stratA.sendProfitToVault();

        ConfigurableValuationStrategy unavailable = new ConfigurableValuationStrategy(address(underlying));
        vault.addToWhitelist(address(unavailable));
        vault.addStrategy(IStrategy(address(unavailable)), 0, type(uint256).max);
        unavailable.setRevertEstimated(true);

        vm.expectEmit(false, true, false, true, address(vault));
        emit YieldTransferredToTreasury(0, treasury);
        uint256 blockedTransfer = vault.transferYieldToTreasury();

        assertEq(blockedTransfer, 0, "partial valuation cannot authorize a treasury transfer");
        assertEq(underlying.balanceOf(treasury), 0, "treasury remains untouched during the failure");
        assertEq(vault.bufferBalance(), yieldAmount, "yield remains liquid in the vault");

        unavailable.setRevertEstimated(false);
        uint256 recoveredTransfer = vault.transferYieldToTreasury();

        assertEq(recoveredTransfer, yieldAmount, "treasury transfer resumes after live valuation recovers");
        assertEq(underlying.balanceOf(treasury), yieldAmount, "only the realized yield is transferred");
        assertEq(vault.bufferBalance(), 0, "recovered transfer consumes the liquid surplus");
    }

    function test_TransferYieldToTreasury_RequiresAllocatorRole() public {
        address noRole = makeAddr("noRole");
        vm.expectRevert(); // AccessControl: missing role
        vm.prank(noRole);
        vault.transferYieldToTreasury();
    }

    /// @dev Regression for issue #70 High3 / claim2: yield extraction must not
    ///      spend buffer earmarked for queued withdrawals. With a pending claim
    ///      outstanding, transferYieldToTreasury keeps `pendingWithdrawals` in the
    ///      buffer (the old code swept `min(surplus, bufferBalance())` and could
    ///      drain it to zero, stranding the claim) and the claim still settles.
    function test_TransferYieldToTreasury_ReservesBufferForPendingClaims() public {
        _deposit(alice, 100e8);
        vault.setBufferConfig(0, 0); // isolate the pendingWithdrawals reserve
        vault.allocate(); // buffer 0, stratA / stratB 50e8 each

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeem(20e18, alice);
        assertEq(received, 0, "empty buffer -> fully queued");
        assertEq(vault.pendingWithdrawals(), 20e8, "20e8 queued");

        // Realize 30e8 of yield into the liquid buffer via a strategy push.
        underlying.mint(address(stratA), 30e8);
        stratA.setMockYield(30e8);
        vm.prank(admin);
        stratA.sendProfitToVault();
        assertEq(vault.bufferBalance(), 30e8, "yield landed in buffer");

        // managed = 30e8 buffer + 100e8 strategy = 130e8
        // liabilities = 80e8 dToken + 20e8 pending = 100e8 -> surplus 30e8
        // requiredBuffer = pending 20e8 -> freeBuffer = 30e8 - 20e8 = 10e8
        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, 10e8, "only buffer above the pending reserve is swept");
        assertEq(underlying.balanceOf(treasury), 10e8, "treasury got free yield only");
        assertEq(vault.bufferBalance(), 20e8, "pending reserve kept in buffer");
        assertGe(vault.bufferBalance(), vault.pendingWithdrawals(), "queue stays serviceable");

        // The queued claim now settles in full (old behaviour drained buffer to 0).
        _warpPast(1 days);
        vm.prank(alice);
        uint256 claimed = vault.claim(requestId);
        assertEq(claimed, 20e8, "queued claim paid in full");
        assertEq(vault.pendingWithdrawals(), 0, "queue cleared");
    }

    /// @dev With no pending withdrawals, transferYieldToTreasury still keeps the
    ///      same configured buffer target that `allocate` reserves (here 20% of
    ///      managed assets), sweeping only the buffer above it.
    function test_TransferYieldToTreasury_ReservesConfiguredBufferTarget() public {
        vault.setBufferConfig(2000, 0); // 20% target
        _deposit(alice, 100e8);
        vault.allocate(); // keeps 20e8 buffer, 80e8 to strategies (40e8 each)
        assertEq(vault.bufferBalance(), 20e8, "20% target kept by allocate");

        underlying.mint(address(stratA), 30e8);
        stratA.setMockYield(30e8);
        vm.prank(admin);
        stratA.sendProfitToVault();
        assertEq(vault.bufferBalance(), 50e8, "buffer = 20e8 + 30e8 yield");

        // managed = 50e8 buffer + 80e8 strategy = 130e8; liabilities 100e8 -> surplus 30e8
        // requiredBuffer = 20% * 130e8 = 26e8 -> freeBuffer = 50e8 - 26e8 = 24e8
        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, 24e8, "sweeps only buffer above the 20% target");
        assertEq(vault.bufferBalance(), 26e8, "buffer held at 20% of managed assets");
        assertEq(vault.pendingWithdrawals(), 0, "no queue involved");
    }

    /// @dev The surplus cap is retained: when the buffer holds only principal
    ///      (no realized yield), nothing is swept even though the buffer is far
    ///      above the reserve. transferYieldToTreasury never sends principal out.
    function test_TransferYieldToTreasury_SurplusCapStillProtectsPrincipal() public {
        vault.setBufferConfig(2000, 0);
        _deposit(alice, 100e8); // buffer 100e8, unallocated -> all principal, surplus 0

        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, 0, "no surplus -> nothing swept despite free buffer");
        assertEq(underlying.balanceOf(treasury), 0, "principal untouched");
        assertEq(vault.bufferBalance(), 100e8, "buffer (principal) preserved");
    }

    // =================================================================
    //                  writeoff / removeStrategy
    // =================================================================

    function test_WriteoffStrategyPrincipal_RevertsWhileEnabledAndAllocationUnpaused() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.expectRevert(CollateralVault.StrategyWriteoffNotReady.selector);
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), 1, 0);
    }

    function test_WriteoffStrategyPrincipal_DecreasesPrincipal() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();
        vault.pauseAllocation();

        uint256 principalBefore = stratA.principal();
        uint256 writeAmt = principalBefore / 2;

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyPrincipalWrittenOff(address(stratA), writeAmt);
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), writeAmt, 0);

        assertEq(stratA.principal(), principalBefore - writeAmt, "principal reduced by writeoff");
        assertTrue(vault.pausedDeposit(), "writeoff pauses deposits");
        assertTrue(vault.pausedRedeem(), "writeoff pauses redemptions");
        assertTrue(vault.pausedClaim(), "writeoff pauses claims");

        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.deposit(1e8);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.redeem(1e18, alice);
    }

    function test_WriteoffStrategyPrincipal_DiscountsBackingWhenEstimateUnchanged() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();
        vault.pauseAllocation();

        uint256 principalBefore = stratA.principal();
        uint256 totalBefore = vault.totalUnderlying();
        uint256 ratioBefore = vault.backingRatio();
        uint256 writeAmt = principalBefore / 2;

        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), writeAmt, 0);

        assertEq(vault.totalUnderlying(), totalBefore - writeAmt, "manual writeoff lowers accounted assets");
        assertLt(vault.backingRatio(), ratioBefore, "manual writeoff lowers backing ratio");
        assertEq(
            _lens().backingShortfall(ICollateralVault(address(vault))),
            writeAmt,
            "shortfall reflects written off principal"
        );
        assertEq(stratA.estimatedTotalUnderlying(), principalBefore, "strategy estimate unchanged");
    }

    function test_WriteoffStrategyPrincipal_AfterZeroRecoveryExposesResidualLoss() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 principalBefore = stratA.principal();
        uint256 totalBefore = vault.totalUnderlying();
        uint256 liabilities = vault.actualLiabilities();
        assertGt(principalBefore, 0, "strategy should hold principal");
        assertEq(totalBefore, liabilities, "setup starts fully backed");

        deal(address(underlying), address(stratA), 0);

        vault.emergencyDisableStrategy(IStrategy(address(stratA)));

        vm.prank(admin);
        uint256 sent = stratA.sendToVault(principalBefore);
        assertEq(sent, 0, "no underlying was recoverable");
        assertEq(stratA.principal(), principalBefore, "zero recovery must not reduce principal");
        assertEq(vault.totalUnderlying(), totalBefore, "loss is not acknowledged before writeoff");

        uint256 expectedTotalAfter = totalBefore - principalBefore;
        uint256 expectedBackingAfter = (expectedTotalAfter * 1e18) / liabilities;

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyPrincipalWrittenOff(address(stratA), principalBefore);
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), principalBefore, expectedBackingAfter);

        assertEq(stratA.principal(), 0, "principal written off");
        assertEq(vault.totalUnderlying(), expectedTotalAfter, "residual loss removed from accounted backing");
        assertEq(
            _lens().backingShortfall(ICollateralVault(address(vault))),
            principalBefore,
            "shortfall equals unrecovered residual"
        );
        assertEq(vault.backingRatio(), expectedBackingAfter, "backing ratio reflects finalized loss");
        assertTrue(vault.pausedDeposit(), "writeoff leaves deposits paused");
        assertTrue(vault.pausedRedeem(), "writeoff leaves redemptions paused");
        assertTrue(vault.pausedClaim(), "writeoff leaves claims paused");
    }

    function test_WriteoffStrategyPrincipal_RevertsWhenBackingWouldFallBelowGuard() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();
        vault.pauseAllocation();

        uint256 principalBefore = stratA.principal();
        uint256 writeAmt = principalBefore / 2;
        uint256 expectedBackingAfter = 75e16;

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, expectedBackingAfter, 80e16)
        );
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), writeAmt, 80e16);

        assertEq(stratA.principal(), principalBefore, "failed guarded writeoff leaves principal unchanged");
        assertEq(vault.backingRatio(), 1e18, "failed guarded writeoff leaves backing unchanged");
        assertFalse(vault.pausedDeposit(), "failed guarded writeoff does not pause deposits");
        assertFalse(vault.pausedRedeem(), "failed guarded writeoff does not pause redemptions");
        assertFalse(vault.pausedClaim(), "failed guarded writeoff does not pause claims");

        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), writeAmt, expectedBackingAfter);
        assertEq(vault.backingRatio(), expectedBackingAfter, "guard allows expected backing impact");
    }

    function test_WriteoffStrategyPrincipal_GuardedRevertPreservesSeparateEmergencyDisable() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();
        vault.emergencyDisableStrategy(IStrategy(address(stratA)));

        uint256 principalBefore = stratA.principal();
        uint256 writeAmt = principalBefore / 2;

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(75e16), uint256(80e16))
        );
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), writeAmt, 80e16);

        (, ICollateralVault.StrategyConfig memory config) = _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertFalse(config.enabled, "separately disabled strategy remains disabled");
        assertEq(config.weightBps, 0, "separately disabled weight remains zero");
        assertEq(stratA.principal(), principalBefore, "guarded writeoff still rolls back principal");
        assertTrue(vault.pausedDeposit(), "separate deposit pause remains committed");
        assertTrue(vault.pausedRedeem(), "separate redeem pause remains committed");
        assertTrue(vault.pausedClaim(), "separate claim pause remains committed");
        assertTrue(vault.pausedAllocation(), "separate allocation pause remains committed");
    }

    function test_WriteoffStrategyPrincipal_RevertsWhenBackingGuardExceedsOne() public {
        vm.expectRevert(CollateralVault.InvalidBackingRatioGuard.selector);
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), 1, 1e18 + 1);
    }

    function test_WriteoffStrategyPrincipal_BlocksStrategyReentry() public {
        ReentrantWriteoffStrategy reentrant =
            new ReentrantWriteoffStrategy(address(underlying), ICollateralVault(address(vault)), 1e8);
        vault.addToWhitelist(address(reentrant));
        vault.addStrategy(IStrategy(address(reentrant)), 0, type(uint256).max);
        reentrant.setReenterOnWriteoff(true);
        vault.pauseAllocation();

        vm.expectRevert();
        vault.writeoffStrategyPrincipal(IStrategy(address(reentrant)), 1, 0);

        assertEq(reentrant.principal(), 1e8, "failed writeoff left principal unchanged");
    }

    function test_Initialize_GrantsWriteoffRoleToAdmin() public view {
        assertTrue(vault.hasRole(WRITEOFF_ROLE, admin), "admin has writeoff role");
    }

    function test_RemoveStrategy_RequiresZeroPrincipal() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.expectRevert(CollateralVault.StrategyHasPrincipal.selector);
        vault.removeStrategy(IStrategy(address(stratA)));
    }

    function test_RemoveStrategy_RevertsWhenPrincipalUnavailable() public {
        ConfigurableValuationStrategy stratC = new ConfigurableValuationStrategy(address(underlying));
        vault.addToWhitelist(address(stratC));
        vault.addStrategy(IStrategy(address(stratC)), 0, type(uint256).max);
        stratC.setRevertPrincipal(true);

        vm.expectRevert(CollateralVault.StrategyHasPrincipal.selector);
        vault.removeStrategy(IStrategy(address(stratC)));
    }

    function test_RemoveStrategy_SuccessAfterDrain() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyRemoved(address(stratA));
        vault.removeStrategy(IStrategy(address(stratA)));

        assertEq(vault.getStrategiesCount(), 1, "only stratB remains");
    }

    function test_PersistentCanaryCanSwapDrainedERC4626ForMorphoV2Candidate() public {
        vault.setBufferConfig(0, 0);
        _deposit(alice, 10e8);
        vault.allocate();
        assertGt(stratA.principal(), 0, "Gauntlet-like strategy funded");

        stratA.sendToVault(stratA.principal());
        assertEq(stratA.principal(), 0, "old strategy fully drained");
        assertEq(stratA.estimatedTotalUnderlying(), 0, "old strategy has no managed assets");
        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vault.removeStrategy(IStrategy(address(stratA)));

        MockStrategy morphoV2Candidate = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vault.addToWhitelist(address(morphoV2Candidate));
        vault.addStrategy(IStrategy(address(morphoV2Candidate)), 5000, type(uint256).max);
        _warpPast(vault.allocatorCooldown());
        vault.allocate();

        assertGt(morphoV2Candidate.principal(), 0, "Morpho V2 candidate funded in the same Vault");
        assertEq(vault.getStrategiesCount(), 2, "old strategy replaced without redeploying Vault");
    }

    function test_RemoveStrategy_SucceedsForLastStrategy() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.prank(admin);
        stratB.sendToVault(stratB.principal());
        vault.updateStrategy(IStrategy(address(stratB)), 0, type(uint256).max, false);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyRemoved(address(stratB));
        vault.removeStrategy(IStrategy(address(stratB)));

        assertEq(vault.getStrategiesCount(), 1, "only stratA remains");
        (IStrategy strategy, ICollateralVault.StrategyConfig memory config) =
            _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertEq(address(strategy), address(stratA), "stratA retained");
        assertTrue(config.enabled, "stratA still enabled");
    }

    function test_RemoveStrategy_RevertsWhenZeroPrincipalButAssetsRemain() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 yieldAmt = 1e7;
        underlying.mint(address(stratA), yieldAmt);
        stratA.setMockYield(yieldAmt);

        vm.prank(admin);
        stratA.sendToVault(stratA.principal());

        assertEq(stratA.principal(), 0, "principal drained");
        assertGt(stratA.estimatedTotalUnderlying(), 0, "recoverable assets remain");

        vm.expectRevert(CollateralVault.StrategyHasAssets.selector);
        vault.removeStrategy(IStrategy(address(stratA)));
    }

    function test_RemoveStrategy_RevertsWhenZeroPrincipalButValuationUnavailable() public {
        ConfigurableValuationStrategy stratC = new ConfigurableValuationStrategy(address(underlying));
        vault.addToWhitelist(address(stratC));
        vault.addStrategy(IStrategy(address(stratC)), 0, type(uint256).max);
        stratC.setRevertEstimated(true);

        vm.expectRevert(CollateralVault.StrategyHasAssets.selector);
        vault.removeStrategy(IStrategy(address(stratC)));
    }

    function test_RemoveStrategy_UnregisteredReverts() public {
        MockStrategy stratC = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vm.expectRevert(CollateralVault.StrategyNotFound.selector);
        vault.removeStrategy(IStrategy(address(stratC)));
    }

    function test_WriteoffOnDisabledStrategy_Succeeds() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);

        uint256 principalBefore = stratA.principal();
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), principalBefore, 0);

        assertEq(stratA.principal(), 0, "writeoff worked on disabled strategy");
    }

    function test_RemoveStrategyOnDisabled_Succeeds() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        vm.prank(admin);
        stratA.sendToVault(stratA.principal());

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyRemoved(address(stratA));
        vault.removeStrategy(IStrategy(address(stratA)));

        assertEq(vault.getStrategiesCount(), 1, "only stratB left");
    }

    // =================================================================
    //                  emergencyWithdraw (BaseStrategy)
    // =================================================================

    function test_EmergencyWithdraw_DestinationIsVault() public {
        uint256 stuck = 1e8;
        underlying.mint(address(stratA), stuck);
        uint256 vaultBefore = underlying.balanceOf(address(vault));

        vm.expectEmit(true, false, false, true, address(vault));
        emit ReceivedFromStrategy(address(stratA), stuck, stuck);
        vm.prank(admin); // owner of the strategy
        stratA.emergencyWithdraw(stuck);

        assertEq(underlying.balanceOf(address(vault)), vaultBefore + stuck, "vault received stuck balance");
        assertEq(underlying.balanceOf(address(stratA)), 0, "strategy drained");
    }

    function test_EmergencyWithdraw_ReducesVaultCacheForFallbackSolvency() public {
        (CollateralVault fVault, FailingMockStrategy fStrat) = _deployFailingSetup();

        uint256 amount = 10e8;
        underlying.mint(address(fVault), amount);
        fVault.setBufferConfig(0, 0);
        fVault.allocate();

        (uint256 cachedBefore, uint256 cachedAt, bool cacheInitializedBefore) =
            fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertTrue(cacheInitializedBefore, "cache initialized by allocation");
        assertEq(cachedBefore, amount, "cache starts at allocated value");
        assertEq(fVault.totalUnderlying(), amount, "strategy value counted before recovery");

        vm.prank(admin);
        fStrat.setValuationShouldFail(true);

        vm.expectEmit(true, false, false, true, address(fVault));
        emit StrategyValuationCacheInvalidated(address(fStrat), cachedBefore, cachedAt);
        vm.expectEmit(true, false, false, true, address(fVault));
        emit ReceivedFromStrategy(address(fStrat), amount, amount);
        vm.prank(admin);
        fStrat.emergencyWithdraw(amount);

        (uint256 cachedAfter,, bool cacheInitializedAfter) = fVault.strategyValuationCaches(IStrategy(address(fStrat)));
        assertFalse(cacheInitializedAfter, "exhausted historical estimate is invalidated");
        assertEq(cachedAfter, 0, "cache reduced by recovered amount");
        assertEq(underlying.balanceOf(address(fVault)), amount, "recovered funds are in vault buffer");
        assertEq(fVault.totalUnderlying(), amount, "fallback solvency view does not double count");
    }

    // =================================================================
    //                  reward token sweep (BaseStrategy)
    // =================================================================

    function test_SweepRewardToken_SendsNonUnderlyingToTreasury() public {
        MockERC20 reward = new MockERC20("Aave Reward", "AAVE", 18);
        uint256 amount = 100e18;
        reward.mint(address(stratA), amount);

        vm.expectEmit(true, true, false, true, address(stratA));
        emit RewardTokenSwept(address(reward), treasury, amount, amount);
        vm.prank(admin);
        uint256 swept = stratA.sweepRewardToken(IERC20(address(reward)), amount);

        assertEq(swept, amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(stratA)), 0, "strategy reward drained");
        assertEq(stratA.principal(), 0, "reward sweep does not touch principal");
    }

    function test_SweepRewardToken_UsesCurrentVaultTreasury() public {
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);
        address newTreasury = makeAddr("newTreasury");
        uint256 amount = 25e18;
        reward.mint(address(stratA), amount);
        vault.setTreasury(newTreasury);

        vm.prank(admin);
        uint256 swept = stratA.sweepRewardToken(IERC20(address(reward)), amount);

        assertEq(swept, amount, "reported new treasury receipt");
        assertEq(reward.balanceOf(newTreasury), amount, "new treasury received reward");
        assertEq(reward.balanceOf(treasury), 0, "old treasury untouched");
    }

    function test_SweepRewardToken_MaxAmountSweepsFullBalance() public {
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);
        uint256 amount = 42e18;
        reward.mint(address(stratA), amount);

        vm.expectEmit(true, true, false, true, address(stratA));
        emit RewardTokenSwept(address(reward), treasury, amount, amount);
        vm.prank(admin);
        uint256 swept = stratA.sweepRewardToken(IERC20(address(reward)), type(uint256).max);

        assertEq(swept, amount, "reported full balance receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received full balance");
        assertEq(reward.balanceOf(address(stratA)), 0, "strategy reward drained");
    }

    function test_SweepRewardToken_RejectsProtectedUnderlying() public {
        underlying.mint(address(stratA), 1e8);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        stratA.sweepRewardToken(IERC20(address(underlying)), 1e8);
    }

    function test_SweepRewardToken_RejectsVaultDToken() public {
        vm.prank(address(vault));
        dToken.mint(address(stratA), 1e18);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        stratA.sweepRewardToken(IERC20(address(dToken)), type(uint256).max);

        assertEq(dToken.balanceOf(address(stratA)), 1e18, "strategy keeps protected dToken");
        assertEq(dToken.balanceOf(treasury), 0, "treasury did not receive dToken");
    }

    function test_SweepRewardToken_RequiresOwner() public {
        MockERC20 reward = new MockERC20("Aave Reward", "AAVE", 18);
        reward.mint(address(stratA), 1e18);

        vm.expectRevert();
        vm.prank(alice);
        stratA.sweepRewardToken(IERC20(address(reward)), 1e18);
    }

    function test_SweepRewardToken_ZeroAmountIsNoOp() public {
        MockERC20 reward = new MockERC20("Aave Reward", "AAVE", 18);
        reward.mint(address(stratA), 1e18);

        vm.prank(admin);
        uint256 swept = stratA.sweepRewardToken(IERC20(address(reward)), 0);

        assertEq(swept, 0, "zero sweep returns zero");
        assertEq(reward.balanceOf(treasury), 0, "treasury untouched");
        assertEq(reward.balanceOf(address(stratA)), 1e18, "strategy balance untouched");
    }

    function test_SweepRewardToken_FeeOnTransferReportsTreasuryReceipt() public {
        FeeOnTransferToken reward = new FeeOnTransferToken("Fee Reward", "FRWD", 18);
        uint256 amount = 100e18;
        uint256 expectedReceived = amount - ((amount * reward.FEE_BPS()) / reward.BPS());
        reward.mint(address(stratA), amount);

        vm.expectEmit(true, true, false, true, address(stratA));
        emit RewardTokenSwept(address(reward), treasury, amount, expectedReceived);
        vm.prank(admin);
        uint256 swept = stratA.sweepRewardToken(IERC20(address(reward)), amount);

        assertEq(swept, expectedReceived, "reported net receipt");
        assertEq(reward.balanceOf(treasury), expectedReceived, "treasury received net reward");
    }

    function test_ClaimMerklRewards_ClaimsAsStrategyAndSweepsRewardToTreasury() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);
        uint256 amount = 25e18;
        reward.mint(address(distributor), amount);

        address[] memory tokens = new address[](1);
        tokens[0] = address(reward);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectEmit(true, true, false, true, address(stratA));
        emit RewardTokenSwept(address(reward), treasury, amount, amount);
        vm.expectEmit(true, true, false, true, address(stratA));
        emit MerklRewardsClaimed(address(distributor), address(reward), amount, amount);

        vm.prank(admin);
        uint256[] memory swept =
            stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(stratA), "strategy called Merkl");
        assertEq(distributor.lastUser(), address(stratA), "claim user is strategy");
        assertEq(swept[0], amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(stratA)), 0, "strategy reward drained");
    }

    function test_ClaimMerklRewards_PushesUnderlyingRewardToVault() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        uint256 amount = 1e8;
        underlying.mint(address(distributor), amount);
        uint256 bufferBefore = vault.bufferBalance();
        uint256 principalBefore = stratA.principal();

        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectEmit(true, true, false, true, address(stratA));
        emit MerklUnderlyingRewardsClaimed(address(distributor), address(underlying), amount, amount);
        vm.prank(admin);
        uint256[] memory sent =
            stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(stratA), "strategy called Merkl");
        assertEq(distributor.lastUser(), address(stratA), "claim user is strategy");
        assertEq(sent[0], amount, "reported vault receipt");
        assertEq(underlying.balanceOf(address(distributor)), 0, "distributor paid reward");
        assertEq(underlying.balanceOf(address(stratA)), 0, "strategy did not keep underlying idle");
        assertEq(vault.bufferBalance(), bufferBefore + amount, "underlying reward pushed to vault");
        assertEq(stratA.principal(), principalBefore, "principal unchanged");
    }

    function test_ClaimMerklRewards_RequiresOwnerAndValidLengths() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(reward);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](0);

        vm.expectRevert();
        vm.prank(alice);
        stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        vm.expectRevert(BaseStrategy.InvalidMerklClaim.selector);
        vm.prank(admin);
        stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);
    }

    function test_ClaimMerklRewards_RejectsDuplicateTokenBeforeDistributorCall() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(reward);
        tokens[1] = address(reward);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 2e18;
        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.DuplicateMerklToken.selector, address(reward)));
        vm.prank(admin);
        stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(0), "distributor was not called");
    }

    function test_ClaimMerklRewards_RejectsVaultDTokenBeforeDistributorCall() public {
        MockMerklDistributor distributor = new MockMerklDistributor();

        address[] memory tokens = new address[](1);
        tokens[0] = address(dToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        stratA.claimMerklRewards(IMerklDistributor(address(distributor)), tokens, amounts, proofs);

        assertEq(distributor.lastCaller(), address(0), "distributor was not called");
    }

    function test_ClaimMerklRewards_RejectsZeroAndNonContractDistributor() public {
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(reward);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        vm.prank(admin);
        stratA.claimMerklRewards(IMerklDistributor(address(0)), tokens, amounts, proofs);

        vm.expectRevert(BaseStrategy.InvalidMerklDistributor.selector);
        vm.prank(admin);
        stratA.claimMerklRewards(IMerklDistributor(alice), tokens, amounts, proofs);
    }

    // =================================================================
    //                  fee-on-transfer principal accounting
    // =================================================================

    /// @dev principal decrement uses `sent` (vault-received), not declared.
    function test_FeeOnTransferToken_PrincipalMatchesSent() public {
        (CollateralVault fotVault, MockStrategy fotStrat, FeeOnTransferToken fot) = _deployFeeOnTransferSetup();

        uint256 amount = 1e10;
        fot.mint(address(fotVault), amount);
        fotVault.setBufferConfig(0, 0);
        fotVault.allocate();

        uint256 principalBefore = fotStrat.principal();
        uint256 vaultBalBefore = fot.balanceOf(address(fotVault));

        vm.prank(admin);
        uint256 sent = fotStrat.sendToVault(principalBefore);

        uint256 actuallyReceived = fot.balanceOf(address(fotVault)) - vaultBalBefore;

        assertEq(sent, actuallyReceived, "returned sent matches vault credit");
        assertLt(sent, principalBefore, "fee took a bite out of the transfer");
        assertEq(fotStrat.principal(), principalBefore - sent, "principal decremented by sent, not declared");
    }

    function test_FeeOnTransferToken_InvalidatesCacheBeforeValuationOutage() public {
        (CollateralVault fotVault, FailingMockStrategy fotStrat, FeeOnTransferToken fot) =
            _deployFeeOnTransferFailingSetup();

        uint256 amount = 1e10;
        fot.mint(alice, amount);
        vm.startPrank(alice);
        fot.approve(address(fotVault), amount);
        fotVault.deposit(amount);
        vm.stopPrank();

        uint256 allocationFeeCushion = (amount * fot.FEE_BPS()) / fot.BPS();
        fot.mint(bob, allocationFeeCushion);
        vm.startPrank(bob);
        fot.approve(address(fotVault), allocationFeeCushion);
        fotVault.backstopDeposit(allocationFeeCushion);
        vm.stopPrank();

        fotVault.setBufferConfig(0, 0);
        fotVault.allocate();

        (uint256 cachedBefore,, bool initializedBefore) = fotVault.strategyValuationCaches(IStrategy(address(fotStrat)));
        assertTrue(initializedBefore, "allocation seeds cache");
        assertGt(cachedBefore, 0, "cache has strategy value");

        fotStrat.setWithdrawShouldFail(false);
        vm.prank(admin);
        uint256 sent = fotStrat.sendToVault(cachedBefore / 10);
        assertGt(sent, 0, "principal return reached vault");

        (uint256 cachedAfter,, bool initializedAfter) = fotVault.strategyValuationCaches(IStrategy(address(fotStrat)));
        assertEq(cachedAfter, 0, "ambiguous cache removed");
        assertFalse(initializedAfter, "fee mismatch invalidates cache");

        fotStrat.setValuationShouldFail(true);
        (, bool availableDuringOutage) = fotVault.backingRatioForPricing();
        assertFalse(availableDuringOutage, "pricing fails closed without ambiguous cache");

        fotStrat.setValuationShouldFail(false);
        (, bool availableAfterRecovery) = fotVault.backingRatioForPricing();
        assertTrue(availableAfterRecovery, "live valuation restores availability");
    }

    /// @dev allocation increments Strategy principal by the net Strategy receipt, not the gross Vault transfer.
    function test_FeeOnTransferToken_AllocationCreditsNetReceipt() public {
        (CollateralVault fotVault, MockStrategy fotStrat, FeeOnTransferToken fot) = _deployFeeOnTransferSetup();

        uint256 amount = 1e10;
        uint256 expectedReceived = amount - ((amount * fot.FEE_BPS()) / fot.BPS());
        fot.mint(address(fotVault), amount);
        fotVault.setBufferConfig(0, 0);

        vm.expectEmit(true, false, false, true, address(fotVault));
        emit StrategyAllocated(address(fotStrat), expectedReceived);
        fotVault.allocate();

        assertEq(fot.balanceOf(address(fotVault)), 0, "gross transfer leaves buffer");
        assertEq(fot.balanceOf(address(fotStrat)), expectedReceived, "strategy holds net receipt");
        assertEq(fotStrat.deposited(), expectedReceived, "deposited tracks net receipt");
        assertEq(fotStrat.principal(), expectedReceived, "principal tracks net receipt");
        assertEq(fotVault.totalUnderlying(), expectedReceived, "backing excludes burned transfer fee");
    }

    // =================================================================
    //                  receiveFromStrategy
    // =================================================================

    function test_ReceiveFromStrategy_OnlyFromRegistered() public {
        address attacker = makeAddr("attacker");
        vm.expectRevert(CollateralVault.NotRegisteredStrategy.selector);
        vm.prank(attacker);
        vault.receiveFromStrategy(1);
    }

    function test_ReceiveFromStrategy_DisabledButTracked_Accepts() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);

        uint256 principalBefore = stratA.principal();
        vm.prank(admin);
        uint256 sent = stratA.sendToVault(principalBefore);
        assertGt(sent, 0, "disabled-but-tracked strategy can push back");
    }

    function test_ReceiveFromStrategy_ZeroAmountFromRegistered() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit ReceivedFromStrategy(address(stratA), 0, 0);
        vm.prank(address(stratA));
        uint256 received = vault.receiveFromStrategy(0);
        assertEq(received, 0, "zero-declared returns zero");
    }

    // =================================================================
    //                  addStrategy / whitelist / updateStrategy
    // =================================================================

    function test_AddStrategy_RequiresWhitelist() public {
        MockStrategy stratC = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vm.expectRevert(CollateralVault.NotWhitelisted.selector);
        vault.addStrategy(IStrategy(address(stratC)), 0, type(uint256).max);
    }

    function test_AddStrategy_RequiresWeightBpsBound() public {
        // stratA + stratB already at 5000 each => totalWeightBps == 10000.
        MockStrategy stratC = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vault.addToWhitelist(address(stratC));
        vm.expectRevert(CollateralVault.WeightExceedsBps.selector);
        vault.addStrategy(IStrategy(address(stratC)), 1, type(uint256).max);
    }

    function test_AddStrategy_RevertsForDisabledButRegisteredStrategy() public {
        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);

        vm.expectRevert(CollateralVault.StrategyAlreadyExists.selector);
        vault.addStrategy(IStrategy(address(stratA)), 5000, type(uint256).max);
    }

    function test_AddStrategy_ZeroAddressReverts() public {
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.addStrategy(IStrategy(address(0)), 0, type(uint256).max);
    }

    function test_AddStrategy_RevertsOnEOA() public {
        vm.expectRevert(CollateralVault.NotContract.selector);
        vault.addStrategy(IStrategy(makeAddr("notStrategy")), 0, type(uint256).max);
    }

    function test_AddStrategy_RevertsAtMaxStrategyCount() public {
        uint256 maxStrategies = vault.MAX_STRATEGIES();
        assertEq(vault.getStrategiesCount(), 2, "setup strategy count");

        for (uint256 i = vault.getStrategiesCount(); i < maxStrategies; i++) {
            MockStrategy strategy = _deployMockStrategyFor(vault, IERC20(address(underlying)));
            vault.addToWhitelist(address(strategy));
            vault.addStrategy(IStrategy(address(strategy)), 0, type(uint256).max);
        }

        assertEq(vault.getStrategiesCount(), maxStrategies, "max strategy count reached");

        MockStrategy overflowStrategy = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vault.addToWhitelist(address(overflowStrategy));
        vm.expectRevert(CollateralVault.TooManyStrategies.selector);
        vault.addStrategy(IStrategy(address(overflowStrategy)), 0, type(uint256).max);

        vm.expectRevert(CollateralVault.TooManyStrategies.selector);
        vault.addStrategy(IStrategy(address(overflowStrategy)), 1, type(uint256).max);
    }

    function test_UpdateStrategy_DisableWithNonZeroWeight_Reverts() public {
        vm.expectRevert(CollateralVault.InvalidWeight.selector);
        vault.updateStrategy(IStrategy(address(stratA)), 100, type(uint256).max, false);
    }

    function test_UpdateStrategy_RevertsForUnregisteredStrategy() public {
        MockStrategy stratC = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        vault.addToWhitelist(address(stratC));

        vm.expectRevert(CollateralVault.StrategyNotFound.selector);
        vault.updateStrategy(IStrategy(address(stratC)), 5000, type(uint256).max, true);

        assertEq(vault.totalWeightBps(), 10_000, "total weight unchanged");
        assertEq(vault.getStrategiesCount(), 2, "strategy list unchanged");
    }

    function test_UpdateStrategy_ReEnableAfterDisable() public {
        vault.updateStrategy(IStrategy(address(stratA)), 0, type(uint256).max, false);
        (, ICollateralVault.StrategyConfig memory cfgDisabled) =
            _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertFalse(cfgDisabled.enabled, "disabled");

        vault.updateStrategy(IStrategy(address(stratA)), 5000, type(uint256).max, true);
        (, ICollateralVault.StrategyConfig memory cfgEnabled) =
            _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertTrue(cfgEnabled.enabled, "re-enabled");
        assertEq(cfgEnabled.weightBps, 5000, "weight restored");
    }

    function test_EmergencyDisableStrategy_ZeroesWeightPausesAllocationWithoutChangingBacking() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 totalBefore = vault.totalUnderlying();
        uint256 ratioBefore = vault.backingRatio();

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyUpdated(address(stratA), 0, type(uint256).max, false);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyEmergencyDisabled(address(stratA), 5000);
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit RedeemPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit ClaimPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocationPaused();
        vault.emergencyDisableStrategy(IStrategy(address(stratA)));

        (, ICollateralVault.StrategyConfig memory cfg) = _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertFalse(cfg.enabled, "strategy disabled");
        assertEq(cfg.weightBps, 0, "weight zeroed");
        assertEq(cfg.cap, type(uint256).max, "cap unchanged");
        assertEq(vault.totalWeightBps(), 5000, "total weight reduced");
        assertTrue(vault.pausedAllocation(), "allocation paused");
        assertTrue(vault.pausedDeposit(), "deposit paused");
        assertTrue(vault.pausedRedeem(), "redeem paused");
        assertTrue(vault.pausedClaim(), "claim paused");
        assertEq(vault.totalUnderlying(), totalBefore, "backing assets unchanged");
        assertEq(vault.backingRatio(), ratioBefore, "backing ratio unchanged");

        vm.expectRevert(CollateralVault.Paused.selector);
        vault.allocate();
        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.deposit(1e8);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.redeem(1e18, alice);

        uint256 principalBefore = stratA.principal();
        vm.prank(admin);
        uint256 sent = stratA.sendToVault(principalBefore);
        assertGt(sent, 0, "strategy recovery remains available");
        assertEq(vault.totalUnderlying(), totalBefore, "recovery preserves accounted backing");
    }

    function test_EmergencyDisableStrategy_RevertsForUnregisteredStrategy() public {
        MockStrategy stratC = _deployMockStrategyFor(vault, IERC20(address(underlying)));

        vm.expectRevert(CollateralVault.StrategyNotFound.selector);
        vault.emergencyDisableStrategy(IStrategy(address(stratC)));
    }

    function test_Whitelist_AddRemove() public {
        MockStrategy candidate = _deployMockStrategyFor(vault, IERC20(address(underlying)));
        address candidateAddress = address(candidate);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyWhitelisted(candidateAddress);
        vault.addToWhitelist(candidateAddress);

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyRemovedFromWhitelist(candidateAddress);
        vault.removeFromWhitelist(candidateAddress);

        assertFalse(vault.pausedAllocation(), "unused whitelist removal does not pause allocation");
        assertFalse(vault.pausedDeposit(), "unused whitelist removal does not pause deposits");
        assertFalse(vault.pausedRedeem(), "unused whitelist removal does not pause redemptions");
        assertFalse(vault.pausedClaim(), "unused whitelist removal does not pause claims");
    }

    function test_Whitelist_RemoveRegisteredStrategyDisablesPausesAndBlocksFutureAllocation() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 stratAPrincipalBefore = stratA.principal();
        uint256 stratBPrincipalBefore = stratB.principal();
        assertGt(stratAPrincipalBefore, 0, "stratA initially funded");
        assertGt(stratBPrincipalBefore, 0, "stratB initially funded");

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyRemovedFromWhitelist(address(stratA));
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyUpdated(address(stratA), 0, type(uint256).max, false);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyEmergencyDisabled(address(stratA), 5000);
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit RedeemPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit ClaimPaused();
        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocationPaused();
        vault.removeFromWhitelist(address(stratA));

        (IStrategy strategy, ICollateralVault.StrategyConfig memory cfg) =
            _lens().getStrategyAt(ICollateralVault(address(vault)), 0);
        assertEq(address(strategy), address(stratA), "stratA remains registered for recovery");
        assertFalse(cfg.enabled, "stratA disabled");
        assertEq(cfg.weightBps, 0, "stratA weight zeroed");
        assertEq(vault.totalWeightBps(), 5000, "total weight reduced");
        assertTrue(vault.pausedAllocation(), "allocation paused");
        assertTrue(vault.pausedDeposit(), "deposit paused");
        assertTrue(vault.pausedRedeem(), "redeem paused");
        assertTrue(vault.pausedClaim(), "claim paused");

        vm.expectRevert(CollateralVault.Paused.selector);
        vault.allocate();

        vault.unpauseDeposit();
        vault.unpauseRedeem();
        vault.unpauseClaim();
        vault.unpauseAllocation();

        _deposit(alice, 10e8);
        vault.allocate();

        assertEq(stratA.principal(), stratAPrincipalBefore, "removed strategy not allocated again");
        assertGt(stratB.principal(), stratBPrincipalBefore, "remaining enabled strategy receives allocation");
    }

    function test_Whitelist_RevertsOnEOA() public {
        vm.expectRevert(CollateralVault.NotContract.selector);
        vault.addToWhitelist(makeAddr("notStrategy"));
    }

    function test_Whitelist_DoubleAddReverts() public {
        vm.expectRevert(CollateralVault.AlreadyWhitelisted.selector);
        vault.addToWhitelist(address(stratA));
    }

    function test_Whitelist_RemoveUnregisteredReverts() public {
        address random = makeAddr("random");
        vm.expectRevert(CollateralVault.StrategyNotFound.selector);
        vault.removeFromWhitelist(random);
    }

    // =================================================================
    //                  pause
    // =================================================================

    function test_PausedAllocation_BlocksOutboundVaultFlows_ButNotRecovery() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vault.pauseAllocation();

        vm.expectRevert(CollateralVault.Paused.selector);
        vault.allocate();

        // sendToVault is on the strategy side; pauseAllocation must not block it.
        uint256 principalBefore = stratA.principal();
        vm.prank(admin);
        uint256 sent = stratA.sendToVault(principalBefore);
        assertGt(sent, 0, "sendToVault not blocked by pauseAllocation");

        // transferYieldToTreasury is a Vault outbound flow and is blocked.
        vm.prank(admin);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.transferYieldToTreasury();
    }

    function test_PauseDepositRedeem_BlocksIndependently_NotClaim() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        // Create a pending request, then refill the buffer so claim CAN succeed.
        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);
        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());

        vault.pauseDeposit();
        vault.pauseRedeem();

        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.deposit(1e8);
        vm.stopPrank();

        vm.expectRevert(CollateralVault.Paused.selector);
        vm.prank(alice);
        vault.redeem(1, alice);

        // claim is not blocked by deposit/redeem pause.
        _warpPast(vault.withdrawDelay());
        vm.prank(alice);
        uint256 claimed = vault.claim(reqId);
        assertEq(claimed, 10e8, "claim still works while deposit/redeem paused");
    }

    function test_PauseClaim_BlocksOnlyClaimUntilGovUnpauses() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);
        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());
        _warpPast(vault.withdrawDelay());

        vault.pauseClaim();
        assertTrue(vault.pausedClaim(), "claim paused");

        vm.prank(alice);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.claim(reqId);

        vault.unpauseClaim();
        vm.prank(alice);
        assertEq(vault.claim(reqId), 10e8, "claim resumes after GOV unpause");
    }

    // =================================================================
    //                  redeem / claim round trips (push model)
    // =================================================================

    function test_Redeem_WithBufferShortfall_CreatesRequest() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);

        vault.setBufferConfig(0, 0); // push everything to strategies
        vault.allocate();
        assertEq(underlying.balanceOf(address(vault)), 0, "buffer empty");

        uint256 dTokens = dToken.balanceOf(alice);
        uint256 claimableAt = block.timestamp + vault.withdrawDelay();

        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawRequested(alice, alice, 1, amount, claimableAt);

        vm.prank(alice);
        (uint256 received, uint256 reqId) = vault.redeem(dTokens, alice);

        assertEq(received, 0, "no immediate payout");
        assertEq(reqId, 1, "first requestId is 1");
        assertEq(vault.pendingWithdrawals(), amount, "pendingWithdrawals tracked");
    }

    function test_Claim_AfterDelay_Succeeds() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);

        // Drain strategies back to buffer so claim can pay out.
        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());

        _warpPast(vault.withdrawDelay());

        vm.expectEmit(true, false, false, true, address(vault));
        emit WithdrawClaimed(alice, reqId, amount);

        vm.prank(alice);
        uint256 claimed = vault.claim(reqId);

        assertEq(claimed, amount, "claimed full amount");
        assertEq(vault.pendingWithdrawals(), 0, "pendingWithdrawals cleared");
        assertEq(underlying.balanceOf(alice), amount, "alice paid");
    }

    function test_Claim_BeforeDelay_Reverts() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);

        vm.expectRevert(CollateralVault.RequestNotReady.selector);
        vm.prank(alice);
        vault.claim(reqId);
    }

    function test_Claim_CEIOrder_BufferCheckFirst() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);

        _warpPast(vault.withdrawDelay());

        // Buffer empty; claim reverts without mutating the request.
        vm.expectRevert(CollateralVault.InsufficientBuffer.selector);
        vm.prank(alice);
        vault.claim(reqId);

        // Refill and retry.
        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());

        vm.prank(alice);
        uint256 claimed = vault.claim(reqId);
        assertEq(claimed, 10e8, "retry succeeded after buffer refill");
    }

    function test_DepositRedeemRoundTrip() public {
        uint256 amount = 10e8;
        _deposit(alice, amount);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 aliceDTokens = dToken.balanceOf(alice);
        vm.prank(alice);
        (, uint256 reqId) = vault.redeem(aliceDTokens, alice);

        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());

        _warpPast(vault.withdrawDelay());
        vm.prank(alice);
        uint256 claimed = vault.claim(reqId);

        assertEq(claimed, amount, "round-trip claimed");
        assertEq(underlying.balanceOf(alice), amount, "alice got all underlying back");
    }

    function test_MultiplePendingRequests_SameUser_OrderedClaim() public {
        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        uint256 dHalf = dToken.balanceOf(alice) / 2;
        vm.prank(alice);
        (, uint256 reqId1) = vault.redeem(dHalf, alice);
        vm.prank(alice);
        (, uint256 reqId2) = vault.redeem(dHalf, alice);

        assertEq(reqId1, 1, "first requestId");
        assertEq(reqId2, 2, "second requestId");

        vm.prank(admin);
        stratA.sendToVault(stratA.principal());
        vm.prank(admin);
        stratB.sendToVault(stratB.principal());

        _warpPast(vault.withdrawDelay());

        vm.prank(alice);
        uint256 c1 = vault.claim(reqId1);
        vm.prank(alice);
        uint256 c2 = vault.claim(reqId2);

        assertEq(c1 + c2, 10e8, "total claimed equals deposit");
        assertEq(vault.pendingWithdrawals(), 0, "all requests cleared");
    }

    // =================================================================
    //                  roles / config / views / upgrade
    // =================================================================

    function test_RoleManagement_GrantRevoke() public {
        address candidate = makeAddr("candidate");
        vault.grantRole(ALLOCATOR_ROLE, candidate);
        assertTrue(vault.hasRole(ALLOCATOR_ROLE, candidate), "granted");
        vault.revokeRole(ALLOCATOR_ROLE, candidate);
        assertFalse(vault.hasRole(ALLOCATOR_ROLE, candidate), "revoked");
    }

    function test_RoleSeparation_GuardianCanOnlyPause() public {
        address guardian = makeAddr("guardianOnly");
        vault.grantRole(GUARDIAN_ROLE, guardian);

        vm.prank(guardian);
        vault.pauseAllocation();
        assertTrue(vault.pausedAllocation(), "allocation paused");

        vm.prank(guardian);
        vm.expectRevert(); // missing GOV_ROLE
        vault.unpauseAllocation();

        vm.prank(guardian);
        vm.expectRevert(); // missing GOV_ROLE
        vault.setAllocatorConfig(1, 1);

        vm.prank(guardian);
        vm.expectRevert(); // missing ALLOCATOR_ROLE
        vault.allocate();

        vm.prank(guardian);
        vault.pauseDeposit();
        vault.pauseRedeem();
        vault.pauseClaim();
        assertTrue(vault.pausedDeposit(), "deposit paused");
        assertTrue(vault.pausedRedeem(), "redeem paused");
        assertTrue(vault.pausedClaim(), "claim paused");

        vm.prank(guardian);
        vm.expectRevert(); // missing GOV_ROLE
        vault.unpauseDeposit();
    }

    function test_RoleSeparation_AllocatorCannotGovernPauseOrGrantRoles() public {
        address allocator = makeAddr("allocatorOnly");
        address candidate = makeAddr("candidate");
        bytes32 guardianRole = GUARDIAN_ROLE;
        vault.grantRole(ALLOCATOR_ROLE, allocator);

        vm.prank(allocator);
        vm.expectRevert(); // missing GUARDIAN_ROLE
        vault.pauseAllocation();

        vm.prank(allocator);
        vm.expectRevert(); // missing GOV_ROLE
        vault.setTreasury(makeAddr("newTreasury"));

        vm.prank(allocator);
        vm.expectRevert(); // missing DEFAULT_ADMIN_ROLE
        vault.grantRole(guardianRole, candidate);
    }

    function test_RoleSeparation_GovWithoutDefaultAdminCannotGrantRoles() public {
        address govOnly = makeAddr("govOnly");
        address candidate = makeAddr("candidate");
        bytes32 allocatorRole = ALLOCATOR_ROLE;
        vault.grantRole(GOV_ROLE, govOnly);

        vm.prank(govOnly);
        vault.setAllocatorConfig(123, 456);

        vm.prank(govOnly);
        vm.expectRevert(); // missing DEFAULT_ADMIN_ROLE
        vault.grantRole(allocatorRole, candidate);
    }

    function test_RoleSeparation_GovCannotWriteoffWithoutWriteoffRole() public {
        address govOnly = makeAddr("govOnly");
        vault.grantRole(GOV_ROLE, govOnly);

        _deposit(alice, 10e8);
        vault.setBufferConfig(0, 0);
        vault.allocate();

        vm.prank(govOnly);
        vm.expectRevert(); // missing WRITEOFF_ROLE
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), 1, 0);
    }

    function test_ConfigSetters_RevertAndStateUpdate() public {
        vm.expectRevert(CollateralVault.InvalidBufferConfig.selector);
        vault.setBufferConfig(10001, 0);

        vm.expectEmit(false, false, false, true, address(vault));
        emit WithdrawDelayUpdated(1 days, 3 days);
        vault.setWithdrawDelay(3 days);
        assertEq(vault.withdrawDelay(), 3 days, "delay updated");

        vm.expectEmit(false, false, false, true, address(vault));
        emit AllocatorConfigUpdated(type(uint256).max, 123, 0, 456);
        vault.setAllocatorConfig(123, 456);
        assertEq(vault.allocateMaxMove(), 123, "max move updated");
        assertEq(vault.allocatorCooldown(), 456, "cooldown updated");

        vm.expectEmit(false, false, false, true, address(vault));
        emit StrategyValuationMaxAgeUpdated(1 days, 31 days);
        vault.setStrategyValuationMaxAge(31 days);
        assertEq(vault.strategyValuationMaxAge(), 31 days, "large valuation max age updated");

        vm.expectEmit(false, false, false, true, address(vault));
        emit StrategyValuationMaxAgeUpdated(31 days, 2 hours);
        vault.setStrategyValuationMaxAge(2 hours);
        assertEq(vault.strategyValuationMaxAge(), 2 hours, "valuation max age updated");

        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.setTreasury(address(0));
    }

    function test_GetStrategyAt_OutOfBoundsReverts() public {
        uint256 count = vault.getStrategiesCount();
        CollateralVaultLens lens = _lens();
        vm.expectRevert(CollateralVaultLens.StrategyNotFound.selector);
        lens.getStrategyAt(ICollateralVault(address(vault)), count);
    }

    function test_GetAllStrategies_ReturnsCorrectShape() public {
        (IStrategy[] memory strats, ICollateralVault.StrategyConfig[] memory cfgs, uint256[] memory balances) =
            _lens().getAllStrategies(ICollateralVault(address(vault)));

        assertEq(strats.length, 2, "two strategies");
        assertEq(cfgs.length, 2, "two configs");
        assertEq(balances.length, 2, "two balances");
        assertTrue(cfgs[0].enabled, "stratA enabled");
        assertTrue(cfgs[1].enabled, "stratB enabled");
        assertEq(cfgs[0].weightBps, 5000, "stratA weight");
        assertEq(cfgs[1].weightBps, 5000, "stratB weight");
    }

    function test_GetAllStrategies_FailSoftWhenEstimateReverts() public {
        ConfigurableValuationStrategy flaky = new ConfigurableValuationStrategy(address(underlying));
        flaky.setEstimatedValue(123e8);

        vault.addToWhitelist(address(flaky));
        vault.addStrategy(IStrategy(address(flaky)), 0, type(uint256).max);

        (,, uint256[] memory balancesBefore) = _lens().getAllStrategies(ICollateralVault(address(vault)));
        assertEq(balancesBefore.length, 3, "three balances");
        assertEq(balancesBefore[2], 123e8, "raw estimate returned while readable");

        flaky.setRevertEstimated(true);

        (IStrategy[] memory strats, ICollateralVault.StrategyConfig[] memory cfgs, uint256[] memory balancesAfter) =
            _lens().getAllStrategies(ICollateralVault(address(vault)));

        assertEq(strats.length, 3, "three strategies");
        assertEq(address(strats[2]), address(flaky), "flaky strategy returned");
        assertTrue(cfgs[2].enabled, "zero-weight strategy remains enabled");
        assertEq(cfgs[2].weightBps, 0, "zero weight");
        assertEq(balancesAfter[2], 0, "unreadable estimate is reported as zero");
    }

    function test_ForceDeallocateMorphoV2_ReducesFallbackCacheByTrackedLossAndRecovery() public {
        ConfigurableValuationStrategy incident = new ConfigurableValuationStrategy(address(underlying));
        incident.setEstimatedValue(100e8);
        incident.setPrincipalValue(100e8);
        incident.setForceDeallocateResult(9e8, 9e8, 2e8);
        underlying.mint(address(incident), 10e8);

        vault.addToWhitelist(address(incident));
        vault.addStrategy(IStrategy(address(incident)), 0, type(uint256).max);

        (uint256 cachedBefore,, bool initializedBefore) = vault.strategyValuationCaches(IStrategy(address(incident)));
        assertTrue(initializedBefore, "registration initializes the cache");
        assertEq(cachedBefore, 100e8, "pre-incident cache");

        (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets) =
            vault.forceDeallocateMorphoV2(IStrategy(address(incident)), makeAddr("adapter"), "", 10e8, 10e8, 0);

        assertEq(penaltyShares, 9e8, "total penalty shares reported");
        assertEq(penaltyAssets, 9e8, "total venue penalty reported");
        assertEq(valuationLossAssets, 2e8, "tracked loss reported separately");
        (uint256 cachedAfter,, bool initializedAfter) = vault.strategyValuationCaches(IStrategy(address(incident)));
        assertTrue(initializedAfter, "fallback cache remains initialized");
        assertEq(cachedAfter, 88e8, "cache excludes loss and recovered assets");
        assertEq(vault.bufferBalance(), 10e8);
    }

    function test_GuardianL05_ActualReceiptOverridesReportedWithdrawal() public {
        ConfigurableValuationStrategy incident = new ConfigurableValuationStrategy(address(underlying));
        incident.setEstimatedValue(100e8);
        incident.setPrincipalValue(100e8);
        incident.setForceReceipt(1e8);
        underlying.mint(address(incident), 10e8);
        vault.addToWhitelist(address(incident));
        vault.addStrategy(incident, 0, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(CollateralVault.RecoveryBelowMinimum.selector, 1e8, 10e8));
        vault.forceDeallocateMorphoV2(incident, makeAddr("adapter"), "", 10e8, 10e8, 0);
        assertEq(vault.bufferBalance(), 0);
        assertEq(underlying.balanceOf(address(incident)), 10e8);

        vault.forceDeallocateMorphoV2(incident, makeAddr("adapter"), "", 10e8, 1e8, 0);
        assertEq(vault.bufferBalance(), 1e8);
        (,, bool initialized) = vault.strategyValuationCaches(incident);
        assertFalse(initialized, "receipt mismatch cannot preserve unknown backing");
    }

    function test_GetStrategyStatuses_ReturnsAllocationAndEstimatedPnL() public {
        uint256 amount = 10e8;
        uint256 yieldAmt = 1e7;

        vault.setBufferConfig(0, 0);
        _deposit(alice, amount);
        vault.allocate();

        underlying.mint(address(stratA), yieldAmt);
        stratA.setMockYield(yieldAmt);

        ICollateralVault.StrategyStatus[] memory statuses =
            _lens().getStrategyStatuses(ICollateralVault(address(vault)));
        ICollateralVault.StrategyStatus memory status = statuses[0];
        uint256 expectedPrincipal = amount / 2;

        assertEq(statuses.length, 2, "two strategy snapshots");
        assertEq(address(status.strategy), address(stratA), "stratA snapshot");
        assertTrue(status.config.enabled, "enabled");
        assertEq(status.config.weightBps, 5000, "weight");
        assertTrue(status.estimateAvailable, "estimate available");
        assertTrue(status.principalAvailable, "principal available");
        assertEq(status.estimatedUnderlying, expectedPrincipal + yieldAmt, "estimated total");
        assertEq(status.principal, expectedPrincipal, "principal");
        assertEq(status.conservativeValue, expectedPrincipal, "conservative value");
        assertEq(status.estimatedGain, yieldAmt, "estimated gain");
        assertEq(status.estimatedLoss, 0, "no estimated loss");
        assertEq(status.capRemaining, type(uint256).max - expectedPrincipal - yieldAmt, "cap remaining");
    }

    function test_UpgradeAuthorization_RequiresGov() public {
        CollateralVault newImpl = new CollateralVault();

        address noRole = makeAddr("noRole");
        vm.expectRevert(); // AccessControl: missing role
        vm.prank(noRole);
        UUPSUpgradeable(address(vault)).upgradeTo(address(newImpl));

        UUPSUpgradeable(address(vault)).upgradeTo(address(newImpl)); // GOV (admin) can upgrade
    }

    // =================================================================
    //                  BaseStrategy edge cases
    // =================================================================

    function test_BaseStrategy_Deposit_ZeroAmountShortCircuits() public {
        uint256 principalBefore = stratA.principal();
        vm.prank(address(vault)); // deposit is onlyVault
        stratA.deposit(0, 0);
        assertEq(stratA.principal(), principalBefore, "principal unchanged for deposit(0)");
    }

    function test_BaseStrategy_Deposit_NonzeroDeclaredWithZeroReceiptFailsClosed() public {
        vm.expectRevert(BaseStrategy.DepositRecoveryFailed.selector);
        vm.prank(address(vault));
        stratA.deposit(1, 0);
    }

    function test_BaseStrategy_DeployUnderlyingIsSelfOnly() public {
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        stratA.deployUnderlying(1);
    }

    function test_BaseStrategy_SendToVault_ZeroAmountReturnsZero() public {
        _deposit(alice, 10e8);
        vault.allocate();
        uint256 principalBefore = stratA.principal();

        vm.prank(admin);
        uint256 sent = stratA.sendToVault(0);

        assertEq(sent, 0, "zero-amount push returns zero");
        assertEq(stratA.principal(), principalBefore, "principal unchanged");
    }

    function test_BaseStrategy_SendProfitToVault_ZeroYieldReturnsZero() public {
        _deposit(alice, 10e8);
        vault.allocate();
        uint256 principalBefore = stratA.principal();
        uint256 bufferBefore = vault.bufferBalance();

        vm.prank(admin);
        uint256 sent = stratA.sendProfitToVault();

        assertEq(sent, 0, "no yield -> sent is zero");
        assertEq(stratA.principal(), principalBefore, "principal unchanged");
        assertEq(vault.bufferBalance(), bufferBefore, "buffer unchanged");
    }

    function test_BaseStrategy_WriteoffPrincipal_ClampsAtPrincipal() public {
        _deposit(alice, 10e8);
        vault.allocate();
        vault.pauseAllocation();
        uint256 principalBefore = stratA.principal();

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyPrincipalWrittenOff(address(stratA), principalBefore);
        vault.writeoffStrategyPrincipal(IStrategy(address(stratA)), principalBefore * 100, 0);
        assertEq(stratA.principal(), 0, "principal clamped to zero, no underflow");
    }

    function test_BaseStrategy_EmergencyWithdraw_ZeroAmountIsNoOp() public {
        uint256 vaultBefore = underlying.balanceOf(address(vault));
        vm.prank(admin);
        stratA.emergencyWithdraw(0);
        assertEq(underlying.balanceOf(address(vault)), vaultBefore, "no balance change");
    }

    // =================================================================
    //                  fresh-setup helpers
    // =================================================================

    function _deployFeeOnTransferSetup()
        internal
        returns (CollateralVault vault_, MockStrategy strat_, FeeOnTransferToken fot_)
    {
        fot_ = new FeeOnTransferToken("FoT WBTC", "FoT", 8);

        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        DToken d_ = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        d_.setAllowedUnderlying(address(fot_), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(fot_)), IDToken(address(d_)), treasury, admin
        );
        vault_ = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        d_.setTokenInfo("dFoT", "dFoT", IERC20MetadataUpgradeable(address(fot_)));
        activateDTokenForTest(d_);

        strat_ = _deployMockStrategyFor(vault_, IERC20(address(fot_)));
        vault_.addToWhitelist(address(strat_));
        vault_.addStrategy(IStrategy(address(strat_)), 10000, type(uint256).max);
    }

    function _deployFeeOnTransferFailingSetup()
        internal
        returns (CollateralVault vault_, FailingMockStrategy strat_, FeeOnTransferToken fot_)
    {
        fot_ = new FeeOnTransferToken("FoT WBTC", "FoT", 8);

        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        DToken d_ = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        d_.setAllowedUnderlying(address(fot_), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(fot_)), IDToken(address(d_)), treasury, admin
        );
        vault_ = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        d_.setTokenInfo("dFoT", "dFoT", IERC20MetadataUpgradeable(address(fot_)));
        activateDTokenForTest(d_);

        FailingMockStrategy impl = new FailingMockStrategy();
        bytes memory sInit = abi.encodeWithSelector(
            FailingMockStrategy.initialize.selector, address(vault_), IERC20(address(fot_)), admin
        );
        strat_ = FailingMockStrategy(address(new ERC1967Proxy(address(impl), sInit)));
        vault_.addToWhitelist(address(strat_));
        vault_.addStrategy(IStrategy(address(strat_)), 10000, type(uint256).max);
    }

    function _deployMockStrategySetupFor(IERC20MetadataUpgradeable token)
        internal
        returns (CollateralVault vault_, MockStrategy strategy_)
    {
        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        DToken d_ = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        d_.setAllowedUnderlying(address(token), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(token)), IDToken(address(d_)), treasury, admin
        );
        vault_ = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        d_.setTokenInfo("dMock", "dMock", token);
        activateDTokenForTest(d_);

        strategy_ = _deployMockStrategyFor(vault_, IERC20(address(token)));
        vault_.addToWhitelist(address(strategy_));
        vault_.addStrategy(IStrategy(address(strategy_)), 10_000, type(uint256).max);
    }

    function _deployFailingSetup() internal returns (CollateralVault vault_, FailingMockStrategy strat_) {
        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        DToken d_ = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        d_.setAllowedUnderlying(address(underlying), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(underlying)), IDToken(address(d_)), treasury, admin
        );
        vault_ = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        d_.setTokenInfo("dFail", "dFail", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(d_);

        FailingMockStrategy impl = new FailingMockStrategy();
        bytes memory sInit = abi.encodeWithSelector(
            FailingMockStrategy.initialize.selector, address(vault_), IERC20(address(underlying)), admin
        );
        strat_ = FailingMockStrategy(address(new ERC1967Proxy(address(impl), sInit)));
        vault_.addToWhitelist(address(strat_));
        vault_.addStrategy(IStrategy(address(strat_)), 10000, type(uint256).max);
    }
}
