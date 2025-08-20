// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import {EigenVaultHook} from "../src/EigenVaultHook.sol";
import {EigenVaultServiceManager} from "../src/EigenVaultServiceManager.sol";
import {OrderVault} from "../src/OrderVault.sol";
import {ZKProofLib} from "../src/libraries/ZKProofLib.sol";
import {IEigenVaultHook} from "../src/interfaces/IEigenVaultHook.sol";

contract EigenVaultIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolManager poolManager;
    EigenVaultHook eigenVaultHook;
    EigenVaultServiceManager serviceManager;
    OrderVault orderVault;
    
    PoolKey key;
    address trader = address(0x1234);
    address operator = address(0x5678);
    address operator2 = address(0x9abc);

    function setUp() public {
        // Deploy Pool Manager
        poolManager = new PoolManager(address(this));

        // Deploy Order Vault
        orderVault = new OrderVault();

        // Deploy Service Manager (simplified constructor)
        serviceManager = new EigenVaultServiceManager(
            IEigenVaultHook(address(0)), // Placeholder, will be updated after hook deployment
            orderVault
        );

        // Deploy hook with service manager
        eigenVaultHook = new EigenVaultHook(
            poolManager,
            address(orderVault),
            address(serviceManager)
        );

        // Configure contracts
        orderVault.authorizeHook(address(eigenVaultHook));
        orderVault.authorizeOperator(operator);
        orderVault.authorizeOperator(operator2);

        // Set vault threshold to 10 bps (0.1%) for testing
        eigenVaultHook.updateVaultThreshold(10);

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
        vm.deal(operator2, 100 ether);
    }

    function testCompleteOrderFlow() public {
        // 1. Submit a large order
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18, // Large order
            sqrtPriceLimitX96: 0
        });

        // Route order to vault
        vm.prank(address(poolManager));
        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Verify order was stored
        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertEq(order.trader, trader, "Trader address mismatch");
        assertEq(order.commitment, commitment, "Commitment mismatch");
        assertFalse(order.executed, "Order should not be executed yet");

        // 2. Create a ZK proof
        ZKProofLib.MatchingProof memory proof = _createMockProof(orderId, key);

        // 3. Execute the order through the service manager
        vm.prank(address(serviceManager));
        eigenVaultHook.executeVaultOrder(orderId, abi.encode(proof), "");

        // Verify order was executed
        order = eigenVaultHook.getOrder(orderId);
        assertTrue(order.executed, "Order should be executed");
    }

    function testOrderClassification() public {
        // Test small order (should not be routed to vault)
        int256 smallAmount = 999e18; // 999 tokens (below 0.1% threshold)
        bool isLarge = eigenVaultHook.isLargeOrder(smallAmount, key);
        assertFalse(isLarge, "Small order should not be classified as large");

        // Test large order (should be routed to vault)
        int256 largeAmount = 1000e18; // 1000 tokens (at 0.1% threshold)
        isLarge = eigenVaultHook.isLargeOrder(largeAmount, key);
        assertTrue(isLarge, "Large order should be classified as large");
    }

    function testVaultThresholdManagement() public {
        // Test default threshold
        uint256 defaultThreshold = eigenVaultHook.getVaultThreshold(key);
        assertEq(defaultThreshold, 10, "Default threshold should be 10 bps (0.1%)");

        // Test pool-specific threshold
        uint256 customThreshold = 500; // 5%
        vm.prank(eigenVaultHook.owner());
        eigenVaultHook.setPoolThreshold(key, customThreshold);
        
        uint256 newThreshold = eigenVaultHook.getVaultThreshold(key);
        assertEq(newThreshold, customThreshold, "Pool-specific threshold should be set");

        // Test global threshold update
        uint256 newGlobalThreshold = 200; // 2%
        vm.prank(eigenVaultHook.owner());
        eigenVaultHook.updateVaultThreshold(newGlobalThreshold);
        
        uint256 globalThreshold = eigenVaultHook.getVaultThreshold(key);
        assertEq(globalThreshold, customThreshold, "Pool-specific threshold should override global");
    }

    function testOrderExpiration() public {
        // Submit an order
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18,
            sqrtPriceLimitX96: 0
        });

        vm.prank(address(poolManager));
        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Fast forward past deadline
        vm.warp(deadline + 1);

        // Test fallback to AMM
        vm.prank(trader);
        eigenVaultHook.fallbackToAMM(orderId);

        IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
        assertTrue(order.executed, "Order should be marked as executed after fallback");
    }

    function testInvalidProofRejection() public {
        // Submit an order
        bytes32 commitment = keccak256(abi.encodePacked("test_commitment", block.timestamp));
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data");
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 100000e18,
            sqrtPriceLimitX96: 0
        });

        vm.prank(address(poolManager));
        bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

        // Try to execute with invalid proof through the service manager
        ZKProofLib.MatchingProof memory invalidProof = _createInvalidProof(orderId, key);

        vm.prank(address(serviceManager));
        vm.expectRevert("Invalid proof");
        eigenVaultHook.executeVaultOrder(orderId, abi.encode(invalidProof), "");
    }

    function testMultipleOrders() public {
        // Submit multiple orders
        for (uint256 i = 0; i < 3; i++) {
            bytes32 commitment = keccak256(abi.encodePacked("test_commitment", i, block.timestamp));
            uint256 deadline = block.timestamp + 1 hours;
            bytes memory encryptedOrder = abi.encodePacked("encrypted_order_data", i);
            bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

            SwapParams memory params = SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: int256(50000e18 + i * 10000e18),
                sqrtPriceLimitX96: 0
            });

            vm.prank(address(poolManager));
            bytes32 orderId = eigenVaultHook.routeToVault(trader, key, params, hookData);

            // Verify each order was stored
            IEigenVaultHook.PrivateOrder memory order = eigenVaultHook.getOrder(orderId);
            assertEq(order.trader, trader, "Trader address mismatch");
            assertFalse(order.executed, "Order should not be executed yet");
        }
    }

    // Helper functions
    function _createMockProof(bytes32 orderId, PoolKey memory poolKey) internal view returns (ZKProofLib.MatchingProof memory) {
        bytes32[] memory orderCommitments = new bytes32[](1);
        orderCommitments[0] = orderId;
        
        bytes32[] memory operatorSignatures = new bytes32[](2);
        operatorSignatures[0] = bytes32(uint256(uint160(operator)));
        operatorSignatures[1] = bytes32(uint256(uint160(operator2)));

        // Create a mock proof that's at least 32 bytes long to pass ZK verification
        bytes memory mockProof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            mockProof[i] = bytes1(uint8(i % 256));
        }

        return ZKProofLib.MatchingProof({
            proofId: keccak256(abi.encodePacked(orderId, "proof_id")),
            proof: mockProof,
            publicInputs: orderCommitments,
            verificationKey: abi.encodePacked("mock_verification_key"),
            timestamp: block.timestamp,
            operators: _getOperatorArray(operator, operator2),
            poolHash: keccak256(abi.encode(poolKey)),
            orderCount: 2
        });
    }

    function _createInvalidProof(bytes32 orderId, PoolKey memory poolKey) internal view returns (ZKProofLib.MatchingProof memory) {
        bytes32[] memory orderCommitments = new bytes32[](1);
        orderCommitments[0] = orderId;
        
        bytes32[] memory operatorSignatures = new bytes32[](1); // Only 1 signature (insufficient)

        return ZKProofLib.MatchingProof({
            proofId: keccak256(abi.encodePacked(orderId, "invalid_proof_id")),
            proof: "", // Empty proof data
            publicInputs: orderCommitments,
            verificationKey: abi.encodePacked("invalid_verification_key"),
            timestamp: block.timestamp,
            operators: _getOperatorArray(operator, address(0)), // Only 1 operator (insufficient)
            poolHash: keccak256(abi.encode(poolKey)),
            orderCount: 1
        });
    }

    /// @notice Helper function to create operator array
    function _getOperatorArray(address op1, address op2) internal pure returns (address[] memory) {
        address[] memory operators = new address[](2);
        operators[0] = op1;
        operators[1] = op2;
        return operators;
    }
} 