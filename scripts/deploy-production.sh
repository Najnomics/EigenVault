#!/bin/bash

# Production Deployment Script for EigenVault
# This script deploys EigenVault to production networks with proper verification

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 EigenVault Production Deployment${NC}"
echo "=================================="

# Check if required environment variables are set
required_vars=("DEPLOYER_PRIVATE_KEY" "RPC_URL" "ETHERSCAN_API_KEY")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo -e "${RED}❌ Error: $var is not set${NC}"
        exit 1
    fi
done

# Get network from first argument or prompt user
NETWORK=${1:-""}
if [[ -z "$NETWORK" ]]; then
    echo "Available networks:"
    echo "1. holesky (Holesky Testnet)"
    echo "2. unichain (Unichain Sepolia)"
    echo "3. mainnet (Ethereum Mainnet - BE CAREFUL!)"
    read -p "Select network (1-3): " choice
    case $choice in
        1) NETWORK="holesky" ;;
        2) NETWORK="unichain" ;;
        3) NETWORK="mainnet" ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
fi

echo -e "${YELLOW}📋 Deployment Configuration${NC}"
echo "Network: $NETWORK"
echo "RPC URL: $RPC_URL"
echo "Deployer: $(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY)"

# Confirm deployment
read -p "Do you want to proceed with deployment? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Change to contracts directory
cd eigenvault/contracts

# Install dependencies
echo -e "${YELLOW}📦 Installing dependencies...${NC}"
forge install

# Compile contracts
echo -e "${YELLOW}🔨 Compiling contracts...${NC}"
forge build

# Run tests before deployment
echo -e "${YELLOW}🧪 Running tests...${NC}"
forge test -vv

# Deploy contracts
echo -e "${YELLOW}🚀 Deploying contracts...${NC}"

if [[ "$NETWORK" == "holesky" ]]; then
    RPC_URL="https://ethereum-holesky-rpc.publicnode.com"
    ETHERSCAN_URL="https://holesky.etherscan.io"
elif [[ "$NETWORK" == "unichain" ]]; then
    RPC_URL="https://sepolia.unichain.org"
    ETHERSCAN_URL="https://unichain-sepolia.blockscout.com"
elif [[ "$NETWORK" == "mainnet" ]]; then
    RPC_URL="$MAINNET_RPC_URL"
    ETHERSCAN_URL="https://etherscan.io"
    echo -e "${RED}⚠️  DEPLOYING TO MAINNET - DOUBLE CHECK EVERYTHING!${NC}"
    read -p "Type 'MAINNET' to confirm: " mainnet_confirm
    if [[ $mainnet_confirm != "MAINNET" ]]; then
        echo "Mainnet deployment cancelled"
        exit 0
    fi
fi

# Deploy and verify contracts
forge script script/DeployEigenVault.s.sol:DeployEigenVault \
    --rpc-url $RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv

# Check if deployment was successful
if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    
    # Source the deployment addresses
    if [[ -f "deployments.env" ]]; then
        source deployments.env
        echo -e "${GREEN}📄 Deployment Summary:${NC}"
        echo "Order Vault: $EIGENVAULT_ORDER_VAULT"
        echo "Service Manager: $EIGENVAULT_SERVICE_MANAGER" 
        echo "Hook: $EIGENVAULT_HOOK"
        echo ""
        echo -e "${GREEN}🔗 Etherscan Links:${NC}"
        echo "Order Vault: $ETHERSCAN_URL/address/$EIGENVAULT_ORDER_VAULT"
        echo "Service Manager: $ETHERSCAN_URL/address/$EIGENVAULT_SERVICE_MANAGER"
        echo "Hook: $ETHERSCAN_URL/address/$EIGENVAULT_HOOK"
    fi
    
    # Copy ABIs to frontend
    echo -e "${YELLOW}📋 Copying ABIs to frontend...${NC}"
    mkdir -p ../../frontend/src/contracts
    cp out/EigenVaultHook.sol/EigenVaultHook.json ../../frontend/src/contracts/
    cp out/OrderVault.sol/OrderVault.json ../../frontend/src/contracts/
    cp out/EigenVaultServiceManager.sol/EigenVaultServiceManager.json ../../frontend/src/contracts/
    
    # Update frontend environment file
    echo -e "${YELLOW}🔧 Updating frontend environment...${NC}"
    if [[ -f "deployments.env" ]]; then
        cp deployments.env ../../frontend/.env.local
        echo "REACT_APP_NETWORK=$NETWORK" >> ../../frontend/.env.local
        echo "REACT_APP_RPC_URL=$RPC_URL" >> ../../frontend/.env.local
    fi
    
    # Build and start operator
    echo -e "${YELLOW}🤖 Building operator...${NC}"
    cd ../operator
    cargo build --release
    
    # Generate operator configuration
    echo -e "${YELLOW}⚙️  Generating operator configuration...${NC}"
    cp config.example.yaml config.yaml
    
    echo -e "${GREEN}🎉 Deployment Complete!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Register operators with: ./scripts/register-operators.sh"
    echo "2. Start operator with: ./scripts/start-operator.sh" 
    echo "3. Start frontend with: cd frontend && npm start"
    echo "4. Monitor system with: ./scripts/monitor-system.sh"
    
else
    echo -e "${RED}❌ Deployment failed!${NC}"
    exit 1
fi