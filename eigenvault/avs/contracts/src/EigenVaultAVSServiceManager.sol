// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAVSDirectory} from "./interfaces/IAVSDirectory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title EigenVaultAVSServiceManager
 * @notice Service Manager for EigenVault AVS handling operator registration and order matching tasks
 * @dev This contract manages the EigenLayer AVS for order matching validation and consensus
 */
contract EigenVaultAVSServiceManager is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum stake required for operators (in wei)
    uint256 public constant MINIMUM_STAKE = 32 ether;
    
    /// @notice Task response window (60 seconds)
    uint256 public constant TASK_RESPONSE_WINDOW = 60;
    
    /// @notice Challenge window (7 days)
    uint256 public constant CHALLENGE_WINDOW = 7 days;
    
    /// @notice Minimum operators required for quorum
    uint256 public constant MINIMUM_QUORUM_SIZE = 3;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EigenLayer AVS Directory
    IAVSDirectory public immutable avsDirectory;
    
    /// @notice Current task number
    uint32 public latestTaskNum;
    
    /// @notice Mapping of task number to task hash
    mapping(uint32 => bytes32) public allTaskHashes;
    
    /// @notice Mapping of task number to task response hash
    mapping(uint32 => bytes32) public allTaskResponses;
    
    /// @notice Mapping to track operator registration status
    mapping(address => bool) public operatorRegistered;
    
    /// @notice Array of registered operators
    address[] public registeredOperators;
    
    /// @notice Mapping to check if task has been responded to
    mapping(uint32 => mapping(address => bool)) public operatorResponded;
    
    /// @notice Mapping to track challenge status
    mapping(uint32 => bool) public taskChallenged;
    
    /// @notice Reward pool for operators
    uint256 public rewardPool;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Structure for order matching tasks
    struct OrderMatchingTask {
        bytes32 taskId;
        bytes32 poolId;
        bytes32 ordersHash;
        uint32 taskCreatedBlock;
        uint256 deadline;
        bool completed;
        uint256 minOrderSize;
        uint256 privacyThreshold;
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
    
    /// @notice Mapping of task number to order matching task
    mapping(uint32 => OrderMatchingTask) public orderMatchingTasks;
    
    /// @notice Mapping of task number to operator responses
    mapping(uint32 => mapping(address => TaskResponse)) public taskResponses;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event NewOrderMatchingTaskCreated(uint32 indexed taskIndex, OrderMatchingTask task);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, TaskResponse response);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 matchHash, uint256 executionPrice);
    event TaskChallenged(uint32 indexed taskIndex, address indexed challenger);
    event RewardsDistributed(uint32 indexed taskIndex, uint256 totalReward);
    event StakeSlashed(address indexed operator, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyRegisteredOperator() {
        require(operatorRegistered[msg.sender], "Not a registered operator");
        _;
    }
    
    modifier onlyValidTask(uint32 taskIndex) {
        require(taskIndex <= latestTaskNum, "Invalid task index");
        require(!orderMatchingTasks[taskIndex].completed, "Task already completed");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(IAVSDirectory _avsDirectory) Ownable(msg.sender) {
        avsDirectory = _avsDirectory;
    }

    /*//////////////////////////////////////////////////////////////
                           OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register as an operator in the AVS
     * @param operatorSignature Signature proving operator authorization
     */
    function registerOperator(bytes calldata operatorSignature) external payable nonReentrant {
        require(!operatorRegistered[msg.sender], "Already registered");
        require(msg.value >= MINIMUM_STAKE, "Insufficient stake");
        
        // Register with EigenLayer AVS Directory
        avsDirectory.registerOperatorToAVS(msg.sender, operatorSignature);
        
        // Update local state
        operatorRegistered[msg.sender] = true;
        registeredOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, msg.value);
    }
    
    /**
     * @notice Deregister from the AVS
     */
    function deregisterOperator() external onlyRegisteredOperator nonReentrant {
        // Deregister from EigenLayer
        avsDirectory.deregisterOperatorFromAVS(msg.sender);
        
        // Update local state
        operatorRegistered[msg.sender] = false;
        _removeOperator(msg.sender);
        
        emit OperatorDeregistered(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create a new order matching task
     * @param taskId The task identifier
     * @param poolId The pool identifier
     * @param ordersHash The hash of the orders to be matched
     * @param minOrderSize Minimum order size for this task
     * @param privacyThreshold Privacy threshold for this task
     * @return taskIndex The created task index
     */
    function createOrderMatchingTask(
        bytes32 taskId,
        bytes32 poolId,
        bytes32 ordersHash,
        uint256 minOrderSize,
        uint256 privacyThreshold
    ) external onlyOwner returns (uint32) {
        require(registeredOperators.length >= MINIMUM_QUORUM_SIZE, "Insufficient operators");
        
        uint32 taskIndex = latestTaskNum;
        latestTaskNum++;
        
        // Create task
        OrderMatchingTask memory task = OrderMatchingTask({
            taskId: taskId,
            poolId: poolId,
            ordersHash: ordersHash,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + TASK_RESPONSE_WINDOW,
            completed: false,
            minOrderSize: minOrderSize,
            privacyThreshold: privacyThreshold
        });
        
        orderMatchingTasks[taskIndex] = task;
        allTaskHashes[taskIndex] = keccak256(abi.encode(task));
        
        emit NewOrderMatchingTaskCreated(taskIndex, task);
        
        return taskIndex;
    }
    
    /**
     * @notice Submit task response
     * @param taskIndex The task index
     * @param matchHash The hash of the matching result
     * @param executionPrice The execution price for the match
     * @param signature The operator's signature
     */
    function submitTaskResponse(
        uint32 taskIndex,
        bytes32 matchHash,
        uint256 executionPrice,
        bytes calldata signature
    ) external onlyRegisteredOperator onlyValidTask(taskIndex) {
        OrderMatchingTask storage task = orderMatchingTasks[taskIndex];
        require(block.timestamp <= task.deadline, "Task deadline passed");
        require(!operatorResponded[taskIndex][msg.sender], "Already responded");
        
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(taskIndex, matchHash, executionPrice));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ecrecover(ethSignedMessageHash, 
            uint8(signature[0]), 
            bytes32(signature[1:33]), 
            bytes32(signature[33:65])
        );
        require(signer == msg.sender, "Invalid signature");
        
        // Record response
        TaskResponse memory response = TaskResponse({
            operator: msg.sender,
            taskId: task.taskId,
            matchHash: matchHash,
            executionPrice: executionPrice,
            signature: signature,
            timestamp: block.timestamp
        });
        
        taskResponses[taskIndex][msg.sender] = response;
        operatorResponded[taskIndex][msg.sender] = true;
        
        emit TaskResponded(taskIndex, msg.sender, response);
        
        // Check if quorum reached
        if (_checkQuorum(taskIndex)) {
            _completeTask(taskIndex);
        }
    }
    
    /**
     * @notice Challenge a task response
     * @param taskIndex The task index to challenge
     */
    function challengeTask(uint32 taskIndex) external onlyValidTask(taskIndex) {
        require(!taskChallenged[taskIndex], "Task already challenged");
        
        taskChallenged[taskIndex] = true;
        
        emit TaskChallenged(taskIndex, msg.sender);
    }
    
    /**
     * @notice Complete a task after quorum is reached
     * @param taskIndex The task index to complete
     */
    function _completeTask(uint32 taskIndex) internal {
        OrderMatchingTask storage task = orderMatchingTasks[taskIndex];
        require(!task.completed, "Task already completed");
        
        // Aggregate responses to find consensus
        (bytes32 consensusMatchHash, uint256 consensusExecutionPrice) = _aggregateResponses(taskIndex);
        
        task.completed = true;
        allTaskResponses[taskIndex] = keccak256(abi.encode(consensusMatchHash, consensusExecutionPrice));
        
        emit TaskCompleted(taskIndex, consensusMatchHash, consensusExecutionPrice);
    }
    
    /**
     * @notice Check if quorum is reached for a task
     * @param taskIndex The task index
     * @return True if quorum is reached
     */
    function _checkQuorum(uint32 taskIndex) internal view returns (bool) {
        uint256 responseCount = 0;
        uint256 totalOperators = registeredOperators.length;
        
        for (uint256 i = 0; i < totalOperators; i++) {
            if (operatorResponded[taskIndex][registeredOperators[i]]) {
                responseCount++;
            }
        }
        
        // Require 67% of operators to respond
        return responseCount >= (totalOperators * 67) / 100;
    }
    
    /**
     * @notice Aggregate operator responses to find consensus
     * @param taskIndex The task index
     * @return consensusMatchHash The consensus match hash
     * @return consensusExecutionPrice The consensus execution price
     */
    function _aggregateResponses(uint32 taskIndex) internal view returns (bytes32 consensusMatchHash, uint256 consensusExecutionPrice) {
        // For simplicity, return the first response
        // In production, you'd implement proper consensus logic
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            address operator = registeredOperators[i];
            if (operatorResponded[taskIndex][operator]) {
                TaskResponse storage response = taskResponses[taskIndex][operator];
                return (response.matchHash, response.executionPrice);
            }
        }
        
        revert("No responses found");
    }
    
    /**
     * @notice Remove operator from the registered operators array
     * @param operator The operator to remove
     */
    function _removeOperator(address operator) internal {
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Get task details
     * @param taskIndex The task index
     * @return task The order matching task details
     */
    function getTask(uint32 taskIndex) external view returns (OrderMatchingTask memory task) {
        return orderMatchingTasks[taskIndex];
    }
    
    /**
     * @notice Get operator information
     * @param operator The operator address
     * @return isRegistered Whether the operator is registered
     * @return stake The operator's stake
     */
    function getOperatorInfo(address operator) external view returns (bool isRegistered, uint256 stake) {
        isRegistered = operatorRegistered[operator];
        // Note: In a real implementation, you'd get the actual stake from EigenLayer
        stake = isRegistered ? MINIMUM_STAKE : 0;
    }
    
    /**
     * @notice Get all registered operators
     * @return operators Array of registered operator addresses
     */
    function getRegisteredOperators() external view returns (address[] memory operators) {
        return registeredOperators;
    }
    
    /**
     * @notice Get task response for an operator
     * @param taskIndex The task index
     * @param operator The operator address
     * @return response The task response
     */
    function getTaskResponse(uint32 taskIndex, address operator) external view returns (TaskResponse memory response) {
        return taskResponses[taskIndex][operator];
    }
} 