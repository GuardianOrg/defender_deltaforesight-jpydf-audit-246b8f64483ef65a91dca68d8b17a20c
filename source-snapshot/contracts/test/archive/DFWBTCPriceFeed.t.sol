// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "src/PriceFeeds/archive/DFWBTCPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "../TestContracts/ChainlinkOracleMock.sol";

contract MockWBTCBO {
    bool public shutDownCalled;

    function shutdownFromOracleFailure() external {
        shutDownCalled = true;
    }
}

contract MockWBTCBackingVault {
    uint256 public ratio = 1e18;
    bool public shouldRevert;
    bool public backingUnavailable;

    function setBackingRatio(uint256 _ratio) external {
        ratio = _ratio;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setBackingUnavailable(bool _backingUnavailable) external {
        backingUnavailable = _backingUnavailable;
    }

    function backingRatio() external view returns (uint256) {
        if (shouldRevert) revert("backing unavailable");
        return ratio;
    }

    function backingRatioForPricing() external view returns (uint256, bool) {
        if (shouldRevert) revert("backing unavailable");
        if (backingUnavailable) return (0, false);
        return (ratio, true);
    }
}

/// @notice Forkless tests for the WBTC peg-monitored JPY feed.
contract DFWBTCPriceFeedTest is Test {
    ChainlinkOracleMock wbtcBtc;
    ChainlinkOracleMock btcUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockWBTCBO bo;
    MockWBTCBackingVault backingVault;

    uint256 constant WBTC_BTC_STALENESS = 48 hours;
    uint256 constant BTC_USD_STALENESS = 48 hours;
    uint256 constant JPY_STALENESS = 72 hours;

    // JPY/USD = 0.005 USD per JPY (¥200 per $1), 8-decimal Chainlink.
    int256 constant JPY_USD_8DEC = 500_000;

    function setUp() public {
        vm.warp(1_700_000_000);

        wbtcBtc = new ChainlinkOracleMock();
        wbtcBtc.setDecimals(8);
        wbtcBtc.setPrice(1e8); // 1 WBTC = 1 BTC
        wbtcBtc.setUpdatedAt(block.timestamp);

        btcUsd = new ChainlinkOracleMock();
        btcUsd.setDecimals(8);
        btcUsd.setPrice(100_000e8); // BTC = $100,000
        btcUsd.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(JPY_USD_8DEC);
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        bo = new MockWBTCBO();
        backingVault = new MockWBTCBackingVault();
    }

    function _deploy() internal returns (DFWBTCPriceFeed) {
        return new DFWBTCPriceFeed(
            address(wbtcBtc),
            WBTC_BTC_STALENESS,
            address(btcUsd),
            BTC_USD_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo)
        );
    }

    function test_wbtcPriceMultipliesPegRatioAndBtcUsd() public {
        wbtcBtc.setPrice(0.5e8); // 1 WBTC = 0.5 BTC

        DFWBTCPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 10_000_000e18); // 0.5 * $100,000 / 0.005 = ¥10,000,000
    }

    function test_wbtcPriceDoesNotDivideByPegRatio() public {
        wbtcBtc.setPrice(0.5e8);

        DFWBTCPriceFeed feed = _deploy();
        (uint256 price,) = feed.fetchPrice();

        assertEq(price, 10_000_000e18);
        assertLt(price, 20_000_000e18, "division by WBTC/BTC would overprice depegged WBTC");
    }

    function test_wbtcPegRatioUpdatesAfterDeploy() public {
        DFWBTCPriceFeed feed = _deploy();
        (uint256 parityPrice,) = feed.fetchPrice();
        assertEq(parityPrice, 20_000_000e18);

        wbtcBtc.setPrice(0.9e8);
        (uint256 discountedPrice, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(discountedPrice, 18_000_000e18);
    }

    function test_backingRatioDiscountsWbtcJpyPrice() public {
        backingVault.setBackingRatio(0.8e18);
        DFWBTCPriceFeed feed = _deploy();

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 16_000_000e18);
        assertEq(feed.lastGoodBacking(), 0.8e18);
    }

    function test_backingRatioFailureShutsDownAtLastGoodPrice() public {
        backingVault.setBackingRatio(0.8e18);
        DFWBTCPriceFeed feed = _deploy();
        (uint256 discounted,) = feed.fetchPrice();

        backingVault.setBackingRatio(0.5e18);
        backingVault.setShouldRevert(true);
        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, discounted);
        assertEq(feed.lastGoodBacking(), 0.8e18);
    }

    function test_wbtcBtcStale_shutsDown() public {
        DFWBTCPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        vm.warp(block.timestamp + 49 hours);
        btcUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, goodPrice);
    }

    function test_wbtcBtcZeroRoundId_shutsDown() public {
        DFWBTCPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        wbtcBtc.setRoundData(0, 0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, goodPrice);
    }

    function test_btcUsdStale_shutsDown() public {
        DFWBTCPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        vm.warp(block.timestamp + 49 hours);
        wbtcBtc.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, goodPrice);
    }

    function test_btcUsdFutureTimestamp_shutsDown() public {
        DFWBTCPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        btcUsd.setUpdatedAt(block.timestamp + 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, goodPrice);
    }

    function test_jpyUsdStale_substitutesLastGoodRate_noShutdown() public {
        DFWBTCPriceFeed feed = _deploy();
        feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        wbtcBtc.setUpdatedAt(block.timestamp);
        btcUsd.setPrice(110_000e8);
        btcUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, 22_000_000e18); // live BTC leg, frozen JPY leg
    }

    function test_constructorReverts_ifWbtcBtcDecimalsNot8() public {
        wbtcBtc.setDecimals(18);
        vm.expectRevert();
        _deploy();
    }

    // ---------------------------------------------------------------
    // 旧shared standard-feed suite(#1458以前のDFPriceFeed.t.sol)から移設した
    // WBTC固有ケース: peg>1のcanonical cap、redemption lag band、mulDiv精度。
    // ---------------------------------------------------------------

    function test_wbtcFetchPriceCapsAtCanonicalWhenPegMonitorIsAboveOne() public {
        wbtcBtc.setPrice(1.01e8); // WBTC/BTC = 1.01

        DFWBTCPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 20_000_000e18, "normal price is capped at canonical BTC/USD"); // $100,000 / 0.005
    }

    function test_wbtcRedemptionPriceUsesCanonicalWhenPegLagIsWithinThreshold() public {
        wbtcBtc.setPrice(0.99e8); // WBTC/BTC = 0.99, within the 2% band

        DFWBTCPriceFeed feed = _deploy();
        (uint256 normalPrice, bool normalFailure) = feed.fetchPrice();
        (uint256 redemptionPrice, bool redemptionFailure) = feed.fetchRedemptionPrice();

        assertFalse(normalFailure);
        assertFalse(redemptionFailure);
        assertEq(normalPrice, 19_800_000e18, "normal price reflects market peg monitor"); // $99,000 / 0.005
        assertEq(redemptionPrice, 20_000_000e18, "redemption uses canonical max inside lag band");
        assertGt(redemptionPrice, normalPrice);
    }

    function test_wbtcRedemptionPriceReflectsRealDepegOutsideThreshold() public {
        wbtcBtc.setPrice(0.97e8); // WBTC/BTC = 0.97, outside the 2% band

        DFWBTCPriceFeed feed = _deploy();
        (uint256 normalPrice, bool normalFailure) = feed.fetchPrice();
        (uint256 redemptionPrice, bool redemptionFailure) = feed.fetchRedemptionPrice();

        assertFalse(normalFailure);
        assertFalse(redemptionFailure);
        assertEq(normalPrice, 19_400_000e18); // $97,000 / 0.005
        assertEq(redemptionPrice, normalPrice, "real depeg outside threshold is not masked for redemptions");
    }

    function test_wbtcMarketPriceUsesFullPrecisionMulDiv() public {
        btcUsd.setPrice(1e50);
        jpyUsd.setPrice(1e8); // JPY/USD = 1, normalized to 1e18

        DFWBTCPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 1e60, "final WBTC market price fits even though wbtcBtc * btcUsd would overflow");
    }

    function test_wbtcRedemptionDeviationUsesFullPrecisionMulDiv() public {
        btcUsd.setPrice(1e50);
        jpyUsd.setPrice(1e8); // JPY/USD = 1, normalized to 1e18
        wbtcBtc.setPrice(0.99e8); // WBTC/BTC = 0.99, within the 2% lag band

        DFWBTCPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchRedemptionPrice();

        assertFalse(failure);
        assertEq(price, 1e60, "redemption threshold handles high reference prices without overflow");
    }
}
