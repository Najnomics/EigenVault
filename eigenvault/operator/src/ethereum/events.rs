use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, warn};

use crate::config::EthereumConfig;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventFilter {
    pub contract_address: String,
    pub event_signature: String,
    pub topics: Vec<Option<String>>,
    pub from_block: u64,
    pub to_block: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedEvent {
    pub contract_address: String,
    pub event_name: String,
    pub block_number: u64,
    pub transaction_hash: String,
    pub log_index: u64,
    pub parameters: HashMap<String, EventParam>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EventParam {
    Address(String),
    Uint(u64),
    Bytes(Vec<u8>),
    Bytes32(String),
    Bool(bool),
    String(String),
}

impl ParsedEvent {
    /// Get string parameter from event
    pub fn get_string_param(&self, name: &str) -> Result<String> {
        match self.parameters.get(name) {
            Some(EventParam::String(s)) => Ok(s.clone()),
            Some(EventParam::Address(addr)) => Ok(addr.clone()),
            Some(EventParam::Bytes32(hex)) => Ok(hex.clone()),
            _ => Err(anyhow::anyhow!("Parameter {} not found or wrong type", name)),
        }
    }

    /// Get uint parameter from event
    pub fn get_uint_param(&self, name: &str) -> Result<u64> {
        match self.parameters.get(name) {
            Some(EventParam::Uint(n)) => Ok(*n),
            _ => Err(anyhow::anyhow!("Parameter {} not found or wrong type", name)),
        }
    }

    /// Get bytes parameter from event
    pub fn get_bytes_param(&self, name: &str) -> Result<Vec<u8>> {
        match self.parameters.get(name) {
            Some(EventParam::Bytes(data)) => Ok(data.clone()),
            _ => Err(anyhow::anyhow!("Parameter {} not found or wrong type", name)),
        }
    }

    /// Get boolean parameter from event
    pub fn get_bool_param(&self, name: &str) -> Result<bool> {
        match self.parameters.get(name) {
            Some(EventParam::Bool(b)) => Ok(*b),
            _ => Err(anyhow::anyhow!("Parameter {} not found or wrong type", name)),
        }
    }
}

/// Event listener for Ethereum contracts
pub struct EventListener {
    config: EthereumConfig,
    contract_addresses: Vec<String>,
    event_signatures: HashMap<String, EventSignature>,
    last_processed_block: u64,
}

impl EventListener {
    pub async fn new(config: &EthereumConfig) -> Result<Self> {
        info!("Initializing event listener");
        
        let mut listener = Self {
            config: config.clone(),
            contract_addresses: Vec::new(),
            event_signatures: HashMap::new(),
            last_processed_block: 0,
        };
        
        // Load event signatures
        listener.load_event_signatures().await?;
        
        // Add contract addresses to watch
        listener.add_contract_addresses().await?;
        
        Ok(listener)
    }

    /// Load event signatures for known contracts
    async fn load_event_signatures(&mut self) -> Result<()> {
        info!("Loading event signatures");
        
        // Service Manager events
        self.event_signatures.insert(
            "TaskCreated".to_string(),
            EventSignature {
                name: "TaskCreated".to_string(),
                signature: "TaskCreated(bytes32,bytes32,uint256)".to_string(),
                signature_hash: self.keccak256("TaskCreated(bytes32,bytes32,uint256)".as_bytes()),
                indexed_params: vec![0, 1], // taskId and ordersSetHash are indexed
                param_types: vec![
                    ("taskId".to_string(), "bytes32".to_string()),
                    ("ordersSetHash".to_string(), "bytes32".to_string()),
                    ("deadline".to_string(), "uint256".to_string()),
                ],
            },
        );
        
        self.event_signatures.insert(
            "TaskCompleted".to_string(),
            EventSignature {
                name: "TaskCompleted".to_string(),
                signature: "TaskCompleted(bytes32,bytes32,address)".to_string(),
                signature_hash: self.keccak256("TaskCompleted(bytes32,bytes32,address)".as_bytes()),
                indexed_params: vec![0, 2], // taskId and operator are indexed
                param_types: vec![
                    ("taskId".to_string(), "bytes32".to_string()),
                    ("resultHash".to_string(), "bytes32".to_string()),
                    ("operator".to_string(), "address".to_string()),
                ],
            },
        );

        // Hook events
        self.event_signatures.insert(
            "OrderRoutedToVault".to_string(),
            EventSignature {
                name: "OrderRoutedToVault".to_string(),
                signature: "OrderRoutedToVault(address,bytes32,bool,uint256,bytes32)".to_string(),
                signature_hash: self.keccak256("OrderRoutedToVault(address,bytes32,bool,uint256,bytes32)".as_bytes()),
                indexed_params: vec![0, 1], // trader and orderId are indexed
                param_types: vec![
                    ("trader".to_string(), "address".to_string()),
                    ("orderId".to_string(), "bytes32".to_string()),
                    ("zeroForOne".to_string(), "bool".to_string()),
                    ("amount".to_string(), "uint256".to_string()),
                    ("commitment".to_string(), "bytes32".to_string()),
                ],
            },
        );

        self.event_signatures.insert(
            "VaultOrderExecuted".to_string(),
            EventSignature {
                name: "VaultOrderExecuted".to_string(),
                signature: "VaultOrderExecuted(bytes32,address,uint256,uint256,bytes32)".to_string(),
                signature_hash: self.keccak256("VaultOrderExecuted(bytes32,address,uint256,uint256,bytes32)".as_bytes()),
                indexed_params: vec![0, 1], // orderId and trader are indexed
                param_types: vec![
                    ("orderId".to_string(), "bytes32".to_string()),
                    ("trader".to_string(), "address".to_string()),
                    ("amountIn".to_string(), "uint256".to_string()),
                    ("amountOut".to_string(), "uint256".to_string()),
                    ("proofHash".to_string(), "bytes32".to_string()),
                ],
            },
        );

        // Order Vault events
        self.event_signatures.insert(
            "OrderStored".to_string(),
            EventSignature {
                name: "OrderStored".to_string(),
                signature: "OrderStored(bytes32,address,bytes,uint256)".to_string(),
                signature_hash: self.keccak256("OrderStored(bytes32,address,bytes,uint256)".as_bytes()),
                indexed_params: vec![0, 1], // orderId and trader are indexed
                param_types: vec![
                    ("orderId".to_string(), "bytes32".to_string()),
                    ("trader".to_string(), "address".to_string()),
                    ("encryptedOrder".to_string(), "bytes".to_string()),
                    ("timestamp".to_string(), "uint256".to_string()),
                ],
            },
        );

        info!("Loaded {} event signatures", self.event_signatures.len());
        Ok(())
    }

    /// Add contract addresses to monitor
    async fn add_contract_addresses(&mut self) -> Result<()> {
        // Add addresses from config or defaults
        self.contract_addresses.extend(vec![
            "0x1234567890123456789012345678901234567890".to_string(), // Service Manager
            "0x2345678901234567890123456789012345678901".to_string(), // EigenVault Hook
            "0x3456789012345678901234567890123456789012".to_string(), // Order Vault
        ]);
        
        info!("Monitoring {} contract addresses", self.contract_addresses.len());
        Ok(())
    }

    /// Get events for block range
    pub async fn get_events(&self, from_block: u64, to_block: u64) -> Result<Vec<ParsedEvent>> {
        debug!("Getting events from block {} to {}", from_block, to_block);
        
        let mut all_events = Vec::new();
        
        // Query events for each contract address
        for contract_address in &self.contract_addresses {
            let contract_events = self.get_contract_events(
                contract_address,
                from_block,
                to_block,
            ).await?;
            
            all_events.extend(contract_events);
        }
        
        // Sort events by block number and log index
        all_events.sort_by(|a, b| {
            a.block_number.cmp(&b.block_number)
                .then_with(|| a.log_index.cmp(&b.log_index))
        });
        
        if !all_events.is_empty() {
            info!("Retrieved {} events from blocks {} to {}", 
                  all_events.len(), from_block, to_block);
        }
        
        Ok(all_events)
    }

    /// Get events for a specific contract
    async fn get_contract_events(
        &self,
        contract_address: &str,
        from_block: u64,
        to_block: u64,
    ) -> Result<Vec<ParsedEvent>> {
        debug!("Getting events for contract: {}", contract_address);
        
        // Mock event retrieval - in production, this would use actual RPC calls
        let mock_events = self.generate_mock_events(contract_address, from_block, to_block).await?;
        
        let mut parsed_events = Vec::new();
        
        for mock_event in mock_events {
            match self.parse_log_entry(&mock_event).await {
                Ok(Some(parsed)) => parsed_events.push(parsed),
                Ok(None) => {}, // Unknown event, skip
                Err(e) => warn!("Failed to parse log entry: {:?}", e),
            }
        }
        
        Ok(parsed_events)
    }

    /// Generate mock events for testing
    async fn generate_mock_events(
        &self,
        contract_address: &str,
        from_block: u64,
        to_block: u64,
    ) -> Result<Vec<MockLogEntry>> {
        let mut mock_events = Vec::new();
        
        // Generate some mock events based on current time and blocks
        let current_time = chrono::Utc::now().timestamp() as u64;
        
        if current_time % 30 < 5 { // Generate events occasionally
            // Mock TaskCreated event
            if contract_address.ends_with("90") { // Service Manager
                mock_events.push(MockLogEntry {
                    address: contract_address.to_string(),
                    topics: vec![
                        hex::encode(self.keccak256("TaskCreated(bytes32,bytes32,uint256)".as_bytes())),
                        format!("task_{}", current_time % 1000), // taskId
                        format!("orders_hash_{}", current_time % 1000), // ordersSetHash  
                    ],
                    data: hex::encode((current_time + 3600).to_le_bytes()), // deadline
                    block_number: from_block + 1,
                    transaction_hash: format!("0x{:x}", current_time),
                    log_index: 0,
                });
            }
            
            // Mock OrderStored event
            if contract_address.ends_with("12") { // Order Vault
                mock_events.push(MockLogEntry {
                    address: contract_address.to_string(),
                    topics: vec![
                        hex::encode(self.keccak256("OrderStored(bytes32,address,bytes,uint256)".as_bytes())),
                        format!("order_{}", current_time % 1000), // orderId
                        format!("0x{:040x}", current_time % 1000000), // trader address
                    ],
                    data: hex::encode(format!("encrypted_order_data_{}", current_time).as_bytes()),
                    block_number: from_block + 1,  
                    transaction_hash: format!("0x{:x}", current_time + 1),
                    log_index: 1,
                });
            }
        }
        
        Ok(mock_events)
    }

    /// Parse raw log entry into typed event
    async fn parse_log_entry(&self, log_entry: &MockLogEntry) -> Result<Option<ParsedEvent>> {
        if log_entry.topics.is_empty() {
            return Ok(None);
        }
        
        // Find matching event signature by topic[0] (event signature hash)
        let event_signature_hash = &log_entry.topics[0];
        
        let event_signature = self.event_signatures.values()
            .find(|sig| hex::encode(&sig.signature_hash) == *event_signature_hash);
        
        let event_signature = match event_signature {
            Some(sig) => sig,
            None => {
                debug!("Unknown event signature: {}", event_signature_hash);
                return Ok(None);
            }
        };
        
        debug!("Parsing event: {}", event_signature.name);
        
        // Parse parameters
        let mut parameters = HashMap::new();
        
        // Parse indexed parameters from topics
        let mut topic_index = 1; // Skip topic[0] which is event signature
        for (param_index, indexed_param) in event_signature.indexed_params.iter().enumerate() {
            if topic_index < log_entry.topics.len() {
                let (param_name, param_type) = &event_signature.param_types[*indexed_param];
                let topic_value = &log_entry.topics[topic_index];
                
                let param_value = self.decode_event_param(param_type, topic_value, true)?;
                parameters.insert(param_name.clone(), param_value);
                
                topic_index += 1;
            }
        }
        
        // Parse non-indexed parameters from data
        if !log_entry.data.is_empty() {
            let data_bytes = hex::decode(&log_entry.data)?;
            
            // Find non-indexed parameters
            for (param_index, (param_name, param_type)) in event_signature.param_types.iter().enumerate() {
                if !event_signature.indexed_params.contains(&param_index) {
                    // For simplicity, we'll decode based on position
                    // In production, this would use proper ABI decoding
                    let param_value = self.decode_event_param(param_type, &log_entry.data, false)?;
                    parameters.insert(param_name.clone(), param_value);
                }
            }
        }
        
        let parsed_event = ParsedEvent {
            contract_address: log_entry.address.clone(),
            event_name: event_signature.name.clone(),
            block_number: log_entry.block_number,
            transaction_hash: log_entry.transaction_hash.clone(),
            log_index: log_entry.log_index,
            parameters,
        };
        
        debug!("Parsed event: {} with {} parameters", 
               parsed_event.event_name, parsed_event.parameters.len());
        
        Ok(Some(parsed_event))
    }

    /// Decode event parameter based on type
    fn decode_event_param(&self, param_type: &str, raw_value: &str, is_indexed: bool) -> Result<EventParam> {
        match param_type {
            "address" => Ok(EventParam::Address(raw_value.to_string())),
            "bytes32" => Ok(EventParam::Bytes32(raw_value.to_string())),
            "uint256" => {
                // Simplified uint decoding
                let numeric_value = raw_value.len() as u64; // Mock conversion
                Ok(EventParam::Uint(numeric_value))
            }
            "bool" => {
                let bool_value = !raw_value.is_empty();
                Ok(EventParam::Bool(bool_value))
            }
            "bytes" => {
                let bytes_value = hex::decode(raw_value).unwrap_or_default();
                Ok(EventParam::Bytes(bytes_value))
            }
            "string" => Ok(EventParam::String(raw_value.to_string())),
            _ => {
                warn!("Unknown parameter type: {}", param_type);
                Ok(EventParam::String(raw_value.to_string()))
            }
        }
    }

    /// Keccak256 hash (simplified)
    fn keccak256(&self, data: &[u8]) -> Vec<u8> {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }

    /// Update last processed block
    pub fn update_last_processed_block(&mut self, block_number: u64) {
        self.last_processed_block = block_number;
    }

    /// Get last processed block
    pub fn get_last_processed_block(&self) -> u64 {
        self.last_processed_block
    }

    /// Add contract address to monitor
    pub fn add_contract_address(&mut self, address: String) {
        if !self.contract_addresses.contains(&address) {
            self.contract_addresses.push(address);
            info!("Added contract address to monitoring");
        }
    }

    /// Remove contract address from monitoring
    pub fn remove_contract_address(&mut self, address: &str) {
        self.contract_addresses.retain(|addr| addr != address);
        info!("Removed contract address from monitoring");
    }
}

/// Event signature definition
#[derive(Debug, Clone)]
struct EventSignature {
    name: String,
    signature: String,
    signature_hash: Vec<u8>,
    indexed_params: Vec<usize>, // Indices of indexed parameters
    param_types: Vec<(String, String)>, // (name, type)
}

/// Mock log entry for testing
#[derive(Debug, Clone)]
struct MockLogEntry {
    address: String,
    topics: Vec<String>,
    data: String,
    block_number: u64,
    transaction_hash: String,
    log_index: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::EthereumConfig;

    #[tokio::test]
    async fn test_event_listener_creation() {
        let config = EthereumConfig::default();
        let listener = EventListener::new(&config).await;
        assert!(listener.is_ok());
    }

    #[tokio::test]
    async fn test_event_signatures_loaded() {
        let config = EthereumConfig::default();
        let listener = EventListener::new(&config).await.unwrap();
        
        assert!(listener.event_signatures.contains_key("TaskCreated"));
        assert!(listener.event_signatures.contains_key("OrderStored"));
    }

    #[test]
    fn test_parsed_event_getters() {
        let mut parameters = HashMap::new();
        parameters.insert("testUint".to_string(), EventParam::Uint(123));
        parameters.insert("testString".to_string(), EventParam::String("test".to_string()));
        parameters.insert("testBool".to_string(), EventParam::Bool(true));
        
        let event = ParsedEvent {
            contract_address: "0x123".to_string(),
            event_name: "TestEvent".to_string(),
            block_number: 100,
            transaction_hash: "0xabc".to_string(),
            log_index: 0,
            parameters,
        };
        
        assert_eq!(event.get_uint_param("testUint").unwrap(), 123);
        assert_eq!(event.get_string_param("testString").unwrap(), "test");
        assert_eq!(event.get_bool_param("testBool").unwrap(), true);
    }
}

/// Ethereum events that the operator needs to handle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EthereumEvent {
    TaskCreated {
        task_id: String,
        orders_hash: String,
        deadline: u64,
    },
    OrderStored {
        order_id: String,
        trader: String,
        encrypted_order: Vec<u8>,
    },
    ProofSubmitted {
        task_id: String,
        operator: String,
        proof_hash: String,
    },
    TaskCompleted {
        task_id: String,
        result_hash: String,
    },
}

/// Event processor that handles parsed events
pub struct EventProcessor {
    config: EthereumConfig,
}

impl EventProcessor {
    pub fn new(config: EthereumConfig) -> Self {
        Self { config }
    }

    /// Process parsed event and convert to EthereumEvent
    pub fn process_event(&self, parsed_event: ParsedEvent) -> Result<EthereumEvent> {
        match parsed_event.event_name.as_str() {
            "TaskCreated" => {
                let task_id = parsed_event.get_string_param("taskId")?;
                let orders_hash = parsed_event.get_string_param("ordersHash")?;
                let deadline = parsed_event.get_uint_param("deadline")?;
                
                Ok(EthereumEvent::TaskCreated {
                    task_id,
                    orders_hash,
                    deadline,
                })
            }
            "OrderStored" => {
                let order_id = parsed_event.get_string_param("orderId")?;
                let trader = parsed_event.get_string_param("trader")?;
                let encrypted_order = parsed_event.get_bytes_param("encryptedOrder")?;
                
                Ok(EthereumEvent::OrderStored {
                    order_id,
                    trader,
                    encrypted_order,
                })
            }
            "ProofSubmitted" => {
                let task_id = parsed_event.get_string_param("taskId")?;
                let operator = parsed_event.get_string_param("operator")?;
                let proof_hash = parsed_event.get_string_param("proofHash")?;
                
                Ok(EthereumEvent::ProofSubmitted {
                    task_id,
                    operator,
                    proof_hash,
                })
            }
            "TaskCompleted" => {
                let task_id = parsed_event.get_string_param("taskId")?;
                let result_hash = parsed_event.get_string_param("resultHash")?;
                
                Ok(EthereumEvent::TaskCompleted {
                    task_id,
                    result_hash,
                })
            }
            _ => Err(anyhow::anyhow!("Unknown event type: {}", parsed_event.event_name)),
        }
    }

    /// Get recent events from the blockchain
    pub async fn get_events(&self, from_block: u64, to_block: u64) -> Result<Vec<EthereumEvent>> {
        // In a real implementation, this would query the blockchain for events
        // For now, return empty vector
        info!("Getting events from block {} to {}", from_block, to_block);
        Ok(vec![])
    }
}