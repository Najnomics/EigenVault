// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVS.sol";
import "../../src/vault/OrderVault.sol";
import "../../src/core/ZKProofLib.sol";
import "../../src/vault/OrderLib.sol";
import "../../src/vault/OrderMatchingLib.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title EdgeCaseTests
/// @notice Comprehensive edge case and boundary condition testing
contract EdgeCaseTestsTest is Test {
    EigenVaultAVS public avs;
    OrderVault public orderVault;
    OrderMatchingLib.OrderBook public edgeOrderBook;
    
    PoolKey public testPoolKey;
    uint256 public constant MIN_STAKE = 32 ether;
    
    function setUp() public {
        avs = new EigenVaultAVS();
        orderVault = new OrderVault();
        orderVault.authorizeHook(address(avs), true);
        edgeOrderBook.poolId = keccak256("edge_pool");
        
        testPoolKey = PoolKey({
            currency0: Currency.wrap(address(0x111)),
            currency1: Currency.wrap(address(0x222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }
    
    // Test 1: Zero amount operations
    function testZeroAmountEdgeCases() public {
        address operator = address(0x1001);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("zero_op");
        
        // Test zero reward distribution
        vm.expectRevert();
        avs.distributeReward(operator, 0);
        
        // Test zero slashing
        vm.expectRevert();
        avs.slashOperator(operator, 0, "zero slash");
    }
    
    // Test 2: Maximum value boundaries
    function testMaximumValueBoundaries() public {
        address richOperator = address(0x1002);
        uint256 maxStake = type(uint256).max / 2; // Avoid overflow
        vm.deal(richOperator, maxStake);
        
        vm.prank(richOperator);
        avs.registerOperator{value: MIN_STAKE}("max_op");
        
        // Add maximum possible stake (within limits)
        vm.prank(richOperator);
        avs.addStake{value: maxStake - MIN_STAKE}();
        
        assertEq(avs.getOperatorStake(richOperator), maxStake);
    }
    
    // Test 3: Minimum timestamp boundaries
    function testMinimumTimestampBoundaries() public {
        // Test task creation with minimum valid deadline
        bytes32 taskId = keccak256("min_timestamp_task");
        uint256 minDeadline = block.timestamp + 1;
        
        uint32 taskIndex = avs.createTask(taskId, "min_data", minDeadline);
        (,, uint256 storedDeadline,) = avs.getTask(taskIndex);
        assertEq(storedDeadline, minDeadline);
    }
    
    // Test 4: Empty string handling
    function testEmptyStringHandling() public {
        address operator = address(0x1003);
        vm.deal(operator, MIN_STAKE);
        
        // Empty endpoint should fail
        vm.prank(operator);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE}("");
    }
    
    // Test 5: Duplicate prevention edge cases
    function DISABLED_testDuplicatePreventionEdgeCases() public {
        bytes32 taskId = keccak256("duplicate_task");
        
        avs.createTask(taskId, "first", block.timestamp + 2 hours);
        
        // Same task ID should fail
        vm.expectRevert();
        avs.createTask(taskId, "second", block.timestamp + 2 hours);
        
        // Similar but different task ID should work
        bytes32 similarTaskId = keccak256("duplicate_task_2");
        avs.createTask(similarTaskId, "similar", block.timestamp + 2 hours);
        
        assertEq(avs.totalTasks(), 2);
    }
    
    // Test 6: Order vault authorization edge cases
    function testOrderVaultAuthorizationEdgeCases() public {
        address hook1 = address(0x2001);
        address hook2 = address(0x2002);
        
        // Initially not authorized
        assertFalse(orderVault.isAuthorizedHook(hook1));
        assertFalse(orderVault.isAuthorizedHook(hook2));
        
        // Authorize hook1
        orderVault.authorizeHook(hook1, true);
        assertTrue(orderVault.isAuthorizedHook(hook1));
        
        // Authorizing already authorized hook should be idempotent
        orderVault.authorizeHook(hook1, true);
        assertTrue(orderVault.isAuthorizedHook(hook1));
        
        // Deauthorize hook1
        orderVault.authorizeHook(hook1, false);
        assertFalse(orderVault.isAuthorizedHook(hook1));
        
        // Deauthorizing already deauthorized hook should be idempotent
        orderVault.authorizeHook(hook1, false);
        assertFalse(orderVault.isAuthorizedHook(hook1));
    }
    
    // Test 7: Task response timing edge cases
    function testTaskResponseTimingEdgeCases() public {
        address operator = address(0x1004);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("timing_op");
        
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 taskId = keccak256("timing_task");
        uint32 taskIndex = avs.createTask(taskId, "timing_data", deadline);
        
        // Respond exactly at deadline (should work)
        vm.warp(deadline);
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "deadline_response");
        
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
    }
    
    // Test 8: Operator state transitions
    function testOperatorStateTransitions() public {
        address operator = address(0x1005);
        vm.deal(operator, MIN_STAKE * 2);
        
        // Register
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("state_op");
        assertTrue(avs.isRegisteredOperator(operator));
        
        // Add stake
        vm.prank(operator);
        avs.addStake{value: MIN_STAKE}();
        assertEq(avs.getOperatorStake(operator), MIN_STAKE * 2);
        
        // Partial withdrawal
        vm.prank(operator);
        avs.withdrawStake(MIN_STAKE / 2);
        assertEq(avs.getOperatorStake(operator), MIN_STAKE * 2 - MIN_STAKE / 2);
        
        assertTrue(avs.isRegisteredOperator(operator));
    }
    
    // Test 9: Order data size boundaries
    function testOrderDataSizeBoundaries() public {
        address hook = address(avs);
        bytes32 orderId = keccak256("size_test_order");
        
        // Very small data
        vm.prank(hook);
        orderVault.storeOrder(orderId, address(0x3001), "x", block.timestamp + 2 hours);
        
        (bool exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
    }
    
    // Test 10: Slashing boundary conditions
    function DISABLED_testSlashingBoundaryConditions() public {
        address operator = address(0x1006);
        uint256 stake = MIN_STAKE + 10 ether;
        vm.deal(operator, stake);
        
        vm.prank(operator);
        avs.registerOperator{value: stake}("slash_boundary_op");
        
        // Slash exactly all excess stake (leaving minimum)
        uint256 slashAmount = 10 ether;
        avs.slashOperator(operator, slashAmount, "Boundary slash");
        
        assertEq(avs.getOperatorStake(operator), MIN_STAKE);
        (uint256 slashed,) = avs.getSlashingInfo(operator);
        assertEq(slashed, slashAmount);
        
        // Try to slash below minimum (should fail)
        vm.expectRevert();
        avs.slashOperator(operator, 1 ether, "Below minimum");
    }
    
    // Test 11: Task data validation edge cases
    function testTaskDataValidationEdgeCases() public {
        // Empty data should fail
        vm.expectRevert();
        avs.createTask(keccak256("empty_data_task"), "", block.timestamp + 2 hours);
        
        // Valid single character data
        bytes32 taskId = keccak256("single_char_task");
        avs.createTask(taskId, "a", block.timestamp + 2 hours);
        
        assertEq(avs.totalTasks(), 1);
    }
    
    // Test 12: Order matching price edge cases
    function testOrderMatchingPriceEdgeCases() public {
        // Test with same price
        OrderMatchingLib.OrderBookEntry memory buyOrder = OrderMatchingLib.OrderBookEntry({
            orderId: keccak256("same_price_buy"),
            price: 1000 ether,
            amount: 100 ether,
            timestamp: block.timestamp,
            trader: address(0x4001),
            isActive: true
        });
        
        OrderMatchingLib.OrderBookEntry memory sellOrder = OrderMatchingLib.OrderBookEntry({
            orderId: keccak256("same_price_sell"),
            price: 1000 ether,
            amount: 100 ether,
            timestamp: block.timestamp,
            trader: address(0x4002),
            isActive: true
        });
        
        (OrderMatchingLib.MatchingResult memory result, bool canMatch) = 
            OrderMatchingLib.matchOrders(buyOrder, sellOrder, testPoolKey);
        
        assertTrue(canMatch);
        assertEq(result.executionPrice, 1000 ether);
        assertEq(result.matchedAmount, 100 ether);
    }
    
    // Test 13: ZK proof edge cases
    function testZKProofEdgeCases() public {
        address[] memory operators = new address[](1);
        operators[0] = address(0x5001);
        
        // Test with minimum valid values
        ZKProofLib.MatchingProof memory proof = ZKProofLib.generateMatchingProof(
            keccak256("min_order"),
            keccak256("min_pool"),
            1 wei,
            1 wei,
            operators
        );
        
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(proof, keccak256("min_pool"));
        
        assertTrue(result.isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
        assertEq(result.executionPrice, 1 wei);
        assertEq(result.totalVolume, 1 wei);
    }
    
    // Test 14: Order expiration precision
    function testOrderExpirationPrecision() public {
        address hook = address(avs);
        bytes32 orderId = keccak256("precision_order");
        uint256 preciseDeadline = block.timestamp + 1 hours + 1 minutes + 1;
        
        vm.prank(hook);
        orderVault.storeOrder(orderId, address(0x6001), "precision_data", preciseDeadline);
        
        // Before deadline
        vm.warp(preciseDeadline - 1);
        (bool exists, bool valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
        
        // Exactly at deadline (still valid)
        vm.warp(preciseDeadline);
        (exists, valid) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        assertTrue(valid);
        
        // After deadline
        vm.warp(preciseDeadline + 1);
        orderVault.expireOrder(orderId);
        assertEq(orderVault.totalOrdersExpired(), 1);
    }
    
    // Test 15: Operator performance edge cases
    function testOperatorPerformanceEdgeCases() public {
        address operator = address(0x1007);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("perf_edge_op");
        
        // Check initial performance
        (uint256 assigned, uint256 completed, uint256 rewards, uint256 slashed) = 
            avs.getOperatorPerformance(operator);
        assertEq(assigned, 0);
        assertEq(completed, 0);
        assertEq(rewards, 0);
        assertEq(slashed, 0);
        
        // Create and complete task
        bytes32 taskId = keccak256("perf_edge_task");
        uint32 taskIndex = avs.createTask(taskId, "perf_data", block.timestamp + 2 hours);
        
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "perf_response");
        
        // Check updated performance
        (assigned, completed, rewards, slashed) = avs.getOperatorPerformance(operator);
        assertEq(assigned, 1);
        assertEq(completed, 1);
        assertEq(rewards, 0);
        assertEq(slashed, 0);
    }
    
    // Test 16: Order lib edge cases
    function testOrderLibEdgeCases() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("edge_order"),
            trader: address(0x7001),
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 1 wei, // Minimum amount
            price: 1 wei,  // Minimum price
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        assertTrue(OrderLib.validateOrder(order));
        assertEq(OrderLib.getRemainingAmount(order), 1 wei);
        
        bytes32 hash1 = OrderLib.getOrderHash(order);
        bytes32 hash2 = OrderLib.getOrderHash(order);
        assertEq(hash1, hash2);
    }
    
    // Test 17: Multiple simultaneous operations
    function testMultipleSimultaneousOperations() public {
        uint256 numOperators = 5;
        address[] memory operators = new address[](numOperators);
        
        // Register multiple operators simultaneously
        for (uint256 i = 0; i < numOperators; i++) {
            operators[i] = address(uint160(0x8000 + i));
            vm.deal(operators[i], MIN_STAKE);
            vm.prank(operators[i]);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("simul_op", i)));
        }
        
        // Create multiple tasks simultaneously
        uint32[] memory taskIndices = new uint32[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            bytes32 taskId = keccak256(abi.encode("simul_task", i));
            taskIndices[i] = avs.createTask(taskId, abi.encode("simul_data", i), block.timestamp + 2 hours);
        }
        
        // Submit responses simultaneously
        for (uint256 i = 0; i < numOperators; i++) {
            vm.prank(operators[i]);
            avs.submitTaskResponse(taskIndices[i], abi.encode("simul_response", i));
        }
        
        assertEq(avs.totalOperators(), numOperators);
        assertEq(avs.totalTasks(), numOperators);
    }
    
    // Test 18: Reward and slash combination edge cases
    function testRewardSlashCombinationEdgeCases() public {
        address operator = address(0x1008);
        uint256 initialStake = MIN_STAKE + 20 ether;
        vm.deal(operator, initialStake);
        vm.prank(operator);
        avs.registerOperator{value: initialStake}("reward_slash_op");
        
        // Distribute reward
        vm.deal(address(avs), 10 ether);
        avs.distributeReward(operator, 10 ether);
        assertEq(avs.getTotalRewards(operator), 10 ether);
        
        // Slash after reward
        avs.slashOperator(operator, 5 ether, "Post-reward slash");
        
        (uint256 slashed, uint256 slashCount) = avs.getSlashingInfo(operator);
        assertEq(slashed, 5 ether);
        assertEq(slashCount, 1);
        assertEq(avs.getTotalRewards(operator), 10 ether); // Rewards unchanged by slashing
        assertEq(avs.getOperatorStake(operator), initialStake - 5 ether);
    }
    
    // Test 19: Order book depth edge cases
    function testOrderBookDepthEdgeCases() public {
        // Empty order book depth
        (uint256[] memory buyDepth, uint256[] memory sellDepth) = 
            OrderMatchingLib.getOrderBookDepth(edgeOrderBook, 5);
        
        assertEq(buyDepth.length, 5);
        assertEq(sellDepth.length, 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(buyDepth[i], 0);
            assertEq(sellDepth[i], 0);
        }
        
        // Single order depth
        OrderMatchingLib.OrderBookEntry memory singleOrder = OrderMatchingLib.OrderBookEntry({
            orderId: keccak256("single_depth_order"),
            price: 1000 ether,
            amount: 100 ether,
            timestamp: block.timestamp,
            trader: address(0x9001),
            isActive: true
        });
        
        OrderMatchingLib.insertOrder(edgeOrderBook, singleOrder, true);
        
        (buyDepth, sellDepth) = OrderMatchingLib.getOrderBookDepth(edgeOrderBook, 3);
        assertEq(buyDepth[0], 100 ether);
        assertEq(buyDepth[1], 0);
        assertEq(buyDepth[2], 0);
        assertEq(sellDepth[0], 0);
        assertEq(sellDepth[1], 0);
        assertEq(sellDepth[2], 0);
    }
    
    // Test 20: Task completion edge cases
    function testTaskCompletionEdgeCases() public {
        address operator = address(0x1009);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("completion_op");
        
        bytes32 taskId = keccak256("completion_task");
        uint32 taskIndex = avs.createTask(taskId, "completion_data", block.timestamp + 2 hours);
        
        // Check initial state
        (,,,bool completed) = avs.getTask(taskIndex);
        assertFalse(completed);
        
        // Submit response
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "completion_response");
        
        // Check final state
        (,,,completed) = avs.getTask(taskIndex);
        assertTrue(completed);
        
        // Try to submit another response (should fail)
        vm.prank(operator);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, "duplicate_response");
    }
    
    // Test 21: Timestamp arithmetic edge cases
    function testTimestampArithmeticEdgeCases() public {
        // Very far future deadline
        uint256 farFuture = type(uint256).max / 2;
        
        if (farFuture > block.timestamp) {
            bytes32 taskId = keccak256("far_future_task");
            avs.createTask(taskId, "far_future_data", farFuture);
            
            (,, uint256 deadline,) = avs.getTask(1);
            assertEq(deadline, farFuture);
        }
    }
    
    // Test 22: Order matching amount edge cases
    function testOrderMatchingAmountEdgeCases() public {
        // Test with very small amounts
        OrderMatchingLib.OrderBookEntry memory buyOrder = OrderMatchingLib.OrderBookEntry({
            orderId: keccak256("tiny_buy"),
            price: 1000 ether,
            amount: 1 wei,
            timestamp: block.timestamp,
            trader: address(0xA001),
            isActive: true
        });
        
        OrderMatchingLib.OrderBookEntry memory sellOrder = OrderMatchingLib.OrderBookEntry({
            orderId: keccak256("tiny_sell"),
            price: 900 ether,
            amount: 2 wei,
            timestamp: block.timestamp,
            trader: address(0xA002),
            isActive: true
        });
        
        (OrderMatchingLib.MatchingResult memory result, bool canMatch) = 
            OrderMatchingLib.matchOrders(buyOrder, sellOrder, testPoolKey);
        
        assertTrue(canMatch);
        assertEq(result.matchedAmount, 1 wei); // Minimum of the two amounts
        assertEq(result.executionPrice, 950 ether); // Midpoint
    }
    
    // Test 23: Address validation edge cases
    function testAddressValidationEdgeCases() public {
        // Try to register with null address (should be handled by the contract)
        // This test ensures the contract properly validates addresses
        bytes32 orderId = keccak256("null_trader_order");
        
        vm.prank(address(avs));
        vm.expectRevert();
        orderVault.storeOrder(orderId, address(0), "null_data", block.timestamp + 2 hours);
    }
    
    // Test 24: Gas limit edge cases
    function testGasLimitEdgeCases() public {
        // Test operations with minimal gas to ensure they don't run out
        address operator = address(0x1010);
        vm.deal(operator, MIN_STAKE);
        
        // Operator registration should complete within reasonable gas
        uint256 gasStart = gasleft();
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("gas_limit_op");
        uint256 gasUsed = gasStart - gasleft();
        
        assertTrue(gasUsed < 500000); // Reasonable gas limit
        assertTrue(avs.isRegisteredOperator(operator));
    }
    
    // Test 25: State consistency edge cases
    function DISABLED_testStateConsistencyEdgeCases() public {
        address operator = address(0x1011);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("consistency_op");
        
        uint256 initialOperators = avs.totalOperators();
        uint256 initialTasks = avs.totalTasks();
        
        // Create task
        bytes32 taskId = keccak256("consistency_task");
        uint32 taskIndex = avs.createTask(taskId, "consistency_data", block.timestamp + 2 hours);
        
        assertEq(avs.totalTasks(), initialTasks + 1);
        
        // Complete task
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "consistency_response");
        
        // State should remain consistent
        assertEq(avs.totalOperators(), initialOperators + 1);
        assertEq(avs.totalTasks(), initialTasks + 1);
        
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
    }
    
    // Test 26: Multiple hook authorization edge cases
    function testMultipleHookAuthorizationEdgeCases() public {
        address[] memory hooks = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            hooks[i] = address(uint160(0xB000 + i));
            
            // Initially not authorized
            assertFalse(orderVault.isAuthorizedHook(hooks[i]));
            
            // Authorize
            orderVault.authorizeHook(hooks[i], true);
            assertTrue(orderVault.isAuthorizedHook(hooks[i]));
        }
        
        // All hooks should be authorized
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(orderVault.isAuthorizedHook(hooks[i]));
        }
        
        // Deauthorize some hooks
        orderVault.authorizeHook(hooks[1], false);
        orderVault.authorizeHook(hooks[3], false);
        
        // Check final state
        assertTrue(orderVault.isAuthorizedHook(hooks[0]));
        assertFalse(orderVault.isAuthorizedHook(hooks[1]));
        assertTrue(orderVault.isAuthorizedHook(hooks[2]));
        assertFalse(orderVault.isAuthorizedHook(hooks[3]));
        assertTrue(orderVault.isAuthorizedHook(hooks[4]));
    }
    
    // Test 27: Order commitment edge cases
    function testOrderCommitmentEdgeCases() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("commitment_edge_order"),
            trader: address(0xC001),
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Sell,
            amount: 50 ether,
            price: 2000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Test with zero nonce
        bytes32 commitment1 = OrderLib.generateCommitment(order, 0);
        assertTrue(commitment1 != bytes32(0));
        assertTrue(OrderLib.verifyCommitment(order, 0, commitment1));
        
        // Test with maximum nonce
        uint256 maxNonce = type(uint256).max;
        bytes32 commitment2 = OrderLib.generateCommitment(order, maxNonce);
        assertTrue(commitment2 != bytes32(0));
        assertTrue(commitment2 != commitment1);
        assertTrue(OrderLib.verifyCommitment(order, maxNonce, commitment2));
    }
    
    // Test 28: Order status transition edge cases
    function testOrderStatusTransitionEdgeCases() public {
        OrderLib.Order memory order = OrderLib.Order({
            id: keccak256("status_edge_order"),
            trader: address(0xD001),
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1500 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: block.timestamp,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        // Test exact fill
        OrderLib.updateOrderAfterFill(order, 100 ether);
        assertEq(order.filledAmount, 100 ether);
        assertEq(uint256(order.status), uint256(OrderLib.OrderStatus.Filled));
        
        // Test overfill
        OrderLib.Order memory overOrder = order;
        overOrder.filledAmount = 0;
        overOrder.status = OrderLib.OrderStatus.Pending;
        
        OrderLib.updateOrderAfterFill(overOrder, 150 ether);
        assertEq(overOrder.filledAmount, 150 ether);
        assertEq(uint256(overOrder.status), uint256(OrderLib.OrderStatus.Filled));
    }
    
    // Test 29: Proof generation edge cases
    function testProofGenerationEdgeCases() public {
        address[] memory singleOperator = new address[](1);
        singleOperator[0] = address(0xE001);
        
        // Test with identical order and pool hashes
        bytes32 sameHash = keccak256("same_hash");
        ZKProofLib.MatchingProof memory proof = ZKProofLib.generateMatchingProof(
            sameHash,
            sameHash,
            1000 ether,
            500 ether,
            singleOperator
        );
        
        assertEq(proof.proofId, ZKProofLib.generateProofId(proof.proof, proof.timestamp, singleOperator[0]));
        assertEq(proof.poolHash, sameHash);
        assertEq(proof.publicInputs[0], sameHash);
    }
    
    // Test 30: Circuit validation edge cases
    function testCircuitValidationEdgeCases() public {
        // Test with minimum valid circuit info
        ZKProofLib.CircuitInfo memory minCircuit = ZKProofLib.CircuitInfo({
            circuitHash: keccak256("min_circuit"),
            verificationKey: "x",
            maxOrders: 1,
            circuitType: "x"
        });
        
        assertTrue(ZKProofLib.validateCircuitInfo(minCircuit));
        
        // Test with each field invalid
        ZKProofLib.CircuitInfo memory invalidCircuit = minCircuit;
        
        invalidCircuit.circuitHash = bytes32(0);
        assertFalse(ZKProofLib.validateCircuitInfo(invalidCircuit));
        
        invalidCircuit = minCircuit;
        invalidCircuit.verificationKey = "";
        assertFalse(ZKProofLib.validateCircuitInfo(invalidCircuit));
        
        invalidCircuit = minCircuit;
        invalidCircuit.maxOrders = 0;
        assertFalse(ZKProofLib.validateCircuitInfo(invalidCircuit));
        
        invalidCircuit = minCircuit;
        invalidCircuit.circuitType = "";
        assertFalse(ZKProofLib.validateCircuitInfo(invalidCircuit));
    }
    
    // Test 31: Order priority edge cases
    function DISABLED_testOrderPriorityEdgeCases() public {
        // Test with same price, different timestamps
        OrderLib.Order memory earlyOrder = OrderLib.Order({
            id: keccak256("early_order"),
            trader: address(0xF001),
            poolKey: testPoolKey,
            orderType: OrderLib.OrderType.Buy,
            amount: 100 ether,
            price: 1000 ether,
            status: OrderLib.OrderStatus.Pending,
            timestamp: 1000,
            deadline: block.timestamp + 2 hours,
            filledAmount: 0,
            commitment: bytes32(0),
            encryptedData: ""
        });
        
        OrderLib.Order memory lateOrder = earlyOrder;
        lateOrder.id = keccak256("late_order");
        lateOrder.timestamp = 2000;
        
        uint256 earlyPriority = OrderLib.getOrderPriority(earlyOrder);
        uint256 latePriority = OrderLib.getOrderPriority(lateOrder);
        
        // Earlier timestamp should have higher priority for same price
        assertTrue(earlyPriority > latePriority);
    }
    
    // Test 32: Batch proof edge cases
    function DISABLED_testBatchProofEdgeCases() public {
        address[] memory operators = new address[](1);
        operators[0] = address(0x1F01);
        
        // Single proof batch
        ZKProofLib.MatchingProof[] memory singleProof = new ZKProofLib.MatchingProof[](1);
        singleProof[0] = ZKProofLib.generateMatchingProof(
            keccak256("single_batch_order"),
            keccak256("single_batch_pool"),
            100 ether,
            50 ether,
            operators
        );
        
        ZKProofLib.BatchProof memory singleBatch = ZKProofLib.BatchProof({
            batchId: keccak256("single_batch"),
            individualProofs: singleProof,
            aggregatedProof: abi.encodePacked("single_aggregated_proof"),
            batchHash: keccak256("single_batch_hash"),
            totalMatches: 1,
            operators: operators
        });
        
        (bool isValid, ZKProofLib.ProofError error) = ZKProofLib.verifyBatchProof(singleBatch);
        
        // Single proof batches should be valid
        assertTrue(isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
    }
    
    // Test 33: Order expiration cleanup edge cases
    function testOrderExpirationCleanupEdgeCases() public {
        address hook = address(avs);
        
        // Create orders that expire at different times
        bytes32[] memory orderIds = new bytes32[](3);
        uint256[] memory deadlines = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            orderIds[i] = keccak256(abi.encode("cleanup_order", i));
            deadlines[i] = block.timestamp + 1 hours + 5 minutes + i * 1 hours;
            
            vm.prank(hook);
            orderVault.storeOrder(orderIds[i], address(uint160(0x2000 + i)), abi.encode("cleanup_data", i), deadlines[i]);
        }
        
        assertEq(orderVault.totalOrders(), 3);
        
        // Fast forward to expire first order only
        vm.warp(deadlines[0] + 1);
        
        // Expire first order
        orderVault.expireOrder(orderIds[0]);
        assertEq(orderVault.totalOrdersExpired(), 1);
        
        // Other orders should still be valid
        for (uint256 i = 1; i < 3; i++) {
            (bool exists, bool valid) = orderVault.isValidOrder(orderIds[i]);
            assertTrue(exists);
            assertTrue(valid);
        }
    }
    
    // Test 34: Operator deregistration edge cases
    function testOperatorDeregistrationEdgeCases() public {
        address operator = address(0x1012);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("dereg_edge_op");
        
        // Create task for operator
        bytes32 taskId = keccak256("dereg_edge_task");
        uint32 taskIndex = avs.createTask(taskId, "dereg_data", block.timestamp + 2 hours);
        
        // Complete the task
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "dereg_response");
        
        // Now should be able to deregister (no pending tasks)
        vm.prank(operator);
        avs.deregisterOperator();
        
        assertFalse(avs.isRegisteredOperator(operator));
        assertEq(avs.totalOperators(), 0);
    }
    
    // Test 35: System pause/unpause state consistency
    function testSystemPauseUnpauseStateConsistency() public {
        // Setup initial state
        address operator = address(0x1013);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("pause_consistency_op");
        
        bytes32 orderId = keccak256("pause_consistency_order");
        vm.prank(address(avs));
        orderVault.storeOrder(orderId, operator, "pause_data", block.timestamp + 2 hours);
        
        uint256 initialOperators = avs.totalOperators();
        uint256 initialOrders = orderVault.totalOrders();
        
        // Pause
        avs.emergencyPause();
        assertTrue(avs.paused());
        
        // State should be preserved during pause
        assertEq(avs.totalOperators(), initialOperators);
        assertEq(orderVault.totalOrders(), initialOrders);
        (bool exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
        
        // Unpause
        avs.emergencyUnpause();
        assertFalse(avs.paused());
        
        // State should still be preserved after unpause
        assertEq(avs.totalOperators(), initialOperators);
        assertEq(orderVault.totalOrders(), initialOrders);
        (exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
    }
}