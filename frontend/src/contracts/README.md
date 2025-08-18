# Contract ABIs

This directory contains the ABI files for EigenVault smart contracts.

## Files Required

Place the following ABI files in this directory after deployment:

- `EigenVaultHook.json` - Main hook contract ABI
- `OrderVault.json` - Order vault contract ABI  
- `EigenVaultServiceManager.json` - Service manager contract ABI

## Generating ABIs

After compiling contracts with Foundry:

```bash
cd eigenvault/contracts
forge build

# Copy ABIs to frontend
cp out/EigenVaultHook.sol/EigenVaultHook.json ../../frontend/src/contracts/
cp out/OrderVault.sol/OrderVault.json ../../frontend/src/contracts/
cp out/EigenVaultServiceManager.sol/EigenVaultServiceManager.json ../../frontend/src/contracts/
```

## Environment Variables

Update your `.env` file with deployed contract addresses:

```
REACT_APP_EIGENVAULT_HOOK=0x...
REACT_APP_ORDER_VAULT=0x...
REACT_APP_SERVICE_MANAGER=0x...
REACT_APP_POOL_MANAGER=0x...
```