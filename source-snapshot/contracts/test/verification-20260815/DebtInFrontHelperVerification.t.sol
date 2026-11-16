// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DebtInFrontHelper} from "src/DebtInFrontHelper.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

/// @notice Focused execution evidence for DebtInFrontHelper read-only and error paths.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract DebtInFrontHelperVerification is DevTestSetup {
    function testRangeAndStopQueriesAreReadOnlyAndNonCustodial() external {
        DebtInFrontHelper helper = new DebtInFrontHelper(collateralRegistry, hintHelpers);
        uint256 troveId = openTroveNoHints100pct(A, 15_000e18, 750_000e18, 5e16);
        uint256 recordedDebtBefore = troveManager.getTroveDebt(troveId);
        uint256 helperCollBalanceBefore = collToken.balanceOf(address(helper));
        uint256 helperJpydfBalanceBefore = jpydfToken.balanceOf(address(helper));

        (uint256 rangeDebt, uint256 rangeTimestamp) = helper.getDebtBetweenInterestRates(0, 1e16, 10e16, 0, 0, 0);
        (uint256 debtBeforeTrove, uint256 stopTimestamp) =
            helper.getDebtBetweenInterestRateAndTrove(0, 1e16, 10e16, troveId, 0, 0);

        assertEq(rangeDebt, troveManager.getTroveEntireDebt(troveId), "range includes active trove");
        assertEq(debtBeforeTrove, 0, "stop trove is excluded");
        assertEq(rangeTimestamp, block.timestamp, "range timestamp");
        assertEq(stopTimestamp, block.timestamp, "stop timestamp");
        assertEq(troveManager.getTroveDebt(troveId), recordedDebtBefore, "queries do not mutate troves");
        assertEq(collToken.balanceOf(address(helper)), helperCollBalanceBefore, "helper retains no collateral");
        assertEq(jpydfToken.balanceOf(address(helper)), helperJpydfBalanceBefore, "helper retains no JPYdf");
    }

    function testInvalidCollateralIndexRevertsForBothQuerySurfaces() external {
        DebtInFrontHelper helper = new DebtInFrontHelper(collateralRegistry, hintHelpers);

        vm.expectRevert("Invalid collateral index");
        helper.getDebtBetweenInterestRates(1, 1e16, 10e16, 0, 0, 0);

        vm.expectRevert("Invalid collateral index");
        helper.getDebtBetweenInterestRateAndTrove(1, 1e16, 10e16, 0, 0, 0);
    }
}
