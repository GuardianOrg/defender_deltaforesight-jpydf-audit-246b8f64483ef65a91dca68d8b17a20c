// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestContracts/DevTestSetup.sol";

// Focused tests for the production JPYdf minimum-debt floor: MIN_DEBT = 100,000e18 (¥100,000).
//
// MIN_DEBT is enforced in BorrowerOperations.openTrove via `_requireAtLeastMinDebt(entireDebt)`,
// which runs BEFORE the collateral is pulled (`_pullCollAndSendToActivePool`), reverting with
// `DebtBelowMin()`. The repay path caps repayment so a Trove can never drop below MIN_DEBT.
//
contract MinDebtJPYdfTest is DevTestSetup {
    uint256 constant PRICE = 2000e18; // mock collateral price ($/unit, 18 dec)
    uint256 constant RATE = 5e16; // 5% annual interest

    function testMinDebtConstantIsOneHundredThousand() public pure {
        assertEq(MIN_DEBT, 100_000e18, "production MIN_DEBT must be 100,000e18");
    }

    function testProductionKeepsStabilityPoolSplit() public {
        vm.chainId(1);
        priceFeed.setPrice(PRICE);
        uint256 troveId = openTroveNoHints100pct(A, 1000 ether, MIN_DEBT, RATE);
        uint256 routerBalanceBefore = jpydfToken.balanceOf(address(mockInterestRouter));
        uint256 stabilityPoolBalanceBefore = jpydfToken.balanceOf(address(stabilityPool));

        vm.warp(block.timestamp + 1 days);
        uint256 pendingInterest = activePool.calcPendingAggInterest();
        assertGt(pendingInterest, 0, "test needs pending aggregate interest");
        uint256 pendingSpYield = activePool.calcPendingSPYield();
        assertEq(pendingSpYield, pendingInterest * SP_YIELD_SPLIT / DECIMAL_PRECISION, "must keep production SP split");

        vm.prank(A);
        borrowerOperations.addColl(troveId, 1 ether);

        assertEq(
            jpydfToken.balanceOf(address(stabilityPool)) - stabilityPoolBalanceBefore,
            pendingSpYield,
            "production must route the configured SP share"
        );
        assertEq(
            jpydfToken.balanceOf(address(mockInterestRouter)) - routerBalanceBefore,
            pendingInterest - pendingSpYield,
            "router must receive the production remainder"
        );
    }

    function testProductionRejectsLastTroveCloseOnMainnet() public {
        vm.chainId(1);
        priceFeed.setPrice(PRICE);
        uint256 troveId = openTroveNoHints100pct(A, 1000 ether, MIN_DEBT, RATE);
        uint256 entireDebt = troveManager.getTroveEntireDebt(troveId);
        deal(address(jpydfToken), A, entireDebt);

        vm.prank(A);
        vm.expectRevert(TroveManager.OnlyOneTroveLeft.selector);
        borrowerOperations.closeTrove(troveId);
    }

    function testProductionBuildRejectsLastTroveCloseOffMainnet() public {
        priceFeed.setPrice(PRICE);
        uint256 troveId = openTroveNoHints100pct(A, 1000 ether, MIN_DEBT, RATE);
        uint256 entireDebt = troveManager.getTroveEntireDebt(troveId);
        deal(address(jpydfToken), A, entireDebt);

        vm.prank(A);
        vm.expectRevert(TroveManager.OnlyOneTroveLeft.selector);
        borrowerOperations.closeTrove(troveId);
    }

    // openTrove with a debt well below MIN_DEBT reverts with DebtBelowMin, and because the
    // MIN_DEBT check precedes the collateral pull, no collateral reaches the ActivePool.
    function testOpenTroveBelowMinDebtReverts() public {
        priceFeed.setPrice(PRICE);
        uint256 coll = 1000 ether; // abundant: the only condition that can fail is the debt floor
        uint256 activePoolCollBefore = collToken.balanceOf(address(activePool));

        vm.prank(A);
        vm.expectRevert(BorrowerOperations.DebtBelowMin.selector);
        borrowerOperations.openTrove(
            A, 0, coll, MIN_DEBT / 2, 0, 0, RATE, type(uint256).max, address(0), address(0), address(0)
        );

        // The check at openTrove fires before any collateral is pulled.
        assertEq(
            collToken.balanceOf(address(activePool)),
            activePoolCollBefore,
            "no collateral should be pulled when debt is below MIN_DEBT"
        );
    }

    // Precise boundary: an entire debt (requested + upfront fee) of MIN_DEBT - 1 still reverts.
    function testOpenTroveJustBelowMinDebtReverts() public {
        priceFeed.setPrice(PRICE);
        (uint256 request, uint256 upfrontFee) = findAmountToBorrowWithOpenTrove(MIN_DEBT - 1, RATE);
        assertEq(request + upfrontFee, MIN_DEBT - 1, "precondition: exact debt below floor");

        vm.prank(A);
        vm.expectRevert(BorrowerOperations.DebtBelowMin.selector);
        borrowerOperations.openTrove(
            A, 0, 1000 ether, request, 0, 0, RATE, upfrontFee, address(0), address(0), address(0)
        );
    }

    // An entire debt of exactly MIN_DEBT succeeds and remains in the active sorted set.
    function testOpenTroveAtMinDebtSucceeds() public {
        priceFeed.setPrice(PRICE);
        (uint256 request, uint256 upfrontFee) = findAmountToBorrowWithOpenTrove(MIN_DEBT, RATE);
        assertEq(request + upfrontFee, MIN_DEBT, "precondition: exact debt at floor");

        vm.prank(A);
        uint256 troveId = borrowerOperations.openTrove(
            A, 0, 1000 ether, request, 0, 0, RATE, upfrontFee, address(0), address(0), address(0)
        );

        assertEq(
            uint8(troveManager.getTroveStatus(troveId)), uint8(ITroveManager.Status.active), "trove should be active"
        );
        assertEq(troveManager.getTroveEntireDebt(troveId), MIN_DEBT, "entire debt should equal MIN_DEBT");
        assertTrue(sortedTroves.contains(troveId), "floor Trove should remain sorted");
    }

    // Requesting comfortably above MIN_DEBT succeeds.
    function testOpenTroveAboveMinDebtSucceeds() public {
        priceFeed.setPrice(PRICE);
        uint256 troveId = openTroveNoHints100pct(A, 5000 ether, MIN_DEBT * 5, RATE);

        assertEq(
            uint8(troveManager.getTroveStatus(troveId)), uint8(ITroveManager.Status.active), "trove should be active"
        );
        assertGe(troveManager.getTroveEntireDebt(troveId), MIN_DEBT * 5, "entire debt should be >= 5x MIN_DEBT");
    }

    // repayJpydf caps the repayment so the Trove debt never drops below MIN_DEBT.
    function testRepayCapsAtMinDebt() public {
        priceFeed.setPrice(PRICE);
        uint256 troveId = openTroveNoHints100pct(A, 5000 ether, MIN_DEBT * 2, RATE);

        // Give A more than enough JPYDF to try to over-repay.
        deal(address(jpydfToken), A, MIN_DEBT * 3);
        vm.prank(A);
        borrowerOperations.repayJpydf(troveId, MIN_DEBT * 3);

        assertEq(troveManager.getTroveEntireDebt(troveId), MIN_DEBT, "repay must cap the Trove at MIN_DEBT");

        uint256 balanceBefore = jpydfToken.balanceOf(A);
        vm.prank(A);
        vm.expectRevert(BorrowerOperations.ZeroAdjustment.selector);
        borrowerOperations.repayJpydf(troveId, 1);
        assertEq(troveManager.getTroveEntireDebt(troveId), MIN_DEBT, "floor debt must remain unchanged");
        assertEq(jpydfToken.balanceOf(A), balanceBefore, "zero repayment must not burn JPYdf");
    }
}
