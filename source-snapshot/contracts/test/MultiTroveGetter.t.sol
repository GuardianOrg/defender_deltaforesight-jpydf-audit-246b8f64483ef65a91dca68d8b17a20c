// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/LiquidationCandidateGetter.sol";
import "src/Interfaces/ICollateralRegistry.sol";
import "src/Interfaces/ILiquidationCandidateGetter.sol";
import "src/Interfaces/ITroveManager.sol";
import "./TestContracts/DevTestSetup.sol";

contract LiquidationCandidateGetterTest is DevTestSetup {
    LiquidationCandidateGetter internal getter;

    function setUp() public override {
        super.setUp();
        getter = new LiquidationCandidateGetter(collateralRegistry);
    }

    function test_GetLiquidationCandidates_ReturnsUndercollateralizedTroves() public {
        _openCandidateFixture();
        uint256 price = priceFeed.getPrice() * 99 / 100;
        priceFeed.setPrice(price);

        (ILiquidationCandidateGetter.LiquidationCandidate[] memory candidates, uint256 nextId) =
            getter.getLiquidationCandidates(0, 0, 10, price, MCR);

        assertEq(candidates.length, 2, "candidate count");
        assertEq(nextId, 0, "scan completed");
        for (uint256 i = 0; i < candidates.length; ++i) {
            assertLt(candidates[i].ICR, MCR, "candidate must be below MCR");
            assertEq(candidates[i].entireDebt, troveManager.getTroveEntireDebt(candidates[i].id), "debt");
            assertEq(candidates[i].entireColl, troveManager.getTroveEntireColl(candidates[i].id), "coll");
        }
    }

    function test_GetLiquidationCandidates_PaginatesBySortedListCursor() public {
        (uint256 safeId, uint256 firstCandidateId,) = _openCandidateFixture();
        uint256 price = priceFeed.getPrice() * 99 / 100;
        priceFeed.setPrice(price);

        (ILiquidationCandidateGetter.LiquidationCandidate[] memory firstPage, uint256 nextId) =
            getter.getLiquidationCandidates(0, 0, 1, price, MCR);
        assertEq(firstPage.length, 0, "safe trove skipped");
        assertEq(sortedTroves.getFirst(), safeId, "fixture order");
        assertEq(nextId, firstCandidateId, "cursor after safe trove");

        (ILiquidationCandidateGetter.LiquidationCandidate[] memory secondPage,) =
            getter.getLiquidationCandidates(0, nextId, 1, price, MCR);
        assertEq(secondPage.length, 1, "second page candidate count");
        assertEq(secondPage[0].id, firstCandidateId, "candidate id");
        assertLt(secondPage[0].ICR, MCR, "candidate must be below MCR");
    }

    function test_GetLiquidationCandidatesWithLastZombie_AppendsLiquidatableZombie() public {
        (,, ABCDEF memory troveIDs) = _setupForRedemptionAscendingInterest();
        _redeemAndCreateZombieTrovesAAndB(troveIDs);

        uint256 zombieId = troveManager.lastZombieTroveId();
        assertEq(zombieId, troveIDs.B, "fixture zombie");
        assertFalse(sortedTroves.contains(zombieId), "zombie is not in sorted list");

        uint256 zombieDebt = troveManager.getTroveEntireDebt(zombieId);
        uint256 zombieColl = troveManager.getTroveEntireColl(zombieId);
        uint256 price = zombieDebt * MCR / zombieColl / 2;
        priceFeed.setPrice(price);

        (bool found, ILiquidationCandidateGetter.LiquidationCandidate memory zombieCandidate) =
            getter.getLastZombieLiquidationCandidate(0, price, MCR);
        assertTrue(found, "last zombie should be liquidatable");
        assertEq(zombieCandidate.id, zombieId, "zombie id");
        assertLt(zombieCandidate.ICR, MCR, "zombie must be below MCR");
        assertEq(zombieCandidate.entireDebt, troveManager.getTroveEntireDebt(zombieId), "zombie debt");
        assertEq(zombieCandidate.entireColl, troveManager.getTroveEntireColl(zombieId), "zombie coll");
        assertGt(zombieCandidate.entireDebt, 0, "zombie debt should be populated");
        assertGt(zombieCandidate.entireColl, 0, "zombie coll should be populated");

        (ILiquidationCandidateGetter.LiquidationCandidate[] memory candidates, uint256 nextId, bool includedLastZombie)
        = getter.getLiquidationCandidatesWithLastZombie(0, 0, 0, price, MCR, true);

        assertTrue(includedLastZombie, "zombie included");
        assertEq(candidates.length, 1, "only zombie candidate");
        assertEq(candidates[0].id, zombieId, "appended zombie id");
        assertEq(nextId, sortedTroves.getFirst(), "zero-iteration cursor remains first sorted trove");
    }

    function test_RevertWhen_CollateralRegistryIsZero() public {
        vm.expectRevert(ILiquidationCandidateGetter.LiquidationCandidateGetter__InvalidCollateralRegistry.selector);
        new LiquidationCandidateGetter(ICollateralRegistry(address(0)));
    }

    function test_RevertWhen_CollateralIndexIsInvalid() public {
        LiquidationCandidateGetter zeroManagerGetter =
            new LiquidationCandidateGetter(ICollateralRegistry(address(new ZeroTroveManagerRegistry())));
        uint256 price = priceFeed.getPrice();

        vm.expectRevert(ILiquidationCandidateGetter.LiquidationCandidateGetter__InvalidCollateralIndex.selector);
        zeroManagerGetter.getLiquidationCandidates(0, 0, 10, price, MCR);

        vm.expectRevert(ILiquidationCandidateGetter.LiquidationCandidateGetter__InvalidCollateralIndex.selector);
        zeroManagerGetter.getLastZombieLiquidationCandidate(0, price, MCR);
    }

    function _openCandidateFixture()
        internal
        returns (uint256 safeId, uint256 firstCandidateId, uint256 secondCandidateId)
    {
        // SortedTroves is ordered by descending interest rate. The first page
        // intentionally starts with a safe trove to verify cursor behaviour.
        (safeId,) = openTroveWithExactICRAndDebt(B, 0, 2 * CCR, 500000 ether, 0.03 ether);
        (firstCandidateId,) = openTroveWithExactICRAndDebt(A, 0, MCR, 500000 ether, 0.02 ether);
        (secondCandidateId,) = openTroveWithExactICRAndDebt(C, 0, MCR, 500000 ether, 0.01 ether);
    }
}

contract ZeroTroveManagerRegistry {
    function getTroveManager(uint256) external pure returns (ITroveManager) {
        return ITroveManager(address(0));
    }
}
