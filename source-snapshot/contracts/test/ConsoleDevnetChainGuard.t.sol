// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {ConsoleDevnetChainGuard} from "script/ConsoleDevnetChainGuard.sol";

contract ConsoleDevnetChainGuardTest is Test {
    function testAcceptsExplicitNonMainnetChain() external pure {
        ConsoleDevnetChainGuard.requireExpected(31338, 31338);
    }

    function testRejectsMainnetAsExpectedChain() external {
        vm.expectRevert("Console devnet: expected mainnet forbidden");
        this.check(1, 1);
    }

    function testRejectsUnexpectedChain() external {
        vm.expectRevert("Console devnet: unexpected chain");
        this.check(31337, 31338);
    }

    function testAcceptsExpectedManifestHash() external pure {
        string memory manifest = "{\"deployment\":\"hosted-anvil\"}";
        ConsoleDevnetChainGuard.requireExpectedManifestHash(manifest, keccak256(bytes(manifest)));
    }

    function testRejectsZeroManifestHash() external {
        vm.expectRevert("Console devnet: zero manifest hash");
        this.checkManifest("{}", bytes32(0));
    }

    function testRejectsUnexpectedManifestHash() external {
        vm.expectRevert("Console devnet: unexpected manifest");
        this.checkManifest("{}", keccak256("different manifest"));
    }

    function check(uint256 actualChainId, uint256 expectedChainId) external pure {
        ConsoleDevnetChainGuard.requireExpected(actualChainId, expectedChainId);
    }

    function checkManifest(string memory manifest, bytes32 expectedManifestHash) external pure {
        ConsoleDevnetChainGuard.requireExpectedManifestHash(manifest, expectedManifestHash);
    }
}
