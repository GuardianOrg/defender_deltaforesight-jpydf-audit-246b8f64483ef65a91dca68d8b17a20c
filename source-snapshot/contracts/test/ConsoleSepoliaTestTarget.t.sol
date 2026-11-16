// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ConsoleSepoliaTestTarget} from "script/ConsoleSepoliaTestTarget.sol";

contract ConsoleSepoliaTestTargetTest is Test {
    address private constant SAFE = address(0x1201);
    address private constant UNDERLYING = address(0x1202);
    uint256 private constant DELAY = 3;

    TimelockController private timelock;
    ConsoleSepoliaTestTarget private target;

    function setUp() external {
        address[] memory proposers = new address[](1);
        proposers[0] = SAFE;
        address[] memory executors = new address[](1);
        executors[0] = SAFE;
        timelock = new TimelockController(DELAY, proposers, executors, address(0));
        target = new ConsoleSepoliaTestTarget(SAFE, address(timelock), UNDERLYING);
    }

    function testRolesAreLimitedToSafeAndTimelock() external view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), SAFE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), SAFE));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), SAFE));
        assertFalse(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), SAFE));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        assertTrue(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock)));

        assertTrue(target.hasRole(target.GUARDIAN_ROLE(), SAFE));
        assertTrue(target.hasRole(target.GOV_ROLE(), address(timelock)));
        assertTrue(target.hasRole(target.DEFAULT_ADMIN_ROLE(), address(target)));
        assertFalse(target.hasRole(target.GOV_ROLE(), SAFE));
        assertFalse(target.hasRole(target.GUARDIAN_ROLE(), address(timelock)));
        assertFalse(target.hasRole(target.ALLOCATOR_ROLE(), SAFE));
        assertFalse(target.hasRole(target.WRITEOFF_ROLE(), SAFE));
    }

    function testDirectSafeActionIsHarmlessAndTracked() external {
        vm.prank(SAFE);
        target.pauseDeposit();

        assertTrue(target.pausedDeposit());
        assertEq(target.lastUpdater(), SAFE);
        assertEq(target.updateCount(), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConsoleSepoliaTestTarget.RoleRequired.selector,
                target.GUARDIAN_ROLE(),
                address(this)
            )
        );
        target.pauseDeposit();
    }

    function testTimelockScheduleExecuteAndCancel() external {
        bytes memory data = abi.encodeCall(ConsoleSepoliaTestTarget.setWithdrawDelay, (7200));
        bytes32 predecessor;
        bytes32 salt = keccak256("execute");

        vm.prank(SAFE);
        timelock.schedule(address(target), 0, data, predecessor, salt, DELAY);
        bytes32 operationId = timelock.hashOperation(address(target), 0, data, predecessor, salt);
        assertTrue(timelock.isOperationPending(operationId));

        vm.warp(block.timestamp + DELAY);
        vm.prank(SAFE);
        timelock.execute(address(target), 0, data, predecessor, salt);
        assertTrue(timelock.isOperationDone(operationId));
        assertEq(target.withdrawDelay(), 7200);
        assertEq(target.lastUpdater(), address(timelock));

        bytes memory cancelData = abi.encodeCall(ConsoleSepoliaTestTarget.setWithdrawDelay, (10_800));
        bytes32 cancelSalt = keccak256("cancel");
        vm.prank(SAFE);
        timelock.schedule(address(target), 0, cancelData, predecessor, cancelSalt, DELAY);
        bytes32 cancelId = timelock.hashOperation(address(target), 0, cancelData, predecessor, cancelSalt);

        vm.prank(SAFE);
        timelock.cancel(cancelId);
        assertFalse(timelock.isOperation(cancelId));
        assertEq(target.withdrawDelay(), 7200);
    }
}
