// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/Interfaces/IAddressesRegistry.sol";
import "src/Interfaces/ICollateralRegistry.sol";
import "src/Interfaces/IPriceFeed.sol";
import "src/Interfaces/IRedemptionHelper.sol";
import "src/Interfaces/ISortedTroves.sol";
import "src/Interfaces/ITroveManager.sol";
import "src/RedemptionHelper.sol";
import "src/Types/LatestTroveData.sol";

contract RedemptionFailurePriceFeedMock is IPriceFeed {
    uint256 public lastGoodPrice = 1e18;
    uint256 public redemptionCalls;
    bool public alwaysFailRedemption;
    bool public failAfterFirstRedemptionCall;

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        ++redemptionCalls;
        bool failure = alwaysFailRedemption || (failAfterFirstRedemptionCall && redemptionCalls > 1);
        return (lastGoodPrice, failure);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function setAlwaysFailRedemption(bool value) external {
        alwaysFailRedemption = value;
    }

    function setFailAfterFirstRedemptionCall(bool value) external {
        failAfterFirstRedemptionCall = value;
    }
}

contract RedemptionFailureTroveManagerMock {
    function getUnbackedPortionPriceAndRedeemability() external pure returns (uint256, uint256, bool) {
        return (100e18, 1e18, true);
    }

    function getEntireBranchDebt() external pure returns (uint256) {
        return 100e18;
    }

    function lastZombieTroveId() external pure returns (uint256) {
        return 0;
    }

    function getLatestTroveData(uint256) external pure returns (LatestTroveData memory data) {
        data.entireDebt = 100e18;
        data.entireColl = 100e18;
    }
}

contract RedemptionFailureSortedTrovesMock {
    function getLast() external pure returns (uint256) {
        return 1;
    }

    function getPrev(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract RedemptionFailureAddressesMock {
    ITroveManager public immutable troveManager;
    ISortedTroves public immutable sortedTroves;
    IPriceFeed public immutable priceFeed;

    constructor(address troveManager_, address sortedTroves_, address priceFeed_) {
        troveManager = ITroveManager(troveManager_);
        sortedTroves = ISortedTroves(sortedTroves_);
        priceFeed = IPriceFeed(priceFeed_);
    }
}

contract RedemptionFailureCollateralRegistryMock {
    ITroveManager public immutable troveManager;

    constructor(address troveManager_) {
        troveManager = ITroveManager(troveManager_);
    }

    function totalCollaterals() external pure returns (uint256) {
        return 1;
    }

    function getTroveManager(uint256) external view returns (ITroveManager) {
        return troveManager;
    }

    function jpydfToken() external pure returns (address) {
        return address(0);
    }

    function getRedemptionRateForRedeemedAmount(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract RedemptionHelperOracleFailureTest is Test {
    RedemptionFailurePriceFeedMock priceFeed;
    RedemptionHelper helper;

    function setUp() public {
        priceFeed = new RedemptionFailurePriceFeedMock();
        RedemptionFailureTroveManagerMock troveManager = new RedemptionFailureTroveManagerMock();
        RedemptionFailureSortedTrovesMock sortedTroves = new RedemptionFailureSortedTrovesMock();
        RedemptionFailureCollateralRegistryMock collateralRegistry =
            new RedemptionFailureCollateralRegistryMock(address(troveManager));
        RedemptionFailureAddressesMock addresses =
            new RedemptionFailureAddressesMock(address(troveManager), address(sortedTroves), address(priceFeed));
        IAddressesRegistry[] memory registries = new IAddressesRegistry[](1);
        registries[0] = IAddressesRegistry(address(addresses));
        helper = new RedemptionHelper(ICollateralRegistry(address(collateralRegistry)), registries);
    }

    function test_simulationExcludesRedemptionFailureBeforeComputingProportions() public {
        priceFeed.setAlwaysFailRedemption(true);
        (IRedemptionHelper.SimulationContext[] memory branch, uint256 totalProportions) =
            helper.simulateRedemption(10e18, 1);

        assertFalse(branch[0].redeemable);
        assertEq(totalProportions, 0);
        assertEq(branch[0].attemptedJpydf, 0);
    }

    function test_truncateReturnsZeroIfSecondRedemptionReadFails() public {
        priceFeed.setFailAfterFirstRedemptionCall(true);
        (uint256 truncatedJpydf, uint256 feePct, IRedemptionHelper.Redeemed[] memory redeemed) =
            helper.truncateRedemption(10e18, 1);

        assertEq(priceFeed.redemptionCalls(), 2);
        assertEq(truncatedJpydf, 0);
        assertEq(feePct, 0);
        assertEq(redeemed.length, 1);
        assertEq(redeemed[0].jpydf, 0);
        assertEq(redeemed[0].coll, 0);
    }
}
