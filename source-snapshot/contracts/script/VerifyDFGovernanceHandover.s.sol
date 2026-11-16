// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Day1TokenEnvelope} from "script/Day1TokenEnvelope.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";
import {MainnetProductionTimelockPolicy} from "script/MainnetProductionTimelockPolicy.sol";

import {CollateralVault} from "src/CollateralVault.sol";
import {DToken} from "src/DToken.sol";
import {PriceFeedPlaceholder} from "src/PriceFeeds/PriceFeedPlaceholder.sol";
import {PriceFeedProxy} from "src/PriceFeeds/PriceFeedProxy.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";

interface IStrategyGovernanceView {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function upgrader() external view returns (address);
}

interface ITwoStepOwnableView {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
}

interface IVerifyInterestRouterForwarderView {
    function jpydfToken() external view returns (address);
    function recipient() external view returns (address);
}

interface IVerifyHandoverVaultStrategiesView {
    function getStrategiesCount() external view returns (uint256);
    function strategies(uint256 index) external view returns (address);
    function strategyConfigs(address strategy) external view returns (bool enabled, uint256 weightBps, uint256 cap);
    function totalWeightBps() external view returns (uint256);
}

/// @dev Machine-checks the DF governance holder split after the handover ceremony
///      has completed. DToken/Vault ownership defaults to the production Timelock
///      topology and can be overridden explicitly for a non-mainnet test environment.
///
///      Set DF_VERIFY_PENDING_OWNERSHIP=true only for the pre-exposure intermediate
///      state after PrepareDFGovernanceHandover has started 2-step ownership transfers
///      but before the Timelock/Guardian accept them. This mode also requires every
///      active dToken cap to remain zero. Mainnet verification also requires the reviewed
///      production governance evidence path and SHA-256 used by Prepare.
contract VerifyDFGovernanceHandover is Day1TokenEnvelope {
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
        bool allowPendingOwnership;
    }

    function run() external view {
        string memory manifest = vm.readFile(vm.envOr("DF_HANDOVER_MANIFEST", string("deployment-manifest.json")));
        if (block.chainid == 1) {
            ScriptSecurityPolicy.requireProductionManifestForMainnet(
                block.chainid, vm.parseJsonString(manifest, ".deploymentClassification")
            );
        }
        HandoverConfig memory cfg = _loadConfig();
        _requireMainnetProductionGovernance(manifest, cfg);
        _requireMainnetProductionGovernanceEvidence(cfg.timelock);

        address interestRouter = _branch(manifest, 0, "interestRouter");
        _verifyInterestRouterForwarder(manifest, interestRouter, cfg.interestRouterRecipient);
        _verifyTwoStepOwner(interestRouter, cfg.timelock, cfg, "interest router");

        for (uint256 i; i < cfg.totalBranches; ++i) {
            require(_branch(manifest, i, "interestRouter") == interestRouter, "DF verify: mixed interest router");

            DToken dToken = DToken(_dfYield(manifest, i, "dToken"));
            _verifyTwoStepOwner(_branch(manifest, i, "priceFeed"), cfg.priceFeedOwner, cfg, "price feed");

            if (i < cfg.activeBranches) {
                CollateralVault vault = CollateralVault(_dfYield(manifest, i, "collateralVault"));

                _verifyActiveBranchParameters(i, dToken, vault, cfg.allowPendingOwnership);
                _verifyVault(vault, cfg);
                _verifyBranchStrategies(manifest, i, vault, cfg);
            } else {
                CollateralVault vault = CollateralVault(_dfYield(manifest, i, "collateralVault"));

                _verifyInertBranch(manifest, i, dToken);
                _verifyVault(vault, cfg);
            }

            _verifyDToken(dToken, cfg);
        }
    }

    function _verifyInertBranch(string memory manifest, uint256 branchIndex, DToken dToken) internal view {
        CollateralVault vault = CollateralVault(_dfYield(manifest, branchIndex, "collateralVault"));
        PriceFeedProxy feedProxy = PriceFeedProxy(_branch(manifest, branchIndex, "priceFeed"));

        require(dToken.cap() == 0, "DF verify: inert cap");
        require(address(dToken.underlying()) == address(0), "DF verify: inert dToken underlying");
        require(address(vault.underlying()) == address(0), "DF verify: inert vault underlying");
        require(vault.getStrategiesCount() == 0, "DF verify: inert strategy count");
        require(vault.totalWeightBps() == 0, "DF verify: inert strategy weight");
        require(
            feedProxy.source().codehash == keccak256(type(PriceFeedPlaceholder).runtimeCode), "DF verify: inert source"
        );
        require(_dfYield(manifest, branchIndex, "collateralYieldZapper") == address(0), "DF verify: inert zapper");
    }

    function _verifyDToken(DToken dToken, HandoverConfig memory cfg) internal view {
        address pendingOwner = dToken.pendingOwner();
        address currentOwner = dToken.owner();

        if (currentOwner == cfg.dTokenOwner) {
            require(pendingOwner == address(0), "DF verify: dToken pending owner");
            return;
        }

        if (cfg.allowPendingOwnership && pendingOwner == cfg.dTokenOwner) {
            _requireCurrentAdminOwner(currentOwner, cfg, "dToken");
            return;
        }

        require(false, "DF verify: dToken owner");
    }

    function _verifyVault(CollateralVault vault, HandoverConfig memory cfg) internal view {
        require(vault.treasury() == cfg.treasury, "DF verify: vault treasury");

        require(vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.vaultAdmin), "DF verify: vault admin");
        require(vault.hasRole(GOV_ROLE, cfg.vaultAdmin), "DF verify: vault gov");
        require(vault.hasRole(ALLOCATOR_ROLE, cfg.allocator), "DF verify: allocator");
        require(vault.hasRole(GUARDIAN_ROLE, cfg.guardian), "DF verify: guardian");
        require(vault.hasRole(WRITEOFF_ROLE, cfg.writeoff), "DF verify: writeoff");

        require(!vault.hasRole(ALLOCATOR_ROLE, cfg.vaultAdmin), "DF verify: vault admin allocator");
        require(!vault.hasRole(GUARDIAN_ROLE, cfg.vaultAdmin), "DF verify: vault admin guardian");
        require(!vault.hasRole(WRITEOFF_ROLE, cfg.vaultAdmin), "DF verify: vault admin writeoff");

        require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.guardian), "DF verify: guardian admin");
        require(!vault.hasRole(GOV_ROLE, cfg.guardian), "DF verify: guardian gov");
        require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.allocator), "DF verify: allocator admin");
        require(!vault.hasRole(GOV_ROLE, cfg.allocator), "DF verify: allocator gov");
        require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.writeoff), "DF verify: writeoff admin");
        require(!vault.hasRole(GOV_ROLE, cfg.writeoff), "DF verify: writeoff gov");

        if (cfg.currentAdmin != address(0)) {
            require(!vault.hasRole(DEFAULT_ADMIN_ROLE, cfg.currentAdmin), "DF verify: current admin still admin");
            require(!vault.hasRole(GOV_ROLE, cfg.currentAdmin), "DF verify: current admin still gov");
            require(!vault.hasRole(ALLOCATOR_ROLE, cfg.currentAdmin), "DF verify: current admin still allocator");
            require(!vault.hasRole(GUARDIAN_ROLE, cfg.currentAdmin), "DF verify: current admin still guardian");
            require(!vault.hasRole(WRITEOFF_ROLE, cfg.currentAdmin), "DF verify: current admin still writeoff");
        }
    }

    function _verifyStrategy(IStrategyGovernanceView strategy, HandoverConfig memory cfg) internal view {
        require(strategy.upgrader() == cfg.strategyUpgrader, "DF verify: strategy upgrader");

        address pendingOwner = strategy.pendingOwner();
        address currentOwner = strategy.owner();

        if (currentOwner == cfg.strategyOwner) {
            require(pendingOwner == address(0), "DF verify: strategy pending owner");
            return;
        }

        if (cfg.allowPendingOwnership && pendingOwner == cfg.strategyOwner) {
            _requireCurrentAdminOwner(currentOwner, cfg, "strategy");
            return;
        }

        require(false, "DF verify: strategy owner");
    }

    function _verifyBranchStrategies(
        string memory manifest,
        uint256 branchIndex,
        CollateralVault vault,
        HandoverConfig memory cfg
    ) internal view {
        IVerifyHandoverVaultStrategiesView strategyList = IVerifyHandoverVaultStrategiesView(address(vault));
        uint256 strategyCount = strategyList.getStrategiesCount();
        _requireManifestStrategyCount(manifest, branchIndex, strategyCount);

        if (strategyCount == 0) {
            return;
        }

        uint256 manifestTotalWeightBps;
        for (uint256 strategyIndex; strategyIndex < strategyCount; ++strategyIndex) {
            address strategy = strategyList.strategies(strategyIndex);
            require(strategy != address(0), "DF verify: zero strategy");
            require(strategy == _dfYieldStrategy(manifest, branchIndex, strategyIndex), "DF verify: strategy mismatch");
            (bool enabled, uint256 weightBps, uint256 cap) = strategyList.strategyConfigs(strategy);
            uint256 manifestWeightBps = _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyWeightBps");
            require(enabled, "DF verify: strategy disabled");
            require(weightBps == manifestWeightBps, "DF verify: strategy weight mismatch");
            require(
                cap == _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyCap"),
                "DF verify: strategy cap mismatch"
            );
            manifestTotalWeightBps += manifestWeightBps;
            _verifyStrategy(IStrategyGovernanceView(strategy), cfg);
        }
        require(strategyList.totalWeightBps() == manifestTotalWeightBps, "DF verify: total strategy weight mismatch");
    }

    function _verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        internal
        view
    {
        require(interestRouter != address(0), "DF verify: zero interest router");
        require(interestRouter.code.length != 0, "DF verify: codeless interest router");

        IVerifyInterestRouterForwarderView forwarder = IVerifyInterestRouterForwarderView(interestRouter);
        address token = _root(manifest, "jpydfToken");
        try forwarder.jpydfToken() returns (address actualToken) {
            require(actualToken == token, "DF verify: interest router token");
        } catch {
            revert("DF verify: not interest router forwarder");
        }

        try forwarder.recipient() returns (address recipient) {
            require(recipient == expectedRecipient, "DF verify: interest router recipient");
            IJpydfToken(token).requireValidRecipient(recipient);
        } catch {
            revert("DF verify: not interest router forwarder");
        }
    }

    function _verifyTwoStepOwner(address target, address expectedOwner, HandoverConfig memory cfg, string memory label)
        internal
        view
    {
        require(target != address(0), string.concat("DF verify: zero ", label));
        require(target.code.length != 0, string.concat("DF verify: codeless ", label));

        ITwoStepOwnableView ownable = ITwoStepOwnableView(target);
        address currentOwner;

        try ownable.owner() returns (address value) {
            currentOwner = value;
        } catch {
            revert(string.concat("DF verify: not ownable ", label));
        }

        address pendingOwner;
        try ownable.pendingOwner() returns (address value) {
            pendingOwner = value;
        } catch {
            revert(string.concat("DF verify: not 2-step ownable ", label));
        }

        if (currentOwner == expectedOwner) {
            require(pendingOwner == address(0), string.concat("DF verify: ", label, " pending owner"));
            return;
        }

        if (cfg.allowPendingOwnership && pendingOwner == expectedOwner) {
            _requireCurrentAdminOwner(currentOwner, cfg, label);
            return;
        }

        require(false, string.concat("DF verify: ", label, " owner"));
    }

    function _requireCurrentAdminOwner(address currentOwner, HandoverConfig memory cfg, string memory label)
        internal
        pure
    {
        require(cfg.currentAdmin != address(0), "DF verify: current admin");
        require(currentOwner == cfg.currentAdmin, string.concat("DF verify: ", label, " current owner"));
    }

    function _verifyActiveBranchParameters(
        uint256 branchIndex,
        DToken dToken,
        CollateralVault vault,
        bool requireFrozenCap
    ) internal view {
        uint256 expectedCap = _dfBranchUint("DF_DTOKEN_CAP", branchIndex);
        uint256 expectedAllocateMaxMove = _dfBranchUint("DF_ALLOCATE_MAX_MOVE", branchIndex);
        address underlying = address(dToken.underlying());
        if (block.chainid == MAINNET_CHAIN_ID) {
            require(dToken.vault() == address(vault), "DF verify: dToken vault");
            require(address(vault.dToken()) == address(dToken), "DF verify: vault dToken");
            require(address(vault.underlying()) == underlying, "DF verify: vault underlying");
        }
        _requireMainnetDay1Envelope(
            branchIndex, address(dToken), underlying, dToken.underlyingDecimals(), expectedCap, expectedAllocateMaxMove
        );

        require(dToken.cap() == (requireFrozenCap ? 0 : expectedCap), "DF verify: dToken cap");
        require(
            vault.bufferTargetBps() == _dfBranchUint("DF_BUFFER_TARGET_BPS", branchIndex), "DF verify: buffer target"
        );
        require(vault.bufferFloor() == _dfBranchUint("DF_BUFFER_FLOOR", branchIndex), "DF verify: buffer floor");
        require(vault.withdrawDelay() == _dfBranchUint("DF_WITHDRAW_DELAY", branchIndex), "DF verify: withdraw delay");
        require(vault.allocateMaxMove() == expectedAllocateMaxMove, "DF verify: allocate max move");
        require(
            vault.allocatorCooldown() == _dfBranchUint("DF_ALLOCATOR_COOLDOWN", branchIndex),
            "DF verify: allocator cooldown"
        );
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
        cfg.allowPendingOwnership = _envFlag("DF_VERIFY_PENDING_OWNERSHIP");

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
        require(cfg.activeBranches <= cfg.totalBranches, "DF verify: branch count");
        require(cfg.strategyOwner == cfg.guardian, "DF verify: strategy owner must be guardian");
        require(cfg.strategyUpgrader == cfg.timelock, "DF verify: strategy upgrader must be timelock");
        require(cfg.priceFeedOwner != cfg.timelock, "DF verify: priceFeedOwner=timelock");
        require(cfg.priceFeedOwner != cfg.guardian, "DF verify: priceFeedOwner=guardian");
        require(cfg.priceFeedOwner != cfg.allocator, "DF verify: priceFeedOwner=allocator");
        require(cfg.timelock != cfg.guardian, "DF verify: timelock=guardian");
        require(cfg.timelock != cfg.allocator, "DF verify: timelock=allocator");
        require(cfg.timelock != cfg.writeoff, "DF verify: timelock=writeoff");
        require(cfg.guardian != cfg.allocator, "DF verify: guardian=allocator");
        require(cfg.guardian != cfg.writeoff, "DF verify: guardian=writeoff");
        require(cfg.allocator != cfg.writeoff, "DF verify: allocator=writeoff");
    }

    function _requireMainnetProductionGovernance(string memory manifest, HandoverConfig memory cfg) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;
        _requireMainnetDay1BranchTopology(cfg.totalBranches, cfg.activeBranches);
        MainnetProductionTimelockPolicy.requireValid(cfg.timelock);
        MainnetProductionTimelockPolicy.requireRoleHolders(
            cfg.treasury, cfg.interestRouterRecipient, cfg.guardian, cfg.allocator, cfg.writeoff, cfg.priceFeedOwner
        );
        require(cfg.dTokenOwner == cfg.timelock, "DF verify: production dToken owner");
        require(cfg.vaultAdmin == cfg.timelock, "DF verify: production vault admin");
        for (uint256 i; i < cfg.activeBranches; ++i) {
            require(
                _dfYield(manifest, i, "lidoReferralManager") == cfg.timelock, "DF verify: production manifest Timelock"
            );
        }
    }

    function _requireMainnetDay1BranchTopology(uint256 totalBranches, uint256 activeBranches) internal view {
        if (block.chainid != MAINNET_CHAIN_ID) return;
        require(totalBranches == 8, "DF verify: production total branches");
        require(activeBranches == 2, "DF verify: production active branches");
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
            require(vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, i)), "DF verify: missing strategy");
        }
        require(
            !vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, expectedCount)),
            "DF verify: strategy count mismatch"
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
        require(value != address(0), string.concat("DF verify: zero ", label));
    }
}
