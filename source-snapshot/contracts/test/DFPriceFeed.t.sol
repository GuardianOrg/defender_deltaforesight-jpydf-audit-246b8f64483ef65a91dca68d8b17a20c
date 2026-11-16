// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/DFUSDCPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "src/PriceFeeds/MainnetPriceFeedBase.sol";
import "./TestContracts/ChainlinkOracleMock.sol";
import "./TestContracts/GasGuzzlerOracle.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

// Minimal permissive BorrowerOperations stub for direct-source unit tests. Production
// registers PriceFeedProxy instead; the dedicated proxy integration suites exercise
// that authorization boundary and delegated shutdown path.
contract MockBO {
    bool public shutDownCalled;

    function shutdownFromOracleFailure() external {
        shutDownCalled = true;
    }
}

contract MockBackingVault {
    uint256 public ratio = 1e18;
    bool public shouldRevert;
    bool public shouldConsumeAllGas;
    bool public backingUnavailable;

    function setBackingRatio(uint256 _ratio) external {
        ratio = _ratio;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldConsumeAllGas(bool _shouldConsumeAllGas) external {
        shouldConsumeAllGas = _shouldConsumeAllGas;
    }

    function setBackingUnavailable(bool _backingUnavailable) external {
        backingUnavailable = _backingUnavailable;
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

/// @notice Forkless tests for the active USDC Standard JPY feed. Candidate-asset
///         wrappers and composite feeds are preserved under test/archive/.
///         Uses ChainlinkOracleMock for both the collateral/USD and JPY/USD
///         aggregators, so the JPY-conversion math, staleness handling, and
///         oracle-failure shutdown path are verified without a mainnet fork.
///         Integration against the real mainnet Chainlink addresses is a CI/Phase-6
///         concern (requires MAINNET_RPC_URL).
contract DFPriceFeedTest is Test {
    using stdStorage for StdStorage;

    ChainlinkOracleMock collUsd;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockBO bo;
    MockBackingVault backingVault;

    uint256 constant COLL_STALENESS = 24 hours;
    uint256 constant JPY_STALENESS = 72 hours;

    // JPY/USD = 0.006667 USD per JPY (≈ ¥150 per $1), 8-decimal Chainlink.
    int256 constant JPY_USD_8DEC = 666_700;

    function setUp() public {
        // A realistic, non-trivial timestamp so staleness arithmetic is meaningful.
        vm.warp(1_700_000_000);

        collUsd = new ChainlinkOracleMock();
        collUsd.setDecimals(8);
        collUsd.setUpdatedAt(block.timestamp);

        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(JPY_USD_8DEC);
        jpyUsd.setUpdatedAt(block.timestamp);
        jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);

        bo = new MockBO();
        backingVault = new MockBackingVault();
    }

    function _deployStandardFeed() internal returns (DFUSDCPriceFeed) {
        return new DFUSDCPriceFeed(
            address(collUsd), COLL_STALENESS, address(jpyRateProvider), address(backingVault), address(bo)
        );
    }

    function _jpyFromUsd(uint256 usdPrice) internal pure returns (uint256) {
        return Math.mulDiv(usdPrice, 1e18, uint256(JPY_USD_8DEC) * 1e10);
    }

    // =========================================================
    //  JPY conversion — numeric checks (Coll/JPY = Coll/USD / (JPY/USD))
    // =========================================================

    function test_StandardFeed_jpyConversion() public {
        collUsd.setPrice(3000e8); // ETH = $3,000
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        // 3000 / 0.006667 ≈ 449,977 → ~¥450,000
        assertApproxEqRel(price, 450_000e18, 0.001e18); // within 0.1%
    }

    function test_urgentPriceRejectsLegacyTerminalSourceCache() public {
        collUsd.setPrice(1e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 lastGoodPrice = feed.lastGoodPrice();

        stdstore.target(address(feed)).sig(IMainnetPriceFeed.priceSource.selector)
            .checked_write(uint256(IMainnetPriceFeed.PriceSource.lastGoodPrice));

        (uint256 price, bool failure) = feed.fetchUrgentRedemptionPrice();
        assertEq(price, lastGoodPrice);
        assertTrue(failure);
    }

    function test_StandardFeed_jpyConversionUsesFullPrecisionMulDiv() public {
        collUsd.setPrice(1e50);
        jpyUsd.setPrice(1e8); // JPY/USD = 1, normalized to 1e18

        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(price, 1e60, "final price fits even though usdPrice * 1e18 would overflow");
    }

    function test_USDC_jpyConversion() public {
        collUsd.setPrice(1e8); // USDC = $1.00
        DFUSDCPriceFeed feed = new DFUSDCPriceFeed(
            address(collUsd), COLL_STALENESS, address(jpyRateProvider), address(backingVault), address(bo)
        );
        (uint256 price,) = feed.fetchPrice();
        assertApproxEqRel(price, 150e18, 0.001e18); // ~¥150
    }

    function test_USDCDepegAndBackingDiscountCompoundDownward() public {
        collUsd.setPrice(72_000_000); // USDC = $0.72
        backingVault.setBackingRatio(75e16); // dUSDC backing = 75%
        DFUSDCPriceFeed feed = new DFUSDCPriceFeed(
            address(collUsd), COLL_STALENESS, address(jpyRateProvider), address(backingVault), address(bo)
        );

        uint256 marketJpy = _jpyFromUsd(72e16);
        uint256 expected = Math.mulDiv(marketJpy, 75e16, 1e18);

        (uint256 price, bool failure) = feed.fetchPrice();
        (uint256 redemptionPrice, bool redemptionFailure) = feed.fetchRedemptionPrice();

        assertFalse(failure);
        assertFalse(redemptionFailure);
        assertEq(price, expected, "USDC market depeg and dToken backing both discount price");
        assertEq(redemptionPrice, expected, "redemption price uses the same compounded discount");
        assertLt(price, _jpyFromUsd(1e18), "depegged price must be below par USDC/JPY");
        assertEq(feed.lastGoodBacking(), 75e16);
    }

    // =========================================================
    //  Redemption price == price (Standard feeds)
    // =========================================================

    function test_redemptionPriceEqualsPrice() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 p,) = feed.fetchPrice();
        (uint256 rp,) = feed.fetchRedemptionPrice();
        assertEq(p, rp);
    }

    function test_urgentRedemptionPriceEqualsPriceForStandardFeed() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 p,) = feed.fetchPrice();
        (uint256 redemptionPrice,) = feed.fetchRedemptionPrice();
        (uint256 urgentPrice, bool failure) = feed.fetchUrgentRedemptionPrice();
        assertFalse(failure);
        assertEq(p, urgentPrice);
        assertEq(redemptionPrice, urgentPrice, "proxy continuity assumes urgent == redemption");
    }

    // =========================================================
    //  dToken backing ratio — price is down-only adjusted
    // =========================================================

    function test_backingRatioDiscountsFetchAndRedemptionPrice() public {
        collUsd.setPrice(3000e8);
        backingVault.setBackingRatio(0.8e18);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        (uint256 price, bool failure) = feed.fetchPrice();
        (uint256 redemptionPrice, bool redemptionFailure) = feed.fetchRedemptionPrice();

        assertFalse(failure);
        assertFalse(redemptionFailure);
        assertApproxEqRel(price, 360_000e18, 0.001e18);
        assertEq(price, redemptionPrice);
        assertEq(feed.lastGoodBacking(), 0.8e18);
    }

    function test_backingRatioFailureShutsDownAtLastGoodPrice() public {
        collUsd.setPrice(3000e8);
        backingVault.setBackingRatio(0.8e18);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 discounted,) = feed.fetchPrice();

        backingVault.setBackingRatio(0.5e18);
        backingVault.setShouldRevert(true);
        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, discounted, "shutdown serves last good price");
        assertEq(feed.lastGoodBacking(), 0.8e18);
    }

    function test_backingRatioRecoveryRepricesWithoutBranchShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 basePrice,) = feed.fetchPrice();

        backingVault.setBackingRatio(0.6e18);
        (uint256 impairedPrice, bool impairedFailure) = feed.fetchPrice();

        assertFalse(impairedFailure);
        assertFalse(bo.shutDownCalled(), "accounted backing loss keeps branch live");
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(impairedPrice, Math.mulDiv(basePrice, 0.6e18, 1e18));
        assertEq(feed.lastGoodBacking(), 0.6e18);

        backingVault.setBackingRatio(1e18);
        (uint256 recoveredPrice, bool recoveredFailure) = feed.fetchPrice();

        assertFalse(recoveredFailure);
        assertFalse(bo.shutDownCalled(), "backing recovery must not need branch restart");
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(recoveredPrice, basePrice, "backstop or strategy recovery restores oracle value");
        assertEq(feed.lastGoodBacking(), 1e18);
    }

    function test_backingRatioReadFailureRecoversOnFreshRead() public {
        collUsd.setPrice(3000e8);
        backingVault.setBackingRatio(0.8e18);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 lastLivePrice,) = feed.fetchPrice();

        backingVault.setShouldRevert(true);
        (uint256 shutdownPrice, bool shutdownFailure) = feed.fetchPrice();

        assertTrue(shutdownFailure);
        assertTrue(bo.shutDownCalled(), "backing read failure is a branch oracle failure");
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(shutdownPrice, lastLivePrice, "shutdown serves the last live price");

        backingVault.setShouldRevert(false);
        backingVault.setBackingRatio(1e18);
        collUsd.setPrice(3500e8);

        (uint256 recoveredReadPrice, bool recoveredReadFailure) = feed.fetchPrice();

        assertFalse(recoveredReadFailure);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertGt(recoveredReadPrice, lastLivePrice, "source recovery restores live pricing");
        assertEq(feed.lastGoodPrice(), recoveredReadPrice);
    }

    function test_backingRatioGasGriefing_bubblesInsufficientGas() public {
        collUsd.setPrice(3000e8);
        backingVault.setBackingRatio(0.8e18);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        (, bool healthyFailure) = feed.fetchPrice{gas: 500_000}();
        assertFalse(healthyFailure);

        backingVault.setShouldConsumeAllGas(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        feed.fetchPrice{gas: 500_000}();
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertFalse(bo.shutDownCalled(), "gas-starved backing read must not shut down branch");
    }

    function test_backingRatioAboveOneIsCapped() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 basePrice,) = feed.fetchPrice();

        backingVault.setBackingRatio(1.2e18);
        (uint256 cappedPrice, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertEq(cappedPrice, basePrice);
        assertEq(feed.lastGoodBacking(), 1e18);
    }

    function test_zeroBackingRatioReturnsNearZeroNonSentinelPrice() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        backingVault.setBackingRatio(0);
        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertGt(price, 0, "zero is an invalid oracle sentinel");
        assertLt(price, 1e18, "complete loss is represented as near-zero");
        assertEq(feed.lastGoodBacking(), 1);
    }

    // =========================================================
    //  Staleness / oracle failure → branch shutdown
    // =========================================================

    function test_collUsdStale_shutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        // Advance past coll/USD staleness (24h); keep JPY fresh so only coll/USD is stale.
        vm.warp(block.timestamp + 25 hours);
        jpyUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, feed.lastGoodPrice());
    }

    function test_collUsdAnsweredInRoundBehindRoundId_shutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 goodPrice = feed.lastGoodPrice();

        collUsd.setRoundData(2, 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, goodPrice);
        assertEq(price, feed.lastGoodPrice());
    }

    function test_collUsdZeroRoundId_shutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 goodPrice = feed.lastGoodPrice();

        collUsd.setRoundData(0, 0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, goodPrice);
        assertEq(price, feed.lastGoodPrice());
    }

    function test_collUsdFutureTimestamp_shutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 goodPrice = feed.lastGoodPrice();

        collUsd.setUpdatedAt(block.timestamp + 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, goodPrice);
        assertEq(price, feed.lastGoodPrice());
    }

    // JPY/USD is a SHARED systemic leg across all branches. Unlike the per-branch
    // collateral/USD oracle, a JPY-leg failure must NOT synchronously stop the branch
    // (that would turn an isolated fail-safe into a global one). Instead the feed
    // substitutes the last good JPY rate and keeps operating; collateral/USD stays live,
    // so the price still tracks the (high-vol) collateral and only the (low-vol) FX leg
    // is frozen. Auto-recovers when JPY/USD is fresh again.
    function test_jpyUsdStale_substitutesLastGoodRate_noShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 goodPrice,) = feed.fetchPrice();

        // Advance past JPY staleness (72h); refresh coll/USD so ONLY the shared JPY leg is stale.
        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        // Frozen JPY rate × live (unchanged) collateral → price unchanged.
        assertApproxEqRel(price, 450_000e18, 0.001e18);
        assertEq(price, goodPrice);
    }

    function test_sharedProviderKeepsFeedsAtSameJpyRateAndFreezeTime() public {
        collUsd.setPrice(1e8);
        DFUSDCPriceFeed olderFeed = _deployStandardFeed();

        vm.warp(block.timestamp + 1 hours);
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setPrice(500_000); // JPY/USD = 0.005, or 200 JPY per USD
        jpyUsd.setUpdatedAt(block.timestamp);
        DFUSDCPriceFeed newerFeed = _deployStandardFeed();

        vm.warp(block.timestamp + JPY_STALENESS + 1);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 olderPrice, bool olderFailure) = olderFeed.fetchPrice();
        (uint256 newerPrice, bool newerFailure) = newerFeed.fetchPrice();

        assertFalse(olderFailure);
        assertFalse(newerFailure);
        assertEq(address(olderFeed.jpyUsdRateProvider()), address(newerFeed.jpyUsdRateProvider()));
        assertEq(olderPrice, newerPrice, "all feeds use the provider's single frozen JPY rate");
        assertEq(jpyRateProvider.lastGoodJpyRate(), uint256(500_000) * 1e10);
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp - 1);
    }

    function test_freshRecoveryRestoresAllSourceReads() public {
        collUsd.setPrice(1e8);
        DFUSDCPriceFeed firstFeed = _deployStandardFeed();
        DFUSDCPriceFeed dormantFeed = _deployStandardFeed();
        uint256 dormantPriceBefore = dormantFeed.lastGoodPrice();
        uint256 freezeStart = block.timestamp + JPY_STALENESS;

        vm.warp(freezeStart + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        collUsd.setUpdatedAt(block.timestamp);
        (, bool firstFailure) = firstFeed.fetchPrice();

        assertTrue(firstFailure);
        assertTrue(jpyRateProvider.jpyFreezeExpired());

        jpyUsd.setPrice(500_000);
        jpyUsd.setUpdatedAt(block.timestamp);
        (uint256 recoveredPrice, bool dormantFailure) = dormantFeed.fetchPrice();

        assertFalse(dormantFailure, "fresh recovery starts a new provider episode");
        assertEq(uint256(dormantFeed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.lastGoodJpyRate(), uint256(500_000) * 1e10);
        assertEq(jpyRateProvider.jpyFrozenSince(), 0);
        assertFalse(jpyRateProvider.jpyFreezeExpired());
        assertEq(recoveredPrice, 200e18, "dormant branch uses the recovered live JPY rate");
        assertNotEq(recoveredPrice, dormantPriceBefore);

        // A feed that observed expiry also reports the recovered source. Core remains paused
        // until the registered PriceFeedProxy owner explicitly resumes it.
        (uint256 firstPriceAfterRecovery, bool firstFailureAfterRecovery) = firstFeed.fetchPrice();
        assertFalse(firstFailureAfterRecovery);
        assertEq(uint256(firstFeed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(firstPriceAfterRecovery, recoveredPrice);
    }

    function test_jpyUsdAnsweredInRoundBehindRoundId_substitutesLastGoodRate_noShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 goodPrice,) = feed.fetchPrice();

        jpyUsd.setRoundData(2, 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
        assertEq(price, goodPrice);
    }

    function test_jpyUsdZeroRoundId_substitutesLastGoodRate_noShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 goodPrice,) = feed.fetchPrice();

        jpyUsd.setRoundData(0, 0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
        assertEq(price, goodPrice);
    }

    function test_jpyUsdFutureTimestamp_substitutesLastGoodRate_noShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 goodPrice,) = feed.fetchPrice();

        jpyUsd.setUpdatedAt(block.timestamp + 1);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
        assertEq(price, goodPrice);
    }

    function test_jpyUsdFreeze_tracksLiveCollateral() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        // JPY/USD frozen (stale), but collateral/USD keeps updating and rises 10%.
        vm.warp(block.timestamp + 73 hours);
        collUsd.setPrice(3300e8);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        // 3300 / 0.006667 ≈ 494,975 → ~¥495,000: the collateral move IS reflected mid-freeze.
        assertApproxEqRel(price, 495_000e18, 0.001e18);
    }

    function test_jpyUsdFreeze_thenRecovers_repricesWithLiveRate() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        // Freeze the JPY leg.
        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertFalse(bo.shutDownCalled());

        // JPY/USD recovers with a fresh, different rate (¥200/$). Auto-resume on the live rate.
        jpyUsd.setPrice(500_000); // 0.005 USD per JPY
        jpyUsd.setUpdatedAt(block.timestamp);
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertApproxEqRel(price, 600_000e18, 0.001e18); // 3000 / 0.005
    }

    // --- JPY freeze observability (for monitoring + the governance recovery path) ---

    function test_jpyFreeze_setsAndClearsFrozenSince() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), 0, "not frozen while healthy");

        // Enter the freeze.
        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart, "freeze onset anchored to stale boundary");

        // JPY/USD recovers → freeze cleared.
        jpyUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), 0, "freeze cleared on recovery");
    }

    function test_jpyFrozenSince_recordedOnceDuringContinuousFreeze() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        uint256 onset = jpyRateProvider.jpyFrozenSince();

        // A later fetch while still frozen must NOT advance the onset timestamp.
        vm.warp(block.timestamp + 10 hours);
        collUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(jpyRateProvider.jpyFrozenSince(), onset, "onset is sticky during a continuous freeze");
    }

    function test_jpyFreezeExpires_shutsDownAtLastGoodPrice() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = feed.fetchPrice();
        assertFalse(freezeFailure, "fresh freeze stays live");
        assertFalse(bo.shutDownCalled());

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        collUsd.setPrice(3300e8);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(price, frozenPrice, "expired freeze serves the last bounded-good price");
        assertEq(price, feed.lastGoodPrice());
    }

    function test_jpyStaleBeforeFirstCallPastFreezeWindowShutsDownImmediately() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;

        vm.warp(expectedFreezeStart + jpyRateProvider.MAX_JPY_FREEZE_DURATION() + 1);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
        assertEq(price, feed.lastGoodPrice());
    }

    function test_jpyFreeze_emitsFrozenAndUnfrozenEvents() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        uint256 expectedFreezeStart = block.timestamp + JPY_STALENESS;
        vm.warp(block.timestamp + 73 hours);
        collUsd.setUpdatedAt(block.timestamp);
        vm.expectEmit(true, true, true, true, address(jpyRateProvider));
        emit JpyUsdRateProvider.JpyRateFrozen(expectedFreezeStart, jpyRateProvider.lastGoodJpyRate());
        feed.fetchPrice();

        jpyUsd.setUpdatedAt(block.timestamp);
        vm.expectEmit(true, true, true, true, address(jpyRateProvider));
        emit JpyUsdRateProvider.JpyRateUnfrozen(block.timestamp, uint256(JPY_USD_8DEC) * 1e10);
        feed.fetchPrice();
    }

    function test_collUsdStale_duringJpyStale_stillShutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        // BOTH legs stale: the per-branch collateral leg is checked first and still shuts
        // down terminally. The JPY soft-freeze never masks a collateral-leg failure.
        vm.warp(block.timestamp + 73 hours);
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
    }

    function test_jpyUsdWeekendCloseWithinThreshold_keepsPrimary() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        // Simulate a normal FX weekend: JPY/USD remains at the Friday close, while
        // the collateral/USD feed continues updating. This must remain healthy.
        vm.warp(block.timestamp + 60 hours);
        collUsd.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertApproxEqRel(price, 450_000e18, 0.001e18);
    }

    function test_jpyUsdStalenessBoundary_substitutesNoShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        feed.fetchPrice();

        // MainnetPriceFeedBase requires age < threshold, so exactly 72h is stale.
        // JPY-only stale at the boundary → substitute, not shutdown.
        vm.warp(block.timestamp + JPY_STALENESS);
        collUsd.setUpdatedAt(block.timestamp);

        (, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
    }

    function test_jpyUsdOracleCanBeReplacedViaSourceSwap() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed oldSource = _deployStandardFeed();
        oldSource.fetchPrice(); // warm lastGoodPrice before wiring the source behind the proxy
        PriceFeedProxy proxy = new PriceFeedProxy(address(oldSource), address(this), address(bo));

        (uint256 oldPrice, bool oldFailure) = proxy.fetchPrice();
        assertFalse(oldFailure);
        assertApproxEqRel(oldPrice, 450_000e18, 0.001e18);

        ChainlinkOracleMock newJpyUsd = new ChainlinkOracleMock();
        newJpyUsd.setDecimals(8);
        newJpyUsd.setPrice(500_000); // JPY/USD = 0.005 USD per JPY => ¥200 per $1
        newJpyUsd.setUpdatedAt(block.timestamp);

        JpyUsdRateProvider newProvider = new JpyUsdRateProvider(address(newJpyUsd), JPY_STALENESS);
        DFUSDCPriceFeed newSource = new DFUSDCPriceFeed(
            address(collUsd), COLL_STALENESS, address(newProvider), address(backingVault), address(bo)
        );

        proxy.proposeSource(address(newSource));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        collUsd.setUpdatedAt(block.timestamp);
        newJpyUsd.setUpdatedAt(block.timestamp);
        vm.expectRevert();
        proxy.confirmSource();

        proxy.confirmSourceEmergency();

        assertEq(proxy.source(), address(newSource), "proxy source switched");

        (uint256 newPrice, bool newFailure) = proxy.fetchPrice();
        assertFalse(newFailure);
        assertApproxEqRel(newPrice, 600_000e18, 0.001e18);
        assertGt(newPrice, oldPrice, "JPY/USD source change reprices collateral");
    }

    function test_collUsdZeroPrice_shutsDown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        collUsd.setPrice(0); // invalid (answer <= 0)
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
    }

    function test_jpyUsdZeroPrice_substitutesNoShutdown() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 goodPrice,) = feed.fetchPrice();

        // An invalid (0/negative) JPY answer is a JPY-leg failure like staleness:
        // substitute the last good rate rather than shut the whole protocol down.
        jpyUsd.setPrice(0);
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(price, goodPrice);
    }

    function test_jpyInvalidAnswerWhileCachedRateFreshStartsFreezeAtObservation() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        assertEq(jpyRateProvider.lastGoodJpyUpdatedAt(), block.timestamp, "provider stores cached rate provenance");

        vm.warp(block.timestamp + 10 hours);
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
        feed.fetchPrice();
        assertEq(
            jpyRateProvider.lastGoodJpyUpdatedAt(), block.timestamp, "healthy read refreshes cached rate provenance"
        );

        vm.warp(block.timestamp + 10 hours);
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setPrice(0);

        (, bool failure) = feed.fetchPrice();

        assertFalse(failure);
        assertFalse(bo.shutDownCalled());
        assertEq(jpyRateProvider.jpyFrozenSince(), block.timestamp);
    }

    function test_jpyInvalidAnswerAfterCachedRateExpiredShutsDownImmediately() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        uint256 expectedFreezeStart = jpyRateProvider.lastGoodJpyUpdatedAt() + JPY_STALENESS;

        vm.warp(expectedFreezeStart + jpyRateProvider.MAX_JPY_FREEZE_DURATION() + 1);
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setPrice(0);

        (uint256 price, bool failure) = feed.fetchPrice();

        assertTrue(failure);
        assertTrue(bo.shutDownCalled());
        assertEq(jpyRateProvider.jpyFrozenSince(), expectedFreezeStart);
        assertEq(price, feed.lastGoodPrice());
    }

    // =========================================================
    //  After temporary shutdown, source recovery is observable
    // =========================================================

    function test_afterOracleRecovery_returnsLivePrice() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();
        (uint256 good,) = feed.fetchPrice();

        collUsd.setPrice(0);
        feed.fetchPrice(); // triggers shutdown
        assertTrue(bo.shutDownCalled());

        // The source reports recovery; Core remains paused until PriceFeedProxy owner resumes.
        collUsd.setPrice(3500e8);
        (uint256 price, bool failure) = feed.fetchPrice();
        assertFalse(failure);
        assertGt(price, good);
        assertEq(feed.lastGoodPrice(), price);
    }

    // =========================================================
    //  Constructor liveness / decimals asserts
    // =========================================================

    function test_constructorReverts_ifCollOracleDeadAtDeploy() public {
        // collUsd price left at 0 → _fetchPricePrimary in the constructor shuts down,
        // then `assert(priceSource == primary)` fails.
        vm.expectRevert();
        _deployStandardFeed();
    }

    function test_constructorReverts_ifJpyDecimalsNot8() public {
        collUsd.setPrice(3000e8);
        jpyUsd.setDecimals(18);
        vm.expectRevert(JpyUsdRateProvider.UnexpectedOracleDecimals.selector);
        new JpyUsdRateProvider(address(jpyUsd), JPY_STALENESS);
    }

    function test_constructorReverts_ifCollDecimalsNot8() public {
        collUsd.setPrice(3000e8);
        collUsd.setDecimals(18); // violates the inherited assert(ethUsdOracle.decimals == 8)
        vm.expectRevert();
        _deployStandardFeed();
    }

    function test_constructorReverts_ifCollateralVaultHasNoCode() public {
        collUsd.setPrice(3000e8);
        vm.expectRevert(DFPriceFeedBase.InvalidCollateralVault.selector);
        new DFUSDCPriceFeed(
            address(collUsd), COLL_STALENESS, address(jpyRateProvider), makeAddr("no-code-vault"), address(bo)
        );
    }

    // =========================================================
    //  Gas-griefing guard is preserved for the DF-added JPY/USD read
    // =========================================================
    //  Mirror of the upstream gas-griefing guard pattern. A low-gas call in
    //  which the JPY/USD oracle runs out of gas must bubble
    //  InsufficientGasForExternalCall — NOT silently shut the branch down — so the
    //  upstream gas-griefing guard still protects the SECOND (JPY) Chainlink read
    //  that DFPriceFeedBase adds on top of the upstream collateral/USD read.

    function test_jpyUsdGasGriefing_bubblesInsufficientGas() public {
        collUsd.setPrice(3000e8);
        DFUSDCPriceFeed feed = _deployStandardFeed();

        // With ample gas and healthy oracles, fetchPrice() succeeds at 500k gas.
        (bool ok,) = address(feed).call{gas: 500_000}(abi.encodeWithSignature("fetchPrice()"));
        assertTrue(ok);

        // Etch a gas guzzler over the JPY/USD oracle so its latestRoundData() OOGs.
        // coll/USD still returns a valid price, so the OOG occurs on the JPY read.
        GasGuzzlerOracle guzzler = new GasGuzzlerOracle();
        vm.etch(address(jpyUsd), address(guzzler).code);

        // The inherited guard must re-revert (not shut down): a gas-starved call
        // cannot force a false branch shutdown via the DF-added JPY read.
        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        (bool revertsAsExpected,) = address(feed).call{gas: 500_000}(abi.encodeWithSignature("fetchPrice()"));
        assertTrue(revertsAsExpected);
    }
}
