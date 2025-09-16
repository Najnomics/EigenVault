// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {EigenVaultAVSTaskHook} from "@project/l2-contracts/EigenVaultAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

contract EigenVaultAVSTaskHookTest is Test {
    EigenVaultAVSTaskHook public taskHook;
    
    address public eigenVaultTaskRegistrar = address(0x1);
    address public eigenVaultHook = address(0x2);
    address public performer = address(0x3);
    address public caller = address(0x4);

    function setUp() public {
        taskHook = new EigenVaultAVSTaskHook();
        
        // Set up the hook addresses
        taskHook.setEigenVaultTaskRegistrar(eigenVaultTaskRegistrar);
        taskHook.setEigenVaultHook(eigenVaultHook);
    }

    function testSetEigenVaultHook() public {
        address newHook = address(0x123);
        
        vm.expectEmit(true, true, false, false);
        emit EigenVaultAVSTaskHook.EigenVaultHookUpdated(eigenVaultHook, newHook);
        
        taskHook.setEigenVaultHook(newHook);
        assertEq(taskHook.eigenVaultHook(), newHook);
    }

    function testSetEigenVaultHookFailsWithZeroAddress() public {
        vm.expectRevert("Invalid hook address");
        taskHook.setEigenVaultHook(address(0));
    }

    function testSetEigenVaultTaskRegistrar() public {
        address newRegistrar = address(0x456);
        taskHook.setEigenVaultTaskRegistrar(newRegistrar);
        assertEq(taskHook.eigenVaultTaskRegistrar(), newRegistrar);
    }

    function testSetEigenVaultTaskRegistrarFailsWithZeroAddress() public {
        vm.expectRevert("Invalid registrar address");
        taskHook.setEigenVaultTaskRegistrar(address(0));
    }

    function testCalculateTaskFeeOrderMatching() public {
        bytes memory payload = abi.encode(taskHook.ORDER_MATCHING_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertEq(fee, taskHook.ORDER_MATCHING_FEE());
    }

    function testCalculateTaskFeePrivacyExecution() public {
        bytes memory payload = abi.encode(taskHook.PRIVACY_EXECUTION_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertEq(fee, taskHook.PRIVACY_EXECUTION_FEE());
    }

    function testCalculateTaskFeeRewardsUpdate() public {
        bytes memory payload = abi.encode(taskHook.REWARDS_UPDATE_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertEq(fee, taskHook.REWARDS_UPDATE_FEE());
    }

    function testCalculateTaskFeeStakeValidation() public {
        bytes memory payload = abi.encode(taskHook.STAKE_VALIDATION_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertEq(fee, taskHook.STAKE_VALIDATION_FEE());
    }

    function testCalculateTaskFeeDefault() public {
        bytes memory payload = abi.encode(bytes32("unknown_task"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertEq(fee, taskHook.DEFAULT_TASK_FEE());
    }

    function testValidatePreTaskCreation() public view {
        bytes memory payload = abi.encode(taskHook.ORDER_MATCHING_TASK());
        payload = abi.encodePacked(payload, bytes(64)); // Add minimum required data
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        // Should not revert for valid task
        taskHook.validatePreTaskCreation(caller, taskParams);
    }

    function testValidatePreTaskCreationFailsWithInvalidCaller() public {
        bytes memory payload = abi.encode(taskHook.ORDER_MATCHING_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        vm.expectRevert("Invalid caller");
        taskHook.validatePreTaskCreation(address(0), taskParams);
    }

    function testValidatePreTaskCreationFailsWithInvalidPerformer() public {
        bytes memory payload = abi.encode(taskHook.ORDER_MATCHING_TASK());
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: address(0),
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        vm.expectRevert("Invalid performer address");
        taskHook.validatePreTaskCreation(caller, taskParams);
    }

    function testValidatePreTaskCreationFailsWithInvalidTaskType() public {
        bytes memory payload = abi.encode(bytes32("invalid_task"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            performerAddress: performer,
            payload: payload,
            maxFee: 1 ether,
            expiry: block.timestamp + 1 hours
        });

        vm.expectRevert("Invalid task type");
        taskHook.validatePreTaskCreation(caller, taskParams);
    }

    function testHandlePostTaskCreation() public {
        bytes32 taskHash = keccak256("test_task");
        
        vm.expectEmit(true, false, false, false);
        emit EigenVaultAVSTaskHook.TaskValidated(taskHash, bytes32(0), address(this));
        
        taskHook.handlePostTaskCreation(taskHash);
        
        assertEq(taskHook.getTaskCreationTime(taskHash), block.timestamp);
    }

    function testHandlePostTaskCreationFailsWithInvalidHash() public {
        vm.expectRevert("Invalid task hash");
        taskHook.handlePostTaskCreation(bytes32(0));
    }

    function testValidatePreTaskResultSubmission() public {
        bytes32 taskHash = keccak256("test_task");
        
        // First create the task
        taskHook.handlePostTaskCreation(taskHash);
        
        // Then validate result submission
        bytes memory cert = "test_certificate";
        bytes memory result = "test_result";
        
        taskHook.validatePreTaskResultSubmission(caller, taskHash, cert, result);
    }

    function testValidatePreTaskResultSubmissionFailsWithInvalidCaller() public {
        bytes32 taskHash = keccak256("test_task");
        bytes memory cert = "test_certificate";
        bytes memory result = "test_result";
        
        vm.expectRevert("Invalid caller");
        taskHook.validatePreTaskResultSubmission(address(0), taskHash, cert, result);
    }

    function testValidatePreTaskResultSubmissionFailsWithInvalidHash() public {
        bytes memory cert = "test_certificate";
        bytes memory result = "test_result";
        
        vm.expectRevert("Invalid task hash");
        taskHook.validatePreTaskResultSubmission(caller, bytes32(0), cert, result);
    }

    function testValidatePreTaskResultSubmissionFailsWithEmptyCert() public {
        bytes32 taskHash = keccak256("test_task");
        bytes memory result = "test_result";
        
        vm.expectRevert("Empty certificate");
        taskHook.validatePreTaskResultSubmission(caller, taskHash, "", result);
    }

    function testValidatePreTaskResultSubmissionFailsWithEmptyResult() public {
        bytes32 taskHash = keccak256("test_task");
        bytes memory cert = "test_certificate";
        
        vm.expectRevert("Empty result");
        taskHook.validatePreTaskResultSubmission(caller, taskHash, cert, "");
    }

    function testValidatePreTaskResultSubmissionFailsWithTaskNotFound() public {
        bytes32 taskHash = keccak256("nonexistent_task");
        bytes memory cert = "test_certificate";
        bytes memory result = "test_result";
        
        vm.expectRevert("Task not found");
        taskHook.validatePreTaskResultSubmission(caller, taskHash, cert, result);
    }

    function testValidatePreTaskResultSubmissionFailsWithExpiredTask() public {
        bytes32 taskHash = keccak256("test_task");
        
        // Create task
        taskHook.handlePostTaskCreation(taskHash);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + taskHook.MAX_TASK_EXECUTION_TIME() + 1);
        
        bytes memory cert = "test_certificate";
        bytes memory result = "test_result";
        
        vm.expectRevert("Task execution time expired");
        taskHook.validatePreTaskResultSubmission(caller, taskHash, cert, result);
    }

    function testHandlePostTaskResultSubmission() public {
        bytes32 taskHash = keccak256("test_task");
        
        // Create task first
        taskHook.handlePostTaskCreation(taskHash);
        
        vm.expectEmit(true, true, false, false);
        emit EigenVaultAVSTaskHook.TaskResultSubmitted(taskHash, caller);
        
        taskHook.handlePostTaskResultSubmission(caller, taskHash);
        
        assertTrue(taskHook.isTaskCompleted(taskHash));
    }

    function testHandlePostTaskResultSubmissionFailsWithInvalidHash() public {
        vm.expectRevert("Invalid task hash");
        taskHook.handlePostTaskResultSubmission(caller, bytes32(0));
    }

    function testHandlePostTaskResultSubmissionFailsWithAlreadyCompleted() public {
        bytes32 taskHash = keccak256("test_task");
        
        // Create and complete task
        taskHook.handlePostTaskCreation(taskHash);
        taskHook.handlePostTaskResultSubmission(caller, taskHash);
        
        // Try to complete again
        vm.expectRevert("Task already completed");
        taskHook.handlePostTaskResultSubmission(caller, taskHash);
    }

    function testTaskConstants() public view {
        assertEq(taskHook.ORDER_MATCHING_TASK(), keccak256("order_matching"));
        assertEq(taskHook.PRIVACY_EXECUTION_TASK(), keccak256("privacy_execution"));
        assertEq(taskHook.REWARDS_UPDATE_TASK(), keccak256("rewards_update"));
        assertEq(taskHook.STAKE_VALIDATION_TASK(), keccak256("stake_validation"));
    }

    function testFeeConstants() public view {
        assertEq(taskHook.ORDER_MATCHING_FEE(), 0.001 ether);
        assertEq(taskHook.PRIVACY_EXECUTION_FEE(), 0.005 ether);
        assertEq(taskHook.REWARDS_UPDATE_FEE(), 0.002 ether);
        assertEq(taskHook.STAKE_VALIDATION_FEE(), 0.001 ether);
        assertEq(taskHook.DEFAULT_TASK_FEE(), 0.001 ether);
        assertEq(taskHook.MAX_TASK_EXECUTION_TIME(), 1 hours);
    }
}