// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title EigenLayer Mock Contracts
/// @notice Simple mock implementations for EigenLayer components that don't fully implement interfaces

contract SimpleMockAVSDirectory {
    mapping(address => bool) public operatorRegistered;
    
    function registerOperatorToAVS(address operator, bytes memory /*signature*/) external {
        operatorRegistered[operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external {
        operatorRegistered[operator] = false;
    }
}

contract SimpleMockRewardsCoordinator {
    function createAVSRewardsSubmission(
        address[] calldata /*tokens*/,
        uint256[] calldata /*amounts*/,
        address /*avs*/,
        uint256 /*startTimestamp*/,
        uint256 /*duration*/,
        string calldata /*description*/
    ) external {}
}

contract SimpleMockSlashingRegistryCoordinator {
    function registerOperator(address /*operator*/, uint32 /*serveUntilBlock*/) external {}
    function deregisterOperator(address /*operator*/) external {}
}

contract SimpleMockStakeRegistry {
    function registerOperator(address /*operator*/, bytes calldata /*signature*/) external {}
    function deregisterOperator(address /*operator*/) external {}
}

contract SimpleMockPermissionController {
    function setPermission(address /*target*/, bytes4 /*selector*/, bool /*allowed*/) external {}
}

contract SimpleMockAllocationManager {
    function allocateToOperator(address /*operator*/, uint256 /*amount*/) external {}
    function deallocateFromOperator(address /*operator*/, uint256 /*amount*/) external {}
}