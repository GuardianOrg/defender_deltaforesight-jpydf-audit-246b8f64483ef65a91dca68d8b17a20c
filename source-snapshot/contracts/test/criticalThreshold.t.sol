// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./TestContracts/DevTestSetup.sol";

contract CriticalThresholdTest is DevTestSetup {
    function setUpBelowCT() internal returns (uint256, uint256, uint256) {
        priceFeed.setPrice(2000e18);
        // TCR: 200% -> 149.9%
        uint256 ATroveId = openTroveNoHints100pct(A, 15000 ether, 13500000e18, 1e17); // CR: 222% -> 166.6%
        uint256 BTroveId = openTroveNoHints100pct(B, 15000 ether, 16500000e18, 1e17); // CR: ~182% -> 136.27%
        uint256 newPrice = 1499e18;
        priceFeed.setPrice(newPrice);
        assert(troveManager.checkBelowCriticalThreshold(newPrice));

        return (ATroveId, BTroveId, newPrice);
    }

    function testTrovesAreNotLiquidatedBetweenMCRAndCT() public {
        (, uint256 BTroveId, uint256 price) = setUpBelowCT();

        // Check A between MCR and CT
        uint256 AICR = troveManager.getCurrentICR(BTroveId, price);
        assertGe(AICR, MCR, "Trove A should be above MCR");
        assertLt(AICR, CCR, "Trove A should be below CT");

        vm.expectRevert(TroveManager.NothingToLiquidate.selector);
        troveManager.liquidate(BTroveId);
    }

    function testNoNewTrovesWithFinalTCRBelowCT() public {
        setUpBelowCT();

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.openTroveNoHints100pct(C, 345 ether, 450000e18, 1e17); // CR: ~110%
    }

    function testNewTrovesWithFinalTCRAboveCT() public {
        setUpBelowCT();

        this.openTroveNoHints100pct(C, 15000 ether, 1500000e18, 1e17); // CR: ~1500%
        uint256 price = priceFeed.getPrice();
        assertGe(troveManager.getTCR(price), CCR, "TCR should be >= CCR");
    }

    function testNoIncreaseDebtAloneWithFinalTCRBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.adjustTrove100pct(A, ATroveId, 0, 1, false, true);

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.withdrawJpydf100pct(A, ATroveId, 1);
    }

    function testNoIncreaseDebtWithAddCollWithFinalTCRBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        uint256 price = priceFeed.getPrice();
        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.adjustTrove100pct(A, ATroveId, 1.1 ether, price, true, true);
    }

    function testIncreaseDebtWithAddCollWithFinalTCRAboveCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        this.adjustTrove100pct(A, ATroveId, 1500e18, 1, true, true);
        uint256 price = priceFeed.getPrice();
        assertGe(troveManager.getTCR(price), CCR, "TCR should be >= CCR");
    }

    function testNoIncreaseDebtWithWithdrawCollBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.adjustTrove100pct(A, ATroveId, 1, 1, false, true);
    }

    function testWithdrawCollAlongWithRepaymentBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        uint256 initialColl = troveManager.getTroveEntireColl(ATroveId);
        adjustTrove100pct(A, ATroveId, 1e18, 224850e18, false, false);

        assertEq(troveManager.getTroveEntireColl(ATroveId), initialColl - 1e18);
    }

    function testNoCollWithdrawalWithLowRepaymentBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        vm.expectRevert(BorrowerOperations.RepaymentNotMatchingCollWithdrawal.selector);
        this.adjustTrove100pct(A, ATroveId, 1e18, 1498999999999999999999, false, false); // 1 gwei short
    }

    function testNoCollWithdrawalWithNoRepaymentBelowCT() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        vm.expectRevert(BorrowerOperations.RepaymentNotMatchingCollWithdrawal.selector);
        this.adjustTrove100pct(A, ATroveId, 1, 0, false, false);

        vm.expectRevert(BorrowerOperations.RepaymentNotMatchingCollWithdrawal.selector);
        this.withdrawColl(A, ATroveId, 1);
    }

    function testNoPrematureInterestRateAdjustmentIfItWouldPullTCRBelowCCR() public {
        uint256 price = CCR; // set price such that TCR=CCR when nominalTCR=100%
        priceFeed.setPrice(price);

        uint256 interestRate = 0.1 ether;
        uint256 targetDebt = 1500000 ether;
        (uint256 borrow,) = findAmountToBorrowWithOpenTrove(targetDebt, interestRate);
        uint256 troveId = openTroveNoHints100pct(A, targetDebt, borrow, interestRate);
        assertEq(troveManager.getTCR(price), CCR, "TCR should equal CCR");

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.changeInterestRateNoHints(A, troveId, 0.3 ether);
    }

    function testPrematureInterestRateAdjustmentDisallowedIfTCRAlreadyBelowCCR() public {
        (uint256 ATroveId,,) = setUpBelowCT();

        vm.expectRevert(BorrowerOperations.TCRBelowCCR.selector);
        this.changeInterestRateNoHints(A, ATroveId, 0.3 ether);
    }

    function testSafeAdjustmentImprovesICRBelowMCRFromAbove100AddingColl() public {
        (, uint256 BTroveId,) = setUpBelowCT();
        uint256 price = 1110e18;
        priceFeed.setPrice(price); // B ICR ~101%
        assertGt(troveManager.getCurrentICR(BTroveId, price), 1e18);
        assertLt(troveManager.getCurrentICR(BTroveId, price), 110e16);

        uint256 beforeICR = troveManager.getCurrentICR(BTroveId, price);
        uint256 beforeColl = getTroveEntireColl(BTroveId);
        uint256 beforeDebt = getTroveEntireDebt(BTroveId);
        vm.startPrank(B);
        borrowerOperations.addColl(BTroveId, 1 ether);
        assertEq(getTroveEntireColl(BTroveId), beforeColl + 1 ether);
        assertEq(getTroveEntireDebt(BTroveId), beforeDebt);
        assertGt(troveManager.getCurrentICR(BTroveId, price), beforeICR);
        assertLt(troveManager.getCurrentICR(BTroveId, price), MCR);

        // With sufficient coll it works
        borrowerOperations.addColl(BTroveId, 1500 ether);
    }

    function testSafeAdjustmentImprovesICRBelowMCRFromAbove100Repaying() public {
        (, uint256 BTroveId,) = setUpBelowCT();
        uint256 price = 1110e18;
        priceFeed.setPrice(price); // B ICR ~101%
        assertGt(troveManager.getCurrentICR(BTroveId, price), 1e18);
        assertLt(troveManager.getCurrentICR(BTroveId, price), 110e16);

        uint256 beforeICR = troveManager.getCurrentICR(BTroveId, price);
        uint256 beforeColl = getTroveEntireColl(BTroveId);
        uint256 beforeDebt = getTroveEntireDebt(BTroveId);
        vm.startPrank(B);
        borrowerOperations.repayJpydf(BTroveId, 150000e18);
        assertEq(getTroveEntireColl(BTroveId), beforeColl);
        assertEq(getTroveEntireDebt(BTroveId), beforeDebt - 150000e18);
        assertGt(troveManager.getCurrentICR(BTroveId, price), beforeICR);
        assertLt(troveManager.getCurrentICR(BTroveId, price), MCR);

        // With sufficient repayment it works
        borrowerOperations.repayJpydf(BTroveId, 2250000e18);
    }

    function testSafeAdjustmentImprovesICRBelowMCRFromBelow100AddingColl() public {
        (, uint256 BTroveId,) = setUpBelowCT();
        uint256 price = 1059e18;
        priceFeed.setPrice(price); // B ICR < 100%
        assertLt(troveManager.getCurrentICR(BTroveId, price), 1e18);

        uint256 beforeICR = troveManager.getCurrentICR(BTroveId, price);
        uint256 beforeColl = getTroveEntireColl(BTroveId);
        uint256 beforeDebt = getTroveEntireDebt(BTroveId);
        vm.startPrank(B);
        borrowerOperations.addColl(BTroveId, 1 ether);
        assertEq(getTroveEntireColl(BTroveId), beforeColl + 1 ether);
        assertEq(getTroveEntireDebt(BTroveId), beforeDebt);
        assertGt(troveManager.getCurrentICR(BTroveId, price), beforeICR);
        assertLt(troveManager.getCurrentICR(BTroveId, price), MCR);

        // With sufficient coll it works
        borrowerOperations.addColl(BTroveId, 2250 ether);
    }

    function testSafeAdjustmentImprovesICRBelowMCRFromBelow100Repaying() public {
        (, uint256 BTroveId,) = setUpBelowCT();
        uint256 price = 1059e18;
        priceFeed.setPrice(price); // B ICR < 100%
        assertLt(troveManager.getCurrentICR(BTroveId, price), 1e18);

        uint256 beforeICR = troveManager.getCurrentICR(BTroveId, price);
        uint256 beforeColl = getTroveEntireColl(BTroveId);
        uint256 beforeDebt = getTroveEntireDebt(BTroveId);
        vm.startPrank(B);
        borrowerOperations.repayJpydf(BTroveId, 150000e18);
        assertEq(getTroveEntireColl(BTroveId), beforeColl);
        assertEq(getTroveEntireDebt(BTroveId), beforeDebt - 150000e18);
        assertGt(troveManager.getCurrentICR(BTroveId, price), beforeICR);
        assertLt(troveManager.getCurrentICR(BTroveId, price), MCR);

        // With sufficient repayment it works
        borrowerOperations.repayJpydf(BTroveId, 2250000e18);
    }
}
