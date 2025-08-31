// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {OrderVault} from "../src/OrderVault.sol";
import {EigenVaultAVSServiceManager} from "../src/EigenVaultAVSServiceManager.sol";
import {EigenVaultHook} from "../src/EigenVaultHook.sol";


/// @title DeployEigenVaultAVS
/// @notice Deployment script for EigenVault AVS with ZK proofs
/// @dev Deploys all contracts and configures initial setup
contract DeployEigenVaultAVS is Script {
    // Deployed contracts
    OrderVault public orderVault;
    EigenVaultAVSServiceManager public avsServiceManager;
    EigenVaultHook public eigenVaultHook;


    // Configuration
    uint256 public deployerPrivateKey;
    address public deployer;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        console2.log("Deploying EigenVault AVS contracts...");
        console2.log("Deployer:", deployer);

        // Deploy OrderVault
        console2.log("Deploying OrderVault...");
        orderVault = new OrderVault();
        console2.log("OrderVault deployed at:", address(orderVault));

        // Deploy AVS Service Manager
        console2.log("Deploying EigenVaultAVSServiceManager...");
        avsServiceManager = new EigenVaultAVSServiceManager();
        console2.log("EigenVaultAVSServiceManager deployed at:", address(avsServiceManager));



        // Deploy EigenVaultHook
        console2.log("Deploying EigenVaultHook...");
        eigenVaultHook = new EigenVaultHook(
            address(0), // PoolManager - will be set by deployer
            address(orderVault),
            address(avsServiceManager)
        );
        console2.log("EigenVaultHook deployed at:", address(eigenVaultHook));

        // Configure authorizations
        console2.log("Configuring authorizations...");
        
        // Authorize the hook in OrderVault
        orderVault.authorizeHook(address(eigenVaultHook), true);
        console2.log("Hook authorized in OrderVault");

        // Authorize the hook in AVS Service Manager
        eigenVaultHook.setServiceManagerAuthorization(address(avsServiceManager), true);
        console2.log("AVS Service Manager authorized in Hook");





        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("OrderVault:", address(orderVault));
        console2.log("EigenVaultAVSServiceManager:", address(avsServiceManager));

        console2.log("EigenVaultHook:", address(eigenVaultHook));
        console2.log("Deployer:", deployer);
        console2.log("========================\n");

        // Verify deployment
        _verifyDeployment();
    }

    function _verifyDeployment() internal view {
        console2.log("Verifying deployment...");

        // Check OrderVault
        require(address(orderVault) != address(0), "OrderVault not deployed");
        require(orderVault.owner() == deployer, "OrderVault owner mismatch");

        // Check AVS Service Manager
        require(address(avsServiceManager) != address(0), "AVS Service Manager not deployed");
        require(avsServiceManager.owner() == deployer, "AVS Service Manager owner mismatch");



        // Check Hook
        require(address(eigenVaultHook) != address(0), "Hook not deployed");
        require(eigenVaultHook.owner() == deployer, "Hook owner mismatch");
        require(eigenVaultHook.orderVault() == address(orderVault), "Hook orderVault mismatch");
        require(eigenVaultHook.avsServiceManager() == address(avsServiceManager), "Hook avsServiceManager mismatch");

        console2.log("Deployment verification successful!");
    }

    // ============ Configuration Functions ============

    /// @notice Set pool manager address in hook
    /// @param poolManager The pool manager address
    function setPoolManager(address poolManager) external {
        vm.startBroadcast(deployerPrivateKey);
        
        // Note: This would require the hook to have a setter function
        // For now, we'll just log the intended configuration
        console2.log("Pool Manager should be set to:", poolManager);
        console2.log("Note: Update the hook constructor or add a setter function");
        
        vm.stopBroadcast();
    }

    /// @notice Register test operators
    /// @param operators Array of operator addresses
    function registerTestOperators(address[] calldata operators) external {
        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < operators.length; i++) {
            // Send ETH to cover stake
            (bool success, ) = address(avsServiceManager).call{value: 32 ether}("");
            require(success, "Failed to send ETH for stake");

            // Register operator
            avsServiceManager.registerOperator{value: 32 ether}(operators[i]);
            console2.log("Registered operator:", operators[i]);
        }

        vm.stopBroadcast();
    }

    /// @notice Configure pool thresholds
    /// @param poolKeys Array of pool keys
    /// @param thresholds Array of thresholds in basis points
    function configurePoolThresholds(
        bytes32[] calldata poolKeys,
        uint256[] calldata thresholds
    ) external {
        require(poolKeys.length == thresholds.length, "Array length mismatch");

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < poolKeys.length; i++) {
            eigenVaultHook.setPoolThreshold(poolKeys[i], thresholds[i]);
            console2.log("Set threshold for pool", poolKeys[i], "to", thresholds[i], "bps");
        }

        vm.stopBroadcast();
    }



    // ============ Testing Functions ============

    /// @notice Create test order matching task
    /// @param orderId The order ID
    /// @param poolId The pool ID
    /// @param ordersHash The orders hash
    function createTestTask(
        bytes32 orderId,
        bytes32 poolId,
        bytes32 ordersHash
    ) external {
        vm.startBroadcast(deployerPrivateKey);

        uint32 taskIndex = avsServiceManager.createMatchingTask(orderId, poolId, ordersHash);
        console2.log("Created test task:", taskIndex);

        vm.stopBroadcast();
    }



    /// @notice Get deployment info
    function getDeploymentInfo() external view returns (
        address orderVaultAddr,
        address avsServiceManagerAddr,

        address eigenVaultHookAddr,
        address deployerAddr
    ) {
        return (
            address(orderVault),
            address(avsServiceManager),

            address(eigenVaultHook),
            deployer
        );
    }
} 