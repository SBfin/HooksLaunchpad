// SPDX-License-Identifier MIT

pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

// Foundry libraries
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
// import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

// Our contracts
// import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";

// Needed for the deployment and testing:
// - PoolManager to create the pool
// - PositionManager to create the contracts
// - Router contract for the swaps
// - A developer (user) that deploy the contract and get the initial supply
// - A user that buys or sells the tokens
contract DeployBondingCurveToken is Script {
    address public DEVELOPER = 0x1B7E1b7EA98232c77f9eFc75c4a7C7ea2c4D79F1;
    // BondingCurveToken public bondingCurveToken;

    function run() external {
        vm.startBroadcast();
        console.log("Deploying FreshManagers and Routers");
        //deployFreshManagerAndRouters();

        vm.prank(DEVELOPER);
        console.log("Deploying BondingCurveToken");
        // console.log("Deploying BondingCurveToken with manager: ", address(manager));
        //bondingCurveToken = new BondingCurveToken(address(manager), address(modifyLiquidityRouter));
        vm.stopPrank();

        vm.stopBroadcast();
    }
}
