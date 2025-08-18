// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/OrderVault.sol";
import "../src/EigenVaultHook.sol";
import "../src/EigenVaultBase.sol";
import "./mocks/MockPoolManager.sol";
import "./mocks/MockERC20.sol";

/// @title ProductionContractsTest
/// @notice Test to verify our production contracts compile and basic functionality works
contract ProductionContractsTest is Test {
    OrderVault public orderVault;
    EigenVaultHook public eigenVaultHook; 
    MockPoolManager public poolManager;
    MockERC20 public token0;
    MockERC20 public token1;
    
    address public trader1 = address(0x1);
    address public hook = address(0x2);
    
    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        
        // Deploy OrderVault
        orderVault = new OrderVault();
        
        // Deploy EigenVaultHook (without ServiceManager for now)
        eigenVaultHook = new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault), 
            address(0) // No service manager
        );
        
        // Setup authorizations
        orderVault.authorizeHook(address(eigenVaultHook));
        
        // Set lower vault threshold for testing (10 bps = 0.1%)
        eigenVaultHook.updateVaultThreshold(10);
        
        // Fund accounts
        token0.mint(trader1, 10000 ether);
        token1.mint(trader1, 10000 ether);
    }
    
    function testOrderVaultDeployment() public {
        assertEq(orderVault.owner(), address(this));
        assertTrue(orderVault.isAuthorizedHook(address(eigenVaultHook)));
        assertEq(orderVault.totalOrdersStored(), 0);
    }
    
    function testEigenVaultHookDeployment() public {
        assertEq(address(eigenVaultHook.poolManager()), address(poolManager));
        assertEq(eigenVaultHook.orderVault(), address(orderVault));
        assertEq(eigenVaultHook.owner(), address(this));
    }
    
    function testOrderVaultStoreOrder() public {
        bytes32 orderId = keccak256("test_order_1");
        bytes memory encryptedData = "encrypted_test_data";
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(address(eigenVaultHook));
        orderVault.storeOrder(orderId, trader1, encryptedData, deadline);
        
        assertEq(orderVault.totalOrdersStored(), 1);
        assertEq(orderVault.getActiveOrderCount(), 1);
        
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
    }
    
    function testHookPermissions() public {
        Hooks.Permissions memory permissions = eigenVaultHook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
    }
    
    function testVaultThresholds() public {
        // Test default threshold
        uint256 defaultThreshold = eigenVaultHook.vaultThresholdBps();
        assertEq(defaultThreshold, 100); // 1%
        
        // Test threshold update
        eigenVaultHook.updateVaultThreshold(200);
        assertEq(eigenVaultHook.vaultThresholdBps(), 200);
    }
    
    function testLargeOrderDetection() public {
        // Create test pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)), 
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(eigenVaultHook))
        });
        
        // Test large order (should be true)
        assertTrue(eigenVaultHook.isLargeOrder(1000 ether, poolKey));
        
        // Test small order (should be false) 
        assertFalse(eigenVaultHook.isLargeOrder(1 ether, poolKey));
    }
    
    function testOrderVaultAuthorization() public {
        address unauthorizedHook = address(0x999);
        
        bytes32 orderId = keccak256("test_order");
        bytes memory encryptedData = "encrypted_data";
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(unauthorizedHook);
        vm.expectRevert("Hook not authorized");
        orderVault.storeOrder(orderId, trader1, encryptedData, deadline);
    }
    
    function testOrderExpiration() public {
        bytes32 orderId = keccak256("test_order");
        bytes memory encryptedData = "encrypted_data"; 
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(address(eigenVaultHook));
        orderVault.storeOrder(orderId, trader1, encryptedData, deadline);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        // Order should be expirable now
        orderVault.expireOrder(orderId);
        
        assertEq(orderVault.totalOrdersExpired(), 1);
        assertEq(orderVault.getActiveOrderCount(), 0);
    }
    
    function testBatchOperations() public {
        // Store multiple orders
        bytes32[] memory orderIds = new bytes32[](3);
        for (uint i = 0; i < 3; i++) {
            orderIds[i] = keccak256(abi.encode("order", i));
            
            vm.prank(address(eigenVaultHook));
            orderVault.storeOrder(
                orderIds[i], 
                trader1, 
                abi.encode("encrypted_data", i),
                block.timestamp + 1 hours
            );
        }
        
        assertEq(orderVault.getActiveOrderCount(), 3);
        
        // Test batch retrieval  
        bytes32[] memory retrievedIds = orderVault.getActiveOrderIds(0, 3);
        assertEq(retrievedIds.length, 3);
    }
}