// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IEigenVaultHook} from "./interfaces/IEigenVaultHook.sol";
import {IOrderVault} from "./interfaces/IOrderVault.sol";
import {IEigenVaultServiceManager} from "./interfaces/IEigenVaultServiceManager.sol";
import {OrderLib} from "./libraries/OrderLib.sol";
import {ZKProofLib} from "./libraries/ZKProofLib.sol";

/// @title EigenVaultServiceManager
/// @notice Simplified service manager for order matching without full EigenLayer integration
/// @dev Manages operators and tasks for privacy-preserving order matching
contract EigenVaultServiceManager is IEigenVaultServiceManager {
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
        address assignedOperator;
        bool verified;
    }

    /// @notice Simplified operator info
    struct OperatorInfo {
        bool isRegistered;
        uint256 stake;
        bool isSlashed;
        uint256 tasksCompleted;
        uint256 registrationTime;
    }

    /// @notice Hook contract reference
    IEigenVaultHook public immutable eigenVaultHook;
    
    /// @notice Order vault reference
    IOrderVault public immutable orderVault;
    
    /// @notice Task counter
    uint256 public taskCounter;
    
    /// @notice Minimum stake required for operators
    uint256 public minimumStake = 1 ether;

    /// @notice Mapping of task IDs to tasks
    mapping(bytes32 => MatchingTask) public tasks;
    
    /// @notice Mapping of operators to their info
    mapping(address => OperatorInfo) public operators;
    
    /// @notice Active operators list
    address[] public activeOperators;

    /// @notice Contract owner
    address public owner;

    /// @notice Events
    event TaskCreated(bytes32 indexed taskId, bytes32 indexed ordersSetHash, uint256 deadline, address assignedOperator);
    event TaskCompleted(bytes32 indexed taskId, bytes32 resultHash, address operator);
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);

    /// @notice Modifiers
    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isRegistered, "Operator not registered");
        require(!operators[msg.sender].isSlashed, "Operator slashed");
        _;
    }

    modifier onlyEigenVaultHook() {
        require(msg.sender == address(eigenVaultHook), "Only EigenVault hook");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /// @notice Constructor
    /// @param _eigenVaultHook The EigenVault hook contract
    /// @param _orderVault The order vault contract
    constructor(
        IEigenVaultHook _eigenVaultHook,
        IOrderVault _orderVault
    ) {
        eigenVaultHook = _eigenVaultHook;
        orderVault = _orderVault;
        owner = msg.sender;
    }

    /// @notice Register operator with stake
    function registerOperator() external payable override {
        require(msg.value >= minimumStake, "Insufficient stake");
        require(!operators[msg.sender].isRegistered, "Already registered");

        operators[msg.sender] = OperatorInfo({
            isRegistered: true,
            stake: msg.value,
            isSlashed: false,
            tasksCompleted: 0,
            registrationTime: block.timestamp
        });

        activeOperators.push(msg.sender);
        emit OperatorRegistered(msg.sender, msg.value);
    }

    /// @notice Create a task for order matching
    function createTask(
        bytes32 ordersSetHash,
        uint256 deadline
    ) external override returns (bytes32) {
        require(deadline > block.timestamp, "Invalid deadline");
        require(activeOperators.length > 0, "No registered operators");

        bytes32 taskId = keccak256(abi.encodePacked(taskCounter++, block.timestamp, ordersSetHash));
        
        // Simple assignment to first available operator
        address assignedOperator = activeOperators[taskCounter % activeOperators.length];
        
        tasks[taskId] = MatchingTask({
            taskId: taskId,
            ordersSetHash: ordersSetHash,
            deadline: deadline,
            status: TaskStatus.Pending,
            resultHash: bytes32(0),
            createdAt: block.timestamp,
            completedAt: 0,
            assignedOperator: assignedOperator,
            verified: false
        });

        emit TaskCreated(taskId, ordersSetHash, deadline, assignedOperator);
        return taskId;
    }

    /// @notice Submit task response
    function submitTaskResponse(
        bytes32 taskId,
        bytes calldata response,
        bytes32 resultHash
    ) external override onlyRegisteredOperator {
        MatchingTask storage task = tasks[taskId];
        require(task.taskId != bytes32(0), "Task not found");
        require(task.status == TaskStatus.Pending, "Task not pending");
        require(block.timestamp <= task.deadline, "Task deadline passed");
        require(task.assignedOperator == msg.sender, "Not assigned to this task");

        task.resultHash = resultHash;
        task.status = TaskStatus.Completed;
        task.completedAt = block.timestamp;
        task.verified = true;

        operators[msg.sender].tasksCompleted++;

        emit TaskCompleted(taskId, resultHash, msg.sender);
    }

    /// @notice Get task details
    function getTask(bytes32 taskId) external view override returns (
        bytes32 ordersSetHash,
        uint256 deadline,
        bool completed,
        address assignedOperator,
        bytes32 resultHash
    ) {
        MatchingTask storage task = tasks[taskId];
        return (
            task.ordersSetHash,
            task.deadline,
            task.status == TaskStatus.Completed,
            task.assignedOperator,
            task.resultHash
        );
    }

    /// @notice Get operator information
    function getOperatorInfo(address operator) external view override returns (
        bool isRegistered,
        uint256 stake,
        bool isSlashed
    ) {
        OperatorInfo storage info = operators[operator];
        return (info.isRegistered, info.stake, info.isSlashed);
    }

    /// @notice Slash operator for misbehavior
    function slashOperator(address operator, uint256 amount) external override onlyOwner {
        require(operators[operator].isRegistered, "Operator not registered");
        require(operators[operator].stake >= amount, "Insufficient stake to slash");
        
        operators[operator].stake -= amount;
        operators[operator].isSlashed = true;
        
        emit OperatorSlashed(operator, amount, "Misbehavior detected");
    }

    /// @notice Get all active operators
    function getActiveOperators() external view returns (address[] memory) {
        return activeOperators;
    }
}