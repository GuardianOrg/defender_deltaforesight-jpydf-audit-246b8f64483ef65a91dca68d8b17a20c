// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "../script/DeployLiquity2.s.sol";
import "../src/AddressesRegistry.sol";

contract ExternalAuditInfo06DeployHarness is DeployLiquity2Script {
    function verifyAddressesRegistryWiring(IAddressesRegistry registry, IAddressesRegistry.AddressVars memory expected)
        external
    {
        _verifyAddressesRegistryWiring(registry, expected);
    }
}

contract ExternalAuditInfo06CodeStub {}

contract ExternalAuditInfo06AddressesRegistryWiringTest is Test {
    ExternalAuditInfo06DeployHarness internal harness;

    function setUp() public {
        harness = new ExternalAuditInfo06DeployHarness();
    }

    function test_PostDeployVerifierAcceptsAll18DistinctCodeBackedAddresses() public {
        IAddressesRegistry.AddressVars memory vars = _completeCodeBackedVars();
        AddressesRegistry registry = _configuredRegistry(vars);

        harness.verifyAddressesRegistryWiring(registry, vars);
    }

    function test_PostDeployVerifierRejectsFieldMismatch() public {
        IAddressesRegistry.AddressVars memory registered = _completeCodeBackedVars();
        AddressesRegistry registry = _configuredRegistry(registered);
        IAddressesRegistry.AddressVars memory expected = registered;
        expected.borrowerOperations = IBorrowerOperations(address(new ExternalAuditInfo06CodeStub()));

        vm.expectRevert(bytes("DF: addressesRegistry borrowerOperations mismatch"));
        harness.verifyAddressesRegistryWiring(registry, expected);
    }

    function test_PostDeployVerifierRejectsZeroAddress() public {
        IAddressesRegistry.AddressVars memory vars = _completeCodeBackedVars();
        vars.collToken = IERC20Metadata(address(0));
        AddressesRegistry registry = _configuredRegistry(vars);

        vm.expectRevert(bytes("DF: zero addressesRegistry collToken"));
        harness.verifyAddressesRegistryWiring(registry, vars);
    }

    function test_PostDeployVerifierRejectsCodelessAddress() public {
        IAddressesRegistry.AddressVars memory vars = _completeCodeBackedVars();
        vars.collToken = IERC20Metadata(makeAddr("codelessCollToken"));
        AddressesRegistry registry = _configuredRegistry(vars);

        vm.expectRevert(bytes("DF: codeless addressesRegistry collToken"));
        harness.verifyAddressesRegistryWiring(registry, vars);
    }

    function _configuredRegistry(IAddressesRegistry.AddressVars memory vars)
        internal
        returns (AddressesRegistry registry)
    {
        registry = new AddressesRegistry(
            address(this),
            1.5e18, // CCR
            1.1e18, // MCR
            0.05e18, // BCR
            1.2e18, // SCR
            0.05e18, // liquidation penalty SP
            0.1e18, // liquidation penalty redistribution
            address(0) // deploy-time finalized
        );
        registry.setAddresses(vars);
    }

    function _completeCodeBackedVars() internal returns (IAddressesRegistry.AddressVars memory vars) {
        address[18] memory target;
        for (uint256 i; i < target.length; ++i) {
            target[i] = address(new ExternalAuditInfo06CodeStub());
        }

        vars = IAddressesRegistry.AddressVars({
            collToken: IERC20Metadata(target[0]),
            borrowerOperations: IBorrowerOperations(target[1]),
            troveManager: ITroveManager(target[2]),
            troveNFT: ITroveNFT(target[3]),
            metadataNFT: IMetadataNFT(target[4]),
            stabilityPool: IStabilityPool(target[5]),
            priceFeed: IPriceFeed(target[6]),
            activePool: IActivePool(target[7]),
            defaultPool: IDefaultPool(target[8]),
            gasPoolAddress: target[9],
            collSurplusPool: ICollSurplusPool(target[10]),
            sortedTroves: ISortedTroves(target[11]),
            interestRouter: IInterestRouter(target[12]),
            hintHelpers: IHintHelpers(target[13]),
            multiTroveGetter: IMultiTroveGetter(target[14]),
            collateralRegistry: ICollateralRegistry(target[15]),
            jpydfToken: IJpydfToken(target[16]),
            WETH: IWETH(target[17])
        });
    }
}
