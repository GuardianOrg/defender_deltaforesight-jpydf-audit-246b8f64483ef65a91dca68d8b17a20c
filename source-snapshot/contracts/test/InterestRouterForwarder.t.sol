// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {InterestRouterForwarder} from "src/InterestRouterForwarder.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {JpydfToken} from "src/JpydfToken.sol";
import {ERC20Faucet} from "test/TestContracts/ERC20Faucet.sol";

contract RecipientCheckedERC20 is ERC20Faucet {
    mapping(address recipient => bool invalid) internal invalidRecipients;

    constructor() ERC20Faucet("JPYdf", "JPYdf", 0, type(uint256).max) {}

    function setInvalidRecipient(address _recipient, bool _invalid) external {
        invalidRecipients[_recipient] = _invalid;
    }

    function requireValidRecipient(address _recipient) external view {
        if (invalidRecipients[_recipient]) revert IJpydfToken.JpydfToken__CannotTransferToProtocolContract();
    }
}

contract InterestRouterForwarderTest is Test {
    RecipientCheckedERC20 internal token;
    InterestRouterForwarder internal forwarder;

    address internal owner = makeAddr("owner");
    address internal recipient = makeAddr("recipient");

    function setUp() public {
        token = new RecipientCheckedERC20();
        forwarder = new InterestRouterForwarder(token, recipient, owner);
    }

    function test_RevertWhen_ConstructorArgsAreZero() public {
        vm.expectRevert(InterestRouterForwarder.ZeroAddress.selector);
        new InterestRouterForwarder(RecipientCheckedERC20(address(0)), recipient, owner);

        vm.expectRevert(InterestRouterForwarder.ZeroAddress.selector);
        new InterestRouterForwarder(token, address(0), owner);

        vm.expectRevert(InterestRouterForwarder.ZeroAddress.selector);
        new InterestRouterForwarder(token, recipient, address(0));
    }

    function test_RouteForwardsFullBalancePermissionlessly() public {
        token.mint(address(forwarder), 100e18);

        uint256 routed = forwarder.route();

        assertEq(routed, 100e18, "routed amount");
        assertEq(token.balanceOf(recipient), 100e18, "recipient balance");
        assertEq(token.balanceOf(address(forwarder)), 0, "forwarder drained");
    }

    function test_RouteReturnsZeroWhenEmpty() public {
        assertEq(forwarder.route(), 0, "empty route");
    }

    function test_OnlyOwnerCanUpdateRecipient() public {
        address nextRecipient = makeAddr("nextRecipient");

        vm.prank(owner);
        forwarder.setRecipient(nextRecipient);

        token.mint(address(forwarder), 1e18);
        forwarder.route();
        assertEq(token.balanceOf(nextRecipient), 1e18, "new recipient receives routed balance");
    }

    function test_RevertWhen_NonOwnerUpdatesRecipient() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(InterestRouterForwarder.Unauthorized.selector);
        forwarder.setRecipient(makeAddr("nextRecipient"));
    }

    function test_RevertWhen_RecipientIsZero() public {
        vm.prank(owner);
        vm.expectRevert(InterestRouterForwarder.ZeroAddress.selector);
        forwarder.setRecipient(address(0));
    }

    function test_RevertWhen_ConstructorRecipientIsInvalidForJpydf() public {
        address invalidRecipient = makeAddr("protocolContract");
        token.setInvalidRecipient(invalidRecipient, true);

        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        new InterestRouterForwarder(token, invalidRecipient, owner);
    }

    function test_RevertWhen_NewRecipientIsInvalidForJpydfAndKeepCurrentRouteLive() public {
        address invalidRecipient = makeAddr("protocolContract");
        token.setInvalidRecipient(invalidRecipient, true);

        vm.prank(owner);
        vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
        forwarder.setRecipient(invalidRecipient);

        assertEq(forwarder.recipient(), recipient, "recipient unchanged");

        token.mint(address(forwarder), 1e18);
        assertEq(forwarder.route(), 1e18, "route remains live");
        assertEq(token.balanceOf(recipient), 1e18, "current recipient receives balance");
    }

    function test_OwnershipTransferIsTwoStepAndRenounceDisabled() public {
        address nextOwner = makeAddr("nextOwner");

        vm.prank(owner);
        forwarder.transferOwnership(nextOwner);
        assertEq(forwarder.owner(), owner, "owner unchanged before accept");

        vm.prank(nextOwner);
        forwarder.acceptOwnership();
        assertEq(forwarder.owner(), nextOwner, "owner accepted");

        vm.prank(nextOwner);
        vm.expectRevert(InterestRouterForwarder.RenounceOwnershipDisabled.selector);
        forwarder.renounceOwnership();
    }

    function test_TransferOwnershipToZeroCancelsPendingOwner() public {
        address nextOwner = makeAddr("nextOwner");

        vm.prank(owner);
        forwarder.transferOwnership(nextOwner);
        assertEq(forwarder.pendingOwner(), nextOwner, "pending owner set");

        vm.prank(owner);
        forwarder.transferOwnership(address(0));
        assertEq(forwarder.pendingOwner(), address(0), "pending owner cancelled");

        vm.prank(nextOwner);
        vm.expectRevert(InterestRouterForwarder.Unauthorized.selector);
        forwarder.acceptOwnership();
    }

    function test_RevertWhen_NonPendingOwnerAcceptsOwnership() public {
        address nextOwner = makeAddr("nextOwner");

        vm.prank(owner);
        forwarder.transferOwnership(nextOwner);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(InterestRouterForwarder.Unauthorized.selector);
        forwarder.acceptOwnership();
    }
}

contract RecipientContract {}

contract InterestRouterForwarderJpydfIntegrationTest is Test {
    JpydfToken internal token;
    InterestRouterForwarder internal forwarder;

    address internal owner = makeAddr("owner");
    address internal recipient = makeAddr("recipient");
    address[6] internal blockedRecipients;

    function setUp() public {
        RecipientContract bridgeAdmin = new RecipientContract();
        RecipientContract troveManager = new RecipientContract();
        RecipientContract stabilityPool = new RecipientContract();
        RecipientContract borrowerOperations = new RecipientContract();
        RecipientContract activePool = new RecipientContract();
        RecipientContract collateralRegistry = new RecipientContract();

        token = new JpydfToken(address(this), address(bridgeAdmin));
        token.setBranchAddresses(
            address(troveManager), address(stabilityPool), address(borrowerOperations), address(activePool)
        );
        token.setCollateralRegistry(address(collateralRegistry));

        blockedRecipients = [
            address(token),
            address(collateralRegistry),
            address(troveManager),
            address(stabilityPool),
            address(borrowerOperations),
            address(activePool)
        ];
        forwarder = new InterestRouterForwarder(token, recipient, owner);
    }

    function test_RevertWhen_ConstructorRecipientIsAnyJpydfProtocolAddress() public {
        for (uint256 i; i < blockedRecipients.length; ++i) {
            vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
            new InterestRouterForwarder(token, blockedRecipients[i], owner);
        }
    }

    function test_RevertWhen_SetRecipientIsAnyJpydfProtocolAddress() public {
        for (uint256 i; i < blockedRecipients.length; ++i) {
            vm.prank(owner);
            vm.expectRevert(IJpydfToken.JpydfToken__CannotTransferToProtocolContract.selector);
            forwarder.setRecipient(blockedRecipients[i]);
            assertEq(forwarder.recipient(), recipient, "recipient unchanged");
        }
    }
}
