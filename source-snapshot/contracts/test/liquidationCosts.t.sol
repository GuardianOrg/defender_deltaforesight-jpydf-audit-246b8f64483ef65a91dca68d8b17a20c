// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./TestContracts/DevTestSetup.sol";
import {DECIMAL_PRECISION, MIN_JPYDF_IN_SP} from "src/Dependencies/Constants.sol";

contract LiquidationCostsTest is DevTestSetup {
    uint256 public constant N_TROVES = 100;

    function testBatchLiquidationsOffset() public {
        priceFeed.setPrice(2000e18);

        // Healthy troves
        for (uint256 i = 0; i < N_TROVES; i++) {
            openTroveNoHints100pctWithIndex(A, i, 1500 ether, 750000e18, 1e16);
        }
        // Deposit to SP
        makeSPDepositAndClaim(A, N_TROVES * 750000e18);

        uint256[] memory trovesToLiq = new uint256[](N_TROVES);
        // To be liquidated troves
        for (uint256 i = 0; i < N_TROVES; i++) {
            uint256 troveId = openTroveNoHints100pctWithIndex(B, i, 32850e16, 300000e18, 1e16);
            trovesToLiq[i] = troveId;
        }

        // Price drops
        priceFeed.setPrice(1000e18);
        (uint256 price,) = priceFeed.fetchPrice();

        // Check not RM
        assertEq(troveManager.checkBelowCriticalThreshold(price), false, "System should not be below CT");

        batchLiquidateTroves(A, trovesToLiq);

        // Check all troves were liquidated
        for (uint256 i = 0; i < N_TROVES; i++) {
            assertEq(
                uint8(troveManager.getTroveStatus(trovesToLiq[i])),
                uint8(ITroveManager.Status.closedByLiquidation),
                "Trove should have been liquidated"
            );
        }
    }

    function testBatchLiquidationsRedistribution() public {
        priceFeed.setPrice(2000e18);

        // Healthy troves
        for (uint256 i = 0; i < N_TROVES; i++) {
            openTroveNoHints100pctWithIndex(A, i, 1500 ether, 750000e18, 1e16);
        }

        uint256[] memory trovesToLiq = new uint256[](N_TROVES);
        // To be liquidated troves
        for (uint256 i = 0; i < N_TROVES; i++) {
            uint256 troveId = openTroveNoHints100pctWithIndex(B, i, 32850e16, 300000e18, 1e16);
            trovesToLiq[i] = troveId;
        }

        // Price drops
        priceFeed.setPrice(1000e18);
        (uint256 price,) = priceFeed.fetchPrice();

        // Check not RM
        assertEq(troveManager.checkBelowCriticalThreshold(price), false, "System should not be below CT");

        batchLiquidateTroves(A, trovesToLiq);

        // Check all troves were liquidated
        for (uint256 i = 0; i < N_TROVES; i++) {
            assertEq(
                uint8(troveManager.getTroveStatus(trovesToLiq[i])),
                uint8(ITroveManager.Status.closedByLiquidation),
                "Trove should have been liquidated"
            );
        }
    }

    function testBatchLiquidationsManyUnderwaterTrovesPartialOffsetAndRedistribution() public {
        priceFeed.setPrice(2000e18);

        uint256[] memory healthyTroves = new uint256[](N_TROVES);
        for (uint256 i = 0; i < N_TROVES; i++) {
            healthyTroves[i] = openTroveNoHints100pctWithIndex(A, i, 1500 ether, 750000e18, 1e16);
        }

        uint256 partialSPDeposit = 10_000_000e18;
        makeSPDepositAndClaim(A, partialSPDeposit);

        uint256[] memory underwaterTroves = new uint256[](N_TROVES);
        for (uint256 i = 0; i < N_TROVES; i++) {
            underwaterTroves[i] = openTroveNoHints100pctWithIndex(B, i, 32850e16, 300000e18, 1e16);
        }

        priceFeed.setPrice(900e18);
        (uint256 price,) = priceFeed.fetchPrice();

        assertGt(troveManager.getTCR(price), CCR, "branch should stay above CCR while many troves are underwater");
        for (uint256 i = 0; i < N_TROVES; i++) {
            assertLt(
                troveManager.getCurrentICR(underwaterTroves[i], price),
                DECIMAL_PRECISION,
                "stress trove should be underwater"
            );
        }

        uint256 trovesCountBefore = troveManager.getTroveIdsCount();
        uint256 defaultPoolDebtBefore = defaultPool.getJpydfDebt();
        uint256 defaultPoolCollBefore = defaultPool.getCollBalance();
        uint256 spDepositsBefore = stabilityPool.getTotalJpydfDeposits();
        assertEq(spDepositsBefore, partialSPDeposit, "SP fixture deposit mismatch");

        batchLiquidateTroves(A, underwaterTroves);

        assertEq(troveManager.getTroveIdsCount(), trovesCountBefore - N_TROVES, "wrong active trove count");
        for (uint256 i = 0; i < N_TROVES; i++) {
            assertEq(
                uint8(troveManager.getTroveStatus(underwaterTroves[i])),
                uint8(ITroveManager.Status.closedByLiquidation),
                "underwater trove should have been liquidated"
            );
            assertEq(
                uint8(troveManager.getTroveStatus(healthyTroves[i])),
                uint8(ITroveManager.Status.active),
                "healthy trove should remain active"
            );
        }

        assertEq(stabilityPool.getTotalJpydfDeposits(), MIN_JPYDF_IN_SP, "SP should retain only protocol floor");
        assertGt(stabilityPool.getCollBalance(), 0, "SP should receive offset collateral");
        assertGt(defaultPool.getJpydfDebt(), defaultPoolDebtBefore, "unoffset debt should be redistributed");
        assertGt(defaultPool.getCollBalance(), defaultPoolCollBefore, "unoffset collateral should be redistributed");
        assertTrue(troveManager.hasRedistributionGains(healthyTroves[0]), "healthy troves should receive redist gains");
        assertEq(collSurplusPool.getCollBalance(), 0, "underwater liquidations should not create surplus");
    }
}
