// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {PriceFeedProxy} from "../src/PriceFeeds/PriceFeedProxy.sol";
import "./TestContracts/FreshJpyProvenance.sol";

// Source whose live fetch reverts, but lastGoodPrice() is valid (so the proxy is constructible
// and the runtime fail-safe catch path is exercised).
contract _AlarmRevertingSource is FreshJpyProvenance {
    uint256 public lastGoodPrice = 1e18;

    function fetchPrice() external returns (uint256, bool) {
        revert("down");
    }

    function fetchRedemptionPrice() external returns (uint256, bool) {
        revert("down");
    }

    function fetchUrgentRedemptionPrice() external pure returns (uint256, bool) {
        return (1e18, false);
    }
}

// BorrowerOperations that reverts on shutdownFromOracleFailure -- simulates a deploy miswire
// (this proxy is not the BO's registered priceFeed -> CallerNotPriceFeed).
contract _AlarmRevertingBO {
    error CallerNotPriceFeed();

    function shutdownFromOracleFailure() external pure {
        revert CallerNotPriceFeed();
    }
}

// Correctly-wired BO that accepts the shutdown call.
contract _AlarmOkBO {
    bool public called;

    function shutdownFromOracleFailure() external {
        called = true;
    }
}

contract PriceFeedProxyShutdownAlarmTest is Test {
    bytes32 constant SIG = keccak256("ShutdownCallReverted(address,address)");

    function test_miswire_shutdownRevert_emitsAlarm_servesLastGood_noRevert() public {
        _AlarmRevertingSource src = new _AlarmRevertingSource();
        _AlarmRevertingBO bo = new _AlarmRevertingBO();
        PriceFeedProxy proxy = new PriceFeedProxy(address(src), address(this), address(bo));

        vm.recordLogs();
        (uint256 p, bool failed) = proxy.fetchPrice();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == SIG) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(bo));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(src));
            }
        }
        assertTrue(found, "ShutdownCallReverted not emitted on miswire");
        assertEq(p, 1e18, "should still serve cached lastGoodPrice");
        assertTrue(failed, "oracleFailure flag should be true");
    }

    function test_correctWire_noAlarm_andShutdownCalled() public {
        _AlarmRevertingSource src = new _AlarmRevertingSource();
        _AlarmOkBO bo = new _AlarmOkBO();
        PriceFeedProxy proxy = new PriceFeedProxy(address(src), address(this), address(bo));

        vm.recordLogs();
        proxy.fetchPrice();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != SIG, "alarm must NOT fire on correct wiring");
        }
        assertTrue(bo.called(), "shutdown should have been called");
    }
}
