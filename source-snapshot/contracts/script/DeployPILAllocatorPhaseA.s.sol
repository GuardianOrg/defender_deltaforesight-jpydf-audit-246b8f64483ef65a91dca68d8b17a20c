// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

import {PILAllocator} from "src/PILAllocator.sol";
import {UniV4MerklInitiative} from "src/Initiatives/UniV4MerklInitiative.sol";
import {IDistributionCreator} from "src/Interfaces/IDistributionCreator.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";

contract DeployPILAllocatorPhaseA is Script {
    using Strings for *;

    uint256 internal constant MERKL_TOTAL_WEIGHT = 10_000;

    struct Config {
        address jpydfToken;
        address owner;
        address guardian;
        uint256 epochStart;
        uint256 epochDuration;
        uint256 minDistribute;
        address merklDistributionCreator;
        address campaignCreator;
        uint256 campaignJpydfAmountThreshold;
        uint256 campaignCreationWindow;
        bytes32 uniV4PoolId;
        uint32 weightFees;
        uint32 weightToken0;
        uint32 weightToken1;
    }

    error DeployPILAllocatorPhaseA__ZeroAddress(string key);
    error DeployPILAllocatorPhaseA__NotContract(string key, address account);
    error DeployPILAllocatorPhaseA__EpochStartInFuture(uint256 epochStart);
    error DeployPILAllocatorPhaseA__InvalidEpochDuration(uint256 epochDuration);
    error DeployPILAllocatorPhaseA__ZeroAmount(string key);
    error DeployPILAllocatorPhaseA__InvalidCampaignCreationWindow(uint256 window, uint256 epochDuration);
    error DeployPILAllocatorPhaseA__PoolIdZero();
    error DeployPILAllocatorPhaseA__InvalidMerklWeights(uint256 totalWeight);
    error DeployPILAllocatorPhaseA__ExplicitSaltRequired();
    error DeployPILAllocatorPhaseA__EnvUint32Overflow(string key, uint256 value);
    error DeployPILAllocatorPhaseA__VerificationFailed(string field);

    function run() external returns (PILAllocator allocator, UniV4MerklInitiative initiative) {
        Config memory cfg = _loadConfig();
        (bytes32 salt, string memory saltString) = _deploymentSalt();

        _requireConfig(cfg);

        console2.log("PILAllocator Phase-A deploy");
        console2.log("JPYdf token:", cfg.jpydfToken);
        console2.log("CREATE2 salt:", saltString);
        console2.log("salt hash:", uint256(salt).toHexString(32));

        _startBroadcast();
        (allocator, initiative) = _deployContracts(cfg, salt);
        vm.stopBroadcast();

        string memory outputPath = vm.envOr("DF_PILA_OUTPUT_MANIFEST", string("pil-activation-manifest.json"));
        vm.writeFile(outputPath, _manifestJson(cfg, address(allocator), address(initiative), salt));

        console2.log("PILAllocator:", address(allocator));
        console2.log("UniV4MerklInitiative:", address(initiative));
        console2.log("PIL activation manifest:", outputPath);
    }

    function _deployContracts(Config memory cfg, bytes32 salt)
        internal
        returns (PILAllocator allocator, UniV4MerklInitiative initiative)
    {
        allocator = new PILAllocator{salt: salt}(
            IJpydfToken(cfg.jpydfToken), cfg.epochStart, cfg.epochDuration, cfg.minDistribute, cfg.owner, cfg.guardian
        );
        initiative = new UniV4MerklInitiative{salt: salt}(
            address(allocator),
            IERC20(cfg.jpydfToken),
            IDistributionCreator(cfg.merklDistributionCreator),
            cfg.campaignCreator,
            cfg.campaignJpydfAmountThreshold,
            cfg.campaignCreationWindow,
            cfg.uniV4PoolId,
            cfg.weightFees,
            cfg.weightToken0,
            cfg.weightToken1,
            cfg.epochStart,
            cfg.epochDuration
        );

        _verifyDeployment(cfg, allocator, initiative);
    }

    function _loadConfig() internal view returns (Config memory cfg) {
        string memory manifestPath = vm.envOr("DF_PILA_DEPLOYMENT_MANIFEST", string("deployment-manifest.json"));
        string memory manifest = vm.readFile(manifestPath);
        if (block.chainid == 1) {
            ScriptSecurityPolicy.requireProductionManifestForMainnet(
                block.chainid, vm.parseJsonString(manifest, ".deploymentClassification")
            );
        }

        cfg.jpydfToken = vm.parseJsonAddress(manifest, ".jpydfToken");
        cfg.owner = vm.envAddress("DF_PILA_OWNER");
        cfg.guardian = vm.envAddress("DF_PILA_GUARDIAN");
        cfg.epochStart = vm.envUint("DF_PILA_EPOCH_START");
        cfg.epochDuration = vm.envUint("DF_PILA_EPOCH_DURATION");
        cfg.minDistribute = vm.envUint("DF_PILA_MIN_DISTRIBUTE");
        cfg.merklDistributionCreator = vm.envAddress("DF_PILA_MERKL_DISTRIBUTION_CREATOR");
        cfg.campaignCreator = vm.envAddress("DF_PILA_CAMPAIGN_CREATOR");
        cfg.campaignJpydfAmountThreshold = vm.envUint("DF_PILA_CAMPAIGN_THRESHOLD");
        cfg.campaignCreationWindow = vm.envUint("DF_PILA_CAMPAIGN_CREATION_WINDOW");
        cfg.uniV4PoolId = vm.envBytes32("DF_PILA_UNIV4_POOL_ID");
        cfg.weightFees = _envUint32("DF_PILA_WEIGHT_FEES");
        cfg.weightToken0 = _envUint32("DF_PILA_WEIGHT_TOKEN0");
        cfg.weightToken1 = _envUint32("DF_PILA_WEIGHT_TOKEN1");
    }

    function _startBroadcast() internal {
        try vm.envBytes("DEPLOYER") returns (bytes memory raw) {
            if (raw.length == 0) {
                vm.startBroadcast();
            } else {
                ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", raw);
                vm.startBroadcast(vm.envAddress("DEPLOYER"));
            }
        } catch {
            vm.startBroadcast();
        }
    }

    function _deploymentSalt() internal view returns (bytes32 salt, string memory saltString) {
        return _resolveDeploymentSalt(
            vm.envOr("DF_PILA_SALT", string("")), vm.envOr("SALT", string("")), block.chainid, block.timestamp
        );
    }

    function _resolveDeploymentSalt(
        string memory pilaSalt,
        string memory sharedSalt,
        uint256 chainId,
        uint256 timestamp
    ) internal pure returns (bytes32 salt, string memory saltString) {
        saltString = pilaSalt;
        if (bytes(saltString).length == 0) saltString = sharedSalt;
        if (bytes(saltString).length == 0) {
            if (chainId == 1) revert DeployPILAllocatorPhaseA__ExplicitSaltRequired();
            saltString = timestamp.toString();
        }

        salt = keccak256(bytes(saltString));
    }

    function _requireConfig(Config memory cfg) internal view {
        _requireNonZero("jpydfToken", cfg.jpydfToken);
        _requireNonZero("DF_PILA_OWNER", cfg.owner);
        _requireNonZero("DF_PILA_GUARDIAN", cfg.guardian);
        _requireNonZero("DF_PILA_MERKL_DISTRIBUTION_CREATOR", cfg.merklDistributionCreator);
        _requireNonZero("DF_PILA_CAMPAIGN_CREATOR", cfg.campaignCreator);

        _requireContract("jpydfToken", cfg.jpydfToken);
        _requireContract("DF_PILA_MERKL_DISTRIBUTION_CREATOR", cfg.merklDistributionCreator);

        if (cfg.epochStart > block.timestamp) {
            revert DeployPILAllocatorPhaseA__EpochStartInFuture(cfg.epochStart);
        }
        if (cfg.epochDuration == 0 || cfg.epochDuration > type(uint32).max) {
            revert DeployPILAllocatorPhaseA__InvalidEpochDuration(cfg.epochDuration);
        }
        if (cfg.minDistribute == 0) revert DeployPILAllocatorPhaseA__ZeroAmount("DF_PILA_MIN_DISTRIBUTE");
        if (cfg.campaignJpydfAmountThreshold == 0) {
            revert DeployPILAllocatorPhaseA__ZeroAmount("DF_PILA_CAMPAIGN_THRESHOLD");
        }
        if (cfg.campaignCreationWindow == 0 || cfg.campaignCreationWindow >= cfg.epochDuration) {
            revert DeployPILAllocatorPhaseA__InvalidCampaignCreationWindow(
                cfg.campaignCreationWindow, cfg.epochDuration
            );
        }
        if (cfg.uniV4PoolId == bytes32(0)) revert DeployPILAllocatorPhaseA__PoolIdZero();

        uint256 totalWeight = uint256(cfg.weightFees) + uint256(cfg.weightToken0) + uint256(cfg.weightToken1);
        if (totalWeight != MERKL_TOTAL_WEIGHT) {
            revert DeployPILAllocatorPhaseA__InvalidMerklWeights(totalWeight);
        }

        if (block.chainid == 1) {
            _requireContract("DF_PILA_OWNER", cfg.owner);
            _requireContract("DF_PILA_GUARDIAN", cfg.guardian);
        }
    }

    function _envUint32(string memory key) internal view returns (uint32 value) {
        uint256 rawValue = vm.envUint(key);
        if (rawValue > type(uint32).max) revert DeployPILAllocatorPhaseA__EnvUint32Overflow(key, rawValue);

        value = uint32(rawValue);
    }

    function _manifestJson(Config memory cfg, address allocator, address initiative, bytes32 salt)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "{",
            string.concat(
                string.concat('"deploymentMode":"pilallocator-phase-a",'),
                string.concat('"saltHash":"', uint256(salt).toHexString(32), '",'),
                string.concat('"jpydfToken":"', cfg.jpydfToken.toHexString(), '",'),
                string.concat('"pilAllocator":"', allocator.toHexString(), '",'),
                string.concat('"uniV4MerklInitiative":"', initiative.toHexString(), '",')
            ),
            string.concat(
                string.concat('"owner":"', cfg.owner.toHexString(), '",'),
                string.concat('"guardian":"', cfg.guardian.toHexString(), '",'),
                string.concat('"epochStart":"', cfg.epochStart.toString(), '",'),
                string.concat('"epochDuration":"', cfg.epochDuration.toString(), '",'),
                string.concat('"minDistribute":"', cfg.minDistribute.toString(), '",')
            ),
            string.concat(
                string.concat('"merklDistributionCreator":"', cfg.merklDistributionCreator.toHexString(), '",'),
                string.concat('"campaignCreator":"', cfg.campaignCreator.toHexString(), '",'),
                string.concat('"campaignJpydfAmountThreshold":"', cfg.campaignJpydfAmountThreshold.toString(), '",'),
                string.concat('"campaignCreationWindow":"', cfg.campaignCreationWindow.toString(), '",')
            ),
            string.concat(
                string.concat('"uniV4PoolId":"', uint256(cfg.uniV4PoolId).toHexString(32), '",'),
                string.concat('"weightFees":"', uint256(cfg.weightFees).toString(), '",'),
                string.concat('"weightToken0":"', uint256(cfg.weightToken0).toString(), '",'),
                string.concat('"weightToken1":"', uint256(cfg.weightToken1).toString(), '"')
            ),
            "}"
        );
    }

    function _verifyDeployment(Config memory cfg, PILAllocator allocator, UniV4MerklInitiative initiative)
        internal
        view
    {
        if (address(allocator.jpydfToken()) != cfg.jpydfToken) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.jpydfToken");
        }
        if (allocator.EPOCH_START() != cfg.epochStart) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.EPOCH_START");
        }
        if (allocator.EPOCH_DURATION() != cfg.epochDuration) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.EPOCH_DURATION");
        }
        if (allocator.MIN_DISTRIBUTE() != cfg.minDistribute) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.MIN_DISTRIBUTE");
        }
        if (allocator.owner() != cfg.owner) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.owner");
        }
        if (allocator.guardian() != cfg.guardian) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("allocator.guardian");
        }
        if (initiative.allocator() != address(allocator)) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.allocator");
        }
        if (address(initiative.jpydfToken()) != cfg.jpydfToken) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.jpydfToken");
        }
        if (address(initiative.merklDistributionCreator()) != cfg.merklDistributionCreator) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.merklDistributionCreator");
        }
        if (initiative.CAMPAIGN_CREATOR() != cfg.campaignCreator) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.CAMPAIGN_CREATOR");
        }
        if (initiative.CAMPAIGN_JPYDF_AMOUNT_THRESHOLD() != cfg.campaignJpydfAmountThreshold) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.CAMPAIGN_JPYDF_AMOUNT_THRESHOLD");
        }
        if (initiative.CAMPAIGN_CREATION_WINDOW() != cfg.campaignCreationWindow) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.CAMPAIGN_CREATION_WINDOW");
        }
        if (initiative.UNIV4_POOL_ID() != cfg.uniV4PoolId) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.UNIV4_POOL_ID");
        }
        if (initiative.WEIGHT_FEES() != cfg.weightFees) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.WEIGHT_FEES");
        }
        if (initiative.WEIGHT_TOKEN_0() != cfg.weightToken0) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.WEIGHT_TOKEN_0");
        }
        if (initiative.WEIGHT_TOKEN_1() != cfg.weightToken1) {
            revert DeployPILAllocatorPhaseA__VerificationFailed("initiative.WEIGHT_TOKEN_1");
        }
    }

    function _requireNonZero(string memory key, address account) internal pure {
        if (account == address(0)) revert DeployPILAllocatorPhaseA__ZeroAddress(key);
    }

    function _requireContract(string memory key, address account) internal view {
        if (account.code.length == 0) revert DeployPILAllocatorPhaseA__NotContract(key, account);
    }
}
