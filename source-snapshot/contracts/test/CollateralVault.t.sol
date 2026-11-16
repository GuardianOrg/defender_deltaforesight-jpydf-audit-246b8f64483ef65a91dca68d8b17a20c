// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "src/CollateralVaultLens.sol";
import "../src/Interfaces/IDToken.sol";
import "../src/Interfaces/ICollateralVault.sol";
import "../src/Interfaces/IStrategy.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./mocks/MockERC20.sol";

contract FeeOnTransferMockERC20 is MockERC20 {
    uint256 public immutable feeBps;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_)
        MockERC20(name_, symbol_, decimals_)
    {
        feeBps = feeBps_;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = (amount * feeBps) / 10_000;
        uint256 received = amount - fee;
        super._transfer(from, to, received);
        if (fee > 0) {
            super._transfer(from, address(0xdead), fee);
        }
    }
}

contract BlacklistableMockERC20 is MockERC20 {
    mapping(address => bool) public blacklisted;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function setBlacklisted(address account, bool blocked) external {
        blacklisted[account] = blocked;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(!blacklisted[from] && !blacklisted[to], "BLACKLISTED");
        super._transfer(from, to, amount);
    }
}

interface ITransferObservationHook {
    function observeTransferHook() external;
}

contract HookedMockERC20 is MockERC20 {
    address public hookTarget;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function setHookTarget(address target) external {
        hookTarget = target;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        super._transfer(from, to, amount);

        if (to == hookTarget) {
            ITransferObservationHook(to).observeTransferHook();
        }
    }
}

contract VaultTransferObservationReceiver is ITransferObservationHook {
    CollateralVault public immutable vault;

    uint256 public observedPendingWithdrawals;
    uint256 public observedActualLiabilities;
    uint256 public observedBackingRatio;

    constructor(CollateralVault _vault) {
        vault = _vault;
    }

    function observeTransferHook() external override {
        observedPendingWithdrawals = vault.pendingWithdrawals();
        observedActualLiabilities = vault.actualLiabilities();
        observedBackingRatio = vault.backingRatio();
    }
}

contract RevertingValuationStrategy is IStrategy {
    address private immutable underlyingToken;
    bool public revertEstimated;
    bool public revertPrincipal;
    uint256 public estimatedValue;
    uint256 public principalValue;

    constructor(address _underlying) {
        underlyingToken = _underlying;
    }

    function underlying() external view override returns (address) {
        return underlyingToken;
    }

    function setValues(uint256 _estimatedValue, uint256 _principalValue) external {
        estimatedValue = _estimatedValue;
        principalValue = _principalValue;
    }

    function setReverts(bool _revertEstimated, bool _revertPrincipal) external {
        revertEstimated = _revertEstimated;
        revertPrincipal = _revertPrincipal;
    }

    function deposit(uint256, uint256 _receivedAmount) external pure override returns (uint256 deposited) {
        return _receivedAmount;
    }

    function principal() external view override returns (uint256) {
        if (revertPrincipal) revert("principal failed");
        return principalValue;
    }

    function realizedYield() external view override returns (uint256) {
        return estimatedValue > principalValue ? estimatedValue - principalValue : 0;
    }

    function estimatedTotalUnderlying() external view override returns (uint256) {
        if (revertEstimated) revert("estimate failed");
        return estimatedValue;
    }

    function sendToVault(uint256) external pure override returns (uint256 sent) {
        return 0;
    }

    function sendProfitToVault() external pure override returns (uint256 sent) {
        return 0;
    }

    function writeoffPrincipal(uint256) external pure override returns (uint256 writtenOff) {
        return 0;
    }

    function sweepRewardToken(IERC20, uint256) external pure override returns (uint256 swept) {
        return 0;
    }
}

/// @title CollateralVaultTest - Phase 3a (dToken portion) BUCKET A coverage.
/// @notice Exercises deposit / redeem / redeemWithPermit / claim / pause / setters
///         on a fully-activated Vault with NO Strategy registered (buffer holds
///         100% of the underlying). Healthy buffer-shortfall paths use the
///         protected reserve to keep total backing unchanged.
contract CollateralVaultTest is Test {
    /// @dev Reporting views moved to CollateralVaultLens. It is stateless, so one instance
    ///      serves every Vault and the Vault is passed per call.
    CollateralVaultLens private _sharedLens;

    function _lens() internal returns (CollateralVaultLens) {
        if (address(_sharedLens) == address(0)) _sharedLens = new CollateralVaultLens();
        return _sharedLens;
    }

    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant WRITEOFF_ROLE = keccak256("WRITEOFF_ROLE");

    // --- Events re-declared for vm.expectEmit ---
    event Deposited(address indexed user, uint256 underlyingAmount, uint256 dTokenAmount);
    event Redeemed(
        address indexed user,
        address indexed receiver,
        uint256 dTokenAmount,
        uint256 underlyingPaidNow,
        uint256 requestId
    );
    event WithdrawRequested(
        address indexed user, address indexed receiver, uint256 requestId, uint256 amount, uint256 claimableAt
    );
    event WithdrawClaimed(address indexed user, uint256 requestId, uint256 amount);
    event BackstopDeposited(address indexed backstop, uint256 declaredAmount, uint256 received);
    event BackstopReleased(address indexed caller, uint256 amount);
    event DepositPaused();
    event DepositUnpaused();
    event RedeemPaused();
    event RedeemUnpaused();
    event ClaimPaused();
    event ClaimUnpaused();
    event BufferConfigUpdated(uint256 oldTargetBps, uint256 newTargetBps, uint256 oldFloor, uint256 newFloor);
    event WithdrawDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event StrategyValuationRefreshed(
        address indexed strategy, uint256 estimatedUnderlying, uint256 principal, uint256 conservativeValue
    );
    event StrategyValuationRefreshFailed(address indexed strategy, bool estimateAvailable, bool principalAvailable);
    event StrategyValuationCacheInvalidated(address indexed strategy, uint256 oldValue, uint256 oldUpdatedAt);

    DToken public dToken;
    CollateralVault public vault;
    MockERC20 public underlying;

    address public admin;
    address public treasury;
    address public alice;
    uint256 internal aliceKey;
    address public bob;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");

        // 8-decimal underlying (WBTC-like) => decimalMultiplier 1e10.
        underlying = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        DToken dTokenImpl = new DToken();
        CollateralVault vaultImpl = new CollateralVault();

        // Resolve the DToken <-> Vault circular reference by predicting the Vault
        // proxy address (deployed one nonce after the DToken proxy below).
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        dToken = DToken(address(new ERC1967Proxy(address(dTokenImpl), dInit)));
        dToken.setAllowedUnderlying(address(underlying), true);

        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(underlying)), IDToken(address(dToken)), treasury, admin
        );
        vault = CollateralVault(address(new ERC1967Proxy(address(vaultImpl), vInit)));
        assertEq(address(vault), predictedVault, "vault address prediction mismatch");

        dToken.setTokenInfo("dWBTC", "dWBTC", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(dToken);
    }

    // --- Helpers ---

    function _deposit(address user, uint256 amount) internal returns (uint256 dTokenAmount) {
        underlying.mint(user, amount);
        vm.startPrank(user);
        underlying.approve(address(vault), amount);
        dTokenAmount = vault.deposit(amount);
        vm.stopPrank();
    }

    /// @dev Move `_amount` out of the liquid buffer without changing total assets.
    function _protectBufferAmount(CollateralVault targetVault, MockERC20 token, uint256 amount) internal {
        token.mint(bob, amount);
        vm.startPrank(bob);
        token.approve(address(targetVault), amount);
        targetVault.backstopDeposit(amount);
        vm.stopPrank();
        token.burn(address(targetVault), amount);
    }

    function _deployVaultFor(IERC20 token) internal returns (DToken newDToken, CollateralVault newVault) {
        DToken dTokenImpl = new DToken();
        CollateralVault vaultImpl = new CollateralVault();

        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, admin);
        newDToken = DToken(address(new ERC1967Proxy(address(dTokenImpl), dInit)));
        newDToken.setAllowedUnderlying(address(token), true);

        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, token, IDToken(address(newDToken)), treasury, admin
        );
        newVault = CollateralVault(address(new ERC1967Proxy(address(vaultImpl), vInit)));
        assertEq(address(newVault), predictedVault, "vault address prediction mismatch");

        newDToken.setTokenInfo("dFEE", "dFEE", IERC20MetadataUpgradeable(address(token)));
        activateDTokenForTest(newDToken);
    }

    /// @dev Build the dToken EIP-712 permit domain from `name()` as a standard
    ///      frontend would, and sign it. This makes redeemWithPermit an
    ///      end-to-end proof that the Option B permit fix works in the Vault path.
    function _signPermitFromName(uint256 pk, address owner_, address spender, uint256 amount, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(dToken.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(dToken)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner_,
                spender,
                amount,
                dToken.nonces(owner_),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (v, r, s) = vm.sign(pk, digest);
    }

    // =================================================================
    //                          deposit
    // =================================================================

    function test_Deposit_MintsDTokens() public {
        uint256 amount = 10e8; // 10 WBTC
        underlying.mint(alice, amount);
        vm.startPrank(alice);
        underlying.approve(address(vault), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposited(alice, amount, 10e18);
        uint256 minted = vault.deposit(amount);
        vm.stopPrank();

        assertEq(minted, 10e18, "8dec->18dec mint");
        assertEq(dToken.balanceOf(alice), 10e18);
        assertEq(vault.bufferBalance(), amount, "buffer holds 100% (no strategies)");
        assertEq(vault.totalUnderlying(), amount);
    }

    function test_Deposit_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_Deposit_MintsFromActualReceivedAmount() public {
        FeeOnTransferMockERC20 feeToken = new FeeOnTransferMockERC20("Fee Token", "FEE", 8, 1_000);
        (DToken feeDToken, CollateralVault feeVault) = _deployVaultFor(IERC20(address(feeToken)));

        feeToken.mint(alice, 10e8);
        vm.startPrank(alice);
        feeToken.approve(address(feeVault), 10e8);
        vm.expectEmit(true, true, true, true, address(feeVault));
        emit Deposited(alice, 9e8, 9e18);
        uint256 minted = feeVault.deposit(10e8);
        vm.stopPrank();

        assertEq(minted, 9e18, "minted from actual received amount");
        assertEq(feeDToken.balanceOf(alice), 9e18);
        assertEq(feeVault.bufferBalance(), 9e8);
    }

    // =================================================================
    //                          redeem
    // =================================================================

    function test_Redeem_ImmediateWhenBufferSufficient() public {
        _deposit(alice, 10e8);

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeem(10e18, alice);

        assertEq(received, 10e8, "full underlying returned immediately");
        assertEq(requestId, 0, "no request when buffer sufficient");
        assertEq(dToken.balanceOf(alice), 0, "dToken burned");
        assertEq(underlying.balanceOf(alice), 10e8);
        assertEq(vault.bufferBalance(), 0);
    }

    function test_Redeem_FeeOnTransferReturnsReceiverBalanceDelta() public {
        FeeOnTransferMockERC20 feeToken = new FeeOnTransferMockERC20("Fee Token", "FEE", 8, 1_000);
        (DToken feeDToken, CollateralVault feeVault) = _deployVaultFor(IERC20(address(feeToken)));

        feeToken.mint(alice, 10e8);
        vm.startPrank(alice);
        feeToken.approve(address(feeVault), 10e8);
        uint256 minted = feeVault.deposit(10e8);

        uint256 receiverBalanceBefore = feeToken.balanceOf(alice);
        (uint256 received, uint256 requestId) = feeVault.redeem(minted, alice);
        vm.stopPrank();

        uint256 receiverDelta = feeToken.balanceOf(alice) - receiverBalanceBefore;
        assertEq(received, receiverDelta, "return matches receiver delta");
        assertEq(received, 81e7, "outbound transfer fee excluded");
        assertEq(requestId, 0, "nominal buffer was sufficient");
        assertEq(feeDToken.balanceOf(alice), 0, "dToken burned");
    }

    function test_Redeem_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.redeem(0, alice);
    }

    function test_Redeem_RevertsOnNonExactDTokenDust() public {
        _deposit(alice, 1e8);

        vm.prank(alice);
        vm.expectRevert(CollateralVault.InvalidDTokenAmount.selector);
        vault.redeem(1, alice);

        assertEq(dToken.balanceOf(alice), 1e18, "dust redeem did not burn");
        assertEq(vault.pendingWithdrawals(), 0, "no dust request");
    }

    function test_RedeemWithPermit_RevertsOnNonExactDTokenDustBeforePermit() public {
        _deposit(alice, 1e8);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(CollateralVault.InvalidDTokenAmount.selector);
        vault.redeemWithPermit(1, deadline, 0, bytes32(0), bytes32(0), alice);

        assertEq(dToken.nonces(alice), 0, "permit nonce not consumed");
        assertEq(dToken.balanceOf(alice), 1e18, "dust redeem did not burn");
        assertEq(vault.pendingWithdrawals(), 0, "no dust request");
    }

    function test_Redeem_USDC6QueuesOnlyExactBaseUnits() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        (DToken usdcDToken, CollateralVault usdcVault) = _deployVaultFor(IERC20(address(usdc)));

        usdc.mint(alice, 1e6);
        vm.startPrank(alice);
        usdc.approve(address(usdcVault), 1e6);
        usdcVault.deposit(1e6);
        vm.stopPrank();

        _protectBufferAmount(usdcVault, usdc, 1e6);

        vm.prank(alice);
        vm.expectRevert(CollateralVault.InvalidDTokenAmount.selector);
        usdcVault.redeem(1, bob);

        vm.prank(alice);
        (uint256 received, uint256 requestId) = usdcVault.redeem(1e12, bob);

        (address owner, uint256 amount,, bool claimed) = usdcVault.withdrawRequests(requestId);
        assertEq(received, 0, "no immediate buffer payout");
        assertEq(owner, bob, "request owner is receiver");
        assertEq(amount, 1, "1e12 dToken maps to one USDC base unit");
        assertFalse(claimed, "request remains open");
        assertEq(usdcVault.pendingWithdrawals(), 1, "queue tracks underlying units");
        assertEq(usdcDToken.balanceOf(alice), 1e18 - 1e12, "only exact amount burned");
    }

    function test_Redeem_BlacklistedReceiverRevertsWithoutBurnOrRequest() public {
        BlacklistableMockERC20 usdc = new BlacklistableMockERC20("USD Coin", "USDC", 6);
        (DToken usdcDToken, CollateralVault usdcVault) = _deployVaultFor(IERC20(address(usdc)));

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(usdcVault), 100e6);
        usdcVault.deposit(100e6);
        vm.stopPrank();

        usdc.setBlacklisted(bob, true);

        vm.prank(alice);
        vm.expectRevert();
        usdcVault.redeem(100e18, bob);

        assertEq(usdcDToken.balanceOf(alice), 100e18, "burn rolled back");
        assertEq(usdcVault.pendingWithdrawals(), 0, "no queued request");
        assertEq(usdcVault.bufferBalance(), 100e6, "buffer unchanged");
    }

    function test_Claim_BlacklistedOwnerRevertsWithoutConsumingRequest() public {
        BlacklistableMockERC20 usdc = new BlacklistableMockERC20("USD Coin", "USDC", 6);
        (, CollateralVault usdcVault) = _deployVaultFor(IERC20(address(usdc)));

        usdc.mint(alice, 100e6);
        vm.startPrank(alice);
        usdc.approve(address(usdcVault), 100e6);
        usdcVault.deposit(100e6);
        vm.stopPrank();

        _protectBufferAmount(usdcVault, usdc, 100e6);

        vm.prank(alice);
        (, uint256 requestId) = usdcVault.redeem(100e18, bob);
        usdcVault.releaseBackstopToBuffer(100e6);
        usdc.setBlacklisted(bob, true);
        vm.warp(block.timestamp + usdcVault.withdrawDelay() + 1);

        uint256 triggerBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        usdcVault.claim(requestId);

        (address owner, uint256 amount,, bool claimed) = usdcVault.withdrawRequests(requestId);
        assertEq(owner, bob, "request owner retained");
        assertEq(amount, 100e6, "queued amount retained");
        assertFalse(claimed, "claim flag rolled back");
        assertEq(usdcVault.pendingWithdrawals(), 100e6, "pending counter retained");
        assertEq(usdc.balanceOf(alice), triggerBalanceBefore, "permissionless trigger cannot receive funds");
    }

    function test_Redeem_ZeroReceiverRevertsBeforeBurnOrRequest() public {
        _deposit(alice, 100e8);

        vm.prank(alice);
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.redeem(100e18, address(0));

        assertEq(dToken.balanceOf(alice), 100e18, "dToken not burned");
        assertEq(vault.pendingWithdrawals(), 0, "no unclaimable request");
        assertEq(vault.nextRequestId(), 1, "request id unchanged");
    }

    function test_Redeem_ShortfallCreatesRequest() public {
        _deposit(alice, 100e8); // buffer 100e8, supply 100e18

        _protectBufferAmount(vault, underlying, 70e8);

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeem(100e18, alice);

        assertEq(received, 30e8, "first-come-takes-all of the remaining buffer");
        assertEq(requestId, 1);
        assertEq(vault.pendingWithdrawals(), 70e8);
        assertEq(dToken.balanceOf(alice), 0, "full dToken burned");

        (address owner, uint256 amt, uint256 claimableAt, bool claimed) = vault.withdrawRequests(1);
        assertEq(owner, alice);
        assertEq(amt, 70e8);
        assertEq(claimableAt, block.timestamp + 1 days);
        assertEq(claimed, false);
    }

    function test_Redeem_QueuesShortfallBeforePartialBufferTransferHook() public {
        HookedMockERC20 hooked = new HookedMockERC20("Hooked Wrapped Bitcoin", "hWBTC", 8);
        (DToken hookedDToken, CollateralVault hookedVault) = _deployVaultFor(IERC20(address(hooked)));
        VaultTransferObservationReceiver receiver = new VaultTransferObservationReceiver(hookedVault);
        hooked.setHookTarget(address(receiver));

        hooked.mint(alice, 100e8);
        vm.startPrank(alice);
        hooked.approve(address(hookedVault), 100e8);
        hookedVault.deposit(100e8);
        vm.stopPrank();

        _protectBufferAmount(hookedVault, hooked, 70e8);

        vm.prank(alice);
        (uint256 received, uint256 requestId) = hookedVault.redeem(100e18, address(receiver));

        assertEq(received, 30e8, "partial buffer paid immediately");
        assertEq(requestId, 1, "shortfall request created");
        assertEq(hookedDToken.balanceOf(alice), 0, "dToken burned");
        assertEq(hookedVault.pendingWithdrawals(), 70e8, "pending retained after hook");
        assertEq(receiver.observedPendingWithdrawals(), 70e8, "pending visible during transfer hook");
        assertEq(receiver.observedActualLiabilities(), 70e8, "liabilities visible during transfer hook");
        assertEq(receiver.observedBackingRatio(), 1e18, "queue remains fully backed during transfer hook");
    }

    // =================================================================
    //                       redeemWithPermit
    // =================================================================

    /// @notice End-to-end proof of the Option B permit fix in the Vault path:
    ///         a permit whose EIP-712 domain is derived from dToken.name()
    ///         is accepted, the dToken is pulled+burned, and underlying is
    ///         returned in a single tx (the Zapper permit path).
    function test_RedeemWithPermit_RoundTrip() public {
        _deposit(alice, 5e8); // alice holds 5e18 dWBTC
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermitFromName(aliceKey, alice, address(vault), 5e18, deadline);

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeemWithPermit(5e18, deadline, v, r, s, alice);

        assertEq(received, 5e8, "underlying returned via permit-redeem");
        assertEq(requestId, 0);
        assertEq(dToken.balanceOf(alice), 0, "dToken pulled and burned");
        assertEq(dToken.totalSupply(), 0);
        assertEq(underlying.balanceOf(alice), 5e8);
    }

    function test_RedeemWithPermit_ToleratesPermitFrontRunWhenAllowanceExists() public {
        _deposit(alice, 5e8); // alice holds 5e18 dWBTC
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermitFromName(aliceKey, alice, address(vault), 5e18, deadline);

        dToken.permit(alice, address(vault), 5e18, deadline, v, r, s);
        assertEq(dToken.nonces(alice), 1, "front-run permit consumed nonce");
        assertEq(dToken.allowance(alice, address(vault)), 5e18, "permit left redeem allowance");

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeemWithPermit(5e18, deadline, v, r, s, alice);

        assertEq(received, 5e8, "underlying returned after consumed permit");
        assertEq(requestId, 0);
        assertEq(dToken.balanceOf(alice), 0, "dToken pulled and burned");
        assertEq(dToken.allowance(alice, address(vault)), 0, "allowance consumed");
        assertEq(underlying.balanceOf(alice), 5e8);
    }

    function test_RedeemWithPermit_RevertsWhenPermitFailsAndAllowanceIsMissing() public {
        _deposit(alice, 5e8);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(CollateralVault.PermitFailed.selector);
        vault.redeemWithPermit(5e18, deadline, 0, bytes32(0), bytes32(0), alice);

        assertEq(dToken.nonces(alice), 0, "permit nonce not consumed");
        assertEq(dToken.balanceOf(alice), 5e18, "dToken not burned");
        assertEq(dToken.allowance(alice, address(vault)), 0, "allowance unchanged");
        assertEq(underlying.balanceOf(alice), 0, "underlying not returned");
    }

    function test_RedeemWithPermit_ZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.redeemWithPermit(0, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), alice);
    }

    function test_RedeemWithPermit_ZeroReceiverRevertsBeforePermit() public {
        _deposit(alice, 5e8);

        vm.prank(alice);
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.redeemWithPermit(5e18, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), address(0));

        assertEq(dToken.nonces(alice), 0, "permit nonce not consumed");
        assertEq(dToken.balanceOf(alice), 5e18, "dToken not burned");
    }

    // =================================================================
    //                          claim
    // =================================================================

    /// @dev Create a pending request, then refill the buffer (as an ALLOCATOR
    ///      would in Phase 3b) and claim after the delay.
    function _seedRequest(address user, uint256 depositAmt, uint256 keepInBuffer)
        internal
        returns (uint256 requestId, uint256 owed)
    {
        _deposit(user, depositAmt);
        _protectBufferAmount(vault, underlying, depositAmt - keepInBuffer);
        // Precompute the dToken amount BEFORE pranking: evaluating an external
        // call inside the redeem args would otherwise consume the vm.prank.
        uint256 dAmt = dToken.convertToDToken(depositAmt);
        vm.prank(user);
        (, requestId) = vault.redeem(dAmt, user);
        owed = depositAmt - keepInBuffer;
    }

    function test_Claim_AfterRefillAndDelay_Succeeds() public {
        (uint256 id, uint256 owed) = _seedRequest(alice, 100e8, 30e8); // owed 70e8

        vault.releaseBackstopToBuffer(owed);
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit WithdrawClaimed(alice, id, owed);
        uint256 claimed = vault.claim(id);

        assertEq(claimed, owed);
        assertEq(underlying.balanceOf(alice) - balBefore, owed);
        assertEq(vault.pendingWithdrawals(), 0);
    }

    function test_Claim_BeforeDelay_Reverts() public {
        (uint256 id,) = _seedRequest(alice, 100e8, 30e8);
        vm.prank(alice);
        vm.expectRevert(CollateralVault.RequestNotReady.selector);
        vault.claim(id);
    }

    /// @dev CEI: buffer sufficiency is checked before the request is marked
    ///      claimed, so an insufficient-buffer revert leaves the request claimable.
    function test_Claim_InsufficientBuffer_Reverts_ThenSucceeds() public {
        (uint256 id, uint256 owed) = _seedRequest(alice, 100e8, 30e8); // owed 70e8
        vm.warp(block.timestamp + 1 days + 1);

        // Protected reserve is not claim liquidity -> revert, request NOT consumed.
        vm.prank(alice);
        vm.expectRevert(CollateralVault.InsufficientBuffer.selector);
        vault.claim(id);

        (,,, bool claimedFlag) = vault.withdrawRequests(id);
        assertEq(claimedFlag, false, "request must remain claimable after revert");

        vault.releaseBackstopToBuffer(owed);
        vm.prank(alice);
        assertEq(vault.claim(id), owed);
    }

    function test_Claim_PermissionlessTriggerPaysContractRequestOwner() public {
        VaultTransferObservationReceiver receiver = new VaultTransferObservationReceiver(vault);
        (uint256 id, uint256 owed) = _seedRequest(address(receiver), 100e8, 30e8);
        uint256 receiverBalanceBefore = underlying.balanceOf(address(receiver));
        vault.releaseBackstopToBuffer(owed);
        vm.warp(block.timestamp + 1 days + 1);

        uint256 callerBalanceBefore = underlying.balanceOf(bob);
        vm.expectEmit(true, true, false, true, address(vault));
        emit WithdrawClaimed(address(receiver), id, owed);
        vm.prank(bob);
        uint256 claimed = vault.claim(id);

        assertEq(claimed, owed, "full request claimed");
        assertEq(
            underlying.balanceOf(address(receiver)) - receiverBalanceBefore,
            owed,
            "request owner receives the underlying"
        );
        assertEq(underlying.balanceOf(bob), callerBalanceBefore, "permissionless caller cannot redirect funds");
        assertEq(vault.pendingWithdrawals(), 0, "pending liability cleared");
    }

    function test_Claim_FrontRunSettlementMakesOwnerRetryIdempotent() public {
        (uint256 id, uint256 owed) = _seedRequest(alice, 100e8, 30e8);
        vault.releaseBackstopToBuffer(owed);
        vm.warp(block.timestamp + 1 days + 1);

        uint256 aliceBalanceBefore = underlying.balanceOf(alice);
        uint256 bobBalanceBefore = underlying.balanceOf(bob);
        vm.prank(bob);
        assertEq(vault.claim(id), owed, "front-run settles the request");
        assertEq(underlying.balanceOf(alice) - aliceBalanceBefore, owed, "recorded owner receives payout");
        assertEq(underlying.balanceOf(bob), bobBalanceBefore, "front-runner receives nothing");

        uint256 aliceBalanceAfterSettlement = underlying.balanceOf(alice);
        vm.recordLogs();
        vm.prank(alice);
        assertEq(vault.claim(id), 0, "owner retry is idempotent");
        Vm.Log[] memory retryLogs = vm.getRecordedLogs();

        assertEq(underlying.balanceOf(alice), aliceBalanceAfterSettlement, "no second payout");
        assertEq(retryLogs.length, 0, "no second claim event");
        assertEq(vault.pendingWithdrawals(), 0, "liability settled exactly once");
        (,,, bool claimedFlag) = vault.withdrawRequests(id);
        assertTrue(claimedFlag, "request remains settled");
    }

    function test_Claim_UnknownId_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(CollateralVault.RequestNotFound.selector);
        vault.claim(999);
    }

    function test_MultiplePendingRequests_OrderedClaim() public {
        // alice opens two requests; both claimable independently.
        _deposit(alice, 100e8);
        _protectBufferAmount(vault, underlying, 100e8);
        vm.startPrank(alice);
        (, uint256 id1) = vault.redeem(40e18, alice); // owed 40e8
        (, uint256 id2) = vault.redeem(60e18, alice); // owed 60e8
        vm.stopPrank();
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(vault.pendingWithdrawals(), 100e8);

        vm.warp(block.timestamp + 1 days + 1);

        // Claim id2 first (order-independent), then id1.
        vault.releaseBackstopToBuffer(60e8);
        vm.prank(alice);
        assertEq(vault.claim(id2), 60e8);

        vault.releaseBackstopToBuffer(40e8);
        vm.prank(alice);
        assertEq(vault.claim(id1), 40e8);

        assertEq(vault.pendingWithdrawals(), 0);
    }

    // =================================================================
    //                    backstopDeposit / backingRatio
    // =================================================================

    function test_BackingRatio_ZeroLiabilitiesAndHealthyReturnOne() public {
        assertEq(vault.backingRatio(), 1e18, "zero liabilities -> 1");

        _deposit(alice, 100e8);
        assertEq(vault.backingRatio(), 1e18, "fully backed -> 1");
    }

    function test_BackingRatio_ImpairmentReturnsAssetOverLiability() public {
        _deposit(alice, 100e8);

        // Simulate an unrecovered loss / impairment in the Vault buffer.
        deal(address(underlying), address(vault), 60e8);

        assertEq(vault.totalUnderlying(), 60e8);
        assertEq(dToken.convertToUnderlying(dToken.totalSupply()), 100e8);
        assertEq(vault.backingRatio(), 6e17, "60 / 100");
    }

    function test_UserFlows_FailClosedWhenUnderbacked_AndResumeAfterBackstopRepair() public {
        _deposit(alice, 100e8);
        _protectBufferAmount(vault, underlying, 100e8);

        vm.prank(alice);
        (, uint256 requestId) = vault.redeem(40e18, alice);
        deal(address(underlying), address(vault), 80e8);

        uint256 supplyBefore = dToken.totalSupply();
        uint256 aliceDTokenBefore = dToken.balanceOf(alice);
        uint256 pendingBefore = vault.pendingWithdrawals();
        uint256 nextRequestIdBefore = vault.nextRequestId();
        bytes memory underbacked =
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(8e17), uint256(1e18));

        underlying.mint(bob, 20e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 20e8);
        vm.expectRevert(underbacked);
        vault.deposit(20e8);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(underbacked);
        vault.redeem(20e18, alice);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermitFromName(aliceKey, alice, address(vault), 20e18, deadline);
        vm.startPrank(alice);
        vm.expectRevert(underbacked);
        vault.redeemWithPermit(20e18, deadline, v, r, s, alice);
        vm.stopPrank();

        assertEq(underlying.balanceOf(bob), 20e8, "deposit did not transfer underlying");
        assertEq(dToken.totalSupply(), supplyBefore, "failed user flows did not change supply");
        assertEq(dToken.balanceOf(alice), aliceDTokenBefore, "failed redemptions did not burn");
        assertEq(dToken.nonces(alice), 0, "solvency check ran before permit");
        assertEq(dToken.allowance(alice, address(vault)), 0, "permit allowance unchanged");
        assertEq(vault.pendingWithdrawals(), pendingBefore, "queue liabilities unchanged");
        assertEq(vault.nextRequestId(), nextRequestIdBefore, "no new queue entry");

        vault.releaseBackstopToBuffer(60e8);
        vm.warp(block.timestamp + vault.withdrawDelay() + 1);
        vm.startPrank(alice);
        vm.expectRevert(underbacked);
        vault.claim(requestId);
        vm.stopPrank();

        (,,, bool claimedBeforeRepair) = vault.withdrawRequests(requestId);
        assertFalse(claimedBeforeRepair, "failed claim did not consume request");
        assertEq(vault.pendingWithdrawals(), pendingBefore, "failed claim retained liability");

        vm.startPrank(bob);
        vault.backstopDeposit(20e8);
        vm.stopPrank();
        assertEq(vault.backingRatio(), 1e18, "backstop restored full backing");

        vm.prank(alice);
        assertEq(vault.claim(requestId), 40e8, "claim resumed after repair");
        assertEq(vault.pendingWithdrawals(), 0, "claim liability cleared");
        assertEq(vault.backingRatio(), 1e18, "settlement preserved full backing");
    }

    function test_ActualLiabilities_RoundsUpDTokenDust() public {
        // Force a legacy / migration dust supply that cannot be created by the
        // current mint path, but should still be conservatively valued.
        deal(address(dToken), bob, 1, true);
        assertEq(dToken.totalSupply(), 1, "only dToken dust remains");
        assertEq(dToken.convertToUnderlying(dToken.totalSupply()), 0, "floor conversion would understate");
        assertEq(vault.actualLiabilities(), 1, "liability view rounds dust up to one base unit");
    }

    function test_BackingRatio_IncludesPendingWithdrawals() public {
        _seedRequest(alice, 100e8, 30e8);
        deal(address(underlying), address(vault), 30e8);

        assertEq(dToken.totalSupply(), 0, "dToken burned into pending claim");
        assertEq(vault.pendingWithdrawals(), 70e8);
        assertEq(vault.totalUnderlying(), 30e8);
        uint256 expectedRatio = (uint256(30e8) * 1e18) / uint256(70e8);
        assertEq(vault.backingRatio(), expectedRatio, "30 / 70 pending liability");
    }

    function test_BackingOpsViews_ReportShortfallAndRepairAmounts() public {
        _deposit(alice, 100e8);
        deal(address(underlying), address(vault), 60e8);

        assertEq(vault.actualLiabilities(), 100e8, "dToken liabilities");
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 40e8, "full repair shortfall");
        assertEq(_lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 1e18), 40e8, "repair to 100%");
        assertEq(_lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 8e17), 20e8, "repair to 80%");
        assertEq(_lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 6e17), 0, "already at 60%");
        assertEq(_lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 0), 0, "zero target");
    }

    function test_BackingOpsViews_IncludePendingWithdrawalsAndRoundUp() public {
        _seedRequest(alice, 100e8, 30e8);
        deal(address(underlying), address(vault), 30e8);

        assertEq(vault.actualLiabilities(), 70e8, "pending liabilities");
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 40e8, "pending shortfall");

        uint256 target = 5e17 + 1;
        uint256 requiredAssets = (uint256(70e8) * target + 1e18 - 1) / 1e18;
        assertEq(
            _lens().backstopRequiredForRatio(ICollateralVault(address(vault)), target),
            requiredAssets - 30e8,
            "ceil repair amount"
        );
    }

    function test_BackingOpsViews_TargetAboveOneReverts() public {
        CollateralVaultLens lens = _lens();
        vm.expectRevert(CollateralVaultLens.InvalidBackingTarget.selector);
        lens.backstopRequiredForRatio(ICollateralVault(address(vault)), 1e18 + 1);
    }

    function test_BackingOpsViews_StrategyValuationRevertUsesFreshCacheThenExpires() public {
        _deposit(alice, 100e8);

        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        assertEq(vault.totalUnderlying(), 150e8, "healthy strategy included");

        strategy.setReverts(true, false);
        assertEq(vault.totalUnderlying(), 150e8, "estimated revert -> fresh cache");
        assertEq(vault.backingRatio(), 1e18, "buffer still fully backs liabilities");

        deal(address(underlying), address(vault), 60e8);
        assertEq(
            _lens().backingShortfall(ICollateralVault(address(vault))), 0, "fresh cache prevents transient shortfall"
        );
        assertEq(
            _lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 1e18),
            0,
            "fresh cache prevents transient repair need"
        );

        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);
        assertEq(vault.totalUnderlying(), 60e8, "expired cache -> strategy zero");
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 40e8, "expired cache exposes shortfall");
        assertEq(
            _lens().backstopRequiredForRatio(ICollateralVault(address(vault)), 1e18), 40e8, "expired cache needs repair"
        );

        strategy.setReverts(false, false);
        assertTrue(vault.refreshStrategyValuation(IStrategy(address(strategy))), "refresh restored cache");
        strategy.setReverts(false, true);
        assertEq(vault.totalUnderlying(), 110e8, "principal revert -> fresh cache");
        assertEq(vault.backingRatio(), 1e18, "fresh cache keeps branch fully backed");
    }

    function test_UserFlowSolvencyGate_IgnoresFreshCacheAndRecoversFromConfirmedAssets() public {
        _deposit(alice, 100e8);

        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        strategy.setReverts(true, false);
        deal(address(underlying), address(vault), 60e8);

        (uint256 pricingRatio, bool pricingAvailable) = vault.backingRatioForPricing();
        assertEq(pricingRatio, 1e18, "fresh cache keeps pricing ratio whole");
        assertTrue(pricingAvailable, "fresh cache remains available to pricing");

        underlying.mint(bob, 42e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 42e8);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralVault.BackingRatioBelowMinimum.selector, uint256(6e17), uint256(1e18))
        );
        vault.deposit(1e8);
        vm.stopPrank();

        RevertingValuationStrategy confirmedStrategy = new RevertingValuationStrategy(address(underlying));
        confirmedStrategy.setValues(40e8, 40e8);
        vault.addToWhitelist(address(confirmedStrategy));
        vault.addStrategy(IStrategy(address(confirmedStrategy)), 0, 0);

        vm.startPrank(bob);
        assertEq(vault.deposit(1e8), 1e18, "later live Strategy can prove full backing");

        confirmedStrategy.setReverts(true, false);
        vault.backstopDeposit(40e8);
        assertEq(vault.deposit(1e8), 1e18, "confirmed raw backing restores user-flow liveness");
        vm.stopPrank();

        assertEq(dToken.balanceOf(bob), 2e18, "deposits resumed without cached valuation");
        assertEq(underlying.balanceOf(bob), 0, "repair and deposit consumed only approved amounts");
    }

    function test_BackingOpsViews_ZeroMaxAgeDisablesOnlyFallbackAndConfigCorrectionRecovers() public {
        _deposit(alice, 100e8);

        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        vault.setStrategyValuationMaxAge(0);
        assertEq(vault.totalUnderlying(), 150e8, "zero TTL still uses live valuation");

        strategy.setReverts(true, false);
        deal(address(underlying), address(vault), 60e8);
        assertEq(vault.totalUnderlying(), 60e8, "zero TTL fails closed to zero strategy value");
        assertEq(vault.backingRatio(), 6e17, "solvency view returns conservative ratio without reverting");
        assertEq(
            _lens().backingShortfall(ICollateralVault(address(vault))), 40e8, "disabled fallback exposes shortfall"
        );

        vault.setStrategyValuationMaxAge(1 days);
        assertEq(vault.totalUnderlying(), 110e8, "nonzero TTL restores the existing fresh cache");
        assertEq(vault.backingRatio(), 1e18, "corrected TTL restores fallback liveness");
    }

    function test_StrategyValuationRefresh_EmitsSuccessAndFailure() public {
        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 80e8);
        vault.addToWhitelist(address(strategy));

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationRefreshed(address(strategy), 50e8, 80e8, 50e8);
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        strategy.setReverts(true, false);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationRefreshFailed(address(strategy), false, true);
        assertFalse(vault.refreshStrategyValuation(IStrategy(address(strategy))), "estimate failure reported");

        strategy.setReverts(false, true);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationRefreshFailed(address(strategy), true, false);
        assertFalse(vault.refreshStrategyValuation(IStrategy(address(strategy))), "principal failure reported");

        strategy.setReverts(false, false);
        strategy.setValues(70e8, 60e8);
        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationRefreshed(address(strategy), 70e8, 60e8, 60e8);
        assertTrue(vault.refreshStrategyValuation(IStrategy(address(strategy))), "success reported");
    }

    function test_BackingOpsViews_WriteoffRoleCanInvalidateFreshStrategyCacheOnValuationFailure() public {
        _deposit(alice, 100e8);

        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        strategy.setReverts(true, false);
        deal(address(underlying), address(vault), 60e8);
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 0, "fresh cache masks transient shortfall");

        (uint256 cachedValue, uint256 cacheUpdatedAt, bool initialized) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertTrue(initialized, "cache initialized");
        assertEq(cachedValue, 50e8, "cache starts at conservative value");

        address writeoff = makeAddr("writeoff");
        vault.grantRole(WRITEOFF_ROLE, writeoff);

        vm.prank(writeoff);
        vm.expectRevert(CollateralVault.StrategyWriteoffNotReady.selector);
        vault.invalidateStrategyValuationCache(IStrategy(address(strategy)));

        vault.pauseAllocation();

        vm.expectEmit(true, false, false, true, address(vault));
        emit StrategyValuationCacheInvalidated(address(strategy), cachedValue, cacheUpdatedAt);
        vm.prank(writeoff);
        vault.invalidateStrategyValuationCache(IStrategy(address(strategy)));

        assertEq(vault.totalUnderlying(), 60e8, "cache invalidation removes stale strategy backing");
        assertEq(_lens().backingShortfall(ICollateralVault(address(vault))), 40e8, "shortfall visible immediately");
        assertEq(vault.backingRatio(), 6e17, "backing ratio repriced conservatively");

        (uint256 cachedAfter, uint256 updatedAfter, bool initializedAfter) =
            vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertEq(cachedAfter, 0, "cache value cleared");
        assertEq(updatedAfter, 0, "cache timestamp cleared");
        assertFalse(initializedAfter, "cache deinitialized");
    }

    function test_BackingOpsViews_GuardianCannotInvalidateStrategyCache() public {
        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        address guardian = makeAddr("guardianOnly");
        vault.grantRole(GUARDIAN_ROLE, guardian);

        vm.prank(guardian);
        vm.expectRevert();
        vault.invalidateStrategyValuationCache(IStrategy(address(strategy)));

        (uint256 cachedValue,, bool initialized) = vault.strategyValuationCaches(IStrategy(address(strategy)));
        assertTrue(initialized, "guardian did not clear cache");
        assertEq(cachedValue, 50e8, "cache still intact");
    }

    function test_GetStrategyStatuses_FailSoftOnValuationRevert() public {
        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 100e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 200e8);

        ICollateralVault.StrategyStatus[] memory statuses =
            _lens().getStrategyStatuses(ICollateralVault(address(vault)));
        assertEq(statuses.length, 1, "one strategy");
        assertTrue(statuses[0].estimateAvailable, "estimate available");
        assertTrue(statuses[0].principalAvailable, "principal available");
        assertEq(statuses[0].estimatedUnderlying, 50e8, "estimated");
        assertEq(statuses[0].principal, 100e8, "principal");
        assertEq(statuses[0].conservativeValue, 50e8, "conservative");
        assertEq(statuses[0].estimatedGain, 0, "no gain");
        assertEq(statuses[0].estimatedLoss, 50e8, "loss");
        assertEq(statuses[0].capRemaining, 150e8, "cap remaining");

        strategy.setReverts(true, false);
        statuses = _lens().getStrategyStatuses(ICollateralVault(address(vault)));
        assertFalse(statuses[0].estimateAvailable, "estimate unavailable");
        assertTrue(statuses[0].principalAvailable, "principal still available");
        assertEq(statuses[0].estimatedUnderlying, 0, "failed estimate zeroed");
        assertEq(statuses[0].principal, 100e8, "principal retained");
        assertEq(statuses[0].conservativeValue, 50e8, "fresh cache used");
        assertEq(statuses[0].cachedConservativeValue, 50e8, "cache value");
        assertTrue(statuses[0].usingCachedConservativeValue, "cache fallback flagged");
        assertTrue(statuses[0].cacheAvailable, "cache available");
        assertFalse(statuses[0].cacheStale, "cache fresh");
        assertEq(statuses[0].estimatedLoss, 0, "loss not inferred without estimate");
        assertEq(statuses[0].capRemaining, 0, "cap not inferred without estimate");

        strategy.setReverts(false, true);
        statuses = _lens().getStrategyStatuses(ICollateralVault(address(vault)));
        assertTrue(statuses[0].estimateAvailable, "estimate restored");
        assertFalse(statuses[0].principalAvailable, "principal unavailable");
        assertEq(statuses[0].estimatedUnderlying, 50e8, "estimate retained");
        assertEq(statuses[0].principal, 0, "failed principal zeroed");
        assertEq(statuses[0].conservativeValue, 50e8, "fresh cache used");
        assertTrue(statuses[0].usingCachedConservativeValue, "cache fallback flagged");
        assertEq(statuses[0].capRemaining, 150e8, "cap uses estimate only");

        vm.warp(block.timestamp + vault.strategyValuationMaxAge() + 1);
        statuses = _lens().getStrategyStatuses(ICollateralVault(address(vault)));
        assertEq(statuses[0].conservativeValue, 0, "expired cache not used");
        assertFalse(statuses[0].cacheAvailable, "expired cache unavailable");
        assertTrue(statuses[0].cacheStale, "expired cache flagged stale");
    }

    function test_TransferYieldToTreasury_DoesNotSpendAgainstCachedStrategyValue() public {
        _deposit(alice, 100e8);

        RevertingValuationStrategy strategy = new RevertingValuationStrategy(address(underlying));
        strategy.setValues(50e8, 50e8);
        vault.addToWhitelist(address(strategy));
        vault.addStrategy(IStrategy(address(strategy)), 0, 0);

        strategy.setReverts(true, false);

        uint256 transferred = vault.transferYieldToTreasury();
        assertEq(transferred, 0, "cached strategy value is not treasury surplus");
        assertEq(underlying.balanceOf(treasury), 0, "treasury not paid from buffer");
    }

    function test_BackstopDeposit_RepairsBackingWithoutMintingDToken() public {
        _deposit(alice, 100e8);
        deal(address(underlying), address(vault), 60e8);

        uint256 supplyBefore = dToken.totalSupply();
        uint256 aliceBalanceBefore = dToken.balanceOf(alice);
        uint256 pendingBefore = vault.pendingWithdrawals();
        assertEq(vault.backingRatio(), 6e17, "impaired before repair");

        underlying.mint(bob, 40e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 40e8);
        vm.expectEmit(true, true, true, true);
        emit BackstopDeposited(bob, 40e8, 40e8);
        uint256 received = vault.backstopDeposit(40e8);
        vm.stopPrank();

        assertEq(received, 40e8);
        assertEq(vault.bufferBalance(), 60e8, "backstop is not liquid buffer");
        assertEq(vault.backstopBalance(), 40e8, "backstop reserve credited");
        assertEq(vault.totalUnderlying(), 100e8);
        assertEq(vault.backingRatio(), 1e18, "fully repaired");
        assertEq(dToken.totalSupply(), supplyBefore, "no dToken minted");
        assertEq(dToken.balanceOf(alice), aliceBalanceBefore, "holder balance unchanged");
        assertEq(dToken.balanceOf(bob), 0, "backstop receives no dToken");
        assertEq(vault.pendingWithdrawals(), pendingBefore, "pending unchanged");
    }

    function test_BackstopReserve_NotSpendableUntilReleased() public {
        _deposit(alice, 100e8);
        deal(address(underlying), address(vault), 0);

        underlying.mint(bob, 100e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 100e8);
        vault.backstopDeposit(100e8);
        vm.stopPrank();

        assertEq(vault.bufferBalance(), 0, "no liquid buffer");
        assertEq(vault.backstopBalance(), 100e8, "protected reserve");
        assertEq(vault.totalUnderlying(), 100e8, "reserve counts as backing");
        assertEq(vault.backingRatio(), 1e18, "backing repaired");

        vm.prank(alice);
        (uint256 received, uint256 requestId) = vault.redeem(100e18, alice);
        assertEq(received, 0, "redeem cannot spend backstop reserve");
        assertEq(requestId, 1, "shortfall request created");
        assertEq(vault.pendingWithdrawals(), 100e8);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        vm.expectRevert(CollateralVault.InsufficientBuffer.selector);
        vault.claim(requestId);

        vm.expectEmit(true, false, false, true);
        emit BackstopReleased(address(this), 100e8);
        uint256 released = vault.releaseBackstopToBuffer(100e8);

        assertEq(released, 100e8);
        assertEq(vault.backstopBalance(), 0, "reserve released");
        assertEq(vault.bufferBalance(), 100e8, "liquid buffer restored");

        vm.prank(alice);
        assertEq(vault.claim(requestId), 100e8, "claim succeeds after explicit release");
    }

    function test_BackstopReserve_DoesNotCreateTreasurySurplus() public {
        _deposit(alice, 100e8);

        underlying.mint(bob, 40e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 40e8);
        vault.backstopDeposit(40e8);
        vm.stopPrank();

        uint256 transferred = vault.transferYieldToTreasury();

        assertEq(transferred, 0, "protected reserve is not treasury surplus");
        assertEq(underlying.balanceOf(treasury), 0, "treasury untouched");
        assertEq(vault.bufferBalance(), 100e8, "liquid buffer preserved");
        assertEq(vault.backstopBalance(), 40e8, "reserve preserved");
        assertEq(vault.totalUnderlying(), 140e8, "reserve still backs vault");
    }

    function test_ReleaseBackstopToBuffer_RevertsOnZeroOrInsufficient() public {
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.releaseBackstopToBuffer(0);

        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        vault.backstopDeposit(1e8);
        vm.stopPrank();

        vm.expectRevert(CollateralVault.InsufficientBackstop.selector);
        vault.releaseBackstopToBuffer(1e8 + 1);
    }

    function test_BackstopDeposit_ZeroReverts() public {
        vm.prank(bob);
        vm.expectRevert(CollateralVault.ZeroAmount.selector);
        vault.backstopDeposit(0);
    }

    function test_BackstopDeposit_WorksWhilePaused() public {
        vault.pauseDeposit();
        vault.pauseRedeem();
        vault.pauseAllocation();

        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        uint256 received = vault.backstopDeposit(1e8);
        vm.stopPrank();

        assertEq(received, 1e8);
        assertEq(vault.bufferBalance(), 0);
        assertEq(vault.backstopBalance(), 1e8);
        assertEq(vault.totalUnderlying(), 1e8);
        assertEq(dToken.totalSupply(), 0, "no mint while paused");
    }

    // =================================================================
    //                          pause
    // =================================================================

    function test_Pause_BlocksDepositAndRedeem() public {
        _deposit(alice, 10e8);

        vault.pauseDeposit(); // admin holds GUARDIAN_ROLE
        vault.pauseRedeem();
        assertTrue(vault.pausedDeposit());
        assertTrue(vault.pausedRedeem());

        underlying.mint(bob, 1e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 1e8);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.deposit(1e8);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(CollateralVault.Paused.selector);
        vault.redeem(10e18, alice);

        // GOV can unpause; deposit works again.
        vault.unpauseDeposit();
        vault.unpauseRedeem();
        assertFalse(vault.pausedDeposit());
        assertFalse(vault.pausedRedeem());
        _deposit(bob, 1e8);
        assertEq(dToken.balanceOf(bob), 1e18);
    }

    function test_PauseGuardian_CannotUnpause() public {
        address guardian = makeAddr("guardian");
        vault.grantRole(GUARDIAN_ROLE, guardian);

        vm.prank(guardian);
        vault.pauseDeposit(); // guardian can pause
        assertTrue(vault.pausedDeposit());

        vm.prank(guardian);
        vm.expectRevert(); // guardian lacks GOV_ROLE -> AccessControl revert
        vault.unpauseDeposit();
    }

    // =================================================================
    //                          setters
    // =================================================================

    function test_SetBufferConfig_RevertAboveBpsAndState() public {
        vm.expectRevert(CollateralVault.InvalidBufferConfig.selector);
        vault.setBufferConfig(10001, 0);

        vm.expectEmit(false, false, false, true, address(vault));
        emit BufferConfigUpdated(2000, 3333, 0, 5e8);
        vault.setBufferConfig(3333, 5e8);
        assertEq(vault.bufferTargetBps(), 3333);
        assertEq(vault.bufferFloor(), 5e8);
    }

    function test_SetWithdrawDelay() public {
        vm.expectRevert(CollateralVault.InvalidBufferConfig.selector);
        vault.setWithdrawDelay(31 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit WithdrawDelayUpdated(1 days, 3 days);
        vault.setWithdrawDelay(3 days);
        // verified indirectly: a new request uses the updated delay
        (uint256 id,) = _seedRequest(alice, 100e8, 0);
        (,, uint256 claimableAt,) = vault.withdrawRequests(id);
        assertEq(claimableAt, block.timestamp + 3 days);
    }

    function test_SetTreasury_ZeroRevertAndState() public {
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        vault.setTreasury(address(0));

        address t = makeAddr("newTreasury");
        vm.expectEmit(true, true, false, true, address(vault));
        emit TreasuryUpdated(treasury, t);
        vault.setTreasury(t);
        assertEq(vault.treasury(), t);
    }

    function test_Setters_RequireGov() public {
        vm.startPrank(alice);
        vm.expectRevert();
        vault.setWithdrawDelay(1);
        vm.expectRevert();
        vault.setTreasury(alice);
        vm.expectRevert();
        vault.setStrategyValuationMaxAge(0);
        vm.stopPrank();
    }

    // =================================================================
    //                       initialize reverts
    // =================================================================

    function test_Initialize_ZeroDTokenTreasuryAdmin_Revert() public {
        CollateralVault impl = new CollateralVault();

        bytes memory badDToken = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(underlying)), IDToken(address(0)), treasury, admin
        );
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), badDToken);

        bytes memory badTreasury = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlying)),
            IDToken(address(dToken)),
            address(0),
            admin
        );
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), badTreasury);

        bytes memory badAdmin = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlying)),
            IDToken(address(dToken)),
            treasury,
            address(0)
        );
        vm.expectRevert(CollateralVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), badAdmin);
    }

    function test_Initialize_RevertsOnDTokenEOA() public {
        CollateralVault impl = new CollateralVault();
        bytes memory badDToken = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(0)), IDToken(makeAddr("notDToken")), treasury, admin
        );

        vm.expectRevert(CollateralVault.NotContract.selector);
        new ERC1967Proxy(address(impl), badDToken);
    }

    function test_Initialize_RevertsOnDTokenVaultMismatch() public {
        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        DToken wrongDToken = DToken(
            address(
                new ERC1967Proxy(
                    address(dImpl), abi.encodeWithSelector(DToken.initialize.selector, makeAddr("wrongVault"), admin)
                )
            )
        );
        wrongDToken.setAllowedUnderlying(address(underlying), true);

        bytes memory init = abi.encodeWithSelector(
            CollateralVault.initialize.selector,
            IERC20(address(underlying)),
            IDToken(address(wrongDToken)),
            treasury,
            admin
        );

        vm.expectRevert(CollateralVault.UnderlyingMismatch.selector);
        new ERC1967Proxy(address(vImpl), init);
    }

    // =================================================================
    //                       edge cases / views
    // =================================================================

    /// @dev Sub-unit dToken (1 wei) converts to 0 underlying (floor), so redeem
    ///      rejects it rather than silently burning value into a zero payout.
    function test_DustRedeem_8dec() public {
        _deposit(alice, 1e8); // 1 WBTC -> 1e18 dWBTC

        vm.prank(alice);
        vm.expectRevert(CollateralVault.InvalidDTokenAmount.selector);
        vault.redeem(1, alice); // 1 wei dToken

        assertEq(dToken.totalSupply(), 1e18, "dust dToken not burned");
    }

    function test_BufferAndTotalUnderlying_NoStrategies() public {
        assertEq(vault.bufferBalance(), 0);
        assertEq(vault.totalUnderlying(), 0);
        _deposit(alice, 7e8);
        assertEq(vault.bufferBalance(), 7e8);
        assertEq(vault.totalUnderlying(), 7e8, "no strategies => total == buffer");

        underlying.mint(bob, 3e8);
        vm.startPrank(bob);
        underlying.approve(address(vault), 3e8);
        vault.backstopDeposit(3e8);
        vm.stopPrank();

        assertEq(vault.bufferBalance(), 7e8, "backstop excluded from buffer");
        assertEq(vault.backstopBalance(), 3e8, "backstop tracked separately");
        assertEq(vault.totalUnderlying(), 10e8, "total includes buffer + backstop");
    }
}
