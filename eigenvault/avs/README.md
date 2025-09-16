# EigenVault AVS

A Hourglass-based Autonomous Verifiable Service (AVS) that provides distributed compute infrastructure for EigenVault's privacy-preserving order matching and MEV redistribution system.

## Overview

This AVS serves as a **distributed execution layer** for EigenVault operations using the Hourglass framework to provide:

- **Distributed task execution** for order matching operations
- **EigenLayer operator management** and staking coordination  
- **Privacy-preserving computation** for encrypted order processing
- **Decentralized consensus** on order execution and rewards distribution

## Architecture

This AVS follows the Hourglass DevKit template structure:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  EigenLayer     │───▶│  L1: Service    │───▶│  L2: Task Hook  │
│  (Operators)    │    │  Manager        │    │  (Validator)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
                                               ┌─────────────────┐
                                               │  EigenVault:    │
                                               │  Order Matching │
                                               │  & MEV System   │
                                               └─────────────────┘
```

### Directory Structure

```
├── cmd/                          # Performer application (task orchestration)
│   ├── main.go                  # ✅ EigenVault Performer implementation
│   └── main_test.go             # ✅ Comprehensive tests for all task types
├── contracts/                    # EigenVault AVS contracts
│   ├── src/
│   │   ├── interfaces/          # AVS-specific interfaces
│   │   │   └── IAVSDirectory.sol # ✅ EigenLayer AVS interface
│   │   ├── l1-contracts/        # EigenLayer integration
│   │   │   └── EigenVaultServiceManager.sol # ✅ L1 service manager
│   │   └── l2-contracts/        # Task lifecycle management
│   │       └── EigenVaultTaskHook.sol # ✅ L2 task hook
│   ├── script/                  # Deployment scripts
│   │   ├── DeployEigenVaultL1Contracts.s.sol # ✅ Deploy L1 contracts
│   │   └── DeployEigenVaultL2Contracts.s.sol # ✅ Deploy L2 contracts
│   └── test/                    # Contract tests
│       ├── EigenVaultServiceManager.t.sol # ✅ L1 contract tests
│       └── EigenVaultTaskHook.t.sol       # ✅ L2 contract tests
├── .devkit/                     # DevKit integration
├── .hourglass/                  # Hourglass framework configuration
├── go.mod                       # ✅ Go dependencies (Hourglass/Ponos)
├── go.sum                       # ✅ Dependency checksums
└── README.md                    # This file
```

### Component Responsibilities

**✅ AVS Contracts:**
- **L1 ServiceManager** (`EigenVaultServiceManager.sol`):
  - EigenLayer operator registration and staking coordination
  - Extends `TaskAVSRegistrarBase` for EigenLayer integration
  - Manages operator stake requirements and slashing conditions
  
- **L2 TaskHook** (`EigenVaultTaskHook.sol`):
  - Implements `IAVSTaskHook` for Hourglass task lifecycle management
  - Validates EigenVault task parameters and calculates fees
  - Coordinates with main EigenVault Hook system

**✅ Go Performer (`cmd/main.go`):**
- **Task Orchestration**: Coordinates distributed execution of EigenVault tasks
- **Payload Parsing**: Handles 4 task types (order matching, privacy execution, rewards update, stake validation)
- **Result Aggregation**: Aggregates responses from operators for consensus
- **Hourglass Integration**: Implements `ValidateTask` and `HandleTask` interfaces

## Quick Start

### Prerequisites

- [Docker (latest)](https://docs.docker.com/engine/install/)
- [Foundry (latest)](https://book.getfoundry.sh/getting-started/installation)
- [Go (v1.23.6)](https://go.dev/doc/install)
- [DevKit CLI](https://github.com/Layr-Labs/devkit-cli)

### Build

```bash
# Build the performer binary
make build

# Build contracts
make build-contracts

# Build everything
make
```

### Development with DevKit

```bash
# Build AVS and contracts
devkit avs build --image eigenvault

# Start local development network
devkit avs devnet start

# Run the performer
devkit avs run

# Simulate tasks
devkit avs call --task-type order_matching
```

### Testing

```bash
# Run all tests
make test

# Run Go tests only
make test-go

# Run Forge tests only
make test-forge
```

## Task Types

The EigenVault Performer coordinates distributed execution of four main task types:

### 1. Order Matching Tasks
- **Coordinate** order matching across multiple operators
- **Apply** optimal matching algorithms with privacy preservation
- **Generate** execution plans for matched orders

### 2. Privacy Execution Tasks  
- **Process** encrypted order parameters using secure computation
- **Execute** orders with privacy guarantees
- **Generate** zero-knowledge proofs for order execution

### 3. Rewards Update Tasks
- **Calculate** operator performance metrics
- **Update** stake weights and rewards distribution
- **Process** MEV redistribution to users

### 4. Stake Validation Tasks
- **Validate** operator stake amounts and delegations
- **Check** slashing conditions and requirements
- **Coordinate** stake updates with EigenLayer

## Configuration

Configuration is managed through the Hourglass framework:

- **`.hourglass/config/`** - Framework configuration
- **`.hourglass/context/`** - Environment-specific settings
- **`.devkit/`** - Development tooling configuration

## Smart Contracts

### AVS Contracts

#### L1 Contracts (Ethereum Mainnet)
- **EigenVaultServiceManager.sol** - EigenLayer integration
  - ✅ Extends `TaskAVSRegistrarBase` for DevKit compliance
  - ✅ Handles operator registration with minimum stake requirements
  - ✅ Manages slashing conditions for poor performance
  - ✅ Coordinates with L2 hook system

#### L2 Contracts (Layer 2 Networks)
- **EigenVaultTaskHook.sol** - Task system coordinator
  - ✅ Implements `IAVSTaskHook` for Hourglass integration
  - ✅ Validates 4 EigenVault task types with proper fee structure
  - ✅ Calculates task fees based on computational complexity
  - ✅ Interfaces with main EigenVault Hook system

## Deployment

### AVS Deployment
Deployment is handled through DevKit scripts:

```bash
# 1. Deploy L1 AVS contracts (EigenLayer integration)
forge script contracts/script/DeployEigenVaultL1Contracts.s.sol:DeployEigenVaultL1Contracts

# 2. Deploy L2 AVS contracts
forge script contracts/script/DeployEigenVaultL2Contracts.s.sol:DeployEigenVaultL2Contracts
```

### Deployment Order
1. **AVS L1**: Deploy `EigenVaultServiceManager` (EigenLayer integration)  
2. **AVS L2**: Deploy `EigenVaultTaskHook` (task coordination)
3. **Configure**: Update context files with deployed addresses

## API

The performer exposes a gRPC server on port 8080 implementing the Hourglass Performer interface:

- `ValidateTask(TaskRequest) -> error` - Validates EigenVault task parameters
- `HandleTask(TaskRequest) -> TaskResponse` - Coordinates task execution

### Task Payload Structure

Tasks are JSON payloads with the following structure:
```json
{
  "type": "order_matching|privacy_execution|rewards_update|stake_validation", 
  "parameters": {
    "poolId": "0x...",
    "orders": [...],
    "privacyLevel": "high",
    // ... task-specific parameters
  }
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.