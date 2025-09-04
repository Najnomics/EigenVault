// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title OrderLib
/// @notice Library for order data structures and utility functions
library OrderLib {
    /// @notice Order type enumeration
    enum OrderType {
        Buy,
        Sell
    }

    /// @notice Order status enumeration  
    enum OrderStatus {
        Pending,
        PartiallyFilled,
        Filled,
        Cancelled,
        Expired
    }

    /// @notice Core order structure
    struct Order {
        bytes32 id;
        address trader;
        PoolKey poolKey;
        OrderType orderType;
        uint256 amount;
        uint256 price;
        OrderStatus status;
        uint256 timestamp;
        uint256 deadline;
        uint256 filledAmount;
        bytes32 commitment;
        bytes encryptedData;
    }

    /// @notice Order matching result
    struct MatchResult {
        bytes32 buyOrderId;
        bytes32 sellOrderId;
        uint256 matchedAmount;
        uint256 executionPrice;
        uint256 timestamp;
        bytes32 matchHash;
    }

    /// @notice Order book entry
    struct OrderBookEntry {
        bytes32 orderId;
        uint256 price;
        uint256 amount;
        uint256 timestamp;
        address trader;
    }

    /// @notice Events
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed trader,
        PoolKey indexed poolKey,
        OrderType orderType,
        uint256 amount,
        uint256 price
    );

    event OrderMatched(
        bytes32 indexed buyOrderId,
        bytes32 indexed sellOrderId,
        uint256 matchedAmount,
        uint256 executionPrice
    );

    event OrderCancelled(bytes32 indexed orderId, address indexed trader);
    event OrderExpired(bytes32 indexed orderId, address indexed trader);

    /// @notice Generate a unique order ID
    /// @param trader The trader address
    /// @param poolKey The pool key
    /// @param params The swap parameters
    /// @param nonce The order nonce
    /// @return orderId The generated order ID
    function generateOrderId(
        address trader,
        PoolKey calldata poolKey,
        SwapParams calldata params,
        uint256 nonce
    ) internal view returns (bytes32 orderId) {
        return keccak256(abi.encodePacked(
            trader,
            poolKey.currency0,
            poolKey.currency1,
            poolKey.fee,
            params.zeroForOne,
            params.amountSpecified,
            nonce,
            block.timestamp
        ));
    }

    /// @notice Validate order parameters
    /// @param order The order to validate
    /// @return isValid Whether the order is valid
    function validateOrder(Order memory order) internal view returns (bool isValid) {
        return order.trader != address(0) &&
               order.amount > 0 &&
               order.price > 0 &&
               order.deadline > block.timestamp &&
               order.deadline <= block.timestamp + 24 hours; // Max 24 hour deadline
    }

    /// @notice Check if two orders can be matched
    /// @param buyOrder The buy order
    /// @param sellOrder The sell order
    /// @return canMatch Whether the orders can be matched
    function canMatch(Order memory buyOrder, Order memory sellOrder) internal view returns (bool) {
        return buyOrder.orderType == OrderType.Buy &&
               sellOrder.orderType == OrderType.Sell &&
               buyOrder.price >= sellOrder.price &&
               buyOrder.trader != sellOrder.trader &&
               buyOrder.deadline > block.timestamp &&
               sellOrder.deadline > block.timestamp &&
               buyOrder.status == OrderStatus.Pending &&
               sellOrder.status == OrderStatus.Pending &&
               _samePool(buyOrder.poolKey, sellOrder.poolKey);
    }

    /// @notice Calculate the execution price for matched orders
    /// @param buyPrice The buy order price
    /// @param sellPrice The sell order price
    /// @return executionPrice The calculated execution price
    function calculateExecutionPrice(
        uint256 buyPrice,
        uint256 sellPrice
    ) internal pure returns (uint256 executionPrice) {
        // Use midpoint pricing
        return (buyPrice + sellPrice) / 2;
    }

    /// @notice Calculate the matched amount for two orders
    /// @param buyAmount The buy order amount
    /// @param sellAmount The sell order amount
    /// @return matchedAmount The amount that can be matched
    function calculateMatchedAmount(
        uint256 buyAmount,
        uint256 sellAmount
    ) internal pure returns (uint256 matchedAmount) {
        return buyAmount < sellAmount ? buyAmount : sellAmount;
    }

    /// @notice Generate commitment hash for order privacy
    /// @param order The order data
    /// @param nonce Random nonce
    /// @return commitment The commitment hash
    function generateCommitment(
        Order memory order,
        uint256 nonce
    ) internal pure returns (bytes32 commitment) {
        return keccak256(abi.encodePacked(
            order.trader,
            order.poolKey.currency0,
            order.poolKey.currency1,
            order.amount,
            order.price,
            order.deadline,
            nonce
        ));
    }

    /// @notice Verify order commitment
    /// @param order The order data
    /// @param nonce The nonce used
    /// @param commitment The commitment to verify
    /// @return isValid Whether the commitment is valid
    function verifyCommitment(
        Order memory order,
        uint256 nonce,
        bytes32 commitment
    ) internal pure returns (bool isValid) {
        return generateCommitment(order, nonce) == commitment;
    }

    /// @notice Convert swap parameters to order type
    /// @param zeroForOne Whether swapping token0 for token1
    /// @return orderType The corresponding order type
    function getOrderType(bool zeroForOne) internal pure returns (OrderType orderType) {
        return zeroForOne ? OrderType.Buy : OrderType.Sell;
    }

    /// @notice Get order priority score for matching
    /// @param order The order
    /// @return priority The priority score (higher is better)
    function getOrderPriority(Order memory order) internal pure returns (uint256 priority) {
        // Price-time priority: better price gets higher priority, earlier orders break ties
        uint256 priceScore = order.orderType == OrderType.Buy ? order.price : (type(uint256).max - order.price);
        uint256 timeScore = type(uint256).max - order.timestamp;
        return priceScore + (timeScore / 1000000); // Time as tiebreaker
    }

    /// @notice Calculate order hash for matching
    /// @param order The order
    /// @return hash The order hash
    function getOrderHash(Order memory order) internal pure returns (bytes32 hash) {
        return keccak256(abi.encode(
            order.id,
            order.trader,
            order.poolKey,
            order.orderType,
            order.amount,
            order.price,
            order.timestamp
        ));
    }

    /// @notice Check if order has expired
    /// @param order The order to check
    /// @return expired Whether the order has expired
    function isExpired(Order memory order) internal view returns (bool expired) {
        return block.timestamp > order.deadline;
    }

    /// @notice Check if order can be cancelled
    /// @param order The order to check
    /// @param caller The address attempting to cancel
    /// @return canCancel Whether the order can be cancelled
    function canCancel(Order memory order, address caller) internal pure returns (bool) {
        return order.trader == caller && 
               (order.status == OrderStatus.Pending || order.status == OrderStatus.PartiallyFilled);
    }

    /// @notice Update order status after partial fill
    /// @param order The order to update
    /// @param filledAmount The amount filled
    function updateOrderAfterFill(Order memory order, uint256 filledAmount) internal pure {
        order.filledAmount += filledAmount;
        if (order.filledAmount >= order.amount) {
            order.status = OrderStatus.Filled;
        } else {
            order.status = OrderStatus.PartiallyFilled;
        }
    }

    /// @notice Get remaining order amount
    /// @param order The order
    /// @return remaining The remaining amount to be filled
    function getRemainingAmount(Order memory order) internal pure returns (uint256 remaining) {
        return order.amount > order.filledAmount ? order.amount - order.filledAmount : 0;
    }

    /// @notice Create match result from two orders
    /// @param buyOrder The buy order
    /// @param sellOrder The sell order
    /// @param matchedAmount The matched amount
    /// @param executionPrice The execution price
    /// @return result The match result
    function createMatchResult(
        Order memory buyOrder,
        Order memory sellOrder,
        uint256 matchedAmount,
        uint256 executionPrice
    ) internal view returns (MatchResult memory result) {
        bytes32 matchHash = keccak256(abi.encodePacked(
            buyOrder.id,
            sellOrder.id,
            matchedAmount,
            executionPrice,
            block.timestamp
        ));

        return MatchResult({
            buyOrderId: buyOrder.id,
            sellOrderId: sellOrder.id,
            matchedAmount: matchedAmount,
            executionPrice: executionPrice,
            timestamp: block.timestamp,
            matchHash: matchHash
        });
    }

    /// @notice Internal function to check if two pool keys represent the same pool
    function _samePool(PoolKey memory pool1, PoolKey memory pool2) private pure returns (bool) {
        return pool1.currency0 == pool2.currency0 &&
               pool1.currency1 == pool2.currency1 &&
               pool1.fee == pool2.fee &&
               pool1.tickSpacing == pool2.tickSpacing &&
               pool1.hooks == pool2.hooks;
    }
}