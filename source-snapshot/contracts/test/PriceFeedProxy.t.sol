// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/Interfaces/IPriceFeed.sol";
import "src/Interfaces/IPriceFeedProxy.sol";
import "src/Interfaces/IBorrowerOperations.sol";
import "./TestContracts/FreshJpyProvenance.sol";

// =============================================================
//  Mocks
// =============================================================

contract MockPriceFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice;
    uint256 private _price;
    bool private _oracleFailure;

    constructor(uint256 price_) {
        _price = price_;
        lastGoodPrice = price_;
    }

    function fetchPrice() external returns (uint256, bool) {
        lastGoodPrice = _price;
        return (_price, _oracleFailure);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        lastGoodPrice = _price;
        return (_price, _oracleFailure);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (_price, _oracleFailure);
    }

    function setPrice(uint256 price_) external {
        _price = price_;
    }

    function setOracleFailure(bool fail_) external {
        _oracleFailure = fail_;
    }
}

contract MockBorrowerOperations {
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address _priceFeed) external {
        registeredPriceFeed = _priceFeed;
    }

    function shutdownFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        if (isOracleFailureShutdown) return;
        isOracleFailureShutdown = true;
    }

    function resumeFromOracleFailure() external {
        require(msg.sender == registeredPriceFeed, "CallerNotPriceFeed");
        require(isOracleFailureShutdown, "NotOracleFailureShutdown");
        isOracleFailureShutdown = false;
    }
}

/// @dev Simulates real oracle failure: calls borrowerOperations.shutdownFromOracleFailure()
///      directly on stale oracle, which reverts when behind the proxy.
contract RealisticPriceFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice;
    uint256 private _price;
    bool private _oracleStale;
    IBorrowerOperations public borrowerOperations;

    constructor(uint256 price_, address _borrowOps) {
        _price = price_;
        lastGoodPrice = price_;
        borrowerOperations = IBorrowerOperations(_borrowOps);
    }

    function fetchPrice() external returns (uint256, bool) {
        if (_oracleStale) {
            borrowerOperations.shutdownFromOracleFailure();
            return (lastGoodPrice, true);
        }
        lastGoodPrice = _price;
        return (_price, false);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        if (_oracleStale) {
            borrowerOperations.shutdownFromOracleFailure();
            return (lastGoodPrice, true);
        }
        lastGoodPrice = _price;
        return (_price, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_oracleStale) return (lastGoodPrice, true);
        return (_price, false);
    }

    function setOracleStale(bool stale_) external {
        _oracleStale = stale_;
    }

    function setPrice(uint256 price_) external {
        _price = price_;
        lastGoodPrice = price_;
    }
}

/// @dev Completely bricked feed — all calls revert.
contract BrickedPriceFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice;

    constructor(uint256 price_) {
        lastGoodPrice = price_;
    }

    function fetchPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }

    function fetchRedemptionPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }

    function fetchUrgentRedemptionPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }
}

/// @dev Fully bricked feed — even lastGoodPrice reverts, so construction must fail closed.
contract FullyBrickedPriceFeed is IPriceFeed, FreshJpyProvenance {
    function fetchPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }

    function fetchRedemptionPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }

    function fetchUrgentRedemptionPrice() external pure returns (uint256, bool) {
        revert("bricked");
    }

    function lastGoodPrice() external pure returns (uint256) {
        revert("bricked");
    }
}

/// @dev Feed that is valid at first (so it passes confirmSource's smoke-test) but can be fully
///      bricked at runtime — fetchPrice / fetchRedemptionPrice / lastGoodPrice all revert — to
///      exercise the proxy's own cached-price fallback after a post-switch source failure.
contract TogglableBrickFeed is IPriceFeed, FreshJpyProvenance {
    uint256 private _price;
    bool private _bricked;

    constructor(uint256 price_) {
        _price = price_;
    }

    function fetchPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_price, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_price, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_price, false);
    }

    function lastGoodPrice() external view returns (uint256) {
        if (_bricked) revert("bricked");
        return _price;
    }

    function brick() external {
        _bricked = true;
    }
}

/// @dev Valid when selected, then able to consume every unit of gas forwarded by the old-source
///      health probe. Governance must still be able to replace it through the emergency path.
contract TogglableGasBurnFeed is IPriceFeed, FreshJpyProvenance {
    uint256 private immutable _price;
    bool private _burnGas;

    constructor(uint256 price_) {
        _price = price_;
    }

    function fetchPrice() external view returns (uint256, bool) {
        _burnIfEnabled();
        return (_price, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        _burnIfEnabled();
        return (_price, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        _burnIfEnabled();
        return (_price, false);
    }

    function lastGoodPrice() external view returns (uint256) {
        _burnIfEnabled();
        return _price;
    }

    function burnGas() external {
        _burnGas = true;
    }

    function _burnIfEnabled() private view {
        if (_burnGas) {
            assembly {
                invalid()
            }
        }
    }
}

/// @dev Source with intentionally distinct normal and redemption prices. It is healthy during
///      switching and can later fully brick, forcing the proxy to use its own per-path caches.
contract DivergentTogglableBrickFeed is IPriceFeed, FreshJpyProvenance {
    uint256 private _normalPrice;
    uint256 private _redemptionPrice;
    uint256 private _urgentRedemptionPrice;
    bool private _bricked;

    constructor(uint256 normalPrice_, uint256 redemptionPrice_) {
        _normalPrice = normalPrice_;
        _redemptionPrice = redemptionPrice_;
        _urgentRedemptionPrice = redemptionPrice_;
    }

    function fetchPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_normalPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_redemptionPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_bricked) revert("bricked");
        return (_urgentRedemptionPrice, false);
    }

    function setUrgentRedemptionPrice(uint256 price_) external {
        _urgentRedemptionPrice = price_;
    }

    function lastGoodPrice() external view returns (uint256) {
        if (_bricked) revert("bricked");
        return _normalPrice;
    }

    function brick() external {
        _bricked = true;
    }
}

/// @dev Source with distinct normal/redemption prices where live fetches can fail while
///      lastGoodPrice() continues to return the normal-path price. This catches accidental
///      redemption fallback to source.lastGoodPrice().
contract DivergentFetchBrickFeed is IPriceFeed, FreshJpyProvenance {
    uint256 private _normalPrice;
    uint256 private _redemptionPrice;
    bool private _fetchBricked;

    constructor(uint256 normalPrice_, uint256 redemptionPrice_) {
        _normalPrice = normalPrice_;
        _redemptionPrice = redemptionPrice_;
    }

    function fetchPrice() external view returns (uint256, bool) {
        if (_fetchBricked) revert("fetch bricked");
        return (_normalPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        if (_fetchBricked) revert("fetch bricked");
        return (_redemptionPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_fetchBricked) revert("fetch bricked");
        return (_redemptionPrice, false);
    }

    function lastGoodPrice() external view returns (uint256) {
        return _normalPrice;
    }

    function brickFetches() external {
        _fetchBricked = true;
    }
}

contract BrokenUrgentFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_500e18;

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchUrgentRedemptionPrice() external pure returns (uint256, bool) {
        revert("urgent broken");
    }
}

// =============================================================
//  Tests — Constructor, delegation, price validation, timelock, ownership
// =============================================================

contract PriceFeedProxyTest is Test {
    // Local event declarations for vm.expectEmit. Ownable2Step's events are
    // not re-declared in IPriceFeedProxy, so the test declares matching
    // signatures here.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    PriceFeedProxy proxy;
    MockPriceFeed feedA;
    MockPriceFeed feedB;
    MockBorrowerOperations mockBO;
    address owner;
    address nonOwner;

    function setUp() public {
        owner = address(this);
        nonOwner = makeAddr("nonOwner");

        mockBO = new MockBorrowerOperations();
        feedA = new MockPriceFeed(100_000e18);
        feedB = new MockPriceFeed(100_500e18);

        proxy = new PriceFeedProxy(address(feedA), owner, address(mockBO));
        mockBO.setRegisteredPriceFeed(address(proxy));
    }

    function _proposeAndConfirm(address _newSource) internal {
        proxy.proposeSource(_newSource);
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        proxy.confirmSource();
    }

    // --- Constructor ---

    function testConstructorSetsSource() public view {
        assertEq(proxy.source(), address(feedA));
    }

    function testConstructorSetsOwner() public view {
        assertEq(proxy.owner(), owner);
    }

    function testConstructorSetsBorrowerOperations() public view {
        assertEq(address(proxy.borrowerOperations()), address(mockBO));
    }

    function testConstructorRevertsOnZeroSource() public {
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(0), owner, address(mockBO));
    }

    function testConstructorRevertsOnZeroInitialPrice() public {
        MockPriceFeed zeroFeed = new MockPriceFeed(0);
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(zeroFeed), owner, address(mockBO));
    }

    function testConstructorRevertsWhenInitialLastGoodPriceReverts() public {
        FullyBrickedPriceFeed brickedFeed = new FullyBrickedPriceFeed();
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(brickedFeed), owner, address(mockBO));
    }

    function testConstructorRevertsOnZeroOwner() public {
        vm.expectRevert(IPriceFeedProxy.ZeroOwnerAddress.selector);
        new PriceFeedProxy(address(feedA), address(0), address(mockBO));
    }

    function testConstructorRevertsOnZeroBorrowerOperations() public {
        vm.expectRevert(IPriceFeedProxy.InvalidAddress.selector);
        new PriceFeedProxy(address(feedA), owner, address(0));
    }

    function testConstructorEmitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit IPriceFeedProxy.SourceUpdated(address(0), address(feedA));
        new PriceFeedProxy(address(feedA), owner, address(mockBO));
    }

    function testTimelockDelay() public view {
        assertEq(proxy.TIMELOCK_DELAY(), 12 hours);
    }

    // --- fetchPrice delegation ---

    function testFetchPriceDelegatesToSource() public {
        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 100_000e18);
        assertFalse(failure);
    }

    function testFetchPriceReturnsOracleFailure() public {
        feedA.setOracleFailure(true);
        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchRedemptionPriceReturnsOracleFailure() public {
        feedA.setOracleFailure(true);
        (, bool failure) = proxy.fetchRedemptionPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchPriceReflectsPriceChanges() public {
        feedA.setPrice(200_000e18);
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 200_000e18);
    }

    function testFetchRedemptionPriceDelegatesToSource() public {
        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(price, 100_000e18);
        assertFalse(failure);
    }

    function testFetchUrgentRedemptionPriceDelegatesToSource() public {
        (uint256 price, bool failure) = proxy.fetchUrgentRedemptionPrice();
        assertEq(price, 100_000e18);
        assertFalse(failure);
    }

    function testFetchUrgentRedemptionPriceRejectsOracleFailure() public {
        feedA.setOracleFailure(true);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.UrgentRedemptionPriceUnavailable.selector, address(feedA))
        );
        proxy.fetchUrgentRedemptionPrice();
        assertFalse(mockBO.isOracleFailureShutdown());
    }

    // --- Price validation (zero and max) ---

    function testFetchPriceRejectsZero() public {
        proxy.fetchPrice(); // establish lastGoodPrice
        feedA.setPrice(0);
        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchPriceRejectsMaxUint() public {
        proxy.fetchPrice();
        feedA.setPrice(type(uint256).max);
        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchRedemptionPriceRejectsZero() public {
        proxy.fetchRedemptionPrice();
        feedA.setPrice(0);
        (, bool failure) = proxy.fetchRedemptionPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchRedemptionPriceRejectsMaxUint() public {
        proxy.fetchRedemptionPrice();
        feedA.setPrice(type(uint256).max);
        (, bool failure) = proxy.fetchRedemptionPrice();
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchUrgentRedemptionPriceRejectsZero() public {
        feedA.setPrice(0);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.UrgentRedemptionPriceUnavailable.selector, address(feedA))
        );
        proxy.fetchUrgentRedemptionPrice();
    }

    function testFetchUrgentRedemptionPriceRejectsMaxUint() public {
        feedA.setPrice(type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.UrgentRedemptionPriceUnavailable.selector, address(feedA))
        );
        proxy.fetchUrgentRedemptionPrice();
    }

    // --- lastGoodPrice ---

    function testLastGoodPriceDelegatesToSource() public view {
        assertEq(proxy.lastGoodPrice(), 100_000e18);
    }

    function testLastGoodPriceUpdatesAfterFetch() public {
        feedA.setPrice(250_000e18);
        proxy.fetchPrice();
        assertEq(proxy.lastGoodPrice(), 250_000e18);
    }

    // --- C-1 fix: Bricked source fallback ---

    function testFetchPriceFallsBackToCachedPriceWhenSourceFullyBricked() public {
        // Establish a cached price first
        proxy.fetchPrice();
        assertEq(proxy.lastGoodPrice(), 100_000e18);

        // Switch to a healthy feed (passes confirmSource's smoke-test), then fully brick it at
        // runtime. confirmSource re-initialises the proxy cache to the new feed's price, proving
        // the fallback does not serve the old source's stale value.
        TogglableBrickFeed bricked = new TogglableBrickFeed(100_500e18);
        _proposeAndConfirm(address(bricked));
        bricked.brick(); // fetchPrice AND lastGoodPrice now revert

        // fetchPrice should NOT revert — falls back to proxy's own cached price
        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 100_500e18);
        assertTrue(failure);
    }

    function testLastGoodPriceFallsBackWhenSourceBricked() public {
        proxy.fetchPrice(); // cache price

        TogglableBrickFeed bricked = new TogglableBrickFeed(100_500e18);
        _proposeAndConfirm(address(bricked));
        bricked.brick();

        // lastGoodPrice (view) should also not revert — falls back to proxy's cached price
        assertEq(proxy.lastGoodPrice(), 100_500e18);
    }

    function testBrickedSourceFallsBackForNormalPathsButRejectsUrgentAfterSwitch() public {
        DivergentTogglableBrickFeed divergent = new DivergentTogglableBrickFeed(99_500e18, 100_500e18);
        _proposeAndConfirm(address(divergent));
        divergent.brick(); // fetchPrice, fetchRedemptionPrice, and lastGoodPrice now revert

        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 99_500e18);
        assertTrue(failure);

        (uint256 redemptionPrice, bool redemptionFailure) = proxy.fetchRedemptionPrice();
        assertEq(redemptionPrice, 100_500e18);
        assertTrue(redemptionFailure);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.UrgentRedemptionPriceUnavailable.selector, address(divergent))
        );
        proxy.fetchUrgentRedemptionPrice();
    }

    function testRedemptionFallbackDoesNotUseNormalSourceLastGoodPrice() public {
        DivergentFetchBrickFeed divergent = new DivergentFetchBrickFeed(99_500e18, 100_500e18);
        _proposeAndConfirm(address(divergent));
        divergent.brickFetches(); // fetches revert, but lastGoodPrice still returns normal price

        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 99_500e18);
        assertTrue(failure);

        (uint256 redemptionPrice, bool redemptionFailure) = proxy.fetchRedemptionPrice();
        assertEq(redemptionPrice, 100_500e18);
        assertTrue(redemptionFailure);
    }

    // =========================================================
    //  Timelocked source switching
    // =========================================================

    function testProposeSourceSetsState() public {
        proxy.proposeSource(address(feedB));
        assertEq(proxy.proposedSource(), address(feedB));
        assertEq(proxy.sourceProposedAt(), block.timestamp);
    }

    function testProposeSourceEmitsEvent() public {
        uint256 expectedExec = block.timestamp + proxy.TIMELOCK_DELAY();
        vm.expectEmit(true, false, false, true);
        emit IPriceFeedProxy.SourceProposed(address(feedB), expectedExec);
        proxy.proposeSource(address(feedB));
    }

    function testProposeSourceRevertsForNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.proposeSource(address(feedB));
    }

    function testProposeSourceRevertsOnZeroAddress() public {
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        proxy.proposeSource(address(0));
    }

    function testProposeSourceRevertsOnSameSource() public {
        vm.expectRevert(IPriceFeedProxy.SameSource.selector);
        proxy.proposeSource(address(feedA));
    }

    function testProposeSourceDoesNotChangeActiveSource() public {
        proxy.proposeSource(address(feedB));
        assertEq(proxy.source(), address(feedA));
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 100_000e18);
    }

    // M-4 fix: overwriting proposal emits cancellation
    function testOverwriteProposalEmitsCancellation() public {
        MockPriceFeed feedC = new MockPriceFeed(200_000e18);
        proxy.proposeSource(address(feedB));

        vm.expectEmit(true, false, false, false);
        emit IPriceFeedProxy.SourceProposalCancelled(address(feedB));
        proxy.proposeSource(address(feedC));

        assertEq(proxy.proposedSource(), address(feedC));
    }

    // --- confirmSource ---

    function testConfirmSourceAfterTimelock() public {
        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        proxy.confirmSource();

        assertEq(proxy.source(), address(feedB));
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 100_500e18);
    }

    function testConfirmSourceClearsProposal() public {
        _proposeAndConfirm(address(feedB));
        assertEq(proxy.proposedSource(), address(0));
        assertEq(proxy.sourceProposedAt(), 0);
    }

    function testConfirmSourceEmitsEvent() public {
        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectEmit(true, true, false, false);
        emit IPriceFeedProxy.SourceUpdated(address(feedA), address(feedB));
        proxy.confirmSource();
    }

    function testConfirmSourceRevertsBeforeTimelock() public {
        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY() - 1);
        vm.expectRevert(IPriceFeedProxy.TimelockNotElapsed.selector);
        proxy.confirmSource();
    }

    function testConfirmSourceRevertsWithNoProposal() public {
        vm.expectRevert(IPriceFeedProxy.NoProposalPending.selector);
        proxy.confirmSource();
    }

    function testConfirmSourceRevertsForNonOwner() public {
        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.confirmSource();
    }

    function testConfirmSourceRevertsWhenNewSourceFetchReverts() public {
        BrickedPriceFeed brickedFeed = new BrickedPriceFeed(100_000e18);
        proxy.proposeSource(address(brickedFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert();
        proxy.confirmSource();

        assertEq(proxy.source(), address(feedA));
    }

    function testConfirmSourceRejectsSourceWithBrokenUrgentPath() public {
        BrokenUrgentFeed broken = new BrokenUrgentFeed();
        proxy.proposeSource(address(broken));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert("urgent broken");
        proxy.confirmSource();
    }

    // --- cancelSourceProposal ---

    function testCancelSourceProposal() public {
        proxy.proposeSource(address(feedB));
        proxy.cancelSourceProposal();

        assertEq(proxy.proposedSource(), address(0));
        assertEq(proxy.sourceProposedAt(), 0);
        assertEq(proxy.source(), address(feedA));
    }

    function testCancelSourceProposalEmitsEvent() public {
        proxy.proposeSource(address(feedB));
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedProxy.SourceProposalCancelled(address(feedB));
        proxy.cancelSourceProposal();
    }

    function testCancelSourceProposalRevertsWithNoProposal() public {
        vm.expectRevert(IPriceFeedProxy.NoProposalPending.selector);
        proxy.cancelSourceProposal();
    }

    function testCancelSourceProposalRevertsForNonOwner() public {
        proxy.proposeSource(address(feedB));
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.cancelSourceProposal();
    }

    // --- Multiple swaps ---

    function testMultipleTimelockSwaps() public {
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 100_000e18);

        _proposeAndConfirm(address(feedB));
        (price,) = proxy.fetchPrice();
        assertEq(price, 100_500e18);

        _proposeAndConfirm(address(feedA));
        (price,) = proxy.fetchPrice();
        assertEq(price, 100_000e18);
    }

    function testConfirmSourceRevertsWhenHealthyOldSourcePriceJumpsTooFar() public {
        MockPriceFeed jumpFeed = new MockPriceFeed(150_000e18);

        proxy.proposeSource(address(jumpFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert();
        proxy.confirmSource();

        assertEq(proxy.source(), address(feedA));
    }

    function testConfirmSourceRevertsWhenOnlyUrgentPriceJumpsTooFar() public {
        DivergentTogglableBrickFeed divergent = new DivergentTogglableBrickFeed(100_500e18, 100_500e18);
        divergent.setUrgentRedemptionPrice(102_000e18);
        proxy.proposeSource(address(divergent));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedProxy.SourcePriceDeviationTooLarge.selector, 100_000e18, 102_000e18, 100)
        );
        proxy.confirmSource();
    }

    function testConfirmSourceRevertsWhenUnhealthyOldSourceCachedPriceJumpsTooFar() public {
        MockPriceFeed jumpFeed = new MockPriceFeed(150_000e18);
        feedA.setOracleFailure(true);

        proxy.proposeSource(address(jumpFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceFeedProxy.SourcePriceDeviationTooLarge.selector,
                100_000e18,
                150_000e18,
                proxy.MAX_SOURCE_SWITCH_DEVIATION_BPS()
            )
        );
        proxy.confirmSource();

        assertEq(proxy.source(), address(feedA));
    }

    function testConfirmSourceUsesSeparateCachedRedemptionPriceWhenOldSourceFails() public {
        DivergentTogglableBrickFeed divergent = new DivergentTogglableBrickFeed(100_000e18, 90_000e18);
        proxy.proposeSource(address(divergent));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        proxy.confirmSourceEmergency();
        divergent.brick();

        DivergentTogglableBrickFeed jumpFeed = new DivergentTogglableBrickFeed(100_500e18, 100_500e18);
        proxy.proposeSource(address(jumpFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceFeedProxy.SourcePriceDeviationTooLarge.selector,
                90_000e18,
                100_500e18,
                proxy.MAX_SOURCE_SWITCH_DEVIATION_BPS()
            )
        );
        proxy.confirmSource();

        assertEq(proxy.source(), address(divergent));
    }

    function testConfirmSourceUsesCachedPricesWithoutImplicitEmergencyBypass() public {
        feedA.setOracleFailure(true);

        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        vm.expectEmit(true, true, false, true);
        emit IPriceFeedProxy.SourceSwitchValidated(
            address(feedA), address(feedB), false, false, 100_000e18, 100_500e18, 100_000e18, 100_500e18
        );
        proxy.confirmSource();

        assertEq(proxy.source(), address(feedB));
    }

    function testConfirmSourceEmergencyBypassesCachedPriceGuardWhenOldSourceFails() public {
        MockPriceFeed jumpFeed = new MockPriceFeed(150_000e18);
        feedA.setOracleFailure(true);

        proxy.proposeSource(address(jumpFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        vm.expectEmit(true, true, false, true);
        emit IPriceFeedProxy.SourceSwitchValidated(
            address(feedA), address(jumpFeed), false, true, 100_000e18, 150_000e18, 100_000e18, 150_000e18
        );
        proxy.confirmSourceEmergency();

        assertEq(proxy.source(), address(jumpFeed));
    }

    function testConfirmSourceEmergencyBypassesPriceJumpGuard() public {
        MockPriceFeed jumpFeed = new MockPriceFeed(150_000e18);

        proxy.proposeSource(address(jumpFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        vm.expectEmit(true, true, false, false);
        emit IPriceFeedProxy.SourceUpdated(address(feedA), address(jumpFeed));
        vm.expectEmit(true, true, false, true);
        emit IPriceFeedProxy.SourceSwitchValidated(
            address(feedA), address(jumpFeed), false, true, 100_000e18, 150_000e18, 100_000e18, 150_000e18
        );
        proxy.confirmSourceEmergency();

        assertEq(proxy.source(), address(jumpFeed));
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 150_000e18);
    }

    function testConfirmSourceEmergencyCanReplaceGasBurningOldSource() public {
        TogglableGasBurnFeed gasBurningFeed = new TogglableGasBurnFeed(100_000e18);
        _proposeAndConfirm(address(gasBurningFeed));
        gasBurningFeed.burnGas();

        proxy.proposeSource(address(feedB));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        (bool success,) =
            address(proxy).call{gas: 1_000_000}(abi.encodeWithSelector(IPriceFeedProxy.confirmSourceEmergency.selector));

        assertTrue(success, "gas-burning old source made emergency replacement impossible");
        assertEq(proxy.source(), address(feedB));
    }

    // --- Scenario tests ---

    function testFixedFeedToChainlinkUpgrade() public {
        MockPriceFeed fixedFeed = new MockPriceFeed(1e18);
        PriceFeedProxy dJpyProxy = new PriceFeedProxy(address(fixedFeed), owner, address(mockBO));

        (uint256 price,) = dJpyProxy.fetchPrice();
        assertEq(price, 1e18);

        MockPriceFeed chainlinkFeed = new MockPriceFeed(0.998e18);
        dJpyProxy.proposeSource(address(chainlinkFeed));
        vm.warp(block.timestamp + dJpyProxy.TIMELOCK_DELAY());
        dJpyProxy.confirmSource();

        (price,) = dJpyProxy.fetchPrice();
        assertEq(price, 0.998e18);
    }

    function testOracleUpgradeWBTCtoCBTC() public {
        MockPriceFeed wbtcOracle = new MockPriceFeed(10_000_000e18);
        PriceFeedProxy btcProxy = new PriceFeedProxy(address(wbtcOracle), owner, address(mockBO));

        (uint256 price,) = btcProxy.fetchPrice();
        assertEq(price, 10_000_000e18);

        MockPriceFeed cbtcOracle = new MockPriceFeed(10_050_000e18);
        btcProxy.proposeSource(address(cbtcOracle));
        vm.warp(block.timestamp + btcProxy.TIMELOCK_DELAY());
        btcProxy.confirmSource();

        (price,) = btcProxy.fetchPrice();
        assertEq(price, 10_050_000e18);
    }

    // =========================================================
    //  Ownership tests — 2-step transfer
    // =========================================================

    function testTransferOwnershipSetsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        // Pending owner is set
        assertEq(proxy.pendingOwner(), newOwner);
        // Owner has NOT changed yet
        assertEq(proxy.owner(), owner);
    }

    function testTransferOwnershipRevertsForNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.transferOwnership(nonOwner);
    }

    function testTransferOwnershipEmitsStartedEvent() public {
        address newOwner = makeAddr("newOwner");
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(owner, newOwner);
        proxy.transferOwnership(newOwner);
    }

    function testTransferOwnershipWithZeroAddressCancelsPending() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);
        assertEq(proxy.pendingOwner(), newOwner);

        // Passing address(0) cancels the pending transfer
        proxy.transferOwnership(address(0));
        assertEq(proxy.pendingOwner(), address(0));
        // Owner is still the original owner
        assertEq(proxy.owner(), owner);
    }

    function testTransferOwnershipCanBeOverwritten() public {
        address firstCandidate = makeAddr("firstCandidate");
        address secondCandidate = makeAddr("secondCandidate");

        proxy.transferOwnership(firstCandidate);
        assertEq(proxy.pendingOwner(), firstCandidate);

        // Overwrite the pending transfer
        proxy.transferOwnership(secondCandidate);
        assertEq(proxy.pendingOwner(), secondCandidate);

        // First candidate can no longer accept
        vm.prank(firstCandidate);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        proxy.acceptOwnership();

        // Second candidate can
        vm.prank(secondCandidate);
        proxy.acceptOwnership();
        assertEq(proxy.owner(), secondCandidate);
    }

    function testAcceptOwnershipCompletesTransfer() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        vm.prank(newOwner);
        proxy.acceptOwnership();

        assertEq(proxy.owner(), newOwner);
        assertEq(proxy.pendingOwner(), address(0));
    }

    function testAcceptOwnershipRevertsForNonPending() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        // A random address (non-pending) cannot accept
        vm.prank(nonOwner);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        proxy.acceptOwnership();
    }

    function testAcceptOwnershipRevertsWithNoPendingTransfer() public {
        // No transfer has been started — any caller should revert
        vm.prank(nonOwner);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        proxy.acceptOwnership();
    }

    function testAcceptOwnershipEmitsTransferredEvent() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        proxy.acceptOwnership();
    }

    function testAcceptOwnershipClearsPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        vm.prank(newOwner);
        proxy.acceptOwnership();

        assertEq(proxy.pendingOwner(), address(0));
    }

    function testOldOwnerStillControlsBeforeAccept() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        // Old owner can still perform owner actions until the transfer is accepted
        proxy.proposeSource(address(feedB));
        assertEq(proxy.proposedSource(), address(feedB));
    }

    function testNewOwnerCannotActBeforeAccept() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        // New owner cannot perform owner actions until they accept
        vm.prank(newOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.proposeSource(address(feedB));
    }

    function testNewOwnerCanActAfterAccept() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        vm.prank(newOwner);
        proxy.acceptOwnership();

        vm.prank(newOwner);
        proxy.proposeSource(address(feedB));
        assertEq(proxy.proposedSource(), address(feedB));
    }

    function testOldOwnerCannotActAfterAccept() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);

        vm.prank(newOwner);
        proxy.acceptOwnership();

        // Old owner has lost power
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.proposeSource(address(feedB));
    }

    function testRenounceOwnershipIsDisabled() public {
        vm.expectRevert(IPriceFeedProxy.RenounceOwnershipDisabled.selector);
        proxy.renounceOwnership();

        assertEq(proxy.owner(), owner);
        proxy.proposeSource(address(feedB));
        assertEq(proxy.proposedSource(), address(feedB));
    }

    function testRenounceOwnershipDoesNotCancelPendingProposal() public {
        proxy.proposeSource(address(feedB));

        vm.expectRevert(IPriceFeedProxy.RenounceOwnershipDisabled.selector);
        proxy.renounceOwnership();

        assertEq(proxy.owner(), owner);
        assertEq(proxy.proposedSource(), address(feedB));
        assertGt(proxy.sourceProposedAt(), 0);
    }

    function testRenounceOwnershipDoesNotClearPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        proxy.transferOwnership(newOwner);
        assertEq(proxy.pendingOwner(), newOwner);

        vm.expectRevert(IPriceFeedProxy.RenounceOwnershipDisabled.selector);
        proxy.renounceOwnership();

        assertEq(proxy.owner(), owner);
        assertEq(proxy.pendingOwner(), newOwner);

        vm.prank(newOwner);
        proxy.acceptOwnership();
        assertEq(proxy.owner(), newOwner);
    }
}

// =============================================================
//  Integration tests — oracle failure path through proxy
// =============================================================

contract PriceFeedProxyOracleFailureTest is Test {
    PriceFeedProxy proxy;
    RealisticPriceFeed realisticFeed;
    MockBorrowerOperations mockBO;
    address owner;

    function setUp() public {
        owner = address(this);
        mockBO = new MockBorrowerOperations();

        realisticFeed = new RealisticPriceFeed(450_000e18, address(mockBO));

        proxy = new PriceFeedProxy(address(realisticFeed), owner, address(mockBO));
        mockBO.setRegisteredPriceFeed(address(proxy));
    }

    function testFetchPriceHandlesOracleFailureViaProxy() public {
        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 450_000e18);
        assertFalse(failure);
        assertFalse(mockBO.isOracleFailureShutdown());

        realisticFeed.setOracleStale(true);

        (price, failure) = proxy.fetchPrice();
        assertEq(price, 450_000e18);
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testFetchRedemptionPriceHandlesOracleFailureViaProxy() public {
        realisticFeed.setOracleStale(true);

        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(price, 450_000e18);
        assertTrue(failure);
        assertTrue(mockBO.isOracleFailureShutdown());
    }

    function testRepeatedCallsAfterShutdownReturnLastGoodPrice() public {
        realisticFeed.setOracleStale(true);

        (uint256 price1,) = proxy.fetchPrice();
        assertTrue(mockBO.isOracleFailureShutdown());

        (uint256 price2, bool failure2) = proxy.fetchPrice();
        assertEq(price1, price2);
        assertTrue(failure2);
    }

    function testLastGoodPricePreservedThroughFailure() public {
        realisticFeed.setPrice(500_000e18);
        proxy.fetchPrice();
        assertEq(proxy.lastGoodPrice(), 500_000e18);

        realisticFeed.setOracleStale(true);
        (uint256 price,) = proxy.fetchPrice();
        assertEq(price, 500_000e18);
    }

    function testSourceSwapViaEmergencyAfterOracleFailure() public {
        realisticFeed.setOracleStale(true);
        proxy.fetchPrice();
        assertTrue(mockBO.isOracleFailureShutdown());

        MockPriceFeed newFeed = new MockPriceFeed(460_000e18);
        proxy.proposeSource(address(newFeed));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        proxy.confirmSourceEmergency();

        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 460_000e18);
        assertFalse(failure);
        assertTrue(mockBO.isOracleFailureShutdown());

        proxy.resumeFromOracleFailure();
        assertFalse(mockBO.isOracleFailureShutdown());
    }

    function testResumeRequiresHealthyCurrentSource() public {
        realisticFeed.setOracleStale(true);
        proxy.fetchPrice();

        vm.expectRevert(IPriceFeedProxy.SourceNotHealthy.selector);
        proxy.resumeFromOracleFailure();

        realisticFeed.setOracleStale(false);
        (, bool failureBeforeResume) = proxy.fetchPrice();
        assertFalse(failureBeforeResume, "healthy normal price must be usable for liquidation");
        assertTrue(mockBO.isOracleFailureShutdown(), "source recovery alone must not resume borrower operations");
        (, bool redemptionFailureBeforeResume) = proxy.fetchRedemptionPrice();
        assertTrue(redemptionFailureBeforeResume, "redemption must remain paused until explicit resume");
        vm.expectEmit(true, false, false, true);
        emit IPriceFeedProxy.OracleFailureShutdownResumed(address(realisticFeed), 450_000e18, 450_000e18);
        proxy.resumeFromOracleFailure();

        assertFalse(mockBO.isOracleFailureShutdown());
    }

    function testResumeRequiresActiveOracleFailureShutdown() public {
        vm.expectRevert(IPriceFeedProxy.OracleFailureShutdownNotActive.selector);
        proxy.resumeFromOracleFailure();
    }

    function testOnlyOwnerCanResume() public {
        realisticFeed.setOracleStale(true);
        proxy.fetchPrice();
        realisticFeed.setOracleStale(false);

        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.resumeFromOracleFailure();
    }
}
