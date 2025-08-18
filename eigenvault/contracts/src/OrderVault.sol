// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOrderVault} from "./interfaces/IOrderVault.sol";

/// @title OrderVault
/// @notice Secure storage for encrypted trading orders
contract OrderVault is IOrderVault {
    /// @notice Maximum order lifetime (24 hours)
    uint256 public constant MAX_ORDER_LIFETIME = 24 hours;
    
    /// @notice Minimum order lifetime (5 minutes)
    uint256 public constant MIN_ORDER_LIFETIME = 5 minutes;

    /// @notice Mapping of order IDs to vault orders
    mapping(bytes32 => VaultOrder) public vaultOrders;
    
    /// @notice Mapping of operators to access permissions
    mapping(address => bool) public authorizedOperators;
    
    /// @notice Mapping of hook contracts to access permissions
    mapping(address => bool) public authorizedHooks;
    
    /// @notice Array of active order IDs for enumeration
    bytes32[] public activeOrderIds;
    
    /// @notice Mapping from order ID to index in activeOrderIds array
    mapping(bytes32 => uint256) public orderIdToIndex;
    
    /// @notice Owner of the contract
    address public owner;
    
    /// @notice Total number of orders stored
    uint256 public totalOrdersStored;
    
    /// @notice Total number of orders retrieved
    uint256 public totalOrdersRetrieved;
    
    /// @notice Total number of expired orders
    uint256 public totalOrdersExpired;

    /// @notice Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorizedHook() {
        require(authorizedHooks[msg.sender], "Hook not authorized");
        _;
    }

    modifier onlyAuthorizedOperator() {
        require(authorizedOperators[msg.sender], "Operator not authorized");
        _;
    }

    modifier validOrderId(bytes32 orderId) {
        require(vaultOrders[orderId].orderId != bytes32(0), "Order not found");
        _;
    }

    /// @notice Constructor
    constructor() {
        owner = msg.sender;
    }

    /// @inheritdoc IOrderVault
    function storeOrder(
        bytes32 orderId,
        address trader,
        bytes calldata encryptedOrder,
        uint256 deadline
    ) external onlyAuthorizedHook {
        require(orderId != bytes32(0), "Invalid order ID");
        require(trader != address(0), "Invalid trader address");
        require(encryptedOrder.length > 0, "Empty encrypted order");
        require(
            deadline > block.timestamp + MIN_ORDER_LIFETIME &&
            deadline <= block.timestamp + MAX_ORDER_LIFETIME,
            "Invalid deadline"
        );
        require(vaultOrders[orderId].orderId == bytes32(0), "Order already exists");

        // Create vault order
        VaultOrder memory vaultOrder = VaultOrder({
            orderId: orderId,
            trader: trader,
            encryptedOrder: encryptedOrder,
            deadline: deadline,
            timestamp: block.timestamp,
            retrieved: false,
            expired: false
        });

        // Store the order
        vaultOrders[orderId] = vaultOrder;
        
        // Add to active orders array
        orderIdToIndex[orderId] = activeOrderIds.length;
        activeOrderIds.push(orderId);
        
        totalOrdersStored++;

        emit OrderStored(orderId, trader, encryptedOrder, block.timestamp);
    }

    /// @inheritdoc IOrderVault
    function retrieveOrder(bytes32 orderId) 
        external 
        onlyAuthorizedOperator 
        validOrderId(orderId) 
        returns (bytes memory encryptedOrder) 
    {
        VaultOrder storage vaultOrder = vaultOrders[orderId];
        
        require(!vaultOrder.retrieved, "Order already retrieved");
        require(!vaultOrder.expired, "Order expired");
        require(block.timestamp <= vaultOrder.deadline, "Order deadline passed");

        // Mark as retrieved
        vaultOrder.retrieved = true;
        totalOrdersRetrieved++;

        // Remove from active orders array since it's no longer active
        _removeFromActiveOrders(orderId);

        emit OrderRetrieved(orderId, msg.sender, block.timestamp);

        return vaultOrder.encryptedOrder;
    }

    /// @inheritdoc IOrderVault
    function expireOrder(bytes32 orderId) external validOrderId(orderId) {
        VaultOrder storage vaultOrder = vaultOrders[orderId];
        
        require(!vaultOrder.expired, "Order already expired");
        require(
            block.timestamp > vaultOrder.deadline || 
            msg.sender == vaultOrder.trader ||
            authorizedHooks[msg.sender],
            "Cannot expire order yet"
        );

        // Mark as expired
        vaultOrder.expired = true;
        totalOrdersExpired++;

        // Remove from active orders array
        _removeFromActiveOrders(orderId);

        emit OrderExpired(orderId, vaultOrder.trader, block.timestamp);
    }

    /// @inheritdoc IOrderVault
    function getVaultOrder(bytes32 orderId) 
        external 
        view 
        validOrderId(orderId) 
        returns (VaultOrder memory vaultOrder) 
    {
        return vaultOrders[orderId];
    }

    /// @inheritdoc IOrderVault
    function isValidOrder(bytes32 orderId) 
        external 
        view 
        returns (bool exists, bool valid) 
    {
        VaultOrder memory vaultOrder = vaultOrders[orderId];
        exists = vaultOrder.orderId != bytes32(0);
        
        if (!exists) {
            return (false, false);
        }
        
        valid = !vaultOrder.retrieved && 
                !vaultOrder.expired && 
                block.timestamp <= vaultOrder.deadline;
        
        return (exists, valid);
    }

    /// @inheritdoc IOrderVault
    function getActiveOrderCount() external view returns (uint256 count) {
        return activeOrderIds.length;
    }

    /// @notice Get active order ID by index
    /// @param index The index in the active orders array
    /// @return orderId The order ID at the specified index
    function getActiveOrderId(uint256 index) external view returns (bytes32 orderId) {
        require(index < activeOrderIds.length, "Index out of bounds");
        return activeOrderIds[index];
    }

    /// @notice Get multiple active order IDs
    /// @param startIndex The starting index
    /// @param count The number of orders to retrieve
    /// @return orderIds Array of order IDs
    function getActiveOrderIds(uint256 startIndex, uint256 count) 
        external 
        view 
        returns (bytes32[] memory orderIds) 
    {
        require(startIndex < activeOrderIds.length, "Start index out of bounds");
        
        uint256 endIndex = startIndex + count;
        if (endIndex > activeOrderIds.length) {
            endIndex = activeOrderIds.length;
        }
        
        uint256 actualCount = endIndex - startIndex;
        orderIds = new bytes32[](actualCount);
        
        for (uint256 i = 0; i < actualCount; i++) {
            orderIds[i] = activeOrderIds[startIndex + i];
        }
        
        return orderIds;
    }

    /// @notice Get orders by trader
    /// @param trader The trader address
    /// @param includeExpired Whether to include expired orders
    /// @return orderIds Array of order IDs for the trader
    function getOrdersByTrader(address trader, bool includeExpired) 
        external 
        view 
        returns (bytes32[] memory orderIds) 
    {
        // First pass: count matching orders
        uint256 matchCount = 0;
        for (uint256 i = 0; i < activeOrderIds.length; i++) {
            bytes32 orderId = activeOrderIds[i];
            VaultOrder memory vaultOrder = vaultOrders[orderId];
            
            if (vaultOrder.trader == trader) {
                if (includeExpired || (!vaultOrder.expired && block.timestamp <= vaultOrder.deadline)) {
                    matchCount++;
                }
            }
        }
        
        // Second pass: collect matching order IDs
        orderIds = new bytes32[](matchCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < activeOrderIds.length; i++) {
            bytes32 orderId = activeOrderIds[i];
            VaultOrder memory vaultOrder = vaultOrders[orderId];
            
            if (vaultOrder.trader == trader) {
                if (includeExpired || (!vaultOrder.expired && block.timestamp <= vaultOrder.deadline)) {
                    orderIds[currentIndex] = orderId;
                    currentIndex++;
                }
            }
        }
        
        return orderIds;
    }

    /// @notice Batch expire multiple orders
    /// @param orderIds Array of order IDs to expire
    function batchExpireOrders(bytes32[] calldata orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            bytes32 orderId = orderIds[i];
            
            if (vaultOrders[orderId].orderId == bytes32(0)) {
                continue; // Skip non-existent orders
            }
            
            VaultOrder storage vaultOrder = vaultOrders[orderId];
            
            if (vaultOrder.expired) {
                continue; // Skip already expired orders
            }
            
            // Check expiration conditions
            bool canExpire = block.timestamp > vaultOrder.deadline ||
                           msg.sender == vaultOrder.trader ||
                           authorizedHooks[msg.sender];
            
            if (canExpire) {
                vaultOrder.expired = true;
                totalOrdersExpired++;
                _removeFromActiveOrders(orderId);
                
                emit OrderExpired(orderId, vaultOrder.trader, block.timestamp);
            }
        }
    }

    /// @notice Clean up expired orders (callable by anyone for gas rewards)
    /// @param maxOrders Maximum number of orders to clean up in one call
    function cleanupExpiredOrders(uint256 maxOrders) external {
        uint256 cleaned = 0;
        uint256 i = 0;
        
        while (i < activeOrderIds.length && cleaned < maxOrders) {
            bytes32 orderId = activeOrderIds[i];
            VaultOrder storage vaultOrder = vaultOrders[orderId];
            
            if (block.timestamp > vaultOrder.deadline && !vaultOrder.expired) {
                vaultOrder.expired = true;
                totalOrdersExpired++;
                _removeFromActiveOrders(orderId);
                
                emit OrderExpired(orderId, vaultOrder.trader, block.timestamp);
                cleaned++;
            } else {
                i++;
            }
        }
    }

    /// @notice Authorize a hook contract
    /// @param hook The hook contract address
    function authorizeHook(address hook) external onlyOwner {
        require(hook != address(0), "Invalid hook address");
        authorizedHooks[hook] = true;
    }

    /// @notice Revoke hook authorization
    /// @param hook The hook contract address
    function revokeHookAuthorization(address hook) external onlyOwner {
        authorizedHooks[hook] = false;
    }

    /// @notice Authorize an operator
    /// @param operator The operator address
    function authorizeOperator(address operator) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        authorizedOperators[operator] = true;
    }

    /// @notice Revoke operator authorization
    /// @param operator The operator address
    function revokeOperatorAuthorization(address operator) external onlyOwner {
        authorizedOperators[operator] = false;
    }

    /// @notice Batch authorize multiple operators
    /// @param operators Array of operator addresses
    function batchAuthorizeOperators(address[] calldata operators) external onlyOwner {
        for (uint256 i = 0; i < operators.length; i++) {
            require(operators[i] != address(0), "Invalid operator address");
            authorizedOperators[operators[i]] = true;
        }
    }

    /// @notice Get vault statistics
    /// @return totalStored Total orders stored
    /// @return totalRetrieved Total orders retrieved 
    /// @return totalExpired Total orders expired
    /// @return currentlyActive Currently active orders
    function getVaultStats() external view returns (
        uint256 totalStored,
        uint256 totalRetrieved,
        uint256 totalExpired,
        uint256 currentlyActive
    ) {
        return (
            totalOrdersStored,
            totalOrdersRetrieved,
            totalOrdersExpired,
            activeOrderIds.length
        );
    }

    /// @notice Check if an address is an authorized hook
    /// @param hook The address to check
    /// @return authorized Whether the address is authorized
    function isAuthorizedHook(address hook) external view returns (bool authorized) {
        return authorizedHooks[hook];
    }

    /// @notice Check if an address is an authorized operator
    /// @param operator The address to check
    /// @return authorized Whether the address is authorized
    function isAuthorizedOperator(address operator) external view returns (bool authorized) {
        return authorizedOperators[operator];
    }

    /// @notice Transfer ownership
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    /// @notice Internal function to remove an order from the active orders array
    /// @param orderId The order ID to remove
    function _removeFromActiveOrders(bytes32 orderId) internal {
        uint256 index = orderIdToIndex[orderId];
        uint256 lastIndex = activeOrderIds.length - 1;
        
        if (index != lastIndex) {
            // Move the last element to the position of the element to remove
            bytes32 lastOrderId = activeOrderIds[lastIndex];
            activeOrderIds[index] = lastOrderId;
            orderIdToIndex[lastOrderId] = index;
        }
        
        // Remove the last element
        activeOrderIds.pop();
        delete orderIdToIndex[orderId];
    }

    /// @notice Emergency pause function (owner only)
    /// @dev This would be implemented with a proper pause mechanism in production
    function emergencyPause() external onlyOwner {
        // Implementation would include pausing contract functionality
        // For now, this is a placeholder
    }

    /// @notice Emergency unpause function (owner only)
    /// @dev This would be implemented with a proper pause mechanism in production
    function emergencyUnpause() external onlyOwner {
        // Implementation would include unpausing contract functionality
        // For now, this is a placeholder
    }
}