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
    address charlie = makeAddr("charlie");
    address liquidityProvider = makeAddr("liquidityProvider");
    address liquidator = makeAddr("liquidator");

    uint256 constant INITIAL_BTC_PRICE = 50000e18; // $50,000
    uint256 constant INITIAL_LIQUIDITY = 100000e6; // 100,000 USDT
    uint256 constant COLLATERAL_AMOUNT = 1000e6; // 1,000 USDT
    uint256 constant POSITION_SIZE = 5000e6; // 5,000 USDT
    uint256 constant TRADING_FEE = 5e6; // 5,000 USDT

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
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);

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
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
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
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
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
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT * 2 + (2 * TRADING_FEE));

        uint256 positionId1 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        uint256 positionId2 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);

        uint256[] memory positions = perpEngine.getTraderPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], positionId1);
        assertEq(positions[1], positionId2);

        vm.stopPrank();
    }
    // =================== SHORT POSITION TESTS ===================

    function testOpenShortPosition() public {
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);

        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false); // false = short

        // Check position details
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertEq(position.trader, alice);
        assertEq(position.collateral, COLLATERAL_AMOUNT);
        assertEq(position.size, POSITION_SIZE);
        assertEq(position.entryPrice, INITIAL_BTC_PRICE);
        assertFalse(position.isLong); // Should be short
        assertTrue(position.isActive);

        vm.stopPrank();
    }

    function testShortPositionProfitWhenPriceDecreases() public {
        // Open short position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);

        // Decrease BTC price to create profit for short position
        uint256 newPrice = 45000e18; // $45,000 (-10%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check unrealized P&L - should be positive for short when price decreases
        int256 unrealizedPnL = perpEngine.getUnrealizedPnL(positionId);
        assertGt(unrealizedPnL, 0); // Should be positive (profit)
        assertEq(unrealizedPnL, 500e6); // 500 USDT profit

        // Get balance before closing
        uint256 balanceBefore = usdt.balanceOf(alice);

        // Close position
        perpEngine.closePosition(positionId);

        // Get balance after closing
        uint256 balanceAfter = usdt.balanceOf(alice);

        // Expected: collateral + profit - trading fee = 1000 + 500 - 5 = 1495 USDT
        uint256 expectedReturn = 1495e6;
        uint256 actualReturn = balanceAfter - balanceBefore;
        assertEq(actualReturn, expectedReturn);

        vm.stopPrank();
    }

    function testShortPositionLossWhenPriceIncreases() public {
        // Open short position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);

        // Increase BTC price to create loss for short position
        uint256 newPrice = 55000e18; // $55,000 (+10%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check unrealized P&L - should be negative for short when price increases
        int256 unrealizedPnL = perpEngine.getUnrealizedPnL(positionId);
        assertLt(unrealizedPnL, 0); // Should be negative (loss)
        assertEq(unrealizedPnL, -500e6); // 500 USDT loss

        // Get balance before closing
        uint256 balanceBefore = usdt.balanceOf(alice);

        // Close position
        perpEngine.closePosition(positionId);

        // Get balance after closing
        uint256 balanceAfter = usdt.balanceOf(alice);

        // Expected: collateral - loss - trading fee = 1000 - 500 - 5 = 495 USDT
        uint256 expectedReturn = 495e6;
        uint256 actualReturn = balanceAfter - balanceBefore;
        assertEq(actualReturn, expectedReturn);

        vm.stopPrank();
    }

    // =================== LIQUIDATION TESTS ===================

    function testLiquidatePositionLongWithHeavyLoss() public {
        // Alice opens a long position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        vm.stopPrank();

        // Price drops significantly to trigger liquidation
        // Liquidation threshold is 80% of collateral = 800 USDT
        // For liquidation: remaining collateral <= 800 USDT
        uint256 newPrice = 42000e18; // $42,000 (-16% from $50,000)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check if position is liquidatable
        assertTrue(perpEngine.isLiquidatable(positionId));

        // Get liquidatable positions
        uint256[] memory liquidatablePositions = perpEngine.getLiquidatablePositions();
        assertEq(liquidatablePositions.length, 1);
        assertEq(liquidatablePositions[0], positionId);

        // Get initial balances
        uint256 liquidatorBalanceBefore = usdt.balanceOf(liquidator);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);

        // Liquidate the position
        vm.prank(liquidator);
        perpEngine.liquidatePosition(positionId);

        // Check position is no longer active
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertFalse(position.isActive);

        // Check that liquidator received reward
        uint256 liquidatorBalanceAfter = usdt.balanceOf(liquidator);
        uint256 expectedLiquidationReward = (COLLATERAL_AMOUNT * 500) / 10000; // 5% = 50 USDT

        // Calculate remaining collateral after loss
        int256 pnl = perpEngine.getUnrealizedPnL(positionId); // Should be 0 now since position is closed
        // At $42,000: PnL = (42000 - 50000) * 5000 / 50000 = -800 USDT
        int256 remainingCollateral = int256(COLLATERAL_AMOUNT) + (-800e6);
        assertEq(remainingCollateral, 200e6); // 200 USDT remaining

        // Liquidator should get the liquidation reward (50 USDT)
        // Alice should get the remainder (200 - 50 = 150 USDT)
        assertEq(liquidatorBalanceAfter - liquidatorBalanceBefore, expectedLiquidationReward);

        uint256 aliceBalanceAfter = usdt.balanceOf(alice);
        uint256 expectedAliceReturn = 150e6; // 200 - 50 = 150 USDT
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedAliceReturn);
    }

    function testLiquidatePositionShortWithHeavyLoss() public {
        // Alice opens a short position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);
        vm.stopPrank();

        // Price increases significantly to trigger liquidation for short position
        uint256 newPrice = 58000e18; // $58,000 (+16% from $50,000)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check if position is liquidatable
        assertTrue(perpEngine.isLiquidatable(positionId));

        // Get initial balances
        uint256 liquidatorBalanceBefore = usdt.balanceOf(liquidator);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);

        // Liquidate the position
        vm.prank(liquidator);
        perpEngine.liquidatePosition(positionId);

        // Check position is no longer active
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertFalse(position.isActive);

        // Check balances after liquidation
        uint256 liquidatorBalanceAfter = usdt.balanceOf(liquidator);
        uint256 expectedLiquidationReward = (COLLATERAL_AMOUNT * 500) / 10000; // 5% = 50 USDT

        // For short position at $58,000: PnL = (50000 - 58000) * 5000 / 50000 = -800 USDT
        // Remaining collateral = 1000 - 800 = 200 USDT
        // Liquidator gets 50 USDT, Alice gets 150 USDT
        assertEq(liquidatorBalanceAfter - liquidatorBalanceBefore, expectedLiquidationReward);

        uint256 aliceBalanceAfter = usdt.balanceOf(alice);
        uint256 expectedAliceReturn = 150e6;
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedAliceReturn);
    }

    function testCannotLiquidateHealthyPosition() public {
        // Alice opens a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        vm.stopPrank();

        // Price drops slightly but not enough for liquidation
        uint256 newPrice = 49000e18; // $48,000 (-2% from $50,000)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Check position is not liquidatable
        assertFalse(perpEngine.isLiquidatable(positionId));

        // Try to liquidate - should revert
        vm.prank(liquidator);
        vm.expectRevert(PerpEngine.PositionNotLiquidatable.selector);
        perpEngine.liquidatePosition(positionId);
    }

    function testLiquidatePositionCompletelyInsolvent() public {
        // Alice opens a position with minimal collateral
        uint256 minCollateral = 750e6; // Minimum for 5000 USDT position (150% ratio)
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), minCollateral + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(minCollateral, POSITION_SIZE, true);
        vm.stopPrank();

        // Price drops drastically to make position completely insolvent
        uint256 newPrice = 35000e18; // $35,000 (-30% from $50,000)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Position should be liquidatable
        assertTrue(perpEngine.isLiquidatable(positionId));

        // Get initial balances
        uint256 liquidatorBalanceBefore = usdt.balanceOf(liquidator);
        uint256 aliceBalanceBefore = usdt.balanceOf(alice);

        // Liquidate the position
        vm.prank(liquidator);
        perpEngine.liquidatePosition(positionId);

        // Check position is no longer active
        PerpEngine.Position memory position = perpEngine.getPosition(positionId);
        assertFalse(position.isActive);

        // With 30% price drop: PnL = (35000 - 50000) * 5000 / 50000 = -1500 USDT
        // Remaining collateral = 750 - 1500 = -750 USDT (insolvent)
        // Liquidator should get nothing since remaining collateral <= 0
        uint256 liquidatorBalanceAfter = usdt.balanceOf(liquidator);
        uint256 aliceBalanceAfter = usdt.balanceOf(alice);

        assertEq(liquidatorBalanceAfter - liquidatorBalanceBefore, 0);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 0);
    }

    function testCannotLiquidateInactivePosition() public {
        // Alice opens and then closes a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + (2 * TRADING_FEE));
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        perpEngine.closePosition(positionId);
        vm.stopPrank();

        // Try to liquidate closed position - should revert
        vm.prank(liquidator);
        vm.expectRevert(PerpEngine.PositionNotActive.selector);
        perpEngine.liquidatePosition(positionId);
    }

    // =================== UTILITY FUNCTION TESTS ===================

    function testGetPositionWithPnL() public {
        // Alice opens a long position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        vm.stopPrank();

        // Change price
        uint256 newPrice = 55000e18; // $55,000 (+10%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Get position with P&L
        (PerpEngine.Position memory position, int256 unrealizedPnL, uint256 currentPrice, bool liquidatable) =
            perpEngine.getPositionWithPnL(positionId);

        assertEq(position.trader, alice);
        assertEq(position.collateral, COLLATERAL_AMOUNT);
        assertEq(unrealizedPnL, 500e6); // 500 USDT profit
        assertEq(currentPrice, newPrice);
        assertFalse(liquidatable); // Position should be healthy
    }

    function testGetProtocolStats() public {
        // Open some positions to generate stats
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), (COLLATERAL_AMOUNT + TRADING_FEE) * 2);
        perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);
        vm.stopPrank();

        // Get protocol stats
        (
            uint256 _totalTradingVolume,
            uint256 _totalLiquidations,
            uint256 _totalFeesCollected,
            uint256 _activePositions,
            uint256 _totalLiquidity,
            uint256 _utilizationRate
        ) = perpEngine.getProtocolStats();

        assertEq(_totalTradingVolume, POSITION_SIZE * 2); // Two positions
        assertEq(_totalLiquidations, 0); // No liquidations yet
        assertEq(_totalFeesCollected, TRADING_FEE * 2); // Two trading fees
        assertEq(_activePositions, 2); // Two active positions
        assertEq(_totalLiquidity, INITIAL_LIQUIDITY);
        assertEq(_utilizationRate, POSITION_SIZE * 2); // Both positions reserved
    }

    function testMultipleLiquidatablePositions() public {
        // Open multiple positions that will become liquidatable
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), (COLLATERAL_AMOUNT + TRADING_FEE) * 2);
        uint256 positionId1 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        uint256 positionId2 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, false);
        vm.stopPrank();

        vm.startPrank(bob);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + TRADING_FEE);
        uint256 positionId3 = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        vm.stopPrank();

        // Price that makes long positions liquidatable but not short
        uint256 newPrice = 42000e18; // $42,000 (-16%)
        priceFeed.updateAnswer(int256(newPrice / 1e10));

        // Get liquidatable positions
        uint256[] memory liquidatablePositions = perpEngine.getLiquidatablePositions();

        // Should have 2 liquidatable positions (both long positions)
        assertEq(liquidatablePositions.length, 2);

        // Check that both long positions are in the array
        bool foundPosition1 = false;
        bool foundPosition3 = false;
        for (uint256 i = 0; i < liquidatablePositions.length; i++) {
            if (liquidatablePositions[i] == positionId1) foundPosition1 = true;
            if (liquidatablePositions[i] == positionId3) foundPosition3 = true;
        }
        assertTrue(foundPosition1);
        assertTrue(foundPosition3);

        // Verify short position is not liquidatable
        assertFalse(perpEngine.isLiquidatable(positionId2));
    }

    // =================== EDGE CASE TESTS ===================

    function testGetUnrealizedPnLForInactivePosition() public {
        // Open and close a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + (2 * TRADING_FEE));
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        perpEngine.closePosition(positionId);
        vm.stopPrank();

        // Get unrealized P&L for inactive position
        int256 pnl = perpEngine.getUnrealizedPnL(positionId);
        assertEq(pnl, 0); // Should return 0 for inactive positions
    }

    function testGetPositionWithPnLForInactivePosition() public {
        // Open and close a position
        vm.startPrank(alice);
        usdt.approve(address(perpEngine), COLLATERAL_AMOUNT + (2 * TRADING_FEE));
        uint256 positionId = perpEngine.openPosition(COLLATERAL_AMOUNT, POSITION_SIZE, true);
        perpEngine.closePosition(positionId);
        vm.stopPrank();

        // Get position with P&L for inactive position
        (PerpEngine.Position memory position, int256 unrealizedPnL, uint256 currentPrice, bool liquidatable) =
            perpEngine.getPositionWithPnL(positionId);

        assertFalse(position.isActive);
        assertFalse(liquidatable); // Inactive positions are not liquidatable
    }
}
