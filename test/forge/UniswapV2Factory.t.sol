// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/UniswapV2Factory.sol";

import "../../src/UniswapV2Pair.sol";

import "openzeppelin-contracts/contracts/utils/Create2.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory uniswapV2Factory;
    address public _feeToSetter = address(30);

    address[] public addresses =
        [address(0x1000000000000000000000000000000000000000), address(0x2000000000000000000000000000000000000000)];

    address factory_hardhhat_address = address(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    function setUp() public {
        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        // console.log("uniswapV2Factory");
        // console.log(address(uniswapV2Factory));
    }

    function testCreatPair() public {
        bytes memory bytecode = abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode("Uniswap V2", "UNI-V2"));
        bytes32 salt = keccak256(abi.encodePacked(addresses[0], addresses[1]));
        console.log("abi.encodePacked(addresses[0],addresses[1])");
        console.logBytes(abi.encodePacked(addresses[0], addresses[1]));
        console.log("salt");
        console.logBytes32(salt);

        address precompileAddress = getAddress(bytecode, salt, address(uniswapV2Factory));
        address pariAddress = uniswapV2Factory.createPair(addresses[0], addresses[1]);
        console.log(precompileAddress);
        console.log(pariAddress);
        assertEq(precompileAddress, pariAddress);

        //  UniswapV2Pair test
        assertEq(UniswapV2Pair(pariAddress).name(), "Uniswap V2");
        assertEq(UniswapV2Pair(pariAddress).symbol(), "UNI-V2");
        assertEq(UniswapV2Pair(pariAddress).factory(), address(uniswapV2Factory));
        assertEq(UniswapV2Pair(pariAddress).token0(), addresses[0]);
        assertEq(UniswapV2Pair(pariAddress).token1(), addresses[1]);

        // getPair test
        assertEq(uniswapV2Factory.getPair(addresses[0], addresses[1]), precompileAddress);
        assertEq(uniswapV2Factory.getPair(addresses[1], addresses[0]), precompileAddress);

        // allPairs test
        assertEq(uniswapV2Factory.allPairs(0), precompileAddress);
        assertEq(uniswapV2Factory.allPairsLength(), 1);

        //0x5FbDB2315678afecb367f032d93F642f64180aa3

        // address precompileAddress2 = getAddress(bytecode,salt,address(0x5FbDB2315678afecb367f032d93F642f64180aa3));
        // console.log("hardhat-create2 address");
        // console.log(precompileAddress2);
    }

    function testCreatPair3() private {
        address pariAddress = UniswapV2Factory(factory_hardhhat_address).createPair(addresses[0], addresses[1]);
        console.log("pariAddress");
        console.log(pariAddress);
    }

    // 2. Compute the address of the contract to be deployed
    // NOTE: _salt is a random number used to create an address
    function getAddress(bytes memory bytecode, bytes32 _salt, address factory) internal view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), factory, _salt, keccak256(bytecode)));

        console.log("hash");
        console.logBytes32(hash);

        // NOTE: cast last 20 bytes of hash to address

        return address(uint160(uint256(hash)));
    }

    /**
     * export function getCreate2Address(
     *   factoryAddress: string,
     *   [tokenA, tokenB]: [string, string],
     *   bytecode: string
     * ): string {
     *   const [token0, token1] = tokenA.toLowerCase() < tokenB.toLowerCase() ? [tokenA, tokenB] : [tokenB, tokenA]
     *   const constructorArgumentsEncoded = utils.defaultAbiCoder.encode(
     * ['address', 'address'],
     * [token0, token1]
     *   )
     *   const create2Inputs = [
     * '0xff',
     * factoryAddress,
     * // salt
     * utils.keccak256(constructorArgumentsEncoded),
     * utils.keccak256(bytecode)
     *   ]
     *   const sanitizedInputs = `0x${create2Inputs.map(i => i.slice(2)).join('')}`
     *   return utils.getAddress(`0x${utils.keccak256(sanitizedInputs).slice(-40)}`)
     * }
     */
}
