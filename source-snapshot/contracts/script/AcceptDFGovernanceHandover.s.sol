// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

interface ITwoStepOwnableAccept {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function acceptOwnership() external;
}

interface IAcceptInterestRouterForwarderView {
    function jpydfToken() external view returns (address);
    function recipient() external view returns (address);
}

interface IAcceptHandoverVaultStrategiesView {
    function getStrategiesCount() external view returns (uint256);
    function strategies(uint256 index) external view returns (address);
    function strategyConfigs(address strategy) external view returns (bool enabled, uint256 weightBps, uint256 cap);
    function totalWeightBps() external view returns (uint256);
}

/// @dev Local/CI helper for the second half of the DF governance handover.
///      Production Timelock/Safe holders should execute the same acceptOwnership()
///      calls through their own control plane; this script intentionally requires
///      private keys and is meant for EOA-backed local drills.
///
///      Usage:
///      DF_TIMELOCK=0x... DF_TIMELOCK_PRIVATE_KEY=0x... \
///      DF_INTEREST_ROUTER_RECIPIENT=0x... \
///      DF_PRICE_FEED_OWNER=0x... DF_PRICE_FEED_OWNER_PRIVATE_KEY=0x... \
///      DF_STRATEGY_OWNER=0x... DF_STRATEGY_OWNER_PRIVATE_KEY=0x... \
///      forge script AcceptDFGovernanceHandover --rpc-url ... --broadcast
contract AcceptDFGovernanceHandover is Script {
    struct HandoverConfig {
        address timelock;
        address interestRouterRecipient;
        address priceFeedOwner;
        address strategyOwner;
        uint256 timelockPrivateKey;
        uint256 priceFeedOwnerPrivateKey;
        uint256 strategyOwnerPrivateKey;
        uint256 totalBranches;
        uint256 activeBranches;
    }

    function run() external {
        _requireLocalChain(block.chainid);
        string memory manifest = vm.readFile(vm.envOr("DF_HANDOVER_MANIFEST", string("deployment-manifest.json")));
        HandoverConfig memory handoverConfig = _loadConfig();

        address interestRouter = _verifiedSharedInterestRouter(manifest, handoverConfig.totalBranches);
        _verifyInterestRouterForwarder(manifest, interestRouter, handoverConfig.interestRouterRecipient);
        _acceptIfPending(interestRouter, handoverConfig.timelock, handoverConfig.timelockPrivateKey, "interest router");

        for (uint256 branchIndex; branchIndex < handoverConfig.totalBranches; ++branchIndex) {
            _acceptIfPending(
                _dfYield(manifest, branchIndex, "dToken"),
                handoverConfig.timelock,
                handoverConfig.timelockPrivateKey,
                "dToken"
            );
            _acceptIfPending(
                _branch(manifest, branchIndex, "priceFeed"),
                handoverConfig.priceFeedOwner,
                handoverConfig.priceFeedOwnerPrivateKey,
                "price feed"
            );

            if (branchIndex < handoverConfig.activeBranches) {
                _acceptBranchStrategies(manifest, branchIndex, handoverConfig);
            }
        }
    }

    function _requireLocalChain(uint256 chainId) internal pure {
        ScriptSecurityPolicy.requireLocalChain(chainId);
    }

    function _verifiedSharedInterestRouter(string memory manifest, uint256 totalBranches)
        internal
        pure
        returns (address interestRouter)
    {
        interestRouter = _branch(manifest, 0, "interestRouter");
        for (uint256 branchIndex = 1; branchIndex < totalBranches; ++branchIndex) {
            require(
                _branch(manifest, branchIndex, "interestRouter") == interestRouter, "DF accept: mixed interest router"
            );
        }
    }

    function _verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        internal
        view
    {
        require(interestRouter != address(0), "DF accept: zero interest router");
        require(interestRouter.code.length != 0, "DF accept: codeless interest router");

        IAcceptInterestRouterForwarderView forwarder = IAcceptInterestRouterForwarderView(interestRouter);
        address token = _root(manifest, "jpydfToken");
        try forwarder.jpydfToken() returns (address actualToken) {
            require(actualToken == token, "DF accept: interest router token");
        } catch {
            revert("DF accept: not interest router forwarder");
        }

        try forwarder.recipient() returns (address recipient) {
            require(recipient == expectedRecipient, "DF accept: interest router recipient");
            IJpydfToken(token).requireValidRecipient(recipient);
        } catch {
            revert("DF accept: not interest router forwarder");
        }
    }

    function _acceptIfPending(
        address ownableTarget,
        address expectedPendingOwner,
        uint256 expectedOwnerPrivateKey,
        string memory targetLabel
    ) internal {
        require(ownableTarget != address(0), string.concat("DF accept: zero ", targetLabel));
        require(ownableTarget.code.length != 0, string.concat("DF accept: codeless ", targetLabel));

        ITwoStepOwnableAccept targetOwnable = ITwoStepOwnableAccept(ownableTarget);
        if (targetOwnable.owner() == expectedPendingOwner) return;

        require(targetOwnable.pendingOwner() == expectedPendingOwner, string.concat("DF accept: pending ", targetLabel));
        require(
            vm.addr(expectedOwnerPrivateKey) == expectedPendingOwner,
            string.concat("DF accept: key mismatch ", targetLabel)
        );

        vm.broadcast(expectedOwnerPrivateKey);
        targetOwnable.acceptOwnership();
        console2.log("Ownership accepted", targetLabel, ownableTarget, expectedPendingOwner);
    }

    function _acceptBranchStrategies(string memory manifest, uint256 branchIndex, HandoverConfig memory handoverConfig)
        internal
    {
        IAcceptHandoverVaultStrategiesView strategyList =
            IAcceptHandoverVaultStrategiesView(_dfYield(manifest, branchIndex, "collateralVault"));
        uint256 strategyCount = strategyList.getStrategiesCount();
        _requireManifestStrategyCount(manifest, branchIndex, strategyCount);

        if (strategyCount == 0) {
            return;
        }

        uint256 manifestTotalWeightBps;
        for (uint256 strategyIndex; strategyIndex < strategyCount; ++strategyIndex) {
            address strategy = strategyList.strategies(strategyIndex);
            require(strategy != address(0), "DF accept: zero strategy");
            require(strategy == _dfYieldStrategy(manifest, branchIndex, strategyIndex), "DF accept: strategy mismatch");
            (bool enabled, uint256 weightBps, uint256 cap) = strategyList.strategyConfigs(strategy);
            uint256 manifestWeightBps = _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyWeightBps");
            require(enabled, "DF accept: strategy disabled");
            require(weightBps == manifestWeightBps, "DF accept: strategy weight mismatch");
            require(
                cap == _dfYieldStrategyUint(manifest, branchIndex, strategyIndex, "strategyCap"),
                "DF accept: strategy cap mismatch"
            );
            manifestTotalWeightBps += manifestWeightBps;
            _acceptIfPending(strategy, handoverConfig.strategyOwner, handoverConfig.strategyOwnerPrivateKey, "strategy");
        }
        require(strategyList.totalWeightBps() == manifestTotalWeightBps, "DF accept: total strategy weight mismatch");
    }

    function _loadConfig() internal view returns (HandoverConfig memory handoverConfig) {
        handoverConfig.timelock = vm.envAddress("DF_TIMELOCK");
        handoverConfig.interestRouterRecipient = vm.envAddress("DF_INTEREST_ROUTER_RECIPIENT");
        handoverConfig.priceFeedOwner = vm.envAddress("DF_PRICE_FEED_OWNER");
        handoverConfig.strategyOwner = vm.envAddress("DF_STRATEGY_OWNER");
        handoverConfig.timelockPrivateKey = vm.envUint("DF_TIMELOCK_PRIVATE_KEY");
        handoverConfig.priceFeedOwnerPrivateKey = vm.envUint("DF_PRICE_FEED_OWNER_PRIVATE_KEY");
        handoverConfig.strategyOwnerPrivateKey = vm.envUint("DF_STRATEGY_OWNER_PRIVATE_KEY");
        handoverConfig.totalBranches = vm.envOr("DF_HANDOVER_TOTAL_BRANCHES", uint256(8));
        handoverConfig.activeBranches = vm.envOr("DF_HANDOVER_ACTIVE_BRANCHES", uint256(2));

        _requireNonZero(handoverConfig.timelock, "DF_TIMELOCK");
        _requireNonZero(handoverConfig.interestRouterRecipient, "DF_INTEREST_ROUTER_RECIPIENT");
        _requireNonZero(handoverConfig.priceFeedOwner, "DF_PRICE_FEED_OWNER");
        _requireNonZero(handoverConfig.strategyOwner, "DF_STRATEGY_OWNER");
        require(handoverConfig.activeBranches <= handoverConfig.totalBranches, "DF accept: branch count");
        require(handoverConfig.timelock != handoverConfig.priceFeedOwner, "DF accept: timelock=priceFeedOwner");
        require(handoverConfig.timelock != handoverConfig.strategyOwner, "DF accept: timelock=strategyOwner");
        require(
            handoverConfig.priceFeedOwner != handoverConfig.strategyOwner, "DF accept: priceFeedOwner=strategyOwner"
        );
    }

    function _dfYield(string memory manifest, uint256 branchIndex, string memory manifestKey)
        internal
        pure
        returns (address)
    {
        return vm.parseJsonAddress(manifest, string.concat(".dfYield[", vm.toString(branchIndex), "].", manifestKey));
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
            require(vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, i)), "DF accept: missing strategy");
        }
        require(
            !vm.keyExistsJson(manifest, _dfYieldStrategyPath(branchIndex, expectedCount)),
            "DF accept: strategy count mismatch"
        );
    }

    function _dfYieldStrategyPath(uint256 branchIndex, uint256 strategyIndex) internal pure returns (string memory) {
        return
            string.concat(
                ".dfYield[", vm.toString(branchIndex), "].strategies[", vm.toString(strategyIndex), "].strategy"
            );
    }

    function _branch(string memory manifest, uint256 branchIndex, string memory manifestKey)
        internal
        pure
        returns (address)
    {
        return vm.parseJsonAddress(manifest, string.concat(".branches[", vm.toString(branchIndex), "].", manifestKey));
    }

    function _root(string memory manifest, string memory manifestKey) internal pure returns (address) {
        return vm.parseJsonAddress(manifest, string.concat(".", manifestKey));
    }

    function _requireNonZero(address value, string memory label) internal pure {
        require(value != address(0), string.concat("DF accept: zero ", label));
    }
}
