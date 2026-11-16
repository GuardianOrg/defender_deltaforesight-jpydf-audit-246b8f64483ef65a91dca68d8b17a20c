// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {FinalizeConsoleDevnetTimelockHandover} from "script/FinalizeConsoleDevnetTimelockHandover.s.sol";
import {PrepareConsoleDevnetTimelockHandover} from "script/PrepareConsoleDevnetTimelockHandover.s.sol";

contract ConsoleDevnetNotATimelock {}

contract ConsoleDevnetOwnableMock {
    address public owner;
    address public pendingOwner;

    constructor(address initialOwner) {
        owner = initialOwner;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "not owner");
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}

contract PrepareConsoleDevnetTimelockHandoverHarness is PrepareConsoleDevnetTimelockHandover {
    function verifyTimelock(address timelock, address operator) external view {
        Config memory cfg;
        cfg.timelock = timelock;
        cfg.currentAdmin = operator;
        _verifyTimelockConfiguration(cfg);
    }
}

contract FinalizeConsoleDevnetTimelockHandoverHarness is FinalizeConsoleDevnetTimelockHandover {
    function loadConfig() external view {
        _loadConfig();
    }

    function verifyTimelock(TimelockController timelock, address operator) external view {
        Config memory cfg;
        cfg.timelock = timelock;
        cfg.operator = operator;
        _verifyTimelockRoles(cfg);
    }

    function acceptThroughTimelock(TimelockController timelock, address target) external {
        Config memory cfg;
        cfg.timelock = timelock;
        _acceptThroughTimelock(cfg, target, "mock");
    }

    function setFinalDelayThroughTimelock(TimelockController timelock, uint256 finalDelay) external {
        Config memory cfg;
        cfg.timelock = timelock;
        cfg.finalDelay = finalDelay;
        _setFinalDelayThroughTimelock(cfg);
    }
}

contract ConsoleDevnetTimelockHandoverTest is Test {
    PrepareConsoleDevnetTimelockHandoverHarness internal prepare;
    FinalizeConsoleDevnetTimelockHandoverHarness internal finalize;

    function setUp() external {
        vm.warp(1 days);
        prepare = new PrepareConsoleDevnetTimelockHandoverHarness();
        finalize = new FinalizeConsoleDevnetTimelockHandoverHarness();
    }

    function testPrepareAcceptsExpectedBootstrapTimelock() external {
        TimelockController timelock = _timelock(0, address(this), address(this));
        prepare.verifyTimelock(address(timelock), address(this));
    }

    function testPrepareRejectsCodedNonTimelock() external {
        ConsoleDevnetNotATimelock target = new ConsoleDevnetNotATimelock();

        vm.expectRevert("Console devnet prepare: Timelock implementation");
        prepare.verifyTimelock(address(target), address(this));
    }

    function testPrepareRejectsNonzeroBootstrapDelay() external {
        TimelockController timelock = _timelock(1, address(this), address(this));

        vm.expectRevert("Console devnet prepare: bootstrap delay");
        prepare.verifyTimelock(address(timelock), address(this));
    }

    function testPrepareRejectsOperatorWithoutRoles() external {
        TimelockController timelock = _timelock(0, address(0xBEEF), address(0xBEEF));

        vm.expectRevert("Console devnet prepare: Timelock proposer");
        prepare.verifyTimelock(address(timelock), address(this));
    }

    function testFinalizeRejectsCodedNonTimelock() external {
        ConsoleDevnetNotATimelock target = new ConsoleDevnetNotATimelock();

        vm.expectRevert("Console devnet handover: Timelock implementation");
        finalize.verifyTimelock(TimelockController(payable(address(target))), address(this));
    }

    function testFinalizeRejectsBroadcasterDifferentFromCurrentAdmin() external {
        uint256 operatorPrivateKey = 0xA11CE;
        address operator = vm.addr(operatorPrivateKey);
        TimelockController timelock = _timelock(0, operator, operator);

        vm.setEnv("DF_TIMELOCK", vm.toString(address(timelock)));
        vm.setEnv("DEVNET_OPERATOR_PRIVATE_KEY", vm.toString(operatorPrivateKey));
        vm.setEnv("DF_CURRENT_ADMIN", vm.toString(address(0xBEEF)));
        vm.setEnv("DEVNET_TIMELOCK_MIN_DELAY", "30");

        vm.expectRevert("Console devnet handover: broadcaster != admin");
        finalize.loadConfig();
    }

    function testFinalizeAcceptsOwnershipFromUnscheduledState() external {
        TimelockController timelock = _finalizerTimelock();
        ConsoleDevnetOwnableMock target = _pendingOwnable(timelock);

        finalize.acceptThroughTimelock(timelock, address(target));

        assertEq(target.owner(), address(timelock));
        assertEq(target.pendingOwner(), address(0));
    }

    function testFinalizeResumesScheduledOwnershipAcceptance() external {
        TimelockController timelock = _finalizerTimelock();
        ConsoleDevnetOwnableMock target = _pendingOwnable(timelock);
        bytes memory data = abi.encodeCall(ConsoleDevnetOwnableMock.acceptOwnership, ());
        bytes32 salt = keccak256(abi.encode("console-devnet-accept", block.chainid, address(target)));
        bytes32 operationId = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, 0);

        assertTrue(timelock.isOperationReady(operationId));
        finalize.acceptThroughTimelock(timelock, address(target));

        assertTrue(timelock.isOperationDone(operationId));
        assertEq(target.owner(), address(timelock));
        assertEq(target.pendingOwner(), address(0));
    }

    function testFinalizeResumesScheduledDelayUpdate() external {
        TimelockController timelock = _finalizerTimelock();
        uint256 finalDelay = 30;
        bytes memory data = abi.encodeCall(TimelockController.updateDelay, (finalDelay));
        bytes32 salt = keccak256(abi.encode("console-devnet-delay", block.chainid, address(timelock), finalDelay));
        bytes32 operationId = timelock.hashOperation(address(timelock), 0, data, bytes32(0), salt);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, 0);

        assertTrue(timelock.isOperationReady(operationId));
        finalize.setFinalDelayThroughTimelock(timelock, finalDelay);

        assertTrue(timelock.isOperationDone(operationId));
        assertEq(timelock.getMinDelay(), finalDelay);
    }

    function testFinalizeCompletedStateCanBeVerifiedAgain() external {
        TimelockController timelock = _finalizerTimelock();
        ConsoleDevnetOwnableMock target = _pendingOwnable(timelock);

        finalize.acceptThroughTimelock(timelock, address(target));
        finalize.acceptThroughTimelock(timelock, address(target));
        finalize.setFinalDelayThroughTimelock(timelock, 30);
        finalize.setFinalDelayThroughTimelock(timelock, 30);

        assertEq(target.owner(), address(timelock));
        assertEq(timelock.getMinDelay(), 30);
    }

    function _pendingOwnable(TimelockController timelock) internal returns (ConsoleDevnetOwnableMock target) {
        target = new ConsoleDevnetOwnableMock(address(this));
        target.transferOwnership(address(timelock));
    }

    function _finalizerTimelock() internal returns (TimelockController) {
        return _timelock(0, address(this), address(finalize));
    }

    function _timelock(uint256 delay, address proposer, address executor)
        internal
        returns (TimelockController timelock)
    {
        address[] memory proposers = new address[](2);
        proposers[0] = proposer;
        proposers[1] = address(finalize);
        address[] memory executors = new address[](2);
        executors[0] = executor;
        executors[1] = address(finalize);
        timelock = new TimelockController(delay, proposers, executors, address(0));
    }
}
