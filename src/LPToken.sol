// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract LPToken is ERC20, Ownable, AccessControl {
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE"); // Role for minting and burning
        // tokens (the vault contracts)

    constructor() ERC20("Vault LP Token", "vUSD") Ownable(msg.sender) { }

    function grantMintAndBurnRole(address _address) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _address);
    }

    function mint(address to, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _burn(from, amount);
    }
}
