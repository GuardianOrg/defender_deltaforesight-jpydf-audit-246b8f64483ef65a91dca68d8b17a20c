// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DebtInFrontHelper} from "src/DebtInFrontHelper.sol";
import {RedemptionHelper} from "src/RedemptionHelper.sol";
import {IAddressesRegistry} from "src/Interfaces/IAddressesRegistry.sol";
import {ITroveManager} from "src/Interfaces/ITroveManager.sol";
import {DevTestSetup} from "../TestContracts/DevTestSetup.sol";

contract WrongTroveManagerRegistry {
    function troveManager() external pure returns (ITroveManager) {
        return ITroveManager(address(0));
    }
}

contract ReadHelpersVerification is DevTestSetup {
    function testDebtInFrontHelperExposesConfiguredReferences() public {
        DebtInFrontHelper helper = new DebtInFrontHelper(collateralRegistry, hintHelpers);

        assertEq(address(helper.collateralRegistry()), address(collateralRegistry), "collateral registry");
        assertEq(address(helper.hintHelpers()), address(hintHelpers), "hint helpers");
    }

    function testRedemptionHelperBindsConfiguredBranch() public {
        IAddressesRegistry[] memory branchAddresses = new IAddressesRegistry[](1);
        branchAddresses[0] = addressesRegistry;
        RedemptionHelper helper = new RedemptionHelper(collateralRegistry, branchAddresses);

        assertEq(helper.numBranches(), 1, "branch count");
        assertEq(address(helper.collateralRegistry()), address(collateralRegistry), "collateral registry");
        assertEq(address(helper.jpydfToken()), address(jpydfToken), "JPYdf token");
        assertEq(address(helper.addresses(0)), address(addressesRegistry), "branch registry");
    }

    function testRedemptionHelperRejectsWrongConstructorRegistries() public {
        IAddressesRegistry[] memory empty = new IAddressesRegistry[](0);
        vm.expectRevert("Wrong number of registries");
        new RedemptionHelper(collateralRegistry, empty);

        IAddressesRegistry[] memory mismatched = new IAddressesRegistry[](1);
        mismatched[0] = IAddressesRegistry(address(new WrongTroveManagerRegistry()));
        vm.expectRevert("TroveManager mismatch");
        new RedemptionHelper(collateralRegistry, mismatched);
    }
}
