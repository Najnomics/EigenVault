# EigenVault Contracts 🔐

> **Core Smart Contract Implementation for EigenLayer-Secured Dark Pool Trading**

This directory contains the complete smart contract implementation for EigenVault, a privacy-preserving trading infrastructure that combines Uniswap v4 Hooks with EigenLayer's Actively Validated Services (AVS).

## 🏗️ Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    EigenVault Smart Contracts                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │   Uniswap v4    │  │  EigenLayer AVS  │  │   Order Vault   │  │
│  │      Hook       │◄─►│   ServiceManager │◄─►│   Storage      │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
│           │                       │                       │      │
│           ▼                       ▼                       ▼      │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Order Routing & │  │ Private Matching │  │ ZK Proof        │  │
│  │ Classification  │  │ & Verification   │  │ Verification    │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
contracts/
├── src/                              # Source contracts
│   ├── hooks/                        # Uniswap v4 Hook implementation
│   │   ├── EigenVaultHook.sol        # Main hook contract
│   │   └── IEigenVaultHook.sol       # Hook interface
│   ├── avs/                          # EigenLayer AVS contracts
│   │   ├── EigenVaultAVSServiceManager.sol  # AVS service manager
│   │   └── IEigenVaultAVSServiceManager.sol # AVS interface
│   ├── vault/                        # Order storage contracts
│   │   ├── OrderVault.sol            # Order storage contract
│   │   ├── OrderLib.sol              # Order data structures
│   │   ├── OrderMatchingLib.sol      # Order matching logic
│   │   └── IOrderVault.sol           # Vault interface
│   └── core/                         # Core utilities
│       ├── SecurityLib.sol           # Security utilities
│       └── ZKProofLib.sol            # ZK proof utilities
│
├── script/                           # Deployment scripts
│   ├── DeployOrderVaultOnly.s.sol    # OrderVault deployment
│   └── DeployWithProperHook.s.sol    # Full hook deployment
│
├── test/                             # Comprehensive test suite
│   ├── hooks/                        # Hook tests (180+ tests)
│   │   ├── EigenVaultHook.t.sol      # Main hook tests
│   │   ├── EigenVaultHookAdvanced.t.sol # Advanced hook tests
│   │   ├── EigenVaultHookBasic.t.sol # Basic hook tests
│   │   ├── EigenVaultHookCompleteTest.t.sol # Complete test suite
│   │   ├── EigenVaultHookDirectTest.t.sol # Direct hook tests
│   │   ├── EigenVaultHookUnitTest.t.sol # Unit tests
│   │   ├── EigenVaultHookWorkingTest.t.sol # Working tests
│   │   └── MockPoolManager.sol       # Mock pool manager
│   ├── avs/                          # AVS tests (50+ tests)
│   │   ├── EigenVaultAVSAdvanced.t.sol # Advanced AVS tests
│   │   └── EigenVaultAVSComprehensive.t.sol # Comprehensive AVS tests
│   ├── integration/                  # Integration tests (200+ tests)
│   │   ├── ComprehensiveIntegrationTests.t.sol
│   │   ├── MultiChainIntegrationTests.t.sol
│   │   ├── PerformanceTests.t.sol
│   │   ├── ProductionContractsTest.t.sol
│   │   └── StressTests.t.sol
│   ├── security/                     # Security tests (30+ tests)
│   │   └── AdvancedSecurityTests.t.sol
│   ├── vault/                        # Vault tests (50+ tests)
│   │   ├── BasicOrderVault.t.sol
│   │   ├── OrderLibComprehensive.t.sol
│   │   ├── OrderMatchingLibComprehensive.t.sol
│   │   └── OrderVaultAdvanced.t.sol
│   ├── core/                         # Core utility tests (40+ tests)
│   │   ├── SecurityLibComprehensive.t.sol
│   │   ├── SecurityTests.t.sol
│   │   ├── ZKProofEnhanced.t.sol
│   │   └── ZKProofLibComprehensive.t.sol
│   ├── mocks/                        # Mock contracts
│   │   ├── EigenLayerMocks.sol       # EigenLayer mock contracts
│   │   └── MockEigenVaultHookComplete.sol # Complete hook mock
│   ├── helpers/                      # Test helpers
│   │   └── HookDeployer.sol          # Hook deployment helper
│   ├── resilience/                   # Resilience tests
│   │   └── ProtocolResilienceTests.t.sol
│   └── utils/                        # Test utilities
│       ├── EigenVaultDeployers.sol
│       └── HookMiner.sol
│
├── lib/                              # External dependencies
│   ├── eigenlayer-middleware/        # EigenLayer middleware
│   ├── forge-std/                    # Foundry standard library
│   ├── openzeppelin-contracts/       # OpenZeppelin contracts
│   ├── v4-core/                      # Uniswap v4 core
│   └── v4-periphery/                 # Uniswap v4 periphery
│
├── foundry.toml                      # Foundry configuration
├── anvil-deployments.env             # Anvil deployment addresses
└── package.json                      # Node.js dependencies
```

## 🧪 Testing & Coverage

### Test Results Summary ✅
- **Total Tests**: 651 tests across all modules
- **Passing**: 651 ✅ (**100% pass rate**)
- **Test Coverage**: 
  - Lines: 47.46% (952/2006)
  - Statements: 49.59% (970/1956)
  - Branches: 9.19% (42/457)
  - Functions: 45.92% (208/453)

### Test Categories Breakdown

#### **Hook Tests** (180+ tests)
- **EigenVaultHook.t.sol**: 40 tests (100% passing)
- **EigenVaultHookAdvanced.t.sol**: 23 tests (100% passing)
- **EigenVaultHookBasic.t.sol**: 25 tests (100% passing)
- **EigenVaultHookCompleteTest.t.sol**: 100+ tests (100% passing)
- **EigenVaultHookDirectTest.t.sol**: 101 tests (100% passing)
- **EigenVaultHookUnitTest.t.sol**: 46 tests (100% passing)
- **EigenVaultHookWorkingTest.t.sol**: 28 tests (100% passing)

#### **AVS Tests** (50+ tests)
- **EigenVaultAVSAdvanced.t.sol**: Advanced AVS functionality
- **EigenVaultAVSComprehensive.t.sol**: 27 tests (100% passing)

#### **Integration Tests** (200+ tests)
- **ComprehensiveIntegrationTests.t.sol**: End-to-end workflows
- **MultiChainIntegrationTests.t.sol**: 9 tests (100% passing)
- **PerformanceTests.t.sol**: 10 tests (100% passing)
- **ProductionContractsTest.t.sol**: 6 tests (100% passing)
- **StressTests.t.sol**: 14 tests (100% passing)

#### **Security Tests** (30+ tests)
- **AdvancedSecurityTests.t.sol**: Advanced security scenarios
- **SecurityTests.t.sol**: 4 tests (100% passing)

#### **Vault Tests** (50+ tests)
- **BasicOrderVault.t.sol**: Basic vault functionality
- **OrderLibComprehensive.t.sol**: 22 tests (100% passing)
- **OrderMatchingLibComprehensive.t.sol**: 16 tests (100% passing)
- **OrderVaultAdvanced.t.sol**: 12 tests (100% passing)

#### **Core Tests** (40+ tests)
- **SecurityLibComprehensive.t.sol**: Security library tests
- **ZKProofEnhanced.t.sol**: 8 tests (100% passing)
- **ZKProofLibComprehensive.t.sol**: 15 tests (100% passing)

### Fuzz Testing
- **Fuzz Tests**: 180+ fuzz tests across all modules
- **Coverage**: Random parameter generation for edge case discovery
- **Security**: Boundary testing and overflow protection

### Performance Testing
- **Load Tests**: Large-scale order processing
- **Gas Optimization**: Efficient contract execution
- **Memory Usage**: Optimized storage patterns

## 🚀 Installation & Setup

### Prerequisites
- Node.js 18+
- Foundry (latest version)
- Git

### Installation Commands

```bash
# Install dependencies
npm install
forge install

# Setup environment
cp .env.example .env
# Configure your RPC URLs, private keys, etc.
```

## 🔧 Build Commands

```bash
# Build contracts
forge build

# Clean build artifacts
forge clean

# Build with optimization
forge build --sizes
```

## 🧪 Testing Commands

### Run All Tests
```bash
# All tests with verbose output
forge test -v

# All tests with gas reporting
forge test --gas-report
```

### Coverage Testing
```bash
# Full coverage with IR optimization
forge coverage --ir-minimum

# Standard coverage
forge coverage

# Coverage for specific modules
forge coverage --match-path "src/hooks/*" --ir-minimum
forge coverage --match-path "src/avs/*" --ir-minimum
forge coverage --match-path "src/vault/*" --ir-minimum
```

### Test Categories
```bash
# Hook tests only
forge test --match-contract "EigenVaultHook" -v

# AVS tests only
forge test --match-path "test/avs/*" -v

# Integration tests only
forge test --match-path "test/integration/*" -v

# Security tests only
forge test --match-path "test/security/*" -v

# Vault tests only
forge test --match-path "test/vault/*" -v

# Fuzz tests only
forge test --match-test "testFuzz" -v

# Performance tests only
forge test --match-path "test/integration/PerformanceTests.t.sol" -v
```

### Specific Test Files
```bash
# Main hook tests
forge test --match-path "test/hooks/EigenVaultHook.t.sol" -v

# Advanced hook tests
forge test --match-path "test/hooks/EigenVaultHookAdvanced.t.sol" -v

# Complete hook test suite
forge test --match-path "test/hooks/EigenVaultHookCompleteTest.t.sol" -v

# AVS comprehensive tests
forge test --match-path "test/avs/EigenVaultAVSComprehensive.t.sol" -v

# Stress tests
forge test --match-path "test/integration/StressTests.t.sol" -v
```

## 🚀 Deployment

### Local Development (Anvil)

```bash
# Start Anvil (in separate terminal)
anvil --host 0.0.0.0 --port 8545 --accounts 10 --balance 10000

# Deploy OrderVault only
forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy full hook system
forge script script/DeployWithProperHook.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet Deployment

```bash
# Deploy to Holesky testnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $HOLESKY_RPC_URL

# Deploy with verification
forge script script/DeployOrderVaultOnly.s.sol --broadcast --verify --rpc-url $HOLESKY_RPC_URL
```

### Production Deployment

```bash
# Deploy to mainnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $MAINNET_RPC_URL

# Verify contracts on Etherscan
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --etherscan-api-key $ETHERSCAN_API_KEY $CONTRACT_ADDRESS src/hooks/EigenVaultHook.sol:EigenVaultHook
```

## 📊 Contract Analysis

### Gas Optimization
- **Hook Deployment**: Optimized for minimal gas usage
- **Order Processing**: Efficient storage patterns
- **AVS Operations**: Batch processing for multiple orders

### Security Features
- **Access Control**: Role-based permissions
- **Reentrancy Protection**: Secure state management
- **Integer Overflow**: Safe math operations
- **Emergency Pause**: Circuit breaker functionality

### Key Contracts

#### **EigenVaultHook.sol**
- **Lines**: 307
- **Functions**: 51
- **Coverage**: Core hook functionality
- **Features**: Order routing, threshold management, emergency controls

#### **EigenVaultAVSServiceManager.sol**
- **Lines**: 167
- **Functions**: 34
- **Coverage**: AVS operator management
- **Features**: Task distribution, reward management, slashing

#### **OrderVault.sol**
- **Lines**: 206
- **Functions**: 42
- **Coverage**: Order storage and retrieval
- **Features**: Encrypted storage, expiration handling, authorization

## 🔍 Code Quality

### Linting
```bash
# Run linter
npm run lint

# Fix linting issues
npm run lint:fix
```

### Formatting
```bash
# Format code
forge fmt

# Check formatting
forge fmt --check
```

### Static Analysis
```bash
# Run static analysis
slither .

# Run Mythril
myth analyze src/hooks/EigenVaultHook.sol
```

## 📈 Performance Metrics

### Gas Usage
- **Hook Deployment**: ~2.8M gas
- **Order Storage**: ~300K gas
- **Order Retrieval**: ~50K gas
- **AVS Task Creation**: ~200K gas

### Storage Optimization
- **Packed Structs**: Efficient storage layout
- **Batch Operations**: Reduced transaction costs
- **Lazy Loading**: On-demand data retrieval

## 🛡️ Security Considerations

### Access Control
- **Owner Functions**: Restricted to contract owner
- **Hook Authorization**: Only authorized hooks can store orders
- **AVS Operator**: Only registered operators can process tasks

### Privacy Protection
- **Order Encryption**: Client-side encryption before storage
- **Commitment Schemes**: Order details hidden until execution
- **Zero-Knowledge Proofs**: Valid matching without revealing orders

### Emergency Controls
- **Emergency Pause**: Circuit breaker for critical functions
- **Owner Recovery**: Emergency owner functions for upgrades
- **Slashing Protection**: Operator stake protection mechanisms

## 📚 Documentation

### Contract Documentation
- **NatSpec Comments**: Comprehensive function documentation
- **Interface Definitions**: Clear contract interfaces
- **Usage Examples**: Code examples for integration

### API Reference
- **Function Signatures**: Complete function documentation
- **Parameter Types**: Detailed parameter descriptions
- **Return Values**: Clear return value documentation

## 🤝 Contributing

### Development Workflow
1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Testing Requirements
- **New Features**: Must include unit tests
- **Bug Fixes**: Must include regression tests
- **Coverage**: Maintain or improve test coverage
- **Performance**: Consider gas optimization

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

**Built with ❤️ for the Uniswap v4 Hookathon (UHI6) - EigenLayer Benefactor Track**

*"Your Private Trading Vault on EigenLayer"*