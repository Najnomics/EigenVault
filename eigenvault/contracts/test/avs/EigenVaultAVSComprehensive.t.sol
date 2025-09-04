// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {EigenVaultAVS} from "../../src/avs/EigenVaultAVS.sol";
import {IEigenVaultAVS} from "../../src/avs/IEigenVaultAVS.sol";

/// @title EigenVaultAVSComprehensive
/// @notice Comprehensive test suite for EigenVaultAVS contract covering all AVS functionalities
contract EigenVaultAVSComprehensiveTest is Test {
    
    EigenVaultAVS public eigenVaultAVS;
    
    // Test addresses
    address public owner = address(this);
    address public operator1 = address(0x1);
    address public operator2 = address(0x2);
    address public operator3 = address(0x3);
    address public maliciousOperator = address(0x666);
    address public unauthorizedUser = address(0x999);
    
    // Test constants
    uint256 public constant MIN_STAKE = 32 ether;
    uint256 public constant TEST_STAKE = 100 ether;
    string public constant OPERATOR1_URL = "http://operator1.com";
    string public constant OPERATOR2_URL = "http://operator2.com";
    
    // Events
    event OperatorRegistered(address indexed operator, string metadataURL);
    event OperatorDeregistered(address indexed operator);
    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed taskId);
    event TaskResponseSubmitted(uint32 indexed taskIndex, address indexed operator);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 result);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event RewardDistributed(address indexed operator, uint256 amount);
    event EmergencyPauseActivated();
    event EmergencyPauseDeactivated();
    
    function setUp() public {
        eigenVaultAVS = new EigenVaultAVS();
        
        // Fund test accounts
        vm.deal(operator1, 1000 ether);
        vm.deal(operator2, 1000 ether);
        vm.deal(operator3, 1000 ether);
        vm.deal(maliciousOperator, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment_success() public view {
        assertEq(eigenVaultAVS.owner(), owner);
        assertEq(eigenVaultAVS.totalOperators(), 0);
        assertEq(eigenVaultAVS.totalTasks(), 0);
        assertFalse(eigenVaultAVS.paused());
    }

    /*//////////////////////////////////////////////////////////////
                         OPERATOR REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_register_operator_success() public {
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operator1, OPERATOR1_URL);
        
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator1));
        assertEq(eigenVaultAVS.totalOperators(), 1);
        assertEq(eigenVaultAVS.getOperatorStake(operator1), TEST_STAKE);
        assertEq(eigenVaultAVS.getOperatorMetadataURL(operator1), OPERATOR1_URL);
    }

    function test_register_operator_insufficient_stake() public {
        vm.startPrank(operator1);
        vm.expectRevert("Insufficient stake");
        eigenVaultAVS.registerOperator{value: MIN_STAKE - 1}(OPERATOR1_URL);
        vm.stopPrank();
    }

    function test_register_operator_already_registered() public {
        // Register once
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Try to register again
        vm.expectRevert("Already registered");
        eigenVaultAVS.registerOperator{value: TEST_STAKE}("new_url");
        vm.stopPrank();
    }

    function test_register_operator_empty_url() public {
        vm.startPrank(operator1);
        vm.expectRevert("Empty metadata URL");
        eigenVaultAVS.registerOperator{value: TEST_STAKE}("");
        vm.stopPrank();
    }

    function test_register_multiple_operators() public {
        // Register operator1
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Register operator2
        vm.startPrank(operator2);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR2_URL);
        vm.stopPrank();
        
        // Register operator3
        vm.startPrank(operator3);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}("http://operator3.com");
        vm.stopPrank();
        
        assertEq(eigenVaultAVS.totalOperators(), 3);
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator1));
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator2));
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator3));
    }

    /*//////////////////////////////////////////////////////////////
                       OPERATOR DEREGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deregister_operator_success() public {
        // Register first
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Deregister
        vm.expectEmit(true, true, true, true);
        emit OperatorDeregistered(operator1);
        
        eigenVaultAVS.deregisterOperator();
        vm.stopPrank();
        
        assertFalse(eigenVaultAVS.isRegisteredOperator(operator1));
        assertEq(eigenVaultAVS.totalOperators(), 0);
        assertEq(eigenVaultAVS.getOperatorStake(operator1), 0);
    }

    function test_deregister_operator_not_registered() public {
        vm.startPrank(operator1);
        vm.expectRevert("Not registered");
        eigenVaultAVS.deregisterOperator();
        vm.stopPrank();
    }

    function test_deregister_operator_with_pending_tasks() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create task
        bytes32 taskId = keccak256("test_task");
        eigenVaultAVS.createTask(taskId, abi.encode("task_data"), block.timestamp + 1 hours);
        
        // Try to deregister with pending tasks
        vm.startPrank(operator1);
        vm.expectRevert("Has pending tasks");
        eigenVaultAVS.deregisterOperator();
        vm.stopPrank();
    }

    function test_deregister_operator_stake_withdrawal() public {
        uint256 initialBalance = operator1.balance;
        
        // Register
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Deregister
        eigenVaultAVS.deregisterOperator();
        vm.stopPrank();
        
        // Check stake is returned
        assertEq(operator1.balance, initialBalance);
    }

    /*//////////////////////////////////////////////////////////////
                           TASK CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_create_task_success() public {
        bytes32 taskId = keccak256("test_task");
        bytes memory taskData = abi.encode("order_matching_task");
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.expectEmit(true, true, true, true);
        emit TaskCreated(1, taskId);
        
        uint32 taskIndex = eigenVaultAVS.createTask(taskId, taskData, deadline);
        
        assertEq(taskIndex, 1);
        assertEq(eigenVaultAVS.totalTasks(), 1);
        
        (bytes32 storedTaskId, bytes memory storedData, uint256 storedDeadline, bool completed) = 
            eigenVaultAVS.getTask(taskIndex);
        
        assertEq(storedTaskId, taskId);
        assertEq(keccak256(storedData), keccak256(taskData));
        assertEq(storedDeadline, deadline);
        assertFalse(completed);
    }

    function test_create_task_only_owner() public {
        bytes32 taskId = keccak256("test_task");
        bytes memory taskData = abi.encode("order_matching_task");
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.startPrank(operator1);
        vm.expectRevert();
        eigenVaultAVS.createTask(taskId, taskData, deadline);
        vm.stopPrank();
    }

    function test_create_task_zero_task_id() public {
        bytes memory taskData = abi.encode("order_matching_task");
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.expectRevert("Invalid task ID");
        eigenVaultAVS.createTask(bytes32(0), taskData, deadline);
    }

    function test_create_task_empty_data() public {
        bytes32 taskId = keccak256("test_task");
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.expectRevert("Empty task data");
        eigenVaultAVS.createTask(taskId, "", deadline);
    }

    function test_create_task_past_deadline() public {
        bytes32 taskId = keccak256("test_task");
        bytes memory taskData = abi.encode("order_matching_task");
        uint256 pastDeadline = block.timestamp - 1 hours;
        
        vm.expectRevert("Invalid deadline");
        eigenVaultAVS.createTask(taskId, taskData, pastDeadline);
    }

    function test_create_multiple_tasks() public {
        bytes memory taskData = abi.encode("order_matching_task");
        uint256 deadline = block.timestamp + 1 hours;
        
        for (uint i = 0; i < 5; i++) {
            bytes32 taskId = keccak256(abi.encode("task", i));
            uint32 taskIndex = eigenVaultAVS.createTask(taskId, taskData, deadline);
            assertEq(taskIndex, i + 1);
        }
        
        assertEq(eigenVaultAVS.totalTasks(), 5);
    }

    /*//////////////////////////////////////////////////////////////
                         TASK RESPONSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_submit_task_response_success() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Submit response
        bytes memory response = abi.encode("task_response");
        
        vm.expectEmit(true, true, true, true);
        emit TaskResponseSubmitted(taskIndex, operator1);
        
        vm.startPrank(operator1);
        eigenVaultAVS.submitTaskResponse(taskIndex, response);
        vm.stopPrank();
        
        bytes memory storedResponse = eigenVaultAVS.getTaskResponse(taskIndex, operator1);
        assertEq(keccak256(storedResponse), keccak256(response));
    }

    function test_submit_task_response_not_registered() public {
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Try to submit response without being registered
        vm.startPrank(operator1);
        vm.expectRevert("Not registered operator");
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response"));
        vm.stopPrank();
    }

    function test_submit_task_response_nonexistent_task() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Try to submit response for nonexistent task
        vm.expectRevert("Task not found");
        eigenVaultAVS.submitTaskResponse(999, abi.encode("response"));
        vm.stopPrank();
    }

    function test_submit_task_response_expired() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create task with short deadline
        bytes32 taskId = keccak256("test_task");
        uint256 shortDeadline = block.timestamp + 1 seconds;
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            shortDeadline
        );
        
        // Fast forward past deadline
        vm.warp(shortDeadline + 1);
        
        // Try to submit response
        vm.startPrank(operator1);
        vm.expectRevert("Task deadline passed");
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response"));
        vm.stopPrank();
    }

    function test_submit_task_response_already_completed() public {
        // Register operators
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.startPrank(operator2);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR2_URL);
        vm.stopPrank();
        
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Submit response from operator1
        vm.startPrank(operator1);
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response1"));
        vm.stopPrank();
        
        // Complete task
        eigenVaultAVS.completeTask(taskIndex, keccak256("result"));
        
        // Try to submit response from operator2
        vm.startPrank(operator2);
        vm.expectRevert("Task already completed");
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response2"));
        vm.stopPrank();
    }

    function test_submit_task_response_duplicate() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Submit response
        vm.startPrank(operator1);
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response"));
        
        // Try to submit again
        vm.expectRevert("Already responded");
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("new_response"));
        vm.stopPrank();
    }

    function test_submit_task_response_empty() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Try to submit empty response
        vm.startPrank(operator1);
        vm.expectRevert("Empty response");
        eigenVaultAVS.submitTaskResponse(taskIndex, "");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         TASK COMPLETION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_complete_task_success() public {
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Complete task
        bytes32 result = keccak256("task_result");
        
        vm.expectEmit(true, true, true, true);
        emit TaskCompleted(taskIndex, result);
        
        eigenVaultAVS.completeTask(taskIndex, result);
        
        (,, , bool completed) = eigenVaultAVS.getTask(taskIndex);
        assertTrue(completed);
        assertEq(eigenVaultAVS.getTaskResult(taskIndex), result);
    }

    function test_complete_task_only_owner() public {
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Try to complete as non-owner
        vm.startPrank(operator1);
        vm.expectRevert();
        eigenVaultAVS.completeTask(taskIndex, keccak256("result"));
        vm.stopPrank();
    }

    function test_complete_task_nonexistent() public {
        vm.expectRevert("Task not found");
        eigenVaultAVS.completeTask(999, keccak256("result"));
    }

    function test_complete_task_already_completed() public {
        // Create task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        // Complete once
        eigenVaultAVS.completeTask(taskIndex, keccak256("result1"));
        
        // Try to complete again
        vm.expectRevert("Already completed");
        eigenVaultAVS.completeTask(taskIndex, keccak256("result2"));
    }

    /*//////////////////////////////////////////////////////////////
                           SLASHING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_slash_operator_success() public {
        // Register operator with stake
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        uint256 slashAmount = TEST_STAKE / 4; // 25%
        string memory reason = "Malicious behavior detected";
        
        vm.expectEmit(true, true, true, true);
        emit OperatorSlashed(operator1, slashAmount, reason);
        
        eigenVaultAVS.slashOperator(operator1, slashAmount, reason);
        
        // Check stake is reduced
        assertEq(eigenVaultAVS.getOperatorStake(operator1), TEST_STAKE - slashAmount);
        
        // Check slashing record
        (uint256 totalSlashed, uint256 slashCount) = eigenVaultAVS.getSlashingInfo(operator1);
        assertEq(totalSlashed, slashAmount);
        assertEq(slashCount, 1);
    }

    function test_slash_operator_only_owner() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.startPrank(operator2);
        vm.expectRevert();
        eigenVaultAVS.slashOperator(operator1, TEST_STAKE / 4, "test");
        vm.stopPrank();
    }

    function test_slash_operator_not_registered() public {
        vm.expectRevert("Operator not registered");
        eigenVaultAVS.slashOperator(operator1, 1 ether, "test");
    }

    function test_slash_operator_insufficient_stake() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.expectRevert("Insufficient stake to slash");
        eigenVaultAVS.slashOperator(operator1, TEST_STAKE + 1 ether, "test");
    }

    function test_slash_operator_empty_reason() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.expectRevert("Empty slashing reason");
        eigenVaultAVS.slashOperator(operator1, 1 ether, "");
    }

    function test_slash_operator_multiple_times() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        uint256 slashAmount1 = 10 ether;
        uint256 slashAmount2 = 20 ether;
        
        // First slash
        eigenVaultAVS.slashOperator(operator1, slashAmount1, "First offense");
        
        // Second slash
        eigenVaultAVS.slashOperator(operator1, slashAmount2, "Second offense");
        
        // Check cumulative slashing
        (uint256 totalSlashed, uint256 slashCount) = eigenVaultAVS.getSlashingInfo(operator1);
        assertEq(totalSlashed, slashAmount1 + slashAmount2);
        assertEq(slashCount, 2);
        assertEq(eigenVaultAVS.getOperatorStake(operator1), TEST_STAKE - slashAmount1 - slashAmount2);
    }

    function test_slash_operator_full_stake() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Slash full stake
        eigenVaultAVS.slashOperator(operator1, TEST_STAKE, "Full slash");
        
        // Operator should be automatically deregistered
        assertFalse(eigenVaultAVS.isRegisteredOperator(operator1));
        assertEq(eigenVaultAVS.getOperatorStake(operator1), 0);
        assertEq(eigenVaultAVS.totalOperators(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           REWARD DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_distribute_reward_success() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Fund the contract for rewards
        vm.deal(address(eigenVaultAVS), 10 ether);
        
        uint256 rewardAmount = 1 ether;
        uint256 initialBalance = operator1.balance;
        
        vm.expectEmit(true, true, true, true);
        emit RewardDistributed(operator1, rewardAmount);
        
        eigenVaultAVS.distributeReward(operator1, rewardAmount);
        
        // Check reward is sent
        assertEq(operator1.balance, initialBalance + rewardAmount);
        
        // Check reward record
        assertEq(eigenVaultAVS.getTotalRewards(operator1), rewardAmount);
    }

    function test_distribute_reward_only_owner() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.startPrank(operator2);
        vm.expectRevert();
        eigenVaultAVS.distributeReward(operator1, 1 ether);
        vm.stopPrank();
    }

    function test_distribute_reward_not_registered() public {
        vm.expectRevert("Operator not registered");
        eigenVaultAVS.distributeReward(operator1, 1 ether);
    }

    function test_distribute_reward_insufficient_balance() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Contract has no balance
        vm.expectRevert("Insufficient contract balance");
        eigenVaultAVS.distributeReward(operator1, 1 ether);
    }

    function test_distribute_reward_zero_amount() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.expectRevert("Invalid reward amount");
        eigenVaultAVS.distributeReward(operator1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergency_pause_success() public {
        vm.expectEmit(true, true, true, true);
        emit EmergencyPauseActivated();
        
        eigenVaultAVS.emergencyPause();
        
        assertTrue(eigenVaultAVS.paused());
    }

    function test_emergency_pause_only_owner() public {
        vm.startPrank(operator1);
        vm.expectRevert();
        eigenVaultAVS.emergencyPause();
        vm.stopPrank();
    }

    function test_emergency_pause_already_paused() public {
        eigenVaultAVS.emergencyPause();
        
        vm.expectRevert("Already paused");
        eigenVaultAVS.emergencyPause();
    }

    function test_emergency_unpause_success() public {
        // Pause first
        eigenVaultAVS.emergencyPause();
        
        vm.expectEmit(true, true, true, true);
        emit EmergencyPauseDeactivated();
        
        eigenVaultAVS.emergencyUnpause();
        
        assertFalse(eigenVaultAVS.paused());
    }

    function test_emergency_unpause_only_owner() public {
        eigenVaultAVS.emergencyPause();
        
        vm.startPrank(operator1);
        vm.expectRevert();
        eigenVaultAVS.emergencyUnpause();
        vm.stopPrank();
    }

    function test_emergency_unpause_not_paused() public {
        vm.expectRevert("Not paused");
        eigenVaultAVS.emergencyUnpause();
    }

    function test_paused_blocks_operations() public {
        // Register operator first
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Pause
        eigenVaultAVS.emergencyPause();
        
        // Try various operations that should fail
        vm.startPrank(operator2);
        vm.expectRevert("Pausable: paused");
        eigenVaultAVS.registerOperator{value: TEST_STAKE}("url");
        vm.stopPrank();
        
        vm.startPrank(operator1);
        vm.expectRevert("Pausable: paused");
        eigenVaultAVS.deregisterOperator();
        vm.stopPrank();
        
        vm.expectRevert("Pausable: paused");
        eigenVaultAVS.createTask(keccak256("task"), abi.encode("data"), block.timestamp + 1 hours);
    }

    /*//////////////////////////////////////////////////////////////
                           GETTER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_get_registered_operators() public {
        // Register multiple operators
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.startPrank(operator2);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR2_URL);
        vm.stopPrank();
        
        address[] memory operators = eigenVaultAVS.getRegisteredOperators();
        assertEq(operators.length, 2);
        
        // Check operators are in the list
        bool found1 = false;
        bool found2 = false;
        for (uint i = 0; i < operators.length; i++) {
            if (operators[i] == operator1) found1 = true;
            if (operators[i] == operator2) found2 = true;
        }
        assertTrue(found1);
        assertTrue(found2);
    }

    function test_get_active_tasks() public {
        // Create multiple tasks
        for (uint i = 0; i < 3; i++) {
            bytes32 taskId = keccak256(abi.encode("task", i));
            eigenVaultAVS.createTask(taskId, abi.encode("data", i), block.timestamp + 1 hours);
        }
        
        uint32[] memory activeTasks = eigenVaultAVS.getActiveTasks();
        assertEq(activeTasks.length, 3);
        
        // Complete one task
        eigenVaultAVS.completeTask(1, keccak256("result"));
        
        activeTasks = eigenVaultAVS.getActiveTasks();
        assertEq(activeTasks.length, 2);
    }

    function test_get_operator_performance() public {
        // Register operator
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        // Create and respond to task
        bytes32 taskId = keccak256("test_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("task_data"),
            block.timestamp + 1 hours
        );
        
        vm.startPrank(operator1);
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response"));
        vm.stopPrank();
        
        (uint256 tasksAssigned, uint256 tasksCompleted, uint256 totalRewards, uint256 totalSlashed) = 
            eigenVaultAVS.getOperatorPerformance(operator1);
        
        assertEq(tasksAssigned, 1);
        assertEq(tasksCompleted, 0); // Not completed yet
        assertEq(totalRewards, 0);
        assertEq(totalSlashed, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_maximum_stake_registration() public {
        uint256 maxStake = 1000000 ether;
        vm.deal(operator1, maxStake);
        
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: maxStake}(OPERATOR1_URL);
        vm.stopPrank();
        
        assertEq(eigenVaultAVS.getOperatorStake(operator1), maxStake);
    }

    function test_task_with_maximum_data() public {
        bytes32 taskId = keccak256("big_task");
        bytes memory bigData = new bytes(10000); // 10KB
        
        // Fill with test data
        for (uint i = 0; i < 10000; i++) {
            bigData[i] = bytes1(uint8(i % 256));
        }
        
        uint32 taskIndex = eigenVaultAVS.createTask(taskId, bigData, block.timestamp + 1 hours);
        
        (,bytes memory storedData,,) = eigenVaultAVS.getTask(taskIndex);
        assertEq(storedData.length, 10000);
    }

    function test_concurrent_operator_registration() public {
        // Simulate concurrent registrations
        address[] memory operators = new address[](10);
        
        for (uint i = 0; i < 10; i++) {
            operators[i] = address(uint160(i + 100));
            vm.deal(operators[i], TEST_STAKE);
            
            vm.startPrank(operators[i]);
            eigenVaultAVS.registerOperator{value: TEST_STAKE}(
                string(abi.encodePacked("http://operator", i, ".com"))
            );
            vm.stopPrank();
        }
        
        assertEq(eigenVaultAVS.totalOperators(), 10);
        
        address[] memory registered = eigenVaultAVS.getRegisteredOperators();
        assertEq(registered.length, 10);
    }

    function test_operator_restaking() public {
        // Register with initial stake
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Add more stake
        uint256 additionalStake = 50 ether;
        eigenVaultAVS.addStake{value: additionalStake}();
        vm.stopPrank();
        
        assertEq(eigenVaultAVS.getOperatorStake(operator1), TEST_STAKE + additionalStake);
    }

    function test_operator_partial_stake_withdrawal() public {
        // Register with stake
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        uint256 withdrawAmount = 20 ether;
        uint256 initialBalance = operator1.balance;
        
        eigenVaultAVS.withdrawStake(withdrawAmount);
        vm.stopPrank();
        
        assertEq(eigenVaultAVS.getOperatorStake(operator1), TEST_STAKE - withdrawAmount);
        assertEq(operator1.balance, initialBalance + withdrawAmount);
    }

    function test_operator_minimum_stake_enforcement() public {
        // Register with stake
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        
        // Try to withdraw below minimum
        uint256 excessiveWithdraw = TEST_STAKE - MIN_STAKE + 1 ether;
        
        vm.expectRevert("Would go below minimum stake");
        eigenVaultAVS.withdrawStake(excessiveWithdraw);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_full_task_lifecycle() public {
        // 1. Register operators
        vm.startPrank(operator1);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR1_URL);
        vm.stopPrank();
        
        vm.startPrank(operator2);
        eigenVaultAVS.registerOperator{value: TEST_STAKE}(OPERATOR2_URL);
        vm.stopPrank();
        
        // 2. Create task
        bytes32 taskId = keccak256("integration_task");
        uint32 taskIndex = eigenVaultAVS.createTask(
            taskId,
            abi.encode("complex_order_matching"),
            block.timestamp + 1 hours
        );
        
        // 3. Operators submit responses
        vm.startPrank(operator1);
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response_1"));
        vm.stopPrank();
        
        vm.startPrank(operator2);
        eigenVaultAVS.submitTaskResponse(taskIndex, abi.encode("response_2"));
        vm.stopPrank();
        
        // 4. Complete task
        eigenVaultAVS.completeTask(taskIndex, keccak256("final_result"));
        
        // 5. Distribute rewards
        vm.deal(address(eigenVaultAVS), 10 ether);
        eigenVaultAVS.distributeReward(operator1, 2 ether);
        eigenVaultAVS.distributeReward(operator2, 2 ether);
        
        // 6. Verify final state
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator1));
        assertTrue(eigenVaultAVS.isRegisteredOperator(operator2));
        
        (,,,bool completed) = eigenVaultAVS.getTask(taskIndex);
        assertTrue(completed);
        
        assertEq(eigenVaultAVS.getTotalRewards(operator1), 2 ether);
        assertEq(eigenVaultAVS.getTotalRewards(operator2), 2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}