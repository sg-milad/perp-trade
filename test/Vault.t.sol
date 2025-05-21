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

    function setUp() public {
        vm.startPrank(owner);

        mockUSDT = new MockUSDT();
        lpToken = new LPToken();

        vault = new Vault(address(mockUSDT), address(lpToken));

        lpToken.grantMintAndBurnRole(address(vault));

        vm.stopPrank();
    }

    function testDeposit() public {}

    function testWithdraw() public {}
}
