use anyhow::Result;
use serde::{Deserialize, Serialize};
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use rsa::{RsaPrivateKey, RsaPublicKey, Pkcs1v15Encrypt};
use rsa::traits::PaddingScheme; // Updated import path for PaddingScheme
use sha2::{Sha256, Digest};
use tracing::{debug, info, warn};

use super::{OrderType};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecryptedOrder {
    pub id: String,
    pub trader: String,
    pub pool_key: String,
    pub order_type: OrderType,
    pub amount: f64,
    pub price: f64,
    pub deadline: u64,
    pub encrypted_data: Vec<u8>, // Original encrypted data for proof generation
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedOrderData {
    pub trader: String,
    pub pool_key: String,
    pub order_type: OrderType,
    pub amount: f64,
    pub price: f64,
    pub deadline: u64,
    pub nonce: Vec<u8>,
    pub commitment: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptionKeys {
    pub public_key: Vec<u8>,
    pub private_key: Vec<u8>,
    pub symmetric_key: Vec<u8>,
}

pub struct EncryptionManager {
    rsa_private_key: RsaPrivateKey,
    rsa_public_key: RsaPublicKey,
    symmetric_key: Key<Aes256Gcm>,
    cipher: Aes256Gcm,
}

impl EncryptionManager {
    /// Create new encryption manager with generated keys
    pub fn new() -> Result<Self> {
        info!("Initializing encryption manager with new keys");
        
        let mut rng = rand::thread_rng();
        let rsa_private_key = RsaPrivateKey::new(&mut rng, 2048)?;
        let rsa_public_key = RsaPublicKey::from(&rsa_private_key);
        
        // Generate symmetric key for AES encryption
        let symmetric_key = Aes256Gcm::generate_key(&mut OsRng);
        let cipher = Aes256Gcm::new(&symmetric_key);
        
        Ok(Self {
            rsa_private_key,
            rsa_public_key,
            symmetric_key,
            cipher,
        })
    }

    /// Create encryption manager from existing keys
    pub fn from_keys(keys: EncryptionKeys) -> Result<Self> {
        info!("Initializing encryption manager from existing keys");
        
        // Deserialize RSA keys (in production, these would be proper key formats)
        let mut rng = rand::thread_rng();
        let rsa_private_key = RsaPrivateKey::new(&mut rng, 2048)?;
        let rsa_public_key = RsaPublicKey::from(&rsa_private_key);
        
        // Use provided symmetric key
        let symmetric_key = Key::<Aes256Gcm>::from_slice(&keys.symmetric_key);
        let cipher = Aes256Gcm::new(symmetric_key);
        
        Ok(Self {
            rsa_private_key,
            rsa_public_key,
            symmetric_key: *symmetric_key,
            cipher,
        })
    }

    /// Export encryption keys
    pub fn export_keys(&self) -> Result<EncryptionKeys> {
        // In production, these would be properly serialized key formats
        Ok(EncryptionKeys {
            public_key: vec![1, 2, 3, 4], // Mock public key
            private_key: vec![5, 6, 7, 8], // Mock private key (encrypted)
            symmetric_key: self.symmetric_key.as_slice().to_vec(),
        })
    }

    /// Get public key for client-side encryption
    pub fn get_public_key(&self) -> Vec<u8> {
        // In production, this would return the actual RSA public key
        vec![1, 2, 3, 4] // Mock public key
    }

    /// Encrypt order data for storage
    pub fn encrypt_order(&self, order_data: &EncryptedOrderData) -> Result<Vec<u8>> {
        debug!("Encrypting order data for order ID: {}", order_data.trader);
        
        // Serialize order data
        let plaintext = serde_json::to_vec(order_data)?;
        
        // Generate nonce
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        
        // Encrypt with AES-GCM
        let ciphertext = self.cipher.encrypt(&nonce, plaintext.as_ref())
            .map_err(|e| anyhow::anyhow!("Encryption failed: {:?}", e))?;
        
        // Combine nonce and ciphertext
        let mut encrypted_data = nonce.to_vec();
        encrypted_data.extend(ciphertext);
        
        info!("Successfully encrypted order data: {} bytes", encrypted_data.len());
        Ok(encrypted_data)
    }

    /// Decrypt order data
    pub fn decrypt_order(&self, encrypted_data: &[u8], order_id: String) -> Result<DecryptedOrder> {
        debug!("Decrypting order data for order ID: {}", order_id);
        
        if encrypted_data.len() < 12 {
            return Err(anyhow::anyhow!("Invalid encrypted data length"));
        }
        
        // Extract nonce and ciphertext
        let (nonce_bytes, ciphertext) = encrypted_data.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);
        
        // Decrypt
        let plaintext = self.cipher.decrypt(nonce, ciphertext)
            .map_err(|e| anyhow::anyhow!("Decryption failed: {:?}", e))?;
        
        // Deserialize
        let order_data: EncryptedOrderData = serde_json::from_slice(&plaintext)?;
        
        let decrypted_order = DecryptedOrder {
            id: order_id,
            trader: order_data.trader,
            pool_key: order_data.pool_key,
            order_type: order_data.order_type,
            amount: order_data.amount,
            price: order_data.price,
            deadline: order_data.deadline,
            encrypted_data: encrypted_data.to_vec(),
        };
        
        info!("Successfully decrypted order: {}", decrypted_order.id);
        Ok(decrypted_order)
    }

    /// Decrypt multiple orders in batch
    pub fn decrypt_orders_batch(&self, encrypted_orders: Vec<(String, Vec<u8>)>) -> Result<Vec<DecryptedOrder>> {
        info!("Decrypting batch of {} orders", encrypted_orders.len());
        
        let mut decrypted_orders = Vec::new();
        let mut failed_count = 0;
        
        for (order_id, encrypted_data) in encrypted_orders {
            match self.decrypt_order(&encrypted_data, order_id.clone()) {
                Ok(decrypted) => {
                    decrypted_orders.push(decrypted);
                }
                Err(e) => {
                    warn!("Failed to decrypt order {}: {:?}", order_id, e);
                    failed_count += 1;
                }
            }
        }
        
        if failed_count > 0 {
            warn!("Failed to decrypt {} out of {} orders", failed_count, 
                  decrypted_orders.len() + failed_count);
        }
        
        info!("Successfully decrypted {} orders", decrypted_orders.len());
        Ok(decrypted_orders)
    }

    /// Generate commitment hash for order
    pub fn generate_commitment(&self, order_data: &EncryptedOrderData) -> Result<String> {
        let mut hasher = Sha256::new();
        
        // Hash key order components
        hasher.update(order_data.trader.as_bytes());
        hasher.update(order_data.pool_key.as_bytes());
        hasher.update(&order_data.amount.to_le_bytes());
        hasher.update(&order_data.price.to_le_bytes());
        hasher.update(&order_data.deadline.to_le_bytes());
        hasher.update(&order_data.nonce);
        
        let hash = hasher.finalize();
        let commitment = hex::encode(hash);
        
        debug!("Generated commitment: {}", commitment);
        Ok(commitment)
    }

    /// Verify order commitment
    pub fn verify_commitment(&self, order_data: &EncryptedOrderData, commitment: &str) -> Result<bool> {
        let calculated_commitment = self.generate_commitment(order_data)?;
        let is_valid = calculated_commitment == commitment;
        
        debug!("Commitment verification: {} (expected: {}, got: {})", 
               is_valid, commitment, calculated_commitment);
        
        Ok(is_valid)
    }

    /// Create zero-knowledge proof for order matching
    pub fn create_matching_proof(&self, orders: &[DecryptedOrder]) -> Result<Vec<u8>> {
        info!("Creating matching proof for {} orders", orders.len());
        
        // Simplified proof generation (in production, this would use proper ZK circuits)
        let mut proof_data = Vec::new();
        
        for order in orders {
            // Add order hash to proof
            let order_hash = self.hash_order(order)?;
            proof_data.extend(order_hash);
        }
        
        // Add timestamp
        let timestamp = chrono::Utc::now().timestamp() as u64;
        proof_data.extend(timestamp.to_le_bytes());
        
        // Sign with private key (simplified)
        let signature = self.sign_data(&proof_data)?;
        proof_data.extend(signature);
        
        info!("Generated matching proof: {} bytes", proof_data.len());
        Ok(proof_data)
    }

    /// Verify zero-knowledge proof
    pub fn verify_matching_proof(&self, proof: &[u8], orders: &[DecryptedOrder]) -> Result<bool> {
        info!("Verifying matching proof for {} orders", orders.len());
        
        // Simplified verification (in production, this would use proper ZK verification)
        if proof.len() < 72 { // 32 bytes per order hash + 8 bytes timestamp + 32 bytes signature minimum
            return Ok(false);
        }
        
        // In a real implementation, this would verify the ZK proof
        // For now, we'll just check if the proof length is reasonable
        let expected_min_length = orders.len() * 32 + 8 + 32;
        let is_valid = proof.len() >= expected_min_length;
        
        info!("Proof verification result: {}", is_valid);
        Ok(is_valid)
    }

    /// Hash order for proof generation
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

    /// Sign data with private key
    fn sign_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        // Simplified signing (in production, use proper digital signatures)
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.update("operator_signature_key"); // Mock private key material
        
        Ok(hasher.finalize().to_vec())
    }

    /// Generate secure random nonce
    pub fn generate_nonce() -> Vec<u8> {
        use rand::RngCore;
        let mut nonce = vec![0u8; 32];
        rand::thread_rng().fill_bytes(&mut nonce);
        nonce
    }

    /// Health check for encryption manager
    pub fn health_check(&self) -> Result<()> {
        // Test encryption/decryption with mock data
        let test_order = EncryptedOrderData {
            trader: "test_trader".to_string(),
            pool_key: "TEST_POOL".to_string(),
            order_type: OrderType::Buy,
            amount: 100.0,
            price: 2000.0,
            deadline: chrono::Utc::now().timestamp() as u64 + 3600,
            nonce: Self::generate_nonce(),
            commitment: "test_commitment".to_string(),
        };
        
        let encrypted = self.encrypt_order(&test_order)?;
        let decrypted = self.decrypt_order(&encrypted, "test_order".to_string())?;
        
        if decrypted.trader != test_order.trader {
            return Err(anyhow::anyhow!("Encryption/decryption test failed"));
        }
        
        debug!("Encryption manager health check passed");
        Ok(())
    }
}

impl Default for EncryptionManager {
    fn default() -> Self {
        Self::new().expect("Failed to create default encryption manager")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encryption_manager_creation() {
        let manager = EncryptionManager::new();
        assert!(manager.is_ok());
    }

    #[test]
    fn test_encrypt_decrypt_order() {
        let manager = EncryptionManager::new().unwrap();
        
        let order_data = EncryptedOrderData {
            trader: "test_trader".to_string(),
            pool_key: "ETH_USDC_3000".to_string(),
            order_type: OrderType::Buy,
            amount: 100.0,
            price: 2000.0,
            deadline: chrono::Utc::now().timestamp() as u64 + 3600,
            nonce: EncryptionManager::generate_nonce(),
            commitment: "test_commitment".to_string(),
        };
        
        let encrypted = manager.encrypt_order(&order_data).unwrap();
        let decrypted = manager.decrypt_order(&encrypted, "test_order".to_string()).unwrap();
        
        assert_eq!(decrypted.trader, order_data.trader);
        assert_eq!(decrypted.amount, order_data.amount);
        assert_eq!(decrypted.price, order_data.price);
    }

    #[test]
    fn test_commitment_generation() {
        let manager = EncryptionManager::new().unwrap();
        
        let order_data = EncryptedOrderData {
            trader: "test_trader".to_string(),
            pool_key: "ETH_USDC_3000".to_string(),
            order_type: OrderType::Buy,
            amount: 100.0,
            price: 2000.0,
            deadline: chrono::Utc::now().timestamp() as u64 + 3600,
            nonce: vec![1, 2, 3, 4],
            commitment: "".to_string(),
        };
        
        let commitment = manager.generate_commitment(&order_data).unwrap();
        assert!(!commitment.is_empty());
        assert_eq!(commitment.len(), 64); // SHA256 hex string
        
        let is_valid = manager.verify_commitment(&order_data, &commitment).unwrap();
        assert!(is_valid);
    }
}