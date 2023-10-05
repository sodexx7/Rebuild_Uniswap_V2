// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC20Permit, IERC20, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC3156FlashLender} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "openzeppelin-contracts/contracts/interfaces/IERC3156FlashBorrower.sol";
import "../../src/test/TestERC20.sol";

import "./UniswapV2Pair.t.sol";


import "forge-std/Test.sol";

contract FlashBorrowerTest is Test {

    UniswapV2PairTest uniswapV2Test;
    address lenderAddress;
    FlashBorrower flashBorrower;

    ERC20Permit lenderToken0;
    ERC20Permit lenderToken1;

    function setUp() public {
        // create pool, and init the liquidity
        uniswapV2Test = new UniswapV2PairTest();
        uniswapV2Test.setUp();
        uniswapV2Test.test_Mint();
        lenderAddress = address(uniswapV2Test.uniswapV2Pair());
        console.log("lenderAddress",lenderAddress);

        // token0: 1 * 10 ** token0.decimals();
        // token0: 4 * 10 ** token1.decimals();

        // 1000*1000 = 1*1000,000,  the max token can borrow?

        // create FlashBorrower
        flashBorrower = new FlashBorrower(IERC3156FlashLender(lenderAddress));

        // set which token can be borrowed
        lenderToken0 = uniswapV2Test.token0();
        lenderToken1 = uniswapV2Test.token1();
        console.log("the valid borrowd token0:",address(lenderToken0));
        console.log("the valid borrowd token1:",address(lenderToken1));

    }

    function test_FlashBorrow() public {

        console.log("the valid balance:");
        console.log("token0 balance:",lenderToken0.balanceOf(lenderAddress));
        console.log("token1 balance:",lenderToken1.balanceOf(lenderAddress));
        // borrow lenderToken0 
        
        // uint borrowAmount = 5 * 10 ** (lenderToken0.decimals()-1);
        // 1000000000000000000
        uint borrowAmount = 1000000000000000000;
        //  plus fees:
        uint256 fee = IERC3156FlashLender(lenderAddress).flashFee(address(lenderToken0), borrowAmount);
        vm.prank(address(uniswapV2Test));
        lenderToken0.transfer(address(flashBorrower),fee);

        flashBorrower.flashBorrow(address(lenderToken0),borrowAmount);
        // after borrow， check the balance
        assertEq(lenderToken0.balanceOf(address(flashBorrower)),0);


        // beyond max borrow



        // consider the MINIMUM_LIQUIDITY



    }
}





contract FlashBorrower is IERC3156FlashBorrower {
    enum Action {ARBITRAGE_TRADING}

    IERC3156FlashLender lender;

    uint beforeBorrowBalance;

    constructor (
        IERC3156FlashLender lender_
    ) {
        lender = lender_;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns(bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        console.log("received amount:",ERC20Permit(token).balanceOf(address(this))-beforeBorrowBalance);
        (Action action) = abi.decode(data, (Action));
        if (action == Action.ARBITRAGE_TRADING) {
            console.log("Can do ARBITRAGE_TRADING while in this stage");
        } 
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(
        address token,
        uint256 amount
    ) public {
        bytes memory data = abi.encode(Action.ARBITRAGE_TRADING);
        uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(token, amount);
        uint256 _repayment = amount + _fee;
        console.log("_repayment",_repayment);
        IERC20(token).approve(address(lender), _allowance + _repayment);
        console.log("-------------------------start flash borrow-------------------------");
        console.log("amount,fee",amount,_fee);
        beforeBorrowBalance = ERC20Permit(token).balanceOf(address(this));
        lender.flashLoan(this, token, amount, data);
        console.log("-------------------------end flash borrow-------------------------");
        
        
    }
}