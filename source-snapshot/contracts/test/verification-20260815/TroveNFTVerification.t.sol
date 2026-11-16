// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {JPYdfTroveNFT} from "src/JPYdfTroveNFT.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

contract RevertingTroveNFTReceiver {
    fallback() external {
        revert("unexpected ERC721 receiver callback");
    }
}

/// @notice Focused evidence for TroveNFT mint/burn and ERC-721 ownership surfaces.
/// @dev This is verification-only coverage; it does not alter deployed protocol code.
contract TroveNFTVerification is DevTestSetup {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function testConstructorMetadataAndBindings() external {
        JPYdfTroveNFT fresh = new JPYdfTroveNFT(addressesRegistry);

        IERC20Metadata collateral = IERC20Metadata(address(collToken));
        assertEq(fresh.name(), string.concat("JPYdf - ", collateral.name()));
        assertEq(fresh.symbol(), string.concat("JPYdf_", collateral.symbol()));
        assertEq(address(fresh.troveManager()), address(troveManager));
        assertEq(address(fresh.metadataNFT()), address(metadataNFT));
    }

    function testTroveManagerMintBurnsAndERC721Events() external {
        JPYdfTroveNFT nft = JPYdfTroveNFT(address(troveNFT));
        uint256 troveId = 987654;

        vm.expectEmit(true, true, true, true, address(nft));
        emit Transfer(address(0), A, troveId);
        vm.prank(address(troveManager));
        nft.mint(A, troveId);
        assertEq(nft.ownerOf(troveId), A);
        assertEq(nft.balanceOf(A), 1);
        assertTrue(nft.supportsInterface(0x80ac58cd));
        assertTrue(nft.supportsInterface(0x5b5e139f));

        vm.expectEmit(true, true, true, true, address(nft));
        emit Approval(A, B, troveId);
        vm.prank(A);
        nft.approve(B, troveId);
        assertEq(nft.getApproved(troveId), B);

        vm.expectEmit(true, true, false, true, address(nft));
        emit ApprovalForAll(A, C, true);
        vm.prank(A);
        nft.setApprovalForAll(C, true);
        assertTrue(nft.isApprovedForAll(A, C));

        vm.expectEmit(true, true, true, true, address(nft));
        emit Transfer(A, D, troveId);
        vm.prank(B);
        nft.transferFrom(A, D, troveId);
        assertEq(nft.ownerOf(troveId), D);

        vm.expectEmit(true, true, true, true, address(nft));
        emit Transfer(D, address(0), troveId);
        vm.prank(address(troveManager));
        nft.burn(troveId);
        vm.expectRevert();
        nft.ownerOf(troveId);
    }

    function testMintBurnCallerGuardsAndDuplicateMint() external {
        JPYdfTroveNFT nft = JPYdfTroveNFT(address(troveNFT));
        uint256 troveId = 123456;

        vm.expectRevert(JPYdfTroveNFT.JPYdfTroveNFT__CallerIsNotTroveManager.selector);
        nft.mint(A, troveId);
        vm.expectRevert(JPYdfTroveNFT.JPYdfTroveNFT__CallerIsNotTroveManager.selector);
        nft.burn(troveId);

        vm.prank(address(troveManager));
        nft.mint(A, troveId);
        vm.prank(address(troveManager));
        vm.expectRevert();
        nft.mint(A, troveId);
        vm.prank(address(troveManager));
        nft.burn(troveId);
        vm.prank(address(troveManager));
        vm.expectRevert();
        nft.burn(troveId);
    }

    function testMintDoesNotCallReceiverCallback() external {
        JPYdfTroveNFT nft = JPYdfTroveNFT(address(troveNFT));
        RevertingTroveNFTReceiver receiver = new RevertingTroveNFTReceiver();
        uint256 troveId = 444444;

        vm.prank(address(troveManager));
        nft.mint(address(receiver), troveId);
        assertEq(nft.ownerOf(troveId), address(receiver));
    }

    function testTokenURIRejectsNonexistentTrove() external {
        JPYdfTroveNFT nft = JPYdfTroveNFT(address(troveNFT));
        vm.expectRevert();
        nft.tokenURI(987654321);
    }
}
