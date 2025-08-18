// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @title IEigenVaultHook
/// @notice Interface for the EigenVault Hook contract
interface IEigenVaultHook {
    /// @notice Emitted when a large order is routed to the vault
    event OrderRoutedToVault(
        address indexed trader,
        bytes32 indexed orderId,
        PoolKey indexed poolKey,
        bool zeroForOne,
        uint256 amountSpecified,
        bytes32 commitment
    );

    /// @notice Emitted when a vault order is executed
    event VaultOrderExecuted(
        bytes32 indexed orderId,
        address indexed trader,
        uint256 amountIn,
        bytes32 matchHash,
        address[] operators
    );

    /// @notice Emitted when an order is executed via the pool manager
    event OrderExecuted(
        address indexed trader,
        PoolKey indexed poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes32 matchHash
    );

    /// @notice Emitted when an order falls back to AMM
    event OrderFallbackToAMM(
        bytes32 indexed orderId,
        address indexed trader,
        string reason
    );

    /// @notice Structure representing a private order
    struct PrivateOrder {
        address trader;
        PoolKey poolKey;
        bool zeroForOne;
        int256 amountSpecified;
        bytes32 commitment; // Hash of order details + nonce
        uint256 deadline;
        uint256 timestamp;
        bool executed;
    }

    /// @notice Check if an order qualifies as a large order for vault routing
    /// @param amountSpecified The amount being swapped
    /// @param key The pool key
    /// @return Whether the order should be routed to vault
    function isLargeOrder(int256 amountSpecified, PoolKey calldata key) external view returns (bool);

    /// @notice Route a large order to the AVS for private matching
    /// @param trader The trader address
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Additional hook data
    /// @return orderId The unique order identifier
    function routeToVault(
        address trader,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes32 orderId);

    /// @notice Execute a matched vault order
    /// @param orderId The order identifier
    /// @param proof The ZK proof of valid matching
    /// @param signatures The operator signatures
    function executeVaultOrder(
        bytes32 orderId,
        bytes calldata proof,
        bytes calldata signatures
    ) external;

    /// @notice Fallback to AMM execution for unmatched orders
    /// @param orderId The order identifier
    function fallbackToAMM(bytes32 orderId) external;

    /// @notice Get order details
    /// @param orderId The order identifier
    /// @return order The private order details
    function getOrder(bytes32 orderId) external view returns (PrivateOrder memory order);

    /// @notice Get vault threshold for a pool
    /// @param key The pool key
    /// @return threshold The threshold in basis points
    function getVaultThreshold(PoolKey calldata key) external view returns (uint256 threshold);

    /// @notice Update vault threshold (admin only)
    /// @param newThreshold The new threshold in basis points
    function updateVaultThreshold(uint256 newThreshold) external;
}