// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "../../src/test/TestERC20.sol";
import "../../src/UniswapV2Factory.sol";
import "../../src/UniswapV2Pair.sol";




contract UniswapV2PairTest is Test {
    address public _feeToSetter = address(0x30);
    address public testAddress = address(0x31);
    address public pairAddress;

    TestERC20 token0;
    TestERC20 token1;
    UniswapV2Pair uniswapV2Pair;
    UniswapV2Factory uniswapV2Factory;
    

    function setUp() public {

        

        token0 = new TestERC20(10000*10**18,'TOKEN0','T0');
        token1 = new TestERC20(10000*10**18,'TOKEN1','1');
        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        pairAddress =  uniswapV2Factory.createPair(address(token0),address(token1));
        console.log("pairAddress",pairAddress);
       
    }


    /**
    *   https://book.getfoundry.sh/forge/cheatcodes, check the event
    *
    */
    function test_Mint() public {

        token0.transfer(pairAddress,1*10**18);
        token1.transfer(pairAddress,4*10**18);

        uint expectedLiquidity = 2*10**18;

        uniswapV2Pair = UniswapV2Pair(pairAddress);
        
        uniswapV2Pair.mint(testAddress);
    }
   
}
