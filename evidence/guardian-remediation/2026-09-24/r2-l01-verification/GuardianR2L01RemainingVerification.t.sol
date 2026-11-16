// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Guardian remediation review L-01, remaining verification matrix:
//  - attack after owner recovery, on all three price paths
//  - measured Strategy loss with a fresh valuation cache (a starved probe must not
//    resurrect the pre-loss cached value)
//  - urgent redemption price path
// Wiring: real CollateralVault + ERC4626Strategy + DFUSDCPriceFeed + JpyUsdRateProvider +
// PriceFeedProxy. BorrowerOperations is a stub with the real caller semantics: only the
// registered price feed (the proxy) may shut down or resume.
// The file compiles against both the pre-fix and the fixed source so the same matrix can be
// run on each.

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    IERC20MetadataUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {DToken} from "src/DToken.sol";
import {CollateralVault} from "src/CollateralVault.sol";
import {ERC4626Strategy} from "src/Strategies/ERC4626Strategy.sol";
import {IDToken} from "src/Interfaces/IDToken.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {IPriceFeed} from "src/Interfaces/IPriceFeed.sol";
import {DFUSDCPriceFeed} from "src/PriceFeeds/DFUSDCPriceFeed.sol";
import {JpyUsdRateProvider} from "src/PriceFeeds/JpyUsdRateProvider.sol";
import {PriceFeedProxy} from "src/PriceFeeds/PriceFeedProxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";
import {ChainlinkOracleMock} from "test/TestContracts/ChainlinkOracleMock.sol";

/// @dev ERC-4626 venue with a deterministic valuation cost and an injectable loss.
contract LossyGasHeavyVault is ERC4626 {
    uint256 public burnGas = 450_000; // inside the 500k probe budget of the fix

    constructor(IERC20 asset_) ERC20("Lossy Heavy Vault", "lhv") ERC4626(asset_) {}

    bool public broken;

    function setBurnGas(uint256 g) external {
        burnGas = g;
    }

    function setBroken(bool b) external {
        broken = b;
    }

    /// @dev Realise a loss: send assets away so share value drops.
    function loseAssets(uint256 amount, address sink) external {
        IERC20(asset()).transfer(sink, amount);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        require(!broken, "venue outage");
        uint256 start = gasleft();
        uint256 sink;
        while (start - gasleft() < burnGas) sink += 1;
        return super.convertToAssets(shares) + (sink == 0 ? 1 : 0);
    }
}

/// @dev BorrowerOperations stub with real caller semantics.
contract StrictBO {
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    error CallerNotPriceFeed();

    function setRegisteredPriceFeed(address p) external {
        registeredPriceFeed = p;
    }

    function shutdownFromOracleFailure() external {
        if (msg.sender != registeredPriceFeed) revert CallerNotPriceFeed();
        isOracleFailureShutdown = true;
    }

    function resumeFromOracleFailure() external {
        if (msg.sender != registeredPriceFeed) revert CallerNotPriceFeed();
        isOracleFailureShutdown = false;
    }
}

contract GuardianR2L01RemainingVerificationTest is Test {
    MockERC20 internal underlying;
    LossyGasHeavyVault internal venue;
    CollateralVault internal vault;
    ERC4626Strategy internal strategy;
    ChainlinkOracleMock internal collUsd;
    ChainlinkOracleMock internal jpyUsd;
    StrictBO internal bo;
    DFUSDCPriceFeed internal feed;
    PriceFeedProxy internal proxy;
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");
    address internal lossSink = makeAddr("lossSink");

    function setUp() public {
        vm.warp(1_700_000_000);
        underlying = new MockERC20("Mock USDC", "mUSDC", 18);
        venue = new LossyGasHeavyVault(IERC20(address(underlying)));

        DToken dTokenImpl = new DToken();
        CollateralVault vaultImpl = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        DToken dToken = DToken(
            address(
                new ERC1967Proxy(
                    address(dTokenImpl),
                    abi.encodeWithSelector(DToken.initialize.selector, predictedVault, address(this))
                )
            )
        );
        dToken.setAllowedUnderlying(address(underlying), true);
        vault = CollateralVault(
            address(
                new ERC1967Proxy(
                    address(vaultImpl),
                    abi.encodeWithSelector(
                        CollateralVault.initialize.selector,
                        IERC20(address(underlying)),
                        IDToken(address(dToken)),
                        makeAddr("treasury"),
                        address(this)
                    )
                )
            )
        );
        dToken.setTokenInfo("dmUSDC", "dmUSDC", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(dToken);

        ERC4626Strategy stratImpl = new ERC4626Strategy();
        strategy = ERC4626Strategy(
            address(
                new ERC1967Proxy(
                    address(stratImpl),
                    abi.encodeWithSelector(
                        ERC4626Strategy.initialize.selector,
                        address(vault),
                        IERC20(address(underlying)),
                        address(this),
                        address(this),
                        IERC4626(address(venue))
                    )
                )
            )
        );
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 10_000, type(uint256).max);

        underlying.mint(alice, 100e18);
        vm.startPrank(alice);
        underlying.approve(address(vault), type(uint256).max);
        vault.deposit(100e18);
        vm.stopPrank();
        vault.setBufferConfig(0, 0);
        vault.allocate();
        assertEq(underlying.balanceOf(address(vault)), 0, "raw assets do not cover liabilities");

        collUsd = new ChainlinkOracleMock();
        collUsd.setDecimals(8);
        collUsd.setPrice(1e8);
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(666_700);
        jpyUsd.setUpdatedAt(block.timestamp);
        JpyUsdRateProvider jpyProvider = new JpyUsdRateProvider(address(jpyUsd), 72 hours);
        bo = new StrictBO();
        feed = new DFUSDCPriceFeed(address(collUsd), 24 hours, address(jpyProvider), address(vault), address(bo));
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    // ------------------------------------------------------------------ helpers

    function _refreshOracles() internal {
        collUsd.setUpdatedAt(block.timestamp);
        jpyUsd.setUpdatedAt(block.timestamp);
    }

    function _expireValuationCache() internal {
        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);
        _refreshOracles();
    }

    /// @dev Sweep caller gas on one price path. Every attempt must either revert (no state)
    ///      or return a non-failure price no higher than `maxPrice`; no attempt may leave the
    ///      branch paused.
    function _sweep(bytes memory call, uint256 hi, uint256 lo, uint256 step, uint256 maxPrice)
        internal
        returns (uint256 healthy, uint256 reverted)
    {
        for (uint256 g = hi; g > lo; g -= step) {
            uint256 snap = vm.snapshotState();
            vm.prank(attacker);
            (bool ok, bytes memory ret) = address(proxy).call{gas: g}(call);
            if (ok) {
                (uint256 price, bool failure) = abi.decode(ret, (uint256, bool));
                assertFalse(failure, "healthy branch reported oracle failure");
                assertLe(price, maxPrice, "starved probe produced a price above the measured value");
                healthy++;
            } else {
                reverted++;
            }
            assertFalse(bo.isOracleFailureShutdown(), "caller-chosen gas latched an oracle-failure pause");
            vm.revertToState(snap);
        }
    }

    function _sweepAllPaths(uint256 maxPrice) internal {
        bytes[3] memory calls = [
            abi.encodeCall(IPriceFeed.fetchPrice, ()),
            abi.encodeCall(IPriceFeed.fetchRedemptionPrice, ()),
            abi.encodeCall(IPriceFeed.fetchUrgentRedemptionPrice, ())
        ];
        for (uint256 i; i < 3; ++i) {
            (uint256 healthy, uint256 reverted) = _sweep(calls[i], 1_600_000, 150_000, 2_500, maxPrice);
            assertGt(healthy, 0, "sweep never reached the healthy region");
            assertGt(reverted, 0, "sweep never reached the starved region");
        }
    }

    // ------------------------------------------------------------------ matrix

    /// Attack after owner recovery: a genuine valuation outage pauses the branch, the
    /// venue recovers, the owner resumes through the proxy, and the attacker then sweeps
    /// gas on every price path with a stale cache.
    function test_attackAfterOwnerRecovery_allPricePaths() public {
        venue.setBroken(true); // genuine venue outage: valuation reverts
        _expireValuationCache();
        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure, "genuine outage pauses the branch");
        assertTrue(bo.isOracleFailureShutdown());

        venue.setBroken(false); // venue recovers
        _refreshOracles();
        proxy.resumeFromOracleFailure();
        assertFalse(bo.isOracleFailureShutdown(), "owner recovery");

        (uint256 price,) = proxy.fetchPrice();
        (uint256 ratio, bool available) = vault.backingRatioForPricing();
        assertTrue(available);
        assertEq(ratio, 1e18);
        _expireValuationCache(); // the window the finding needs: stale cache after recovery
        _sweepAllPaths(price);
    }

    /// Measured loss with a *fresh* cache: the cache still holds the pre-loss value. If a
    /// starved probe fell back to that cache the branch would be over-priced; every
    /// successful read must reflect the loss.
    function test_measuredLoss_freshCache_starvedProbeCannotUsePreLossCache() public {
        (uint256 prePrice,) = proxy.fetchPrice();
        venue.loseAssets(30e18, lossSink); // 30% realised loss inside the venue
        (uint256 ratio, bool available) = vault.backingRatioForPricing();
        assertTrue(available);
        assertApproxEqAbs(ratio, 0.7e18, 1e12, "live valuation reflects the loss");
        (uint256 postPrice, bool failure) = proxy.fetchPrice();
        assertFalse(failure);
        assertLt(postPrice, prePrice, "measured loss lowers the price");

        (, uint256 cachedAt, bool initialized) = vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertTrue(initialized && block.timestamp - cachedAt <= vault.strategyValuationMaxAge(), "cache still fresh");
        _sweepAllPaths(postPrice);
    }

    /// Measured loss with a stale cache: same guarantee, and no pause.
    function test_measuredLoss_staleCache_noPauseAndNoOverPricing() public {
        venue.loseAssets(30e18, lossSink);
        _expireValuationCache();
        (uint256 postPrice, bool failure) = proxy.fetchPrice();
        assertFalse(failure);
        _sweepAllPaths(postPrice);
    }

    /// Urgent redemption quote under starvation: never served from a cache, never a pause.
    function test_urgentPath_starvationRevertsOrQuotesLive() public {
        _expireValuationCache();
        (uint256 urgent, bool failure) = proxy.fetchUrgentRedemptionPrice();
        assertFalse(failure);
        (uint256 healthy, uint256 reverted) =
            _sweep(abi.encodeCall(IPriceFeed.fetchUrgentRedemptionPrice, ()), 1_600_000, 150_000, 1_000, urgent);
        assertGt(healthy, 0);
        assertGt(reverted, 0);
    }
}
