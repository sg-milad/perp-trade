// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, Vm } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDT is ERC20 {
    uint256 constant INITIAL_SUPPLY = 1_000_000_000_000_000_000_000_000;
    uint8 constant DECIMALS = 18;

    constructor() ERC20("Tether USDT", "USDT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address user, uint256 value) public {
        _mint(user, value);
    }
}
