// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockEigenVaultAVS
/// @notice Mock implementation of EigenVaultAVS for testing
contract MockEigenVaultAVS {
    mapping(bytes32 => address[]) public assignedOperators;
    mapping(uint32 => bytes32) public taskToOrder;
    mapping(bytes32 => bool) public completedTasks;
    
    uint32 public taskCounter;
    
    function createMatchingTask(
        bytes32 orderId,
        bytes32 /* poolId */,
        bytes32 /* commitment */
    ) external returns (uint32 taskIndex) {
        taskCounter++;
        taskToOrder[taskCounter] = orderId;
        completedTasks[orderId] = false;
        return taskCounter;
    }
    
    function getAssignedOperators(bytes32 matchId) external view returns (address[] memory) {
        return assignedOperators[matchId];
    }
    
    function requestConsensus(bytes32 /* taskId */, bytes32 /* consensusHash */) external {
        // Mock implementation - no-op
    }
    
    function setAssignedOperators(bytes32 matchId, address[] calldata operators) external {
        assignedOperators[matchId] = operators;
    }
}