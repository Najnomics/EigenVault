// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IEigenVaultServiceManager
/// @notice Interface for the simplified EigenVault service manager contract
interface IEigenVaultServiceManager {
    /// @notice Register operator with stake
    function registerOperator() external payable;

    /// @notice Create a task for order matching
    function createTask(
        bytes32 ordersSetHash,
        uint256 deadline
    ) external returns (bytes32);

    /// @notice Submit task response
    function submitTaskResponse(
        bytes32 taskId,
        bytes calldata response,
        bytes32 resultHash
    ) external;

    /// @notice Get task details
    function getTask(bytes32 taskId) external view returns (
        bytes32 ordersSetHash,
        uint256 deadline,
        bool completed,
        address assignedOperator,
        bytes32 resultHash
    );

    /// @notice Get operator information
    function getOperatorInfo(address operator) external view returns (
        bool isRegistered,
        uint256 stake,
        bool isSlashed
    );

    /// @notice Slash operator for misbehavior
    function slashOperator(address operator, uint256 amount) external;
}