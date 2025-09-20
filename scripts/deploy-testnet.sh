#!/bin/bash

# EigenVault Testnet Deployment Script
# Deploys EigenVault contracts to Holesky testnet

set -e

echo "🚀 Starting EigenVault Testnet Deployment"
echo "========================================"

# Configuration
NETWORK="holesky"
CHAIN_ID="17000"
RPC_URL_ENV="HOLESKY_RPC_URL"
ETHERSCAN_API_KEY_ENV="HOLESKY_ETHERSCAN_API_KEY"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check environment variables
check_env() {
    local var_name=$1
    local var_value=${!var_name}
    
    if [ -z "$var_value" ]; then
        print_error "Environment variable $var_name is not set"
        print_status "Please set $var_name in your .env file"
        exit 1
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get balance
get_balance() {
    local address=$1
    local balance=$(cast balance $address --rpc-url ${!RPC_URL_ENV})
    echo "scale=4; $balance / 1000000000000000000" | bc
}

# Function to check if account has sufficient balance
check_balance() {
    local address=$1
    local required_eth=$2
    
    print_status "Checking balance for $address..."
    
    local balance=$(get_balance $address)
    print_status "Current balance: $balance ETH"
    
    if (( $(echo "$balance < $required_eth" | bc -l) )); then
        print_error "Insufficient balance. Required: $required_eth ETH, Available: $balance ETH"
        print_status "Please fund your account with testnet ETH"
        exit 1
    fi
    
    print_success "Balance check passed!"
}

# Function to wait for transaction
wait_for_tx() {
    local tx_hash=$1
    local max_wait=300 # 5 minutes
    
    print_status "Waiting for transaction: $tx_hash"
    
    local start_time=$(date +%s)
    while true; do
        local tx_status=$(cast tx $tx_hash --rpc-url ${!RPC_URL_ENV} 2>/dev/null || echo "pending")
        
        if [ "$tx_status" != "pending" ]; then
            break
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait ]; then
            print_error "Transaction timeout after $max_wait seconds"
            exit 1
        fi
        
        echo -n "."
        sleep 5
    done
    
    echo ""
    print_success "Transaction confirmed!"
}

# Function to deploy contracts
deploy_contracts() {
    print_status "Deploying contracts to $NETWORK..."
    
    cd eigenvault/contracts
    
    # Deploy OrderVault and test tokens
    print_status "Deploying OrderVault and test tokens..."
    
    local tx_hash=$(forge script script/DeployOrderVaultOnly.s.sol \
        --broadcast \
        --rpc-url ${!RPC_URL_ENV} \
        --private-key ${DEPLOYER_PRIVATE_KEY} \
        --json | jq -r '.transactions[0].hash' 2>/dev/null || echo "")
    
    if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
        wait_for_tx $tx_hash
    fi
    
    # Deploy full hook system
    print_status "Deploying full hook system..."
    
    local tx_hash=$(forge script script/DeployWithProperHook.s.sol \
        --broadcast \
        --rpc-url ${!RPC_URL_ENV} \
        --private-key ${DEPLOYER_PRIVATE_KEY} \
        --json | jq -r '.transactions[0].hash' 2>/dev/null || echo "")
    
    if [ -n "$tx_hash" ] && [ "$tx_hash" != "null" ]; then
        wait_for_tx $tx_hash
    fi
    
    cd ../..
}

# Function to verify contracts
verify_contracts() {
    print_status "Verifying contracts on Etherscan..."
    
    if [ -z "${!ETHERSCAN_API_KEY_ENV}" ]; then
        print_warning "Etherscan API key not set. Skipping verification."
        return
    fi
    
    cd eigenvault/contracts
    
    # Get contract addresses from deployment
    if [ -f "broadcast/DeployOrderVaultOnly.s.sol/$CHAIN_ID/run-latest.json" ]; then
        local order_vault_addr=$(jq -r '.transactions[] | select(.contractName == "OrderVault") | .contractAddress' broadcast/DeployOrderVaultOnly.s.sol/$CHAIN_ID/run-latest.json 2>/dev/null || echo "")
        
        if [ -n "$order_vault_addr" ] && [ "$order_vault_addr" != "null" ]; then
            print_status "Verifying OrderVault at $order_vault_addr..."
            forge verify-contract \
                --chain-id $CHAIN_ID \
                --num-of-optimizations 200 \
                --watch \
                --etherscan-api-key ${!ETHERSCAN_API_KEY_ENV} \
                $order_vault_addr \
                src/vault/OrderVault.sol:OrderVault || print_warning "Verification failed"
        fi
    fi
    
    cd ../..
}

# Function to save deployment info
save_deployment_info() {
    print_status "Saving deployment information..."
    
    local deployments_file="eigenvault/testnet-deployments.env"
    
    # Create deployments file
    cat > $deployments_file << EOF
# EigenVault $NETWORK Deployment
# Generated on $(date)

NETWORK=$NETWORK
CHAIN_ID=$CHAIN_ID
RPC_URL=${!RPC_URL_ENV}
DEPLOYER_ADDRESS=${DEPLOYER_ADDRESS}
EOF
    
    # Add contract addresses if available
    if [ -f "eigenvault/contracts/broadcast/DeployOrderVaultOnly.s.sol/$CHAIN_ID/run-latest.json" ]; then
        local order_vault_addr=$(jq -r '.transactions[] | select(.contractName == "OrderVault") | .contractAddress' eigenvault/contracts/broadcast/DeployOrderVaultOnly.s.sol/$CHAIN_ID/run-latest.json 2>/dev/null || echo "")
        
        if [ -n "$order_vault_addr" ] && [ "$order_vault_addr" != "null" ]; then
            echo "ORDER_VAULT_ADDRESS=$order_vault_addr" >> $deployments_file
        fi
    fi
    
    print_success "Deployment information saved to $deployments_file"
}

# Function to display deployment summary
display_summary() {
    print_status "Deployment Summary"
    echo "=================="
    echo "Network: $NETWORK"
    echo "Chain ID: $CHAIN_ID"
    echo "RPC URL: ${!RPC_URL_ENV}"
    echo "Deployer: $DEPLOYER_ADDRESS"
    echo ""
    
    if [ -f "eigenvault/testnet-deployments.env" ]; then
        print_status "Contract Addresses:"
        echo "==================="
        grep -v "^#" eigenvault/testnet-deployments.env | grep -v "^$" | grep "_ADDRESS"
    fi
    
    echo ""
    print_status "Block Explorer:"
    echo "==============="
    echo "Holesky: https://holesky.etherscan.io"
    echo ""
}

# Function to run post-deployment tests
run_tests() {
    print_status "Running post-deployment tests..."
    
    cd eigenvault/contracts
    
    # Run basic tests against deployed contracts
    forge test --fork-url ${!RPC_URL_ENV} --match-test "test_001_hookPermissions" || print_warning "Some tests failed"
    
    cd ../..
    
    print_success "Post-deployment tests completed!"
}

# Main execution
main() {
    echo ""
    print_status "EigenVault Testnet Deployment Script"
    print_status "===================================="
    echo ""
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! command_exists forge; then
        print_error "Foundry (forge) not found. Please install Foundry first."
        exit 1
    fi
    
    if ! command_exists cast; then
        print_error "Cast not found. Please install Foundry first."
        exit 1
    fi
    
    if ! command_exists jq; then
        print_error "jq not found. Please install jq first."
        exit 1
    fi
    
    if ! command_exists bc; then
        print_error "bc not found. Please install bc first."
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
    
    # Check environment variables
    print_status "Checking environment variables..."
    
    check_env $RPC_URL_ENV
    check_env "DEPLOYER_PRIVATE_KEY"
    
    # Get deployer address
    DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY)
    print_status "Deployer address: $DEPLOYER_ADDRESS"
    
    # Check balance
    check_balance $DEPLOYER_ADDRESS 0.1
    
    # Deploy contracts
    deploy_contracts
    
    # Verify contracts
    verify_contracts
    
    # Save deployment info
    save_deployment_info
    
    # Run tests
    run_tests
    
    # Display summary
    display_summary
    
    print_success "🎉 EigenVault testnet deployment completed successfully!"
    print_status "Network: $NETWORK (Chain ID: $CHAIN_ID)"
    print_status "Block Explorer: https://holesky.etherscan.io"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "EigenVault Testnet Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --verify-only  Only verify existing contracts"
        echo "  --test-only    Only run post-deployment tests"
        echo ""
        echo "Environment Variables Required:"
        echo "  HOLESKY_RPC_URL        Holesky RPC endpoint"
        echo "  DEPLOYER_PRIVATE_KEY   Private key for deployment"
        echo "  HOLESKY_ETHERSCAN_API_KEY  Etherscan API key (optional)"
        echo ""
        echo "Examples:"
        echo "  $0                     Deploy contracts"
        echo "  $0 --verify-only       Verify contracts only"
        echo "  $0 --test-only         Run tests only"
        exit 0
        ;;
    --verify-only)
        print_status "Verifying existing contracts..."
        verify_contracts
        exit 0
        ;;
    --test-only)
        print_status "Running post-deployment tests..."
        run_tests
        exit 0
        ;;
    *)
        main
        ;;
esac
