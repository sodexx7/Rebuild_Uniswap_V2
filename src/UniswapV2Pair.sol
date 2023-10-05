// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

// openzeppelin-contracts/=lib/openzeppelin-contracts/
// openzeppelin/=lib/openzeppelin-contracts/contracts/

import {ERC20Permit, IERC20, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";

// reference: https://github.com/PaulRBerg/prb-math/tree/v4.0.1
// https://soliditylang.org/blog/2021/09/27/user-defined-value-types/
import {ud, unwrap} from "prb-math/UD60x18.sol";

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC3156FlashLender} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";

import "forge-std/Test.sol";

// import "forge-std/Test.sol";

/**
 * @title
 * @author
 * @notice
 * @dev
 * 1. remove the  _safeTransfer and apply SafeERC20
 *      IERC20(_token0).safeTransfer(to, amount0);
 * 2. remove UQ112x112 and apply  UD60x18.sol
 * 3. just use openzeplin ERC20Permit(uniswap ERC20, uniswap permit,  ) permit function as below
 *                  function mint(address to) external returns (uint256 liquidity);
 *                     function burn(address to) external returns (uint256 amount0, uint256 amount1);
 *                     function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
 *                     function skim(address to) external;
 *                     function sync() external;
 *
 *                     function initialize(address, address) external;
 * 4. delete UniswapV2ERC20
 * 5. uint112(-1)  =>  type(uint112).max
 * 6. the important tips: lock for swap,mint,burn,skim,sync
 * 7. the math knowledge lack?
 *
 *
 * delete:
 * 1. ERC20 related, permit related  IUniswapV2Pair UniswapV2ERC20
 * 2. flashloan   swap delete param (bytes calldata data), delete IUniswapV2Callee interface and related functions
 *
 *
 *
 *     some small tips:
 *  1. creat2: with arguments:
 *  // bytes memory bytecode = type(UniswapV2Pair).creationCode;
 *       bytes memory bytecode = abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode("Uniswap V2","UNI-V2"));
 *
 *     2. consider the uniswap use typescipt for uint test, add the corrospending uint test cases
 * todo compare the differences between old and my current implementation for erc20 and
 *
 *
 *     3. encode datas
 *
 *
 *     4.Maht points
 *     1.how to decide the liqudity(First mint,second mint)?
 *
 *     2.how to calculate the amount of tokenB, given the amount of tokenA?
 *
 *     3.****
 *         test case not work.
 */
contract UniswapV2Pair is ERC20Permit, IUniswapV2Pair, IERC3156FlashLender {
    // flash loan
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    // uint256 public fee; //  1 == 0.01 %. should adjust based on the uniswap_v2 flashloan fee

    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    // bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;

    event FlashLoan(address indexed borrower, address indexed token, uint256 amount);

    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    //  string public constant name = 'Uniswap V2';
    // string public constant symbol = 'UNI-V2';
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    // todo , mnove the logic into the constructor
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    // ? how to guarantee the first call per block???
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2: OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired TODO???
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            // the orginal uniswap desgin: uint112=>uint256=> UD60x18(operations)=> uint
            price0CumulativeLast += unwrap(ud(uint256(_reserve1)) / ud(uint256(_reserve0))) * timeElapsed;
            price1CumulativeLast += unwrap(ud(uint256(_reserve0)) / ud(uint256(_reserve1))) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * (_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens TODO//  address(0) => address(1) ,for ERC20Permit first MINIMUM_LIQUIDITY
        } else {
            liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
            // console.log("liquidity-test");
            // console.log("amount0",amount0);
            // console.log("amount1",amount1);
            // console.log("_totalSupply",_totalSupply);
            // console.log("amount0 * _totalSupply",amount0 * _totalSupply);
            // console.log("amount0 * _totalSupply / _reserve0",amount0 * _totalSupply / _reserve0);
            // console.log("amount1 * _totalSupply / _reserve1",amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * (reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // dx = X (S/T )  dy = Y （S/T）
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // change points
    // 1:don't support the flashswap
    // 2.should modify logic dealing with the flashSwap, the fee calculation, no, fee has been considerated
    //  3. when delete the flashswap, should adjust some logic,just one scenario, guarantee first send the tokens

    //  if remove the flashswap, there only exist one scenario which the asseet have been transfered to this address
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;

            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out); // optimistically transfer tokens  _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out); // optimistically transfer tokens  _safeTransfer(_token1, to, amount1Out);

            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;

        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
            require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000 ** 2), "UniswapV2: K");
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    // how to test?
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
        // _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0 );
        // _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1 );
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    /**
     * @dev Loan `amount` tokens to `receiver`, and takes it back plus a `flashFee` after the callback.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     *
     * whether according to the flashLoan desgin?
     *
     * inherit funciton, the visbality can change?
     *
     * todo , fee quesiton, consider??
     *
     *
     * the conflict problems?
     * uniswap can return all type
     * but the interface only return the corresping type token
     *
     * and the floashlocan can pull the fee and the principle   the uniswap v2?  doing problem
     *
     * Antoher implementation comparing the uniswap-v2 flashloan
     *
     * change points comparing the uniswap-v2 flashloan
     * 1. the lend token and the returned token are same while the uniswap v2 support return the corresponding token in one pair.
     * 2. the lender pull token and the fee while the borrower should return the token and the fee to the pair address in the uniswap_v2
     * 3. according to the swap funciton, It seems can borrow two tokens in the pair, but current implementation(EIP 3156) only support one token.
     * 4. the flashSwap fees is hardcode in the uniswap_v2 while EIP 3156 seems have more flexibility
     * 5. user want to use the flashswap  in uniswap_v2 , should calling swap which support typical swap and flashswap, the EIP 3156 directly call the EIP 3156
     * 6. the borrower must be the smart contract address?  and implement the IERC3156FlashBorrower., what's about the EOA address
     *
     * todo, security considerations
     * if the borrower lies, how to deal with?
     * lender check the arguments.
     *
     * other implementation. diffrerent current implementation
     *
     *
     * question?
     * when the fee returned, have some effects on the formula k
     *
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        require(token == token0 || token == token1, "FlashLender: Unsupported currency");


        uint256 fee = _flashFee(token, amount); // defalut 0.3%

        // flashloan transfer no tips??
        IERC20(token).safeTransfer(address(receiver), amount);

        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == CALLBACK_SUCCESS,
            "FlashLender: Callback failed"
        );

        // Can the below function can success execute?, the borrower should grant the operations, change,require borrower return the tokens
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount + fee);


        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));


        /** TODO
        check the balance change according to the uniswap v-2 x*y = k, but the below logic never can't execute， 
        because the above code can guarantee the recevice toekn must greater than borrow token and fees has included.
        but the desgin seems not consistant with the uniswap fee desgin.
        */

        // uint256 balance0Adjusted = token == token0 ? balance0 - fee : balance0;
        // uint256 balance1Adjusted = token == token1 ? balance1 - fee : balance1;
        // require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1, "UniswapV2: K");

        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        _update(balance0, balance1, _reserve0, _reserve1);

        emit FlashLoan(address(receiver), token, amount);

        return true;
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     *
     * according to the uniswap-v2 fee desgin
     *
     * amount * 3 / 1000 have precious problem?
     *
     */
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        require(token == token0 || token == token1, "FlashLender: Unsupported currency");

        return _flashFee(token, amount);
    }

    /**
     * todo tokem how to use ??
     * @dev The fee to be charged for a given loan. Internal function with no checks.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(address token, uint256 amount) internal pure returns (uint256) {
        return amount * 3 / 1000;
    }

    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256) {
        require(token == token0 || token == token1, "FlashLender: Unsupported currency");
        return IERC20(token).balanceOf(address(this));
    }

    // test: override internal mint funcition. delete the zero address check
    // can't  work, because can't access the _balances. So should change many places
    // function _burn(address account, uint256 amount) private {
    //     // require(account != address(0), "ERC20: mint to the zero address");

    //     _beforeTokenTransfer(address(0), account, amount);

    //     _totalSupply += amount;
    //     unchecked {
    //         // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
    //         _balances[account] += amount;
    //     }
    //     emit Transfer(address(0), account, amount);

    //     _afterTokenTransfer(address(0), account, amount);
    // }
}

/**
 * doing
 * 1. pair remake
 * - You must use solidity 0.8.0 or higher, don’t use SafeMath
 *    - Use an existing fixed point library, but don’t use the Uniswap one.
 *    - Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does
 *
 *
 * functions:
 * - Adding liquidity
 *    - Swapping
 *    - Withdrawing liquidity
 *
 *     checklist
 *     1. mint ,swap,burn delete the safeMath， other function skim. done
 *     2.              Use an existing fixed point library, but don’t use the Uniswap one. still have some questions should todo
 *             UQ112x112 ????     whle calculating the price0CumulativeLast.  the token price ?
 *             the basic usages?
 *             where to use fixed point number.
 *             the mechniasm? why use the UQ112x112 mechniasm ?
 *
 *             related contents. how to dealwith the precision/ more alternatives?
 *             QN*N
 *             MUL/DIV
 *
 *     3. Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does done
 *     4. doing
 *         Instead of implementing a flash swap the way Uniswap does, use EIP 3156. Be very careful at which point you update the reserves!
 *
 *         acknowledge the flashloan related contents, code ,doc, how to use exmaple, some consideration doing
 *
 *         doing eip-3156 implementation
 *         tooo 20230916
 *         https://eips.ethereum.org/EIPS/eip-3156
 *         EIP-3156 considerations
 *         1. Two interfaces, the sender, the receiver, the callback involved with the receiver
 *         2. some amount of token to send and replay...
 *         3. This implementation  how to transfer the token, the transfer approvel grant right?
 *         4. security considerations
 *             4.1 conditions check
 *             4.2  Flash lending security considerations  Automatic approvals do more
 *         5. flashloan test should consider the security problems
 *         6.
 *             the differences between ExampleFlashSwap and ERC-3156 borrowers inferface
 *             ExampleFlashSwap
 *
 *         implementaion
 *         1. currently, the uniswap_v2 implemened the flashloan in swap. implemnet the flashloan by ERC1365, where to implemented?
 *         2.
 *
 *         question1? the entry point? not changed?
 *                 how to adjust the current uniswap-v2 to the ERC3165 desgin?
 *         question2? uniswap-v2 fee consideration?
 *
 *         original swap and flashloan as a whole. accoring to the orginal desgin to apply the ERC3165
 *
 *         Be very careful at which point you update the reserves!
 *             1. current when to update the reserves
 *             2. where to update the reserves,
 *
 *
 *        7. new flash implementation doing
 *             fee calcuation
 *
 *        8. forge build warn and errors checklist basic done
 *
 *
 *        9. when to use lock, as before
 *
 *        10. inherit dig?? reference julisa's presenpeation
 */

// consideration checklist
// 1. the init param，swap can adjust more scenairos.
//                  Amount0Out          Amount1Out
//               tokenA <=> tokenB   (Amount0In <=> Amount1Out)

// 2. summary the main logic
//    factory=>pair
//

// 5. ???
// uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

// 6. calculate how much gas will be saved tests
// 7. some core operations
//      1. mint, the liquidity add and two reserves deposit

// 8. the indenpencies  clarify

// mint
// 1. calculate the liquidity
// 2. send the liquidity to address
// 3. update hte reservece
//      2. burn, the liquidity burn and return two reserves
//      3. swap, the liquidity change? and the change of the two reserves
/**
 *
 *      3. question
 *      // scope for _token{0,1}, avoids stack too deep errors ??
 *      // 2. swap main desgin???
 *          swap one tokenA to tokenB, but it seems not the desgin
 *          3. liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
 *          4. feeOn, whether or not set?
 *          5. Calculate the? the formula, list the below formula doing
 *               amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
 *                  amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
 *             6.
 *                 uint32 blockTimestamp = uint32(block.timestamp % 2**32);
 *
 *
 *
 *             8. block.timestamp???
 *                     seconds units, why % 2**32
 *                 uint32 blockTimestamp = uint32(block.timestamp % 2**32);
 *                 uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
 *                 blockTimestamp consideration
 *
 *             9.price0CumulativeLast
 *                 overflow check considerations.
 *                     uint32 blockTimestamp
 *                 diffculty problem
 *
 *             10. how to guarantee the price in one block? the relatihonships with the TWAP, and how to avoid the price-control.
 *
 *             11. the math meaning of the TAMP,  the relatinships with arbitrage?
 *
 *             12. check  the below calculation has some problem? overflow
 *                 price0CumulativeLast += Unwraps(ud(_reserve1)/ud(_reserve0))* timeElapsed;
 *
 *             14. the difference between Openzeppelin’s safeTransfer and uniswap safeTrasnfer
 *                 Use Openzeppelin’s or Solmate’s safeTransfer instead of building it from scratch like Unisawp does
 *                 Is uniswap safeTrasnfer have some problem?  not the check the address is contract
 *
 *             15. how to
 *                 flashswap, where shows the fee's logic?
 *
 *                 1. pay for the withdrawn ERC20 tokens with the corresponding pair tokens
 *                 2. return the withdrawn ERC20 tokens along with a small fee
 *
 *             16. stack too deep errors ???
 *                 scope for reserve{0,1}Adjusted, avoids stack too deep errors
 *                                 uint balance0Adjusted = balance0 * 1000 - amount0In * 3;
 *                                 uint balance1Adjusted = balance1 * 1000 - amount1In * 3;
 *
 *              17. swap hidden logic
 *
 *            . how to consider the swap logic in typical (non-flash) swap logic and flash logic.
 *
 *                 if (amount0Out > 0)  IERC20(_token0).safeTransfer(to, amount0Out); // optimistically transfer tokens  _safeTransfer(_token0, to, amount0Out);
 *                 if (amount1Out > 0)  IERC20(_token1).safeTransfer(to, amount1Out);  // optimistically transfer tokens  _safeTransfer(_token1, to, amount1Out);
 *
 *                 for this implementation, can transfer two type token each time.
 *
 *              21 overflow check tt
 */

//      4. transfer, transfer the liquidity pair token

//      5. balanceAdjusted????
/**
 *            consider the flashloan, how to calculate the result?
 *            https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps#single-token
 *
 *            reference: the blow formula
 *            https://www.youtube.com/watch?v=QNPyFs8Wybk
 */

// 8. some tricks， gas optimaztion?
// 1. if dont' add MINIMUM_LIQUIDITY, what's the results?
// consider the precious problem?
// the order, such as the execute order in mint, if changes, have some bad effects?

// 3. the below threee params in one slot
/**
 * uint112 private reserve0;           // uses single storage slot, accessible via getReserves
 *             uint112 private reserve1;           // uses single storage slot, accessible via getReserves
 *             uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves
 */
//4. who can call the function, factory contract
//5. how to use the lock?

// 6. the differences
/**
 * _update(balance0, balance1, _reserve0, _reserve1); the differece between balance0 and _reserve0
 */
// 7. _update the mechniasm? the involved mechniasm
// 8. { // scope for _token{0,1}, avoids stack too deep errors ???
// 9. the core deshin considerate how to interact with other layers, such as pherily, effectly, the datastructre and implementation have consider the point?

// 9. remake considerations

//      2. What considerations do you need in your fixed point library? How much of a token with 18 decimals can your contract store?
//      3. the core contract's api not directly called by the eoa? by the pherily contract?

/**
 * 10. other thoughts
 *  1. Solmate’s implementation and openzepplion's implementation.
 *  2. the main parties
 *      such as solmate https://github.com/Rari-Capital
 *  3.  Why exist flashloan
 *           It's well-known that an integral part of Uniswap's design is to create incentives for arbitrageurs to trade the Uniswap price to a "fair" market price.
 *
 */

/**
 * some design checklist
 * 1. why cache the reserve?
 *      somebody will send the token to pair address to manipulate the price  before calcuting the cumulativePrice
 *      another consideration, cache reserve will save gas?
 *
 * 2. cumulative price, one block?
 *      1. use balance, avovid someone to manipulate the asset price
 *
 * 3. the software desgin involving such as send onctract and received contract.
 */

// todo
// 1. digram the contract
// 2.  the section about the security
//   https://eips.ethereum.org/EIPS/eip-3156

// 3. the below modify add

// 4. the below format?

/**
 * require(
 *             token == token0 || token == token1
 *             "FlashLender: Unsupported currency"
 *         );
 */

/**
 * proper laypout
 * contract ProperLayout {
 *
 * 	// type declarations, e.g. using Address for address
 * 	// state vars
 * 	address internal owner;
 * 	uint256 internal _stateVar;
 * 	uint256 internal _starteVar2;
 *
 * 	// events
 * 	event Foo();
 * 	event Bar(address indexed sender);
 *
 * 	// errors
 * 	error NotOwner();
 * 	error FooError();
 * 	error BarError();
 *
 * 	// modifiers
 * 	modifier onlyOwner() {
 * 		if (msg.sender != owner) {
 * 			revert NotOwner();
 * 		}
 * 		_;
 * 	}
 *
 * 	// functions
 * 	constructor() {
 *
 * 	}
 *
 * 	receive() external payable {
 *
 * 	}
 *
 * 	falback() external payable {
 *
 * 	}
 *
 * 	// functions are first grouped by
 * 	// - external
 * 	// - public
 * 	// - internal
 * 	// - private
 * 	// note how the external functions "descend" in order of how much they can modify or interact with the state
 * 	function foo() external payable {
 *
 * 	}
 *
 * 	function bar() external {
 *
 * 	}
 *
 * 	function baz() external view {
 *
 * 	}
 *
 * 	function qux() external pure {
 *
 * 	}
 *
 * 	// public functions
 * 	function fred() public {
 *
 * 	}
 *
 * 	function bob() public view {
 *
 * 	}
 *
 * 	// internal functions
 * 	// internal view functions
 * 	// internal pure functions
 * 	// private functions
 * 	// private view functions
 * 	// private pure functions
 * }
 */

/**
 * test should pay attentaions checklist
 *
 * 1. // todo, creat2 contract test
 *    2. factory related?
 *    3.
 *         //  abi.encodePacked(token0, token1)   address token0, address token1, the same as abi.encode(token0, token1)  address 160bits. 320bits?
 *          //  abi.encodePacked, truncate the tail.
 *
 *    4.
 *                 // question
 *                 //  abi.encodePacked(token0, token1)   address token0, address token1, the same as abi.encode(token0, token1)  address 160bits. 320bits?
 *                 //  abi.encodePacked, truncate the tail.
 *
 *                 // 1. create2, pehaps have some same address? 2. sometime the same salt?
 *                 // 2.
 *
 *                 // 2. quesiton 2, in my understanding, the below contract can't be executed, because the contract was contracted and in one transaction ,and the transaction not end.
 *                 /**
 *   assembly {
 *         pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
 *     }
 *     IUniswapV2Pair(pair).initialize(token0, token1);
 *
 *
 *     5. check fee whether or not need?
 *
 *     6. import adjust
 *
 *     7. how to express fee?
 *
 *     8. overflow updarre
 *             overflow is desired
 *
 *     9.klist check?
 *         the math formula
 *
 *     10. some design considerations
 *
 *     11. fee two type fee
 *         swap fee, protocol fee
 *
 *     12.
 *         scope for _token{0,1}, avoids stack too deep errors
 *
 *     13.doing important
 *
 *             3. when delete the flashswap, should adjust some logic,just one scenario, guarantee first send the tokens
 *
 *     14, reference the orginal test case
 *
 *
 *
 */
