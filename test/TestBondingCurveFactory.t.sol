// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {BondingCurveFactory} from "../src/BondingCurveFactory.sol";
import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookRevenues} from "../src/HookRevenues.sol";

contract TestBondingCurveFactory is Test, Deployers {
    BondingCurveFactory public factory;
    address public constant USER = address(0x1);
    HookRevenues public hook;

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

        // Create token
        address payable tokenAddress = payable(factory.createToken("MyToken", "MTK"));
        BondingCurveToken token = BondingCurveToken(tokenAddress);

        // Verify token creation
        assertEq(token.name(), "MyToken", "Token name mismatch");
        assertEq(token.symbol(), "MTK", "Token symbol mismatch");

        vm.stopPrank();
    }

}