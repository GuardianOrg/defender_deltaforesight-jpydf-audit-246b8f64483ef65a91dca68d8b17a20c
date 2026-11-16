// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

/// @dev Deploys the five-minute Timelock used only by the August 2026
///      TEST_ONLY_NOT_FOR_PRODUCTION mainnet pilot. Production keeps the
///      canonical 12-hour delay and must use a separate deployment.
contract DeployMainnetPilotTimelock is Script {
    uint256 public constant PILOT_MIN_DELAY = 5 minutes;
    address public constant ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;

    string internal constant PILOT_ACK = "JPYDF_MAINNET_TEST_ONLY_TIMELOCK_5_MINUTES_NOT_FOR_PRODUCTION";

    error DeployMainnetPilotTimelock__WrongChain(uint256 chainId);
    error DeployMainnetPilotTimelock__InvalidAcknowledgement();
    error DeployMainnetPilotTimelock__CodelessAdminSafe();
    error DeployMainnetPilotTimelock__ZeroDeployer();
    error DeployMainnetPilotTimelock__RoleMismatch();

    function run() external returns (TimelockController timelock) {
        if (block.chainid != 1) revert DeployMainnetPilotTimelock__WrongChain(block.chainid);
        _requireAcknowledgement(vm.envString("DF_MAINNET_PILOT_TIMELOCK_ACK"));
        if (ADMIN_SAFE.code.length == 0) revert DeployMainnetPilotTimelock__CodelessAdminSafe();

        bytes memory rawDeployer = vm.envBytes("DEPLOYER");
        ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", rawDeployer);
        address deployer = vm.envAddress("DEPLOYER");
        if (deployer == address(0)) revert DeployMainnetPilotTimelock__ZeroDeployer();

        address[] memory proposers = new address[](1);
        proposers[0] = ADMIN_SAFE;
        address[] memory executors = new address[](1);
        executors[0] = ADMIN_SAFE;

        vm.startBroadcast(deployer);
        timelock = new TimelockController(PILOT_MIN_DELAY, proposers, executors, address(0));
        vm.stopBroadcast();

        _verify(timelock, deployer);

        console2.log("Mainnet test-only pilot Timelock", address(timelock));
        console2.log("Pilot minDelay", timelock.getMinDelay());
        console2.logBytes32(address(timelock).codehash);
    }

    function _requireAcknowledgement(string memory acknowledgement) internal pure {
        if (keccak256(bytes(acknowledgement)) != keccak256(bytes(PILOT_ACK))) {
            revert DeployMainnetPilotTimelock__InvalidAcknowledgement();
        }
    }

    function _verify(TimelockController timelock, address deployer) internal view {
        if (address(timelock).codehash != keccak256(type(TimelockController).runtimeCode)) {
            revert DeployMainnetPilotTimelock__RoleMismatch();
        }
        if (timelock.getMinDelay() != PILOT_MIN_DELAY) revert DeployMainnetPilotTimelock__RoleMismatch();
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetPilotTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.EXECUTOR_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetPilotTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.CANCELLER_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetPilotTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock))) {
            revert DeployMainnetPilotTimelock__RoleMismatch();
        }
        if (
            timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), ADMIN_SAFE)
                || timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), deployer)
                || timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0))
        ) revert DeployMainnetPilotTimelock__RoleMismatch();
    }
}
