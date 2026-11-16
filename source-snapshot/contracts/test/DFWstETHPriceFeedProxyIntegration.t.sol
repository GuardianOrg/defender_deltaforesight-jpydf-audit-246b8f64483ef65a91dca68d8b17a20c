// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/DFWstETHPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "src/Interfaces/IPriceFeed.sol";
import "./TestContracts/ChainlinkOracleMock.sol";

// Gated BO: reproduces the REAL BorrowerOperations gate (_requireCallerIsPriceFeed
// reverts CallerNotPriceFeed if msg.sender != registered priceFeed). When the feed
// sits behind the proxy, the feed's own shutdown call reverts because the *proxy* is
// the registered priceFeed, not the feed. (DFWstETHPriceFeed.t.sol's MockBO is
// permissive and therefore does NOT exercise this path.)
contract GatedMockBO {
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address _pf) external {
        registeredPriceFeed = _pf;
    }

    function shutdownFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        isOracleFailureShutdown = true;
    }

    function resumeFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        isOracleFailureShutdown = false;
    }
}

// Mock wstETH. stEthPerToken() = canonical rate (stETH per wstETH).
contract MockWstETHForProxy {
    uint8 public decimals = 18;
    uint256 public rate;
    bool public shouldRevert;

    function setRate(uint256 r) external {
        rate = r;
    }

    function setShouldRevert(bool b) external {
        shouldRevert = b;
    }

    function stEthPerToken() external view returns (uint256) {
        if (shouldRevert) revert("wstETH down");
        return rate;
    }
}

contract MockWstETHBackingVaultForProxy {
    uint256 public ratio = 1e18;

    function setBackingRatio(uint256 r) external {
        ratio = r;
    }

    function backingRatio() external view returns (uint256) {
        return ratio;
    }

    function backingRatioForPricing() external view returns (uint256, bool) {
        return (ratio, true);
    }
}

/// @notice Verifies the M-1 carry-over claim for DFWstETHPriceFeed (mirrors the
///         composite-feed proxy-integration suites): "behind the PriceFeedProxy, an oracle
///         failure degrades to branch-shutdown + lastGoodPrice (NOT a secondary
///         ETHUSDxCanonical price), equivalent to direct use." The gated BO makes the
///         source's own shutdown call revert (the M-1 mechanism), forcing the proxy's
///         catch -> proxy shutdown -> lastGoodPrice.
contract DFWstETHPriceFeedProxyIntegrationTest is Test {
    ChainlinkOracleMock stEthUsd;
    ChainlinkOracleMock ethUsd;
    ChainlinkOracleMock stEthEth;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockWstETHForProxy wstEth;
    GatedMockBO bo;
    MockWstETHBackingVaultForProxy backingVault;
    DFWstETHPriceFeed feed;
    PriceFeedProxy proxy;

    uint256 constant STETH_STALENESS = 24 hours;
    uint256 constant ETH_STALENESS = 2 hours;
    uint256 constant STETH_ETH_STALENESS = 25 hours;
    uint256 constant JPY_STALENESS = 72 hours;
    int256 constant JPY_USD_8DEC = 666_700; // 0.006667 USD per JPY (~¥150/$)

    function setUp() public {
        vm.warp(1_700_000_000);

        stEthUsd = new ChainlinkOracleMock();
        stEthUsd.setDecimals(8);
        stEthUsd.setPrice(3000e8); // stETH = $3,000
        stEthUsd.setUpdatedAt(block.timestamp);

        ethUsd = new ChainlinkOracleMock();
        ethUsd.setDecimals(8);
        ethUsd.setPrice(3000e8);
        ethUsd.setUpdatedAt(block.timestamp);

        stEthEth = new ChainlinkOracleMock();
        stEthEth.setDecimals(18);
        stEthEth.setPrice(1e18);
        stEthEth.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(JPY_USD_8DEC);
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        wstEth = new MockWstETHForProxy();
        wstEth.setRate(1.2e18); // 1 wstETH = 1.2 stETH

        bo = new GatedMockBO();
        backingVault = new MockWstETHBackingVaultForProxy();

        // Real feed pointed at the gated BO. Constructor fetch succeeds (oracles healthy).
        feed = new DFWstETHPriceFeed(
            address(stEthUsd),
            address(ethUsd),
            address(stEthEth),
            address(wstEth),
            STETH_STALENESS,
            ETH_STALENESS,
            STETH_ETH_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo)
        );

        // Wrap behind the proxy and register the PROXY (not the feed) as BO's priceFeed
        // — the production wiring (Oracle.md §4.4 / §6.6).
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    function _refreshAll() internal {
        stEthUsd.setUpdatedAt(block.timestamp);
        ethUsd.setUpdatedAt(block.timestamp);
        stEthEth.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
    }

    // Sanity: healthy path through the proxy returns the composite JPY price, primary mode, no shutdown.
    function test_proxy_healthy_servesCompositeJpyPrice() public {
        (uint256 p, bool fail) = proxy.fetchPrice();
        assertApproxEqRel(p, 540_000e18, 0.001e18); // 3000 × 1.2 / 0.006667 ≈ ¥540,000
        assertFalse(fail);
        assertFalse(bo.isOracleFailureShutdown());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_healthy_appliesBackingRatio() public {
        backingVault.setBackingRatio(0.8e18);

        (uint256 p, bool fail) = proxy.fetchPrice();

        assertApproxEqRel(p, 432_000e18, 0.001e18);
        assertFalse(fail);
        assertFalse(bo.isOracleFailureShutdown());
    }

    function test_proxy_redemptionUsesHigherEthReferenceWithoutPollutingNormalFallback() public {
        (uint256 normalPrice,) = proxy.fetchPrice();

        ethUsd.setPrice(3300e8);
        ethUsd.setUpdatedAt(block.timestamp);
        (uint256 redemptionPrice, bool redemptionFailure) = proxy.fetchRedemptionPrice();

        assertFalse(redemptionFailure);
        assertGt(redemptionPrice, normalPrice);
        assertEq(feed.lastGoodPrice(), normalPrice);

        // A later normal-path source failure may refresh the proxy cache from the
        // source's lastGoodPrice. It must still return the normal quote, not the
        // higher borrower-protective redemption quote.
        stEthUsd.setPrice(0);
        (uint256 fallbackPrice, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertEq(fallbackPrice, normalPrice);
        assertTrue(bo.isOracleFailureShutdown());
    }

    function test_proxy_redemptionReferenceStalePausesUntilValidatedResume() public {
        (uint256 goodRedemptionPrice,) = proxy.fetchRedemptionPrice();

        vm.warp(block.timestamp + ETH_STALENESS + 1);
        stEthUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);

        vm.expectEmit(true, true, true, true, address(feed));
        emit DFWstETHPriceFeed.RedemptionReferenceUnavailable(address(ethUsd), 3000e18);
        (uint256 fallbackPrice, bool redemptionFailure) = proxy.fetchRedemptionPrice();
        assertTrue(redemptionFailure);
        assertEq(fallbackPrice, goodRedemptionPrice);
        assertTrue(bo.isOracleFailureShutdown());

        (, bool normalFailureBeforeResume) = proxy.fetchPrice();
        assertFalse(normalFailureBeforeResume, "healthy normal price remains available for liquidation");
        assertTrue(bo.isOracleFailureShutdown(), "source recovery alone must not reopen borrower operations");

        ethUsd.setUpdatedAt(block.timestamp);
        proxy.resumeFromOracleFailure();
        (, bool normalFailureAfterResume) = proxy.fetchPrice();
        assertFalse(normalFailureAfterResume);
    }

    function test_proxy_urgentReferenceFailureFailsClosedWithoutThirdCache() public {
        proxy.fetchPrice();
        stEthEth.setPrice(0);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.UrgentRedemptionPriceUnavailable.selector, address(feed))
        );
        proxy.fetchUrgentRedemptionPrice();
        assertFalse(bo.isOracleFailureShutdown());
    }

    // M-1 core (stETH/USD stale): proxy shuts the branch down and serves lastGoodPrice.
    // Confirms NO secondary (ETHUSDxCanonical) price is ever served.
    function test_proxy_stEthStale_shutsDownAndServesLastGood() public {
        (uint256 good,) = proxy.fetchPrice(); // prime lastGoodPrice
        vm.warp(block.timestamp + 25 hours); // > stETH staleness (24h)
        jpyUsd.setUpdatedAt(block.timestamp); // keep JPY fresh -> isolate stETH failure

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown());
        assertEq(p, good); // served lastGoodPrice, not a recomputed/secondary price
        // The source NEVER entered secondary mode. (Behind the proxy its priceSource
        // even stays `primary` — its shutdown attempt reverts & rolls back — but it is
        // categorically never ETHUSDxCanonical.)
        assertTrue(feed.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }

    // JPY/USD stale behind the proxy -> soft-freeze, NOT shutdown. The shared JPY leg is
    // systemic across all branches, so the source substitutes the last good JPY rate and
    // returns a valid price; the proxy sees no failure and the branch stays live. ORCL-SEC-005.
    function test_proxy_jpyStale_substitutesNoShutdown() public {
        (uint256 good,) = proxy.fetchPrice();
        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours); // > JPY staleness (72h)
        stEthUsd.setUpdatedAt(block.timestamp); // keep stETH fresh -> isolate JPY failure

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertFalse(fail);
        assertFalse(bo.isOracleFailureShutdown());
        assertEq(p, good); // frozen JPY rate × live (unchanged) stETH leg
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
    }

    function test_proxy_jpyFreezeExpires_proxyShutsDownAndServesLastGood() public {
        proxy.fetchPrice();

        vm.warp(block.timestamp + 73 hours); // enter the bounded JPY freeze
        stEthUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = proxy.fetchPrice();
        assertFalse(freezeFailure);
        assertFalse(bo.isOracleFailureShutdown());

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        stEthUsd.setPrice(3300e8);
        stEthUsd.setUpdatedAt(block.timestamp);

        (uint256 p, bool fail) = proxy.fetchPrice();

        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown(), "proxy performs the registered temporary shutdown");
        assertEq(p, frozenPrice, "proxy serves the source's bounded lastGoodPrice");
        assertTrue(jpyRateProvider.jpyFreezeExpired(), "shared expiry latch survives proxy shutdown delegation");

        // The source stays on `primary` for the shared-JPY exit, unlike every other shutdown
        // path. `fetchPrice()` is public and the source's own BorrowerOperations call always
        // reverts on the caller check under this topology, so latching would let a direct
        // caller consume the one-shot failure=true and leave the branch live on a frozen
        // price. See test/JpySharedShutdownLatch.t.sol. The guarantees above are unchanged;
        // only the mechanism that delivers them differs.
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));

        // Re-arming rather than latching keeps the branch shut down across further fetches.
        (, bool againFail) = proxy.fetchPrice();
        assertTrue(againFail, "shared JPY failure keeps re-reporting");
        assertTrue(bo.isOracleFailureShutdown());
    }

    // JPY/USD weekend-close age within threshold is not an oracle failure.
    function test_proxy_jpyWeekendCloseWithinThreshold_staysHealthy() public {
        vm.warp(block.timestamp + 60 hours);
        stEthUsd.setUpdatedAt(block.timestamp); // keep stETH fresh; leave JPY at prior close

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertFalse(fail);
        assertFalse(bo.isOracleFailureShutdown());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertApproxEqRel(p, 540_000e18, 0.001e18);
    }

    // wstETH canonical-rate revert behind the proxy -> shutdown + lastGoodPrice.
    function test_proxy_canonicalRateRevert_shutsDown() public {
        (uint256 good,) = proxy.fetchPrice();
        wstEth.setShouldRevert(true);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown());
        assertEq(p, good);
        assertTrue(feed.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }

    // wstETH canonical-rate zero behind the proxy -> shutdown + lastGoodPrice.
    function test_proxy_canonicalRateZero_shutsDown() public {
        (uint256 good,) = proxy.fetchPrice();
        wstEth.setRate(0);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown());
        assertEq(p, good);
    }

    // Redemption path behind the proxy also degrades to lastGoodPrice
    // (urgent redemption / CollateralRegistry must not break).
    function test_proxy_redemption_failureDegradesToLastGood() public {
        (uint256 good,) = proxy.fetchRedemptionPrice();
        wstEth.setShouldRevert(true);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchRedemptionPrice();
        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown());
        assertEq(p, good);
    }

    // Direct vs proxy equivalence at the system level: both signal temporary shutdown and
    // serve lastGoodPrice on failure, while keeping the primary path retryable for recovery.
    function test_direct_failure_endStateMatchesProxy() public {
        GatedMockBO bo2 = new GatedMockBO();
        DFWstETHPriceFeed direct = new DFWstETHPriceFeed(
            address(stEthUsd),
            address(ethUsd),
            address(stEthEth),
            address(wstEth),
            STETH_STALENESS,
            ETH_STALENESS,
            STETH_ETH_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo2)
        );
        bo2.setRegisteredPriceFeed(address(direct)); // the feed IS the registered priceFeed

        _refreshAll();
        (uint256 good,) = direct.fetchPrice();

        vm.warp(block.timestamp + 25 hours);
        jpyUsd.setUpdatedAt(block.timestamp);

        (uint256 p, bool fail) = direct.fetchPrice();
        assertTrue(fail);
        assertTrue(bo2.isOracleFailureShutdown());
        assertEq(p, good);
        // Direct: temporary shutdown keeps probing the primary source so recovery is observable.
        assertEq(uint256(direct.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertTrue(direct.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }
}
