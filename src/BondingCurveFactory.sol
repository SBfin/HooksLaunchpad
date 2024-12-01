// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BondingCurveToken} from "./BondingCurveToken.sol";
import {HookRevenues} from "./HookRevenues.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract BondingCurveFactory {
    // State variables
    IPoolManager public immutable poolManager;
    address public immutable modifyLiquidityRouter;
    mapping(address => BondingCurveToken[]) public userTokens;
    
    // Events
    event TokenCreated(
        address indexed creator,
        address tokenAddress,
        address hookAddress,
        string name,
        string symbol
    );

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
    function createToken(
        string memory name,
        string memory symbol
    ) external returns (address token) {
        // Deploy the hook using foundry cheatcode
        address hookAddress = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | 
                Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook
        );

        // Deploy hook
        HookRevenues hook = new HookRevenues{salt: keccak256(abi.encode(name, symbol))}(
            poolManager
        );
        require(address(hook) == hookAddress, "Hook deployment failed");

        // Deploy token
        BondingCurveToken newToken = new BondingCurveToken{salt: keccak256(abi.encode(name, symbol))}(
            address(poolManager),
            modifyLiquidityRouter,
            address(hook)
        );

        // Store token in user's array
        userTokens[msg.sender].push(newToken);

        emit TokenCreated(
            msg.sender,
            address(newToken),
            address(hook),
            name,
            symbol
        );

        return address(newToken);
    }

    /**
     * @notice Gets all tokens created by a specific user
     * @param user The address of the user
     * @return An array of token addresses
     */
    function getTokensByUser(address user) external view returns (BondingCurveToken[] memory) {
        return userTokens[user];
    }

    /**
     * @notice Predicts the address of the token before it's created
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @return The predicted address of the token
     */
    function predictTokenAddress(
        string memory name,
        string memory symbol
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(name, symbol));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(type(BondingCurveToken).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Predicts the address of the hook before it's created
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @return The predicted address of the hook
     */
    function predictHookAddress(
        string memory name,
        string memory symbol
    ) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(name, symbol));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(type(HookRevenues).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}