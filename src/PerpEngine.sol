// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PriceConverter} from "./lib/PriceConverter.sol";
import {Vault} from "./Vault.sol";

contract PerpEngine {
    using SafeERC20 for IERC20;
    using PriceConverter for AggregatorV3Interface;

    // State variables
    Vault public immutable vault;
    IERC20 public immutable collateralToken; // USDT
    AggregatorV3Interface public immutable priceFeed; // BTC/USD price feed

    uint256 public constant MAX_UTILIZATION_RATE = 8000;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant LIQUIDATION_THRESHOLD = 8000;
    uint256 public constant MIN_COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_REWARD = 500;
    uint256 public constant TRADING_FEE = 10;

    uint256 private nextPositionId = 1;

    struct Position {
        uint256 collateral; // Collateral amount in USDT
        uint256 size; // Position size in USDT
        uint256 entryPrice; // Entry price of BTC
        uint256 timestamp; // Position open timestamp
        address trader;
        bool isLong; // Long or short position
        bool isActive; // Position status
    }

    // Mappings
    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) public traderPositions;

    // Protocol stats
    uint256 public totalTradingVolume;
    uint256 public totalLiquidations;
    uint256 public totalFeesCollected;

    // Events
    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        uint256 collateral,
        uint256 size,
        uint256 entryPrice,
        bool isLong,
        uint256 tradingFee
    );

    event PositionSizeIncreased(
        uint256 indexed positionId, uint256 additionalSize, uint256 newSize, uint256 tradingFee
    );

    event CollateralAdded(uint256 indexed positionId, uint256 additionalCollateral, uint256 newCollateral);

    event PositionClosed(uint256 indexed positionId, int256 pnl, uint256 tradingFee);

    event PositionLiquidated(
        uint256 indexed positionId, address indexed liquidator, uint256 liquidationReward, int256 pnl
    );

    // Errors
    error InsufficientCollateral();
    error PositionNotFound();
    error NotPositionOwner();
    error ExceedsUtilizationLimit();
    error InvalidPositionSize();
    error PositionNotActive();
    error PositionNotLiquidatable();
    error InsufficientBalance();

    constructor(address _vault, address _collateralToken, address _priceFeed) {
        vault = Vault(_vault);
        collateralToken = IERC20(_collateralToken);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /**
     * @notice Open a new perpetual position for BTC
     * @param collateralAmount Amount of collateral to deposit
     * @param positionSize Size of the position in USDT
     * @param isLong True for long position, false for short
     */
    function openPosition(uint256 collateralAmount, uint256 positionSize, bool isLong)
        external
        returns (uint256 positionId)
    {
        if (collateralAmount == 0 || positionSize == 0) {
            revert InvalidPositionSize();
        }

        uint256 tradingFee = (positionSize * TRADING_FEE) / BASIS_POINTS;
        uint256 totalRequired = collateralAmount + tradingFee;

        if (collateralToken.balanceOf(msg.sender) < totalRequired) {
            revert InsufficientBalance();
        }
        // 100e4 < 15,0000
        if (collateralAmount * BASIS_POINTS < positionSize * MIN_COLLATERAL_RATIO) {
            revert InsufficientCollateral();
        }

        if (!_checkUtilizationRate(positionSize)) {
            revert ExceedsUtilizationLimit();
        }

        uint256 currentPrice = priceFeed.getPrice();
        positionId = nextPositionId++;

        // Create position
        positions[positionId] = Position({
            trader: msg.sender,
            collateral: collateralAmount,
            size: positionSize,
            entryPrice: currentPrice,
            isLong: isLong,
            timestamp: block.timestamp,
            isActive: true
        });

        traderPositions[msg.sender].push(positionId);

        vault.reserveLiquidity(positionSize);

        totalTradingVolume += positionSize;
        totalFeesCollected += tradingFee;

        collateralToken.safeTransferFrom(msg.sender, address(vault), totalRequired);

        emit PositionOpened(positionId, msg.sender, collateralAmount, positionSize, currentPrice, isLong, tradingFee);
    }

    /**
     * @notice Increase the size of an existing position
     * @param positionId ID of the position to increase
     * @param additionalSize Additional size to add to the position
     */
    function increasePositionSize(uint256 positionId, uint256 additionalSize) external {
        Position storage position = positions[positionId];

        if (!position.isActive) {
            revert PositionNotActive();
        }
        if (position.trader != msg.sender) {
            revert NotPositionOwner();
        }
        if (additionalSize == 0) {
            revert InvalidPositionSize();
        }

        uint256 tradingFee = (additionalSize * TRADING_FEE) / BASIS_POINTS;

        if (collateralToken.balanceOf(msg.sender) < tradingFee) {
            revert InsufficientBalance();
        }

        uint256 newSize = position.size + additionalSize;

        if (position.collateral * BASIS_POINTS < newSize * MIN_COLLATERAL_RATIO) {
            revert InsufficientCollateral();
        }

        if (!_checkUtilizationRate(additionalSize)) {
            revert ExceedsUtilizationLimit();
        }

        position.size = newSize;

        vault.reserveLiquidity(additionalSize);

        totalTradingVolume += additionalSize;
        totalFeesCollected += tradingFee;

        collateralToken.safeTransferFrom(msg.sender, address(vault), tradingFee);

        emit PositionSizeIncreased(positionId, additionalSize, newSize, tradingFee);
    }

    /**
     * @notice Add collateral to an existing position
     * @param positionId ID of the position
     * @param additionalCollateral Amount of collateral to add
     */
    function addCollateral(uint256 positionId, uint256 additionalCollateral) external {
        Position storage position = positions[positionId];

        if (!position.isActive) {
            revert PositionNotActive();
        }
        if (position.trader != msg.sender) {
            revert NotPositionOwner();
        }
        if (additionalCollateral == 0) {
            revert InvalidPositionSize();
        }

        position.collateral += additionalCollateral;

        collateralToken.safeTransferFrom(msg.sender, address(vault), additionalCollateral);

        emit CollateralAdded(positionId, additionalCollateral, position.collateral);
    }

    /**
     * @notice Close a position and settle P&L
     * @param positionId ID of the position to close
     */
    function closePosition(uint256 positionId) external {
        Position storage position = positions[positionId];

        if (!position.isActive) {
            revert PositionNotActive();
        }
        if (position.trader != msg.sender) {
            revert NotPositionOwner();
        }

        uint256 currentPrice = priceFeed.getPrice();
        int256 pnl = _calculatePnL(position, currentPrice);

        uint256 tradingFee = (position.size * TRADING_FEE) / BASIS_POINTS;

        position.isActive = false;

        vault.releaseLiquidity(position.size);

        int256 netPnl = pnl - int256(tradingFee);

        totalFeesCollected += tradingFee;

        vault.settlePnL(msg.sender, int256(position.collateral) + netPnl);

        emit PositionClosed(positionId, pnl, tradingFee);
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param positionId ID of the position to liquidate
     */
    function liquidate(uint256 positionId) external {
        Position storage position = positions[positionId];

        if (!position.isActive) {
            revert PositionNotActive();
        }

        uint256 currentPrice = priceFeed.getPrice();
        int256 pnl = _calculatePnL(position, currentPrice);
        int256 remainingCollateral = int256(position.collateral) + pnl;

        if (remainingCollateral > int256((position.collateral * LIQUIDATION_THRESHOLD) / BASIS_POINTS)) {
            revert PositionNotLiquidatable();
        }

        // Calculate liquidation reward for keeper(liqudater bot)
        uint256 liquidationReward = (position.collateral * LIQUIDATION_REWARD) / BASIS_POINTS;

        position.isActive = false;

        vault.releaseLiquidity(position.size);

        // Distribute remaining collateral
        if (remainingCollateral > 0) {
            uint256 remaining = uint256(remainingCollateral);
            if (remaining > liquidationReward) {
                // Pay liquidator reward
                vault.settlePnL(msg.sender, int256(liquidationReward));
                // Return remainder to trader
                vault.settlePnL(position.trader, int256(remaining - liquidationReward));
            } else {
                // Give all remaining to liquidator
                vault.settlePnL(msg.sender, remainingCollateral);
            }
        }
        // If remainingCollateral <= 0, position is fully liquidated with no payout

        // Update stats
        totalLiquidations++;

        emit PositionLiquidated(positionId, msg.sender, liquidationReward, pnl);
    }

    /**
     * @notice Check if a position can be liquidated
     * @param positionId ID of the position to check
     */
    function isLiquidatable(uint256 positionId) external view returns (bool) {
        Position memory position = positions[positionId];
        if (!position.isActive) return false;

        uint256 currentPrice = priceFeed.getPrice();
        int256 pnl = _calculatePnL(position, currentPrice);
        int256 remainingCollateral = int256(position.collateral) + pnl;
        int256 liquidationThreshold = int256(position.collateral * LIQUIDATION_THRESHOLD / BASIS_POINTS);

        return remainingCollateral <= liquidationThreshold;
    }

    /**
     * @notice Get all liquidatable positions
     */
    function getLiquidatablePositions() external view returns (uint256[] memory) {
        uint256[] memory liquidatable = new uint256[](nextPositionId - 1);
        uint256 count = 0;

        for (uint256 i = 1; i < nextPositionId; i++) {
            Position memory position = positions[i];
            if (!position.isActive) continue;

            uint256 currentPrice = priceFeed.getPrice();
            int256 pnl = _calculatePnL(position, currentPrice);
            int256 remainingCollateral = int256(position.collateral) + pnl;
            int256 liquidationThreshold = int256(position.collateral * LIQUIDATION_THRESHOLD / BASIS_POINTS);

            if (remainingCollateral <= liquidationThreshold) {
                liquidatable[count] = i;
                count++;
            }
        }

        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = liquidatable[i];
        }

        return result;
    }

    /**
     * @notice Get position details
     * @param positionId ID of the position
     */
    function getPosition(uint256 positionId) external view returns (Position memory) {
        return positions[positionId];
    }

    /**
     * @notice Get position details with current P&L
     * @param positionId ID of the position
     */
    function getPositionWithPnL(uint256 positionId)
        external
        view
        returns (Position memory position, int256 unrealizedPnL, uint256 currentPrice, bool liquidatable)
    {
        position = positions[positionId];
        currentPrice = priceFeed.getPrice();
        unrealizedPnL = _calculatePnL(position, currentPrice);

        if (position.isActive) {
            int256 remainingCollateral = int256(position.collateral) + unrealizedPnL;
            int256 liquidationThreshold = int256(position.collateral * LIQUIDATION_THRESHOLD / BASIS_POINTS);
            liquidatable = remainingCollateral <= liquidationThreshold;
        }
    }

    /**
     * @notice Get all position IDs for a trader
     * @param trader Address of the trader
     */
    function getTraderPositions(address trader) external view returns (uint256[] memory) {
        return traderPositions[trader];
    }

    /**
     * @notice Calculate unrealized P&L for a position
     * @param positionId ID of the position
     */
    function getUnrealizedPnL(uint256 positionId) external view returns (int256) {
        Position memory position = positions[positionId];
        if (!position.isActive) {
            return 0;
        }

        uint256 currentPrice = priceFeed.getPrice();
        return _calculatePnL(position, currentPrice);
    }

    /**
     * @notice Get current BTC price
     */
    function getCurrentPrice() external view returns (uint256) {
        return priceFeed.getPrice();
    }

    /**
     * @notice Get protocol statistics
     */
    function getProtocolStats()
        external
        view
        returns (
            uint256 _totalTradingVolume,
            uint256 _totalLiquidations,
            uint256 _totalFeesCollected,
            uint256 _activePositions,
            uint256 _totalLiquidity,
            uint256 _utilizationRate
        )
    {
        _totalTradingVolume = totalTradingVolume;
        _totalLiquidations = totalLiquidations;
        _totalFeesCollected = totalFeesCollected;
        _totalLiquidity = vault.totalLiquidity();
        _utilizationRate = vault.getUtilizationRate();

        // Count active positions
        for (uint256 i = 1; i < nextPositionId; i++) {
            if (positions[i].isActive) {
                _activePositions++;
            }
        }
    }

    // Internal functions
    function _calculatePnL(Position memory position, uint256 currentPrice) internal pure returns (int256) {
        int256 entryPrice = int256(position.entryPrice);
        int256 currPrice = int256(currentPrice);
        int256 priceDiff;

        if (position.isLong) {
            priceDiff = currPrice - entryPrice; // can be negative for loss
        } else {
            priceDiff = entryPrice - currPrice; // inverse for short
        }

        // position.size is uint256, cast to int256 safely if needed:
        int256 size = int256(position.size);

        // Calculate PnL scaled properly:
        int256 pnl = (priceDiff * size) / entryPrice;

        return pnl;
    }

    function _checkUtilizationRate(uint256 additionalSize) internal view returns (bool) {
        uint256 totalLiquidity = vault.totalLiquidity();
        if (totalLiquidity == 0) return false;

        uint256 currentUtilization = vault.getUtilizationRate();
        uint256 newUtilization = (currentUtilization + additionalSize) * BASIS_POINTS / totalLiquidity;

        return newUtilization <= MAX_UTILIZATION_RATE;
    }
}
