// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {DefaultPool} from "src/DefaultPool.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

/// @notice Focused evidence for every externally callable DefaultPool surface.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract DefaultPoolVerification is DevTestSetup {
    event CollTokenAddressChanged(address _newCollTokenAddress);
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolJpydfDebtUpdated(uint256 _jpydfDebt);
    event DefaultPoolCollBalanceUpdated(uint256 _collBalance);

    function testConstructorWiringApprovalAndEvents() external {
        vm.recordLogs();
        DefaultPool freshPool = new DefaultPool(addressesRegistry);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(freshPool.NAME(), "DefaultPool");
        assertEq(address(freshPool.collToken()), address(collToken));
        assertEq(freshPool.troveManagerAddress(), address(troveManager));
        assertEq(freshPool.activePoolAddress(), address(activePool));
        assertEq(collToken.allowance(address(freshPool), address(activePool)), type(uint256).max);

        assertEq(logs.length, 4);
        assertEq(logs[0].emitter, address(freshPool));
        assertEq(logs[0].topics[0], keccak256("CollTokenAddressChanged(address)"));
        assertEq(abi.decode(logs[0].data, (address)), address(collToken));
        assertEq(logs[1].topics[0], keccak256("TroveManagerAddressChanged(address)"));
        assertEq(abi.decode(logs[1].data, (address)), address(troveManager));
        assertEq(logs[2].topics[0], keccak256("ActivePoolAddressChanged(address)"));
        assertEq(abi.decode(logs[2].data, (address)), address(activePool));
        assertEq(logs[3].emitter, address(collToken));
        assertEq(logs[3].topics[0], keccak256("Approval(address,address,uint256)"));
        assertEq(address(uint160(uint256(logs[3].topics[1]))), address(freshPool));
        assertEq(address(uint160(uint256(logs[3].topics[2]))), address(activePool));
        assertEq(abi.decode(logs[3].data, (uint256)), type(uint256).max);
    }

    function testCollateralRoundTripAccountsAndEmits() external {
        DefaultPool pool = DefaultPool(address(defaultPool));
        uint256 amount = 10 ether;

        // The production ActivePool records collateral only after it has actually received it.
        deal(address(collToken), address(activePool), amount);
        vm.prank(address(borrowerOperations));
        activePool.accountForReceivedColl(amount);

        vm.recordLogs();
        vm.prank(address(troveManager));
        activePool.sendCollToDefaultPool(amount);
        Vm.Log[] memory toDefaultPoolLogs = vm.getRecordedLogs();

        assertEq(activePool.getCollBalance(), 0);
        assertEq(pool.getCollBalance(), amount);
        assertEq(collToken.balanceOf(address(defaultPool)), amount);
        assertEq(toDefaultPoolLogs.length, 3);
        assertEq(toDefaultPoolLogs[0].topics[0], keccak256("ActivePoolCollBalanceUpdated(uint256)"));
        assertEq(toDefaultPoolLogs[2].emitter, address(pool));
        assertEq(toDefaultPoolLogs[2].topics[0], keccak256("DefaultPoolCollBalanceUpdated(uint256)"));
        assertEq(abi.decode(toDefaultPoolLogs[2].data, (uint256)), amount);

        vm.expectEmit(false, false, false, true, address(pool));
        emit DefaultPoolCollBalanceUpdated(0);
        vm.prank(address(troveManager));
        pool.sendCollToActivePool(amount);

        assertEq(pool.getCollBalance(), 0);
        assertEq(activePool.getCollBalance(), amount);
        assertEq(collToken.balanceOf(address(defaultPool)), 0);
        assertEq(collToken.balanceOf(address(activePool)), amount);
    }

    function testDebtAccountingViewsAndEvents() external {
        DefaultPool pool = DefaultPool(address(defaultPool));
        uint256 increase = 7 ether;
        uint256 decrease = 2 ether;

        vm.recordLogs();
        vm.prank(address(troveManager));
        pool.increaseJpydfDebt(increase);
        vm.prank(address(troveManager));
        pool.decreaseJpydfDebt(decrease);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(pool.getJpydfDebt(), increase - decrease);
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(pool));
        assertEq(logs[0].topics[0], keccak256("DefaultPoolJpydfDebtUpdated(uint256)"));
        assertEq(abi.decode(logs[0].data, (uint256)), increase);
        assertEq(logs[1].topics[0], keccak256("DefaultPoolJpydfDebtUpdated(uint256)"));
        assertEq(abi.decode(logs[1].data, (uint256)), increase - decrease);
    }

    function testCallerGuardsAndAccountingCannotUnderflow() external {
        DefaultPool pool = DefaultPool(address(defaultPool));

        vm.expectRevert(bytes("DefaultPool: Caller is not the ActivePool"));
        pool.receiveColl(0);
        vm.expectRevert(bytes("DefaultPool: Caller is not the TroveManager"));
        pool.sendCollToActivePool(0);
        vm.expectRevert(bytes("DefaultPool: Caller is not the TroveManager"));
        pool.increaseJpydfDebt(0);
        vm.expectRevert(bytes("DefaultPool: Caller is not the TroveManager"));
        pool.decreaseJpydfDebt(0);

        vm.prank(address(troveManager));
        vm.expectRevert();
        pool.sendCollToActivePool(1);
        vm.prank(address(troveManager));
        vm.expectRevert();
        pool.decreaseJpydfDebt(1);
    }
}
