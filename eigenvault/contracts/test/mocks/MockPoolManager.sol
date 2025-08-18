// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockPoolManager
/// @notice Mock implementation of Uniswap v4 PoolManager for testing
contract MockPoolManager {
    mapping(bytes32 => bool) public poolExists;
    mapping(bytes32 => uint256) public poolLiquidity;
    
    event Swap(
        bytes32 indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    
    function initialize(bytes32 poolId, uint160 sqrtPriceX96) external {
        poolExists[poolId] = true;
        poolLiquidity[poolId] = 1000000e18; // 1M tokens liquidity
    }
    
    function swap(
        bytes32 poolId,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata hookData
    ) external returns (int128 amount0, int128 amount1) {
        require(poolExists[poolId], "Pool does not exist");
        
        // Mock swap logic
        if (zeroForOne) {
            amount0 = int128(amountSpecified);
            amount1 = -int128(int256(uint256(amountSpecified) * 1800)); // Mock 1800 price
        } else {
            amount0 = -int128(int256(uint256(-amountSpecified) / 1800));
            amount1 = int128(amountSpecified);
        }
        
        emit Swap(poolId, recipient, amount0, amount1, sqrtPriceLimitX96, 1000000, 0);
        
        return (amount0, amount1);
    }
    
    function getSlot0(bytes32 poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 protocolFee,
        uint24 swapFee
    ) {
        require(poolExists[poolId], "Pool does not exist");
        return (1771595571142957166656628962687, 0, 0, 3000);
    }
}