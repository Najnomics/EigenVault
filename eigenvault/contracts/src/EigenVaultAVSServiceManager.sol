// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IEigenVaultAVSServiceManager} from "./interfaces/IEigenVaultAVSServiceManager.sol";

/// @title EigenVaultAVSServiceManager
/// @notice EigenLayer AVS service manager for EigenVault with ZK proof integration
/// @dev Manages operator registration, task creation, and consensus for order matching
contract EigenVaultAVSServiceManager is ReentrancyGuard, Ownable, IEigenVaultAVSServiceManager {
    using MessageHashUtils for bytes32;

    // Enums
    enum TaskStatus {
        Pending,
        Completed,
        Failed
    }

    // Errors
    error EigenVaultAVSServiceManager__InvalidOperator();
    error EigenVaultAVSServiceManager__OperatorAlreadyRegistered();
    error EigenVaultAVSServiceManager__OperatorNotRegistered();
    error EigenVaultAVSServiceManager__InvalidTask();
    error EigenVaultAVSServiceManager__TaskNotFound();
    error EigenVaultAVSServiceManager__TaskAlreadyCompleted();
    error EigenVaultAVSServiceManager__InvalidSignature();
    error EigenVaultAVSServiceManager__InsufficientStake();
    error EigenVaultAVSServiceManager__QuorumNotReached();
    error EigenVaultAVSServiceManager__InvalidZKProof();

    // Constants
    uint256 public constant MIN_STAKE_AMOUNT = 32 ether;
    uint256 public constant TASK_RESPONSE_WINDOW = 1 hours;
    uint256 public constant QUORUM_THRESHOLD = 2; // Minimum 2 operators must agree

    // State variables
    mapping(address => bool) public registeredOperators;
    mapping(address => uint256) public operatorStakes;
    
    /// @notice Array of registered operator addresses for iteration
    address[] public registeredOperatorAddresses;
    mapping(uint32 => MatchingTask) public matchingTasks;
    mapping(uint32 => mapping(address => TaskResponse)) public taskResponses;
    mapping(uint32 => mapping(address => bool)) public operatorResponded;
    
    // Task management
    uint32 public latestTaskNum;
    uint32 public completedTaskCount;

    // Events unique to implementation
    event TaskDataUpdated(uint32 indexed taskIndex, uint256 value, uint256 price, uint256 volume);

    constructor() Ownable(msg.sender) {
        // No initialization needed for ZK-based system
    }

    // ============ Operator Management ============

    /// @notice Register an operator
    /// @param operatorSignature Signature proving operator authorization
    function registerOperator(bytes calldata operatorSignature) external payable override {
        // Decode operator address from signature
        address operator = msg.sender; // For now, use msg.sender as operator
        
        if (operator == address(0)) {
            revert EigenVaultAVSServiceManager__InvalidOperator();
        }
        if (registeredOperators[operator]) {
            revert EigenVaultAVSServiceManager__OperatorAlreadyRegistered();
        }
        if (msg.value < MIN_STAKE_AMOUNT) {
            revert EigenVaultAVSServiceManager__InsufficientStake();
        }

        registeredOperators[operator] = true;
        operatorStakes[operator] = msg.value;
        registeredOperatorAddresses.push(operator);

        emit OperatorRegistered(operator, msg.value);
    }

    /// @notice Deregister from the AVS
    function deregisterOperator() external override {
        address operator = msg.sender;
        
        if (!registeredOperators[operator]) {
            revert EigenVaultAVSServiceManager__OperatorNotRegistered();
        }

        uint256 stake = operatorStakes[operator];
        registeredOperators[operator] = false;
        operatorStakes[operator] = 0;

        // Remove from registered operators array
        for (uint256 i = 0; i < registeredOperatorAddresses.length; i++) {
            if (registeredOperatorAddresses[i] == operator) {
                registeredOperatorAddresses[i] = registeredOperatorAddresses[registeredOperatorAddresses.length - 1];
                registeredOperatorAddresses.pop();
                break;
            }
        }

        // Return stake to operator
        (bool success, ) = operator.call{value: stake}("");
        require(success, "Failed to return stake");

        emit OperatorDeregistered(operator);
    }

    // ============ Task Management ============

    /// @notice Create a new matching task
    /// @param orderId The order ID
    /// @param poolId The pool ID
    /// @param ordersHash The hash of the orders to match
    /// @return taskIndex The index of the created task
    function createMatchingTask(
        bytes32 orderId,
        bytes32 poolId,
        bytes32 ordersHash
    ) external override returns (uint32 taskIndex) {
        require(orderId != bytes32(0), "Invalid order ID");
        require(poolId != bytes32(0), "Invalid pool ID");
        require(ordersHash != bytes32(0), "Invalid orders hash");

        taskIndex = latestTaskNum + 1;
        latestTaskNum = taskIndex;

        matchingTasks[taskIndex] = MatchingTask({
            taskId: orderId,
            poolId: poolId,
            ordersHash: ordersHash,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + TASK_RESPONSE_WINDOW,
            completed: false
        });

        emit NewTaskCreated(taskIndex, matchingTasks[taskIndex]);
        return taskIndex;
    }

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
    ) external override {
        require(registeredOperators[msg.sender], "Operator not registered");
        require(taskIndex <= latestTaskNum, "Task not found");
        require(!matchingTasks[taskIndex].completed, "Task already completed");
        require(block.timestamp <= matchingTasks[taskIndex].deadline, "Task deadline passed");
        require(!operatorResponded[taskIndex][msg.sender], "Already responded");

        // Create task response
        TaskResponse memory response = TaskResponse({
            operator: msg.sender,
            taskId: matchingTasks[taskIndex].taskId,
            matchHash: matchHash,
            executionPrice: executionPrice,
            signature: signature,
            timestamp: block.timestamp
        });

        // Store response
        taskResponses[taskIndex][msg.sender] = response;
        operatorResponded[taskIndex][msg.sender] = true;

        emit TaskResponded(taskIndex, msg.sender, response);

        // Check if quorum is reached
        _checkQuorum(taskIndex);
    }

    /// @notice Complete a task after quorum is reached
    /// @param taskIndex The task index
    /// @param finalResult The final result hash
    /// @param zkProof The ZK proof of consensus
    function completeTask(
        uint32 taskIndex,
        bytes32 finalResult,
        bytes calldata zkProof
    ) external {
        require(taskIndex <= latestTaskNum, "Task not found");
        require(!matchingTasks[taskIndex].completed, "Task already completed");
        // Check if quorum is reached by counting responses
        uint256 responseCount = 0;
        for (uint256 i = 0; i < registeredOperatorAddresses.length; i++) {
            if (operatorResponded[taskIndex][registeredOperatorAddresses[i]]) {
                responseCount++;
            }
        }
        require(responseCount >= QUORUM_THRESHOLD, "Quorum not reached");

        // Verify ZK proof of consensus
        require(_verifyConsensusProof(taskIndex, finalResult, zkProof), "Invalid consensus proof");

        // Update task status
        matchingTasks[taskIndex].completed = true;
        completedTaskCount++;

        emit TaskCompleted(taskIndex, finalResult, 0); // executionPrice placeholder
    }

    // ============ Quorum Management ============

    /// @notice Check if quorum is reached for a task
    /// @param taskIndex The task index
    function _checkQuorum(uint32 taskIndex) internal {
        uint256 responseCount = 0;
        
        for (uint256 i = 0; i < registeredOperatorAddresses.length; i++) {
            if (operatorResponded[taskIndex][registeredOperatorAddresses[i]]) {
                responseCount++;
            }
        }

        if (responseCount >= QUORUM_THRESHOLD) {
            // Add quorumReached field to MatchingTask if needed
            emit QuorumReached(taskIndex, responseCount);
        }
    }

    // ============ ZK Proof Verification ============

    /// @notice Verify ZK proof for consensus
    /// @param taskIndex The task index
    /// @param finalResult The final result
    /// @param zkProof The ZK proof
    function _verifyConsensusProof(
        uint32 taskIndex,
        bytes32 finalResult,
        bytes calldata zkProof
    ) internal pure returns (bool) {
        // TODO: Implement ZK proof verification for consensus
        // This would integrate with your ZK proof system
        // For now, return true as placeholder
        return true;
    }

    // ============ View Functions ============

    /// @notice Get task details
    /// @param taskIndex The task index
    function getTask(uint32 taskIndex) external view override returns (MatchingTask memory) {
        return matchingTasks[taskIndex];
    }

    /// @notice Get operator response for a task
    /// @param taskIndex The task index
    /// @param operator The operator address
    function getTaskResponse(uint32 taskIndex, address operator) external view override returns (TaskResponse memory) {
        return taskResponses[taskIndex][operator];
    }

    /// @notice Check if operator has responded to a task
    /// @param taskIndex The task index
    /// @param operator The operator address
    function hasOperatorResponded(uint32 taskIndex, address operator) external view returns (bool) {
        return operatorResponded[taskIndex][operator];
    }

    /// @notice Get registered operator count
    function getRegisteredOperatorCount() external view returns (uint256) {
        return registeredOperatorAddresses.length;
    }

    /// @notice Get operator stake
    /// @param operator The operator address
    function getOperatorStake(address operator) external view returns (uint256) {
        return operatorStakes[operator];
    }

    /// @notice Check if address is registered operator
    /// @param operator The operator address
    function isRegisteredOperator(address operator) external view returns (bool) {
        return registeredOperators[operator];
    }

    /// @notice Get operator information
    /// @param operator The operator address
    /// @return isRegistered Whether the operator is registered
    /// @return stake The operator's stake
    function getOperatorInfo(address operator) external view override returns (bool isRegistered, uint256 stake) {
        return (registeredOperators[operator], operatorStakes[operator]);
    }

    /// @notice Get all registered operators
    /// @return operators Array of registered operator addresses
    function getRegisteredOperators() external view override returns (address[] memory operators) {
        return registeredOperatorAddresses;
    }

    /// @notice Get assigned operators for a specific task
    /// @param matchId The match ID
    /// @return operators Array of assigned operator addresses
    function getAssignedOperators(bytes32 matchId) external view override returns (address[] memory operators) {
        // For now, return a default set of operators
        // In production, this would query the actual AVS registry
        operators = new address[](3);
        operators[0] = address(0x1);
        operators[1] = address(0x2);
        operators[2] = address(0x3);
        return operators;
    }

    /// @notice Request consensus from operators
    /// @param taskId The consensus task ID
    /// @param consensusHash The consensus hash to validate
    function requestConsensus(bytes32 taskId, bytes32 consensusHash) external override {
        // Emit event for operator notification
        emit ConsensusRequested(taskId, consensusHash, block.timestamp);
        
        // In production, this would trigger operator notifications
        // For now, just log the request
    }

    // ============ Challenge Functions ============

    /// @notice Challenge a task response
    /// @param taskIndex The task index to challenge
    function challengeTask(uint32 taskIndex) external override {
        // TODO: Implement challenge logic
        emit TaskChallenged(taskIndex, msg.sender);
    }

    // ============ Emergency Functions ============

    /// @notice Emergency pause (owner only)
    function emergencyPause() external onlyOwner {
        // TODO: Implement emergency pause functionality
        emit EmergencyPaused(msg.sender);
    }

    /// @notice Emergency unpause (owner only)
    function emergencyUnpause() external onlyOwner {
        // TODO: Implement emergency unpause functionality
        emit EmergencyUnpaused(msg.sender);
    }

    /// @notice Slash operator for misbehavior
    /// @param operator The operator to slash
    /// @param amount The amount to slash
    function slashOperator(address operator, uint256 amount) external onlyOwner {
        require(registeredOperators[operator], "Operator not registered");
        require(amount <= operatorStakes[operator], "Amount exceeds stake");

        operatorStakes[operator] -= amount;
        
        // Transfer slashed amount to owner (or burn)
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Failed to transfer slashed amount");

        emit StakeSlashed(operator, amount);
    }

    // ============ Events ============

    event QuorumReached(uint32 indexed taskIndex, uint256 responseCount);
    event EmergencyPaused(address indexed pauser);
    event EmergencyUnpaused(address indexed unpauser);
    event ConsensusRequested(bytes32 indexed taskId, bytes32 indexed consensusHash, uint256 timestamp);
} 