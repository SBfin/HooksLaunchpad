// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

// Foundry libraries
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

// Our contracts
import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";

// Needed for the deployment and testing:
// - PoolManager to create the pool
// - PositionManager to create the contracts
// - Router contract for the swaps
// - A developer (user) that deploy the contract and get the initial supply
// - A user that buys or sells the tokens
contract TestBondingCurveToken is Test, Deployers {
    address public DEVELOPER = 0x1B7E1b7EA98232c77f9eFc75c4a7C7ea2c4D79F1;
    BondingCurveToken public bondingCurveToken;
    uint256 public constant PRECISION = 1e18;

    function setUp() public {
        vm.startBroadcast(DEVELOPER);
        console.log("Deploying FreshManagers and Routers");
        deployFreshManagerAndRouters();

        console.log("Deploying BondingCurveToken");
        bondingCurveToken = new BondingCurveToken(address(manager), address(modifyLiquidityRouter));
        vm.deal(address(this), 1e6 ether);
        vm.stopBroadcast();
    }

    function testBuy() public {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);
        uint256 initialBalance = bondingCurveToken.balanceOf(address(this));
        uint256 price = bondingCurveToken.getPrice();
        uint256 amountToBuy = 100 ether;
        uint256 ethAmount = (price * amountToBuy) / PRECISION;
        console.log("ethAmount: %d", ethAmount);

        // Calculate price and send enough ETH to buy tokens
        address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));

        uint256 newBalance = bondingCurveToken.balanceOf(address(this));
        assertEq(newBalance, initialBalance + amountToBuy, "User's balance should increase after buying");
        assertEq(
            address(bondingCurveToken).balance,
            (price * amountToBuy) / PRECISION,
            "Contract's balance should increase after buying"
        );
    }

    function testSell() public {
        uint256 amountToSell = 50 ether;

        // First, buy some tokens to sell
        uint256 price = bondingCurveToken.getPrice();
        uint256 amountToBuy = 100 ether;
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));

        uint256 initialBalance = address(this).balance; // Get initial Ether balance
        uint256 initialTokenBalance = bondingCurveToken.balanceOf(address(this)); // Get initial token balance

        bondingCurveToken.sell(amountToSell);

        uint256 newBalance = address(this).balance;
        uint256 newTokenBalance = bondingCurveToken.balanceOf(address(this));

        //assertEq(newBalance, initialBalance + (bondingCurveToken.getPrice() * amountToSell) / PRECISION, "User's Ether balance should increase after selling");
        assertEq(
            newTokenBalance, initialTokenBalance - amountToSell, "User's token balance should decrease after selling"
        );
    }
}
