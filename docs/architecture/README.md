# EigenVault Architecture Documentation

## Overview

EigenVault is a privacy-preserving trading infrastructure that combines Uniswap v4 Hooks with EigenLayer's Actively Validated Services (AVS) to enable institutional-grade dark pool functionality.

## Core Architecture

### System Components

1. **Uniswap v4 Hook Layer**
   - EigenVaultHook: Main hook contract for order interception
   - Order classification and routing logic
   - Integration with Uniswap v4 pool manager

2. **EigenLayer AVS Infrastructure**
   - EigenVaultAVSServiceManager: Central coordination contract
   - Operator registration and management
   - Task distribution and execution

3. **Order Storage & Management**
   - OrderVault: Encrypted order storage
   - OrderLib: Order data structures and utilities
   - OrderMatchingLib: Matching algorithms and logic

4. **Privacy & Security**
   - ZKProofLib: Zero-knowledge proof verification
   - SecurityLib: Security utilities and access control
   - Client-side encryption for order privacy

### Data Flow

```
User Order → Hook Interception → Order Classification → 
Large Order → AVS Processing → Private Matching → 
ZK Proof Generation → On-chain Verification → Execution
```

## Detailed Component Analysis

### EigenVaultHook.sol

The main Uniswap v4 hook that orchestrates the entire system:

- **Order Interception**: Catches all swaps before execution
- **Size Classification**: Determines if orders need private processing
- **Routing Logic**: Routes large orders to AVS, small orders to AMM
- **Execution Coordination**: Manages the execution of matched orders

### EigenVaultAVSServiceManager.sol

Central coordination contract for the AVS network:

- **Operator Management**: Registration, deregistration, and stake management
- **Task Distribution**: Assigns matching tasks to operator quorum
- **Proof Verification**: Validates ZK proofs of successful matches
- **Reward Distribution**: Distributes fees to performing operators
- **Slashing Enforcement**: Executes penalties for malicious behavior

### OrderVault.sol

Secure storage for encrypted orders:

- **Encrypted Storage**: Stores orders with client-side encryption
- **Access Control**: Only authorized hooks can store/retrieve orders
- **Expiration Handling**: Manages order timeouts and cleanup
- **Metadata Management**: Tracks order statistics and performance

## Security Model

### Cryptoeconomic Security

The system leverages EigenLayer's restaking mechanism for security:

- **Operator Staking**: Minimum 32 ETH stake per operator
- **Slashing Conditions**: Penalties for malicious behavior
- **Incentive Alignment**: Rewards for correct behavior

### Privacy Protection

Multi-layer privacy protection:

1. **Client-Side Encryption**: Orders encrypted before submission
2. **Commitment Schemes**: Order details hidden until execution
3. **Zero-Knowledge Proofs**: Valid matching without revealing orders
4. **Threshold Decryption**: Requires multiple operators for decryption

### Access Control

Role-based access control system:

- **Owner**: Contract administration and emergency controls
- **Authorized Hooks**: Can store and retrieve orders
- **AVS Operators**: Can process matching tasks
- **Service Manager**: Can execute matched orders

## Performance Considerations

### Gas Optimization

- **Efficient Storage**: Packed structs and optimized data layouts
- **Batch Operations**: Process multiple orders in single transaction
- **Lazy Loading**: On-demand data retrieval to reduce gas costs

### Scalability

- **Horizontal Scaling**: Multiple operators can process orders in parallel
- **Load Balancing**: Automatic distribution of tasks across operators
- **Caching**: In-memory caching for frequently accessed data

## Integration Points

### Uniswap v4 Integration

- **Hook Interface**: Implements IHook interface for v4 compatibility
- **Pool Manager**: Interacts with Uniswap v4 pool manager
- **Swap Parameters**: Handles swap parameters and execution

### EigenLayer Integration

- **AVS Registration**: Registers as an actively validated service
- **Operator Management**: Manages operator registration and stakes
- **Slashing Integration**: Integrates with EigenLayer's slashing mechanism

### FHEnix Integration

- **Client Encryption**: Uses FHEnix libraries for client-side encryption
- **Secure Computation**: Leverages FHE for privacy-preserving matching
- **Proof Generation**: Generates proofs using FHEnix circuits

## Deployment Architecture

### Network Topology

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Ethereum      │    │   EigenLayer     │    │   FHEnix        │
│   Mainnet       │◄──►│   AVS Network    │◄──►│   Privacy Layer │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Uniswap v4    │    │   EigenVault     │    │   Client Apps   │
│   Pools         │    │   Operators      │    │   & Wallets     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Deployment Components

1. **Smart Contracts**: Deployed on Ethereum mainnet
2. **AVS Operators**: Distributed across multiple nodes
3. **Client Libraries**: Available for integration
4. **Monitoring**: Comprehensive monitoring and alerting

## Future Enhancements

### Planned Features

- **Multi-chain Support**: Extend to other EVM-compatible chains
- **Advanced Matching**: AI-powered matching algorithms
- **Cross-chain Orders**: Support for cross-chain order matching
- **Institutional Features**: Advanced order types and controls

### Research Areas

- **Privacy Improvements**: Enhanced privacy-preserving techniques
- **Performance Optimization**: Further gas and latency optimizations
- **Security Enhancements**: Additional security mechanisms
- **User Experience**: Improved interfaces and workflows
