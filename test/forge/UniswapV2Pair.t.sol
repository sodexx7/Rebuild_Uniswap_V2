// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "../../src/test/TestERC20.sol";
import "../../src/UniswapV2Factory.sol";
import "../../src/UniswapV2Pair.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";




contract UniswapV2PairTest is Test {

    address public _feeToSetter = address(0x30);
    address public pairAddress;
    address public lockAddress = address(0x1);

    TestERC20 tokenA;
    TestERC20 tokenB;
    UniswapV2Pair uniswapV2Pair;
    UniswapV2Factory uniswapV2Factory;

    // test events
    // 
    event Sync(uint112 reserve0, uint112 reserve1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );


    event Transfer(address indexed from, address indexed to, uint256 value);

    

    function setUp() public {
        

        tokenA = new TestERC20(10000*10**18,'TOKENA','TA');
        tokenB = new TestERC20(10000*10**18,'TOKENB','TB');
        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        pairAddress =  uniswapV2Factory.createPair(address(tokenA),address(tokenB));
        uniswapV2Pair = UniswapV2Pair(pairAddress);
        console.log("pairAddress",pairAddress);
    }


    /**
    *   https://book.getfoundry.sh/forge/cheatcodes, check the event
    * math points
    *
    * test  init mint， transfer 1  token and 4 token, for the first time
    */
    function test_Mint() public {
        uint token0transferAmount = 1*10**tokenA.decimals();
        uint token1transferAmount = 4*10**tokenA.decimals();

        address tokenAaddress = address(tokenA);
        address tokenBaddress = address(tokenB);
        (address token0ddress, address token1ddress) = tokenAaddress < tokenBaddress ? (tokenAaddress, tokenBaddress) : (tokenBaddress, tokenAaddress);
        TestERC20 token0 = TestERC20(token0ddress);
        TestERC20 token1 = TestERC20(token1ddress);

        token0.transfer(pairAddress,token0transferAmount);
        token1.transfer(pairAddress,token1transferAmount);


        
        uint expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
        
        vm.expectEmit(address(pairAddress));

        // for the first mint, should lock  MINIMUM_LIQUIDITY forever
        emit Transfer(address(0),lockAddress,uniswapV2Pair.MINIMUM_LIQUIDITY());
        // transfer LP to the caller
        uint actualLiquidity = expectedLiquidity-uniswapV2Pair.MINIMUM_LIQUIDITY();
        emit Transfer(address(0),address(this),actualLiquidity);

        emit Sync(uint112(token0.balanceOf(pairAddress)), uint112(token1.balanceOf(pairAddress)));

        // first mint, amount0 and amount1 equal the corresponding token transfer amount
        emit Mint(address(this), token0.balanceOf(pairAddress), uint112(token1.balanceOf(pairAddress)));


        uniswapV2Pair.mint(address(this));


        // check the Liquidity amount and reserves
        assertEq(uniswapV2Pair.balanceOf(lockAddress),uniswapV2Pair.MINIMUM_LIQUIDITY());
        assertEq(uniswapV2Pair.totalSupply(),expectedLiquidity);
        assertEq(uniswapV2Pair.balanceOf(address(this)),actualLiquidity);

        assertEq(token0.balanceOf(pairAddress) ,token0transferAmount);
        assertEq(token1.balanceOf(pairAddress) ,token1transferAmount);

        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();
        assertEq(uint112(token0.balanceOf(pairAddress)) ,_reserve0);
        assertEq(uint112(token1.balanceOf(pairAddress)) ,_reserve1);
    }

    function test_AddLiquidity() public {
        // init mint, as test_Mint
        uint[2] memory addAmounts = [1*10**tokenA.decimals(),4*10**tokenA.decimals()]; 
        addLiquidity(addAmounts[0],addAmounts[1]);
        console.log(uniswapV2Pair.balanceOf(address(this)));

        // add liquidity after mint
        // normal 
        // points
        /**
        1. calculate the liquidity
        2. the more token, how to deal with?
         */
        /**
         * 2. how many shares will mint while adding liquidity 
            s = (dx/X) T=  (dy/Y) T
         
         
         */
        // 1999999999999999000 + 2000000000000000000

        // after initing the pool, add liquidity again
        uint[2] memory addAmounts2 = [1*10**tokenA.decimals(),4*10**tokenA.decimals()]; 
        addLiquidity(addAmounts2[0],addAmounts2[1]);
        console.log(uniswapV2Pair.balanceOf(address(this)));
        // the lp token are not propratation to the received pair tokens, of there are more pair token, how to deal with it, use sync() 
        // 

        
        // Exception
        // uint[2] memory addAmounts3 = [1*10**tokenA.decimals(),0];
        // tokenA.transfer(pairAddress,addAmounts3[0]);
        // tokenB.transfer(pairAddress,addAmounts3[1]);
        // vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED")); 
        // UniswapV2Pair(pairAddress).mint(address(this));

        uint[2] memory addAmounts4 = [0,1*10**tokenA.decimals()];
        tokenA.transfer(pairAddress,addAmounts4[0]);
        tokenB.transfer(pairAddress,addAmounts4[1]);
        vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED")); 
        UniswapV2Pair(pairAddress).mint(address(this));



    }


    function  addLiquidity(uint tokenAAmount,uint tokenBAmount ) private {
        tokenA.transfer(pairAddress,tokenAAmount);
        tokenB.transfer(pairAddress,tokenBAmount);
        UniswapV2Pair(pairAddress).mint(address(this));

    }

  }


   
