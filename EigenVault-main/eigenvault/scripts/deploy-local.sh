#!/bin/bash

# EigenVault Local Deployment Script
# This script deploys EigenVault contracts to a local testnet

set -e

echo "🚀 Starting EigenVault local deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NETWORK=${1:-"local"}
RPC_URL=${2:-"http://localhost:8545"}
PRIVATE_KEY=${3:-"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"} # Default Anvil key

echo -e "${YELLOW}Network: $NETWORK${NC}"
echo -e "${YELLOW}RPC URL: $RPC_URL${NC}"

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo -e "${RED}❌ Forge is not installed. Please install Foundry.${NC}"
    exit 1
fi

# Check if anvil is running (for local deployment)
if [ "$NETWORK" == "local" ]; then
    if ! curl -s $RPC_URL > /dev/null; then
        echo -e "${YELLOW}⚠️  Starting local Anvil testnet...${NC}"
        anvil --host 0.0.0.0 --port 8545 &
        ANVIL_PID=$!
        sleep 3
        
        # Cleanup function
        cleanup() {
            echo -e "${YELLOW}🧹 Cleaning up...${NC}"
            kill $ANVIL_PID 2>/dev/null || true
        }
        trap cleanup EXIT
    fi
fi

# Navigate to contracts directory
cd contracts

# Clean and build contracts
echo -e "${YELLOW}🔨 Building contracts...${NC}"
forge clean
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Contract compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Contracts compiled successfully${NC}"

# Run tests
echo -e "${YELLOW}🧪 Running tests...${NC}"
forge test -v

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Tests failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All tests passed${NC}"

# Deploy contracts
echo -e "${YELLOW}📦 Deploying contracts...${NC}"

export DEPLOYER_PRIVATE_KEY=$PRIVATE_KEY

forge script script/DeployEigenVault.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    -v

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Contracts deployed successfully${NC}"

# Extract deployment addresses
DEPLOYMENT_LOG="broadcast/DeployEigenVault.s.sol/$NETWORK/run-latest.json"

if [ -f "$DEPLOYMENT_LOG" ]; then
    echo -e "${YELLOW}📋 Deployment Summary:${NC}"
    
    # Parse deployment addresses using jq if available
    if command -v jq &> /dev/null; then
        echo "Hook Address: $(jq -r '.transactions[] | select(.transactionType == "CREATE") | .contractAddress' $DEPLOYMENT_LOG | head -1)"
        echo "Service Manager: $(jq -r '.transactions[] | select(.transactionType == "CREATE") | .contractAddress' $DEPLOYMENT_LOG | tail -1)"
    else
        echo "Deployment log: $DEPLOYMENT_LOG"
    fi
fi

# Save addresses to env file
echo -e "${YELLOW}💾 Saving deployment addresses...${NC}"
cat > ../.env.local << EOF
# EigenVault Local Deployment Addresses
NETWORK=$NETWORK
RPC_URL=$RPC_URL
DEPLOYED_AT=$(date)

# Contract Addresses (update these after deployment)
EIGENVAULT_HOOK_ADDRESS=0x0000000000000000000000000000000000000000
SERVICE_MANAGER_ADDRESS=0x0000000000000000000000000000000000000000
ORDER_VAULT_ADDRESS=0x0000000000000000000000000000000000000000
POOL_MANAGER_ADDRESS=0x0000000000000000000000000000000000000000
EOF

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "${YELLOW}📝 Next steps:${NC}"
echo "1. Update contract addresses in .env.local"
echo "2. Configure operator settings"
echo "3. Start the operator with: ./scripts/start-operator.sh"
echo "4. Test the frontend with: cd frontend && npm run dev"

if [ "$NETWORK" == "local" ]; then
    echo -e "${YELLOW}ℹ️  Local testnet is running. Press Ctrl+C to stop.${NC}"
    wait
fi