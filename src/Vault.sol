// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "solmate/tokens/ERC4626.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {LPToken} from "./LPToken.sol";

contract Vault {
    ERC20 public immutable i_depositToken; // e.g., USDT
    LPToken public immutable i_LPToken;

    constructor(address _depositToken, address _shareToken) {
        i_depositToken = ERC20(_depositToken);
        i_LPToken = LPToken(_shareToken);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero deposit");
        i_depositToken.transferFrom(msg.sender, address(this), amount);
        i_LPToken.mint(msg.sender, amount);
    }

    function withdraw(uint256 shareAmount) external {
        require(shareAmount > 0, "Zero withdraw");
        i_LPToken.burn(msg.sender, shareAmount);
        i_depositToken.transfer(msg.sender, shareAmount);
    }

    // allows the contract to receive rewards
    receive() external payable {}
}
