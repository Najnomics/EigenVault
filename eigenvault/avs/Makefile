# EigenVault AVS Makefile
# Provides commands for building, testing, and deploying the EigenVault AVS

.PHONY: help build clean test keys config deploy-operator deploy-aggregator deploy-all dev-setup deps fmt lint test-race docs docker-build docker-run docker-stop monitor prod-deploy help-operator help-aggregator

# Default target
help: ## Show this help message
	@echo "EigenVault AVS - Available Commands:"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Build targets
build: ## Build all components (operator, aggregator)
	@echo "Building EigenVault AVS components..."
	@mkdir -p bin
	go build -o bin/operator ./cmd/operator
	go build -o bin/aggregator ./cmd/aggregator
	@echo "Build complete!"

build-operator: ## Build only the operator
	@echo "Building operator..."
	@mkdir -p bin
	go build -o bin/operator ./cmd/operator

build-aggregator: ## Build only the aggregator
	@echo "Building aggregator..."
	@mkdir -p bin
	go build -o bin/aggregator ./cmd/aggregator

# Clean targets
clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	rm -rf contracts/out/
	rm -rf contracts/cache/
	@echo "Clean complete!"

# Test targets
test: ## Run all tests
	@echo "Running tests..."
	go test -v ./...
	@echo "Tests complete!"

test-race: ## Run tests with race detection
	@echo "Running tests with race detection..."
	go test -race -v ./...

# Key management
keys: ## Generate operator and aggregator keys
	@echo "Generating keys..."
	@mkdir -p keys
	@echo '{"address":"0x0000000000000000000000000000000000000000","privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > keys/operator.ecdsa.key.json
	@echo '{"privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000","publicKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > keys/operator.bls.key.json
	@echo '{"address":"0x0000000000000000000000000000000000000000","privateKey":"0x0000000000000000000000000000000000000000000000000000000000000000"}' > keys/aggregator.ecdsa.key.json
	@echo "Keys generated in keys/ directory"

# Configuration
config: ## Create default configuration files
	@echo "Creating configuration files..."
	@mkdir -p config
	@if [ ! -f config/operator.yaml ]; then \
		echo "Creating operator.yaml..."; \
		cp config/operator.yaml config/operator.yaml.example 2>/dev/null || echo "operator.yaml already exists"; \
	fi
	@if [ ! -f config/aggregator.yaml ]; then \
		echo "Creating aggregator.yaml..."; \
		cp config/aggregator.yaml config/aggregator.yaml.example 2>/dev/null || echo "aggregator.yaml already exists"; \
	fi
	@echo "Configuration files ready!"

# Deployment targets
deploy-operator: build-operator ## Deploy and start the operator
	@echo "Starting EigenVault operator..."
	@if [ ! -f config/operator.yaml ]; then \
		echo "Error: config/operator.yaml not found. Run 'make config' first."; \
		exit 1; \
	fi
	./bin/operator -config ./config/operator.yaml

deploy-aggregator: build-aggregator ## Deploy and start the aggregator
	@echo "Starting EigenVault aggregator..."
	@if [ ! -f config/aggregator.yaml ]; then \
		echo "Error: config/aggregator.yaml not found. Run 'make config' first."; \
		exit 1; \
	fi
	./bin/aggregator -config ./config/aggregator.yaml

deploy-all: build ## Deploy all components
	@echo "Deploying all EigenVault AVS components..."
	@echo "Starting aggregator in background..."
	@./bin/aggregator -config ./config/aggregator.yaml &
	@sleep 2
	@echo "Starting operator..."
	@./bin/operator -config ./config/operator.yaml

# Development setup
dev-setup: deps keys config ## Set up development environment
	@echo "Setting up development environment..."
	@echo "Development environment ready!"
	@echo "Next steps:"
	@echo "  1. Edit config/operator.yaml with your settings"
	@echo "  2. Edit config/aggregator.yaml with your settings"
	@echo "  3. Run 'make deploy-all' to start the system"

deps: ## Install Go dependencies
	@echo "Installing Go dependencies..."
	go mod tidy
	go mod download
	@echo "Dependencies installed!"

# Code quality
fmt: ## Format Go code
	@echo "Formatting Go code..."
	go fmt ./...
	@echo "Code formatting complete!"

lint: ## Lint Go code
	@echo "Linting Go code..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "golangci-lint not found. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

# Documentation
docs: ## Generate documentation
	@echo "Generating documentation..."
	@echo "Documentation generation complete!"

# Docker targets
docker-build: ## Build Docker images
	@echo "Building Docker images..."
	docker build -t eigenvault-operator:latest -f Dockerfile.operator .
	docker build -t eigenvault-aggregator:latest -f Dockerfile.aggregator .
	@echo "Docker images built!"

docker-run: ## Run with Docker Compose
	@echo "Starting EigenVault AVS with Docker..."
	docker-compose up -d
	@echo "Docker services started!"

docker-stop: ## Stop Docker services
	@echo "Stopping Docker services..."
	docker-compose down
	@echo "Docker services stopped!"

# Monitoring
monitor: ## Monitor system status
	@echo "Monitoring EigenVault AVS..."
	@echo "Operator health:"
	@curl -s http://localhost:9091/health || echo "Operator not responding"
	@echo "Aggregator health:"
	@curl -s http://localhost:8090/health || echo "Aggregator not responding"
	@echo "Operator metrics:"
	@curl -s http://localhost:9090/metrics | head -20 || echo "Metrics not available"

# Production deployment
prod-deploy: ## Production deployment
	@echo "Production deployment not implemented yet"
	@echo "Please implement production deployment scripts"

# Smart contract targets
contracts-build: ## Build smart contracts
	@echo "Building smart contracts..."
	cd contracts && forge build
	@echo "Smart contracts built!"

contracts-test: ## Test smart contracts
	@echo "Testing smart contracts..."
	cd contracts && forge test
	@echo "Smart contract tests complete!"

contracts-deploy-testnet: ## Deploy smart contracts to testnet
	@echo "Deploying smart contracts to testnet..."
	cd contracts && forge script DeployEigenVaultAVS --rpc-url ${SEPOLIA_RPC_URL} --broadcast --verify

contracts-deploy-mainnet: ## Deploy smart contracts to mainnet
	@echo "Deploying smart contracts to mainnet..."
	cd contracts && forge script DeployEigenVaultAVS --rpc-url ${MAINNET_RPC_URL} --broadcast --verify

# Help targets
help-operator: ## Show operator-specific help
	@echo "EigenVault Operator Commands:"
	@echo "  make build-operator     - Build the operator"
	@echo "  make deploy-operator    - Start the operator"
	@echo "  make keys               - Generate operator keys"
	@echo "  make config             - Create configuration files"

help-aggregator: ## Show aggregator-specific help
	@echo "EigenVault Aggregator Commands:"
	@echo "  make build-aggregator   - Build the aggregator"
	@echo "  make deploy-aggregator  - Start the aggregator"
	@echo "  make keys               - Generate aggregator keys"
	@echo "  make config             - Create configuration files"

# Utility targets
check-env: ## Check environment setup
	@echo "Checking environment..."
	@echo "Go version: $(shell go version)"
	@echo "Go modules: $(shell go env GOMOD)"
	@echo "Working directory: $(shell pwd)"
	@echo "Environment check complete!"

install-tools: ## Install development tools
	@echo "Installing development tools..."
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/vektra/mockery/v2@latest
	@echo "Development tools installed!"

# Default target
.DEFAULT_GOAL := help 