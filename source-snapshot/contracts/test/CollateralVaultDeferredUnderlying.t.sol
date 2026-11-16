// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "../src/Interfaces/IDToken.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./mocks/MockERC20.sol";

/// @title CollateralVaultDeferredUnderlyingTest
/// @notice Covers the deferred-binding (placeholder branch) behavior:
///         initialize(underlying=0), setUnderlying one-shot + dToken-first
///         enforcement, the whenUnderlyingReady use-time guard (immediate AND
///         deferred paths), and placeholder-safe views.
contract CollateralVaultDeferredUnderlyingTest is Test {
    event UnderlyingSet(address indexed underlying);

    DToken public dToken; // placeholder pair: unbound dToken
    CollateralVault public vault; // placeholder pair: underlying == address(0)
    MockERC20 public wbtc; // intended underlying (8 dec)
    MockERC20 public usdc; // mismatch token (6 dec)

    address public admin;
    address public treasury;
    address public alice;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");

        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // Placeholder pair: vault underlying == address(0), dToken not yet bound.
        (dToken, vault) = _deployPair(address(0));
    }

    /// @dev Deploy a DToken+CollateralVault proxy pair, resolving the circular
    ///      reference via address prediction. `vaultUnderlying` may be address(0)
    ///      (placeholder). The dToken is left unbound (no setTokenInfo).
    function _deployPair(address vaultUnderlying) internal returns (DToken d, CollateralVault v) {
        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        d = DToken(
            address(
                new ERC1967Proxy(address(dImpl), abi.encodeWithSelector(DToken.initialize.selector, predicted, admin))
            )
        );
        if (vaultUnderlying != address(0)) {
            d.setAllowedUnderlying(vaultUnderlying, true);
        }
        v = CollateralVault(
            address(
                new ERC1967Proxy(
                    address(vImpl),
                    abi.encodeWithSelector(
                        CollateralVault.initialize.selector,
                        IERC20(vaultUnderlying),
                        IDToken(address(d)),
                        treasury,
                        admin
                    )
                )
            )
        );
        require(address(v) == predicted, "addr prediction");
    }

    // =================================================================
    //                  initialize(underlying = 0)
    // =================================================================

    function test_Initialize_AllowsZeroUnderlying() public view {
        assertEq(address(vault.underlying()), address(0), "placeholder underlying is zero");
        assertEq(address(vault.dToken()), address(dToken));
        assertEq(vault.treasury(), treasury);
    }

    function test_Initialize_StillRejectsZeroDTokenTreasuryAdmin() public {
        CollateralVault impl = new CollateralVault();
        // zero dToken
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                CollateralVault.initialize.selector, IERC20(address(0)), IDToken(address(0)), treasury, admin
            )
        );
        // zero treasury
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                CollateralVault.initialize.selector, IERC20(address(0)), IDToken(address(dToken)), address(0), admin
            )
        );
        // zero admin
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                CollateralVault.initialize.selector, IERC20(address(0)), IDToken(address(dToken)), treasury, address(0)
            )
        );
    }

    function test_Initialize_RevertsOnDTokenVaultMismatchForPlaceholder() public {
        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        DToken wrongDToken = DToken(
            address(
                new ERC1967Proxy(
                    address(dImpl), abi.encodeWithSelector(DToken.initialize.selector, makeAddr("wrongVault"), admin)
                )
            )
        );

        bytes memory init = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(0)), IDToken(address(wrongDToken)), treasury, admin
        );

        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        new ERC1967Proxy(address(vImpl), init);
    }

    // =================================================================
    //          whenUnderlyingReady — pre-activation reverts
    // =================================================================

    function test_Deposit_RevertsBeforeSetUnderlying() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        vault.deposit(1e8);
    }

    function test_Redeem_RevertsBeforeSetUnderlying() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        vault.redeem(1e18, alice);
    }

    function test_RedeemWithPermit_RevertsBeforeSetUnderlying() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        vault.redeemWithPermit(1e18, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), alice);
    }

    function test_BackstopDeposit_RevertsBeforeSetUnderlying() public {
        wbtc.mint(alice, 1e8);
        vm.startPrank(alice);
        wbtc.approve(address(vault), 1e8);
        vm.expectRevert(CollateralVault.UnderlyingNotSet.selector);
        vault.backstopDeposit(1e8);
        vm.stopPrank();
    }

    // =================================================================
    //                       setUnderlying
    // =================================================================

    function test_SetUnderlying_RevertsIfNotGov() public {
        dToken.setAllowedUnderlying(address(wbtc), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc)));
        vm.prank(alice);
        vm.expectRevert(); // AccessControl: missing GOV_ROLE
        vault.setUnderlying(IERC20(address(wbtc)));
    }

    function test_SetUnderlying_RevertsOnZeroAddress() public {
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.setUnderlying(IERC20(address(0)));
    }

    /// @dev dToken-first ordering: binding the vault before the dToken reverts.
    function test_SetUnderlying_RevertsIfDTokenNotBound() public {
        // dToken still unbound (dToken.underlying() == 0).
        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        vault.setUnderlying(IERC20(address(wbtc)));
    }

    /// @dev The core asset-mismatch guard: dToken bound to WBTC, vault to USDC.
    function test_SetUnderlying_RevertsOnAssetMismatch() public {
        dToken.setAllowedUnderlying(address(wbtc), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc)));
        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        vault.setUnderlying(IERC20(address(usdc)));
    }

    function test_SetUnderlying_RevertsIfAlreadySet() public {
        dToken.setAllowedUnderlying(address(wbtc), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc)));
        vault.setUnderlying(IERC20(address(wbtc)));
        vm.expectRevert(CollateralVault.UnderlyingAlreadySet.selector);
        vault.setUnderlying(IERC20(address(wbtc)));
    }

    function test_SetUnderlying_SucceedsWhenDTokenMatches() public {
        dToken.setAllowedUnderlying(address(wbtc), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc)));
        vm.expectEmit(true, true, true, true);
        emit UnderlyingSet(address(wbtc));
        vault.setUnderlying(IERC20(address(wbtc)));
        assertEq(address(vault.underlying()), address(wbtc));
    }

    // =================================================================
    //               immediate-path mismatch (initialize)
    // =================================================================

    /// @dev Even if a vault is initialized with a NON-zero underlying that
    ///      differs from its dToken's, the use-time guard fails closed.
    function test_Deposit_RevertsOnImmediatePathMismatch() public {
        (DToken d, CollateralVault v) = _deployPair(address(usdc)); // vault underlying = USDC
        d.setAllowedUnderlying(address(wbtc), true);
        d.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc))); // dToken = WBTC

        usdc.mint(alice, 1e6);
        vm.startPrank(alice);
        usdc.approve(address(v), 1e6);
        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        v.deposit(1e6);
        vm.stopPrank();
    }

    // =================================================================
    //                   full activation flow
    // =================================================================

    function test_FullActivationFlow_ThenDepositWorks() public {
        // dToken-first activation order.
        dToken.setAllowedUnderlying(address(wbtc), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(wbtc)));
        vault.setUnderlying(IERC20(address(wbtc)));
        activateDTokenForTest(dToken);

        wbtc.mint(alice, 5e8);
        vm.startPrank(alice);
        wbtc.approve(address(vault), 5e8);
        uint256 minted = vault.deposit(5e8);
        vm.stopPrank();

        assertEq(minted, 5e18, "8->18 dec convert after activation");
        assertEq(dToken.balanceOf(alice), 5e18);
        assertEq(vault.bufferBalance(), 5e8);

        // Immediate redeem also works post-activation.
        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeem(5e18, alice);
        assertEq(received, 5e8);
        assertEq(requestId, 0);
    }

    // =================================================================
    //                  placeholder-safe views
    // =================================================================

    function test_PlaceholderSafe_Views_ReturnZeroNotRevert() public view {
        // underlying == address(0): bufferBalance/totalUnderlying must return 0
        // (a naive underlying.balanceOf(this) would revert on address(0)).
        assertEq(address(vault.underlying()), address(0));
        assertEq(vault.bufferBalance(), 0, "buffer 0 while placeholder");
        assertEq(vault.backstopBalance(), 0, "backstop 0 while placeholder");
        assertEq(vault.totalUnderlying(), 0, "total 0 while placeholder");
        assertEq(vault.backingRatio(), 1e18, "zero-liability placeholder backing");
    }
}
