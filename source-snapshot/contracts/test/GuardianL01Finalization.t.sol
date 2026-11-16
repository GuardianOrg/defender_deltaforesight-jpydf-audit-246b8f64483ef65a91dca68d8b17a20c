// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20MetadataUpgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {DToken} from "src/DToken.sol";
import {CollateralVault} from "src/CollateralVault.sol";
import {AddressesRegistry} from "src/AddressesRegistry.sol";
import {RiskParams} from "src/Types/RiskParams.sol";
import {YieldLayerProxyDeployer} from "script/DeployLiquity2.s.sol";
import {CollateralYieldBranchDeployer} from "test/CollateralYieldZapper.t.sol";
import {TestDeployer} from "test/TestContracts/Deployment.t.sol";
import {WETH9} from "test/TestContracts/WETH.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract GuardianL01FinalizationTest is Test {
    DToken private token;
    CollateralVault private vault;
    MockERC20 private underlying;
    AddressesRegistry private registry;
    address private attacker = makeAddr("attacker");

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND", 6);
        YieldLayerProxyDeployer helper =
            new YieldLayerProxyDeployer(address(new DToken()), address(new CollateralVault()));
        (token, vault) = helper.deployYieldLayer(
            IERC20MetadataUpgradeable(address(underlying)), "dUND", "dUND", address(this), address(this)
        );
        token.acceptOwnership();

        CollateralYieldBranchDeployer deployer = new CollateralYieldBranchDeployer();
        deployer.setRiskParamsFinalizer(address(this));
        (TestDeployer.LiquityContractsDev memory branch,,,,,) =
            deployer.deployDTokenBranch(IERC20Metadata(address(token)), new WETH9());
        registry = AddressesRegistry(address(branch.addressesRegistry));
        token.setRiskParamsRegistry(address(registry));
    }

    function testFuzz_GuardianL01_DepositCannotBlockFinalization(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        assertEq(token.cap(), 0);
        assertFalse(registry.riskParamsFinalized());

        // An owner mistake cannot open the cap while the branch is reserved.
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        token.setCap(type(uint256).max);
        underlying.mint(attacker, amount);
        vm.startPrank(attacker);
        underlying.approve(address(vault), amount);
        vm.expectRevert(DToken.DToken__RiskParamsNotFinalized.selector);
        vault.deposit(amount);
        vm.stopPrank();
        assertEq(token.totalSupply(), 0);
        assertEq(underlying.balanceOf(attacker), amount);
        assertEq(underlying.balanceOf(address(vault)), 0, "failed deposit rolls back transfer");

        RiskParams memory params = RiskParams(150e16, 125e16, 10e16, 110e16, 5e16, 10e16, 2 ether);
        registry.finalizeRiskParams(address(underlying), params);
        assertTrue(registry.riskParamsFinalized());
        token.setCap(amount * 1e12);
        vm.prank(attacker);
        vault.deposit(amount);
        assertEq(token.balanceOf(attacker), amount * 1e12);

        // Closing issuance does not block safe redemption; reopening still works.
        token.setCap(0);
        vm.prank(attacker);
        vault.redeem(amount * 1e12, attacker);
        assertEq(token.totalSupply(), 0);
        assertEq(underlying.balanceOf(attacker), amount);
        token.setCap(amount * 1e12);
    }
}
