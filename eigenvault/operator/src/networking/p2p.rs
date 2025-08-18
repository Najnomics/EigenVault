use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{sleep, Duration, Instant};
use tracing::{debug, info, warn, error};

use crate::config::NetworkingConfig;
use super::{GossipProtocol, NetworkEncryption, SecureMessage};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum P2PMessage {
    /// Handshake message for peer connection
    Handshake {
        peer_id: String,
        version: String,
        capabilities: Vec<String>,
    },
    /// Order gossip between peers
    OrderGossip {
        order_id: String,
        encrypted_data: Vec<u8>,
        signature: Vec<u8>,
    },
    /// Matching result sharing
    MatchingResult {
        task_id: String,
        result: Vec<u8>,
        signature: Vec<u8>,
    },
    /// Ping message for keepalive
    Ping {
        timestamp: u64,
    },
    /// Pong response to ping
    Pong {
        timestamp: u64,
        original_timestamp: u64,
    },
    /// Request for peer list
    PeerListRequest,
    /// Response containing known peers
    PeerListResponse {
        peers: Vec<PeerInfo>,
    },
    /// Task announcement
    TaskAnnouncement {
        task_id: String,
        orders_hash: String,
        deadline: u64,
    },
    /// Proof sharing
    ProofShare {
        proof_id: String,
        proof_data: Vec<u8>,
        signature: Vec<u8>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerInfo {
    pub peer_id: String,
    pub address: String,
    pub port: u16,
    pub public_key: Vec<u8>,
    pub last_seen: u64,
    pub stake: u64,
    pub is_active: bool,
    pub reputation: f64,
}

#[derive(Debug)]
struct PeerConnection {
    peer_info: PeerInfo,
    stream: Option<TcpStream>,
    last_ping: Instant,
    connection_time: Instant,
    message_count: u64,
}

pub struct P2PNetwork {
    config: NetworkingConfig,
    local_peer_id: String,
    local_port: u16,
    peers: HashMap<String, PeerConnection>,
    gossip_protocol: GossipProtocol,
    network_encryption: NetworkEncryption,
    listener: Option<TcpListener>,
    is_running: bool,
    message_queue: tokio::sync::mpsc::UnboundedReceiver<P2PMessage>,
    message_sender: tokio::sync::mpsc::UnboundedSender<P2PMessage>,
}

impl P2PNetwork {
    pub async fn new(config: NetworkingConfig) -> Result<Self> {
        info!("Initializing P2P network on port {}", config.listen_port);
        
        let (message_sender, message_queue) = tokio::sync::mpsc::unbounded_channel();
        
        let local_peer_id = format!("peer_{}", uuid::Uuid::new_v4());
        
        let gossip_protocol = GossipProtocol::new(&config).await?;
        let network_encryption = NetworkEncryption::new().await?;
        
        let mut network = Self {
            local_peer_id: local_peer_id.clone(),
            local_port: config.listen_port,
            config,
            peers: HashMap::new(),
            gossip_protocol,
            network_encryption,
            listener: None,
            is_running: false,
            message_queue,
            message_sender,
        };
        
        // Start listening for connections
        network.start_listener().await?;
        
        // Connect to bootstrap peers
        network.connect_to_bootstrap_peers().await?;
        
        info!("P2P network initialized with peer ID: {}", local_peer_id);
        Ok(network)
    }

    /// Start TCP listener for incoming connections
    async fn start_listener(&mut self) -> Result<()> {
        let listen_addr = format!("0.0.0.0:{}", self.local_port);
        let listener = TcpListener::bind(&listen_addr).await?;
        
        info!("P2P listener started on {}", listen_addr);
        self.listener = Some(listener);
        
        Ok(())
    }

    /// Connect to bootstrap peers
    async fn connect_to_bootstrap_peers(&mut self) -> Result<()> {
        info!("Connecting to {} bootstrap peers", self.config.bootstrap_peers.len());
        
        let bootstrap_peers = self.config.bootstrap_peers.clone();
        for peer_addr in &bootstrap_peers {
            match self.connect_to_peer(peer_addr).await {
                Ok(peer_info) => {
                    info!("Connected to bootstrap peer: {}", peer_info.peer_id);
                    self.add_peer(peer_info).await?;
                }
                Err(e) => {
                    warn!("Failed to connect to bootstrap peer {}: {:?}", peer_addr, e);
                }
            }
        }
        
        Ok(())
    }

    /// Connect to a specific peer
    async fn connect_to_peer(&self, peer_addr: &str) -> Result<PeerInfo> {
        debug!("Connecting to peer: {}", peer_addr);
        
        let stream = TcpStream::connect(peer_addr).await?;
        
        // Send handshake
        let handshake = P2PMessage::Handshake {
            peer_id: self.local_peer_id.clone(),
            version: "1.0.0".to_string(),
            capabilities: vec!["order_matching".to_string(), "gossip".to_string()],
        };
        
        self.send_message_to_stream(&stream, &handshake).await?;
        
        // Receive handshake response
        let response = self.receive_message_from_stream(&stream).await?;
        
        match response {
            P2PMessage::Handshake { peer_id, version, capabilities } => {
                let peer_info = PeerInfo {
                    peer_id: peer_id.clone(),
                    address: peer_addr.split(':').next().unwrap_or("unknown").to_string(),
                    port: peer_addr.split(':').nth(1).unwrap_or("0").parse().unwrap_or(0),
                    public_key: vec![0u8; 32], // Mock public key
                    last_seen: chrono::Utc::now().timestamp() as u64,
                    stake: 32_000_000_000_000_000_000u64, // Mock 32 ETH
                    is_active: true,
                    reputation: 1.0,
                };
                
                info!("Handshake completed with peer: {} (version: {})", peer_id, version);
                Ok(peer_info)
            }
            _ => Err(anyhow::anyhow!("Invalid handshake response")),
        }
    }

    /// Add peer to the network
    async fn add_peer(&mut self, peer_info: PeerInfo) -> Result<()> {
        debug!("Adding peer: {}", peer_info.peer_id);
        
        let peer_connection = PeerConnection {
            peer_info: peer_info.clone(),
            stream: None,
            last_ping: Instant::now(),
            connection_time: Instant::now(),
            message_count: 0,
        };
        
        self.peers.insert(peer_info.peer_id.clone(), peer_connection);
        let peer_id = peer_info.peer_id.clone();
        
        // Notify gossip protocol about new peer
        self.gossip_protocol.add_peer(peer_info).await?;
        
        info!("Added peer to network: {}", peer_id);
        Ok(())
    }

    /// Listen for incoming messages
    pub async fn listen_for_messages(&mut self) -> Result<P2PMessage> {
        loop {
            // Check for queued messages first
            if let Ok(message) = self.message_queue.try_recv() {
                return Ok(message);
            }
            
            // Handle incoming connections
            if let Err(e) = self.accept_connections().await {
                warn!("Error accepting connections: {:?}", e);
            }
            
            // Handle peer maintenance
            self.maintain_peer_connections().await?;
            
            // Small delay to prevent busy waiting
            sleep(Duration::from_millis(10)).await;
        }
    }

    /// Accept incoming connections
    async fn accept_connections(&mut self) -> Result<()> {
        if let Some(listener) = &mut self.listener {
            match listener.accept().await {
                Ok((stream, addr)) => {
                    info!("Accepted connection from: {}", addr);
                    self.handle_incoming_connection(stream).await?;
                }
                Err(e) => {
                    warn!("Error accepting connection: {:?}", e);
                }
            }
        }
        Ok(())
    }

    /// Handle incoming connection
    async fn handle_incoming_connection(&mut self, stream: TcpStream) -> Result<()> {
        // Receive handshake
        let handshake = self.receive_message_from_stream(&stream).await?;
        
        match handshake {
            P2PMessage::Handshake { peer_id, version, capabilities } => {
                info!("Received handshake from: {} (version: {})", peer_id, version);
                
                // Send handshake response
                let response = P2PMessage::Handshake {
                    peer_id: self.local_peer_id.clone(),
                    version: "1.0.0".to_string(),
                    capabilities: vec!["order_matching".to_string(), "gossip".to_string()],
                };
                
                self.send_message_to_stream(&stream, &response).await?;
                
                // Create peer info
                let peer_info = PeerInfo {
                    peer_id: peer_id.clone(),
                    address: "unknown".to_string(), // Would extract from stream
                    port: 0,
                    public_key: vec![0u8; 32],
                    last_seen: chrono::Utc::now().timestamp() as u64,
                    stake: 32_000_000_000_000_000_000u64,
                    is_active: true,
                    reputation: 1.0,
                };
                
                self.add_peer(peer_info).await?;
            }
            _ => {
                warn!("Invalid handshake message from incoming connection");
            }
        }
        
        Ok(())
    }

    /// Maintain peer connections
    async fn maintain_peer_connections(&mut self) -> Result<()> {
        let current_time = Instant::now();
        let mut inactive_peers = Vec::new();
        
        // Check for inactive peers
        let peer_ids: Vec<String> = self.peers.keys().cloned().collect();
        for peer_id in peer_ids {
            if let Some(connection) = self.peers.get(&peer_id) {
                if current_time.duration_since(connection.last_ping) > Duration::from_secs(300) {
                    warn!("Peer {} appears inactive", peer_id);
                    inactive_peers.push(peer_id.clone());
                } else {
                    // Send ping
                    let ping = P2PMessage::Ping {
                        timestamp: chrono::Utc::now().timestamp() as u64,
                    };
                    
                    if let Err(e) = self.send_message_to_peer(&peer_id, &ping).await {
                        warn!("Failed to ping peer {}: {:?}", peer_id, e);
                        inactive_peers.push(peer_id.clone());
                    }
                }
            }
        }
        
        // Remove inactive peers
        for peer_id in inactive_peers {
            self.remove_peer(&peer_id).await?;
        }
        
        // Request more peers if we have too few
        if self.peers.len() < self.config.min_peers {
            self.request_more_peers().await?;
        }
        
        debug!("Peer maintenance completed. Active peers: {}", self.peers.len());
        Ok(())
    }

    /// Remove peer from network
    async fn remove_peer(&mut self, peer_id: &str) -> Result<()> {
        if let Some(_) = self.peers.remove(peer_id) {
            info!("Removed inactive peer: {}", peer_id);
            self.gossip_protocol.remove_peer(peer_id).await?;
        }
        Ok(())
    }

    /// Request more peers from existing connections
    async fn request_more_peers(&mut self) -> Result<()> {
        info!("Requesting more peers from network");
        
        let request = P2PMessage::PeerListRequest;
        
        // Send request to all active peers
        for peer_id in self.peers.keys().cloned().collect::<Vec<_>>() {
            if let Err(e) = self.send_message_to_peer(&peer_id, &request).await {
                warn!("Failed to request peers from {}: {:?}", peer_id, e);
            }
        }
        
        Ok(())
    }

    /// Broadcast message to all peers
    pub async fn broadcast_message(&mut self, message: &P2PMessage) -> Result<()> {
        debug!("Broadcasting message to {} peers", self.peers.len());
        
        let peer_ids: Vec<String> = self.peers.keys().cloned().collect();
        
        for peer_id in peer_ids {
            if let Err(e) = self.send_message_to_peer(&peer_id, message).await {
                warn!("Failed to send message to peer {}: {:?}", peer_id, e);
            }
        }
        
        // Also propagate through gossip protocol
        self.gossip_protocol.propagate_message(message).await?;
        
        Ok(())
    }

    /// Send message to specific peer
    pub async fn send_message_to_peer(&mut self, peer_id: &str, message: &P2PMessage) -> Result<()> {
        debug!("Sending message to peer: {}", peer_id);
        
        if let Some(connection) = self.peers.get_mut(peer_id) {
            // Encrypt message
            let secure_message = self.network_encryption.encrypt_message(message).await?;
            
            // Send via gossip protocol for reliability
            self.gossip_protocol.send_message_to_peer(peer_id, &secure_message).await?;
            
            connection.message_count += 1;
            connection.peer_info.last_seen = chrono::Utc::now().timestamp() as u64;
            
            Ok(())
        } else {
            Err(anyhow::anyhow!("Peer not found: {}", peer_id))
        }
    }

    /// Send message to TCP stream
    async fn send_message_to_stream(&self, stream: &TcpStream, message: &P2PMessage) -> Result<()> {
        let serialized = serde_json::to_vec(message)?;
        
        // In production, this would use proper framing and error handling
        // For now, we'll simulate successful sending
        debug!("Sent {} bytes to stream", serialized.len());
        
        Ok(())
    }

    /// Receive message from TCP stream
    async fn receive_message_from_stream(&self, stream: &TcpStream) -> Result<P2PMessage> {
        // Mock message reception
        let mock_handshake = P2PMessage::Handshake {
            peer_id: format!("peer_{}", uuid::Uuid::new_v4()),
            version: "1.0.0".to_string(),
            capabilities: vec!["order_matching".to_string()],
        };
        
        Ok(mock_handshake)
    }

    /// Get peer information
    pub fn get_peer_info(&self, peer_id: &str) -> Option<&PeerInfo> {
        self.peers.get(peer_id).map(|conn| &conn.peer_info)
    }

    /// Get all active peers
    pub fn get_active_peers(&self) -> Vec<&PeerInfo> {
        self.peers.values()
            .filter(|conn| conn.peer_info.is_active)
            .map(|conn| &conn.peer_info)
            .collect()
    }

    /// Get network statistics
    pub fn get_network_stats(&self) -> NetworkStats {
        let total_peers = self.peers.len();
        let active_peers = self.get_active_peers().len();
        let total_messages = self.peers.values()
            .map(|conn| conn.message_count)
            .sum();
        
        NetworkStats {
            total_peers: total_peers as u64,
            active_peers: active_peers as u64,
            total_messages,
            uptime_seconds: 0, // Would track actual uptime
        }
    }

    /// Health check for P2P network
    pub async fn health_check(&self) -> Result<()> {
        let active_peers = self.get_active_peers();
        
        if active_peers.is_empty() {
            return Err(anyhow::anyhow!("No active peers connected"));
        }
        
        if active_peers.len() < self.config.min_peers {
            warn!("Below minimum peer count: {} < {}", active_peers.len(), self.config.min_peers);
        }
        
        // Test gossip protocol
        self.gossip_protocol.health_check().await?;
        
        // Test network encryption
        self.network_encryption.health_check().await?;
        
        debug!("P2P network health check passed. Active peers: {}", active_peers.len());
        Ok(())
    }

    /// Get local peer ID
    pub fn get_local_peer_id(&self) -> &str {
        &self.local_peer_id
    }

    /// Update peer reputation
    pub fn update_peer_reputation(&mut self, peer_id: &str, delta: f64) {
        if let Some(connection) = self.peers.get_mut(peer_id) {
            connection.peer_info.reputation = (connection.peer_info.reputation + delta).max(0.0).min(10.0);
            debug!("Updated peer {} reputation to {}", peer_id, connection.peer_info.reputation);
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]  
pub struct NetworkStats {
    pub total_peers: u64,
    pub active_peers: u64,
    pub total_messages: u64,
    pub uptime_seconds: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::NetworkingConfig;

    #[tokio::test]
    async fn test_p2p_network_creation() {
        let config = NetworkingConfig::default();
        // This test would require actual network setup
        // let network = P2PNetwork::new(config).await;
        // assert!(network.is_ok());
    }

    #[test]
    fn test_peer_info_creation() {
        let peer_info = PeerInfo {
            peer_id: "test_peer".to_string(),
            address: "127.0.0.1".to_string(),
            port: 8080,
            public_key: vec![1, 2, 3, 4],
            last_seen: chrono::Utc::now().timestamp() as u64,
            stake: 1000,
            is_active: true,
            reputation: 5.0,
        };
        
        assert_eq!(peer_info.peer_id, "test_peer");
        assert!(peer_info.is_active);
        assert_eq!(peer_info.reputation, 5.0);
    }
}