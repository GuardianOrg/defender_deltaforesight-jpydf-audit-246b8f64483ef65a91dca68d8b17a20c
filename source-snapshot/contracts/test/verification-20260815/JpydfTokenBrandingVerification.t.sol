// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {JpydfToken} from "src/JpydfToken.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

contract JpydfTokenBrandingVerification is DevTestSetup {
    function testCoreReferenceViewsReflectRenouncedDeployment() public view {
        JpydfToken token = JpydfToken(address(jpydfToken));

        assertEq(token.owner(), address(0), "Core owner is renounced");
        assertFalse(token.isOwner(), "test caller is not owner");
        assertEq(token.collateralRegistryAddress(), address(collateralRegistry), "collateral registry reference");
    }

    function testNameSymbolAndEip712DomainUseJpydfBrand() public view {
        JpydfToken token = JpydfToken(address(jpydfToken));

        assertEq(token.name(), "JPYdf Stablecoin", "ERC-20 name");
        assertEq(token.symbol(), "JPYdf", "ERC-20 symbol");

        (
            bytes1 fields,
            string memory domainName,
            string memory domainVersion,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = token.eip712Domain();
        assertEq(uint8(fields), 0x0f, "EIP-712 populated fields");
        assertEq(domainName, "JPYdf Stablecoin", "EIP-712 domain name");
        assertEq(domainVersion, "1", "EIP-712 domain version");
        assertEq(chainId, block.chainid, "EIP-712 chain id");
        assertEq(verifyingContract, address(token), "EIP-712 verifying contract");
        assertEq(salt, bytes32(0), "EIP-712 no salt");
        assertEq(extensions.length, 0, "EIP-712 no extensions");
    }
}
