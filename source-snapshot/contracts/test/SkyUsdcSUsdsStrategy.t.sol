// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/CollateralVault.sol";
import "../src/DToken.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/IMainnetPriceFeed.sol";
import "../src/Interfaces/ISkyUsdcSUsdsConverter.sol";
import "../src/Interfaces/IStrategy.sol";
import "../src/PriceFeeds/DFUSDCPriceFeed.sol";
import "../src/PriceFeeds/JpyUsdRateProvider.sol";
import "../src/Strategies/SkyUsdcSUsdsStrategy.sol";
import "./TestContracts/ChainlinkOracleMock.sol";
import "./mocks/MockERC20.sol";

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract MockSUsdsVault is ERC4626 {
    uint256 public maxWithdrawLimit = type(uint256).max;

    constructor(IERC20 asset_) ERC20("Mock sUSDS", "msUSDS") ERC4626(asset_) {}

    function setMaxWithdrawLimit(uint256 _limit) external {
        maxWithdrawLimit = _limit;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 maxAssets = super.maxWithdraw(owner);
        return maxAssets < maxWithdrawLimit ? maxAssets : maxWithdrawLimit;
    }
}

contract M02MockBorrowerOperations {
    bool public shutdownCalled;

    function shutdownFromOracleFailure() external {
        shutdownCalled = true;
    }
}

contract MockSkyUsdcUsdsConverter is ISkyUsdcSUsdsConverter {
    using SafeERC20 for IERC20;

    MockERC20 public immutable usdc;
    MockERC20 public immutable usds;
    uint256 public feeBps;
    uint256 public reverseRefund;
    bool public previewShouldFail;
    bool public routeHalted;

    constructor(MockERC20 _usdc, MockERC20 _usds) {
        usdc = _usdc;
        usds = _usds;
    }

    function usdcToken() external view returns (IERC20) {
        return IERC20(address(usdc));
    }

    function usdsToken() external view returns (IERC20) {
        return IERC20(address(usds));
    }

    function psmWrapper() external pure returns (ISkyLitePsmWrapper) {
        return ISkyLitePsmWrapper(address(0));
    }

    function setFeeBps(uint256 _feeBps) external {
        feeBps = _feeBps;
    }

    function setReverseRefund(uint256 _reverseRefund) external {
        reverseRefund = _reverseRefund;
    }

    function setPreviewShouldFail(bool _previewShouldFail) external {
        previewShouldFail = _previewShouldFail;
    }

    function setRouteHalted(bool _routeHalted) external {
        routeHalted = _routeHalted;
    }

    function isUsdsToUsdcRouteHalted() external view returns (bool) {
        return routeHalted;
    }

    function convertUsdcToUsds(uint256 usdcAmount, uint256 minUsdsOut, address receiver)
        external
        returns (uint256 usdsOut)
    {
        IERC20(address(usdc)).safeTransferFrom(msg.sender, address(this), usdcAmount);
        usdc.burn(address(this), usdcAmount);
        usdsOut = (usdcAmount * 1e12 * (10_000 - feeBps)) / 10_000;
        require(usdsOut >= minUsdsOut, "USDS_MIN");
        usds.mint(receiver, usdsOut);
    }

    function convertUsdsToUsdc(uint256 usdsAmount, uint256 minUsdcOut, address receiver)
        external
        returns (uint256 usdcOut)
    {
        uint256 usdsSpent = usdsAmount - reverseRefund;
        IERC20(address(usds)).safeTransferFrom(msg.sender, address(this), usdsAmount);
        usds.burn(address(this), usdsSpent);
        if (reverseRefund != 0) IERC20(address(usds)).safeTransfer(msg.sender, reverseRefund);
        usdcOut = (usdsSpent * (10_000 - feeBps)) / 10_000 / 1e12;
        require(usdcOut >= minUsdcOut, "USDC_MIN");
        usdc.mint(receiver, usdcOut);
    }

    function previewUsdsToUsdc(uint256 usdsAmount) external view returns (uint256 usdcOut) {
        if (previewShouldFail) revert("PREVIEW_UNAVAILABLE");
        usdcOut = (usdsAmount * (10_000 - feeBps)) / 10_000 / 1e12;
    }
}

contract SkyUsdcSUsdsStrategyTest is Test {
    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
    }

    function test_Allocate_ConvertsUsdcToSUsdsAndValuesInUsdc() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,,) = _deploySkySetup();

        _depositAndAllocate(vault, usdc, 1_000e6);

        assertEq(vault.bufferBalance(), 0, "buffer allocated");
        assertEq(strategy.principal(), 1_000e6, "principal");
        assertEq(strategy.estimatedTotalUnderlying(), 1_000e6, "strategy value");
        assertEq(vault.totalUnderlying(), 1_000e6, "vault backing");
        assertGt(strategy.ownSUsdsShares(), 0, "shares minted");
    }

    function test_GuardianL10_ReturnInvalidatesExhaustedCacheBeforeLaterPreviewOutage() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        converter.setFeeBps(5_000);
        assertTrue(vault.refreshStrategyValuation(IStrategy(address(strategy))));
        (uint256 value,,) = vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertEq(value, 500e6);

        converter.setFeeBps(0);
        assertEq(strategy.sendToVault(600e6), 600e6);
        vm.startPrank(alice);
        vault.redeem(600e18, alice);
        vm.stopPrank();
        converter.setPreviewShouldFail(true);
        (uint256 ratio, bool available) = vault.backingRatioForPricing();
        assertFalse(available, "an exhausted historical estimate is not a measured zero");
        assertEq(ratio, 0, "unavailable sentinel, not an available haircut");
        assertEq(strategy.principal(), 400e6);
        converter.setPreviewShouldFail(false);
        (ratio, available) = vault.backingRatioForPricing();
        assertTrue(available, "live valuation restores pricing without privileged action");
        assertEq(ratio, 1e18);
    }

    function test_GuardianL08_KnownCustodyCoversLiabilitiesDuringValuationOutage() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        usdc.mint(address(vault), 1_000e6);
        converter.setPreviewShouldFail(true);
        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);

        assertGt(strategy.principal(), 0);
        (uint256 ratio, bool available) = vault.backingRatioForPricing();
        assertTrue(available, "known custody suffices without the unknown position");
        assertEq(ratio, 1e18);

        usdc.burn(address(vault), 1);
        (ratio, available) = vault.backingRatioForPricing();
        assertFalse(available, "unknown position is needed for even one missing atom");
        assertEq(ratio, 0);
        converter.setPreviewShouldFail(false);
        (ratio, available) = vault.backingRatioForPricing();
        assertTrue(available, "live valuation restores availability");
        assertEq(ratio, 1e18);
    }

    function test_PricingUsesFreshCacheWhenSkyQuoteUnavailable() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        converter.setPreviewShouldFail(true);
        (uint256 cachedRatio, bool cachedAvailable) = vault.backingRatioForPricing();
        assertEq(cachedRatio, 1e18, "fresh cache preserves measured backing");
        assertTrue(cachedAvailable, "quote outage is not measured loss");

        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);
        (uint256 staleRatio, bool staleAvailable) = vault.backingRatioForPricing();
        assertEq(staleRatio, 0, "unavailable pricing has no numeric fallback");
        assertFalse(staleAvailable, "stale cache fails closed");

        converter.setPreviewShouldFail(false);
        (uint256 recoveredRatio, bool recoveredAvailable) = vault.backingRatioForPricing();
        assertEq(recoveredRatio, 1e18, "live quote restores backing");
        assertTrue(recoveredAvailable, "live quote restores availability");
        assertEq(strategy.estimatedTotalUnderlying(), 1_000e6, "position remains intact");
    }

    function test_PricingRemainsAvailablePastCacheWhileSkyRouteHalted() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        converter.setRouteHalted(true);
        converter.setPreviewShouldFail(true);
        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);

        (uint256 haltedRatio, bool haltedAvailable) = vault.backingRatioForPricing();
        assertEq(haltedRatio, 1e18, "explicit halt uses principal-capped one-to-one value");
        assertTrue(haltedAvailable, "explicit halt does not expire into pricing unavailable");
        assertEq(strategy.estimatedTotalUnderlying(), 1_000e6, "halt valuation bypasses unavailable quote");

        converter.setRouteHalted(false);
        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);
        (uint256 failedRatio, bool failedAvailable) = vault.backingRatioForPricing();
        assertEq(failedRatio, 0, "generic quote failure has no numeric fallback");
        assertFalse(failedAvailable, "generic quote failure still fails closed after cache");

        converter.setPreviewShouldFail(false);
        (uint256 recoveredRatio, bool recoveredAvailable) = vault.backingRatioForPricing();
        assertEq(recoveredRatio, 1e18, "live quote restores backing");
        assertTrue(recoveredAvailable, "live quote restores availability");
    }

    function test_HaltedRouteValuationDoesNotRecognizeUnrealizedYield() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        usds.mint(address(susdsVault), 200e18);
        converter.setRouteHalted(true);
        converter.setPreviewShouldFail(true);

        assertEq(strategy.estimatedTotalUnderlying(), 1_000e6, "halt valuation is capped at principal");
        assertEq(strategy.realizedYield(), 0, "unrealized Sky yield is not recognized while exit is halted");
    }

    function test_PriceFeedDoesNotShutDownBranchAfterHaltedRouteCacheExpires() public {
        (CollateralVault vault,,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        converter.setRouteHalted(true);
        converter.setPreviewShouldFail(true);
        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);

        ChainlinkOracleMock usdcUsd = new ChainlinkOracleMock();
        usdcUsd.setDecimals(8);
        usdcUsd.setPrice(1e8);
        usdcUsd.setUpdatedAt(block.timestamp);

        ChainlinkOracleMock jpyUsd = new ChainlinkOracleMock();
        jpyUsd.setDecimals(8);
        jpyUsd.setPrice(666_700);
        jpyUsd.setUpdatedAt(block.timestamp);

        JpyUsdRateProvider jpyRateProvider = new JpyUsdRateProvider(address(jpyUsd), 72 hours);
        M02MockBorrowerOperations borrowerOperations = new M02MockBorrowerOperations();
        DFUSDCPriceFeed feed = new DFUSDCPriceFeed(
            address(usdcUsd), 24 hours, address(jpyRateProvider), address(vault), address(borrowerOperations)
        );

        (, bool failure) = feed.fetchPrice();
        assertFalse(failure, "route halt is not an oracle failure");
        assertFalse(borrowerOperations.shutdownCalled(), "branch remains live");
        assertEq(uint256(feed.priceSource()), uint256(IMainnetPriceFeed.PriceSource.primary), "primary remains active");
    }

    function test_SendToVault_RedeemsSUsdsAndReturnsUsdc() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,,) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        uint256 sent = strategy.sendToVault(400e6);

        assertEq(sent, 400e6, "sent");
        assertEq(vault.bufferBalance(), 400e6, "vault received usdc");
        assertEq(strategy.principal(), 600e6, "principal reduced");
        assertEq(strategy.estimatedTotalUnderlying(), 600e6, "remaining value");
    }

    function test_SendToVault_RefundedUsdsBudgetRemainsTracked() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        converter.setReverseRefund(123);

        uint256 sent = strategy.sendToVault(400e6);

        assertEq(sent, 399_999_999, "actual USDC output sent");
        assertEq(vault.bufferBalance(), 399_999_999, "vault received actual output");
        assertEq(strategy.principal(), 600_000_001, "principal reduced by actual output");
        assertEq(strategy.ownIdleUsds(), 123, "unspent USDS remains tracked");
        assertEq(usds.balanceOf(address(strategy)), 123, "tracked USDS remains in strategy");
        assertEq(usds.balanceOf(address(converter)), 0, "converter keeps no USDS");
        assertEq(usds.allowance(address(strategy), address(converter)), 0, "converter allowance cleared");
    }

    function test_SendProfitToVault_HarvestsSUsdsYieldAsUsdcWithoutReducingPrincipal() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        usds.mint(address(susdsVault), 100e18);
        assertApproxEqAbs(strategy.realizedYield(), 100e6, 1, "yield");

        uint256 sent = strategy.sendProfitToVault();

        assertApproxEqAbs(sent, 100e6, 1, "yield sent");
        assertEq(strategy.principal(), 1_000e6, "principal unchanged");
        assertApproxEqAbs(vault.bufferBalance(), 100e6, 1, "yield in buffer");
        assertApproxEqAbs(strategy.estimatedTotalUnderlying(), 1_000e6, 1, "remaining value");
    }

    function test_GuardianL07_ConversionSurplusIsReturnedPrincipalNotYield() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        usds.mint(address(susdsVault), 200e18);
        converter.setFeeBps(25); // Nonzero actual fee below the 50 bps allowance.
        uint256 profit = strategy.realizedYield();
        uint256 principalBefore = strategy.principal();
        uint256 sent = strategy.sendProfitToVault();
        assertEq(sent, profit, "yield-only amount cannot include withdrawn principal");
        uint256 returnedPrincipal = vault.bufferBalance() - sent;
        assertGt(returnedPrincipal, 0, "conversion allowance withdrew excess assets");
        assertEq(strategy.principal(), principalBefore - returnedPrincipal);
        assertGe(strategy.estimatedTotalUnderlying() + 1, strategy.principal(), "no phantom principal gap");
        strategy.emergencyWithdrawFromSky(type(uint256).max, 0);
        assertLe(strategy.principal(), 1, "full recovery leaves at most one USDC atom of rounding");
    }

    function test_SUsdsYieldDustBelowUsdcAtomDoesNotInflateOrSendProfit() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        usds.mint(address(susdsVault), 1e12 - 1);

        assertEq(strategy.estimatedTotalUnderlying(), 1_000e6, "sub-usdc dust rounds down");
        assertEq(strategy.realizedYield(), 0, "dust is not realized yield");
        assertEq(strategy.sendProfitToVault(), 0, "dust cannot be harvested as usdc");
        assertEq(vault.bufferBalance(), 0, "no dust sent to vault");

        // ERC-4626 convertToAssets can round share-accounted donations down by
        // one USDS wei, so one extra wei is still not necessarily harvestable.
        usds.mint(address(susdsVault), 1);
        assertEq(strategy.realizedYield(), 0, "share-rounded usdc atom is still dust");

        usds.mint(address(susdsVault), 1);

        assertEq(strategy.realizedYield(), 1, "dust above share and usdc floors becomes yield");
        assertEq(strategy.sendProfitToVault(), 1, "yield atom sent");
        assertEq(vault.bufferBalance(), 1, "vault received one usdc atom");
        assertEq(strategy.principal(), 1_000e6, "principal unchanged");
    }

    function test_DonatedSUsdsSharesDoNotInflateValuation() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        uint256 valueBefore = strategy.estimatedTotalUnderlying();

        address donor = makeAddr("donor");
        usds.mint(donor, 500e18);
        vm.startPrank(donor);
        usds.approve(address(susdsVault), 500e18);
        uint256 donatedShares = susdsVault.deposit(500e18, donor);
        susdsVault.transfer(address(strategy), donatedShares);
        vm.stopPrank();

        assertEq(strategy.estimatedTotalUnderlying(), valueBefore, "donation ignored");
        assertEq(vault.totalUnderlying(), valueBefore, "vault backing unchanged");
    }

    function test_EmergencyRedeemThenConvertReturnsPrincipalToVault() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,,) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        strategy.emergencyRedeemSUsdsToUsds(1_000e18);
        assertEq(strategy.ownIdleUsds(), 1_000e18, "idle usds tracked");

        uint256 sent = strategy.emergencyConvertIdleUsdsToVault(type(uint256).max, 1_000e6);

        assertEq(sent, 1_000e6, "sent");
        assertEq(strategy.principal(), 0, "principal returned");
        assertEq(vault.bufferBalance(), 1_000e6, "vault recovered");
        assertEq(strategy.estimatedTotalUnderlying(), 0, "strategy empty");
    }

    function test_EmergencyConvertCannotBypassMaxConversionLoss() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        strategy.emergencyRedeemSUsdsToUsds(1_000e18);
        converter.setFeeBps(100);

        vm.expectRevert(bytes("USDC_MIN"));
        strategy.emergencyConvertIdleUsdsToVault(type(uint256).max, 0);

        assertEq(strategy.ownIdleUsds(), 1_000e18, "idle usds preserved");
    }

    function test_EmergencyConvertRevertsWhenUsdsDustWouldReturnZeroUsdc() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,,) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        uint256 usdsDust = 1e12 - 1;
        strategy.emergencyRedeemSUsdsToUsds(usdsDust);
        assertEq(strategy.ownIdleUsds(), usdsDust, "idle usds dust tracked");

        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsStrategy.SkyUsdcSUsdsStrategy__ZeroUsdcOut.selector, usdsDust)
        );
        strategy.emergencyConvertIdleUsdsToVault(type(uint256).max, 0);

        assertEq(strategy.ownIdleUsds(), usdsDust, "idle usds dust preserved");
        assertEq(vault.bufferBalance(), 0, "vault received no zero-usdc conversion");
        assertEq(strategy.principal(), 1_000e6, "principal unchanged");
    }

    function test_EmergencyConvertTracksActualUsdsSpentWhenConverterUsesBudget() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        strategy.emergencyRedeemSUsdsToUsds(1_000e18);
        converter.setReverseRefund(123);

        uint256 sent = strategy.emergencyConvertIdleUsdsToVault(1_000e18, 999_999_999);

        assertEq(sent, 999_999_999);
        assertEq(strategy.ownIdleUsds(), 123, "unspent USDS remains tracked");
        assertEq(usdc.balanceOf(address(vault)), 999_999_999);
        assertEq(strategy.principal(), 1, "principal reduced by actual output");
        assertEq(usds.balanceOf(address(strategy)), 123, "tracked USDS remains in strategy");
        assertEq(usds.balanceOf(address(converter)), 0, "converter keeps no USDS");
        assertEq(usds.allowance(address(strategy), address(converter)), 0, "converter allowance cleared");
    }

    function test_EmergencyWithdrawFromSky_RefundedUsdsBudgetRemainsTracked() public {
        (
            CollateralVault vault,
            SkyUsdcSUsdsStrategy strategy,,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        ) = _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);
        converter.setReverseRefund(123);

        uint256 sent = strategy.emergencyWithdrawFromSky(type(uint256).max, 999_999_999);

        assertEq(sent, 999_999_999, "actual USDC output sent");
        assertEq(vault.bufferBalance(), 999_999_999, "vault received actual output");
        assertEq(strategy.principal(), 1, "principal reduced by actual output");
        assertEq(strategy.ownSUsdsShares(), 0, "all owned sUSDS redeemed");
        assertEq(strategy.ownIdleUsds(), 123, "unspent USDS remains tracked");
        assertEq(usds.balanceOf(address(strategy)), 123, "tracked USDS remains in strategy");
        assertEq(usds.balanceOf(address(converter)), 0, "converter keeps no USDS");
        assertEq(usds.allowance(address(strategy), address(converter)), 0, "converter allowance cleared");
    }

    function test_EmergencyWithdrawCannotBypassMaxConversionLoss() public {
        (CollateralVault vault, SkyUsdcSUsdsStrategy strategy,, MockERC20 usdc,, MockSkyUsdcUsdsConverter converter) =
            _deploySkySetup();
        _depositAndAllocate(vault, usdc, 1_000e6);

        uint256 sharesBefore = strategy.ownSUsdsShares();
        converter.setFeeBps(100);

        vm.expectRevert(bytes("USDC_MIN"));
        strategy.emergencyWithdrawFromSky(type(uint256).max, 0);

        assertEq(strategy.ownSUsdsShares(), sharesBefore, "sUSDS redeem rolled back");
        assertEq(strategy.ownIdleUsds(), 0, "idle usds unchanged");
        assertEq(vault.bufferBalance(), 0, "vault did not receive under-floor usdc");
    }

    function test_SweepRewardToken_RejectsUsdsAndSUsds() public {
        (, SkyUsdcSUsdsStrategy strategy, MockSUsdsVault susdsVault,, MockERC20 usds,) = _deploySkySetup();

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(usds)), type(uint256).max);

        vm.expectRevert(BaseStrategy.CannotSweepProtectedToken.selector);
        strategy.sweepRewardToken(IERC20(address(susdsVault)), type(uint256).max);
    }

    function test_Initialize_RevertsWhenUnderlyingIsNotUsdcDecimals() public {
        MockERC20 badUsdc = new MockERC20("Bad USDC", "bUSDC", 18);
        MockERC20 usds = new MockERC20("USDS", "USDS", 18);
        MockSUsdsVault susdsVault = new MockSUsdsVault(IERC20(address(usds)));
        MockSkyUsdcUsdsConverter converter = new MockSkyUsdcUsdsConverter(badUsdc, usds);

        SkyUsdcSUsdsStrategy implementation = new SkyUsdcSUsdsStrategy();
        bytes memory initializer = abi.encodeWithSelector(
            SkyUsdcSUsdsStrategy.initialize.selector,
            address(this),
            IERC20(address(badUsdc)),
            admin,
            admin,
            IERC20(address(usds)),
            IERC4626(address(susdsVault)),
            ISkyUsdcSUsdsConverter(address(converter)),
            50
        );

        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsStrategy.SkyUsdcSUsdsStrategy__InvalidUsdcDecimals.selector, 18)
        );
        new ERC1967Proxy(address(implementation), initializer);
    }

    function test_Initialize_RevertsOnNonContractConverter() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        MockERC20 usds = new MockERC20("USDS", "USDS", 18);
        MockSUsdsVault susdsVault = new MockSUsdsVault(IERC20(address(usds)));
        address converterEoa = makeAddr("converterEoa");

        SkyUsdcSUsdsStrategy implementation = new SkyUsdcSUsdsStrategy();
        bytes memory initializer = abi.encodeWithSelector(
            SkyUsdcSUsdsStrategy.initialize.selector,
            address(this),
            IERC20(address(usdc)),
            admin,
            admin,
            IERC20(address(usds)),
            IERC4626(address(susdsVault)),
            ISkyUsdcSUsdsConverter(converterEoa),
            50
        );

        vm.expectRevert(abi.encodeWithSelector(BaseStrategy.NotContract.selector, converterEoa));
        new ERC1967Proxy(address(implementation), initializer);
    }

    function _deploySkySetup()
        internal
        returns (
            CollateralVault collateralVault,
            SkyUsdcSUsdsStrategy strategy,
            MockSUsdsVault susdsVault,
            MockERC20 usdc,
            MockERC20 usds,
            MockSkyUsdcUsdsConverter converter
        )
    {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        usds = new MockERC20("Mock USDS", "mUSDS", 18);
        susdsVault = new MockSUsdsVault(IERC20(address(usds)));
        converter = new MockSkyUsdcUsdsConverter(usdc, usds);

        collateralVault = _deployVault(usdc);
        strategy = _deployStrategy(collateralVault, usdc, usds, susdsVault, converter);

        collateralVault.addToWhitelist(address(strategy));
        collateralVault.addStrategy(IStrategy(address(strategy)), 10000, type(uint256).max);
    }

    function _deployVault(MockERC20 usdc) internal returns (CollateralVault collateralVault) {
        DToken dTokenImplementation = new DToken();
        CollateralVault vaultImplementation = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dTokenInitializer = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        DToken dToken = DToken(address(new ERC1967Proxy(address(dTokenImplementation), dTokenInitializer)));
        dToken.setAllowedUnderlying(address(usdc), true);
        bytes memory vaultInitializer = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(usdc)), IDToken(address(dToken)), treasury, admin
        );
        collateralVault = CollateralVault(address(new ERC1967Proxy(address(vaultImplementation), vaultInitializer)));
        dToken.setTokenInfo("dUSDC", "dUSDC", IERC20MetadataUpgradeable(address(usdc)));
        activateDTokenForTest(dToken);
    }

    function _deployStrategy(
        CollateralVault collateralVault,
        MockERC20 usdc,
        MockERC20 usds,
        MockSUsdsVault susdsVault,
        MockSkyUsdcUsdsConverter converter
    ) internal returns (SkyUsdcSUsdsStrategy strategy) {
        SkyUsdcSUsdsStrategy strategyImplementation = new SkyUsdcSUsdsStrategy();
        bytes memory strategyInitializer = abi.encodeWithSelector(
            SkyUsdcSUsdsStrategy.initialize.selector,
            address(collateralVault),
            IERC20(address(usdc)),
            admin,
            admin,
            IERC20(address(usds)),
            IERC4626(address(susdsVault)),
            ISkyUsdcSUsdsConverter(address(converter)),
            50
        );
        strategy = SkyUsdcSUsdsStrategy(address(new ERC1967Proxy(address(strategyImplementation), strategyInitializer)));
    }

    function _depositAndAllocate(CollateralVault collateralVault, MockERC20 usdc, uint256 amount) internal {
        usdc.mint(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(collateralVault), amount);
        collateralVault.deposit(amount);
        vm.stopPrank();
        collateralVault.setBufferConfig(0, 0);
        collateralVault.allocate();
    }
}
