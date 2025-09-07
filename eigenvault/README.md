# EigenVault - Private Order Routing with EigenLayer AVS

EigenVault is a production-ready protocol that combines EigenLayer's Actively Validated Services (AVS) with Uniswap v4 hooks to enable private, secure order routing with zero-knowledge proof verification.

## 🎯 Overview

EigenVault provides institutional-grade private order execution by routing large orders through a decentralized network of EigenLayer operators who perform private matching using zero-knowledge proofs, while smaller orders execute directly on Uniswap v4 AMM pools.

### Key Features

- **🔒 Private Order Matching**: Large orders are routed privately through EigenLayer operators
- **⚡ Smart Order Routing**: Automatic routing based on order size thresholds  
- **🛡️ ZK Proof Verification**: Zero-knowledge proofs ensure matching integrity
- **🏗️ EigenLayer Integration**: Leverages EigenLayer's security and operator network
- **🔄 Uniswap v4 Native**: Built as native Uniswap v4 hooks for seamless integration
- **🌐 Multi-Chain Ready**: Designed for cross-chain deployment and operation

## 🏗️ Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    EigenVault Protocol                      │
├─────────────────┬─────────────────┬─────────────────────────┤
│  Uniswap v4     │   EigenLayer    │    Zero-Knowledge       │
│     Hooks       │      AVS        │       Proofs            │
├─────────────────┼─────────────────┼─────────────────────────┤
│ • Order Routing │ • Operator Mgmt │ • Private Matching      │
│ • Threshold     │ • Task Creation │ • Proof Generation      │  
│   Detection     │ • Consensus     │ • Batch Verification    │
│ • Execution     │ • Slashing      │ • Privacy Preservation  │
└─────────────────┴─────────────────┴─────────────────────────┘
```

### Contract Structure

- **`EigenVaultHook.sol`** - Main Uniswap v4 hook for order routing
- **`EigenVaultAVS.sol`** - EigenLayer AVS contract for operator management  
- **`OrderVault.sol`** - Secure order storage with privacy preservation
- **`ZKProofLib.sol`** - Zero-knowledge proof generation and verification
- **`OrderLib.sol`** - Order data structures and utilities
- **`OrderMatchingLib.sol`** - Private order matching algorithms
- **`SecurityLib.sol`** - Security controls and risk management

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) - Ethereum development toolkit
- [Node.js](https://nodejs.org/) v18+ for scripts
- [Git](https://git-scm.com/) for version control

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/EigenVault.git
cd EigenVault/eigenvault

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Configuration

Copy the environment template:
```bash
cp .env.example .env
```

Edit `.env` with your configuration:
```env
# RPC URLs
MAINNET_RPC_URL="your_mainnet_rpc"
GOERLI_RPC_URL="your_goerli_rpc"

# Private keys (for deployment)
PRIVATE_KEY="your_private_key"

# Contract addresses (after deployment)
EIGENLAYER_CORE_ADDRESS=""
UNISWAP_V4_MANAGER_ADDRESS=""
```

## 🧪 Testing

EigenVault includes comprehensive testing with **343+ test functions** covering:

### Test Categories
- **Core Protocol Tests** (116 tests) - Basic functionality and integration
- **Security Tests** (31 tests) - Attack vectors and security hardening
- **Performance Tests** (78 tests) - Gas optimization and scalability
- **Integration Tests** (118 tests) - End-to-end workflows and multi-chain scenarios

### Run Tests

```bash
# Run all tests
forge test

# Run specific test categories
forge test --match-path "test/core/*"      # Core functionality
forge test --match-path "test/security/*"  # Security tests
forge test --match-path "test/integration/*" # Integration tests

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```

### Performance Benchmarks

```bash
# Gas snapshots
forge snapshot

# Performance tests
forge test --match-path "test/integration/PerformanceTests*" -vv
```

## 📋 Deployment

### Local Development

```bash
# Start local node
anvil

# Deploy contracts locally
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment

```bash
# Deploy to Goerli
forge script script/Deploy.s.sol \
  --rpc-url $GOERLI_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Mainnet Deployment

```bash
# Deploy to mainnet (use with caution)
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## 🔧 Usage

### For Traders

```solidity
// Large orders (>threshold) are automatically routed to private matching
IEigenVaultHook hook = IEigenVaultHook(hookAddress);

// Check if order qualifies for private routing
bool isLarge = hook.isLargeOrder(amountSpecified, poolKey);

// Orders execute automatically through appropriate channel
```

### For Liquidity Providers

```solidity
// Standard Uniswap v4 liquidity provision works seamlessly
// EigenVault adds no additional complexity for LPs
```

### For Operators

```solidity
// Register as EigenLayer operator
IEigenVaultAVS avs = IEigenVaultAVS(avsAddress);
avs.registerOperator{value: minimumStake}("operator-metadata-url");

// Respond to tasks
avs.submitTaskResponse(taskIndex, zkProofResponse);
```

## 🔒 Security

### Audits & Testing
- **343+ Test Functions** - Comprehensive test coverage
- **Security Test Suite** - 31 dedicated security tests
- **Attack Vector Analysis** - Protection against common DeFi attacks
- **ZK Proof Verification** - Mathematical verification of matching integrity

### Security Features
- **Reentrancy Protection** - OpenZeppelin ReentrancyGuard
- **Access Control** - Multi-level permission system
- **Emergency Pause** - System-wide pause capability
- **Slashing Protection** - EigenLayer slashing for misbehavior
- **Privacy Preservation** - Zero-knowledge proof privacy

### Bug Bounty
We welcome security researchers to review our code. Please report vulnerabilities responsibly through our [security policy](SECURITY.md).

## 📚 Documentation

### Technical Documentation
- [ZK Architecture](README_ZK_Architecture.md) - Zero-knowledge proof system design
- [ZK Implementation](ZK_IMPLEMENTATION.md) - Implementation details and proofs
- [AVS Integration](avs/README.md) - EigenLayer AVS integration guide

### API Reference
- **Smart Contracts** - See `/contracts/src/` for all contract interfaces
- **Test Examples** - See `/contracts/test/` for usage examples
- **Integration Guides** - See individual contract documentation

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add comprehensive tests
5. Ensure all tests pass (`forge test`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Standards
- Follow Solidity style guide
- Add comprehensive tests for all new features
- Include detailed documentation
- Maintain gas efficiency
- Ensure security best practices

## 📊 Metrics

- **343+ Test Functions** - Comprehensive testing coverage
- **Production Ready** - Hardened for institutional use
- **Gas Optimized** - Efficient execution costs
- **Multi-Chain** - Ready for cross-chain deployment

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Website**: [https://eigenvault.com](https://eigenvault.com)
- **Documentation**: [https://docs.eigenvault.com](https://docs.eigenvault.com)
- **GitHub**: [https://github.com/yourusername/EigenVault](https://github.com/yourusername/EigenVault)
- **Discord**: [Join our community](https://discord.gg/eigenvault)
- **Twitter**: [@EigenVault](https://twitter.com/eigenvault)

## ⚠️ Disclaimer

This software is in active development. Use at your own risk. The authors are not responsible for any losses that may occur from using this software.

---

**Built with ❤️ by the EigenVault team**