// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVS.sol";
import "../../src/vault/OrderVault.sol";
import "../../src/core/ZKProofLib.sol";

/// @title StressTests
/// @notice Stress and edge case testing for EigenVault system
contract StressTestsTest is Test {
    EigenVaultAVS public avs;
    OrderVault public orderVault;
    
    uint256 public constant MIN_STAKE = 32 ether;
    
    function setUp() public {
        avs = new EigenVaultAVS();
        orderVault = new OrderVault();
        orderVault.authorizeHook(address(avs), true);
    }
    
    function testMaximumOperatorRegistration() public {
        uint256 maxOperators = 1000;
        
        for (uint256 i = 0; i < maxOperators; i++) {
            address operator = address(uint160(0x10000 + i));
            vm.deal(operator, MIN_STAKE);
            
            vm.prank(operator);
            avs.registerOperator{value: MIN_STAKE}(string(abi.encodePacked("max_op_", i)));
            
            if (i % 100 == 0) {
                assertEq(avs.totalOperators(), i + 1);
            }
        }
        
        assertEq(avs.totalOperators(), maxOperators);
    }
    
    function testExtremeTaskVolume() public {
        uint256 maxTasks = 2000;
        
        for (uint256 i = 0; i < maxTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("extreme_task", i, block.timestamp));
            bytes memory taskData = abi.encode("extreme_data", i);
            
            avs.createTask(taskId, taskData, block.timestamp + 2 hours);
            
            if (i % 200 == 0) {
                assertEq(avs.totalTasks(), i + 1);
            }
        }
        
        assertEq(avs.totalTasks(), maxTasks);
    }
    
    function testMassiveOrderStorage() public {
        address hook = address(avs);
        uint256 maxOrders = 1500;
        
        for (uint256 i = 0; i < maxOrders; i++) {
            bytes32 orderId = keccak256(abi.encode("massive_order", i, block.number));
            address trader = address(uint160(0x20000 + (i % 500))); // Reuse some traders
            bytes memory orderData = abi.encode("massive_data", i, block.timestamp);
            
            vm.prank(hook);
            orderVault.storeOrder(orderId, trader, orderData, block.timestamp + 2 hours);
            
            if (i % 150 == 0) {
                assertEq(orderVault.totalOrders(), i + 1);
            }
        }
        
        assertEq(orderVault.totalOrders(), maxOrders);
    }
    
    function testMinimumStakeEdgeCase() public {
        address operator = address(0x12345);
        
        // Try with exactly MIN_STAKE - 1 wei (should fail)
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE - 1}("edge_operator");
        
        // Try with exactly MIN_STAKE (should succeed)
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("edge_operator");
        assertTrue(avs.isRegisteredOperator(operator));
        assertEq(avs.getOperatorStake(operator), MIN_STAKE);
    }
    
    function testMaximumStakeScenario() public {
        address richOperator = address(0x54321);
        uint256 maximumStake = 1000000 ether; // 1M ETH
        
        vm.deal(richOperator, maximumStake);
        vm.prank(richOperator);
        avs.registerOperator{value: maximumStake}("rich_operator");
        
        assertEq(avs.getOperatorStake(richOperator), maximumStake);
        assertTrue(avs.isRegisteredOperator(richOperator));
    }
    
    function testZeroValueOperations() public {
        address operator = address(0x67890);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("zero_op");
        
        // Try to distribute zero rewards
        vm.expectRevert();
        avs.distributeReward(operator, 0);
        
        // Try to slash zero amount
        vm.expectRevert();
        avs.slashOperator(operator, 0, "zero slash");
        
        // Try to withdraw zero stake
        vm.prank(operator);
        vm.expectRevert();
        avs.withdrawStake(0);
    }
    
    function testDeadlineEdgeCases() public {
        // Test with deadline too soon (should fail)
        bytes32 taskId1 = keccak256("deadline_edge_1");
        vm.prank(address(this));
        vm.expectRevert("Invalid deadline");
        avs.createTask(taskId1, "data1", block.timestamp); // Deadline in past
        
        // Test with minimum valid deadline
        bytes32 taskId2 = keccak256("deadline_edge_2");
        vm.prank(address(this));
        uint32 taskIndex = avs.createTask(taskId2, "data2", block.timestamp + 1 hours + 1 minutes);
        
        address operator = address(0xABCDE);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("deadline_op");
        
        // Should be able to respond before deadline
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "response");
        
        // Test with maximum deadline
        bytes32 taskId3 = keccak256("deadline_edge_3");
        vm.prank(address(this));
        uint32 taskIndex3 = avs.createTask(taskId3, "data3", block.timestamp + 24 hours);
        
        // Fast forward close to deadline
        vm.warp(block.timestamp + 23 hours);
        
        // Should still be able to respond
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex3, "late_response");
    }
    
    function testMaliciousDataSubmission() public {
        address operator = address(0xBAD123);
        vm.deal(operator, MIN_STAKE);
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("malicious_op");
        
        bytes32 taskId = keccak256("malicious_task");
        uint32 taskIndex = avs.createTask(taskId, "normal_data", block.timestamp + 2 hours);
        
        // Try to submit empty response
        vm.prank(operator);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, "");
        
        // Try to submit extremely large response
        bytes memory largeResponse = new bytes(100000); // 100KB
        for (uint256 i = 0; i < largeResponse.length; i++) {
            largeResponse[i] = bytes1(uint8(i % 256));
        }
        
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, largeResponse);
        
        // Verify the large response was stored
        bytes memory storedResponse = avs.getTaskResponse(taskIndex, operator);
        assertEq(storedResponse.length, largeResponse.length);
    }
    
    function testBoundaryTimestamps() public {
        address hook = address(avs);
        
        // Test with minimum deadline (1 hour + 1 second)
        bytes32 orderId1 = keccak256("boundary_1");
        uint256 minDeadline = block.timestamp + 1 hours + 1;
        
        vm.prank(hook);
        orderVault.storeOrder(orderId1, address(0x1111), "data1", minDeadline);
        
        (bool exists, bool valid) = orderVault.isValidOrder(orderId1);
        assertTrue(exists);
        assertTrue(valid);
        
        // Test with exactly 1 hour (should fail)
        bytes32 orderId2 = keccak256("boundary_2");
        uint256 exactHour = block.timestamp + 1 hours;
        
        vm.prank(hook);
        vm.expectRevert();
        orderVault.storeOrder(orderId2, address(0x2222), "data2", exactHour);
    }
    
    function testStringLengthLimits() public {
        address operator = address(0x5FFFFF);
        vm.deal(operator, MIN_STAKE);
        
        // Test with extremely long operator endpoint
        string memory longEndpoint = "";
        for (uint256 i = 0; i < 100; i++) {
            longEndpoint = string(abi.encodePacked(longEndpoint, "very_long_operator_endpoint_"));
        }
        
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}(longEndpoint);
        
        assertTrue(avs.isRegisteredOperator(operator));
    }
    
    function DISABLED_testDuplicateTaskIds() public {
        bytes32 duplicateId = keccak256("duplicate_task");
        
        // Create first task
        vm.prank(address(this));
        avs.createTask(duplicateId, "first_data", block.timestamp + 2 hours);
        
        // Try to create second task with same ID (should fail)
        vm.expectRevert();
        vm.prank(address(this));
        avs.createTask(duplicateId, "second_data", block.timestamp + 2 hours);
    }
    
    function testDuplicateOrderIds() public {
        address hook = address(avs);
        bytes32 duplicateOrderId = keccak256("duplicate_order");
        
        // Store first order
        vm.prank(hook);
        orderVault.storeOrder(duplicateOrderId, address(0x3333), "first_order", block.timestamp + 2 hours);
        
        // Try to store second order with same ID (should fail)
        vm.prank(hook);
        vm.expectRevert();
        orderVault.storeOrder(duplicateOrderId, address(0x4444), "second_order", block.timestamp + 2 hours);
    }
    
    function testUnauthorizedHookAttempts() public {
        address unauthorizedHook = address(0x999999);
        bytes32 orderId = keccak256("unauth_order");
        
        // Try to store order without authorization
        vm.prank(unauthorizedHook);
        vm.expectRevert();
        orderVault.storeOrder(orderId, address(0x5555), "unauth_data", block.timestamp + 2 hours);
        
        // Authorize hook
        orderVault.authorizeHook(unauthorizedHook, true);
        
        // Now should work
        vm.prank(unauthorizedHook);
        orderVault.storeOrder(orderId, address(0x5555), "auth_data", block.timestamp + 2 hours);
        
        (bool exists,) = orderVault.isValidOrder(orderId);
        assertTrue(exists);
    }
    
    function testPauseStateConsistency() public {
        address operator = address(0xAABBCC);
        vm.deal(operator, MIN_STAKE);
        
        // Register operator
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("pause_op");
        
        // Create task
        bytes32 taskId = keccak256("pause_task");
        uint32 taskIndex = avs.createTask(taskId, "pause_data", block.timestamp + 2 hours);
        
        // Pause system
        avs.emergencyPause();
        
        // All operations should be paused
        address newOperator = address(0xDDEEFF);
        vm.deal(newOperator, MIN_STAKE);
        vm.prank(newOperator);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE}("new_op");
        
        vm.expectRevert();
        avs.createTask(keccak256("new_task"), "new_data", block.timestamp + 2 hours);
        
        vm.prank(operator);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, "paused_response");
        
        vm.prank(operator);
        vm.expectRevert();
        avs.deregisterOperator();
        
        // Unpause
        avs.emergencyUnpause();
        
        // Operations should work again
        vm.prank(operator);
        avs.submitTaskResponse(taskIndex, "unpaused_response");
        
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
    }
    
    function testOwnershipTransferEdgeCases() public {
        address newOwner = address(0x123456);
        address operator = address(0x789ABC);
        
        // Transfer ownership
        avs.transferOwnership(newOwner);
        assertEq(avs.owner(), newOwner);
        
        // Old owner should not be able to perform owner actions
        vm.expectRevert();
        avs.emergencyPause();
        
        vm.expectRevert();
        avs.distributeReward(operator, 1 ether);
        
        // New owner should be able to perform owner actions
        vm.prank(newOwner);
        avs.emergencyPause();
        
        vm.prank(newOwner);
        avs.emergencyUnpause();
    }
    
    function testRapidStateChanges() public {
        address operator = address(0xFEDCBA);
        vm.deal(operator, MIN_STAKE + 10 ether);
        
        // Rapid registration -> stake addition -> withdrawal cycle
        vm.prank(operator);
        avs.registerOperator{value: MIN_STAKE}("rapid_op");
        
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(operator);
            avs.addStake{value: 1 ether}();
            
            vm.prank(operator);
            avs.withdrawStake(0.5 ether);
        }
        
        uint256 expectedStake = MIN_STAKE + 10 ether - 5 ether; // Added 10, withdrew 5
        assertEq(avs.getOperatorStake(operator), expectedStake);
    }
    
    function testExtremeSlashingScenarios() public {
        address operator = address(0xABCDEF);
        uint256 largeStake = 1000 ether;
        vm.deal(operator, largeStake);
        vm.prank(operator);
        avs.registerOperator{value: largeStake}("slashed_op");
        
        // Slash most of the stake in multiple rounds
        avs.slashOperator(operator, 300 ether, "Major violation");
        avs.slashOperator(operator, 200 ether, "Secondary violation");
        avs.slashOperator(operator, 100 ether, "Minor violation");
        
        uint256 expectedStake = largeStake - 600 ether;
        assertEq(avs.getOperatorStake(operator), expectedStake);
        
        (uint256 totalSlashed, uint256 slashCount) = avs.getSlashingInfo(operator);
        assertEq(totalSlashed, 600 ether);
        assertEq(slashCount, 3);
        
        // Try to slash more than remaining stake (should fail)
        vm.expectRevert();
        avs.slashOperator(operator, expectedStake + 1 ether, "Excessive slash");
    }
    
    function testMemoryLimitStress() public {
        // Create tasks with very large data payloads
        for (uint256 i = 0; i < 10; i++) {
            bytes memory largeData = new bytes(50000); // 50KB per task
            for (uint256 j = 0; j < largeData.length; j++) {
                largeData[j] = bytes1(uint8((i + j) % 256));
            }
            
            bytes32 taskId = keccak256(abi.encode("memory_stress", i));
            avs.createTask(taskId, largeData, block.timestamp + 2 hours);
        }
        
        assertEq(avs.totalTasks(), 10);
    }
    
    function testConcurrentOrderExpiration() public {
        address hook = address(avs);
        uint256 numOrders = 100;
        bytes32[] memory orderIds = new bytes32[](numOrders);
        
        // Create orders that will expire at the same time
        uint256 commonDeadline = block.timestamp + 2 hours;
        for (uint256 i = 0; i < numOrders; i++) {
            orderIds[i] = keccak256(abi.encode("concurrent_expire", i));
            address trader = address(uint160(0x30000 + i));
            
            vm.prank(hook);
            orderVault.storeOrder(orderIds[i], trader, abi.encode("expire_data", i), commonDeadline);
        }
        
        // Fast forward past deadline
        vm.warp(commonDeadline + 1);
        
        // Expire all orders
        uint256 expiredCount = 0;
        for (uint256 i = 0; i < numOrders; i++) {
            orderVault.expireOrder(orderIds[i]);
            expiredCount++;
        }
        
        assertEq(orderVault.totalOrdersExpired(), expiredCount);
    }
    
    function testSystemRecoveryAfterPause() public {
        address operator1 = address(0x111111);
        address operator2 = address(0x222222);
        vm.deal(operator1, MIN_STAKE);
        vm.deal(operator2, MIN_STAKE);
        
        // Normal operations before pause
        vm.prank(operator1);
        avs.registerOperator{value: MIN_STAKE}("recover1");
        
        bytes32 taskId = keccak256("recovery_task");
        uint32 taskIndex = avs.createTask(taskId, "recovery_data", block.timestamp + 4 hours);
        
        // Pause system
        avs.emergencyPause();
        
        // Try operations during pause (should fail)
        vm.prank(operator2);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE}("recover2");
        
        vm.prank(operator1);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, "paused_response");
        
        // Unpause and verify full recovery
        avs.emergencyUnpause();
        
        // All operations should work normally
        vm.prank(operator2);
        avs.registerOperator{value: MIN_STAKE}("recover2");
        
        vm.prank(operator1);
        avs.submitTaskResponse(taskIndex, "recovery_response");
        
        bytes32 newTaskId = keccak256("post_recovery_task");
        avs.createTask(newTaskId, "post_recovery_data", block.timestamp + 2 hours);
        
        assertEq(avs.totalOperators(), 2);
        assertEq(avs.totalTasks(), 2);
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
    }
}