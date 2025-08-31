// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title OrderMatchingLib
/// @notice Advanced order matching library for EigenVault with ZK proof integration
library OrderMatchingLib {
    /// @notice Order matching result
    struct MatchingResult {
        bytes32 matchId;
        bytes32 buyOrderId;
        bytes32 sellOrderId;
        uint256 matchedAmount;
        uint256 executionPrice;
        uint256 timestamp;
        address[] operators;
        bytes32 consensusHash;
        bool executed;
    }

    /// @notice Order book entry
    struct OrderBookEntry {
        bytes32 orderId;
        uint256 price;
        uint256 amount;
        uint256 timestamp;
        address trader;
        bool isActive;
    }

    /// @notice Order book for a specific pool
    struct OrderBook {
        bytes32 poolId;
        OrderBookEntry[] buyOrders;  // Sorted by price (highest first)
        OrderBookEntry[] sellOrders; // Sorted by price (lowest first)
        uint256 totalBuyVolume;
        uint256 totalSellVolume;
        uint256 lastMatchTime;
    }

    /// @notice Match two orders efficiently
    /// @param buyOrder The buy order
    /// @param sellOrder The sell order
    /// @param poolKey The pool key
    /// @return result The matching result
    /// @return canMatch Whether the orders can be matched
    function matchOrders(
        OrderBookEntry memory buyOrder,
        OrderBookEntry memory sellOrder,
        PoolKey memory poolKey
    ) internal pure returns (MatchingResult memory result, bool canMatch) {
        // Check if orders can be matched
        if (!_canOrdersMatch(buyOrder, sellOrder)) {
            return (result, false);
        }

        // Calculate execution price (midpoint pricing)
        uint256 executionPrice = _calculateExecutionPrice(buyOrder.price, sellOrder.price);
        
        // Calculate matched amount
        uint256 matchedAmount = _calculateMatchedAmount(buyOrder.amount, sellOrder.amount);
        
        // Generate match ID
        bytes32 matchId = keccak256(abi.encodePacked(
            buyOrder.orderId,
            sellOrder.orderId,
            executionPrice,
            matchedAmount,
            block.timestamp
        ));

        // Create consensus hash for operator validation
        bytes32 consensusHash = keccak256(abi.encodePacked(
            matchId,
            executionPrice,
            matchedAmount,
            poolKey.currency0,
            poolKey.currency1
        ));

        result = MatchingResult({
            matchId: matchId,
            buyOrderId: buyOrder.orderId,
            sellOrderId: sellOrder.orderId,
            matchedAmount: matchedAmount,
            executionPrice: executionPrice,
            timestamp: block.timestamp,
            operators: new address[](0), // Will be populated by AVS
            consensusHash: consensusHash,
            executed: false
        });

        return (result, true);
    }

    /// @notice Check if two orders can be matched
    /// @param buyOrder The buy order
    /// @param sellOrder The sell order
    /// @return canMatch Whether the orders can be matched
    function _canOrdersMatch(
        OrderBookEntry memory buyOrder,
        OrderBookEntry memory sellOrder
    ) internal pure returns (bool canMatch) {
        // Basic validation
        if (!buyOrder.isActive || !sellOrder.isActive) {
            return false;
        }

        // Check if buy price >= sell price
        if (buyOrder.price < sellOrder.price) {
            return false;
        }

        // Check if orders are from different traders
        if (buyOrder.trader == sellOrder.trader) {
            return false;
        }

        // Check if orders have sufficient amounts
        if (buyOrder.amount == 0 || sellOrder.amount == 0) {
            return false;
        }

        return true;
    }

    /// @notice Calculate execution price using midpoint pricing
    /// @param buyPrice The buy order price
    /// @param sellPrice The sell order price
    /// @return executionPrice The calculated execution price
    function _calculateExecutionPrice(
        uint256 buyPrice,
        uint256 sellPrice
    ) internal pure returns (uint256 executionPrice) {
        // Use midpoint pricing for fair execution
        return (buyPrice + sellPrice) / 2;
    }

    /// @notice Calculate the amount that can be matched between two orders
    /// @param buyAmount The buy order amount
    /// @param sellAmount The sell order amount
    /// @return matchedAmount The amount that can be matched
    function _calculateMatchedAmount(
        uint256 buyAmount,
        uint256 sellAmount
    ) internal pure returns (uint256 matchedAmount) {
        // Match the smaller of the two amounts
        return buyAmount < sellAmount ? buyAmount : sellAmount;
    }

    /// @notice Insert order into order book maintaining price-time priority
    /// @param orderBook The order book to insert into
    /// @param order The order to insert
    /// @param isBuy Whether this is a buy order
    function insertOrder(
        OrderBook storage orderBook,
        OrderBookEntry memory order,
        bool isBuy
    ) internal {
        if (isBuy) {
            _insertBuyOrder(orderBook, order);
            orderBook.totalBuyVolume += order.amount;
        } else {
            _insertSellOrder(orderBook, order);
            orderBook.totalSellVolume += order.amount;
        }
    }

    /// @notice Insert buy order maintaining price-time priority
    /// @param orderBook The order book
    /// @param order The order to insert
    function _insertBuyOrder(
        OrderBook storage orderBook,
        OrderBookEntry memory order
    ) internal {
        // Find insertion point (highest price first, then earliest timestamp)
        uint256 insertIndex = orderBook.buyOrders.length;
        
        for (uint256 i = 0; i < orderBook.buyOrders.length; i++) {
            if (order.price > orderBook.buyOrders[i].price || 
                (order.price == orderBook.buyOrders[i].price && order.timestamp < orderBook.buyOrders[i].timestamp)) {
                insertIndex = i;
                break;
            }
        }
        
        // Insert order at the correct position
        orderBook.buyOrders.push(order);
        if (insertIndex < orderBook.buyOrders.length - 1) {
            // Shift orders to make room
            for (uint256 i = orderBook.buyOrders.length - 1; i > insertIndex; i--) {
                orderBook.buyOrders[i] = orderBook.buyOrders[i - 1];
            }
            orderBook.buyOrders[insertIndex] = order;
        }
    }

    /// @notice Insert sell order maintaining price-time priority
    /// @param orderBook The order book
    /// @param order The order to insert
    function _insertSellOrder(
        OrderBook storage orderBook,
        OrderBookEntry memory order
    ) internal {
        // Find insertion point (lowest price first, then earliest timestamp)
        uint256 insertIndex = orderBook.sellOrders.length;
        
        for (uint256 i = 0; i < orderBook.sellOrders.length; i++) {
            if (order.price < orderBook.sellOrders[i].price || 
                (order.price == orderBook.sellOrders[i].price && order.timestamp < orderBook.sellOrders[i].timestamp)) {
                insertIndex = i;
                break;
            }
        }
        
        // Insert order at the correct position
        orderBook.sellOrders.push(order);
        if (insertIndex < orderBook.sellOrders.length - 1) {
            // Shift orders to make room
            for (uint256 i = orderBook.sellOrders.length - 1; i > insertIndex; i--) {
                orderBook.sellOrders[i] = orderBook.sellOrders[i - 1];
            }
            orderBook.sellOrders[insertIndex] = order;
        }
    }

    /// @notice Remove order from order book
    /// @param orderBook The order book
    /// @param orderId The order ID to remove
    /// @param isBuy Whether this is a buy order
    function removeOrder(
        OrderBook storage orderBook,
        bytes32 orderId,
        bool isBuy
    ) internal returns (bool removed) {
        if (isBuy) {
            return _removeBuyOrder(orderBook, orderId);
        } else {
            return _removeSellOrder(orderBook, orderId);
        }
    }

    /// @notice Remove buy order from order book
    /// @param orderBook The order book
    /// @param orderId The order ID to remove
    /// @return removed Whether the order was removed
    function _removeBuyOrder(
        OrderBook storage orderBook,
        bytes32 orderId
    ) internal returns (bool removed) {
        for (uint256 i = 0; i < orderBook.buyOrders.length; i++) {
            if (orderBook.buyOrders[i].orderId == orderId) {
                // Update total volume
                orderBook.totalBuyVolume -= orderBook.buyOrders[i].amount;
                
                // Remove order by shifting array
                for (uint256 j = i; j < orderBook.buyOrders.length - 1; j++) {
                    orderBook.buyOrders[j] = orderBook.buyOrders[j + 1];
                }
                orderBook.buyOrders.pop();
                return true;
            }
        }
        return false;
    }

    /// @notice Remove sell order from order book
    /// @param orderBook The order book
    /// @param orderId The order ID to remove
    /// @return removed Whether the order was removed
    function _removeSellOrder(
        OrderBook storage orderBook,
        bytes32 orderId
    ) internal returns (bool removed) {
        for (uint256 i = 0; i < orderBook.sellOrders.length; i++) {
            if (orderBook.sellOrders[i].orderId == orderId) {
                // Update total volume
                orderBook.totalSellVolume -= orderBook.sellOrders[i].amount;
                
                // Remove order by shifting array
                for (uint256 j = i; j < orderBook.sellOrders.length - 1; j++) {
                    orderBook.sellOrders[j] = orderBook.sellOrders[j + 1];
                }
                orderBook.sellOrders.pop();
                return true;
            }
        }
        return false;
    }

    /// @notice Get best bid and ask prices
    /// @param orderBook The order book
    /// @return bestBid The best bid price
    /// @return bestAsk The best ask price
    function getBestPrices(OrderBook storage orderBook) internal view returns (uint256 bestBid, uint256 bestAsk) {
        if (orderBook.buyOrders.length > 0) {
            bestBid = orderBook.buyOrders[0].price;
        }
        if (orderBook.sellOrders.length > 0) {
            bestAsk = orderBook.sellOrders[0].price;
        }
    }

    /// @notice Calculate spread between best bid and ask
    /// @param orderBook The order book
    /// @return spread The spread in basis points
    function calculateSpread(OrderBook storage orderBook) internal view returns (uint256 spread) {
        (uint256 bestBid, uint256 bestAsk) = getBestPrices(orderBook);
        
        if (bestBid > 0 && bestAsk > 0 && bestAsk > bestBid) {
            spread = ((bestAsk - bestBid) * 10000) / bestBid;
        }
    }

    /// @notice Get order book depth at specific price levels
    /// @param orderBook The order book
    /// @param priceLevels The number of price levels to analyze
    /// @return buyDepth Array of buy order volumes at each price level
    /// @return sellDepth Array of sell order volumes at each price level
    function getOrderBookDepth(
        OrderBook storage orderBook,
        uint256 priceLevels
    ) internal view returns (uint256[] memory buyDepth, uint256[] memory sellDepth) {
        buyDepth = new uint256[](priceLevels);
        sellDepth = new uint256[](priceLevels);
        
        // Aggregate buy orders by price level
        for (uint256 i = 0; i < orderBook.buyOrders.length && i < priceLevels; i++) {
            buyDepth[i] = orderBook.buyOrders[i].amount;
        }
        
        // Aggregate sell orders by price level
        for (uint256 i = 0; i < orderBook.sellOrders.length && i < priceLevels; i++) {
            sellDepth[i] = orderBook.sellOrders[i].amount;
        }
    }
} 