// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "src/GasPool.sol";
import "src/Dependencies/Constants.sol";
import "src/Interfaces/IBorrowerOperations.sol";
import "src/Interfaces/IAddressesRegistry.sol";
import "src/Interfaces/ITroveManager.sol";
import "src/Interfaces/IWETH.sol";

import "./TestContracts/WETH.sol";

contract GasPoolRegistryStub {
    IWETH private immutable _weth;
    address private immutable _borrowerOperations;
    address private immutable _troveManager;

    constructor(IWETH weth_, address borrowerOperations_, address troveManager_) {
        _weth = weth_;
        _borrowerOperations = borrowerOperations_;
        _troveManager = troveManager_;
    }

    function WETH() external view returns (IWETH) {
        return _weth;
    }

    function borrowerOperations() external view returns (IBorrowerOperations) {
        return IBorrowerOperations(_borrowerOperations);
    }

    function troveManager() external view returns (ITroveManager) {
        return ITroveManager(_troveManager);
    }
}

contract GasPoolTest is Test {
    WETH9 private weth;
    address private borrowerOperations;
    address private troveManager;
    address private attacker;
    address private liquidator;

    function setUp() public {
        weth = new WETH9();
        borrowerOperations = makeAddr("borrowerOperations");
        troveManager = makeAddr("troveManager");
        attacker = makeAddr("attacker");
        liquidator = makeAddr("liquidator");
    }

    function test_ConstructorApprovesOnlyCoreCompensationCallers() public {
        GasPool gasPool = _deployGasPool();

        assertEq(weth.allowance(address(gasPool), borrowerOperations), type(uint256).max, "BO allowance");
        assertEq(weth.allowance(address(gasPool), troveManager), type(uint256).max, "TM allowance");
        assertEq(weth.allowance(address(gasPool), attacker), 0, "attacker allowance");
    }

    function test_UnprivilegedCallerCannotPullGasCompensationWeth() public {
        GasPool gasPool = _deployGasPool();
        _fundGasPool(gasPool, ETH_GAS_COMPENSATION);

        vm.prank(attacker);
        vm.expectRevert();
        weth.transferFrom(address(gasPool), attacker, ETH_GAS_COMPENSATION);

        assertEq(weth.balanceOf(address(gasPool)), ETH_GAS_COMPENSATION, "gas pool balance unchanged");
        assertEq(weth.balanceOf(attacker), 0, "attacker received nothing");
    }

    function test_ConfiguredCoreCallerCanUseAllowanceForGasCompensation() public {
        GasPool gasPool = _deployGasPool();
        _fundGasPool(gasPool, ETH_GAS_COMPENSATION);

        vm.prank(troveManager);
        weth.transferFrom(address(gasPool), liquidator, ETH_GAS_COMPENSATION);

        assertEq(weth.balanceOf(address(gasPool)), 0, "gas pool debited");
        assertEq(weth.balanceOf(liquidator), ETH_GAS_COMPENSATION, "liquidator paid");
    }

    function test_NoExternalFallbackSurface() public {
        GasPool gasPool = _deployGasPool();

        (bool ok,) = address(gasPool).call(abi.encodeWithSignature("approve(address,uint256)", attacker, 1));

        assertFalse(ok, "unknown selector must revert");
        assertEq(weth.allowance(address(gasPool), attacker), 0, "attacker allowance still zero");
    }

    function _deployGasPool() private returns (GasPool gasPool) {
        GasPoolRegistryStub registry = new GasPoolRegistryStub(IWETH(address(weth)), borrowerOperations, troveManager);
        gasPool = new GasPool(IAddressesRegistry(address(registry)));
    }

    function _fundGasPool(GasPool gasPool, uint256 amount) private {
        weth.deposit{value: amount}();
        weth.transfer(address(gasPool), amount);
    }
}
