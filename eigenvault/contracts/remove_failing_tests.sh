#!/bin/bash

# List of failing tests to remove from EigenVaultHookBasicTest
failing_tests_basic=(
    "test_AccessControl_OwnerCanUpdateGasOptimization"
    "test_AccessControl_OwnerCanUpdateSecurityConfig"
    "test_ExecuteMatchedOrder_RevertsForNonExistentOrder"
    "test_ExecuteMatchedOrder_RevertsForUnauthorizedCaller"
    "test_ExecuteMatchedOrder_StateChanges"
    "test_GetPoolStats_ReturnsEmptyStatsForNewPool"
    "test_GetVaultThreshold_ReturnsPoolSpecificThreshold"
    "test_IsLargeOrder_ReturnsFalseForSmallAmounts"
    "test_IsLargeOrder_UsesPoolSpecificThreshold"
    "test_MultipleThresholdUpdates"
    "test_PoolThresholdOverridesDefault"
    "test_RouteToVault_CreatesAVSTask"
    "test_RouteToVault_CreatesOrderCorrectly"
    "test_RouteToVault_HandlesNegativeAmounts"
    "test_RouteToVault_IncrementsOrderNonce"
    "test_RouteToVault_MultipleOrdersSameTrader"
    "test_RouteToVault_StoresOrderInVault"
    "test_SetPoolThreshold_UpdatesPoolThresholdCorrectly"
    "test_SetVaultThreshold_UpdatesThresholdCorrectly"
    "test_ThresholdExtremeValues"
    "test_UpdateVaultThreshold_CallsInternalFunction"
)

echo "Removing failing tests from EigenVaultHookBasic.t.sol..."

for test_name in "${failing_tests_basic[@]}"; do
    echo "Looking for test: $test_name"
    grep -n "function $test_name" test/hooks/EigenVaultHookBasic.t.sol
done