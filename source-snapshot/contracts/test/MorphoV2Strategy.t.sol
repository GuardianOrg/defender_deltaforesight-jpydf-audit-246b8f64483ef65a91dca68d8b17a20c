// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "../src/Strategies/MorphoV2Strategy.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/IStrategy.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockMorphoV2Vault.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract ZeroShareMorphoV2Vault is MockMorphoV2Vault {
    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function deposit(uint256 assets, address receiver) public pure override returns (uint256) {
        assets;
        receiver;
        return 0;
    }
}

contract LyingDepositMorphoV2Vault is MockMorphoV2Vault {
    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        return super.deposit(assets, receiver) + 1;
    }
}

contract LyingWithdrawMorphoV2Vault is MockMorphoV2Vault {
    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        return super.withdraw(assets, receiver, owner) + 1;
    }
}

contract ZeroBurnWithdrawMorphoV2Vault is MockMorphoV2Vault {
    using SafeERC20 for IERC20;

    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        owner;
        IERC20(asset()).safeTransfer(receiver, assets);
        return 0;
    }
}

contract ZeroAssetRedeemMorphoV2Vault is MockMorphoV2Vault {
    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function redeem(uint256 shares, address, address owner) public override returns (uint256 assets) {
        assets = previewRedeem(shares);
        _burn(owner, shares);
    }
}

/// @notice Attempts to reenter the Strategy during the venue deposit/withdraw
///         call and records whether the reentrancy was blocked.
contract ReenteringMorphoV2Vault is MockMorphoV2Vault {
    MorphoV2Strategy public strategy;
    bool public reenterOnDeposit;
    bool public reenterOnWithdraw;
    bool public reentrancyBlocked;
    bool public reentrancySucceeded;
    bool public vaultReentrancyBlocked;

    constructor(IERC20 asset_) MockMorphoV2Vault(asset_) {}

    function setStrategy(MorphoV2Strategy _strategy) external {
        strategy = _strategy;
    }

    function setReenterOnDeposit(bool _reenter) external {
        reenterOnDeposit = _reenter;
    }

    function setReenterOnWithdraw(bool _reenter) external {
        reenterOnWithdraw = _reenter;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (reenterOnDeposit) _attemptReentry();
        return super.deposit(assets, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        if (reenterOnWithdraw) _attemptReentry();
        return super.withdraw(assets, receiver, owner);
    }

    function _attemptReentry() internal {
        (bool success, bytes memory result) =
            strategy.vault().call(abi.encodeCall(CollateralVault.receiveFromStrategy, (0)));
        vaultReentrancyBlocked = !success
            && keccak256(result) == keccak256(abi.encodeWithSignature("Error(string)", "ReentrancyGuard: reentrant call"));
        try strategy.sendToVault(1) returns (uint256) {
            reentrancySucceeded = true;
        } catch (bytes memory reason) {
            // Only count the reentrancy guard itself, not a role/other revert.
            reentrancyBlocked = reason.length == 4 && bytes4(reason) == BaseStrategy.ReentrantCall.selector;
        }
    }
}

/// @title MorphoV2StrategyTest - Morpho Vaults V2 strategy coverage.
/// @notice Covers the adapter for Morpho Vaults V2 venues: hard-zero max*
///         views, deposit rejection recovery, fail-soft liquidity-short
///         withdrawals, bounded forceDeallocate, and share-capped emergency
///         recovery.
contract MorphoV2StrategyTest is Test {
    uint256 internal constant DEFAULT_MAX_PENALTY_BPS = 200;

    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
    }

    function _deployMorphoV2Setup()
        internal
        returns (
            CollateralVault collateralVault,
            MorphoV2Strategy strategy,
            MockMorphoV2Vault morphoVault,
            MockERC20 underlyingToken
        )
    {
        underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        morphoVault = new MockMorphoV2Vault(IERC20(address(underlyingToken)));
        (collateralVault, strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);
    }

    function _deployMorphoV2SetupWithVault(MockERC20 underlyingToken, MockMorphoV2Vault morphoVault)
        internal
        returns (CollateralVault collateralVault, MorphoV2Strategy strategy)
    {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(underlyingToken), true);
        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlyingToken)),
            IDToken(address(dToken)),
            treasury,
            admin
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        dToken.setTokenInfo("dmUSDC", "dmUSDC", IERC20MetadataUpgradeable(address(underlyingToken)));
        activateDTokenForTest(dToken);

        strategy = _deployStrategy(address(collateralVault), underlyingToken, morphoVault, DEFAULT_MAX_PENALTY_BPS);

        collateralVault.addToWhitelist(address(strategy));
        collateralVault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
    }

    function _deployStrategy(
        address vault,
        MockERC20 underlyingToken,
        MockMorphoV2Vault morphoVault,
        uint256 maxPenaltyBps
    ) internal returns (MorphoV2Strategy strategy) {
        MorphoV2Strategy strategyImplementation = new MorphoV2Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            MorphoV2Strategy.initialize.selector,
            vault,
            IERC20(address(underlyingToken)),
            admin,
            admin,
            IMorphoVaultV2(address(morphoVault)),
            maxPenaltyBps
        );
        strategy = MorphoV2Strategy(address(new ERC1967Proxy(address(strategyImplementation), strategyInitializer)));
    }

    function _depositAndAllocate(CollateralVault collateralVault, MockERC20 underlyingToken, uint256 amount) internal {
        underlyingToken.mint(alice, amount);
        vm.startPrank(alice);
        underlyingToken.approve(address(collateralVault), amount);
        collateralVault.deposit(amount);
        vm.stopPrank();
        collateralVault.setBufferConfig(0, 0);
        collateralVault.allocate();
    }

    // =============================================================
    //                      INITIALIZATION
    // =============================================================

    function test_Initialize_RevertsOnMorphoVaultAssetMismatch() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        MockERC20 otherUnderlying = new MockERC20("Other", "OTHER", 18);
        MockMorphoV2Vault wrongVault = new MockMorphoV2Vault(IERC20(address(otherUnderlying)));

        MorphoV2Strategy strategyImplementation = new MorphoV2Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            MorphoV2Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IMorphoVaultV2(address(wrongVault)),
            DEFAULT_MAX_PENALTY_BPS
        );

        vm.expectRevert(MorphoV2Strategy.InvalidMorphoVaultAsset.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnNonContractMorphoVault() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        address vaultEoa = makeAddr("morphoVaultEoa");

        MorphoV2Strategy strategyImplementation = new MorphoV2Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            MorphoV2Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IMorphoVaultV2(vaultEoa),
            DEFAULT_MAX_PENALTY_BPS
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, vaultEoa));
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnPenaltyBoundAboveProtocolMax() public {
        MockERC20 underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(underlying)));

        MorphoV2Strategy strategyImplementation = new MorphoV2Strategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            MorphoV2Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IMorphoVaultV2(address(morphoVault)),
            uint256(201)
        );

        vm.expectRevert(abi.encodeWithSelector(MorphoV2Strategy.ForceDeallocatePenaltyAboveMax.selector, 201, 200));
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    // =============================================================
    //                DEPOSIT / WITHDRAW WITH max* == 0
    // =============================================================

    function test_AllocateAndSendToVault_WorkDespiteHardZeroMaxViews() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        assertEq(morphoVault.maxDeposit(address(strategy)), 0, "venue reports zero maxDeposit");
        assertEq(morphoVault.maxWithdraw(address(strategy)), 0, "venue reports zero maxWithdraw");
        assertEq(strategy.principal(), 100e18, "principal deployed");
        assertEq(strategy.ownShares(), morphoVault.balanceOf(address(strategy)), "ownShares track venue balance");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 100e18, 2, "estimated tracks deposit");

        uint256 sent = strategy.sendToVault(40e18);

        assertEq(sent, 40e18, "withdraw works despite maxWithdraw == 0");
        assertEq(vault.bufferBalance(), 40e18, "vault received withdrawal");
        assertEq(strategy.principal(), 60e18, "principal reduced by sent amount");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 60e18, 2, "remaining shares track residual principal");
    }

    function test_SendProfitToVault_HarvestsSharePriceYieldWithoutReducingPrincipal() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        underlyingToken.mint(address(morphoVault), 10e18);
        uint256 principalBefore = strategy.principal();

        uint256 sent = strategy.sendProfitToVault();

        assertApproxEqAbs(sent, 10e18, 2, "yield pushed to vault");
        assertEq(strategy.principal(), principalBefore, "principal unchanged by harvest");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), principalBefore, 2, "remaining shares back principal");
    }

    // =============================================================
    //          DEPOSIT REJECTION -> EXACT RECEIPT RECOVERY
    // =============================================================

    function test_Allocate_RecoversWhenLiquidityAdapterCapHit() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();
        morphoVault.setDepositCapExceeded(true);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "rejected allocation returns to buffer same-tx");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
        assertEq(strategy.ownShares(), 0, "no shares tracked");
    }

    function test_Allocate_RecoversWhenReceiveGateCloses() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();
        morphoVault.setReceiveGateClosed(true);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "gated allocation returns to buffer same-tx");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_Allocate_RecoversAndSkipsWhenMorphoVaultMintsZeroShares() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroShareMorphoV2Vault morphoVault = new ZeroShareMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "rejected allocation returns to buffer");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_Allocate_RecoversAndSkipsWhenMorphoDepositReturnDoesNotMatchShareDelta() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        LyingDepositMorphoV2Vault morphoVault = new LyingDepositMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);

        underlyingToken.mint(alice, 100e18);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 100e18);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 100e18, "mismatched deposit returns to buffer");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "strategy retains no idle underlying");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_Allocate_RevertsAndRollsBackWhenMorphoShareRoundingBreaksFullBacking() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();
        address seeder = makeAddr("seeder");

        underlyingToken.mint(seeder, 3);
        vm.startPrank(seeder);
        underlyingToken.approve(address(morphoVault), 2);
        morphoVault.deposit(2, seeder);
        underlyingToken.transfer(address(morphoVault), 1);
        vm.stopPrank();

        underlyingToken.mint(alice, 2);
        vm.startPrank(alice);
        underlyingToken.approve(address(vault), 2);
        vault.deposit(2);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        (uint256 cacheBefore, uint256 cacheUpdatedAtBefore, bool cacheInitializedBefore) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        uint256 allocatorTimeBefore = vault.lastAllocatorTime();

        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(5e17), uint256(1e18))
        );
        vault.allocate();

        (uint256 cacheAfter, uint256 cacheUpdatedAtAfter, bool cacheInitializedAfter) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertEq(vault.bufferBalance(), 2, "failed allocation restores buffer");
        assertEq(strategy.principal(), 0, "failed allocation restores principal");
        assertEq(strategy.ownShares(), 0, "failed allocation restores tracked shares");
        assertEq(morphoVault.balanceOf(address(strategy)), 0, "failed allocation restores vault shares");
        assertEq(cacheAfter, cacheBefore, "failed allocation restores cached value");
        assertEq(cacheUpdatedAtAfter, cacheUpdatedAtBefore, "failed allocation restores cache timestamp");
        assertEq(cacheInitializedAfter, cacheInitializedBefore, "failed allocation restores cache state");
        assertEq(vault.lastAllocatorTime(), allocatorTimeBefore, "failed allocation preserves allocator timestamp");
    }

    // =============================================================
    //               FAIL-SOFT WITHDRAW (ADR-006)
    // =============================================================

    function test_SendToVault_ReturnsZeroFailSoftWhenLiquidityShort() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setAvailableLiquidity(0);

        uint256 principalBefore = strategy.principal();
        uint256 ownSharesBefore = strategy.ownShares();

        uint256 sent = strategy.sendToVault(10e18);

        assertEq(sent, 0, "liquidity-short withdraw fails soft");
        assertEq(vault.bufferBalance(), 0, "vault received nothing");
        assertEq(strategy.principal(), principalBefore, "principal unchanged");
        assertEq(strategy.ownShares(), ownSharesBefore, "ownShares unchanged");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "no idle underlying stranded");
    }

    function test_SendToVault_RetriesSmallerAmountWhenRequestedLiquidityIsShort() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setAvailableLiquidity(9e18);

        uint256 sent = strategy.sendToVault(10e18);

        assertEq(sent, 5e18, "bounded half-size retry recovers available liquidity");
        assertEq(vault.bufferBalance(), 5e18, "vault receives the successful partial withdrawal");
        assertEq(strategy.principal(), 95e18, "principal falls only by the amount actually received");
        assertEq(morphoVault.availableLiquidity(), 9e18, "failed full-size attempt rolled back venue state");
    }

    function test_SendToVault_ReturnsZeroFailSoftWhenSendGateCloses() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setSendGateClosed(true);

        uint256 sent = strategy.sendToVault(10e18);

        assertEq(sent, 0, "gated withdraw fails soft");
        assertEq(vault.bufferBalance(), 0, "vault received nothing");
        assertEq(strategy.principal(), 100e18, "principal unchanged");
    }

    function test_SendToVault_ReturnsZeroFailSoftWhenWithdrawReturnDoesNotMatchShareDelta() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        LyingWithdrawMorphoV2Vault morphoVault = new LyingWithdrawMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 ownSharesBefore = strategy.ownShares();

        uint256 sent = strategy.sendToVault(10e18);

        assertEq(sent, 0, "lying withdraw rolled back inside isolated frame");
        assertEq(vault.bufferBalance(), 0, "vault received nothing");
        assertEq(strategy.principal(), 100e18, "principal unchanged");
        assertEq(strategy.ownShares(), ownSharesBefore, "ownShares unchanged");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "hostile asset transfer rolled back");
    }

    function test_SendToVault_ReturnsZeroFailSoftWhenWithdrawBurnsZeroShares() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroBurnWithdrawMorphoV2Vault morphoVault = new ZeroBurnWithdrawMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 ownSharesBefore = strategy.ownShares();

        uint256 sent = strategy.sendToVault(10e18);

        assertEq(sent, 0, "zero-burn withdraw rolled back inside isolated frame");
        assertEq(vault.bufferBalance(), 0, "vault received nothing");
        assertEq(strategy.principal(), 100e18, "principal unchanged");
        assertEq(strategy.ownShares(), ownSharesBefore, "ownShares unchanged");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "hostile asset transfer rolled back");
        assertEq(morphoVault.balanceOf(address(strategy)), ownSharesBefore, "share balance unchanged");
    }

    // =============================================================
    //                 VALUATION SEMANTICS
    // =============================================================

    function test_ShareDonationDoesNotInflateRealizedYield() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        uint256 yieldBefore = strategy.realizedYield();
        uint256 principalBefore = strategy.principal();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();

        address donor = makeAddr("donor");
        underlyingToken.mint(donor, 10e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(morphoVault), 10e18);
        uint256 donatedShares = morphoVault.deposit(10e18, donor);
        morphoVault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        assertEq(strategy.realizedYield(), yieldBefore, "share donation did not inflate realizedYield");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "estimatedTotalUnderlying unchanged");
        assertEq(strategy.principal(), principalBefore, "principal unchanged");
    }

    function test_AssetLossReflectedImmediatelyInEstimateAndVaultTotal() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        uint256 totalBefore = vault.totalUnderlying();

        underlyingToken.burn(address(morphoVault), 50e18);

        assertLt(strategy.estimatedTotalUnderlying(), estimatedBefore, "estimated dropped after loss");
        assertLt(vault.totalUnderlying(), totalBefore, "vault total reflects loss immediately");
    }

    function test_SweepRewardToken_RejectsMorphoShareToken() public {
        (, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault,) = _deployMorphoV2Setup();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        strategy.sweepRewardToken(IERC20(address(morphoVault)), type(uint256).max);
    }

    // =============================================================
    //                 EMERGENCY WITHDRAW
    // =============================================================

    function test_EmergencyWithdrawFromMorphoV2_FullDrainPushesToVaultSameTx() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromMorphoV2(type(uint256).max);

        assertEq(sent, 100e18, "reported vault receipt");
        assertEq(morphoVault.balanceOf(address(strategy)), 0, "share token drained");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "underlying not left idle in strategy");
        assertEq(strategy.estimatedTotalUnderlying(), 0, "estimated reset to zero");
        assertEq(strategy.ownShares(), 0, "ownShares reset to zero");
        assertEq(strategy.principal(), 0, "returned principal accounted");
        assertEq(vault.bufferBalance(), 100e18, "underlying returned to vault buffer");
        (uint256 cachedValue,, bool cacheInitialized) = vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertFalse(cacheInitialized, "exhausted historical estimate is invalidated");
        assertEq(cachedValue, 0, "valuation cache reduced after emergency push");
    }

    function test_EmergencyWithdrawFromMorphoV2_PartialRecoveryViaMaxSharesAccountsReturnedPrincipal() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 ownSharesBefore = strategy.ownShares();

        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromMorphoV2(40e18);

        assertApproxEqAbs(sent, 40e18, 2, "reported vault receipt");
        assertApproxEqAbs(vault.bufferBalance(), 40e18, 2, "vault received capped portion");
        assertEq(strategy.ownShares(), ownSharesBefore - 40e18, "ownShares reduced by redeemed cap");
        assertEq(morphoVault.balanceOf(address(strategy)), ownSharesBefore - 40e18, "share balance matches ownShares");
        assertApproxEqAbs(strategy.principal(), 60e18, 2, "principal reduced by recovered amount");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 60e18, 2, "remaining shares stay valued");
        assertApproxEqAbs(vault.totalUnderlying(), 100e18, 2, "partial recovery is not loss");

        vm.prank(admin);
        uint256 sentRest = strategy.emergencyWithdrawFromMorphoV2(type(uint256).max);

        assertApproxEqAbs(sent + sentRest, 100e18, 2, "full principal recovered across both pulls");
        assertEq(strategy.ownShares(), 0, "ownShares fully unwound");
        assertApproxEqAbs(strategy.principal(), 0, 2, "principal fully accounted");
    }

    // Recovering a donation with a PARTIAL call must not consume own-share accounting.
    // Every other path clamps to min(_ownShares, balance) so donations are ignored; the
    // emergency path deliberately redeems from the raw balance, so the decrement has to know
    // which of the redeemed shares were actually the Strategy's.
    function test_EmergencyWithdrawFromMorphoV2_PartialDonationRecoveryKeepsOwnShares() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 ownSharesBefore = strategy.ownShares();
        uint256 valuationBefore = strategy.estimatedTotalUnderlying();
        assertGt(ownSharesBefore, 0);

        address donor = makeAddr("donor");
        underlyingToken.mint(donor, 10e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(morphoVault), 10e18);
        uint256 donatedShares = morphoVault.deposit(10e18, donor);
        morphoVault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        // The documented recovery: redeem exactly the donated portion.
        vm.prank(admin);
        strategy.emergencyWithdrawFromMorphoV2(donatedShares);

        assertEq(morphoVault.balanceOf(address(strategy)), ownSharesBefore, "only the donated shares were redeemed");
        assertEq(strategy.ownShares(), ownSharesBefore, "own-share accounting survives the donation recovery");
        assertApproxEqAbs(
            strategy.estimatedTotalUnderlying(),
            valuationBefore,
            2,
            "recovering a donation must not shrink the Strategy's reported value"
        );
    }

    function test_EmergencyWithdrawFromMorphoV2_RecoversDonatedSharesAfterFullUnwind() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);

        address donor = makeAddr("donor");
        underlyingToken.mint(donor, 10e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(morphoVault), 10e18);
        uint256 donatedShares = morphoVault.deposit(10e18, donor);
        morphoVault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        // Full unwind of the tracked position leaves only donated shares.
        uint256 sentPrincipal = strategy.sendToVault(type(uint256).max);
        assertApproxEqAbs(sentPrincipal, 100e18, 2, "tracked position fully unwound");
        assertEq(strategy.ownShares(), 0, "no own shares left");
        assertGt(morphoVault.balanceOf(address(strategy)), 0, "donated shares still held");

        // Emergency recovery redeems the donated shares too instead of
        // stranding them (sweepRewardToken rejects the position token).
        vm.prank(admin);
        uint256 sent = strategy.emergencyWithdrawFromMorphoV2(type(uint256).max);

        assertApproxEqAbs(sent, 10e18, 2, "donated value recovered to the Vault");
        assertEq(morphoVault.balanceOf(address(strategy)), 0, "no shares stranded");
        assertEq(strategy.ownShares(), 0, "ownShares clamped at zero");
        assertEq(underlyingToken.balanceOf(address(strategy)), 0, "nothing left idle in strategy");
        assertApproxEqAbs(vault.bufferBalance(), 110e18, 2, "vault holds principal plus donation");
    }

    function test_EmergencyWithdrawFromMorphoV2_RevertsWhenRedeemAssetDeltaMismatch() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ZeroAssetRedeemMorphoV2Vault morphoVault = new ZeroAssetRedeemMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);

        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.expectRevert(abi.encodeWithSelector(MorphoV2Strategy.MorphoV2AssetAmountMismatch.selector, 100e18, 0));
        vm.prank(admin);
        strategy.emergencyWithdrawFromMorphoV2(type(uint256).max);

        assertEq(strategy.estimatedTotalUnderlying(), 100e18, "revert preserves strategy value");
        assertEq(strategy.principal(), 100e18, "principal unchanged");
        assertEq(vault.bufferBalance(), 0, "vault did not receive mismatched redeem");
    }

    // =============================================================
    //                    FORCE DEALLOCATE
    // =============================================================

    function testFuzz_GuardianL05_InsufficientReceiptRollsBackEverything(uint96 rawAmount) public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 token) =
            _deployMorphoV2Setup();
        uint256 amount = bound(uint256(rawAmount), 1e6, 1e24);
        _depositAndAllocate(vault, token, amount);
        morphoVault.setForceDeallocatePenaltyBps(100);
        morphoVault.setAvailableLiquidity(0);
        uint256 sharesBefore = strategy.ownShares();
        (uint256 cacheBefore, uint256 ageBefore, bool initializedBefore) = vault.strategyValuationCaches(strategy);

        // Withdrawing the full amount cannot succeed after a positive penalty.
        vm.expectRevert(abi.encodeWithSelector(CollateralVault.RecoveryBelowMinimum.selector, amount - amount / 100, amount));
        vault.forceDeallocateMorphoV2(strategy, makeAddr("adapter"), "", amount, amount, 0);
        assertEq(strategy.ownShares(), sharesBefore);
        assertEq(morphoVault.balanceOf(address(strategy)), sharesBefore);
        assertEq(morphoVault.balanceOf(address(morphoVault)), 0, "penalty rolled back");
        assertEq(morphoVault.availableLiquidity(), 0, "deallocation rolled back");
        assertEq(strategy.principal(), amount);
        assertEq(vault.bufferBalance(), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertFalse(vault.pausedAllocation());
        assertFalse(vault.pausedDeposit());
        assertFalse(vault.pausedRedeem());
        assertFalse(vault.pausedClaim());
        (uint256 cacheAfter, uint256 ageAfter, bool initializedAfter) = vault.strategyValuationCaches(strategy);
        assertEq(cacheAfter, cacheBefore);
        assertEq(ageAfter, ageBefore);
        assertEq(initializedAfter, initializedBefore);
    }

    function test_GuardianL05_ClosedSendGateAndZeroMinimumCannotCommitPenalty() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 token) =
            _deployMorphoV2Setup();
        _depositAndAllocate(vault, token, 100e18);
        morphoVault.setForceDeallocatePenaltyBps(100);
        morphoVault.setSendGateClosed(true);
        vm.expectRevert(abi.encodeWithSelector(CollateralVault.RecoveryBelowMinimum.selector, 0, 1));
        vault.forceDeallocateMorphoV2(strategy, makeAddr("adapter"), "", 100e18, 1, 0);
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.forceDeallocateMorphoV2(strategy, makeAddr("adapter"), "", 100e18, 0, 0);
        assertEq(strategy.ownShares(), 100e18);
        assertEq(strategy.principal(), 100e18);
        assertEq(vault.bufferBalance(), 0);
        assertFalse(vault.pausedAllocation());
    }

    function test_GuardianL05_AtomicRecoveryRetainsStrategyReentrancyGuard() public {
        MockERC20 token = new MockERC20("Underlying", "UND", 18);
        ReenteringMorphoV2Vault morphoVault = new ReenteringMorphoV2Vault(IERC20(address(token)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(token, morphoVault);
        _depositAndAllocate(vault, token, 100e18);
        morphoVault.setStrategy(strategy);
        morphoVault.setReenterOnWithdraw(true);
        vault.forceDeallocateMorphoV2(strategy, makeAddr("adapter"), "", 50e18, 50e18, 1e18);
        assertTrue(morphoVault.reentrancyBlocked());
        assertTrue(morphoVault.vaultReentrancyBlocked());
        assertFalse(morphoVault.reentrancySucceeded());
        assertEq(vault.bufferBalance(), 50e18);
    }

    function test_ForceDeallocate_WithinBoundResyncsOwnSharesAndDropsValuation() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setForceDeallocatePenaltyBps(100); // 1% <= 2% strategy bound

        uint256 ownSharesBefore = strategy.ownShares();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();

        (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets) =
            vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 0.99e18);

        assertGt(penaltyShares, 0, "penalty charged");
        assertApproxEqAbs(penaltyAssets, 5e17, 2, "vault receives measured penalty assets");
        assertApproxEqAbs(valuationLossAssets, 5e17, 2, "tracked valuation bears the penalty");
        assertApproxEqAbs(strategy.ownShares(), ownSharesBefore - penaltyShares - 50e18, 2, "penalty and recovery reduce shares");
        assertEq(morphoVault.balanceOf(address(strategy)), strategy.ownShares(), "balance matches ownShares");
        assertApproxEqAbs(
            strategy.estimatedTotalUnderlying(), estimatedBefore - 5e17 - 50e18, 2, "valuation reflects penalty and recovered assets"
        );
        assertEq(strategy.principal(), 50e18, "only actual receipt reduces principal");
        assertEq(vault.bufferBalance(), 50e18, "liquidity recovered atomically");
        assertTrue(vault.pausedAllocation(), "incident call pauses allocation atomically");
        assertTrue(vault.pausedDeposit(), "incident call pauses deposits atomically");
        assertTrue(vault.pausedRedeem(), "incident call pauses redemptions atomically");
        assertTrue(vault.pausedClaim(), "incident call pauses claims atomically");
    }

    function test_ForceDeallocate_RevertsWhenPenaltyExceedsBound() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setForceDeallocatePenaltyBps(300); // 3% > 2% strategy bound

        uint256 ownSharesBefore = strategy.ownShares();

        vm.expectRevert(
            abi.encodeWithSelector(MorphoV2Strategy.ForceDeallocatePenaltyExceeded.selector, 15e17, 1e18 + 1)
        );
        vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 0);

        assertEq(strategy.ownShares(), ownSharesBefore, "revert preserves ownShares");
        assertEq(morphoVault.balanceOf(address(strategy)), ownSharesBefore, "revert preserves share balance");
        assertFalse(vault.pausedAllocation(), "revert rolls back incident pauses");
        assertFalse(vault.pausedDeposit(), "revert rolls back user-flow pauses");
    }

    function test_ForceDeallocate_ZeroPenaltyVaultBurnsNothing() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        assertEq(morphoVault.forceDeallocatePenaltyBps(), 0, "penalty-free venue");

        uint256 ownSharesBefore = strategy.ownShares();

        (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets) =
            vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 1e18);

        assertEq(penaltyShares, 0, "no penalty charged");
        assertEq(penaltyAssets, 0, "no penalty assets charged");
        assertEq(valuationLossAssets, 0, "tracked valuation is unchanged");
        assertApproxEqAbs(strategy.ownShares(), ownSharesBefore - 50e18, 2, "withdrawn shares consumed");
        assertEq(strategy.estimatedTotalUnderlying(), 50e18, "remaining position");
        assertEq(vault.bufferBalance(), 50e18, "recovered receipt");
    }

    function test_ForceDeallocate_ChargesDonatedSharesBeforeTrackedShares() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        uint256 ownSharesBefore = strategy.ownShares();

        address donor = makeAddr("force-deallocate-donor");
        underlyingToken.mint(donor, 10e18);
        vm.startPrank(donor);
        underlyingToken.approve(address(morphoVault), 10e18);
        uint256 donatedShares = morphoVault.deposit(10e18, donor);
        morphoVault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        morphoVault.setForceDeallocatePenaltyBps(100);
        (uint256 penaltyShares, uint256 penaltyAssets, uint256 valuationLossAssets) =
            vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 1e18);

        assertGt(penaltyShares, 0, "venue penalty is paid");
        assertApproxEqAbs(penaltyAssets, 5e17, 2, "total venue penalty is measured");
        assertEq(valuationLossAssets, 0, "donated value absorbs the penalty first");
        assertApproxEqAbs(strategy.ownShares(), ownSharesBefore - 50e18, 2, "tracked shares pay recovery but not donation-funded penalty");
        assertEq(vault.backingRatio(), 1e18, "excluded donations cannot create a false backing loss");
    }

    function test_ForceDeallocate_StrategyEntryIsVaultOnly() public {
        (CollateralVault vault, MorphoV2Strategy strategy,, MockERC20 underlyingToken) = _deployMorphoV2Setup();
        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.expectRevert(BaseStrategy.OnlyVault.selector);
        strategy.forceDeallocate(makeAddr("adapter"), "", 50e18);
    }

    function test_ForceDeallocate_VaultEntryRequiresWriteoffRole() public {
        (CollateralVault vault, MorphoV2Strategy strategy,, MockERC20 underlyingToken) = _deployMorphoV2Setup();
        _depositAndAllocate(vault, underlyingToken, 100e18);

        vm.expectRevert();
        vm.prank(alice);
        vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 0);
    }

    function test_ForceDeallocate_RevertsAndRollsBackWhenBackingFallsBelowCallerFloor() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setForceDeallocatePenaltyBps(100);
        uint256 ownSharesBefore = strategy.ownShares();

        vm.expectRevert(abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, 0.995e18, 0.996e18));
        vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 50e18, 50e18, 0.996e18);

        assertEq(strategy.ownShares(), ownSharesBefore, "backing guard rolls back the penalty");
        assertFalse(vault.pausedAllocation(), "backing guard rolls back allocation pause");
        assertFalse(vault.pausedDeposit(), "backing guard rolls back user-flow pause");
    }

    function test_GuardianL05_RecoveryIsAtomicAcrossSeparatedRoles() public {
        (CollateralVault vault, MorphoV2Strategy strategy, MockMorphoV2Vault morphoVault, MockERC20 underlyingToken) =
            _deployMorphoV2Setup();

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setForceDeallocatePenaltyBps(100);
        morphoVault.setAvailableLiquidity(0);

        // 1) Normal path fails soft: no liquidity.
        uint256 sent = strategy.sendToVault(100e18);
        assertEq(sent, 0, "no liquidity: sendToVault fails soft");

        // The writeoff role is neither Strategy owner nor allocator.
        address writeoff = makeAddr("independent-writeoff");
        vault.grantRole(keccak256("WRITEOFF_ROLE"), writeoff);
        assertFalse(vault.hasRole(keccak256("ALLOCATOR_ROLE"), writeoff));
        assertTrue(strategy.owner() != writeoff);
        vm.prank(writeoff);
        (uint256 penaltyShares,,) =
            vault.forceDeallocateMorphoV2(IStrategy(address(strategy)), makeAddr("adapter"), "", 100e18, 99e18, 0.99e18);
        assertGt(penaltyShares, 0, "penalty paid to unlock liquidity");

        uint256 recovered = vault.bufferBalance();

        assertApproxEqAbs(recovered, 99e18, 2, "recovered all but the ~1% penalty");
        assertEq(strategy.ownShares(), 0, "position fully unwound");
        assertApproxEqAbs(strategy.principal(), 1e18, 2, "residual principal equals the confirmed penalty loss");
        assertApproxEqAbs(vault.bufferBalance(), 99e18, 2, "vault holds recovered underlying");

        // 4) GOV acknowledges the penalty as a permanent loss.
        vault.emergencyDisableStrategy(IStrategy(address(strategy)));
        vault.writeoffStrategyPrincipal(IStrategy(address(strategy)), strategy.principal(), 0);
        assertEq(strategy.principal(), 0, "residual principal written off");
    }

    // =============================================================
    //             REENTRANCY / SELF-CALL ISOLATION
    // =============================================================

    function test_DepositIntoMorphoVault_SelfOnly() public {
        (, MorphoV2Strategy strategy,,) = _deployMorphoV2Setup();

        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        strategy.depositIntoMorphoVault(1e18);
    }

    function test_WithdrawFromMorphoVault_SelfOnly() public {
        (, MorphoV2Strategy strategy,,) = _deployMorphoV2Setup();

        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        strategy.withdrawFromMorphoVault(1e18);
    }

    function test_Reentrancy_DuringVenueDepositIsBlocked() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ReenteringMorphoV2Vault morphoVault = new ReenteringMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);
        morphoVault.setStrategy(strategy);
        morphoVault.setReenterOnDeposit(true);

        _depositAndAllocate(vault, underlyingToken, 100e18);

        assertTrue(morphoVault.reentrancyBlocked(), "reentrant sendToVault reverted");
        assertFalse(morphoVault.reentrancySucceeded(), "reentrancy never succeeded");
        assertEq(strategy.principal(), 100e18, "deposit completed normally after blocked reentry");
        assertEq(strategy.ownShares(), 100e18, "shares tracked normally");
    }

    function test_Reentrancy_DuringVenueWithdrawIsBlocked() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        ReenteringMorphoV2Vault morphoVault = new ReenteringMorphoV2Vault(IERC20(address(underlyingToken)));
        (CollateralVault vault, MorphoV2Strategy strategy) = _deployMorphoV2SetupWithVault(underlyingToken, morphoVault);
        morphoVault.setStrategy(strategy);

        _depositAndAllocate(vault, underlyingToken, 100e18);
        morphoVault.setReenterOnWithdraw(true);

        uint256 sent = strategy.sendToVault(10e18);

        assertTrue(morphoVault.reentrancyBlocked(), "reentrant sendToVault reverted");
        assertFalse(morphoVault.reentrancySucceeded(), "reentrancy never succeeded");
        assertEq(sent, 10e18, "withdraw completed normally after blocked reentry");
        assertEq(vault.bufferBalance(), 10e18, "vault received exactly the requested amount");
        assertEq(strategy.principal(), 90e18, "principal reduced once");
    }
}
