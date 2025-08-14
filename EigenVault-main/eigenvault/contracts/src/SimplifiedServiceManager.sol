// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IEigenVaultHook} from "./interfaces/IEigenVaultHook.sol";
import {OrderLib} from "./libraries/OrderLib.sol";

/// @title SimplifiedServiceManager
/// @notice A simplified service manager for EigenVault demonstration
contract SimplifiedServiceManager {
    using OrderLib for OrderLib.Order;

    /// @notice Task states
    enum TaskStatus {
        Pending,
        Completed,
        Challenged,
        Slashed
    }

    /// @notice Matching task structure
    struct MatchingTask {
        bytes32 taskId;
        bytes32 ordersSetHash;
        uint256 deadline;
        TaskStatus status;
        bytes32 resultHash;
        uint256 createdAt;
        uint256 completedAt;
        address[] assignedOperators;
    }

    /// @notice Operator metrics
    struct OperatorMetrics {
        uint256 tasksCompleted;
        uint256 totalRewards;
        uint256 lastActiveTime;
        bool isActive;
    }

    /// @notice Hook contract reference
    IEigenVaultHook public immutable eigenVaultHook;
    
    /// @notice Task counter
    uint256 public taskCounter;
    
    /// @notice Base reward per task
    uint256 public constant BASE_TASK_REWARD = 0.01 ether;

    /// @notice Mapping of task IDs to tasks
    mapping(bytes32 => MatchingTask) public tasks;
    
    /// @notice Mapping of operators to their metrics
    mapping(address => OperatorMetrics) public operatorMetrics;
    
    /// @notice Mapping of registered operators
    mapping(address => bool) public registeredOperators;
    
    /// @notice Active operators list
    address[] public activeOperators;
    
    /// @notice Owner of the contract
    address public owner;

    /// @notice Events
    event TaskCreated(
        bytes32 indexed taskId,
        bytes32 indexed ordersSetHash,
        uint256 deadline,
        address[] assignedOperators
    );
    
    event TaskCompleted(
        bytes32 indexed taskId,
        bytes32 resultHash,
        address[] respondingOperators,
        uint256 completedAt
    );
    
    event OperatorRegistered(address indexed operator);
    
    event RewardsDistributed(
        bytes32 indexed taskId,
        address[] operators,
        uint256[] rewards
    );

    /// @notice Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyRegisteredOperator() {
        require(registeredOperators[msg.sender], "Operator not registered");
        _;
    }

    /// @notice Constructor
    /// @param _eigenVaultHook The EigenVault hook contract
    constructor(IEigenVaultHook _eigenVaultHook) {
        eigenVaultHook = _eigenVaultHook;
        owner = msg.sender;
    }

    /// @notice Create a new matching task
    /// @param ordersSetHash Hash of the orders to be matched
    /// @param deadline Task completion deadline
    /// @return taskId The created task ID
    function createMatchingTask(
        bytes32 ordersSetHash,
        uint256 deadline
    ) external returns (bytes32 taskId) {
        require(deadline > block.timestamp + 10 minutes, "Invalid deadline");
        
        taskId = keccak256(abi.encodePacked(
            "MATCHING_TASK",
            ++taskCounter,
            ordersSetHash,
            block.timestamp
        ));
        
        // Select operators for this task (simplified)
        address[] memory assignedOperators = new address[](activeOperators.length);
        for (uint256 i = 0; i < activeOperators.length; i++) {
            assignedOperators[i] = activeOperators[i];
        }
        
        // Create task
        tasks[taskId] = MatchingTask({
            taskId: taskId,
            ordersSetHash: ordersSetHash,
            deadline: deadline,
            status: TaskStatus.Pending,
            resultHash: bytes32(0),
            createdAt: block.timestamp,
            completedAt: 0,
            assignedOperators: assignedOperators
        });
        
        emit TaskCreated(taskId, ordersSetHash, deadline, assignedOperators);
        
        return taskId;
    }

    /// @notice Submit a matching task response
    /// @param taskId The task identifier
    /// @param resultHash Hash of the matching result
    /// @param zkProof Zero-knowledge proof of valid matching
    /// @param operatorSignatures Signatures from participating operators
    function submitTaskResponse(
        bytes32 taskId,
        bytes32 resultHash,
        bytes calldata zkProof,
        bytes calldata operatorSignatures
    ) external onlyRegisteredOperator {
        MatchingTask storage task = tasks[taskId];
        require(task.taskId != bytes32(0), "Task not found");
        require(task.status == TaskStatus.Pending, "Task not pending");
        require(block.timestamp <= task.deadline, "Task deadline passed");
        
        // Update task
        task.status = TaskStatus.Completed;
        task.resultHash = resultHash;
        task.completedAt = block.timestamp;
        
        // Update operator metrics
        operatorMetrics[msg.sender].tasksCompleted++;
        operatorMetrics[msg.sender].lastActiveTime = block.timestamp;
        
        // Execute matched orders via hook
        eigenVaultHook.executeVaultOrder(taskId, zkProof, operatorSignatures);
        
        // Create responding operators array (simplified)
        address[] memory respondingOperators = new address[](1);
        respondingOperators[0] = msg.sender;
        
        // Distribute rewards
        _distributeRewards(taskId, respondingOperators);
        
        emit TaskCompleted(taskId, resultHash, respondingOperators, block.timestamp);
    }

    /// @notice Register operator
    function registerOperator() external {
        require(!registeredOperators[msg.sender], "Already registered");
        
        registeredOperators[msg.sender] = true;
        
        // Initialize operator metrics
        operatorMetrics[msg.sender] = OperatorMetrics({
            tasksCompleted: 0,
            totalRewards: 0,
            lastActiveTime: block.timestamp,
            isActive: true
        });
        
        activeOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender);
    }

    /// @notice Deregister operator
    function deregisterOperator() external onlyRegisteredOperator {
        registeredOperators[msg.sender] = false;
        operatorMetrics[msg.sender].isActive = false;
        
        // Remove from active operators list
        for (uint256 i = 0; i < activeOperators.length; i++) {
            if (activeOperators[i] == msg.sender) {
                activeOperators[i] = activeOperators[activeOperators.length - 1];
                activeOperators.pop();
                break;
            }
        }
    }

    /// @notice Get task details
    /// @param taskId The task identifier
    /// @return task The task details
    function getTask(bytes32 taskId) external view returns (MatchingTask memory task) {
        return tasks[taskId];
    }

    /// @notice Get operator metrics
    /// @param operator The operator address
    /// @return metrics The operator metrics
    function getOperatorMetrics(address operator) external view returns (OperatorMetrics memory metrics) {
        return operatorMetrics[operator];
    }

    /// @notice Get active operators count
    /// @return count The number of active operators
    function getActiveOperatorsCount() external view returns (uint256 count) {
        return activeOperators.length;
    }

    /// @notice Internal function to distribute rewards
    /// @param taskId The task identifier
    /// @param operators The operators to reward
    function _distributeRewards(bytes32 taskId, address[] memory operators) internal {
        uint256 totalReward = BASE_TASK_REWARD;
        uint256 rewardPerOperator = totalReward / operators.length;
        uint256[] memory rewards = new uint256[](operators.length);
        
        for (uint256 i = 0; i < operators.length; i++) {
            rewards[i] = rewardPerOperator;
            operatorMetrics[operators[i]].totalRewards += rewardPerOperator;
            
            // In production, this would actually transfer rewards
        }
        
        emit RewardsDistributed(taskId, operators, rewards);
    }

    /// @notice Transfer ownership
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}