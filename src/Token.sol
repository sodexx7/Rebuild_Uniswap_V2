// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

// import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("TestERC20", "TTERC") {}
}
