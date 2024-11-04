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
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {console} from "forge-std/console.sol";
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

    // Bonding curve params
    uint256 public constant TOTAL_SUPPLY = 10000 ether;
    uint256 public constant OWN_SUPPLY = 2000 ether;
    uint256 public constant INITIAL_PRICE = 2e15;
    uint256 public constant PRICE_SLOPE = 24e10;
    uint256 public constant PRECISION = 1 ether;

    // Mapping to keep track of NFTs owned by this contract
    mapping(address => uint256[]) public ownedNFTs;

    // Position Manager
    IPositionManager public posm;
    IPoolManager public poolm;
    IHooks constant hookContract = IHooks(address(0x0));

    // Event to log received NFTs
    event NFTReceived(address operator, address from, uint256 tokenId, bytes data);
    event PoolInitialized(address poolManager, address currency0, address currency1, uint160 sqrtPriceX96);
    event LiquidityAddedToPool(address positionManager);

    // Errors
    error InvalidAmountError();
    error NotEnoughETHtoSellTokens();

    constructor(address poolmAddress, address posmAddress)
        ERC20Capped(TOTAL_SUPPLY)
        ERC20("Bonding Curve Token", "BCT")
    {
        _mint(address(this), OWN_SUPPLY);
        posm = IPositionManager(posmAddress);
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
            PoolKey memory pool = _createUniswapPool();
            console.log("Deploying the pool...");
            //_addLiquidity(pool);
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

    function getPrice() public view returns (uint256) {
        return INITIAL_PRICE + (totalSupply() * PRICE_SLOPE) / PRECISION;
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

    function _createUniswapPool() internal returns (PoolKey memory) {
        // Currently, we are not using hooks
        PoolKey memory pool = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap((address(this))),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Deploy pool from poolManager
        IPoolManager(poolm).initialize(pool, uint160(getPrice()));

        emit PoolInitialized(address(poolm), address(Currency.unwrap(CurrencyLibrary.ADDRESS_ZERO)), address(this), uint160(getPrice()));
        
        return pool;
    }

    function _addLiquidity(PoolKey memory pool) internal {

        // We want to create a new liquidity positions, actions is needed when calling the poolm
        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION, Actions.SETTLE_PAIR);

        // Parameters to modify liquidity
        bytes[] memory params = new bytes[](2);

        // Deploy liquidity in the entire range
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(getPrice()),
            TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK),
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
            address(this).balance,
            totalSupply() // TO DO: this should be precisely equal to what we have minted
        );

        // TODO: implement hooks in this contract
        bytes memory hookData = new bytes(0);

        // Params for the liquidity additions
        params[0] = abi.encode(
            pool,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK,
            liquidity,
            address(this).balance + 1 wei,
            totalSupply() + 1 wei,
            address(this),
            hookData
        );

        params[1] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap((address(this))));

        uint256 deadline = block.timestamp + 60;

        // Approve tokens
        tokenApprovals();

        posm.modifyLiquidities(abi.encode(actions, params), deadline);

        // TO Do: better way to emit this event
        emit LiquidityAddedToPool(address(posm));
        
    }

    function tokenApprovals() internal {
        // Currency0 is alaways ETH
        // if (!currency0.isAddressZero()) {
        //    token0.approve(address(PERMIT2), type(uint256).max);
        //    PERMIT2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
        //}
        this.approve(address(poolm), type(uint256).max);
        // PERMIT2.approve(address(this), address(posm), type(uint160).max, type(uint48).max);
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
}
