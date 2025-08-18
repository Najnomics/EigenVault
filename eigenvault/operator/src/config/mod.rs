use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub mod keys;
pub mod settings;

pub use keys::KeyManager;
pub use settings::{Settings, EthereumConfig, MatchingConfig, NetworkingConfig, ProofConfig};

// Re-export unified config
pub type Config = Settings;

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert!(!config.ethereum.rpc_url.is_empty());
        assert!(config.networking.listen_port > 0);
    }

    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let serialized = toml::to_string(&config).unwrap();
        let deserialized: Config = toml::from_str(&serialized).unwrap();
        
        assert_eq!(config.ethereum.rpc_url, deserialized.ethereum.rpc_url);
        assert_eq!(config.networking.listen_port, deserialized.networking.listen_port);
    }

    #[test]
    fn test_config_save_load() -> Result<()> {
        let config = Config::default();
        let temp_file = NamedTempFile::new().unwrap();
        
        config.save(temp_file.path())?;
        let loaded_config = Config::load(temp_file.path())?;
        
        assert_eq!(config.ethereum.rpc_url, loaded_config.ethereum.rpc_url);
        Ok(())
    }

    #[test]
    fn test_config_validation() -> Result<()> {
        let mut config = Config::default();
        
        // Should fail with default operator address
        assert!(config.validate().is_err());
        
        // Set valid addresses
        config.ethereum.operator_address = "0x1234567890123456789012345678901234567890".to_string();
        config.ethereum.private_key = "0x1234567890123456789012345678901234567890123456789012345678901234".to_string();
        
        assert!(config.validate().is_ok());
        Ok(())
    }
}