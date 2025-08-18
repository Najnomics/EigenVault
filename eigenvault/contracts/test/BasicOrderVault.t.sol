// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/OrderVault.sol";

/// @title BasicOrderVaultTest  
/// @notice Basic test to verify Foundry compilation works
contract BasicOrderVaultTest is Test {
    OrderVault public orderVault;
    
    address public trader1 = address(0x1);
    address public hook1 = address(0x2);
    
    function setUp() public {
        orderVault = new OrderVault();
        orderVault.authorizeHook(hook1);
    }
    
    function testDeployment() public {
        assertEq(orderVault.owner(), address(this));
        assertTrue(orderVault.isAuthorizedHook(hook1));
        assertEq(orderVault.totalOrdersStored(), 0);
    }
    
    function testStoreOrder() public {
        bytes32 orderId = keccak256("test_order");
        bytes memory encryptedData = "encrypted_test_data";
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(hook1);
        orderVault.storeOrder(orderId, trader1, encryptedData, deadline);
        
        assertEq(orderVault.totalOrdersStored(), 1);
        
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
    }
    
    function testUnauthorizedStore() public {
        bytes32 orderId = keccak256("test_order"); 
        bytes memory encryptedData = "encrypted_test_data";
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(address(0x99)); // Unauthorized
        vm.expectRevert("Hook not authorized");
        orderVault.storeOrder(orderId, trader1, encryptedData, deadline);
    }
}