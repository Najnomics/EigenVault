#!/bin/bash

# EigenVault Anvil Deployment Script
# Deploys the complete EigenVault system to local Anvil instance

set -e

echo "🚀 Starting EigenVault Anvil Deployment"
echo "======================================="

# Configuration
ANVIL_HOST="0.0.0.0"
ANVIL_PORT="8545"
ANVIL_CHAIN_ID="31337"
ANVIL_ACCOUNTS="10"
ANVIL_BALANCE="10000"

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is in use
port_in_use() {
    lsof -i :$1 >/dev/null 2>&1
}

# Function to wait for Anvil to be ready
wait_for_anvil() {
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for Anvil to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -X POST -H "Content-Type: application/json" \
           -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
           http://localhost:$ANVIL_PORT >/dev/null 2>&1; then
            print_success "Anvil is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    
    print_error "Anvil failed to start within 30 seconds"
    return 1
}

# Function to kill existing Anvil processes
kill_anvil() {
    print_status "Checking for existing Anvil processes..."
    
    if port_in_use $ANVIL_PORT; then
        print_warning "Port $ANVIL_PORT is in use. Killing existing processes..."
        
        # Kill processes using the port
        lsof -ti:$ANVIL_PORT | xargs kill -9 2>/dev/null || true
        
        # Wait a moment for cleanup
        sleep 2
    fi
}

# Function to start Anvil
start_anvil() {
    print_status "Starting Anvil..."
    
    # Kill any existing Anvil processes
    kill_anvil
    
    # Start Anvil in background
    anvil \
        --host $ANVIL_HOST \
        --port $ANVIL_PORT \
        --chain-id $ANVIL_CHAIN_ID \
        --accounts $ANVIL_ACCOUNTS \
        --balance $ANVIL_BALANCE \
        --block-time 2 \
        --gas-limit 30000000 \
        --gas-price 20000000000 \
        > anvil.log 2>&1 &
    
    ANVIL_PID=$!
    echo $ANVIL_PID > anvil.pid
    
    # Wait for Anvil to be ready
    wait_for_anvil
}

# Function to deploy contracts
deploy_contracts() {
    print_status "Deploying contracts..."
    
    cd eigenvault/contracts
    
    # Deploy OrderVault and test tokens
    print_status "Deploying OrderVault and test tokens..."
    forge script script/DeployOrderVaultOnly.s.sol \
        --rpc-url http://localhost:$ANVIL_PORT \
        --broadcast \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    
    # Deploy full hook system
    print_status "Deploying full hook system..."
    forge script script/DeployWithProperHook.s.sol \
        --rpc-url http://localhost:$ANVIL_PORT \
        --broadcast \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    
    cd ../..
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Check if deployment addresses file exists
    if [ -f "eigenvault/anvil-deployments.env" ]; then
        print_success "Deployment addresses saved to anvil-deployments.env"
        
        # Display deployment addresses
        echo ""
        print_status "Deployment Summary:"
        echo "===================="
        cat eigenvault/anvil-deployments.env | grep -v "^#" | grep -v "^$"
    else
        print_warning "Deployment addresses file not found"
    fi
    
    # Test basic contract functionality
    print_status "Testing basic contract functionality..."
    
    cd eigenvault/contracts
    
    # Run a quick test to verify deployment
    forge test --match-test "test_001_hookPermissions" --rpc-url http://localhost:$ANVIL_PORT
    
    cd ../..
    
    print_success "Basic functionality test passed!"
}

# Function to display network info
display_network_info() {
    print_status "Network Information:"
    echo "===================="
    echo "RPC URL: http://localhost:$ANVIL_PORT"
    echo "Chain ID: $ANVIL_CHAIN_ID"
    echo "Block Explorer: N/A (local)"
    echo ""
    print_status "Pre-funded Accounts:"
    echo "====================="
    echo "Account 0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)"
    echo "Account 1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)"
    echo "Account 2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000 ETH)"
    echo ""
    print_status "Private Keys (for testing only):"
    echo "====================================="
    echo "Account 0: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    echo "Account 1: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
    echo "Account 2: 0x5de4111daa5ba4a5d96dca0d8a70975e8ae67e10c4f7b254cc33099322d31d1a"
}

# Function to cleanup on exit
cleanup() {
    print_status "Cleaning up..."
    
    if [ -f "anvil.pid" ]; then
        ANVIL_PID=$(cat anvil.pid)
        if ps -p $ANVIL_PID > /dev/null; then
            print_status "Stopping Anvil (PID: $ANVIL_PID)..."
            kill $ANVIL_PID
            wait $ANVIL_PID 2>/dev/null || true
        fi
        rm -f anvil.pid
    fi
    
    # Kill any remaining processes on the port
    lsof -ti:$ANVIL_PORT | xargs kill -9 2>/dev/null || true
    
    print_success "Cleanup completed!"
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main execution
main() {
    echo ""
    print_status "EigenVault Anvil Deployment Script"
    print_status "=================================="
    echo ""
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! command_exists forge; then
        print_error "Foundry (forge) not found. Please install Foundry first."
        exit 1
    fi
    
    if ! command_exists anvil; then
        print_error "Anvil not found. Please install Foundry first."
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
    
    # Start Anvil
    start_anvil
    
    # Deploy contracts
    deploy_contracts
    
    # Verify deployment
    verify_deployment
    
    # Display network info
    echo ""
    display_network_info
    
    echo ""
    print_success "🎉 EigenVault deployment completed successfully!"
    print_status "Anvil is running on http://localhost:$ANVIL_PORT"
    print_status "Press Ctrl+C to stop Anvil and exit"
    echo ""
    
    # Keep script running
    while true; do
        sleep 10
    done
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "EigenVault Anvil Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --stop         Stop running Anvil instance"
        echo "  --status       Show deployment status"
        echo "  --clean        Clean up deployment artifacts"
        echo ""
        echo "Examples:"
        echo "  $0             Start deployment"
        echo "  $0 --stop      Stop Anvil"
        echo "  $0 --status    Show status"
        exit 0
        ;;
    --stop)
        print_status "Stopping Anvil..."
        cleanup
        exit 0
        ;;
    --status)
        if [ -f "anvil.pid" ]; then
            ANVIL_PID=$(cat anvil.pid)
            if ps -p $ANVIL_PID > /dev/null; then
                print_success "Anvil is running (PID: $ANVIL_PID)"
                print_status "RPC URL: http://localhost:$ANVIL_PORT"
            else
                print_error "Anvil is not running"
            fi
        else
            print_error "Anvil is not running"
        fi
        exit 0
        ;;
    --clean)
        print_status "Cleaning deployment artifacts..."
        cleanup
        rm -f anvil.log
        rm -f eigenvault/anvil-deployments.env
        print_success "Cleanup completed!"
        exit 0
        ;;
    *)
        main
        ;;
esac
