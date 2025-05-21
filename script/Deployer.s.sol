// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPToken} from "../src/LPToken.sol";
import {Vault} from "../src/Vault.sol";
import {MockUSDT} from "../test/mock/MockUSDT.sol";

contract DeployerScript is Script {
    LPToken public lPToken;
    Vault public vault;
    MockUSDT public mockUSDT;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        mockUSDT = new MockUSDT();
        lPToken = new LPToken();
        vault = new Vault(address(mockUSDT), address(lPToken));

        lPToken.grantMintAndBurnRole(address(vault));

        console.log("lPToken: ", address(lPToken));
        console.log("vault: ", address(vault));
        console.log("mockUSDT: ", address(mockUSDT));

        vm.stopBroadcast();
    }
}
