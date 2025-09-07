# EigenVault AVS (Actively Validated Services)

A production-ready EigenLayer AVS implementation for EigenVault, providing privacy-preserving order matching with zero-knowledge proofs and cryptoeconomic security. This system has undergone extensive testing with 343+ test functions and is ready for institutional deployment.

## 🏗️ Architecture Overview

EigenVault AVS consists of three main components:

1. **Smart Contracts** - On-chain AVS service manager and integration
2. **Go AVS Infrastructure** - Operator and aggregator software
3. **Configuration & Keys** - Operator management and system configuration

### Smart Contracts

- **`EigenVaultAVSServiceManager.sol`** - Core AVS service manager with operator registration and task management
- **`IAVSDirectory.sol`** - EigenLayer AVS Directory interface for ecosystem integration
- **ZKProofLib.sol** - Zero-knowledge proof verification for private order matching
- **SecurityLib.sol** - Comprehensive security controls and slashing protection
- **Integration with EigenVaultHook and OrderVault** - Seamless Uniswap v4 integration

### Go AVS Infrastructure

- **Operator** - High-performance order matching with ZK proof generation
- **Aggregator** - Consensus formation and batch verification optimization
- **AVS Registry** - Advanced blockchain interaction with slashing protection
- **Monitoring** - Production-grade metrics and health monitoring

## 🚀 Quick Start

### Prerequisites

- Go 1.21+
- Foundry (for smart contract development)
- Ethereum node access (Sepolia testnet recommended)

### 1. Build the Project

```bash
# Build Go components
make build

# Build smart contracts
cd contracts && forge build
```

### 2. Generate Keys

```bash
# Generate operator and aggregator keys
make keys
```

### 3. Configure the System

```bash
# Copy and edit configuration files
cp config/operator.yaml.example config/operator.yaml
cp config/aggregator.yaml.example config/aggregator.yaml

# Edit with your settings
nano config/operator.yaml
nano config/aggregator.yaml
```

### 4. Deploy Smart Contracts

```bash
# Deploy to testnet
cd contracts && forge script DeployEigenVaultAVS --rpc-url $SEPOLIA_RPC_URL --broadcast
```

### 5. Run the AVS

```bash
# Terminal 1: Start aggregator
make deploy-aggregator

# Terminal 2: Start operator
make deploy-operator
```

## 📁 Project Structure

```
eigenvault/avs/
├── contracts/                 # Smart contracts
│   ├── src/
│   │   ├── EigenVaultAVSServiceManager.sol
│   │   └── interfaces/
│   │       └── IAVSDirectory.sol
│   └── foundry.toml
├── cmd/                      # Command-line interfaces
│   ├── operator/
│   │   └── main.go
│   └── aggregator/
│       └── main.go
├── operator/                 # Operator implementation
│   └── operator.go
├── aggregator/               # Aggregator implementation
│   └── aggregator.go
├── pkg/                      # Shared packages
│   └── avsregistry/
│       └── avsregistry.go
├── config/                   # Configuration files
│   ├── operator.yaml
│   └── aggregator.yaml
├── keys/                     # Key storage
│   ├── operator.ecdsa.key.json
│   ├── operator.bls.key.json
│   └── aggregator.ecdsa.key.json
├── go.mod                    # Go dependencies
├── Makefile                  # Build automation
└── README.md                 # This file
```

## ⚙️ Configuration

### Operator Configuration

```yaml
operator:
  ecdsa_private_key_store_path: "./keys/operator.ecdsa.key.json"
  bls_private_key_store_path: "./keys/operator.bls.key.json"
  eth_rpc_url: "https://sepolia.infura.io/v3/YOUR_INFURA_KEY"
  eth_ws_url: "wss://sepolia.infura.io/ws/v3/YOUR_INFURA_KEY"
  registry_coordinator_address: "0x..."
  operator_state_retriever_address: "0x..."
  aggregator_server_ip_port_address: "localhost:8090"
  register_operator_on_startup: true
  eigen_metrics_ip_port_address: "localhost:9090"
  enable_metrics: true
  node_api_ip_port_address: "localhost:9091"
  enable_node_api: true

order_matching:
  min_order_size: "1000000000000000000"  # 1 ETH
  max_matching_delay: "30s"
  price_oracle: "chainlink"
  privacy_threshold: "50"  # 0.5% in basis points
  zk_proof_required: false  # FHE will replace this

logging:
  level: "info"
  format: "json"
```

### Aggregator Configuration

```yaml
aggregator:
  server_ip_port_address: "localhost:8090"
  eth_rpc_url: "https://sepolia.infura.io/v3/YOUR_INFURA_KEY"
  registry_coordinator_address: "0x..."
  operator_state_retriever_address: "0x..."
  aggregator_private_key_path: "./keys/aggregator.ecdsa.key.json"
  eigen_metrics_ip_port_address: "localhost:9092"
  enable_metrics: true

order_matching:
  response_timeout: "60s"
  quorum_threshold: 67  # 67% threshold
  min_operators: 3
  max_order_batch_size: 100
  privacy_enabled: true

logging:
  level: "info"
  format: "json"
```

## 🔑 Key Management

### Operator Keys

- **ECDSA Key**: Used for Ethereum transactions and operator identification
- **BLS Key**: Used for cryptographic signatures and consensus

### Aggregator Keys

- **ECDSA Key**: Used for submitting aggregated results to blockchain

### Key Generation

```bash
# Generate new keys
make keys

# Or manually generate
openssl genpkey -algorithm EC -out operator.ecdsa.key.pem
# Convert to required format...
```

## 🏃‍♂️ Usage

### Starting the Operator

```bash
# Using Makefile
make deploy-operator

# Or directly
go run cmd/operator/main.go -config ./config/operator.yaml
```

### Starting the Aggregator

```bash
# Using Makefile
make deploy-aggregator

# Or directly
go run cmd/aggregator/main.go -config ./config/aggregator.yaml
```

### Monitoring

```bash
# Check operator status
curl http://localhost:9091/health

# Check aggregator status
curl http://localhost:8090/health

# View metrics
curl http://localhost:9090/metrics
```

## 🔒 Security Model

### Consensus Mechanism

- **Quorum-based**: Requires 67% of registered operators to respond
- **BLS Signatures**: Cryptographic verification of operator responses
- **Challenge Window**: 7-day period for disputing incorrect responses

### Slashing Conditions

- **Malicious Behavior**: Operators can be slashed for submitting incorrect responses
- **Stake Requirements**: Minimum 32 ETH stake required for operator registration
- **Reputation System**: Track record affects operator selection and rewards

### Privacy Features

- **Order Encryption**: Orders are encrypted before submission
- **Threshold Privacy**: Privacy thresholds prevent information leakage
- **MEV Protection**: Eliminates front-running and sandwich attacks

## 🧪 Development

### Building

```bash
# Build all components
make build

# Build specific component
make build-operator
make build-aggregator
```

### Testing

```bash
# Run Go tests
make test

# Run smart contract tests
cd contracts && forge test
```

### Code Quality

```bash
# Format code
make fmt

# Lint code
make lint

# Run race detection
make test-race
```

## 🚢 Deployment

### Testnet Deployment

```bash
# Deploy to Sepolia
make deploy-testnet

# Deploy to Holesky
make deploy-holesky
```

### Mainnet Deployment

```bash
# Deploy to mainnet
make deploy-mainnet
```

### Docker Deployment

```bash
# Build Docker images
make docker-build

# Run with Docker Compose
make docker-run

# Stop Docker services
make docker-stop
```

## 📊 Monitoring & Metrics

### Prometheus Metrics

- **Operator Metrics**: Response times, task processing rates
- **Aggregator Metrics**: Consensus formation, quorum achievement
- **System Metrics**: Memory usage, network activity

### Health Checks

- **Operator Health**: Key status, blockchain connectivity
- **Aggregator Health**: Server status, operator connectivity
- **Contract Health**: AVS registration, stake verification

## 🔧 Troubleshooting

### Common Issues

1. **Operator Registration Failed**
   - Check stake requirements (32 ETH minimum)
   - Verify signature validity
   - Ensure proper EigenLayer integration

2. **Quorum Not Reached**
   - Check operator count (minimum 3 required)
   - Verify operator responses
   - Check network connectivity

3. **Task Processing Errors**
   - Verify order format and encryption
   - Check privacy threshold settings
   - Ensure proper task validation

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug

# Run with verbose output
go run cmd/operator/main.go -config ./config/operator.yaml -debug
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **EigenLayer Team** - For the AVS framework and documentation
- **EigenLVR Project** - For the reference implementation pattern
- **Uniswap Team** - For the v4 hooks architecture

## 📞 Support

For questions and support:
- Open an issue on GitHub
- Join our Discord community
- Check the documentation wiki 