// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {DeployMainnetPilotTimelock} from "script/DeployMainnetPilotTimelock.s.sol";

contract DeployMainnetPilotTimelockHarness is DeployMainnetPilotTimelock {
    function requireAcknowledgement(string calldata acknowledgement) external pure {
        _requireAcknowledgement(acknowledgement);
    }
}

contract DeployMainnetPilotTimelockTest is Test {
    DeployMainnetPilotTimelockHarness internal deployScript;

    address internal constant ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    address internal constant DEPLOYER = address(0xA11CE);
    string internal constant PILOT_ACK = "JPYDF_MAINNET_TEST_ONLY_TIMELOCK_5_MINUTES_NOT_FOR_PRODUCTION";

    function setUp() external {
        deployScript = new DeployMainnetPilotTimelockHarness();
        vm.chainId(1);
        vm.etch(ADMIN_SAFE, hex"00");
        vm.setEnv("DEPLOYER", vm.toString(DEPLOYER));
        vm.setEnv("DF_MAINNET_PILOT_TIMELOCK_ACK", PILOT_ACK);
    }

    function testDeploysSelfAdministeredFiveMinuteTimelock() external {
        TimelockController timelock = deployScript.run();

        assertEq(timelock.getMinDelay(), 5 minutes);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), ADMIN_SAFE));
        assertFalse(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), DEPLOYER));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function testRevertsOnWrongChain() external {
        vm.chainId(11_155_111);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMainnetPilotTimelock.DeployMainnetPilotTimelock__WrongChain.selector, 11_155_111
            )
        );
        deployScript.run();
    }

    function testRevertsWithoutExactPilotAcknowledgement() external {
        vm.expectRevert(DeployMainnetPilotTimelock.DeployMainnetPilotTimelock__InvalidAcknowledgement.selector);
        deployScript.requireAcknowledgement("wrong");
    }

    function testRevertsForCodelessAdminSafe() external {
        vm.etch(ADMIN_SAFE, bytes(""));

        vm.expectRevert(DeployMainnetPilotTimelock.DeployMainnetPilotTimelock__CodelessAdminSafe.selector);
        deployScript.run();
    }
}
