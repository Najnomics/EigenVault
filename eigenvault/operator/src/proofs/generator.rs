use anyhow::Result;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use tracing::{debug, info, warn};
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use rand::rngs::OsRng;

use crate::config::ProofConfig;
use crate::matching::{OrderMatch, DecryptedOrder};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchingProof {
    pub proof_id: String,
    pub order_matches: Vec<String>, // Order match IDs
    pub proof_data: Vec<u8>,
    pub public_inputs: Vec<u8>,
    pub verification_key: Vec<u8>,
    pub timestamp: u64,
    pub operator_signature: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchProof {
    pub batch_id: String,
    pub individual_proofs: Vec<MatchingProof>,
    pub aggregated_proof: Vec<u8>,
    pub batch_public_inputs: Vec<u8>,
    pub operator_signatures: Vec<Vec<u8>>,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofCircuit {
    pub circuit_id: String,
    pub circuit_hash: Vec<u8>,
    pub verification_key: Vec<u8>,
    pub proving_key: Vec<u8>,
}

pub struct ZKProver {
    config: ProofConfig,
    circuits: std::collections::HashMap<String, ProofCircuit>,
    proving_keys: std::collections::HashMap<String, Vec<u8>>,
    signing_key: SigningKey,
}

impl ZKProver {
    pub async fn new(config: ProofConfig) -> Result<Self> {
        info!("Initializing ZK prover with config: {:?}", config);
        
        // Generate a new signing key for this operator
        let signing_key = SigningKey::from_bytes(&rand::random::<[u8; 32]>());
        
        let mut prover = Self {
            config,
            circuits: std::collections::HashMap::new(),
            proving_keys: std::collections::HashMap::new(),
            signing_key,
        };
        
        // Load default circuits
        prover.load_default_circuits().await?;
        
        Ok(prover)
    }

    /// Load default ZK circuits for order matching
    async fn load_default_circuits(&mut self) -> Result<()> {
        info!("Loading default ZK circuits");
        
        // Order matching circuit
        let order_matching_circuit = ProofCircuit {
            circuit_id: "order_matching_v1".to_string(),
            circuit_hash: self.hash_data(b"order_matching_circuit_v1")?,
            verification_key: self.generate_verification_key("order_matching")?,
            proving_key: self.generate_proving_key("order_matching")?,
        };
        
        self.circuits.insert(
            "order_matching".to_string(), 
            order_matching_circuit.clone()
        );
        
        self.proving_keys.insert(
            "order_matching".to_string(),
            order_matching_circuit.proving_key.clone()
        );

        // Privacy preservation circuit
        let privacy_circuit = ProofCircuit {
            circuit_id: "privacy_proof_v1".to_string(),
            circuit_hash: self.hash_data(b"privacy_proof_circuit_v1")?,
            verification_key: self.generate_verification_key("privacy_proof")?,
            proving_key: self.generate_proving_key("privacy_proof")?,
        };
        
        self.circuits.insert(
            "privacy_proof".to_string(), privacy_circuit.clone()
        );
        
        self.proving_keys.insert(
            "privacy_proof".to_string(),
            privacy_circuit.proving_key.clone()
        );

        info!("Loaded {} ZK circuits", self.circuits.len());
        Ok(())
    }

    /// Generate a proof for order matching
    pub async fn generate_matching_proof(
        &self,
        order_matches: &[OrderMatch],
        pool_key: &str,
    ) -> Result<MatchingProof> {
        info!("Generating matching proof for {} matches in pool {}", order_matches.len(), pool_key);
        
        // Create proof ID
        let proof_id = uuid::Uuid::new_v4().to_string();
        
        // Generate actual proof data using the order matching circuit
        let proof_data = self.generate_order_matching_proof(order_matches, pool_key).await?;
        
        // Generate public inputs
        let public_inputs = self.generate_public_inputs(order_matches, pool_key)?;
        
        // Get verification key
        let verification_key = self.circuits.get("order_matching")
            .ok_or_else(|| anyhow::anyhow!("Order matching circuit not found"))?
            .verification_key.clone();
        
        // Sign the proof
        let operator_signature = self.sign_proof(&proof_data, &public_inputs)?;
        
        let proof = MatchingProof {
            proof_id: proof_id.clone(),
            order_matches: order_matches.iter().map(|m| m.match_id.clone()).collect(),
            proof_data,
            public_inputs,
            verification_key,
            timestamp: chrono::Utc::now().timestamp() as u64,
            operator_signature,
        };
        
        info!("Generated proof {} with {} bytes", proof_id, proof.proof_data.len());
        Ok(proof)
    }

    /// Generate batch proof for multiple order matches
    pub async fn generate_batch_proof(&self, order_matches: &[OrderMatch]) -> Result<MatchingProof> {
        info!("Generating batch proof for {} order matches", order_matches.len());
        
        // Use the same logic as generate_matching_proof but for a batch
        self.generate_matching_proof(order_matches, "batch_pool").await
    }

    /// Generate actual order matching proof data
    async fn generate_order_matching_proof(
        &self,
        order_matches: &[OrderMatch],
        pool_key: &str,
    ) -> Result<Vec<u8>> {
        // In a real implementation, this would use a ZK-SNARK proving system
        // For now, we'll create a structured proof that can be verified
        
        let mut proof_data = Vec::new();
        
        // Add circuit identifier
        proof_data.extend_from_slice(b"ORDER_MATCHING_V1");
        
        // Add pool key hash
        let pool_key_hash = self.hash_data(pool_key.as_bytes())?;
        proof_data.extend_from_slice(&pool_key_hash);
        
        // Add match count
        proof_data.extend_from_slice(&(order_matches.len() as u32).to_le_bytes());
        
        // Add each match's proof data
        for match_data in order_matches {
            let match_proof = self.generate_single_match_proof(match_data)?;
            proof_data.extend_from_slice(&match_proof);
        }
        
        // Add timestamp
        let timestamp = chrono::Utc::now().timestamp() as u64;
        proof_data.extend_from_slice(&timestamp.to_le_bytes());
        
        // Add proof hash for verification
        let proof_hash = self.hash_data(&proof_data)?;
        proof_data.extend_from_slice(&proof_hash);
        
        Ok(proof_data)
    }

    /// Generate proof for a single order match
    fn generate_single_match_proof(&self, order_match: &OrderMatch) -> Result<Vec<u8>> {
        let mut proof = Vec::new();
        
        // Add match ID hash
        let match_id_hash = self.hash_data(order_match.match_id.as_bytes())?;
        proof.extend_from_slice(&match_id_hash);
        
        // Add price validation (buy price >= sell price)
        let price_valid = order_match.matched_price >= 
            order_match.buy_order.price.min(order_match.sell_order.price);
        proof.extend_from_slice(&[if price_valid { 1 } else { 0 }]);
        
        // Add amount validation (matched amount <= min(buy, sell))
        let max_amount = order_match.buy_order.amount.min(order_match.sell_order.amount);
        let amount_valid = order_match.matched_amount <= max_amount;
        proof.extend_from_slice(&[if amount_valid { 1 } else { 0 }]);
        
        // Add type validation (buy = 0, sell = 1)
        let buy_type_valid = order_match.buy_order.order_type == crate::matching::OrderType::Buy;
        let sell_type_valid = order_match.sell_order.order_type == crate::matching::OrderType::Sell;
        proof.extend_from_slice(&[if buy_type_valid && sell_type_valid { 1 } else { 0 }]);
        
        // Add deadline validation
        let now = chrono::Utc::now().timestamp() as u64;
        let deadline_valid = order_match.buy_order.deadline > now && 
                           order_match.sell_order.deadline > now;
        proof.extend_from_slice(&[if deadline_valid { 1 } else { 0 }]);
        
        Ok(proof)
    }

    /// Generate public inputs for the proof
    fn generate_public_inputs(
        &self,
        order_matches: &[OrderMatch],
        pool_key: &str,
    ) -> Result<Vec<u8>> {
        let mut inputs = Vec::new();
        
        // Add pool key
        inputs.extend_from_slice(pool_key.as_bytes());
        
        // Add match count
        inputs.extend_from_slice(&(order_matches.len() as u32).to_le_bytes());
        
        // Add total volume
        let total_volume: f64 = order_matches.iter()
            .map(|m| m.matched_amount)
            .sum();
        inputs.extend_from_slice(&total_volume.to_le_bytes());
        
        // Add average price
        let avg_price: f64 = if order_matches.is_empty() { 0.0 } else {
            order_matches.iter()
                .map(|m| m.matched_price * m.matched_amount)
                .sum::<f64>() / total_volume
        };
        inputs.extend_from_slice(&avg_price.to_le_bytes());
        
        Ok(inputs)
    }

    /// Sign a proof with the operator's private key
    fn sign_proof(&self, proof_data: &[u8], public_inputs: &[u8]) -> Result<Vec<u8>> {
        let message = [proof_data, public_inputs].concat();
        let signature = self.signing_key.sign(&message);
        Ok(signature.to_bytes().to_vec())
    }

    /// Generate verification key for a circuit
    fn generate_verification_key(&self, circuit_name: &str) -> Result<Vec<u8>> {
        // In a real implementation, this would load from a trusted setup
        // For now, we'll generate a deterministic key based on the circuit name
        let mut key = Vec::new();
        key.extend_from_slice(circuit_name.as_bytes());
        key.extend_from_slice(&self.hash_data(circuit_name.as_bytes())?);
        Ok(key)
    }

    /// Generate proving key for a circuit
    fn generate_proving_key(&self, circuit_name: &str) -> Result<Vec<u8>> {
        // In a real implementation, this would load from a trusted setup
        // For now, we'll generate a deterministic key based on the circuit name
        let mut key = Vec::new();
        key.extend_from_slice(circuit_name.as_bytes());
        key.extend_from_slice(b"_PROVING");
        key.extend_from_slice(&self.hash_data(circuit_name.as_bytes())?);
        Ok(key)
    }

    /// Hash data using SHA-256
    fn hash_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(data);
        Ok(hasher.finalize().to_vec())
    }

    /// Get the operator's public key
    pub fn get_public_key(&self) -> VerifyingKey {
        self.signing_key.verifying_key()
    }

    /// Verify a proof signature
    pub fn verify_proof_signature(
        &self,
        proof_data: &[u8],
        public_inputs: &[u8],
        signature: &[u8],
        public_key: &VerifyingKey,
    ) -> Result<bool> {
        let message = [proof_data, public_inputs].concat();
        if signature.len() != 64 {
            return Err(anyhow::anyhow!("Invalid signature length"));
        }
        let signature_bytes: [u8; 64] = signature.try_into()
            .map_err(|_| anyhow::anyhow!("Failed to convert signature to array"))?;
        let signature = Signature::from_bytes(&signature_bytes);
        
        match public_key.verify(&message, &signature) {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ProofConfig;

    #[tokio::test]
    async fn test_zk_prover_creation() {
        let config = ProofConfig::default();
        let prover = ZKProver::new(config).await;
        assert!(prover.is_ok());
    }

    #[tokio::test]
    async fn test_list_circuits() {
        let config = ProofConfig::default();
        let prover = ZKProver::new(config).await.unwrap();
        
        let circuits = prover.list_circuits();
        assert!(circuits.contains(&"order_matching".to_string()));
        assert!(circuits.contains(&"privacy_proof".to_string()));
    }
}