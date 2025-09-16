// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title MockPoolManager
/// @notice Mock implementation of Uniswap v4 PoolManager for testing
contract MockPoolManager {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    mapping(PoolId => bool) public poolExists;
    mapping(PoolId => uint128) public poolLiquidity;
    mapping(PoolId => uint160) public poolSqrtPriceX96;
    mapping(PoolId => int24) public poolTick;
    bool public shouldFailSwap;
    
    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    
    constructor() {
        // Initialize some default pools
        _initializeDefaults();
    }
    
    function _initializeDefaults() internal {
        // Set up some default pool state for testing
        PoolKey memory defaultKey = PoolKey({
            currency0: Currency.wrap(address(0x111)),
            currency1: Currency.wrap(address(0x222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        PoolId poolId = defaultKey.toId();
        poolExists[poolId] = true;
        poolLiquidity[poolId] = 1000000e18; // 1M liquidity
        poolSqrtPriceX96[poolId] = uint160(79228162514264337593543950336); // Price = 1
        poolTick[poolId] = 0;
    }
    
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external {
        PoolId poolId = key.toId();
        poolExists[poolId] = true;
        poolLiquidity[poolId] = 1000000e18; // 1M tokens liquidity
        poolSqrtPriceX96[poolId] = sqrtPriceX96;
        poolTick[poolId] = 0;
    }
    
    function setShouldFailSwap(bool _shouldFail) external {
        shouldFailSwap = _shouldFail;
    }
    
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata /* hookData */
    ) external returns (BalanceDelta delta) {
        PoolId poolId = key.toId();
        require(poolExists[poolId], "Pool does not exist");
        require(!shouldFailSwap, "Swap execution failed");
        
        // Mock swap logic
        int128 amount0;
        int128 amount1;
        
        if (params.zeroForOne) {
            amount0 = int128(params.amountSpecified);
            amount1 = -int128(int256(uint256(params.amountSpecified) * 1800 / 1e18)); // Mock 1800 price
        } else {
            amount0 = -int128(int256(uint256(-params.amountSpecified) / 1800 * 1e18));
            amount1 = int128(params.amountSpecified);
        }
        
        // Create BalanceDelta - for mock purposes, just create a simple representation
        int256 packed = (int256(amount0) << 128) | int256(uint256(uint128(amount1)));
        delta = BalanceDelta.wrap(packed);
        
        emit Swap(poolId, msg.sender, amount0, amount1, poolSqrtPriceX96[poolId], poolLiquidity[poolId], poolTick[poolId]);
        
        return delta;
    }
    
    // Function for StateLibrary to call - this is the correct signature
    function getSlot0(PoolId poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 swapFee) {
        if (!poolExists[poolId]) {
            // Return default values for non-existent pools
            return (79228162514264337593543950336, 0, 0, 3000); // Price = 1, tick = 0, fees = 0.3%
        }
        
        sqrtPriceX96 = poolSqrtPriceX96[poolId];
        tick = poolTick[poolId];
        protocolFee = 0;
        swapFee = 3000; // 0.3%
    }
    
    // Additional methods for comprehensive testing
    function setPoolState(PoolKey memory key, uint160 sqrtPriceX96, int24 tick, uint128 liquidity) external {
        PoolId poolId = key.toId();
        poolExists[poolId] = true;
        poolSqrtPriceX96[poolId] = sqrtPriceX96;
        poolTick[poolId] = tick;
        poolLiquidity[poolId] = liquidity;
    }
    
    function getPoolLiquidity(PoolId poolId) external view returns (uint128) {
        return poolLiquidity[poolId];
    }
}