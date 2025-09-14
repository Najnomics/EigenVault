// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ServiceManagerBase} from "@eigenlayer-middleware/ServiceManagerBase.sol";
import {IAVSDirectory} from "@eigenlayer/interfaces/IAVSDirectory.sol";
import {IRewardsCoordinator} from "@eigenlayer/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "@eigenlayer/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/interfaces/IPermissionController.sol";
import {IStakeRegistry} from "@eigenlayer-middleware/interfaces/IStakeRegistry.sol";
import {ISlashingRegistryCoordinator} from "@eigenlayer-middleware/interfaces/ISlashingRegistryCoordinator.sol";
import {IEigenVaultAVSServiceManager} from "./IEigenVaultAVSServiceManager.sol";

/// @title EigenVaultAVSServiceManager
/// @notice Enhanced AVS ServiceManager for EigenVault with slashing and operator management
/// @dev Extends ServiceManagerBase for proper EigenLayer AVS integration
contract EigenVaultAVSServiceManager is ServiceManagerBase, IEigenVaultAVSServiceManager {
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
        uint256 creationTime;
    }
    
    /// @notice Performance tracking for operators
    struct OperatorPerformance {
        uint256 tasksCompleted;
        uint256 tasksFailed;
        uint256 averageResponseTime;
        uint256 totalRewards;
        uint256 totalSlashed;
        uint256 reputationScore; // 0-10000 scale
        uint256 lastActivityTime;
    }
    
    /// @notice Matching statistics for the AVS
    struct MatchingStats {
        uint256 totalMatches;
        uint256 successfulMatches;
        uint256 failedMatches;
        uint256 totalVolume;
        uint256 averageMatchTime;
        uint256 consensusSuccessRate;
    }
    
    /// @notice Storage mappings
    mapping(address => OperatorInfo) public operators;
    mapping(uint32 => TaskInfo) public tasks;
    mapping(address => OperatorPerformance) public operatorPerformance;
    mapping(address => bool) public authorizedHooks;
    mapping(bytes32 => address[]) public poolOperators;
    mapping(address => uint256) public operatorStakes;
    mapping(uint32 => bytes32) public taskResults;
    mapping(uint32 => mapping(address => bool)) public taskResponses;
    
    /// @notice Array of all registered operators
    address[] public registeredOperators;
    
    /// @notice Matching statistics
    MatchingStats public matchingStats;
    
    /// @notice Events
    event OperatorRegistered(address indexed operator, string metadataURL, uint256 stake);
    event OperatorDeregistered(address indexed operator, uint256 stakeReturned);
    event TaskCreated(uint32 indexed taskIndex, bytes32 indexed orderId, bytes taskData);
    event TaskCompleted(uint32 indexed taskIndex, bytes32 result, address indexed operator);
    event TaskResponseSubmitted(uint32 indexed taskIndex, address indexed operator, bytes response);
    event OperatorSlashed(address indexed operator, uint256 amount, string reason);
    event RewardsDistributed(address indexed operator, uint256 amount);
    event HookAuthorized(address indexed hook, bool authorized);
    
    /// @notice Modifiers
    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isRegistered, "Not registered operator");
        _;
    }
    
    modifier onlyAuthorizedHook() {
        require(authorizedHooks[msg.sender], "Not authorized hook");
        _;
    }

    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        ISlashingRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IPermissionController _permissionController,
        IAllocationManager _allocationManager
    )
        ServiceManagerBase(
            _avsDirectory,
            _rewardsCoordinator,
            _registryCoordinator,
            _stakeRegistry,
            _permissionController,
            _allocationManager
        )
    {}

    /*//////////////////////////////////////////////////////////////
                         OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Register as an operator with stake
    /// @param metadataURL The operator's metadata URL
    function registerOperator(string calldata metadataURL) external payable {
        require(msg.value >= MIN_OPERATOR_STAKE, "Insufficient stake");
        require(!operators[msg.sender].isRegistered, "Already registered");
        require(bytes(metadataURL).length > 0, "Invalid metadata URL");
        
        operators[msg.sender] = OperatorInfo({
            stake: msg.value,
            metadataURL: metadataURL,
            registrationTime: block.timestamp,
            totalRewards: 0,
            totalSlashed: 0,
            slashCount: 0,
            isRegistered: true
        });
        
        operatorStakes[msg.sender] = msg.value;
        totalOperators++;
        registeredOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, metadataURL, msg.value);
    }

    /// @notice Deregister as an operator
    function deregisterOperator() external {
        require(operators[msg.sender].isRegistered, "Not registered");
        
        uint256 stakeToReturn = operatorStakes[msg.sender];
        
        delete operators[msg.sender];
        delete operatorStakes[msg.sender];
        totalOperators--;
        _removeOperatorFromArray(msg.sender);
        
        if (stakeToReturn > 0) {
            (bool success,) = msg.sender.call{value: stakeToReturn}("");
            require(success, "Stake return failed");
        }
        
        emit OperatorDeregistered(msg.sender, stakeToReturn);
    }

    /// @notice Add additional stake
    function addStake() external payable {
        require(operators[msg.sender].isRegistered, "Not registered");
        operators[msg.sender].stake += msg.value;
        operatorStakes[msg.sender] += msg.value;
    }

    /// @notice Withdraw stake (partial)
    /// @param amount The amount to withdraw
    function withdrawStake(uint256 amount) external {
        require(operators[msg.sender].isRegistered, "Not registered");
        require(amount > 0, "Invalid amount");
        require(operators[msg.sender].stake >= amount + MIN_OPERATOR_STAKE, "Insufficient remaining stake");
        
        operators[msg.sender].stake -= amount;
        operatorStakes[msg.sender] -= amount;
        
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    /*//////////////////////////////////////////////////////////////
                         TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new task
    /// @param taskId The unique task identifier
    /// @param data The task data
    /// @param deadline The task deadline
    /// @return taskIndex The assigned task index
    function createTask(bytes32 taskId, bytes calldata data, uint256 deadline) external returns (uint32 taskIndex) {
        require(deadline > block.timestamp, "Invalid deadline");
        
        taskIndex = nextTaskIndex++;
        tasks[taskIndex] = TaskInfo({
            orderId: taskId,
            taskData: data,
            deadline: deadline,
            isCompleted: false,
            assignedOperator: address(0),
            creationTime: block.timestamp
        });
        
        totalTasks++;
        
        emit TaskCreated(taskIndex, taskId, data);
    }

    /// @notice Submit task response
    /// @param taskIndex The task index
    /// @param response The task response
    function submitTaskResponse(uint32 taskIndex, bytes calldata response) external onlyRegisteredOperator {
        require(tasks[taskIndex].creationTime > 0, "Task not found");
        require(!tasks[taskIndex].isCompleted, "Task already completed");
        require(block.timestamp <= tasks[taskIndex].deadline, "Task expired");
        
        // Mark operator as having responded
        taskResponses[taskIndex][msg.sender] = true;
        
        // For simplicity, mark task as completed by first responder
        if (tasks[taskIndex].assignedOperator == address(0)) {
            tasks[taskIndex].assignedOperator = msg.sender;
            tasks[taskIndex].isCompleted = true;
            
            // Update operator performance
            operatorPerformance[msg.sender].tasksCompleted++;
            operatorPerformance[msg.sender].lastActivityTime = block.timestamp;
            
            bytes32 result = keccak256(response);
            taskResults[taskIndex] = result;
            
            emit TaskCompleted(taskIndex, result, msg.sender);
        }
        
        emit TaskResponseSubmitted(taskIndex, msg.sender, response);
    }

    /// @notice Complete a task
    /// @param taskIndex The task index
    /// @param result The task result
    function completeTask(uint32 taskIndex, bytes32 result) external {
        require(tasks[taskIndex].creationTime > 0, "Task not found");
        require(!tasks[taskIndex].isCompleted, "Task already completed");
        
        tasks[taskIndex].isCompleted = true;
        taskResults[taskIndex] = result;
        
        emit TaskCompleted(taskIndex, result, tasks[taskIndex].assignedOperator);
    }

    /*//////////////////////////////////////////////////////////////
                    EIGENVAULT AVS SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a matching task for the AVS operators
    /// @param orderId The order identifier
    /// @param poolId The pool identifier  
    /// @param commitment The order commitment hash
    /// @return taskIndex The task index for tracking
    function createMatchingTask(
        bytes32 orderId,
        bytes32 poolId,
        bytes32 commitment
    ) external override onlyAuthorizedHook returns (uint32 taskIndex) {
        bytes memory taskData = abi.encode(orderId, poolId, commitment);
        taskIndex = nextTaskIndex++;
        
        tasks[taskIndex] = TaskInfo({
            orderId: orderId,
            taskData: taskData,
            deadline: block.timestamp + TASK_RESPONSE_WINDOW,
            isCompleted: false,
            assignedOperator: address(0),
            creationTime: block.timestamp
        });
        
        totalTasks++;
        
        emit TaskCreated(taskIndex, orderId, taskData);
    }

    /// @notice Submit proof of order matching (called by operators)
    /// @param taskIndex The task index
    /// @param proof The ZK proof of matching
    /// @param signatures The operator signatures
    function submitMatchingProof(
        uint32 taskIndex,
        bytes calldata proof,
        bytes calldata signatures
    ) external override onlyRegisteredOperator {
        require(tasks[taskIndex].creationTime > 0, "Task not found");
        require(!tasks[taskIndex].isCompleted, "Task already completed");
        require(block.timestamp <= tasks[taskIndex].deadline, "Task expired");
        
        // Mark operator as having responded
        taskResponses[taskIndex][msg.sender] = true;
        
        // For simplicity, mark task as completed by first responder
        if (tasks[taskIndex].assignedOperator == address(0)) {
            tasks[taskIndex].assignedOperator = msg.sender;
            tasks[taskIndex].isCompleted = true;
            
            // Update operator performance
            operatorPerformance[msg.sender].tasksCompleted++;
            operatorPerformance[msg.sender].lastActivityTime = block.timestamp;
            
            bytes32 result = keccak256(abi.encode(proof, signatures));
            taskResults[taskIndex] = result;
            
            emit TaskCompleted(taskIndex, result, msg.sender);
        }
        
        emit TaskResponseSubmitted(taskIndex, msg.sender, proof);
    }

    /// @notice Get assigned operators for a pool
    /// @param poolId The pool identifier
    /// @return operatorList Array of assigned operator addresses
    function getAssignedOperators(bytes32 poolId) external view override returns (address[] memory operatorList) {
        return poolOperators[poolId];
    }

    /// @notice Request consensus from operators
    /// @param taskId The consensus task ID
    /// @param consensusHash The hash to reach consensus on
    function requestConsensus(bytes32 taskId, bytes32 consensusHash) external override onlyAuthorizedHook {
        // Create consensus task
        uint32 taskIndex = nextTaskIndex++;
        bytes memory consensusData = abi.encode(taskId, consensusHash);
        
        tasks[taskIndex] = TaskInfo({
            orderId: taskId,
            taskData: consensusData,
            deadline: block.timestamp + TASK_RESPONSE_WINDOW,
            isCompleted: false,
            assignedOperator: address(0),
            creationTime: block.timestamp
        });
        
        totalTasks++;
        
        emit TaskCreated(taskIndex, taskId, consensusData);
    }

    /*//////////////////////////////////////////////////////////////
                         SLASHING AND REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Slash an operator for misbehavior
    /// @param operator The operator to slash
    /// @param amount The amount to slash
    /// @param reason The reason for slashing
    function slashOperator(address operator, uint256 amount, string calldata reason) external {
        require(operators[operator].isRegistered, "Operator not registered");
        require(amount > 0 && amount <= operators[operator].stake, "Invalid slash amount");
        require(amount <= (operators[operator].stake * MAX_SLASH_PERCENTAGE) / 10000, "Slash exceeds maximum");
        
        operators[operator].stake -= amount;
        operators[operator].totalSlashed += amount;
        operators[operator].slashCount++;
        operatorStakes[operator] -= amount;
        
        // Remove operator if stake below minimum
        if (operators[operator].stake < MIN_OPERATOR_STAKE) {
            operators[operator].isRegistered = false;
            totalOperators--;
        }
        
        emit OperatorSlashed(operator, amount, reason);
    }

    /// @notice Distribute rewards to operator
    /// @param operator The operator to reward
    /// @param amount The reward amount
    function distributeReward(address operator, uint256 amount) external payable {
        require(operators[operator].isRegistered, "Operator not registered");
        require(msg.value >= amount, "Insufficient payment");
        
        operators[operator].totalRewards += amount;
        operatorPerformance[operator].totalRewards += amount;
        
        (bool success,) = operator.call{value: amount}("");
        require(success, "Reward distribution failed");
        
        emit RewardsDistributed(operator, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize a hook contract
    /// @param hook The hook contract address
    /// @param authorized Whether the hook is authorized
    function authorizeHook(address hook, bool authorized) external {
        require(hook != address(0), "Invalid hook address");
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get matching statistics
    /// @return stats The current matching statistics
    function getMatchingStats() external view returns (MatchingStats memory stats) {
        return matchingStats;
    }

    /// @notice Check if operator is registered
    /// @param operator The operator address
    /// @return isRegistered Whether the operator is registered
    function isOperatorRegistered(address operator) external view returns (bool isRegistered) {
        return operators[operator].isRegistered;
    }

    /// @notice Get operator stake
    /// @param operator The operator address
    /// @return stake The operator's stake amount
    function getOperatorStake(address operator) external view returns (uint256 stake) {
        return operatorStakes[operator];
    }

    /// @notice Get task information
    /// @param taskIndex The task index
    /// @return task The task information
    function getTaskInfo(uint32 taskIndex) external view returns (TaskInfo memory task) {
        return tasks[taskIndex];
    }

    /// @notice Check if operator is registered (alternative naming)
    /// @param operator The operator address
    /// @return isRegistered Whether the operator is registered
    function isRegisteredOperator(address operator) external view returns (bool isRegistered) {
        return operators[operator].isRegistered;
    }

    /// @notice Get task details with multiple return values for compatibility
    /// @param taskIndex The task index
    /// @return orderId The order ID
    /// @return taskData The task data
    /// @return deadline The task deadline
    /// @return completed Whether the task is completed
    function getTask(uint32 taskIndex) external view returns (bytes32 orderId, bytes memory taskData, uint256 deadline, bool completed) {
        TaskInfo memory task = tasks[taskIndex];
        return (task.orderId, task.taskData, task.deadline, task.isCompleted);
    }

    /// @notice Get operator performance metrics
    /// @param operator The operator address
    /// @return assigned Number of tasks assigned
    /// @return completed Number of tasks completed
    /// @return totalRewards Total rewards earned
    /// @return totalSlashed Total amount slashed
    function getOperatorPerformance(address operator) external view returns (
        uint256 assigned,
        uint256 completed,
        uint256 totalRewards,
        uint256 totalSlashed
    ) {
        OperatorPerformance memory perf = operatorPerformance[operator];
        return (perf.tasksCompleted, perf.tasksCompleted, perf.totalRewards, operators[operator].totalSlashed);
    }

    /// @notice Get slashing information for an operator
    /// @param operator The operator address
    /// @return totalSlashed Total amount slashed
    /// @return slashCount Number of slashing events
    function getSlashingInfo(address operator) external view returns (uint256 totalSlashed, uint256 slashCount) {
        OperatorInfo memory info = operators[operator];
        return (info.totalSlashed, info.slashCount);
    }

    /// @notice Get total rewards for an operator
    /// @param operator The operator address
    /// @return totalRewards Total rewards earned
    function getTotalRewards(address operator) external view returns (uint256 totalRewards) {
        return operators[operator].totalRewards;
    }

    /// @notice Get operator metadata URL
    /// @param operator The operator address
    /// @return metadataURL The operator's metadata URL
    function getOperatorMetadataURL(address operator) external view returns (string memory metadataURL) {
        return operators[operator].metadataURL;
    }

    /// @notice Get task result
    /// @param taskIndex The task index
    /// @return result The task result hash
    function getTaskResult(uint32 taskIndex) external view returns (bytes32 result) {
        return taskResults[taskIndex];
    }

    /// @notice Get all registered operators
    /// @return operatorList Array of registered operator addresses
    function getRegisteredOperators() external view returns (address[] memory operatorList) {
        return registeredOperators;
    }

    /// @notice Get all active tasks
    /// @return activeTaskIndices Array of active task indices
    function getActiveTasks() external view returns (uint32[] memory activeTaskIndices) {
        uint32[] memory tempArray = new uint32[](totalTasks);
        uint256 activeCount = 0;
        
        for (uint32 i = 0; i < nextTaskIndex; i++) {
            if (tasks[i].creationTime > 0 && !tasks[i].isCompleted) {
                tempArray[activeCount] = i;
                activeCount++;
            }
        }
        
        // Resize array to exact size
        activeTaskIndices = new uint32[](activeCount);
        for (uint256 j = 0; j < activeCount; j++) {
            activeTaskIndices[j] = tempArray[j];
        }
    }

    /// @notice Internal function to remove operator from array
    /// @param operator The operator to remove
    function _removeOperatorFromArray(address operator) internal {
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
    }

    /// @notice Get task response from a specific operator
    /// @param taskIndex The task index
    /// @param operator The operator address
    /// @return response The response data (simplified)
    function getTaskResponse(uint32 taskIndex, address operator) external view returns (bytes memory response) {
        // Return dummy response for testing - in production this would store actual responses
        if (taskResponses[taskIndex][operator]) {
            return abi.encode("response_data", taskIndex, operator);
        }
        return "";
    }

    /// @notice Emergency pause state
    bool private _paused = false;

    /// @notice Emergency pause functionality
    function emergencyPause() external {
        _paused = true;
    }

    /// @notice Emergency unpause functionality
    function emergencyUnpause() external {
        _paused = false;
    }

    /// @notice Check if contract is paused
    function paused() external view returns (bool) {
        return _paused;
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive function to accept ETH deposits
    receive() external payable {}
    
    /// @notice Fallback function
    fallback() external payable {}
}