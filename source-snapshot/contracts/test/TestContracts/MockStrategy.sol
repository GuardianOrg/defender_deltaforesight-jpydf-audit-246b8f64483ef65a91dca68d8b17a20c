// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.24;

import "../../src/Strategies/BaseStrategy.sol";

/**
 * @title MockStrategy - Mock Strategy for Testing (push model, Upgradeable)
 * @notice Holds funds within this contract instead of a real yield protocol.
 *         Simulated yield can be injected via `setMockYield` so tests can
 *         exercise `realizedYield()` / `sendProfitToVault()` flows without an
 *         external protocol fork.
 */
contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    /// @notice Simulated yield (in underlying terms; for testing)
    uint256 public mockYield;

    /// @notice Underlying physically deposited via `_doDeposit` (not principal accounting)
    uint256 public deposited;

    // =============================================================
    //                          EVENTS
    // =============================================================

    event MockDeposited(uint256 amount);
    event MockWithdrawn(uint256 amount);
    event MockYieldSet(uint256 yield);

    // =============================================================
    //                        INITIALIZER
    // =============================================================

    function initialize(address _vault, IERC20 _underlying, address _owner) external initializer {
        __BaseStrategy_init(_vault, _underlying, _owner, _owner);
    }

    // =============================================================
    //                  BaseStrategy HOOKS
    // =============================================================

    /// @inheritdoc BaseStrategy
    /// @dev Underlying has already been transferred to this contract by the
    ///      Vault. We just record it.
    function _doDeposit(uint256 _amount) internal override {
        deposited += _amount;
        emit MockDeposited(_amount);
    }

    /// @inheritdoc BaseStrategy
    /// @dev Withdraws underlying held by this contract. Pulls from the
    ///      simulated yield first, then from the deposited principal.
    ///      The underlying stays in THIS contract so the Vault can pull it
    ///      via `safeTransferFrom` inside `receiveFromStrategy`.
    function _doWithdraw(uint256 _amount) internal override returns (uint256 actual) {
        uint256 available = underlyingToken.balanceOf(address(this));
        actual = _amount > available ? available : _amount;
        if (actual > 0) {
            if (actual <= mockYield) {
                mockYield -= actual;
            } else {
                uint256 fromDeposited = actual - mockYield;
                mockYield = 0;
                deposited = deposited > fromDeposited ? deposited - fromDeposited : 0;
            }
            emit MockWithdrawn(actual);
        }
    }

    /// @inheritdoc BaseStrategy
    function _estimatedTotalUnderlying() internal view override returns (uint256) {
        // Simulated total: physically deposited + simulated yield.
        return deposited + mockYield;
    }

    // =============================================================
    //                     TEST HELPERS
    // =============================================================

    function setMockYield(uint256 _yield) external onlyOwner {
        mockYield = _yield;
        emit MockYieldSet(_yield);
    }

    /// @notice Directly inject underlying for yield simulation. Callers must
    ///         have already approved this contract.
    function injectUnderlying(uint256 _amount) external {
        underlyingToken.safeTransferFrom(msg.sender, address(this), _amount);
    }
}
