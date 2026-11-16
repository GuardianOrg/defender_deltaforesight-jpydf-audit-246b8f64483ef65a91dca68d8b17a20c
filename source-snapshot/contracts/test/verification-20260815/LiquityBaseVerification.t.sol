// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LiquityBase} from "src/Dependencies/LiquityBase.sol";
import {IAddressesRegistry} from "src/Interfaces/IAddressesRegistry.sol";
import {IActivePool} from "src/Interfaces/IActivePool.sol";
import {IDefaultPool} from "src/Interfaces/IDefaultPool.sol";
import {IPriceFeed} from "src/Interfaces/IPriceFeed.sol";

contract LiquityBaseMockPool {
    uint256 internal _coll;
    uint256 internal _debt;

    constructor(uint256 coll, uint256 debt) {
        _coll = coll;
        _debt = debt;
    }

    function getCollBalance() external view returns (uint256) {
        return _coll;
    }

    function getJpydfDebt() external view returns (uint256) {
        return _debt;
    }
}

contract LiquityBaseMockRegistry {
    IActivePool public activePool;
    IDefaultPool public defaultPool;
    IPriceFeed public priceFeed;

    constructor(IActivePool activePool_, IDefaultPool defaultPool_, IPriceFeed priceFeed_) {
        activePool = activePool_;
        defaultPool = defaultPool_;
        priceFeed = priceFeed_;
    }
}

contract LiquityBaseVerification is Test {
    event ActivePoolAddressChanged(address _newActivePoolAddress);
    event DefaultPoolAddressChanged(address _newDefaultPoolAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);

    function testConstructorWiringAggregateViewsAndEvents() public {
        LiquityBaseMockPool active = new LiquityBaseMockPool(17 ether, 900_000 ether);
        LiquityBaseMockPool defaults = new LiquityBaseMockPool(3 ether, 100_000 ether);
        address priceFeed = address(0xFEE1);
        LiquityBaseMockRegistry registry = new LiquityBaseMockRegistry(
            IActivePool(address(active)), IDefaultPool(address(defaults)), IPriceFeed(priceFeed)
        );

        vm.expectEmit();
        emit ActivePoolAddressChanged(address(active));
        vm.expectEmit();
        emit DefaultPoolAddressChanged(address(defaults));
        vm.expectEmit();
        emit PriceFeedAddressChanged(priceFeed);
        LiquityBase base = new LiquityBase(IAddressesRegistry(address(registry)));

        assertEq(address(base.activePool()), address(active), "ActivePool binding");
        assertEq(base.getEntireBranchColl(), 20 ether, "aggregate collateral");
        assertEq(base.getEntireBranchDebt(), 1_000_000 ether, "aggregate debt");
    }
}
