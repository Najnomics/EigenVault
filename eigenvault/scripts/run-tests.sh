#!/bin/bash

# EigenVault Test Runner Script

set -e

echo "🧪 Running EigenVault Test Suite..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TYPE=${1:-"all"}
VERBOSE=${2:-"false"}

echo -e "${BLUE}Test Type: $TEST_TYPE${NC}"

# Function to run contract tests
run_contract_tests() {
    echo -e "${YELLOW}📋 Running Solidity contract tests...${NC}"
    cd contracts
    
    if [ "$VERBOSE" == "true" ]; then
        forge test -vvv
    else
        forge test -v
    fi
    
    local exit_code=$?
    cd ..
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ Contract tests passed${NC}"
    else
        echo -e "${RED}❌ Contract tests failed${NC}"
        return $exit_code
    fi
}

# Function to run operator tests
run_operator_tests() {
    echo -e "${YELLOW}🤖 Running Rust operator tests...${NC}"
    cd operator
    
    if [ "$VERBOSE" == "true" ]; then
        RUST_LOG=debug cargo test -- --nocapture
    else
        cargo test
    fi
    
    local exit_code=$?
    cd ..
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ Operator tests passed${NC}"
    else
        echo -e "${RED}❌ Operator tests failed${NC}"
        return $exit_code
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${YELLOW}🔗 Running integration tests...${NC}"
    
    # Start local testnet
    echo -e "${BLUE}Starting local testnet...${NC}"
    anvil --host 0.0.0.0 --port 8545 &
    ANVIL_PID=$!
    sleep 3
    
    # Cleanup function
    cleanup() {
        echo -e "${YELLOW}🧹 Cleaning up test environment...${NC}"
        kill $ANVIL_PID 2>/dev/null || true
        kill $OPERATOR_PID 2>/dev/null || true
    }
    trap cleanup EXIT
    
    # Deploy contracts
    echo -e "${BLUE}Deploying test contracts...${NC}"
    cd contracts
    forge script script/DeployEigenVault.s.sol \
        --rpc-url http://localhost:8545 \
        --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
        --broadcast
    cd ..
    
    # Start operator in test mode
    echo -e "${BLUE}Starting test operator...${NC}"
    cd operator
    cargo run -- start --config ../config.test.yaml &
    OPERATOR_PID=$!
    cd ..
    sleep 5
    
    # Run integration tests
    cd contracts
    forge test --match-contract Integration -v
    local contracts_exit=$?
    cd ..
    
    if [ $contracts_exit -eq 0 ]; then
        echo -e "${GREEN}✅ Integration tests passed${NC}"
    else
        echo -e "${RED}❌ Integration tests failed${NC}"
        return $contracts_exit
    fi
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${YELLOW}⚡ Running performance tests...${NC}"
    
    cd operator
    cargo test --release --test performance_tests
    local exit_code=$?
    cd ..
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ Performance tests passed${NC}"
    else
        echo -e "${RED}❌ Performance tests failed${NC}"
        return $exit_code
    fi
}

# Function to run security tests
run_security_tests() {
    echo -e "${YELLOW}🔒 Running security tests...${NC}"
    
    # Contract security tests
    cd contracts
    echo -e "${BLUE}Running Slither analysis...${NC}"
    if command -v slither &> /dev/null; then
        slither src/ || echo -e "${YELLOW}⚠️  Slither found potential issues${NC}"
    else
        echo -e "${YELLOW}⚠️  Slither not installed, skipping static analysis${NC}"
    fi
    cd ..
    
    # Operator security tests
    cd operator
    echo -e "${BLUE}Running cargo audit...${NC}"
    if command -v cargo-audit &> /dev/null; then
        cargo audit || echo -e "${YELLOW}⚠️  Audit found potential issues${NC}"
    else
        echo -e "${YELLOW}⚠️  cargo-audit not installed, skipping security audit${NC}"
    fi
    cd ..
    
    echo -e "${GREEN}✅ Security tests completed${NC}"
}

# Function to generate test report
generate_test_report() {
    echo -e "${YELLOW}📊 Generating test report...${NC}"
    
    local report_file="test-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# EigenVault Test Report

Generated on: $(date)
Test Type: $TEST_TYPE

## Summary

- Contract Tests: $CONTRACT_TESTS_STATUS
- Operator Tests: $OPERATOR_TESTS_STATUS
- Integration Tests: $INTEGRATION_TESTS_STATUS
- Performance Tests: $PERFORMANCE_TESTS_STATUS
- Security Tests: $SECURITY_TESTS_STATUS

## Details

### Contract Tests
$(cd contracts && forge test --list 2>/dev/null | wc -l) tests found

### Operator Tests
$(cd operator && cargo test --list 2>/dev/null | wc -l) tests found

### Coverage
To generate coverage report, run:
\`\`\`bash
cd contracts && forge coverage
cd operator && cargo tarpaulin --out Html
\`\`\`

EOF

    echo -e "${GREEN}📄 Test report generated: $report_file${NC}"
}

# Initialize test status variables
CONTRACT_TESTS_STATUS="Not Run"
OPERATOR_TESTS_STATUS="Not Run"
INTEGRATION_TESTS_STATUS="Not Run"
PERFORMANCE_TESTS_STATUS="Not Run"
SECURITY_TESTS_STATUS="Not Run"

# Main test execution
case $TEST_TYPE in
    "contracts")
        run_contract_tests && CONTRACT_TESTS_STATUS="Passed" || CONTRACT_TESTS_STATUS="Failed"
        ;;
    "operator")
        run_operator_tests && OPERATOR_TESTS_STATUS="Passed" || OPERATOR_TESTS_STATUS="Failed"
        ;;
    "integration")
        run_integration_tests && INTEGRATION_TESTS_STATUS="Passed" || INTEGRATION_TESTS_STATUS="Failed"
        ;;
    "performance")
        run_performance_tests && PERFORMANCE_TESTS_STATUS="Passed" || PERFORMANCE_TESTS_STATUS="Failed"
        ;;
    "security")
        run_security_tests && SECURITY_TESTS_STATUS="Completed"
        ;;
    "all")
        echo -e "${BLUE}🚀 Running full test suite...${NC}"
        
        run_contract_tests && CONTRACT_TESTS_STATUS="Passed" || CONTRACT_TESTS_STATUS="Failed"
        run_operator_tests && OPERATOR_TESTS_STATUS="Passed" || OPERATOR_TESTS_STATUS="Failed"
        run_integration_tests && INTEGRATION_TESTS_STATUS="Passed" || INTEGRATION_TESTS_STATUS="Failed"
        run_performance_tests && PERFORMANCE_TESTS_STATUS="Passed" || PERFORMANCE_TESTS_STATUS="Failed"
        run_security_tests && SECURITY_TESTS_STATUS="Completed"
        ;;
    *)
        echo -e "${RED}❌ Unknown test type: $TEST_TYPE${NC}"
        echo "Usage: $0 [contracts|operator|integration|performance|security|all] [verbose]"
        exit 1
        ;;
esac

# Generate report
generate_test_report

# Final summary
echo -e "\n${BLUE}📋 Test Summary:${NC}"
echo -e "Contract Tests: $CONTRACT_TESTS_STATUS"
echo -e "Operator Tests: $OPERATOR_TESTS_STATUS"
echo -e "Integration Tests: $INTEGRATION_TESTS_STATUS"
echo -e "Performance Tests: $PERFORMANCE_TESTS_STATUS"
echo -e "Security Tests: $SECURITY_TESTS_STATUS"

# Exit with appropriate code
if [[ "$CONTRACT_TESTS_STATUS" == "Failed" ]] || 
   [[ "$OPERATOR_TESTS_STATUS" == "Failed" ]] || 
   [[ "$INTEGRATION_TESTS_STATUS" == "Failed" ]] || 
   [[ "$PERFORMANCE_TESTS_STATUS" == "Failed" ]]; then
    echo -e "\n${RED}❌ Some tests failed${NC}"
    exit 1
else
    echo -e "\n${GREEN}✅ All tests completed successfully${NC}"
    exit 0
fi