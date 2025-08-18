// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockStakeRegistry
/// @notice Mock implementation of EigenLayer Stake Registry for testing
contract MockStakeRegistry {
    mapping(address => uint256) public operatorStake;
    mapping(address => bool) public isOperatorRegistered;
    mapping(address => uint256) public quorumBitmaps;
    
    event OperatorStakeUpdate(
        address indexed operator,
        uint8 quorumNumber,
        uint256 stake
    );
    
    event OperatorRegistered(
        address indexed operator,
        uint256 quorumBitmap
    );
    
    function registerOperator(
        address operator,
        uint256 quorumBitmap,
        bytes calldata signature
    ) external {
        isOperatorRegistered[operator] = true;
        quorumBitmaps[operator] = quorumBitmap;
        
        emit OperatorRegistered(operator, quorumBitmap);
    }
    
    function deregisterOperator(address operator) external {
        isOperatorRegistered[operator] = false;
        operatorStake[operator] = 0;
        quorumBitmaps[operator] = 0;
    }
    
    function setOperatorStake(address operator, uint256 stake) external {
        operatorStake[operator] = stake;
        
        emit OperatorStakeUpdate(operator, 0, stake);
    }
    
    function getCurrentStake(
        address operator,
        uint8 quorumNumber
    ) external view returns (uint96) {
        return uint96(operatorStake[operator]);
    }
    
    function getStakeAtBlockNumber(
        address operator,
        uint8 quorumNumber,
        uint32 blockNumber
    ) external view returns (uint96) {
        return uint96(operatorStake[operator]);
    }
    
    function getOperatorFromIndex(
        uint8 quorumNumber,
        uint256 index
    ) external pure returns (address) {
        // Mock implementation - return zero address if not found
        return address(0);
    }
    
    function getOperatorIndex(
        uint8 quorumNumber,
        address operator
    ) external pure returns (uint32) {
        return 0; // Mock index
    }
    
    function quorumExists(uint8 quorumNumber) external pure returns (bool) {
        return quorumNumber < 192; // Mock - support up to 192 quorums
    }
    
    function minimumStakeForQuorum(uint8 quorumNumber) external pure returns (uint96) {
        return 32 ether; // 32 ETH minimum stake
    }
}