// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVSServiceManager.sol";
import "../../src/vault/OrderVault.sol";
import "../../src/hooks/EigenVaultHook.sol";
import "../hooks/MockPoolManager.sol";
import "../core/MockERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import "../mocks/EigenLayerMocks.sol";

/// @title MultiChainIntegrationTests
/// @notice Tests for multi-chain scenarios, cross-protocol integration, and bridge-like functionality
contract MultiChainIntegrationTests is Test {
    EigenVaultAVSServiceManager public mainnetAVS;
    EigenVaultAVSServiceManager public l2AVS;
    OrderVault public mainnetOrderVault;
    OrderVault public l2OrderVault;
    MockPoolManager public mainnetPoolManager;
    MockPoolManager public l2PoolManager;
    MockERC20 public mainnetToken;
    MockERC20 public l2Token;
    
    // Mock contracts
    MockAVSDirectory public mockAVSDirectory;
    MockRewardsCoordinator public mockRewardsCoordinator;
    MockSlashingRegistryCoordinator public mockRegistryCoordinator;
    MockStakeRegistry public mockStakeRegistry;
    MockPermissionController public mockPermissionController;
    MockAllocationManager public mockAllocationManager;
    
    address public constant OWNER = address(0x1);
    address public constant MAINNET_OPERATOR = address(0x10);
    address public constant L2_OPERATOR = address(0x11);
    address public constant CROSS_CHAIN_USER = address(0x20);
    address public constant BRIDGE_RELAYER = address(0x30);
    
    uint256 public constant MIN_STAKE = 32 ether;
    uint256 public constant CHAIN_ID_MAINNET = 1;
    uint256 public constant CHAIN_ID_L2 = 10;

    // Events for cross-chain communication
    event CrossChainOrderCreated(bytes32 indexed orderId, uint256 sourceChain, uint256 targetChain);
    event CrossChainOrderExecuted(bytes32 indexed orderId, uint256 sourceChain, uint256 targetChain);
    event BridgeMessageSent(bytes32 indexed messageId, uint256 targetChain, bytes data);
    event BridgeMessageReceived(bytes32 indexed messageId, uint256 sourceChain, bytes data);
    event ChainSyncCompleted(uint256 chainId, uint256 blockNumber);

    function setUp() public {
        // Deploy mock contracts
        mockAVSDirectory = new MockAVSDirectory();
        mockRewardsCoordinator = new MockRewardsCoordinator();
        mockRegistryCoordinator = new MockSlashingRegistryCoordinator();
        mockStakeRegistry = new MockStakeRegistry();
        mockPermissionController = new MockPermissionController();
        mockAllocationManager = new MockAllocationManager();
        
        // Deploy mainnet contracts
        vm.startPrank(OWNER);
        mainnetAVS = new EigenVaultAVSServiceManager(
            IAVSDirectory(address(mockAVSDirectory)),
            IRewardsCoordinator(address(mockRewardsCoordinator)),
            ISlashingRegistryCoordinator(address(mockRegistryCoordinator)),
            IStakeRegistry(address(mockStakeRegistry)),
            IPermissionController(address(mockPermissionController)),
            IAllocationManager(address(mockAllocationManager))
        );
        mainnetOrderVault = new OrderVault();
        mainnetPoolManager = new MockPoolManager();
        mainnetToken = new MockERC20("MainnetToken", "MNET", 18);
        
        // Deploy L2 contracts (simulating different chain)
        l2AVS = new EigenVaultAVSServiceManager(
            IAVSDirectory(address(mockAVSDirectory)),
            IRewardsCoordinator(address(mockRewardsCoordinator)),
            ISlashingRegistryCoordinator(address(mockRegistryCoordinator)),
            IStakeRegistry(address(mockStakeRegistry)),
            IPermissionController(address(mockPermissionController)),
            IAllocationManager(address(mockAllocationManager))
        );
        l2OrderVault = new OrderVault();
        l2PoolManager = new MockPoolManager();
        l2Token = new MockERC20("L2Token", "L2TK", 18);
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(MAINNET_OPERATOR, 100 ether);
        vm.deal(L2_OPERATOR, 100 ether);
        vm.deal(CROSS_CHAIN_USER, 100 ether);
        vm.deal(BRIDGE_RELAYER, 100 ether);
        
        // Mint tokens
        mainnetToken.mint(CROSS_CHAIN_USER, 1000000 ether);
        l2Token.mint(CROSS_CHAIN_USER, 1000000 ether);
    }
    
    function testCrossChainOperatorRegistration() public {
        // Register operator on mainnet
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.registerOperator{value: MIN_STAKE}("mainnet_operator");
        assertTrue(mainnetAVS.isRegisteredOperator(MAINNET_OPERATOR));
        
        // Register same operator on L2 (different stake requirements possible)
        vm.prank(MAINNET_OPERATOR);
        l2AVS.registerOperator{value: MIN_STAKE}("l2_operator");
        assertTrue(l2AVS.isRegisteredOperator(MAINNET_OPERATOR));
        
        // Verify operator can operate on both chains
        assertEq(mainnetAVS.totalOperators(), 1);
        assertEq(l2AVS.totalOperators(), 1);
        
        // Test cross-chain operator performance tracking
        bytes32 mainnetTask = keccak256("mainnet_task");
        bytes32 l2Task = keccak256("l2_task");
        
        vm.prank(OWNER);
        uint32 mainnetTaskIndex = mainnetAVS.createTask(mainnetTask, "mainnet_data", block.timestamp + 2 hours);
        vm.prank(OWNER);
        uint32 l2TaskIndex = l2AVS.createTask(l2Task, "l2_data", block.timestamp + 2 hours);
        
        // Complete tasks on both chains
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(mainnetTaskIndex, "mainnet_response");
        
        vm.prank(MAINNET_OPERATOR);
        l2AVS.submitTaskResponse(l2TaskIndex, "l2_response");
        
        // Verify performance tracking on both chains
        (uint256 mainnetAssigned, uint256 mainnetCompleted,,) = mainnetAVS.getOperatorPerformance(MAINNET_OPERATOR);
        (uint256 l2Assigned, uint256 l2Completed,,) = l2AVS.getOperatorPerformance(MAINNET_OPERATOR);
        
        assertEq(mainnetAssigned, 1);
        assertEq(mainnetCompleted, 1);
        assertEq(l2Assigned, 1);
        assertEq(l2Completed, 1);
    }
    
    function testCrossChainOrderRouting() public {
        // Setup operators on both chains
        _setupCrossChainOperators();
        
        // Create order on mainnet that needs execution on L2
        bytes32 crossChainOrderId = keccak256("cross_chain_order");
        bytes memory crossChainData = abi.encode(
            "cross_chain",
            CROSS_CHAIN_USER,
            CHAIN_ID_L2, // Target chain
            1000 ether
        );
        
        vm.prank(OWNER);
        mainnetOrderVault.authorizeHook(CROSS_CHAIN_USER, true);
        vm.prank(CROSS_CHAIN_USER);
        mainnetOrderVault.storeOrder(
            crossChainOrderId,
            CROSS_CHAIN_USER,
            crossChainData,
            block.timestamp + 4 hours // Longer deadline for cross-chain
        );
        
        // Create corresponding task for cross-chain routing
        bytes32 routingTaskId = keccak256("routing_task");
        vm.prank(OWNER);
        uint32 routingTaskIndex = mainnetAVS.createTask(
            routingTaskId,
            abi.encode("route_to_l2", crossChainOrderId, CHAIN_ID_L2),
            block.timestamp + 3 hours
        );
        
        // Operator processes routing task
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(routingTaskIndex, abi.encode("routed_to_l2", crossChainOrderId));
        
        // Simulate bridge message to L2
        bytes32 bridgeMessageId = keccak256(abi.encode("bridge_msg", crossChainOrderId));
        emit BridgeMessageSent(bridgeMessageId, CHAIN_ID_L2, crossChainData);
        
        // Process on L2 side
        vm.prank(OWNER);
        l2OrderVault.authorizeHook(BRIDGE_RELAYER, true);
        vm.prank(BRIDGE_RELAYER);
        l2OrderVault.storeOrder(
            crossChainOrderId,
            CROSS_CHAIN_USER,
            crossChainData,
            block.timestamp + 2 hours
        );
        
        // Verify order exists on both chains
        (bool mainnetExists,) = mainnetOrderVault.isValidOrder(crossChainOrderId);
        (bool l2Exists,) = l2OrderVault.isValidOrder(crossChainOrderId);
        assertTrue(mainnetExists);
        assertTrue(l2Exists);
        
        emit CrossChainOrderCreated(crossChainOrderId, CHAIN_ID_MAINNET, CHAIN_ID_L2);
    }
    
    function testCrossChainConsensus() public {
        _setupCrossChainOperators();
        
        // Create task requiring consensus across chains
        bytes32 consensusTaskId = keccak256("cross_chain_consensus");
        bytes memory consensusData = abi.encode(
            "multi_chain_consensus",
            "price_oracle_update",
            1500 ether // New price
        );
        
        // Create task on mainnet
        vm.prank(OWNER);
        uint32 mainnetTaskIndex = mainnetAVS.createTask(
            consensusTaskId,
            consensusData,
            block.timestamp + 1 hours
        );
        
        // Create corresponding task on L2
        vm.prank(OWNER);
        uint32 l2TaskIndex = l2AVS.createTask(
            consensusTaskId,
            consensusData,
            block.timestamp + 1 hours
        );
        
        // Operators submit responses on both chains
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(mainnetTaskIndex, abi.encode("consensus_agree", 1500 ether));
        
        vm.prank(L2_OPERATOR);
        l2AVS.submitTaskResponse(l2TaskIndex, abi.encode("consensus_agree", 1500 ether));
        
        // Verify consensus reached on both chains
        (,,,bool mainnetCompleted) = mainnetAVS.getTask(mainnetTaskIndex);
        (,,,bool l2Completed) = l2AVS.getTask(l2TaskIndex);
        assertTrue(mainnetCompleted);
        assertTrue(l2Completed);
    }
    
    function testCrossChainArbitrage() public {
        _setupCrossChainOperators();
        
        // Setup arbitrage scenario - price difference between chains
        bytes32 arbitrageOrderId = keccak256("arbitrage_opportunity");
        
        // User wants to exploit price difference
        bytes memory arbitrageData = abi.encode(
            "arbitrage",
            "ETH/USDC",
            1000 ether, // Amount
            3000 ether,  // Mainnet price
            2950 ether   // L2 price (cheaper)
        );
        
        // Create order on mainnet (sell at high price)
        vm.prank(OWNER);
        mainnetOrderVault.authorizeHook(CROSS_CHAIN_USER, true);
        vm.prank(CROSS_CHAIN_USER);
        mainnetOrderVault.storeOrder(
            arbitrageOrderId,
            CROSS_CHAIN_USER,
            arbitrageData,
            block.timestamp + 2 hours // Adequate deadline for arbitrage
        );
        
        // Create corresponding buy order on L2 (buy at low price)
        bytes32 l2ArbitrageOrderId = keccak256("l2_arbitrage_buy");
        vm.prank(OWNER);
        l2OrderVault.authorizeHook(CROSS_CHAIN_USER, true);
        vm.prank(CROSS_CHAIN_USER);
        l2OrderVault.storeOrder(
            l2ArbitrageOrderId,
            CROSS_CHAIN_USER,
            abi.encode("arbitrage_buy", 1000 ether, 2950 ether),
            block.timestamp + 2 hours
        );
        
        // Create arbitrage execution task
        bytes32 arbitrageTaskId = keccak256("execute_arbitrage");
        vm.prank(OWNER);
        uint32 arbitrageTaskIndex = mainnetAVS.createTask(
            arbitrageTaskId,
            abi.encode("cross_chain_arbitrage", arbitrageOrderId, l2ArbitrageOrderId),
            block.timestamp + 2 hours
        );
        
        // Operator executes arbitrage
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(
            arbitrageTaskIndex,
            abi.encode("arbitrage_executed", 50 ether) // Profit: 50 ETH
        );
        
        // Verify arbitrage tracking
        (,,,bool completed) = mainnetAVS.getTask(arbitrageTaskIndex);
        assertTrue(completed);
    }
    
    function testCrossChainLiquidityBridging() public {
        _setupCrossChainOperators();
        
        // User has liquidity on mainnet but needs it on L2
        bytes32 liquidityBridgeId = keccak256("liquidity_bridge");
        uint256 bridgeAmount = 10000 ether;
        
        // Create bridge request order
        bytes memory bridgeData = abi.encode(
            "liquidity_bridge",
            CROSS_CHAIN_USER,
            CHAIN_ID_MAINNET, // Source
            CHAIN_ID_L2,      // Destination
            bridgeAmount
        );
        
        vm.prank(OWNER);
        mainnetOrderVault.authorizeHook(CROSS_CHAIN_USER, true);
        vm.prank(CROSS_CHAIN_USER);
        mainnetOrderVault.storeOrder(
            liquidityBridgeId,
            CROSS_CHAIN_USER,
            bridgeData,
            block.timestamp + 2 hours
        );
        
        // Create bridge execution task
        bytes32 bridgeTaskId = keccak256("execute_bridge");
        vm.prank(OWNER);
        uint32 bridgeTaskIndex = mainnetAVS.createTask(
            bridgeTaskId,
            abi.encode("process_bridge", liquidityBridgeId, bridgeAmount),
            block.timestamp + 1.5 hours
        );
        
        // Operator processes bridge request
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(
            bridgeTaskIndex,
            abi.encode("bridge_initiated", liquidityBridgeId, CHAIN_ID_L2)
        );
        
        // Simulate bridge completion on L2
        bytes32 l2BridgeOrderId = keccak256("l2_bridge_completion");
        vm.prank(OWNER);
        l2OrderVault.authorizeHook(BRIDGE_RELAYER, true);
        vm.prank(BRIDGE_RELAYER);
        l2OrderVault.storeOrder(
            l2BridgeOrderId,
            CROSS_CHAIN_USER,
            abi.encode("bridge_complete", bridgeAmount),
            block.timestamp + 1 hours + 5 minutes
        );
        
        // Verify bridge tracking on both chains
        (bool mainnetExists,) = mainnetOrderVault.isValidOrder(liquidityBridgeId);
        (bool l2Exists,) = l2OrderVault.isValidOrder(l2BridgeOrderId);
        assertTrue(mainnetExists);
        assertTrue(l2Exists);
    }
    
    function testCrossChainFailover() public {
        _setupCrossChainOperators();
        
        // Create task on mainnet
        bytes32 failoverTaskId = keccak256("failover_task");
        vm.prank(OWNER);
        uint32 mainnetTaskIndex = mainnetAVS.createTask(
            failoverTaskId,
            "mainnet_primary_execution",
            block.timestamp + 1 hours
        );
        
        // Simulate mainnet failure by slashing operator
        vm.prank(OWNER);
        mainnetAVS.slashOperator(MAINNET_OPERATOR, MIN_STAKE, "Simulated failure");
        
        // Create failover task on L2
        vm.prank(OWNER);
        uint32 l2TaskIndex = l2AVS.createTask(
            failoverTaskId,
            "l2_failover_execution", 
            block.timestamp + 45 minutes
        );
        
        // L2 operator handles failover
        vm.prank(L2_OPERATOR);
        l2AVS.submitTaskResponse(l2TaskIndex, "failover_complete");
        
        // Verify failover worked
        (,,,bool mainnetCompleted) = mainnetAVS.getTask(mainnetTaskIndex);
        (,,,bool l2Completed) = l2AVS.getTask(l2TaskIndex);
        assertFalse(mainnetCompleted); // Mainnet task failed
        assertTrue(l2Completed);       // L2 picked up the task
    }
    
    function testCrossChainDataSync() public {
        _setupCrossChainOperators();
        
        // Create data that needs to be synced across chains
        bytes32[] memory syncItems = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            syncItems[i] = keccak256(abi.encode("sync_item", i));
        }
        
        // Store data on mainnet
        for (uint256 i = 0; i < 5; i++) {
            bytes memory syncData = abi.encode("sync_data", i, block.timestamp);
            vm.prank(OWNER);
            mainnetOrderVault.authorizeHook(BRIDGE_RELAYER, true);
            vm.prank(BRIDGE_RELAYER);
            mainnetOrderVault.storeOrder(
                syncItems[i],
                BRIDGE_RELAYER,
                syncData,
                block.timestamp + 4 hours
            );
        }
        
        assertEq(mainnetOrderVault.totalOrders(), 5);
        
        // Create sync task
        bytes32 syncTaskId = keccak256("cross_chain_sync");
        vm.prank(OWNER);
        uint32 syncTaskIndex = mainnetAVS.createTask(
            syncTaskId,
            abi.encode("sync_to_l2", syncItems),
            block.timestamp + 2 hours
        );
        
        // Execute sync
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(syncTaskIndex, "sync_initiated");
        
        // Simulate sync completion on L2
        for (uint256 i = 0; i < 5; i++) {
            bytes memory syncData = abi.encode("sync_data", i, block.timestamp);
            vm.prank(OWNER);
            l2OrderVault.authorizeHook(BRIDGE_RELAYER, true);
            vm.prank(BRIDGE_RELAYER);
            l2OrderVault.storeOrder(
                syncItems[i],
                BRIDGE_RELAYER,
                syncData,
                block.timestamp + 3 hours
            );
        }
        
        // Verify sync completed
        assertEq(l2OrderVault.totalOrders(), 5);
        emit ChainSyncCompleted(CHAIN_ID_L2, block.number);
    }
    
    function testCrossChainRewardDistribution() public {
        _setupCrossChainOperators();
        
        // Create tasks on both chains
        bytes32 mainnetTaskId = keccak256("mainnet_reward_task");
        bytes32 l2TaskId = keccak256("l2_reward_task");
        
        vm.prank(OWNER);
        uint32 mainnetTaskIndex = mainnetAVS.createTask(mainnetTaskId, "mainnet_work", block.timestamp + 2 hours);
        vm.prank(OWNER);
        uint32 l2TaskIndex = l2AVS.createTask(l2TaskId, "l2_work", block.timestamp + 2 hours);
        
        // Complete tasks
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(mainnetTaskIndex, "mainnet_result");
        
        vm.prank(L2_OPERATOR);
        l2AVS.submitTaskResponse(l2TaskIndex, "l2_result");
        
        // Distribute rewards on both chains
        vm.deal(address(mainnetAVS), 10 ether);
        vm.deal(address(l2AVS), 5 ether);
        
        vm.prank(OWNER);
        mainnetAVS.distributeReward(MAINNET_OPERATOR, 2 ether);
        
        vm.prank(OWNER);
        l2AVS.distributeReward(L2_OPERATOR, 1 ether);
        
        // Verify cross-chain reward tracking
        uint256 mainnetRewards = mainnetAVS.getTotalRewards(MAINNET_OPERATOR);
        uint256 l2Rewards = l2AVS.getTotalRewards(L2_OPERATOR);
        
        assertEq(mainnetRewards, 2 ether);
        assertEq(l2Rewards, 1 ether);
        
        // Test cross-chain reward aggregation (would be done off-chain in practice)
        uint256 totalCrossChainRewards = mainnetRewards + l2Rewards;
        assertEq(totalCrossChainRewards, 3 ether);
    }
    
    function testCrossChainEmergencyResponse() public {
        _setupCrossChainOperators();
        
        // Trigger emergency on mainnet
        vm.prank(OWNER);
        mainnetAVS.emergencyPause();
        assertTrue(mainnetAVS.paused());
        
        // Create emergency response task on L2
        bytes32 emergencyTaskId = keccak256("emergency_response");
        vm.prank(OWNER);
        uint32 emergencyTaskIndex = l2AVS.createTask(
            emergencyTaskId,
            abi.encode("handle_mainnet_emergency", CHAIN_ID_MAINNET),
            block.timestamp + 2 hours
        );
        
        // L2 operator handles emergency
        vm.prank(L2_OPERATOR);
        l2AVS.submitTaskResponse(emergencyTaskIndex, "emergency_handled");
        
        // Verify emergency response
        (,,,bool completed) = l2AVS.getTask(emergencyTaskIndex);
        assertTrue(completed);
        
        // Resume operations on mainnet
        vm.prank(OWNER);
        mainnetAVS.emergencyUnpause();
        assertFalse(mainnetAVS.paused());
        
        // Create recovery sync task
        bytes32 recoveryTaskId = keccak256("recovery_sync");
        vm.prank(OWNER);
        uint32 recoveryTaskIndex = mainnetAVS.createTask(
            recoveryTaskId,
            "sync_with_l2_during_emergency",
            block.timestamp + 1 hours
        );
        
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.submitTaskResponse(recoveryTaskIndex, "recovery_complete");
        
        (,,,bool recoveryCompleted) = mainnetAVS.getTask(recoveryTaskIndex);
        assertTrue(recoveryCompleted);
    }
    
    function testCrossChainLoadBalancing() public {
        _setupCrossChainOperators();
        
        // Create high load scenario on mainnet
        uint256 highLoadTasks = 50;
        uint256 completedOnMainnet = 0;
        uint256 routedToL2 = 0;
        
        for (uint256 i = 0; i < highLoadTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("load_task", i));
            
            // Simulate load balancing decision (route some to L2)
            if (i % 3 == 0) {
                // Route to L2
                vm.prank(OWNER);
                uint32 l2TaskIndex = l2AVS.createTask(taskId, "l2_load_task", block.timestamp + 2 hours);
                vm.prank(L2_OPERATOR);
                l2AVS.submitTaskResponse(l2TaskIndex, "l2_result");
                routedToL2++;
            } else {
                // Process on mainnet
                vm.prank(OWNER);
                uint32 mainnetTaskIndex = mainnetAVS.createTask(taskId, "mainnet_load_task", block.timestamp + 2 hours);
                vm.prank(MAINNET_OPERATOR);
                mainnetAVS.submitTaskResponse(mainnetTaskIndex, "mainnet_result");
                completedOnMainnet++;
            }
        }
        
        // Verify load distribution
        assertTrue(routedToL2 > 0);
        assertTrue(completedOnMainnet > 0);
        assertEq(routedToL2 + completedOnMainnet, highLoadTasks);
        
        // Verify performance across chains
        (uint256 mainnetAssigned, uint256 mainnetCompleted,,) = mainnetAVS.getOperatorPerformance(MAINNET_OPERATOR);
        (uint256 l2Assigned, uint256 l2Completed,,) = l2AVS.getOperatorPerformance(L2_OPERATOR);
        
        assertEq(mainnetCompleted, completedOnMainnet);
        assertEq(l2Completed, routedToL2);
    }
    
    // Helper function
    function _setupCrossChainOperators() internal {
        // Register operators on both chains
        vm.prank(MAINNET_OPERATOR);
        mainnetAVS.registerOperator{value: MIN_STAKE}("mainnet_operator");
        
        vm.prank(L2_OPERATOR);
        l2AVS.registerOperator{value: MIN_STAKE}("l2_operator");
        
        // Setup cross-chain authorizations (owner only)
        vm.prank(OWNER);
        mainnetOrderVault.authorizeHook(BRIDGE_RELAYER, true);
        
        vm.prank(OWNER);
        l2OrderVault.authorizeHook(BRIDGE_RELAYER, true);
    }
}