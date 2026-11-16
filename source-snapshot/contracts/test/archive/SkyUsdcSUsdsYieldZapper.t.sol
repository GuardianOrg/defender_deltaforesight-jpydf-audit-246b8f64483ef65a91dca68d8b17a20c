// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IERC20MetadataUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {CollateralVault} from "src/CollateralVault.sol";
import {DToken} from "src/DToken.sol";
import {HintHelpers} from "src/HintHelpers.sol";
import {MultiTroveGetter} from "src/MultiTroveGetter.sol";
import {ETH_GAS_COMPENSATION, MIN_ANNUAL_INTEREST_RATE} from "src/Dependencies/Constants.sol";
import {ICollateralRegistry} from "src/Interfaces/ICollateralRegistry.sol";
import {IDToken} from "src/Interfaces/IDToken.sol";
import {IJpydfToken} from "src/Interfaces/IJpydfToken.sol";
import {IWETH} from "src/Interfaces/IWETH.sol";
import {ISkyLitePsmWrapper, ISkyUsdcSUsdsConverter} from "src/Interfaces/ISkyUsdcSUsdsConverter.sol";
import {CollateralYieldZapper} from "src/Zappers/CollateralYieldZapper.sol";
import {IZapper} from "src/Zappers/Interfaces/IZapper.sol";
import {SkyUsdcSUsdsYieldZapper} from "src/Zappers/archive/SkyUsdcSUsdsYieldZapper.sol";

import {CollateralYieldBranchDeployer} from "../CollateralYieldZapper.t.sol";
import {TestDeployer} from "../TestContracts/Deployment.t.sol";
import {WETH9} from "../TestContracts/WETH.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract MockSUsdsVault is ERC20, ERC4626 {
    constructor(IERC20 asset_) ERC20("Savings USDS", "sUSDS") ERC4626(asset_) {}

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }
}

contract MockUsdcUsdsConverter is ISkyUsdcSUsdsConverter {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    MockERC20 public immutable usds;

    constructor(IERC20 _usdc, MockERC20 _usds) {
        usdc = _usdc;
        usds = _usds;
    }

    function usdcToken() external view returns (IERC20) {
        return usdc;
    }

    function usdsToken() external view returns (IERC20) {
        return IERC20(address(usds));
    }

    function psmWrapper() external pure returns (ISkyLitePsmWrapper) {
        return ISkyLitePsmWrapper(address(0));
    }

    function isUsdsToUsdcRouteHalted() external pure returns (bool) {
        return false;
    }

    function convertUsdsToUsdc(uint256, uint256, address) external pure returns (uint256) {
        revert("UNUSED");
    }

    function previewUsdsToUsdc(uint256) external pure returns (uint256) {
        return 0;
    }

    function convertUsdcToUsds(uint256 usdcAmount, uint256 minUsdsOut, address receiver)
        external
        returns (uint256 usdsOut)
    {
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        usdsOut = usdcAmount * 1e12;
        require(usdsOut >= minUsdsOut, "USDS_OUT");
        usds.mint(receiver, usdsOut);
    }
}

contract UnderPullUsdcUsdsConverter is ISkyUsdcSUsdsConverter {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    MockERC20 public immutable usds;

    constructor(IERC20 _usdc, MockERC20 _usds) {
        usdc = _usdc;
        usds = _usds;
    }

    function usdcToken() external view returns (IERC20) {
        return usdc;
    }

    function usdsToken() external view returns (IERC20) {
        return IERC20(address(usds));
    }

    function psmWrapper() external pure returns (ISkyLitePsmWrapper) {
        return ISkyLitePsmWrapper(address(0));
    }

    function isUsdsToUsdcRouteHalted() external pure returns (bool) {
        return false;
    }

    function convertUsdsToUsdc(uint256, uint256, address) external pure returns (uint256) {
        revert("UNUSED");
    }

    function previewUsdsToUsdc(uint256) external pure returns (uint256) {
        return 0;
    }

    function convertUsdcToUsds(uint256 usdcAmount, uint256 minUsdsOut, address receiver)
        external
        returns (uint256 usdsOut)
    {
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount - 1);
        usdsOut = usdcAmount * 1e12;
        require(usdsOut >= minUsdsOut, "USDS_OUT");
        usds.mint(receiver, usdsOut);
    }
}

contract SkyUsdcSUsdsYieldZapperTest is Test {
    event ReferralDeposit(
        address indexed user,
        uint256 indexed troveId,
        uint256 underlyingAmount,
        uint256 dTokenAmount,
        uint256 jpydfAmount,
        bytes32 indexed referralCode
    );

    address private constant TREASURY = address(0xA11CE);
    address internal constant ALICE = address(0x1001);
    address internal constant BOB = address(0x1002);

    event SkyUsdcRouteDeposit(
        address indexed user,
        uint256 indexed troveId,
        uint256 usdcAmount,
        uint256 usdsAmount,
        uint256 susdsAmount,
        uint256 dTokenAmount,
        bytes32 indexed referralCode
    );
    event SkyUsdcRouteAddColl(
        address indexed user,
        uint256 indexed troveId,
        uint256 usdcAmount,
        uint256 usdsAmount,
        uint256 susdsAmount,
        uint256 dTokenAmount
    );

    struct SkyRouteFixture {
        MockERC20 usdc;
        MockERC20 usds;
        MockSUsdsVault susds;
        ISkyUsdcSUsdsConverter converter;
        DToken skyDToken;
        CollateralVault skyVault;
        TestDeployer.LiquityContractsDev skyBranch;
        IJpydfToken skyJpydfToken;
        SkyUsdcSUsdsYieldZapper skyZapper;
    }

    function test_SkyRoute_ConvertsUsdcThroughUsdsAndSusdsForOpenReferralAddCollAndSlippage() external {
        SkyRouteFixture memory fixture = _deploySkyRoute();
        _fundAndApproveUsdc(fixture.usdc, fixture.skyZapper, ALICE, 10_000e6);

        MockERC20 badUsdc = new MockERC20("Bad USDC", "bUSDC", 18);
        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsYieldZapper.SkyUsdcSUsdsYieldZapper__InvalidUsdcDecimals.selector, 18)
        );
        new SkyUsdcSUsdsYieldZapper(
            fixture.skyBranch.addressesRegistry,
            fixture.skyVault,
            fixture.susds,
            IERC20(address(badUsdc)),
            IERC20(address(fixture.usds)),
            fixture.converter,
            address(this)
        );

        address converterEoa = makeAddr("converterEoa");
        vm.expectRevert(
            abi.encodeWithSelector(SkyUsdcSUsdsYieldZapper.SkyUsdcSUsdsYieldZapper__NotContract.selector, converterEoa)
        );
        new SkyUsdcSUsdsYieldZapper(
            fixture.skyBranch.addressesRegistry,
            fixture.skyVault,
            fixture.susds,
            IERC20(address(fixture.usdc)),
            IERC20(address(fixture.usds)),
            ISkyUsdcSUsdsConverter(converterEoa),
            address(this)
        );

        address susdsEoa = makeAddr("susdsEoa");
        vm.expectRevert(
            abi.encodeWithSelector(CollateralYieldZapper.CollateralYieldZapper__NotContract.selector, susdsEoa)
        );
        new SkyUsdcSUsdsYieldZapper(
            fixture.skyBranch.addressesRegistry,
            fixture.skyVault,
            IERC4626(susdsEoa),
            IERC20(address(fixture.usdc)),
            IERC20(address(fixture.usds)),
            fixture.converter,
            address(this)
        );

        IZapper.OpenTroveParams memory params = _openParams(1500e6, 1_500_000e18);

        vm.prank(ALICE);
        vm.expectRevert(SkyUsdcSUsdsYieldZapper.SkyUsdcSUsdsYieldZapper__ZeroAmount.selector);
        fixture.skyZapper.openTroveWithUsdc{value: ETH_GAS_COMPENSATION}(_openParams(0, 1_500_000e18), 0, 0);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                SkyUsdcSUsdsYieldZapper.SkyUsdcSUsdsYieldZapper__InsufficientSUsdsOut.selector, 1500e18, 1501e18
            )
        );
        fixture.skyZapper.openTroveWithUsdc{value: ETH_GAS_COMPENSATION}(params, 1500e18, 1501e18);

        vm.prank(ALICE);
        uint256 troveId = fixture.skyZapper.openTroveWithUsdc{value: ETH_GAS_COMPENSATION}(params, 1500e18, 1500e18);

        assertEq(fixture.skyBranch.troveNFT.ownerOf(troveId), ALICE, "owner");
        assertEq(fixture.skyBranch.troveManager.getTroveEntireColl(troveId), 1500e18, "dUSDS collateral");
        assertEq(fixture.skyJpydfToken.balanceOf(ALICE), 1_500_000e18, "borrowed JPYdf");
        assertEq(fixture.usdc.balanceOf(ALICE), 8500e6, "USDC pulled");
        assertEq(fixture.susds.balanceOf(address(fixture.skyVault)), 1500e18, "Vault holds sUSDS");
        _assertSkyZapperNoTokenResidue(fixture);

        {
            bytes32 referralCode = bytes32("REF-7");

            IZapper.OpenTroveParams memory referralParams = _openParams(ALICE, 1, 1500e6, 1_500_000e18);
            vm.recordLogs();
            vm.prank(ALICE);
            uint256 referralTroveId = fixture.skyZapper.openTroveWithUsdcAndReferral{value: ETH_GAS_COMPENSATION}(
                referralParams, 1500e18, 1500e18, referralCode
            );
            Vm.Log[] memory logs = vm.getRecordedLogs();

            uint256 referralDepositTroveId = _assertSingleReferralDeposit(
                logs, address(fixture.skyZapper), ALICE, 1500e6, 1500e18, 1_500_000e18, referralCode
            );
            uint256 skyRouteTroveId = _assertSingleSkyUsdcRouteDeposit(
                logs, address(fixture.skyZapper), ALICE, 1500e6, 1500e18, 1500e18, 1500e18, referralCode
            );
            assertEq(referralDepositTroveId, referralTroveId, "sky referral deposit trove id");
            assertEq(skyRouteTroveId, referralTroveId, "sky route trove id");
        }

        vm.expectEmit(true, true, false, true, address(fixture.skyZapper));
        emit SkyUsdcRouteAddColl(ALICE, troveId, 100e6, 100e18, 100e18, 100e18);
        vm.prank(ALICE);
        (uint256 usdsAmount, uint256 susdsAmount, uint256 dTokenAmount) =
            fixture.skyZapper.addCollWithUsdc(troveId, 100e6, 100e18, 100e18);

        assertEq(usdsAmount, 100e18, "USDS amount");
        assertEq(susdsAmount, 100e18, "sUSDS amount");
        assertEq(dTokenAmount, 100e18, "dUSDS amount");
        assertEq(fixture.skyBranch.troveManager.getTroveEntireColl(troveId), 1600e18, "coll after add");
        assertEq(fixture.usdc.balanceOf(ALICE), 6900e6, "USDC pulled");
        assertEq(fixture.susds.balanceOf(address(fixture.skyVault)), 3100e18, "Vault holds sUSDS");
        _assertSkyZapperNoTokenResidue(fixture);
    }

    function test_SkyRoute_RevertsWhenConverterLeavesUsdcResidue() external {
        SkyRouteFixture memory fixture = _deploySkyRouteWithUnderPullConverter();
        _fundAndApproveUsdc(fixture.usdc, fixture.skyZapper, ALICE, 10_000e6);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                SkyUsdcSUsdsYieldZapper.SkyUsdcSUsdsYieldZapper__UnexpectedTokenResidue.selector,
                address(fixture.usdc),
                0,
                1
            )
        );
        fixture.skyZapper.openTroveWithUsdc{value: ETH_GAS_COMPENSATION}(_openParams(1500e6, 1_500_000e18), 0, 0);
    }

    function test_SkyRoute_RevertsWhenOwnerIsNotSender() external {
        SkyRouteFixture memory fixture = _deploySkyRoute();
        _fundAndApproveUsdc(fixture.usdc, fixture.skyZapper, BOB, 10_000e6);
        deal(BOB, 100 ether);

        IZapper.OpenTroveParams memory params = _openParams(ALICE, 0, 1500e6, 1_500_000e18);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(CollateralYieldZapper.CollateralYieldZapper__OwnerMismatch.selector, ALICE, BOB)
        );
        fixture.skyZapper.openTroveWithUsdc{value: ETH_GAS_COMPENSATION}(params, 1500e18, 1500e18);
    }

    function _deploySkyRoute() internal returns (SkyRouteFixture memory fixture) {
        fixture.usdc = new MockERC20("USD Coin", "USDC", 6);
        fixture.usds = new MockERC20("USDS", "USDS", 18);
        fixture.susds = new MockSUsdsVault(IERC20(address(fixture.usds)));
        fixture.converter = new MockUsdcUsdsConverter(IERC20(address(fixture.usdc)), fixture.usds);

        fixture = _deploySkyRouteContracts(fixture);
    }

    function _deploySkyRouteWithUnderPullConverter() internal returns (SkyRouteFixture memory fixture) {
        fixture.usdc = new MockERC20("USD Coin", "USDC", 6);
        fixture.usds = new MockERC20("USDS", "USDS", 18);
        fixture.susds = new MockSUsdsVault(IERC20(address(fixture.usds)));
        fixture.converter = new UnderPullUsdcUsdsConverter(IERC20(address(fixture.usdc)), fixture.usds);

        fixture = _deploySkyRouteContracts(fixture);
    }

    function _deploySkyRouteContracts(SkyRouteFixture memory fixture) internal returns (SkyRouteFixture memory) {
        (fixture.skyDToken, fixture.skyVault) = _deployVaultFor(
            IERC20(address(fixture.susds)), IERC20MetadataUpgradeable(address(fixture.susds)), "dUSDS", "dUSDS"
        );

        (fixture.skyBranch,, fixture.skyJpydfToken,,,) = _deployBranchForDToken(fixture.skyDToken);
        fixture.skyZapper = new SkyUsdcSUsdsYieldZapper(
            fixture.skyBranch.addressesRegistry,
            fixture.skyVault,
            fixture.susds,
            IERC20(address(fixture.usdc)),
            IERC20(address(fixture.usds)),
            fixture.converter,
            address(this)
        );
        return fixture;
    }

    function _assertSingleSkyUsdcRouteDeposit(
        Vm.Log[] memory logs,
        address emitter,
        address expectedUser,
        uint256 expectedUsdcAmount,
        uint256 expectedUsdsAmount,
        uint256 expectedSUsdsAmount,
        uint256 expectedDTokenAmount,
        bytes32 expectedReferralCode
    ) internal pure returns (uint256 troveId) {
        uint256 count;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != emitter || logs[i].topics.length == 0
                    || logs[i].topics[0] != SkyUsdcRouteDeposit.selector
            ) {
                continue;
            }

            ++count;
            assertEq(logs[i].topics.length, 4, "sky route topic count");
            assertEq(address(uint160(uint256(logs[i].topics[1]))), expectedUser, "sky route user");
            troveId = uint256(logs[i].topics[2]);
            assertEq(logs[i].topics[3], expectedReferralCode, "sky route referral code");

            (uint256 usdcAmount, uint256 usdsAmount, uint256 susdsAmount, uint256 dTokenAmount) =
                abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
            assertEq(usdcAmount, expectedUsdcAmount, "sky route USDC amount");
            assertEq(usdsAmount, expectedUsdsAmount, "sky route USDS amount");
            assertEq(susdsAmount, expectedSUsdsAmount, "sky route sUSDS amount");
            assertEq(dTokenAmount, expectedDTokenAmount, "sky route dToken amount");
        }

        assertEq(count, 1, "single sky route deposit event");
    }

    function _assertSkyZapperNoTokenResidue(SkyRouteFixture memory fixture) internal view {
        assertEq(fixture.usdc.balanceOf(address(fixture.skyZapper)), 0, "sky zapper USDC residue");
        assertEq(fixture.usds.balanceOf(address(fixture.skyZapper)), 0, "sky zapper USDS residue");
        assertEq(fixture.susds.balanceOf(address(fixture.skyZapper)), 0, "sky zapper sUSDS residue");
        assertEq(fixture.skyDToken.balanceOf(address(fixture.skyZapper)), 0, "sky zapper dUSDS residue");
        assertEq(fixture.skyJpydfToken.balanceOf(address(fixture.skyZapper)), 0, "sky zapper JPYdf residue");
        assertEq(
            fixture.usdc.allowance(address(fixture.skyZapper), address(fixture.converter)),
            0,
            "sky zapper converter USDC allowance"
        );
        assertEq(
            fixture.usds.allowance(address(fixture.skyZapper), address(fixture.susds)),
            0,
            "sky zapper sUSDS vault USDS allowance"
        );
    }

    function _fundAndApproveUsdc(MockERC20 usdc, SkyUsdcSUsdsYieldZapper skyZapper, address user, uint256 amount)
        internal
    {
        deal(user, 100 ether);
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(skyZapper), type(uint256).max);
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
        WETH9 weth = new WETH9();
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
}
