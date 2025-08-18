use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub ethereum: EthereumConfig,
    pub matching: MatchingConfig,
    pub networking: NetworkingConfig,
    pub proofs: ProofConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EthereumConfig {
    pub rpc_url: String,
    pub operator_address: String,
    pub private_key: String,
    pub service_manager_address: String,
    pub eigenvault_hook_address: String,
    pub order_vault_address: String,
    pub gas_limit: u64,
    pub gas_price: u64,
    pub confirmation_blocks: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchingConfig {
    pub max_pending_orders: usize,
    pub matching_interval_ms: u64,
    pub price_tolerance_bps: u64,
    pub max_slippage_bps: u64,
    pub order_timeout_seconds: u64,
    pub enable_cross_pool_matching: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkingConfig {
    pub listen_port: u16,
    pub bootstrap_peers: Vec<String>,
    pub min_peers: usize,
    pub max_peers: usize,
    pub connection_timeout_seconds: u64,
    pub gossip_interval_ms: u64,
    pub enable_encryption: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProofConfig {
    pub circuit_path: String,
    pub proving_key_path: String,
    pub verification_key_path: String,
    pub max_proof_size: usize,
    pub proof_timeout_seconds: u64,
    pub enable_batch_proving: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            ethereum: EthereumConfig::default(),
            matching: MatchingConfig::default(),
            networking: NetworkingConfig::default(),
            proofs: ProofConfig::default(),
        }
    }
}

impl Default for EthereumConfig {
    fn default() -> Self {
        Self {
            rpc_url: "https://holesky.infura.io/v3/YOUR_PROJECT_ID".to_string(),
            operator_address: "0x0000000000000000000000000000000000000000".to_string(),
            private_key: "0x0000000000000000000000000000000000000000000000000000000000000000".to_string(),
            service_manager_address: "0x1234567890123456789012345678901234567890".to_string(),
            eigenvault_hook_address: "0x2345678901234567890123456789012345678901".to_string(),
            order_vault_address: "0x3456789012345678901234567890123456789012".to_string(),
            gas_limit: 500_000,
            gas_price: 20_000_000_000, // 20 gwei
            confirmation_blocks: 3,
        }
    }
}

impl Default for MatchingConfig {
    fn default() -> Self {
        Self {
            max_pending_orders: 1000,
            matching_interval_ms: 100,
            price_tolerance_bps: 10, // 0.1%
            max_slippage_bps: 50, // 0.5%
            order_timeout_seconds: 3600, // 1 hour
            enable_cross_pool_matching: true,
        }
    }
}

impl Default for NetworkingConfig {
    fn default() -> Self {
        Self {
            listen_port: 9000,
            bootstrap_peers: vec![
                "127.0.0.1:9001".to_string(),
                "127.0.0.1:9002".to_string(),
            ],
            min_peers: 3,
            max_peers: 50,
            connection_timeout_seconds: 30,
            gossip_interval_ms: 1000,
            enable_encryption: true,
        }
    }
}

impl Default for ProofConfig {
    fn default() -> Self {
        Self {
            circuit_path: "./circuits".to_string(),
            proving_key_path: "./keys/proving.key".to_string(),
            verification_key_path: "./keys/verification.key".to_string(),
            max_proof_size: 1_048_576, // 1MB
            proof_timeout_seconds: 300, // 5 minutes
            enable_batch_proving: true,
        }
    }
}

impl Settings {
    /// Load settings from TOML file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let contents = std::fs::read_to_string(path)?;
        let settings: Settings = toml::from_str(&contents)?;
        Ok(settings)
    }

    /// Save settings to TOML file
    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let contents = toml::to_string_pretty(self)?;
        std::fs::write(path, contents)?;
        Ok(())
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<()> {
        // Validate Ethereum config
        if self.ethereum.rpc_url.is_empty() {
            return Err(anyhow::anyhow!("Ethereum RPC URL is required"));
        }

        if self.ethereum.operator_address.is_empty() || self.ethereum.operator_address == "0x0000000000000000000000000000000000000000" {
            return Err(anyhow::anyhow!("Valid operator address is required"));
        }

        if self.ethereum.private_key.is_empty() || self.ethereum.private_key == "0x0000000000000000000000000000000000000000000000000000000000000000" {
            return Err(anyhow::anyhow!("Valid private key is required"));
        }

        // Validate matching config
        if self.matching.max_pending_orders == 0 {
            return Err(anyhow::anyhow!("Max pending orders must be greater than 0"));
        }

        if self.matching.matching_interval_ms == 0 {
            return Err(anyhow::anyhow!("Matching interval must be greater than 0"));
        }

        // Validate networking config
        if self.networking.listen_port == 0 {
            return Err(anyhow::anyhow!("Listen port must be greater than 0"));
        }

        if self.networking.min_peers > self.networking.max_peers {
            return Err(anyhow::anyhow!("Min peers cannot be greater than max peers"));
        }

        // Validate proof config
        if self.proofs.max_proof_size == 0 {
            return Err(anyhow::anyhow!("Max proof size must be greater than 0"));
        }

        if self.proofs.proof_timeout_seconds == 0 {
            return Err(anyhow::anyhow!("Proof timeout must be greater than 0"));
        }

        Ok(())
    }

    /// Get environment-specific overrides
    pub fn apply_env_overrides(&mut self) -> Result<()> {
        use std::env;

        // Ethereum overrides
        if let Ok(rpc_url) = env::var("ETHEREUM_RPC_URL") {
            self.ethereum.rpc_url = rpc_url;
        }

        if let Ok(operator_address) = env::var("OPERATOR_ADDRESS") {
            self.ethereum.operator_address = operator_address;
        }

        if let Ok(private_key) = env::var("OPERATOR_PRIVATE_KEY") {
            self.ethereum.private_key = private_key;
        }

        if let Ok(service_manager) = env::var("SERVICE_MANAGER_ADDRESS") {
            self.ethereum.service_manager_address = service_manager;
        }

        // Networking overrides
        if let Ok(listen_port) = env::var("LISTEN_PORT") {
            if let Ok(port) = listen_port.parse::<u16>() {
                self.networking.listen_port = port;
            }
        }

        if let Ok(bootstrap_peers) = env::var("BOOTSTRAP_PEERS") {
            self.networking.bootstrap_peers = bootstrap_peers
                .split(',')
                .map(|s| s.trim().to_string())
                .collect();
        }

        // Proof config overrides
        if let Ok(circuit_path) = env::var("CIRCUIT_PATH") {
            self.proofs.circuit_path = circuit_path;
        }

        Ok(())
    }

    /// Create development configuration
    pub fn development() -> Self {
        let mut config = Self::default();
        
        // Use local network settings
        config.ethereum.rpc_url = "http://localhost:8545".to_string();
        config.networking.bootstrap_peers = vec![
            "127.0.0.1:9001".to_string(),
        ];
        
        // More permissive settings for development
        config.matching.matching_interval_ms = 1000; // 1 second
        config.networking.min_peers = 1;
        config.proofs.proof_timeout_seconds = 60; // 1 minute
        
        config
    }

    /// Create production configuration
    pub fn production() -> Self {
        let mut config = Self::default();
        
        // Production Ethereum settings
        config.ethereum.rpc_url = "https://mainnet.infura.io/v3/YOUR_PROJECT_ID".to_string();
        config.ethereum.gas_price = 30_000_000_000; // 30 gwei
        config.ethereum.confirmation_blocks = 12;
        
        // Production networking
        config.networking.min_peers = 10;
        config.networking.max_peers = 100;
        
        // Stricter matching settings
        config.matching.max_pending_orders = 10000;
        config.matching.price_tolerance_bps = 5; // 0.05%
        
        // Production proof settings
        config.proofs.proof_timeout_seconds = 600; // 10 minutes
        
        config
    }

    /// Create testnet configuration
    pub fn testnet() -> Self {
        let mut config = Self::default();
        
        // Holesky testnet settings
        config.ethereum.rpc_url = "https://holesky.infura.io/v3/YOUR_PROJECT_ID".to_string();
        config.ethereum.gas_price = 10_000_000_000; // 10 gwei
        config.ethereum.confirmation_blocks = 3;
        
        // Testnet networking
        config.networking.min_peers = 3;
        config.networking.max_peers = 20;
        
        config
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_default_settings() {
        let settings = Settings::default();
        assert!(!settings.ethereum.rpc_url.is_empty());
        assert!(settings.matching.max_pending_orders > 0);
        assert!(settings.networking.listen_port > 0);
        assert!(settings.proofs.max_proof_size > 0);
    }

    #[test]
    fn test_settings_validation() {
        let mut settings = Settings::default();
        
        // Valid settings should pass
        assert!(settings.validate().is_ok());
        
        // Invalid operator address should fail
        settings.ethereum.operator_address = "".to_string();
        assert!(settings.validate().is_err());
        
        // Reset and test invalid matching config
        settings = Settings::default();
        settings.matching.max_pending_orders = 0;
        assert!(settings.validate().is_err());
    }

    #[test]
    fn test_save_load_settings() -> Result<()> {
        let dir = tempdir()?;
        let file_path = dir.path().join("test_config.toml");
        
        let original_settings = Settings::default();
        original_settings.save(&file_path)?;
        
        let loaded_settings = Settings::load(&file_path)?;
        
        assert_eq!(original_settings.ethereum.rpc_url, loaded_settings.ethereum.rpc_url);
        assert_eq!(original_settings.matching.max_pending_orders, loaded_settings.matching.max_pending_orders);
        
        Ok(())
    }

    #[test]
    fn test_development_config() {
        let config = Settings::development();
        assert_eq!(config.ethereum.rpc_url, "http://localhost:8545");
        assert_eq!(config.networking.min_peers, 1);
    }

    #[test]
    fn test_production_config() {
        let config = Settings::production();
        assert!(config.ethereum.rpc_url.contains("mainnet"));
        assert!(config.networking.min_peers >= 10);
        assert!(config.matching.price_tolerance_bps <= 10);
    }
}