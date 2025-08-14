use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub mod keys;
pub mod settings;

pub use keys::KeyManager;
pub use settings::Settings;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub ethereum: EthereumConfig,
    pub matching: MatchingConfig,
    pub networking: NetworkingConfig,
    pub proofs: ProofsConfig,
    pub database: DatabaseConfig,
    pub logging: LoggingConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthereumConfig {
    pub rpc_url: String,
    pub ws_url: String,
    pub private_key: String,
    pub service_manager_address: String,
    pub hook_address: String,
    pub order_vault_address: String,
    pub chain_id: u64,
    pub gas_limit: u64,
    pub gas_price_gwei: u64,
    pub confirmation_blocks: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchingConfig {
    pub max_orders_per_batch: usize,
    pub matching_interval_ms: u64,
    pub price_tolerance_bps: u64,
    pub max_slippage_bps: u64,
    pub min_order_size: String, // Wei amount
    pub max_order_size: String, // Wei amount
    pub enable_cross_token_matching: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkingConfig {
    pub listen_port: u16,
    pub bootstrap_peers: Vec<String>,
    pub max_peers: usize,
    pub gossip_heartbeat_interval_ms: u64,
    pub discovery_enabled: bool,
    pub nat_traversal: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofsConfig {
    pub proving_key_path: String,
    pub verification_key_path: String,
    pub circuit_path: String,
    pub max_proof_generation_time_s: u64,
    pub enable_proof_caching: bool,
    pub proof_cache_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub connection_timeout_s: u64,
    pub enable_migrations: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    pub level: String,
    pub format: String,
    pub output: String,
    pub rotation: String,
    pub max_files: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            ethereum: EthereumConfig {
                rpc_url: "https://sepolia.unichain.org".to_string(),
                ws_url: "wss://sepolia.unichain.org/ws".to_string(),
                private_key: "YOUR_PRIVATE_KEY_HERE".to_string(),
                service_manager_address: "0x0000000000000000000000000000000000000000".to_string(),
                hook_address: "0x0000000000000000000000000000000000000000".to_string(),
                order_vault_address: "0x0000000000000000000000000000000000000000".to_string(),
                chain_id: 1301, // Unichain Sepolia
                gas_limit: 500000,
                gas_price_gwei: 20,
                confirmation_blocks: 1,
            },
            matching: MatchingConfig {
                max_orders_per_batch: 100,
                matching_interval_ms: 100,
                price_tolerance_bps: 10, // 0.1%
                max_slippage_bps: 50,    // 0.5%
                min_order_size: "1000000000000000000".to_string(), // 1 ETH
                max_order_size: "1000000000000000000000".to_string(), // 1000 ETH
                enable_cross_token_matching: true,
            },
            networking: NetworkingConfig {
                listen_port: 9000,
                bootstrap_peers: vec![],
                max_peers: 50,
                gossip_heartbeat_interval_ms: 1000,
                discovery_enabled: true,
                nat_traversal: true,
            },
            proofs: ProofsConfig {
                proving_key_path: "./circuits/build/proving_key.json".to_string(),
                verification_key_path: "./circuits/build/verification_key.json".to_string(),
                circuit_path: "./circuits/build/".to_string(),
                max_proof_generation_time_s: 30,
                enable_proof_caching: true,
                proof_cache_size: 1000,
            },
            database: DatabaseConfig {
                url: "sqlite://./operator.db".to_string(),
                max_connections: 10,
                connection_timeout_s: 30,
                enable_migrations: true,
            },
            logging: LoggingConfig {
                level: "info".to_string(),
                format: "json".to_string(),
                output: "stdout".to_string(),
                rotation: "daily".to_string(),
                max_files: 7,
            },
        }
    }
}

impl Config {
    pub fn load<P: AsRef<std::path::Path>>(path: P) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    pub fn save<P: AsRef<std::path::Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }

    pub fn validate(&self) -> Result<()> {
        // Validate Ethereum config
        if self.ethereum.private_key == "YOUR_PRIVATE_KEY_HERE" {
            return Err(anyhow::anyhow!("Private key not configured"));
        }

        if self.ethereum.service_manager_address.starts_with("0x000000") {
            return Err(anyhow::anyhow!("Service manager address not configured"));
        }

        // Validate other configurations
        if self.networking.listen_port == 0 {
            return Err(anyhow::anyhow!("Invalid listen port"));
        }

        if self.matching.max_orders_per_batch == 0 {
            return Err(anyhow::anyhow!("Invalid max orders per batch"));
        }

        Ok(())
    }

    pub fn get_operator_address(&self) -> Result<String> {
        use ethers::signers::Wallet;
        use ethers::types::Address;
        
        let wallet: Wallet<ethers::signers::coins_bip39::English> = self.ethereum.private_key.parse()?;
        let address: Address = wallet.address();
        Ok(format!("{:?}", address))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.ethereum.chain_id, 1301);
        assert_eq!(config.networking.listen_port, 9000);
    }

    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let serialized = toml::to_string(&config).unwrap();
        let deserialized: Config = toml::from_str(&serialized).unwrap();
        
        assert_eq!(config.ethereum.chain_id, deserialized.ethereum.chain_id);
        assert_eq!(config.networking.listen_port, deserialized.networking.listen_port);
    }

    #[test]
    fn test_config_save_load() {
        let config = Config::default();
        let temp_file = NamedTempFile::new().unwrap();
        
        config.save(temp_file.path()).unwrap();
        let loaded_config = Config::load(temp_file.path()).unwrap();
        
        assert_eq!(config.ethereum.chain_id, loaded_config.ethereum.chain_id);
    }

    #[test]
    fn test_config_validation() {
        let mut config = Config::default();
        
        // Should fail with default private key
        assert!(config.validate().is_err());
        
        // Set valid private key and addresses
        config.ethereum.private_key = "0x1234567890123456789012345678901234567890123456789012345678901234".to_string();
        config.ethereum.service_manager_address = "0x1234567890123456789012345678901234567890".to_string();
        
        assert!(config.validate().is_ok());
    }
}