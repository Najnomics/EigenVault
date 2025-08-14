// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @title OrderLib
/// @notice Library for order data structures and utilities
library OrderLib {
    /// @notice Order execution status
    enum OrderStatus {
        Pending,    // Order submitted but not processed
        Matched,    // Order matched by AVS operators
        Executed,   // Order successfully executed
        Expired,    // Order expired without execution
        Cancelled   // Order cancelled by trader
    }

    /// @notice Complete order structure
    struct Order {
        bytes32 id;
        address trader;
        PoolKey poolKey;
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        bytes32 commitment;
        uint256 deadline;
        uint256 timestamp;
        OrderStatus status;
        bytes32 matchProofHash;
        uint256 executedAmountIn;
        uint256 executedAmountOut;
    }

    /// @notice Order matching proof structure
    struct MatchProof {
        bytes32 orderId;
        bytes32 matchHash;
        uint256 executionPrice;
        uint256 amountIn;
        uint256 amountOut;
        bytes zkProof;
        bytes operatorSignatures;
        uint256 timestamp;
    }

    /// @notice Order commitment structure for privacy
    struct OrderCommitment {
        bytes32 hash;
        uint256 nonce;
        uint256 timestamp;
        address trader;
    }

    /// @notice Generate order ID from order details
    /// @param trader The trader address
    /// @param poolKey The pool key
    /// @param params The swap parameters
    /// @param nonce The unique nonce
    /// @return orderId The generated order ID
    function generateOrderId(
        address trader,
        PoolKey memory poolKey,
        IPoolManager.SwapParams memory params,
        uint256 nonce
    ) internal pure returns (bytes32 orderId) {
        return keccak256(
            abi.encodePacked(
                trader,
                poolKey.currency0,
                poolKey.currency1,
                poolKey.fee,
                poolKey.tickSpacing,
                poolKey.hooks,
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                nonce
            )
        );
    }

    /// @notice Generate order commitment hash
    /// @param order The order details
    /// @param nonce The privacy nonce
    /// @return commitment The commitment hash
    function generateCommitment(
        Order memory order,
        uint256 nonce
    ) internal pure returns (bytes32 commitment) {
        return keccak256(
            abi.encodePacked(
                order.trader,
                order.poolKey.currency0,
                order.poolKey.currency1,
                order.amountSpecified,
                order.sqrtPriceLimitX96,
                nonce,
                order.deadline
            )
        );
    }

    /// @notice Verify order commitment
    /// @param order The order details
    /// @param commitment The claimed commitment
    /// @param nonce The privacy nonce
    /// @return valid Whether the commitment is valid
    function verifyCommitment(
        Order memory order,
        bytes32 commitment,
        uint256 nonce
    ) internal pure returns (bool valid) {
        bytes32 expectedCommitment = generateCommitment(order, nonce);
        return commitment == expectedCommitment;
    }

    /// @notice Check if order is expired
    /// @param order The order to check
    /// @return expired Whether the order is expired
    function isExpired(Order memory order) internal view returns (bool expired) {
        return block.timestamp > order.deadline;
    }

    /// @notice Check if order is executable
    /// @param order The order to check
    /// @return executable Whether the order can be executed
    function isExecutable(Order memory order) internal view returns (bool executable) {
        return order.status == OrderStatus.Matched && 
               !isExpired(order) && 
               order.matchProofHash != bytes32(0);
    }

    /// @notice Get pool liquidity identifier
    /// @param poolKey The pool key
    /// @return liquidityId The liquidity identifier
    function getPoolLiquidityId(PoolKey memory poolKey) internal pure returns (bytes32 liquidityId) {
        return keccak256(
            abi.encodePacked(
                poolKey.currency0,
                poolKey.currency1,
                poolKey.fee,
                poolKey.tickSpacing
            )
        );
    }

    /// @notice Calculate order size threshold
    /// @param poolLiquidity The total pool liquidity
    /// @param thresholdBps The threshold in basis points
    /// @return threshold The calculated threshold
    function calculateThreshold(
        uint256 poolLiquidity,
        uint256 thresholdBps
    ) internal pure returns (uint256 threshold) {
        return (poolLiquidity * thresholdBps) / 10000;
    }

    /// @notice Validate order parameters
    /// @param order The order to validate
    /// @return valid Whether the order parameters are valid
    /// @return reason The reason if invalid
    function validateOrder(Order memory order) internal view returns (bool valid, string memory reason) {
        if (order.trader == address(0)) {
            return (false, "Invalid trader address");
        }
        
        if (order.amountSpecified == 0) {
            return (false, "Invalid amount specified");
        }
        
        if (order.deadline <= block.timestamp) {
            return (false, "Order already expired");
        }
        
        if (order.commitment == bytes32(0)) {
            return (false, "Invalid commitment");
        }
        
        return (true, "");
    }
}