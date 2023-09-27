// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/UniswapV2Pair.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Pair uniswapV2Pair;

    address[2] public addresses = [address(20),address(21)];

    function setUp() public {
        uniswapV2Pair = new UniswapV2Pair('Uniswap V2','UNI-V2');
       
    }


    function testInitialize() public {

        // console.log(addresses[0]);
        // console.log(addresses[1]);
        console.log(uniswapV2Pair.factory());
         uniswapV2Pair.initialize(addresses[0],addresses[1]);
        // console.log(pairAddress);
    }
   
}
