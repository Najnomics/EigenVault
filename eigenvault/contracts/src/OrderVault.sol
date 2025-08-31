// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOrderVault} from "./interfaces/IOrderVault.sol";
import {ZKProofLib} from "./libraries/ZKProofLib.sol";

/// @notice Order structure for ZK proof verification
struct StoredOrder {
    uint256 amount;
    bool zeroForOne;
    uint256 price;
    uint256 deadline;
    address trader;
    bool executed;
    bytes32 commitment;
    bytes32 poolId;
}

/// @title OrderVault
/// @notice Secure storage for orders using ZK proof verification
/// @dev Manages order storage, retrieval, and lifecycle with ZK proof integration
contract OrderVault is ReentrancyGuard, Ownable, IOrderVault {
    constructor() Ownable(msg.sender) {}
    
    // Errors
    error OrderVault__InvalidSender();
    error OrderVault__InvalidReceiver();
    error OrderVault__OrderNotFound();
    error OrderVault__OrderAlreadyExecuted();
    error OrderVault__OrderExpired();
    error OrderVault__UnauthorizedOperator();
    error OrderVault__InvalidZKProof();

    // State variables
    mapping(bytes32 => StoredOrder) public vaultOrders;
    mapping(address => bool) public authorizedOperators;
    mapping(address => bool) public authorizedHooks;
    
    // Statistics
    uint256 public totalOrders;
    uint256 public totalVolume;
    uint256 public totalValue;

    // Events
    event VaultOrderStored(
        bytes32 indexed orderId,
        address indexed trader,
        uint256 amount,
        bool zeroForOne,
        uint256 deadline
    );
    
    event VaultOrderRetrieved(
        bytes32 indexed orderId,
        address indexed operator,
        uint256 timestamp
    );
    
    event VaultOrderExpired(
        bytes32 indexed orderId,
        address indexed trader,
        uint256 timestamp
    );
    
    event OperatorAuthorized(address indexed operator, bool authorized);
    event HookAuthorized(address indexed hook, bool authorized);
    event StatisticsUpdated(uint256 totalOrders, uint256 totalVolume, uint256 totalValue);

    // Modifiers
    modifier onlyAuthorizedOperator() {
        if (!authorizedOperators[msg.sender]) {
            revert OrderVault__UnauthorizedOperator();
        }
        _;
    }

    modifier onlyAuthorizedHook() {
        if (!authorizedHooks[msg.sender]) {
            revert OrderVault__UnauthorizedOperator();
        }
        _;
    }

    /// @notice Store an order in the vault
    /// @param orderId The order ID
    /// @param amount The order amount
    /// @param zeroForOne Whether this is a buy (false) or sell (true) order
    /// @param price The order price
    /// @param deadline The order deadline
    /// @param trader The order trader
    /// @param commitment The order commitment hash
    /// @param poolId The pool ID
    function storeOrder(
        bytes32 orderId,
        uint256 amount,
        bool zeroForOne,
        uint256 price,
        uint256 deadline,
        address trader,
        bytes32 commitment,
        bytes32 poolId
    ) public onlyAuthorizedHook {
        _storeOrderInternal(orderId, amount, zeroForOne, price, deadline, trader, commitment, poolId);
    }

    /// @notice Retrieve an order from the vault
    /// @param orderId The order ID
    /// @return The order details
    function getOrder(bytes32 orderId) public view returns (StoredOrder memory) {
        StoredOrder memory order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        return order;
    }

    /// @notice Mark an order as executed
    /// @param orderId The order ID
    /// @param zkProof The ZK proof of valid execution
    function markOrderExecuted(
        bytes32 orderId,
        bytes calldata zkProof
    ) external onlyAuthorizedOperator {
        StoredOrder storage order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        if (order.executed) {
            revert OrderVault__OrderAlreadyExecuted();
        }

        // Verify ZK proof (this would integrate with your ZK proof system)
        require(_verifyZKProof(orderId, zkProof), "Invalid ZK proof");

        order.executed = true;

        emit VaultOrderRetrieved(orderId, msg.sender, block.timestamp);
    }

    /// @notice Check if an order is expired
    /// @param orderId The order ID
    /// @return True if expired, false otherwise
    function isOrderExpired(bytes32 orderId) external view returns (bool) {
        StoredOrder memory order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        return block.timestamp > order.deadline;
    }

    /// @notice Check if an order is valid for execution
    /// @param orderId The order ID
    /// @return True if valid, false otherwise
    function isOrderValid(bytes32 orderId) external view returns (bool) {
        StoredOrder memory order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        return !order.executed && block.timestamp <= order.deadline;
    }

    /// @notice Get order statistics
    /// @return _totalOrders The total number of orders
    /// @return _totalVolume The total volume of orders
    /// @return _totalValue The total value of orders
    function getStatistics() external view returns (
        uint256 _totalOrders,
        uint256 _totalVolume,
        uint256 _totalValue
    ) {
        return (totalOrders, totalVolume, totalValue);
    }

    /// @notice Verify ZK proof for order execution
    /// @param orderId The order ID
    /// @param zkProof The ZK proof
    function _verifyZKProof(bytes32 orderId, bytes calldata zkProof) internal view returns (bool) {
        // Decode the ZK proof data
        (bytes32 proofId, bytes memory proofData, bytes32[] memory commitments, bytes32 validityHash, uint256 timestamp, address proofOperator) = 
            abi.decode(zkProof, (bytes32, bytes, bytes32[], bytes32, uint256, address));
        
        // Basic validation
        if (proofData.length == 0 || commitments.length == 0) {
            return false;
        }
        
        // Check proof freshness (24 hours)
        if (block.timestamp > timestamp + 24 hours) {
            return false;
        }
        
        // Verify the proof using ZKProofLib
        ZKProofLib.PrivacyProof memory privacyProof = ZKProofLib.PrivacyProof({
            proofId: proofId,
            proof: proofData,
            commitments: commitments,
            validityHash: validityHash,
            timestamp: timestamp,
            operator: proofOperator
        });
        
        // Get the expected commitment for this order
        StoredOrder memory order = vaultOrders[orderId];
        bytes32[] memory expectedCommitments = new bytes32[](1);
        expectedCommitments[0] = order.commitment;
        
        (bool isValid, ZKProofLib.ProofError error) = 
            ZKProofLib.verifyPrivacyProof(privacyProof, expectedCommitments);
        
        return isValid && error == ZKProofLib.ProofError.None;
    }

    /// @notice Authorize an operator
    /// @param operator The operator address
    /// @param authorized Whether to authorize
    function authorizeOperator(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "Invalid operator");
        authorizedOperators[operator] = authorized;
        emit OperatorAuthorized(operator, authorized);
    }

    /// @notice Authorize a hook
    /// @param hook The hook address
    /// @param authorized Whether to authorize
    function authorizeHook(address hook, bool authorized) external onlyOwner {
        require(hook != address(0), "Invalid hook");
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    /// @notice Get order details for ZK proof generation
    /// @param orderId The order ID
    /// @return amount The order amount
    /// @return zeroForOne The order direction
    /// @return price The order price
    /// @return deadline The order deadline
    /// @return trader The order trader
    /// @return commitment The order commitment
    /// @return poolId The pool ID
    function getOrderForZKProof(bytes32 orderId) external view returns (
        uint256 amount,
        bool zeroForOne,
        uint256 price,
        uint256 deadline,
        address trader,
        bytes32 commitment,
        bytes32 poolId
    ) {
        StoredOrder memory order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        
        return (
            order.amount,
            order.zeroForOne,
            order.price,
            order.deadline,
            order.trader,
            order.commitment,
            order.poolId
        );
    }

    /// @notice Batch store multiple orders
    /// @param orderIds Array of order IDs
    /// @param amounts Array of amounts
    /// @param zeroForOnes Array of zeroForOne flags
    /// @param prices Array of prices
    /// @param deadlines Array of deadlines
    /// @param traders Array of traders
    /// @param commitments Array of commitments
    /// @param poolIds Array of pool IDs
    function batchStoreOrders(
        bytes32[] calldata orderIds,
        uint256[] calldata amounts,
        bool[] calldata zeroForOnes,
        uint256[] calldata prices,
        uint256[] calldata deadlines,
        address[] calldata traders,
        bytes32[] calldata commitments,
        bytes32[] calldata poolIds
    ) external onlyAuthorizedHook {
        require(
            orderIds.length == amounts.length &&
            amounts.length == zeroForOnes.length &&
            zeroForOnes.length == prices.length &&
            prices.length == deadlines.length &&
            deadlines.length == traders.length &&
            traders.length == commitments.length &&
            commitments.length == poolIds.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < orderIds.length; i++) {
            storeOrder(
                orderIds[i],
                amounts[i],
                zeroForOnes[i],
                prices[i],
                deadlines[i],
                traders[i],
                commitments[i],
                poolIds[i]
            );
        }
    }

    /// @notice Clean up expired orders
    /// @param orderIds Array of order IDs to clean up
    function cleanupExpiredOrders(bytes32[] calldata orderIds) external onlyAuthorizedOperator {
        for (uint256 i = 0; i < orderIds.length; i++) {
            bytes32 orderId = orderIds[i];
            StoredOrder storage order = vaultOrders[orderId];
            
            if (order.trader != address(0) && !order.executed && block.timestamp > order.deadline) {
                emit VaultOrderExpired(orderId, order.trader, block.timestamp);
                
                // Remove order data
                delete vaultOrders[orderId];
            }
        }
    }

    // ============ Interface Implementation ============

    /// @notice Store an order (interface implementation)
    /// @param orderId The order ID
    /// @param amount The order amount
    /// @param zeroForOne The order direction
    /// @param price The order price


    /// @notice Internal function to store an order
    /// @param orderId The order ID
    /// @param amount The order amount
    /// @param zeroForOne The order direction
    /// @param price The order price
    /// @param deadline The order deadline
    /// @param trader The order trader
    /// @param commitment The order commitment
    /// @param poolId The pool ID
    function _storeOrderInternal(
        bytes32 orderId,
        uint256 amount,
        bool zeroForOne,
        uint256 price,
        uint256 deadline,
        address trader,
        bytes32 commitment,
        bytes32 poolId
    ) internal {
        require(trader != address(0), "Invalid trader");
        require(amount > 0, "Invalid amount");
        require(deadline > block.timestamp, "Invalid deadline");
        require(commitment != bytes32(0), "Invalid commitment");

        vaultOrders[orderId] = StoredOrder({
            amount: amount,
            zeroForOne: zeroForOne,
            price: price,
            deadline: deadline,
            trader: trader,
            executed: false,
            commitment: commitment,
            poolId: poolId
        });

        totalOrders++;
        totalVolume += amount;
        totalValue += amount * price;

        emit VaultOrderStored(orderId, trader, amount, zeroForOne, deadline);
        emit StatisticsUpdated(totalOrders, totalVolume, totalValue);
    }

    /// @notice Retrieve an order (interface implementation)
    /// @param orderId The order ID
    /// @return The encrypted order data
    function retrieveOrder(bytes32 orderId) external view override returns (bytes memory) {
        StoredOrder memory order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        
        // Return encoded order data
        return abi.encode(order);
    }

    /// @notice Expire an order
    /// @param orderId The order ID
    function expireOrder(bytes32 orderId) external override {
        StoredOrder storage order = vaultOrders[orderId];
        if (order.trader == address(0)) {
            revert OrderVault__OrderNotFound();
        }
        
        if (!order.executed && block.timestamp > order.deadline) {
            emit VaultOrderExpired(orderId, order.trader, block.timestamp);
            delete vaultOrders[orderId];
        }
    }

    /// @notice Get vault order details
    /// @param orderId The order ID
    /// @return vaultOrder The vault order details
    function getVaultOrder(bytes32 orderId) external view override returns (VaultOrder memory vaultOrder) {
        StoredOrder memory stored = vaultOrders[orderId];
        require(stored.trader != address(0), "Order not found");
        
        // Convert StoredOrder to VaultOrder format for interface compliance
        vaultOrder = VaultOrder({
            orderId: orderId,
            trader: stored.trader,
            encryptedOrder: abi.encode(stored.amount, stored.zeroForOne, stored.price, stored.commitment, stored.poolId),
            deadline: stored.deadline,
            timestamp: block.timestamp,
            retrieved: false, // This would need proper tracking
            expired: block.timestamp > stored.deadline,
            executed: stored.executed
        });
    }

    /// @notice Check if an order is valid
    /// @param orderId The order ID
    /// @return exists Whether the order exists
    /// @return valid Whether the order is valid
    function isValidOrder(bytes32 orderId) external view override returns (bool exists, bool valid) {
        StoredOrder memory order = vaultOrders[orderId];
        exists = order.trader != address(0);
        valid = exists && !order.executed && block.timestamp <= order.deadline;
    }

    /// @notice Get active order count
    /// @return count The number of active orders
    function getActiveOrderCount() external view override returns (uint256 count) {
        // This would require iterating through all orders
        // For now, return a placeholder
        return totalOrders;
    }
}