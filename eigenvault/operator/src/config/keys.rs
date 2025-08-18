use anyhow::Result;
use secp256k1::{SecretKey, PublicKey, Secp256k1};
use rand::rngs::OsRng;
use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use sha3::Digest; // Add this import for digest functionality

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorKeys {
    pub ethereum_private_key: String,
    pub ethereum_public_key: String,
    pub ethereum_address: String,
    pub bls_private_key: String,
    pub bls_public_key: String,
    pub encryption_private_key: String,
    pub encryption_public_key: String,
}

pub struct KeyManager {
    secp: Secp256k1<secp256k1::All>,
}

impl KeyManager {
    pub fn new() -> Self {
        Self {
            secp: Secp256k1::new(),
        }
    }

    pub async fn generate_keys(&self, output_dir: &PathBuf) -> Result<OperatorKeys> {
        tokio::fs::create_dir_all(output_dir).await?;

        // Generate Ethereum keys
        let ethereum_keys = self.generate_ethereum_keys()?;
        
        // Generate BLS keys (simplified - in production would use proper BLS library)
        let bls_keys = self.generate_bls_keys()?;
        
        // Generate encryption keys
        let encryption_keys = self.generate_encryption_keys()?;

        let operator_keys = OperatorKeys {
            ethereum_private_key: ethereum_keys.0,
            ethereum_public_key: ethereum_keys.1,
            ethereum_address: ethereum_keys.2,
            bls_private_key: bls_keys.0,
            bls_public_key: bls_keys.1,
            encryption_private_key: encryption_keys.0,
            encryption_public_key: encryption_keys.1,
        };

        // Save keys to files
        self.save_keys(&operator_keys, output_dir).await?;

        Ok(operator_keys)
    }

    fn generate_ethereum_keys(&self) -> Result<(String, String, String)> {
        let mut rng = OsRng;
        let secret_key = SecretKey::new(&mut rng);
        let public_key = PublicKey::from_secret_key(&self.secp, &secret_key);

        // Convert to hex strings
        let private_key_hex = hex::encode(secret_key.secret_bytes());
        let public_key_hex = hex::encode(public_key.serialize());

        // Generate Ethereum address from public key
        let address = self.public_key_to_address(&public_key)?;

        Ok((
            format!("0x{}", private_key_hex),
            format!("0x{}", public_key_hex),
            format!("0x{}", hex::encode(address)),
        ))
    }

    fn generate_bls_keys(&self) -> Result<(String, String)> {
        // Simplified BLS key generation
        // In production, would use a proper BLS library like blstrs
        let mut rng = OsRng;
        let secret_key = SecretKey::new(&mut rng);
        let public_key = PublicKey::from_secret_key(&self.secp, &secret_key);

        Ok((
            hex::encode(secret_key.secret_bytes()),
            hex::encode(public_key.serialize()),
        ))
    }

    fn generate_encryption_keys(&self) -> Result<(String, String)> {
        // Generate keys for order encryption/decryption
        let mut rng = OsRng;
        let secret_key = SecretKey::new(&mut rng);
        let public_key = PublicKey::from_secret_key(&self.secp, &secret_key);

        Ok((
            hex::encode(secret_key.secret_bytes()),
            hex::encode(public_key.serialize()),
        ))
    }

    fn public_key_to_address(&self, public_key: &PublicKey) -> Result<[u8; 20]> {
        use sha3::{Digest, Keccak256};

        let public_key_bytes = &public_key.serialize_uncompressed()[1..]; // Remove 0x04 prefix
        let hash = Keccak256::digest(public_key_bytes);
        let mut address = [0u8; 20];
        address.copy_from_slice(&hash[12..]);
        Ok(address)
    }

    async fn save_keys(&self, keys: &OperatorKeys, output_dir: &PathBuf) -> Result<()> {
        // Save complete keys as JSON
        let keys_json = serde_json::to_string_pretty(keys)?;
        let keys_path = output_dir.join("operator_keys.json");
        tokio::fs::write(keys_path, keys_json).await?;

        // Save individual key files
        tokio::fs::write(
            output_dir.join("ethereum_private_key.txt"),
            &keys.ethereum_private_key,
        ).await?;

        tokio::fs::write(
            output_dir.join("ethereum_address.txt"),
            &keys.ethereum_address,
        ).await?;

        tokio::fs::write(
            output_dir.join("bls_private_key.txt"),
            &keys.bls_private_key,
        ).await?;

        tokio::fs::write(
            output_dir.join("encryption_private_key.txt"),
            &keys.encryption_private_key,
        ).await?;

        // Create public keys file
        let public_keys = serde_json::json!({
            "ethereum_address": keys.ethereum_address,
            "ethereum_public_key": keys.ethereum_public_key,
            "bls_public_key": keys.bls_public_key,
            "encryption_public_key": keys.encryption_public_key,
        });

        tokio::fs::write(
            output_dir.join("public_keys.json"),
            serde_json::to_string_pretty(&public_keys)?,
        ).await?;

        // Create secure permissions for private key files
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = tokio::fs::metadata(output_dir.join("ethereum_private_key.txt")).await?.permissions();
            perms.set_mode(0o600);
            tokio::fs::set_permissions(output_dir.join("ethereum_private_key.txt"), perms).await?;
        }

        Ok(())
    }

    pub async fn load_keys(&self, keys_dir: &PathBuf) -> Result<OperatorKeys> {
        let keys_path = keys_dir.join("operator_keys.json");
        let keys_content = tokio::fs::read_to_string(keys_path).await?;
        let keys: OperatorKeys = serde_json::from_str(&keys_content)?;
        Ok(keys)
    }

    pub fn verify_keys(&self, keys: &OperatorKeys) -> Result<bool> {
        // Verify Ethereum key pair
        let private_key = keys.ethereum_private_key.strip_prefix("0x").unwrap_or(&keys.ethereum_private_key);
        let private_key_bytes = hex::decode(private_key)?;
        let secret_key = SecretKey::from_slice(&private_key_bytes)?;
        let public_key = PublicKey::from_secret_key(&self.secp, &secret_key);
        
        let computed_public_key = hex::encode(public_key.serialize());
        let expected_public_key = keys.ethereum_public_key.strip_prefix("0x").unwrap_or(&keys.ethereum_public_key);
        
        if computed_public_key != expected_public_key {
            return Ok(false);
        }

        // Verify address matches public key
        let computed_address = self.public_key_to_address(&public_key)?;
        let expected_address = keys.ethereum_address.strip_prefix("0x").unwrap_or(&keys.ethereum_address);
        let computed_address_hex = hex::encode(computed_address);
        
        if computed_address_hex != expected_address {
            return Ok(false);
        }

        Ok(true)
    }

    pub fn sign_message(&self, message: &[u8], private_key: &str) -> Result<Vec<u8>> {
        use sha3::{Digest, Keccak256};
        
        let private_key = private_key.strip_prefix("0x").unwrap_or(private_key);
        let private_key_bytes = hex::decode(private_key)?;
        let secret_key = SecretKey::from_slice(&private_key_bytes)?;

        // Ethereum-style message signing
        let prefix = format!("\x19Ethereum Signed Message:\n{}", message.len());
        let mut full_message = prefix.into_bytes();
        full_message.extend_from_slice(message);
        
        let message_hash = Keccak256::digest(&full_message);
        let message = secp256k1::Message::from_digest_slice(&message_hash)?;
        
        let signature = self.secp.sign_ecdsa_recoverable(&message, &secret_key);
        let (recovery_id, signature_bytes) = signature.serialize_compact();
        
        let mut result = signature_bytes.to_vec();
        result.push(recovery_id.to_i32() as u8);
        
        Ok(result)
    }

    pub fn encrypt_data(&self, data: &[u8], public_key: &str) -> Result<Vec<u8>> {
        use aes_gcm::{
            aead::{Aead, AeadCore, KeyInit, OsRng},
            Aes256Gcm,
        };

        // In a real implementation, would use ECIES or similar
        // For now, using AES-GCM with a key derived from the public key
        let key_bytes = hex::decode(public_key.strip_prefix("0x").unwrap_or(public_key))?;
        let key_hash = sha3::Keccak256::digest(&key_bytes);
        let cipher = Aes256Gcm::new_from_slice(&key_hash)
            .map_err(|e| anyhow::anyhow!("Failed to create cipher: {:?}", e))?;
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        
        let mut ciphertext = cipher.encrypt(&nonce, data)
            .map_err(|e| anyhow::anyhow!("Encryption failed: {:?}", e))?;
        let mut result = nonce.to_vec();
        result.append(&mut ciphertext);
        
        Ok(result)
    }

    pub fn decrypt_data(&self, encrypted_data: &[u8], private_key: &str) -> Result<Vec<u8>> {
        use aes_gcm::{
            aead::{Aead, KeyInit},
            Aes256Gcm,
        };

        if encrypted_data.len() < 12 {
            return Err(anyhow::anyhow!("Invalid encrypted data length"));
        }

        let private_key = private_key.strip_prefix("0x").unwrap_or(private_key);
        let private_key_bytes = hex::decode(private_key)?;
        let secret_key = SecretKey::from_slice(&private_key_bytes)?;
        let public_key = PublicKey::from_secret_key(&self.secp, &secret_key);
        
        let key_hash = sha3::Keccak256::digest(&public_key.serialize());
        let cipher = Aes256Gcm::new_from_slice(&key_hash)
            .map_err(|e| anyhow::anyhow!("Failed to create cipher: {:?}", e))?;
        
        let (nonce_bytes, ciphertext) = encrypted_data.split_at(12);
        let nonce = aes_gcm::Nonce::from_slice(nonce_bytes);
        
        let plaintext = cipher.decrypt(nonce, ciphertext)
            .map_err(|e| anyhow::anyhow!("Decryption failed: {:?}", e))?;
        Ok(plaintext)
    }
}

impl Default for KeyManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_key_generation() {
        let key_manager = KeyManager::new();
        let temp_dir = TempDir::new().unwrap();
        let output_path = temp_dir.path().to_path_buf();

        let keys = key_manager.generate_keys(&output_path).await.unwrap();
        
        assert!(keys.ethereum_private_key.starts_with("0x"));
        assert!(keys.ethereum_address.starts_with("0x"));
        assert!(!keys.bls_private_key.is_empty());
        assert!(!keys.encryption_private_key.is_empty());
    }

    #[tokio::test]
    async fn test_key_verification() {
        let key_manager = KeyManager::new();
        let temp_dir = TempDir::new().unwrap();
        let output_path = temp_dir.path().to_path_buf();

        let keys = key_manager.generate_keys(&output_path).await.unwrap();
        let is_valid = key_manager.verify_keys(&keys).unwrap();
        
        assert!(is_valid);
    }

    #[tokio::test]
    async fn test_save_and_load_keys() {
        let key_manager = KeyManager::new();
        let temp_dir = TempDir::new().unwrap();
        let output_path = temp_dir.path().to_path_buf();

        let original_keys = key_manager.generate_keys(&output_path).await.unwrap();
        let loaded_keys = key_manager.load_keys(&output_path).await.unwrap();
        
        assert_eq!(original_keys.ethereum_private_key, loaded_keys.ethereum_private_key);
        assert_eq!(original_keys.ethereum_address, loaded_keys.ethereum_address);
    }

    #[test]
    fn test_message_signing() {
        let key_manager = KeyManager::new();
        let (private_key, _, _) = key_manager.generate_ethereum_keys().unwrap();
        let message = b"Hello, EigenVault!";
        
        let signature = key_manager.sign_message(message, &private_key).unwrap();
        assert_eq!(signature.len(), 65); // 64 bytes signature + 1 byte recovery id
    }

    #[test]
    fn test_data_encryption() {
        let key_manager = KeyManager::new();
        let (private_key, public_key, _) = key_manager.generate_ethereum_keys().unwrap();
        let data = b"Secret order data";
        
        let encrypted = key_manager.encrypt_data(data, &public_key).unwrap();
        let decrypted = key_manager.decrypt_data(&encrypted, &private_key).unwrap();
        
        assert_eq!(data, decrypted.as_slice());
    }
}