// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DevTestSetup} from "./TestContracts/DevTestSetup.sol";
import {TroveChange} from "../src/Types/TroveChange.sol";
import {console2} from "forge-std/console2.sol";

// External audit Gas 02 evidence: moving the shutdown return ahead of the
// upfront-fee assertion saves shutdown-path gas but changes malformed-input
// behavior from Panic(0x01) to a successful zero return.
contract ExternalAuditGas02ShutdownAssertTest is DevTestSetup {
    function test_ShutdownZeroFeeReturnsZero() external {
        _shutdownActivePool();

        TroveChange memory change;
        uint256 gasBefore = gasleft();
        uint256 result = activePool.getNewApproxAvgInterestRateFromTroveChange(change);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("shutdown valid-call gas", gasUsed);
        assertEq(result, 0, "shutdown result");
    }

    function test_ShutdownNonzeroUpfrontFeeStillPanics() external {
        _shutdownActivePool();

        TroveChange memory change;
        change.upfrontFee = 1;

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x01));
        activePool.getNewApproxAvgInterestRateFromTroveChange(change);
    }

    function _shutdownActivePool() internal {
        vm.prank(address(troveManager));
        activePool.setShutdownFlag();
        assertTrue(activePool.hasBeenShutDown(), "shutdown precondition");
    }
}
