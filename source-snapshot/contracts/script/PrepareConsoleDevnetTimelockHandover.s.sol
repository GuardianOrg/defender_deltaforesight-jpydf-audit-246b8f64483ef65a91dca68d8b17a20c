// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {CollateralVault} from "src/CollateralVault.sol";

import {ConsoleDevnetChainGuard} from "script/ConsoleDevnetChainGuard.sol";

interface IConsoleDevnetPendingOwnable {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IConsoleDevnetStrategyList {
    function getStrategiesCount() external view returns (uint256);
    function strategies(uint256 index) external view returns (address);
}

interface IConsoleDevnetStrategyGovernance {
    function upgrader() external view returns (address);
    function setUpgrader(address newUpgrader) external;
}

/// @dev Prepares only the Timelock-held governance boundary for a non-mainnet
///      Admin Console environment. Unlike PrepareDFGovernanceHandover, this script
///      does not change caps, Vault operating parameters, treasury, PriceFeed owner,
///      Strategy owner, Guardian, Allocator, or Writeoff holders.
///
///      It preflights every target before broadcasting any transaction, then:
///      - starts DToken and InterestRouterForwarder ownership transfers to Timelock;
///      - moves active Vault DEFAULT_ADMIN_ROLE / GOV_ROLE to Timelock; and
///      - moves every active Strategy upgrader to Timelock.
///
///      Usage:
///      DEVNET_EXPECTED_CHAIN_ID=31338 DEVNET_EXPECTED_MANIFEST_HASH=0x... \
///      DEVNET_OPERATOR_PRIVATE_KEY=0x... \
///      DF_CURRENT_ADMIN=0x... DF_TIMELOCK=0x... forge script \
///        script/PrepareConsoleDevnetTimelockHandover.s.sol:PrepareConsoleDevnetTimelockHandover \
///        --rpc-url https://... --broadcast
contract PrepareConsoleDevnetTimelockHandover is Script {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");

    struct Config {
        address timelock;
        address currentAdmin;
        uint256 operatorPrivateKey;
        uint256 totalBranches;
        uint256 activeBranches;
    }

    function run() external {
        ConsoleDevnetChainGuard.requireExpected(block.chainid, vm.envUint("DEVNET_EXPECTED_CHAIN_ID"));

        string memory manifest = vm.readFile(vm.envOr("DF_HANDOVER_MANIFEST", string("deployment-manifest.json")));
        ConsoleDevnetChainGuard.requireExpectedManifestHash(manifest, vm.envBytes32("DEVNET_EXPECTED_MANIFEST_HASH"));
        Config memory cfg = _loadConfig();
        _verifyTimelockConfiguration(cfg);
        _preflight(manifest, cfg);

        vm.startBroadcast(cfg.operatorPrivateKey);
        _startOwnershipTransfer(_branch(manifest, 0, "interestRouter"), cfg, "interest router");
        for (uint256 branchIndex; branchIndex < cfg.totalBranches; ++branchIndex) {
            _startOwnershipTransfer(_dfYield(manifest, branchIndex, "dToken"), cfg, "dToken");
            if (branchIndex >= cfg.activeBranches) continue;

            CollateralVault vault = CollateralVault(_dfYield(manifest, branchIndex, "collateralVault"));
            _prepareVault(vault, cfg);
            _prepareStrategies(vault, cfg);
        }
        vm.stopBroadcast();

        _verifyPreparedState(manifest, cfg);
        console2.log("Console devnet Timelock handover prepared", cfg.timelock);
    }

    function _preflight(string memory manifest, Config memory cfg) internal view {
        address interestRouter = _branch(manifest, 0, "interestRouter");
        _requireOwnershipReady(interestRouter, cfg, "interest router");

        for (uint256 branchIndex; branchIndex < cfg.totalBranches; ++branchIndex) {
            require(
                _branch(manifest, branchIndex, "interestRouter") == interestRouter,
                "Console devnet prepare: mixed interest router"
            );
            _requireOwnershipReady(_dfYield(manifest, branchIndex, "dToken"), cfg, "dToken");
            if (branchIndex >= cfg.activeBranches) continue;

            address vaultAddress = _dfYield(manifest, branchIndex, "collateralVault");
            require(vaultAddress != address(0) && vaultAddress.code.length != 0, "Console devnet prepare: vault");
            CollateralVault vault = CollateralVault(vaultAddress);
            bool timelockAdmin = vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
            bool timelockGov = vault.hasRole(GOV_ROLE, cfg.timelock);
            bool oldAdmin = vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin);
            bool oldGov = vault.hasRole(GOV_ROLE, cfg.currentAdmin);
            if (!timelockAdmin || !timelockGov || oldAdmin || oldGov) {
                require(
                    vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin), "Console devnet prepare: current vault admin"
                );
            }

            IConsoleDevnetStrategyList strategyList = IConsoleDevnetStrategyList(vaultAddress);
            for (uint256 strategyIndex; strategyIndex < strategyList.getStrategiesCount(); ++strategyIndex) {
                address strategy = strategyList.strategies(strategyIndex);
                require(strategy != address(0) && strategy.code.length != 0, "Console devnet prepare: strategy");
                address upgrader = IConsoleDevnetStrategyGovernance(strategy).upgrader();
                require(
                    upgrader == cfg.currentAdmin || upgrader == cfg.timelock,
                    "Console devnet prepare: unexpected strategy upgrader"
                );
            }
        }
    }

    function _startOwnershipTransfer(address target, Config memory cfg, string memory label) internal {
        IConsoleDevnetPendingOwnable ownable = IConsoleDevnetPendingOwnable(target);
        if (ownable.owner() == cfg.timelock || ownable.pendingOwner() == cfg.timelock) return;

        ownable.transferOwnership(cfg.timelock);
        console2.log("Console devnet ownership transfer started", label, target, cfg.timelock);
    }

    function _prepareVault(CollateralVault vault, Config memory cfg) internal {
        if (!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.timelock)) {
            vault.grantRole(DEFAULT_ADMIN_ROLE, cfg.timelock);
        }
        if (!vault.hasRole(GOV_ROLE, cfg.timelock)) {
            vault.grantRole(GOV_ROLE, cfg.timelock);
        }
        if (vault.hasRole(GOV_ROLE, cfg.currentAdmin)) {
            vault.revokeRole(GOV_ROLE, cfg.currentAdmin);
        }
        if (vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin)) {
            vault.revokeRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin);
        }
    }

    function _prepareStrategies(CollateralVault vault, Config memory cfg) internal {
        IConsoleDevnetStrategyList strategyList = IConsoleDevnetStrategyList(address(vault));
        for (uint256 strategyIndex; strategyIndex < strategyList.getStrategiesCount(); ++strategyIndex) {
            IConsoleDevnetStrategyGovernance strategy =
                IConsoleDevnetStrategyGovernance(strategyList.strategies(strategyIndex));
            if (strategy.upgrader() != cfg.timelock) {
                strategy.setUpgrader(cfg.timelock);
            }
        }
    }

    function _verifyPreparedState(string memory manifest, Config memory cfg) internal view {
        address interestRouter = _branch(manifest, 0, "interestRouter");
        _requirePreparedOwnership(interestRouter, cfg, "interest router");

        for (uint256 branchIndex; branchIndex < cfg.totalBranches; ++branchIndex) {
            require(
                _branch(manifest, branchIndex, "interestRouter") == interestRouter,
                "Console devnet prepare: mixed interest router"
            );
            _requirePreparedOwnership(_dfYield(manifest, branchIndex, "dToken"), cfg, "dToken");
            if (branchIndex >= cfg.activeBranches) continue;

            CollateralVault vault = CollateralVault(_dfYield(manifest, branchIndex, "collateralVault"));
            require(vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.timelock), "Console devnet prepare: vault admin");
            require(vault.hasRole(GOV_ROLE, cfg.timelock), "Console devnet prepare: vault gov");
            require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin), "Console devnet prepare: old vault admin");
            require(!vault.hasRole(GOV_ROLE, cfg.currentAdmin), "Console devnet prepare: old vault gov");

            IConsoleDevnetStrategyList strategyList = IConsoleDevnetStrategyList(address(vault));
            for (uint256 strategyIndex; strategyIndex < strategyList.getStrategiesCount(); ++strategyIndex) {
                require(
                    IConsoleDevnetStrategyGovernance(strategyList.strategies(strategyIndex)).upgrader() == cfg.timelock,
                    "Console devnet prepare: strategy upgrader"
                );
            }
        }
    }

    function _requireOwnershipReady(address target, Config memory cfg, string memory label) internal view {
        require(target != address(0) && target.code.length != 0, string.concat("Console devnet prepare: ", label));
        IConsoleDevnetPendingOwnable ownable = IConsoleDevnetPendingOwnable(target);
        address owner = ownable.owner();
        address pendingOwner = ownable.pendingOwner();
        require(
            owner == cfg.currentAdmin || owner == cfg.timelock,
            string.concat("Console devnet prepare: unexpected ", label, " owner")
        );
        if (owner == cfg.timelock) {
            require(pendingOwner == address(0), string.concat("Console devnet prepare: pending ", label));
        } else {
            require(
                pendingOwner == address(0) || pendingOwner == cfg.timelock,
                string.concat("Console devnet prepare: unexpected pending ", label)
            );
        }
    }

    function _requirePreparedOwnership(address target, Config memory cfg, string memory label) internal view {
        IConsoleDevnetPendingOwnable ownable = IConsoleDevnetPendingOwnable(target);
        bool completed = ownable.owner() == cfg.timelock && ownable.pendingOwner() == address(0);
        bool pending = ownable.owner() == cfg.currentAdmin && ownable.pendingOwner() == cfg.timelock;
        require(completed || pending, string.concat("Console devnet prepare: unprepared ", label));
    }

    function _verifyTimelockConfiguration(Config memory cfg) internal view {
        require(
            cfg.timelock.codehash == keccak256(type(TimelockController).runtimeCode),
            "Console devnet prepare: Timelock implementation"
        );

        TimelockController timelock = TimelockController(payable(cfg.timelock));
        require(timelock.getMinDelay() == 0, "Console devnet prepare: bootstrap delay");
        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), cfg.currentAdmin), "Console devnet prepare: Timelock proposer"
        );
        require(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), cfg.currentAdmin), "Console devnet prepare: Timelock executor"
        );
        require(
            timelock.hasRole(timelock.CANCELLER_ROLE(), cfg.currentAdmin), "Console devnet prepare: Timelock canceller"
        );
        require(
            timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), cfg.timelock),
            "Console devnet prepare: Timelock self admin"
        );
        require(
            !timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "Console devnet prepare: Timelock open executor"
        );
        require(
            !timelock.hasRole(timelock.TIMELOCK_ADMIN_ROLE(), cfg.currentAdmin),
            "Console devnet prepare: Timelock operator admin"
        );
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        cfg.timelock = vm.envAddress("DF_TIMELOCK");
        cfg.currentAdmin = vm.envAddress("DF_CURRENT_ADMIN");
        cfg.operatorPrivateKey = vm.envUint("DEVNET_OPERATOR_PRIVATE_KEY");
        cfg.totalBranches = vm.envOr("DF_HANDOVER_TOTAL_BRANCHES", uint256(8));
        cfg.activeBranches = vm.envOr("DF_HANDOVER_ACTIVE_BRANCHES", uint256(2));

        require(cfg.timelock != address(0) && cfg.timelock.code.length != 0, "Console devnet prepare: timelock");
        require(cfg.currentAdmin != address(0), "Console devnet prepare: current admin");
        require(cfg.currentAdmin != cfg.timelock, "Console devnet prepare: current admin=timelock");
        require(vm.addr(cfg.operatorPrivateKey) == cfg.currentAdmin, "Console devnet prepare: broadcaster != admin");
        require(cfg.totalBranches > 0, "Console devnet prepare: zero branches");
        require(cfg.activeBranches <= cfg.totalBranches, "Console devnet prepare: branch count");
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
