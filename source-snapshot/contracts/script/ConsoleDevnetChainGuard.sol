// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library ConsoleDevnetChainGuard {
    function requireExpected(uint256 actualChainId, uint256 expectedChainId) internal pure {
        require(expectedChainId != 1, "Console devnet: expected mainnet forbidden");
        require(actualChainId == expectedChainId, "Console devnet: unexpected chain");
    }

    function requireExpectedManifestHash(string memory manifest, bytes32 expectedManifestHash) internal pure {
        require(expectedManifestHash != bytes32(0), "Console devnet: zero manifest hash");
        require(keccak256(bytes(manifest)) == expectedManifestHash, "Console devnet: unexpected manifest");
    }
}
