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
    address public immutable hookAddress;
    bytes32 public immutable salt;
    HookRevenues public immutable hook;

    // Events
    event TokenCreated(address indexed creator, address tokenAddress, address hookAddress, string name, string symbol);

    constructor(
        address _poolManager, 
        address _modifyLiquidityRouter, 
        address payable _hookAddress,
        bytes32 _salt
    ) {
        poolManager = IPoolManager(_poolManager);
        modifyLiquidityRouter = _modifyLiquidityRouter;
        hookAddress = _hookAddress;
        salt = _salt;
        
        hook = HookRevenues(_hookAddress);
    }

    /**
     * @notice Creates a new bonding curve token with associated hook
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @return token The address of the newly created token
     **/
    function createToken(
        string memory name, 
        string memory symbol
    ) external returns (address token) {
        // Use precomputed values instead of calculating on-chain        
        // Deploy token
        console.log('deployment');
        BondingCurveToken newToken = new BondingCurveToken{salt: keccak256(abi.encode(name, symbol))}(
            address(poolManager),
            address(modifyLiquidityRouter),
            address(hookAddress),
            name,
            symbol
        );

        console.log('newToken', address(newToken));

        emit TokenCreated(msg.sender, address(newToken), hookAddress, name, symbol);

        return address(newToken);
    }

}