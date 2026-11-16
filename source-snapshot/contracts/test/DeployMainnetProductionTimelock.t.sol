// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {DeployMainnetProductionTimelock} from "script/DeployMainnetProductionTimelock.s.sol";
import {MainnetProductionTimelockPolicy} from "script/MainnetProductionTimelockPolicy.sol";

contract DeployMainnetProductionTimelockHarness is DeployMainnetProductionTimelock {
    function requireAcknowledgement(string calldata acknowledgement) external pure {
        _requireAcknowledgement(acknowledgement);
    }

    function requireValidProductionTimelock(address timelock) external view {
        MainnetProductionTimelockPolicy.requireValid(timelock);
    }
}

contract DeployProductionTimelockTest is Test {
    DeployMainnetProductionTimelockHarness internal deployScript;

    address internal constant ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    address internal constant PILOT_TIMELOCK = 0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6;
    address internal constant DEPLOYER = address(0xA11CE);
    string internal constant PRODUCTION_ACK = "JPYDF_MAINNET_PRODUCTION_TIMELOCK_12_HOURS";
    bytes32 internal constant EXPECTED_CREATION_CODEHASH =
        0xb63901a8ebd9631adedb9726668993ad7857d8a765ab21994e5b9d5d381c50b9;
    bytes32 internal constant EXPECTED_RUNTIME_CODEHASH =
        0xfbb8dca0ef620c28593dafd8ead5162f233db640a9ebfdc4d47a7920cc06b2af;

    function setUp() external {
        bool canonicalBuild = type(TimelockController).creationCode.length == 8_736
            && keccak256(type(TimelockController).creationCode) == EXPECTED_CREATION_CODEHASH
            && type(TimelockController).runtimeCode.length == 7_454
            && keccak256(type(TimelockController).runtimeCode) == EXPECTED_RUNTIME_CODEHASH;
        if (!canonicalBuild) {
            require(
                !vm.envOr("DF_REQUIRE_CANONICAL_TIMELOCK_TESTS", false),
                "production Timelock tests require FOUNDRY_PROFILE=production-timelock"
            );
            vm.skip(true);
        }
        deployScript = new DeployMainnetProductionTimelockHarness();
        vm.chainId(1);
        vm.etch(ADMIN_SAFE, hex"00");
        vm.setEnv("DEPLOYER", vm.toString(DEPLOYER));
        vm.setEnv("DF_MAINNET_PRODUCTION_TIMELOCK_ACK", PRODUCTION_ACK);
    }

    function testDeploysDistinctSelfAdministeredTwelveHourTimelock() external {
        TimelockController timelock = deployScript.run();

        assertNotEq(address(timelock), PILOT_TIMELOCK);
        assertEq(timelock.getMinDelay(), 12 hours);
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), ADMIN_SAFE));
        assertTrue(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), ADMIN_SAFE));
        assertFalse(timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), DEPLOYER));
        assertFalse(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        deployScript.requireValidProductionTimelock(address(timelock));
    }

    function testPinsReviewedCreationCode() external pure {
        assertEq(type(TimelockController).creationCode.length, 8_736);
        assertEq(keccak256(type(TimelockController).creationCode), EXPECTED_CREATION_CODEHASH);
        assertEq(type(TimelockController).runtimeCode.length, 7_454);
        assertEq(keccak256(type(TimelockController).runtimeCode), EXPECTED_RUNTIME_CODEHASH);
    }

    function testRevertsOnWrongChain() external {
        vm.chainId(11_155_111);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMainnetProductionTimelock.DeployMainnetProductionTimelock__WrongChain.selector, 11_155_111
            )
        );
        deployScript.run();
    }

    function testRevertsWithoutExactProductionAcknowledgement() external {
        vm.expectRevert(
            DeployMainnetProductionTimelock.DeployMainnetProductionTimelock__InvalidAcknowledgement.selector
        );
        deployScript.requireAcknowledgement("wrong");
    }

    function testRevertsForCodelessAdminSafe() external {
        vm.etch(ADMIN_SAFE, bytes(""));

        vm.expectRevert(DeployMainnetProductionTimelock.DeployMainnetProductionTimelock__CodelessAdminSafe.selector);
        deployScript.run();
    }
}

contract DeployProductionTimelockNonCanonicalBuildTest is Test {
    address internal constant ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    string internal constant PRODUCTION_ACK = "JPYDF_MAINNET_PRODUCTION_TIMELOCK_12_HOURS";
    bytes32 internal constant EXPECTED_CREATION_CODEHASH =
        0xb63901a8ebd9631adedb9726668993ad7857d8a765ab21994e5b9d5d381c50b9;

    function testRejectsNonCanonicalBuildBeforeBroadcast() external {
        if (keccak256(type(TimelockController).creationCode) == EXPECTED_CREATION_CODEHASH) vm.skip(true);

        vm.chainId(1);
        vm.setEnv("DF_MAINNET_PRODUCTION_TIMELOCK_ACK", PRODUCTION_ACK);
        vm.etch(ADMIN_SAFE, hex"00");

        DeployMainnetProductionTimelockHarness deployScript = new DeployMainnetProductionTimelockHarness();
        vm.expectRevert(DeployMainnetProductionTimelock.DeployMainnetProductionTimelock__NonCanonicalBuild.selector);
        deployScript.run();
    }

    function testPolicyRejectsNonCanonicalRuntime() external {
        if (keccak256(type(TimelockController).creationCode) == EXPECTED_CREATION_CODEHASH) vm.skip(true);

        address[] memory roleHolders = new address[](1);
        roleHolders[0] = ADMIN_SAFE;
        TimelockController timelock = new TimelockController(12 hours, roleHolders, roleHolders, address(0));
        DeployMainnetProductionTimelockHarness deployScript = new DeployMainnetProductionTimelockHarness();

        vm.expectRevert(MainnetProductionTimelockPolicy.RuntimeCodehashMismatch.selector);
        deployScript.requireValidProductionTimelock(address(timelock));
    }
}
