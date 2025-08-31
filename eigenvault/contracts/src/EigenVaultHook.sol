// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IEigenVaultHook} from "./interfaces/IEigenVaultHook.sol";
import {IOrderVault} from "./interfaces/IOrderVault.sol";
import {IEigenVaultAVSServiceManager} from "./interfaces/IEigenVaultAVSServiceManager.sol";
import {OrderLib} from "./libraries/OrderLib.sol";
import {ZKProofLib} from "./libraries/ZKProofLib.sol";

/// @title EigenVaultHook
/// @notice Main Uniswap v4 hook that orchestrates private order routing and execution using ZK proofs
/// @dev Extends BaseHook for proper Uniswap v4 hook inheritance with ZK proof integration
contract EigenVaultHook is BaseHook, ReentrancyGuard, Ownable, IEigenVaultHook {
    using OrderLib for OrderLib.Order;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /// @notice AVS service manager contract for EigenLayer integration
    IEigenVaultAVSServiceManager public immutable avsServiceManager;

    /// @notice The order vault contract for order storage
    address public immutable orderVault;

    /// @notice Default vault threshold in basis points (0.1% = 10 bps)
    uint256 public vaultThresholdBps = 10;

    /// @notice Mapping of pool keys to custom thresholds
    mapping(bytes32 => uint256) public poolThresholds;

    /// @notice Order structure for ZK proof verification
    struct VaultOrder {
        uint256 amount;
        bool zeroForOne;
        uint256 price;
        uint256 deadline;
        address trader;
        bool executed;
        bytes32 commitment;
        PoolKey poolKey;
    }

    /// @notice Events unique to implementation
    event AVSServiceManagerAuthorized(address indexed avsServiceManager, bool authorized);
    event MatchingTaskCreated(uint32 indexed taskIndex, bytes32 indexed orderId, bytes32 indexed poolId);
    event VaultThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event PoolThresholdUpdated(bytes32 indexed poolId, uint256 oldThreshold, uint256 newThreshold);
    event VaultOrderCreated(bytes32 indexed orderId, address indexed trader, uint256 amount, bool zeroForOne);
    event OrderRoutedToVault(address indexed trader, bytes32 indexed orderId, PoolKey indexed key, bool zeroForOne, int256 amountSpecified, bytes32 commitment);

    /// @notice Execution statistics for a pool
    struct ExecutionStats {
        uint256 totalOrders;
        uint256 successfulMatches;
        uint256 fallbackExecutions;
        uint256 totalVolume;
        uint256 averageExecutionTime;
    }

    /// @notice Modifiers
    modifier onlyAuthorizedAVSServiceManager() {
        require(msg.sender == address(avsServiceManager), "Only AVS service manager");
        _;
    }

    /// @notice Mapping of order IDs to vault order details
    mapping(bytes32 => VaultOrder) public vaultOrders;
    
    /// @notice Mapping of order commitments to prevent replay
    mapping(bytes32 => bool) public usedCommitments;
    
    /// @notice Order nonce counter
    uint256 public orderNonce;

    /// @notice Mapping of pool keys to execution statistics
    mapping(bytes32 => ExecutionStats) public poolStats;

    /// @notice Mapping of pool keys to order counts
    mapping(bytes32 => uint256) public poolOrderCounts;

    /// @notice Mapping of pool keys to total volumes
    mapping(bytes32 => uint256) public poolTotalVolumes;

    /// @notice Constructor
    /// @param _poolManager The Uniswap v4 pool manager
    /// @param _orderVault The order vault contract
    /// @param _avsServiceManager The AVS service manager contract
    constructor(
        IPoolManager _poolManager,
        address _orderVault,
        address _avsServiceManager
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        require(_orderVault != address(0), "Invalid order vault address");
        require(_avsServiceManager != address(0), "Invalid AVS service manager address");
        orderVault = _orderVault;
        avsServiceManager = IEigenVaultAVSServiceManager(_avsServiceManager);
    }

    /// @notice Get the hook permissions
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Before swap hook implementation
    /// @param sender The sender address
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Additional hook data
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        
        // Check if this is a large order that should go to the vault
        bool isLargeOrderResult = _isLargeOrder(poolId, params.amountSpecified);
        
        if (isLargeOrderResult) {
            // Route to vault for private matching
            _routeToVault(sender, key, params, hookData);
        } else {
            // Small order - execute directly on AMM
            _executeDirectSwap(sender, key, params);
        }
        
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Check if an order amount qualifies as large order
    /// @param poolId The pool ID
    /// @param amountSpecified The amount specified in the swap
    function _isLargeOrder(bytes32 poolId, int256 amountSpecified) internal view returns (bool) {
        uint256 threshold = poolThresholds[poolId];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
        
        // Get pool liquidity (simplified - in practice you'd query the actual pool)
        uint256 poolLiquidity = 1000000e18; // Placeholder
        
        uint256 thresholdAmount = (poolLiquidity * threshold) / 10000;
        uint256 orderAmount = uint256(amountSpecified > 0 ? amountSpecified : -amountSpecified);
        
        return orderAmount >= thresholdAmount;
    }

    /// @notice Route a large order to the vault
    /// @param sender The order sender
    /// @param key The pool key
    /// @param params The swap parameters
    /// @param hookData Additional hook data
    function _routeToVault(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        bytes32 orderId = keccak256(abi.encodePacked(sender, poolId, orderNonce, block.timestamp));
        
        // Create order commitment
        bytes32 commitment = keccak256(abi.encodePacked(
            orderId,
            params.amountSpecified,
            params.sqrtPriceLimitX96,
            hookData
        ));
        
        require(!usedCommitments[commitment], "Commitment already used");
        usedCommitments[commitment] = true;
        
        // Store order in vault
        IOrderVault(orderVault).storeOrder(
            orderId,
            uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified),
            params.amountSpecified > 0,
            _getCurrentPrice(key),
            block.timestamp + 1 hours,
            sender,
            commitment,
            poolId
        );
        
        // Create AVS matching task
        uint32 taskIndex = avsServiceManager.createMatchingTask(
            orderId,
            poolId,
            commitment
        );
        
        emit MatchingTaskCreated(taskIndex, orderId, poolId);
        orderNonce++;
        
        // Update pool statistics
        poolOrderCounts[poolId]++;
        poolTotalVolumes[poolId] += uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified);
    }

    /// @notice Execute a swap directly on the AMM
    /// @param sender The order sender
    /// @param key The pool key
    /// @param params The swap parameters
    function _executeDirectSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params
    ) internal {
        // For small orders, we can execute directly
        // This would typically involve calling the pool manager directly
        // For now, we'll just update statistics
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        poolStats[poolId].fallbackExecutions++;
    }

    /// @notice Execute a matched vault order
    /// @param orderId The order ID
    /// @param zkProof The ZK proof of valid matching
    function executeMatchedOrder(
        bytes32 orderId,
        bytes calldata zkProof
    ) public onlyAuthorizedAVSServiceManager {
        VaultOrder storage order = vaultOrders[orderId];
        require(!order.executed, "Order already executed");
        require(block.timestamp <= order.deadline, "Order expired");
        
        // Verify ZK proof (this would integrate with your ZK proof system)
        require(_verifyZKProof(orderId, zkProof), "Invalid ZK proof");
        
        // Mark order as executed
        order.executed = true;
        
        // Update pool statistics
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(order.poolKey));
        poolStats[poolId].successfulMatches++;
        poolStats[poolId].totalVolume += order.amount;
        
        // Execute the actual swap on Uniswap
        _executeSwapOnUniswap(order);
    }

    /// @notice Verify ZK proof for order matching
    /// @param orderId The order ID
    /// @param zkProof The ZK proof
    function _verifyZKProof(bytes32 orderId, bytes calldata zkProof) internal view returns (bool) {
        // Decode the ZK proof data
        (bytes32 proofId, bytes memory proofData, bytes32[] memory publicInputs, bytes memory verificationKey, uint256 timestamp, address[] memory operators) = 
            abi.decode(zkProof, (bytes32, bytes, bytes32[], bytes, uint256, address[]));
        
        // Basic validation
        if (proofData.length == 0 || publicInputs.length == 0 || verificationKey.length == 0) {
            return false;
        }
        
        // Check proof freshness (24 hours)
        if (block.timestamp > timestamp + 24 hours) {
            return false;
        }
        
        // Verify the proof using ZKProofLib
        ZKProofLib.MatchingProof memory matchingProof = ZKProofLib.MatchingProof({
            proofId: proofId,
            proof: proofData,
            publicInputs: publicInputs,
            verificationKey: verificationKey,
            timestamp: timestamp,
            operators: operators,
            poolHash: bytes32(0), // Will be set from order data
            orderCount: 1
        });
        
        // Set the pool hash from the order
        VaultOrder memory order = vaultOrders[orderId];
        matchingProof.poolHash = keccak256(abi.encodePacked(
            order.poolKey.currency0,
            order.poolKey.currency1,
            order.poolKey.fee,
            order.poolKey.tickSpacing
        ));
        
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(matchingProof, matchingProof.poolHash);
        
        return result.isValid && error == ZKProofLib.ProofError.None;
    }

    /// @notice Execute swap on Uniswap after ZK verification
    /// @param order The vault order
    function _executeSwapOnUniswap(VaultOrder storage order) internal {
        // Create swap parameters for the pool manager
        SwapParams memory swapParams = SwapParams({
            zeroForOne: order.zeroForOne,
            amountSpecified: int256(order.amount),
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        // Execute the swap through the pool manager
        try poolManager.swap(order.poolKey, swapParams, "") {
            // Swap successful - update statistics
            bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(order.poolKey));
            poolStats[poolId].totalVolume += order.amount;
            poolStats[poolId].averageExecutionTime = 
                (poolStats[poolId].averageExecutionTime + (block.timestamp - order.deadline + 1 hours)) / 2;
        } catch {
            // Swap failed - this could happen if pool conditions changed
            // In production, you might want to retry or handle this differently
            revert("Swap execution failed");
        }
    }

    /// @notice Get current price for a pool
    /// @param key The pool key
    function _getCurrentPrice(PoolKey calldata key) internal view returns (uint256) {
        // Convert PoolKey to PoolId and get the current sqrt price from the pool
        PoolId poolId = PoolIdLibrary.toId(key);
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
        
        // Convert sqrt price to actual price
        // price = (sqrtPriceX96 / 2^96)^2
        uint256 price = uint256(sqrtPriceX96);
        price = (price * price) >> 192; // Divide by 2^96 twice
        
        return price;
    }

    /// @notice Set pool threshold
    /// @param poolId The pool ID
    /// @param threshold The threshold in basis points
    function setPoolThreshold(bytes32 poolId, uint256 threshold) external onlyOwner {
        uint256 oldThreshold = poolThresholds[poolId];
        poolThresholds[poolId] = threshold;
        emit PoolThresholdUpdated(poolId, oldThreshold, threshold);
    }

    /// @notice Set vault threshold
    /// @param threshold The threshold in basis points
    function setVaultThreshold(uint256 threshold) external onlyOwner {
        uint256 oldThreshold = vaultThresholdBps;
        vaultThresholdBps = threshold;
        emit VaultThresholdUpdated(oldThreshold, threshold);
    }

    /// @notice Set vault threshold (internal function)
    /// @param threshold The threshold in basis points
    function _setVaultThreshold(uint256 threshold) internal {
        uint256 oldThreshold = vaultThresholdBps;
        vaultThresholdBps = threshold;
        emit VaultThresholdUpdated(oldThreshold, threshold);
    }

    /// @notice Set AVS service manager authorization
    /// @param _avsServiceManager The AVS service manager address
    /// @param authorized Whether it's authorized
    function setServiceManagerAuthorization(address _avsServiceManager, bool authorized) external onlyOwner {
        // This would typically involve updating an authorization mapping
        emit AVSServiceManagerAuthorized(_avsServiceManager, authorized);
    }

    /// @notice Get pool statistics
    /// @param poolId The pool ID
    function getPoolStats(bytes32 poolId) external view returns (ExecutionStats memory) {
        return poolStats[poolId];
    }

    /// @notice Get vault order details
    /// @param orderId The order ID
    function getVaultOrder(bytes32 orderId) external view returns (VaultOrder memory) {
        return vaultOrders[orderId];
    }

    // ============ Interface Implementation ============

    /// @notice Check if an order qualifies as a large order for vault routing
    /// @param amountSpecified The amount being swapped
    /// @param key The pool key
    /// @return Whether the order should be routed to vault
    function isLargeOrder(int256 amountSpecified, PoolKey calldata key) external view override returns (bool) {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        return _isLargeOrder(poolId, amountSpecified);
    }

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
    ) external override returns (bytes32 orderId) {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        orderId = keccak256(abi.encodePacked(trader, poolId, orderNonce, block.timestamp));
        
        // Create order commitment
        bytes32 commitment = keccak256(abi.encodePacked(
            orderId,
            params.amountSpecified,
            params.sqrtPriceLimitX96,
            hookData
        ));
        
        // Store order in vault
        IOrderVault(orderVault).storeOrder(
            orderId,
            uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified),
            params.amountSpecified > 0,
            _getCurrentPrice(key),
            block.timestamp + 1 hours,
            trader,
            commitment,
            poolId
        );
        
        // Create AVS matching task
        avsServiceManager.createMatchingTask(orderId, poolId, commitment);
        
        emit OrderRoutedToVault(trader, orderId, key, params.amountSpecified > 0, params.amountSpecified, commitment);
        orderNonce++;
        
        return orderId;
    }

    /// @notice Execute a matched vault order
    /// @param orderId The order identifier
    /// @param proof The ZK proof of valid matching
    /// @param signatures The operator signatures
    function executeVaultOrder(
        bytes32 orderId,
        bytes calldata proof,
        bytes calldata signatures
    ) external override {
        // Call the public executeMatchedOrder function
        this.executeMatchedOrder(orderId, proof);
    }

    /// @notice Fallback to AMM execution for unmatched orders
    /// @param orderId The order identifier
    function fallbackToAMM(bytes32 orderId) external override {
        VaultOrder storage order = vaultOrders[orderId];
        require(!order.executed, "Order already executed");
        require(block.timestamp > order.deadline, "Order not expired yet");
        
        // Mark order as executed
        order.executed = true;
        
        // Execute the swap on Uniswap
        _executeSwapOnUniswap(order);
        
        emit OrderFallbackToAMM(orderId, order.trader, "Order expired, fallback to AMM");
    }

    /// @notice Get order details
    /// @param orderId The order identifier
    /// @return order The private order details
    function getOrder(bytes32 orderId) external view override returns (PrivateOrder memory order) {
        VaultOrder memory vaultOrder = vaultOrders[orderId];
        return PrivateOrder({
            trader: vaultOrder.trader,
            poolKey: vaultOrder.poolKey,
            zeroForOne: vaultOrder.zeroForOne,
            amountSpecified: int256(vaultOrder.amount),
            commitment: vaultOrder.commitment,
            deadline: vaultOrder.deadline,
            timestamp: vaultOrder.deadline - 1 hours,
            executed: vaultOrder.executed
        });
    }

    /// @notice Get vault threshold for a pool
    /// @param key The pool key
    /// @return threshold The threshold in basis points
    function getVaultThreshold(PoolKey calldata key) external view override returns (uint256 threshold) {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        threshold = poolThresholds[poolId];
        if (threshold == 0) {
            threshold = vaultThresholdBps;
        }
    }

    /// @notice Update vault threshold (admin only)
    /// @param newThreshold The new threshold in basis points
    function updateVaultThreshold(uint256 newThreshold) external override onlyOwner {
        _setVaultThreshold(newThreshold);
    }
}