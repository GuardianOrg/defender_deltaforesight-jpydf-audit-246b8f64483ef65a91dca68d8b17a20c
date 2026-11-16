// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";
import "src/PriceFeeds/MainnetPriceFeedBase.sol";
import "src/Interfaces/IPriceFeed.sol";
import "./TestContracts/FreshJpyProvenance.sol";

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

contract GasGuardRevertFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_000e18;
    bool private _revertFetch;

    error InsufficientGasForExternalCall();

    function fetchPrice() external view returns (uint256, bool) {
        if (_revertFetch) revert InsufficientGasForExternalCall();
        return (lastGoodPrice, false);
    }

    function fetchRedemptionPrice() external view returns (uint256, bool) {
        if (_revertFetch) revert InsufficientGasForExternalCall();
        return (lastGoodPrice, false);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        if (_revertFetch) revert InsufficientGasForExternalCall();
        return (lastGoodPrice, false);
    }

    function setRevertFetch(bool value) external {
        _revertFetch = value;
    }
}

contract GenuineFailureFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_000e18;
    MockBO public bo;

    constructor(MockBO _bo) {
        bo = _bo;
    }

    function fetchPrice() external returns (uint256, bool) {
        bo.shutdownFromOracleFailure();
        return (lastGoodPrice, true);
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        bo.shutdownFromOracleFailure();
        return (lastGoodPrice, true);
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }
}

// Mirrors the REAL genuine-failure revert shape that the proxy must NOT bubble:
// BorrowerOperations.shutdownFromOracleFailure() reverts with the no-arg custom
// error CallerNotPriceFeed() (exactly 4 bytes) when the caller is the underlying
// feed rather than the registered proxy. Unlike GenuineFailureFeed (which reverts
// via a long Error(string) require), this exercises _bubbleIfGasError's `length == 4`
// branch — where only the selector, not the length, separates it from the gas guard.
contract FourByteNonGasErrorFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_000e18;

    error CallerNotPriceFeed();

    function fetchPrice() external pure returns (uint256, bool) {
        revert CallerNotPriceFeed();
    }

    function fetchRedemptionPrice() external pure returns (uint256, bool) {
        revert CallerNotPriceFeed();
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }
}

// Same 4-byte selector as the gas guard, but with extra ABI data appended (36 bytes:
// abi.encodeWithSelector(sel, uint256(1))). This is NOT the genuine no-arg
// InsufficientGasForExternalCall() (which is exactly 4 bytes), so _bubbleIfGasError's
// `length == 4` guard must REJECT it: the proxy must fall through to a normal shutdown,
// never bubble. A malicious/broken source could craft exactly this payload.
contract SameSelectorExtraDataFeed is IPriceFeed, FreshJpyProvenance {
    uint256 public lastGoodPrice = 100_000e18;

    function fetchPrice() external pure returns (uint256, bool) {
        bytes memory err =
            abi.encodeWithSelector(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector, uint256(1));
        assembly {
            revert(add(err, 0x20), mload(err))
        }
    }

    function fetchRedemptionPrice() external pure returns (uint256, bool) {
        bytes memory err =
            abi.encodeWithSelector(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector, uint256(1));
        assembly {
            revert(add(err, 0x20), mload(err))
        }
    }

    function fetchUrgentRedemptionPrice() external view returns (uint256, bool) {
        return (lastGoodPrice, false);
    }
}

contract PriceFeedProxyGasGriefTest is Test {
    PriceFeedProxy proxy;
    MockBO bo;

    function test_fix_gasGuardRevert_isBubbled_notShutdown() public {
        bo = new MockBO();
        GasGuardRevertFeed feed = new GasGuardRevertFeed();
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
        feed.setRevertFetch(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        proxy.fetchPrice();
        assertFalse(bo.hasBeenShutDown());
    }

    // Regression for the redemption path: the gas guard must bubble here too, not shut down.
    function test_fix_gasGuardRevert_isBubbled_notShutdown_redemption() public {
        bo = new MockBO();
        GasGuardRevertFeed feed = new GasGuardRevertFeed();
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
        feed.setRevertFetch(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        proxy.fetchRedemptionPrice();
        assertFalse(bo.hasBeenShutDown());
    }

    function test_fix_gasGuardRevert_isBubbled_notShutdown_urgentRedemption() public {
        bo = new MockBO();
        GasGuardRevertFeed feed = new GasGuardRevertFeed();
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));
        feed.setRevertFetch(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        proxy.fetchUrgentRedemptionPrice();
        assertFalse(bo.hasBeenShutDown());
    }

    function test_constructorUrgentGasGuardRevert_isBubbled() public {
        bo = new MockBO();
        GasGuardRevertFeed feed = new GasGuardRevertFeed();
        feed.setRevertFetch(true);

        vm.expectRevert(MainnetPriceFeedBase.InsufficientGasForExternalCall.selector);
        new PriceFeedProxy(address(feed), address(this), address(bo));
    }

    function test_regression_genuineOracleFailure_stillShutsDown() public {
        bo = new MockBO();
        GenuineFailureFeed feed = new GenuineFailureFeed(bo);
        proxy = new PriceFeedProxy(address(feed), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));

        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
    }

    // Regression for the 4-byte selector-discrimination path — the real production
    // shape that test_regression_genuineOracleFailure_stillShutsDown does NOT cover
    // (it reverts via a long Error(string), filtered out by the `length == 4` check).
    // A no-arg custom error is the same length (4 bytes) as the gas guard, so only the
    // selector keeps it OUT of the bubble branch: it must fall through to a normal
    // shutdown and never be re-reverted. If _bubbleIfGasError ever matched too loosely,
    // a genuine failure would be bubbled instead of shutting the branch down — this
    // test would catch that.
    function test_regression_fourByteNonGasError_shutsDown_notBubbled() public {
        bo = new MockBO();
        proxy = new PriceFeedProxy(address(new FourByteNonGasErrorFeed()), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));

        // A non-bubbled revert means fetchPrice returns normally (no re-revert) and the
        // branch is shut down. A bubbled revert would make this call revert and fail here.
        (, bool failure) = proxy.fetchPrice();
        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
    }

    // Negative test for the EXACT-LENGTH intent of `_err.length == 4` (suggested by Codex).
    // A malicious/broken source can return the gas-guard selector with extra data appended
    // (abi.encodeWithSelector(sel, uint256(1)) => 36 bytes). That is NOT the genuine no-arg
    // gas guard, so it must NOT be bubbled: the proxy must fall through to a normal shutdown.
    // Locks the `== 4` boundary against a future relaxation to `>= 4` (selector prefix match).
    function test_regression_sameSelectorExtraData_shutsDown_notBubbled() public {
        bo = new MockBO();
        proxy = new PriceFeedProxy(address(new SameSelectorExtraDataFeed()), address(this), address(bo));
        bo.setRegisteredPriceFeed(address(proxy));

        // Same path on the redemption side is covered by exercising fetchPrice here; both
        // proxy entrypoints share the identical _bubbleIfGasError filter.
        (uint256 price, bool failure) = proxy.fetchPrice();
        assertEq(price, 100_000e18); // fell back to source.lastGoodPrice() via _handleFailedFetch
        assertTrue(failure);
        assertTrue(bo.hasBeenShutDown());
    }

    // (Removed test_proxySelectorMirrorsUpstream: PriceFeedProxy now references
    //  MainnetPriceFeedBase.InsufficientGasForExternalCall.selector directly, so selector
    //  identity with upstream is enforced at COMPILE time — there is no local mirror to drift.)
}
