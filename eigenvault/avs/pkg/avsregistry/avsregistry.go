package avsregistry

import (
	"context"
	"fmt"
	"math/big"
	"strings"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

// EigenVault AVS Service Manager ABI
const eigenVaultAVSServiceManagerABI = `[
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "_avsDirectory",
				"type": "address"
			}
		],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "",
				"type": "uint32"
			}
		],
		"name": "orderMatchingTasks",
		"outputs": [
			{
				"internalType": "bytes32",
				"name": "taskId",
				"type": "bytes32"
			},
			{
				"internalType": "bytes32",
				"name": "poolId",
				"type": "bytes32"
			},
			{
				"internalType": "bytes32",
				"name": "ordersHash",
				"type": "bytes32"
			},
			{
				"internalType": "uint32",
				"name": "taskCreatedBlock",
				"type": "uint32"
			},
			{
				"internalType": "uint256",
				"name": "deadline",
				"type": "uint256"
			},
			{
				"internalType": "bool",
				"name": "completed",
				"type": "bool"
			},
			{
				"internalType": "uint256",
				"name": "minOrderSize",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "privacyThreshold",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "taskIndex",
				"type": "uint32"
			},
			{
				"internalType": "bytes32",
				"name": "matchHash",
				"type": "bytes32"
			},
			{
				"internalType": "uint256",
				"name": "executionPrice",
				"type": "uint256"
			},
			{
				"internalType": "bytes",
				"name": "signature",
				"type": "bytes"
			}
		],
		"name": "submitTaskResponse",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "operator",
				"type": "address"
			}
		],
		"name": "operatorRegistered",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "getRegisteredOperators",
		"outputs": [
			{
				"internalType": "address[]",
				"name": "",
				"type": "address[]"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint32",
				"name": "taskIndex",
				"type": "uint32"
			},
			{
				"internalType": "address",
				"name": "operator",
				"type": "address"
			}
		],
		"name": "getTaskResponse",
		"outputs": [
			{
				"components": [
					{
						"internalType": "address",
						"name": "operator",
						"type": "address"
					},
					{
						"internalType": "bytes32",
						"name": "taskId",
						"type": "bytes32"
					},
					{
						"internalType": "bytes32",
						"name": "matchHash",
						"type": "bytes32"
					},
					{
						"internalType": "uint256",
						"name": "executionPrice",
						"type": "uint256"
					},
					{
						"internalType": "bytes",
						"name": "signature",
						"type": "bytes"
					},
					{
						"internalType": "uint256",
						"name": "timestamp",
						"type": "uint256"
					}
				],
				"internalType": "struct EigenVaultAVSServiceManager.TaskResponse",
				"name": "",
				"type": "tuple"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
]`

type AvsRegistryChainReader struct {
	avsServiceManagerAddress common.Address
	ethClient               eth.Client
	logger                  logging.Logger
	avsServiceManagerABI    abi.ABI
}

type AvsRegistryChainWriter struct {
	avsServiceManagerAddress common.Address
	ethClient               eth.Client
	logger                  logging.Logger
	avsServiceManagerABI    abi.ABI
}

func NewAvsRegistryChainReader(
	avsServiceManagerAddress common.Address,
	operatorStateRetrieverAddress common.Address,
	ethClient eth.Client,
	logger logging.Logger,
) (*AvsRegistryChainReader, error) {
	avsServiceManagerABI, err := abi.JSON(strings.NewReader(eigenVaultAVSServiceManagerABI))
	if err != nil {
		return nil, fmt.Errorf("failed to parse ABI: %w", err)
	}

	return &AvsRegistryChainReader{
		avsServiceManagerAddress: avsServiceManagerAddress,
		ethClient:               ethClient,
		logger:                  logger,
		avsServiceManagerABI:    avsServiceManagerABI,
	}, nil
}

func NewAvsRegistryChainWriter(
	avsServiceManagerAddress common.Address,
	operatorStateRetrieverAddress common.Address,
	ethClient eth.Client,
	logger logging.Logger,
) (*AvsRegistryChainWriter, error) {
	avsServiceManagerABI, err := abi.JSON(strings.NewReader(eigenVaultAVSServiceManagerABI))
	if err != nil {
		return nil, fmt.Errorf("failed to parse ABI: %w", err)
	}

	return &AvsRegistryChainWriter{
		avsServiceManagerAddress: avsServiceManagerAddress,
		ethClient:               ethClient,
		logger:                  logger,
		avsServiceManagerABI:    avsServiceManagerABI,
	}, nil
}

// Reader methods

func (r *AvsRegistryChainReader) GetOperatorStake(operator common.Address) (*big.Int, error) {
	// For now, return a mock value
	// In a real implementation, this would query the actual contract
	return big.NewInt(32e18), nil // 32 ETH
}

func (r *AvsRegistryChainReader) IsOperatorRegistered(operator common.Address) (bool, error) {
	// For now, return a mock value
	// In a real implementation, this would query the actual contract
	return true, nil
}

func (r *AvsRegistryChainReader) GetRegisteredOperators() ([]common.Address, error) {
	// For now, return mock values
	// In a real implementation, this would query the actual contract
	return []common.Address{
		common.HexToAddress("0x742d35Cc6608C8B29a1b8d9c0f6f8aD5b7c8b0A1"),
		common.HexToAddress("0x8ba1f109551bD432803012645Hac136c772c3c2b"),
		common.HexToAddress("0x1234567890123456789012345678901234567890"),
	}, nil
}

func (r *AvsRegistryChainReader) GetOrderMatchingTask(taskIndex uint32) (map[string]interface{}, error) {
	// For now, return a mock task
	// In a real implementation, this would query the actual contract
	return map[string]interface{}{
		"taskId":             common.HexToHash("0x123456789abcdef"),
		"poolId":             common.HexToHash("0xabcdef123456789"),
		"ordersHash":         common.HexToHash("0x987654321fedcba"),
		"taskCreatedBlock":   uint32(12345),
		"deadline":           big.NewInt(1234567890),
		"completed":          false,
		"minOrderSize":       big.NewInt(1000000000000000000), // 1 ETH
		"privacyThreshold":   big.NewInt(50), // 0.5%
	}, nil
}

// Writer methods

func (w *AvsRegistryChainWriter) RegisterOperator(operator common.Address, operatorSignature []byte) error {
	// For now, just log the registration
	// In a real implementation, this would call the actual contract
	w.logger.Info("Registering operator", "operator", operator.Hex())
	return nil
}

func (w *AvsRegistryChainWriter) DeregisterOperator(operator common.Address) error {
	// For now, just log the deregistration
	// In a real implementation, this would call the actual contract
	w.logger.Info("Deregistering operator", "operator", operator.Hex())
	return nil
}

func (w *AvsRegistryChainWriter) SubmitTaskResponse(
	taskIndex uint32,
	matchHash common.Hash,
	executionPrice *big.Int,
	signature []byte,
) error {
	// For now, just log the submission
	// In a real implementation, this would call the actual contract
	w.logger.Info("Submitting task response",
		"taskIndex", taskIndex,
		"matchHash", matchHash.Hex(),
		"executionPrice", executionPrice.String(),
	)
	return nil
}

func (w *AvsRegistryChainWriter) CreateOrderMatchingTask(
	taskId common.Hash,
	poolId common.Hash,
	ordersHash common.Hash,
	minOrderSize *big.Int,
	privacyThreshold *big.Int,
) (uint32, error) {
	// For now, just log the task creation
	// In a real implementation, this would call the actual contract
	w.logger.Info("Creating order matching task",
		"taskId", taskId.Hex(),
		"poolId", poolId.Hex(),
		"ordersHash", ordersHash.Hex(),
		"minOrderSize", minOrderSize.String(),
		"privacyThreshold", privacyThreshold.String(),
	)
	return 1, nil // Return mock task index
} 