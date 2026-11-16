// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/archive/sUSDSPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "src/Interfaces/IPriceFeed.sol";
import "../TestContracts/ChainlinkOracleMock.sol";

// Gated BO: reproduces the REAL BorrowerOperations gate
// (BorrowerOperations.sol:1238-1239,1583-1585 -> _requireCallerIsPriceFeed reverts
//  CallerNotPriceFeed if msg.sender != registered priceFeed). This is the crux of M-1:
//  when the feed sits behind the proxy, the feed's own shutdown call reverts because
//  the *proxy* is the registered priceFeed, not the feed.
//  (sUSDSPriceFeed.t.sol's MockBO is permissive and therefore does NOT exercise this path.)
contract GatedMockBO {
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

contract MockUSDSAssetForProxy {
    uint8 public decimals = 18;
}

// Mock sUSDS (ERC-4626 view). convertToAssets(1e18) = canonical rate (USDS per sUSDS).
contract MockSUSDS {
    address public asset;
    uint8 public decimals = 18;
    uint256 public rate;
    bool public shouldRevert;

    constructor(address _asset) {
        asset = _asset;
    }

    function setRate(uint256 r) external {
        rate = r;
    }

    function setShouldRevert(bool b) external {
        shouldRevert = b;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (shouldRevert) revert("sUSDS down");
        return shares * rate / 1e18;
    }
}

contract MockSUSDSBackingVaultForProxy {
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

/// @notice Verifies the M-1 carry-over claim for sUSDSPriceFeed (PR#9 issue comment 4645464933):
///         "behind the PriceFeedProxy, an oracle failure degrades to branch-shutdown +
///          lastGoodPrice (NOT a secondary ETHUSDxCanonical price), equivalent to direct use."
///         The gated BO makes the source's own shutdown call revert (the M-1 mechanism),
///         forcing the proxy's catch -> proxy shutdown -> lastGoodPrice.
contract SUSDSPriceFeedProxyIntegrationTest is Test {
    ChainlinkOracleMock usdsUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockUSDSAssetForProxy usds;
    MockSUSDS susds;
    GatedMockBO bo;
    MockSUSDSBackingVaultForProxy backingVault;
    sUSDSPriceFeed feed;
    PriceFeedProxy proxy;

    uint256 constant USDS_STALENESS = 24 hours;
    uint256 constant JPY_STALENESS = 72 hours;
    int256 constant JPY_USD_8DEC = 666_700; // 0.006667 USD per JPY (~¥150/$)

    function setUp() public {
        vm.warp(1_700_000_000);

        usdsUsd = new ChainlinkOracleMock();
        usdsUsd.setDecimals(8);
        usdsUsd.setPrice(1e8); // USDS = $1.00
        usdsUsd.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(JPY_USD_8DEC);
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        usds = new MockUSDSAssetForProxy();
        susds = new MockSUSDS(address(usds));
        susds.setRate(1.05e18); // 1 sUSDS = 1.05 USDS

        bo = new GatedMockBO();
        backingVault = new MockSUSDSBackingVaultForProxy();

        // Real feed pointed at the gated BO. Constructor fetch succeeds (oracles healthy).
        feed = new sUSDSPriceFeed(
            address(usdsUsd),
            address(susds),
            USDS_STALENESS,
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
        usdsUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
    }

    // Sanity: healthy path through the proxy returns the composite JPY price, primary mode, no shutdown.
    function test_proxy_healthy_servesCompositeJpyPrice() public {
        (uint256 p, bool fail) = proxy.fetchPrice();
        assertApproxEqRel(p, 157.5e18, 0.001e18); // 1.00 × 1.05 / 0.006667 ≈ ¥157.5
        assertFalse(fail);
        assertFalse(bo.hasBeenShutDown());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_proxy_healthy_appliesBackingRatio() public {
        backingVault.setBackingRatio(0.8e18);

        (uint256 p, bool fail) = proxy.fetchPrice();

        assertApproxEqRel(p, 126e18, 0.001e18);
        assertFalse(fail);
        assertFalse(bo.hasBeenShutDown());
    }

    // M-1 core (USDS/USD stale): proxy shuts the branch down and serves lastGoodPrice.
    // Confirms NO secondary (ETHUSDxCanonical) price is ever served.
    function test_proxy_usdsStale_shutsDownAndServesLastGood() public {
        (uint256 good,) = proxy.fetchPrice(); // prime lastGoodPrice
        vm.warp(block.timestamp + 25 hours); // > USDS staleness (24h)
        jpyUsd.setUpdatedAt(block.timestamp); // keep JPY fresh -> isolate USDS failure

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.hasBeenShutDown());
        assertEq(p, good); // served lastGoodPrice, not a recomputed/secondary price
        // The source NEVER entered secondary mode. (Behind the proxy its priceSource
        // even stays `primary` — its shutdown attempt reverts & rolls back — but it is
        // categorically never ETHUSDxCanonical.)
        assertTrue(feed.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }

    // JPY/USD stale behind the proxy -> soft-freeze, NOT shutdown. The shared JPY leg is
    // systemic across all branches, so the source substitutes the last good JPY rate and
    // returns a valid price; the proxy sees no failure and the branch stays live (the whole
    // proxy + feed + BO stack no longer permanently dies on a JPY hiccup). ORCL-SEC-005.
    function test_proxy_jpyStale_substitutesNoShutdown() public {
        (uint256 good,) = proxy.fetchPrice();
        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours); // > JPY staleness (72h)
        usdsUsd.setUpdatedAt(block.timestamp); // keep USDS fresh -> isolate JPY failure

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertFalse(fail);
        assertFalse(bo.hasBeenShutDown());
        assertEq(p, good); // frozen JPY rate × live (unchanged) USDS leg
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
    }

    function test_proxy_jpyFreezeExpires_proxyShutsDownAndServesLastGood() public {
        proxy.fetchPrice();

        vm.warp(block.timestamp + 73 hours); // enter the bounded JPY freeze
        usdsUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = proxy.fetchPrice();
        assertFalse(freezeFailure);
        assertFalse(bo.hasBeenShutDown());

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        usdsUsd.setPrice(1.1e8);
        usdsUsd.setUpdatedAt(block.timestamp);

        (uint256 p, bool fail) = proxy.fetchPrice();

        assertTrue(fail);
        assertTrue(bo.hasBeenShutDown(), "proxy performs the registered shutdown");
        assertEq(p, frozenPrice, "proxy serves the source's bounded lastGoodPrice");
        assertTrue(jpyRateProvider.jpyFreezeExpired(), "shared expiry latch survives proxy shutdown delegation");
        // Under the proxy topology the source's own BorrowerOperations call reverts on the
        // caller check, so it must not latch here -- see test/JpySharedShutdownLatch.t.sol.
        // The proxy still performs the shutdown from the returned failure=true.
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    // JPY/USD weekend-close age within threshold is not an oracle failure.
    function test_proxy_jpyWeekendCloseWithinThreshold_staysHealthy() public {
        vm.warp(block.timestamp + 60 hours);
        usdsUsd.setUpdatedAt(block.timestamp); // keep USDS fresh; leave JPY at prior close

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertFalse(fail);
        assertFalse(bo.hasBeenShutDown());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertApproxEqRel(p, 157.5e18, 0.001e18);
    }

    // sUSDS canonical-rate revert behind the proxy -> shutdown + lastGoodPrice.
    function test_proxy_canonicalRateRevert_shutsDown() public {
        (uint256 good,) = proxy.fetchPrice();
        susds.setShouldRevert(true);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.hasBeenShutDown());
        assertEq(p, good);
        assertTrue(feed.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }

    // sUSDS canonical-rate zero behind the proxy -> shutdown + lastGoodPrice.
    function test_proxy_canonicalRateZero_shutsDown() public {
        (uint256 good,) = proxy.fetchPrice();
        susds.setRate(0);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.hasBeenShutDown());
        assertEq(p, good);
    }

    // Redemption path behind the proxy also degrades to lastGoodPrice
    // (urgent redemption / CollateralRegistry must not break).
    function test_proxy_redemption_failureDegradesToLastGood() public {
        (uint256 good,) = proxy.fetchRedemptionPrice();
        susds.setShouldRevert(true);
        _refreshAll();

        (uint256 p, bool fail) = proxy.fetchRedemptionPrice();
        assertTrue(fail);
        assertTrue(bo.hasBeenShutDown());
        assertEq(p, good);
    }

    // Direct vs proxy equivalence at the system level: when the feed itself is the
    // registered priceFeed, its shutdown call succeeds (priceSource latches to
    // lastGoodPrice). End-state — branch shut down + lastGoodPrice served — matches
    // the proxy case, and is categorically never ETHUSDxCanonical. (This is exactly
    // why M-1 is N/A for a single-stage feed like sUSDS.)
    function test_direct_failure_endStateMatchesProxy() public {
        GatedMockBO bo2 = new GatedMockBO();
        sUSDSPriceFeed direct = new sUSDSPriceFeed(
            address(usdsUsd),
            address(susds),
            USDS_STALENESS,
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
        assertTrue(bo2.hasBeenShutDown());
        assertEq(p, good);
        // Direct: shutdown completes, so priceSource latches to lastGoodPrice (== 2).
        assertEq(uint256(direct.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertTrue(direct.priceSource() != IMainnetPriceFeed.PriceSource.ETHUSDxCanonical);
    }
}
