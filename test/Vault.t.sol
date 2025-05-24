// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {LPToken} from "../src/LPToken.sol";
import {MockUSDT} from "./mock/MockUSDT.sol";

contract VaultTest is Test {
    Vault public vault;
    LPToken public lpToken;
    MockUSDT public mockUSDT;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address attacker = makeAddr("attacker");

    uint256 public constant TEST_AMOUNT = 100 ether;

    function setUp() public {
        vm.startPrank(owner);
        mockUSDT = new MockUSDT();
        lpToken = new LPToken();
        vault = new Vault(address(mockUSDT), address(lpToken));
        lpToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);

        mockUSDT.mint(user, TEST_AMOUNT);
        mockUSDT.approve(address(vault), TEST_AMOUNT);

        assertEq(mockUSDT.balanceOf(user), TEST_AMOUNT, "Initial USDT balance incorrect");
        assertEq(lpToken.balanceOf(user), 0, "Initial LP balance should be zero");

        vault.deposit(TEST_AMOUNT);

        assertEq(mockUSDT.balanceOf(user), 0, "USDT not deposited");
        assertEq(vault.totalLiquidity(), TEST_AMOUNT, "total liqudity is wrong");
        assertEq(mockUSDT.balanceOf(address(vault)), TEST_AMOUNT, "Vault USDT balance incorrect");
        assertEq(lpToken.balanceOf(user), TEST_AMOUNT, "LP tokens not minted");

        vm.stopPrank();
    }

    function testWithdraw() public {
        // Setup deposit first
        vm.startPrank(user);
        mockUSDT.mint(user, TEST_AMOUNT);
        mockUSDT.approve(address(vault), TEST_AMOUNT);
        vault.deposit(TEST_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user);
        // Execute withdrawal
        vault.withdraw(TEST_AMOUNT);

        // Verify post-withdrawal state
        assertEq(mockUSDT.balanceOf(user), TEST_AMOUNT, "USDT not returned");
        assertEq(lpToken.balanceOf(user), 0, "LP tokens not burned");
        assertEq(vault.totalLiquidity(), 0, "total liqudity is wrong");
        assertEq(mockUSDT.balanceOf(address(vault)), 0, "Vault USDT not deducted");

        vm.stopPrank();
    }

    function testAttackerWithdrawUsersToken() public {
        vm.startPrank(user);
        mockUSDT.mint(user, TEST_AMOUNT);
        mockUSDT.approve(address(vault), TEST_AMOUNT);
        vault.deposit(TEST_AMOUNT);
        vm.stopPrank();

        vm.startPrank(attacker);

        vm.expectRevert();

        vault.withdraw(TEST_AMOUNT);
        vm.stopPrank();
    }

    function testCannotWithdrawWithoutShares() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        vault.withdraw(1 ether);
        vm.stopPrank();
    }

    function testCannotDepositZero() public {
        vm.startPrank(user);
        vm.expectRevert("Zero deposit");
        vault.deposit(0);
        vm.stopPrank();
    }
}
