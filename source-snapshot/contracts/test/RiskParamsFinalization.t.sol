// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "../src/AddressesRegistry.sol";
import "../src/BorrowerOperations.sol";
import "../src/StabilityPool.sol";
import "../src/TroveManager.sol";
import "../src/Interfaces/IAddressesRegistry.sol";
import "../src/Interfaces/IBorrowerOperations.sol";
import "../src/Interfaces/ICollateralVault.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/ILiquityBase.sol";
import "../src/Interfaces/ITroveManager.sol";
import {MIN_LIQUIDATION_PENALTY_SP, MAX_LIQUIDATION_PENALTY_REDISTRIBUTION} from "../src/Dependencies/Constants.sol";
import "./TestContracts/Deployment.t.sol";
import "./TestContracts/Interfaces/IBorrowerOperationsTester.sol";
import "./TestContracts/Interfaces/ITroveManagerTester.sol";
import "./mocks/MockERC20.sol";

contract RiskParamsVaultMock {
    IERC20 public underlying;
    IDToken public dToken;

    constructor(IDToken _dToken, IERC20 _underlying) {
        dToken = _dToken;
        underlying = _underlying;
    }

    function setUnderlying(IERC20 _underlying) external {
        underlying = _underlying;
    }

    function setDToken(IDToken _dToken) external {
        dToken = _dToken;
    }
}

/// @notice Focused lifecycle tests for a reserved branch's one-shot risk finalization.
/// @dev The full Liquity branch is deployed through TestDeployer. Only the deferred
///      DToken/Vault read surface is mocked because the dev deployer otherwise uses WETH.
contract RiskParamsFinalizationTest is Test {
    address internal finalizer = makeAddr("risk finalizer");
    address internal attacker = makeAddr("attacker");

    AddressesRegistry internal registry;
    IBorrowerOperationsTester internal borrowerOperations;
    ITroveManagerTester internal troveManager;
    IActivePool internal activePool;
    IStabilityPool internal stabilityPool;
    IERC20Metadata internal dToken;
    MockERC20 internal expectedUnderlying;
    MockERC20 internal otherUnderlying;
    RiskParamsVaultMock internal vault;

    function setUp() public {
        vm.warp(1 days);

        TestDeployer deployer = new TestDeployer();
        deployer.setRiskParamsFinalizer(finalizer);

        TestDeployer.LiquityContractsDev memory branch;
        (branch,,,,,,) = deployer.deployAndConnectContracts();

        registry = AddressesRegistry(address(branch.addressesRegistry));
        borrowerOperations = branch.borrowerOperations;
        troveManager = branch.troveManager;
        activePool = branch.activePool;
        stabilityPool = branch.stabilityPool;
        dToken = branch.collToken;

        expectedUnderlying = new MockERC20("Expected", "EXP", 6);
        otherUnderlying = new MockERC20("Other", "OTHER", 8);
        vault = new RiskParamsVaultMock(IDToken(address(dToken)), IERC20(address(expectedUnderlying)));
        _mockDTokenState(address(expectedUnderlying), address(vault), 0, 0);
    }

    function _validParams() internal pure returns (RiskParams memory) {
        return RiskParams({
            CCR: 160e16,
            MCR: 125e16,
            BCR: 12e16,
            SCR: 110e16,
            LIQUIDATION_PENALTY_SP: 6e16,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 10e16,
            COLL_GAS_COMPENSATION_CAP: 2 ether
        });
    }

    function _mockDTokenState(address _underlying, address _vault, uint256 _cap, uint256 _supply) internal {
        vm.mockCall(address(dToken), abi.encodeWithSelector(IDToken.underlying.selector), abi.encode(_underlying));
        vm.mockCall(address(dToken), abi.encodeWithSelector(IDToken.vault.selector), abi.encode(_vault));
        vm.mockCall(address(dToken), abi.encodeWithSelector(IDToken.cap.selector), abi.encode(_cap));
        vm.mockCall(address(dToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(_supply));
    }

    function _finalize(RiskParams memory _params) internal {
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), _params);
    }

    function _expectFinalizationRevert(RiskParams memory _params) internal {
        vm.prank(finalizer);
        vm.expectRevert();
        registry.finalizeRiskParams(address(expectedUnderlying), _params);
        assertFalse(registry.riskParamsFinalized(), "failed finalization changed lifecycle");
    }

    function test_GuardianI09_RedistributionCoverageBoundary() public {
        RiskParams memory params = _validParams();
        params.SCR = 103e16;
        params.LIQUIDATION_PENALTY_SP = 5e16;
        params.LIQUIDATION_PENALTY_REDISTRIBUTION = 20e16;
        params.MCR = 110e16;
        vm.expectRevert(AddressesRegistry.MCRBelowRedistributionPenalty.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        params.MCR = 120e16 - 1;
        vm.expectRevert(AddressesRegistry.MCRBelowRedistributionPenalty.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        assertFalse(registry.riskParamsFinalized());
        params.MCR = 120e16;
        _finalize(params);
        assertEq(registry.MCR(), params.MCR);
        assertEq(troveManager.get_LIQUIDATION_PENALTY_REDISTRIBUTION(), 20e16);
    }

    function test_GuardianL04_ExactSpCoverageBoundary() public {
        RiskParams memory params = _validParams();
        params.SCR = 103e16;
        params.LIQUIDATION_PENALTY_SP = 5e16;
        params.LIQUIDATION_PENALTY_REDISTRIBUTION = 5e16;
        params.MCR = 10530e14;
        vm.expectRevert(AddressesRegistry.MCRBelowSPPenalty.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        uint256 numerator = (1e18 + params.LIQUIDATION_PENALTY_SP) * COLL_GAS_COMPENSATION_DIVISOR;
        uint256 divisor = COLL_GAS_COMPENSATION_DIVISOR - 1;
        uint256 boundary = (numerator + divisor - 1) / divisor;
        params.MCR = boundary - 1;
        vm.expectRevert(AddressesRegistry.MCRBelowSPPenalty.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        assertFalse(registry.riskParamsFinalized());
        params.MCR = boundary;
        _finalize(params);
        assertEq(registry.MCR(), boundary);
        assertEq(troveManager.get_MCR(), boundary);
    }

    function test_FinalizerIsAuthorizedAndFinalizationIsOneShot() public {
        assertEq(registry.riskParamsFinalizer(), finalizer);
        assertFalse(registry.riskParamsFinalized());

        vm.prank(attacker);
        vm.expectRevert(AddressesRegistry.CallerNotRiskParamsFinalizer.selector);
        registry.finalizeRiskParams(address(expectedUnderlying), _validParams());

        _finalize(_validParams());
        assertTrue(registry.riskParamsFinalized());

        vm.prank(finalizer);
        vm.expectRevert(AddressesRegistry.RiskParamsAlreadyFinalized.selector);
        registry.finalizeRiskParams(address(expectedUnderlying), _validParams());
    }

    function test_ZeroFinalizerPreservesDeployTimeFinalizedBranches() public {
        AddressesRegistry finalizedRegistry =
            new AddressesRegistry(address(this), 160e16, 125e16, 12e16, 110e16, 6e16, 10e16, address(0));

        assertEq(finalizedRegistry.riskParamsFinalizer(), address(0));
        assertTrue(finalizedRegistry.riskParamsFinalized());
    }

    function test_FinalizationSynchronizesRiskParamsAndGasCap() public {
        RiskParams memory params = _validParams();
        assertEq(troveManager.getCollGasCompensation(1_000_000 ether), 1000 ether, "bootstrap cap");

        vm.expectEmit(true, false, false, true, address(registry));
        emit AddressesRegistry.RiskParamsFinalized(
            address(expectedUnderlying),
            params.CCR,
            params.MCR,
            params.BCR,
            params.SCR,
            params.LIQUIDATION_PENALTY_SP,
            params.LIQUIDATION_PENALTY_REDISTRIBUTION,
            params.COLL_GAS_COMPENSATION_CAP
        );
        _finalize(params);

        assertEq(registry.CCR(), params.CCR);
        assertEq(registry.MCR(), params.MCR);
        assertEq(registry.BCR(), params.BCR);
        assertEq(registry.SCR(), params.SCR);
        assertEq(registry.LIQUIDATION_PENALTY_SP(), params.LIQUIDATION_PENALTY_SP);
        assertEq(registry.LIQUIDATION_PENALTY_REDISTRIBUTION(), params.LIQUIDATION_PENALTY_REDISTRIBUTION);

        BorrowerOperations bo = BorrowerOperations(address(borrowerOperations));
        assertEq(bo.CCR(), params.CCR);
        assertEq(bo.MCR(), params.MCR);
        assertEq(bo.BCR(), params.BCR);
        assertEq(bo.SCR(), params.SCR);

        assertEq(troveManager.get_CCR(), params.CCR);
        assertEq(troveManager.get_MCR(), params.MCR);
        assertEq(troveManager.get_SCR(), params.SCR);
        assertEq(troveManager.get_LIQUIDATION_PENALTY_SP(), params.LIQUIDATION_PENALTY_SP);
        assertEq(troveManager.get_LIQUIDATION_PENALTY_REDISTRIBUTION(), params.LIQUIDATION_PENALTY_REDISTRIBUTION);
        assertEq(troveManager.getCollGasCompensation(1_000_000 ether), params.COLL_GAS_COMPENSATION_CAP);
    }

    function test_GuardianL03_FinalizationRejectsInvalidGasCaps() public {
        RiskParams memory params = _validParams();
        params.COLL_GAS_COMPENSATION_CAP = 0;
        vm.expectRevert(AddressesRegistry.InvalidCollGasCompensationCap.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        params.COLL_GAS_COMPENSATION_CAP = 1000 ether + 1;
        vm.expectRevert(AddressesRegistry.InvalidCollGasCompensationCap.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        assertFalse(registry.riskParamsFinalized());
        assertEq(troveManager.getCollGasCompensation(1_000_000 ether), 1000 ether);
    }

    function testFuzz_GuardianL03_CapFinalizesOnceAndCannotChange(uint256 cap) public {
        RiskParams memory params = _validParams();
        params.COLL_GAS_COMPENSATION_CAP = bound(cap, 1, 1000 ether);
        _finalize(params);
        assertEq(troveManager.getCollGasCompensation(1_000_000 ether), params.COLL_GAS_COMPENSATION_CAP);
        assertEq(troveManager.getCollGasCompensation(0), 0);
        params.COLL_GAS_COMPENSATION_CAP = params.COLL_GAS_COMPENSATION_CAP == 1 ? 2 : 1;
        vm.expectRevert(AddressesRegistry.RiskParamsAlreadyFinalized.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);
        assertNotEq(troveManager.getCollGasCompensation(1_000_000 ether), params.COLL_GAS_COMPENSATION_CAP);
    }

    function test_FinalizationRejectsEveryCrossParameterInvariant() public {
        RiskParams memory params = _validParams();
        params.SCR = params.MCR;
        vm.expectRevert(AddressesRegistry.InvalidCollateralRatioOrder.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.MCR = params.CCR;
        vm.expectRevert(AddressesRegistry.InvalidCollateralRatioOrder.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.MCR = 119e16;
        params.LIQUIDATION_PENALTY_SP = 20e16;
        params.LIQUIDATION_PENALTY_REDISTRIBUTION = 20e16;
        vm.expectRevert(AddressesRegistry.MCRBelowSPPenalty.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.LIQUIDATION_PENALTY_SP = 11e16;
        vm.expectRevert(AddressesRegistry.SPPenaltyGtRedist.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.SCR = 101e16;
        vm.expectRevert(AddressesRegistry.SCRBelowUrgentRedemptionBonus.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        assertFalse(registry.riskParamsFinalized());
    }

    function test_FinalizationRejectsEveryConstructorRange() public {
        RiskParams memory params = _validParams();
        params.CCR = 1e18;
        vm.expectRevert(AddressesRegistry.InvalidCCR.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.MCR = 2e18;
        vm.expectRevert(AddressesRegistry.InvalidMCR.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.BCR = 5e16 - 1;
        vm.expectRevert(AddressesRegistry.InvalidBCR.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.SCR = 2e18;
        vm.expectRevert(AddressesRegistry.InvalidSCR.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.LIQUIDATION_PENALTY_SP = MIN_LIQUIDATION_PENALTY_SP - 1;
        vm.expectRevert(AddressesRegistry.SPPenaltyTooLow.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        params = _validParams();
        params.LIQUIDATION_PENALTY_REDISTRIBUTION = MAX_LIQUIDATION_PENALTY_REDISTRIBUTION + 1;
        vm.expectRevert(AddressesRegistry.RedistPenaltyTooHigh.selector);
        vm.prank(finalizer);
        registry.finalizeRiskParams(address(expectedUnderlying), params);

        assertFalse(registry.riskParamsFinalized());
    }

    function test_FinalizationRequiresDTokenAndVaultBoundToExpectedUnderlying() public {
        vm.prank(finalizer);
        vm.expectRevert(AddressesRegistry.InvalidExpectedUnderlying.selector);
        registry.finalizeRiskParams(address(0), _validParams());

        vm.prank(finalizer);
        vm.expectRevert(AddressesRegistry.InvalidExpectedUnderlying.selector);
        registry.finalizeRiskParams(attacker, _validParams());

        _mockDTokenState(address(0), address(vault), 0, 0);
        _expectFinalizationRevert(_validParams());

        _mockDTokenState(address(otherUnderlying), address(vault), 0, 0);
        _expectFinalizationRevert(_validParams());

        _mockDTokenState(address(expectedUnderlying), address(vault), 0, 0);
        vault.setUnderlying(IERC20(address(otherUnderlying)));
        _expectFinalizationRevert(_validParams());

        vault.setUnderlying(IERC20(address(expectedUnderlying)));
        vault.setDToken(IDToken(address(otherUnderlying)));
        _expectFinalizationRevert(_validParams());
    }

    function test_FinalizationRejectsNonzeroCapOrSupply() public {
        _mockDTokenState(address(expectedUnderlying), address(vault), 1, 0);
        _expectFinalizationRevert(_validParams());

        _mockDTokenState(address(expectedUnderlying), address(vault), 0, 1);
        _expectFinalizationRevert(_validParams());
    }

    function test_FinalizationRejectsNonemptyCoreState() public {
        vm.mockCall(
            address(troveManager), abi.encodeWithSelector(ITroveManager.getTroveIdsCount.selector), abi.encode(1)
        );
        _expectFinalizationRevert(_validParams());

        vm.mockCall(
            address(troveManager), abi.encodeWithSelector(ITroveManager.getTroveIdsCount.selector), abi.encode(0)
        );
        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(ILiquityBase.getEntireBranchDebt.selector),
            abi.encode(1)
        );
        _expectFinalizationRevert(_validParams());

        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(ILiquityBase.getEntireBranchDebt.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(ILiquityBase.getEntireBranchColl.selector),
            abi.encode(1)
        );
        _expectFinalizationRevert(_validParams());

        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(ILiquityBase.getEntireBranchColl.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(stabilityPool), abi.encodeWithSelector(IStabilityPool.getTotalJpydfDeposits.selector), abi.encode(1)
        );
        vm.prank(finalizer);
        vm.expectRevert(abi.encodeWithSelector(AddressesRegistry.StabilityPoolNotEmpty.selector, 1));
        registry.finalizeRiskParams(address(expectedUnderlying), _validParams());
        assertFalse(registry.riskParamsFinalized(), "failed finalization changed lifecycle");
    }

    function test_FinalizationRejectsEveryShutdownState() public {
        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(IBorrowerOperations.isOracleFailureShutdown.selector),
            abi.encode(true)
        );
        _expectFinalizationRevert(_validParams());

        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(IBorrowerOperations.isOracleFailureShutdown.selector),
            abi.encode(false)
        );
        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(IBorrowerOperations.hasBeenShutDown.selector),
            abi.encode(true)
        );
        _expectFinalizationRevert(_validParams());

        vm.mockCall(
            address(borrowerOperations),
            abi.encodeWithSelector(IBorrowerOperations.hasBeenShutDown.selector),
            abi.encode(false)
        );
        vm.mockCall(address(troveManager), abi.encodeWithSelector(ITroveManager.shutdownTime.selector), abi.encode(1));
        _expectFinalizationRevert(_validParams());

        vm.mockCall(address(troveManager), abi.encodeWithSelector(ITroveManager.shutdownTime.selector), abi.encode(0));
        vm.mockCall(address(activePool), abi.encodeWithSelector(IActivePool.hasBeenShutDown.selector), abi.encode(true));
        _expectFinalizationRevert(_validParams());
    }

    function test_ReversibleOraclePauseCanRecoverThenFinalize() public {
        address priceFeed = address(registry.priceFeed());
        vm.prank(priceFeed);
        borrowerOperations.shutdownFromOracleFailure();

        vm.prank(finalizer);
        vm.expectRevert(AddressesRegistry.OracleFailureShutdownActive.selector);
        registry.finalizeRiskParams(address(expectedUnderlying), _validParams());

        vm.prank(priceFeed);
        borrowerOperations.resumeFromOracleFailure();
        _finalize(_validParams());

        assertTrue(registry.riskParamsFinalized());
        assertFalse(borrowerOperations.isOracleFailureShutdown());
        assertFalse(borrowerOperations.hasBeenShutDown());
    }

    function test_EmptyReservedBranchCannotEnterTerminalShutdown() public {
        vm.expectRevert(BorrowerOperations.TCRNotBelowSCR.selector);
        borrowerOperations.shutdown();

        assertFalse(borrowerOperations.hasBeenShutDown());
        assertEq(troveManager.shutdownTime(), 0);
        assertFalse(activePool.hasBeenShutDown());
    }

    function test_OnlyRegistryCanSynchronizeChildCopies() public {
        vm.prank(attacker);
        vm.expectRevert(BorrowerOperations.CallerNotAddressesRegistry.selector);
        borrowerOperations.syncRiskParams(0, 0, 0, 0);

        vm.prank(attacker);
        vm.expectRevert(TroveManager.CallerNotAddressesRegistry.selector);
        troveManager.syncRiskParams(_validParams());
    }

    function test_ChildSyncFailureRollsBackRegistryAndOtherChild() public {
        RiskParams memory params = _validParams();
        uint256 oldRegistryCCR = registry.CCR();
        uint256 oldBorrowerOperationsCCR = BorrowerOperations(address(borrowerOperations)).CCR();
        uint256 oldTroveManagerCCR = troveManager.get_CCR();

        vm.mockCallRevert(
            address(troveManager), abi.encodeCall(ITroveManager.syncRiskParams, (params)), bytes("sync failed")
        );
        _expectFinalizationRevert(params);

        assertEq(registry.CCR(), oldRegistryCCR);
        assertEq(BorrowerOperations(address(borrowerOperations)).CCR(), oldBorrowerOperationsCCR);
        assertEq(troveManager.get_CCR(), oldTroveManagerCCR);
    }

    function test_UnfinalizedBranchCannotOpenTrove() public {
        vm.prank(attacker);
        vm.expectRevert(BorrowerOperations.RiskParamsNotFinalized.selector);
        borrowerOperations.openTrove(
            attacker, 0, 1 ether, 2_000e18, 0, 0, 5e16, type(uint256).max, address(0), address(0), address(0)
        );
    }

    function test_UnfinalizedBranchCannotAcceptStabilityPoolDeposit() public {
        vm.expectRevert(IStabilityPool.RiskParamsNotFinalized.selector);
        stabilityPool.provideToSP(1, false);

        IStabilityPool legacyStabilityPool = IStabilityPool(address(new StabilityPool(registry)));
        vm.expectRevert(IStabilityPool.RiskParamsNotFinalized.selector);
        legacyStabilityPool.provideToSP(1, false);
    }

    function test_FinalizedBranchPassesStabilityPoolLifecycleGuard() public {
        _finalize(_validParams());

        IJpydfToken jpydfToken = registry.jpydfToken();
        vm.prank(address(activePool));
        jpydfToken.mint(attacker, 1);
        vm.prank(attacker);
        stabilityPool.provideToSP(1, false);

        assertEq(stabilityPool.getCompoundedJpydfDeposit(attacker), 1);
        assertEq(stabilityPool.getTotalJpydfDeposits(), 1);
    }
}
