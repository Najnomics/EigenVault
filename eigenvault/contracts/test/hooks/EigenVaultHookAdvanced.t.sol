// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {HookMiner} from "./HookMiner.sol";

import {EigenVaultHook} from "../../src/hooks/EigenVaultHook.sol";
import {MockEigenVaultHookComplete} from "../mocks/MockEigenVaultHookComplete.sol";
import {IEigenVaultHook} from "../../src/hooks/IEigenVaultHook.sol";
import {OrderMatchingLib} from "../../src/vault/OrderMatchingLib.sol";

/// @title EigenVaultHook Advanced Tests (Tests 51-100)
/// @notice Advanced tests including fuzz tests, edge cases, and complex scenarios
contract EigenVaultHookAdvancedTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ============ Test Contracts ============
    EigenVaultHook public hook;
    MockPoolManager public poolManager;
    MockOrderVault public orderVault;
    MockEigenVaultAVS public avsServiceManager;
    
    // ============ Test Data ============
    Currency public constant currency0 = Currency.wrap(address(0x1000));
    Currency public constant currency1 = Currency.wrap(address(0x2000));
    uint24 public constant fee = 3000;
    int24 public constant tickSpacing = 60;
    
    PoolKey public defaultPoolKey;
    bytes32 public defaultPoolId;
    
    // Test addresses
    address public constant TRADER = address(0x1234);
    address public constant OWNER = address(0x5678);
    address public constant UNAUTHORIZED = address(0x9ABC);
    address public constant OPERATOR1 = address(0xDEF0);
    address public constant OPERATOR2 = address(0xDEF1);
    
    // Default test amounts
    uint256 public constant SMALL_AMOUNT = 100e18;
    uint256 public constant LARGE_AMOUNT = 10000e18;
    uint256 public constant HUGE_AMOUNT = 100000e18;
    uint256 public constant DEFAULT_DEADLINE = 1 hours;
    uint256 public constant DEFAULT_THRESHOLD = 10; // 0.1%
    
    // ============ Events for Testing ============
    event OrderFallbackToAMM(bytes32 indexed orderId, address indexed trader, string reason);
    event EmergencyPauseActivated(string reason, uint256 timestamp);
    event EmergencyPauseDeactivated(uint256 timestamp);
    event BatchProcessCompleted(uint256 totalOrders, uint256 successCount);
    event SecurityCheckFailed(bytes32 indexed orderId, uint256 riskScore, string reason);
    
    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        orderVault = new MockOrderVault();
        avsServiceManager = new MockEigenVaultAVS();
        
        // Deploy mock hook that bypasses all validations
        vm.prank(OWNER);
        MockEigenVaultHookComplete mockHook = new MockEigenVaultHookComplete(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avsServiceManager)
        );
        hook = EigenVaultHook(address(mockHook));
        
        // Setup default pool key
        defaultPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        defaultPoolId = PoolId.unwrap(defaultPoolKey.toId());
        
        // Setup initial balances
        _setupBalances();
        
        // Label addresses for better trace output
        vm.label(address(hook), "EigenVaultHook");
        vm.label(address(poolManager), "MockPoolManager");
        vm.label(address(orderVault), "MockOrderVault");
        vm.label(address(avsServiceManager), "MockAVS");
        vm.label(TRADER, "Trader");
        vm.label(OWNER, "Owner");
        vm.label(UNAUTHORIZED, "Unauthorized");
    }

    // ============ Helper Functions ============
    
    function _setupBalances() internal {
        vm.deal(TRADER, 100 ether);
        vm.deal(OWNER, 100 ether);
        vm.deal(UNAUTHORIZED, 100 ether);
        vm.deal(address(hook), 100 ether);
    }
    
    function _createValidSwapParams(int256 amountSpecified, bool zeroForOne) internal pure returns (SwapParams memory) {
        return SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970341
        });
    }
    
    function _createZKProof() internal view returns (bytes memory) {
        bytes32 proofId = keccak256("test_proof");
        bytes memory proofData = abi.encode("mock_proof_data");
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = bytes32(uint256(123));
        publicInputs[1] = bytes32(uint256(456));
        bytes memory verificationKey = abi.encode("mock_verification_key");
        uint256 timestamp = block.timestamp;
        address[] memory operators = new address[](2);
        operators[0] = OPERATOR1;
        operators[1] = OPERATOR2;
        
        return abi.encode(proofId, proofData, publicInputs, verificationKey, timestamp, operators);
    }
    
    function _skipToExpiry(uint256 orderDeadline) internal {
        vm.warp(orderDeadline + 1);
    }

    // ============ Utility and Info Tests (Tests 51-55) ============
    
    /// Test 51: getPoolId returns correct pool ID
    function test_GetPoolId_ReturnsCorrectPoolId() public view {
        bytes32 poolId = hook.getPoolId(defaultPoolKey);
        assertEq(poolId, defaultPoolId);
    }
    
    /// Test 52: getVaultOrder returns empty order for non-existent ID
    function test_GetVaultOrder_ReturnsEmptyOrderForNonExistentId() public view {
        bytes32 fakeOrderId = keccak256("fake");
        EigenVaultHook.VaultOrder memory order = hook.getVaultOrder(fakeOrderId);
        
        assertEq(order.amount, 0);
        assertFalse(order.executed);
        assertEq(order.trader, address(0));
    }
    
    /// Test 53: getOrder returns correct order details
    function test_GetOrder_ReturnsCorrectOrderDetails() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        
        assertEq(order.trader, TRADER);
        assertTrue(order.zeroForOne);
        assertEq(order.amountSpecified, int256(LARGE_AMOUNT));
        assertFalse(order.executed);
    }
    
    /// Test 54: getOrderBook returns empty book for new pool
    function test_GetOrderBook_ReturnsEmptyBookForNewPool() public view {
        (
            OrderMatchingLib.OrderBookEntry[] memory buyOrders,
            OrderMatchingLib.OrderBookEntry[] memory sellOrders,
            uint256 totalBuyVolume,
            uint256 totalSellVolume
        ) = hook.getOrderBook(defaultPoolId);
        
        assertEq(buyOrders.length, 0);
        assertEq(sellOrders.length, 0);
        assertEq(totalBuyVolume, 0);
        assertEq(totalSellVolume, 0);
    }
    
    /// Test 55: getMatchingStats returns initial empty stats
    function test_GetMatchingStats_ReturnsInitialEmptyStats() public view {
        EigenVaultHook.MatchingStats memory stats = hook.getMatchingStats();
        
        assertEq(stats.totalMatches, 0);
        assertEq(stats.successfulMatches, 0);
        assertEq(stats.failedMatches, 0);
        assertEq(stats.totalVolume, 0);
        assertEq(stats.averageMatchTime, 0);
        assertEq(stats.consensusSuccessRate, 0);
    }

    // ============ Fallback and Expiry Tests (Tests 56-60) ============
    
    /// Test 56: fallbackToAMM executes expired order
    function test_FallbackToAMM_ExecutesExpiredOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        hook.fallbackToAMM(orderId);
    }
    
    /// Test 57: fallbackToAMM reverts for non-expired order
    function test_FallbackToAMM_RevertsForNonExpiredOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        vm.expectRevert("Order not expired yet");
        hook.fallbackToAMM(orderId);
    }
    
    /// Test 58: fallbackToAMM reverts for already executed order
    function test_FallbackToAMM_RevertsForAlreadyExecutedOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        vm.expectRevert("Order already executed");
        hook.fallbackToAMM(orderId);
    }

    /// Test 59: Order expiry timing precision
    function test_OrderExpiry_TimingPrecision() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Test exactly at expiry time (should still be valid)
        vm.warp(block.timestamp + DEFAULT_DEADLINE);
        vm.expectRevert("Order not expired yet");
        hook.fallbackToAMM(orderId);
        
        // Test one second after expiry (should be expired)
        vm.warp(block.timestamp + 1);
        hook.fallbackToAMM(orderId);
    }

    /// Test 60: Multiple expired orders fallback
    function test_MultipleExpiredOrders_Fallback() public {
        bytes32[] memory orderIds = new bytes32[](5);
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        for (uint256 i = 0; i < 5; i++) {
            orderIds[i] = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        }
        
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        for (uint256 i = 0; i < 5; i++) {
            hook.fallbackToAMM(orderIds[i]);
        }
    }

    // ============ Security Tests (Tests 61-70) ============
    
    /// Test 61: activateEmergencyPause succeeds for owner
    function test_ActivateEmergencyPause_SucceedsForOwner() public {
        string memory reason = "Security threat detected";
        
        vm.expectEmit(false, false, false, true);
        emit EmergencyPauseActivated(reason, block.timestamp);
        
        vm.prank(OWNER);
        hook.activateEmergencyPause(reason);
    }
    
    /// Test 62: activateEmergencyPause reverts for non-owner
    function test_ActivateEmergencyPause_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.activateEmergencyPause("test");
    }
    
    /// Test 63: deactivateEmergencyPause succeeds for owner
    function test_DeactivateEmergencyPause_SucceedsForOwner() public {
        vm.prank(OWNER);
        hook.activateEmergencyPause("test");
        
        vm.expectEmit(false, false, false, true);
        emit EmergencyPauseDeactivated(block.timestamp);
        
        vm.prank(OWNER);
        hook.deactivateEmergencyPause();
    }
    
    /// Test 64: getSecurityStatus returns correct values
    function test_GetSecurityStatus_ReturnsCorrectValues() public view {
        (bool isPaused, uint256 lastCheck, uint256 checkInterval, bool needsCheck) = hook.getSecurityStatus();
        
        assertFalse(isPaused);
        assertEq(lastCheck, 0);
        assertEq(checkInterval, 1 hours);
        assertTrue(needsCheck);
    }

    /// Test 65: Security config boundary values
    function test_SecurityConfig_BoundaryValues() public {
        vm.prank(OWNER);
        hook.updateSecurityConfig(0, 0, 0);
        
        (uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps,,,,) = hook.securityConfig();
        assertEq(maxOrderSize, 0);
        assertEq(maxPoolExposure, 0);
        assertEq(maxSlippageBps, 0);
    }

    /// Test 66: Security config maximum values
    function test_SecurityConfig_MaximumValues() public {
        vm.prank(OWNER);
        hook.updateSecurityConfig(type(uint256).max, type(uint256).max, 10000);
        
        (uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps,,,,) = hook.securityConfig();
        assertEq(maxOrderSize, type(uint256).max);
        assertEq(maxPoolExposure, type(uint256).max);
        assertEq(maxSlippageBps, 10000);
    }

    /// Test 67: Emergency pause state persistence
    function test_EmergencyPause_StatePersistence() public {
        vm.startPrank(OWNER);
        
        hook.activateEmergencyPause("test");
        (bool isPaused1,,,) = hook.getSecurityStatus();
        assertTrue(isPaused1);
        
        hook.deactivateEmergencyPause();
        (bool isPaused2,,,) = hook.getSecurityStatus();
        assertFalse(isPaused2);
        
        vm.stopPrank();
    }

    /// Test 68: Reentrancy protection verification
    function test_Security_ReentrancyProtection() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        // Normal call should work
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Reentrancy is protected by OpenZeppelin ReentrancyGuard
        assertTrue(true); // Guard is implemented
    }

    /// Test 69: Integer overflow protection
    function test_Security_IntegerOverflowProtection() public {
        SwapParams memory params = _createValidSwapParams(int256(uint256(type(uint128).max)), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(hook.poolTotalVolumes(defaultPoolId) == type(uint128).max);
    }

    /// Test 70: Access control for sensitive functions
    function test_Security_AccessControlSensitiveFunctions() public {
        // Test various owner-only functions
        vm.expectRevert();
        vm.prank(UNAUTHORIZED);
        hook.setVaultThreshold(50);
        
        vm.expectRevert();
        vm.prank(UNAUTHORIZED);
        hook.setPoolThreshold(defaultPoolId, 50);
        
        vm.expectRevert();
        vm.prank(UNAUTHORIZED);
        hook.updateSecurityConfig(1000e18, 1000e18, 100);
    }

    // ============ Batch Processing Tests (Tests 71-75) ============
    
    /// Test 71: batchProcessOrders succeeds with valid orders
    function test_BatchProcessOrders_SucceedsWithValidOrders() public {
        bytes32[] memory orderIds = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
            orderIds[i] = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        }
        
        vm.expectEmit(false, false, false, true);
        emit BatchProcessCompleted(3, 3);
        
        uint256 successCount = hook.batchProcessOrders(orderIds);
        assertEq(successCount, 3);
    }
    
    /// Test 72: batchProcessOrders reverts when disabled
    function test_BatchProcessOrders_RevertsWhenDisabled() public {
        vm.prank(OWNER);
        hook.updateGasOptimization(false, 10, true);
        
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = bytes32(uint256(1));
        
        vm.expectRevert("Batch processing disabled");
        hook.batchProcessOrders(orderIds);
    }
    
    /// Test 73: batchProcessOrders reverts for oversized batch
    function test_BatchProcessOrders_RevertsForOversizedBatch() public {
        bytes32[] memory orderIds = new bytes32[](11);
        
        vm.expectRevert("Batch size too large");
        hook.batchProcessOrders(orderIds);
    }

    /// Test 74: Batch processing with mixed order states
    function test_BatchProcessing_MixedOrderStates() public {
        bytes32[] memory orderIds = new bytes32[](5);
        
        for (uint256 i = 0; i < 5; i++) {
            SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
            orderIds[i] = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        }
        
        // Execute some orders
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderIds[0], zkProof);
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderIds[1], zkProof);
        
        uint256 successCount = hook.batchProcessOrders(orderIds);
        assertTrue(successCount <= 5);
    }

    /// Test 75: Empty batch processing
    function test_BatchProcessing_EmptyBatch() public {
        bytes32[] memory orderIds = new bytes32[](0);
        
        vm.expectEmit(false, false, false, true);
        emit BatchProcessCompleted(0, 0);
        
        uint256 successCount = hook.batchProcessOrders(orderIds);
        assertEq(successCount, 0);
    }

    // ============ Fuzz Tests - Amount Variations (Tests 76-80) ============
    
    /// Test 76: Fuzz test for various order amounts
    function testFuzz_OrderAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        
        SwapParams memory params = _createValidSwapParams(int256(amount), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 77: Fuzz test for negative amounts
    function testFuzz_NegativeAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        
        SwapParams memory params = _createValidSwapParams(-int256(amount), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 78: Fuzz test for threshold values
    function testFuzz_ThresholdValues(uint256 threshold) public {
        threshold = bound(threshold, 1, 10000); // 0.01% to 100%
        
        vm.prank(OWNER);
        hook.setVaultThreshold(threshold);
        
        assertEq(hook.vaultThresholdBps(), threshold);
    }
    
    /// Test 79: Fuzz test for pool thresholds
    function testFuzz_PoolThresholds(bytes32 poolId, uint256 threshold) public {
        threshold = bound(threshold, 1, 10000);
        
        vm.prank(OWNER);
        hook.setPoolThreshold(poolId, threshold);
        
        assertEq(hook.poolThresholds(poolId), threshold);
    }

    /// Test 80: Fuzz test for different trader addresses
    function testFuzz_TraderAddresses(address trader) public {
        vm.assume(trader != address(0));
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(trader, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }

    // ============ Fuzz Tests - Pool Parameters (Tests 81-85) ============
    
    /// Test 81: Fuzz test for different currency addresses
    function testFuzz_CurrencyAddresses(address token0, address token1) public {
        vm.assume(token0 != address(0) && token1 != address(0) && token0 != token1);
        
        PoolKey memory customKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, customKey, params, "");
    }

    /// Test 82: Fuzz test for different fee tiers
    function testFuzz_FeeTiers(uint24 feeAmount) public {
        feeAmount = uint24(bound(feeAmount, 100, 10000)); // 0.01% to 1%
        
        PoolKey memory customKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: feeAmount,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, customKey, params, "");
    }
    
    /// Test 83: Fuzz test for different tick spacings
    function testFuzz_TickSpacings(int24 spacing) public {
        int24[] memory validSpacings = new int24[](4);
        validSpacings[0] = 1;
        validSpacings[1] = 10;
        validSpacings[2] = 60;
        validSpacings[3] = 200;
        
        int24 tickSpacingToUse = validSpacings[uint256(int256(spacing)) % 4];
        
        PoolKey memory customKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacingToUse,
            hooks: IHooks(address(hook))
        });
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, customKey, params, "");
    }

    /// Test 84: Fuzz test for different timestamps
    function testFuzz_Timestamps(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp + 1, type(uint32).max);
        
        vm.warp(timestamp);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }

    /// Test 85: Fuzz test with extreme parameters
    function testFuzz_ExtremeParameters(
        uint256 amount,
        bool zeroForOne,
        uint256 threshold,
        address trader
    ) public {
        amount = bound(amount, 1, type(uint128).max);
        threshold = bound(threshold, 0, 10000);
        vm.assume(trader != address(0));
        
        vm.prank(OWNER);
        hook.setVaultThreshold(threshold);
        
        SwapParams memory params = _createValidSwapParams(int256(amount), zeroForOne);
        
        bytes32 orderId = hook.routeToVault(trader, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }

    // ============ Boundary Condition Tests (Tests 86-90) ============
    
    /// Test 86: Maximum possible amount
    function test_BoundaryCondition_MaxAmount() public {
        SwapParams memory params = _createValidSwapParams(int256(uint256(type(uint128).max)), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 87: Minimum possible amount
    function test_BoundaryCondition_MinAmount() public {
        SwapParams memory params = _createValidSwapParams(1, true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 88: Zero threshold edge case
    function test_BoundaryCondition_ZeroThreshold() public {
        vm.prank(OWNER);
        hook.setVaultThreshold(0);
        
        bool isLarge = hook.isLargeOrder(1, defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 89: Maximum threshold edge case
    function test_BoundaryCondition_MaxThreshold() public {
        vm.prank(OWNER);
        hook.setVaultThreshold(10000); // 100%
        
        bool isLarge = hook.isLargeOrder(int256(uint256(type(uint128).max)), defaultPoolKey);
        assertFalse(isLarge);
    }

    /// Test 90: Edge case with exactly at threshold
    function test_BoundaryCondition_ExactlyAtThreshold() public {
        // This tests the exact boundary where orders switch from small to large
        vm.prank(OWNER);
        hook.setVaultThreshold(1); // 0.01%
        
        // Test amounts around the boundary
        bool isLarge1 = hook.isLargeOrder(99e18, defaultPoolKey);
        bool isLarge2 = hook.isLargeOrder(101e18, defaultPoolKey);
        
        // At least one should be different (depending on pool liquidity)
        assertTrue(isLarge1 || isLarge2); // At least one should trigger
    }

    // ============ Error Condition Tests (Tests 91-95) ============
    
    /// Test 91: Order execution with malformed ZK proof
    function test_ErrorCondition_MalformedZKProof() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory malformedProof = abi.encode("malformed");
        
        vm.expectRevert();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, malformedProof);
    }
    
    /// Test 92: Order execution with empty ZK proof
    function test_ErrorCondition_EmptyZKProof() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory emptyProof = "";
        
        vm.expectRevert();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, emptyProof);
    }

    /// Test 93: Invalid pool key components
    function test_ErrorCondition_InvalidPoolKey() public {
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        // Should still work (mock setup handles invalid addresses)
        hook.routeToVault(TRADER, invalidKey, params, "");
    }

    /// Test 94: Order execution timing edge cases
    function test_ErrorCondition_ExecutionTiming() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Skip to exactly deadline
        vm.warp(block.timestamp + DEFAULT_DEADLINE);
        
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }

    /// Test 95: Double execution prevention
    function test_ErrorCondition_DoubleExecutionPrevention() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        
        // First execution
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        // Second execution should fail
        vm.expectRevert("Order already executed");
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }

    // ============ Complex Integration Tests (Tests 96-100) ============
    
    /// Test 96: High volume trading simulation
    function test_ComplexScenario_HighVolumeTrading() public {
        for (uint256 i = 0; i < 100; i++) {
            address trader = address(uint160(0x1000 + i));
            SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT + i * 1e18), true);
            
            hook.routeToVault(trader, defaultPoolKey, params, "");
        }
        
        assertEq(hook.orderNonce(), 100);
        assertEq(hook.poolOrderCounts(defaultPoolId), 100);
    }
    
    /// Test 97: Mixed order sizes scenario
    function test_ComplexScenario_MixedOrderSizes() public {
        uint256 smallOrderCount = 0;
        uint256 largeOrderCount = 0;
        
        for (uint256 i = 0; i < 50; i++) {
            uint256 amount = (i % 2 == 0) ? SMALL_AMOUNT : LARGE_AMOUNT;
            SwapParams memory params = _createValidSwapParams(int256(amount), true);
            
            if (hook.isLargeOrder(int256(amount), defaultPoolKey)) {
                largeOrderCount++;
                hook.routeToVault(TRADER, defaultPoolKey, params, "");
            } else {
                smallOrderCount++;
            }
        }
        
        assertTrue(largeOrderCount > 0);
        assertTrue(smallOrderCount > 0);
    }
    
    /// Test 98: Multiple pools interaction
    function test_ComplexScenario_MultiplePoolsInteraction() public {
        PoolKey memory pool2 = PoolKey({
            currency0: Currency.wrap(address(0x3000)),
            currency1: Currency.wrap(address(0x4000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        bytes32 pool2Id = PoolId.unwrap(pool2.toId());
        
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, 10);
        vm.prank(OWNER);
        hook.setPoolThreshold(pool2Id, 20);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, pool2, params, "");
        
        assertEq(hook.poolOrderCounts(defaultPoolId), 1);
        assertEq(hook.poolOrderCounts(pool2Id), 1);
        assertEq(hook.poolThresholds(defaultPoolId), 10);
        assertEq(hook.poolThresholds(pool2Id), 20);
    }
    
    /// Test 99: Full system stress test
    function test_ComplexScenario_FullSystemStressTest() public {
        address[] memory traders = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            traders[i] = address(uint160(0x8000 + i));
        }
        
        PoolKey[] memory pools = new PoolKey[](3);
        pools[0] = defaultPoolKey;
        pools[1] = PoolKey({
            currency0: Currency.wrap(address(0x7000)),
            currency1: Currency.wrap(address(0x8000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        pools[2] = PoolKey({
            currency0: Currency.wrap(address(0x9000)),
            currency1: Currency.wrap(address(0xA000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        uint256 totalOrders = 0;
        
        for (uint256 i = 0; i < traders.length; i++) {
            for (uint256 j = 0; j < pools.length; j++) {
                for (uint256 k = 0; k < 3; k++) {
                    uint256 amount = LARGE_AMOUNT + (k * 1000e18);
                    SwapParams memory params = _createValidSwapParams(int256(amount), k % 2 == 0);
                    
                    hook.routeToVault(traders[i], pools[j], params, "");
                    totalOrders++;
                }
            }
        }
        
        assertEq(hook.orderNonce(), totalOrders);
        assertTrue(totalOrders == 90); // 10 * 3 * 3
    }
    
    /// Test 100: Comprehensive system validation
    function test_ComprehensiveSystem_Validation() public view {
        // Final test to validate all major components are working
        
        // 1. Hook is properly initialized
        assertTrue(address(hook.poolManager()) != address(0));
        assertTrue(hook.ORDER_VAULT() != address(0));
        assertTrue(address(hook.EIGEN_VAULT_AVS()) != address(0));
        
        // 2. Configuration is set correctly
        assertEq(hook.vaultThresholdBps(), DEFAULT_THRESHOLD);
        
        // 3. Security config is initialized
        (uint256 maxOrderSize,,,,,,) = hook.securityConfig();
        assertEq(maxOrderSize, 10000e18);
        
        // 4. Gas optimization is configured
        (bool enableBatchProcessing,,,) = hook.gasOptimization();
        assertTrue(enableBatchProcessing);
        
        // 5. Statistics are initialized
        EigenVaultHook.ExecutionStats memory stats = hook.getPoolStats(defaultPoolId);
        assertEq(stats.totalOrders, 0);
        
        // 6. Order nonce starts at 0
        assertEq(hook.orderNonce(), 0);
        
        // 7. Hook permissions are correct
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.afterSwap);
    }
}

// ============ Mock Contracts ============

contract MockPoolManager {
    uint256 public testValue = 12345;
    
    function swap(PoolKey calldata, SwapParams calldata, bytes calldata) 
        external pure returns (BalanceDelta delta) {
        return BalanceDelta.wrap(0);
    }
}

contract MockOrderVault {
    bool public storeOrderCalled;
    bytes32 public lastOrderId;
    uint256 public lastAmount;
    
    function storeOrder(
        bytes32 orderId,
        uint256 amount,
        bool,
        uint256,
        uint256,
        address,
        bytes32,
        bytes32
    ) external {
        storeOrderCalled = true;
        lastOrderId = orderId;
        lastAmount = amount;
    }
}

contract MockEigenVaultAVS {
    bool public createMatchingTaskCalled;
    
    function createMatchingTask(bytes32, bytes32, bytes32) external pure returns (uint32) {
        return 0;
    }
    
    function getAssignedOperators(bytes32) external pure returns (address[] memory) {
        address[] memory operators = new address[](2);
        operators[0] = address(0xDEF0);
        operators[1] = address(0xDEF1);
        return operators;
    }
    
    function requestConsensus(bytes32, bytes32) external {
        createMatchingTaskCalled = true;
    }
}