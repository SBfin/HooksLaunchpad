// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { BondingCurveFactory } from "../src/BondingCurveFactory.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import "forge-std/console.sol";
import {HookMiner} from "@uniswap/v4-template/test/utils/HookMiner.sol";
import {HookRevenues} from "../src/HookRevenues.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract Deploy is Script, Deployers {
    function run() external {
        
        console.log("Deploying contracts");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // console.log("Deployer private key:", deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // DEPLOY hook: we are using a single hook - in prod we should do hook per token
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(address(manager));

        // TODO USE CREATE2 address
        (address hookAddress, bytes32 salt) = HookMiner.find(0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, type(HookRevenues).creationCode, constructorArgs);

        console.log("Hook address:", hookAddress, "Salt:", uint256(salt));

        // Initialize Deployers
        // Deploy the PoolManager contract
        console.log("Deploying PoolManager and Routers");
        deployFreshManagerAndRouters();

        BondingCurveFactory tokenFactory = new BondingCurveFactory(
            address(manager),
            address(modifyLiquidityRouter),
            payable(hookAddress),
            salt
        );

        console.log("TokenFactory deployed at:", address(tokenFactory));


        
        // Deploy the TokenFactory contract
        console.log("Deploying TokenFactory");
        
        
        vm.stopBroadcast();
    }
}