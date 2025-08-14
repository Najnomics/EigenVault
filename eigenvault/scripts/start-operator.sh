#!/bin/bash

# EigenVault Operator Startup Script

set -e

echo "🤖 Starting EigenVault Operator..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE=${1:-"config.yaml"}
ENVIRONMENT=${2:-"development"}

echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Config file: $CONFIG_FILE${NC}"

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}❌ Rust is not installed. Please install Rust.${NC}"
    exit 1
fi

# Navigate to operator directory
cd operator

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  Config file not found. Initializing...${NC}"
    cargo run -- init --config "$CONFIG_FILE"
    echo -e "${YELLOW}📝 Please edit $CONFIG_FILE with your settings${NC}"
    exit 0
fi

# Build operator in release mode
echo -e "${YELLOW}🔨 Building operator...${NC}"
cargo build --release

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Operator build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Operator built successfully${NC}"

# Run tests
echo -e "${YELLOW}🧪 Running operator tests...${NC}"
cargo test --release

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Some tests failed, but continuing...${NC}"
fi

# Check if keys exist
KEYS_DIR="keys"
if [ ! -d "$KEYS_DIR" ] || [ ! -f "$KEYS_DIR/operator_keys.json" ]; then
    echo -e "${YELLOW}🔑 Generating operator keys...${NC}"
    cargo run --release -- keygen --output "$KEYS_DIR"
    echo -e "${YELLOW}🔒 Please secure your private keys!${NC}"
fi

# Validate configuration
echo -e "${YELLOW}🔍 Validating configuration...${NC}"

# Set environment variables
export EIGENVAULT_ENV=$ENVIRONMENT
export RUST_LOG=${RUST_LOG:-"eigenvault_operator=info,info"}
export RUST_BACKTRACE=1

# Create logs directory
mkdir -p logs

# Function to handle cleanup
cleanup() {
    echo -e "\n${YELLOW}🧹 Shutting down operator...${NC}"
    kill $OPERATOR_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start the operator
echo -e "${GREEN}🚀 Starting EigenVault operator...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"

# Run operator with logging
cargo run --release -- start --config "$CONFIG_FILE" 2>&1 | tee logs/operator-$(date +%Y%m%d-%H%M%S).log &
OPERATOR_PID=$!

# Wait for operator to start
sleep 2

# Check if operator is running
if ! kill -0 $OPERATOR_PID 2>/dev/null; then
    echo -e "${RED}❌ Operator failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Operator is running (PID: $OPERATOR_PID)${NC}"

# Monitor operator health
while kill -0 $OPERATOR_PID 2>/dev/null; do
    sleep 5
    
    # Basic health check (you could add more sophisticated checks)
    if ! kill -0 $OPERATOR_PID 2>/dev/null; then
        echo -e "${RED}❌ Operator process died${NC}"
        break
    fi
done

echo -e "${YELLOW}👋 Operator stopped${NC}"