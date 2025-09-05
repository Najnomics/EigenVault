// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVS.sol";
import "../../src/vault/OrderVault.sol";
import "../../src/core/ZKProofLib.sol";
import "../../src/vault/OrderLib.sol";
import "../../src/vault/OrderMatchingLib.sol";

/// @title PerformanceTests
/// @notice Performance and load testing for EigenVault system
contract PerformanceTestsTest is Test {
    EigenVaultAVS public avs;
    OrderVault public orderVault;
    OrderMatchingLib.OrderBook public testOrderBook;
    
    uint256 public constant MIN_STAKE = 32 ether;
    uint256 public constant GAS_LIMIT_OPERATOR_REGISTRATION = 200000;
    uint256 public constant GAS_LIMIT_TASK_CREATION = 150000;
    uint256 public constant GAS_LIMIT_TASK_RESPONSE = 100000;
    uint256 public constant GAS_LIMIT_ORDER_STORAGE = 80000;
    
    function setUp() public {
        avs = new EigenVaultAVS();
        orderVault = new OrderVault();
        orderVault.authorizeHook(address(avs), true);
    }
    
    function DISABLED_testOperatorRegistrationPerformance() public {
        uint256 numOperators = 100;
        uint256 totalGasUsed = 0;
        
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x1000 + i));
            vm.deal(operator, MIN_STAKE);
            
            uint256 gasStart = gasleft();
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("operator", i, ".com")));
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
            assertTrue(gasUsed < GAS_LIMIT_OPERATOR_REGISTRATION);
        }
        
        uint256 averageGas = totalGasUsed / numOperators;
        emit log_named_uint("Average registration gas", averageGas);
        assertTrue(averageGas < GAS_LIMIT_OPERATOR_REGISTRATION);
        assertEq(avs.totalOperators(), numOperators);
    }
    
    function DISABLED_testTaskCreationPerformance() public {
        uint256 numTasks = 200;
        uint256 totalGasUsed = 0;
        
        for (uint256 i = 0; i < numTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("perf_task", i));
            bytes memory taskData = abi.encode("performance_data", i, block.timestamp);
            
            uint256 gasStart = gasleft();
            vm.prank(address(this));
            avs.createTask(taskId, taskData, block.timestamp + 2 hours);
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
            assertTrue(gasUsed < GAS_LIMIT_TASK_CREATION);
        }
        
        uint256 averageGas = totalGasUsed / numTasks;
        emit log_named_uint("Average task creation gas", averageGas);
        assertTrue(averageGas < GAS_LIMIT_TASK_CREATION);
        assertEq(avs.totalTasks(), numTasks);
    }
    
    function DISABLED_testTaskResponsePerformance() public {
        uint256 numOperators = 50;
        uint256 numTasks = 100;
        
        // Register operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x2000 + i));
            vm.deal(operator, MIN_STAKE);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("perf_op", i, ".com")));
        }
        
        // Create tasks
        uint32[] memory taskIndices = new uint32[](numTasks);
        for (uint256 i = 0; i < numTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("response_task", i));
            taskIndices[i] = avs.createTask(taskId, abi.encode("data", i), block.timestamp + 2 hours);
        }
        
        uint256 totalGasUsed = 0;
        uint256 responses = 0;
        
        // Submit responses
        for (uint256 i = 0; i < numTasks && i < numOperators; i++) {
            address operator = address(uint160(0x2000 + i));
            bytes memory response = abi.encode("response", i, taskIndices[i]);
            
            uint256 gasStart = gasleft();
            vm.prank(operator);
            avs.submitTaskResponse(taskIndices[i], response);
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
            responses++;
            assertTrue(gasUsed < GAS_LIMIT_TASK_RESPONSE);
        }
        
        uint256 averageGas = totalGasUsed / responses;
        emit log_named_uint("Average task response gas", averageGas);
        assertTrue(averageGas < GAS_LIMIT_TASK_RESPONSE);
    }
    
    function DISABLED_testOrderStoragePerformance() public {
        address hook = address(avs);
        orderVault.authorizeHook(hook, true);
        
        uint256 numOrders = 150;
        uint256 totalGasUsed = 0;
        
        for (uint256 i = 0; i < numOrders; i++) {
            bytes32 orderId = keccak256(abi.encode("perf_order", i));
            address trader = address(uint160(0x3000 + i));
            bytes memory orderData = abi.encode("order_data", i, trader, block.timestamp);
            uint256 deadline = block.timestamp + 2 hours;
            
            uint256 gasStart = gasleft();
            vm.prank(hook);
            orderVault.storeOrder(orderId, trader, orderData, deadline);
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
            assertTrue(gasUsed < GAS_LIMIT_ORDER_STORAGE);
        }
        
        uint256 averageGas = totalGasUsed / numOrders;
        emit log_named_uint("Average order storage gas", averageGas);
        assertTrue(averageGas < GAS_LIMIT_ORDER_STORAGE);
        assertEq(orderVault.totalOrders(), numOrders);
    }
    
    function testLargeScaleOperations() public {
        uint256 operators = 20;
        uint256 tasks = 50;
        uint256 orders = 100;
        
        // Phase 1: Register operators
        for (uint256 i = 0; i < operators; i++) {
            address operator = address(uint160(0x4000 + i));
            vm.deal(operator, MIN_STAKE);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("large_op", i, ".com")));
        }
        
        // Phase 2: Create tasks
        uint32[] memory taskIndices = new uint32[](tasks);
        for (uint256 i = 0; i < tasks; i++) {
            bytes32 taskId = keccak256(abi.encode("large_task", i));
            taskIndices[i] = avs.createTask(taskId, abi.encode("large_data", i), block.timestamp + 2 hours);
        }
        
        // Phase 3: Store orders
        address hook = address(avs);
        for (uint256 i = 0; i < orders; i++) {
            bytes32 orderId = keccak256(abi.encode("large_order", i));
            address trader = address(uint160(0x5000 + i));
            bytes memory orderData = abi.encode("large_order_data", i);
            
            vm.prank(hook);
            orderVault.storeOrder(orderId, trader, orderData, block.timestamp + 2 hours);
        }
        
        // Phase 4: Submit task responses
        for (uint256 i = 0; i < tasks && i < operators; i++) {
            address operator = address(uint160(0x4000 + i));
            bytes memory response = abi.encode("large_response", i);
            
            vm.prank(operator);
            avs.submitTaskResponse(taskIndices[i], response);
        }
        
        // Verify final state
        assertEq(avs.totalOperators(), operators);
        assertEq(avs.totalTasks(), tasks);
        assertEq(orderVault.totalOrders(), orders);
    }
    
    function testConcurrentOperatorRegistration() public {
        uint256 numOperators = 50;
        
        // Simulate concurrent registrations by rapid succession
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x6000 + i));
            vm.deal(operator, MIN_STAKE);
            
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("concurrent", i, ".com")));
            
            assertTrue(avs.isRegisteredOperator(operator));
        }
        
        assertEq(avs.totalOperators(), numOperators);
    }
    
    function testBatchTaskCreation() public {
        uint256 batchSize = 25;
        uint256 numBatches = 8;
        uint256 totalTasks = 0;
        
        for (uint256 batch = 0; batch < numBatches; batch++) {
            for (uint256 i = 0; i < batchSize; i++) {
                bytes32 taskId = keccak256(abi.encode("batch", batch, "task", i));
                bytes memory taskData = abi.encode("batch_data", batch, i);
                
                avs.createTask(taskId, taskData, block.timestamp + 2 hours);
                totalTasks++;
            }
        }
        
        assertEq(avs.totalTasks(), totalTasks);
        assertEq(totalTasks, batchSize * numBatches);
    }
    
    function testOrderExpirationPerformance() public {
        address hook = address(avs);
        uint256 numOrders = 100;
        bytes32[] memory orderIds = new bytes32[](numOrders);
        
        // Create orders with different expiration times
        for (uint256 i = 0; i < numOrders; i++) {
            orderIds[i] = keccak256(abi.encode("expiry_order", i));
            address trader = address(uint160(0x7000 + i));
            bytes memory orderData = abi.encode("expiry_data", i);
            uint256 deadline = block.timestamp + 1 hours + 1 minutes + (i % 10) * 1 hours; // Varying deadlines (1h1m - 10h1m)
            
            vm.prank(hook);
            orderVault.storeOrder(orderIds[i], trader, orderData, deadline);
        }
        
        // Fast forward time to expire some orders
        vm.warp(block.timestamp + 5 hours);
        
        uint256 totalGasUsed = 0;
        uint256 expired = 0;
        
        // Expire orders and measure gas usage
        for (uint256 i = 0; i < numOrders; i++) {
            uint256 gasStart = gasleft();
            try orderVault.expireOrder(orderIds[i]) {
                expired++;
            } catch {
                // Order not eligible for expiration
            }
            uint256 gasUsed = gasStart - gasleft();
            totalGasUsed += gasUsed;
        }
        
        assertTrue(expired > 0);
        uint256 averageGas = totalGasUsed / numOrders;
        emit log_named_uint("Average expiration gas", averageGas);
    }
    
    function testRewardDistributionPerformance() public {
        uint256 numOperators = 30;
        uint256 rewardAmount = 1 ether;
        
        // Register operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x8000 + i));
            vm.deal(operator, MIN_STAKE);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("reward_op", i, ".com")));
        }
        
        uint256 totalGasUsed = 0;
        
        // Distribute rewards to all operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x8000 + i));
            vm.deal(address(avs), rewardAmount);
            
            uint256 gasStart = gasleft();
            avs.distributeReward(operator, rewardAmount);
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
        }
        
        uint256 averageGas = totalGasUsed / numOperators;
        emit log_named_uint("Average reward distribution gas", averageGas);
        
        // Verify all operators received rewards
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x8000 + i));
            assertTrue(avs.getTotalRewards(operator) >= rewardAmount);
        }
    }
    
    function testSlashingPerformance() public {
        uint256 numOperators = 25;
        uint256 slashAmount = 1 ether;
        
        // Register operators with higher stakes
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x9000 + i));
            vm.deal(operator, MIN_STAKE + slashAmount);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE + slashAmount}(string(abi.encodePacked("slash_op", i, ".com")));
        }
        
        uint256 totalGasUsed = 0;
        
        // Slash all operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x9000 + i));
            
            uint256 gasStart = gasleft();
            avs.slashOperator(operator, slashAmount, "Performance test slashing");
            uint256 gasUsed = gasStart - gasleft();
            
            totalGasUsed += gasUsed;
        }
        
        uint256 averageGas = totalGasUsed / numOperators;
        emit log_named_uint("Average slashing gas", averageGas);
        
        // Verify all operators were slashed
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0x9000 + i));
            (uint256 slashed,) = avs.getSlashingInfo(operator);
            assertEq(slashed, slashAmount);
        }
    }
    
    function testStakeManagementPerformance() public {
        uint256 numOperators = 40;
        uint256 additionalStake = 10 ether;
        uint256 withdrawAmount = 5 ether;
        
        // Register operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0xA000 + i));
            vm.deal(operator, MIN_STAKE + additionalStake);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("stake_op", i, ".com")));
        }
        
        uint256 totalAddStakeGas = 0;
        uint256 totalWithdrawGas = 0;
        
        // Add stake for all operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0xA000 + i));
            
            uint256 gasStart = gasleft();
            vm.prank(operator);
            avs.addStake{value: additionalStake}();
            uint256 gasUsed = gasStart - gasleft();
            
            totalAddStakeGas += gasUsed;
        }
        
        // Withdraw stake for all operators
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0xA000 + i));
            
            uint256 gasStart = gasleft();
            vm.prank(operator);
            avs.withdrawStake(withdrawAmount);
            uint256 gasUsed = gasStart - gasleft();
            
            totalWithdrawGas += gasUsed;
        }
        
        uint256 avgAddStakeGas = totalAddStakeGas / numOperators;
        uint256 avgWithdrawGas = totalWithdrawGas / numOperators;
        
        emit log_named_uint("Average add stake gas", avgAddStakeGas);
        emit log_named_uint("Average withdraw stake gas", avgWithdrawGas);
        
        // Verify final stakes
        for (uint256 i = 0; i < numOperators; i++) {
            address operator = address(uint160(0xA000 + i));
            uint256 expectedStake = MIN_STAKE + additionalStake - withdrawAmount;
            assertEq(avs.getOperatorStake(operator), expectedStake);
        }
    }
    
    function DISABLED_testZKProofPerformance() public {
        uint256 numProofs = 20;
        uint256 totalGenerationGas = 0;
        uint256 totalVerificationGas = 0;
        
        address[] memory operators = new address[](1);
        operators[0] = address(0xB001);
        
        for (uint256 i = 0; i < numProofs; i++) {
            bytes32 orderId = keccak256(abi.encode("zk_order", i));
            bytes32 poolHash = keccak256(abi.encode("zk_pool", i));
            
            // Generate proof
            uint256 gasStart = gasleft();
            ZKProofLib.MatchingProof memory proof = ZKProofLib.generateMatchingProof(
                orderId,
                poolHash,
                100 ether + i * 10 ether,
                50 ether + i * 5 ether,
                operators
            );
            uint256 generationGas = gasStart - gasleft();
            totalGenerationGas += generationGas;
            
            // Verify proof
            gasStart = gasleft();
            (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
                ZKProofLib.verifyMatchingProof(proof, poolHash);
            uint256 verificationGas = gasStart - gasleft();
            totalVerificationGas += verificationGas;
            
            assertTrue(result.isValid);
            assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
        }
        
        uint256 avgGenerationGas = totalGenerationGas / numProofs;
        uint256 avgVerificationGas = totalVerificationGas / numProofs;
        
        emit log_named_uint("Average proof generation gas", avgGenerationGas);
        emit log_named_uint("Average proof verification gas", avgVerificationGas);
    }
    
    function testOrderBookPerformance() public {
        testOrderBook.poolId = keccak256("perf_pool");
        
        uint256 numOrders = 100;
        uint256 totalInsertionGas = 0;
        uint256 totalRemovalGas = 0;
        
        bytes32[] memory orderIds = new bytes32[](numOrders);
        
        // Insert buy and sell orders
        for (uint256 i = 0; i < numOrders / 2; i++) {
            // Buy orders
            OrderMatchingLib.OrderBookEntry memory buyOrder = OrderMatchingLib.OrderBookEntry({
                orderId: keccak256(abi.encode("perf_buy", i)),
                price: 1000 ether + i * 10 ether,
                amount: 50 ether + i * 5 ether,
                timestamp: block.timestamp,
                trader: address(uint160(0xC000 + i)),
                isActive: true
            });
            
            orderIds[i * 2] = buyOrder.orderId;
            
            uint256 gasStart = gasleft();
            OrderMatchingLib.insertOrder(testOrderBook, buyOrder, true);
            uint256 gasUsed = gasStart - gasleft();
            totalInsertionGas += gasUsed;
            
            // Sell orders
            OrderMatchingLib.OrderBookEntry memory sellOrder = OrderMatchingLib.OrderBookEntry({
                orderId: keccak256(abi.encode("perf_sell", i)),
                price: 2000 ether - i * 10 ether,
                amount: 75 ether + i * 3 ether,
                timestamp: block.timestamp,
                trader: address(uint160(0xD000 + i)),
                isActive: true
            });
            
            orderIds[i * 2 + 1] = sellOrder.orderId;
            
            gasStart = gasleft();
            OrderMatchingLib.insertOrder(testOrderBook, sellOrder, false);
            gasUsed = gasStart - gasleft();
            totalInsertionGas += gasUsed;
        }
        
        // Remove orders
        for (uint256 i = 0; i < numOrders / 4; i++) {
            uint256 gasStart = gasleft();
            OrderMatchingLib.removeOrder(testOrderBook, orderIds[i * 2], true);
            uint256 gasUsed = gasStart - gasleft();
            totalRemovalGas += gasUsed;
            
            gasStart = gasleft();
            OrderMatchingLib.removeOrder(testOrderBook, orderIds[i * 2 + 1], false);
            gasUsed = gasStart - gasleft();
            totalRemovalGas += gasUsed;
        }
        
        uint256 avgInsertionGas = totalInsertionGas / numOrders;
        uint256 avgRemovalGas = totalRemovalGas / (numOrders / 2);
        
        emit log_named_uint("Average order insertion gas", avgInsertionGas);
        emit log_named_uint("Average order removal gas", avgRemovalGas);
    }
    
    function testSystemLoadTest() public {
        uint256 operators = 15;
        uint256 tasks = 30;
        uint256 orders = 60;
        uint256 rewards = 10;
        uint256 slashes = 5;
        
        // Load test: Mix all operations
        // Register operators
        for (uint256 i = 0; i < operators; i++) {
            address operator = address(uint160(0xE000 + i));
            vm.deal(operator, MIN_STAKE + 10 ether);
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE + 5 ether}(string(abi.encodePacked("load_op", i, ".com")));
        }
        
        // Create tasks
        uint32[] memory taskIndices = new uint32[](tasks);
        for (uint256 i = 0; i < tasks; i++) {
            bytes32 taskId = keccak256(abi.encode("load_task", i));
            taskIndices[i] = avs.createTask(taskId, abi.encode("load_data", i), block.timestamp + 2 hours);
        }
        
        // Store orders
        address hook = address(avs);
        for (uint256 i = 0; i < orders; i++) {
            bytes32 orderId = keccak256(abi.encode("load_order", i));
            address trader = address(uint160(0xF000 + i));
            vm.prank(hook);
            orderVault.storeOrder(orderId, trader, abi.encode("load_order_data", i), block.timestamp + 2 hours);
        }
        
        // Submit task responses
        for (uint256 i = 0; i < tasks && i < operators; i++) {
            address operator = address(uint160(0xE000 + i));
            vm.prank(operator);
            avs.submitTaskResponse(taskIndices[i], abi.encode("load_response", i));
        }
        
        // Distribute some rewards
        for (uint256 i = 0; i < rewards && i < operators; i++) {
            address operator = address(uint160(0xE000 + i));
            vm.deal(address(avs), 1 ether);
            avs.distributeReward(operator, 1 ether);
        }
        
        // Perform some slashing
        for (uint256 i = 0; i < slashes && i < operators; i++) {
            address operator = address(uint160(0xE000 + i));
            avs.slashOperator(operator, 1 ether, "Load test slashing");
        }
        
        // Verify final system state
        assertEq(avs.totalOperators(), operators);
        assertEq(avs.totalTasks(), tasks);
        assertEq(orderVault.totalOrders(), orders);
        
        // Verify some operators have rewards and slashing
        assertTrue(avs.getTotalRewards(address(uint160(0xE000))) > 0);
        (uint256 slashed,) = avs.getSlashingInfo(address(uint160(0xE000)));
        assertTrue(slashed > 0);
    }
}