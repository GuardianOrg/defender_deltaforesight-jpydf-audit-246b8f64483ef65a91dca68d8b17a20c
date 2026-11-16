// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DevTestSetup} from "./TestContracts/DevTestSetup.sol";
import {DFStabilityPool} from "../src/DFStabilityPool.sol";
import {console2} from "forge-std/console2.sol";

// External audit Low 07 evidence: `SCALE_SPAN = 2` stops counting coll/yield gains
// more than two scale changes past a deposit's snapshot scale. This measures the
// omitted tail directly by replaying the same gain formula with the full
// `MAX_SCALE_FACTOR_EXPONENT` span, after driving four scale changes.
contract ExternalAuditLow07ScaleSpanTest is DevTestSetup {
    uint256 internal constant MIN_JPYDF_IN_SP = 1e18;
    uint256 internal constant RESTOCK = 2e27;
    address internal constant ALICE = address(0xA11CE);

    function test_RealisticFourScaleTailRoundsToZero() external {
        _runScaleSequence(10_000e18, 100_000e18, false);
    }

    function test_ExtremeFourScaleTailIsBoundedDust() external {
        _runScaleSequence(1e32, 1e32, true);
    }

    function _runScaleSequence(uint256 aliceDeposit, uint256 collateralPerRound, bool expectNonZeroTail) internal {
        _fundActivePoolCollateral(collateralPerRound * 4);
        _deposit(address(0xBEEF), RESTOCK);
        _deposit(ALICE, aliceDeposit);

        for (uint256 round = 0; round < 4; ++round) {
            _deposit(address(uint160(0x1000 + round)), RESTOCK);

            // Accrue interest yield at every scale so the `scaleToB` tail is measured too.
            vm.prank(address(activePool));
            stabilityPool.triggerJpydfRewards(collateralPerRound / 100);

            uint256 totalDeposits = stabilityPool.getTotalJpydfDeposits();
            uint256 scaleBefore = stabilityPool.currentScale();
            vm.prank(address(troveManager));
            stabilityPool.offset(totalDeposits - MIN_JPYDF_IN_SP, collateralPerRound);
            assertGt(stabilityPool.currentScale(), scaleBefore, "expected a scale change");
        }

        assertGe(stabilityPool.currentScale(), 4, "expected four scale changes");

        uint256 spanTwoColl = stabilityPool.getDepositorCollGain(ALICE);
        uint256 spanTwoYield = stabilityPool.getDepositorYieldGain(ALICE);
        uint256 collTail = _fullSpanGain(ALICE, true) - spanTwoColl;
        uint256 yieldTail = _fullSpanGain(ALICE, false) - spanTwoYield;

        console2.log("scales", stabilityPool.currentScale());
        console2.log("SCALE_SPAN=2 coll gain", spanTwoColl);
        console2.log("omitted coll tail", collTail);
        console2.log("SCALE_SPAN=2 yield gain", spanTwoYield);
        console2.log("omitted yield tail", yieldTail);

        if (expectNonZeroTail) {
            assertGt(collTail, 0, "extreme coll tail should cross one wei");
            assertLt(collTail, spanTwoColl / 1e20, "coll tail must stay below 1e-20 of accrued gains");
            assertLt(yieldTail, spanTwoYield / 1e20 + 1, "yield tail must stay below 1e-20 of accrued gains");
        } else {
            assertEq(collTail, 0, "realistic omitted coll tail should round below one wei");
            assertEq(yieldTail, 0, "realistic omitted yield tail should round below one wei");
        }
    }

    function _deposit(address depositor, uint256 amount) internal {
        deal(address(jpydfToken), depositor, amount);
        vm.prank(depositor);
        stabilityPool.provideToSP(amount, false);
    }

    function _fundActivePoolCollateral(uint256 amount) internal {
        deal(address(collToken), address(activePool), amount);
        vm.prank(address(borrowerOperations));
        activePool.accountForReceivedColl(amount);
    }

    // Same formula as `getDepositorCollGain` / `getDepositorYieldGain`, but iterating the
    // whole representable span instead of stopping at `SCALE_SPAN`.
    function _fullSpanGain(address depositor, bool coll) internal view returns (uint256) {
        DFStabilityPool sp = DFStabilityPool(address(stabilityPool));
        uint256 initialDeposit = sp.deposits(depositor);
        (uint256 snapshotS, uint256 snapshotP, uint256 snapshotB, uint256 snapshotScale) =
            sp.depositSnapshots(depositor);

        uint256 snapshotSum = coll ? snapshotS : snapshotB;
        uint256 normalizedGains = _scaleSum(sp, snapshotScale, coll) - snapshotSum;
        for (uint256 i = 1; i <= sp.MAX_SCALE_FACTOR_EXPONENT(); ++i) {
            if (snapshotScale + i > sp.currentScale()) break;
            normalizedGains += _scaleSum(sp, snapshotScale + i, coll) / sp.SCALE_FACTOR() ** i;
        }

        uint256 gain = initialDeposit * normalizedGains / snapshotP;
        uint256 cap = coll ? sp.getCollBalance() : sp.getYieldGainsOwed();
        return gain < cap ? gain : cap;
    }

    function _scaleSum(DFStabilityPool sp, uint256 scale, bool coll) internal view returns (uint256) {
        return coll ? sp.scaleToS(scale) : sp.scaleToB(scale);
    }
}
