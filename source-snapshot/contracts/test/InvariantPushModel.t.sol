// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {activateDTokenForTest} from "test/mocks/MockDTokenRegistry.sol";

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import "../src/DToken.sol";
import "../src/CollateralVault.sol";
import "./TestContracts/MockStrategy.sol";
import "../src/Strategies/AaveV3Strategy.sol";
import "../src/Interfaces/ICollateralVault.sol";
import "../src/Interfaces/IStrategy.sol";
import "./PushModelMocks.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/// @notice Local 8-decimal mintable token used by the invariant suite.
/// @dev    A local copy avoids cross-test-file dependencies; the same shape is
///         defined in `test/CollateralVault.t.sol` for the unit suite.
contract InvU is ERC20 {
    constructor() ERC20("Invariant WBTC", "iWBTC") {}

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title PushModelHandler - stateful handler for the invariant suite
/// @notice Holds references to a deployed vault + strategies, randomly drives
///         deposits, redeems, claims, allocations, strategy-side pushes,
///         yield injection, and donations. Every external call into the
///         vault / strategies is wrapped in try/catch so the handler itself
///         never reverts — this lets the suite run with
///         `fail_on_revert = true` (the default in `foundry.toml`).
contract PushModelHandler is Test {
    // --- Deployed contracts ---
    CollateralVault public vault;
    DToken public dToken;
    InvU public underlying;
    MockStrategy public stratA;
    MockStrategy public stratB;
    AaveV3Strategy public stratC;
    MockAavePool public aavePool;
    MockAToken public aToken;
    address public admin;
    address[3] public users;

    // --- Ghost variables (used by invariants) ---
    /// @notice Sum of all `vault.deposit` calls' `_underlyingAmount`.
    uint256 public cumulativeDeposits;
    /// @notice Underlying contributed through `backstopDeposit`.
    uint256 public cumulativeBufferDonations;
    /// @notice Yield-equivalent value injected into MockStrategies via
    ///         `mint + setMockYield`. Counts toward "yield sources".
    uint256 public cumulativeYieldInjected;
    /// @notice Sum of `transferYieldToTreasury` return values.
    uint256 public cumulativeTreasuryReceived;

    // --- Pending request bookkeeping ---
    uint256[] public pendingReqIds;
    mapping(uint256 => address) public pendingOwners;
    mapping(uint256 => bool) public pendingClaimed;

    constructor(
        CollateralVault _vault,
        DToken _dToken,
        InvU _underlying,
        MockStrategy _stratA,
        MockStrategy _stratB,
        AaveV3Strategy _stratC,
        MockAavePool _aavePool,
        MockAToken _aToken,
        address _admin,
        address[3] memory _users
    ) {
        vault = _vault;
        dToken = _dToken;
        underlying = _underlying;
        stratA = _stratA;
        stratB = _stratB;
        stratC = _stratC;
        aavePool = _aavePool;
        aToken = _aToken;
        admin = _admin;
        users = _users;
    }

    // --- Internal helpers ---

    function _strategyOf(uint8 sel) internal view returns (IStrategy) {
        uint8 idx = sel % 3;
        if (idx == 0) return IStrategy(address(stratA));
        if (idx == 1) return IStrategy(address(stratB));
        return IStrategy(address(stratC));
    }

    function _removePending(uint256 idx) internal {
        uint256 last = pendingReqIds.length - 1;
        if (idx != last) pendingReqIds[idx] = pendingReqIds[last];
        pendingReqIds.pop();
    }

    function sumOfPendingRequests() public view returns (uint256 total) {
        for (uint256 i = 0; i < pendingReqIds.length; i++) {
            uint256 reqId = pendingReqIds[i];
            (, uint256 amt,, bool claimed) = vault.withdrawRequests(reqId);
            if (!claimed) total += amt;
        }
    }

    function cumulativeYieldOrDonation() public view returns (uint256) {
        return cumulativeYieldInjected + cumulativeBufferDonations;
    }

    function totalStrategyPrincipal() public view returns (uint256) {
        return stratA.principal() + stratB.principal() + stratC.principal();
    }

    // --- Handler actions ---

    function h_deposit(uint8 userSel, uint256 amount) public {
        amount = bound(amount, 1, 1e12);
        address user = users[userSel % 3];
        underlying.mint(user, amount);
        vm.startPrank(user);
        underlying.approve(address(vault), amount);
        try vault.deposit(amount) {
            cumulativeDeposits += amount;
        } catch {}
        vm.stopPrank();
    }

    function h_redeem(uint8 userSel, uint256 underlyingAmt, uint8 recvSel) public {
        address user = users[userSel % 3];
        uint256 bal = dToken.balanceOf(user);
        uint256 underlyingAvail = dToken.convertToUnderlying(bal);
        if (underlyingAvail == 0) return;
        // Bound in *underlying* units, then round-trip back to dToken so the
        // dToken redeemed corresponds exactly to a whole-unit underlying
        // amount (no convertToUnderlying rounding dust, which would otherwise
        // manifest as phantom surplus on the vault buffer).
        underlyingAmt = bound(underlyingAmt, 1, underlyingAvail);
        uint256 dAmt = dToken.convertToDToken(underlyingAmt);
        address receiver = users[recvSel % 3];
        vm.prank(user);
        try vault.redeem(dAmt, receiver) returns (uint256, uint256 reqId) {
            if (reqId != 0 && !pendingClaimed[reqId]) {
                pendingReqIds.push(reqId);
                pendingOwners[reqId] = receiver;
            }
        } catch {}
    }

    function h_claim(uint8 reqSel) public {
        if (pendingReqIds.length == 0) return;
        uint256 idx = reqSel % pendingReqIds.length;
        uint256 reqId = pendingReqIds[idx];
        address owner = pendingOwners[reqId];
        if (owner == address(0)) {
            _removePending(idx);
            return;
        }
        vm.prank(owner);
        try vault.claim(reqId) {
            pendingClaimed[reqId] = true;
            _removePending(idx);
        } catch {}
    }

    function h_allocate() public {
        try vault.allocate() {} catch {}
    }

    /// @notice Exercise valid governance configuration transitions while keeping
    ///         the aggregate weight within the Vault's 10,000 bps bound.
    function h_updateStrategy(uint8 stratSel, uint256 weightSeed, uint256 capSeed, bool enabled) public {
        IStrategy strat = _strategyOf(stratSel);
        (, uint256 oldWeight,) = vault.strategyConfigs(strat);
        uint256 totalWithoutSelected = vault.totalWeightBps() - oldWeight;
        uint256 maxWeight = 10_000 - totalWithoutSelected;
        uint256 newWeight = enabled ? bound(weightSeed, 0, maxWeight) : 0;
        uint256 newCap = bound(capSeed, 0, 1e15);

        vm.prank(admin);
        try vault.updateStrategy(strat, newWeight, newCap, enabled) {} catch {}
    }

    /// @notice Exercise the guardian's immediate risk-reduction path.
    function h_emergencyDisableStrategy(uint8 stratSel) public {
        vm.prank(admin);
        try vault.emergencyDisableStrategy(_strategyOf(stratSel)) {} catch {}
    }

    /// @notice Recover from the incident pauses created by emergency disable so
    ///         sustained fuzz traffic can continue proving liveness.
    function h_unpauseAll() public {
        vm.startPrank(admin);
        if (vault.pausedDeposit()) {
            try vault.unpauseDeposit() {} catch {}
        }
        if (vault.pausedRedeem()) {
            try vault.unpauseRedeem() {} catch {}
        }
        if (vault.pausedClaim()) {
            try vault.unpauseClaim() {} catch {}
        }
        if (vault.pausedAllocation()) {
            try vault.unpauseAllocation() {} catch {}
        }
        vm.stopPrank();
    }

    function h_sendToVault(uint8 stratSel, uint256 amt) public {
        IStrategy strat = _strategyOf(stratSel);
        uint256 prin = strat.principal();
        if (prin == 0) return;
        amt = bound(amt, 1, prin);
        vm.prank(admin);
        try strat.sendToVault(amt) {} catch {}
    }

    function h_sendProfitToVault(uint8 stratSel) public {
        IStrategy strat = _strategyOf(stratSel);
        vm.prank(admin);
        try strat.sendProfitToVault() {} catch {}
    }

    function h_transferYieldToTreasury() public {
        vm.prank(admin);
        try vault.transferYieldToTreasury() returns (uint256 t) {
            cumulativeTreasuryReceived += t;
        } catch {}
    }

    /// @notice Backstop repair deposit to the protected reserve.
    function h_donateUnderlying(uint256 amt) public {
        amt = bound(amt, 1, 1e10);
        uint256 supplyBefore = dToken.totalSupply();
        uint256 pendingBefore = vault.pendingWithdrawals();
        uint256 bufferBefore = vault.bufferBalance();
        uint256 backstopBefore = vault.backstopBalance();
        uint256 totalBefore = vault.totalUnderlying();
        uint256 backingBefore = vault.backingRatio();

        underlying.mint(address(this), amt);
        underlying.approve(address(vault), amt);
        try vault.backstopDeposit(amt) returns (uint256 received) {
            assertEq(dToken.totalSupply(), supplyBefore, "backstop minted dToken");
            assertEq(vault.pendingWithdrawals(), pendingBefore, "backstop changed pending");
            assertEq(vault.bufferBalance(), bufferBefore, "backstop changed liquid buffer");
            assertEq(vault.backstopBalance(), backstopBefore + received, "backstop reserve diff");
            assertEq(vault.totalUnderlying(), totalBefore + received, "backstop total diff");
            assertGe(vault.backingRatio(), backingBefore, "backstop lowered backing");
            cumulativeBufferDonations += received;
        } catch {}
    }

    /// @notice Inject mock yield into a MockStrategy (mint underlying + setMockYield).
    /// @dev    Only operates on stratA/stratB; stratC is the AaveV3Strategy.
    function h_strategyEarnYield(uint8 stratSel, uint256 amt) public {
        MockStrategy ms = (stratSel & 1) == 0 ? stratA : stratB;
        amt = bound(amt, 1, 1e10);
        underlying.mint(address(ms), amt);
        vm.prank(admin);
        try ms.setMockYield(ms.mockYield() + amt) {
            cumulativeYieldInjected += amt;
        } catch {}
    }

    /// @notice Third-party Aave donation: supply `amt` onBehalfOf=stratC.
    ///         Verifies vault is unaffected (HC-03 surface).
    function h_aaveDonation(uint256 amt) public {
        amt = bound(amt, 1, 1e10);
        underlying.mint(address(this), amt);
        underlying.approve(address(aavePool), amt);
        try aavePool.supply(address(underlying), amt, address(stratC), 0) {} catch {}
    }
}

/// @title InvariantPushModelTest - root invariant test for the push-model vault.
/// @dev   Deploys vault + 3 strategies (2 MockStrategy + 1 AaveV3Strategy with
///        a mock Aave pool), wires them into a `PushModelHandler`, and scopes
///        the invariant fuzzing target to the handler.
contract InvariantPushModelTest is StdInvariant, Test {
    CollateralVault public vault;
    DToken public dToken;
    InvU public underlying;
    MockStrategy public stratA;
    MockStrategy public stratB;
    AaveV3Strategy public stratC;
    MockAavePool public aavePool;
    MockAToken public aToken;
    PushModelHandler public handler;

    address public admin;
    address public treasury;
    address[3] internal _users;

    function setUp() public {
        admin = address(this);
        treasury = makeAddr("treasury");
        _users[0] = makeAddr("alice");
        _users[1] = makeAddr("bob");
        _users[2] = makeAddr("carol");

        underlying = new InvU();
        aavePool = new MockAavePool();
        aToken = new MockAToken(address(aavePool), address(underlying));
        aavePool.setAsset(IERC20(address(underlying)));
        aavePool.setAToken(aToken);

        DToken dImpl = new DToken();
        CollateralVault vImpl = new CollateralVault();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predicted, admin);
        dToken = DToken(address(new ERC1967Proxy(address(dImpl), dInit)));
        dToken.setAllowedUnderlying(address(underlying), true);
        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, IERC20(address(underlying)), IDToken(address(dToken)), treasury, admin
        );
        vault = CollateralVault(address(new ERC1967Proxy(address(vImpl), vInit)));
        assertEq(address(vault), predicted, "vault address mismatch");
        dToken.setTokenInfo("dInvU", "dInvU", IERC20MetadataUpgradeable(address(underlying)));
        activateDTokenForTest(dToken);

        stratA = _deployMockStrategy();
        stratB = _deployMockStrategy();
        stratC = _deployAaveV3Strategy();

        vault.addToWhitelist(address(stratA));
        vault.addToWhitelist(address(stratB));
        vault.addToWhitelist(address(stratC));
        vault.addStrategy(IStrategy(address(stratA)), 3333, type(uint256).max);
        vault.addStrategy(IStrategy(address(stratB)), 3333, type(uint256).max);
        vault.addStrategy(IStrategy(address(stratC)), 3334, type(uint256).max);

        handler =
            new PushModelHandler(vault, dToken, underlying, stratA, stratB, stratC, aavePool, aToken, admin, _users);

        // Scope foundry's invariant fuzzer to the handler only.
        targetContract(address(handler));

        // Exclude actor addresses from the random caller pool so we don't
        // accidentally use them as msg.sender when the handler does not vm.prank.
        excludeSender(admin);
        for (uint256 i = 0; i < _users.length; i++) {
            excludeSender(_users[i]);
        }
    }

    function _deployMockStrategy() internal returns (MockStrategy s) {
        MockStrategy impl = new MockStrategy();
        bytes memory data = abi.encodeWithSelector(
            MockStrategy.initialize.selector, address(vault), IERC20(address(underlying)), admin
        );
        s = MockStrategy(address(new ERC1967Proxy(address(impl), data)));
    }

    function _deployAaveV3Strategy() internal returns (AaveV3Strategy s) {
        AaveV3Strategy impl = new AaveV3Strategy();
        bytes memory data = abi.encodeWithSelector(
            AaveV3Strategy.initialize.selector,
            address(vault),
            IERC20(address(underlying)),
            admin,
            admin,
            IAaveV3Pool(address(aavePool)),
            IAToken(address(aToken))
        );
        s = AaveV3Strategy(address(new ERC1967Proxy(address(impl), data)));
    }

    // =================================================================
    //                          Invariants
    // =================================================================

    /// @notice Vault must always be able to cover dToken backing + pending
    ///         withdrawals out of its buffer + conservative strategy view.
    function invariant_solvency() public view {
        uint256 totalAssets = vault.totalUnderlying();
        uint256 liabilities = vault.actualLiabilities();
        assertGe(totalAssets, liabilities, "solvency: totalUnderlying < liabilities");
    }

    /// @notice Treasury can only ever receive money that came from a yield
    ///         source (mock yield injection or direct buffer donation).
    ///         It must never receive principal that backs outstanding dToken.
    function invariant_no_silent_loss() public view {
        assertLe(
            handler.cumulativeTreasuryReceived(),
            handler.cumulativeYieldOrDonation(),
            "treasury received more than total yield + donations"
        );
    }

    /// @notice The vault's `pendingWithdrawals` counter must equal the sum of
    ///         underlyingAmount across unclaimed `WithdrawRequest`s.
    function invariant_pendingWithdrawals_consistent() public view {
        uint256 sumPending = handler.sumOfPendingRequests();
        assertEq(vault.pendingWithdrawals(), sumPending, "pendingWithdrawals counter drifted from request sum");
    }

    /// @notice With no loss/writeoff actions in this handler, the Vault should
    ///         remain fully backed and report a capped backing ratio of 1e18.
    function invariant_backingRatio_cappedAtOneWhenSolvent() public view {
        uint256 liabilities = vault.actualLiabilities();
        uint256 totalAssets = vault.totalUnderlying();

        assertLe(vault.backingRatio(), 1e18, "backing ratio above cap");
        if (liabilities == 0 || totalAssets >= liabilities) {
            assertEq(vault.backingRatio(), 1e18, "solvent backing ratio not capped at one");
        }
    }

    /// @notice VAULT-INV-009: every disabled Strategy has zero weight and the
    ///         cached aggregate equals the sum of all registered weights.
    function invariant_disabledStrategiesHaveZeroWeightAndWeightSumMatches() public view {
        uint256 strategyCount = vault.getStrategiesCount();
        uint256 summedWeight;

        for (uint256 i; i < strategyCount; i++) {
            IStrategy strategy = vault.strategies(i);
            (bool enabled, uint256 weightBps,) = vault.strategyConfigs(strategy);
            if (!enabled) assertEq(weightBps, 0, "disabled strategy retained weight");
            summedWeight += weightBps;
        }

        assertLe(summedWeight, 10_000, "strategy weights exceed BPS denominator");
        assertEq(vault.totalWeightBps(), summedWeight, "cached strategy weight sum drifted");
    }

    /// @notice VAULT-INV-012: operational and pricing ratios implement the
    ///         same downward-only min(1, A/L) definition while valuation is live.
    function invariant_backingRatioMatchesDefinition() public view {
        uint256 liabilities = vault.actualLiabilities();
        uint256 totalAssets = vault.totalUnderlying();
        uint256 expected =
            liabilities == 0 || totalAssets >= liabilities ? 1e18 : Math.mulDiv(totalAssets, 1e18, liabilities);

        assertEq(vault.backingRatio(), expected, "operational backing ratio formula drifted");
        (uint256 pricingRatio, bool available) = vault.backingRatioForPricing();
        assertTrue(available, "live invariant fixture unexpectedly unavailable");
        assertEq(pricingRatio, expected, "pricing backing ratio formula drifted");
    }

    /// @notice VAULT-INV-014: dToken supply is converted to Underlying with
    ///         ceiling semantics, then queued claims are added exactly once.
    function invariant_actualLiabilitiesUseCeilingAndIncludePending() public view {
        uint256 supply = dToken.totalSupply();
        uint256 userLiabilities = dToken.convertToUnderlying(supply);
        if (dToken.convertToDToken(userLiabilities) < supply) userLiabilities += 1;

        assertEq(
            vault.actualLiabilities(),
            userLiabilities + vault.pendingWithdrawals(),
            "actual liabilities did not use ceil(supply) plus pending"
        );
    }
}
