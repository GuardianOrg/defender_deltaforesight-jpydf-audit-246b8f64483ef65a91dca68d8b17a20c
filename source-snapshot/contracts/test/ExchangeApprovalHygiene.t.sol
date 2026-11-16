// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {IExchange} from "src/Zappers/Interfaces/IExchange.sol";
import {Currency, IHooks, IV4Router, PoolKey} from "src/Zappers/Modules/Exchanges/UniswapV4/IV4Router.sol";
import {IPermit2} from "src/Zappers/Modules/Exchanges/UniswapV4/IPermit2.sol";
import {IUniversalRouter} from "src/Zappers/Modules/Exchanges/UniswapV4/IUniversalRouter.sol";
import {V4RouterCodec} from "src/Zappers/Modules/Exchanges/UniswapV4/V4RouterCodec.sol";
import {UniV4Exchange} from "src/Zappers/Modules/Exchanges/UniV4Exchange.sol";

interface MintableToken {
    function mint(address _to, uint256 _amount) external;
}

contract ZeroFirstToken {
    string public name;
    string public symbol;
    uint8 private immutable DECIMALS;
    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    error NonZeroToNonZeroApproval();
    error InsufficientBalance();
    error InsufficientAllowance();

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint8 decimals_) {
        name = _name;
        symbol = _symbol;
        DECIMALS = decimals_;
    }

    function decimals() external view returns (uint8) {
        return DECIMALS;
    }

    function mint(address _to, uint256 _amount) external {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
        emit Transfer(address(0), _to, _amount);
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        if (_amount != 0 && allowance[msg.sender][_spender] != 0) {
            revert NonZeroToNonZeroApproval();
        }
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool) {
        uint256 currentAllowance = allowance[_from][msg.sender];
        if (currentAllowance < _amount) revert InsufficientAllowance();
        allowance[_from][msg.sender] = currentAllowance - _amount;
        emit Approval(_from, msg.sender, currentAllowance - _amount);
        _transfer(_from, _to, _amount);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        if (balanceOf[_from] < _amount) revert InsufficientBalance();
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        emit Transfer(_from, _to, _amount);
    }
}

contract MockPermit2 is IPermit2 {
    struct PackedAllowance {
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    mapping(address owner => mapping(address token => mapping(address spender => PackedAllowance))) private approvals;

    error AllowanceExpired(uint256 deadline);
    error InsufficientAllowance(uint256 amount);

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        PackedAllowance storage approval = approvals[msg.sender][token][spender];
        approval.amount = amount;
        approval.expiration = expiration;
    }

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        PackedAllowance storage approval = approvals[user][token][spender];
        amount = approval.amount;
        expiration = approval.expiration;
        nonce = approval.nonce;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        PackedAllowance storage approval = approvals[from][token][msg.sender];
        if (approval.expiration < block.timestamp) revert AllowanceExpired(approval.expiration);
        if (approval.amount < amount) revert InsufficientAllowance(approval.amount);

        approval.amount -= amount;
        bool success = ZeroFirstToken(token).transferFrom(from, to, amount);
        require(success, "transferFrom failed");
    }
}

contract MockUniversalRouter is IUniversalRouter {
    MockPermit2 public immutable PERMIT2;

    uint8 public lastCommand;
    uint8 public lastFirstAction;
    uint8 public lastSecondAction;
    uint8 public lastThirdAction;
    bool public lastZeroForOne;
    uint128 public lastAmountIn;
    uint128 public lastAmountOut;
    uint128 public lastAmountInMaximum;
    uint128 public lastAmountOutMinimum;
    uint256 public lastMinHopPriceX36;
    address public lastCurrency0;
    address public lastCurrency1;
    uint24 public lastFee;
    int24 public lastTickSpacing;
    address public lastHooks;
    uint256 public exactInputAmountOut;
    uint256 public exactOutputSpend;
    IExchange public reentryTarget;
    bool public reenterSwapFromJpydf;
    bool public reentryGuardBlocked;
    bool public reentryUnexpectedSuccess;
    bool public reentryNonGuardRevert;

    error InvalidCommand();
    error InvalidActions();
    error Expired();
    error UnsupportedAction(uint8 action);
    error CurrencyMismatch();
    error TooMuchRequested();
    error TooLittleReceived();

    constructor(MockPermit2 _permit2) {
        PERMIT2 = _permit2;
    }

    function setExactInputAmountOut(uint256 _amountOut) external {
        exactInputAmountOut = _amountOut;
    }

    function setExactOutputSpend(uint256 _amountIn) external {
        exactOutputSpend = _amountIn;
    }

    function setReentryTarget(IExchange _target, bool _swapFromJpydf) external {
        reentryTarget = _target;
        reenterSwapFromJpydf = _swapFromJpydf;
        reentryGuardBlocked = false;
        reentryUnexpectedSuccess = false;
        reentryNonGuardRevert = false;
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable {
        if (deadline < block.timestamp) revert Expired();
        if (commands.length != 1 || uint8(commands[0]) != V4RouterCodec.V4_SWAP || inputs.length != 1) {
            revert InvalidCommand();
        }

        _attemptReentry();
        lastCommand = uint8(commands[0]);

        (bytes memory actions, bytes[] memory params) = abi.decode(inputs[0], (bytes, bytes[]));
        if (
            actions.length != 3 || params.length != 3 || uint8(actions[1]) != V4RouterCodec.SETTLE_ALL
                || uint8(actions[2]) != V4RouterCodec.TAKE_ALL
        ) {
            revert InvalidActions();
        }

        lastFirstAction = uint8(actions[0]);
        lastSecondAction = uint8(actions[1]);
        lastThirdAction = uint8(actions[2]);

        if (lastFirstAction == V4RouterCodec.SWAP_EXACT_IN_SINGLE) {
            _executeExactInput(params);
        } else if (lastFirstAction == V4RouterCodec.SWAP_EXACT_OUT_SINGLE) {
            _executeExactOutput(params);
        } else {
            revert UnsupportedAction(lastFirstAction);
        }
    }

    function _attemptReentry() internal {
        IExchange target = reentryTarget;
        if (address(target) == address(0)) return;

        reentryTarget = IExchange(address(0));
        if (reenterSwapFromJpydf) {
            try target.swapFromJpydf(1, 1) {
                reentryUnexpectedSuccess = true;
            } catch Error(string memory reason) {
                _recordReentryRevert(reason);
            } catch {
                reentryNonGuardRevert = true;
            }
        } else {
            try target.swapToJpydf(1, 1) returns (uint256) {
                reentryUnexpectedSuccess = true;
            } catch Error(string memory reason) {
                _recordReentryRevert(reason);
            } catch {
                reentryNonGuardRevert = true;
            }
        }
    }

    function _recordReentryRevert(string memory reason) internal {
        if (keccak256(bytes(reason)) == keccak256(bytes("ReentrancyGuard: reentrant call"))) {
            reentryGuardBlocked = true;
        } else {
            reentryNonGuardRevert = true;
        }
    }

    function _executeExactInput(bytes[] memory params) internal {
        IV4Router.ExactInputSingleParams memory swapParams = abi.decode(params[0], (IV4Router.ExactInputSingleParams));
        (Currency inputCurrency, uint256 settleAmount) = abi.decode(params[1], (Currency, uint256));
        (Currency outputCurrency, uint256 takeMinimum) = abi.decode(params[2], (Currency, uint256));

        _recordPoolKey(swapParams.poolKey, swapParams.zeroForOne);

        address tokenIn =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency0 : swapParams.poolKey.currency1);
        address tokenOut =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency1 : swapParams.poolKey.currency0);
        if (Currency.unwrap(inputCurrency) != tokenIn || Currency.unwrap(outputCurrency) != tokenOut) {
            revert CurrencyMismatch();
        }
        if (settleAmount != swapParams.amountIn || takeMinimum != swapParams.amountOutMinimum) {
            revert CurrencyMismatch();
        }

        uint256 amountOut = exactInputAmountOut == 0 ? swapParams.amountOutMinimum : exactInputAmountOut;
        if (amountOut < swapParams.amountOutMinimum) revert TooLittleReceived();

        PERMIT2.transferFrom(msg.sender, address(this), swapParams.amountIn, tokenIn);
        MintableToken(tokenOut).mint(msg.sender, amountOut);

        lastAmountIn = swapParams.amountIn;
        lastAmountOutMinimum = swapParams.amountOutMinimum;
        lastMinHopPriceX36 = swapParams.minHopPriceX36;
    }

    function _executeExactOutput(bytes[] memory params) internal {
        IV4Router.ExactOutputSingleParams memory swapParams = abi.decode(params[0], (IV4Router.ExactOutputSingleParams));
        (Currency inputCurrency, uint256 settleMaximum) = abi.decode(params[1], (Currency, uint256));
        (Currency outputCurrency, uint256 takeAmount) = abi.decode(params[2], (Currency, uint256));

        _recordPoolKey(swapParams.poolKey, swapParams.zeroForOne);

        address tokenIn =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency0 : swapParams.poolKey.currency1);
        address tokenOut =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency1 : swapParams.poolKey.currency0);
        if (Currency.unwrap(inputCurrency) != tokenIn || Currency.unwrap(outputCurrency) != tokenOut) {
            revert CurrencyMismatch();
        }
        if (settleMaximum != swapParams.amountInMaximum || takeAmount != swapParams.amountOut) {
            revert CurrencyMismatch();
        }

        uint256 amountIn = exactOutputSpend == 0 ? swapParams.amountInMaximum : exactOutputSpend;
        if (amountIn > swapParams.amountInMaximum) revert TooMuchRequested();

        PERMIT2.transferFrom(msg.sender, address(this), uint160(amountIn), tokenIn);
        MintableToken(tokenOut).mint(msg.sender, swapParams.amountOut);

        lastAmountOut = swapParams.amountOut;
        lastAmountInMaximum = swapParams.amountInMaximum;
        lastMinHopPriceX36 = swapParams.minHopPriceX36;
    }

    function _recordPoolKey(PoolKey memory poolKey, bool zeroForOne) internal {
        lastZeroForOne = zeroForOne;
        lastCurrency0 = Currency.unwrap(poolKey.currency0);
        lastCurrency1 = Currency.unwrap(poolKey.currency1);
        lastFee = poolKey.fee;
        lastTickSpacing = poolKey.tickSpacing;
        lastHooks = address(poolKey.hooks);
    }
}

contract UnderpayingUniversalRouter is IUniversalRouter {
    MockPermit2 public immutable PERMIT2;
    uint256 public immutable outputAmount;
    uint256 public immutable exactOutputSpend;

    error InvalidCommand();
    error InvalidActions();
    error UnsupportedAction(uint8 action);

    constructor(MockPermit2 _permit2, uint256 _outputAmount, uint256 _exactOutputSpend) {
        PERMIT2 = _permit2;
        outputAmount = _outputAmount;
        exactOutputSpend = _exactOutputSpend;
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256) external payable {
        if (commands.length != 1 || uint8(commands[0]) != V4RouterCodec.V4_SWAP || inputs.length != 1) {
            revert InvalidCommand();
        }

        (bytes memory actions, bytes[] memory params) = abi.decode(inputs[0], (bytes, bytes[]));
        if (
            actions.length != 3 || params.length != 3 || uint8(actions[1]) != V4RouterCodec.SETTLE_ALL
                || uint8(actions[2]) != V4RouterCodec.TAKE_ALL
        ) {
            revert InvalidActions();
        }

        uint8 swapAction = uint8(actions[0]);
        if (swapAction == V4RouterCodec.SWAP_EXACT_IN_SINGLE) {
            _executeExactInput(params);
        } else if (swapAction == V4RouterCodec.SWAP_EXACT_OUT_SINGLE) {
            _executeExactOutput(params);
        } else {
            revert UnsupportedAction(swapAction);
        }
    }

    function _executeExactInput(bytes[] memory params) internal {
        IV4Router.ExactInputSingleParams memory swapParams = abi.decode(params[0], (IV4Router.ExactInputSingleParams));
        address tokenIn =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency0 : swapParams.poolKey.currency1);
        address tokenOut =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency1 : swapParams.poolKey.currency0);

        PERMIT2.transferFrom(msg.sender, address(this), swapParams.amountIn, tokenIn);
        MintableToken(tokenOut).mint(msg.sender, outputAmount);
    }

    function _executeExactOutput(bytes[] memory params) internal {
        IV4Router.ExactOutputSingleParams memory swapParams = abi.decode(params[0], (IV4Router.ExactOutputSingleParams));
        address tokenIn =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency0 : swapParams.poolKey.currency1);
        address tokenOut =
            Currency.unwrap(swapParams.zeroForOne ? swapParams.poolKey.currency1 : swapParams.poolKey.currency0);
        uint256 amountIn = exactOutputSpend == 0 ? swapParams.amountInMaximum : exactOutputSpend;

        PERMIT2.transferFrom(msg.sender, address(this), uint160(amountIn), tokenIn);
        MintableToken(tokenOut).mint(msg.sender, outputAmount);
    }
}

contract ExchangeApprovalHygieneTest is Test {
    function test_UniV4SwapFromJpydfClearsResidualPermit2AndTokenAllowancesForZeroFirstTokens() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        router.setExactOutputSpend(500 ether);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        jpydf.mint(user, 1_000 ether);

        vm.startPrank(user);
        jpydf.approve(address(exchange), 1_000 ether);
        exchange.swapFromJpydf(1_000 ether, 100 ether);

        _assertPermit2AllowancesCleared(exchange, jpydf, permit2, router);
        assertEq(coll.balanceOf(user), 100 ether, "user receives exact-output collateral");
        assertEq(jpydf.balanceOf(user), 500 ether, "unused input is returned");
        assertEq(router.lastCommand(), V4RouterCodec.V4_SWAP, "v4 command");
        assertEq(router.lastFirstAction(), V4RouterCodec.SWAP_EXACT_OUT_SINGLE, "exact-output action");
        assertEq(router.lastSecondAction(), V4RouterCodec.SETTLE_ALL, "settle action");
        assertEq(router.lastThirdAction(), V4RouterCodec.TAKE_ALL, "take action");
        assertEq(router.lastZeroForOne(), address(jpydf) < address(coll), "JPYDF -> collateral direction");
        assertEq(router.lastAmountOut(), 100 ether, "collateral amount out");
        assertEq(router.lastAmountInMaximum(), 1_000 ether, "JPYDF max input");
        assertEq(router.lastMinHopPriceX36(), 0, "per-hop price guard disabled");

        jpydf.approve(address(exchange), 500 ether);
        router.setExactOutputSpend(250 ether);
        exchange.swapFromJpydf(500 ether, 50 ether);

        _assertPermit2AllowancesCleared(exchange, jpydf, permit2, router);
        assertEq(coll.balanceOf(user), 150 ether, "second swap succeeds with zero-first token");
        assertEq(jpydf.balanceOf(user), 250 ether, "second unused input is returned");
        vm.stopPrank();
    }

    function test_UniV4SwapFromJpydfRejectsRouterReentrancy() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        router.setExactOutputSpend(500 ether);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        router.setReentryTarget(IExchange(address(exchange)), true);

        address user = makeAddr("user");
        jpydf.mint(user, 1_000 ether);

        vm.startPrank(user);
        jpydf.approve(address(exchange), 1_000 ether);
        exchange.swapFromJpydf(1_000 ether, 100 ether);
        vm.stopPrank();

        assertTrue(router.reentryGuardBlocked(), "router reentry blocked by ReentrancyGuard");
        assertFalse(router.reentryUnexpectedSuccess(), "router reentry did not succeed");
        assertFalse(router.reentryNonGuardRevert(), "router reentry did not reach token path");
        _assertPermit2AllowancesCleared(exchange, jpydf, permit2, router);
    }

    function test_UniV4SwapToJpydfReturnsActualOutputAndClearsPermit2AndTokenAllowances() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        router.setExactInputAmountOut(15 ether);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        coll.mint(user, 100 ether);

        vm.startPrank(user);
        coll.approve(address(exchange), 100 ether);
        uint256 output = exchange.swapToJpydf(100 ether, 10 ether);
        vm.stopPrank();

        _assertPermit2AllowancesCleared(exchange, coll, permit2, router);
        assertEq(output, 15 ether, "swapToJpydf returns actual output");
        assertEq(jpydf.balanceOf(user), 15 ether, "user receives actual JPYDF output");
        assertEq(router.lastCommand(), V4RouterCodec.V4_SWAP, "v4 command");
        assertEq(router.lastFirstAction(), V4RouterCodec.SWAP_EXACT_IN_SINGLE, "exact-input action");
        assertEq(router.lastSecondAction(), V4RouterCodec.SETTLE_ALL, "settle action");
        assertEq(router.lastThirdAction(), V4RouterCodec.TAKE_ALL, "take action");
        assertEq(router.lastZeroForOne(), address(coll) < address(jpydf), "collateral -> JPYDF direction");
        assertEq(router.lastAmountIn(), 100 ether, "collateral amount in");
        assertEq(router.lastAmountOutMinimum(), 10 ether, "JPYDF min output");
        assertEq(router.lastMinHopPriceX36(), 0, "per-hop price guard disabled");
        assertEq(router.lastFee(), 500, "pool fee");
        assertEq(router.lastTickSpacing(), 10, "pool tick spacing");
        assertEq(router.lastHooks(), address(0), "hookless pool");
        assertEq(router.lastCurrency0(), address(coll) < address(jpydf) ? address(coll) : address(jpydf), "currency0");
        assertEq(router.lastCurrency1(), address(coll) < address(jpydf) ? address(jpydf) : address(coll), "currency1");
    }

    function test_UniV4SwapToJpydfRejectsRouterReentrancy() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        router.setExactInputAmountOut(15 ether);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        router.setReentryTarget(IExchange(address(exchange)), false);

        address user = makeAddr("user");
        coll.mint(user, 100 ether);

        vm.startPrank(user);
        coll.approve(address(exchange), 100 ether);
        exchange.swapToJpydf(100 ether, 10 ether);
        vm.stopPrank();

        assertTrue(router.reentryGuardBlocked(), "router reentry blocked by ReentrancyGuard");
        assertFalse(router.reentryUnexpectedSuccess(), "router reentry did not succeed");
        assertFalse(router.reentryNonGuardRevert(), "router reentry did not reach token path");
        _assertPermit2AllowancesCleared(exchange, coll, permit2, router);
    }

    function test_UniV4SwapToJpydfRevertsWhenRouterUnderpaysOutput() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        UnderpayingUniversalRouter router = new UnderpayingUniversalRouter(permit2, 9 ether, 0);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        coll.mint(user, 100 ether);

        vm.startPrank(user);
        coll.approve(address(exchange), 100 ether);
        vm.expectRevert(
            abi.encodeWithSignature("UniV4Exchange__InsufficientOutput(uint256,uint256)", 9 ether, 10 ether)
        );
        exchange.swapToJpydf(100 ether, 10 ether);
        vm.stopPrank();
    }

    function test_UniV4SwapFromJpydfRevertsWhenRouterUnderpaysOutput() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        UnderpayingUniversalRouter router = new UnderpayingUniversalRouter(permit2, 99 ether, 500 ether);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        jpydf.mint(user, 1_000 ether);

        vm.startPrank(user);
        jpydf.approve(address(exchange), 1_000 ether);
        vm.expectRevert(
            abi.encodeWithSignature("UniV4Exchange__InsufficientOutput(uint256,uint256)", 99 ether, 100 ether)
        );
        exchange.swapFromJpydf(1_000 ether, 100 ether);
        vm.stopPrank();
    }

    function test_UniV4SwapToJpydfRevertsWhenAmountExceedsV4Uint128() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        uint256 tooLargeAmount = uint256(type(uint128).max) + 1;
        coll.mint(user, tooLargeAmount);

        vm.startPrank(user);
        coll.approve(address(exchange), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__AmountTooLarge(uint256)", tooLargeAmount));
        exchange.swapToJpydf(tooLargeAmount, 1 ether);
        vm.stopPrank();
    }

    function test_UniV4SwapFromJpydfRevertsWhenAmountExceedsV4Uint128() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);
        UniV4Exchange exchange = new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        address user = makeAddr("user");
        uint256 tooLargeAmount = uint256(type(uint128).max) + 1;
        jpydf.mint(user, tooLargeAmount);

        vm.startPrank(user);
        jpydf.approve(address(exchange), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__AmountTooLarge(uint256)", tooLargeAmount));
        exchange.swapFromJpydf(tooLargeAmount, 1 ether);
        vm.stopPrank();
    }

    function test_UniV4ConstructorRejectsInvalidAddressesAndIdenticalTokens() external {
        ZeroFirstToken jpydf = new ZeroFirstToken("JPYDF", "JPYDF", 18);
        ZeroFirstToken coll = new ZeroFirstToken("COLL", "COLL", 18);
        MockPermit2 permit2 = new MockPermit2();
        MockUniversalRouter router = new MockUniversalRouter(permit2);

        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__ZeroAddress()"));
        new UniV4Exchange(
            IERC20(address(0)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );

        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__ZeroAddress()"));
        new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(0)),
            IPermit2(address(permit2))
        );

        address routerEoa = makeAddr("routerEoa");
        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__NotContract(address)", routerEoa));
        new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(routerEoa),
            IPermit2(address(permit2))
        );

        address permit2Eoa = makeAddr("permit2Eoa");
        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__NotContract(address)", permit2Eoa));
        new UniV4Exchange(
            IERC20(address(coll)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(permit2Eoa)
        );

        vm.expectRevert(abi.encodeWithSignature("UniV4Exchange__IdenticalTokens()"));
        new UniV4Exchange(
            IERC20(address(jpydf)),
            IJpydfToken(address(jpydf)),
            500,
            10,
            IHooks(address(0)),
            IUniversalRouter(address(router)),
            IPermit2(address(permit2))
        );
    }

    function _assertPermit2AllowancesCleared(
        IExchange exchange,
        ZeroFirstToken token,
        MockPermit2 permit2,
        MockUniversalRouter router
    ) internal view {
        (uint160 permit2Amount, uint48 permit2Expiration,) =
            permit2.allowance(address(exchange), address(token), address(router));
        assertEq(token.allowance(address(exchange), address(permit2)), 0, "token allowance to Permit2 must be cleared");
        assertEq(permit2Amount, 0, "Permit2 router allowance must be cleared");
        assertEq(permit2Expiration, 0, "Permit2 router expiration must be cleared");
    }
}
