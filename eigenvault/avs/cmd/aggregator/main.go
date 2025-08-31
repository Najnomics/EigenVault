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

	"github.com/eigenvault/avs/aggregator"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "./config/aggregator.yaml", "Path to config file")
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

	// Create aggregator
	agg, err := aggregator.NewAggregator(*config, logger)
	if err != nil {
		logger.Error("Failed to create aggregator", "error", err)
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

	// Start aggregator
	logger.Info("Starting EigenVault aggregator")
	if err := agg.Start(ctx); err != nil {
		logger.Error("Aggregator failed", "error", err)
		os.Exit(1)
	}

	logger.Info("Aggregator stopped gracefully")
}

func loadConfig(configPath string) (*aggregator.Config, error) {
	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")

	// Set defaults
	viper.SetDefault("aggregator.server_ip_port_address", "localhost:8090")
	viper.SetDefault("aggregator.eth_rpc_url", "https://sepolia.infura.io/v3/YOUR_INFURA_KEY")
	viper.SetDefault("aggregator.registry_coordinator_address", "0x0000000000000000000000000000000000000000")
	viper.SetDefault("aggregator.operator_state_retriever_address", "0x0000000000000000000000000000000000000000")
	viper.SetDefault("aggregator.aggregator_private_key_path", "./keys/aggregator.ecdsa.key.json")
	viper.SetDefault("aggregator.eigen_metrics_ip_port_address", "localhost:9092")
	viper.SetDefault("aggregator.enable_metrics", true)
	viper.SetDefault("order_matching.response_timeout", "60s")
	viper.SetDefault("order_matching.quorum_threshold", 67)
	viper.SetDefault("order_matching.min_operators", 3)
	viper.SetDefault("order_matching.max_order_batch_size", 100)
	viper.SetDefault("order_matching.privacy_enabled", true)
	viper.SetDefault("logging.level", "info")
	viper.SetDefault("logging.format", "json")

	if err := viper.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config aggregator.Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &config, nil
} 