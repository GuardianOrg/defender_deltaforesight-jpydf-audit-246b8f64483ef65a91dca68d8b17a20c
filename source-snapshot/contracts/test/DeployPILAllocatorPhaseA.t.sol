// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import "../script/DeployPILAllocatorPhaseA.s.sol";
import "../src/Interfaces/IDistributionCreator.sol";

contract DeployPILAllocatorPhaseAHarness is DeployPILAllocatorPhaseA {
    function loadConfigForHarness() external view returns (Config memory cfg) {
        cfg = _loadConfig();
    }

    function deploymentSaltForHarness() external view returns (bytes32 salt, string memory saltString) {
        (salt, saltString) = _deploymentSalt();
    }

    function resolveDeploymentSaltForHarness(
        string memory pilaSalt,
        string memory sharedSalt,
        uint256 chainId,
        uint256 timestamp
    ) external pure returns (bytes32 salt, string memory saltString) {
        (salt, saltString) = _resolveDeploymentSalt(pilaSalt, sharedSalt, chainId, timestamp);
    }

    function requireConfigForHarness(Config memory cfg) external view {
        _requireConfig(cfg);
    }

    function deployContractsForHarness(Config memory cfg, bytes32 salt)
        external
        returns (PILAllocator allocator, UniV4MerklInitiative initiative)
    {
        return _deployContracts(cfg, salt);
    }

    function manifestJsonForHarness(Config memory cfg, address allocator, address initiative, bytes32 salt)
        external
        pure
        returns (string memory)
    {
        return _manifestJson(cfg, allocator, initiative, salt);
    }

    function envUint32ForHarness(string memory key) external view returns (uint32 value) {
        value = _envUint32(key);
    }
}

contract MockJpydfToken {}

contract MockRoleHolder {}

contract MockDistributionCreator is IDistributionCreator {
    bool public acceptedConditions;

    function acceptConditions() external {
        acceptedConditions = true;
    }

    function campaignId(CampaignParameters memory) external pure returns (bytes32) {
        return keccak256("mock-campaign");
    }

    function createCampaign(CampaignParameters memory) external pure returns (bytes32) {
        return keccak256("mock-campaign");
    }
}

contract DeployPILAllocatorPhaseATest is Test {
    using Strings for *;

    DeployPILAllocatorPhaseAHarness internal harness;
    MockJpydfToken internal jpydfToken;
    MockDistributionCreator internal merkl;

    function setUp() public {
        vm.chainId(31337);
        vm.warp(1_800_000_000);
        harness = new DeployPILAllocatorPhaseAHarness();
        jpydfToken = new MockJpydfToken();
        merkl = new MockDistributionCreator();
    }

    function test_DeployContractsUsesProductionScriptPath() public {
        DeployPILAllocatorPhaseA.Config memory cfg = _validConfig();

        (PILAllocator allocator, UniV4MerklInitiative initiative) =
            harness.deployContractsForHarness(cfg, keccak256("pil-test"));

        assertEq(address(allocator.jpydfToken()), cfg.jpydfToken, "allocator token");
        assertEq(allocator.owner(), cfg.owner, "allocator owner");
        assertEq(allocator.guardian(), cfg.guardian, "allocator guardian");
        assertEq(initiative.allocator(), address(allocator), "initiative allocator");
        assertEq(address(initiative.jpydfToken()), cfg.jpydfToken, "initiative token");
        assertEq(address(initiative.merklDistributionCreator()), cfg.merklDistributionCreator, "merkl");
        assertEq(initiative.UNIV4_POOL_ID(), cfg.uniV4PoolId, "pool id");
        assertTrue(merkl.acceptedConditions(), "conditions accepted");
    }

    function test_RequireConfigRejectsInvalidMerklWeights() public {
        DeployPILAllocatorPhaseA.Config memory cfg = _validConfig();
        cfg.weightToken1 = 6_000;

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployPILAllocatorPhaseA.DeployPILAllocatorPhaseA__InvalidMerklWeights.selector, uint256(11_750)
            )
        );
        harness.requireConfigForHarness(cfg);
    }

    function test_RequireConfigRejectsMainnetCodelessAdminRoles() public {
        DeployPILAllocatorPhaseA.Config memory cfg = _validConfig();
        cfg.owner = makeAddr("owner-eoa");
        cfg.guardian = address(new MockRoleHolder());
        vm.chainId(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployPILAllocatorPhaseA.DeployPILAllocatorPhaseA__NotContract.selector, "DF_PILA_OWNER", cfg.owner
            )
        );
        harness.requireConfigForHarness(cfg);
    }

    function test_RequireConfigAllowsMainnetContractAdminRoles() public {
        DeployPILAllocatorPhaseA.Config memory cfg = _validConfig();
        cfg.owner = address(new MockRoleHolder());
        cfg.guardian = address(new MockRoleHolder());
        vm.chainId(1);

        harness.requireConfigForHarness(cfg);
    }

    function test_DeploymentSaltRequiresExplicitSaltOnMainnet() public {
        vm.expectRevert(DeployPILAllocatorPhaseA.DeployPILAllocatorPhaseA__ExplicitSaltRequired.selector);
        harness.resolveDeploymentSaltForHarness("", "", 1, block.timestamp);
    }

    function test_DeploymentSaltPrefersPilaSalt() public view {
        (bytes32 salt, string memory saltString) =
            harness.resolveDeploymentSaltForHarness("pila-salt", "shared-salt", block.chainid, block.timestamp);

        assertEq(salt, keccak256("pila-salt"), "salt hash");
        assertEq(saltString, "pila-salt", "salt string");
    }

    function test_EnvUint32RejectsOverflow() public {
        string memory key = "DF_PILA_UINT32_OVERFLOW_TEST";
        vm.setEnv(key, vm.toString(uint256(type(uint32).max) + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployPILAllocatorPhaseA.DeployPILAllocatorPhaseA__EnvUint32Overflow.selector,
                key,
                uint256(type(uint32).max) + 1
            )
        );
        harness.envUint32ForHarness(key);
    }

    function test_LoadConfigReadsJpydfManifestAndPilaEnv() public {
        string memory manifestPath = "./utils/assets/test_output/pil-deployment-manifest.json";
        try vm.removeFile(manifestPath) {} catch {}
        vm.writeFile(manifestPath, string.concat('{"jpydfToken":"', address(jpydfToken).toHexString(), '"}'));
        _setEnvFor(_validConfig(), manifestPath);

        DeployPILAllocatorPhaseA.Config memory loaded = harness.loadConfigForHarness();
        vm.removeFile(manifestPath);

        assertEq(loaded.jpydfToken, address(jpydfToken), "jpydf token");
        assertEq(loaded.owner, makeAddr("owner"), "owner");
        assertEq(loaded.guardian, makeAddr("guardian"), "guardian");
        assertEq(loaded.merklDistributionCreator, address(merkl), "merkl");
        assertEq(loaded.weightFees, 1_500, "fees");
        assertEq(loaded.weightToken0, 4_250, "token0");
        assertEq(loaded.weightToken1, 4_250, "token1");
    }

    function test_ManifestJsonIsMachineReadable() public {
        DeployPILAllocatorPhaseA.Config memory cfg = _validConfig();
        address allocator = makeAddr("allocator");
        address initiative = makeAddr("initiative");
        bytes32 salt = keccak256("manifest-salt");

        string memory json = harness.manifestJsonForHarness(cfg, allocator, initiative, salt);

        assertEq(vm.parseJsonString(json, ".deploymentMode"), "pilallocator-phase-a", "mode");
        assertEq(vm.parseJsonAddress(json, ".jpydfToken"), cfg.jpydfToken, "token");
        assertEq(vm.parseJsonAddress(json, ".pilAllocator"), allocator, "allocator");
        assertEq(vm.parseJsonAddress(json, ".uniV4MerklInitiative"), initiative, "initiative");
        assertEq(vm.parseJsonString(json, ".epochDuration"), vm.toString(cfg.epochDuration), "duration");
        assertEq(vm.parseJsonString(json, ".uniV4PoolId"), uint256(cfg.uniV4PoolId).toHexString(32), "pool id");
        assertEq(vm.parseJsonString(json, ".saltHash"), uint256(salt).toHexString(32), "salt");
    }

    function _validConfig() internal returns (DeployPILAllocatorPhaseA.Config memory cfg) {
        cfg.jpydfToken = address(jpydfToken);
        cfg.owner = makeAddr("owner");
        cfg.guardian = makeAddr("guardian");
        cfg.epochStart = block.timestamp;
        cfg.epochDuration = 7 days;
        cfg.minDistribute = 1_000e18;
        cfg.merklDistributionCreator = address(merkl);
        cfg.campaignCreator = makeAddr("campaign-creator");
        cfg.campaignJpydfAmountThreshold = 500e18;
        cfg.campaignCreationWindow = 1 days;
        cfg.uniV4PoolId = keccak256("JPYdf/USDC v4 pool");
        cfg.weightFees = 1_500;
        cfg.weightToken0 = 4_250;
        cfg.weightToken1 = 4_250;
    }

    function _setEnvFor(DeployPILAllocatorPhaseA.Config memory cfg, string memory manifestPath) internal {
        vm.setEnv("DF_PILA_DEPLOYMENT_MANIFEST", manifestPath);
        vm.setEnv("DF_PILA_OWNER", cfg.owner.toHexString());
        vm.setEnv("DF_PILA_GUARDIAN", cfg.guardian.toHexString());
        vm.setEnv("DF_PILA_EPOCH_START", vm.toString(cfg.epochStart));
        vm.setEnv("DF_PILA_EPOCH_DURATION", vm.toString(cfg.epochDuration));
        vm.setEnv("DF_PILA_MIN_DISTRIBUTE", vm.toString(cfg.minDistribute));
        vm.setEnv("DF_PILA_MERKL_DISTRIBUTION_CREATOR", cfg.merklDistributionCreator.toHexString());
        vm.setEnv("DF_PILA_CAMPAIGN_CREATOR", cfg.campaignCreator.toHexString());
        vm.setEnv("DF_PILA_CAMPAIGN_THRESHOLD", vm.toString(cfg.campaignJpydfAmountThreshold));
        vm.setEnv("DF_PILA_CAMPAIGN_CREATION_WINDOW", vm.toString(cfg.campaignCreationWindow));
        vm.setEnv("DF_PILA_UNIV4_POOL_ID", uint256(cfg.uniV4PoolId).toHexString(32));
        vm.setEnv("DF_PILA_WEIGHT_FEES", vm.toString(cfg.weightFees));
        vm.setEnv("DF_PILA_WEIGHT_TOKEN0", vm.toString(cfg.weightToken0));
        vm.setEnv("DF_PILA_WEIGHT_TOKEN1", vm.toString(cfg.weightToken1));
    }
}
