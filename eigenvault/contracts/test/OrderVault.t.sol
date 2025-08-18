// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/OrderVault.sol";
import "../src/interfaces/IOrderVault.sol";
import "./utils/EigenVaultTestBase.sol";

/// @title OrderVault Test Suite
/// @notice Comprehensive test suite for OrderVault contract
contract OrderVaultTest is EigenVaultTestBase {
    OrderVault public orderVault;
    
    address public hook1 = address(0x101);
    address public hook2 = address(0x102);

    bytes32 public testOrderId1 = keccak256("order1");
    bytes32 public testOrderId2 = keccak256("order2");
    bytes public testEncryptedOrder = "encrypted_order_data_123";

    function setUp() public override {
        orderVault = new OrderVault();
        
        // Authorize hooks and operators
        orderVault.authorizeHook(hook1);
        orderVault.authorizeOperator(operator1);
    }

    /// @notice Test contract deployment and initialization
    function testDeployment() public {
        assertEq(orderVault.owner(), address(this));
        assertEq(orderVault.totalOrdersStored(), 0);
        assertEq(orderVault.totalOrdersRetrieved(), 0);
        assertEq(orderVault.totalOrdersExpired(), 0);
        assertEq(orderVault.getActiveOrderCount(), 0);
    }

    /// @notice Test order storage by authorized hook
    function testStoreOrder() public {
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.expectEmit(true, true, false, false);
        emit IOrderVault.OrderStored(testOrderId1, trader1, testEncryptedOrder, block.timestamp);
        
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, deadline);
        
        assertEq(orderVault.totalOrdersStored(), 1);
        assertEq(orderVault.getActiveOrderCount(), 1);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertEq(order.orderId, testOrderId1);
        assertEq(order.trader, trader1);
        assertEq(order.encryptedOrder, testEncryptedOrder);
        assertEq(order.deadline, deadline);
        assertFalse(order.retrieved);
        assertFalse(order.expired);
    }

    /// @notice Test order storage by unauthorized hook
    function testStoreOrderUnauthorized() public {
        vm.prank(hook2); // Unauthorized hook
        vm.expectRevert("Hook not authorized");
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
    }

    /// @notice Test order storage with invalid parameters
    function testStoreOrderInvalidParams() public {
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.startPrank(hook1);
        
        // Invalid order ID
        vm.expectRevert("Invalid order ID");
        orderVault.storeOrder(bytes32(0), trader1, testEncryptedOrder, deadline);
        
        // Invalid trader
        vm.expectRevert("Invalid trader address");
        orderVault.storeOrder(testOrderId1, address(0), testEncryptedOrder, deadline);
        
        // Empty encrypted order
        vm.expectRevert("Empty encrypted order");
        orderVault.storeOrder(testOrderId1, trader1, "", deadline);
        
        // Invalid deadline (too soon)
        vm.expectRevert("Invalid deadline");
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 minutes);
        
        // Invalid deadline (too far)
        vm.expectRevert("Invalid deadline");
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 25 hours);
        
        vm.stopPrank();
    }

    /// @notice Test duplicate order storage
    function testStoreOrderDuplicate() public {
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.startPrank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, deadline);
        
        vm.expectRevert("Order already exists");
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, deadline);
        vm.stopPrank();
    }

    /// @notice Test order retrieval by authorized operator
    function testRetrieveOrder() public {
        // Store order first
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.expectEmit(true, true, false, false);
        emit IOrderVault.OrderRetrieved(testOrderId1, operator1, block.timestamp);
        
        vm.prank(operator1);
        bytes memory retrieved = orderVault.retrieveOrder(testOrderId1);
        
        assertEq(retrieved, testEncryptedOrder);
        assertEq(orderVault.totalOrdersRetrieved(), 1);
        assertEq(orderVault.getActiveOrderCount(), 0); // Should be removed from active
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertTrue(order.retrieved);
    }

    /// @notice Test order retrieval by unauthorized operator
    function testRetrieveOrderUnauthorized() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.prank(operator2); // Unauthorized operator
        vm.expectRevert("Operator not authorized");
        orderVault.retrieveOrder(testOrderId1);
    }

    /// @notice Test order retrieval of non-existent order
    function testRetrieveOrderNotFound() public {
        vm.prank(operator1);
        vm.expectRevert("Order not found");
        orderVault.retrieveOrder(keccak256("non_existent"));
    }

    /// @notice Test order retrieval already retrieved
    function testRetrieveOrderAlreadyRetrieved() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.startPrank(operator1);
        orderVault.retrieveOrder(testOrderId1);
        
        vm.expectRevert("Order already retrieved");
        orderVault.retrieveOrder(testOrderId1);
        vm.stopPrank();
    }

    /// @notice Test order expiration by deadline
    function testExpireOrderDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, deadline);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        vm.expectEmit(true, true, false, false);
        emit IOrderVault.OrderExpired(testOrderId1, trader1, block.timestamp);
        
        orderVault.expireOrder(testOrderId1);
        
        assertEq(orderVault.totalOrdersExpired(), 1);
        assertEq(orderVault.getActiveOrderCount(), 0);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertTrue(order.expired);
    }

    /// @notice Test order expiration by trader
    function testExpireOrderByTrader() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.prank(trader1);
        orderVault.expireOrder(testOrderId1);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertTrue(order.expired);
    }

    /// @notice Test order expiration by authorized hook
    function testExpireOrderByHook() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.prank(hook1);
        orderVault.expireOrder(testOrderId1);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertTrue(order.expired);
    }

    /// @notice Test unauthorized order expiration
    function testExpireOrderUnauthorized() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        vm.prank(trader2); // Different trader
        vm.expectRevert("Cannot expire order yet");
        orderVault.expireOrder(testOrderId1);
    }

    /// @notice Test order validity checking
    function testIsValidOrder() public {
        // Non-existent order
        (bool exists, bool valid) = orderVault.isValidOrder(testOrderId1);
        assertFalse(exists);
        assertFalse(valid);
        
        // Store order
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        // Valid order
        (exists, valid) = orderVault.isValidOrder(testOrderId1);
        assertTrue(exists);
        assertTrue(valid);
        
        // Retrieve order (should become invalid)
        vm.prank(operator1);
        orderVault.retrieveOrder(testOrderId1);
        
        (exists, valid) = orderVault.isValidOrder(testOrderId1);
        assertTrue(exists);
        assertFalse(valid);
    }

    /// @notice Test active order enumeration
    function testActiveOrderEnumeration() public {
        // Store multiple orders
        vm.startPrank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        orderVault.storeOrder(testOrderId2, trader2, "different_data", block.timestamp + 2 hours);
        vm.stopPrank();
        
        assertEq(orderVault.getActiveOrderCount(), 2);
        
        // Get order IDs
        bytes32 firstOrderId = orderVault.getActiveOrderId(0);
        bytes32 secondOrderId = orderVault.getActiveOrderId(1);
        
        assertTrue(firstOrderId == testOrderId1 || firstOrderId == testOrderId2);
        assertTrue(secondOrderId == testOrderId1 || secondOrderId == testOrderId2);
        assertFalse(firstOrderId == secondOrderId);
    }

    /// @notice Test batch order ID retrieval
    function testGetActiveOrderIds() public {
        // Store multiple orders
        vm.startPrank(hook1);
        for (uint i = 0; i < 5; i++) {
            bytes32 orderId = keccak256(abi.encode("order", i));
            orderVault.storeOrder(orderId, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        }
        vm.stopPrank();
        
        bytes32[] memory orderIds = orderVault.getActiveOrderIds(0, 3);
        assertEq(orderIds.length, 3);
        
        // Test with bounds
        orderIds = orderVault.getActiveOrderIds(2, 10); // Should return 3 orders (5 total - 2 start)
        assertEq(orderIds.length, 3);
    }

    /// @notice Test orders by trader
    function testGetOrdersByTrader() public {
        // Store orders from different traders
        vm.startPrank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        orderVault.storeOrder(testOrderId2, trader2, testEncryptedOrder, block.timestamp + 1 hours);
        orderVault.storeOrder(keccak256("order3"), trader1, testEncryptedOrder, block.timestamp + 1 hours);
        vm.stopPrank();
        
        bytes32[] memory trader1Orders = orderVault.getOrdersByTrader(trader1, false);
        assertEq(trader1Orders.length, 2);
        
        bytes32[] memory trader2Orders = orderVault.getOrdersByTrader(trader2, false);
        assertEq(trader2Orders.length, 1);
    }

    /// @notice Test batch order expiration
    function testBatchExpireOrders() public {
        // Store orders with different deadlines
        vm.startPrank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 30 minutes);
        orderVault.storeOrder(testOrderId2, trader2, testEncryptedOrder, block.timestamp + 2 hours);
        vm.stopPrank();
        
        // Fast forward past first deadline
        vm.warp(block.timestamp + 1 hours);
        
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = testOrderId1;
        orderIds[1] = testOrderId2;
        
        orderVault.batchExpireOrders(orderIds);
        
        // Only first order should be expired
        assertEq(orderVault.totalOrdersExpired(), 1);
        
        IOrderVault.VaultOrder memory order1 = orderVault.getVaultOrder(testOrderId1);
        assertTrue(order1.expired);
        
        IOrderVault.VaultOrder memory order2 = orderVault.getVaultOrder(testOrderId2);
        assertFalse(order2.expired);
    }

    /// @notice Test cleanup expired orders
    function testCleanupExpiredOrders() public {
        // Store orders that will expire
        vm.startPrank(hook1);
        for (uint i = 0; i < 3; i++) {
            bytes32 orderId = keccak256(abi.encode("order", i));
            orderVault.storeOrder(orderId, trader1, testEncryptedOrder, block.timestamp + 30 minutes);
        }
        vm.stopPrank();
        
        assertEq(orderVault.getActiveOrderCount(), 3);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 1 hours);
        
        orderVault.cleanupExpiredOrders(5);
        
        assertEq(orderVault.getActiveOrderCount(), 0);
        assertEq(orderVault.totalOrdersExpired(), 3);
    }

    /// @notice Test cleanup expired orders with limit
    function testCleanupExpiredOrdersWithLimit() public {
        // Store many expired orders
        vm.startPrank(hook1);
        for (uint i = 0; i < 10; i++) {
            bytes32 orderId = keccak256(abi.encode("order", i));
            orderVault.storeOrder(orderId, trader1, testEncryptedOrder, block.timestamp + 30 minutes);
        }
        vm.stopPrank();
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 1 hours);
        
        orderVault.cleanupExpiredOrders(5); // Limit to 5
        
        assertEq(orderVault.totalOrdersExpired(), 5);
        assertEq(orderVault.getActiveOrderCount(), 5);
    }

    /// @notice Test hook authorization
    function testHookAuthorization() public {
        assertFalse(orderVault.isAuthorizedHook(hook2));
        
        orderVault.authorizeHook(hook2);
        assertTrue(orderVault.isAuthorizedHook(hook2));
        
        orderVault.revokeHookAuthorization(hook2);
        assertFalse(orderVault.isAuthorizedHook(hook2));
    }

    /// @notice Test hook authorization access control
    function testHookAuthorizationAccessControl() public {
        vm.prank(trader1);
        vm.expectRevert("Not owner");
        orderVault.authorizeHook(hook2);
    }

    /// @notice Test operator authorization
    function testOperatorAuthorization() public {
        assertFalse(orderVault.isAuthorizedOperator(operator2));
        
        orderVault.authorizeOperator(operator2);
        assertTrue(orderVault.isAuthorizedOperator(operator2));
        
        orderVault.revokeOperatorAuthorization(operator2);
        assertFalse(orderVault.isAuthorizedOperator(operator2));
    }

    /// @notice Test batch operator authorization
    function testBatchAuthorizeOperators() public {
        address[] memory operators = new address[](3);
        operators[0] = operator2;
        operators[1] = address(0x203);
        operators[2] = address(0x204);
        
        orderVault.batchAuthorizeOperators(operators);
        
        assertTrue(orderVault.isAuthorizedOperator(operator2));
        assertTrue(orderVault.isAuthorizedOperator(address(0x203)));
        assertTrue(orderVault.isAuthorizedOperator(address(0x204)));
    }

    /// @notice Test batch operator authorization with invalid address
    function testBatchAuthorizeOperatorsInvalid() public {
        address[] memory operators = new address[](2);
        operators[0] = operator2;
        operators[1] = address(0);
        
        vm.expectRevert("Invalid operator address");
        orderVault.batchAuthorizeOperators(operators);
    }

    /// @notice Test vault statistics
    function testVaultStats() public {
        // Store some orders
        vm.startPrank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        orderVault.storeOrder(testOrderId2, trader2, testEncryptedOrder, block.timestamp + 1 hours);
        vm.stopPrank();
        
        // Retrieve one order
        vm.prank(operator1);
        orderVault.retrieveOrder(testOrderId1);
        
        // Expire one order
        vm.prank(trader2);
        orderVault.expireOrder(testOrderId2);
        
        (uint256 totalStored, uint256 totalRetrieved, uint256 totalExpired, uint256 currentlyActive) = 
            orderVault.getVaultStats();
        
        assertEq(totalStored, 2);
        assertEq(totalRetrieved, 1);
        assertEq(totalExpired, 1);
        assertEq(currentlyActive, 0);
    }

    /// @notice Test ownership transfer
    function testOwnershipTransfer() public {
        address newOwner = address(0x999);
        orderVault.transferOwnership(newOwner);
        assertEq(orderVault.owner(), newOwner);
    }

    /// @notice Test ownership transfer to zero address
    function testOwnershipTransferZeroAddress() public {
        vm.expectRevert("Invalid address");
        orderVault.transferOwnership(address(0));
    }

    /// @notice Test emergency pause (placeholder)
    function testEmergencyPause() public {
        // This is a placeholder test since the actual implementation
        // would require a proper pause mechanism
        orderVault.emergencyPause();
        orderVault.emergencyUnpause();
        // No assertions since these are placeholder functions
    }

    /// @notice Test order retrieval after expiration
    function testRetrieveOrderAfterExpiration() public {
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        
        // Expire the order
        vm.prank(trader1);
        orderVault.expireOrder(testOrderId1);
        
        // Try to retrieve expired order
        vm.prank(operator1);
        vm.expectRevert("Order expired");
        orderVault.retrieveOrder(testOrderId1);
    }

    /// @notice Test order retrieval past deadline
    function testRetrieveOrderPastDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, deadline);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        vm.prank(operator1);
        vm.expectRevert("Order deadline passed");
        orderVault.retrieveOrder(testOrderId1);
    }

    /// @notice Test array bounds checking
    function testArrayBoundsChecking() public {
        vm.expectRevert("Index out of bounds");
        orderVault.getActiveOrderId(0);
        
        vm.expectRevert("Start index out of bounds");
        orderVault.getActiveOrderIds(1, 5);
    }

    /// @notice Test gas optimization scenarios
    function testGasOptimization() public {
        uint256 gasBefore = gasleft();
        
        // Store multiple orders
        vm.startPrank(hook1);
        for (uint i = 0; i < 10; i++) {
            bytes32 orderId = keccak256(abi.encode("order", i));
            orderVault.storeOrder(orderId, trader1, testEncryptedOrder, block.timestamp + 1 hours);
        }
        vm.stopPrank();
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Ensure gas usage is reasonable
        assertLt(gasUsed, 2000000); // 2M gas limit
    }

    /// @notice Test edge case: maximum order lifetime
    function testMaximumOrderLifetime() public {
        uint256 maxDeadline = block.timestamp + orderVault.MAX_ORDER_LIFETIME();
        
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, maxDeadline);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertEq(order.deadline, maxDeadline);
    }

    /// @notice Test edge case: minimum order lifetime
    function testMinimumOrderLifetime() public {
        uint256 minDeadline = block.timestamp + orderVault.MIN_ORDER_LIFETIME() + 1; // Must be > MIN_ORDER_LIFETIME
        
        vm.prank(hook1);
        orderVault.storeOrder(testOrderId1, trader1, testEncryptedOrder, minDeadline);
        
        IOrderVault.VaultOrder memory order = orderVault.getVaultOrder(testOrderId1);
        assertEq(order.deadline, minDeadline);
    }
}