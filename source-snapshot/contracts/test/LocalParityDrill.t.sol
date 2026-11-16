// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ETH_GAS_COMPENSATION} from "src/Dependencies/Constants.sol";
import {DToken} from "src/DToken.sol";
import {CollateralVault} from "src/CollateralVault.sol";
import {TroveManager} from "src/TroveManager.sol";
import {IStrategy} from "src/Interfaces/IStrategy.sol";
import {IPriceFeed} from "src/Interfaces/IPriceFeed.sol";
import {IBorrowerOperations} from "src/Interfaces/IBorrowerOperations.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";
import {IWETH} from "src/Interfaces/IWETH.sol";
import {LocalERC20Faucet} from "script/local/LocalTokens.sol";

interface IStrategyGovernance {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
    function upgrader() external view returns (address);
    function setUpgrader(address newUpgrader) external;
}

interface IInterestRouterForwarderGovernance {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

/// @dev Local Production-Parity failure drills (Development-Plan §2-6 acceptance ① / Phase 4
///      検証). Runs as a fork test AGAINST A LIVE NON-MAINNET DEPLOYMENT (local anvil after
///      `./deploy local`), consuming its deployment-manifest.json. Gated on DF_PARITY_DRILL —
///      the "DF deploy wiring (local)" CI job always runs it right after the deploy, so the
///      drills are continuously exercised (never dormant); plain forkless `forge test` skips
///      it like the other deployment-bound suites (E2E).
///
///      Drills: ① governance handover ceremony (2-step dToken ownership -> TimelockController,
///      then a timelock-gated cap change = the Day-2 activation path), ② strategy principal
///      loss -> backingRatio < 1e18 -> oracle price drops (ORCL-FR-014 end to end),
///      ③ collateral oracle staleness -> PriceFeedProxy failsafe -> recoverable branch pause
///      (SYS-RISK-001/006 class), ④ core redemption scanning all 8 branches including the
///      placeholder ones (SYS-RISK-006).
contract LocalParityDrill is Test {
    using stdJson for string;

    string json;
    address deployer;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant WRITEOFF_ROLE = keccak256("WRITEOFF_ROLE");

    ICollateralRegistry registry;
    IERC20 bold;

    function setUp() public {
        if (!_envFlag("DF_PARITY_DRILL")) vm.skip(true);
        json = vm.readFile(vm.envOr("DF_PARITY_MANIFEST", string("deployment-manifest.json")));
        deployer = vm.envOr("DF_PARITY_DEPLOYER", address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266));
        registry = ICollateralRegistry(json.readAddress(".collateralRegistry"));
        bold = IERC20(json.readAddress(".jpydfToken"));
    }

    function _envFlag(string memory key) internal view returns (bool) {
        string memory value = vm.envOr(key, string("false"));
        bytes32 hash = keccak256(bytes(value));
        return hash == keccak256(bytes("true")) || hash == keccak256(bytes("1")) || hash == keccak256(bytes("yes"));
    }

    // ---- manifest helpers -------------------------------------------------

    function _branch(uint256 i, string memory key) internal view returns (address) {
        return json.readAddress(string.concat(".branches[", vm.toString(i), "].", key));
    }

    function _dfYield(uint256 i, string memory key) internal view returns (address) {
        return json.readAddress(string.concat(".dfYield[", vm.toString(i), "].", key));
    }

    function _dfYieldStrategy(uint256 i, uint256 strategyIndex) internal view returns (address) {
        return json.readAddress(
            string.concat(".dfYield[", vm.toString(i), "].strategies[", vm.toString(strategyIndex), "].strategy")
        );
    }

    function _fetchPrice(uint256 i) internal returns (uint256 price) {
        bool failed;
        (price, failed) = IPriceFeed(_branch(i, "priceFeed")).fetchPrice();
        assertFalse(failed, "fetchPrice failed on healthy branch");
    }

    /// @dev Fund `deployer` with `amount` dwstETH (branch 0) through the production path:
    ///      local wstETH faucet mint -> CollateralVault.deposit (1:1 dToken mint).
    function _mintDWstETH(uint256 amount) internal {
        LocalERC20Faucet wstEth = LocalERC20Faucet(_dfYield(0, "underlying"));
        DToken dWstEth = DToken(_dfYield(0, "dToken"));
        CollateralVault vault = CollateralVault(_dfYield(0, "collateralVault"));

        // The live deployment must remain fail-closed until governance preparation.
        // This local fork test opens the cap only inside its per-test snapshot so the
        // strategy and oracle failure drills can mint their fixtures before handover.
        assertEq(dWstEth.cap(), 0, "active branch must start frozen");
        vm.startPrank(deployer);
        dWstEth.setCap(type(uint256).max);
        wstEth.mint(deployer, amount);
        wstEth.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    // ---- drills -----------------------------------------------------------

    /// @notice ① Day-2 governance ceremony: 2-step dToken ownership handover to a 24h
    ///         TimelockController, then a timelock-gated setCap on an inert branch (the
    ///         activation step that unfreezes minting). Proves the production governance
    ///         path works against the deployed wiring, including the 24h delay.
    function test_TimelockOwnershipCeremonyAndCapGovernance() public {
        DToken dInert = DToken(_branch(7, "collToken"));
        assertEq(dInert.cap(), 0, "inert branch must start frozen");

        address gov = makeAddr("govStandin");
        address[] memory proposers = new address[](1);
        proposers[0] = gov;
        address[] memory executors = new address[](1);
        executors[0] = gov;
        TimelockController timelock = new TimelockController(24 hours, proposers, executors, address(0));

        // 2-step handover: deployer starts the transfer, the timelock accepts it (via a
        // scheduled, delayed operation — exactly how the real GOV multisig would).
        vm.prank(deployer);
        dInert.transferOwnership(address(timelock));
        assertEq(dInert.owner(), deployer, "2-step: owner unchanged until acceptance");

        bytes memory acceptCall = abi.encodeWithSignature("acceptOwnership()");
        vm.prank(gov);
        timelock.schedule(address(dInert), 0, acceptCall, bytes32(0), bytes32(uint256(1)), 24 hours);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(gov);
        timelock.execute(address(dInert), 0, acceptCall, bytes32(0), bytes32(uint256(1)));
        assertEq(dInert.owner(), address(timelock), "timelock must own the dToken after ceremony");

        // Timelock-gated cap change (Day-2 activation step shape).
        bytes memory capCall = abi.encodeWithSignature("setCap(uint256)", uint256(123e18));
        vm.prank(gov);
        timelock.schedule(address(dInert), 0, capCall, bytes32(0), bytes32(uint256(2)), 24 hours);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(gov);
        timelock.execute(address(dInert), 0, capCall, bytes32(0), bytes32(uint256(2)));
        assertEq(dInert.cap(), 123e18, "timelock-gated setCap must take effect");

        bytes memory freezeCall = abi.encodeWithSignature("setCap(uint256)", uint256(0));
        vm.prank(gov);
        timelock.schedule(address(dInert), 0, freezeCall, bytes32(0), bytes32(uint256(3)), 24 hours);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(gov);
        timelock.execute(address(dInert), 0, freezeCall, bytes32(0), bytes32(uint256(3)));
        assertEq(dInert.cap(), 0, "timelock must be able to return the branch to idle");

        bytes memory reopenCall = abi.encodeWithSignature("setCap(uint256)", uint256(456e18));
        vm.prank(gov);
        timelock.schedule(address(dInert), 0, reopenCall, bytes32(0), bytes32(uint256(4)), 24 hours);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(gov);
        timelock.execute(address(dInert), 0, reopenCall, bytes32(0), bytes32(uint256(4)));
        assertEq(dInert.cap(), 456e18, "timelock must be able to reopen a previously idle branch");
    }

    /// @notice Full DF yield-layer handover ceremony for one active branch:
    ///         dToken owner -> Timelock, Vault DEFAULT_ADMIN/GOV -> Timelock,
    ///         Vault emergency/ops/writeoff roles split to their dedicated holders,
    ///         deployer revoked from all Vault roles, Strategy upgrader -> Timelock,
    ///         Strategy owner -> Guardian, InterestRouterForwarder owner -> Timelock,
    ///         PriceFeedProxy owner -> GOV multisig directly.
    function test_FullDFGovernanceHandoverCeremony() public {
        IInterestRouterForwarderGovernance interestRouter =
            IInterestRouterForwarderGovernance(_branch(0, "interestRouter"));
        IInterestRouterForwarderGovernance priceFeed = IInterestRouterForwarderGovernance(_branch(0, "priceFeed"));
        DToken dToken = DToken(_dfYield(0, "dToken"));
        CollateralVault vault = CollateralVault(_dfYield(0, "collateralVault"));
        IStrategyGovernance strategy = IStrategyGovernance(_dfYieldStrategy(0, 0));

        address gov = makeAddr("govMultisig");
        address guardian = makeAddr("guardianMultisig");
        address allocator = makeAddr("allocatorOps");
        address writeoff = makeAddr("writeoffGov");
        address treasury = makeAddr("treasurySafe");

        address[] memory proposers = new address[](1);
        proposers[0] = gov;
        address[] memory executors = new address[](1);
        executors[0] = gov;
        TimelockController timelock = new TimelockController(24 hours, proposers, executors, address(0));

        vm.prank(deployer);
        dToken.transferOwnership(address(timelock));
        _executeTimelockCall(timelock, gov, address(dToken), abi.encodeWithSignature("acceptOwnership()"), 1);
        assertEq(dToken.owner(), address(timelock), "dToken owner");

        vm.prank(deployer);
        interestRouter.transferOwnership(address(timelock));
        _executeTimelockCall(timelock, gov, address(interestRouter), abi.encodeWithSignature("acceptOwnership()"), 2);
        assertEq(interestRouter.owner(), address(timelock), "interest router owner");

        vm.prank(deployer);
        priceFeed.transferOwnership(gov);
        vm.prank(gov);
        priceFeed.acceptOwnership();
        assertEq(priceFeed.owner(), gov, "price feed owner");

        vm.startPrank(deployer);
        vault.setTreasury(treasury);
        vault.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
        vault.grantRole(GOV_ROLE, address(timelock));
        vault.grantRole(ALLOCATOR_ROLE, allocator);
        vault.grantRole(GUARDIAN_ROLE, guardian);
        vault.grantRole(WRITEOFF_ROLE, writeoff);
        vault.revokeRole(GOV_ROLE, deployer);
        vault.revokeRole(ALLOCATOR_ROLE, deployer);
        vault.revokeRole(GUARDIAN_ROLE, deployer);
        vault.revokeRole(WRITEOFF_ROLE, deployer);
        vault.revokeRole(DEFAULT_ADMIN_ROLE, deployer);
        strategy.setUpgrader(address(timelock));
        strategy.transferOwnership(guardian);
        vm.stopPrank();

        vm.prank(guardian);
        strategy.acceptOwnership();

        assertEq(vault.treasury(), treasury, "vault treasury");
        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, address(timelock)), "timelock admin");
        assertTrue(vault.hasRole(GOV_ROLE, address(timelock)), "timelock gov");
        assertTrue(vault.hasRole(ALLOCATOR_ROLE, allocator), "allocator");
        assertTrue(vault.hasRole(GUARDIAN_ROLE, guardian), "guardian");
        assertTrue(vault.hasRole(WRITEOFF_ROLE, writeoff), "writeoff");
        assertFalse(vault.hasRole(DEFAULT_ADMIN_ROLE, deployer), "deployer admin revoked");
        assertFalse(vault.hasRole(GOV_ROLE, deployer), "deployer gov revoked");
        assertFalse(vault.hasRole(ALLOCATOR_ROLE, deployer), "deployer allocator revoked");
        assertFalse(vault.hasRole(GUARDIAN_ROLE, deployer), "deployer guardian revoked");
        assertFalse(vault.hasRole(WRITEOFF_ROLE, deployer), "deployer writeoff revoked");
        assertFalse(vault.hasRole(WRITEOFF_ROLE, address(timelock)), "writeoff is not timelock");
        assertEq(strategy.upgrader(), address(timelock), "strategy upgrader");
        assertEq(strategy.owner(), guardian, "strategy owner");
    }

    /// @notice ② Strategy principal loss must lower the branch oracle price through
    ///         backingRatio (VAULT-FR-016 -> ORCL-FR-014), with the PRODUCTION feed doing the
    ///         multiplication — the SYS-RISK-002 mitigation, end to end.
    function test_StrategyLossLowersOraclePriceViaBackingRatio() public {
        CollateralVault vault = CollateralVault(_dfYield(0, "collateralVault"));
        IStrategy strategy = IStrategy(_dfYieldStrategy(0, 0));

        _mintDWstETH(10 ether);
        uint256 priceBefore = _fetchPrice(0);
        assertEq(vault.backingRatio(), 1e18, "fully backed before the loss");

        vm.startPrank(deployer);
        vault.allocate(); // ALLOCATOR: push buffer above target into the (production) strategy
        vault.pauseAllocation(); // GUARDIAN: freeze outbound strategy moves before recognizing the loss
        vault.writeoffStrategyPrincipal(strategy, 1 ether, 0); // WRITEOFF: recognize a 1-wstETH loss
        vm.stopPrank();

        uint256 backing = vault.backingRatio();
        assertLt(backing, 1e18, "loss must surface as backingRatio < 1e18");

        (uint256 priceAfter,) = IPriceFeed(_branch(0, "priceFeed")).fetchPrice();
        assertLt(priceAfter, priceBefore, "oracle price must drop after the loss");
        assertApproxEqRel(priceAfter, priceBefore * backing / 1e18, 1e15, "price must scale by the backing ratio");
    }

    /// @notice ③ A stale collateral/USD aggregator must trip the failsafe chain:
    ///         production feed fails -> PriceFeedProxy catches and reports the failure ->
    ///         branch is temporarily paused (lastGoodPrice mode), never a silent stale price
    ///         or an irreversible economic shutdown.
    function test_StaleCollateralOracleTemporarilyPausesBranch() public {
        TroveManager tm = TroveManager(_branch(1, "troveManager"));
        IBorrowerOperations bo = IBorrowerOperations(_branch(1, "borrowerOperations"));
        assertEq(tm.shutdownTime(), 0, "active branch 1 must start live");
        assertFalse(bo.isOracleFailureShutdown(), "active branch 1 must start unpaused");

        // Past the 24h collateral staleness threshold but inside the 72h JPY one: the
        // failure is attributable to the collateral leg only.
        vm.warp(block.timestamp + 25 hours);

        (uint256 price, bool failed) = IPriceFeed(_branch(1, "priceFeed")).fetchPrice();
        assertTrue(failed, "stale collateral oracle must be reported as a failure");
        assertGt(price, 0, "failsafe must still serve lastGoodPrice");
        assertTrue(bo.isOracleFailureShutdown(), "branch must be temporarily paused by the failsafe");
        assertEq(tm.shutdownTime(), 0, "oracle failure must not trigger irreversible shutdown");
    }

    /// @notice ④ Core redemption walks ALL eight branches (CollateralRegistry has no
    ///         try/catch): the placeholder branches must be scanned without reverting and
    ///         without their sentinel price being consumed (SYS-RISK-006 / ORCL-FR-008).
    function test_RedemptionScansAllEightBranches() public {
        // Open a real trove on branch 0 to have debt + JPYdf to redeem. Gas compensation
        // uses the protocol-level WETH from the manifest, NOT the branch-0 underlying
        // (which is wstETH).
        _mintDWstETH(5 ether);
        IWETH weth = IWETH(json.readAddress(".weth"));
        IERC20 dWstETH = IERC20(_branch(0, "collToken"));
        IBorrowerOperations bo = IBorrowerOperations(_branch(0, "borrowerOperations"));

        vm.deal(deployer, 100 ether);
        vm.startPrank(deployer);
        weth.deposit{value: ETH_GAS_COMPENSATION}();
        dWstETH.approve(address(bo), 5 ether);
        IERC20(address(weth)).approve(address(bo), ETH_GAS_COMPENSATION);
        uint256 troveId = bo.openTrove(
            deployer,
            uint256(keccak256("parity-drill")), // avoid colliding with pre-existing troves
            5 ether,
            400_000e18,
            0,
            0,
            5e16,
            type(uint256).max,
            address(0),
            address(0),
            address(0)
        );

        TroveManager tm = TroveManager(_branch(0, "troveManager"));
        uint256 debtBefore = tm.getLatestTroveData(troveId).entireDebt;
        uint256 boldBefore = bold.balanceOf(deployer);
        uint256 dWstETHBefore = dWstETH.balanceOf(deployer);

        registry.redeemCollateral(10_000e18, 0, 1e18); // scans branches 0..7 incl. placeholders
        vm.stopPrank();

        // Fee-independent invariants: right after deploy the redemption rate is at
        // INITIAL_BASE_RATE (= 100%, the launch anti-redemption guard, decaying over time),
        // so the collateral PAYOUT can legitimately round to zero here. What must hold
        // regardless of the fee: the full-branch scan completes (no revert across the 8
        // branches incl. placeholders), the redeemer's JPYdf is burned, and the hit trove's
        // debt shrinks by the redeemed amount.
        assertLt(bold.balanceOf(deployer), boldBefore, "redemption must burn JPYdf");
        assertLt(tm.getLatestTroveData(troveId).entireDebt, debtBefore, "trove debt must shrink");
        assertGe(dWstETH.balanceOf(deployer), dWstETHBefore, "collateral balance must not decrease");
    }

    function _executeTimelockCall(
        TimelockController timelock,
        address gov,
        address target,
        bytes memory data,
        uint256 salt
    ) internal {
        bytes32 saltBytes = bytes32(salt);
        vm.prank(gov);
        timelock.schedule(target, 0, data, bytes32(0), saltBytes, 24 hours);
        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(gov);
        timelock.execute(target, 0, data, bytes32(0), saltBytes);
    }
}
