// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/Strategies/BaseStrategy.sol";
import "../src/Strategies/AaveV3Strategy.sol"; // for IAToken / IAaveV3Pool

/// @title PushModelMocks - shared mocks for the push-model Strategy / Vault suite.
/// @notice BaseStrategy-only mocks (`FeeOnTransferToken`, `FailingMockStrategy`)
///         landed in Phase 3b-1a; the Aave-V3 mocks (`MockAToken`,
///         `MockAavePool`), which implement the `IAToken` / `IAaveV3Pool`
///         interfaces declared inside `AaveV3Strategy.sol`, are added here in
///         Phase 3b-1b alongside that strategy.

/// @notice ERC20 that burns a 1% fee on every transfer. Exercises the push
///         model's "decrement principal by `sent` (vault-received), not declared"
///         accounting (HC-05).
contract FeeOnTransferToken is ERC20 {
    uint8 private immutable _decimals;
    uint256 public constant FEE_BPS = 100; // 1%
    uint256 public constant BPS = 10000;
    address public constant SINK = 0x000000000000000000000000000000000000dEaD;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_BPS) / BPS;
        uint256 net = amount - fee;
        address from = _msgSender();
        _transfer(from, to, net);
        if (fee > 0) _transfer(from, SINK, fee);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_BPS) / BPS;
        uint256 net = amount - fee;
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, net);
        if (fee > 0) _transfer(from, SINK, fee);
        return true;
    }
}

/// @notice ERC20 that can report `false` for transfers to one recipient
///         without moving funds. Exercises exact-recovery transfer failure.
contract FalseReturnToken is ERC20 {
    uint8 private immutable _decimals;
    address public falseReturnRecipient;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setFalseReturnRecipient(address _recipient) external {
        falseReturnRecipient = _recipient;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == falseReturnRecipient) return false;
        return super.transfer(to, amount);
    }
}

/// @notice Strategy whose `_doWithdraw` can be toggled to revert. Used to prove
///         that a failing upstream withdrawal propagates out of `sendToVault` /
///         `sendProfitToVault` (negative-path coverage) without making the
///         post-withdraw BaseStrategy path unreachable at compile time.
contract FailingMockStrategy is BaseStrategy {
    bool public withdrawShouldFail;
    bool public valuationShouldFail;

    function initialize(address _vault, IERC20 _underlying, address _owner) external initializer {
        __BaseStrategy_init(_vault, _underlying, _owner, _owner);
        withdrawShouldFail = true;
    }

    function setWithdrawShouldFail(bool _shouldFail) external onlyOwner {
        withdrawShouldFail = _shouldFail;
    }

    function setValuationShouldFail(bool _shouldFail) external onlyOwner {
        valuationShouldFail = _shouldFail;
    }

    function _doDeposit(uint256) internal override {}

    function _doWithdraw(uint256 _amount) internal view override returns (uint256 actual) {
        if (withdrawShouldFail) revert("WithdrawFailed");
        uint256 available = underlyingToken.balanceOf(address(this));
        return _amount > available ? available : _amount;
    }

    function _estimatedTotalUnderlying() internal view override returns (uint256) {
        if (valuationShouldFail) revert("ValuationFailed");
        return underlyingToken.balanceOf(address(this));
    }
}

/// @notice Strategy whose upstream deposit can be toggled to revert. The
///         BaseStrategy initializer deliberately preserves the production
///         Strategy -> Vault underlying approval so allocation recovery tests
///         exercise the real push-model trust boundary.
contract FailingDepositMockStrategy is BaseStrategy {
    bool public depositShouldFail;
    uint256 public depositAttempts;

    function initialize(address _vault, IERC20 _underlying, address _owner) external initializer {
        __BaseStrategy_init(_vault, _underlying, _owner, _owner);
        depositShouldFail = true;
    }

    function setDepositShouldFail(bool _shouldFail) external onlyOwner {
        depositShouldFail = _shouldFail;
    }

    function _doDeposit(uint256) internal override {
        depositAttempts += 1;
        if (depositShouldFail) revert("DepositFailed");
    }

    function _doWithdraw(uint256 _amount) internal view override returns (uint256 actual) {
        uint256 available = underlyingToken.balanceOf(address(this));
        return _amount > available ? available : _amount;
    }

    function _estimatedTotalUnderlying() internal view override returns (uint256) {
        return underlyingToken.balanceOf(address(this));
    }
}

/// @notice Minimal Aave-V3-like aToken that tracks scaled balances.
/// @dev    Only the surface used by `AaveV3Strategy` is implemented:
///         `balanceOf` (RAY-scaled), `scaledBalanceOf`, plus pool-only mint/burn.
contract MockAToken is IAToken {
    using SafeERC20 for IERC20;

    address public pool;
    address private immutable _underlyingAsset;
    mapping(address => uint256) internal _scaled;

    constructor(address _pool, address underlyingAsset_) {
        pool = _pool;
        _underlyingAsset = underlyingAsset_;
    }

    function setPool(address _pool) external {
        pool = _pool;
    }

    function scaledBalanceOf(address account) external view override returns (uint256) {
        return _scaled[account];
    }

    function balanceOf(address account) external view override returns (uint256) {
        uint256 index = MockAavePool(pool).liquidityIndex();
        return (_scaled[account] * index) / 1e27;
    }

    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return _underlyingAsset;
    }

    function mintScaled(address to, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _scaled[to] += amount;
    }

    function burnScaled(address from, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        _scaled[from] -= amount;
    }

    function transferUnderlyingTo(address to, uint256 amount) external {
        require(msg.sender == pool, "MockAToken: only pool");
        IERC20(_underlyingAsset).safeTransfer(to, amount);
    }
}

/// @notice Minimal Aave-V3-like Pool that supports `supply`, `withdraw`, and a
///         mutable `liquidityIndex` for simulating yield accrual or non-standard
///         index loss. Like Aave, liquid underlying is held by the aToken.
contract MockAavePool is IAaveV3Pool {
    using SafeERC20 for IERC20;

    uint256 internal constant RAY = 1e27;

    IERC20 public asset;
    MockAToken public aToken;
    uint256 public liquidityIndex = RAY;
    bool public supplyCapReached;

    function setAsset(IERC20 _asset) external {
        asset = _asset;
    }

    function setAToken(MockAToken _aToken) external {
        aToken = _aToken;
    }

    function setLiquidityIndex(uint256 _index) external {
        liquidityIndex = _index;
    }

    function setSupplyCapReached(bool _reached) external {
        supplyCapReached = _reached;
    }

    function supply(address _asset, uint256 _amount, address _onBehalfOf, uint16) external override {
        require(_asset == address(asset), "MockAavePool: asset mismatch");
        require(!supplyCapReached, "MockAavePool: supply cap reached");
        asset.safeTransferFrom(msg.sender, address(aToken), _amount);
        uint256 scaledAmt = (_amount * RAY) / liquidityIndex;
        aToken.mintScaled(_onBehalfOf, scaledAmt);
    }

    function withdraw(address _asset, uint256 _amount, address _to) external override returns (uint256) {
        require(_asset == address(asset), "MockAavePool: asset mismatch");
        uint256 scaledBal = aToken.scaledBalanceOf(msg.sender);
        uint256 currentBal = (scaledBal * liquidityIndex) / RAY;

        uint256 amountOut = _amount == type(uint256).max ? currentBal : _amount;
        require(amountOut <= currentBal, "MockAavePool: insufficient user balance");
        uint256 scaledToBurn = (amountOut * RAY) / liquidityIndex;
        if (scaledToBurn > scaledBal) scaledToBurn = scaledBal;

        aToken.burnScaled(msg.sender, scaledToBurn);
        aToken.transferUnderlyingTo(_to, amountOut);
        return amountOut;
    }

    function getReserveNormalizedIncome(address) external view override returns (uint256) {
        return liquidityIndex;
    }
}
