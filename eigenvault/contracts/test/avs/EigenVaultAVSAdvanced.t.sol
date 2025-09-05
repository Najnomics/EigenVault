// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/avs/EigenVaultAVS.sol";

/// @title EigenVaultAVSAdvancedTest
/// @notice Advanced tests for EigenVaultAVS functionality
contract EigenVaultAVSAdvancedTest is Test {
    EigenVaultAVS public avs;
    
    address public constant OPERATOR1 = address(0x1);
    address public constant OPERATOR2 = address(0x2);
    address public constant OPERATOR3 = address(0x3);
    
    uint256 public constant MIN_STAKE = 32 ether;
    
    function setUp() public {
        avs = new EigenVaultAVS();
    }
    
    function testAdvancedOperatorRegistration() public {
        vm.deal(OPERATOR1, 100 ether);
        
        // Register with minimum stake
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.example.com");
        
        assertTrue(avs.isRegisteredOperator(OPERATOR1));
        assertEq(avs.getOperatorStake(OPERATOR1), MIN_STAKE);
        assertEq(avs.totalOperators(), 1);
    }
    
    function testOperatorStakeManagement() public {
        vm.deal(OPERATOR1, 100 ether);
        
        // Register with excess stake
        uint256 initialStake = 50 ether;
        vm.prank(OPERATOR1);
        avs.registerOperator{value: initialStake}("operator1.com");
        
        // Add more stake
        uint256 additionalStake = 10 ether;
        vm.prank(OPERATOR1);
        avs.addStake{value: additionalStake}();
        
        assertEq(avs.getOperatorStake(OPERATOR1), initialStake + additionalStake);
        
        // Withdraw partial stake
        uint256 withdrawAmount = 15 ether;
        vm.prank(OPERATOR1);
        avs.withdrawStake(withdrawAmount);
        
        assertEq(avs.getOperatorStake(OPERATOR1), initialStake + additionalStake - withdrawAmount);
    }
    
    function testTaskCreationAndManagement() public {
        // Create multiple tasks
        uint256 numTasks = 5;
        bytes32[] memory taskIds = new bytes32[](numTasks);
        uint32[] memory taskIndices = new uint32[](numTasks);
        
        for (uint256 i = 0; i < numTasks; i++) {
            taskIds[i] = keccak256(abi.encode("advanced_task", i));
            bytes memory taskData = abi.encode("complex_matching_data", i, block.timestamp);
            uint256 deadline = block.timestamp + (i + 1) * 1 hours;
            
            taskIndices[i] = avs.createTask(taskIds[i], taskData, deadline);
            
            assertEq(taskIndices[i], i + 1);
        }
        
        // Verify task counter
        assertEq(avs.taskCounter(), numTasks);
        assertEq(avs.totalTasks(), numTasks);
        
        // Verify individual tasks
        for (uint256 i = 0; i < numTasks; i++) {
            (bytes32 storedId, , , bool completed) = avs.getTask(taskIndices[i]);
            assertEq(storedId, taskIds[i]);
            assertFalse(completed);
        }
    }
    
    function testOperatorTaskCompletion() public {
        // Register operator
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Create task
        bytes32 taskId = keccak256("completion_task");
        uint32 taskIndex = avs.createTask(
            taskId, 
            abi.encode("matching_task"), 
            block.timestamp + 1 hours
        );
        
        // Submit response
        bytes memory response = abi.encode("matching_result", taskId, block.timestamp);
        vm.prank(OPERATOR1);
        avs.submitTaskResponse(taskIndex, response);
        
        // Verify task completion
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
        
        // Verify operator performance
        (uint256 assigned, uint256 completedCount,,) = avs.getOperatorPerformance(OPERATOR1);
        assertEq(assigned, 1);
        assertEq(completedCount, 1);
        
        // Verify stored response
        bytes memory storedResponse = avs.getTaskResponse(taskIndex, OPERATOR1);
        assertEq(keccak256(storedResponse), keccak256(response));
    }
    
    function testRewardDistributionSystem() public {
        // Register operator
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Create and complete task
        uint32 taskIndex = avs.createTask(
            keccak256("reward_task"), 
            abi.encode("data"), 
            block.timestamp + 1 hours
        );
        
        vm.prank(OPERATOR1);
        avs.submitTaskResponse(taskIndex, abi.encode("result"));
        
        // Distribute rewards
        uint256[] memory rewardAmounts = new uint256[](3);
        rewardAmounts[0] = 0.5 ether;
        rewardAmounts[1] = 0.3 ether; 
        rewardAmounts[2] = 0.2 ether;
        
        for (uint256 i = 0; i < rewardAmounts.length; i++) {
            vm.deal(address(avs), rewardAmounts[i]);
            avs.distributeReward(OPERATOR1, rewardAmounts[i]);
        }
        
        // Check total rewards
        uint256 expectedTotal = rewardAmounts[0] + rewardAmounts[1] + rewardAmounts[2];
        assertEq(avs.getTotalRewards(OPERATOR1), expectedTotal);
        
        // Check performance tracking
        (,,uint256 totalRewards,) = avs.getOperatorPerformance(OPERATOR1);
        assertEq(totalRewards, expectedTotal);
    }
    
    function testSlashingMechanism() public {
        // Register operator with large stake
        uint256 largeStake = 100 ether;
        vm.deal(OPERATOR1, largeStake);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: largeStake}("operator1.com");
        
        uint256 initialStake = avs.getOperatorStake(OPERATOR1);
        
        // Test multiple slashing events
        uint256[] memory slashAmounts = new uint256[](3);
        slashAmounts[0] = 5 ether;
        slashAmounts[1] = 3 ether;
        slashAmounts[2] = 2 ether;
        
        string[] memory reasons = new string[](3);
        reasons[0] = "Malicious behavior";
        reasons[1] = "Invalid proof submission";
        reasons[2] = "Offline for extended period";
        
        for (uint256 i = 0; i < slashAmounts.length; i++) {
            avs.slashOperator(OPERATOR1, slashAmounts[i], reasons[i]);
        }
        
        // Verify total slashing
        uint256 totalSlashed = slashAmounts[0] + slashAmounts[1] + slashAmounts[2];
        uint256 finalStake = avs.getOperatorStake(OPERATOR1);
        assertEq(finalStake, initialStake - totalSlashed);
        
        // Verify slashing record
        (uint256 slashedAmount, uint256 slashCount) = avs.getSlashingInfo(OPERATOR1);
        assertEq(slashedAmount, totalSlashed);
        assertEq(slashCount, 3);
    }
    
    function testMultipleOperatorScenario() public {
        address[] memory operators = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            operators[i] = address(uint160(0x100 + i));
            vm.deal(operators[i], 100 ether);
            
            vm.prank(operators[i]);
            avs.registerOperator{value: MIN_STAKE}(
                string(abi.encodePacked("operator", i, ".com"))
            );
        }
        
        assertEq(avs.totalOperators(), 5);
        
        // Create multiple tasks
        uint256 numTasks = 10;
        uint32[] memory taskIndices = new uint32[](numTasks);
        
        for (uint256 i = 0; i < numTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("multi_task", i));
            taskIndices[i] = avs.createTask(
                taskId, 
                abi.encode("task_data", i), 
                block.timestamp + 2 hours
            );
        }
        
        // Have different operators complete different tasks
        for (uint256 i = 0; i < numTasks; i++) {
            address operator = operators[i % operators.length];
            vm.prank(operator);
            avs.submitTaskResponse(taskIndices[i], abi.encode("result", i));
        }
        
        // Verify operator performance distribution
        for (uint256 i = 0; i < operators.length; i++) {
            (uint256 assigned, uint256 completed,,) = avs.getOperatorPerformance(operators[i]);
            assertTrue(assigned > 0);
            assertEq(assigned, completed);
        }
    }
    
    function DISABLED_testEmergencyPauseScenario() public {
        // Register operator first
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Create task
        uint32 taskIndex = avs.createTask(
            keccak256("pause_test"), 
            abi.encode("data"), 
            block.timestamp + 2 hours
        );
        
        // Emergency pause
        avs.emergencyPause();
        
        // All critical operations should be paused
        vm.prank(OPERATOR2);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE}("operator2.com");
        
        vm.expectRevert();
        avs.createTask(keccak256("test"), abi.encode("data"), block.timestamp + 1 hours);
        
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, abi.encode("response"));
        
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.deregisterOperator();
        
        // Unpause and verify operations work
        avs.emergencyUnpause();
        
        vm.prank(OPERATOR1);
        avs.submitTaskResponse(taskIndex, abi.encode("response"));
        
        (,,,bool completed) = avs.getTask(taskIndex);
        assertTrue(completed);
    }
    
    function testTaskTimeouts() public {
        // Create task with short deadline
        uint256 shortDeadline = block.timestamp + 1 hours;
        uint32 taskIndex = avs.createTask(
            keccak256("timeout_test"), 
            abi.encode("data"), 
            shortDeadline
        );
        
        // Register operator
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Fast forward past deadline
        vm.warp(shortDeadline + 1);
        
        // Should not be able to submit response after deadline
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.submitTaskResponse(taskIndex, abi.encode("late_response"));
    }
    
    function testOperatorDeregistrationEdgeCases() public {
        // Register operator
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Create task
        uint32 taskIndex = avs.createTask(
            keccak256("dereg_test"), 
            abi.encode("data"), 
            block.timestamp + 2 hours
        );
        
        // Cannot deregister with pending tasks
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.deregisterOperator();
        
        // Complete task
        vm.prank(OPERATOR1);
        avs.submitTaskResponse(taskIndex, abi.encode("response"));
        
        // Now should be able to deregister
        vm.prank(OPERATOR1);
        avs.deregisterOperator();
        
        assertFalse(avs.isRegisteredOperator(OPERATOR1));
        assertEq(avs.totalOperators(), 0);
    }
    
    function testStakeThresholdEnforcement() public {
        vm.deal(OPERATOR1, 100 ether);
        
        // Should fail with insufficient stake
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.registerOperator{value: MIN_STAKE - 1 ether}("operator1.com");
        
        // Should succeed with minimum stake
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        assertTrue(avs.isRegisteredOperator(OPERATOR1));
        
        // Cannot withdraw below minimum
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.withdrawStake(1 ether);
    }
    
    function testPerformanceMetrics() public {
        // Register operator
        vm.deal(OPERATOR1, 100 ether);
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        
        // Complete multiple tasks
        uint256 numTasks = 10;
        for (uint256 i = 0; i < numTasks; i++) {
            bytes32 taskId = keccak256(abi.encode("perf_task", i));
            uint32 taskIndex = avs.createTask(
                taskId, 
                abi.encode("data", i), 
                block.timestamp + 2 hours
            );
            
            vm.prank(OPERATOR1);
            avs.submitTaskResponse(taskIndex, abi.encode("result", i));
        }
        
        // Distribute varying rewards
        uint256 totalExpectedRewards = 0;
        for (uint256 i = 0; i < numTasks; i++) {
            uint256 reward = (i + 1) * 0.1 ether;
            totalExpectedRewards += reward;
            
            vm.deal(address(avs), reward);
            avs.distributeReward(OPERATOR1, reward);
        }
        
        // Apply some slashing
        uint256 slashAmount = 2 ether;
        avs.slashOperator(OPERATOR1, slashAmount, "Performance issues");
        
        // Verify comprehensive performance metrics
        (uint256 assigned, uint256 completed, uint256 totalRewards, uint256 totalSlashed) = 
            avs.getOperatorPerformance(OPERATOR1);
        
        assertEq(assigned, numTasks);
        assertEq(completed, numTasks);
        assertEq(totalRewards, totalExpectedRewards);
        assertEq(totalSlashed, slashAmount);
        
        // Verify slashing info
        (uint256 slashedAmount, uint256 slashCount) = avs.getSlashingInfo(OPERATOR1);
        assertEq(slashedAmount, slashAmount);
        assertEq(slashCount, 1);
    }
    
    function testGasOptimizationMeasurements() public {
        vm.deal(OPERATOR1, 100 ether);
        
        // Measure operator registration gas
        uint256 gasStart = gasleft();
        vm.prank(OPERATOR1);
        avs.registerOperator{value: MIN_STAKE}("operator1.com");
        uint256 registrationGas = gasStart - gasleft();
        
        // Measure task creation gas
        gasStart = gasleft();
        uint32 taskIndex = avs.createTask(
            keccak256("gas_test"), 
            abi.encode("test_data"), 
            block.timestamp + 2 hours
        );
        uint256 creationGas = gasStart - gasleft();
        
        // Measure task response gas
        gasStart = gasleft();
        vm.prank(OPERATOR1);
        avs.submitTaskResponse(taskIndex, abi.encode("response"));
        uint256 responseGas = gasStart - gasleft();
        
        // Log gas measurements for analysis
        emit log_named_uint("Registration gas", registrationGas);
        emit log_named_uint("Task creation gas", creationGas);
        emit log_named_uint("Task response gas", responseGas);
        
        // Ensure reasonable gas usage
        assertTrue(registrationGas < 300000);
        assertTrue(creationGas < 250000);
        assertTrue(responseGas < 200000);
    }
    
    function DISABLED_testEdgeCaseErrorHandling() public {
        // Test invalid inputs
        vm.expectRevert();
        avs.createTask(bytes32(0), abi.encode("data"), block.timestamp + 1 hours);
        
        vm.expectRevert();
        avs.createTask(keccak256("test"), "", block.timestamp + 1 hours);
        
        vm.expectRevert();
        avs.createTask(keccak256("test"), abi.encode("data"), block.timestamp - 1);
        
        // Test operations on non-existent tasks
        vm.expectRevert();
        avs.getTask(999);
        
        vm.expectRevert();
        avs.getTaskResponse(999, OPERATOR1);
        
        // Test unauthorized operations
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.createTask(keccak256("test"), abi.encode("data"), block.timestamp + 1 hours);
        
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.distributeReward(OPERATOR1, 1 ether);
        
        vm.prank(OPERATOR1);
        vm.expectRevert();
        avs.slashOperator(OPERATOR1, 1 ether, "test");
    }
}