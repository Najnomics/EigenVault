use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, warn};

use crate::config::EthereumConfig;
use super::OperatorInfo;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractCall {
    pub to: String,
    pub data: Vec<u8>,
    pub value: u64,
    pub gas_limit: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractAddresses {
    pub service_manager: String,
    pub eigenvault_hook: String,
    pub order_vault: String,
    pub pool_manager: String,
}

impl Default for ContractAddresses {
    fn default() -> Self {
        Self {
            service_manager: "0x1234567890123456789012345678901234567890".to_string(),
            eigenvault_hook: "0x2345678901234567890123456789012345678901".to_string(),
            order_vault: "0x3456789012345678901234567890123456789012".to_string(),
            pool_manager: "0x4567890123456789012345678901234567890123".to_string(),
        }
    }
}

/// Manager for all contract interactions
pub struct ContractManager {
    config: EthereumConfig,
    addresses: ContractAddresses,
    abis: HashMap<String, ContractAbi>,
}

impl ContractManager {
    pub async fn new(config: &EthereumConfig) -> Result<Self> {
        info!("Initializing contract manager");
        
        let addresses = ContractAddresses::default();
        let mut abis = HashMap::new();
        
        // Load contract ABIs
        abis.insert("ServiceManager".to_string(), Self::load_service_manager_abi()?);
        abis.insert("EigenVaultHook".to_string(), Self::load_hook_abi()?);
        abis.insert("OrderVault".to_string(), Self::load_order_vault_abi()?);
        
        Ok(Self {
            config: config.clone(),
            addresses,
            abis,
        })
    }

    /// Load service manager contract ABI
    fn load_service_manager_abi() -> Result<ContractAbi> {
        Ok(ContractAbi {
            contract_name: "SimplifiedServiceManager".to_string(),
            functions: vec![
                FunctionSignature {
                    name: "registerOperator".to_string(),
                    inputs: vec![
                        ("operator".to_string(), "address".to_string()),
                        ("signature".to_string(), "bytes".to_string()),
                    ],
                    outputs: vec![],
                },
                FunctionSignature {
                    name: "submitTaskResponse".to_string(),
                    inputs: vec![
                        ("taskId".to_string(), "bytes32".to_string()),
                        ("resultHash".to_string(), "bytes32".to_string()),
                        ("zkProof".to_string(), "bytes".to_string()),
                        ("operatorSignatures".to_string(), "bytes".to_string()),
                    ],
                    outputs: vec![],
                },
                FunctionSignature {
                    name: "getOperatorMetrics".to_string(),
                    inputs: vec![("operator".to_string(), "address".to_string())],
                    outputs: vec![
                        ("tasksCompleted".to_string(), "uint256".to_string()),
                        ("totalRewards".to_string(), "uint256".to_string()),
                        ("isActive".to_string(), "bool".to_string()),
                    ],
                },
            ],
            events: vec![
                EventSignature {
                    name: "TaskCreated".to_string(),
                    inputs: vec![
                        ("taskId".to_string(), "bytes32".to_string(), true),
                        ("ordersSetHash".to_string(), "bytes32".to_string(), true),
                        ("deadline".to_string(), "uint256".to_string(), false),
                    ],
                },
                EventSignature {
                    name: "TaskCompleted".to_string(),
                    inputs: vec![
                        ("taskId".to_string(), "bytes32".to_string(), true),
                        ("resultHash".to_string(), "bytes32".to_string(), false),
                        ("operator".to_string(), "address".to_string(), true),
                    ],
                },
            ],
        })
    }

    /// Load hook contract ABI  
    fn load_hook_abi() -> Result<ContractAbi> {
        Ok(ContractAbi {
            contract_name: "SimplifiedEigenVaultHook".to_string(),
            functions: vec![
                FunctionSignature {
                    name: "executeVaultOrder".to_string(),
                    inputs: vec![
                        ("orderId".to_string(), "bytes32".to_string()),
                        ("proof".to_string(), "bytes".to_string()),
                        ("signatures".to_string(), "bytes".to_string()),
                    ],
                    outputs: vec![],
                },
                FunctionSignature {
                    name: "getOrder".to_string(),
                    inputs: vec![("orderId".to_string(), "bytes32".to_string())],
                    outputs: vec![
                        ("trader".to_string(), "address".to_string()),
                        ("amount".to_string(), "uint256".to_string()),
                        ("executed".to_string(), "bool".to_string()),
                    ],
                },
            ],
            events: vec![
                EventSignature {
                    name: "OrderRoutedToVault".to_string(),
                    inputs: vec![
                        ("trader".to_string(), "address".to_string(), true),
                        ("orderId".to_string(), "bytes32".to_string(), true),
                        ("amount".to_string(), "uint256".to_string(), false),
                    ],
                },
                EventSignature {
                    name: "VaultOrderExecuted".to_string(),
                    inputs: vec![
                        ("orderId".to_string(), "bytes32".to_string(), true),
                        ("trader".to_string(), "address".to_string(), true),
                        ("amountIn".to_string(), "uint256".to_string(), false),
                        ("amountOut".to_string(), "uint256".to_string(), false),
                    ],
                },
            ],
        })
    }

    /// Load order vault contract ABI
    fn load_order_vault_abi() -> Result<ContractAbi> {
        Ok(ContractAbi {
            contract_name: "OrderVault".to_string(),
            functions: vec![
                FunctionSignature {
                    name: "storeOrder".to_string(),
                    inputs: vec![
                        ("orderId".to_string(), "bytes32".to_string()),
                        ("trader".to_string(), "address".to_string()),
                        ("encryptedOrder".to_string(), "bytes".to_string()),
                        ("deadline".to_string(), "uint256".to_string()),
                    ],
                    outputs: vec![],
                },
                FunctionSignature {
                    name: "retrieveOrder".to_string(),
                    inputs: vec![("orderId".to_string(), "bytes32".to_string())],
                    outputs: vec![("encryptedOrder".to_string(), "bytes".to_string())],
                },
                FunctionSignature {
                    name: "getActiveOrderIds".to_string(),
                    inputs: vec![
                        ("startIndex".to_string(), "uint256".to_string()),
                        ("count".to_string(), "uint256".to_string()),
                    ],
                    outputs: vec![("orderIds".to_string(), "bytes32[]".to_string())],
                },
            ],
            events: vec![
                EventSignature {
                    name: "OrderStored".to_string(),
                    inputs: vec![
                        ("orderId".to_string(), "bytes32".to_string(), true),
                        ("trader".to_string(), "address".to_string(), true),
                        ("encryptedOrder".to_string(), "bytes".to_string(), false),
                    ],
                },
                EventSignature {
                    name: "OrderRetrieved".to_string(),
                    inputs: vec![
                        ("orderId".to_string(), "bytes32".to_string(), true),
                        ("operator".to_string(), "address".to_string(), true),
                    ],
                },
            ],
        })
    }

    /// Register operator with the service manager
    pub async fn call_register_operator(&self, operator: &str, signature: &[u8]) -> Result<String> {
        info!("Calling registerOperator for: {}", operator);
        
        let function_data = self.encode_function_call(
            "ServiceManager",
            "registerOperator",
            &[
                EncodedParam::Address(operator.to_string()),
                EncodedParam::Bytes(signature.to_vec()),
            ],
        )?;
        
        let contract_call = ContractCall {
            to: self.addresses.service_manager.clone(),
            data: function_data,
            value: 0,
            gas_limit: 200_000,
        };
        
        let tx_hash = self.send_transaction(contract_call).await?;
        info!("Register operator transaction sent: {}", tx_hash);
        
        Ok(tx_hash)
    }

    /// Submit task response to service manager
    pub async fn call_submit_task_response(&self, task_id: &str, response_data: &[u8]) -> Result<String> {
        info!("Calling submitTaskResponse for task: {}", task_id);
        
        // Hash the response data
        let result_hash = self.hash_data(response_data);
        
        let function_data = self.encode_function_call(
            "ServiceManager",
            "submitTaskResponse",
            &[
                EncodedParam::Bytes32(task_id.to_string()),
                EncodedParam::Bytes32(hex::encode(&result_hash)),
                EncodedParam::Bytes(response_data.to_vec()),
                EncodedParam::Bytes(vec![0u8; 65]), // Mock signature
            ],
        )?;
        
        let contract_call = ContractCall {
            to: self.addresses.service_manager.clone(),
            data: function_data,
            value: 0,
            gas_limit: 300_000,
        };
        
        let tx_hash = self.send_transaction(contract_call).await?;
        info!("Submit task response transaction sent: {}", tx_hash);
        
        Ok(tx_hash)
    }

    /// Execute vault order through hook contract
    pub async fn call_execute_vault_order(
        &self,
        order_id: &str,
        proof: &[u8],
        signature: &[u8],
    ) -> Result<String> {
        info!("Calling executeVaultOrder for order: {}", order_id);
        
        let function_data = self.encode_function_call(
            "EigenVaultHook",
            "executeVaultOrder",
            &[
                EncodedParam::Bytes32(order_id.to_string()),
                EncodedParam::Bytes(proof.to_vec()),
                EncodedParam::Bytes(signature.to_vec()),
            ],
        )?;
        
        let contract_call = ContractCall {
            to: self.addresses.eigenvault_hook.clone(),
            data: function_data,
            value: 0,
            gas_limit: 400_000,
        };
        
        let tx_hash = self.send_transaction(contract_call).await?;
        info!("Execute vault order transaction sent: {}", tx_hash);
        
        Ok(tx_hash)
    }

    /// Get operator information from service manager
    pub async fn call_get_operator_info(&self, operator: &str) -> Result<OperatorInfo> {
        debug!("Calling getOperatorMetrics for: {}", operator);
        
        let function_data = self.encode_function_call(
            "ServiceManager",
            "getOperatorMetrics",
            &[EncodedParam::Address(operator.to_string())],
        )?;
        
        let result = self.call_contract(
            &self.addresses.service_manager,
            &function_data,
        ).await?;
        
        // Decode result (simplified)
        let info = OperatorInfo {
            address: operator.to_string(),
            stake: 32_000_000_000_000_000_000u64, // 32 ETH in wei (mock)
            is_active: true,
            tasks_completed: result.len() as u64 % 100, // Mock based on result
            last_active: chrono::Utc::now().timestamp() as u64,
        };
        
        Ok(info)
    }

    /// Get task orders from order vault
    pub async fn call_get_task_orders(&self, task_id: &str) -> Result<Vec<Vec<u8>>> {
        debug!("Getting orders for task: {}", task_id);
        
        // First get active order IDs
        let function_data = self.encode_function_call(
            "OrderVault", 
            "getActiveOrderIds",
            &[
                EncodedParam::Uint(0), // start index
                EncodedParam::Uint(100), // max count
            ],
        )?;
        
        let order_ids_result = self.call_contract(
            &self.addresses.order_vault,
            &function_data,
        ).await?;
        
        // Mock order IDs extraction
        let order_ids: Vec<String> = vec![
            format!("order_1_{}", task_id),
            format!("order_2_{}", task_id),
        ];
        
        // Retrieve each order
        let mut orders = Vec::new();
        for order_id in order_ids {
            match self.retrieve_single_order(&order_id).await {
                Ok(order_data) => orders.push(order_data),
                Err(e) => warn!("Failed to retrieve order {}: {:?}", order_id, e),
            }
        }
        
        info!("Retrieved {} orders for task {}", orders.len(), task_id);
        Ok(orders)
    }

    /// Retrieve a single order from vault
    async fn retrieve_single_order(&self, order_id: &str) -> Result<Vec<u8>> {
        let function_data = self.encode_function_call(
            "OrderVault",
            "retrieveOrder", 
            &[EncodedParam::Bytes32(order_id.to_string())],
        )?;
        
        let result = self.call_contract(
            &self.addresses.order_vault,
            &function_data,
        ).await?;
        
        Ok(result)
    }

    /// Get pending tasks for operator
    pub async fn call_get_pending_tasks(&self, operator: &str) -> Result<Vec<String>> {
        debug!("Getting pending tasks for operator: {}", operator);
        
        // Mock implementation - in production, this would query the contract
        let mock_tasks = vec![
            format!("task_1_{}", chrono::Utc::now().timestamp() % 1000),
            format!("task_2_{}", chrono::Utc::now().timestamp() % 1000),
        ];
        
        Ok(mock_tasks)
    }

    /// Update contract addresses
    pub async fn update_addresses(&mut self, addresses: HashMap<String, String>) -> Result<()> {
        info!("Updating contract addresses: {:?}", addresses);
        
        if let Some(service_manager) = addresses.get("service_manager") {
            self.addresses.service_manager = service_manager.clone();
        }
        
        if let Some(hook) = addresses.get("eigenvault_hook") {
            self.addresses.eigenvault_hook = hook.clone();
        }
        
        if let Some(vault) = addresses.get("order_vault") {
            self.addresses.order_vault = vault.clone();
        }
        
        if let Some(pool_manager) = addresses.get("pool_manager") {
            self.addresses.pool_manager = pool_manager.clone();
        }
        
        Ok(())
    }

    /// Encode function call data
    fn encode_function_call(
        &self,
        contract_name: &str,
        function_name: &str,
        params: &[EncodedParam],
    ) -> Result<Vec<u8>> {
        let abi = self.abis.get(contract_name)
            .ok_or_else(|| anyhow::anyhow!("ABI not found for contract: {}", contract_name))?;
        
        let function = abi.functions.iter()
            .find(|f| f.name == function_name)
            .ok_or_else(|| anyhow::anyhow!("Function not found: {}", function_name))?;
        
        // Generate function selector (first 4 bytes of keccak256 hash of signature)
        let signature = self.generate_function_signature(function);
        let selector = self.keccak256(signature.as_bytes())[0..4].to_vec();
        
        let mut encoded_data = selector;
        
        // Encode parameters (simplified)  
        for param in params {
            encoded_data.extend(param.encode());
        }
        
        debug!("Encoded function call: {} bytes", encoded_data.len());
        Ok(encoded_data)
    }

    /// Generate function signature string
    fn generate_function_signature(&self, function: &FunctionSignature) -> String {
        let params: Vec<String> = function.inputs.iter()
            .map(|(_, param_type)| param_type.clone())
            .collect();
        format!("{}({})", function.name, params.join(","))
    }

    /// Send transaction to blockchain
    async fn send_transaction(&self, call: ContractCall) -> Result<String> {
        debug!("Sending transaction to: {}", call.to);
        
        // Mock transaction sending
        let tx_hash = format!("0x{:x}", 
            std::collections::hash_map::DefaultHasher::new().finish()
        );
        
        debug!("Transaction sent with hash: {}", tx_hash);
        Ok(tx_hash)
    }

    /// Call contract (read-only)
    async fn call_contract(&self, to: &str, data: &[u8]) -> Result<Vec<u8>> {
        debug!("Calling contract: {} with {} bytes data", to, data.len());
        
        // Mock contract call result
        let result = vec![0u8; 64]; // Mock 64-byte result
        
        Ok(result)
    }

    /// Hash data using keccak256
    fn hash_data(&self, data: &[u8]) -> Vec<u8> {
        // Simplified hash - in production use actual keccak256
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }

    /// Keccak256 hash
    fn keccak256(&self, data: &[u8]) -> Vec<u8> {
        // Simplified - in production use actual keccak256
        self.hash_data(data)
    }

    /// Health check for contract manager
    pub async fn health_check(&self) -> Result<()> {
        // Test contract connectivity
        let test_data = vec![0u8; 4]; // Empty function call
        
        match self.call_contract(&self.addresses.service_manager, &test_data).await {
            Ok(_) => {
                debug!("Contract manager health check passed");
                Ok(())
            }
            Err(e) => {
                warn!("Contract manager health check failed: {:?}", e);
                Err(e)
            }
        }
    }

    /// Get contract addresses
    pub fn get_addresses(&self) -> &ContractAddresses {
        &self.addresses
    }
}

/// Contract ABI representation
#[derive(Debug, Clone)]
struct ContractAbi {
    contract_name: String,
    functions: Vec<FunctionSignature>,
    events: Vec<EventSignature>,
}

#[derive(Debug, Clone)]
struct FunctionSignature {
    name: String,
    inputs: Vec<(String, String)>, // (name, type)
    outputs: Vec<(String, String)>,
}

#[derive(Debug, Clone)]
struct EventSignature {
    name: String,
    inputs: Vec<(String, String, bool)>, // (name, type, indexed)
}

/// Encoded parameter for function calls
#[derive(Debug, Clone)]
enum EncodedParam {
    Address(String),
    Uint(u64),
    Bytes(Vec<u8>),
    Bytes32(String),
    Bool(bool),
}

impl EncodedParam {
    fn encode(&self) -> Vec<u8> {
        match self {
            EncodedParam::Address(addr) => {
                // Simplified address encoding
                let mut encoded = vec![0u8; 12]; // Padding
                encoded.extend(addr.as_bytes().get(0..20).unwrap_or(&[0u8; 20]));
                encoded
            }
            EncodedParam::Uint(value) => {
                // Encode as 32-byte big-endian
                let mut encoded = vec![0u8; 24]; // Padding
                encoded.extend(&value.to_be_bytes());
                encoded
            }
            EncodedParam::Bytes(data) => {
                // Simplified bytes encoding
                let mut encoded = vec![0u8; 32]; // Length slot
                encoded.extend(data);
                // Pad to 32-byte boundary
                while encoded.len() % 32 != 0 {
                    encoded.push(0);
                }
                encoded
            }
            EncodedParam::Bytes32(hex_str) => {
                // Decode hex string to 32 bytes
                let bytes = hex::decode(hex_str.trim_start_matches("0x"))
                    .unwrap_or_else(|_| vec![0u8; 32]);
                let mut encoded = bytes;
                encoded.resize(32, 0); // Ensure exactly 32 bytes
                encoded
            }
            EncodedParam::Bool(value) => {
                let mut encoded = vec![0u8; 31]; // Padding
                encoded.push(if *value { 1 } else { 0 });
                encoded
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_contract_addresses_default() {
        let addresses = ContractAddresses::default();
        assert!(!addresses.service_manager.is_empty());
        assert!(!addresses.eigenvault_hook.is_empty());
        assert!(!addresses.order_vault.is_empty());
    }

    #[test]
    fn test_encoded_param_uint() {
        let param = EncodedParam::Uint(123);
        let encoded = param.encode();
        assert_eq!(encoded.len(), 32);
    }

    #[test]
    fn test_encoded_param_bool() {
        let param_true = EncodedParam::Bool(true);
        let param_false = EncodedParam::Bool(false);
        
        let encoded_true = param_true.encode();
        let encoded_false = param_false.encode();
        
        assert_eq!(encoded_true.len(), 32);
        assert_eq!(encoded_false.len(), 32);
        assert_eq!(encoded_true[31], 1);
        assert_eq!(encoded_false[31], 0);
    }
}