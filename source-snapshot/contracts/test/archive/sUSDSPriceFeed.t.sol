// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/archive/sUSDSPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "../TestContracts/ChainlinkOracleMock.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

// Minimal BorrowerOperations stub (the feed calls shutdownFromOracleFailure directly).
contract MockBO {
    bool public shutDownCalled;

    function shutdownFromOracleFailure() external {
        shutDownCalled = true;
    }
}

contract MockUSDSAsset {
    uint8 public decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }
}

// Mock sUSDS (ERC-4626 view). convertToAssets(1e18) = canonical rate (USDS per sUSDS).
contract MockSUSDS {
    address public asset;
    uint8 public decimals = 18;
    uint256 public rate; // USDS per sUSDS, 18-dec
    bool public shouldRevert;

    constructor(address _asset) {
        asset = _asset;
    }

    function setAsset(address a) external {
        asset = a;
    }

    function setDecimals(uint8 d) external {
        decimals = d;
    }

    function setRate(uint256 r) external {
        rate = r;
    }

    function setShouldRevert(bool b) external {
        shouldRevert = b;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (shouldRevert) revert("sUSDS down");
        return Math.mulDiv(shares, rate, 1e18);
    }
}

contract MockSUSDSBackingVault {
    uint256 public ratio = 1e18;
    bool public shouldRevert;
    bool public shouldConsumeAllGas;
    bool public backingUnavailable;

    function setBackingRatio(uint256 r) external {
        ratio = r;
    }

    function setShouldRevert(bool b) external {
        shouldRevert = b;
    }

    function setShouldConsumeAllGas(bool b) external {
        shouldConsumeAllGas = b;
    }

    function setBackingUnavailable(bool b) external {
        backingUnavailable = b;
    }

    function backingRatio() external view returns (uint256) {
        if (shouldConsumeAllGas) {
            assembly {
                invalid()
            }
        }
        if (shouldRevert) revert("backing unavailable");
        return ratio;
    }

    function backingRatioForPricing() external view returns (uint256, bool) {
        if (shouldConsumeAllGas) {
            assembly {
                invalid()
            }
        }
        if (shouldRevert) revert("backing unavailable");
        if (backingUnavailable) return (0, false);
        return (ratio, true);
    }
}

/// @notice Forkless tests for sUSDSPriceFeed (composite rate).
///         Mocks USDS/USD + JPY/USD (ChainlinkOracleMock) and the sUSDS canonical
///         rate (MockSUSDS), so the composite math + shutdown paths are verified
///         without a mainnet fork. Real-mainnet integration is a CI/Phase-6 concern.
contract SUSDSPriceFeedTest is Test {
    ChainlinkOracleMock usdsUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockUSDSAsset usds;
    MockSUSDS susds;
    MockBO bo;
    MockSUSDSBackingVault backingVault;

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

        usds = new MockUSDSAsset(18);
        susds = new MockSUSDS(address(usds));
        susds.setRate(1.05e18); // 1 sUSDS = 1.05 USDS

        bo = new MockBO();
        backingVault = new MockSUSDSBackingVault();
    }

    function _deploy() internal returns (sUSDSPriceFeed) {
        return new sUSDSPriceFeed(
            address(usdsUsd),
            address(susds),
            USDS_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo)
        );
    }

    // --- composite math: sUSDS/JPY = USDS/USD × rate / (JPY/USD) ---

    function test_jpyConversion() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        // 1.00 × 1.05 / 0.006667 ≈ 157.49 → ~¥157.5
        assertApproxEqRel(price, 157.5e18, 0.001e18);
    }

    function test_compositeJpyConversionUsesFullPrecisionMulDiv() public {
        usdsUsd.setPrice(1e50);
        jpyUsd.setPrice(1e8); // JPY/USD = 1, normalized to 1e18
        susds.setRate(2e18);

        sUSDSPriceFeed feed = _deploy();
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 2e60, "final price fits even though intermediate products would overflow");
    }

    function test_rateAffectsPrice() public {
        susds.setRate(1.1e18); // higher canonical rate → higher JPY price
        sUSDSPriceFeed feed = _deploy();
        (uint256 price,) = feed.fetchPrice();
        // 1.00 × 1.10 / 0.006667 ≈ 164.99 → ~¥165
        assertApproxEqRel(price, 165e18, 0.001e18);
    }

    function test_redemptionPriceEqualsPrice() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 p,) = feed.fetchPrice();
        (uint256 rp,) = feed.fetchRedemptionPrice();
        assertEq(p, rp);
    }

    // --- dToken backing ratio ---

    function test_backingRatioDiscountsFetchAndRedemptionPrice() public {
        backingVault.setBackingRatio(0.8e18);
        sUSDSPriceFeed feed = _deploy();

        (uint256 price, bool failure) = feed.fetchPrice();
        (uint256 redemptionPrice, bool redemptionFailure) = feed.fetchRedemptionPrice();

        assertFalse(failure);
        assertFalse(redemptionFailure);
        assertApproxEqRel(price, 126e18, 0.001e18); // 157.5 * 0.8
        assertEq(price, redemptionPrice);
        assertEq(feed.lastGoodBacking(), 0.8e18);
    }

    function test_backingRatioFailureShutsDownAtLastGoodPrice() public {
        backingVault.setBackingRatio(0.8e18);
        sUSDSPriceFeed feed = _deploy();
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

    function test_backingRatioGasGriefing_bubblesInsufficientGas() public {
        backingVault.setBackingRatio(0.8e18);
        sUSDSPriceFeed feed = _deploy();

        (, bool healthyFailure) = feed.fetchPrice{gas: 500_000}();
        assertFalse(healthyFailure);

        backingVault.setShouldConsumeAllGas(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        feed.fetchPrice{gas: 500_000}();
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertFalse(bo.shutDownCalled(), "gas-starved backing read must not shut down branch");
    }

    function test_zeroBackingRatioReturnsNearZeroNonSentinelPrice() public {
        sUSDSPriceFeed feed = _deploy();

        backingVault.setBackingRatio(0);
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertGt(price, 0);
        assertLt(price, 1e18);
        assertEq(feed.lastGoodBacking(), 1);
    }

    // --- failure paths → shutdown ---

    function test_usdsUsdStale_shutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        vm.warp(block.timestamp + 25 hours); // past USDS staleness (24h)
        jpyUsd.setUpdatedAt(block.timestamp); // keep JPY fresh
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
    }

    function test_usdsUsdFutureTimestamp_shutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        usdsUsd.setUpdatedAt(block.timestamp + 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, goodPrice);
    }

    // JPY/USD is a SHARED systemic leg across all branches; a JPY-leg failure must NOT
    // terminally shut the branch down (see DFPriceFeedBase / ORCL-SEC-005). The composite
    // feed substitutes the last good JPY rate and keeps operating; the USDS/USD + canonical
    // legs stay live, so only the (low-vol) FX leg is frozen. Auto-recovers when JPY is fresh.
    function test_jpyUsdStale_substitutesLastGoodRate_noShutdown() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours); // past JPY staleness (72h)
        usdsUsd.setUpdatedAt(block.timestamp); // keep USDS fresh → ONLY the shared JPY leg is stale
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, goodPrice);
    }

    function test_jpyUsdZeroRoundId_substitutesNoShutdown() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        jpyUsd.setRoundData(0, 0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
        assertEq(price, goodPrice);
    }

    function test_jpyUsdFreeze_tracksLiveUsdsLeg() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        // JPY frozen, but USDS/USD keeps updating (USDS richens to $1.10).
        vm.warp(block.timestamp + 73 hours);
        usdsUsd.setPrice(1.1e8);
        usdsUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        // 1.10 × 1.05 / 0.006667 ≈ 173.25: the USDS-leg move IS reflected mid-freeze.
        assertApproxEqRel(price, 173.25e18, 0.001e18);
    }

    function test_jpyUsdFreeze_thenRecovers_repricesWithLiveRate() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertFalse(bo.shutDownCalled());

        // JPY/USD recovers at ¥200/$ (0.005). Auto-resume on the live rate.
        jpyUsd.setPrice(500_000);
        jpyUsd.setUpdatedAt(block.timestamp);
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        // 1.00 × 1.05 / 0.005 = 210
        assertApproxEqRel(price, 210e18, 0.001e18);
    }

    function test_jpyUsdZeroPrice_substitutesNoShutdown() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 goodPrice,) = feed.fetchPrice();

        jpyUsd.setPrice(0); // invalid JPY answer → JPY-leg failure
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(price, goodPrice);
    }

    function test_jpyInvalidAnswerWhileCachedRateFreshStartsFreezeAtObservation() public {
        sUSDSPriceFeed feed = _deploy();
        assertEq(jpyRateProvider.lastGoodJpyUpdatedAt(), block.timestamp, "provider stores cached rate provenance");

        vm.warp(block.timestamp + 10 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(
            jpyRateProvider.lastGoodJpyUpdatedAt(), block.timestamp, "healthy read refreshes cached rate provenance"
        );

        vm.warp(block.timestamp + 10 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setPrice(0);

        (, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
    }

    function test_jpyInvalidAnswerAfterCachedRateExpiredShutsDownImmediately() public {
        sUSDSPriceFeed feed = _deploy();
        uint256 expectedFreezeStart = jpyRateProvider.lastGoodJpyUpdatedAt() + JPY_STALENESS;

        vm.warp(expectedFreezeStart + jpyRateProvider.MAX_JPY_FREEZE_DURATION() + 1);
        usdsUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setPrice(0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
        assertEq(price, feed.lastGoodPrice());
    }

    function test_usdsUsdStale_duringJpyStale_stillShutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        // BOTH the USDS/USD (collateral) leg and JPY leg stale: the collateral leg is
        // checked first and still shuts down terminally; the JPY freeze never masks it.
        vm.warp(block.timestamp + 73 hours);
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
    }

    // --- JPY freeze observability ---

    function test_jpyFreeze_setsAndClearsFrozenSince() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), 0);

        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);

        jpyUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), 0);
    }

    function test_jpyFreeze_emitsFrozenAndUnfrozenEvents() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        vm.expectEmit(true, true, true, true, address(jpyRateProvider));
        emit JpyUsdRateProvider.JpyRateFrozen(expectedFreezeStart, jpyRateProvider.lastGoodJpyRate());
        feed.fetchPrice();

        jpyUsd.setUpdatedAt(block.timestamp);
        vm.expectEmit(true, true, true, true, address(jpyRateProvider));
        emit JpyUsdRateProvider.JpyRateUnfrozen(block.timestamp, uint256(JPY_USD_8DEC) * 1e10);
        feed.fetchPrice();
    }

    function test_jpyFreezeExpires_shutsDownAtLastGoodPrice() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        usdsUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = feed.fetchPrice();
        assertFalse(freezeFailure, "fresh freeze stays live");
        assertFalse(bo.shutDownCalled());

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        usdsUsd.setPrice(1.1e8);
        usdsUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(price, frozenPrice, "expired freeze serves the last bounded-good price");
        assertEq(price, feed.lastGoodPrice());
    }

    function test_jpyStaleBeforeFirstCallPastFreezeWindowShutsDownImmediately() public {
        sUSDSPriceFeed feed = _deploy();
        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;

        vm.warp(expectedFreezeStart + jpyRateProvider.MAX_JPY_FREEZE_DURATION() + 1);
        usdsUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
        assertEq(price, feed.lastGoodPrice());
    }

    function test_jpyUsdWeekendCloseWithinThreshold_keepsPrimary() public {
        sUSDSPriceFeed feed = _deploy();

        // FX weekend behavior: JPY/USD can remain at its last healthy close while
        // the crypto/stable collateral feed keeps updating.
        vm.warp(block.timestamp + 60 hours);
        usdsUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertApproxEqRel(price, 157.5e18, 0.001e18);
    }

    function test_jpyUsdStalenessBoundary_substitutesNoShutdown() public {
        sUSDSPriceFeed feed = _deploy();
        feed.fetchPrice();

        // MainnetPriceFeedBase requires age < threshold, so exactly 72h is stale.
        // JPY-only stale at the boundary → substitute, not shutdown.
        vm.warp(block.timestamp + JPY_STALENESS);
        usdsUsd.setUpdatedAt(block.timestamp);

        (, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
    }

    function test_canonicalRateZero_shutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        susds.setRate(0); // convertToAssets(1e18) == 0 → rate down
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
    }

    function test_canonicalRateRevert_shutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        susds.setShouldRevert(true); // convertToAssets reverts → caught → rate down
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
    }

    function test_usdsUsdZeroPrice_shutsDown() public {
        sUSDSPriceFeed feed = _deploy();
        usdsUsd.setPrice(0); // invalid
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
    }

    function test_afterShutdown_returnsLastGoodPrice() public {
        sUSDSPriceFeed feed = _deploy();
        (uint256 good,) = feed.fetchPrice();

        usdsUsd.setPrice(0);
        feed.fetchPrice(); // shutdown
        assertTrue(bo.shutDownCalled());

        usdsUsd.setPrice(1e8); // even if it "recovers"
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertEq(price, good);
    }

    // --- constructor asserts ---

    function test_constructorReverts_ifUsdsOracleDeadAtDeploy() public {
        usdsUsd.setPrice(0);
        vm.expectRevert();
        _deploy();
    }

    function test_constructorReverts_ifJpyDecimalsNot8() public {
        jpyUsd.setDecimals(18);
        vm.expectRevert(JpyUsdRateProvider.UnexpectedOracleDecimals.selector);
        new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);
    }

    function test_constructorReverts_ifSusdsHasNoCode() public {
        vm.expectRevert(sUSDSPriceFeed.InvalidRateProvider.selector);
        new sUSDSPriceFeed(
            address(usdsUsd),
            makeAddr("no-code-susds"),
            USDS_STALENESS,
            address(jpyRateProvider),
            address(backingVault),
            address(bo)
        );
    }

    function test_constructorReverts_ifSusdsAssetHasNoCode() public {
        susds.setAsset(makeAddr("no-code-usds"));
        vm.expectRevert(sUSDSPriceFeed.InvalidRateProvider.selector);
        _deploy();
    }

    function test_constructorReverts_ifSusdsDecimalsNot18() public {
        susds.setDecimals(6);
        vm.expectRevert(sUSDSPriceFeed.InvalidRateProviderDecimals.selector);
        _deploy();
    }

    function test_constructorReverts_ifSusdsAssetDecimalsNot18() public {
        susds.setAsset(address(new MockUSDSAsset(6)));
        vm.expectRevert(sUSDSPriceFeed.InvalidRateProviderDecimals.selector);
        _deploy();
    }

    function test_constructorReverts_ifCollateralVaultHasNoCode() public {
        vm.expectRevert(sUSDSPriceFeed.InvalidCollateralVault.selector);
        new sUSDSPriceFeed(
            address(usdsUsd),
            address(susds),
            USDS_STALENESS,
            address(jpyRateProvider),
            makeAddr("no-code-vault"),
            address(bo)
        );
    }
}
