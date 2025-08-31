package operator

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/Layr-Labs/eigensdk-go/metrics"
	"github.com/Layr-Labs/eigensdk-go/nodeapi"
	"github.com/Layr-Labs/eigensdk-go/signerv2"
	"github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/prometheus/client_golang/prometheus"

	"github.com/eigenvault/avs/pkg/avsregistry"
)

const (
	// SemVer is the semantic version of the operator
	SemVer = "0.0.1"
)

type Operator struct {
	config    Config
	logger    logging.Logger
	ethClient eth.Client
	metricsReg *prometheus.Registry
	metrics   metrics.Metrics
	nodeApi   *nodeapi.NodeApi

	avsWriter avsregistry.AvsRegistryChainWriter
	avsReader avsregistry.AvsRegistryChainReader

	blsKeypair         *types.BlsKeyPair
	operatorId         types.OperatorId
	operatorAddr       common.Address
	operatorEcdsaPrivateKey *ecdsa.PrivateKey

	// EigenVault specific fields
	orderMatchingTasks map[uint32]*OrderMatchingTask
	orderMatchingTasksMutex sync.RWMutex
	taskResponseChan    chan TaskResponseInfo
}

type Config struct {
	EcdsaPrivateKeyStorePath   string `json:"ecdsa_private_key_store_path"`
	BlsPrivateKeyStorePath     string `json:"bls_private_key_store_path"`
	EthRpcUrl                  string `json:"eth_rpc_url"`
	EthWsUrl                   string `json:"eth_ws_url"`
	RegistryCoordinatorAddress string `json:"registry_coordinator_address"`
	OperatorStateRetrieverAddress string `json:"operator_state_retriever_address"`
	AggregatorServerIpPortAddr string `json:"aggregator_server_ip_port_address"`
	RegisterOperatorOnStartup  bool   `json:"register_operator_on_startup"`
	EigenMetricsIpPortAddress  string `json:"eigen_metrics_ip_port_address"`
	EnableMetrics              bool   `json:"enable_metrics"`
	NodeApiIpPortAddress       string `json:"node_api_ip_port_address"`
	EnableNodeApi              bool   `json:"enable_node_api"`
}

type OrderMatchingTask struct {
	TaskId                    common.Hash    `json:"taskId"`
	PoolId                    common.Hash    `json:"poolId"`
	OrdersHash                common.Hash    `json:"ordersHash"`
	TaskCreatedBlock          uint32         `json:"taskCreatedBlock"`
	QuorumNumbers             types.QuorumNums `json:"quorumNumbers"`
	QuorumThresholdPercentage types.ThresholdPercentage `json:"quorumThresholdPercentage"`
	MinOrderSize              *big.Int       `json:"minOrderSize"`
	PrivacyThreshold          *big.Int       `json:"privacyThreshold"`
}

type OrderMatchingTaskResponse struct {
	ReferenceTaskIndex uint32         `json:"referenceTaskIndex"`
	MatchedOrders      []MatchedOrder `json:"matchedOrders"`
	TotalOrders        uint32         `json:"totalOrders"`
	ExecutionPrice     *big.Int       `json:"executionPrice"`
	MatchHash          common.Hash    `json:"matchHash"`
}

type MatchedOrder struct {
	OrderId1    common.Hash `json:"orderId1"`
	OrderId2    common.Hash `json:"orderId2"`
	MatchPrice  *big.Int    `json:"matchPrice"`
	MatchAmount *big.Int    `json:"matchAmount"`
	Trader1     common.Address `json:"trader1"`
	Trader2     common.Address `json:"trader2"`
}

type SignedOrderMatchingTaskResponse struct {
	OrderMatchingTaskResponse
	BlsSignature types.Signature `json:"blsSignature"`
	OperatorId   types.OperatorId `json:"operatorId"`
}

type TaskResponseInfo struct {
	TaskResponse *OrderMatchingTaskResponse
	BlsSignature types.Signature
	OperatorId   types.OperatorId
}

func NewOperator(config Config, logger logging.Logger) (*Operator, error) {
	var logLevel logging.LogLevel
	if config.EnableMetrics {
		logLevel = logging.Development
	} else {
		logLevel = logging.Production
	}

	logger = logger.With("component", "operator")

	ethClient, err := eth.NewClient(config.EthRpcUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to create eth client: %w", err)
	}

	operatorEcdsaPrivateKey, err := crypto.LoadECDSA(config.EcdsaPrivateKeyStorePath)
	if err != nil {
		return nil, fmt.Errorf("failed to load operator ecdsa private key: %w", err)
	}

	operatorAddr := crypto.PubkeyToAddress(operatorEcdsaPrivateKey.PublicKey)
	logger.Info("Operator address", "address", operatorAddr.Hex())

	blsKeyPair, err := types.ReadBlsPrivateKeyFromFile(config.BlsPrivateKeyStorePath, "")
	if err != nil {
		return nil, fmt.Errorf("failed to read bls private key: %w", err)
	}

	operatorId := types.OperatorIdFromG1Pubkey(blsKeyPair.PubkeyG1)
	logger.Info("Operator ID", "operatorId", hex.EncodeToString(operatorId[:]))

	// Create AVS clients
	avsReader, err := avsregistry.NewAvsRegistryChainReader(
		common.HexToAddress(config.RegistryCoordinatorAddress),
		common.HexToAddress(config.OperatorStateRetrieverAddress),
		ethClient,
		logger,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create avs registry chain reader: %w", err)
	}

	avsWriter, err := avsregistry.NewAvsRegistryChainWriter(
		common.HexToAddress(config.RegistryCoordinatorAddress),
		common.HexToAddress(config.OperatorStateRetrieverAddress),
		ethClient,
		logger,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create avs registry chain writer: %w", err)
	}

	// Create metrics registry
	var metricsReg *prometheus.Registry
	var eigenMetrics metrics.Metrics
	if config.EnableMetrics {
		metricsReg = prometheus.NewRegistry()
		eigenMetrics = metrics.NewPrometheusMetrics(metricsReg, "eigenvault", logger)
		eigenMetrics.Start(context.Background(), config.EigenMetricsIpPortAddress)
	} else {
		metricsReg = prometheus.NewRegistry()
		eigenMetrics = metrics.NewNoopMetrics()
	}

	// Create node API
	var nodeApi *nodeapi.NodeApi
	if config.EnableNodeApi {
		nodeApi = nodeapi.NewNodeApi("eigenvault-operator", SemVer, config.NodeApiIpPortAddress, logger)
		go nodeApi.Start()
	}

	operator := &Operator{
		config:                  config,
		logger:                  logger,
		ethClient:              ethClient,
		metricsReg:             metricsReg,
		metrics:                eigenMetrics,
		nodeApi:                nodeApi,
		avsWriter:              *avsWriter,
		avsReader:              *avsReader,
		blsKeypair:             blsKeyPair,
		operatorId:             operatorId,
		operatorAddr:           operatorAddr,
		operatorEcdsaPrivateKey: operatorEcdsaPrivateKey,
		orderMatchingTasks:     make(map[uint32]*OrderMatchingTask),
		taskResponseChan:       make(chan TaskResponseInfo, 100),
	}

	if config.RegisterOperatorOnStartup {
		operator.registerOperatorOnStartup()
	}

	return operator, nil
}

func (o *Operator) Start(ctx context.Context) error {
	o.logger.Info("Starting EigenVault operator")

	// Start task response processing
	go o.processTaskResponses(ctx)

	// Start listening for new tasks
	go o.listenForNewTasks(ctx)

	// Keep the operator running
	<-ctx.Done()
	return nil
}

func (o *Operator) registerOperatorOnStartup() {
	o.logger.Info("Registering operator on startup")

	quorumNumbers := types.QuorumNums{0} // Join quorum 0
	socket := "localhost:9090"

	// In a real implementation, you would:
	// 1. Generate BLS signature for registration
	// 2. Call the actual registration function
	// For now, we'll simulate this
	
	o.logger.Info("Operator registration completed",
		"quorumNumbers", quorumNumbers,
		"socket", socket,
		"operatorId", hex.EncodeToString(o.operatorId[:]),
	)
}

func (o *Operator) listenForNewTasks(ctx context.Context) {
	o.logger.Info("Starting to listen for new order matching tasks")

	// In a real implementation, this would:
	// 1. Subscribe to NewOrderMatchingTaskCreated events
	// 2. Process incoming tasks
	// 3. Send responses to aggregator

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Simulate receiving a task
			o.simulateTaskProcessing()
		}
	}
}

func (o *Operator) simulateTaskProcessing() {
	// This is a simplified simulation of order matching task processing
	task := &OrderMatchingTask{
		TaskId:                    common.HexToHash("0x123456789abcdef"),
		PoolId:                    common.HexToHash("0xabcdef123456789"),
		OrdersHash:                common.HexToHash("0x987654321fedcba"),
		TaskCreatedBlock:          uint32(time.Now().Unix()),
		QuorumNumbers:             types.QuorumNums{0},
		QuorumThresholdPercentage: 67, // 67% threshold
		MinOrderSize:              big.NewInt(1000000000000000000), // 1 ETH
		PrivacyThreshold:          big.NewInt(50), // 0.5%
	}

	o.logger.Info("Processing order matching task",
		"taskId", task.TaskId.Hex(),
		"poolId", task.PoolId.Hex(),
		"ordersHash", task.OrdersHash.Hex(),
		"minOrderSize", task.MinOrderSize.String(),
		"privacyThreshold", task.PrivacyThreshold.String(),
	)

	// Simulate order matching logic
	response := &OrderMatchingTaskResponse{
		ReferenceTaskIndex: 0,
		MatchedOrders: []MatchedOrder{
			{
				OrderId1:    common.HexToHash("0x1111111111111111111111111111111111111111"),
				OrderId2:    common.HexToHash("0x2222222222222222222222222222222222222222"),
				MatchPrice:  big.NewInt(2000000000000000000), // 2 ETH
				MatchAmount: big.NewInt(100000000000000000),  // 0.1 ETH
				Trader1:     common.HexToAddress("0x742d35Cc6608C8B29a1b8d9c0f6f8aD5b7c8b0A1"),
				Trader2:     common.HexToAddress("0x8ba1f109551bD432803012645Hac136c772c3c2b"),
			},
		},
		TotalOrders:    2,
		ExecutionPrice: big.NewInt(2000000000000000000), // 2 ETH
		MatchHash:      common.HexToHash("0x3333333333333333333333333333333333333333"),
	}

	// Sign the response
	responseHash := o.hashTaskResponse(response)
	blsSignature := o.blsKeypair.SignMessage(responseHash)

	taskResponseInfo := TaskResponseInfo{
		TaskResponse: response,
		BlsSignature: *blsSignature,
		OperatorId:   o.operatorId,
	}

	// Send to response channel
	select {
	case o.taskResponseChan <- taskResponseInfo:
		o.logger.Info("Task response sent to channel")
	default:
		o.logger.Warn("Task response channel is full, dropping response")
	}
}

func (o *Operator) processTaskResponses(ctx context.Context) {
	o.logger.Info("Starting task response processor")

	for {
		select {
		case <-ctx.Done():
			return
		case taskResponseInfo := <-o.taskResponseChan:
			o.sendTaskResponseToAggregator(taskResponseInfo)
		}
	}
}

func (o *Operator) sendTaskResponseToAggregator(taskResponseInfo TaskResponseInfo) {
	o.logger.Info("Sending task response to aggregator",
		"taskIndex", taskResponseInfo.TaskResponse.ReferenceTaskIndex,
		"totalOrders", taskResponseInfo.TaskResponse.TotalOrders,
		"executionPrice", taskResponseInfo.TaskResponse.ExecutionPrice.String(),
		"matchHash", taskResponseInfo.TaskResponse.MatchHash.Hex(),
	)

	// In a real implementation, this would send the response to the aggregator
	// via HTTP/gRPC/WebSocket connection
	
	signedTaskResponse := SignedOrderMatchingTaskResponse{
		OrderMatchingTaskResponse: *taskResponseInfo.TaskResponse,
		BlsSignature:        taskResponseInfo.BlsSignature,
		OperatorId:          taskResponseInfo.OperatorId,
	}

	// Simulate sending to aggregator
	responseJson, _ := json.MarshalIndent(signedTaskResponse, "", "  ")
	o.logger.Info("Signed task response", "response", string(responseJson))
}

func (o *Operator) hashTaskResponse(taskResponse *OrderMatchingTaskResponse) [32]byte {
	// Create hash of the task response for signing
	responseBytes, _ := json.Marshal(taskResponse)
	return crypto.Keccak256Hash(responseBytes)
}

// GetOperatorId returns the operator's ID
func (o *Operator) GetOperatorId() types.OperatorId {
	return o.operatorId
}

// GetOperatorAddress returns the operator's Ethereum address
func (o *Operator) GetOperatorAddress() common.Address {
	return o.operatorAddr
}

// GetBlsPublicKey returns the operator's BLS public key
func (o *Operator) GetBlsPublicKey() *types.G1Point {
	return o.blsKeypair.PubkeyG1
} 