// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/archive/DFUSDTPriceFeed.sol";
import "src/PriceFeeds/archive/DFXAUTPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "../TestContracts/ChainlinkOracleMock.sol";

contract ArchivedCandidateMockBO {
    function shutdownFromOracleFailure() external {}
}

contract ArchivedCandidateBackingVault {
    function backingRatio() external pure returns (uint256) {
        return 1e18;
    }

    function backingRatioForPricing() external pure returns (uint256, bool) {
        return (1e18, true);
    }
}

/// @notice Compile-and-behavior guard for archived Standard-feed wrappers.
contract DFCandidateStandardPriceFeedsTest is Test {
    ChainlinkOracleMock collateralUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    ArchivedCandidateMockBO borrowerOperations;
    ArchivedCandidateBackingVault backingVault;

    uint256 constant COLLATERAL_STALENESS = 24 hours;
    uint256 constant JPY_STALENESS = 72 hours;

    function setUp() public {
        vm.warp(1_700_000_000);

        collateralUsd = new ChainlinkOracleMock();
        collateralUsd.setDecimals(8);
        collateralUsd.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(666_700); // ≈ ¥150 per USD
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        borrowerOperations = new ArchivedCandidateMockBO();
        backingVault = new ArchivedCandidateBackingVault();
    }

    function test_USDTWrapperStillCompilesAndConvertsToJpy() public {
        collateralUsd.setPrice(1e8);
        DFUSDTPriceFeed feed = new DFUSDTPriceFeed(
            address(collateralUsd),
            COLLATERAL_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(borrowerOperations)
        );

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertApproxEqRel(price, 150e18, 0.001e18);
    }

    function test_XAUTWrapperStillCompilesAndConvertsToJpy() public {
        collateralUsd.setPrice(2400e8);
        DFXAUTPriceFeed feed = new DFXAUTPriceFeed(
            address(collateralUsd),
            COLLATERAL_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(borrowerOperations)
        );

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertApproxEqRel(price, 360_000e18, 0.001e18);
    }
}
