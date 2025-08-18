use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use tokio::sync::RwLock;
use tracing::{debug, info};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum OrderType {
    Buy,
    Sell,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum OrderStatus {
    Pending,
    PartiallyFilled,
    Filled,
    Cancelled,
    Expired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Order {
    pub id: String,
    pub trader: String,
    pub pool_key: String,
    pub order_type: OrderType,
    pub amount: f64,
    pub price: f64,
    pub status: OrderStatus,
    pub timestamp: u64,
    pub deadline: u64,
}

impl Order {
    pub fn new(
        id: String,
        trader: String,
        pool_key: String,
        order_type: OrderType,
        amount: f64,
        price: f64,
        deadline: u64,
    ) -> Self {
        Self {
            id,
            trader,
            pool_key,
            order_type,
            amount,
            price,
            status: OrderStatus::Pending,
            timestamp: chrono::Utc::now().timestamp() as u64,
            deadline,
        }
    }

    pub fn is_expired(&self) -> bool {
        chrono::Utc::now().timestamp() as u64 > self.deadline
    }

    pub fn is_active(&self) -> bool {
        matches!(self.status, OrderStatus::Pending | OrderStatus::PartiallyFilled) && !self.is_expired()
    }
}

pub struct OrderBook {
    pub pool_key: String,
    // Price -> Vec<Order> (orders at that price level)
    buy_orders: RwLock<BTreeMap<OrderedFloat, Vec<Order>>>,
    sell_orders: RwLock<BTreeMap<OrderedFloat, Vec<Order>>>,
    // Order ID -> Order for quick lookup
    orders_by_id: RwLock<HashMap<String, Order>>,
    total_orders: RwLock<usize>,
}

// Wrapper for f64 to make it Ord for BTreeMap
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd)]
pub struct OrderedFloat(pub f64);

impl Eq for OrderedFloat {}

impl Ord for OrderedFloat {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.partial_cmp(other).unwrap_or(std::cmp::Ordering::Equal)
    }
}

impl From<f64> for OrderedFloat {
    fn from(value: f64) -> Self {
        OrderedFloat(value)
    }
}

impl OrderBook {
    pub fn new(pool_key: String) -> Self {
        info!("Creating new order book for pool: {}", pool_key);
        
        Self {
            pool_key,
            buy_orders: RwLock::new(BTreeMap::new()),
            sell_orders: RwLock::new(BTreeMap::new()),
            orders_by_id: RwLock::new(HashMap::new()),
            total_orders: RwLock::new(0),
        }
    }

    /// Add an order to the order book
    pub async fn add_order(&mut self, order: Order) -> Result<()> {
        debug!("Adding order {} to order book for pool {}", order.id, self.pool_key);
        
        if order.is_expired() {
            return Err(anyhow::anyhow!("Cannot add expired order: {}", order.id));
        }

        let price_key = OrderedFloat::from(order.price);
        
        match order.order_type {
            OrderType::Buy => {
                let mut buy_orders = self.buy_orders.write().await;
                buy_orders.entry(price_key)
                         .or_insert_with(Vec::new)
                         .push(order.clone());
                
                // Keep buy orders sorted by price (highest first) and time (earliest first)
                if let Some(orders_at_price) = buy_orders.get_mut(&price_key) {
                    orders_at_price.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
                }
            }
            OrderType::Sell => {
                let mut sell_orders = self.sell_orders.write().await;
                sell_orders.entry(price_key)
                          .or_insert_with(Vec::new)
                          .push(order.clone());
                
                // Keep sell orders sorted by price (lowest first) and time (earliest first)
                if let Some(orders_at_price) = sell_orders.get_mut(&price_key) {
                    orders_at_price.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
                }
            }
        }

        // Add to lookup map
        let order_id = order.id.clone();
        let mut orders_by_id = self.orders_by_id.write().await;
        orders_by_id.insert(order_id.clone(), order);
        
        // Update total count
        let mut total = self.total_orders.write().await;
        *total += 1;
        
        info!("Added order {} to order book. Total orders: {}", order_id, *total);
        Ok(())
    }

    /// Remove an order from the order book
    pub async fn remove_order(&mut self, order_id: &str) -> Result<Option<Order>> {
        debug!("Removing order {} from order book", order_id);
        
        let mut orders_by_id = self.orders_by_id.write().await;
        
        if let Some(order) = orders_by_id.remove(order_id) {
            let price_key = OrderedFloat::from(order.price);
            
            match order.order_type {
                OrderType::Buy => {
                    let mut buy_orders = self.buy_orders.write().await;
                    if let Some(orders_at_price) = buy_orders.get_mut(&price_key) {
                        orders_at_price.retain(|o| o.id != order_id);
                        if orders_at_price.is_empty() {
                            buy_orders.remove(&price_key);
                        }
                    }
                }
                OrderType::Sell => {
                    let mut sell_orders = self.sell_orders.write().await;
                    if let Some(orders_at_price) = sell_orders.get_mut(&price_key) {
                        orders_at_price.retain(|o| o.id != order_id);
                        if orders_at_price.is_empty() {
                            sell_orders.remove(&price_key);
                        }
                    }
                }
            }
            
            // Update total count
            let mut total = self.total_orders.write().await;
            *total = total.saturating_sub(1);
            
            info!("Removed order {} from order book. Total orders: {}", order_id, *total);
            return Ok(Some(order));
        }
        
        Ok(None)
    }

    /// Get all buy orders sorted by price (highest first) and time (earliest first)
    pub async fn get_buy_orders(&self) -> Vec<Order> {
        let buy_orders = self.buy_orders.read().await;
        let mut all_orders = Vec::new();
        
        // Iterate in reverse order for buy orders (highest price first)
        for (_, orders_at_price) in buy_orders.iter().rev() {
            for order in orders_at_price {
                if order.is_active() {
                    all_orders.push(order.clone());
                }
            }
        }
        
        all_orders
    }

    /// Get all sell orders sorted by price (lowest first) and time (earliest first)
    pub async fn get_sell_orders(&self) -> Vec<Order> {
        let sell_orders = self.sell_orders.read().await;
        let mut all_orders = Vec::new();
        
        // Iterate in normal order for sell orders (lowest price first)
        for (_, orders_at_price) in sell_orders.iter() {
            for order in orders_at_price {
                if order.is_active() {
                    all_orders.push(order.clone());
                }
            }
        }
        
        all_orders
    }

    /// Get best bid (highest buy price)
    pub async fn get_best_bid(&self) -> Option<f64> {
        let buy_orders = self.buy_orders.read().await;
        buy_orders.keys().last().map(|price| price.0)
    }

    /// Get best ask (lowest sell price)
    pub async fn get_best_ask(&self) -> Option<f64> {
        let sell_orders = self.sell_orders.read().await;
        sell_orders.keys().next().map(|price| price.0)
    }

    /// Get spread between best bid and ask
    pub async fn get_spread(&self) -> Option<f64> {
        match (self.get_best_bid().await, self.get_best_ask().await) {
            (Some(bid), Some(ask)) => Some(ask - bid),
            _ => None,
        }
    }

    /// Get order by ID
    pub async fn get_order(&self, order_id: &str) -> Option<Order> {
        let orders_by_id = self.orders_by_id.read().await;
        orders_by_id.get(order_id).cloned()
    }

    /// Get all orders for a specific trader
    pub async fn get_orders_by_trader(&self, trader: &str) -> Vec<Order> {
        let orders_by_id = self.orders_by_id.read().await;
        orders_by_id.values()
                   .filter(|order| order.trader == trader && order.is_active())
                   .cloned()
                   .collect()
    }

    /// Update order status
    pub async fn update_order_status(&mut self, order_id: &str, new_status: OrderStatus) -> Result<()> {
        let mut orders_by_id = self.orders_by_id.write().await;
        
        if let Some(order) = orders_by_id.get_mut(order_id) {
            order.status = new_status;
            debug!("Updated order {} status to {:?}", order_id, order.status);
            Ok(())
        } else {
            Err(anyhow::anyhow!("Order not found: {}", order_id))
        }
    }

    /// Clean up expired orders
    pub async fn cleanup_expired_orders(&mut self) -> Result<Vec<String>> {
        let mut expired_order_ids = Vec::new();
        let current_time = chrono::Utc::now().timestamp() as u64;
        
        // Find expired orders
        {
            let orders_by_id = self.orders_by_id.read().await;
            for (order_id, order) in orders_by_id.iter() {
                if order.deadline <= current_time && order.is_active() {
                    expired_order_ids.push(order_id.clone());
                }
            }
        }
        
        // Remove expired orders
        for order_id in &expired_order_ids {
            if let Some(mut order) = self.remove_order(order_id).await? {
                order.status = OrderStatus::Expired;
                debug!("Expired order: {}", order_id);
            }
        }
        
        if !expired_order_ids.is_empty() {
            info!("Cleaned up {} expired orders", expired_order_ids.len());
        }
        
        Ok(expired_order_ids)
    }

    /// Get order book statistics
    pub async fn get_stats(&self) -> OrderBookStats {
        let total_orders = *self.total_orders.read().await;
        let buy_orders = self.buy_orders.read().await;
        let sell_orders = self.sell_orders.read().await;
        
        let active_buy_count = buy_orders.values()
            .flatten()
            .filter(|order| order.is_active())
            .count();
            
        let active_sell_count = sell_orders.values()
            .flatten()
            .filter(|order| order.is_active())
            .count();
        
        let best_bid = buy_orders.keys().last().map(|price| price.0);
        let best_ask = sell_orders.keys().next().map(|price| price.0);
        
        let spread = match (best_bid, best_ask) {
            (Some(bid), Some(ask)) => Some(ask - bid),
            _ => None,
        };

        OrderBookStats {
            pool_key: self.pool_key.clone(),
            total_orders,
            active_buy_orders: active_buy_count,
            active_sell_orders: active_sell_count,
            best_bid,
            best_ask,
            spread,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OrderBookStats {
    pub pool_key: String,
    pub total_orders: usize,
    pub active_buy_orders: usize,
    pub active_sell_orders: usize,
    pub best_bid: Option<f64>,
    pub best_ask: Option<f64>,
    pub spread: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_order_book_creation() {
        let order_book = OrderBook::new("ETH_USDC_3000".to_string());
        assert_eq!(order_book.pool_key, "ETH_USDC_3000");
    }

    #[tokio::test]
    async fn test_add_buy_order() {
        let mut order_book = OrderBook::new("ETH_USDC_3000".to_string());
        
        let order = Order::new(
            "order_1".to_string(),
            "trader_1".to_string(),
            "ETH_USDC_3000".to_string(),
            OrderType::Buy,
            100.0,
            2000.0,
            chrono::Utc::now().timestamp() as u64 + 3600,
        );
        
        let result = order_book.add_order(order).await;
        assert!(result.is_ok());
        
        let buy_orders = order_book.get_buy_orders().await;
        assert_eq!(buy_orders.len(), 1);
        assert_eq!(buy_orders[0].id, "order_1");
    }

    #[tokio::test]
    async fn test_get_best_bid_ask() {
        let mut order_book = OrderBook::new("ETH_USDC_3000".to_string());
        
        let buy_order = Order::new(
            "buy_1".to_string(),
            "trader_1".to_string(),
            "ETH_USDC_3000".to_string(),
            OrderType::Buy,
            100.0,
            1999.0,
            chrono::Utc::now().timestamp() as u64 + 3600,
        );
        
        let sell_order = Order::new(
            "sell_1".to_string(),
            "trader_2".to_string(),
            "ETH_USDC_3000".to_string(),
            OrderType::Sell,
            100.0,
            2001.0,
            chrono::Utc::now().timestamp() as u64 + 3600,
        );
        
        order_book.add_order(buy_order).await.unwrap();
        order_book.add_order(sell_order).await.unwrap();
        
        assert_eq!(order_book.get_best_bid().await, Some(1999.0));
        assert_eq!(order_book.get_best_ask().await, Some(2001.0));
        assert_eq!(order_book.get_spread().await, Some(2.0));
    }
}