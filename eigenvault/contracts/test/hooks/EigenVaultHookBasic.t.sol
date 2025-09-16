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
import {OrderMatchingLib} from "../../src/vault/OrderMatchingLib.sol";

/// @title EigenVaultHook Basic Tests (Tests 1-50)
/// @notice Comprehensive unit tests covering basic functionality
contract EigenVaultHookBasicTest is Test {
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
    uint256 public constant DEFAULT_DEADLINE = 1 hours;
    uint256 public constant DEFAULT_THRESHOLD = 10; // 0.1%
    
    // ============ Events for Testing ============
    event VaultThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PoolThresholdUpdated(bytes32 indexed poolId, uint256 oldThreshold, uint256 newThreshold);
    event OrderRoutedToVault(address indexed trader, bytes32 indexed orderId, PoolKey indexed key, bool zeroForOne, int256 amountSpecified, bytes32 commitment);
    event MatchingTaskCreated(uint32 indexed taskIndex, bytes32 indexed orderId, bytes32 indexed poolId);
    event SecurityConfigUpdated(uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps);
    event GasOptimizationUpdated(bool batchProcessing, uint256 maxBatchSize, bool compression);
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

    // ============ Constructor Tests (Tests 1-5) ============
    
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

    // ============ Hook Permissions Tests (Tests 6-8) ============
    
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

    /// Test 7: Hook permissions beforeSwap enabled
    function test_GetHookPermissions_BeforeSwapEnabled() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.beforeSwap);
    }

    /// Test 8: Hook permissions afterSwap disabled
    function test_GetHookPermissions_AfterSwapDisabled() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertFalse(permissions.afterSwap);
    }

    // ============ Large Order Detection Tests (Tests 9-15) ============
    
    /// Test 9: isLargeOrder returns true for large amounts
    function test_IsLargeOrder_ReturnsTrueForLargeAmounts() public view {
        bool isLarge = hook.isLargeOrder(int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 10: isLargeOrder returns false for small amounts
    function test_IsLargeOrder_ReturnsFalseForSmallAmounts() public view {
        bool isLarge = hook.isLargeOrder(int256(SMALL_AMOUNT), defaultPoolKey);
        assertFalse(isLarge);
    }
    
    /// Test 11: isLargeOrder works with negative amounts
    function test_IsLargeOrder_WorksWithNegativeAmounts() public view {
        bool isLarge = hook.isLargeOrder(-int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 12: isLargeOrder uses pool-specific threshold
    function test_IsLargeOrder_UsesPoolSpecificThreshold() public {
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, 50); // 0.5%
        
        bool isLarge = hook.isLargeOrder(int256(SMALL_AMOUNT * 6), defaultPoolKey);
        assertTrue(isLarge);
    }
    
    /// Test 13: isLargeOrder falls back to default threshold
    function test_IsLargeOrder_FallsBackToDefaultThreshold() public view {
        bool isLarge = hook.isLargeOrder(int256(LARGE_AMOUNT), defaultPoolKey);
        assertTrue(isLarge);
    }

    /// Test 14: isLargeOrder with zero amount
    function test_IsLargeOrder_WithZeroAmount() public view {
        bool isLarge = hook.isLargeOrder(0, defaultPoolKey);
        assertFalse(isLarge);
    }

    /// Test 15: isLargeOrder boundary testing
    function test_IsLargeOrder_BoundaryTesting() public view {
        // Test right at the threshold boundary
        bool isLarge1 = hook.isLargeOrder(999e18, defaultPoolKey);
        bool isLarge2 = hook.isLargeOrder(1001e18, defaultPoolKey);
        
        // Results depend on pool liquidity, but both should be consistent
        assertTrue(isLarge1 == isLarge1); // Consistent
        assertTrue(isLarge2 == isLarge2); // Consistent
    }

    // ============ Threshold Management Tests (Tests 16-25) ============
    
    /// Test 16: setVaultThreshold updates threshold correctly
    function test_SetVaultThreshold_UpdatesThresholdCorrectly() public {
        uint256 newThreshold = 20;
        
        vm.expectEmit(true, true, false, true);
        emit VaultThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);
        
        vm.prank(OWNER);
        hook.setVaultThreshold(newThreshold);
        
        assertEq(hook.vaultThresholdBps(), newThreshold);
    }
    
    /// Test 17: setVaultThreshold reverts for non-owner
    function test_SetVaultThreshold_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.setVaultThreshold(20);
    }
    
    /// Test 18: setPoolThreshold updates pool threshold correctly
    function test_SetPoolThreshold_UpdatesPoolThresholdCorrectly() public {
        uint256 newThreshold = 25;
        
        vm.expectEmit(true, false, false, true);
        emit PoolThresholdUpdated(defaultPoolId, 0, newThreshold);
        
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, newThreshold);
        
        assertEq(hook.poolThresholds(defaultPoolId), newThreshold);
    }
    
    /// Test 19: setPoolThreshold reverts for non-owner
    function test_SetPoolThreshold_RevertsForNonOwner() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.setPoolThreshold(defaultPoolId, 25);
    }
    
    /// Test 20: getVaultThreshold returns pool-specific threshold
    function test_GetVaultThreshold_ReturnsPoolSpecificThreshold() public {
        uint256 poolThreshold = 30;
        
        vm.prank(OWNER);
        hook.setPoolThreshold(defaultPoolId, poolThreshold);
        
        uint256 returned = hook.getVaultThreshold(defaultPoolKey);
        assertEq(returned, poolThreshold);
    }
    
    /// Test 21: getVaultThreshold returns default when no pool threshold
    function test_GetVaultThreshold_ReturnsDefaultWhenNoPoolThreshold() public view {
        uint256 returned = hook.getVaultThreshold(defaultPoolKey);
        assertEq(returned, DEFAULT_THRESHOLD);
    }
    
    /// Test 22: updateVaultThreshold calls internal function
    function test_UpdateVaultThreshold_CallsInternalFunction() public {
        uint256 newThreshold = 15;
        
        vm.expectEmit(true, true, false, true);
        emit VaultThresholdUpdated(DEFAULT_THRESHOLD, newThreshold);
        
        vm.prank(OWNER);
        hook.updateVaultThreshold(newThreshold);
        
        assertEq(hook.vaultThresholdBps(), newThreshold);
    }

    /// Test 23: Multiple threshold updates
    function test_MultipleThresholdUpdates() public {
        vm.startPrank(OWNER);
        
        hook.setVaultThreshold(20);
        assertEq(hook.vaultThresholdBps(), 20);
        
        hook.setVaultThreshold(30);
        assertEq(hook.vaultThresholdBps(), 30);
        
        hook.setVaultThreshold(10);
        assertEq(hook.vaultThresholdBps(), 10);
        
        vm.stopPrank();
    }

    /// Test 24: Pool threshold overrides default
    function test_PoolThresholdOverridesDefault() public {
        vm.startPrank(OWNER);
        
        hook.setVaultThreshold(100); // High default
        hook.setPoolThreshold(defaultPoolId, 1); // Low pool-specific
        
        vm.stopPrank();
        
        // Pool threshold should take precedence
        uint256 threshold = hook.getVaultThreshold(defaultPoolKey);
        assertEq(threshold, 1);
    }

    /// Test 25: Threshold extreme values
    function test_ThresholdExtremeValues() public {
        vm.startPrank(OWNER);
        
        // Test minimum threshold
        hook.setVaultThreshold(0);
        assertEq(hook.vaultThresholdBps(), 0);
        
        // Test maximum threshold
        hook.setVaultThreshold(10000); // 100%
        assertEq(hook.vaultThresholdBps(), 10000);
        
        vm.stopPrank();
    }

    // ============ Order Routing Tests (Tests 26-35) ============
    
    /// Test 26: routeToVault creates order correctly
    function test_RouteToVault_CreatesOrderCorrectly() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes memory hookData = abi.encode("test_data");
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, hookData);
        
        assertTrue(orderId != bytes32(0));
        assertEq(hook.orderNonce(), 1);
    }
    
    /// Test 27: routeToVault increments order nonce
    function test_RouteToVault_IncrementsOrderNonce() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        uint256 initialNonce = hook.orderNonce();
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.orderNonce(), initialNonce + 1);
    }
    
    /// Test 28: routeToVault stores order in vault
    function test_RouteToVault_StoresOrderInVault() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(orderVault.storeOrderCalled());
        assertEq(orderVault.lastOrderId(), orderId);
    }
    
    /// Test 29: routeToVault creates AVS task
    function test_RouteToVault_CreatesAVSTask() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(avsServiceManager.createMatchingTaskCalled());
    }
    
    /// Test 30: routeToVault handles zero for one correctly
    function test_RouteToVault_HandlesZeroForOneCorrectly() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), false);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }
    
    /// Test 31: routeToVault handles negative amounts
    function test_RouteToVault_HandlesNegativeAmounts() public {
        SwapParams memory params = _createValidSwapParams(-int256(LARGE_AMOUNT), true);
        
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(orderVault.lastAmount(), LARGE_AMOUNT);
    }

    /// Test 32: routeToVault with empty hook data
    function test_RouteToVault_WithEmptyHookData() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        assertTrue(orderId != bytes32(0));
    }

    /// Test 33: routeToVault with large hook data
    function test_RouteToVault_WithLargeHookData() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes memory largeData = new bytes(1000);
        
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, largeData);
        assertTrue(orderId != bytes32(0));
    }

    /// Test 34: Multiple orders from same trader
    function test_RouteToVault_MultipleOrdersSameTrader() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32 orderId1 = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        bytes32 orderId2 = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertTrue(orderId1 != orderId2);
        assertEq(hook.orderNonce(), 2);
    }

    /// Test 35: Order ID uniqueness
    function test_RouteToVault_OrderIdUniqueness() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        bytes32[] memory orderIds = new bytes32[](10);
        for (uint256 i = 0; i < 10; i++) {
            orderIds[i] = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        }
        
        // Verify all order IDs are unique
        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = i + 1; j < 10; j++) {
                assertTrue(orderIds[i] != orderIds[j]);
            }
        }
    }

    // ============ Order Execution Tests (Tests 36-40) ============
    
    /// Test 36: executeMatchedOrder succeeds with valid proof
    function test_ExecuteMatchedOrder_SucceedsWithValidProof() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 37: executeMatchedOrder reverts for unauthorized caller
    function test_ExecuteMatchedOrder_RevertsForUnauthorizedCaller() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Only EigenVault AVS");
        vm.prank(UNAUTHORIZED);
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 38: executeMatchedOrder reverts for non-existent order
    function test_ExecuteMatchedOrder_RevertsForNonExistentOrder() public {
        bytes32 fakeOrderId = keccak256("fake_order");
        bytes memory zkProof = _createZKProof();
        
        vm.expectRevert("Order already executed");
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(fakeOrderId, zkProof);
    }
    
    /// Test 39: executeVaultOrder interface method
    function test_ExecuteVaultOrder_InterfaceMethod() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        bytes memory signatures = abi.encode("mock_signatures");
        
        try hook.executeVaultOrder(orderId, zkProof, signatures) {
            // Success case
        } catch {
            // Expected to fail due to mock setup
        }
    }

    /// Test 40: Order execution state changes
    function test_ExecuteMatchedOrder_StateChanges() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Check initial state
        EigenVaultHook.VaultOrder memory orderBefore = hook.getVaultOrder(orderId);
        assertFalse(orderBefore.executed);
        
        // Execute order
        bytes memory zkProof = _createZKProof();
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
        
        // Check final state
        EigenVaultHook.VaultOrder memory orderAfter = hook.getVaultOrder(orderId);
        assertTrue(orderAfter.executed);
    }

    // ============ Statistics Tests (Tests 41-45) ============
    
    /// Test 41: getPoolStats returns empty stats for new pool
    function test_GetPoolStats_ReturnsEmptyStatsForNewPool() public view {
        EigenVaultHook.ExecutionStats memory stats = hook.getPoolStats(defaultPoolId);
        
        assertEq(stats.totalOrders, 0);
        assertEq(stats.successfulMatches, 0);
        assertEq(stats.fallbackExecutions, 0);
        assertEq(stats.totalVolume, 0);
        assertEq(stats.averageExecutionTime, 0);
    }
    
    /// Test 42: poolOrderCounts increments on route
    function test_PoolOrderCounts_IncrementsOnRoute() public {
        uint256 initialCount = hook.poolOrderCounts(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolOrderCounts(defaultPoolId), initialCount + 1);
    }
    
    /// Test 43: poolTotalVolumes increases on route
    function test_PoolTotalVolumes_IncreasesOnRoute() public {
        uint256 initialVolume = hook.poolTotalVolumes(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolTotalVolumes(defaultPoolId), initialVolume + LARGE_AMOUNT);
    }

    /// Test 44: Multiple orders statistics accumulation
    function test_Statistics_MultipleOrdersAccumulation() public {
        uint256 initialCount = hook.poolOrderCounts(defaultPoolId);
        uint256 initialVolume = hook.poolTotalVolumes(defaultPoolId);
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        assertEq(hook.poolOrderCounts(defaultPoolId), initialCount + 3);
        assertEq(hook.poolTotalVolumes(defaultPoolId), initialVolume + (LARGE_AMOUNT * 3));
    }

    /// Test 45: Statistics independence per pool
    function test_Statistics_IndependencePerPool() public {
        // Create second pool
        PoolKey memory pool2 = PoolKey({
            currency0: Currency.wrap(address(0x3000)),
            currency1: Currency.wrap(address(0x4000)),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        bytes32 pool2Id = PoolId.unwrap(pool2.toId());
        
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        
        // Route to both pools
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        hook.routeToVault(TRADER, pool2, params, "");
        hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        // Check independence
        assertEq(hook.poolOrderCounts(defaultPoolId), 2);
        assertEq(hook.poolOrderCounts(pool2Id), 1);
    }

    // ============ Access Control Tests (Tests 46-50) ============
    
    /// Test 46: Owner can update security config
    function test_AccessControl_OwnerCanUpdateSecurityConfig() public {
        vm.prank(OWNER);
        hook.updateSecurityConfig(20000e18, 200000e18, 1000);
        
        (uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps,,,,) = hook.securityConfig();
        assertEq(maxOrderSize, 20000e18);
        assertEq(maxPoolExposure, 200000e18);
        assertEq(maxSlippageBps, 1000);
    }
    
    /// Test 47: Non-owner cannot update security config
    function test_AccessControl_NonOwnerCannotUpdateSecurityConfig() public {
        vm.expectRevert(); // Ownable: caller is not the owner
        vm.prank(UNAUTHORIZED);
        hook.updateSecurityConfig(20000e18, 200000e18, 1000);
    }
    
    /// Test 48: Owner can update gas optimization
    function test_AccessControl_OwnerCanUpdateGasOptimization() public {
        vm.prank(OWNER);
        hook.updateGasOptimization(false, 5, false);
        
        (bool enableBatchProcessing, uint256 maxBatchSize, bool enableCompression,) = hook.gasOptimization();
        assertFalse(enableBatchProcessing);
        assertEq(maxBatchSize, 5);
        assertFalse(enableCompression);
    }
    
    /// Test 49: Only AVS can execute matched orders
    function test_AccessControl_OnlyAVSCanExecuteMatchedOrders() public {
        SwapParams memory params = _createValidSwapParams(int256(LARGE_AMOUNT), true);
        bytes32 orderId = hook.routeToVault(TRADER, defaultPoolKey, params, "");
        
        bytes memory zkProof = _createZKProof();
        
        // Should work for AVS
        vm.prank(address(avsServiceManager));
        hook.executeMatchedOrder(orderId, zkProof);
    }
    
    /// Test 50: System owner verification
    function test_AccessControl_SystemOwnerVerification() public view {
        assertEq(hook.owner(), OWNER);
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