// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { BondingCurveFactory } from "../src/BondingCurveFactory.sol";
import "forge-std/console.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {console} from "forge-std/console.sol";

contract Deploy is Script, Deployers {
    function run() external {
        
        console.log("Deploying contracts");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // console.log("Deployer private key:", deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // Initialize Deployers
        // Deploy the PoolManager contract
        console.log("Deploying PoolManager and Routers");
        deployFreshManagerAndRouters();

        // Deploy the TokenFactory contract
        console.log("Deploying TokenFactory");
        
        BondingCurveFactory tokenFactory = new BondingCurveFactory(
            address(manager),
            address(modifyLiquidityRouter)
        );

        console.log("TokenFactory deployed at:", address(tokenFactory));

        vm.stopBroadcast();
    }
}