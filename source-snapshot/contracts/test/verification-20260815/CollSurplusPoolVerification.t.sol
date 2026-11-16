// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {CollSurplusPool} from "src/CollSurplusPool.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

/// @notice Focused evidence for all externally callable CollSurplusPool surfaces.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract CollSurplusPoolVerification is DevTestSetup {
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event CollBalanceUpdated(address indexed _account, uint256 _newBalance);
    event CollSent(address indexed _to, uint256 _amount);

    function testConstructorWiringAndEvents() external {
        vm.recordLogs();
        CollSurplusPool fresh = new CollSurplusPool(addressesRegistry);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(fresh.NAME(), "CollSurplusPool");
        assertEq(address(fresh.collToken()), address(collToken));
        assertEq(fresh.borrowerOperationsAddress(), address(borrowerOperations));
        assertEq(fresh.troveManagerAddress(), address(troveManager));
        assertEq(fresh.getCollBalance(), 0);
        assertEq(fresh.getCollateral(A), 0);
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], keccak256("BorrowerOperationsAddressChanged(address)"));
        assertEq(abi.decode(logs[0].data, (address)), address(borrowerOperations));
        assertEq(logs[1].topics[0], keccak256("TroveManagerAddressChanged(address)"));
        assertEq(abi.decode(logs[1].data, (address)), address(troveManager));
    }

    function testAccountAndClaimSurplusWithEvents() external {
        CollSurplusPool pool = CollSurplusPool(address(collSurplusPool));
        uint256 amount = 10 ether;
        uint256 balanceBefore = collToken.balanceOf(A);
        deal(address(collToken), address(pool), amount);

        vm.expectEmit(true, false, false, true, address(pool));
        emit CollBalanceUpdated(A, amount);
        vm.prank(address(troveManager));
        pool.accountSurplus(A, amount);
        assertEq(pool.getCollateral(A), amount);
        assertEq(pool.getCollBalance(), amount);
        assertEq(collToken.balanceOf(address(pool)), amount);

        vm.expectEmit(true, false, false, true, address(pool));
        emit CollBalanceUpdated(A, 0);
        vm.expectEmit(true, false, false, true, address(pool));
        emit CollSent(A, amount);
        vm.prank(address(borrowerOperations));
        pool.claimColl(A);
        assertEq(pool.getCollateral(A), 0);
        assertEq(pool.getCollBalance(), 0);
        assertEq(collToken.balanceOf(address(pool)), 0);
        assertEq(collToken.balanceOf(A), balanceBefore + amount);

        vm.prank(address(borrowerOperations));
        vm.expectRevert(bytes("CollSurplusPool: No collateral available to claim"));
        pool.claimColl(A);
    }

    function testCallerGuards() external {
        CollSurplusPool pool = CollSurplusPool(address(collSurplusPool));

        vm.expectRevert(bytes("CollSurplusPool: Caller is not TroveManager"));
        pool.accountSurplus(A, 0);
        vm.expectRevert(bytes("CollSurplusPool: Caller is not Borrower Operations"));
        pool.claimColl(A);
    }
}
