// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "@forge-std/src/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {SimplifiedEigenVaultHook} from "../src/SimplifiedEigenVaultHook.sol";
import {SimplifiedServiceManager} from "../src/SimplifiedServiceManager.sol";
import {OrderVault} from "../src/OrderVault.sol";
import {IEigenVaultHook} from "../src/interfaces/IEigenVaultHook.sol";

contract SimplifiedHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolManager poolManager;
    SimplifiedEigenVaultHook eigenVaultHook;
    SimplifiedServiceManager serviceManager;
    OrderVault orderVault;
    
    PoolKey key;
    address trader = address(0x1234);
    address operator = address(0x5678);

    function setUp() public {
        // Deploy Pool Manager
        poolManager = new PoolManager(500000);

        // Deploy Order Vault
        orderVault = new OrderVault();

        // Deploy Service Manager
        serviceManager = new SimplifiedServiceManager(
            SimplifiedEigenVaultHook(address(0)) // Will be updated
        );

        // Deploy Hook
        eigenVaultHook = new SimplifiedEigenVaultHook(
            poolManager,
            address(serviceManager),
            orderVault
        );

        // Configure contracts
        orderVault.authorizeHook(address(eigenVaultHook));
        orderVault.authorizeOperator(operator);

        // Create test pool key
        key = PoolKey(
            Currency.wrap(address(0x1111)),
            Currency.wrap(address(0x2222)),
            3000,
            60,
            eigenVaultHook
        );

        // Fund accounts
        vm.deal(trader, 100 ether);
        vm.deal(operator, 100 ether);
    }

    function testIsLargeOrder() public {
        // Test small order (should return false)
        int256 smallAmount = 1000e18; // 1000 tokens
        bool isLarge = eigenVaultHook.isLargeOrder(smallAmount, key);
        assertFalse(isLarge, "Small order should not be classified as large");

        // Test large order (should return true)
        int256 largeAmount = 100000e18; // 100,000 tokens (10% of mock liquidity)
        isLarge = eigenVaultHook.isLargeOrder(largeAmount, key);
        assertTrue(isLarge, "Large order should be classified as large");
    }

    function testRouteToVault() public {
        // Prepare order data
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18, // Large order
            sqrtPriceLimitX96: 0
        });

        // Route order to vault
        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Verify order was stored
        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertEq(order.trader, trader, "Trader address mismatch");
        assertEq(order.commitment, commitment, "Commitment mismatch");
        assertEq(order.deadline, deadline, "Deadline mismatch");
        assertFalse(order.executed, "Order should not be executed yet");
    }

    function testExecuteVaultOrder() public {
        // First, route an order to vault
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18,
            sqrtPriceLimitX96: 0
        });

        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Prepare proof and signatures
        bytes memory proof = abi.encodePacked("mock_zk_proof_data");
        bytes memory signatures = abi.encodePacked("mock_operator_signatures");

        // Execute order (should be called by service manager)
        vm.prank(address(serviceManager));
        eigenVaultHook.executeVaultOrder(orderId, proof, signatures);

        // Verify order was executed
        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertTrue(order.executed, "Order should be executed");
    }

    function testFallbackToAMM() public {
        // Route an order with short deadline
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 minutes;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18,
            sqrtPriceLimitX96: 0
        });

        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Wait for deadline to pass
        vm.warp(block.timestamp + 2 minutes);

        // Fallback to AMM
        eigenVaultHook.fallbackToAMM(orderId);

        // Verify order was executed
        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertTrue(order.executed, "Order should be executed via fallback");
    }

    function testServiceManagerIntegration() public {
        // Register operator
        vm.prank(operator);
        serviceManager.registerOperator();

        // Verify operator is registered
        assertTrue(serviceManager.registeredOperators(operator), "Operator should be registered");
        assertEq(serviceManager.getActiveOperatorsCount(), 1, "Should have 1 active operator");

        // Create matching task
        bytes32 ordersHash = keccak256("test_orders");
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 taskId = serviceManager.createMatchingTask(ordersHash, deadline);

        // Verify task was created
        (bytes32 storedTaskId, bytes32 storedOrdersHash, uint256 storedDeadline, , , , , ) = 
            serviceManager.tasks(taskId);
        assertEq(storedTaskId, taskId, "Task ID mismatch");
        assertEq(storedOrdersHash, ordersHash, "Orders hash mismatch");
        assertEq(storedDeadline, deadline, "Deadline mismatch");
    }

    function testUnauthorizedAccess() public {
        bytes memory proof = abi.encodePacked("mock_proof");
        bytes memory signatures = abi.encodePacked("mock_signatures");
        
        // Try to execute order from unauthorized address
        vm.prank(trader);
        vm.expectRevert("Not service manager");
        eigenVaultHook.executeVaultOrder(bytes32(0), proof, signatures);
    }

    function testInvalidOrderExecution() public {
        bytes memory proof = abi.encodePacked("mock_proof");
        bytes memory signatures = abi.encodePacked("mock_signatures");
        
        // Try to execute non-existent order
        vm.prank(address(serviceManager));
        vm.expectRevert("Order not found");
        eigenVaultHook.executeVaultOrder(bytes32(uint256(123)), proof, signatures);
    }

    function testUpdateVaultThreshold() public {
        uint256 newThreshold = 200; // 2%
        
        eigenVaultHook.updateVaultThreshold(newThreshold);
        
        uint256 updatedThreshold = eigenVaultHook.getVaultThreshold(key);
        assertEq(updatedThreshold, newThreshold, "Threshold should be updated");
    }

    function testCommitmentReplay() public {
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18,
            sqrtPriceLimitX96: 0
        });

        // First order should succeed
        eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Second order with same commitment should fail
        vm.expectRevert("Commitment already used");
        eigenVaultHook.routeToVault(trader, key, params, hookData);
    }
}