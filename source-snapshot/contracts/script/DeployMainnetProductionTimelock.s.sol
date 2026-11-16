// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

/// @dev Deploys the 12-hour Timelock used by production. The five-minute
///      mainnet pilot keeps its existing, separate Timelock deployment.
contract DeployMainnetProductionTimelock is Script {
    uint256 public constant PRODUCTION_MIN_DELAY = 12 hours;
    address public constant ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    uint256 public constant PRODUCTION_CREATION_CODE_LENGTH = 8_736;
    bytes32 public constant PRODUCTION_CREATION_CODEHASH =
        0xb63901a8ebd9631adedb9726668993ad7857d8a765ab21994e5b9d5d381c50b9;
    uint256 public constant PRODUCTION_RUNTIME_CODE_LENGTH = 7_454;
    bytes32 public constant PRODUCTION_RUNTIME_CODEHASH =
        0xfbb8dca0ef620c28593dafd8ead5162f233db640a9ebfdc4d47a7920cc06b2af;

    string internal constant PRODUCTION_ACK = "JPYDF_MAINNET_PRODUCTION_TIMELOCK_12_HOURS";

    error DeployMainnetProductionTimelock__WrongChain(uint256 chainId);
    error DeployMainnetProductionTimelock__InvalidAcknowledgement();
    error DeployMainnetProductionTimelock__CodelessAdminSafe();
    error DeployMainnetProductionTimelock__ZeroDeployer();
    error DeployMainnetProductionTimelock__NonCanonicalBuild();
    error DeployMainnetProductionTimelock__RoleMismatch();

    function run() external returns (TimelockController timelock) {
        if (block.chainid != 1) revert DeployMainnetProductionTimelock__WrongChain(block.chainid);
        _requireAcknowledgement(vm.envString("DF_MAINNET_PRODUCTION_TIMELOCK_ACK"));
        _requireCanonicalBuild();
        if (ADMIN_SAFE.code.length == 0) revert DeployMainnetProductionTimelock__CodelessAdminSafe();

        bytes memory rawDeployer = vm.envBytes("DEPLOYER");
        ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", rawDeployer);
        address deployer = vm.envAddress("DEPLOYER");
        if (deployer == address(0)) revert DeployMainnetProductionTimelock__ZeroDeployer();

        address[] memory proposers = new address[](1);
        proposers[0] = ADMIN_SAFE;
        address[] memory executors = new address[](1);
        executors[0] = ADMIN_SAFE;

        vm.startBroadcast(deployer);
        timelock = new TimelockController(PRODUCTION_MIN_DELAY, proposers, executors, address(0));
        vm.stopBroadcast();

        _verify(timelock, deployer);

        console2.log("Mainnet production Timelock", address(timelock));
        console2.log("Production minDelay", timelock.getMinDelay());
        console2.logBytes32(address(timelock).codehash);
    }

    function _requireAcknowledgement(string memory acknowledgement) internal pure {
        if (keccak256(bytes(acknowledgement)) != keccak256(bytes(PRODUCTION_ACK))) {
            revert DeployMainnetProductionTimelock__InvalidAcknowledgement();
        }
    }

    function _requireCanonicalBuild() internal pure {
        bytes memory creationCode = type(TimelockController).creationCode;
        bytes memory runtimeCode = type(TimelockController).runtimeCode;
        if (
            creationCode.length != PRODUCTION_CREATION_CODE_LENGTH
                || keccak256(creationCode) != PRODUCTION_CREATION_CODEHASH
                || runtimeCode.length != PRODUCTION_RUNTIME_CODE_LENGTH
                || keccak256(runtimeCode) != PRODUCTION_RUNTIME_CODEHASH
        ) revert DeployMainnetProductionTimelock__NonCanonicalBuild();
    }

    function _verify(TimelockController timelock, address deployer) internal view {
        if (
            address(timelock).code.length != PRODUCTION_RUNTIME_CODE_LENGTH
                || address(timelock).codehash != PRODUCTION_RUNTIME_CODEHASH
        ) {
            revert DeployMainnetProductionTimelock__RoleMismatch();
        }
        if (timelock.getMinDelay() != PRODUCTION_MIN_DELAY) revert DeployMainnetProductionTimelock__RoleMismatch();
        if (!timelock.hasRole(timelock.PROPOSER_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetProductionTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.EXECUTOR_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetProductionTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.CANCELLER_ROLE(), ADMIN_SAFE)) {
            revert DeployMainnetProductionTimelock__RoleMismatch();
        }
        if (!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock))) {
            revert DeployMainnetProductionTimelock__RoleMismatch();
        }
        if (
            timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), ADMIN_SAFE)
                || timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), deployer)
                || timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0))
        ) revert DeployMainnetProductionTimelock__RoleMismatch();
    }
}
