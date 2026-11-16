// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../script/DeployLiquity2.s.sol";
import "../script/MainnetProductionTimelockPolicy.sol";
import "../script/local/LocalAaveVenue.sol";
import "../src/AddressesRegistry.sol";
import "../src/CollateralVault.sol";
import "../src/DToken.sol";
import "../src/JpydfToken.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/IAddressesRegistry.sol";
import "../src/Interfaces/IJpydfToken.sol";
import "../src/Interfaces/IStrategy.sol";
import "../src/Interfaces/ISkyUsdcSUsdsConverter.sol";
import "../src/Interfaces/IWETH.sol";
import "../src/Strategies/SkyUsdcSUsdsConverter.sol";
import "./TestContracts/WETH.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockMorphoV2Vault.sol";

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract DeployLiquity2StrategySelectorHarness is DeployLiquity2Script {
    function setHarnessDeployer(address deployerAddress) external {
        deployer = deployerAddress;
    }

    function setHarnessSalt(bytes32 salt) external {
        SALT = salt;
    }

    function setHarnessWETH(IWETH wethToken) external {
        WETH = wethToken;
    }

    function setHarnessUSDC(IERC20Metadata usdcToken) external {
        USDC = usdcToken;
    }

    function configureBaseTokensForHarness() external returns (IWETH wethToken, IERC20Metadata usdcToken) {
        _configureBaseTokens();
        return (WETH, USDC);
    }

    function sepoliaUsdcAddressForHarness() external pure returns (address) {
        return SepoliaExternalAddresses.AAVE_USDC;
    }

    function sepoliaAavePoolAddressForHarness() external pure returns (address) {
        return SepoliaExternalAddresses.AAVE_V3_POOL;
    }

    function sepoliaAaveATokenAddressForHarness() external pure returns (address) {
        return SepoliaExternalAddresses.AAVE_USDC_ATOKEN;
    }

    function resolveBridgeAdminForHarness() external returns (address) {
        return _resolveBridgeAdmin();
    }

    function validateBridgeAdminCandidateForHarness(address admin, bool configured) external view {
        _validateBridgeAdminCandidate(admin, configured);
    }

    function bridgeReadinessJsonForHarness(IJpydfToken jpydfToken) external view returns (string memory) {
        return _getBridgeReadinessJson(jpydfToken);
    }

    function setDfOracleFreezeForHarness(address jpyUsdOracle, uint256 jpyUsdStaleness, address jpyUsdRateProvider)
        external
    {
        dfJpyUsdOracle = jpyUsdOracle;
        dfJpyUsdStaleness = jpyUsdStaleness;
        dfJpyUsdRateProvider = jpyUsdRateProvider;
    }

    function envFreezeJsonForHarness(IJpydfToken jpydfToken, CollateralVault collateralVault, IInterestRouter router)
        external
        view
        returns (string memory)
    {
        DeploymentResult memory deployed;
        deployed.contractsArray = new LiquityContracts[](1);
        deployed.contractsArray[0].interestRouter = router;
        deployed.jpydfToken = jpydfToken;
        deployed.vaults = new CollateralVault[](1);
        deployed.vaults[0] = collateralVault;
        return _getEnvFreezeJson(deployed);
    }

    function deployAndRegisterStrategy(
        uint256 branchIndex,
        CollateralVault collateralVault,
        IERC20Metadata underlyingToken
    ) external returns (IStrategy) {
        return _deployAndRegisterStrategy(branchIndex, collateralVault, underlyingToken);
    }

    function deployAndRegisterStrategyAtIndex(
        uint256 branchIndex,
        uint256 strategyIndex,
        CollateralVault collateralVault,
        IERC20Metadata underlyingToken
    ) external returns (IStrategy) {
        return _deployAndRegisterStrategy(branchIndex, strategyIndex, collateralVault, underlyingToken);
    }

    function deployAndRegisterStrategies(
        uint256 branchIndex,
        CollateralVault collateralVault,
        IERC20Metadata underlyingToken
    ) external returns (IStrategy) {
        return _deployAndRegisterStrategies(branchIndex, collateralVault, underlyingToken);
    }

    function deployYieldLayerForHarness(
        IERC20Metadata underlyingToken,
        string memory dTokenName,
        string memory dTokenSymbol
    ) external returns (DToken dToken, CollateralVault collateralVault) {
        return _deployYieldLayer(underlyingToken, dTokenName, dTokenSymbol);
    }

    function dfYieldJsonForHarness(uint256 branchIndex, CollateralVault collateralVault, IERC20Metadata underlyingToken)
        external
        view
        returns (string memory)
    {
        DeploymentResult memory deployed;
        uint256 arrayLength = branchIndex + 1;
        deployed.contractsArray = new LiquityContracts[](arrayLength);
        deployed.vaults = new CollateralVault[](arrayLength);
        deployed.vaults[branchIndex] = collateralVault;
        deployed.dTokens = new DToken[](arrayLength);
        deployed.dTokens[branchIndex] = DToken(address(0x1000));
        deployed.strategies = new IStrategy[](arrayLength);
        if (collateralVault.getStrategiesCount() != 0) {
            deployed.strategies[branchIndex] = collateralVault.strategies(0);
        }
        deployed.underlyings = new IERC20Metadata[](arrayLength);
        deployed.underlyings[branchIndex] = underlyingToken;

        return string.concat(
            '{"strategies":[',
            _getDFYieldStrategiesJson(deployed, branchIndex, collateralVault.getStrategiesCount()),
            '],"jpyUsdRateProvider":"',
            vm.toString(dfJpyUsdRateProvider),
            '"}'
        );
    }

    function deployZapperForHarness(
        IAddressesRegistry addressesRegistry,
        CollateralVault collateralVault,
        IERC20 underlyingToken
    ) external returns (CollateralYieldZapper collateralYieldZapper) {
        return _deployZapper(addressesRegistry, collateralVault, underlyingToken, 0);
    }

    function resolveZapperExpectedStEthForHarness(
        IERC20 underlyingToken,
        uint256 branchIndex,
        address configuredStEth,
        bool enableLocalNativeEthRoute
    ) external view returns (address) {
        return _resolveZapperExpectedStEth(underlyingToken, branchIndex, configuredStEth, enableLocalNativeEthRoute);
    }

    function validateProductionNativeEthRouteForHarness(
        uint256 branchIndex,
        address configuredStEth,
        address lidoReferral,
        bool mainnetTestBuild
    ) external view {
        _validateProductionNativeEthRouteForProfile(branchIndex, configuredStEth, lidoReferral, mainnetTestBuild);
    }

    function day1NativeEthRouteForHarness() external view returns (address expectedStEth, address lidoReferral) {
        string memory ownerManifest = vm.readFile("../config/day1-branch-manifest.json");
        expectedStEth = vm.parseJsonAddress(ownerManifest, ".branches[0].nativeEthRoute.expectedStEth");
        lidoReferral = vm.parseJsonAddress(ownerManifest, ".branches[0].nativeEthRoute.lidoReferral");
    }

    function dfYieldNativeEthRouteJsonForHarness(CollateralYieldZapper collateralYieldZapper)
        external
        view
        returns (string memory)
    {
        return _getDFYieldNativeEthRouteJson(collateralYieldZapper);
    }

    function resolveZapperLidoReferralManagerForHarness(address configuredManager) external returns (address) {
        return _resolveZapperLidoReferralManagerCandidate(configuredManager);
    }

    function validateMainnetZapperLidoReferralManagerForHarness(address configuredManager, bool isCanary)
        external
        view
    {
        _validateMainnetZapperLidoReferralManager(configuredManager, isCanary);
    }

    function requireGovernanceEvidenceBindingForHarness(
        bytes memory evidence,
        bytes32 expectedSha256,
        address evidenceTimelock,
        address expectedTimelock
    ) external pure {
        MainnetProductionTimelockPolicy.requireGovernanceEvidenceBinding(
            evidence, expectedSha256, evidenceTimelock, expectedTimelock
        );
    }

    function envFlagForHarness(string memory key) external view returns (bool) {
        return _envFlag(key);
    }

    function validateRunModeGatesForHarness(
        string memory deploymentMode,
        bool mainnetDTokenWiring,
        string memory saltInput,
        string memory manifestPath
    ) external {
        _validateRunModeGates(deploymentMode, mainnetDTokenWiring, saltInput, manifestPath);
    }

    function validateMainnetCanaryExecutionBoundaryForHarness() external {
        _requireMainnetCanaryExecutionBoundary();
    }

    function validateMainnetCanaryGatesForHarness(
        string memory deploymentMode,
        string memory saltInput,
        string memory manifestPath,
        string memory minDebtAck,
        string memory canaryId,
        string memory broadcastPath,
        address expectedDeployer,
        string memory bridgeAdmin
    ) external view {
        _validateMainnetCanaryGates(
            MAINNET_CANARY_MIN_DEBT,
            deploymentMode,
            saltInput,
            manifestPath,
            minDebtAck,
            canaryId,
            broadcastPath,
            expectedDeployer,
            bridgeAdmin
        );
    }

    function deploymentClassificationForHarness() external view returns (string memory) {
        return _getDeploymentClassification();
    }

    function deploymentMetadataForHarness(string memory deploymentMode, string memory manifest)
        external
        view
        returns (string memory)
    {
        return _withDeploymentMetadata(manifest, deploymentMode);
    }

    function validateSepoliaLidoWiringForHarness(address wstEth, address stEth) external view {
        _validateSepoliaLidoWiring(wstEth, stEth);
    }

    function requireMainnetDay1StrategyPolicyForHarness(uint256 branchIndex) external view {
        _requireMainnetDay1StrategyPolicy(branchIndex);
    }

    function requireMainnetDay1StableStrategySetForHarness(uint256 branchIndex) external view {
        _requireMainnetDay1StableStrategySet(branchIndex);
    }

    function requireMainnetCanaryStableStrategySetForHarness(uint256 branchIndex) external view {
        _requireMainnetCanaryStableStrategySet(branchIndex);
    }
}

contract SelectorMockERC4626Vault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Selector ERC4626 Vault", "s4626") ERC4626(asset_) {}
}

contract SelectorMockSkyPsmWrapper is ISkyLitePsmWrapper {
    IERC20 public immutable usdcToken;
    IERC20 public immutable usdsToken;
    uint256 public tin;
    uint256 public tout;

    constructor(IERC20 _usdcToken, IERC20 _usdsToken) {
        usdcToken = _usdcToken;
        usdsToken = _usdsToken;
    }

    function gem() external view returns (address) {
        return address(usdcToken);
    }

    function dai() external view returns (address) {
        return address(usdsToken);
    }

    function sellGem(address, uint256 usdcAmount) external pure returns (uint256 usdsOut) {
        return usdcAmount * 1e12;
    }

    function buyGem(address, uint256 usdcAmount) external pure returns (uint256 usdsIn) {
        return usdcAmount * 1e12;
    }
}

contract SelectorMockVaultTreasury {
    address public immutable treasury;

    constructor(address treasury_) {
        treasury = treasury_;
    }
}

contract SelectorSepoliaLidoWstEthMock {
    address private immutable linkedStEth;
    uint256 private immutable rate;

    constructor(address linkedStEth_, uint256 rate_) {
        linkedStEth = linkedStEth_;
        rate = rate_;
    }

    function stETH() external view returns (address) {
        return linkedStEth;
    }

    function stEthPerToken() external view returns (uint256) {
        return rate;
    }
}

contract SelectorSepoliaLidoStEthMock {
    bool private immutable paused;
    bool private immutable stopped;
    uint256 private immutable stakeLimit;

    constructor(bool paused_, bool stopped_, uint256 stakeLimit_) {
        paused = paused_;
        stopped = stopped_;
        stakeLimit = stakeLimit_;
    }

    function isStakingPaused() external view returns (bool) {
        return paused;
    }

    function isStopped() external view returns (bool) {
        return stopped;
    }

    function getCurrentStakeLimit() external view returns (uint256) {
        return stakeLimit;
    }
}

contract DeployLiquity2StrategySelectorTest is Test {
    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");
    string internal constant INITIALIZABLE_ALREADY_INITIALIZED = "Initializable: contract is already initialized";
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    address internal constant SEPOLIA_LIDO_STETH = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af;
    address internal constant SEPOLIA_LIDO_WSTETH = 0xB82381A3fBD3FaFA77B3a7bE693342618240067b;
    address internal constant MAINNET_PILOT_TIMELOCK = 0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6;
    address internal constant MAINNET_ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    string internal constant CANARY_ACK = "JPYDF_MAINNET_CANARY_MIN_DEBT_1000_TEST_ONLY";
    string internal constant CANARY_ID = "jpydf-mainnet-persistent-canary-v2-2026-08";
    string internal constant CANARY_SALT = "JPYDF_MAINNET_PERSISTENT_CANARY_V2_2026_08";
    string internal constant CANARY_MANIFEST =
        "canary-artifacts/jpydf-mainnet-persistent-canary-v2-2026-08/deployment-manifest.json";
    string internal constant CANARY_BROADCAST = "canary-artifacts/jpydf-mainnet-persistent-canary-v2-2026-08/broadcast";

    address internal treasury = makeAddr("treasury");
    DeployLiquity2StrategySelectorHarness internal harness;

    struct YieldZapperFixture {
        CollateralYieldZapper collateralYieldZapper;
        address underlyingToken;
    }

    function setUp() public {
        vm.chainId(31337);
        harness = new DeployLiquity2StrategySelectorHarness();
        harness.setHarnessDeployer(address(this));
        vm.setEnv("DF_TREASURY", vm.toString(treasury));
        vm.setEnv("DF_ENABLE_MAINNET_DTOKEN_WIRING", "false");
        vm.setEnv("DF_BRIDGE_ADMIN", "");
        vm.setEnv("DF_TIMELOCK", "");
    }

    function test_ZapperReferralManagerRejectsMissingTimelockOnNonLocalChain() public {
        vm.chainId(11155111);
        vm.expectRevert(bytes("DeployLiquity2: missing DF_TIMELOCK for Lido referral manager"));
        harness.resolveZapperLidoReferralManagerForHarness(address(0));
    }

    function test_ZapperReferralManagerRejectsCodelessTimelock() public {
        vm.chainId(11155111);
        address codelessTimelock = makeAddr("codelessTimelock");

        vm.expectRevert(bytes("DF: codeless DF_TIMELOCK"));
        harness.resolveZapperLidoReferralManagerForHarness(codelessTimelock);
    }

    function test_ZapperReferralManagerProbesConfiguredNonMainnetTimelock() public {
        TimelockController timelock = _deployTimelock(1 days);
        vm.chainId(11155111);

        assertEq(
            harness.resolveZapperLidoReferralManagerForHarness(address(timelock)),
            address(timelock),
            "configured Timelock accepted"
        );
    }

    function test_ZapperReferralManagerAcceptsExactFiveMinuteMainnetCanaryTimelock() public {
        vm.chainId(1);
        _installMainnetPilotTimelock(5 minutes);

        harness.validateMainnetZapperLidoReferralManagerForHarness(MAINNET_PILOT_TIMELOCK, true);
    }

    function test_ZapperReferralManagerRejectsWrongMainnetCanaryTimelock() public {
        vm.chainId(1);
        TimelockController timelock = _deployTimelock(5 minutes);

        vm.expectRevert(bytes("DeployLiquity2: canary requires pilot Timelock"));
        harness.validateMainnetZapperLidoReferralManagerForHarness(address(timelock), true);
    }

    function test_ZapperReferralManagerRejectsWrongMainnetCanaryDelay() public {
        vm.chainId(1);
        _installMainnetPilotTimelock(12 hours);

        vm.expectRevert(bytes("DeployLiquity2: canary Timelock delay"));
        harness.validateMainnetZapperLidoReferralManagerForHarness(MAINNET_PILOT_TIMELOCK, true);
    }

    function test_ZapperReferralManagerRejectsWrongMainnetCanaryCodehash() public {
        vm.chainId(1);
        vm.etch(MAINNET_PILOT_TIMELOCK, hex"6000");

        vm.expectRevert(bytes("DeployLiquity2: Timelock codehash"));
        harness.validateMainnetZapperLidoReferralManagerForHarness(MAINNET_PILOT_TIMELOCK, true);
    }

    function test_ZapperReferralManagerAcceptsDistinctTwelveHourProductionTimelock() public {
        vm.chainId(1);
        TimelockController timelock = _deployProductionTimelock(12 hours);

        harness.validateMainnetZapperLidoReferralManagerForHarness(address(timelock), false);
    }

    function test_ZapperReferralManagerRejectsWrongProductionTimelockRoles() public {
        vm.chainId(1);
        TimelockController timelock = _deployTimelock(12 hours);

        vm.expectRevert(MainnetProductionTimelockPolicy.RoleMismatch.selector);
        harness.validateMainnetZapperLidoReferralManagerForHarness(address(timelock), false);
    }

    function test_ProductionGovernanceEvidenceBindingRejectsAddressOrHashDrift() public {
        bytes memory evidence = bytes('{"timelock":"0x1111111111111111111111111111111111111111"}');
        address timelock = 0x1111111111111111111111111111111111111111;
        bytes32 evidenceSha256 = sha256(evidence);

        harness.requireGovernanceEvidenceBindingForHarness(evidence, evidenceSha256, timelock, timelock);
        vm.expectRevert(MainnetProductionTimelockPolicy.GovernanceEvidenceMismatch.selector);
        harness.requireGovernanceEvidenceBindingForHarness(evidence, bytes32(uint256(1)), timelock, timelock);
        vm.expectRevert(MainnetProductionTimelockPolicy.GovernanceEvidenceMismatch.selector);
        harness.requireGovernanceEvidenceBindingForHarness(evidence, evidenceSha256, timelock, address(0xBEEF));
    }

    function test_ZapperReferralManagerRejectsPilotTimelockForProduction() public {
        vm.chainId(1);
        _installMainnetPilotTimelock(12 hours);

        vm.expectRevert(MainnetProductionTimelockPolicy.PilotTimelockForbidden.selector);
        harness.validateMainnetZapperLidoReferralManagerForHarness(MAINNET_PILOT_TIMELOCK, false);
    }

    function test_ZapperReferralManagerRejectsWrongProductionTimelockDelay() public {
        vm.chainId(1);
        TimelockController timelock = _deployTimelock(5 minutes);

        vm.expectRevert(
            abi.encodeWithSelector(MainnetProductionTimelockPolicy.MinDelayMismatch.selector, uint256(5 minutes))
        );
        harness.validateMainnetZapperLidoReferralManagerForHarness(address(timelock), false);
    }

    function test_ZapperReferralManagerRejectsNonOzProductionTimelock() public {
        vm.chainId(1);

        vm.expectRevert(MainnetProductionTimelockPolicy.RuntimeCodehashMismatch.selector);
        harness.validateMainnetZapperLidoReferralManagerForHarness(address(harness), false);
    }

    function test_ResolveBridgeAdminValidatesConfiguredContract() public {
        harness.validateBridgeAdminCandidateForHarness(address(harness), true);

        vm.expectRevert(bytes("DeployLiquity2: zero bridge admin"));
        harness.validateBridgeAdminCandidateForHarness(address(0), true);

        address deployerAddress = makeAddr("bridgeDeployDeployer");
        harness.setHarnessDeployer(deployerAddress);
        vm.expectRevert(bytes("DeployLiquity2: bridge admin is deployer"));
        harness.validateBridgeAdminCandidateForHarness(deployerAddress, true);

        vm.expectRevert(bytes("DF: codeless DF_BRIDGE_ADMIN"));
        harness.validateBridgeAdminCandidateForHarness(makeAddr("bridgeAdminEoa"), true);
    }

    function test_BridgeReadinessJsonIncludesDay1LaunchEvidence() public {
        JpydfToken token = new JpydfToken(address(this), address(harness));
        string memory manifestFragment =
            string.concat("{", harness.bridgeReadinessJsonForHarness(IJpydfToken(address(token))), '"tail":true}');

        assertEq(vm.parseJsonAddress(manifestFragment, ".bridgeAdmin"), address(harness), "bridge admin");
        assertEq(abi.decode(vm.parseJson(manifestFragment, ".bridgeMinterCount"), (uint256)), 0, "bridge minter count");
        assertEq(vm.parseJsonAddress(manifestFragment, ".proposedBridgeMinter"), address(0), "proposed minter");
        assertEq(
            abi.decode(vm.parseJson(manifestFragment, ".launchEvidence.bridgeMinterCount"), (uint256)),
            0,
            "launch minter count"
        );
        assertEq(
            vm.parseJsonAddress(manifestFragment, ".launchEvidence.proposedBridgeMinter"), address(0), "launch proposal"
        );
        assertEq(vm.parseJsonAddress(manifestFragment, ".launchEvidence.bridgeAdapter"), address(0), "bridge adapter");
        assertFalse(
            abi.decode(vm.parseJson(manifestFragment, ".launchEvidence.activeBridgeAdapter"), (bool)),
            "active bridge adapter"
        );
        assertEq(
            vm.parseJsonString(manifestFragment, ".launchEvidence.day1JpydfLiquidityVenue"),
            "uniswap-v4",
            "liquidity venue"
        );
        assertEq(
            vm.parseJsonString(manifestFragment, ".launchEvidence.day1JpydfLiquidityPair"),
            "JPYdf/USDC",
            "liquidity pair"
        );
        assertEq(
            vm.parseJsonString(manifestFragment, ".launchEvidence.uniswapV4RouteStatus"),
            "unwired-audit-scope",
            "route status"
        );
        assertEq(
            vm.parseJsonAddress(manifestFragment, ".launchEvidence.uniswapV4RouteAdapter"), address(0), "v4 adapter"
        );
        assertFalse(
            abi.decode(vm.parseJson(manifestFragment, ".launchEvidence.nonDay1JpydfLiquidityRoute"), (bool)),
            "non-Day-1 route"
        );
    }

    function test_EnvFreezeJsonIncludesGovernanceTreasuryAndOracleEvidence() public {
        address recipient = makeAddr("interestRecipient");
        address owner = makeAddr("interestOwner");
        address jpyUsdFeed = makeAddr("jpyUsdFeed");
        address jpyUsdRateProvider = makeAddr("jpyUsdRateProvider");
        uint256 jpyUsdStaleness = 72 hours;
        JpydfToken token = new JpydfToken(address(this), address(harness));
        InterestRouterForwarder router = new InterestRouterForwarder(IERC20(address(token)), recipient, owner);
        SelectorMockVaultTreasury vault = new SelectorMockVaultTreasury(treasury);

        harness.setDfOracleFreezeForHarness(jpyUsdFeed, jpyUsdStaleness, jpyUsdRateProvider);

        string memory manifestFragment = string.concat(
            '{"envFreeze":',
            harness.envFreezeJsonForHarness(
                IJpydfToken(address(token)), CollateralVault(address(vault)), IInterestRouter(address(router))
            ),
            "}"
        );

        assertEq(vm.parseJsonAddress(manifestFragment, ".envFreeze.bridgeAdmin"), address(harness), "bridge admin");
        assertEq(vm.parseJsonAddress(manifestFragment, ".envFreeze.treasury"), treasury, "treasury");
        assertEq(vm.parseJsonAddress(manifestFragment, ".envFreeze.interestRouter"), address(router), "router");
        assertEq(
            vm.parseJsonAddress(manifestFragment, ".envFreeze.interestRouterRecipient"), recipient, "router recipient"
        );
        assertEq(vm.parseJsonAddress(manifestFragment, ".envFreeze.interestRouterOwner"), owner, "router owner");
        assertEq(
            vm.parseJsonAddress(manifestFragment, ".envFreeze.interestRouterPendingOwner"), address(0), "pending owner"
        );
        assertEq(vm.parseJsonAddress(manifestFragment, ".envFreeze.jpyUsdFeed"), jpyUsdFeed, "jpy feed");
        assertEq(
            vm.parseJsonAddress(manifestFragment, ".envFreeze.jpyUsdRateProvider"),
            jpyUsdRateProvider,
            "shared jpy provider"
        );
        assertEq(
            vm.parseJsonString(manifestFragment, ".envFreeze.jpyUsdStaleness"),
            vm.toString(jpyUsdStaleness),
            "jpy staleness"
        );
    }

    function test_Run_RevertsOnMainnetCompleteWithoutDTokenWiringFlag() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: mainnet dToken wiring disabled"));
        harness.validateRunModeGatesForHarness("complete", false, "", "");
    }

    function test_Run_RevertsOnMainnetProductionWithoutExplicitSalt() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: mainnet requires explicit SALT"));
        harness.validateRunModeGatesForHarness("complete", true, "", "deployment-manifest.json");
    }

    function test_Run_AcceptsProductionBuildWithoutCanaryIdentity() public {
        vm.chainId(1);
        vm.setEnv("DF_MAINNET_CANARY_ID", "");

        harness.validateRunModeGatesForHarness("complete", true, CANARY_SALT, CANARY_MANIFEST);
    }

    function test_MainnetCanaryExecutionBoundaryAcceptsExactRealMainnetAck() public {
        vm.setEnv(
            "DF_MAINNET_CANARY_REAL_BROADCAST_ACK", "JPYDF_MAINNET_CANARY_REAL_MAINNET_BROADCAST_SEPARATELY_APPROVED"
        );
        harness.validateMainnetCanaryExecutionBoundaryForHarness();
    }

    function _validateCanary(
        string memory deploymentMode,
        string memory salt,
        string memory manifest,
        string memory ack,
        string memory canaryId,
        string memory broadcastPath,
        address expectedDeployer,
        string memory bridgeAdmin
    ) internal view {
        harness.validateMainnetCanaryGatesForHarness(
            deploymentMode, salt, manifest, ack, canaryId, broadcastPath, expectedDeployer, bridgeAdmin
        );
    }

    function test_Run_RevertsOnMainnetCanaryWithoutExplicitMinDebtAck() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: explicit canary MIN_DEBT ack required"));
        _validateCanary("complete", CANARY_SALT, CANARY_MANIFEST, "", CANARY_ID, CANARY_BROADCAST, address(this), "");
    }

    function test_Run_RevertsOnMainnetCanaryWithIncorrectMinDebtAck() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: explicit canary MIN_DEBT ack required"));
        _validateCanary(
            "complete", CANARY_SALT, CANARY_MANIFEST, "not-approved", CANARY_ID, CANARY_BROADCAST, address(this), ""
        );
    }

    function test_LegacyCanaryGateAcceptsExactMinDebtAck() public {
        vm.chainId(1);

        _validateCanary(
            "complete", CANARY_SALT, CANARY_MANIFEST, CANARY_ACK, CANARY_ID, CANARY_BROADCAST, address(this), ""
        );
    }

    function test_Run_MainnetCanaryRejectsNonCompleteMode() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: canary requires complete deployment"));
        _validateCanary(
            "jpydf-only", CANARY_SALT, CANARY_MANIFEST, CANARY_ACK, CANARY_ID, CANARY_BROADCAST, address(this), ""
        );
    }

    function test_Run_MainnetCanaryRejectsWrongCanaryId() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: exact canary id required"));
        _validateCanary(
            "complete", CANARY_SALT, CANARY_MANIFEST, CANARY_ACK, "wrong-canary", CANARY_BROADCAST, address(this), ""
        );
    }

    function test_Run_MainnetCanaryRejectsWrongSalt() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: exact canary salt required"));
        _validateCanary(
            "complete", "wrong-salt", CANARY_MANIFEST, CANARY_ACK, CANARY_ID, CANARY_BROADCAST, address(this), ""
        );
    }

    function test_Run_MainnetCanaryRejectsSharedManifestPath() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: isolated canary manifest path required"));
        _validateCanary(
            "complete",
            CANARY_SALT,
            "deployment-manifest.json",
            CANARY_ACK,
            CANARY_ID,
            CANARY_BROADCAST,
            address(this),
            ""
        );
    }

    function test_Run_MainnetCanaryRejectsSharedBroadcastPath() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: isolated canary broadcast path required"));
        _validateCanary("complete", CANARY_SALT, CANARY_MANIFEST, CANARY_ACK, CANARY_ID, "broadcast", address(this), "");
    }

    function test_Run_MainnetCanaryRejectsWrongExpectedDeployer() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: canary deployer confirmation mismatch"));
        _validateCanary(
            "complete",
            CANARY_SALT,
            CANARY_MANIFEST,
            CANARY_ACK,
            CANARY_ID,
            CANARY_BROADCAST,
            makeAddr("wrongCanaryDeployer"),
            ""
        );
    }

    function test_Run_MainnetCanaryRejectsConfiguredBridgeAdmin() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DeployLiquity2: canary bridge admin must be inert"));
        _validateCanary(
            "complete",
            CANARY_SALT,
            CANARY_MANIFEST,
            CANARY_ACK,
            CANARY_ID,
            CANARY_BROADCAST,
            address(this),
            vm.toString(address(harness))
        );
    }

    function test_MainnetCanaryBridgeAdminHasNoCallableSurface() public {
        address canaryBridgeAdmin = address(new MainnetCanaryBridgeAdmin());
        assertGt(canaryBridgeAdmin.code.length, 0, "canary bridge admin must be a contract");
        (bool success,) = canaryBridgeAdmin.call(hex"deadbeef");
        assertFalse(success, "canary bridge admin must expose no callable fallback");
    }

    function test_ManifestClassifiesLocalBuildAsTestOnly() public view {
        assertEq(harness.deploymentClassificationForHarness(), "TEST_ONLY_NOT_FOR_PRODUCTION");
    }

    function test_ManifestClassifiesSepoliaBuildAsTestOnly() public {
        vm.chainId(SEPOLIA_CHAIN_ID);
        assertEq(harness.deploymentClassificationForHarness(), "TEST_ONLY_NOT_FOR_PRODUCTION");
    }

    function test_ManifestClassifiesMainnetBuildAsProductionCandidate() public {
        vm.chainId(1);
        assertEq(harness.deploymentClassificationForHarness(), "PRODUCTION_CANDIDATE");
    }

    function test_ManifestIncludesProductionIdentityMetadata() public {
        vm.chainId(1);
        vm.setEnv("DF_MAINNET_CANARY_ID", CANARY_ID);
        harness.setHarnessSalt(keccak256(bytes(CANARY_SALT)));
        string memory manifest = harness.deploymentMetadataForHarness("complete", '{"tail":true}');

        assertEq(vm.parseJsonString(manifest, ".deploymentClassification"), "PRODUCTION_CANDIDATE", "classification");
        assertEq(vm.parseJsonString(manifest, ".deploymentProfile"), "production-candidate", "profile");
        assertEq(vm.parseJsonString(manifest, ".deploymentId"), "jpydf-production-candidate", "deployment id");
        assertEq(abi.decode(vm.parseJson(manifest, ".chainId"), (uint256)), 1, "chain id");
        assertEq(vm.parseJsonString(manifest, ".deploymentMode"), "complete", "mode");
        assertEq(vm.parseJsonString(manifest, ".create2Salt"), vm.toString(keccak256(bytes(CANARY_SALT))), "salt");
        assertEq(vm.parseJsonAddress(manifest, ".deployer"), address(this), "deployer");
    }

    function test_ConfigureBaseTokens_UsesAaveUsdcOnSepolia() public {
        address aaveUsdc = harness.sepoliaUsdcAddressForHarness();
        vm.chainId(11155111);
        vm.etch(aaveUsdc, hex"00");
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(6)));
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode("USDC"));

        (IWETH wethToken, IERC20Metadata usdcToken) = harness.configureBaseTokensForHarness();

        assertTrue(address(wethToken).code.length != 0, "Sepolia gas-comp WETH deployed");
        assertEq(address(usdcToken), aaveUsdc, "Aave Sepolia USDC selected");
    }

    function test_ConfigureBaseTokens_KeepsLocalUsdcOnAnvil() public {
        (IWETH wethToken, IERC20Metadata usdcToken) = harness.configureBaseTokensForHarness();

        assertTrue(address(wethToken).code.length != 0, "local WETH deployed");
        assertTrue(address(usdcToken).code.length != 0, "local USDC deployed");
        assertNotEq(address(usdcToken), harness.sepoliaUsdcAddressForHarness(), "Aave USDC not bound on Anvil");
        assertEq(usdcToken.decimals(), 6, "local USDC decimals");
    }

    function test_ConfigureBaseTokens_RejectsUnexpectedSepoliaUsdcMetadata() public {
        address aaveUsdc = harness.sepoliaUsdcAddressForHarness();
        vm.chainId(11155111);
        vm.etch(aaveUsdc, hex"00");
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));

        vm.expectRevert(bytes("DeployLiquity2: Sepolia USDC decimals"));
        harness.configureBaseTokensForHarness();
    }

    function test_ConfigureBaseTokens_RejectsUnexpectedSepoliaUsdcSymbol() public {
        address aaveUsdc = harness.sepoliaUsdcAddressForHarness();
        vm.chainId(11155111);
        vm.etch(aaveUsdc, hex"00");
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(6)));
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode("USDT"));

        vm.expectRevert(bytes("DeployLiquity2: Sepolia USDC symbol"));
        harness.configureBaseTokensForHarness();
    }

    function test_SepoliaLidoPreflightAcceptsCanonicalLiveShape() public {
        _installSepoliaLidoMocks(SEPOLIA_LIDO_STETH, 1.04e18, false, false, 1_000e18);

        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsNoncanonicalAddresses() public {
        vm.chainId(SEPOLIA_CHAIN_ID);

        vm.expectRevert(bytes("DF: noncanonical Sepolia Lido wstETH"));
        harness.validateSepoliaLidoWiringForHarness(makeAddr("notCanonicalWstEth"), SEPOLIA_LIDO_STETH);

        vm.expectRevert(bytes("DF: noncanonical Sepolia Lido stETH"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, makeAddr("notCanonicalStEth"));
    }

    function test_SepoliaLidoPreflightRejectsLinkedStEthMismatch() public {
        _installSepoliaLidoMocks(makeAddr("unexpectedLinkedStEth"), 1.04e18, false, false, 1_000e18);

        vm.expectRevert(bytes("DF: Sepolia Lido stETH mismatch"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsZeroRate() public {
        _installSepoliaLidoMocks(SEPOLIA_LIDO_STETH, 0, false, false, 1_000e18);

        vm.expectRevert(bytes("DF: Sepolia Lido wstETH rate is zero"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsPausedStaking() public {
        _installSepoliaLidoMocks(SEPOLIA_LIDO_STETH, 1.04e18, true, false, 1_000e18);

        vm.expectRevert(bytes("DF: Sepolia Lido staking is paused"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsStoppedProtocol() public {
        _installSepoliaLidoMocks(SEPOLIA_LIDO_STETH, 1.04e18, false, true, 1_000e18);

        vm.expectRevert(bytes("DF: Sepolia Lido is stopped"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsExhaustedStakeLimit() public {
        _installSepoliaLidoMocks(SEPOLIA_LIDO_STETH, 1.04e18, false, false, 0);

        vm.expectRevert(bytes("DF: Sepolia Lido stake limit exhausted"));
        harness.validateSepoliaLidoWiringForHarness(SEPOLIA_LIDO_WSTETH, SEPOLIA_LIDO_STETH);
    }

    function test_SepoliaLidoPreflightRejectsOtherChains() public {
        vm.expectRevert(bytes("DeployLiquity2: Sepolia Lido preflight requires chain 11155111"));
        harness.validateSepoliaLidoWiring();
    }

    function test_LocalNativeEthRouteResolvesLinkedStEthOnlyForBranchZero() public {
        LocalStETH stEth = new LocalStETH();
        LocalWstETH wstEth = new LocalWstETH(stEth, 100e18, 1 days);

        assertEq(
            harness.resolveZapperExpectedStEthForHarness(IERC20(address(wstEth)), 0, address(0), true),
            address(stEth),
            "local branch zero stETH"
        );
        assertEq(
            harness.resolveZapperExpectedStEthForHarness(IERC20(address(wstEth)), 1, address(0), true),
            address(0),
            "other branch disabled"
        );
        assertEq(
            harness.resolveZapperExpectedStEthForHarness(IERC20(address(wstEth)), 0, address(0), false),
            address(0),
            "explicit local gate off"
        );

        vm.chainId(1);
        assertEq(
            harness.resolveZapperExpectedStEthForHarness(IERC20(address(wstEth)), 0, address(0), true),
            address(0),
            "mainnet remains explicitly configured"
        );

        address configuredStEth = makeAddr("configuredStEth");
        assertEq(
            harness.resolveZapperExpectedStEthForHarness(IERC20(address(wstEth)), 0, configuredStEth, true),
            configuredStEth,
            "configured address takes precedence"
        );
    }

    function test_ProductionMainnetNativeEthRouteRequiresExactOwnerManifestValues() public {
        vm.chainId(1);
        (address expectedStEth, address lidoReferral) = harness.day1NativeEthRouteForHarness();
        assertEq(lidoReferral, 0x57af3a60314cD24032a4435b715f4dC8eb5967F0, "frozen referral");

        harness.validateProductionNativeEthRouteForHarness(0, expectedStEth, lidoReferral, false);

        vm.expectRevert(bytes("DF: mainnet stETH differs from Day-1 owner manifest"));
        harness.validateProductionNativeEthRouteForHarness(0, address(0), lidoReferral, false);

        vm.expectRevert(bytes("DF: mainnet Lido referral differs from Day-1 owner manifest"));
        harness.validateProductionNativeEthRouteForHarness(0, expectedStEth, address(0), false);
    }

    function test_ProductionNativeEthRouteGateDoesNotApplyOutsideMainnetBranchZero() public {
        harness.validateProductionNativeEthRouteForHarness(0, address(0), address(0), false);

        vm.chainId(1);
        harness.validateProductionNativeEthRouteForHarness(1, address(0), address(0), false);
        harness.validateProductionNativeEthRouteForHarness(0, address(0), address(0), true);

        vm.expectRevert(bytes("DF: unexpected mainnet branch Lido referral"));
        harness.validateProductionNativeEthRouteForHarness(1, address(0), makeAddr("unexpectedReferral"), false);
    }

    function _installSepoliaLidoMocks(address linkedStEth, uint256 rate, bool paused, bool stopped, uint256 stakeLimit)
        internal
    {
        vm.chainId(SEPOLIA_CHAIN_ID);
        SelectorSepoliaLidoWstEthMock wstEthMock = new SelectorSepoliaLidoWstEthMock(linkedStEth, rate);
        SelectorSepoliaLidoStEthMock stEthMock = new SelectorSepoliaLidoStEthMock(paused, stopped, stakeLimit);
        vm.etch(SEPOLIA_LIDO_WSTETH, address(wstEthMock).code);
        vm.etch(SEPOLIA_LIDO_STETH, address(stEthMock).code);
    }

    function test_MainnetDay1StrategyPolicyRequiresNoStrategyOnBranchZero() public {
        vm.setEnv("DF_STRATEGY_KIND_0", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_0", "0");
        vm.setEnv("DF_STRATEGY_CAP_0", "0");

        harness.requireMainnetDay1StrategyPolicyForHarness(0);

        vm.setEnv("DF_STRATEGY_KIND_0", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_0", "10000");
        vm.setEnv("DF_STRATEGY_CAP_0", "1");
        vm.expectRevert(bytes("DF: Day-1 branch strategies disabled"));
        harness.requireMainnetDay1StrategyPolicyForHarness(0);
    }

    function test_MainnetDay1StrategyPolicyRejectsAdditionalERC4626OnBranchOne() public {
        uint256 stableBranch = 28;
        vm.setEnv("DF_STRATEGY_COUNT_28", "3");
        _setStrategyArrayEnv(stableBranch, 0, "aave", 4_000);
        _setStrategyArrayEnv(stableBranch, 1, "morpho-v2", 3_000);
        _setStrategyArrayEnv(stableBranch, 2, "erc4626", 3_000);

        vm.expectRevert(bytes("DF: strategy outside Day-1 scope erc4626"));
        harness.requireMainnetDay1StableStrategySetForHarness(stableBranch);
    }

    function test_MainnetDay1StrategyPolicyAcceptsPlannedActiveSet() public {
        uint256 stableBranch = 24;
        vm.setEnv("DF_STRATEGY_COUNT_24", "2");
        _setStrategyArrayEnv(stableBranch, 0, "aave", 5_000);
        _setStrategyArrayEnv(stableBranch, 1, "morpho-v2", 5_000);

        vm.setEnv("DF_STRATEGY_KIND_2", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_2", "0");
        vm.setEnv("DF_STRATEGY_CAP_2", "0");

        harness.requireMainnetDay1StableStrategySetForHarness(stableBranch);
        harness.requireMainnetDay1StrategyPolicyForHarness(2);
    }

    function test_MainnetCanaryStrategyPolicyAcceptsPinnedGauntletUsdcPrime() public {
        uint256 stableBranch = 29;
        _setMainnetCanaryStrategyEnv(stableBranch, "0xdd0f28e19C1780eb6396170735D45153D261490d", 100_000_000);

        harness.requireMainnetCanaryStableStrategySetForHarness(stableBranch);
    }

    function test_MainnetCanaryStrategyPolicyRejectsUnpinnedVault() public {
        uint256 stableBranch = 30;
        _setMainnetCanaryStrategyEnv(stableBranch, vm.toString(makeAddr("notGauntlet")), 100_000_000);

        vm.expectRevert(bytes("DF: canary requires Gauntlet USDC Prime"));
        harness.requireMainnetCanaryStableStrategySetForHarness(stableBranch);
    }

    function test_MainnetCanaryStrategyPolicyRejectsCapAboveOneHundredUsdc() public {
        uint256 stableBranch = 31;
        _setMainnetCanaryStrategyEnv(stableBranch, "0xdd0f28e19C1780eb6396170735D45153D261490d", 100_000_001);

        vm.expectRevert(bytes("DF: canary strategy cap exceeds 100 USDC"));
        harness.requireMainnetCanaryStableStrategySetForHarness(stableBranch);
    }

    function test_MainnetDay1StrategyPolicyRejectsCandidateKind() public {
        uint256 stableBranch = 25;
        vm.setEnv("DF_STRATEGY_COUNT_25", "2");
        _setStrategyArrayEnv(stableBranch, 0, "aave", 5_000);
        _setStrategyArrayEnv(stableBranch, 1, "sky-susds", 5_000);

        vm.expectRevert(bytes("DF: strategy outside Day-1 scope sky-susds"));
        harness.requireMainnetDay1StableStrategySetForHarness(stableBranch);
    }

    function test_MainnetDay1StrategyPolicyRejectsDroppedStakingKinds() public {
        uint256 stakingBranch = 27;
        vm.setEnv("DF_STRATEGY_COUNT_27", "2");
        _setStrategyArrayEnv(stakingBranch, 0, "aave", 5_000);
        _setStrategyArrayEnv(stakingBranch, 1, "lido", 5_000);

        vm.expectRevert(bytes("DF: strategy outside Day-1 scope lido"));
        harness.requireMainnetDay1StableStrategySetForHarness(stakingBranch);

        _setStrategyArrayEnv(stakingBranch, 1, "etherfi-weeth", 5_000);
        vm.expectRevert(bytes("DF: strategy outside Day-1 scope etherfi-weeth"));
        harness.requireMainnetDay1StableStrategySetForHarness(stakingBranch);
    }

    function test_Run_EnvFlagParsesFalseStringsAsFalse() public {
        string memory key = "DF_TEST_ENV_FLAG_PARSE";
        vm.setEnv(key, "0");
        assertFalse(harness.envFlagForHarness(key), "zero string");

        vm.setEnv(key, "false");
        assertFalse(harness.envFlagForHarness(key), "false string");

        vm.setEnv(key, "true");
        assertTrue(harness.envFlagForHarness(key), "true string");
    }

    function test_DeployYieldLayer_InitializesDTokenAndVaultThroughAtomicHelper() public {
        harness.setHarnessDeployer(address(harness));
        MockERC20 underlyingToken = new MockERC20("Underlying", "UND", 6);

        (DToken dToken, CollateralVault collateralVault) =
            harness.deployYieldLayerForHarness(IERC20Metadata(address(underlyingToken)), "dUnderlying", "dUND");

        assertEq(dToken.owner(), address(harness), "dToken owner accepted");
        assertEq(dToken.pendingOwner(), address(0), "dToken pending owner cleared");
        assertEq(dToken.vault(), address(collateralVault), "dToken vault");
        assertEq(address(dToken.underlying()), address(underlyingToken), "dToken underlying");
        assertTrue(dToken.allowedUnderlying(address(underlyingToken)), "underlying allowlisted");
        assertEq(dToken.name(), "dUnderlying", "dToken name");
        assertEq(dToken.symbol(), "dUND", "dToken symbol");
        assertEq(dToken.underlyingDecimals(), 6, "underlying decimals");
        assertEq(dToken.cap(), 0, "active cap remains frozen before handover");

        assertEq(address(collateralVault.dToken()), address(dToken), "vault dToken");
        assertEq(address(collateralVault.underlying()), address(underlyingToken), "vault underlying");
        assertEq(collateralVault.treasury(), treasury, "vault treasury");
        assertTrue(collateralVault.hasRole(GOV_ROLE, address(harness)), "vault gov role");

        address depositor = makeAddr("preHandoverDepositor");
        underlyingToken.mint(depositor, 1e6);
        vm.startPrank(depositor);
        underlyingToken.approve(address(collateralVault), 1e6);
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        collateralVault.deposit(1e6);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(depositor), 1e6, "failed deposit returns underlying");
        assertEq(underlyingToken.balanceOf(address(collateralVault)), 0, "vault remains empty");
        assertEq(dToken.totalSupply(), 0, "failed deposit cannot mint");
    }

    function test_DeployYieldLayer_InitializesInertBranchWithZeroCapAndFailClosedVault() public {
        harness.setHarnessDeployer(address(harness));

        (DToken dToken, CollateralVault collateralVault) =
            harness.deployYieldLayerForHarness(IERC20Metadata(address(0)), "unused", "unused");

        assertEq(dToken.owner(), address(harness), "dToken owner accepted");
        assertEq(dToken.pendingOwner(), address(0), "dToken pending owner cleared");
        assertEq(dToken.vault(), address(collateralVault), "dToken vault");
        assertEq(address(dToken.underlying()), address(0), "inert dToken has no underlying");
        assertEq(dToken.cap(), 0, "inert cap");
        assertEq(dToken.name(), "DToken Placeholder", "placeholder name");
        assertEq(dToken.symbol(), "dTOKEN", "placeholder symbol");

        assertEq(address(collateralVault.dToken()), address(dToken), "vault dToken");
        assertEq(address(collateralVault.underlying()), address(0), "inert vault has no underlying");
        assertEq(collateralVault.treasury(), treasury, "vault treasury");

        vm.expectRevert(DToken.TokenInfoNotSet.selector);
        dToken.convertToDToken(1);

        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        collateralVault.deposit(1);
    }

    function test_UUPSImplementationsRejectDirectInitialization() public {
        DToken dTokenImpl = new DToken();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        dTokenImpl.initialize(address(0x1001), address(this));

        CollateralVault vaultImpl = new CollateralVault();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        vaultImpl.initialize(IERC20(address(0x2001)), IDToken(address(0x2002)), treasury, address(this));

        AaveV3Strategy aaveImpl = new AaveV3Strategy();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        aaveImpl.initialize(
            address(0x3001),
            IERC20(address(0x3002)),
            address(this),
            address(this),
            IAaveV3Pool(address(0x3003)),
            IAToken(address(0x3004))
        );

        ERC4626Strategy erc4626Impl = new ERC4626Strategy();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        erc4626Impl.initialize(
            address(0x4001), IERC20(address(0x4002)), address(this), address(this), IERC4626(address(0x4003))
        );

        MorphoV2Strategy morphoImpl = new MorphoV2Strategy();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        morphoImpl.initialize(
            address(0x5001), IERC20(address(0x5002)), address(this), address(this), IMorphoVaultV2(address(0x5003)), 200
        );

        SkyUsdcSUsdsStrategy skyImpl = new SkyUsdcSUsdsStrategy();
        vm.expectRevert(bytes(INITIALIZABLE_ALREADY_INITIALIZED));
        skyImpl.initialize(
            address(0x7001),
            IERC20(address(0x7002)),
            address(this),
            address(this),
            IERC20(address(0x7003)),
            IERC4626(address(0x7004)),
            ISkyUsdcSUsdsConverter(address(0x7005)),
            1
        );
    }

    function test_DeploySelector_DeploysAndRegistersERC4626Strategy() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        SelectorMockERC4626Vault erc4626Vault = new SelectorMockERC4626Vault(IERC20(address(underlyingToken)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        uint256 branchIndex = 8;
        vm.setEnv("DF_STRATEGY_KIND_8", "erc4626");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_8", "10000");
        vm.setEnv("DF_STRATEGY_CAP_8", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_ERC4626_VAULT_8", vm.toString(address(erc4626Vault)));

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));

        assertEq(collateralVault.getStrategiesCount(), 1, "registered");
        assertEq(address(collateralVault.strategies(0)), address(strategy), "strategy slot");
        assertEq(strategy.underlying(), address(underlyingToken), "underlying");
    }

    function test_DeploySelector_RevertsWhenERC4626VaultHasNoCode() public {
        uint256 branchIndex = 21;
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_21", "erc4626");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_21", "10000");
        vm.setEnv("DF_STRATEGY_CAP_21", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_ERC4626_VAULT_21", vm.toString(makeAddr("codelessERC4626Vault")));

        vm.expectRevert(bytes("DF: codeless DF_STRATEGY_ERC4626_VAULT_21"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_DeploysLocalAaveVenueOffMainnet() public {
        uint256 branchIndex = 11;
        vm.chainId(31337);
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_11", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_11", "10000");
        vm.setEnv("DF_STRATEGY_CAP_11", vm.toString(type(uint256).max));

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
        AaveV3Strategy aaveStrategy = AaveV3Strategy(address(strategy));

        assertEq(collateralVault.getStrategiesCount(), 1, "registered");
        assertEq(address(collateralVault.strategies(0)), address(strategy), "strategy slot");
        assertEq(strategy.underlying(), address(underlyingToken), "underlying");
        assertTrue(address(aaveStrategy.aavePool()).code.length != 0, "local pool deployed");
        assertEq(aaveStrategy.aToken().UNDERLYING_ASSET_ADDRESS(), address(underlyingToken), "local aToken");
    }

    function test_DeploySelector_UsesLiveAaveVenueOnSepolia() public {
        uint256 branchIndex = 30;
        address aaveUsdc = harness.sepoliaUsdcAddressForHarness();
        address aavePool = harness.sepoliaAavePoolAddressForHarness();
        address aaveAToken = harness.sepoliaAaveATokenAddressForHarness();
        MockERC20 codeSource = new MockERC20("USDC", "USDC", 6);

        vm.chainId(11155111);
        vm.etch(aaveUsdc, address(codeSource).code);
        vm.etch(aavePool, hex"00");
        vm.etch(aaveAToken, hex"00");
        vm.mockCall(aaveUsdc, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(6)));
        vm.mockCall(aaveAToken, abi.encodeCall(IAToken.UNDERLYING_ASSET_ADDRESS, ()), abi.encode(aaveUsdc));

        CollateralVault collateralVault = _deployVault(IERC20Metadata(aaveUsdc));
        vm.setEnv("DF_STRATEGY_KIND_30", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_30", "10000");
        vm.setEnv("DF_STRATEGY_CAP_30", vm.toString(type(uint256).max));

        AaveV3Strategy strategy = AaveV3Strategy(
            address(harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(aaveUsdc)))
        );

        assertEq(address(strategy.aavePool()), aavePool, "live Sepolia Aave Pool selected");
        assertEq(address(strategy.aToken()), aaveAToken, "live Sepolia aUSDC selected");
        assertEq(strategy.underlying(), aaveUsdc, "Aave Faucet USDC selected");
    }

    function test_DeploySelector_RejectsOtherAaveUnderlyingOnSepolia() public {
        uint256 branchIndex = 31;
        vm.chainId(11155111);
        MockERC20 underlyingToken = new MockERC20("Other USDC", "USDC", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_31", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_31", "10000");
        vm.setEnv("DF_STRATEGY_CAP_31", vm.toString(type(uint256).max));

        vm.expectRevert(bytes("DF: unsupported Sepolia Aave underlying"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_LocalAaveRoundTripSupportsSixDecimalUsdc() public {
        uint256 branchIndex = 29;
        uint256 depositAmount = 10e6;
        MockERC20 underlyingToken = new MockERC20("USDC", "USDC", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_29", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_29", "10000");
        vm.setEnv("DF_STRATEGY_CAP_29", vm.toString(type(uint256).max));

        AaveV3Strategy strategy = AaveV3Strategy(
            address(
                harness.deployAndRegisterStrategy(
                    branchIndex, collateralVault, IERC20Metadata(address(underlyingToken))
                )
            )
        );

        underlyingToken.mint(address(this), depositAmount);
        underlyingToken.approve(address(collateralVault), depositAmount);
        uint256 dTokenAmount = collateralVault.deposit(depositAmount);
        collateralVault.allocate();

        uint256 allocated = strategy.principal();
        assertEq(dTokenAmount, 10e18, "six-decimal USDC converts to 18-decimal dUSDC");
        assertEq(allocated, 8e6, "default 20 percent buffer retained");
        assertEq(underlyingToken.balanceOf(address(strategy.aToken())), allocated, "USDC held by local aToken");
        assertEq(strategy.aToken().balanceOf(address(strategy)), allocated, "aToken position minted");

        assertEq(strategy.sendToVault(allocated), allocated, "Aave position returned to Vault");
        assertEq(strategy.principal(), 0, "strategy principal cleared");
        assertEq(underlyingToken.balanceOf(address(collateralVault)), depositAmount, "USDC buffer restored");

        (uint256 redeemed, uint256 requestId) = collateralVault.redeem(dTokenAmount, address(this));
        assertEq(redeemed, depositAmount, "USDC round trip redeemed exactly");
        assertEq(requestId, 0, "no delayed withdrawal");
        assertEq(underlyingToken.balanceOf(address(this)), depositAmount, "USDC returned to depositor");
    }

    function test_DeploySelector_UsesConfiguredAaveVenueOnMainnet() public {
        uint256 branchIndex = 12;
        vm.chainId(1);
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));
        LocalAavePool pool = new LocalAavePool();
        LocalAToken aToken = new LocalAToken(address(pool), address(underlyingToken));
        pool.setAsset(IERC20(address(underlyingToken)));
        pool.setAToken(aToken);

        vm.setEnv("DF_STRATEGY_KIND_12", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_12", "10000");
        vm.setEnv("DF_STRATEGY_CAP_12", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_AAVE_POOL_12", vm.toString(address(pool)));
        vm.setEnv("DF_STRATEGY_AAVE_ATOKEN_12", vm.toString(address(aToken)));

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
        AaveV3Strategy aaveStrategy = AaveV3Strategy(address(strategy));

        assertEq(address(aaveStrategy.aavePool()), address(pool), "configured pool");
        assertEq(address(aaveStrategy.aToken()), address(aToken), "configured aToken");
    }

    function test_DeploySelector_RevertsWhenMainnetAavePoolHasNoCode() public {
        uint256 branchIndex = 7;
        vm.chainId(1);
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_7", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_7", "10000");
        vm.setEnv("DF_STRATEGY_CAP_7", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_AAVE_POOL_7", vm.toString(makeAddr("codelessPool")));
        vm.setEnv("DF_STRATEGY_AAVE_ATOKEN_7", vm.toString(makeAddr("codelessAToken")));

        vm.expectRevert(bytes("DF: codeless DF_STRATEGY_AAVE_POOL_7"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_DeploysAndRegistersMorphoV2Strategy() public {
        uint256 branchIndex = 13;
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 6);
        MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(underlyingToken)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_13", "morpho-v2");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_13", "10000");
        vm.setEnv("DF_STRATEGY_CAP_13", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_MORPHOV2_VAULT_13", vm.toString(address(morphoVault)));
        vm.setEnv("DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_13", "150");

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
        MorphoV2Strategy morphoStrategy = MorphoV2Strategy(address(strategy));

        assertEq(collateralVault.getStrategiesCount(), 1, "registered");
        assertEq(address(collateralVault.strategies(0)), address(strategy), "strategy slot");
        assertEq(strategy.underlying(), address(underlyingToken), "underlying");
        assertEq(address(morphoStrategy.morphoVault()), address(morphoVault), "morpho vault");
        assertEq(morphoStrategy.maxForceDeallocatePenaltyBps(), 150, "penalty bound");
    }

    function test_DeploySelector_MorphoV2PenaltyDefaultsToProtocolMax() public {
        uint256 branchIndex = 14;
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 6);
        MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(underlyingToken)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_14", "morpho-v2");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_14", "10000");
        vm.setEnv("DF_STRATEGY_CAP_14", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_MORPHOV2_VAULT_14", vm.toString(address(morphoVault)));

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));

        assertEq(MorphoV2Strategy(address(strategy)).maxForceDeallocatePenaltyBps(), 200, "default penalty bound");
    }

    function test_DeploySelector_RevertsWhenMorphoV2PenaltyAboveProtocolMax() public {
        uint256 branchIndex = 15;
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 6);
        MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(underlyingToken)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_15", "morpho-v2");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_15", "10000");
        vm.setEnv("DF_STRATEGY_CAP_15", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_MORPHOV2_VAULT_15", vm.toString(address(morphoVault)));
        vm.setEnv("DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_15", "201");

        vm.expectRevert(bytes("DF: morpho-v2 penalty > 200 bps"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_RevertsWhenMorphoV2VaultHasNoCode() public {
        uint256 branchIndex = 22;
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_22", "morpho-v2");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_22", "10000");
        vm.setEnv("DF_STRATEGY_CAP_22", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_MORPHOV2_VAULT_22", vm.toString(makeAddr("codelessMorphoVault")));

        vm.expectRevert(bytes("DF: codeless DF_STRATEGY_MORPHOV2_VAULT_22"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_DeploysMultipleStrategiesForOneBranch() public {
        uint256 branchIndex = 3;
        address jpyUsdRateProvider = makeAddr("jpyUsdRateProvider");
        harness.setDfOracleFreezeForHarness(makeAddr("jpyUsdFeed"), 72 hours, jpyUsdRateProvider);
        WETH9 weth = new WETH9();
        harness.setHarnessWETH(IWETH(address(weth)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(weth)));
        MockMorphoV2Vault morphoVault = new MockMorphoV2Vault(IERC20(address(weth)));

        vm.setEnv("DF_STRATEGY_COUNT_3", "2");
        vm.setEnv("DF_STRATEGY_KIND_3_0", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_3_0", "5000");
        vm.setEnv("DF_STRATEGY_CAP_3_0", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_KIND_3_1", "morpho-v2");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_3_1", "5000");
        vm.setEnv("DF_STRATEGY_CAP_3_1", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_MORPHOV2_VAULT_3_1", vm.toString(address(morphoVault)));
        vm.setEnv("DF_STRATEGY_MORPHOV2_MAX_PENALTY_BPS_3_1", "200");

        IStrategy primaryStrategy =
            harness.deployAndRegisterStrategies(branchIndex, collateralVault, IERC20Metadata(address(weth)));

        assertEq(collateralVault.getStrategiesCount(), 2, "registered");
        assertEq(address(collateralVault.strategies(0)), address(primaryStrategy), "primary strategy");
        assertEq(collateralVault.totalWeightBps(), 10_000, "total weight");
        assertEq(primaryStrategy.underlying(), address(weth), "primary underlying");
        assertEq(IStrategy(address(collateralVault.strategies(1))).underlying(), address(weth), "secondary underlying");

        string memory dfYieldJson =
            harness.dfYieldJsonForHarness(branchIndex, collateralVault, IERC20Metadata(address(weth)));
        assertFalse(vm.keyExistsJson(dfYieldJson, ".strategy"), "no legacy primary strategy");
        assertFalse(vm.keyExistsJson(dfYieldJson, ".strategyKind"), "no legacy primary strategy kind");
        assertFalse(vm.keyExistsJson(dfYieldJson, ".strategyWeightBps"), "no legacy primary weight");
        assertFalse(vm.keyExistsJson(dfYieldJson, ".strategyCap"), "no legacy primary cap");
        assertEq(vm.parseJsonAddress(dfYieldJson, ".strategies[0].strategy"), address(primaryStrategy), "array first");
        assertEq(
            vm.parseJsonAddress(dfYieldJson, ".strategies[1].strategy"),
            address(collateralVault.strategies(1)),
            "array second"
        );
        assertEq(vm.parseJsonString(dfYieldJson, ".strategies[1].strategyKind"), "morpho-v2", "array kind");
        assertEq(
            vm.parseJsonAddress(dfYieldJson, ".jpyUsdRateProvider"),
            jpyUsdRateProvider,
            "shared provider manifest evidence"
        );
    }

    function test_DeploySelector_RevertsWhenNoneIsUsedInsideStrategyArray() public {
        uint256 branchIndex = 6;
        WETH9 weth = new WETH9();
        harness.setHarnessWETH(IWETH(address(weth)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(weth)));

        vm.setEnv("DF_STRATEGY_COUNT_6", "2");
        vm.setEnv("DF_STRATEGY_KIND_6_0", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_6_0", "0");
        vm.setEnv("DF_STRATEGY_CAP_6_0", "0");
        vm.setEnv("DF_STRATEGY_KIND_6_1", "aave");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_6_1", "10000");
        vm.setEnv("DF_STRATEGY_CAP_6_1", vm.toString(type(uint256).max));

        vm.expectRevert(bytes("DF: array strategy none"));
        harness.deployAndRegisterStrategies(branchIndex, collateralVault, IERC20Metadata(address(weth)));
    }

    function test_DeploySelector_DeploysSkyUsdcSUsdsStrategy() public {
        uint256 branchIndex = 1;
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 usds = new MockERC20("Mock USDS", "mUSDS", 18);
        SelectorMockERC4626Vault susdsVault = new SelectorMockERC4626Vault(IERC20(address(usds)));
        SelectorMockSkyPsmWrapper psmWrapper =
            new SelectorMockSkyPsmWrapper(IERC20(address(usdc)), IERC20(address(usds)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(usdc)));
        harness.setHarnessUSDC(IERC20Metadata(address(usdc)));

        _setSkyBranchOneStrategyEnv(address(usds), address(susdsVault), address(psmWrapper));

        IStrategy strategy =
            harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(usdc)));

        assertEq(collateralVault.getStrategiesCount(), 1, "registered");
        assertEq(address(collateralVault.strategies(0)), address(strategy), "strategy slot");
        assertEq(strategy.underlying(), address(usdc), "underlying");
        ISkyUsdcSUsdsConverter deployedConverter = SkyUsdcSUsdsStrategy(address(strategy)).converter();
        assertEq(address(deployedConverter.psmWrapper()), address(psmWrapper), "first-party converter wrapper");
        assertTrue(address(deployedConverter) != address(psmWrapper), "wrapper is not injected as converter");
    }

    function test_DeploySelector_RevertsWhenSkyStrategyIsNotDUsdcBranch() public {
        uint256 branchIndex = 16;
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 usds = new MockERC20("Mock USDS", "mUSDS", 18);
        SelectorMockERC4626Vault susdsVault = new SelectorMockERC4626Vault(IERC20(address(usds)));
        SelectorMockSkyPsmWrapper psmWrapper =
            new SelectorMockSkyPsmWrapper(IERC20(address(usdc)), IERC20(address(usds)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(usdc)));
        harness.setHarnessUSDC(IERC20Metadata(address(usdc)));

        vm.setEnv("DF_STRATEGY_KIND_16", "sky-susds");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_16", "10000");
        vm.setEnv("DF_STRATEGY_CAP_16", vm.toString(type(uint256).max));
        vm.setEnv("DF_STRATEGY_SKY_USDS_16", vm.toString(address(usds)));
        vm.setEnv("DF_STRATEGY_SKY_SUSDS_VAULT_16", vm.toString(address(susdsVault)));
        vm.setEnv("DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_16", vm.toString(address(psmWrapper)));
        vm.setEnv("DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_16", "50");

        vm.expectRevert(bytes("DF: Sky strategy requires dUSDC branch"));
        harness.deployAndRegisterStrategy(branchIndex, collateralVault, IERC20Metadata(address(usdc)));
    }

    function test_DeploySelector_RevertsWhenSkyStrategyUnderlyingIsNotUSDC() public {
        uint256 branchIndex = 1;
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 usdt = new MockERC20("Mock USDT", "mUSDT", 6);
        MockERC20 usds = new MockERC20("Mock USDS", "mUSDS", 18);
        SelectorMockERC4626Vault susdsVault = new SelectorMockERC4626Vault(IERC20(address(usds)));
        SelectorMockSkyPsmWrapper psmWrapper =
            new SelectorMockSkyPsmWrapper(IERC20(address(usdc)), IERC20(address(usds)));
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(usdt)));
        harness.setHarnessUSDC(IERC20Metadata(address(usdc)));

        uint256 strategyIndex = 1;
        _setSkyBranchStrategyEnv(strategyIndex, address(usds), address(susdsVault), address(psmWrapper));

        vm.expectRevert(bytes("DF: Sky strategy requires USDC"));
        harness.deployAndRegisterStrategyAtIndex(
            branchIndex, strategyIndex, collateralVault, IERC20Metadata(address(usdt))
        );
    }

    function test_DeploySelector_RevertsWhenSkyVenueHasNoCode() public {
        uint256 branchIndex = 1;
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(usdc)));
        harness.setHarnessUSDC(IERC20Metadata(address(usdc)));

        MockERC20 usds = new MockERC20("Mock USDS", "mUSDS", 18);
        SelectorMockERC4626Vault susdsVault = new SelectorMockERC4626Vault(IERC20(address(usds)));
        SelectorMockSkyPsmWrapper psmWrapper =
            new SelectorMockSkyPsmWrapper(IERC20(address(usdc)), IERC20(address(usds)));

        address codelessUsds = address(0x000000000000000000000000000000000000dEaD);
        assertEq(codelessUsds.code.length, 0, "codeless USDS fixture");
        uint256 strategyIndex = 2;
        _setSkyBranchStrategyEnv(strategyIndex, codelessUsds, address(susdsVault), address(psmWrapper));

        vm.expectRevert(bytes("DF: codeless DF_STRATEGY_SKY_USDS_1_2"));
        harness.deployAndRegisterStrategyAtIndex(
            branchIndex, strategyIndex, collateralVault, IERC20Metadata(address(usdc))
        );
    }

    function test_DeploySelector_RevertsOnUnknownStrategyKind() public {
        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_17", "unknown");

        vm.expectRevert(bytes("DF: unknown strategy kind unknown"));
        harness.deployAndRegisterStrategy(17, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_SkipsRegistrationForNoneStrategyWithZeroConfig() public {
        MockERC20 underlyingToken = new MockERC20("Mock XAUT", "mXAUT", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_18", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_18", "0");
        vm.setEnv("DF_STRATEGY_CAP_18", "0");

        IStrategy strategy =
            harness.deployAndRegisterStrategy(18, collateralVault, IERC20Metadata(address(underlyingToken)));

        assertEq(address(strategy), address(0), "no strategy");
        assertEq(collateralVault.getStrategiesCount(), 0, "no registered strategy");
        assertEq(collateralVault.totalWeightBps(), 0, "no strategy weight");
    }

    function test_DeploySelector_RevertsWhenNoneStrategyHasNonZeroWeight() public {
        MockERC20 underlyingToken = new MockERC20("Mock XAUT", "mXAUT", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_19", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_19", "1");
        vm.setEnv("DF_STRATEGY_CAP_19", "0");

        vm.expectRevert(bytes("DF: none strategy weight"));
        harness.deployAndRegisterStrategy(19, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeploySelector_RevertsWhenNoneStrategyHasNonZeroCap() public {
        MockERC20 underlyingToken = new MockERC20("Mock XAUT", "mXAUT", 6);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));

        vm.setEnv("DF_STRATEGY_KIND_20", "none");
        vm.setEnv("DF_STRATEGY_WEIGHT_BPS_20", "0");
        vm.setEnv("DF_STRATEGY_CAP_20", "1");

        vm.expectRevert(bytes("DF: none strategy cap"));
        harness.deployAndRegisterStrategy(20, collateralVault, IERC20Metadata(address(underlyingToken)));
    }

    function test_DeployZappers_DTokenBranchOnlyDeploysCollateralYieldZapper() public {
        address lidoReferral = 0x57af3a60314cD24032a4435b715f4dC8eb5967F0;
        vm.setEnv("DF_ZAPPER_LIDO_REFERRAL_0", vm.toString(lidoReferral));
        YieldZapperFixture memory fixture = _deployYieldZapperFixture();

        assertEq(address(fixture.collateralYieldZapper.underlyingToken()), fixture.underlyingToken, "yield underlying");
        string memory routeJson = string.concat(
            "{", harness.dfYieldNativeEthRouteJsonForHarness(fixture.collateralYieldZapper), '"end":true}'
        );
        assertEq(vm.parseJsonAddress(routeJson, ".stEthToken"), address(0), "manifest route disabled");
        assertEq(vm.parseJsonAddress(routeJson, ".lidoReferral"), lidoReferral, "manifest referral getter");

        TimelockController referralTimelock =
            TimelockController(payable(fixture.collateralYieldZapper.lidoReferralManager()));
        assertTrue(address(referralTimelock).code.length != 0, "local referral manager is a contract");
        assertEq(referralTimelock.getMinDelay(), 0, "local referral Timelock permits deterministic tests");

        address updatedReferral = makeAddr("localUpdatedReferral");
        bytes memory data = abi.encodeCall(CollateralYieldZapper.setLidoReferral, (updatedReferral));
        bytes32 salt = keccak256("local-lido-referral-update");
        referralTimelock.schedule(address(fixture.collateralYieldZapper), 0, data, bytes32(0), salt, 1);
        vm.warp(block.timestamp + 1);
        referralTimelock.execute(address(fixture.collateralYieldZapper), 0, data, bytes32(0), salt);
        assertEq(fixture.collateralYieldZapper.lidoReferral(), updatedReferral, "local Timelock executes update");
    }

    function _deployYieldZapperFixture() internal returns (YieldZapperFixture memory fixture) {
        WETH9 weth = new WETH9();
        harness.setHarnessWETH(IWETH(address(weth)));

        MockERC20 underlyingToken = new MockERC20("Mock USDC", "mUSDC", 18);
        MockERC20 jpydfToken = new MockERC20("JPYdf", "JPYDF", 18);
        CollateralVault collateralVault = _deployVault(IERC20Metadata(address(underlyingToken)));
        fixture.underlyingToken = address(underlyingToken);

        AddressesRegistry registry = new AddressesRegistry(
            address(this),
            1.5e18, // CCR
            1.1e18, // MCR
            0.05e18, // BCR
            1.2e18, // SCR
            0.05e18, // liquidation penalty SP
            0.1e18, // liquidation penalty redistribution
            address(0) // deploy-time finalized
        );
        IAddressesRegistry.AddressVars memory addressVars;
        addressVars.collToken = IERC20Metadata(address(collateralVault.dToken()));
        addressVars.borrowerOperations = IBorrowerOperations(makeAddr("borrowerOperations"));
        addressVars.jpydfToken = IJpydfToken(address(jpydfToken));
        addressVars.WETH = IWETH(address(weth));
        registry.setAddresses(addressVars);

        CollateralYieldZapper collateralYieldZapper = harness.deployZapperForHarness(
            IAddressesRegistry(address(registry)), collateralVault, IERC20(address(underlyingToken))
        );

        assertTrue(address(collateralYieldZapper) != address(0), "collateral yield zapper");

        fixture.collateralYieldZapper = collateralYieldZapper;
    }

    function _setSkyBranchOneStrategyEnv(address usds, address susdsVault, address psmWrapper) internal {
        _setSkyBranchStrategyEnv(0, usds, susdsVault, psmWrapper);
    }

    function _setStrategyArrayEnv(uint256 branchIndex, uint256 strategyIndex, string memory kind, uint256 weightBps)
        internal
    {
        vm.setEnv(string.concat("DF_STRATEGY_KIND_", vm.toString(branchIndex), "_", vm.toString(strategyIndex)), kind);
        vm.setEnv(
            string.concat("DF_STRATEGY_WEIGHT_BPS_", vm.toString(branchIndex), "_", vm.toString(strategyIndex)),
            vm.toString(weightBps)
        );
    }

    function _setMainnetCanaryStrategyEnv(uint256 branchIndex, string memory erc4626Vault, uint256 erc4626Cap)
        internal
    {
        string memory branch = vm.toString(branchIndex);
        vm.setEnv(string.concat("DF_STRATEGY_COUNT_", branch), "2");
        _setStrategyArrayEnv(branchIndex, 0, "aave", 5_000);
        _setStrategyArrayEnv(branchIndex, 1, "erc4626", 5_000);
        vm.setEnv(string.concat("DF_STRATEGY_CAP_", branch, "_0"), "100000000");
        vm.setEnv(string.concat("DF_STRATEGY_CAP_", branch, "_1"), vm.toString(erc4626Cap));
        vm.setEnv(string.concat("DF_STRATEGY_ERC4626_VAULT_", branch, "_1"), erc4626Vault);
    }

    function _setSkyBranchStrategyEnv(uint256 strategyIndex, address usds, address susdsVault, address psmWrapper)
        internal
    {
        vm.setEnv("DF_STRATEGY_COUNT_1", "3");
        vm.setEnv(string.concat("DF_STRATEGY_KIND_1_", vm.toString(strategyIndex)), "sky-susds");
        vm.setEnv(string.concat("DF_STRATEGY_WEIGHT_BPS_1_", vm.toString(strategyIndex)), "10000");
        vm.setEnv(string.concat("DF_STRATEGY_CAP_1_", vm.toString(strategyIndex)), vm.toString(type(uint256).max));
        vm.setEnv(string.concat("DF_STRATEGY_SKY_USDS_1_", vm.toString(strategyIndex)), vm.toString(usds));
        vm.setEnv(string.concat("DF_STRATEGY_SKY_SUSDS_VAULT_1_", vm.toString(strategyIndex)), vm.toString(susdsVault));
        vm.setEnv(
            string.concat("DF_STRATEGY_SKY_USDC_USDS_PSM_WRAPPER_1_", vm.toString(strategyIndex)),
            vm.toString(psmWrapper)
        );
        vm.setEnv(string.concat("DF_STRATEGY_SKY_MAX_CONVERSION_LOSS_BPS_1_", vm.toString(strategyIndex)), "50");
    }

    function _deployTimelock(uint256 minDelay) internal returns (TimelockController timelock) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(minDelay, proposers, executors, address(0));
        _installCanonicalProductionTimelockRuntime(address(timelock));
    }

    function _deployProductionTimelock(uint256 minDelay) internal returns (TimelockController timelock) {
        address[] memory admins = new address[](1);
        admins[0] = MAINNET_ADMIN_SAFE;
        timelock = new TimelockController(minDelay, admins, admins, address(0));
        _installCanonicalProductionTimelockRuntime(address(timelock));
    }

    function _installCanonicalProductionTimelockRuntime(address timelock) internal {
        bytes memory runtimeCode = type(TimelockController).runtimeCode;
        assertEq(runtimeCode.length, 7_508);
        assembly {
            mstore(runtimeCode, 7454)
        }
        assertEq(keccak256(runtimeCode), 0xfbb8dca0ef620c28593dafd8ead5162f233db640a9ebfdc4d47a7920cc06b2af);
        vm.etch(timelock, runtimeCode);
    }

    function _installMainnetPilotTimelock(uint256 minDelay) internal {
        bytes memory runtimeCode = type(TimelockController).runtimeCode;
        bytes memory pilotMetadataTail =
            hex"8eb5e82098c3418fd5fa9c02e5c2c2d88e780e36433c12723f9686008b1ff0c064736f6c63430008180033";
        for (uint256 i; i < pilotMetadataTail.length; ++i) {
            runtimeCode[runtimeCode.length - pilotMetadataTail.length + i] = pilotMetadataTail[i];
        }
        assertEq(keccak256(runtimeCode), 0x7919dd185a79d90854632f7fa3ce5d7ef7ba8fa01dda17fff718a9be37efa7bc);
        vm.etch(MAINNET_PILOT_TIMELOCK, runtimeCode);
        vm.mockCall(
            MAINNET_PILOT_TIMELOCK,
            abi.encodeWithSelector(TimelockController.getMinDelay.selector),
            abi.encode(minDelay)
        );
    }

    function _deployVault(IERC20Metadata underlyingToken) internal returns (CollateralVault collateralVault) {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer =
            abi.encodeWithSelector(DToken.initialize.selector, predictedVault, address(this));
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(underlyingToken), true);

        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlyingToken)),
            IDToken(address(dToken)),
            treasury,
            address(this)
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        collateralVault.grantRole(GOV_ROLE, address(harness));
        dToken.setTokenInfo("dToken", "dTKN", IERC20MetadataUpgradeable(address(underlyingToken)));
        activateDTokenForTest(dToken);
    }
}
