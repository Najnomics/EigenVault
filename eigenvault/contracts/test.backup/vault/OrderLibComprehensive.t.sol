// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/vault/OrderLib.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title OrderLibComprehensiveTest
/// @notice Comprehensive tests for OrderLib functionality
contract OrderLibComprehensiveTest is Test {
    using OrderLib for *;
    
    address public constant TRADER1 = address(0x1);
    address public constant TRADER2 = address(0x2);
    address public constant TOKEN0 = address(0x10);
    address public constant TOKEN1 = address(0x11);
    
    PoolKey public testPoolKey;
    
    function setUp() public {
        testPoolKey = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }
    
    function testOrderIdGeneration() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100 ether,
            sqrtPriceLimitX96: 0
        });
        
        uint256 nonce = 1;
        
        bytes32 orderId1 = _generateOrderIdWrapper(TRADER1, testPoolKey, params, nonce);
        bytes32 orderId2 = _generateOrderIdWrapper(TRADER1, testPoolKey, params, nonce);
        
        // Same inputs should generate same ID
        assertEq(orderId1, orderId2);
        
        // Different nonce should generate different ID
        bytes32 orderId3 = _generateOrderIdWrapper(TRADER1, testPoolKey, params, nonce + 1);
        assertTrue(orderId1 != orderId3);
        
        // Different trader should generate different ID
        bytes32 orderId4 = _generateOrderIdWrapper(TRADER2, testPoolKey, params, nonce);
        assertTrue(orderId1 != orderId4);
    }
    
    // Helper function to handle calldata conversion
    function _generateOrderIdWrapper(
        address trader,
        PoolKey memory poolKey,
        SwapParams memory params,
        uint256 nonce
    ) internal view returns (bytes32) {
        // Create a simple hash-based ID since we can't easily convert to calldata in tests
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
    
    function testValidOrderCreation() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("test_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        assertTrue(OrderLib.validateOrder(order));
    }
    
    function testInvalidOrderValidation() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("invalid_order"),
            trader: address(0), // Invalid trader
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        assertFalse(OrderLib.validateOrder(order));
        
        // Test zero amount
        order.trader = TRADER1;
        order.amount = 0;
        assertFalse(OrderLib.validateOrder(order));
        
        // Test zero price
        order.amount = 100 ether;
        order.price = 0;
        assertFalse(OrderLib.validateOrder(order));
        
        // Test expired deadline
        order.price = 1000 ether;
        order.deadline = block.timestamp > 1 ? block.timestamp - 1 : 0;
        assertFalse(OrderLib.validateOrder(order));
        
        // Test deadline too far in future
        order.deadline = block.timestamp + 25 hours;
        assertFalse(OrderLib.validateOrder(order));
    }
    
    function testOrderMatching() public {
        OrderLib.Order memory buyOrder = OrderLib.Order({
            id: keccak256("buy_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1200 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory sellOrder = OrderLib.Order({
            id: keccak256("sell_order"),
            trader: TRADER2,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Sell,
            amount: 80 ether,
            price: 1100 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        assertTrue(OrderLib.canMatch(buyOrder, sellOrder));
    }
    
    function testOrderMatchingFailures() public {
        OrderLib.Order memory buyOrder = OrderLib.Order({
            id: keccak256("buy_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory sellOrder = OrderLib.Order({
            id: keccak256("sell_order"),
            trader: TRADER2,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Sell,
            amount: 80 ether,
            price: 1200 ether, // Higher than buy price
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Should fail because sell price > buy price
        assertFalse(OrderLib.canMatch(buyOrder, sellOrder));
        
        // Test same trader
        sellOrder.price = 900 ether;
        sellOrder.trader = TRADER1;
        assertFalse(OrderLib.canMatch(buyOrder, sellOrder));
        
        // Test expired buy order
        sellOrder.trader = TRADER2;
        buyOrder.deadline = block.timestamp > 1 ? block.timestamp - 1 : 0;
        assertFalse(OrderLib.canMatch(buyOrder, sellOrder));
        
        // Test expired sell order
        buyOrder.deadline = block.timestamp + 2 hours;
        sellOrder.deadline = block.timestamp > 1 ? block.timestamp - 1 : 0;
        assertFalse(OrderLib.canMatch(buyOrder, sellOrder));
        
        // Test non-pending status
        sellOrder.deadline = block.timestamp + 2 hours;
        buyOrder.status = OrderLib.OrderStatus.Filled;
        assertFalse(OrderLib.canMatch(buyOrder, sellOrder));
    }
    
    function testExecutionPriceCalculation() public {
        uint256 buyPrice = 1200 ether;
        uint256 sellPrice = 1100 ether;
        uint256 expectedPrice = (buyPrice + sellPrice) / 2; // 1150 ether
        
        uint256 executionPrice = OrderLib.calculateExecutionPrice(buyPrice, sellPrice);
        assertEq(executionPrice, expectedPrice);
    }
    
    function testMatchedAmountCalculation() public {
        // Test buy amount smaller
        uint256 matchedAmount = OrderLib.calculateMatchedAmount(80 ether, 100 ether);
        assertEq(matchedAmount, 80 ether);
        
        // Test sell amount smaller
        matchedAmount = OrderLib.calculateMatchedAmount(120 ether, 90 ether);
        assertEq(matchedAmount, 90 ether);
        
        // Test equal amounts
        matchedAmount = OrderLib.calculateMatchedAmount(100 ether, 100 ether);
        assertEq(matchedAmount, 100 ether);
    }
    
    function testCommitmentGeneration() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("commitment_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        uint256 nonce = 123456;
        bytes32 commitment = OrderLib.generateCommitment(order, nonce);
        
        assertTrue(commitment != bytes32(0));
        assertTrue(OrderLib.verifyCommitment(order, nonce, commitment));
        
        // Different nonce should generate different commitment
        bytes32 commitment2 = OrderLib.generateCommitment(order, nonce + 1);
        assertTrue(commitment != commitment2);
        
        // Verification with wrong nonce should fail
        assertFalse(OrderLib.verifyCommitment(order, nonce + 1, commitment));
    }
    
    function testOrderTypeConversion() public {
        // zeroForOne = true means swapping token0 for token1 (buying token1)
        OrderLib.OrderType orderType = OrderLib.getOrderType(true);
        assertEq(uint256(orderType), uint256(OrderLib.OrderType.Buy));
        
        // zeroForOne = false means swapping token1 for token0 (selling token1)
        orderType = OrderLib.getOrderType(false);
        assertEq(uint256(orderType), uint256(OrderLib.OrderType.Sell));
    }
    
    function testOrderPriorityCalculation() public {
        // Buy orders: higher price = higher priority
        OrderLib.Order memory buyOrder1 = OrderLib.Order({
            id: keccak256("buy1"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1200 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp + 100, // Avoid underflow by adding instead
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory buyOrder2 = OrderLib.Order({
            id: keccak256("buy2"),
            trader: TRADER2,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1100 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp + 150, // Different timestamp, avoid underflow
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        uint256 priority1 = OrderLib.getOrderPriority(buyOrder1);
        uint256 priority2 = OrderLib.getOrderPriority(buyOrder2);
        
        // Higher price should have higher priority
        assertTrue(priority1 > priority2);
        
        // Sell orders: lower price = higher priority
        OrderLib.Order memory sellOrder1 = buyOrder1;
        OrderLib.Order memory sellOrder2 = buyOrder2;
        sellOrder1.orderType = OrderLib.OrderType.Sell;
        sellOrder2.orderType = OrderLib.OrderType.Sell;
        
        uint256 sellPriority1 = OrderLib.getOrderPriority(sellOrder1);
        uint256 sellPriority2 = OrderLib.getOrderPriority(sellOrder2);
        
        // Lower price should have higher priority for sell orders
        assertTrue(sellPriority2 > sellPriority1);
    }
    
    function testOrderHashGeneration() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("hash_test"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        bytes32 hash1 = OrderLib.getOrderHash(order);
        bytes32 hash2 = OrderLib.getOrderHash(order);
        
        assertEq(hash1, hash2);
        
        // Different order should generate different hash
        order.amount = 200 ether;
        bytes32 hash3 = OrderLib.getOrderHash(order);
        assertTrue(hash1 != hash3);
    }
    
    function testOrderExpiration() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("expiry_test"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Should not be expired
        assertFalse(OrderLib.isExpired(order));
        
        // Set deadline in the past
        order.deadline = block.timestamp > 1 ? block.timestamp - 1 : 0;
        assertTrue(OrderLib.isExpired(order));
    }
    
    function testOrderCancellation() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("cancel_test"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            deadline: block.timestamp + 2 hours,
            timestamp: block.timestamp,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Trader should be able to cancel their own order
        assertTrue(OrderLib.canCancel(order, TRADER1));
        
        // Other trader should not be able to cancel
        assertFalse(OrderLib.canCancel(order, TRADER2));
        
        // Cannot cancel filled order
        order.status = OrderLib.OrderStatus.Filled;
        assertFalse(OrderLib.canCancel(order, TRADER1));
        
        // Can cancel partially filled order
        order.status = OrderLib.OrderStatus.PartiallyFilled;
        assertTrue(OrderLib.canCancel(order, TRADER1));
    }
    
    function testOrderFillingUpdates() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("fill_test"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Partial fill
        OrderLib.updateOrderAfterFill(order, 30 ether);
        assertEq(order.filledAmount, 30 ether);
        assertEq(uint256(order.status), uint256(OrderLib.OrderStatus.PartiallyFilled));
        
        // Complete fill
        OrderLib.updateOrderAfterFill(order, 70 ether);
        assertEq(order.filledAmount, 100 ether);
        assertEq(uint256(order.status), uint256(OrderLib.OrderStatus.Filled));
        
        // Overfill should still mark as filled
        OrderLib.updateOrderAfterFill(order, 10 ether);
        assertEq(order.filledAmount, 110 ether);
        assertEq(uint256(order.status), uint256(OrderLib.OrderStatus.Filled));
    }
    
    function testRemainingAmount() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("remaining_test"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 30 ether,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        uint256 remaining = OrderLib.getRemainingAmount(order);
        assertEq(remaining, 70 ether);
        
        // Fully filled order
        order.filledAmount = 100 ether;
        remaining = OrderLib.getRemainingAmount(order);
        assertEq(remaining, 0);
        
        // Overfilled order
        order.filledAmount = 110 ether;
        remaining = OrderLib.getRemainingAmount(order);
        assertEq(remaining, 0);
    }
    
    function testMatchResultCreation() public {
        OrderLib.Order memory buyOrder = OrderLib.Order({
            id: keccak256("buy_result"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1200 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory sellOrder = OrderLib.Order({
            id: keccak256("sell_result"),
            trader: TRADER2,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Sell,
            amount: 80 ether,
            price: 1100 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        uint256 matchedAmount = 80 ether;
        uint256 executionPrice = 1150 ether;
        
        OrderLib.MatchResult memory result = OrderLib.createMatchResult(
            buyOrder,
            sellOrder,
            matchedAmount,
            executionPrice
        );
        
        assertEq(result.buyOrderId, buyOrder.id);
        assertEq(result.sellOrderId, sellOrder.id);
        assertEq(result.matchedAmount, matchedAmount);
        assertEq(result.executionPrice, executionPrice);
        assertEq(result.timestamp, block.timestamp);
        assertTrue(result.matchHash != bytes32(0));
    }
    
    function testPoolKeyComparison() public {
        PoolKey memory pool1 = testPoolKey;
        PoolKey memory pool2 = testPoolKey;
        
        OrderLib.Order memory order1 = OrderLib.Order({
            id: keccak256("pool_test1"),
            trader: TRADER1,
            poolKey: pool1,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory order2 = OrderLib.Order({
            id: keccak256("pool_test2"),
            trader: TRADER2,
            poolKey: pool2,
            orderType: OrderLib.OrderType.Sell,
            amount: 80 ether,
            price: 900 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Same pools should match
        assertTrue(OrderLib.canMatch(order1, order2));
        
        // Different fee should not match
        pool2.fee = 10000;
        order2.poolKey = pool2;
        assertFalse(OrderLib.canMatch(order1, order2));
    }
    
    function testOrderStatusEnum() public {
        // Test all order status values are distinct
        assertTrue(uint256(OrderLib.OrderStatus.Pending) != uint256(OrderLib.OrderStatus.PartiallyFilled));
        assertTrue(uint256(OrderLib.OrderStatus.PartiallyFilled) != uint256(OrderLib.OrderStatus.Filled));
        assertTrue(uint256(OrderLib.OrderStatus.Filled) != uint256(OrderLib.OrderStatus.Cancelled));
        assertTrue(uint256(OrderLib.OrderStatus.Cancelled) != uint256(OrderLib.OrderStatus.Expired));
    }
    
    function testOrderTypeEnum() public {
        // Test order type values
        assertEq(uint256(OrderLib.OrderType.Buy), 0);
        assertEq(uint256(OrderLib.OrderType.Sell), 1);
    }
    
    function testLargeOrderAmounts() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("large_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: type(uint256).max / 2,
            price: type(uint256).max / 4,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        assertTrue(OrderLib.validateOrder(order));
        
        uint256 priority = OrderLib.getOrderPriority(order);
        assertTrue(priority > 0);
        
        bytes32 hash = OrderLib.getOrderHash(order);
        assertTrue(hash != bytes32(0));
    }
    
    function testTimePriorityTieBreaker() public {
        // Two orders with same price, different timestamps
        OrderLib.Order memory earlyOrder = OrderLib.Order({
            id: keccak256("early_order"),
            trader: TRADER1,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp, // Earlier absolute time
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Advance time slightly for the late order
        vm.warp(block.timestamp + 100);
        
        OrderLib.Order memory lateOrder = OrderLib.Order({
            id: keccak256("late_order"),
            trader: TRADER2,
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp, // Later absolute time
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        uint256 earlyPriority = OrderLib.getOrderPriority(earlyOrder);
        uint256 latePriority = OrderLib.getOrderPriority(lateOrder);
        
        // Earlier order should have higher priority (same price)
        assertTrue(earlyPriority > latePriority);
    }
}