// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest, MockDTokenRegistry} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";
import "../src/DToken.sol";
import "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./mocks/MockERC20.sol";

/**
 * @title DTokenTest - Unit tests for DToken
 */
contract DTokenTest is Test {
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    DToken public dToken;
    DToken public dTokenImpl;
    MockERC20 public underlying;
    address public vault;
    address public user;
    address public owner;

    function setUp() public {
        vault = address(0x1234);
        user = address(0x5678);
        owner = address(this);

        // 8 decimals underlying (like WBTC)
        underlying = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        // Deploy DToken implementation
        dTokenImpl = new DToken();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, vault, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(dTokenImpl), initData);
        dToken = DToken(address(proxy));

        // Set token info (name, symbol, underlying) separately
        dToken.setAllowedUnderlying(address(underlying), true);
        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(dToken);
    }

    function test_Decimals() public view {
        assertEq(dToken.decimals(), 18);
        assertEq(dToken.underlyingDecimals(), 8);
    }

    function test_NameAndSymbol() public view {
        assertEq(dToken.name(), "dWBTC");
        assertEq(dToken.symbol(), "dWBTC");
    }

    // Before setTokenInfo is called, name/symbol fall back to the placeholder set in initialize
    function test_NameAndSymbolFallbackBeforeSetTokenInfo() public {
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, vault, owner);
        DToken td = DToken(address(new ERC1967Proxy(address(dTokenImpl), initData)));
        assertEq(td.name(), "DToken Placeholder");
        assertEq(td.symbol(), "dTOKEN");
    }

    function test_ConvertToDToken() public view {
        // 1 WBTC (8 decimals) = 1e8 → 1 dWBTC (18 decimals) = 1e18
        uint256 wbtcAmount = 1e8;
        uint256 dTokenAmount = dToken.convertToDToken(wbtcAmount);
        assertEq(dTokenAmount, 1e18);

        // 0.5 WBTC
        wbtcAmount = 5e7;
        dTokenAmount = dToken.convertToDToken(wbtcAmount);
        assertEq(dTokenAmount, 5e17);
    }

    function test_ConvertToUnderlying() public view {
        // 1 dWBTC (18 decimals) = 1e18 → 1 WBTC (8 decimals) = 1e8
        uint256 dTokenAmount = 1e18;
        uint256 wbtcAmount = dToken.convertToUnderlying(dTokenAmount);
        assertEq(wbtcAmount, 1e8);

        // Rounding: less than smallest WBTC unit rounds down to 0
        dTokenAmount = 1e10 - 1;
        wbtcAmount = dToken.convertToUnderlying(dTokenAmount);
        assertEq(wbtcAmount, 0);
    }

    function test_MintOnlyVault() public {
        vm.prank(vault);
        dToken.mint(user, 1e18);
        assertEq(dToken.balanceOf(user), 1e18);
    }

    function test_MintRevertNonVault() public {
        vm.prank(user);
        vm.expectRevert(DToken.OnlyVault.selector);
        dToken.mint(user, 1e18);
    }

    function test_BurnOnlyVault() public {
        vm.prank(vault);
        dToken.mint(user, 1e18);

        vm.prank(vault);
        dToken.burn(user, 1e18);
        assertEq(dToken.balanceOf(user), 0);
    }

    function test_BurnRevertNonVault() public {
        vm.prank(vault);
        dToken.mint(user, 1e18);

        vm.prank(user);
        vm.expectRevert(DToken.OnlyVault.selector);
        dToken.burn(user, 1e18);
    }

    // --- Cap Tests ---

    function test_DefaultCap() public {
        assertEq(_deployDTokenNoTokenInfo().cap(), 0);
    }

    function test_GuardianL01_UnboundRegistryBlocksCapAndMint() public {
        DToken td = _deployDTokenNoTokenInfo();
        td.setAllowedUnderlying(address(underlying), true);
        td.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        td.setCap(1e18);
        vm.prank(vault);
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        td.mint(user, 1e18);
        td.setCap(0);
        assertEq(td.totalSupply(), 0);
    }

    function test_GuardianL01_RegistryBindingIsAuthorizedAndOneShot() public {
        DToken td = _deployDTokenNoTokenInfo();
        MockDTokenRegistry registry = new MockDTokenRegistry(address(td), true);
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        td.setRiskParamsRegistry(address(registry));
        vm.expectRevert(DToken.NotContract.selector);
        td.setRiskParamsRegistry(address(0));
        vm.expectRevert(DToken.NotContract.selector);
        td.setRiskParamsRegistry(user);
        MockDTokenRegistry wrongRegistry = new MockDTokenRegistry(address(dToken), true);
        vm.expectRevert(DToken.DToken__RegistryCollateralMismatch.selector);
        td.setRiskParamsRegistry(address(wrongRegistry));
        td.setRiskParamsRegistry(address(registry));
        assertEq(td.riskParamsRegistry(), address(registry));
        vm.expectRevert(DToken.DToken__RiskParamsRegistryAlreadySet.selector);
        td.setRiskParamsRegistry(address(wrongRegistry));
    }

    function test_GuardianL01_MintChecksFinalizationEvenWithOpenCap() public {
        // A failing registry read must stop issuance without blocking cap closure
        // or redemption. Real AddressesRegistry finalization is monotonic.
        vm.prank(vault);
        dToken.mint(user, 1e18);
        MockDTokenRegistry(dToken.riskParamsRegistry()).setFinalized(false);
        vm.prank(vault);
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        dToken.mint(user, 1e18);
        dToken.setCap(0);
        vm.prank(vault);
        dToken.burn(user, 1e18);
        assertEq(dToken.totalSupply(), 0);
    }

    function test_SetCap() public {
        uint256 newCap = 1000e18;
        dToken.setCap(newCap);
        assertEq(dToken.cap(), newCap);
    }

    function test_TimelockOwnerCanIdleAndReopenCapRepeatedly() public {
        address governor = makeAddr("governor");
        address[] memory proposers = new address[](1);
        proposers[0] = governor;
        address[] memory executors = new address[](1);
        executors[0] = governor;
        TimelockController timelock = new TimelockController(5 minutes, proposers, executors, address(0));

        dToken.transferOwnership(address(timelock));
        _executeTimelockCall(timelock, governor, abi.encodeCall(DToken.acceptOwnership, ()), bytes32(uint256(1)));

        _executeTimelockCall(timelock, governor, abi.encodeCall(DToken.setCap, (123e18)), bytes32(uint256(2)));
        assertEq(dToken.cap(), 123e18);
        _executeTimelockCall(timelock, governor, abi.encodeCall(DToken.setCap, (0)), bytes32(uint256(3)));
        assertEq(dToken.cap(), 0);
        _executeTimelockCall(timelock, governor, abi.encodeCall(DToken.setCap, (456e18)), bytes32(uint256(4)));
        assertEq(dToken.cap(), 456e18);
    }

    function _executeTimelockCall(TimelockController timelock, address governor, bytes memory payload, bytes32 salt)
        internal
    {
        vm.prank(governor);
        timelock.schedule(address(dToken), 0, payload, bytes32(0), salt, 5 minutes);
        vm.warp(block.timestamp + 5 minutes);
        vm.prank(governor);
        timelock.execute(address(dToken), 0, payload, bytes32(0), salt);
    }

    function test_SetCapEvent() public {
        uint256 oldCap = dToken.cap();
        uint256 newCap = 500e18;

        vm.expectEmit(true, true, true, true);
        emit DToken.CapUpdated(oldCap, newCap);

        dToken.setCap(newCap);
    }

    function test_SetCapRevertNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dToken.setCap(100e18);
    }

    function test_MintWithinCap() public {
        uint256 cap = 100e18;
        dToken.setCap(cap);

        vm.prank(vault);
        dToken.mint(user, 50e18);
        assertEq(dToken.balanceOf(user), 50e18);

        vm.prank(vault);
        dToken.mint(user, 50e18);
        assertEq(dToken.balanceOf(user), 100e18);
    }

    function test_MintExceedsCap() public {
        uint256 cap = 100e18;
        dToken.setCap(cap);

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(DToken.CapExceeded.selector, 101e18, cap));
        dToken.mint(user, 101e18);
    }

    function test_MintExceedsCapAfterPartialMint() public {
        uint256 cap = 100e18;
        dToken.setCap(cap);

        vm.prank(vault);
        dToken.mint(user, 80e18);

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(DToken.CapExceeded.selector, 130e18, cap));
        dToken.mint(user, 50e18);
    }

    function test_SetCapBelowCurrentSupply() public {
        vm.prank(vault);
        dToken.mint(user, 100e18);

        // Setting cap below current supply is an intentional issuance stop.
        dToken.setCap(50e18);
        assertEq(dToken.cap(), 50e18);
        assertEq(dToken.totalSupply(), 100e18, "existing issuance is preserved");
        assertEq(dToken.balanceOf(user), 100e18, "holder balance is preserved");

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(DToken.CapExceeded.selector, 101e18, 50e18));
        dToken.mint(user, 1e18);

        // Redemption remains available and naturally brings supply back below cap.
        vm.prank(vault);
        dToken.burn(user, 60e18);
        assertEq(dToken.totalSupply(), 40e18);

        // Minting resumes without another governance action once supply fits the cap.
        vm.prank(vault);
        dToken.mint(user, 10e18);
        assertEq(dToken.totalSupply(), 50e18);
    }

    function test_BurnThenMintWithCap() public {
        uint256 cap = 100e18;
        dToken.setCap(cap);

        vm.prank(vault);
        dToken.mint(user, 100e18);

        vm.prank(vault);
        dToken.burn(user, 30e18);
        assertEq(dToken.totalSupply(), 70e18);

        // After burn, minting within cap works again
        vm.prank(vault);
        dToken.mint(user, 30e18);
        assertEq(dToken.totalSupply(), 100e18);
    }

    // --- Upgrade Tests ---

    function test_UpgradeOnlyOwner() public {
        DToken newImpl = new DToken();
        dToken.upgradeTo(address(newImpl));
        // proxy still works after upgrade
        assertEq(dToken.decimals(), 18);
    }

    function test_UpgradeRevertNonOwner() public {
        DToken newImpl = new DToken();
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        dToken.upgradeTo(address(newImpl));
    }

    // --- Ownership Tests ---

    function test_TransferOwnership_IsTwoStep() public {
        address newOwner = makeAddr("newOwner");

        vm.expectEmit(true, true, false, true, address(dToken));
        emit OwnershipTransferStarted(owner, newOwner);
        dToken.transferOwnership(newOwner);

        assertEq(dToken.owner(), owner, "owner unchanged until accept");
        assertEq(dToken.pendingOwner(), newOwner, "pending owner set");

        vm.prank(newOwner);
        dToken.acceptOwnership();

        assertEq(dToken.owner(), newOwner, "ownership accepted");
        assertEq(dToken.pendingOwner(), address(0), "pending owner cleared");

        vm.prank(newOwner);
        dToken.setCap(123e18);
        assertEq(dToken.cap(), 123e18, "new owner controls cap");
    }

    function test_AcceptOwnership_RevertsForNonPendingOwner() public {
        address newOwner = makeAddr("newOwner");
        address notPending = makeAddr("notPending");

        dToken.transferOwnership(newOwner);

        vm.prank(notPending);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        dToken.acceptOwnership();
    }

    function test_TransferOwnership_ZeroAddressCancelsPendingTransfer() public {
        address newOwner = makeAddr("newOwner");

        dToken.transferOwnership(newOwner);
        assertEq(dToken.pendingOwner(), newOwner, "pending owner set");

        dToken.transferOwnership(address(0));
        assertEq(dToken.owner(), owner, "owner unchanged");
        assertEq(dToken.pendingOwner(), address(0), "pending owner cleared");

        vm.prank(newOwner);
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        dToken.acceptOwnership();
    }

    function test_RenounceOwnership_Disabled() public {
        vm.expectRevert(DToken.RenounceOwnershipDisabled.selector);
        dToken.renounceOwnership();

        assertEq(dToken.owner(), owner, "owner preserved");
    }

    // --- Permit / Nonces Tests ---

    function test_NonceStartsAtZero() public view {
        assertEq(dToken.nonces(user), 0);
    }

    function test_NonceIncrementsAfterPermit() public {
        uint256 privateKey = 0x5678;
        address signer = vm.addr(privateKey);
        address spender = address(this);
        uint256 amount = 5e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Deploy a fresh dToken so signer is the target user
        DToken td = _deployDToken();
        vm.prank(vault);
        td.mint(signer, 10e18);

        uint256 nonceBefore = td.nonces(signer);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, td, signer, spender, amount, nonceBefore, deadline);

        td.permit(signer, spender, amount, deadline, v, r, s);

        assertEq(td.nonces(signer), nonceBefore + 1, "nonce should increment");
        assertEq(td.allowance(signer, spender), amount, "allowance should be set");
    }

    // --- Option B: EIP-712 domain tracks name() (permit correctness) ---
    // These prove the DOMAIN_SEPARATOR follows the live name() set via setTokenInfo,
    // so a standard wallet/frontend that derives the permit domain from token.name()
    // produces a signature that permit() accepts (required for redeemWithPermit / Zapper).

    /// @dev DOMAIN_SEPARATOR uses the live name() ("dWBTC"), NOT the init-time placeholder.
    function test_Permit_DomainSeparatorReflectsCurrentName() public view {
        assertEq(dToken.name(), "dWBTC");
        assertEq(
            dToken.DOMAIN_SEPARATOR(),
            _domainFromName(dToken, "dWBTC"),
            "domain separator must be built from the live name()"
        );
        assertTrue(
            dToken.DOMAIN_SEPARATOR() != _domainFromName(dToken, "DToken Placeholder"),
            "domain separator must NOT use the init-time placeholder name"
        );
    }

    /// @dev A frontend that derives the EIP-712 domain from name() can sign a permit that verifies.
    function test_Permit_FrontendDomainFromName_PermitSucceeds() public {
        uint256 pk = 0xA11CE;
        address signer = vm.addr(pk);
        address spender = address(0xBEEF);
        uint256 amount = 7e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Simulate a standard frontend: build the domain from token.name() (not DOMAIN_SEPARATOR()).
        bytes32 domain = _domainFromName(dToken, dToken.name());
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                spender,
                amount,
                dToken.nonces(signer),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        // If the on-chain domain diverged from name() (Option A), this would revert "invalid signature".
        dToken.permit(signer, spender, amount, deadline, v, r, s);

        assertEq(dToken.allowance(signer, spender), amount, "permit signed from name()-domain must succeed");
        assertEq(dToken.nonces(signer), 1, "nonce should increment after permit");
    }

    /// @dev ERC-5267 eip712Domain() reports the live name() and version "1" (consistent for wallets).
    function test_Permit_eip712DomainReportsCurrentName() public view {
        (, string memory dn, string memory dv,,,,) = dToken.eip712Domain();
        assertEq(dn, dToken.name(), "eip712Domain name must equal name()");
        assertEq(dn, "dWBTC");
        assertEq(dv, "1");
    }

    /// @dev The domain follows name() across setTokenInfo: placeholder before, real name after.
    function test_Permit_DomainTracksNameAcrossSetTokenInfo() public {
        DToken td = _deployDTokenNoTokenInfo();
        assertEq(td.name(), "DToken Placeholder");
        assertEq(
            td.DOMAIN_SEPARATOR(),
            _domainFromName(td, "DToken Placeholder"),
            "before setTokenInfo, domain uses the placeholder name"
        );

        td.setAllowedUnderlying(address(underlying), true);
        td.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        assertEq(td.name(), "dWBTC");
        assertEq(td.DOMAIN_SEPARATOR(), _domainFromName(td, "dWBTC"), "after setTokenInfo, domain tracks the new name");
    }

    // --- initialize() revert tests ---

    function test_InitializeRevertZeroVault() public {
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, address(0), owner);
        vm.expectRevert(DToken.ZeroAddress.selector);
        new ERC1967Proxy(address(dTokenImpl), initData);
    }

    function test_InitializeRevertZeroOwner() public {
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, vault, address(0));
        vm.expectRevert(DToken.ZeroAddress.selector);
        new ERC1967Proxy(address(dTokenImpl), initData);
    }

    // --- setTokenInfo() revert tests ---

    function test_SetTokenInfoRevertAlreadySet() public {
        vm.expectRevert(DToken.TokenInfoAlreadySet.selector);
        dToken.setTokenInfo("X", "X", IERC20MetadataUpgradeable(address(underlying)));
    }

    function test_SetTokenInfoRevertZeroUnderlying() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.ZeroAddress.selector);
        td.setTokenInfo("X", "X", IERC20MetadataUpgradeable(address(0)));
    }

    function test_SetTokenInfoRevertUnderlyingNotAllowed() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.UnderlyingNotAllowed.selector);
        td.setTokenInfo("X", "X", IERC20MetadataUpgradeable(address(underlying)));
    }

    function test_SetTokenInfoRevertUnderlyingEOA() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.NotContract.selector);
        td.setTokenInfo("X", "X", IERC20MetadataUpgradeable(makeAddr("notToken")));
    }

    function test_SetTokenInfoRevertEmptyName() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.EmptyTokenName.selector);
        td.setTokenInfo("", "X", IERC20MetadataUpgradeable(address(underlying)));
    }

    function test_SetTokenInfoRevertEmptySymbol() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.EmptyTokenSymbol.selector);
        td.setTokenInfo("X", "", IERC20MetadataUpgradeable(address(underlying)));
    }

    // With the mint() bind-guard, dTokens cannot be minted before setTokenInfo, so
    // totalSupply() > 0 is impossible while underlying is unbound. This proves the
    // guard (and is why SupplyAlreadyExists in setTokenInfo is now a defensive,
    // unreachable-in-practice check retained for spec alignment, dToken.md §2.1.3).
    function test_MintRevertsBeforeTokenInfoSet() public {
        // Deploy a proxy where vault = address(this) so this contract can call mint()
        DToken tdImpl2 = new DToken();
        bytes memory initData = abi.encodeWithSelector(
            DToken.initialize.selector,
            address(this), // vault = test contract
            owner
        );
        DToken td = DToken(address(new ERC1967Proxy(address(tdImpl2), initData)));

        // underlying not yet bound -> mint must revert (cannot brick setTokenInfo)
        vm.expectRevert(DToken.TokenInfoNotSet.selector);
        td.mint(user, 1e18);
        assertEq(td.totalSupply(), 0);
    }

    function test_SetTokenInfoRevertInvalidUnderlyingDecimals() public {
        DToken td = _deployDTokenNoTokenInfo();
        MockERC20 highDecimals = new MockERC20("High", "HIGH", 19); // > 18
        td.setAllowedUnderlying(address(highDecimals), true);
        vm.expectRevert(DToken.InvalidUnderlyingDecimals.selector);
        td.setTokenInfo("X", "X", IERC20MetadataUpgradeable(address(highDecimals)));
    }

    function test_SetAllowedUnderlying_RevertsOnZeroOrEOA() public {
        DToken td = _deployDTokenNoTokenInfo();

        vm.expectRevert(DToken.ZeroAddress.selector);
        td.setAllowedUnderlying(address(0), true);

        vm.expectRevert(DToken.NotContract.selector);
        td.setAllowedUnderlying(makeAddr("notToken"), true);
    }

    function test_SetAllowedUnderlying_EmitsAndCanRemoveBeforeBind() public {
        DToken td = _deployDTokenNoTokenInfo();

        vm.expectEmit(true, true, true, true, address(td));
        emit DToken.AllowedUnderlyingUpdated(address(underlying), true);
        td.setAllowedUnderlying(address(underlying), true);
        assertTrue(td.allowedUnderlying(address(underlying)), "allowed");

        vm.expectEmit(true, true, true, true, address(td));
        emit DToken.AllowedUnderlyingUpdated(address(underlying), false);
        td.setAllowedUnderlying(address(underlying), false);
        assertFalse(td.allowedUnderlying(address(underlying)), "removed");
    }

    function test_SetAllowedUnderlying_RevertsAfterTokenInfoSet() public {
        vm.expectRevert(DToken.TokenInfoAlreadySet.selector);
        dToken.setAllowedUnderlying(address(underlying), false);
    }

    // --- convertToDToken / convertToUnderlying revert when TokenInfo not set ---

    function test_ConvertToDTokenRevertTokenInfoNotSet() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.TokenInfoNotSet.selector);
        td.convertToDToken(1e8);
    }

    function test_ConvertToUnderlyingRevertTokenInfoNotSet() public {
        DToken td = _deployDTokenNoTokenInfo();
        vm.expectRevert(DToken.TokenInfoNotSet.selector);
        td.convertToUnderlying(1e18);
    }

    // --- Internal helpers ---

    /// @dev Deploy a fresh DToken proxy WITHOUT calling setTokenInfo
    function _deployDTokenNoTokenInfo() internal returns (DToken td) {
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, vault, owner);
        td = DToken(address(new ERC1967Proxy(address(dTokenImpl), initData)));
    }

    function _deployDToken() internal returns (DToken td) {
        bytes memory initData = abi.encodeWithSelector(DToken.initialize.selector, vault, owner);
        td = DToken(address(new ERC1967Proxy(address(dTokenImpl), initData)));
        td.setAllowedUnderlying(address(underlying), true);
        td.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(td);
    }

    function _signPermit(
        uint256 privateKey,
        DToken td,
        address signer,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                spender,
                amount,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", td.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    /// @dev Build the EIP-712 domain separator from a name as a standard frontend would (version "1").
    function _domainFromName(DToken td, string memory nm) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(nm)),
                keccak256(bytes("1")),
                block.chainid,
                address(td)
            )
        );
    }
}
