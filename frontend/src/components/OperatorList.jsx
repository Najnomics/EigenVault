import React, { useState, useEffect } from 'react';
import './OperatorList.css';

const OperatorList = () => {
  const [operators, setOperators] = useState([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // Simulate loading operators data
    const loadOperators = async () => {
      setIsLoading(true);
      
      // Mock data - in production this would come from the smart contract
      const mockOperators = [
        {
          id: 'op_001',
          address: '0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6',
          name: 'EigenVault Operator Alpha',
          status: 'active',
          stake: '32.0',
          uptime: '99.8%',
          tasksCompleted: 1247,
          totalRewards: '2.45',
          lastActive: '2 minutes ago',
          performance: 'excellent'
        },
        {
          id: 'op_002',
          address: '0x8ba1f109551bD432803012645Hac136c772c3c2c',
          name: 'EigenVault Operator Beta',
          status: 'active',
          stake: '32.0',
          uptime: '99.2%',
          tasksCompleted: 892,
          totalRewards: '1.87',
          lastActive: '5 minutes ago',
          performance: 'good'
        },
        {
          id: 'op_003',
          address: '0x1234567890123456789012345678901234567890',
          name: 'EigenVault Operator Gamma',
          status: 'active',
          stake: '32.0',
          uptime: '98.7%',
          tasksCompleted: 567,
          totalRewards: '1.23',
          lastActive: '1 minute ago',
          performance: 'good'
        },
        {
          id: 'op_004',
          address: '0xabcdef1234567890abcdef1234567890abcdef12',
          name: 'EigenVault Operator Delta',
          status: 'maintenance',
          stake: '32.0',
          uptime: '97.3%',
          tasksCompleted: 234,
          totalRewards: '0.89',
          lastActive: '15 minutes ago',
          performance: 'fair'
        }
      ];
      
      // Simulate API delay
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      setOperators(mockOperators);
      setIsLoading(false);
    };

    loadOperators();
  }, []);

  const getStatusColor = (status) => {
    switch (status) {
      case 'active': return '#10b981';
      case 'maintenance': return '#f59e0b';
      case 'inactive': return '#ef4444';
      default: return '#6b7280';
    }
  };

  const getPerformanceColor = (performance) => {
    switch (performance) {
      case 'excellent': return '#10b981';
      case 'good': return '#3b82f6';
      case 'fair': return '#f59e0b';
      case 'poor': return '#ef4444';
      default: return '#6b7280';
    }
  };

  const getPerformanceIcon = (performance) => {
    switch (performance) {
      case 'excellent': return '⭐';
      case 'good': return '✅';
      case 'fair': return '⚠️';
      case 'poor': return '❌';
      default: return '❓';
    }
  };

  const formatAddress = (address) => {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  if (isLoading) {
    return (
      <div className="operator-list-container">
        <h2>AVS Operators</h2>
        <div className="loading-state">
          <div className="loading-spinner"></div>
          <p>Loading operators...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="operator-list-container">
      <h2>AVS Operators</h2>
      <p className="operator-description">
        Active operators securing the EigenVault network through EigenLayer restaking
      </p>
      
      <div className="operator-stats">
        <div className="stat-item">
          <span className="stat-number">{operators.length}</span>
          <span className="stat-label">Total Operators</span>
        </div>
        <div className="stat-item">
          <span className="stat-number">{operators.filter(op => op.status === 'active').length}</span>
          <span className="stat-label">Active</span>
        </div>
        <div className="stat-item">
          <span className="stat-number">{operators.reduce((sum, op) => sum + parseFloat(op.stake), 0).toFixed(1)}</span>
          <span className="stat-label">Total Stake (ETH)</span>
        </div>
      </div>

      <div className="operators-grid">
        {operators.map((operator) => (
          <div key={operator.id} className="operator-card">
            <div className="operator-header">
              <div className="operator-info">
                <h3 className="operator-name">{operator.name}</h3>
                <p className="operator-address">{formatAddress(operator.address)}</p>
              </div>
              <div className="operator-status">
                <span 
                  className="status-badge"
                  style={{ backgroundColor: getStatusColor(operator.status) }}
                >
                  {operator.status}
                </span>
              </div>
            </div>

            <div className="operator-metrics">
              <div className="metric-row">
                <span className="metric-label">Stake:</span>
                <span className="metric-value">{operator.stake} ETH</span>
              </div>
              <div className="metric-row">
                <span className="metric-label">Uptime:</span>
                <span className="metric-value">{operator.uptime}</span>
              </div>
              <div className="metric-row">
                <span className="metric-label">Tasks Completed:</span>
                <span className="metric-value">{operator.tasksCompleted.toLocaleString()}</span>
              </div>
              <div className="metric-row">
                <span className="metric-label">Total Rewards:</span>
                <span className="metric-value">{operator.totalRewards} ETH</span>
              </div>
              <div className="metric-row">
                <span className="metric-label">Last Active:</span>
                <span className="metric-value">{operator.lastActive}</span>
              </div>
            </div>

            <div className="operator-performance">
              <div className="performance-indicator">
                <span className="performance-icon">
                  {getPerformanceIcon(operator.performance)}
                </span>
                <span 
                  className="performance-badge"
                  style={{ backgroundColor: getPerformanceColor(operator.performance) }}
                >
                  {operator.performance}
                </span>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="network-info">
        <h3>Network Information</h3>
        <div className="info-grid">
          <div className="info-item">
            <span className="info-label">Minimum Stake:</span>
            <span className="info-value">32 ETH</span>
          </div>
          <div className="info-item">
            <span className="info-label">Slashing Conditions:</span>
            <span className="info-value">Active</span>
          </div>
          <div className="info-item">
            <span className="info-label">Quorum Size:</span>
            <span className="info-value">2/3</span>
          </div>
          <div className="info-item">
            <span className="info-label">Reward Rate:</span>
            <span className="info-value">0.5% APY</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OperatorList; 