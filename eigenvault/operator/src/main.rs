use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::{info, warn, error};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use uuid;

mod config;
mod ethereum;
mod matching;
mod networking;
mod proofs;

use config::{Config, KeyManager, EthereumConfig, MatchingConfig, NetworkingConfig, ProofConfig};
use ethereum::EthereumClient;
use matching::MatchingEngine;
use networking::P2PNetwork;
use proofs::ZKProver;

#[derive(Parser)]
#[command(name = "eigenvault-operator")]
#[command(about = "EigenVault AVS Operator", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize operator configuration
    Init {
        /// Configuration file path
        #[arg(short, long, default_value = "config.yaml")]
        config: PathBuf,
    },
    /// Start the operator
    Start {
        /// Configuration file path
        #[arg(short, long, default_value = "config.yaml")]
        config: PathBuf,
    },
    /// Generate operator keys
    Keygen {
        /// Output directory for keys
        #[arg(short, long, default_value = "keys")]
        output: PathBuf,
    },
    /// Register operator with EigenLayer
    Register {
        /// Configuration file path
        #[arg(short, long, default_value = "config.yaml")]
        config: PathBuf,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "eigenvault_operator=debug,info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Init { config } => {
            info!("Initializing operator configuration at {:?}", config);
            init_config(config).await?;
        }
        Commands::Start { config } => {
            info!("Starting EigenVault operator with config {:?}", config);
            start_operator(config).await?;
        }
        Commands::Keygen { output } => {
            info!("Generating operator keys in {:?}", output);
            generate_keys(output).await?;
        }
        Commands::Register { config } => {
            info!("Registering operator with config {:?}", config);
            register_operator(config).await?;
        }
    }

    Ok(())
}

async fn init_config(config_path: PathBuf) -> Result<()> {
    let default_config = Config::default();
    let config_str = toml::to_string_pretty(&default_config)?;
    
    tokio::fs::create_dir_all(config_path.parent().unwrap_or(&PathBuf::from("."))).await?;
    tokio::fs::write(&config_path, config_str).await?;
    
    info!("Configuration initialized at {:?}", config_path);
    info!("Please edit the configuration file and add your private keys and RPC URLs");
    
    Ok(())
}

async fn start_operator(config_path: PathBuf) -> Result<()> {
    info!("Loading configuration from {:?}", config_path);
    let config = Config::load(config_path)?;
    
    info!("Starting EigenVault operator...");
    
    // Initialize components
    let ethereum_client = EthereumClient::new(config.ethereum.clone()).await?;
    let matching_engine = MatchingEngine::new(config.matching.clone()).await?;
    let p2p_network = P2PNetwork::new(config.networking.clone()).await?;
    let zk_prover = ZKProver::new(config.proofs.clone()).await?;

    // Create operator instance
    let operator = Operator::new(
        ethereum_client,
        matching_engine,
        p2p_network,
        zk_prover,
        config.clone(),
    );

    // Start operator
    operator.run().await?;

    Ok(())
}

async fn generate_keys(output_path: PathBuf) -> Result<()> {
    tokio::fs::create_dir_all(&output_path).await?;
    
    let key_manager = KeyManager::new();
    key_manager.generate_keys(&output_path).await?;
    
    info!("Keys generated successfully in {:?}", output_path);
    info!("Please secure your private keys and update your configuration");
    
    Ok(())
}

async fn register_operator(config_path: PathBuf) -> Result<()> {
    let config = Config::load(config_path)?;
    let ethereum_client = EthereumClient::new(config.ethereum.clone()).await?;
    
    info!("Registering operator with EigenLayer...");
    ethereum_client.register_operator().await?;
    
    info!("Operator registration completed!");
    
    Ok(())
}

/// Main operator struct that coordinates all components
pub struct Operator {
    ethereum_client: EthereumClient,
    matching_engine: MatchingEngine,
    p2p_network: P2PNetwork,
    zk_prover: ZKProver,
    config: Config,
}

impl Operator {
    pub fn new(
        ethereum_client: EthereumClient,
        matching_engine: MatchingEngine,
        p2p_network: P2PNetwork,
        zk_prover: ZKProver,
        config: Config,
    ) -> Self {
        Self {
            ethereum_client,
            matching_engine,
            p2p_network,
            zk_prover,
            config,
        }
    }

    pub async fn run(self) -> Result<()> {
        info!("EigenVault operator starting...");

        // Start background tasks
        let ethereum_handle = tokio::spawn(self.run_ethereum_listener());
        let p2p_handle = tokio::spawn(self.run_p2p_network());
        let matching_handle = tokio::spawn(self.run_matching_engine());
        let health_check_handle = tokio::spawn(self.run_health_check());

        // Wait for any task to complete (or fail)
        tokio::select! {
            result = ethereum_handle => {
                error!("Ethereum listener stopped: {:?}", result);
            }
            result = p2p_handle => {
                error!("P2P network stopped: {:?}", result);
            }
            result = matching_handle => {
                error!("Matching engine stopped: {:?}", result);
            }
            result = health_check_handle => {
                error!("Health check stopped: {:?}", result);
            }
        }

        warn!("Operator shutting down...");
        Ok(())
    }

    async fn run_ethereum_listener(self) -> Result<()> {
        info!("Starting Ethereum event listener...");
        
        loop {
            match self.ethereum_client.listen_for_events().await {
                Ok(events) => {
                    for event in events {
                        if let Err(e) = self.handle_ethereum_event(event).await {
                            error!("Failed to handle Ethereum event: {:?}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Error listening for Ethereum events: {:?}", e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                }
            }
        }
    }

    async fn run_p2p_network(mut self) -> Result<()> {
        info!("Starting P2P network...");
        
        loop {
            match self.p2p_network.listen_for_messages().await {
                Ok(message) => {
                    if let Err(e) = self.handle_p2p_message(message).await {
                        error!("Failed to handle P2P message: {:?}", e);
                    }
                }
                Err(e) => {
                    error!("Error in P2P network: {:?}", e);
                    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
                }
            }
        }
    }

    async fn run_matching_engine(self) -> Result<()> {
        info!("Starting matching engine...");
        
        loop {
            match self.matching_engine.process_pending_orders().await {
                Ok(matches) => {
                    for order_match in matches {
                        if let Err(e) = self.handle_order_match(order_match).await {
                            error!("Failed to handle order match: {:?}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Error in matching engine: {:?}", e);
                }
            }
            
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        }
    }

    async fn run_health_check(self) -> Result<()> {
        info!("Starting health check...");
        
        loop {
            // Perform health checks
            let ethereum_healthy = self.ethereum_client.health_check().await.is_ok();
            let p2p_healthy = self.p2p_network.health_check().await.is_ok();
            let matching_healthy = self.matching_engine.health_check().await.is_ok();
            
            if !ethereum_healthy || !p2p_healthy || !matching_healthy {
                warn!(
                    "Health check failed - Ethereum: {}, P2P: {}, Matching: {}",
                    ethereum_healthy, p2p_healthy, matching_healthy
                );
            }
            
            tokio::time::sleep(tokio::time::Duration::from_secs(30)).await;
        }
    }

    async fn handle_ethereum_event(&self, event: ethereum::EthereumEvent) -> Result<()> {
        use ethereum::EthereumEvent;
        
        match event {
            EthereumEvent::TaskCreated { task_id, orders_hash, deadline } => {
                info!("New task created: {} with deadline {}", task_id, deadline);
                // Process the task
                self.process_matching_task(task_id, orders_hash, deadline).await?;
            }
            EthereumEvent::OrderStored { order_id, trader, encrypted_order } => {
                info!("New order stored: {} from trader {}", order_id, trader);
                // Add order to matching engine
                self.matching_engine.add_encrypted_order(order_id, encrypted_order).await?;
            }
            _ => {
                // Handle other events
            }
        }
        
        Ok(())
    }

    async fn handle_p2p_message(&self, message: networking::P2PMessage) -> Result<()> {
        use networking::P2PMessage;
        
        match message {
            P2PMessage::OrderGossip { order_id, encrypted_data, signature: _ } => {
                info!("Received order gossip: {}", order_id);
                self.matching_engine.add_encrypted_order(order_id, encrypted_data).await?;
            }
            P2PMessage::MatchingResult { task_id, result, signature } => {
                info!("Received matching result for task: {}", task_id);
                self.handle_matching_result(task_id, result, signature).await?;
            }
            _ => {
                // Handle other message types
            }
        }
        
        Ok(())
    }

    async fn handle_order_match(&self, order_match: matching::OrderMatch) -> Result<()> {
        info!("Processing order match: {:?}", order_match);
        
        // Generate ZK proof for the match
        let proof = self.zk_prover.generate_matching_proof(&[order_match], "default_pool").await?;
        
        // Submit proof to Ethereum - convert to expected format
        let task_id = format!("task_{}", uuid::Uuid::new_v4());
        self.ethereum_client.submit_matching_proof(&task_id, proof.proof_data, &proof.proof_id, vec![]).await?;
        
        Ok(())
    }

    async fn process_matching_task(&self, task_id: String, orders_hash: String, deadline: u64) -> Result<()> {
        info!("Processing matching task: {}", task_id);
        
        // Get orders from vault
        let orders = self.ethereum_client.retrieve_orders_for_task(&task_id).await?;
        
        // Decrypt orders
        let decrypted_orders = self.decrypt_orders(orders).await?;
        
        // Find matches
        let matches = self.matching_engine.find_matches(decrypted_orders).await?;
        
        if !matches.is_empty() {
            // Generate proof for matches
            let proof = self.zk_prover.generate_batch_proof(&matches).await?;
            
            // Submit to contract
            self.ethereum_client.submit_task_response(&task_id, matches, proof).await?;
            
            info!("Submitted {} matches for task {}", matches.len(), task_id);
        }
        
        Ok(())
    }

    async fn decrypt_orders(&self, encrypted_orders: Vec<Vec<u8>>) -> Result<Vec<matching::DecryptedOrder>> {
        // Implementation would decrypt orders using operator's private key
        // For now, return mock orders
        Ok(vec![])
    }

    async fn handle_matching_result(&self, task_id: String, result: Vec<u8>, signature: Vec<u8>) -> Result<()> {
        // Verify signature and result
        // Aggregate with other operator results
        // Submit if threshold reached
        Ok(())
    }
}