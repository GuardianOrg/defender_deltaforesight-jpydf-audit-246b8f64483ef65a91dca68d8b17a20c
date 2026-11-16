// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IGovernance as UpstreamIGovernance} from "V2-gov/src/interfaces/IGovernance.sol";
import {IInitiative as UpstreamIInitiative} from "V2-gov/src/interfaces/IInitiative.sol";
import {IInitiative} from "../src/Interfaces/IInitiative.sol";
import {PILAllocator} from "../src/PILAllocator.sol";
import {JpydfToken} from "../src/JpydfToken.sol";
import {MockBridgeAdmin} from "./PILAllocator.t.sol";

/// @notice Mechanical parity check of the DF hook / epoch surface against the vendored
/// upstream `liquity/V2-gov` interfaces in `lib/V2-gov`.
///
/// PILA-INV-007 requires `IInitiative` to match upstream exactly so a Phase-B deployment can
/// reuse the same initiative unmodified, and PILA-FR-002 requires the epoch interface to be
/// upstream-compatible. DF redeclares the hook structs locally instead of importing
/// `IGovernance`, so the parity that matters is at the ABI level: identical selectors, which
/// are derived from the fully expanded tuple signatures. A field reorder or a width change in
/// any of the three structs moves the selector and fails here.
contract PILAInitiativeParityTest is Test {
    // PILA-INV-007: the four upstream hooks, selector-identical.
    function test_InitiativeHookSelectorsMatchUpstream() external pure {
        assertEq(
            IInitiative.onRegisterInitiative.selector,
            UpstreamIInitiative.onRegisterInitiative.selector,
            "onRegisterInitiative"
        );
        assertEq(
            IInitiative.onUnregisterInitiative.selector,
            UpstreamIInitiative.onUnregisterInitiative.selector,
            "onUnregisterInitiative"
        );
        assertEq(
            IInitiative.onAfterAllocateLQTY.selector,
            UpstreamIInitiative.onAfterAllocateLQTY.selector,
            "onAfterAllocateLQTY"
        );
        assertEq(
            IInitiative.onClaimForInitiative.selector,
            UpstreamIInitiative.onClaimForInitiative.selector,
            "onClaimForInitiative"
        );
    }

    /// @dev The DF interface must not grow or shrink relative to upstream either: an extra hook
    /// would still leave the four selectors matching, so pin the canonical signatures too.
    function test_InitiativeHookSignaturesAreCanonical() external pure {
        assertEq(
            IInitiative.onRegisterInitiative.selector,
            bytes4(keccak256("onRegisterInitiative(uint256)")),
            "register sig"
        );
        assertEq(
            IInitiative.onUnregisterInitiative.selector,
            bytes4(keccak256("onUnregisterInitiative(uint256)")),
            "unregister sig"
        );
        assertEq(
            IInitiative.onClaimForInitiative.selector,
            bytes4(keccak256("onClaimForInitiative(uint256,uint256)")),
            "claim sig"
        );
        // UserState (4x uint256), Allocation (5x uint256), InitiativeState (5x uint256).
        assertEq(
            IInitiative.onAfterAllocateLQTY.selector,
            bytes4(
                keccak256(
                    "onAfterAllocateLQTY(uint256,address,(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint256,uint256))"
                )
            ),
            "allocate sig"
        );
    }

    /// PILA-FR-002: the epoch surface answers the upstream selectors. `EPOCH_START` and
    /// `EPOCH_DURATION` are public immutables rather than declared functions, so this calls each
    /// upstream selector against a deployed allocator instead of comparing selector constants.
    function test_EpochInterfaceAnswersUpstreamSelectors() external {
        uint256 epochDuration = 7 days;
        uint256 epochStart = block.timestamp;
        JpydfToken token = new JpydfToken(address(this), address(new MockBridgeAdmin()));
        PILAllocator allocator =
            new PILAllocator(token, epochStart, epochDuration, 1000e18, address(this), address(this));

        assertEq(_callUint(address(allocator), UpstreamIGovernance.EPOCH_START.selector), epochStart, "EPOCH_START");
        assertEq(
            _callUint(address(allocator), UpstreamIGovernance.EPOCH_DURATION.selector), epochDuration, "EPOCH_DURATION"
        );
        assertEq(_callUint(address(allocator), UpstreamIGovernance.epoch.selector), allocator.epoch(), "epoch");
        assertEq(
            _callUint(address(allocator), UpstreamIGovernance.epochStart.selector), allocator.epochStart(), "epochStart"
        );
    }

    function _callUint(address _target, bytes4 _selector) internal view returns (uint256 value) {
        (bool ok, bytes memory ret) = _target.staticcall(abi.encodeWithSelector(_selector));
        require(ok && ret.length == 32, "upstream selector not answered");
        value = abi.decode(ret, (uint256));
    }

    /// @dev Selector parity alone would pass even if epochs were 0-indexed or measured from a
    /// different origin, so pin the upstream semantics: epoch 1 starts at EPOCH_START and each
    /// boundary advances exactly one epoch.
    function test_EpochNumberingFollowsUpstreamSemantics() external {
        uint256 epochDuration = 7 days;
        uint256 epochStart = block.timestamp;
        JpydfToken token = new JpydfToken(address(this), address(new MockBridgeAdmin()));
        PILAllocator allocator =
            new PILAllocator(token, epochStart, epochDuration, 1000e18, address(this), address(this));

        assertEq(allocator.epoch(), 1, "epoch is 1-indexed at the origin");
        assertEq(allocator.epochStart(), epochStart, "first epoch starts at EPOCH_START");

        vm.warp(epochStart + epochDuration - 1);
        assertEq(allocator.epoch(), 1, "still epoch 1 one second before the boundary");

        vm.warp(epochStart + epochDuration);
        assertEq(allocator.epoch(), 2, "boundary advances exactly one epoch");
        assertEq(allocator.epochStart(), epochStart + epochDuration, "epochStart follows the boundary");

        vm.warp(epochStart + epochDuration * 10 + 1);
        assertEq(allocator.epoch(), 11, "epoch count is floor(elapsed / duration) + 1");
    }
}
