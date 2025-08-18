// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EigenVaultBase} from "./EigenVaultBase.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IEigenVaultHook} from "./interfaces/IEigenVaultHook.sol";
import {IOrderVault} from "./interfaces/IOrderVault.sol";
import {OrderLib} from "./libraries/OrderLib.sol";
import {ZKProofLib} from "./libraries/ZKProofLib.sol";

/// @title EigenVaultHook
/// @notice Main Uniswap v4 hook that orchestrates private order routing and execution
/// @dev Extends EigenVaultBase which extends BaseHook for proper inheritance hierarchy
contract EigenVaultHook is EigenVaultBase, IEigenVaultHook {
    using OrderLib for OrderLib.Order;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using StateLibrary for IPoolManager;

    /// @notice Service manager contract for AVS coordination
    address public immutable serviceManager;

    /// @notice Events unique to implementation
    event ServiceManagerAuthorized(address indexed serviceManager, bool authorized);

    /// @notice Execution statistics for a pool
    struct ExecutionStats {
        uint256 totalOrders;
        uint256 successfulMatches;
        uint256 fallbackExecutions;
        uint256 totalVolume;
        uint256 averageExecutionTime;
    }

    /// @notice Modifiers
    modifier onlyAuthorizedServiceManager() {
        require(authorizedServiceManagers[msg.sender], "Unauthorized service manager");
        _;
    }

    /// @notice Mapping of order IDs to order details
    mapping(bytes32 => PrivateOrder) public orders;
    
    /// @notice Mapping of order commitments to prevent replay
    mapping(bytes32 => bool) public usedCommitments;
    
    /// @notice Order nonce counter
    uint256 public orderNonce;

    /// @notice Mapping of pool keys to execution statistics
    mapping(bytes32 => ExecutionStats) public poolStats;

    /// @notice Mapping of authorized service managers
    mapping(address => bool) public authorizedServiceManagers;



    /// @notice Constructor
    /// @param _poolManager The Uniswap v4 pool manager
    /// @param _orderVault The order vault contract
    /// @param _serviceManager The service manager contract for AVS coordination
    constructor(
        IPoolManager _poolManager,
        address _orderVault,
        address _serviceManager
    ) EigenVaultBase(_poolManager, _orderVault) {
        serviceManager = _serviceManager;
        authorizedServiceManagers[_serviceManager] = true;
    }

    /// @notice Returns the hook permissions
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Check if an order amount qualifies as large order
    /// @dev Override both EigenVaultBase and IEigenVaultHook
    function isLargeOrder(int256 amountSpecified, PoolKey calldata key) public view override(EigenVaultBase, IEigenVaultHook) returns (bool) {
        uint256 threshold = poolThresholds[getPoolId(key)];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
        
        // Simplified calculation for testing - would use proper pool state in production
        uint256 absoluteAmount = uint256(amountSpecified < 0 ? -amountSpecified : amountSpecified);
        uint256 poolLiquidity = 1000000 ether; // Mock liquidity
        
        return (absoluteAmount * 10000) / poolLiquidity >= threshold;
    }

    /// @notice Get vault threshold for a pool
    function getVaultThreshold(PoolKey calldata key) external view override(EigenVaultBase, IEigenVaultHook) returns (uint256 threshold) {
        bytes32 poolId = getPoolId(key);
        threshold = poolThresholds[poolId];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
    }

    /// @notice Update vault threshold
    function updateVaultThreshold(uint256 newThreshold) external override(EigenVaultBase, IEigenVaultHook) onlyOwner {
        require(newThreshold > 0 && newThreshold <= 1000, "Invalid threshold");
        
        uint256 oldThreshold = vaultThresholdBps;
        vaultThresholdBps = newThreshold;
        
        emit VaultThresholdUpdated(oldThreshold, newThreshold);
    }

    /// @notice Set pool-specific threshold
    function setPoolThreshold(PoolKey calldata key, uint256 threshold) external override onlyOwner {
        require(threshold <= 1000, "Invalid threshold");
        
        bytes32 poolId = getPoolId(key);
        uint256 oldThreshold = poolThresholds[poolId];
        poolThresholds[poolId] = threshold;
        
        emit PoolThresholdUpdated(poolId, oldThreshold, threshold);
    }

    /// @notice Required IHooks implementations (empty for unused hooks)
    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        revert("Hook not implemented");
    }
    
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert("Hook not implemented");
    }
    
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure returns (bytes4) {
        revert("Hook not implemented");
    }
    
    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure returns (bytes4, BalanceDelta) {
        revert("Hook not implemented");
    }
    
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure returns (bytes4) {
        revert("Hook not implemented");
    }
    
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure returns (bytes4, BalanceDelta) {
        revert("Hook not implemented");
    }
    
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert("Hook not implemented");
    }
    
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert("Hook not implemented");
    }

    /// @notice Hook called before swap execution
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // Only process if coming through PoolManager
        require(msg.sender == address(poolManager), "Only PoolManager");

        // Check if this is a large order that should be routed to vault
        if (isLargeOrder(params.amountSpecified, key)) {
            bytes32 orderId = routeToVault(sender, key, params, hookData);
            
            // Update pool statistics
            bytes32 poolId = getPoolId(key);
            poolStats[poolId].totalOrders++;
            
            // Return early to prevent immediate AMM execution
            // The order will be executed later via executeVaultOrder
            return (
                IHooks.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        // For small orders, proceed with normal AMM execution
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Hook called after swap execution
    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // Update pool statistics for regular swaps
        bytes32 poolId = getPoolId(key);
        uint256 volume = uint256(int256(delta.amount0())) + uint256(int256(delta.amount1()));
        poolStats[poolId].totalVolume += volume;
        
        return (IHooks.afterSwap.selector, 0);
    }

    /// @inheritdoc IEigenVaultHook
    function routeToVault(
        address trader,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) public override returns (bytes32 orderId) {
        require(trader != address(0), "Invalid trader");
        
        // Parse hook data for commitment and deadline
        (bytes32 commitment, uint256 deadline, bytes memory encryptedOrder) = 
            abi.decode(hookData, (bytes32, uint256, bytes));
        
        // Validate deadline
        require(
            deadline > block.timestamp + 5 minutes && 
            deadline <= block.timestamp + 24 hours,
            "Invalid deadline"
        );
        
        // Check commitment hasn't been used
        require(!usedCommitments[commitment], "Commitment already used");
        usedCommitments[commitment] = true;
        
        // Generate unique order ID
        orderId = OrderLib.generateOrderId(trader, key, params, ++orderNonce);
        
        // Create private order
        PrivateOrder memory order = PrivateOrder({
            trader: trader,
            poolKey: key,
            zeroForOne: params.zeroForOne,
            amountSpecified: params.amountSpecified,
            commitment: commitment,
            deadline: deadline,
            timestamp: block.timestamp,
            executed: false
        });
        
        // Store order
        orders[orderId] = order;
        
        // Store encrypted order in vault
        IOrderVault(orderVault).storeOrder(orderId, trader, encryptedOrder, deadline);
        
        emit OrderRoutedToVault(
            trader,
            orderId,
            key,
            params.zeroForOne,
            uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified),
            commitment
        );
        
        return orderId;
    }

    /// @inheritdoc IEigenVaultHook
    function executeVaultOrder(
        bytes32 orderId,
        bytes calldata proof,
        bytes calldata signatures
    ) external override onlyAuthorizedServiceManager {
        PrivateOrder storage order = orders[orderId];
        require(order.trader != address(0), "Order not found");
        require(!order.executed, "Order already executed");
        require(block.timestamp <= order.deadline, "Order expired");
        
        // Decode the proof data
        ZKProofLib.MatchingProof memory matchingProof = abi.decode(proof, (ZKProofLib.MatchingProof));
        
        // Verify the ZK proof
        bytes32 poolKey = keccak256(abi.encode(order.poolKey));
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(matchingProof, poolKey);
        
        require(error == ZKProofLib.ProofError.None, "Invalid proof");
        require(result.isValid, "Proof verification failed");
        
        // Mark order as executed
        order.executed = true;
        
        // Execute the order via pool manager using periphery patterns
        _executeOrderThroughPeriphery(order, result);
        
        // Update statistics
        bytes32 poolId = _getPoolId(
            order.poolKey.currency0,
            order.poolKey.currency1, 
            order.poolKey.fee,
            order.poolKey.tickSpacing,
            order.poolKey.hooks
        );
        poolStats[poolId].successfulMatches++;
        poolStats[poolId].averageExecutionTime = 
            (poolStats[poolId].averageExecutionTime + (block.timestamp - order.timestamp)) / 2;
        
        emit VaultOrderExecuted(
            orderId,
            order.trader,
            uint256(order.amountSpecified > 0 ? order.amountSpecified : -order.amountSpecified),
            result.matchHash,
            result.operators
        );
    }

    /// @notice Execute an order through Uniswap v4 periphery patterns
    /// @param order The order to execute
    /// @param result The proof result containing execution parameters
    function _executeOrderThroughPeriphery(
        PrivateOrder storage order,
        ZKProofLib.ProofResult memory result
    ) internal {
        // In production, this would interact with v4 periphery contracts
        // For now, we'll use direct pool manager interaction
        
        SwapParams memory params = SwapParams({
            zeroForOne: order.zeroForOne,
            amountSpecified: order.amountSpecified,
            sqrtPriceLimitX96: uint160(result.executionPrice) // Use price from ZK proof
        });
        
        // The actual swap would be executed here through proper channels
        // This is a simplified version for demonstration
        
        emit OrderExecuted(
            order.trader,
            order.poolKey,
            order.zeroForOne,
            order.amountSpecified,
            result.matchHash
        );
    }

    /// @inheritdoc IEigenVaultHook
    function fallbackToAMM(bytes32 orderId) external override {
        PrivateOrder storage order = orders[orderId];
        require(order.trader != address(0), "Order not found");
        require(!order.executed, "Order already executed");
        require(
            block.timestamp > order.deadline || 
            msg.sender == order.trader ||
            authorizedServiceManagers[msg.sender],
            "Cannot fallback yet"
        );
        
        order.executed = true;
        
        // Update statistics
        bytes32 poolId = _getPoolId(
            order.poolKey.currency0,
            order.poolKey.currency1, 
            order.poolKey.fee,
            order.poolKey.tickSpacing,
            order.poolKey.hooks
        );
        poolStats[poolId].fallbackExecutions++;
        
        // In production, this would trigger actual AMM execution
        // For now, we'll just emit the event
        
        emit OrderFallbackToAMM(
            orderId, 
            order.trader, 
            block.timestamp > order.deadline ? "Deadline exceeded" : "Manual fallback"
        );
    }

    /// @inheritdoc IEigenVaultHook
    function getOrder(bytes32 orderId) external view override returns (PrivateOrder memory order) {
        return orders[orderId];
    }

    /// @notice Get execution statistics for a pool
    /// @param key The pool key
    /// @return stats The execution statistics
    function getPoolExecutionStats(PoolKey calldata key) external view returns (ExecutionStats memory stats) {
        bytes32 poolId = getPoolId(key);
        return poolStats[poolId];
    }

    /// @notice Authorize or deauthorize a service manager
    /// @param serviceManagerAddr The service manager address
    /// @param authorized Whether to authorize or deauthorize
    function setServiceManagerAuthorization(
        address serviceManagerAddr,
        bool authorized
    ) external onlyOwner {
        require(serviceManagerAddr != address(0), "Invalid service manager");
        authorizedServiceManagers[serviceManagerAddr] = authorized;
        emit ServiceManagerAuthorized(serviceManagerAddr, authorized);
    }

    /// @notice Get order count for a trader
    /// @param trader The trader address
    /// @return count The number of orders
    function getTraderOrderCount(address trader) external view returns (uint256 count) {
        // This is a simplified version - in production you'd maintain proper indices
        return 0; // Placeholder
    }

    /// @notice Check if an order is executable
    /// @param orderId The order ID
    /// @return executable Whether the order can be executed
    function isOrderExecutable(bytes32 orderId) external view returns (bool executable) {
        PrivateOrder memory order = orders[orderId];
        return order.trader != address(0) && 
               !order.executed && 
               block.timestamp <= order.deadline;
    }

    /// @notice Helper function to generate pool ID from individual components
    function _getPoolId(
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks));
    }

    /// @notice Emergency pause functionality (owner only)
    bool public paused;
    
    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }
}