# EigenVault Deployment Documentation

## Overview

This document provides comprehensive deployment instructions for the EigenVault smart contract system across different networks and environments.

## Deployment Environments

### 1. Local Development (Anvil)

#### Prerequisites
- Foundry installed and configured
- Anvil running on localhost:8545

#### Quick Start
```bash
# Start Anvil
anvil --host 0.0.0.0 --port 8545 --accounts 10 --balance 10000

# Deploy contracts
forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy full hook system
forge script script/DeployWithProperHook.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Configuration
- **Chain ID**: 31337
- **RPC URL**: http://localhost:8545
- **Accounts**: 10 pre-funded accounts with 10,000 ETH each
- **Block Time**: 2 seconds

#### Post-Deployment
- Contract addresses saved to `anvil-deployments.env`
- Basic functionality tests can be run
- Frontend can connect to local contracts

### 2. Testnet Deployment (Holesky)

#### Prerequisites
- Holesky ETH for gas fees
- Etherscan API key for verification
- Environment variables configured

#### Environment Setup
```bash
# Required environment variables
HOLESKY_RPC_URL=https://holesky.infura.io/v3/YOUR_KEY
HOLESKY_ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
DEPLOYER_PRIVATE_KEY=0x...
```

#### Deployment Process
```bash
# Deploy contracts
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $HOLESKY_RPC_URL

# Verify contracts
forge verify-contract --chain-id 17000 --num-of-optimizations 200 --watch --etherscan-api-key $HOLESKY_ETHERSCAN_API_KEY $CONTRACT_ADDRESS src/hooks/EigenVaultHook.sol:EigenVaultHook
```

#### Network Details
- **Chain ID**: 17000
- **Block Explorer**: https://holesky.etherscan.io
- **RPC Endpoints**: Infura, Alchemy, public RPCs

### 3. Production Deployment (Mainnet)

#### Prerequisites
- Sufficient ETH for deployment and gas
- Etherscan API key
- Comprehensive testing completed
- Security audit completed

#### Pre-Deployment Checklist
- [ ] All tests passing
- [ ] Security audit completed
- [ ] Gas optimization verified
- [ ] Deployment scripts tested on testnet
- [ ] Emergency procedures documented
- [ ] Monitoring configured

#### Deployment Process
```bash
# Final testnet validation
forge test --fork-url $MAINNET_RPC_URL --gas-report

# Deploy to mainnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $MAINNET_RPC_URL

# Verify contracts
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --etherscan-api-key $ETHERSCAN_API_KEY $CONTRACT_ADDRESS src/hooks/EigenVaultHook.sol:EigenVaultHook
```

#### Network Details
- **Chain ID**: 1
- **Block Explorer**: https://etherscan.io
- **Gas Strategy**: Optimized for mainnet conditions

## Deployment Scripts

### Available Scripts

#### 1. DeployOrderVaultOnly.s.sol
- **Purpose**: Deploy core OrderVault contract and test tokens
- **Components**: OrderVault, MockERC20 tokens, MockPoolManager
- **Use Case**: Basic functionality testing

#### 2. DeployWithProperHook.s.sol
- **Purpose**: Deploy complete hook system with proper Uniswap v4 flags
- **Components**: EigenVaultHook, OrderVault, EigenVaultAVSServiceManager, test tokens
- **Use Case**: Full system deployment

### Script Usage

#### Local Deployment
```bash
# OrderVault only
forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast

# Full hook system
forge script script/DeployWithProperHook.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Testnet Deployment
```bash
# Deploy with verification
forge script script/DeployOrderVaultOnly.s.sol --broadcast --verify --rpc-url $HOLESKY_RPC_URL
```

#### Mainnet Deployment
```bash
# Production deployment
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $MAINNET_RPC_URL
```

## Contract Addresses

### Address Management

#### Local Development
- **File**: `anvil-deployments.env`
- **Auto-generated**: Yes, during deployment
- **Format**: Environment variables

#### Testnet/Mainnet
- **File**: Manual tracking or deployment scripts
- **Verification**: Etherscan verification required
- **Documentation**: Update deployment documentation

### Address Format
```bash
# Environment file format
NETWORK=anvil
CHAIN_ID=31337
RPC_URL=http://localhost:8545
ORDER_VAULT_ADDRESS=0x...
EIGENVAULT_HOOK_ADDRESS=0x...
AVS_SERVICE_MANAGER_ADDRESS=0x...
```

## Gas Optimization

### Deployment Gas Usage
- **OrderVault**: ~2.8M gas
- **EigenVaultHook**: ~3.2M gas (with flags)
- **EigenVaultAVSServiceManager**: ~4.1M gas
- **Total**: ~10.1M gas

### Optimization Strategies
- **Compiler Optimization**: 200 runs recommended
- **Constructor Optimization**: Minimize constructor logic
- **Libraries**: Use libraries for common functionality
- **Packing**: Optimize storage layout

### Gas Price Strategy
- **Testnet**: Use low gas prices for cost efficiency
- **Mainnet**: Use competitive gas prices for timely deployment
- **Monitoring**: Monitor gas prices during deployment

## Verification Process

### Etherscan Verification

#### Automatic Verification
```bash
# Deploy with automatic verification
forge script script/DeployOrderVaultOnly.s.sol --broadcast --verify --rpc-url $RPC_URL
```

#### Manual Verification
```bash
# Verify specific contract
forge verify-contract \
  --chain-id $CHAIN_ID \
  --num-of-optimizations 200 \
  --watch \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  $CONTRACT_ADDRESS \
  src/hooks/EigenVaultHook.sol:EigenVaultHook
```

### Verification Requirements
- **Compiler Version**: Must match deployment
- **Optimization Runs**: Must match deployment
- **Constructor Arguments**: Must be provided
- **Source Code**: Must be available

## Post-Deployment

### Verification Steps

#### 1. Contract Verification
- Verify contracts on Etherscan
- Check constructor parameters
- Verify bytecode matches source

#### 2. Functionality Testing
```bash
# Run basic functionality tests
forge test --fork-url $RPC_URL --match-test "test_001_hookPermissions"

# Run integration tests
forge test --fork-url $RPC_URL --match-path "test/integration/*"
```

#### 3. Integration Testing
- Test frontend connection
- Test operator integration
- Test AVS registration

### Monitoring Setup

#### Contract Monitoring
- **Event Monitoring**: Set up event listeners
- **State Monitoring**: Monitor contract state changes
- **Error Monitoring**: Monitor for errors and failures

#### Performance Monitoring
- **Gas Usage**: Monitor gas consumption
- **Transaction Volume**: Monitor transaction patterns
- **Error Rates**: Monitor error frequencies

## Troubleshooting

### Common Issues

#### Deployment Failures
```bash
# Check gas limits
forge script script/DeployOrderVaultOnly.s.sol --rpc-url $RPC_URL --gas-limit 15000000

# Check RPC connectivity
curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL

# Verify private key
cast wallet address $DEPLOYER_PRIVATE_KEY
```

#### Verification Failures
```bash
# Check compiler version
forge --version

# Verify optimization settings
forge build --sizes

# Check constructor arguments
cast call $CONTRACT_ADDRESS "totalOrders()" --rpc-url $RPC_URL
```

#### Contract Issues
```bash
# Check contract state
cast call $CONTRACT_ADDRESS "totalOrders()" --rpc-url $RPC_URL

# Verify contract code
cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL

# Check transaction status
cast tx $TX_HASH --rpc-url $RPC_URL
```

### Debug Commands

#### Transaction Analysis
```bash
# Get transaction details
cast tx $TX_HASH --rpc-url $RPC_URL

# Get transaction receipt
cast receipt $TX_HASH --rpc-url $RPC_URL

# Trace transaction execution
cast run $TX_HASH --rpc-url $RPC_URL --trace
```

#### Contract Interaction
```bash
# Call view functions
cast call $CONTRACT_ADDRESS "functionName()" --rpc-url $RPC_URL

# Send transactions
cast send $CONTRACT_ADDRESS "functionName()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Get storage values
cast storage $CONTRACT_ADDRESS $SLOT --rpc-url $RPC_URL
```

## Security Considerations

### Private Key Management
- **Secure Storage**: Use secure key management systems
- **Access Control**: Limit access to deployment keys
- **Key Rotation**: Regular key rotation procedures
- **Backup**: Secure backup of critical keys

### Deployment Security
- **Verification**: Always verify contracts after deployment
- **Testing**: Comprehensive testing before mainnet deployment
- **Monitoring**: Continuous monitoring after deployment
- **Emergency Procedures**: Documented emergency procedures

### Network Security
- **RPC Security**: Use trusted RPC endpoints
- **Network Monitoring**: Monitor network conditions
- **Gas Price Monitoring**: Monitor gas price fluctuations
- **Transaction Monitoring**: Monitor deployment transactions

## Best Practices

### Pre-Deployment
1. **Testing**: Comprehensive testing on testnet
2. **Gas Estimation**: Accurate gas estimation
3. **Verification**: Prepare verification parameters
4. **Documentation**: Update deployment documentation

### During Deployment
1. **Monitoring**: Monitor deployment progress
2. **Gas Management**: Manage gas prices effectively
3. **Error Handling**: Handle deployment errors gracefully
4. **Rollback Plan**: Have rollback procedures ready

### Post-Deployment
1. **Verification**: Verify all contracts
2. **Testing**: Run post-deployment tests
3. **Documentation**: Update address documentation
4. **Monitoring**: Set up monitoring systems

## Automation

### CI/CD Integration
- **Automated Testing**: Run tests on every deployment
- **Automated Verification**: Automatic contract verification
- **Automated Monitoring**: Set up monitoring alerts
- **Automated Documentation**: Update deployment docs

### Deployment Scripts
- **Environment Detection**: Automatic environment detection
- **Parameter Validation**: Validate deployment parameters
- **Error Handling**: Comprehensive error handling
- **Logging**: Detailed deployment logging

## Support Resources

### Documentation
- **Foundry Book**: https://book.getfoundry.sh/
- **Etherscan API**: https://docs.etherscan.io/
- **EigenLayer Docs**: https://docs.eigenlayer.xyz/

### Community
- **Discord**: EigenVault Discord server
- **GitHub**: Issue tracking and discussions
- **Stack Overflow**: Technical questions

### Emergency Contacts
- **Security Issues**: security@eigenvault.com
- **Technical Support**: support@eigenvault.com
- **Emergency Response**: emergency@eigenvault.com
