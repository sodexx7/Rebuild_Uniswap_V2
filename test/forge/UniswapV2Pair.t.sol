// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import "../../src/test/TestERC20.sol";
import "../../src/UniswapV2Factory.sol";
import "../../src/UniswapV2Pair.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ud, unwrap, UD60x18} from "prb-math/UD60x18.sol";

import "../../src/libraries/UQ112x112.sol";

contract UniswapV2PairTest is Test {
    using UQ112x112 for uint224;

    address public _feeToSetter = address(0x30);
    address public pairAddress;
    address public lockAddress = address(0x1);

    TestERC20 tokenA;
    TestERC20 tokenB;
    // reorder tokenA tokenB by address
    TestERC20 token0;
    TestERC20 token1;

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
        pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
        uniswapV2Pair = UniswapV2Pair(pairAddress);
        console.log("pairAddress", pairAddress);
        (token0, token1) = getOrderTestERC20(tokenA, tokenB);
    }

    /**
     *   https://book.getfoundry.sh/forge/cheatcodes, check the event
     * math points
     *
     * test  init mint， transfer 1  token and 4 token, for the first time
     */
    function test_Mint() public {
        uint256 token0transferAmount = 1 * 10 ** token0.decimals();
        uint256 token1transferAmount = 4 * 10 ** token1.decimals();

        token0.transfer(pairAddress, token0transferAmount);
        token1.transfer(pairAddress, token1transferAmount);

        uint256 expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
        vm.expectEmit(address(pairAddress));

        // for the first mint, should lock  MINIMUM_LIQUIDITY forever
        emit Transfer(address(0), lockAddress, uniswapV2Pair.MINIMUM_LIQUIDITY());
        // transfer LP to the caller
        uint256 actualLiquidity = expectedLiquidity - uniswapV2Pair.MINIMUM_LIQUIDITY();
        emit Transfer(address(0), address(this), actualLiquidity);

        emit Sync(uint112(token0.balanceOf(pairAddress)), uint112(token1.balanceOf(pairAddress)));

        // first mint, amount0 and amount1 equal the corresponding token transfer amount
        emit Mint(address(this), token0.balanceOf(pairAddress), uint112(token1.balanceOf(pairAddress)));

        uniswapV2Pair.mint(address(this));

        // check the Liquidity amount and reserves
        assertEq(uniswapV2Pair.balanceOf(lockAddress), uniswapV2Pair.MINIMUM_LIQUIDITY());
        assertEq(uniswapV2Pair.totalSupply(), expectedLiquidity);
        assertEq(uniswapV2Pair.balanceOf(address(this)), actualLiquidity);

        assertEq(token0.balanceOf(pairAddress), token0transferAmount);
        assertEq(token1.balanceOf(pairAddress), token1transferAmount);

        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();
        assertEq(uint112(token0.balanceOf(pairAddress)), _reserve0);
        assertEq(uint112(token1.balanceOf(pairAddress)), _reserve1);
    }

    /**
     * test cases:
     *   after initing the pool,  test the following actions includingc normal and expections cases  
     * 
     * 
     *    the related Math formula
     *    1. how to calculate the liqudity?
     *          uint expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
     *          for the first time, should lock  MINIMUM_LIQUIDITY(10 ** 3), so the received lp = expectedLiquidity - MINIMUM_LIQUIDITY
     *          for the following actions, the received lp = expectedLiquidity
     * 
     *    2. What's the effects of using the geometric mean.
     *         2.1 This formula ensures that the value of a liquidity pool share at any time is essentially independent of the ratio
     *     at which liquidity was initially deposited.
     *         (For the uniswap_v1,the value of a liquidity pool share was dependent on the ratio
     *         at which liquidity was initially deposited, which was fairly arbitrary, especially since there
     *         was no guarantee that that ratio reflected the true price.)
     * 
     *         TODO questions, seems this situation not test,how to do this specifical case
     *         2.2 but this desgin have one situation: the minimum quantity of liquidity pool shares ((1e-18 pool shares) is worth so much that
     *             it becomes infeasible for small liquidity providers to provide any liquidity.  ???
     * 
     *             
     *         but the desgin supply a possible:if one attacker donate 
     * 
     *    3. why store the MINIMUM_LIQUIDITY forever?
     *         1. prevent the situation, the minimum quantity of liquidity pool shares worth so much, that small liquidity providers to provide any liquidity.
     */
    function test_AddLiquidity() public {
        // init mint,
        uint256[2] memory addAmounts = [1 * 10 ** token0.decimals(), 4 * 10 ** token1.decimals()];
        uint256 expectedLiquidity = Math.sqrt(addAmounts[0] * addAmounts[1]);
        addLiquidity(addAmounts[0], addAmounts[1]);
        assertEq(uniswapV2Pair.balanceOf(address(this)), expectedLiquidity - uniswapV2Pair.MINIMUM_LIQUIDITY());
        uint256 firstLPAmount = uniswapV2Pair.balanceOf(address(this));
        console.log(firstLPAmount);

        // add liquidity after mint
        // normal
        // points
        /**
         * 1. calculate the liquidity
         *     2. the more token, how to deal with?
         */
        /**
         * 2. how many shares will mint while adding liquidity
         *         s = (dx/X) T=  (dy/Y) T
         */
        // 1999999999999999000 + 2000000000000000000

        // after initing the pool, add liquidity again,
        uint256[2] memory addAmounts2 = [1 * 10 ** token0.decimals(), 4 * 10 ** token1.decimals()];
        uint256 expectedLiquidity2 = Math.sqrt(addAmounts2[0] * addAmounts2[1]);
        addLiquidity(addAmounts2[0], addAmounts2[1]);
        assertEq(uniswapV2Pair.balanceOf(address(this)), expectedLiquidity2 + firstLPAmount);
        // console.log(uniswapV2Pair.balanceOf(address(this)));
        // the lp token are not propratation to the received pair tokens, of there are more pair token, how to deal with it, use sync()
        //

        // Exception test
        // uint[2] memory addAmounts3 = [1*10**tokenA.decimals(),0];
        // tokenA.transfer(pairAddress,addAmounts3[0]);
        // tokenB.transfer(pairAddress,addAmounts3[1]);
        // vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"));
        // UniswapV2Pair(pairAddress).mint(address(this));

        uint256[2] memory addAmounts4 = [0, 1 * 10 ** token0.decimals()];
        token0.transfer(pairAddress, addAmounts4[0]);
        token1.transfer(pairAddress, addAmounts4[1]);
        vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"));
        UniswapV2Pair(pairAddress).mint(address(this));
    }

    /**
     * Swap test:
     * 
     * 
     *     todo
     *     /expect test
     */

    //  problem:  [1, 5, 10, 1662497915624478906], my calculated resut is: (10*1)*10**18/(5+1) = 1666666666666666666
    //  given the pool, the swapAmount of token0, check the output Amount of token1 is right
    function test_SwapNormalCases() public {
        uint64[4][7] memory arrays_test = [
            [1, 5, 10, 1662497915624478906],
            [1, 10, 5, 453305446940074565],
            [2, 5, 10, 2851015155847869602],
            [2, 10, 5, 831248957812239453],
            [1, 10, 10, 906610893880149131],
            [1, 100, 100, 987158034397061298],
            [1, 1000, 1000, 996006981039903216]
        ];
        for (uint256 i = 0; i < arrays_test.length; i++) {
            uint256[2] memory liqudity =
                [(arrays_test[i][1] * uint256(10 ** 18)), uint256(arrays_test[i][2]) * uint256(10 ** 18)];
            uint256 swapAmount = uint256(arrays_test[i][0]) * uint256(10 ** 18);
            uint256 expectedOutputAmount1 = arrays_test[i][3];
            console.log(swapAmount);
            // vm.expectRevert(bytes("UniswapV2: K"));
            SwapTest(swapAmount, liqudity, 0, expectedOutputAmount1 + 1);
            // rebuild the pool address
            uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
            pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
            uniswapV2Pair = UniswapV2Pair(pairAddress);
            console.log("pairAddress", pairAddress);
            (token0, token1) = getOrderTestERC20(tokenA, tokenB);
        }
    }

    // same toke swap and same toke return.
    // 1/2/3 give the inputAmount, calculate the outputAmout
    // 4 given the  outputAmout, calculate the inputAmount
    function test_SwapCasesWithFees() public {
        uint64[4][4] memory arrays_test = [
            // [outputAmount, token0Amount, token1Amount, inputAmount]
            [997000000000000000, 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .997)
            [997000000000000000, 10, 5, 1],
            [997000000000000000, 5, 5, 1],
            [1, 5, 5, 1003009027081243732] // given amountOut, amountIn = ceiling(amountOut / .997)
        ];
        for (uint256 i = 0; i < arrays_test.length; i++) {
            uint256[2] memory liqudity =
                [(arrays_test[i][1] * uint256(10 ** 18)), uint256(arrays_test[i][2]) * uint256(10 ** 18)];

            uint256 swapAmount = i < 3 ? uint256(arrays_test[i][3]) * uint256(10 ** 18) : arrays_test[i][3];
            uint256 expectedOutputAmount0 = i < 3 ? arrays_test[i][0] : arrays_test[i][0] ** uint256(10 ** 18);
            SwapTest(swapAmount, liqudity, expectedOutputAmount0, 0);

            // rebuild the pool address
            uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
            pairAddress = uniswapV2Factory.createPair(address(tokenA), address(tokenB));
            uniswapV2Pair = UniswapV2Pair(pairAddress);
            console.log("pairAddress", pairAddress);
            (token0, token1) = getOrderTestERC20(tokenA, tokenB);
        }

        // test:amountIn = ceiling(amountOut / .997)
        uint256 result = Math.ceilDiv(10 ** 21, 997);
        console.log(result);
    }

    function test_SwapToken0AndCheck() public {
        uint256[2] memory liqudity = [uint256(5 * 10 ** 18), uint256(10 * 10 ** 18)];
        addLiquidity(liqudity[0], liqudity[1]);
        uint swapAmount = uint256(10 ** 18);
        // also a quesiton, can not figure out how to calculate the result
        uint256 expectedOutputAmount = 1662497915624478906;
        token0.transfer(pairAddress, swapAmount);

        // pair transfer the token1 to the this address
        emit Transfer(pairAddress, address(this), expectedOutputAmount);
        // Sync the balance0 and balance1
        emit Sync(uint112(swapAmount + liqudity[0]), uint112(liqudity[1] - expectedOutputAmount));

        // check the swap event
        emit Swap(pairAddress, swapAmount, 0, 0, expectedOutputAmount, address(this));
        
        uniswapV2Pair.swap(0, expectedOutputAmount, address(this));
        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();

        // check all kinds of balance
        assertEq(_reserve0,liqudity[0]+swapAmount);
        assertEq(_reserve1,liqudity[1]-expectedOutputAmount);


        assertEq(token0.balanceOf(pairAddress) ,liqudity[0]+swapAmount);
        assertEq(token1.balanceOf(pairAddress) ,liqudity[1]-expectedOutputAmount);

        uint totalSupplyToken0 =  token0.totalSupply();
        uint totalSupplyToken1 =  token1.totalSupply();
        assertEq(token0.balanceOf(address(this)) ,totalSupplyToken0-liqudity[0]-swapAmount);
        assertEq(token1.balanceOf(address(this)) ,totalSupplyToken0-liqudity[1]+expectedOutputAmount);
   
    }

    // just the opposite of the test_SwapToken0AndCheck
    function test_SwapToken1AndCheck() public {
        uint256[2] memory liqudity = [uint256(5 * 10 ** 18), uint256(10 * 10 ** 18)];
        addLiquidity(liqudity[0], liqudity[1]);
        uint swapAmount = uint256(10 ** 18);
        // also a quesiton, can not figure out how to calculate the result
        uint256 expectedOutputAmount = 453305446940074565;
        token1.transfer(pairAddress, swapAmount);

        // pair transfer the token1 to the this address
        emit Transfer(pairAddress, address(this), expectedOutputAmount);

        // Sync the balance0 and balance1
        emit Sync(uint112(liqudity[1] - expectedOutputAmount),uint112(swapAmount + liqudity[0]));

        // check the swap event
        emit Swap(pairAddress, 0,swapAmount, 0, expectedOutputAmount, address(this));
        
        uniswapV2Pair.swap(expectedOutputAmount,0, address(this));
        (uint112 _reserve0, uint112 _reserve1,) = uniswapV2Pair.getReserves();

        // // check all kinds of balance
        assertEq(_reserve0,liqudity[0]-expectedOutputAmount);
        assertEq(_reserve1,liqudity[1]+swapAmount);


        assertEq(token0.balanceOf(pairAddress) ,liqudity[0]-expectedOutputAmount);
        assertEq(token1.balanceOf(pairAddress) ,liqudity[1]+swapAmount);

        uint totalSupplyToken0 =  token0.totalSupply();
        uint totalSupplyToken1 =  token1.totalSupply();
        assertEq(token0.balanceOf(address(this)) ,totalSupplyToken0-liqudity[0]+expectedOutputAmount);
        assertEq(token1.balanceOf(address(this)) ,totalSupplyToken0-liqudity[1]-swapAmount);
   
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        token0.transfer(pairAddress, token0Amount);
        token1.transfer(pairAddress, token1Amount);
        UniswapV2Pair(pairAddress).mint(address(this));
    }

    function SwapTest(
        uint256 swapAmount,
        uint256[2] memory liqudity,
        uint256 expectedOutputAmount0,
        uint256 expectedOutputAmount1
    ) private {
        addLiquidity(liqudity[0], liqudity[1]);
        token0.transfer(pairAddress, swapAmount);
        uniswapV2Pair.swap(expectedOutputAmount0, expectedOutputAmount1, address(this));
    }

    /**
     * 1. calculate expectedOutputAmount1
     *     how many dy while swaping dx?
     *     dx=  x*dy / y + dx
     *     dy = y*dx/ (x+ dx)
     * 
     *     should consider the fees
     */

    function test_calculateExpectedOutputAmount1() public {
        uint256[2] memory liqudity = [uint256(10 * 10 ** 18), uint256(5 * 10 ** 18)];
        addLiquidity(liqudity[0], liqudity[1]);

        uint256 swapAmount = 1 * 10 ** 18;
        (uint112 _x, uint112 _y,) = uniswapV2Pair.getReserves();
        token0.transfer(pairAddress, swapAmount);

        //  453305446940074565
        uint256 expectedOutputAmount1 = 453305446940074565; // 1666666666666666667 1662497915624478906  the most expectedOutputAmount1:1662497915624478906
        uniswapV2Pair.swap(0, expectedOutputAmount1, address(this));
    }

    function test_calculateExpectedOutputAmount12() public {
        uint256[2] memory liqudity = [uint256(10 * 10 ** 18), uint256(5 * 10 ** 18)];
        addLiquidity(liqudity[0], liqudity[1]);

        UD60x18 dx = ud(1 * 10 ** 18);
        (uint112 _x, uint112 _y,) = uniswapV2Pair.getReserves();
        UD60x18 x = ud(uint256(_x));
        UD60x18 y = ud(uint256(_y));

        UD60x18 dy = (x.mul(dx)) / (y.add(dx));
        console.log(unwrap(dy));
    }

    // reorder address
    function getOrderTestERC20(TestERC20 tokenA, TestERC20 tokenB)
        private
        returns (TestERC20 token0, TestERC20 token1)
    {
        (address token0Address, address token1Address) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
        return (TestERC20(token0Address), TestERC20(token1Address));
    }
}
