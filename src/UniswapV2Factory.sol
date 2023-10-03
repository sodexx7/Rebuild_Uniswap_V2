// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./interfaces/IUniswapV2Factory.sol";
import "./UniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 1: token0 not equal 0, and because token 1> token0, so token1>token0 NOT euqal 0
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS"); // single check is sufficient
        // bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes memory bytecode = abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode("Uniswap V2", "UNI-V2"));
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    // create pair
    // 0 check
    // 1. check the two address can't be equal
    // 2. check the two address can't be zero address
    // 3. check the two address can't have be used for this pair. have been to make a pair, the trick: when judge the getPair[token0][token1] == address(0) also judge the
    //  getPair[token1][token0] == address(0), because all set while creating the pair
    // 4.

    //  1 make pair
    // 1. create2 code
    //   by create2 code
    //      the difference between create2 and create ???
    //
    // question
    //  abi.encodePacked(token0, token1)   address token0, address token1, the same as abi.encode(token0, token1)  address 160bits. 320bits?
    //  abi.encodePacked, truncate the tail.

    // 1. create2, pehaps have some same address? 2. sometime the same salt?
    // 2.

    // 2. quesiton 2, in my understanding, the below contract can't be executed, because the contract was contracted and in one transaction ,and the transaction not end.
    /**
     *   assembly {
     *         pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
     *     }
     *     IUniswapV2Pair(pair).initialize(token0, token1);
     */

    //

    // https://www.evm.codes/#F5 doing??

    // other consideration confirm
    // the original desgin consideration
    //  1: why need cache token0 and token1???
    //  2:

    // summary
    // createPari
    //  uniswapFactory main funciton, create pair and store all the pair, by array  address[] public allPairs;
    // 1. create pair address, which specify the two token address. only the two token address.
    //  how to get the pair address  getPair[token0][token1]
    //
}
