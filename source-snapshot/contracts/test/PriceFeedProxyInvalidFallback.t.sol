// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IPriceFeed.sol";
import "src/Interfaces/IPriceFeedProxy.sol";
import "./TestContracts/FreshJpyProvenance.sol";

// =============================================================
//  Follow-up review (Codex) regression specs
//
//  C-1: _handleFailedFetch() and the lastGoodPrice() view must reject an INVALID
//       sentinel (type(uint256).max), not just 0, when reading source.lastGoodPrice().
//       Otherwise the invalid value is cached into _lastGoodPrice and returned, and —
//       since redemption/liquidation ignore the failure bool — it reaches them directly.
//       The proxy must instead fall back to its own (always-valid) cached price.
//
//  C-2: confirmSource() must reject a live-but-failing source that returns
//       (validPrice, oracleFailure == true) WITHOUT reverting — consistent with
//       fetchPrice()'s F-02 handling. A bare price-validity check would let it through.
// =============================================================

contract MockBO {
    bool public hasBeenShutDown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address p) external {
        registeredPriceFeed = p;
    }

    function shutdownFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        if (hasBeenShutDown) return;
        hasBeenShutDown = true;
    }
}

/// @dev Configurable feed: optional failure flag, optional fetch revert, and an arbitrary
///      lastGoodPrice (so the invalid type(uint256).max sentinel can be injected).
contract CfgFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice;
    uint256 private _price;
    uint256 private _urgentPrice;
    bool private _fail;
    bool private _urgentFail;
    bool private _revertFetch;
    bool private _revertUrgent;

    constructor(uint256 p) {
        _price = p;
        _urgentPrice = p;
        lastGoodPrice = p;
    }

    function fetchPrice() external view returns (uint256, bool) {
        if (_revertFetch) revert("down");
        return (_price, _fail);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        if (_revertFetch) revert("down");
        return (_price, _fail);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_revertUrgent) revert("urgent down");
        return (_urgentPrice, _urgentFail);
    }

    function setPrice(uint256 p) external {
        _price = p;
        _urgentPrice = p;
    }

    function setFail(bool f) external {
        _fail = f;
        _urgentFail = f;
    }

    function setRevertFetch(bool r) external {
        _revertFetch = r;
    }

    function setUrgentPrice(uint256 p) external {
        _urgentPrice = p;
    }

    function setUrgentFail(bool f) external {
        _urgentFail = f;
    }

    function setRevertUrgent(bool r) external {
        _revertUrgent = r;
    }

    function setLastGoodPrice(uint256 v) external {
        lastGoodPrice = v;
    }
}

contract PriceFeedProxyInvalidFallbackTest is Test {
    MockBO bo;
    CfgFeed feedA;

    function setUp() public {
        bo = new MockBO();
        feedA = new CfgFeed(100_000e18);
    }

    function _deploy(address src) internal returns (PriceFeedProxy p) {
        p = new PriceFeedProxy(src, address(this), address(bo));
        bo.setRegisteredPriceFeed(address(p));
    }

    // --- C-1: invalid (max) source.lastGoodPrice() must NOT be served ---

    function test_C1_handleFailedFetch_rejectsMaxSourceLastGood() public {
        PriceFeedProxy proxy = _deploy(address(feedA));
        proxy.fetchPrice(); // warm proxy cache = 100k

        // Source now reverts on fetch, and its lastGoodPrice is the invalid max sentinel.
        feedA.setRevertFetch(true);
        feedA.setLastGoodPrice(type(uint256).max);

        (uint256 price, bool failure) = proxy.fetchPrice();
        assertTrue(failure, "must signal failure");
        assertEq(price, 100_000e18, "must fall back to proxy cache, not serve max");
        assertTrue(bo.hasBeenShutDown(), "branch must be shut down");
    }

    function test_C1_lastGoodPriceView_rejectsMaxSourceLastGood() public {
        PriceFeedProxy proxy = _deploy(address(feedA));
        proxy.fetchPrice(); // warm = 100k

        feedA.setLastGoodPrice(type(uint256).max);
        assertEq(proxy.lastGoodPrice(), 100_000e18, "view must not return max");
    }

    // --- C-2: confirmSource must reject a (validPrice, oracleFailure == true) source ---

    function test_C2_confirmSource_rejectsFailureFlaggedSource() public {
        PriceFeedProxy proxy = _deploy(address(feedA));

        CfgFeed liveButFailing = new CfgFeed(200_000e18);
        liveButFailing.setFail(true); // returns (200k, true) WITHOUT reverting

        proxy.proposeSource(address(liveButFailing));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        proxy.confirmSource();

        // Source must stay the original, and the cache must be untouched.
        assertEq(proxy.source(), address(feedA), "source must not switch");
    }

    // --- C-2 (constructor): the constructor must ALSO reject a (validPrice, oracleFailure == true)
    //     source — symmetric with confirmSource. Previously the constructor's smoke-test discarded
    //     the fetch return values, so a failure-flagged initial source deployed fine and shut the
    //     branch down (or, under a deploy miswire, stayed live on a frozen price) on its first
    //     fetch (dead-on-arrival). ---

    function test_C2_constructor_rejectsFailureFlaggedSource() public {
        CfgFeed liveButFailing = new CfgFeed(100_000e18);
        liveButFailing.setFail(true); // (100k, true) WITHOUT reverting; lastGoodPrice 100k warms F-01

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(liveButFailing), address(this), address(bo));
    }

    function test_C2_constructor_rejectsInvalidPriceOnLiveFetch() public {
        // lastGoodPrice stays valid (warms F-01), but the live fetch returns an invalid sentinel.
        CfgFeed badLiveFetch = new CfgFeed(100_000e18);
        badLiveFetch.setPrice(0); // fetchPrice() / fetchRedemptionPrice() now return (0, false)

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(badLiveFetch), address(this), address(bo));
    }

    function test_F4_constructor_rejectsRevertingUrgentPath() public {
        CfgFeed brokenUrgent = new CfgFeed(100_000e18);
        brokenUrgent.setRevertUrgent(true);

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(brokenUrgent), address(this), address(bo));
    }

    function test_F4_constructor_rejectsZeroUrgentPrice() public {
        CfgFeed brokenUrgent = new CfgFeed(100_000e18);
        brokenUrgent.setUrgentPrice(0);

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(brokenUrgent), address(this), address(bo));
    }

    function test_F4_constructor_rejectsMaxUrgentPrice() public {
        CfgFeed brokenUrgent = new CfgFeed(100_000e18);
        brokenUrgent.setUrgentPrice(type(uint256).max);

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(brokenUrgent), address(this), address(bo));
    }

    function test_F4_constructor_rejectsFailureFlaggedUrgentPath() public {
        CfgFeed brokenUrgent = new CfgFeed(100_000e18);
        brokenUrgent.setUrgentFail(true);

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(brokenUrgent), address(this), address(bo));
    }

    function test_C2_constructor_stillToleratesRevertingCachedPaths() public {
        // Temporarily reverting normal/redemption paths remain constructible because their
        // runtime paths have proxy caches. The urgent path stays healthy and cache-free.
        CfgFeed reverting = new CfgFeed(100_000e18); // lastGoodPrice = 100k warms F-01
        reverting.setRevertFetch(true);

        PriceFeedProxy proxy = new PriceFeedProxy(address(reverting), address(this), address(bo));
        assertEq(proxy.source(), address(reverting), "cache-backed fetch reverts remain constructible");
        assertEq(proxy.lastGoodPrice(), 100_000e18, "warmed from the lastGoodPrice() view");
    }
}
