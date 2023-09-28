import {UniswapV2Factory} from "../../../typechain-types/src/UniswapV2Factory"
import {TestERC20} from "../../../typechain-types/src/test/TestERC20"
import {UniswapV2Pair} from "../../../typechain-types/src/UniswapV2Pair"
import { BigNumber,Wallet } from 'ethers'
import { ethers } from 'hardhat'
import { expandTo18Decimals } from '../shared/utilities'



interface FactoryFixture {
  factory: UniswapV2Factory
}

// this param should confirm
// the format of below params's meaning?
async function factoryFixture([wallet]: Wallet[]): Promise<FactoryFixture> {
  const factoryFactory = await ethers.getContractFactory('UniswapV2Factory')
  const factory = (await factoryFactory.deploy(wallet.address)) as UniswapV2Factory
  return { factory }
}

// export async function factoryFixture(_: Web3Provider, [wallet]: Wallet[]): Promise<FactoryFixture> {
//   const factory = await deployContract(wallet, UniswapV2Factory, [wallet.address], overrides)
//   return { factory }
// }


interface PairFixture extends FactoryFixture {
  token0: TestERC20
  token1: TestERC20
  pair: UniswapV2Pair
}

export async function pairFixture([wallet]: Wallet[]): Promise<PairFixture> {
  const { factory } = await factoryFixture([wallet])

  const tokenFactory = await ethers.getContractFactory('TestERC20')
  const tokenA = (await tokenFactory.deploy(expandTo18Decimals(10000),"TOKEN0","T0")) as TestERC20
  const tokenB = (await tokenFactory.deploy(expandTo18Decimals(10000),"TOKEN1","T1")) as TestERC20


  await factory.createPair(tokenA.address, tokenB.address)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)

  const pairContractFactory = await ethers.getContractFactory('UniswapV2Pair')
  const pair = pairContractFactory.attach(pairAddress)


  const token0Address = (await pair.token0())
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return { factory, token0, token1, pair }
}
