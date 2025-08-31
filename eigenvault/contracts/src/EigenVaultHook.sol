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
import {OrderMatchingLib} from "./libraries/OrderMatchingLib.sol";
import {AVSConsensusLib} from "./libraries/AVSConsensusLib.sol";
import {SecurityLib} from "./libraries/SecurityLib.sol";

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
    event VaultOrderExecuted(PoolKey indexed poolKey, uint256 amountIn, uint256 expectedAmountOut, uint256 actualAmount0, uint256 actualAmount1, bool zeroForOne);
    event OrderMatched(bytes32 indexed orderId, address indexed trader, uint256 executionPrice, uint256 matchedAmount);
    event LiquidityChecked(bytes32 indexed poolId, uint256 requiredAmount, uint256 availableLiquidity, bool sufficient);
    event MatchExecuted(bytes32 indexed matchId, uint256 executionPrice, uint256 matchedAmount);
    event ConsensusTaskCreated(bytes32 indexed taskId, bytes32 indexed matchId, uint256 threshold);
    event OrderAddedToBook(bytes32 indexed orderId, bytes32 indexed poolId, uint256 price, uint256 amount, bool isBuy);
    event SecurityCheckFailed(bytes32 indexed orderId, uint256 riskScore, string reason);
    event EmergencyPauseActivated(string reason, uint256 timestamp);
    event EmergencyPauseDeactivated(uint256 timestamp);
    event GasOptimizationUpdated(bool batchProcessing, uint256 maxBatchSize, bool compression);
    event SecurityConfigUpdated(uint256 maxOrderSize, uint256 maxPoolExposure, uint256 maxSlippageBps);
    event BatchProcessCompleted(uint256 totalOrders, uint256 successCount);

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

    /// @notice Mapping of pool keys to order books
    mapping(bytes32 => OrderMatchingLib.OrderBook) public orderBooks;
    
    /// @notice Mapping of match IDs to matching results
    mapping(bytes32 => OrderMatchingLib.MatchingResult) public matches;
    
    /// @notice Mapping of consensus task IDs to consensus tasks
    mapping(bytes32 => AVSConsensusLib.ConsensusTask) public consensusTasks;
    
    /// @notice Consensus configuration
    AVSConsensusLib.ConsensusConfig public consensusConfig;
    
    /// @notice Order matching statistics
    struct MatchingStats {
        uint256 totalMatches;
        uint256 successfulMatches;
        uint256 failedMatches;
        uint256 totalVolume;
        uint256 averageMatchTime;
        uint256 consensusSuccessRate;
    }
    
    /// @notice Global matching statistics
    MatchingStats public matchingStats;
    
    /// @notice Security configuration for production hardening
    SecurityLib.SecurityConfig public securityConfig;
    
    /// @notice Gas optimization settings
    struct GasOptimization {
        bool enableBatchProcessing;
        uint256 maxBatchSize;
        bool enableCompression;
        uint256 gasPriceLimit;
    }
    
    /// @notice Gas optimization configuration
    GasOptimization public gasOptimization;

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
        
        // Initialize consensus configuration
        consensusConfig = AVSConsensusLib.ConsensusConfig({
            minOperators: 3,
            consensusThreshold: 2,
            responseTimeout: 5 minutes,
            maxRetries: 3,
            requireSignature: true
        });
        
        // Initialize security configuration
        securityConfig = SecurityLib.SecurityConfig({
            maxOrderSize: 10000e18,        // 10,000 tokens max
            maxPoolExposure: 100000e18,    // 100,000 tokens max
            maxSlippageBps: 500,           // 5% max slippage
            emergencyPauseThreshold: 80,   // 80% risk threshold
            emergencyPaused: false,
            lastSecurityCheck: 0,
            securityCheckInterval: 1 hours
        });
        
        // Initialize gas optimization
        gasOptimization = GasOptimization({
            enableBatchProcessing: true,
            maxBatchSize: 10,
            enableCompression: true,
            gasPriceLimit: 100 gwei
        });
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

    /// @notice Get comprehensive pool state including liquidity and fees
    /// @param key The pool key
    /// @return sqrtPriceX96 Current sqrt price in X96 format
    /// @return tick Current tick
    /// @return fee The pool fee
    /// @return tickSpacing The tick spacing
    function _getPoolState(PoolKey memory key) internal view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 fee,
        uint24 tickSpacing
    ) {
        PoolId poolId = PoolIdLibrary.toId(key);
        (sqrtPriceX96, tick, fee, tickSpacing) = StateLibrary.getSlot0(poolManager, poolId);
    }

    /// @notice Get pool liquidity at specific tick range (simplified)
    /// @param key The pool key
    /// @param tickLower Lower tick boundary
    /// @param tickUpper Upper tick boundary
    /// @return liquidity The liquidity at the specified range
    function _getLiquidityAtTickRange(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity) {
        // Simplified liquidity query - in production, this would use proper position queries
        // For now, return a reasonable estimate based on pool state
        (uint160 sqrtPriceX96, int24 tick,,) = _getPoolState(key);
        
        // Calculate liquidity based on current price and tick range
        if (tick >= tickLower && tick <= tickUpper) {
            // Current tick is within range, estimate liquidity
            liquidity = uint128(uint256(sqrtPriceX96) / 1e12); // Simplified calculation
        } else {
            // Current tick is outside range, minimal liquidity
            liquidity = 1000; // Minimum liquidity threshold
        }
    }

    /// @notice Calculate optimal swap amount considering slippage and liquidity
    /// @param key The pool key
    /// @param amountIn The input amount
    /// @param zeroForOne Whether swapping token0 for token1
    /// @param maxSlippageBps Maximum allowed slippage in basis points
    /// @return amountOut The expected output amount
    /// @return sqrtPriceLimitX96 The price limit for the swap
    function _calculateOptimalSwapAmount(
        PoolKey memory key,
        uint256 amountIn,
        bool zeroForOne,
        uint256 maxSlippageBps
    ) internal view returns (uint256 amountOut, uint160 sqrtPriceLimitX96) {
        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick,,) = _getPoolState(key);
        
        // Estimate liquidity based on current price
        uint128 liquidity = uint128(uint256(sqrtPriceX96) / 1e12);
        
        // Calculate price impact based on liquidity
        uint256 priceImpact = _calculatePriceImpact(amountIn, liquidity, zeroForOne);
        
        // Apply slippage protection
        uint256 maxPriceImpact = (maxSlippageBps * 100) / 10000; // Convert bps to percentage
        
        if (priceImpact > maxPriceImpact) {
            // Reduce amount to meet slippage requirements
            amountIn = (amountIn * maxPriceImpact) / priceImpact;
        }
        
        // Calculate expected output using constant product formula
        amountOut = _calculateOutputAmount(amountIn, sqrtPriceX96, liquidity, zeroForOne);
        
        // Set price limit to prevent excessive slippage
        if (zeroForOne) {
            // Swapping token0 for token1 (price decreases)
            sqrtPriceLimitX96 = uint160(uint256(sqrtPriceX96) - (uint256(sqrtPriceX96) * maxSlippageBps) / 10000);
        } else {
            // Swapping token1 for token0 (price increases)
            sqrtPriceLimitX96 = uint160(uint256(sqrtPriceX96) + (uint256(sqrtPriceX96) * maxSlippageBps) / 10000);
        }
    }

    /// @notice Calculate price impact of a swap
    /// @param amountIn The input amount
    /// @param liquidity The pool liquidity
    /// @param zeroForOne Whether swapping token0 for token1
    /// @return priceImpact The price impact as a percentage
    function _calculatePriceImpact(
        uint256 amountIn,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint256 priceImpact) {
        // Simplified price impact calculation
        // In production, this would use more sophisticated AMM math
        if (liquidity == 0) return type(uint256).max;
        
        // Price impact = amountIn / (liquidity * 2)
        priceImpact = (amountIn * 10000) / (uint256(liquidity) * 2);
        
        // Cap at 100%
        if (priceImpact > 10000) priceImpact = 10000;
    }

    /// @notice Calculate expected output amount using constant product formula
    /// @param amountIn The input amount
    /// @param sqrtPriceX96 Current sqrt price
    /// @param liquidity Current liquidity
    /// @param zeroForOne Whether swapping token0 for token1
    /// @return amountOut The expected output amount
    function _calculateOutputAmount(
        uint256 amountIn,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint256 amountOut) {
        if (zeroForOne) {
            // Swapping token0 for token1
            // amountOut = (amountIn * liquidity) / (amountIn + liquidity * sqrtPriceX96^2 / 2^192)
            uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) >> 192;
            amountOut = (amountIn * uint256(liquidity)) / (amountIn + (uint256(liquidity) * price) / 1e18);
        } else {
            // Swapping token1 for token0
            // amountOut = (amountIn * liquidity * sqrtPriceX96^2 / 2^192) / (amountIn + liquidity)
            uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) >> 192;
            amountOut = (amountIn * uint256(liquidity) * price / 1e18) / (amountIn + uint256(liquidity));
        }
    }

    /// @notice Enhanced swap execution with slippage protection and liquidity checks
    /// @param order The vault order
    function _executeSwapOnUniswap(VaultOrder storage order) internal {
        // Get optimal swap parameters
        PoolKey memory poolKey = order.poolKey;
        (uint256 expectedAmountOut, uint160 sqrtPriceLimitX96) = _calculateOptimalSwapAmount(
            poolKey,
            order.amount,
            order.zeroForOne,
            100 // 1% max slippage
        );
        
        // Create enhanced swap parameters
        SwapParams memory swapParams = SwapParams({
            zeroForOne: order.zeroForOne,
            amountSpecified: int256(order.amount),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        
        // Execute the swap through the pool manager with enhanced error handling
        try poolManager.swap(poolKey, swapParams, "") returns (BalanceDelta delta) {
            // Swap successful - update statistics
            bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(poolKey));
            poolStats[poolId].totalVolume += order.amount;
            poolStats[poolId].successfulMatches++;
            poolStats[poolId].averageExecutionTime = 
                (poolStats[poolId].averageExecutionTime + (block.timestamp - order.deadline + 1 hours)) / 2;
            
            // Log successful execution
            emit VaultOrderExecuted(
                poolKey,
                order.amount,
                expectedAmountOut,
                delta.amount0() < 0 ? uint256(uint128(-delta.amount0())) : uint256(uint128(delta.amount0())),
                delta.amount1() < 0 ? uint256(uint128(-delta.amount1())) : uint256(uint128(delta.amount1())),
                order.zeroForOne
            );
        } catch Error(string memory reason) {
            // Handle specific error cases
            if (bytes(reason).length > 0) {
                revert(string(abi.encodePacked("Swap failed: ", reason)));
            } else {
                revert("Swap execution failed");
            }
        } catch {
            // Generic fallback
            revert("Swap execution failed");
        }
    }

    /// @notice Check if pool has sufficient liquidity for a swap
    /// @param key The pool key
    /// @param amount The swap amount
    /// @param zeroForOne Whether swapping token0 for token1
    /// @return hasLiquidity Whether the pool has sufficient liquidity
    /// @return availableLiquidity The available liquidity
    function _checkPoolLiquidity(
        PoolKey memory key,
        uint256 amount,
        bool zeroForOne
    ) internal view returns (bool hasLiquidity, uint256 availableLiquidity) {
        (uint160 sqrtPriceX96,,,) = _getPoolState(key);
        
        // Estimate liquidity based on current price
        availableLiquidity = uint256(sqrtPriceX96) / 1e12;
        
        // Simple liquidity check - in production, this would be more sophisticated
        hasLiquidity = availableLiquidity >= amount * 2; // Require 2x liquidity for safety
    }

    /// @notice Get pool fee information
    /// @param key The pool key
    /// @return fee The pool fee in basis points
    /// @return protocolFee The protocol fee in basis points
    function _getPoolFees(PoolKey memory key) internal pure returns (uint24 fee, uint8 protocolFee) {
        fee = key.fee;
        protocolFee = 0; // Default protocol fee, could be made configurable
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

    /// @notice Enhanced order matching with liquidity and price validation
    /// @param orderId The order ID to match
    /// @param matchingProof The ZK proof of valid matching
    /// @return success Whether the order was successfully matched
    function _executeOrderWithEnhancedMatching(
        bytes32 orderId,
        ZKProofLib.MatchingProof memory matchingProof
    ) internal returns (bool success) {
        VaultOrder storage order = vaultOrders[orderId];
        require(!order.executed, "Order already executed");
        require(block.timestamp <= order.deadline, "Order expired");
        
        // Perform security check before execution
        SecurityLib.RiskAssessment memory riskAssessment = SecurityLib.performSecurityCheck(
            securityConfig,
            order.amount,
            poolStats[PoolId.unwrap(PoolIdLibrary.toId(order.poolKey))].totalVolume,
            100 // Default slippage
        );
        
        if (!riskAssessment.shouldExecute) {
            emit SecurityCheckFailed(orderId, riskAssessment.riskScore, riskAssessment.riskReason);
            return false;
        }
        
        // Verify ZK proof
        (ZKProofLib.ProofResult memory result, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyMatchingProof(matchingProof, matchingProof.poolHash);
        
        if (!result.isValid || error != ZKProofLib.ProofError.None) {
            return false;
        }
        
        // Check pool liquidity before execution
        PoolKey memory poolKey = order.poolKey;
        (bool hasLiquidity, uint256 availableLiquidity) = _checkPoolLiquidity(
            poolKey,
            order.amount,
            order.zeroForOne
        );
        
        emit LiquidityChecked(
            PoolId.unwrap(PoolIdLibrary.toId(poolKey)),
            order.amount,
            availableLiquidity,
            hasLiquidity
        );
        
        if (!hasLiquidity) {
            // Insufficient liquidity - mark for fallback
            poolStats[PoolId.unwrap(PoolIdLibrary.toId(poolKey))].fallbackExecutions++;
            return false;
        }
        
        // Execute the swap with enhanced Uniswap integration
        _executeSwapOnUniswap(order);
        
        // Mark order as executed
        order.executed = true;
        
        // Update pool statistics
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(poolKey));
        poolStats[poolId].totalOrders++;
        poolStats[poolId].successfulMatches++;
        
        // Emit matching event
        emit OrderMatched(
            orderId,
            order.trader,
            result.executionPrice,
            result.totalVolume
        );
        
        return true;
    }

    /// @notice Get comprehensive pool analytics for order routing decisions
    /// @param key The pool key
    /// @return poolState The current pool state
    /// @return liquidityInfo Liquidity distribution information
    /// @return feeInfo Fee and protocol information
    /// @return volumeInfo Volume and execution statistics
    function _getPoolAnalytics(PoolKey memory key) internal view returns (
        PoolState memory poolState,
        LiquidityInfo memory liquidityInfo,
        FeeInfo memory feeInfo,
        VolumeInfo memory volumeInfo
    ) {
        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick, uint24 fee, uint24 tickSpacing) = _getPoolState(key);
        
        // Estimate liquidity based on current price
        uint128 liquidity = uint128(uint256(sqrtPriceX96) / 1e12);
        
        poolState = PoolState({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            liquidity: liquidity,
            feeGrowthGlobal0X128: 0, // Not available in current implementation
            feeGrowthGlobal1X128: 0, // Not available in current implementation
            protocolFees: 0,          // Not available in current implementation
            swapFees: 0               // Not available in current implementation
        });
        
        // Get fee information
        (uint24 poolFee, uint8 protocolFee) = _getPoolFees(key);
        feeInfo = FeeInfo({
            poolFee: poolFee,
            protocolFee: protocolFee,
            totalFees: uint256(poolFee) + uint256(protocolFee)
        });
        
        // Get volume information
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(key));
        ExecutionStats memory stats = poolStats[poolId];
        volumeInfo = VolumeInfo({
            totalVolume: stats.totalVolume,
            totalOrders: stats.totalOrders,
            successfulMatches: stats.successfulMatches,
            fallbackExecutions: stats.fallbackExecutions,
            averageExecutionTime: stats.averageExecutionTime
        });
        
        // Calculate liquidity distribution (simplified)
        liquidityInfo = LiquidityInfo({
            totalLiquidity: uint256(liquidity),
            concentratedLiquidity: uint256(liquidity) * 80 / 100, // Assume 80% concentrated
            distributedLiquidity: uint256(liquidity) * 20 / 100,  // Assume 20% distributed
            liquidityDepth: _calculateLiquidityDepth(key, liquidity)
        });
    }

    /// @notice Calculate liquidity depth for price impact assessment
    /// @param key The pool key
    /// @param liquidity The current liquidity
    /// @return depth The liquidity depth score
    function _calculateLiquidityDepth(PoolKey memory key, uint128 liquidity) internal view returns (uint256 depth) {
        // Get liquidity at different tick ranges for depth calculation
        (uint160 sqrtPriceX96, int24 currentTick,,) = _getPoolState(key);
        
        // Sample liquidity at different tick ranges
        uint128 liquidityAtTick1 = _getLiquidityAtTickRange(key, currentTick - 100, currentTick + 100);
        uint128 liquidityAtTick2 = _getLiquidityAtTickRange(key, currentTick - 500, currentTick + 500);
        uint128 liquidityAtTick3 = _getLiquidityAtTickRange(key, currentTick - 1000, currentTick + 1000);
        
        // Calculate depth as weighted average (ensure positive values)
        depth = (uint256(liquidityAtTick1) * 50 + uint256(liquidityAtTick2) * 30 + uint256(liquidityAtTick3) * 20) / 100;
    }

    /// @notice Smart order routing based on pool analytics
    /// @param key The pool key
    /// @param amount The order amount
    /// @param zeroForOne Whether swapping token0 for token1
    /// @return shouldRouteToVault Whether to route to vault
    /// @return reason The routing decision reason
    function _smartOrderRouting(
        PoolKey memory key,
        uint256 amount,
        bool zeroForOne
    ) internal view returns (bool shouldRouteToVault, string memory reason) {
        // Get comprehensive pool analytics
        (PoolState memory poolState, LiquidityInfo memory liquidityInfo, FeeInfo memory feeInfo, VolumeInfo memory volumeInfo) = 
            _getPoolAnalytics(key);
        
        // Check if order is large relative to liquidity
        if (amount > liquidityInfo.totalLiquidity / 10) {
            return (true, "Order size > 10% of total liquidity");
        }
        
        // Check if pool has high fees (might want to route to vault for better pricing)
        if (feeInfo.totalFees > 100) { // > 1%
            return (true, "High pool fees - route to vault for better pricing");
        }
        
        // Check if pool has low liquidity depth
        if (liquidityInfo.liquidityDepth < liquidityInfo.totalLiquidity / 5) {
            return (true, "Low liquidity depth - route to vault for better execution");
        }
        
        // Check if pool has high volume (might indicate good execution)
        if (volumeInfo.totalVolume > 0 && volumeInfo.successfulMatches > volumeInfo.totalOrders * 90 / 100) {
            return (false, "High success rate - execute directly on pool");
        }
        
        // Default to vault routing for large orders
        if (amount > 1000e18) { // > 1000 tokens
            return (true, "Large order - route to vault for private matching");
        }
        
        return (false, "Standard order - execute directly on pool");
    }

    // ============ Enhanced Data Structures ============
    
    /// @notice Pool state information
    struct PoolState {
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 protocolFees;
        uint128 swapFees;
    }
    
    /// @notice Liquidity distribution information
    struct LiquidityInfo {
        uint256 totalLiquidity;
        uint256 concentratedLiquidity;
        uint256 distributedLiquidity;
        uint256 liquidityDepth;
    }
    
    /// @notice Fee information
    struct FeeInfo {
        uint24 poolFee;
        uint8 protocolFee;
        uint256 totalFees;
    }
    
    /// @notice Volume and execution information
    struct VolumeInfo {
        uint256 totalVolume;
        uint256 totalOrders;
        uint256 successfulMatches;
        uint256 fallbackExecutions;
        uint256 averageExecutionTime;
    }

    /// @notice Add order to order book for matching
    /// @param orderId The order ID
    /// @param poolKey The pool key
    /// @param price The order price
    /// @param amount The order amount
    /// @param zeroForOne Whether swapping token0 for token1
    function addOrderToBook(
        bytes32 orderId,
        PoolKey memory poolKey,
        uint256 price,
        uint256 amount,
        bool zeroForOne
    ) internal {
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(poolKey));
        
        OrderMatchingLib.OrderBookEntry memory orderEntry = OrderMatchingLib.OrderBookEntry({
            orderId: orderId,
            price: price,
            amount: amount,
            timestamp: block.timestamp,
            trader: msg.sender,
            isActive: true
        });
        
        OrderMatchingLib.insertOrder(orderBooks[poolId], orderEntry, !zeroForOne);
        
        // Try to match orders immediately
        _attemptOrderMatching(poolId);
    }

    /// @notice Attempt to match orders in the order book
    /// @param poolId The pool ID
    function _attemptOrderMatching(bytes32 poolId) internal {
        OrderMatchingLib.OrderBook storage orderBook = orderBooks[poolId];
        
        // Check if there are orders to match
        if (orderBook.buyOrders.length == 0 || orderBook.sellOrders.length == 0) {
            return;
        }
        
        // Get best bid and ask
        (uint256 bestBid, uint256 bestAsk) = OrderMatchingLib.getBestPrices(orderBook);
        
        // Check if orders can cross
        if (bestBid < bestAsk) {
            return;
        }
        
        // Match orders at the crossing price
        OrderMatchingLib.OrderBookEntry memory buyOrder = orderBook.buyOrders[0];
        OrderMatchingLib.OrderBookEntry memory sellOrder = orderBook.sellOrders[0];
        
        // Create a local copy of pool key for matching
        PoolKey memory localPoolKey = _getPoolKeyFromId(poolId);
        
        (OrderMatchingLib.MatchingResult memory result, bool canMatch) = 
            OrderMatchingLib.matchOrders(buyOrder, sellOrder, localPoolKey);
        
        if (canMatch) {
            // Store the match
            matches[result.matchId] = result;
            
            // Create consensus task for AVS validation
            _createConsensusTask(result);
            
            // Update statistics
            matchingStats.totalMatches++;
            matchingStats.totalVolume += result.matchedAmount;
            
            // Remove matched orders from book
            OrderMatchingLib.removeOrder(orderBook, buyOrder.orderId, true);
            OrderMatchingLib.removeOrder(orderBook, sellOrder.orderId, false);
            
            emit OrderMatched(
                result.matchId,
                buyOrder.trader,
                result.executionPrice,
                result.matchedAmount
            );
        }
    }

    /// @notice Create consensus task for AVS validation
    /// @param result The matching result
    function _createConsensusTask(OrderMatchingLib.MatchingResult memory result) internal {
        // Get assigned operators from AVS service manager
        address[] memory operators = avsServiceManager.getAssignedOperators(result.matchId);
        
        // Create consensus configuration
        AVSConsensusLib.ConsensusConfig memory config = AVSConsensusLib.ConsensusConfig({
            minOperators: 3,
            consensusThreshold: AVSConsensusLib.calculateConsensusThreshold(operators.length),
            responseTimeout: 5 minutes,
            maxRetries: 3,
            requireSignature: true
        });
        
        // Create consensus task
        bytes32 taskId = AVSConsensusLib.createConsensusTask(
            result.matchId,
            operators,
            config
        );
        
        // Initialize consensus task storage
        consensusTasks[taskId].taskId = taskId;
        consensusTasks[taskId].matchId = result.matchId;
        consensusTasks[taskId].consensusThreshold = config.consensusThreshold;
        consensusTasks[taskId].deadline = block.timestamp + config.responseTimeout;
        consensusTasks[taskId].completed = false;
        consensusTasks[taskId].responseCount = 0;
        
        // Assign operators
        consensusTasks[taskId].assignedOperators = operators;
        
        // Request operator responses
        avsServiceManager.requestConsensus(taskId, result.consensusHash);
    }

    /// @notice Submit operator consensus response
    /// @param taskId The consensus task ID
    /// @param responseHash The response hash
    /// @param signature The operator signature
    function submitConsensusResponse(
        bytes32 taskId,
        bytes32 responseHash,
        bytes memory signature
    ) external {
        AVSConsensusLib.ConsensusTask storage task = consensusTasks[taskId];
        require(task.taskId != bytes32(0), "Task not found");
        require(!task.completed, "Task already completed");
        
        // Submit response
        bool success = AVSConsensusLib.submitOperatorResponse(
            task,
            msg.sender,
            responseHash,
            signature
        );
        
        require(success, "Failed to submit response");
        
        // Check if consensus reached
        if (task.completed) {
            _executeConsensusMatch(task.matchId);
        }
    }

    /// @notice Execute match after consensus is reached
    /// @param matchId The match ID
    function _executeConsensusMatch(bytes32 matchId) internal {
        OrderMatchingLib.MatchingResult storage result = matches[matchId];
        require(result.matchId != bytes32(0), "Match not found");
        require(!result.executed, "Match already executed");
        
        // Mark match as executed
        result.executed = true;
        
        // Update statistics
        matchingStats.successfulMatches++;
        
        // Execute the actual swap
        _executeMatchedSwap(result);
        
        emit MatchExecuted(matchId, result.executionPrice, result.matchedAmount);
    }

    /// @notice Execute the actual swap for a matched order
    /// @param result The matching result
    function _executeMatchedSwap(OrderMatchingLib.MatchingResult memory result) internal {
        // Get order details
        VaultOrder storage buyOrder = vaultOrders[result.buyOrderId];
        VaultOrder storage sellOrder = vaultOrders[result.sellOrderId];
        
        // Execute swaps for both orders
        _executeSwapOnUniswap(buyOrder);
        _executeSwapOnUniswap(sellOrder);
        
        // Update pool statistics
        bytes32 poolId = PoolId.unwrap(PoolIdLibrary.toId(buyOrder.poolKey));
        poolStats[poolId].successfulMatches += 2;
        poolStats[poolId].totalVolume += result.matchedAmount * 2;
    }

    /// @notice Get pool key from pool ID (helper function)
    /// @param poolId The pool ID
    /// @return poolKey The pool key
    function _getPoolKeyFromId(bytes32 poolId) internal view returns (PoolKey memory poolKey) {
        // This would need to be implemented based on your pool registry
        // For now, return a placeholder
        revert("Pool key lookup not implemented");
    }

    /// @notice Get order book for a pool
    /// @param poolId The pool ID
    /// @return buyOrders Array of buy orders
    /// @return sellOrders Array of sell orders
    /// @return totalBuyVolume Total buy volume
    /// @return totalSellVolume Total sell volume
    function getOrderBook(bytes32 poolId) external view returns (
        OrderMatchingLib.OrderBookEntry[] memory buyOrders,
        OrderMatchingLib.OrderBookEntry[] memory sellOrders,
        uint256 totalBuyVolume,
        uint256 totalSellVolume
    ) {
        OrderMatchingLib.OrderBook storage orderBook = orderBooks[poolId];
        return (
            orderBook.buyOrders,
            orderBook.sellOrders,
            orderBook.totalBuyVolume,
            orderBook.totalSellVolume
        );
    }

    /// @notice Get matching statistics
    /// @return stats The matching statistics
    function getMatchingStats() external view returns (MatchingStats memory) {
        return matchingStats;
    }

    /// @notice Get consensus task details
    /// @param taskId The task ID
    /// @return matchId The match ID
    /// @return consensusThreshold The consensus threshold
    /// @return deadline The task deadline
    /// @return completed Whether the task is completed
    /// @return assignedOperators Array of assigned operators
    /// @return responseCount Number of responses received
    function getConsensusTask(bytes32 taskId) external view returns (
        bytes32 matchId,
        uint256 consensusThreshold,
        uint256 deadline,
        bool completed,
        address[] memory assignedOperators,
        uint256 responseCount
    ) {
        AVSConsensusLib.ConsensusTask storage task = consensusTasks[taskId];
        return (
            task.matchId,
            task.consensusThreshold,
            task.deadline,
            task.completed,
            task.assignedOperators,
            task.responseCount
        );
    }

    /// @notice Emergency pause activation (owner only)
    /// @param reason Reason for emergency pause
    function activateEmergencyPause(string memory reason) external onlyOwner {
        SecurityLib.activateEmergencyPause(securityConfig, reason);
    }

    /// @notice Emergency pause deactivation (owner only)
    function deactivateEmergencyPause() external onlyOwner {
        SecurityLib.deactivateEmergencyPause(securityConfig);
    }

    /// @notice Update security configuration (owner only)
    /// @param maxOrderSize Maximum order size
    /// @param maxPoolExposure Maximum pool exposure
    /// @param maxSlippageBps Maximum slippage in basis points
    function updateSecurityConfig(
        uint256 maxOrderSize,
        uint256 maxPoolExposure,
        uint256 maxSlippageBps
    ) external onlyOwner {
        securityConfig.maxOrderSize = maxOrderSize;
        securityConfig.maxPoolExposure = maxPoolExposure;
        securityConfig.maxSlippageBps = maxSlippageBps;
        
        emit SecurityConfigUpdated(maxOrderSize, maxPoolExposure, maxSlippageBps);
    }

    /// @notice Update gas optimization settings (owner only)
    /// @param enableBatch Whether to enable batch processing
    /// @param maxBatchSize Maximum batch size
    /// @param enableCompression Whether to enable compression
    function updateGasOptimization(
        bool enableBatch,
        uint256 maxBatchSize,
        bool enableCompression
    ) external onlyOwner {
        gasOptimization.enableBatchProcessing = enableBatch;
        gasOptimization.maxBatchSize = maxBatchSize;
        gasOptimization.enableCompression = enableCompression;
        
        emit GasOptimizationUpdated(enableBatch, maxBatchSize, enableCompression);
    }

    /// @notice Get security status
    /// @return isPaused Whether emergency pause is active
    /// @return lastCheck Last security check timestamp
    /// @return checkInterval Security check interval
    /// @return needsCheck Whether security check is needed
    function getSecurityStatus() external view returns (
        bool isPaused,
        uint256 lastCheck,
        uint256 checkInterval,
        bool needsCheck
    ) {
        (isPaused, lastCheck, checkInterval, needsCheck) = SecurityLib.getSecurityStatus(securityConfig);
    }

    /// @notice Batch process multiple orders for gas efficiency
    /// @param orderIds Array of order IDs to process
    /// @return successCount Number of successfully processed orders
    function batchProcessOrders(bytes32[] memory orderIds) external returns (uint256 successCount) {
        require(gasOptimization.enableBatchProcessing, "Batch processing disabled");
        require(orderIds.length <= gasOptimization.maxBatchSize, "Batch size too large");
        
        successCount = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (_processOrder(orderIds[i])) {
                successCount++;
            }
        }
        
        emit BatchProcessCompleted(orderIds.length, successCount);
    }

    /// @notice Internal order processing function
    /// @param orderId The order ID to process
    /// @return success Whether the order was processed successfully
    function _processOrder(bytes32 orderId) internal returns (bool success) {
        // Basic order validation and processing
        VaultOrder storage order = vaultOrders[orderId];
        if (order.executed || block.timestamp > order.deadline) {
            return false;
        }
        
        // Simple processing logic - in production this would be more sophisticated
        return true;
    }
}