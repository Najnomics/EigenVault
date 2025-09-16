// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from "@eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "@eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from "@eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {TaskAVSRegistrarBase} from "@eigenlayer-middleware/src/avs/task/TaskAVSRegistrarBase.sol";

/**
 * @title EigenVaultTaskAVSRegistrar
 * @dev L1 contract that manages operator registration and staking for the EigenVault AVS.
 * This contract extends TaskAVSRegistrarBase to provide DevKit compliance and integrates
 * with EigenLayer's staking and operator management system.
 */
contract EigenVaultTaskAVSRegistrar is TaskAVSRegistrarBase {
    /// @notice Minimum stake required for operators (32 ETH)
    uint256 public constant MINIMUM_STAKE = 32 ether;
    
    /// @notice Address of the L2 EigenVault task hook contract
    address public eigenVaultTaskHook;
    
    /// @notice Mapping of operator addresses to their performance scores
    mapping(address => uint256) public operatorPerformanceScores;
    
    /// @notice Mapping of operator addresses to their last task completion timestamp
    mapping(address => uint256) public operatorLastTaskCompletion;

    /// @notice Event emitted when an operator's performance score is updated
    event OperatorPerformanceUpdated(address indexed operator, uint256 score);
    
    /// @notice Event emitted when the EigenVault task hook address is updated
    event EigenVaultTaskHookUpdated(address indexed oldHook, address indexed newHook);

    /**
     * @dev Constructor that passes parameters to parent TaskAVSRegistrarBase
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     * @param _permissionController The PermissionController contract address
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController
    ) TaskAVSRegistrarBase(_allocationManager, _keyRegistrar, _permissionController) {}

    /**
     * @dev Initializer that calls parent initializer
     * @param _avs The address of the AVS
     * @param _owner The owner of the contract
     * @param _initialConfig The initial AVS configuration
     */
    function initialize(
        address _avs, 
        address _owner, 
        AvsConfig memory _initialConfig
    ) external initializer {
        __TaskAVSRegistrarBase_init(_avs, _owner, _initialConfig);
    }

    /**
     * @notice Set the address of the EigenVault task hook contract
     * @param _eigenVaultTaskHook The address of the L2 task hook contract
     */
    function setEigenVaultTaskHook(address _eigenVaultTaskHook) external onlyOwner {
        require(_eigenVaultTaskHook != address(0), "Invalid task hook address");
        
        address oldHook = eigenVaultTaskHook;
        eigenVaultTaskHook = _eigenVaultTaskHook;
        
        emit EigenVaultTaskHookUpdated(oldHook, _eigenVaultTaskHook);
    }

    /**
     * @notice Update an operator's performance score
     * @param operator The operator address
     * @param score The new performance score
     */
    function updateOperatorPerformance(address operator, uint256 score) external {
        require(msg.sender == eigenVaultTaskHook || msg.sender == owner(), "Unauthorized");
        require(isOperatorRegistered(operator), "Operator not registered");
        
        operatorPerformanceScores[operator] = score;
        operatorLastTaskCompletion[operator] = block.timestamp;
        
        emit OperatorPerformanceUpdated(operator, score);
    }

    /**
     * @notice Get operator performance score
     * @param operator The operator address
     * @return The operator's performance score
     */
    function getOperatorPerformanceScore(address operator) external view returns (uint256) {
        return operatorPerformanceScores[operator];
    }

    /**
     * @notice Check if operator meets minimum stake requirements for EigenVault
     * @param operator The operator address to check
     * @return Whether the operator meets the minimum stake
     */
    function meetsMinimumStake(address operator) external view returns (bool) {
        // Note: This would integrate with EigenLayer's staking system
        // For now, we'll assume this is implemented in the parent contract
        return isOperatorRegistered(operator);
    }

    /**
     * @notice Get the number of eligible operators for task assignment
     * @return The count of operators that meet requirements
     */
    function getEligibleOperatorCount() external view returns (uint256) {
        // This would iterate through registered operators and check their eligibility
        // For now, return the total registered operator count
        return getRegisteredOperatorCount();
    }

    /**
     * @notice Check if an operator is eligible for task assignment
     * @param operator The operator address
     * @return Whether the operator is eligible
     */
    function isOperatorEligible(address operator) external view returns (bool) {
        if (!isOperatorRegistered(operator)) {
            return false;
        }
        
        // Check performance score threshold (minimum 80%)
        uint256 performanceScore = operatorPerformanceScores[operator];
        if (performanceScore > 0 && performanceScore < 80) {
            return false;
        }
        
        // Check if operator has been active recently (within last 24 hours)
        if (operatorLastTaskCompletion[operator] > 0) {
            uint256 timeSinceLastTask = block.timestamp - operatorLastTaskCompletion[operator];
            if (timeSinceLastTask > 24 hours) {
                return false;
            }
        }
        
        return true;
    }
}