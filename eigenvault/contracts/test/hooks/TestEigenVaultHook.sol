// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../src/hooks/EigenVaultHook.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/**
 * @title Test version of EigenVaultHook that skips address validation
 * @notice This allows deployment to any address for testing purposes
 */
contract TestEigenVaultHook is EigenVaultHook {
    
    constructor(
        IPoolManager _poolManager,
        address _orderVault,
        address _avsServiceManager
    ) EigenVaultHook(
        _poolManager,
        _orderVault,
        _avsServiceManager
    ) {}
    
    /// @dev Override to skip hook address validation during testing
    function validateHookAddress(BaseHook) internal pure override {
        // Skip validation for testing
    }
    
    // Test wrapper functions that expose internal functionality for testing
    function testBeforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(sender, key, params, hookData);
    }
}