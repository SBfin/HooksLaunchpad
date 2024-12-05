// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {BondingCurveFactory} from "../src/BondingCurveFactory.sol";
import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookRevenues} from "../src/HookRevenues.sol";
import {HookMiner} from "@uniswap/v4-template/test/utils/HookMiner.sol";


contract TestBondingCurveFactory is Test, Deployers {
    BondingCurveFactory public factory;
    address public constant USER = address(0x1);
    HookRevenues public hook;
    address public hookAddress;
    bytes32 public salt;

    event TokenCreated(address indexed creator, address tokenAddress, address hookAddress, string name, string symbol);


    function setUp() public {
        // Deploy Uniswap v4 contracts
        deployFreshManagerAndRouters();

        // generated with hook miner, cannot run it in the factory as goes out of gas
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(address(manager));

        (hookAddress, salt) = HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, type(HookRevenues).creationCode, constructorArgs);

        console.log("Hook address:", hookAddress);

        // Deploy factory
        factory = new BondingCurveFactory(
            address(manager),
            address(modifyLiquidityRouter),
            payable(hookAddress),
            salt
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