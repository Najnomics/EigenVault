import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import './OrderForm.css';

const OrderForm = ({ onOrderSubmit }) => {
  const [formData, setFormData] = useState({
    poolKey: '',
    zeroForOne: true,
    amountSpecified: '',
    price: '',
    deadline: '',
    commitment: '',
    encryptedOrder: ''
  });

  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // Mock pool options for demonstration
  const poolOptions = [
    { value: 'ETH_USDC_3000', label: 'ETH/USDC - 0.05% Fee' },
    { value: 'ETH_USDT_3000', label: 'ETH/USDT - 0.05% Fee' },
    { value: 'USDC_USDT_100', label: 'USDC/USDT - 0.01% Fee' },
    { value: 'WBTC_ETH_3000', label: 'WBTC/ETH - 0.05% Fee' }
  ];

  useEffect(() => {
    // Set default deadline to 1 hour from now
    const defaultDeadline = new Date(Date.now() + 60 * 60 * 1000);
    setFormData(prev => ({
      ...prev,
      deadline: defaultDeadline.toISOString().slice(0, 16)
    }));
  }, []);

  const handleInputChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }));
  };

  const generateCommitment = () => {
    try {
      const commitmentData = {
        poolKey: formData.poolKey,
        zeroForOne: formData.zeroForOne,
        amountSpecified: formData.amountSpecified,
        price: formData.price,
        deadline: new Date(formData.deadline).getTime(),
        nonce: Date.now()
      };
      
      const commitment = ethers.utils.keccak256(
        ethers.utils.toUtf8Bytes(JSON.stringify(commitmentData))
      );
      
      setFormData(prev => ({ ...prev, commitment }));
      setSuccess('Commitment generated successfully!');
      setError('');
    } catch (err) {
      setError('Failed to generate commitment: ' + err.message);
      setSuccess('');
    }
  };

  const encryptOrder = () => {
    try {
      // Mock encryption - in production this would use actual encryption
      const orderData = {
        poolKey: formData.poolKey,
        zeroForOne: formData.zeroForOne,
        amountSpecified: formData.amountSpecified,
        price: formData.price,
        deadline: new Date(formData.deadline).getTime(),
        timestamp: Date.now()
      };
      
      // Simulate encryption by encoding and hashing
      const encryptedOrder = ethers.utils.base64.encode(
        ethers.utils.toUtf8Bytes(JSON.stringify(orderData))
      );
      
      setFormData(prev => ({ ...prev, encryptedOrder }));
      setSuccess('Order encrypted successfully!');
      setError('');
    } catch (err) {
      setError('Failed to encrypt order: ' + err.message);
      setSuccess('');
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsLoading(true);
    setError('');
    setSuccess('');

    try {
      // Validate form data
      if (!formData.poolKey || !formData.amountSpecified || !formData.price || !formData.deadline) {
        throw new Error('Please fill in all required fields');
      }

      if (!formData.commitment) {
        throw new Error('Please generate a commitment first');
      }

      if (!formData.encryptedOrder) {
        throw new Error('Please encrypt the order first');
      }

      // Create order object
      const order = {
        ...formData,
        id: ethers.utils.id(Date.now().toString()),
        timestamp: Date.now(),
        status: 'pending'
      };

      // Call parent callback
      if (onOrderSubmit) {
        await onOrderSubmit(order);
      }

      setSuccess('Order submitted successfully!');
      
      // Reset form
      setFormData({
        poolKey: '',
        zeroForOne: true,
        amountSpecified: '',
        price: '',
        deadline: '',
        commitment: '',
        encryptedOrder: ''
      });

    } catch (err) {
      setError('Failed to submit order: ' + err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const isFormValid = () => {
    return formData.poolKey && 
           formData.amountSpecified && 
           formData.price && 
           formData.deadline &&
           formData.commitment &&
           formData.encryptedOrder;
  };

  return (
    <div className="order-form-container">
      <h2>Submit Large Order to EigenVault</h2>
      <p className="form-description">
        Submit large orders for private matching through the EigenVault system. 
        Orders are encrypted and routed through the vault for optimal execution.
      </p>

      <form onSubmit={handleSubmit} className="order-form">
        <div className="form-group">
          <label htmlFor="poolKey">Pool *</label>
          <select
            id="poolKey"
            name="poolKey"
            value={formData.poolKey}
            onChange={handleInputChange}
            required
            className="form-select"
          >
            <option value="">Select a pool</option>
            {poolOptions.map(pool => (
              <option key={pool.value} value={pool.value}>
                {pool.label}
              </option>
            ))}
          </select>
        </div>

        <div className="form-group">
          <label htmlFor="zeroForOne">Order Type *</label>
          <div className="radio-group">
            <label className="radio-label">
              <input
                type="radio"
                name="zeroForOne"
                value={true}
                checked={formData.zeroForOne === true}
                onChange={handleInputChange}
              />
              Buy (Zero for One)
            </label>
            <label className="radio-label">
              <input
                type="radio"
                name="zeroForOne"
                value={false}
                checked={formData.zeroForOne === false}
                onChange={handleInputChange}
              />
              Sell (One for Zero)
            </label>
          </div>
        </div>

        <div className="form-group">
          <label htmlFor="amountSpecified">Amount *</label>
          <input
            type="number"
            id="amountSpecified"
            name="amountSpecified"
            value={formData.amountSpecified}
            onChange={handleInputChange}
            placeholder="Enter amount"
            required
            min="0"
            step="0.000001"
            className="form-input"
          />
        </div>

        <div className="form-group">
          <label htmlFor="price">Price *</label>
          <input
            type="number"
            id="price"
            name="price"
            value={formData.price}
            onChange={handleInputChange}
            placeholder="Enter price"
            required
            min="0"
            step="0.000001"
            className="form-input"
          />
        </div>

        <div className="form-group">
          <label htmlFor="deadline">Deadline *</label>
          <input
            type="datetime-local"
            id="deadline"
            name="deadline"
            value={formData.deadline}
            onChange={handleInputChange}
            required
            className="form-input"
          />
        </div>

        <div className="form-group">
          <label>Commitment</label>
          <div className="commitment-section">
            <button
              type="button"
              onClick={generateCommitment}
              className="btn btn-secondary"
              disabled={!formData.poolKey || !formData.amountSpecified || !formData.price}
            >
              Generate Commitment
            </button>
            {formData.commitment && (
              <div className="commitment-display">
                <span className="label">Commitment Hash:</span>
                <code className="hash-value">{formData.commitment}</code>
              </div>
            )}
          </div>
        </div>

        <div className="form-group">
          <label>Order Encryption</label>
          <div className="encryption-section">
            <button
              type="button"
              onClick={encryptOrder}
              className="btn btn-secondary"
              disabled={!formData.commitment}
            >
              Encrypt Order
            </button>
            {formData.encryptedOrder && (
              <div className="encrypted-order-display">
                <span className="label">Encrypted Order:</span>
                <code className="encrypted-value">{formData.encryptedOrder.substring(0, 50)}...</code>
              </div>
            )}
          </div>
        </div>

        {error && <div className="error-message">{error}</div>}
        {success && <div className="success-message">{success}</div>}

        <button
          type="submit"
          className="btn btn-primary submit-btn"
          disabled={!isFormValid() || isLoading}
        >
          {isLoading ? 'Submitting...' : 'Submit Order to Vault'}
        </button>
      </form>
    </div>
  );
};

export default OrderForm; 