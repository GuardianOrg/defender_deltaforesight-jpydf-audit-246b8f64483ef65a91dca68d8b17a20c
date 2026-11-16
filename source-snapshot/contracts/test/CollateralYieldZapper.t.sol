// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IERC20MetadataUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeTransferLib} from "Solady/utils/SafeTransferLib.sol";

import {JpydfToken} from "src/JpydfToken.sol";
import {CollateralRegistry} from "src/CollateralRegistry.sol";
import {CollateralVault} from "src/CollateralVault.sol";
import {DToken} from "src/DToken.sol";
import {HintHelpers} from "src/HintHelpers.sol";
import {MultiTroveGetter} from "src/MultiTroveGetter.sol";
import {ETH_GAS_COMPENSATION, MIN_ANNUAL_INTEREST_RATE, MIN_DEBT} from "src/Dependencies/Constants.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {IAddressesRegistry} from "src/Interfaces/IAddressesRegistry.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";
import {IDToken} from "src/Interfaces/IDToken.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {IWETH} from "src/Interfaces/IWETH.sol";
import {BaseZapper} from "src/Zappers/BaseZapper.sol";
import {CollateralYieldZapper} from "src/Zappers/CollateralYieldZapper.sol";
import {IZapper} from "src/Zappers/Interfaces/IZapper.sol";

import {TestDeployer} from "./TestContracts/Deployment.t.sol";
import {WETH9} from "./TestContracts/WETH.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract CollateralYieldBranchDeployer is TestDeployer {
    bytes32 private constant TEST_SALT = keccak256("LiquityV2");

    function deployDTokenBranch(IERC20Metadata _collToken, IWETH _weth)
        external
        returns (
            LiquityContractsDev memory contracts,
            ICollateralRegistry collateralRegistry,
            IJpydfToken jpydfToken,
            HintHelpers hintHelpers,
            MultiTroveGetter multiTroveGetter,
            Zappers memory zappers
        )
    {
        TroveManagerParams memory params = TroveManagerParams(150e16, 110e16, 10e16, 110e16, 5e16, 10e16);

        jpydfToken = new JpydfToken{salt: TEST_SALT}(address(this), _newBridgeRoleHolder());

        (IAddressesRegistry addressesRegistry, address troveManagerAddress) = _deployAddressesRegistryDev(params);

        IERC20Metadata[] memory collaterals = new IERC20Metadata[](1);
        collaterals[0] = _collToken;
        ITroveManager[] memory troveManagers = new ITroveManager[](1);
        troveManagers[0] = ITroveManager(troveManagerAddress);

        collateralRegistry = new CollateralRegistry(jpydfToken, collaterals, troveManagers);
        hintHelpers = new HintHelpers(collateralRegistry);
        multiTroveGetter = new MultiTroveGetter(collateralRegistry);

        (contracts, zappers) = _deployAndConnectCollateralContractsDev(
            _collToken,
            jpydfToken,
            collateralRegistry,
            _weth,
            addressesRegistry,
            troveManagerAddress,
            hintHelpers,
            multiTroveGetter
        );

        jpydfToken.setCollateralRegistry(address(collateralRegistry));
    }
}

contract MockStETH is ERC20 {
    bool public submitPaused;
    address public reenterTarget;
    bytes public reenterData;
    bool public lastReenterSucceeded;

    constructor() ERC20("Liquid staked Ether", "stETH") {}

    function setSubmitPaused(bool paused) external {
        submitPaused = paused;
    }

    function setReenter(address target, bytes calldata data) external {
        reenterTarget = target;
        reenterData = data;
    }

    address public lastSubmitReferral;

    function submit(address _referral) external payable returns (uint256) {
        lastSubmitReferral = _referral;
        require(!submitPaused, "STAKE_PAUSED");
        require(msg.value > 0, "ZERO_DEPOSIT");
        if (reenterTarget != address(0)) {
            (bool ok,) = reenterTarget.call(reenterData);
            lastReenterSucceeded = ok;
        }
        _mint(msg.sender, msg.value);
        return msg.value;
    }
}

contract MockWstETH is ERC20 {
    using SafeERC20 for IERC20;

    MockStETH public immutable stEthToken;
    uint256 public stEthPerToken = 1.2e18;
    uint256 public wrapShortfall;

    constructor(MockStETH _stEth) ERC20("Wrapped liquid staked Ether", "wstETH") {
        stEthToken = _stEth;
    }

    function stETH() external view returns (address) {
        return address(stEthToken);
    }

    function setWrapShortfall(uint256 shortfall) external {
        wrapShortfall = shortfall;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function wrap(uint256 _stETHAmount) external returns (uint256 wstEthOut) {
        // wrapShortfall models Lido stETH 1-2 wei share rounding: the wrap pulls slightly
        // less stETH than requested, leaving the residue with the caller.
        uint256 pulled = _stETHAmount - wrapShortfall;
        IERC20(address(stEthToken)).safeTransferFrom(msg.sender, address(this), pulled);
        wstEthOut = pulled * 1e18 / stEthPerToken;
        _mint(msg.sender, wstEthOut);
    }
}

contract MockERC20PermitToken is ERC20Permit {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeOnTransferZapperToken is MockERC20 {
    uint256 internal constant FEE_BPS = 1_000;

    constructor() MockERC20("Fee Underlying", "fUND", 18) {}

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = amount * FEE_BPS / 10_000;
        super._transfer(from, to, amount - fee);
        if (fee != 0) super._transfer(from, address(0xdead), fee);
    }
}

contract RevertingEthReceiver {
    receive() external payable {
        revert("ETH_REJECTED");
    }
}

contract CollateralYieldZapperTest is Test {
    event ReferralDeposit(
        address indexed user,
        uint256 indexed troveId,
        uint256 underlyingAmount,
        uint256 dTokenAmount,
        uint256 jpydfAmount,
        bytes32 indexed referralCode
    );
    event NativeEthRouteDeposit(
        address indexed user,
        uint256 indexed troveId,
        uint256 ethAmount,
        uint256 stEthAmount,
        uint256 wstEthAmount,
        uint256 dTokenAmount,
        bytes32 indexed referralCode
    );

    struct PermitFixture {
        MockERC20PermitToken underlying;
        DToken dToken;
        CollateralVault vault;
        TestDeployer.LiquityContractsDev branch;
        IJpydfToken jpydfToken;
        CollateralYieldZapper zapper;
    }

    struct LidoFixture {
        MockStETH stEth;
        MockWstETH wstEth;
        DToken dToken;
        CollateralVault vault;
        TestDeployer.LiquityContractsDev branch;
        IJpydfToken jpydfToken;
        CollateralYieldZapper zapper;
    }

    struct FeeOnTransferFixture {
        FeeOnTransferZapperToken underlying;
        DToken dToken;
        CollateralVault vault;
        TestDeployer.LiquityContractsDev branch;
        IJpydfToken jpydfToken;
        CollateralYieldZapper zapper;
    }

    struct DecimalFixture {
        MockERC20 underlying;
        DToken dToken;
        CollateralVault vault;
        TestDeployer.LiquityContractsDev branch;
        ICollateralRegistry collateralRegistry;
        IJpydfToken jpydfToken;
        CollateralYieldZapper zapper;
    }

    address private constant TREASURY = address(0xA11CE);
    address private constant ALICE = address(0x1001);
    address private constant BOB = address(0x1002);
    bytes4 private constant NOT_OWNER_NOR_ADD_MANAGER = bytes4(keccak256("NotOwnerNorAddManager()"));
    bytes4 private constant NOT_OWNER_NOR_REMOVE_MANAGER = bytes4(keccak256("NotOwnerNorRemoveManager()"));

    MockERC20 private underlying;
    DToken private dToken;
    CollateralVault private vault;
    WETH9 private weth;
    TestDeployer.LiquityContractsDev private branch;
    ICollateralRegistry private collateralRegistry;
    IJpydfToken private jpydfToken;
    CollateralYieldZapper private yieldZapper;

    function setUp() public {
        underlying = new MockERC20("Mock Underlying", "mUND", 18);
        (dToken, vault) = _deployVault(underlying);

        weth = new WETH9();
        CollateralYieldBranchDeployer deployer = new CollateralYieldBranchDeployer();
        (branch, collateralRegistry, jpydfToken,,,) =
            deployer.deployDTokenBranch(IERC20Metadata(address(dToken)), IWETH(address(weth)));
        dToken.setRiskParamsRegistry(address(branch.addressesRegistry));
        dToken.setCap(type(uint256).max);
        branch.priceFeed.setPrice(2000e18);

        yieldZapper = new CollateralYieldZapper(
            branch.addressesRegistry, vault, IERC20(address(underlying)), address(0), address(0), address(this)
        );

        deal(ALICE, 100 ether);
        underlying.mint(ALICE, 10_000e18);
        vm.prank(ALICE);
        underlying.approve(address(yieldZapper), type(uint256).max);
    }

    function test_OpenTrove_DepositsUnderlyingAndUsesDTokenCollateral() external {
        IZapper.OpenTroveParams memory params = _openParams(1500e18, 1_500_000e18);

        vm.recordLogs();
        vm.prank(ALICE);
        uint256 troveId = yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(branch.troveNFT.ownerOf(troveId), ALICE, "owner");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1500e18, "trove dToken collateral");
        assertGt(branch.troveManager.getTroveEntireDebt(troveId), 1_500_000e18, "debt includes upfront fee");
        assertEq(jpydfToken.balanceOf(ALICE), 1_500_000e18, "borrowed JPYdf");
        assertEq(underlying.balanceOf(ALICE), 8500e18, "underlying pulled");
        assertEq(dToken.balanceOf(ALICE), 0, "user never receives dToken");
        assertEq(_countReferralLogs(logs, address(yieldZapper)), 0, "no referral event");
        _assertZapperNoTokenResidue();
    }

    function test_OpenTroveWithReferral_EmitsReferralDeposit() external {
        IZapper.OpenTroveParams memory params = _openParams(1500e18, 1_500_000e18);
        bytes32 referralCode = bytes32("REF-42");

        vm.recordLogs();
        vm.prank(ALICE);
        uint256 troveId = yieldZapper.openTroveWithRawETHAndReferral{value: ETH_GAS_COMPENSATION}(params, referralCode);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 loggedTroveId = _assertSingleReferralDeposit(
            logs, address(yieldZapper), ALICE, 1500e18, 1500e18, 1_500_000e18, referralCode
        );
        assertEq(loggedTroveId, troveId, "referral trove id");
    }

    function test_OpenTrove_RevertsWhenOwnerIsNotSender() external {
        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1500e18, 1_500_000e18);
        deal(BOB, 100 ether);
        underlying.mint(BOB, 1500e18);

        vm.startPrank(BOB);
        underlying.approve(address(yieldZapper), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralYieldZapper.CollateralYieldZapper__OwnerMismatch.selector, ALICE, BOB)
        );
        yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);
        vm.stopPrank();
    }

    function test_OpenTrove_RevertsWhenBatchManagerAndInterestRateAreBothSet() external {
        IZapper.OpenTroveParams memory params = _openParams(1500e18, 1_500_000e18);
        params.batchManager = BOB;

        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__CannotChooseInterestIfJoiningBatch.selector);
        vm.prank(ALICE);
        yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);
    }

    function test_OpenTroveWithUnderlyingPermit_DepositsWithoutPriorApproval() external {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);
        PermitFixture memory fixture = _deployPermitFixture();
        deal(signer, 100 ether);
        fixture.underlying.mint(signer, 10_000e18);

        IZapper.OpenTroveParams memory params = _openParams(signer, 0, 1500e18, 1_500_000e18);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(privateKey, fixture.underlying, signer, address(fixture.zapper), params.collAmount, deadline);

        assertEq(fixture.underlying.allowance(signer, address(fixture.zapper)), 0, "no prior allowance");

        vm.prank(signer);
        uint256 troveId =
            fixture.zapper.openTroveWithUnderlyingPermit{value: ETH_GAS_COMPENSATION}(params, deadline, v, r, s);

        assertEq(fixture.branch.troveNFT.ownerOf(troveId), signer, "owner");
        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), 1500e18, "trove dToken collateral");
        assertEq(fixture.jpydfToken.balanceOf(signer), 1_500_000e18, "borrowed JPYdf");
        assertEq(fixture.underlying.balanceOf(signer), 8500e18, "underlying pulled through permit");
        assertEq(fixture.dToken.balanceOf(signer), 0, "user never receives dToken");
        _assertPermitZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithUnderlyingPermit_ToleratesPermitFrontRunWhenAllowanceExists() external {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);
        PermitFixture memory fixture = _deployPermitFixture();
        deal(signer, 100 ether);
        fixture.underlying.mint(signer, 10_000e18);

        IZapper.OpenTroveParams memory params = _openParams(signer, 0, 1500e18, 1_500_000e18);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(privateKey, fixture.underlying, signer, address(fixture.zapper), params.collAmount, deadline);

        fixture.underlying.permit(signer, address(fixture.zapper), params.collAmount, deadline, v, r, s);
        assertEq(fixture.underlying.nonces(signer), 1, "front-run permit consumed nonce");
        assertEq(
            fixture.underlying.allowance(signer, address(fixture.zapper)),
            params.collAmount,
            "permit left zapper allowance"
        );

        vm.prank(signer);
        uint256 troveId =
            fixture.zapper.openTroveWithUnderlyingPermit{value: ETH_GAS_COMPENSATION}(params, deadline, v, r, s);

        assertEq(fixture.branch.troveNFT.ownerOf(troveId), signer, "owner");
        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), 1500e18, "trove dToken collateral");
        assertEq(fixture.jpydfToken.balanceOf(signer), 1_500_000e18, "borrowed JPYdf");
        assertEq(fixture.underlying.balanceOf(signer), 8500e18, "underlying pulled through front-run permit");
        assertEq(fixture.underlying.allowance(signer, address(fixture.zapper)), 0, "allowance consumed");
        _assertPermitZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithUnderlyingPermitAndReferral_EmitsReferralAndRejectsInvalidSignature() external {
        uint256 privateKey = 0xB0B;
        address signer = vm.addr(privateKey);
        PermitFixture memory fixture = _deployPermitFixture();
        deal(signer, 100 ether);
        fixture.underlying.mint(signer, 10_000e18);

        IZapper.OpenTroveParams memory invalidParams = _openParams(signer, 0, 1500e18, 1_500_000e18);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__PermitFailed.selector);
        vm.prank(signer);
        fixture.zapper.openTroveWithUnderlyingPermit{value: ETH_GAS_COMPENSATION}(
            invalidParams, block.timestamp + 1 days, 0, bytes32(0), bytes32(0)
        );

        bytes32 referralCode = bytes32("REF-77");
        IZapper.OpenTroveParams memory params = _openParams(signer, 1, 1500e18, 1_500_000e18);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(privateKey, fixture.underlying, signer, address(fixture.zapper), params.collAmount, deadline);

        vm.recordLogs();
        vm.prank(signer);
        uint256 troveId = fixture.zapper.openTroveWithUnderlyingPermitAndReferral{value: ETH_GAS_COMPENSATION}(
            params, deadline, v, r, s, referralCode
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 loggedTroveId = _assertSingleReferralDeposit(
            logs, address(fixture.zapper), signer, 1500e18, 1500e18, 1_500_000e18, referralCode
        );
        assertEq(loggedTroveId, troveId, "permit referral trove id");

        _assertPermitZapperNoTokenResidue(fixture);
    }

    function test_AddAndWithdrawCollateral_UsesUnderlyingAtEdges() external {
        uint256 troveId = _openDefaultTrove();
        underlying.mint(ALICE, 100e18);

        vm.prank(ALICE);
        uint256 mintedDToken = yieldZapper.addCollWithUnderlying(troveId, 100e18);
        assertEq(mintedDToken, 100e18, "minted dToken");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1600e18, "coll after add");

        uint256 underlyingBefore = underlying.balanceOf(ALICE);
        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = yieldZapper.withdrawCollToUnderlying(troveId, 50e18);

        assertEq(received, 50e18, "redeemed underlying");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore + 50e18, "receiver got underlying");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1550e18, "coll after withdraw");
        _assertZapperNoTokenResidue();
    }

    function test_AddCollWithUnderlying_RespectsAddManagerRestriction() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 200e18);

        vm.prank(ALICE);
        yieldZapper.setAddManager(troveId, BOB);

        vm.prank(BOB);
        uint256 mintedDToken = yieldZapper.addCollWithUnderlying(troveId, 100e18);

        assertEq(mintedDToken, 100e18, "manager minted dToken");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1600e18, "manager added collateral");
        _assertZapperNoTokenResidue();

        vm.prank(ALICE);
        yieldZapper.setAddManager(troveId, ALICE);

        vm.expectRevert(NOT_OWNER_NOR_ADD_MANAGER);
        vm.prank(BOB);
        yieldZapper.addCollWithUnderlying(troveId, 100e18);
    }

    function test_WithdrawCollToUnderlying_AllowsQueuedRedeemWithoutMinimum() external {
        uint256 troveId = _openDefaultTrove();
        _protectVaultBufferTo(vault, underlying, 10e18);

        uint256 underlyingBefore = underlying.balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = yieldZapper.withdrawCollToUnderlying(troveId, 50e18);

        assertEq(received, 10e18, "partial immediate underlying");
        assertGt(requestId, 0, "queued request");
        assertEq(vault.pendingWithdrawals(), 40e18, "queued remainder");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore + 10e18, "receiver got immediate buffer");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1450e18, "coll withdrawn");
        _assertZapperNoTokenResidue();
    }

    function test_WithdrawCollToUnderlyingWithMin_RevertsWhenRedeemWouldQueue() external {
        uint256 troveId = _openDefaultTrove();
        _protectVaultBufferTo(vault, underlying, 10e18);

        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);
        uint256 underlyingBefore = underlying.balanceOf(ALICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientUnderlyingReceived.selector, 10e18, 50e18
            )
        );
        vm.prank(ALICE);
        yieldZapper.withdrawCollToUnderlyingWithMin(troveId, 50e18, 50e18);

        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore, "trove unchanged");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore, "receiver unchanged");
        assertEq(vault.pendingWithdrawals(), 0, "no queued request");
    }

    function test_WithdrawCollToUnderlyingWithMin_UsesFeeTokenReceiverDelta() external {
        FeeOnTransferFixture memory fixture = _deployFeeOnTransferFixture();
        fixture.underlying.mint(ALICE, 10_000e18);
        vm.prank(ALICE);
        fixture.underlying.approve(address(fixture.zapper), type(uint256).max);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 2_000e18, 1_500_000e18);
        vm.prank(ALICE);
        uint256 troveId = fixture.zapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);

        uint256 collBefore = fixture.branch.troveManager.getTroveEntireColl(troveId);
        uint256 receiverBalanceBefore = fixture.underlying.balanceOf(ALICE);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientUnderlyingReceived.selector, 45e18, 50e18
            )
        );
        vm.prank(ALICE);
        fixture.zapper.withdrawCollToUnderlyingWithMin(troveId, 50e18, 50e18);

        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), collBefore, "trove unchanged");
        assertEq(fixture.underlying.balanceOf(ALICE), receiverBalanceBefore, "receiver unchanged");
        assertEq(fixture.vault.pendingWithdrawals(), 0, "no queued request");
    }

    function test_RevertWhen_CoreRemoveManagerReceiverIsNotZapper() external {
        uint256 troveId = _openDefaultTrove();

        vm.prank(ALICE);
        branch.borrowerOperations.setRemoveManagerWithReceiver(troveId, BOB, ALICE);

        vm.expectRevert(BaseZapper.BaseZapper__ZapperIsNotReceiver.selector);
        vm.prank(ALICE);
        yieldZapper.withdrawCollToUnderlying(troveId, 50e18);
    }

    function test_AdjustTroveWithUnderlyingWithMin_RevertsWhenRedeemWouldQueue() external {
        uint256 troveId = _openDefaultTrove();
        _protectVaultBufferTo(vault, underlying, 10e18);

        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientUnderlyingReceived.selector, 10e18, 50e18
            )
        );
        vm.prank(ALICE);
        yieldZapper.adjustTroveWithUnderlyingWithMin(troveId, 50e18, false, 0, false, 0, 50e18);

        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore, "trove unchanged");
        assertEq(vault.pendingWithdrawals(), 0, "no queued request");
    }

    function test_WithdrawAndRepayJpydf_RoutesToReceiverAndReturnsLeftovers() external {
        uint256 troveId = _openDefaultTrove();
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, ALICE);

        uint256 aliceJpydfBefore = jpydfToken.balanceOf(ALICE);
        vm.prank(BOB);
        yieldZapper.withdrawJpydf(troveId, 100_000e18, 100_000e18);
        assertEq(jpydfToken.balanceOf(ALICE), aliceJpydfBefore + 100_000e18, "borrowed to receiver");

        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), 50_000e18);

        vm.prank(ALICE);
        yieldZapper.repayJpydf(troveId, 50_000e18);
        assertEq(IERC20(address(jpydfToken)).balanceOf(address(yieldZapper)), 0, "no jpydf residue");
    }

    function test_RepayJpydf_ReturnsAmountAboveMinDebtCap() external {
        uint256 troveId = _openDefaultTrove();
        uint256 debtBefore = branch.troveManager.getTroveEntireDebt(troveId);
        assertGt(debtBefore, MIN_DEBT, "default trove must be above floor");

        uint256 requestedRepayment = debtBefore * 2;
        uint256 cappedRepayment = debtBefore - MIN_DEBT;
        deal(address(jpydfToken), ALICE, requestedRepayment);

        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), requestedRepayment);

        vm.prank(ALICE);
        yieldZapper.repayJpydf(troveId, requestedRepayment);

        assertEq(branch.troveManager.getTroveEntireDebt(troveId), MIN_DEBT, "repay capped at min debt");
        assertEq(jpydfToken.balanceOf(ALICE), requestedRepayment - cappedRepayment, "excess JPYdf returned");
        assertEq(jpydfToken.balanceOf(address(yieldZapper)), 0, "no jpydf residue");
    }

    function test_WithdrawJpydf_RevertsForUnauthorizedRemoveManager() external {
        uint256 troveId = _openDefaultTrove();

        vm.expectRevert(NOT_OWNER_NOR_REMOVE_MANAGER);
        vm.prank(BOB);
        yieldZapper.withdrawJpydf(troveId, 100_000e18, 100_000e18);
    }

    function test_RepayJpydf_RespectsAddManagerRestriction() external {
        uint256 troveId = _openDefaultTrove();
        deal(address(jpydfToken), BOB, 20_000e18);
        vm.prank(BOB);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), 20_000e18);

        vm.prank(ALICE);
        yieldZapper.setAddManager(troveId, BOB);

        vm.prank(BOB);
        yieldZapper.repayJpydf(troveId, 10_000e18);

        assertEq(IERC20(address(jpydfToken)).balanceOf(address(yieldZapper)), 0, "manager repay no jpydf residue");

        vm.prank(ALICE);
        yieldZapper.setAddManager(troveId, ALICE);

        vm.expectRevert(NOT_OWNER_NOR_ADD_MANAGER);
        vm.prank(BOB);
        yieldZapper.repayJpydf(troveId, 10_000e18);
    }

    function test_RiskReducingManagerAdjustmentWorksAfterOracleRecoveryBeforeResume() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 100e18);
        deal(address(jpydfToken), BOB, 10_000e18);
        vm.prank(BOB);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), 10_000e18);
        vm.prank(ALICE);
        yieldZapper.setAddManager(troveId, ALICE);
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, ALICE);

        vm.prank(address(branch.priceFeed));
        branch.borrowerOperations.shutdownFromOracleFailure();
        assertTrue(branch.borrowerOperations.isOracleFailureShutdown());

        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);
        uint256 debtBefore = branch.troveManager.getTroveEntireDebt(troveId);
        vm.prank(BOB);
        yieldZapper.adjustTroveWithUnderlying(troveId, 100e18, true, 10_000e18, false, 0);

        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore + 100e18);
        assertEq(branch.troveManager.getTroveEntireDebt(troveId), debtBefore - 10_000e18);
        assertTrue(branch.borrowerOperations.isOracleFailureShutdown(), "zapper must not resume the branch");
        _assertZapperNoTokenResidue();
    }

    function test_AdjustTroveWithUnderlying_CollDecreaseAndDebtIncreaseRoutesToReceiver() external {
        uint256 troveId = _openDefaultTrove();
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, ALICE);

        uint256 underlyingBefore = underlying.balanceOf(ALICE);
        uint256 jpydfBefore = jpydfToken.balanceOf(ALICE);

        vm.prank(BOB);
        (uint256 dTokenChange, uint256 received, uint256 requestId) =
            yieldZapper.adjustTroveWithUnderlying(troveId, 50e18, false, 100_000e18, true, 100_000e18);

        assertEq(dTokenChange, 50e18, "dToken change");
        assertEq(received, 50e18, "redeemed underlying");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore + 50e18, "underlying to receiver");
        assertEq(jpydfToken.balanceOf(ALICE), jpydfBefore + 100_000e18, "jpydf to receiver");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), 1450e18, "coll after adjust");
        _assertZapperNoTokenResidue();
    }

    function test_AdjustTroveWithUnderlying_CoversCollateralDebtQuadrants() external {
        uint256 troveId = _openDefaultTrove();
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, ALICE);
        _fundAndApproveUnderlying(BOB, 300e18);

        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);
        uint256 debtBefore = branch.troveManager.getTroveEntireDebt(troveId);
        uint256 bobUnderlyingBefore = underlying.balanceOf(BOB);
        uint256 aliceJpydfBefore = jpydfToken.balanceOf(ALICE);

        vm.prank(BOB);
        (uint256 dTokenChange, uint256 received, uint256 requestId) =
            yieldZapper.adjustTroveWithUnderlying(troveId, 100e18, true, 100_000e18, true, 100_000e18);

        assertEq(dTokenChange, 100e18, "coll increase debt increase dToken change");
        assertEq(received, 0, "coll increase debt increase received");
        assertEq(requestId, 0, "coll increase debt increase request");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore + 100e18, "coll increased");
        assertGt(branch.troveManager.getTroveEntireDebt(troveId), debtBefore, "debt increased");
        assertEq(underlying.balanceOf(BOB), bobUnderlyingBefore - 100e18, "manager provided underlying");
        assertEq(jpydfToken.balanceOf(ALICE), aliceJpydfBefore + 100_000e18, "receiver got borrowed JPYdf");
        _assertZapperNoTokenResidue();

        collBefore = branch.troveManager.getTroveEntireColl(troveId);
        debtBefore = branch.troveManager.getTroveEntireDebt(troveId);
        uint256 aliceUnderlyingBefore = underlying.balanceOf(ALICE);
        aliceJpydfBefore = jpydfToken.balanceOf(ALICE);
        underlying.mint(ALICE, 100e18);
        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), 50_000e18);

        vm.prank(ALICE);
        (dTokenChange, received, requestId) =
            yieldZapper.adjustTroveWithUnderlying(troveId, 100e18, true, 50_000e18, false, 0);

        assertEq(dTokenChange, 100e18, "coll increase debt decrease dToken change");
        assertEq(received, 0, "coll increase debt decrease received");
        assertEq(requestId, 0, "coll increase debt decrease request");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore + 100e18, "coll increased with repay");
        assertLt(branch.troveManager.getTroveEntireDebt(troveId), debtBefore, "debt decreased");
        assertEq(underlying.balanceOf(ALICE), aliceUnderlyingBefore, "owner supplied newly minted underlying");
        assertEq(jpydfToken.balanceOf(ALICE), aliceJpydfBefore - 50_000e18, "owner repaid JPYdf");
        _assertZapperNoTokenResidue();

        collBefore = branch.troveManager.getTroveEntireColl(troveId);
        debtBefore = branch.troveManager.getTroveEntireDebt(troveId);
        aliceUnderlyingBefore = underlying.balanceOf(ALICE);
        aliceJpydfBefore = jpydfToken.balanceOf(ALICE);
        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), 25_000e18);

        vm.prank(ALICE);
        (dTokenChange, received, requestId) =
            yieldZapper.adjustTroveWithUnderlying(troveId, 50e18, false, 25_000e18, false, 0);

        assertEq(dTokenChange, 50e18, "coll decrease debt decrease dToken change");
        assertEq(received, 50e18, "coll decrease debt decrease received");
        assertEq(requestId, 0, "coll decrease debt decrease request");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore - 50e18, "coll decreased with repay");
        assertLt(branch.troveManager.getTroveEntireDebt(troveId), debtBefore, "debt decreased again");
        assertEq(underlying.balanceOf(ALICE), aliceUnderlyingBefore + 50e18, "owner received underlying");
        assertEq(jpydfToken.balanceOf(ALICE), aliceJpydfBefore - 25_000e18, "owner repaid second JPYdf");
        _assertZapperNoTokenResidue();
    }

    function test_AdjustZombieTroveWithUnderlying_ResuscitatesZombieTrove() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);

        IZapper.OpenTroveParams memory bobParams = _openParams(BOB, 0, 3000e18, 3_000_000e18);
        bobParams.annualInterestRate = MIN_ANNUAL_INTEREST_RATE + 1;
        vm.prank(BOB);
        yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(bobParams);

        vm.warp(block.timestamp + 30 days);
        vm.prank(BOB);
        collateralRegistry.redeemCollateral(1_500_000e18, 0, 1e18);

        assertTrue(branch.troveManager.checkTroveIsZombie(troveId), "trove is zombie");
        uint256 zombieDebt = branch.troveManager.getTroveEntireDebt(troveId);
        assertLt(zombieDebt, MIN_DEBT, "zombie below min debt");

        uint256 debtIncrease = MIN_DEBT - zombieDebt + 100_000e18;
        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);
        uint256 aliceJpydfBefore = jpydfToken.balanceOf(ALICE);
        underlying.mint(ALICE, 100e18);

        vm.prank(ALICE);
        (uint256 dTokenChange, uint256 underlyingReceived, uint256 requestId) =
            yieldZapper.adjustZombieTroveWithUnderlying(troveId, 100e18, true, debtIncrease, true, 0, 0, 150_000e18);

        assertEq(dTokenChange, 100e18, "dToken added");
        assertEq(underlyingReceived, 0, "no underlying received on coll increase");
        assertEq(requestId, 0, "no redeem request");
        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore + 100e18, "coll increased");
        assertGt(branch.troveManager.getTroveEntireDebt(troveId), MIN_DEBT, "debt above min");
        assertFalse(branch.troveManager.checkTroveIsZombie(troveId), "trove is active");
        assertEq(jpydfToken.balanceOf(ALICE), aliceJpydfBefore + debtIncrease, "borrowed JPYdf to owner");
        _assertZapperNoTokenResidue();
    }

    function test_GuardianL09_ManagerClosesToDTokenDuringVaultIncident() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, ALICE);
        uint256 debt = branch.troveManager.getTroveEntireDebt(troveId);
        uint256 collateral = branch.troveManager.getTroveEntireColl(troveId);
        deal(address(jpydfToken), BOB, debt);
        vm.prank(BOB);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), debt);
        vault.pauseRedeem();

        vm.prank(BOB);
        vm.expectRevert();
        branch.borrowerOperations.closeTrove(troveId);
        vm.prank(BOB);
        vm.expectRevert(CollateralVault.Paused.selector);
        yieldZapper.closeTroveToUnderlying(troveId);
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        yieldZapper.closeTroveToDToken(troveId);
        assertEq(branch.troveManager.getTroveEntireColl(troveId), collateral);

        uint256 receivedBefore = dToken.balanceOf(ALICE);
        uint256 ethBefore = ALICE.balance;
        deal(address(dToken), address(yieldZapper), 7); // An unrelated donation must remain untouched.
        vm.prank(BOB);
        assertEq(yieldZapper.closeTroveToDToken(troveId), collateral);
        assertEq(dToken.balanceOf(ALICE), receivedBefore + collateral);
        assertEq(ALICE.balance, ethBefore + ETH_GAS_COMPENSATION);
        assertEq(dToken.balanceOf(address(yieldZapper)), 7);
        assertEq(jpydfToken.balanceOf(BOB), 0);
        assertEq(vault.pendingWithdrawals(), 0, "no Vault redemption or queue dependency");
        assertEq(uint256(branch.troveManager.getTroveStatus(troveId)), uint256(ITroveManager.Status.closedByOwner));
    }

    function test_GuardianL09_OwnerClosesToDToken() external {
        _checkDTokenCloseDefaultReceiver(false);
    }

    function test_GuardianL09_ManagerWithZeroReceiverReturnsDTokenToOwner() external {
        _checkDTokenCloseDefaultReceiver(true);
    }

    function _checkDTokenCloseDefaultReceiver(bool managerCalls) internal {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, address(0));
        address caller = managerCalls ? BOB : ALICE;
        uint256 debt = branch.troveManager.getTroveEntireDebt(troveId);
        uint256 collateral = branch.troveManager.getTroveEntireColl(troveId);
        deal(address(jpydfToken), caller, debt);
        vm.prank(caller);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), debt);
        vault.pauseRedeem();
        uint256 ownerCollateralBefore = dToken.balanceOf(ALICE);
        uint256 ownerEthBefore = ALICE.balance;
        uint256 managerCollateralBefore = dToken.balanceOf(BOB);
        vm.prank(caller);
        assertEq(yieldZapper.closeTroveToDToken(troveId), collateral);
        assertEq(dToken.balanceOf(ALICE), ownerCollateralBefore + collateral);
        assertEq(ALICE.balance, ownerEthBefore + ETH_GAS_COMPENSATION);
        assertEq(dToken.balanceOf(BOB), managerCollateralBefore);
        assertEq(jpydfToken.balanceOf(caller), 0);
        assertEq(vault.pendingWithdrawals(), 0);
        _assertZapperNoTokenResidue();
    }

    function test_CloseTroveToUnderlying_RedeemsCollateralAndReturnsGasComp() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);

        uint256 entireDebt = branch.troveManager.getTroveEntireDebt(troveId);
        deal(address(jpydfToken), ALICE, entireDebt);

        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), entireDebt);

        uint256 underlyingBefore = underlying.balanceOf(ALICE);
        uint256 ethBefore = ALICE.balance;

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = yieldZapper.closeTroveToUnderlying(troveId);

        assertEq(received, 1500e18, "redeemed collateral");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore + 1500e18, "underlying returned");
        assertEq(ALICE.balance, ethBefore + ETH_GAS_COMPENSATION, "gas compensation returned");
        _assertZapperNoTokenResidue();
    }

    function test_CloseTroveToUnderlying_RevertsWhenGasCompensationReceiverRejectsETH() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);

        RevertingEthReceiver receiver = new RevertingEthReceiver();
        vm.prank(ALICE);
        yieldZapper.setRemoveManagerWithReceiver(troveId, BOB, address(receiver));

        uint256 entireDebt = branch.troveManager.getTroveEntireDebt(troveId);
        uint256 collBefore = branch.troveManager.getTroveEntireColl(troveId);
        deal(address(jpydfToken), BOB, entireDebt);

        vm.prank(BOB);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), entireDebt);

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        vm.prank(BOB);
        yieldZapper.closeTroveToUnderlying(troveId);

        assertEq(branch.troveManager.getTroveEntireColl(troveId), collBefore, "trove remains open");
        assertEq(underlying.balanceOf(address(receiver)), 0, "underlying transfer reverted");
        assertEq(address(receiver).balance, 0, "gas compensation not forced");
    }

    function test_CloseTroveToUnderlying_AllowsQueuedRedeemWithoutMinimum() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);
        _protectVaultBufferTo(vault, underlying, 500e18);

        uint256 entireDebt = branch.troveManager.getTroveEntireDebt(troveId);
        deal(address(jpydfToken), ALICE, entireDebt);

        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), entireDebt);

        uint256 underlyingBefore = underlying.balanceOf(ALICE);
        uint256 ethBefore = ALICE.balance;

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = yieldZapper.closeTroveToUnderlying(troveId);

        assertEq(received, 500e18, "partial immediate underlying");
        assertGt(requestId, 0, "queued request");
        assertEq(vault.pendingWithdrawals(), 1000e18, "queued remainder");
        assertEq(underlying.balanceOf(ALICE), underlyingBefore + 500e18, "receiver got immediate buffer");
        assertEq(ALICE.balance, ethBefore + ETH_GAS_COMPENSATION, "gas compensation returned");
        _assertZapperNoTokenResidue();
    }

    function test_CloseTroveToUnderlyingWithMin_RevertsWhenRedeemWouldQueue() external {
        uint256 troveId = _openDefaultTrove();
        _fundAndApproveUnderlying(BOB, 10_000e18);
        _openTroveFor(BOB, 0, 1500e18, 1_500_000e18);
        _protectVaultBufferTo(vault, underlying, 500e18);

        uint256 entireDebt = branch.troveManager.getTroveEntireDebt(troveId);
        deal(address(jpydfToken), ALICE, entireDebt);

        vm.prank(ALICE);
        IERC20(address(jpydfToken)).approve(address(yieldZapper), entireDebt);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientUnderlyingReceived.selector, 500e18, 1500e18
            )
        );
        vm.prank(ALICE);
        yieldZapper.closeTroveToUnderlyingWithMin(troveId, 1500e18);

        assertEq(branch.troveNFT.ownerOf(troveId), ALICE, "trove still open");
        assertEq(vault.pendingWithdrawals(), 0, "no queued request");
    }

    function test_CloseTroveToUnderlying_SixDecimalUnderlyingReturnsRedemptionDust() external {
        DecimalFixture memory fixture = _deployDecimalFixture(6);
        _fundAndApproveDecimalFixture(fixture, ALICE, 10_000e6);
        _fundAndApproveDecimalFixture(fixture, BOB, 10_000e6);

        uint256 troveId = _openDecimalTrove(fixture, ALICE, 0, 1500e6, 1_500_000e18, MIN_ANNUAL_INTEREST_RATE);
        _openDecimalTrove(fixture, BOB, 0, 3000e6, 3_000_000e18, MIN_ANNUAL_INTEREST_RATE + 1);

        vm.warp(block.timestamp + 30 days);
        vm.prank(BOB);
        fixture.collateralRegistry.redeemCollateral(1_500_000e18, 0, 1e18);

        uint256 entireColl = fixture.branch.troveManager.getTroveEntireColl(troveId);
        uint256 redeemableColl = fixture.dToken.convertToDToken(fixture.dToken.convertToUnderlying(entireColl));
        uint256 expectedDust = entireColl - redeemableColl;
        assertGt(expectedDust, 0, "redemption must create sub-USDC dToken dust");

        uint256 entireDebt = fixture.branch.troveManager.getTroveEntireDebt(troveId);
        deal(address(fixture.jpydfToken), ALICE, entireDebt);
        vm.prank(ALICE);
        IERC20(address(fixture.jpydfToken)).approve(address(fixture.zapper), entireDebt);

        uint256 underlyingBefore = fixture.underlying.balanceOf(ALICE);
        uint256 dTokenBefore = fixture.dToken.balanceOf(ALICE);
        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = fixture.zapper.closeTroveToUnderlying(troveId);

        assertEq(received, fixture.dToken.convertToUnderlying(entireColl), "max representable USDC returned");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(fixture.underlying.balanceOf(ALICE), underlyingBefore + received, "USDC returned");
        assertEq(fixture.dToken.balanceOf(ALICE), dTokenBefore + expectedDust, "dToken dust returned");
        _assertDecimalZapperNoTokenResidue(fixture);
    }

    function test_WithdrawCollToUnderlying_SixDecimalUnderlyingReturnsDust() external {
        _assertDecimalWithdrawalReturnsDust(6, 50e18 + 123, 50e6, 123);
    }

    function test_WithdrawCollToUnderlying_EightDecimalUnderlyingReturnsDust() external {
        _assertDecimalWithdrawalReturnsDust(8, 50e18 + 456, 50e8, 456);
    }

    function test_WithdrawCollToUnderlying_QueuedRedeemStillReturnsDust() external {
        DecimalFixture memory fixture = _deployDecimalFixture(6);
        _fundAndApproveDecimalFixture(fixture, ALICE, 10_000e6);
        uint256 troveId = _openDecimalTrove(fixture, ALICE, 0, 1500e6, 1_500_000e18, MIN_ANNUAL_INTEREST_RATE);

        _protectVaultBufferTo(fixture.vault, fixture.underlying, 10e6);

        uint256 underlyingBefore = fixture.underlying.balanceOf(ALICE);
        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = fixture.zapper.withdrawCollToUnderlying(troveId, 50e18 + 123);

        assertEq(received, 10e6, "available USDC returned immediately");
        assertGt(requestId, 0, "remainder queued");
        assertEq(fixture.vault.pendingWithdrawals(), 40e6, "only redeemable remainder queued");
        assertEq(fixture.underlying.balanceOf(ALICE), underlyingBefore + 10e6, "immediate USDC returned");
        assertEq(fixture.dToken.balanceOf(ALICE), 123, "dToken dust returned despite queue");
        _assertDecimalZapperNoTokenResidue(fixture);
    }

    function test_WithdrawCollToUnderlying_OnlyDustSkipsVaultRedeem() external {
        DecimalFixture memory fixture = _deployDecimalFixture(6);
        _fundAndApproveDecimalFixture(fixture, ALICE, 10_000e6);
        uint256 troveId = _openDecimalTrove(fixture, ALICE, 0, 1500e6, 1_500_000e18, MIN_ANNUAL_INTEREST_RATE);

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = fixture.zapper.withdrawCollToUnderlying(troveId, 1);

        assertEq(received, 0, "no whole underlying unit");
        assertEq(requestId, 0, "vault redeem skipped");
        assertEq(fixture.dToken.balanceOf(ALICE), 1, "only-dust amount returned as dToken");
        _assertDecimalZapperNoTokenResidue(fixture);
    }

    function test_WithdrawCollToUnderlyingWithMin_OnlyDustRevertsAtomically() external {
        DecimalFixture memory fixture = _deployDecimalFixture(6);
        _fundAndApproveDecimalFixture(fixture, ALICE, 10_000e6);
        uint256 troveId = _openDecimalTrove(fixture, ALICE, 0, 1500e6, 1_500_000e18, MIN_ANNUAL_INTEREST_RATE);
        uint256 collBefore = fixture.branch.troveManager.getTroveEntireColl(troveId);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientUnderlyingReceived.selector, 0, 1
            )
        );
        vm.prank(ALICE);
        fixture.zapper.withdrawCollToUnderlyingWithMin(troveId, 1, 1);

        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), collBefore, "trove unchanged");
        assertEq(fixture.dToken.balanceOf(ALICE), 0, "dust transfer reverted");
        _assertDecimalZapperNoTokenResidue(fixture);
    }

    function test_RevertWhen_OpenReceivesWrongETH() external {
        IZapper.OpenTroveParams memory params = _openParams(1500e18, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__WrongETH.selector);
        yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION - 1}(params);
    }

    function test_RevertWhen_DirectEthTransferIsNotFromWeth() external {
        deal(address(this), 1 ether);

        (bool success, bytes memory revertData) = address(yieldZapper).call{value: 1 wei}("");

        assertFalse(success, "direct ETH transfer should revert");
        assertEq(bytes4(revertData), CollateralYieldZapper.CollateralYieldZapper__OnlyWETH.selector, "revert selector");
    }

    function test_RevertWhen_VaultDTokenDoesNotMatchRegistryCollateral() external {
        MockERC20 otherUnderlying = new MockERC20("Other", "OTHER", 18);
        (, CollateralVault otherVault) = _deployVault(otherUnderlying);

        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__InvalidVaultDToken.selector);
        new CollateralYieldZapper(
            branch.addressesRegistry,
            otherVault,
            IERC20(address(otherUnderlying)),
            address(0),
            address(0),
            address(this)
        );
    }

    function test_RevertWhen_ZapperDependenciesAreUnset() external {
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__ZeroAddress.selector);
        new CollateralYieldZapper(
            branch.addressesRegistry,
            CollateralVault(address(0)),
            IERC20(address(underlying)),
            address(0),
            address(0),
            address(this)
        );

        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__ZeroAddress.selector);
        new CollateralYieldZapper(
            branch.addressesRegistry, vault, IERC20(address(0)), address(0), address(0), address(this)
        );

        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__ZeroAddress.selector);
        new CollateralYieldZapper(
            branch.addressesRegistry, vault, IERC20(address(underlying)), address(0), address(0), address(0)
        );

        address vaultEoa = makeAddr("vaultEoa");
        vm.expectRevert(
            abi.encodeWithSelector(CollateralYieldZapper.CollateralYieldZapper__NotContract.selector, vaultEoa)
        );
        new CollateralYieldZapper(
            branch.addressesRegistry,
            CollateralVault(vaultEoa),
            IERC20(address(underlying)),
            address(0),
            address(0),
            address(this)
        );

        address underlyingEoa = makeAddr("underlyingEoa");
        vm.expectRevert(
            abi.encodeWithSelector(CollateralYieldZapper.CollateralYieldZapper__NotContract.selector, underlyingEoa)
        );
        new CollateralYieldZapper(
            branch.addressesRegistry, vault, IERC20(underlyingEoa), address(0), address(0), address(this)
        );
    }

    function test_OpenTroveWithNativeEth_StakesWrapsAndOpensTrove() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        uint256 ethAmount = 1800e18;
        uint256 expectedWstEth = 1500e18; // 1800 stETH at 1.2 stETH per wstETH
        uint256 aliceEthBefore = ALICE.balance;

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, ethAmount, 1_500_000e18);

        vm.recordLogs();
        vm.prank(ALICE);
        uint256 troveId =
            fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + ethAmount}(params, expectedWstEth);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(fixture.branch.troveNFT.ownerOf(troveId), ALICE, "owner");
        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), expectedWstEth, "trove dToken collateral");
        assertEq(fixture.jpydfToken.balanceOf(ALICE), 1_500_000e18, "borrowed JPYdf");
        assertEq(ALICE.balance, aliceEthBefore - ETH_GAS_COMPENSATION - ethAmount, "exact ETH taken");
        assertEq(fixture.stEth.balanceOf(address(fixture.wstEth)), ethAmount, "stETH locked in wstETH");
        assertEq(fixture.wstEth.balanceOf(address(fixture.vault)), expectedWstEth, "vault holds wstETH");
        assertEq(weth.balanceOf(address(fixture.branch.pools.gasPool)), ETH_GAS_COMPENSATION, "gas comp held as WETH");
        assertEq(_countReferralLogs(logs, address(fixture.zapper)), 0, "no referral event");
        uint256 routeTroveId = _assertSingleNativeEthRouteDeposit(
            logs, address(fixture.zapper), ALICE, ethAmount, ethAmount, expectedWstEth, expectedWstEth, bytes32(0)
        );
        assertEq(routeTroveId, troveId, "route event trove id");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithNativeEth_RecordsProtocolLidoReferralOnSubmit() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 4000 ether);

        // Both native entrypoints stake through the current protocol-designated Lido referral.
        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);
        vm.prank(ALICE);
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(params, 1500e18);
        assertEq(fixture.stEth.lastSubmitReferral(), LIDO_REFERRAL, "plain native open uses protocol referral");

        IZapper.OpenTroveParams memory referralParams = _openParams(ALICE, 1, 1200e18, 1_000_000e18);
        vm.prank(ALICE);
        fixture.zapper.openTroveWithNativeEthAndReferral{value: ETH_GAS_COMPENSATION + 1200e18}(
            referralParams, 1000e18, bytes32("campaign")
        );
        assertEq(
            fixture.stEth.lastSubmitReferral(),
            LIDO_REFERRAL,
            "borrow-referral variant keeps the protocol Lido referral, not the campaign code"
        );

        // A zero-referral deployment stays valid and submits address(0) (attribution disabled).
        CollateralYieldZapper zeroReferralZapper = new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.wstEth)),
            address(fixture.stEth),
            address(0),
            address(this)
        );
        assertEq(zeroReferralZapper.lidoReferral(), address(0), "zero referral allowed");
        IZapper.OpenTroveParams memory zeroParams = _openParams(ALICE, 2, 600e18, 550_000e18);
        vm.prank(ALICE);
        zeroReferralZapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 600e18}(zeroParams, 500e18);
        assertEq(fixture.stEth.lastSubmitReferral(), address(0), "zero referral submits address(0)");
    }

    function test_SetLidoReferral_ManagerCanUpdateAndDisableAttribution() external {
        LidoFixture memory fixture = _deployLidoFixture();
        address updatedReferral = makeAddr("updatedLidoReferral");
        deal(ALICE, 4000 ether);

        vm.expectEmit(true, true, false, false, address(fixture.zapper));
        emit CollateralYieldZapper.LidoReferralUpdated(LIDO_REFERRAL, updatedReferral);
        fixture.zapper.setLidoReferral(updatedReferral);
        assertEq(fixture.zapper.lidoReferral(), updatedReferral, "manager updates referral");

        IZapper.OpenTroveParams memory updatedParams = _openParams(ALICE, 0, 1800e18, 1_500_000e18);
        vm.prank(ALICE);
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(updatedParams, 1500e18);
        assertEq(fixture.stEth.lastSubmitReferral(), updatedReferral, "submit uses updated referral");

        fixture.zapper.setLidoReferral(address(0));
        assertEq(fixture.zapper.lidoReferral(), address(0), "manager disables attribution");

        IZapper.OpenTroveParams memory disabledParams = _openParams(ALICE, 1, 1200e18, 1_000_000e18);
        vm.prank(ALICE);
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1200e18}(disabledParams, 1000e18);
        assertEq(fixture.stEth.lastSubmitReferral(), address(0), "disabled attribution submits zero");
    }

    function test_SetLidoReferral_RevertsForNonManager() external {
        LidoFixture memory fixture = _deployLidoFixture();

        vm.prank(ALICE);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__UnauthorizedReferralManager.selector);
        fixture.zapper.setLidoReferral(ALICE);
    }

    function test_OpenTroveWithNativeEthAndReferral_EmitsReferralAndRouteEvents() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        uint256 ethAmount = 1800e18;
        bytes32 referralCode = bytes32("REF-ETH");

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, ethAmount, 1_500_000e18);

        vm.recordLogs();
        vm.prank(ALICE);
        uint256 troveId = fixture.zapper.openTroveWithNativeEthAndReferral{value: ETH_GAS_COMPENSATION + ethAmount}(
            params, 1500e18, referralCode
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 referralTroveId = _assertSingleReferralDeposit(
            logs, address(fixture.zapper), ALICE, 1500e18, 1500e18, 1_500_000e18, referralCode
        );
        assertEq(referralTroveId, troveId, "referral trove id");
        uint256 routeTroveId = _assertSingleNativeEthRouteDeposit(
            logs, address(fixture.zapper), ALICE, ethAmount, ethAmount, 1500e18, 1500e18, referralCode
        );
        assertEq(routeTroveId, troveId, "route trove id");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithNativeEth_RevertsWhenSubmitPausedAndPlainPathUnaffected() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        fixture.stEth.setSubmitPaused(true);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__StEthSubmitFailed.selector,
                abi.encodeWithSignature("Error(string)", "STAKE_PAUSED")
            )
        );
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(params, 0);

        assertEq(fixture.stEth.totalSupply(), 0, "no stETH minted");
        assertEq(fixture.wstEth.balanceOf(address(fixture.vault)), 0, "no wstETH deposited");
        assertEq(fixture.dToken.totalSupply(), 0, "no dToken minted");

        // The plain wstETH direct-deposit path keeps working while staking is paused.
        fixture.wstEth.mint(ALICE, 1500e18);
        vm.prank(ALICE);
        fixture.wstEth.approve(address(fixture.zapper), type(uint256).max);

        IZapper.OpenTroveParams memory plainParams = _openParams(ALICE, 1, 1500e18, 1_500_000e18);
        vm.prank(ALICE);
        uint256 troveId = fixture.zapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(plainParams);

        assertEq(fixture.branch.troveNFT.ownerOf(troveId), ALICE, "plain path owner");
        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), 1500e18, "plain path collateral");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithNativeEth_RevertsWhenMinWstEthOutNotMet() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__InsufficientWstEthOut.selector, 1500e18, 1500e18 + 1
            )
        );
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(params, 1500e18 + 1);

        assertEq(fixture.dToken.totalSupply(), 0, "no dToken minted");
    }

    function test_OpenTroveWithNativeEth_SweepsStEthRoundingResidueToCaller() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        fixture.wstEth.setWrapShortfall(2);
        uint256 ethAmount = 1800e18;
        uint256 expectedWstEth = (ethAmount - 2) * 1e18 / 1.2e18;

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, ethAmount, 1_500_000e18);

        vm.prank(ALICE);
        uint256 troveId =
            fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + ethAmount}(params, expectedWstEth);

        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), expectedWstEth, "trove collateral");
        assertEq(fixture.stEth.balanceOf(ALICE), 2, "rounding residue swept to caller");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithNativeEth_RevertsOnWrongMsgValue() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__WrongETH.selector);
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18 - 1}(params, 0);

        IZapper.OpenTroveParams memory zeroParams = _openParams(ALICE, 0, 0, 1_500_000e18);
        vm.prank(ALICE);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__WrongETH.selector);
        fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION}(zeroParams, 0);
    }

    function test_OpenTroveWithNativeEth_RevertsWhenRouteUnavailable() external {
        // setUp's zapper is deployed with _expectedStEth = address(0), so the route is disabled.
        assertEq(address(yieldZapper.stEthToken()), address(0), "route disabled for non-wstETH underlying");

        IZapper.OpenTroveParams memory params = _openParams(1e18, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(CollateralYieldZapper.CollateralYieldZapper__NativeEthRouteUnavailable.selector);
        yieldZapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1e18}(params, 0);
    }

    function test_Constructor_RevertsWhenExpectedStEthMismatches() external {
        LidoFixture memory fixture = _deployLidoFixture();
        address wrongStEth = makeAddr("wrongStEth");

        vm.expectRevert(
            abi.encodeWithSelector(
                CollateralYieldZapper.CollateralYieldZapper__StEthMismatch.selector, address(fixture.stEth), wrongStEth
            )
        );
        new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.wstEth)),
            wrongStEth,
            address(0),
            address(this)
        );

        // A nonzero expected stETH on a non-wstETH underlying reverts deployment outright.
        vm.expectRevert();
        new CollateralYieldZapper(
            branch.addressesRegistry,
            vault,
            IERC20(address(underlying)),
            makeAddr("anyStEth"),
            address(0),
            address(this)
        );
    }

    function test_CloseTroveToUnderlying_AfterNativeEthZapReturnsWstEthAndGasComp() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        deal(BOB, 100 ether);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);
        vm.prank(ALICE);
        uint256 troveId = fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(params, 1500e18);

        // Second trove so the zap-opened trove is closable.
        fixture.wstEth.mint(BOB, 3000e18);
        vm.startPrank(BOB);
        fixture.wstEth.approve(address(fixture.zapper), type(uint256).max);
        fixture.zapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(_openParams(BOB, 0, 3000e18, 3_000_000e18));
        vm.stopPrank();

        uint256 entireDebt = fixture.branch.troveManager.getTroveEntireDebt(troveId);
        deal(address(fixture.jpydfToken), ALICE, entireDebt);
        vm.prank(ALICE);
        IERC20(address(fixture.jpydfToken)).approve(address(fixture.zapper), entireDebt);

        uint256 wstEthBefore = fixture.wstEth.balanceOf(ALICE);
        uint256 ethBefore = ALICE.balance;

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = fixture.zapper.closeTroveToUnderlying(troveId);

        assertEq(received, 1500e18, "redeemed wstETH collateral");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(fixture.wstEth.balanceOf(ALICE), wstEthBefore + 1500e18, "wstETH returned");
        assertEq(fixture.dToken.balanceOf(ALICE), 0, "no dToken dust for 18-decimal underlying");
        assertEq(ALICE.balance, ethBefore + ETH_GAS_COMPENSATION, "gas compensation returned");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function test_OpenTroveWithNativeEth_ReentrantSubmitIsBlockedByGuard() external {
        LidoFixture memory fixture = _deployLidoFixture();
        deal(ALICE, 2000 ether);
        fixture.stEth
            .setReenter(address(fixture.zapper), abi.encodeCall(CollateralYieldZapper.addCollWithUnderlying, (1, 1)));

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1800e18, 1_500_000e18);

        vm.prank(ALICE);
        uint256 troveId = fixture.zapper.openTroveWithNativeEth{value: ETH_GAS_COMPENSATION + 1800e18}(params, 1500e18);

        assertFalse(fixture.stEth.lastReenterSucceeded(), "reentrant call rejected by guard");
        assertEq(fixture.branch.troveManager.getTroveEntireColl(troveId), 1500e18, "outer flow completed");
        _assertLidoZapperNoTokenResidue(fixture);
    }

    function _deployVault(MockERC20 token) internal returns (DToken newDToken, CollateralVault newVault) {
        return
            _deployVaultFor(
                IERC20(address(token)), IERC20MetadataUpgradeable(address(token)), "dMock Underlying", "dMUND"
            );
    }

    function _deployVaultFor(
        IERC20 token,
        IERC20MetadataUpgradeable tokenMetadata,
        string memory name,
        string memory symbol
    ) internal returns (DToken newDToken, CollateralVault newVault) {
        DToken dTokenImpl = new DToken();
        CollateralVault vaultImpl = new CollateralVault();
        address predictedVault = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        bytes memory dInit = abi.encodeWithSelector(DToken.initialize.selector, predictedVault, address(this));
        newDToken = DToken(address(new ERC1967Proxy(address(dTokenImpl), dInit)));
        newDToken.setAllowedUnderlying(address(token), true);

        bytes memory vInit = abi.encodeWithSelector(
            CollateralVault.initialize.selector, token, IDToken(address(newDToken)), TREASURY, address(this)
        );
        newVault = CollateralVault(address(new ERC1967Proxy(address(vaultImpl), vInit)));
        assertEq(address(newVault), predictedVault, "vault prediction");

        newDToken.setTokenInfo(name, symbol, tokenMetadata);
    }

    function _deployBranchForDToken(DToken branchDToken)
        internal
        returns (
            TestDeployer.LiquityContractsDev memory deployedBranch,
            ICollateralRegistry deployedCollateralRegistry,
            IJpydfToken deployedJpydfToken,
            HintHelpers deployedHintHelpers,
            MultiTroveGetter deployedMultiTroveGetter,
            TestDeployer.Zappers memory deployedZappers
        )
    {
        CollateralYieldBranchDeployer deployer = new CollateralYieldBranchDeployer();
        (
            deployedBranch,
            deployedCollateralRegistry,
            deployedJpydfToken,
            deployedHintHelpers,
            deployedMultiTroveGetter,
            deployedZappers
        ) = deployer.deployDTokenBranch(IERC20Metadata(address(branchDToken)), IWETH(address(weth)));
        branchDToken.setRiskParamsRegistry(address(deployedBranch.addressesRegistry));
        branchDToken.setCap(type(uint256).max);
        deployedBranch.priceFeed.setPrice(2000e18);
    }

    function _deployPermitFixture() internal returns (PermitFixture memory fixture) {
        fixture.underlying = new MockERC20PermitToken("Permit Underlying", "pUND");
        (fixture.dToken, fixture.vault) = _deployVaultFor(
            IERC20(address(fixture.underlying)),
            IERC20MetadataUpgradeable(address(fixture.underlying)),
            "dPUND",
            "dPUND"
        );
        (fixture.branch,, fixture.jpydfToken,,,) = _deployBranchForDToken(fixture.dToken);
        fixture.zapper = new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.underlying)),
            address(0),
            address(0),
            address(this)
        );
    }

    address internal constant LIDO_REFERRAL = address(0xD314141414141414141414141414141414141414);

    function _deployLidoFixture() internal returns (LidoFixture memory fixture) {
        fixture.stEth = new MockStETH();
        fixture.wstEth = new MockWstETH(fixture.stEth);
        (fixture.dToken, fixture.vault) = _deployVaultFor(
            IERC20(address(fixture.wstEth)), IERC20MetadataUpgradeable(address(fixture.wstEth)), "dwstETH", "dwstETH"
        );
        (fixture.branch,, fixture.jpydfToken,,,) = _deployBranchForDToken(fixture.dToken);
        fixture.zapper = new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.wstEth)),
            address(fixture.stEth),
            LIDO_REFERRAL,
            address(this)
        );
        assertEq(address(fixture.zapper.stEthToken()), address(fixture.stEth), "stETH resolved from wstETH");
        assertEq(fixture.zapper.lidoReferral(), LIDO_REFERRAL, "initial protocol Lido referral");
    }

    function _deployFeeOnTransferFixture() internal returns (FeeOnTransferFixture memory fixture) {
        fixture.underlying = new FeeOnTransferZapperToken();
        (fixture.dToken, fixture.vault) = _deployVaultFor(
            IERC20(address(fixture.underlying)),
            IERC20MetadataUpgradeable(address(fixture.underlying)),
            "dFee Underlying",
            "dfUND"
        );
        (fixture.branch,, fixture.jpydfToken,,,) = _deployBranchForDToken(fixture.dToken);
        fixture.zapper = new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.underlying)),
            address(0),
            address(0),
            address(this)
        );
    }

    function _assertLidoZapperNoTokenResidue(LidoFixture memory fixture) internal view {
        assertEq(fixture.stEth.balanceOf(address(fixture.zapper)), 0, "lido zapper stETH residue");
        assertEq(fixture.wstEth.balanceOf(address(fixture.zapper)), 0, "lido zapper wstETH residue");
        assertEq(fixture.dToken.balanceOf(address(fixture.zapper)), 0, "lido zapper dToken residue");
        assertEq(IERC20(address(fixture.jpydfToken)).balanceOf(address(fixture.zapper)), 0, "lido zapper JPYdf residue");
        assertEq(weth.balanceOf(address(fixture.zapper)), 0, "lido zapper WETH residue");
        assertEq(address(fixture.zapper).balance, 0, "lido zapper native ETH residue");
        assertEq(
            fixture.stEth.allowance(address(fixture.zapper), address(fixture.wstEth)), 0, "lido zapper stETH allowance"
        );
    }

    function _assertSingleNativeEthRouteDeposit(
        Vm.Log[] memory logs,
        address emitter,
        address expectedUser,
        uint256 expectedEthAmount,
        uint256 expectedStEthAmount,
        uint256 expectedWstEthAmount,
        uint256 expectedDTokenAmount,
        bytes32 expectedReferralCode
    ) internal pure returns (uint256 troveId) {
        uint256 count;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != emitter || logs[i].topics.length == 0
                    || logs[i].topics[0] != NativeEthRouteDeposit.selector
            ) {
                continue;
            }

            ++count;
            assertEq(logs[i].topics.length, 4, "native eth route topic count");
            assertEq(address(uint160(uint256(logs[i].topics[1]))), expectedUser, "native eth route user");
            troveId = uint256(logs[i].topics[2]);
            assertEq(logs[i].topics[3], expectedReferralCode, "native eth route referral code");

            (uint256 ethAmount, uint256 stEthAmount, uint256 wstEthAmount, uint256 dTokenAmount) =
                abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            assertEq(ethAmount, expectedEthAmount, "native eth route ETH amount");
            assertEq(stEthAmount, expectedStEthAmount, "native eth route stETH amount");
            assertEq(wstEthAmount, expectedWstEthAmount, "native eth route wstETH amount");
            assertEq(dTokenAmount, expectedDTokenAmount, "native eth route dToken amount");
        }

        assertEq(count, 1, "single native eth route deposit event");
    }

    function _deployDecimalFixture(uint8 decimals) internal returns (DecimalFixture memory fixture) {
        fixture.underlying = new MockERC20("Decimal Underlying", "UND", decimals);
        (fixture.dToken, fixture.vault) = _deployVault(fixture.underlying);
        (fixture.branch, fixture.collateralRegistry, fixture.jpydfToken,,,) = _deployBranchForDToken(fixture.dToken);
        fixture.zapper = new CollateralYieldZapper(
            fixture.branch.addressesRegistry,
            fixture.vault,
            IERC20(address(fixture.underlying)),
            address(0),
            address(0),
            address(this)
        );
    }

    function _fundAndApproveDecimalFixture(DecimalFixture memory fixture, address user, uint256 amount) internal {
        deal(user, 100 ether);
        fixture.underlying.mint(user, amount);
        vm.prank(user);
        fixture.underlying.approve(address(fixture.zapper), type(uint256).max);
    }

    function _openDecimalTrove(
        DecimalFixture memory fixture,
        address user,
        uint256 ownerIndex,
        uint256 collAmount,
        uint256 jpydfAmount,
        uint256 annualInterestRate
    ) internal returns (uint256 troveId) {
        IZapper.OpenTroveParams memory params = _openParams(user, ownerIndex, collAmount, jpydfAmount);
        params.annualInterestRate = annualInterestRate;
        vm.prank(user);
        troveId = fixture.zapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);
    }

    function _assertDecimalWithdrawalReturnsDust(
        uint8 decimals,
        uint256 dTokenAmount,
        uint256 expectedUnderlying,
        uint256 expectedDust
    ) internal {
        DecimalFixture memory fixture = _deployDecimalFixture(decimals);
        uint256 unit = 10 ** decimals;
        _fundAndApproveDecimalFixture(fixture, ALICE, 10_000 * unit);
        uint256 troveId = _openDecimalTrove(fixture, ALICE, 0, 1500 * unit, 1_500_000e18, MIN_ANNUAL_INTEREST_RATE);
        uint256 underlyingBefore = fixture.underlying.balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 received, uint256 requestId) = fixture.zapper.withdrawCollToUnderlying(troveId, dTokenAmount);

        assertEq(received, expectedUnderlying, "whole underlying units returned");
        assertEq(requestId, 0, "immediate redeem");
        assertEq(fixture.underlying.balanceOf(ALICE), underlyingBefore + expectedUnderlying, "underlying returned");
        assertEq(fixture.dToken.balanceOf(ALICE), expectedDust, "dToken dust returned");
        _assertDecimalZapperNoTokenResidue(fixture);
    }

    function _assertDecimalZapperNoTokenResidue(DecimalFixture memory fixture) internal view {
        assertEq(fixture.underlying.balanceOf(address(fixture.zapper)), 0, "decimal zapper underlying residue");
        assertEq(fixture.dToken.balanceOf(address(fixture.zapper)), 0, "decimal zapper dToken residue");
        assertEq(
            IERC20(address(fixture.jpydfToken)).balanceOf(address(fixture.zapper)), 0, "decimal zapper JPYdf residue"
        );
    }

    function _signPermit(
        uint256 privateKey,
        MockERC20PermitToken token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                token.nonces(owner),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }

    function _openDefaultTrove() internal returns (uint256 troveId) {
        troveId = _openTroveFor(ALICE, 0, 1500e18, 1_500_000e18);
    }

    function _openTroveFor(address user, uint256 ownerIndex, uint256 collAmount, uint256 jpydfAmount)
        internal
        returns (uint256 troveId)
    {
        IZapper.OpenTroveParams memory params = _openParams(user, ownerIndex, collAmount, jpydfAmount);
        vm.prank(user);
        troveId = yieldZapper.openTroveWithRawETH{value: ETH_GAS_COMPENSATION}(params);
    }

    function _openParams(uint256 collAmount, uint256 jpydfAmount)
        internal
        pure
        returns (IZapper.OpenTroveParams memory)
    {
        return _openParams(ALICE, 0, collAmount, jpydfAmount);
    }

    function _openParams(address owner, uint256 ownerIndex, uint256 collAmount, uint256 jpydfAmount)
        internal
        pure
        returns (IZapper.OpenTroveParams memory)
    {
        return IZapper.OpenTroveParams({
            owner: owner,
            ownerIndex: ownerIndex,
            collAmount: collAmount,
            jpydfAmount: jpydfAmount,
            upperHint: 0,
            lowerHint: 0,
            annualInterestRate: MIN_ANNUAL_INTEREST_RATE,
            batchManager: address(0),
            maxUpfrontFee: 150_000e18,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
    }

    function _countReferralLogs(Vm.Log[] memory logs, address emitter) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == ReferralDeposit.selector
            ) {
                ++count;
            }
        }
    }

    function _assertSingleReferralDeposit(
        Vm.Log[] memory logs,
        address emitter,
        address expectedUser,
        uint256 expectedUnderlyingAmount,
        uint256 expectedDTokenAmount,
        uint256 expectedJpydfAmount,
        bytes32 expectedReferralCode
    ) internal pure returns (uint256 troveId) {
        uint256 count;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != emitter || logs[i].topics.length == 0
                    || logs[i].topics[0] != ReferralDeposit.selector
            ) {
                continue;
            }

            ++count;
            assertEq(logs[i].topics.length, 4, "referral topic count");
            assertEq(address(uint160(uint256(logs[i].topics[1]))), expectedUser, "referral user");
            troveId = uint256(logs[i].topics[2]);
            assertEq(logs[i].topics[3], expectedReferralCode, "referral code");

            (uint256 underlyingAmount, uint256 dTokenAmount, uint256 jpydfAmount) =
                abi.decode(logs[i].data, (uint256, uint256, uint256));
            assertEq(underlyingAmount, expectedUnderlyingAmount, "referral underlying amount");
            assertEq(dTokenAmount, expectedDTokenAmount, "referral dToken amount");
            assertEq(jpydfAmount, expectedJpydfAmount, "referral JPYdf amount");
        }

        assertEq(count, 1, "single referral event");
    }

    function _assertZapperNoTokenResidue() internal view {
        assertEq(underlying.balanceOf(address(yieldZapper)), 0, "zapper underlying residue");
        assertEq(dToken.balanceOf(address(yieldZapper)), 0, "zapper dToken residue");
        assertEq(IERC20(address(jpydfToken)).balanceOf(address(yieldZapper)), 0, "zapper jpydf residue");
    }

    function _assertPermitZapperNoTokenResidue(PermitFixture memory fixture) internal view {
        assertEq(fixture.underlying.balanceOf(address(fixture.zapper)), 0, "permit zapper underlying residue");
        assertEq(fixture.dToken.balanceOf(address(fixture.zapper)), 0, "permit zapper dToken residue");
        assertEq(
            IERC20(address(fixture.jpydfToken)).balanceOf(address(fixture.zapper)), 0, "permit zapper JPYdf residue"
        );
    }

    function _fundAndApproveUnderlying(address user, uint256 amount) internal {
        deal(user, 100 ether);
        underlying.mint(user, amount);
        vm.prank(user);
        underlying.approve(address(yieldZapper), type(uint256).max);
    }

    /// @dev Model healthy illiquidity by reclassifying Vault-held assets as protected reserve.
    function _protectVaultBufferTo(CollateralVault targetVault, MockERC20 token, uint256 targetBuffer) internal {
        uint256 currentBuffer = targetVault.bufferBalance();
        assertGe(currentBuffer, targetBuffer, "vault buffer below target");

        uint256 protectedAmount = currentBuffer - targetBuffer;
        token.mint(address(this), protectedAmount);
        token.approve(address(targetVault), protectedAmount);
        targetVault.backstopDeposit(protectedAmount);
        token.burn(address(targetVault), protectedAmount);

        assertEq(targetVault.bufferBalance(), targetBuffer, "target buffer");
        assertEq(targetVault.backingRatio(), 1e18, "queue fixture remains fully backed");
    }
}
