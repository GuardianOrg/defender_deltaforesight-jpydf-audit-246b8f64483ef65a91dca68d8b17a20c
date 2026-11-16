// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

interface IPrestoPending {
    function timelock(bytes4 selector) external view returns (uint256);
    function executableAt(bytes memory data) external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function managementFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);
    function managementFeeRecipient() external view returns (address);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function maxRate() external view returns (uint256);
    function forceDeallocatePenalty(address adapter) external view returns (uint256);
}

/// @notice Simulates only already-submitted, matured governance operations.
/// No new proposal, signer key, impersonated curator or live broadcast is used.
contract PrestoPendingExecutionMainnetTest is Test {
    IPrestoPending constant VENUE = IPrestoPending(0x133614490896bc02C774bc3399E4Db1B6D05a2CA);
    address constant ADAPTER = 0xb30dDEb6BbFDEeb1938000223a7A1a4d1935e1BF;
    bytes4 constant PERFORMANCE = 0x70897b23;
    bytes4 constant PENALTY = 0x3e9d2ac7;

    function test_ExecuteMaturedDelayIncreasesFromUnprivilegedCaller() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), vm.envUint("PRESTO_BLOCK"));
        bytes32 beforeHash = _unrelatedState();
        bytes4[2] memory selectors = [PENALTY, PERFORMANCE];
        address executor = makeAddr("unprivileged-executor");
        assertTrue(executor != VENUE.owner() && executor != VENUE.curator());
        for (uint256 i; i < selectors.length; ++i) {
            bytes memory data = abi.encodeWithSignature("increaseTimelock(bytes4,uint256)", selectors[i], 3 days);
            uint256 executableAt = VENUE.executableAt(data);
            assertGt(executableAt, 0, "proposal must exist");
            assertLe(executableAt, block.timestamp, "proposal must be mature");
            assertEq(VENUE.timelock(selectors[i]), 0, "pinned prior delay");
            vm.prank(executor);
            (bool success, bytes memory result) = address(VENUE).call(data);
            assertTrue(success, string(result));
            assertEq(VENUE.timelock(selectors[i]), 3 days);
            assertEq(VENUE.executableAt(data), 0, "proposal consumed");
            vm.prank(executor);
            (bool replay,) = address(VENUE).call(data);
            assertFalse(replay, "replay must fail");
        }
        assertEq(_unrelatedState(), beforeHash, "fees, recipients, roles, assets and penalty unchanged");
        emit log("Both pending delay increases execute permissionlessly; replay rejected.");
    }

    function _unrelatedState() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                VENUE.performanceFee(),
                VENUE.managementFee(),
                VENUE.performanceFeeRecipient(),
                VENUE.managementFeeRecipient(),
                VENUE.owner(),
                VENUE.curator(),
                VENUE.totalSupply(),
                VENUE.totalAssets(),
                VENUE.maxRate(),
                VENUE.forceDeallocatePenalty(ADAPTER)
            )
        );
    }
}
