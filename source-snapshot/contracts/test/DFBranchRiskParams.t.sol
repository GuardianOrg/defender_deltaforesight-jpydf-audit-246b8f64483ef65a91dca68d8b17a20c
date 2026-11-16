// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    BCR_DBTC,
    BCR_DETH,
    BCR_DJGB,
    BCR_DJPY,
    BCR_DUSD_A,
    BCR_DUSD_B,
    BCR_DUSDC,
    BCR_DWSTETH,
    CCR_DBTC,
    CCR_DETH,
    CCR_DJGB,
    CCR_DJPY,
    CCR_DUSD_A,
    CCR_DUSD_B,
    CCR_DUSDC,
    CCR_DWSTETH,
    COLL_GAS_COMPENSATION_DIVISOR,
    DECIMAL_PRECISION,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DBTC,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DETH,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DJGB,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DJPY,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DUSD_A,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DUSD_B,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DUSDC,
    LIQUIDATION_PENALTY_REDISTRIBUTION_DWSTETH,
    LIQUIDATION_PENALTY_SP_DBTC,
    LIQUIDATION_PENALTY_SP_DETH,
    LIQUIDATION_PENALTY_SP_DJGB,
    LIQUIDATION_PENALTY_SP_DJPY,
    LIQUIDATION_PENALTY_SP_DUSD_A,
    LIQUIDATION_PENALTY_SP_DUSD_B,
    LIQUIDATION_PENALTY_SP_DUSDC,
    LIQUIDATION_PENALTY_SP_DWSTETH,
    MAX_LIQUIDATION_PENALTY_REDISTRIBUTION,
    MCR_DBTC,
    MCR_DETH,
    MCR_DJGB,
    MCR_DJPY,
    MCR_DUSD_A,
    MCR_DUSD_B,
    MCR_DUSDC,
    MCR_DWSTETH,
    MIN_LIQUIDATION_PENALTY_SP,
    SCR_DBTC,
    SCR_DETH,
    SCR_DJGB,
    SCR_DJPY,
    SCR_DUSD_A,
    SCR_DUSD_B,
    SCR_DUSDC,
    SCR_DWSTETH,
    URGENT_REDEMPTION_BONUS
} from "src/Dependencies/Constants.sol";

/// @notice Locks the eight Owner Decision branch slots and their risk invariants.
contract DFBranchRiskParamsTest is Test {
    function testBranchParamsMatchOwnerDecisionManifest() public pure {
        uint256 onePct = DECIMAL_PRECISION / 100;

        _assertBranch(
            "dwstETH",
            MCR_DWSTETH,
            CCR_DWSTETH,
            SCR_DWSTETH,
            BCR_DWSTETH,
            LIQUIDATION_PENALTY_SP_DWSTETH,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DWSTETH,
            12318 * onePct / 100,
            14167 * onePct / 100,
            110 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dUSDC",
            MCR_DUSDC,
            CCR_DUSDC,
            SCR_DUSDC,
            BCR_DUSDC,
            LIQUIDATION_PENALTY_SP_DUSDC,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DUSDC,
            11158 * onePct / 100,
            12450 * onePct / 100,
            105 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dETH",
            MCR_DETH,
            CCR_DETH,
            SCR_DETH,
            BCR_DETH,
            LIQUIDATION_PENALTY_SP_DETH,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DETH,
            12318 * onePct / 100,
            14167 * onePct / 100,
            110 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dUSD-A",
            MCR_DUSD_A,
            CCR_DUSD_A,
            SCR_DUSD_A,
            BCR_DUSD_A,
            LIQUIDATION_PENALTY_SP_DUSD_A,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DUSD_A,
            120 * onePct,
            13765 * onePct / 100,
            105 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dBTC",
            MCR_DBTC,
            CCR_DBTC,
            SCR_DBTC,
            BCR_DBTC,
            LIQUIDATION_PENALTY_SP_DBTC,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DBTC,
            11955 * onePct / 100,
            13082 * onePct / 100,
            110 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dUSD-B",
            MCR_DUSD_B,
            CCR_DUSD_B,
            SCR_DUSD_B,
            BCR_DUSD_B,
            LIQUIDATION_PENALTY_SP_DUSD_B,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DUSD_B,
            120 * onePct,
            13765 * onePct / 100,
            105 * onePct,
            10 * onePct,
            5 * onePct,
            10 * onePct
        );
        _assertBranch(
            "dJPY",
            MCR_DJPY,
            CCR_DJPY,
            SCR_DJPY,
            BCR_DJPY,
            LIQUIDATION_PENALTY_SP_DJPY,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DJPY,
            10553 * onePct / 100,
            10730 * onePct / 100,
            10330 * onePct / 100,
            5 * onePct,
            5 * onePct,
            5 * onePct
        );
        _assertBranch(
            "dJGB",
            MCR_DJGB,
            CCR_DJGB,
            SCR_DJGB,
            BCR_DJGB,
            LIQUIDATION_PENALTY_SP_DJGB,
            LIQUIDATION_PENALTY_REDISTRIBUTION_DJGB,
            10553 * onePct / 100,
            10730 * onePct / 100,
            10330 * onePct / 100,
            5 * onePct,
            5 * onePct,
            5 * onePct
        );
    }

    function _assertBranch(
        string memory branch,
        uint256 mcr,
        uint256 ccr,
        uint256 scr,
        uint256 bcr,
        uint256 spPenalty,
        uint256 redistributionPenalty,
        uint256 expectedMcr,
        uint256 expectedCcr,
        uint256 expectedScr,
        uint256 expectedBcr,
        uint256 expectedSpPenalty,
        uint256 expectedRedistributionPenalty
    ) internal pure {
        assertEq(mcr, expectedMcr, string.concat(branch, ": MCR"));
        assertEq(ccr, expectedCcr, string.concat(branch, ": CCR"));
        assertEq(scr, expectedScr, string.concat(branch, ": SCR"));
        assertEq(bcr, expectedBcr, string.concat(branch, ": BCR"));
        assertEq(spPenalty, expectedSpPenalty, string.concat(branch, ": SP penalty"));
        assertEq(
            redistributionPenalty, expectedRedistributionPenalty, string.concat(branch, ": redistribution penalty")
        );

        assertLt(scr, mcr, string.concat(branch, ": SCR < MCR"));
        assertLt(mcr, ccr, string.concat(branch, ": MCR < CCR"));
        assertGe(scr, DECIMAL_PRECISION + URGENT_REDEMPTION_BONUS, string.concat(branch, ": shutdown buffer"));
        assertGe(spPenalty, MIN_LIQUIDATION_PENALTY_SP, string.concat(branch, ": SP penalty floor"));
        assertLe(spPenalty, redistributionPenalty, string.concat(branch, ": penalty ordering"));
        assertLe(redistributionPenalty, MAX_LIQUIDATION_PENALTY_REDISTRIBUTION, string.concat(branch, ": penalty cap"));
        assertLe(DECIMAL_PRECISION + redistributionPenalty, mcr, string.concat(branch, ": redistribution coverage"));
        assertLe(
            (DECIMAL_PRECISION + spPenalty) * COLL_GAS_COMPENSATION_DIVISOR,
            mcr * (COLL_GAS_COMPENSATION_DIVISOR - 1),
            string.concat(branch, ": SP coverage after gas compensation")
        );
    }
}
