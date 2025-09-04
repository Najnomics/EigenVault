// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/core/ZKProofLib.sol";

/// @title ZKProofIntegrationTest
/// @notice Comprehensive test suite for ZK proof generation and verification
contract ZKProofIntegrationTest is Test {
    using ZKProofLib for *;

    address[] operators;
    bytes32 constant TEST_POOL_HASH = keccak256("test_pool");
    bytes32 constant TEST_ORDER_ID = keccak256("test_order");
    
    function setUp() public {
        operators.push(address(0x1));
        operators.push(address(0x2));
    }

    /// @notice Test matching proof generation and verification
    function testMatchingProofGenerationAndVerification() public view {
        // Generate a matching proof
        ZKProofLib.MatchingProof memory proof = ZKProofLib.generateMatchingProof(
            TEST_ORDER_ID,
            TEST_POOL_HASH,
            2000e18, // execution price
            1e18,    // total volume
            operators
        );
        
        // Verify the proof structure
        assertEq(proof.poolHash, TEST_POOL_HASH);
        assertEq(proof.orderCount, 1);
        assertEq(proof.operators.length, 2);
        assertTrue(proof.proof.length > 0);
        assertTrue(proof.verificationKey.length > 0);
        assertEq(proof.publicInputs.length, 3);
        
        // Verify the proof is valid
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(proof, TEST_POOL_HASH);
            
        assertTrue(result.isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
        assertEq(result.matchHash, TEST_ORDER_ID);
        assertEq(result.executionPrice, 2000e18);
        assertEq(result.totalVolume, 1e18);
    }

    /// @notice Test privacy proof generation and verification
    function testPrivacyProofGenerationAndVerification() public view {
        // Create test commitments
        bytes32[] memory commitments = new bytes32[](2);
        commitments[0] = keccak256("commitment1");
        commitments[1] = keccak256("commitment2");
        
        bytes32 validityHash = keccak256("validity_result");
        
        // Generate privacy proof
        ZKProofLib.PrivacyProof memory proof = ZKProofLib.generatePrivacyProof(
            commitments,
            validityHash,
            operators[0]
        );
        
        // Verify proof structure
        assertEq(proof.commitments.length, 2);
        assertEq(proof.validityHash, validityHash);
        assertEq(proof.operator, operators[0]);
        assertTrue(proof.proof.length > 0);
        
        // Verify the proof is valid
        (bool isValid, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyPrivacyProof(proof, commitments);
            
        assertTrue(isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
    }

    /// @notice Test batch proof verification
    function testBatchProofVerification() public view {
        // Create multiple individual proofs
        ZKProofLib.MatchingProof[] memory individualProofs = new ZKProofLib.MatchingProof[](2);
        
        individualProofs[0] = ZKProofLib.generateMatchingProof(
            keccak256("order1"),
            TEST_POOL_HASH,
            1000e18,
            0.5e18,
            operators
        );
        
        individualProofs[1] = ZKProofLib.generateMatchingProof(
            keccak256("order2"), 
            TEST_POOL_HASH,
            1500e18,
            0.3e18,
            operators
        );
        
        // Create batch proof
        bytes memory aggregatedProof = abi.encodePacked(
            individualProofs[0].proof,
            individualProofs[1].proof,
            uint256(0x1111222233334444) // Aggregation magic constant
        );
        
        ZKProofLib.BatchProof memory batchProof = ZKProofLib.BatchProof({
            batchId: keccak256("batch1"),
            individualProofs: individualProofs,
            aggregatedProof: aggregatedProof,
            batchHash: keccak256(abi.encodePacked(individualProofs[0].proofId, individualProofs[1].proofId)),
            totalMatches: 2,
            operators: operators
        });
        
        // Verify batch proof
        (bool isValid, ZKProofLib.ProofError error) = ZKProofLib.verifyBatchProof(batchProof);
        
        assertTrue(isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.None));
    }

    /// @notice Test proof validation edge cases
    function testProofValidationEdgeCases() public view {
        // Test with empty proof
        ZKProofLib.MatchingProof memory emptyProof;
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(emptyProof, TEST_POOL_HASH);
            
        assertFalse(result.isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.InvalidProof));
        
        // Test with expired proof
        ZKProofLib.MatchingProof memory validProof = ZKProofLib.generateMatchingProof(
            TEST_ORDER_ID,
            TEST_POOL_HASH,
            2000e18,
            1e18,
            operators
        );
        
        // Simulate expired proof by manipulating timestamp
        validProof.timestamp = block.timestamp - 25 hours;
        
        (result, error) = ZKProofLib.verifyMatchingProof(validProof, TEST_POOL_HASH);
        assertFalse(result.isValid);
        assertEq(uint256(error), uint256(ZKProofLib.ProofError.ProofExpired));
    }

    /// @notice Test proof ID generation
    function testProofIdGeneration() public view {
        bytes memory proofData = "test_proof_data";
        uint256 timestamp = block.timestamp;
        address operator = operators[0];
        
        bytes32 proofId1 = ZKProofLib.generateProofId(proofData, timestamp, operator);
        bytes32 proofId2 = ZKProofLib.generateProofId(proofData, timestamp, operator);
        
        // Same inputs should generate same ID
        assertEq(proofId1, proofId2);
        
        // Different inputs should generate different ID
        bytes32 proofId3 = ZKProofLib.generateProofId(proofData, timestamp + 1, operator);
        assertTrue(proofId1 != proofId3);
    }

    /// @notice Test commitment validation in privacy proofs
    function testPrivacyProofCommitmentValidation() public view {
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256("test_commitment");
        
        bytes32[] memory wrongCommitments = new bytes32[](1);
        wrongCommitments[0] = keccak256("wrong_commitment");
        
        ZKProofLib.PrivacyProof memory proof = ZKProofLib.generatePrivacyProof(
            commitments,
            keccak256("validity"),
            operators[0]
        );
        
        // Valid commitments should pass
        (bool isValid,) = ZKProofLib.verifyPrivacyProof(proof, commitments);
        assertTrue(isValid);
        
        // Wrong commitments should fail
        (isValid,) = ZKProofLib.verifyPrivacyProof(proof, wrongCommitments);
        assertFalse(isValid);
    }

    /// @notice Performance test for proof generation
    function testProofGenerationPerformance() public {
        uint256 gasStart = gasleft();
        
        ZKProofLib.generateMatchingProof(
            TEST_ORDER_ID,
            TEST_POOL_HASH,
            2000e18,
            1e18,
            operators
        );
        
        uint256 gasUsed = gasStart - gasleft();
        
        // Proof generation should be reasonably efficient
        assertTrue(gasUsed < 200000, "Proof generation uses too much gas");
        
        emit log_named_uint("Proof generation gas cost", gasUsed);
    }
} 