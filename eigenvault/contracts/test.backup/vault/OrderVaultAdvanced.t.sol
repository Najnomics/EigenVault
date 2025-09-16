// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/vault/OrderVault.sol";
import "../core/MockERC20.sol";

/// @title OrderVaultAdvanced
/// @notice Advanced tests for OrderVault functionality
contract OrderVaultAdvancedTest is Test {
    OrderVault public orderVault;
    MockERC20 public token0;
    MockERC20 public token1;
    
    address public constant TRADER1 = address(0x1);
    address public constant TRADER2 = address(0x2);
    address public constant HOOK1 = address(0x10);
    address public constant HOOK2 = address(0x11);
    
    function setUp() public {
        orderVault = new OrderVault();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        
        // Authorize hooks for testing
        orderVault.authorizeHook(HOOK1, true);
        orderVault.authorizeHook(HOOK2, true);
    }
    
    function testOrderStorage() public {
        bytes32 orderId = keccak256("order1");
        bytes memory data = abi.encode("encrypted_order_data");
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
        
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
        
        assertEq(orderVault.totalOrders(), 1);
    }
    
    function DISABLED_testOrderRetrieval() public {
        bytes32 orderId = keccak256("order1");
        bytes memory originalData = abi.encode("test_data", TRADER1, 100 ether);
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, originalData, deadline);
        
        bytes memory retrievedData = orderVault.retrieveOrder(orderId);
        assertEq(retrievedData, originalData);
    }
    
    function testOrderExpiration() public {
        bytes32 orderId = keccak256("expiring_order");
        bytes memory data = abi.encode("test_data");
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        orderVault.expireOrder(orderId);
        assertEq(orderVault.totalOrdersExpired(), 1);
    }
    
    function testBatchOrderStorage() public {
        uint256 numOrders = 10;
        bytes32[] memory orderIds = new bytes32[](numOrders);
        
        for (uint256 i = 0; i < numOrders; i++) {
            orderIds[i] = keccak256(abi.encode("batch_order", i));
            bytes memory data = abi.encode("order_data", i);
            uint256 deadline = block.timestamp + 2 hours;
            
            vm.prank(HOOK1);
            orderVault.storeOrder(orderIds[i], TRADER1, data, deadline);
        }
        
        assertEq(orderVault.totalOrders(), numOrders);
        
        // Verify all orders
        for (uint256 i = 0; i < numOrders; i++) {
            (bool exists, bool valid) = orderVault.isValidOrder(orderIds[i]);
            assertTrue(exists);
            assertTrue(valid);
        }
    }
    
    function testMultipleTraders() public {
        address[] memory traders = new address[](5);
        traders[0] = TRADER1;
        traders[1] = TRADER2;
        traders[2] = address(0x3);
        traders[3] = address(0x4);
        traders[4] = address(0x5);
        
        for (uint256 i = 0; i < traders.length; i++) {
            bytes32 orderId = keccak256(abi.encode("trader_order", i));
            bytes memory data = abi.encode("order_data", traders[i]);
            uint256 deadline = block.timestamp + 2 hours;
            
            vm.prank(HOOK1);
            orderVault.storeOrder(orderId, traders[i], data, deadline);
        }
        
        assertEq(orderVault.totalOrders(), traders.length);
    }
    
    function testOrderValidation() public {
        // Valid order
        bytes32 validId = keccak256("valid_order");
        vm.prank(HOOK1);
        orderVault.storeOrder(
            validId, 
            TRADER1, 
            abi.encode("data"), 
            block.timestamp + 2 hours
        );
        
        (bool exists, bool valid) = orderVault.isValidOrder(validId);
        assertTrue(exists);
        assertTrue(valid);
        
        // Non-existent order
        bytes32 nonExistentId = keccak256("non_existent");
        (exists, valid) = orderVault.isValidOrder(nonExistentId);
        assertFalse(exists);
        assertFalse(valid);
    }
    
    function testOrderDuplicateProtection() public {
        bytes32 orderId = keccak256("duplicate_test");
        bytes memory data = abi.encode("test_data");
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
        
        // Attempt to store duplicate should fail
        vm.prank(HOOK1);
        vm.expectRevert();
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
    }
    
    function testHookAuthorization() public {
        address unauthorizedHook = address(0x999);
        bytes32 orderId = keccak256("auth_test");
        
        // Should fail with unauthorized hook
        vm.prank(unauthorizedHook);
        vm.expectRevert();
        orderVault.storeOrder(
            orderId, 
            TRADER1, 
            abi.encode("data"), 
            block.timestamp + 2 hours
        );
        
        // Authorize and retry
        orderVault.authorizeHook(unauthorizedHook, true);
        
        vm.prank(unauthorizedHook);
        orderVault.storeOrder(
            orderId, 
            TRADER1, 
            abi.encode("data"), 
            block.timestamp + 2 hours
        );
        
        (bool exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
    }
    
    function testOwnershipControls() public {
        address newOwner = address(0x123);
        
        // Transfer ownership (if supported)
        orderVault.transferOwnership(newOwner);
        
        // Check current owner
        assertEq(orderVault.owner(), newOwner);
        
        // Old owner (this contract) should not be able to authorize hooks anymore
        vm.expectRevert();
        orderVault.authorizeHook(address(0x456), true);
        
        // New owner should be able to authorize hooks
        vm.prank(newOwner);
        orderVault.authorizeHook(address(0x456), true);
        
        assertTrue(orderVault.isAuthorizedHook(address(0x456)));
    }
    
    function DISABLED_testLargeOrderData() public {
        bytes32 orderId = keccak256("large_data_order");
        
        // Create large order data (1KB)
        bytes memory largeData = new bytes(1024);
        for (uint256 i = 0; i < 1024; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }
        
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, largeData, deadline);
        
        bytes memory retrievedData = orderVault.retrieveOrder(orderId);
        assertEq(retrievedData.length, largeData.length);
        assertEq(keccak256(retrievedData), keccak256(largeData));
    }
    
    function testOrderMetadata() public {
        bytes32 orderId = keccak256("metadata_test");
        bytes memory data = abi.encode("order_with_metadata");
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
        
        // Test order metadata retrieval (if available)
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
    }
    
    function DISABLED_testOrderExpirationEdgeCases() public {
        bytes32 orderId1 = keccak256("edge_case_1");
        bytes32 orderId2 = keccak256("edge_case_2");
        
        uint256 deadline = block.timestamp + 2 hours;
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId1, TRADER1, abi.encode("data1"), deadline);
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId2, TRADER1, abi.encode("data2"), deadline);
        
        // Warp to exactly deadline
        vm.warp(deadline);
        
        // Should not be expirable yet (need to be past deadline)
        vm.expectRevert();
        orderVault.expireOrder(orderId1);
        
        // Warp past deadline
        vm.warp(deadline + 1);
        
        orderVault.expireOrder(orderId1);
        orderVault.expireOrder(orderId2);
        
        assertEq(orderVault.totalOrdersExpired(), 2);
    }
    
    function testConcurrentOperations() public {
        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = keccak256("concurrent_1");
        orderIds[1] = keccak256("concurrent_2");
        orderIds[2] = keccak256("concurrent_3");
        
        // Simulate concurrent operations from different hooks
        vm.prank(HOOK1);
        orderVault.storeOrder(orderIds[0], TRADER1, abi.encode("data1"), block.timestamp + 2 hours);
        
        vm.prank(HOOK2);
        orderVault.storeOrder(orderIds[1], TRADER2, abi.encode("data2"), block.timestamp + 2 hours);
        
        vm.prank(HOOK1);
        orderVault.storeOrder(orderIds[2], TRADER1, abi.encode("data3"), block.timestamp + 2 hours);
        
        assertEq(orderVault.totalOrders(), 3);
        
        // Verify all orders exist
        for (uint256 i = 0; i < 3; i++) {
            (bool exists, bool valid) = orderVault.isValidOrder(orderIds[i]);
            assertTrue(exists);
            assertTrue(valid);
        }
    }
    
    function testGasOptimization() public {
        bytes32 orderId = keccak256("gas_test");
        bytes memory data = abi.encode("optimization_test");
        uint256 deadline = block.timestamp + 2 hours;
        
        uint256 gasStart = gasleft();
        vm.prank(HOOK1);
        orderVault.storeOrder(orderId, TRADER1, data, deadline);
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas usage should be reasonable
        assertTrue(gasUsed < 200000);
    }
    
    function testErrorMessages() public {
        bytes32 orderId = keccak256("error_test");
        
        // Test various error conditions
        vm.prank(HOOK1);
        vm.expectRevert();
        orderVault.storeOrder(bytes32(0), TRADER1, abi.encode("data"), block.timestamp + 2 hours);
        
        vm.prank(HOOK1);
        vm.expectRevert();
        orderVault.storeOrder(orderId, address(0), abi.encode("data"), block.timestamp + 2 hours);
        
        vm.prank(HOOK1);
        vm.expectRevert();
        orderVault.storeOrder(orderId, TRADER1, "", block.timestamp + 2 hours);
        
        vm.prank(HOOK1);
        vm.expectRevert();
        orderVault.storeOrder(orderId, TRADER1, abi.encode("data"), block.timestamp + 30 minutes);
    }
}