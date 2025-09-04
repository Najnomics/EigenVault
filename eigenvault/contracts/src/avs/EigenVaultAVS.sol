// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEigenVaultAVS} from "./IEigenVaultAVS.sol";

/// @title EigenVaultAVS
/// @notice Enhanced AVS contract for EigenVault with slashing and operator management
/// @dev Integrates with Go AVS implementation with proper slashing mechanisms
contract EigenVaultAVS is IEigenVaultAVS, Ownable, Pausable, ReentrancyGuard {
    /// @notice Minimum stake required for operators
    uint256 public constant MIN_OPERATOR_STAKE = 32 ether;
    
    /// @notice Maximum slash percentage (100%)
    uint256 public constant MAX_SLASH_PERCENTAGE = 10000; // 100% in basis points
    
    /// @notice Task response window
    uint256 public constant TASK_RESPONSE_WINDOW = 1 hours;
    
    /// @notice Task counter for unique task IDs
    uint32 public taskCounter;
    
    /// @notice Next task index for new tasks
    uint32 public nextTaskIndex;
    
    /// @notice Total number of registered operators
    uint256 public totalOperators;
    
    /// @notice Total number of tasks
    uint256 public totalTasks;
    
    /// @notice Operator information
    struct OperatorInfo {
        uint256 stake;
        string metadataURL;
        uint256 registrationTime;
        uint256 totalRewards;
        uint256 totalSlashed;
        uint256 slashCount;
        bool isRegistered;
    }
    
    /// @notice Task information
    struct TaskInfo {
        bytes32 orderId;
        bytes taskData;
        uint256 deadline;
        bool isCompleted;
        address assignedOperator;
        bytes32 result;
    }
    
    /// @notice Slashing event information
    struct SlashingEvent {
        address operator;
        uint256 amount;
        string reason;
        uint256 timestamp;
        address slasher;
    }
    
    /// @notice Mapping of operators to their info
    mapping(address => OperatorInfo) public operators;
    
    /// @notice Array of registered operators
    address[] public registeredOperators;
    
    /// @notice Mapping of task IDs to task data
    mapping(uint32 => TaskInfo) public tasks;
    
    /// @notice Mapping of order IDs to task IDs
    mapping(bytes32 => uint32) public orderToTask;
    
    /// @notice Mapping of task responses by operator
    mapping(uint32 => mapping(address => bytes)) public taskResponses;
    
    /// @notice Mapping to track if operator responded to task
    mapping(uint32 => mapping(address => bool)) public operatorResponded;
    
    /// @notice Authorized hook contracts
    mapping(address => bool) public authorizedHooks;
    
    /// @notice Slashing events log
    SlashingEvent[] public slashingEvents;

    /// @notice Events
    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed orderId, bytes taskData, uint256 deadline);
    event ProofSubmitted(uint32 indexed taskIndex, bytes proof, bytes signatures);
    event HookAuthorized(address indexed hook, bool authorized);
    event OperatorRegistered(address indexed operator, string metadataURL);
    event OperatorDeregistered(address indexed operator);
    event TaskResponseSubmitted(uint32 indexed taskIndex, address indexed operator);
    event TaskCompleted(uint32 indexed taskIndex, address indexed operator, bytes response);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event RewardDistributed(address indexed operator, uint256 amount);
    event EmergencyPauseActivated();
    event EmergencyPauseDeactivated();

    /// @notice Modifiers
    modifier onlyAuthorizedHook() {
        require(authorizedHooks[msg.sender], "Unauthorized hook");
        _;
    }

    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isRegistered, "Not registered operator");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                         OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Register as an operator with stake
    /// @param metadataURL The operator's metadata URL
    function registerOperator(string calldata metadataURL) external payable whenNotPaused nonReentrant {
        require(msg.value >= MIN_OPERATOR_STAKE, "Insufficient stake");
        require(!operators[msg.sender].isRegistered, "Already registered");
        require(bytes(metadataURL).length > 0, "Empty metadata URL");

        operators[msg.sender] = OperatorInfo({
            stake: msg.value,
            metadataURL: metadataURL,
            registrationTime: block.timestamp,
            totalRewards: 0,
            totalSlashed: 0,
            slashCount: 0,
            isRegistered: true
        });

        registeredOperators.push(msg.sender);
        totalOperators++;

        emit OperatorRegistered(msg.sender, metadataURL);
    }

    /// @notice Deregister as an operator and withdraw stake
    function deregisterOperator() external nonReentrant {
        require(operators[msg.sender].isRegistered, "Not registered");
        require(!_hasPendingTasks(msg.sender), "Has pending tasks");

        uint256 stakeToReturn = operators[msg.sender].stake;
        operators[msg.sender].isRegistered = false;
        operators[msg.sender].stake = 0;
        
        // Remove from array
        _removeOperatorFromArray(msg.sender);
        totalOperators--;

        // Return stake
        (bool success,) = msg.sender.call{value: stakeToReturn}("");
        require(success, "Stake transfer failed");

        emit OperatorDeregistered(msg.sender);
    }

    /// @notice Add additional stake
    function addStake() external payable nonReentrant {
        require(operators[msg.sender].isRegistered, "Not registered");
        require(msg.value > 0, "Invalid stake amount");

        operators[msg.sender].stake += msg.value;
    }

    /// @notice Withdraw part of the stake (above minimum)
    /// @param amount The amount to withdraw
    function withdrawStake(uint256 amount) external nonReentrant {
        require(operators[msg.sender].isRegistered, "Not registered");
        require(amount > 0, "Invalid amount");
        require(operators[msg.sender].stake >= amount, "Insufficient stake");
        require(operators[msg.sender].stake - amount >= MIN_OPERATOR_STAKE, "Would go below minimum stake");

        operators[msg.sender].stake -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    /*//////////////////////////////////////////////////////////////
                           TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new task (public interface)
    /// @param taskId The task identifier
    /// @param data The task data
    /// @param deadline The task deadline
    /// @return taskIndex The created task index
    function createTask(bytes32 taskId, bytes calldata data, uint256 deadline) external onlyOwner whenNotPaused returns (uint32 taskIndex) {
        require(taskId != bytes32(0), "Invalid task ID");
        require(data.length > 0, "Empty task data");
        require(deadline > block.timestamp, "Invalid deadline");

        taskIndex = ++taskCounter;
        totalTasks++;

        tasks[taskIndex] = TaskInfo({
            orderId: taskId,
            taskData: data,
            deadline: deadline,
            isCompleted: false,
            assignedOperator: address(0),
            result: bytes32(0)
        });

        emit TaskCreated(taskIndex, taskId, data, deadline);
        return taskIndex;
    }

    /// @notice Submit a task response (public interface)
    /// @param taskIndex The task index
    /// @param response The response data
    function submitTaskResponse(uint32 taskIndex, bytes calldata response) external onlyRegisteredOperator whenNotPaused {
        require(taskIndex <= taskCounter && taskIndex > 0, "Task not found");
        require(!tasks[taskIndex].isCompleted, "Task already completed");
        require(block.timestamp <= tasks[taskIndex].deadline, "Task deadline passed");
        require(response.length > 0, "Empty response");

        tasks[taskIndex].isCompleted = true;
        tasks[taskIndex].assignedOperator = msg.sender;
        tasks[taskIndex].result = keccak256(response);

        emit TaskResponseSubmitted(taskIndex, msg.sender);
        emit TaskCompleted(taskIndex, msg.sender, response);
    }

    /// @notice Complete a task (public interface)
    /// @param taskIndex The task index
    /// @param result The task result
    function completeTask(uint32 taskIndex, bytes32 result) external onlyOwner {
        require(taskIndex <= taskCounter && taskIndex > 0, "Task not found");
        require(!tasks[taskIndex].isCompleted, "Already completed");

        tasks[taskIndex].isCompleted = true;
        tasks[taskIndex].result = result;

        emit TaskCompleted(taskIndex, tasks[taskIndex].assignedOperator, abi.encode(result));
    }


    /*//////////////////////////////////////////////////////////////
                         SLASHING MECHANISMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Slash an operator for malicious behavior
    /// @param operator The operator to slash
    /// @param amount The amount to slash
    /// @param reason The reason for slashing
    function slashOperator(address operator, uint256 amount, string calldata reason) external onlyOwner nonReentrant {
        require(operators[operator].isRegistered, "Operator not registered");
        require(amount > 0, "Invalid slash amount");
        require(operators[operator].stake >= amount, "Insufficient stake to slash");
        require(bytes(reason).length > 0, "Empty slashing reason");

        operators[operator].stake -= amount;
        operators[operator].totalSlashed += amount;
        operators[operator].slashCount++;

        // Record slashing event
        slashingEvents.push(SlashingEvent({
            operator: operator,
            amount: amount,
            reason: reason,
            timestamp: block.timestamp,
            slasher: msg.sender
        }));

        // If operator has no stake left, deregister them
        if (operators[operator].stake == 0) {
            operators[operator].isRegistered = false;
            _removeOperatorFromArray(operator);
            totalOperators--;
        }

        emit OperatorSlashed(operator, amount, reason);
    }

    /// @notice Distribute rewards to an operator
    /// @param operator The operator to reward
    /// @param amount The reward amount
    function distributeReward(address operator, uint256 amount) external onlyOwner nonReentrant {
        require(operators[operator].isRegistered, "Operator not registered");
        require(amount > 0, "Invalid reward amount");
        require(address(this).balance >= amount, "Insufficient contract balance");

        operators[operator].totalRewards += amount;

        (bool success,) = operator.call{value: amount}("");
        require(success, "Reward transfer failed");

        emit RewardDistributed(operator, amount);
    }

    /// @notice Internal function to create a new task
    /// @param orderId The order ID
    /// @param taskData The encoded task data
    /// @param deadline The task deadline
    /// @return taskIndex The created task index
    function _createTask(
        bytes32 orderId,
        bytes memory taskData,
        uint256 deadline
    ) internal returns (uint32 taskIndex) {
        taskIndex = nextTaskIndex++;
        
        tasks[taskIndex] = TaskInfo({
            orderId: orderId,
            taskData: taskData,
            deadline: deadline,
            isCompleted: false,
            assignedOperator: address(0),
            result: bytes32(0)
        });

        emit TaskCreated(taskIndex, orderId, taskData, deadline);
        return taskIndex;
    }

    /// @notice Internal function to submit task response
    /// @param taskIndex The task index
    /// @param response The encoded response data
    function _submitTaskResponse(uint32 taskIndex, bytes memory response) internal {
        require(tasks[taskIndex].orderId != bytes32(0), "Task does not exist");
        require(!tasks[taskIndex].isCompleted, "Task already completed");
        require(block.timestamp <= tasks[taskIndex].deadline, "Task deadline passed");

        tasks[taskIndex].isCompleted = true;
        tasks[taskIndex].assignedOperator = msg.sender;
        tasks[taskIndex].result = keccak256(response);

        emit TaskCompleted(taskIndex, msg.sender, response);
    }

    /*//////////////////////////////////////////////////////////////
                         EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency pause
    function emergencyPause() external onlyOwner {
        require(!paused(), "Already paused");
        _pause();
        emit EmergencyPauseActivated();
    }

    /// @notice Emergency unpause
    function emergencyUnpause() external onlyOwner {
        require(paused(), "Not paused");
        _unpause();
        emit EmergencyPauseDeactivated();
    }

    /*//////////////////////////////////////////////////////////////
                         EIGENVAULT AVS INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a matching task for Go AVS operators
    /// @param orderId The order identifier
    /// @param poolId The pool identifier
    /// @param commitment The order commitment hash
    /// @return taskIndex The task index for tracking
    function createMatchingTask(
        bytes32 orderId,
        bytes32 poolId,
        bytes32 commitment
    ) external override onlyAuthorizedHook whenNotPaused returns (uint32 taskIndex) {
        taskIndex = _createTask(
            orderId,
            abi.encode(poolId, commitment),
            block.timestamp + TASK_RESPONSE_WINDOW
        );
        orderToTask[orderId] = taskIndex;
        return taskIndex;
    }

    /// @notice Submit proof of order matching (called by Go operators)
    /// @param taskIndex The task index
    /// @param proof The ZK proof of matching
    /// @param signatures The operator signatures
    function submitMatchingProof(
        uint32 taskIndex,
        bytes calldata proof,
        bytes calldata signatures
    ) external override onlyRegisteredOperator whenNotPaused {
        _submitTaskResponse(taskIndex, abi.encode(proof, signatures));
        emit ProofSubmitted(taskIndex, proof, signatures);
    }

    /// @notice Get assigned operators
    /// @param poolId The pool ID (unused in this implementation)
    /// @return operatorList Array of registered operators
    function getAssignedOperators(bytes32 poolId) external view override returns (address[] memory operatorList) {
        return registeredOperators;
    }

    /// @notice Request consensus
    /// @param taskId The consensus task ID
    /// @param consensusHash The hash to reach consensus on
    function requestConsensus(bytes32 taskId, bytes32 consensusHash) external override onlyAuthorizedHook whenNotPaused {
        _createTask(taskId, abi.encode(consensusHash), block.timestamp + TASK_RESPONSE_WINDOW);
    }

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize hook contract
    /// @param hook The hook address
    /// @param authorized Whether to authorize
    function authorizeHook(address hook, bool authorized) external onlyOwner {
        require(hook != address(0), "Invalid hook address");
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if an operator is registered
    /// @param operator The operator address
    /// @return isRegistered Whether the operator is registered
    function isRegisteredOperator(address operator) external view returns (bool isRegistered) {
        return operators[operator].isRegistered;
    }

    /// @notice Get operator stake
    /// @param operator The operator address
    /// @return stake The operator's stake
    function getOperatorStake(address operator) external view returns (uint256 stake) {
        return operators[operator].stake;
    }

    /// @notice Get operator metadata URL
    /// @param operator The operator address
    /// @return metadataURL The operator's metadata URL
    function getOperatorMetadataURL(address operator) external view returns (string memory metadataURL) {
        return operators[operator].metadataURL;
    }

    /// @notice Get total rewards for an operator
    /// @param operator The operator address
    /// @return totalRewards The total rewards received
    function getTotalRewards(address operator) external view returns (uint256 totalRewards) {
        return operators[operator].totalRewards;
    }

    /// @notice Get slashing information for an operator
    /// @param operator The operator address
    /// @return totalSlashed The total amount slashed
    /// @return slashCount The number of slashing events
    function getSlashingInfo(address operator) external view returns (uint256 totalSlashed, uint256 slashCount) {
        return (operators[operator].totalSlashed, operators[operator].slashCount);
    }

    /// @notice Get registered operators
    /// @return operatorList Array of registered operator addresses
    function getRegisteredOperators() external view returns (address[] memory operatorList) {
        return registeredOperators;
    }

    /// @notice Get active tasks
    /// @return taskIndexes Array of active task indexes
    function getActiveTasks() external view returns (uint32[] memory taskIndexes) {
        uint32 activeCount = 0;
        for (uint32 i = 1; i <= taskCounter; i++) {
            if (!tasks[i].isCompleted) {
                activeCount++;
            }
        }

        taskIndexes = new uint32[](activeCount);
        uint32 index = 0;
        for (uint32 i = 1; i <= taskCounter; i++) {
            if (!tasks[i].isCompleted) {
                taskIndexes[index] = i;
                index++;
            }
        }
        return taskIndexes;
    }

    /// @notice Get task information
    /// @param taskIndex The task index
    /// @return orderId The order ID
    /// @return taskData The task data
    /// @return deadline The task deadline
    /// @return isCompleted Whether the task is completed
    function getTask(uint32 taskIndex) external view returns (bytes32 orderId, bytes memory taskData, uint256 deadline, bool isCompleted) {
        TaskInfo memory task = tasks[taskIndex];
        return (task.orderId, task.taskData, task.deadline, task.isCompleted);
    }

    /// @notice Get task result
    /// @param taskIndex The task index
    /// @return result The task result
    function getTaskResult(uint32 taskIndex) external view returns (bytes32 result) {
        return tasks[taskIndex].result;
    }

    /// @notice Get task response from an operator
    /// @param taskIndex The task index
    /// @param operator The operator address
    /// @return response The operator's response
    function getTaskResponse(uint32 taskIndex, address operator) external view returns (bytes memory response) {
        return taskResponses[taskIndex][operator];
    }

    /// @notice Get task index for order
    /// @param orderId The order ID
    /// @return taskIndex The task index
    function getTaskForOrder(bytes32 orderId) external view returns (uint32 taskIndex) {
        return orderToTask[orderId];
    }

    /// @notice Get operator performance metrics
    /// @param operator The operator address
    /// @return tasksAssigned Number of tasks assigned
    /// @return tasksCompleted Number of tasks completed
    /// @return totalRewards Total rewards received
    /// @return totalSlashed Total amount slashed
    function getOperatorPerformance(address operator) external view returns (
        uint256 tasksAssigned,
        uint256 tasksCompleted,
        uint256 totalRewards,
        uint256 totalSlashed
    ) {
        // Simple implementation - in production this would be more sophisticated
        tasksAssigned = 0;
        tasksCompleted = 0;
        
        for (uint32 i = 1; i <= taskCounter; i++) {
            if (operatorResponded[i][operator]) {
                tasksAssigned++;
                if (tasks[i].isCompleted) {
                    tasksCompleted++;
                }
            }
        }

        return (tasksAssigned, tasksCompleted, operators[operator].totalRewards, operators[operator].totalSlashed);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if operator has pending tasks
    /// @param operator The operator address
    /// @return hasPending Whether the operator has pending tasks
    function _hasPendingTasks(address operator) internal view returns (bool hasPending) {
        for (uint32 i = 1; i <= taskCounter; i++) {
            if (operatorResponded[i][operator] && !tasks[i].isCompleted) {
                return true;
            }
        }
        return false;
    }

    /// @notice Remove operator from the registered operators array
    /// @param operator The operator to remove
    function _removeOperatorFromArray(address operator) internal {
        for (uint i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
    }

    /// @notice Receive function to accept ETH deposits
    receive() external payable {}
}