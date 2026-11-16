// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../../src/CollateralVault.sol";
import "../../src/DToken.sol";
import "../../src/Interfaces/IDToken.sol";
import "../../src/Interfaces/IStrategy.sol";
import "../../src/Strategies/archive/AsyncRequestStrategy.sol";
import "../../src/Strategies/archive/LidoStrategy.sol";
import "../TestContracts/WETH.sol";
import "../mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract MockStETH is ILido {
    using Math for uint256;

    string public constant name = "Mock stETH";
    string public constant symbol = "mstETH";
    uint8 public constant decimals = 18;

    uint256 internal _totalPooledEther;
    uint256 internal _totalShares;
    mapping(address => uint256) internal _shares;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public lastReferral;

    function totalSupply() external view override returns (uint256) {
        return _totalPooledEther;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return getPooledEthByShares(_shares[account]);
    }

    function sharesOf(address account) external view override returns (uint256) {
        return _shares[account];
    }

    function getPooledEthByShares(uint256 sharesAmount) public view override returns (uint256) {
        if (_totalShares == 0) return sharesAmount;
        return Math.mulDiv(sharesAmount, _totalPooledEther, _totalShares);
    }

    function getSharesByPooledEth(uint256 amount) public view returns (uint256) {
        return _sharesByPooledEth(amount, Math.Rounding.Down);
    }

    function submit(address referral_) external payable override returns (uint256) {
        lastReferral = referral_;
        uint256 sharesToMint = _sharesByPooledEth(msg.value, Math.Rounding.Down);
        require(sharesToMint != 0 || msg.value == 0, "MockStETH: zero shares");

        _totalPooledEther += msg.value;
        _totalShares += sharesToMint;
        _shares[msg.sender] += sharesToMint;

        emit Transfer(address(0), msg.sender, msg.value);
        return sharesToMint;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transferPooled(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "MockStETH: insufficient allowance");
            allowance[from][msg.sender] = currentAllowance - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transferPooled(from, to, amount);
        return true;
    }

    function mintPooled(address to, uint256 amount) external {
        uint256 sharesToMint = _sharesByPooledEth(amount, Math.Rounding.Down);
        require(sharesToMint != 0 || amount == 0, "MockStETH: zero shares");

        _totalPooledEther += amount;
        _totalShares += sharesToMint;
        _shares[to] += sharesToMint;
        emit Transfer(address(0), to, amount);
    }

    function addRewards(uint256 amount) external {
        _totalPooledEther += amount;
    }

    function _transferPooled(address from, address to, uint256 amount) internal {
        require(to != address(0), "MockStETH: zero recipient");
        uint256 sharesToMove = _sharesByPooledEth(amount, Math.Rounding.Up);
        require(_shares[from] >= sharesToMove, "MockStETH: insufficient balance");

        _shares[from] -= sharesToMove;
        _shares[to] += sharesToMove;
        emit Transfer(from, to, amount);
    }

    function _sharesByPooledEth(uint256 amount, Math.Rounding rounding) internal view returns (uint256) {
        if (_totalShares == 0 || _totalPooledEther == 0) return amount;
        return Math.mulDiv(amount, _totalShares, _totalPooledEther, rounding);
    }
}

contract MockWstETH is IWstETH {
    using SafeERC20 for IERC20;

    string public constant name = "Mock wstETH";
    string public constant symbol = "mwstETH";
    uint8 public constant decimals = 18;

    MockStETH public immutable stETHToken;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(MockStETH stETHMock) {
        stETHToken = stETHMock;
    }

    function wrap(uint256 stETHAmount) external virtual override returns (uint256 wstETHAmount) {
        wstETHAmount = getWstETHByStETH(stETHAmount);
        require(wstETHAmount != 0 || stETHAmount == 0, "MockWstETH: zero amount");

        IERC20(address(stETHToken)).safeTransferFrom(msg.sender, address(this), stETHAmount);
        _mint(msg.sender, wstETHAmount);
    }

    function unwrap(uint256 wstETHAmount) external override returns (uint256 stETHAmount) {
        stETHAmount = getStETHByWstETH(wstETHAmount);
        _burn(msg.sender, wstETHAmount);
        IERC20(address(stETHToken)).safeTransfer(msg.sender, stETHAmount);
    }

    function stETH() external view override returns (address) {
        return address(stETHToken);
    }

    function getStETHByWstETH(uint256 wstETHAmount) public view override returns (uint256) {
        return stETHToken.getPooledEthByShares(wstETHAmount);
    }

    function getWstETHByStETH(uint256 stETHAmount) public view override returns (uint256) {
        return stETHToken.getSharesByPooledEth(stETHAmount);
    }

    function stEthPerToken() external view override returns (uint256) {
        return getStETHByWstETH(1 ether);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "MockWstETH: insufficient allowance");
            allowance[from][msg.sender] = currentAllowance - amount;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, amount);
        return true;
    }

    function mintShares(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "MockWstETH: zero recipient");
        require(balanceOf[from] >= amount, "MockWstETH: insufficient balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "MockWstETH: insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

contract LyingWstETH is MockWstETH {
    using SafeERC20 for IERC20;

    constructor(MockStETH stETHToken) MockWstETH(stETHToken) {}

    function wrap(uint256 stETHAmount) external override returns (uint256 wstETHAmount) {
        wstETHAmount = getWstETHByStETH(stETHAmount);
        require(wstETHAmount != 0 || stETHAmount == 0, "MockWstETH: zero amount");

        IERC20(address(stETHToken)).safeTransferFrom(msg.sender, address(this), stETHAmount);
        _mint(msg.sender, wstETHAmount);
        return wstETHAmount + 1;
    }
}

contract MockWithdrawalQueue is IWithdrawalQueueERC721 {
    using SafeERC20 for IERC20;

    struct Request {
        uint256 amount;
        bool finalized;
        bool claimed;
        uint256 claimableEth;
        address owner;
    }

    MockWstETH public immutable wstETH;
    uint256 public immutable minStETHAmount;
    uint256 public immutable maxStETHAmount;
    uint256 public nextRequestId = 1;
    uint256 public singleClaimCalls;
    uint256 public batchClaimCalls;
    bool public requestShouldRevert;
    address public requestOwnerOverride;
    mapping(uint256 => Request) public requests;

    constructor(MockWstETH wstETHToken, uint256 minStETHAmount_, uint256 maxStETHAmount_) {
        wstETH = wstETHToken;
        minStETHAmount = minStETHAmount_;
        maxStETHAmount = maxStETHAmount_;
    }

    receive() external payable {}

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view override returns (uint256) {
        return minStETHAmount;
    }

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view override returns (uint256) {
        return maxStETHAmount;
    }

    function requestWithdrawalsWstETH(uint256[] calldata wstETHAmounts, address owner)
        external
        override
        returns (uint256[] memory requestIds)
    {
        require(!requestShouldRevert, "MockWQ: request paused");

        requestIds = new uint256[](wstETHAmounts.length);
        for (uint256 requestIndex = 0; requestIndex < wstETHAmounts.length; requestIndex++) {
            uint256 stETHAmount = wstETH.getStETHByWstETH(wstETHAmounts[requestIndex]);
            require(stETHAmount >= minStETHAmount, "MockWQ: below min");
            require(stETHAmount <= maxStETHAmount, "MockWQ: above max");
            IERC20(address(wstETH)).safeTransferFrom(msg.sender, address(this), wstETHAmounts[requestIndex]);

            uint256 requestId = nextRequestId++;
            address requestOwner = requestOwnerOverride == address(0) ? owner : requestOwnerOverride;
            requests[requestId] =
                Request({amount: stETHAmount, finalized: false, claimed: false, claimableEth: 0, owner: requestOwner});
            requestIds[requestIndex] = requestId;
        }
    }

    function setRequestOwnerOverride(address requestOwner) external {
        requestOwnerOverride = requestOwner;
    }

    function ownerOf(uint256 requestId) external view override returns (address owner) {
        owner = requests[requestId].owner;
        require(owner != address(0), "MockWQ: unknown");
    }

    function setRequestShouldRevert(bool shouldRevert) external {
        requestShouldRevert = shouldRevert;
    }

    function finalize(uint256 requestId, uint256 claimableEth) external {
        Request storage request = requests[requestId];
        require(request.owner != address(0), "MockWQ: unknown");
        request.finalized = true;
        request.claimableEth = claimableEth;
    }

    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external override {
        require(requestIds.length == hints.length, "MockWQ: hints length");

        batchClaimCalls++;
        for (uint256 requestIndex = 0; requestIndex < requestIds.length; requestIndex++) {
            _claimWithdrawal(requestIds[requestIndex]);
        }
    }

    function claimWithdrawal(uint256 requestId) external override {
        singleClaimCalls++;
        _claimWithdrawal(requestId);
    }

    function _claimWithdrawal(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.owner == msg.sender, "MockWQ: not owner");
        require(request.finalized, "MockWQ: not finalized");
        require(!request.claimed, "MockWQ: claimed");

        request.claimed = true;
        (bool ok,) = payable(msg.sender).call{value: request.claimableEth}("");
        require(ok, "MockWQ: eth send failed");
    }
}

/// @title LidoStrategyTest - Phase 3b-2 async Lido strategy coverage.
contract LidoStrategyTest is Test {
    using stdStorage for StdStorage;

    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    address public admin;
    address public treasury;
    address public alice;
    address public referral;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        referral = makeAddr("referral");
    }

    function _deployLidoSetup()
        internal
        returns (
            CollateralVault collateralVault,
            LidoStrategy strategy,
            MockStETH stETHToken,
            MockWstETH wstETHToken,
            MockWithdrawalQueue withdrawalQueue,
            WETH9 wethToken
        )
    {
        wethToken = new WETH9();
        stETHToken = new MockStETH();
        wstETHToken = new MockWstETH(stETHToken);
        withdrawalQueue = new MockWithdrawalQueue(wstETHToken, 1 ether, 10 ether);

        (collateralVault, strategy) = _deployLidoSetupWithMocks(wethToken, stETHToken, wstETHToken, withdrawalQueue);
    }

    function _deployLidoSetupWithMocks(
        WETH9 wethToken,
        MockStETH stETHToken,
        MockWstETH wstETHToken,
        MockWithdrawalQueue withdrawalQueue
    ) internal returns (CollateralVault collateralVault, LidoStrategy strategy) {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(wethToken), true);
        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(wethToken)), IDToken(address(dToken)), treasury, admin
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        dToken.setTokenInfo("dWETH", "dWETH", IERC20MetadataUpgradeable(address(wethToken)));
        activateDTokenForTest(dToken);

        strategy = _deployLidoStrategy(collateralVault, wethToken, stETHToken, wstETHToken, withdrawalQueue);

        collateralVault.addToWhitelist(address(strategy));
        collateralVault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
    }

    function _deployLidoStrategy(
        CollateralVault collateralVault,
        WETH9 wethToken,
        MockStETH stETHToken,
        MockWstETH wstETHToken,
        MockWithdrawalQueue withdrawalQueue
    ) internal returns (LidoStrategy strategy) {
        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(collateralVault),
            IWETH(address(wethToken)),
            admin,
            admin,
            ILido(address(stETHToken)),
            IWstETH(address(wstETHToken)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            referral
        );
        strategy =
            LidoStrategy(payable(address(new ERC1967Proxy(address(strategyImplementation), strategyInitializer))));
    }

    function _depositAndAllocate(CollateralVault collateralVault, WETH9 wethToken, uint256 amount) internal {
        vm.deal(alice, amount);
        vm.startPrank(alice);
        wethToken.deposit{value: amount}();
        wethToken.approve(address(collateralVault), amount);
        collateralVault.deposit(amount);
        vm.stopPrank();

        collateralVault.setBufferConfig(0, 0);
        collateralVault.allocate();
    }

    function _donateWeth(WETH9 wethToken, address recipient, uint256 amount) internal {
        vm.deal(alice, amount);
        vm.startPrank(alice);
        wethToken.deposit{value: amount}();
        wethToken.transfer(recipient, amount);
        vm.stopPrank();
    }

    function _donateRawEth(address recipient, uint256 amount) internal {
        vm.deal(alice, amount);
        vm.prank(alice);
        (bool ok,) = payable(recipient).call{value: amount}("");
        assertTrue(ok, "raw ETH donation");
    }

    function _singleRequest(uint256 requestId) internal pure returns (uint256[] memory requestIds) {
        requestIds = new uint256[](1);
        requestIds[0] = requestId;
    }

    function _assertPendingAccounting(LidoStrategy strategy) internal view {
        uint256[] memory requestIds = strategy.getPendingRequestIds();

        assertEq(requestIds.length, strategy.pendingRequestCount(), "pending id count");

        uint256 pendingAmountSum;
        for (uint256 requestIndex = 0; requestIndex < requestIds.length; requestIndex++) {
            uint256 requestAmount = strategy.pendingWithdrawalAmountByRequestId(requestIds[requestIndex]);
            assertGt(requestAmount, 0, "pending request amount");
            pendingAmountSum += requestAmount;
        }

        assertEq(pendingAmountSum, strategy.pendingWithdrawAmount(), "pending amount sum");
    }

    function test_Initialize_RevertsOnZeroLido() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 1 ether, 10 ether);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(0)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            referral
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnZeroWithdrawalQueue() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(address(0)),
            referral
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnZeroWstETH() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 1 ether, 10 ether);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(0)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            referral
        );

        vm.expectRevert(BaseStrategy.ZeroAddress.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnMismatchedWstETHStETH() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockStETH otherStETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(otherStETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 1 ether, 10 ether);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            referral
        );

        vm.expectRevert(LidoStrategy.InvalidWstETHStETH.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnInvalidWithdrawalQueueBounds() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 0, 10 ether);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            referral
        );

        vm.expectRevert(LidoStrategy.InvalidWithdrawalQueueBounds.selector);
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_RevertsOnNonContractWithdrawalQueue() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);
        address withdrawalQueueEoa = makeAddr("withdrawalQueueEoa");

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(withdrawalQueueEoa),
            referral
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, withdrawalQueueEoa));
        new ERC1967Proxy(address(strategyImplementation), strategyInitializer);
    }

    function test_Initialize_AllowsZeroReferral() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        MockWstETH wstETH = new MockWstETH(stETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 1 ether, 10 ether);

        LidoStrategy strategyImplementation = new LidoStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            LidoStrategy.initialize.selector,
            address(this),
            IWETH(address(weth)),
            admin,
            admin,
            ILido(address(stETH)),
            IWstETH(address(wstETH)),
            IWithdrawalQueueERC721(address(withdrawalQueue)),
            address(0)
        );

        LidoStrategy strategy =
            LidoStrategy(payable(address(new ERC1967Proxy(address(strategyImplementation), strategyInitializer))));

        assertEq(strategy.referral(), address(0), "zero referral allowed");
    }

    function test_Initialize_ApprovesWithdrawalQueue() public {
        (, LidoStrategy strategy, MockStETH stETH, MockWstETH wstETH, MockWithdrawalQueue withdrawalQueue,) =
            _deployLidoSetup();

        assertEq(stETH.allowance(address(strategy), address(wstETH)), type(uint256).max, "stETH allowance");
        assertEq(wstETH.allowance(address(strategy), address(withdrawalQueue)), type(uint256).max, "wstETH allowance");
        assertEq(address(strategy.lido()), address(stETH), "lido fixed");
        assertEq(address(strategy.stETH()), address(stETH), "stETH fixed");
        assertEq(address(strategy.wstETH()), address(wstETH), "wstETH fixed");
        assertEq(address(strategy.withdrawalQueue()), address(withdrawalQueue), "withdrawalQueue fixed");
    }

    function test_Allocate_StakesWethIntoLidoAndTracksEstimate() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH, MockWstETH wstETH,, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);

        assertEq(weth.balanceOf(address(strategy)), 0, "strategy WETH deployed");
        assertEq(stETH.balanceOf(address(strategy)), 0, "strategy wrapped stETH");
        assertEq(wstETH.balanceOf(address(strategy)), 20 ether, "strategy received wstETH");
        assertEq(strategy.ownWstETH(), 20 ether, "own wstETH tracked");
        assertEq(strategy.pendingWithdrawAmount(), 0, "no pending");
        _assertPendingAccounting(strategy);
        assertEq(strategy.ownIdleUnderlying(), 0, "no own idle");
        assertEq(strategy.principal(), 20 ether, "principal");
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "estimated");
        assertEq(vault.totalUnderlying(), 20 ether, "vault conservative total");
    }

    function test_Allocate_RecoversAndSkipsWhenWstETHReturnDoesNotMatchBalanceDelta() public {
        WETH9 weth = new WETH9();
        MockStETH stETH = new MockStETH();
        LyingWstETH wstETH = new LyingWstETH(stETH);
        MockWithdrawalQueue withdrawalQueue = new MockWithdrawalQueue(wstETH, 1 ether, 10 ether);
        (CollateralVault vault, LidoStrategy strategy) =
            _deployLidoSetupWithMocks(weth, stETH, wstETH, withdrawalQueue);

        vm.deal(alice, 5 ether);
        vm.startPrank(alice);
        weth.deposit{value: 5 ether}();
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);

        vault.allocate();

        assertEq(vault.bufferBalance(), 5 ether, "rejected allocation returns to buffer");
        assertEq(weth.balanceOf(address(strategy)), 0, "strategy retains no idle WETH");
        assertEq(stETH.balanceOf(address(strategy)), 0, "inner submit effects rolled back");
        assertEq(wstETH.balanceOf(address(strategy)), 0, "inner wrap effects rolled back");
        assertEq(strategy.principal(), 0, "principal stays zero");
    }

    function test_SetReferral_AppliesToNextSubmit() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH,,, WETH9 weth) = _deployLidoSetup();
        address newReferral = makeAddr("newReferral");

        strategy.setReferral(newReferral);
        _depositAndAllocate(vault, weth, 5 ether);

        assertEq(strategy.referral(), newReferral, "referral stored");
        assertEq(stETH.lastReferral(), newReferral, "submit referral");
    }

    function test_SetReferral_AllowsZeroAddress() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH,,, WETH9 weth) = _deployLidoSetup();
        address newReferral = makeAddr("newReferral");

        strategy.setReferral(newReferral);
        strategy.setReferral(address(0));
        _depositAndAllocate(vault, weth, 5 ether);

        assertEq(strategy.referral(), address(0), "zero referral stored");
        assertEq(stETH.lastReferral(), address(0), "zero referral submitted");
    }

    function test_DonationDoesNotInflateRealizedYield() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH, MockWstETH wstETH,, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);

        uint256 yieldBefore = strategy.realizedYield();
        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        stETH.mintPooled(address(strategy), 5 ether);
        wstETH.mintShares(address(strategy), 5 ether);

        assertEq(strategy.realizedYield(), yieldBefore, "donation did not inflate realizedYield");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "donation ignored in estimate");
        assertEq(strategy.ownWstETH(), 20 ether, "own wstETH unchanged");
    }

    function test_WethDonationDoesNotInflateRealizedYieldOrPushAsProfit() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);

        uint256 estimatedBefore = strategy.estimatedTotalUnderlying();
        uint256 yieldBefore = strategy.realizedYield();
        _donateWeth(weth, address(strategy), 5 ether);

        assertEq(weth.balanceOf(address(strategy)), 5 ether, "donated WETH held");
        assertEq(strategy.ownIdleUnderlying(), 0, "donation is not own idle");
        assertEq(strategy.estimatedTotalUnderlying(), estimatedBefore, "donation ignored in estimate");
        assertEq(strategy.realizedYield(), yieldBefore, "donation ignored in yield");
        assertEq(strategy.sendProfitToVault(), 0, "donation not sent as yield");
        assertEq(vault.bufferBalance(), 0, "vault buffer unchanged");
        assertEq(weth.balanceOf(address(strategy)), 5 ether, "donation remains direct idle");
    }

    function test_RebaseYieldIsVisibleButNotWithdrawableUntilClaimed() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        stETH.addRewards(2 ether);

        assertEq(strategy.realizedYield(), 2 ether, "rebase yield visible");
        assertEq(strategy.sendProfitToVault(), 0, "no idle WETH yet");
        assertEq(strategy.principal(), 20 ether, "principal unchanged");
    }

    function test_SendToVault_UsesOnlyOwnClaimedWeth() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);

        uint256 sent = strategy.sendToVault(5 ether);

        assertEq(sent, 0, "nothing claimable yet");
        assertEq(vault.bufferBalance(), 0, "vault buffer unchanged");
        assertEq(strategy.principal(), 20 ether, "principal unchanged");
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "estimate unchanged");
    }

    function test_RequestLidoWithdrawal_SplitsTracksPendingAndKeepsPrincipal() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 30 ether);

        uint256 requested = 20_500_000_000_000_000_000;
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(requested);

        assertEq(requestIds.length, 3, "split into three requests");
        assertEq(strategy.pendingWithdrawAmount(), requested, "pending tracked");
        assertEq(strategy.pendingRequestCount(), 3, "request count");
        _assertPendingAccounting(strategy);
        assertEq(strategy.principal(), 30 ether, "principal unchanged");
        assertApproxEqAbs(strategy.ownWstETH(), 9_500_000_000_000_000_000, 2, "wstETH reduced");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 30 ether, 2, "pending remains in AUM");

        (uint256 firstAmount,,,, address firstOwner) = withdrawalQueue.requests(requestIds[0]);
        (uint256 secondAmount,,,, address secondOwner) = withdrawalQueue.requests(requestIds[1]);
        (uint256 thirdAmount,,,, address thirdOwner) = withdrawalQueue.requests(requestIds[2]);

        assertEq(firstAmount, 10 ether, "first max chunk");
        assertEq(secondAmount, 9_500_000_000_000_000_000, "adjusted chunk avoids dust");
        assertEq(thirdAmount, 1 ether, "final min chunk");
        assertEq(firstOwner, address(strategy), "first owner");
        assertEq(secondOwner, address(strategy), "second owner");
        assertEq(thirdOwner, address(strategy), "third owner");
    }

    function test_SetPendingWithdrawalValuationBps_DiscountsPendingLidoValue() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(8 ether);

        assertEq(strategy.pendingWithdrawalValuationBps(), 10_000, "default full pending valuation");
        assertTrue(strategy.pendingWithdrawalValuationBpsConfigured(), "valuation configured");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 20 ether, 2, "default pending valued at par");

        vault.pauseAllocation();
        vm.expectEmit(address(strategy));
        emit AsyncRequestStrategy.PendingWithdrawalValuationBpsUpdated(10_000, 5_000);
        strategy.setPendingWithdrawalValuationBps(5_000);

        assertEq(strategy.pendingWithdrawalValuationBps(), 5_000, "discount stored");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 16 ether, 2, "pending value discounted");
        assertApproxEqAbs(vault.totalUnderlying(), 16 ether, 2, "vault backing sees discount");

        vm.deal(address(withdrawalQueue), 7 ether);
        withdrawalQueue.finalize(requestIds[0], 7 ether);
        strategy.claimLidoWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 19 ether, 2, "claim actual replaces pending");
    }

    function test_SetPendingWithdrawalValuationBps_RevertsAboveDenominator() public {
        (, LidoStrategy strategy,,,,) = _deployLidoSetup();

        vm.expectRevert(
            abi.encodeWithSelector(AsyncRequestStrategy.InvalidPendingWithdrawalValuationBps.selector, 10_001)
        );
        strategy.setPendingWithdrawalValuationBps(10_001);
    }

    function test_PendingWithdrawalValuationBps_UnconfiguredStorageDefaultsToFullValue() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256 requested = 8 ether;
        strategy.requestLidoWithdrawal(requested);

        stdstore.target(address(strategy)).sig(strategy.pendingWithdrawalValuationBpsConfigured.selector).checked_write(
            false
        );

        assertFalse(strategy.pendingWithdrawalValuationBpsConfigured(), "simulated pre-upgrade storage");
        assertEq(strategy.pendingWithdrawalValuationBps(), 10_000, "effective default remains par");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 20 ether, 2, "pending still valued at par");

        vault.pauseAllocation();
        vm.expectEmit(address(strategy));
        emit AsyncRequestStrategy.PendingWithdrawalValuationBpsUpdated(10_000, 5_000);
        strategy.setPendingWithdrawalValuationBps(5_000);

        assertTrue(strategy.pendingWithdrawalValuationBpsConfigured(), "setter configures storage");
        assertEq(strategy.pendingWithdrawalValuationBps(), 5_000, "new bps stored");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 16 ether, 2, "pending discount applies");
    }

    function test_SetPendingWithdrawalValuationBps_RequiresWriteoffRole() public {
        (, LidoStrategy strategy,,,,) = _deployLidoSetup();

        vm.prank(alice);
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        strategy.setPendingWithdrawalValuationBps(5_000);
    }

    function test_SetPendingWithdrawalValuationBps_RevertsDiscountBeforeAllocationPause() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        strategy.requestLidoWithdrawal(8 ether);

        vm.expectRevert(AsyncRequestStrategy.PendingWithdrawalValuationNotPaused.selector);
        strategy.setPendingWithdrawalValuationBps(5_000);
    }

    function test_SetPendingWithdrawalValuationBps_AllowsRestoreAfterAllocationUnpause() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        strategy.requestLidoWithdrawal(8 ether);

        vault.pauseAllocation();
        strategy.setPendingWithdrawalValuationBps(5_000);
        vault.unpauseAllocation();

        strategy.setPendingWithdrawalValuationBps(10_000);

        assertEq(strategy.pendingWithdrawalValuationBps(), 10_000, "restored without allocation pause");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 20 ether, 2, "pending valued at par again");
    }

    function test_SetPendingWithdrawalValuationBps_RoundsPendingDustDown() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256 requested = 8 ether + 7;
        strategy.requestLidoWithdrawal(requested);
        vault.pauseAllocation();
        strategy.setPendingWithdrawalValuationBps(3_333);

        uint256 expected = (20 ether - requested) + Math.mulDiv(requested, 3_333, 10_000);

        assertEq(strategy.estimatedTotalUnderlying(), expected, "dust rounds down");
        assertEq(vault.totalUnderlying(), expected, "vault uses rounded-down estimate");

        strategy.setPendingWithdrawalValuationBps(0);
        assertTrue(strategy.pendingWithdrawalValuationBpsConfigured(), "zero bps configured");
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether - requested, "zero bps excludes pending");

        strategy.setPendingWithdrawalValuationBps(10_000);
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "full bps restores par valuation");
    }

    function test_ClaimSurplusAfterPendingDiscountCanBeRecoveredAsProfit() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(8 ether);
        vault.pauseAllocation();
        strategy.setPendingWithdrawalValuationBps(5_000);

        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 16 ether, 2, "pending discounted");
        assertEq(strategy.realizedYield(), 0, "discount is not yield");

        vm.deal(address(withdrawalQueue), 10 ether);
        withdrawalQueue.finalize(requestIds[0], 10 ether);
        strategy.claimLidoWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertApproxEqAbs(strategy.ownIdleUnderlying(), 10 ether, 2, "actual claim tracked");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 22 ether, 2, "claim surplus visible");
        assertApproxEqAbs(strategy.realizedYield(), 2 ether, 2, "surplus is realized yield");

        uint256 sent = strategy.sendProfitToVault();

        assertApproxEqAbs(sent, 2 ether, 2, "yield sent");
        assertEq(strategy.principal(), 20 ether, "principal unchanged");
        assertApproxEqAbs(vault.bufferBalance(), 2 ether, 2, "yield in vault buffer");
        assertApproxEqAbs(strategy.ownIdleUnderlying(), 8 ether, 2, "principal idle remains");
        assertApproxEqAbs(strategy.realizedYield(), 0, 2, "yield settled");
    }

    function test_RequestLidoWithdrawal_RevertsWhenQueueDoesNotMintRequestToStrategy() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        address wrongRecipient = makeAddr("wrongRecipient");
        withdrawalQueue.setRequestOwnerOverride(wrongRecipient);

        vm.expectRevert(abi.encodeWithSelector(LidoStrategy.UnexpectedWithdrawalRequestOwner.selector, wrongRecipient));
        strategy.requestLidoWithdrawal(8 ether);

        assertEq(strategy.pendingWithdrawAmount(), 0, "no phantom pending");
        assertEq(strategy.pendingRequestCount(), 0, "no pending id");
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "revert preserves position");
    }

    function test_RequestLidoWithdrawal_AfterRebaseUsesWstETHAmountsAndTracksStETHValue() public {
        (
            CollateralVault vault,
            LidoStrategy strategy,
            MockStETH stETH,
            MockWstETH wstETH,
            MockWithdrawalQueue withdrawalQueue,
            WETH9 weth
        ) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        stETH.addRewards(4 ether);

        uint256[] memory requestIds = strategy.requestLidoWithdrawal(12 ether);

        assertEq(requestIds.length, 2, "split by stETH max");
        assertApproxEqAbs(strategy.pendingWithdrawAmount(), 12 ether, 2, "pending uses stETH value");
        _assertPendingAccounting(strategy);
        assertApproxEqAbs(strategy.ownWstETH(), 10 ether, 2, "wstETH amount reduced");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 24 ether, 2, "AUM preserved through pending");
        assertGt(wstETH.balanceOf(address(withdrawalQueue)), 0, "withdrawalQueue received wstETH");

        (uint256 firstAmount,,,,) = withdrawalQueue.requests(requestIds[0]);
        (uint256 secondAmount,,,,) = withdrawalQueue.requests(requestIds[1]);

        assertLe(firstAmount, 10 ether, "first request within max");
        assertGe(firstAmount, 1 ether, "first request above min");
        assertLe(secondAmount, 10 ether, "second request within max");
        assertGe(secondAmount, 1 ether, "second request above min");
    }

    function test_RequestLidoWithdrawal_RevertsBelowMin() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 5 ether);

        vm.expectRevert(LidoStrategy.AmountOutOfRange.selector);
        strategy.requestLidoWithdrawal(0.5 ether);
    }

    function test_RequestLidoWithdrawal_RevertsWhenAmountExceedsStaked() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 5 ether);

        vm.expectRevert(LidoStrategy.AmountExceedsStaked.selector);
        strategy.requestLidoWithdrawal(6 ether);
    }

    function test_RequestLidoWithdrawal_RevertsWhenRequestBatchTooLarge() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        uint256 maxRequestAmount = strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL() * 10 ether;
        _depositAndAllocate(vault, weth, maxRequestAmount + 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                LidoStrategy.LidoWithdrawalRequestTooLarge.selector,
                strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL() + 1,
                strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL()
            )
        );
        strategy.requestLidoWithdrawal(maxRequestAmount + 10 ether);
    }

    function test_RequestLidoWithdrawal_RevertsWhenPendingRequestLimitReached() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        uint256 requestsPerBatch = strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL();
        uint256 maxPendingRequests = strategy.MAX_ASYNC_PENDING_REQUESTS();
        uint256 fullBatches = maxPendingRequests / requestsPerBatch;
        assertEq(maxPendingRequests % requestsPerBatch, 0, "test assumes exact batches");

        uint256 maxRequestAmount = requestsPerBatch * 10 ether;
        _depositAndAllocate(vault, weth, maxRequestAmount * fullBatches + 1 ether);

        for (uint256 batchIndex; batchIndex < fullBatches; batchIndex++) {
            strategy.requestLidoWithdrawal(maxRequestAmount);
        }

        assertEq(strategy.pendingRequestCount(), maxPendingRequests, "pending request cap reached");

        vm.expectRevert(
            abi.encodeWithSelector(
                AsyncRequestStrategy.AsyncPendingRequestLimitExceeded.selector,
                maxPendingRequests,
                1,
                maxPendingRequests
            )
        );
        strategy.requestLidoWithdrawal(1 ether);
    }

    function test_RequestAndClaim_ReflectsLossThenSendToVaultReducesPrincipal() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(8 ether);

        vm.expectRevert("MockWQ: not finalized");
        strategy.claimLidoWithdrawals(requestIds);

        vm.deal(address(withdrawalQueue), 7 ether);
        withdrawalQueue.finalize(requestIds[0], 7 ether);
        strategy.claimLidoWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertEq(strategy.pendingRequestCount(), 0, "request removed");
        _assertPendingAccounting(strategy);
        assertEq(weth.balanceOf(address(strategy)), 7 ether, "claimed ETH wrapped");
        assertEq(strategy.ownIdleUnderlying(), 7 ether, "claimed WETH tracked");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 19 ether, 2, "loss reflected");
        assertEq(strategy.principal(), 20 ether, "claim does not move principal");

        uint256 sent = strategy.sendToVault(7 ether);

        assertEq(sent, 7 ether, "pushed claimed WETH");
        assertEq(vault.bufferBalance(), 7 ether, "vault received WETH");
        assertEq(strategy.ownIdleUnderlying(), 0, "own idle spent");
        assertEq(strategy.principal(), 13 ether, "principal reduced on push");
        assertApproxEqAbs(vault.totalUnderlying(), 19 ether, 2, "vault total reflects loss");
    }

    function test_ClaimLidoWithdrawals_PermissionlessClaimReflectsFinalizedLoss() public {
        (CollateralVault vault, LidoStrategy strat,,, MockWithdrawalQueue queue, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strat.requestLidoWithdrawal(8 ether);

        vm.deal(address(queue), 7 ether);
        queue.finalize(requestIds[0], 7 ether);

        assertApproxEqAbs(strat.estimatedTotalUnderlying(), 20 ether, 2, "loss hidden until claim");

        vm.prank(alice);
        strat.claimLidoWithdrawals(requestIds);

        assertEq(strat.pendingWithdrawAmount(), 0, "pending cleared");
        _assertPendingAccounting(strat);
        assertEq(weth.balanceOf(address(strat)), 7 ether, "claimed ETH wrapped");
        assertEq(strat.ownIdleUnderlying(), 7 ether, "claimed WETH tracked");
        assertApproxEqAbs(strat.estimatedTotalUnderlying(), 19 ether, 2, "loss reflected after third-party claim");
    }

    function test_ClaimLidoWithdrawals_PendingAccountingTracksPartialClaim() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(12 ether);
        _assertPendingAccounting(strategy);

        vm.deal(address(withdrawalQueue), 12 ether);
        withdrawalQueue.finalize(requestIds[0], 10 ether);
        strategy.claimLidoWithdrawals(_singleRequest(requestIds[0]));

        assertEq(strategy.pendingWithdrawAmount(), 2 ether, "only second request remains");
        assertEq(strategy.pendingRequestCount(), 1, "one request remains");
        _assertPendingAccounting(strategy);

        uint256[] memory remainingRequestIds = strategy.getPendingRequestIds();
        withdrawalQueue.finalize(remainingRequestIds[0], 2 ether);
        strategy.claimLidoWithdrawals(remainingRequestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending fully cleared");
        assertEq(strategy.pendingRequestCount(), 0, "all requests removed");
        _assertPendingAccounting(strategy);
        assertEq(strategy.ownIdleUnderlying(), 12 ether, "claimed WETH tracked");
        assertEq(weth.balanceOf(address(strategy)), 12 ether, "claimed ETH wrapped");
    }

    function test_SendToVault_UsesOnlyOwnClaimedWethWhenDonatedWethExists() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(5 ether);
        vm.deal(address(withdrawalQueue), 5 ether);
        withdrawalQueue.finalize(requestIds[0], 5 ether);
        strategy.claimLidoWithdrawals(requestIds);
        _donateWeth(weth, address(strategy), 2 ether);

        assertEq(weth.balanceOf(address(strategy)), 7 ether, "claimed plus donated WETH");
        assertEq(strategy.ownIdleUnderlying(), 5 ether, "only claimed WETH is own idle");
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "donation excluded from estimate");

        uint256 sent = strategy.sendToVault(7 ether);

        assertEq(sent, 5 ether, "only own claimed WETH pushed");
        assertEq(vault.bufferBalance(), 5 ether, "vault received own idle");
        assertEq(weth.balanceOf(address(strategy)), 2 ether, "donated WETH remains");
        assertEq(strategy.ownIdleUnderlying(), 0, "own idle spent");
        assertEq(strategy.principal(), 15 ether, "principal reduced by own idle only");
        assertEq(strategy.estimatedTotalUnderlying(), 15 ether, "remaining Lido value excludes donation");
    }

    function test_ClaimLidoWithdrawals_RevertsForMultiRequestWithoutHints() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(12 ether);

        vm.deal(address(withdrawalQueue), 12 ether);
        withdrawalQueue.finalize(requestIds[0], 10 ether);
        withdrawalQueue.finalize(requestIds[1], 2 ether);

        vm.expectRevert(LidoStrategy.ClaimHintsRequired.selector);
        strategy.claimLidoWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 12 ether, "pending unchanged");
        assertEq(strategy.pendingRequestCount(), 2, "requests unchanged");
        _assertPendingAccounting(strategy);
        assertEq(weth.balanceOf(address(strategy)), 0, "nothing wrapped");
    }

    function test_ClaimLidoWithdrawals_UsesHintedBatchForMultipleRequests() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(12 ether);

        vm.deal(address(withdrawalQueue), 12 ether);
        withdrawalQueue.finalize(requestIds[0], 10 ether);
        withdrawalQueue.finalize(requestIds[1], 2 ether);

        uint256[] memory hints = new uint256[](2);
        hints[0] = 1;
        hints[1] = 2;

        strategy.claimLidoWithdrawals(requestIds, hints);

        assertEq(withdrawalQueue.batchClaimCalls(), 1, "batch claim used");
        assertEq(withdrawalQueue.singleClaimCalls(), 0, "single claim skipped");
        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertEq(strategy.pendingRequestCount(), 0, "requests removed");
        _assertPendingAccounting(strategy);
        assertEq(strategy.ownIdleUnderlying(), 12 ether, "claimed WETH tracked");
        assertEq(weth.balanceOf(address(strategy)), 12 ether, "claimed ETH wrapped");
        assertEq(strategy.principal(), 20 ether, "principal unchanged");
    }

    function test_ClaimLidoWithdrawals_RevertsOnHintLengthMismatch() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(12 ether);

        uint256[] memory hints = new uint256[](1);
        hints[0] = 1;

        vm.expectRevert(LidoStrategy.WithdrawalQueueRequestMismatch.selector);
        strategy.claimLidoWithdrawals(requestIds, hints);

        assertEq(strategy.pendingWithdrawAmount(), 12 ether, "pending unchanged");
        assertEq(strategy.pendingRequestCount(), 2, "requests unchanged");
    }

    function test_ClaimLidoWithdrawals_RevertsWhenHintedBatchTooLarge() public {
        (, LidoStrategy strategy,,,,) = _deployLidoSetup();

        uint256 requestCount = strategy.MAX_ASYNC_REQUESTS_PER_CLAIM() + 1;
        uint256[] memory requestIds = new uint256[](requestCount);
        uint256[] memory hints = new uint256[](requestCount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AsyncRequestStrategy.AsyncRequestClaimTooLarge.selector,
                requestCount,
                strategy.MAX_ASYNC_REQUESTS_PER_CLAIM()
            )
        );
        strategy.claimLidoWithdrawals(requestIds, hints);
    }

    function test_ClaimLidoWithdrawals_AllowsNonAllocatorAndRejectsUnknownRequest() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 5 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(2 ether);

        vm.deal(address(withdrawalQueue), 2 ether);
        withdrawalQueue.finalize(requestIds[0], 2 ether);

        vm.prank(alice);
        strategy.claimLidoWithdrawals(requestIds);

        vm.expectRevert(AsyncRequestStrategy.UnknownRequest.selector);
        strategy.claimLidoWithdrawals(requestIds);
    }

    function test_EmergencyWithdrawFromLido_PushesIdleAndRequestsRemainingStETH() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(5 ether);
        vm.deal(address(withdrawalQueue), 5 ether);
        withdrawalQueue.finalize(requestIds[0], 5 ether);
        strategy.claimLidoWithdrawals(requestIds);

        uint256 sent = strategy.emergencyWithdrawFromLido();

        assertEq(sent, 5 ether, "idle pushed");
        assertEq(vault.bufferBalance(), 5 ether, "vault received idle");
        assertEq(weth.balanceOf(address(strategy)), 0, "no idle left");
        assertEq(strategy.ownIdleUnderlying(), 0, "own idle spent");
        assertEq(strategy.principal(), 15 ether, "emergency accounts returned principal");
        assertEq(strategy.pendingWithdrawAmount(), 15 ether, "remaining stETH requested");
        assertEq(strategy.pendingRequestCount(), 2, "remaining split");
        _assertPendingAccounting(strategy);
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 15 ether, 2, "pending remains valued");
    }

    function test_EmergencyWithdrawFromLido_RequestsOnlyBoundedChunk() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        uint256 maxRequestAmount = strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL() * 10 ether;
        uint256 total = maxRequestAmount + 20 ether;
        _depositAndAllocate(vault, weth, total);

        uint256 sent = strategy.emergencyWithdrawFromLido();

        assertEq(sent, 0, "no idle pushed");
        assertEq(strategy.pendingWithdrawAmount(), maxRequestAmount, "bounded emergency request");
        assertEq(
            strategy.pendingRequestCount(), strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL(), "bounded request count"
        );
        _assertPendingAccounting(strategy);
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), total, 2, "AUM preserved");
    }

    function test_EmergencyWithdrawFromLido_RespectsCustomRequestCap() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 50 ether);

        uint256 sent = strategy.emergencyWithdrawFromLido(12 ether);

        assertEq(sent, 0, "no idle pushed");
        assertEq(strategy.pendingWithdrawAmount(), 12 ether, "custom cap requested");
        assertEq(strategy.pendingRequestCount(), 2, "custom cap split");
        _assertPendingAccounting(strategy);
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 50 ether, 2, "AUM preserved");
    }

    function test_EmergencyWithdrawFromLido_ClampsOversizedCustomRequestCap() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        uint256 maxRequestAmount = strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL() * 10 ether;
        uint256 total = maxRequestAmount + 20 ether;
        _depositAndAllocate(vault, weth, total);

        uint256 sent = strategy.emergencyWithdrawFromLido(type(uint256).max);

        assertEq(sent, 0, "no idle pushed");
        assertEq(strategy.pendingWithdrawAmount(), maxRequestAmount, "oversized cap clamped");
        assertEq(
            strategy.pendingRequestCount(), strategy.MAX_LIDO_WITHDRAWAL_REQUESTS_PER_CALL(), "bounded request count"
        );
        _assertPendingAccounting(strategy);
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), total, 2, "AUM preserved");
    }

    function test_EmergencyWithdrawFromLido_PushesIdleWhenQueueRequestFails() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(5 ether);
        vm.deal(address(withdrawalQueue), 5 ether);
        withdrawalQueue.finalize(requestIds[0], 5 ether);
        strategy.claimLidoWithdrawals(requestIds);
        withdrawalQueue.setRequestShouldRevert(true);

        uint256 sent = strategy.emergencyWithdrawFromLido();

        assertEq(sent, 5 ether, "idle still pushed");
        assertEq(vault.bufferBalance(), 5 ether, "vault received idle");
        assertEq(strategy.ownIdleUnderlying(), 0, "own idle spent");
        assertEq(strategy.principal(), 15 ether, "emergency accounts returned principal");
        assertEq(strategy.pendingWithdrawAmount(), 0, "no new request tracked");
        assertEq(strategy.pendingRequestCount(), 0, "no pending ids");
        _assertPendingAccounting(strategy);
        assertEq(strategy.ownWstETH(), 15 ether, "wstETH remains staked");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 15 ether, 2, "remaining stake still valued");
    }

    function test_EmergencyWithdrawFromLido_IgnoresDonatedPositionTokens() public {
        (CollateralVault vault, LidoStrategy strategy, MockStETH stETH, MockWstETH wstETH,, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        stETH.mintPooled(address(strategy), 5 ether);
        wstETH.mintShares(address(strategy), 5 ether);

        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "position donations excluded");

        uint256 sent = strategy.emergencyWithdrawFromLido();

        assertEq(sent, 0, "no idle underlying pushed");
        assertEq(strategy.pendingWithdrawAmount(), 20 ether, "only own position requested");
        assertEq(strategy.ownWstETH(), 0, "own wstETH queued");
        assertEq(wstETH.balanceOf(address(strategy)), 5 ether, "donated wstETH remains excluded");
        assertEq(stETH.balanceOf(address(strategy)), 5 ether, "donated stETH remains excluded");
        _assertPendingAccounting(strategy);
        assertEq(strategy.estimatedTotalUnderlying(), 20 ether, "donations still excluded after request");
    }

    function test_EmergencyWithdrawFromLido_PushesOnlyOwnIdleAndIgnoresRawEthDonation() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(5 ether);
        vm.deal(address(withdrawalQueue), 5 ether);
        withdrawalQueue.finalize(requestIds[0], 5 ether);
        strategy.claimLidoWithdrawals(requestIds);
        _donateWeth(weth, address(strategy), 2 ether);
        _donateRawEth(address(strategy), 3 ether);

        uint256 sent = strategy.emergencyWithdrawFromLido();

        assertEq(sent, 5 ether, "only own idle pushed");
        assertEq(vault.bufferBalance(), 5 ether, "vault received own idle");
        assertEq(weth.balanceOf(address(strategy)), 2 ether, "donated WETH remains");
        assertEq(address(strategy).balance, 3 ether, "raw ETH donation remains excluded");
        assertEq(strategy.ownIdleUnderlying(), 0, "own idle spent");
        assertEq(strategy.principal(), 15 ether, "returned principal accounts own idle only");
        assertEq(strategy.pendingWithdrawAmount(), 15 ether, "remaining own stake requested");
        assertEq(strategy.estimatedTotalUnderlying(), 15 ether, "donations excluded from estimate");
    }

    function test_BaseEmergencyWithdraw_ReducesLidoOwnIdleTracking() public {
        (CollateralVault vault, LidoStrategy strategy,,, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        _depositAndAllocate(vault, weth, 20 ether);
        uint256[] memory requestIds = strategy.requestLidoWithdrawal(5 ether);
        vm.deal(address(withdrawalQueue), 5 ether);
        withdrawalQueue.finalize(requestIds[0], 5 ether);
        strategy.claimLidoWithdrawals(requestIds);

        strategy.emergencyWithdraw(5 ether);
        _donateWeth(weth, address(strategy), 5 ether);

        assertEq(vault.bufferBalance(), 5 ether, "base emergency sent idle");
        assertEq(strategy.ownIdleUnderlying(), 0, "base emergency cleared own idle");
        assertEq(strategy.principal(), 20 ether, "base emergency does not reduce principal");
        assertEq(weth.balanceOf(address(strategy)), 5 ether, "new donation held");
        assertEq(strategy.estimatedTotalUnderlying(), 15 ether, "new donation cannot refill stale own idle");
        assertEq(strategy.realizedYield(), 0, "donation not yield after base emergency");
    }

    function test_SweepRewardToken_RejectsPositionTokensButSweepsReward() public {
        (, LidoStrategy strategy, MockStETH stETH, MockWstETH wstETH, MockWithdrawalQueue withdrawalQueue, WETH9 weth) =
            _deployLidoSetup();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(weth)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(stETH)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(wstETH)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(withdrawalQueue)), type(uint256).max);

        MockERC20 reward = new MockERC20("Lido Reward", "LRWD", 18);
        reward.mint(address(strategy), 3 ether);

        uint256 swept = strategy.sweepRewardToken(IERC20(address(reward)), type(uint256).max);

        assertEq(swept, 3 ether, "swept amount");
        assertEq(reward.balanceOf(treasury), 3 ether, "treasury reward");
    }

    function test_RequestLidoWithdrawal_RejectsNonAllocator() public {
        (CollateralVault vault, LidoStrategy strategy,,,, WETH9 weth) = _deployLidoSetup();

        _depositAndAllocate(vault, weth, 5 ether);

        vm.prank(alice);
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        strategy.requestLidoWithdrawal(2 ether);
    }
}
