package main

import (
	"encoding/json"
	"testing"

	performerV1 "github.com/Layr-Labs/protocol-apis/gen/protos/eigenlayer/hourglass/v1/performer"
	"go.uber.org/zap/zaptest"
)

func TestEigenVaultPerformer_ValidateTask(t *testing.T) {
	logger := zaptest.NewLogger(t)
	performer := NewEigenVaultPerformer(logger)

	tests := []struct {
		name      string
		task      *performerV1.TaskRequest
		expectErr bool
	}{
		{
			name: "valid order matching task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-1"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeOrderMatching,
					Parameters: map[string]interface{}{
						"poolId": "0x1234567890123456789012345678901234567890",
						"orders": []interface{}{
							map[string]interface{}{
								"amount": "1000000000000000000",
								"price":  "100000000000000000000",
							},
						},
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "valid privacy execution task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-2"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypePrivacyExecution,
					Parameters: map[string]interface{}{
						"encryptedOrders": "0xdeadbeef",
						"privacyLevel":    "high",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "valid rewards update task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-3"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeRewardsUpdate,
					Parameters: map[string]interface{}{
						"operators": []interface{}{"0x1234", "0x5678"},
						"period":    "7d",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "valid stake validation task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-4"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeStakeValidation,
					Parameters: map[string]interface{}{
						"operator":     "0x1234567890123456789012345678901234567890",
						"stakeAmount": "32000000000000000000",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "empty task ID",
			task: &performerV1.TaskRequest{
				TaskId: []byte(""),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type:       TaskTypeOrderMatching,
					Parameters: map[string]interface{}{},
				}),
			},
			expectErr: true,
		},
		{
			name: "empty payload",
			task: &performerV1.TaskRequest{
				TaskId:  []byte("test-task"),
				Payload: []byte(""),
			},
			expectErr: true,
		},
		{
			name: "invalid task type",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type:       TaskType("invalid_type"),
					Parameters: map[string]interface{}{},
				}),
			},
			expectErr: true,
		},
		{
			name: "malformed JSON payload",
			task: &performerV1.TaskRequest{
				TaskId:  []byte("test-task"),
				Payload: []byte("{invalid json}"),
			},
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := performer.ValidateTask(tt.task)
			if (err != nil) != tt.expectErr {
				t.Errorf("ValidateTask() error = %v, expectErr %v", err, tt.expectErr)
			}
		})
	}
}

func TestEigenVaultPerformer_HandleTask(t *testing.T) {
	logger := zaptest.NewLogger(t)
	performer := NewEigenVaultPerformer(logger)

	tests := []struct {
		name      string
		task      *performerV1.TaskRequest
		expectErr bool
	}{
		{
			name: "handle order matching task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-1"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeOrderMatching,
					Parameters: map[string]interface{}{
						"poolId": "0x1234567890123456789012345678901234567890",
						"orders": []interface{}{
							map[string]interface{}{
								"amount": "1000000000000000000",
								"price":  "100000000000000000000",
							},
						},
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "handle privacy execution task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-2"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypePrivacyExecution,
					Parameters: map[string]interface{}{
						"encryptedOrders": "0xdeadbeef",
						"privacyLevel":    "high",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "handle rewards update task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-3"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeRewardsUpdate,
					Parameters: map[string]interface{}{
						"operators": []interface{}{"0x1234", "0x5678"},
						"period":    "7d",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "handle stake validation task",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task-4"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeStakeValidation,
					Parameters: map[string]interface{}{
						"operator":     "0x1234567890123456789012345678901234567890",
						"stakeAmount": "32000000000000000000",
					},
				}),
			},
			expectErr: false,
		},
		{
			name: "handle unknown task type",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type:       TaskType("unknown_type"),
					Parameters: map[string]interface{}{},
				}),
			},
			expectErr: true,
		},
		{
			name: "handle malformed payload",
			task: &performerV1.TaskRequest{
				TaskId:  []byte("test-task"),
				Payload: []byte("{invalid json}"),
			},
			expectErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := performer.HandleTask(tt.task)
			if (err != nil) != tt.expectErr {
				t.Errorf("HandleTask() error = %v, expectErr %v", err, tt.expectErr)
				return
			}
			if !tt.expectErr {
				if resp == nil {
					t.Error("HandleTask() returned nil response for valid task")
					return
				}
				if len(resp.TaskId) == 0 {
					t.Error("HandleTask() returned empty task ID")
				}
				if len(resp.Result) == 0 {
					t.Error("HandleTask() returned empty result")
				}
			}
		})
	}
}

func TestParseTaskPayload(t *testing.T) {
	tests := []struct {
		name      string
		task      *performerV1.TaskRequest
		expectErr bool
		expected  *TaskPayload
	}{
		{
			name: "valid order matching payload",
			task: &performerV1.TaskRequest{
				TaskId: []byte("test-task"),
				Payload: mustMarshalJSON(t, TaskPayload{
					Type: TaskTypeOrderMatching,
					Parameters: map[string]interface{}{
						"poolId": "0x1234",
						"orders": []interface{}{"order1", "order2"},
					},
				}),
			},
			expectErr: false,
			expected: &TaskPayload{
				Type: TaskTypeOrderMatching,
				Parameters: map[string]interface{}{
					"poolId": "0x1234",
					"orders": []interface{}{"order1", "order2"},
				},
			},
		},
		{
			name: "invalid JSON payload",
			task: &performerV1.TaskRequest{
				TaskId:  []byte("test-task"),
				Payload: []byte("{invalid json}"),
			},
			expectErr: true,
			expected:  nil,
		},
		{
			name: "empty payload",
			task: &performerV1.TaskRequest{
				TaskId:  []byte("test-task"),
				Payload: []byte(""),
			},
			expectErr: true,
			expected:  nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := parseTaskPayload(tt.task)
			if (err != nil) != tt.expectErr {
				t.Errorf("parseTaskPayload() error = %v, expectErr %v", err, tt.expectErr)
				return
			}
			if !tt.expectErr {
				if result == nil {
					t.Error("parseTaskPayload() returned nil for valid payload")
					return
				}
				if result.Type != tt.expected.Type {
					t.Errorf("parseTaskPayload() type = %v, expected %v", result.Type, tt.expected.Type)
				}
			}
		})
	}
}

func TestTaskTypes(t *testing.T) {
	expectedTypes := []TaskType{
		TaskTypeOrderMatching,
		TaskTypePrivacyExecution,
		TaskTypeRewardsUpdate,
		TaskTypeStakeValidation,
	}

	expectedValues := []string{
		"order_matching",
		"privacy_execution",
		"rewards_update",
		"stake_validation",
	}

	for i, taskType := range expectedTypes {
		if string(taskType) != expectedValues[i] {
			t.Errorf("TaskType %v = %v, expected %v", taskType, string(taskType), expectedValues[i])
		}
	}
}

func TestEigenVaultPerformer_TaskHandlers(t *testing.T) {
	logger := zaptest.NewLogger(t)
	performer := NewEigenVaultPerformer(logger)

	testTask := &performerV1.TaskRequest{
		TaskId: []byte("test-task"),
	}

	testPayload := &TaskPayload{
		Type: TaskTypeOrderMatching,
		Parameters: map[string]interface{}{
			"poolId": "0x1234",
			"orders": []interface{}{"order1"},
		},
	}

	t.Run("handleOrderMatching", func(t *testing.T) {
		result, err := performer.handleOrderMatching(testTask, testPayload)
		if err != nil {
			t.Errorf("handleOrderMatching() error = %v", err)
		}
		if len(result) == 0 {
			t.Error("handleOrderMatching() returned empty result")
		}
	})

	t.Run("handlePrivacyExecution", func(t *testing.T) {
		result, err := performer.handlePrivacyExecution(testTask, testPayload)
		if err != nil {
			t.Errorf("handlePrivacyExecution() error = %v", err)
		}
		if len(result) == 0 {
			t.Error("handlePrivacyExecution() returned empty result")
		}
	})

	t.Run("handleRewardsUpdate", func(t *testing.T) {
		result, err := performer.handleRewardsUpdate(testTask, testPayload)
		if err != nil {
			t.Errorf("handleRewardsUpdate() error = %v", err)
		}
		if len(result) == 0 {
			t.Error("handleRewardsUpdate() returned empty result")
		}
	})

	t.Run("handleStakeValidation", func(t *testing.T) {
		result, err := performer.handleStakeValidation(testTask, testPayload)
		if err != nil {
			t.Errorf("handleStakeValidation() error = %v", err)
		}
		if len(result) == 0 {
			t.Error("handleStakeValidation() returned empty result")
		}
	})
}

// Helper function to marshal JSON and handle errors in tests
func mustMarshalJSON(t *testing.T, v interface{}) []byte {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("Failed to marshal JSON: %v", err)
	}
	return data
}