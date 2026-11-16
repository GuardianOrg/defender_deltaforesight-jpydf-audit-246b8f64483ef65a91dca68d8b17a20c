// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/Strategies/MorphoV2Strategy.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Candidate-specific I-07 evidence. The venue and Strategy are real;
/// this contract supplies only the Vault authorization/receipt boundary.
/// USDC funding and time changes are local fork fixtures, never live transactions.
contract PrestoRoundingMainnetTest is Test {
    IMorphoVaultV2 constant VENUE = IMorphoVaultV2(0x133614490896bc02C774bc3399E4Db1B6D05a2CA);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MorphoV2Strategy strategy;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), vm.envUint("PRESTO_BLOCK"));
        strategy = MorphoV2Strategy(
            address(
                new ERC1967Proxy(
                    address(new MorphoV2Strategy()),
                    abi.encodeCall(
                        MorphoV2Strategy.initialize, (address(this), USDC, address(this), address(this), VENUE, 200)
                    )
                )
            )
        );
        // Deposit in setUp: the venue's per-transaction transient accrual guard
        // must reset before the later harvest transaction.
        _deposit(100_000e6);
    }

    function hasRole(bytes32, address account) external view returns (bool) {
        return account == address(this);
    }

    function receiveFromStrategy(uint256 amount) external returns (uint256) {
        require(msg.sender == address(strategy));
        uint256 before_ = USDC.balanceOf(address(this));
        USDC.transferFrom(msg.sender, address(this), amount);
        return USDC.balanceOf(address(this)) - before_;
    }

    function _deposit(uint256 amount) internal {
        deal(address(USDC), address(strategy), amount);
        assertEq(strategy.deposit(amount, amount), amount, "actual venue deposit must succeed");
        assertEq(strategy.principal(), amount);
        assertGt(strategy.ownShares(), 0);
        assertLe(amount - strategy.estimatedTotalUnderlying(), 1, "deposit floor at most one USDC base unit");
    }

    function _withdraw(uint256 requested) internal returns (uint256 received) {
        uint256 sharesBefore = strategy.ownShares();
        uint256 valueBefore = strategy.estimatedTotalUnderlying();
        uint256 balanceBefore = USDC.balanceOf(address(this));
        uint256 quotedBurn = VENUE.previewWithdraw(requested);
        received = strategy.sendToVault(requested);
        assertEq(received, requested, "must exercise full request, not fail-soft zero/half");
        assertEq(USDC.balanceOf(address(this)) - balanceBefore, received);
        uint256 burned = sharesBefore - strategy.ownShares();
        uint256 valueAfter = strategy.estimatedTotalUnderlying();
        assertLe(valueBefore - valueAfter, received + 1, "ceil-share loss at most one asset base unit");
        assertEq(quotedBurn, burned, "actual burn equals pre-withdraw ceil quote");
        assertEq(VENUE.previewRedeem(1), 0, "smallest share is below one asset base unit");
        emit log_named_uint("withdraw_assets", received);
        emit log_named_uint("withdraw_burned_share_units", burned);
        emit log_named_uint("withdraw_valuation_loss_base_units", valueBefore - valueAfter - received);
    }

    function test_PrestoPartialFullAndEmergencyDust() public {
        _withdraw(12_345e6 + 1);
        uint256 available = strategy.estimatedTotalUnderlying();
        _withdraw(available);
        assertEq(strategy.estimatedTotalUnderlying(), 0);
        assertLe(strategy.principal(), 2, "bounded residual from two floor/ceil cycles");
        uint256 dust = strategy.ownShares();
        strategy.emergencyWithdrawFromMorphoV2(type(uint256).max);
        assertEq(strategy.ownShares(), 0);
        assertEq(VENUE.balanceOf(address(strategy)), 0);
        emit log_named_uint("full_withdraw_residual_principal_base_units", strategy.principal());
        emit log_named_uint("emergency_cleanup_share_units", dust);
    }

    function testFuzz_PrestoPartialRounding(uint96 rawWithdrawal) public {
        _withdraw(bound(uint256(rawWithdrawal), 1, 50_000e6));
    }

    function test_PrestoHarvestAfterAccrual() public {
        vm.warp(block.timestamp + 1 days);
        uint256 yieldBefore = strategy.realizedYield();
        assertGt(yieldBefore, 0, "harvest must exercise nonzero real accrued yield");
        uint256 principalBefore = strategy.principal();
        uint256 balanceBefore = USDC.balanceOf(address(this));
        uint256 sent = strategy.sendProfitToVault();
        assertEq(sent, yieldBefore);
        assertEq(USDC.balanceOf(address(this)) - balanceBefore, sent);
        assertEq(strategy.principal(), principalBefore);
        uint256 remaining = strategy.estimatedTotalUnderlying();
        assertGe(remaining + 1, principalBefore, "harvest rounding bounded to one USDC base unit");
        emit log_named_uint("harvest_assets", sent);
        emit log_named_uint("harvest_remaining_value", remaining);
        emit log_named_uint("harvest_principal", principalBefore);
    }
}
