// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockDTokenRegistry} from "test/mocks/MockDTokenRegistry.sol";

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    IERC20MetadataUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {CollateralVault} from "src/CollateralVault.sol";
import {DToken} from "src/DToken.sol";
import {InterestRouterForwarder} from "src/InterestRouterForwarder.sol";
import {IDToken} from "src/Interfaces/IDToken.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {AcceptDFGovernanceHandover} from "script/AcceptDFGovernanceHandover.s.sol";
import {YieldLayerProxyDeployer} from "script/DeployLiquity2.s.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";
import {PrepareDFGovernanceHandover} from "script/PrepareDFGovernanceHandover.s.sol";
import {VerifyDFGovernanceHandover} from "script/VerifyDFGovernanceHandover.s.sol";
import {MainnetProductionTimelockPolicy} from "script/MainnetProductionTimelockPolicy.sol";
import {MockStrategy} from "./TestContracts/MockStrategy.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PrepareDFGovernanceHandoverHarness is PrepareDFGovernanceHandover {
    function verifiedSharedInterestRouter(string memory manifest, uint256 totalBranches)
        external
        pure
        returns (address)
    {
        return _verifiedSharedInterestRouter(manifest, totalBranches);
    }

    function verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        external
        view
    {
        _verifyInterestRouterForwarder(manifest, interestRouter, expectedRecipient);
    }

    function envFlagForHarness(string memory key) external view returns (bool) {
        return _envFlag(key);
    }

    function requireMainnetDay1EnvelopeForHarness(
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) external view {
        _requireMainnetDay1Envelope(branchIndex, dToken, underlying, underlyingDecimals, cap, allocateMaxMove);
    }

    function requireMainnetDay1EnvelopeFromEvidenceForHarness(
        string memory evidence,
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) external view {
        _requireMainnetDay1EnvelopeFromEvidence(
            evidence, branchIndex, dToken, underlying, underlyingDecimals, cap, allocateMaxMove
        );
    }

    function requireMainnetProductionGovernanceForHarness(
        string memory manifest,
        address timelock,
        address[6] calldata roleHolders
    ) external view {
        HandoverConfig memory cfg;
        cfg.timelock = timelock;
        cfg.dTokenOwner = timelock;
        cfg.vaultAdmin = timelock;
        cfg.treasury = roleHolders[0];
        cfg.interestRouterRecipient = roleHolders[1];
        cfg.guardian = roleHolders[2];
        cfg.allocator = roleHolders[3];
        cfg.writeoff = roleHolders[4];
        cfg.priceFeedOwner = roleHolders[5];
        cfg.totalBranches = 8;
        cfg.activeBranches = 2;
        _requireMainnetProductionGovernance(manifest, cfg);
    }

    function requireMainnetBranchTopologyForHarness(uint256 totalBranches, uint256 activeBranches) external view {
        _requireMainnetDay1BranchTopology(totalBranches, activeBranches);
    }

    function prepareBranchStrategiesForHarness(
        string memory manifest,
        uint256 branchIndex,
        CollateralVault vault,
        address currentAdmin,
        address strategyOwner,
        address strategyUpgrader
    ) external {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.strategyOwner = strategyOwner;
        cfg.strategyUpgrader = strategyUpgrader;
        _prepareBranchStrategies(manifest, branchIndex, vault, cfg);
    }

    function acceptDTokenOwnershipForHarness(DToken dToken) external {
        dToken.acceptOwnership();
    }

    function applyActiveBranchVaultParametersForHarness(uint256 branchIndex, DToken dToken, CollateralVault vault)
        external
    {
        _applyActiveBranchVaultParameters(branchIndex, dToken, vault);
    }

    function requireActiveBranchCapFrozenForHarness(DToken dToken) external view {
        _requireActiveBranchCapFrozen(dToken);
    }

    function setOwnVaultGovRoleForHarness(CollateralVault vault, bool enabled) external {
        bytes32 govRole = keccak256("GOV_ROLE");
        if (enabled) {
            vault.grantRole(govRole, address(this));
        } else {
            vault.revokeRole(govRole, address(this));
        }
    }

    function prepareVaultForHarness(
        CollateralVault vault,
        address currentAdmin,
        address timelock,
        address treasury,
        address guardian,
        address allocator,
        address writeoff
    ) external {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.timelock = timelock;
        cfg.vaultAdmin = timelock;
        cfg.treasury = treasury;
        cfg.guardian = guardian;
        cfg.allocator = allocator;
        cfg.writeoff = writeoff;
        _prepareVault(vault, cfg);
    }
}

contract VerifyDFGovernanceHandoverHarness is VerifyDFGovernanceHandover {
    function verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        external
        view
    {
        _verifyInterestRouterForwarder(manifest, interestRouter, expectedRecipient);
    }

    function envFlagForHarness(string memory key) external view returns (bool) {
        return _envFlag(key);
    }

    function requireMainnetDay1EnvelopeForHarness(
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) external view {
        _requireMainnetDay1Envelope(branchIndex, dToken, underlying, underlyingDecimals, cap, allocateMaxMove);
    }

    function requireMainnetDay1EnvelopeFromEvidenceForHarness(
        string memory evidence,
        uint256 branchIndex,
        address dToken,
        address underlying,
        uint8 underlyingDecimals,
        uint256 cap,
        uint256 allocateMaxMove
    ) external view {
        _requireMainnetDay1EnvelopeFromEvidence(
            evidence, branchIndex, dToken, underlying, underlyingDecimals, cap, allocateMaxMove
        );
    }

    function requireMainnetProductionGovernanceForHarness(
        string memory manifest,
        address timelock,
        address[6] calldata roleHolders
    ) external view {
        HandoverConfig memory cfg;
        cfg.timelock = timelock;
        cfg.dTokenOwner = timelock;
        cfg.vaultAdmin = timelock;
        cfg.treasury = roleHolders[0];
        cfg.interestRouterRecipient = roleHolders[1];
        cfg.guardian = roleHolders[2];
        cfg.allocator = roleHolders[3];
        cfg.writeoff = roleHolders[4];
        cfg.priceFeedOwner = roleHolders[5];
        cfg.totalBranches = 8;
        cfg.activeBranches = 2;
        _requireMainnetProductionGovernance(manifest, cfg);
    }

    function requireMainnetBranchTopologyForHarness(uint256 totalBranches, uint256 activeBranches) external view {
        _requireMainnetDay1BranchTopology(totalBranches, activeBranches);
    }

    function verifyBranchStrategiesForHarness(
        string memory manifest,
        uint256 branchIndex,
        CollateralVault vault,
        address currentAdmin,
        address strategyOwner,
        address strategyUpgrader,
        bool allowPendingOwnership
    ) external view {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.strategyOwner = strategyOwner;
        cfg.strategyUpgrader = strategyUpgrader;
        cfg.allowPendingOwnership = allowPendingOwnership;
        _verifyBranchStrategies(manifest, branchIndex, vault, cfg);
    }

    function verifyDTokenForHarness(DToken dToken, address timelock, address currentAdmin, bool allowPendingOwnership)
        external
        view
    {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.timelock = timelock;
        cfg.dTokenOwner = timelock;
        cfg.allowPendingOwnership = allowPendingOwnership;
        _verifyDToken(dToken, cfg);
    }

    function verifyTwoStepOwnerForHarness(
        address target,
        address expectedOwner,
        address currentAdmin,
        bool allowPendingOwnership,
        string memory label
    ) external view {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.allowPendingOwnership = allowPendingOwnership;
        _verifyTwoStepOwner(target, expectedOwner, cfg, label);
    }

    function verifyVaultForHarness(
        CollateralVault vault,
        address currentAdmin,
        address timelock,
        address treasury,
        address guardian,
        address allocator,
        address writeoff
    ) external view {
        HandoverConfig memory cfg;
        cfg.currentAdmin = currentAdmin;
        cfg.timelock = timelock;
        cfg.vaultAdmin = timelock;
        cfg.treasury = treasury;
        cfg.guardian = guardian;
        cfg.allocator = allocator;
        cfg.writeoff = writeoff;
        _verifyVault(vault, cfg);
    }
}

contract AcceptDFGovernanceHandoverHarness is AcceptDFGovernanceHandover {
    function requireLocalChainForHarness(uint256 chainId) external pure {
        _requireLocalChain(chainId);
    }

    function verifiedSharedInterestRouter(string memory manifest, uint256 totalBranches)
        external
        pure
        returns (address)
    {
        return _verifiedSharedInterestRouter(manifest, totalBranches);
    }

    function verifyInterestRouterForwarder(string memory manifest, address interestRouter, address expectedRecipient)
        external
        view
    {
        _verifyInterestRouterForwarder(manifest, interestRouter, expectedRecipient);
    }

    function acceptBranchStrategiesForHarness(
        string memory manifest,
        uint256 branchIndex,
        address strategyOwner,
        uint256 strategyOwnerPrivateKey
    ) external {
        HandoverConfig memory cfg;
        cfg.strategyOwner = strategyOwner;
        cfg.strategyOwnerPrivateKey = strategyOwnerPrivateKey;
        _acceptBranchStrategies(manifest, branchIndex, cfg);
    }
}

contract ScriptSecurityPolicyHarness {
    function requirePublicAddress(string memory environmentVariable, bytes memory encodedValue) external pure {
        ScriptSecurityPolicy.requirePublicAddress(environmentVariable, encodedValue);
    }
}

contract NonForwarderInterestRouter {
    address public owner;
    address public pendingOwner;

    constructor(address _owner) {
        owner = _owner;
    }
}

contract MockJpydfRecipientValidator {
    mapping(address recipient => bool invalid) internal invalidRecipients;

    function setInvalidRecipient(address recipient, bool invalid) external {
        invalidRecipients[recipient] = invalid;
    }

    function requireValidRecipient(address recipient) external view {
        if (invalidRecipients[recipient]) revert IJpydfToken.JpydfToken__CannotTransferToProtocolContract();
    }
}

contract DFGovernanceHandoverTest is Test {
    address private constant LOCAL_FORK_SENTINEL = 0x0000000000000000000000000000000000001455;
    address private constant MAINNET_PILOT_TIMELOCK = 0xEd33edB1eA442475eFd076e1AE2C9da9EdaB86f6;
    address private constant MAINNET_ADMIN_SAFE = 0xA8331cFA52BC67a468D6126b4A18419C6D830b4E;
    address private constant MAINNET_GUARDIAN_SAFE = 0xC89592b35278B6Bbba2b710acd463E7A3C8D0Eb0;
    address private constant MAINNET_ALLOCATOR_SAFE = 0x34b8Edd6E6B8032cCDb930722486edd2Ac9134B5;
    address private constant MAINNET_TREASURY_SAFE = 0x739b9e6BeB4C278DFc327523880fdBafe4BD129D;
    address private constant MAINNET_PIL_RECIPIENT_SAFE = 0x3CC1e7987a1459c7374AfBAEe104d1D65F07E658;

    PrepareDFGovernanceHandoverHarness internal prepare;
    VerifyDFGovernanceHandoverHarness internal verifyHandover;
    AcceptDFGovernanceHandoverHarness internal acceptHandover;
    ScriptSecurityPolicyHarness internal signerPolicy;
    address internal pilRecipient;
    address internal routerOwner;
    MockJpydfRecipientValidator internal tokenValidator;

    function setUp() public {
        prepare = new PrepareDFGovernanceHandoverHarness();
        verifyHandover = new VerifyDFGovernanceHandoverHarness();
        acceptHandover = new AcceptDFGovernanceHandoverHarness();
        signerPolicy = new ScriptSecurityPolicyHarness();
        pilRecipient = makeAddr("pilRecipient");
        routerOwner = makeAddr("routerOwner");
        tokenValidator = new MockJpydfRecipientValidator();
    }

    function test_DeploymentSignerPolicyAcceptsOnlyPublicAddress() public view {
        signerPolicy.requirePublicAddress("DEPLOYER", abi.encodePacked(address(this)));
    }

    function test_DeploymentSignerPolicyRejectsPrivateKeyBytes() public {
        bytes memory encodedPrivateKey = abi.encode(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                ScriptSecurityPolicy.ScriptSecurityPolicy__PublicAddressRequired.selector,
                "DEPLOYER",
                encodedPrivateKey.length
            )
        );
        signerPolicy.requirePublicAddress("DEPLOYER", encodedPrivateKey);
    }

    function test_AcceptHandoverAllowsOnlyLocalChains() public {
        acceptHandover.requireLocalChainForHarness(31_337);
        acceptHandover.requireLocalChainForHarness(31_338);

        vm.expectRevert(abi.encodeWithSelector(ScriptSecurityPolicy.ScriptSecurityPolicy__LocalChainOnly.selector, 1));
        acceptHandover.requireLocalChainForHarness(1);
    }

    function test_AcceptHandoverRejectsProductionBeforeReadingSecrets() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(ScriptSecurityPolicy.ScriptSecurityPolicy__LocalChainOnly.selector, 1));
        acceptHandover.run();
    }

    function test_MainnetHandoverRequiresDistinctTwelveHourProductionTimelock() public {
        vm.chainId(1);
        address[] memory admins = new address[](1);
        admins[0] = MAINNET_ADMIN_SAFE;
        TimelockController timelock = new TimelockController(12 hours, admins, admins, address(0));
        _installCanonicalProductionTimelockRuntime(address(timelock));
        string memory manifest = _productionGovernanceManifest(address(timelock));

        address[6] memory roleHolders = _productionRoleHolders();
        prepare.requireMainnetProductionGovernanceForHarness(manifest, address(timelock), roleHolders);
        verifyHandover.requireMainnetProductionGovernanceForHarness(manifest, address(timelock), roleHolders);
    }

    function test_MainnetHandoverRejectsPartialBranchTopology() public {
        vm.chainId(1);

        vm.expectRevert(bytes("DF handover: production total branches"));
        prepare.requireMainnetBranchTopologyForHarness(2, 2);
        vm.expectRevert(bytes("DF verify: production total branches"));
        verifyHandover.requireMainnetBranchTopologyForHarness(2, 2);

        vm.expectRevert(bytes("DF handover: production active branches"));
        prepare.requireMainnetBranchTopologyForHarness(8, 8);
        vm.expectRevert(bytes("DF verify: production active branches"));
        verifyHandover.requireMainnetBranchTopologyForHarness(8, 8);
    }

    function test_MainnetHandoverRejectsFiveMinutePilotTimelock() public {
        vm.chainId(1);
        string memory manifest = _productionGovernanceManifest(MAINNET_PILOT_TIMELOCK);

        vm.expectRevert(MainnetProductionTimelockPolicy.PilotTimelockForbidden.selector);
        address[6] memory roleHolders = _productionRoleHolders();
        prepare.requireMainnetProductionGovernanceForHarness(manifest, MAINNET_PILOT_TIMELOCK, roleHolders);
        vm.expectRevert(MainnetProductionTimelockPolicy.PilotTimelockForbidden.selector);
        verifyHandover.requireMainnetProductionGovernanceForHarness(manifest, MAINNET_PILOT_TIMELOCK, roleHolders);
    }

    function test_MainnetHandoverRejectsNonCanonicalTreasury() public {
        _assertMainnetRoleHolderDriftRejected(0);
    }

    function test_MainnetHandoverRejectsNonCanonicalInterestRouterRecipient() public {
        _assertMainnetRoleHolderDriftRejected(1);
    }

    function test_MainnetHandoverRejectsNonCanonicalGuardian() public {
        _assertMainnetRoleHolderDriftRejected(2);
    }

    function test_MainnetHandoverRejectsNonCanonicalAllocator() public {
        _assertMainnetRoleHolderDriftRejected(3);
    }

    function test_MainnetHandoverRejectsNonCanonicalWriteoff() public {
        _assertMainnetRoleHolderDriftRejected(4);
    }

    function test_MainnetHandoverRejectsNonCanonicalPriceFeedOwner() public {
        _assertMainnetRoleHolderDriftRejected(5);
    }

    function test_MainnetDay1EnvelopeAllowsConvertedTokenValues() public view {
        string memory evidence = _conversionEvidence();
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 50e18, 0
        );
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 1, address(0xD701), address(0x701), 6, 500_000e18, 500_000e6
        );
        verifyHandover.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 50e18, 0
        );
        verifyHandover.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 1, address(0xD701), address(0x701), 6, 500_000e18, 500_000e6
        );
    }

    function test_MainnetDay1EnvelopeRequiresOverrideAndLocalForkSentinelForTestOnlyEvidence() public {
        string memory evidence = _conversionEvidenceWithClassification("TEST_ONLY_NOT_APPROVED_FOR_MAINNET_BROADCAST");

        vm.expectRevert(bytes("DF Day-1: test-only evidence"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 50e18, 0
        );

        vm.setEnv("DF_ALLOW_TEST_ONLY_CAP_CONVERSION", "LOCAL_MAINNET_FORK_ONLY");
        vm.expectRevert(bytes("DF Day-1: local fork sentinel"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 50e18, 0
        );

        vm.etch(LOCAL_FORK_SENTINEL, hex"60006000fd");
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 50e18, 0
        );
    }

    function test_MainnetDay1EnvelopeRejectsUnknownEvidenceClassification() public {
        vm.expectRevert(bytes("DF Day-1: evidence classification"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            _conversionEvidenceWithClassification("UNREVIEWED"), 0, address(0xD700), address(0x700), 18, 50e18, 0
        );
    }

    function test_MainnetDay1EnvelopeRejectsUnlimitedValues() public {
        string memory evidence = _conversionEvidence();
        vm.expectRevert(bytes("DF Day-1: cap unlimited"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, type(uint256).max, 0
        );

        vm.expectRevert(bytes("DF Day-1: allocate unlimited"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 1, address(0xD701), address(0x701), 6, 500_000e18, type(uint256).max
        );

        vm.expectRevert(bytes("DF Day-1: cap unlimited"));
        verifyHandover.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, type(uint256).max, 0
        );
    }

    function test_MainnetDay1EnvelopeRejectsNominalJpyAsTokenUnits() public {
        string memory evidence = _conversionEvidence();
        vm.expectRevert(bytes("DF Day-1: cap != converted value"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0x700), 18, 35_000_000e18, 0
        );

        vm.expectRevert(bytes("DF Day-1: allocate != converted value"));
        verifyHandover.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 1, address(0xD701), address(0x701), 6, 500_000e18, 100_000_000e18
        );
    }

    function test_MainnetDay1EnvelopeRejectsMismatchedEvidence() public {
        string memory evidence = _conversionEvidence();
        vm.expectRevert(bytes("DF Day-1: evidence decimals"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 1, address(0xD701), address(0x701), 18, 500_000e18, 500_000e6
        );

        vm.expectRevert(bytes("DF Day-1: evidence underlying"));
        verifyHandover.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            evidence, 0, address(0xD700), address(0xBAD), 18, 50e18, 0
        );
    }

    function test_MainnetDay1EnvelopeRejectsExpiredEvidence() public {
        vm.warp(86_402);
        vm.expectRevert(bytes("DF Day-1: evidence expired"));
        prepare.requireMainnetDay1EnvelopeFromEvidenceForHarness(
            _conversionEvidence(), 0, address(0xD700), address(0x700), 18, 50e18, 0
        );
    }

    function test_MainnetDay1EnvelopeSkipsNonMainnetChains() public {
        vm.chainId(31_337);
        prepare.requireMainnetDay1EnvelopeForHarness(
            0, address(0), address(0), 18, type(uint256).max, type(uint256).max
        );
        verifyHandover.requireMainnetDay1EnvelopeForHarness(1, address(0), address(0), 6, 123, 456);

        vm.chainId(31_338);
        prepare.requireMainnetDay1EnvelopeForHarness(5, address(0), address(0), 18, 777, 888);
    }

    function test_HandoverBoolEnvFlagsParseExplicitFalseAsFalse() public {
        string memory prepareKey = "DF_TEST_ALLOW_CURRENT_ADMIN_AS_TARGET_PARSE";
        vm.setEnv(prepareKey, "false");
        assertFalse(prepare.envFlagForHarness(prepareKey), "prepare false string");
        vm.setEnv(prepareKey, "yes");
        assertTrue(prepare.envFlagForHarness(prepareKey), "prepare yes string");

        string memory verifyKey = "DF_TEST_VERIFY_PENDING_OWNERSHIP_PARSE";
        vm.setEnv(verifyKey, "0");
        assertFalse(verifyHandover.envFlagForHarness(verifyKey), "verify zero string");
        vm.setEnv(verifyKey, "true");
        assertTrue(verifyHandover.envFlagForHarness(verifyKey), "verify true string");
    }

    function test_ActiveBranchPreparationKeepsDepositsFrozen() public {
        (MockERC20 underlying, DToken dToken, CollateralVault vault) = _deployFrozenActiveYieldLayer();
        address depositor = makeAddr("handoverDepositor");
        underlying.mint(depositor, 101e6);

        vm.startPrank(depositor);
        underlying.approve(address(vault), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(DToken.CapExceeded.selector, 1e18, 0));
        vault.deposit(1e6);
        vm.stopPrank();

        _setActiveBranchParameterEnv(0, 100e18, 333);
        prepare.applyActiveBranchVaultParametersForHarness(0, dToken, vault);
        assertEq(dToken.cap(), 0, "parameter preparation keeps cap frozen");
        prepare.requireActiveBranchCapFrozenForHarness(dToken);

        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(DToken.CapExceeded.selector, 60e18, 0));
        vault.deposit(60e6);

        vm.prank(address(prepare));
        dToken.setCap(100e18);
        vm.expectRevert(bytes("DF handover: active cap must remain zero"));
        prepare.requireActiveBranchCapFrozenForHarness(dToken);
    }

    function test_FailedHandoverParameterApplicationRollsBackCapAndCanRecover() public {
        (, DToken dToken, CollateralVault vault) = _deployFrozenActiveYieldLayer();
        _setActiveBranchParameterEnv(1, 100e18, 333);
        prepare.setOwnVaultGovRoleForHarness(vault, false);

        vm.expectRevert();
        prepare.applyActiveBranchVaultParametersForHarness(1, dToken, vault);

        assertEq(dToken.cap(), 0, "partial handover failure keeps branch frozen");
        assertEq(vault.bufferTargetBps(), 2_000, "partial handover failure rolls back vault config");

        prepare.setOwnVaultGovRoleForHarness(vault, true);
        prepare.applyActiveBranchVaultParametersForHarness(1, dToken, vault);
        assertEq(dToken.cap(), 0, "successful preparation alone cannot activate minting");
        prepare.requireActiveBranchCapFrozenForHarness(dToken);
    }

    function test_InterestRouterVerifierAcceptsForwarder() public {
        InterestRouterForwarder forwarder =
            new InterestRouterForwarder(IERC20(address(tokenValidator)), pilRecipient, routerOwner);
        string memory manifest = _manifest(address(tokenValidator));

        prepare.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);
        verifyHandover.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);
        acceptHandover.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);
    }

    function test_InterestRouterVerifierRejectsDirectOwnableReceiver() public {
        NonForwarderInterestRouter router = new NonForwarderInterestRouter(routerOwner);
        string memory manifest = _manifest(address(tokenValidator));

        vm.expectRevert(bytes("DF handover: not interest router forwarder"));
        prepare.verifyInterestRouterForwarder(manifest, address(router), pilRecipient);

        vm.expectRevert(bytes("DF verify: not interest router forwarder"));
        verifyHandover.verifyInterestRouterForwarder(manifest, address(router), pilRecipient);

        vm.expectRevert(bytes("DF accept: not interest router forwarder"));
        acceptHandover.verifyInterestRouterForwarder(manifest, address(router), pilRecipient);
    }

    function test_InterestRouterVerifierRejectsWrongTokenOrRecipient() public {
        InterestRouterForwarder forwarder =
            new InterestRouterForwarder(IERC20(address(tokenValidator)), pilRecipient, routerOwner);

        vm.expectRevert(bytes("DF handover: interest router token"));
        prepare.verifyInterestRouterForwarder(_manifest(address(0xBAD)), address(forwarder), pilRecipient);

        vm.expectRevert(bytes("DF verify: interest router recipient"));
        verifyHandover.verifyInterestRouterForwarder(
            _manifest(address(tokenValidator)), address(forwarder), makeAddr("other")
        );

        vm.expectRevert(bytes("DF accept: interest router recipient"));
        acceptHandover.verifyInterestRouterForwarder(
            _manifest(address(tokenValidator)), address(forwarder), makeAddr("other2")
        );
    }

    function test_InterestRouterVerifierRejectsRecipientThatJpydfNoLongerAccepts() public {
        InterestRouterForwarder forwarder =
            new InterestRouterForwarder(IERC20(address(tokenValidator)), pilRecipient, routerOwner);
        string memory manifest = _manifest(address(tokenValidator));
        tokenValidator.setInvalidRecipient(pilRecipient, true);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        prepare.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        verifyHandover.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        acceptHandover.verifyInterestRouterForwarder(manifest, address(forwarder), pilRecipient);
    }

    function test_HandoverPreflightRejectsSplitRoutersBeforeMutation() public {
        string memory manifest = _manifestWithRouters(address(tokenValidator), address(0xA11CE), address(0xB0B));

        vm.expectRevert(bytes("DF handover: mixed interest router"));
        prepare.verifiedSharedInterestRouter(manifest, 2);

        vm.expectRevert(bytes("DF accept: mixed interest router"));
        acceptHandover.verifiedSharedInterestRouter(manifest, 2);
    }

    function test_HandoverPreflightReturnsSharedRouter() public view {
        address router = address(0xA11CE);
        string memory manifest = _manifestWithRouters(address(tokenValidator), router, router);

        assertEq(prepare.verifiedSharedInterestRouter(manifest, 2), router);
        assertEq(acceptHandover.verifiedSharedInterestRouter(manifest, 2), router);
    }

    function test_HandoverStrategyHelpersCoverSecondaryStrategies() public {
        (CollateralVault vault, MockStrategy stratA, MockStrategy stratB) = _deployTwoStrategyVault(address(prepare));
        uint256 strategyOwnerPrivateKey = 0xA11CE;
        address strategyOwner = vm.addr(strategyOwnerPrivateKey);
        address strategyUpgrader = makeAddr("strategyUpgrader");
        string memory manifest = _strategyManifest(address(vault), address(stratA), address(stratB));

        prepare.prepareBranchStrategiesForHarness(manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader);

        assertEq(stratA.upgrader(), strategyUpgrader, "primary upgrader");
        assertEq(stratB.upgrader(), strategyUpgrader, "secondary upgrader");
        assertEq(stratA.pendingOwner(), strategyOwner, "primary pending owner");
        assertEq(stratB.pendingOwner(), strategyOwner, "secondary pending owner");

        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader, true
        );

        acceptHandover.acceptBranchStrategiesForHarness(manifest, 0, strategyOwner, strategyOwnerPrivateKey);

        assertEq(stratA.owner(), strategyOwner, "primary owner");
        assertEq(stratB.owner(), strategyOwner, "secondary owner");
        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader, false
        );
    }

    function test_HandoverStrategyHelpersRejectSecondaryManifestMismatch() public {
        (CollateralVault vault, MockStrategy stratA,) = _deployTwoStrategyVault(address(prepare));
        string memory manifest = _strategyManifest(address(vault), address(stratA), makeAddr("wrongSecondary"));
        address strategyOwner = address(prepare);
        address strategyUpgrader = address(prepare);

        vm.expectRevert(bytes("DF handover: strategy mismatch"));
        prepare.prepareBranchStrategiesForHarness(manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader);
        vm.expectRevert(bytes("DF verify: strategy mismatch"));
        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader, true
        );
        vm.expectRevert(bytes("DF accept: strategy mismatch"));
        acceptHandover.acceptBranchStrategiesForHarness(manifest, 0, strategyOwner, 0xA11CE);
    }

    function test_HandoverStrategyHelpersRejectLiveConfigMismatch() public {
        (CollateralVault vault, MockStrategy stratA, MockStrategy stratB) = _deployTwoStrategyVault(address(prepare));
        string memory manifest = _strategyManifest(address(vault), address(stratA), address(stratB));
        vault.updateStrategy(IStrategy(address(stratB)), 4000, type(uint256).max, true);

        vm.expectRevert(bytes("DF handover: strategy weight mismatch"));
        prepare.prepareBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), address(prepare), address(prepare)
        );
        vm.expectRevert(bytes("DF verify: strategy weight mismatch"));
        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), address(prepare), address(prepare), false
        );
        vm.expectRevert(bytes("DF accept: strategy weight mismatch"));
        acceptHandover.acceptBranchStrategiesForHarness(manifest, 0, address(prepare), 0xA11CE);
    }

    function test_VaultHandoverRemovesFormerAdminFromPlaceholderVault() public {
        (CollateralVault vault,,) = _deployTwoStrategyVault();
        address formerAdmin = address(prepare);
        address timelock = makeAddr("vaultTimelock");
        address treasury = makeAddr("vaultTreasuryTarget");
        address guardian = makeAddr("vaultGuardian");
        address allocator = makeAddr("vaultAllocator");
        address writeoff = makeAddr("vaultWriteoff");

        bytes32 defaultAdminRole = bytes32(0);
        bytes32 govRole = keccak256("GOV_ROLE");
        bytes32 guardianRole = keccak256("GUARDIAN_ROLE");
        bytes32 allocatorRole = keccak256("ALLOCATOR_ROLE");
        bytes32 writeoffRole = keccak256("WRITEOFF_ROLE");
        vault.grantRole(defaultAdminRole, formerAdmin);
        vault.grantRole(govRole, formerAdmin);
        vault.grantRole(guardianRole, formerAdmin);
        vault.grantRole(allocatorRole, formerAdmin);
        vault.grantRole(writeoffRole, formerAdmin);

        prepare.prepareVaultForHarness(vault, formerAdmin, timelock, treasury, guardian, allocator, writeoff);
        verifyHandover.verifyVaultForHarness(vault, formerAdmin, timelock, treasury, guardian, allocator, writeoff);

        assertFalse(vault.hasRole(defaultAdminRole, formerAdmin), "former placeholder admin");
        assertFalse(vault.hasRole(govRole, formerAdmin), "former placeholder GOV");
        assertTrue(vault.hasRole(defaultAdminRole, timelock), "placeholder Timelock admin");
        assertTrue(vault.hasRole(govRole, timelock), "placeholder Timelock GOV");
    }

    function test_VerifyRejectsFinalDTokenPendingOwner() public {
        address timelock = makeAddr("timelock");
        address stalePendingOwner = makeAddr("stalePendingOwner");
        DToken dToken = _deployDTokenForHandover(address(this));

        dToken.transferOwnership(timelock);
        verifyHandover.verifyDTokenForHarness(dToken, timelock, address(this), true);

        vm.expectRevert(bytes("DF verify: dToken current owner"));
        verifyHandover.verifyDTokenForHarness(dToken, timelock, makeAddr("wrongCurrentAdmin"), true);

        vm.prank(timelock);
        dToken.acceptOwnership();
        verifyHandover.verifyDTokenForHarness(dToken, timelock, address(this), false);

        vm.prank(timelock);
        dToken.transferOwnership(stalePendingOwner);

        vm.expectRevert(bytes("DF verify: dToken pending owner"));
        verifyHandover.verifyDTokenForHarness(dToken, timelock, address(this), false);
    }

    function test_VerifyRejectsFinalStrategyPendingOwner() public {
        (CollateralVault vault, MockStrategy stratA, MockStrategy stratB) = _deployTwoStrategyVault(address(prepare));
        uint256 strategyOwnerPrivateKey = 0xA11CE;
        address strategyOwner = vm.addr(strategyOwnerPrivateKey);
        address strategyUpgrader = makeAddr("strategyUpgrader");
        address stalePendingOwner = makeAddr("staleStrategyPendingOwner");
        string memory manifest = _strategyManifest(address(vault), address(stratA), address(stratB));

        prepare.prepareBranchStrategiesForHarness(manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader);
        acceptHandover.acceptBranchStrategiesForHarness(manifest, 0, strategyOwner, strategyOwnerPrivateKey);
        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader, false
        );

        vm.prank(strategyOwner);
        stratA.transferOwnership(stalePendingOwner);

        vm.expectRevert(bytes("DF verify: strategy pending owner"));
        verifyHandover.verifyBranchStrategiesForHarness(
            manifest, 0, vault, address(prepare), strategyOwner, strategyUpgrader, false
        );
    }

    function test_VerifyRejectsFinalGenericPendingOwner() public {
        address stalePendingOwner = makeAddr("staleRouterPendingOwner");
        InterestRouterForwarder forwarder =
            new InterestRouterForwarder(IERC20(address(tokenValidator)), pilRecipient, routerOwner);

        verifyHandover.verifyTwoStepOwnerForHarness(
            address(forwarder), routerOwner, routerOwner, false, "interest router"
        );

        vm.prank(routerOwner);
        forwarder.transferOwnership(stalePendingOwner);

        vm.expectRevert(bytes("DF verify: interest router pending owner"));
        verifyHandover.verifyTwoStepOwnerForHarness(
            address(forwarder), routerOwner, routerOwner, false, "interest router"
        );
        verifyHandover.verifyTwoStepOwnerForHarness(
            address(forwarder), stalePendingOwner, routerOwner, true, "interest router"
        );

        vm.expectRevert(bytes("DF verify: interest router current owner"));
        verifyHandover.verifyTwoStepOwnerForHarness(
            address(forwarder), stalePendingOwner, makeAddr("wrongCurrentAdmin"), true, "interest router"
        );
    }

    function _conversionEvidence() internal pure returns (string memory) {
        return _conversionEvidenceWithClassification("APPROVED_FOR_MAINNET_BROADCAST");
    }

    function _conversionEvidenceWithClassification(string memory classification) internal pure returns (string memory) {
        return string.concat(
            '{"schemaVersion":1,"classification":"',
            classification,
            '","chainId":1,"forkBlock":12345678,"capturedAt":"1970-01-01T00:00:01Z","capturedAtUnix":1,"validUntil":86401,"branches":[',
            _branch0ConversionEvidence(),
            ",",
            _branch1ConversionEvidence(),
            "]}"
        );
    }

    function _branch0ConversionEvidence() internal pure returns (string memory) {
        return string.concat(
            '{"branchIndex":0,"dToken":"',
            vm.toString(address(0xD700)),
            '","underlying":"',
            vm.toString(address(0x700)),
            '","underlyingDecimals":18,"nominalCapJpyWad":"35000000000000000000000000",',
            '"nominalAllocateMaxMoveJpyWad":"0","priceJpyPerUnderlyingWad":"700000000000000000000000",',
            '"priceSource":"production oracle legs","backingRatioExcluded":true,"rounding":"floor",',
            '"computedDTokenCap":"50000000000000000000","computedAllocateMaxMove":"0",',
            '"riskOwnerSignoff":"risk-owner","deployReviewerSignoff":"deploy-reviewer"}'
        );
    }

    function _branch1ConversionEvidence() internal pure returns (string memory) {
        return string.concat(
            '{"branchIndex":1,"dToken":"',
            vm.toString(address(0xD701)),
            '","underlying":"',
            vm.toString(address(0x701)),
            '","underlyingDecimals":6,"nominalCapJpyWad":"100000000000000000000000000",',
            '"nominalAllocateMaxMoveJpyWad":"100000000000000000000000000",',
            '"priceJpyPerUnderlyingWad":"200000000000000000000",',
            '"priceSource":"production oracle legs","backingRatioExcluded":true,"rounding":"floor",',
            '"computedDTokenCap":"500000000000000000000000",',
            '"computedAllocateMaxMove":"500000000000",',
            '"riskOwnerSignoff":"risk-owner","deployReviewerSignoff":"deploy-reviewer"}'
        );
    }

    function _manifest(address jpydfToken) internal pure returns (string memory) {
        return string.concat('{"jpydfToken":"', vm.toString(jpydfToken), '"}');
    }

    function _productionGovernanceManifest(address timelock) internal pure returns (string memory) {
        return string.concat(
            '{"dfYield":[{"lidoReferralManager":"',
            vm.toString(timelock),
            '"},{"lidoReferralManager":"',
            vm.toString(timelock),
            '"}]}'
        );
    }

    function _productionRoleHolders() internal pure returns (address[6] memory roleHolders) {
        roleHolders = [
            MAINNET_TREASURY_SAFE,
            MAINNET_PIL_RECIPIENT_SAFE,
            MAINNET_GUARDIAN_SAFE,
            MAINNET_ALLOCATOR_SAFE,
            MAINNET_ADMIN_SAFE,
            MAINNET_ADMIN_SAFE
        ];
    }

    function _assertMainnetRoleHolderDriftRejected(uint256 roleIndex) internal {
        vm.chainId(1);
        address[] memory admins = new address[](1);
        admins[0] = MAINNET_ADMIN_SAFE;
        TimelockController timelock = new TimelockController(12 hours, admins, admins, address(0));
        _installCanonicalProductionTimelockRuntime(address(timelock));
        string memory manifest = _productionGovernanceManifest(address(timelock));
        address[6] memory roleHolders = _productionRoleHolders();
        roleHolders[roleIndex] = makeAddr("nonCanonicalRoleHolder");

        vm.expectRevert(MainnetProductionTimelockPolicy.RoleHolderMismatch.selector);
        prepare.requireMainnetProductionGovernanceForHarness(manifest, address(timelock), roleHolders);
        vm.expectRevert(MainnetProductionTimelockPolicy.RoleHolderMismatch.selector);
        verifyHandover.requireMainnetProductionGovernanceForHarness(manifest, address(timelock), roleHolders);
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

    function _manifestWithRouters(address jpydfToken, address router0, address router1)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"jpydfToken":"',
            vm.toString(jpydfToken),
            '","branches":[{"interestRouter":"',
            vm.toString(router0),
            '"},{"interestRouter":"',
            vm.toString(router1),
            '"}]}'
        );
    }

    function _strategyManifest(address vault, address primaryStrategy, address secondaryStrategy)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"dfYield":[{"collateralVault":"',
            vm.toString(vault),
            '","strategies":[{"strategy":"',
            vm.toString(primaryStrategy),
            '","strategyWeightBps":"5000","strategyCap":"',
            vm.toString(type(uint256).max),
            '"},{"strategy":"',
            vm.toString(secondaryStrategy),
            '","strategyWeightBps":"5000","strategyCap":"',
            vm.toString(type(uint256).max),
            '"}]}]}'
        );
    }

    function _deployTwoStrategyVault()
        internal
        returns (CollateralVault vault, MockStrategy stratA, MockStrategy stratB)
    {
        return _deployTwoStrategyVault(address(this));
    }

    function _deployTwoStrategyVault(address strategyAdmin)
        internal
        returns (CollateralVault vault, MockStrategy stratA, MockStrategy stratB)
    {
        MockERC20 underlying = new MockERC20("Mock Underlying", "MUNDER", 18);
        CollateralVault vaultImpl = new CollateralVault();

        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        DToken dToken = _deployDTokenForHandover(predictedVault);
        dToken.setAllowedUnderlying(address(underlying), true);

        bytes memory vaultInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlying)),
            IDToken(address(dToken)),
            makeAddr("vaultTreasury"),
            address(this)
        );
        vault = CollateralVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));
        assertEq(address(vault), predictedVault, "vault address mismatch");

        stratA = _deployMockStrategyFor(vault, IERC20(address(underlying)), strategyAdmin);
        stratB = _deployMockStrategyFor(vault, IERC20(address(underlying)), strategyAdmin);

        vault.addToWhitelist(address(stratA));
        vault.addToWhitelist(address(stratB));
        vault.addStrategy(IStrategy(address(stratA)), 5000, type(uint256).max);
        vault.addStrategy(IStrategy(address(stratB)), 5000, type(uint256).max);
    }

    function _deployMockStrategyFor(CollateralVault vault, IERC20 underlying) internal returns (MockStrategy strategy) {
        return _deployMockStrategyFor(vault, underlying, address(this));
    }

    function _deployMockStrategyFor(CollateralVault vault, IERC20 underlying, address strategyAdmin)
        internal
        returns (MockStrategy strategy)
    {
        MockStrategy impl = new MockStrategy();
        bytes memory init =
            abi.encodeWithSelector(MockStrategy.initialize.selector, address(vault), underlying, strategyAdmin);
        strategy = MockStrategy(address(new ERC1967Proxy(address(impl), init)));
    }

    function _deployDTokenForHandover(address vaultAddress) internal returns (DToken dToken) {
        DToken dTokenImpl = new DToken();
        bytes memory dTokenInit = abi.encodeWithSelector(DToken.initialize.selector, vaultAddress, address(this));
        dToken = DToken(address(new ERC1967Proxy(address(dTokenImpl), dTokenInit)));
    }

    function _deployFrozenActiveYieldLayer()
        internal
        returns (MockERC20 underlying, DToken dToken, CollateralVault vault)
    {
        underlying = new MockERC20("Mock USDC", "mUSDC", 6);
        YieldLayerProxyDeployer helper =
            new YieldLayerProxyDeployer(address(new DToken()), address(new CollateralVault()));
        (dToken, vault) = helper.deployYieldLayer(
            IERC20MetadataUpgradeable(address(underlying)),
            "dMock USDC",
            "dmUSDC",
            makeAddr("handoverVaultTreasury"),
            address(prepare)
        );
        assertEq(dToken.cap(), 0, "deploy helper freezes active branch");
        prepare.acceptDTokenOwnershipForHarness(dToken);
        assertEq(dToken.owner(), address(prepare), "prepare harness owns dToken");
        MockDTokenRegistry registry = new MockDTokenRegistry(address(dToken), true);
        vm.prank(address(prepare));
        dToken.setRiskParamsRegistry(address(registry));
    }

    function _setActiveBranchParameterEnv(uint256 branchIndex, uint256 cap, uint256 bufferTargetBps) internal {
        string memory suffix = vm.toString(branchIndex);
        vm.setEnv(string.concat("DF_DTOKEN_CAP_", suffix), vm.toString(cap));
        vm.setEnv(string.concat("DF_ALLOCATE_MAX_MOVE_", suffix), "1000000");
        vm.setEnv(string.concat("DF_BUFFER_TARGET_BPS_", suffix), vm.toString(bufferTargetBps));
        vm.setEnv(string.concat("DF_BUFFER_FLOOR_", suffix), "0");
        vm.setEnv(string.concat("DF_WITHDRAW_DELAY_", suffix), "259200");
        vm.setEnv(string.concat("DF_ALLOCATOR_COOLDOWN_", suffix), "1800");
    }
}
