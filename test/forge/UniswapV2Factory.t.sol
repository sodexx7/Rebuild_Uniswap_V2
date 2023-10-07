// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../../src/UniswapV2Factory.sol";

import "../../src/UniswapV2Pair.sol";

import "openzeppelin-contracts/contracts/utils/Create2.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory uniswapV2Factory;
    address public _feeToSetter = address(30);
    address spenderAddress = address(11);// permit test address

    address pairAddress;
    UniswapV2Pair pair;

    address[] public addresses =
        [address(0x1000000000000000000000000000000000000000), address(0x2000000000000000000000000000000000000000)];

    address factory_hardhhat_address = address(0x5FbDB2315678afecb367f032d93F642f64180aa3);

    function setUp() public {
        uniswapV2Factory = new UniswapV2Factory(_feeToSetter);
        // console.log("uniswapV2Factory");
        // console.log(address(uniswapV2Factory));
        
        pairAddress = uniswapV2Factory.createPair(addresses[0], addresses[1]);
        pair = UniswapV2Pair(pairAddress);
    }

    function testCreatPair() public {
        // create pair
        bytes memory bytecode = abi.encodePacked(type(UniswapV2Pair).creationCode, abi.encode("Uniswap V2", "UNI-V2"));
        bytes32 salt = keccak256(abi.encodePacked(addresses[0], addresses[1]));
        console.log("abi.encodePacked(addresses[0],addresses[1])");
        console.logBytes(abi.encodePacked(addresses[0], addresses[1]));
        console.log("salt");
        console.logBytes32(salt);

        address precompileAddress = getAddress(bytecode, salt, address(uniswapV2Factory));
        console.log(precompileAddress);
        console.log(pairAddress);
        assertEq(precompileAddress, pairAddress);

        //  UniswapV2Pair test
        assertEq(pair.name(), "Uniswap V2");
        assertEq(pair.symbol(), "UNI-V2");
        assertEq(pair.factory(), address(uniswapV2Factory));
        assertEq(pair.token0(), addresses[0]);
        assertEq(pair.token1(), addresses[1]);

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
    // todo 
    function test_Permit() public {
        bytes32 value = pair.DOMAIN_SEPARATOR();

        bytes32 _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domain_separator_value = keccak256(abi.encode(_TYPE_HASH, keccak256(bytes("Uniswap V2")), keccak256(bytes("1")), block.chainid, pairAddress));
        console.logBytes32(domain_separator_value);
        assertEq(pair.DOMAIN_SEPARATOR(),domain_separator_value);

        uint nounces = pair.nonces(address(this));
        uint deadline = type(uint256).max;
        uint approveAmount = 1*10**pair.decimals();

        console.log("nounce",pair.nonces(address(this)));

        bytes32 _PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 signMessageHash = keccak256(abi.encode(_PERMIT_TYPEHASH, address(this), spenderAddress, approveAmount, nounces, deadline));


        // (bytes32 r, bytes32 s, uint8 v) = splitSignature(signMessageHash);

        // pair.permit(address(this),spenderAddress,approveAmount,deadline,v,r,s);


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


        return address(uint160(uint256(hash)));
    }


    // Permint related functions reference:https://solidity-by-example.org/signature/
    function splitSignature(
        bytes32  sig
    ) public pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
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
