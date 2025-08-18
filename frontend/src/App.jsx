import React, { useState, useEffect } from "react";
import OrderForm from "./components/OrderForm.jsx";
import VaultStatus from "./components/VaultStatus";
import OperatorList from "./components/OperatorList";
import "./App.css";

const Home = () => {
  const [orders, setOrders] = useState([]);
  const [isConnected] = useState(false); // Simplified for compilation
  const [error] = useState(null);
  const [isLoading] = useState(false);

  const handleOrderSubmit = async (order) => {
    try {
      console.log('Submitting order:', order);
      
      // Add order to local state for demo
      setOrders(prev => [...prev, { 
        ...order, 
        id: Date.now().toString(),
        timestamp: Date.now(),
        status: 'pending'
      }]);
      
      return true;
    } catch (error) {
      console.error('Failed to submit order:', error);
      throw error;
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <div className="header-content">
          <h1>🔐 EigenVault</h1>
          <p>Privacy-preserving trading infrastructure on EigenLayer</p>
          
          <div className="connection-status">
            {!isConnected ? (
              <button className="connect-wallet-btn">
                Connect Wallet
              </button>
            ) : (
              <div className="wallet-info">
                <span>✅ Connected</span>
              </div>
            )}
          </div>
        </div>
      </header>
      
      <main className="App-main">
        {error && (
          <div className="error-banner">
            ⚠️ Error: {error}
          </div>
        )}
        
        <div className="container">
          <div className="content-grid">
            <div className="order-section">
              <OrderForm 
                onOrderSubmit={handleOrderSubmit}
                isConnected={isConnected}
                isLoading={isLoading}
              />
            </div>
            
            <div className="status-section">
              <VaultStatus orders={orders} />
            </div>
          </div>
          
          <div className="operators-section">
            <OperatorList />
          </div>
        </div>
      </main>
    </div>
  );
};

function App() {
  return <Home />;
}

export default App; 