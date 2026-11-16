// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {INTEREST_RATE_ADJ_COOLDOWN, MIN_INTEREST_RATE_CHANGE_PERIOD} from "src/Dependencies/Constants.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

/// @notice Focused execution evidence for HintHelpers fee predictions used by batch exits.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract HintHelpersVerification is DevTestSetup {
    function testPredictOpenTroveFeeMatchesActualDebtCharge() external {
        uint256 borrowedAmount = 300_000e18;
        uint256 interestRate = 5e16;
        uint256 quotedFee = hintHelpers.predictOpenTroveUpfrontFee(0, borrowedAmount, interestRate);

        assertGt(quotedFee, 0, "opening quote is nonzero");
        vm.prank(A);
        uint256 troveId = borrowerOperations.openTrove(
            A, 0, 15_000e18, borrowedAmount, 0, 0, interestRate, quotedFee, address(0), address(0), address(0)
        );

        assertEq(troveManager.getTroveEntireDebt(troveId), borrowedAmount + quotedFee, "opening quote equals debt charge");
    }

    function testPredictAdjustInterestAndDebtFeesMatchActualCharges() external {
        uint256 troveId = openTroveNoHints100pct(A, 15_000e18, 750_000e18, 5e16);
        uint256 debtBeforeRateChange = troveManager.getTroveEntireDebt(troveId);
        uint256 rateQuote = hintHelpers.predictAdjustInterestRateUpfrontFee(0, troveId, 4e16);

        assertGt(rateQuote, 0, "premature rate change quote is nonzero");
        vm.prank(A);
        borrowerOperations.adjustTroveInterestRate(troveId, 4e16, 0, 0, rateQuote);
        assertEq(troveManager.getTroveEntireDebt(troveId), debtBeforeRateChange + rateQuote, "rate quote equals debt charge");

        uint256 debtIncrease = 100_000e18;
        uint256 debtBeforeWithdrawal = troveManager.getTroveEntireDebt(troveId);
        uint256 withdrawalQuote = hintHelpers.predictAdjustTroveUpfrontFee(0, troveId, debtIncrease);
        assertEq(hintHelpers.predictAdjustTroveUpfrontFee(0, troveId, 0), 0, "zero debt increase is free");

        vm.prank(A);
        borrowerOperations.withdrawJpydf(troveId, debtIncrease, withdrawalQuote);
        assertEq(
            troveManager.getTroveEntireDebt(troveId),
            debtBeforeWithdrawal + debtIncrease + withdrawalQuote,
            "debt-adjustment quote equals debt charge"
        );
    }

    function testBatchFeePredictionsMatchOpenJoinAndBatchRateChange() external {
        uint256 borrowedAmount = 300_000e18;
        uint256 batchRate = 5e16;
        registerBatchManager(
            B,
            uint128(1e16),
            uint128(20e16),
            uint128(batchRate),
            uint128(25e14),
            MIN_INTEREST_RATE_CHANGE_PERIOD
        );

        uint256 openAndJoinQuote = hintHelpers.predictOpenTroveAndJoinBatchUpfrontFee(0, borrowedAmount, B);
        IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams memory params = IBorrowerOperations
            .OpenTroveAndJoinInterestBatchManagerParams({
            owner: A,
            ownerIndex: 0,
            collAmount: 15_000e18,
            jpydfAmount: borrowedAmount,
            upperHint: 0,
            lowerHint: 0,
            interestBatchManager: B,
            maxUpfrontFee: openAndJoinQuote,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
        vm.prank(A);
        uint256 batchedTroveId = borrowerOperations.openTroveAndJoinInterestBatchManager(params);
        assertEq(
            troveManager.getTroveEntireDebt(batchedTroveId),
            borrowedAmount + openAndJoinQuote,
            "open-and-join quote equals debt charge"
        );

        uint256 individualTroveId = openTroveNoHints100pct(C, 15_000e18, borrowedAmount, 6e16);
        uint256 debtBeforeJoin = troveManager.getTroveEntireDebt(individualTroveId);
        uint256 joinQuote = hintHelpers.predictJoinBatchInterestRateUpfrontFee(0, individualTroveId, B);
        vm.prank(C);
        borrowerOperations.setInterestBatchManager(individualTroveId, B, 0, 0, joinQuote);
        assertEq(
            troveManager.getTroveEntireDebt(individualTroveId), debtBeforeJoin + joinQuote, "join quote equals debt charge"
        );

        vm.warp(block.timestamp + MIN_INTEREST_RATE_CHANGE_PERIOD);
        uint256 batchDebtBeforeRateChange = troveManager.getLatestBatchData(B).entireDebtWithoutRedistribution;
        uint256 batchRateQuote = hintHelpers.predictAdjustBatchInterestRateUpfrontFee(0, B, 6e16);
        assertGt(batchRateQuote, 0, "premature batch rate quote is nonzero");
        vm.prank(B);
        borrowerOperations.setBatchManagerAnnualInterestRate(uint128(6e16), 0, 0, batchRateQuote);
        assertEq(
            troveManager.getLatestBatchData(B).entireDebtWithoutRedistribution,
            batchDebtBeforeRateChange + batchRateQuote,
            "batch rate quote equals batch debt charge"
        );

        assertEq(troveManager.getBatchAnnualInterestRate(B), 6e16, "batch rate updated");
        assertEq(batchRate, 5e16, "initial batch rate documented");
    }

    function testReferenceViewsApproxHintForceQuoteAndInvalidIndexAreSafe() external {
        uint256 troveId = openTroveNoHints100pct(A, 15_000e18, 750_000e18, 5e16);
        uint256 helperCollBalanceBefore = collToken.balanceOf(address(hintHelpers));
        uint256 helperJpydfBalanceBefore = jpydfToken.balanceOf(address(hintHelpers));
        uint256 troveRecordedDebtBefore = troveManager.getTroveDebt(troveId);

        assertEq(hintHelpers.NAME(), "HintHelpers", "NAME view");
        assertEq(address(hintHelpers.collateralRegistry()), address(collateralRegistry), "registry reference view");

        (uint256 hintId, uint256 diff, uint256 latestSeed) = hintHelpers.getApproxHint(0, 5e16, 1, 987654);
        assertEq(hintId, troveId, "single active trove is the hint");
        assertEq(diff, 0, "exact-rate hint has zero difference");
        assertEq(latestSeed, 987654, "one trial leaves the seed unchanged");

        vm.warp(block.timestamp + INTEREST_RATE_ADJ_COOLDOWN);
        assertEq(hintHelpers.predictAdjustInterestRateUpfrontFee(0, troveId, 4e16), 0, "cooldown-aware quote is zero");
        assertGt(
            hintHelpers.forcePredictAdjustInterestRateUpfrontFee(0, troveId, 4e16),
            0,
            "force quote remains available after cooldown"
        );
        assertEq(collToken.balanceOf(address(hintHelpers)), helperCollBalanceBefore, "helper retains no collateral");
        assertEq(jpydfToken.balanceOf(address(hintHelpers)), helperJpydfBalanceBefore, "helper retains no JPYdf");
        assertEq(troveManager.getTroveDebt(troveId), troveRecordedDebtBefore, "views do not mutate recorded trove debt");

        vm.expectRevert(bytes("Invalid index"));
        hintHelpers.getApproxHint(10, 5e16, 1, 1);
    }

    function testPredictRemoveFromBatchFeeMatchesActualDebtCharge() external {
        uint256 troveId = openTroveAndJoinBatchManager();
        uint256 newAnnualInterestRate = 4e16;
        uint256 debtBefore = troveManager.getTroveEntireDebt(troveId);
        uint256 predictedFee = hintHelpers.predictRemoveFromBatchUpfrontFee(0, troveId, newAnnualInterestRate);

        assertGt(predictedFee, 0, "premature rate change has an upfront fee");

        vm.prank(A);
        borrowerOperations.removeFromBatch(troveId, newAnnualInterestRate, 0, 0, predictedFee);

        assertEq(borrowerOperations.interestBatchManagerOf(troveId), address(0), "trove left batch");
        assertEq(
            troveManager.getTroveEntireDebt(troveId), debtBefore + predictedFee, "prediction equals applied debt charge"
        );
    }

    function testPredictRemoveFromBatchFeeIsZeroForNoRateChangeOrAfterCooldown() external {
        uint256 troveId = openTroveAndJoinBatchManager();

        assertEq(hintHelpers.predictRemoveFromBatchUpfrontFee(0, troveId, 5e16), 0, "unchanged rate has no fee");

        vm.warp(block.timestamp + INTEREST_RATE_ADJ_COOLDOWN);
        assertEq(hintHelpers.predictRemoveFromBatchUpfrontFee(0, troveId, 4e16), 0, "cooldown removes fee");
    }
}
