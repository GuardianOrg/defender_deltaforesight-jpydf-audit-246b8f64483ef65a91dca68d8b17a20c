// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {ConsoleDevnetChainGuard} from "script/ConsoleDevnetChainGuard.sol";

/// @dev Deploys a real TimelockController for non-mainnet Admin Console E2E drills.
///      The operator receives proposer / executor / canceller roles. No external
///      account receives TIMELOCK_ADMIN_ROLE; the Timelock remains its own admin.
///      A zero bootstrap delay lets FinalizeConsoleDevnetTimelockHandover accept
///      pending ownership before raising the delay to DEVNET_TIMELOCK_MIN_DELAY.
///
///      Usage:
///      DEVNET_EXPECTED_CHAIN_ID=31337 DEVNET_OPERATOR_PRIVATE_KEY=0x... forge script \
///        script/DeployConsoleDevnetTimelock.s.sol:DeployConsoleDevnetTimelock \
///        --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployConsoleDevnetTimelock is Script {
    function run() external returns (TimelockController timelock) {
        ConsoleDevnetChainGuard.requireExpected(block.chainid, vm.envUint("DEVNET_EXPECTED_CHAIN_ID"));

        uint256 operatorPrivateKey = vm.envUint("DEVNET_OPERATOR_PRIVATE_KEY");
        address operator = vm.addr(operatorPrivateKey);
        require(operator != address(0), "Console devnet Timelock: zero operator");

        address[] memory proposers = new address[](1);
        proposers[0] = operator;
        address[] memory executors = new address[](1);
        executors[0] = operator;

        vm.startBroadcast(operatorPrivateKey);
        timelock = new TimelockController(0, proposers, executors, address(0));
        vm.stopBroadcast();

        require(timelock.hasRole(timelock.PROPOSER_ROLE(), operator), "Console devnet Timelock: proposer");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), operator), "Console devnet Timelock: executor");
        require(timelock.hasRole(timelock.CANCELLER_ROLE(), operator), "Console devnet Timelock: canceller");
        require(
            timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock)), "Console devnet Timelock: self admin"
        );
        require(!timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), operator), "Console devnet Timelock: operator admin");
        require(!timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Console devnet Timelock: open executor");

        console2.log("Console devnet Timelock", address(timelock));
        console2.log("Preflight block (use CREATE receipt block for fromBlock)", block.number);
        console2.log("Bootstrap minDelay", timelock.getMinDelay());
        console2.log("Operator", operator);
    }
}
