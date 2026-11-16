// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MultiTroveGetter} from "src/MultiTroveGetter.sol";
import {IMultiTroveGetter} from "src/Interfaces/IMultiTroveGetter.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

contract MultiTroveGetterVerification is DevTestSetup {
    MultiTroveGetter internal getter;

    function setUp() public override {
        super.setUp();
        getter = new MultiTroveGetter(collateralRegistry);
    }

    function testReadsSortedTroveSlicesFromHeadAndTail() public {
        (uint256 lowRateId, uint256 middleRateId, uint256 highRateId) = _openThreeTroves();

        IMultiTroveGetter.CombinedTroveData[] memory fromHead = getter.getMultipleSortedTroves(0, 0, 2);
        assertEq(fromHead.length, 2, "head slice length");
        assertEq(fromHead[0].id, highRateId, "head first id");
        assertEq(fromHead[1].id, middleRateId, "head second id");
        assertEq(fromHead[0].annualInterestRate, 3e16, "head first rate");
        assertEq(fromHead[1].annualInterestRate, 2e16, "head second rate");
        assertEq(fromHead[0].entireDebt, troveManager.getTroveEntireDebt(highRateId), "head debt");
        assertEq(fromHead[1].entireColl, troveManager.getTroveEntireColl(middleRateId), "head collateral");

        IMultiTroveGetter.CombinedTroveData[] memory fromTail = getter.getMultipleSortedTroves(0, -1, 2);
        assertEq(fromTail.length, 2, "tail slice length");
        assertEq(fromTail[0].id, lowRateId, "tail first id");
        assertEq(fromTail[1].id, middleRateId, "tail second id");

        assertEq(getter.getMultipleSortedTroves(0, 3, 1).length, 0, "out of range is empty");
        assertEq(getter.getMultipleSortedTroves(0, 0, 0).length, 0, "zero count is empty");
    }

    function testReturnsDebtDistributionAscendingAndResumesAtCursor() public {
        (uint256 lowRateId, uint256 middleRateId, uint256 highRateId) = _openThreeTroves();

        (IMultiTroveGetter.DebtPerInterestRate[] memory data, uint256 cursor) =
            getter.getDebtPerInterestRateAscending(0, 0, 4);
        assertEq(data.length, 4, "requested allocation length");
        assertEq(data[0].interestRate, 1e16, "lowest rate first");
        assertEq(data[1].interestRate, 2e16, "middle rate second");
        assertEq(data[2].interestRate, 3e16, "highest rate third");
        assertEq(data[0].debt, troveManager.getTroveEntireDebt(lowRateId), "low debt");
        assertEq(data[1].debt, troveManager.getTroveEntireDebt(middleRateId), "middle debt");
        assertEq(data[2].debt, troveManager.getTroveEntireDebt(highRateId), "high debt");
        assertEq(cursor, 0, "completed cursor");
        assertEq(data[3].debt, 0, "unused trailing item remains zero");

        (IMultiTroveGetter.DebtPerInterestRate[] memory resumed, uint256 nextCursor) =
            getter.getDebtPerInterestRateAscending(0, middleRateId, 1);
        assertEq(resumed[0].interestRate, 2e16, "explicit cursor starts at requested id");
        assertEq(nextCursor, highRateId, "cursor advances toward higher rate");
    }

    function testInvalidCollateralIndexReverts() public {
        vm.expectRevert("Invalid collateral index");
        getter.getMultipleSortedTroves(1, 0, 1);

        vm.expectRevert("Invalid collateral index");
        getter.getDebtPerInterestRateAscending(1, 0, 1);
    }

    function testQueriesAreReadOnlyAndNonCustodial() public {
        (, uint256 middleRateId,) = _openThreeTroves();
        uint256 recordedDebtBefore = troveManager.getTroveDebt(middleRateId);
        uint256 collBalanceBefore = collToken.balanceOf(address(getter));
        uint256 jpydfBalanceBefore = jpydfToken.balanceOf(address(getter));

        getter.getMultipleSortedTroves(0, 0, 3);
        getter.getDebtPerInterestRateAscending(0, 0, 3);

        assertEq(address(getter.collateralRegistry()), address(collateralRegistry), "registry reference remains configured");
        assertEq(troveManager.getTroveDebt(middleRateId), recordedDebtBefore, "queries do not mutate troves");
        assertEq(collToken.balanceOf(address(getter)), collBalanceBefore, "getter retains no collateral");
        assertEq(jpydfToken.balanceOf(address(getter)), jpydfBalanceBefore, "getter retains no JPYdf");
    }

    function _openThreeTroves() internal returns (uint256 lowRateId, uint256 middleRateId, uint256 highRateId) {
        (lowRateId,) = openTroveWithExactICRAndDebt(A, 0, 2 * CCR, 300000 ether, 1e16);
        (middleRateId,) = openTroveWithExactICRAndDebt(B, 0, 2 * CCR, 300000 ether, 2e16);
        (highRateId,) = openTroveWithExactICRAndDebt(C, 0, 2 * CCR, 300000 ether, 3e16);
    }
}
