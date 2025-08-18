// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title EigenVaultBase
/// @notice Base contract for EigenVault hooks that implements IHooks
/// @dev Provides common functionality and access control for EigenVault hooks
abstract contract EigenVaultBase is IHooks {
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    /// @notice The pool manager contract
    IPoolManager public immutable poolManager;

    /// @notice The order vault contract for encrypted order storage
    address public immutable orderVault;
    
    /// @notice The owner of the contract
    address public owner;
    
    /// @notice Default vault threshold in basis points (1% = 100 bps)
    uint256 public vaultThresholdBps = 100;

    /// @notice Mapping of pool keys to custom thresholds
    mapping(bytes32 => uint256) public poolThresholds;

    /// @notice Events
    event VaultThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PoolThresholdUpdated(bytes32 indexed poolId, uint256 oldThreshold, uint256 newThreshold);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Constructor
    /// @param _poolManager The Uniswap v4 pool manager
    /// @param _orderVault The order vault contract address
    constructor(
        IPoolManager _poolManager,
        address _orderVault
    ) {
        poolManager = _poolManager;
        orderVault = _orderVault;
        owner = msg.sender;
    }

    /// @notice Modifier to restrict access to owner only
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /// @notice Transfer ownership to a new address
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /// @notice Check if an order qualifies as a large order for vault routing
    /// @param amountSpecified The amount being swapped
    /// @param key The pool key
    /// @return Whether the order should be routed to vault
    function isLargeOrder(int256 amountSpecified, PoolKey calldata key) public view virtual returns (bool) {
        uint256 absAmount = amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
        
        // Get pool-specific threshold or use default
        bytes32 poolId = keccak256(abi.encode(key));
        uint256 threshold = poolThresholds[poolId];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
        
        // For simplicity, we'll use a fixed liquidity base
        // In production, this should query actual pool liquidity
        uint256 poolLiquidity = 1000000e18; // Mock 1M token liquidity
        uint256 thresholdAmount = (poolLiquidity * threshold) / 10000;
        
        return absAmount >= thresholdAmount;
    }

    /// @notice Get vault threshold for a pool
    /// @param key The pool key
    /// @return threshold The threshold in basis points
    function getVaultThreshold(PoolKey calldata key) external view virtual returns (uint256 threshold) {
        bytes32 poolId = keccak256(abi.encode(key));
        threshold = poolThresholds[poolId];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
    }

    /// @notice Update vault threshold (admin only)
    /// @param newThreshold The new threshold in basis points
    function updateVaultThreshold(uint256 newThreshold) external virtual onlyOwner {
        require(newThreshold > 0 && newThreshold <= 1000, "Invalid threshold"); // Max 10%
        uint256 oldThreshold = vaultThresholdBps;
        vaultThresholdBps = newThreshold;
        emit VaultThresholdUpdated(oldThreshold, newThreshold);
    }

    /// @notice Set pool-specific threshold
    /// @param key The pool key
    /// @param threshold The threshold in basis points
    function setPoolThreshold(PoolKey calldata key, uint256 threshold) external virtual onlyOwner {
        require(threshold <= 1000, "Invalid threshold");
        bytes32 poolId = keccak256(abi.encode(key));
        uint256 oldThreshold = poolThresholds[poolId];
        poolThresholds[poolId] = threshold;
        emit PoolThresholdUpdated(poolId, oldThreshold, threshold);
    }

    /// @notice Get pool ID for a pool key (public wrapper)
    function getPoolId(PoolKey calldata key) public pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    /// @notice Internal function to get pool ID
    function _getPoolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    /// @notice Validate that the caller is the order vault
    modifier onlyOrderVault() {
        require(msg.sender == orderVault, "Only order vault");
        _;
    }

    /// @notice Validate that the caller is an authorized operator
    modifier onlyAuthorizedOperator() {
        // This would check against a list of authorized operators
        // For now, we'll allow any call but in production this would be restricted
        _;
    }
} 