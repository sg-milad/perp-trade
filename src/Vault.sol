// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LPToken } from "./LPToken.sol";

contract Vault is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant PERP_ENGINE_ROLE = keccak256("PERP_ENGINE_ROLE");

    IERC20 private immutable i_depositToken; // e.g., USDT
    LPToken private immutable i_LPToken;
    uint256 public totalLiquidity;
    uint256 private reservedLiquidity;

    event Deposit(address indexed sender, uint256 indexed amount);
    event Withdraw(address indexed sender, uint256 indexed amount);
    event PnLSettled(address indexed trader, int256 indexed pnlAmount);

    error InsufficientFreeLiquidity();
    error InsufficientReservedLiquidity();
    error ZeroAmount();
    error UnauthorizedAccess();

    constructor(address _depositToken, address _shareToken) {
        i_depositToken = IERC20(_depositToken);
        i_LPToken = LPToken(_shareToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Grant PerpEngine role to a contract
     * @param perpEngine Address of the PerpEngine contract
     */
    function grantPerpEngineRole(address perpEngine) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PERP_ENGINE_ROLE, perpEngine);
    }

    /**
     * @notice Deposit liquidity and receive LP tokens
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        totalLiquidity = totalLiquidity + amount;
        i_depositToken.safeTransferFrom(msg.sender, address(this), amount);
        i_LPToken.mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Withdraw liquidity by burning LP tokens
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (totalLiquidity - reservedLiquidity < amount) {
            revert InsufficientFreeLiquidity();
        }

        totalLiquidity = totalLiquidity - amount;

        i_LPToken.burn(msg.sender, amount);
        i_depositToken.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @notice Reserve liquidity for open positions
     * @param amount Amount to reserve
     */
    function reserveLiquidity(uint256 amount) external onlyRole(PERP_ENGINE_ROLE) {
        if (totalLiquidity - reservedLiquidity < amount) {
            revert InsufficientFreeLiquidity();
        }
        reservedLiquidity += amount;
    }

    /**
     * @notice Release reserved liquidity when positions are closed
     * @param amount Amount to release
     */
    function releaseLiquidity(uint256 amount) external onlyRole(PERP_ENGINE_ROLE) {
        if (reservedLiquidity < amount) {
            revert InsufficientReservedLiquidity();
        }
        reservedLiquidity -= amount;
    }

    /**
     * @notice Settle P&L for a trader
     * @param trader Address of the trader
     * @param pnlAmount P&L amount (positive for profit, negative for loss)
     */
    function settlePnL(address trader, int256 pnlAmount) external onlyRole(PERP_ENGINE_ROLE) {
        if (pnlAmount > 0) {
            // Trader has profit - vault pays the trader
            uint256 profit = uint256(pnlAmount);
            if (totalLiquidity < profit) {
                // Vault is insolvent - this is a critical issue
                profit = totalLiquidity;
            }
            totalLiquidity -= profit;
            i_depositToken.safeTransfer(trader, profit);
        } else if (pnlAmount < 0) {
            // Trader has loss - add to vault liquidity
            uint256 loss = uint256(-pnlAmount);
            totalLiquidity += loss;
            // Loss is already deducted from trader's collateral
        }

        emit PnLSettled(trader, pnlAmount);
    }

    /**
     * @notice Get current utilization rate
     */
    function getUtilizationRate() external view returns (uint256) {
        if (totalLiquidity == 0) return 0;
        return reservedLiquidity;
    }

    /**
     * @notice Get free liquidity available for new positions
     */
    function getFreeLiquidity() external view returns (uint256) {
        return totalLiquidity - reservedLiquidity;
    }

    /**
     * @notice Get reserved liquidity
     */
    function getReservedLiquidity() external view returns (uint256) {
        return reservedLiquidity;
    }
}
