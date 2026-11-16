// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "src/PriceFeeds/archive/DFWBTCPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "../TestContracts/ChainlinkOracleMock.sol";

contract GatedWBTCMockBO {
    bool public hasBeenShutDown;
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address _pf) external {
        registeredPriceFeed = _pf;
    }

    function shutdownFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        if (hasBeenShutDown) return;
        hasBeenShutDown = true;
        isOracleFailureShutdown = true;
    }
}

contract MockWBTCBackingVaultForProxy {
    uint256 public ratio = 1e18;

    function setBackingRatio(uint256 _ratio) external {
        ratio = _ratio;
    }

    function backingRatio() external view returns (uint256) {
        return ratio;
    }

    function backingRatioForPricing() external view returns (uint256, bool) {
        return (ratio, true);
    }
}

/// @notice Production-wiring tests for the WBTC peg-monitored feed behind PriceFeedProxy.
///         The gated BO reproduces BorrowerOperations' registered-priceFeed check, so a
///         source-level shutdown reverts behind the proxy and the proxy must perform the
///         registered shutdown while serving lastGoodPrice.
contract DFWBTCPriceFeedProxyIntegrationTest is Test {
    ChainlinkOracleMock wbtcBtc;
    ChainlinkOracleMock btcUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    GatedWBTCMockBO bo;
    MockWBTCBackingVaultForProxy backingVault;
    DFWBTCPriceFeed feed;
    PriceFeedProxy proxy;

    uint256 constant WBTC_BTC_STALENESS = 48 hours;
    uint256 constant BTC_USD_STALENESS = 48 hours;
    uint256 constant JPY_STALENESS = 72 hours;

    // JPY/USD = 0.005 USD per JPY (JPY 200 per USD), 8-decimal Chainlink.
    int256 constant JPY_USD_8DEC = 500_000;

    function setUp() public {
        vm.warp(1_700_000_000);

        wbtcBtc = new ChainlinkOracleMock();
        wbtcBtc.setDecimals(8);
        wbtcBtc.setPrice(1e8);
        wbtcBtc.setUpdatedAt(block.timestamp);

        btcUsd = new ChainlinkOracleMock();
        btcUsd.setDecimals(8);
        btcUsd.setPrice(100_000e8);
        btcUsd.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(JPY_USD_8DEC);
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        bo = new GatedWBTCMockBO();
        backingVault = new MockWBTCBackingVaultForProxy();

        feed = new DFWBTCPriceFeed(
            address(wbtcBtc),
            WBTC_BTC_STALENESS,
            address(btcUsd),
            BTC_USD_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo)
        );

        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    function _refreshBtcAndJpy() internal {
        btcUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
    }

    function _refreshWbtcAndBtc() internal {
        wbtcBtc.setUpdatedAt(block.timestamp);
        btcUsd.setUpdatedAt(block.timestamp);
    }

    function test_proxy_healthy_multipliesPegBtcUsdAndJpy() public {
        wbtcBtc.setPrice(0.75e8);

        (uint256 price, bool failure) = proxy.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.hasBeenShutDown());
        assertEq(price, 15_000_000e18); // 0.75 * $100,000 / 0.005
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_wbtcBtcStale_shutsDownAndServesLastGood() public {
        (uint256 goodPrice,) = proxy.fetchPrice();

        vm.warp(block.timestamp + 49 hours);
        _refreshBtcAndJpy();

        (uint256 price, bool failure) = proxy.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
        assertEq(price, goodPrice);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_btcUsdStale_shutsDownAndServesLastGood() public {
        (uint256 goodPrice,) = proxy.fetchPrice();

        vm.warp(block.timestamp + 49 hours);
        wbtcBtc.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = proxy.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
        assertEq(price, goodPrice);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_jpyStale_substitutesNoShutdownAndTracksLivePegLegs() public {
        proxy.fetchPrice();

        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours);
        wbtcBtc.setPrice(0.9e8);
        wbtcBtc.setUpdatedAt(block.timestamp);
        btcUsd.setPrice(110_000e8);
        btcUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = proxy.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.hasBeenShutDown());
        assertEq(price, 19_800_000e18); // 0.9 * $110,000 / frozen 0.005
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_jpyFreezeExpires_proxyShutsDownAndServesLastGood() public {
        proxy.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        wbtcBtc.setUpdatedAt(block.timestamp);
        btcUsd.setPrice(110_000e8);
        btcUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = proxy.fetchPrice();
        assertFalse(freezeFailure);
        assertFalse(bo.hasBeenShutDown());

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        _refreshWbtcAndBtc();

        (uint256 price, bool failure) = proxy.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
        assertEq(price, frozenPrice);
        assertTrue(jpyRateProvider.jpyFreezeExpired(), "shared expiry latch survives proxy shutdown delegation");
        // Under the proxy topology the source's own BorrowerOperations call reverts on the
        // caller check, so it must not latch here -- see test/JpySharedShutdownLatch.t.sol.
        // The proxy still performs the shutdown from the returned failure=true.
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_redemption_wbtcBtcFailureDegradesToLastGood() public {
        (uint256 goodPrice,) = proxy.fetchRedemptionPrice();

        vm.warp(block.timestamp + 49 hours);
        _refreshBtcAndJpy();

        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();

        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
        assertEq(price, goodPrice);
    }
}
