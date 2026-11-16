// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../../src/CollateralVault.sol";
import "../../src/DToken.sol";
import "../../src/Interfaces/IDToken.sol";
import "../../src/Interfaces/IStrategy.sol";
import "../../src/Strategies/AaveV3Strategy.sol";
import "../../src/Strategies/archive/AsyncRequestStrategy.sol";
import "../../src/Strategies/archive/EtherfiWeETHStrategy.sol";
import "../../src/Strategies/archive/WeETHWithdrawAdapter.sol";
import "../../script/local/LocalAaveVenue.sol";
import "../TestContracts/WETH.sol";

import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract MockEtherfiEETH is ERC20, IEtherfiEETH {
    constructor() ERC20("Mock eETH", "meETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockEtherfiWeETH is ERC20, IEtherfiWeETH {
    IEtherfiEETH public immutable eETH;
    IEtherfiLiquidityPool public immutable liquidityPool;
    uint256 public residualWeETHOnUnwrap;

    constructor(IEtherfiEETH eETH_, IEtherfiLiquidityPool liquidityPool_) ERC20("Mock weETH", "mweETH") {
        eETH = eETH_;
        liquidityPool = liquidityPool_;
    }

    function wrap(uint256 eETHAmount) external returns (uint256) {
        _mint(msg.sender, eETHAmount);
        eETH.transferFrom(msg.sender, address(this), eETHAmount);
        return eETHAmount;
    }

    function unwrap(uint256 weETHAmount) external returns (uint256) {
        _burn(msg.sender, weETHAmount - residualWeETHOnUnwrap);
        eETH.transfer(msg.sender, weETHAmount);
        return weETHAmount;
    }

    function setResidualWeETHOnUnwrap(uint256 residualWeETHOnUnwrap_) external {
        residualWeETHOnUnwrap = residualWeETHOnUnwrap_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function getWeETHByeETH(uint256 eETHAmount) external pure returns (uint256) {
        return eETHAmount;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount;
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract RoundingMockEtherfiWeETH is ERC20, IEtherfiWeETH {
    IEtherfiEETH public immutable eETH;
    IEtherfiLiquidityPool public immutable liquidityPool;

    constructor(IEtherfiEETH eETH_, IEtherfiLiquidityPool liquidityPool_) ERC20("Rounding Mock weETH", "rmweETH") {
        eETH = eETH_;
        liquidityPool = liquidityPool_;
    }

    function wrap(uint256 eETHAmount) external returns (uint256 minted) {
        minted = eETHAmount / 2;
        _mint(msg.sender, minted);
        eETH.transferFrom(msg.sender, address(this), eETHAmount);
    }

    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount) {
        eETHAmount = weETHAmount * 2;
        _burn(msg.sender, weETHAmount);
        eETH.transfer(msg.sender, eETHAmount);
    }

    function getWeETHByeETH(uint256 eETHAmount) external pure returns (uint256) {
        return eETHAmount / 2;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount * 2;
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

interface IMockEtherfiWithdrawRequestCreator {
    function createRequest(uint256 amount, address recipient) external returns (uint256 requestId);
}

contract MockEtherfiLiquidityPool is IEtherfiLiquidityPool {
    MockEtherfiEETH public immutable eeth;
    IEtherfiWithdrawRequestNFT public withdrawRequestNFT;
    uint256 public eETHShortfallOnRequest;

    constructor(MockEtherfiEETH eeth_) {
        eeth = eeth_;
    }

    function setWithdrawRequestNFT(address withdrawRequestNFT_) external {
        withdrawRequestNFT = IEtherfiWithdrawRequestNFT(withdrawRequestNFT_);
    }

    function setEETHShortfallOnRequest(uint256 eETHShortfallOnRequest_) external {
        eETHShortfallOnRequest = eETHShortfallOnRequest_;
    }

    function deposit(address) external payable returns (uint256) {
        eeth.mint(msg.sender, msg.value);
        return msg.value;
    }

    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId) {
        IERC20(address(eeth)).transferFrom(msg.sender, address(withdrawRequestNFT), amount - eETHShortfallOnRequest);
        requestId = IMockEtherfiWithdrawRequestCreator(address(withdrawRequestNFT)).createRequest(amount, recipient);
    }
}

contract MockEtherfiWithdrawRequestNFT is ERC721, IEtherfiWithdrawRequestNFT {
    using Address for address payable;

    IEtherfiEETH public immutable eETH;
    IEtherfiLiquidityPool public immutable liquidityPool;
    uint256 public nextRequestId = 1;
    mapping(uint256 => WithdrawRequest) internal requests;
    mapping(uint256 => bool) internal finalized;
    mapping(uint256 => uint256) internal claimAmountOverrides;

    constructor(IEtherfiEETH eETH_, IEtherfiLiquidityPool liquidityPool_)
        ERC721("Mock Etherfi Withdraw Request", "mEFWR")
    {
        eETH = eETH_;
        liquidityPool = liquidityPool_;
    }

    receive() external payable {}

    function createRequest(uint256 amount, address recipient) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        requests[requestId] =
            WithdrawRequest({amountOfEEth: uint96(amount), shareOfEEth: uint96(amount), isValid: true, feeGwei: 0});
        _safeMint(recipient, requestId);
    }

    function finalize(uint256 requestId) external {
        finalized[requestId] = true;
    }

    function setClaimAmountOverride(uint256 requestId, uint256 amount) external {
        claimAmountOverrides[requestId] = amount;
    }

    function ownerOf(uint256 requestId)
        public
        view
        override(ERC721, IEtherfiWithdrawRequestNFT)
        returns (address owner)
    {
        return super.ownerOf(requestId);
    }

    function claimWithdraw(uint256 requestId) external {
        require(ownerOf(requestId) == msg.sender, "NOT_OWNER");
        require(finalized[requestId], "NOT_FINALIZED");
        WithdrawRequest memory request = requests[requestId];
        require(request.isValid, "INVALID");
        requests[requestId].isValid = false;
        _burn(requestId);
        uint256 claimAmount = claimAmountOverrides[requestId];
        if (claimAmount == 0) claimAmount = uint256(request.amountOfEEth);
        payable(msg.sender).sendValue(claimAmount);
    }

    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory) {
        return requests[requestId];
    }

    function isFinalized(uint256 requestId) external view returns (bool) {
        return finalized[requestId];
    }
}

contract MockEtherfiWithdrawAdapter is IWeETHWithdrawAdapter {
    MockEtherfiWeETH public immutable weeth;
    IEtherfiWithdrawRequestNFT public immutable withdrawRequestNFT;

    constructor(MockEtherfiWeETH weeth_, MockEtherfiWithdrawRequestNFT withdrawRequestNFT_) {
        weeth = weeth_;
        withdrawRequestNFT = withdrawRequestNFT_;
    }

    function dfWeETHWithdrawAdapterId() external pure returns (bytes32 adapterId) {
        adapterId = keccak256("DeltaForesight.WeETHWithdrawAdapter.v1");
    }

    function liquidityPool() external view returns (IEtherfiLiquidityPool) {
        return weeth.liquidityPool();
    }

    function eETH() external view returns (IEtherfiEETH) {
        return weeth.eETH();
    }

    function weETH() external view returns (IEtherfiWeETH) {
        return weeth;
    }

    function requestWithdraw(uint256 weETHAmount, address recipient) external returns (uint256 requestId) {
        IERC20(address(weeth)).transferFrom(msg.sender, address(this), weETHAmount);
        weeth.burn(address(this), weETHAmount);
        requestId =
            IMockEtherfiWithdrawRequestCreator(address(withdrawRequestNFT)).createRequest(weETHAmount, recipient);
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount;
    }
}

contract RoundingEtherfiWithdrawAdapter is IWeETHWithdrawAdapter {
    RoundingMockEtherfiWeETH public immutable weeth;
    IEtherfiWithdrawRequestNFT public immutable withdrawRequestNFT;

    constructor(RoundingMockEtherfiWeETH weeth_, MockEtherfiWithdrawRequestNFT withdrawRequestNFT_) {
        weeth = weeth_;
        withdrawRequestNFT = withdrawRequestNFT_;
    }

    function dfWeETHWithdrawAdapterId() external pure returns (bytes32 adapterId) {
        adapterId = keccak256("DeltaForesight.WeETHWithdrawAdapter.v1");
    }

    function liquidityPool() external view returns (IEtherfiLiquidityPool) {
        return weeth.liquidityPool();
    }

    function eETH() external view returns (IEtherfiEETH) {
        return weeth.eETH();
    }

    function weETH() external view returns (IEtherfiWeETH) {
        return weeth;
    }

    function requestWithdraw(uint256 weETHAmount, address recipient) external returns (uint256 requestId) {
        IERC20(address(weeth)).transferFrom(msg.sender, address(this), weETHAmount);
        weeth.burn(address(this), weETHAmount);
        requestId = IMockEtherfiWithdrawRequestCreator(address(withdrawRequestNFT)).createRequest(
            weeth.getEETHByWeETH(weETHAmount), recipient
        );
    }

    function getEETHByWeETH(uint256 weETHAmount) external view returns (uint256) {
        return weeth.getEETHByWeETH(weETHAmount);
    }
}

contract MisroutingEtherfiWithdrawAdapter is IWeETHWithdrawAdapter {
    MockEtherfiWeETH public immutable weeth;
    IEtherfiWithdrawRequestNFT public immutable withdrawRequestNFT;
    address public immutable requestRecipient;

    constructor(MockEtherfiWeETH weeth_, MockEtherfiWithdrawRequestNFT withdrawRequestNFT_, address requestRecipient_) {
        weeth = weeth_;
        withdrawRequestNFT = withdrawRequestNFT_;
        requestRecipient = requestRecipient_;
    }

    function dfWeETHWithdrawAdapterId() external pure returns (bytes32 adapterId) {
        adapterId = keccak256("DeltaForesight.WeETHWithdrawAdapter.v1");
    }

    function liquidityPool() external view returns (IEtherfiLiquidityPool) {
        return weeth.liquidityPool();
    }

    function eETH() external view returns (IEtherfiEETH) {
        return weeth.eETH();
    }

    function weETH() external view returns (IEtherfiWeETH) {
        return weeth;
    }

    function requestWithdraw(uint256 weETHAmount, address) external returns (uint256 requestId) {
        IERC20(address(weeth)).transferFrom(msg.sender, address(this), weETHAmount);
        weeth.burn(address(this), weETHAmount);
        requestId =
            IMockEtherfiWithdrawRequestCreator(address(withdrawRequestNFT)).createRequest(weETHAmount, requestRecipient);
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount;
    }
}

contract ConfigurableEtherfiWithdrawAdapter is IWeETHWithdrawAdapter {
    IEtherfiLiquidityPool public immutable liquidityPool;
    IEtherfiEETH public immutable eETH;
    IEtherfiWeETH public immutable weETH;
    IEtherfiWithdrawRequestNFT public immutable withdrawRequestNFT;

    constructor(
        IEtherfiLiquidityPool liquidityPool_,
        IEtherfiEETH eETH_,
        IEtherfiWeETH weETH_,
        IEtherfiWithdrawRequestNFT withdrawRequestNFT_
    ) {
        liquidityPool = liquidityPool_;
        eETH = eETH_;
        weETH = weETH_;
        withdrawRequestNFT = withdrawRequestNFT_;
    }

    function dfWeETHWithdrawAdapterId() external pure returns (bytes32 adapterId) {
        adapterId = keccak256("DeltaForesight.WeETHWithdrawAdapter.v1");
    }

    function requestWithdraw(uint256, address) external pure returns (uint256 requestId) {
        requestId = 1;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount;
    }
}

contract EtherfiLikeWithdrawAdapterWithoutDfIdentity {
    IEtherfiLiquidityPool public immutable liquidityPool;
    IEtherfiEETH public immutable eETH;
    IEtherfiWeETH public immutable weETH;
    IEtherfiWithdrawRequestNFT public immutable withdrawRequestNFT;

    constructor(
        IEtherfiLiquidityPool liquidityPool_,
        IEtherfiEETH eETH_,
        IEtherfiWeETH weETH_,
        IEtherfiWithdrawRequestNFT withdrawRequestNFT_
    ) {
        liquidityPool = liquidityPool_;
        eETH = eETH_;
        weETH = weETH_;
        withdrawRequestNFT = withdrawRequestNFT_;
    }

    function requestWithdraw(uint256, address) external pure returns (uint256 requestId) {
        requestId = 1;
    }

    function getEETHByWeETH(uint256 weETHAmount) external pure returns (uint256) {
        return weETHAmount;
    }
}

contract EtherfiWeETHStrategyTest is Test {
    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
    }

    function test_WeETHWithdrawAdapter_UnwrapsWeETHAndRequestsNativeEtherfiWithdrawal() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        eeth.mint(alice, 5 ether);
        vm.startPrank(alice);
        eeth.approve(address(weeth), 5 ether);
        weeth.wrap(5 ether);
        IERC20(address(weeth)).approve(address(withdrawAdapter), 3 ether);
        uint256 requestId = withdrawAdapter.requestWithdraw(3 ether, alice);
        vm.stopPrank();

        IEtherfiWithdrawRequestNFT.WithdrawRequest memory request = withdrawRequestNFT.getRequest(requestId);
        assertEq(withdrawRequestNFT.ownerOf(requestId), alice, "request recipient owns NFT");
        assertEq(uint256(request.amountOfEEth), 3 ether, "native eETH request amount");
        assertEq(weeth.balanceOf(alice), 2 ether, "weETH spent");
        assertEq(eeth.balanceOf(address(withdrawRequestNFT)), 3 ether, "eETH escrowed by NFT");
        assertEq(eeth.balanceOf(address(withdrawAdapter)), 0, "adapter keeps no eETH");
        assertEq(weeth.balanceOf(address(withdrawAdapter)), 0, "adapter keeps no weETH");
    }

    function test_WeETHWithdrawAdapter_RevertsOnMismatchedWeETHEETH() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiEETH otherEETH = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(otherEETH, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);

        vm.expectRevert(WeETHWithdrawAdapter.WeETHWithdrawAdapter__InvalidWeETHEETH.selector);
        new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);
    }

    function test_WeETHWithdrawAdapter_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT otherWithdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(otherWithdrawRequestNFT));

        vm.expectRevert(WeETHWithdrawAdapter.WeETHWithdrawAdapter__InvalidLiquidityPoolWithdrawRequestNFT.selector);
        new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);
    }

    function test_WeETHWithdrawAdapter_RevertsOnZeroRequest() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        vm.expectRevert(WeETHWithdrawAdapter.WeETHWithdrawAdapter__ZeroAmount.selector);
        withdrawAdapter.requestWithdraw(0, alice);
    }

    function test_WeETHWithdrawAdapter_RevertsWhenUnwrapLeavesResidualWeETH() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        eeth.mint(address(weeth), 3 ether);
        weeth.mint(alice, 3 ether);
        weeth.setResidualWeETHOnUnwrap(1);

        vm.startPrank(alice);
        IERC20(address(weeth)).approve(address(withdrawAdapter), 3 ether);
        vm.expectRevert(abi.encodeWithSelector(WeETHWithdrawAdapter.WeETHWithdrawAdapter__ResidualWeETH.selector, 0, 1));
        withdrawAdapter.requestWithdraw(3 ether, alice);
        vm.stopPrank();
    }

    function test_WeETHWithdrawAdapter_RevertsWhenPoolLeavesResidualEETH() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        liquidityPool.setEETHShortfallOnRequest(1);
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        eeth.mint(alice, 3 ether);
        vm.startPrank(alice);
        eeth.approve(address(weeth), 3 ether);
        weeth.wrap(3 ether);
        IERC20(address(weeth)).approve(address(withdrawAdapter), 3 ether);
        vm.expectRevert(abi.encodeWithSelector(WeETHWithdrawAdapter.WeETHWithdrawAdapter__ResidualEETH.selector, 0, 1));
        withdrawAdapter.requestWithdraw(3 ether, alice);
        vm.stopPrank();
    }

    function test_WeETHWithdrawAdapter_DonationBaselineDoesNotAffectResidualChecks() public {
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        eeth.mint(address(withdrawAdapter), 1);
        weeth.mint(address(withdrawAdapter), 1);
        eeth.mint(alice, 3 ether);
        vm.startPrank(alice);
        eeth.approve(address(weeth), 3 ether);
        weeth.wrap(3 ether);
        IERC20(address(weeth)).approve(address(withdrawAdapter), 3 ether);
        uint256 requestId = withdrawAdapter.requestWithdraw(3 ether, alice);
        vm.stopPrank();

        IEtherfiWithdrawRequestNFT.WithdrawRequest memory request = withdrawRequestNFT.getRequest(requestId);
        assertEq(uint256(request.amountOfEEth), 3 ether, "request amount excludes donation");
        assertEq(eeth.balanceOf(address(withdrawAdapter)), 1, "eETH baseline unchanged");
        assertEq(weeth.balanceOf(address(withdrawAdapter)), 1, "weETH baseline unchanged");
    }

    function test_Allocate_DepositsWethIntoWeETHAndValuesInWeth() public {
        (CollateralVault vault, EtherfiWeETHStrategy strategy, WETH9 weth,,,,) = _deployEtherfiSetup();

        _depositAndAllocate(vault, weth, 10 ether);

        assertEq(vault.bufferBalance(), 0, "buffer allocated");
        assertEq(strategy.principal(), 10 ether, "principal");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "strategy value");
        assertEq(vault.totalUnderlying(), 10 ether, "vault backing");
        assertEq(strategy.ownWeETH(), 10 ether, "weETH tracked");
    }

    function test_RequestClaimAndSendToVault_ReturnsClaimedWeth() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            ,
            ,
            ,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);

        uint256 requestId = strategy.requestEtherfiWithdrawal(4 ether);
        assertEq(strategy.pendingWithdrawAmount(), 4 ether, "pending");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "pending still valued");
        assertEq(strategy.sendToVault(4 ether), 0, "no synchronous liquidity before claim");

        withdrawRequestNFT.finalize(requestId);
        vm.deal(address(withdrawRequestNFT), 4 ether);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        strategy.claimEtherfiWithdrawals(requestIds);

        assertEq(strategy.ownIdleUnderlying(), 4 ether, "claimed weth tracked");
        uint256 sent = strategy.sendToVault(4 ether);

        assertEq(sent, 4 ether, "sent");
        assertEq(vault.bufferBalance(), 4 ether, "vault received weth");
        assertEq(strategy.principal(), 6 ether, "principal reduced");
        assertEq(strategy.estimatedTotalUnderlying(), 6 ether, "remaining value");
    }

    function test_RequestEtherfiWithdrawal_RoundsTinyEETHRequestUpToOneWeETHAtom() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        RoundingMockEtherfiWeETH weeth = new RoundingMockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);
        EtherfiWeETHStrategy strategy =
            _deployStrategy(vault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);

        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
        _depositAndAllocate(vault, weth, 10 ether);
        assertEq(strategy.ownWeETH(), 5 ether, "rounding mock mints half weETH");

        uint256 requestId = strategy.requestEtherfiWithdrawal(1);

        assertEq(strategy.ownWeETH(), 5 ether - 1, "one weETH atom spent");
        assertEq(strategy.pendingWithdrawalAmountByRequestId(requestId), 2, "request records actual net eETH");
        assertEq(strategy.pendingWithdrawAmount(), 2, "pending tracks actual request value");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "staked plus pending remains consistent");
    }

    function test_SetPendingWithdrawalValuationBps_DiscountsAndRoundsEtherfiPendingValue() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            ,
            ,
            ,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);

        uint256 requested = 4 ether + 7;
        uint256 requestId = strategy.requestEtherfiWithdrawal(requested);

        assertEq(strategy.pendingWithdrawalValuationBps(), 10_000, "default full pending valuation");
        assertTrue(strategy.pendingWithdrawalValuationBpsConfigured(), "valuation configured");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "default pending valued at par");

        vault.pauseAllocation();
        vm.expectEmit(address(strategy));
        emit AsyncRequestStrategy.PendingWithdrawalValuationBpsUpdated(10_000, 3_333);
        strategy.setPendingWithdrawalValuationBps(3_333);
        uint256 expected = (10 ether - requested) + Math.mulDiv(requested, 3_333, 10_000);

        assertEq(strategy.estimatedTotalUnderlying(), expected, "dust rounds down");
        assertEq(vault.totalUnderlying(), expected, "vault uses rounded-down estimate");

        strategy.setPendingWithdrawalValuationBps(0);
        assertTrue(strategy.pendingWithdrawalValuationBpsConfigured(), "zero bps configured");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether - requested, "zero bps excludes pending");

        withdrawRequestNFT.finalize(requestId);
        vm.deal(address(withdrawRequestNFT), requested);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        strategy.claimEtherfiWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "claim actual replaces pending discount");
    }

    function test_SetPendingWithdrawalValuationBps_RevertsAboveDenominator() public {
        (, EtherfiWeETHStrategy strategy,,,,,) = _deployEtherfiSetup();

        vm.expectRevert(
            abi.encodeWithSelector(AsyncRequestStrategy.InvalidPendingWithdrawalValuationBps.selector, 10_001)
        );
        strategy.setPendingWithdrawalValuationBps(10_001);
    }

    function test_SetPendingWithdrawalValuationBps_RequiresWriteoffRole() public {
        (, EtherfiWeETHStrategy strategy,,,,,) = _deployEtherfiSetup();

        vm.prank(alice);
        vm.expectRevert(BaseStrategy.Unauthorized.selector);
        strategy.setPendingWithdrawalValuationBps(5_000);
    }

    function test_SetPendingWithdrawalValuationBps_RevertsDiscountBeforeAllocationPause() public {
        (CollateralVault vault, EtherfiWeETHStrategy strategy, WETH9 weth,,,,) = _deployEtherfiSetup();

        _depositAndAllocate(vault, weth, 10 ether);
        strategy.requestEtherfiWithdrawal(4 ether);

        vm.expectRevert(AsyncRequestStrategy.PendingWithdrawalValuationNotPaused.selector);
        strategy.setPendingWithdrawalValuationBps(5_000);
    }

    function test_ClaimSurplusAfterPendingDiscountCanBeRecoveredAsProfit() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            ,
            ,
            ,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);

        uint256 requestId = strategy.requestEtherfiWithdrawal(4 ether);
        vault.pauseAllocation();
        strategy.setPendingWithdrawalValuationBps(5_000);

        assertEq(strategy.estimatedTotalUnderlying(), 8 ether, "pending discounted");
        assertEq(strategy.realizedYield(), 0, "discount is not yield");

        withdrawRequestNFT.finalize(requestId);
        withdrawRequestNFT.setClaimAmountOverride(requestId, 5 ether);
        vm.deal(address(withdrawRequestNFT), 5 ether);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        strategy.claimEtherfiWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertEq(strategy.ownIdleUnderlying(), 5 ether, "actual claim tracked");
        assertEq(strategy.estimatedTotalUnderlying(), 11 ether, "claim surplus visible");
        assertEq(strategy.realizedYield(), 1 ether, "surplus is realized yield");

        uint256 sent = strategy.sendProfitToVault();

        assertEq(sent, 1 ether, "yield sent");
        assertEq(strategy.principal(), 10 ether, "principal unchanged");
        assertEq(vault.bufferBalance(), 1 ether, "yield in vault buffer");
        assertEq(strategy.ownIdleUnderlying(), 4 ether, "principal idle remains");
        assertEq(strategy.realizedYield(), 0, "yield settled");
    }

    function test_ClaimUsesActualEthReceivedWhenEtherfiReturnsLessThanPending() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            ,
            ,
            ,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);

        uint256 requestId = strategy.requestEtherfiWithdrawal(4 ether);
        assertEq(strategy.pendingWithdrawAmount(), 4 ether, "pending value");

        withdrawRequestNFT.finalize(requestId);
        withdrawRequestNFT.setClaimAmountOverride(requestId, 3 ether);
        vm.deal(address(withdrawRequestNFT), 3 ether);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        strategy.claimEtherfiWithdrawals(requestIds);

        assertEq(strategy.pendingWithdrawAmount(), 0, "pending cleared");
        assertEq(strategy.ownIdleUnderlying(), 3 ether, "actual claim tracked");
        assertEq(strategy.estimatedTotalUnderlying(), 9 ether, "short claim reflected");

        uint256 sent = strategy.sendToVault(4 ether);

        assertEq(sent, 3 ether, "only actual idle sent");
        assertEq(vault.bufferBalance(), 3 ether, "vault received actual");
        assertEq(strategy.principal(), 7 ether, "principal reduced by actual return");
        assertEq(strategy.estimatedTotalUnderlying(), 6 ether, "remaining value");
    }

    function test_ClaimEtherfiWithdrawals_RevertsWhenBatchTooLarge() public {
        (, EtherfiWeETHStrategy strategy,,,,,) = _deployEtherfiSetup();

        uint256 requestCount = strategy.MAX_ASYNC_REQUESTS_PER_CLAIM() + 1;
        uint256[] memory requestIds = new uint256[](requestCount);

        vm.expectRevert(
            abi.encodeWithSelector(
                AsyncRequestStrategy.AsyncRequestClaimTooLarge.selector,
                requestCount,
                strategy.MAX_ASYNC_REQUESTS_PER_CLAIM()
            )
        );
        strategy.claimEtherfiWithdrawals(requestIds);
    }

    function test_RequestEtherfiWithdrawal_RevertsWhenPendingRequestLimitReached() public {
        (CollateralVault vault, EtherfiWeETHStrategy strategy, WETH9 weth,,,,) = _deployEtherfiSetup();

        uint256 maxPendingRequests = strategy.MAX_ASYNC_PENDING_REQUESTS();
        _depositAndAllocate(vault, weth, (maxPendingRequests + 1) * 1 ether);

        for (uint256 requestIndex; requestIndex < maxPendingRequests; requestIndex++) {
            strategy.requestEtherfiWithdrawal(1 ether);
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
        strategy.requestEtherfiWithdrawal(1 ether);
    }

    function test_RequestEtherfiWithdrawal_RevertsWhenAdapterDoesNotMintRequestToStrategy() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        address wrongRecipient = makeAddr("wrongRecipient");
        MisroutingEtherfiWithdrawAdapter withdrawAdapter =
            new MisroutingEtherfiWithdrawAdapter(weeth, withdrawRequestNFT, wrongRecipient);
        CollateralVault vault = _deployVault(weth);
        EtherfiWeETHStrategy strategy =
            _deployStrategy(vault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);

        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
        _depositAndAllocate(vault, weth, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                EtherfiWeETHStrategy.EtherfiWeETHStrategy__UnexpectedWithdrawRequestOwner.selector, wrongRecipient
            )
        );
        strategy.requestEtherfiWithdrawal(4 ether);

        assertEq(strategy.pendingWithdrawAmount(), 0, "no phantom pending");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "revert preserves position");
    }

    function test_DonatedWeETHDoesNotInflateValuation() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            MockEtherfiEETH eeth,
            MockEtherfiWeETH weeth,
            ,
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);
        uint256 valueBefore = strategy.estimatedTotalUnderlying();

        address donor = makeAddr("donor");
        eeth.mint(donor, 5 ether);
        vm.startPrank(donor);
        eeth.approve(address(weeth), 5 ether);
        weeth.wrap(5 ether);
        weeth.transfer(address(strategy), 5 ether);
        vm.stopPrank();

        assertEq(strategy.estimatedTotalUnderlying(), valueBefore, "donation ignored");
        assertEq(vault.totalUnderlying(), valueBefore, "vault backing unchanged");
    }

    function test_RawEthDonationBeforeClaimDoesNotInflateIdleOrYield() public {
        (
            CollateralVault vault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            ,
            ,
            ,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        ) = _deployEtherfiSetup();
        _depositAndAllocate(vault, weth, 10 ether);

        uint256 requestId = strategy.requestEtherfiWithdrawal(4 ether);
        _donateRawEth(address(strategy), 3 ether);

        assertEq(address(strategy).balance, 3 ether, "raw ETH donation held");
        assertEq(strategy.ownIdleUnderlying(), 0, "raw ETH is not idle WETH");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "raw ETH not valued");
        assertEq(strategy.sendProfitToVault(), 0, "raw ETH not yield");

        withdrawRequestNFT.finalize(requestId);
        vm.deal(address(withdrawRequestNFT), 4 ether);
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        strategy.claimEtherfiWithdrawals(requestIds);

        assertEq(address(strategy).balance, 3 ether, "raw ETH donation remains");
        assertEq(weth.balanceOf(address(strategy)), 4 ether, "only claim delta wrapped");
        assertEq(strategy.ownIdleUnderlying(), 4 ether, "only claim delta tracked");
        assertEq(strategy.estimatedTotalUnderlying(), 10 ether, "donation excluded after claim");
        assertEq(strategy.sendProfitToVault(), 0, "claim principal not yield");

        uint256 sent = strategy.sendToVault(4 ether);

        assertEq(sent, 4 ether, "only own idle returned");
        assertEq(address(strategy).balance, 3 ether, "raw ETH still excluded");
        assertEq(weth.balanceOf(address(strategy)), 0, "wrapped claim returned");
        assertEq(vault.bufferBalance(), 4 ether, "vault got claim only");
        assertEq(strategy.estimatedTotalUnderlying(), 6 ether, "remaining staked only");
    }

    function test_SweepRewardToken_RejectsPositionTokens() public {
        (
            ,
            EtherfiWeETHStrategy strategy,
            ,
            MockEtherfiEETH eeth,
            MockEtherfiWeETH weeth,
            ,
            MockEtherfiWithdrawRequestNFT nft
        ) = _deployEtherfiSetup();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(eeth)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(weeth)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(nft)), type(uint256).max);
    }

    function test_VaultCanAllocateAcrossAaveAndEtherfiFiftyFifty() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        WeETHWithdrawAdapter withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);
        EtherfiWeETHStrategy etherfiStrategy =
            _deployStrategy(vault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);
        AaveV3Strategy aaveStrategy = _deployAaveStrategy(vault, weth);

        vault.addToWhitelist(address(aaveStrategy));
        vault.addToWhitelist(address(etherfiStrategy));
        vault.addStrategy(IStrategy(address(aaveStrategy)), 5000, type(uint256).max);
        vault.addStrategy(IStrategy(address(etherfiStrategy)), 5000, type(uint256).max);

        _depositAndAllocate(vault, weth, 10 ether);

        assertEq(vault.totalWeightBps(), 10_000, "total weight");
        assertEq(aaveStrategy.principal(), 5 ether, "aave half");
        assertEq(etherfiStrategy.principal(), 5 ether, "etherfi half");
        assertEq(vault.totalUnderlying(), 10 ether, "vault backing");
    }

    function test_Initialize_RevertsOnMismatchedWeETHEETH() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiEETH otherEETH = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(otherEETH, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidWeETHEETH.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedWeETHLiquidityPool() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiLiquidityPool otherLiquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, otherLiquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidWeETHLiquidityPool.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedWithdrawRequestNFTEETH() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiEETH otherEETH = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(otherEETH, liquidityPool);
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidWithdrawRequestNFTEETH.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedWithdrawRequestNFTLiquidityPool() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiLiquidityPool otherLiquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, otherLiquidityPool);
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidWithdrawRequestNFTLiquidityPool.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedLiquidityPoolWithdrawRequestNFT() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT otherWithdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(otherWithdrawRequestNFT));
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidLiquidityPoolWithdrawRequestNFT.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedAdapterWeETH() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWeETH otherWeETH = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(otherWeETH, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidAdapterWeETH.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedAdapterLiquidityPool() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiLiquidityPool otherLiquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        ConfigurableEtherfiWithdrawAdapter withdrawAdapter =
            new ConfigurableEtherfiWithdrawAdapter(otherLiquidityPool, eeth, weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidAdapterLiquidityPool.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedAdapterEETH() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiEETH otherEETH = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        ConfigurableEtherfiWithdrawAdapter withdrawAdapter =
            new ConfigurableEtherfiWithdrawAdapter(liquidityPool, otherEETH, weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidAdapterEETH.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnMismatchedAdapterWithdrawRequestNFT() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT otherWithdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        MockEtherfiWithdrawAdapter withdrawAdapter = new MockEtherfiWithdrawAdapter(weeth, otherWithdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidAdapterWithdrawRequestNFT.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            withdrawAdapter,
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsWhenAdapterDoesNotExposeDfIdentity() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        EtherfiLikeWithdrawAdapterWithoutDfIdentity withdrawAdapter =
            new EtherfiLikeWithdrawAdapterWithoutDfIdentity(liquidityPool, eeth, weeth, withdrawRequestNFT);
        CollateralVault vault = _deployVault(weth);

        _deployStrategyExpectRevert(
            EtherfiWeETHStrategy.EtherfiWeETHStrategy__InvalidAdapterIdentity.selector,
            vault,
            weth,
            liquidityPool,
            eeth,
            weeth,
            IWeETHWithdrawAdapter(address(withdrawAdapter)),
            withdrawRequestNFT
        );
    }

    function test_Initialize_RevertsOnNonContractWithdrawAdapter() public {
        WETH9 weth = new WETH9();
        MockEtherfiEETH eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        MockEtherfiWeETH weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        address withdrawAdapterEoa = makeAddr("withdrawAdapterEoa");
        CollateralVault vault = _deployVault(weth);

        EtherfiWeETHStrategy implementation = new EtherfiWeETHStrategy();
        bytes memory initializer = abi.encodeWithSelector(
            EtherfiWeETHStrategy.initialize.selector,
            address(vault),
            IWETH(address(weth)),
            admin,
            admin,
            IEtherfiLiquidityPool(address(liquidityPool)),
            IEtherfiEETH(address(eeth)),
            IEtherfiWeETH(address(weeth)),
            IWeETHWithdrawAdapter(withdrawAdapterEoa),
            IEtherfiWithdrawRequestNFT(address(withdrawRequestNFT)),
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, withdrawAdapterEoa));
        new ERC1967Proxy(address(implementation), initializer);
    }

    function _deployEtherfiSetup()
        internal
        returns (
            CollateralVault collateralVault,
            EtherfiWeETHStrategy strategy,
            WETH9 weth,
            MockEtherfiEETH eeth,
            MockEtherfiWeETH weeth,
            WeETHWithdrawAdapter withdrawAdapter,
            MockEtherfiWithdrawRequestNFT withdrawRequestNFT
        )
    {
        weth = new WETH9();
        eeth = new MockEtherfiEETH();
        MockEtherfiLiquidityPool liquidityPool = new MockEtherfiLiquidityPool(eeth);
        weeth = new MockEtherfiWeETH(eeth, liquidityPool);
        withdrawRequestNFT = new MockEtherfiWithdrawRequestNFT(eeth, liquidityPool);
        liquidityPool.setWithdrawRequestNFT(address(withdrawRequestNFT));
        withdrawAdapter = new WeETHWithdrawAdapter(liquidityPool, eeth, weeth, withdrawRequestNFT);

        collateralVault = _deployVault(weth);
        strategy =
            _deployStrategy(collateralVault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);

        collateralVault.addToWhitelist(address(strategy));
        collateralVault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
    }

    function _deployVault(WETH9 weth) internal returns (CollateralVault collateralVault) {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(weth), true);
        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(weth)), IDToken(address(dToken)), treasury, admin
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        dToken.setTokenInfo("dETH", "dETH", IERC20MetadataUpgradeable(address(weth)));
        activateDTokenForTest(dToken);
    }

    function _deployStrategy(
        CollateralVault collateralVault,
        WETH9 weth,
        MockEtherfiLiquidityPool liquidityPool,
        MockEtherfiEETH eeth,
        IEtherfiWeETH weeth,
        IWeETHWithdrawAdapter withdrawAdapter,
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT
    ) internal returns (EtherfiWeETHStrategy strategy) {
        EtherfiWeETHStrategy implementation = new EtherfiWeETHStrategy();
        bytes memory initializer =
            _strategyInitializer(collateralVault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);
        strategy = EtherfiWeETHStrategy(payable(address(new ERC1967Proxy(address(implementation), initializer))));
    }

    function _deployStrategyExpectRevert(
        bytes4 expectedRevert,
        CollateralVault collateralVault,
        WETH9 weth,
        MockEtherfiLiquidityPool liquidityPool,
        MockEtherfiEETH eeth,
        IEtherfiWeETH weeth,
        IWeETHWithdrawAdapter withdrawAdapter,
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT
    ) internal {
        EtherfiWeETHStrategy implementation = new EtherfiWeETHStrategy();
        bytes memory initializer =
            _strategyInitializer(collateralVault, weth, liquidityPool, eeth, weeth, withdrawAdapter, withdrawRequestNFT);

        vm.expectRevert(expectedRevert);
        new ERC1967Proxy(address(implementation), initializer);
    }

    function _strategyInitializer(
        CollateralVault collateralVault,
        WETH9 weth,
        MockEtherfiLiquidityPool liquidityPool,
        MockEtherfiEETH eeth,
        IEtherfiWeETH weeth,
        IWeETHWithdrawAdapter withdrawAdapter,
        MockEtherfiWithdrawRequestNFT withdrawRequestNFT
    ) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            EtherfiWeETHStrategy.initialize.selector,
            address(collateralVault),
            IWETH(address(weth)),
            admin,
            admin,
            IEtherfiLiquidityPool(address(liquidityPool)),
            IEtherfiEETH(address(eeth)),
            IEtherfiWeETH(address(weeth)),
            IWeETHWithdrawAdapter(address(withdrawAdapter)),
            IEtherfiWithdrawRequestNFT(address(withdrawRequestNFT)),
            address(0)
        );
    }

    function _deployAaveStrategy(CollateralVault collateralVault, WETH9 weth)
        internal
        returns (AaveV3Strategy strategy)
    {
        LocalAavePool pool = new LocalAavePool();
        LocalAToken aToken = new LocalAToken(address(pool), address(weth));
        pool.setAsset(IERC20(address(weth)));
        pool.setAToken(aToken);

        AaveV3Strategy implementation = new AaveV3Strategy();
        bytes memory initializer = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(collateralVault),
            IERC20(address(weth)),
            admin,
            admin,
            IAaveV3Pool(address(pool)),
            IAToken(address(aToken))
        );
        strategy = AaveV3Strategy(address(new ERC1967Proxy(address(implementation), initializer)));
    }

    function _depositAndAllocate(CollateralVault collateralVault, WETH9 weth, uint256 amount) internal {
        vm.deal(alice, amount);
        vm.startPrank(alice);
        weth.deposit{value: amount}();
        weth.approve(address(collateralVault), amount);
        collateralVault.deposit(amount);
        vm.stopPrank();
        collateralVault.setBufferConfig(0, 0);
        collateralVault.allocate();
    }

    function _donateRawEth(address recipient, uint256 amount) internal {
        address donor = makeAddr("rawEthDonor");
        vm.deal(donor, amount);
        vm.prank(donor);
        (bool ok,) = payable(recipient).call{value: amount}("");
        assertTrue(ok, "raw ETH donation");
    }
}
