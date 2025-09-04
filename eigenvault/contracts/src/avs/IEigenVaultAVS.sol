// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IEigenVaultAVS
/// @notice Minimal interface for EigenVault AVS integration
/// @dev This replaces the complex redundant AVS contracts since Go implementation handles the real AVS logic
interface IEigenVaultAVS {
    /// @notice Create a matching task for the Go AVS operators
    /// @param orderId The order identifier
    /// @param poolId The pool identifier
    /// @param commitment The order commitment hash
    /// @return taskIndex The task index for tracking
    function createMatchingTask(
        bytes32 orderId,
        bytes32 poolId,
        bytes32 commitment
    ) external returns (uint32 taskIndex);

    /// @notice Submit proof of order matching (called by Go operators)
    /// @param taskIndex The task index
    /// @param proof The ZK proof of matching
    /// @param signatures The operator signatures
    function submitMatchingProof(
        uint32 taskIndex,
        bytes calldata proof,
        bytes calldata signatures
    ) external;

    /// @notice Get assigned operators for a task (called by hook)
    /// @param matchId The match identifier
    /// @return operators Array of assigned operator addresses
    function getAssignedOperators(bytes32 matchId) external view returns (address[] memory operators);

    /// @notice Request consensus from operators (called by hook)
    /// @param taskId The consensus task ID
    /// @param consensusHash The hash to reach consensus on
    function requestConsensus(bytes32 taskId, bytes32 consensusHash) external;
}