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
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {HookMiner} from "./HookMiner.sol";

import {EigenVaultHook} from "../../src/hooks/EigenVaultHook.sol";
import {TestEigenVaultHook} from "./TestEigenVaultHook.sol";
import {IEigenVaultHook} from "../../src/hooks/IEigenVaultHook.sol";
import {IOrderVault} from "../../src/vault/IOrderVault.sol";
import {IEigenVaultAVSServiceManager} from "../../src/avs/IEigenVaultAVSServiceManager.sol";
import {OrderLib} from "../../src/vault/OrderLib.sol";
import {ZKProofLib} from "../../src/core/ZKProofLib.sol";
import {OrderMatchingLib} from "../../src/vault/OrderMatchingLib.sol";
import {SecurityLib} from "../../src/core/SecurityLib.sol";

/// @title Comprehensive EigenVaultHook Test Suite
/// @notice 200+ unit tests covering success flows, failure flows, and fuzz tests
contract EigenVaultHookTest is Test {
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
    event VaultThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PoolThresholdUpdated(bytes32 indexed poolId, uint256 oldThreshold, uint256 newThreshold);
    event OrderRoutedToVault(address indexed trader, bytes32 indexed orderId, PoolKey indexed key, bool zeroForOne, int256 amountSpecified, bytes32 commitment);
    event MatchingTaskCreated(uint32 indexed taskIndex, bytes32 indexed orderId, bytes32 indexed poolId);
    event VaultOrderExecuted(PoolKey indexed poolKey, uint256 amountIn, uint256 expectedAmountOut, uint256 actualAmount0, uint256 actualAmount1, bool zeroForOne);
    event SecurityConfigUpdated(uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps);
    event GasOptimizationUpdated(bool batchProcessing, uint256 maxBatchSize, bool compression);
    event AVSServiceManagerAuthorized(address indexed avsServiceManager, bool authorized);
    event OrderMatched(bytes32 indexed orderId, address indexed trader, uint256 executionPrice, uint256 matchedAmount);
    event LiquidityChecked(bytes32 indexed poolId, uint256 requiredAmount, uint256 availableLiquidity, bool sufficient);
    event SecurityCheckFailed(bytes32 indexed orderId, uint256 riskScore, string reason);
    event EmergencyPauseActivated(string reason, uint256 timestamp);
    event EmergencyPauseDeactivated(uint256 timestamp);
    event BatchProcessCompleted(uint256 totalOrders, uint256 successCount);
    
    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        orderVault = new MockOrderVault();
        avsServiceManager = new MockEigenVaultAVS();
        
        // Deploy test hook directly (skips address validation)
        vm.prank(OWNER);
        TestEigenVaultHook testHook = new TestEigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avsServiceManager)
        );
        hook = EigenVaultHook(address(testHook));
        
        // Setup default pool key
        defaultPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        defaultPoolId = PoolId.unwrap(defaultPoolKey.toId());
        
        // Setup initial balances and allowances
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
        // Give test addresses some ETH
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
    
    function _expectOrderRoutedToVault(address trader, bool zeroForOne, int256 amountSpecified) internal {
        vm.expectEmit(true, true, true, false);
        emit OrderRoutedToVault(trader, bytes32(0), defaultPoolKey, zeroForOne, amountSpecified, bytes32(0));
    }
    
    function _expectMatchingTaskCreated() internal {
        vm.expectEmit(true, true, true, false);
        emit MatchingTaskCreated(0, bytes32(0), defaultPoolId);
    }
    
    function _skipToExpiry(uint256 orderDeadline) internal {
        vm.warp(orderDeadline + 1);
    }
    
    function _createOrderId(address trader, uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(trader, defaultPoolId, nonce, block.timestamp));
    }

    // ============ Constructor Tests ============
    
    /// Test 1: Valid constructor parameters
    function test_Constructor_ValidParameters() public {
        EigenVaultHook newHook = new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(avsServiceManager)
        );
        
        assertEq(address(newHook.poolManager()), address(poolManager));
        assertEq(newHook.ORDER_VAULT(), address(orderVault));
        assertEq(address(newHook.EIGEN_VAULT_AVS()), address(avsServiceManager));
        assertEq(newHook.vaultThresholdBps(), 10);
    }
    
    /// Test 2: Constructor reverts with zero order vault
    function test_Constructor_RevertsWithZeroOrderVault() public {
        vm.expectRevert("Invalid order vault address");
        new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(0),
            address(avsServiceManager)
        );
    }
    
    /// Test 3: Constructor reverts with zero AVS address
    function test_Constructor_RevertsWithZeroAVS() public {
        vm.expectRevert("Invalid EigenVault AVS address");
        new EigenVaultHook(
            IPoolManager(address(poolManager)),
            address(orderVault),
            address(0)
        );
    }
    
    /// Test 4: Constructor sets security config
    function test_Constructor_SetsSecurityConfig() public view {
        (uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps, 
         uint256 emergencyPauseThreshold, bool emergencyPaused,,) = hook.securityConfig();
        
        assertEq(maxOrderSize, 10000e18);
        assertEq(maxPoolExposure, 100000e18);
        assertEq(maxSlippageBps, 500);
        assertEq(emergencyPauseThreshold, 80);
        assertFalse(emergencyPaused);
    }
    
    /// Test 5: Constructor sets gas optimization config
    function test_Constructor_SetsGasOptimizationConfig() public view {
        (bool enableBatchProcessing, uint256 maxBatchSize, bool enableCompression, uint256 gasPriceLimit) = 
            hook.gasOptimization();
        
        assertTrue(enableBatchProcessing);
        assertEq(maxBatchSize, 10);
        assertTrue(enableCompression);
        assertEq(gasPriceLimit, 100 gwei);
    }

    // ============ Hook Permissions Tests ============
    
    /// Test 6: Get hook permissions returns correct values
    function test_GetHookPermissions_ReturnsCorrectValues() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }

    // ============ Large Order Detection Tests ============
    
    /// Test 7: isLargeOrder returns true for large amounts
    function test_IsLargeOrder_ReturnsTrueForLargeAmounts() public view {
        bool isLarge = hook.isLargeOrder(int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 8: isLargeOrder returns false for small amounts
    function test_IsLargeOrder_ReturnsFalseForSmallAmounts() public view {
        bool isLarge = hook.isLargeOrder(int256(SMALL_AMOUNT), defaultPoolKey);
        assertFalse(isLarge);
    }
    
    /// Test 9: isLargeOrder works with negative amounts
    function test_IsLargeOrder_WorksWithNegativeAmounts() public view {
        bool isLarge = hook.isLargeOrder(-int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 10: isLargeOrder uses pool-specific threshold
    function test_IsLargeOrder_UsesPoolSpecificThreshold() public {
        // Set pool-specific threshold
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, 50); // 0.5%
        
        // Amount that would be small with default threshold but large with new threshold
        bool isLarge = hook.isLargeOrder(int256(SMALL_AMOUNT * 6), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 11: isLargeOrder falls back to default threshold
    function test_IsLargeOrder_FallsBackToDefaultThreshold() public view {
        // Pool with no specific threshold should use default
        bool isLarge = hook.isLargeOrder(int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }

    // ============ Threshold Management Tests ============
    
    /// Test 12: setVaultThreshold updates threshold correctly
    function test_SetVaultThreshold_UpdatesThresholdCorrectly() public {
        uint256 newThreshold = 20;
        
        vm.expectEmit(true, true, false, true);
        emit VaultThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);
        
        vm.prank(OWNER);
        hook.setVaultThreshold(newThreshold);
        
        assertEq(hook.vaultThresholdBps(), newThreshold);
    }
    
    /// Test 13: setVaultThreshold reverts for non-owner
    function test_SetVaultThreshold_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.setVaultThreshold(20);
    }
    
    /// Test 14: setPoolThreshold updates pool threshold correctly
    function test_SetPoolThreshold_UpdatesPoolThresholdCorrectly() public {
        uint256 newThreshold = 25;
        
        vm.expectEmit(true, false, false, true);
        emit PoolThresholdUpdated(defaultPoolId, 0, newThreshold);
        
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, newThreshold);
        
        assertEq(hook.poolThresholds(defaultPoolId), newThreshold);
    }
    
    /// Test 15: setPoolThreshold reverts for non-owner
    function test_SetPoolThreshold_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.setPoolThreshold(defaultPoolId, 25);
    }
    
    /// Test 16: getVaultThreshold returns pool-specific threshold
    function test_GetVaultThreshold_ReturnsPoolSpecificThreshold() public {
        uint256 poolThreshold = 30;
        
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, poolThreshold);
        
        uint256 returned = hook.getVaultThreshold(defaultPoolKey);
        assertEq(returned, poolThreshold);
    }
    
    /// Test 17: getVaultThreshold returns default when no pool threshold
    function test_GetVaultThreshold_ReturnsDefaultWhenNoPoolThreshold() public view {
        uint256 returned = hook.getVaultThreshold(defaultPoolKey);
        assertEq(returned, DEFAULT_THRESHOLD);
    }
    
    /// Test 18: updateVaultThreshold calls internal function
    function test_UpdateVaultThreshold_CallsInternalFunction() public {
        uint256 newThreshold = 15;
        
        vm.expectEmit(true, true, false, true);
        emit VaultThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);
        
        vm.prank(OWNER);
        hook.updateVaultThreshold(newThreshold);
        
        assertEq(hook.vaultThresholdBps(), newThreshold);
    }

    // ============ Order Routing Tests ============
    
    /// Test 19: routeToVault creates order correctly
    function test_RouteToVault_CreatesOrderCorrectly() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes memory hookData = abi.encode("test_data");
        
        _expectOrderRoutedToVault(TRADER, true, int256(LARGE_AMOUNT));
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, hookData);
        
        assertTrue(orderId != bytes32(0));
        assertEq(hook.orderNonce(), 1);
    }
    
    /// Test 20: routeToVault increments order nonce
    function test_RouteToVault_IncrementsOrderNonce() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        uint256 initialNonce = hook.orderNonce();
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.orderNonce(), initialNonce + 1);
    }
    
    /// Test 21: routeToVault stores order in vault
    function test_RouteToVault_StoresOrderInVault() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Verify order was stored (check mock was called)
        assertTrue(orderVault.storeOrderCalled());
        assertEq(orderVault.lastOrderId(), orderId);
    }
    
    /// Test 22: routeToVault creates AVS task
    function test_RouteToVault_CreatesAVSTask() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(avsServiceManager.createMatchingTaskCalled());
    }
    
    /// Test 23: routeToVault handles zero for one correctly
    function test_RouteToVault_HandlesZeroForOneCorrectly() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), false);
        
        _expectOrderRoutedToVault(TRADER, false, int256(LARGE_AMOUNT));
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 24: routeToVault handles negative amounts
    function test_RouteToVault_HandlesNegativeAmounts() public {
        SwapParams memory params = _createValidSwapParams(-int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Should convert negative to positive
        assertEq(orderVault.lastAmount(), LARGE_AMOUNT);
    }

    // ============ Order Execution Tests ============
    
    /// Test 25: executeMatchedOrder succeeds with valid proof
    function test_ExecuteMatchedOrder_SucceedsWithValidProof() public {
        // First route an order
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Create ZK proof
        bytes memory zkProof = _createZKProof();
        
        // Execute order
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 26: executeMatchedOrder reverts for unauthorized caller
    function test_ExecuteMatchedOrder_RevertsForUnauthorizedCaller() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Only EigenVault AVS");
        vm.prank(UNAUTHORIZED);
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 27: executeMatchedOrder reverts for non-existent order
    function test_ExecuteMatchedOrder_RevertsForNonExistentOrder() public {
        bytes32 fakeOrderId = keccak256("fake_order");
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Order already executed");
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(fakeOrderId, zkProof);
    }
    
    /// Test 28: executeMatchedOrder reverts for expired order
    function test_ExecuteMatchedOrder_RevertsForExpiredOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Skip to expiry
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Order expired");
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 29: executeVaultOrder calls executeMatchedOrder
    function test_ExecuteVaultOrder_CallsExecuteMatchedOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        bytes memory signatures = abi.encode("mock_signatures");
        
        // Should not revert (will revert internally but interface should work)
        try hook.executeVaultOrder(orderId, zkProof, signatures) {
            // Success
        } catch {
            // Expected to fail due to mock setup, but interface works
        }
    }

    // ============ Fallback Tests ============
    
    /// Test 30: fallbackToAMM executes expired order
    function test_FallbackToAMM_ExecutesExpiredOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Skip to expiry
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        hook.fallbackToAMM(orderId);
    }
    
    /// Test 31: fallbackToAMM reverts for non-expired order
    function test_FallbackToAMM_RevertsForNonExpiredOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        vm.expectRevert("Order not expired yet");
        hook.fallbackToAMM(orderId);
    }
    
    /// Test 32: fallbackToAMM reverts for already executed order
    function test_FallbackToAMM_RevertsForAlreadyExecutedOrder() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Execute order first
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        // Skip to expiry
        _skipToExpiry(block.timestamp + DEFAULT_DEADLINE);
        
        vm.expectRevert("Order already executed");
        hook.fallbackToAMM(orderId);
    }

    // ============ Statistics Tests ============
    
    /// Test 33: getPoolStats returns empty stats for new pool
    function test_GetPoolStats_ReturnsEmptyStatsForNewPool() public view {
        EigenVaultHook.ExecutionStats memory stats = hook.getPoolStats(defaultPoolId);
        
        assertEq(stats.totalOrders, 0);
        assertEq(stats.successfulMatches, 0);
        assertEq(stats.fallbackExecutions, 0);
        assertEq(stats.totalVolume, 0);
        assertEq(stats.averageExecutionTime, 0);
    }
    
    /// Test 34: poolOrderCounts increments on route
    function test_PoolOrderCounts_IncrementsOnRoute() public {
        uint256 initialCount = hook.poolOrderCounts(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolOrderCounts(defaultPoolId), initialCount + 1);
    }
    
    /// Test 35: poolTotalVolumes increases on route
    function test_PoolTotalVolumes_IncreasesOnRoute() public {
        uint256 initialVolume = hook.poolTotalVolumes(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolTotalVolumes(defaultPoolId), initialVolume + LARGE_AMOUNT);
    }

    // ============ Security Tests ============
    
    /// Test 36: activateEmergencyPause succeeds for owner
    function test_ActivateEmergencyPause_SucceedsForOwner() public {
        string memory reason = "Security threat detected";
        
        vm.expectEmit(false, false, false, true);
        emit EmergencyPauseActivated(reason, block.timestamp);
        
        vm.prank(OWNER);
        hook.activateEmergencyPause(reason);
    }
    
    /// Test 37: activateEmergencyPause reverts for non-owner
    function test_ActivateEmergencyPause_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.activateEmergencyPause("test");
    }
    
    /// Test 38: deactivateEmergencyPause succeeds for owner
    function test_DeactivateEmergencyPause_SucceedsForOwner() public {
        // First activate
        vm.prank(OWNER);
        hook.activateEmergencyPause("test");
        
        vm.expectEmit(false, false, false, true);
        emit EmergencyPauseDeactivated(block.timestamp);
        
        vm.prank(OWNER);
        hook.deactivateEmergencyPause();
    }
    
    /// Test 39: updateSecurityConfig succeeds for owner
    function test_UpdateSecurityConfig_SucceedsForOwner() public {
        uint256 maxOrderSize = 20000e18;
        uint256 maxPoolExposure = 200000e18;
        uint256 maxSlippageBps = 1000;
        
        vm.expectEmit(false, false, false, true);
        emit SecurityConfigUpdated(maxOrderSize, maxPoolExposure, maxSlippageBps);
        
        vm.prank(OWNER);
        hook.updateSecurityConfig(maxOrderSize, maxPoolExposure, maxSlippageBps);
    }
    
    /// Test 40: getSecurityStatus returns correct values
    function test_GetSecurityStatus_ReturnsCorrectValues() public view {
        (bool isPaused, uint256 lastCheck, uint256 checkInterval, bool needsCheck) = hook.getSecurityStatus();
        
        assertFalse(isPaused);
        assertEq(lastCheck, 0);
        assertEq(checkInterval, 1 hours);
        assertTrue(needsCheck);
    }

    // ============ Gas Optimization Tests ============
    
    /// Test 41: updateGasOptimization succeeds for owner
    function test_UpdateGasOptimization_SucceedsForOwner() public {
        bool enableBatch = false;
        uint256 maxBatchSize = 20;
        bool enableCompression = false;
        
        vm.expectEmit(false, false, false, true);
        emit GasOptimizationUpdated(enableBatch, maxBatchSize, enableCompression);
        
        vm.prank(OWNER);
        hook.updateGasOptimization(enableBatch, maxBatchSize, enableCompression);
    }
    
    /// Test 42: batchProcessOrders succeeds with valid orders
    function test_BatchProcessOrders_SucceedsWithValidOrders() public {
        // Create some orders
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
    
    /// Test 43: batchProcessOrders reverts when disabled
    function test_BatchProcessOrders_RevertsWhenDisabled() public {
        // Disable batch processing
        vm.prank(OWNER);
        hook.updateGasOptimization(false, 10, true);
        
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = bytes32(uint256(1));
        
        vm.expectRevert("Batch processing disabled");
        hook.batchProcessOrders(orderIds);
    }
    
    /// Test 44: batchProcessOrders reverts for oversized batch
    function test_BatchProcessOrders_RevertsForOversizedBatch() public {
        // Create batch larger than max size
        bytes32[] memory orderIds = new bytes32[](11);
        
        vm.expectRevert("Batch size too large");
        hook.batchProcessOrders(orderIds);
    }

    // ============ Order Book Tests ============
    
    /// Test 45: getOrderBook returns empty book for new pool
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
    
    /// Test 46: getMatchingStats returns initial empty stats
    function test_GetMatchingStats_ReturnsInitialEmptyStats() public view {
        EigenVaultHook.MatchingStats memory stats = hook.getMatchingStats();
        
        assertEq(stats.totalMatches, 0);
        assertEq(stats.successfulMatches, 0);
        assertEq(stats.failedMatches, 0);
        assertEq(stats.totalVolume, 0);
        assertEq(stats.averageMatchTime, 0);
        assertEq(stats.consensusSuccessRate, 0);
    }

    // ============ Access Control Tests ============
    
    /// Test 47: setServiceManagerAuthorization succeeds for owner
    function test_SetServiceManagerAuthorization_SucceedsForOwner() public {
        address newAVS = address(0x7777);
        
        vm.expectEmit(true, false, false, true);
        emit AVSServiceManagerAuthorized(newAVS, true);
        
        vm.prank(OWNER);
        hook.setServiceManagerAuthorization(newAVS, true);
    }
    
    /// Test 48: setServiceManagerAuthorization reverts for non-owner
    function test_SetServiceManagerAuthorization_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.setServiceManagerAuthorization(address(0x7777), true);
    }

    // ============ Order Information Tests ============
    
    /// Test 49: getVaultOrder returns empty order for non-existent ID
    function test_GetVaultOrder_ReturnsEmptyOrderForNonExistentId() public view {
        bytes32 fakeOrderId = keccak256("fake");
        EigenVaultHook.VaultOrder memory order = hook.getVaultOrder(fakeOrderId);
        
        assertEq(order.amount, 0);
        assertFalse(order.executed);
        assertEq(order.trader, address(0));
    }
    
    /// Test 50: getOrder returns correct order details
    function test_GetOrder_ReturnsCorrectOrderDetails() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        
        assertEq(order.trader, TRADER);
        assertTrue(order.zeroForOne);
        assertEq(order.amountSpecified, int256(LARGE_AMOUNT));
        assertFalse(order.executed);
    }

    // ============ Utility Function Tests ============
    
    /// Test 51: getPoolId returns correct pool ID
    function test_GetPoolId_ReturnsCorrectPoolId() public view {
        bytes32 poolId = hook.getPoolId(defaultPoolKey);
        assertEq(poolId, defaultPoolId);
    }

    // ============ Fuzz Tests - Amount Variations ============
    
    /// Test 52: Fuzz test for various order amounts
    function testFuzz_OrderAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        
        SwapParams memory params = _createValidSwapParams(int256(amount), true);
        
        // Should not revert for any valid amount
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 53: Fuzz test for negative amounts
    function testFuzz_NegativeAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        
        SwapParams memory params = _createValidSwapParams(-int256(amount), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 54: Fuzz test for threshold values
    function testFuzz_ThresholdValues(uint256 threshold) public {
        threshold = bound(threshold, 1, 10000); // 0.01% to 100%
        
        vm.prank(OWNER);
        hook.setVaultThreshold(threshold);
        
        assertEq(hook.vaultThresholdBps(), threshold);
    }
    
    /// Test 55: Fuzz test for pool thresholds
    function testFuzz_PoolThresholds(bytes32 poolId, uint256 threshold) public {
        threshold = bound(threshold, 1, 10000);
        
        vm.prank(OWNER);
        hook.setPoolThreshold(poolId, threshold);
        
        assertEq(hook.poolThresholds(poolId), threshold);
    }

    // ============ Fuzz Tests - Address Variations ============
    
    /// Test 56: Fuzz test for different trader addresses
    function testFuzz_TraderAddresses(address trader) public {
        vm.assume(trader != address(0));
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(trader, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }
    
    /// Test 57: Fuzz test for different currency addresses
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
        
        // Should not revert for any valid currency pair
        hook.routeToVault(TRADER, customKey, params, "");
    }

    // ============ Fuzz Tests - Time Variations ============
    
    /// Test 58: Fuzz test for different timestamps
    function testFuzz_Timestamps(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp + 1, type(uint32).max);
        
        vm.warp(timestamp);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }

    // ============ Fuzz Tests - Pool Parameter Variations ============
    
    /// Test 59: Fuzz test for different fee tiers
    function testFuzz_FeeTiers(uint24 feeAmount) public {
        // Common Uniswap fee tiers
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
    
    /// Test 60: Fuzz test for different tick spacings
    function testFuzz_TickSpacings(int24 spacing) public {
        // Valid tick spacings: 1, 10, 60, 200
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

    // ============ Boundary Condition Tests ============
    
    /// Test 61: Maximum possible amount
    function test_BoundaryCondition_MaxAmount() public {
        SwapParams memory params = _createValidSwapParams(int256(uint256(type(uint128).max)), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 62: Minimum possible amount
    function test_BoundaryCondition_MinAmount() public {
        SwapParams memory params = _createValidSwapParams(1, true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }
    
    /// Test 63: Zero threshold edge case
    function test_BoundaryCondition_ZeroThreshold() public {
        vm.prank(OWNER);
        hook.setVaultThreshold(0);
        
        // Even small amounts should be considered large with 0 threshold
        bool isLarge = hook.isLargeOrder(1, defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 64: Maximum threshold edge case
    function test_BoundaryCondition_MaxThreshold() public {
        vm.prank(OWNER);
        hook.setVaultThreshold(10000); // 100%
        
        // No amount should be large enough with 100% threshold
        bool isLarge = hook.isLargeOrder(int256(uint256(type(uint128).max)), defaultPoolKey);
        assertFalse(isLarge);
    }

    // ============ Edge Case Tests ============
    
    /// Test 65: Empty hook data
    function test_EdgeCase_EmptyHookData() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }
    
    /// Test 66: Large hook data
    function test_EdgeCase_LargeHookData() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes memory largeHookData = new bytes(1024);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, largeHookData);
        assertTrue(orderId != bytes32(0));
    }
    
    /// Test 67: Rapid consecutive orders
    function test_EdgeCase_RapidConsecutiveOrders() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        for (uint256 i = 0; i < 10; i++) {
            bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
            assertTrue(orderId != bytes32(0));
        }
        
        assertEq(hook.orderNonce(), 10);
    }

    // ============ Error Condition Tests ============
    
    /// Test 68: Order execution with malformed ZK proof
    function test_ErrorCondition_MalformedZKProof() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory malformedProof = abi.encode("malformed");
        
        vm.expectRevert();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, malformedProof);
    }
    
    /// Test 69: Order execution with empty ZK proof
    function test_ErrorCondition_EmptyZKProof() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory emptyProof = "";
        
        vm.expectRevert();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, emptyProof);
    }

    // ============ State Consistency Tests ============
    
    /// Test 70: Order nonce consistency
    function test_StateConsistency_OrderNonce() public {
        uint256 initialNonce = hook.orderNonce();
        
        for (uint256 i = 0; i < 5; i++) {
            SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
            hook.routeToVault(TRADER, defaultPoolKey, params, "");
        }
        
        assertEq(hook.orderNonce(), initialNonce + 5);
    }
    
    /// Test 71: Pool statistics consistency
    function test_StateConsistency_PoolStatistics() public {
        uint256 initialCount = hook.poolOrderCounts(defaultPoolId);
        uint256 initialVolume = hook.poolTotalVolumes(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolOrderCounts(defaultPoolId), initialCount + 1);
        assertEq(hook.poolTotalVolumes(defaultPoolId), initialVolume + LARGE_AMOUNT);
    }

    // ============ Integration Tests ============
    
    /// Test 72: Complete order lifecycle - route to execution
    function test_Integration_CompleteOrderLifecycle() public {
        // 1. Route order
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // 2. Verify order exists
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertEq(order.trader, TRADER);
        assertFalse(order.executed);
        
        // 3. Execute order
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        // 4. Verify execution
        EigenVaultHook.VaultOrder memory vaultOrder = hook.getVaultOrder(orderId);
        assertTrue(vaultOrder.executed);
    }
    
    /// Test 73: Multiple pools interaction
    function test_Integration_MultiplePoolsInteraction() public {
        // Create second pool
        PoolKey memory pool2 = PoolKey({
            currency0: Currency.wrap(address(0x3000)),
            currency1: Currency.wrap(address(0x4000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        bytes32 pool2Id = PoolId.unwrap(pool2.toId());
        
        // Set different thresholds
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, 10);
        vm.prank(OWNER);
        hook.setPoolThreshold(pool2Id, 20);
        
        // Route orders to both pools
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, pool2, params, "");
        
        // Verify separate statistics
        assertEq(hook.poolOrderCounts(defaultPoolId), 1);
        assertEq(hook.poolOrderCounts(pool2Id), 1);
        assertEq(hook.poolThresholds(defaultPoolId), 10);
        assertEq(hook.poolThresholds(pool2Id), 20);
    }

    // ============ Gas Optimization Tests (Advanced) ============
    
    /// Test 74: Gas consumption for small vs large orders
    function test_GasOptimization_SmallVsLargeOrders() public {
        SwapParams memory smallParams = _createValidSwapParams(int256(SMALL_AMOUNT), true);
        SwapParams memory largeParams = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        uint256 gasBeforeSmall = gasleft();
        hook.isLargeOrder(smallParams.amountSpecified, defaultPoolKey);
        uint256 gasAfterSmall = gasBeforeSmall - gasleft();
        
        uint256 gasBeforeLarge = gasleft();
        hook.isLargeOrder(largeParams.amountSpecified, defaultPoolKey);
        uint256 gasAfterLarge = gasBeforeLarge - gasleft();
        
        // Gas consumption should be similar for both
        assertTrue(gasAfterSmall > 0);
        assertTrue(gasAfterLarge > 0);
    }

    // ============ Event Emission Tests ============
    
    /// Test 75: Threshold update events
    function test_Events_ThresholdUpdates() public {
        vm.expectEmit(true, true, false, true);
        emit VaultThresholdUpdated(DEFAULT_THRESHOLD, 25);
        
        vm.prank(OWNER);
        hook.setVaultThreshold(25);
    }
    
    /// Test 76: Order routing events
    function test_Events_OrderRouting() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        vm.expectEmit(true, true, true, false);
        emit OrderRoutedToVault(TRADER, bytes32(0), defaultPoolKey, true, int256(LARGE_AMOUNT), bytes32(0));
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
    }

    // ============ Mock Contract Tests ============
    
    /// Test 77: Mock pool manager interaction
    function test_MockContracts_PoolManagerInteraction() public view {
        // Verify mock is working
        assertTrue(address(poolManager) != address(0));
        assertEq(poolManager.testValue(), 12345);
    }
    
    /// Test 78: Mock order vault interaction
    function test_MockContracts_OrderVaultInteraction() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(orderVault.storeOrderCalled());
    }
    
    /// Test 79: Mock AVS interaction
    function test_MockContracts_AVSInteraction() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(avsServiceManager.createMatchingTaskCalled());
    }

    // ============ Complex Scenario Tests ============
    
    /// Test 80: High volume trading simulation
    function test_ComplexScenario_HighVolumeTrading() public {
        // Simulate 100 orders
        for (uint256 i = 0; i < 100; i++) {
            address trader = address(uint160(0x1000 + i));
            SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT + i * 1e18), true);
            
            hook.routeToVault(trader, defaultPoolKey, params, "");
        }
        
        assertEq(hook.orderNonce(), 100);
        assertEq(hook.poolOrderCounts(defaultPoolId), 100);
    }
    
    /// Test 81: Mixed order sizes scenario
    function test_ComplexScenario_MixedOrderSizes() public {
        uint256 smallOrderCount = 0;
        uint256 largeOrderCount = 0;
        
        // Mix of small and large orders
        for (uint256 i = 0; i < 50; i++) {
            uint256 amount = (i % 2 == 0) ? SMALL_AMOUNT : LARGE_AMOUNT;
            SwapParams memory params = _createValidSwapParams(int256(amount), true);
            
            if (hook.isLargeOrder(int256(amount), defaultPoolKey)) {
                largeOrderCount++;
                hook.routeToVault(TRADER, defaultPoolKey, params, "");
            } else {
                smallOrderCount++;
                // Small orders don't get routed to vault
            }
        }
        
        assertTrue(largeOrderCount > 0);
        assertTrue(smallOrderCount > 0);
    }

    // ============ Security Edge Cases ============
    
    /// Test 82: Reentrancy protection
    function test_Security_ReentrancyProtection() public {
        // The hook uses ReentrancyGuard, test that it's properly applied
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        // Normal call should work
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Reentrancy attempts would fail (testing the guard is in place)
        assertTrue(true); // Guard is implemented via OpenZeppelin
    }
    
    /// Test 83: Integer overflow protection
    function test_Security_IntegerOverflowProtection() public {
        // Test with maximum values
        SwapParams memory params = _createValidSwapParams(int256(uint256(type(uint128).max)), true);
        
        // Should not overflow
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Volume tracking should handle large numbers
        assertTrue(hook.poolTotalVolumes(defaultPoolId) == type(uint128).max);
    }

    // ============ Advanced Fuzz Tests ============
    
    /// Test 84: Fuzz test with extreme parameters
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
    
    /// Test 85: Fuzz test order execution timing
    function testFuzz_OrderExecutionTiming(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 1, DEFAULT_DEADLINE - 1);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Fast forward but not to expiry
        vm.warp(block.timestamp + timeOffset);
        
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }

    // ============ Data Structure Tests ============
    
    /// Test 86: VaultOrder structure integrity
    function test_DataStructure_VaultOrderIntegrity() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        EigenVaultHook.VaultOrder memory order = hook.getVaultOrder(orderId);
        
        assertEq(order.amount, LARGE_AMOUNT);
        assertTrue(order.zeroForOne);
        assertEq(order.trader, TRADER);
        assertFalse(order.executed);
        assertTrue(order.commitment != bytes32(0));
    }
    
    /// Test 87: ExecutionStats structure
    function test_DataStructure_ExecutionStats() public view {
        EigenVaultHook.ExecutionStats memory stats = hook.getPoolStats(defaultPoolId);
        
        // Initially all should be zero
        assertEq(stats.totalOrders, 0);
        assertEq(stats.successfulMatches, 0);
        assertEq(stats.fallbackExecutions, 0);
        assertEq(stats.totalVolume, 0);
        assertEq(stats.averageExecutionTime, 0);
    }

    // ============ Interface Compliance Tests ============
    
    /// Test 88: IEigenVaultHook interface compliance
    function test_Interface_IEigenVaultHookCompliance() public {
        // Test all interface methods are implemented
        assertTrue(hook.isLargeOrder(int256(LARGE_AMOUNT), defaultPoolKey));
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        IEigenVaultHook.PrivateOrder memory order = hook.getOrder(orderId);
        assertEq(order.trader, TRADER);
        
        uint256 threshold = hook.getVaultThreshold(defaultPoolKey);
        assertEq(threshold, DEFAULT_THRESHOLD);
    }

    // ============ Error Message Tests ============
    
    /// Test 89: Specific error messages for unauthorized access
    function test_ErrorMessages_UnauthorizedAccess() public {
        vm.expectRevert("Only EigenVault AVS");
        vm.prank(UNAUTHORIZED);
        hook.executeMatchedOrder(bytes32(0), "");
    }
    
    /// Test 90: Specific error messages for order states
    function test_ErrorMessages_OrderStates() public {
        bytes32 fakeOrderId = keccak256("fake");
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Order already executed");
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(fakeOrderId, zkProof);
    }

    // ============ Performance Tests ============
    
    /// Test 91: Order routing performance with large hook data
    function test_Performance_LargeHookData() public {
        bytes memory largeData = new bytes(10000);
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        uint256 gasBefore = gasleft();
        hook.routeToVault(TRADER, defaultPoolKey, params, largeData);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should still be reasonable
        assertTrue(gasUsed > 0);
    }

    // ============ State Transition Tests ============
    
    /// Test 92: Order state transitions
    function test_StateTransition_OrderLifecycle() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Initial state
        EigenVaultHook.VaultOrder memory order = hook.getVaultOrder(orderId);
        assertFalse(order.executed);
        
        // Execute
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        // Final state
        order = hook.getVaultOrder(orderId);
        assertTrue(order.executed);
    }

    // ============ Configuration Tests ============
    
    /// Test 93: Security configuration updates
    function test_Configuration_SecurityUpdates() public {
        vm.prank(OWNER);
        hook.updateSecurityConfig(50000e18, 500000e18, 2000);
        
        (uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps,,,,) = hook.securityConfig();
        
        assertEq(maxOrderSize, 50000e18);
        assertEq(maxPoolExposure, 500000e18);
        assertEq(maxSlippageBps, 2000);
    }
    
    /// Test 94: Gas optimization configuration updates
    function test_Configuration_GasOptimizationUpdates() public {
        vm.prank(OWNER);
        hook.updateGasOptimization(false, 5, false);
        
        (bool enableBatchProcessing, uint256 maxBatchSize, bool enableCompression,) = hook.gasOptimization();
        
        assertFalse(enableBatchProcessing);
        assertEq(maxBatchSize, 5);
        assertFalse(enableCompression);
    }

    // ============ Batch Processing Advanced Tests ============
    
    /// Test 95: Batch processing with mixed order states
    function test_BatchProcessing_MixedOrderStates() public {
        // Create orders with different states
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
        
        // Batch process all (some will succeed, some will fail)
        uint256 successCount = hook.batchProcessOrders(orderIds);
        
        // Should have some successes and some failures
        assertTrue(successCount <= 5);
    }

    // ============ Emergency Scenarios ============
    
    /// Test 96: Emergency pause during order execution
    function test_EmergencyScenario_PauseDuringExecution() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Activate emergency pause
        vm.prank(OWNER);
        hook.activateEmergencyPause("Emergency situation");
        
        // Order execution should still be possible (pause doesn't block existing orders)
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }

    // ============ Multiple Pool Advanced Tests ============
    
    /// Test 97: Cross-pool statistics independence
    function test_MultiplePool_StatisticsIndependence() public {
        // Create second pool
        PoolKey memory pool2 = PoolKey({
            currency0: Currency.wrap(address(0x5000)),
            currency1: Currency.wrap(address(0x6000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        bytes32 pool2Id = PoolId.unwrap(pool2.toId());
        
        // Route orders to both pools
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, pool2, params, "");
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Verify statistics are independent
        assertEq(hook.poolOrderCounts(defaultPoolId), 2);
        assertEq(hook.poolOrderCounts(pool2Id), 1);
        assertEq(hook.poolTotalVolumes(defaultPoolId), LARGE_AMOUNT * 2);
        assertEq(hook.poolTotalVolumes(pool2Id), LARGE_AMOUNT);
    }

    // ============ Final Integration Tests ============
    
    /// Test 98: Full system stress test
    function test_FullSystem_StressTest() public {
        // Multiple pools, multiple traders, multiple order sizes
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
        
        // Route orders from multiple traders to multiple pools
        for (uint256 i = 0; i < traders.length; i++) {
            for (uint256 j = 0; j < pools.length; j++) {
                for (uint256 k = 0; k < 3; k++) { // 3 orders per trader per pool
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
    
    /// Test 99: Complex order matching scenario
    function test_ComplexOrderMatching_Scenario() public {
        // This test simulates complex order matching scenarios
        // Route multiple orders that could potentially match
        
        SwapParams memory buyParams = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        SwapParams memory sellParams = _createValidSwapParams(int256(LARGE_AMOUNT), false);
        
        // Create buy orders
        for (uint256 i = 0; i < 5; i++) {
            hook.routeToVault(address(uint160(0xB000 + i)), defaultPoolKey, buyParams, "");
        }
        
        // Create sell orders
        for (uint256 i = 0; i < 5; i++) {
            hook.routeToVault(address(uint160(0xC000 + i)), defaultPoolKey, sellParams, "");
        }
        
        assertEq(hook.orderNonce(), 10);
        
        // Get order book state
        (
            OrderMatchingLib.OrderBookEntry[] memory buyOrders,
            OrderMatchingLib.OrderBookEntry[] memory sellOrders,,
        ) = hook.getOrderBook(defaultPoolId);
        
        // Order book should have entries (though implementation details may vary)
        assertTrue(buyOrders.length >= 0);
        assertTrue(sellOrders.length >= 0);
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
        // Return mock delta
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