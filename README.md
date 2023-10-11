
## Environments 
* This project apply Hardhat x Foundry Template for testing the new features by Foundry and can references the uniswap-v2 existed test cases.
* The hardhat environment have been adjusted to the current version, as the v2 have been build for almost three years.

## Modify points(remake uniswap_v2)
1. swap functions only support swap,don't support flashloan. 
2. inherited the IERC3156 to implement the flashloan, which has sonme difference comparing to the uniswap_V2
3. build the UniswapV2Pair by directly using ERC20Permit instead of UniswapV2ERC20. Now,just ignore the permit test
4. Calculate the TAWP by using the prb-math/UD60x18.sol instead of uniswap_v2 library UQ112x112. 
5. Other change points
    1.  use solidity 0.8.21  delete SafeMath
    2.  delete uniswap_v2 _safeTransfer, apply SafeERC20

## Fixed point library considerations
* What considerations do you need in your fixed point library? How much of a token with 18 decimals can your contract store?

    1. the fixed point library should consider how much decimals can have. For the prb, ud60x18 has 18 decimals and 60 digits.And based on that, do arithmetic operations while keep this precision. 
    2. Because for my current desgin, which is same as the uniswap v2, also the type is uint112.
       * uint112: 5192296858534827.     type(uint256).max/1e18
       * If apply the uint256, the max token can as the below.
       uint256: 115792089237316195423570985008687907853269984665640564039457                         type(uint256).max/1e18



## Test cases:
1. Adding liquidity
    * test_Mint()
    * test_AddLiquidity()
2. Swapping
    * test_SwapNormalCases()
    * test_SwapCasesWithFees()
    * test_SwapToken0AndCheck()
    * test_SwapToken1AndCheck()
3. Withdrawing liquidity
    * test_burn() 
    * test_burnReceivedAllTokens()
4. Check TWAP
    * test_TAWP()
5. Taking a flashloan(just show the feature, no cover many corner cases)
    * test_FlashBorrow()
6. Permit functions, Now, just ignore
    * test_Permit() 
7. Calculate the exactly outputAmount by considering the fee 
    * test_CalculateExpectOutputAmountWithFee()


## Tips:
1. how many dy while swaping dx?
    
    * Apply the below formulas, x,y means the balance of token0 and token1 in the last update. and dx,dy represent the increased or decreased amount 
    for x or y.

    ```
    dx=  (x*dy) / (y + dx)
    dy = (y*dx)/ (x+ dx)

    ```

    * x means the balance of token0,y means the balance of token1 in the last update, This is very important, For TAWP, this involved the security considerations.

2. The pool should lock MINIMUM_LIQUIDITY forever.

    * Increase the attacker cost. more detaisl can see the whitepaper:https://uniswap.org/whitepaper.pdf ( Initialization of liquidity token supply)

    * This desgin is different from the v1, calculating the uniswap_v2 pairs's liquidity is represent by the formula: ```Math.sqrt(uint256(_reserve0) * (_reserve1)).```
    This formula ensures that the value of a liquidity pool share at any time is essentially independent of the ratio at which liquidity was initially deposited.
    
    And this formula has more tricks, such as the desgin make the liquidity  linear grow while the pair token increasing.

3. Some Math formula 

    ````
        Given conditions。 
        X: amount of TokenA in AMM
        Y: amount of TokenB in AMM
        dx: amount of TokenA will in the AMM
        dy: amount of TokenB will in the AMM
        L0:Total liquidity before
        L1:Total liquidity After
        T: Total share before
        S: share to mint

        1. how many dy while swaping dx
            dx= x*dy / (y + dx)
            dy = y*dx/ (x+ dx)
            
        2. how many shares will mint while adding liquidity 
            s = (dx/X) T=  (dy/Y) T

        3. how many token will withdraw will remove  liquidity
            dx = X (S/T )  dy = Y （S/T）

    ```

4. Security considerations  
    1. TAWP price control
    2. prevent price manipulate by  lock MINIMUM_LIQUIDITY 

## Some small questions
1.  The plances where the overflow is desired.
2.  scope for _token{0,1}, avoids stack too deep errors
    to tead
    * https://levelup.gitconnected.com/stack-too-deep-error-in-solidity-ca83326ff0f0

3. Have some relationships with https://eips.ethereum.org/EIPS/eip-4626?


## TODO if time permits
1.  the difference between Openzeppelin’s safeTransfer and uniswap safeTrasnfer
    * Is uniswap safeTrasnfer have some problem?  not the check the address is contract
2. other stuffs relarted the desgin
    * lastK

## To read
* https://ethereum.org/sr/developers/tutorials/uniswap-v2-annotated-code/




## Plus
* change the uniswap_v2 Lock to the ReentrancyGuard(openzepplin), which saves more gas. 
* overflow is desired
    ```
    unchecked {
             timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired 
        }
    ```
   
    the reason why overflow is desired, because even overflow will happen, and the price{0,1}CumulativeLast will also work, just the user notice the overflow interval time. when use it should consider this situation.

    But This leads to a question about my code, because there is no overflow, so when time has passed until 2**32-1 and then update the blockTimeStamp. The scary thing will happen, The next time the actual blockTimeStamp will less than the blockTimeStamp. So the code almost will never go through .
    So one solution is just as uniswap v2 , make the overflow desired.