import { Wallet,BigNumber, utils } from 'ethers'
import { ethers, waffle } from 'hardhat'
import {UniswapV2Factory} from "../typechain-types/src/UniswapV2Factory"
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import {getCreate2Address } from './shared/utilities'
const { constants } = ethers
import foundry_UniswapV2Pair from './shared/foundry_UniswapV2Pair.json'

const TEST_ADDRESSES: [string, string] = [
  '0x1000000000000000000000000000000000000000',
  '0x2000000000000000000000000000000000000000'
]

const createFixtureLoader = waffle.createFixtureLoader



describe('UniswapV2Factory', () => {

  let wallet: Wallet, other: Wallet

  let factory: UniswapV2Factory
  let pairBytecode: string
  const fixture = async () => {
    const factoryFactory = await ethers.getContractFactory('UniswapV2Factory')
    return (await factoryFactory.deploy(wallet.address)) as UniswapV2Factory
  }

  // What's the meanings of the below code?
  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader([wallet, other])
  })

  before('load pair bytecode', async () => {
    // const initCode  = (await ethers.getContractFactory('UniswapV2Pair')).bytecode

    // console.log("initCode");
    // console.log(initCode);
    // // ?? doing contract address not equal?
    // // // Encode the constructor parameters
    // const encodedConstructorParameters = ethers.utils.defaultAbiCoder.encode(['string', 'string'], ['Uniswap V2', 'UNI-V2']);
    // // console.log("pairBytecode2",pairBytecode2);

    // pairBytecode = utils.solidityPack(
    //   ['bytes','bytes'],
    //   [initCode,
    //     encodedConstructorParameters
    //   ]
    // )

    // todo, perhaps the typescript calculate the bytecode have some problem?
    pairBytecode = `${foundry_UniswapV2Pair.bytecode.object}`

  })

  beforeEach('deploy factory', async () => {
    factory = await loadFixture(fixture)
  })


  // it('factory bytecode size', async () => {
  //   expect(((await waffle.provider.getCode(factory.address)).length - 2) / 2).to.matchSnapshot()
  // })


  it('pair bytecode size', async () => {
    
    await factory.createPair(TEST_ADDRESSES[0], TEST_ADDRESSES[1])
    const pairAddress = getCreate2Address(factory.address, TEST_ADDRESSES,pairBytecode)
    expect(((await waffle.provider.getCode(pairAddress)).length - 2) / 2).to.matchSnapshot()
  })

  it('feeTo, feeToSetter, allPairsLength', async () => {
    expect(await factory.feeTo()).to.eq(constants.AddressZero)
    expect(await factory.feeToSetter()).to.eq(wallet.address)
    expect(await factory.allPairsLength()).to.eq(0)
  })


  async function createPair(tokens: [string, string]) {
    // console.log("pairBytecode",pairBytecode)
    const create2Address = getCreate2Address(factory.address, tokens, pairBytecode)
    console.log("test- create2Address",create2Address)
    console.log("factory",factory.address)

    const create = await factory.createPair(...tokens)

    await expect(create)
      .to.emit(factory, 'PairCreated')
      .withArgs(TEST_ADDRESSES[0], TEST_ADDRESSES[1], create2Address,  BigNumber.from(1))



    // await expect(factory.createPair(tokens[0], tokens[1])).to.be.reverted  
    // await expect(factory.createPair(tokens[1], tokens[0])).to.be.reverted  

    // expect(await factory.getPair(tokens[0], tokens[1]), 'getPool in order').to.eq(create2Address)
    // expect(await factory.getPair(tokens[1], tokens[0]), 'getPool in reverse').to.eq(create2Address)

    
    // expect(await factory.allPairs(0)).to.eq(create2Address)
    // expect(await factory.allPairsLength()).to.eq(1)


    // const pairContractFactory = await ethers.getContractFactory('UniswapV2Pair')
    // console.log("test- pairContractFactory",pairContractFactory)
    // const pair = pairContractFactory.attach(create2Address)
    // console.log("test- pair",pair)

    // expect(await pair.factory()).to.eq(factory.address)
    // expect(await pair.token0()).to.eq(TEST_ADDRESSES[0])
    // expect(await pair.token1()).to.eq(TEST_ADDRESSES[1])
  }

  it('createPair', async () => {
    await createPair(TEST_ADDRESSES)
  })

  // it('createPair:reverse', async () => {
  //   await createPair(TEST_ADDRESSES.slice().reverse() as [string, string])
  // })

  // it('createPair:gas', async () => {
  //   const tx = await factory.createPair(...TEST_ADDRESSES)
  //   const receipt = await tx.wait()
  //   expect(receipt.gasUsed).to.eq(2512920)
  // })

  // // check the below right or not?
  // it('createPair:gas', async () => {
  //   await snapshotGasCost(factory.createPair(...TEST_ADDRESSES))
  // })

  // it('setFeeTo', async () => {
  //   await expect(factory.connect(other).setFeeTo(other.address)).to.be.revertedWith('UniswapV2: FORBIDDEN')
  //   await factory.setFeeTo(wallet.address)
  //   expect(await factory.feeTo()).to.eq(wallet.address)
  // })

  // it('setFeeToSetter', async () => {
  //   await expect(factory.connect(other).setFeeToSetter(other.address)).to.be.revertedWith('UniswapV2: FORBIDDEN')
  //   await factory.setFeeToSetter(other.address)
  //   expect(await factory.feeToSetter()).to.eq(other.address)
  //   await expect(factory.setFeeToSetter(wallet.address)).to.be.revertedWith('UniswapV2: FORBIDDEN')
  // })
})
