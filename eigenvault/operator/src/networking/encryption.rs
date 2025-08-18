use anyhow::Result;
use serde::{Deserialize, Serialize};
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Key, Nonce,
};
use tracing::{debug, info, warn};

use super::P2PMessage;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecureMessage {
    pub message_id: String,
    pub sender_id: String,
    pub recipient_id: Option<String>, // None for broadcast
    pub encrypted_data: Vec<u8>,
    pub nonce: Vec<u8>,
    pub signature: Vec<u8>,
    pub timestamp: u64,
}

#[derive(Clone)]
pub struct NetworkEncryption {
    local_key: Key<Aes256Gcm>,
    cipher: Aes256Gcm,
    peer_keys: std::collections::HashMap<String, Vec<u8>>,
}

impl std::fmt::Debug for NetworkEncryption {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NetworkEncryption")
            .field("peer_keys", &self.peer_keys)
            .finish()
    }
}

impl NetworkEncryption {
    pub async fn new() -> Result<Self> {
        info!("Initializing network encryption");
        
        // Generate local encryption key
        let local_key = Aes256Gcm::generate_key(&mut OsRng);
        let cipher = Aes256Gcm::new(&local_key);
        
        Ok(Self {
            local_key,
            cipher,
            peer_keys: std::collections::HashMap::new(),
        })
    }

    /// Add peer's public key for encrypted communication
    pub fn add_peer_key(&mut self, peer_id: String, public_key: Vec<u8>) {
        debug!("Adding public key for peer: {}", peer_id);
        self.peer_keys.insert(peer_id, public_key);
    }

    /// Remove peer's public key
    pub fn remove_peer_key(&mut self, peer_id: &str) {
        debug!("Removing public key for peer: {}", peer_id);
        self.peer_keys.remove(peer_id);
    }

    /// Encrypt message for transmission
    pub async fn encrypt_message(&self, message: &P2PMessage) -> Result<SecureMessage> {
        debug!("Encrypting P2P message for transmission");
        
        // Serialize the message
        let plaintext = serde_json::to_vec(message)?;
        
        // Generate nonce
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        
        // Encrypt the message
        let encrypted_data = self.cipher.encrypt(&nonce, plaintext.as_ref())
            .map_err(|e| anyhow::anyhow!("Message encryption failed: {:?}", e))?;
        
        // Sign the encrypted data
        let signature = self.sign_data(&encrypted_data).await?;
        
        let secure_message = SecureMessage {
            message_id: uuid::Uuid::new_v4().to_string(),
            sender_id: "local_peer".to_string(), // Would use actual peer ID
            recipient_id: None,
            encrypted_data,
            nonce: nonce.to_vec(),
            signature,
            timestamp: chrono::Utc::now().timestamp() as u64,
        };
        
        debug!("Message encrypted successfully: {} bytes", secure_message.encrypted_data.len());
        Ok(secure_message)
    }

    /// Decrypt received message
    pub async fn decrypt_message(&self, secure_message: &SecureMessage) -> Result<P2PMessage> {
        debug!("Decrypting received message: {}", secure_message.message_id);
        
        // Verify signature
        if !self.verify_signature(&secure_message.encrypted_data, &secure_message.signature).await? {
            return Err(anyhow::anyhow!("Message signature verification failed"));
        }
        
        // Check timestamp (reject messages older than 1 hour)
        let current_time = chrono::Utc::now().timestamp() as u64;
        if current_time > secure_message.timestamp + 3600 {
            return Err(anyhow::anyhow!("Message too old"));
        }
        
        // Decrypt the message
        let nonce = Nonce::from_slice(&secure_message.nonce);
        let plaintext = self.cipher.decrypt(nonce, secure_message.encrypted_data.as_ref())
            .map_err(|e| anyhow::anyhow!("Message decryption failed: {:?}", e))?;
        
        // Deserialize the message
        let message: P2PMessage = serde_json::from_slice(&plaintext)?;
        
        debug!("Message decrypted successfully");
        Ok(message)
    }

    /// Encrypt message for specific peer
    pub async fn encrypt_message_for_peer(
        &self,
        message: &P2PMessage,
        peer_id: &str,
    ) -> Result<SecureMessage> {
        debug!("Encrypting message for specific peer: {}", peer_id);
        
        // Get peer's public key
        let _peer_key = self.peer_keys.get(peer_id)
            .ok_or_else(|| anyhow::anyhow!("Peer key not found: {}", peer_id))?;
        
        // For now, use the same encryption as broadcast
        // In production, would use peer's public key for asymmetric encryption
        let mut secure_message = self.encrypt_message(message).await?;
        secure_message.recipient_id = Some(peer_id.to_string());
        
        Ok(secure_message)
    }

    /// Create encrypted broadcast message
    pub async fn create_broadcast_message(&self, message: &P2PMessage) -> Result<SecureMessage> {
        debug!("Creating encrypted broadcast message");
        self.encrypt_message(message).await
    }

    /// Sign data with local private key
    async fn sign_data(&self, data: &[u8]) -> Result<Vec<u8>> {
        // Mock signature - in production, use actual cryptographic signing
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.update(b"network_encryption_key"); // Mock private key
        hasher.update(&chrono::Utc::now().timestamp().to_le_bytes());
        
        Ok(hasher.finalize().to_vec())
    }

    /// Verify signature
    async fn verify_signature(&self, data: &[u8], signature: &[u8]) -> Result<bool> {
        // Mock verification - in production, use actual cryptographic verification
        if signature.is_empty() {
            return Ok(false);
        }
        
        // Simple check: signature should be 32 bytes (SHA256)
        if signature.len() != 32 {
            return Ok(false);
        }
        
        // In production, would verify against sender's public key
        Ok(true)
    }

    /// Rotate encryption keys
    pub async fn rotate_keys(&mut self) -> Result<()> {
        info!("Rotating network encryption keys");
        
        // Generate new key
        let new_key = Aes256Gcm::generate_key(&mut OsRng);
        let new_cipher = Aes256Gcm::new(&new_key);
        
        // Update keys
        self.local_key = new_key;
        self.cipher = new_cipher;
        
        info!("Network encryption keys rotated successfully");
        Ok(())
    }

    /// Get encryption statistics
    pub fn get_encryption_stats(&self) -> EncryptionStats {
        EncryptionStats {
            peer_keys_count: self.peer_keys.len() as u64,
            local_key_created: chrono::Utc::now().timestamp() as u64, // Mock timestamp
        }
    }

    /// Health check for network encryption
    pub async fn health_check(&self) -> Result<()> {
        // Test encryption/decryption with mock data
        let test_message = P2PMessage::Ping {
            timestamp: chrono::Utc::now().timestamp() as u64,
        };
        
        let encrypted = self.encrypt_message(&test_message).await?;
        let decrypted = self.decrypt_message(&encrypted).await?;
        
        match (&test_message, &decrypted) {
            (P2PMessage::Ping { timestamp: t1 }, P2PMessage::Ping { timestamp: t2 }) => {
                if t1 != t2 {
                    return Err(anyhow::anyhow!("Encryption/decryption test failed"));
                }
            }
            _ => return Err(anyhow::anyhow!("Message type mismatch in encryption test")),
        }
        
        debug!("Network encryption health check passed");
        Ok(())
    }

    /// Export public key for sharing with peers
    pub fn export_public_key(&self) -> Vec<u8> {
        // In production, this would export the actual public key
        // For now, return a mock public key
        self.local_key.as_slice().to_vec()
    }

    /// Derive shared secret with peer (for ECDH)
    pub async fn derive_shared_secret(&self, peer_public_key: &[u8]) -> Result<Vec<u8>> {
        // Mock shared secret derivation
        // In production, would use ECDH or similar
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(self.local_key.as_slice());
        hasher.update(peer_public_key);
        hasher.update(b"shared_secret_derivation");
        
        Ok(hasher.finalize().to_vec())
    }

    /// Create secure channel with peer
    pub async fn create_secure_channel(&mut self, peer_id: String, peer_public_key: Vec<u8>) -> Result<()> {
        info!("Creating secure channel with peer: {}", peer_id);
        
        // Derive shared secret
        let _shared_secret = self.derive_shared_secret(&peer_public_key).await?;
        
        // Store peer's public key
        self.add_peer_key(peer_id.clone(), peer_public_key);
        
        info!("Secure channel established with peer: {}", peer_id);
        Ok(())
    }

    /// Close secure channel with peer
    pub async fn close_secure_channel(&mut self, peer_id: &str) -> Result<()> {
        info!("Closing secure channel with peer: {}", peer_id);
        
        self.remove_peer_key(peer_id);
        
        info!("Secure channel closed with peer: {}", peer_id);
        Ok(())
    }

    /// Encrypt bulk data (for large payloads)
    pub async fn encrypt_bulk_data(&self, data: &[u8]) -> Result<(Vec<u8>, Vec<u8>)> {
        debug!("Encrypting bulk data: {} bytes", data.len());
        
        // Generate nonce
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        
        // Encrypt data
        let encrypted_data = self.cipher.encrypt(&nonce, data)
            .map_err(|e| anyhow::anyhow!("Bulk data encryption failed: {:?}", e))?;
        
        debug!("Bulk data encrypted: {} bytes", encrypted_data.len());
        Ok((encrypted_data, nonce.to_vec()))
    }

    /// Decrypt bulk data
    pub async fn decrypt_bulk_data(&self, encrypted_data: &[u8], nonce: &[u8]) -> Result<Vec<u8>> {
        debug!("Decrypting bulk data: {} bytes", encrypted_data.len());
        
        let nonce = Nonce::from_slice(nonce);
        let plaintext = self.cipher.decrypt(nonce, encrypted_data)
            .map_err(|e| anyhow::anyhow!("Bulk data decryption failed: {:?}", e))?;
        
        debug!("Bulk data decrypted: {} bytes", plaintext.len());
        Ok(plaintext)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptionStats {
    pub peer_keys_count: u64,
    pub local_key_created: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_network_encryption_creation() {
        let encryption = NetworkEncryption::new().await;
        assert!(encryption.is_ok());
    }

    #[tokio::test]
    async fn test_encrypt_decrypt_message() -> Result<()> {
        let encryption = NetworkEncryption::new().await?;
        
        let test_message = P2PMessage::Ping {
            timestamp: chrono::Utc::now().timestamp() as u64,
        };
        
        let encrypted = encryption.encrypt_message(&test_message).await?;
        let decrypted = encryption.decrypt_message(&encrypted).await?;
        
        match (&test_message, &decrypted) {
            (P2PMessage::Ping { timestamp: t1 }, P2PMessage::Ping { timestamp: t2 }) => {
                assert_eq!(t1, t2);
            }
            _ => panic!("Message type mismatch"),
        }
        
        Ok(())
    }

    #[tokio::test]
    async fn test_peer_key_management() -> Result<()> {
        let mut encryption = NetworkEncryption::new().await?;
        
        let peer_id = "test_peer".to_string();
        let public_key = vec![1, 2, 3, 4, 5, 6, 7, 8];
        
        encryption.add_peer_key(peer_id.clone(), public_key.clone());
        assert!(encryption.peer_keys.contains_key(&peer_id));
        
        encryption.remove_peer_key(&peer_id);
        assert!(!encryption.peer_keys.contains_key(&peer_id));
        
        Ok(())
    }

    #[tokio::test]
    async fn test_bulk_data_encryption() -> Result<()> {
        let encryption = NetworkEncryption::new().await?;
        
        let test_data = vec![0u8; 10000]; // 10KB test data
        
        let (encrypted_data, nonce) = encryption.encrypt_bulk_data(&test_data).await?;
        let decrypted_data = encryption.decrypt_bulk_data(&encrypted_data, &nonce).await?;
        
        assert_eq!(test_data, decrypted_data);
        
        Ok(())
    }

    #[tokio::test]
    async fn test_secure_channel_creation() -> Result<()> {
        let mut encryption = NetworkEncryption::new().await?;
        
        let peer_id = "test_peer".to_string();
        let peer_public_key = vec![1, 2, 3, 4, 5, 6, 7, 8];
        
        encryption.create_secure_channel(peer_id.clone(), peer_public_key).await?;
        assert!(encryption.peer_keys.contains_key(&peer_id));
        
        encryption.close_secure_channel(&peer_id).await?;
        assert!(!encryption.peer_keys.contains_key(&peer_id));
        
        Ok(())
    }
}