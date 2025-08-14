// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "@forge-std/src/Test.sol";
import {OrderVault} from "../src/OrderVault.sol";
import {IOrderVault} from "../src/interfaces/IOrderVault.sol";

contract OrderVaultTest is Test {
    OrderVault orderVault;
    
    address hook = address(0x1234);
    address operator = address(0x5678);
    address trader = address(0x9abc);
    address unauthorized = address(0xdef0);

    function setUp() public {
        orderVault = new OrderVault();
        
        // Authorize hook and operator
        orderVault.authorizeHook(hook);
        orderVault.authorizeOperator(operator);
        
        // Fund accounts
        vm.deal(trader, 1 ether);
        vm.deal(operator, 1 ether);
    }

    function testStoreOrder() public {
        bytes32 orderId = keccak256("test_order_1");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        // Verify order was stored
        IOrderVault.VaultOrder memory vaultOrder = orderVault.getVaultOrder(orderId);
        assertEq(vaultOrder.orderId, orderId);
        assertEq(vaultOrder.trader, trader);
        assertEq(vaultOrder.encryptedOrder, encryptedOrder);
        assertEq(vaultOrder.deadline, deadline);
        assertFalse(vaultOrder.retrieved);
        assertFalse(vaultOrder.expired);
    }

    function testUnauthorizedStore() public {
        bytes32 orderId = keccak256("test_order_2");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(unauthorized);
        vm.expectRevert("Hook not authorized");
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);
    }

    function testRetrieveOrder() public {
        // First store an order
        bytes32 orderId = keccak256("test_order_3");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        // Retrieve the order
        vm.prank(operator);
        bytes memory retrievedOrder = orderVault.retrieveOrder(orderId);

        assertEq(retrievedOrder, encryptedOrder);

        // Verify order is marked as retrieved
        IOrderVault.VaultOrder memory vaultOrder = orderVault.getVaultOrder(orderId);
        assertTrue(vaultOrder.retrieved);
    }

    function testUnauthorizedRetrieve() public {
        bytes32 orderId = keccak256("test_order_4");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        vm.prank(unauthorized);
        vm.expectRevert("Operator not authorized");
        orderVault.retrieveOrder(orderId);
    }

    function testExpireOrder() public {
        bytes32 orderId = keccak256("test_order_5");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        // Fast forward past deadline
        vm.warp(block.timestamp + 2 hours);

        // Anyone can expire an order past its deadline
        orderVault.expireOrder(orderId);

        // Verify order is marked as expired
        IOrderVault.VaultOrder memory vaultOrder = orderVault.getVaultOrder(orderId);
        assertTrue(vaultOrder.expired);
    }

    function testTraderCanExpireOwnOrder() public {
        bytes32 orderId = keccak256("test_order_6");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        // Trader can expire their own order before deadline
        vm.prank(trader);
        orderVault.expireOrder(orderId);

        IOrderVault.VaultOrder memory vaultOrder = orderVault.getVaultOrder(orderId);
        assertTrue(vaultOrder.expired);
    }

    function testIsValidOrder() public {
        bytes32 orderId = keccak256("test_order_7");
        bytes memory encryptedOrder = abi.encodePacked("encrypted_data");
        uint256 deadline = block.timestamp + 1 hours;

        // Non-existent order
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertFalse(exists);
        assertFalse(valid);

        // Store order
        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, encryptedOrder, deadline);

        // Valid order
        (exists, valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);

        // Retrieve order
        vm.prank(operator);
        orderVault.retrieveOrder(orderId);

        // Order exists but not valid (already retrieved)
        (exists, valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertFalse(valid);
    }

    function testGetActiveOrderCount() public {
        assertEq(orderVault.getActiveOrderCount(), 0);

        // Store first order
        bytes32 orderId1 = keccak256("test_order_8");
        vm.prank(hook);
        orderVault.storeOrder(orderId1, trader, "data1", block.timestamp + 1 hours);
        assertEq(orderVault.getActiveOrderCount(), 1);

        // Store second order
        bytes32 orderId2 = keccak256("test_order_9");
        vm.prank(hook);
        orderVault.storeOrder(orderId2, trader, "data2", block.timestamp + 1 hours);
        assertEq(orderVault.getActiveOrderCount(), 2);

        // Expire first order
        vm.warp(block.timestamp + 2 hours);
        orderVault.expireOrder(orderId1);
        assertEq(orderVault.getActiveOrderCount(), 1);
    }

    function testGetOrdersByTrader() public {
        address trader1 = address(0x1111);
        address trader2 = address(0x2222);

        // Store orders for trader1
        bytes32 orderId1 = keccak256("trader1_order1");
        bytes32 orderId2 = keccak256("trader1_order2");
        vm.startPrank(hook);
        orderVault.storeOrder(orderId1, trader1, "data1", block.timestamp + 1 hours);
        orderVault.storeOrder(orderId2, trader1, "data2", block.timestamp + 1 hours);
        vm.stopPrank();

        // Store order for trader2
        bytes32 orderId3 = keccak256("trader2_order1");
        vm.prank(hook);
        orderVault.storeOrder(orderId3, trader2, "data3", block.timestamp + 1 hours);

        // Get orders for trader1
        bytes32[] memory trader1Orders = orderVault.getOrdersByTrader(trader1, false);
        assertEq(trader1Orders.length, 2);
        assertTrue(trader1Orders[0] == orderId1 || trader1Orders[0] == orderId2);
        assertTrue(trader1Orders[1] == orderId1 || trader1Orders[1] == orderId2);

        // Get orders for trader2
        bytes32[] memory trader2Orders = orderVault.getOrdersByTrader(trader2, false);
        assertEq(trader2Orders.length, 1);
        assertEq(trader2Orders[0], orderId3);
    }

    function testBatchExpireOrders() public {
        // Store multiple orders
        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = keccak256("batch_order_1");
        orderIds[1] = keccak256("batch_order_2");
        orderIds[2] = keccak256("batch_order_3");

        vm.startPrank(hook);
        for (uint256 i = 0; i < orderIds.length; i++) {
            orderVault.storeOrder(orderIds[i], trader, "data", block.timestamp + 1 hours);
        }
        vm.stopPrank();

        // Fast forward past deadline
        vm.warp(block.timestamp + 2 hours);

        // Batch expire orders
        orderVault.batchExpireOrders(orderIds);

        // Verify all orders are expired
        for (uint256 i = 0; i < orderIds.length; i++) {
            IOrderVault.VaultOrder memory vaultOrder = orderVault.getVaultOrder(orderIds[i]);
            assertTrue(vaultOrder.expired);
        }
    }

    function testCleanupExpiredOrders() public {
        // Store orders with different deadlines
        bytes32 orderId1 = keccak256("cleanup_order_1");
        bytes32 orderId2 = keccak256("cleanup_order_2");
        bytes32 orderId3 = keccak256("cleanup_order_3");

        vm.startPrank(hook);
        orderVault.storeOrder(orderId1, trader, "data1", block.timestamp + 1 hours);
        orderVault.storeOrder(orderId2, trader, "data2", block.timestamp + 2 hours);
        orderVault.storeOrder(orderId3, trader, "data3", block.timestamp + 3 hours);
        vm.stopPrank();

        // Fast forward to expire first two orders
        vm.warp(block.timestamp + 2.5 hours);

        uint256 initialActiveCount = orderVault.getActiveOrderCount();
        
        // Cleanup expired orders
        orderVault.cleanupExpiredOrders(10);

        // Verify expired orders were cleaned up
        assertLt(orderVault.getActiveOrderCount(), initialActiveCount);
        
        IOrderVault.VaultOrder memory order1 = orderVault.getVaultOrder(orderId1);
        IOrderVault.VaultOrder memory order2 = orderVault.getVaultOrder(orderId2);
        IOrderVault.VaultOrder memory order3 = orderVault.getVaultOrder(orderId3);
        
        assertTrue(order1.expired);
        assertTrue(order2.expired);
        assertFalse(order3.expired);
    }

    function testGetVaultStats() public {
        // Initial stats
        (uint256 stored, uint256 retrieved, uint256 expired, uint256 active) = 
            orderVault.getVaultStats();
        assertEq(stored, 0);
        assertEq(retrieved, 0);
        assertEq(expired, 0);
        assertEq(active, 0);

        // Store orders
        bytes32 orderId1 = keccak256("stats_order_1");
        bytes32 orderId2 = keccak256("stats_order_2");
        
        vm.startPrank(hook);
        orderVault.storeOrder(orderId1, trader, "data1", block.timestamp + 1 hours);
        orderVault.storeOrder(orderId2, trader, "data2", block.timestamp + 1 hours);
        vm.stopPrank();

        // Check stats after storing
        (stored, retrieved, expired, active) = orderVault.getVaultStats();
        assertEq(stored, 2);
        assertEq(retrieved, 0);
        assertEq(expired, 0);
        assertEq(active, 2);

        // Retrieve one order
        vm.prank(operator);
        orderVault.retrieveOrder(orderId1);

        // Expire one order
        vm.warp(block.timestamp + 2 hours);
        orderVault.expireOrder(orderId2);

        // Check final stats
        (stored, retrieved, expired, active) = orderVault.getVaultStats();
        assertEq(stored, 2);
        assertEq(retrieved, 1);
        assertEq(expired, 1);
        assertEq(active, 0);
    }

    function testInvalidOrderStorage() public {
        // Invalid order ID
        vm.prank(hook);
        vm.expectRevert("Invalid order ID");
        orderVault.storeOrder(bytes32(0), trader, "data", block.timestamp + 1 hours);

        // Invalid trader address
        vm.prank(hook);
        vm.expectRevert("Invalid trader address");
        orderVault.storeOrder(keccak256("test"), address(0), "data", block.timestamp + 1 hours);

        // Empty encrypted order
        vm.prank(hook);
        vm.expectRevert("Empty encrypted order");
        orderVault.storeOrder(keccak256("test"), trader, "", block.timestamp + 1 hours);

        // Invalid deadline (too short)
        vm.prank(hook);
        vm.expectRevert("Invalid deadline");
        orderVault.storeOrder(keccak256("test"), trader, "data", block.timestamp + 1 minutes);

        // Invalid deadline (too long)
        vm.prank(hook);
        vm.expectRevert("Invalid deadline");
        orderVault.storeOrder(keccak256("test"), trader, "data", block.timestamp + 25 hours);
    }

    function testDoubleRetrieve() public {
        bytes32 orderId = keccak256("double_retrieve_order");
        
        vm.prank(hook);
        orderVault.storeOrder(orderId, trader, "data", block.timestamp + 1 hours);

        // First retrieve should succeed
        vm.prank(operator);
        orderVault.retrieveOrder(orderId);

        // Second retrieve should fail
        vm.prank(operator);
        vm.expectRevert("Order already retrieved");
        orderVault.retrieveOrder(orderId);
    }

    function testAuthorization() public {
        address newHook = address(0xaaaa);
        address newOperator = address(0xbbbb);

        // Initially not authorized
        assertFalse(orderVault.isAuthorizedHook(newHook));
        assertFalse(orderVault.isAuthorizedOperator(newOperator));

        // Authorize
        orderVault.authorizeHook(newHook);
        orderVault.authorizeOperator(newOperator);

        assertTrue(orderVault.isAuthorizedHook(newHook));
        assertTrue(orderVault.isAuthorizedOperator(newOperator));

        // Revoke authorization
        orderVault.revokeHookAuthorization(newHook);
        orderVault.revokeOperatorAuthorization(newOperator);

        assertFalse(orderVault.isAuthorizedHook(newHook));
        assertFalse(orderVault.isAuthorizedOperator(newOperator));
    }
}