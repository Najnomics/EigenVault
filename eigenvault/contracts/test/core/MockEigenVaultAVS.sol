// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../src/avs/IEigenVaultAVS.sol";

/// @title MockEigenVaultAVS
/// @notice Mock implementation of EigenVaultAVS for testing
contract MockEigenVaultAVS is IEigenVaultAVS {
    mapping(bytes32 => address[]) public assignedOperators;
    mapping(uint32 => bytes32) public taskToOrder;
    mapping(bytes32 => bool) public completedTasks;
    
    uint32 public taskCounter;
    
    function createMatchingTask(
        bytes32 orderId,
        bytes32 /* poolId */,
        bytes32 /* commitment */
    ) external override returns (uint32 taskIndex) {
        taskCounter++;
        taskToOrder[taskCounter] = orderId;
        completedTasks[orderId] = false;
        return taskCounter;
    }
    
    function submitMatchingProof(
        uint32 taskIndex,
        bytes calldata /* proof */,
        bytes calldata /* signatures */
    ) external override {
        bytes32 orderId = taskToOrder[taskIndex];
        completedTasks[orderId] = true;
    }
    
    function getAssignedOperators(bytes32 matchId) external view override returns (address[] memory) {
        return assignedOperators[matchId];
    }
    
    function requestConsensus(bytes32 /* taskId */, bytes32 /* consensusHash */) external override {
        // Mock implementation - no-op
    }
    
    function setAssignedOperators(bytes32 matchId, address[] calldata operators) external {
        assignedOperators[matchId] = operators;
    }
}