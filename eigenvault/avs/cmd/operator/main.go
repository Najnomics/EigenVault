package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/spf13/viper"
	"go.uber.org/zap"

	"github.com/eigenvault/avs/operator"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "./config/operator.yaml", "Path to config file")
	flag.Parse()

	// Load configuration
	config, err := loadConfig(*configPath)
	if err != nil {
		fmt.Printf("Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger
	logger, err := logging.NewZapLogger(logging.Development)
	if err != nil {
		fmt.Printf("Failed to create logger: %v\n", err)
		os.Exit(1)
	}

	// Create operator
	op, err := operator.NewOperator(*config, logger)
	if err != nil {
		logger.Error("Failed to create operator", "error", err)
		os.Exit(1)
	}

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		logger.Info("Received shutdown signal", "signal", sig)
		cancel()
	}()

	// Start operator
	logger.Info("Starting EigenVault operator")
	if err := op.Start(ctx); err != nil {
		logger.Error("Operator failed", "error", err)
		os.Exit(1)
	}

	logger.Info("Operator stopped gracefully")
}

func loadConfig(configPath string) (*operator.Config, error) {
	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	// Set defaults
	viper.SetDefault("operator.ecdsa_private_key_store_path", "./keys/operator.ecdsa.key.json")
	viper.SetDefault("operator.bls_private_key_store_path", "./keys/operator.bls.key.json")
	viper.SetDefault("operator.eth_rpc_url", "https://sepolia.infura.io/v3/YOUR_INFURA_KEY")
	viper.SetDefault("operator.eth_ws_url", "wss://sepolia.infura.io/ws/v3/YOUR_INFURA_KEY")
	viper.SetDefault("operator.registry_coordinator_address", "0x0000000000000000000000000000000000000000")
	viper.SetDefault("operator.operator_state_retriever_address", "0x0000000000000000000000000000000000000000")
	viper.SetDefault("operator.aggregator_server_ip_port_address", "localhost:8090")
	viper.SetDefault("operator.register_operator_on_startup", true)
	viper.SetDefault("operator.eigen_metrics_ip_port_address", "localhost:9090")
	viper.SetDefault("operator.enable_metrics", true)
	viper.SetDefault("operator.node_api_ip_port_address", "localhost:9091")
	viper.SetDefault("operator.enable_node_api", true)
	viper.SetDefault("order_matching.min_order_size", "1000000000000000000")
	viper.SetDefault("order_matching.max_matching_delay", "30s")
	viper.SetDefault("order_matching.price_oracle", "chainlink")
	viper.SetDefault("order_matching.privacy_threshold", "50")
	viper.SetDefault("order_matching.zk_proof_required", false)
	viper.SetDefault("logging.level", "info")
	viper.SetDefault("logging.format", "json")

	if err := viper.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config operator.Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &config, nil
} 