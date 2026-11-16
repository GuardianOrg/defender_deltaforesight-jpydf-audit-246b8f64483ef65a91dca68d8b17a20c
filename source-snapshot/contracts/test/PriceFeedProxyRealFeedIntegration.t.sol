// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/PriceFeeds/MainnetPriceFeedBase.sol";
import "./TestContracts/ChainlinkOracleMock.sol";
import "./TestContracts/FreshJpyProvenance.sol";

// =============================================================
//  案件3: 実 PriceFeed を proxy の裏に置く統合テスト（forkless）
//
//  既存の PriceFeedProxy*.t.sol は全て「純 mock feed」だが、本テストは
//  MainnetPriceFeedBase を継承する test-local feed（本物の障害セマンティクス・
//  Chainlink staleness 判定・gas-griefing guard）を mock Chainlink aggregator で
//  forkless に立て、proxy の裏に挿して検証する。production `src` には
//  deploy されない WETHPriceFeed wrapper を残さない。
//
//  特に仕様書 §4.4 / PR §5.2 の中核フローを「実 feed」で再現する:
//    実 feed が障害時に borrowerOperations.shutdownFromOracleFailure() を *直接* 呼ぶ
//      → proxy 経由では msg.sender != registered priceFeed なので revert
//      → proxy がその revert を catch し、自分で shutdown を呼ぶ
//      → source.lastGoodPrice() を返す
//
//  本体（PriceFeedProxy.sol / MainnetPriceFeedBase.sol）は一切変更しない。
//
//  注: 実コア（CollateralRegistry.redeemCollateral の除算経路まで）の
//      フル E2E は、proxy をブランチの priceFeed として deploy 配線する必要があり
//      Phase 4（DeployLiquity2 への `new PriceFeedProxy(...)` 追加）とセットで実施する。
// =============================================================

/// @dev BorrowerOperations スタブ（実セマンティクス: registered priceFeed のみ shutdown 可）。
///      TestMainnetPriceFeed / PriceFeedProxy 双方からは IBorrowerOperations としてキャストされる。
contract MockBO {
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address p) external {
        registeredPriceFeed = p;
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

contract TestMainnetPriceFeed is MainnetPriceFeedBase, FreshJpyProvenance {
    constructor(address _ethUsdOracleAddress, uint256 _ethUsdStalenessThreshold, address _borrowerOperationsAddress)
        MainnetPriceFeedBase(_ethUsdOracleAddress, _ethUsdStalenessThreshold, _borrowerOperationsAddress)
    {
        _fetchPricePrimary();
        assert(priceSource == PriceSource.primary);
    }

    function fetchPrice() public returns (uint256, bool) {
        if (priceSource == PriceSource.primary) return _fetchPricePrimary();

        assert(priceSource == PriceSource.lastGoodPrice);
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        return fetchPrice();
    }

    function fetchUrgentRedemptionPrice() external returns (uint256, bool) {
        return fetchPrice();
    }

    function _fetchPricePrimary() internal returns (uint256, bool) {
        assert(priceSource == PriceSource.primary);
        (uint256 ethUsdPrice, bool ethUsdOracleDown) = _getOracleAnswer(ethUsdOracle);

        if (ethUsdOracleDown) return (_shutDownAndReturnLastGoodPrice(address(ethUsdOracle.aggregator)), true);

        lastGoodPrice = ethUsdPrice;
        return (ethUsdPrice, false);
    }
}

contract PriceFeedProxyRealFeedIntegrationTest is Test {
    uint256 constant STALENESS = 24 hours;
    uint256 constant ETH_USD = 2_000e18; // 18-decimal scaled expected price
    int256 constant ETH_USD_8DEC = 2_000e8; // Chainlink raw (8 decimals)

    PriceFeedProxy proxy;
    TestMainnetPriceFeed realFeed;
    ChainlinkOracleMock ethUsdOracle;
    MockBO bo;

    function setUp() public {
        // 実時刻に近づけておく（staleness 判定の余裕確保）
        vm.warp(1_700_000_000);

        bo = new MockBO();

        ethUsdOracle = new ChainlinkOracleMock();
        ethUsdOracle.setDecimals(8); // MainnetPriceFeedBase の constructor が decimals==8 を assert
        ethUsdOracle.setPrice(ETH_USD_8DEC);
        ethUsdOracle.setUpdatedAt(block.timestamp);

        // 実 MainnetPriceFeedBase セマンティクスの test-local feed を deploy
        // （constructor 内で _fetchPricePrimary を実行し primary 状態を確認）
        realFeed = new TestMainnetPriceFeed(address(ethUsdOracle), STALENESS, address(bo));

        // proxy で実 feed をラップし、proxy を registered priceFeed にする
        proxy = new PriceFeedProxy(address(realFeed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    // --- 正常系: 実 feed への委譲が proxy 越しで成立する ---

    function test_realFeed_normalFetch_delegatesThroughProxy() public {
        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, ETH_USD, "proxy should return real feed's 18-dec price");
        assertFalse(failure, "no oracle failure expected");
        assertFalse(bo.isOracleFailureShutdown(), "branch must stay live");
    }

    function test_realFeed_fetchRedemptionPrice_delegatesThroughProxy() public {
        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(price, ETH_USD);
        assertFalse(failure);
    }

    function test_realFeed_lastGoodPrice_readsThroughProxy() public {
        proxy.fetchPrice();
        assertEq(proxy.lastGoodPrice(), ETH_USD);
    }

    // --- 障害系（仕様 §4.4 の中核フローを実 feed で再現）---

    /// @notice Chainlink が stale になると、実 feed は shutdown を直接呼んで revert し、
    ///         proxy がそれを catch して自分で shutdown を呼び、lastGoodPrice を返す。
    function test_realFeed_staleOracle_proxyCatchesAndShutsDown() public {
        // staleness 閾値を超えて時間を進める（updatedAt は据え置き）
        vm.warp(block.timestamp + STALENESS + 1);

        (uint256 price, bool failure) = proxy.fetchPrice();

        // 実 feed の lastGoodPrice（構築時に確定した 2000e18）が proxy 経由で返る
        assertEq(price, ETH_USD, "should fall back to real feed's lastGoodPrice");
        assertTrue(failure, "proxy must signal oracleFailure=true");
        // proxy が registered priceFeed として shutdown を発火できた = 信頼境界が正しい
        assertTrue(bo.isOracleFailureShutdown(), "proxy must temporarily shut the branch down on real-feed failure");
    }

    /// @notice Chainlink answer が 0（無効価格）でも同じフォールバック/ shutdown 経路を通る。
    function test_realFeed_zeroAnswer_proxyCatchesAndShutsDown() public {
        ethUsdOracle.setPrice(0);
        ethUsdOracle.setUpdatedAt(block.timestamp);

        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();

        assertEq(price, ETH_USD);
        assertTrue(failure);
        assertTrue(bo.isOracleFailureShutdown());
    }

    /// @notice 障害後も繰り返し呼べて lastGoodPrice を返し続ける（恒久 DoS なし）。
    function test_realFeed_repeatedCallsAfterFailure_returnLastGoodPrice() public {
        vm.warp(block.timestamp + STALENESS + 1);

        (uint256 p1,) = proxy.fetchPrice();
        assertTrue(bo.isOracleFailureShutdown());

        (uint256 p2, bool f2) = proxy.fetchPrice();
        assertEq(p1, p2);
        assertTrue(f2);
    }

    // --- source 差替（timelock + 明示 emergency）を実 feed 間で行う ---

    /// @notice stale な実 feed から1%超で復旧する場合も、明示 emergency と12h timelock で差替できる。
    function test_realFeed_sourceSwapViaEmergency_betweenRealFeeds() public {
        // 新しい価格の実 feed を用意
        ChainlinkOracleMock newOracle = new ChainlinkOracleMock();
        newOracle.setDecimals(8);
        newOracle.setPrice(2_500e8);
        newOracle.setUpdatedAt(block.timestamp);
        TestMainnetPriceFeed newFeed = new TestMainnetPriceFeed(address(newOracle), STALENESS, address(bo));

        proxy.proposeSource(address(newFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        // confirmSource now smoke-tests the new source, so the new feed must be LIVE (fresh
        // oracle) at the moment of the switch. Refresh updatedAt before confirming — in
        // production a real Chainlink feed updates every heartbeat, so it is fresh at confirm.
        newOracle.setUpdatedAt(block.timestamp);
        proxy.confirmSourceEmergency();

        assertEq(proxy.source(), address(newFeed));

        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 2_500e18, "new real feed price should flow through proxy");
        assertFalse(failure);
    }
}
