import React, { useState, useEffect } from 'react';
import './VaultStatus.css';

const VaultStatus = ({ orders }) => {
  const [vaultStats, setVaultStats] = useState({
    totalOrders: 0,
    pendingOrders: 0,
    matchedOrders: 0,
    totalVolume: 0,
    averageExecutionTime: 0
  });

  const [recentActivity, setRecentActivity] = useState([]);

  useEffect(() => {
    // Calculate vault statistics
    const stats = {
      totalOrders: orders.length,
      pendingOrders: orders.filter(o => o.status === 'pending').length,
      matchedOrders: orders.filter(o => o.status === 'matched').length,
      totalVolume: orders.reduce((sum, o) => sum + parseFloat(o.amountSpecified || 0), 0),
      averageExecutionTime: orders.length > 0 ? 2.5 : 0 // Mock data
    };
    setVaultStats(stats);

    // Generate recent activity
    const activity = orders.slice(-5).map(order => ({
      id: order.id,
      type: order.zeroForOne ? 'Buy' : 'Sell',
      amount: order.amountSpecified,
      pool: order.poolKey,
      status: order.status,
      timestamp: new Date(order.timestamp).toLocaleTimeString()
    }));
    setRecentActivity(activity);
  }, [orders]);

  const getStatusColor = (status) => {
    switch (status) {
      case 'pending': return '#f59e0b';
      case 'matched': return '#10b981';
      case 'executed': return '#3b82f6';
      case 'expired': return '#ef4444';
      default: return '#6b7280';
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'pending': return '⏳';
      case 'matched': return '✅';
      case 'executed': return '🚀';
      case 'expired': return '⏰';
      default: return '❓';
    }
  };

  return (
    <div className="vault-status-container">
      <h2>Vault Status</h2>
      
      {/* Statistics Cards */}
      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-icon">📊</div>
          <div className="stat-content">
            <div className="stat-value">{vaultStats.totalOrders}</div>
            <div className="stat-label">Total Orders</div>
          </div>
        </div>
        
        <div className="stat-card">
          <div className="stat-icon">⏳</div>
          <div className="stat-content">
            <div className="stat-value">{vaultStats.pendingOrders}</div>
            <div className="stat-label">Pending</div>
          </div>
        </div>
        
        <div className="stat-card">
          <div className="stat-icon">✅</div>
          <div className="stat-content">
            <div className="stat-value">{vaultStats.matchedOrders}</div>
            <div className="stat-label">Matched</div>
          </div>
        </div>
        
        <div className="stat-card">
          <div className="stat-icon">💰</div>
          <div className="stat-content">
            <div className="stat-value">{vaultStats.totalVolume.toFixed(2)}</div>
            <div className="stat-label">Total Volume</div>
          </div>
        </div>
      </div>

      {/* Recent Activity */}
      <div className="activity-section">
        <h3>Recent Activity</h3>
        <div className="activity-list">
          {recentActivity.length > 0 ? (
            recentActivity.map((activity) => (
              <div key={activity.id} className="activity-item">
                <div className="activity-icon">
                  {getStatusIcon(activity.status)}
                </div>
                <div className="activity-details">
                  <div className="activity-type">
                    {activity.type} {activity.amount}
                  </div>
                  <div className="activity-pool">{activity.pool}</div>
                </div>
                <div className="activity-status">
                  <span 
                    className="status-badge"
                    style={{ backgroundColor: getStatusColor(activity.status) }}
                  >
                    {activity.status}
                  </span>
                </div>
                <div className="activity-time">{activity.timestamp}</div>
              </div>
            ))
          ) : (
            <div className="no-activity">
              <p>No recent activity</p>
              <p className="subtitle">Submit an order to see activity here</p>
            </div>
          )}
        </div>
      </div>

      {/* Vault Health */}
      <div className="health-section">
        <h3>Vault Health</h3>
        <div className="health-indicators">
          <div className="health-indicator">
            <span className="health-dot healthy"></span>
            <span>Operators Active</span>
          </div>
          <div className="health-indicator">
            <span className="health-dot healthy"></span>
            <span>Matching Engine</span>
          </div>
          <div className="health-indicator">
            <span className="health-dot healthy"></span>
            <span>ZK Proof System</span>
          </div>
          <div className="health-indicator">
            <span className="health-dot healthy"></span>
            <span>EigenLayer Connection</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VaultStatus; 