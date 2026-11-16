// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console2} from "forge-std/Script.sol";
import {Day1TokenEnvelope} from "script/Day1TokenEnvelope.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";
import {MainnetProductionTimelockPolicy} from "script/MainnetProductionTimelockPolicy.sol";

import {CollateralVault} from "src/CollateralVault.sol";
import {DToken} from "src/DToken.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";

interface IStrategyGovernance {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function upgrader() external view returns (address);
    function setUpgrader(address newUpgrader) external;
}

interface ITwoStepOwnableGovernance {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IPrepareInterestRouterForwarderView {
    function jpydfToken() external view returns (address);
    function recipient() external view returns (address);
}

interface IHandoverVaultStrategiesView {
    function getStrategiesCount() external view returns (uint256);
    function strategies(uint256 index) external view returns (address);
    function strategyConfigs(address strategy) external view returns (bool enabled, uint256 weightBps, uint256 cap);
    function totalWeightBps() external view returns (uint256);
}

/// @dev One-shot governance preparation helper for the DF yield layer deployed by DeployLiquity2.
///      It performs the actions that the current deploy/admin key can safely do before
///      control is fully handed to the production governance holders:
///      - DToken: start 2-step ownership transfer to the configured owner (Timelock by default)
///      - Vault: set treasury, grant target roles, revoke current admin roles
///      - Strategy: set upgrader to Timelock and start owner transfer to Guardian
///      - InterestRouterForwarder: start 2-step ownership transfer to the common Timelock
///      - PriceFeedProxy: start 2-step ownership transfer to the GOV multisig
///      - Day-1 branch parameters: validate the frozen dToken cap input and set Vault allocator/buffer/delay knobs
///
///      Active dToken caps remain zero. Cap activation belongs to the separately
///      simulated controlled-initialization bundle that also opens the company
///      bootstrap Troves and reaches each branch's Stability Pool target.
///
///      Usage:
///      DEPLOYER=<current deploy/admin address> \
///      DF_TIMELOCK=0x... DF_TREASURY=0x... DF_INTEREST_ROUTER_RECIPIENT=0x... DF_GUARDIAN=0x... \
///      DF_ALLOCATOR=0x... DF_WRITEOFF=0x... DF_PRICE_FEED_OWNER=0x... \
///      DF_STRATEGY_OWNER=0x... DF_STRATEGY_UPGRADER=0x... \
///      DF_PRODUCTION_GOVERNANCE_EVIDENCE=/path/to/mainnet-governance-evidence.json \
///      DF_PRODUCTION_GOVERNANCE_EVIDENCE_SHA256=0x... \
///      DF_DTOKEN_CAP_CONVERSION=/path/to/dtoken-cap-conversion.json \
///      DF_DTOKEN_CAP_0=... DF_ALLOCATE_MAX_MOVE_0=... DF_ALLOCATOR_COOLDOWN_0=... \
///      DF_WITHDRAW_DELAY_0=... DF_BUFFER_TARGET_BPS_0=... DF_BUFFER_FLOOR_0=... \
///      forge script PrepareDFGovernanceHandover --rpc-url ... --broadcast
contract PrepareDFGovernanceHandover is Day1TokenEnvelope {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant WRITEOFF_ROLE = keccak256("WRITEOFF_ROLE");

    struct HandoverConfig {
        address currentAdmin;
        address timelock;
        address dTokenOwner;
        address vaultAdmin;
        address treasury;
        address interestRouterRecipient;
        address guardian;
        address allocator;
        address writeoff;
        address priceFeedOwner;
        address strategyOwner;
        address strategyUpgrader;
        uint256 totalBranches;
        uint256 activeBranches;
        bool allowCurrentAdminAsTarget;
    }

    function run() external {
        string memory manifest = vm.readFile(vm.envOr("DF_HANDOVER_MANIFEST", string("deployment-manifest.json")));
        if (block.chainid == 1) {
            ScriptSecurityPolicy.requireProductionManifestForMainnet(
                block.chainid, vm.parseJsonString(manifest, ".deploymentClassification")
            );
        }
        HandoverConfig memory cfg = _loadConfig();
        _requireMainnetProductionGovernance(manifest, cfg);
        _requireMainnetProductionGovernanceEvidence(cfg.timelock);
        address interestRouter = _verifiedSharedInterestRouter(manifest, cfg.totalBranches);
        _verifyInterestRouterForwarder(manifest, interestRouter, cfg.interestRouterRecipient);
        for (uint256 i; i < cfg.activeBranches; ++i) {
            _requireActiveBranchCapFrozen(DToken(_dfYield(manifest, i, "dToken")));
        }

        address broadcaster = _startBroadcast();
        require(broadcaster == cfg.currentAdmin, "DF handover: broadcaster != current admin");

        _startTwoStepHandover(interestRouter, cfg.timelock, cfg, "interest router");

        for (uint256 i; i < cfg.totalBranches; ++i) {
            DToken dToken = DToken(_dfYield(manifest, i, "dToken"));
            _startTwoStepHandover(_branch(manifest, i, "priceFeed"), cfg.priceFeedOwner, cfg, "price feed");

            if (i < cfg.activeBranches) {
                CollateralVault vault = CollateralVault(_dfYield(manifest, i, "collateralVault"));

                _applyActiveBranchVaultParameters(i, dToken, vault);
                _requireActiveBranchCapFrozen(dToken);
                _prepareVault(vault, cfg);
                _prepareBranchStrategies(manifest, i, vault, cfg);
            } else {
                CollateralVault vault = CollateralVault(_dfYield(manifest, i, "collateralVault"));

                _ensureInertBranchCap(dToken, cfg);
                // Placeholder branches are frozen, but their Vault implementations
                // remain privileged contracts. Normalize the Vault so the deployer
                // retains no authority if the placeholder is activated later.
                _prepareVault(vault, cfg);
            }

            _startDTokenHandover(dToken, cfg);
        }
        vm.stopBroadcast();
    }

    function _startDTokenHandover(DToken dToken, HandoverConfig memory cfg) internal {
        if (dToken.owner() == cfg.dTokenOwner) return;
        if (dToken.pendingOwner() == cfg.dTokenOwner) return;
        require(dToken.owner() == cfg.currentAdmin, "DF handover: unexpected dToken owner");

        dToken.transferOwnership(cfg.dTokenOwner);
        console2.log("DToken ownership transfer started", address(dToken), cfg.dTokenOwner);
    }

    function _verifiedSharedInterestRouter(string memory manifest, uint256 totalBranches)
        internal
        pure
        returns (address interestRouter)
    {
        interestRouter = _branch(manifest, 0, "interestRouter");
        for (uint256 i = 1; i < totalBranches; ++i) {
            require(_branch(manifest, i, "interestRouter") == interestRouter, "DF handover: mixed interest router");
        }
    }

    function _verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        internal
        view
    {
        require(interestRouter != address(0), "DF handover: zero interest router");
        require(interestRouter.code.length != 0, "DF handover: codeless interest router");

        IPrepareInterestRouterForwarderView forwarder = IPrepareInterestRouterForwarderView(interestRouter);
        address token = _root(manifest, "jpydfToken");
        try forwarder.jpydfToken() returns (address actualToken) {
            require(actualToken == token, "DF handover: interest router token");
        } catch {
            revert("DF handover: not interest router forwarder");
        }

        try forwarder.recipient() returns (address recipient) {
            require(recipient == expectedRecipient, "DF handover: interest router recipient");
            IJpydfToken(token).requireValidRecipient(recipient);
        } catch {
            revert("DF handover: not interest router forwarder");
        }
    }

    function _startTwoStepHandover(address target, address newOwner, HandoverConfig memory cfg, string memory label)
        internal
    {
        require(target != address(0), string.concat("DF handover: zero ", label));
        require(target.code.length != 0, string.concat("DF handover: codeless ", label));

        ITwoStepOwnableGovernance ownable = ITwoStepOwnableGovernance(target);
        address currentOwner;
        address pendingOwner;

        try ownable.owner() returns (address value) {
            currentOwner = value;
        } catch {
            revert(string.concat("DF handover: not ownable ", label));
        }

        try ownable.pendingOwner() returns (address value) {
            pendingOwner = value;
        } catch {
            revert(string.concat("DF handover: not 2-step ownable ", label));
        }

        if (currentOwner == newOwner) return;
        if (pendingOwner == newOwner) return;

        require(currentOwner == cfg.currentAdmin, string.concat("DF handover: unexpected ", label, " owner"));
        ownable.transferOwnership(newOwner);
        console2.log("Ownership transfer started", label, target, newOwner);
    }

    function _prepareVault(CollateralVault vault, HandoverConfig memory cfg) internal {
        if (vault.treasury() != cfg.treasury) {
            vault.setTreasury(cfg.treasury);
            console2.log("Vault treasury updated", address(vault), cfg.treasury);
        }

        _grantIfMissing(vault, DEFAULT_ADMIN_ROLE, cfg.vaultAdmin);
        _grantIfMissing(vault, GOV_ROLE, cfg.vaultAdmin);
        _grantIfMissing(vault, ALLOCATOR_ROLE, cfg.allocator);
        _grantIfMissing(vault, GUARDIAN_ROLE, cfg.guardian);
        _grantIfMissing(vault, WRITEOFF_ROLE, cfg.writeoff);

        _revokeIfHeld(vault, GOV_ROLE, cfg.currentAdmin, cfg.vaultAdmin);
        _revokeIfHeld(vault, ALLOCATOR_ROLE, cfg.currentAdmin, cfg.allocator);
        _revokeIfHeld(vault, GUARDIAN_ROLE, cfg.currentAdmin, cfg.guardian);
        _revokeIfHeld(vault, WRITEOFF_ROLE, cfg.currentAdmin, cfg.writeoff);
        _revokeIfHeld(vault, DEFAULT_ADMIN_ROLE, cfg.currentAdmin, cfg.vaultAdmin);
    }

    function _prepareStrategy(IStrategyGovernance strategy, HandoverConfig memory cfg) internal {
        if (strategy.upgrader() != cfg.strategyUpgrader) {
            require(strategy.upgrader() == cfg.currentAdmin, "DF handover: unexpected strategy upgrader");
            strategy.setUpgrader(cfg.strategyUpgrader);
            console2.log("Strategy upgrader updated", address(strategy), cfg.strategyUpgrader);
        }

        if (strategy.owner() == cfg.strategyOwner) return;
        if (strategy.pendingOwner() == cfg.strategyOwner) return;
        require(strategy.owner() == cfg.currentAdmin, "DF handover: unexpected strategy owner");

        strategy.transferOwnership(cfg.strategyOwner);
        console2.log("Strategy ownership transfer started", address(strategy), cfg.strategyOwner);
    }

    function _prepareBranchStrategies(
        string memory manifest,
        uint256 branchIndex,
        CollateralVault vault,
        HandoverConfig memory cfg
    ) internal {
        IHandoverVaultStrategiesView strategyList = IHandoverVaultStrategiesView(address(vault));
        uint256 strategyCount = strategyList.getStrategiesCount();
        _requireManifestStrategyCount(manifest, branchIndex, strategyCount);

        if (strategyCount == 0) {
            return;
        }

        uint256 manifestTotalWeightBps;
        for (uint256 strategyIndex; strategyIndex < strategyCount; ++strategyIndex) {
            address strategy = strategyList.strategies(strategyIndex);
            require(strategy != address(0), "DF handover: zero strategy");
            require(
                strategy == _dfYieldStrategy(manifest, branchIndex, strategyIndex), "DF handover: strategy mismatch"
            );
            (bool enabled, uint256 weightBps, uint256 cap) = strategyList.strategyConfigs(strategy);
            uint256 manifestWeightBps = _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyWeightBps");
            require(enabled, "DF handover: strategy disabled");
            require(weightBps == manifestWeightBps, "DF handover: strategy weight mismatch");
            require(
                cap == _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyCap"),
                "DF handover: strategy cap mismatch"
            );
            manifestTotalWeightBps += manifestWeightBps;
            _prepareStrategy(IStrategyGovernance(strategy), cfg);
        }
        require(strategyList.totalWeightBps() == manifestTotalWeightBps, "DF handover: total strategy weight mismatch");
    }

    function _applyActiveBranchVaultParameters(uint256 branchIndex, DToken dToken, CollateralVault vault) internal {
        uint256 cap = _dfBranchUint("DF_DTOKEN_CAP", branchIndex);
        uint256 allocateMaxMove = _dfBranchUint("DF_ALLOCATE_MAX_MOVE", branchIndex);
        address underlying = address(dToken.underlying());
        if (block.chainid == MAINNET_CHAIN_ID) {
            require(dToken.vault() == address(vault), "DF handover: dToken vault");
            require(address(vault.dToken()) == address(dToken), "DF handover: vault dToken");
            require(address(vault.underlying()) == underlying, "DF handover: vault underlying");
        }
        _requireMainnetDay1Envelope(
            branchIndex, address(dToken), underlying, dToken.underlyingDecimals(), cap, allocateMaxMove
        );

        uint256 bufferTargetBps = _dfBranchUint("DF_BUFFER_TARGET_BPS", branchIndex);
        uint256 bufferFloor = _dfBranchUint("DF_BUFFER_FLOOR", branchIndex);
        if (vault.bufferTargetBps() != bufferTargetBps || vault.bufferFloor() != bufferFloor) {
            vault.setBufferConfig(bufferTargetBps, bufferFloor);
            console2.log("Vault buffer config updated", address(vault), bufferTargetBps, bufferFloor);
        }

        uint256 withdrawDelay = _dfBranchUint("DF_WITHDRAW_DELAY", branchIndex);
        if (vault.withdrawDelay() != withdrawDelay) {
            vault.setWithdrawDelay(withdrawDelay);
            console2.log("Vault withdraw delay updated", address(vault), withdrawDelay);
        }

        uint256 allocatorCooldown = _dfBranchUint("DF_ALLOCATOR_COOLDOWN", branchIndex);
        if (vault.allocateMaxMove() != allocateMaxMove || vault.allocatorCooldown() != allocatorCooldown) {
            vault.setAllocatorConfig(allocateMaxMove, allocatorCooldown);
            console2.log("Vault allocator config updated", address(vault), allocateMaxMove, allocatorCooldown);
        }
    }

    function _requireActiveBranchCapFrozen(DToken dToken) internal view {
        require(dToken.cap() == 0, "DF handover: active cap must remain zero");
    }

    function _ensureInertBranchCap(DToken dToken, HandoverConfig memory cfg) internal {
        if (dToken.cap() == 0) return;
        require(dToken.owner() == cfg.currentAdmin, "DF handover: inert cap needs current owner");
        dToken.setCap(0);
        console2.log("Inert DToken cap frozen", address(dToken));
    }

    function _grantIfMissing(CollateralVault vault, bytes32 role, address account) internal {
        if (!vault.hasRole(role, account)) {
            vault.grantRole(role, account);
        }
    }

    function _revokeIfHeld(CollateralVault vault, bytes32 role, address account, address targetHolder) internal {
        if (account != address(0) && account != targetHolder && vault.hasRole(role, account)) {
            vault.revokeRole(role, account);
        }
    }

    function _loadConfig() internal view returns (HandoverConfig memory cfg) {
        cfg.currentAdmin = _currentAdmin();
        cfg.timelock = vm.envAddress("DF_TIMELOCK");
        cfg.dTokenOwner = _optionalAddress("DF_DTOKEN_OWNER", cfg.timelock);
        cfg.vaultAdmin = _optionalAddress("DF_VAULT_ADMIN", cfg.timelock);
        cfg.treasury = vm.envAddress("DF_TREASURY");
        cfg.interestRouterRecipient = vm.envAddress("DF_INTEREST_ROUTER_RECIPIENT");
        cfg.guardian = vm.envAddress("DF_GUARDIAN");
        cfg.allocator = vm.envAddress("DF_ALLOCATOR");
        cfg.writeoff = vm.envAddress("DF_WRITEOFF");
        cfg.priceFeedOwner = vm.envAddress("DF_PRICE_FEED_OWNER");
        cfg.strategyOwner = vm.envAddress("DF_STRATEGY_OWNER");
        cfg.strategyUpgrader = vm.envAddress("DF_STRATEGY_UPGRADER");
        cfg.totalBranches = vm.envOr("DF_HANDOVER_TOTAL_BRANCHES", uint256(8));
        cfg.activeBranches = vm.envOr("DF_HANDOVER_ACTIVE_BRANCHES", uint256(2));
        cfg.allowCurrentAdminAsTarget = _envFlag("DF_ALLOW_CURRENT_ADMIN_AS_TARGET");

        _requireNonZero(cfg.currentAdmin, "DF_CURRENT_ADMIN/DEPLOYER");
        _requireNonZero(cfg.timelock, "DF_TIMELOCK");
        _requireNonZero(cfg.dTokenOwner, "DF_DTOKEN_OWNER");
        _requireNonZero(cfg.vaultAdmin, "DF_VAULT_ADMIN");
        _requireNonZero(cfg.treasury, "DF_TREASURY");
        _requireNonZero(cfg.interestRouterRecipient, "DF_INTEREST_ROUTER_RECIPIENT");
        _requireNonZero(cfg.guardian, "DF_GUARDIAN");
        _requireNonZero(cfg.allocator, "DF_ALLOCATOR");
        _requireNonZero(cfg.writeoff, "DF_WRITEOFF");
        _requireNonZero(cfg.priceFeedOwner, "DF_PRICE_FEED_OWNER");
        _requireNonZero(cfg.strategyOwner, "DF_STRATEGY_OWNER");
        _requireNonZero(cfg.strategyUpgrader, "DF_STRATEGY_UPGRADER");

        require(cfg.activeBranches <= cfg.totalBranches, "DF handover: branch count");
        require(cfg.strategyOwner == cfg.guardian, "DF handover: strategy owner must be guardian");
        require(cfg.strategyUpgrader == cfg.timelock, "DF handover: strategy upgrader must be timelock");
        require(cfg.priceFeedOwner != cfg.timelock, "DF handover: priceFeedOwner=timelock");
        require(cfg.priceFeedOwner != cfg.guardian, "DF handover: priceFeedOwner=guardian");
        require(cfg.priceFeedOwner != cfg.allocator, "DF handover: priceFeedOwner=allocator");
        require(cfg.timelock != cfg.guardian, "DF handover: timelock=guardian");
        require(cfg.timelock != cfg.allocator, "DF handover: timelock=allocator");
        require(cfg.timelock != cfg.writeoff, "DF handover: timelock=writeoff");
        require(cfg.guardian != cfg.allocator, "DF handover: guardian=allocator");
        require(cfg.guardian != cfg.writeoff, "DF handover: guardian=writeoff");
        require(cfg.allocator != cfg.writeoff, "DF handover: allocator=writeoff");

        if (!cfg.allowCurrentAdminAsTarget) {
            require(cfg.currentAdmin != cfg.timelock, "DF handover: currentAdmin=timelock");
            require(cfg.currentAdmin != cfg.guardian, "DF handover: currentAdmin=guardian");
            require(cfg.currentAdmin != cfg.allocator, "DF handover: currentAdmin=allocator");
            require(cfg.currentAdmin != cfg.writeoff, "DF handover: currentAdmin=writeoff");
            require(cfg.currentAdmin != cfg.priceFeedOwner, "DF handover: currentAdmin=priceFeedOwner");
            require(cfg.currentAdmin != cfg.dTokenOwner, "DF handover: currentAdmin=dTokenOwner");
            require(cfg.currentAdmin != cfg.vaultAdmin, "DF handover: currentAdmin=vaultAdmin");
        }
    }

    function _requireMainnetProductionGovernance(string memory manifest, HandoverConfig memory cfg) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;
        _requireMainnetDay1BranchTopology(cfg.totalBranches, cfg.activeBranches);
        MainnetProductionTimelockPolicy.requireValid(cfg.timelock);
        MainnetProductionTimelockPolicy.requireRoleHolders(
            cfg.treasury, cfg.interestRouterRecipient, cfg.guardian, cfg.allocator, cfg.writeoff, cfg.priceFeedOwner
        );
        require(cfg.dTokenOwner == cfg.timelock, "DF handover: production dToken owner");
        require(cfg.vaultAdmin == cfg.timelock, "DF handover: production vault admin");
        for (uint256 i; i < cfg.activeBranches; ++i) {
            require(
                _dfYield(manifest, i, "lidoReferralManager") == cfg.timelock,
                "DF handover: production manifest Timelock"
            );
        }
    }

    function _requireMainnetDay1BranchTopology(uint256 totalBranches, uint256 activeBranches) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;
        require(totalBranches == 8, "DF handover: production total branches");
        require(activeBranches == 2, "DF handover: production active branches");
    }

    function _requireMainnetProductionGovernanceEvidence(address timelock) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;
        string memory evidence = vm.readFile(vm.envString("DF_PRODUCTION_GOVERNANCE_EVIDENCE"));
        MainnetProductionTimelockPolicy.requireGovernanceEvidenceBinding(
            bytes(evidence),
            vm.envBytes32("DF_PRODUCTION_GOVERNANCE_EVIDENCE_SHA256"),
            vm.parseJsonAddress(evidence, ".timelock"),
            timelock
        );
    }

    function _optionalAddress(string memory key, address fallbackValue) internal view returns (address) {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }

    function _currentAdmin() internal view returns (address) {
        try vm.envAddress("DF_CURRENT_ADMIN") returns (address value) {
            return value;
        } catch {}

        try vm.envBytes("DEPLOYER") returns (bytes memory raw) {
            ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", raw);
            return vm.envAddress("DEPLOYER");
        } catch {}

        return address(0);
    }

    function _startBroadcast() internal returns (address) {
        bytes memory raw = vm.envBytes("DEPLOYER");
        ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", raw);
        address broadcaster = vm.envAddress("DEPLOYER");
        vm.startBroadcast(broadcaster);
        return broadcaster;
    }

    function _dfYield(string memory manifest, uint256 i, string memory key) internal pure returns (address) {
        return vm.parseJsonAddress(manifest, string.concat(".dfYield[", vm.toString(i), "].", key));
    }

    function _dfYieldStrategy(string memory manifest, uint256 branchIndex, uint256 strategyIndex)
        internal
        pure
        returns (address)
    {
        return vm.parseJsonAddress(manifest, _dfYieldStrategyPath(branchIndex, strategyIndex));
    }

    function _dfYieldStrategyUint(string memory manifest, uint256 branchIndex, uint256 strategyIndex, string memory key)
        internal
        pure
        returns (uint256)
    {
        return vm.parseUint(
            vm.parseJsonString(
                manifest,
                string.concat(
                    ".dfYield[", vm.toString(branchIndex), "].strategies[", vm.toString(strategyIndex), "].", key
                )
            )
        );
    }

    function _requireManifestStrategyCount(string memory manifest, uint256 branchIndex, uint256 expectedCount)
        internal
        view
    {
        for (uint256 i; i < expectedCount; ++i) {
            require(vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, i)), "DF handover: missing strategy");
        }
        require(
            !vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, expectedCount)),
            "DF handover: strategy count mismatch"
        );
    }

    function _dfYieldStrategyPath(uint256 branchIndex, uint256 strategyIndex) internal pure returns (string memory) {
        return
            string.concat(
                ".dfYield[", vm.toString(branchIndex), "].strategies[", vm.toString(strategyIndex), "].strategy"
            );
    }

    function _branch(string memory manifest, uint256 i, string memory key) internal pure returns (address) {
        return vm.parseJsonAddress(manifest, string.concat(".branches[", vm.toString(i), "].", key));
    }

    function _root(string memory manifest, string memory key) internal pure returns (address) {
        return vm.parseJsonAddress(manifest, string.concat(".", key));
    }

    function _dfBranchUint(string memory prefix, uint256 branchIndex) internal view returns (uint256) {
        return vm.envUint(string.concat(prefix, "_", vm.toString(branchIndex)));
    }

    function _envFlag(string memory key) internal view returns (bool) {
        string memory value = vm.envOr(key, string("false"));
        bytes32 hash = keccak256(bytes(value));
        return hash == keccak256(bytes("true")) || hash == keccak256(bytes("1")) || hash == keccak256(bytes("yes"));
    }

    function _requireNonZero(address value, string memory label) internal pure {
        require(value != address(0), string.concat("DF handover: zero ", label));
    }
}
