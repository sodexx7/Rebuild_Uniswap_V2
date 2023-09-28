// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20Permit, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TestERC20 is ERC20Permit {
    constructor(uint _totalSupply,string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, _totalSupply);
    }
}
