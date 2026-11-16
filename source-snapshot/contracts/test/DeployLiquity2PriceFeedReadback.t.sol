// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {DeployLiquity2Script} from "script/DeployLiquity2.s.sol";
import {IPriceFeed} from "src/Interfaces/IPriceFeed.sol";

contract DeployLiquity2PriceFeedReadbackHarness is DeployLiquity2Script {
    function verifyPriceFeedReadback(IPriceFeed priceFeed) external {
        _verifyDFPriceFeedReadback(priceFeed);
    }

    function requireProductionMinDebt(uint256 minDebt) external view {
        _requireProductionMinDebt(minDebt);
    }
}

contract DeployLiquity2ReadbackFeed is IPriceFeed {
    uint256 public lastGoodPrice = 1e18;
    bool private _urgentFailure;

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, _urgentFailure);
    }

    function setUrgentFailure(bool value) external {
        _urgentFailure = value;
    }
}

contract DeployLiquity2PriceFeedReadbackTest is Test {
    DeployLiquity2PriceFeedReadbackHarness private harness;
    DeployLiquity2ReadbackFeed private feed;

    function setUp() external {
        harness = new DeployLiquity2PriceFeedReadbackHarness();
        feed = new DeployLiquity2ReadbackFeed();
    }

    function test_VerifierAcceptsAllHealthyPricePaths() external {
        harness.verifyPriceFeedReadback(feed);
    }

    function test_VerifierRejectsUnavailableUrgentPrice() external {
        feed.setUrgentFailure(true);

        vm.expectRevert(bytes("DF: bad fetchUrgentRedemptionPrice"));
        harness.verifyPriceFeedReadback(feed);
    }

    function test_ProductionMinDebtGateAcceptsFinalFloor() external {
        vm.chainId(1);
        harness.requireProductionMinDebt(100_000e18);
    }

    function test_ProductionMinDebtGateRejectsStaleFloor() external {
        vm.chainId(1);
        vm.expectRevert(bytes("DeployLiquity2: production MIN_DEBT must be 100,000e18"));
        harness.requireProductionMinDebt(300_000e18);
    }

    function test_ProductionMinDebtGateRejectsPilotFloor() external {
        vm.chainId(1);
        vm.expectRevert(bytes("DeployLiquity2: production MIN_DEBT must be 100,000e18"));
        harness.requireProductionMinDebt(1_000e18);
    }

    function test_ProductionMinDebtGateSkipsNonMainnet() external view {
        harness.requireProductionMinDebt(1);
    }
}
