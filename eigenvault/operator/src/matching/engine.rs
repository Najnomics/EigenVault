use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{info, debug, warn};
use tokio::sync::RwLock;
use uuid::Uuid;

use super::{Order, OrderBook, OrderType, OrderStatus, DecryptedOrder};
use crate::config::MatchingConfig;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderMatch {
    pub match_id: String,
    pub buy_order: Order,
    pub sell_order: Order,
    pub matched_price: f64,
    pub matched_amount: f64,
    pub timestamp: u64,
    pub pool_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchingResult {
    pub matches: Vec<OrderMatch>,
    pub unmatched_orders: Vec<Order>,
    pub total_volume: f64,
    pub average_price: f64,
}

pub struct MatchingEngine {
    config: MatchingConfig,
    order_books: RwLock<HashMap<String, OrderBook>>,
    pending_orders: RwLock<Vec<DecryptedOrder>>,
    recent_matches: RwLock<Vec<OrderMatch>>,
}

impl MatchingEngine {
    pub async fn new(config: MatchingConfig) -> Result<Self> {
        info!("Initializing matching engine with config: {:?}", config);
        
        Ok(Self {
            config,
            order_books: RwLock::new(HashMap::new()),
            pending_orders: RwLock::new(Vec::new()),
            recent_matches: RwLock::new(Vec::new()),
        })
    }

    /// Add encrypted order to pending queue
    pub async fn add_encrypted_order(&self, order_id: String, encrypted_data: Vec<u8>) -> Result<()> {
        info!("Adding encrypted order {} to pending queue", order_id);
        
        // For now, we'll create a mock decrypted order
        // In production, this would decrypt using operator private key
        let decrypted_order = DecryptedOrder {
            id: order_id.clone(),
            trader: format!("trader_{}", order_id.chars().take(8).collect::<String>()),
            pool_key: "ETH_USDC_3000".to_string(),
            order_type: if order_id.len() % 2 == 0 { OrderType::Buy } else { OrderType::Buy },
            amount: 1000.0 + (order_id.len() as f64 * 100.0),
            price: 2000.0 + (order_id.len() as f64 * 10.0),
            deadline: chrono::Utc::now().timestamp() as u64 + 3600, // 1 hour from now
            encrypted_data,
        };

        let mut pending = self.pending_orders.write().await;
        pending.push(decrypted_order);
        
        debug!("Added order {} to pending queue. Total pending: {}", order_id, pending.len());
        Ok(())
    }

    /// Process pending orders and find matches
    pub async fn process_pending_orders(&self) -> Result<Vec<OrderMatch>> {
        let mut pending = self.pending_orders.write().await;
        if pending.is_empty() {
            return Ok(vec![]);
        }

        info!("Processing {} pending orders", pending.len());
        
        let mut all_matches = Vec::new();
        let mut processed_indices = Vec::new();

        // Group orders by pool
        let mut pool_orders: HashMap<String, Vec<(usize, &DecryptedOrder)>> = HashMap::new();
        for (idx, order) in pending.iter().enumerate() {
            pool_orders.entry(order.pool_key.clone())
                      .or_insert_with(Vec::new)
                      .push((idx, order));
        }

        // Process each pool separately
        for (pool_key, orders) in pool_orders {
            if orders.len() < 2 {
                debug!("Pool {} has only {} orders, skipping matching", pool_key, orders.len());
                continue;
            }

            info!("Processing {} orders for pool {}", orders.len(), pool_key);
            
            // Convert to Order structs for matching
            let mut pool_order_book = OrderBook::new(pool_key.clone());
            
            for (idx, decrypted_order) in &orders {
                let order = Order {
                    id: decrypted_order.id.clone(),
                    trader: decrypted_order.trader.clone(),
                    pool_key: decrypted_order.pool_key.clone(),
                    order_type: decrypted_order.order_type.clone(),
                    amount: decrypted_order.amount,
                    price: decrypted_order.price,
                    status: OrderStatus::Pending,
                    timestamp: chrono::Utc::now().timestamp() as u64,
                    deadline: decrypted_order.deadline,
                };
                
                pool_order_book.add_order(order).await?;
            }

            // Find matches in this pool
            let matches = self.find_matches_in_pool(&pool_order_book).await?;
            
            // Track which orders were matched
            for order_match in &matches {
                for (idx, _) in &orders {
                    if order_match.buy_order.id == pending[*idx].id || 
                       order_match.sell_order.id == pending[*idx].id {
                        processed_indices.push(*idx);
                    }
                }
            }
            
            all_matches.extend(matches);
        }

        // Remove processed orders from pending (in reverse order to maintain indices)
        processed_indices.sort_by(|a, b| b.cmp(a));
        processed_indices.dedup();
        
        for idx in processed_indices {
            pending.remove(idx);
        }

        if !all_matches.is_empty() {
            info!("Found {} matches across all pools", all_matches.len());
            
            // Store recent matches
            let mut recent = self.recent_matches.write().await;
            recent.extend(all_matches.clone());
            
            // Keep only last 100 matches
            if recent.len() > 100 {
                let overflow = recent.len() - 100;
                recent.drain(0..overflow);
            }
        }

        Ok(all_matches)
    }

    /// Find matches for decrypted orders
    pub async fn find_matches(&self, orders: Vec<DecryptedOrder>) -> Result<Vec<OrderMatch>> {
        if orders.len() < 2 {
            return Ok(vec![]);
        }

        info!("Finding matches for {} decrypted orders", orders.len());
        
        // Group by pool key
        let mut pool_groups: HashMap<String, Vec<DecryptedOrder>> = HashMap::new();
        for order in orders {
            pool_groups.entry(order.pool_key.clone())
                      .or_insert_with(Vec::new)
                      .push(order);
        }

        let mut all_matches = Vec::new();

        for (pool_key, pool_orders) in pool_groups {
            if pool_orders.len() < 2 {
                continue;
            }

            // Create order book for this pool
            let mut order_book = OrderBook::new(pool_key.clone());
            
            for decrypted_order in pool_orders {
                let order = Order {
                    id: decrypted_order.id,
                    trader: decrypted_order.trader,
                    pool_key: decrypted_order.pool_key,
                    order_type: decrypted_order.order_type,
                    amount: decrypted_order.amount,
                    price: decrypted_order.price,
                    status: OrderStatus::Pending,
                    timestamp: chrono::Utc::now().timestamp() as u64,
                    deadline: decrypted_order.deadline,
                };
                
                order_book.add_order(order).await?;
            }

            // Find matches
            let matches = self.find_matches_in_pool(&order_book).await?;
            all_matches.extend(matches);
        }

        Ok(all_matches)
    }

    /// Find matches within a single pool's order book
    async fn find_matches_in_pool(&self, order_book: &OrderBook) -> Result<Vec<OrderMatch>> {
        let buy_orders = order_book.get_buy_orders().await;
        let sell_orders = order_book.get_sell_orders().await;
        
        if buy_orders.is_empty() || sell_orders.is_empty() {
            debug!("No matching possible: {} buy orders, {} sell orders", 
                   buy_orders.len(), sell_orders.len());
            return Ok(vec![]);
        }

        let mut matches = Vec::new();
        
        // Simple price-time priority matching
        for buy_order in &buy_orders {
            for sell_order in &sell_orders {
                if self.can_match(buy_order, sell_order) {
                    let matched_price = self.calculate_match_price(buy_order, sell_order);
                    let matched_amount = self.calculate_match_amount(buy_order, sell_order);
                    
                    let order_match = OrderMatch {
                        match_id: Uuid::new_v4().to_string(),
                        buy_order: buy_order.clone(),
                        sell_order: sell_order.clone(),
                        matched_price,
                        matched_amount,
                        timestamp: chrono::Utc::now().timestamp() as u64,
                        pool_key: buy_order.pool_key.clone(),
                    };
                    
                    matches.push(order_match);
                    info!("Found match: {} units at price {}", matched_amount, matched_price);
                }
            }
        }

        Ok(matches)
    }

    /// Check if two orders can be matched
    fn can_match(&self, buy_order: &Order, sell_order: &Order) -> bool {
        // Basic matching criteria
        buy_order.pool_key == sell_order.pool_key &&
        buy_order.price >= sell_order.price &&
        buy_order.status == OrderStatus::Pending &&
        sell_order.status == OrderStatus::Pending &&
        buy_order.trader != sell_order.trader &&
        buy_order.deadline > chrono::Utc::now().timestamp() as u64 &&
        sell_order.deadline > chrono::Utc::now().timestamp() as u64
    }

    /// Calculate the execution price for a match
    fn calculate_match_price(&self, buy_order: &Order, sell_order: &Order) -> f64 {
        // Use mid-point pricing
        (buy_order.price + sell_order.price) / 2.0
    }

    /// Calculate the execution amount for a match
    fn calculate_match_amount(&self, buy_order: &Order, sell_order: &Order) -> f64 {
        // Use minimum of both amounts
        buy_order.amount.min(sell_order.amount)
    }

    /// Get recent matching statistics
    pub async fn get_matching_stats(&self) -> Result<MatchingResult> {
        let recent_matches = self.recent_matches.read().await;
        let pending_orders = self.pending_orders.read().await;
        
        let total_volume = recent_matches.iter()
            .map(|m| m.matched_amount)
            .sum::<f64>();
            
        let average_price = if recent_matches.is_empty() {
            0.0
        } else {
            recent_matches.iter()
                .map(|m| m.matched_price)
                .sum::<f64>() / recent_matches.len() as f64
        };

        // Convert pending orders to unmatched orders
        let unmatched_orders: Vec<Order> = pending_orders.iter()
            .map(|decrypted| Order {
                id: decrypted.id.clone(),
                trader: decrypted.trader.clone(),
                pool_key: decrypted.pool_key.clone(),
                order_type: decrypted.order_type.clone(),
                amount: decrypted.amount,
                price: decrypted.price,
                status: OrderStatus::Pending,
                timestamp: chrono::Utc::now().timestamp() as u64,
                deadline: decrypted.deadline,
            })
            .collect();

        Ok(MatchingResult {
            matches: recent_matches.clone(),
            unmatched_orders,
            total_volume,
            average_price,
        })
    }

    /// Health check for the matching engine
    pub async fn health_check(&self) -> Result<()> {
        let pending_count = self.pending_orders.read().await.len();
        let recent_matches_count = self.recent_matches.read().await.len();
        
        debug!("Matching engine health: {} pending orders, {} recent matches", 
               pending_count, recent_matches_count);
        
        // Check if engine is responsive
        if pending_count > self.config.max_pending_orders {
            warn!("High number of pending orders: {}", pending_count);
        }
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_matching_engine_creation() {
        let config = crate::config::MatchingConfig::default();
        let engine = MatchingEngine::new(config).await;
        assert!(engine.is_ok());
    }
    
    #[tokio::test]
    async fn test_add_encrypted_order() {
        let config = crate::config::MatchingConfig::default();
        let engine = MatchingEngine::new(config).await.unwrap();
        
        let result = engine.add_encrypted_order(
            "test_order_1".to_string(), 
            vec![1, 2, 3, 4]
        ).await;
        
        assert!(result.is_ok());
    }
}