// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LPToken} from "../src/LPToken.sol";
import {Vault} from "../src/Vault.sol";

contract LPTokenTest is Test {
    LPToken public lPToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        lPToken = new LPToken();
        lPToken.grantMintAndBurnRole(owner);
        vm.stopPrank();
    }

    function test_MintToken() public {
        vm.startPrank(owner);
        lPToken.mint(owner, 1000);
        assertEq(lPToken.balanceOf(owner), 1000);
        vm.stopPrank();
    }

    function test_MintTokenForUser() public {
        vm.startPrank(owner);
        lPToken.mint(user, 1000);
        assertEq(lPToken.balanceOf(user), 1000);
        vm.stopPrank();
    }

    function test_BurnToken() public {
        vm.startPrank(owner);
        lPToken.mint(owner, 1000);
        lPToken.burn(owner, 1000);
        assertEq(lPToken.balanceOf(owner), 0);
        vm.stopPrank();
    }

    function test_BurnTokenWithZeroBalance() public {
        vm.startPrank(owner);
        vm.expectRevert();
        lPToken.burn(owner, 1000);
        vm.stopPrank();
    }

    function test_RevertIfUserCallMint() public {
        vm.startPrank(user);
        vm.expectRevert();
        lPToken.mint(user, 1000);
        vm.stopPrank();
    }

    function test_RevertIfUserCallBurn() public {
        vm.startPrank(user);
        vm.expectRevert();
        lPToken.burn(user, 1000);
        vm.stopPrank();
    }
}
