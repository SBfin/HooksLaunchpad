// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BondingCurveToken} from "./BondingCurveToken.sol";
import {HookRevenues} from "./HookRevenues.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-template/test/utils/HookMiner.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import "forge-std/console.sol";
contract BondingCurveFactory {
    // State variables
    IPoolManager public immutable poolManager;
    address public immutable modifyLiquidityRouter;

    // Events
    event TokenCreated(address indexed creator, address tokenAddress, address hookAddress, string name, string symbol);

    constructor(address _poolManager, address _modifyLiquidityRouter) {
        poolManager = IPoolManager(_poolManager);
        modifyLiquidityRouter = _modifyLiquidityRouter;
    }

    /**
     * @notice Creates a new bonding curve token with associated hook
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @return token The address of the newly created token
     */
    function createToken(string memory name, string memory symbol) external returns (address token) {
        // Calculate hook flags
        console.log("inside createToken");
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
        
        // Prepare constructor arguments for the hook
        // should add also name and symbol in the constructorArgs of the hook miner
        bytes memory constructorArgs = abi.encode(poolManager);
        
        // Find hook address using HookMiner
        console.log("inside HookMiner.find");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this), // Correct checksummed address
            flags,
            type(HookRevenues).creationCode,
            constructorArgs
        );

        console.log("Hook address:", hookAddress);

        // Deploy hook
        HookRevenues hook = new HookRevenues{salt: salt}(IPoolManager(poolManager));

        console.log("Hook address:", address(hook));
        require(address(hook) == hookAddress, "Hook deployment failed");


        // Deploy token
        BondingCurveToken newToken = new BondingCurveToken{salt: keccak256(abi.encode(name, symbol))}(
            address(poolManager),
            address(modifyLiquidityRouter),
            address(hook),
            name,
            symbol
        );

        emit TokenCreated(msg.sender, address(newToken), address(hook), name, symbol);

        return address(newToken);
    }

}