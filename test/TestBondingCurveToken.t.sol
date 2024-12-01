// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

// Foundry libraries
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

// Our contracts
import {BondingCurveToken} from "../src/BondingCurveToken.sol";
import {console} from "forge-std/console.sol";
import {HookRevenues} from "../src/HookRevenues.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

// Needed for the deployment and testing:
// - PoolManager to create the pool
// - PositionManager to create the contracts
// - Router contract for the swaps
// - A developer (user) that deploy the contract and get the initial supply
// - A user that buys or sells the tokens
// TODO test with the fees, doing another swap

contract TestBondingCurveToken is Test, Deployers {
    address public DEVELOPER = 0x1B7E1b7EA98232c77f9eFc75c4a7C7ea2c4D79F1;
    BondingCurveToken public bondingCurveToken;
    uint256 public constant PRECISION = 1e18;
    HookRevenues public hook;

    event PoolInitialized(address poolManager, address currency0, address currency1, uint160 sqrtPriceX96);

    function setUp() public {
        vm.startBroadcast(DEVELOPER);
        console.log("Deploying FreshManagers and Routers");
        deployFreshManagerAndRouters();

        // Deploy the hook using a foundry cheatcode
        // the hook address must have correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        deployCodeTo("HookRevenues.sol:HookRevenues", abi.encode(manager), flags);
        hook = HookRevenues(payable(flags));

        // Deploy bonding curve token
        console.log("Deploying BondingCurveToken");
        bondingCurveToken = new BondingCurveToken(address(manager), address(modifyLiquidityRouter), address(hook));

        vm.deal(address(this), 1e12 ether);

        // deploy hook

        vm.stopBroadcast();
    }

    ///////////////////////
    /// MODIFIERS ////////
    //////////////////////

    modifier poolCreated() {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);

        uint256 amountToBuy = bondingCurveToken.TOTAL_SUPPLY() - bondingCurveToken.totalSupply() + 1 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        (bool success, ) = address(bondingCurveToken).call{value: ethAmount}(
            abi.encodeWithSignature("buy(uint256)", amountToBuy)
        );
        require(success, "Buy transaction failed in poolCreated");
        _;
    }

    function testBuy() public {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);
        uint256 initialBalance = bondingCurveToken.balanceOf(address(this));
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;
        console.log("ethAmount: %d", ethAmount);

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

        uint256 newBalance = bondingCurveToken.balanceOf(address(this));
        assertEq(newBalance, initialBalance + amountToBuy, "User's balance should increase after buying");
        assertEq(
            address(bondingCurveToken).balance,
            (price * amountToBuy) / PRECISION,
            "Contract's balance should increase after buying"
        );
    }

    function testSell() public {
        uint256 amountToSell = 50 ether;

        // First, buy some tokens to sell
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

        // uint256 initialBalance = address(this).balance; // Get initial Ether balance
        uint256 initialTokenBalance = bondingCurveToken.balanceOf(address(this)); // Get initial token balance

        bondingCurveToken.sell(amountToSell);

        // uint256 newBalance = address(this).balance;
        uint256 newTokenBalance = bondingCurveToken.balanceOf(address(this));

        //assertEq(newBalance, initialBalance + (bondingCurveToken.getPrice() * amountToSell) / PRECISION, "User's Ether balance should increase after selling");
        assertEq(
            newTokenBalance, initialTokenBalance - amountToSell, "User's token balance should decrease after selling"
        );
    }

    function testExpectRevertInvalidAmount() public {
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        vm.expectRevert(BondingCurveToken.InvalidAmountError.selector);
        bondingCurveToken.buy{value: ethAmount - 1}(amountToBuy);
    }

    function testExpectRevertNotEnoughETHtoSellTokens() public {
        // First, buy some tokens to sell
        uint256 amountToBuy = 100 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        // Calculate price and send enough ETH to buy tokens
        (bool success,) =
            address(bondingCurveToken).call{value: ethAmount}(abi.encodeWithSignature("buy(uint256)", amountToBuy));
        require(success, "Buy transaction failed");

        vm.expectRevert(BondingCurveToken.NotEnoughETHtoSellTokens.selector);
        bondingCurveToken.sell(amountToBuy + 50 ether);
    }

    function testCreateUniswapPool() public {
        uint256 initialEthBalance = address(this).balance;
        console.log("Initial ETH balance: %d", initialEthBalance);

        // Buy enough tokens to trigger the creation of the Uniswap pool
        uint256 amountToBuy = bondingCurveToken.TOTAL_SUPPLY() - bondingCurveToken.totalSupply() + 1 ether;
        uint256 price = bondingCurveToken.getBuyQuote(amountToBuy);
        uint256 ethAmount = (price * amountToBuy) / PRECISION;

        console.log("ETH needed to buy enough tokens for pool creation: %d", ethAmount);

        // Send enough ETH to buy the remaining tokens
        // Set up expectations for PoolInitialized event
        // vm.expectEmit(true, true, true, true); // Setting all fields to true for full match
        // uint160 initialPriceCurve =
        // uint160(bondingCurveToken.getPriceAtSupply(bondingCurveToken.TOTAL_SUPPLY()) * (2 ^ 96));
        // emit PoolInitialized(address(manager), address(0), address(bondingCurveToken), uint160(initialPriceCurve)); // Expected event parameters

        (bool success, ) = address(bondingCurveToken).call{value: ethAmount}(
            abi.encodeWithSignature("buy(uint256)", amountToBuy)
        );
        require(success, "Buy transaction failed in createUniswapPool");

        // Check that the supply is exactly the total supply
        assertEq(
            bondingCurveToken.totalSupply(),
            bondingCurveToken.TOTAL_SUPPLY(),
            "Total supply should be equal to TOTAL_SUPPLY"
        );
    }

    function testRevAccrualAfterSwap() public poolCreated {
        // Swap some ETH for the bonding curve token, using the uniswap pool
        // Get initial hook balance
        // ETh and token balance of hook before swap
        uint256 hookEthBalanceBefore = address(hook).balance;
        uint256 hookTokenBalanceBefore = bondingCurveToken.balanceOf(address(hook));

        PoolKey memory pool = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap((address(bondingCurveToken))),
            fee: bondingCurveToken.FEE(),
            tickSpacing: bondingCurveToken.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });

        // slippage tolerance to allow for unlimited price impact
        uint160 MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
        uint160 MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT // unlimited impact
        });

        // in v4, users have the option to receieve native ERC20s or wrapped ERC6909 tokens
        // here, we'll take the ERC20s
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap{value: 1 ether}(pool, params, testSettings, new bytes(0));

        // Verify swap happened by checking token balance increased
        assertGt(bondingCurveToken.balanceOf(address(this)), 0, "Should have received tokens from swap");

        // Verify hook collected fees
        uint256 hookTokenBalanceAfter = bondingCurveToken.balanceOf(address(hook));
        uint256 hookEthBalanceAfter = address(hook).balance;

        // assertGt(hookTokenBalanceAfter, hookTokenBalanceBefore, "Hook should have collected fees");
        assertGt(hookTokenBalanceAfter, hookTokenBalanceBefore, "Hook should have collected fees");
    }
}
