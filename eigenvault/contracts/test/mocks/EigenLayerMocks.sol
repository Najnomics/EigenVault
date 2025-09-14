// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title EigenLayer Mock Contracts
/// @notice Reusable mock implementations for EigenLayer interfaces

contract MockAVSDirectory {
    function registerOperator(address /*operator*/, bytes calldata /*operatorSignature*/) external {}
    function deregisterOperator(address /*operator*/) external {}
}

contract MockRewardsCoordinator {
    function createAVSRewardsSubmission(
        address[] calldata /*rewardsSubmissionTokens*/,
        uint256[] calldata /*rewardsSubmissionAmounts*/,
        address /*rewardsSubmissionToken*/,
        uint256 /*rewardsSubmissionAmount*/,
        uint32 /*rewardsSubmissionDuration*/,
        uint32 /*rewardsSubmissionStartTimestamp*/
    ) external {}
}

contract MockSlashingRegistryCoordinator {
    function registerOperator(
        address /*operator*/,
        uint32 /*serveUntilBlock*/
    ) external {}
    
    function deregisterOperator(address /*operator*/) external {}
}

contract MockStakeRegistry {
    function registerOperator(
        address /*operator*/,
        bytes calldata /*signature*/
    ) external {}
    
    function deregisterOperator(address /*operator*/) external {}
}

contract MockPermissionController {
    function setPermission(address /*target*/, bytes4 /*selector*/, bool /*allowed*/) external {}
}

contract MockAllocationManager {
    function allocateToOperator(address /*operator*/, uint256 /*amount*/) external {}
    function deallocateFromOperator(address /*operator*/, uint256 /*amount*/) external {}
}