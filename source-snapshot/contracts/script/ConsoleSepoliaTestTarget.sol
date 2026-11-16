// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Harmless, immutable-authority target for Admin Console Safe/Timelock E2E on Sepolia.
/// @dev This contract deliberately mirrors only the CollateralVault selectors used by the
///      Issue #1201 testbed. It is not a protocol component and must never hold assets.
contract ConsoleSepoliaTestTarget {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant WRITEOFF_ROLE = keccak256("WRITEOFF_ROLE");

    error RoleRequired(bytes32 role, address account);
    error ZeroAddress();

    event WithdrawDelayUpdated(uint256 previousDelay, uint256 newDelay, address indexed caller);
    event DepositPaused(address indexed caller);
    event DepositUnpaused(address indexed caller);

    address public immutable safe;
    address public immutable timelock;
    address public immutable underlying;
    address public immutable treasury;

    uint256 public withdrawDelay = 3600;
    bool public pausedDeposit;
    address public lastUpdater;
    uint256 public updateCount;

    constructor(address safe_, address timelock_, address underlying_) {
        if (safe_ == address(0) || timelock_ == address(0) || underlying_ == address(0)) {
            revert ZeroAddress();
        }
        safe = safe_;
        timelock = timelock_;
        underlying = underlying_;
        treasury = safe_;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) return account == address(this);
        if (role == GOV_ROLE) return account == timelock;
        if (role == GUARDIAN_ROLE) return account == safe;
        return false;
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    function setWithdrawDelay(uint256 newDelay) external {
        _requireCaller(GOV_ROLE, timelock);
        uint256 previousDelay = withdrawDelay;
        withdrawDelay = newDelay;
        lastUpdater = msg.sender;
        updateCount++;
        emit WithdrawDelayUpdated(previousDelay, newDelay, msg.sender);
    }

    function pauseDeposit() external {
        _requireCaller(GUARDIAN_ROLE, safe);
        pausedDeposit = true;
        lastUpdater = msg.sender;
        updateCount++;
        emit DepositPaused(msg.sender);
    }

    function unpauseDeposit() external {
        _requireCaller(GOV_ROLE, timelock);
        pausedDeposit = false;
        lastUpdater = msg.sender;
        updateCount++;
        emit DepositUnpaused(msg.sender);
    }

    // Benign CollateralVault-compatible views keep the existing Console card on the
    // production code path while the binding points only branch 0 at this test target.
    function bufferBalance() external pure returns (uint256) {
        return 0;
    }

    function backstopBalance() external pure returns (uint256) {
        return 0;
    }

    function totalUnderlying() external pure returns (uint256) {
        return 0;
    }

    function actualLiabilities() external pure returns (uint256) {
        return 0;
    }

    function backingRatio() external pure returns (uint256) {
        return 1e18;
    }

    function backingRatioForPricing() external pure returns (uint256, bool) {
        return (1e18, true);
    }

    function backingShortfall() external pure returns (uint256) {
        return 0;
    }

    function bufferTargetBps() external pure returns (uint256) {
        return 0;
    }

    function bufferFloor() external pure returns (uint256) {
        return 0;
    }

    function pendingWithdrawals() external pure returns (uint256) {
        return 0;
    }

    function pausedRedeem() external pure returns (bool) {
        return false;
    }

    function pausedClaim() external pure returns (bool) {
        return false;
    }

    function pausedAllocation() external pure returns (bool) {
        return false;
    }

    function allocateMaxMove() external pure returns (uint256) {
        return 0;
    }

    function allocatorCooldown() external pure returns (uint256) {
        return 0;
    }

    function lastAllocatorTime() external pure returns (uint256) {
        return 0;
    }

    function totalWeightBps() external pure returns (uint256) {
        return 0;
    }

    function strategyValuationMaxAge() external pure returns (uint256) {
        return 0;
    }

    function _requireCaller(bytes32 role, address expected) private view {
        if (msg.sender != expected) revert RoleRequired(role, msg.sender);
    }
}
