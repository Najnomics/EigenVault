// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOrderVault
/// @notice Interface for the Order Vault that stores encrypted orders
interface IOrderVault {
    /// @notice Emitted when an order is stored in the vault
    event OrderStored(
        bytes32 indexed orderId,
        address indexed trader,
        bytes encryptedOrder,
        uint256 timestamp
    );

    /// @notice Emitted when an order is retrieved from the vault
    event OrderRetrieved(
        bytes32 indexed orderId,
        address indexed operator,
        uint256 timestamp
    );

    /// @notice Emitted when an order expires
    event OrderExpired(
        bytes32 indexed orderId,
        address indexed trader,
        uint256 timestamp
    );

    /// @notice Structure for vault storage metadata
    struct VaultOrder {
        bytes32 orderId;
        address trader;
        bytes encryptedOrder;
        uint256 deadline;
        uint256 timestamp;
        bool retrieved;
        bool expired;
    }

    /// @notice Store an encrypted order in the vault
    /// @param orderId The unique order identifier
    /// @param trader The trader address
    /// @param encryptedOrder The encrypted order data
    /// @param deadline The order deadline
    function storeOrder(
        bytes32 orderId,
        address trader,
        bytes calldata encryptedOrder,
        uint256 deadline
    ) external;

    /// @notice Retrieve an encrypted order from the vault (operators only)
    /// @param orderId The order identifier
    /// @return encryptedOrder The encrypted order data
    function retrieveOrder(bytes32 orderId) external returns (bytes memory encryptedOrder);

    /// @notice Mark an order as expired
    /// @param orderId The order identifier
    function expireOrder(bytes32 orderId) external;

    /// @notice Get vault order metadata
    /// @param orderId The order identifier
    /// @return vaultOrder The vault order details
    function getVaultOrder(bytes32 orderId) external view returns (VaultOrder memory vaultOrder);

    /// @notice Check if an order exists and is valid
    /// @param orderId The order identifier
    /// @return exists Whether the order exists
    /// @return valid Whether the order is still valid (not expired/retrieved)
    function isValidOrder(bytes32 orderId) external view returns (bool exists, bool valid);

    /// @notice Get total number of active orders
    /// @return count The number of active orders
    function getActiveOrderCount() external view returns (uint256 count);
}