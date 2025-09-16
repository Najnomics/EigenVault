// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAVSTaskHook} from "@eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

/**
 * @title EigenVaultAVSTaskHook
 * @dev L2 contract that validates and manages EigenVault task lifecycle.
 * This contract implements the IAVSTaskHook interface to integrate with Hourglass
 * framework and handles task validation, fee calculation, and lifecycle management
 * for EigenVault's privacy-preserving order matching operations.
 */
contract EigenVaultAVSTaskHook is IAVSTaskHook {
    /// @notice Task type constants
    bytes32 public constant ORDER_MATCHING_TASK = keccak256("order_matching");
    bytes32 public constant PRIVACY_EXECUTION_TASK = keccak256("privacy_execution");
    bytes32 public constant REWARDS_UPDATE_TASK = keccak256("rewards_update");
    bytes32 public constant STAKE_VALIDATION_TASK = keccak256("stake_validation");

    /// @notice Fee structure for different task types (in wei)
    uint96 public constant ORDER_MATCHING_FEE = 0.001 ether;
    uint96 public constant PRIVACY_EXECUTION_FEE = 0.005 ether;
    uint96 public constant REWARDS_UPDATE_FEE = 0.002 ether;
    uint96 public constant STAKE_VALIDATION_FEE = 0.001 ether;
    uint96 public constant DEFAULT_TASK_FEE = 0.001 ether;

    /// @notice Address of the L1 EigenVault task registrar
    address public eigenVaultTaskRegistrar;
    
    /// @notice Address of the main EigenVault Hook contract
    address public eigenVaultHook;
    
    /// @notice Mapping of task hashes to their completion status
    mapping(bytes32 => bool) public taskCompleted;
    
    /// @notice Mapping of task hashes to their creation timestamps
    mapping(bytes32 => uint256) public taskCreationTime;
    
    /// @notice Maximum task execution time (1 hour)
    uint256 public constant MAX_TASK_EXECUTION_TIME = 1 hours;

    /// @notice Event emitted when a task is validated and created
    event TaskValidated(bytes32 indexed taskHash, bytes32 taskType, address indexed caller);
    
    /// @notice Event emitted when a task result is submitted
    event TaskResultSubmitted(bytes32 indexed taskHash, address indexed submitter);
    
    /// @notice Event emitted when the EigenVault hook address is updated
    event EigenVaultHookUpdated(address indexed oldHook, address indexed newHook);

    /// @notice Modifier to check if caller is authorized
    modifier onlyAuthorized() {
        require(
            msg.sender == eigenVaultTaskRegistrar || 
            msg.sender == eigenVaultHook,
            "Unauthorized caller"
        );
        _;
    }

    /**
     * @notice Set the address of the EigenVault hook contract
     * @param _eigenVaultHook The address of the main EigenVault hook contract
     */
    function setEigenVaultHook(address _eigenVaultHook) external {
        require(_eigenVaultHook != address(0), "Invalid hook address");
        // Note: In production, this should have proper access control
        
        address oldHook = eigenVaultHook;
        eigenVaultHook = _eigenVaultHook;
        
        emit EigenVaultHookUpdated(oldHook, _eigenVaultHook);
    }

    /**
     * @notice Set the address of the EigenVault task registrar
     * @param _eigenVaultTaskRegistrar The address of the L1 task registrar
     */
    function setEigenVaultTaskRegistrar(address _eigenVaultTaskRegistrar) external {
        require(_eigenVaultTaskRegistrar != address(0), "Invalid registrar address");
        // Note: In production, this should have proper access control
        
        eigenVaultTaskRegistrar = _eigenVaultTaskRegistrar;
    }

    /**
     * @notice Validate task parameters before task creation
     * @param caller The address calling task creation
     * @param taskParams The parameters of the task being created
     */
    function validatePreTaskCreation(
        address caller,
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override {
        require(caller != address(0), "Invalid caller");
        require(taskParams.performerAddress != address(0), "Invalid performer address");
        
        // Parse task type from the payload
        bytes32 taskType = _parseTaskType(taskParams.payload);
        require(_isValidTaskType(taskType), "Invalid task type");
        
        // Validate task-specific parameters
        if (taskType == ORDER_MATCHING_TASK) {
            _validateOrderMatchingTask(taskParams.payload);
        } else if (taskType == PRIVACY_EXECUTION_TASK) {
            _validatePrivacyExecutionTask(taskParams.payload);
        } else if (taskType == REWARDS_UPDATE_TASK) {
            _validateRewardsUpdateTask(taskParams.payload);
        } else if (taskType == STAKE_VALIDATION_TASK) {
            _validateStakeValidationTask(taskParams.payload);
        }
    }

    /**
     * @notice Handle post-task creation logic
     * @param taskHash The hash of the created task
     */
    function handlePostTaskCreation(bytes32 taskHash) external override {
        require(taskHash != bytes32(0), "Invalid task hash");
        
        // Record task creation time
        taskCreationTime[taskHash] = block.timestamp;
        
        // Get task type for event emission
        // Note: In a full implementation, we'd store the task type during creation
        emit TaskValidated(taskHash, bytes32(0), msg.sender);
    }

    /**
     * @notice Validate task result before submission
     * @param caller The address submitting the result
     * @param taskHash The hash of the task
     * @param cert The certificate proving task execution
     * @param result The task execution result
     */
    function validatePreTaskResultSubmission(
        address caller,
        bytes32 taskHash,
        bytes memory cert,
        bytes memory result
    ) external view override {
        require(caller != address(0), "Invalid caller");
        require(taskHash != bytes32(0), "Invalid task hash");
        require(cert.length > 0, "Empty certificate");
        require(result.length > 0, "Empty result");
        require(!taskCompleted[taskHash], "Task already completed");
        
        // Check task hasn't expired
        uint256 creationTime = taskCreationTime[taskHash];
        require(creationTime > 0, "Task not found");
        require(
            block.timestamp <= creationTime + MAX_TASK_EXECUTION_TIME,
            "Task execution time expired"
        );
        
        // Additional validation can be added here for certificate verification
    }

    /**
     * @notice Handle post-task result submission
     * @param caller The address that submitted the result
     * @param taskHash The hash of the completed task
     */
    function handlePostTaskResultSubmission(
        address caller,
        bytes32 taskHash
    ) external override {
        require(taskHash != bytes32(0), "Invalid task hash");
        require(!taskCompleted[taskHash], "Task already completed");
        
        // Mark task as completed
        taskCompleted[taskHash] = true;
        
        emit TaskResultSubmitted(taskHash, caller);
        
        // Additional post-completion logic can be added here
        // For example, updating operator performance scores
    }

    /**
     * @notice Calculate the fee for a given task
     * @param taskParams The parameters of the task
     * @return The fee amount in wei
     */
    function calculateTaskFee(
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external view override returns (uint96) {
        bytes32 taskType = _parseTaskType(taskParams.payload);
        
        if (taskType == ORDER_MATCHING_TASK) {
            return ORDER_MATCHING_FEE;
        } else if (taskType == PRIVACY_EXECUTION_TASK) {
            return PRIVACY_EXECUTION_FEE;
        } else if (taskType == REWARDS_UPDATE_TASK) {
            return REWARDS_UPDATE_FEE;
        } else if (taskType == STAKE_VALIDATION_TASK) {
            return STAKE_VALIDATION_FEE;
        }
        
        return DEFAULT_TASK_FEE;
    }

    /**
     * @notice Parse task type from payload
     * @param payload The task payload
     * @return The parsed task type
     */
    function _parseTaskType(bytes memory payload) internal pure returns (bytes32) {
        // Simple implementation - in practice, this would parse JSON or structured data
        // For now, we'll assume the first 32 bytes contain the task type hash
        if (payload.length < 32) {
            return bytes32(0);
        }
        
        bytes32 taskType;
        assembly {
            taskType := mload(add(payload, 32))
        }
        return taskType;
    }

    /**
     * @notice Check if a task type is valid
     * @param taskType The task type to validate
     * @return Whether the task type is valid
     */
    function _isValidTaskType(bytes32 taskType) internal pure returns (bool) {
        return taskType == ORDER_MATCHING_TASK ||
               taskType == PRIVACY_EXECUTION_TASK ||
               taskType == REWARDS_UPDATE_TASK ||
               taskType == STAKE_VALIDATION_TASK;
    }

    /**
     * @notice Validate order matching task parameters
     * @param payload The task payload
     */
    function _validateOrderMatchingTask(bytes memory payload) internal pure {
        require(payload.length >= 64, "Invalid order matching payload");
        // Additional validation logic for order matching tasks
    }

    /**
     * @notice Validate privacy execution task parameters
     * @param payload The task payload
     */
    function _validatePrivacyExecutionTask(bytes memory payload) internal pure {
        require(payload.length >= 64, "Invalid privacy execution payload");
        // Additional validation logic for privacy execution tasks
    }

    /**
     * @notice Validate rewards update task parameters
     * @param payload The task payload
     */
    function _validateRewardsUpdateTask(bytes memory payload) internal pure {
        require(payload.length >= 32, "Invalid rewards update payload");
        // Additional validation logic for rewards update tasks
    }

    /**
     * @notice Validate stake validation task parameters
     * @param payload The task payload
     */
    function _validateStakeValidationTask(bytes memory payload) internal pure {
        require(payload.length >= 32, "Invalid stake validation payload");
        // Additional validation logic for stake validation tasks
    }

    /**
     * @notice Get task completion status
     * @param taskHash The task hash to check
     * @return Whether the task is completed
     */
    function isTaskCompleted(bytes32 taskHash) external view returns (bool) {
        return taskCompleted[taskHash];
    }

    /**
     * @notice Get task creation time
     * @param taskHash The task hash to check
     * @return The timestamp when the task was created
     */
    function getTaskCreationTime(bytes32 taskHash) external view returns (uint256) {
        return taskCreationTime[taskHash];
    }
}