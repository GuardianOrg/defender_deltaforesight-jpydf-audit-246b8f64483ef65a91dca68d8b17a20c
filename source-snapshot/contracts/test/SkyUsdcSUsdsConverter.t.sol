// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISkyLitePsmWrapper} from "src/Interfaces/ISkyUsdcSUsdsConverter.sol";
import {SkyUsdcSUsdsConverter} from "src/Strategies/SkyUsdcSUsdsConverter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MockSkyLitePsmWrapper is ISkyLitePsmWrapper {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant SCALE = 1e12;

    MockERC20 public immutable usdc;
    MockERC20 public immutable usds;
    uint256 public tin;
    uint256 public tout;
    int256 public reportedAmountOffset;

    constructor(MockERC20 _usdc, MockERC20 _usds) {
        usdc = _usdc;
        usds = _usds;
    }

    function gem() external view returns (address) {
        return address(usdc);
    }

    function dai() external view returns (address) {
        return address(usds);
    }

    function setFees(uint256 _tin, uint256 _tout) external {
        tin = _tin;
        tout = _tout;
    }

    function setReportedAmountOffset(int256 _amountOffset) external {
        reportedAmountOffset = _amountOffset;
    }

    function sellGem(address _receiver, uint256 _usdcAmount) external returns (uint256 usdsOut) {
        require(tin != type(uint256).max, "SELL_HALTED");
        IERC20(address(usdc)).safeTransferFrom(msg.sender, address(this), _usdcAmount);
        uint256 gross = _usdcAmount * SCALE;
        usdsOut = gross - (gross * tin / WAD);
        IERC20(address(usds)).safeTransfer(_receiver, usdsOut);
        return _offset(usdsOut);
    }

    function buyGem(address _receiver, uint256 _usdcAmount) external returns (uint256 usdsIn) {
        require(tout != type(uint256).max, "BUY_HALTED");
        uint256 base = _usdcAmount * SCALE;
        usdsIn = base + (base * tout / WAD);
        IERC20(address(usds)).safeTransferFrom(msg.sender, address(this), usdsIn);
        IERC20(address(usdc)).safeTransfer(_receiver, _usdcAmount);
        return _offset(usdsIn);
    }

    function _offset(uint256 _amount) internal view returns (uint256) {
        if (reportedAmountOffset >= 0) return _amount + uint256(reportedAmountOffset);
        return _amount - uint256(-reportedAmountOffset);
    }
}

contract SkyUsdcSUsdsConverterTest is Test {
    uint256 internal constant HALTED = type(uint256).max;

    MockERC20 internal usdc;
    MockERC20 internal usds;
    MockSkyLitePsmWrapper internal wrapper;
    SkyUsdcSUsdsConverter internal converter;
    address internal alice;
    address internal receiver;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        usds = new MockERC20("USDS", "USDS", 18);
        wrapper = new MockSkyLitePsmWrapper(usdc, usds);
        converter = new SkyUsdcSUsdsConverter(wrapper);
        alice = makeAddr("alice");
        receiver = makeAddr("receiver");

        usdc.mint(address(wrapper), 10_000_000e6);
        usds.mint(address(wrapper), 10_000_000e18);
    }

    function test_ConstructorBindsWrapperTokens() public view {
        assertEq(address(converter.psmWrapper()), address(wrapper));
        assertEq(address(converter.usdcToken()), address(usdc));
        assertEq(address(converter.usdsToken()), address(usds));
    }

    function test_ConstructorRejectsNonUsdcGemDecimals() public {
        MockERC20 badUsdc = new MockERC20("Bad USDC", "bUSDC", 18);
        MockSkyLitePsmWrapper badWrapper = new MockSkyLitePsmWrapper(badUsdc, usds);

        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__InvalidUsdcDecimals.selector, uint8(18))
        );
        new SkyUsdcSUsdsConverter(badWrapper);
    }

    function test_ConvertUsdcToUsds_AppliesTinAndLeavesNoResidueOrAllowance() public {
        wrapper.setFees(5e15, 0); // 0.5%
        usdc.mint(alice, 100e6);

        vm.startPrank(alice);
        usdc.approve(address(converter), 100e6);
        uint256 usdsOut = converter.convertUsdcToUsds(100e6, 99e18, receiver);
        vm.stopPrank();

        assertEq(usdsOut, 99.5e18);
        assertEq(usds.balanceOf(receiver), usdsOut);
        assertEq(usdc.balanceOf(address(converter)), 0);
        assertEq(usds.balanceOf(address(converter)), 0);
        assertEq(usdc.allowance(address(converter), address(wrapper)), 0);
    }

    function test_ConvertUsdcToUsds_RevertsOnHaltAndMinOut() public {
        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(converter), type(uint256).max);

        wrapper.setFees(HALTED, 0);
        vm.expectRevert(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__RouteHalted.selector);
        converter.convertUsdcToUsds(100e6, 0, receiver);

        wrapper.setFees(1e16, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__InsufficientUsdsOut.selector, 99e18, 100e18
            )
        );
        converter.convertUsdcToUsds(100e6, 100e18, receiver);
        vm.stopPrank();
    }

    function test_ConvertUsdsToUsdc_UsesBudgetAndRefundsUnspentDust() public {
        wrapper.setFees(0, 1e16); // 1%
        uint256 budget = 101e18 + 123;
        usds.mint(alice, budget);

        vm.startPrank(alice);
        usds.approve(address(converter), budget);
        uint256 usdcOut = converter.convertUsdsToUsdc(budget, 100e6, receiver);
        vm.stopPrank();

        assertEq(usdcOut, 100e6);
        assertEq(usdc.balanceOf(receiver), 100e6);
        assertEq(usds.balanceOf(alice), 123, "unspent budget refunded");
        assertEq(usdc.balanceOf(address(converter)), 0);
        assertEq(usds.balanceOf(address(converter)), 0);
        assertEq(usds.allowance(address(converter), address(wrapper)), 0);
    }

    function test_PreviewUsdsToUsdc_AccountsForFeeFloorAtOneUsdcAtom() public {
        wrapper.setFees(0, 1);

        assertEq(converter.previewUsdsToUsdc(1e12), 1, "fee rounds to zero for one USDC atom");
        assertEq(converter.previewUsdsToUsdc(1e12 - 1), 0);
    }

    function test_RouteHaltStatusDistinguishesExplicitHaltFromInvalidFee() public {
        wrapper.setFees(0, 0);
        assertFalse(converter.isUsdsToUsdcRouteHalted(), "live route");

        wrapper.setFees(0, HALTED);
        assertTrue(converter.isUsdsToUsdcRouteHalted(), "explicit halt");

        wrapper.setFees(0, 1e18 + 1);
        assertFalse(converter.isUsdsToUsdcRouteHalted(), "invalid fee is not a halt");
    }

    function testFuzz_PreviewReturnsMaximumAffordableUsdc(uint128 budgetSeed, uint64 toutSeed) public {
        uint256 budget = bound(uint256(budgetSeed), 0, 1e36);
        uint256 tout = bound(uint256(toutSeed), 0, 1e18);
        wrapper.setFees(0, tout);

        uint256 usdcOut = converter.previewUsdsToUsdc(budget);
        uint256 base = usdcOut * 1e12;
        uint256 required = base + (base * tout / 1e18);
        assertLe(required, budget, "quote exceeds budget");

        uint256 nextBase = (usdcOut + 1) * 1e12;
        uint256 nextRequired = nextBase + (nextBase * tout / 1e18);
        assertGt(nextRequired, budget, "quote is not maximal");
    }

    function test_PreviewAndConversionFailClosedWhenBuyRouteHaltedOrFeeInvalid() public {
        wrapper.setFees(0, HALTED);
        vm.expectRevert(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__RouteHalted.selector);
        converter.previewUsdsToUsdc(100e18);

        usds.mint(alice, 100e18);
        vm.startPrank(alice);
        usds.approve(address(converter), type(uint256).max);
        vm.expectRevert(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__RouteHalted.selector);
        converter.convertUsdsToUsdc(100e18, 0, receiver);

        wrapper.setFees(0, 1e18 + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__InvalidFee.selector, uint256(1e18 + 1))
        );
        converter.previewUsdsToUsdc(100e18);
        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__InvalidFee.selector, uint256(1e18 + 1))
        );
        converter.convertUsdsToUsdc(100e18, 0, receiver);
        vm.stopPrank();
    }

    function test_ConversionRejectsWrapperReportedAmountMismatch() public {
        wrapper.setReportedAmountOffset(1);
        usdc.mint(alice, 1e6);

        vm.startPrank(alice);
        usdc.approve(address(converter), 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                SkyUsdcSUsdsConverter.SkyUsdcSUsdsConverter__TokenAmountMismatch.selector, address(usds), 1e18 + 1, 1e18
            )
        );
        converter.convertUsdcToUsds(1e6, 0, receiver);
        vm.stopPrank();
    }
}

contract SkyUsdcSUsdsConverterMainnetForkTest is Test {
    address internal constant SKY_LITE_PSM_WRAPPER_USDS_USDC = 0xA188EEC8F81263234dA3622A406892F3D630f98c;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    function test_MainnetFork_BindsCanonicalSkyWrapperAndTokens() public {
        string memory rpcUrl = _mainnetRpcUrl();
        if (bytes(rpcUrl).length == 0) return;

        vm.createSelectFork(rpcUrl);
        SkyUsdcSUsdsConverter converter = new SkyUsdcSUsdsConverter(ISkyLitePsmWrapper(SKY_LITE_PSM_WRAPPER_USDS_USDC));

        assertEq(address(converter.psmWrapper()), SKY_LITE_PSM_WRAPPER_USDS_USDC);
        assertEq(address(converter.usdcToken()), MAINNET_USDC);
        assertEq(address(converter.usdsToken()), MAINNET_USDS);

        uint256 tout = ISkyLitePsmWrapper(SKY_LITE_PSM_WRAPPER_USDS_USDC).tout();
        if (tout == type(uint256).max) {
            assertEq(converter.previewUsdsToUsdc(100e18), 0);
        } else {
            assertLe(tout, 1e18);
            assertLe(converter.previewUsdsToUsdc(100e18), 100e6);
        }
    }

    function test_MainnetFork_ExecutesRoundTripWhenRoutesAreActive() public {
        string memory rpcUrl = _mainnetRpcUrl();
        if (bytes(rpcUrl).length == 0) return;

        vm.createSelectFork(rpcUrl);
        ISkyLitePsmWrapper wrapper = ISkyLitePsmWrapper(SKY_LITE_PSM_WRAPPER_USDS_USDC);
        if (wrapper.tin() == type(uint256).max || wrapper.tout() == type(uint256).max) return;

        SkyUsdcSUsdsConverter converter = new SkyUsdcSUsdsConverter(wrapper);
        IERC20 usdc = IERC20(MAINNET_USDC);
        IERC20 usds = IERC20(MAINNET_USDS);
        address user = makeAddr("fork-user");
        uint256 usdcIn = 100e6;
        deal(MAINNET_USDC, user, usdcIn);

        vm.startPrank(user);
        usdc.approve(address(converter), usdcIn);
        uint256 usdsOut = converter.convertUsdcToUsds(usdcIn, 1, user);
        usds.approve(address(converter), usdsOut);
        uint256 usdcOut = converter.convertUsdsToUsdc(usdsOut, 1, user);
        vm.stopPrank();

        assertGt(usdsOut, 0);
        assertGt(usdcOut, 0);
        assertEq(usdc.balanceOf(address(converter)), 0);
        assertEq(usds.balanceOf(address(converter)), 0);
        assertEq(usdc.allowance(address(converter), address(wrapper)), 0);
        assertEq(usds.allowance(address(converter), address(wrapper)), 0);
    }

    function _mainnetRpcUrl() internal view returns (string memory rpcUrl) {
        rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0 && vm.envOr("DF_REQUIRE_MAINNET_FORK_TESTS", false)) {
            revert("Sky converter mainnet evidence requires MAINNET_RPC_URL");
        }
    }
}
