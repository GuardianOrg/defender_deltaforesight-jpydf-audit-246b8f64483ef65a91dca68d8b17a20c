// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {LocalStETH, LocalWstETH} from "script/local/LocalTokens.sol";

contract LocalLidoTokensTest is Test {
    LocalStETH internal stEth;
    LocalWstETH internal wstEth;

    function setUp() external {
        stEth = new LocalStETH();
        wstEth = new LocalWstETH(stEth, 100e18, 1 days);
    }

    function test_SubmitAndWrapMatchesConfiguredRate() external {
        uint256 ethAmount = 1.2 ether;
        uint256 expectedWstEth = 1 ether;

        assertEq(stEth.submit{value: ethAmount}(address(0)), ethAmount, "stETH minted");
        stEth.approve(address(wstEth), ethAmount);

        assertEq(wstEth.wrap(ethAmount), expectedWstEth, "wstETH returned");
        assertEq(stEth.balanceOf(address(wstEth)), ethAmount, "stETH locked");
        assertEq(wstEth.balanceOf(address(this)), expectedWstEth, "wstETH minted");
        assertEq(wstEth.stETH(), address(stEth), "linked stETH");
    }

    function test_StakeLimitAndPauseSignalsMatchSubmitBehavior() external {
        stEth.setCurrentStakeLimit(2 ether);
        assertEq(stEth.getCurrentStakeLimit(), 2 ether, "initial limit");

        stEth.submit{value: 1 ether}(address(0));
        assertEq(stEth.getCurrentStakeLimit(), 1 ether, "remaining limit");

        stEth.setStakingPaused(true);
        assertTrue(stEth.isStakingPaused(), "pause signal");
        vm.expectRevert("LocalStETH: staking paused");
        stEth.submit{value: 1 ether}(address(0));
    }
}
