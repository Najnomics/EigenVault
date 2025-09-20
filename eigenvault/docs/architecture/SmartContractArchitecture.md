# EigenVault Smart Contract Architecture

## Overview

This document provides a detailed technical architecture of the EigenVault smart contract system, including contract relationships, data flow, and security considerations.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    EigenVault System Architecture              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │   Uniswap v4    │  │  EigenLayer AVS  │  │   Order Vault   │  │
│  │      Hook       │◄─►│   ServiceManager │◄─►│   Storage      │  │
│  │                 │  │                  │  │                 │  │
│  │ • Order Routing │  │ • Operator Mgmt  │  │ • Encrypted     │  │
│  │ • Classification│  │ • Task Dist.     │  │   Storage       │  │
│  │ • Execution     │  │ • Proof Verify   │  │ • Order Mgmt    │  │
│  │ • Fallback      │  │ • Rewards        │  │ • Expiration    │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
│           │                       │                       │      │
│           ▼                       ▼                       ▼      │
│  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Order Processing│  │ Private Matching │  │ ZK Proof        │  │
│  │ & Validation    │  │ & Verification   │  │ Verification    │  │
│  └─────────────────┘  └──────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Contracts

### 1. EigenVaultHook.sol

The main Uniswap v4 hook that orchestrates the entire system.

#### Key Responsibilities
- **Order Interception**: Catches all swaps before execution
- **Size Classification**: Determines if orders need private processing
- **Routing Logic**: Routes large orders to AVS, small orders to AMM
- **Execution Coordination**: Manages the execution of matched orders

#### Hook Permissions
```solidity
function getHookPermissions() public pure override returns (HookPermissions memory) {
    return HookPermissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: false,
        afterAddLiquidity: false,
        beforeRemoveLiquidity: false,
        afterRemoveLiquidity: false,
        beforeSwap: true,    // ✅ Intercept swaps
        afterSwap: true,     // ✅ Handle post-swap logic
        beforeDonate: false,
        afterDonate: false
    });
}
```

#### Order Classification Logic
```solidity
function isLargeOrder(uint256 amount, PoolKey calldata key) internal view returns (bool) {
    uint256 poolLiquidity = getPoolLiquidity(key);
    uint256 threshold = (poolLiquidity * vaultThresholdBps) / 10000;
    return amount >= threshold; // Default: 1% of pool liquidity
}
```

#### State Variables
```solidity
contract EigenVaultHook is BaseHook {
    // Core dependencies
    IOrderVault public immutable ORDER_VAULT;
    IEigenVaultAVSServiceManager public immutable EIGEN_VAULT_AVS;
    
    // Configuration
    uint256 public vaultThresholdBps; // Default: 100 (1%)
    mapping(bytes32 => uint256) public poolThresholdBps; // Pool-specific thresholds
    
    // Statistics
    mapping(bytes32 => uint256) public poolOrderCounts;
    mapping(bytes32 => uint256) public poolTotalVolumes;
    
    // Security
    bool public emergencyPause;
    uint8 public securityConfig;
    bool public gasOptimizationEnabled;
}
```

### 2. EigenVaultAVSServiceManager.sol

Central coordination contract for the EigenLayer AVS network.

#### Key Responsibilities
- **Operator Registration**: Manages AVS operator onboarding and staking
- **Task Distribution**: Distributes order matching tasks to operator quorum
- **Proof Verification**: Validates ZK proofs of successful matches
- **Reward Distribution**: Distributes fees to performing operators
- **Slashing Enforcement**: Executes penalties for malicious behavior

#### Operator Management
```solidity
struct OperatorInfo {
    address operator;
    uint256 stake;
    uint256 registrationTime;
    bool isActive;
    uint256 performanceScore;
    uint256 totalRewards;
}

mapping(address => OperatorInfo) public operators;
address[] public operatorList;
uint256 public totalStake;
```

#### Task Management
```solidity
struct MatchingTask {
    bytes32 orderSetHash;        // Hash of orders to match
    uint256 deadline;            // Execution deadline
    bytes32 quorumBitmask;       // Required operator participation
    uint256 minimumStake;        // Minimum operator stake required
    MatchingStatus status;       // Task status tracking
    uint256 rewardAmount;        // Reward for successful completion
}

mapping(bytes32 => MatchingTask) public tasks;
mapping(bytes32 => address[]) public taskOperators;
```

#### Reward System
```solidity
function distributeReward(bytes32 taskId, address[] calldata operators, uint256[] calldata amounts) external {
    require(msg.sender == authorizedCaller, "Unauthorized");
    
    for (uint256 i = 0; i < operators.length; i++) {
        address operator = operators[i];
        uint256 amount = amounts[i];
        
        require(operators[operator].isActive, "Operator not active");
        require(operators[operator].stake >= minimumStake, "Insufficient stake");
        
        // Transfer reward
        payable(operator).transfer(amount);
        
        // Update operator statistics
        operators[operator].totalRewards += amount;
        operators[operator].performanceScore += 1;
    }
}
```

### 3. OrderVault.sol

Secure storage for encrypted orders with comprehensive order management.

#### Order Storage
```solidity
struct PrivateOrder {
    address trader;              // Order creator
    bool zeroForOne;            // Swap direction
    uint256 amountSpecified;    // Order amount
    bytes32 commitment;         // Hash of order details + nonce
    uint256 deadline;           // Order expiration
    uint256 nonce;              // Order nonce for uniqueness
    OrderStatus status;         // Order status tracking
    uint256 createdAt;          // Creation timestamp
    uint256 matchedAt;          // Matching timestamp
}

mapping(bytes32 => PrivateOrder) public orders;
mapping(address => bytes32[]) public traderOrders;
mapping(bytes32 => bytes32[]) public poolOrders;
```

#### Access Control
```solidity
modifier onlyAuthorizedHook() {
    require(authorizedHooks[msg.sender], "Unauthorized hook");
    _;
}

modifier onlyAuthorizedAVS() {
    require(authorizedAVS[msg.sender], "Unauthorized AVS");
    _;
}
```

#### Order Lifecycle Management
```solidity
function storeOrder(
    bytes32 orderId,
    address trader,
    bool zeroForOne,
    uint256 amountSpecified,
    bytes32 commitment,
    uint256 deadline
) external onlyAuthorizedHook returns (bool) {
    require(orders[orderId].trader == address(0), "Order exists");
    require(deadline > block.timestamp, "Invalid deadline");
    
    orders[orderId] = PrivateOrder({
        trader: trader,
        zeroForOne: zeroForOne,
        amountSpecified: amountSpecified,
        commitment: commitment,
        deadline: deadline,
        nonce: orderNonce++,
        status: OrderStatus.Pending,
        createdAt: block.timestamp,
        matchedAt: 0
    });
    
    traderOrders[trader].push(orderId);
    poolOrders[getPoolId()].push(orderId);
    
    emit OrderStored(orderId, trader, amountSpecified);
    return true;
}
```

## Data Flow Architecture

### 1. Order Submission Flow

```
User → Hook → Order Classification → Large Order? → Yes → Vault Storage
                                        ↓
                                      No → Direct AMM Execution
```

#### Detailed Flow
1. **User submits order** via Uniswap v4 interface
2. **Hook intercepts** order in `beforeSwap()`
3. **Order classification** determines if order is "large"
4. **Large orders** routed to OrderVault for private processing
5. **Small orders** proceed with standard AMM execution

### 2. Private Matching Flow

```
Vault Storage → AVS Operators → Private Matching → ZK Proof → Verification → Execution
```

#### Detailed Flow
1. **Order stored** in OrderVault with encryption
2. **AVS operators** receive matching tasks
3. **Private matching** performed off-chain
4. **ZK proof** generated for valid matches
5. **On-chain verification** of proofs
6. **Atomic execution** of matched orders

### 3. Execution Flow

```
Matched Orders → Hook Execution → AMM Integration → Final Settlement
```

#### Detailed Flow
1. **Matched orders** submitted to hook
2. **Hook validates** proofs and signatures
3. **Orders executed** atomically via AMM
4. **Settlement** and reward distribution

## Security Architecture

### 1. Access Control

#### Role-Based Access Control
```solidity
enum Role {
    OWNER,           // Contract owner
    OPERATOR,        // AVS operators
    AUTHORIZED_HOOK, // Authorized hooks
    AUTHORIZED_AVS   // Authorized AVS contracts
}

mapping(address => Role) public roles;
mapping(Role => bool) public rolePermissions;
```

#### Permission Matrix
| Function | Owner | Operator | Hook | AVS |
|----------|-------|----------|------|-----|
| Update Config | ✅ | ❌ | ❌ | ❌ |
| Store Order | ❌ | ❌ | ✅ | ❌ |
| Process Order | ❌ | ❌ | ❌ | ✅ |
| Manage Operators | ✅ | ❌ | ❌ | ❌ |
| Emergency Pause | ✅ | ❌ | ❌ | ❌ |

### 2. Cryptoeconomic Security

#### Slashing Conditions
```solidity
enum SlashingCondition {
    INVALID_MATCHING,    // Submitting impossible price matches
    ORDER_LEAKAGE,       // Revealing private order information
    FRONT_RUNNING,       // Using order info for personal gain
    AVAILABILITY,        // Failing to process orders within SLA
    COLLUSION            // Coordinating with other operators
}

mapping(SlashingCondition => uint256) public slashingPenalties;
```

#### Stake Requirements
- **Minimum Stake**: 32 ETH per operator
- **Slashing Penalties**: 25-100% of stake depending on violation
- **Performance Requirements**: Minimum performance score for rewards

### 3. Privacy Protection

#### Multi-Layer Privacy
1. **Client-Side Encryption**: Orders encrypted before submission
2. **Commitment Schemes**: Order details hidden until execution
3. **Zero-Knowledge Proofs**: Valid matching without revealing orders
4. **Threshold Decryption**: Requires multiple operators for decryption

#### Privacy Guarantees
- **Order Privacy**: Individual orders remain private until matching
- **Strategy Privacy**: Trading strategies not revealed
- **Execution Privacy**: Matched orders executed atomically
- **Metadata Privacy**: Order metadata protected

## Gas Optimization

### 1. Storage Optimization

#### Packed Structs
```solidity
struct OptimizedOrder {
    address trader;        // 20 bytes
    uint32 nonce;          // 4 bytes
    uint64 amountSpecified; // 8 bytes
    bool zeroForOne;       // 1 byte
    uint8 status;          // 1 byte
    // Total: 34 bytes (fits in 2 storage slots)
}
```

#### Efficient Mappings
```solidity
// Use bytes32 keys for efficient lookups
mapping(bytes32 => OrderInfo) public ordersByHash;

// Use arrays for iteration
bytes32[] public activeOrders;
mapping(bytes32 => uint256) public orderIndex;
```

### 2. Function Optimization

#### Batch Operations
```solidity
function batchProcessOrders(bytes32[] calldata orderIds) external {
    for (uint256 i = 0; i < orderIds.length; i++) {
        processOrder(orderIds[i]);
    }
}
```

#### Efficient Loops
```solidity
// Use unchecked arithmetic for known-safe operations
unchecked {
    for (uint256 i = 0; i < length; i++) {
        // Safe operations
    }
}
```

## Integration Architecture

### 1. Uniswap v4 Integration

#### Hook Interface Implementation
```solidity
contract EigenVaultHook is BaseHook {
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (isLargeOrder(params.amountSpecified, key)) {
            return routeToVault(sender, key, params, hookData);
        }
        return BaseHook.beforeSwap.selector;
    }
}
```

#### Pool Manager Integration
```solidity
function executeMatchedOrder(
    bytes32 orderId,
    PoolKey calldata key,
    SwapParams calldata params
) external onlyAuthorizedAVS returns (BalanceDelta) {
    // Validate order and proof
    require(orders[orderId].status == OrderStatus.Pending, "Invalid order");
    
    // Execute swap
    BalanceDelta delta = poolManager.swap(key, params, hookData);
    
    // Update order status
    orders[orderId].status = OrderStatus.Executed;
    orders[orderId].matchedAt = block.timestamp;
    
    return delta;
}
```

### 2. EigenLayer Integration

#### AVS Registration
```solidity
function registerWithEigenLayer() external onlyOwner {
    // Register as AVS with EigenLayer
    IAVSDirectory avsDirectory = IAVSDirectory(EIGENLAYER_AVS_DIRECTORY);
    avsDirectory.registerAVS(
        AVS_NAME,
        AVS_METADATA_URI,
        minimumStake,
        quorumThreshold
    );
}
```

#### Operator Management
```solidity
function registerOperator(address operator, uint256 stake) external {
    require(stake >= minimumStake, "Insufficient stake");
    require(!operators[operator].isActive, "Already registered");
    
    operators[operator] = OperatorInfo({
        operator: operator,
        stake: stake,
        registrationTime: block.timestamp,
        isActive: true,
        performanceScore: 0,
        totalRewards: 0
    });
    
    operatorList.push(operator);
    totalStake += stake;
    
    emit OperatorRegistered(operator, stake);
}
```

## Error Handling

### 1. Error Categories

#### Validation Errors
```solidity
error InvalidOrder(bytes32 orderId, string reason);
error InvalidProof(bytes32 proofId, string reason);
error InvalidOperator(address operator, string reason);
```

#### Access Control Errors
```solidity
error Unauthorized(address caller, string requiredRole);
error InsufficientStake(address operator, uint256 required, uint256 provided);
error EmergencyPauseActive();
```

#### Business Logic Errors
```solidity
error OrderExpired(bytes32 orderId, uint256 deadline);
error OrderAlreadyExecuted(bytes32 orderId);
error InsufficientLiquidity(uint256 required, uint256 available);
```

### 2. Error Recovery

#### Graceful Degradation
```solidity
function handleOrderFailure(bytes32 orderId, string memory reason) internal {
    orders[orderId].status = OrderStatus.Failed;
    emit OrderFailed(orderId, reason);
    
    // Fallback to AMM if possible
    if (canFallbackToAMM(orderId)) {
        fallbackToAMM(orderId);
    }
}
```

#### Emergency Procedures
```solidity
function emergencyPause() external onlyOwner {
    emergencyPause = true;
    emit EmergencyPauseActivated(block.timestamp);
}

function emergencyWithdraw(bytes32 orderId) external onlyOwner {
    require(emergencyPause, "Not in emergency mode");
    // Emergency withdrawal logic
}
```

## Monitoring and Observability

### 1. Event Architecture

#### Core Events
```solidity
event OrderStored(bytes32 indexed orderId, address indexed trader, uint256 amount);
event OrderMatched(bytes32 indexed orderId, bytes32 indexed matchId, uint256 price);
event OrderExecuted(bytes32 indexed orderId, uint256 gasUsed);
event OperatorRegistered(address indexed operator, uint256 stake);
event RewardDistributed(address indexed operator, uint256 amount);
event SlashingExecuted(address indexed operator, uint256 amount, string reason);
```

#### Performance Events
```solidity
event GasUsageMeasured(string operation, uint256 gasUsed);
event ExecutionTimeMeasured(string operation, uint256 duration);
event ErrorOccurred(string operation, string error);
```

### 2. Metrics Collection

#### Key Metrics
- **Order Volume**: Total order volume processed
- **Matching Efficiency**: Percentage of orders matched
- **Gas Usage**: Gas consumption per operation
- **Execution Time**: Time to execute orders
- **Error Rates**: Frequency of errors

#### Performance Monitoring
```solidity
struct PerformanceMetrics {
    uint256 totalOrders;
    uint256 matchedOrders;
    uint256 totalGasUsed;
    uint256 averageExecutionTime;
    uint256 errorCount;
}

mapping(string => PerformanceMetrics) public metrics;
```

## Future Enhancements

### 1. Planned Features

#### Advanced Matching
- **Cross-Chain Orders**: Support for cross-chain order matching
- **Complex Orders**: Support for complex order types
- **AI-Powered Matching**: Machine learning for optimal matching

#### Enhanced Privacy
- **Homomorphic Encryption**: Fully homomorphic encryption for matching
- **Secure Multi-Party Computation**: Enhanced privacy-preserving computation
- **Differential Privacy**: Additional privacy guarantees

### 2. Scalability Improvements

#### Layer 2 Integration
- **Optimism**: Layer 2 deployment for reduced gas costs
- **Arbitrum**: Alternative layer 2 solution
- **Polygon**: Sidechain deployment

#### Performance Optimization
- **Batch Processing**: Enhanced batch processing capabilities
- **Parallel Execution**: Parallel order processing
- **Caching**: In-memory caching for frequently accessed data

## Conclusion

The EigenVault smart contract architecture provides a robust, secure, and scalable foundation for privacy-preserving decentralized trading. The system leverages Uniswap v4's hook architecture and EigenLayer's cryptoeconomic security to create a unique dark pool solution that protects institutional traders while maintaining the transparency and security of decentralized finance.

Key architectural strengths include:
- **Modular Design**: Clean separation of concerns
- **Security First**: Multiple layers of security and privacy protection
- **Gas Efficient**: Optimized for minimal gas usage
- **Extensible**: Designed for future enhancements and improvements
- **Well Tested**: Comprehensive test coverage and validation
