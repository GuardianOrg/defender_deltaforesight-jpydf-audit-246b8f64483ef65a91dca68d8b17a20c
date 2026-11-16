// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/Interfaces/IPriceFeed.sol";
import "src/Interfaces/IPriceFeedProxy.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";

contract JpyAgeProviderMock {
    uint256 private _updatedAt;
    bool private _revertRead;
    bool private _burnReadGas;
    bool private _returnBomb;

    constructor(uint256 updatedAt_) {
        _updatedAt = updatedAt_;
    }

    function lastGoodJpyUpdatedAt() external view returns (uint256) {
        if (_revertRead) revert("provenance unavailable");
        if (_burnReadGas) {
            assembly {
                invalid()
            }
        }
        if (_returnBomb) {
            assembly {
                return(0, 0x10000)
            }
        }
        return _updatedAt;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    function setRevertRead(bool value) external {
        _revertRead = value;
    }

    function setBurnReadGas(bool value) external {
        _burnReadGas = value;
    }

    function setReturnBomb(bool value) external {
        _returnBomb = value;
    }
}

contract JpyAgeSourceMock is IPriceFeed {
    JpyAgeProviderMock public immutable jpyUsdRateProvider;
    uint256 public lastGoodPrice;
    uint256 private _redemptionPrice;
    bool private _failure;
    bool private _revertRedemption;
    bool private _refreshOnRedemption;

    constructor(JpyAgeProviderMock provider_, uint256 price_) {
        jpyUsdRateProvider = provider_;
        lastGoodPrice = price_;
        _redemptionPrice = price_;
    }

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, _failure);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        if (_revertRedemption) revert("redemption unavailable");
        if (_refreshOnRedemption) jpyUsdRateProvider.setUpdatedAt(block.timestamp);
        return (_redemptionPrice, _failure);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (_redemptionPrice, _failure);
    }

    function setPrices(uint256 normalPrice, uint256 redemptionPrice) external {
        lastGoodPrice = normalPrice;
        _redemptionPrice = redemptionPrice;
    }

    function setFailure(bool value) external {
        _failure = value;
    }

    function setRevertRedemption(bool value) external {
        _revertRedemption = value;
    }

    function setRefreshOnRedemption(bool value) external {
        _refreshOnRedemption = value;
    }
}

contract MissingJpyProvenanceSource is IPriceFeed {
    uint256 public lastGoodPrice = 100_000e18;

    function fetchPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }
}

contract MalformedJpyProvenanceSource is MissingJpyProvenanceSource {
    function jpyUsdRateProvider() external pure returns (bytes32) {
        return bytes32(type(uint256).max);
    }
}

contract JpyAgeBorrowerOperationsMock {
    bool public isOracleFailureShutdown;
    address public registeredPriceFeed;

    function setRegisteredPriceFeed(address priceFeed) external {
        registeredPriceFeed = priceFeed;
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

contract PriceFeedProxyJpyRedemptionAgeTest is Test {
    bytes32 private constant SOURCE_FAILURE_HANDLED_SIG = keccak256("SourceFailureHandled(address)");

    JpyAgeProviderMock provider;
    JpyAgeSourceMock source;
    JpyAgeBorrowerOperationsMock bo;
    PriceFeedProxy proxy;

    function setUp() public {
        vm.warp(100 days);
        provider = new JpyAgeProviderMock(block.timestamp);
        source = new JpyAgeSourceMock(provider, 100_000e18);
        bo = new JpyAgeBorrowerOperationsMock();
        proxy = new PriceFeedProxy(address(source), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
    }

    function test_redemptionAllowedOneSecondBeforeBoundary() public {
        provider.setUpdatedAt(block.timestamp - 30 hours + 1);
        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(price, 100_000e18);
        assertFalse(failure);
    }

    function test_exactBoundaryStopsOnlyNormalRedemptionWithoutFailureAlarmOrPause() public {
        provider.setUpdatedAt(block.timestamp - 30 hours);

        vm.recordLogs();
        (uint256 redemptionPrice, bool redemptionFailure) = proxy.fetchRedemptionPrice();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(redemptionPrice, 100_000e18);
        assertTrue(redemptionFailure);
        assertFalse(bo.isOracleFailureShutdown());
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != SOURCE_FAILURE_HANDLED_SIG);
        }

        (, bool normalFailure) = proxy.fetchPrice();
        (, bool urgentFailure) = proxy.fetchUrgentRedemptionPrice();
        assertFalse(normalFailure);
        assertFalse(urgentFailure);
    }

    function test_agedQuoteNeverReplacesRedemptionCache() public {
        proxy.fetchRedemptionPrice();
        source.setPrices(200_000e18, 200_000e18);
        provider.setUpdatedAt(block.timestamp - 30 hours);

        (uint256 agedPrice, bool agedFailure) = proxy.fetchRedemptionPrice();
        assertEq(agedPrice, 200_000e18);
        assertTrue(agedFailure);

        source.setRevertRedemption(true);
        (uint256 fallbackPrice, bool fallbackFailure) = proxy.fetchRedemptionPrice();
        assertEq(fallbackPrice, 100_000e18);
        assertTrue(fallbackFailure);
        assertTrue(bo.isOracleFailureShutdown());
    }

    function test_firstFreshSourceCallReopensRedemptionAutomatically() public {
        provider.setUpdatedAt(block.timestamp - 30 hours);
        source.setPrices(101_000e18, 101_000e18);
        source.setRefreshOnRedemption(true);

        (uint256 price, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(price, 101_000e18);
        assertFalse(failure);
        assertFalse(bo.isOracleFailureShutdown());
    }

    function test_realSourceFailureStillUsesExistingPausePathWhenAged() public {
        provider.setUpdatedAt(block.timestamp - 30 hours);
        source.setFailure(true);

        vm.expectEmit(true, false, false, false);
        emit IPriceFeedProxy.SourceFailureHandled(address(source));
        (, bool failure) = proxy.fetchRedemptionPrice();
        assertTrue(failure);
        assertTrue(bo.isOracleFailureShutdown());
    }

    function test_runtimeProvenanceReadFailureStopsOnlyNormalRedemption() public {
        provider.setRevertRead(true);
        (, bool failure) = proxy.fetchRedemptionPrice();
        assertTrue(failure);
        assertFalse(bo.isOracleFailureShutdown());
    }

    function test_runtimeProvenanceGasBurnIsBoundedAndStopsOnlyNormalRedemption() public {
        provider.setBurnReadGas(true);
        (, bool failure) = proxy.fetchRedemptionPrice{gas: 200_000}();
        assertTrue(failure);
        assertFalse(bo.isOracleFailureShutdown());
    }

    function test_runtimeProvenanceReturnBombIsBoundedAndStopsOnlyNormalRedemption() public {
        provider.setReturnBomb(true);
        (, bool failure) = proxy.fetchRedemptionPrice{gas: 200_000}();
        assertTrue(failure);
        assertFalse(bo.isOracleFailureShutdown());
    }

    function test_constructorRejectsMissingMalformedAndAgedProvenance() public {
        MissingJpyProvenanceSource missing = new MissingJpyProvenanceSource();
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(missing), address(this), address(bo));

        MalformedJpyProvenanceSource malformed = new MalformedJpyProvenanceSource();
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(malformed), address(this), address(bo));

        JpyAgeProviderMock agedProvider = new JpyAgeProviderMock(block.timestamp - 30 hours);
        JpyAgeSourceMock agedSource = new JpyAgeSourceMock(agedProvider, 100_000e18);
        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        new PriceFeedProxy(address(agedSource), address(this), address(bo));
    }

    function test_bothConfirmationPathsRejectMissingProvenanceAtomically() public {
        MissingJpyProvenanceSource missing = new MissingJpyProvenanceSource();
        proxy.proposeSource(address(missing));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        proxy.confirmSource();
        assertEq(proxy.source(), address(source));
        assertEq(proxy.proposedSource(), address(missing));

        vm.expectRevert(IPriceFeedProxy.InvalidSource.selector);
        proxy.confirmSourceEmergency();
        assertEq(proxy.source(), address(source));
        assertEq(proxy.proposedSource(), address(missing));
    }

    function test_agedSourceCanBeEmergencySwitchedWithoutCachingItsQuote() public {
        JpyAgeProviderMock agedProvider = new JpyAgeProviderMock(block.timestamp - 30 hours);
        JpyAgeSourceMock agedSource = new JpyAgeSourceMock(agedProvider, 150_000e18);
        proxy.proposeSource(address(agedSource));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        agedProvider.setUpdatedAt(block.timestamp - 30 hours);
        proxy.confirmSourceEmergency();

        assertEq(proxy.source(), address(agedSource));
        (, bool gated) = proxy.fetchRedemptionPrice();
        assertTrue(gated);

        agedSource.setRevertRedemption(true);
        (uint256 fallbackPrice, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(fallbackPrice, 100_000e18);
        assertTrue(failure);
    }

    function test_agedSourceCanBeNormallySwitchedWithinDeviationWithoutCachingItsQuote() public {
        JpyAgeProviderMock agedProvider = new JpyAgeProviderMock(block.timestamp);
        JpyAgeSourceMock agedSource = new JpyAgeSourceMock(agedProvider, 100_500e18);
        proxy.proposeSource(address(agedSource));
        vm.warp(block.timestamp + proxy.TIMELOCK_DELAY());
        agedProvider.setUpdatedAt(block.timestamp - 30 hours);
        proxy.confirmSource();

        assertEq(proxy.source(), address(agedSource));
        (, bool gated) = proxy.fetchRedemptionPrice();
        assertTrue(gated);

        agedSource.setRevertRedemption(true);
        (uint256 fallbackPrice, bool failure) = proxy.fetchRedemptionPrice();
        assertEq(fallbackPrice, 100_000e18);
        assertTrue(failure);
    }

    function test_resumeCanClearIndependentPauseWithoutCachingAgedQuote() public {
        proxy.fetchRedemptionPrice();
        source.setFailure(true);
        proxy.fetchPrice();
        assertTrue(bo.isOracleFailureShutdown());

        source.setFailure(false);
        source.setPrices(200_000e18, 200_000e18);
        provider.setUpdatedAt(block.timestamp - 30 hours);
        proxy.resumeFromOracleFailure();
        assertFalse(bo.isOracleFailureShutdown());

        (, bool gated) = proxy.fetchRedemptionPrice();
        assertTrue(gated);
        source.setRevertRedemption(true);
        (uint256 fallbackPrice,) = proxy.fetchRedemptionPrice();
        assertEq(fallbackPrice, 100_000e18);
    }

    function test_resumeCanClearIndependentPauseWhenRuntimeProvenanceIsUnavailable() public {
        proxy.fetchRedemptionPrice();
        source.setFailure(true);
        proxy.fetchPrice();
        assertTrue(bo.isOracleFailureShutdown());

        source.setFailure(false);
        source.setPrices(200_000e18, 200_000e18);
        provider.setRevertRead(true);
        proxy.resumeFromOracleFailure();
        assertFalse(bo.isOracleFailureShutdown());

        (, bool gated) = proxy.fetchRedemptionPrice();
        assertTrue(gated);
        source.setRevertRedemption(true);
        (uint256 fallbackPrice,) = proxy.fetchRedemptionPrice();
        assertEq(fallbackPrice, 100_000e18);
    }
}
