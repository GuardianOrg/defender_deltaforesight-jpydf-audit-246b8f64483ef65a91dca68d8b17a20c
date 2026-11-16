// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "./TestContracts/Deployment.t.sol";

contract GuardianL03GasCapTest is Test {
    TestDeployer internal deployer;
    TestDeployer.LiquityContractsDev internal branch;
    IJpydfToken internal debtToken;
    IWETH internal weth;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function _deploy(uint256 cap) internal {
        vm.warp(600);
        deployer = new TestDeployer();
        deployer.setCollGasCompensationCap(cap);
        TestDeployer.TroveManagerParams[] memory params = new TestDeployer.TroveManagerParams[](2);
        params[0] = TestDeployer.TroveManagerParams(150e16, 110e16, 10e16, 110e16, 5e16, 10e16);
        params[1] = params[0];
        TestDeployer.LiquityContractsDev[] memory branches;
        (branches,, debtToken,,, weth,) = deployer.deployAndConnectContractsMultiColl(params);
        branch = branches[1]; // Separate 18-decimal collateral from the WETH gas reserve.
        branch.priceFeed.setPrice(2000e18);
    }

    function _open(address owner, uint256 collateral, uint256 debt) internal returns (uint256) {
        deal(address(branch.collToken), owner, collateral);
        deal(address(weth), owner, weth.balanceOf(owner) + ETH_GAS_COMPENSATION);
        vm.startPrank(owner);
        branch.collToken.approve(address(branch.borrowerOperations), type(uint256).max);
        weth.approve(address(branch.borrowerOperations), type(uint256).max);
        uint256 id = branch.borrowerOperations
            .openTrove(
                owner,
                0,
                collateral,
                debt,
                0,
                0,
                MIN_ANNUAL_INTEREST_RATE,
                type(uint256).max,
                address(0),
                address(0),
                address(0)
            );
        vm.stopPrank();
        return id;
    }

    struct LiquidationValues {
        uint256 collateral;
        uint256 requestedDebt;
        uint256 id;
        uint256 debt;
        uint256 deposit;
        uint256 spDebtBefore;
        uint256 price;
        uint256 offsetDebt;
        uint256 spPortion;
        uint256 reward;
        uint256 spCollateral;
        uint256 surplus;
        uint256 redistributed;
    }

    function _checkLiquidation(uint256 cap, bool fullOffset) internal {
        LiquidationValues memory v;
        _deploy(cap);
        v.collateral = cap * 400; // 0.5% exceeds the branch cap.
        v.requestedDebt = v.collateral * 1000;
        v.id = _open(alice, v.collateral, v.requestedDebt);
        _open(bob, v.collateral * 8, v.requestedDebt * 2);
        v.debt = branch.troveManager.getTroveEntireDebt(v.id);
        v.deposit = fullOffset ? v.requestedDebt * 2 : v.debt / 4 + MIN_JPYDF_IN_SP;
        vm.startPrank(bob);
        debtToken.approve(address(branch.stabilityPool), v.deposit);
        branch.stabilityPool.provideToSP(v.deposit, false);
        vm.stopPrank();
        v.spDebtBefore = branch.stabilityPool.getTotalJpydfDeposits();
        v.price = 1100e18 - 1;
        branch.priceFeed.setPrice(v.price);
        assertLt(branch.troveManager.getCurrentICR(v.id, v.price), branch.addressesRegistry.MCR());
        assertGt(branch.troveManager.getTCR(v.price), branch.addressesRegistry.CCR());
        v.offsetDebt = fullOffset ? v.debt : v.debt / 4;
        v.spPortion = v.collateral * v.offsetDebt / v.debt;
        v.reward = v.spPortion / COLL_GAS_COMPENSATION_DIVISOR;
        if (v.reward > cap) v.reward = cap;
        v.spCollateral = v.offsetDebt * (1e18 + branch.addressesRegistry.LIQUIDATION_PENALTY_SP()) / v.price;
        if (v.spCollateral > v.spPortion - v.reward) v.spCollateral = v.spPortion - v.reward;

        branch.troveManager.liquidate(v.id);

        v.surplus = branch.pools.collSurplusPool.getCollateral(alice);
        v.redistributed = branch.pools.defaultPool.getCollBalance();
        assertEq(branch.collToken.balanceOf(address(this)), v.reward, "liquidator collateral reward");
        assertEq(weth.balanceOf(address(this)), ETH_GAS_COMPENSATION, "fixed WETH reward");
        assertEq(branch.stabilityPool.getCollBalance(), v.spCollateral, "SP penalty allocation");
        assertEq(v.spDebtBefore - branch.stabilityPool.getTotalJpydfDeposits(), v.offsetDebt, "offset debt");
        assertEq(branch.pools.defaultPool.getJpydfDebt(), v.debt - v.offsetDebt, "redistributed debt");
        assertEq(v.reward + v.spCollateral + v.redistributed + v.surplus, v.collateral, "collateral conservation");
        if (fullOffset) {
            assertEq(v.reward, cap);
            assertEq(v.surplus, v.collateral - cap - v.spCollateral, "borrower surplus");
            assertGt(v.surplus, 0);
        } else {
            assertLt(v.reward, cap, "partial-offset reward remains below cap");
        }
    }

    function test_DwstethFullOffset() external {
        _checkLiquidation(2 ether, true);
    }

    function test_DusdcFullOffset() external {
        _checkLiquidation(1000 ether, true);
    }

    function test_DwstethPartialOffset() external {
        _checkLiquidation(2 ether, false);
    }

    function test_DusdcPartialOffset() external {
        _checkLiquidation(1000 ether, false);
    }

    function testFuzz_CapAndProportionalOffset(uint256 collateral, bool dwsteth) external {
        uint256 cap = dwsteth ? 2 ether : 1000 ether;
        _deploy(cap);
        collateral = bound(collateral, 0, 1e30);
        assertEq(branch.troveManager.getCollGasCompensation(0), 0);
        assertEq(branch.troveManager.getCollGasCompensation(cap * 200 - 1), cap - 1);
        assertEq(branch.troveManager.getCollGasCompensation(cap * 200), cap);
        assertEq(branch.troveManager.getCollGasCompensation(cap * 200 + 1), cap);
        uint256 expected = collateral / 200;
        if (expected > cap) expected = cap;
        assertEq(branch.troveManager.getCollGasCompensation(collateral), expected);
        assertEq(branch.troveManager.getCollGasCompensation(collateral, 100, 0), 0);
        expected = (collateral / 2) / 200;
        if (expected > cap) expected = cap;
        assertEq(branch.troveManager.getCollGasCompensation(collateral, 100, 50), expected);
        deployer.setCollGasCompensationCap(cap == 2 ether ? 1000 ether : 2 ether);
        assertEq(branch.troveManager.getCollGasCompensation(cap * 400), cap, "deployed cap remains fixed");
    }

    function test_RejectsZeroOrExcessiveCap() external {
        _deploy(2 ether);
        new TroveManager(branch.addressesRegistry, 1); // Valid boundary is a constructor positive control.
        new TroveManager(branch.addressesRegistry, 1000 ether);
        vm.expectRevert();
        new TroveManager(branch.addressesRegistry, 0);
        vm.expectRevert();
        new TroveManager(branch.addressesRegistry, 1000 ether + 1);
    }
}
