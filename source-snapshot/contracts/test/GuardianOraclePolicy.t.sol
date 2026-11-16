// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestContracts/DevTestSetup.sol";
import "./TestContracts/ChainlinkOracleMock.sol";
import "src/PriceFeeds/DFUSDCPriceFeed.sol";
import "src/PriceFeeds/JpyUsdRateProvider.sol";
import "src/PriceFeeds/PriceFeedProxy.sol";

contract GuardianOracleBacking {
    function backingRatioForPricing() external pure returns (uint256, bool) {
        return (1e18, true);
    }
}

// Policy regression and residual-risk comparison; synthetic FX, not a market replay.
contract GuardianOraclePolicyTest is DevTestSetup {
    ChainlinkOracleMock internal usd;
    ChainlinkOracleMock internal jpy;
    JpyUsdRateProvider internal provider;
    PriceFeedProxy internal proxy;
    uint256 internal anchor;
    uint256 internal victim;

    function setUp() public override {
        vm.warp(1_700_000_000);
        accounts = new Accounts();
        createAccounts();
        A = accountsList[0];
        B = accountsList[1];
        C = accountsList[2];
        TestDeployer deployer = new TestDeployer();
        TestDeployer.LiquityContractsDev memory c;
        (c, collateralRegistry, jpydfToken, hintHelpers,, WETH,) = deployer.deployAndConnectContracts(
            TestDeployer.TroveManagerParams(
                CCR_DUSDC,
                MCR_DUSDC,
                BCR_DUSDC,
                SCR_DUSDC,
                LIQUIDATION_PENALTY_SP_DUSDC,
                LIQUIDATION_PENALTY_REDISTRIBUTION_DUSDC
            )
        );
        borrowerOperations = c.borrowerOperations;
        troveManager = c.troveManager;
        activePool = c.activePool;
        stabilityPool = c.stabilityPool;
        collToken = c.collToken;
        MCR = MCR_DUSDC;
        SCR = SCR_DUSDC;
        for (uint256 i; i < 3; ++i) {
            giveAndApproveColl(accountsList[i], 1_000_000e18);
        }
        usd = new ChainlinkOracleMock();
        usd.setDecimals(8);
        usd.setPrice(1e8);
        usd.setUpdatedAt(block.timestamp);
        jpy = new ChainlinkOracleMock();
        jpy.setDecimals(8);
        jpy.setPrice(600_000);
        jpy.setUpdatedAt(block.timestamp);
        provider = new JpyUsdRateProvider(address(jpy), 30 hours);
        DFUSDCPriceFeed source = new DFUSDCPriceFeed(
            address(usd), 24 hours, address(provider), address(new GuardianOracleBacking()), address(borrowerOperations)
        );
        PriceFeedProxy deployed = new PriceFeedProxy(address(source), address(this), address(borrowerOperations));
        // Existing deployer wires a test feed into Core. Install the real proxy at that
        // registered address so BOTH BO and TM use it and callback authorization is real.
        // No core state, liquidation guard, or shutdown threshold is patched.
        vm.etch(address(c.priceFeed), address(deployed).code);
        vm.copyStorage(address(deployed), address(c.priceFeed));
        proxy = PriceFeedProxy(address(c.priceFeed));
        assertEq(proxy.source(), address(source));
        assertEq(address(proxy.borrowerOperations()), address(borrowerOperations));
        openTroveNoHints100pct(A, 3000e18, 200_000e18, 5e16);
        vm.prank(A);
        stabilityPool.provideToSP(150_000e18, false);
        victim = openTroveNoHints100pct(B, 800e18, 100_000e18, 5e16);
        anchor = block.timestamp;
    }

    // Pre-position the book near a boundary with a VALID published FX round;
    // then omit updates. Subsequent reference FX is the counterfactual price.
    function _ageAtVictimICR(uint256 age, uint256 target) internal returns (uint256 price) {
        uint256 q = getTroveEntireColl(victim) * 1e26 / (getTroveEntireDebt(victim) * target);
        jpy.setPrice(int256(q));
        jpy.setRoundData(2, 2);
        proxy.fetchPrice();
        vm.warp(anchor + age);
        usd.setUpdatedAt(block.timestamp);
        bool failure;
        (price, failure) = proxy.fetchPrice();
        assertFalse(failure, "liquidation price remains usable before 54h");
        assertEq(provider.lastGoodJpyUpdatedAt(), anchor);
    }

    function _liquidate() internal {
        uint256[] memory ids = new uint256[](1);
        ids[0] = victim;
        troveManager.batchLiquidateTroves(ids);
    }

    function _freshFx(int256 q) internal returns (uint256 price) {
        jpy.setPrice(q);
        jpy.setRoundData(3, 3);
        jpy.setUpdatedAt(block.timestamp);
        (price,) = proxy.fetchPrice();
    }

    function _wrongfulLiquidation(uint256 age) internal {
        uint256 stale = _ageAtVictimICR(age, MCR - 0.005e18);
        uint256 q = provider.lastGoodJpyRate() / 1e10;
        uint256 snapshot = vm.snapshotState();
        // JPY/USD down 1% = yen weakens; fresh collateral/JPY is higher.
        uint256 fresh = _freshFx(int256(q * 99 / 100));
        emit log_named_uint("fresh ICR", troveManager.getCurrentICR(victim, fresh));
        assertGt(troveManager.getCurrentICR(victim, fresh), MCR);
        vm.expectRevert(TroveManager.NothingToLiquidate.selector);
        _liquidate();
        assertTrue(vm.revertToState(snapshot));
        emit log_named_uint("stale ICR", troveManager.getCurrentICR(victim, stale));
        assertLt(troveManager.getCurrentICR(victim, stale), MCR);
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.closedByLiquidation));
    }

    function testFuzz_GraceWindowCanWrongfullyLiquidateWhenJpyWeakens(uint32 age) public {
        _wrongfulLiquidation(bound(uint256(age), 30 hours, 54 hours - 1));
    }

    function testFuzz_GraceWindowCanMissLiquidationWhenJpyStrengthens(uint32 age) public {
        uint256 stale = _ageAtVictimICR(bound(uint256(age), 30 hours, 54 hours - 1), MCR + 0.005e18);
        assertGt(troveManager.getCurrentICR(victim, stale), MCR);
        vm.expectRevert(TroveManager.NothingToLiquidate.selector);
        _liquidate();
        uint256 fresh = _freshFx(int256(provider.lastGoodJpyRate() / 1e10 * 101 / 100));
        assertLt(troveManager.getCurrentICR(victim, fresh), MCR);
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.closedByLiquidation));
    }

    function test_30hBlocksAllRiskIncreasesButFreshRoundReopens() public {
        vm.warp(anchor + 30 hours - 1);
        usd.setUpdatedAt(block.timestamp);
        vm.prank(address(borrowerOperations));
        (, bool beforeFailure) = proxy.fetchPrice();
        assertFalse(beforeFailure);
        vm.warp(anchor + 30 hours);
        (, bool liquidationFailure) = proxy.fetchPrice();
        assertFalse(liquidationFailure);
        (, bool redemptionFailure) = proxy.fetchRedemptionPrice();
        assertTrue(redemptionFailure);
        assertFalse(borrowerOperations.isOracleFailureShutdown());

        vm.prank(A);
        jpydfToken.transfer(B, 1000e18); // Cover accrued debt so close reaches its price gate.
        vm.startPrank(B);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.withdrawColl(victim, 1e18);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.closeTrove(victim);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.withdrawJpydf(victim, 1e18, type(uint256).max);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.adjustTrove(victim, 1e18, true, 1e18, true, type(uint256).max);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.adjustTrove(victim, 1e18, false, 1000e18, false, 0);
        vm.stopPrank();
        vm.prank(C);
        vm.expectRevert(BorrowerOperations.NewOracleFailureDetected.selector);
        borrowerOperations.openTrove(C, 0, 1000e18, 100_000e18, 0, 0, 5e16, type(uint256).max, address(0), address(0), address(0));

        _freshFx(600_000);
        vm.prank(B);
        borrowerOperations.withdrawJpydf(victim, 1e18, type(uint256).max);
        (, bool reopened) = proxy.fetchRedemptionPrice();
        assertFalse(reopened);
    }

    function test_SafeAddAndRepayNeverCallUnavailableOracle() public {
        uint256 debt = getTroveEntireDebt(victim);
        uint256 coll = getTroveEntireColl(victim);
        vm.mockCallRevert(address(proxy), abi.encodeWithSelector(IPriceFeed.fetchPrice.selector), "oracle unavailable");
        vm.startPrank(B);
        borrowerOperations.addColl(victim, 1e18);
        borrowerOperations.repayJpydf(victim, 10e18);
        borrowerOperations.adjustTrove(victim, 1e18, true, 10e18, false, 0);
        vm.stopPrank();
        assertEq(getTroveEntireColl(victim), coll + 2e18);
        assertEq(getTroveEntireDebt(victim), debt - 20e18);
    }

    function test_54hStopsLiquidationAndSafeActionsRemainAvailable() public {
        _ageAtVictimICR(54 hours - 1, MCR - 0.005e18);
        vm.warp(anchor + 54 hours);
        usd.setUpdatedAt(block.timestamp);
        (, bool failed) = proxy.fetchPrice();
        assertTrue(failed);
        assertTrue(borrowerOperations.isOracleFailureShutdown());
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.active));
        vm.startPrank(B);
        borrowerOperations.addColl(victim, 1);
        borrowerOperations.repayJpydf(victim, 1);
        vm.stopPrank();
        assertFalse(borrowerOperations.hasBeenShutDown());
        _freshFx(int256(provider.lastGoodJpyRate() / 1e10));
        assertTrue(borrowerOperations.isOracleFailureShutdown(), "owner pause stays latched");
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.closedByLiquidation));
    }

    function test_OtherInputFailureStopsLiquidationInsideGraceWindow() public {
        _ageAtVictimICR(30 hours, MCR - 0.005e18);
        usd.setPrice(0);
        (, bool failed) = proxy.fetchPrice();
        assertTrue(failed);
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.active));
    }

    function test_StaleShutdownWaitsForFreshFxAndDebtKeepsAccruing() public {
        uint256 q = borrowerOperations.getEntireBranchColl() * 1e26
            / (borrowerOperations.getEntireBranchDebt() * (SCR - 0.005e18));
        _freshFx(int256(q));
        vm.warp(anchor + 30 hours);
        usd.setUpdatedAt(block.timestamp);
        borrowerOperations.shutdown();
        assertFalse(borrowerOperations.hasBeenShutDown());
        uint256 debtAt30h = borrowerOperations.getEntireBranchDebt();
        uint256[] memory ids = new uint256[](1);
        ids[0] = victim;
        vm.prank(B);
        vm.expectRevert(TroveManager.NotShutDown.selector);
        troveManager.urgentRedemption(1e18, ids, 0);

        vm.warp(anchor + 53 hours);
        usd.setUpdatedAt(block.timestamp);
        assertGt(borrowerOperations.getEntireBranchDebt(), debtAt30h);
        borrowerOperations.shutdown();
        assertEq(troveManager.shutdownTime(), 0);
        _freshFx(int256(q));
        borrowerOperations.shutdown();
        assertTrue(borrowerOperations.hasBeenShutDown());
        assertEq(troveManager.shutdownTime(), block.timestamp);
        vm.prank(B);
        troveManager.urgentRedemption(1e18, ids, 0);
    }

    function test_FreshFxAvoidsWrongfulPermanentShutdown() public {
        uint256 q = borrowerOperations.getEntireBranchColl() * 1e26
            / (borrowerOperations.getEntireBranchDebt() * (SCR - 0.005e18));
        _freshFx(int256(q));
        vm.warp(anchor + 30 hours);
        usd.setUpdatedAt(block.timestamp);
        borrowerOperations.shutdown();
        assertFalse(borrowerOperations.hasBeenShutDown());
        _freshFx(int256(q * 99 / 100));
        vm.expectRevert(BorrowerOperations.TCRNotBelowSCR.selector);
        borrowerOperations.shutdown();
        assertFalse(borrowerOperations.hasBeenShutDown());
    }

    function test_PausingAt30hCanLeaveUncoveredDebtDuringGraceWindow() public {
        uint256 stale = _ageAtVictimICR(30 hours, MCR - 0.005e18);
        assertGt(troveManager.getCurrentICR(victim, stale), 1e18);
        uint256 snapshot = vm.snapshotState();
        _liquidate();
        assertEq(uint256(troveManager.getTroveStatus(victim)), uint256(ITroveManager.Status.closedByLiquidation));
        assertTrue(vm.revertToState(snapshot));
        // Synthetic 15% FX stress over the extra 24h, not an observed move.
        vm.warp(anchor + 54 hours);
        usd.setUpdatedAt(block.timestamp);
        uint256 fresh = _freshFx(int256(provider.lastGoodJpyRate() / 1e10 * 115 / 100));
        assertLt(troveManager.getCurrentICR(victim, fresh), 1e18);
        emit log_named_uint("uncovered JPYdf before liquidation", getTroveEntireDebt(victim) - getTroveEntireColl(victim) * fresh / 1e18);
    }
}
