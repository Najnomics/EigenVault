import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';
import { useWeb3 } from './useWeb3';

// Import contract ABIs
import EigenVaultHookABI from '../contracts/EigenVaultHook.json';
import OrderVaultABI from '../contracts/OrderVault.json';
import ServiceManagerABI from '../contracts/EigenVaultServiceManager.json';

// Contract addresses from environment
const CONTRACT_ADDRESSES = {
  eigenVaultHook: process.env.REACT_APP_EIGENVAULT_HOOK || '',
  orderVault: process.env.REACT_APP_ORDER_VAULT || '',
  serviceManager: process.env.REACT_APP_SERVICE_MANAGER || '',
  poolManager: process.env.REACT_APP_POOL_MANAGER || '',
};

export interface Order {
  id: string;
  trader: string;
  poolKey: {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
  };
  zeroForOne: boolean;
  amountSpecified: string;
  commitment: string;
  deadline: number;
  timestamp: number;
  executed: boolean;
}

export interface OrderSubmission {
  poolKey: {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
  };
  zeroForOne: boolean;
  amountSpecified: string;
  price: string;
  deadline: number;
}

export interface OperatorInfo {
  address: string;
  isActive: boolean;
  tasksCompleted: number;
  totalRewards: string;
  successRate: number;
  averageResponseTime: number;
}

export const useEigenVault = () => {
  const { provider, signer, account, chainId } = useWeb3();
  const [contracts, setContracts] = useState<{
    hook?: ethers.Contract;
    orderVault?: ethers.Contract;
    serviceManager?: ethers.Contract;
  }>({});
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize contracts when provider is available
  useEffect(() => {
    if (provider && signer) {
      initializeContracts();
    }
  }, [provider, signer]);

  const initializeContracts = useCallback(async () => {
    try {
      if (!signer) return;

      const hookContract = new ethers.Contract(
        CONTRACT_ADDRESSES.eigenVaultHook,
        EigenVaultHookABI.abi,
        signer
      );

      const orderVaultContract = new ethers.Contract(
        CONTRACT_ADDRESSES.orderVault,
        OrderVaultABI.abi,
        signer
      );

      const serviceManagerContract = new ethers.Contract(
        CONTRACT_ADDRESSES.serviceManager,
        ServiceManagerABI.abi,
        signer
      );

      setContracts({
        hook: hookContract,
        orderVault: orderVaultContract,
        serviceManager: serviceManagerContract,
      });
    } catch (error) {
      console.error('Failed to initialize contracts:', error);
      setError('Failed to initialize contracts');
    }
  }, [signer]);

  // Submit a large order to EigenVault
  const submitOrder = useCallback(async (orderData: OrderSubmission): Promise<string> => {
    if (!contracts.hook || !account) {
      throw new Error('Contracts not initialized or wallet not connected');
    }

    setIsLoading(true);
    setError(null);

    try {
      // Generate commitment hash
      const commitment = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ['address', 'uint256', 'uint256', 'uint256', 'uint256'],
          [
            account,
            orderData.amountSpecified,
            orderData.price,
            orderData.deadline,
            Date.now(), // nonce
          ]
        )
      );

      // Encrypt order data (client-side encryption)
      const encryptedOrder = await encryptOrderData(orderData);

      // Encode hook data
      const hookData = ethers.utils.defaultAbiCoder.encode(
        ['bytes32', 'uint256', 'bytes'],
        [commitment, orderData.deadline, encryptedOrder]
      );

      // Create pool key
      const poolKey = {
        currency0: orderData.poolKey.currency0,
        currency1: orderData.poolKey.currency1,
        fee: orderData.poolKey.fee,
        tickSpacing: orderData.poolKey.tickSpacing,
        hooks: CONTRACT_ADDRESSES.eigenVaultHook,
      };

      // Create swap params
      const swapParams = {
        zeroForOne: orderData.zeroForOne,
        amountSpecified: ethers.utils.parseEther(orderData.amountSpecified),
        sqrtPriceLimitX96: 0,
      };

      // Submit order to vault
      const tx = await contracts.hook.routeToVault(
        account,
        poolKey,
        swapParams,
        hookData,
        {
          gasLimit: 500000, // Reasonable gas limit
        }
      );

      const receipt = await tx.wait();
      
      // Extract order ID from events
      const orderRoutedEvent = receipt.events?.find(
        (event: any) => event.event === 'OrderRoutedToVault'
      );

      const orderId = orderRoutedEvent?.args?.orderId || tx.hash;
      
      return orderId;
    } catch (error: any) {
      console.error('Failed to submit order:', error);
      const errorMessage = error.reason || error.message || 'Failed to submit order';
      setError(errorMessage);
      throw new Error(errorMessage);
    } finally {
      setIsLoading(false);
    }
  }, [contracts.hook, account]);

  // Get order details
  const getOrder = useCallback(async (orderId: string): Promise<Order | null> => {
    if (!contracts.hook) return null;

    try {
      const orderData = await contracts.hook.getOrder(orderId);
      
      return {
        id: orderId,
        trader: orderData.trader,
        poolKey: orderData.poolKey,
        zeroForOne: orderData.zeroForOne,
        amountSpecified: ethers.utils.formatEther(orderData.amountSpecified),
        commitment: orderData.commitment,
        deadline: orderData.deadline.toNumber(),
        timestamp: orderData.timestamp.toNumber(),
        executed: orderData.executed,
      };
    } catch (error) {
      console.error('Failed to get order:', error);
      return null;
    }
  }, [contracts.hook]);

  // Check if order amount qualifies as large order
  const isLargeOrder = useCallback(async (
    amount: string,
    poolKey: OrderSubmission['poolKey']
  ): Promise<boolean> => {
    if (!contracts.hook) return false;

    try {
      const amountWei = ethers.utils.parseEther(amount);
      const fullPoolKey = {
        ...poolKey,
        hooks: CONTRACT_ADDRESSES.eigenVaultHook,
      };
      
      return await contracts.hook.isLargeOrder(amountWei, fullPoolKey);
    } catch (error) {
      console.error('Failed to check order size:', error);
      return false;
    }
  }, [contracts.hook]);

  // Get vault threshold for a pool
  const getVaultThreshold = useCallback(async (
    poolKey: OrderSubmission['poolKey']
  ): Promise<number> => {
    if (!contracts.hook) return 0;

    try {
      const fullPoolKey = {
        ...poolKey,
        hooks: CONTRACT_ADDRESSES.eigenVaultHook,
      };
      
      const threshold = await contracts.hook.getVaultThreshold(fullPoolKey);
      return threshold.toNumber();
    } catch (error) {
      console.error('Failed to get vault threshold:', error);
      return 0;
    }
  }, [contracts.hook]);

  // Get active operators
  const getActiveOperators = useCallback(async (): Promise<OperatorInfo[]> => {
    if (!contracts.serviceManager) return [];

    try {
      const operatorAddresses = await contracts.serviceManager.getActiveOperators();
      
      const operators = await Promise.all(
        operatorAddresses.map(async (address: string) => {
          const metrics = await contracts.serviceManager!.getOperatorMetrics(address);
          
          return {
            address,
            isActive: metrics.isActive,
            tasksCompleted: metrics.tasksCompleted.toNumber(),
            totalRewards: ethers.utils.formatEther(metrics.totalRewards),
            successRate: metrics.successRate.toNumber() / 100, // Convert from basis points
            averageResponseTime: metrics.averageResponseTime.toNumber(),
          };
        })
      );

      return operators;
    } catch (error) {
      console.error('Failed to get active operators:', error);
      return [];
    }
  }, [contracts.serviceManager]);

  // Get vault statistics
  const getVaultStats = useCallback(async () => {
    if (!contracts.orderVault) return null;

    try {
      const stats = await contracts.orderVault.getVaultStats();
      
      return {
        totalStored: stats.totalStored.toNumber(),
        totalRetrieved: stats.totalRetrieved.toNumber(),
        totalExpired: stats.totalExpired.toNumber(),
        currentlyActive: stats.currentlyActive.toNumber(),
      };
    } catch (error) {
      console.error('Failed to get vault stats:', error);
      return null;
    }
  }, [contracts.orderVault]);

  // Listen for order events
  const subscribeToOrderEvents = useCallback((callback: (event: any) => void) => {
    if (!contracts.hook) return () => {};

    const eventFilter = contracts.hook.filters.OrderRoutedToVault();
    contracts.hook.on(eventFilter, callback);

    return () => {
      contracts.hook?.off(eventFilter, callback);
    };
  }, [contracts.hook]);

  // Execute order fallback to AMM
  const fallbackToAMM = useCallback(async (orderId: string): Promise<void> => {
    if (!contracts.hook) throw new Error('Hook contract not initialized');

    setIsLoading(true);
    setError(null);

    try {
      const tx = await contracts.hook.fallbackToAMM(orderId, {
        gasLimit: 200000,
      });

      await tx.wait();
    } catch (error: any) {
      console.error('Failed to fallback order:', error);
      const errorMessage = error.reason || error.message || 'Failed to fallback order';
      setError(errorMessage);
      throw new Error(errorMessage);
    } finally {
      setIsLoading(false);
    }
  }, [contracts.hook]);

  return {
    // State
    isLoading,
    error,
    contracts,
    
    // Contract interaction functions
    submitOrder,
    getOrder,
    isLargeOrder,
    getVaultThreshold,
    getActiveOperators,
    getVaultStats,
    subscribeToOrderEvents,
    fallbackToAMM,
    
    // Utility functions
    isConnected: !!account,
    currentAccount: account,
    networkId: chainId,
  };
};

// Helper function for client-side order encryption
async function encryptOrderData(orderData: OrderSubmission): Promise<Uint8Array> {
  // In production, this would use proper encryption with operator public keys
  // For now, return encoded order data
  const encoder = new TextEncoder();
  return encoder.encode(JSON.stringify(orderData));
}

export default useEigenVault;