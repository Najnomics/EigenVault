import { useState, useEffect, useCallback } from 'react';
import { ethers } from 'ethers';

declare global {
  interface Window {
    ethereum?: any;
  }
}

export interface Web3State {
  provider: ethers.providers.Web3Provider | null;
  signer: ethers.Signer | null;
  account: string | null;
  chainId: number | null;
  balance: string | null;
  isConnecting: boolean;
  error: string | null;
}

export const useWeb3 = () => {
  const [state, setState] = useState<Web3State>({
    provider: null,
    signer: null,
    account: null,
    chainId: null,
    balance: null,
    isConnecting: false,
    error: null,
  });

  // Supported networks
  const supportedNetworks = {
    1: 'Ethereum Mainnet',
    17000: 'Holesky Testnet',
    1301: 'Unichain Sepolia',
  };

  // Initialize provider on mount
  useEffect(() => {
    initializeProvider();
    
    // Listen for account and network changes
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', handleChainChanged);
      window.ethereum.on('disconnect', handleDisconnect);
    }

    return () => {
      if (window.ethereum) {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
        window.ethereum.removeListener('disconnect', handleDisconnect);
      }
    };
  }, []);

  const initializeProvider = useCallback(async () => {
    if (!window.ethereum) {
      setState(prev => ({ 
        ...prev, 
        error: 'MetaMask or compatible wallet not found' 
      }));
      return;
    }

    try {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const accounts = await provider.listAccounts();
      
      if (accounts.length > 0) {
        const signer = provider.getSigner();
        const account = accounts[0];
        const network = await provider.getNetwork();
        const balance = await provider.getBalance(account);

        setState(prev => ({
          ...prev,
          provider,
          signer,
          account,
          chainId: network.chainId,
          balance: ethers.utils.formatEther(balance),
          error: null,
        }));
      } else {
        setState(prev => ({
          ...prev,
          provider,
          signer: null,
          account: null,
          chainId: null,
          balance: null,
        }));
      }
    } catch (error: any) {
      console.error('Failed to initialize provider:', error);
      setState(prev => ({ 
        ...prev, 
        error: error.message || 'Failed to initialize Web3 provider' 
      }));
    }
  }, []);

  const connectWallet = useCallback(async () => {
    if (!window.ethereum) {
      setState(prev => ({ 
        ...prev, 
        error: 'MetaMask or compatible wallet not found' 
      }));
      return;
    }

    setState(prev => ({ ...prev, isConnecting: true, error: null }));

    try {
      // Request account access
      await window.ethereum.request({ method: 'eth_requestAccounts' });
      
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      const account = await signer.getAddress();
      const network = await provider.getNetwork();
      const balance = await provider.getBalance(account);

      setState(prev => ({
        ...prev,
        provider,
        signer,
        account,
        chainId: network.chainId,
        balance: ethers.utils.formatEther(balance),
        isConnecting: false,
        error: null,
      }));
    } catch (error: any) {
      console.error('Failed to connect wallet:', error);
      setState(prev => ({ 
        ...prev, 
        isConnecting: false,
        error: error.message || 'Failed to connect wallet' 
      }));
    }
  }, []);

  const disconnectWallet = useCallback(() => {
    setState(prev => ({
      ...prev,
      signer: null,
      account: null,
      chainId: null,
      balance: null,
      error: null,
    }));
  }, []);

  const switchNetwork = useCallback(async (chainId: number) => {
    if (!window.ethereum) return;

    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: `0x${chainId.toString(16)}` }],
      });
    } catch (error: any) {
      // If the network is not added to MetaMask
      if (error.code === 4902) {
        await addNetwork(chainId);
      } else {
        console.error('Failed to switch network:', error);
        setState(prev => ({ 
          ...prev, 
          error: `Failed to switch to network ${chainId}` 
        }));
      }
    }
  }, []);

  const addNetwork = async (chainId: number) => {
    if (!window.ethereum) return;

    const networkConfigs: { [key: number]: any } = {
      17000: {
        chainId: '0x4268',
        chainName: 'Holesky Testnet',
        nativeCurrency: {
          name: 'Ethereum',
          symbol: 'ETH',
          decimals: 18,
        },
        rpcUrls: ['https://ethereum-holesky-rpc.publicnode.com'],
        blockExplorerUrls: ['https://holesky.etherscan.io'],
      },
      1301: {
        chainId: '0x515',
        chainName: 'Unichain Sepolia',
        nativeCurrency: {
          name: 'Ethereum',
          symbol: 'ETH',
          decimals: 18,
        },
        rpcUrls: ['https://sepolia.unichain.org'],
        blockExplorerUrls: ['https://unichain-sepolia.blockscout.com'],
      },
    };

    const config = networkConfigs[chainId];
    if (!config) {
      setState(prev => ({ 
        ...prev, 
        error: `Network ${chainId} not supported` 
      }));
      return;
    }

    try {
      await window.ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [config],
      });
    } catch (error: any) {
      console.error('Failed to add network:', error);
      setState(prev => ({ 
        ...prev, 
        error: `Failed to add network ${chainId}` 
      }));
    }
  };

  const updateBalance = useCallback(async () => {
    if (!state.provider || !state.account) return;

    try {
      const balance = await state.provider.getBalance(state.account);
      setState(prev => ({
        ...prev,
        balance: ethers.utils.formatEther(balance),
      }));
    } catch (error) {
      console.error('Failed to update balance:', error);
    }
  }, [state.provider, state.account]);

  const handleAccountsChanged = useCallback((accounts: string[]) => {
    if (accounts.length === 0) {
      disconnectWallet();
    } else {
      // Reinitialize with new account
      initializeProvider();
    }
  }, [disconnectWallet, initializeProvider]);

  const handleChainChanged = useCallback((chainId: string) => {
    // Reload the page to reset state
    window.location.reload();
  }, []);

  const handleDisconnect = useCallback(() => {
    disconnectWallet();
  }, [disconnectWallet]);

  const isNetworkSupported = useCallback((chainId: number | null) => {
    return chainId !== null && chainId in supportedNetworks;
  }, []);

  const getNetworkName = useCallback((chainId: number | null) => {
    if (chainId === null) return 'Unknown';
    return supportedNetworks[chainId as keyof typeof supportedNetworks] || `Network ${chainId}`;
  }, []);

  return {
    // State
    ...state,
    isConnected: !!state.account,
    isNetworkSupported: isNetworkSupported(state.chainId),
    networkName: getNetworkName(state.chainId),
    
    // Actions
    connectWallet,
    disconnectWallet,
    switchNetwork,
    addNetwork,
    updateBalance,
    
    // Utilities
    supportedNetworks,
    formatAddress: (address: string) => 
      address ? `${address.slice(0, 6)}...${address.slice(-4)}` : '',
    formatBalance: (balance: string | null) => 
      balance ? parseFloat(balance).toFixed(4) : '0.0000',
  };
};

export default useWeb3;