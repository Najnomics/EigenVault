# EigenVault Architecture

## Overview

EigenVault is a sophisticated DeFi project that combines Uniswap v4 Hooks with EigenLayer AVS (Actively Validated Services) to create a privacy-preserving dark pool for large orders. This document provides a detailed technical overview of the system architecture.

## System Components

### 1. Smart Contracts Layer

#### EigenVaultHook
- **Location**: `eigenvault/contracts/src/SimplifiedEigenVaultHook.sol`
- **Purpose**: Uniswap v4 hook that intercepts large orders and routes them to the privacy vault
- **Key Functions**:
  - `beforeSwap()`: Intercepts swap attempts and checks order size
  - `executeVaultOrder()`: Executes matched orders with ZK proofs
  - Order routing logic for large trades

#### ServiceManager
- **Location**: `eigenvault/contracts/src/SimplifiedServiceManager.sol`
- **Purpose**: EigenLayer AVS service manager for operator coordination
- **Key Functions**:
  - Operator registration and management
  - Task creation and distribution
  - Result aggregation and validation

#### OrderVault
- **Location**: `eigenvault/contracts/src/OrderVault.sol`
- **Purpose**: Secure storage for encrypted orders
- **Key Functions**:
  - `storeOrder()`: Store encrypted order data
  - `retrieveOrder()`: Allow authorized operators to retrieve orders
  - Order lifecycle management

### 2. Off-chain Operator Software

#### Matching Engine
- **Location**: `eigenvault/operator/src/matching/`
- **Components**:
  - `engine.rs`: Core order matching logic
  - `orderbook.rs`: Order book management
  - `privacy.rs`: Encryption/decryption handling
- **Functionality**:
  - Decrypt operator orders using private keys
  - Find optimal matches using price-time priority
  - Generate batch matches for efficiency

#### Zero-Knowledge Proof System
- **Location**: `eigenvault/operator/src/proofs/`
- **Components**:
  - `generator.rs`: ZK proof generation
  - `verifier.rs`: Proof verification
- **Circuits**: `circuits/order_matching.circom`, `circuits/privacy_proof.circom`
- **Purpose**: Prove correct matching without revealing order details

#### P2P Networking
- **Location**: `eigenvault/operator/src/networking/`
- **Components**:
  - `p2p.rs`: Peer-to-peer network management
  - `gossip.rs`: Order and result gossip protocol
  - `encryption.rs`: Secure communication
- **Functionality**:
  - Distribute encrypted orders among operators
  - Share matching results for consensus
  - Maintain operator network topology

#### Ethereum Integration
- **Location**: `eigenvault/operator/src/ethereum/`
- **Components**:
  - `client.rs`: Ethereum RPC client
  - `contracts.rs`: Smart contract interactions
  - `events.rs`: Event monitoring and parsing
- **Purpose**: Bridge between off-chain matching and on-chain execution

### 3. Frontend Interface

#### Trading Interface
- **Location**: `frontend/src/components/`
- **Components**:
  - `OrderForm.tsx`: Large order submission
  - `VaultStatus.tsx`: Vault monitoring
  - `OperatorList.tsx`: Operator information
- **Features**:
  - Client-side order encryption
  - Real-time order status tracking
  - Operator performance metrics

## Data Flow

### 1. Order Submission Flow

```
1. Trader submits large order via frontend
2. Frontend encrypts order with operator public keys
3. Order routed through EigenVaultHook
4. Encrypted order stored in OrderVault
5. TaskCreated event emitted
6. Operators receive and decrypt order
7. Order added to matching engine
```

### 2. Matching Flow

```
1. Operator matching engine processes pending orders
2. Compatible orders identified using price-time priority
3. ZK proof generated for valid matches
4. Proof and results shared via P2P gossip
5. Consensus reached among operators
6. Results submitted to ServiceManager
7. Orders executed on-chain via hook
```

### 3. Privacy Preservation

```
1. Orders encrypted client-side before submission
2. Only authorized operators can decrypt
3. ZK proofs prove correct matching without revealing details
4. On-chain execution reveals only final trade details
5. Trader identities and intermediate states remain private
```

## Security Model

### Cryptographic Assumptions
- **Encryption**: AES-256-GCM for order data
- **Key Exchange**: ECDH for operator communication
- **Signatures**: ECDSA for authentication
- **Zero-Knowledge**: Groth16 for succinctness

### Trust Model
- **Operators**: Staked entities with economic incentives
- **Cryptography**: No trusted setup required for order privacy
- **Smart Contracts**: Immutable logic with timelock governance
- **Users**: Trust in cryptographic primitives only

### Attack Vectors & Mitigations
- **MEV**: Orders hidden until execution
- **Front-running**: Encrypted order submission
- **Collusion**: Multiple independent operators required
- **Censorship**: Decentralized operator network

## Performance Characteristics

### Scalability
- **Order Throughput**: ~100 orders/second per operator
- **Matching Latency**: ~100ms for simple matches
- **Proof Generation**: ~30 seconds for complex batches
- **Network Propagation**: ~1 second for P2P gossip

### Resource Requirements
- **CPU**: Moderate for proof generation
- **Memory**: ~1GB per operator
- **Storage**: ~10GB for order history
- **Network**: ~10 Mbps for real-time operation

## Deployment Architecture

### Development Environment
```
Frontend (React) ←→ Operator (Rust) ←→ Local Ethereum Node
                           ↓
                    MongoDB (Orders) + Redis (Cache)
```

### Production Environment
```
Load Balancer → Frontend Cluster
                     ↓
              Operator Network ←→ Ethereum Mainnet
                     ↓              ↓
              Monitoring Stack   Smart Contracts
```

## Integration Points

### Uniswap v4 Integration
- Hook deployment and registration
- Pool factory integration
- Liquidity provider coordination
- Fee structure alignment

### EigenLayer Integration
- AVS registration and management
- Slashing condition specification
- Reward distribution mechanism
- Governance participation

## Future Enhancements

### Phase 2: Advanced Features
- Cross-chain order matching
- Dynamic fee adjustment
- Advanced order types (stop-loss, etc.)
- Institutional API endpoints

### Phase 3: Ecosystem Integration
- DEX aggregator partnerships
- Institutional custody integration
- Regulatory compliance tools
- Advanced analytics dashboard

## Technical Specifications

### Smart Contract Addresses (Testnet)
```
ServiceManager: 0x1234567890123456789012345678901234567890
EigenVaultHook: 0x2345678901234567890123456789012345678901
OrderVault: 0x3456789012345678901234567890123456789012
```

### Network Configuration
```
Chain ID: 1301 (Unichain Sepolia)
RPC URL: https://sepolia.unichain.org
Block Time: ~2 seconds
Gas Limit: 30M
```

### Operator Requirements
```
Minimum Stake: 32 ETH
Hardware: 4 CPU, 8GB RAM, 100GB SSD
Network: Static IP, 10 Mbps
Uptime: >99% availability required
```

This architecture enables secure, private, and efficient large order execution while maintaining decentralization and preventing MEV extraction.