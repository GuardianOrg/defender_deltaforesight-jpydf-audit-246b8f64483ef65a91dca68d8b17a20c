// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {ICollateralRegistry} from "../src/Interfaces/ICollateralRegistry.sol";
import {LiquidationCandidateGetter} from "../src/LiquidationCandidateGetter.sol";
import {ScriptSecurityPolicy} from "script/ScriptSecurityPolicy.sol";

contract DeployLiquidationCandidateGetter is Script {
    function run() external {
        string memory manifestPath = vm.envOr("DEPLOYMENT_MANIFEST", string("deployment-manifest.json"));
        string memory manifest = vm.readFile(manifestPath);
        ICollateralRegistry collateralRegistry =
            ICollateralRegistry(vm.parseJsonAddress(manifest, ".collateralRegistry"));

        _startBroadcast();
        LiquidationCandidateGetter getter = new LiquidationCandidateGetter(collateralRegistry);
        vm.stopBroadcast();

        console.log("liquidationCandidateGetter:", address(getter));
    }

    function _startBroadcast() internal {
        try vm.envBytes("DEPLOYER") returns (bytes memory raw) {
            ScriptSecurityPolicy.requirePublicAddress("DEPLOYER", raw);
            vm.startBroadcast(vm.envAddress("DEPLOYER"));
        } catch {
            vm.startBroadcast();
        }
    }
}
