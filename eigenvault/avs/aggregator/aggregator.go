package aggregator

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/common"
	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"

	"github.com/eigenvault/avs/pkg/avsregistry"
)

type Aggregator struct {
	config     Config
	logger     logging.Logger
	ethClient  eth.Client
	metricsReg *prometheus.Registry

	avsWriter avsregistry.AvsRegistryChainWriter
	avsReader avsregistry.AvsRegistryChainReader

	// Task aggregation
	tasksMutex    sync.RWMutex
	tasks         map[uint32]*TaskInfo
	httpServer    *http.Server
}

type Config struct {
	ServerIpPortAddr              string `json:"server_ip_port_address"`
	EthRpcUrl                     string `json:"eth_rpc_url"`
	RegistryCoordinatorAddress    string `json:"registry_coordinator_address"`
	OperatorStateRetrieverAddress string `json:"operator_state_retriever_address"`
	AggregatorPrivateKeyPath      string `json:"aggregator_private_key_path"`
	EigenMetricsIpPortAddress     string `json:"eigen_metrics_ip_port_address"`
	EnableMetrics                 bool   `json:"enable_metrics"`
}

type TaskInfo struct {
	TaskIndex                 uint32                           `json:"taskIndex"`
	TaskId                    common.Hash                      `json:"taskId"`
	PoolId                    common.Hash                      `json:"poolId"`
	OrdersHash                common.Hash                      `json:"ordersHash"`
	TaskCreatedBlock          uint32                           `json:"taskCreatedBlock"`
	QuorumNumbers             types.QuorumNums                 `json:"quorumNumbers"`
	QuorumThresholdPercentage types.ThresholdPercentage        `json:"quorumThresholdPercentage"`
	MinOrderSize              *big.Int                         `json:"minOrderSize"`
	PrivacyThreshold          *big.Int                         `json:"privacyThreshold"`
	TaskResponses             map[types.OperatorId]TaskResponse `json:"taskResponses"`
	TaskResponsesInfo         map[types.OperatorId]TaskResponseInfo `json:"taskResponsesInfo"`
	IsCompleted               bool                             `json:"isCompleted"`
	CreatedAt                 time.Time                        `json:"createdAt"`
}

type TaskResponse struct {
	ReferenceTaskIndex uint32         `json:"referenceTaskIndex"`
	MatchedOrders      []MatchedOrder `json:"matchedOrders"`
	TotalOrders        uint32         `json:"totalOrders"`
	ExecutionPrice     *big.Int       `json:"executionPrice"`
	MatchHash          common.Hash    `json:"matchHash"`
}

type MatchedOrder struct {
	OrderId1    common.Hash    `json:"orderId1"`
	OrderId2    common.Hash    `json:"orderId2"`
	MatchPrice  *big.Int       `json:"matchPrice"`
	MatchAmount *big.Int       `json:"matchAmount"`
	Trader1     common.Address `json:"trader1"`
	Trader2     common.Address `json:"trader2"`
}

type TaskResponseInfo struct {
	TaskResponse TaskResponse        `json:"taskResponse"`
	BlsSignature types.Signature     `json:"blsSignature"`
	OperatorId   types.OperatorId    `json:"operatorId"`
}

type SignedTaskResponse struct {
	TaskResponse TaskResponse        `json:"taskResponse"`
	BlsSignature types.Signature     `json:"blsSignature"`
	OperatorId   types.OperatorId    `json:"operatorId"`
}

func NewAggregator(config Config, logger logging.Logger) (*Aggregator, error) {
	logger = logger.With("component", "aggregator")

	ethClient, err := eth.NewClient(config.EthRpcUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to create eth client: %w", err)
	}

	// Create AVS registry clients
	avsReader, err := avsregistry.NewAvsRegistryChainReader(
		common.HexToAddress(config.RegistryCoordinatorAddress),
		common.HexToAddress(config.OperatorStateRetrieverAddress),
		ethClient,
		logger,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create avs registry chain reader: %w", err)
	}

	// For the writer, we'd need the aggregator's private key
	// For now, we'll skip this as it requires key management
	var avsWriter avsregistry.AvsRegistryChainWriter

	aggregator := &Aggregator{
		config:     config,
		logger:     logger,
		ethClient:  ethClient,
		metricsReg: prometheus.NewRegistry(),
		avsWriter:  avsWriter,
		avsReader:  *avsReader,
		tasks:      make(map[uint32]*TaskInfo),
	}

	// Setup HTTP server
	router := mux.NewRouter()
	router.HandleFunc("/health", aggregator.healthHandler).Methods("GET")
	router.HandleFunc("/tasks", aggregator.getTasksHandler).Methods("GET")
	router.HandleFunc("/tasks/{taskIndex}", aggregator.getTaskHandler).Methods("GET")
	router.HandleFunc("/submit-response", aggregator.submitResponseHandler).Methods("POST")

	aggregator.httpServer = &http.Server{
		Addr:    config.ServerIpPortAddr,
		Handler: router,
	}

	return aggregator, nil
}

func (a *Aggregator) Start(ctx context.Context) error {
	a.logger.Info("Starting EigenVault aggregator", "address", a.config.ServerIpPortAddr)

	// Start HTTP server
	go func() {
		if err := a.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			a.logger.Error("HTTP server error", "error", err)
		}
	}()

	// Start task monitoring
	go a.monitorTasks(ctx)

	// Keep the aggregator running
	<-ctx.Done()
	return nil
}

func (a *Aggregator) Stop() error {
	a.logger.Info("Stopping aggregator")
	return a.httpServer.Shutdown(context.Background())
}

func (a *Aggregator) monitorTasks(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.processCompletedTasks()
		}
	}
}

func (a *Aggregator) processCompletedTasks() {
	a.tasksMutex.Lock()
	defer a.tasksMutex.Unlock()

	for taskIndex, task := range a.tasks {
		if !task.IsCompleted && a.hasQuorum(task) {
			a.completeTask(taskIndex, task)
		}
	}
}

func (a *Aggregator) hasQuorum(task *TaskInfo) bool {
	// Check if we have enough responses to reach quorum
	responseCount := len(task.TaskResponses)
	requiredResponses := int(task.QuorumThresholdPercentage) * len(task.QuorumNumbers) / 100

	return responseCount >= requiredResponses
}

func (a *Aggregator) completeTask(taskIndex uint32, task *TaskInfo) {
	a.logger.Info("Completing order matching task", "taskIndex", taskIndex)

	// Aggregate responses
	aggregatedResponse := a.aggregateResponses(task)
	
	// Submit to blockchain
	if err := a.submitToBlockchain(taskIndex, aggregatedResponse); err != nil {
		a.logger.Error("Failed to submit to blockchain", "error", err, "taskIndex", taskIndex)
		return
	}

	task.IsCompleted = true
	a.logger.Info("Order matching task completed successfully", "taskIndex", taskIndex)
}

func (a *Aggregator) aggregateResponses(task *TaskInfo) *TaskResponse {
	// For now, just return the first response
	// In a real implementation, you'd aggregate multiple responses
	for _, responseInfo := range task.TaskResponsesInfo {
		return &responseInfo.TaskResponse
	}
	return nil
}

func (a *Aggregator) submitToBlockchain(taskIndex uint32, response *TaskResponse) error {
	// This would submit the aggregated response to the blockchain
	// For now, just log it
	a.logger.Info("Submitting order matching result to blockchain", 
		"taskIndex", taskIndex,
		"totalOrders", response.TotalOrders,
		"executionPrice", response.ExecutionPrice.String(),
		"matchHash", response.MatchHash.Hex(),
	)
	return nil
}

// HTTP Handlers

func (a *Aggregator) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func (a *Aggregator) getTasksHandler(w http.ResponseWriter, r *http.Request) {
	a.tasksMutex.RLock()
	defer a.tasksMutex.RUnlock()

	tasks := make([]*TaskInfo, 0, len(a.tasks))
	for _, task := range a.tasks {
		tasks = append(tasks, task)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tasks)
}

func (a *Aggregator) getTaskHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	taskIndexStr := vars["taskIndex"]
	
	// Parse task index
	var taskIndex uint32
	if _, err := fmt.Sscanf(taskIndexStr, "%d", &taskIndex); err != nil {
		http.Error(w, "Invalid task index", http.StatusBadRequest)
		return
	}

	a.tasksMutex.RLock()
	task, exists := a.tasks[taskIndex]
	a.tasksMutex.RUnlock()

	if !exists {
		http.Error(w, "Task not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(task)
}

func (a *Aggregator) submitResponseHandler(w http.ResponseWriter, r *http.Request) {
	var signedResponse SignedTaskResponse
	if err := json.NewDecoder(r.Body).Decode(&signedResponse); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate response
	if err := a.validateResponse(&signedResponse); err != nil {
		http.Error(w, fmt.Sprintf("Invalid response: %v", err), http.StatusBadRequest)
		return
	}

	// Store response
	a.storeResponse(&signedResponse)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "response accepted"})
}

func (a *Aggregator) validateResponse(response *SignedTaskResponse) error {
	// Basic validation
	if response.TaskResponse.ReferenceTaskIndex == 0 {
		return fmt.Errorf("invalid task index")
	}
	if len(response.TaskResponse.MatchedOrders) == 0 {
		return fmt.Errorf("no matched orders")
	}
	if response.TaskResponse.ExecutionPrice == nil || response.TaskResponse.ExecutionPrice.Sign() <= 0 {
		return fmt.Errorf("invalid execution price")
	}
	if response.TaskResponse.MatchHash == (common.Hash{}) {
		return fmt.Errorf("invalid match hash")
	}

	return nil
}

func (a *Aggregator) storeResponse(response *SignedTaskResponse) {
	a.tasksMutex.Lock()
	defer a.tasksMutex.Unlock()

	taskIndex := response.TaskResponse.ReferenceTaskIndex
	
	// Create task if it doesn't exist
	if _, exists := a.tasks[taskIndex]; !exists {
		a.tasks[taskIndex] = &TaskInfo{
			TaskIndex:                 taskIndex,
			TaskId:                    common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000000"),
			PoolId:                    common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000000"),
			OrdersHash:                common.HexToHash("0x0000000000000000000000000000000000000000000000000000000000000000"),
			TaskCreatedBlock:          0,
			QuorumNumbers:             types.QuorumNums{0},
			QuorumThresholdPercentage: 67,
			MinOrderSize:              big.NewInt(1000000000000000000), // 1 ETH
			PrivacyThreshold:          big.NewInt(50), // 0.5%
			TaskResponses:             make(map[types.OperatorId]TaskResponse),
			TaskResponsesInfo:         make(map[types.OperatorId]TaskResponseInfo),
			IsCompleted:               false,
			CreatedAt:                 time.Now(),
		}
	}

	task := a.tasks[taskIndex]
	
	// Store response
	task.TaskResponses[response.OperatorId] = response.TaskResponse
	task.TaskResponsesInfo[response.OperatorId] = TaskResponseInfo{
		TaskResponse: response.TaskResponse,
		BlsSignature: response.BlsSignature,
		OperatorId:   response.OperatorId,
	}

	a.logger.Info("Order matching response stored", 
		"taskIndex", taskIndex,
		"operatorId", fmt.Sprintf("0x%x", response.OperatorId[:]),
		"totalResponses", len(task.TaskResponses),
		"matchHash", response.TaskResponse.MatchHash.Hex(),
	)
} 