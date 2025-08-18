#!/bin/bash

# Operator Registration Script for EigenVault
# Registers operators with the AVS after deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🤖 EigenVault Operator Registration${NC}"
echo "===================================="

# Check if deployment environment exists
if [[ ! -f "eigenvault/contracts/deployments.env" ]]; then
    echo -e "${RED}❌ No deployment found. Run deploy-production.sh first.${NC}"
    exit 1
fi

# Source deployment addresses
source eigenvault/contracts/deployments.env

# Check required environment variables
required_vars=("OPERATOR_PRIVATE_KEY" "RPC_URL")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo -e "${RED}❌ Error: $var is not set${NC}"
        exit 1
    fi
done

OPERATOR_ADDRESS=$(cast wallet address --private-key $OPERATOR_PRIVATE_KEY)

echo -e "${YELLOW}📋 Registration Configuration${NC}"
echo "Operator Address: $OPERATOR_ADDRESS"
echo "Service Manager: $EIGENVAULT_SERVICE_MANAGER"
echo "RPC URL: $RPC_URL"

# Check operator balance
balance=$(cast balance $OPERATOR_ADDRESS --rpc-url $RPC_URL)
balance_eth=$(cast to-unit $balance ether)
echo "Operator Balance: $balance_eth ETH"

if (( $(echo "$balance_eth < 0.1" | bc -l) )); then
    echo -e "${RED}⚠️  Low balance. Make sure operator has enough ETH for gas.${NC}"
fi

# Check if operator is already registered
cd eigenvault/contracts
echo -e "${YELLOW}🔍 Checking registration status...${NC}"

is_registered=$(cast call $EIGENVAULT_SERVICE_MANAGER "registeredOperators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL)

if [[ "$is_registered" == "true" ]]; then
    echo -e "${GREEN}✅ Operator is already registered${NC}"
    
    # Get operator metrics
    echo -e "${YELLOW}📊 Operator Metrics:${NC}"
    metrics=$(cast call $EIGENVAULT_SERVICE_MANAGER \
        "getOperatorMetrics(address)" $OPERATOR_ADDRESS \
        --rpc-url $RPC_URL)
    echo "Metrics: $metrics"
    
    exit 0
fi

echo -e "${YELLOW}📝 Registering operator...${NC}"

# Register operator using script
forge script script/RegisterOperator.s.sol:RegisterOperator \
    --rpc-url $RPC_URL \
    --private-key $OPERATOR_PRIVATE_KEY \
    --broadcast \
    -vvvv

# Verify registration
echo -e "${YELLOW}✅ Verifying registration...${NC}"
sleep 5 # Wait for transaction to be mined

is_registered=$(cast call $EIGENVAULT_SERVICE_MANAGER "registeredOperators(address)(bool)" $OPERATOR_ADDRESS --rpc-url $RPC_URL)

if [[ "$is_registered" == "true" ]]; then
    echo -e "${GREEN}🎉 Operator successfully registered!${NC}"
    
    # Get updated operator count
    operator_count=$(cast call $EIGENVAULT_SERVICE_MANAGER "getActiveOperatorsCount()(uint256)" --rpc-url $RPC_URL)
    echo "Total active operators: $operator_count"
    
    # Get operator metrics
    echo -e "${YELLOW}📊 Operator Metrics:${NC}"
    metrics=$(cast call $EIGENVAULT_SERVICE_MANAGER \
        "getOperatorMetrics(address)" $OPERATOR_ADDRESS \
        --rpc-url $RPC_URL)
    echo "Metrics: $metrics"
    
    # Update operator configuration
    echo -e "${YELLOW}⚙️  Updating operator configuration...${NC}"
    cd ../operator
    
    # Create operator config with real addresses
    cat > config.yaml << EOF
# EigenVault Operator Configuration

# Operator Identity
operator:
  address: "$OPERATOR_ADDRESS"
  private_key_file: "keys/operator.key"

# Ethereum Configuration  
ethereum:
  rpc_url: "$RPC_URL"
  chain_id: 17000
  contracts:
    hook: "$EIGENVAULT_HOOK"
    service_manager: "$EIGENVAULT_SERVICE_MANAGER"
    order_vault: "$EIGENVAULT_ORDER_VAULT"

# Matching Configuration
matching:
  max_pending_orders: 1000
  matching_timeout: 300
  min_profit_bps: 10

# Networking Configuration
networking:
  listen_port: 8080
  peer_discovery: true
  max_peers: 50

# Proof Configuration  
proofs:
  circuit_dir: "../circuits/build"
  proving_keys_dir: "../circuits/keys"
  verification_keys_dir: "../circuits/verification"
  proof_timeout: 30

# Performance Configuration
performance:
  worker_threads: 4
  batch_size: 100
  response_timeout: 60

# Security Configuration
security:
  enable_tls: true
  cert_file: "certs/operator.crt"
  key_file: "certs/operator.key"

# Logging Configuration
logging:
  level: "info"
  file: "logs/operator.log"
  max_size: "100MB"
  max_files: 10
EOF
    
    echo -e "${GREEN}✅ Configuration updated${NC}"
    
    echo -e "${GREEN}🎉 Operator registration complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Start the operator: ./scripts/start-operator.sh"
    echo "2. Monitor operator performance: ./scripts/monitor-operator.sh"
    echo "3. Check operator logs: tail -f operator/logs/operator.log"
    
else
    echo -e "${RED}❌ Registration failed!${NC}"
    exit 1
fi