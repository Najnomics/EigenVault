# EigenVault Makefile
# Comprehensive build, test, and deployment automation

.PHONY: help install build test coverage clean deploy-anvil deploy-testnet deploy-mainnet lint format

# Default target
help: ## Show this help message
	@echo "EigenVault Development Commands"
	@echo "================================"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "\033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# =============================================================================
# INSTALLATION & SETUP
# =============================================================================

install: ## Install all dependencies
	@echo "Installing Node.js dependencies..."
	npm install
	@echo "Installing Foundry dependencies..."
	cd eigenvault/contracts && forge install
	@echo "Installing frontend dependencies..."
	cd frontend && npm install
	@echo "Installing Go dependencies..."
	cd eigenvault/avs && go mod tidy
	@echo "✅ All dependencies installed successfully!"

install-foundry: ## Install Foundry toolchain
	@echo "Installing Foundry..."
	curl -L https://foundry.paradigm.xyz | bash
	foundryup
	@echo "✅ Foundry installed successfully!"

install-eigenlayer-cli: ## Install EigenLayer CLI
	@echo "Installing EigenLayer CLI..."
	go install github.com/Layr-Labs/eigenlayer-cli@latest
	@echo "✅ EigenLayer CLI installed successfully!"

# =============================================================================
# BUILD COMMANDS
# =============================================================================

build: ## Build all components
	@echo "Building smart contracts..."
	cd eigenvault/contracts && forge build
	@echo "Building frontend..."
	cd frontend && npm run build
	@echo "Building operator..."
	cd eigenvault/avs && go build -o bin/operator ./cmd/operator
	@echo "✅ All components built successfully!"

build-contracts: ## Build smart contracts only
	@echo "Building smart contracts..."
	cd eigenvault/contracts && forge build --sizes
	@echo "✅ Smart contracts built successfully!"

build-frontend: ## Build frontend only
	@echo "Building frontend..."
	cd frontend && npm run build
	@echo "✅ Frontend built successfully!"

build-operator: ## Build operator only
	@echo "Building operator..."
	cd eigenvault/avs && go build -o bin/operator ./cmd/operator
	@echo "✅ Operator built successfully!"

# =============================================================================
# TESTING COMMANDS
# =============================================================================

test: ## Run all tests
	@echo "Running smart contract tests..."
	cd eigenvault/contracts && forge test -v
	@echo "Running frontend tests..."
	cd frontend && npm test
	@echo "Running operator tests..."
	cd eigenvault/avs && go test ./...
	@echo "✅ All tests completed!"

test-unit: ## Run unit tests only
	@echo "Running unit tests..."
	cd eigenvault/contracts && forge test --match-test "test_" -v
	@echo "✅ Unit tests completed!"

test-integration: ## Run integration tests only
	@echo "Running integration tests..."
	cd eigenvault/contracts && forge test --match-path "test/integration/*" -v
	@echo "✅ Integration tests completed!"

test-fuzz: ## Run fuzz tests only
	@echo "Running fuzz tests..."
	cd eigenvault/contracts && forge test --match-test "testFuzz" -v
	@echo "✅ Fuzz tests completed!"

test-security: ## Run security tests only
	@echo "Running security tests..."
	cd eigenvault/contracts && forge test --match-path "test/security/*" -v
	@echo "✅ Security tests completed!"

test-hooks: ## Run hook tests only
	@echo "Running hook tests..."
	cd eigenvault/contracts && forge test --match-contract "EigenVaultHook" -v
	@echo "✅ Hook tests completed!"

test-avs: ## Run AVS tests only
	@echo "Running AVS tests..."
	cd eigenvault/contracts && forge test --match-path "test/avs/*" -v
	@echo "✅ AVS tests completed!"

test-vault: ## Run vault tests only
	@echo "Running vault tests..."
	cd eigenvault/contracts && forge test --match-path "test/vault/*" -v
	@echo "✅ Vault tests completed!"

test-performance: ## Run performance tests only
	@echo "Running performance tests..."
	cd eigenvault/contracts && forge test --match-path "test/integration/PerformanceTests.t.sol" -v
	@echo "✅ Performance tests completed!"

test-stress: ## Run stress tests only
	@echo "Running stress tests..."
	cd eigenvault/contracts && forge test --match-path "test/integration/StressTests.t.sol" -v
	@echo "✅ Stress tests completed!"

# =============================================================================
# COVERAGE COMMANDS
# =============================================================================

coverage: ## Generate coverage report
	@echo "Generating coverage report..."
	cd eigenvault/contracts && forge coverage --ir-minimum
	@echo "✅ Coverage report generated!"

coverage-full: ## Generate full coverage with IR optimization
	@echo "Generating full coverage report..."
	cd eigenvault/contracts && forge coverage --ir-minimum --report-file coverage-report.txt
	@echo "✅ Full coverage report generated!"

coverage-hooks: ## Generate hook-specific coverage
	@echo "Generating hook coverage..."
	cd eigenvault/contracts && forge coverage --match-path "src/hooks/*" --ir-minimum
	@echo "✅ Hook coverage generated!"

coverage-avs: ## Generate AVS-specific coverage
	@echo "Generating AVS coverage..."
	cd eigenvault/contracts && forge coverage --match-path "src/avs/*" --ir-minimum
	@echo "✅ AVS coverage generated!"

coverage-vault: ## Generate vault-specific coverage
	@echo "Generating vault coverage..."
	cd eigenvault/contracts && forge coverage --match-path "src/vault/*" --ir-minimum
	@echo "✅ Vault coverage generated!"

coverage-report: ## Generate HTML coverage report
	@echo "Generating HTML coverage report..."
	cd eigenvault/contracts && forge coverage --report lcov && genhtml lcov.info -o coverage-report
	@echo "✅ HTML coverage report generated in coverage-report/"

# =============================================================================
# DEPLOYMENT COMMANDS
# =============================================================================

deploy-anvil: ## Deploy to local Anvil
	@echo "Starting Anvil..."
	anvil --host 0.0.0.0 --port 8545 --accounts 10 --balance 10000 &
	@sleep 3
	@echo "Deploying to Anvil..."
	cd eigenvault/contracts && forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast
	@echo "✅ Deployed to Anvil successfully!"

deploy-testnet: ## Deploy to Holesky testnet
	@echo "Deploying to Holesky testnet..."
	cd eigenvault/contracts && forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $$HOLESKY_RPC_URL
	@echo "✅ Deployed to testnet successfully!"

deploy-mainnet: ## Deploy to mainnet (requires confirmation)
	@echo "⚠️  WARNING: This will deploy to Ethereum mainnet!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	@echo "Deploying to mainnet..."
	cd eigenvault/contracts && forge script script/DeployOrderVaultOnly.s.sol --broadcast --rpc-url $$MAINNET_RPC_URL
	@echo "✅ Deployed to mainnet successfully!"

deploy-hook: ## Deploy full hook system
	@echo "Deploying full hook system..."
	cd eigenvault/contracts && forge script script/DeployWithProperHook.s.sol --rpc-url http://localhost:8545 --broadcast
	@echo "✅ Full hook system deployed successfully!"

verify-testnet: ## Verify contracts on Holesky
	@echo "Verifying contracts on Holesky..."
	cd eigenvault/contracts && forge verify-contract --chain-id 17000 --num-of-optimizations 200 --watch --etherscan-api-key $$HOLESKY_ETHERSCAN_API_KEY $$CONTRACT_ADDRESS src/hooks/EigenVaultHook.sol:EigenVaultHook
	@echo "✅ Contracts verified on Holesky!"

verify-mainnet: ## Verify contracts on mainnet
	@echo "Verifying contracts on mainnet..."
	cd eigenvault/contracts && forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --etherscan-api-key $$ETHERSCAN_API_KEY $$CONTRACT_ADDRESS src/hooks/EigenVaultHook.sol:EigenVaultHook
	@echo "✅ Contracts verified on mainnet!"

# =============================================================================
# CODE QUALITY COMMANDS
# =============================================================================

lint: ## Run linting
	@echo "Running Solidity linting..."
	cd eigenvault/contracts && forge fmt --check
	@echo "Running JavaScript linting..."
	cd frontend && npm run lint
	@echo "Running Go linting..."
	cd eigenvault/avs && golangci-lint run
	@echo "✅ Linting completed!"

format: ## Format code
	@echo "Formatting Solidity code..."
	cd eigenvault/contracts && forge fmt
	@echo "Formatting JavaScript code..."
	cd frontend && npm run format
	@echo "Formatting Go code..."
	cd eigenvault/avs && go fmt ./...
	@echo "✅ Code formatting completed!"

lint-fix: ## Fix linting issues
	@echo "Fixing Solidity formatting..."
	cd eigenvault/contracts && forge fmt
	@echo "Fixing JavaScript linting..."
	cd frontend && npm run lint:fix
	@echo "✅ Linting issues fixed!"

# =============================================================================
# SECURITY COMMANDS
# =============================================================================

security-check: ## Run security analysis
	@echo "Running Slither analysis..."
	cd eigenvault/contracts && slither .
	@echo "Running Mythril analysis..."
	cd eigenvault/contracts && myth analyze src/hooks/EigenVaultHook.sol
	@echo "✅ Security analysis completed!"

security-audit: ## Run comprehensive security audit
	@echo "Running comprehensive security audit..."
	cd eigenvault/contracts && forge test --match-path "test/security/*" -v
	@echo "Running Slither analysis..."
	cd eigenvault/contracts && slither . --exclude-dependencies
	@echo "Running Mythril analysis..."
	cd eigenvault/contracts && myth analyze src/hooks/EigenVaultHook.sol
	@echo "✅ Security audit completed!"

# =============================================================================
# DEVELOPMENT COMMANDS
# =============================================================================

dev: ## Start development environment
	@echo "Starting development environment..."
	@echo "Starting Anvil..."
	anvil --host 0.0.0.0 --port 8545 --accounts 10 --balance 10000 &
	@sleep 3
	@echo "Deploying contracts..."
	cd eigenvault/contracts && forge script script/DeployOrderVaultOnly.s.sol --rpc-url http://localhost:8545 --broadcast
	@echo "Starting frontend..."
	cd frontend && npm run dev &
	@echo "Starting operator..."
	cd eigenvault/avs && ./bin/operator start --config config.yaml &
	@echo "✅ Development environment started!"

dev-frontend: ## Start frontend development server
	@echo "Starting frontend development server..."
	cd frontend && npm run dev

dev-operator: ## Start operator development
	@echo "Starting operator..."
	cd eigenvault/avs && go run ./cmd/operator start --config config.yaml

dev-monitoring: ## Start monitoring stack
	@echo "Starting monitoring stack..."
	docker-compose -f docker/docker-compose.yml up -d prometheus grafana
	@echo "✅ Monitoring stack started!"

# =============================================================================
# CLEANUP COMMANDS
# =============================================================================

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	cd eigenvault/contracts && forge clean
	cd frontend && rm -rf dist build
	cd eigenvault/avs && rm -rf bin/
	@echo "✅ Build artifacts cleaned!"

clean-all: ## Clean everything including dependencies
	@echo "Cleaning all artifacts and dependencies..."
	rm -rf node_modules/
	rm -rf frontend/node_modules/
	cd eigenvault/contracts && forge clean && rm -rf lib/
	cd eigenvault/avs && rm -rf bin/ && go clean -cache
	@echo "✅ All artifacts and dependencies cleaned!"

clean-logs: ## Clean log files
	@echo "Cleaning log files..."
	find . -name "*.log" -type f -delete
	find . -name "logs" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "✅ Log files cleaned!"

# =============================================================================
# DOCKER COMMANDS
# =============================================================================

docker-build: ## Build Docker images
	@echo "Building Docker images..."
	docker build -f docker/operator.Dockerfile -t eigenvault-operator:latest .
	docker build -f docker/frontend.Dockerfile -t eigenvault-frontend:latest ./frontend
	@echo "✅ Docker images built!"

docker-up: ## Start Docker services
	@echo "Starting Docker services..."
	docker-compose -f docker/docker-compose.yml up -d
	@echo "✅ Docker services started!"

docker-down: ## Stop Docker services
	@echo "Stopping Docker services..."
	docker-compose -f docker/docker-compose.yml down
	@echo "✅ Docker services stopped!"

docker-logs: ## View Docker logs
	docker-compose -f docker/docker-compose.yml logs -f

# =============================================================================
# MONITORING COMMANDS
# =============================================================================

monitoring-start: ## Start monitoring stack
	@echo "Starting monitoring stack..."
	docker-compose -f docker/docker-compose.yml up -d prometheus grafana
	@echo "✅ Monitoring stack started!"
	@echo "Prometheus: http://localhost:9090"
	@echo "Grafana: http://localhost:3001 (admin/admin)"

monitoring-stop: ## Stop monitoring stack
	@echo "Stopping monitoring stack..."
	docker-compose -f docker/docker-compose.yml stop prometheus grafana
	@echo "✅ Monitoring stack stopped!"

monitoring-restart: ## Restart monitoring stack
	@echo "Restarting monitoring stack..."
	docker-compose -f docker/docker-compose.yml restart prometheus grafana
	@echo "✅ Monitoring stack restarted!"

# =============================================================================
# UTILITY COMMANDS
# =============================================================================

gas-report: ## Generate gas usage report
	@echo "Generating gas report..."
	cd eigenvault/contracts && forge test --gas-report
	@echo "✅ Gas report generated!"

size-report: ## Generate contract size report
	@echo "Generating size report..."
	cd eigenvault/contracts && forge build --sizes
	@echo "✅ Size report generated!"

fork-test: ## Run tests against forked mainnet
	@echo "Running tests against forked mainnet..."
	cd eigenvault/contracts && forge test --fork-url $$MAINNET_RPC_URL
	@echo "✅ Fork tests completed!"

benchmark: ## Run performance benchmarks
	@echo "Running performance benchmarks..."
	cd eigenvault/contracts && forge test --match-path "test/integration/PerformanceTests.t.sol" --gas-report
	@echo "✅ Benchmarks completed!"

# =============================================================================
# CI/CD COMMANDS
# =============================================================================

ci-test: ## Run CI test suite
	@echo "Running CI test suite..."
	cd eigenvault/contracts && forge test --gas-report
	cd frontend && npm run test:ci
	cd eigenvault/avs && go test ./...
	@echo "✅ CI test suite completed!"

ci-coverage: ## Generate CI coverage report
	@echo "Generating CI coverage report..."
	cd eigenvault/contracts && forge coverage --report lcov
	@echo "✅ CI coverage report generated!"

ci-security: ## Run CI security checks
	@echo "Running CI security checks..."
	cd eigenvault/contracts && forge test --match-path "test/security/*"
	@echo "✅ CI security checks completed!"

# =============================================================================
# DOCUMENTATION COMMANDS
# =============================================================================

docs-build: ## Build documentation
	@echo "Building documentation..."
	@echo "Documentation is in Markdown format and ready to view"
	@echo "✅ Documentation built!"

docs-serve: ## Serve documentation locally
	@echo "Serving documentation..."
	@echo "Open docs/ directory in your browser"
	@echo "✅ Documentation served!"

# =============================================================================
# RELEASE COMMANDS
# =============================================================================

release-prepare: ## Prepare release
	@echo "Preparing release..."
	@echo "Running full test suite..."
	$(MAKE) test
	@echo "Running security audit..."
	$(MAKE) security-audit
	@echo "Generating coverage report..."
	$(MAKE) coverage
	@echo "✅ Release preparation completed!"

release-build: ## Build release artifacts
	@echo "Building release artifacts..."
	$(MAKE) build
	@echo "Creating release package..."
	tar -czf eigenvault-release.tar.gz eigenvault/ frontend/ docs/ scripts/ docker/
	@echo "✅ Release artifacts built!"

# =============================================================================
# HELPERS
# =============================================================================

check-env: ## Check environment configuration
	@echo "Checking environment configuration..."
	@test -f .env && echo "✅ .env file exists" || echo "❌ .env file missing"
	@test -f eigenvault/contracts/anvil-deployments.env && echo "✅ Anvil deployments file exists" || echo "❌ Anvil deployments file missing"
	@echo "Environment check completed!"

status: ## Show project status
	@echo "EigenVault Project Status"
	@echo "========================"
	@echo "Smart Contracts:"
	@cd eigenvault/contracts && forge build --sizes 2>/dev/null | grep -E "(EigenVaultHook|OrderVault)" || echo "Not built"
	@echo "Frontend:"
	@test -d frontend/dist && echo "✅ Built" || echo "❌ Not built"
	@echo "Operator:"
	@test -f eigenvault/avs/bin/operator && echo "✅ Built" || echo "❌ Not built"
	@echo "Tests:"
	@cd eigenvault/contracts && forge test --summary 2>/dev/null | tail -1 || echo "Tests not run"
	@echo "Status check completed!"
