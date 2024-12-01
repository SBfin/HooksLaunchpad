// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {FixedPointMathLib} from "@uniswap/v4-core/lib/solmate/src/utils/FixedPointMathLib.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {console} from "forge-std/console.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LiquidityOperations} from "@uniswap/v4-periphery/test/shared/LiquidityOperations.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

// BondingCurveToken contract
// The base for launching memecoins
// User can buy and sell tokens using a bonding curve
// Once a certain amount of tokens are minted, a Uniswap pool is created and liquidity is added
// The contract holds liquidity in the pool (V2 style)
// TO DO: Add trading fees to the bonding curve
// TO DO: Fee management for the pool
// TO DO: Change shape of the bonding curve

contract BondingCurveToken is ERC20Capped, IERC721Receiver {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint160;

    // Bonding curve params
    uint256 public constant TOTAL_SUPPLY = 10000 ether;
    uint256 public constant OWN_SUPPLY = 2000 ether;
    uint256 public constant INITIAL_PRICE = 2e15;
    uint256 public constant PRICE_SLOPE = 24e10;
    uint256 public constant PRECISION = 1 ether;
    int24 public constant TICK_SPACING = 60;

    // Mapping to keep track of NFTs owned by this contract
    mapping(address => uint256[]) public ownedNFTs;

    // Position Manager
    PoolModifyLiquidityTest public posm;
    IPoolManager public poolm;
    IHooks constant hookContract = IHooks(address(0x0));

    // Event to log received NFTs
    event NFTReceived(address operator, address from, uint256 tokenId, bytes data);
    event PoolInitialized(address poolManager, address currency0, address currency1, uint160 sqrtPriceX96);
    event LiquidityAddedToPool(address positionManager);

    // Errors
    error InvalidAmountError();
    error NotEnoughETHtoSellTokens();
    error NotEnoughETHtoProvideLiquidity();

    constructor(address poolmAddress, address posmAddress)
        ERC20Capped(TOTAL_SUPPLY)
        ERC20("Bonding Curve Token", "BCT")
    {
        _mint(address(this), OWN_SUPPLY);
        // posm = IPositionManager(posmAddress);
        posm = PoolModifyLiquidityTest(posmAddress);
        poolm = IPoolManager(poolmAddress);
    }

    function buy(uint256 amount) public payable {
        uint256 price = getBuyQuote(amount);
        console.log("Price: %d", price);
        console.log("Amount: %d", amount);
        console.log("Value: %d", msg.value);
        console.log("Price * amount / PRECISION: %d", (price * amount) / PRECISION);

        if (msg.value < (price * amount) / PRECISION) {
            revert InvalidAmountError();
        }

        // Computing amount
        // if amount exceeds total supply, then mint the remaining amount
        if (totalSupply() + amount > TOTAL_SUPPLY) {
            amount = TOTAL_SUPPLY - totalSupply();
            payable(msg.sender).transfer(msg.value - (price * amount) / PRECISION);
            _mint(msg.sender, amount);
            console.log("Deploying the pool...");
            PoolKey memory pool = _createUniswapPool();
            console.log("Adding liquidity to the pool...");
            _addLiquidity(pool);
        } else {
            console.log("amount: %d", amount);
            payable(msg.sender).transfer(msg.value - (price * amount) / PRECISION);
            console.log("Minting %d tokens", amount);
            _mint(msg.sender, amount);
        }
    }

    function sell(uint256 amount) public {
        console.log("Get sell price...");
        uint256 price = getSellQuote(amount);
        console.log("Sell price: %d", price);
        uint256 value = (price * amount) / PRECISION;
        console.log("Sell value: %d", value);

        if (value > address(this).balance) {
            revert NotEnoughETHtoSellTokens();
        }

        _burn(msg.sender, amount);
        payable(msg.sender).transfer(value);
    }

    // Implement onERC721Received so the contract can receive ERC721 tokens
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data)
        public
        override
        returns (bytes4)
    {
        // Store the NFT in the ownedNFTs mapping
        ownedNFTs[msg.sender].push(tokenId);

        // Emit an event for tracking purposes
        emit NFTReceived(operator, from, tokenId, data);

        // Return the selector to confirm the NFT was received
        return this.onERC721Received.selector;
    }

    //////////////////////////
    //// Internal functions //
    //////////////////////////
    function _createUniswapPool() internal returns (PoolKey memory) {
        // PriceQ
        uint160 pricePoolQ = uint160(FixedPointMathLib.sqrt(getPriceInv() * (2 ** 96)));

        // Currently, we are not using hooks
        PoolKey memory pool = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap((address(this))),
            fee: 3000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        // Deploy pool from poolManager
        IPoolManager(poolm).initialize(pool, pricePoolQ);

        emit PoolInitialized(
            address(poolm), address(Currency.unwrap(CurrencyLibrary.ADDRESS_ZERO)), address(this), pricePoolQ
        );

        return pool;
    }

    function _addLiquidity(PoolKey memory pool) internal {

        console.log("ETH balance: %d", address(this).balance);
        console.log("Token balance: %d", this.balanceOf(address(this)) );
        console.log("Price: %d", getPriceInv());
        bytes memory hookData = new bytes(0);

        uint160 pricePoolQ = uint160(FixedPointMathLib.sqrt(getPriceInv() * (2 ** 96)));
        console.log("Pool price SQRTX96: %d", pricePoolQ);
        

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            1e18,
            this.balanceOf(address(this))// TO DO: this should be precisely equal to what we have minted
        );

        (uint256 amount0Check, uint256 amount1Check) = LiquidityAmounts.getAmountsForLiquidity(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(TICK_SPACING)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(TICK_SPACING)),
            liquidityDelta
        );

        console.log("amount0Check: %d", amount0Check);
        console.log("amount1Check: %d", amount1Check);
        // check if the amount of ETH and tokens is enough to cover the liquidity
        if (amount0Check > address(this).balance || amount1Check > this.balanceOf(address(this))) {
            revert NotEnoughETHtoProvideLiquidity();
        }

        _tokenApprovals();

        posm.modifyLiquidity(
            pool,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(TICK_SPACING), TickMath.maxUsableTick(TICK_SPACING), int256(uint256(liquidityDelta)), 0
            ),
            new bytes(0)
        );
        
    }
    /*
    function _addLiquidity(PoolKey memory pool) internal {
        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = this.balanceOf(address(this));
        
        uint160 pricePoolQ = uint160(FixedPointMathLib.sqrt(getPriceInv() * (2**96)));
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            ethBalance,
            tokenBalance
        );

        (uint256 amount0Check, uint256 amount1Check) = LiquidityAmounts.getAmountsForLiquidity(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            liquidity
        );

        uint256 amount0Max = (ethBalance * 98) / 100;  // Slightly higher to account for slippage
        uint256 amount1Max = (tokenBalance * 98) / 100; // Slightly higher to account for slippage

        console.log("amount0Check: %d", amount0Check);
        console.log("amount1Check: %d", amount1Check);

        console.log("amount0Max: %d", amount0Max);
        console.log("amount1Max: %d", amount1Max);

        bytes memory hookData = new bytes(0);
        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION, Actions.SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            pool,
            TickMath.MIN_TICK + 60,
            TickMath.MAX_TICK - 3000,
            liquidity,
            amount0Max,
            amount1Max,
            address(this),
            hookData
        );

        params[1] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(this)));

        _tokenApprovals();

        uint256 deadline = block.timestamp + 60;

        posm.modifyLiquidities{value: ethBalance}(
            abi.encode(actions, params),
            deadline
        );

        emit LiquidityAddedToPool(address(posm));
    }*/

    /*

    function _addLiquidity(PoolKey memory pool) internal {
        // Print ETH balance and token balance
        console.log("ETH balance: %d", address(this).balance);
        console.log("Token balance: %d", this.balanceOf(address(this)) );
        console.log("Price: %d", getPriceInv());

        uint160 pricePoolQ = uint160(FixedPointMathLib.sqrt(getPriceInv() * (2 ** 96)));
        console.log("Pool price SQRTX96: %d", pricePoolQ);
        
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            address(this).balance - 1 wei,
            this.balanceOf(address(this)) - 1 wei// TO DO: this should be precisely equal to what we have minted
        );

        (uint256 amount0Check, uint256 amount1Check) = LiquidityAmounts.getAmountsForLiquidity(
            pricePoolQ,
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            liquidity
        );

        console.log("Liquidity: %d", liquidity);
        console.log("Amount0Check: %d", amount0Check);
        console.log("Amount1Check: %d", amount1Check);

         // slippage limits
        uint256 amount0Max = address(this).balance - 1 wei;
        uint256 amount1Max = this.balanceOf(address(this)) - 1 wei;

        bytes memory hookData = new bytes(0);

        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION, Actions.SETTLE_PAIR);
        
        bytes[] memory params = new bytes[](2);
        
        params[0] = abi.encode(pool, 
                                TickMath.MIN_TICK+1, 
                                TickMath.MAX_TICK-1, 
                                liquidity, 
                                amount0Max, 
                                amount1Max, 
                                address(this), 
                                hookData);

        params[1] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(this)));

        _tokenApprovals();
        
        uint256 deadline = block.timestamp + 60;

        posm.modifyLiquidities{value: amount0Max}(
            abi.encode(actions, params),
            deadline
        );
        
        // TO Do: better way to emit this event
        emit LiquidityAddedToPool(address(posm));

    }*/

    function _tokenApprovals() internal {
        // Currency0 is alaways ETH
        // if (!currency0.isAddressZero()) {
        //    token0.approve(address(PERMIT2), type(uint256).max);
        //    PERMIT2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
        //}
        console.log("Approving token1...");
        this.approve(address(posm), type(uint256).max);
        // PERMIT2.approve(address(this), address(posm), type(uint160).max, type(uint48).max);
    }

    //////////////////////////
    //// View functions //////
    //////////////////////////

    function getPrice() public view returns (uint256) {
        return INITIAL_PRICE + (totalSupply() * PRICE_SLOPE) / PRECISION;
    }

    function getPriceInv() public view returns (uint256) {
        return (PRECISION * PRECISION) / getPrice();
    }

    function getPriceAtSupply(uint256 supply) public view returns (uint256) {
        return INITIAL_PRICE + (supply * PRICE_SLOPE) / PRECISION;
    }

    function getBuyQuote(uint256 amount) public view returns (uint256) {
        // Average between the current price and the price after the amount is minted
        return (getPrice() + getPrice() + (PRICE_SLOPE * amount) / PRECISION) / 2;
    }

    function getSellQuote(uint256 amount) public view returns (uint256) {
        // Average between the current price and the price after the amount is minted
        return (getPrice() + (getPrice() - (PRICE_SLOPE * amount) / PRECISION)) / 2;
    }

    function getMarketCap() public view returns (uint256) {
        return totalSupply() * getPrice();
    }

}