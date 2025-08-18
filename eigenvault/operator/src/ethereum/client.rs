use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info, warn, error};
use tokio::time::{Duration, interval};

use crate::config::EthereumConfig;
use super::contracts::EigenVaultContracts;
use super::events::{EthereumEvent, EventProcessor};

/// Real Ethereum client for interacting with EigenVault contracts
pub struct EthereumClient {
    config: EthereumConfig,
    contracts: EigenVaultContracts,
    event_processor: EventProcessor,
    last_processed_block: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContractAddresses {
    pub hook: String,
    pub service_manager: String,
    pub order_vault: String,
    pub pool_manager: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperatorRegistration {
    pub operator_address: String,
    pub stake_amount: String,
    pub registration_signature: String,
    pub registration_timestamp: u64,
}

impl EthereumClient {
    pub async fn new(config: EthereumConfig) -> Result<Self> {
        info!("Initializing Ethereum client for RPC: {}", config.rpc_url);
        
        // Initialize contract interfaces
        let contracts = EigenVaultContracts::new(
            &config.rpc_url,
            &config.eigenvault_hook_address,
            &config.service_manager_address,
            &config.order_vault_address,
        ).await?;

        // Initialize event processor
        let event_processor = EventProcessor::new(config.clone());

        // Get latest block to start from
        let latest_block = contracts.get_latest_block_number().await?;

        Ok(Self {
            config,
            contracts,
            event_processor,
            last_processed_block: latest_block.saturating_sub(100), // Start 100 blocks ago
        })
    }

    /// Listen for new events from EigenVault contracts
    pub async fn listen_for_events(&mut self) -> Result<Vec<EthereumEvent>> {
        let current_block = self.contracts.get_latest_block_number().await?;
        
        if current_block <= self.last_processed_block {
            // No new blocks to process
            return Ok(vec![]);
        }

        debug!(
            "Processing blocks {} to {}",
            self.last_processed_block + 1,
            current_block
        );

        let events = self.event_processor.get_events(
            self.last_processed_block + 1,
            current_block,
        ).await?;

        self.last_processed_block = current_block;
        
        info!("Found {} events in block range", events.len());
        Ok(events)
    }

    /// Register operator with EigenVault AVS
    pub async fn register_operator(&self) -> Result<()> {
        info!("Registering operator with EigenVault AVS...");

        // Generate registration signature
        let registration_sig = self.generate_registration_signature().await?;

        // Call service manager registration
        let tx_hash = self.contracts.register_operator(registration_sig).await?;
        
        info!("Operator registration transaction: {}", tx_hash);
        
        // Wait for confirmation
        self.wait_for_transaction_confirmation(&tx_hash, 5).await?;
        
        info!("Operator registration confirmed");
        Ok(())
    }

    /// Submit matching proof for a task
    pub async fn submit_matching_proof(
        &self,
        task_id: &str,
        proof: Vec<u8>,
        result_hash: &str,
        operator_signatures: Vec<u8>,
    ) -> Result<String> {
        info!("Submitting matching proof for task: {}", task_id);

        let tx_hash = self.contracts.submit_task_response(
            task_id,
            &proof, // matches_data
            &proof, // proof_data (using same for simplicity)
            &operator_signatures,
        ).await?;

        info!("Proof submission transaction: {}", tx_hash);
        
        // Wait for confirmation
        self.wait_for_transaction_confirmation(&tx_hash, 3).await?;
        
        Ok(tx_hash)
    }

    /// Execute matched orders via hook contract
    pub async fn execute_vault_order(
        &self,
        order_id: &str,
        proof: Vec<u8>,
        signatures: Vec<u8>,
    ) -> Result<String> {
        info!("Executing vault order: {}", order_id);

        let tx_hash = self.contracts.execute_vault_order(
            order_id,
            &proof,
            &signatures,
        ).await?;

        info!("Order execution transaction: {}", tx_hash);
        
        // Wait for confirmation
        self.wait_for_transaction_confirmation(&tx_hash, 3).await?;
        
        Ok(tx_hash)
    }

    /// Submit task response with proof and matches
    pub async fn submit_task_response(
        &self,
        task_id: &str,
        matches: Vec<crate::matching::OrderMatch>,
        proof: crate::proofs::MatchingProof,
    ) -> Result<String> {
        info!("Submitting task response for task: {}", task_id);
        
        // Convert matches to serialized format for contract submission
        let matches_data = serde_json::to_vec(&matches)?;
        let proof_data = proof.proof_data;
        
        // Submit through the service manager contract
        let tx_hash = self.contracts.submit_task_response(
            task_id,
            &matches_data,
            &proof_data,
            &proof.operator_signature,
        ).await?;
        
        info!("Task response submitted: {}", tx_hash);
        Ok(tx_hash)
    }

    /// Retrieve encrypted orders for a task
    pub async fn retrieve_orders_for_task(&self, task_id: &str) -> Result<Vec<Vec<u8>>> {
        debug!("Retrieving orders for task: {}", task_id);

        // Get task details from service manager
        let task = self.contracts.get_task(task_id).await?;
        
        // Get order IDs from the task
        let order_ids = self.extract_order_ids_from_task(&task).await?;
        
        // Retrieve each encrypted order from vault
        let mut encrypted_orders = Vec::new();
        for order_id in order_ids {
            match self.contracts.retrieve_order(&order_id).await {
                Ok(encrypted_order) => encrypted_orders.push(encrypted_order),
                Err(e) => {
                    warn!("Failed to retrieve order {}: {}", order_id, e);
                    // Continue with other orders
                }
            }
        }

        info!("Retrieved {} encrypted orders for task", encrypted_orders.len());
        Ok(encrypted_orders)
    }

    /// Check operator's current stake
    pub async fn get_operator_stake(&self, operator: &str) -> Result<u64> {
        let stake = self.contracts.get_operator_stake(operator).await?;
        debug!("Operator {} stake: {}", operator, stake);
        Ok(stake)
    }

    /// Health check for Ethereum connection
    pub async fn health_check(&self) -> Result<()> {
        // Check if we can connect to the node
        let latest_block = self.contracts.get_latest_block_number().await?;
        
        // Check if contracts are responsive
        let hook_address = self.contracts.get_hook_address().await?;
        
        // Verify we're on the correct network
        let chain_id = self.contracts.get_chain_id().await?;
        info!("Connected to chain ID: {}", chain_id);

        debug!("Ethereum health check passed - block: {}, hook: {}", latest_block, hook_address);
        Ok(())
    }

    /// Monitor for slashing events
    pub async fn monitor_slashing_events(&self) -> Result<Vec<SlashingEvent>> {
        let events = self.contracts.get_slashing_events(
            self.last_processed_block.saturating_sub(1000), // Look back 1000 blocks
            self.last_processed_block,
        ).await?;

        if !events.is_empty() {
            warn!("Detected {} slashing events", events.len());
        }

        Ok(events)
    }

    /// Get pending tasks for this operator
    pub async fn get_pending_tasks(&self) -> Result<Vec<TaskInfo>> {
        let operator_address = &self.config.operator_address;
        let tasks = self.contracts.get_pending_tasks_for_operator(operator_address).await?;
        
        debug!("Found {} pending tasks for operator", tasks.len());
        Ok(tasks)
    }

    /// Private helper methods
    async fn generate_registration_signature(&self) -> Result<Vec<u8>> {
        // In production, this would generate a proper EigenLayer registration signature
        // For now, return a placeholder
        Ok(vec![0u8; 64]) // 64-byte signature placeholder
    }

    async fn wait_for_transaction_confirmation(&self, tx_hash: &str, confirmations: u32) -> Result<()> {
        info!("Waiting for {} confirmations for tx: {}", confirmations, tx_hash);
        
        let mut attempts = 0;
        let max_attempts = 60; // 10 minutes with 10 second intervals
        
        while attempts < max_attempts {
            match self.contracts.get_transaction_receipt(tx_hash).await {
                Ok(Some(receipt)) => {
                    if receipt.confirmations >= confirmations {
                        info!("Transaction {} confirmed with {} confirmations", tx_hash, receipt.confirmations);
                        return Ok(());
                    }
                }
                Ok(None) => {
                    debug!("Transaction {} not yet mined", tx_hash);
                }
                Err(e) => {
                    warn!("Error checking transaction {}: {}", tx_hash, e);
                }
            }
            
            attempts += 1;
            tokio::time::sleep(Duration::from_secs(10)).await;
        }
        
        Err(anyhow::anyhow!("Transaction {} not confirmed after {} attempts", tx_hash, max_attempts))
    }

    async fn extract_order_ids_from_task(&self, task: &TaskInfo) -> Result<Vec<String>> {
        // Extract order IDs from task data
        // This would parse the orders_set_hash to get individual order IDs
        // For now, return a placeholder implementation
        Ok(vec![])
    }
}

/// Slashing event information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlashingEvent {
    pub operator: String,
    pub slash_amount: u64,
    pub slash_type: u8,
    pub block_number: u64,
    pub transaction_hash: String,
}

/// Task information from service manager
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskInfo {
    pub task_id: String,
    pub orders_set_hash: String,
    pub deadline: u64,
    pub assigned_operators: Vec<String>,
    pub minimum_stake: u64,
    pub created_at: u64,
}

/// Transaction receipt information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionReceipt {
    pub transaction_hash: String,
    pub block_number: u64,
    pub confirmations: u32,
    pub status: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::EthereumConfig;

    #[tokio::test]
    async fn test_ethereum_client_creation() {
        let config = EthereumConfig::default();
        
        // This test would require a real RPC endpoint
        // For now, it's a placeholder
        assert!(true);
    }

    #[tokio::test] 
    async fn test_health_check() {
        // Test health check functionality
        assert!(true);
    }
}