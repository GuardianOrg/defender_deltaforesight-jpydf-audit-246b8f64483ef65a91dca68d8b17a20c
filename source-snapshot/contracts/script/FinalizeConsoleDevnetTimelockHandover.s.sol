// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {CollateralVault} from "src/CollateralVault.sol";

import {ConsoleDevnetChainGuard} from "script/ConsoleDevnetChainGuard.sol";

interface IConsoleDevnetTwoStepOwnable {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function acceptOwnership() external;
}

interface IConsoleDevnetVaultStrategies {
    function getStrategiesCount() external view returns (uint256);
    function strategies(uint256 index) external view returns (address);
}

interface IConsoleDevnetStrategyUpgrader {
    function upgrader() external view returns (address);
}

/// @dev Completes only the Timelock-held portion of the DF governance handover
///      on a non-mainnet E2E deployment. PrepareConsoleDevnetTimelockHandover or
///      the full PrepareDFGovernanceHandover must run first.
///      DToken and InterestRouterForwarder ownership are accepted by scheduling and
///      executing acceptOwnership() through the actual Timelock. The Timelock then
///      schedules and executes its own updateDelay() call.
///
///      PriceFeed and Strategy owner transfers remain pending for their separate
///      role holders; this script verifies the Issue #1176 Timelock boundary only.
///
///      Usage:
///      DEVNET_EXPECTED_CHAIN_ID=31337 DEVNET_EXPECTED_MANIFEST_HASH=0x... \
///      DEVNET_OPERATOR_PRIVATE_KEY=0x... DF_TIMELOCK=0x... \
///      DEVNET_TIMELOCK_MIN_DELAY=30 forge script \
///        script/FinalizeConsoleDevnetTimelockHandover.s.sol:FinalizeConsoleDevnetTimelockHandover \
///        --rpc-url http://127.0.0.1:8545 --broadcast
contract FinalizeConsoleDevnetTimelockHandover is Script {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");

    struct Config {
        TimelockController timelock;
        address operator;
        address currentAdmin;
        uint256 operatorPrivateKey;
        uint256 finalDelay;
        uint256 totalBranches;
        uint256 activeBranches;
    }

    function run() external {
        ConsoleDevnetChainGuard.requireExpected(block.chainid, vm.envUint("DEVNET_EXPECTED_CHAIN_ID"));

        string memory manifest = vm.readFile(vm.envOr("DF_HANDOVER_MANIFEST", string("deployment-manifest.json")));
        ConsoleDevnetChainGuard.requireExpectedManifestHash(manifest, vm.envBytes32("DEVNET_EXPECTED_MANIFEST_HASH"));
        Config memory cfg = _loadConfig();

        require(
            cfg.timelock.getMinDelay() == 0 || cfg.timelock.getMinDelay() == cfg.finalDelay,
            "Console devnet handover: delay"
        );
        _verifyTimelockRoles(cfg);

        vm.startBroadcast(cfg.operatorPrivateKey);
        _acceptThroughTimelock(cfg, _branch(manifest, 0, "interestRouter"), "interest router");
        for (uint256 branchIndex; branchIndex < cfg.totalBranches; ++branchIndex) {
            require(
                _branch(manifest, branchIndex, "interestRouter") == _branch(manifest, 0, "interestRouter"),
                "Console devnet handover: mixed interest router"
            );
            _acceptThroughTimelock(cfg, _dfYield(manifest, branchIndex, "dToken"), "dToken");
        }
        _setFinalDelayThroughTimelock(cfg);
        vm.stopBroadcast();

        _verifyFinalState(manifest, cfg);
        console2.log("Console devnet Timelock handover complete", address(cfg.timelock));
        console2.log("Final minDelay", cfg.timelock.getMinDelay());
    }

    function _acceptThroughTimelock(Config memory cfg, address target, string memory label) internal {
        require(target != address(0) && target.code.length != 0, string.concat("Console devnet handover: ", label));

        IConsoleDevnetTwoStepOwnable ownable = IConsoleDevnetTwoStepOwnable(target);
        if (ownable.owner() == address(cfg.timelock)) {
            require(ownable.pendingOwner() == address(0), string.concat("Console devnet handover: pending ", label));
            return;
        }
        require(
            ownable.pendingOwner() == address(cfg.timelock),
            string.concat("Console devnet handover: unexpected pending ", label)
        );

        bytes memory data = abi.encodeCall(IConsoleDevnetTwoStepOwnable.acceptOwnership, ());
        bytes32 salt = keccak256(abi.encode("console-devnet-accept", block.chainid, target));
        _scheduleOrExecute(cfg.timelock, target, data, salt, label);

        require(ownable.owner() == address(cfg.timelock), string.concat("Console devnet handover: owner ", label));
        require(ownable.pendingOwner() == address(0), string.concat("Console devnet handover: pending ", label));
        console2.log("Timelock accepted ownership", label, target);
    }

    function _setFinalDelayThroughTimelock(Config memory cfg) internal {
        if (cfg.timelock.getMinDelay() == cfg.finalDelay) return;

        bytes memory data = abi.encodeCall(TimelockController.updateDelay, (cfg.finalDelay));
        bytes32 salt =
            keccak256(abi.encode("console-devnet-delay", block.chainid, address(cfg.timelock), cfg.finalDelay));
        _scheduleOrExecute(cfg.timelock, address(cfg.timelock), data, salt, "delay");
        require(cfg.timelock.getMinDelay() == cfg.finalDelay, "Console devnet handover: final delay");
    }

    function _scheduleOrExecute(
        TimelockController timelock,
        address target,
        bytes memory data,
        bytes32 salt,
        string memory label
    ) internal {
        bytes32 operationId = timelock.hashOperation(target, 0, data, bytes32(0), salt);
        if (!timelock.isOperation(operationId)) {
            timelock.schedule(target, 0, data, bytes32(0), salt, 0);
        }

        if (timelock.isOperationReady(operationId)) {
            timelock.execute(target, 0, data, bytes32(0), salt);
            return;
        }

        require(timelock.isOperationDone(operationId), string.concat("Console devnet handover: operation ", label));
    }

    function _verifyFinalState(string memory manifest, Config memory cfg) internal view {
        _verifyTimelockRoles(cfg);
        require(cfg.timelock.getMinDelay() == cfg.finalDelay, "Console devnet handover: final delay");

        _requireOwnedByTimelock(_branch(manifest, 0, "interestRouter"), cfg.timelock, "interest router");
        for (uint256 branchIndex; branchIndex < cfg.totalBranches; ++branchIndex) {
            _requireOwnedByTimelock(_dfYield(manifest, branchIndex, "dToken"), cfg.timelock, "dToken");
            if (branchIndex >= cfg.activeBranches) continue;

            CollateralVault vault = CollateralVault(_dfYield(manifest, branchIndex, "collateralVault"));
            require(vault.hasRole(DEFAULT_ADMIN_ROLE, address(cfg.timelock)), "Console devnet handover: vault admin");
            require(vault.hasRole(GOV_ROLE, address(cfg.timelock)), "Console devnet handover: vault gov");
            require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin), "Console devnet handover: old vault admin");
            require(!vault.hasRole(GOV_ROLE, cfg.currentAdmin), "Console devnet handover: old vault gov");

            IConsoleDevnetVaultStrategies strategyList = IConsoleDevnetVaultStrategies(address(vault));
            for (uint256 strategyIndex; strategyIndex < strategyList.getStrategiesCount(); ++strategyIndex) {
                require(
                    IConsoleDevnetStrategyUpgrader(strategyList.strategies(strategyIndex)).upgrader()
                        == address(cfg.timelock),
                    "Console devnet handover: strategy upgrader"
                );
            }
        }
    }

    function _verifyTimelockRoles(Config memory cfg) internal view {
        require(
            address(cfg.timelock).codehash == keccak256(type(TimelockController).runtimeCode),
            "Console devnet handover: Timelock implementation"
        );
        require(cfg.timelock.hasRole(cfg.timelock.PROPOSER_ROLE(), cfg.operator), "Console devnet handover: proposer");
        require(cfg.timelock.hasRole(cfg.timelock.EXECUTOR_ROLE(), cfg.operator), "Console devnet handover: executor");
        require(cfg.timelock.hasRole(cfg.timelock.CANCELLER_ROLE(), cfg.operator), "Console devnet handover: canceller");
        require(
            cfg.timelock.hasRole(cfg.timelock.TIMELOCK_ADMIN_ROLE(), address(cfg.timelock)),
            "Console devnet handover: self admin"
        );
        require(
            !cfg.timelock.hasRole(cfg.timelock.EXECUTOR_ROLE(), address(0)), "Console devnet handover: open executor"
        );
        require(
            !cfg.timelock.hasRole(cfg.timelock.TIMELOCK_ADMIN_ROLE(), cfg.operator),
            "Console devnet handover: operator admin"
        );
    }

    function _requireOwnedByTimelock(address target, TimelockController timelock, string memory label) internal view {
        IConsoleDevnetTwoStepOwnable ownable = IConsoleDevnetTwoStepOwnable(target);
        require(ownable.owner() == address(timelock), string.concat("Console devnet handover: owner ", label));
        require(ownable.pendingOwner() == address(0), string.concat("Console devnet handover: pending ", label));
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        address timelockAddress = vm.envAddress("DF_TIMELOCK");
        cfg.timelock = TimelockController(payable(timelockAddress));
        cfg.operatorPrivateKey = vm.envUint("DEVNET_OPERATOR_PRIVATE_KEY");
        cfg.operator = vm.addr(cfg.operatorPrivateKey);
        cfg.currentAdmin = vm.envAddress("DF_CURRENT_ADMIN");
        cfg.finalDelay = vm.envUint("DEVNET_TIMELOCK_MIN_DELAY");
        cfg.totalBranches = vm.envOr("DF_HANDOVER_TOTAL_BRANCHES", uint256(8));
        cfg.activeBranches = vm.envOr("DF_HANDOVER_ACTIVE_BRANCHES", uint256(2));

        require(timelockAddress != address(0) && timelockAddress.code.length != 0, "Console devnet handover: timelock");
        require(cfg.operator != address(0), "Console devnet handover: operator");
        require(cfg.currentAdmin != address(0), "Console devnet handover: current admin");
        require(cfg.operator == cfg.currentAdmin, "Console devnet handover: broadcaster != admin");
        require(cfg.currentAdmin != timelockAddress, "Console devnet handover: current admin=timelock");
        require(cfg.finalDelay > 0, "Console devnet handover: zero final delay");
        require(cfg.activeBranches <= cfg.totalBranches, "Console devnet handover: branch count");
    }

    function _dfYield(string memory manifest, uint256 branchIndex, string memory manifestKey)
        internal
        pure
        returns (address)
    {
        return vm.parseJsonAddress(manifest, string.concat(".dfYield[", vm.toString(branchIndex), "].", manifestKey));
    }

    function _branch(string memory manifest, uint256 branchIndex, string memory manifestKey)
        internal
        pure
        returns (address)
    {
        return vm.parseJsonAddress(manifest, string.concat(".branches[", vm.toString(branchIndex), "].", manifestKey));
    }
}
