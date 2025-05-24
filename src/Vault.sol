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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LPToken} from "./LPToken.sol";

contract Vault {
    ERC20 private immutable i_depositToken; // e.g., USDT
    LPToken private immutable i_LPToken;
    uint256 public totalLiquidity;
    uint256 private reservedLiquidity;

    event Deposit(address indexed sender, uint256 indexed amount);
    event Withdraw(address indexed sender, uint256 indexed amount);

    constructor(address _depositToken, address _shareToken) {
        i_depositToken = ERC20(_depositToken);
        i_LPToken = LPToken(_shareToken);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero deposit");
        totalLiquidity = totalLiquidity + amount;
        i_depositToken.transferFrom(msg.sender, address(this), amount);
        i_LPToken.mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Zero withdraw");
        totalLiquidity = totalLiquidity - amount;

        i_LPToken.burn(msg.sender, amount);
        i_depositToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    // TODO: implement access control for reserveLiquidity & releaseLiquidity.
    // only perp contract should able to call theme
    function reserveLiquidity(uint256 amount) external {
        require(totalLiquidity - reservedLiquidity >= amount, "Not enough free liquidity");
        reservedLiquidity += amount;
    }

    function releaseLiquidity(uint256 amount) external {
        require(reservedLiquidity >= amount, "Release exceeds reserved");
        reservedLiquidity -= amount;
    }

    // allows the contract to receive rewards
    receive() external payable {}
}
