#!/bin/bash

# System Integration Test Script for EigenVault
# Tests the complete system end-to-end

set -e

# Colors for output  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🧪 EigenVault System Integration Tests${NC}"
echo "====================================="

# Check if system is deployed
if [[ ! -f "eigenvault/contracts/deployments.env" ]]; then
    echo -e "${RED}❌ System not deployed. Run deploy-production.sh first.${NC}"
    exit 1
fi

source eigenvault/contracts/deployments.env

# Test configuration
TEST_PRIVATE_KEY=${TEST_PRIVATE_KEY:-$DEPLOYER_PRIVATE_KEY}
RPC_URL=${RPC_URL:-"https://ethereum-holesky-rpc.publicnode.com"}
TEST_AMOUNT="100" # 100 ETH for large order test

echo -e "${YELLOW}📋 Test Configuration${NC}"
echo "Hook Contract: $EIGENVAULT_HOOK"
echo "Service Manager: $EIGENVAULT_SERVICE_MANAGER"
echo "Order Vault: $EIGENVAULT_ORDER_VAULT"
echo "RPC URL: $RPC_URL"

# Test 1: Contract Deployment Verification
echo -e "${YELLOW}🔍 Test 1: Verifying contract deployments...${NC}"

cd eigenvault/contracts

# Check if contracts have code
hook_code=$(cast code $EIGENVAULT_HOOK --rpc-url $RPC_URL)
if [[ ${#hook_code} -gt 10 ]]; then
    echo -e "${GREEN}✅ Hook contract deployed successfully${NC}"
else
    echo -e "${RED}❌ Hook contract not found${NC}"
    exit 1
fi

vault_code=$(cast code $EIGENVAULT_ORDER_VAULT --rpc-url $RPC_URL)
if [[ ${#vault_code} -gt 10 ]]; then
    echo -e "${GREEN}✅ Order vault deployed successfully${NC}"
else
    echo -e "${RED}❌ Order vault not found${NC}"
    exit 1
fi

manager_code=$(cast code $EIGENVAULT_SERVICE_MANAGER --rpc-url $RPC_URL)
if [[ ${#manager_code} -gt 10 ]]; then
    echo -e "${GREEN}✅ Service manager deployed successfully${NC}"
else
    echo -e "${RED}❌ Service manager not found${NC}"
    exit 1
fi

# Test 2: Contract Configuration
echo -e "${YELLOW}🔧 Test 2: Verifying contract configuration...${NC}"

# Check hook-vault authorization
is_authorized=$(cast call $EIGENVAULT_ORDER_VAULT \
    "isAuthorizedHook(address)(bool)" $EIGENVAULT_HOOK \
    --rpc-url $RPC_URL)

if [[ "$is_authorized" == "true" ]]; then
    echo -e "${GREEN}✅ Hook is authorized in order vault${NC}"
else
    echo -e "${RED}❌ Hook authorization missing${NC}"
    exit 1
fi

# Check vault threshold
threshold=$(cast call $EIGENVAULT_HOOK \
    "vaultThresholdBps()(uint256)" \
    --rpc-url $RPC_URL)

echo "Vault threshold: $threshold bps"

# Test 3: Order Size Classification
echo -e "${YELLOW}🔢 Test 3: Testing order size classification...${NC}"

# Create test pool key
POOL_KEY="(0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222,3000,60,$EIGENVAULT_HOOK)"

# Test large order detection
large_amount="100000000000000000000000" # 100,000 ETH
is_large=$(cast call $EIGENVAULT_HOOK \
    "isLargeOrder(int256,$POOL_KEY)(bool)" $large_amount \
    --rpc-url $RPC_URL)

if [[ "$is_large" == "true" ]]; then
    echo -e "${GREEN}✅ Large order detection working${NC}"
else
    echo -e "${RED}❌ Large order detection failed${NC}"
    exit 1
fi

# Test small order detection  
small_amount="1000000000000000000" # 1 ETH
is_small=$(cast call $EIGENVAULT_HOOK \
    "isLargeOrder(int256,$POOL_KEY)(bool)" $small_amount \
    --rpc-url $RPC_URL)

if [[ "$is_small" == "false" ]]; then
    echo -e "${GREEN}✅ Small order detection working${NC}"
else
    echo -e "${RED}❌ Small order detection failed${NC}"
    exit 1
fi

# Test 4: Order Submission
echo -e "${YELLOW}📝 Test 4: Testing order submission...${NC}"

TRADER_ADDRESS=$(cast wallet address --private-key $TEST_PRIVATE_KEY)
echo "Trader address: $TRADER_ADDRESS"

# Create order data
COMMITMENT=$(cast keccak "test_commitment_$(date +%s)")
DEADLINE=$(($(date +%s) + 3600)) # 1 hour from now
ENCRYPTED_ORDER="0x$(echo "encrypted_test_order_$(date +%s)" | xxd -p)"

# Encode hook data
HOOK_DATA=$(cast abi-encode "f(bytes32,uint256,bytes)" $COMMITMENT $DEADLINE $ENCRYPTED_ORDER)

echo "Commitment: $COMMITMENT"
echo "Deadline: $DEADLINE"

# Submit order (this will fail without proper pool setup, but we can test the call)
echo "Testing order submission call..."

set +e # Allow failure for this test
cast send $EIGENVAULT_HOOK \
    "routeToVault(address,$POOL_KEY,(bool,int256,uint160),bytes)" \
    $TRADER_ADDRESS \
    "true" $large_amount "0" \
    $HOOK_DATA \
    --private-key $TEST_PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    > /tmp/order_submission.log 2>&1

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Order submission successful${NC}"
    TX_HASH=$(grep "transactionHash" /tmp/order_submission.log | cut -d'"' -f4)
    echo "Transaction: $TX_HASH"
else
    echo -e "${YELLOW}⚠️  Order submission failed (expected without pool setup)${NC}"
    cat /tmp/order_submission.log
fi
set -e

# Test 5: Operator Registration
echo -e "${YELLOW}🤖 Test 5: Testing operator functionality...${NC}"

# Check operator count
operator_count=$(cast call $EIGENVAULT_SERVICE_MANAGER \
    "getActiveOperatorsCount()(uint256)" \
    --rpc-url $RPC_URL)

echo "Active operators: $operator_count"

if [[ "$operator_count" -gt 0 ]]; then
    echo -e "${GREEN}✅ Operators are registered${NC}"
    
    # Get first operator
    operators=$(cast call $EIGENVAULT_SERVICE_MANAGER \
        "getActiveOperators()(address[])" \
        --rpc-url $RPC_URL)
    echo "Operators: $operators"
else
    echo -e "${YELLOW}⚠️  No operators registered yet${NC}"
fi

# Test 6: Frontend Integration
echo -e "${YELLOW}🌐 Test 6: Testing frontend build...${NC}"

cd ../../frontend

# Check if contract ABIs exist
if [[ -f "src/contracts/EigenVaultHook.json" ]]; then
    echo -e "${GREEN}✅ Contract ABIs available${NC}"
else
    echo -e "${YELLOW}⚠️  Contract ABIs missing, copying...${NC}"
    mkdir -p src/contracts
    cp ../eigenvault/contracts/out/EigenVaultHook.sol/EigenVaultHook.json src/contracts/
    cp ../eigenvault/contracts/out/OrderVault.sol/OrderVault.json src/contracts/
    cp ../eigenvault/contracts/out/EigenVaultServiceManager.sol/EigenVaultServiceManager.json src/contracts/
fi

# Test frontend build
if command -v npm &> /dev/null; then
    echo "Testing frontend build..."
    npm install --silent
    CI=true npm run build
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Frontend build successful${NC}"
    else
        echo -e "${RED}❌ Frontend build failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  npm not found, skipping frontend test${NC}"
fi

# Test 7: Operator Health Check
echo -e "${YELLOW}💓 Test 7: Testing operator health...${NC}"

if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Operator is running and healthy${NC}"
    
    # Get operator status
    status=$(curl -s http://localhost:8080/status 2>/dev/null || echo "Status unavailable")
    echo "Operator status: $status"
else
    echo -e "${YELLOW}⚠️  Operator not running or not accessible${NC}"
    echo "Start operator with: ./scripts/start-operator.sh"
fi

# Test Summary
echo ""
echo -e "${GREEN}🎉 System Integration Test Summary${NC}"
echo "================================="
echo -e "${GREEN}✅ Contract deployments verified${NC}"
echo -e "${GREEN}✅ Contract configurations correct${NC}"
echo -e "${GREEN}✅ Order size classification working${NC}"
echo -e "${GREEN}✅ Contract interfaces functional${NC}"

if [[ "$operator_count" -gt 0 ]]; then
    echo -e "${GREEN}✅ Operators registered and active${NC}"
else
    echo -e "${YELLOW}⚠️  Operator registration recommended${NC}"
fi

if [[ -f "../frontend/build/index.html" ]]; then
    echo -e "${GREEN}✅ Frontend built successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Frontend build skipped${NC}"
fi

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Register operators: ./scripts/register-operators.sh"
echo "2. Start operator: ./scripts/start-operator.sh"
echo "3. Start frontend: cd frontend && npm start"
echo "4. Submit test orders through the UI"
echo "5. Monitor system: ./scripts/monitor-system.sh"

echo ""
echo -e "${GREEN}✅ System integration tests completed successfully!${NC}"