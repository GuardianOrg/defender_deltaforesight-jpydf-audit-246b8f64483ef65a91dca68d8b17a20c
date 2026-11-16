// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {AddressesRegistry} from "src/AddressesRegistry.sol";
import {SortedTroves} from "src/SortedTroves.sol";
import {IAddressesRegistry} from "src/Interfaces/IAddressesRegistry.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";

contract SortedTrovesConstructorVerification is Test {
    event TroveManagerAddressChanged(address _troveManagerAddress);
    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);

    function testConstructorWiringEventsAndSentinel() public {
        AddressesRegistry registry =
            new AddressesRegistry(address(this), 150e16, 110e16, 10e16, 110e16, 5e16, 10e16, address(0));
        IAddressesRegistry.AddressVars memory vars;
        vars.borrowerOperations = IBorrowerOperations(address(this));
        vars.troveManager = ITroveManager(address(this));
        registry.setAddresses(vars);

        vm.expectEmit();
        emit TroveManagerAddressChanged(address(this));
        vm.expectEmit();
        emit BorrowerOperationsAddressChanged(address(this));
        SortedTroves sortedTroves = new SortedTroves(registry);

        assertEq(sortedTroves.NAME(), "SortedTroves", "contract name");
        assertEq(address(sortedTroves.troveManager()), address(this), "TroveManager binding");
        assertEq(sortedTroves.borrowerOperationsAddress(), address(this), "BorrowerOperations binding");
        assertEq(sortedTroves.getSize(), 0, "initial size");
        assertEq(sortedTroves.getFirst(), 0, "initial first sentinel");
        assertEq(sortedTroves.getLast(), 0, "initial last sentinel");
        assertTrue(sortedTroves.isEmpty(), "initially empty");
    }

    function testWriteCallerGuardsAndNodeExistenceCoherence() public {
        SortedTroves sortedTroves = _deployWithThisAsAuthorizedCaller();
        address outsider = makeAddr("sorted-troves-outsider");

        vm.prank(outsider);
        vm.expectRevert("SortedTroves: Caller is not BorrowerOperations");
        sortedTroves.insert(1, 5e16, 0, 0);

        vm.prank(outsider);
        vm.expectRevert("SortedTroves: Caller is not BorrowerOperations nor TroveManager");
        sortedTroves.remove(1);

        sortedTroves.insert(1, 5e16, 0, 0);
        assertTrue(sortedTroves.contains(1), "inserted node exists");
        assertEq(sortedTroves.getSize(), 1, "insert increments size");
        assertEq(sortedTroves.getFirst(), 1, "inserted node is head");
        assertEq(sortedTroves.getLast(), 1, "inserted node is tail");

        sortedTroves.remove(1);
        assertFalse(sortedTroves.contains(1), "removed node no longer exists");
        assertEq(sortedTroves.getSize(), 0, "remove decrements size");
        assertEq(sortedTroves.getFirst(), 0, "remove restores head sentinel");
        assertEq(sortedTroves.getLast(), 0, "remove restores tail sentinel");
    }

    function testInvalidOperationRevertStrings() public {
        SortedTroves sortedTroves = _deployWithThisAsAuthorizedCaller();

        vm.expectRevert("SortedTroves: _id cannot be the root node's ID");
        sortedTroves.insert(0, 5e16, 0, 0);

        sortedTroves.insert(1, 5e16, 0, 0);

        vm.expectRevert("SortedTroves: List already contains the node");
        sortedTroves.insert(1, 5e16, 0, 0);

        vm.expectRevert("SortedTroves: List does not contain the id");
        sortedTroves.remove(2);

        vm.expectRevert("SortedTroves: List does not contain the id");
        sortedTroves.reInsert(2, 4e16, 0, 0);
    }

    function _deployWithThisAsAuthorizedCaller() internal returns (SortedTroves sortedTroves) {
        AddressesRegistry registry =
            new AddressesRegistry(address(this), 150e16, 110e16, 10e16, 110e16, 5e16, 10e16, address(0));
        IAddressesRegistry.AddressVars memory vars;
        vars.borrowerOperations = IBorrowerOperations(address(this));
        vars.troveManager = ITroveManager(address(this));
        registry.setAddresses(vars);
        sortedTroves = new SortedTroves(registry);
    }
}
