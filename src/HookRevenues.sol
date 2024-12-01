// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract HookRevenues is BaseHook {
    // Hook to collect fees from the pool
    uint256 public constant HOOK_FEE = 100; // 1% fee (assuming WAD scale)

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterSwap(
        address, // sender
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata // hookData
    ) external override returns (bytes4, int128) {
        // fee will be in the unspecified token of the swap
        bool isCurrency0Specified = (params.amountSpecified < 0 == params.zeroForOne);

        (Currency currencyUnspecified, int128 amountUnspecified) =
            (isCurrency0Specified) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        // if exactOutput swap, get the absolute output amount
        if (amountUnspecified < 0) amountUnspecified = -amountUnspecified;

        uint256 feeAmount = mulWadDown(uint256(int256(amountUnspecified)), HOOK_FEE);

        // mint ERC6909 as it's cheaper than ERC20 transfer
        poolManager.mint(address(this), CurrencyLibrary.toId(currencyUnspecified), feeAmount);

        return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
    }

    // Helper function for WAD math (assuming 18 decimals)
    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / 1e18;
    }
}