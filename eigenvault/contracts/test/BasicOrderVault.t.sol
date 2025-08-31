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
        orderVault.authorizeHook(hook1, true);
    }
    
    function testDeployment() public {
        assertEq(orderVault.owner(), address(this));
        assertTrue(orderVault.authorizedHooks(hook1));
        assertEq(orderVault.getActiveOrderCount(), 0);
    }
    
    function testStoreOrder() public {
        bytes32 orderId = keccak256("test_order");
        uint256 amount = 1e18; // 1 token
        bool zeroForOne = true;
        uint256 price = 2000e18; // $2000
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 commitment = keccak256("commitment");
        bytes32 poolId = keccak256("pool");
        
        vm.prank(hook1);
        orderVault.storeOrder(orderId, amount, zeroForOne, price, deadline, trader1, commitment, poolId);
        
        assertEq(orderVault.getActiveOrderCount(), 1);
        
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
    }
    
    function testUnauthorizedStore() public {
        bytes32 orderId = keccak256("test_order");
        uint256 amount = 1e18;
        bool zeroForOne = true;
        uint256 price = 2000e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 commitment = keccak256("commitment");
        bytes32 poolId = keccak256("pool");
        
        vm.prank(address(0x99)); // Unauthorized
        vm.expectRevert();
        orderVault.storeOrder(orderId, amount, zeroForOne, price, deadline, trader1, commitment, poolId);
    }
}