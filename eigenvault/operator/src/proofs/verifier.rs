use anyhow::Result;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use tracing::{debug, info, warn};

use super::{MatchingProof, BatchProof};
use crate::config::ProofConfig;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VerificationResult {
    Valid,
    Invalid { reason: String },
    Pending,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationReport {
    pub proof_id: String,
    pub result: VerificationResult,
    pub verified_at: u64,
    pub verifier_id: String,
    pub gas_cost_estimate: Option<u64>,
}

pub struct ProofVerifier {
    config: ProofConfig,
    verification_keys: std::collections::HashMap<String, Vec<u8>>,
    trusted_circuits: std::collections::HashMap<String, Vec<u8>>,
}

impl ProofVerifier {
    pub async fn new(config: ProofConfig) -> Result<Self> {
        info!("Initializing proof verifier");
        
        let mut verifier = Self {
            config,
            verification_keys: std::collections::HashMap::new(),
            trusted_circuits: std::collections::HashMap::new(),
        };
        
        // Load trusted verification keys
        verifier.load_verification_keys().await?;
        
        Ok(verifier)
    }

    /// Load trusted verification keys for circuits
    async fn load_verification_keys(&mut self) -> Result<()> {
        info!("Loading trusted verification keys");
        
        // Order matching circuit verification key
        self.verification_keys.insert(
            "order_matching".to_string(),
            vec![1, 2, 3, 4], // Mock verification key
        );
        
        // Privacy proof circuit verification key
        self.verification_keys.insert(
            "privacy_proof".to_string(),
            vec![9, 10, 11, 12], // Mock verification key
        );
        
        // Load trusted circuit hashes
        self.trusted_circuits.insert(
            "order_matching".to_string(),
            self.hash_data(b"order_matching_circuit_v1")?,
        );
        
        self.trusted_circuits.insert(
            "privacy_proof".to_string(),
            self.hash_data(b"privacy_proof_circuit_v1")?,
        );
        
        info!("Loaded {} verification keys", self.verification_keys.len());
        Ok(())
    }

    /// Verify a single matching proof
    pub async fn verify_matching_proof(&self, proof: &MatchingProof) -> Result<VerificationReport> {
        info!("Verifying matching proof: {}", proof.proof_id);
        
        let start_time = std::time::Instant::now();
        let mut verification_steps = Vec::new();
        
        // Step 1: Verify proof structure
        verification_steps.push(self.verify_proof_structure(proof).await?);
        
        // Step 2: Verify operator signature
        verification_steps.push(self.verify_operator_signature(proof).await?);
        
        // Step 3: Verify ZK proof validity
        verification_steps.push(self.verify_zk_proof(proof).await?);
        
        // Step 4: Verify public inputs consistency
        verification_steps.push(self.verify_public_inputs(proof).await?);
        
        // Step 5: Verify timestamp validity
        verification_steps.push(self.verify_timestamp(proof.timestamp).await?);
        
        // Aggregate results
        let all_valid = verification_steps.iter().all(|step| matches!(step, VerificationResult::Valid));
        
        let result = if all_valid {
            VerificationResult::Valid
        } else {
            let failed_steps: Vec<String> = verification_steps
                .into_iter()
                .filter_map(|step| match step {
                    VerificationResult::Invalid { reason } => Some(reason),
                    _ => None,
                })
                .collect();
            
            VerificationResult::Invalid {
                reason: format!("Verification failed: {}", failed_steps.join(", "))
            }
        };
        
        let verification_time = start_time.elapsed();
        let gas_cost_estimate = self.estimate_verification_gas_cost(proof).await?;
        
        let report = VerificationReport {
            proof_id: proof.proof_id.clone(),
            result,
            verified_at: chrono::Utc::now().timestamp() as u64,
            verifier_id: "eigenvault_verifier_v1".to_string(),
            gas_cost_estimate: Some(gas_cost_estimate),
        };
        
        info!("Verification completed in {:?}: {:?}", verification_time, report.result);
        Ok(report)
    }

    /// Verify a batch proof
    pub async fn verify_batch_proof(&self, batch_proof: &BatchProof) -> Result<VerificationReport> {
        info!("Verifying batch proof: {}", batch_proof.batch_id);
        
        let start_time = std::time::Instant::now();
        let mut all_valid = true;
        let mut error_messages = Vec::new();
        
        // Verify individual proofs
        for (i, individual_proof) in batch_proof.individual_proofs.iter().enumerate() {
            match self.verify_matching_proof(individual_proof).await {
                Ok(report) => {
                    if !matches!(report.result, VerificationResult::Valid) {
                        all_valid = false;
                        error_messages.push(format!("Individual proof {} failed: {:?}", i, report.result));
                    }
                }
                Err(e) => {
                    all_valid = false;
                    error_messages.push(format!("Individual proof {} error: {}", i, e));
                }
            }
        }
        
        // Verify batch aggregation
        if all_valid {
            match self.verify_batch_aggregation(batch_proof).await {
                Ok(VerificationResult::Valid) => {},
                Ok(invalid_result) => {
                    all_valid = false;
                    error_messages.push(format!("Batch aggregation failed: {:?}", invalid_result));
                }
                Err(e) => {
                    all_valid = false;
                    error_messages.push(format!("Batch aggregation error: {}", e));
                }
            }
        }
        
        // Verify batch signatures
        if all_valid {
            match self.verify_batch_signatures(batch_proof).await {
                Ok(VerificationResult::Valid) => {},
                Ok(invalid_result) => {
                    all_valid = false;
                    error_messages.push(format!("Batch signatures failed: {:?}", invalid_result));
                }
                Err(e) => {
                    all_valid = false;
                    error_messages.push(format!("Batch signatures error: {}", e));
                }
            }
        }
        
        let result = if all_valid {
            VerificationResult::Valid
        } else {
            VerificationResult::Invalid {
                reason: error_messages.join("; ")
            }
        };
        
        let verification_time = start_time.elapsed();
        let gas_cost_estimate = self.estimate_batch_verification_gas_cost(batch_proof).await?;
        
        let report = VerificationReport {
            proof_id: batch_proof.batch_id.clone(),
            result,
            verified_at: chrono::Utc::now().timestamp() as u64,
            verifier_id: "eigenvault_batch_verifier_v1".to_string(),
            gas_cost_estimate: Some(gas_cost_estimate),
        };
        
        info!("Batch verification completed in {:?}: {:?}", verification_time, report.result);
        Ok(report)
    }

    /// Verify proof structure and format
    async fn verify_proof_structure(&self, proof: &MatchingProof) -> Result<VerificationResult> {
        debug!("Verifying proof structure for: {}", proof.proof_id);
        
        // Check required fields
        if proof.proof_id.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty proof ID".to_string()
            });
        }
        
        if proof.proof_data.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty proof data".to_string()
            });
        }
        
        if proof.verification_key.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty verification key".to_string()
            });
        }
        
        // Check proof data length (should be reasonable for ZK proof)
        if proof.proof_data.len() < 100 {
            return Ok(VerificationResult::Invalid {
                reason: "Proof data too short".to_string()
            });
        }
        
        if proof.proof_data.len() > 100_000 {
            return Ok(VerificationResult::Invalid {
                reason: "Proof data too long".to_string()
            });
        }
        
        // Check timestamp is reasonable
        let current_time = chrono::Utc::now().timestamp() as u64;
        if proof.timestamp > current_time + 300 { // Allow 5 minutes clock skew
            return Ok(VerificationResult::Invalid {
                reason: "Proof timestamp in future".to_string()
            });
        }
        
        if proof.timestamp < current_time - 86400 { // Reject proofs older than 24 hours
            return Ok(VerificationResult::Invalid {
                reason: "Proof timestamp too old".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify operator signature on proof
    async fn verify_operator_signature(&self, proof: &MatchingProof) -> Result<VerificationResult> {
        debug!("Verifying operator signature for: {}", proof.proof_id);
        
        if proof.operator_signature.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty operator signature".to_string()
            });
        }
        
        // Verify signature (simplified - in production use actual cryptographic verification)
        let expected_signature = self.compute_expected_signature(&proof.proof_data, proof.timestamp).await?;
        
        if proof.operator_signature != expected_signature {
            return Ok(VerificationResult::Invalid {
                reason: "Invalid operator signature".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify the actual ZK proof
    async fn verify_zk_proof(&self, proof: &MatchingProof) -> Result<VerificationResult> {
        debug!("Verifying ZK proof for: {}", proof.proof_id);
        
        // Extract circuit type from proof data
        let circuit_type = self.extract_circuit_type(&proof.proof_data)?;
        
        // Get verification key for this circuit
        let verification_key = self.verification_keys.get(&circuit_type)
            .ok_or_else(|| anyhow::anyhow!("Unknown circuit type: {}", circuit_type))?;
        
        // Verify the verification key matches
        if &proof.verification_key != verification_key {
            return Ok(VerificationResult::Invalid {
                reason: "Verification key mismatch".to_string()
            });
        }
        
        // Verify ZK proof (simplified mock implementation)
        // In production, this would use actual ZK verification libraries
        let is_valid = self.mock_zk_verify(&proof.proof_data, &proof.public_inputs, verification_key).await?;
        
        if !is_valid {
            return Ok(VerificationResult::Invalid {
                reason: "ZK proof verification failed".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify public inputs consistency
    async fn verify_public_inputs(&self, proof: &MatchingProof) -> Result<VerificationResult> {
        debug!("Verifying public inputs for: {}", proof.proof_id);
        
        if proof.public_inputs.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty public inputs".to_string()
            });
        }
        
        // Verify public inputs format and constraints
        // This would depend on the specific circuit being used
        let inputs_valid = self.validate_public_inputs_format(&proof.public_inputs).await?;
        
        if !inputs_valid {
            return Ok(VerificationResult::Invalid {
                reason: "Invalid public inputs format".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify timestamp validity
    async fn verify_timestamp(&self, timestamp: u64) -> Result<VerificationResult> {
        let current_time = chrono::Utc::now().timestamp() as u64;
        
        // Allow reasonable time window
        if timestamp > current_time + 300 { // 5 minutes future
            return Ok(VerificationResult::Invalid {
                reason: "Timestamp too far in future".to_string()
            });
        }
        
        if timestamp < current_time - 3600 { // 1 hour past
            return Ok(VerificationResult::Invalid {
                reason: "Timestamp too old".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify batch proof aggregation
    async fn verify_batch_aggregation(&self, batch_proof: &BatchProof) -> Result<VerificationResult> {
        debug!("Verifying batch aggregation for: {}", batch_proof.batch_id);
        
        if batch_proof.individual_proofs.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty individual proofs".to_string()
            });
        }
        
        if batch_proof.aggregated_proof.is_empty() {
            return Ok(VerificationResult::Invalid {
                reason: "Empty aggregated proof".to_string()
            });
        }
        
        // Verify aggregation is correct (simplified)
        let expected_aggregation = self.compute_expected_aggregation(&batch_proof.individual_proofs).await?;
        
        // In production, this would verify the actual cryptographic aggregation
        if batch_proof.aggregated_proof.len() != expected_aggregation.len() {
            return Ok(VerificationResult::Invalid {
                reason: "Aggregated proof length mismatch".to_string()
            });
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Verify batch signatures
    async fn verify_batch_signatures(&self, batch_proof: &BatchProof) -> Result<VerificationResult> {
        debug!("Verifying batch signatures for: {}", batch_proof.batch_id);
        
        if batch_proof.operator_signatures.len() != batch_proof.individual_proofs.len() {
            return Ok(VerificationResult::Invalid {
                reason: "Signature count mismatch".to_string()
            });
        }
        
        // Verify each signature corresponds to its proof
        for (i, signature) in batch_proof.operator_signatures.iter().enumerate() {
            let proof = &batch_proof.individual_proofs[i];
            if signature != &proof.operator_signature {
                return Ok(VerificationResult::Invalid {
                    reason: format!("Signature mismatch for proof {}", i)
                });
            }
        }
        
        Ok(VerificationResult::Valid)
    }

    /// Mock ZK proof verification (replace with actual ZK library in production)
    async fn mock_zk_verify(&self, proof_data: &[u8], public_inputs: &[u8], verification_key: &[u8]) -> Result<bool> {
        // Simplified verification logic
        // In production, this would use libraries like arkworks, bellman, etc.
        
        // Check proof has expected structure
        if proof_data.len() < 1024 { // Expect at least 1KB for ZK proof
            return Ok(false);
        }
        
        // Check public inputs are reasonable
        if public_inputs.is_empty() {
            return Ok(false);
        }
        
        // Check verification key is known
        let is_known_key = self.verification_keys.values().any(|key| key == verification_key);
        if !is_known_key {
            return Ok(false);
        }
        
        // Mock verification passes
        Ok(true)
    }

    /// Extract circuit type from proof data
    fn extract_circuit_type(&self, proof_data: &[u8]) -> Result<String> {
        // Extract circuit type from proof data (simplified)
        if proof_data.len() < 16 {
            return Err(anyhow::anyhow!("Proof data too short to extract circuit type"));
        }
        
        // Check for known circuit prefixes
        let proof_str = String::from_utf8_lossy(&proof_data[..16]);
        
        if proof_str.starts_with("order_matching") {
            Ok("order_matching".to_string())
        } else if proof_str.starts_with("privacy_proof") {
            Ok("privacy_proof".to_string())
        } else {
            Err(anyhow::anyhow!("Unknown circuit type in proof"))
        }
    }

    /// Validate public inputs format
    async fn validate_public_inputs_format(&self, public_inputs: &[u8]) -> Result<bool> {
        // Check inputs are not empty
        if public_inputs.is_empty() {
            return Ok(false);
        }
        
        // Check inputs have reasonable length
        if public_inputs.len() > 10000 {
            return Ok(false);
        }
        
        // Additional format validation would go here
        Ok(true)
    }

    /// Compute expected signature for verification
    async fn compute_expected_signature(&self, proof_data: &[u8], timestamp: u64) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(proof_data);
        hasher.update(b"operator_private_key"); // Mock private key
        hasher.update(&timestamp.to_le_bytes());
        Ok(hasher.finalize().to_vec())
    }

    /// Compute expected aggregation for batch verification
    async fn compute_expected_aggregation(&self, individual_proofs: &[MatchingProof]) -> Result<Vec<u8>> {
        let mut aggregated = Vec::new();
        
        // Number of proofs
        aggregated.extend((individual_proofs.len() as u64).to_le_bytes());
        
        // Hash of all proofs
        for proof in individual_proofs {
            let proof_hash = self.hash_data(&proof.proof_data)?;
            aggregated.extend(proof_hash);
        }
        
        // Mock aggregated components
        aggregated.extend(vec![0x50; 512]);
        
        Ok(aggregated)
    }

    /// Estimate gas cost for on-chain verification
    async fn estimate_verification_gas_cost(&self, proof: &MatchingProof) -> Result<u64> {
        // Estimate based on proof complexity
        let base_cost = 50_000u64; // Base verification cost
        let data_cost = (proof.proof_data.len() as u64) * 16; // Gas per byte
        let input_cost = (proof.public_inputs.len() as u64) * 16;
        
        Ok(base_cost + data_cost + input_cost)
    }

    /// Estimate gas cost for batch verification
    async fn estimate_batch_verification_gas_cost(&self, batch_proof: &BatchProof) -> Result<u64> {
        let individual_cost = 30_000u64 * batch_proof.individual_proofs.len() as u64;
        let aggregation_cost = 100_000u64; // Fixed cost for aggregation verification
        let batch_data_cost = (batch_proof.aggregated_proof.len() as u64) * 16;
        
        Ok(individual_cost + aggregation_cost + batch_data_cost)
    }

    /// Hash data helper
    fn hash_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(data);
        Ok(hasher.finalize().to_vec())
    }

    /// Health check for proof verifier
    pub async fn health_check(&self) -> Result<()> {
        // Verify we have required verification keys
        if self.verification_keys.is_empty() {
            return Err(anyhow::anyhow!("No verification keys loaded"));
        }
        
        // Test with mock proof
        let mock_proof = MatchingProof {
            proof_id: "test_proof".to_string(),
            order_matches: vec!["test_match".to_string()],
            proof_data: vec![0u8; 1024],
            public_inputs: vec![1, 2, 3, 4],
            verification_key: vec![1, 2, 3, 4],
            timestamp: chrono::Utc::now().timestamp() as u64,
            operator_signature: vec![5, 6, 7, 8],
        };
        
        // This should fail verification (as expected for mock data)
        let _report = self.verify_matching_proof(&mock_proof).await?;
        
        debug!("Proof verifier health check passed");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ProofConfig;

    #[tokio::test]
    async fn test_proof_verifier_creation() {
        let config = ProofConfig::default();
        let verifier = ProofVerifier::new(config).await;
        assert!(verifier.is_ok());
    }

    #[tokio::test]
    async fn test_verification_keys_loaded() {
        let config = ProofConfig::default();
        let verifier = ProofVerifier::new(config).await.unwrap();
        
        assert!(verifier.verification_keys.contains_key("order_matching"));
        assert!(verifier.verification_keys.contains_key("privacy_proof"));
    }
}