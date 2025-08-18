#!/bin/bash

# EigenVault Local Deployment Script
# This script sets up a complete local development environment

set -e

echo "EigenVault Local Deployment Script"
echo "=================================="

# Configuration
PROJECT_ROOT="$(dirname "$0")/.."
BUILD_DIR="$PROJECT_ROOT/build"
LOGS_DIR="$PROJECT_ROOT/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    commands=("node" "yarn" "cargo" "anvil" "forge")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed"
            exit 1
        fi
    done
    
    log_success "All prerequisites are installed"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p "$BUILD_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$PROJECT_ROOT/keys"
    mkdir -p "$PROJECT_ROOT/data"
    
    log_success "Directory structure created"
}

# Start local Ethereum node
start_ethereum_node() {
    log_info "Starting local Ethereum node..."
    
    # Kill any existing anvil process
    pkill anvil || true
    
    # Start anvil in background
    anvil \
        --host 0.0.0.0 \
        --port 8545 \
        --block-time 2 \
        --accounts 10 \
        --balance 10000 \
        > "$LOGS_DIR/anvil.log" 2>&1 &
    
    ANVIL_PID=$!
    echo $ANVIL_PID > "$BUILD_DIR/anvil.pid"
    
    # Wait for anvil to start
    sleep 3
    
    # Test connection
    if curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 > /dev/null; then
        log_success "Local Ethereum node started (PID: $ANVIL_PID)"
    else
        log_error "Failed to start local Ethereum node"
        exit 1
    fi
}

# Deploy smart contracts
deploy_contracts() {
    log_info "Deploying smart contracts..."
    
    cd "$PROJECT_ROOT/eigenvault/contracts"
    
    # Install dependencies
    forge install
    
    # Compile contracts
    forge build
    
    # Deploy contracts
    forge script script/DeployEigenVault.s.sol \
        --rpc-url http://localhost:8545 \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --broadcast \
        > "$LOGS_DIR/contract-deployment.log" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Smart contracts deployed successfully"
        
        # Extract contract addresses from logs
        SERVICE_MANAGER=$(grep "ServiceManager deployed at" "$LOGS_DIR/contract-deployment.log" | cut -d' ' -f4)
        HOOK_ADDRESS=$(grep "EigenVaultHook deployed at" "$LOGS_DIR/contract-deployment.log" | cut -d' ' -f4)
        VAULT_ADDRESS=$(grep "OrderVault deployed at" "$LOGS_DIR/contract-deployment.log" | cut -d' ' -f4)
        
        # Save addresses to environment file
        cat > "$BUILD_DIR/contract-addresses.env" <<EOF
SERVICE_MANAGER_ADDRESS=$SERVICE_MANAGER
EIGENVAULT_HOOK_ADDRESS=$HOOK_ADDRESS
ORDER_VAULT_ADDRESS=$VAULT_ADDRESS
EOF
        
        log_info "Contract addresses saved to $BUILD_DIR/contract-addresses.env"
    else
        log_error "Failed to deploy smart contracts"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Compile ZK circuits
compile_circuits() {
    log_info "Compiling ZK circuits..."
    
    cd "$PROJECT_ROOT/circuits"
    
    # Install dependencies
    if [ ! -d "node_modules" ]; then
        npm install
    fi
    
    # Run setup and compilation
    ./scripts/setup.sh > "$LOGS_DIR/circuit-setup.log" 2>&1
    ./scripts/compile.sh > "$LOGS_DIR/circuit-compile.log" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "ZK circuits compiled successfully"
    else
        log_error "Failed to compile ZK circuits"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Build operator
build_operator() {
    log_info "Building operator..."
    
    cd "$PROJECT_ROOT/eigenvault/operator"
    
    # Build in release mode
    cargo build --release > "$LOGS_DIR/operator-build.log" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Operator built successfully"
    else
        log_error "Failed to build operator"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Generate operator keys
generate_operator_keys() {
    log_info "Generating operator keys..."
    
    cd "$PROJECT_ROOT/eigenvault/operator"
    
    # Generate keys
    ./target/release/eigenvault-operator keygen \
        --output "$PROJECT_ROOT/keys" \
        > "$LOGS_DIR/keygen.log" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Operator keys generated"
        log_info "Keys saved to $PROJECT_ROOT/keys/"
        log_warning "Please secure these keys - they are critical for operator functionality"
    else
        log_error "Failed to generate operator keys"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Configure operator
configure_operator() {
    log_info "Configuring operator..."
    
    # Source contract addresses
    source "$BUILD_DIR/contract-addresses.env"
    
    # Get operator address from keys
    OPERATOR_ADDRESS=$(cat "$PROJECT_ROOT/keys/ethereum_address.txt")
    OPERATOR_PRIVATE_KEY=$(cat "$PROJECT_ROOT/keys/ethereum_private_key.txt")
    
    # Create operator configuration
    cat > "$PROJECT_ROOT/eigenvault/operator/config.yaml" <<EOF
ethereum:
  rpc_url: "http://localhost:8545"
  operator_address: "$OPERATOR_ADDRESS"
  private_key: "$OPERATOR_PRIVATE_KEY"
  service_manager_address: "$SERVICE_MANAGER_ADDRESS"
  eigenvault_hook_address: "$HOOK_ADDRESS"
  order_vault_address: "$VAULT_ADDRESS"
  gas_limit: 500000
  gas_price: 20000000000
  confirmation_blocks: 1

matching:
  max_pending_orders: 1000
  matching_interval_ms: 100
  price_tolerance_bps: 10
  max_slippage_bps: 50
  order_timeout_seconds: 3600
  enable_cross_pool_matching: true

networking:
  listen_port: 9000
  bootstrap_peers: []
  min_peers: 1
  max_peers: 10
  connection_timeout_seconds: 30
  gossip_interval_ms: 1000
  enable_encryption: true

proofs:
  circuit_path: "$PROJECT_ROOT/circuits/build"
  proving_key_path: "$PROJECT_ROOT/circuits/build/order_matching_final.zkey"
  verification_key_path: "$PROJECT_ROOT/circuits/build/order_matching_verification_key.json"
  max_proof_size: 1048576
  proof_timeout_seconds: 300
  enable_batch_proving: true
EOF
    
    log_success "Operator configuration created"
}

# Build frontend
build_frontend() {
    log_info "Building frontend..."
    
    cd "$PROJECT_ROOT/frontend"
    
    # Install dependencies
    yarn install > "$LOGS_DIR/frontend-install.log" 2>&1
    
    # Create environment file
    cat > .env <<EOF
REACT_APP_BACKEND_URL=http://localhost:8001/api
REACT_APP_CHAIN_ID=31337
REACT_APP_SERVICE_MANAGER_ADDRESS=$SERVICE_MANAGER_ADDRESS
REACT_APP_HOOK_ADDRESS=$HOOK_ADDRESS
REACT_APP_VAULT_ADDRESS=$VAULT_ADDRESS
EOF
    
    # Build frontend
    yarn build > "$LOGS_DIR/frontend-build.log" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Frontend built successfully"
    else
        log_error "Failed to build frontend"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    # Register operator
    cd "$PROJECT_ROOT/eigenvault/operator"
    ./target/release/eigenvault-operator register \
        --config config.yaml \
        > "$LOGS_DIR/operator-register.log" 2>&1 &
    
    sleep 5
    
    # Start operator
    ./target/release/eigenvault-operator start \
        --config config.yaml \
        > "$LOGS_DIR/operator.log" 2>&1 &
    
    OPERATOR_PID=$!
    echo $OPERATOR_PID > "$BUILD_DIR/operator.pid"
    
    log_success "Operator started (PID: $OPERATOR_PID)"
    
    # Start frontend
    cd "$PROJECT_ROOT/frontend"
    yarn start > "$LOGS_DIR/frontend.log" 2>&1 &
    
    FRONTEND_PID=$!
    echo $FRONTEND_PID > "$BUILD_DIR/frontend.pid"
    
    log_success "Frontend started (PID: $FRONTEND_PID)"
    
    cd "$PROJECT_ROOT"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Kill processes
    if [ -f "$BUILD_DIR/anvil.pid" ]; then
        kill $(cat "$BUILD_DIR/anvil.pid") 2>/dev/null || true
        rm "$BUILD_DIR/anvil.pid"
    fi
    
    if [ -f "$BUILD_DIR/operator.pid" ]; then
        kill $(cat "$BUILD_DIR/operator.pid") 2>/dev/null || true
        rm "$BUILD_DIR/operator.pid"
    fi
    
    if [ -f "$BUILD_DIR/frontend.pid" ]; then
        kill $(cat "$BUILD_DIR/frontend.pid") 2>/dev/null || true
        rm "$BUILD_DIR/frontend.pid"
    fi
    
    log_info "Cleanup completed"
}

# Handle interrupts
trap cleanup EXIT INT TERM

# Main deployment flow
main() {
    log_info "Starting EigenVault local deployment..."
    
    check_prerequisites
    create_directories
    start_ethereum_node
    deploy_contracts
    compile_circuits
    build_operator
    generate_operator_keys
    configure_operator
    build_frontend
    start_services
    
    log_success "EigenVault deployment completed successfully!"
    echo ""
    echo "Services running:"
    echo "- Ethereum Node: http://localhost:8545"
    echo "- Operator: http://localhost:9000"
    echo "- Frontend: http://localhost:3000"
    echo ""
    echo "Logs available in: $LOGS_DIR"
    echo "Contract addresses in: $BUILD_DIR/contract-addresses.env"
    echo ""
    echo "Press Ctrl+C to stop all services"
    
    # Wait for interrupt
    while true; do
        sleep 1
    done
}

# Check for command line arguments
case "${1:-}" in
    "cleanup")
        cleanup
        exit 0
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [cleanup|help]"
        echo ""
        echo "Commands:"
        echo "  (none)   - Deploy EigenVault locally"
        echo "  cleanup  - Stop all services and clean up"
        echo "  help     - Show this help message"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac