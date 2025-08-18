// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockAVSDirectory  
/// @notice Mock implementation of EigenLayer AVS Directory for testing
contract MockAVSDirectory {
    mapping(address => bool) public operatorRegistered;
    mapping(address => uint256) public operatorStake;
    mapping(address => address[]) public operatorAVSs;
    
    event OperatorAVSRegistrationStatusUpdated(
        address indexed operator,
        address indexed avs,
        uint8 status
    );
    
    function registerOperatorToAVS(
        address operator,
        bytes calldata signature
    ) external {
        operatorRegistered[operator] = true;
        operatorAVSs[operator].push(msg.sender);
        
        emit OperatorAVSRegistrationStatusUpdated(operator, msg.sender, 1);
    }
    
    function deregisterOperatorFromAVS(address operator) external {
        operatorRegistered[operator] = false;
        
        // Remove from AVS list
        address[] storage avsArray = operatorAVSs[operator];
        for (uint i = 0; i < avsArray.length; i++) {
            if (avsArray[i] == msg.sender) {
                avsArray[i] = avsArray[avsArray.length - 1];
                avsArray.pop();
                break;
            }
        }
        
        emit OperatorAVSRegistrationStatusUpdated(operator, msg.sender, 0);
    }
    
    function avsOperatorStatus(
        address avs,
        address operator
    ) external view returns (uint8) {
        address[] memory avsArray = operatorAVSs[operator];
        for (uint i = 0; i < avsArray.length; i++) {
            if (avsArray[i] == avs) {
                return 1; // Registered
            }
        }
        return 0; // Not registered
    }
    
    function operatorSaltIsSpent(
        address operator,
        bytes32 salt
    ) external view returns (bool) {
        // Mock implementation
        return false;
    }
    
    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) external view returns (bytes32) {
        return keccak256(abi.encodePacked(operator, avs, salt, expiry, block.chainid, address(this)));
    }
}