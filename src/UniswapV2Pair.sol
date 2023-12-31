// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";


import {ERC20Permit, IERC20, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


// reference: https://github.com/PaulRBerg/prb-math/tree/v4.0.1
// https://soliditylang.org/blog/2021/09/27/user-defined-value-types/
import {ud, unwrap} from "prb-math/UD60x18.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IERC3156FlashLender} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";


/**
 * @title
 * @author
 * @notice
 * @dev
   checklist
   0. use solidity 0.8.21  delete SafeMath
 * 1. remove the  _safeTransfer and apply SafeERC20
 *      IERC20(_token0).safeTransfer(to, amount0);

 * 2. remove UQ112x112 and apply  UD60x18.sol to calculate the price{0,1}CumulativeLast

 * 3. directly use ERC20Permit instead of UniswapV2ERC20.
        ERC20Permit cover basic ERC20 functions and Permit funciton

 * 4. uint112(-1)  =>  type(uint112).max

 * 5. swap funciton: delete the flashloan function and make a separate function exectuing flashloan
        flashloan   swap delete param (bytes calldata data), delete IUniswapV2Callee interface and related functions
        reference: https://eips.ethereum.org/EIPS/eip-3156

   6.small tips:
      create2 create contract, which has arguments:
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes memory bytecode = abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode("Uniswap V2","UNI-V2"));


   other ignore points: lock for swap,mint,burn,skim,sync
 
 *  questions:
    1:how to calculate the amount of tokenB, given the amount of tokenA?
    2:// * never overflows, and + overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
    3: // scope for _token{0,1}, avoids stack too deep errors   
            scope for _token{0,1}, avoids stack too deep errors ??
    4:
        TAWP 
		how to attack? The cost of the attack?
		two complications:
		1:price tokenA/tokenB vs tokenB/tokenA
		2:prevent manipulation
        how to guarantee the price in one block? the relatihonships with the TWAP, and how to avoid the price-control.
    5:
        MINIMUM_LIQUIDITY, how to prevent attack?
    6:the below threee params in one slot,just for saving gas?
   
                uint112 private reserve0;           // uses single storage slot, accessible via getReserves
                 uint112 private reserve1;           // uses single storage slot, accessible via getReserves
                 uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves
  

    TODO
    1: forge build warn and errors checklist basic 
    2: calculate how much gas will be saved tests
    4: klist
    5:

 */
contract UniswapV2Pair is ERC20Permit, IUniswapV2Pair, IERC3156FlashLender,ReentrancyGuard {
    // flash loan
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");
    // uint256 public fee; //  1 == 0.01 %. should adjust based on the uniswap_v2 flashloan fee

    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

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
        uint32 timeElapsed;
        
        unchecked {
             timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired 
        }
        
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
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
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
 
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * (reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // dx = X (S/T )  dy = Y （S/T）
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
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
    /**
        change points
        1:don't support the flashswap
        2.when do flashloan in other functions, should make the fee calculation consistent with this function
    
     */

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
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
    function skim(address to) external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        IERC20(_token0).safeTransfer(to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        IERC20(_token1).safeTransfer(to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }


    /**
     * @dev Loan `amount` tokens to `receiver`, and takes it back plus a `flashFee` after the callback.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     *
     *
     * change points comparing the uniswap-v2 flashloan
     * 1. the lend token and the returned token are same while the uniswap v2 support return the corresponding token in one pair.
     * 2. the lender pull token and the fee while the borrower should return the token and the fee to the pair address in the uniswap_v2
     * 3. according to the swap funciton, It seems can borrow two tokens in the pair, but current implementation(EIP 3156) only support one token.
     * 4. the flashSwap fees is hardcode in the uniswap_v2 while EIP 3156 seems have more flexibility but bring some unconsistent, TODO
     * 5. user want to use the flashswap  in uniswap_v2 , should calling swap which support typical swap and flashswap, the EIP 3156 directly call the flashloan function
     * 6. the borrower must be the smart contract address in this implementation and for uniswap-v2 the borrower can be the  EOA address
     *
       security considerations
     * if the borrower lies, how to deal with?  lender check the arguments.

     *
     * other implementation. diffrerent current implementation
     *
     * 
     * when the fee returned, have some effects on the formula k
     *
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data) nonReentrant
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

        // require the borrower must have enough tokens to let the lender transfer
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount + fee);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

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
     * amount * 3 / 1000 have precious problem? at least borrow 1000 
     *
     */
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        require(token == token0 || token == token1, "FlashLender: Unsupported currency");

        return _flashFee(token, amount);
    }

    /**
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

}

/**

reference:
    https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/using-flash-swaps#single-token
    https://github.com/Rari-Capital
    the section about the security
                 https://eips.ethereum.org/EIPS/eip-3156
    reference: the blew formula
        https://www.youtube.com/watch?v=QNPyFs8Wybk
 *
 */










