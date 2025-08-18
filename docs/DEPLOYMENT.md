# EigenVault Deployment Guide

This guide covers the deployment process for EigenVault components across different environments.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ or equivalent Linux distribution
- **CPU**: 4 cores minimum, 8 cores recommended
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 100GB SSD minimum
- **Network**: Static IP address, 10 Mbps minimum bandwidth

### Software Dependencies
```bash
# Install Docker and Docker Compose
sudo apt update
sudo apt install docker.io docker-compose-plugin

# Install Node.js and Yarn
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install nodejs
npm install -g yarn

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install Foundry (for smart contracts)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Environment Setup

### 1. Development Environment

#### Clone Repository
```bash
git clone https://github.com/Najnomics/EigenVault.git
cd EigenVault
```

#### Install Dependencies
```bash
# Install circuit dependencies
cd circuits
npm install circomlib
./scripts/setup.sh
cd ..

# Install operator dependencies
cd eigenvault/operator
cargo build
cd ../..

# Install frontend dependencies
cd frontend
yarn install
cd ..
```

#### Configure Environment Variables
```bash
# Copy example environment files
cp .env.example .env
cp eigenvault/operator/config.example.yaml eigenvault/operator/config.yaml
cp frontend/.env.example frontend/.env

# Edit configuration files with your values
nano .env
nano eigenvault/operator/config.yaml
nano frontend/.env
```

#### Generate Operator Keys
```bash
cd eigenvault/operator
cargo run -- keygen --output keys/
# Securely store the generated keys
cd ../..
```

### 2. Production Environment

#### Server Setup
```bash
# Create dedicated user
sudo useradd -m -s /bin/bash eigenvault
sudo usermod -aG docker eigenvault

# Create directory structure
sudo mkdir -p /opt/eigenvault/{keys,logs,data,config}
sudo chown -R eigenvault:eigenvault /opt/eigenvault

# Switch to eigenvault user
sudo -u eigenvault -i
```

#### Configuration Management
```bash
# Production configuration
cd /opt/eigenvault
git clone https://github.com/Najnomics/EigenVault.git .

# Set up production environment files
cp .env.production .env
cp eigenvault/operator/config.production.yaml eigenvault/operator/config.yaml

# Configure with production values
nano .env
nano eigenvault/operator/config.yaml
```

## Smart Contract Deployment

### 1. Local Development (Anvil)
```bash
# Start local Ethereum node
anvil --host 0.0.0.0 --port 8545

# Deploy contracts
cd eigenvault/contracts
forge script script/DeployEigenVault.s.sol --rpc-url http://localhost:8545 --private-key 0x... --broadcast

# Verify deployment
forge verify-contract <CONTRACT_ADDRESS> src/SimplifiedEigenVaultHook.sol:SimplifiedEigenVaultHook --rpc-url http://localhost:8545
```

### 2. Testnet Deployment (Holesky)
```bash
# Set environment variables
export PRIVATE_KEY="0x..."
export RPC_URL="https://holesky.infura.io/v3/YOUR_PROJECT_ID"
export ETHERSCAN_API_KEY="YOUR_API_KEY"

# Deploy to testnet
cd eigenvault/contracts
forge script script/DeployEigenVault.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 3. Mainnet Deployment
```bash
# Use hardware wallet for mainnet deployment
forge script script/DeployEigenVault.s.sol \
  --rpc-url https://mainnet.infura.io/v3/YOUR_PROJECT_ID \
  --ledger \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## Operator Deployment

### 1. Manual Deployment
```bash
# Build operator
cd eigenvault/operator
cargo build --release

# Generate keys
./target/release/eigenvault-operator keygen --output /opt/eigenvault/keys/

# Initialize configuration
./target/release/eigenvault-operator init --config /opt/eigenvault/config.yaml

# Register with EigenLayer
./target/release/eigenvault-operator register --config /opt/eigenvault/config.yaml

# Start operator
./target/release/eigenvault-operator start --config /opt/eigenvault/config.yaml
```

### 2. Docker Deployment
```bash
# Build Docker image
docker build -f docker/operator.Dockerfile -t eigenvault-operator .

# Run operator container
docker run -d \
  --name eigenvault-operator \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /opt/eigenvault/keys:/app/keys:ro \
  -v /opt/eigenvault/config.yaml:/app/config.yaml:ro \
  -v /opt/eigenvault/logs:/app/logs \
  eigenvault-operator
```

### 3. Docker Compose Deployment
```bash
# Set up environment
cp docker/.env.example docker/.env
nano docker/.env

# Start all services
cd docker
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs eigenvault-operator
```

## Frontend Deployment

### 1. Development Server
```bash
cd frontend
yarn start
# Accessible at http://localhost:3000
```

### 2. Production Build
```bash
cd frontend
yarn build

# Serve with nginx
sudo apt install nginx
sudo cp -r build/* /var/www/html/
sudo systemctl restart nginx
```

### 3. Docker Deployment
```bash
# Build and run frontend container
docker build -f docker/frontend.Dockerfile -t eigenvault-frontend .
docker run -d --name eigenvault-frontend -p 3000:80 eigenvault-frontend
```

## Zero-Knowledge Circuit Setup

### 1. Circuit Compilation
```bash
cd circuits
./scripts/setup.sh
./scripts/compile.sh
./scripts/generate_proof.sh
```

### 2. Key Generation (Production)
```bash
# Generate production proving keys
cd circuits
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v

# Generate circuit-specific keys
snarkjs groth16 setup order_matching.r1cs pot12_final.ptau order_matching_0000.zkey
snarkjs zkey contribute order_matching_0000.zkey order_matching_final.zkey --name="Production contribution" -v
snarkjs zkey export verificationkey order_matching_final.zkey order_matching_vkey.json
```

## Monitoring Setup

### 1. Prometheus Configuration
```bash
# Start Prometheus
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v /opt/eigenvault/monitoring/prometheus:/etc/prometheus \
  prom/prometheus
```

### 2. Grafana Setup
```bash
# Start Grafana
docker run -d \
  --name grafana \
  -p 3001:3000 \
  -v grafana-storage:/var/lib/grafana \
  grafana/grafana

# Import dashboards
# Navigate to http://localhost:3001
# Login with admin/admin
# Import dashboard from monitoring/grafana/dashboards/
```

## Security Hardening

### 1. Firewall Configuration
```bash
# Configure UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 9000  # Operator P2P
sudo ufw allow 80    # HTTP
sudo ufw allow 443   # HTTPS
sudo ufw enable
```

### 2. SSL/TLS Setup
```bash
# Install Certbot
sudo apt install certbot

# Generate certificates
sudo certbot certonly --standalone -d your-domain.com

# Configure nginx with SSL
sudo nano /etc/nginx/sites-available/eigenvault
```

### 3. Key Management
```bash
# Secure key storage
chmod 600 /opt/eigenvault/keys/*.txt
chown eigenvault:eigenvault /opt/eigenvault/keys/*

# Consider using hardware security modules (HSM) for production
```

## Health Checks and Monitoring

### 1. Service Health Checks
```bash
# Check operator status
curl http://localhost:9000/health

# Check logs
tail -f /opt/eigenvault/logs/operator.log

# Monitor resources
htop
df -h
```

### 2. Automated Monitoring
```bash
# Set up log rotation
sudo nano /etc/logrotate.d/eigenvault

# Configure systemd service
sudo nano /etc/systemd/system/eigenvault-operator.service
sudo systemctl enable eigenvault-operator
sudo systemctl start eigenvault-operator
```

## Backup and Recovery

### 1. Key Backup
```bash
# Create encrypted backup of keys
tar -czf keys-backup.tar.gz /opt/eigenvault/keys/
gpg --symmetric --cipher-algo AES256 keys-backup.tar.gz
rm keys-backup.tar.gz

# Store encrypted backup securely offsite
```

### 2. Configuration Backup
```bash
# Backup configuration
cp /opt/eigenvault/config.yaml config-backup-$(date +%Y%m%d).yaml

# Version control for configuration
cd /opt/eigenvault
git add config.yaml
git commit -m "Update configuration"
git push origin main
```

## Troubleshooting

### Common Issues

#### Operator Not Starting
```bash
# Check configuration
eigenvault-operator validate --config config.yaml

# Check logs
tail -f logs/operator.log

# Verify key permissions
ls -la keys/
```

#### Network Connectivity Issues
```bash
# Test RPC connection
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC_URL

# Test P2P connectivity
telnet <peer-ip> 9000
```

#### Contract Deployment Failures
```bash
# Check gas price
forge script script/DeployEigenVault.s.sol --rpc-url $RPC_URL --gas-estimate

# Verify account balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL
```

### Recovery Procedures

#### Operator Recovery
```bash
# Stop operator
docker-compose stop eigenvault-operator

# Restore from backup
gpg --decrypt keys-backup.tar.gz.gpg | tar -xzf -

# Restart with clean state
docker-compose up -d eigenvault-operator
```

#### Database Recovery
```bash
# Backup current state
docker exec mongodb mongodump --out /backup/

# Restore from backup
docker exec mongodb mongorestore /backup/
```

This deployment guide ensures a secure and reliable EigenVault installation across various environments.