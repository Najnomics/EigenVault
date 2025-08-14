use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{sleep, Duration};
use tracing::{debug, info, warn, error};

use crate::config::EthereumConfig;
use crate::matching::{OrderMatch, DecryptedOrder};
use crate::proofs::MatchingProof;
use super::{ContractManager, EventListener, ParsedEvent};

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
    OrderExecuted {
        order_id: String,
        trader: String,
        amount_in: u64,
        amount_out: u64,
    },
    OperatorRegistered {
        operator: String,
        stake: u64,
    },
    TaskCompleted {
        task_id: String,
        result_hash: String,
        operator: String,
    },
    ProofSubmitted {
        proof_id: String,
        task_id: String,
        operator: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskResponse {
    pub task_id: String,
    pub matches: Vec<OrderMatch>,
    pub proof: MatchingProof,
    pub operator: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorInfo {
    pub address: String,
    pub stake: u64,
    pub is_active: bool,
    pub tasks_completed: u64,
    pub last_active: u64,
}

pub struct EthereumClient {
    config: EthereumConfig,
    contract_manager: ContractManager,
    event_listener: EventListener,
    operator_address: String,
    is_registered: bool,
    block_number: u64,
    connection_healthy: bool,
}

impl EthereumClient {
    pub async fn new(config: EthereumConfig) -> Result<Self> {
        info!("Initializing Ethereum client with RPC: {}", config.rpc_url);
        
        let contract_manager = ContractManager::new(&config).await?;
        let event_listener = EventListener::new(&config).await?;
        
        let mut client = Self {
            operator_address: config.operator_address.clone(),
            config,
            contract_manager,
            event_listener,
            is_registered: false,
            block_number: 0,
            connection_healthy: false,
        };
        
        // Test connection and get latest block
        client.test_connection().await?;
        
        Ok(client)
    }

    /// Test Ethereum connection
    async fn test_connection(&mut self) -> Result<()> {
        info!("Testing Ethereum connection...");
        
        match self.get_latest_block_number().await {
            Ok(block_number) => {
                self.block_number = block_number;
                self.connection_healthy = true;
                info!("Connected to Ethereum. Latest block: {}", block_number);
                Ok(())
            }
            Err(e) => {
                self.connection_healthy = false;
                error!("Failed to connect to Ethereum: {:?}", e);
                Err(e)
            }
        }
    }

    /// Get latest block number
    pub async fn get_latest_block_number(&self) -> Result<u64> {
        // Mock implementation - in production, use actual RPC call
        let mock_block = 18_000_000 + (chrono::Utc::now().timestamp() as u64 % 1000);
        debug!("Latest block number: {}", mock_block);
        Ok(mock_block)
    }

    /// Register operator with EigenLayer
    pub async fn register_operator(&mut self) -> Result<()> {
        if self.is_registered {
            info!("Operator already registered");
            return Ok(());
        }

        info!("Registering operator with EigenLayer: {}", self.operator_address);
        
        // Call service manager contract to register
        let registration_data = self.prepare_registration_data().await?;
        
        let tx_result = self.contract_manager.call_register_operator(
            &self.operator_address,
            &registration_data,
        ).await?;
        
        info!("Registration transaction submitted: {:?}", tx_result);
        
        // Wait for confirmation
        self.wait_for_transaction_confirmation(&tx_result).await?;
        
        self.is_registered = true;
        info!("Operator registration completed successfully");
        
        Ok(())
    }

    /// Prepare operator registration data
    async fn prepare_registration_data(&self) -> Result<Vec<u8>> {
        // Prepare registration signature and data
        let timestamp = chrono::Utc::now().timestamp() as u64;
        let mut registration_data = Vec::new();
        
        registration_data.extend(self.operator_address.as_bytes());
        registration_data.extend(timestamp.to_le_bytes());
        registration_data.extend(b"eigenvault_operator_v1");
        
        Ok(registration_data)
    }

    /// Listen for Ethereum events
    pub async fn listen_for_events(&self) -> Result<Vec<EthereumEvent>> {
        debug!("Listening for Ethereum events...");
        
        let latest_block = self.get_latest_block_number().await?;
        let from_block = self.block_number.max(latest_block.saturating_sub(10));
        
        let raw_events = self.event_listener.get_events(from_block, latest_block).await?;
        
        let mut parsed_events = Vec::new();
        
        for raw_event in raw_events {
            match self.parse_ethereum_event(raw_event).await {
                Ok(Some(event)) => parsed_events.push(event),
                Ok(None) => {}, // Ignored event
                Err(e) => warn!("Failed to parse event: {:?}", e),
            }
        }
        
        if !parsed_events.is_empty() {
            info!("Received {} events from blocks {} to {}", 
                  parsed_events.len(), from_block, latest_block);
        }
        
        Ok(parsed_events)
    }

    /// Parse raw Ethereum event into typed event
    async fn parse_ethereum_event(&self, raw_event: ParsedEvent) -> Result<Option<EthereumEvent>> {
        match raw_event.event_name.as_str() {
            "TaskCreated" => {
                let task_id = raw_event.get_string_param("taskId")?;
                let orders_hash = raw_event.get_string_param("ordersHash")?;
                let deadline = raw_event.get_uint_param("deadline")?;
                
                Ok(Some(EthereumEvent::TaskCreated {
                    task_id,
                    orders_hash,
                    deadline,
                }))
            }
            "OrderStored" => {
                let order_id = raw_event.get_string_param("orderId")?;
                let trader = raw_event.get_string_param("trader")?;
                let encrypted_order = raw_event.get_bytes_param("encryptedOrder")?;
                
                Ok(Some(EthereumEvent::OrderStored {
                    order_id,
                    trader,
                    encrypted_order,
                }))
            }
            "OrderExecuted" => {
                let order_id = raw_event.get_string_param("orderId")?;
                let trader = raw_event.get_string_param("trader")?;
                let amount_in = raw_event.get_uint_param("amountIn")?;
                let amount_out = raw_event.get_uint_param("amountOut")?;
                
                Ok(Some(EthereumEvent::OrderExecuted {
                    order_id,
                    trader,
                    amount_in,
                    amount_out,
                }))
            }
            "OperatorRegistered" => {
                let operator = raw_event.get_string_param("operator")?;
                let stake = raw_event.get_uint_param("stake")?;
                
                Ok(Some(EthereumEvent::OperatorRegistered {
                    operator,
                    stake,
                }))
            }
            "TaskCompleted" => {
                let task_id = raw_event.get_string_param("taskId")?;
                let result_hash = raw_event.get_string_param("resultHash")?;
                let operator = raw_event.get_string_param("operator")?;
                
                Ok(Some(EthereumEvent::TaskCompleted {
                    task_id,
                    result_hash,
                    operator,
                }))
            }
            "ProofSubmitted" => {
                let proof_id = raw_event.get_string_param("proofId")?;
                let task_id = raw_event.get_string_param("taskId")?;
                let operator = raw_event.get_string_param("operator")?;
                
                Ok(Some(EthereumEvent::ProofSubmitted {
                    proof_id,
                    task_id,
                    operator,
                }))
            }
            _ => {
                debug!("Ignoring unknown event: {}", raw_event.event_name);
                Ok(None)
            }
        }
    }

    /// Retrieve orders for a specific task
    pub async fn retrieve_orders_for_task(&self, task_id: &str) -> Result<Vec<Vec<u8>>> {
        info!("Retrieving orders for task: {}", task_id);
        
        // Call order vault contract to get orders
        let orders = self.contract_manager.call_get_task_orders(task_id).await?;
        
        info!("Retrieved {} orders for task {}", orders.len(), task_id);
        Ok(orders)
    }

    /// Submit matching proof for executed orders
    pub async fn submit_matching_proof(&self, order_match: &OrderMatch, proof: MatchingProof) -> Result<String> {
        info!("Submitting matching proof for match: {}", order_match.match_id);
        
        let tx_hash = self.contract_manager.call_execute_vault_order(
            &order_match.match_id,
            &proof.proof_data,
            &proof.operator_signature,
        ).await?;
        
        info!("Submitted matching proof. Transaction: {}", tx_hash);
        Ok(tx_hash)
    }

    /// Submit task response with batch matches
    pub async fn submit_task_response(&self, task_id: &str, matches: Vec<OrderMatch>, proof: MatchingProof) -> Result<String> {
        info!("Submitting task response for task: {} with {} matches", task_id, matches.len());
        
        let task_response = TaskResponse {
            task_id: task_id.to_string(),
            matches,
            proof,
            operator: self.operator_address.clone(),
        };
        
        let response_data = serde_json::to_vec(&task_response)?;
        
        let tx_hash = self.contract_manager.call_submit_task_response(
            task_id,
            &response_data,
        ).await?;
        
        info!("Submitted task response. Transaction: {}", tx_hash);
        Ok(tx_hash)
    }

    /// Get operator information
    pub async fn get_operator_info(&self, operator_address: &str) -> Result<OperatorInfo> {
        debug!("Getting operator info for: {}", operator_address);
        
        let info = self.contract_manager.call_get_operator_info(operator_address).await?;
        Ok(info)
    }

    /// Get current operator stake
    pub async fn get_operator_stake(&self) -> Result<u64> {
        let info = self.get_operator_info(&self.operator_address).await?;
        Ok(info.stake)
    }

    /// Check if operator is registered and active
    pub async fn is_operator_active(&self) -> Result<bool> {
        let info = self.get_operator_info(&self.operator_address).await?;
        Ok(info.is_active && self.is_registered)
    }

    /// Get pending tasks for this operator
    pub async fn get_pending_tasks(&self) -> Result<Vec<String>> {
        debug!("Getting pending tasks for operator: {}", self.operator_address);
        
        let tasks = self.contract_manager.call_get_pending_tasks(&self.operator_address).await?;
        
        if !tasks.is_empty() {
            info!("Found {} pending tasks", tasks.len());
        }
        
        Ok(tasks)
    }

    /// Wait for transaction confirmation
    async fn wait_for_transaction_confirmation(&self, tx_hash: &str) -> Result<()> {
        info!("Waiting for transaction confirmation: {}", tx_hash);
        
        let max_wait_time = Duration::from_secs(300); // 5 minutes
        let poll_interval = Duration::from_secs(5);
        let start_time = std::time::Instant::now();
        
        loop {
            if start_time.elapsed() > max_wait_time {
                return Err(anyhow::anyhow!("Transaction confirmation timeout: {}", tx_hash));
            }
            
            match self.get_transaction_receipt(tx_hash).await {
                Ok(Some(receipt)) => {
                    info!("Transaction confirmed in block: {}", receipt.block_number);
                    return Ok(());
                }
                Ok(None) => {
                    debug!("Transaction {} not yet mined", tx_hash);
                }
                Err(e) => {
                    warn!("Error checking transaction receipt: {:?}", e);
                }
            }
            
            sleep(poll_interval).await;
        }
    }

    /// Get transaction receipt
    async fn get_transaction_receipt(&self, tx_hash: &str) -> Result<Option<TransactionReceipt>> {
        // Mock implementation
        debug!("Getting transaction receipt for: {}", tx_hash);
        
        // Simulate confirmation after some time
        let receipt = TransactionReceipt {
            transaction_hash: tx_hash.to_string(),
            block_number: self.block_number + 1,
            gas_used: 200_000,
            status: true,
        };
        
        Ok(Some(receipt))
    }

    /// Update contract addresses (for upgrades)
    pub async fn update_contract_addresses(&mut self, addresses: HashMap<String, String>) -> Result<()> {
        info!("Updating contract addresses: {:?}", addresses);
        self.contract_manager.update_addresses(addresses).await?;
        Ok(())
    }

    /// Get current gas price
    pub async fn get_gas_price(&self) -> Result<u64> {
        // Mock implementation - in production, query actual gas price
        let base_gas_price = 20_000_000_000u64; // 20 gwei
        let variation = (chrono::Utc::now().timestamp() as u64 % 100) * 1_000_000_000;
        Ok(base_gas_price + variation)
    }

    /// Estimate gas for transaction
    pub async fn estimate_gas(&self, to: &str, data: &[u8]) -> Result<u64> {
        debug!("Estimating gas for transaction to: {}", to);
        
        // Mock estimation based on data size
        let base_gas = 21_000u64;
        let data_gas = (data.len() as u64) * 16;
        let complexity_gas = 50_000u64; // For contract interaction
        
        Ok(base_gas + data_gas + complexity_gas)
    }

    /// Health check for Ethereum client
    pub async fn health_check(&self) -> Result<()> {
        // Check connection
        let latest_block = self.get_latest_block_number().await?;
        
        if latest_block == 0 {
            return Err(anyhow::anyhow!("Invalid latest block number"));
        }
        
        // Check if significantly behind
        let expected_recent_block = (chrono::Utc::now().timestamp() as u64) / 12; // Approximate
        if latest_block + 100 < expected_recent_block {
            warn!("Ethereum client may be behind. Latest block: {}", latest_block);
        }
        
        // Check operator registration
        if !self.is_registered {
            warn!("Operator not registered with EigenLayer");
        }
        
        // Test contract connectivity
        self.contract_manager.health_check().await?;
        
        debug!("Ethereum client health check passed");
        Ok(())
    }

    /// Get current block number
    pub fn get_current_block(&self) -> u64 {
        self.block_number
    }

    /// Check if connection is healthy
    pub fn is_connection_healthy(&self) -> bool {
        self.connection_healthy
    }

    /// Get operator address
    pub fn get_operator_address(&self) -> &str {
        &self.operator_address
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransactionReceipt {
    transaction_hash: String,
    block_number: u64,
    gas_used: u64,
    status: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::EthereumConfig;

    #[tokio::test]
    async fn test_ethereum_client_creation() {
        let config = EthereumConfig::default();
        // This test would require a test RPC endpoint
        // let client = EthereumClient::new(config).await;
        // assert!(client.is_ok());
    }

    #[test]
    fn test_operator_address() {
        let config = EthereumConfig::default();
        assert!(!config.operator_address.is_empty());
    }
}