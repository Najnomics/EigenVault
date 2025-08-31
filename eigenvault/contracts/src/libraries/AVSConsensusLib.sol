// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title AVSConsensusLib
/// @notice Advanced consensus library for EigenLayer AVS operators
library AVSConsensusLib {
    /// @notice Consensus result structure
    struct ConsensusResult {
        bytes32 consensusId;
        bytes32 matchId;
        uint256 consensusThreshold;
        uint256 agreedOperators;
        uint256 totalOperators;
        bool consensusReached;
        uint256 timestamp;
        bytes32 finalHash;
    }

    /// @notice Operator response structure
    struct OperatorResponse {
        address operator;
        bytes32 responseHash;
        uint256 timestamp;
        bool isValid;
        bytes signature;
    }

    /// @notice Consensus task structure
    struct ConsensusTask {
        bytes32 taskId;
        bytes32 matchId;
        uint256 consensusThreshold;
        uint256 deadline;
        bool completed;
        address[] assignedOperators;
        mapping(address => OperatorResponse) responses;
        uint256 responseCount;
    }

    /// @notice Consensus configuration
    struct ConsensusConfig {
        uint256 minOperators;
        uint256 consensusThreshold;
        uint256 responseTimeout;
        uint256 maxRetries;
        bool requireSignature;
    }

    /// @notice Events
    event ConsensusTaskCreated(bytes32 indexed taskId, bytes32 indexed matchId, uint256 threshold);
    event OperatorResponded(bytes32 indexed taskId, address indexed operator, bytes32 responseHash);
    event ConsensusReached(bytes32 indexed taskId, bytes32 consensusHash, uint256 agreedOperators);
    event ConsensusFailed(bytes32 indexed taskId, string reason);

    /// @notice Create a new consensus task
    /// @param matchId The match ID requiring consensus
    /// @param operators Array of assigned operators
    /// @param config Consensus configuration
    /// @return taskId The created task ID
    function createConsensusTask(
        bytes32 matchId,
        address[] memory operators,
        ConsensusConfig memory config
    ) internal returns (bytes32 taskId) {
        require(operators.length >= config.minOperators, "Insufficient operators");
        require(config.consensusThreshold > 0, "Invalid consensus threshold");
        
        taskId = keccak256(abi.encodePacked(
            matchId,
            operators,
            block.timestamp,
            block.chainid
        ));
        
        emit ConsensusTaskCreated(taskId, matchId, config.consensusThreshold);
    }

    /// @notice Submit operator response to consensus task
    /// @param task The consensus task
    /// @param operator The operator address
    /// @param responseHash The response hash
    /// @param signature The operator signature
    /// @return success Whether the response was accepted
    function submitOperatorResponse(
        ConsensusTask storage task,
        address operator,
        bytes32 responseHash,
        bytes memory signature
    ) internal returns (bool success) {
        // Check if operator is assigned to this task
        bool isAssigned = false;
        for (uint256 i = 0; i < task.assignedOperators.length; i++) {
            if (task.assignedOperators[i] == operator) {
                isAssigned = true;
                break;
            }
        }
        
        require(isAssigned, "Operator not assigned to task");
        require(!task.responses[operator].isValid, "Operator already responded");
        require(block.timestamp <= task.deadline, "Task deadline passed");
        
        // Verify signature if required
        if (task.consensusThreshold > 0) {
            require(_verifySignature(operator, responseHash, signature), "Invalid signature");
        }
        
        // Record response
        task.responses[operator] = OperatorResponse({
            operator: operator,
            responseHash: responseHash,
            timestamp: block.timestamp,
            isValid: true,
            signature: signature
        });
        
        task.responseCount++;
        
        emit OperatorResponded(task.taskId, operator, responseHash);
        
        // Check if consensus can be reached
        _checkConsensus(task);
        
        return true;
    }

    /// @notice Check if consensus has been reached
    /// @param task The consensus task
    /// @return consensusResult The consensus result
    function checkConsensus(
        ConsensusTask storage task
    ) internal view returns (ConsensusResult memory consensusResult) {
        consensusResult = ConsensusResult({
            consensusId: task.taskId,
            matchId: task.matchId,
            consensusThreshold: task.consensusThreshold,
            agreedOperators: 0,
            totalOperators: task.assignedOperators.length,
            consensusReached: false,
            timestamp: block.timestamp,
            finalHash: bytes32(0)
        });
        
        if (task.responseCount < task.assignedOperators.length) {
            return consensusResult;
        }
        
        // Count responses and find most common response hash
        bytes32[] memory responseHashes = new bytes32[](task.responseCount);
        uint256[] memory hashCounts = new uint256[](task.responseCount);
        uint256 uniqueHashes = 0;
        
        for (uint256 i = 0; i < task.assignedOperators.length; i++) {
            address operator = task.assignedOperators[i];
            if (task.responses[operator].isValid) {
                bytes32 responseHash = task.responses[operator].responseHash;
                
                // Find if this hash already exists
                bool hashExists = false;
                for (uint256 j = 0; j < uniqueHashes; j++) {
                    if (responseHashes[j] == responseHash) {
                        hashCounts[j]++;
                        hashExists = true;
                        break;
                    }
                }
                
                if (!hashExists) {
                    responseHashes[uniqueHashes] = responseHash;
                    hashCounts[uniqueHashes] = 1;
                    uniqueHashes++;
                }
            }
        }
        
        // Find the most common response hash
        bytes32 mostCommonHash = bytes32(0);
        uint256 maxCount = 0;
        
        for (uint256 i = 0; i < uniqueHashes; i++) {
            if (hashCounts[i] > maxCount) {
                maxCount = hashCounts[i];
                mostCommonHash = responseHashes[i];
            }
        }
        
        consensusResult.agreedOperators = maxCount;
        consensusResult.finalHash = mostCommonHash;
        
        // Check if consensus threshold is met
        consensusResult.consensusReached = maxCount >= task.consensusThreshold;
        
        return consensusResult;
    }

    /// @notice Internal function to check consensus and emit events
    /// @param task The consensus task
    function _checkConsensus(ConsensusTask storage task) internal {
        ConsensusResult memory result = checkConsensus(task);
        
        if (result.consensusReached) {
            emit ConsensusReached(task.taskId, result.finalHash, result.agreedOperators);
            task.completed = true;
        } else if (block.timestamp > task.deadline) {
            emit ConsensusFailed(task.taskId, "Deadline exceeded");
        }
    }

    /// @notice Verify operator signature
    /// @param operator The operator address
    /// @param messageHash The message hash
    /// @param signature The signature
    /// @return isValid Whether the signature is valid
    function _verifySignature(
        address operator,
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (bool isValid) {
        // In production, this would use proper ECDSA signature verification
        // For now, return true as placeholder
        return true;
    }

    /// @notice Calculate consensus threshold based on operator count
    /// @param operatorCount The number of operators
    /// @return threshold The consensus threshold
    function calculateConsensusThreshold(
        uint256 operatorCount
    ) internal pure returns (uint256 threshold) {
        // Simple 2/3 majority rule
        threshold = (operatorCount * 2) / 3;
        
        // Ensure minimum threshold
        if (threshold < 2) {
            threshold = 2;
        }
    }

    /// @notice Validate consensus configuration
    /// @param config The consensus configuration
    /// @return isValid Whether the configuration is valid
    function validateConsensusConfig(
        ConsensusConfig memory config
    ) internal pure returns (bool isValid) {
        return (
            config.minOperators > 0 &&
            config.consensusThreshold > 0 &&
            config.consensusThreshold <= config.minOperators &&
            config.responseTimeout > 0 &&
            config.maxRetries > 0
        );
    }

    /// @notice Get operator response for a task
    /// @param task The consensus task
    /// @param operator The operator address
    /// @return response The operator response
    function getOperatorResponse(
        ConsensusTask storage task,
        address operator
    ) internal view returns (OperatorResponse memory response) {
        return task.responses[operator];
    }

    /// @notice Check if operator has responded to a task
    /// @param task The consensus task
    /// @param operator The operator address
    /// @return hasResponded Whether the operator has responded
    function hasOperatorResponded(
        ConsensusTask storage task,
        address operator
    ) internal view returns (bool hasResponded) {
        return task.responses[operator].isValid;
    }

    /// @notice Get task completion status
    /// @param task The consensus task
    /// @return isCompleted Whether the task is completed
    function isTaskCompleted(
        ConsensusTask storage task
    ) internal view returns (bool isCompleted) {
        return task.completed || block.timestamp > task.deadline;
    }
} 