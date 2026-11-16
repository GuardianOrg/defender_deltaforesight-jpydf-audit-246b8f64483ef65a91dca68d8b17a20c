// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {JpydfToken} from "src/JpydfToken.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";

import "./TestContracts/DevTestSetup.sol";
import {TestBridgeRoleHolder} from "./TestContracts/Deployment.t.sol";

contract JpydfTokenTest is DevTestSetup {
    uint256 internal constant BRIDGE_MINTER_TIMELOCK = 48 hours;

    event BridgeAdminTransferStarted(address indexed currentBridgeAdmin, address indexed pendingBridgeAdmin);
    event BridgeAdminTransferred(address indexed previousBridgeAdmin, address indexed newBridgeAdmin);
    event BridgeMinterProposed(address indexed bridgeMinter, uint256 proposedAt, uint256 confirmableAt);
    event BridgeMinterProposalCancelled(address indexed bridgeMinter);
    event BridgeMinterConfirmed(address indexed bridgeMinter);
    event BridgeMinterRemoved(address indexed bridgeMinter);
    event BridgeMint(address indexed bridgeMinter, address indexed account, uint256 amount);
    event BridgeBurn(address indexed bridgeMinter, uint256 amount);

    // TODO: need more tests for:
    // - sendToPool() / returnFromPool()

    function test_InfiniteApprovalPersistsAfterTransfer() external {
        uint256 initialBalance_A = 1_500_000 ether;

        openTroveHelper(A, 0, 15000 ether, initialBalance_A, 0.01 ether);
        assertEq(jpydfToken.balanceOf(A), initialBalance_A, "A's balance is wrong");

        vm.prank(A);
        assertTrue(jpydfToken.approve(B, UINT256_MAX));
        assertEq(jpydfToken.allowance(A, B), UINT256_MAX, "Allowance should be infinite");

        uint256 value = 1_000 ether;

        vm.prank(B);
        assertTrue(jpydfToken.transferFrom(A, C, value));
        assertEq(jpydfToken.balanceOf(A), initialBalance_A - value, "A's balance should have decreased by value");
        assertEq(jpydfToken.balanceOf(C), value, "C's balance should have increased by value");
        assertEq(jpydfToken.allowance(A, B), UINT256_MAX, "Allowance should still be infinite");
    }

    function test_TransferProtectionRejectsProtocolRecipients() external {
        openTroveHelper(A, 0, 15000 ether, 1_500_000 ether, 0.01 ether);

        address[5] memory blockedRecipients = [
            address(collateralRegistry),
            address(troveManager),
            address(stabilityPool),
            address(borrowerOperations),
            address(activePool)
        ];

        for (uint256 i = 0; i < blockedRecipients.length; i++) {
            vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
            vm.prank(A);
            jpydfToken.transfer(blockedRecipients[i], 1 ether);
        }
    }

    function test_TransferFromProtectionRejectsProtocolRecipients() external {
        openTroveHelper(A, 0, 15000 ether, 1_500_000 ether, 0.01 ether);

        vm.prank(A);
        jpydfToken.approve(B, 1 ether);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        vm.prank(B);
        jpydfToken.transferFrom(A, address(stabilityPool), 1 ether);
    }

    function test_RecipientHelpersMatchTransferProtection() external view {
        assertTrue(jpydfToken.isValidRecipient(A), "EOA is valid");
        assertFalse(jpydfToken.isValidRecipient(address(0)), "zero address is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(jpydfToken)), "token is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(collateralRegistry)), "registry is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(troveManager)), "trove manager is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(stabilityPool)), "stability pool is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(borrowerOperations)), "borrower operations is invalid");
        assertFalse(jpydfToken.isValidRecipient(address(activePool)), "active pool is invalid");

        jpydfToken.requireValidRecipient(A);
    }

    function test_RevertWhen_RequireValidRecipientInvalid() external {
        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        jpydfToken.requireValidRecipient(address(stabilityPool));
    }

    function test_CoreAddressRegistrationRequiresContracts() external {
        JpydfToken token = new JpydfToken(address(this), _newBridgeRoleHolder());
        address coreContract = _newBridgeRoleHolder();
        address codelessAddress = makeAddr("codeless core");

        vm.expectRevert(IJpydfToken.JpydfToken__ZeroCoreAddress.selector);
        token.setBranchAddresses(address(0), coreContract, coreContract, coreContract);

        vm.expectRevert(IJpydfToken.JpydfToken__CoreAddressMustBeContract.selector);
        token.setBranchAddresses(codelessAddress, coreContract, coreContract, coreContract);

        vm.expectRevert(IJpydfToken.JpydfToken__ZeroCoreAddress.selector);
        token.setCollateralRegistry(address(0));

        vm.expectRevert(IJpydfToken.JpydfToken__CoreAddressMustBeContract.selector);
        token.setCollateralRegistry(codelessAddress);
    }

    function test_MainnetUsesProductionIdentity() external {
        vm.chainId(1);
        JpydfToken token = new JpydfToken(address(this), _newBridgeRoleHolder());

        assertEq(token.name(), "JPYdf Stablecoin");
        assertEq(token.symbol(), "JPYdf");
        (, string memory domainName, string memory domainVersion, uint256 chainId, address verifyingContract,,) =
            token.eip712Domain();
        assertEq(domainName, "JPYdf Stablecoin");
        assertEq(domainVersion, "1");
        assertEq(chainId, 1);
        assertEq(verifyingContract, address(token));
        assertEq(
            token.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("JPYdf Stablecoin")),
                    keccak256(bytes("1")),
                    uint256(1),
                    address(token)
                )
            )
        );
    }

    function test_NonMainnetKeepsProductionIdentity() external {
        vm.chainId(31337);
        JpydfToken token = new JpydfToken(address(this), _newBridgeRoleHolder());

        assertEq(token.name(), "JPYdf Stablecoin");
        assertEq(token.symbol(), "JPYdf");
    }

    function test_BridgeConstructorRejectsInvalidRoles() external {
        address bridgeAdmin = _newBridgeRoleHolder();

        vm.expectRevert(IJpydfToken.JpydfToken__ZeroOwner.selector);
        new JpydfToken(address(0), bridgeAdmin);

        vm.expectRevert(IJpydfToken.JpydfToken__ZeroBridgeAdmin.selector);
        new JpydfToken(address(this), address(0));

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminCannotBeOwner.selector);
        new JpydfToken(address(this), address(this));
    }

    function test_BridgeReadinessIsDormantAfterCoreSetup() external {
        JpydfToken token = JpydfToken(address(jpydfToken));
        address bridgeMinter = makeAddr("bridgeMinter");

        assertEq(token.owner(), address(0), "core owner renounced");
        assertGt(jpydfToken.bridgeAdmin().code.length, 0, "bridge admin is contract");
        assertEq(jpydfToken.bridgeMinterCount(), 0, "no bridge minters");
        assertEq(jpydfToken.proposedBridgeMinter(), address(0), "no bridge proposal");
        assertFalse(jpydfToken.isBridgeMinter(bridgeMinter), "not bridge minter");

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBorrowerOperationsOrActivePool.selector);
        vm.prank(bridgeMinter);
        jpydfToken.mint(A, 1 ether);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeMinter.selector);
        vm.prank(bridgeMinter);
        jpydfToken.bridgeMint(A, 1 ether);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotCoreBurner.selector);
        vm.prank(bridgeMinter);
        jpydfToken.burn(A, 1 ether);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotStabilityPool.selector);
        vm.prank(bridgeMinter);
        jpydfToken.sendToPool(A, address(stabilityPool), 1 ether);
    }

    function test_BridgeMinterLifecycleUsesTimelockAndSelfBurn() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();
        uint256 amount = 10 ether;

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);
        assertEq(jpydfToken.proposedBridgeMinter(), bridgeMinter, "proposed minter");
        assertEq(jpydfToken.bridgeMinterProposedAt(), block.timestamp, "proposal timestamp");

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterTimelockNotElapsed.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.warp(block.timestamp + BRIDGE_MINTER_TIMELOCK);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        assertTrue(jpydfToken.isBridgeMinter(bridgeMinter), "confirmed bridge minter");
        assertEq(jpydfToken.bridgeMinterCount(), 1, "minter count");
        assertEq(jpydfToken.proposedBridgeMinter(), address(0), "proposal cleared");

        vm.prank(bridgeMinter);
        jpydfToken.bridgeMint(A, amount);
        assertEq(jpydfToken.balanceOf(A), amount, "bridge minted to user");

        vm.expectRevert();
        vm.prank(bridgeMinter);
        jpydfToken.bridgeBurn(1 ether);

        vm.prank(A);
        jpydfToken.transfer(bridgeMinter, 4 ether);

        vm.prank(bridgeMinter);
        jpydfToken.bridgeBurn(3 ether);
        assertEq(jpydfToken.balanceOf(bridgeMinter), 1 ether, "self-burn leaves bridge balance only");

        vm.prank(bridgeAdmin);
        jpydfToken.removeBridgeMinter(bridgeMinter);
        assertFalse(jpydfToken.isBridgeMinter(bridgeMinter), "removed bridge minter");
        assertEq(jpydfToken.bridgeMinterCount(), 0, "minter count cleared");

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeMinter.selector);
        vm.prank(bridgeMinter);
        jpydfToken.bridgeMint(A, 1 ether);
    }

    function test_BridgeAdminCanCancelAndTransferTwoStep() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();
        address newBridgeAdmin = _newBridgeRoleHolder();

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);

        vm.prank(bridgeAdmin);
        jpydfToken.cancelBridgeMinterProposal();
        assertEq(jpydfToken.proposedBridgeMinter(), address(0), "proposal cancelled");
        assertEq(jpydfToken.bridgeMinterProposedAt(), 0, "proposal timestamp cleared");

        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(newBridgeAdmin);
        assertEq(jpydfToken.pendingBridgeAdmin(), newBridgeAdmin, "pending bridge admin");

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterCannotBeAdmin.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(newBridgeAdmin);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotPendingBridgeAdmin.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.acceptBridgeAdmin();

        vm.prank(newBridgeAdmin);
        jpydfToken.acceptBridgeAdmin();
        assertEq(jpydfToken.bridgeAdmin(), newBridgeAdmin, "bridge admin transferred");
        assertEq(jpydfToken.pendingBridgeAdmin(), address(0), "pending cleared");
    }

    function test_BridgeMinterProposalRejectsInvalidStateTransitions() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();
        address otherBridgeMinter = _newBridgeRoleHolder();

        vm.expectRevert(IJpydfToken.JpydfToken__NoBridgeMinterProposed.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectRevert(IJpydfToken.JpydfToken__NoBridgeMinterProposed.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.cancelBridgeMinterProposal();

        vm.expectRevert(IJpydfToken.JpydfToken__NotBridgeMinter.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.removeBridgeMinter(bridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__ZeroBridgeMinter.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(address(0));

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterAlreadyProposed.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(otherBridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotRenounceWithPendingBridgeMinter.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.renounceBridgeAdmin();

        vm.warp(block.timestamp + BRIDGE_MINTER_TIMELOCK);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterAlreadySet.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);
    }

    function test_BridgeAdminEntryPointsRejectNonAdminCallers() external {
        address nonAdmin = _newBridgeRoleHolder();
        address bridgeMinter = _newBridgeRoleHolder();
        address newBridgeAdmin = _newBridgeRoleHolder();

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.cancelBridgeMinterProposal();

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.removeBridgeMinter(bridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.transferBridgeAdmin(newBridgeAdmin);

        vm.expectRevert(IJpydfToken.JpydfToken__CallerIsNotBridgeAdmin.selector);
        vm.prank(nonAdmin);
        jpydfToken.renounceBridgeAdmin();
    }

    function test_BridgeAdminTransferRejectsOwner() external {
        address bridgeAdmin = _newBridgeRoleHolder();
        JpydfToken token = new JpydfToken(address(this), bridgeAdmin);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminCannotBeOwner.selector);
        vm.prank(bridgeAdmin);
        token.transferBridgeAdmin(address(this));
    }

    function test_BridgeAdminCannotRenounceWithLiveMinter() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);
        vm.warp(block.timestamp + BRIDGE_MINTER_TIMELOCK);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMintersStillSet.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.renounceBridgeAdmin();

        vm.prank(bridgeAdmin);
        jpydfToken.removeBridgeMinter(bridgeMinter);

        vm.prank(bridgeAdmin);
        jpydfToken.renounceBridgeAdmin();
        assertEq(jpydfToken.bridgeAdmin(), address(0), "bridge admin renounced");
    }

    function test_BridgeRolesMustBeContractsAndSeparated() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();
        address eoa = makeAddr("eoa");

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminMustBeContract.selector);
        new JpydfToken(address(this), eoa);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterMustBeContract.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(eoa);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminMustBeContract.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(eoa);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterCannotBeToken.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(address(jpydfToken));

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminCannotBeToken.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(address(jpydfToken));

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterCannotBeAdmin.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeAdmin);

        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(bridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeMinterCannotBeAdmin.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);

        address otherBridgeMinter = _newBridgeRoleHolder();
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(otherBridgeMinter);

        vm.expectRevert(IJpydfToken.JpydfToken__BridgeAdminCannotBeMinter.selector);
        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(otherBridgeMinter);
    }

    function test_BridgeMintRejectsProtocolRecipients() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);
        vm.warp(block.timestamp + BRIDGE_MINTER_TIMELOCK);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        vm.prank(bridgeMinter);
        jpydfToken.bridgeMint(address(stabilityPool), 1 ether);
    }

    function test_BridgeReadinessEventsExposeLifecyclePayloads() external {
        address bridgeAdmin = jpydfToken.bridgeAdmin();
        address bridgeMinter = _newBridgeRoleHolder();
        address newBridgeAdmin = _newBridgeRoleHolder();
        uint256 amount = 2 ether;

        vm.expectEmit(true, false, false, true, address(jpydfToken));
        emit BridgeMinterProposed(bridgeMinter, block.timestamp, block.timestamp + BRIDGE_MINTER_TIMELOCK);
        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);

        vm.expectEmit(true, false, false, false, address(jpydfToken));
        emit BridgeMinterProposalCancelled(bridgeMinter);
        vm.prank(bridgeAdmin);
        jpydfToken.cancelBridgeMinterProposal();

        vm.prank(bridgeAdmin);
        jpydfToken.proposeBridgeMinter(bridgeMinter);
        vm.warp(block.timestamp + BRIDGE_MINTER_TIMELOCK);

        vm.expectEmit(true, false, false, false, address(jpydfToken));
        emit BridgeMinterConfirmed(bridgeMinter);
        vm.prank(bridgeAdmin);
        jpydfToken.confirmBridgeMinter();

        vm.expectEmit(true, true, false, true, address(jpydfToken));
        emit BridgeMint(bridgeMinter, bridgeMinter, amount);
        vm.prank(bridgeMinter);
        jpydfToken.bridgeMint(bridgeMinter, amount);

        vm.expectEmit(true, false, false, true, address(jpydfToken));
        emit BridgeBurn(bridgeMinter, 1 ether);
        vm.prank(bridgeMinter);
        jpydfToken.bridgeBurn(1 ether);

        vm.expectEmit(true, false, false, false, address(jpydfToken));
        emit BridgeMinterRemoved(bridgeMinter);
        vm.prank(bridgeAdmin);
        jpydfToken.removeBridgeMinter(bridgeMinter);

        vm.expectEmit(true, true, false, false, address(jpydfToken));
        emit BridgeAdminTransferStarted(bridgeAdmin, newBridgeAdmin);
        vm.prank(bridgeAdmin);
        jpydfToken.transferBridgeAdmin(newBridgeAdmin);

        vm.expectEmit(true, true, false, false, address(jpydfToken));
        emit BridgeAdminTransferred(bridgeAdmin, newBridgeAdmin);
        vm.prank(newBridgeAdmin);
        jpydfToken.acceptBridgeAdmin();

        vm.expectEmit(true, true, false, false, address(jpydfToken));
        emit BridgeAdminTransferred(newBridgeAdmin, address(0));
        vm.prank(newBridgeAdmin);
        jpydfToken.renounceBridgeAdmin();
    }

    function _newBridgeRoleHolder() internal returns (address) {
        return address(new TestBridgeRoleHolder());
    }
}
