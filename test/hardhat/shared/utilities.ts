import { utils } from 'ethers'

import {BigNumber,Contract } from 'ethers'

const PERMIT_TYPEHASH = utils.keccak256(
  utils.toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
)

export function expandTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

function getDomainSeparator(name: string, tokenAddress: string) {
  return utils.keccak256(
    utils.defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        utils.keccak256(utils.toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        utils.keccak256(utils.toUtf8Bytes(name)),
        utils.keccak256(utils.toUtf8Bytes('1')),
        1,
        tokenAddress
      ]
    )
  )
}

// can be as a funciton tool, get the address while generate the address by create2 
export function getCreate2Address(
  factoryAddress: string,
  [tokenA, tokenB]: [string, string],
  bytecode: string
): string {
  const [token0, token1] = tokenA.toLowerCase() < tokenB.toLowerCase() ? [tokenA, tokenB] : [tokenB, tokenA]
  
  // const constructorArgumentsEncoded = utils.defaultAbiCoder.encode(
  //   ['address', 'address'],
  //   [token0, token1]
  // )
  // like the sol implementation, us the abi.encodePacked
  const constructorArgumentsEncoded = utils.solidityPack(
    ['bytes', 'bytes'],
    [
      token0,
      token1,
    ]
  )

  const hash = utils.keccak256(utils.solidityPack(
        ['bytes1', 'address', 'bytes32', 'bytes32'],
        [
          '0xff',
          factoryAddress,
          // salt 
          utils.keccak256(constructorArgumentsEncoded),
          utils.keccak256(bytecode)
        ]
      )
    )

  // console.log("token0, token1")
  // console.log(token0, token1)

  // console.log("constructorArgumentsEncoded")
  // console.log(utils.keccak256(constructorArgumentsEncoded))


  // console.log("utils.keccak256(bytecode)")
  // console.log(utils.keccak256(bytecode))


  console.log("hash")
  console.log(hash)

  return utils.getAddress(`0x${hash.slice(-40)}`)
}

export async function getApprovalDigest(
  token: Contract,
  approve: {
    owner: string
    spender: string
    value: BigNumber
  },
  nonce: BigNumber,
  deadline: BigNumber
): Promise<string> {
  const name = await token.name()
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address)
  return utils.keccak256(
    utils.solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
        utils.keccak256(
          utils.defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
          )
        )
      ]
    )
  )
}


export function encodePrice(reserve0: BigNumber, reserve1: BigNumber) {
  return [reserve1.mul(BigNumber.from(2).pow(112)).div(reserve0), reserve0.mul(BigNumber.from(2).pow(112)).div(reserve1)]
}
