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
import {HookRevenues} from "../src/HookRevenues.sol";   

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

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
    HookRevenues public hook;

    event PoolInitialized(address poolManager, address currency0, address currency1, uint160 sqrtPriceX96);

    function setUp() public {
        vm.startBroadcast(DEVELOPER);
        console.log("Deploying FreshManagers and Routers");
        deployFreshManagerAndRouters();

        // Deploy the hook using a foundry cheatcode
        // the hook address must have correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG 
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        deployCodeTo("HookRevenues.sol:HookRevenues", abi.encode(manager), flags);
        hook = HookRevenues(flags);

        // Deploy bonding curve token
        console.log("Deploying BondingCurveToken");
        bondingCurveToken = new BondingCurveToken(address(manager), address(modifyLiquidityRouter));

        vm.deal(address(this), 1e12 ether);

        // deploy hook

        vm.stopBroadcast();
    }


    function testBuy() public {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);
        uint256 initialBalance = bondingCurveToken.balanceOf(address(this));
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;
        console.log("ethAmount: %d", ethAmount);

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

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
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

        // uint256 initialBalance = address(this).balance; // Get initial Ether balance
        uint256 initialTokenBalance = bondingCurveToken.balanceOf(address(this)); // Get initial token balance

        bondingCurveToken.sell(amountToSell);

        // uint256 newBalance = address(this).balance;
        uint256 newTokenBalance = bondingCurveToken.balanceOf(address(this));

        //assertEq(newBalance, initialBalance + (bondingCurveToken.getPrice() * amountToSell) / PRECISION, "User's Ether balance should increase after selling");
        assertEq(
            newTokenBalance, initialTokenBalance - amountToSell, "User's token balance should decrease after selling"
        );
    }

    function testExpectRevertInvalidAmount() public {
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        vm.expectRevert(BondingCurveToken.InvalidAmountError.selector);
        bondingCurveToken.buy{value: ethAmount - 1}(amountToBuy);
    }

    function testExpectRevertNotEnoughETHtoSellTokens() public {
        // First, buy some tokens to sell
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

        vm.expectRevert(BondingCurveToken.NotEnoughETHtoSellTokens.selector);
        bondingCurveToken.sell(amountToBuy + 50 ether);
    }

    function testCreateUniswapPool() public {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);

        // Buy enough tokens to trigger the creation of the Uniswap pool
        uint256 amountToBuy = bondingCurveToken.TOTAL_SUPPLY() - bondingCurveToken.totalSupply() + 1 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        console.log("ETH needed to buy enough tokens for pool creation: %d", ethAmount);

        // Send enough ETH to buy the remaining tokens
        // Set up expectations for PoolInitialized event
        // vm.expectEmit(true, true, true, true); // Setting all fields to true for full match
        // uint160 initialPriceCurve =
            // uint160(bondingCurveToken.getPriceAtSupply(bondingCurveToken.TOTAL_SUPPLY()) * (2 ^ 96));
        // emit PoolInitialized(address(manager), address(0), address(bondingCurveToken), uint160(initialPriceCurve)); // Expected event parameters

        address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        // Check that the supply is exactly the total supply
        assertEq(
            bondingCurveToken.totalSupply(),
            bondingCurveToken.TOTAL_SUPPLY(),
            "Total supply should be equal to TOTAL_SUPPLY"
        );
    }
}
