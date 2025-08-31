// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IEigenVaultAVSServiceManager
 * @notice Interface for the EigenVault AVS Service Manager
 */
interface IEigenVaultAVSServiceManager {
    /// @notice Structure for matching tasks
    struct MatchingTask {
        bytes32 taskId;
        bytes32 poolId;
        bytes32 ordersHash;
        uint32 taskCreatedBlock;
        uint256 deadline;
        bool completed;
    }
    
    /// @notice Structure for task responses
    struct TaskResponse {
        address operator;
        bytes32 taskId;
        bytes32 matchHash;
        uint256 executionPrice;
        bytes signature;
        uint256 timestamp;
    }

    /// @notice Events
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event NewTaskCreated(uint32 indexed taskIndex, MatchingTask task);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, TaskResponse response);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 matchHash, uint256 executionPrice);
    event TaskChallenged(uint32 indexed taskIndex, address indexed challenger);
    event RewardsDistributed(uint32 indexed taskIndex, uint256 totalReward);
    event StakeSlashed(address indexed operator, uint256 amount);

    /// @notice Register as an operator in the AVS
    /// @param operatorSignature Signature proving operator authorization
    function registerOperator(bytes calldata operatorSignature) external payable;

    /// @notice Deregister from the AVS
    function deregisterOperator() external;

    /// @notice Create a new matching task
    /// @param taskId The task identifier
    /// @param poolId The pool identifier
    /// @param ordersHash The hash of the orders to be matched
    /// @return taskIndex The created task index
    function createMatchingTask(
        bytes32 taskId,
        bytes32 poolId,
        bytes32 ordersHash
    ) external returns (uint32);

    /// @notice Submit task response
    /// @param taskIndex The task index
    /// @param matchHash The hash of the matching result
    /// @param executionPrice The execution price for the match
    /// @param signature The operator's signature
    function submitTaskResponse(
        uint32 taskIndex,
        bytes32 matchHash,
        uint256 executionPrice,
        bytes calldata signature
    ) external;

    /// @notice Challenge a task response
    /// @param taskIndex The task index to challenge
    function challengeTask(uint32 taskIndex) external;

    /// @notice Get task details
    /// @param taskIndex The task index
    /// @return task The matching task details
    function getTask(uint32 taskIndex) external view returns (MatchingTask memory task);

    /// @notice Get operator information
    /// @param operator The operator address
    /// @return isRegistered Whether the operator is registered
    /// @return stake The operator's stake
    function getOperatorInfo(address operator) external view returns (bool isRegistered, uint256 stake);

    /// @notice Get all registered operators
    /// @return operators Array of registered operator addresses
    function getRegisteredOperators() external view returns (address[] memory operators);

    /// @notice Get task response for an operator
    /// @param taskIndex The task index
    /// @param operator The operator address
    /// @return response The task response
    function getTaskResponse(uint32 taskIndex, address operator) external view returns (TaskResponse memory response);
} 