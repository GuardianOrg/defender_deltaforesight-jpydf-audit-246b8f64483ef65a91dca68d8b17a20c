// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../script/DeployLiquity2.s.sol";

contract DeployBranchRiskInvariantsHarness is DeployLiquity2Script {
    function requireBranchRiskInvariants(TroveManagerParams[] memory _params) external pure {
        _requireBranchRiskInvariants(_params);
    }

    function dfBranchParams() external pure returns (TroveManagerParams[] memory params) {
        (params,,) = _dfBranchParams();
    }

    function collGasCompensationCap(uint256 branchIndex) external pure returns (uint256) {
        return _collGasCompensationCap(branchIndex);
    }

    function dfDTokenSlot(uint256 branchIndex) external pure returns (string memory) {
        return _dfDTokenSlot(branchIndex);
    }
}

/// @notice Guards the deploy-time PRM-INV machine checks (Parameter-Catalog §PRM-INV-*).
///
/// Branch risk parameters are immutable once deployed, and this preflight is the last machine
/// check before they are burned in, so each invariant needs a test that fails when the guard
/// stops enforcing it.
contract DeployBranchRiskInvariantsTest is Test {
    DeployBranchRiskInvariantsHarness internal harness;

    uint256 internal constant PCT = 1e16;

    function setUp() public {
        harness = new DeployBranchRiskInvariantsHarness();
    }

    /// @dev A branch that satisfies every published invariant, used as the mutation base.
    function _validParams() internal pure returns (DeployLiquity2Script.TroveManagerParams[] memory params) {
        params = new DeployLiquity2Script.TroveManagerParams[](1);
        params[0] = DeployLiquity2Script.TroveManagerParams({
            CCR: 14167 * PCT / 100,
            MCR: 12318 * PCT / 100,
            SCR: 110 * PCT,
            BCR: 10 * PCT,
            LIQUIDATION_PENALTY_SP: 5 * PCT,
            LIQUIDATION_PENALTY_REDISTRIBUTION: 10 * PCT
        });
    }

    function test_Day1BranchParamsSatisfyEveryInvariant() external view {
        harness.requireBranchRiskInvariants(harness.dfBranchParams());
    }

    function test_GuardianL03_Day1BranchGasCaps() external view {
        assertEq(harness.collGasCompensationCap(0), 2 ether);
        assertEq(harness.collGasCompensationCap(1), 1000 ether);
        for (uint256 i = 2; i < 8; ++i) {
            assertEq(harness.collGasCompensationCap(i), 1000 ether, "reserved bootstrap cap");
        }
    }

    function test_Day1ManifestSlotLabelsMatchOwnerDecision() external view {
        assertEq(harness.dfDTokenSlot(0), "dwstETH");
        assertEq(harness.dfDTokenSlot(1), "dUSDC");
        assertEq(harness.dfDTokenSlot(2), "dETH");
        assertEq(harness.dfDTokenSlot(3), "dUSD-A");
        assertEq(harness.dfDTokenSlot(4), "dBTC");
        assertEq(harness.dfDTokenSlot(5), "dUSD-B");
        assertEq(harness.dfDTokenSlot(6), "dJPY");
        assertEq(harness.dfDTokenSlot(7), "dJGB");
    }

    function test_RevertWhen_ManifestSlotIndexIsOutOfBounds() external {
        vm.expectRevert("DF: branch slot");
        harness.dfDTokenSlot(8);
    }

    function test_ValidParamsAreAccepted() external view {
        harness.requireBranchRiskInvariants(_validParams());
    }

    // PRM-INV-006: the bound is on SCR, not MCR.
    function test_RevertWhen_ScrBelowUrgentRedemptionBonus() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].SCR = 101 * PCT;

        // The parameters stay otherwise valid, and crucially MCR is still far above the bound, so
        // a guard that compares MCR would accept this set.
        assertLt(params[0].SCR, DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS, "SCR is under the bound");
        assertGt(params[0].MCR, DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS, "MCR is still above the bound");
        assertLt(params[0].SCR, params[0].MCR, "CR ordering still holds");

        vm.expectRevert("DF: PRM-INV 1+urgentBonus <= SCR");
        harness.requireBranchRiskInvariants(params);
    }

    function test_ScrExactlyAtTheBoundIsAccepted() external view {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].SCR = DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS;

        harness.requireBranchRiskInvariants(params);
    }

    // PRM-INV-001
    function test_RevertWhen_CrOrderingBroken() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].SCR = params[0].MCR;

        vm.expectRevert("DF: PRM-INV CR ordering");
        harness.requireBranchRiskInvariants(params);
    }

    // PRM-INV-004
    function test_RevertWhen_SpPenaltyLeavesNoMcrMargin() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].LIQUIDATION_PENALTY_SP = 25 * PCT;
        params[0].LIQUIDATION_PENALTY_REDISTRIBUTION = 25 * PCT;

        vm.expectRevert("DF: PRM-INV SP coverage after gas compensation");
        harness.requireBranchRiskInvariants(params);
    }

    function test_GuardianL04_ExactSpCoverageBoundary() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].SCR = 103e16;
        params[0].LIQUIDATION_PENALTY_REDISTRIBUTION = params[0].LIQUIDATION_PENALTY_SP;
        uint256 numerator = (1e18 + params[0].LIQUIDATION_PENALTY_SP) * COLL_GAS_COMPENSATION_DIVISOR;
        uint256 divisor = COLL_GAS_COMPENSATION_DIVISOR - 1;
        params[0].MCR = (numerator + divisor - 1) / divisor;
        harness.requireBranchRiskInvariants(params);
        params[0].MCR -= 1;
        vm.expectRevert("DF: PRM-INV SP coverage after gas compensation");
        harness.requireBranchRiskInvariants(params);
        params[0].MCR = 10530e14;
        vm.expectRevert("DF: PRM-INV SP coverage after gas compensation");
        harness.requireBranchRiskInvariants(params);
    }

    function test_GuardianI09_RedistributionCoverageBoundary() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].SCR = 103e16;
        params[0].LIQUIDATION_PENALTY_REDISTRIBUTION = 20e16;
        params[0].MCR = 110e16;
        vm.expectRevert("DF: PRM-INV 1+penaltyRedistribution <= MCR");
        harness.requireBranchRiskInvariants(params);
        params[0].MCR = 120e16 - 1;
        vm.expectRevert("DF: PRM-INV 1+penaltyRedistribution <= MCR");
        harness.requireBranchRiskInvariants(params);
        params[0].MCR = 120e16;
        harness.requireBranchRiskInvariants(params);
    }

    // PRM-INV-003
    function test_RevertWhen_SpPenaltyExceedsRedistribution() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = _validParams();
        params[0].LIQUIDATION_PENALTY_SP = 11 * PCT;

        vm.expectRevert("DF: PRM-INV penalty ordering");
        harness.requireBranchRiskInvariants(params);
    }

    /// @dev The loop must reach every branch, not just the first one.
    function test_RevertWhen_ALaterBranchViolatesAnInvariant() external {
        DeployLiquity2Script.TroveManagerParams[] memory params = new DeployLiquity2Script.TroveManagerParams[](2);
        params[0] = _validParams()[0];
        params[1] = _validParams()[0];
        params[1].SCR = 101 * PCT;

        vm.expectRevert("DF: PRM-INV 1+urgentBonus <= SCR");
        harness.requireBranchRiskInvariants(params);
    }
}
