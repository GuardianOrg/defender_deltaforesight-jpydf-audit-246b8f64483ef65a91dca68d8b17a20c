// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {DevTestSetup} from "./TestContracts/DevTestSetup.sol";
import {FixedAssetReader} from "src/NFTMetadata/utils/FixedAssets.sol";
import {TroveChange} from "src/Types/TroveChange.sol";

contract SlitherTriageHardeningTest is DevTestSetup {
    event ActivePoolAggRecordedDebtUpdated(uint256 _aggRecordedDebt);
    event ActivePoolAggWeightedDebtSumUpdated(uint256 _aggWeightedDebtSum);

    function testFixedAssetReaderRejectsZeroPointer() public {
        bytes4[] memory sigs = new bytes4[](0);
        FixedAssetReader.Asset[] memory assets = new FixedAssetReader.Asset[](0);

        vm.expectRevert(bytes("FixedAssetReader: Invalid pointer"));
        new FixedAssetReader(address(0), sigs, assets);
    }

    function testMintAggInterestAndAccountForTroveChangeEmitsAggregateDebtEvents() public {
        TroveChange memory noChange;

        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggRecordedDebtUpdated(0);
        vm.expectEmit(false, false, false, true, address(activePool));
        emit ActivePoolAggWeightedDebtSumUpdated(0);

        vm.prank(address(borrowerOperations));
        activePool.mintAggInterestAndAccountForTroveChange(noChange, address(0));
    }
}
