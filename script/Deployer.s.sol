// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPToken} from "../src/LPToken.sol";
import {Vault} from "../src/Vault.sol";
import {PerpEngine} from "../src/PerpEngine.sol";
import {MockUSDT} from "../test/mock/MockUSDT.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";

contract DeployerScript is Script {
    uint256 constant INITIAL_BTC_PRICE = 50000e18; // $50,000

    LPToken public lPToken;
    Vault public vault;
    MockUSDT public mockUSDT;
    PerpEngine public perpEngine;
    MockV3Aggregator public priceFeed;
    address deployer = makeAddr("deployer");

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        mockUSDT = new MockUSDT();
        lPToken = new LPToken();
        vault = new Vault(address(mockUSDT), address(lPToken));
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_BTC_PRICE / 1e10)); // Chainlink uses 8 decimals

        perpEngine = new PerpEngine(address(vault), address(mockUSDT), address(priceFeed));

        // Setup roles
        lPToken.grantMintAndBurnRole(address(vault));
        vault.grantPerpEngineRole(address(perpEngine));

        console.log("priceFeed: ", address(priceFeed));
        console.log("perpEngine: ", address(perpEngine));
        console.log("lPToken: ", address(lPToken));
        console.log("vault: ", address(vault));
        console.log("mockUSDT: ", address(mockUSDT));
        deposoitToValut();
        vm.stopBroadcast();
    }

    function deposoitToValut() public {
        mockUSDT.mint(msg.sender, 1_000_000e6);
        mockUSDT.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6);
    }
}
