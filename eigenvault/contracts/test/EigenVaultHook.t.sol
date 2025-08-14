// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "@forge-std/src/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import {EigenVaultHook} from "../src/EigenVaultHook.sol";
import {EigenVaultServiceManager} from "../src/EigenVaultServiceManager.sol";
import {OrderVault} from "../src/OrderVault.sol";
import {IEigenVaultHook} from "../src/interfaces/IEigenVaultHook.sol";

contract EigenVaultHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolManager poolManager;
    EigenVaultHook eigenVaultHook;
    EigenVaultServiceManager serviceManager;
    OrderVault orderVault;
    
    PoolKey key;
    address trader = address(0x1234);
    address operator = address(0x5678);

    function setUp() public {
        // Deploy Pool Manager
        poolManager = new PoolManager(500000);

        // Deploy Order Vault
        orderVault = new OrderVault();

        // Deploy Service Manager (with mock addresses)
        serviceManager = new EigenVaultServiceManager(
            IAVSDirectory(address(0)), // Mock
            IRewardsCoordinator(address(0)), // Mock
            RegistryCoordinator(address(0)), // Mock
            StakeRegistry(address(0)), // Mock
            IEigenVaultHook(address(0)) // Will be set after hook deployment
        );

        // Mine hook address with correct permissions
        uint160 permissions = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            permissions,
            type(EigenVaultHook).creationCode,
            abi.encode(address(poolManager), address(serviceManager), address(orderVault))
        );

        // Deploy hook at mined address
        eigenVaultHook = new EigenVaultHook{salt: salt}(
            poolManager,
            address(serviceManager),
            orderVault
        );
        
        require(address(eigenVaultHook) == hookAddress, "Hook address mismatch");

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
        vm.prank(address(poolManager)); // Simulate call from pool manager
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

        vm.prank(address(poolManager));
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

        vm.prank(address(poolManager));
        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Wait for deadline to pass
        vm.warp(block.timestamp + 2 minutes);

        // Fallback to AMM
        eigenVaultHook.fallbackToAMM(orderId);

        // Verify order was executed
        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertTrue(order.executed, "Order should be executed via fallback");
    }

    function testUpdateVaultThreshold() public {
        uint256 newThreshold = 200; // 2%
        
        eigenVaultHook.updateVaultThreshold(newThreshold);
        
        uint256 updatedThreshold = eigenVaultHook.getVaultThreshold(key);
        assertEq(updatedThreshold, newThreshold, "Threshold should be updated");
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

    function testBeforeSwapHook() public {
        // This would test the actual hook integration with pool manager
        // For now, we'll test the routing logic separately
        
        IPoolManager.SwapParams memory smallSwapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1000e18, // Small order
            sqrtPriceLimitX96: 0
        });
        
        IPoolManager.SwapParams memory largeSwapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18, // Large order
            sqrtPriceLimitX96: 0
        });

        // Small orders should not be routed to vault
        assertFalse(eigenVaultHook.isLargeOrder(smallSwapParams.amountSpecified, key));
        
        // Large orders should be routed to vault
        assertTrue(eigenVaultHook.isLargeOrder(largeSwapParams.amountSpecified, key));
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
        vm.prank(address(poolManager));
        eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Second order with same commitment should fail
        vm.prank(address(poolManager));
        vm.expectRevert("Commitment already used");
        eigenVaultHook.routeToVault(trader, key, params, hookData);
    }
}