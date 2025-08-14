use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::time::{sleep, Duration, Instant};
use tracing::{debug, info, warn};

use crate::config::NetworkingConfig;
use super::{PeerInfo, SecureMessage};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    OrderAnnouncement,
    TaskNotification,
    ProofShare,
    PeerDiscovery,
    Heartbeat,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GossipMessage {
    pub message_id: String,
    pub message_type: MessageType,
    pub sender_id: String,
    pub timestamp: u64,
    pub ttl: u32,
    pub payload: Vec<u8>,
    pub signature: Vec<u8>,
}

#[derive(Debug, Clone)]
struct MessageState {
    message: GossipMessage,
    first_seen: Instant,
    propagation_count: u32,
    peers_sent_to: Vec<String>,
}

pub struct GossipProtocol {
    config: NetworkingConfig,
    local_peer_id: String,
    peers: HashMap<String, PeerInfo>,
    message_cache: HashMap<String, MessageState>,
    last_cleanup: Instant,
    message_sender: tokio::sync::mpsc::UnboundedSender<GossipMessage>,
    message_receiver: tokio::sync::mpsc::UnboundedReceiver<GossipMessage>,
}

impl GossipProtocol {
    pub async fn new(config: &NetworkingConfig) -> Result<Self> {
        info!("Initializing gossip protocol");
        
        let (message_sender, message_receiver) = tokio::sync::mpsc::unbounded_channel();
        
        Ok(Self {
            config: config.clone(),
            local_peer_id: format!("gossip_peer_{}", uuid::Uuid::new_v4()),
            peers: HashMap::new(),
            message_cache: HashMap::new(),
            last_cleanup: Instant::now(),
            message_sender,
            message_receiver,
        })
    }

    /// Add peer to gossip network
    pub async fn add_peer(&mut self, peer_info: PeerInfo) -> Result<()> {
        debug!("Adding peer to gossip network: {}", peer_info.peer_id);
        self.peers.insert(peer_info.peer_id.clone(), peer_info);
        Ok(())
    }

    /// Remove peer from gossip network
    pub async fn remove_peer(&mut self, peer_id: &str) -> Result<()> {
        debug!("Removing peer from gossip network: {}", peer_id);
        self.peers.remove(peer_id);
        
        // Clean up message cache entries for this peer
        for message_state in self.message_cache.values_mut() {
            message_state.peers_sent_to.retain(|id| id != peer_id);
        }
        
        Ok(())
    }

    /// Propagate message through gossip network
    pub async fn propagate_message(&mut self, message: &super::P2PMessage) -> Result<()> {
        let gossip_message = self.create_gossip_message(message).await?;
        
        info!("Propagating message: {} to {} peers", 
              gossip_message.message_id, self.peers.len());
        
        // Add to our message cache
        self.add_to_cache(gossip_message.clone()).await?;
        
        // Send to selected peers using gossip algorithm
        let target_peers = self.select_gossip_targets(&gossip_message).await?;
        
        for peer_id in target_peers {
            if let Err(e) = self.send_gossip_message(&peer_id, &gossip_message).await {
                warn!("Failed to send gossip message to peer {}: {:?}", peer_id, e);
            }
        }
        
        Ok(())
    }

    /// Send message to specific peer
    pub async fn send_message_to_peer(&mut self, peer_id: &str, message: &SecureMessage) -> Result<()> {
        debug!("Sending direct message to peer: {}", peer_id);
        
        if !self.peers.contains_key(peer_id) {
            return Err(anyhow::anyhow!("Peer not found: {}", peer_id));
        }
        
        // Convert secure message to gossip format
        let gossip_message = GossipMessage {
            message_id: uuid::Uuid::new_v4().to_string(),
            message_type: MessageType::Custom("direct_message".to_string()),
            sender_id: self.local_peer_id.clone(),
            timestamp: chrono::Utc::now().timestamp() as u64,
            ttl: 1, // Direct message, no propagation
            payload: message.encrypted_data.clone(),
            signature: message.signature.clone(),
        };
        
        self.send_gossip_message(peer_id, &gossip_message).await?;
        Ok(())
    }

    /// Create gossip message from P2P message
    async fn create_gossip_message(&self, message: &super::P2PMessage) -> Result<GossipMessage> {
        let message_type = match message {
            super::P2PMessage::OrderGossip { .. } => MessageType::OrderAnnouncement,
            super::P2PMessage::TaskAnnouncement { .. } => MessageType::TaskNotification,
            super::P2PMessage::ProofShare { .. } => MessageType::ProofShare,
            super::P2PMessage::Ping { .. } => MessageType::Heartbeat,
            _ => MessageType::Custom("general".to_string()),
        };
        
        let payload = serde_json::to_vec(message)?;
        let signature = self.sign_message(&payload).await?;
        
        let gossip_message = GossipMessage {
            message_id: uuid::Uuid::new_v4().to_string(),
            message_type,
            sender_id: self.local_peer_id.clone(),
            timestamp: chrono::Utc::now().timestamp() as u64,
            ttl: 5, // Allow 5 hops
            payload,
            signature,
        };
        
        Ok(gossip_message)
    }

    /// Add message to cache
    async fn add_to_cache(&mut self, message: GossipMessage) -> Result<()> {
        let message_state = MessageState {
            message: message.clone(),
            first_seen: Instant::now(),
            propagation_count: 0,
            peers_sent_to: Vec::new(),
        };
        
        self.message_cache.insert(message.message_id.clone(), message_state);
        
        // Cleanup old messages periodically
        if self.last_cleanup.elapsed() > Duration::from_secs(300) { // 5 minutes
            self.cleanup_message_cache().await?;
            self.last_cleanup = Instant::now();
        }
        
        Ok(())
    }

    /// Select peers for gossip propagation
    async fn select_gossip_targets(&self, message: &GossipMessage) -> Result<Vec<String>> {
        let mut targets = Vec::new();
        
        // Use simple gossip algorithm: send to sqrt(n) random peers
        let target_count = (self.peers.len() as f64).sqrt().ceil() as usize;
        let target_count = target_count.max(1).min(self.peers.len());
        
        // Get all peer IDs except the sender
        let available_peers: Vec<&String> = self.peers.keys()
            .filter(|&peer_id| peer_id != &message.sender_id)
            .collect();
        
        if available_peers.is_empty() {
            return Ok(targets);
        }
        
        // Select random peers
        use rand::seq::SliceRandom;
        let mut rng = rand::thread_rng();
        let selected_peers = available_peers.choose_multiple(&mut rng, target_count);
        
        for peer_id in selected_peers {
            targets.push((*peer_id).clone());
        }
        
        debug!("Selected {} peers for gossip propagation", targets.len());
        Ok(targets)
    }

    /// Send gossip message to specific peer
    async fn send_gossip_message(&mut self, peer_id: &str, message: &GossipMessage) -> Result<()> {
        debug!("Sending gossip message {} to peer {}", message.message_id, peer_id);
        
        // In production, this would use actual network transport
        // For now, we'll simulate successful sending
        
        // Update message state
        if let Some(message_state) = self.message_cache.get_mut(&message.message_id) {
            message_state.peers_sent_to.push(peer_id.to_string());
            message_state.propagation_count += 1;
        }
        
        // Send via message queue (in production, would use actual network)
        self.message_sender.send(message.clone())?;
        
        Ok(())
    }

    /// Handle incoming gossip message
    pub async fn handle_incoming_message(&mut self, message: GossipMessage) -> Result<bool> {
        debug!("Handling incoming gossip message: {}", message.message_id);
        
        // Check if we've already seen this message
        if self.message_cache.contains_key(&message.message_id) {
            debug!("Message already seen, ignoring: {}", message.message_id);
            return Ok(false);
        }
        
        // Verify message signature
        if !self.verify_message_signature(&message).await? {
            warn!("Invalid message signature: {}", message.message_id);
            return Ok(false);
        }
        
        // Check TTL
        if message.ttl == 0 {
            debug!("Message TTL expired: {}", message.message_id);
            return Ok(false);
        }
        
        // Add to cache
        self.add_to_cache(message.clone()).await?;
        
        // Propagate to other peers if TTL allows
        if message.ttl > 1 {
            let mut propagated_message = message.clone();
            propagated_message.ttl -= 1;
            
            let target_peers = self.select_gossip_targets(&propagated_message).await?;
            
            for peer_id in target_peers {
                // Don't send back to the sender
                if peer_id != message.sender_id {
                    if let Err(e) = self.send_gossip_message(&peer_id, &propagated_message).await {
                        warn!("Failed to propagate message to peer {}: {:?}", peer_id, e);
                    }
                }
            }
        }
        
        info!("Processed gossip message: {}", message.message_id);
        Ok(true)
    }

    /// Cleanup old messages from cache
    async fn cleanup_message_cache(&mut self) -> Result<()> {
        let now = Instant::now();
        let max_age = Duration::from_secs(3600); // 1 hour
        
        let mut expired_messages = Vec::new();
        
        for (message_id, message_state) in &self.message_cache {
            if now.duration_since(message_state.first_seen) > max_age {
                expired_messages.push(message_id.clone());
            }
        }
        
        for message_id in expired_messages {
            self.message_cache.remove(&message_id);
        }
        
        debug!("Cleaned up {} expired messages from cache", 
               self.message_cache.len());
        
        Ok(())
    }

    /// Sign message payload
    async fn sign_message(&self, payload: &[u8]) -> Result<Vec<u8>> {
        // Mock signature - in production, use actual cryptographic signing
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(payload);
        hasher.update(self.local_peer_id.as_bytes());
        hasher.update(&chrono::Utc::now().timestamp().to_le_bytes());
        
        Ok(hasher.finalize().to_vec())
    }

    /// Verify message signature
    async fn verify_message_signature(&self, message: &GossipMessage) -> Result<bool> {
        // Mock verification - in production, use actual cryptographic verification
        if message.signature.is_empty() {
            return Ok(false);
        }
        
        // Simple check: signature should be 32 bytes (SHA256)
        Ok(message.signature.len() == 32)
    }

    /// Get gossip statistics
    pub fn get_gossip_stats(&self) -> GossipStats {
        let total_messages = self.message_cache.len();
        let total_peers = self.peers.len();
        
        let propagation_counts: Vec<u32> = self.message_cache.values()
            .map(|state| state.propagation_count)
            .collect();
        
        let avg_propagation = if propagation_counts.is_empty() {
            0.0
        } else {
            propagation_counts.iter().sum::<u32>() as f64 / propagation_counts.len() as f64
        };
        
        GossipStats {
            total_messages: total_messages as u64,
            total_peers: total_peers as u64,
            average_propagation: avg_propagation,
            cache_size: total_messages as u64,
        }
    }

    /// Health check for gossip protocol
    pub async fn health_check(&self) -> Result<()> {
        if self.peers.is_empty() {
            return Err(anyhow::anyhow!("No peers in gossip network"));
        }
        
        // Check message cache size
        if self.message_cache.len() > 10000 {
            warn!("Large message cache size: {}", self.message_cache.len());
        }
        
        debug!("Gossip protocol health check passed. Peers: {}, Messages: {}", 
               self.peers.len(), self.message_cache.len());
        
        Ok(())
    }

    /// Get active peers
    pub fn get_active_peers(&self) -> Vec<&PeerInfo> {
        self.peers.values()
            .filter(|peer| peer.is_active)
            .collect()
    }

    /// Update peer reputation based on gossip behavior
    pub fn update_peer_reputation(&mut self, peer_id: &str, delta: f64) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.reputation = (peer.reputation + delta).max(0.0).min(10.0);
            debug!("Updated peer {} gossip reputation to {}", peer_id, peer.reputation);
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GossipStats {
    pub total_messages: u64,
    pub total_peers: u64,
    pub average_propagation: f64,
    pub cache_size: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::NetworkingConfig;

    #[tokio::test]
    async fn test_gossip_protocol_creation() {
        let config = NetworkingConfig::default();
        let gossip = GossipProtocol::new(&config).await;
        assert!(gossip.is_ok());
    }

    #[tokio::test]
    async fn test_add_remove_peer() -> Result<()> {
        let config = NetworkingConfig::default();
        let mut gossip = GossipProtocol::new(&config).await?;
        
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
        
        gossip.add_peer(peer_info.clone()).await?;
        assert!(gossip.peers.contains_key(&peer_info.peer_id));
        
        gossip.remove_peer(&peer_info.peer_id).await?;
        assert!(!gossip.peers.contains_key(&peer_info.peer_id));
        
        Ok(())
    }

    #[tokio::test]
    async fn test_message_cache() -> Result<()> {
        let config = NetworkingConfig::default();
        let mut gossip = GossipProtocol::new(&config).await?;
        
        let message = GossipMessage {
            message_id: "test_message".to_string(),
            message_type: MessageType::Heartbeat,
            sender_id: "test_sender".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
            ttl: 3,
            payload: vec![1, 2, 3, 4],
            signature: vec![5, 6, 7, 8],
        };
        
        gossip.add_to_cache(message.clone()).await?;
        assert!(gossip.message_cache.contains_key(&message.message_id));
        
        Ok(())
    }
}