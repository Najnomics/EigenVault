#!/bin/bash

# Operator Startup Script for EigenVault
# Starts the EigenVault operator with proper monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🤖 Starting EigenVault Operator${NC}"
echo "==============================="

# Check if operator is built
if [[ ! -f "eigenvault/operator/target/release/eigenvault-operator" ]]; then
    echo -e "${YELLOW}🔨 Building operator...${NC}"
    cd eigenvault/operator
    cargo build --release
    cd ../..
fi

# Check if configuration exists
if [[ ! -f "eigenvault/operator/config.yaml" ]]; then
    echo -e "${RED}❌ No operator configuration found. Run register-operators.sh first.${NC}"
    exit 1
fi

# Create necessary directories
mkdir -p eigenvault/operator/logs
mkdir -p eigenvault/operator/data
mkdir -p eigenvault/operator/keys

# Check if private key exists
if [[ ! -f "eigenvault/operator/keys/operator.key" ]]; then
    echo -e "${YELLOW}🔑 Generating operator keys...${NC}"
    cd eigenvault/operator
    ./target/release/eigenvault-operator keygen --output keys/
    cd ../..
fi

# Start operator in production mode
echo -e "${YELLOW}🚀 Starting operator...${NC}"

cd eigenvault/operator

# Option 1: Start with systemd (recommended for production)
if command -v systemctl &> /dev/null; then
    echo -e "${YELLOW}📝 Creating systemd service...${NC}"
    
    sudo tee /etc/systemd/system/eigenvault-operator.service > /dev/null << EOF
[Unit]
Description=EigenVault Operator
After=network.target
Wants=network.target

[Service]
Type=exec
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/target/release/eigenvault-operator start --config config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=eigenvault-operator

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$(pwd)

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable eigenvault-operator
    sudo systemctl start eigenvault-operator
    
    echo -e "${GREEN}✅ Operator started as systemd service${NC}"
    echo "Status: sudo systemctl status eigenvault-operator"
    echo "Logs: sudo journalctl -u eigenvault-operator -f"
    echo "Stop: sudo systemctl stop eigenvault-operator"

# Option 2: Start with screen (development/testing)
elif command -v screen &> /dev/null; then
    echo -e "${YELLOW}📺 Starting operator in screen session...${NC}"
    screen -dmS eigenvault-operator ./target/release/eigenvault-operator start --config config.yaml
    
    echo -e "${GREEN}✅ Operator started in screen session${NC}"
    echo "Attach: screen -r eigenvault-operator"
    echo "List sessions: screen -ls"

# Option 3: Start with nohup (fallback)
else
    echo -e "${YELLOW}🔄 Starting operator with nohup...${NC}"
    nohup ./target/release/eigenvault-operator start --config config.yaml > logs/operator.log 2>&1 &
    OPERATOR_PID=$!
    echo $OPERATOR_PID > eigenvault-operator.pid
    
    echo -e "${GREEN}✅ Operator started (PID: $OPERATOR_PID)${NC}"
    echo "Logs: tail -f logs/operator.log"
    echo "Stop: kill $OPERATOR_PID"
fi

# Wait a moment for startup
sleep 3

# Check if operator is healthy
echo -e "${YELLOW}🏥 Checking operator health...${NC}"

# Try to connect to operator API
if curl -s http://localhost:8080/health > /dev/null; then
    echo -e "${GREEN}✅ Operator is healthy and responding${NC}"
    
    # Get operator status
    status=$(curl -s http://localhost:8080/status)
    echo "Status: $status"
else
    echo -e "${YELLOW}⚠️  Operator may still be starting up...${NC}"
fi

# Display monitoring information
echo ""
echo -e "${GREEN}🎉 Operator startup complete!${NC}"
echo ""
echo -e "${YELLOW}Monitoring Commands:${NC}"
if command -v systemctl &> /dev/null; then
    echo "• Status: sudo systemctl status eigenvault-operator"
    echo "• Logs: sudo journalctl -u eigenvault-operator -f"
    echo "• Stop: sudo systemctl stop eigenvault-operator"
    echo "• Restart: sudo systemctl restart eigenvault-operator"
elif command -v screen &> /dev/null; then
    echo "• Attach: screen -r eigenvault-operator"
    echo "• Detach: Ctrl+A, D"
    echo "• Kill: screen -X -S eigenvault-operator quit"
else
    echo "• Logs: tail -f logs/operator.log"
    echo "• Stop: kill \$(cat eigenvault-operator.pid)"
fi

echo ""
echo -e "${YELLOW}API Endpoints:${NC}"
echo "• Health: http://localhost:8080/health"
echo "• Status: http://localhost:8080/status" 
echo "• Metrics: http://localhost:8080/metrics"

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Monitor operator logs for successful task processing"
echo "2. Submit test orders through the frontend"
echo "3. Set up monitoring dashboard: ./scripts/setup-monitoring.sh"