// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {BondingCurveFactory} from "../src/BondingCurveFactory.sol";
import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";

contract TestBondingCurveFactory is Test, Deployers {
    BondingCurveFactory public factory;
    address public constant USER = address(0x1);

    function setUp() public {
        // Deploy Uniswap v4 contracts
        deployFreshManagerAndRouters();

        // Deploy factory
        factory = new BondingCurveFactory(
            address(manager),
            address(modifyLiquidityRouter)
        );

        // Fund test user
        vm.deal(USER, 100 ether);
    }

    function testCreateToken() public {
        vm.startPrank(USER);

        // Predict addresses
        address predictedToken = factory.predictTokenAddress("MyToken", "MTK");
        address predictedHook = factory.predictHookAddress("MyToken", "MTK");

        // Create token - declare as payable address
        address payable tokenAddress = payable(factory.createToken("MyToken", "MTK"));
        BondingCurveToken token = BondingCurveToken(tokenAddress);

        // Verify predictions
        assertEq(tokenAddress, predictedToken, "Token address prediction failed");
        
        // Verify token creation
        assertEq(token.name(), "MyToken", "Token name mismatch");
        assertEq(token.symbol(), "MTK", "Token symbol mismatch");

        // Verify user's tokens
        BondingCurveToken[] memory userTokens = factory.getTokensByUser(USER);
        assertEq(userTokens.length, 1, "User should have 1 token");
        assertEq(address(userTokens[0]), tokenAddress, "Token address mismatch in user's tokens");

        vm.stopPrank();
    }

    function testCreateMultipleTokens() public {
        vm.startPrank(USER);

        // Create multiple tokens
        address token1 = factory.createToken("Token1", "TK1");
        address token2 = factory.createToken("Token2", "TK2");

        // Verify user's tokens
        BondingCurveToken[] memory userTokens = factory.getTokensByUser(USER);
        assertEq(userTokens.length, 2, "User should have 2 tokens");
        assertEq(address(userTokens[0]), token1, "First token address mismatch");
        assertEq(address(userTokens[1]), token2, "Second token address mismatch");

        vm.stopPrank();
    }

    function testPredictAddresses() public {
        // Get predictions
        address predictedToken = factory.predictTokenAddress("MyToken", "MTK");
        address predictedHook = factory.predictHookAddress("MyToken", "MTK");

        // Verify predictions are different
        assertTrue(predictedToken != predictedHook, "Token and hook addresses should be different");
        assertTrue(predictedToken != address(0), "Token address should not be zero");
        assertTrue(predictedHook != address(0), "Hook address should not be zero");
    }
}