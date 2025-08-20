// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import "../src/EigenVaultHook.sol";
import "../src/OrderVault.sol";
import "../src/EigenVaultServiceManager.sol";
import "../src/interfaces/IEigenVaultHook.sol";
import "../src/interfaces/IOrderVault.sol";
import "./mocks/MockPoolManager.sol";
import "./mocks/MockERC20.sol";
import "./utils/EigenVaultTestBase.sol";

/// @title EigenVaultHook Test Suite
/// @notice Comprehensive test suite for EigenVaultHook contract
contract EigenVaultHookTest is EigenVaultTestBase {
    using CurrencyLibrary for Currency;

    EigenVaultHook public hook;
    OrderVault public orderVault;
    EigenVaultServiceManager public serviceManager;
    MockPoolManager public poolManager;
    
    MockERC20 public token0;
    MockERC20 public token1;
    Currency public currency0;
    Currency public currency1;
    
    PoolKey public testPoolKey;
    // Use addresses from EigenVaultTestBase

    function setUp() public override {
        // Deploy mock tokens
        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // Setup test pool key
        testPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Deploy mock pool manager
        poolManager = new MockPoolManager();

        // Deploy order vault
        orderVault = new OrderVault();

        // Deploy service manager (simplified for testing)
        serviceManager = new EigenVaultServiceManager(
            IEigenVaultHook(address(0)), // Will be updated after hook deployment
            IOrderVault(address(orderVault))
        );

        // Deploy hook
        hook = new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(serviceManager)
        );

        // Update pool key with hook address
        testPoolKey.hooks = IHooks(address(hook));

        // Setup authorizations
        orderVault.authorizeHook(address(hook));
        
        // Set lower vault threshold for testing (10 bps = 0.1%)
        hook.updateVaultThreshold(10);
        
        // Fund traders
        token0.mint(trader1, 10000 ether);
        token1.mint(trader1, 10000 ether);
        token0.mint(trader2, 10000 ether);
        token1.mint(trader2, 10000 ether);
    }

    /// @notice Test contract deployment and initialization
    function testDeployment() public {
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(hook.orderVault(), address(orderVault));
        assertEq(hook.owner(), address(this));
        assertEq(hook.vaultThresholdBps(), 10); // Updated to reflect our test setup
    }

    /// @notice Test hook permissions are set correctly
    function testHookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }

    /// @notice Test large order detection
    function testIsLargeOrder() public {
        // Test large order
        assertTrue(hook.isLargeOrder(int256(LARGE_ORDER_AMOUNT), testPoolKey));
        
        // Test small order
        assertFalse(hook.isLargeOrder(int256(SMALL_ORDER_AMOUNT), testPoolKey));
        
        // Test negative amounts
        assertTrue(hook.isLargeOrder(-int256(LARGE_ORDER_AMOUNT), testPoolKey));
        assertFalse(hook.isLargeOrder(-int256(SMALL_ORDER_AMOUNT), testPoolKey));
    }

    /// @notice Test vault threshold updates
    function testUpdateVaultThreshold() public {
        uint256 newThreshold = 200;
        uint256 oldThreshold = hook.vaultThresholdBps();
        
        vm.expectEmit(true, false, false, true);
        emit EigenVaultBase.VaultThresholdUpdated(oldThreshold, newThreshold);
        
        hook.updateVaultThreshold(newThreshold);
        assertEq(hook.vaultThresholdBps(), newThreshold);
    }

    /// @notice Test vault threshold update access control
    function testUpdateVaultThresholdOnlyOwner() public {
        vm.prank(trader1);
        vm.expectRevert("Only owner");
        hook.updateVaultThreshold(200);
    }

    /// @notice Test invalid vault threshold
    function testInvalidVaultThreshold() public {
        vm.expectRevert("Invalid threshold");
        hook.updateVaultThreshold(0);
        
        vm.expectRevert("Invalid threshold");
        hook.updateVaultThreshold(1001);
    }

    /// @notice Test pool-specific threshold setting
    function testSetPoolThreshold() public {
        uint256 poolThreshold = 300;
        
        vm.expectEmit(true, false, false, true);
        emit EigenVaultBase.PoolThresholdUpdated(hook.getPoolId(testPoolKey), 0, poolThreshold);
        
        hook.setPoolThreshold(testPoolKey, poolThreshold);
        assertEq(hook.getVaultThreshold(testPoolKey), poolThreshold);
    }

    /// @notice Test beforeSwap with small order
    function testBeforeSwapSmallOrder() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(SMALL_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes memory hookData = "";
        
        vm.prank(address(poolManager));
        (bytes4 selector,,) = hook.beforeSwap(trader1, testPoolKey, params, hookData);
        
        assertEq(selector, IHooks.beforeSwap.selector);
    }

    /// @notice Test beforeSwap with large order routes to vault
    function testBeforeSwapLargeOrder() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("test_commitment");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = "encrypted_order_data";
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);
        
        // Get the current order nonce
        uint256 currentNonce = hook.orderNonce();
        
        vm.prank(address(poolManager));
        (bytes4 selector,,) = hook.beforeSwap(trader1, testPoolKey, params, hookData);
        
        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(hook.orderNonce(), currentNonce + 1);
        
        // Verify that the order was created by checking the nonce increased
        // The actual order ID verification can be done in a separate test
    }

    /// @notice Test routeToVault with valid parameters
    function testRouteToVault() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("test_commitment");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory encryptedOrder = "encrypted_order_data";
        bytes memory hookData = abi.encode(commitment, deadline, encryptedOrder);

        bytes32 orderId = hook.routeToVault(trader1, testPoolKey, params, hookData);
        
        assertFalse(orderId == bytes32(0));
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertEq(order.trader, trader1);
        assertEq(order.zeroForOne, true);
        assertEq(order.amountSpecified, int256(LARGE_ORDER_AMOUNT));
        assertEq(order.commitment, commitment);
        assertEq(order.deadline, deadline);
        assertFalse(order.executed);
    }

    /// @notice Test routeToVault with invalid trader
    function testRouteToVaultInvalidTrader() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes memory hookData = abi.encode(bytes32(0), block.timestamp + 1 hours, "data");

        vm.expectRevert("Invalid trader");
        hook.routeToVault(address(0), testPoolKey, params, hookData);
    }

    /// @notice Test routeToVault with invalid deadline
    function testRouteToVaultInvalidDeadline() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        // Test deadline too soon
        bytes memory hookData1 = abi.encode(bytes32(0), block.timestamp + 1 minutes, "data");
        vm.expectRevert("Invalid deadline");
        hook.routeToVault(trader1, testPoolKey, params, hookData1);

        // Test deadline too far
        bytes memory hookData2 = abi.encode(bytes32(0), block.timestamp + 25 hours, "data");
        vm.expectRevert("Invalid deadline");
        hook.routeToVault(trader1, testPoolKey, params, hookData2);
    }

    /// @notice Test commitment replay protection
    function testCommitmentReplayProtection() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("test_commitment");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory hookData = abi.encode(commitment, deadline, "data");

        // First use should succeed
        hook.routeToVault(trader1, testPoolKey, params, hookData);

        // Second use should fail
        vm.expectRevert("Commitment already used");
        hook.routeToVault(trader1, testPoolKey, params, hookData);
    }

    /// @notice Test order execution with valid proof
    function testExecuteVaultOrder() public {
        // First, route an order to vault
        bytes32 orderId = _createTestOrder();
        
        // Create mock proof that will pass validation
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = bytes32(uint256(1000)); // executionPrice
        publicInputs[1] = bytes32(uint256(1000)); // totalVolume
        publicInputs[2] = keccak256("test_match"); // matchHash
        
        // Create a mock proof that's at least 32 bytes long to pass ZK verification
        bytes memory mockProof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            mockProof[i] = bytes1(uint8(i % 256));
        }
        
        bytes memory proof = abi.encode(
            ZKProofLib.MatchingProof({
                proofId: keccak256("test_proof"),
                proof: mockProof,
                publicInputs: publicInputs,
                verificationKey: "mock_vk",
                timestamp: block.timestamp,
                operators: new address[](1),
                poolHash: keccak256(abi.encode(testPoolKey)),
                orderCount: 1
            })
        );
        bytes memory signatures = "mock_signatures";

        // This would normally be called by service manager
        vm.prank(address(serviceManager));
        hook.executeVaultOrder(orderId, proof, signatures);
        
        // Verify the order was executed
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertTrue(order.executed);
    }

    /// @notice Test execute vault order with non-existent order
    function testExecuteVaultOrderNotFound() public {
        bytes32 orderId = keccak256("non_existent");
        bytes memory proof = "mock_proof";
        bytes memory signatures = "mock_signatures";

        vm.prank(address(serviceManager));
        vm.expectRevert("Order not found");
        hook.executeVaultOrder(orderId, proof, signatures);
    }

    /// @notice Test execute vault order already executed
    function testExecuteVaultOrderAlreadyExecuted() public {
        bytes32 orderId = _createTestOrder();
        
        // Execute once
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = bytes32(uint256(1000)); // executionPrice
        publicInputs[1] = bytes32(uint256(1000)); // totalVolume
        publicInputs[2] = keccak256("test_match"); // matchHash
        
        // Create a mock proof that's at least 32 bytes long to pass ZK verification
        bytes memory mockProof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            mockProof[i] = bytes1(uint8(i % 256));
        }
        
        bytes memory proof = abi.encode(
            ZKProofLib.MatchingProof({
                proofId: keccak256("test_proof"),
                proof: mockProof,
                publicInputs: publicInputs,
                verificationKey: "mock_vk",
                timestamp: block.timestamp,
                operators: new address[](1),
                poolHash: keccak256(abi.encode(testPoolKey)),
                orderCount: 1
            })
        );
        
        vm.startPrank(address(serviceManager));
        hook.executeVaultOrder(orderId, proof, "signatures");
        
        // Try to execute again
        vm.expectRevert("Order already executed");
        hook.executeVaultOrder(orderId, proof, "signatures");
        vm.stopPrank();
    }

    /// @notice Test execute vault order expired
    function testExecuteVaultOrderExpired() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("test_commitment");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory hookData = abi.encode(commitment, deadline, "data");

        bytes32 orderId = hook.routeToVault(trader1, testPoolKey, params, hookData);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        bytes memory proof = "mock_proof";
        vm.prank(address(serviceManager));
        vm.expectRevert("Order expired");
        hook.executeVaultOrder(orderId, proof, "signatures");
    }

    /// @notice Test fallback to AMM after deadline
    function testFallbackToAMMAfterDeadline() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("test_commitment");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory hookData = abi.encode(commitment, deadline, "data");

        bytes32 orderId = hook.routeToVault(trader1, testPoolKey, params, hookData);
        
        // Fast forward past deadline
        vm.warp(deadline + 1);
        
        vm.expectEmit(true, true, false, false);
        emit IEigenVaultHook.OrderFallbackToAMM(orderId, trader1, "Deadline exceeded");
        
        hook.fallbackToAMM(orderId);
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertTrue(order.executed);
    }

    /// @notice Test fallback to AMM by trader
    function testFallbackToAMMByTrader() public {
        bytes32 orderId = _createTestOrder();
        
        vm.prank(trader1);
        vm.expectEmit(true, true, false, false);
        emit IEigenVaultHook.OrderFallbackToAMM(orderId, trader1, "Manual fallback");
        
        hook.fallbackToAMM(orderId);
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertTrue(order.executed);
    }

    /// @notice Test fallback to AMM unauthorized
    function testFallbackToAMMUnauthorized() public {
        bytes32 orderId = _createTestOrder();
        
        vm.prank(trader2);
        vm.expectRevert("Cannot fallback yet");
        hook.fallbackToAMM(orderId);
    }

    /// @notice Test service manager authorization
    function testServiceManagerAuthorization() public {
        address newServiceManager = address(0x999);
        
        vm.expectEmit(true, false, false, true);
        emit EigenVaultHook.ServiceManagerAuthorized(newServiceManager, true);
        
        hook.setServiceManagerAuthorization(newServiceManager, true);
        assertTrue(hook.authorizedServiceManagers(newServiceManager));
        
        // Test deauthorization
        hook.setServiceManagerAuthorization(newServiceManager, false);
        assertFalse(hook.authorizedServiceManagers(newServiceManager));
    }

    /// @notice Test unauthorized service manager execution
    function testUnauthorizedServiceManagerExecution() public {
        bytes32 orderId = _createTestOrder();
        bytes memory proof = "mock_proof";
        
        vm.prank(address(0x999));
        vm.expectRevert("Unauthorized service manager");
        hook.executeVaultOrder(orderId, proof, "signatures");
    }

    /// @notice Test pool execution stats tracking
    function testPoolExecutionStats() public {
        // Create and execute an order
        bytes32 orderId = _createTestOrder();
        
        // Create mock proof that will pass validation
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = bytes32(uint256(1000)); // executionPrice
        publicInputs[1] = bytes32(uint256(1000)); // totalVolume
        publicInputs[2] = keccak256("test_match"); // matchHash
        
        // Create a mock proof that's at least 32 bytes long to pass ZK verification
        bytes memory mockProof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            mockProof[i] = bytes1(uint8(i % 256));
        }
        
        bytes memory proof = abi.encode(
            ZKProofLib.MatchingProof({
                proofId: keccak256("test_proof"),
                proof: mockProof,
                publicInputs: publicInputs,
                verificationKey: "mock_vk",
                timestamp: block.timestamp,
                operators: new address[](1),
                poolHash: keccak256(abi.encode(testPoolKey)),
                orderCount: 1
            })
        );
        
        vm.prank(address(serviceManager));
        hook.executeVaultOrder(orderId, proof, "signatures");
        
        EigenVaultHook.ExecutionStats memory stats = hook.getPoolExecutionStats(testPoolKey);
        assertEq(stats.totalOrders, 1);
        assertEq(stats.successfulMatches, 1);
    }

    /// @notice Test pause functionality
    function testPauseFunctionality() public {
        hook.setPaused(true);
        assertTrue(hook.paused());
        
        hook.setPaused(false);
        assertFalse(hook.paused());
    }

    /// @notice Test pause access control
    function testPauseOnlyOwner() public {
        vm.prank(trader1);
        vm.expectRevert("Only owner");
        hook.setPaused(true);
    }

    /// @notice Test ownership transfer
    function testOwnershipTransfer() public {
        address newOwner = address(0x999);
        
        vm.expectEmit(true, true, false, false);
        emit EigenVaultBase.OwnershipTransferred(address(this), newOwner);
        
        hook.transferOwnership(newOwner);
        assertEq(hook.owner(), newOwner);
    }

    /// @notice Test ownership transfer to zero address
    function testOwnershipTransferZeroAddress() public {
        vm.expectRevert("New owner cannot be zero address");
        hook.transferOwnership(address(0));
    }

    /// @notice Test isOrderExecutable
    function testIsOrderExecutable() public {
        bytes32 orderId = _createTestOrder();
        assertTrue(hook.isOrderExecutable(orderId));
        
        // Execute order
        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = bytes32(uint256(1000)); // executionPrice
        publicInputs[1] = bytes32(uint256(1000)); // totalVolume
        publicInputs[2] = keccak256("test_match"); // matchHash
        
        // Create a mock proof that's at least 32 bytes long to pass ZK verification
        bytes memory mockProof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            mockProof[i] = bytes1(uint8(i % 256));
        }
        
        bytes memory proof = abi.encode(
            ZKProofLib.MatchingProof({
                proofId: keccak256("test_proof"),
                proof: mockProof,
                publicInputs: publicInputs,
                verificationKey: "mock_vk",
                timestamp: block.timestamp,
                operators: new address[](1),
                poolHash: keccak256(abi.encode(testPoolKey)),
                orderCount: 1
            })
        );
        
        vm.prank(address(serviceManager));
        hook.executeVaultOrder(orderId, proof, "signatures");
        
        assertFalse(hook.isOrderExecutable(orderId));
    }

    /// @notice Test multiple orders from same trader
    function testMultipleOrdersFromTrader() public {
        bytes32 orderId1 = _createTestOrder();
        bytes32 orderId2 = _createTestOrderWithCommitment(keccak256("commitment2"));
        
        assertFalse(orderId1 == orderId2);
        
        IEigenVaultHook.PrivateOrder memory order1 = hook.getOrder(orderId1);
        IEigenVaultHook.PrivateOrder memory order2 = hook.getOrder(orderId2);
        
        assertEq(order1.trader, trader1);
        assertEq(order2.trader, trader1);
        assertFalse(order1.commitment == order2.commitment);
    }

    /// @notice Test order with different pool
    function testOrderWithDifferentPool() public {
        PoolKey memory differentPool = PoolKey({
            currency0: Currency.wrap(address(token1)),
            currency1: Currency.wrap(address(token0)),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });

        SwapParams memory params = SwapParams({
            zeroForOne: false,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes32 commitment = keccak256("different_pool_commitment");
        bytes memory hookData = abi.encode(commitment, block.timestamp + 1 hours, "data");

        bytes32 orderId = hook.routeToVault(trader1, differentPool, params, hookData);
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertEq(order.poolKey.fee, 10000);
        assertEq(order.zeroForOne, false);
    }

    /// @notice Test order amount edge cases
    function testOrderAmountEdgeCases() public {
        // Test exactly at threshold (10 bps = 0.1% of 1M liquidity = 1000)
        uint256 thresholdAmount = 1000 ether; // 0.1% of 1M liquidity
        
        assertTrue(hook.isLargeOrder(int256(thresholdAmount), testPoolKey));
        assertFalse(hook.isLargeOrder(int256(thresholdAmount - 1), testPoolKey));
        
        // Test very large amounts
        uint256 veryLargeAmount = type(uint128).max;
        assertTrue(hook.isLargeOrder(int256(veryLargeAmount), testPoolKey));
    }

    /// @notice Test gas optimization scenarios
    function testGasOptimization() public {
        uint256 gasBefore = gasleft();
        _createTestOrder();
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        // Ensure gas usage is reasonable (adjust threshold as needed)
        assertLt(gasUsed, 500000);
    }

    // Helper function to create a test order
    function _createTestOrder() internal returns (bytes32) {
        return _createTestOrderWithCommitment(keccak256("test_commitment"));
    }

    function _createTestOrderWithCommitment(bytes32 commitment) internal returns (bytes32) {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(LARGE_ORDER_AMOUNT),
            sqrtPriceLimitX96: 0
        });

        bytes memory hookData = abi.encode(commitment, block.timestamp + 1 hours, "data");
        return hook.routeToVault(trader1, testPoolKey, params, hookData);
    }

    // Helper function to generate order ID with correct types
    function _generateOrderId(address trader, PoolKey memory poolKey, SwapParams memory params, uint256 nonce) internal view returns (bytes32) {
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
}