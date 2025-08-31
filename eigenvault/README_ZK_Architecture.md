# EigenVault ZK Proof Architecture 🔐

## Overview

EigenVault is a privacy-preserving trading infrastructure that combines Uniswap v4 Hooks with EigenLayer's Actively Validated Services (AVS) to enable institutional-grade dark pool functionality on DEXs. This document outlines the clean ZK proof-based architecture after removing all FHE implementations.

## 🏗️ Architecture Overview

### Core Components

1. **EigenVaultHook** - Uniswap v4 hook for order routing and execution
2. **OrderVault** - Secure storage for order data with ZK proof verification
3. **EigenVaultAVSServiceManager** - AVS integration for consensus and task management
4. **ZK Proof Circuits** - Circom circuits for order validation and matching verification

### Architecture Flow

```
User Order → EigenVaultHook → Threshold Check → Route Decision
                                    ↓
                            Large Order → OrderVault → AVS Task Creation
                                    ↓
                            AVS Operators → Private Matching → ZK Proof Generation
                                    ↓
                            ZK Proof Verification → Order Execution → Uniswap Pool
```

## 🔐 ZK Proof Integration

### What ZK Proofs Provide

- **Order Validity**: Prove orders satisfy constraints without revealing details
- **Matching Verification**: Ensure correct order matching logic
- **Privacy**: Hide sensitive order information while maintaining verifiability
- **Efficiency**: Batch verification for multiple operations

### ZK Proof Circuits

#### 1. Privacy Proof Circuit (`privacy_proof.circom`)
- Validates order commitments
- Ensures price and amount bounds
- Verifies deadline constraints
- Generates validity hashes

#### 2. Order Matching Circuit (`order_matching.circom`)
- Proves correct order matching
- Validates buy/sell compatibility
- Ensures price compatibility
- Verifies amount constraints

## 🚀 Key Benefits of ZK Architecture

### 1. **Privacy & Security**
- Orders are committed to the chain as hashes
- Sensitive data remains private until execution
- ZK proofs ensure correctness without revealing inputs

### 2. **Efficiency**
- No encryption/decryption overhead
- Efficient batch verification
- Lower gas costs compared to FHE

### 3. **Proven Technology**
- ZK proofs are battle-tested in production
- Well-understood security model
- Extensive tooling and ecosystem support

### 4. **Regulatory Compliance**
- Audit trail through commitments
- Verifiable correctness
- Transparent execution process

## 🏛️ Smart Contract Architecture

### EigenVaultHook

The main hook contract that:
- Intercepts Uniswap v4 swaps
- Determines if orders should go to vault or execute directly
- Routes large orders to the OrderVault
- Executes matched orders after ZK verification

### OrderVault

Secure storage contract that:
- Stores order commitments and metadata
- Manages order lifecycle
- Integrates with ZK proof verification
- Provides order retrieval for AVS operators

### EigenVaultAVSServiceManager

AVS integration contract that:
- Manages operator registration and staking
- Creates and tracks matching tasks
- Handles consensus through quorum mechanisms
- Integrates ZK proof verification for task completion

## 🔄 Order Flow

### 1. **Order Submission**
```
User submits order → Hook intercepts → Threshold check → Route decision
```

### 2. **Large Order Processing**
```
Order routed to vault → Commitment stored → AVS task created → Operators notified
```

### 3. **Private Matching**
```
AVS operators match orders off-chain → Generate ZK proof → Submit to service manager
```

### 4. **Execution**
```
ZK proof verified → Order executed → Uniswap swap performed → Results recorded
```

## 🛡️ Security Features

### 1. **Commitment Scheme**
- Orders committed as hashes before processing
- Prevents front-running and MEV attacks
- Ensures order integrity

### 2. **ZK Proof Verification**
- Mathematical guarantees of correctness
- No trusted third parties required
- Verifiable privacy preservation

### 3. **EigenLayer Security**
- Cryptoeconomic security through restaking
- Slashing conditions for misbehavior
- Decentralized operator network

### 4. **Access Control**
- Authorized hooks and operators only
- Owner controls for critical functions
- Emergency pause capabilities

## 🧪 Testing & Development

### ZK Circuit Development
- Use Circom for circuit development
- Test circuits with Circom tester
- Generate and verify proofs

### Smart Contract Testing
- Foundry-based testing framework
- Comprehensive test coverage
- Integration testing with ZK proofs

### AVS Integration Testing
- Test operator registration and staking
- Verify task creation and completion
- Test consensus mechanisms

## 🚀 Deployment

### 1. **Circuit Compilation**
```bash
cd circuits
circom privacy_proof.circom --r1cs --wasm --sym
circom order_matching.circom --r1cs --wasm --sym
```

### 2. **Contract Deployment**
```bash
cd contracts
forge script script/DeployEigenVaultAVS.s.sol --rpc-url <RPC_URL> --broadcast
```

### 3. **AVS Configuration**
- Register with EigenLayer
- Configure operator requirements
- Set up slashing conditions

## 📚 Next Steps

### 1. **ZK Proof Integration**
- Implement ZK proof verification in contracts
- Connect Circom circuits to Solidity
- Add proof generation utilities

### 2. **AVS Operator Software**
- Develop operator client software
- Implement order matching algorithms
- Add ZK proof generation

### 3. **Testing & Auditing**
- Comprehensive testing suite
- Security audit
- Performance optimization

### 4. **Mainnet Deployment**
- Testnet validation
- Gradual rollout
- Monitoring and maintenance

## 🎯 Conclusion

The ZK proof-based architecture provides EigenVault with:
- **Strong privacy guarantees** through cryptographic commitments
- **Efficient verification** without encryption overhead
- **Proven security** through battle-tested ZK technology
- **Scalable design** for institutional adoption

This architecture positions EigenVault as a leading privacy-preserving DEX solution, combining the best of Uniswap v4, EigenLayer, and zero-knowledge proofs. 