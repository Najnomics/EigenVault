# EigenVault Deployment Guide

## Overview

This guide covers the complete deployment process for EigenVault, including smart contracts, AVS operators, and supporting infrastructure.

## Prerequisites

### Required Tools
- **Foundry**: Latest version for smart contract deployment
- **Node.js**: 18+ for frontend and tooling
- **Docker**: For containerized deployments
- **EigenLayer CLI**: For AVS operations
- **Go**: 1.21+ for operator development

### Environment Setup
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install EigenLayer CLI
go install github.com/Layr-Labs/eigenlayer-cli@latest

# Install Node.js dependencies
npm install
```

## Environment Configuration

### Environment Variables

Create `.env` files with the following variables:

```bash
# Network Configuration
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
HOLESKY_RPC_URL=https://holesky.infura.io/v3/YOUR_KEY
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY

# Deployment Keys
DEPLOYER_PRIVATE_KEY=0x...
OPERATOR_PRIVATE_KEY=0x...

# EigenLayer Configuration
EIGENLAYER_RPC_URL=https://holesky.eigenda.xyz
EIGENLAYER_OPERATOR_ADDRESS=0x...

# Etherscan Verification
ETHERSCAN_API_KEY=YOUR_KEY

# AVS Configuration
AVS_NAME=EigenVault
AVS_METADATA_URI=https://your-domain.com/metadata.json
```

## Deployment Scripts

### Available Scripts

1. **DeployOrderVaultOnly.s.sol**: Deploy core OrderVault contract
2. **DeployWithProperHook.s.sol**: Deploy complete hook system
3. **RegisterOperator.s.sol**: Register AVS operators

### Script Usage

```bash
# Deploy to Anvil (local development)
forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to Holesky testnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $HOLESKY_RPC_URL

# Deploy to mainnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $MAINNET_RPC_URL

# Deploy with verification
forge script script/DeployOrderVaultOnly.s.sol --broadcast --verify --rpc-url $HOLESKY_RPC_URL
```

## Deployment Environments

### 1. Local Development (Anvil)

#### Setup
```bash
# Start Anvil
anvil --host 0.0.0.0 --port 8545 --accounts 10 --balance 10000

# Deploy contracts
forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Configuration
- **Chain ID**: 31337
- **RPC URL**: http://localhost:8545
- **Pre-funded accounts**: 10 accounts with 10,000 ETH each

#### Verification
```bash
# Check deployment
cast call <CONTRACT_ADDRESS> "totalOrders()" --rpc-url http://localhost:8545

# Verify contract code
cast code <CONTRACT_ADDRESS> --rpc-url http://localhost:8545
```

### 2. Testnet Deployment (Holesky)

#### Prerequisites
- Holesky ETH for gas fees
- EigenLayer testnet registration
- Etherscan API key for verification

#### Deployment Steps
```bash
# 1. Deploy contracts
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $HOLESKY_RPC_URL

# 2. Verify contracts
forge verify-contract --chain-id 17000 --num-of-optimizations 200 --watch --etherscan-api-key $ETHERSCAN_API_KEY <CONTRACT_ADDRESS> src/hooks/EigenVaultHook.sol:EigenVaultHook

# 3. Register with EigenLayer
eigenlayer-cli register-avs --rpc-url $EIGENLAYER_RPC_URL --private-key $OPERATOR_PRIVATE_KEY
```

#### Post-Deployment
```bash
# Register operators
forge script script/RegisterOperator.s.sol --broadcast --rpc-url $HOLESKY_RPC_URL

# Test functionality
forge test --fork-url $HOLESKY_RPC_URL
```

### 3. Production Deployment (Mainnet)

#### Prerequisites
- Sufficient ETH for deployment and gas
- EigenLayer mainnet registration
- Comprehensive testing on testnet
- Security audit completion

#### Deployment Steps
```bash
# 1. Final testnet validation
forge test --fork-url $HOLESKY_RPC_URL --gas-report

# 2. Deploy to mainnet
forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $MAINNET_RPC_URL

# 3. Verify contracts
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --etherscan-api-key $ETHERSCAN_API_KEY <CONTRACT_ADDRESS> src/hooks/EigenVaultHook.sol:EigenVaultHook

# 4. Register with EigenLayer
eigenlayer-cli register-avs --rpc-url https://api.eigenlayer.xyz --private-key $OPERATOR_PRIVATE_KEY
```

#### Production Checklist
- [ ] Contracts deployed successfully
- [ ] Contracts verified on Etherscan
- [ ] AVS registered with EigenLayer
- [ ] Operators registered and staked
- [ ] Monitoring and alerting configured
- [ ] Emergency procedures documented

## AVS Operator Deployment

### Operator Setup

#### Prerequisites
- Go 1.21+
- EigenLayer operator registration
- Sufficient stake (minimum 32 ETH)

#### Installation
```bash
# Clone operator repository
git clone https://github.com/your-org/eigenvault-operator
cd eigenvault-operator

# Build operator
go build -o eigenvault-operator ./cmd/operator

# Generate keys
./eigenvault-operator keygen --output ./keys
```

#### Configuration
```yaml
# config.yaml
ethereum:
  rpc_url: "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
  operator_address: "0x..."
  private_key: "0x..."
  service_manager_address: "0x..."
  gas_limit: 500000
  gas_price: 20000000000

matching:
  max_pending_orders: 1000
  matching_interval_ms: 100
  price_tolerance_bps: 10
  max_slippage_bps: 50

networking:
  listen_port: 9000
  bootstrap_peers: []
  min_peers: 1
  max_peers: 10

proofs:
  circuit_path: "./circuits/build"
  proving_key_path: "./circuits/build/order_matching_final.zkey"
  max_proof_size: 1048576
  proof_timeout_seconds: 300
```

#### Deployment
```bash
# Start operator
./eigenvault-operator start --config config.yaml

# Or use Docker
docker run -d --name eigenvault-operator \
  -v $(pwd)/config.yaml:/app/config.yaml \
  -v $(pwd)/keys:/app/keys \
  eigenvault-operator:latest
```

### Docker Deployment

#### Docker Compose Setup
```yaml
# docker-compose.yml
version: '3.8'
services:
  eigenvault-operator:
    build: ./operator
    environment:
      - CONFIG_PATH=/app/config.yaml
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./keys:/app/keys
    ports:
      - "9000:9000"
    restart: unless-stopped

  monitoring:
    image: prometheus/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus/config:/etc/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
```

#### Deployment Commands
```bash
# Build and start services
docker-compose up -d

# View logs
docker-compose logs -f eigenvault-operator

# Stop services
docker-compose down
```

## Monitoring & Observability

### Metrics Collection

#### Prometheus Configuration
```yaml
# monitoring/prometheus/config/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'eigenvault-operator'
    static_configs:
      - targets: ['eigenvault-operator:9000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'ethereum-node'
    static_configs:
      - targets: ['eth-mainnet.g.alchemy.com:443']
```

#### Grafana Dashboards
- **Operator Performance**: Response times, success rates
- **Order Processing**: Order volume, matching efficiency
- **System Health**: Memory usage, CPU utilization
- **Security Metrics**: Slashing events, stake changes

### Alerting

#### Critical Alerts
- **Operator Offline**: No heartbeat for 5 minutes
- **High Error Rate**: >5% error rate in 10 minutes
- **Stake At Risk**: Slashing conditions triggered
- **System Overload**: High memory or CPU usage

#### Alert Configuration
```yaml
# monitoring/grafana/alerts.yml
groups:
  - name: eigenvault
    rules:
      - alert: OperatorOffline
        expr: up{job="eigenvault-operator"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "EigenVault operator is offline"
          
      - alert: HighErrorRate
        expr: rate(operator_errors_total[10m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
```

## Security Considerations

### Key Management
- **Private Keys**: Store in secure key management systems
- **Access Control**: Limit access to production keys
- **Rotation**: Regular key rotation procedures
- **Backup**: Secure backup of critical keys

### Network Security
- **Firewall**: Restrict access to operator ports
- **TLS**: Use TLS for all network communications
- **VPN**: Secure operator-to-operator communications
- **DDoS Protection**: Implement DDoS mitigation

### Operational Security
- **Monitoring**: Continuous monitoring of all systems
- **Incident Response**: Documented incident response procedures
- **Access Logs**: Comprehensive access logging
- **Audit Trails**: Complete audit trails for all operations

## Troubleshooting

### Common Issues

#### Deployment Failures
```bash
# Check gas limits
forge script script/DeployOrderVaultOnly.s.sol --rpc-url $RPC_URL --gas-limit 10000000

# Check RPC connectivity
curl -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL

# Verify private key
cast wallet address $DEPLOYER_PRIVATE_KEY
```

#### Operator Issues
```bash
# Check operator status
curl http://localhost:9000/health

# View operator logs
docker logs eigenvault-operator

# Restart operator
docker restart eigenvault-operator
```

#### Contract Issues
```bash
# Check contract state
cast call <CONTRACT_ADDRESS> "totalOrders()" --rpc-url $RPC_URL

# Verify contract code
cast code <CONTRACT_ADDRESS> --rpc-url $RPC_URL

# Check transaction status
cast tx <TX_HASH> --rpc-url $RPC_URL
```

### Support Resources

- **Documentation**: [docs.eigenvault.com](https://docs.eigenvault.com)
- **Discord**: [discord.gg/eigenvault](https://discord.gg/eigenvault)
- **GitHub Issues**: [github.com/your-org/eigenvault/issues](https://github.com/your-org/eigenvault/issues)
- **Emergency Contact**: emergency@eigenvault.com
