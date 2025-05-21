// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LPToken} from "../src/LPToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockUSDT} from "./mock/MockUSDT.sol";

contract VaultTest is Test {
    Vault public vault;
    LPToken public lPToken;
    MockUSDT public mockUSDT;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startBroadcast(owner);

        mockUSDT = new MockUSDT();

        lPToken = new LPToken();

        vault = new Vault(address(mockUSDT), address(lPToken));

        vm.stopBroadcast();
    }
}
