// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PerpEngine} from "../src/PerpEngine.sol";
import {Vault} from "../src/Vault.sol";
import {LPToken} from "../src/LPToken.sol";
import {MockUSDT} from "./mock/MockUSDT.sol";
import {MockV3Aggregator} from "./mock/MockV3Aggregator.sol";

contract PerpEngineTest is Test {
    PerpEngine perpEngine;
    Vault vault;
    LPToken lpToken;
    MockUSDT usdt;
    MockV3Aggregator priceFeed;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address liquidityProvider = makeAddr("liquidityProvider");

    uint256 constant INITIAL_BTC_PRICE = 50000e18; // $50,000
    uint256 constant INITIAL_LIQUIDITY = 100000e6; // 100,000 USDT
    uint256 constant COLLATERAL_AMOUNT = 1000e6; // 1,000 USDT
    uint256 constant POSITION_SIZE = 5000e6; // 5,000 USDT
    uint256 constant TRADEING_FEE = 5e6; // 5,000 USDT

    function setUp() public {
        // Deploy mock tokens and price feed
        usdt = new MockUSDT();
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_BTC_PRICE / 1e10)); // Chainlink uses 8 decimals

        // Deploy LP token
        lpToken = new LPToken();

        // Deploy vault
        vault = new Vault(address(usdt), address(lpToken));

        // Deploy PerpEngine
        perpEngine = new PerpEngine(address(vault), address(usdt), address(priceFeed));

        // Setup roles
        lpToken.grantMintAndBurnRole(address(vault));
        vault.grantPerpEngineRole(address(perpEngine));

        // Mint tokens to users
        usdt.mint(alice, 10000e6);
        usdt.mint(bob, 10000e6);
        usdt.mint(liquidityProvider, INITIAL_LIQUIDITY);

        // Provide initial liquidity
        vm.startPrank(liquidityProvider);
        usdt.approve(address(vault), INITIAL_LIQUIDITY);
        vault.deposit(INITIAL_LIQUIDITY);
        vm.stopPrank();
    }

    function testOpenPosition() public {
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADEING_FEE);

        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);

        // Check position details
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertEq(position.trader, alice);
        assertEq(position.collateral, COLLATERAL_AMOUNT);
        assertEq(position.size, POSITION_SIZE);
        assertEq(position.entryPrice, INITIAL_BTC_PRICE);
        assertTrue(position.isLong);
        assertTrue(position.isActive);

        vm.stopPrank();
    }

    function testIncreasePositionSize() public {
        // First open a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT * 2);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);

        // Increase position size
        uint256 additionalSize = 2000e6;
        perpEngine.increasePositionSize(positionId, additionalSize);

        // Check updated position
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertEq(position.size, POSITION_SIZE + additionalSize);

        vm.stopPrank();
    }

    function testAddCollateral() public {
        // First open a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT * 2);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);

        // Add collateral
        uint256 additionalCollateral = 500e6;
        perpEngine.addCollateral(positionId, additionalCollateral);

        // Check updated position
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertEq(position.collateral, COLLATERAL_AMOUNT + additionalCollateral);

        vm.stopPrank();
    }

    function testClosePositionWithProfit() public {
        // Open position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADEING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);

        // Increase BTC price to create profit
        uint256 newPrice = 55000e18; // $55,000 (+10%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check unrealized P&L
        int256 unrealizedPnL = perpEngine.getUnrealizedPnL(positionId);
        assertGt(unrealizedPnL, 0); // Should be positive (profit)

        // Get balance before closing
        uint256 balanceBefore = usdt.balanceOf(alice);

        assertEq(unrealizedPnL, 500e6); // 500 USDT profit
        // Close position
        perpEngine.closePosition(positionId);

        // Get balance after closing
        uint256 balanceAfter = usdt.balanceOf(alice);

        // Expected profit + collateral - trading fee = 1000 + 500 - 5 = 1495 USDT
        uint256 expectedProfit = 1495e6;
        uint256 actualProfit = balanceAfter - balanceBefore;
        assertEq(actualProfit, expectedProfit);

        // Check position is inactive
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertFalse(position.isActive);

        vm.stopPrank();
    }

    function testClosePositionWithLoss() public {
        // Open position
        vm.startPrank(alice);
        // 5 usdc trading fee is fee
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADEING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        // 5000000000000
        console.log("btc old price", answer);
        // Decrease BTC price to create loss
        uint256 newPrice = 45000e18; // $45,000 (-10%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));
        (, int256 answer1,,,) = priceFeed.latestRoundData();
        // 5000000000000
        console.log("btc new price", answer1);
        // Check unrealized P&L
        int256 unrealizedPnL = perpEngine.getUnrealizedPnL(positionId);
        assertLt(unrealizedPnL, 0); // Should be negative (loss)

        // Get balance before closing
        uint256 balanceBefore = usdt.balanceOf(alice);
        // Close position
        perpEngine.closePosition(positionId);

        uint256 balanceAfter = usdt.balanceOf(alice);

        // Expected profit + collateral - trading fee = 1000 + 500 - 5 = 1495 USDT
        uint256 expectedLoss = 495e6;
        uint256 actualLoss = balanceAfter - balanceBefore;
        assertEq(expectedLoss, actualLoss);

        // Check position is inactive
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertFalse(position.isActive);

        vm.stopPrank();
    }

    function test_RevertInsufficientCollateral() public {
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), 100e6);
        vm.expectRevert();
        // Try to open position with insufficient collateral (less than 150% collateral ratio)
        perpEngine.openPosition(100e6, 1000e6, true);

        vm.stopPrank();
    }

    function test_RevertExceedsUtilization() public {
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), 50000e6);

        // Try to open position that exceeds 80% utilization
        vm.expectRevert();
        perpEngine.openPosition(50000e6, 90000e6, true); // More than 80% of 100k liquidity

        vm.stopPrank();
    }

    function testGetCurrentPrice() public view {
        uint256 currentPrice = perpEngine.getCurrentPrice();
        assertEq(currentPrice, INITIAL_BTC_PRICE);
    }

    function testGetTraderPositions() public {
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT * 2 + (2 * TRADEING_FEE));

        uint256 positionId1 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        uint256 positionId2 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);

        uint256[] memory positions = perpEngine.getTraderPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], positionId1);
        assertEq(positions[1], positionId2);

        vm.stopPrank();
    }
}
