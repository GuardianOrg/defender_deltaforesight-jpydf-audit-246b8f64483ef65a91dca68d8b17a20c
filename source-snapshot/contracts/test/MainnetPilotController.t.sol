// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    IMainnetPilotDToken,
    IMainnetPilotInterestRouter,
    MainnetPilotController
} from "script/MainnetPilotController.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ICollateralVault} from "src/Interfaces/ICollateralVault.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {LatestTroveData} from "src/Types/LatestTroveData.sol";

contract PilotMockToken is ERC20 {
    uint8 private immutable _tokenDecimals;

    constructor(string memory _name, string memory _symbol, uint8 decimals_) ERC20(_name, _symbol) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }
}

contract PilotMockDToken is ERC20 {
    IERC20 public immutable underlying;
    address public owner;
    address public pendingOwner;
    address public vault;
    uint256 public cap;

    constructor(IERC20 _underlying, address _owner, string memory _symbol) ERC20(_symbol, _symbol) {
        underlying = _underlying;
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function transferOwnership(address _pendingOwner) external onlyOwner {
        pendingOwner = _pendingOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "pending owner");
        owner = msg.sender;
        pendingOwner = address(0);
    }

    function setCap(uint256 _cap) external onlyOwner {
        cap = _cap;
    }

    function mint(address _account, uint256 _amount) external {
        require(msg.sender == vault, "vault");
        require(totalSupply() + _amount <= cap, "cap");
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        require(msg.sender == vault, "vault");
        _burn(_account, _amount);
    }
}

contract PilotMockVault {
    IERC20 public immutable underlying;
    PilotMockDToken public immutable dToken;
    bool public failDeposit;
    uint256 public pendingWithdrawals;
    IStrategy[] private _strategies;
    mapping(IStrategy => ICollateralVault.StrategyConfig) public strategyConfigs;

    constructor(IERC20 _underlying, PilotMockDToken _dToken) {
        underlying = _underlying;
        dToken = _dToken;
    }

    function setFailDeposit(bool _failDeposit) external {
        failDeposit = _failDeposit;
    }

    function addStrategy(IStrategy _strategy) external {
        _strategies.push(_strategy);
        strategyConfigs[_strategy] = ICollateralVault.StrategyConfig({enabled: true, weightBps: 5_000, cap: 100e6});
    }

    function updateStrategy(IStrategy _strategy, uint256 _weightBps, uint256 _cap, bool _enabled) external {
        strategyConfigs[_strategy] =
            ICollateralVault.StrategyConfig({enabled: _enabled, weightBps: _weightBps, cap: _cap});
    }

    function getStrategiesCount() external view returns (uint256) {
        return _strategies.length;
    }

    function strategies(uint256 _index) external view returns (IStrategy) {
        return _strategies[_index];
    }

    function deposit(uint256 _amount) external returns (uint256 minted) {
        if (failDeposit) revert("deposit failed");
        require(underlying.transferFrom(msg.sender, address(this), _amount));
        minted = _amount * 1e12;
        dToken.mint(msg.sender, minted);
    }

    function redeem(uint256 _amount, address _receiver) external returns (uint256 received, uint256 requestId) {
        dToken.burn(msg.sender, _amount);
        received = _amount / 1e12;
        require(underlying.transfer(_receiver, received));
        return (received, 0);
    }

    function bufferBalance() external view returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function totalUnderlying() external view returns (uint256) {
        return underlying.balanceOf(address(this));
    }
}

contract PilotMockStrategy {
    address public immutable underlying;
    address public owner;
    address public pendingOwner;
    uint256 public principal;
    uint256 public estimatedTotalUnderlying;

    constructor(address _underlying) {
        underlying = _underlying;
        owner = msg.sender;
    }

    function setBalances(uint256 _principal, uint256 _estimated) external {
        principal = _principal;
        estimatedTotalUnderlying = _estimated;
    }
}

contract PilotMockRouter {
    IERC20 public immutable jpydfToken;
    address public owner;
    address public pendingOwner;
    address public recipient;

    constructor(IERC20 _jpydfToken, address _recipient) {
        jpydfToken = _jpydfToken;
        owner = msg.sender;
        recipient = _recipient;
    }

    function setRecipient(address _recipient) external {
        recipient = _recipient;
    }

    function route() external returns (uint256 amount) {
        amount = jpydfToken.balanceOf(address(this));
        if (amount != 0) require(jpydfToken.transfer(recipient, amount));
    }
}

contract PilotMockTroveManager {
    address public borrowerOperations;
    address public immutable stabilityPool;
    uint256 public count;
    uint256 public debt;
    ITroveManager.Status public status;

    constructor(address _stabilityPool) {
        stabilityPool = _stabilityPool;
    }

    function setBorrowerOperations(address _borrowerOperations) external {
        borrowerOperations = _borrowerOperations;
    }

    function open(uint256 _debt) external {
        count = 1;
        debt = _debt;
        status = ITroveManager.Status.active;
    }

    function setDebt(uint256 _debt) external {
        debt = _debt;
    }

    function close() external {
        count = 0;
        debt = 0;
        status = ITroveManager.Status.closedByOwner;
    }

    function getTroveIdsCount() external view returns (uint256) {
        return count;
    }

    function getTroveStatus(uint256) external view returns (ITroveManager.Status) {
        return status;
    }

    function getLatestTroveData(uint256) external view returns (LatestTroveData memory trove) {
        trove.entireDebt = debt;
    }
}

contract PilotMockBorrowerOperations {
    PilotMockToken public immutable jpydf;
    PilotMockTroveManager public immutable troveManager;
    address public immutable router;
    address public removeManager;
    address public receiver;
    uint256 public pendingInterest;
    uint256 public repayResidual;

    constructor(PilotMockToken _jpydf, PilotMockTroveManager _troveManager, address _router) {
        jpydf = _jpydf;
        troveManager = _troveManager;
        router = _router;
    }

    function configureTrove(address _removeManager, address _receiver, uint256 _pendingInterest) external {
        removeManager = _removeManager;
        receiver = _receiver;
        pendingInterest = _pendingInterest;
    }

    function removeManagerReceiverOf(uint256) external view returns (address, address) {
        return (removeManager, receiver);
    }

    function setRepayResidual(uint256 _repayResidual) external {
        repayResidual = _repayResidual;
    }

    function repayJpydf(uint256, uint256 _amount) external {
        uint256 residual = repayResidual;
        uint256 actualRepayment = _amount - residual;
        jpydf.burn(msg.sender, actualRepayment);
        troveManager.setDebt(troveManager.debt() - actualRepayment);
        if (residual != 0) repayResidual = 0;
        if (pendingInterest != 0) {
            jpydf.mint(router, pendingInterest);
            pendingInterest = 0;
        }
    }

    function closeTrove(uint256) external {
        uint256 debt = troveManager.debt();
        jpydf.burn(msg.sender, debt);
        uint256 roundingDust = jpydf.balanceOf(msg.sender);
        if (roundingDust != 0) jpydf.burn(msg.sender, roundingDust);
        troveManager.close();
    }
}

contract MainnetPilotControllerTest is Test {
    uint256 private constant TROVE_ID = 7;
    uint256 private constant PRODUCTION_DUSDC_CAP = 627_676_740192561561589913;
    uint256 private constant PRINCIPAL = 1_000e18;
    uint256 private constant UPFRONT_FEE = 100e18;
    uint256 private constant PENDING_INTEREST = 5e18;

    PilotMockToken private usdc;
    PilotMockToken private jpydf;
    PilotMockDToken private dUsdc;
    PilotMockDToken[8] private dTokens;
    PilotMockVault private vault;
    PilotMockStrategy[2] private strategies;
    PilotMockRouter private router;
    PilotMockTroveManager private troveManager;
    PilotMockBorrowerOperations private borrowerOperations;
    MainnetPilotController private controller;
    address private stabilityPool;

    function setUp() external {
        vm.chainId(1);
        stabilityPool = makeAddr("stabilityPool");
        vm.etch(stabilityPool, hex"00");

        usdc = new PilotMockToken("USDC", "USDC", 6);
        jpydf = new PilotMockToken("JPYdf", "JPYDF", 18);
        for (uint256 i; i < 8; ++i) {
            dTokens[i] =
                new PilotMockDToken(i == 1 ? IERC20(address(usdc)) : IERC20(address(jpydf)), address(this), "d");
        }
        dUsdc = dTokens[1];
        vault = new PilotMockVault(IERC20(address(usdc)), dUsdc);
        dUsdc.setVault(address(vault));
        strategies[0] = new PilotMockStrategy(address(usdc));
        strategies[1] = new PilotMockStrategy(address(usdc));
        vault.addStrategy(IStrategy(address(strategies[0])));
        vault.addStrategy(IStrategy(address(strategies[1])));
        router = new PilotMockRouter(IERC20(address(jpydf)), address(this));
        troveManager = new PilotMockTroveManager(stabilityPool);
        borrowerOperations = new PilotMockBorrowerOperations(jpydf, troveManager, address(router));
        troveManager.setBorrowerOperations(address(borrowerOperations));

        IMainnetPilotDToken[] memory controllerDTokens = new IMainnetPilotDToken[](8);
        for (uint256 i; i < 8; ++i) {
            controllerDTokens[i] = IMainnetPilotDToken(address(dTokens[i]));
        }
        IStrategy[] memory controllerStrategies = new IStrategy[](2);
        controllerStrategies[0] = IStrategy(address(strategies[0]));
        controllerStrategies[1] = IStrategy(address(strategies[1]));

        MainnetPilotController.PilotConfiguration memory config = MainnetPilotController.PilotConfiguration({
            pilotOwner: address(this),
            usdc: IERC20(address(usdc)),
            jpydfToken: IERC20(address(jpydf)),
            dUsdc: IMainnetPilotDToken(address(dUsdc)),
            usdcVault: ICollateralVault(address(vault)),
            borrowerOperations: IBorrowerOperations(address(borrowerOperations)),
            troveManager: ITroveManager(address(troveManager)),
            stabilityPool: stabilityPool,
            interestRouter: IMainnetPilotInterestRouter(address(router)),
            dTokens: controllerDTokens,
            strategies: controllerStrategies
        });
        controller = new MainnetPilotController(config);

        for (uint256 i; i < 8; ++i) {
            dTokens[i].transferOwnership(address(controller));
        }
        controller.acceptDTokenOwnerships();
        borrowerOperations.configureTrove(address(controller), address(this), PENDING_INTEREST);
    }

    function testProductionCapWindowOpensOnceAndFreezesPermanently() external {
        _openTestWindow();

        assertEq(dUsdc.cap(), PRODUCTION_DUSDC_CAP);
        assertEq(controller.testWindowCap(), PRODUCTION_DUSDC_CAP);
        assertTrue(controller.testWindowOpened());
        vm.expectRevert(MainnetPilotController.MainnetPilotController__InvalidState.selector);
        controller.openTestWindow(PRODUCTION_DUSDC_CAP);

        controller.freezeTestWindow();
        assertEq(dUsdc.cap(), 0);
        assertTrue(controller.testWindowFrozen());

        vm.expectRevert(MainnetPilotController.MainnetPilotController__InvalidState.selector);
        controller.freezeTestWindow();
    }

    function testOnlyPilotOwnerCanOpenOrFreezeTestWindow() external {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(MainnetPilotController.MainnetPilotController__Unauthorized.selector);
        controller.openTestWindow(PRODUCTION_DUSDC_CAP);

        _openTestWindow();
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(MainnetPilotController.MainnetPilotController__Unauthorized.selector);
        controller.freezeTestWindow();
    }

    function testZeroCapCannotOpenTestWindow() external {
        vm.expectRevert(MainnetPilotController.MainnetPilotController__InvalidCap.selector);
        controller.openTestWindow(0);

        assertEq(dUsdc.cap(), 0);
        assertFalse(controller.testWindowOpened());
    }

    function testMultipleFrontendWalletsCanDepositBeforeFreezeAndRedeemAfterFreeze() external {
        address testerA = makeAddr("testerA");
        address testerB = makeAddr("testerB");
        _openTestWindow();

        _depositUsdc(testerA, 10e6);
        _depositUsdc(testerB, 15e6);

        assertEq(dUsdc.balanceOf(testerA), 10e18);
        assertEq(dUsdc.balanceOf(testerB), 15e18);
        assertEq(dUsdc.totalSupply(), 25e18);

        controller.freezeTestWindow();

        address lateTester = makeAddr("lateTester");
        usdc.mint(lateTester, 1e6);
        vm.startPrank(lateTester);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(bytes("cap"));
        vault.deposit(1e6);
        vm.stopPrank();

        vm.prank(testerA);
        vault.redeem(10e18, testerA);
        vm.prank(testerB);
        vault.redeem(15e18, testerB);

        assertEq(dUsdc.totalSupply(), 0);
        assertEq(usdc.balanceOf(testerA), 10e6);
        assertEq(usdc.balanceOf(testerB), 15e6);
    }

    function testUnsolicitedUsdcIsSweptWhenWindowOpens() external {
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 1);
        vm.prank(attacker);
        usdc.transfer(address(controller), 1);

        _openTestWindow();

        assertEq(usdc.balanceOf(address(controller)), 0);
        assertEq(usdc.balanceOf(address(this)), 1);
        assertEq(dUsdc.cap(), PRODUCTION_DUSDC_CAP);
    }

    function testSettlesAccruedInterestAndClosesLastTroveWithZeroSupply() external {
        _openAndFreezeTestWindow();
        _openMockTrove();

        jpydf.approve(address(controller), type(uint256).max);
        controller.settleAndClose(TROVE_ID);

        assertEq(jpydf.totalSupply(), 0);
        assertEq(jpydf.balanceOf(address(controller)), 0);
        assertEq(jpydf.balanceOf(address(router)), 0);
        assertEq(troveManager.getTroveIdsCount(), 0);
        assertEq(uint256(troveManager.getTroveStatus(TROVE_ID)), uint256(ITroveManager.Status.closedByOwner));
        assertTrue(controller.troveClosed());
    }

    function testRetriesOneMeasuredAggregateInterestResidualBeforeClose() external {
        _openAndFreezeTestWindow();
        _openMockTrove();
        borrowerOperations.setRepayResidual(3);

        jpydf.approve(address(controller), type(uint256).max);
        controller.settleAndClose(TROVE_ID);

        assertEq(jpydf.totalSupply(), 0);
        assertEq(troveManager.getTroveIdsCount(), 0);
        assertTrue(controller.troveClosed());
    }

    function testSettlesMaximumSupplyRoundingDustDuringLastTroveClose() external {
        _openAndFreezeTestWindow();
        _openMockTrove();
        jpydf.mint(address(this), 1e6);

        jpydf.approve(address(controller), type(uint256).max);
        controller.settleAndClose(TROVE_ID);

        assertEq(jpydf.totalSupply(), 0);
        assertEq(jpydf.balanceOf(address(controller)), 0);
        assertEq(troveManager.getTroveIdsCount(), 0);
    }

    function testRejectsMaterialSupplyMismatchBeforeLastTroveClose() external {
        _openAndFreezeTestWindow();
        _openMockTrove();
        jpydf.mint(address(this), 1e6 + 1);
        jpydf.approve(address(controller), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                MainnetPilotController.MainnetPilotController__UnexpectedAmount.selector, PRINCIPAL, PRINCIPAL + 1e6 + 1
            )
        );
        controller.settleAndClose(TROVE_ID);

        assertEq(troveManager.getTroveIdsCount(), 1);
        assertEq(uint256(troveManager.getTroveStatus(TROVE_ID)), uint256(ITroveManager.Status.active));
    }

    function testNonZeroStabilityPoolBalanceBlocksSettlement() external {
        _openAndFreezeTestWindow();
        _openMockTrove();
        jpydf.mint(stabilityPool, 1);
        jpydf.approve(address(controller), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                MainnetPilotController.MainnetPilotController__NonZeroState.selector, stabilityPool, uint256(1)
            )
        );
        controller.settleAndClose(TROVE_ID);
    }

    function testChangedRouterRecipientBlocksSettlementUntilRestored() external {
        _openAndFreezeTestWindow();
        _openMockTrove();
        jpydf.approve(address(controller), type(uint256).max);
        router.setRecipient(makeAddr("wrongRecipient"));

        vm.expectRevert(MainnetPilotController.MainnetPilotController__BadWiring.selector);
        controller.settleAndClose(TROVE_ID);

        router.setRecipient(address(this));
        controller.settleAndClose(TROVE_ID);
        assertTrue(controller.troveClosed());
        assertEq(jpydf.totalSupply(), 0);
    }

    function testFinalizeRejectsResidualStrategyStateThenPermanentlyFreezes() external {
        _completeLifecycleBeforeFinalize();
        strategies[0].setBalances(1, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                MainnetPilotController.MainnetPilotController__NonZeroState.selector, address(strategies[0]), uint256(1)
            )
        );
        controller.finalize();

        strategies[0].setBalances(0, 0);
        controller.finalize();
        assertTrue(controller.finalized());

        vm.expectRevert(MainnetPilotController.MainnetPilotController__InvalidState.selector);
        controller.finalize();
    }

    function testFinalizeRejectsActiveStrategyConfiguration() external {
        _completeLifecycleBeforeStrategyFreeze();

        vm.expectRevert(
            abi.encodeWithSelector(
                MainnetPilotController.MainnetPilotController__ActiveStrategyConfiguration.selector,
                address(strategies[0]),
                true,
                uint256(5_000),
                uint256(100e6)
            )
        );
        controller.finalize();

        _freezeStrategyConfigurations();
        controller.finalize();
        assertTrue(controller.finalized());
    }

    function testFinalizeAcceptsZeroStateAfterFrontendUsersSelfClose() external {
        _openAndFreezeTestWindow();
        _freezeStrategyConfigurations();

        controller.finalize();

        assertTrue(controller.finalized());
        assertFalse(controller.troveClosed());
    }

    function testUnsolicitedUsdcIsSweptDuringFinalize() external {
        _completeLifecycleBeforeFinalize();
        uint256 ownerBalanceBefore = usdc.balanceOf(address(this));
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 1);
        vm.prank(attacker);
        usdc.transfer(address(controller), 1);

        controller.finalize();

        assertTrue(controller.finalized());
        assertEq(usdc.balanceOf(address(controller)), 0);
        assertEq(usdc.balanceOf(address(this)), ownerBalanceBefore + 1);
    }

    function testUnsolicitedVaultUsdcDoesNotBlockFinalize() external {
        _completeLifecycleBeforeFinalize();
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 1);
        vm.prank(attacker);
        usdc.transfer(address(vault), 1);

        controller.finalize();

        assertTrue(controller.finalized());
        assertEq(vault.bufferBalance(), 1);
    }

    function testUnsolicitedStrategyAssetsDoNotBlockFinalize() external {
        _completeLifecycleBeforeFinalize();
        strategies[0].setBalances(0, 1);

        controller.finalize();

        assertTrue(controller.finalized());
        assertEq(strategies[0].principal(), 0);
        assertEq(strategies[0].estimatedTotalUnderlying(), 1);
    }

    function _openTestWindow() private {
        controller.openTestWindow(PRODUCTION_DUSDC_CAP);
    }

    function _openAndFreezeTestWindow() private {
        _openTestWindow();
        controller.freezeTestWindow();
    }

    function _depositUsdc(address _tester, uint256 _amount) private {
        usdc.mint(_tester, _amount);
        vm.startPrank(_tester);
        usdc.approve(address(vault), _amount);
        vault.deposit(_amount);
        vm.stopPrank();
    }

    function _openMockTrove() private {
        jpydf.mint(address(this), PRINCIPAL);
        jpydf.mint(address(router), UPFRONT_FEE);
        troveManager.open(PRINCIPAL + UPFRONT_FEE + PENDING_INTEREST);
    }

    function _completeLifecycleBeforeFinalize() private {
        _completeLifecycleBeforeStrategyFreeze();
        _freezeStrategyConfigurations();
    }

    function _completeLifecycleBeforeStrategyFreeze() private {
        _openAndFreezeTestWindow();
        _openMockTrove();
        jpydf.approve(address(controller), type(uint256).max);
        controller.settleAndClose(TROVE_ID);
    }

    function _freezeStrategyConfigurations() private {
        for (uint256 i; i < 2; ++i) {
            vault.updateStrategy(IStrategy(address(strategies[i])), 0, 0, false);
        }
    }
}
