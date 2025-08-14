use anyhow::Result;
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use tracing::{debug, info, warn};

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
}

impl ZKProver {
    pub async fn new(config: ProofConfig) -> Result<Self> {
        info!("Initializing ZK prover with config: {:?}", config);
        
        let mut prover = Self {
            config,
            circuits: std::collections::HashMap::new(),
            proving_keys: std::collections::HashMap::new(),
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
            verification_key: vec![1, 2, 3, 4], // Mock verification key
            proving_key: vec![5, 6, 7, 8], // Mock proving key
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
            verification_key: vec![9, 10, 11, 12], // Mock verification key
            proving_key: vec![13, 14, 15, 16], // Mock proving key
        };
        
        self.circuits.insert(
            "privacy_proof".to_string(),
            privacy_circuit.clone()
        );
        
        self.proving_keys.insert(
            "privacy_proof".to_string(),
            privacy_circuit.proving_key.clone()
        );

        info!("Loaded {} ZK circuits", self.circuits.len());
        Ok(())
    }

    /// Generate proof for a single order match
    pub async fn generate_matching_proof(&self, order_match: &OrderMatch) -> Result<MatchingProof> {
        info!("Generating matching proof for match: {}", order_match.match_id);
        
        let circuit = self.circuits.get("order_matching")
            .ok_or_else(|| anyhow::anyhow!("Order matching circuit not found"))?;
        
        // Prepare inputs for the circuit
        let mut inputs = Vec::new();
        
        // Add order match data to inputs
        inputs.extend(order_match.match_id.as_bytes());
        inputs.extend(order_match.buy_order.id.as_bytes());
        inputs.extend(order_match.sell_order.id.as_bytes());
        inputs.extend(order_match.matched_price.to_le_bytes());
        inputs.extend(order_match.matched_amount.to_le_bytes());
        inputs.extend(order_match.timestamp.to_le_bytes());
        
        // Generate public inputs (what can be verified publicly)
        let public_inputs = self.generate_public_inputs(order_match).await?;
        
        // Generate the actual proof using the circuit
        let proof_data = self.run_proof_generation(&inputs, "order_matching").await?;
        
        // Sign the proof with operator key
        let operator_signature = self.sign_proof(&proof_data).await?;
        
        let matching_proof = MatchingProof {
            proof_id: format!("proof_{}", order_match.match_id),
            order_matches: vec![order_match.match_id.clone()],
            proof_data,
            public_inputs,
            verification_key: circuit.verification_key.clone(),
            timestamp: chrono::Utc::now().timestamp() as u64,
            operator_signature,
        };
        
        info!("Generated matching proof: {}", matching_proof.proof_id);
        Ok(matching_proof)
    }

    /// Generate batch proof for multiple matches
    pub async fn generate_batch_proof(&self, matches: &[OrderMatch]) -> Result<BatchProof> {
        if matches.is_empty() {
            return Err(anyhow::anyhow!("Cannot generate batch proof for empty matches"));
        }
        
        info!("Generating batch proof for {} matches", matches.len());
        
        let batch_id = format!("batch_{}", uuid::Uuid::new_v4());
        let mut individual_proofs = Vec::new();
        let mut all_signatures = Vec::new();
        
        // Generate individual proofs
        for order_match in matches {
            let proof = self.generate_matching_proof(order_match).await?;
            all_signatures.push(proof.operator_signature.clone());
            individual_proofs.push(proof);
        }
        
        // Generate aggregated proof
        let aggregated_proof = self.aggregate_proofs(&individual_proofs).await?;
        
        // Generate batch public inputs
        let batch_public_inputs = self.generate_batch_public_inputs(matches).await?;
        
        let batch_proof = BatchProof {
            batch_id: batch_id.clone(),
            individual_proofs,
            aggregated_proof,
            batch_public_inputs,
            operator_signatures: all_signatures,
            timestamp: chrono::Utc::now().timestamp() as u64,
        };
        
        info!("Generated batch proof: {}", batch_id);
        Ok(batch_proof)
    }

    /// Generate privacy preservation proof
    pub async fn generate_privacy_proof(&self, orders: &[DecryptedOrder]) -> Result<MatchingProof> {
        info!("Generating privacy proof for {} orders", orders.len());
        
        let circuit = self.circuits.get("privacy_proof")
            .ok_or_else(|| anyhow::anyhow!("Privacy proof circuit not found"))?;
        
        // Prepare inputs without revealing sensitive order data
        let mut inputs = Vec::new();
        
        for order in orders {
            // Only include commitment hashes, not actual order data
            let order_hash = self.hash_order(order)?;
            inputs.extend(order_hash);
        }
        
        // Add number of orders
        inputs.extend((orders.len() as u64).to_le_bytes());
        
        // Generate public inputs (commitments only)
        let public_inputs = self.generate_privacy_public_inputs(orders).await?;
        
        // Generate proof
        let proof_data = self.run_proof_generation(&inputs, "privacy_proof").await?;
        
        // Sign proof
        let operator_signature = self.sign_proof(&proof_data).await?;
        
        let privacy_proof = MatchingProof {
            proof_id: format!("privacy_proof_{}", uuid::Uuid::new_v4()),
            order_matches: orders.iter().map(|o| o.id.clone()).collect(),
            proof_data,
            public_inputs,
            verification_key: circuit.verification_key.clone(),
            timestamp: chrono::Utc::now().timestamp() as u64,
            operator_signature,
        };
        
        info!("Generated privacy proof: {}", privacy_proof.proof_id);
        Ok(privacy_proof)
    }

    /// Generate proof for order validity without revealing content
    pub async fn generate_validity_proof(&self, order: &DecryptedOrder) -> Result<Vec<u8>> {
        info!("Generating validity proof for order: {}", order.id);
        
        // Create proof that order is valid without revealing details
        let mut proof_inputs = Vec::new();
        
        // Add order hash
        let order_hash = self.hash_order(order)?;
        proof_inputs.extend(order_hash);
        
        // Add validity constraints (price > 0, amount > 0, deadline in future)
        let is_valid = order.price > 0.0 && 
                      order.amount > 0.0 && 
                      order.deadline > chrono::Utc::now().timestamp() as u64;
        
        proof_inputs.push(if is_valid { 1u8 } else { 0u8 });
        
        // Generate proof
        let proof = self.run_proof_generation(&proof_inputs, "privacy_proof").await?;
        
        info!("Generated validity proof for order: {}", order.id);
        Ok(proof)
    }

    /// Run the actual proof generation (simplified mock implementation)
    async fn run_proof_generation(&self, inputs: &[u8], circuit_type: &str) -> Result<Vec<u8>> {
        debug!("Running proof generation for circuit: {}", circuit_type);
        
        let proving_key = self.proving_keys.get(circuit_type)
            .ok_or_else(|| anyhow::anyhow!("Proving key not found for circuit: {}", circuit_type))?;
        
        // Mock proof generation (in production, this would use actual ZK libraries)
        let mut proof = Vec::new();
        
        // Add circuit identifier
        proof.extend(circuit_type.as_bytes());
        
        // Add input hash
        let input_hash = self.hash_data(inputs)?;
        proof.extend(input_hash);
        
        // Add proving key hash
        let key_hash = self.hash_data(proving_key)?;
        proof.extend(key_hash);
        
        // Add timestamp
        let timestamp = chrono::Utc::now().timestamp() as u64;
        proof.extend(timestamp.to_le_bytes());
        
        // Add mock proof elements (in production, these would be actual ZK proof components)
        proof.extend(vec![0x42; 256]); // Mock proof pi_a
        proof.extend(vec![0x43; 512]); // Mock proof pi_b  
        proof.extend(vec![0x44; 256]); // Mock proof pi_c
        
        debug!("Generated proof of {} bytes", proof.len());
        Ok(proof)
    }

    /// Aggregate multiple proofs into a batch proof
    async fn aggregate_proofs(&self, proofs: &[MatchingProof]) -> Result<Vec<u8>> {
        info!("Aggregating {} proofs", proofs.len());
        
        let mut aggregated = Vec::new();
        
        // Add number of proofs
        aggregated.extend((proofs.len() as u64).to_le_bytes());
        
        // Add hash of all individual proofs
        for proof in proofs {
            let proof_hash = self.hash_data(&proof.proof_data)?;
            aggregated.extend(proof_hash);
        }
        
        // Add aggregation timestamp
        let timestamp = chrono::Utc::now().timestamp() as u64;
        aggregated.extend(timestamp.to_le_bytes());
        
        // Mock aggregated proof components
        aggregated.extend(vec![0x50; 512]); // Mock aggregated proof
        
        info!("Generated aggregated proof of {} bytes", aggregated.len());
        Ok(aggregated)
    }

    /// Generate public inputs for order match
    async fn generate_public_inputs(&self, order_match: &OrderMatch) -> Result<Vec<u8>> {
        let mut public_inputs = Vec::new();
        
        // Pool key (public)
        public_inputs.extend(order_match.pool_key.as_bytes());
        
        // Match timestamp (public)
        public_inputs.extend(order_match.timestamp.to_le_bytes());
        
        // Matched price (public after execution)
        public_inputs.extend(order_match.matched_price.to_le_bytes());
        
        // Matched amount (public after execution)
        public_inputs.extend(order_match.matched_amount.to_le_bytes());
        
        // Order commitments (public)
        let buy_commitment = self.hash_order_commitment(&order_match.buy_order)?;
        let sell_commitment = self.hash_order_commitment(&order_match.sell_order)?;
        public_inputs.extend(buy_commitment);
        public_inputs.extend(sell_commitment);
        
        Ok(public_inputs)
    }

    /// Generate batch public inputs
    async fn generate_batch_public_inputs(&self, matches: &[OrderMatch]) -> Result<Vec<u8>> {
        let mut batch_inputs = Vec::new();
        
        // Number of matches
        batch_inputs.extend((matches.len() as u64).to_le_bytes());
        
        // Batch timestamp
        let timestamp = chrono::Utc::now().timestamp() as u64;
        batch_inputs.extend(timestamp.to_le_bytes());
        
        // Total volume
        let total_volume: f64 = matches.iter().map(|m| m.matched_amount).sum();
        batch_inputs.extend(total_volume.to_le_bytes());
        
        // Average price
        let avg_price = if matches.is_empty() {
            0.0
        } else {
            matches.iter().map(|m| m.matched_price).sum::<f64>() / matches.len() as f64
        };
        batch_inputs.extend(avg_price.to_le_bytes());
        
        // Hash of all match IDs
        let mut match_ids = String::new();
        for order_match in matches {
            match_ids.push_str(&order_match.match_id);
        }
        let match_ids_hash = self.hash_data(match_ids.as_bytes())?;
        batch_inputs.extend(match_ids_hash);
        
        Ok(batch_inputs)
    }

    /// Generate privacy-preserving public inputs
    async fn generate_privacy_public_inputs(&self, orders: &[DecryptedOrder]) -> Result<Vec<u8>> {
        let mut public_inputs = Vec::new();
        
        // Number of orders (public)
        public_inputs.extend((orders.len() as u64).to_le_bytes());
        
        // Timestamp (public)
        let timestamp = chrono::Utc::now().timestamp() as u64;
        public_inputs.extend(timestamp.to_le_bytes());
        
        // Order commitment hashes (public)
        for order in orders {
            let commitment_hash = self.hash_order(order)?;
            public_inputs.extend(commitment_hash);
        }
        
        Ok(public_inputs)
    }

    /// Hash order for commitment
    fn hash_order_commitment(&self, order: &crate::matching::Order) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(order.id.as_bytes());
        hasher.update(order.trader.as_bytes());
        hasher.update(&order.timestamp.to_le_bytes());
        Ok(hasher.finalize().to_vec())
    }

    /// Hash decrypted order
    fn hash_order(&self, order: &DecryptedOrder) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(order.id.as_bytes());
        hasher.update(order.trader.as_bytes());
        hasher.update(order.pool_key.as_bytes());
        hasher.update(&order.amount.to_le_bytes());
        hasher.update(&order.price.to_le_bytes());
        hasher.update(&order.deadline.to_le_bytes());
        Ok(hasher.finalize().to_vec())
    }

    /// Hash arbitrary data
    fn hash_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        let mut hasher = Sha256::new();
        hasher.update(data);
        Ok(hasher.finalize().to_vec())
    }

    /// Sign proof with operator private key
    async fn sign_proof(&self, proof_data: &[u8]) -> Result<Vec<u8>> {
        // Mock signature (in production, use actual cryptographic signatures)
        let mut hasher = Sha256::new();
        hasher.update(proof_data);
        hasher.update(b"operator_private_key"); // Mock private key
        hasher.update(&chrono::Utc::now().timestamp().to_le_bytes());
        
        Ok(hasher.finalize().to_vec())
    }

    /// Get circuit information
    pub fn get_circuit_info(&self, circuit_type: &str) -> Option<&ProofCircuit> {
        self.circuits.get(circuit_type)
    }

    /// List available circuits
    pub fn list_circuits(&self) -> Vec<String> {
        self.circuits.keys().cloned().collect()
    }

    /// Health check for ZK prover
    pub async fn health_check(&self) -> Result<()> {
        // Test proof generation with mock data
        use crate::matching::{Order, OrderType, OrderStatus};
        
        let mock_buy_order = Order {
            id: "test_buy".to_string(),
            trader: "test_trader_1".to_string(),
            pool_key: "TEST_POOL".to_string(),
            order_type: OrderType::Buy,
            amount: 100.0,
            price: 2000.0,
            status: OrderStatus::Pending,
            timestamp: chrono::Utc::now().timestamp() as u64,
            deadline: chrono::Utc::now().timestamp() as u64 + 3600,
        };
        
        let mock_sell_order = Order {
            id: "test_sell".to_string(),
            trader: "test_trader_2".to_string(),
            pool_key: "TEST_POOL".to_string(),
            order_type: OrderType::Sell,
            amount: 100.0,
            price: 2000.0,
            status: OrderStatus::Pending,
            timestamp: chrono::Utc::now().timestamp() as u64,
            deadline: chrono::Utc::now().timestamp() as u64 + 3600,
        };
        
        let mock_match = OrderMatch {
            match_id: "test_match".to_string(),
            buy_order: mock_buy_order,
            sell_order: mock_sell_order,
            matched_price: 2000.0,
            matched_amount: 100.0,
            timestamp: chrono::Utc::now().timestamp() as u64,
            pool_key: "TEST_POOL".to_string(),
        };
        
        // Test proof generation
        let _proof = self.generate_matching_proof(&mock_match).await?;
        
        debug!("ZK prover health check passed");
        Ok(())
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