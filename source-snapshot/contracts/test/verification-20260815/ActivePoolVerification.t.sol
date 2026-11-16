// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ActivePool} from "src/ActivePool.sol";
import "src/Dependencies/Constants.sol";
import {TroveChange} from "src/Types/TroveChange.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

/// @notice Focused evidence for every externally callable ActivePool surface.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract ActivePoolVerification is DevTestSetup {
    event CollTokenAddressChanged(address _newCollTokenAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event ActivePoolCollBalanceUpdated(uint256 _collBalance);
    event ActivePoolAggRecordedDebtUpdated(uint256 _aggRecordedDebt);
    event ActivePoolAggWeightedDebtSumUpdated(uint256 _aggWeightedDebtSum);
    event ActivePoolAggBatchManagementFeesUpdated(uint256 _aggBatchManagementFees);
    event ActivePoolAggWeightedBatchManagementFeeSumUpdated(uint256 _aggWeightedBatchManagementFeeSum);

    function testConstructorWiringApprovalAndEvents() external {
        vm.recordLogs();
        ActivePool freshPool = new ActivePool(addressesRegistry);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(freshPool.collToken()), address(collToken));
        assertEq(freshPool.borrowerOperationsAddress(), address(borrowerOperations));
        assertEq(freshPool.troveManagerAddress(), address(troveManager));
        assertEq(freshPool.defaultPoolAddress(), address(defaultPool));
        assertEq(address(freshPool.stabilityPool()), address(stabilityPool));
        assertEq(address(freshPool.interestRouter()), address(mockInterestRouter));
        assertEq(collToken.allowance(address(freshPool), address(defaultPool)), type(uint256).max);

        assertEq(logs.length, 6);
        assertEq(logs[0].emitter, address(freshPool));
        assertEq(logs[0].topics[0], keccak256("CollTokenAddressChanged(address)"));
        assertEq(abi.decode(logs[0].data, (address)), address(collToken));
        assertEq(logs[1].topics[0], keccak256("BorrowerOperationsAddressChanged(address)"));
        assertEq(abi.decode(logs[1].data, (address)), address(borrowerOperations));
        assertEq(logs[2].topics[0], keccak256("TroveManagerAddressChanged(address)"));
        assertEq(abi.decode(logs[2].data, (address)), address(troveManager));
        assertEq(logs[3].topics[0], keccak256("StabilityPoolAddressChanged(address)"));
        assertEq(abi.decode(logs[3].data, (address)), address(stabilityPool));
        assertEq(logs[4].topics[0], keccak256("DefaultPoolAddressChanged(address)"));
        assertEq(abi.decode(logs[4].data, (address)), address(defaultPool));
        assertEq(logs[5].emitter, address(collToken));
        assertEq(logs[5].topics[0], keccak256("Approval(address,address,uint256)"));
        assertEq(address(uint160(uint256(logs[5].topics[1]))), address(freshPool));
        assertEq(address(uint160(uint256(logs[5].topics[2]))), address(defaultPool));
        assertEq(abi.decode(logs[5].data, (uint256)), type(uint256).max);
    }

    function testCollateralTransferSurfacesAccountAndEmit() external {
        uint256 received = 10 ether;
        uint256 sentToUser = 3 ether;
        uint256 sentToDefaultPool = 4 ether;
        uint256 directlyAccounted = 2 ether;

        deal(address(collToken), address(borrowerOperations), received);
        vm.startPrank(address(borrowerOperations));
        collToken.approve(address(activePool), received);
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolCollBalanceUpdated(received);
        activePool.receiveColl(received);
        vm.stopPrank();
        assertEq(activePool.getCollBalance(), received);
        assertEq(collToken.balanceOf(address(activePool)), received);

        uint256 userBalanceBefore = collToken.balanceOf(A);
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolCollBalanceUpdated(received - sentToUser);
        vm.prank(address(borrowerOperations));
        activePool.sendColl(A, sentToUser);
        assertEq(activePool.getCollBalance(), received - sentToUser);
        assertEq(collToken.balanceOf(A), userBalanceBefore + sentToUser);

        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolCollBalanceUpdated(received - sentToUser - sentToDefaultPool);
        vm.prank(address(troveManager));
        activePool.sendCollToDefaultPool(sentToDefaultPool);
        assertEq(activePool.getCollBalance(), received - sentToUser - sentToDefaultPool);
        assertEq(defaultPool.getCollBalance(), sentToDefaultPool);
        assertEq(collToken.balanceOf(address(defaultPool)), sentToDefaultPool);

        deal(
            address(collToken),
            address(activePool),
            received - sentToUser - sentToDefaultPool + directlyAccounted,
            true
        );
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolCollBalanceUpdated(received - sentToUser - sentToDefaultPool + directlyAccounted);
        vm.prank(address(borrowerOperations));
        activePool.accountForReceivedColl(directlyAccounted);
        assertEq(activePool.getCollBalance(), received - sentToUser - sentToDefaultPool + directlyAccounted);
        assertEq(collToken.balanceOf(address(activePool)), received - sentToUser - sentToDefaultPool + directlyAccounted);
    }

    function testInterestDebtAndApproximateRateViews() external {
        priceFeed.setPrice(2000e18);
        openTroveNoHints100pct(A, 300 ether, 300000e18, 25e16);
        openTroveNoHints100pct(B, 300 ether, 300000e18, 75e16);
        vm.warp(block.timestamp + 1 days);

        uint256 pendingInterest = activePool.calcPendingAggInterest();
        assertGt(pendingInterest, 0);
        assertEq(activePool.calcPendingSPYield(), pendingInterest * SP_YIELD_SPLIT / DECIMAL_PRECISION);
        assertEq(
            activePool.getJpydfDebt(),
            activePool.aggRecordedDebt() + pendingInterest + activePool.aggBatchManagementFees()
                + activePool.calcPendingAggBatchManagementFee()
        );

        TroveChange memory noChange;
        assertEq(
            activePool.getNewApproxAvgInterestRateFromTroveChange(noChange),
            activePool.aggWeightedDebtSum() / (activePool.aggRecordedDebt() + pendingInterest)
        );
    }

    function testBatchFeeViewAndAccountingEvents() external {
        openTroveAndJoinBatchManager(A, 15000e18, 750000e18, B, 5e16);
        vm.warp(block.timestamp + 10 days);
        assertGt(activePool.calcPendingAggBatchManagementFee(), 0);

        TroveChange memory noChange;
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggRecordedDebtUpdated(activePool.aggRecordedDebt());
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggBatchManagementFeesUpdated(activePool.calcPendingAggBatchManagementFee());
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggWeightedBatchManagementFeeSumUpdated(activePool.aggWeightedBatchManagementFeeSum());
        vm.prank(address(troveManager));
        activePool.mintBatchManagementFeeAndAccountForChange(noChange, B);
        assertEq(activePool.calcPendingAggBatchManagementFee(), 0);
    }

    function testAggregateAccountingEventsAndCallerGuards() external {
        TroveChange memory noChange;

        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggRecordedDebtUpdated(0);
        vm.prank(address(stabilityPool));
        activePool.mintAggInterest();

        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggRecordedDebtUpdated(0);
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggWeightedDebtSumUpdated(0);
        vm.prank(address(borrowerOperations));
        activePool.mintAggInterestAndAccountForTroveChange(noChange, address(0));

        vm.expectRevert(bytes("ActivePool: Caller is neither BorrowerOperations nor TroveManager nor StabilityPool"));
        activePool.sendColl(A, 0);
        vm.expectRevert(bytes("ActivePool: Caller is not TroveManager"));
        activePool.sendCollToDefaultPool(0);
        vm.expectRevert(bytes("ActivePool: Caller is neither BO nor Default Pool"));
        activePool.receiveColl(0);
        vm.expectRevert(bytes("ActivePool: Caller is neither BO nor Default Pool"));
        activePool.accountForReceivedColl(0);
        vm.expectRevert(bytes("ActivePool: Caller is not BorrowerOperations nor StabilityPool"));
        activePool.mintAggInterest();
        vm.expectRevert(bytes("ActivePool: Caller is neither BorrowerOperations nor TroveManager"));
        activePool.mintAggInterestAndAccountForTroveChange(noChange, address(0));
        vm.expectRevert(bytes("ActivePool: Caller is not TroveManager"));
        activePool.mintBatchManagementFeeAndAccountForChange(noChange, address(0));
        vm.expectRevert(bytes("ActivePool: Caller is not TroveManager"));
        activePool.setShutdownFlag();
    }

    function testShutdownFreezesAggregateInterest() external {
        priceFeed.setPrice(2000e18);
        openTroveNoHints100pct(A, 300 ether, 300000e18, 25e16);
        openTroveAndJoinBatchManager(B, 15000e18, 750000e18, C, 5e16);
        vm.warp(block.timestamp + 1 days);
        assertGt(activePool.calcPendingAggInterest(), 0);
        assertGt(activePool.calcPendingAggBatchManagementFee(), 0);

        vm.prank(address(troveManager));
        activePool.setShutdownFlag();
        assertTrue(activePool.hasBeenShutDown());
        assertEq(activePool.shutdownTime(), block.timestamp);
        assertEq(activePool.calcPendingAggInterest(), 0);
        uint256 frozenBatchManagementFee = activePool.calcPendingAggBatchManagementFee();
        vm.warp(block.timestamp + 1 days);
        assertEq(activePool.calcPendingAggInterest(), 0);
        assertEq(activePool.calcPendingAggBatchManagementFee(), frozenBatchManagementFee);
        assertEq(activePool.getNewApproxAvgInterestRateFromTroveChange(TroveChange(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), 0);
    }

    function testCollateralAccountingCannotUnderflow() external {
        vm.prank(address(borrowerOperations));
        vm.expectRevert();
        activePool.sendColl(A, 1);
    }
}
