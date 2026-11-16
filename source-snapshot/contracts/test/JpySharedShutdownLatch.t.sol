// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/DFUSDCPriceFeed.sol";
import "src/PriceFeeds/DFWstETHPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IMainnetPriceFeed.sol";
import "./TestContracts/ChainlinkOracleMock.sol";

contract GatedMockBO2 {
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

contract MockWstETH2 {
    uint8 public decimals = 18;
    uint256 public rate;

    function setRate(uint256 r) external {
        rate = r;
    }

    function stEthPerToken() external view returns (uint256) {
        return rate;
    }
}

contract MockBackingVault2 {
    function backingRatio() external pure returns (uint256) {
        return 1e18;
    }

    function backingRatioForPricing() external pure returns (uint256, bool) {
        return (1e18, true);
    }
}

contract JpySharedShutdownLatchTest is Test {
    ChainlinkOracleMock stEthUsd;
    ChainlinkOracleMock ethUsd;
    ChainlinkOracleMock stEthEth;
    ChainlinkOracleMock jpyUsd;
    JpyUsdRateProvider jpyRateProvider;
    MockWstETH2 wstEth;
    GatedMockBO2 bo;
    MockBackingVault2 backingVault;
    DFWstETHPriceFeed feed;
    PriceFeedProxy proxy;

    address constant ATTACKER = address(0xBAD);

    uint256 constant STETH_STALENESS = 24 hours;
    uint256 constant ETH_STALENESS = 2 hours;
    uint256 constant STETH_ETH_STALENESS = 25 hours;
    uint256 constant JPY_STALENESS = 72 hours;
    int256 constant JPY_USD_8DEC = 666_700;

    function setUp() public {
        vm.warp(1_700_000_000);

        stEthUsd = new ChainlinkOracleMock();
        stEthUsd.setDecimals(8);
        stEthUsd.setPrice(3000e8);
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

        wstEth = new MockWstETH2();
        wstEth.setRate(1.2e18);

        bo = new GatedMockBO2();
        backingVault = new MockBackingVault2();

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

        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    /// Attacker consumes the one-shot JPY-expiry failure signal by calling the SOURCE feed
    /// directly. BO never shuts down, and the proxy never learns about the failure.
    function test_directCallCannotConsumeTheSharedShutdownSignal() public {
        proxy.fetchPrice();

        // Enter the bounded JPY freeze (JPY oracle stops updating; stETH stays fresh).
        vm.warp(block.timestamp + 73 hours);
        stEthUsd.setUpdatedAt(block.timestamp);
        (uint256 frozenPrice, bool freezeFailure) = proxy.fetchPrice();
        assertFalse(freezeFailure);
        assertFalse(bo.isOracleFailureShutdown());

        // Let the 24h freeze window expire.
        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        stEthUsd.setPrice(3300e8); // real price moved +10%
        stEthUsd.setUpdatedAt(block.timestamp);

        // ---- ATTACK: unprivileged EOA calls the SOURCE feed directly, not the proxy ----
        vm.prank(ATTACKER);
        (uint256 attackerPrice, bool attackerFail) = feed.fetchPrice();
        assertTrue(attackerFail, "source reported the failure to the attacker");
        assertEq(attackerPrice, frozenPrice);

        // The BorrowerOperations call reverted on the caller check, so the feed must NOT have
        // latched its terminal source state. Leaving it at primary is what keeps the signal
        // available to the registered proxy.
        // Under the proxy topology the source's own BorrowerOperations call reverts on the
        // caller check, so it must NOT latch. If it did, the next proxy fetch would take
        // _fetchPriceDuringShutdown and report (lastGoodPrice, false) -- a frozen price
        // served as healthy, forever.
        assertEq(
            uint256(feed.priceSource()),
            uint256(IMainnetPriceFeed.PriceSource.primary),
            "direct caller must not latch the terminal source state"
        );
        assertFalse(bo.isOracleFailureShutdown(), "a direct caller cannot shut the branch down");

        // The registered proxy still observes the failure and performs the shutdown.
        (, bool proxyFail) = proxy.fetchPrice();
        assertTrue(proxyFail, "proxy still observes the shared JPY failure");
        assertTrue(bo.isOracleFailureShutdown(), "proxy performs the temporary shutdown after the direct call");

        // Idempotent while the oracle remains unhealthy: the provider keeps re-reporting the
        // current episode's expiry, so the branch stays shut down on repeated fetches.
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 1 hours);
            stEthUsd.setPrice(3300e8);
            stEthUsd.setUpdatedAt(block.timestamp);
            (, bool againFail) = proxy.fetchPrice();
            assertTrue(againFail, "failure signal must not be consumable");
            assertTrue(bo.isOracleFailureShutdown());
        }
    }

    /// Control: identical scenario, but the expiry call goes through the proxy (intended flow).
    function test_proxyCallStillShutsDownTheBranch() public {
        proxy.fetchPrice();
        vm.warp(block.timestamp + 73 hours);
        stEthUsd.setUpdatedAt(block.timestamp);
        proxy.fetchPrice();

        uint256 freezeStartedAt = jpyRateProvider.jpyFrozenSince();
        vm.warp(freezeStartedAt + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        stEthUsd.setPrice(3300e8);
        stEthUsd.setUpdatedAt(block.timestamp);

        (, bool fail) = proxy.fetchPrice();
        assertTrue(fail);
        assertTrue(bo.isOracleFailureShutdown(), "control: proxy performs the temporary shutdown");
    }

    function test_expiredSharedProviderRejectsNewActiveFeedDeployments() public {
        _expireSharedProviderWithoutBranchShutdown();

        ChainlinkOracleMock usdcUsd = new ChainlinkOracleMock();
        usdcUsd.setDecimals(8);
        usdcUsd.setPrice(1e8);
        usdcUsd.setUpdatedAt(block.timestamp);

        vm.expectRevert(DFPriceFeedBase.InvalidInitialPrice.selector);
        new DFUSDCPriceFeed(
            address(usdcUsd), STETH_STALENESS, address(jpyRateProvider), address(backingVault), address(bo)
        );

        vm.expectRevert(DFWstETHPriceFeed.InvalidInitialPrice.selector);
        new DFWstETHPriceFeed(
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
    }

    function test_activeFeedDeploymentRecoversAfterFreshJpyRound() public {
        _expireSharedProviderWithoutBranchShutdown();

        jpyUsd.setPrice(700_000);
        jpyUsd.setUpdatedAt(block.timestamp);
        stEthUsd.setUpdatedAt(block.timestamp);
        ethUsd.setUpdatedAt(block.timestamp);
        stEthEth.setUpdatedAt(block.timestamp);

        DFWstETHPriceFeed recoveredFeed = new DFWstETHPriceFeed(
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

        assertGt(recoveredFeed.lastGoodPrice(), 0, "fresh JPY round seeds a nonzero price");
        assertEq(uint256(recoveredFeed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary));
        assertFalse(jpyRateProvider.jpyFreezeExpired(), "fresh round clears the episode expiry");
    }

    /// A newer valid round starts a new freeze episode even if no caller observed it while fresh.
    function test_newerStaleRoundDoesNotInheritThePreviousFreezeOnset() public {
        proxy.fetchPrice();

        // Episode 1: JPY oracle stalls for ~73h. Someone reads -> jpyFrozenSince is set.
        vm.warp(block.timestamp + 73 hours);
        stEthUsd.setUpdatedAt(block.timestamp);
        proxy.fetchPrice();
        uint256 onset1 = jpyRateProvider.jpyFrozenSince();
        assertGt(onset1, 0);
        assertFalse(jpyRateProvider.jpyFreezeExpired());

        // Oracle fully RECOVERS and publishes normally for 10 days, but nobody happens to call
        // fetchJpyUsdRate during that window (quiet branch / branch not read).
        vm.warp(block.timestamp + 10 days);
        jpyUsd.setRoundData(2, 2);
        jpyUsd.setUpdatedAt(block.timestamp); // healthy round published now
        uint256 recoveredRoundAt = block.timestamp;
        stEthUsd.setUpdatedAt(block.timestamp);

        // Now the JPY oracle goes stale again -- by only 1 second past the threshold.
        vm.warp(block.timestamp + JPY_STALENESS + 1);
        stEthUsd.setUpdatedAt(block.timestamp);

        (, bool fail) = proxy.fetchPrice();

        uint256 onset2 = recoveredRoundAt + JPY_STALENESS;
        assertFalse(jpyRateProvider.jpyFreezeExpired(), "new episode must receive its own grace window");
        assertEq(jpyRateProvider.jpyFrozenSince(), onset2, "new episode anchors to the newer round");
        assertGt(onset2, onset1, "old episode onset must not be inherited");
        assertFalse(fail);
        assertFalse(bo.isOracleFailureShutdown(), "one second of new staleness must not shut down the branch");

        vm.warp(onset2 + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        stEthUsd.setUpdatedAt(block.timestamp);
        (, bool expiredFailure) = proxy.fetchPrice();

        assertTrue(expiredFailure, "new episode still expires after the full grace window");
        assertTrue(jpyRateProvider.jpyFreezeExpired());
        assertTrue(bo.isOracleFailureShutdown());
    }

    function _expireSharedProviderWithoutBranchShutdown() internal {
        proxy.fetchPrice();

        vm.warp(block.timestamp + JPY_STALENESS + 1);
        stEthUsd.setUpdatedAt(block.timestamp);
        proxy.fetchPrice();

        vm.warp(jpyRateProvider.jpyFrozenSince() + jpyRateProvider.MAX_JPY_FREEZE_DURATION());
        stEthUsd.setUpdatedAt(block.timestamp);

        vm.prank(ATTACKER);
        (, bool failure) = feed.fetchPrice();
        assertTrue(failure, "direct source call observes the expired provider");
        assertTrue(jpyRateProvider.jpyFreezeExpired(), "provider episode is expired");
        assertFalse(bo.isOracleFailureShutdown(), "unregistered source cannot shut the branch down");
    }
}
