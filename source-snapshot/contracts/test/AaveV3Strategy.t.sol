// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "../src/Strategies/AaveV3Strategy.sol"; // AaveV3Strategy, IAaveV3Pool, IAToken
import "../src/Interfaces/IStrategy.sol";
import "../src/Interfaces/IDToken.sol";
import "./PushModelMocks.sol"; // MockAToken, MockAavePool
import "./mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract SenderFeeMockERC20 is MockERC20 {
    uint256 public constant FEE_BPS = 100; // 1%
    uint256 public constant BPS = 10000;
    address public constant SINK = 0x000000000000000000000000000000000000dEaD;

    address public feeSender;

    constructor(string memory name, string memory symbol, uint8 decimals_) MockERC20(name, symbol, decimals_) {}

    function setFeeSender(address _feeSender) external {
        feeSender = _feeSender;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address sender = _msgSender();
        if (sender != feeSender) return super.transfer(to, amount);

        uint256 fee = (amount * FEE_BPS) / BPS;
        uint256 net = amount - fee;
        _transfer(sender, to, net);
        if (fee > 0) _transfer(sender, SINK, fee);
        return true;
    }
}

contract MockAaveRewardsController is IAaveRewardsController {
    address public lastCaller;
    address public lastAsset;
    address public lastTo;
    address public lastReward;
    uint256 public lastAmount;
    uint256 public payoutAmount;

    function setPayoutAmount(uint256 _payoutAmount) external {
        payoutAmount = _payoutAmount;
    }

    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward)
        external
        returns (uint256)
    {
        require(assets.length == 1, "assets length");
        lastCaller = msg.sender;
        lastAsset = assets[0];
        lastTo = to;
        lastReward = reward;
        lastAmount = amount;

        uint256 payout = payoutAmount;
        if (payout != 0) {
            MockERC20(reward).transfer(to, payout);
        }
        return payout;
    }
}

/// @title AaveV3StrategyTest - Phase 3b synchronous Aave-V3 strategy coverage.
/// @notice Ports the Aave-dependent push-model tests from jpydf #61
///         (`feat/push-model-migration` head `9acb750`): donation-resistant AUM
///         (HC-03), immediate loss reflection, vault total reflecting loss, and
///         the atomic emergency recovery (`emergencyWithdrawFromAave` pushes
///         recovered funds to the Vault and accounts returned principal).
///         Backed by `MockAavePool` / `MockAToken` (forkless); a mainnet fork is
///         optional and not required here.
contract AaveV3StrategyTest is Test {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
    }

    /// @dev Build a CollateralVault wired to an AaveV3Strategy over a mock Aave Pool.
    function _deployAaveSetup()
        internal
        returns (CollateralVault vault_, AaveV3Strategy strat_, MockAavePool pool_, MockERC20 u_)
    {
        u_ = new MockERC20("Aave WBTC", "aWBTCu", 8);
        (vault_, strat_, pool_) = _deployAaveSetupWithUnderlying(u_);
    }

    function _deployAaveSetupWithUnderlying(MockERC20 u_)
        internal
        returns (CollateralVault vault_, AaveV3Strategy strat_, MockAavePool pool_)
    {
        pool_ = new MockAavePool();
        MockAToken aToken_ = new MockAToken(address(pool_), address(u_));
        pool_.setAsset(IERC20(address(u_)));
        pool_.setAToken(aToken_);

        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        DToken d_ = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        d_.setAllowedUnderlying(address(u_), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(u_)), IDToken(address(d_)), treasury, admin
        );
        vault_ = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        d_.setTokenInfo("daWBTC", "daWBTC", IERC20MetadataUpgradeable(address(u_)));
        activateDTokenForTest(d_);

        AaveV3Strategy sImpl = new AaveV3Strategy();
        bytes memory sInit = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(vault_),
            IERC20(address(u_)),
            admin,
            admin,
            IAaveV3Pool(address(pool_)),
            IAToken(address(aToken_))
        );
        strat_ = AaveV3Strategy(address(new ERC1967Proxy(address(sImpl), sInit)));

        vault_.addToWhitelist(address(strat_));
        vault_.addStrategy(IStrategy(address(strat_)), 10000, type(uint256).max);
    }

    function test_Initialize_RevertsOnATokenUnderlyingMismatch() public {
        MockERC20 underlying = new MockERC20("Aave WBTC", "aWBTCu", 8);
        MockERC20 otherUnderlying = new MockERC20("Other", "OTHER", 8);
        MockAavePool pool = new MockAavePool();
        MockAToken wrongAToken = new MockAToken(address(pool), address(otherUnderlying));

        AaveV3Strategy impl = new AaveV3Strategy();
        bytes memory init = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IAaveV3Pool(address(pool)),
            IAToken(address(wrongAToken))
        );

        vm.expectRevert(AaveV3Strategy.InvalidATokenUnderlying.selector);
        new ERC1967Proxy(address(impl), init);
    }

    function test_Initialize_RevertsOnNonContractAavePool() public {
        MockERC20 underlying = new MockERC20("Aave WBTC", "aWBTCu", 8);
        MockAavePool pool = new MockAavePool();
        MockAToken aToken = new MockAToken(address(pool), address(underlying));
        address poolEoa = makeAddr("poolEoa");

        AaveV3Strategy impl = new AaveV3Strategy();
        bytes memory init = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IAaveV3Pool(poolEoa),
            IAToken(address(aToken))
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, poolEoa));
        new ERC1967Proxy(address(impl), init);
    }

    function test_Initialize_RevertsOnNonContractAToken() public {
        MockERC20 underlying = new MockERC20("Aave WBTC", "aWBTCu", 8);
        MockAavePool pool = new MockAavePool();
        address aTokenEoa = makeAddr("aTokenEoa");

        AaveV3Strategy impl = new AaveV3Strategy();
        bytes memory init = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            admin,
            IAaveV3Pool(address(pool)),
            IAToken(aTokenEoa)
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, aTokenEoa));
        new ERC1967Proxy(address(impl), init);
    }

    function test_Initialize_RevertsOnZeroUpgrader() public {
        MockERC20 underlying = new MockERC20("Aave WBTC", "aWBTCu", 8);
        MockAavePool pool = new MockAavePool();
        MockAToken aToken = new MockAToken(address(pool), address(underlying));

        AaveV3Strategy impl = new AaveV3Strategy();
        bytes memory init = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(this),
            IERC20(address(underlying)),
            admin,
            address(0),
            IAaveV3Pool(address(pool)),
            IAToken(address(aToken))
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), init);
    }

    function test_SweepRewardToken_RejectsATokenPositionToken() public {
        (, AaveV3Strategy aaveStrat, MockAavePool pool,) = _deployAaveSetup();
        MockAToken aToken = pool.aToken();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        aaveStrat.sweepRewardToken(IERC20(address(aToken)), type(uint256).max);
    }

    function test_SweepRewardToken_AaveRewardStillSweepsToTreasury() public {
        (, AaveV3Strategy aaveStrat,,) = _deployAaveSetup();
        MockERC20 reward = new MockERC20("Merkl Reward", "MRKL", 18);
        uint256 amount = 25e18;
        reward.mint(address(aaveStrat), amount);

        vm.prank(admin);
        uint256 swept = aaveStrat.sweepRewardToken(IERC20(address(reward)), type(uint256).max);

        assertEq(swept, amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(aaveStrat)), 0, "strategy reward drained");
    }

    function test_ClaimAaveRewards_ClaimsOnlyATokenAssetAndSweepsRewardToTreasury() public {
        (, AaveV3Strategy aaveStrat, MockAavePool pool,) = _deployAaveSetup();
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        MockERC20 reward = new MockERC20("Aave Reward", "AAVE-R", 18);
        uint256 amount = 25e18;
        reward.mint(address(rewardsController), amount);
        rewardsController.setPayoutAmount(amount);

        vm.expectEmit(true, true, false, true, address(aaveStrat));
        emit AaveV3Strategy.AaveRewardsClaimed(
            address(rewardsController), address(reward), type(uint256).max, amount, amount
        );
        vm.prank(admin);
        (uint256 claimed, uint256 settled) = aaveStrat.claimAaveRewards(
            IAaveRewardsController(address(rewardsController)), type(uint256).max, address(reward)
        );

        assertEq(rewardsController.lastCaller(), address(aaveStrat), "strategy called rewards controller");
        assertEq(rewardsController.lastAsset(), address(pool.aToken()), "claim asset pinned to aToken");
        assertEq(rewardsController.lastTo(), address(aaveStrat), "claim recipient is strategy");
        assertEq(rewardsController.lastReward(), address(reward), "reward token");
        assertEq(claimed, amount, "reported claimed amount");
        assertEq(settled, amount, "reported treasury receipt");
        assertEq(reward.balanceOf(treasury), amount, "treasury received reward");
        assertEq(reward.balanceOf(address(aaveStrat)), 0, "strategy reward drained");
    }

    function test_ClaimAaveRewards_PushesUnderlyingRewardToVaultWithoutReducingPrincipal() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat,, MockERC20 aaveU) = _deployAaveSetup();
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        uint256 amount = 3e8;
        aaveU.mint(address(rewardsController), amount);
        rewardsController.setPayoutAmount(amount);

        uint256 bufferBefore = aaveVault.bufferBalance();
        uint256 totalUnderlyingBefore = aaveVault.totalUnderlying();
        uint256 principalBefore = aaveStrat.principal();

        vm.expectEmit(true, true, false, true, address(aaveStrat));
        emit AaveV3Strategy.AaveUnderlyingRewardsClaimed(
            address(rewardsController), address(aaveU), amount, amount, amount
        );
        vm.prank(admin);
        (uint256 claimed, uint256 settled) =
            aaveStrat.claimAaveRewards(IAaveRewardsController(address(rewardsController)), amount, address(aaveU));

        assertEq(claimed, amount, "reported claimed underlying");
        assertEq(settled, amount, "reported vault receipt");
        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "underlying not left idle");
        assertEq(aaveVault.bufferBalance(), bufferBefore + amount, "vault buffer received underlying reward");
        assertEq(aaveVault.totalUnderlying(), totalUnderlyingBefore + amount, "vault assets include underlying reward");
        assertEq(aaveStrat.principal(), principalBefore, "principal unchanged");
    }

    function test_ClaimAaveRewards_RejectsProtectedRewardTokensBeforeControllerCall() public {
        (, AaveV3Strategy aaveStrat, MockAavePool pool,) = _deployAaveSetup();
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        address aToken = address(pool.aToken());

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        vm.prank(admin);
        aaveStrat.claimAaveRewards(IAaveRewardsController(address(rewardsController)), type(uint256).max, aToken);

        assertEq(rewardsController.lastCaller(), address(0), "controller was not called");
    }

    function test_ClaimAaveRewards_RejectsInvalidCallerAndController() public {
        (, AaveV3Strategy aaveStrat,,) = _deployAaveSetup();
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        MockERC20 reward = new MockERC20("Aave Reward", "AAVE-R", 18);

        vm.expectRevert();
        vm.prank(alice);
        aaveStrat.claimAaveRewards(IAaveRewardsController(address(rewardsController)), 1e18, address(reward));

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        vm.prank(admin);
        aaveStrat.claimAaveRewards(IAaveRewardsController(address(0)), 1e18, address(reward));

        vm.expectRevert(AaveV3Strategy.InvalidAaveRewardsController.selector);
        vm.prank(admin);
        aaveStrat.claimAaveRewards(IAaveRewardsController(alice), 1e18, address(reward));

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        vm.prank(admin);
        aaveStrat.claimAaveRewards(IAaveRewardsController(address(rewardsController)), 1e18, address(0));
    }

    function test_ClaimAaveRewards_FeeOnTransferRewardReportsTreasuryReceipt() public {
        (, AaveV3Strategy aaveStrat,,) = _deployAaveSetup();
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        SenderFeeMockERC20 reward = new SenderFeeMockERC20("Aave Fee Reward", "AFR", 18);
        uint256 amount = 100e18;
        uint256 expectedReceived = amount - ((amount * reward.FEE_BPS()) / reward.BPS());
        reward.mint(address(rewardsController), amount);
        reward.setFeeSender(address(aaveStrat));
        rewardsController.setPayoutAmount(amount);

        vm.prank(admin);
        (uint256 claimed, uint256 settled) =
            aaveStrat.claimAaveRewards(IAaveRewardsController(address(rewardsController)), amount, address(reward));

        assertEq(claimed, amount, "controller reported gross reward");
        assertEq(settled, expectedReceived, "reported treasury net receipt");
        assertEq(reward.balanceOf(treasury), expectedReceived, "treasury received net reward");
        assertEq(reward.balanceOf(address(aaveStrat)), 0, "strategy reward drained");
    }

    function _depositAndAllocate(CollateralVault vault_, MockERC20 u_, uint256 amount) internal {
        u_.mint(alice, amount);
        vm.startPrank(alice);
        u_.approve(address(vault_), amount);
        vault_.deposit(amount);
        vm.stopPrank();
        vault_.setBufferConfig(0, 0);
        vault_.allocate();
    }

    // =================================================================
    //   HC-03: third-party donation must NOT inflate realized yield
    // =================================================================

    function test_DonationDoesNotInflateRealizedYield() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        uint256 yieldBefore = aaveStrat.realizedYield();
        uint256 principalBefore = aaveStrat.principal();
        uint256 estimatedBefore = aaveStrat.estimatedTotalUnderlying();

        // Third party donates 1e8 via supply(onBehalfOf=aaveStrat).
        address donor = makeAddr("donor");
        aaveU.mint(donor, 1e8);
        vm.startPrank(donor);
        aaveU.approve(address(pool), 1e8);
        pool.supply(address(aaveU), 1e8, address(aaveStrat), 0);
        vm.stopPrank();

        assertEq(aaveStrat.realizedYield(), yieldBefore, "donation did not inflate realizedYield");
        assertEq(aaveStrat.estimatedTotalUnderlying(), estimatedBefore, "estimatedTotalUnderlying unchanged");
        assertEq(aaveStrat.principal(), principalBefore, "principal unchanged");
    }

    function test_Allocate_RecoversAndSkipsWhenAaveSupplyMintsZeroScaledBalance() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        pool.setLiquidityIndex(2e27);

        aaveU.mint(alice, 1);
        vm.startPrank(alice);
        aaveU.approve(address(aaveVault), 1);
        aaveVault.deposit(1);
        vm.stopPrank();
        aaveVault.setBufferConfig(0, 0);

        aaveVault.allocate();

        assertEq(aaveStrat.principal(), 0, "principal not inflated by zero-scaled supply");
        assertEq(aaveU.balanceOf(address(aaveVault)), 1, "dust stays in vault buffer after recovered skip");
        assertEq(aaveStrat.estimatedTotalUnderlying(), 0, "no zero-valued position tracked");
    }

    function test_Allocate_RecoversAndSkipsWhenAaveSupplyCapRejects() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();
        uint256 amount = 10e8;

        aaveU.mint(alice, amount);
        vm.startPrank(alice);
        aaveU.approve(address(aaveVault), amount);
        aaveVault.deposit(amount);
        vm.stopPrank();
        aaveVault.setBufferConfig(0, 0);
        pool.setSupplyCapReached(true);

        aaveVault.allocate();

        assertEq(aaveVault.bufferBalance(), amount, "supply-cap rejected share returns to buffer");
        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "Aave strategy retains no idle underlying");
        assertEq(aaveStrat.principal(), 0, "rejected supply does not increase principal");
        assertEq(aaveStrat.estimatedTotalUnderlying(), 0, "rejected supply creates no position");
    }

    function test_SendToVault_RevertsWhenAaveWithdrawBurnsZeroScaledBalance() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);
        uint256 principalBefore = aaveStrat.principal();
        pool.setLiquidityIndex(2e27);

        vm.expectRevert(abi.encodeWithSelector(AaveV3Strategy.AaveWithdrawZeroScaledBurn.selector, 1));
        aaveStrat.sendToVault(1);

        assertEq(aaveStrat.principal(), principalBefore, "principal unchanged after failed zero-burn withdraw");
        assertEq(aaveVault.bufferBalance(), 0, "vault received no dust after revert");
    }

    function test_EmergencyWithdrawFromAave_RevertsWhenAaveWithdrawBurnsZeroScaledBalance() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);
        uint256 principalBefore = aaveStrat.principal();
        pool.setLiquidityIndex(2e36);

        vm.expectRevert(abi.encodeWithSelector(AaveV3Strategy.AaveWithdrawZeroScaledBurn.selector, 10e8));
        vm.prank(admin);
        aaveStrat.emergencyWithdrawFromAave();

        assertEq(aaveStrat.principal(), principalBefore, "principal unchanged after failed emergency withdraw");
        assertEq(aaveVault.bufferBalance(), 0, "vault received no emergency dust after revert");
        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "strategy kept no idle dust after revert");
    }

    // =================================================================
    //   Non-standard Aave accounting-index loss reflects immediately in the strategy estimate
    // =================================================================

    function test_LossReflectedInEstimate() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        uint256 estimatedBefore = aaveStrat.estimatedTotalUnderlying();

        // Halve the mock liquidityIndex -> non-standard accounting-index loss;
        // real Aave reserve deficits do not normally propagate this way.
        pool.setLiquidityIndex(5e26);

        assertLt(aaveStrat.estimatedTotalUnderlying(), estimatedBefore, "estimated dropped after loss");
        assertLt(aaveVault.totalUnderlying(), 10e8, "vault total reflects loss immediately");
    }

    // =================================================================
    //   Vault totalUnderlying reflects a non-standard Aave accounting-index loss immediately
    // =================================================================

    function test_VaultTotalUnderlyingReflectsLossImmediately() public {
        (CollateralVault aaveVault,, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        uint256 totalBefore = aaveVault.totalUnderlying();
        pool.setLiquidityIndex(8e26); // 20% non-standard accounting-index loss
        uint256 totalAfter = aaveVault.totalUnderlying();

        assertLt(totalAfter, totalBefore, "totalUnderlying dropped post-loss");
    }

    function test_SendToVault_AaveWithdrawalCreditsNetUnderlyingReceipt() public {
        SenderFeeMockERC20 aaveU = new SenderFeeMockERC20("Aave Fee WBTC", "aFeeWBTCu", 8);
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool) = _deployAaveSetupWithUnderlying(aaveU);
        aaveU.setFeeSender(address(pool.aToken()));

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        uint256 principalBefore = aaveStrat.principal();
        uint256 expectedReceived = principalBefore - ((principalBefore * aaveU.FEE_BPS()) / aaveU.BPS());

        uint256 sent = aaveStrat.sendToVault(principalBefore);

        assertEq(sent, expectedReceived, "vault received net Aave withdrawal");
        assertEq(aaveU.balanceOf(address(aaveVault)), expectedReceived, "vault buffer holds net receipt");
        assertEq(aaveVault.totalUnderlying(), expectedReceived, "burned transfer fee is not counted as backing");
        assertEq(aaveStrat.principal(), principalBefore - expectedReceived, "residual principal reflects loss");
    }

    function test_SendToVault_CapsAaveWithdrawalToLiquidUnderlying() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        address borrower = makeAddr("aaveBorrower");
        vm.prank(address(pool.aToken()));
        aaveU.transfer(borrower, 6e8);

        uint256 sent = aaveStrat.sendToVault(10e8);

        assertEq(sent, 4e8, "sent only liquid Aave liquidity");
        assertEq(aaveU.balanceOf(address(aaveVault)), 4e8, "vault received liquid portion");
        assertEq(aaveStrat.principal(), 6e8, "principal reduced only by receipt");
        assertEq(aaveStrat.estimatedTotalUnderlying(), 6e8, "remaining Aave accounting value stays tracked");
        assertEq(aaveVault.totalUnderlying(), 10e8, "utilization is not treated as solvency loss");

        assertEq(aaveStrat.sendToVault(6e8), 0, "no revert when no liquid Aave liquidity remains");
    }

    // =================================================================
    //   emergencyWithdrawFromAave drains liquid Aave value, accounts returned principal, and pushes to Vault
    // =================================================================

    function test_EmergencyWithdrawFromAave_DrainsResetsScaleAndPushesToVault() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        assertGt(aaveStrat.estimatedTotalUnderlying(), 0, "strategy holds Aave position pre-call");

        uint256 vaultBufferBefore = aaveVault.bufferBalance();

        vm.prank(admin); // owner of the strategy
        aaveStrat.emergencyWithdrawFromAave();

        // Aave position drained: estimate is 0 (both _ownScaledBalance and aave scaledBalanceOf are 0).
        assertEq(aaveStrat.estimatedTotalUnderlying(), 0, "estimated reset to zero");
        // Recovered underlying is pushed to the Vault in the same transaction.
        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "underlying not left idle in strategy");
        assertEq(aaveU.balanceOf(address(aaveVault)), vaultBufferBefore + 10e8, "underlying returned to vault");
        assertEq(aaveVault.bufferBalance(), vaultBufferBefore + 10e8, "underlying returned to vault buffer");
        assertEq(aaveStrat.principal(), 0, "returned principal accounted");
        (uint256 cachedValue,, bool cacheInitialized) = aaveVault.strategyValuationCaches(IStrategy(address(aaveStrat)));
        assertFalse(cacheInitialized, "exhausted historical estimate is invalidated");
        assertEq(cachedValue, 0, "valuation cache reduced after emergency push");
        pool; // silence unused-var warning
    }

    function test_EmergencyWithdrawFromAave_PartialWhenReserveIlliquid() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        address borrower = makeAddr("aaveBorrower");
        vm.prank(address(pool.aToken()));
        aaveU.transfer(borrower, 7e8);

        vm.prank(admin);
        uint256 sent = aaveStrat.emergencyWithdrawFromAave();

        assertEq(sent, 3e8, "emergency withdraw drains only liquid reserve");
        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "underlying not left idle in strategy");
        assertEq(aaveU.balanceOf(address(aaveVault)), 3e8, "liquid reserve returned to vault");
        assertEq(aaveStrat.principal(), 7e8, "emergency recovery accounts returned principal");
        assertEq(aaveStrat.estimatedTotalUnderlying(), 7e8, "illiquid accounting value remains tracked");
        assertEq(aaveVault.totalUnderlying(), 10e8, "partial utilization is not treated as loss");
    }

    function test_EmergencyWithdrawFromAave_WriteoffResidualAfterPartialRecovery() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat, MockAavePool pool, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        address borrower = makeAddr("aaveBorrower");
        vm.prank(address(pool.aToken()));
        aaveU.transfer(borrower, 7e8);

        vm.prank(admin);
        aaveStrat.emergencyWithdrawFromAave();

        aaveVault.emergencyDisableStrategy(IStrategy(address(aaveStrat)));
        aaveVault.writeoffStrategyPrincipal(IStrategy(address(aaveStrat)), 7e8, 0);

        assertEq(aaveStrat.principal(), 0, "residual principal written off");
        assertEq(aaveVault.totalUnderlying(), 3e8, "only recovered buffer remains counted");
        assertEq(_lens().backingShortfall(ICollateralVault(address(aaveVault))), 7e8, "writeoff exposes confirmed residual loss");
    }

    function test_EmergencyWithdrawFromAave_DoesNotTransientlyDiscountBacking() public {
        (CollateralVault aaveVault, AaveV3Strategy aaveStrat,, MockERC20 aaveU) = _deployAaveSetup();

        _depositAndAllocate(aaveVault, aaveU, 10e8);

        assertEq(aaveVault.totalUnderlying(), 10e8, "fully accounted before emergency");
        assertEq(aaveVault.backingRatio(), 1e18, "fully backed before emergency");

        vm.prank(admin);
        aaveStrat.emergencyWithdrawFromAave();

        assertEq(aaveU.balanceOf(address(aaveStrat)), 0, "funds are not left idle in strategy");
        assertEq(aaveStrat.estimatedTotalUnderlying(), 0, "idle strategy funds are not counted as Aave AUM");
        assertEq(aaveVault.totalUnderlying(), 10e8, "vault still accounts recovered funds");
        assertEq(aaveVault.backingRatio(), 1e18, "oracle-visible backing never discounts recoverable funds");
    }
}
