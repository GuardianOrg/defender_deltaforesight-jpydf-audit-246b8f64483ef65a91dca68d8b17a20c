// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {LocalAToken, LocalAavePool} from "script/local/LocalAaveVenue.sol";
import {WETH9} from "test/TestContracts/WETH.sol";

contract LocalAaveVenueTest is Test {
    function test_SupplyPlacesLiquidityAtATokenAndWithdrawReturnsIt() external {
        WETH9 underlying = new WETH9();
        LocalAavePool pool = new LocalAavePool();
        LocalAToken aToken = new LocalAToken(address(pool), address(underlying));
        pool.setAsset(underlying);
        pool.setAToken(aToken);

        underlying.deposit{value: 4 ether}();
        underlying.approve(address(pool), 4 ether);
        pool.supply(address(underlying), 4 ether, address(this), 0);

        assertEq(underlying.balanceOf(address(aToken)), 4 ether, "aToken holds reserve liquidity");
        assertEq(underlying.balanceOf(address(pool)), 0, "pool does not retain reserve liquidity");
        assertEq(aToken.scaledBalanceOf(address(this)), 4 ether, "scaled supply recorded");

        assertEq(pool.withdraw(address(underlying), 2 ether, address(this)), 2 ether, "withdraw reports amount");
        assertEq(underlying.balanceOf(address(this)), 2 ether, "underlying returned");
        assertEq(underlying.balanceOf(address(aToken)), 2 ether, "remaining reserve liquidity");
        assertEq(aToken.scaledBalanceOf(address(this)), 2 ether, "scaled supply burned");
    }
}
